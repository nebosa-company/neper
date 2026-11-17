// R DRDID 1.4.1: difference-in-differences with panel or repeated cross-section data. Every estimator returns the ATT, the influence function, the
// analytic standard error and 95% limits, or the multiplier / weighted bootstrap draws with the IQR based standard error and the sup-t style critical value,
// all as R computes them. Kinds: panel 0 reg_did_panel, 1 ipw_did_panel, 2 std_ipw_did_panel, 3 drdid_panel, 4 drdid_imp_panel, 5 twfe_did_panel;
// repeated cross-sections 10 reg_did_rc, 11 ipw_did_rc, 12 std_ipw_did_rc, 13 drdid_rc, 14 drdid_rc1, 15 drdid_imp_rc, 16 drdid_imp_rc1, 17 twfe_did_rc.
// The propensity score is fastglm's logistic IRLS (tolerance 1e-8 on the deviance, which is why its iterates are reproduced step for step), the improved
// variants fit the inverse-probability-tilting score with trust::trust.
//
// Not here: the secondary nlm fit pscore.cal falls back on when trust does not verify (the result is NaN then), the range-repair paths of the IPT loss for
// weights outside [1e-50, 1e50], zero sampling weights, and the formula / data frame preprocessing of drdid, ipwdid and ordid (kind_drdid, kind_ipwdid and kind_ordid give the kind they dispatch to).

use e.algo.rand.r as rng
use e.algo.rand.rdist as rdist
use e.algo.stat.carlmtest as ols
use e.algo.stat.classint as ci
use e.algo.stat.pwr as pwr
use e.algo.linalg.lapack_syevr as syevr
use e.math
use e.math.dist as dist
use e.mem

type Data = struct { n: usize, p: usize, y: []const f64, post: []const f64, d: []const f64, x: []const f64 }

type Res = struct { att: f64, se: f64, lci: f64, uci: f64, inf: []f64, boots: []f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn fin(v: f64) -> bool { ret v - v == 0.0f64 }

fn vec(a: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret v }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v
}

fn meanv(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    ret s / f64(v.len)
}

// sum_i v_i x_i / n, R's as.vector(crossprod(v, X)) / n
fn xbar(a: *mem.Arena, v: []const f64, x: []const f64, n: usize, p: usize) -> []f64 {
    let o = vec(a, p)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            o[j] += v[i] * x[i * p + j]
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < p {
        o[j] = o[j] / f64(n)
        j += 1usize
    }
    ret o
}

fn xdot(x: []const f64, i: usize, p: usize, g: []const f64) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < p {
        s += x[i * p + j] * g[j]
        j += 1usize
    }
    ret s
}

// weighted least squares of y on the p columns of x with row weights wm (a zero weight leaves the row out): normal equations, false when singular
fn wls(a: *mem.Arena, x: []const f64, y: []const f64, wm: []const f64, n: usize, p: usize, beta: []f64) -> bool {
    let xtx = vec(a, p * p)
    let inv = vec(a, p * p)
    let xty = vec(a, p)
    var i = 0usize
    while i < n {
        if wm[i] != 0.0f64 {
            var u = 0usize
            while u < p {
                xty[u] += wm[i] * x[i * p + u] * y[i]
                var v = 0usize
                while v < p {
                    xtx[u * p + v] += wm[i] * x[i * p + u] * x[i * p + v]
                    v += 1usize
                }
                u += 1usize
            }
        }
        i += 1usize
    }
    if ols.inverse(a, xtx, p, inv) != ok { ret false }
    var u = 0usize
    while u < p {
        var s = 0.0f64
        var v = 0usize
        while v < p {
            s += inv[u * p + v] * xty[v]
            v += 1usize
        }
        beta[u] = s
        u += 1usize
    }
    ret true
}

// the fitted values x beta of the weighted regression
fn fit_out(a: *mem.Arena, x: []const f64, y: []const f64, wm: []const f64, n: usize, p: usize, out: []f64) -> bool {
    let beta = vec(a, p)
    if !wls(a, x, y, wm, n, p, beta) { ret false }
    var i = 0usize
    while i < n {
        out[i] = xdot(x, i, p, beta)
        i += 1usize
    }
    ret true
}

fn logit_inv(eta: f64) -> f64 {
    var t = 0.0f64
    if eta < 0.0f64 - 30.0f64 {
        t = 2.220446049250313e-16f64
    } else if eta > 30.0f64 {
        t = 1.0f64 / 2.220446049250313e-16f64
    } else {
        t = math.exp[f64](eta)
    }
    ret t / (1.0f64 + t)
}

fn logit_dev(d: []const f64, mu: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < d.len {
        var t = 0.0f64
        if d[i] != 0.0f64 { t = math.log[f64](d[i] / mu[i]) }
        if 1.0f64 - d[i] != 0.0f64 { t += (1.0f64 - d[i]) * math.log[f64]((1.0f64 - d[i]) / (1.0f64 - mu[i])) }
        s += 2.0f64 * w[i] * t
        i += 1usize
    }
    ret s
}

fn logit_valid(mu: []const f64) -> bool {
    var i = 0usize
    while i < mu.len {
        if !fin(mu[i]) || mu[i] <= 0.0f64 || mu[i] >= 1.0f64 { ret false }
        i += 1usize
    }
    ret true
}

