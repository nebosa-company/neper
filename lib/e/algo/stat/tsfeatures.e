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
use e.algo.stat.rnm as rnm

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

type EtsCtx = struct { y: []const f64, damped: bool }

// forecast's etscalc for ETS(A,A,N): the one-step errors and the likelihood term n * log(sum e^2); NaN when the sum is 0
fn ets_aan(c: *EtsCtx, alpha: f64, beta: f64, phi: f64, l0: f64, b0: f64, e: []f64) -> f64 {
    let n = c.y.len
    var l = l0
    var b = b0
    var s = 0.0f64
    var i = 0usize
    while i < n {
        let q = l + phi * b
        e[i] = c.y[i] - q
        let nl = q + alpha * (c.y[i] - q)
        b = phi * b + (beta / alpha) * (nl - q)
        l = nl
        s += e[i] * e[i]
        i += 1usize
    }
    ret f64(n) * math.log[f64](s)
}

// the check.param of forecast with bounds "both": usual limits then the admissible region
fn ets_param_ok(alpha: f64, beta: f64, phi: f64) -> bool {
    if alpha < 0.0001f64 || alpha > 0.9999f64 { ret false }
    if beta < 0.0001f64 || beta > alpha || beta > 0.9999f64 { ret false }
    if phi < 0.8f64 || phi > 0.98f64 { ret false }
    if phi < 0.0f64 || phi > 1.00000001f64 { ret false }
    if alpha < 1.0f64 - 1.0f64 / phi || alpha > 1.0f64 + 1.0f64 / phi { ret false }
    if beta < alpha * (phi - 1.0f64) || beta > (1.0f64 + phi) * (2.0f64 - alpha) { ret false }
    ret true
}

fn ets_obj(c: *EtsCtx, par: []const f64) -> f64 {
    var phi = 1.0f64
    var k = 2usize
    if c.damped {
        phi = par[2usize]
        k = 3usize
    }
    // the usual limits on phi apply only when it is estimated; the undamped phi of 1 is outside them but is not tested
    var ok_ = true
    if c.damped {
        ok_ = ets_param_ok(par[0usize], par[1usize], phi)
    } else {
        ok_ = par[0usize] >= 0.0001f64 && par[0usize] <= 0.9999f64 && par[1usize] >= 0.0001f64 && par[1usize] <= par[0usize] && par[1usize] <= 0.9999f64
        if ok_ { ok_ = par[1usize] >= 0.0f64 * par[0usize] && par[1usize] <= 2.0f64 * (2.0f64 - par[0usize]) && par[0usize] <= 2.0f64 }
    }
    if !ok_ { ret 1.0e35f64 }
    var buf: [1024]f64 = zero
    if c.y.len > 1024usize { ret 1.0e35f64 }
    let v = ets_aan(c, par[0usize], par[1usize], phi, par[k], par[k + 1usize], buf[0usize..c.y.len])
    if v != v { ret 1.0e35f64 }
    if math.abs[f64](v + 99999.0f64) < 1.0e-7f64 { ret 1.0e35f64 }
    ret v
}

