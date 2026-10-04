// Meta-analysis core over caller slices: log odds-ratio, log risk-ratio,
// Cohen-d, Hedges-g and Fisher-z effect sizes with sampling variances,
// inverse-variance fixed and DerSimonian-Laird random pooling, Cochran's Q,
// I-squared, DerSimonian-Laird tau-squared, between-subgroup Q, and
// weighted-least-squares meta-regression. The numerical core only; report
// formatting is out of scope.

use e.math
use e.math.special

type Effect = struct { estimate: f64, variance: f64 }
type Pooled = struct { estimate: f64, se: f64, low: f64, high: f64 }
error TooSmall
error Singular
error Invalid

// The log odds ratio over `[[a, b], [c, d]]` with variance
// `1/a + 1/b + 1/c + 1/d`; any zero cell is `Invalid`.
fn log_odds_ratio(a: u64, b: u64, c: u64, d: u64) -> (Effect, err) {
    if a == 0u64 || b == 0u64 || c == 0u64 || d == 0u64 { ret (zero, Invalid) }
    ret (Effect {
        estimate: math.log[f64](f64(a) * f64(d) / (f64(b) * f64(c))),
        variance: 1.0f64 / f64(a) + 1.0f64 / f64(b) + 1.0f64 / f64(c) + 1.0f64 / f64(d)
    }, ok)
}

// The log risk ratio with variance `1/a - 1/(a+b) + 1/c - 1/(c+d)`; a zero
// `a` or `c`, or an empty row, is `Invalid`.
fn log_risk_ratio(a: u64, b: u64, c: u64, d: u64) -> (Effect, err) {
    if a == 0u64 || c == 0u64 || a + b == 0u64 || c + d == 0u64 { ret (zero, Invalid) }
    ret (Effect {
        estimate: math.log[f64](f64(a) * f64(c + d) / (f64(c) * f64(a + b))),
        variance: 1.0f64 / f64(a) - 1.0f64 / f64(a + b) + 1.0f64 / f64(c) - 1.0f64 / f64(c + d)
    }, ok)
}

// Cohen's d over two means with the pooled standard deviation, variance
// `(n1+n2)/(n1 n2) + d^2/(2(n1+n2))`; a non-positive deviation or a group
// below two observations is `Invalid`.
fn cohen_d(m1: f64, sd1: f64, n1: u64, m2: f64, sd2: f64, n2: u64) -> (Effect, err) {
    if !(sd1 > 0.0f64) || !(sd2 > 0.0f64) || n1 < 2u64 || n2 < 2u64 { ret (zero, Invalid) }
    let pooled = math.sqrt[f64]((f64(n1 - 1u64) * sd1 * sd1 + f64(n2 - 1u64) * sd2 * sd2) / f64(n1 + n2 - 2u64))
    let d = (m1 - m2) / pooled
    let total = f64(n1 + n2)
    ret (Effect {
        estimate: d,
        variance: total / (f64(n1) * f64(n2)) + d * d / (2.0f64 * total)
    }, ok)
}

// Hedges' g: Cohen's d with the small-sample `J` correction applied to the
// estimate and squared onto the variance.
fn hedges_g(m1: f64, sd1: f64, n1: u64, m2: f64, sd2: f64, n2: u64) -> (Effect, err) {
    let (d, d_error) = cohen_d(m1, sd1, n1, m2, sd2, n2)
    if d_error != ok { ret (zero, d_error) }
    let adjust = 1.0f64 - 3.0f64 / (4.0f64 * f64(n1 + n2 - 2u64) - 1.0f64)
    ret (Effect { estimate: adjust * d.estimate, variance: adjust * adjust * d.variance }, ok)
}

// Fisher's z (`atanh`) of a correlation with variance `1/(n-3)`; `|r| >= 1`
// or fewer than four observations is `Invalid`.
fn fisher_z(r: f64, n: u64) -> (Effect, err) {
    if !(r > 0.0f64 - 1.0f64) || !(r < 1.0f64) || n <= 3u64 { ret (zero, Invalid) }
    ret (Effect {
        estimate: 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r)),
        variance: 1.0f64 / (f64(n) - 3.0f64)
    }, ok)
}

