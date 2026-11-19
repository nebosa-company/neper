// R strucchange: the F statistics of a single-break test (Fstats) and the optimal m-break segmentation by dynamic programming (breakpoints, Bai and Perron). The model is y on the columns of x (row-major, n by p, a constant column included by the caller), every coefficient shifting.
//
// Not here: efp, sctest, gefp, mefp, partial-change models, BIC choice and the confidence intervals of the breaks.

use e.algo.stat.arm as ar
use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
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

// segmented::davies.test for a linear model (the exact daviesLM of the package, n <= 300): the new term pmax(z - psi, 0) is added in front of the n by p design xreg for each of the k
// values psi = seq(sort(z)[2], sort(z)[n - 1], length = k); the t statistic of its coefficient is kept, the variation V of asin(sqrt(share of the squared coefficient in the deviance))
// gives Davies' upper bound added to the naive p value of the extreme statistic. alt 0 two-sided, 1 less, 2 greater; out = (the psi of the extreme statistic, the adjusted p value (capped
// at 1), the number of usable points)
fn davies_lm(a: *mem.Arena, y: []const f64, z: []const f64, xreg: []const f64, n: usize, p: usize, k: usize, alt: usize, out: []f64) -> err {
    let (zs, e0) = mem.alloc[f64](a, n)
    let (vals, e1) = mem.alloc[f64](a, k)
    let (tv, e2) = mem.alloc[f64](a, k)
    let (sh, e3) = mem.alloc[f64](a, k)
    let (ok_, e4) = mem.alloc[bool](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e0 }
    var i = 0usize
    while i < n {
        zs[i] = z[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = zs[i]
        var j = i
        while j > 0usize && zs[j - 1usize] > v {
            zs[j] = zs[j - 1usize]
            j -= 1usize
        }
        zs[j] = v
        i += 1usize
    }
    let lo = zs[1usize]
    let hi = zs[n - 2usize]
    let q = p + 1usize
    let dfres = f64(n) - f64(p) - 1.0f64
    i = 0usize
    while i < k {
        vals[i] = lo + (hi - lo) * f64(i) / f64(k - 1usize)
        let start = mem.mark(a)
        let (xtx, f1) = mem.alloc[f64](a, q * q)
        let (xty, f2) = mem.alloc[f64](a, q)
        let (xr, f3) = mem.alloc[f64](a, q)
        if f1 != ok || f2 != ok || f3 != ok { ret f1 }
        var r = 0usize
        while r < q * q {
            xtx[r] = 0.0f64
            r += 1usize
        }
        r = 0usize
        while r < q {
            xty[r] = 0.0f64
            r += 1usize
        }
        var t = 0usize
        while t < n {
            var psi = z[t] - vals[i]
            if psi < 0.0f64 { psi = 0.0f64 }
            xr[0usize] = psi
            var c = 0usize
            while c < p {
                xr[1usize + c] = xreg[t * p + c]
                c += 1usize
            }
            var c1 = 0usize
            while c1 < q {
                xty[c1] += xr[c1] * y[t]
                var c2 = 0usize
                while c2 < q {
                    xtx[c1 * q + c2] += xr[c1] * xr[c2]
                    c2 += 1usize
                }
                c1 += 1usize
            }
            t += 1usize
        }
        let (inv, ie) = gp.invert(a, xtx, q)
        ok_[i] = ie == ok
        if ie == ok {
            var b0 = 0.0f64
            var c = 0usize
            while c < q {
                b0 += inv[c] * xty[c]
                c += 1usize
            }
            var bh: [16]f64 = zero
            r = 0usize
            while r < q {
                var v = 0.0f64
                c = 0usize
                while c < q {
                    v += inv[r * q + c] * xty[c]
                    c += 1usize
                }
                bh[r] = v
                r += 1usize
            }
            var dev = 0.0f64
            t = 0usize
            while t < n {
                var psi = z[t] - vals[i]
                if psi < 0.0f64 { psi = 0.0f64 }
                var fit = bh[0usize] * psi
                c = 0usize
                while c < p {
                    fit += bh[1usize + c] * xreg[t * p + c]
                    c += 1usize
                }
                dev += (y[t] - fit) * (y[t] - fit)
                t += 1usize
            }
            let sg = math.sqrt[f64](dev / dfres)
            tv[i] = bh[0usize] / (sg * math.sqrt[f64](inv[0usize]))
            let zz = bh[0usize] / math.sqrt[f64](inv[0usize])
            sh[i] = zz * zz / (zz * zz + dev)
        }
        mem.reset(a, start)
        i += 1usize
    }
    var m_ = 0.0f64
    var best = 0.0f64
    var cnt = 0usize
    var vsum = 0.0f64
    var prev = 0.0f64
    var havep = false
    var first = true
    i = 0usize
    while i < k {
        if ok_[i] {
            cnt += 1usize
            let a_ = math.asin(math.sqrt[f64](sh[i]))
            if havep { vsum += math.abs[f64](a_ - prev) }
            prev = a_
            havep = true
            var cand = tv[i]
            if alt == 0usize { cand = math.abs[f64](tv[i]) }
            var better = false
            if first { better = true } else if alt == 1usize { better = cand < m_ } else { better = cand > m_ }
            if better {
                m_ = cand
                best = vals[i]
                first = false
            }
        }
        i += 1usize
    }
    var pnaive = nb.pt(m_, dfres, false, false)
    if alt == 1usize { pnaive = nb.pt(m_, dfres, true, false) }
    let u = m_ * m_ / ((f64(n) - f64(q)) + m_ * m_)
    let approxx = vsum * (math.pow[f64](1.0f64 - u, (dfres - 1.0f64) / 2.0f64) * nm.gammafn(dfres / 2.0f64 + 0.5f64)) / (2.0f64 * nm.gammafn(dfres / 2.0f64) * math.sqrt[f64](3.141592653589793f64))
    var padj = pnaive + approxx
    if alt == 0usize { padj = 2.0f64 * padj }
    if padj > 1.0f64 { padj = 1.0f64 }
    out[0usize] = best
    out[1usize] = padj
    out[2usize] = f64(cnt)
    ret ok
}

// segmented::pscore.test for an lm (one break): the score of the term mean_k pmax(z - psi_k, 0), psi = seq(min z, max z, length = k), after the n by p design xreg; stat = sc / (sigma sqrt(v)), sigma^2 the
// residual variance of the model, p from t with n - p degrees of freedom (alt 0 two-sided, 1 less, 2 greater); out = (stat, p)
fn pscore_lm(a: *mem.Arena, y: []const f64, z: []const f64, xreg: []const f64, n: usize, p: usize, k: usize, alt: usize, out: []f64) -> err {
    var zmin = z[0usize]
    var zmax = z[0usize]
    var i = 0usize
    while i < n {
        if z[i] < zmin { zmin = z[i] }
        if z[i] > zmax { zmax = z[i] }
        i += 1usize
    }
    let (pm, e0) = mem.alloc[f64](a, n)
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok { ret e0 }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            let psi = zmin + (zmax - zmin) * f64(j) / f64(k - 1usize)
            var v = z[i] - psi
            if v < 0.0f64 { v = 0.0f64 }
            s += v
            j += 1usize
        }
        pm[i] = s / f64(k)
        i += 1usize
    }
    var r = 0usize
    while r < p * p {
        xtx[r] = 0.0f64
        r += 1usize
    }
    i = 0usize
    while i < n {
        var c1 = 0usize
        while c1 < p {
            var c2 = 0usize
            while c2 < p {
                xtx[c1 * p + c2] += xreg[i * p + c1] * xreg[i * p + c2]
                c2 += 1usize
            }
            c1 += 1usize
        }
        i += 1usize
    }
    let (inv, ie) = gp.invert(a, xtx, p)
    if ie != ok { ret ie }
    let (resy, e2) = mem.alloc[f64](a, n)
    let (resp, e3) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok { ret e2 }
    var pass = 0usize
    while pass < 2usize {
        var xt: [64]f64 = zero
        i = 0usize
        while i < n {
            var c = 0usize
            while c < p {
                if pass == 0usize { xt[c] += xreg[i * p + c] * y[i] } else { xt[c] += xreg[i * p + c] * pm[i] }
                c += 1usize
            }
            i += 1usize
        }
        var bh: [64]f64 = zero
        var c1 = 0usize
        while c1 < p {
            var c2 = 0usize
            while c2 < p {
                bh[c1] += inv[c1 * p + c2] * xt[c2]
                c2 += 1usize
            }
            c1 += 1usize
        }
        i = 0usize
        while i < n {
            var fit = 0.0f64
            var c = 0usize
            while c < p {
                fit += bh[c] * xreg[i * p + c]
                c += 1usize
            }
            if pass == 0usize { resy[i] = y[i] - fit } else { resp[i] = pm[i] - fit }
            i += 1usize
        }
        pass += 1usize
    }
    var sc = 0.0f64
    var vs = 0.0f64
    var rss = 0.0f64
    i = 0usize
    while i < n {
        sc += resp[i] * y[i]
        vs += resp[i] * pm[i]
        rss += resy[i] * resy[i]
        i += 1usize
    }
    let df = f64(n) - f64(p)
    let sg = math.sqrt[f64](rss / df)
    let st = sc / (sg * math.sqrt[f64](vs))
    var pv = 2.0f64 * nb.pt(math.abs[f64](st), df, false, false)
    if alt == 1usize { pv = nb.pt(st, df, true, false) }
    if alt == 2usize { pv = nb.pt(st, df, false, false) }
    out[0usize] = st
    out[1usize] = pv
    ret ok
}

