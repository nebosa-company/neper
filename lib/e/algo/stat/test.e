// Hypothesis tests over `f64` samples: Student's and Welch's t, Mann-Whitney U,
// Wilcoxon signed-rank, chi-squared goodness of fit, Fisher's exact test on a
// 2x2 table, the two-sample Kolmogorov-Smirnov test, one-way ANOVA,
// Kruskal-Wallis, a permutation test of the mean difference, and the
// Bonferroni and Benjamini-Hochberg multiple-comparison corrections.
//
// Every test answers a `Result` of statistic and two-sided p-value computed with
// `e.math.special`'s distribution functions; the rank tests use the normal
// approximation with tie correction, which is what R and SciPy do above small
// samples. Scratch slices are the caller's and sized as each declaration says.

use e.algo.rand
use e.math
use e.math.special

type Result = struct { statistic: f64, p_value: f64 }
error TooSmall
error Invalid

fn mean(values: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < values.len {
        sum += values[i]
        i += 1usize
    }
    ret sum / f64(values.len)
}

fn sample_variance(values: []const f64) -> f64 {
    let m = mean(values)
    var sum = 0.0f64
    var i = 0usize
    while i < values.len {
        sum += (values[i] - m) * (values[i] - m)
        i += 1usize
    }
    ret sum / f64(values.len - 1usize)
}

fn two_sided_t(t: f64, df: f64) -> f64 {
    ret 2.0f64 * (1.0f64 - special.t_cdf(math.abs[f64](t), df))
}

fn two_sided_normal(z: f64) -> f64 {
    ret 2.0f64 * (1.0f64 - special.normal_cdf(math.abs[f64](z)))
}

// One-sample t-test of the mean against `mu`.
fn t_test(values: []const f64, mu: f64) -> (Result, err) {
    if values.len < 2usize { ret (zero, Invalid) }
    let n = f64(values.len)
    let s = math.sqrt[f64](sample_variance(values))
    if s == 0.0f64 { ret (zero, Invalid) }
    let t = (mean(values) - mu) / (s / math.sqrt[f64](n))
    ret (Result { statistic: t, p_value: two_sided_t(t, n - 1.0f64) }, ok)
}

// Two-sample t-test with pooled variance.
fn t_test_two(a: []const f64, b: []const f64) -> (Result, err) {
    if a.len < 2usize || b.len < 2usize { ret (zero, Invalid) }
    let na = f64(a.len)
    let nb = f64(b.len)
    let pooled = ((na - 1.0f64) * sample_variance(a) + (nb - 1.0f64) * sample_variance(b)) / (na + nb - 2.0f64)
    if pooled == 0.0f64 { ret (zero, Invalid) }
    let t = (mean(a) - mean(b)) / math.sqrt[f64](pooled * (1.0f64 / na + 1.0f64 / nb))
    ret (Result { statistic: t, p_value: two_sided_t(t, na + nb - 2.0f64) }, ok)
}

// Welch's t-test with the Welch-Satterthwaite degrees of freedom.
fn welch(a: []const f64, b: []const f64) -> (Result, err) {
    if a.len < 2usize || b.len < 2usize { ret (zero, Invalid) }
    let na = f64(a.len)
    let nb = f64(b.len)
    let va = sample_variance(a) / na
    let vb = sample_variance(b) / nb
    if va + vb == 0.0f64 { ret (zero, Invalid) }
    let t = (mean(a) - mean(b)) / math.sqrt[f64](va + vb)
    let df = (va + vb) * (va + vb) / (va * va / (na - 1.0f64) + vb * vb / (nb - 1.0f64))
    ret (Result { statistic: t, p_value: two_sided_t(t, df) }, ok)
}

