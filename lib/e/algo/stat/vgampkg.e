// R VGAM::vglm with the cumulative logit family and parallel = TRUE (the proportional odds model): P(Y <= j | x) = logistic(alpha_j + x' beta), j = 1 .. J - 1 for an ordered response with J levels. Fisher scoring
// (Newton with the expected information, the exact sum over the outcomes of the outer products of their scores) from the marginal logits and beta = 0; the log-likelihood and the standard errors from the same expected
// information, which is what VGAM's vcov uses.
//
// Not here: other links and families, non-parallel and partial odds, factors in the formula, weights and offsets, vgam smoothers.

use e.algo.stat.quantreg as qrb
use e.math
use e.mem

fn lg(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

// the cumulative probabilities F_k = logistic(alpha_k + eta) for k = 0 .. J - 2 with F_-1 = 0 and F_(J-1) = 1 held implicit
fn cum_obs(par: []const f64, x: []const f64, p: usize, jn: usize, cls: usize, sc: []f64) -> f64 {
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
        fu = lg(par[cls] + eta)
        gu = fu * (1.0f64 - fu)
    }
    if cls > 0usize {
        fl = lg(par[cls - 1usize] + eta)
        gl = fl * (1.0f64 - fl)
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
fn cum_logit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, jn: usize, out: []f64) -> bool {
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
            let pr = cum_obs(par, xi, p, jn, usize(y[i]), sc)
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
                let po = cum_obs(par, xi, p, jn, oc, sc2[0usize..q])
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
                    let pr = cum_obs(trial, x[i * p..(i + 1usize) * p], p, jn, usize(y[i]), sc)
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
