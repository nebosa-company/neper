// Streaming statistics: Welford's running moments, merged by Chan's formula, and a
// bivariate accumulator for a least-squares line and Pearson's correlation. Every
// answer that divides by a count or a spread says `false` when there is not enough
// data for it.
//
// Below the accumulators, batch statistics over `[]const f64` samples: a compensated
// mean, the Hyndman-Fan quantiles, sample skewness and kurtosis, Shannon entropy,
// covariance matrices with Ledoit-Wolf shrinkage, Pearson, Spearman and Kendall
// correlations, Gaussian kernel density, bootstrap and jackknife resampling, binomial
// proportion intervals, empirical value at risk and expected shortfall, and
// moment and maximum-likelihood fits of the normal, exponential, gamma and beta
// distributions. Scratch slices are the caller's; a sample said to be `sorted` is
// ascending.

use e.algo.rand
use e.algo.sort
use e.math
use e.math.special

error TooSmall
error Invalid

type Moments = struct { count: u64, mean: f64, m2: f64, min: f64, max: f64 }
type Regression = struct { count: u64, mean_x: f64, mean_y: f64, m2_x: f64, m2_y: f64, cov: f64 }

fn moments() -> Moments {
    var s: Moments = zero
    ret s
}

fn moments_add(s: *Moments, x: f64) {
    if s.count == 0u64 {
        s.min = x
        s.max = x
    } else {
        if x < s.min { s.min = x }
        if x > s.max { s.max = x }
    }
    s.count += 1u64
    let delta = x - s.mean
    s.mean = s.mean + delta / f64(s.count)
    s.m2 = s.m2 + delta * (x - s.mean)
}

fn moments_merge(dst: *Moments, src: *const Moments) {
    if src.count == 0u64 { ret }
    if dst.count == 0u64 {
        dst.count = src.count
        dst.mean = src.mean
        dst.m2 = src.m2
        dst.min = src.min
        dst.max = src.max
        ret
    }
    let total = dst.count + src.count
    let delta = src.mean - dst.mean
    dst.mean = dst.mean + delta * f64(src.count) / f64(total)
    dst.m2 = dst.m2 + src.m2 + delta * delta * f64(dst.count) * f64(src.count) / f64(total)
    if src.min < dst.min { dst.min = src.min }
    if src.max > dst.max { dst.max = src.max }
    dst.count = total
}

fn variance_population(s: *const Moments) -> (f64, bool) {
    if s.count == 0u64 { ret (0.0, false) }
    ret (s.m2 / f64(s.count), true)
}

fn variance_sample(s: *const Moments) -> (f64, bool) {
    if s.count < 2u64 { ret (0.0, false) }
    ret (s.m2 / f64(s.count - 1u64), true)
}

fn standard_deviation_population(s: *const Moments) -> (f64, bool) {
    let (variance, has_variance) = variance_population(s)
    if !has_variance { ret (0.0, false) }
    ret (math.sqrt[f64](variance), true)
}

fn standard_deviation_sample(s: *const Moments) -> (f64, bool) {
    let (variance, has_variance) = variance_sample(s)
    if !has_variance { ret (0.0, false) }
    ret (math.sqrt[f64](variance), true)
}

fn regression() -> Regression {
    var s: Regression = zero
    ret s
}

fn regression_add(s: *Regression, x: f64, y: f64) {
    s.count += 1u64
    let n = f64(s.count)
    let delta_x = x - s.mean_x
    let delta_y = y - s.mean_y
    s.mean_x = s.mean_x + delta_x / n
    s.mean_y = s.mean_y + delta_y / n
    s.m2_x = s.m2_x + delta_x * (x - s.mean_x)
    s.m2_y = s.m2_y + delta_y * (y - s.mean_y)
    s.cov = s.cov + delta_x * (y - s.mean_y)
}

// The least-squares line needs two points and some spread in x.
fn regression_slope(s: *const Regression) -> (f64, bool) {
    if s.count < 2u64 || s.m2_x == 0.0 { ret (0.0, false) }
    ret (s.cov / s.m2_x, true)
}

