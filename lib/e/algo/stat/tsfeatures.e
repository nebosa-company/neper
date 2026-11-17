// R tsfeatures, the closed-form features of one series: acf and pacf features (`acf_features`, `pacf_features`), crossing_points,
// flat_spots, lumpiness and stability (on the standardised series), max_level_shift and max_var_shift (rolling mean and variance
// differenced at the window width), firstmin_ac, firstzero_ac, ac_9, embed2_incircle, std1st_der, trev_num, walker_propcross,
// motiftwo_entro3 and zero_proportion. `acf` is R's (denominator n, mean removed) and `pacf` the Durbin-Levinson recursion over it.
//
// Not here: the features that fit models (stl, arch and garch, hurst, holt and hw parameters, entropy by Burg's spectrum, the
// unit-root tests of urca and nonlinearity), histogram_mode, the sample entropies and the features that sample.

use e.math
use e.math.scale
use e.mem
use e.algo.stat.fracdiff_fit as fdf
use e.algo.linalg.decomp as decomp
use e.algo.stat.stlpkg as stlp

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s / f64(x.len)
}

fn var_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

// acf(x, lag.max) for lags 0..lag.max
fn acf(a: *mem.Arena, x: []const f64, lag_max: usize) -> ([]f64, err) {
    let n = x.len
    let (r, e) = mem.alloc[f64](a, lag_max + 1usize)
    if e != ok { ret (r, e) }
    let m = mean_of(x)
    var c0 = 0.0f64
    var i = 0usize
    while i < n {
        c0 += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    var k = 0usize
    while k <= lag_max {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i] - m) * (x[i + k] - m)
            i += 1usize
        }
        r[k] = s / c0
        k += 1usize
    }
    ret (r, ok)
}

// pacf for lags 1..lag.max from the acf r (lags 0..lag.max)
fn pacf_from(a: *mem.Arena, r: []const f64, lag_max: usize) -> ([]f64, err) {
    let (p, e) = mem.alloc[f64](a, lag_max)
    let (phi, e2) = mem.alloc[f64](a, (lag_max + 1usize) * (lag_max + 1usize))
    if e != ok { ret (p, e) }
    if e2 != ok { ret (p, e2) }
    var k = 1usize
    while k <= lag_max {
        var num = r[k]
        var den = 1.0f64
        var j = 1usize
        while j < k {
            num -= phi[(k - 1usize) * (lag_max + 1usize) + j] * r[k - j]
            den -= phi[(k - 1usize) * (lag_max + 1usize) + j] * r[j]
            j += 1usize
        }
        let pk = num / den
        phi[k * (lag_max + 1usize) + k] = pk
        j = 1usize
        while j < k {
            phi[k * (lag_max + 1usize) + j] = phi[(k - 1usize) * (lag_max + 1usize) + j] - pk * phi[(k - 1usize) * (lag_max + 1usize) + k - j]
            j += 1usize
        }
        p[k - 1usize] = pk
        k += 1usize
    }
    ret (p, ok)
}

fn diff_of(a: *mem.Arena, x: []const f64) -> []f64 {
    let (d, e) = mem.alloc[f64](a, x.len - 1usize)
    if e != ok { ret d }
    var i = 0usize
    while i + 1usize < x.len {
        d[i] = x[i + 1usize] - x[i]
        i += 1usize
    }
    ret d
}

fn sumsq_to(v: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += v[i] * v[i]
        i += 1usize
    }
    ret s
}

// acf_features: [x_acf1, x_acf10, diff1_acf1, diff1_acf10, diff2_acf1, diff2_acf10, seas_acf1] (the last only when m > 1; NaN where R has NA)
fn acf_features(a: *mem.Arena, x: []const f64, m: usize, out: []f64) -> err {
    var lm = 10usize
    if m > lm { lm = m }
    let n = x.len
    var i = 0usize
    while i < 7usize {
        out[i] = nan()
        i += 1usize
    }
    let (r, e) = acf(a, x, lm)
    if e != ok { ret e }
    out[0usize] = r[1usize]
    out[1usize] = sumsq_to(r[1usize..11usize], 10usize)
    if n > 10usize {
        let d1 = diff_of(a, x)
        let (r1, e1) = acf(a, d1, 10usize)
        if e1 != ok { ret e1 }
        out[2usize] = r1[1usize]
        out[3usize] = sumsq_to(r1[1usize..11usize], 10usize)
    }
    if n > 11usize {
        let d2 = diff_of(a, diff_of(a, x))
        let (r2, e2) = acf(a, d2, 10usize)
        if e2 != ok { ret e2 }
        out[4usize] = r2[1usize]
        out[5usize] = sumsq_to(r2[1usize..11usize], 10usize)
    }
    if m > 1usize { out[6usize] = r[m] }
    ret ok
}

