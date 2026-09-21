// Continuous optimisation over `f64` vectors in caller storage: gradient
// descent, nonlinear conjugate gradient (Polak-Ribière), BFGS with a dense
// inverse Hessian, limited-memory BFGS, the Nelder-Mead simplex, and the
// two-phase dense simplex method for linear programmes.
//
// An objective is `f(ctx, x) -> f64` and its gradient `g(ctx, x, out)`; every
// descent method takes a step by backtracking (Armijo) line search from the
// caller's `x`, which it improves in place, and answers the final value with
// the iteration count and whether the gradient norm fell under `tolerance`.
// Scratch is the caller's, sized per declaration.

use e.math

type Result = struct { value: f64, iterations: u32, converged: bool }
error TooSmall
error Infeasible
error Unbounded
error Invalid

fn dot(a: []const f64, b: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < a.len {
        sum += a[i] * b[i]
        i += 1usize
    }
    ret sum
}

fn norm(a: []const f64) -> f64 { ret math.sqrt[f64](dot(a, a)) }

// Backtracking line search along `direction` from `x` (a descent direction):
// halves `step` until the Armijo condition holds; writes the new point to
// `trial` and answers the step taken (0 when none was accepted).
fn line_search[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []const f64, fx: f64, gradient: []const f64, direction: []const f64, trial: []f64, initial: f64) -> f64 {
    let slope = dot(gradient, direction)
    if slope >= 0.0f64 { ret 0.0f64 }
    var step = initial
    var tries = 0usize
    while tries < 60usize {
        var i = 0usize
        while i < x.len {
            trial[i] = x[i] + step * direction[i]
            i += 1usize
        }
        if f(ctx, trial) <= fx + 0.0001f64 * step * slope { ret step }
        step = step * 0.5f64
        tries += 1usize
    }
    ret 0.0f64
}

// Backtracking with the weak Wolfe curvature condition, by bisection on the
// bracket the Armijo test and the curvature test close from either side;
// `trial_gradient` holds the gradient at the returned point.
fn line_search_wolfe[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []const f64, fx: f64, gradient: []const f64, direction: []const f64, trial: []f64, trial_gradient: []f64) -> f64 {
    let slope = dot(gradient, direction)
    if slope >= 0.0f64 { ret 0.0f64 }
    var low = 0.0f64
    var high = 0.0f64
    var bracketed = false
    var step = 1.0f64
    var tries = 0usize
    while tries < 60usize {
        var i = 0usize
        while i < x.len {
            trial[i] = x[i] + step * direction[i]
            i += 1usize
        }
        if f(ctx, trial) > fx + 0.0001f64 * step * slope {
            high = step
            bracketed = true
        } else {
            g(ctx, trial, trial_gradient)
            if dot(trial_gradient, direction) < 0.9f64 * slope {
                low = step
            } else {
                ret step
            }
        }
        if bracketed { step = 0.5f64 * (low + high) } else { step = 2.0f64 * step }
        tries += 1usize
    }
    ret 0.0f64
}

// Steepest descent; `scratch.len >= 3 * n`.
fn gradient_descent[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, step: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if scratch.len < 3usize * n { ret (zero, TooSmall) }
    var gradient = scratch[..n]
    var direction = scratch[n..2usize * n]
    var trial = scratch[2usize * n..3usize * n]
    var fx = f(ctx, x)
    var i = 0u32
    while i < max_iterations {
        g(ctx, x, gradient)
        if norm(gradient) <= tolerance { ret (Result { value: fx, iterations: i, converged: true }, ok) }
        var k = 0usize
        while k < n {
            direction[k] = 0.0f64 - gradient[k]
            k += 1usize
        }
        let taken = line_search[Ctx](ctx, f, x, fx, gradient, direction, trial, step)
        if taken == 0.0f64 { ret (Result { value: fx, iterations: i, converged: false }, ok) }
        k = 0usize
        while k < n {
            x[k] = trial[k]
            k += 1usize
        }
        fx = f(ctx, x)
        i += 1u32
    }
    ret (Result { value: fx, iterations: i, converged: false }, ok)
}