fn regression_intercept(s: *const Regression) -> (f64, bool) {
    let (slope, has_slope) = regression_slope(s)
    if !has_slope { ret (0.0, false) }
    ret (s.mean_y - slope * s.mean_x, true)
}

fn correlation(s: *const Regression) -> (f64, bool) {
    if s.count < 2u64 || s.m2_x == 0.0 || s.m2_y == 0.0 { ret (0.0, false) }
    ret (s.cov / math.sqrt[f64](s.m2_x * s.m2_y), true)
}

// ---- Batch statistics over samples ----

// Hyndman-Fan quantile definitions R-1..R-9 (numpy's `inverted_cdf` ..
// `normal_unbiased`; R7 is numpy's default `linear`) and numpy's `nearest`.
type QuantileMethod = enum u8 { R1, R2, R3, R4, R5, R6, R7, R8, R9, Nearest }
// Kernel bandwidth rules of thumb, as `scipy.stats.gaussian_kde` scales them.
type Bandwidth = enum u8 { Silverman, Scott }
type Distribution = enum u8 { Normal, Exponential, Gamma, Beta }
// The two parameters of a fit: Normal (mean, standard deviation), Exponential
// (rate, 0), Gamma (shape, scale), Beta (alpha, beta).
type Fit = struct { a: f64, b: f64 }
type Interval = struct { low: f64, high: f64 }
// `estimate` is the statistic of the full sample; the bias-corrected value is
// `estimate - bias`.
type Jackknife = struct { estimate: f64, bias: f64, standard_error: f64 }
type RankKey = struct { values: []const f64 }

fn sum_plain(values: []const f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        total += values[i]
        i += 1usize
    }
    ret total
}

// The mean by Neumaier's compensated sum: the rounding error of every addition
// is carried separately and folded in at the end.
fn mean_compensated(values: []const f64) -> (f64, bool) {
    if values.len == 0usize { ret (0.0f64, false) }
    var total = 0.0f64
    var compensation = 0.0f64
    var i = 0usize
    while i < values.len {
        let x = values[i]
        let t = total + x
        if math.abs[f64](total) >= math.abs[f64](x) {
            compensation += (total - t) + x
        } else {
            compensation += (x - t) + total
        }
        total = t
        i += 1usize
    }
    ret ((total + compensation) / f64(values.len), true)
}

// numpy's `_lerp`: the form that is exact at both ends.
fn lerp(a: f64, b: f64, t: f64) -> f64 {
    if t >= 0.5f64 { ret b - (b - a) * (1.0f64 - t) }
    ret a + (b - a) * t
}

// The `p`-quantile (0 <= p <= 1) of an ascending sample; `false` when the sample
// is empty or `p` is out of range. Bit-for-bit numpy's `quantile(method=...)`.
fn quantile(sorted: []const f64, p: f64, method: QuantileMethod) -> (f64, bool) {
    let n = sorted.len
    if n == 0usize || !(p >= 0.0f64 && p <= 1.0f64) { ret (0.0f64, false) }
    let nf = f64(n)
    let last = n - 1usize
    if method == .Nearest {
        let k = math.round[f64]((nf - 1.0f64) * p)
        ret (sorted[usize(k)], true)
    }
    if method == .R1 || method == .R3 {
        var index = nf * p - 1.0f64
        if method == .R3 { index -= 0.5f64 }
        let previous = math.floor[f64](index)
        var chosen = previous + 1.0f64
        if index == previous {
            if method == .R1 { chosen = previous }
            // R3 keeps the previous only when it is odd (zero-based), which is
            // the even order statistic of the paper.
            if method == .R3 && previous >= 0.0f64 && i64(previous) % 2i64 == 1i64 { chosen = previous }
        }
        if chosen < 0.0f64 { chosen = 0.0f64 }
        if chosen > f64(last) { chosen = f64(last) }
        ret (sorted[usize(chosen)], true)
    }
    var virtual = 0.0f64
    var alpha = 1.0f64
    var beta = 1.0f64
    if method == .R4 { alpha = 0.0f64 }
    if method == .R5 {
        alpha = 0.5f64
        beta = 0.5f64
    }
    if method == .R6 {
        alpha = 0.0f64
        beta = 0.0f64
    }
    if method == .R8 {
        alpha = 1.0f64 / 3.0f64
        beta = alpha
    }
    if method == .R9 {
        alpha = 0.375f64
        beta = 0.375f64
    }
    if method == .R7 {
        virtual = (nf - 1.0f64) * p
    } else if method == .R2 {
        virtual = nf * p - 1.0f64
    } else {
        virtual = nf * p + (alpha + p * (1.0f64 - alpha - beta)) - 1.0f64
    }
    let previous = math.floor[f64](virtual)
    var gamma = virtual - previous
    if method == .R2 {
        gamma = 1.0f64
        if virtual == previous { gamma = 0.5f64 }
    }
    var lo = 0usize
    var hi = 0usize
    if virtual >= nf - 1.0f64 {
        lo = last
        hi = last
    } else if virtual >= 0.0f64 {
        lo = usize(previous)
        hi = lo + 1usize
    }
    ret (lerp(sorted[lo], sorted[hi], gamma), true)
}

