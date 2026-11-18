// R aod: varbin (the binomial, ratio, arithmetic and jackknife estimates of a proportion over clusters, with their variances and normal limits) and iccbin
// method "C" (the one-way ANOVA intra-cluster correlation of binary data).
//
// Not here: the bootstrap row of varbin, iccbin methods A and B (mixed-model based), betabin, negbin, quasibin, quasipois, anova, splitbin.

use e.algo.stat.desctools as dt
use e.algo.stat.flexmixpkg as fx
use e.math.special as sp
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem
use e.algo.stat.wrs2 as wr
use e.algo.stat.rnm as rn

// varbin(n, y)$tab: part 0 the estimate, 1 its variance, 2 the lower and 3 the upper limit of row `row`
// (0 binomial, 1 ratio, 2 arithmetic, 3 jackknife) at level 1 - alpha
fn varbin(n: []const f64, y: []const f64, alpha: f64, row: usize, part: usize) -> f64 {
    let k = n.len
    let kf = f64(k)
    var ntot = 0.0f64
    var ytot = 0.0f64
    var i = 0usize
    while i < k {
        ntot += n[i]
        ytot += y[i]
        i += 1usize
    }
    let p = ytot / ntot
    var est = 0.0f64
    var v = 0.0f64
    if row == 0usize {
        est = p
        v = p * (1.0f64 - p) / (ntot - 1.0f64)
    } else if row == 1usize {
        var s = 0.0f64
        i = 0usize
        while i < k {
            let r = y[i] - n[i] * p
            s += r * r
            i += 1usize
        }
        est = p
        v = kf / (kf - 1.0f64) / (ntot * ntot) * s
    } else if row == 2usize {
        let (m, w) = prop_stats(n, y)
        est = m
        v = w
    } else {
        // the jackknife pseudovalues p + (k - 1) (y_i - n_i p) / (ntot - n_i)
        var m = 0.0f64
        i = 0usize
        while i < k {
            m += p + (kf - 1.0f64) * (y[i] - n[i] * p) / (ntot - n[i])
            i += 1usize
        }
        m = m / kf
        var ss = 0.0f64
        i = 0usize
        while i < k {
            let ps = p + (kf - 1.0f64) * (y[i] - n[i] * p) / (ntot - n[i])
            ss += (ps - m) * (ps - m)
            i += 1usize
        }
        est = m
        v = ss / (kf - 1.0f64) / kf
    }
    if part == 0usize { ret est }
    if part == 1usize { ret v }
    let z = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    if part == 2usize { ret dt.max_f(0.0f64, est - z * math.sqrt[f64](v)) }
    ret dt.min_f(1.0f64, est + z * math.sqrt[f64](v))
}

// the mean of y_i / n_i and the variance of that mean
fn prop_stats(n: []const f64, y: []const f64) -> (f64, f64) {
    let k = n.len
    var m = 0.0f64
    var i = 0usize
    while i < k {
        m += y[i] / n[i]
        i += 1usize
    }
    m = m / f64(k)
    var ss = 0.0f64
    i = 0usize
    while i < k {
        let r = y[i] / n[i] - m
        ss += r * r
        i += 1usize
    }
    ret (m, ss / f64(k - 1usize) / f64(k))
}

// iccbin(n, y, method = "C")@rho: (MSA - MSE) / (MSA + (nA - 1) MSE) of the one-way ANOVA of the binary observations on the cluster
fn iccbin_c(n: []const f64, y: []const f64) -> f64 {
    let k = n.len
    var ntot = 0.0f64
    var ytot = 0.0f64
    var s2 = 0.0f64
    var sn2 = 0.0f64
    var i = 0usize
    while i < k {
        ntot += n[i]
        ytot += y[i]
        s2 += y[i] * y[i] / n[i]
        sn2 += n[i] * n[i]
        i += 1usize
    }
    let ssa = s2 - ytot * ytot / ntot
    let sse = ytot - s2
    let msa = ssa / (f64(k) - 1.0f64)
    let mse = sse / (ntot - f64(k))
    let na = (ntot - sn2 / ntot) / (f64(k) - 1.0f64)
    ret (msa - mse) / (msa + (na - 1.0f64) * mse)
}

