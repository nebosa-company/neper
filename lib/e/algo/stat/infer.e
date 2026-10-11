// Elementary inferential completions over `f64` samples: known-variance and
// proportion z-tests, the chi-squared test of independence on a contingency
// table (with Yates' correction and Cramer's V), Levene (mean, median and
// trimmed centres) and Bartlett homogeneity-of-variance tests, Tukey's HSD
// post-hoc comparison with the studentized range distribution it rests on,
// power and sample-size analysis for the t-test (through the noncentral t) and
// the z-test, and the mode and weighted descriptives (mean, variance, quantile).
//
// Results are a statistic, a two-sided p-value and the degrees of freedom the
// reference distribution used. Storage is the caller's: each declaration says
// how many floats or indices it wants. The studentized range is evaluated by
// 16-point Gauss-Legendre quadrature over the range of `k` normals (inner) and
// the scale of the variance estimate (outer), the construction of Copenhaver and
// Holland that R's `ptukey` follows; the noncentral t is Lenth's AS 243 series.

use e.algo.stat.test as hypothesis
use e.math
use e.math.special

type Outcome = struct { statistic: f64, p_value: f64, df: f64 }
type Center = enum u8 { Mean, Median, Trimmed }
type Design = enum u8 { OneSample, Paired, TwoSample }
type Pair = struct { first: usize, second: usize, mean_diff: f64, statistic: f64, p_value: f64, ci_low: f64, ci_high: f64 }
error TooSmall
error Invalid

fn two_sided_normal(z: f64) -> f64 {
    ret special.erfc(math.abs[f64](z) / 1.4142135623730951f64)
}

fn chi_squared_sf(x: f64, df: f64) -> f64 {
    if x <= 0.0f64 { ret 1.0f64 }
    ret special.gamma_q(df / 2.0f64, x / 2.0f64)
}

fn sample_mean(values: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < values.len {
        sum += values[i]
        i += 1usize
    }
    ret sum / f64(values.len)
}

// Shell sort in place, for the places that need more than a handful of floats
// ordered.
fn sort_ascending(values: []f64) {
    var gap = values.len / 2usize
    while gap > 0usize {
        var i = gap
        while i < values.len {
            let held = values[i]
            var j = i
            while j >= gap && values[j - gap] > held {
                values[j] = values[j - gap]
                j -= gap
            }
            values[j] = held
            i += 1usize
        }
        gap = gap / 2usize
    }
}

// z-test of a sample mean against `mu` with the population standard deviation
// `sigma` known.
fn z_test(values: []const f64, mu: f64, sigma: f64) -> (Outcome, err) {
    if values.len < 1usize || !(sigma > 0.0f64) { ret (zero, Invalid) }
    let z = (sample_mean(values) - mu) / (sigma / math.sqrt[f64](f64(values.len)))
    ret (Outcome { statistic: z, p_value: two_sided_normal(z), df: 0.0f64 }, ok)
}

// z-test of the difference of two means with known standard deviations.
fn z_test_two(a: []const f64, b: []const f64, sigma_a: f64, sigma_b: f64) -> (Outcome, err) {
    if a.len < 1usize || b.len < 1usize || !(sigma_a > 0.0f64) || !(sigma_b > 0.0f64) { ret (zero, Invalid) }
    let se = math.sqrt[f64](sigma_a * sigma_a / f64(a.len) + sigma_b * sigma_b / f64(b.len))
    let z = (sample_mean(a) - sample_mean(b)) / se
    ret (Outcome { statistic: z, p_value: two_sided_normal(z), df: 0.0f64 }, ok)
}

// One-sample proportion z-test; the variance is the null's, `p0 (1 - p0) / n`.
fn proportion_z(successes: u64, n: u64, p0: f64) -> (Outcome, err) {
    if n == 0u64 || successes > n || !(p0 > 0.0f64 && p0 < 1.0f64) { ret (zero, Invalid) }
    let nf = f64(n)
    let z = (f64(successes) / nf - p0) / math.sqrt[f64](p0 * (1.0f64 - p0) / nf)
    ret (Outcome { statistic: z, p_value: two_sided_normal(z), df: 0.0f64 }, ok)
}