// fastglm::fastglmPure(x, d, binomial(), w, method = 3, tol = 1e-8, maxit = 100): the coefficients and the fitted probabilities
fn glm_logit(a: *mem.Arena, x: []const f64, d: []const f64, w: []const f64, n: usize, p: usize, beta: []f64, mu: []f64) -> bool {
    let eta = vec(a, n)
    let bprev = vec(a, p)
    let xtx = vec(a, p * p)
    let inv = vec(a, p * p)
    let xtz = vec(a, p)
    let tol = 1.0e-8f64
    let maxit = 100usize
    var i = 0usize
    while i < n {
        let m0 = (w[i] * d[i] + 0.5f64) / (w[i] + 1.0f64)
        eta[i] = math.log[f64](m0 / (1.0f64 - m0))
        mu[i] = logit_inv(eta[i])
        i += 1usize
    }
    var j = 0usize
    while j < p {
        beta[j] = 0.0f64
        j += 1usize
    }
    var dev = logit_dev(d, mu, w)
    var devold = dev
    var it = 0usize
    while it < maxit {
        j = 0usize
        while j < p * p {
            xtx[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < p {
            xtz[j] = 0.0f64
            j += 1usize
        }
        i = 0usize
        while i < n {
            var me = 2.220446049250313e-16f64
            if !(eta[i] > 30.0f64 || eta[i] < 0.0f64 - 30.0f64) {
                let ee = math.exp[f64](eta[i])
                me = ee / ((1.0f64 + ee) * (1.0f64 + ee))
            }
            let z = eta[i] + (d[i] - mu[i]) / me
            let ww = w[i] * me * me / (mu[i] * (1.0f64 - mu[i]))
            var u = 0usize
            while u < p {
                xtz[u] += ww * z * x[i * p + u]
                var v = 0usize
                while v < p {
                    xtx[u * p + v] += ww * x[i * p + u] * x[i * p + v]
                    v += 1usize
                }
                u += 1usize
            }
            i += 1usize
        }
        if ols.inverse(a, xtx, p, inv) != ok { ret false }
        j = 0usize
        while j < p {
            bprev[j] = beta[j]
            var s = 0.0f64
            var v = 0usize
            while v < p {
                s += inv[j * p + v] * xtz[v]
                v += 1usize
            }
            beta[j] = s
            j += 1usize
        }
        i = 0usize
        while i < n {
            eta[i] = xdot(x, i, p, beta)
            mu[i] = logit_inv(eta[i])
            i += 1usize
        }
        devold = dev
        dev = logit_dev(d, mu, w)
        var halves = 0usize
        while !fin(dev) {
            halves += 1usize
            if halves > maxit { break }
            glm_halve(x, n, p, beta, bprev, eta, mu)
            dev = logit_dev(d, mu, w)
        }
        halves = 0usize
        while !logit_valid(mu) {
            halves += 1usize
            if halves > maxit { break }
            glm_halve(x, n, p, beta, bprev, eta, mu)
        }
        if halves > 0usize { dev = logit_dev(d, mu, w) }
        if (dev - devold) / (0.1f64 + math.abs[f64](dev)) >= tol && it > 0usize {
            halves = 0usize
            while (dev - devold) / (0.1f64 + math.abs[f64](dev)) >= 0.0f64 - tol {
                halves += 1usize
                if halves > maxit { break }
                glm_halve(x, n, p, beta, bprev, eta, mu)
                dev = logit_dev(d, mu, w)
            }
        }
        if !fin(dev) && it == 0usize { ret false }
        if math.abs[f64](dev - devold) / (0.1f64 + math.abs[f64](dev)) < tol { ret true }
        it += 1usize
    }
    ret false
}

fn glm_halve(x: []const f64, n: usize, p: usize, beta: []f64, bprev: []const f64, eta: []f64, mu: []f64) {
    var j = 0usize
    while j < p {
        beta[j] = 0.5f64 * (beta[j] + bprev[j])
        j += 1usize
    }
    var i = 0usize
    while i < n {
        eta[i] = xdot(x, i, p, beta)
        mu[i] = logit_inv(eta[i])
        i += 1usize
    }
}

// the Hessian of the propensity score likelihood, n * (X' diag(wps) X)^-1
fn hess_ps(a: *mem.Arena, x: []const f64, wps: []const f64, n: usize, p: usize) -> []f64 {
    let m = vec(a, p * p)
    let h = vec(a, p * p)
    var i = 0usize
    while i < n {
        var u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                m[u * p + v] += wps[i] * x[i * p + u] * x[i * p + v]
                v += 1usize
            }
            u += 1usize
        }
        i += 1usize
    }
    if ols.inverse(a, m, p, h) != ok { ret vec(a, 0usize) }
    var k = 0usize
    while k < p * p {
        h[k] = h[k] * f64(n)
        k += 1usize
    }
    ret h
}

// out_i += sign * olsw_i * res_i * x_i (X' diag(olsw) X / n)^-1 m: the weighted OLS influence function times m
fn lin_ols(a: *mem.Arena, out: []f64, sign: f64, olsw: []const f64, res: []const f64, x: []const f64, n: usize, p: usize, m: []const f64) -> bool {
    let xtx = vec(a, p * p)
    let inv = vec(a, p * p)
    var i = 0usize
    while i < n {
        var u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                xtx[u * p + v] += olsw[i] * x[i * p + u] * x[i * p + v] / f64(n)
                v += 1usize
            }
            u += 1usize
        }
        i += 1usize
    }
    if ols.inverse(a, xtx, p, inv) != ok { ret false }
    let g = vec(a, p)
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            g[u] += inv[u * p + v] * m[v]
            v += 1usize
        }
        u += 1usize
    }
    i = 0usize
    while i < n {
        out[i] += sign * olsw[i] * res[i] * xdot(x, i, p, g)
        i += 1usize
    }
    ret true
}

// out_i += sign * score_i x_i H m: the propensity score influence function times m
fn lin_ps(a: *mem.Arena, out: []f64, sign: f64, score: []const f64, h: []const f64, x: []const f64, n: usize, p: usize, m: []const f64) {
    let g = vec(a, p)
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            g[u] += h[u * p + v] * m[v]
            v += 1usize
        }
        u += 1usize
    }
    var i = 0usize
    while i < n {
        out[i] += sign * score[i] * xdot(x, i, p, g)
        i += 1usize
    }
}

type IptCtx = struct { x: []const f64, d: []const f64, w: []const f64, n: usize, p: usize, val: f64, grad: []f64, hess: []f64 }

