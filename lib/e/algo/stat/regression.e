// Generalized regressions over row-major `f64` samples (`n` rows of `d`
// features, intercept last) in caller storage: Poisson rate regression with
// exposure offsets by IRLS, negative-binomial regression by IRLS inside a
// golden-section search over the dispersion, conditional logistic regression
// for 1:M matched sets by Newton, and proportional-odds ordinal logistic
// regression by Nelder-Mead with a numeric covariance. Every fit answers
// `d + 1` coefficients (thresholds first for the ordinal model) with their
// model-based covariance; rank failure is `Singular`.

use e.math
use e.math.opt
use e.math.special

type OrdinalCtx = struct { x: []const f64, y: []const u8, n: usize, d: usize, levels: usize }
error TooSmall
error Singular
error Invalid

// Solve the dense `k × k` system in place; the answer replaces `rhs`.
// `Singular` below 1e-12 pivots.
fn reg_solve(matrix: []f64, rhs: []f64, k: usize) -> err {
    var column = 0usize
    while column < k {
        var pivot = column
        var best = matrix[column * k + column]
        if best < 0.0f64 { best = 0.0f64 - best }
        var row = column + 1usize
        while row < k {
            var contender = matrix[row * k + column]
            if contender < 0.0f64 { contender = 0.0f64 - contender }
            if contender > best {
                pivot = row
                best = contender
            }
            row += 1usize
        }
        if best < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var c = 0usize
            while c < k {
                let held = matrix[column * k + c]
                matrix[column * k + c] = matrix[pivot * k + c]
                matrix[pivot * k + c] = held
                c += 1usize
            }
            let held = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = held
        }
        let scale = 1.0f64 / matrix[column * k + column]
        var j = column
        while j < k {
            matrix[column * k + j] = matrix[column * k + j] * scale
            j += 1usize
        }
        rhs[column] = rhs[column] * scale
        var r = 0usize
        while r < k {
            if r != column {
                let factor = matrix[r * k + column]
                if factor != 0.0f64 {
                    j = column
                    while j < k {
                        matrix[r * k + j] -= factor * matrix[column * k + j]
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

// The feature `j` of sample `i`, the intercept column being `j == d`.
fn reg_at(x: []const f64, d: usize, i: usize, j: usize) -> f64 {
    if j == d { ret 1.0f64 }
    ret x[i * d + j]
}

// Invert the `k × k` Hessian into `covariance` column by column through
// `step` and `work`.
fn reg_covariance(hessian: []const f64, covariance: []f64, k: usize, step: []f64, work: []f64) -> err {
    if covariance.len < k * k || step.len < k || work.len < k * k { ret TooSmall }
    var c = 0usize
    while c < k {
        var j = 0usize
        while j < k * k {
            work[j] = hessian[j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            if j == c {
                step[j] = 1.0f64
            } else {
                step[j] = 0.0f64
            }
            j += 1usize
        }
        let column_error = reg_solve(work, step, k)
        if column_error != ok { ret column_error }
        j = 0usize
        while j < k {
            covariance[j * k + c] = step[j]
            j += 1usize
        }
        c += 1usize
    }
    ret ok
}

// Poisson rate regression: `rate = exposure * exp(x beta)` by IRLS from zero
// (linear predictor clamped to +-30). Answers Newton rounds, coefficients
// and covariance. A negative count or non-positive exposure is `Invalid`;
// `scratch.len >= 2 * k * k + 2 * k` with `k = d + 1`.
fn poisson(x: []const f64, y: []const f64, exposure: []const f64, n: usize, d: usize, tolerance: f64, max_iterations: u32, coefficients: []f64, covariance: []f64, scratch: []f64) -> (u32, err) {
    let k = d + 1usize
    if x.len < n * d || y.len < n || exposure.len < n || coefficients.len < k || covariance.len < k * k { ret (0u32, TooSmall) }
    if n == 0usize || d == 0usize { ret (0u32, Invalid) }
    if !(tolerance > 0.0f64) || max_iterations == 0u32 { ret (0u32, Invalid) }
    if scratch.len < 2usize * k * k + 2usize * k { ret (0u32, TooSmall) }
    var i = 0usize
    while i < n {
        if y[i] < 0.0f64 || exposure[i] <= 0.0f64 { ret (0u32, Invalid) }
        i += 1usize
    }
    var hessian = scratch[..k * k]
    var gradient = scratch[k * k..k * k + k]
    var step = scratch[k * k + k..k * k + 2usize * k]
    var work = scratch[k * k + 2usize * k..2usize * k * k + 2usize * k]
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
            var eta = math.log[f64](exposure[i])
            var a = 0usize
            while a < k {
                eta += reg_at(x, d, i, a) * coefficients[a]
                a += 1usize
            }
            if eta > 30.0f64 { eta = 30.0f64 }
            if eta < 0.0f64 - 30.0f64 { eta = 0.0f64 - 30.0f64 }
            let mu = math.exp[f64](eta)
            let w = mu
            a = 0usize
            while a < k {
                let xa = reg_at(x, d, i, a)
                gradient[a] += xa * (y[i] - mu)
                var b = 0usize
                while b < k {
                    hessian[a * k + b] += w * xa * reg_at(x, d, i, b)
                    b += 1usize
                }
                a += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < k {
            step[j] = gradient[j]
            j += 1usize
        }
        j = 0usize
        while j < k * k {
            work[j] = hessian[j]
            j += 1usize
        }
        if reg_solve(work, step, k) != ok { ret (iteration, Singular) }
        var largest = 0.0f64
        j = 0usize
        while j < k {
            coefficients[j] += step[j]
            let move = math.abs[f64](step[j])
            if move > largest { largest = move }
            j += 1usize
        }
        iteration += 1u32
        if largest < tolerance { converged = true }
    }
    let covariance_error = reg_covariance(hessian, covariance, k, step, work)
    if covariance_error != ok { ret (iteration, covariance_error) }
    ret (iteration, ok)
}

// One IRLS Newton run for the negative-binomial mean at dispersion `theta`
// from `coefficients` in place: `eta = x beta + log exposure` clamped to
// +-30, weights `mu theta / (theta + mu)`. Answers Newton rounds.
fn negbin_beta(x: []const f64, y: []const f64, exposure: []const f64, n: usize, d: usize, theta: f64, tolerance: f64, max_iterations: u32, coefficients: []f64, hessian: []f64, gradient: []f64, step: []f64, work: []f64) -> (u32, err) {
    let k = d + 1usize
    var iteration = 0u32
    var converged = false
    while iteration < max_iterations && !converged {
        var j = 0usize
        while j < k * k {
            hessian[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < k {
            gradient[j] = 0.0f64
            j += 1usize
        }
        var i = 0usize
        while i < n {
            var eta = math.log[f64](exposure[i])
            var a = 0usize
            while a < k {
                eta += reg_at(x, d, i, a) * coefficients[a]
                a += 1usize
            }
            if eta > 30.0f64 { eta = 30.0f64 }
            if eta < 0.0f64 - 30.0f64 { eta = 0.0f64 - 30.0f64 }
            let mu = math.exp[f64](eta)
            let w = mu * theta / (theta + mu)
            let score = (y[i] - mu) * theta / (theta + mu)
            a = 0usize
            while a < k {
                let xa = reg_at(x, d, i, a)
                gradient[a] += xa * score
                var b = 0usize
                while b < k {
                    hessian[a * k + b] += w * xa * reg_at(x, d, i, b)
                    b += 1usize
                }
                a += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < k {
            step[j] = gradient[j]
            j += 1usize
        }
        j = 0usize
        while j < k * k {
            work[j] = hessian[j]
            j += 1usize
        }
        if reg_solve(work, step, k) != ok { ret (iteration, Singular) }
        var largest = 0.0f64
        j = 0usize
        while j < k {
            coefficients[j] += step[j]
            let move = math.abs[f64](step[j])
            if move > largest { largest = move }
            j += 1usize
        }
        iteration += 1u32
        if largest < tolerance { converged = true }
    }
    ret (iteration, ok)
}

// The negative-binomial profile log-likelihood at dispersion `theta` with
// the mean at `coefficients`.
fn negbin_profile(x: []const f64, y: []const f64, exposure: []const f64, n: usize, d: usize, theta: f64, coefficients: []const f64) -> f64 {
    let k = d + 1usize
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var eta = math.log[f64](exposure[i])
        var a = 0usize
        while a < k {
            eta += reg_at(x, d, i, a) * coefficients[a]
            a += 1usize
        }
        if eta > 30.0f64 { eta = 30.0f64 }
        if eta < 0.0f64 - 30.0f64 { eta = 0.0f64 - 30.0f64 }
        let mu = math.exp[f64](eta)
        total += special.lgamma(y[i] + theta) - special.lgamma(theta) - special.lgamma(y[i] + 1.0f64) + theta * (math.log[f64](theta) - math.log[f64](theta + mu)) + y[i] * (math.log[f64](mu) - math.log[f64](theta + mu))
        i += 1usize
    }
    ret total
}

// Negative-binomial rate regression (`Var = mu + mu^2 / theta`) by IRLS over
// the mean inside a golden-section search over `log theta` on
// `[log 1e-3, log 1e3]`: `theta` holds one entry, any positive value, and
// receives the fit. Answers outer rounds, coefficients and covariance.
// `scratch.len >= 2 * k * k + 2 * k` with `k = d + 1`.
fn negbin(x: []const f64, y: []const f64, exposure: []const f64, n: usize, d: usize, tolerance: f64, max_iterations: u32, max_outer: u32, theta: []f64, coefficients: []f64, covariance: []f64, scratch: []f64) -> (u32, err) {
    let k = d + 1usize
    if x.len < n * d || y.len < n || exposure.len < n || theta.len < 1usize || coefficients.len < k || covariance.len < k * k { ret (0u32, TooSmall) }
    if n == 0usize || d == 0usize { ret (0u32, Invalid) }
    if !(tolerance > 0.0f64) || max_iterations == 0u32 || max_outer == 0u32 || !(theta[0usize] > 0.0f64) { ret (0u32, Invalid) }
    if scratch.len < 2usize * k * k + 2usize * k { ret (0u32, TooSmall) }
    var i = 0usize
    while i < n {
        if y[i] < 0.0f64 || exposure[i] <= 0.0f64 { ret (0u32, Invalid) }
        i += 1usize
    }
    var hessian = scratch[..k * k]
    var gradient = scratch[k * k..k * k + k]
    var step = scratch[k * k + k..k * k + 2usize * k]
    var work = scratch[k * k + 2usize * k..2usize * k * k + 2usize * k]
    var j = 0usize
    while j < k {
        coefficients[j] = 0.0f64
        j += 1usize
    }
    var lo = math.log[f64](0.001f64)
    var hi = math.log[f64](1000.0f64)
    let span = 0.6180339887498949f64 * (hi - lo)
    var c = hi - span
    var e = lo + span
    let (_, c_error) = negbin_beta(x, y, exposure, n, d, math.exp[f64](c), tolerance, max_iterations, coefficients, hessian, gradient, step, work)
    if c_error != ok { ret (0u32, c_error) }
    var fc = negbin_profile(x, y, exposure, n, d, math.exp[f64](c), coefficients)
    j = 0usize
    while j < k {
        coefficients[j] = 0.0f64
        j += 1usize
    }
    let (_, e_error) = negbin_beta(x, y, exposure, n, d, math.exp[f64](e), tolerance, max_iterations, coefficients, hessian, gradient, step, work)
    if e_error != ok { ret (0u32, e_error) }
    var fe = negbin_profile(x, y, exposure, n, d, math.exp[f64](e), coefficients)
    var outer = 0u32
    while outer < max_outer && hi - lo > 0.0000001f64 {
        if fc > fe {
            hi = e
            e = c
            fe = fc
            c = hi - 0.6180339887498949f64 * (hi - lo)
            j = 0usize
            while j < k {
                coefficients[j] = 0.0f64
                j += 1usize
            }
            let (_, beta_error) = negbin_beta(x, y, exposure, n, d, math.exp[f64](c), tolerance, max_iterations, coefficients, hessian, gradient, step, work)
            if beta_error != ok { ret (outer, beta_error) }
            fc = negbin_profile(x, y, exposure, n, d, math.exp[f64](c), coefficients)
        } else {
            lo = c
            c = e
            fc = fe
            e = lo + 0.6180339887498949f64 * (hi - lo)
            j = 0usize
            while j < k {
                coefficients[j] = 0.0f64
                j += 1usize
            }
            let (_, beta_error) = negbin_beta(x, y, exposure, n, d, math.exp[f64](e), tolerance, max_iterations, coefficients, hessian, gradient, step, work)
            if beta_error != ok { ret (outer, beta_error) }
            fe = negbin_profile(x, y, exposure, n, d, math.exp[f64](e), coefficients)
        }
        outer += 1u32
    }
    var best = c
    if fe > fc { best = e }
    theta[0usize] = math.exp[f64](best)
    j = 0usize
    while j < k {
        coefficients[j] = 0.0f64
        j += 1usize
    }
    let (_, beta_error) = negbin_beta(x, y, exposure, n, d, theta[0usize], tolerance, max_iterations, coefficients, hessian, gradient, step, work)
    if beta_error != ok { ret (outer, beta_error) }
    let covariance_error = reg_covariance(hessian, covariance, k, step, work)
    if covariance_error != ok { ret (outer, covariance_error) }
    ret (outer, ok)
}

// Conditional logistic regression for 1:M matched sets: the partial
// likelihood over strata (`stratum` groups rows, exactly one `y == 1` case
// and at least one control each) by Newton from zero, with the model-based
// covariance. No intercept is fit (the strata absorb it). Answers Newton
// rounds; `scratch.len >= 2 * d * d + 2 * d`.
fn cond_logistic(x: []const f64, y: []const u8, stratum: []const usize, n: usize, d: usize, tolerance: f64, max_iterations: u32, coefficients: []f64, covariance: []f64, scratch: []f64) -> (u32, err) {
    if x.len < n * d || y.len < n || stratum.len < n || coefficients.len < d || covariance.len < d * d { ret (0u32, TooSmall) }
    if n == 0usize || d == 0usize { ret (0u32, Invalid) }
    if !(tolerance > 0.0f64) || max_iterations == 0u32 { ret (0u32, Invalid) }
    if scratch.len < 2usize * d * d + 2usize * d { ret (0u32, TooSmall) }
    var i = 0usize
    while i < n {
        if y[i] != 0u8 && y[i] != 1u8 { ret (0u32, Invalid) }
        i += 1usize
    }
    var hessian = scratch[..d * d]
    var gradient = scratch[d * d..d * d + d]
    var step = scratch[d * d + d..d * d + 2usize * d]
    var work = scratch[d * d + 2usize * d..2usize * d * d + 2usize * d]
    var j = 0usize
    while j < d {
        coefficients[j] = 0.0f64
        j += 1usize
    }
    var iteration = 0u32
    var converged = false
    while iteration < max_iterations && !converged {
        j = 0usize
        while j < d * d {
            hessian[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < d {
            gradient[j] = 0.0f64
            j += 1usize
        }
        i = 0usize
        while i < n {
            var members = 0usize
            var cases = 0usize
            var s = 0usize
            while s < n {
                if stratum[s] == stratum[i] {
                    members += 1usize
                    if y[s] == 1u8 { cases += 1usize }
                }
                s += 1usize
            }
            if cases != 1usize || members < 2usize { ret (0u32, Invalid) }
            // Every member repeats its stratum's term; scale by size so each
            // stratum contributes once.
            let share = 1.0f64 / f64(members)
            var peak = 0.0f64
            var first = true
            s = 0usize
            while s < n {
                if stratum[s] == stratum[i] {
                    var eta = 0.0f64
                    var a = 0usize
                    while a < d {
                        eta += x[s * d + a] * coefficients[a]
                        a += 1usize
                    }
                    if first || eta > peak {
                        peak = eta
                        first = false
                    }
                }
                s += 1usize
            }
            var denom = 0.0f64
            s = 0usize
            while s < n {
                if stratum[s] == stratum[i] {
                    var eta = 0.0f64
                    var a = 0usize
                    while a < d {
                        eta += x[s * d + a] * coefficients[a]
                        a += 1usize
                    }
                    denom += math.exp[f64](eta - peak)
                }
                s += 1usize
            }
            var a = 0usize
            while a < d {
                var mean = 0.0f64
                s = 0usize
                while s < n {
                    if stratum[s] == stratum[i] {
                        var eta = 0.0f64
                        var b = 0usize
                        while b < d {
                            eta += x[s * d + b] * coefficients[b]
                            b += 1usize
                        }
                        mean += math.exp[f64](eta - peak) / denom * x[s * d + a]
                    }
                    s += 1usize
                }
                var mine = 0.0f64
                s = 0usize
                while s < n {
                    if stratum[s] == stratum[i] && y[s] == 1u8 { mine = x[s * d + a] }
                    s += 1usize
                }
                gradient[a] += (mine - mean) * share
                var h = 0usize
                while h < d {
                    var second = 0.0f64
                    s = 0usize
                    while s < n {
                        if stratum[s] == stratum[i] {
                            var eta = 0.0f64
                            var b = 0usize
                            while b < d {
                                eta += x[s * d + b] * coefficients[b]
                                b += 1usize
                            }
                            second += math.exp[f64](eta - peak) / denom * x[s * d + a] * x[s * d + h]
                        }
                        s += 1usize
                    }
                    hessian[a * d + h] += (second - mean * mean) * share
                    h += 1usize
                }
                a += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < d {
            step[j] = gradient[j]
            j += 1usize
        }
        j = 0usize
        while j < d * d {
            work[j] = hessian[j]
            j += 1usize
        }
        if reg_solve(work, step, d) != ok { ret (iteration, Singular) }
        var largest = 0.0f64
        j = 0usize
        while j < d {
            coefficients[j] += step[j]
            let move = math.abs[f64](step[j])
            if move > largest { largest = move }
            j += 1usize
        }
        iteration += 1u32
        if largest < tolerance { converged = true }
    }
    let covariance_error = reg_covariance(hessian, covariance, d, step, work)
    if covariance_error != ok { ret (iteration, covariance_error) }
    ret (iteration, ok)
}

// The negative log-likelihood at `params` (`threshold`, `levels - 2` log
// gaps, then `d` slopes): cumulative-logit proportional odds with the linear
// predictor clamped to +-30. `1e300` where a level probability vanishes.
fn ordinal_objective(ctx: *OrdinalCtx, params: []const f64) -> f64 {
    let total = ctx.levels - 1usize + ctx.d
    if params.len != total { ret 1.0e300f64 }
    var alpha = 0.0f64
    var cumulative = 0.0f64
    var i = 0usize
    while i < ctx.n {
        if usize(ctx.y[i]) >= ctx.levels { ret 1.0e300f64 }
        var eta = 0.0f64
        var a = 0usize
        while a < ctx.d {
            eta += ctx.x[i * ctx.d + a] * params[ctx.levels - 1usize + a]
            a += 1usize
        }
        if eta > 30.0f64 { eta = 30.0f64 }
        if eta < 0.0f64 - 30.0f64 { eta = 0.0f64 - 30.0f64 }
        let level = usize(ctx.y[i])
        var lo = 0.0f64
        if level > 0usize {
            alpha = params[0usize]
            var k = 1usize
            while k <= level - 1usize {
                alpha += math.exp[f64](params[k])
                k += 1usize
            }
            var z = alpha - eta
            if z > 30.0f64 { z = 30.0f64 }
            if z < 0.0f64 - 30.0f64 { z = 0.0f64 - 30.0f64 }
            lo = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - z))
        }
        var hi = 1.0f64
        if level < ctx.levels - 1usize {
            alpha = params[0usize]
            var k = 1usize
            while k <= level {
                alpha += math.exp[f64](params[k])
                k += 1usize
            }
            var z = alpha - eta
            if z > 30.0f64 { z = 30.0f64 }
            if z < 0.0f64 - 30.0f64 { z = 0.0f64 - 30.0f64 }
            hi = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - z))
        }
        let p = hi - lo
        if !(p > 0.0f64) { ret 1.0e300f64 }
        cumulative += math.log[f64](p)
        i += 1usize
    }
    ret 0.0f64 - cumulative
}

// Proportional-odds ordinal logistic regression: `P(y <= j) = sigmoid(
// alpha_j - x beta)` with increasing thresholds over `levels` codes
// (`y < levels`), the gaps riding log scale so no order is violated. Answers
// Nelder-Mead rounds, the `levels - 1` thresholds then the `d` slopes, and
// the model-based covariance from a numeric Hessian. `scratch.len >=
// (q + 1)^2 + 4 * q + 2 * q * q + q` with `q = levels - 1 + d`.
fn ordinal_logistic(x: []const f64, y: []const u8, n: usize, d: usize, levels: usize, tolerance: f64, max_iterations: u32, thresholds: []f64, coefficients: []f64, covariance: []f64, scratch: []f64) -> (u32, err) {
    let q = levels - 1usize + d
    if x.len < n * d || y.len < n || thresholds.len < levels - 1usize || coefficients.len < d || covariance.len < q * q { ret (0u32, TooSmall) }
    if n == 0usize || levels < 2usize { ret (0u32, Invalid) }
    if !(tolerance > 0.0f64) || max_iterations == 0u32 { ret (0u32, Invalid) }
    if scratch.len < (q + 1usize) * (q + 1usize) + 4usize * q + 2usize * q * q + q { ret (0u32, TooSmall) }
    var i = 0usize
    while i < n {
        if usize(y[i]) >= levels { ret (0u32, Invalid) }
        i += 1usize
    }
    var ctx = OrdinalCtx { x: x, y: y, n: n, d: d, levels: levels }
    var at = 0usize
    var params = scratch[at..at + q]
    at += q
    var nm = scratch[at..at + (q + 1usize) * (q + 1usize) + 4usize * q]
    at += (q + 1usize) * (q + 1usize) + 4usize * q
    var hessian = scratch[at..at + q * q]
    at += q * q
    var sys = scratch[at..at + q * q]
    at += q * q
    var rhs = scratch[at..at + q]
    i = 0usize
    while i < q {
        params[i] = 0.0f64
        i += 1usize
    }
    let (result, nm_error) = opt.nelder_mead[OrdinalCtx](&ctx, ordinal_objective, params, 1.0f64, tolerance, max_iterations, nm)
    if nm_error != ok { ret (0u32, nm_error) }
    var alpha = params[0usize]
    thresholds[0usize] = alpha
    var k = 1usize
    while k < levels - 1usize {
        alpha += math.exp[f64](params[k])
        thresholds[k] = alpha
        k += 1usize
    }
    i = 0usize
    while i < d {
        coefficients[i] = params[levels - 1usize + i]
        i += 1usize
    }
    i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            let hi = math.abs[f64](params[i]) + 1.0f64
            let hj = math.abs[f64](params[j]) + 1.0f64
            let si = 0.00001f64 * hi
            let sj = 0.00001f64 * hj
            let base = params[i]
            let query = params[j]
            if i == j {
                params[i] = base + si
                let up = ordinal_objective(&ctx, params)
                params[i] = base
                let mid = ordinal_objective(&ctx, params)
                params[i] = base - si
                let down = ordinal_objective(&ctx, params)
                params[i] = base
                hessian[i * q + j] = (up - 2.0f64 * mid + down) / (si * si)
            } else {
                params[i] = base + si
                params[j] = query + sj
                let pp = ordinal_objective(&ctx, params)
                params[j] = query - sj
                let pm = ordinal_objective(&ctx, params)
                params[i] = base - si
                params[j] = query + sj
                let mp = ordinal_objective(&ctx, params)
                params[j] = query - sj
                let mm = ordinal_objective(&ctx, params)
                params[i] = base
                params[j] = query
                hessian[i * q + j] = (pp - pm - mp + mm) / (4.0f64 * si * sj)
            }
            j += 1usize
        }
        i += 1usize
    }
    var c = 0usize
    while c < q {
        var j = 0usize
        while j < q * q {
            sys[j] = hessian[j]
            j += 1usize
        }
        j = 0usize
        while j < q {
            if j == c {
                rhs[j] = 1.0f64
            } else {
                rhs[j] = 0.0f64
            }
            j += 1usize
        }
        let column_error = reg_solve(sys, rhs, q)
        if column_error != ok { ret (result.iterations, column_error) }
        j = 0usize
        while j < q {
            covariance[j * q + c] = rhs[j]
            j += 1usize
        }
        c += 1usize
    }
    ret (result.iterations, ok)
}