type Donner = struct { rho: f64, x2: f64 }

// aod::donner (the design effect of cluster samples and the corrected chi-square test of equal proportions across groups) for rows with sizes n, successes y and
// 0-based group codes grp (ng groups, every group present)
fn donner(n: []const f64, y: []const f64, grp: []const f64, ng: usize) -> Donner {
    var out: Donner = zero
    let rows = n.len
    var nn = 0.0f64
    var ntot_all = 0.0f64
    var ytot_all = 0.0f64
    var nA_all = 0.0f64
    var msc = 0.0f64
    var g = 0usize
    while g < ng {
        var cnt = 0.0f64
        var nt = 0.0f64
        var yt = 0.0f64
        var n2 = 0.0f64
        var i = 0usize
        while i < rows {
            if usize(grp[i]) == g {
                cnt += 1.0f64
                nt += n[i]
                yt += y[i]
                n2 += n[i] * n[i]
            }
            i += 1usize
        }
        let pg = yt / nt
        i = 0usize
        while i < rows {
            if usize(grp[i]) == g {
                let d = y[i] / n[i] - pg
                msc += n[i] * d * d
            }
            i += 1usize
        }
        nn += cnt
        ntot_all += nt
        ytot_all += yt
        nA_all += n2 / nt
        g += 1usize
    }
    let ngf = f64(ng)
    let dfc = nn - ngf
    let dfe = ntot_all - nn
    msc = msc / dfc
    var mse = 0.0f64
    var i = 0usize
    while i < rows {
        let pr = y[i] / n[i]
        mse += n[i] * pr * (1.0f64 - pr)
        i += 1usize
    }
    mse = mse / dfe
    let kk = (ntot_all - nA_all) / dfc
    let rho = (msc - mse) / (msc + (kk - 1.0f64) * mse)
    let p = ytot_all / ntot_all
    var x2 = 0.0f64
    g = 0usize
    while g < ng {
        var nt = 0.0f64
        var yt = 0.0f64
        var n2 = 0.0f64
        i = 0usize
        while i < rows {
            if usize(grp[i]) == g {
                nt += n[i]
                yt += y[i]
                n2 += n[i] * n[i]
            }
            i += 1usize
        }
        let c = 1.0f64 + (n2 / nt - 1.0f64) * rho
        x2 += (yt - nt * p) * (yt - nt * p) / (c * nt * p * (1.0f64 - p))
        g += 1usize
    }
    out.rho = rho
    out.x2 = x2
    ret out
}

type Wald = struct { x2: f64, p: f64 }

