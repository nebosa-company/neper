// Scalar root finding over `f64`: bracketing (bisection, Brent) and open methods
// (Newton, Halley, secant).
//
// Every method takes the function as a value over borrowed context, stops when
// successive estimates are within `tolerance` or `|f(x)|` vanishes, and answers
// the estimate with the iteration count and whether it converged. The bracketing
// methods need `f(low)` and `f(high)` of opposite sign and answer `converged:
// false` without iterating when they are not; the open methods answer `false`
// when a derivative vanishes or the budget runs out.

use e.math

type Result = struct { x: f64, iterations: u32, converged: bool }

fn bisect[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, low: f64, high: f64, tolerance: f64, max_iterations: u32) -> Result {
    var a = low
    var b = high
    var fa = f(ctx, a)
    var fb = f(ctx, b)
    if fa == 0.0f64 { ret Result { x: a, iterations: 0u32, converged: true } }
    if fb == 0.0f64 { ret Result { x: b, iterations: 0u32, converged: true } }
    if (fa < 0.0f64) == (fb < 0.0f64) { ret Result { x: a, iterations: 0u32, converged: false } }
    var i = 0u32
    while i < max_iterations {
        let middle = a + (b - a) / 2.0f64
        let fm = f(ctx, middle)
        i += 1u32
        if fm == 0.0f64 || math.abs[f64](b - a) / 2.0f64 <= tolerance {
            ret Result { x: middle, iterations: i, converged: true }
        }
        if (fm < 0.0f64) == (fa < 0.0f64) {
            a = middle
            fa = fm
        } else {
            b = middle
            fb = fm
        }
    }
    ret Result { x: a + (b - a) / 2.0f64, iterations: i, converged: false }
}

fn newton[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, df: fn(*Ctx, f64) -> f64, start: f64, tolerance: f64, max_iterations: u32) -> Result {
    var x = start
    var i = 0u32
    while i < max_iterations {
        let fx = f(ctx, x)
        if fx == 0.0f64 { ret Result { x: x, iterations: i, converged: true } }
        let slope = df(ctx, x)
        if slope == 0.0f64 { ret Result { x: x, iterations: i, converged: false } }
        let next = x - fx / slope
        i += 1u32
        if math.abs[f64](next - x) <= tolerance { ret Result { x: next, iterations: i, converged: true } }
        x = next
    }
    ret Result { x: x, iterations: i, converged: false }
}

// Cubic convergence from the first two derivatives.
fn halley[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, df: fn(*Ctx, f64) -> f64, d2f: fn(*Ctx, f64) -> f64, start: f64, tolerance: f64, max_iterations: u32) -> Result {
    var x = start
    var i = 0u32
    while i < max_iterations {
        let fx = f(ctx, x)
        if fx == 0.0f64 { ret Result { x: x, iterations: i, converged: true } }
        let slope = df(ctx, x)
        let curve = d2f(ctx, x)
        let denominator = 2.0f64 * slope * slope - fx * curve
        if denominator == 0.0f64 { ret Result { x: x, iterations: i, converged: false } }
        let next = x - 2.0f64 * fx * slope / denominator
        i += 1u32
        if math.abs[f64](next - x) <= tolerance { ret Result { x: next, iterations: i, converged: true } }
        x = next
    }
    ret Result { x: x, iterations: i, converged: false }
}

fn secant[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, first: f64, second: f64, tolerance: f64, max_iterations: u32) -> Result {
    var x0 = first
    var x1 = second
    var f0 = f(ctx, x0)
    var f1 = f(ctx, x1)
    if f0 == 0.0f64 { ret Result { x: x0, iterations: 0u32, converged: true } }
    var i = 0u32
    while i < max_iterations {
        if f1 == 0.0f64 { ret Result { x: x1, iterations: i, converged: true } }
        if f1 == f0 { ret Result { x: x1, iterations: i, converged: false } }
        let next = x1 - f1 * (x1 - x0) / (f1 - f0)
        i += 1u32
        if math.abs[f64](next - x1) <= tolerance { ret Result { x: next, iterations: i, converged: true } }
        x0 = x1
        f0 = f1
        x1 = next
        f1 = f(ctx, x1)
    }
    ret Result { x: x1, iterations: i, converged: false }
}

// Brent's method: inverse quadratic interpolation and the secant step, guarded by
// bisection so the bracket always shrinks.
fn brent[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, low: f64, high: f64, tolerance: f64, max_iterations: u32) -> Result {
    var a = low
    var b = high
    var fa = f(ctx, a)
    var fb = f(ctx, b)
    if fa == 0.0f64 { ret Result { x: a, iterations: 0u32, converged: true } }
    if fb == 0.0f64 { ret Result { x: b, iterations: 0u32, converged: true } }
    if (fa < 0.0f64) == (fb < 0.0f64) { ret Result { x: a, iterations: 0u32, converged: false } }
    if math.abs[f64](fa) < math.abs[f64](fb) {
        let swap = a
        a = b
        b = swap
        let swap_f = fa
        fa = fb
        fb = swap_f
    }
    var c = a
    var fc = fa
    var d = b - a
    var bisected = true
    var i = 0u32
    while i < max_iterations {
        var s = 0.0f64
        if fa != fc && fb != fc {
            s = a * fb * fc / ((fa - fb) * (fa - fc)) + b * fa * fc / ((fb - fa) * (fb - fc)) + c * fa * fb / ((fc - fa) * (fc - fb))
        } else {
            s = b - fb * (b - a) / (fb - fa)
        }
        // Reject the interpolated step unless it is inside the inner three quarters
        // of the bracket and shrinks faster than bisection would.
        let quarter = (3.0f64 * a + b) / 4.0f64
        var between = false
        if quarter < b { between = s > quarter && s < b } else { between = s > b && s < quarter }
        var use_bisection = !between
        if !use_bisection {
            if bisected {
                if math.abs[f64](s - b) >= math.abs[f64](b - c) / 2.0f64 || math.abs[f64](b - c) < tolerance { use_bisection = true }
            } else {
                if math.abs[f64](s - b) >= math.abs[f64](c - d) / 2.0f64 || math.abs[f64](c - d) < tolerance { use_bisection = true }
            }
        }
        if use_bisection {
            s = (a + b) / 2.0f64
            bisected = true
        } else {
            bisected = false
        }
        let fs = f(ctx, s)
        i += 1u32
        d = c
        c = b
        fc = fb
        if (fa < 0.0f64) != (fs < 0.0f64) {
            b = s
            fb = fs
        } else {
            a = s
            fa = fs
        }
        if math.abs[f64](fa) < math.abs[f64](fb) {
            let swap = a
            a = b
            b = swap
            let swap_f = fa
            fa = fb
            fb = swap_f
        }
        if fb == 0.0f64 || math.abs[f64](b - a) <= tolerance { ret Result { x: b, iterations: i, converged: true } }
    }
    ret Result { x: b, iterations: i, converged: false }
}