// Nonlinear conjugate gradient (Polak-Ribière with restarts); `scratch.len >= 4 * n`.
fn conjugate_gradient[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if scratch.len < 4usize * n { ret (zero, TooSmall) }
    var gradient = scratch[..n]
    var previous = scratch[n..2usize * n]
    var direction = scratch[2usize * n..3usize * n]
    var trial = scratch[3usize * n..4usize * n]
    var fx = f(ctx, x)
    g(ctx, x, gradient)
    var k = 0usize
    while k < n {
        direction[k] = 0.0f64 - gradient[k]
        k += 1usize
    }
    var i = 0u32
    while i < max_iterations {
        if norm(gradient) <= tolerance { ret (Result { value: fx, iterations: i, converged: true }, ok) }
        let taken = line_search[Ctx](ctx, f, x, fx, gradient, direction, trial, 1.0f64)
        if taken == 0.0f64 {
            // Restart along the gradient before giving up.
            k = 0usize
            while k < n {
                direction[k] = 0.0f64 - gradient[k]
                k += 1usize
            }
            let again = line_search[Ctx](ctx, f, x, fx, gradient, direction, trial, 1.0f64)
            if again == 0.0f64 { ret (Result { value: fx, iterations: i, converged: false }, ok) }
        }
        k = 0usize
        while k < n {
            x[k] = trial[k]
            previous[k] = gradient[k]
            k += 1usize
        }
        fx = f(ctx, x)
        g(ctx, x, gradient)
        var numerator = 0.0f64
        k = 0usize
        while k < n {
            numerator += gradient[k] * (gradient[k] - previous[k])
            k += 1usize
        }
        let denominator = dot(previous, previous)
        var beta = 0.0f64
        if denominator > 0.0f64 { beta = numerator / denominator }
        if beta < 0.0f64 || (i + 1u32) % u32(n + 1usize) == 0u32 { beta = 0.0f64 }
        k = 0usize
        while k < n {
            direction[k] = 0.0f64 - gradient[k] + beta * direction[k]
            k += 1usize
        }
        i += 1u32
    }
    ret (Result { value: fx, iterations: i, converged: false }, ok)
}