// aod::wald.test for the linear hypothesis L b = 0: b (p), sigma the covariance of b (p by p row-major), L (q by p row-major);
// the statistic t(Lb) (L sigma t(L))^-1 (Lb) and its chi-square p value on q degrees of freedom
fn wald_test(a: *mem.Arena, b: []const f64, sigma: []const f64, lm: []const f64, q: usize, p: usize) -> (Wald, err) {
    var out: Wald = zero
    let (lb, e1) = mem.alloc[f64](a, q)
    let (ls, e2) = mem.alloc[f64](a, q * p)
    let (m, e3) = mem.alloc[f64](a, q * q)
    let (mi, e4) = mem.alloc[f64](a, q * q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, mem.Full) }
    var r = 0usize
    while r < q {
        var s = 0.0f64
        var c = 0usize
        while c < p {
            s += lm[r * p + c] * b[c]
            c += 1usize
        }
        lb[r] = s
        c = 0usize
        while c < p {
            var t = 0.0f64
            var k = 0usize
            while k < p {
                t += lm[r * p + k] * sigma[k * p + c]
                k += 1usize
            }
            ls[r * p + c] = t
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < q {
        var c = 0usize
        while c < q {
            var t = 0.0f64
            var k = 0usize
            while k < p {
                t += ls[r * p + k] * lm[c * p + k]
                k += 1usize
            }
            m[r * q + c] = t
            c += 1usize
        }
        r += 1usize
    }
    let ei = wr.invert_small(a, m, q, mi)
    if ei != ok { ret (out, ei) }
    var x2 = 0.0f64
    r = 0usize
    while r < q {
        var c = 0usize
        while c < q {
            x2 += lb[r] * mi[r * q + c] * lb[c]
            c += 1usize
        }
        r += 1usize
    }
    out.x2 = x2
    out.p = nm.pchisq(x2, f64(q), false, false)
    ret (out, ok)
}

fn qp_fitted(x: []const f64, n: usize, p: usize, beta: []const f64, mu: []f64) {
    var i = 0usize
    while i < n {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += x[c * n + i] * beta[c]
            c += 1usize
        }
        mu[i] = math.exp[f64](t)
        i += 1usize
    }
}

fn qp_loglik(y: []const f64, mu: []const f64, w: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += w[i] * (y[i] * math.log[f64](mu[i]) - mu[i] - sp.lgamma(y[i] + 1.0f64))
        i += 1usize
    }
    ret s
}

// quasipois(y ~ x, phi, tol): x is n by p column-major; has_phi false estimates phi by the package's moment iteration, true holds it and iterates the weights to a log-likelihood change below 1e-6;
// out receives the p coefficients and then phi
fn quasipois(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, has_phi: bool, phi0: f64, tol: f64, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (b0, e3) = mem.alloc[f64](a, p)
    let (b1, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret fx.Malformed }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    var phi = phi0
    var e = fx.pois_glm(a, x, n, p, y, w, b0, false)
    if e != ok { ret e }
    if !has_phi {
        phi = 0.0001f64
        var more = true
        while more {
            qp_fitted(x, n, p, b0, mu)
            var x2 = 0.0f64
            i = 0usize
            while i < n {
                x2 += w[i] * (y[i] - mu[i]) * (y[i] - mu[i]) / mu[i]
                i += 1usize
            }
            let dfr = f64(n - p)
            if x2 - dfr <= tol {
                more = false
            } else {
                phi = phi * x2 / dfr
                i = 0usize
                while i < n {
                    w[i] = 1.0f64 / (1.0f64 + phi * mu[i])
                    i += 1usize
                }
                e = fx.pois_glm(a, x, n, p, y, w, b0, false)
                if e != ok { ret e }
            }
        }
    } else {
        var delta = 1.0f64
        var guard = 0usize
        while delta > 0.000001f64 && guard < 200usize {
            guard += 1usize
            qp_fitted(x, n, p, b0, mu)
            let ll0 = qp_loglik(y, mu, w, n)
            i = 0usize
            while i < n {
                w[i] = 1.0f64 / (1.0f64 + phi * mu[i])
                i += 1usize
            }
            e = fx.pois_glm(a, x, n, p, y, w, b1, false)
            if e != ok { ret e }
            qp_fitted(x, n, p, b1, mu)
            delta = qp_loglik(y, mu, w, n) - ll0
            var c = 0usize
            while c < p {
                b0[c] = b1[c]
                c += 1usize
            }
        }
    }
    qp_fitted(x, n, p, b0, mu)
    i = 0usize
    while i < n {
        w[i] = 1.0f64 / (1.0f64 + phi * mu[i])
        i += 1usize
    }
    e = fx.pois_glm(a, x, n, p, y, w, b1, false)
    if e != ok { ret e }
    var c = 0usize
    while c < p {
        out[c] = b1[c]
        c += 1usize
    }
    out[p] = phi
    ret ok
}