// pacf_features: [x_pacf5, diff1x_pacf5, diff2x_pacf5, seas_pacf (m > 1)]
fn pacf_features(a: *mem.Arena, x: []const f64, m: usize, out: []f64) -> err {
    var lm = 5usize
    if m > lm { lm = m }
    let n = x.len
    var i = 0usize
    while i < 4usize {
        out[i] = nan()
        i += 1usize
    }
    let (r, e) = acf(a, x, lm)
    if e != ok { ret e }
    let (p, pe) = pacf_from(a, r, lm)
    if pe != ok { ret pe }
    if n > 5usize { out[0usize] = sumsq_to(p, 5usize) }
    if n > 6usize {
        let d1 = diff_of(a, x)
        let (r1, e1) = acf(a, d1, 5usize)
        if e1 != ok { ret e1 }
        let (p1, pe1) = pacf_from(a, r1, 5usize)
        if pe1 != ok { ret pe1 }
        out[1usize] = sumsq_to(p1, 5usize)
    }
    if n > 7usize {
        let d2 = diff_of(a, diff_of(a, x))
        let (r2, e2) = acf(a, d2, 5usize)
        if e2 != ok { ret e2 }
        let (p2, pe2) = pacf_from(a, r2, 5usize)
        if pe2 != ok { ret pe2 }
        out[2usize] = sumsq_to(p2, 5usize)
    }
    if m > 1usize { out[3usize] = p[m - 1usize] }
    ret ok
}