// Inverse-variance fixed-effect pooling with the 95% interval; an empty set
// or a non-positive variance is `Invalid`.
fn fixed_pool(estimates: []const f64, variances: []const f64, n: usize) -> (Pooled, err) {
    if estimates.len < n || variances.len < n { ret (zero, TooSmall) }
    if n == 0usize { ret (zero, Invalid) }
    var top = 0.0f64
    var bottom = 0.0f64
    var i = 0usize
    while i < n {
        if !(variances[i] > 0.0f64) { ret (zero, Invalid) }
        let w = 1.0f64 / variances[i]
        top += w * estimates[i]
        bottom += w
        i += 1usize
    }
    let estimate = top / bottom
    let se = 1.0f64 / math.sqrt[f64](bottom)
    ret (Pooled { estimate: estimate, se: se, low: estimate - 1.96f64 * se, high: estimate + 1.96f64 * se }, ok)
}

// Cochran's Q of `estimates` about `pooled` (usually the fixed estimate)
// with inverse-variance weights.
fn q_statistic(estimates: []const f64, variances: []const f64, n: usize, pooled: f64) -> (f64, err) {
    if estimates.len < n || variances.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, Invalid) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        if !(variances[i] > 0.0f64) { ret (0.0f64, Invalid) }
        let gap = estimates[i] - pooled
        total += gap * gap / variances[i]
        i += 1usize
    }
    ret (total, ok)
}

// DerSimonian-Laird between-study variance from `q` over `n` studies;
// negative truncates to zero. Fewer than two studies is `Invalid`.
fn tau_squared_dl(q: f64, variances: []const f64, n: usize) -> (f64, err) {
    if variances.len < n { ret (0.0f64, TooSmall) }
    if n < 2usize { ret (0.0f64, Invalid) }
    var sum = 0.0f64
    var squares = 0.0f64
    var i = 0usize
    while i < n {
        if !(variances[i] > 0.0f64) { ret (0.0f64, Invalid) }
        let w = 1.0f64 / variances[i]
        sum += w
        squares += w * w
        i += 1usize
    }
    let denom = sum - squares / sum
    if !(denom > 0.0f64) { ret (0.0f64, Invalid) }
    let excess = (q - f64(n - 1usize)) / denom
    if excess <= 0.0f64 { ret (0.0f64, ok) }
    ret (excess, ok)
}

// I-squared, the share of `q` past its `df` degrees of freedom, floored at
// zero (and zero for a non-positive `q`).
fn i_squared(q: f64, df: usize) -> f64 {
    if !(q > 0.0f64) { ret 0.0f64 }
    let share = (q - f64(df)) / q
    if share <= 0.0f64 { ret 0.0f64 }
    ret share
}

// Between-subgroup heterogeneity: `q_total` minus the subgroup Q values,
// floored at zero for floating-point dust.
fn q_between(q_total: f64, q_subs: []const f64, groups: usize) -> (f64, err) {
    if q_subs.len < groups { ret (0.0f64, TooSmall) }
    if groups == 0usize { ret (0.0f64, Invalid) }
    var within = 0.0f64
    var g = 0usize
    while g < groups {
        within += q_subs[g]
        g += 1usize
    }
    if q_total <= within { ret (0.0f64, ok) }
    ret (q_total - within, ok)
}

// Random-effects pooling with weights `1/(variance + tau2)` and the 95%
// interval; a negative `tau2` is `Invalid`.
fn random_pool(estimates: []const f64, variances: []const f64, n: usize, tau2: f64) -> (Pooled, err) {
    if estimates.len < n || variances.len < n { ret (zero, TooSmall) }
    if n == 0usize { ret (zero, Invalid) }
    if !(tau2 >= 0.0f64) { ret (zero, Invalid) }
    var top = 0.0f64
    var bottom = 0.0f64
    var i = 0usize
    while i < n {
        if !(variances[i] > 0.0f64) { ret (zero, Invalid) }
        let w = 1.0f64 / (variances[i] + tau2)
        top += w * estimates[i]
        bottom += w
        i += 1usize
    }
    let estimate = top / bottom
    let se = 1.0f64 / math.sqrt[f64](bottom)
    ret (Pooled { estimate: estimate, se: se, low: estimate - 1.96f64 * se, high: estimate + 1.96f64 * se }, ok)
}