// Two-sample proportion z-test with the pooled proportion under the null.
fn proportion_z_two(x1: u64, n1: u64, x2: u64, n2: u64) -> (Outcome, err) {
    if n1 == 0u64 || n2 == 0u64 || x1 > n1 || x2 > n2 { ret (zero, Invalid) }
    let a = f64(n1)
    let b = f64(n2)
    let pooled = (f64(x1) + f64(x2)) / (a + b)
    if pooled <= 0.0f64 || pooled >= 1.0f64 { ret (zero, Invalid) }
    let se = math.sqrt[f64](pooled * (1.0f64 - pooled) * (1.0f64 / a + 1.0f64 / b))
    let z = (f64(x1) / a - f64(x2) / b) / se
    ret (Outcome { statistic: z, p_value: two_sided_normal(z), df: 0.0f64 }, ok)
}

// Pearson's chi-squared test of independence on a row-major `rows x cols` table
// of counts. `expected` (rows * cols floats) receives the expected counts.
// Yates' continuity correction applies only to one degree of freedom, as in
// `scipy.stats.chi2_contingency`.
fn chi_squared_independence(table: []const f64, rows: usize, cols: usize, yates: bool, expected: []f64) -> (Outcome, err) {
    if rows < 2usize || cols < 2usize { ret (zero, Invalid) }
    let cells = rows * cols
    if table.len < cells || expected.len < cells { ret (zero, TooSmall) }
    var total = 0.0f64
    var r = 0usize
    while r < rows {
        var c = 0usize
        while c < cols {
            if table[r * cols + c] < 0.0f64 { ret (zero, Invalid) }
            total += table[r * cols + c]
            c += 1usize
        }
        r += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    var row_sum: [64]f64 = zero
    var col_sum: [64]f64 = zero
    if rows > 64usize || cols > 64usize { ret (zero, TooSmall) }
    r = 0usize
    while r < rows {
        var c = 0usize
        while c < cols {
            row_sum[r] += table[r * cols + c]
            col_sum[c] += table[r * cols + c]
            c += 1usize
        }
        r += 1usize
    }
    let df = f64((rows - 1usize) * (cols - 1usize))
    let correct = yates && df == 1.0f64
    var statistic = 0.0f64
    r = 0usize
    while r < rows {
        var c = 0usize
        while c < cols {
            let e = row_sum[r] * col_sum[c] / total
            expected[r * cols + c] = e
            if e <= 0.0f64 { ret (zero, Invalid) }
            var seen = table[r * cols + c]
            if correct {
                let diff = e - seen
                var magnitude = math.abs[f64](diff)
                if magnitude > 0.5f64 { magnitude = 0.5f64 }
                if diff > 0.0f64 { seen += magnitude } else if diff < 0.0f64 { seen -= magnitude }
            }
            statistic += (seen - e) * (seen - e) / e
            c += 1usize
        }
        r += 1usize
    }
    ret (Outcome { statistic: statistic, p_value: chi_squared_sf(statistic, df), df: df }, ok)
}

// Cramer's V (no bias correction) from an uncorrected chi-squared statistic.
fn cramers_v(statistic: f64, total: f64, rows: usize, cols: usize) -> f64 {
    var k = rows
    if cols < k { k = cols }
    if k < 2usize || total <= 0.0f64 { ret 0.0f64 }
    ret math.sqrt[f64](statistic / (total * f64(k - 1usize)))
}

fn centre_of(group: []const f64, kind: Center, scratch: []f64) -> f64 {
    let n = group.len
    var i = 0usize
    while i < n {
        scratch[i] = group[i]
        i += 1usize
    }
    if kind == .Mean { ret sample_mean(group) }
    sort_ascending(scratch[..n])
    if kind == .Median {
        if n % 2usize == 1usize { ret scratch[n / 2usize] }
        ret 0.5f64 * (scratch[n / 2usize - 1usize] + scratch[n / 2usize])
    }
    // Trimmed: five percent from each end, as scipy's trim_mean does.
    let cut = usize(0.05f64 * f64(n))
    ret sample_mean(scratch[cut..n - cut])
}

// Levene's test of equal variances over groups laid out consecutively in
// `values`: one-way ANOVA on the absolute deviations from each group's centre
// (`Median` is the Brown-Forsythe variant). `scratch` wants twice the total.
fn levene(values: []const f64, sizes: []const usize, kind: Center, scratch: []f64) -> (Outcome, err) {
    if sizes.len < 2usize { ret (zero, Invalid) }
    var total = 0usize
    var g = 0usize
    while g < sizes.len {
        if sizes[g] < 2usize { ret (zero, Invalid) }
        total += sizes[g]
        g += 1usize
    }
    if values.len < total || scratch.len < 2usize * total { ret (zero, TooSmall) }
    var at_group = 0usize
    g = 0usize
    while g < sizes.len {
        let group = values[at_group..at_group + sizes[g]]
        let centre = centre_of(group, kind, scratch[total..2usize * total])
        var i = 0usize
        while i < group.len {
            scratch[at_group + i] = math.abs[f64](group[i] - centre)
            i += 1usize
        }
        at_group += sizes[g]
        g += 1usize
    }
    let (r, e) = hypothesis.anova(scratch[..total], sizes)
    if e != ok { ret (zero, Invalid) }
    ret (Outcome { statistic: r.statistic, p_value: r.p_value, df: f64(total - sizes.len) }, ok)
}

// Bartlett's test of equal variances for normal samples.
fn bartlett(values: []const f64, sizes: []const usize) -> (Outcome, err) {
    if sizes.len < 2usize { ret (zero, Invalid) }
    var total = 0usize
    var g = 0usize
    while g < sizes.len {
        if sizes[g] < 2usize { ret (zero, Invalid) }
        total += sizes[g]
        g += 1usize
    }
    if values.len < total { ret (zero, TooSmall) }
    let k = f64(sizes.len)
    let big_n = f64(total)
    var pooled = 0.0f64
    var log_sum = 0.0f64
    var inverse = 0.0f64
    var at_group = 0usize
    g = 0usize
    while g < sizes.len {
        let group = values[at_group..at_group + sizes[g]]
        let v = hypothesis.sample_variance(group)
        if !(v > 0.0f64) { ret (zero, Invalid) }
        let d = f64(sizes[g]) - 1.0f64
        pooled += d * v
        log_sum += d * math.log[f64](v)
        inverse += 1.0f64 / d
        at_group += sizes[g]
        g += 1usize
    }
    pooled = pooled / (big_n - k)
    let numerator = (big_n - k) * math.log[f64](pooled) - log_sum
    let denominator = 1.0f64 + (inverse - 1.0f64 / (big_n - k)) / (3.0f64 * (k - 1.0f64))
    let statistic = numerator / denominator
    ret (Outcome { statistic: statistic, p_value: chi_squared_sf(statistic, k - 1.0f64), df: k - 1.0f64 }, ok)
}

// The sixteen Gauss-Legendre nodes and weights on [-1, 1].
fn gauss_legendre16(x: []f64, w: []f64) {
    var half_x: [8]f64 = zero
    var half_w: [8]f64 = zero
    half_x[0usize] = 0.09501250983763744f64
    half_w[0usize] = 0.18945061045506864f64
    half_x[1usize] = 0.2816035507792589f64
    half_w[1usize] = 0.18260341504492364f64
    half_x[2usize] = 0.45801677765722737f64
    half_w[2usize] = 0.16915651939500265f64
    half_x[3usize] = 0.6178762444026438f64
    half_w[3usize] = 0.1495959888165767f64
    half_x[4usize] = 0.755404408355003f64
    half_w[4usize] = 0.12462897125553407f64
    half_x[5usize] = 0.8656312023878318f64
    half_w[5usize] = 0.0951585116824926f64
    half_x[6usize] = 0.9445750230732326f64
    half_w[6usize] = 0.062253523938647456f64
    half_x[7usize] = 0.9894009349916499f64
    half_w[7usize] = 0.027152459411754176f64
    var i = 0usize
    while i < 8usize {
        x[i] = 0.0f64 - half_x[7usize - i]
        w[i] = half_w[7usize - i]
        x[8usize + i] = half_x[i]
        w[8usize + i] = half_w[i]
        i += 1usize
    }
}

// The range of `k` independent standard normals falls below `w`:
// P(range <= w) = k * integral of phi(z) (Phi(z) - Phi(z - w))^(k - 1) dz.
fn range_cdf(w: f64, k: f64, nodes: []const f64, weights: []const f64) -> f64 {
    if w <= 0.0f64 { ret 0.0f64 }
    let pieces = 6usize
    let lo = 0.0f64 - 9.0f64
    let width = 18.0f64 / f64(pieces)
    var sum = 0.0f64
    var p = 0usize
    while p < pieces {
        let a = lo + f64(p) * width
        let centre = a + 0.5f64 * width
        var i = 0usize
        while i < 16usize {
            let z = centre + 0.5f64 * width * nodes[i]
            let gap = special.normal_cdf(z) - special.normal_cdf(z - w)
            if gap > 0.0f64 {
                let density = 0.3989422804014327f64 * math.exp[f64](0.0f64 - 0.5f64 * z * z)
                sum += weights[i] * density * math.exp[f64]((k - 1.0f64) * math.log[f64](gap))
            }
            i += 1usize
        }
        p += 1usize
    }
    var result = k * sum * 0.5f64 * width
    if result > 1.0f64 { result = 1.0f64 }
    ret result
}

// The studentized range distribution function: the range of `k` normal means
// over an independent standard-deviation estimate with `df` degrees of freedom.
fn studentized_range_cdf(q: f64, k: f64, df: f64) -> f64 {
    if k < 2.0f64 || df < 1.0f64 || q != q { ret special.nan() }
    if q <= 0.0f64 { ret 0.0f64 }
    var nodes: [16]f64 = zero
    var weights: [16]f64 = zero
    gauss_legendre16(nodes[..], weights[..])
    if df > 20000.0f64 { ret range_cdf(q, k, nodes[..], weights[..]) }
    let spread = 12.0f64 / math.sqrt[f64](2.0f64 * df)
    var lower = 1.0f64 - spread
    if lower < 0.0f64 { lower = 0.0f64 }
    let upper = 1.0f64 + spread + 8.0f64 / df + 6.0f64 / math.sqrt[f64](df)
    let log_norm = 0.6931471805599453f64 + 0.5f64 * df * math.log[f64](0.5f64 * df) - special.lgamma(0.5f64 * df)
    let pieces = 12usize
    let width = (upper - lower) / f64(pieces)
    var sum = 0.0f64
    var p = 0usize
    while p < pieces {
        let centre = lower + (f64(p) + 0.5f64) * width
        var i = 0usize
        while i < 16usize {
            let s = centre + 0.5f64 * width * nodes[i]
            if s > 0.0f64 {
                let density = math.exp[f64](log_norm + (df - 1.0f64) * math.log[f64](s) - 0.5f64 * df * s * s)
                sum += weights[i] * density * range_cdf(q * s, k, nodes[..], weights[..])
            }
            i += 1usize
        }
        p += 1usize
    }
    var result = sum * 0.5f64 * width
    if result > 1.0f64 { result = 1.0f64 }
    ret result
}

// The studentized range quantile, by bisection on the distribution function.
fn studentized_range_quantile(p: f64, k: f64, df: f64) -> f64 {
    if !(p > 0.0f64 && p < 1.0f64) || k < 2.0f64 || df < 1.0f64 { ret special.nan() }
    var hi = 4.0f64
    while studentized_range_cdf(hi, k, df) < p && hi < 1000.0f64 { hi *= 2.0f64 }
    var lo = 0.0f64
    // Illinois regula falsi on F(x) - p, bracketed by [lo, hi].
    var f_lo = 0.0f64 - p
    var f_hi = studentized_range_cdf(hi, k, df) - p
    var side = 0i32
    var x = hi
    var i = 0usize
    while i < 60usize {
        x = (lo * f_hi - hi * f_lo) / (f_hi - f_lo)
        let fx = studentized_range_cdf(x, k, df) - p
        if math.abs[f64](fx) < 1.0e-12f64 || hi - lo < 1.0e-12f64 { break }
        if fx > 0.0f64 {
            hi = x
            f_hi = fx
            if side == 1i32 { f_lo = f_lo * 0.5f64 }
            side = 1i32
        } else {
            lo = x
            f_lo = fx
            if side == 0i32 - 1i32 { f_hi = f_hi * 0.5f64 }
            side = 0i32 - 1i32
        }
        i += 1usize
    }
    ret x
}

// Tukey's honestly-significant-difference test over groups laid out
// consecutively in `values`. One `Pair` per `first < second` is written to
// `out` in row order and the count is answered; `out` wants k (k - 1) / 2.
// `statistic` is the signed studentized range of mean_first - mean_second and
// the interval is `confidence` wide, as `scipy.stats.tukey_hsd` reports.
fn tukey_hsd(values: []const f64, sizes: []const usize, confidence: f64, out: []Pair) -> (usize, err) {
    if sizes.len < 2usize || !(confidence > 0.0f64 && confidence < 1.0f64) { ret (0usize, Invalid) }
    var total = 0usize
    var g = 0usize
    while g < sizes.len {
        if sizes[g] < 1usize { ret (0usize, Invalid) }
        total += sizes[g]
        g += 1usize
    }
    if values.len < total || total <= sizes.len { ret (0usize, TooSmall) }
    let k = sizes.len
    let pairs = k * (k - 1usize) / 2usize
    if out.len < pairs { ret (0usize, TooSmall) }
    var within = 0.0f64
    var at_group = 0usize
    g = 0usize
    while g < k {
        let group = values[at_group..at_group + sizes[g]]
        let m = sample_mean(group)
        var i = 0usize
        while i < group.len {
            within += (group[i] - m) * (group[i] - m)
            i += 1usize
        }
        at_group += sizes[g]
        g += 1usize
    }
    let df = f64(total - k)
    let mse = within / df
    if !(mse > 0.0f64) { ret (0usize, Invalid) }
    let critical = studentized_range_quantile(confidence, f64(k), df)
    var offsets: [64]usize = zero
    if k > 64usize { ret (0usize, TooSmall) }
    var run = 0usize
    g = 0usize
    while g < k {
        offsets[g] = run
        run += sizes[g]
        g += 1usize
    }
    var count = 0usize
    var i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            let diff = sample_mean(values[offsets[i]..offsets[i] + sizes[i]]) - sample_mean(values[offsets[j]..offsets[j] + sizes[j]])
            let se = math.sqrt[f64](0.5f64 * mse * (1.0f64 / f64(sizes[i]) + 1.0f64 / f64(sizes[j])))
            let q = diff / se
            var p = 1.0f64 - studentized_range_cdf(math.abs[f64](q), f64(k), df)
            if p < 0.0f64 { p = 0.0f64 }
            out[count] = Pair { first: i, second: j, mean_diff: diff, statistic: q, p_value: p, ci_low: diff - critical * se, ci_high: diff + critical * se }
            count += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

// Student's t quantile by bisection on `special.t_cdf`, for 0 < p < 1.
fn t_quantile(p: f64, df: f64) -> f64 {
    if !(p > 0.0f64 && p < 1.0f64) || df <= 0.0f64 { ret special.nan() }
    if p == 0.5f64 { ret 0.0f64 }
    var hi = 1.0f64
    while special.t_cdf(hi, df) < p && hi < 1.0e12f64 { hi *= 2.0f64 }
    var lo = 0.0f64 - hi
    while special.t_cdf(lo, df) > p && lo > 0.0f64 - 1.0e12f64 { lo *= 2.0f64 }
    var i = 0usize
    while i < 200usize {
        let mid = 0.5f64 * (lo + hi)
        if special.t_cdf(mid, df) < p { lo = mid } else { hi = mid }
        i += 1usize
    }
    ret 0.5f64 * (lo + hi)
}

// The noncentral t distribution function (Lenth's AS 243).
fn noncentral_t_cdf(t: f64, df: f64, ncp: f64) -> f64 {
    if df <= 0.0f64 { ret special.nan() }
    if ncp == 0.0f64 { ret special.t_cdf(t, df) }
    var negative = false
    var tt = t
    var del = ncp
    if t < 0.0f64 {
        negative = true
        tt = 0.0f64 - t
        del = 0.0f64 - ncp
    }
    var tnc = 0.0f64
    if df > 400000.0f64 || del * del > 1000.0f64 {
        let s = 1.0f64 / (4.0f64 * df)
        tnc = special.normal_cdf((tt * (1.0f64 - s) - del) / math.sqrt[f64](1.0f64 + tt * tt * 2.0f64 * s))
    } else {
        let x = tt * tt / (tt * tt + df)
        tnc = 0.0f64
        if x > 0.0f64 {
            let lambda = del * del
            let p = 0.5f64 * math.exp[f64](0.0f64 - 0.5f64 * lambda)
            let q = 0.7978845608028654f64 * p * del
            var s = 0.5f64 - p
            if s < 1.0e-7f64 { s = 0.0f64 - 0.5f64 * (math.exp[f64](0.0f64 - 0.5f64 * lambda) - 1.0f64) }
            var a = 0.5f64
            let b = 0.5f64 * df
            let rxb = math.exp[f64](b * math.log[f64](1.0f64 - x))
            let albeta = 0.5723649429247001f64 + special.lgamma(b) - special.lgamma(0.5f64 + b)
            var xodd = special.beta_i(a, b, x)
            var godd = 2.0f64 * rxb * math.exp[f64](a * math.log[f64](x) - albeta)
            let tnc0 = b * x
            var xeven = 1.0f64 - rxb
            if tnc0 < 2.220446049250313e-16f64 { xeven = tnc0 }
            var geven = tnc0 * rxb
            tnc = p * xodd + q * xeven
            var it = 1usize
            var qterm = q
            var pterm = p
            while it < 2000usize {
                a += 1.0f64
                xodd -= godd
                xeven -= geven
                godd *= x * (a + b - 1.0f64) / a
                geven *= x * (a + b - 0.5f64) / (a + 0.5f64)
                pterm *= lambda / f64(2usize * it)
                qterm *= lambda / f64(2usize * it + 1usize)
                tnc += pterm * xodd + qterm * xeven
                s -= pterm
                if s < 0.0f64 - 1.0e-10f64 { break }
                if s >= 0.0f64 {
                    let bound = 2.0f64 * s * (xodd - godd)
                    if math.abs[f64](bound) < 1.0e-12f64 { break }
                }
                it += 1usize
            }
        }
        tnc += special.normal_cdf(0.0f64 - del)
    }
    if tnc > 1.0f64 { tnc = 1.0f64 }
    if negative { ret 1.0f64 - tnc }
    ret tnc
}

// Power of the t-test for a standardized effect (Cohen's d) with `n` pairs,
// observations or observations per group. `Paired` is the one-sample test on
// the differences, so the effect is the mean difference over its sd.
fn power_t(design: Design, n: usize, effect: f64, alpha: f64, two_sided: bool) -> f64 {
    if n < 2usize || !(alpha > 0.0f64 && alpha < 1.0f64) { ret special.nan() }
    var df = f64(n) - 1.0f64
    var ncp = effect * math.sqrt[f64](f64(n))
    if design == .TwoSample {
        df = 2.0f64 * f64(n) - 2.0f64
        ncp = effect * math.sqrt[f64](f64(n) / 2.0f64)
    }
    if two_sided {
        let crit = t_quantile(1.0f64 - alpha / 2.0f64, df)
        ret 1.0f64 - noncentral_t_cdf(crit, df, ncp) + noncentral_t_cdf(0.0f64 - crit, df, ncp)
    }
    let crit = t_quantile(1.0f64 - alpha, df)
    ret 1.0f64 - noncentral_t_cdf(crit, df, ncp)
}

// Power of the z-test with known sigma for the same effect convention.
fn power_z(design: Design, n: usize, effect: f64, alpha: f64, two_sided: bool) -> f64 {
    if n < 1usize || !(alpha > 0.0f64 && alpha < 1.0f64) { ret special.nan() }
    var shift = effect * math.sqrt[f64](f64(n))
    if design == .TwoSample { shift = effect * math.sqrt[f64](f64(n) / 2.0f64) }
    if two_sided {
        let crit = special.normal_quantile(1.0f64 - alpha / 2.0f64)
        ret 1.0f64 - special.normal_cdf(crit - shift) + special.normal_cdf(0.0f64 - crit - shift)
    }
    let crit = special.normal_quantile(1.0f64 - alpha)
    ret 1.0f64 - special.normal_cdf(crit - shift)
}

// Smallest `n` whose t-test power reaches `power`; `Invalid` when the effect is
// zero or the answer passes ten million.
fn sample_size_t(design: Design, effect: f64, alpha: f64, power: f64, two_sided: bool) -> (usize, err) {
    if effect == 0.0f64 || !(power > 0.0f64 && power < 1.0f64) || !(alpha > 0.0f64 && alpha < 1.0f64) { ret (0usize, Invalid) }
    var lo = 2usize
    var hi = 4usize
    while power_t(design, hi, effect, alpha, two_sided) < power {
        lo = hi
        hi = hi * 2usize
        if hi > 10000000usize { ret (0usize, Invalid) }
    }
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if power_t(design, mid, effect, alpha, two_sided) < power { lo = mid + 1usize } else { hi = mid }
    }
    ret (lo, ok)
}

// Smallest `n` whose z-test power reaches `power`.
fn sample_size_z(design: Design, effect: f64, alpha: f64, power: f64, two_sided: bool) -> (usize, err) {
    if effect == 0.0f64 || !(power > 0.0f64 && power < 1.0f64) || !(alpha > 0.0f64 && alpha < 1.0f64) { ret (0usize, Invalid) }
    var lo = 1usize
    var hi = 2usize
    while power_z(design, hi, effect, alpha, two_sided) < power {
        lo = hi
        hi = hi * 2usize
        if hi > 100000000usize { ret (0usize, Invalid) }
    }
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if power_z(design, mid, effect, alpha, two_sided) < power { lo = mid + 1usize } else { hi = mid }
    }
    ret (lo, ok)
}