// loss.ps.cal: the value, gradient and Hessian of the calibrated propensity score loss
fn ipt_eval(c: *IptCtx, gam: []const f64) {
    let n = c.n
    let p = c.p
    var v = 0.0f64
    var u = 0usize
    while u < p {
        c.grad[u] = 0.0f64
        var k = 0usize
        while k < p {
            c.hess[u * p + k] = 0.0f64
            k += 1usize
        }
        u += 1usize
    }
    var i = 0usize
    while i < n {
        let idx = xdot(c.x, i, p, gam)
        var ex = 0.0f64
        if c.d[i] == 0.0f64 { ex = math.exp[f64](idx) }
        var t = 0.0f64 - ex
        var gt = 0.0f64 - ex
        if c.d[i] != 0.0f64 {
            t = idx
            gt = 1.0f64
        }
        v += t * c.w[i]
        u = 0usize
        while u < p {
            c.grad[u] += gt * c.w[i] * c.x[i * p + u]
            if c.d[i] == 0.0f64 {
                var k = 0usize
                while k < p {
                    c.hess[u * p + k] += ex * c.w[i] * c.x[i * p + u] * c.x[i * p + k]
                    k += 1usize
                }
            }
            u += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    c.val = 0.0f64 - v / nf
    u = 0usize
    while u < p {
        c.grad[u] = 0.0f64 - c.grad[u] / nf
        var k = 0usize
        while k < p {
            c.hess[u * p + k] = c.hess[u * p + k] / nf
            k += 1usize
        }
        u += 1usize
    }
}

type TrustFred = struct { gq: []const f64, beta: []const f64, r: f64, c1: f64, c2: f64 }

fn trust_fred(c: *TrustFred, beep: f64) -> f64 {
    if beep == 0.0f64 {
        if c.c2 > 0.0f64 { ret 0.0f64 - 1.0f64 / c.r }
        ret math.sqrt[f64](1.0f64 / c.c1) - 1.0f64 / c.r
    }
    var s = 0.0f64
    var i = 0usize
    while i < c.gq.len {
        let q = c.gq[i] / (c.beta[i] + beep)
        s += q * q
        i += 1usize
    }
    ret math.sqrt[f64](1.0f64 / s) - 1.0f64 / c.r
}

// trust::trust(loss.ps.cal, parinit, rinit = 1, rmax = 1000, iterlim = 1000) on the IPT loss; the minimiser in theta
fn trust_ipt(a: *mem.Arena, c: *IptCtx, theta: []f64) -> bool {
    let p = c.p
    let fterm = 1.4901161193847656e-08f64
    let rmax = 1000.0f64
    var r = 1.0f64
    ipt_eval(c, theta)
    if !fin(c.val) { ret false }
    var f = c.val
    let g = vec(a, p)
    let bm = vec(a, p * p)
    let tt = vec(a, p)
    let ptry = vec(a, p)
    let gq = vec(a, p)
    let vals = vec(a, p)
    let vecs = vec(a, p * p)
    let w1 = vec(a, p)
    let z1 = vec(a, p * p)
    let sym = vec(a, p * p)
    var accept = true
    var it = 0usize
    while it < 1000usize {
        if accept {
            f = c.val
            var u = 0usize
            while u < p {
                g[u] = c.grad[u]
                var k = 0usize
                while k < p {
                    bm[u * p + k] = c.hess[u * p + k]
                    sym[k * p + u] = c.hess[u * p + k]
                    k += 1usize
                }
                u += 1usize
            }
            if syevr.dsyevr_all(a, sym, p, w1, z1) != ok { ret false }
            // R lists the eigenvalues decreasing; vecs[u * p + k] is component u of vector k
            k_loop(p, w1, z1, vals, vecs)
            u = 0usize
            while u < p {
                var s = 0.0f64
                var k = 0usize
                while k < p {
                    s += vecs[k * p + u] * g[k]
                    k += 1usize
                }
                gq[u] = s
                u += 1usize
            }
        }
        var is_newton = false
        var allpos = true
        var u = 0usize
        while u < p {
            if !(vals[u] > 0.0f64) { allpos = false }
            u += 1usize
        }
        if allpos {
            var nrm = 0.0f64
            u = 0usize
            while u < p {
                var s = 0.0f64
                var k = 0usize
                while k < p {
                    s += vecs[u * p + k] * gq[k] / vals[k]
                    k += 1usize
                }
                ptry[u] = 0.0f64 - s
                nrm += s * s
                u += 1usize
            }
            if math.sqrt[f64](nrm) <= r { is_newton = true }
        }
        if !is_newton {
            var lmin = vals[0usize]
            u = 1usize
            while u < p {
                if vals[u] < lmin { lmin = vals[u] }
                u += 1usize
            }
            let bt = vec(a, p)
            var c1 = 0.0f64
            var c2 = 0.0f64
            var c3 = 0.0f64
            var imin = p
            u = 0usize
            while u < p {
                bt[u] = vals[u] - lmin
                c3 += gq[u] * gq[u]
                if bt[u] == 0.0f64 {
                    c2 += gq[u] * gq[u]
                    if imin == p { imin = u }
                } else {
                    let q = gq[u] / bt[u]
                    c1 += q * q
                }
                u += 1usize
            }
            let wtry = vec(a, p)
            if c2 > 0.0f64 || c1 > r * r {
                var fc: TrustFred = zero
                fc.gq = gq
                fc.beta = bt
                fc.r = r
                fc.c1 = c1
                fc.c2 = c2
                let bdn = math.sqrt[f64](c2) / r
                let bup = math.sqrt[f64](c3) / r
                var root = 0.0f64
                if trust_fred(&fc, bup) <= 0.0f64 {
                    root = bup
                } else if trust_fred(&fc, bdn) >= 0.0f64 {
                    root = bdn
                } else {
                    root = pwr.zeroin[TrustFred](&fc, trust_fred, bdn, bup, math.pow[f64](2.220446049250313e-16f64, 0.25f64), 1000i64)
                }
                u = 0usize
                while u < p {
                    wtry[u] = gq[u] / (bt[u] + root)
                    u += 1usize
                }
                u = 0usize
                while u < p {
                    var s = 0.0f64
                    var k = 0usize
                    while k < p {
                        s += vecs[u * p + k] * wtry[k]
                        k += 1usize
                    }
                    ptry[u] = 0.0f64 - s
                    u += 1usize
                }
            } else {
                u = 0usize
                while u < p {
                    if bt[u] != 0.0f64 { wtry[u] = gq[u] / bt[u] }
                    u += 1usize
                }
                var pn = 0.0f64
                u = 0usize
                while u < p {
                    var s = 0.0f64
                    var k = 0usize
                    while k < p {
                        s += vecs[u * p + k] * wtry[k]
                        k += 1usize
                    }
                    ptry[u] = 0.0f64 - s
                    pn += s * s
                    u += 1usize
                }
                let utry2 = r * r - pn
                if utry2 > 0.0f64 {
                    let utry = math.sqrt[f64](utry2)
                    u = 0usize
                    while u < p {
                        ptry[u] += utry * vecs[u * p + imin]
                        u += 1usize
                    }
                }
            }
        }
        var pred = 0.0f64
        u = 0usize
        while u < p {
            var bp = 0.0f64
            var k = 0usize
            while k < p {
                bp += bm[u * p + k] * ptry[k]
                k += 1usize
            }
            pred += ptry[u] * (g[u] + bp / 2.0f64)
            tt[u] = theta[u] + ptry[u]
            u += 1usize
        }
        ipt_eval(c, tt)
        let ftry = c.val
        var rho = (ftry - f) / pred
        var term = false
        if ftry < 1.0e308f64 {
            term = math.abs[f64](ftry - f) < fterm || math.abs[f64](pred) < fterm
        } else {
            rho = 0.0f64 - 1.0e308f64
        }
        if term {
            if ftry < f {
                accept = true
                u = 0usize
                while u < p {
                    theta[u] = tt[u]
                    u += 1usize
                }
            }
        } else {
            if rho < 0.25f64 {
                accept = false
                r = r / 4.0f64
            } else {
                accept = true
                u = 0usize
                while u < p {
                    theta[u] = tt[u]
                    u += 1usize
                }
                if rho > 0.75f64 && !is_newton {
                    r = 2.0f64 * r
                    if r > rmax { r = rmax }
                }
            }
        }
        if term { ret true }
        it += 1usize
    }
    ret false
}

// the eigenpairs in R's decreasing order: vecs[u * p + k] is component u of eigenvector k
fn k_loop(p: usize, w1: []const f64, z1: []const f64, vals: []f64, vecs: []f64) {
    var k = 0usize
    while k < p {
        let src = p - 1usize - k
        vals[k] = w1[src]
        var u = 0usize
        while u < p {
            vecs[u * p + k] = z1[src * p + u]
            u += 1usize
        }
        k += 1usize
    }
}

// ipt.valid reduced to its Newton decrement and index step tests at tolerance 1e-6
fn ipt_valid(a: *mem.Arena, c: *IptCtx, gam: []const f64) -> bool {
    let p = c.p
    let n = c.n
    let g = vec(a, p)
    let h = vec(a, p * p)
    let hi = vec(a, p * p)
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        var mass = c.w[i]
        var sg = 1.0f64
        if c.d[i] == 0.0f64 {
            mass = c.w[i] * math.exp[f64](xdot(c.x, i, p, gam))
            sg = 0.0f64 - 1.0f64
        }
        tot += mass
        var u = 0usize
        while u < p {
            g[u] += sg * mass * c.x[i * p + u]
            if c.d[i] == 0.0f64 {
                var k = 0usize
                while k < p {
                    h[u * p + k] += mass * c.x[i * p + u] * c.x[i * p + k]
                    k += 1usize
                }
            }
            u += 1usize
        }
        i += 1usize
    }
    if ols.inverse(a, h, p, hi) != ok { ret false }
    let dl = vec(a, p)
    var q = 0.0f64
    var u = 0usize
    while u < p {
        var k = 0usize
        while k < p {
            dl[u] += hi[u * p + k] * g[k]
            k += 1usize
        }
        q += dl[u] * g[u]
        u += 1usize
    }
    if !(math.sqrt[f64](q / tot) <= 1.0e-6f64) { ret false }
    var mx = 0.0f64
    i = 0usize
    while i < n {
        let s = math.abs[f64](xdot(c.x, i, p, dl))
        if s > mx { mx = s }
        i += 1usize
    }
    ret mx <= 1.0e-6f64
}

// the propensity score of the traditional (logit by fastglm) or improved (IPT by trust) estimators, clipped at 1 - 1e-6, and the trimming indicator
fn ps_est(a: *mem.Arena, imp: bool, dt: *const Data, w: []const f64, tl: f64, ps: []f64, trim: []f64, coef: []f64) -> bool {
    let n = dt.n
    let p = dt.p
    if !imp {
        if !glm_logit(a, dt.x, dt.d, w, n, p, coef, ps) { ret false }
    } else {
        let fw = vec(a, n)
        let mw = meanv(w)
        var i = 0usize
        while i < n {
            fw[i] = w[i] / mw
            i += 1usize
        }
        let g0 = vec(a, p)
        let mu0 = vec(a, n)
        if !glm_logit(a, dt.x, dt.d, fw, n, p, g0, mu0) {
            var j = 0usize
            while j < p {
                g0[j] = 0.0f64
                j += 1usize
            }
        }
        var c: IptCtx = zero
        c.x = dt.x
        c.d = dt.d
        c.w = fw
        c.n = n
        c.p = p
        c.grad = vec(a, p)
        c.hess = vec(a, p * p)
        if !trust_ipt(a, &c, g0) { ret false }
        if !ipt_valid(a, &c, g0) { ret false }
        i = 0usize
        while i < n {
            ps[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - xdot(dt.x, i, p, g0)))
            if !fin(ps[i]) { ret false }
            i += 1usize
        }
    }
    var i = 0usize
    while i < n {
        if ps[i] > 1.0f64 - 1.0e-6f64 { ps[i] = 1.0f64 - 1.0e-6f64 }
        trim[i] = 1.0f64
        if dt.d[i] == 0.0f64 && !(ps[i] < tl) { trim[i] = 0.0f64 }
        i += 1usize
    }
    ret true
}

