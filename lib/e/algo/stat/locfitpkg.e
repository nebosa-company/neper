// R locfit local polynomial regression with the tricube kernel evaluated directly at the data points (ev = dat()): the bandwidth is the distance to the floor(nn n)-th nearest point (nn) or a fixed h, the weights (1 - |u|^3)^3 for |u| < 1, the fit a weighted polynomial of the given degree about each point.
//
// Not here: other kernels, local likelihood families, adaptive and interpolated evaluation, confidence bands, bandwidth selection (gcv, cp), several predictors.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// out receives the fitted values at the data points; h <= 0 uses nn
fn lpfit(a: *mem.Arena, x: []const f64, y: []const f64, nn: f64, h0: f64, deg: usize, out: []f64) -> err {
    let n = x.len
    let q = deg + 1usize
    let (d, e1) = mem.alloc[f64](a, n)
    let (s, e2) = mem.alloc[f64](a, n)
    let (w, e3) = mem.alloc[f64](a, n)
    let (g, e4) = mem.alloc[f64](a, q * q)
    let (r, e5) = mem.alloc[f64](a, q)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < n {
        var t = 0usize
        while t < n {
            d[t] = math.abs[f64](x[t] - x[i])
            s[t] = d[t]
            t += 1usize
        }
        var h = h0
        if h0 <= 0.0f64 {
            t = 1usize
            while t < n {
                let v = s[t]
                var j = t
                while j > 0usize && s[j - 1usize] > v {
                    s[j] = s[j - 1usize]
                    j -= 1usize
                }
                s[j] = v
                t += 1usize
            }
            h = s[usize(math.floor[f64](nn * f64(n))) - 1usize]
        }
        var c = 0usize
        while c < q * q {
            g[c] = 0.0f64
            c += 1usize
        }
        c = 0usize
        while c < q {
            r[c] = 0.0f64
            c += 1usize
        }
        t = 0usize
        while t < n {
            var wt = 0.0f64
            let u = d[t] / h
            if u < 1.0f64 {
                let v = 1.0f64 - u * u * u
                wt = v * v * v
            }
            w[t] = wt
            if wt > 0.0f64 {
                var pa = 0usize
                while pa < q {
                    let xa = math.pow[f64](x[t] - x[i], f64(pa))
                    r[pa] += wt * xa * y[t]
                    var pb = 0usize
                    while pb < q {
                        g[pa * q + pb] += wt * xa * math.pow[f64](x[t] - x[i], f64(pb))
                        pb += 1usize
                    }
                    pa += 1usize
                }
            }
            t += 1usize
        }
        let (gi, ge) = gp.invert(a, g, q)
        if ge != ok { ret ge }
        var f = 0.0f64
        c = 0usize
        while c < q {
            f += gi[c] * r[c]
            c += 1usize
        }
        out[i] = f
        i += 1usize
    }
    ret ok
}
