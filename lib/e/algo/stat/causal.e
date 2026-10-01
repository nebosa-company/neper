// Causal and missing-data methods over caller storage: propensity scores
// by Newton's method, Hajek inverse-probability-weighted and augmented
// (doubly robust) treatment effects with closed-form standard errors,
// Bayesian multiple imputation by chained equations for continuous
// variables, and Rubin's pooling rules.
//
// Treatments and missingness flags are `u8` (anything else is `Invalid`);
// rows are observed cases. Propensity scores must stay strictly inside
// (0, 1): trim or overlap-weight caller-side, because a 0 or 1 is a
// positivity violation and answers `Invalid` instead of an exploding
// weight. Outcome predictions for the doubly robust estimator come from
// the caller (a per-arm regression among them), keeping this module free
// of outcome-model opinions.

use e.algo.rand
use e.algo.rand.dist as dist
use e.math
use e.math.special

error TooSmall
error Singular
error Invalid

// Solve the dense `n × n` system in place by Gaussian elimination with
// partial pivoting; the answer replaces `rhs`. `Singular` below 1e-12 pivots.
fn causal_solve(matrix: []f64, rhs: []f64, n: usize) -> err {
    var column = 0usize
    while column < n {
        var pivot = column
        var row = column + 1usize
        while row < n {
            if math.abs[f64](matrix[row * n + column]) > math.abs[f64](matrix[pivot * n + column]) { pivot = row }
            row += 1usize
        }
        if math.abs[f64](matrix[pivot * n + column]) < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var c = 0usize
            while c < n {
                let t = matrix[column * n + c]
                matrix[column * n + c] = matrix[pivot * n + c]
                matrix[pivot * n + c] = t
                c += 1usize
            }
            let t = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = t
        }
        row = column + 1usize
        while row < n {
            let factor = matrix[row * n + column] / matrix[column * n + column]
            if factor != 0.0f64 {
                var c = column
                while c < n {
                    matrix[row * n + c] -= factor * matrix[column * n + c]
                    c += 1usize
                }
                rhs[row] -= factor * rhs[column]
            }
            row += 1usize
        }
        column += 1usize
    }
    var i = n
    while i > 0usize {
        i -= 1usize
        var s = rhs[i]
        var c = i + 1usize
        while c < n {
            s -= matrix[i * n + c] * rhs[c]
            c += 1usize
        }
        rhs[i] = s / matrix[i * n + i]
    }
    ret ok
}

