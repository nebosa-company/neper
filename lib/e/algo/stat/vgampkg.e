// R VGAM::vglm with the cumulative logit family and parallel = TRUE (the proportional odds model): P(Y <= j | x) = logistic(alpha_j + x' beta), j = 1 .. J - 1 for an ordered response with J levels. Fisher scoring
// (Newton with the expected information, the exact sum over the outcomes of the outer products of their scores) from the marginal logits and beta = 0; the log-likelihood and the standard errors from the same expected
// information, which is what VGAM's vcov uses.
//
// Not here: other links and families, non-parallel and partial odds, factors in the formula, weights and offsets, vgam smoothers.

use e.algo.stat.quantreg as qrb
use e.math
use e.math.dist as dist
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