// residuals of v on the n by p design xreg given inv = (X'X)^-1
fn resid_on(inv: []const f64, xreg: []const f64, v: []const f64, n: usize, p: usize, out: []f64) {
    var xt: [64]f64 = zero
    var bh: [64]f64 = zero
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xt[c] += xreg[i * p + c] * v[i]
            c += 1usize
        }
        i += 1usize
    }
    var c1 = 0usize
    while c1 < p {
        var c2 = 0usize
        while c2 < p {
            bh[c1] += inv[c1 * p + c2] * xt[c2]
            c2 += 1usize
        }
        c1 += 1usize
    }
    i = 0usize
    while i < n {
        var fit = 0.0f64
        var c = 0usize
        while c < p {
            fit += bh[c] * xreg[i * p + c]
            c += 1usize
        }
        out[i] = v[i] - fit
        i += 1usize
    }
}

// segmented::pscore.test with n.break = 2 for an lm: the two terms mean_j pmax(z - psi_j, 0) and mean over pairs j > l of pmax(z - psi_j, 0); stat = sc' V^-1 sc / sigma^2 on chi-square(2); out = (stat, p)
fn pscore2_lm(a: *mem.Arena, y: []const f64, z: []const f64, xreg: []const f64, n: usize, p: usize, k: usize, out: []f64) -> err {
    var zmin = z[0usize]
    var zmax = z[0usize]
    var i = 0usize
    while i < n {
        if z[i] < zmin { zmin = z[i] }
        if z[i] > zmax { zmax = z[i] }
        i += 1usize
    }
    let (pm1, e0) = mem.alloc[f64](a, n)
    let (pm2, e1) = mem.alloc[f64](a, n)
    let (xtx, e2) = mem.alloc[f64](a, p * p)
    let (ry, e3) = mem.alloc[f64](a, n)
    let (r1, e4) = mem.alloc[f64](a, n)
    let (r2, e5) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e0 }
    let cnt = f64(k) * f64(k - 1usize) / 2.0f64
    i = 0usize
    while i < n {
        var s1 = 0.0f64
        var s2 = 0.0f64
        var j = 0usize
        while j < k {
            let psi = zmin + (zmax - zmin) * f64(j) / f64(k - 1usize)
            var v = z[i] - psi
            if v < 0.0f64 { v = 0.0f64 }
            s1 += v
            s2 += v * f64(j)
            j += 1usize
        }
        pm1[i] = s1 / f64(k)
        pm2[i] = s2 / cnt
        i += 1usize
    }
    var r = 0usize
    while r < p * p {
        xtx[r] = 0.0f64
        r += 1usize
    }
    i = 0usize
    while i < n {
        var c1 = 0usize
        while c1 < p {
            var c2 = 0usize
            while c2 < p {
                xtx[c1 * p + c2] += xreg[i * p + c1] * xreg[i * p + c2]
                c2 += 1usize
            }
            c1 += 1usize
        }
        i += 1usize
    }
    let (inv, ie) = gp.invert(a, xtx, p)
    if ie != ok { ret ie }
    resid_on(inv, xreg, y, n, p, ry)
    resid_on(inv, xreg, pm1, n, p, r1)
    resid_on(inv, xreg, pm2, n, p, r2)
    var s1 = 0.0f64
    var s2 = 0.0f64
    var v11 = 0.0f64
    var v12 = 0.0f64
    var v22 = 0.0f64
    var rss = 0.0f64
    i = 0usize
    while i < n {
        s1 += r1[i] * y[i]
        s2 += r2[i] * y[i]
        v11 += r1[i] * pm1[i]
        v12 += r1[i] * pm2[i]
        v22 += r2[i] * pm2[i]
        rss += ry[i] * ry[i]
        i += 1usize
    }
    let sig2 = rss / (f64(n) - f64(p))
    let det = v11 * v22 - v12 * v12
    let q = (s1 * s1 * v22 - 2.0f64 * s1 * s2 * v12 + s2 * s2 * v11) / det / sig2
    out[0usize] = q
    out[1usize] = math.exp[f64](-q / 2.0f64)
    ret ok
}

