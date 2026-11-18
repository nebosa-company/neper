// R survival::coxph with strata, an offset and the robust (sandwich) variance, Breslow and Efron ties: the partial likelihood summed over strata, Newton-Raphson as in e.algo.stat.cox.
//
// Not here: exact ties, counting-process data, cluster variances, weights, frailty; the robust variance is for Breslow ties.

use e.algo.stat.quantreg as qr
use e.math
use e.mem

error Singular

// one pass over the rows ordered by (stratum, descending time): the log partial likelihood, the score u and the information; with `resid` true the Breslow score residuals of every row are
// written to res (n by p, column-major) at the beta given
fn evaluate_s(order: []const usize, time: []const f64, status: []const f64, strat: []const usize, off: []const f64, x: []const f64, n: usize, p: usize, beta: []const f64, efron: bool, u: []f64, info: []f64) -> f64 {
    var ll = 0.0f64
    var k = 0usize
    while k < p {
        u[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < p * p {
        info[k] = 0.0f64
        k += 1usize
    }
    var r = 0.0f64
    var rx: [8]f64 = zero
    var rxx: [64]f64 = zero
    var dx: [8]f64 = zero
    var dxx: [64]f64 = zero
    var xbar: [8]f64 = zero
    var at = 0usize
    var cur_s = strat[order[0usize]]
    while at < n {
        if strat[order[at]] != cur_s {
            cur_s = strat[order[at]]
            r = 0.0f64
            k = 0usize
            while k < p {
                rx[k] = 0.0f64
                k += 1usize
            }
            k = 0usize
            while k < p * p {
                rxx[k] = 0.0f64
                k += 1usize
            }
        }
        var end = at
        while end < n && strat[order[end]] == cur_s && time[order[end]] == time[order[at]] { end += 1usize }
        var d = 0.0f64
        var dr = 0.0f64
        k = 0usize
        while k < p {
            dx[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < p * p {
            dxx[k] = 0.0f64
            k += 1usize
        }
        var g = at
        while g < end {
            let i = order[g]
            var eta = off[i]
            k = 0usize
            while k < p {
                eta += x[k * n + i] * beta[k]
                k += 1usize
            }
            let e = math.exp[f64](eta)
            r += e
            var a1 = 0usize
            while a1 < p {
                rx[a1] += e * x[a1 * n + i]
                var b1 = 0usize
                while b1 < p {
                    rxx[a1 * p + b1] += e * x[a1 * n + i] * x[b1 * n + i]
                    b1 += 1usize
                }
                a1 += 1usize
            }
            if status[i] != 0.0f64 {
                d += 1.0f64
                dr += e
                ll += eta
                a1 = 0usize
                while a1 < p {
                    u[a1] += x[a1 * n + i]
                    dx[a1] += e * x[a1 * n + i]
                    var b1 = 0usize
                    while b1 < p {
                        dxx[a1 * p + b1] += e * x[a1 * n + i] * x[b1 * n + i]
                        b1 += 1usize
                    }
                    a1 += 1usize
                }
            }
            g += 1usize
        }
        var j = 0usize
        while f64(j) < d {
            var f = 0.0f64
            if efron { f = f64(j) / d }
            let den = r - f * dr
            ll -= math.log[f64](den)
            var a1 = 0usize
            while a1 < p {
                xbar[a1] = (rx[a1] - f * dx[a1]) / den
                u[a1] -= xbar[a1]
                a1 += 1usize
            }
            a1 = 0usize
            while a1 < p {
                var b1 = 0usize
                while b1 < p {
                    info[a1 * p + b1] += (rxx[a1 * p + b1] - f * dxx[a1 * p + b1]) / den - xbar[a1] * xbar[b1]
                    b1 += 1usize
                }
                a1 += 1usize
            }
            j += 1usize
        }
        at = end
    }
    ret ll
}

// Breslow score residuals (dfbeta-type contributions of each row to the score) at beta: row i receives delta_i (x_i - xbar(t_i)) minus the sum over event times t_j <= t_i in its stratum of
// e_i (x_i - xbar(t_j)) d_j / R(t_j); res is n by p column-major
fn score_resid(time: []const f64, status: []const f64, strat: []const usize, off: []const f64, x: []const f64, n: usize, p: usize, beta: []const f64, res: []f64) {
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < p {
            res[k * n + i] = 0.0f64
            k += 1usize
        }
        i += 1usize
    }
    var ev: [64]f64 = zero
    i = 0usize
    while i < n {
        ev[i] = math.exp[f64](off[i] + dotx(x, n, p, beta, i))
        i += 1usize
    }
    // each distinct event time in each stratum
    var jt = 0usize
    while jt < n {
        if status[jt] != 0.0f64 {
            // skip when an earlier row of the same stratum has this event time (count each time once)
            var first = true
            var q = 0usize
            while q < jt {
                if status[q] != 0.0f64 && strat[q] == strat[jt] && time[q] == time[jt] { first = false }
                q += 1usize
            }
            if first {
                var rsk = 0.0f64
                var d = 0.0f64
                var xb: [8]f64 = zero
                q = 0usize
                while q < n {
                    if strat[q] == strat[jt] && time[q] >= time[jt] {
                        rsk += ev[q]
                        var k = 0usize
                        while k < p {
                            xb[k] += ev[q] * x[k * n + q]
                            k += 1usize
                        }
                    }
                    if strat[q] == strat[jt] && time[q] == time[jt] && status[q] != 0.0f64 { d += 1.0f64 }
                    q += 1usize
                }
                var k = 0usize
                while k < p {
                    xb[k] = xb[k] / rsk
                    k += 1usize
                }
                // the events at this time contribute (x - xbar) each; every row still at risk loses e_i (x_i - xbar) d / R
                q = 0usize
                while q < n {
                    if strat[q] == strat[jt] {
                        k = 0usize
                        while k < p {
                            if time[q] == time[jt] && status[q] != 0.0f64 { res[k * n + q] += x[k * n + q] - xb[k] }
                            if time[q] >= time[jt] { res[k * n + q] -= ev[q] * (x[k * n + q] - xb[k]) * d / rsk }
                            k += 1usize
                        }
                    }
                    q += 1usize
                }
            }
        }
        jt += 1usize
    }
}

fn dotx(x: []const f64, n: usize, p: usize, beta: []const f64, i: usize) -> f64 {
    var s = 0.0f64
    var k = 0usize
    while k < p {
        s += x[k * n + i] * beta[k]
        k += 1usize
    }
    ret s
}

// coxph(Surv(time, status) ~ x + strata(strat) + offset(off), ties, robust): coef, se (robust when asked, else the inverse information), and the log partial likelihood at zero and at the fit in ll
fn coxph_s(a: *mem.Arena, time: []const f64, status: []const f64, strat: []const usize, off: []const f64, x: []const f64, n: usize, p: usize, efron: bool, robust: bool, coef: []f64, se: []f64, ll: []f64) -> err {
    let (order, e1) = mem.alloc[usize](a, n)
    let (u, e2) = mem.alloc[f64](a, p)
    let (info, e3) = mem.alloc[f64](a, p * p)
    let (step, e4) = mem.alloc[f64](a, p)
    let (mat, e5) = mem.alloc[f64](a, p * p)
    let (beta, e6) = mem.alloc[f64](a, p)
    let (nb, e7) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = order[i]
        var j = i
        while j > 0usize && (strat[order[j - 1usize]] > strat[v] || (strat[order[j - 1usize]] == strat[v] && time[order[j - 1usize]] < time[v])) {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = v
        i += 1usize
    }
    var k = 0usize
    while k < p {
        beta[k] = 0.0f64
        k += 1usize
    }
    var cur = evaluate_s(order, time, status, strat, off, x, n, p, beta, efron, u, info)
    ll[0usize] = cur
    var it = 0usize
    while it < 50usize {
        k = 0usize
        while k < p * p {
            mat[k] = info[k]
            k += 1usize
        }
        k = 0usize
        while k < p {
            step[k] = u[k]
            k += 1usize
        }
        if !qr.solve_dense(mat, step, p) { ret Singular }
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        var nll = cur
        while tries < 30usize {
            k = 0usize
            while k < p {
                nb[k] = beta[k] + scale * step[k]
                k += 1usize
            }
            nll = evaluate_s(order, time, status, strat, off, x, n, p, nb, efron, u, info)
            if nll >= cur - 1.0e-12f64 {
                moved = true
                break
            }
            scale = scale / 2.0f64
            tries += 1usize
        }
        if !moved { break }
        k = 0usize
        while k < p {
            beta[k] = nb[k]
            k += 1usize
        }
        let gain = nll - cur
        cur = nll
        if gain < 1.0e-13f64 { break }
        it += 1usize
    }
    cur = evaluate_s(order, time, status, strat, off, x, n, p, beta, efron, u, info)
    ll[1usize] = cur
    // inverse information columns
    let (inv, e8) = mem.alloc[f64](a, p * p)
    if e8 != ok { ret e8 }
    var c = 0usize
    while c < p {
        k = 0usize
        while k < p * p {
            mat[k] = info[k]
            k += 1usize
        }
        k = 0usize
        while k < p {
            step[k] = 0.0f64
            k += 1usize
        }
        step[c] = 1.0f64
        if !qr.solve_dense(mat, step, p) { ret Singular }
        k = 0usize
        while k < p {
            inv[k * p + c] = step[k]
            k += 1usize
        }
        coef[c] = beta[c]
        c += 1usize
    }
    if !robust {
        c = 0usize
        while c < p {
            se[c] = math.sqrt[f64](inv[c * p + c])
            c += 1usize
        }
        ret ok
    }
    let (res, e9) = mem.alloc[f64](a, n * p)
    if e9 != ok { ret e9 }
    score_resid(time, status, strat, off, x, n, p, beta, res)
    // V = inv (sum r r') inv
    let (mid, e10) = mem.alloc[f64](a, p * p)
    if e10 != ok { ret e10 }
    var a1 = 0usize
    while a1 < p {
        var b1 = 0usize
        while b1 < p {
            var sm = 0.0f64
            i = 0usize
            while i < n {
                sm += res[a1 * n + i] * res[b1 * n + i]
                i += 1usize
            }
            mid[a1 * p + b1] = sm
            b1 += 1usize
        }
        a1 += 1usize
    }
    c = 0usize
    while c < p {
        var v = 0.0f64
        var s1 = 0usize
        while s1 < p {
            var s2 = 0usize
            while s2 < p {
                v += inv[c * p + s1] * mid[s1 * p + s2] * inv[s2 * p + c]
                s2 += 1usize
            }
            s1 += 1usize
        }
        se[c] = math.sqrt[f64](v)
        c += 1usize
    }
    ret ok
}