fn median_of(a: *mem.Arena, x: []const f64) -> f64 {
    let (y, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret nan() }
    var i = 0usize
    while i < x.len {
        y[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < y.len {
        let v = y[i]
        var j = i
        while j > 0usize && y[j - 1usize] > v {
            y[j] = y[j - 1usize]
            j -= 1usize
        }
        y[j] = v
        i += 1usize
    }
    let n = y.len
    if n % 2usize == 1usize { ret y[n / 2usize] }
    ret (y[n / 2usize - 1usize] + y[n / 2usize]) / 2.0f64
}

fn crossing_points(a: *mem.Arena, x: []const f64) -> f64 {
    let mid = median_of(a, x)
    var k = 0usize
    var i = 0usize
    while i + 1usize < x.len {
        let p1 = x[i] <= mid
        let p2 = x[i + 1usize] <= mid
        if p1 != p2 { k += 1usize }
        i += 1usize
    }
    ret f64(k)
}

// flat_spots: the longest run in one of 10 equal-width bins (cut(x, breaks = 10, include.lowest = TRUE): the end breaks move out by a
// thousandth of the range)
fn flat_spots(x: []const f64) -> f64 {
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let dx = hi - lo
    var best = 0usize
    var run = 0usize
    var prev = 99usize
    i = 0usize
    while i < x.len {
        var code = 0usize
        var k = 0usize
        while k < 10usize {
            var b = lo + dx * f64(k + 1usize) / 10.0f64
            if k == 9usize { b = hi + dx / 1000.0f64 }
            var a0 = lo + dx * f64(k) / 10.0f64
            if k == 0usize { a0 = lo - dx / 1000.0f64 }
            if x[i] > a0 && x[i] <= b {
                code = k
                break
            }
            k += 1usize
        }
        if code == prev {
            run += 1usize
        } else {
            run = 1usize
            prev = code
        }
        if run > best { best = run }
        i += 1usize
    }
    ret f64(best)
}

// scalets: (x - mean) / sd
fn scalets(a: *mem.Arena, x: []const f64) -> []f64 {
    let (y, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret y }
    let m = mean_of(x)
    let sd = math.sqrt[f64](var_of(x))
    var i = 0usize
    while i < x.len {
        y[i] = (x[i] - m) / sd
        i += 1usize
    }
    ret y
}

// lumpiness (kind 0, the variance of the window variances) and stability (kind 1, the variance of the window means), width w
fn window_stat(a: *mem.Arena, x0: []const f64, w: usize, kind: u8) -> f64 {
    let x = scalets(a, x0)
    let n = x.len
    if n < 2usize * w { ret 0.0f64 }
    let nsegs = n / w
    let (v, e) = mem.alloc[f64](a, nsegs)
    if e != ok { ret nan() }
    var s = 0usize
    while s < nsegs {
        let seg = x[s * w..(s + 1usize) * w]
        if kind == 0u8 { v[s] = var_of(seg) } else { v[s] = mean_of(seg) }
        s += 1usize
    }
    ret var_of(v)
}

// max_level_shift (kind 0) and max_var_shift (kind 1): the largest |difference at lag w| of the rolling mean or variance, and the
// 1-based index of the window it ends at (which.max + w - 1)
fn max_shift(a: *mem.Arena, x: []const f64, w: usize, kind: u8) -> (f64, f64) {
    let n = x.len
    let nr = n - w + 1usize
    let (r, e) = mem.alloc[f64](a, nr)
    if e != ok { ret (nan(), nan()) }
    var i = 0usize
    while i < nr {
        if kind == 0u8 { r[i] = mean_of(x[i..i + w]) } else { r[i] = var_of(x[i..i + w]) }
        i += 1usize
    }
    if nr <= w { ret (0.0f64, nan()) }
    var best = 0.0f64 - 1.0f64
    var at = 0usize
    i = 0usize
    while i + w < nr {
        var d = r[i + w] - r[i]
        if d < 0.0f64 { d = 0.0f64 - d }
        if d > best {
            best = d
            at = i
        }
        i += 1usize
    }
    ret (best, f64(at + 1usize + w - 1usize))
}

// firstmin_ac and firstzero_ac from the acf r (lags 0..N-1)
fn firstmin_ac(r: []const f64) -> f64 {
    let n = r.len
    // autoCorr[i] = r[i], i = 1..N-1 (1-based i)
    var i = 1usize
    while i < n {
        if i == 2usize && r[2usize] > r[1usize] { ret 1.0f64 }
        if i > 2usize && r[i - 2usize] > r[i - 1usize] && r[i - 1usize] < r[i] { ret f64(i - 1usize) }
        i += 1usize
    }
    ret f64(n - 1usize)
}

fn firstzero_ac(r: []const f64) -> f64 {
    var i = 1usize
    while i < r.len {
        if r[i] < 0.0f64 { ret f64(i) }
        i += 1usize
    }
    ret 0.0f64
}

fn std1st_der(a: *mem.Arena, x: []const f64) -> f64 { ret math.sqrt[f64](var_of(diff_of(a, x))) }

fn trev_num(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 1usize < x.len {
        let d = x[i + 1usize] - x[i]
        s += d * d * d
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

fn walker_propcross(x: []const f64) -> f64 {
    let n = x.len
    var w = 0.0f64
    var prev_w = 0.0f64
    var cnt = 0.0f64
    var i = 1usize
    while i < n {
        w = prev_w + 0.1f64 * (x[i - 1usize] - prev_w)
        if (prev_w - x[i - 1usize]) * (w - x[i]) < 0.0f64 { cnt += 1.0f64 }
        prev_w = w
        i += 1usize
    }
    ret cnt / f64(n - 1usize)
}

// motiftwo_entro3: the entropy of the eight three-step up and down patterns of the series binarised at its mean
fn motiftwo_entro3(x: []const f64) -> f64 {
    let n = x.len
    let m = mean_of(x)
    var counts0 = 0.0f64
    var cnt = 0usize
    var tot = 0.0f64
    var p0 = 0.0f64
    var p1 = 0.0f64
    var p2 = 0.0f64
    var p3 = 0.0f64
    var p4 = 0.0f64
    var p5 = 0.0f64
    var p6 = 0.0f64
    var p7 = 0.0f64
    var i = 0usize
    while i + 2usize < n {
        var b0 = 0usize
        var b1 = 0usize
        var b2 = 0usize
        if x[i] - m > 0.0f64 { b0 = 1usize }
        if x[i + 1usize] - m > 0.0f64 { b1 = 1usize }
        if x[i + 2usize] - m > 0.0f64 { b2 = 1usize }
        let code = b0 * 4usize + b1 * 2usize + b2
        if code == 0usize { p0 += 1.0f64 }
        if code == 1usize { p1 += 1.0f64 }
        if code == 2usize { p2 += 1.0f64 }
        if code == 3usize { p3 += 1.0f64 }
        if code == 4usize { p4 += 1.0f64 }
        if code == 5usize { p5 += 1.0f64 }
        if code == 6usize { p6 += 1.0f64 }
        if code == 7usize { p7 += 1.0f64 }
        cnt += 1usize
        i += 1usize
    }
    tot = f64(cnt)
    counts0 = 0.0f64
    var h = 0.0f64
    var k = 0usize
    while k < 8usize {
        var p = p0
        if k == 1usize { p = p1 }
        if k == 2usize { p = p2 }
        if k == 3usize { p = p3 }
        if k == 4usize { p = p4 }
        if k == 5usize { p = p5 }
        if k == 6usize { p = p6 }
        if k == 7usize { p = p7 }
        let q = p / tot
        if q > 0.0f64 { h -= q * math.log[f64](q) }
        k += 1usize
    }
    ret h + counts0
}

fn zero_proportion(x: []const f64, tol: f64) -> f64 {
    var k = 0.0f64
    var i = 0usize
    while i < x.len {
        if math.abs[f64](x[i]) < tol { k += 1.0f64 }
        i += 1usize
    }
    ret k / f64(x.len)
}

// embed2_incircle(y, boundary) with tau = firstzero_ac from the full acf r
fn embed2_incircle(x: []const f64, r: []const f64, boundary: f64) -> f64 {
    let n = x.len
    var tau = usize(firstzero_ac(r))
    if firstzero_ac(r) == 0.0f64 { tau = 0usize }
    let nn = n - tau
    var k = 0.0f64
    var i = 0usize
    while i < nn {
        if x[i + tau] * x[i + tau] + x[i] * x[i] < boundary { k += 1.0f64 }
        i += 1usize
    }
    ret k / f64(nn)
}

// unitroot_kpss(x): urca ur.kpss with type "mu" and the short lag l = trunc(4 (n / 100)^(1/4)): the sum of squared partial sums of the centred series over n^2 times the Bartlett-weighted long-run variance
fn unitroot_kpss(x: []const f64) -> f64 {
    let n = x.len
    let nn = f64(n)
    let m = mean_of(x)
    let l = usize(math.floor[f64](4.0f64 * math.pow[f64](nn / 100.0f64, 0.25f64)))
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        s2 += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    s2 = s2 / nn
    var j = 1usize
    while j <= l {
        var cj = 0.0f64
        var t = j
        while t < n {
            cj += (x[t] - m) * (x[t - j] - m)
            t += 1usize
        }
        s2 += 2.0f64 / nn * (1.0f64 - f64(j) / (f64(l) + 1.0f64)) * cj
        j += 1usize
    }
    var ps = 0.0f64
    var tot = 0.0f64
    i = 0usize
    while i < n {
        ps += x[i] - m
        tot += ps * ps
        i += 1usize
    }
    ret tot / (nn * nn * s2)
}

// unitroot_pp(x): urca ur.pp with the Z-alpha statistic, the constant model and the short lag: the regression of x[t] on x[t - 1] with an intercept (n = length - 1 observations), the residual variance s and its Bartlett long-run
// estimate sig over l = trunc(4 (n / 100)^(1/4)) lags, and n (alpha - 1) - 0.5 (sig - s) / ((1 / n^2) sum (y - mean y)^2) with y the dependent series
fn unitroot_pp(a: *mem.Arena, x: []const f64) -> f64 {
    let total = x.len
    let n = total - 1usize
    let nn = f64(n)
    let (res, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan() }
    var my = 0.0f64
    var ml = 0.0f64
    var i = 0usize
    while i < n {
        my += x[i + 1usize]
        ml += x[i]
        i += 1usize
    }
    my = my / nn
    ml = ml / nn
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        sxy += (x[i] - ml) * (x[i + 1usize] - my)
        sxx += (x[i] - ml) * (x[i] - ml)
        syy += (x[i + 1usize] - my) * (x[i + 1usize] - my)
        i += 1usize
    }
    let alpha = sxy / sxx
    let icpt = my - alpha * ml
    var s = 0.0f64
    i = 0usize
    while i < n {
        res[i] = x[i + 1usize] - icpt - alpha * x[i]
        s += res[i] * res[i]
        i += 1usize
    }
    s = s / nn
    let l = usize(math.floor[f64](4.0f64 * math.pow[f64](nn / 100.0f64, 0.25f64)))
    var sig = s
    var j = 1usize
    while j <= l {
        var cp = 0.0f64
        var t = j
        while t < n {
            cp += res[t] * res[t - j]
            t += 1usize
        }
        sig += 2.0f64 / nn * (1.0f64 - f64(j) / (f64(l) + 1.0f64)) * cp
        j += 1usize
    }
    let lambda = 0.5f64 * (sig - s)
    let myybar = syy / (nn * nn)
    ret nn * (alpha - 1.0f64) - lambda / myybar
}

// hurst(x): the Hurst exponent as fracdiff(x, 0, 0)$d + 0.5, the fractional differencing parameter of an ARFIMA(0, d, 0) fitted on a window of 100 coefficients (the package default)
fn hurst(a: *mem.Arena, x: []const f64) -> f64 {
    var dummy: [1]f64 = zero
    let (r, fe) = fdf.fracdf(a, x, 100usize, 0usize, 0usize, 0.0001220703125f64, 0.0f64, 0.5f64, 0.0f64, 0.0f64 - 1.0f64, dummy[0usize..0usize])
    if fe != ok || r.info != 0i64 { ret nan() }
    ret r.d + 0.5f64
}

// arch_stat(x, lags = 12, demean = TRUE): the R squared of the regression of x^2 on its own lags 1 .. lags (with an intercept); NaN when the series is too short
fn arch_stat(a: *mem.Arena, x: []const f64, lags: usize, demean: bool) -> f64 {
    let n = x.len
    if n <= lags + 1usize { ret nan() }
    var m = 0.0f64
    if demean { m = mean_of(x) }
    let rows = n - lags
    let cols = lags + 1usize
    let (xm, e1) = mem.alloc[f64](a, rows * cols)
    let (y, e2) = mem.alloc[f64](a, rows)
    if e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < rows {
        // row i: the response x^2 at time i + lags, the regressors the squares at i + lags - 1 .. i
        let t = i + lags
        y[i] = (x[t] - m) * (x[t] - m)
        xm[i] = 1.0f64
        var j = 1usize
        while j <= lags {
            xm[j * rows + i] = (x[t - j] - m) * (x[t - j] - m)
            j += 1usize
        }
        i += 1usize
    }
    let (f, fe) = decomp.lm_fit(a, xm, rows, cols, y, 1.0e-7f64)
    if fe != ok { ret nan() }
    var my = 0.0f64
    i = 0usize
    while i < rows {
        my += y[i]
        i += 1usize
    }
    my = my / f64(rows)
    var tss = 0.0f64
    var rss = 0.0f64
    i = 0usize
    while i < rows {
        tss += (y[i] - my) * (y[i] - my)
        rss += f.residuals[i] * f.residuals[i]
        i += 1usize
    }
    if tss == 0.0f64 { ret 1.0f64 }
    ret 1.0f64 - rss / tss
}

// histogram_mode: the centre of the fullest bin of hist(x, breaks = num_bins), whose breaks are pretty(range(x), num_bins); the bins are right-closed, the lowest one includes its lower end, the breaks carry hist's 1e-7 fuzz, and the first fullest bin wins
fn histogram_mode(a: *mem.Arena, x: []const f64, num_bins: usize) -> f64 {
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let (br, e) = scale.pretty(a, lo, hi, i64(num_bins))
    if e != ok { ret nan() }
    let nb = br.len - 1usize
    let (d, e2) = mem.alloc[f64](a, nb)
    if e2 != ok { ret nan() }
    i = 0usize
    while i < nb {
        d[i] = br[i + 1usize] - br[i]
        i += 1usize
    }
    let diddle = 1.0e-7f64 * median_of(a, d)
    var best = 0usize
    var bestc = 0usize
    var b = 0usize
    while b < nb {
        let l = br[b] + diddle
        let u = br[b + 1usize] + diddle
        var lf = l
        if b == 0usize { lf = br[0usize] - diddle }
        var c = 0usize
        i = 0usize
        while i < x.len {
            if x[i] > lf && x[i] <= u { c += 1usize }
            i += 1usize
        }
        if c > bestc {
            bestc = c
            best = b
        }
        b += 1usize
    }
    ret (br[best] + br[best + 1usize]) / 2.0f64
}

fn at1(v: []const f64, k: i64) -> f64 { ret v[usize(k - 1i64)] }

// ppr.f smooth (non-periodic): the running-lines smoother of span `span` over x sorted, weights w; acvr gets the absolute cross-validated residuals when cv
fn smooth_run(n: usize, x: []const f64, y: []const f64, w: []const f64, span: f64, cv: bool, vsmlsq: f64, smo: []f64, acvr: []f64) {
    var xm = 0.0f64
    var ym = 0.0f64
    var vr = 0.0f64
    var cvar = 0.0f64
    var fbw = 0.0f64
    let ni = i64(n)
    var ibw = i64(0.5f64 * span * f64(n) + 0.5f64)
    if ibw < 2i64 { ibw = 2i64 }
    var it = 2i64 * ibw + 1i64
    if it > ni { it = ni }
    var i = 1i64
    while i <= it {
        let xti = at1(x, i)
        let wt = at1(w, i)
        let fbo = fbw
        fbw = fbw + wt
        if fbw > 0.0f64 { xm = (fbo * xm + wt * xti) / fbw }
        if fbw > 0.0f64 { ym = (fbo * ym + wt * at1(y, i)) / fbw }
        var tmp = 0.0f64
        if fbo > 0.0f64 { tmp = fbw * wt * (xti - xm) / fbo }
        vr = vr + tmp * (xti - xm)
        cvar = cvar + tmp * (at1(y, i) - ym)
        i += 1i64
    }
    var j = 1i64
    while j <= ni {
        let out = j - ibw - 1i64
        let inn = j + ibw
        if out >= 1i64 && inn <= ni {
            let xto = at1(x, out)
            let xti = at1(x, inn)
            var wt = at1(w, out)
            var fbo = fbw
            fbw = fbw - wt
            var tmp = 0.0f64
            if fbw > 0.0f64 { tmp = fbo * wt * (xto - xm) / fbw }
            vr = vr - tmp * (xto - xm)
            cvar = cvar - tmp * (at1(y, out) - ym)
            if fbw > 0.0f64 { xm = (fbo * xm - wt * xto) / fbw }
            if fbw > 0.0f64 { ym = (fbo * ym - wt * at1(y, out)) / fbw }
            wt = at1(w, inn)
            fbo = fbw
            fbw = fbw + wt
            if fbw > 0.0f64 { xm = (fbo * xm + wt * xti) / fbw }
            if fbw > 0.0f64 { ym = (fbo * ym + wt * at1(y, inn)) / fbw }
            tmp = 0.0f64
            if fbo > 0.0f64 { tmp = fbw * wt * (xti - xm) / fbo }
            vr = vr + tmp * (xti - xm)
            cvar = cvar + tmp * (at1(y, inn) - ym)
        }
        var a = 0.0f64
        if vr > vsmlsq { a = cvar / vr }
        let xj = at1(x, j)
        smo[usize(j - 1i64)] = a * (xj - xm) + ym
        if cv {
            var h = 0.0f64
            if fbw > 0.0f64 { h = 1.0f64 / fbw }
            if vr > vsmlsq { h = h + (xj - xm) * (xj - xm) / vr }
            acvr[usize(j - 1i64)] = 0.0f64
            a = 1.0f64 - at1(w, j) * h
            if a > 0.0f64 {
                acvr[usize(j - 1i64)] = math.abs[f64](at1(y, j) - smo[usize(j - 1i64)]) / a
            } else {
                if j > 1i64 { acvr[usize(j - 1i64)] = acvr[usize(j - 2i64)] }
            }
        }
        j += 1i64
    }
    // ties in x: the fitted values become the weighted mean over the tie
    j = 1i64
    while j <= ni {
        let j0 = j
        var sy = at1(smo, j) * at1(w, j)
        var fb = at1(w, j)
        while j < ni && at1(x, j + 1i64) <= at1(x, j) {
            j += 1i64
            sy = sy + at1(w, j) * at1(smo, j)
            fb = fb + at1(w, j)
        }
        if j > j0 {
            var m = 0.0f64
            if fb > 0.0f64 { m = sy / fb }
            var q = j0
            while q <= j {
                smo[usize(q - 1i64)] = m
                q += 1i64
            }
        }
        j += 1i64
    }
}

// stats::supsmu(x, y) with the defaults (span = "cv", bass = 0, unit weights) for x strictly increasing: Friedman's super smoother, the three spans 0.05 / 0.2 / 0.5 chosen by cross-validation
fn supsmu(a: *mem.Arena, x: []const f64, y: []const f64, smo: []f64) -> err {
    let n = x.len
    let (sc, e1) = mem.alloc[f64](a, 7usize * n)
    let (w, e2) = mem.alloc[f64](a, n)
    let (h, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    var lo = n / 4usize
    var hi = 3usize * lo
    var spread = x[hi - 1usize] - x[lo - 1usize]
    while spread <= 0.0f64 {
        if hi < n { hi += 1usize }
        if lo > 1usize { lo -= 1usize }
        spread = x[hi - 1usize] - x[lo - 1usize]
    }
    let vsmlsq = (0.001f64 * spread) * (0.001f64 * spread)
    var sp: [3]f64 = zero
    sp[0usize] = 0.05f64
    sp[1usize] = 0.2f64
    sp[2usize] = 0.5f64
    // columns of sc, each n long: 0..5 smooths and their cross-validated residual smooths, 6 the span selected
    var k = 0usize
    while k < 3usize {
        smooth_run(n, x, y, w, sp[k], true, vsmlsq, sc[(2usize * k) * n..(2usize * k + 1usize) * n], sc[6usize * n..7usize * n])
        smooth_run(n, x, sc[6usize * n..7usize * n], w, sp[1usize], false, vsmlsq, sc[(2usize * k + 1usize) * n..(2usize * k + 2usize) * n], h)
        k += 1usize
    }
    var j = 0usize
    while j < n {
        var resmin = 1.0e20f64
        k = 0usize
        while k < 3usize {
            if sc[(2usize * k + 1usize) * n + j] < resmin {
                resmin = sc[(2usize * k + 1usize) * n + j]
                sc[6usize * n + j] = sp[k]
            }
            k += 1usize
        }
        j += 1usize
    }
    smooth_run(n, x, sc[6usize * n..7usize * n], w, sp[1usize], false, vsmlsq, sc[n..2usize * n], h)
    j = 0usize
    while j < n {
        if sc[n + j] <= sp[0usize] { sc[n + j] = sp[0usize] }
        if sc[n + j] >= sp[2usize] { sc[n + j] = sp[2usize] }
        var f = sc[n + j] - sp[1usize]
        if f >= 0.0f64 {
            f = f / (sp[2usize] - sp[1usize])
            sc[3usize * n + j] = (1.0f64 - f) * sc[2usize * n + j] + f * sc[4usize * n + j]
        } else {
            f = (0.0f64 - f) / (sp[1usize] - sp[0usize])
            sc[3usize * n + j] = (1.0f64 - f) * sc[2usize * n + j] + f * sc[j]
        }
        j += 1usize
    }
    smooth_run(n, x, sc[3usize * n..4usize * n], w, sp[0usize], false, vsmlsq, smo, h)
    ret ok
}

fn clamp01(v: f64) -> f64 { ret math.max[f64](0.0f64, math.min[f64](1.0f64, v)) }

// stl_features(x) for a series of frequency m: out = [nperiods, seasonal_period, trend, spike, linearity, curvature, e_acf1, e_acf10, seasonal_strength, peak, trough]
// (the last three NaN without a seasonal component). With m > 1 and more than two periods forecast::mstl runs stl(s.window = 11); otherwise the trend is supsmu(1..n, x).
fn stl_features(a: *mem.Arena, x: []const f64, m: usize, out: []f64) -> err {
    let n = x.len
    var i = 0usize
    while i < 11usize {
        out[i] = nan()
        i += 1usize
    }
    let (trend0, e1) = mem.alloc[f64](a, n)
    let (rem, e2) = mem.alloc[f64](a, n)
    let (seas, e3) = mem.alloc[f64](a, n)
    let (des, e4) = mem.alloc[f64](a, n)
    let (rw, e5) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    let seasonal = m > 1usize && n > 2usize * m
    if seasonal {
        let e = stlp.stl(a, x, m, false, 11.0f64, 0i64, 0.0f64, 1i64, 0.0f64, 1i64, 0usize, 0usize, 0usize, false, seas, trend0, rw)
        if e != ok { ret e }
    } else {
        let (t, e6) = mem.alloc[f64](a, n)
        if e6 != ok { ret e6 }
        i = 0usize
        while i < n {
            t[i] = f64(i + 1usize)
            seas[i] = 0.0f64
            i += 1usize
        }
        let e = supsmu(a, t, x, trend0)
        if e != ok { ret e }
    }
    i = 0usize
    while i < n {
        rem[i] = x[i] - trend0[i] - seas[i]
        des[i] = x[i] - seas[i]
        i += 1usize
    }
    if m > 1usize { out[0usize] = 1.0f64 } else { out[0usize] = 0.0f64 }
    out[1usize] = f64(m)
    let varx = var_of(x)
    let vare = var_of(rem)
    let vards = var_of(des)
    var tr = 0.0f64
    if varx < 2.220446049250313e-16f64 { tr = 0.0f64 } else {
        if vards / varx < 1.0e-10f64 { tr = 0.0f64 } else { tr = clamp01(1.0f64 - vare / vards) }
    }
    out[2usize] = tr
    let mr = mean_of(rem)
    let (vl, e7) = mem.alloc[f64](a, n)
    if e7 != ok { ret e7 }
    i = 0usize
    while i < n {
        vl[i] = (vare * f64(n - 1usize) - (rem[i] - mr) * (rem[i] - mr)) / f64(n - 2usize)
        i += 1usize
    }
    out[3usize] = var_of(vl)
    // the linear and quadratic coefficients of lm(trend ~ poly(1..n, 2)): the trend projected on the orthonormal polynomials
    let (q1, e8) = mem.alloc[f64](a, n)
    let (q2, e9) = mem.alloc[f64](a, n)
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    let tm = f64(n + 1usize) / 2.0f64
    var s1 = 0.0f64
    i = 0usize
    while i < n {
        q1[i] = f64(i + 1usize) - tm
        s1 += q1[i] * q1[i]
        i += 1usize
    }
    s1 = math.sqrt[f64](s1)
    var mt2 = 0.0f64
    i = 0usize
    while i < n {
        q1[i] = q1[i] / s1
        mt2 += (f64(i + 1usize) - tm) * (f64(i + 1usize) - tm)
        i += 1usize
    }
    mt2 = mt2 / f64(n)
    var dq = 0.0f64
    i = 0usize
    while i < n {
        dq += (f64(i + 1usize) - tm) * (f64(i + 1usize) - tm) * q1[i]
        i += 1usize
    }
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        q2[i] = (f64(i + 1usize) - tm) * (f64(i + 1usize) - tm) - mt2 - dq * q1[i]
        s2 += q2[i] * q2[i]
        i += 1usize
    }
    s2 = math.sqrt[f64](s2)
    var c1 = 0.0f64
    var c2 = 0.0f64
    i = 0usize
    while i < n {
        c1 += trend0[i] * q1[i]
        c2 += trend0[i] * (q2[i] / s2)
        i += 1usize
    }
    out[4usize] = c1
    out[5usize] = c2
    var me = 1usize
    if seasonal { me = m }
    var af: [7]f64 = zero
    let e = acf_features(a, rem, me, af[0usize..7usize])
    if e != ok { ret e }
    out[6usize] = af[0usize]
    out[7usize] = af[1usize]
    if seasonal {
        let (rs, e10) = mem.alloc[f64](a, n)
        if e10 != ok { ret e10 }
        var pk = 0usize
        var th = 0usize
        i = 0usize
        while i < n {
            rs[i] = rem[i] + seas[i]
            if seas[i] > seas[pk] { pk = i }
            if seas[i] < seas[th] { th = i }
            i += 1usize
        }
        out[8usize] = clamp01(1.0f64 - vare / var_of(rs))
        var p1 = (pk + 1usize) % m
        if p1 == 0usize { p1 = m }
        var p2 = (th + 1usize) % m
        if p2 == 0usize { p2 = m }
        out[9usize] = f64(p1)
        out[10usize] = f64(p2)
    }
    ret ok
}

// stats:::C_Burg: Burg's recursion on the demeaned series up to order pmax; coefs is the pmax x pmax column-major table whose row p-1 holds the order-p coefficients, var1 the recursion variances (what ar.burg uses)
fn burg(a: *mem.Arena, x: []const f64, pmax: usize, coefs: []f64, var1: []f64) -> err {
    let n = x.len
    let (u, e1) = mem.alloc[f64](a, n)
    let (v, e2) = mem.alloc[f64](a, n)
    let (u0, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < pmax * pmax {
        coefs[i] = 0.0f64
        i += 1usize
    }
    var sum = 0.0f64
    var t = 0usize
    while t < n {
        u[t] = x[n - 1usize - t]
        v[t] = x[n - 1usize - t]
        sum += x[t] * x[t]
        t += 1usize
    }
    var1[0usize] = sum / f64(n)
    var p = 1usize
    while p <= pmax {
        sum = 0.0f64
        var d = 0.0f64
        t = p
        while t < n {
            sum += v[t] * u[t - 1usize]
            d += v[t] * v[t] + u[t - 1usize] * u[t - 1usize]
            t += 1usize
        }
        let phii = 2.0f64 * sum / d
        coefs[pmax * (p - 1usize) + (p - 1usize)] = phii
        var j = 1usize
        while j < p {
            coefs[p - 1usize + pmax * (j - 1usize)] = coefs[p - 2usize + pmax * (j - 1usize)] - phii * coefs[p - 2usize + pmax * (p - j - 1usize)]
            j += 1usize
        }
        t = 0usize
        while t < n {
            u0[t] = u[t]
            t += 1usize
        }
        t = p
        while t < n {
            u[t] = u0[t - 1usize] - phii * v[t]
            v[t] = v[t] - phii * u0[t - 1usize]
            t += 1usize
        }
        var1[p] = var1[p - 1usize] * (1.0f64 - phii * phii)
        p += 1usize
    }
    ret ok
}

// the AR spectrum fx of entropy(): spec.ar(method = "burg", n.freq = ceiling(n / 2 + 1)) mirrored; order picked by AIC
fn entropy(a: *mem.Arena, x0: []const f64) -> f64 {
    let n = x0.len
    var omax = usize(math.floor[f64](10.0f64 * math.log10[f64](f64(n))))
    if omax > n - 1usize { omax = n - 1usize }
    let mu = mean_of(x0)
    let (x, e0) = mem.alloc[f64](a, n)
    let (coefs, e1) = mem.alloc[f64](a, omax * omax)
    let (var1, e2) = mem.alloc[f64](a, omax + 1usize)
    if e0 != ok || e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < n {
        x[i] = x0[i] - mu
        i += 1usize
    }
    if burg(a, x, omax, coefs, var1) != ok { ret nan() }
    var order = 0usize
    var best = f64(n) * math.log[f64](var1[0usize])
    var p = 1usize
    while p <= omax {
        let aic = f64(n) * math.log[f64](var1[p]) + 2.0f64 * f64(p)
        if aic < best {
            best = aic
            order = p
        }
        p += 1usize
    }
    let nf = usize(math.ceil[f64](f64(n) / 2.0f64 + 1.0f64))
    let (spec, e3) = mem.alloc[f64](a, nf)
    if e3 != ok { ret nan() }
    let two_pi = 6.283185307179586f64
    i = 0usize
    while i < nf {
        let fr = 0.5f64 * f64(i) / f64(nf - 1usize)
        var cs = 0.0f64
        var sn = 0.0f64
        var k = 1usize
        while k <= order {
            let c = coefs[(order - 1usize) + omax * (k - 1usize)]
            cs += math.cos[f64](two_pi * fr * f64(k)) * c
            sn += math.sin[f64](two_pi * fr * f64(k)) * c
            k += 1usize
        }
        spec[i] = var1[order] / ((1.0f64 - cs) * (1.0f64 - cs) + sn * sn)
        i += 1usize
    }
    let len = 2usize * nf - 1usize
    var tot = 0.0f64
    i = 0usize
    while i < len {
        var s = 0.0f64
        if i < nf - 1usize { s = spec[nf - 1usize - i] } else { s = spec[i - (nf - 1usize)] }
        tot += s / f64(n)
        i += 1usize
    }
    var h = 0.0f64
    i = 0usize
    while i < len {
        var s = 0.0f64
        if i < nf - 1usize { s = spec[nf - 1usize - i] } else { s = spec[i - (nf - 1usize)] }
        let fx = 0.999f64 * (s / f64(n) / tot) + 0.001f64 / f64(len)
        h -= fx * (math.log[f64](fx) / math.log[f64](f64(n)))
        i += 1usize
    }
    ret math.min[f64](1.0f64, h)
}
