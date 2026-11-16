// R timereg aalen: Aalen's additive hazards model with non-parametric cumulative regression functions, the least-squares increments (X'X)^-1 x_i at every event time, with an intercept; the cumulative coefficients are returned at each distinct event time (a time whose risk-set design is singular keeps the previous value, as in timereg).
//
// Not here: robust variances, resampling tests, constant effects (the semi-parametric model), weights, the Cox-Aalen model, other timereg models.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// t, d (1 = event), x (n by p, no constant column); cum receives one row of p + 1 cumulative coefficients (intercept first) for each of up to n event times and times their event times; returns the number of rows written
fn aalen(a: *mem.Arena, t: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, cum: []f64, times: []f64) -> usize {
    let q = p + 1usize
    let (g, e1) = mem.alloc[f64](a, q * q)
    let (cur, e2) = mem.alloc[f64](a, q)
    let (xi, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var i = 0usize
    while i < q {
        cur[i] = 0.0f64
        i += 1usize
    }
    var rows = 0usize
    var done = 0usize
    // visit events in increasing time order
    let (ord, e4) = mem.alloc[usize](a, n)
    if e4 != ok { ret 0usize }
    i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && t[ord[j - 1usize]] > t[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    var pos = 0usize
    while pos < n {
        let who = ord[pos]
        if d[who] > 0.5f64 {
            let tt = t[who]
            let start = mem.mark(a)
            i = 0usize
            while i < q * q {
                g[i] = 0.0f64
                i += 1usize
            }
            var r = 0usize
            while r < n {
                if t[r] >= tt {
                    var c1 = 0usize
                    while c1 < q {
                        var v1 = 1.0f64
                        if c1 > 0usize { v1 = x[r * p + c1 - 1usize] }
                        var c2 = 0usize
                        while c2 < q {
                            var v2 = 1.0f64
                            if c2 > 0usize { v2 = x[r * p + c2 - 1usize] }
                            g[c1 * q + c2] += v1 * v2
                            c2 += 1usize
                        }
                        c1 += 1usize
                    }
                }
                r += 1usize
            }
            let (gi, ge) = gp.invert(a, g, q)
            var well = ge == ok
            if well {
                var ng = 0.0f64
                var ni = 0.0f64
                var c1 = 0usize
                while c1 < q {
                    var cg = 0.0f64
                    var ci = 0.0f64
                    var r1 = 0usize
                    while r1 < q {
                        cg += math.abs[f64](g[r1 * q + c1])
                        ci += math.abs[f64](gi[r1 * q + c1])
                        r1 += 1usize
                    }
                    if cg > ng { ng = cg }
                    if ci > ni { ni = ci }
                    c1 += 1usize
                }
                if ng * ni > 1.0e11f64 { well = false }
            }
            if well {
                xi[0usize] = 1.0f64
                i = 1usize
                while i < q {
                    xi[i] = x[who * p + i - 1usize]
                    i += 1usize
                }
                i = 0usize
                while i < q {
                    var s = 0.0f64
                    var l = 0usize
                    while l < q {
                        s += gi[i * q + l] * xi[l]
                        l += 1usize
                    }
                    cur[i] += s
                    i += 1usize
                }
            }
            i = 0usize
            while i < q {
                cum[rows * q + i] = cur[i]
                i += 1usize
            }
            times[rows] = tt
            rows += 1usize
            mem.reset(a, start)
            done += 1usize
        }
        pos += 1usize
    }
    ret rows
}
