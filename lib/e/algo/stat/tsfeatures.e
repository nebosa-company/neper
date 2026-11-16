// R tsfeatures, the closed-form features of one series: acf and pacf features (`acf_features`, `pacf_features`), crossing_points,
// flat_spots, lumpiness and stability (on the standardised series), max_level_shift and max_var_shift (rolling mean and variance
// differenced at the window width), firstmin_ac, firstzero_ac, ac_9, embed2_incircle, std1st_der, trev_num, walker_propcross,
// motiftwo_entro3 and zero_proportion. `acf` is R's (denominator n, mean removed) and `pacf` the Durbin-Levinson recursion over it.
//
// Not here: the features that fit models (stl, arch and garch, hurst, holt and hw parameters, entropy by Burg's spectrum, the
// unit-root tests of urca and nonlinearity), histogram_mode, the sample entropies and the features that sample.

use e.math
use e.mem

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
