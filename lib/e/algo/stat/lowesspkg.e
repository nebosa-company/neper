// R stats::lowess: the C routine clowess, line for line (tricube weights over the ns nearest points, a local linear fit with the package's curvature correction, linear
// interpolation between points closer than delta, and robustness weights from six times the median absolute residual).
//
// Not here: the R wrapper's sorting of x and the formula interface.

use e.math

// stats::lowess's C routine clowess (Cleveland's robust locally weighted regression): x sorted ascending, ys the smoothed values; w and rw are scratch of n + 2 values and res of n + 2
// (all indexed from 1 internally); f is the smoother span, nsteps the robustness iterations, delta the skip distance
fn lowest(x: []const f64, y: []const f64, n: usize, xs: f64, nleft: usize, nright: usize, w: []f64, userw: bool, rw: []const f64) -> (f64, bool) {
    let range = x[n] - x[1usize]
    var h = xs - x[nleft]
    if x[nright] - xs > h { h = x[nright] - xs }
    let h9 = 0.999f64 * h
    let h1 = 0.001f64 * h
    var a = 0.0f64
    var j = nleft
    while j <= n {
        w[j] = 0.0f64
        let r = math.abs[f64](x[j] - xs)
        if r <= h9 {
            if r <= h1 {
                w[j] = 1.0f64
            } else {
                let q = r / h
                let c = 1.0f64 - q * q * q
                w[j] = c * c * c
            }
            if userw { w[j] = w[j] * rw[j] }
            a += w[j]
        } else if x[j] > xs {
            break
        }
        j += 1usize
    }
    let nrt = j - 1usize
    if a <= 0.0f64 { ret (0.0f64, false) }
    j = nleft
    while j <= nrt {
        w[j] = w[j] / a
        j += 1usize
    }
    if h > 0.0f64 {
        a = 0.0f64
        j = nleft
        while j <= nrt {
            a += w[j] * x[j]
            j += 1usize
        }
        var b = xs - a
        var c = 0.0f64
        j = nleft
        while j <= nrt {
            c += w[j] * (x[j] - a) * (x[j] - a)
            j += 1usize
        }
        if math.sqrt[f64](c) > 0.001f64 * range {
            b = b / c
            j = nleft
            while j <= nrt {
                w[j] = w[j] * (b * (x[j] - a) + 1.0f64)
                j += 1usize
            }
        }
    }
    var yv = 0.0f64
    j = nleft
    while j <= nrt {
        yv += w[j] * y[j]
        j += 1usize
    }
    ret (yv, true)
}

fn sort_part(v: []f64, n: usize) {
    var i = 1usize
    while i < n {
        let t = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > t {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = t
        i += 1usize
    }
}

// x and y of length n + 1 with index 0 unused (1-based), ys of n + 1; scratch w, rw, res of n + 1 each and srt of n
fn clowess(x: []const f64, y: []const f64, n: usize, f: f64, nsteps: usize, delta: f64, ys: []f64, w: []f64, rw: []f64, res: []f64, srt: []f64) {
    if n < 2usize {
        ys[1usize] = y[1usize]
        ret
    }
    var ns = usize(f * f64(n) + 1.0e-7f64)
    if ns > n { ns = n }
    if ns < 2usize { ns = 2usize }
    var iter = 1usize
    while iter <= nsteps + 1usize {
        var nleft = 1usize
        var nright = ns
        var last = 0usize
        var i = 1usize
        while true {
            if nright < n {
                let d1 = x[i] - x[nleft]
                let d2 = x[nright + 1usize] - x[i]
                if d1 > d2 {
                    nleft += 1usize
                    nright += 1usize
                    continue
                }
            }
            let (yv, ok2) = lowest(x, y, n, x[i], nleft, nright, w, iter > 1usize, rw)
            if ok2 { ys[i] = yv } else { ys[i] = y[i] }
            if last + 1usize < i {
                let denom = x[i] - x[last]
                var j = last + 1usize
                while j < i {
                    let alpha = (x[j] - x[last]) / denom
                    ys[j] = alpha * ys[i] + (1.0f64 - alpha) * ys[last]
                    j += 1usize
                }
            }
            last = i
            let cut = x[last] + delta
            i = last + 1usize
            while i <= n {
                if x[i] > cut { break }
                if x[i] == x[last] {
                    ys[i] = ys[last]
                    last = i
                }
                i += 1usize
            }
            var nxt = i - 1usize
            if last + 1usize > nxt { nxt = last + 1usize }
            i = nxt
            if last >= n { break }
        }
        var k = 0usize
        while k < n {
            res[k] = y[k + 1usize] - ys[k + 1usize]
            k += 1usize
        }
        var sc = 0.0f64
        k = 0usize
        while k < n {
            sc += math.abs[f64](res[k])
            k += 1usize
        }
        sc = sc / f64(n)
        if iter > nsteps { break }
        k = 0usize
        while k < n {
            srt[k] = math.abs[f64](res[k])
            k += 1usize
        }
        sort_part(srt, n)
        let m1 = n / 2usize
        var cmad = 0.0f64
        if n % 2usize == 0usize {
            let m2 = n - m1 - 1usize
            cmad = 3.0f64 * (srt[m1] + srt[m2])
        } else {
            cmad = 6.0f64 * srt[m1]
        }
        if cmad < 1.0e-7f64 * sc { break }
        let c9 = 0.999f64 * cmad
        let c1 = 0.001f64 * cmad
        k = 0usize
        while k < n {
            let r = math.abs[f64](res[k])
            if r <= c1 {
                rw[k + 1usize] = 1.0f64
            } else if r <= c9 {
                let q = r / cmad
                let u = 1.0f64 - q * q
                rw[k + 1usize] = u * u
            } else {
                rw[k + 1usize] = 0.0f64
            }
            k += 1usize
        }
        iter += 1usize
    }
}
