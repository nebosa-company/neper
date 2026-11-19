// R VGAM::vglm with the cumulative logit family and parallel = TRUE (the proportional odds model): P(Y <= j | x) = logistic(alpha_j + x' beta), j = 1 .. J - 1 for an ordered response with J levels. Fisher scoring
// (Newton with the expected information, the exact sum over the outcomes of the outer products of their scores) from the marginal logits and beta = 0; the log-likelihood and the standard errors from the same expected
// information, which is what VGAM's vcov uses.
//
// Not here: other links and families, non-parallel and partial odds, factors in the formula, weights and offsets, vgam smoothers.

use e.algo.stat.quantreg as qrb
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.opt as opt
use e.mem

// the link's inverse and its density: lk 0 logit, 1 probit, 2 cloglog
fn lg(t: f64, lk: usize) -> f64 {
    if lk == 1usize { ret dist.pnorm(t, 0.0f64, 1.0f64, true, false) }
    if lk == 2usize { ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](t)) }
    ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
}

fn lgd(t: f64, f: f64, lk: usize) -> f64 {
    if lk == 1usize { ret dist.dnorm(t, 0.0f64, 1.0f64, false) }
    if lk == 2usize { ret math.exp[f64](t) * (1.0f64 - f) }
    ret f * (1.0f64 - f)
}

// the cumulative probabilities F_k = logistic(alpha_k + eta) for k = 0 .. J - 2 with F_-1 = 0 and F_(J-1) = 1 held implicit
fn cum_obs(par: []const f64, x: []const f64, p: usize, jn: usize, cls: usize, lk: usize, sc: []f64) -> f64 {
    // the outcome cls of one case: returns its probability and writes the score (length jn - 1 + p) of log p
    let na = jn - 1usize
    var eta = 0.0f64
    var t = 0usize
    while t < p {
        eta += x[t] * par[na + t]
        t += 1usize
    }
    var fu = 1.0f64
    var fl = 0.0f64
    var gu = 0.0f64
    var gl = 0.0f64
    if cls < na {
        fu = lg(par[cls] + eta, lk)
        gu = lgd(par[cls] + eta, fu, lk)
    }
    if cls > 0usize {
        fl = lg(par[cls - 1usize] + eta, lk)
        gl = lgd(par[cls - 1usize] + eta, fl, lk)
    }
    let pr = fu - fl
    t = 0usize
    while t < na + p {
        sc[t] = 0.0f64
        t += 1usize
    }
    if cls < na { sc[cls] = gu / pr }
    if cls > 0usize { sc[cls - 1usize] = 0.0f64 - gl / pr }
    t = 0usize
    while t < p {
        sc[na + t] = x[t] * (gu - gl) / pr
        t += 1usize
    }
    ret pr
}

