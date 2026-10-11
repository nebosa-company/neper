// Linear models over row-major `f64` samples (`n` rows of `d` features) in
// caller storage. Every fit answers `d + 1` coefficients, the intercept
// last: `ols` solves the normal equations (Gaussian elimination with
// partial pivoting, `Singular` when they have no unique solution), `ridge`
// adds `lambda` to the diagonal (the intercept unpenalised), `lasso` runs
// coordinate descent with soft thresholding, and `logistic` fits a binary
// classifier by Newton's method on the log loss (with a small ridge so a
// separable problem still converges). `predict` and `predict_probability`
// apply the coefficients.

use e.math

error TooSmall
error Singular
error Invalid

// Solve the dense `k × k` system in place; the answer replaces `rhs`.
fn solve(matrix: []f64, rhs: []f64, k: usize) -> err {
    var column = 0usize
    while column < k {
        var pivot = column
        var row = column + 1usize
        while row < k {
            if math.abs[f64](matrix[row * k + column]) > math.abs[f64](matrix[pivot * k + column]) { pivot = row }
            row += 1usize
        }
        if math.abs[f64](matrix[pivot * k + column]) < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var c = 0usize
            while c < k {
                let t = matrix[column * k + c]
                matrix[column * k + c] = matrix[pivot * k + c]
                matrix[pivot * k + c] = t
                c += 1usize
            }
            let t = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = t
        }
        row = column + 1usize
        while row < k {
            let factor = matrix[row * k + column] / matrix[column * k + column]
            if factor != 0.0f64 {
                var c = column
                while c < k {
                    matrix[row * k + c] -= factor * matrix[column * k + c]
                    c += 1usize
                }
                rhs[row] -= factor * rhs[column]
            }
            row += 1usize
        }
        column += 1usize
    }
    var i = k
    while i > 0usize {
        i -= 1usize
        var s = rhs[i]
        var c = i + 1usize
        while c < k {
            s -= matrix[i * k + c] * rhs[c]
            c += 1usize
        }
        rhs[i] = s / matrix[i * k + i]
    }
    ret ok
}

// The feature `j` of sample `i`, the intercept column being `j == d`.
fn at(x: []const f64, d: usize, i: usize, j: usize) -> f64 {
    if j == d { ret 1.0f64 }
    ret x[i * d + j]
}