// Central moments about the mean with divisor n: (mean, m2, m3, m4).
fn central_moments(values: []const f64) -> (f64, f64, f64, f64) {
    let n = f64(values.len)
    let mu = sum_plain(values) / n
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    var i = 0usize
    while i < values.len {
        let d = values[i] - mu
        let d2 = d * d
        m2 += d2
        m3 += d2 * d
        m4 += d2 * d2
        i += 1usize
    }
    ret (mu, m2 / n, m3 / n, m4 / n)
}

// The sample-adjusted skewness G1 (`scipy.stats.skew(bias=False)`); needs three
// values and some spread.
fn skewness(values: []const f64) -> (f64, bool) {
    if values.len < 3usize { ret (0.0f64, false) }
    let (_, m2, m3, _) = central_moments(values)
    if m2 == 0.0f64 { ret (0.0f64, false) }
    let n = f64(values.len)
    let g1 = m3 / math.pow[f64](m2, 1.5f64)
    ret (g1 * math.sqrt[f64](n * (n - 1.0f64)) / (n - 2.0f64), true)
}

// The sample-adjusted excess kurtosis G2 (`scipy.stats.kurtosis(bias=False)`);
// needs four values and some spread.
fn kurtosis(values: []const f64) -> (f64, bool) {
    if values.len < 4usize { ret (0.0f64, false) }
    let (_, m2, _, m4) = central_moments(values)
    if m2 == 0.0f64 { ret (0.0f64, false) }
    let n = f64(values.len)
    let g2 = m4 / (m2 * m2) - 3.0f64
    ret (((n + 1.0f64) * g2 + 6.0f64) * (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64)), true)
}

// Shannon entropy in nats of a weight vector that is normalised first, so counts
// and probabilities both serve; zero weights contribute nothing. `false` for an
// empty, negative or all-zero vector.
fn entropy(weights: []const f64) -> (f64, bool) {
    var total = 0.0f64
    var i = 0usize
    while i < weights.len {
        if weights[i] < 0.0f64 { ret (0.0f64, false) }
        total += weights[i]
        i += 1usize
    }
    if total <= 0.0f64 { ret (0.0f64, false) }
    var h = 0.0f64
    i = 0usize
    while i < weights.len {
        if weights[i] > 0.0f64 {
            let p = weights[i] / total
            h -= p * math.log[f64](p)
        }
        i += 1usize
    }
    ret (h, true)
}

// Shannon entropy in bits of a histogram of counts (a 256-bin byte histogram
// answers between 0 and 8).
fn entropy_counts(counts: []const u64) -> (f64, bool) {
    var total = 0u64
    var i = 0usize
    while i < counts.len {
        total += counts[i]
        i += 1usize
    }
    if total == 0u64 { ret (0.0f64, false) }
    var h = 0.0f64
    i = 0usize
    while i < counts.len {
        if counts[i] != 0u64 {
            let p = f64(counts[i]) / f64(total)
            h -= p * math.log2[f64](p)
        }
        i += 1usize
    }
    ret (h, true)
}