// the model for y (0-based class codes 0 .. jn - 1) on x (n by p row-major, no intercept column). out: alpha (jn - 1), beta (p), the log-likelihood, then the standard errors of alpha and beta; false when it fails
fn cum_logit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, jn: usize, lk: usize, out: []f64) -> bool {
    let na = jn - 1usize
    let q = na + p
    let (par, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, q * q)
    let (mat, e4) = mem.alloc[f64](a, q * q)
    let (step, e5) = mem.alloc[f64](a, q)
    let (trial, e6) = mem.alloc[f64](a, q)
    let (sc, e7) = mem.alloc[f64](a, q)
    let (cnt, e8) = mem.alloc[f64](a, jn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret false }
    var k = 0usize
    while k < jn {
        cnt[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[usize(y[i])] += 1.0f64
        i += 1usize
    }
    var cum = 0.0f64
    k = 0usize
    while k < na {
        cum += cnt[k]
        let pk = cum / f64(n)
        par[k] = math.log[f64](pk / (1.0f64 - pk))
        k += 1usize
    }
    k = 0usize
    while k < p {
        par[na + k] = 0.0f64
        k += 1usize
    }
    var ll = 0.0f64 - 1.0e300f64
    var it = 0usize
    while it < 100usize {
        var z = 0usize
        while z < q * q {
            info[z] = 0.0f64
            z += 1usize
        }
        z = 0usize
        while z < q {
            gr[z] = 0.0f64
            z += 1usize
        }
        var cur = 0.0f64
        i = 0usize
        while i < n {
            let xi = x[i * p..(i + 1usize) * p]
            let pr = cum_obs(par, xi, p, jn, usize(y[i]), lk, sc)
            cur += math.log[f64](pr)
            var u = 0usize
            while u < q {
                gr[u] += sc[u]
                u += 1usize
            }
            // expected information: sum over the outcomes of p_k s_k s_k'
            var oc = 0usize
            while oc < jn {
                var sc2: [32]f64 = zero
                let po = cum_obs(par, xi, p, jn, oc, lk, sc2[0usize..q])
                var u1 = 0usize
                while u1 < q {
                    var u2 = 0usize
                    while u2 < q {
                        info[u1 * q + u2] += po * sc2[u1] * sc2[u2]
                        u2 += 1usize
                    }
                    u1 += 1usize
                }
                oc += 1usize
            }
            i += 1usize
        }
        if it > 0usize && math.abs[f64](cur - ll) < 1.0e-13f64 * (1.0f64 + math.abs[f64](cur)) {
            ll = cur
            break
        }
        ll = cur
        z = 0usize
        while z < q * q {
            mat[z] = info[z]
            z += 1usize
        }
        z = 0usize
        while z < q {
            step[z] = gr[z]
            z += 1usize
        }
        if !qrb.solve_dense(mat, step, q) { ret false }
        var h = 1.0f64
        var tries = 0usize
        while tries < 30usize {
            z = 0usize
            while z < q {
                trial[z] = par[z] + h * step[z]
                z += 1usize
            }
            var ok2 = true
            k = 1usize
            while k < na {
                if trial[k] <= trial[k - 1usize] { ok2 = false }
                k += 1usize
            }
            var tl = 0.0f64
            if ok2 {
                i = 0usize
                while i < n {
                    let pr = cum_obs(trial, x[i * p..(i + 1usize) * p], p, jn, usize(y[i]), lk, sc)
                    if pr <= 0.0f64 { ok2 = false }
                    if ok2 { tl += math.log[f64](pr) }
                    i += 1usize
                }
            }
            if ok2 && tl >= ll - 1.0e-12f64 { break }
            h = h / 2.0f64
            tries += 1usize
        }
        z = 0usize
        while z < q {
            par[z] += h * step[z]
            z += 1usize
        }
        it += 1usize
    }
    // the standard errors from the expected information at the end (info is that of the last evaluated point)
    var j2 = 0usize
    while j2 < q {
        var r = 0usize
        while r < q * q {
            mat[r] = info[r]
            r += 1usize
        }
        r = 0usize
        while r < q {
            step[r] = 0.0f64
            r += 1usize
        }
        step[j2] = 1.0f64
        if !qrb.solve_dense(mat, step, q) { ret false }
        out[q + 1usize + j2] = math.sqrt[f64](step[j2])
        j2 += 1usize
    }
    j2 = 0usize
    while j2 < q {
        out[j2] = par[j2]
        j2 += 1usize
    }
    out[q] = ll
    ret true
}

// vglm(y ~ x, multinomial) with the last level as the reference: class k (0 .. jn - 2) has an intercept and p slopes, laid out class by class (k * (p + 1) + 0 is its intercept). Newton on the exact (concave) log-likelihood; out: the
// q = (jn - 1)(p + 1) coefficients, the log-likelihood, then the q standard errors from the information; false when singular
fn multinom(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, jn: usize, out: []f64) -> bool {
    let na = jn - 1usize
    let p1 = p + 1usize
    let q = na * p1
    let (par, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, q * q)
    let (mat, e4) = mem.alloc[f64](a, q * q)
    let (step, e5) = mem.alloc[f64](a, q)
    let (pr, e6) = mem.alloc[f64](a, jn)
    let (zv, e7) = mem.alloc[f64](a, p1)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret false }
    var t = 0usize
    while t < q {
        par[t] = 0.0f64
        t += 1usize
    }
    var ll = 0.0f64 - 1.0e300f64
    var it = 0usize
    while it < 100usize {
        t = 0usize
        while t < q * q {
            info[t] = 0.0f64
            t += 1usize
        }
        t = 0usize
        while t < q {
            gr[t] = 0.0f64
            t += 1usize
        }
        var cur = 0.0f64
        var i = 0usize
        while i < n {
            zv[0usize] = 1.0f64
            t = 0usize
            while t < p {
                zv[1usize + t] = x[i * p + t]
                t += 1usize
            }
            var mx = 0.0f64
            var k = 0usize
            while k < na {
                var e = 0.0f64
                t = 0usize
                while t < p1 {
                    e += zv[t] * par[k * p1 + t]
                    t += 1usize
                }
                pr[k] = e
                if e > mx { mx = e }
                k += 1usize
            }
            pr[na] = 0.0f64
            var sm = math.exp[f64](0.0f64 - mx)
            k = 0usize
            while k < na {
                pr[k] = math.exp[f64](pr[k] - mx)
                sm += pr[k]
                k += 1usize
            }
            pr[na] = math.exp[f64](0.0f64 - mx)
            k = 0usize
            while k < jn {
                pr[k] = pr[k] / sm
                k += 1usize
            }
            let yc = usize(y[i])
            cur += math.log[f64](pr[yc])
            k = 0usize
            while k < na {
                var ind = 0.0f64
                if yc == k { ind = 1.0f64 }
                t = 0usize
                while t < p1 {
                    gr[k * p1 + t] += (ind - pr[k]) * zv[t]
                    t += 1usize
                }
                var l = 0usize
                while l < na {
                    var w = 0.0f64 - pr[k] * pr[l]
                    if l == k { w += pr[k] }
                    var u = 0usize
                    while u < p1 {
                        var v = 0usize
                        while v < p1 {
                            info[(k * p1 + u) * q + l * p1 + v] += w * zv[u] * zv[v]
                            v += 1usize
                        }
                        u += 1usize
                    }
                    l += 1usize
                }
                k += 1usize
            }
            i += 1usize
        }
        if it > 0usize && math.abs[f64](cur - ll) < 1.0e-13f64 * (1.0f64 + math.abs[f64](cur)) {
            ll = cur
            break
        }
        ll = cur
        t = 0usize
        while t < q * q {
            mat[t] = info[t]
            t += 1usize
        }
        t = 0usize
        while t < q {
            step[t] = gr[t]
            t += 1usize
        }
        if !qrb.solve_dense(mat, step, q) { ret false }
        t = 0usize
        while t < q {
            par[t] += step[t]
            t += 1usize
        }
        it += 1usize
    }
    var c = 0usize
    while c < q {
        t = 0usize
        while t < q * q {
            mat[t] = info[t]
            t += 1usize
        }
        t = 0usize
        while t < q {
            step[t] = 0.0f64
            t += 1usize
        }
        step[c] = 1.0f64
        if !qrb.solve_dense(mat, step, q) { ret false }
        out[q + 1usize + c] = math.sqrt[f64](step[c])
        c += 1usize
    }
    t = 0usize
    while t < q {
        out[t] = par[t]
        t += 1usize
    }
    out[q] = ll
    ret true
}

