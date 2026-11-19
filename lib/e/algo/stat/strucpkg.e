// R strucchange: the F statistics of a single-break test (Fstats) and the optimal m-break segmentation by dynamic programming (breakpoints, Bai and Perron). The model is y on the columns of x (row-major, n by p, a constant column included by the caller), every coefficient shifting.
//
// Not here: efp, sctest, gefp, mefp, partial-change models, BIC choice and the confidence intervals of the breaks.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// the residual sum of squares of y on x over the rows lo .. hi - 1 (hi exclusive); NaN when singular
fn seg_rss(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, lo: usize, hi: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let start = mem.mark(a)
    let (g, e1) = mem.alloc[f64](a, p * p)
    let (b, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < p * p {
        g[i] = 0.0f64
        i += 1usize
    }
    var r = 0usize
    while r < p {
        b[r] = 0.0f64
        r += 1usize
    }
    var yy = 0.0f64
    var t = lo
    while t < hi {
        yy += y[t] * y[t]
        r = 0usize
        while r < p {
            b[r] += x[t * p + r] * y[t]
            var c = 0usize
            while c < p {
                g[r * p + c] += x[t * p + r] * x[t * p + c]
                c += 1usize
            }
            r += 1usize
        }
        t += 1usize
    }
    let (inv, e3) = gp.invert(a, g, p)
    if e3 != ok {
        mem.reset(a, start)
        ret nan
    }
    var q = 0.0f64
    r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            q += b[r] * inv[r * p + c] * b[c]
            c += 1usize
        }
        r += 1usize
    }
    mem.reset(a, start)
    ret yy - q
}

// Fstats(from, to): out[i - from] for a first segment of i rows, i = from .. to
fn fstats(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize, from: usize, to: usize, out: []f64) {
    let rss = seg_rss(a, y, x, p, 0usize, n)
    var i = from
    while i <= to {
        let r12 = seg_rss(a, y, x, p, 0usize, i) + seg_rss(a, y, x, p, i, n)
        out[i - from] = (rss - r12) / (r12 / f64(n - 2usize * p))
        i += 1usize
    }
}

// the optimal segmentation with m breaks and minimal segment length h: the break positions (last row of each segment but the last, 1-based as R) into bp and the RSS returned
fn breakpoints(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize, h: usize, m: usize, bp: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let w = n + 1usize
    let (cost, e1) = mem.alloc[f64](a, w * w)
    let (best, e2) = mem.alloc[f64](a, (m + 1usize) * w)
    let (from, e3) = mem.alloc[usize](a, (m + 1usize) * w)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    let inf = 1.0f64 / 0.0f64
    var i = 0usize
    while i <= n {
        var j = 0usize
        while j <= n {
            cost[i * w + j] = inf
            if j >= i + h { cost[i * w + j] = seg_rss(a, y, x, p, i, j) }
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j <= n {
        best[j] = cost[j]
        j += 1usize
    }
    var k = 1usize
    while k <= m {
        j = 0usize
        while j <= n {
            var bv = inf
            var bi = 0usize
            i = 0usize
            while i < j {
                let v = best[(k - 1usize) * w + i] + cost[i * w + j]
                if v < bv {
                    bv = v
                    bi = i
                }
                i += 1usize
            }
            best[k * w + j] = bv
            from[k * w + j] = bi
            j += 1usize
        }
        k += 1usize
    }
    var at = n
    k = m
    while k >= 1usize {
        at = from[k * w + at]
        bp[k - 1usize] = f64(at)
        k -= 1usize
    }
    ret best[m * w + n]
}

// strucchange efp(type = "OLS-CUSUM") with sctest: the supremum of the cumulative OLS residuals scaled by sigma sqrt(n) (sigma from n - p degrees of freedom) and its Brownian-bridge
// p value 1 - (1 + 2 sum_{i = 1..100} (-1)^i exp(-2 i^2 s^2)) (1 when the statistic is below 0.1); (statistic, p)
fn ols_cusum(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (g, e1) = mem.alloc[f64](a, p * p)
    let (r, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret (nan, nan) }
    var i = 0usize
    while i < p * p {
        g[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        r[i] = 0.0f64
        i += 1usize
    }
    var t = 0usize
    while t < n {
        var c = 0usize
        while c < p {
            r[c] += x[t * p + c] * y[t]
            var d = 0usize
            while d < p {
                g[c * p + d] += x[t * p + c] * x[t * p + d]
                d += 1usize
            }
            c += 1usize
        }
        t += 1usize
    }
    let (inv, ie) = gp.invert(a, g, p)
    if ie != ok { ret (nan, nan) }
    var sse = 0.0f64
    var cum = 0.0f64
    var peak = 0.0f64
    t = 0usize
    var resid_sum = 0.0f64
    while t < n {
        var fit = 0.0f64
        var c = 0usize
        while c < p {
            var bc = 0.0f64
            var d = 0usize
            while d < p {
                bc += inv[c * p + d] * r[d]
                d += 1usize
            }
            fit += bc * x[t * p + c]
            c += 1usize
        }
        let e = y[t] - fit
        sse += e * e
        resid_sum += e
        t += 1usize
    }
    let sg = math.sqrt[f64](sse / f64(n - p))
    // second pass for the cumulative sum (the coefficients are recomputed per row, which is cheap for the small p used here)
    t = 0usize
    while t < n {
        var fit = 0.0f64
        var c = 0usize
        while c < p {
            var bc = 0.0f64
            var d = 0usize
            while d < p {
                bc += inv[c * p + d] * r[d]
                d += 1usize
            }
            fit += bc * x[t * p + c]
            c += 1usize
        }
        cum += y[t] - fit
        let v = math.abs[f64](cum) / (sg * math.sqrt[f64](f64(n)))
        if v > peak { peak = v }
        t += 1usize
    }
    var pv = 1.0f64
    if peak >= 0.1f64 {
        var s = 0.0f64
        var k = 1usize
        while k <= 100usize {
            var sign = 1.0f64
            if k % 2usize == 1usize { sign = 0.0f64 - 1.0f64 }
            s += sign * math.exp[f64](0.0f64 - 2.0f64 * f64(k * k) * peak * peak)
            k += 1usize
        }
        pv = 1.0f64 - (1.0f64 + 2.0f64 * s)
    }
    ret (peak, pv)
}
