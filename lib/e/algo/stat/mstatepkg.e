// e.algo.stat.mstatepkg: the mstate package's probtrans (forward, no variance): the Aalen-Johansen estimate, the product over the event times after predt of (I + dA), where dA has the
// increments of the cumulative transition hazards off the diagonal and minus their row sums on it.

use e.math
use e.mem

// from[k], to[k]: the states (0-based) of transition k; cum is trans-major (cum[k * nt + t] the cumulative hazard of transition k at times[t]); out receives, for each of the
// returned count + 1 rows, the S by S matrix P(predt, .) row-major: row 0 is the identity at predt, row i the product after the i-th event time greater than predt.
fn probtrans_forward(a: *mem.Arena, s: usize, ntrans: usize, from: []const usize, to: []const usize, nt: usize, times: []const f64, cum: []const f64, predt: f64, out: []f64) -> (usize, err) {
    let (p, e0) = mem.alloc[f64](a, s * s)
    let (q, e1) = mem.alloc[f64](a, s * s)
    let (d, e2) = mem.alloc[f64](a, s * s)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    var i = 0usize
    while i < s * s {
        p[i] = 0.0f64
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < s {
        p[i * s + i] = 1.0f64
        out[i * s + i] = 1.0f64
        i += 1usize
    }
    var rows = 0usize
    var t = 0usize
    while t < nt {
        if times[t] > predt {
            i = 0usize
            while i < s * s {
                d[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < s {
                d[i * s + i] = 1.0f64
                i += 1usize
            }
            var k = 0usize
            while k < ntrans {
                var prev = 0.0f64
                if t > 0usize { prev = cum[k * nt + t - 1usize] }
                let dh = cum[k * nt + t] - prev
                d[from[k] * s + to[k]] = dh
                d[from[k] * s + from[k]] = d[from[k] * s + from[k]] - dh
                k += 1usize
            }
            var r = 0usize
            while r < s {
                var c = 0usize
                while c < s {
                    var v = 0.0f64
                    var m = 0usize
                    while m < s {
                        v += p[r * s + m] * d[m * s + c]
                        m += 1usize
                    }
                    q[r * s + c] = v
                    c += 1usize
                }
                r += 1usize
            }
            i = 0usize
            while i < s * s {
                p[i] = q[i]
                i += 1usize
            }
            rows += 1usize
            i = 0usize
            while i < s * s {
                out[rows * s * s + i] = p[i]
                i += 1usize
            }
        }
        t += 1usize
    }
    ret (rows, ok)
}