// the outcome cls of one case under the non-parallel cumulative model (class k has its own intercept and p slopes at k * (p + 1)): its probability, and the score of log p written to sc (length (jn - 1)(p + 1))
fn cum_np_obs(par: []const f64, x: []const f64, p: usize, jn: usize, cls: usize, lk: usize, sc: []f64) -> f64 {
    let na = jn - 1usize
    let p1 = p + 1usize
    var t = 0usize
    while t < na * p1 {
        sc[t] = 0.0f64
        t += 1usize
    }
    var fu = 1.0f64
    var fl = 0.0f64
    var gu = 0.0f64
    var gl = 0.0f64
    var eu = 0.0f64
    var el = 0.0f64
    if cls < na {
        eu = par[cls * p1]
        t = 0usize
        while t < p {
            eu += x[t] * par[cls * p1 + 1usize + t]
            t += 1usize
        }
        fu = lg(eu, lk)
        gu = lgd(eu, fu, lk)
    }
    if cls > 0usize {
        let k = cls - 1usize
        el = par[k * p1]
        t = 0usize
        while t < p {
            el += x[t] * par[k * p1 + 1usize + t]
            t += 1usize
        }
        fl = lg(el, lk)
        gl = lgd(el, fl, lk)
    }
    let pr = fu - fl
    if cls < na {
        sc[cls * p1] = gu / pr
        t = 0usize
        while t < p {
            sc[cls * p1 + 1usize + t] = gu * x[t] / pr
            t += 1usize
        }
    }
    if cls > 0usize {
        let k = cls - 1usize
        sc[k * p1] = 0.0f64 - gl / pr
        t = 0usize
        while t < p {
            sc[k * p1 + 1usize + t] = 0.0f64 - gl * x[t] / pr
            t += 1usize
        }
    }
    ret pr
}

