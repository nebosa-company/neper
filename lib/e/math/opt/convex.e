// Interior-point solvers for linear and convex quadratic programmes in caller
// storage: one infeasible-start primal-dual path-following method (a dense
// Newton system with partial pivoting, fraction-to-boundary steps, the
// centring parameter 0.1) behind `interior_point` for `max c·x` and
// `quadratic_program` for `min ½ x·Q x + c·x`, both subject to `A x <= b` and
// `x >= 0` with `A` row-major `m × n`. An equality is two inequalities.
//
// The solvers answer the objective and the iteration count; a programme
// that is infeasible or unbounded never reaches the tolerance and is
// reported as `Stalled` when `max_iterations` runs out. Scratch is
// `(n + m)^2 + 4 (n + m)` floats.

use e.math

type Result = struct { value: f64, iterations: u32 }
error TooSmall
error Invalid
error Stalled
error Singular

// `max c·x` subject to `A x <= b`, `x >= 0`.
fn interior_point(c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let (r, failure) = solve(a, c, a, b, m, n, true, x, tolerance, max_iterations, scratch)
    if failure != ok { ret (zero, failure) }
    ret (Result { value: 0.0f64 - r.value, iterations: r.iterations }, ok)
}

// `min ½ x·Q x + c·x` subject to `A x <= b`, `x >= 0`, with `Q` symmetric
// positive semidefinite, row-major `n × n`.
fn quadratic_program(q: []const f64, c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    if q.len < n * n { ret (zero, TooSmall) }
    let (r, failure) = solve(q, c, a, b, m, n, false, x, tolerance, max_iterations, scratch)
    ret (r, failure)
}