fn qb_fitted(x: []const f64, n: usize, p: usize, beta: []const f64, mu: []f64) {
    var i = 0usize
    while i < n {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += x[c * n + i] * beta[c]
            c += 1usize
        }
        mu[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
        i += 1usize
    }
}

// quasibin(cbind(succ, size - succ) ~ x, link = "logit", phi = NULL, tol): weights 1 / (1 + (size - 1) phi); phi is estimated by the moment iteration when has_phi is false; out receives the p coefficients and phi
fn quasibin(a: *mem.Arena, x: []const f64, n: usize, p: usize, succ: []const f64, size: []const f64, has_phi: bool, phi0: f64, tol: f64, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (b0, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret fx.Malformed }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    var phi = phi0
    var e = fx.binom_glm(a, x, n, p, succ, size, w, b0, false)
    if e != ok { ret e }
    if !has_phi {
        phi = 0.0001f64
        var more = true
        while more {
            qb_fitted(x, n, p, b0, mu)
            var x2 = 0.0f64
            i = 0usize
            while i < n {
                let d = succ[i] / size[i] - mu[i]
                x2 += w[i] * size[i] * d * d / (mu[i] * (1.0f64 - mu[i]))
                i += 1usize
            }
            let dfr = f64(n - p)
            if x2 - dfr <= tol {
                more = false
            } else {
                phi = phi * x2 / dfr
                i = 0usize
                while i < n {
                    w[i] = 1.0f64 / (1.0f64 + (size[i] - 1.0f64) * phi)
                    i += 1usize
                }
                e = fx.binom_glm(a, x, n, p, succ, size, w, b0, false)
                if e != ok { ret e }
            }
        }
    }
    i = 0usize
    while i < n {
        w[i] = 1.0f64 / (1.0f64 + (size[i] - 1.0f64) * phi)
        i += 1usize
    }
    e = fx.binom_glm(a, x, n, p, succ, size, w, b0, false)
    if e != ok { ret e }
    var c = 0usize
    while c < p {
        out[c] = b0[c]
        c += 1usize
    }
    out[p] = phi
    ret ok
}

// betabin(cbind(y, n - y) ~ x, ~ 1): logit link, one phi; R's optim Nelder-Mead (reltol 1.49e-8, maxit 2000) from the binomial glm coefficients and phi = 0.1
type BbCtx = struct { x: []const f64, n: usize, p: usize, y: []const f64, size: []const f64 }

fn lbeta_(u: f64, v: f64) -> f64 { ret sp.lgamma(u) + sp.lgamma(v) - sp.lgamma(u + v) }

fn bb_nll(c: *BbCtx, par: []const f64) -> f64 {
    let phi = par[c.p]
    var s = 0.0f64
    var i = 0usize
    while i < c.n {
        var t = 0.0f64
        var k = 0usize
        while k < c.p {
            t += c.x[k * c.n + i] * par[k]
            k += 1usize
        }
        let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
        let u = pr * (1.0f64 - phi) / phi
        let v = (1.0f64 - pr) * (1.0f64 - phi) / phi
        s += sp.lgamma(c.size[i] + 1.0f64) - sp.lgamma(c.y[i] + 1.0f64) - sp.lgamma(c.size[i] - c.y[i] + 1.0f64) + lbeta_(u + c.y[i], v + c.size[i] - c.y[i]) - lbeta_(u, v)
        i += 1usize
    }
    if s != s || s > 1.0e300f64 || s < 0.0f64 - 1.0e300f64 { ret 1.0e20f64 }
    ret 0.0f64 - s
}