// vglm(y ~ x, cumulative(parallel = FALSE)): every cumulative split has its own intercept and slopes. Fisher scoring as cum_logit, started at the marginal links with zero slopes; out: the q = (jn - 1)(p + 1) coefficients
// class by class, the log-likelihood, then the q standard errors; false when it fails
fn cum_np(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, jn: usize, lk: usize, out: []f64) -> bool {
    let na = jn - 1usize
    let p1 = p + 1usize
    let q = na * p1
    let (par, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, q * q)
    let (mat, e4) = mem.alloc[f64](a, q * q)
    let (step, e5) = mem.alloc[f64](a, q)
    let (trial, e6) = mem.alloc[f64](a, q)
    let (sc, e7) = mem.alloc[f64](a, q)
    let (sc2, e8) = mem.alloc[f64](a, q)
    let (cnt, e9) = mem.alloc[f64](a, jn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret false }
    var k = 0usize
    while k < jn {
        cnt[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[usize(y[i])] += 1.0f64
        i += 1usize
    }
    var cum = 0.0f64
    k = 0usize
    while k < q {
        par[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < na {
        cum += cnt[k]
        let pk = cum / f64(n)
        // marginal start on the logit scale, rescaled for the other links by a crude monotone map
        var v = math.log[f64](pk / (1.0f64 - pk))
        if lk == 1usize { v = v * 0.6f64 }
        if lk == 2usize { v = math.log[f64](0.0f64 - math.log[f64](1.0f64 - pk)) }
        par[k * p1] = v
        k += 1usize
    }
    var ll = 0.0f64 - 1.0e300f64
    var it = 0usize
    while it < 200usize {
        var z = 0usize
        while z < q * q {
            info[z] = 0.0f64
            z += 1usize
        }
        z = 0usize
        while z < q {
            gr[z] = 0.0f64
            z += 1usize
        }
        var cur = 0.0f64
        i = 0usize
        while i < n {
            let xi = x[i * p..(i + 1usize) * p]
            let pr = cum_np_obs(par, xi, p, jn, usize(y[i]), lk, sc)
            if pr <= 0.0f64 { ret false }
            cur += math.log[f64](pr)
            var u = 0usize
            while u < q {
                gr[u] += sc[u]
                u += 1usize
            }
            var oc = 0usize
            while oc < jn {
                let po = cum_np_obs(par, xi, p, jn, oc, lk, sc2)
                var u1 = 0usize
                while u1 < q {
                    var u2 = 0usize
                    while u2 < q {
                        info[u1 * q + u2] += po * sc2[u1] * sc2[u2]
                        u2 += 1usize
                    }
                    u1 += 1usize
                }
                oc += 1usize
            }
            i += 1usize
        }
        if it > 0usize && math.abs[f64](cur - ll) < 1.0e-13f64 * (1.0f64 + math.abs[f64](cur)) {
            ll = cur
            break
        }
        ll = cur
        z = 0usize
        while z < q * q {
            mat[z] = info[z]
            z += 1usize
        }
        z = 0usize
        while z < q {
            step[z] = gr[z]
            z += 1usize
        }
        if !qrb.solve_dense(mat, step, q) { ret false }
        var h = 1.0f64
        var tries = 0usize
        while tries < 40usize {
            z = 0usize
            while z < q {
                trial[z] = par[z] + h * step[z]
                z += 1usize
            }
            var ok2 = true
            var tl = 0.0f64
            i = 0usize
            while i < n && ok2 {
                let pr = cum_np_obs(trial, x[i * p..(i + 1usize) * p], p, jn, usize(y[i]), lk, sc)
                if pr <= 0.0f64 { ok2 = false }
                if ok2 { tl += math.log[f64](pr) }
                i += 1usize
            }
            if ok2 && tl >= ll - 1.0e-12f64 { break }
            h = h / 2.0f64
            tries += 1usize
        }
        z = 0usize
        while z < q {
            par[z] += h * step[z]
            z += 1usize
        }
        it += 1usize
    }
    var c = 0usize
    while c < q {
        var r = 0usize
        while r < q * q {
            mat[r] = info[r]
            r += 1usize
        }
        r = 0usize
        while r < q {
            step[r] = 0.0f64
            r += 1usize
        }
        step[c] = 1.0f64
        if !qrb.solve_dense(mat, step, q) { ret false }
        out[q + 1usize + c] = math.sqrt[f64](step[c])
        c += 1usize
    }
    c = 0usize
    while c < q {
        out[c] = par[c]
        c += 1usize
    }
    out[q] = ll
    ret true
}

// vglm(y ~ x, acat(parallel = TRUE)) (loglink: P(Y = j + 1) / P(Y = j) = exp(alpha_j + x' beta)): the unnormalised log probability of class c is u_c = sum over l < c of (alpha_l + x' beta), so its derivative is 1 for each
// alpha_l with l < c and c x for beta. An exponential family, so Newton on the exact information (the covariance of that derivative under the class probabilities) is Fisher scoring. out: alpha (jn - 1), beta (p), the
// log-likelihood, then the standard errors in the same order; false when singular
fn acat_par(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, jn: usize, out: []f64) -> bool {
    let na = jn - 1usize
    let q = na + p
    let (par, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, q * q)
    let (mat, e4) = mem.alloc[f64](a, q * q)
    let (step, e5) = mem.alloc[f64](a, q)
    let (pr, e6) = mem.alloc[f64](a, jn)
    let (dm, e7) = mem.alloc[f64](a, jn * q)
    let (mean, e8) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret false }
    var t = 0usize
    while t < q {
        par[t] = 0.0f64
        t += 1usize
    }
    var ll = 0.0f64 - 1.0e300f64
    var it = 0usize
    while it < 100usize {
        t = 0usize
        while t < q * q {
            info[t] = 0.0f64
            t += 1usize
        }
        t = 0usize
        while t < q {
            gr[t] = 0.0f64
            t += 1usize
        }
        var cur = 0.0f64
        var i = 0usize
        while i < n {
            var eta = 0.0f64
            t = 0usize
            while t < p {
                eta += x[i * p + t] * par[na + t]
                t += 1usize
            }
            var u = 0.0f64
            var mx = 0.0f64
            var c = 0usize
            while c < jn {
                if c > 0usize { u += par[c - 1usize] + eta }
                pr[c] = u
                if u > mx { mx = u }
                c += 1usize
            }
            var sm = 0.0f64
            c = 0usize
            while c < jn {
                pr[c] = math.exp[f64](pr[c] - mx)
                sm += pr[c]
                c += 1usize
            }
            c = 0usize
            while c < jn {
                pr[c] = pr[c] / sm
                var l = 0usize
                while l < na {
                    dm[c * q + l] = 0.0f64
                    if l < c { dm[c * q + l] = 1.0f64 }
                    l += 1usize
                }
                t = 0usize
                while t < p {
                    dm[c * q + na + t] = f64(c) * x[i * p + t]
                    t += 1usize
                }
                c += 1usize
            }
            t = 0usize
            while t < q {
                mean[t] = 0.0f64
                t += 1usize
            }
            c = 0usize
            while c < jn {
                t = 0usize
                while t < q {
                    mean[t] += pr[c] * dm[c * q + t]
                    t += 1usize
                }
                c += 1usize
            }
            let yc = usize(y[i])
            cur += math.log[f64](pr[yc])
            t = 0usize
            while t < q {
                gr[t] += dm[yc * q + t] - mean[t]
                t += 1usize
            }
            c = 0usize
            while c < jn {
                var u1 = 0usize
                while u1 < q {
                    var u2 = 0usize
                    while u2 < q {
                        info[u1 * q + u2] += pr[c] * dm[c * q + u1] * dm[c * q + u2]
                        u2 += 1usize
                    }
                    u1 += 1usize
                }
                c += 1usize
            }
            var u1 = 0usize
            while u1 < q {
                var u2 = 0usize
                while u2 < q {
                    info[u1 * q + u2] -= mean[u1] * mean[u2]
                    u2 += 1usize
                }
                u1 += 1usize
            }
            i += 1usize
        }
        if it > 0usize && math.abs[f64](cur - ll) < 1.0e-13f64 * (1.0f64 + math.abs[f64](cur)) {
            ll = cur
            break
        }
        ll = cur
        t = 0usize
        while t < q * q {
            mat[t] = info[t]
            t += 1usize
        }
        t = 0usize
        while t < q {
            step[t] = gr[t]
            t += 1usize
        }
        if !qrb.solve_dense(mat, step, q) { ret false }
        t = 0usize
        while t < q {
            par[t] += step[t]
            t += 1usize
        }
        it += 1usize
    }
    var cc = 0usize
    while cc < q {
        t = 0usize
        while t < q * q {
            mat[t] = info[t]
            t += 1usize
        }
        t = 0usize
        while t < q {
            step[t] = 0.0f64
            t += 1usize
        }
        step[cc] = 1.0f64
        if !qrb.solve_dense(mat, step, q) { ret false }
        out[q + 1usize + cc] = math.sqrt[f64](step[cc])
        cc += 1usize
    }
    t = 0usize
    while t < q {
        out[t] = par[t]
        t += 1usize
    }
    out[q] = ll
    ret true
}

// the outcome cls of one case under the continuation-ratio models with shared slopes: delta_l = linkinv(alpha_l + x' beta); vr 0 (sratio) P(Y = l | Y >= l) = delta_l, vr 1 (cratio) P(Y > l | Y >= l) = delta_l. Returns its probability and writes
// the score (length jn - 1 + p) of log p
fn cr_obs(par: []const f64, x: []const f64, p: usize, jn: usize, cls: usize, lk: usize, vr: usize, sc: []f64) -> f64 {
    let na = jn - 1usize
    var eta = 0.0f64
    var t = 0usize
    while t < p {
        eta += x[t] * par[na + t]
        t += 1usize
    }
    t = 0usize
    while t < na + p {
        sc[t] = 0.0f64
        t += 1usize
    }
    var lp = 0.0f64
    var l = 0usize
    while l <= cls && l < jn {
        if l < na {
            let d = lg(par[l] + eta, lk)
            let g = lgd(par[l] + eta, d, lk)
            // factor: (1 - delta) while below the class, the stop probability at it (nothing at the last class)
            var dl = 0.0f64
            let stop = l >= cls
            if stop {
                if vr == 0usize { dl = g / d } else { dl = 0.0f64 - g / (1.0f64 - d) }
                if vr == 0usize { lp += math.log[f64](d) } else { lp += math.log[f64](1.0f64 - d) }
            } else {
                if vr == 0usize { dl = 0.0f64 - g / (1.0f64 - d) } else { dl = g / d }
                if vr == 0usize { lp += math.log[f64](1.0f64 - d) } else { lp += math.log[f64](d) }
            }
            sc[l] += dl
            t = 0usize
            while t < p {
                sc[na + t] += dl * x[t]
                t += 1usize
            }
        }
        l += 1usize
    }
    ret math.exp[f64](lp)
}

fn cr_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, jn: usize, lk: usize, vr: usize, out: []f64) -> bool {
    let na = jn - 1usize
    let q = na + p
    let (par, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, q * q)
    let (mat, e4) = mem.alloc[f64](a, q * q)
    let (step, e5) = mem.alloc[f64](a, q)
    let (trial, e6) = mem.alloc[f64](a, q)
    let (sc, e7) = mem.alloc[f64](a, q)
    let (cnt, e8) = mem.alloc[f64](a, jn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret false }
    var k = 0usize
    while k < jn {
        cnt[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[usize(y[i])] += 1.0f64
        i += 1usize
    }
    k = 0usize
    while k < na {
        par[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < p {
        par[na + k] = 0.0f64
        k += 1usize
    }
    var ll = 0.0f64 - 1.0e300f64
    var it = 0usize
    while it < 100usize {
        var z = 0usize
        while z < q * q {
            info[z] = 0.0f64
            z += 1usize
        }
        z = 0usize
        while z < q {
            gr[z] = 0.0f64
            z += 1usize
        }
        var cur = 0.0f64
        i = 0usize
        while i < n {
            let xi = x[i * p..(i + 1usize) * p]
            let pr = cr_obs(par, xi, p, jn, usize(y[i]), lk, vr, sc)
            cur += math.log[f64](pr)
            var u = 0usize
            while u < q {
                gr[u] += sc[u]
                u += 1usize
            }
            // expected information: sum over the outcomes of p_k s_k s_k'
            var oc = 0usize
            while oc < jn {
                var sc2: [32]f64 = zero
                let po = cr_obs(par, xi, p, jn, oc, lk, vr, sc2[0usize..q])
                var u1 = 0usize
                while u1 < q {
                    var u2 = 0usize
                    while u2 < q {
                        info[u1 * q + u2] += po * sc2[u1] * sc2[u2]
                        u2 += 1usize
                    }
                    u1 += 1usize
                }
                oc += 1usize
            }
            i += 1usize
        }
        if it > 0usize && math.abs[f64](cur - ll) < 1.0e-13f64 * (1.0f64 + math.abs[f64](cur)) {
            ll = cur
            break
        }
        ll = cur
        z = 0usize
        while z < q * q {
            mat[z] = info[z]
            z += 1usize
        }
        z = 0usize
        while z < q {
            step[z] = gr[z]
            z += 1usize
        }
        if !qrb.solve_dense(mat, step, q) { ret false }
        var h = 1.0f64
        var tries = 0usize
        while tries < 30usize {
            z = 0usize
            while z < q {
                trial[z] = par[z] + h * step[z]
                z += 1usize
            }
            var ok2 = true
            var tl = 0.0f64
            if ok2 {
                i = 0usize
                while i < n {
                    let pr = cr_obs(trial, x[i * p..(i + 1usize) * p], p, jn, usize(y[i]), lk, vr, sc)
                    if pr <= 0.0f64 { ok2 = false }
                    if ok2 { tl += math.log[f64](pr) }
                    i += 1usize
                }
            }
            if ok2 && tl >= ll - 1.0e-12f64 { break }
            h = h / 2.0f64
            tries += 1usize
        }
        z = 0usize
        while z < q {
            par[z] += h * step[z]
            z += 1usize
        }
        it += 1usize
    }
    // the standard errors from the expected information at the end (info is that of the last evaluated point)
    var j2 = 0usize
    while j2 < q {
        var r = 0usize
        while r < q * q {
            mat[r] = info[r]
            r += 1usize
        }
        r = 0usize
        while r < q {
            step[r] = 0.0f64
            r += 1usize
        }
        step[j2] = 1.0f64
        if !qrb.solve_dense(mat, step, q) { ret false }
        out[q + 1usize + j2] = math.sqrt[f64](step[j2])
        j2 += 1usize
    }
    j2 = 0usize
    while j2 < q {
        out[j2] = par[j2]
        j2 += 1usize
    }
    out[q] = ll
    ret true
}

type ZipCtx = struct { a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, q: []f64 }

// minus the zero-inflated Poisson log-likelihood at (beta: lambda = exp(x' beta), then gamma: pstr0 = logistic(gamma))
fn zip_f(c: *ZipCtx, par: []const f64) -> f64 {
    let p = c.p
    let phi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - par[p]))
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var eta = 0.0f64
        var t = 0usize
        while t < p {
            eta += c.x[i * p + t] * par[t]
            t += 1usize
        }
        let lam = math.exp[f64](eta)
        if c.y[i] == 0.0f64 {
            ll += math.log[f64](phi + (1.0f64 - phi) * math.exp[f64](0.0f64 - lam))
        } else {
            ll += math.log[f64](1.0f64 - phi) + c.y[i] * eta - lam - nm.lgammafn(c.y[i] + 1.0f64)
        }
        i += 1usize
    }
    ret 0.0f64 - ll
}

fn zip_g(c: *ZipCtx, par: []const f64, g: []f64) {
    let p = c.p
    let phi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - par[p]))
    var t = 0usize
    while t <= p {
        g[t] = 0.0f64
        t += 1usize
    }
    var i = 0usize
    while i < c.n {
        var eta = 0.0f64
        t = 0usize
        while t < p {
            eta += c.x[i * p + t] * par[t]
            t += 1usize
        }
        let lam = math.exp[f64](eta)
        var de = 0.0f64
        var dg = 0.0f64
        if c.y[i] == 0.0f64 {
            let em = math.exp[f64](0.0f64 - lam)
            let l0 = phi + (1.0f64 - phi) * em
            de = 0.0f64 - (1.0f64 - phi) * lam * em / l0
            dg = phi * (1.0f64 - phi) * (1.0f64 - em) / l0
        } else {
            de = c.y[i] - lam
            dg = 0.0f64 - phi
        }
        t = 0usize
        while t < p {
            g[t] += 0.0f64 - de * c.x[i * p + t]
            t += 1usize
        }
        g[p] += 0.0f64 - dg
        i += 1usize
    }
}