// Column means and the centred cross products of a row-major `n x columns` matrix
// into `out` (`columns x columns`), divided by `divisor`.
fn cross_products(rows: []const f64, columns: usize, out: []f64, divisor: f64) -> err {
    if columns == 0usize || rows.len % columns != 0usize { ret Invalid }
    if out.len < columns * columns { ret TooSmall }
    let n = rows.len / columns
    var j = 0usize
    while j < columns {
        var k = 0usize
        while k < columns {
            out[j * columns + k] = 0.0f64
            k += 1usize
        }
        // The diagonal holds the column mean while it is being formed.
        var total = 0.0f64
        var i = 0usize
        while i < n {
            total += rows[i * columns + j]
            i += 1usize
        }
        out[j * columns + j] = total / f64(n)
        j += 1usize
    }
    var i = 0usize
    while i < n {
        j = 0usize
        while j < columns {
            let dj = rows[i * columns + j] - out[j * columns + j]
            var k = j + 1usize
            while k < columns {
                let dk = rows[i * columns + k] - out[k * columns + k]
                out[j * columns + k] += dj * dk
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < columns {
        let mu = out[j * columns + j]
        var total = 0.0f64
        i = 0usize
        while i < n {
            let d = rows[i * columns + j] - mu
            total += d * d
            i += 1usize
        }
        out[j * columns + j] = total / divisor
        var k = j + 1usize
        while k < columns {
            out[j * columns + k] = out[j * columns + k] / divisor
            out[k * columns + j] = out[j * columns + k]
            k += 1usize
        }
        j += 1usize
    }
    ret ok
}

// The sample covariance (divisor n - 1) of the columns of a row-major matrix
// with `columns` columns; `out` receives `columns x columns`. `numpy.cov(rowvar=False)`.
fn covariance_matrix(rows: []const f64, columns: usize, out: []f64) -> err {
    if columns == 0usize || rows.len < 2usize * columns { ret Invalid }
    ret cross_products(rows, columns, out, f64(rows.len / columns) - 1.0f64)
}

// Ledoit-Wolf (2004) shrinkage of the biased covariance (divisor n) toward the
// scaled identity, as `sklearn.covariance.ledoit_wolf`; answers the shrinkage
// weight and leaves the shrunk matrix in `out`.
fn covariance_shrink(rows: []const f64, columns: usize, out: []f64) -> (f64, err) {
    if columns == 0usize || rows.len < columns || rows.len % columns != 0usize { ret (0.0f64, Invalid) }
    if out.len < columns * columns { ret (0.0f64, TooSmall) }
    let n = rows.len / columns
    let p = f64(columns)
    // The column means sit in the first row of `out` until the covariance
    // overwrites them, so the centred row norms need no scratch.
    var j = 0usize
    while j < columns {
        var total = 0.0f64
        var i = 0usize
        while i < n {
            total += rows[i * columns + j]
            i += 1usize
        }
        out[j] = total / f64(n)
        j += 1usize
    }
    // Sum over samples of the squared norm of the centred row, squared: the
    // <X2.T, X2> total of the reference.
    var beta_sum = 0.0f64
    var i = 0usize
    while i < n {
        var norm2 = 0.0f64
        j = 0usize
        while j < columns {
            let d = rows[i * columns + j] - out[j]
            norm2 += d * d
            j += 1usize
        }
        beta_sum += norm2 * norm2
        i += 1usize
    }
    let e = cross_products(rows, columns, out, f64(n))
    if e != ok { ret (0.0f64, e) }
    if columns == 1usize { ret (0.0f64, ok) }
    var trace = 0.0f64
    var delta_sum = 0.0f64
    j = 0usize
    while j < columns {
        trace += out[j * columns + j]
        var k = 0usize
        while k < columns {
            let c = out[j * columns + k]
            delta_sum += c * c
            k += 1usize
        }
        j += 1usize
    }
    let mu = trace / p
    var beta = (beta_sum / f64(n) - delta_sum) / (p * f64(n))
    let delta = (delta_sum - 2.0f64 * mu * trace + p * mu * mu) / p
    if delta < beta { beta = delta }
    var shrinkage = 0.0f64
    if beta != 0.0f64 { shrinkage = beta / delta }
    j = 0usize
    while j < columns * columns {
        out[j] = (1.0f64 - shrinkage) * out[j]
        j += 1usize
    }
    j = 0usize
    while j < columns {
        out[j * columns + j] += shrinkage * mu
        j += 1usize
    }
    ret (shrinkage, ok)
}

// Pearson's r of two equal-length samples; `false` below two points or without
// spread in either.
fn correlation_pearson(x: []const f64, y: []const f64) -> (f64, bool) {
    let n = x.len
    if n < 2usize || y.len != n { ret (0.0f64, false) }
    let mean_x = sum_plain(x) / f64(n)
    let mean_y = sum_plain(y) / f64(n)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n {
        let dx = x[i] - mean_x
        let dy = y[i] - mean_y
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
        i += 1usize
    }
    if sxx == 0.0f64 || syy == 0.0f64 { ret (0.0f64, false) }
    ret (sxy / math.sqrt[f64](sxx * syy), true)
}

fn compare_by_value(k: *RankKey, a: usize, b: usize) -> i32 {
    if k.values[a] < k.values[b] { ret 0i32 - 1i32 }
    if k.values[a] > k.values[b] { ret 1i32 }
    ret 0i32
}

fn compare_floats(k: *RankKey, a: f64, b: f64) -> i32 {
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// One-based ranks with ties averaged (`scipy.stats.rankdata`); `order` is
// scratch for the sort.
fn rank(values: []const f64, out: []f64, order: []usize) -> err {
    let n = values.len
    if out.len < n || order.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    var k = RankKey { values: values }
    sort.in_place_by[usize, RankKey](order[..n], &k, compare_by_value)
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && values[order[j + 1usize]] == values[order[i]] { j += 1usize }
        let average = (f64(i) + f64(j)) / 2.0f64 + 1.0f64
        var m = i
        while m <= j {
            out[order[m]] = average
            m += 1usize
        }
        i = j + 1usize
    }
    ret ok
}

// Spearman's rho: Pearson's r over average ranks. `scratch` holds `2 * x.len`
// floats and `order` `x.len` indices.
fn correlation_spearman(x: []const f64, y: []const f64, scratch: []f64, order: []usize) -> (f64, err) {
    let n = x.len
    if n < 2usize || y.len != n { ret (0.0f64, Invalid) }
    if scratch.len < 2usize * n { ret (0.0f64, TooSmall) }
    let e1 = rank(x, scratch[..n], order)
    if e1 != ok { ret (0.0f64, e1) }
    let e2 = rank(y, scratch[n..2usize * n], order)
    if e2 != ok { ret (0.0f64, e2) }
    let (rho, has_rho) = correlation_pearson(scratch[..n], scratch[n..2usize * n])
    if !has_rho { ret (0.0f64, Invalid) }
    ret (rho, ok)
}

// Kendall's tau-b with tie corrections (`scipy.stats.kendalltau`); `false` when
// either sample is constant.
// ponytail: O(n^2) pair walk; Knight's merge-sort inversion count is O(n log n).
fn correlation_kendall(x: []const f64, y: []const f64) -> (f64, bool) {
    let n = x.len
    if n < 2usize || y.len != n { ret (0.0f64, false) }
    var concordant = 0.0f64
    var discordant = 0.0f64
    var tied_x = 0.0f64
    var tied_y = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let dx = x[i] - x[j]
            let dy = y[i] - y[j]
            if dx == 0.0f64 { tied_x += 1.0f64 }
            if dy == 0.0f64 { tied_y += 1.0f64 }
            if dx != 0.0f64 && dy != 0.0f64 {
                if (dx > 0.0f64) == (dy > 0.0f64) { concordant += 1.0f64 } else { discordant += 1.0f64 }
            }
            j += 1usize
        }
        i += 1usize
    }
    let pairs = f64(n) * f64(n - 1usize) / 2.0f64
    let denominator = (pairs - tied_x) * (pairs - tied_y)
    if denominator <= 0.0f64 { ret (0.0f64, false) }
    ret ((concordant - discordant) / math.sqrt[f64](denominator), true)
}

// A rule-of-thumb Gaussian bandwidth scaled by the sample standard deviation:
// Scott's n^(-1/5) or Silverman's (3n/4)^(-1/5), the one-dimensional factors of
// `scipy.stats.gaussian_kde`. `false` below two values or without spread.
fn kde_bandwidth(values: []const f64, rule: Bandwidth) -> (f64, bool) {
    let n = values.len
    if n < 2usize { ret (0.0f64, false) }
    let (_, m2, _, _) = central_moments(values)
    if m2 == 0.0f64 { ret (0.0f64, false) }
    let sd = math.sqrt[f64](m2 * f64(n) / (f64(n) - 1.0f64))
    var base = f64(n)
    if rule == .Silverman { base = f64(n) * 0.75f64 }
    ret (sd * math.pow[f64](base, 0.0f64 - 0.2f64), true)
}

// The Gaussian kernel density estimate of `values` at each of `points`.
fn kde(values: []const f64, bandwidth: f64, points: []const f64, out: []f64) -> err {
    if values.len == 0usize || !(bandwidth > 0.0f64) { ret Invalid }
    if out.len < points.len { ret TooSmall }
    let scale = 1.0f64 / (f64(values.len) * bandwidth * 2.5066282746310002f64)
    var q = 0usize
    while q < points.len {
        var total = 0.0f64
        var i = 0usize
        while i < values.len {
            let u = (points[q] - values[i]) / bandwidth
            total += math.exp[f64](0.0f64 - 0.5f64 * u * u)
            i += 1usize
        }
        out[q] = total * scale
        q += 1usize
    }
    ret ok
}

// The bootstrap percentile interval of `statistic` at `confidence` (0 < c < 1)
// over `rounds` resamples drawn with `r`. `sample` holds `values.len` floats and
// `stats` `rounds` floats; `stats` is left sorted.
fn bootstrap[Ctx: type](r: *rand.Pcg64, values: []const f64, ctx: *Ctx, statistic: fn(*Ctx, []const f64) -> f64, rounds: usize, confidence: f64, sample: []f64, stats: []f64) -> (Interval, err) {
    let n = values.len
    var interval: Interval = zero
    if n == 0usize || rounds < 2usize || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (interval, Invalid) }
    if sample.len < n || stats.len < rounds { ret (interval, TooSmall) }
    var k = 0usize
    while k < rounds {
        var i = 0usize
        while i < n {
            sample[i] = values[usize(rand.pcg64_bounded(r, u64(n)))]
            i += 1usize
        }
        stats[k] = statistic(ctx, sample[..n])
        k += 1usize
    }
    var key = RankKey { values: values }
    sort.in_place_by[f64, RankKey](stats[..rounds], &key, compare_floats)
    let (low, _) = quantile(stats[..rounds], (1.0f64 - confidence) / 2.0f64, .R7)
    let (high, _) = quantile(stats[..rounds], (1.0f64 + confidence) / 2.0f64, .R7)
    interval.low = low
    interval.high = high
    ret (interval, ok)
}

