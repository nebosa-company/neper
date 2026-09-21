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
    let k = d + 1usize
    if x.len < n * d || y.len < n || coefficients.len < k || scratch.len < n { ret TooSmall }
    if lambda < 0.0f64 || n == 0usize { ret Invalid }
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
                    let threshold = lambda * f64(n)
                    if rho > threshold {
                        updated = (rho - threshold) / energy
                    } else if rho < 0.0f64 - threshold {
                        updated = (rho + threshold) / energy
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