// segmented::pscore.test for a weighted lm (one break): the weighted form of test.Sc2, which sets only the DIAGONAL of IA to 1 - h (the off-diagonal keeps the sign of X A X'W), so
// sc = sum_j w_j (fit_j + pm_j (1 - 2 h_j)) y_j and v = sum_j (w_j u' A x_j + sqrt(w_j) pm_j (1 - 2 h_j)) w_j pm_j, h_j = w_j x_j A x_j, u = X'(sqrt(w) pm); sigma^2 = sum w r^2 / (n - p); out = (stat, p)
fn pscore_lmw(a: *mem.Arena, y: []const f64, z: []const f64, w: []const f64, xreg: []const f64, n: usize, p: usize, k: usize, alt: usize, out: []f64) -> err {
    var zmin = z[0usize]
    var zmax = z[0usize]
    var i = 0usize
    while i < n {
        if z[i] < zmin { zmin = z[i] }
        if z[i] > zmax { zmax = z[i] }
        i += 1usize
    }
    let (pm, e0) = mem.alloc[f64](a, n)
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok { ret e0 }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            var v = z[i] - (zmin + (zmax - zmin) * f64(j) / f64(k - 1usize))
            if v < 0.0f64 { v = 0.0f64 }
            s += v
            j += 1usize
        }
        pm[i] = s / f64(k)
        i += 1usize
    }
    var r = 0usize
    while r < p * p {
        xtx[r] = 0.0f64
        r += 1usize
    }
    i = 0usize
    while i < n {
        var c1 = 0usize
        while c1 < p {
            var c2 = 0usize
            while c2 < p {
                xtx[c1 * p + c2] += w[i] * xreg[i * p + c1] * xreg[i * p + c2]
                c2 += 1usize
            }
            c1 += 1usize
        }
        i += 1usize
    }
    let (inv, ie) = gp.invert(a, xtx, p)
    if ie != ok { ret ie }
    var xwy: [64]f64 = zero
    var xwp: [64]f64 = zero
    var u: [64]f64 = zero
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xwy[c] += w[i] * xreg[i * p + c] * y[i]
            xwp[c] += w[i] * xreg[i * p + c] * pm[i]
            u[c] += math.sqrt[f64](w[i]) * pm[i] * xreg[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    var byy: [64]f64 = zero
    var bp: [64]f64 = zero
    var ua: [64]f64 = zero
    var c1 = 0usize
    while c1 < p {
        var c2 = 0usize
        while c2 < p {
            byy[c1] += inv[c1 * p + c2] * xwy[c2]
            bp[c1] += inv[c1 * p + c2] * xwp[c2]
            ua[c1] += u[c2] * inv[c2 * p + c1]
            c2 += 1usize
        }
        c1 += 1usize
    }
    var sc = 0.0f64
    var vs = 0.0f64
    var rss = 0.0f64
    i = 0usize
    while i < n {
        var fy = 0.0f64
        var fp = 0.0f64
        var uax = 0.0f64
        var c = 0usize
        while c < p {
            fy += byy[c] * xreg[i * p + c]
            fp += bp[c] * xreg[i * p + c]
            uax += ua[c] * xreg[i * p + c]
            c += 1usize
        }
        var xax = 0.0f64
        var ca = 0usize
        while ca < p {
            var cb = 0usize
            while cb < p {
                xax += xreg[i * p + ca] * inv[ca * p + cb] * xreg[i * p + cb]
                cb += 1usize
            }
            ca += 1usize
        }
        let h = w[i] * xax
        sc += w[i] * (fp + pm[i] * (1.0f64 - 2.0f64 * h)) * y[i]
        vs += (w[i] * uax + math.sqrt[f64](w[i]) * pm[i] * (1.0f64 - 2.0f64 * h)) * w[i] * pm[i]
        rss += w[i] * (y[i] - fy) * (y[i] - fy)
        i += 1usize
    }
    let df = f64(n) - f64(p)
    let st = sc / (math.sqrt[f64](rss / df) * math.sqrt[f64](vs))
    var pv = 2.0f64 * nb.pt(math.abs[f64](st), df, false, false)
    if alt == 1usize { pv = nb.pt(st, df, true, false) }
    if alt == 2usize { pv = nb.pt(st, df, false, false) }
    out[0usize] = st
    out[1usize] = pv
    ret ok
}