// The leave-one-out jackknife of `statistic`: its bias and standard error.
// `scratch` holds `values.len - 1` floats.
fn jackknife[Ctx: type](values: []const f64, ctx: *Ctx, statistic: fn(*Ctx, []const f64) -> f64, scratch: []f64) -> (Jackknife, err) {
    let n = values.len
    var result: Jackknife = zero
    if n < 2usize { ret (result, Invalid) }
    if scratch.len + 1usize < n { ret (result, TooSmall) }
    result.estimate = statistic(ctx, values)
    var total = 0.0f64
    var total_squares = 0.0f64
    var leave = 0usize
    while leave < n {
        var i = 0usize
        var j = 0usize
        while i < n {
            if i != leave {
                scratch[j] = values[i]
                j += 1usize
            }
            i += 1usize
        }
        let theta = statistic(ctx, scratch[..n - 1usize])
        total += theta
        total_squares += theta * theta
        leave += 1usize
    }
    let nf = f64(n)
    let mean_theta = total / nf
    result.bias = (nf - 1.0f64) * (mean_theta - result.estimate)
    var spread = total_squares / nf - mean_theta * mean_theta
    if spread < 0.0f64 { spread = 0.0f64 }
    result.standard_error = math.sqrt[f64]((nf - 1.0f64) * spread)
    ret (result, ok)
}

