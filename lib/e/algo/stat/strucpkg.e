// R strucchange: the F statistics of a single-break test (Fstats) and the optimal m-break segmentation by dynamic programming (breakpoints, Bai and Perron). The model is y on the columns of x (row-major, n by p, a constant column included by the caller), every coefficient shifting.
//
// Not here: efp, sctest, gefp, mefp, partial-change models, BIC choice and the confidence intervals of the breaks.

use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem
use e.algo.stat.strucpkg_tables as tb
use e.str

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

// the recursive residuals w_r = (y_r - x_r b_(r-1)) / sqrt(1 + x_r (X'X)_(r-1)^-1 x_r), r = p + 1 .. n, into w (length n - p); false when a design is singular
fn rec_resid(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize, w: []f64) -> bool {
    var r = p
    while r < n {
        let start = mem.mark(a)
        let (g, e1) = mem.alloc[f64](a, p * p)
        let (rv, e2) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok { ret false }
        var i = 0usize
        while i < p * p {
            g[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < p {
            rv[i] = 0.0f64
            i += 1usize
        }
        var t = 0usize
        while t < r {
            var c = 0usize
            while c < p {
                rv[c] += x[t * p + c] * y[t]
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
        if ie != ok { ret false }
        var pred = 0.0f64
        var quad = 0.0f64
        var c = 0usize
        while c < p {
            var bc = 0.0f64
            var qc = 0.0f64
            var d = 0usize
            while d < p {
                bc += inv[c * p + d] * rv[d]
                qc += inv[c * p + d] * x[r * p + d]
                d += 1usize
            }
            pred += bc * x[r * p + c]
            quad += qc * x[r * p + c]
            c += 1usize
        }
        w[r - p] = (y[r] - pred) / math.sqrt[f64](1.0f64 + quad)
        mem.reset(a, start)
        r += 1usize
    }
    ret true
}

// strucchange efp(type = "Rec-CUSUM") with sctest: the recursive residuals w_r = (y_r - x_r b_(r-1)) / sqrt(1 + x_r (X'X)_(r-1)^-1 x_r), r = p + 1 .. n, scaled by their
// standard deviation (n - p - 1 degrees of freedom) and sqrt(n - p); the statistic is the largest |W_j| / (1 + 2 j / (n - p)) and the p value is the Brownian-motion
// boundary formula; (statistic, p)
fn rec_cusum(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let m = n - p
    let (w, e0) = mem.alloc[f64](a, m)
    if e0 != ok { ret (nan, nan) }
    if !rec_resid(a, y, x, n, p, w) { ret (nan, nan) }
    var mean = 0.0f64
    var i2 = 0usize
    while i2 < m {
        mean += w[i2]
        i2 += 1usize
    }
    mean = mean / f64(m)
    var ss = 0.0f64
    i2 = 0usize
    while i2 < m {
        ss += (w[i2] - mean) * (w[i2] - mean)
        i2 += 1usize
    }
    let sg = math.sqrt[f64](ss / f64(m - 1usize))
    var cum = 0.0f64
    var peak = 0.0f64
    i2 = 0usize
    while i2 < m {
        cum += w[i2]
        let v = math.abs[f64](cum / (sg * math.sqrt[f64](f64(m)))) / (1.0f64 + 2.0f64 * f64(i2 + 1usize) / f64(m))
        if v > peak { peak = v }
        i2 += 1usize
    }
    var pv = 0.0f64
    if peak < 0.3f64 {
        pv = 1.0f64 - 0.1465f64 * peak
    } else {
        let pn1 = dist.pnorm(3.0f64 * peak, 0.0f64, 1.0f64, true, false)
        let pn2 = dist.pnorm(peak, 0.0f64, 1.0f64, true, false)
        let pn3 = dist.pnorm(5.0f64 * peak, 0.0f64, 1.0f64, true, false)
        pv = 2.0f64 * (1.0f64 - pn1 + math.exp[f64](-4.0f64 * peak * peak) * (pn2 + pn3 - 1.0f64) - math.exp[f64](-16.0f64 * peak * peak) * (1.0f64 - pn2))
    }
    ret (peak, pv)
}

// the idx-th (0-based) number of a semicolon-separated table
fn table_value(t: str, idx: usize) -> f64 {
    var start = 0usize
    var seen = 0usize
    var i = 0usize
    while i < t.len {
        if t[i] == 59u8 {
            if seen == idx {
                let (v, e) = str.parse_f64(t[start..i])
                if e != ok { ret 0.0f64 / 0.0f64 }
                ret v
            }
            seen += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    let (v2, e2) = str.parse_f64(t[start..t.len])
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    ret v2
}


// strucchange sctest(Fstats) p value for the statistic x of regression count k <= 5 and trimming tau (type 0 supF, 1 aveF, 2 expF): the table row of beta evaluated as a polynomial
// of x, clipped at zero, then 1 - pchisq against the tabulated degrees of freedom, interpolated between the two rows next to tau
fn pvalue_fstats(ty: usize, x: f64, k: usize, tau: f64) -> f64 {
    var nc = 5usize
    if ty == 0usize { nc = 3usize }
    let m = nc - 1usize
    var pp: [25]f64 = zero
    var r = 0usize
    while r < 25usize {
        let row = ((k - 1usize) * 25usize + r) * nc
        var dummy = 0.0f64
        var xp = 1.0f64
        var j = 0usize
        while j < m {
            var cf = table_value(tb.sc_sup(), row + j)
            if ty == 1usize { cf = table_value(tb.sc_ave(), row + j) }
            if ty == 2usize { cf = table_value(tb.sc_exp(), row + j) }
            dummy += cf * xp
            xp = xp * x
            j += 1usize
        }
        if dummy < 0.0f64 { dummy = 0.0f64 }
        var dfv = table_value(tb.sc_sup(), row + m)
        if ty == 1usize { dfv = table_value(tb.sc_ave(), row + m) }
        if ty == 2usize { dfv = table_value(tb.sc_exp(), row + m) }
        pp[r] = 1.0f64 - nm.pchisq(dummy, dfv, true, false)
        r += 1usize
    }
    if tau == 0.5f64 { ret 1.0f64 - nm.pchisq(x, f64(k), true, false) }
    if tau <= 0.01f64 { ret pp[24usize] }
    if tau >= 0.49f64 { ret ((0.5f64 - tau) * pp[0usize] + (tau - 0.49f64) * (1.0f64 - nm.pchisq(x, f64(k), true, false))) * 100.0f64 }
    let taua = (0.51f64 - tau) * 50.0f64
    let tau1 = math.floor[f64](taua)
    let i1 = usize(tau1)
    ret (tau1 + 1.0f64 - taua) * pp[i1 - 1usize] + (taua - tau1) * pp[i1]
}

// linear interpolation of y over the increasing grid xs at v, clamped at the ends (R's approx with rule = 2)
fn approx_rule2(xs: []const f64, ys: []const f64, v: f64) -> f64 {
    let n = xs.len
    if v <= xs[0usize] { ret ys[0usize] }
    if v >= xs[n - 1usize] { ret ys[n - 1usize] }
    var i = 1usize
    while i < n {
        if v <= xs[i] {
            ret ys[i - 1usize] + (ys[i] - ys[i - 1usize]) * (v - xs[i - 1usize]) / (xs[i] - xs[i - 1usize])
        }
        i += 1usize
    }
    ret ys[n - 1usize]
}

// strucchange efp(type = "OLS-MOSUM", h) with sctest: the largest |moving sum of nh = floor(n h) OLS residuals| / (sigma sqrt(n)) and its p value interpolated in the table sc.me
// (columns for p = 0.1, 0.05, 0.025, 0.01, rows h = 0.05 .. 0.5); (statistic, p)
fn ols_mosum(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize, h: f64) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (g, e1) = mem.alloc[f64](a, p * p)
    let (r, e2) = mem.alloc[f64](a, p)
    let (res, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (nan, nan) }
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
        res[t] = y[t] - fit
        sse += res[t] * res[t]
        t += 1usize
    }
    let sg = math.sqrt[f64](sse / f64(n - p))
    let nh = usize(math.floor[f64](f64(n) * h))
    var win = 0.0f64
    t = 0usize
    while t < nh {
        win += res[t]
        t += 1usize
    }
    var peak = math.abs[f64](win)
    t = nh
    while t < n {
        win += res[t] - res[t - nh]
        if math.abs[f64](win) > peak { peak = math.abs[f64](win) }
        t += 1usize
    }
    peak = peak / (sg * math.sqrt[f64](f64(n)))
    var tableh: [10]f64 = zero
    var q = 0usize
    while q < 10usize {
        tableh[q] = 0.05f64 * f64(q + 1usize)
        q += 1usize
    }
    var col: [10]f64 = zero
    var ipl: [5]f64 = zero
    var pgrid: [5]f64 = zero
    pgrid[0usize] = 0.0f64
    ipl[0usize] = 1.0f64
    var tp: [5]f64 = zero
    tp[0usize] = 1.0f64
    tp[1usize] = 0.1f64
    tp[2usize] = 0.05f64
    tp[3usize] = 0.025f64
    tp[4usize] = 0.01f64
    let tab = tb.sc_me()
    var cidx = 0usize
    while cidx < 4usize {
        q = 0usize
        while q < 10usize {
            col[q] = table_value(tab, q * 4usize + cidx)
            q += 1usize
        }
        pgrid[cidx + 1usize] = approx_rule2(tableh[0usize..10usize], col[0usize..10usize], h)
        cidx += 1usize
    }
    ret (peak, approx_rule2(pgrid[0usize..5usize], tp[0usize..5usize], peak))
}

// strucchange efp(type = "Rec-MOSUM", h) with sctest: the largest absolute moving sum of nh = floor((n - p) h) recursive residuals over sigma sqrt(n - p), sigma^2 being the centred sum of
// squares of the residuals over n - 2p degrees of freedom; the p value interpolates the Brownian-motion-increments table (columns p = 0.2 .. 0.01, scaled by sqrt(h) per row) in h
// and then the statistic; (statistic, p)
fn rec_mosum(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize, h: f64) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let m = n - p
    let (w, e0) = mem.alloc[f64](a, m)
    if e0 != ok { ret (nan, nan) }
    if !rec_resid(a, y, x, n, p, w) { ret (nan, nan) }
    var mean = 0.0f64
    var i = 0usize
    while i < m {
        mean += w[i]
        i += 1usize
    }
    mean = mean / f64(m)
    var ss = 0.0f64
    i = 0usize
    while i < m {
        ss += (w[i] - mean) * (w[i] - mean)
        i += 1usize
    }
    let sg = math.sqrt[f64](ss / f64(m - p))
    let nh = usize(math.floor[f64](f64(m) * h))
    var win = 0.0f64
    i = 0usize
    while i < nh {
        win += w[i]
        i += 1usize
    }
    var peak = math.abs[f64](win)
    i = nh
    while i < m {
        win += w[i] - w[i - nh]
        if math.abs[f64](win) > peak { peak = math.abs[f64](win) }
        i += 1usize
    }
    peak = peak / (sg * math.sqrt[f64](f64(m)))
    var tableh: [10]f64 = zero
    var q = 0usize
    while q < 10usize {
        tableh[q] = 0.05f64 * f64(q + 1usize)
        q += 1usize
    }
    let crit = tb.sc_rm()
    var col: [10]f64 = zero
    var grid: [7]f64 = zero
    var tp: [7]f64 = zero
    tp[0usize] = 1.0f64
    tp[1usize] = 0.2f64
    tp[2usize] = 0.15f64
    tp[3usize] = 0.1f64
    tp[4usize] = 0.05f64
    tp[5usize] = 0.025f64
    tp[6usize] = 0.01f64
    var cidx = 0usize
    while cidx < 6usize {
        q = 0usize
        while q < 10usize {
            col[q] = table_value(crit, q * 6usize + cidx) * math.sqrt[f64](tableh[q])
            q += 1usize
        }
        grid[cidx + 1usize] = approx_rule2(tableh[0usize..10usize], col[0usize..10usize], h)
        cidx += 1usize
    }
    ret (peak, approx_rule2(grid[0usize..7usize], tp[0usize..7usize], peak))
}

// strucchange's BIC of the model with m breaks (summary.breakpointsfull): n (log RSS + 1 - log n + log 2 pi) + log n ((m + 1) p + m + 1), the (m + 1) p coefficients, the m break points and the variance
fn breakpoints_bic(rss: f64, n: usize, p: usize, m: usize) -> f64 {
    let nf = f64(n)
    ret nf * (math.log[f64](rss) + 1.0f64 - math.log[f64](nf) + math.log[f64](2.0f64 * 3.141592653589793f64)) + math.log[f64](nf) * (f64((m + 1usize) * p + m + 1usize))
}