// The most frequent value (the smallest of any tie) and its count. `scratch`
// wants `values.len` floats and is left sorted.
fn mode(values: []const f64, scratch: []f64) -> (f64, usize, err) {
    if values.len == 0usize { ret (0.0f64, 0usize, Invalid) }
    if scratch.len < values.len { ret (0.0f64, 0usize, TooSmall) }
    var i = 0usize
    while i < values.len {
        scratch[i] = values[i]
        i += 1usize
    }
    sort_ascending(scratch[..values.len])
    var best = scratch[0usize]
    var best_count = 0usize
    var run = 0usize
    i = 0usize
    while i < values.len {
        if i > 0usize && scratch[i] == scratch[i - 1usize] { run += 1usize } else { run = 1usize }
        if run > best_count {
            best_count = run
            best = scratch[i]
        }
        i += 1usize
    }
    ret (best, best_count, ok)
}

// Weighted mean; weights must be non-negative with a positive sum.
fn weighted_mean(values: []const f64, weights: []const f64) -> (f64, err) {
    if values.len == 0usize || weights.len != values.len { ret (0.0f64, Invalid) }
    var sum_w = 0.0f64
    var sum = 0.0f64
    var i = 0usize
    while i < values.len {
        if weights[i] < 0.0f64 { ret (0.0f64, Invalid) }
        sum_w += weights[i]
        sum += weights[i] * values[i]
        i += 1usize
    }
    if !(sum_w > 0.0f64) { ret (0.0f64, Invalid) }
    ret (sum / sum_w, ok)
}

