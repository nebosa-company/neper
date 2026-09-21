// `e.math.opt`: every descent method and Nelder-Mead reach Rosenbrock's
// minimum at (1, 1) from (-1.2, 1), the quasi-Newton methods in far fewer
// iterations than steepest descent, and a quadratic bowl converges from
// anywhere; the simplex solves two small linear programmes against SciPy,
// one needing the negative right-hand-side fix, and reports an unbounded and
// an infeasible one. Each check exits with its own code.

use e.io
use e.math.opt
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn rosenbrock(ctx: *Nothing, x: []const f64) -> f64 {
    let a = 1.0f64 - x[0usize]
    let b = x[1usize] - x[0usize] * x[0usize]
    ret a * a + 100.0f64 * b * b
}
fn rosenbrock_gradient(ctx: *Nothing, x: []const f64, g: []f64) {
    g[0usize] = 0.0f64 - 2.0f64 * (1.0f64 - x[0usize]) - 400.0f64 * x[0usize] * (x[1usize] - x[0usize] * x[0usize])
    g[1usize] = 200.0f64 * (x[1usize] - x[0usize] * x[0usize])
}
fn bowl(ctx: *Nothing, x: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < x.len {
        let d = x[i] - f64(i)
        sum += f64(i + 1usize) * d * d
        i += 1usize
    }
    ret sum
}
fn bowl_gradient(ctx: *Nothing, x: []const f64, g: []f64) {
    var i = 0usize
    while i < x.len {
        g[i] = 2.0f64 * f64(i + 1usize) * (x[i] - f64(i))
        i += 1usize
    }
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    var scratch: [256]f64 = zero
    var x: [2]f64 = zero

    // 1: gradient descent reaches the Rosenbrock valley but is slow; BFGS and CG are fast.
    x[0usize] = 0.0f64 - 1.2f64
    x[1usize] = 1.0f64
    let (gd, gd_error) = opt.gradient_descent[Nothing](&nothing, rosenbrock, rosenbrock_gradient, x[..], 1.0f64, 0.0001f64, 20000u32, scratch[..])
    if gd_error != ok || !gd.converged || !near(x[0usize], 1.0f64, 0.01f64) || !near(x[1usize], 1.0f64, 0.01f64) { os.exit(1i32) }
    x[0usize] = 0.0f64 - 1.2f64
    x[1usize] = 1.0f64
    let (cg, cg_error) = opt.conjugate_gradient[Nothing](&nothing, rosenbrock, rosenbrock_gradient, x[..], 0.000001f64, 5000u32, scratch[..])
    if cg_error != ok || !cg.converged || !near(x[0usize], 1.0f64, 0.001f64) || !near(x[1usize], 1.0f64, 0.001f64) { os.exit(1i32) }
    x[0usize] = 0.0f64 - 1.2f64
    x[1usize] = 1.0f64
    let (bf, bf_error) = opt.bfgs[Nothing](&nothing, rosenbrock, rosenbrock_gradient, x[..], 0.000001f64, 500u32, scratch[..])
    if bf_error != ok || !bf.converged || !near(x[0usize], 1.0f64, 0.0001f64) || !near(x[1usize], 1.0f64, 0.0001f64) { os.exit(1i32) }
    if bf.iterations >= gd.iterations || bf.iterations > 200u32 || !near(bf.value, 0.0f64, 0.0000001f64) { os.exit(1i32) }
    x[0usize] = 0.0f64 - 1.2f64
    x[1usize] = 1.0f64
    let (lb, lb_error) = opt.lbfgs[Nothing](&nothing, rosenbrock, rosenbrock_gradient, x[..], 5usize, 0.000001f64, 500u32, scratch[..])
    if lb_error != ok || !lb.converged || !near(x[0usize], 1.0f64, 0.0001f64) || !near(x[1usize], 1.0f64, 0.0001f64) || lb.iterations > 300u32 { os.exit(1i32) }
    let (_, gd_room) = opt.gradient_descent[Nothing](&nothing, rosenbrock, rosenbrock_gradient, x[..], 1.0f64, 0.0001f64, 10u32, scratch[..5usize])
    if gd_room != opt.TooSmall { os.exit(1i32) }
    let (_, lb_invalid) = opt.lbfgs[Nothing](&nothing, rosenbrock, rosenbrock_gradient, x[..], 0usize, 0.000001f64, 10u32, scratch[..])
    if lb_invalid != opt.Invalid { os.exit(1i32) }

    // 2: Nelder-Mead on Rosenbrock, and the budget running out is reported.
    x[0usize] = 0.0f64 - 1.2f64
    x[1usize] = 1.0f64
    let (nm, nm_error) = opt.nelder_mead[Nothing](&nothing, rosenbrock, x[..], 0.5f64, 0.000000000001f64, 5000u32, scratch[..])
    if nm_error != ok || !nm.converged || !near(x[0usize], 1.0f64, 0.001f64) || !near(x[1usize], 1.0f64, 0.001f64) { os.exit(2i32) }
    x[0usize] = 0.0f64 - 1.2f64
    x[1usize] = 1.0f64
    let (short, short_error) = opt.nelder_mead[Nothing](&nothing, rosenbrock, x[..], 0.5f64, 0.000000000001f64, 5u32, scratch[..])
    if short_error != ok || short.converged || short.iterations != 5u32 { os.exit(2i32) }

    // 3: a five-dimensional quadratic bowl from a far start, by every method.
    var y: [5]f64 = zero
    var k = 0usize
    while k < 5usize {
        y[k] = 50.0f64 - 20.0f64 * f64(k)
        k += 1usize
    }
    let (bowl_bfgs, bowl_bfgs_error) = opt.bfgs[Nothing](&nothing, bowl, bowl_gradient, y[..], 0.0000001f64, 200u32, scratch[..])
    if bowl_bfgs_error != ok || !bowl_bfgs.converged { os.exit(3i32) }
    k = 0usize
    while k < 5usize {
        if !near(y[k], f64(k), 0.00001f64) { os.exit(3i32) }
        y[k] = 50.0f64 - 20.0f64 * f64(k)
        k += 1usize
    }
    let (bowl_lbfgs, bowl_lbfgs_error) = opt.lbfgs[Nothing](&nothing, bowl, bowl_gradient, y[..], 3usize, 0.0000001f64, 200u32, scratch[..])
    if bowl_lbfgs_error != ok || !bowl_lbfgs.converged { os.exit(3i32) }
    k = 0usize
    while k < 5usize {
        if !near(y[k], f64(k), 0.00001f64) { os.exit(3i32) }
        y[k] = 50.0f64 - 20.0f64 * f64(k)
        k += 1usize
    }
    let (bowl_cg, bowl_cg_error) = opt.conjugate_gradient[Nothing](&nothing, bowl, bowl_gradient, y[..], 0.0000001f64, 500u32, scratch[..])
    if bowl_cg_error != ok || !bowl_cg.converged { os.exit(3i32) }
    k = 0usize
    while k < 5usize {
        if !near(y[k], f64(k), 0.0001f64) { os.exit(3i32) }
        y[k] = 50.0f64 - 20.0f64 * f64(k)
        k += 1usize
    }
    let (bowl_nm, bowl_nm_error) = opt.nelder_mead[Nothing](&nothing, bowl, y[..], 5.0f64, 0.0000000001f64, 20000u32, scratch[..])
    if bowl_nm_error != ok || !bowl_nm.converged { os.exit(3i32) }
    k = 0usize
    while k < 5usize {
        if !near(y[k], f64(k), 0.001f64) { os.exit(3i32) }
        k += 1usize
    }

    // 4: linear programmes.
    var c: [2]f64 = zero
    c[0usize] = 3.0f64
    c[1usize] = 2.0f64
    var constraints: [4]f64 = zero
    constraints[0usize] = 1.0f64
    constraints[1usize] = 1.0f64
    constraints[2usize] = 1.0f64
    constraints[3usize] = 3.0f64
    var b: [2]f64 = zero
    b[0usize] = 4.0f64
    b[1usize] = 6.0f64
    var solution: [2]f64 = zero
    var tableau: [64]f64 = zero
    var basis: [4]usize = zero
    let (value, lp_error) = opt.simplex(c[..], constraints[..], b[..], 2usize, 2usize, solution[..], tableau[..], basis[..])
    if lp_error != ok || !near(value, 12.0f64, 0.000000001f64) || !near(solution[0usize], 4.0f64, 0.000000001f64) || !near(solution[1usize], 0.0f64, 0.000000001f64) { os.exit(4i32) }
    // maximise x + y with x - y >= 1 (a negative right-hand side) and x + y <= 5.
    c[0usize] = 1.0f64
    c[1usize] = 1.0f64
    constraints[0usize] = 0.0f64 - 1.0f64
    constraints[1usize] = 1.0f64
    constraints[2usize] = 1.0f64
    constraints[3usize] = 1.0f64
    b[0usize] = 0.0f64 - 1.0f64
    b[1usize] = 5.0f64
    let (value2, lp2_error) = opt.simplex(c[..], constraints[..], b[..], 2usize, 2usize, solution[..], tableau[..], basis[..])
    if lp2_error != ok || !near(value2, 5.0f64, 0.000000001f64) || !near(solution[0usize] + solution[1usize], 5.0f64, 0.000000001f64) || solution[0usize] - solution[1usize] < 0.999999999f64 { os.exit(4i32) }
    // Unbounded: maximise x with only x - y <= 1.
    var one_row: [2]f64 = zero
    one_row[0usize] = 1.0f64
    one_row[1usize] = 0.0f64 - 1.0f64
    var one_b: [1]f64 = zero
    one_b[0usize] = 1.0f64
    c[0usize] = 1.0f64
    c[1usize] = 0.0f64
    let (_, unbounded) = opt.simplex(c[..], one_row[..], one_b[..], 1usize, 2usize, solution[..], tableau[..], basis[..])
    if unbounded != opt.Unbounded { os.exit(4i32) }
    // Infeasible: x + y <= -1.
    one_row[0usize] = 1.0f64
    one_row[1usize] = 1.0f64
    one_b[0usize] = 0.0f64 - 1.0f64
    let (_, infeasible) = opt.simplex(c[..], one_row[..], one_b[..], 1usize, 2usize, solution[..], tableau[..], basis[..])
    if infeasible != opt.Infeasible { os.exit(4i32) }
    let (_, lp_room) = opt.simplex(c[..], constraints[..], b[..], 2usize, 2usize, solution[..], tableau[..10usize], basis[..])
    if lp_room != opt.TooSmall { os.exit(4i32) }

    try io.print("math opt ok\n")
    ret ok
}