// Solve the dense `p × p` system in place by Gauss-Jordan elimination with
// partial pivoting; the answer replaces `rhs`. `Singular` below 1e-12 pivots.
fn meta_solve(matrix: []f64, rhs: []f64, p: usize) -> err {
    var column = 0usize
    while column < p {
        var pivot = column
        var best = matrix[column * p + column]
        if best < 0.0f64 { best = 0.0f64 - best }
        var row = column + 1usize
        while row < p {
            var contender = matrix[row * p + column]
            if contender < 0.0f64 { contender = 0.0f64 - contender }
            if contender > best {
                pivot = row
                best = contender
            }
            row += 1usize
        }
        if best < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var j = 0usize
            while j < p {
                let held = matrix[column * p + j]
                matrix[column * p + j] = matrix[pivot * p + j]
                matrix[pivot * p + j] = held
                j += 1usize
            }
            let held = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = held
        }
        let scale = 1.0f64 / matrix[column * p + column]
        var j = column
        while j < p {
            matrix[column * p + j] = matrix[column * p + j] * scale
            j += 1usize
        }
        rhs[column] = rhs[column] * scale
        var r = 0usize
        while r < p {
            if r != column {
                let factor = matrix[r * p + column]
                if factor != 0.0f64 {
                    j = column
                    while j < p {
                        matrix[r * p + j] -= factor * matrix[column * p + j]
                        j += 1usize
                    }
                    rhs[r] -= factor * rhs[column]
                }
            }
            r += 1usize
        }
        column += 1usize
    }
    ret ok
}

// Weighted-least-squares meta-regression of `estimates` on the caller-built
// `x` (`n × p` row-major, intercept column included) with weights
// `1/(variance + tau2)`: `beta` the coefficients, `covariance` their `p × p`
// covariance. `scratch.len >= 2 * p * p + 2 * p` holds the system, its working
// copy and two right-hand sides. Rank failure is `Singular`.
fn meta_regression(estimates: []const f64, variances: []const f64, x: []const f64, n: usize, p: usize, tau2: f64, beta: []f64, covariance: []f64, scratch: []f64) -> err {
    if estimates.len < n || variances.len < n || x.len < n * p || beta.len < p || covariance.len < p * p { ret TooSmall }
    if n == 0usize || p == 0usize { ret Invalid }
    if !(tau2 >= 0.0f64) { ret Invalid }
    if scratch.len < 2usize * p * p + 2usize * p { ret TooSmall }
    var xtwx = scratch[..p * p]
    var xtwy = scratch[p * p..p * p + p]
    var sys = scratch[p * p + p..2usize * p * p + p]
    var rhs = scratch[2usize * p * p + p..2usize * p * p + 2usize * p]
    var a = 0usize
    while a < p * p {
        xtwx[a] = 0.0f64
        a += 1usize
    }
    a = 0usize
    while a < p {
        xtwy[a] = 0.0f64
        a += 1usize
    }
    var i = 0usize
    while i < n {
        if !(variances[i] > 0.0f64) { ret Invalid }
        let w = 1.0f64 / (variances[i] + tau2)
        var u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                xtwx[u * p + v] += w * x[i * p + u] * x[i * p + v]
                v += 1usize
            }
            xtwy[u] += w * x[i * p + u] * estimates[i]
            u += 1usize
        }
        i += 1usize
    }
    var column = 0usize
    while column < p * p {
        sys[column] = xtwx[column]
        column += 1usize
    }
    column = 0usize
    while column < p {
        rhs[column] = xtwy[column]
        column += 1usize
    }
    let beta_error = meta_solve(sys, rhs, p)
    if beta_error != ok { ret beta_error }
    a = 0usize
    while a < p {
        beta[a] = rhs[a]
        a += 1usize
    }
    var j = 0usize
    while j < p {
        column = 0usize
        while column < p * p {
            sys[column] = xtwx[column]
            column += 1usize
        }
        column = 0usize
        while column < p {
            if column == j {
                rhs[column] = 1.0f64
            } else {
                rhs[column] = 0.0f64
            }
            column += 1usize
        }
        let column_error = meta_solve(sys, rhs, p)
        if column_error != ok { ret column_error }
        column = 0usize
        while column < p {
            covariance[column * p + j] = rhs[column]
            column += 1usize
        }
        j += 1usize
    }
    ret ok
}
