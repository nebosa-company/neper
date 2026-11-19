// R survival::coxph with strata, an offset and the robust (sandwich) variance, Breslow and Efron ties: the partial likelihood summed over strata, Newton-Raphson as in e.algo.stat.cox.
//
// Not here: exact ties, counting-process data, cluster variances, weights, frailty; the robust variance is for Breslow ties.

use e.algo.stat.quantreg as qr
use e.algo.stat.cox as cxb
use e.math.nmath as nmz
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

// cox.zph(fit, transform) for a Breslow or Efron fit with distinct event times, one stratum, every covariate its own term: the score test of the interaction x g(t) with the added coefficient (the
// time-interaction score g(t) (x - xbar) summed over events, the 2p by 2p information of (x, x g) from the risk-set covariances), per covariate and for the global test. transform 0 identity,
// 1 rank, 2 log, 3 km; out receives p chi-squares then the global one
fn cox_zph(a: *mem.Arena, time: []const f64, status: []const f64, x: []const f64, n: usize, p: usize, transform: usize, out: []f64) -> err {
    let (coef, e1) = mem.alloc[f64](a, p)
    let (se, e2) = mem.alloc[f64](a, p)
    let (ll, e3) = mem.alloc[f64](a, 2usize)
    let (g, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let fe = cxb.coxph(a, time, status, x, n, p, true, coef, se, ll)
    if fe != ok { ret fe }
    // the transformed times
    var i = 0usize
    while i < n {
        if transform == 0usize {
            g[i] = time[i]
        } else if transform == 2usize {
            g[i] = math.log[f64](time[i])
        } else if transform == 1usize {
            var below = 0.0f64
            var eq = 0.0f64
            var j = 0usize
            while j < n {
                if time[j] < time[i] { below += 1.0f64 }
                if time[j] == time[i] { eq += 1.0f64 }
                j += 1usize
            }
            g[i] = below + (eq + 1.0f64) / 2.0f64
        } else {
            // 1 - S(t-) of the Kaplan-Meier over all rows
            var surv = 1.0f64
            var j = 0usize
            while j < n {
                if status[j] != 0.0f64 && time[j] < time[i] {
                    var nr = 0.0f64
                    var q = 0usize
                    while q < n {
                        if time[q] >= time[j] { nr += 1.0f64 }
                        q += 1usize
                    }
                    surv = surv * (1.0f64 - 1.0f64 / nr)
                }
                j += 1usize
            }
            g[i] = 1.0f64 - surv
        }
        i += 1usize
    }
    var gm = 0.0f64
    var ne = 0.0f64
    i = 0usize
    while i < n {
        if status[i] != 0.0f64 {
            gm += g[i]
            ne += 1.0f64
        }
        i += 1usize
    }
    gm = gm / ne
    i = 0usize
    while i < n {
        g[i] = g[i] - gm
        i += 1usize
    }
    let q2 = 2usize * p
    let (u, e5) = mem.alloc[f64](a, q2)
    let (im, e6) = mem.alloc[f64](a, q2 * q2)
    let (ev, e7) = mem.alloc[f64](a, n)
    if e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var k = 0usize
    while k < q2 {
        u[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < q2 * q2 {
        im[k] = 0.0f64
        k += 1usize
    }
    i = 0usize
    while i < n {
        var eta = 0.0f64
        k = 0usize
        while k < p {
            eta += x[k * n + i] * coef[k]
            k += 1usize
        }
        ev[i] = math.exp[f64](eta)
        i += 1usize
    }
    var jt = 0usize
    while jt < n {
        if status[jt] != 0.0f64 {
            var rsk = 0.0f64
            var xb: [8]f64 = zero
            var xxb: [64]f64 = zero
            var q = 0usize
            while q < n {
                if time[q] >= time[jt] {
                    rsk += ev[q]
                    var a1 = 0usize
                    while a1 < p {
                        xb[a1] += ev[q] * x[a1 * n + q]
                        var b1 = 0usize
                        while b1 < p {
                            xxb[a1 * p + b1] += ev[q] * x[a1 * n + q] * x[b1 * n + q]
                            b1 += 1usize
                        }
                        a1 += 1usize
                    }
                }
                q += 1usize
            }
            var a1 = 0usize
            while a1 < p {
                xb[a1] = xb[a1] / rsk
                a1 += 1usize
            }
            a1 = 0usize
            while a1 < p {
                u[p + a1] += g[jt] * (x[a1 * n + jt] - xb[a1])
                var b1 = 0usize
                while b1 < p {
                    let v = xxb[a1 * p + b1] / rsk - xb[a1] * xb[b1]
                    im[a1 * q2 + b1] += v
                    im[a1 * q2 + p + b1] += g[jt] * v
                    im[(p + a1) * q2 + b1] += g[jt] * v
                    im[(p + a1) * q2 + p + b1] += g[jt] * g[jt] * v
                    b1 += 1usize
                }
                a1 += 1usize
            }
        }
        jt += 1usize
    }
    // per-covariate test: the (p + 1) block of the betas and that covariate's interaction, u = (0, u_k); global: the full 2p system
    var term = 0usize
    while term <= p {
        var m = p + 1usize
        if term == p { m = q2 }
        let (mat, e8) = mem.alloc[f64](a, m * m)
        let (rhs, e9) = mem.alloc[f64](a, m)
        if e8 != ok || e9 != ok { ret mem.Full }
        var r = 0usize
        while r < m {
            var c = 0usize
            while c < m {
                var ir = r
                var ic = c
                if term < p {
                    if r == p { ir = p + term }
                    if c == p { ic = p + term }
                }
                mat[r * m + c] = im[ir * q2 + ic]
                c += 1usize
            }
            var ur = 0.0f64
            if term == p {
                if r >= p { ur = u[r] }
            } else if r == p {
                ur = u[p + term]
            }
            rhs[r] = ur
            r += 1usize
        }
        var uu = rhs[0usize]
        let (cp, e10) = mem.alloc[f64](a, m)
        if e10 != ok { ret mem.Full }
        r = 0usize
        while r < m {
            cp[r] = rhs[r]
            r += 1usize
        }
        if !qr.solve_dense(mat, rhs, m) { ret Singular }
        var tot = 0.0f64
        r = 0usize
        while r < m {
            tot += rhs[r] * cp[r]
            r += 1usize
        }
        out[term] = tot
        term += 1usize
    }
    ret ok
}

// residuals(coxph, type) for a Breslow fit with strata and an offset: the martingale residual delta_i - e_i H0(t_i) (H0 the Breslow cumulative baseline hazard of the stratum at the row's time) and the
// deviance residual sign(m) sqrt(-2 (m + delta log(delta - m))); kind 0 martingale, 1 deviance; row i of the fit
fn cox_resid(a: *mem.Arena, time: []const f64, status: []const f64, strat: []const usize, off: []const f64, x: []const f64, n: usize, p: usize, kind: usize, row: usize) -> f64 {
    let (coef, e1) = mem.alloc[f64](a, p)
    let (se, e2) = mem.alloc[f64](a, p)
    let (ll, e3) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    if coxph_s(a, time, status, strat, off, x, n, p, false, false, coef, se, ll) != ok { ret 0.0f64 / 0.0f64 }
    var h = 0.0f64
    var j = 0usize
    while j < n {
        if status[j] != 0.0f64 && strat[j] == strat[row] && time[j] <= time[row] {
            // the first row at this event time counts it once
            var first = true
            var q = 0usize
            while q < j {
                if status[q] != 0.0f64 && strat[q] == strat[j] && time[q] == time[j] { first = false }
                q += 1usize
            }
            if first {
                var rsk = 0.0f64
                var d = 0.0f64
                q = 0usize
                while q < n {
                    if strat[q] == strat[j] && time[q] >= time[j] { rsk += math.exp[f64](off[q] + dotx(x, n, p, coef, q)) }
                    if strat[q] == strat[j] && time[q] == time[j] && status[q] != 0.0f64 { d += 1.0f64 }
                    q += 1usize
                }
                h += d / rsk
            }
        }
        j += 1usize
    }
    let m = status[row] - math.exp[f64](off[row] + dotx(x, n, p, coef, row)) * h
    if kind == 0usize { ret m }
    var inner = 0.0f64 - 2.0f64 * m
    if status[row] != 0.0f64 { inner = 0.0f64 - 2.0f64 * (m + math.log[f64](status[row] - m)) }
    var sg = 1.0f64
    if m < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    ret sg * math.sqrt[f64](inner)
}

// survival::coxph(Surv(start, stop, status) ~ x + strata) with counting-process data: the risk set at an event time t of a stratum is {i : start_i < t <= stop_i}; Breslow or Efron ties. Newton-Raphson on the exact
// partial likelihood from beta = 0 until the log-likelihood moves by less than 1e-13 relatively; coef and se (the inverse information) of length p; ll receives the log-likelihoods at beta = 0 and at the fit
fn coxph_cp(a: *mem.Arena, start: []const f64, stop: []const f64, status: []const f64, strat: []const usize, x: []const f64, n: usize, p: usize, tiemode: usize, coef: []f64, se: []f64, ll: []f64, vout: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, p)
    let (info, e2) = mem.alloc[f64](a, p * p)
    let (s1, e3) = mem.alloc[f64](a, p)
    let (t1, e4) = mem.alloc[f64](a, p)
    let (s2, e5) = mem.alloc[f64](a, p * p)
    let (t2, e6) = mem.alloc[f64](a, p * p)
    let (w, e7) = mem.alloc[f64](a, n)
    let (mat, e8) = mem.alloc[f64](a, p * p)
    let (col, e9) = mem.alloc[f64](a, p)
    let (seen, e10) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    let efron = tiemode == 1usize
    let exact = tiemode == 2usize
    let maxd = n + 1usize
    let (ek, e11) = mem.alloc[f64](a, maxd)
    let (ak, e12) = mem.alloc[f64](a, maxd * p)
    let (bk, e13) = mem.alloc[f64](a, maxd * p * p)
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    var j = 0usize
    while j < p {
        coef[j] = 0.0f64
        j += 1usize
    }
    var iter = 0usize
    var last = 0.0f64
    var first = 0.0f64
    while iter < 60usize {
        var i = 0usize
        while i < n {
            var eta = 0.0f64
            j = 0usize
            while j < p {
                eta += x[j * n + i] * coef[j]
                j += 1usize
            }
            w[i] = math.exp[f64](eta)
            seen[i] = 0.0f64
            i += 1usize
        }
        var llv = 0.0f64
        j = 0usize
        while j < p {
            u[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < p * p {
            info[j] = 0.0f64
            j += 1usize
        }
        // every event time of every stratum once
        i = 0usize
        while i < n {
            if status[i] > 0.5f64 && seen[i] == 0.0f64 {
                let t = stop[i]
                let sg = strat[i]
                var d = 0.0f64
                var t0 = 0.0f64
                var s0 = 0.0f64
                j = 0usize
                while j < p {
                    s1[j] = 0.0f64
                    t1[j] = 0.0f64
                    j += 1usize
                }
                j = 0usize
                while j < p * p {
                    s2[j] = 0.0f64
                    t2[j] = 0.0f64
                    j += 1usize
                }
                var k = 0usize
                while k < n {
                    if strat[k] == sg && start[k] < t && stop[k] >= t {
                        s0 += w[k]
                        var a1 = 0usize
                        while a1 < p {
                            s1[a1] += w[k] * x[a1 * n + k]
                            var b1 = 0usize
                            while b1 < p {
                                s2[a1 * p + b1] += w[k] * x[a1 * n + k] * x[b1 * n + k]
                                b1 += 1usize
                            }
                            a1 += 1usize
                        }
                        if stop[k] == t && status[k] > 0.5f64 {
                            seen[k] = 1.0f64
                            d += 1.0f64
                            t0 += w[k]
                            var eta = 0.0f64
                            a1 = 0usize
                            while a1 < p {
                                eta += x[a1 * n + k] * coef[a1]
                                u[a1] += x[a1 * n + k]
                                t1[a1] += w[k] * x[a1 * n + k]
                                var b2 = 0usize
                                while b2 < p {
                                    t2[a1 * p + b2] += w[k] * x[a1 * n + k] * x[b2 * n + k]
                                    b2 += 1usize
                                }
                                a1 += 1usize
                            }
                            llv += eta
                        }
                    }
                    k += 1usize
                }
                if exact {
                    // elementary symmetric polynomials of the risk-set weights up to degree d with their first and second derivatives in beta
                    let dd = usize(d)
                    var q0 = 0usize
                    while q0 <= dd {
                        ek[q0] = 0.0f64
                        var a0 = 0usize
                        while a0 < p {
                            ak[q0 * p + a0] = 0.0f64
                            var b0 = 0usize
                            while b0 < p {
                                bk[(q0 * p + a0) * p + b0] = 0.0f64
                                b0 += 1usize
                            }
                            a0 += 1usize
                        }
                        q0 += 1usize
                    }
                    ek[0usize] = 1.0f64
                    var r = 0usize
                    while r < n {
                        if strat[r] == sg && start[r] < t && stop[r] >= t {
                            var kk = dd
                            while kk >= 1usize {
                                var a3 = 0usize
                                while a3 < p {
                                    var b3 = 0usize
                                    while b3 < p {
                                        bk[(kk * p + a3) * p + b3] += w[r] * x[a3 * n + r] * x[b3 * n + r] * ek[kk - 1usize] + w[r] * x[a3 * n + r] * ak[(kk - 1usize) * p + b3] + w[r] * x[b3 * n + r] * ak[(kk - 1usize) * p + a3] + w[r] * bk[((kk - 1usize) * p + a3) * p + b3]
                                        b3 += 1usize
                                    }
                                    ak[kk * p + a3] += w[r] * x[a3 * n + r] * ek[kk - 1usize] + w[r] * ak[(kk - 1usize) * p + a3]
                                    a3 += 1usize
                                }
                                ek[kk] += w[r] * ek[kk - 1usize]
                                kk -= 1usize
                            }
                        }
                        r += 1usize
                    }
                    llv -= math.log[f64](ek[dd])
                    var a4 = 0usize
                    while a4 < p {
                        u[a4] -= ak[dd * p + a4] / ek[dd]
                        var b4 = 0usize
                        while b4 < p {
                            info[a4 * p + b4] += bk[(dd * p + a4) * p + b4] / ek[dd] - ak[dd * p + a4] * ak[dd * p + b4] / (ek[dd] * ek[dd])
                            b4 += 1usize
                        }
                        a4 += 1usize
                    }
                }
                var m = 0usize
                if exact { m = usize(d) }
                while m < usize(d) {
                    var frac = 0.0f64
                    if efron { frac = f64(m) / d }
                    var den = s0
                    if efron { den = s0 - frac * t0 }
                    if !efron { frac = 0.0f64 }
                    var mult = 1.0f64
                    if !efron { mult = d }
                    llv -= mult * math.log[f64](den)
                    var a2 = 0usize
                    while a2 < p {
                        let m1 = s1[a2] - frac * t1[a2]
                        u[a2] -= mult * m1 / den
                        var b3 = 0usize
                        while b3 < p {
                            let m1b = s1[b3] - frac * t1[b3]
                            info[a2 * p + b3] += mult * ((s2[a2 * p + b3] - frac * t2[a2 * p + b3]) / den - m1 * m1b / (den * den))
                            b3 += 1usize
                        }
                        a2 += 1usize
                    }
                    if !efron { break }
                    m += 1usize
                }
            }
            i += 1usize
        }
        if iter == 0usize { first = llv }
        if iter > 0usize && math.abs[f64](llv - last) < 1.0e-13f64 * (1.0f64 + math.abs[f64](llv)) {
            ll[0usize] = first
            ll[1usize] = llv
            // standard errors from the information at the final beta
            var c = 0usize
            while c < p {
                var r = 0usize
                while r < p * p {
                    mat[r] = info[r]
                    r += 1usize
                }
                r = 0usize
                while r < p {
                    col[r] = 0.0f64
                    r += 1usize
                }
                col[c] = 1.0f64
                if !qr.solve_dense(mat, col, p) { ret Singular }
                se[c] = math.sqrt[f64](col[c])
                var vr = 0usize
                while vr < p {
                    vout[vr * p + c] = col[vr]
                    vr += 1usize
                }
                c += 1usize
            }
            ret ok
        }
        last = llv
        var c2 = 0usize
        while c2 < p * p {
            mat[c2] = info[c2]
            c2 += 1usize
        }
        c2 = 0usize
        while c2 < p {
            col[c2] = u[c2]
            c2 += 1usize
        }
        if !qr.solve_dense(mat, col, p) { ret Singular }
        c2 = 0usize
        while c2 < p {
            coef[c2] += col[c2]
            c2 += 1usize
        }
        iter += 1usize
    }
    ret Singular
}

// the robust (sandwich) variance of a Breslow `coxph_cp` fit, survival's robust = TRUE: the score residual of each row at the fitted beta (its deaths' x - xbar(t) minus w (x - xbar(t)) dLambda over the event times of
// (start, stop]) is summed within the clusters clus (0-based, nclus of them; one per row when each row is its own cluster), and the variance is V S V with V the inverse information vin (p by p) and
// S the cross product of the cluster sums. se receives the square roots of the diagonal
fn coxph_cp_robust(a: *mem.Arena, start: []const f64, stop: []const f64, status: []const f64, strat: []const usize, x: []const f64, n: usize, p: usize, coef: []const f64, vin: []const f64, clus: []const usize, nclus: usize, se: []f64) -> err {
    let (rs, e1) = mem.alloc[f64](a, n * p)
    let (cs, e2) = mem.alloc[f64](a, nclus * p)
    let (w, e3) = mem.alloc[f64](a, n)
    let (s1, e4) = mem.alloc[f64](a, p)
    let (seen, e5) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        var j = 0usize
        while j < p {
            eta += x[j * n + i] * coef[j]
            rs[i * p + j] = 0.0f64
            j += 1usize
        }
        w[i] = math.exp[f64](eta)
        seen[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        if status[i] > 0.5f64 && seen[i] == 0.0f64 && start[i] < stop[i] {
            let t = stop[i]
            let sg = strat[i]
            var d = 0.0f64
            var s0 = 0.0f64
            var j = 0usize
            while j < p {
                s1[j] = 0.0f64
                j += 1usize
            }
            var k = 0usize
            while k < n {
                if strat[k] == sg && start[k] < t && stop[k] >= t {
                    s0 += w[k]
                    j = 0usize
                    while j < p {
                        s1[j] += w[k] * x[j * n + k]
                        j += 1usize
                    }
                    if stop[k] == t && status[k] > 0.5f64 {
                        seen[k] = 1.0f64
                        d += 1.0f64
                    }
                }
                k += 1usize
            }
            k = 0usize
            while k < n {
                if strat[k] == sg && start[k] < t && stop[k] >= t {
                    j = 0usize
                    while j < p {
                        let dev = x[j * n + k] - s1[j] / s0
                        if stop[k] == t && status[k] > 0.5f64 { rs[k * p + j] += dev }
                        rs[k * p + j] -= w[k] * dev * d / s0
                        j += 1usize
                    }
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    var c0 = 0usize
    while c0 < nclus * p {
        cs[c0] = 0.0f64
        c0 += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            cs[clus[i] * p + j] += rs[i * p + j]
            j += 1usize
        }
        i += 1usize
    }
    var a1 = 0usize
    while a1 < p {
        var sum = 0.0f64
        var b1 = 0usize
        while b1 < p {
            var c1 = 0usize
            while c1 < p {
                var mid = 0.0f64
                var g = 0usize
                while g < nclus {
                    mid += cs[g * p + b1] * cs[g * p + c1]
                    g += 1usize
                }
                sum += vin[a1 * p + b1] * mid * vin[c1 * p + a1]
                c1 += 1usize
            }
            b1 += 1usize
        }
        se[a1] = math.sqrt[f64](sum)
        a1 += 1usize
    }
    ret ok
}

// the Schoenfeld residuals of a Breslow counting-process fit at coef: one row per death, x_i - xbar(t_i) with xbar the weighted mean of the covariates over the risk set {start < t <= stop} of its stratum.
// sumsq[j] receives the sum of squares of column j and sums[j] the column sum (which is the score, zero at the maximum); nd the number of deaths
fn coxph_cp_schoenfeld(a: *mem.Arena, start: []const f64, stop: []const f64, status: []const f64, strat: []const usize, x: []const f64, n: usize, p: usize, coef: []const f64, sumsq: []f64, sums: []f64) -> usize {
    let (w, e1) = mem.alloc[f64](a, n)
    let (s1, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        var j = 0usize
        while j < p {
            eta += x[j * n + i] * coef[j]
            j += 1usize
        }
        w[i] = math.exp[f64](eta)
        i += 1usize
    }
    var j0 = 0usize
    while j0 < p {
        sumsq[j0] = 0.0f64
        sums[j0] = 0.0f64
        j0 += 1usize
    }
    var nd = 0usize
    i = 0usize
    while i < n {
        if status[i] > 0.5f64 && start[i] < stop[i] {
            let t = stop[i]
            let sg = strat[i]
            var s0 = 0.0f64
            var j = 0usize
            while j < p {
                s1[j] = 0.0f64
                j += 1usize
            }
            var k = 0usize
            while k < n {
                if strat[k] == sg && start[k] < t && stop[k] >= t {
                    s0 += w[k]
                    j = 0usize
                    while j < p {
                        s1[j] += w[k] * x[j * n + k]
                        j += 1usize
                    }
                }
                k += 1usize
            }
            j = 0usize
            while j < p {
                let r = x[j * n + i] - s1[j] / s0
                sumsq[j] += r * r
                sums[j] += r
                j += 1usize
            }
            nd += 1usize
        }
        i += 1usize
    }
    ret nd
}

// survival::tmerge for a time-dependent covariate (kind 0, tdc(time, value)) or a running event count (kind 1, cumevent(time)) merged into follow-up (0, futime[i]] of each subject: the intervals are cut at the distinct
// observation times strictly inside (0, futime[i]); a tdc row carries the value of the last observation at or before its start (NaN before the first), a cumevent row the number of observations in (start, stop], the
// first interval also taking those at or before 0 and the last the one at futime, observations after futime being ignored. Rows come subject by subject in time order into rstart, rstop and rval (at most cap);
// returns the number of rows
fn tmerge_rows(a: *mem.Arena, futime: []const f64, sid: []const usize, tm: []const f64, val: []const f64, kind: usize, rstart: []f64, rstop: []f64, rval: []f64) -> usize {
    let (cuts, e1) = mem.alloc[f64](a, tm.len + 2usize)
    if e1 != ok { ret 0usize }
    var nr = 0usize
    var sub = 0usize
    while sub < futime.len {
        let ft = futime[sub]
        // the distinct cut times inside (0, ft), sorted
        var nc = 0usize
        var k = 0usize
        while k < tm.len {
            if sid[k] == sub && tm[k] > 0.0f64 && tm[k] < ft {
                var seen = false
                var q = 0usize
                while q < nc {
                    if cuts[q] == tm[k] { seen = true }
                    q += 1usize
                }
                if !seen {
                    cuts[nc] = tm[k]
                    nc += 1usize
                }
            }
            k += 1usize
        }
        var i = 1usize
        while i < nc {
            let cur = cuts[i]
            var j = i
            while j > 0usize && cuts[j - 1usize] > cur {
                cuts[j] = cuts[j - 1usize]
                j -= 1usize
            }
            cuts[j] = cur
            i += 1usize
        }
        var r = 0usize
        while r <= nc {
            var st = 0.0f64
            if r > 0usize { st = cuts[r - 1usize] }
            var sp = ft
            if r < nc { sp = cuts[r] }
            var v = 0.0f64 / 0.0f64
            if kind >= 1usize { v = 0.0f64 }
            var bt = 0.0f64
            var have = false
            var hit = false
            var cntle = 0.0f64
            k = 0usize
            while k < tm.len {
                if sid[k] == sub {
                    if kind == 0usize {
                        if tm[k] <= st && (!have || tm[k] >= bt) {
                            bt = tm[k]
                            have = true
                            v = val[k]
                        }
                    } else if kind == 1usize {
                        if tm[k] <= sp { cntle += 1.0f64 }
                        if tm[k] == sp { hit = true }
                    } else {
                        if tm[k] == sp && sp > 0.0f64 { v = val[k] }
                    }
                }
                k += 1usize
            }
            if kind == 1usize && hit { v = cntle }
            rstart[nr] = st
            rstop[nr] = sp
            rval[nr] = v
            nr += 1usize
            r += 1usize
        }
        sub += 1usize
    }
    ret nr
}

// survival::concordance(Surv(time, status) ~ x) by the pair count: out = concordant, discordant, tied in x (different times), tied in time with different x (both events), tied in both, then the concordance
// (concordant + tied x / 2) / (concordant + discordant + tied x). A pair is comparable when its earlier member is an event; at equal times an event comes before a censored observation, two events are tied in time
// and two censored are not comparable. A larger x is concordant with a longer time.
fn concordance(time: []const f64, status: []const f64, x: []const f64, n: usize, out: []f64) {
    var conc = 0.0f64
    var disc = 0.0f64
    var tx = 0.0f64
    var ty = 0.0f64
    var txy = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var e = n
            var l = n
            var skip = false
            if time[i] < time[j] {
                e = i
                l = j
                if status[i] < 0.5f64 { skip = true }
            } else if time[j] < time[i] {
                e = j
                l = i
                if status[j] < 0.5f64 { skip = true }
            } else {
                if status[i] > 0.5f64 && status[j] > 0.5f64 {
                    if x[i] == x[j] { txy += 1.0f64 } else { ty += 1.0f64 }
                    skip = true
                } else if status[i] > 0.5f64 {
                    e = i
                    l = j
                } else if status[j] > 0.5f64 {
                    e = j
                    l = i
                } else {
                    skip = true
                }
            }
            if !skip {
                if x[e] < x[l] {
                    conc += 1.0f64
                } else if x[e] > x[l] {
                    disc += 1.0f64
                } else {
                    tx += 1.0f64
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    out[0usize] = conc
    out[1usize] = disc
    out[2usize] = tx
    out[3usize] = ty
    out[4usize] = txy
    out[5usize] = (conc + tx / 2.0f64) / (conc + disc + tx)
}

// survival::survSplit(Surv(tstart, time, event) ~ ., cut = cuts, episode): every subject's follow-up (start, time] is cut at the sorted cut points strictly inside it; the event stays on the last piece, the episode is one more than the number
// of cuts at or below the piece's start. out is five columns per row in subject-major order (subject index, tstart, tstop, event, episode), room for n (nc + 1) rows; returns the number of rows
fn surv_split(start: []const f64, time: []const f64, event: []const f64, n: usize, cuts: []const f64, nc: usize, out: []f64) -> usize {
    var rows = 0usize
    var i = 0usize
    while i < n {
        var from = start[i]
        var k = 0usize
        var ep = 1usize
        while k < nc && cuts[k] <= from {
            ep += 1usize
            k += 1usize
        }
        while k < nc && cuts[k] < time[i] {
            out[rows * 5usize] = f64(i)
            out[rows * 5usize + 1usize] = from
            out[rows * 5usize + 2usize] = cuts[k]
            out[rows * 5usize + 3usize] = 0.0f64
            out[rows * 5usize + 4usize] = f64(ep)
            rows += 1usize
            from = cuts[k]
            ep += 1usize
            k += 1usize
        }
        out[rows * 5usize] = f64(i)
        out[rows * 5usize + 1usize] = from
        out[rows * 5usize + 2usize] = time[i]
        out[rows * 5usize + 3usize] = event[i]
        out[rows * 5usize + 4usize] = f64(ep)
        rows += 1usize
        i += 1usize
    }
    ret rows
}
