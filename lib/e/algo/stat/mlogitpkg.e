// R mlogit: discrete-choice models over a design x (n choice situations by j alternatives by k columns, row-major in that order; the columns are R's model.matrix, so
// alternative-specific constants and individual-specific covariates with alternative-specific coefficients are columns like any other). The conditional logit is fitted by Newton's
// method on the exact Hessian; the nested logit, the heteroskedastic logit (Gauss-Laguerre quadrature) and the mixed logit (normal random coefficients, Halton draws, panel or not)
// maximise their analytic log-likelihoods to the optimum, and their standard errors are the outer product of the gradients, as mlogit's. Also the fitted and predicted probabilities,
// the marginal effects and the Wald, likelihood-ratio and score tests.
//
// Not here: probit, rank-ordered data, the paired combinatorial and other GEV models, non-normal or correlated random coefficients, weights.

use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.nmath as nmz
use e.mem

// the log-likelihood (returned), the gradient gr (q, when gr.len > 0) and the information -H (q by q row-major into h, when h.len > 0) of the conditional logit at coef,
// q = na + k: the first na coefficients are the constants of alternatives 1..na (the first alternative the reference); ch may be empty (no log-likelihood or gradient)
fn clogit_gh(x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, na: usize, coef: []const f64, gr: []f64, h: []f64) -> f64 {
    let q = na + k
    var z: [1024]f64 = zero
    var pr: [32]f64 = zero
    var zb: [64]f64 = zero
    var i = 0usize
    while i < gr.len {
        gr[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < h.len {
        h[i] = 0.0f64
        i += 1usize
    }
    var ll = 0.0f64
    var c = 0usize
    while c < n {
        var mx = 0.0f64 - 1.0e300f64
        var a2 = 0usize
        while a2 < j {
            var v = 0.0f64
            var q2 = 0usize
            while q2 < q {
                var zv = 0.0f64
                if q2 < na {
                    if a2 > 0usize && q2 == a2 - 1usize { zv = 1.0f64 }
                } else {
                    zv = x[(c * j + a2) * k + q2 - na]
                }
                z[a2 * q + q2] = zv
                v += coef[q2] * zv
                q2 += 1usize
            }
            pr[a2] = v
            if v > mx { mx = v }
            a2 += 1usize
        }
        var s = 0.0f64
        a2 = 0usize
        while a2 < j {
            pr[a2] = math.exp[f64](pr[a2] - mx)
            s += pr[a2]
            a2 += 1usize
        }
        a2 = 0usize
        while a2 < j {
            pr[a2] = pr[a2] / s
            a2 += 1usize
        }
        var q2 = 0usize
        while q2 < q {
            var m = 0.0f64
            a2 = 0usize
            while a2 < j {
                m += pr[a2] * z[a2 * q + q2]
                a2 += 1usize
            }
            zb[q2] = m
            q2 += 1usize
        }
        if ch.len > 0usize {
            let yi = usize(ch[c])
            ll += math.log[f64](pr[yi])
            if gr.len > 0usize {
                q2 = 0usize
                while q2 < q {
                    gr[q2] += z[yi * q + q2] - zb[q2]
                    q2 += 1usize
                }
            }
        }
        if h.len > 0usize {
            a2 = 0usize
            while a2 < j {
                q2 = 0usize
                while q2 < q {
                    var q3 = 0usize
                    while q3 < q {
                        h[q2 * q + q3] += pr[a2] * (z[a2 * q + q2] - zb[q2]) * (z[a2 * q + q3] - zb[q3])
                        q3 += 1usize
                    }
                    q2 += 1usize
                }
                a2 += 1usize
            }
        }
        c += 1usize
    }
    ret ll
}

// x is n choosers by j alternatives by k covariates (row-major in that order); ch[i] is the chosen alternative (0-based); out = coefficients (q), standard errors (q), log-likelihood,
// q = (asc ? j - 1 : 0) + k, the constants first
fn clogit(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, asc: bool, out: []f64) -> err {
    var na = 0usize
    if asc { na = j - 1usize }
    let q = na + k
    let (b, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (h, e3) = mem.alloc[f64](a, q * q)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < q {
        b[i] = 0.0f64
        i += 1usize
    }
    var it = 0usize
    while it < 100usize {
        let _ = clogit_gh(x, ch, n, j, k, na, b, gr, h)
        let (hi, ie) = gp.invert(a, h, q)
        if ie != ok { ret ie }
        var step = 0.0f64
        i = 0usize
        while i < q {
            var d = 0.0f64
            var l = 0usize
            while l < q {
                d += hi[i * q + l] * gr[l]
                l += 1usize
            }
            b[i] += d
            if math.abs[f64](d) > step { step = math.abs[f64](d) }
            i += 1usize
        }
        it += 1usize
        if step < 1.0e-13f64 { break }
    }
    // standard errors and the log-likelihood at the final coefficients
    let ll = clogit_gh(x, ch, n, j, k, na, b, gr, h)
    let (hf, fe) = gp.invert(a, h, q)
    if fe != ok { ret fe }
    i = 0usize
    while i < q {
        out[i] = b[i]
        out[q + i] = math.sqrt[f64](hf[i * q + i])
        i += 1usize
    }
    out[2usize * q] = ll
    ret ok
}

// the fitted choice probabilities of chooser i (utility a_j + x_ij beta, a_0 = 0 as the reference): p[0 .. j]
fn clogit_probs(x: []const f64, i: usize, j: usize, k: usize, asc: bool, coef: []const f64, p: []f64) {
    var na = 0usize
    if asc { na = j - 1usize }
    var tot = 0.0f64
    var a1 = 0usize
    while a1 < j {
        var v = 0.0f64
        if asc && a1 > 0usize { v = coef[a1 - 1usize] }
        var c = 0usize
        while c < k {
            v += x[(i * j + a1) * k + c] * coef[na + c]
            c += 1usize
        }
        p[a1] = math.exp[f64](v)
        tot += p[a1]
        a1 += 1usize
    }
    a1 = 0usize
    while a1 < j {
        p[a1] = p[a1] / tot
        a1 += 1usize
    }
}

// the mean over choosers of the fitted probabilities, colMeans(fitted(f, outcome = FALSE)) of mlogit: out[0 .. j]
fn clogit_shares(x: []const f64, n: usize, j: usize, k: usize, asc: bool, coef: []const f64, out: []f64) {
    var pr: [16]f64 = zero
    var a1 = 0usize
    while a1 < j {
        out[a1] = 0.0f64
        a1 += 1usize
    }
    var i = 0usize
    while i < n {
        clogit_probs(x, i, j, k, asc, coef, pr[0usize..j])
        a1 = 0usize
        while a1 < j {
            out[a1] += pr[a1] / f64(n)
            a1 += 1usize
        }
        i += 1usize
    }
}

// the conditional logit probabilities at the design row means mx (j by k), covariate cov of alternative bump raised by eps (no alternative when bump >= j): p[0 .. j]
fn probs_at(mx: []const f64, j: usize, k: usize, na: usize, coef: []const f64, bump: usize, cov: usize, eps: f64, p: []f64) {
    var tot = 0.0f64
    var a1 = 0usize
    while a1 < j {
        var v = 0.0f64
        if na > 0usize && a1 > 0usize { v = coef[a1 - 1usize] }
        var c = 0usize
        while c < k {
            var xv = mx[a1 * k + c]
            if a1 == bump && c == cov { xv = xv + eps }
            v += xv * coef[na + c]
            c += 1usize
        }
        p[a1] = math.exp[f64](v)
        tot += p[a1]
        a1 += 1usize
    }
    a1 = 0usize
    while a1 < j {
        p[a1] = p[a1] / tot
        a1 += 1usize
    }
}

// effects(f, covariate = c) of mlogit ("aa"): at the means of the covariates by alternative, the forward difference (step 1e-5, as mlogit's) of the probabilities when covariate c of alternative l
// rises; out[l j + a] is the change of the probability of a (row-major out)
fn clogit_effects(x: []const f64, n: usize, j: usize, k: usize, asc: bool, coef: []const f64, cov: usize, out: []f64) {
    var na = 0usize
    if asc { na = j - 1usize }
    var mx: [512]f64 = zero
    var pr: [32]f64 = zero
    var pn: [32]f64 = zero
    var a1 = 0usize
    while a1 < j {
        var c = 0usize
        while c < k {
            var m = 0.0f64
            var i = 0usize
            while i < n {
                m += x[(i * j + a1) * k + c]
                i += 1usize
            }
            mx[a1 * k + c] = m / f64(n)
            c += 1usize
        }
        a1 += 1usize
    }
    let eps = 1.0e-5f64
    probs_at(mx[0usize..j * k], j, k, na, coef, j, cov, eps, pr[0usize..j])
    var l = 0usize
    while l < j {
        probs_at(mx[0usize..j * k], j, k, na, coef, l, cov, eps, pn[0usize..j])
        a1 = 0usize
        while a1 < j {
            out[l * j + a1] = (pn[a1] - pr[a1]) / eps
            a1 += 1usize
        }
        l += 1usize
    }
}

// the covariance matrix of the conditional logit coefficients (the inverse of the information at coef, q by q row-major into v) for the Wald tests of mlogit; q = (asc ? j - 1 : 0) + k; false when singular
fn clogit_vcov(a: *mem.Arena, x: []const f64, n: usize, j: usize, k: usize, asc: bool, coef: []const f64, v: []f64) -> bool {
    var na = 0usize
    if asc { na = j - 1usize }
    let q = na + k
    let (h, e1) = mem.alloc[f64](a, q * q)
    if e1 != ok { ret false }
    let _ = clogit_gh(x, x[0usize..0usize], n, j, k, na, coef, h[0usize..0usize], h)
    let (hi, ie) = gp.invert(a, h, q)
    if ie != ok { ret false }
    var i = 0usize
    while i < q * q {
        v[i] = hi[i]
        i += 1usize
    }
    ret true
}

// scoretest of mlogit for two conditional logits: g' I^-1 g with the gradient g and the information I of the larger model (k columns, no constants) at coef, the restricted estimates with zeros
// for the added coefficients; out[0] the statistic, out[1] its chi-square p value on df degrees of freedom; false when singular
fn clogit_score(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, coef: []const f64, df: usize, out: []f64) -> bool {
    let (h, e1) = mem.alloc[f64](a, k * k + k)
    if e1 != ok { ret false }
    let gr = h[k * k..k * k + k]
    let _ = clogit_gh(x, ch, n, j, k, 0usize, coef, gr, h[0usize..k * k])
    let (hi, ie) = gp.invert(a, h[0usize..k * k], k)
    if ie != ok { ret false }
    var s = 0.0f64
    var i = 0usize
    while i < k {
        var l = 0usize
        while l < k {
            s += gr[i] * hi[i * k + l] * gr[l]
            l += 1usize
        }
        i += 1usize
    }
    out[0usize] = s
    out[1usize] = nmz.pchisq(s, f64(df), false, false)
    ret true
}

// the Wald statistic b_S' (V_SS)^-1 b_S of the coefficients whose indices (0-based into the q coefficients) are listed in sel, from the covariance v (q by q row-major); out[0] the statistic, out[1] its
// chi-square p value on len(sel) degrees of freedom; false when the sub-matrix is singular
fn wald_test(a: *mem.Arena, coef: []const f64, v: []const f64, q: usize, sel: []const usize, out: []f64) -> bool {
    let r = sel.len
    let (vs, e1) = mem.alloc[f64](a, r * r)
    if e1 != ok { ret false }
    var i = 0usize
    while i < r {
        var j2 = 0usize
        while j2 < r {
            vs[i * r + j2] = v[sel[i] * q + sel[j2]]
            j2 += 1usize
        }
        i += 1usize
    }
    let (vi, ie) = gp.invert(a, vs, r)
    if ie != ok { ret false }
    var w = 0.0f64
    i = 0usize
    while i < r {
        var j2 = 0usize
        while j2 < r {
            w += coef[sel[i]] * vi[i * r + j2] * coef[sel[j2]]
            j2 += 1usize
        }
        i += 1usize
    }
    out[0usize] = w
    out[1usize] = nmz.pchisq(w, f64(r), false, false)
    ret true
}

// micsr::gauss_laguerre(nq): nodes u and weights w of the nq-point rule for the integral of e^-u f(u) on (0, inf), by Newton's method on the Laguerre polynomial from the usual initial guesses
fn gauss_laguerre(nq: usize, u: []f64, w: []f64) {
    let fn_ = f64(nq)
    var z = 0.0f64
    var i = 0usize
    while i < nq {
        if i == 0usize {
            z = 3.0f64 / (1.0f64 + 2.4f64 * fn_)
        } else if i == 1usize {
            z += 15.0f64 / (1.0f64 + 2.5f64 * fn_)
        } else {
            let ai = f64(i - 1usize)
            z += (1.0f64 + 2.55f64 * ai) / (1.9f64 * ai) * (z - u[i - 2usize])
        }
        var p1 = 0.0f64
        var p2 = 0.0f64
        var pp = 0.0f64
        var it = 0usize
        while it < 200usize {
            p1 = 1.0f64
            p2 = 0.0f64
            var jj = 1usize
            while jj <= nq {
                let p3 = p2
                p2 = p1
                p1 = ((2.0f64 * f64(jj) - 1.0f64 - z) * p2 - (f64(jj) - 1.0f64) * p3) / f64(jj)
                jj += 1usize
            }
            pp = (fn_ * p1 - fn_ * p2) / z
            let z1 = z
            z = z1 - p1 / pp
            it += 1usize
            if math.abs[f64](z - z1) <= 1.0e-15f64 * z && it > 2usize { break }
        }
        // the weight from the polynomials at the converged node
        p1 = 1.0f64
        p2 = 0.0f64
        var jj = 1usize
        while jj <= nq {
            let p3 = p2
            p2 = p1
            p1 = ((2.0f64 * f64(jj) - 1.0f64 - z) * p2 - (f64(jj) - 1.0f64) * p3) / f64(jj)
            jj += 1usize
        }
        pp = (fn_ * p1 - fn_ * p2) / z
        u[i] = z
        w[i] = 0.0f64 - 1.0f64 / (pp * fn_ * p2)
        i += 1usize
    }
}

// halton(prime, len, drop) of mlogit: the van der Corput sequence in base prime from element drop on (element 0 is 0), each digit d at depth t adding d / prime^t
fn halton(prime: usize, len: usize, drop: usize, out: []f64) {
    var m = 0usize
    while m < len {
        var idx = m + drop
        var t = 1.0f64
        var v = 0.0f64
        while idx > 0usize {
            let d = idx % prime
            if d > 0usize { v += f64(d) / math.pow[f64](f64(prime), t) }
            idx = idx / prime
            t += 1.0f64
        }
        out[m] = v
        m += 1usize
    }
}

// a nested (kind 1), heteroskedastic (kind 2) or mixed (kind 3) logit over the design x with choices ch. Nested: nest[a] (0-based, nn nests) of each alternative, the parameters are the k
// coefficients then one inclusive value per nest. Heteroskedastic: gu and gw the quadrature, the parameters are the k coefficients then the scales of alternatives 2..j. Mixed: the columns ridx
// carry normal random coefficients, nd draws per individual, tp choice situations per individual (1 without panel), eta the standard normal draws (nd rows per individual, one column per random
// coefficient), the parameters are the k means then the standard deviations
type Model = struct { kind: usize, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, nest: []const usize, nn: usize, gu: []const f64, gw: []const f64, nd: usize, tp: usize, ridx: []const usize, eta: []const f64, work: []f64 }

fn model_dim(m: *const Model) -> usize {
    if m.kind == 1usize { ret m.k + m.nn }
    if m.kind == 2usize { ret m.k + m.j - 1usize }
    ret m.k + m.ridx.len
}

fn nested_model(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, nest: []const usize, nn: usize) -> (Model, err) {
    let (wk, e1) = mem.alloc[f64](a, nn * k + 1usize)
    var m = Model { kind: 1usize, x: x, ch: ch, n: n, j: j, k: k, nest: nest, nn: nn, gu: x[0usize..0usize], gw: x[0usize..0usize], nd: 0usize, tp: 1usize, ridx: nest[0usize..0usize], eta: x[0usize..0usize], work: wk }
    ret (m, e1)
}

// lnl.hlogit with mlogit's default R = 40 quadrature nodes
fn hetero_model(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize) -> (Model, err) {
    let (q, e1) = mem.alloc[f64](a, 80usize)
    let (wk, e2) = mem.alloc[f64](a, 1usize)
    let (nz, e3) = mem.alloc[usize](a, 1usize)
    var m = Model { kind: 2usize, x: x, ch: ch, n: n, j: j, k: k, nest: nz[0usize..0usize], nn: 0usize, gu: q[0usize..40usize], gw: q[40usize..80usize], nd: 0usize, tp: 1usize, ridx: nz[0usize..0usize], eta: x[0usize..0usize], work: wk }
    if e1 != ok { ret (m, e1) }
    if e3 != ok { ret (m, e3) }
    gauss_laguerre(40usize, q[0usize..40usize], q[40usize..80usize])
    ret (m, e2)
}

// lnl.rlogit with halton = NA: the draws of random coefficient r are qnorm of halton(prime r, nd * individuals, 100), the primes 2, 3, 5, ... in column order; individual i takes rows
// i nd .. (i + 1) nd
fn mixed_model(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, nd: usize, tp: usize, ridx: []const usize) -> (Model, err) {
    let nr = ridx.len
    let ni = n / tp
    let (eta, e1) = mem.alloc[f64](a, nd * ni * nr)
    let (hv, e2) = mem.alloc[f64](a, nd * ni)
    let (wk, e3) = mem.alloc[f64](a, tp * nd * j + nd + 1usize)
    var m = Model { kind: 3usize, x: x, ch: ch, n: n, j: j, k: k, nest: ridx[0usize..0usize], nn: 0usize, gu: x[0usize..0usize], gw: x[0usize..0usize], nd: nd, tp: tp, ridx: ridx, eta: eta, work: wk }
    if e1 != ok { ret (m, e1) }
    if e2 != ok { ret (m, e2) }
    let primes: [10]usize = [10]usize{ 2usize, 3usize, 5usize, 7usize, 11usize, 13usize, 17usize, 19usize, 23usize, 29usize }
    var r = 0usize
    while r < nr {
        halton(primes[r], nd * ni, 100usize, hv)
        var t = 0usize
        while t < nd * ni {
            eta[t * nr + r] = dist.qnorm(hv[t], 0.0f64, 1.0f64, true, false)
            t += 1usize
        }
        r += 1usize
    }
    ret (m, e3)
}

// the nested logit for chooser i: log P of the chosen alternative; its gradient into g (dim) and the probabilities into p (j) when those are non-empty
fn nl_one(m: *Model, i: usize, par: []const f64, g: []f64, p: []f64) -> f64 {
    let j = m.j
    let k = m.k
    var v: [32]f64 = zero
    var ex: [32]f64 = zero
    var sn: [16]f64 = zero
    var pm: [16]f64 = zero
    var vb: [16]f64 = zero
    var a1 = 0usize
    while a1 < j {
        var s = 0.0f64
        var c = 0usize
        while c < k {
            s += m.x[(i * j + a1) * k + c] * par[c]
            c += 1usize
        }
        v[a1] = s
        ex[a1] = math.exp[f64](s / par[k + m.nest[a1]])
        sn[m.nest[a1]] += ex[a1]
        a1 += 1usize
    }
    var den = 0.0f64
    var l = 0usize
    while l < m.nn {
        pm[l] = math.pow[f64](sn[l], par[k + l])
        den += pm[l]
        l += 1usize
    }
    l = 0usize
    while l < m.nn {
        pm[l] = pm[l] / den
        l += 1usize
    }
    if p.len > 0usize {
        a1 = 0usize
        while a1 < j {
            p[a1] = ex[a1] / sn[m.nest[a1]] * pm[m.nest[a1]]
            a1 += 1usize
        }
    }
    let cc = usize(m.ch[i])
    let mc = m.nest[cc]
    let lc = par[k + mc]
    let lp = v[cc] / lc + (lc - 1.0f64) * math.log[f64](sn[mc]) - math.log[f64](den)
    if g.len > 0usize {
        let xb = m.work[0usize..m.nn * k]
        var t = 0usize
        while t < m.nn * k {
            xb[t] = 0.0f64
            t += 1usize
        }
        a1 = 0usize
        while a1 < j {
            let nm = m.nest[a1]
            let wt = ex[a1] / sn[nm]
            vb[nm] += wt * v[a1]
            var c = 0usize
            while c < k {
                xb[nm * k + c] += wt * m.x[(i * j + a1) * k + c]
                c += 1usize
            }
            a1 += 1usize
        }
        var c = 0usize
        while c < k {
            var s = m.x[(i * j + cc) * k + c] / lc + (lc - 1.0f64) / lc * xb[mc * k + c]
            l = 0usize
            while l < m.nn {
                s -= pm[l] * xb[l * k + c]
                l += 1usize
            }
            g[c] = s
            c += 1usize
        }
        l = 0usize
        while l < m.nn {
            let lm = par[k + l]
            let lg = math.log[f64](sn[l])
            var gl = 0.0f64 - pm[l] * (lg - vb[l] / lm)
            if l == mc { gl += 0.0f64 - v[cc] / (lm * lm) + lg - (lm - 1.0f64) * vb[l] / (lm * lm) }
            g[k + l] = gl
            l += 1usize
        }
    }
    ret lp
}

// the heteroskedastic logit for chooser i choosing cc: the probability (not its log), and the gradient of its log into g when g is non-empty
fn hl_one(m: *Model, i: usize, cc: usize, par: []const f64, g: []f64) -> f64 {
    let j = m.j
    let k = m.k
    var v: [32]f64 = zero
    var th: [32]f64 = zero
    var la: [32]f64 = zero
    var al: [32]f64 = zero
    var a1 = 0usize
    while a1 < j {
        var s = 0.0f64
        var c = 0usize
        while c < k {
            s += m.x[(i * j + a1) * k + c] * par[c]
            c += 1usize
        }
        v[a1] = s
        th[a1] = 1.0f64
        if a1 > 0usize { th[a1] = par[k + a1 - 1usize] }
        a1 += 1usize
    }
    var t = 0usize
    while t < g.len {
        g[t] = 0.0f64
        t += 1usize
    }
    var pr = 0.0f64
    var l = 0usize
    while l < m.gu.len {
        let u = m.gu[l]
        let lu = math.log[f64](u)
        var aa = 0.0f64
        a1 = 0usize
        while a1 < j {
            la[a1] = 0.0f64 - (v[cc] - v[a1] - th[cc] * lu) / th[a1]
            al[a1] = math.exp[f64](la[a1])
            aa += al[a1]
            a1 += 1usize
        }
        let wl = m.gw[l] * math.exp[f64](u) * math.exp[f64](0.0f64 - aa)
        pr += wl
        if g.len > 0usize && wl > 0.0f64 {
            var c = 0usize
            while c < k {
                var s = 0.0f64
                a1 = 0usize
                while a1 < j {
                    s += al[a1] * (m.x[(i * j + cc) * k + c] - m.x[(i * j + a1) * k + c]) / th[a1]
                    a1 += 1usize
                }
                g[c] += wl * s
                c += 1usize
            }
            var sl = 0.0f64
            a1 = 0usize
            while a1 < j {
                sl += al[a1] * lu / th[a1]
                a1 += 1usize
            }
            a1 = 1usize
            while a1 < j {
                var tt = al[a1] * la[a1] / th[a1]
                if a1 == cc { tt -= sl }
                g[k + a1 - 1usize] += wl * tt
                a1 += 1usize
            }
        }
        l += 1usize
    }
    t = 0usize
    while t < g.len {
        g[t] = g[t] / pr
        t += 1usize
    }
    ret pr
}

// the mixed logit for individual gi (choice situations gi tp .. (gi + 1) tp): the log of the mean over the draws of the product of the probabilities of the chosen alternatives; the gradient
// of each choice situation (as mlogit's, which sums to the individual's) into gi_ rows of dim when gi_ is non-empty, and the probabilities averaged over the draws into p rows of j when non-empty
fn mx_one(m: *Model, gi: usize, par: []const f64, gr: []f64, p: []f64) -> f64 {
    let j = m.j
    let k = m.k
    let nr = m.ridx.len
    let nd = m.nd
    let tp = m.tp
    let dim = k + nr
    var bb: [64]f64 = zero
    let pa = m.work[0usize..tp * nd * j]
    let pc = m.work[tp * nd * j..tp * nd * j + nd]
    var pmg = 0.0f64
    var r = 0usize
    while r < nd {
        var c = 0usize
        while c < k {
            bb[c] = par[c]
            c += 1usize
        }
        var q = 0usize
        while q < nr {
            bb[m.ridx[q]] = par[m.ridx[q]] + par[k + q] * m.eta[(gi * nd + r) * nr + q]
            q += 1usize
        }
        var prod = 1.0f64
        var t = 0usize
        while t < tp {
            let i = gi * tp + t
            var sm = 0.0f64
            var a1 = 0usize
            while a1 < j {
                var s = 0.0f64
                c = 0usize
                while c < k {
                    s += m.x[(i * j + a1) * k + c] * bb[c]
                    c += 1usize
                }
                let ev = math.exp[f64](s)
                pa[(t * nd + r) * j + a1] = ev
                sm += ev
                a1 += 1usize
            }
            a1 = 0usize
            while a1 < j {
                pa[(t * nd + r) * j + a1] = pa[(t * nd + r) * j + a1] / sm
                a1 += 1usize
            }
            prod = prod * pa[(t * nd + r) * j + usize(m.ch[i])]
            t += 1usize
        }
        pc[r] = prod
        pmg += prod
        r += 1usize
    }
    let tot = pmg
    pmg = pmg / f64(nd)
    if p.len > 0usize {
        var t = 0usize
        while t < tp {
            var a1 = 0usize
            while a1 < j {
                var s = 0.0f64
                r = 0usize
                while r < nd {
                    s += pa[(t * nd + r) * j + a1]
                    r += 1usize
                }
                p[(gi * tp + t) * j + a1] = s / f64(nd)
                a1 += 1usize
            }
            t += 1usize
        }
    }
    if gr.len > 0usize {
        var t = 0usize
        while t < tp {
            let i = gi * tp + t
            let yi = usize(m.ch[i])
            let row = gr[i * dim..i * dim + dim]
            var d = 0usize
            while d < dim {
                row[d] = 0.0f64
                d += 1usize
            }
            r = 0usize
            while r < nd {
                var c = 0usize
                while c < k {
                    var xm = 0.0f64
                    var a1 = 0usize
                    while a1 < j {
                        xm += pa[(t * nd + r) * j + a1] * m.x[(i * j + a1) * k + c]
                        a1 += 1usize
                    }
                    bb[c] = pc[r] * (m.x[(i * j + yi) * k + c] - xm)
                    row[c] += bb[c]
                    c += 1usize
                }
                var q = 0usize
                while q < nr {
                    row[k + q] += bb[m.ridx[q]] * m.eta[(gi * nd + r) * nr + q]
                    q += 1usize
                }
                r += 1usize
            }
            d = 0usize
            while d < dim {
                row[d] = row[d] / tot
                d += 1usize
            }
            t += 1usize
        }
    }
    ret math.log[f64](pmg)
}

// the log-likelihood of the model at par; the gradient of each choice situation into gi (n rows of model_dim) and the fitted probabilities into prob (n rows of j) when those are non-empty
fn model_ll(m: *Model, par: []const f64, gi: []f64, prob: []f64) -> f64 {
    let dim = model_dim(m)
    var ll = 0.0f64
    if m.kind == 3usize {
        var g = 0usize
        while g < m.n / m.tp {
            ll += mx_one(m, g, par, gi, prob)
            g += 1usize
        }
        ret ll
    }
    var i = 0usize
    while i < m.n {
        var g = gi[0usize..0usize]
        if gi.len > 0usize { g = gi[i * dim..i * dim + dim] }
        if m.kind == 1usize {
            var p = prob[0usize..0usize]
            if prob.len > 0usize { p = prob[i * m.j..i * m.j + m.j] }
            ll += nl_one(m, i, par, g, p)
        } else {
            ll += math.log[f64](hl_one(m, i, usize(m.ch[i]), par, g))
            if prob.len > 0usize {
                var a1 = 0usize
                while a1 < m.j {
                    prob[i * m.j + a1] = hl_one(m, i, a1, par, g[0usize..0usize])
                    a1 += 1usize
                }
            }
        }
        i += 1usize
    }
    ret ll
}

fn sum_rows(gi: []const f64, n: usize, dim: usize, gr: []f64) {
    var d = 0usize
    while d < dim {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += gi[i * dim + d]
            i += 1usize
        }
        gr[d] = s
        d += 1usize
    }
}

// the outer product of the gradients, sum_i g_i g_i' (dim by dim into b)
fn opg(gi: []const f64, n: usize, dim: usize, b: []f64) {
    var p = 0usize
    while p < dim {
        var q = 0usize
        while q < dim {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += gi[i * dim + p] * gi[i * dim + q]
                i += 1usize
            }
            b[p * dim + q] = s
            q += 1usize
        }
        p += 1usize
    }
}

// whether the scales of a heteroskedastic logit are positive: past zero its quadrature integrand grows without bound, and a step that strays there (R's path never does) would be taken
fn scales_positive(m: *const Model, par: []const f64) -> bool {
    if m.kind != 2usize { ret true }
    var d = m.k
    while d < par.len {
        if par[d] <= 0.0f64 { ret false }
        d += 1usize
    }
    ret true
}

// fits the model to its maximum from mlogit's start (the conditional logit on the design, inclusive values and scales 1, standard deviations 0.1) by mlogit.optim's BFGS (the inverse Hessian
// started from the outer product of the gradients, the step halved from 1 until the log-likelihood does not fall, stopping when g' H^-1 g < 1e-20), which keeps R's path to the same one of the
// optima of a simulated likelihood; then Newton on the Hessian differenced from the analytic gradient, past the point where the log-likelihood can still tell the steps apart. par (model_dim)
// receives the estimates, the log-likelihood is returned
fn fit_model(a: *mem.Arena, m: *Model, par: []f64) -> (f64, err) {
    let k = m.k
    let n = m.n
    let dim = model_dim(m)
    let (st, e0) = mem.alloc[f64](a, 2usize * k + 1usize)
    if e0 != ok { ret (0.0f64, e0) }
    let e1 = clogit(a, m.x, m.ch, n, m.j, k, false, st)
    if e1 != ok { ret (0.0f64, e1) }
    var d = 0usize
    while d < dim {
        par[d] = 1.0f64
        if m.kind == 3usize { par[d] = 0.1f64 }
        if d < k { par[d] = st[d] }
        d += 1usize
    }
    let (gi, e2) = mem.alloc[f64](a, 2usize * n * dim)
    let (wk, e3) = mem.alloc[f64](a, 2usize * dim * dim + 5usize * dim)
    if e2 != ok { ret (0.0f64, e2) }
    if e3 != ok { ret (0.0f64, e3) }
    let g2 = gi[n * dim..2usize * n * dim]
    let b = wk[0usize..dim * dim]
    let hs = wk[dim * dim..2usize * dim * dim]
    let gr = wk[2usize * dim * dim..2usize * dim * dim + dim]
    let dir = wk[2usize * dim * dim + dim..2usize * dim * dim + 2usize * dim]
    let tr = wk[2usize * dim * dim + 2usize * dim..2usize * dim * dim + 3usize * dim]
    let ga = wk[2usize * dim * dim + 3usize * dim..2usize * dim * dim + 4usize * dim]
    let gb = wk[2usize * dim * dim + 4usize * dim..2usize * dim * dim + 5usize * dim]
    let none = gi[0usize..0usize]
    var ll = model_ll(m, par, gi[0usize..n * dim], none)
    let (bw, e4) = mem.alloc[f64](a, dim * dim + 3usize * dim)
    if e4 != ok { ret (0.0f64, e4) }
    let og = bw[dim * dim..dim * dim + dim]
    let yv = bw[dim * dim + dim..dim * dim + 2usize * dim]
    let hy = bw[dim * dim + 2usize * dim..dim * dim + 3usize * dim]
    sum_rows(gi, n, dim, gr)
    opg(gi, n, dim, b)
    let (h0, he0) = gp.invert(a, b, dim)
    if he0 != ok { ret (ll, he0) }
    let hm = bw[0usize..dim * dim]
    d = 0usize
    while d < dim * dim {
        hm[d] = h0[d]
        d += 1usize
    }
    var bit = 0usize
    while bit < 2000usize {
        // R minimises -ll: its gradient is -gr and its direction H^-1 gr
        d = 0usize
        while d < dim {
            var s = 0.0f64
            var q = 0usize
            while q < dim {
                s += hm[d * dim + q] * gr[q]
                q += 1usize
            }
            dir[d] = s
            d += 1usize
        }
        var step = 1.0f64
        var found = false
        while step >= 1.0e-10f64 {
            d = 0usize
            while d < dim {
                tr[d] = par[d] + step * dir[d]
                d += 1usize
            }
            let lt = model_ll(m, tr, none, none)
            if lt >= ll && scales_positive(m, tr) {
                ll = lt
                found = true
                break
            }
            step = step / 2.0f64
        }
        if !found { break }
        d = 0usize
        while d < dim {
            og[d] = gr[d]
            par[d] = tr[d]
            d += 1usize
        }
        ll = model_ll(m, par, gi[0usize..n * dim], none)
        sum_rows(gi, n, dim, gr)
        // y = g - oldg in R's sign (the gradient of -ll), incr = step d
        var sy = 0.0f64
        var chi = 0.0f64
        d = 0usize
        while d < dim {
            yv[d] = og[d] - gr[d]
            sy += yv[d] * step * dir[d]
            chi += dir[d] * og[d]
            d += 1usize
        }
        var yhy = 0.0f64
        d = 0usize
        while d < dim {
            var s = 0.0f64
            var q = 0usize
            while q < dim {
                s += hm[d * dim + q] * yv[q]
                q += 1usize
            }
            hy[d] = s
            yhy += yv[d] * s
            d += 1usize
        }
        d = 0usize
        while d < dim {
            var q = 0usize
            while q < dim {
                let id = step * dir[d]
                let iq = step * dir[q]
                hm[d * dim + q] = hm[d * dim + q] + id * iq * (sy + yhy) / (sy * sy) - (hy[d] * iq + id * hy[q]) / sy
                q += 1usize
            }
            d += 1usize
        }
        bit += 1usize
        if math.abs[f64](chi) < 1.0e-20f64 { break }
    }
    var it = 0usize
    var last = 1.0e300f64
    var floor = 0usize
    while it < 500usize {
        let mk = mem.mark(a)
        sum_rows(gi, n, dim, gr)
        opg(gi, n, dim, b)
        var chi = 0.0f64
        var newton = false
        let (bi, be) = gp.invert(a, b, dim)
        if be != ok { ret (ll, be) }
        d = 0usize
        while d < dim {
            var s = 0.0f64
            var q = 0usize
            while q < dim {
                s += bi[d * dim + q] * gr[q]
                q += 1usize
            }
            dir[d] = s
            chi += s * gr[d]
            d += 1usize
        }
        if chi < 0.1f64 {
            // Newton: the information -H from central differences of the analytic gradient
            d = 0usize
            while d < dim {
                var q = 0usize
                while q < dim {
                    tr[q] = par[q]
                    q += 1usize
                }
                let hh = 1.0e-5f64 * (1.0f64 + math.abs[f64](par[d]))
                tr[d] = par[d] + hh
                let _ = model_ll(m, tr, g2, none)
                sum_rows(g2, n, dim, ga)
                tr[d] = par[d] - hh
                let _ = model_ll(m, tr, g2, none)
                sum_rows(g2, n, dim, gb)
                q = 0usize
                while q < dim {
                    hs[q * dim + d] = (gb[q] - ga[q]) / (2.0f64 * hh)
                    q += 1usize
                }
                d += 1usize
            }
            d = 0usize
            while d < dim {
                var q = d + 1usize
                while q < dim {
                    let av = 0.5f64 * (hs[d * dim + q] + hs[q * dim + d])
                    hs[d * dim + q] = av
                    hs[q * dim + d] = av
                    q += 1usize
                }
                d += 1usize
            }
            let (hi, he) = gp.invert(a, hs, dim)
            if he == ok {
                var cn = 0.0f64
                d = 0usize
                while d < dim {
                    var s = 0.0f64
                    var q = 0usize
                    while q < dim {
                        s += hi[d * dim + q] * gr[q]
                        q += 1usize
                    }
                    tr[d] = s
                    cn += s * gr[d]
                    d += 1usize
                }
                if cn > 0.0f64 {
                    chi = cn
                    newton = true
                    d = 0usize
                    while d < dim {
                        dir[d] = tr[d]
                        d += 1usize
                    }
                }
            }
        }
        mem.reset(a, mk)
        if chi < 1.0e-24f64 { break }
        var step = 1.0f64
        var moved = false
        if newton && chi < 1.0e-8f64 {
            // below this the log-likelihood cannot tell the steps apart (its gain is chi / 2): full Newton steps until the gradient stops shrinking
            if chi >= 0.25f64 * last {
                floor += 1usize
                if floor >= 3usize { break }
            }
            last = chi
            d = 0usize
            while d < dim {
                par[d] = par[d] + dir[d]
                d += 1usize
            }
            step = 0.0f64
            moved = true
        }
        while step > 1.0e-12f64 {
            d = 0usize
            while d < dim {
                tr[d] = par[d] + step * dir[d]
                d += 1usize
            }
            let lt = model_ll(m, tr, none, none)
            if lt >= ll && scales_positive(m, tr) {
                d = 0usize
                while d < dim {
                    par[d] = tr[d]
                    d += 1usize
                }
                ll = lt
                moved = true
                break
            }
            step = step / 2.0f64
        }
        if !moved { break }
        ll = model_ll(m, par, gi[0usize..n * dim], none)
        it += 1usize
    }
    ret (ll, ok)
}

// the standard errors of the fitted parameters par from the inverse of the outer product of the gradients of the choice situations, as mlogit's vcov for these models; false when singular
fn model_se(a: *mem.Arena, m: *Model, par: []const f64, se: []f64) -> bool {
    let dim = model_dim(m)
    let (gi, e1) = mem.alloc[f64](a, m.n * dim + dim * dim)
    if e1 != ok { ret false }
    let b = gi[m.n * dim..m.n * dim + dim * dim]
    let _ = model_ll(m, par, gi[0usize..m.n * dim], gi[0usize..0usize])
    opg(gi, m.n, dim, b)
    let (bi, be) = gp.invert(a, b, dim)
    if be != ok { ret false }
    var d = 0usize
    while d < dim {
        if bi[d * dim + d] <= 0.0f64 { ret false }
        se[d] = math.sqrt[f64](bi[d * dim + d])
        d += 1usize
    }
    ret true
}