// Average ranks of `values` written to `out`, using `order` as scratch for the
// sort; answers the tie correction term `sum(t^3 - t)`.
fn ranks(values: []const f64, out: []f64, order: []usize) -> (f64, err) {
    let n = values.len
    if out.len < n || order.len < n { ret (0.0f64, TooSmall) }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    // Insertion sort of the index array by value.
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && values[order[j]] < values[order[j - 1usize]] {
            let swap = order[j]
            order[j] = order[j - 1usize]
            order[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    var ties = 0.0f64
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && values[order[j + 1usize]] == values[order[i]] { j += 1usize }
        let average = (f64(i) + f64(j)) / 2.0f64 + 1.0f64
        var k = i
        while k <= j {
            out[order[k]] = average
            k += 1usize
        }
        let t = f64(j - i + 1usize)
        ties += t * t * t - t
        i = j + 1usize
    }
    ret (ties, ok)
}

// Mann-Whitney U (two-sided, normal approximation with continuity and tie
// correction); `scratch.len >= a.len + b.len` floats and `order` as many indices.
fn mann_whitney(a: []const f64, b: []const f64, scratch: []f64, order: []usize) -> (Result, err) {
    let n = a.len + b.len
    if a.len == 0usize || b.len == 0usize { ret (zero, Invalid) }
    if scratch.len < 2usize * n || order.len < n { ret (zero, TooSmall) }
    var pooled = scratch[..n]
    var i = 0usize
    while i < a.len {
        pooled[i] = a[i]
        i += 1usize
    }
    i = 0usize
    while i < b.len {
        pooled[a.len + i] = b[i]
        i += 1usize
    }
    var ranked = scratch[n..2usize * n]
    let (ties, rank_error) = ranks(pooled, ranked, order)
    if rank_error != ok { ret (zero, rank_error) }
    var rank_sum = 0.0f64
    i = 0usize
    while i < a.len {
        rank_sum += ranked[i]
        i += 1usize
    }
    let na = f64(a.len)
    let nb = f64(b.len)
    let u = rank_sum - na * (na + 1.0f64) / 2.0f64
    let mu = na * nb / 2.0f64
    let nf = f64(n)
    let sigma = math.sqrt[f64](na * nb / 12.0f64 * ((nf + 1.0f64) - ties / (nf * (nf - 1.0f64))))
    if sigma == 0.0f64 { ret (Result { statistic: u, p_value: 1.0f64 }, ok) }
    var z = u - mu
    if z > 0.5f64 { z -= 0.5f64 } else if z < 0.0f64 - 0.5f64 { z += 0.5f64 } else { z = 0.0f64 }
    z = z / sigma
    ret (Result { statistic: u, p_value: two_sided_normal(z) }, ok)
}

// Wilcoxon signed-rank test of paired samples (zero differences dropped,
// normal approximation with tie correction); `scratch.len >= 3 * a.len` floats
// and `order.len >= a.len` indices.
fn wilcoxon(a: []const f64, b: []const f64, scratch: []f64, order: []usize) -> (Result, err) {
    if a.len != b.len || a.len == 0usize { ret (zero, Invalid) }
    if scratch.len < 3usize * a.len || order.len < a.len { ret (zero, TooSmall) }
    var magnitudes = scratch[..a.len]
    var signs = scratch[a.len..2usize * a.len]
    var count = 0usize
    var i = 0usize
    while i < a.len {
        let d = a[i] - b[i]
        if d != 0.0f64 {
            magnitudes[count] = math.abs[f64](d)
            signs[count] = d
            count += 1usize
        }
        i += 1usize
    }
    if count == 0usize { ret (Result { statistic: 0.0f64, p_value: 1.0f64 }, ok) }
    var ranked = scratch[2usize * a.len..2usize * a.len + count]
    let (ties, rank_error) = ranks(magnitudes[..count], ranked, order)
    if rank_error != ok { ret (zero, rank_error) }
    var w_plus = 0.0f64
    i = 0usize
    while i < count {
        if signs[i] > 0.0f64 { w_plus += ranked[i] }
        i += 1usize
    }
    let n = f64(count)
    let mu = n * (n + 1.0f64) / 4.0f64
    let sigma = math.sqrt[f64](n * (n + 1.0f64) * (2.0f64 * n + 1.0f64) / 24.0f64 - ties / 48.0f64)
    if sigma == 0.0f64 { ret (Result { statistic: w_plus, p_value: 1.0f64 }, ok) }
    var z = w_plus - mu
    if z > 0.5f64 { z -= 0.5f64 } else if z < 0.0f64 - 0.5f64 { z += 0.5f64 } else { z = 0.0f64 }
    ret (Result { statistic: w_plus, p_value: two_sided_normal(z / sigma) }, ok)
}

// Chi-squared goodness of fit of `observed` counts against `expected`.
fn chi_squared(observed: []const f64, expected: []const f64) -> (Result, err) {
    if observed.len != expected.len || observed.len < 2usize { ret (zero, Invalid) }
    var statistic = 0.0f64
    var i = 0usize
    while i < observed.len {
        if expected[i] <= 0.0f64 { ret (zero, Invalid) }
        let d = observed[i] - expected[i]
        statistic += d * d / expected[i]
        i += 1usize
    }
    ret (Result { statistic: statistic, p_value: 1.0f64 - special.chi_squared_cdf(statistic, f64(observed.len - 1usize)) }, ok)
}

// Fisher's exact test on the table [[a, b], [c, d]], two-sided: the sum of the
// probabilities of every table at least as unlikely as the observed one.
fn fisher_exact(a: u64, b: u64, c: u64, d: u64) -> Result {
    let row1 = a + b
    let row2 = c + d
    let col1 = a + c
    let n = a + b + c + d
    if n == 0u64 { ret Result { statistic: 1.0f64, p_value: 1.0f64 } }
    let log_total = special.lgamma(f64(row1) + 1.0f64) + special.lgamma(f64(row2) + 1.0f64) + special.lgamma(f64(col1) + 1.0f64) + special.lgamma(f64(n - col1) + 1.0f64) - special.lgamma(f64(n) + 1.0f64)
    var low = 0u64
    if col1 > row2 { low = col1 - row2 }
    var high = row1
    if col1 < high { high = col1 }
    let observed = table_log_probability(a, row1, row2, col1, log_total)
    var p = 0.0f64
    var x = low
    while x <= high {
        let lp = table_log_probability(x, row1, row2, col1, log_total)
        if lp <= observed + 0.0000001f64 { p += math.exp[f64](lp) }
        x += 1u64
    }
    if p > 1.0f64 { p = 1.0f64 }
    var odds = 0.0f64
    if b * c != 0u64 { odds = f64(a * d) / f64(b * c) }
    ret Result { statistic: odds, p_value: p }
}

fn table_log_probability(x: u64, row1: u64, row2: u64, col1: u64, log_total: f64) -> f64 {
    let y = col1 - x
    ret log_total - special.lgamma(f64(x) + 1.0f64) - special.lgamma(f64(row1 - x) + 1.0f64) - special.lgamma(f64(y) + 1.0f64) - special.lgamma(f64(row2 - y) + 1.0f64)
}

// Insertion sort; `f64` has no `cmp` protocol for `e.algo.sort` to use.
fn sort_floats(values: []f64) {
    var i = 1usize
    while i < values.len {
        var j = i
        while j > 0usize && values[j] < values[j - 1usize] {
            let swap = values[j]
            values[j] = values[j - 1usize]
            values[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
}

// Two-sample Kolmogorov-Smirnov: the largest CDF gap `D` and its asymptotic
// p-value; `a` and `b` are sorted in place.
fn kolmogorov_smirnov(a: []f64, b: []f64) -> (Result, err) {
    if a.len == 0usize || b.len == 0usize { ret (zero, Invalid) }
    sort_floats(a)
    sort_floats(b)
    var i = 0usize
    var j = 0usize
    var d = 0.0f64
    while i < a.len && j < b.len {
        let x = a[i]
        let y = b[j]
        var v = x
        if y < x { v = y }
        while i < a.len && a[i] <= v { i += 1usize }
        while j < b.len && b[j] <= v { j += 1usize }
        let gap = math.abs[f64](f64(i) / f64(a.len) - f64(j) / f64(b.len))
        if gap > d { d = gap }
    }
    let en = math.sqrt[f64](f64(a.len) * f64(b.len) / f64(a.len + b.len))
    let lambda = (en + 0.12f64 + 0.11f64 / en) * d
    // Q_KS(lambda) = 2 sum (-1)^(k-1) exp(-2 k^2 lambda^2).
    var p = 0.0f64
    var sign = 1.0f64
    var k = 1.0f64
    var terms = 0usize
    while terms < 100usize {
        let term = sign * math.exp[f64](0.0f64 - 2.0f64 * k * k * lambda * lambda)
        p += 2.0f64 * term
        if math.abs[f64](term) < 1.0e-12f64 { break }
        sign = 0.0f64 - sign
        k += 1.0f64
        terms += 1usize
    }
    if p > 1.0f64 { p = 1.0f64 }
    if p < 0.0f64 { p = 0.0f64 }
    ret (Result { statistic: d, p_value: p }, ok)
}

// One-way ANOVA over groups laid out consecutively in `values` with the given
// `sizes`.
fn anova(values: []const f64, sizes: []const usize) -> (Result, err) {
    if sizes.len < 2usize { ret (zero, Invalid) }
    var total = 0usize
    var g = 0usize
    while g < sizes.len {
        if sizes[g] < 2usize { ret (zero, Invalid) }
        total += sizes[g]
        g += 1usize
    }
    if values.len < total { ret (zero, TooSmall) }
    let grand = mean(values[..total])
    var between = 0.0f64
    var within = 0.0f64
    var at = 0usize
    g = 0usize
    while g < sizes.len {
        let group = values[at..at + sizes[g]]
        let m = mean(group)
        between += f64(sizes[g]) * (m - grand) * (m - grand)
        var i = 0usize
        while i < group.len {
            within += (group[i] - m) * (group[i] - m)
            i += 1usize
        }
        at += sizes[g]
        g += 1usize
    }
    let df1 = f64(sizes.len - 1usize)
    let df2 = f64(total - sizes.len)
    if within == 0.0f64 { ret (zero, Invalid) }
    let f = (between / df1) / (within / df2)
    ret (Result { statistic: f, p_value: 1.0f64 - special.f_cdf(f, df1, df2) }, ok)
}

// Kruskal-Wallis over the same layout; `scratch.len >= total` floats and
// `order` as many indices.
fn kruskal_wallis(values: []const f64, sizes: []const usize, scratch: []f64, order: []usize) -> (Result, err) {
    if sizes.len < 2usize { ret (zero, Invalid) }
    var total = 0usize
    var g = 0usize
    while g < sizes.len {
        if sizes[g] == 0usize { ret (zero, Invalid) }
        total += sizes[g]
        g += 1usize
    }
    if values.len < total { ret (zero, TooSmall) }
    if scratch.len < total || order.len < total { ret (zero, TooSmall) }
    let (ties, rank_error) = ranks(values[..total], scratch, order)
    if rank_error != ok { ret (zero, rank_error) }
    let n = f64(total)
    var h = 0.0f64
    var at = 0usize
    g = 0usize
    while g < sizes.len {
        var rank_sum = 0.0f64
        var i = 0usize
        while i < sizes[g] {
            rank_sum += scratch[at + i]
            i += 1usize
        }
        h += rank_sum * rank_sum / f64(sizes[g])
        at += sizes[g]
        g += 1usize
    }
    h = 12.0f64 / (n * (n + 1.0f64)) * h - 3.0f64 * (n + 1.0f64)
    let correction = 1.0f64 - ties / (n * n * n - n)
    if correction > 0.0f64 { h = h / correction }
    ret (Result { statistic: h, p_value: 1.0f64 - special.chi_squared_cdf(h, f64(sizes.len - 1usize)) }, ok)
}

// A permutation test of the difference of means: `rounds` random relabellings
// over `scratch.len >= a.len + b.len`; the p-value is the fraction of
// relabellings at least as extreme as the observed difference.
fn permutation(r: *rand.Pcg64, a: []const f64, b: []const f64, rounds: u32, scratch: []f64) -> (Result, err) {
    let n = a.len + b.len
    if a.len == 0usize || b.len == 0usize || rounds == 0u32 { ret (zero, Invalid) }
    if scratch.len < n { ret (zero, TooSmall) }
    var pooled = scratch[..n]
    var i = 0usize
    while i < a.len {
        pooled[i] = a[i]
        i += 1usize
    }
    i = 0usize
    while i < b.len {
        pooled[a.len + i] = b[i]
        i += 1usize
    }
    let observed = math.abs[f64](mean(a) - mean(b))
    var extreme = 0u32
    var round = 0u32
    while round < rounds {
        rand.shuffle[f64](r, pooled)
        let d = math.abs[f64](mean(pooled[..a.len]) - mean(pooled[a.len..]))
        if d >= observed - 0.000000000001f64 { extreme += 1u32 }
        round += 1u32
    }
    ret (Result { statistic: mean(a) - mean(b), p_value: (f64(extreme) + 1.0f64) / (f64(rounds) + 1.0f64) }, ok)
}

// Bonferroni: each p-value multiplied by the count, capped at one, in place.
fn bonferroni(p_values: []f64) {
    let m = f64(p_values.len)
    var i = 0usize
    while i < p_values.len {
        p_values[i] = p_values[i] * m
        if p_values[i] > 1.0f64 { p_values[i] = 1.0f64 }
        i += 1usize
    }
}

// Benjamini-Hochberg adjusted p-values in place (monotone from the largest
// down); `order.len >= p_values.len`.
fn benjamini_hochberg(p_values: []f64, order: []usize) -> err {
    let n = p_values.len
    if order.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && p_values[order[j]] < p_values[order[j - 1usize]] {
            let swap = order[j]
            order[j] = order[j - 1usize]
            order[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    var running = 1.0f64
    i = n
    while i > 0usize {
        i -= 1usize
        var adjusted = p_values[order[i]] * f64(n) / f64(i + 1usize)
        if adjusted > running { adjusted = running }
        running = adjusted
        p_values[order[i]] = adjusted
    }
    ret ok
}