fn prod3(a: *mem.Arena, u: []const f64, v: []const f64, w: []const f64) -> []f64 {
    let o = vec(a, u.len)
    var i = 0usize
    while i < u.len {
        o[i] = u[i] * v[i] * w[i]
        i += 1usize
    }
    ret o
}

fn est_panel(a: *mem.Arena, kind: u8, dt: *const Data, w: []const f64, tl: f64, inf: []f64, want: bool) -> f64 {
    let n = dt.n
    let p = dt.p
    let nf = f64(n)
    let dy = dt.y
    let d = dt.d
    let x = dt.x
    let ps = vec(a, n)
    let tr = vec(a, n)
    let out = vec(a, n)
    let cw = vec(a, n)
    let coef = vec(a, p)
    var i = 0usize
    while i < n {
        cw[i] = w[i] * (1.0f64 - d[i])
        i += 1usize
    }
    if kind != 0u8 {
        if !ps_est(a, kind == 4u8, dt, w, tl, ps, tr, coef) { ret nan() }
    }
    if kind == 0u8 || kind == 3u8 {
        if !fit_out(a, x, dy, cw, n, p, out) { ret nan() }
    }
    if kind == 4u8 {
        let ow = vec(a, n)
        i = 0usize
        while i < n {
            ow[i] = cw[i] * ps[i] / (1.0f64 - ps[i])
            i += 1usize
        }
        if !fit_out(a, x, dy, ow, n, p, out) { ret nan() }
    }
    let wd = vec(a, n)
    let wt = vec(a, n)
    let wc = vec(a, n)
    i = 0usize
    while i < n {
        wd[i] = w[i] * d[i]
        wt[i] = tr[i] * w[i] * d[i]
        wc[i] = tr[i] * w[i] * ps[i] * (1.0f64 - d[i]) / (1.0f64 - ps[i])
        i += 1usize
    }
    if kind == 0u8 {
        let mw = meanv(wd)
        var s1 = 0.0f64
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            s1 += wd[i] * dy[i]
            s2 += wd[i] * out[i]
            i += 1usize
        }
        let eta_t = s1 / nf / mw
        let eta_c = s2 / nf / mw
        if !want { ret eta_t - eta_c }
        let res = vec(a, n)
        let m1 = xbar(a, wd, x, n, p)
        i = 0usize
        while i < n {
            res[i] = dy[i] - out[i]
            inf[i] = (wd[i] * dy[i] - wd[i] * eta_t) / mw - (wd[i] * out[i] - wd[i] * eta_c) / mw
            i += 1usize
        }
        if !lin_ols(a, inf, 0.0f64 - 1.0f64 / mw, cw, res, x, n, p, m1) { ret nan() }
        ret eta_t - eta_c
    }
    // the propensity score score and information
    let sc = vec(a, n)
    let wps = vec(a, n)
    i = 0usize
    while i < n {
        sc[i] = w[i] * (d[i] - ps[i])
        wps[i] = ps[i] * (1.0f64 - ps[i]) * w[i]
        i += 1usize
    }
    if kind == 4u8 {
        var num = 0.0f64
        let smm = vec(a, n)
        i = 0usize
        while i < n {
            smm[i] = tr[i] * (1.0f64 - (1.0f64 - d[i]) / (1.0f64 - ps[i])) * (dy[i] - out[i])
            num += w[i] * smm[i]
            i += 1usize
        }
        let md = meanv(wd)
        let att = num / nf / md
        if want {
            i = 0usize
            while i < n {
                inf[i] = w[i] * tr[i] * (smm[i] - d[i] * att) / md
                i += 1usize
            }
        }
        ret att
    }
    if kind == 1u8 {
        let at = vec(a, n)
        let ac = vec(a, n)
        i = 0usize
        while i < n {
            at[i] = wt[i] * dy[i]
            ac[i] = wc[i] * dy[i]
            i += 1usize
        }
        let md = meanv(wd)
        let att = meanv(at) / md - meanv(ac) / md
        if !want { ret att }
        let h = hess_ps(a, x, wps, n, p)
        if h.len == 0usize { ret nan() }
        let mom = xbar(a, ac, x, n, p)
        i = 0usize
        while i < n {
            inf[i] = (at[i] - ac[i] - wd[i] * att) / md
            i += 1usize
        }
        lin_ps(a, inf, 0.0f64 - 1.0f64 / md, sc, h, x, n, p, mom)
        ret att
    }
    let mwt = meanv(wt)
    let mwc = meanv(wc)
    if kind == 2u8 {
        let at = vec(a, n)
        let ac = vec(a, n)
        i = 0usize
        while i < n {
            at[i] = wt[i] * dy[i]
            ac[i] = wc[i] * dy[i]
            i += 1usize
        }
        let eta_t = meanv(at) / mwt
        let eta_c = meanv(ac) / mwc
        if !want { ret eta_t - eta_c }
        let h = hess_ps(a, x, wps, n, p)
        if h.len == 0usize { ret nan() }
        let r2 = vec(a, n)
        i = 0usize
        while i < n {
            r2[i] = wc[i] * (dy[i] - eta_c)
            inf[i] = (at[i] - wt[i] * eta_t) / mwt - (ac[i] - wc[i] * eta_c) / mwc
            i += 1usize
        }
        let m2 = xbar(a, r2, x, n, p)
        lin_ps(a, inf, 0.0f64 - 1.0f64 / mwc, sc, h, x, n, p, m2)
        ret eta_t - eta_c
    }
    // kind 3, drdid_panel
    let dat = vec(a, n)
    let dac = vec(a, n)
    i = 0usize
    while i < n {
        dat[i] = wt[i] * (dy[i] - out[i])
        dac[i] = wc[i] * (dy[i] - out[i])
        i += 1usize
    }
    let eta_t = meanv(dat) / mwt
    let eta_c = meanv(dac) / mwc
    if !want { ret eta_t - eta_c }
    let h = hess_ps(a, x, wps, n, p)
    if h.len == 0usize { ret nan() }
    let res = vec(a, n)
    let r2 = vec(a, n)
    i = 0usize
    while i < n {
        res[i] = dy[i] - out[i]
        r2[i] = wc[i] * (dy[i] - out[i] - eta_c)
        inf[i] = (dat[i] - wt[i] * eta_t) / mwt - (dac[i] - wc[i] * eta_c) / mwc
        i += 1usize
    }
    let m1 = xbar(a, wt, x, n, p)
    let m2 = xbar(a, r2, x, n, p)
    let m3 = xbar(a, wc, x, n, p)
    if !lin_ols(a, inf, 0.0f64 - 1.0f64 / mwt, cw, res, x, n, p, m1) { ret nan() }
    lin_ps(a, inf, 0.0f64 - 1.0f64 / mwc, sc, h, x, n, p, m2)
    if !lin_ols(a, inf, 1.0f64 / mwc, cw, res, x, n, p, m3) { ret nan() }
    ret eta_t - eta_c
}