// Weighted variance with reliability weights (`numpy.cov(aweights=)`):
// unbiased divides by V1 - V2 / V1, biased by V1.
fn weighted_variance(values: []const f64, weights: []const f64, unbiased: bool) -> (f64, err) {
    let (m, e) = weighted_mean(values, weights)
    if e != ok { ret (0.0f64, Invalid) }
    var v1 = 0.0f64
    var v2 = 0.0f64
    var sum = 0.0f64
    var i = 0usize
    while i < values.len {
        v1 += weights[i]
        v2 += weights[i] * weights[i]
        sum += weights[i] * (values[i] - m) * (values[i] - m)
        i += 1usize
    }
    if !unbiased { ret (sum / v1, ok) }
    let denominator = v1 - v2 / v1
    if !(denominator > 0.0f64) { ret (0.0f64, Invalid) }
    ret (sum / denominator, ok)
}

// Weighted quantile as the inverted CDF: the smallest value whose cumulative
// weight fraction reaches `p` (`numpy.quantile(method="inverted_cdf",
// weights=)`). `order` wants `values.len` indices.
fn weighted_quantile(values: []const f64, weights: []const f64, p: f64, order: []usize) -> (f64, err) {
    let n = values.len
    if n == 0usize || weights.len != n || !(p >= 0.0f64 && p <= 1.0f64) { ret (0.0f64, Invalid) }
    if order.len < n { ret (0.0f64, TooSmall) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        if weights[i] < 0.0f64 { ret (0.0f64, Invalid) }
        total += weights[i]
        order[i] = i
        i += 1usize
    }
    if !(total > 0.0f64) { ret (0.0f64, Invalid) }
    var gap = n / 2usize
    while gap > 0usize {
        i = gap
        while i < n {
            let held = order[i]
            var j = i
            while j >= gap && values[order[j - gap]] > values[held] {
                order[j] = order[j - gap]
                j -= gap
            }
            order[j] = held
            i += 1usize
        }
        gap = gap / 2usize
    }
    let goal = p * total
    var running = 0.0f64
    i = 0usize
    while i < n {
        running += weights[order[i]]
        if weights[order[i]] > 0.0f64 && running >= goal * (1.0f64 - 1.0e-12f64) { ret (values[order[i]], ok) }
        i += 1usize
    }
    ret (values[order[n - 1usize]], ok)
}