// In-place Cholesky: the lower triangle becomes `L` with `A = L L'`.
// `Singular` on a non-positive pivot.
fn causal_chol(matrix: []f64, n: usize) -> err {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = matrix[i * n + j]
            var k = 0usize
            while k < j {
                s -= matrix[i * n + k] * matrix[j * n + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret Singular }
                matrix[i * n + i] = math.sqrt[f64](s)
            } else {
                matrix[i * n + j] = s / matrix[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// Solve with a Cholesky factor from `causal_chol` (lower triangle read
// only); the answer replaces `rhs`.
fn causal_chol_solve(l: []const f64, rhs: []f64, n: usize) -> err {
    if l.len < n * n || rhs.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        var s = rhs[i]
        var j = 0usize
        while j < i {
            s -= l[i * n + j] * rhs[j]
            j += 1usize
        }
        if l[i * n + i] == 0.0f64 { ret Singular }
        rhs[i] = s / l[i * n + i]
        i += 1usize
    }
    var r = n
    while r > 0usize {
        r -= 1usize
        var s = rhs[r]
        var j = r + 1usize
        while j < n {
            s -= l[j * n + r] * rhs[j]
            j += 1usize
        }
        rhs[r] = s / l[r * n + r]
    }
    ret ok
}

// The feature `j` of sample `i`, the intercept column being `j == d`.
fn causal_at(x: []const f64, d: usize, i: usize, j: usize) -> f64 {
    if j == d { ret 1.0f64 }
    ret x[i * d + j]
}

// Propensity scores `P(T = 1 | x)` by Newton's method on the log loss with
// a fixed 1e-8 ridge on the feature weights (an intercept is fitted, never
// penalised), stopping when the step falls under `tolerance` or after
// `max_iterations`; answers the rounds taken. `scratch.len >= (d + 1) *
// (d + 3)` holds the coefficients, Hessian, gradient and step.
fn propensity_scores(x: []const f64, treated: []const u8, n: usize, d: usize, tolerance: f64, max_iterations: u32, scores: []f64, scratch: []f64) -> (u32, err) {
    let k = d + 1usize
    if x.len < n * d || treated.len < n || scores.len < n || scratch.len < k * k + 3usize * k { ret (0u32, TooSmall) }
    if n == 0usize || d == 0usize { ret (0u32, Invalid) }
    var i = 0usize
    while i < n {
        if treated[i] != 0u8 && treated[i] != 1u8 { ret (0u32, Invalid) }
        i += 1usize
    }
    var coefficients = scratch[..k]
    var at = k
    var hessian = scratch[at..at + k * k]
    at += k * k
    var gradient = scratch[at..at + k]
    at += k
    var step = scratch[at..at + k]
    var j = 0usize
    while j < k {
        coefficients[j] = 0.0f64
        j += 1usize
    }
    var iteration = 0u32
    var converged = false
    while iteration < max_iterations && !converged {
        j = 0usize
        while j < k * k {
            hessian[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < k {
            gradient[j] = 0.0f64
            j += 1usize
        }
        i = 0usize
        while i < n {
            var s = coefficients[d]
            j = 0usize
            while j < d {
                s += coefficients[j] * x[i * d + j]
                j += 1usize
            }
            let p = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s))
            let w = p * (1.0f64 - p)
            var label = 0.0f64
            if treated[i] == 1u8 { label = 1.0f64 }
            var a = 0usize
            while a < k {
                let xa = causal_at(x, d, i, a)
                gradient[a] += xa * (p - label)
                var h = 0usize
                while h < k {
                    hessian[a * k + h] += w * xa * causal_at(x, d, i, h)
                    h += 1usize
                }
                a += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < d {
            gradient[j] += 0.00000001f64 * coefficients[j]
            hessian[j * k + j] += 0.00000001f64
            j += 1usize
        }
        j = 0usize
        while j < k {
            step[j] = gradient[j]
            j += 1usize
        }
        let solve_error = causal_solve(hessian, step, k)
        if solve_error != ok { ret (iteration, solve_error) }
        var largest = 0.0f64
        j = 0usize
        while j < k {
            coefficients[j] -= step[j]
            largest = math.max[f64](largest, math.abs[f64](step[j]))
            j += 1usize
        }
        iteration += 1u32
        if largest < tolerance { converged = true }
    }
    i = 0usize
    while i < n {
        var s = coefficients[d]
        j = 0usize
        while j < d {
            s += coefficients[j] * x[i * d + j]
            j += 1usize
        }
        scores[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s))
        i += 1usize
    }
    ret (iteration, ok)
}

// The Hajek (normalized) inverse-probability-weighted average treatment
// effect: `mu1 - mu0` with each arm's weighted mean, and the sandwich
// standard error with the weights taken as known, plus the two-sided normal
// p-value. Scores outside (0, 1) and one-sided samples answer `Invalid`.
fn iptw_ate(y: []const f64, treated: []const u8, scores: []const f64, n: usize) -> (f64, f64, f64, err) {
    if y.len < n || treated.len < n || scores.len < n { ret (0.0f64, 0.0f64, 0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    var i = 0usize
    while i < n {
        if treated[i] != 0u8 && treated[i] != 1u8 { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        if !(scores[i] > 0.0f64 && scores[i] < 1.0f64) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        i += 1usize
    }
    var num1 = 0.0f64
    var den1 = 0.0f64
    var num0 = 0.0f64
    var den0 = 0.0f64
    i = 0usize
    while i < n {
        if treated[i] == 1u8 {
            num1 += y[i] / scores[i]
            den1 += 1.0f64 / scores[i]
        } else {
            num0 += y[i] / (1.0f64 - scores[i])
            den0 += 1.0f64 / (1.0f64 - scores[i])
        }
        i += 1usize
    }
    if den1 == 0.0f64 || den0 == 0.0f64 { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    let mu1 = num1 / den1
    let mu0 = num0 / den0
    let ate = mu1 - mu0
    let mean1 = den1 / f64(n)
    let mean0 = den0 / f64(n)
    var total = 0.0f64
    i = 0usize
    while i < n {
        var term = 0.0f64
        if treated[i] == 1u8 {
            term = (y[i] - mu1) / scores[i] / mean1
        } else {
            term = 0.0f64 - (y[i] - mu0) / (1.0f64 - scores[i]) / mean0
        }
        total += term * term
        i += 1usize
    }
    let se = math.sqrt[f64](total) / f64(n)
    if !(se > 0.0f64) { ret (ate, se, 0.0f64, Invalid) }
    let z = math.abs[f64](ate) / se
    ret (ate, se, 2.0f64 * (1.0f64 - special.normal_cdf(z)), ok)
}

// The augmented (doubly robust) treatment effect from caller outcome
// predictions `mu1`/`mu0`: the mean of the augmented terms, consistent
// when either the scores or the predictions are right, with the sample
// standard error of the terms and the two-sided normal p-value.
fn doubly_robust(y: []const f64, treated: []const u8, scores: []const f64, mu1: []const f64, mu0: []const f64, n: usize) -> (f64, f64, f64, err) {
    if y.len < n || treated.len < n || scores.len < n || mu1.len < n || mu0.len < n { ret (0.0f64, 0.0f64, 0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    var i = 0usize
    while i < n {
        if treated[i] != 0u8 && treated[i] != 1u8 { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        if !(scores[i] > 0.0f64 && scores[i] < 1.0f64) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        i += 1usize
    }
    var ate = 0.0f64
    i = 0usize
    while i < n {
        if treated[i] == 1u8 {
            ate += mu1[i] - mu0[i] + (y[i] - mu1[i]) / scores[i]
        } else {
            ate += mu1[i] - mu0[i] - (y[i] - mu0[i]) / (1.0f64 - scores[i])
        }
        i += 1usize
    }
    ate = ate / f64(n)
    var spread = 0.0f64
    i = 0usize
    while i < n {
        var term = 0.0f64
        if treated[i] == 1u8 {
            term = mu1[i] - mu0[i] + (y[i] - mu1[i]) / scores[i]
        } else {
            term = mu1[i] - mu0[i] - (y[i] - mu0[i]) / (1.0f64 - scores[i])
        }
        let t = term - ate
        spread += t * t
        i += 1usize
    }
    if n < 2usize { ret (ate, 0.0f64, 0.0f64, Invalid) }
    let se = math.sqrt[f64](spread / f64(n - 1usize)) / math.sqrt[f64](f64(n))
    if !(se > 0.0f64) { ret (ate, se, 0.0f64, Invalid) }
    let z = math.abs[f64](ate) / se
    ret (ate, se, 2.0f64 * (1.0f64 - special.normal_cdf(z)), ok)
}

// One Bayesian completed dataset by chained equations for continuous
// variables: from observed column means, `cycles` passes regress each
// column with missing entries on all others (intercept included) by least
// squares, draw the variance from its scaled-inverse-chi-squared posterior
// and the coefficients from their normal posterior through the caller's
// generator, and impute with fresh noise. A column needs at least one
// observed value and more observed rows than columns. `scratch.len >= n *
// d + d * d + 2 * d` holds the design, the normal equations, and the
// posterior draws.
fn mice_impute(data: []const f64, missing: []const u8, n: usize, d: usize, cycles: u32, r: *rand.Pcg64, completed: []f64, scratch: []f64) -> err {
    if data.len < n * d || missing.len < n * d || completed.len < n * d || scratch.len < n * d + d * d + 2usize * d { ret TooSmall }
    if n == 0usize || d == 0usize { ret Invalid }
    var at = 0usize
    var design = scratch[..n * d]
    at += n * d
    var normal = scratch[at..at + d * d]
    at += d * d
    var response = scratch[at..at + d]
    at += d
    var draw = scratch[at..at + d]
    var i = 0usize
    while i < n * d {
        if missing[i] != 0u8 && missing[i] != 1u8 { ret Invalid }
        completed[i] = data[i]
        i += 1usize
    }
    var j = 0usize
    while j < d {
        var sum = 0.0f64
        var count = 0usize
        i = 0usize
        while i < n {
            if missing[i * d + j] == 0u8 {
                sum += data[i * d + j]
                count += 1usize
            }
            i += 1usize
        }
        if count == 0usize { ret Invalid }
        let mean = sum / f64(count)
        i = 0usize
        while i < n {
            if missing[i * d + j] == 1u8 { completed[i * d + j] = mean }
            i += 1usize
        }
        j += 1usize
    }
    var round = 0u32
    while round < cycles {
        j = 0usize
        while j < d {
            var observed = 0usize
            i = 0usize
            while i < n {
                if missing[i * d + j] == 0u8 { observed += 1usize }
                i += 1usize
            }
            if observed > 0usize {
                if observed <= d { ret Invalid }
                var row = 0usize
                i = 0usize
                while i < n {
                    if missing[i * d + j] == 0u8 {
                        design[row * d] = 1.0f64
                        var c = 1usize
                        while c < d {
                            var col = c - 1usize
                            if col >= j { col += 1usize }
                            design[row * d + c] = completed[i * d + col]
                            c += 1usize
                        }
                        row += 1usize
                    }
                    i += 1usize
                }
                var a = 0usize
                while a < d {
                    var h = 0usize
                    while h < d {
                        normal[a * d + h] = 0.0f64
                        h += 1usize
                    }
                    response[a] = 0.0f64
                    a += 1usize
                }
                var o = 0usize
                while o < observed {
                    a = 0usize
                    while a < d {
                        var h = 0usize
                        while h < d {
                            normal[a * d + h] += design[o * d + a] * design[o * d + h]
                            h += 1usize
                        }
                        a += 1usize
                    }
                    o += 1usize
                }
                o = 0usize
                i = 0usize
                while i < n {
                    if missing[i * d + j] == 0u8 {
                        a = 0usize
                        while a < d {
                            response[a] += design[o * d + a] * data[i * d + j]
                            a += 1usize
                        }
                        o += 1usize
                    }
                    i += 1usize
                }
                let chol_error = causal_chol(normal, d)
                if chol_error != ok { ret chol_error }
                let solve_error = causal_chol_solve(normal, response, d)
                if solve_error != ok { ret solve_error }
                var rss = 0.0f64
                o = 0usize
                i = 0usize
                while i < n {
                    if missing[i * d + j] == 0u8 {
                        var fitted = 0.0f64
                        a = 0usize
                        while a < d {
                            fitted += design[o * d + a] * response[a]
                            a += 1usize
                        }
                        let residual = data[i * d + j] - fitted
                        rss += residual * residual
                        o += 1usize
                    }
                    i += 1usize
                }
                let freedom = observed - d
                var chi = 0.0f64
                var f = 0usize
                while f < freedom {
                    let z = dist.normal(r)
                    chi += z * z
                    f += 1usize
                }
                if chi <= 0.0f64 { ret Invalid }
                let sigma = math.sqrt[f64](rss / chi)
                a = 0usize
                while a < d {
                    draw[a] = dist.normal(r)
                    a += 1usize
                }
                // The transpose solve `L' w = z` over the kept factor.
                var descending = d
                while descending > 0usize {
                    descending -= 1usize
                    var s = draw[descending]
                    var h = descending + 1usize
                    while h < d {
                        s -= normal[h * d + descending] * draw[h]
                        h += 1usize
                    }
                    draw[descending] = s / normal[descending * d + descending]
                }
                i = 0usize
                while i < n {
                    if missing[i * d + j] == 1u8 {
                        var s = 0.0f64
                        a = 0usize
                        while a < d {
                            var basis = 0.0f64
                            if a == 0usize {
                                basis = 1.0f64
                            } else {
                                var col = a - 1usize
                                if col >= j { col += 1usize }
                                basis = completed[i * d + col]
                            }
                            s += (response[a] + sigma * draw[a]) * basis
                            a += 1usize
                        }
                        completed[i * d + j] = s + sigma * dist.normal(r)
                    }
                    i += 1usize
                }
            }
            j += 1usize
        }
        round += 1u32
    }
    ret ok
}

// Rubin's pooling rules over `m` completed-data estimates with their
// variances: the pooled estimate, the total variance (within plus
// between, the latter inflated by `1 + 1 / m`), and the degrees of freedom
// (a large sentinel for no between variation).
fn mice_pool(estimates: []const f64, variances: []const f64, m: usize) -> (f64, f64, f64, err) {
    if estimates.len < m || variances.len < m { ret (0.0f64, 0.0f64, 0.0f64, TooSmall) }
    if m < 2usize { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    var pooled = 0.0f64
    var within = 0.0f64
    var i = 0usize
    while i < m {
        if !(variances[i] >= 0.0f64) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        pooled += estimates[i] / f64(m)
        within += variances[i] / f64(m)
        i += 1usize
    }
    var between = 0.0f64
    i = 0usize
    while i < m {
        let t = estimates[i] - pooled
        between += t * t
        i += 1usize
    }
    between = between / f64(m - 1usize)
    let total = within + (1.0f64 + 1.0f64 / f64(m)) * between
    if between <= 0.0f64 { ret (pooled, total, 1.0e300f64, ok) }
    let ratio = within / ((1.0f64 + 1.0f64 / f64(m)) * between)
    let freedom = f64(m - 1usize) * (1.0f64 + ratio) * (1.0f64 + ratio)
    ret (pooled, total, freedom, ok)
}

// Multiple imputation by chained equations: `m` independent completed
// datasets (fresh chains from the observed means), each measured by
// `estimate` over its `n × d` completed rows into an estimate and a
// variance, pooled by Rubin's rules into `pooled` (estimate, variance,
// degrees of freedom). `scratch.len >= n * d + d * d + 2 * d + 2 * m`
// holds one imputation's workspace beside its `m` estimates and variances.
fn mice[Ctx: type](data: []const f64, missing: []const u8, n: usize, d: usize, cycles: u32, m: usize, r: *rand.Pcg64, ctx: *Ctx, estimate: fn(*Ctx, []const f64, usize, usize) -> (f64, f64), completed: []f64, pooled: []f64, scratch: []f64) -> err {
    if data.len < n * d || missing.len < n * d || completed.len < n * d || pooled.len < 3usize || scratch.len < n * d + d * d + 2usize * d + 2usize * m { ret TooSmall }
    if m < 2usize { ret Invalid }
    var at = n * d + d * d + 2usize * d
    var estimates = scratch[at..at + m]
    at += m
    var variances = scratch[at..at + m]
    var k = 0usize
    while k < m {
        let impute_error = mice_impute(data, missing, n, d, cycles, r, completed, scratch[..n * d + d * d + 2usize * d])
        if impute_error != ok { ret impute_error }
        let (e, v) = estimate(ctx, completed[..n * d], n, d)
        estimates[k] = e
        variances[k] = v
        k += 1usize
    }
    let (pooled_estimate, pooled_variance, freedom, pool_error) = mice_pool(estimates, variances, m)
    if pool_error != ok { ret pool_error }
    pooled[0usize] = pooled_estimate
    pooled[1usize] = pooled_variance
    pooled[2usize] = freedom
    ret ok
}