// The Wilson score interval for `successes` of `trials` at `confidence`.
fn interval_wilson(successes: u64, trials: u64, confidence: f64) -> (Interval, err) {
    var interval: Interval = zero
    if trials == 0u64 || successes > trials || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (interval, Invalid) }
    let z = special.normal_quantile((1.0f64 + confidence) / 2.0f64)
    let n = f64(trials)
    let p = f64(successes) / n
    let z2 = z * z
    let centre = (p + z2 / (2.0f64 * n)) / (1.0f64 + z2 / n)
    let half = z * math.sqrt[f64](p * (1.0f64 - p) / n + z2 / (4.0f64 * n * n)) / (1.0f64 + z2 / n)
    interval.low = centre - half
    interval.high = centre + half
    ret (interval, ok)
}

// The beta distribution quantile by bisection on the regularised incomplete beta.
fn beta_quantile(p: f64, a: f64, b: f64) -> f64 {
    if p <= 0.0f64 { ret 0.0f64 }
    if p >= 1.0f64 { ret 1.0f64 }
    var lo = 0.0f64
    var hi = 1.0f64
    var i = 0usize
    while i < 200usize && hi - lo > 1.0e-16f64 {
        let mid = (lo + hi) / 2.0f64
        if special.beta_i(a, b, mid) < p { lo = mid } else { hi = mid }
        i += 1usize
    }
    ret (lo + hi) / 2.0f64
}