fn est_rc(a: *mem.Arena, kind: u8, dt: *const Data, w: []const f64, tl: f64, inf: []f64, want: bool) -> f64 {
    let n = dt.n
    let p = dt.p
    let nf = f64(n)
    let y = dt.y
    let post = dt.post
    let d = dt.d
    let x = dt.x
    let ps = vec(a, n)
    let tr = vec(a, n)
    let coef = vec(a, p)
    let gpc = vec(a, n)
    let gqc = vec(a, n)
    let wtp = vec(a, n)
    let wtq = vec(a, n)
    let wd = vec(a, n)
    var i = 0usize
    while i < n {
        gpc[i] = w[i] * (1.0f64 - d[i]) * (1.0f64 - post[i])
        gqc[i] = w[i] * (1.0f64 - d[i]) * post[i]
        wtp[i] = w[i] * d[i] * (1.0f64 - post[i])
        wtq[i] = w[i] * d[i] * post[i]
        wd[i] = w[i] * d[i]
        i += 1usize
    }
    if kind != 10u8 {
        if !ps_est(a, kind >= 15u8, dt, w, tl, ps, tr, coef) { ret nan() }
    }
    let sc = vec(a, n)
    let wps = vec(a, n)
    let wcp = vec(a, n)
    let wcq = vec(a, n)
    i = 0usize
    while i < n {
        sc[i] = w[i] * (d[i] - ps[i])
        wps[i] = ps[i] * (1.0f64 - ps[i]) * w[i]
        wcp[i] = tr[i] * w[i] * ps[i] * (1.0f64 - d[i]) * (1.0f64 - post[i]) / (1.0f64 - ps[i])
        wcq[i] = tr[i] * w[i] * ps[i] * (1.0f64 - d[i]) * post[i] / (1.0f64 - ps[i])
        i += 1usize
    }
    let cpre = vec(a, n)
    let cpost = vec(a, n)
    if kind >= 15u8 {
        let ocp = vec(a, n)
        let ocq = vec(a, n)
        i = 0usize
        while i < n {
            ocp[i] = gpc[i] * ps[i] / (1.0f64 - ps[i])
            ocq[i] = gqc[i] * ps[i] / (1.0f64 - ps[i])
            i += 1usize
        }
        if !fit_out(a, x, y, ocp, n, p, cpre) { ret nan() }
        if !fit_out(a, x, y, ocq, n, p, cpost) { ret nan() }
    } else {
        if !fit_out(a, x, y, gpc, n, p, cpre) { ret nan() }
        if !fit_out(a, x, y, gqc, n, p, cpost) { ret nan() }
    }
    let mtp = meanv(wtp)
    let mtq = meanv(wtq)
    if kind == 10u8 {
        let mc = meanv(wd)
        var s1 = 0.0f64
        var s2 = 0.0f64
        var s3 = 0.0f64
        i = 0usize
        while i < n {
            s1 += wtp[i] * y[i]
            s2 += wtq[i] * y[i]
            s3 += wd[i] * (cpost[i] - cpre[i])
            i += 1usize
        }
        let e_tp = s1 / nf / mtp
        let e_tq = s2 / nf / mtq
        let e_c = s3 / nf / mc
        let att = (e_tq - e_tp) - e_c
        if !want { ret att }
        let rp = vec(a, n)
        let rq = vec(a, n)
        i = 0usize
        while i < n {
            rp[i] = y[i] - cpre[i]
            rq[i] = y[i] - cpost[i]
            inf[i] = (wtq[i] * y[i] - wtq[i] * e_tq) / mtq - (wtp[i] * y[i] - wtp[i] * e_tp) / mtp - (wd[i] * (cpost[i] - cpre[i]) - wd[i] * e_c) / mc
            i += 1usize
        }
        let m1 = xbar(a, wd, x, n, p)
        if !lin_ols(a, inf, 0.0f64 - 1.0f64 / mc, gqc, rq, x, n, p, m1) { ret nan() }
        if !lin_ols(a, inf, 1.0f64 / mc, gpc, rp, x, n, p, m1) { ret nan() }
        ret att
    }
    if kind == 11u8 {
        // w.treat carries no trimming here, as in ipw_did_rc
        let pi_h = meanv(wd)
        var lam = 0.0f64
        var oml = 0.0f64
        i = 0usize
        while i < n {
            lam += w[i] * post[i] / nf
            oml += w[i] * (1.0f64 - post[i]) / nf
            i += 1usize
        }
        let e_tp = vec(a, n)
        let e_tq = vec(a, n)
        let e_cp = vec(a, n)
        let e_cq = vec(a, n)
        i = 0usize
        while i < n {
            e_tp[i] = wtp[i] * y[i] / (pi_h * oml)
            e_tq[i] = wtq[i] * y[i] / (pi_h * lam)
            e_cp[i] = wcp[i] * y[i] / (pi_h * oml)
            e_cq[i] = wcq[i] * y[i] / (pi_h * lam)
            i += 1usize
        }
        let a_tp = meanv(e_tp)
        let a_tq = meanv(e_tq)
        let a_cp = meanv(e_cp)
        let a_cq = meanv(e_cq)
        let att = (a_tq - a_tp) - (a_cq - a_cp)
        if !want { ret att }
        let h = hess_ps(a, x, wps, n, p)
        if h.len == 0usize { ret nan() }
        let nc1 = vec(a, n)
        let nc2 = vec(a, n)
        i = 0usize
        while i < n {
            nc1[i] = 0.0f64 - e_cp[i]
            nc2[i] = 0.0f64 - e_cq[i]
            let tq = (e_tq[i] - a_tq) - (w[i] * d[i] - pi_h) * a_tq / pi_h - (w[i] * post[i] - lam) * a_tq / lam
            let tp = (e_tp[i] - a_tp) - (w[i] * d[i] - pi_h) * a_tp / pi_h - (w[i] * (1.0f64 - post[i]) - oml) * a_tp / oml
            let cq = (e_cq[i] - a_cq) - (w[i] * d[i] - pi_h) * a_cq / pi_h - (w[i] * post[i] - lam) * a_cq / lam
            let cp = (e_cp[i] - a_cp) - (w[i] * d[i] - pi_h) * a_cp / pi_h - (w[i] * (1.0f64 - post[i]) - oml) * a_cp / oml
            inf[i] = (tq - tp) - (cq - cp) + att * (w[i] - 1.0f64)
            i += 1usize
        }
        let mp = xbar(a, nc1, x, n, p)
        let mq = xbar(a, nc2, x, n, p)
        let md = vec(a, p)
        var u = 0usize
        while u < p {
            md[u] = mq[u] - mp[u]
            u += 1usize
        }
        lin_ps(a, inf, 1.0f64, sc, h, x, n, p, md)
        ret att
    }
    let wcpm = meanv(wcp)
    let wcqm = meanv(wcq)
    if kind == 12u8 {
        let e_tp = vec(a, n)
        let e_tq = vec(a, n)
        let e_cp = vec(a, n)
        let e_cq = vec(a, n)
        i = 0usize
        while i < n {
            e_tp[i] = wtp[i] * y[i] / mtp
            e_tq[i] = wtq[i] * y[i] / mtq
            e_cp[i] = wcp[i] * y[i] / wcpm
            e_cq[i] = wcq[i] * y[i] / wcqm
            i += 1usize
        }
        let a_tp = meanv(e_tp)
        let a_tq = meanv(e_tq)
        let a_cp = meanv(e_cp)
        let a_cq = meanv(e_cq)
        let att = (a_tq - a_tp) - (a_cq - a_cp)
        if !want { ret att }
        let h = hess_ps(a, x, wps, n, p)
        if h.len == 0usize { ret nan() }
        let r2p = vec(a, n)
        let r2q = vec(a, n)
        i = 0usize
        while i < n {
            r2p[i] = wcp[i] * (y[i] - a_cp)
            r2q[i] = wcq[i] * (y[i] - a_cq)
            let it_t = (e_tq[i] - wtq[i] * a_tq / mtq) - (e_tp[i] - wtp[i] * a_tp / mtp)
            let it_c = (e_cq[i] - wcq[i] * a_cq / wcqm) - (e_cp[i] - wcp[i] * a_cp / wcpm)
            inf[i] = it_t - it_c
            i += 1usize
        }
        let m2p = xbar(a, r2p, x, n, p)
        let m2q = xbar(a, r2q, x, n, p)
        let md = vec(a, p)
        var u = 0usize
        while u < p {
            md[u] = m2q[u] / wcqm - m2p[u] / wcpm
            u += 1usize
        }
        lin_ps(a, inf, 0.0f64 - 1.0f64, sc, h, x, n, p, md)
        ret att
    }
    // kinds 13 to 16
    let trt = kind == 13u8 || kind == 15u8
    let fx = kind == 13u8 || kind == 14u8
    let tpre = vec(a, n)
    let tpost = vec(a, n)
    if trt {
        if !fit_out(a, x, y, wtp, n, p, tpre) { ret nan() }
        if !fit_out(a, x, y, wtq, n, p, tpost) { ret nan() }
    }
    let oc = vec(a, n)
    let e_tp = vec(a, n)
    let e_tq = vec(a, n)
    let e_cp = vec(a, n)
    let e_cq = vec(a, n)
    let e_dq = vec(a, n)
    let e_1q = vec(a, n)
    let e_dp = vec(a, n)
    let e_0p = vec(a, n)
    let mdd = meanv(wd)
    i = 0usize
    while i < n {
        oc[i] = post[i] * cpost[i] + (1.0f64 - post[i]) * cpre[i]
        e_tp[i] = wtp[i] * (y[i] - oc[i]) / mtp
        e_tq[i] = wtq[i] * (y[i] - oc[i]) / mtq
        e_cp[i] = wcp[i] * (y[i] - oc[i]) / wcpm
        e_cq[i] = wcq[i] * (y[i] - oc[i]) / wcqm
        if trt {
            e_dq[i] = wd[i] * (tpost[i] - cpost[i]) / mdd
            e_1q[i] = wtq[i] * (tpost[i] - cpost[i]) / mtq
            e_dp[i] = wd[i] * (tpre[i] - cpre[i]) / mdd
            e_0p[i] = wtp[i] * (tpre[i] - cpre[i]) / mtp
        }
        i += 1usize
    }
    let a_tp = meanv(e_tp)
    let a_tq = meanv(e_tq)
    let a_cp = meanv(e_cp)
    let a_cq = meanv(e_cq)
    var att = (a_tq - a_tp) - (a_cq - a_cp)
    var a_dq = 0.0f64
    var a_1q = 0.0f64
    var a_dp = 0.0f64
    var a_0p = 0.0f64
    if trt {
        a_dq = meanv(e_dq)
        a_1q = meanv(e_1q)
        a_dp = meanv(e_dp)
        a_0p = meanv(e_0p)
        att += (a_dq - a_1q) - (a_dp - a_0p)
    }
    if !want { ret att }
    i = 0usize
    while i < n {
        var v = (e_tq[i] - wtq[i] * a_tq / mtq) - (e_tp[i] - wtp[i] * a_tp / mtp) - ((e_cq[i] - wcq[i] * a_cq / wcqm) - (e_cp[i] - wcp[i] * a_cp / wcpm))
        if trt {
            v += ((e_dq[i] - wd[i] * a_dq / mdd) - (e_1q[i] - wtq[i] * a_1q / mtq)) - ((e_dp[i] - wd[i] * a_dp / mdd) - (e_0p[i] - wtp[i] * a_0p / mtp))
        }
        inf[i] = v
        i += 1usize
    }
    if !fx { ret att }
    let h = hess_ps(a, x, wps, n, p)
    if h.len == 0usize { ret nan() }
    let rcp = vec(a, n)
    let rcq = vec(a, n)
    let r2p = vec(a, n)
    let r2q = vec(a, n)
    i = 0usize
    while i < n {
        rcp[i] = y[i] - cpre[i]
        rcq[i] = y[i] - cpost[i]
        r2p[i] = wcp[i] * (y[i] - oc[i] - a_cp)
        r2q[i] = wcq[i] * (y[i] - oc[i] - a_cq)
        i += 1usize
    }
    let xtq = xbar(a, wtq, x, n, p)
    let xtp = xbar(a, wtp, x, n, p)
    let xcq = xbar(a, wcq, x, n, p)
    let xcp = xbar(a, wcp, x, n, p)
    let m2p = xbar(a, r2p, x, n, p)
    let m2q = xbar(a, r2q, x, n, p)
    let mt1 = vec(a, p)
    let mt0 = vec(a, p)
    let mc1 = vec(a, p)
    let mc0 = vec(a, p)
    let mps = vec(a, p)
    var u = 0usize
    while u < p {
        mt1[u] = 0.0f64 - xtq[u] / mtq
        mt0[u] = 0.0f64 - xtp[u] / mtp
        mc1[u] = 0.0f64 - xcq[u] / wcqm
        mc0[u] = 0.0f64 - xcp[u] / wcpm
        mps[u] = m2q[u] / wcqm - m2p[u] / wcpm
        u += 1usize
    }
    if !lin_ols(a, inf, 1.0f64, gqc, rcq, x, n, p, mt1) { ret nan() }
    if !lin_ols(a, inf, 0.0f64 - 1.0f64, gpc, rcp, x, n, p, mt0) { ret nan() }
    if !lin_ols(a, inf, 0.0f64 - 1.0f64, gqc, rcq, x, n, p, mc1) { ret nan() }
    if !lin_ols(a, inf, 1.0f64, gpc, rcp, x, n, p, mc0) { ret nan() }
    lin_ps(a, inf, 0.0f64 - 1.0f64, sc, h, x, n, p, mps)
    if kind == 13u8 {
        let rtp = vec(a, n)
        let rtq = vec(a, n)
        let mpo = vec(a, p)
        let mpr = vec(a, p)
        let vq = vec(a, n)
        let vp = vec(a, n)
        i = 0usize
        while i < n {
            rtp[i] = y[i] - tpre[i]
            rtq[i] = y[i] - tpost[i]
            vq[i] = wd[i] / mdd - wtq[i] / mtq
            vp[i] = wd[i] / mdd - wtp[i] / mtp
            i += 1usize
        }
        let bq = xbar(a, vq, x, n, p)
        let bp = xbar(a, vp, x, n, p)
        if !lin_ols(a, inf, 1.0f64, wtq, rtq, x, n, p, bq) { ret nan() }
        if !lin_ols(a, inf, 0.0f64 - 1.0f64, gqc, rcq, x, n, p, bq) { ret nan() }
        if !lin_ols(a, inf, 0.0f64 - 1.0f64, wtp, rtp, x, n, p, bp) { ret nan() }
        if !lin_ols(a, inf, 1.0f64, gpc, rcp, x, n, p, bp) { ret nan() }
    }
    ret att
}