// tsfeatures::holt_parameters(x): (alpha, beta) of the better aicc of forecast::ets(x, "AAN") fitted damped and undamped
fn holt_parameters(a: *mem.Arena, y: []const f64) -> (f64, f64) {
    let n = y.len
    var best = 1.0e300f64
    var ba = nan()
    var bb = nan()
    var pass = 0usize
    while pass < 2usize {
        let damped = pass == 0usize
        var c = EtsCtx{ y: y, damped: damped }
        // initstate: the least-squares line over the first min(10, n) points
        var maxn = 10usize
        if n < maxn { maxn = n }
        var sx = 0.0f64
        var sy = 0.0f64
        var i = 0usize
        while i < maxn {
            sx += f64(i + 1usize)
            sy += y[i]
            i += 1usize
        }
        let mx = sx / f64(maxn)
        let my = sy / f64(maxn)
        var sxy = 0.0f64
        var sxx = 0.0f64
        i = 0usize
        while i < maxn {
            sxy += (f64(i + 1usize) - mx) * (y[i] - my)
            sxx += (f64(i + 1usize) - mx) * (f64(i + 1usize) - mx)
            i += 1usize
        }
        var b0 = sxy / sxx
        var l0 = my - b0 * mx
        if math.abs[f64](l0 + b0) < 1.0e-8f64 {
            l0 = l0 * 1.001f64
            b0 = b0 * 0.999f64
        }
        var np = 4usize
        if damped { np = 5usize }
        if np >= n - 1usize { ret (nan(), nan()) }
        let alpha0 = 0.0001f64 + 0.2f64 * 0.9998f64
        var ub = 0.9999f64
        if alpha0 < ub { ub = alpha0 }
        let beta0 = 0.0001f64 + 0.1f64 * (ub - 0.0001f64)
        var start: [5]f64 = zero
        start[0usize] = alpha0
        start[1usize] = beta0
        var k = 2usize
        if damped {
            start[2usize] = 0.8f64 + 0.99f64 * 0.18f64
            k = 3usize
        }
        start[k] = l0
        start[k + 1usize] = b0
        var fit: [5]f64 = zero
        let (fv, cnt, fail) = rnm.nmmin[EtsCtx](a, &c, ets_obj, start[0usize..np], 0.0f64 - 1.0e308f64, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 2000usize, 1.0f64, fit[0usize..np])
        var phi = 1.0f64
        if damped { phi = fit[2usize] }
        var buf: [1024]f64 = zero
        let lik = ets_aan(&c, fit[0usize], fit[1usize], phi, fit[k], fit[k + 1usize], buf[0usize..n])
        let npp = f64(np + 1usize)
        let aic = lik + 2.0f64 * npp
        let aicc = aic + 2.0f64 * npp * (npp + 1.0f64) / (f64(n) - npp - 1.0f64)
        if aicc < best {
            best = aicc
            ba = fit[0usize]
            bb = fit[1usize]
        }
        pass += 1usize
    }
    ret (ba, bb)
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

// ---- tseries::garch: Gay's SUMSL (ACM TOMS 611, dsumsl.f of tseries) quasi-Newton with the double-dogleg trust region and the BFGS secant update of the Cholesky factor, used by garch() with its analytical gradient. The reverse-communication driver is flattened into direct calls; v and iv are the 1-based work arrays (element 0 unused). Messages (ditsum) and the parameter checks (dparck) are left out: the defaults of ddeflt/dvdflt are always in range here.

const SV_DGNORM: usize = 1usize
const SV_DSTNRM: usize = 2usize
const SV_DST0: usize = 3usize
const SV_GTSTEP: usize = 4usize
const SV_STPPAR: usize = 5usize
const SV_NREDUC: usize = 6usize
const SV_PREDUC: usize = 7usize
const SV_RADIUS: usize = 8usize
const SV_F: usize = 10usize
const SV_FDIF: usize = 11usize
const SV_FLSTGD: usize = 12usize
const SV_F0: usize = 13usize
const SV_GTSLST: usize = 14usize
const SV_PLSTGD: usize = 15usize
const SV_RADFAC: usize = 16usize
const SV_RELDX: usize = 17usize
const SV_DSTSAV: usize = 18usize
const SV_DECFAC: usize = 22usize
const SV_INCFAC: usize = 23usize
const SV_RDFCMN: usize = 24usize
const SV_RDFCMX: usize = 25usize
const SV_TUNER1: usize = 26usize
const SV_TUNER2: usize = 27usize
const SV_TUNER3: usize = 28usize
const SV_TUNER4: usize = 29usize
const SV_TUNER5: usize = 30usize
const SV_AFCTOL: usize = 31usize
const SV_RFCTOL: usize = 32usize
const SV_XCTOL: usize = 33usize
const SV_XFTOL: usize = 34usize
const SV_LMAX0: usize = 35usize
const SV_LMAXS: usize = 36usize
const SV_SCTOL: usize = 37usize
const SV_BIAS: usize = 43usize
const SV_GTHG: usize = 44usize
const SV_GRDFAC: usize = 45usize
const SV_NWTFAC: usize = 46usize

const SI_TOOBIG: usize = 2usize
const SI_MODEL: usize = 5usize
const SI_NFCALL: usize = 6usize
const SI_NFGCAL: usize = 7usize
const SI_RADINC: usize = 8usize
const SI_RESTOR: usize = 9usize
const SI_STAGE: usize = 10usize
const SI_STGLIM: usize = 11usize
const SI_SWITCH: usize = 12usize
const SI_XIRC: usize = 13usize
const SI_IRC: usize = 29usize
const SI_MLSTGD: usize = 32usize

fn dot_of(n: usize, x: []const f64, y: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

fn nrm2_of(n: usize, x: []const f64) -> f64 { ret math.sqrt[f64](dot_of(n, x, x)) }

// dlitvm: x = L^-T y, L packed by rows
fn sl_itvm(n: usize, x: []f64, l: []const f64, y: []const f64) {
    var i = 0usize
    while i < n {
        x[i] = y[i]
        i += 1usize
    }
    var i0 = n * (n + 1usize) / 2usize
    var ii = 1usize
    var go = true
    while go && ii <= n {
        let i1 = n + 1usize - ii
        let xi = x[i1 - 1usize] / l[i0 - 1usize]
        x[i1 - 1usize] = xi
        if i1 <= 1usize {
            go = false
        } else {
            i0 -= i1
            if xi == 0.0f64 {
                go = false
            } else {
                var j = 1usize
                while j < i1 {
                    x[j - 1usize] -= xi * l[i0 + j - 1usize]
                    j += 1usize
                }
            }
        }
        ii += 1usize
    }
}

// dlivmu: x = L^-1 y
fn sl_ivmu(n: usize, x: []f64, l: []const f64, y: []const f64) {
    var k = 1usize
    while k <= n && y[k - 1usize] == 0.0f64 {
        x[k - 1usize] = 0.0f64
        k += 1usize
    }
    if k <= n {
        var j = k * (k + 1usize) / 2usize
        x[k - 1usize] = y[k - 1usize] / l[j - 1usize]
        var i = k + 1usize
        while i <= n {
            var t = 0.0f64
            var q = 0usize
            while q < i - 1usize {
                t += l[j + q] * x[q]
                q += 1usize
            }
            j += i
            x[i - 1usize] = (y[i - 1usize] - t) / l[j - 1usize]
            i += 1usize
        }
    }
}

// dltvmu: x = L^T y
fn sl_tvmu(n: usize, x: []f64, l: []const f64, y: []const f64) {
    var i0 = 0usize
    var i = 1usize
    while i <= n {
        let yi = y[i - 1usize]
        x[i - 1usize] = 0.0f64
        var j = 1usize
        while j <= i {
            x[j - 1usize] += yi * l[i0 + j - 1usize]
            j += 1usize
        }
        i0 += i
        i += 1usize
    }
}

// dlvmul: x = L y
fn sl_vmul(n: usize, x: []f64, l: []const f64, y: []const f64) {
    var i0 = n * (n + 1usize) / 2usize
    var ii = 1usize
    while ii <= n {
        let i1 = n + 1usize - ii
        i0 -= i1
        var t = 0.0f64
        var j = 1usize
        while j <= i1 {
            t += l[i0 + j - 1usize] * y[j - 1usize]
            j += 1usize
        }
        x[i1 - 1usize] = t
        ii += 1usize
    }
}

// dwzbfg: the vectors w and z of the BFGS update of the factor
fn sl_wzbfg(n: usize, l: []const f64, s: []const f64, w: []f64, y: []const f64, z: []f64) {
    sl_tvmu(n, w, l, s)
    let shs = dot_of(n, w, w)
    let ys = dot_of(n, y, s)
    var cy = 0.0f64
    var cs = 0.0f64
    if ys >= 0.1f64 * shs {
        cy = 1.0f64 / (math.sqrt[f64](ys) * math.sqrt[f64](shs))
        cs = 1.0f64 / shs
    } else {
        let theta = (1.0f64 - 0.1f64) * shs / (shs - ys)
        let epsrt = math.sqrt[f64](0.1f64)
        cy = theta / (shs * epsrt)
        cs = (1.0f64 + (theta - 1.0f64) / epsrt) / shs
    }
    sl_ivmu(n, z, l, y)
    var i = 0usize
    while i < n {
        z[i] = cy * z[i] - cs * w[i]
        i += 1usize
    }
}

// dlupdt: lplus = the Cholesky factor of L(I + w z^T)(I + z w^T)L^T, in place when lplus is l
fn sl_updt(beta: []f64, gamma: []f64, l: []const f64, lambda: []f64, lplus: []f64, n: usize, w: []f64, z: []f64) {
    var nu = 1.0f64
    var eta = 0.0f64
    if n > 1usize {
        let nm1 = n - 1usize
        var s = 0.0f64
        var i = 1usize
        while i <= nm1 {
            let j = n - i
            s += w[j] * w[j]
            lambda[j - 1usize] = s
            i += 1usize
        }
        var j = 1usize
        while j <= nm1 {
            let wj = w[j - 1usize]
            let a = nu * z[j - 1usize] - eta * wj
            let theta = 1.0f64 + a * wj
            s = a * lambda[j - 1usize]
            var lj = math.sqrt[f64](theta * theta + a * s)
            if theta > 0.0f64 { lj = 0.0f64 - lj }
            lambda[j - 1usize] = lj
            let b = theta * wj + s
            gamma[j - 1usize] = b * nu / lj
            beta[j - 1usize] = (a - b * eta) / lj
            nu = (0.0f64 - nu) / lj
            eta = (0.0f64 - (eta + (a * a) / (theta - lj))) / lj
            j += 1usize
        }
    }
    lambda[n - 1usize] = 1.0f64 + (nu * z[n - 1usize] - eta * w[n - 1usize]) * w[n - 1usize]
    var jj = n * (n + 1usize) / 2usize
    var k = 1usize
    while k <= n {
        let j = n + 1usize - k
        let lj = lambda[j - 1usize]
        let ljj = l[jj - 1usize]
        lplus[jj - 1usize] = lj * ljj
        let wj = w[j - 1usize]
        w[j - 1usize] = ljj * wj
        let zj = z[j - 1usize]
        z[j - 1usize] = ljj * zj
        if k != 1usize {
            let bj = beta[j - 1usize]
            let gj = gamma[j - 1usize]
            var ij = jj + j
            var i = j + 1usize
            while i <= n {
                let lij = l[ij - 1usize]
                lplus[ij - 1usize] = lj * lij + bj * w[i - 1usize] + gj * z[i - 1usize]
                w[i - 1usize] = w[i - 1usize] + lij * wj
                z[i - 1usize] = z[i - 1usize] + lij * zj
                ij += i
                i += 1usize
            }
        }
        jj -= j
        k += 1usize
    }
}

// ddbdog: the double-dogleg step (sets the step and the model quantities in v)
fn sl_dbdog(n: usize, dig: []const f64, g: []const f64, nwtstp: []const f64, step: []f64, v: []f64) {
    let nwtnrm = v[SV_DST0]
    var rlambd = 1.0f64
    if nwtnrm > 0.0f64 { rlambd = v[SV_RADIUS] / nwtnrm }
    let gnorm = v[SV_DGNORM]
    var i = 0usize
    while i < n {
        step[i] = g[i] / gnorm
        i += 1usize
    }
    let ghinvg = dot_of(n, step, nwtstp)
    v[SV_NREDUC] = 0.5f64 * ghinvg * gnorm
    v[SV_GRDFAC] = 0.0f64
    v[SV_NWTFAC] = 0.0f64
    if rlambd >= 1.0f64 {
        v[SV_STPPAR] = 0.0f64
        v[SV_DSTNRM] = nwtnrm
        v[SV_GTSTEP] = (0.0f64 - ghinvg) * gnorm
        v[SV_PREDUC] = v[SV_NREDUC]
        v[SV_NWTFAC] = 0.0f64 - 1.0f64
        i = 0usize
        while i < n {
            step[i] = 0.0f64 - nwtstp[i]
            i += 1usize
        }
    } else {
        v[SV_DSTNRM] = v[SV_RADIUS]
        let cfact = (gnorm / v[SV_GTHG]) * (gnorm / v[SV_GTHG])
        let cnorm = gnorm * cfact
        let relax = 1.0f64 - v[SV_BIAS] * (1.0f64 - cnorm / ghinvg)
        if rlambd >= relax {
            v[SV_STPPAR] = 1.0f64 - (rlambd - relax) / (1.0f64 - relax)
            let t = 0.0f64 - rlambd
            v[SV_GTSTEP] = t * ghinvg * gnorm
            v[SV_PREDUC] = rlambd * (1.0f64 - 0.5f64 * rlambd) * ghinvg * gnorm
            v[SV_NWTFAC] = t
            i = 0usize
            while i < n {
                step[i] = t * nwtstp[i]
                i += 1usize
            }
        } else {
            if cnorm >= v[SV_RADIUS] {
                let t = (0.0f64 - v[SV_RADIUS]) / gnorm
                v[SV_GRDFAC] = t
                v[SV_STPPAR] = 1.0f64 + cnorm / v[SV_RADIUS]
                v[SV_GTSTEP] = (0.0f64 - v[SV_RADIUS]) * gnorm
                v[SV_PREDUC] = v[SV_RADIUS] * (gnorm - 0.5f64 * v[SV_RADIUS] * ((v[SV_GTHG] / gnorm) * (v[SV_GTHG] / gnorm)))
                i = 0usize
                while i < n {
                    step[i] = t * dig[i]
                    i += 1usize
                }
            } else {
                let ctrnwt = cfact * relax * ghinvg / gnorm
                var t1 = ctrnwt - cfact * cfact
                var t2 = (v[SV_RADIUS] / gnorm) * (v[SV_RADIUS] / gnorm) - cfact * cfact
                let femnsq = (relax * nwtnrm / gnorm) * (relax * nwtnrm / gnorm) - ctrnwt - t1
                let t = t2 / (t1 + math.sqrt[f64](t1 * t1 + femnsq * t2))
                t1 = (t - 1.0f64) * cfact
                v[SV_GRDFAC] = t1
                t2 = (0.0f64 - t) * relax
                v[SV_NWTFAC] = t2
                v[SV_STPPAR] = 2.0f64 - t
                v[SV_GTSTEP] = gnorm * (t1 * gnorm + t2 * ghinvg)
                v[SV_PREDUC] = (0.0f64 - (t1 * gnorm)) * ((t2 + 1.0f64) * gnorm) - (t2 * gnorm) * (1.0f64 + 0.5f64 * t2) * ghinvg - 0.5f64 * ((v[SV_GTHG] * t1) * (v[SV_GTHG] * t1))
                i = 0usize
                while i < n {
                    step[i] = t1 * dig[i] + t2 * nwtstp[i]
                    i += 1usize
                }
            }
        }
    }
}

fn sl_relst(p: usize, x: []const f64, x0: []const f64) -> f64 {
    var emax = 0.0f64
    var xmax = 0.0f64
    var i = 0usize
    while i < p {
        var t = math.abs[f64](x[i] - x0[i])
        if emax < t { emax = t }
        t = math.abs[f64](x[i]) + math.abs[f64](x0[i])
        if xmax < t { xmax = t }
        i += 1usize
    }
    if xmax > 0.0f64 { ret emax / xmax }
    ret 0.0f64
}

fn sl_copy(n: usize, to: []f64, from: []const f64) {
    var i = 0usize
    while i < n {
        to[i] = from[i]
        i += 1usize
    }
}

// dassst: assess the trial step (the returned code is iv[SI_IRC]); labels of the Fortran are the lbl values
fn sl_assst(iv: []i64, p: usize, step: []f64, stlstg: []f64, v: []f64, x: []f64, x0: []f64) {
    var nfc = iv[SI_NFCALL]
    iv[SI_SWITCH] = 0i64
    iv[SI_RESTOR] = 0i64
    var rfac1 = 1.0f64
    var goodx = true
    var i = iv[SI_IRC]
    var reldx1 = 0.0f64
    var emax = 0.0f64
    var emaxs = 0.0f64
    var lbl = 0usize
    if i == 1i64 { lbl = 20usize }
    if i == 2i64 { lbl = 30usize }
    if i == 3i64 || i == 4i64 { lbl = 10usize }
    if i == 5i64 { lbl = 40usize }
    if i == 6i64 { lbl = 280usize }
    if i >= 7i64 && i <= 11i64 { lbl = 220usize }
    if i == 12i64 { lbl = 170usize }
    if lbl == 0usize {
        iv[SI_IRC] = 13i64
        lbl = 999usize
    }
    while lbl != 999usize {
        if lbl == 10usize {
            iv[SI_STAGE] = 1i64
            iv[SI_RADINC] = 0i64
            v[SV_FLSTGD] = v[SV_F0]
            if iv[SI_TOOBIG] == 0i64 {
                lbl = 90usize
            } else {
                iv[SI_STAGE] = -1i64
                iv[SI_XIRC] = i
                lbl = 60usize
            }
        } else if lbl == 20usize {
            if iv[SI_MODEL] != iv[SI_MLSTGD] {
                lbl = 30usize
            } else {
                iv[SI_STAGE] = iv[SI_STGLIM]
                iv[SI_RADINC] = -1i64
                lbl = 90usize
            }
        } else if lbl == 30usize {
            iv[SI_STAGE] = iv[SI_STAGE] + 1i64
            lbl = 40usize
        } else if lbl == 40usize {
            if iv[SI_STAGE] > 0i64 {
                lbl = 50usize
            } else {
                if iv[SI_TOOBIG] != 0i64 {
                    lbl = 60usize
                } else {
                    iv[SI_STAGE] = 0i64 - iv[SI_STAGE]
                    i = iv[SI_XIRC]
                    lbl = 50usize
                    if i == 1i64 { lbl = 20usize }
                    if i == 2i64 { lbl = 30usize }
                    if i == 3i64 || i == 4i64 { lbl = 90usize }
                    if i == 5i64 { lbl = 70usize }
                }
            }
        } else if lbl == 50usize {
            if iv[SI_TOOBIG] == 0i64 {
                lbl = 70usize
            } else {
                if iv[SI_RADINC] > 0i64 {
                    lbl = 80usize
                } else {
                    iv[SI_STAGE] = 0i64 - iv[SI_STAGE]
                    iv[SI_XIRC] = iv[SI_IRC]
                    lbl = 60usize
                }
            }
        } else if lbl == 60usize {
            v[SV_RADFAC] = v[SV_DECFAC]
            iv[SI_RADINC] = iv[SI_RADINC] - 1i64
            iv[SI_IRC] = 5i64
            lbl = 999usize
        } else if lbl == 70usize {
            if v[SV_F] < v[SV_FLSTGD] {
                lbl = 90usize
            } else {
                if iv[SI_MODEL] != iv[SI_MLSTGD] {
                    iv[SI_MODEL] = iv[SI_MLSTGD]
                    iv[SI_SWITCH] = 1i64
                }
                lbl = 80usize
            }
        } else if lbl == 80usize {
            if v[SV_FLSTGD] < v[SV_F0] {
                iv[SI_RESTOR] = 1i64
                v[SV_F] = v[SV_FLSTGD]
                v[SV_PREDUC] = v[SV_PLSTGD]
                v[SV_GTSTEP] = v[SV_GTSLST]
                if iv[SI_SWITCH] == 0i64 { rfac1 = v[SV_DSTNRM] / v[SV_DSTSAV] }
                v[SV_DSTNRM] = v[SV_DSTSAV]
                nfc = iv[SI_NFGCAL]
                goodx = false
            }
            lbl = 90usize
        } else if lbl == 90usize {
            reldx1 = sl_relst(p, x, x0)
            if !goodx {
                var q = 0usize
                while q < p {
                    step[q] = stlstg[q]
                    x[q] = x0[q] + stlstg[q]
                    q += 1usize
                }
            }
            lbl = 110usize
        } else if lbl == 110usize {
            v[SV_FDIF] = v[SV_F0] - v[SV_F]
            if v[SV_FDIF] > v[SV_TUNER2] * v[SV_PREDUC] {
                lbl = 140usize
            } else {
                v[SV_RELDX] = reldx1
                if v[SV_F] < v[SV_F0] {
                    iv[SI_NFGCAL] = nfc
                } else {
                    iv[SI_MLSTGD] = iv[SI_MODEL]
                    v[SV_FLSTGD] = v[SV_F]
                    v[SV_F] = v[SV_F0]
                    sl_copy(p, x, x0)
                    iv[SI_RESTOR] = 1i64
                }
                iv[SI_IRC] = 1i64
                if iv[SI_STAGE] >= iv[SI_STGLIM] {
                    iv[SI_IRC] = 5i64
                    iv[SI_RADINC] = iv[SI_RADINC] - 1i64
                }
                lbl = 160usize
            }
        } else if lbl == 140usize {
            iv[SI_NFGCAL] = nfc
            rfac1 = 1.0f64
            if goodx { v[SV_RELDX] = reldx1 }
            v[SV_DSTSAV] = v[SV_DSTNRM]
            if v[SV_FDIF] > v[SV_PREDUC] * v[SV_TUNER1] {
                lbl = 190usize
            } else {
                if iv[SI_STAGE] < iv[SI_STGLIM] { iv[SI_IRC] = 2i64 } else { iv[SI_IRC] = 4i64 }
                lbl = 160usize
            }
        } else if lbl == 160usize {
            iv[SI_XIRC] = iv[SI_IRC]
            emax = v[SV_GTSTEP] + v[SV_FDIF]
            v[SV_RADFAC] = 0.5f64 * rfac1
            if emax < v[SV_GTSTEP] { v[SV_RADFAC] = rfac1 * math.max[f64](v[SV_RDFCMN], 0.5f64 * v[SV_GTSTEP] / emax) }
            lbl = 170usize
        } else if lbl == 170usize {
            if v[SV_RELDX] <= v[SV_XFTOL] {
                iv[SI_IRC] = 12i64
                lbl = 240usize
            } else {
                iv[SI_IRC] = iv[SI_XIRC]
                if v[SV_F] < v[SV_F0] { lbl = 200usize } else { lbl = 230usize }
            }
        } else if lbl == 190usize {
            if v[SV_FDIF] < (0.0f64 - v[SV_TUNER3]) * v[SV_GTSTEP] || iv[SI_RADINC] < 0i64 || iv[SI_RESTOR] == 1i64 {
                lbl = 210usize
            } else {
                v[SV_RADFAC] = v[SV_RDFCMX]
                let gts = v[SV_GTSTEP]
                if v[SV_FDIF] < (0.5f64 / v[SV_RADFAC] - 1.0f64) * gts { v[SV_RADFAC] = math.max[f64](v[SV_INCFAC], 0.5f64 * gts / (gts + v[SV_FDIF])) }
                iv[SI_IRC] = 4i64
                if v[SV_STPPAR] == 0.0f64 {
                    lbl = 230usize
                } else {
                    iv[SI_IRC] = 5i64
                    iv[SI_RADINC] = iv[SI_RADINC] + 1i64
                    lbl = 200usize
                }
            }
        } else if lbl == 200usize {
            v[SV_FLSTGD] = v[SV_F]
            iv[SI_MLSTGD] = iv[SI_MODEL]
            sl_copy(p, stlstg, step)
            v[SV_DSTSAV] = v[SV_DSTNRM]
            iv[SI_NFGCAL] = nfc
            v[SV_PLSTGD] = v[SV_PREDUC]
            v[SV_GTSLST] = v[SV_GTSTEP]
            lbl = 230usize
        } else if lbl == 210usize {
            v[SV_RADFAC] = 1.0f64
            iv[SI_IRC] = 3i64
            lbl = 230usize
        } else if lbl == 220usize {
            iv[SI_IRC] = iv[SI_XIRC]
            if v[SV_DSTSAV] < 0.0f64 { iv[SI_IRC] = 12i64 }
            lbl = 240usize
        } else if lbl == 230usize {
            iv[SI_XIRC] = iv[SI_IRC]
            lbl = 240usize
        } else if lbl == 240usize {
            if math.abs[f64](v[SV_F]) < v[SV_AFCTOL] { iv[SI_IRC] = 10i64 }
            if 0.5f64 * v[SV_FDIF] > v[SV_PREDUC] {
                lbl = 999usize
            } else {
                emax = v[SV_RFCTOL] * math.abs[f64](v[SV_F0])
                emaxs = v[SV_SCTOL] * math.abs[f64](v[SV_F0])
                if v[SV_DSTNRM] > v[SV_LMAXS] && v[SV_PREDUC] <= emaxs { iv[SI_IRC] = 11i64 }
                if v[SV_DST0] >= 0.0f64 {
                    var k = 0i64
                    if (v[SV_NREDUC] > 0.0f64 && v[SV_NREDUC] <= emax) || (v[SV_NREDUC] == 0.0f64 && v[SV_PREDUC] == 0.0f64) { k = 2i64 }
                    if v[SV_STPPAR] == 0.0f64 && v[SV_RELDX] <= v[SV_XCTOL] && goodx { k = k + 1i64 }
                    if k > 0i64 { iv[SI_IRC] = k + 6i64 }
                }
                lbl = 250usize
            }
        } else if lbl == 250usize {
            if iv[SI_IRC] > 5i64 && iv[SI_IRC] != 12i64 {
                lbl = 999usize
            } else {
                if v[SV_DSTNRM] > v[SV_LMAXS] {
                    lbl = 260usize
                } else {
                    if v[SV_PREDUC] >= emaxs {
                        lbl = 999usize
                    } else {
                        if v[SV_DST0] <= 0.0f64 {
                            lbl = 270usize
                        } else {
                            if 0.5f64 * v[SV_DST0] <= v[SV_LMAXS] { lbl = 999usize } else { lbl = 270usize }
                        }
                    }
                }
            }
        } else if lbl == 260usize {
            if 0.5f64 * v[SV_DSTNRM] <= v[SV_LMAXS] {
                lbl = 999usize
            } else {
                let xmax = v[SV_LMAXS] / v[SV_DSTNRM]
                if xmax * (2.0f64 - xmax) * v[SV_PREDUC] >= emaxs { lbl = 999usize } else { lbl = 270usize }
            }
        } else if lbl == 270usize {
            if v[SV_NREDUC] < 0.0f64 {
                lbl = 290usize
            } else {
                v[SV_GTSLST] = v[SV_GTSTEP]
                v[SV_DSTSAV] = v[SV_DSTNRM]
                if iv[SI_IRC] == 12i64 { v[SV_DSTSAV] = 0.0f64 - v[SV_DSTSAV] }
                v[SV_PLSTGD] = v[SV_PREDUC]
                iv[SI_IRC] = 6i64
                sl_copy(p, stlstg, step)
                lbl = 999usize
            }
        } else if lbl == 280usize {
            v[SV_GTSTEP] = v[SV_GTSLST]
            v[SV_DSTNRM] = math.abs[f64](v[SV_DSTSAV])
            sl_copy(p, step, stlstg)
            iv[SI_IRC] = iv[SI_XIRC]
            if v[SV_DSTSAV] <= 0.0f64 { iv[SI_IRC] = 12i64 }
            v[SV_NREDUC] = 0.0f64 - v[SV_PREDUC]
            v[SV_PREDUC] = v[SV_PLSTGD]
            lbl = 290usize
        } else {
            // 290
            if (0.0f64 - v[SV_NREDUC]) <= v[SV_RFCTOL] * math.abs[f64](v[SV_F0]) { iv[SI_IRC] = 11i64 }
            lbl = 999usize
        }
    }
}

type GarchCtx = struct { y: []const f64, h: []f64, dh: []f64, n: usize, p: usize, q: usize }

fn garch_nll(c: *GarchCtx, par: []const f64) -> f64 {
    let pq = c.p + c.q + 1usize
    var maxpq = c.p
    if c.q > maxpq { maxpq = c.q }
    var valid = par[0usize] > 0.0f64
    var i = 1usize
    while i < pq {
        if par[i] < 0.0f64 { valid = false }
        i += 1usize
    }
    if !valid { ret 1.0e10f64 }
    var sum = 0.0f64
    i = maxpq
    while i < c.n {
        var temp = par[0usize]
        var j = 1usize
        while j <= c.q {
            temp += par[j] * (c.y[i - j] * c.y[i - j])
            j += 1usize
        }
        j = 1usize
        while j <= c.p {
            temp += par[c.q + j] * c.h[i - j]
            j += 1usize
        }
        sum += math.log[f64](temp) + (c.y[i] * c.y[i]) / temp
        c.h[i] = temp
        i += 1usize
    }
    ret 0.5f64 * sum
}

fn garch_grad(c: *GarchCtx, par: []const f64, dp: []f64) {
    let pq = c.p + c.q + 1usize
    var maxpq = c.p
    if c.q > maxpq { maxpq = c.q }
    var k = 0usize
    while k < pq {
        dp[k] = 0.0f64
        k += 1usize
    }
    var i = maxpq
    while i < c.n {
        var temp1 = par[0usize]
        var j = 1usize
        while j <= c.q {
            temp1 += par[j] * (c.y[i - j] * c.y[i - j])
            j += 1usize
        }
        j = 1usize
        while j <= c.p {
            temp1 += par[c.q + j] * c.h[i - j]
            j += 1usize
        }
        c.h[i] = temp1
        let temp2 = 0.5f64 * (1.0f64 - (c.y[i] * c.y[i]) / temp1) / temp1
        var temp3 = 1.0f64
        j = 1usize
        while j <= c.p {
            temp3 += par[c.q + j] * c.dh[pq * (i - j)]
            j += 1usize
        }
        c.dh[pq * i] = temp3
        dp[0usize] += temp2 * temp3
        k = 1usize
        while k <= c.q {
            temp3 = c.y[i - k] * c.y[i - k]
            j = 1usize
            while j <= c.p {
                temp3 += par[c.q + j] * c.dh[pq * (i - j) + k]
                j += 1usize
            }
            c.dh[pq * i + k] = temp3
            dp[k] += temp2 * temp3
            k += 1usize
        }
        k = 1usize
        while k <= c.p {
            temp3 = c.h[i - k]
            j = 1usize
            while j <= c.p {
                temp3 += par[c.q + j] * c.dh[pq * (i - j) + c.q + k]
                j += 1usize
            }
            c.dh[pq * i + c.q + k] = temp3
            dp[c.q + k] += temp2 * temp3
            k += 1usize
        }
        i += 1usize
    }
}

// the SUMSL iteration (dsumit) for a GARCH(p, q) likelihood: par is the start and the answer. Constants are the ddeflt/dvdflt defaults of algorithm 2 with the tseries overrides afctol, rfctol, xctol, xftol and the call limits 2 * maxiter and maxiter.
fn sumsl_garch(a: *mem.Arena, c: *GarchCtx, par: []f64, maxiter: usize, afctol: f64, rfctol: f64, xctol: f64, xftol: f64) -> err {
    let n = c.p + c.q + 1usize
    let nn1o2 = n * (n + 1usize) / 2usize
    let (v, e1) = mem.alloc[f64](a, 80usize + nn1o2 + 8usize * n)
    let (iv, e2) = mem.alloc[i64](a, 64usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < 80usize + nn1o2 + 8usize * n {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 64usize {
        iv[i] = 0i64
        i += 1usize
    }
    v[SV_DECFAC] = 0.5f64
    v[SV_INCFAC] = 2.0f64
    v[SV_LMAX0] = 1.0f64
    v[SV_LMAXS] = 1.0f64
    v[SV_RDFCMN] = 0.1f64
    v[SV_RDFCMX] = 4.0f64
    v[SV_SCTOL] = 1.0e-10f64
    v[SV_TUNER1] = 0.1f64
    v[SV_TUNER2] = 1.0e-4f64
    v[SV_TUNER3] = 0.75f64
    v[SV_TUNER4] = 0.5f64
    v[SV_TUNER5] = 0.75f64
    v[SV_BIAS] = 0.8f64
    v[SV_AFCTOL] = afctol
    v[SV_RFCTOL] = rfctol
    v[SV_XCTOL] = xctol
    v[SV_XFTOL] = xftol
    let mxfcal = i64(2usize * maxiter)
    let mxiter = i64(maxiter)
    // storage in v: the factor L, then x0, step, stlstg, g0, nwtstp, dg, g
    let lo = 72usize
    let x0o = lo + nn1o2
    let stepo = x0o + n
    let stlo = stepo + n
    let g0o = stlo + n
    let nwo = g0o + n
    let dgo = nwo + n
    let go_ = dgo + n
    let d = 1.0f64
    // initial factor: the identity
    var k = 0usize
    i = 1usize
    while i <= n {
        k += i
        v[lo + k - 1usize] = d
        i += 1usize
    }
    iv[SI_NFCALL] = 1i64
    iv[SI_NFGCAL] = 1i64
    iv[SI_MODEL] = 1i64
    iv[SI_STGLIM] = 1i64
    var niter = 0i64
    var nfcall = 1i64
    var cnvcod = 0i64
    var finished = false
    // the first function value and gradient
    v[SV_F] = garch_nll(c, par)
    garch_grad(c, par, v[go_..go_ + n])
    i = 0usize
    while i < n {
        v[dgo + i] = v[go_ + i] / d
        i += 1usize
    }
    v[SV_DGNORM] = nrm2_of(n, v[dgo..dgo + n])
    v[SV_RADFAC] = v[SV_LMAX0]
    v[SV_DSTNRM] = 1.0f64
    var lbl = 80usize
    var kagqt = 0i64
    while !finished {
        if lbl == 80usize {
            if niter >= mxiter { finished = true } else { lbl = 90usize }
        } else if lbl == 90usize {
            niter += 1i64
            v[SV_RADIUS] = v[SV_RADFAC] * v[SV_DSTNRM]
            sl_copy(n, v[x0o..x0o + n], par)
            sl_copy(n, v[g0o..g0o + n], v[go_..go_ + n])
            v[SV_F0] = v[SV_F]
            iv[SI_IRC] = 4i64
            kagqt = 0i64 - 1i64
            lbl = 120usize
        } else if lbl == 100usize {
            lbl = 120usize
        } else if lbl == 120usize {
            if nfcall >= mxfcal {
                if v[SV_F] >= v[SV_F0] {
                    finished = true
                } else {
                    cnvcod = 9i64
                    lbl = 210usize
                }
            } else {
                lbl = 140usize
            }
        } else if lbl == 140usize {
            if kagqt < 0i64 {
                sl_ivmu(n, v[nwo..nwo + n], v[lo..lo + nn1o2], v[go_..go_ + n])
                sl_itvm(n, v[nwo..nwo + n], v[lo..lo + nn1o2], v[nwo..nwo + n])
                i = 0usize
                while i < n {
                    v[stepo + i] = v[nwo + i] * d
                    i += 1usize
                }
                v[SV_DST0] = nrm2_of(n, v[stepo..stepo + n])
                i = 0usize
                while i < n {
                    v[dgo + i] = v[dgo + i] / d
                    i += 1usize
                }
                sl_tvmu(n, v[stepo..stepo + n], v[lo..lo + nn1o2], v[dgo..dgo + n])
                v[SV_GTHG] = nrm2_of(n, v[stepo..stepo + n])
                kagqt = 0i64
            }
            sl_dbdog(n, v[dgo..dgo + n], v[go_..go_ + n], v[nwo..nwo + n], v[stepo..stepo + n], v)
            if iv[SI_IRC] == 6i64 {
                lbl = 160usize
            } else {
                i = 0usize
                while i < n {
                    par[i] = v[stepo + i] + v[x0o + i]
                    i += 1usize
                }
                nfcall += 1i64
                iv[SI_NFCALL] = nfcall
                iv[SI_TOOBIG] = 0i64
                v[SV_F] = garch_nll(c, par)
                lbl = 160usize
            }
        } else if lbl == 160usize {
            iv[SI_NFCALL] = nfcall
            sl_assst(iv, n, v[stepo..stepo + n], v[stlo..stlo + n], v, par, v[x0o..x0o + n])
            let kk = iv[SI_IRC]
            if kk == 1i64 || kk == 5i64 {
                v[SV_RADIUS] = v[SV_RADFAC] * v[SV_DSTNRM]
                lbl = 100usize
            } else if kk == 6i64 {
                v[SV_RADIUS] = v[SV_LMAX0]
                lbl = 140usize
            } else if kk >= 2i64 && kk <= 4i64 {
                lbl = 200usize
            } else if kk >= 7i64 && kk <= 12i64 {
                cnvcod = kk - 4i64
                if v[SV_F] >= v[SV_F0] {
                    finished = true
                } else {
                    if iv[SI_XIRC] == 14i64 {
                        finished = true
                    } else {
                        iv[SI_XIRC] = 14i64
                        lbl = 200usize
                    }
                }
            } else {
                finished = true
            }
        } else if lbl == 200usize {
            if iv[SI_IRC] == 3i64 {
                sl_tvmu(n, v[stlo..stlo + n], v[lo..lo + nn1o2], v[stepo..stepo + n])
                sl_vmul(n, v[stlo..stlo + n], v[lo..lo + nn1o2], v[stlo..stlo + n])
            }
            lbl = 210usize
        } else {
            // 210: the gradient at the accepted point, then the secant update (label 220) and the next iteration
            garch_grad(c, par, v[go_..go_ + n])
            i = 0usize
            while i < n {
                v[dgo + i] = v[go_ + i] / d
                i += 1usize
            }
            v[SV_DGNORM] = nrm2_of(n, v[dgo..dgo + n])
            if cnvcod != 0i64 {
                finished = true
            } else {
                i = 0usize
                while i < n {
                    v[g0o + i] = (0.0f64 - 1.0f64) * v[g0o + i] + v[go_ + i]
                    i += 1usize
                }
                var radfac_set = false
                if iv[SI_IRC] == 3i64 {
                    i = 0usize
                    while i < n {
                        v[stlo + i] = (0.0f64 - 1.0f64) * v[g0o + i] + v[stlo + i]
                        v[stlo + i] = v[stlo + i] / d
                        i += 1usize
                    }
                    if nrm2_of(n, v[stlo..stlo + n]) <= v[SV_DGNORM] * v[SV_TUNER4] {
                        radfac_set = true
                    } else {
                        if dot_of(n, v[go_..go_ + n], v[stepo..stepo + n]) < v[SV_GTSTEP] * v[SV_TUNER5] { radfac_set = true }
                    }
                }
                if radfac_set { v[SV_RADFAC] = v[SV_INCFAC] }
                sl_wzbfg(n, v[lo..lo + nn1o2], v[stepo..stepo + n], v[nwo..nwo + n], v[g0o..g0o + n], v[x0o..x0o + n])
                sl_updt(v[stlo..stlo + n], v[stepo..stepo + n], v[lo..lo + nn1o2], v[g0o..g0o + n], v[lo..lo + nn1o2], n, v[nwo..nwo + n], v[x0o..x0o + n])
                lbl = 80usize
            }
        }
    }
    ret ok
}

// ar(x)$resid with the Yule-Walker AIC order: out gets x minus its mean minus the AR fit, NaN for the first `order` values; returns the order
fn yw_resid(a: *mem.Arena, x: []const f64, out: []f64) -> usize {
    let n = x.len
    var omax = usize(math.floor[f64](10.0f64 * math.log10[f64](f64(n))))
    if omax > n - 1usize { omax = n - 1usize }
    let (r, e1) = acf_cov(a, x, omax)
    let (tab, e2) = mem.alloc[f64](a, (omax + 1usize) * (omax + 1usize))
    let (vv, e3) = mem.alloc[f64](a, omax + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    vv[0usize] = r[0usize]
    var p = 1usize
    while p <= omax {
        var s = r[p]
        var j = 1usize
        while j < p {
            s -= tab[(p - 1usize) * (omax + 1usize) + j] * r[p - j]
            j += 1usize
        }
        let k = s / vv[p - 1usize]
        tab[p * (omax + 1usize) + p] = k
        j = 1usize
        while j < p {
            tab[p * (omax + 1usize) + j] = tab[(p - 1usize) * (omax + 1usize) + j] - k * tab[(p - 1usize) * (omax + 1usize) + p - j]
            j += 1usize
        }
        vv[p] = vv[p - 1usize] * (1.0f64 - k * k)
        p += 1usize
    }
    var order = 0usize
    var best = f64(n) * math.log[f64](vv[0usize])
    p = 1usize
    while p <= omax {
        let aic = f64(n) * math.log[f64](vv[p]) + 2.0f64 * f64(p)
        if aic < best {
            best = aic
            order = p
        }
        p += 1usize
    }
    let mu = mean_of(x)
    var t = 0usize
    while t < n {
        if t < order {
            out[t] = nan()
        } else {
            var s = x[t] - mu
            var j = 1usize
            while j <= order {
                s -= tab[order * (omax + 1usize) + j] * (x[t - j] - mu)
                j += 1usize
            }
            out[t] = s
        }
        t += 1usize
    }
    ret order
}

fn lb12(a: *mem.Arena, w: []const f64) -> f64 {
    let (sq, e) = mem.alloc[f64](a, w.len)
    if e != ok { ret nan() }
    var i = 0usize
    while i < w.len {
        sq[i] = w[i] * w[i]
        i += 1usize
    }
    let (r, e2) = acf(a, sq, 12usize)
    if e2 != ok { ret nan() }
    var s = 0.0f64
    i = 1usize
    while i <= 12usize {
        s += r[i] * r[i]
        i += 1usize
    }
    ret s
}

// tsfeatures::heterogeneity(x): out = [arch_acf, garch_acf, arch_r2, garch_r2] from the Yule-Walker residuals and a tseries::garch(1, 1) fit
fn heterogeneity(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let n = x.len
    out[0usize] = nan()
    out[1usize] = nan()
    out[2usize] = nan()
    out[3usize] = nan()
    let (res, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    let order = yw_resid(a, x, res)
    let w = res[order..n]
    let m = w.len
    out[2usize] = arch_stat(a, w, 12usize, true)
    out[0usize] = lb12(a, w)
    let (h, e1) = mem.alloc[f64](a, m)
    let (dh, e2) = mem.alloc[f64](a, m * 3usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var c = GarchCtx{ y: w, h: h, dh: dh, n: m, p: 1usize, q: 1usize }
    var vs = 0.0f64
    var i = 0usize
    while i < m {
        vs += w[i] * w[i]
        i += 1usize
    }
    vs = vs / f64(m)
    h[0usize] = vs
    dh[0usize] = 1.0f64
    dh[1usize] = 0.0f64
    dh[2usize] = 0.0f64
    var par: [3]f64 = zero
    par[0usize] = var_of(w) * (1.0f64 - 0.05f64 * 2.0f64)
    par[1usize] = 0.05f64
    par[2usize] = 0.05f64
    let e3 = sumsl_garch(a, &c, par[0usize..3usize], 200usize, 1.0e-20f64, 1.0e-10f64, 1.4901161193847656e-08f64, 2.220446049250313e-14f64)
    if e3 != ok { ret e3 }
    let (hp, e4) = mem.alloc[f64](a, m)
    if e4 != ok { ret e4 }
    hp[0usize] = par[0usize] / (1.0f64 - par[1usize] - par[2usize])
    i = 1usize
    while i < m {
        hp[i] = par[0usize] + par[1usize] * (w[i - 1usize] * w[i - 1usize]) + par[2usize] * hp[i - 1usize]
        i += 1usize
    }
    let (z, e5) = mem.alloc[f64](a, m)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < m {
        z[i] = w[i] / math.sqrt[f64](hp[i])
        i += 1usize
    }
    let zz = z[1usize..m]
    out[3usize] = arch_stat(a, zz, 12usize, true)
    out[1usize] = lb12(a, zz)
    ret ok
}

// acf(x, type = "covariance", lag.max)$acf: the autocovariances with denominator n
fn acf_cov(a: *mem.Arena, x: []const f64, lag_max: usize) -> ([]f64, err) {
    let (r, e) = acf(a, x, lag_max)
    if e != ok { ret (r, e) }
    let m = mean_of(x)
    var c0 = 0.0f64
    var i = 0usize
    while i < x.len {
        c0 += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    c0 = c0 / f64(x.len)
    i = 0usize
    while i <= lag_max {
        r[i] = r[i] * c0
        i += 1usize
    }
    ret (r, ok)
}