// The Clopper-Pearson exact interval for `successes` of `trials` at `confidence`.
fn interval_clopper_pearson(successes: u64, trials: u64, confidence: f64) -> (Interval, err) {
    var interval: Interval = zero
    if trials == 0u64 || successes > trials || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (interval, Invalid) }
    let tail = (1.0f64 - confidence) / 2.0f64
    let k = f64(successes)
    let n = f64(trials)
    if successes > 0u64 { interval.low = beta_quantile(tail, k, n - k + 1.0f64) }
    interval.high = 1.0f64
    if successes < trials { interval.high = beta_quantile(1.0f64 - tail, k + 1.0f64, n - k) }
    ret (interval, ok)
}

// Historical value at risk: the `level`-quantile (R-7) of ascending losses.
fn value_at_risk(sorted: []const f64, level: f64) -> (f64, bool) {
    let (v, has_v) = quantile(sorted, level, .R7)
    ret (v, has_v)
}

// Expected shortfall (CVaR): the mean of the largest `n - floor(level * n)`
// ascending losses; `false` when that tail is empty.
fn expected_shortfall(sorted: []const f64, level: f64) -> (f64, bool) {
    let n = sorted.len
    if n == 0usize || !(level >= 0.0f64 && level < 1.0f64) { ret (0.0f64, false) }
    let first = usize(math.floor[f64](level * f64(n)))
    if first >= n { ret (0.0f64, false) }
    ret (sum_plain(sorted[first..]) / f64(n - first), true)
}

// Method of moments: mean and population variance matched to the distribution's.
fn fit_moments(values: []const f64, distribution: Distribution) -> (Fit, err) {
    var fit: Fit = zero
    if values.len < 2usize { ret (fit, Invalid) }
    let (mu, m2, _, _) = central_moments(values)
    if distribution == .Normal {
        fit.a = mu
        fit.b = math.sqrt[f64](m2)
        ret (fit, ok)
    }
    if distribution == .Exponential {
        if mu <= 0.0f64 { ret (fit, Invalid) }
        fit.a = 1.0f64 / mu
        ret (fit, ok)
    }
    if m2 == 0.0f64 { ret (fit, Invalid) }
    if distribution == .Gamma {
        if mu <= 0.0f64 { ret (fit, Invalid) }
        fit.a = mu * mu / m2
        fit.b = m2 / mu
        ret (fit, ok)
    }
    if mu <= 0.0f64 || mu >= 1.0f64 { ret (fit, Invalid) }
    let common = mu * (1.0f64 - mu) / m2 - 1.0f64
    if common <= 0.0f64 { ret (fit, Invalid) }
    fit.a = mu * common
    fit.b = (1.0f64 - mu) * common
    ret (fit, ok)
}

