// R nnls: the Lawson-Hanson active-set solution of min |A x - b| subject to x >= 0 for a matrix given
// column-major (m rows, n columns): the solution, the deviance (squared residual norm) and the passive
// set. The least-squares step on the passive columns goes through the Householder QR of e.algo.linalg.decomp.
//
// Not here: the linear-independence guard the Fortran applies to nearly dependent columns.

use e.algo.linalg.decomp as decomp
use e.mem

type Solution = struct { x: []f64, deviance: f64, passive: []usize, npassive: usize, iterations: usize }

fn nnls(a: *mem.Arena, am: []const f64, m: usize, n: usize, b: []const f64) -> (Solution, err) {
    var none: Solution = zero
    let (x, xe) = mem.alloc[f64](a, n)
    let (inp, ie) = mem.alloc[bool](a, n)
    let (res, re) = mem.alloc[f64](a, m)
    let (w, we) = mem.alloc[f64](a, n)
    let (order, oe) = mem.alloc[usize](a, n)
    if xe != ok { ret (none, xe) }
    if ie != ok { ret (none, ie) }
    if re != ok { ret (none, re) }
    if we != ok { ret (none, we) }
    if oe != ok { ret (none, oe) }
    var j = 0usize
    while j < n {
        x[j] = 0.0f64
        inp[j] = false
        j += 1usize
    }
    var np = 0usize
    var iters = 0usize
    var outer = 0usize
    while outer < 3usize * n + 10usize {
        // residual and dual
        var i = 0usize
        while i < m {
            var s = b[i]
            j = 0usize
            while j < n {
                s -= am[j * m + i] * x[j]
                j += 1usize
            }
            res[i] = s
            i += 1usize
        }
        var best = 0usize
        var wmax = 0.0f64
        var found = false
        j = 0usize
        while j < n {
            var s = 0.0f64
            i = 0usize
            while i < m {
                s += am[j * m + i] * res[i]
                i += 1usize
            }
            w[j] = s
            if !inp[j] && s > wmax {
                wmax = s
                best = j
                found = true
            }
            j += 1usize
        }
        if !found { break }
        inp[best] = true
        order[np] = best
        np += 1usize
        var inner = 0usize
        var done = false
        while !done && inner < 3usize * n + 10usize {
            inner += 1usize
            iters += 1usize
            // least squares on the passive columns
            let (sub, se) = mem.alloc[f64](a, m * np)
            if se != ok { ret (none, se) }
            var cols: [64]usize = zero
            var cn = 0usize
            j = 0usize
            while j < n {
                if inp[j] {
                    i = 0usize
                    while i < m {
                        sub[cn * m + i] = am[j * m + i]
                        i += 1usize
                    }
                    cols[cn] = j
                    cn += 1usize
                }
                j += 1usize
            }
            let (fit, fe) = decomp.lm_fit(a, sub, m, cn, b, 1.0e-12f64)
            if fe != ok { ret (none, fe) }
            let (z, ze) = mem.alloc[f64](a, n)
            if ze != ok { ret (none, ze) }
            j = 0usize
            while j < n {
                z[j] = 0.0f64
                j += 1usize
            }
            var k = 0usize
            while k < cn {
                var c = fit.coef[k]
                if c != c { c = 0.0f64 }
                z[cols[k]] = c
                k += 1usize
            }
            var feasible = true
            k = 0usize
            while k < cn {
                if z[cols[k]] <= 0.0f64 { feasible = false }
                k += 1usize
            }
            if feasible {
                j = 0usize
                while j < n {
                    x[j] = z[j]
                    j += 1usize
                }
                done = true
            } else {
                var alpha = 1.0e308f64
                k = 0usize
                while k < cn {
                    let q = cols[k]
                    if z[q] <= 0.0f64 {
                        let t = x[q] / (x[q] - z[q])
                        if t < alpha { alpha = t }
                    }
                    k += 1usize
                }
                j = 0usize
                while j < n {
                    x[j] = x[j] + alpha * (z[j] - x[j])
                    j += 1usize
                }
                np = 0usize
                j = 0usize
                while j < n {
                    if inp[j] && x[j] > 1.0e-14f64 {
                        order[np] = j
                        np += 1usize
                    } else if inp[j] {
                        inp[j] = false
                        x[j] = 0.0f64
                    }
                    j += 1usize
                }
            }
        }
        outer += 1usize
    }
    var dev = 0.0f64
    var i = 0usize
    while i < m {
        var s = b[i]
        j = 0usize
        while j < n {
            s -= am[j * m + i] * x[j]
            j += 1usize
        }
        dev += s * s
        i += 1usize
    }
    ret (Solution { x: x, deviance: dev, passive: order, npassive: np, iterations: iters }, ok)
}