// vglm(y ~ x, zipoissonff(zero = -2)): the Poisson mean exp(x' beta) with x including the intercept column, and a constant structural-zero probability; out: beta (p), the logit of pstr0, the log-likelihood (p + 2 values);
// by BFGS on the analytic gradient from the plain Poisson start
fn zipoisson(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, out: []f64) -> bool {
    let m = p + 1usize
    let (par, e1) = mem.alloc[f64](a, m)
    let (qq, e2) = mem.alloc[f64](a, m)
    let (scr, e3) = mem.alloc[f64](a, m * m + 6usize * m + 16usize)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var t = 0usize
    while t < m {
        par[t] = 0.0f64
        t += 1usize
    }
    var sy = 0.0f64
    var i = 0usize
    while i < n {
        sy += y[i]
        i += 1usize
    }
    par[0usize] = math.log[f64](sy / f64(n) + 0.1f64)
    var c = ZipCtx { a: a, x: x, y: y, n: n, p: p, q: qq }
    var round = 0usize
    while round < 2usize {
        let (r, e4) = opt.bfgs[ZipCtx](&c, zip_f, zip_g, par, 1.0e-11f64, 300u32, scr)
        if e4 != ok { ret false }
        round += 1usize
    }
    t = 0usize
    while t < m {
        out[t] = par[t]
        t += 1usize
    }
    out[m] = 0.0f64 - zip_f(&c, par)
    ret true
}

