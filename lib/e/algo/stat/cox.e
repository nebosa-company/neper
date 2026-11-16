// R survival::coxph, one stratum, no offset or weights: Cox's proportional hazards by Newton-Raphson on the
// partial likelihood with Breslow or Efron tie handling. Answers the coefficients, their model-based standard errors
// (the inverse information) and the log partial likelihood at the fit and at zero.
//
// Not here: exact ties, strata, offsets, counting-process data, robust and cluster variances, frailty, survfit,
// survreg, survdiff, cox.zph.

use e.algo.stat.quantreg as qr
use e.math
use e.mem

error Singular

// log partial likelihood at beta; u receives the score and info the information matrix (p by p, row-major)
fn evaluate(order: []const usize, time: []const f64, status: []const f64, x: []const f64, n: usize, p: usize, beta: []const f64, efron: bool, u: []f64, info: []f64, rx: []f64, rxx: []f64, dx: []f64, dxx: []f64, xbar: []f64) -> f64 {
    var ll = 0.0f64
    var k = 0usize
    while k < p {
        u[k] = 0.0f64
        rx[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < p * p {
        info[k] = 0.0f64
        rxx[k] = 0.0f64
        k += 1usize
    }
    var r = 0.0f64
    var at = 0usize
    while at < n {
        var end = at
        while end < n && time[order[end]] == time[order[at]] { end += 1usize }
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
            var eta = 0.0f64
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

fn coxph(a: *mem.Arena, time: []const f64, status: []const f64, x0: []const f64, n: usize, p: usize, efron: bool, coef: []f64, se: []f64, ll: []f64) -> err {
    let (order, e1) = mem.alloc[usize](a, n)
    let (x, e2) = mem.alloc[f64](a, n * p)
    let (mean, e3) = mem.alloc[f64](a, p)
    let (u, e4) = mem.alloc[f64](a, p)
    let (info, e5) = mem.alloc[f64](a, p * p)
    let (rx, e6) = mem.alloc[f64](a, p)
    let (rxx, e7) = mem.alloc[f64](a, p * p)
    let (dx, e8) = mem.alloc[f64](a, p)
    let (dxx, e9) = mem.alloc[f64](a, p * p)
    let (xbar, e10) = mem.alloc[f64](a, p)
    let (step, e11) = mem.alloc[f64](a, p)
    let (mat, e12) = mem.alloc[f64](a, p * p)
    let (beta, e13) = mem.alloc[f64](a, p)
    let (nb, e14) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret e1 }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    // descending time by insertion
    i = 1usize
    while i < n {
        let v = order[i]
        var j = i
        while j > 0usize && time[order[j - 1usize]] < time[v] {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = v
        i += 1usize
    }
    var k = 0usize
    while k < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += x0[k * n + i]
            i += 1usize
        }
        mean[k] = m / f64(n)
        i = 0usize
        while i < n {
            x[k * n + i] = x0[k * n + i] - mean[k]
            i += 1usize
        }
        beta[k] = 0.0f64
        k += 1usize
    }
    var cur = evaluate(order, time, status, x, n, p, beta, efron, u, info, rx, rxx, dx, dxx, xbar)
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
            nll = evaluate(order, time, status, x, n, p, nb, efron, u, info, rx, rxx, dx, dxx, xbar)
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
    cur = evaluate(order, time, status, x, n, p, beta, efron, u, info, rx, rxx, dx, dxx, xbar)
    ll[1usize] = cur
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
        se[c] = math.sqrt[f64](step[c])
        coef[c] = beta[c]
        c += 1usize
    }
    ret ok
}