// twfe_did_rc (kind 17) and twfe_did_panel with covariates (kind 5, y holds y1 and post holds y0): the weighted regression y ~ dd:post + post + dd + x
fn est_twfe(a: *mem.Arena, kind: u8, dt: *const Data, w: []const f64, inf: []f64, want: bool) -> f64 {
    let n = dt.n
    let p = dt.p
    var first = 0usize
    var ones = true
    var i = 0usize
    while i < n {
        if dt.x[i * p] != 1.0f64 { ones = false }
        i += 1usize
    }
    if ones { first = 1usize }
    let nx = p - first
    let k = 3usize + nx + 1usize
    var rows = n
    if kind == 5u8 { rows = 2usize * n }
    let z = vec(a, rows * k)
    let yl = vec(a, rows)
    let wl = vec(a, rows)
    var r = 0usize
    while r < rows {
        var src = r
        var po = 0.0f64
        if kind == 5u8 {
            if r >= n {
                src = r - n
                po = 1.0f64
            }
        } else {
            po = dt.post[r]
        }
        if kind == 5u8 {
            if po == 1.0f64 { yl[r] = dt.y[src] } else { yl[r] = dt.post[src] }
        } else {
            yl[r] = dt.y[src]
        }
        wl[r] = w[src]
        z[r * k] = 1.0f64
        z[r * k + 1usize] = po
        z[r * k + 2usize] = dt.d[src]
        var j = 0usize
        while j < nx {
            z[r * k + 3usize + j] = dt.x[src * p + first + j]
            j += 1usize
        }
        z[r * k + k - 1usize] = dt.d[src] * po
        r += 1usize
    }
    let beta = vec(a, k)
    if !wls(a, z, yl, wl, rows, k, beta) { ret nan() }
    if !want { ret beta[k - 1usize] }
    let xtx = vec(a, k * k)
    let inv = vec(a, k * k)
    r = 0usize
    while r < rows {
        var u = 0usize
        while u < k {
            var v = 0usize
            while v < k {
                xtx[u * k + v] += wl[r] * z[r * k + u] * z[r * k + v] / f64(rows)
                v += 1usize
            }
            u += 1usize
        }
        r += 1usize
    }
    if ols.inverse(a, xtx, k, inv) != ok { ret nan() }
    let row_inf = vec(a, rows)
    r = 0usize
    while r < rows {
        let res = yl[r] - xdot(z, r, k, beta)
        var s = 0.0f64
        var u = 0usize
        while u < k {
            s += z[r * k + u] * inv[u * k + k - 1usize]
            u += 1usize
        }
        row_inf[r] = wl[r] * res * s
        r += 1usize
    }
    i = 0usize
    while i < n {
        if kind == 5u8 { inf[i] = (row_inf[i] + row_inf[n + i]) / 2.0f64 } else { inf[i] = row_inf[i] }
        i += 1usize
    }
    ret beta[k - 1usize]
}

