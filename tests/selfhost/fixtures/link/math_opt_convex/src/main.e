// `e.math.opt.convex`: the interior-point method solves the two linear
// programmes the simplex fixture solves (the second with a negative
// right-hand side) to the same optima, a Markowitz portfolio quadratic
// programme against SciPy's SLSQP answer, and reports the unbounded and the
// infeasible programme as stalled. Each check exits with its own code.

use e.io
use e.math.opt.convex
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var scratch: [128]f64 = zero
    var x: [3]f64 = zero

    // 1: maximise 3x + 2y with x + y <= 4, x + 3y <= 6: 12 at (4, 0).
    var c: [2]f64 = zero
    c[0usize] = 3.0f64
    c[1usize] = 2.0f64
    var rows: [4]f64 = zero
    rows[0usize] = 1.0f64
    rows[1usize] = 1.0f64
    rows[2usize] = 1.0f64
    rows[3usize] = 3.0f64
    var b: [2]f64 = zero
    b[0usize] = 4.0f64
    b[1usize] = 6.0f64
    let (lp, lp_error) = convex.interior_point(c[..], rows[..], b[..], 2usize, 2usize, x[..2usize], 0.000000001f64, 100u32, scratch[..])
    if lp_error != ok || !near(lp.value, 12.0f64, 0.0000001f64) || !near(x[0usize], 4.0f64, 0.0000001f64) || !near(x[1usize], 0.0f64, 0.0000001f64) { os.exit(1i32) }
    if lp.iterations == 0u32 || lp.iterations > 40u32 { os.exit(1i32) }
    // maximise x + y with x - y >= 1 and x + y <= 5.
    c[0usize] = 1.0f64
    c[1usize] = 1.0f64
    rows[0usize] = 0.0f64 - 1.0f64
    rows[1usize] = 1.0f64
    rows[2usize] = 1.0f64
    rows[3usize] = 1.0f64
    b[0usize] = 0.0f64 - 1.0f64
    b[1usize] = 5.0f64
    let (lp2, lp2_error) = convex.interior_point(c[..], rows[..], b[..], 2usize, 2usize, x[..2usize], 0.000000001f64, 100u32, scratch[..])
    if lp2_error != ok || !near(lp2.value, 5.0f64, 0.0000001f64) || !near(x[0usize] + x[1usize], 5.0f64, 0.0000001f64) || x[0usize] - x[1usize] < 0.9999999f64 { os.exit(1i32) }

    // 2: Markowitz: minimise x·Σx - ½ μ·x with Σx = 1 as two inequalities.
    var q: [9]f64 = zero
    q[0usize] = 0.08f64
    q[1usize] = 0.012f64
    q[2usize] = 0.04f64
    q[3usize] = 0.012f64
    q[4usize] = 0.18f64
    q[5usize] = 0.02f64
    q[6usize] = 0.04f64
    q[7usize] = 0.02f64
    q[8usize] = 0.32f64
    var cost: [3]f64 = zero
    cost[0usize] = 0.0f64 - 0.025f64
    cost[1usize] = 0.0f64 - 0.04f64
    cost[2usize] = 0.0f64 - 0.06f64
    var budget: [6]f64 = zero
    budget[0usize] = 1.0f64
    budget[1usize] = 1.0f64
    budget[2usize] = 1.0f64
    budget[3usize] = 0.0f64 - 1.0f64
    budget[4usize] = 0.0f64 - 1.0f64
    budget[5usize] = 0.0f64 - 1.0f64
    var one: [2]f64 = zero
    one[0usize] = 1.0f64
    one[1usize] = 0.0f64 - 1.0f64
    let (qp, qp_error) = convex.quadratic_program(q[..], cost[..], budget[..], one[..], 2usize, 3usize, x[..], 0.000000001f64, 100u32, scratch[..])
    if qp_error != ok || !near(qp.value, 0.0f64 - 0.00503919908f64, 0.00000001f64) { os.exit(2i32) }
    if !near(x[0usize], 0.49907141f64, 0.00001f64) || !near(x[1usize], 0.31359237f64, 0.00001f64) || !near(x[2usize], 0.18733623f64, 0.00001f64) { os.exit(2i32) }
    if !near(x[0usize] + x[1usize] + x[2usize], 1.0f64, 0.0000001f64) { os.exit(2i32) }
    let (_, qp_room) = convex.quadratic_program(q[..4usize], cost[..], budget[..], one[..], 2usize, 3usize, x[..], 0.000000001f64, 100u32, scratch[..])
    if qp_room != convex.TooSmall { os.exit(2i32) }

    // 3: unbounded (maximise x with x - y <= 1) and infeasible (x + y <= -1) stall.
    var row: [2]f64 = zero
    row[0usize] = 1.0f64
    row[1usize] = 0.0f64 - 1.0f64
    var limit: [1]f64 = zero
    limit[0usize] = 1.0f64
    c[0usize] = 1.0f64
    c[1usize] = 0.0f64
    let (_, unbounded) = convex.interior_point(c[..], row[..], limit[..], 1usize, 2usize, x[..2usize], 0.000000001f64, 100u32, scratch[..])
    if unbounded != convex.Stalled { os.exit(3i32) }
    row[1usize] = 1.0f64
    limit[0usize] = 0.0f64 - 1.0f64
    let (_, infeasible) = convex.interior_point(c[..], row[..], limit[..], 1usize, 2usize, x[..2usize], 0.000000001f64, 100u32, scratch[..])
    if infeasible != convex.Stalled { os.exit(3i32) }
    let (_, lp_room) = convex.interior_point(c[..], row[..], limit[..], 1usize, 2usize, x[..2usize], 0.000000001f64, 100u32, scratch[..10usize])
    if lp_room != convex.TooSmall { os.exit(3i32) }
    let (_, lp_invalid) = convex.interior_point(c[..], row[..], limit[..], 1usize, 2usize, x[..2usize], 0.0f64, 100u32, scratch[..])
    if lp_invalid != convex.Invalid { os.exit(3i32) }

    try io.print("math opt convex ok\n")
    ret ok
}