// BFGS with a dense inverse Hessian; `scratch.len >= n * n + 6 * n`.
fn bfgs[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if scratch.len < n * n + 6usize * n { ret (zero, TooSmall) }
    var hinv = scratch[..n * n]
    var at = n * n
    var gradient = scratch[at..at + n]
    at += n
    var new_gradient = scratch[at..at + n]
    at += n
    var direction = scratch[at..at + n]
    at += n
    var trial = scratch[at..at + n]
    at += n
    var s = scratch[at..at + n]
    at += n
    var y = scratch[at..at + n]
    var i = 0usize
    while i < n * n {
        hinv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        hinv[i * n + i] = 1.0f64
        i += 1usize
    }
    var fx = f(ctx, x)
    g(ctx, x, gradient)
    var iteration = 0u32
    while iteration < max_iterations {
        if norm(gradient) <= tolerance { ret (Result { value: fx, iterations: iteration, converged: true }, ok) }
        // direction = -Hinv g
        i = 0usize
        while i < n {
            var sum = 0.0f64
            var j = 0usize
            while j < n {
                sum += hinv[i * n + j] * gradient[j]
                j += 1usize
            }
            direction[i] = 0.0f64 - sum
            i += 1usize
        }
        var taken = line_search[Ctx](ctx, f, x, fx, gradient, direction, trial, 1.0f64)
        if taken == 0.0f64 {
            // Reset the curvature and try steepest descent.
            i = 0usize
            while i < n * n {
                hinv[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < n {
                hinv[i * n + i] = 1.0f64
                direction[i] = 0.0f64 - gradient[i]
                i += 1usize
            }
            taken = line_search[Ctx](ctx, f, x, fx, gradient, direction, trial, 1.0f64)
            if taken == 0.0f64 { ret (Result { value: fx, iterations: iteration, converged: false }, ok) }
        }
        g(ctx, trial, new_gradient)
        i = 0usize
        while i < n {
            s[i] = trial[i] - x[i]
            y[i] = new_gradient[i] - gradient[i]
            x[i] = trial[i]
            gradient[i] = new_gradient[i]
            i += 1usize
        }
        fx = f(ctx, x)
        let sy = dot(s, y)
        if sy > 1.0e-12f64 {
            let rho = 1.0f64 / sy
            // Hinv = (I - rho s y') Hinv (I - rho y s') + rho s s', done in place
            // through the identity Hinv' = Hinv + rho(1 + rho y'Hy) s s' - rho (Hy s' + s y'H).
            // Hy into `direction` (free now), y'Hy scalar.
            i = 0usize
            while i < n {
                var sum = 0.0f64
                var j = 0usize
                while j < n {
                    sum += hinv[i * n + j] * y[j]
                    j += 1usize
                }
                direction[i] = sum
                i += 1usize
            }
            let yhy = dot(y, direction)
            let factor = rho * (1.0f64 + rho * yhy)
            i = 0usize
            while i < n {
                var j = 0usize
                while j < n {
                    hinv[i * n + j] += factor * s[i] * s[j] - rho * (direction[i] * s[j] + s[i] * direction[j])
                    j += 1usize
                }
                i += 1usize
            }
        }
        iteration += 1u32
    }
    ret (Result { value: fx, iterations: iteration, converged: false }, ok)
}

// L-BFGS keeping `memory` correction pairs; `scratch.len >= 2 * memory * n + 2 * memory + 4 * n`.
fn lbfgs[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, memory: usize, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if memory == 0usize { ret (zero, Invalid) }
    if scratch.len < 2usize * memory * n + 2usize * memory + 4usize * n { ret (zero, TooSmall) }
    var at = 0usize
    var s_store = scratch[at..at + memory * n]
    at += memory * n
    var y_store = scratch[at..at + memory * n]
    at += memory * n
    var rho = scratch[at..at + memory]
    at += memory
    var alpha = scratch[at..at + memory]
    at += memory
    var gradient = scratch[at..at + n]
    at += n
    var new_gradient = scratch[at..at + n]
    at += n
    var direction = scratch[at..at + n]
    at += n
    var trial = scratch[at..at + n]
    var stored = 0usize
    var head = 0usize
    var fx = f(ctx, x)
    g(ctx, x, gradient)
    var iteration = 0u32
    while iteration < max_iterations {
        if norm(gradient) <= tolerance { ret (Result { value: fx, iterations: iteration, converged: true }, ok) }
        // Two-loop recursion.
        var i = 0usize
        while i < n {
            direction[i] = gradient[i]
            i += 1usize
        }
        var k = 0usize
        while k < stored {
            let slot = (head + memory - 1usize - k) % memory
            let s_k = s_store[slot * n..(slot + 1usize) * n]
            let y_k = y_store[slot * n..(slot + 1usize) * n]
            let a_k = rho[slot] * dot(s_k, direction)
            alpha[slot] = a_k
            i = 0usize
            while i < n {
                direction[i] -= a_k * y_k[i]
                i += 1usize
            }
            k += 1usize
        }
        if stored > 0usize {
            let last = (head + memory - 1usize) % memory
            let s_l = s_store[last * n..(last + 1usize) * n]
            let y_l = y_store[last * n..(last + 1usize) * n]
            let gamma = dot(s_l, y_l) / dot(y_l, y_l)
            i = 0usize
            while i < n {
                direction[i] = direction[i] * gamma
                i += 1usize
            }
        }
        k = stored
        while k > 0usize {
            k -= 1usize
            let slot = (head + memory - 1usize - k) % memory
            let s_k = s_store[slot * n..(slot + 1usize) * n]
            let y_k = y_store[slot * n..(slot + 1usize) * n]
            let b_k = rho[slot] * dot(y_k, direction)
            i = 0usize
            while i < n {
                direction[i] += (alpha[slot] - b_k) * s_k[i]
                i += 1usize
            }
        }
        i = 0usize
        while i < n {
            direction[i] = 0.0f64 - direction[i]
            i += 1usize
        }
        var taken = line_search_wolfe[Ctx](ctx, f, g, x, fx, gradient, direction, trial, new_gradient)
        if taken == 0.0f64 {
            stored = 0usize
            i = 0usize
            while i < n {
                direction[i] = 0.0f64 - gradient[i]
                i += 1usize
            }
            taken = line_search_wolfe[Ctx](ctx, f, g, x, fx, gradient, direction, trial, new_gradient)
            if taken == 0.0f64 { ret (Result { value: fx, iterations: iteration, converged: false }, ok) }
        }
        // The pair is kept only when its curvature is positive; a rejected pair
        // must not overwrite the oldest stored one, so test before storing.
        var sy = 0.0f64
        i = 0usize
        while i < n {
            sy += (trial[i] - x[i]) * (new_gradient[i] - gradient[i])
            i += 1usize
        }
        if sy > 1.0e-12f64 {
            var s_new = s_store[head * n..(head + 1usize) * n]
            var y_new = y_store[head * n..(head + 1usize) * n]
            i = 0usize
            while i < n {
                s_new[i] = trial[i] - x[i]
                y_new[i] = new_gradient[i] - gradient[i]
                i += 1usize
            }
            rho[head] = 1.0f64 / sy
            head = (head + 1usize) % memory
            if stored < memory { stored += 1usize }
        }
        i = 0usize
        while i < n {
            x[i] = trial[i]
            gradient[i] = new_gradient[i]
            i += 1usize
        }
        fx = f(ctx, x)
        iteration += 1u32
    }
    ret (Result { value: fx, iterations: iteration, converged: false }, ok)
}

// Nelder-Mead from the simplex of `x` and `x + scale e_i`, until the simplex's
// value spread is under `tolerance`; `scratch.len >= (n + 1) * (n + 1) + 4 * n`.
fn nelder_mead[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []f64, scale: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    let points = n + 1usize
    if scratch.len < points * points + 4usize * n { ret (zero, TooSmall) }
    var vertices = scratch[..points * n]
    var values = scratch[points * n..points * n + points]
    var at = points * n + points
    var centroid = scratch[at..at + n]
    at += n
    var reflected = scratch[at..at + n]
    at += n
    var expanded = scratch[at..at + n]
    at += n
    var i = 0usize
    while i < points {
        var k = 0usize
        while k < n {
            vertices[i * n + k] = x[k]
            if i > 0usize && k == i - 1usize { vertices[i * n + k] += scale }
            k += 1usize
        }
        values[i] = f(ctx, vertices[i * n..(i + 1usize) * n])
        i += 1usize
    }
    var iteration = 0u32
    while iteration < max_iterations {
        // Order: best, worst, second worst.
        var best = 0usize
        var worst = 0usize
        i = 1usize
        while i < points {
            if values[i] < values[best] { best = i }
            if values[i] > values[worst] { worst = i }
            i += 1usize
        }
        var second = best
        i = 0usize
        while i < points {
            if i != worst && values[i] > values[second] { second = i }
            i += 1usize
        }
        if values[worst] - values[best] <= tolerance {
            var k = 0usize
            while k < n {
                x[k] = vertices[best * n + k]
                k += 1usize
            }
            ret (Result { value: values[best], iterations: iteration, converged: true }, ok)
        }
        var k = 0usize
        while k < n {
            var sum = 0.0f64
            i = 0usize
            while i < points {
                if i != worst { sum += vertices[i * n + k] }
                i += 1usize
            }
            centroid[k] = sum / f64(n)
            reflected[k] = centroid[k] + (centroid[k] - vertices[worst * n + k])
            k += 1usize
        }
        let fr = f(ctx, reflected)
        if fr < values[best] {
            k = 0usize
            while k < n {
                expanded[k] = centroid[k] + 2.0f64 * (reflected[k] - centroid[k])
                k += 1usize
            }
            let fe = f(ctx, expanded)
            if fe < fr {
                replace_vertex(vertices, values, worst, expanded, fe, n)
            } else {
                replace_vertex(vertices, values, worst, reflected, fr, n)
            }
        } else if fr < values[second] {
            replace_vertex(vertices, values, worst, reflected, fr, n)
        } else {
            // Contract toward the centroid, outside or inside.
            k = 0usize
            while k < n {
                if fr < values[worst] {
                    expanded[k] = centroid[k] + 0.5f64 * (reflected[k] - centroid[k])
                } else {
                    expanded[k] = centroid[k] + 0.5f64 * (vertices[worst * n + k] - centroid[k])
                }
                k += 1usize
            }
            let fc = f(ctx, expanded)
            var limit = values[worst]
            if fr < limit { limit = fr }
            if fc < limit {
                replace_vertex(vertices, values, worst, expanded, fc, n)
            } else {
                // Shrink toward the best vertex.
                i = 0usize
                while i < points {
                    if i != best {
                        k = 0usize
                        while k < n {
                            vertices[i * n + k] = vertices[best * n + k] + 0.5f64 * (vertices[i * n + k] - vertices[best * n + k])
                            k += 1usize
                        }
                        values[i] = f(ctx, vertices[i * n..(i + 1usize) * n])
                    }
                    i += 1usize
                }
            }
        }
        iteration += 1u32
    }
    var best = 0usize
    i = 1usize
    while i < points {
        if values[i] < values[best] { best = i }
        i += 1usize
    }
    var k = 0usize
    while k < n {
        x[k] = vertices[best * n + k]
        k += 1usize
    }
    ret (Result { value: values[best], iterations: iteration, converged: false }, ok)
}

fn replace_vertex(vertices: []f64, values: []f64, index: usize, point: []const f64, value: f64, n: usize) {
    var k = 0usize
    while k < n {
        vertices[index * n + k] = point[k]
        k += 1usize
    }
    values[index] = value
}

// Two-phase dense simplex (Bland's rule) for `maximise c x` subject to
// `A x <= b`, `x >= 0`, with `A` row-major `m x n`. Answers the optimum in `x`
// and its value; `Infeasible` or `Unbounded` otherwise. `tableau.len >=
// (m + 2) * (n + m + 2)` and `basis.len >= m`.
fn simplex(c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, x: []f64, tableau: []f64, basis: []usize) -> (f64, err) {
    let width = n + m + 2usize
    let rows = m + 2usize
    if c.len < n || a.len < m * n || b.len < m || x.len < n || tableau.len < rows * width || basis.len < m { ret (0.0f64, TooSmall) }
    var t = tableau[..rows * width]
    var i = 0usize
    while i < rows * width {
        t[i] = 0.0f64
        i += 1usize
    }
    // Rows 0..m: constraints with slack; row m: objective; row m + 1: phase-one objective.
    // Columns 0..n: x; n..n+m: slacks; n+m: artificial column marker unused; n+m+1: rhs.
    let rhs = width - 1usize
    i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            t[i * width + j] = a[i * n + j]
            j += 1usize
        }
        t[i * width + n + i] = 1.0f64
        t[i * width + rhs] = b[i]
        basis[i] = n + i
        i += 1usize
    }
    var j = 0usize
    while j < n {
        t[m * width + j] = 0.0f64 - c[j]
        j += 1usize
    }
    // Negative right-hand sides are made feasible by driving their rows with a
    // phase-one objective over the most negative one at a time (dual-style fix).
    var rounds = 0usize
    while rounds < 10000usize {
        var leave = m
        i = 0usize
        while i < m {
            if t[i * width + rhs] < 0.0f64 - 1.0e-12f64 && (leave == m || t[i * width + rhs] < t[leave * width + rhs]) { leave = i }
            i += 1usize
        }
        if leave == m { break }
        // Entering column: a negative coefficient in the leaving row with the smallest ratio.
        var enter = width
        var best_ratio = 0.0f64
        j = 0usize
        while j < n + m {
            let coefficient = t[leave * width + j]
            if coefficient < 0.0f64 - 1.0e-12f64 {
                let ratio = t[m * width + j] / coefficient
                if enter == width || ratio > best_ratio {
                    enter = j
                    best_ratio = ratio
                }
            }
            j += 1usize
        }
        if enter == width { ret (0.0f64, Infeasible) }
        pivot(t, width, rows, leave, enter)
        basis[leave] = enter
        rounds += 1usize
    }
    // Primal simplex with Bland's rule.
    rounds = 0usize
    while rounds < 10000usize {
        var enter = width
        j = 0usize
        while j < n + m {
            if t[m * width + j] < 0.0f64 - 1.0e-12f64 {
                enter = j
                break
            }
            j += 1usize
        }
        if enter == width { break }
        var leave = m
        var best_ratio = 0.0f64
        i = 0usize
        while i < m {
            let coefficient = t[i * width + enter]
            if coefficient > 1.0e-12f64 {
                let ratio = t[i * width + rhs] / coefficient
                if leave == m || ratio < best_ratio || (ratio == best_ratio && basis[i] < basis[leave]) {
                    leave = i
                    best_ratio = ratio
                }
            }
            i += 1usize
        }
        if leave == m { ret (0.0f64, Unbounded) }
        pivot(t, width, rows, leave, enter)
        basis[leave] = enter
        rounds += 1usize
    }
    j = 0usize
    while j < n {
        x[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < m {
        if basis[i] < n { x[basis[i]] = t[i * width + rhs] }
        i += 1usize
    }
    ret (t[m * width + rhs], ok)
}

fn pivot(t: []f64, width: usize, rows: usize, leave: usize, enter: usize) {
    let scale = t[leave * width + enter]
    var j = 0usize
    while j < width {
        t[leave * width + j] = t[leave * width + j] / scale
        j += 1usize
    }
    var i = 0usize
    while i < rows {
        if i != leave {
            let factor = t[i * width + enter]
            if factor != 0.0f64 {
                j = 0usize
                while j < width {
                    t[i * width + j] -= factor * t[leave * width + j]
                    j += 1usize
                }
            }
        }
        i += 1usize
    }
}