type TobCtx = struct { x: []const f64, y: []const f64, n: usize, p: usize, lo: f64 }

// minus the log-likelihood of the Tobit model with left censoring at lo (observations at or below lo are censored) at (beta, log sd)
fn tob_f(c: *TobCtx, par: []const f64) -> f64 {
    let p = c.p
    let sd = math.exp[f64](par[p])
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var mu = 0.0f64
        var t = 0usize
        while t < p {
            mu += c.x[i * p + t] * par[t]
            t += 1usize
        }
        if c.y[i] <= c.lo {
            ll += dist.pnorm((c.lo - mu) / sd, 0.0f64, 1.0f64, true, true)
        } else {
            let z = (c.y[i] - mu) / sd
            ll += dist.dnorm(z, 0.0f64, 1.0f64, true) - par[p]
        }
        i += 1usize
    }
    ret 0.0f64 - ll
}

fn tob_g(c: *TobCtx, par: []const f64, g: []f64) {
    let p = c.p
    let sd = math.exp[f64](par[p])
    var t = 0usize
    while t <= p {
        g[t] = 0.0f64
        t += 1usize
    }
    var i = 0usize
    while i < c.n {
        var mu = 0.0f64
        t = 0usize
        while t < p {
            mu += c.x[i * p + t] * par[t]
            t += 1usize
        }
        var dm = 0.0f64
        var ds = 0.0f64
        if c.y[i] <= c.lo {
            let a = (c.lo - mu) / sd
            let r = math.exp[f64](dist.dnorm(a, 0.0f64, 1.0f64, true) - dist.pnorm(a, 0.0f64, 1.0f64, true, true))
            dm = 0.0f64 - r / sd
            ds = 0.0f64 - a * r
        } else {
            let z = (c.y[i] - mu) / sd
            dm = z / sd
            ds = z * z - 1.0f64
        }
        t = 0usize
        while t < p {
            g[t] += 0.0f64 - dm * c.x[i * p + t]
            t += 1usize
        }
        g[p] += 0.0f64 - ds
        i += 1usize
    }
}