fn est(a: *mem.Arena, kind: u8, dt: *const Data, w: []const f64, tl: f64, inf: []f64, want: bool) -> f64 {
    if kind == 5u8 {
        if dt.p == 1usize {
            var d2: Data = zero
            d2.n = dt.n
            d2.p = dt.p
            d2.d = dt.d
            d2.x = dt.x
            let dy = vec(a, dt.n)
            var i = 0usize
            while i < dt.n {
                dy[i] = dt.y[i] - dt.post[i]
                i += 1usize
            }
            d2.y = dy
            ret est_panel(a, 0u8, &d2, w, tl, inf, want)
        }
        ret est_twfe(a, kind, dt, w, inf, want)
    }
    if kind == 17u8 { ret est_twfe(a, kind, dt, w, inf, want) }
    if kind < 10u8 { ret est_panel(a, kind, dt, w, tl, inf, want) }
    ret est_rc(a, kind, dt, w, tl, inf, want)
}

fn sort_asc(v: []f64) {
    var i = 1usize
    while i < v.len {
        let t = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > t {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = t
        i += 1usize
    }
}

// bootstrap_inference(errors, estimate): the IQR based standard error and the 95% quantile of |errors / se| as the critical value
fn boot_inference(a: *mem.Arena, errors: []const f64, att: f64, r: *Res) {
    let m = errors.len
    let s = vec(a, m)
    let ab = vec(a, m)
    var i = 0usize
    while i < m {
        s[i] = errors[i]
        i += 1usize
    }
    sort_asc(s)
    let q75 = ci.quantile_r(s, 0.75f64, 7u8)
    let q25 = ci.quantile_r(s, 0.25f64, 7u8)
    let se = (q75 - q25) / (dist.qnorm(0.75f64, 0.0f64, 1.0f64, true, false) - dist.qnorm(0.25f64, 0.0f64, 1.0f64, true, false))
    r.se = se
    if se == 0.0f64 {
        r.lci = att
        r.uci = att
        ret
    }
    i = 0usize
    while i < m {
        ab[i] = math.abs[f64](errors[i] / se)
        i += 1usize
    }
    sort_asc(ab)
    let cv = ci.quantile_r(ab, 0.95f64, 7u8)
    r.lci = att - cv * se
    r.uci = att + cv * se
}

// the estimate of `kind` with its influence function, and inference by the analytic standard error (boot 0), the multiplier bootstrap (1) or the weighted bootstrap (2) drawing from g
fn did(a: *mem.Arena, g: *rng.Rng, kind: u8, boot: u8, nboot: usize, y: []const f64, post: []const f64, d: []const f64, x: []const f64, iwr: []const f64, n: usize, p: usize, tl: f64) -> Res {
    var r: Res = zero
    r.att = nan()
    r.se = nan()
    r.lci = nan()
    r.uci = nan()
    var dt: Data = zero
    dt.n = n
    dt.p = p
    dt.y = y
    dt.post = post
    dt.d = d
    dt.x = x
    let iw = vec(a, n)
    let mw = meanv(iwr)
    var i = 0usize
    while i < n {
        iw[i] = iwr[i] / mw
        i += 1usize
    }
    r.inf = vec(a, n)
    r.att = est(a, kind, &dt, iw, tl, r.inf, true)
    if !fin(r.att) { ret r }
    let nf = f64(n)
    if boot == 0u8 {
        let mn = meanv(r.inf)
        var ss = 0.0f64
        i = 0usize
        while i < n {
            ss += (r.inf[i] - mn) * (r.inf[i] - mn)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / (nf - 1.0f64))
        r.se = sd * math.sqrt[f64](nf - 1.0f64) / nf
        if kind == 17u8 { r.se = sd / math.sqrt[f64](nf) }
        r.lci = r.att - 1.96f64 * r.se
        r.uci = r.att + 1.96f64 * r.se
        ret r
    }
    r.boots = vec(a, nboot)
    if boot == 1u8 {
        let s5 = math.sqrt[f64](5.0f64)
        let k1 = 0.5f64 * (1.0f64 - s5)
        let k2 = 0.5f64 * (1.0f64 + s5)
        let pk = 0.5f64 * (1.0f64 + s5) / s5
        var b = 0usize
        while b < nboot {
            var s = 0.0f64
            i = 0usize
            while i < n {
                var v = k2
                if rdist.rbinom(g, 1.0f64, pk) == 1.0f64 { v = k1 }
                s += r.inf[i] * v
                i += 1usize
            }
            r.boots[b] = s / nf
            b += 1usize
        }
        boot_inference(a, r.boots, r.att, &r)
        ret r
    }
    let er = vec(a, nboot)
    let bw = vec(a, n)
    let noinf = vec(a, 0usize)
    var b = 0usize
    while b < nboot {
        let start = mem.mark(a)
        i = 0usize
        while i < n {
            bw[i] = iw[i] * rng.rexp(g, 1.0f64)
            i += 1usize
        }
        if kind == 11u8 {
            let mb = meanv(bw)
            i = 0usize
            while i < n {
                bw[i] = bw[i] / mb
                i += 1usize
            }
        }
        r.boots[b] = est(a, kind, &dt, bw, tl, noinf, false)
        mem.reset(a, start)
        er[b] = r.boots[b] - r.att
        b += 1usize
    }
    boot_inference(a, er, r.att, &r)
    ret r
}

// the unweighted analytic ATT (part 0), standard error (1) of the panel and cross-section estimators the first oracle checks
fn reg_did_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    ret one(a, 0u8, dy, dy, d, x, n, p, part)
}