// out receives the p coefficients, phi, and the maximised log-likelihood; the result is the optim convergence code
fn betabin(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, size: []const f64, out: []f64) -> (usize, err) {
    let (w, e1) = mem.alloc[f64](a, n)
    let (b0, e2) = mem.alloc[f64](a, p + 1usize)
    let (best, e3) = mem.alloc[f64](a, p + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (1usize, fx.Malformed) }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    let e = fx.binom_glm(a, x, n, p, y, size, w, b0, false)
    if e != ok { ret (1usize, e) }
    b0[p] = 0.1f64
    var c = BbCtx{ x: x, n: n, p: p, y: y, size: size }
    let (fmin, cnt, fail) = rn.nmmin[BbCtx](a, &c, bb_nll, b0, 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, 2000usize, 1.0f64, best)
    var k = 0usize
    while k <= p {
        out[k] = best[k]
        k += 1usize
    }
    out[p + 1usize] = 0.0f64 - fmin
    ret (fail, ok)
}

// negbin(y ~ x, ~ 1): log link, one phi (k = 1 / phi); the Poisson glm coefficients and phi = 0.1 start R's Nelder-Mead; out receives the p coefficients, phi and the maximised log-likelihood
type NbCtx = struct { x: []const f64, n: usize, p: usize, y: []const f64 }

fn nb_nll(c: *NbCtx, par: []const f64) -> f64 {
    let phi = par[c.p]
    let k = 1.0f64 / phi
    var s = 0.0f64
    var i = 0usize
    while i < c.n {
        var t = 0.0f64
        var j = 0usize
        while j < c.p {
            t += c.x[j * c.n + i] * par[j]
            j += 1usize
        }
        let mu = math.exp[f64](t)
        if phi == 0.0f64 {
            s += c.y[i] * math.log[f64](mu) - mu - sp.lgamma(c.y[i] + 1.0f64)
        } else {
            s += sp.lgamma(c.y[i] + k) - sp.lgamma(c.y[i] + 1.0f64) - sp.lgamma(k) + k * math.log[f64](k / (k + mu)) + c.y[i] * math.log[f64](mu / (k + mu))
        }
        i += 1usize
    }
    if s != s || s > 1.0e300f64 || s < 0.0f64 - 1.0e300f64 { ret 1.0e20f64 }
    ret 0.0f64 - s
}

fn negbin(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, out: []f64) -> (usize, err) {
    let (w, e1) = mem.alloc[f64](a, n)
    let (b0, e2) = mem.alloc[f64](a, p + 1usize)
    let (best, e3) = mem.alloc[f64](a, p + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (1usize, fx.Malformed) }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    let e = fx.pois_glm(a, x, n, p, y, w, b0, false)
    if e != ok { ret (1usize, e) }
    b0[p] = 0.1f64
    var c = NbCtx{ x: x, n: n, p: p, y: y }
    let (fmin, cnt, fail) = rn.nmmin[NbCtx](a, &c, nb_nll, b0, 0.0f64 - 1.0f64 / 0.0f64, 0.0000000149011611938f64, 1.0f64, 0.5f64, 2.0f64, 2000usize, 1.0f64, best)
    var k = 0usize
    while k <= p {
        out[k] = best[k]
        k += 1usize
    }
    out[p + 1usize] = 0.0f64 - fmin
    ret (fail, ok)
}