// vglm(y ~ x, tobit(Lower = lo, Upper = Inf)): the mean x' beta (x with its intercept column) and a constant log sd, by BFGS on the analytic gradient from the least-squares fit of the uncensored scale; out: beta (p), log sd, the log-likelihood
fn tobit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, lo: f64, out: []f64) -> bool {
    let m = p + 1usize
    let (par, e1) = mem.alloc[f64](a, m)
    let (scr, e3) = mem.alloc[f64](a, m * m + 6usize * m + 16usize)
    if e1 != ok || e3 != ok { ret false }
    var t = 0usize
    while t < m {
        par[t] = 0.0f64
        t += 1usize
    }
    var sy = 0.0f64
    var i = 0usize
    while i < n {
        sy += y[i]
        i += 1usize
    }
    par[0usize] = sy / f64(n)
    par[p] = 0.0f64
    var c = TobCtx { x: x, y: y, n: n, p: p, lo: lo }
    var round = 0usize
    while round < 2usize {
        let (r, e4) = opt.bfgs[TobCtx](&c, tob_f, tob_g, par, 1.0e-11f64, 300u32, scr)
        if e4 != ok { ret false }
        round += 1usize
    }
    t = 0usize
    while t < m {
        out[t] = par[t]
        t += 1usize
    }
    out[m] = 0.0f64 - tob_f(&c, par)
    ret true
}