// psi(x) for x > 0: the recurrence up to 10, then the asymptotic series.
fn digamma(x: f64) -> f64 {
    if !(x > 0.0f64) { ret special.nan() }
    var result = 0.0f64
    var t = x
    while t < 10.0f64 {
        result -= 1.0f64 / t
        t += 1.0f64
    }
    let r = 1.0f64 / (t * t)
    result += math.log[f64](t) - 0.5f64 / t
    result -= r * (1.0f64 / 12.0f64 - r * (1.0f64 / 120.0f64 - r * (1.0f64 / 252.0f64 - r * (1.0f64 / 240.0f64 - r * (1.0f64 / 132.0f64 - r * 691.0f64 / 32760.0f64)))))
    ret result
}

// psi'(x) for x > 0, by the same recurrence and series.
fn trigamma(x: f64) -> f64 {
    if !(x > 0.0f64) { ret special.nan() }
    var result = 0.0f64
    var t = x
    while t < 10.0f64 {
        result += 1.0f64 / (t * t)
        t += 1.0f64
    }
    let r = 1.0f64 / (t * t)
    result += 1.0f64 / t + 0.5f64 * r
    result += r / t * (1.0f64 / 6.0f64 - r * (1.0f64 / 30.0f64 - r * (1.0f64 / 42.0f64 - r * (1.0f64 / 30.0f64 - r * (5.0f64 / 66.0f64 - r * 691.0f64 / 2730.0f64)))))
    ret result
}

// Maximum likelihood: closed forms for the normal and exponential, Newton on
// the digamma equation for the gamma shape, and a two-dimensional Newton from
// the moment estimate for the beta shapes.
fn fit_mle(values: []const f64, distribution: Distribution) -> (Fit, err) {
    let (start, e) = fit_moments(values, distribution)
    if e != ok || distribution == .Normal || distribution == .Exponential { ret (start, e) }
    var fit = start
    let n = f64(values.len)
    var log_sum = 0.0f64
    var log_complement = 0.0f64
    var i = 0usize
    while i < values.len {
        let x = values[i]
        if x <= 0.0f64 || (distribution == .Beta && x >= 1.0f64) { ret (start, Invalid) }
        log_sum += math.log[f64](x)
        if distribution == .Beta { log_complement += math.log[f64](1.0f64 - x) }
        i += 1usize
    }
    if distribution == .Gamma {
        let mu = sum_plain(values) / n
        let s = math.log[f64](mu) - log_sum / n
        if !(s > 0.0f64) { ret (start, Invalid) }
        var k = (3.0f64 - s + math.sqrt[f64]((s - 3.0f64) * (s - 3.0f64) + 24.0f64 * s)) / (12.0f64 * s)
        var round = 0usize
        while round < 100usize {
            let step = (math.log[f64](k) - digamma(k) - s) / (1.0f64 / k - trigamma(k))
            k -= step
            if k <= 0.0f64 { k = 1.0e-8f64 }
            round += 1usize
            if math.abs[f64](step) < 1.0e-13f64 * k { round = 100usize }
        }
        fit.a = k
        fit.b = mu / k
        ret (fit, ok)
    }
    let l1 = log_sum / n
    let l2 = log_complement / n
    var round = 0usize
    while round < 100usize {
        let both = digamma(fit.a + fit.b)
        let g1 = both - digamma(fit.a) + l1
        let g2 = both - digamma(fit.b) + l2
        let h12 = trigamma(fit.a + fit.b)
        let h11 = h12 - trigamma(fit.a)
        let h22 = h12 - trigamma(fit.b)
        let determinant = h11 * h22 - h12 * h12
        if determinant == 0.0f64 { ret (start, Invalid) }
        var step_a = (h22 * g1 - h12 * g2) / determinant
        var step_b = (h11 * g2 - h12 * g1) / determinant
        while fit.a - step_a <= 0.0f64 || fit.b - step_b <= 0.0f64 {
            step_a = step_a / 2.0f64
            step_b = step_b / 2.0f64
        }
        fit.a -= step_a
        fit.b -= step_b
        round += 1usize
        if math.abs[f64](step_a) < 1.0e-13f64 * fit.a && math.abs[f64](step_b) < 1.0e-13f64 * fit.b { round = 100usize }
    }
    ret (fit, ok)
}