fn drdid_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    ret one(a, 3u8, dy, dy, d, x, n, p, part)
}

fn ipw_did_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, std: bool, part: usize) -> f64 {
    var k = 1u8
    if std { k = 2u8 }
    ret one(a, k, dy, dy, d, x, n, p, part)
}

fn reg_did_rc(a: *mem.Arena, y: []const f64, post: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    ret one(a, 10u8, y, post, d, x, n, p, part)
}

fn one(a: *mem.Arena, kind: u8, y: []const f64, post: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    var g: rng.Rng = zero
    let ones = vec(a, n)
    var i = 0usize
    while i < n {
        ones[i] = 1.0f64
        i += 1usize
    }
    let r = did(a, &g, kind, 0u8, 0usize, y, post, d, x, ones, n, p, 0.995f64)
    if part == 0usize { ret r.att }
    ret r.se
}

// drdid(panel, estMethod): the doubly robust kind, imp for the improved estimators
fn kind_drdid(panel: bool, imp: bool) -> u8 {
    if panel {
        if imp { ret 4u8 }
        ret 3u8
    }
    if imp { ret 15u8 }
    ret 13u8
}

// ipwdid(panel, normalized)
fn kind_ipwdid(panel: bool, normalized: bool) -> u8 {
    if panel {
        if normalized { ret 2u8 }
        ret 1u8
    }
    if normalized { ret 12u8 }
    ret 11u8
}

// ordid(panel)
fn kind_ordid(panel: bool) -> u8 {
    if panel { ret 0u8 }
    ret 10u8
}