type BbCtx = struct { x: []const f64, y: []const f64, m: []const f64, n: usize, p: usize, q: []f64 }

fn lbeta2(u: f64, v: f64) -> f64 { ret nm.lgammafn(u) + nm.lgammafn(v) - nm.lgammafn(u + v) }

// minus the beta-binomial log-likelihood at (beta: logit mu = x' beta, then the logit of rho)
fn bb_f(c: *BbCtx, par: []const f64) -> f64 {
    let p = c.p
    let rho = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - par[p]))
    let s = (1.0f64 - rho) / rho
    var ll = 0.0f64
    var i = 0usize
    while i < c.n {
        var eta = 0.0f64
        var t = 0usize
        while t < p {
            eta += c.x[i * p + t] * par[t]
            t += 1usize
        }
        let mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        let al = mu * s
        let be = (1.0f64 - mu) * s
        let y = c.y[i]
        let m = c.m[i]
        ll += nm.lgammafn(m + 1.0f64) - nm.lgammafn(y + 1.0f64) - nm.lgammafn(m - y + 1.0f64) + lbeta2(y + al, m - y + be) - lbeta2(al, be)
        i += 1usize
    }
    ret 0.0f64 - ll
}

fn bb_g(c: *BbCtx, par: []const f64, g: []f64) {
    let mm = par.len
    var i = 0usize
    while i < mm {
        c.q[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < mm {
        let h = 1.0e-6f64
        c.q[i] = par[i] + h
        let fp = bb_f(c, c.q[0usize..mm])
        c.q[i] = par[i] - h
        let fm = bb_f(c, c.q[0usize..mm])
        c.q[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// vglm(cbind(y, m - y) ~ x, betabinomial): logit mu = x' beta (x with its intercept column) and a constant logit rho; out: beta (p), the logit of rho, the log-likelihood
fn betabinomial(a: *mem.Arena, x: []const f64, y: []const f64, m: []const f64, n: usize, p: usize, out: []f64) -> bool {
    let mm = p + 1usize
    let (par, e1) = mem.alloc[f64](a, mm)
    let (qq, e2) = mem.alloc[f64](a, mm)
    let (scr, e3) = mem.alloc[f64](a, mm * mm + 6usize * mm + 16usize)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var t = 0usize
    while t < mm {
        par[t] = 0.0f64
        t += 1usize
    }
    var sy = 0.0f64
    var sm = 0.0f64
    var i = 0usize
    while i < n {
        sy += y[i]
        sm += m[i]
        i += 1usize
    }
    let pr = sy / sm
    par[0usize] = math.log[f64](pr / (1.0f64 - pr))
    par[p] = math.log[f64](0.1f64 / 0.9f64)
    var c = BbCtx { x: x, y: y, m: m, n: n, p: p, q: qq }
    var round = 0usize
    while round < 2usize {
        let (r, e4) = opt.bfgs[BbCtx](&c, bb_f, bb_g, par, 1.0e-11f64, 300u32, scr)
        if e4 != ok { ret false }
        round += 1usize
    }
    t = 0usize
    while t < mm {
        out[t] = par[t]
        t += 1usize
    }
    out[mm] = 0.0f64 - bb_f(&c, par)
    ret true
}