fn glm_dev(a: *mem.Arena, d: []const f64, y: []const f64, n: usize, k: usize, family: usize, beta: []f64) -> f64 {
    var dev = 0.0f64
    var i = 0usize
    while i < n {
        var e = 0.0f64
        var c = 0usize
        while c < k {
            e += d[i * k + c] * beta[c]
            c += 1usize
        }
        var mu = math.exp[f64](e)
        if family == 1usize { mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e)) }
        if mu < 2.220446049250313e-16f64 { mu = 2.220446049250313e-16f64 }
        if family == 1usize && mu > 1.0f64 - 2.220446049250313e-16f64 { mu = 1.0f64 - 2.220446049250313e-16f64 }
        dev += ar.dev_resid(family, y[i], mu)
        i += 1usize
    }
    ret dev
}

// segmented::davies.test (type "lrt", the default) for a binomial (family 1) or poisson (family 2) glm, dispersion 1: for each of k psi values from the second smallest to the second largest of z
// the term pmax(z - psi, 0) is put in front of the design and RIS = sqrt(dev0 - dev) sign(coef of the term) kept; p = naive normal tail of the extreme value plus V exp(-M^2 / 2) / sqrt(8 pi), V the
// total variation of the RIS, doubled for the two-sided case (alt 0 two-sided, 1 less, 2 greater). out = (best psi, p value, points used)
fn davies_glm(a: *mem.Arena, y: []const f64, z: []const f64, xreg: []const f64, n: usize, p: usize, k: usize, family: usize, alt: usize, out: []f64) -> err {
    let (zs, e0) = mem.alloc[f64](a, n)
    let (ris, e1) = mem.alloc[f64](a, k)
    let (vals, e2) = mem.alloc[f64](a, k)
    let (b0, e3) = mem.alloc[f64](a, p)
    let (c0, e4) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e0 }
    var i = 0usize
    while i < n {
        zs[i] = z[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = zs[i]
        var j = i
        while j > 0usize && zs[j - 1usize] > v {
            zs[j] = zs[j - 1usize]
            j -= 1usize
        }
        zs[j] = v
        i += 1usize
    }
    let lo = zs[1usize]
    let hi = zs[n - 2usize]
    var nostart: []f64 = zero
    let fe = ar.glm_fit(a, xreg, y, n, p, family, nostart, b0, c0)
    if fe != ok { ret fe }
    let (eta0, ee0) = mem.alloc[f64](a, n)
    if ee0 != ok { ret ee0 }
    i = 0usize
    while i < n {
        var s0 = 0.0f64
        var c0i = 0usize
        while c0i < p {
            s0 += xreg[i * p + c0i] * b0[c0i]
            c0i += 1usize
        }
        eta0[i] = s0
        i += 1usize
    }
    let dev0 = glm_dev(a, xreg, y, n, p, family, b0)
    let q = p + 1usize
    let (d1, e5) = mem.alloc[f64](a, n * q)
    let (b1, e6) = mem.alloc[f64](a, q)
    let (c1, e7) = mem.alloc[f64](a, q * q)
    if e5 != ok || e6 != ok || e7 != ok { ret e5 }
    var cnt = 0usize
    i = 0usize
    while i < k {
        let psi = lo + (hi - lo) * f64(i) / f64(k - 1usize)
        var t = 0usize
        while t < n {
            var v = z[t] - psi
            if v < 0.0f64 { v = 0.0f64 }
            d1[t * q] = v
            var c = 0usize
            while c < p {
                d1[t * q + 1usize + c] = xreg[t * p + c]
                c += 1usize
            }
            t += 1usize
        }
        let start = mem.mark(a)
        let ge = ar.glm_fit(a, d1, y, n, q, family, eta0, b1, c1)
        if ge == ok {
            let dev = glm_dev(a, d1, y, n, q, family, b1)
            var dd = dev0 - dev
            if dd < 0.0f64 { dd = 0.0f64 }
            var sg = 1.0f64
            if b1[0usize] < 0.0f64 { sg = 0.0f64 - 1.0f64 }
            ris[cnt] = math.sqrt[f64](dd) * sg
            vals[cnt] = psi
            cnt += 1usize
        }
        mem.reset(a, start)
        i += 1usize
    }
    var vsum = 0.0f64
    i = 1usize
    while i < cnt {
        vsum += math.abs[f64](ris[i] - ris[i - 1usize])
        i += 1usize
    }
    var m_ = ris[0usize]
    var best = vals[0usize]
    i = 0usize
    while i < cnt {
        var cand = ris[i]
        if alt == 0usize { cand = math.abs[f64](ris[i]) }
        var cur = m_
        if alt == 0usize { cur = math.abs[f64](m_) }
        var better = false
        if i == 0usize { better = false } else if alt == 1usize { better = cand < cur } else { better = cand > cur }
        if better {
            m_ = ris[i]
            best = vals[i]
        }
        i += 1usize
    }
    var mm = m_
    if alt == 0usize { mm = math.abs[f64](m_) }
    var pn = dist.pnorm(mm, 0.0f64, 1.0f64, false, false)
    if alt == 1usize { pn = dist.pnorm(mm, 0.0f64, 1.0f64, true, false) }
    var padj = pn + vsum * math.exp[f64](0.0f64 - mm * mm / 2.0f64) / math.sqrt[f64](8.0f64 * 3.141592653589793f64)
    if alt == 0usize { padj = 2.0f64 * padj }
    if padj > 1.0f64 { padj = 1.0f64 }
    out[0usize] = best
    out[1usize] = padj
    out[2usize] = f64(cnt)
    ret ok
}