// splitbin(cbind(y, n - y) ~ 1): the Bernoulli expansion's row i of the table is a block of n_i - y_i zeros then y_i ones; out receives the responses in order (sum of n values)
fn splitbin(n: []const f64, y: []const f64, out: []f64) -> usize {
    var at = 0usize
    var i = 0usize
    while i < n.len {
        let ni = usize(math.round[f64](n[i]))
        let yi = usize(math.round[f64](y[i]))
        var k = 0usize
        while k < ni {
            if ni > 0usize {
                if k < ni - yi { out[at] = 0.0f64 } else { out[at] = 1.0f64 }
                at += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    ret at
}

// R's optimHess: central differences of central-difference gradients with step 1e-3, symmetrised; h is np by np row-major
fn opt_grad[Ctx: type](c: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []f64, g: []f64) {
    let np = x.len
    var j = 0usize
    while j < np {
        let keep = x[j]
        x[j] = keep + 0.001f64
        let v1 = f(c, x)
        x[j] = keep - 0.001f64
        let v2 = f(c, x)
        x[j] = keep
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

fn optimhess[Ctx: type](a: *mem.Arena, c: *Ctx, f: fn(*Ctx, []const f64) -> f64, par: []const f64, h: []f64) -> err {
    let np = par.len
    let (x, e1) = mem.alloc[f64](a, np)
    let (g1, e2) = mem.alloc[f64](a, np)
    let (g2, e3) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok { ret fx.Malformed }
    var i = 0usize
    while i < np {
        var k = 0usize
        while k < np {
            x[k] = par[k]
            k += 1usize
        }
        x[i] = par[i] + 0.001f64
        opt_grad[Ctx](c, f, x, g1)
        x[i] = par[i] - 0.001f64
        opt_grad[Ctx](c, f, x, g2)
        k = 0usize
        while k < np {
            h[i * np + k] = (g1[k] - g2[k]) / 0.002f64
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < np {
        var k = 0usize
        while k < i {
            let m = 0.5f64 * (h[i * np + k] + h[k * np + i])
            h[i * np + k] = m
            h[k * np + i] = m
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the square roots of the diagonal of the inverse of the np by np matrix h (Gauss-Jordan), into se; false when singular
fn inv_se(a: *mem.Arena, h: []const f64, np: usize, se: []f64) -> bool {
    let (m, e1) = mem.alloc[f64](a, np * 2usize * np)
    if e1 != ok { ret false }
    var i = 0usize
    while i < np {
        var k = 0usize
        while k < np {
            m[i * 2usize * np + k] = h[i * np + k]
            m[i * 2usize * np + np + k] = 0.0f64
            k += 1usize
        }
        m[i * 2usize * np + np + i] = 1.0f64
        i += 1usize
    }
    var col = 0usize
    while col < np {
        var piv = col
        var r = col + 1usize
        while r < np {
            if math.abs[f64](m[r * 2usize * np + col]) > math.abs[f64](m[piv * 2usize * np + col]) { piv = r }
            r += 1usize
        }
        if math.abs[f64](m[piv * 2usize * np + col]) < 1.0e-300f64 { ret false }
        var k = 0usize
        while k < 2usize * np {
            let t = m[col * 2usize * np + k]
            m[col * 2usize * np + k] = m[piv * 2usize * np + k]
            m[piv * 2usize * np + k] = t
            k += 1usize
        }
        let d = m[col * 2usize * np + col]
        k = 0usize
        while k < 2usize * np {
            m[col * 2usize * np + k] = m[col * 2usize * np + k] / d
            k += 1usize
        }
        r = 0usize
        while r < np {
            if r != col {
                let f = m[r * 2usize * np + col]
                k = 0usize
                while k < 2usize * np {
                    m[r * 2usize * np + k] = m[r * 2usize * np + k] - f * m[col * 2usize * np + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < np {
        se[i] = math.sqrt[f64](m[i * 2usize * np + np + i])
        i += 1usize
    }
    ret true
}

// betabin_se and negbin_se: the standard errors of (coefficients, phi) at the fitted parameters par (p + 1 values), into se
fn betabin_se(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, size: []const f64, par: []const f64, se: []f64) -> bool {
    var c = BbCtx{ x: x, n: n, p: p, y: y, size: size }
    let np = p + 1usize
    let (h, e) = mem.alloc[f64](a, np * np)
    if e != ok { ret false }
    if optimhess[BbCtx](a, &c, bb_nll, par, h) != ok { ret false }
    ret inv_se(a, h, np, se)
}

fn negbin_se(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, par: []const f64, se: []f64) -> bool {
    var c = NbCtx{ x: x, n: n, p: p, y: y }
    let np = p + 1usize
    let (h, e) = mem.alloc[f64](a, np * np)
    if e != ok { ret false }
    if optimhess[NbCtx](a, &c, nb_nll, par, h) != ok { ret false }
    ret inv_se(a, h, np, se)
}