// Accumulate XᵀX (+ `lambda` on the feature diagonal) and Xᵀy into `matrix`
// (`k × k`) and `rhs` (`k`), `k = d + 1`.
fn normal_equations(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, matrix: []f64, rhs: []f64) {
    let k = d + 1usize
    var i = 0usize
    while i < k * k {
        matrix[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        rhs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var a = 0usize
        while a < k {
            let xa = at(x, d, i, a)
            rhs[a] += xa * y[i]
            var b = 0usize
            while b < k {
                matrix[a * k + b] += xa * at(x, d, i, b)
                b += 1usize
            }
            a += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < d {
        matrix[i * k + i] += lambda
        i += 1usize
    }
}

// Ordinary least squares; `coefficients.len >= d + 1`, `scratch.len >= (d + 1)^2`.
fn ols(x: []const f64, y: []const f64, n: usize, d: usize, coefficients: []f64, scratch: []f64) -> err {
    ret ridge(x, y, n, d, 0.0f64, coefficients, scratch)
}

// Ridge regression with penalty `lambda` on the feature weights.
fn ridge(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, coefficients: []f64, scratch: []f64) -> err {
    let k = d + 1usize
    if x.len < n * d || y.len < n || coefficients.len < k || scratch.len < k * k { ret TooSmall }
    if lambda < 0.0f64 { ret Invalid }
    normal_equations(x, y, n, d, lambda, scratch[..k * k], coefficients[..k])
    ret solve(scratch[..k * k], coefficients[..k], k)
}

// Lasso by cyclic coordinate descent on `(1 / 2n) Σ (y - Xβ)² + lambda Σ |β_j|`,
// the intercept unpenalised, until no coefficient moves by more than
// `tolerance` or `max_sweeps` pass; `scratch.len >= n`.
fn lasso(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, tolerance: f64, max_sweeps: u32, coefficients: []f64, scratch: []f64) -> err {
    ret elastic_net(x, y, n, d, lambda, 1.0f64, tolerance, max_sweeps, coefficients, scratch)
}

// Elastic net by cyclic coordinate descent on
// `(1 / 2n) Σ (y - Xβ)² + lambda (l1_ratio Σ |β_j| + (1 - l1_ratio) / 2 Σ β_j²)`
// (scikit-learn's `ElasticNet` with `alpha = lambda`), the intercept unpenalised;
// `l1_ratio = 1` is the lasso. `scratch.len >= n`.
fn elastic_net(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, l1_ratio: f64, tolerance: f64, max_sweeps: u32, coefficients: []f64, scratch: []f64) -> err {
    let k = d + 1usize
    if x.len < n * d || y.len < n || coefficients.len < k || scratch.len < n { ret TooSmall }
    if lambda < 0.0f64 || n == 0usize || !(l1_ratio >= 0.0f64 && l1_ratio <= 1.0f64) { ret Invalid }
    var residual = scratch[..n]
    var j = 0usize
    while j < k {
        coefficients[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        residual[i] = y[i]
        i += 1usize
    }
    var sweep = 0u32
    var moved = true
    while sweep < max_sweeps && moved {
        moved = false
        j = 0usize
        while j < k {
            // Partial residual correlation and the column's energy.
            var rho = 0.0f64
            var energy = 0.0f64
            i = 0usize
            while i < n {
                let xij = at(x, d, i, j)
                rho += xij * (residual[i] + xij * coefficients[j])
                energy += xij * xij
                i += 1usize
            }
            var updated = 0.0f64
            if energy > 0.0f64 {
                if j == d {
                    updated = rho / energy
                } else {
                    let threshold = lambda * l1_ratio * f64(n)
                    let denominator = energy + lambda * (1.0f64 - l1_ratio) * f64(n)
                    if rho > threshold {
                        updated = (rho - threshold) / denominator
                    } else if rho < 0.0f64 - threshold {
                        updated = (rho + threshold) / denominator
                    }
                }
            }
            let change = updated - coefficients[j]
            if math.abs[f64](change) > tolerance { moved = true }
            if change != 0.0f64 {
                i = 0usize
                while i < n {
                    residual[i] -= change * at(x, d, i, j)
                    i += 1usize
                }
                coefficients[j] = updated
            }
            j += 1usize
        }
        sweep += 1u32
    }
    ret ok
}

fn sigmoid(z: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - z)) }

// The linear score of sample `i` under `coefficients`.
fn predict(x: []const f64, d: usize, i: usize, coefficients: []const f64) -> f64 {
    var s = coefficients[d]
    var j = 0usize
    while j < d {
        s += coefficients[j] * x[i * d + j]
        j += 1usize
    }
    ret s
}

fn predict_probability(x: []const f64, d: usize, i: usize, coefficients: []const f64) -> f64 { ret sigmoid(predict(x, d, i, coefficients)) }

// Logistic regression on labels `y` in {0, 1} by Newton's method with a
// ridge of `lambda` (a small value keeps separable data finite), stopping
// when the step is under `tolerance` or after `max_iterations`;
// `scratch.len >= (d + 1)^2 + 2 (d + 1)`.
fn logistic(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, tolerance: f64, max_iterations: u32, coefficients: []f64, scratch: []f64) -> (u32, err) {
    let k = d + 1usize
    if x.len < n * d || y.len < n || coefficients.len < k || scratch.len < k * k + 2usize * k { ret (0u32, TooSmall) }
    if lambda < 0.0f64 { ret (0u32, Invalid) }
    var hessian = scratch[..k * k]
    var gradient = scratch[k * k..k * k + k]
    var step = scratch[k * k + k..k * k + 2usize * k]
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
        var i = 0usize
        while i < n {
            let p = predict_probability(x, d, i, coefficients)
            let w = p * (1.0f64 - p)
            var a = 0usize
            while a < k {
                let xa = at(x, d, i, a)
                gradient[a] += xa * (p - y[i])
                var b = 0usize
                while b < k {
                    hessian[a * k + b] += w * xa * at(x, d, i, b)
                    b += 1usize
                }
                a += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < d {
            gradient[j] += lambda * coefficients[j]
            hessian[j * k + j] += lambda
            j += 1usize
        }
        j = 0usize
        while j < k {
            step[j] = gradient[j]
            j += 1usize
        }
        if solve(hessian, step, k) != ok { ret (iteration, Singular) }
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
    ret (iteration, ok)
}

// Solve the dense `c × c` system in place for the principal regression;
// the answer replaces `rhs`. `Singular` below 1e-12 pivots.
fn pls_solve(matrix: []f64, rhs: []f64, c: usize) -> err {
    var column = 0usize
    while column < c {
        var pivot = column
        var row = column + 1usize
        while row < c {
            if math.abs[f64](matrix[row * c + column]) > math.abs[f64](matrix[pivot * c + column]) { pivot = row }
            row += 1usize
        }
        if math.abs[f64](matrix[pivot * c + column]) < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var swap = 0usize
            while swap < c {
                let t = matrix[column * c + swap]
                matrix[column * c + swap] = matrix[pivot * c + swap]
                matrix[pivot * c + swap] = t
                swap += 1usize
            }
            let t = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = t
        }
        row = column + 1usize
        while row < c {
            let factor = matrix[row * c + column] / matrix[column * c + column]
            if factor != 0.0f64 {
                var e = column
                while e < c {
                    matrix[row * c + e] -= factor * matrix[column * c + e]
                    e += 1usize
                }
                rhs[row] -= factor * rhs[column]
            }
            row += 1usize
        }
        column += 1usize
    }
    var i = c
    while i > 0usize {
        i -= 1usize
        var s = rhs[i]
        var e = i + 1usize
        while e < c {
            s -= matrix[i * c + e] * rhs[e]
            e += 1usize
        }
        rhs[i] = s / matrix[i * c + i]
    }
    ret ok
}

// Partial least squares (PLS1, NIPALS) of `y` on `x` (`n × d`) with
// `components` latent directions: centered NIPALS deflation, then the
// principal regression over the loadings solved in place. Answers `d + 1`
// coefficients, the intercept last, as `ols` does.
// `scratch.len >= n * d + 2 * n + 2 * d + components * (components + 2)`
// holds the deflated copies, one direction at a time, and the solve.
// `Invalid` with no components, more components than features, or a round
// whose covariance direction vanishes exactly; a constant target yields
// near-zero slopes with the mean as intercept (no error).
fn pls(x: []const f64, y: []const f64, n: usize, d: usize, components: usize, coefficients: []f64, scratch: []f64) -> err {
    let c = components
    if x.len < n * d || y.len < n || coefficients.len < d + 1usize || scratch.len < n * d + 2usize * n + 2usize * d + c * (c + 2usize) { ret TooSmall }
    if n == 0usize || d == 0usize || c == 0usize || c > d { ret Invalid }
    var xw = scratch[..n * d]
    var off = n * d
    var yw = scratch[off..off + n]
    off += n
    var mean_x = scratch[off..off + d]
    off += d
    var direction = scratch[off..off + d]
    off += d
    var scores = scratch[off..off + n]
    off += n
    var weights = scratch[off..off + d * c]
    off += d * c
    var loadings = scratch[off..off + d * c]
    off += d * c
    var system = scratch[off..off + c * c]
    off += c * c
    var response = scratch[off..off + c]
    var mean_y = 0.0f64
    var i = 0usize
    while i < n {
        mean_y += y[i] / f64(n)
        i += 1usize
    }
    var j = 0usize
    while j < d {
        mean_x[j] = 0.0f64
        i = 0usize
        while i < n {
            mean_x[j] += x[i * d + j] / f64(n)
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        yw[i] = y[i] - mean_y
        j = 0usize
        while j < d {
            xw[i * d + j] = x[i * d + j] - mean_x[j]
            j += 1usize
        }
        i += 1usize
    }
    var a = 0usize
    while a < c {
        j = 0usize
        while j < d {
            direction[j] = 0.0f64
            i = 0usize
            while i < n {
                direction[j] += xw[i * d + j] * yw[i]
                i += 1usize
            }
            j += 1usize
        }
        var energy = 0.0f64
        j = 0usize
        while j < d {
            energy += direction[j] * direction[j]
            j += 1usize
        }
        if energy == 0.0f64 { ret Invalid }
        let norm = math.sqrt[f64](energy)
        j = 0usize
        while j < d {
            direction[j] = direction[j] / norm
            weights[j * c + a] = direction[j]
            j += 1usize
        }
        i = 0usize
        while i < n {
            scores[i] = 0.0f64
            j = 0usize
            while j < d {
                scores[i] += xw[i * d + j] * direction[j]
                j += 1usize
            }
            i += 1usize
        }
        var spread = 0.0f64
        i = 0usize
        while i < n {
            spread += scores[i] * scores[i]
            i += 1usize
        }
        if spread == 0.0f64 { ret Invalid }
        j = 0usize
        while j < d {
            var loading = 0.0f64
            i = 0usize
            while i < n {
                loading += xw[i * d + j] * scores[i]
                i += 1usize
            }
            loadings[j * c + a] = loading / spread
            j += 1usize
        }
        var answer = 0.0f64
        i = 0usize
        while i < n {
            answer += yw[i] * scores[i]
            i += 1usize
        }
        answer = answer / spread
        response[a] = answer
        i = 0usize
        while i < n {
            j = 0usize
            while j < d {
                xw[i * d + j] -= scores[i] * loadings[j * c + a]
                j += 1usize
            }
            yw[i] -= scores[i] * answer
            i += 1usize
        }
        a += 1usize
    }
    var r = 0usize
    while r < c {
        var s = 0usize
        while s < c {
            var entry = 0.0f64
            j = 0usize
            while j < d {
                entry += loadings[j * c + r] * weights[j * c + s]
                j += 1usize
            }
            system[r * c + s] = entry
            s += 1usize
        }
        r += 1usize
    }
    let solve_error = pls_solve(system, response, c)
    if solve_error != ok { ret solve_error }
    j = 0usize
    while j < d {
        var beta = 0.0f64
        var s = 0usize
        while s < c {
            beta += weights[j * c + s] * response[s]
            s += 1usize
        }
        coefficients[j] = beta
        j += 1usize
    }
    var correction = 0.0f64
    j = 0usize
    while j < d {
        correction += coefficients[j] * mean_x[j]
        j += 1usize
    }
    coefficients[d] = mean_y - correction
    ret ok
}

// The next combination (with repetition when `repeat`) of `idx.len` indices in
// `0..d`, in lexicographic order; `false` after the last.
fn next_combination(idx: []usize, d: usize, repeat: bool) -> bool {
    let r = idx.len
    var i = r
    while i > 0usize {
        i -= 1usize
        var limit = d - 1usize
        if !repeat { limit = d - r + i }
        if idx[i] < limit {
            idx[i] += 1usize
            var j = i + 1usize
            while j < r {
                if repeat { idx[j] = idx[i] } else { idx[j] = idx[j - 1usize] + 1usize }
                j += 1usize
            }
            ret true
        }
    }
    ret false
}

// The number of columns `polynomial_features` writes: every monomial of degree
// 1..`degree` in `d` features (`interaction_only` keeps distinct features), and a
// leading constant when `include_bias`. `degree` is at most 16.
fn polynomial_width(d: usize, degree: usize, interaction_only: bool, include_bias: bool) -> usize {
    var count = 0usize
    if include_bias { count = 1usize }
    if d == 0usize || degree > 16usize { ret count }
    var idx: [16]usize = zero
    var deg = 1usize
    while deg <= degree {
        if !interaction_only || deg <= d {
            var j = 0usize
            while j < deg {
                if interaction_only { idx[j] = j } else { idx[j] = 0usize }
                j += 1usize
            }
            count += 1usize
            while next_combination(idx[..deg], d, !interaction_only) { count += 1usize }
        }
        deg += 1usize
    }
    ret count
}

// Polynomial feature expansion of `n` rows of `d` features in scikit-learn's
// column order (bias, then each degree's combinations lexicographically), into
// row-major `out` of `polynomial_width` columns; answers that width.
fn polynomial_features(x: []const f64, n: usize, d: usize, degree: usize, interaction_only: bool, include_bias: bool, out: []f64) -> (usize, err) {
    if d == 0usize || degree == 0usize || degree > 16usize { ret (0usize, Invalid) }
    let width = polynomial_width(d, degree, interaction_only, include_bias)
    if x.len < n * d || out.len < n * width { ret (0usize, TooSmall) }
    var col = 0usize
    var i = 0usize
    if include_bias {
        while i < n {
            out[i * width] = 1.0f64
            i += 1usize
        }
        col = 1usize
    }
    var idx: [16]usize = zero
    var deg = 1usize
    while deg <= degree {
        if !interaction_only || deg <= d {
            var j = 0usize
            while j < deg {
                if interaction_only { idx[j] = j } else { idx[j] = 0usize }
                j += 1usize
            }
            var more = true
            while more {
                i = 0usize
                while i < n {
                    var product = 1.0f64
                    j = 0usize
                    while j < deg {
                        product *= x[i * d + idx[j]]
                        j += 1usize
                    }
                    out[i * width + col] = product
                    i += 1usize
                }
                col += 1usize
                more = next_combination(idx[..deg], d, !interaction_only)
            }
        }
        deg += 1usize
    }
    ret (width, ok)
}

// Weighted normal equations: XᵀWX (+ `lambda` on the feature diagonal) and XᵀWy.
fn weighted_normal(x: []const f64, y: []const f64, w: []const f64, n: usize, d: usize, lambda: f64, matrix: []f64, rhs: []f64) {
    let k = d + 1usize
    var i = 0usize
    while i < k * k {
        matrix[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        rhs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var a = 0usize
        while a < k {
            let xa = w[i] * at(x, d, i, a)
            rhs[a] += xa * y[i]
            var b = 0usize
            while b < k {
                matrix[a * k + b] += xa * at(x, d, i, b)
                b += 1usize
            }
            a += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < d {
        matrix[i * k + i] += lambda
        i += 1usize
    }
}

// The check (pinball) loss of the fit: Σ rho_tau(y - Xβ).
fn pinball_loss(x: []const f64, y: []const f64, n: usize, d: usize, tau: f64, coefficients: []const f64) -> f64 {
    var loss = 0.0f64
    var i = 0usize
    while i < n {
        let r = y[i] - predict(x, d, i, coefficients)
        if r >= 0.0f64 { loss += tau * r } else { loss += (tau - 1.0f64) * r }
        i += 1usize
    }
    ret loss
}

// Quantile regression at level `tau` in (0, 1): iteratively reweighted least
// squares on the check loss from the OLS fit, then the exact vertex polish --
// the `d + 1` rows with the smallest residuals are interpolated and kept while
// the loss does not rise -- so the answer is the linear-programming optimum
// (what scikit-learn's `QuantileRegressor(alpha=0, solver="highs")` returns)
// when it is unique. Answers the IRLS iteration count.
// `scratch.len >= (d + 1)^2 + 3 (d + 1) + 2 n`.
fn quantile_regression(x: []const f64, y: []const f64, n: usize, d: usize, tau: f64, tolerance: f64, max_iterations: u32, coefficients: []f64, scratch: []f64) -> (u32, err) {
    let k = d + 1usize
    if x.len < n * d || y.len < n || coefficients.len < k || scratch.len < k * k + 3usize * k + 2usize * n { ret (0u32, TooSmall) }
    if !(tau > 0.0f64 && tau < 1.0f64) || n < k { ret (0u32, Invalid) }
    var matrix = scratch[..k * k]
    var rhs = scratch[k * k..k * k + k]
    var trial = scratch[k * k + k..k * k + 2usize * k]
    var chosen = scratch[k * k + 2usize * k..k * k + 3usize * k]
    var w = scratch[k * k + 3usize * k..k * k + 3usize * k + n]
    var r = scratch[k * k + 3usize * k + n..k * k + 3usize * k + 2usize * n]
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    weighted_normal(x, y, w, n, d, 0.0f64, matrix, rhs)
    if solve(matrix, rhs, k) != ok { ret (0u32, Singular) }
    var j = 0usize
    while j < k {
        coefficients[j] = rhs[j]
        j += 1usize
    }
    var iteration = 0u32
    while iteration < max_iterations {
        i = 0usize
        while i < n {
            let res = y[i] - predict(x, d, i, coefficients)
            var scale = math.abs[f64](res)
            if scale < 1.0e-7f64 { scale = 1.0e-7f64 }
            if res >= 0.0f64 { w[i] = tau / scale } else { w[i] = (1.0f64 - tau) / scale }
            i += 1usize
        }
        weighted_normal(x, y, w, n, d, 0.0f64, matrix, rhs)
        if solve(matrix, rhs, k) != ok { break }
        var moved = 0.0f64
        j = 0usize
        while j < k {
            let change = math.abs[f64](rhs[j] - coefficients[j])
            if change > moved { moved = change }
            coefficients[j] = rhs[j]
            j += 1usize
        }
        iteration += 1u32
        if moved < tolerance { break }
    }
    // Vertex polish.
    var pass = 0usize
    while pass < 20usize {
        i = 0usize
        while i < n {
            r[i] = math.abs[f64](y[i] - predict(x, d, i, coefficients))
            i += 1usize
        }
        j = 0usize
        while j < k {
            var best = 0usize
            i = 1usize
            while i < n {
                if r[i] < r[best] { best = i }
                i += 1usize
            }
            chosen[j] = f64(best)
            r[best] = 1.0e300f64
            j += 1usize
        }
        j = 0usize
        while j < k {
            let row = usize(chosen[j])
            var c = 0usize
            while c < k {
                matrix[j * k + c] = at(x, d, row, c)
                c += 1usize
            }
            rhs[j] = y[row]
            j += 1usize
        }
        if solve(matrix, rhs, k) != ok { break }
        j = 0usize
        while j < k {
            trial[j] = rhs[j]
            j += 1usize
        }
        let before = pinball_loss(x, y, n, d, tau, coefficients[..k])
        let after = pinball_loss(x, y, n, d, tau, trial)
        if after > before { break }
        j = 0usize
        while j < k {
            coefficients[j] = trial[j]
            j += 1usize
        }
        if after >= before - 1.0e-13f64 * (1.0f64 + before) { break }
        pass += 1usize
    }
    ret (iteration, ok)
}

// Median of the first `m` entries of `values`, which it reorders.
fn median_in_place(values: []f64, m: usize) -> f64 {
    var gap = m / 2usize
    while gap > 0usize {
        var i = gap
        while i < m {
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
    if m == 0usize { ret 0.0f64 }
    if m % 2usize == 1usize { ret values[m / 2usize] }
    ret 0.5f64 * (values[m / 2usize - 1usize] + values[m / 2usize])
}

// Huber M-estimation by iteratively reweighted least squares from the OLS fit
// (statsmodels `RLM` with `HuberT(t=threshold)`, scale by the median absolute
// residual over 0.6745): residuals within `threshold` scales get weight 1, the
// rest `threshold / |z|`. Answers the iteration count.
// `scratch.len >= (d + 1)^2 + 2 (d + 1) + 3 n`.
fn huber(x: []const f64, y: []const f64, n: usize, d: usize, threshold: f64, tolerance: f64, max_iterations: u32, coefficients: []f64, scratch: []f64) -> (u32, err) {
    let k = d + 1usize
    if x.len < n * d || y.len < n || coefficients.len < k || scratch.len < k * k + 2usize * k + 3usize * n { ret (0u32, TooSmall) }
    if !(threshold > 0.0f64) || n < k { ret (0u32, Invalid) }
    var matrix = scratch[..k * k]
    var rhs = scratch[k * k..k * k + k]
    var previous = scratch[k * k + k..k * k + 2usize * k]
    var w = scratch[k * k + 2usize * k..k * k + 2usize * k + n]
    var r = scratch[k * k + 2usize * k + n..k * k + 2usize * k + 2usize * n]
    var m = scratch[k * k + 2usize * k + 2usize * n..k * k + 2usize * k + 3usize * n]
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    weighted_normal(x, y, w, n, d, 0.0f64, matrix, rhs)
    if solve(matrix, rhs, k) != ok { ret (0u32, Singular) }
    var j = 0usize
    while j < k {
        coefficients[j] = rhs[j]
        j += 1usize
    }
    var iteration = 0u32
    while iteration < max_iterations {
        i = 0usize
        while i < n {
            r[i] = y[i] - predict(x, d, i, coefficients)
            m[i] = math.abs[f64](r[i])
            i += 1usize
        }
        let scale = median_in_place(m, n) / 0.6744897501960817f64
        if !(scale > 0.0f64) { break }
        i = 0usize
        while i < n {
            let z = math.abs[f64](r[i]) / scale
            if z <= threshold { w[i] = 1.0f64 } else { w[i] = threshold / z }
            i += 1usize
        }
        weighted_normal(x, y, w, n, d, 0.0f64, matrix, rhs)
        j = 0usize
        while j < k {
            previous[j] = coefficients[j]
            j += 1usize
        }
        if solve(matrix, rhs, k) != ok { break }
        var moved = 0.0f64
        j = 0usize
        while j < k {
            let change = math.abs[f64](rhs[j] - previous[j])
            if change > moved { moved = change }
            coefficients[j] = rhs[j]
            j += 1usize
        }
        iteration += 1u32
        if moved < tolerance { break }
    }
    ret (iteration, ok)
}