// The shared method; `linear` ignores `q` and negates `c` (maximisation).
fn solve(q: []const f64, c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, linear: bool, x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let width = n + m
    if c.len < n || a.len < m * n || b.len < m || x.len < n || scratch.len < width * width + 4usize * width { ret (zero, TooSmall) }
    if n == 0usize || tolerance <= 0.0f64 { ret (zero, Invalid) }
    var kkt = scratch[..width * width]
    var at = width * width
    var rhs = scratch[at..at + width]
    at += width
    var z = scratch[at..at + n]
    at += n
    var y = scratch[at..at + m]
    at += m
    var w = scratch[at..at + m]
    at += m
    var dual = scratch[at..at + n]
    at += n
    var primal = scratch[at..at + m]
    var i = 0usize
    while i < n {
        x[i] = 1.0f64
        z[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        y[i] = 1.0f64
        w[i] = 1.0f64
        i += 1usize
    }
    var iteration = 0u32
    while iteration < max_iterations {
        // Residuals: dual = Q x + c - z + Aᵀ y, primal = A x + w - b.
        var worst = 0.0f64
        i = 0usize
        while i < n {
            var s = c[i]
            if linear { s = 0.0f64 - c[i] }
            var k = 0usize
            if !linear {
                while k < n {
                    s += q[i * n + k] * x[k]
                    k += 1usize
                }
            }
            k = 0usize
            while k < m {
                s += a[k * n + i] * y[k]
                k += 1usize
            }
            dual[i] = s - z[i]
            worst = math.max[f64](worst, math.abs[f64](dual[i]))
            i += 1usize
        }
        i = 0usize
        while i < m {
            var s = w[i] - b[i]
            var k = 0usize
            while k < n {
                s += a[i * n + k] * x[k]
                k += 1usize
            }
            primal[i] = s
            worst = math.max[f64](worst, math.abs[f64](primal[i]))
            i += 1usize
        }
        var gap = 0.0f64
        i = 0usize
        while i < n {
            gap += x[i] * z[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            gap += w[i] * y[i]
            i += 1usize
        }
        if worst <= tolerance && gap <= tolerance {
            ret (Result { value: objective(q, c, n, linear, x), iterations: iteration }, ok)
        }
        let mu = 0.1f64 * gap / f64(width)
        // The reduced Newton system in (dx, dy):
        //   [Q + Z/X   Aᵀ  ] [dx]   [-dual + mu/x - z]
        //   [A        -W/Y ] [dy] = [-primal - mu/y + w]
        i = 0usize
        while i < width * width {
            kkt[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            if !linear {
                var k = 0usize
                while k < n {
                    kkt[i * width + k] = q[i * n + k]
                    k += 1usize
                }
            }
            kkt[i * width + i] += z[i] / x[i]
            var k = 0usize
            while k < m {
                kkt[i * width + n + k] = a[k * n + i]
                kkt[(n + k) * width + i] = a[k * n + i]
                k += 1usize
            }
            rhs[i] = mu / x[i] - z[i] - dual[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            kkt[(n + i) * width + n + i] = 0.0f64 - w[i] / y[i]
            rhs[n + i] = w[i] - mu / y[i] - primal[i]
            i += 1usize
        }
        if gaussian_solve(kkt, rhs, width) != ok { ret (zero, Singular) }
        // Recover dz and dw, then the longest step keeping everything positive.
        var step_primal = 1.0f64
        var step_dual = 1.0f64
        i = 0usize
        while i < n {
            let dx = rhs[i]
            let dz = mu / x[i] - z[i] - z[i] / x[i] * dx
            if dx < 0.0f64 { step_primal = math.min[f64](step_primal, 0.0f64 - x[i] / dx) }
            if dz < 0.0f64 { step_dual = math.min[f64](step_dual, 0.0f64 - z[i] / dz) }
            dual[i] = dz
            i += 1usize
        }
        i = 0usize
        while i < m {
            let dy = rhs[n + i]
            let dw = mu / y[i] - w[i] - w[i] / y[i] * dy
            if dw < 0.0f64 { step_primal = math.min[f64](step_primal, 0.0f64 - w[i] / dw) }
            if dy < 0.0f64 { step_dual = math.min[f64](step_dual, 0.0f64 - y[i] / dy) }
            primal[i] = dw
            i += 1usize
        }
        let step = 0.995f64 * math.min[f64](step_primal, step_dual)
        i = 0usize
        while i < n {
            x[i] += step * rhs[i]
            z[i] += step * dual[i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            y[i] += step * rhs[n + i]
            w[i] += step * primal[i]
            i += 1usize
        }
        iteration += 1u32
    }
    ret (zero, Stalled)
}

fn objective(q: []const f64, c: []const f64, n: usize, linear: bool, x: []const f64) -> f64 {
    var value = 0.0f64
    var i = 0usize
    while i < n {
        if linear {
            value -= c[i] * x[i]
        } else {
            value += c[i] * x[i]
            var k = 0usize
            while k < n {
                value += 0.5f64 * x[i] * q[i * n + k] * x[k]
                k += 1usize
            }
        }
        i += 1usize
    }
    ret value
}

// Solve the dense `n × n` system in place by Gaussian elimination with
// partial pivoting; the answer replaces `rhs`.
fn gaussian_solve(matrix: []f64, rhs: []f64, n: usize) -> err {
    var column = 0usize
    while column < n {
        var pivot = column
        var row = column + 1usize
        while row < n {
            if math.abs[f64](matrix[row * n + column]) > math.abs[f64](matrix[pivot * n + column]) { pivot = row }
            row += 1usize
        }
        if math.abs[f64](matrix[pivot * n + column]) < 1.0e-300f64 { ret Singular }
        if pivot != column {
            var k = 0usize
            while k < n {
                let t = matrix[column * n + k]
                matrix[column * n + k] = matrix[pivot * n + k]
                matrix[pivot * n + k] = t
                k += 1usize
            }
            let t = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = t
        }
        row = column + 1usize
        while row < n {
            let factor = matrix[row * n + column] / matrix[column * n + column]
            if factor != 0.0f64 {
                var k = column
                while k < n {
                    matrix[row * n + k] -= factor * matrix[column * n + k]
                    k += 1usize
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
        var k = i + 1usize
        while k < n {
            s -= matrix[i * n + k] * rhs[k]
            k += 1usize
        }
        rhs[i] = s / matrix[i * n + i]
    }
    ret ok
}
