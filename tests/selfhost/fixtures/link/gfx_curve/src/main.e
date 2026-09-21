// `e.gfx.curve`: a Bezier point and its de Casteljau split, de Boor over clamped
// and open knots, Barry-Goldman Catmull-Rom at three alphas, and a rational
// surface point, each against `scipy.interpolate.BSpline` or a numpy replica
// over the same LCG control points to 1e-12. Each check exits with its own code.

use e.gfx.curve
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64((*state >> 33u32) % 1000u64) / 1000.0f64
}

fn draw_point(state: *u64) -> curve.Point {
    let x = draw(state)
    let y = draw(state)
    let z = draw(state)
    ret curve.point(x, y, z)
}

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= 1.0e-12f64
}

fn near_point(p: curve.Point, x: f64, y: f64, z: f64) -> bool {
    ret near(p.x, x) && near(p.y, y) && near(p.z, z)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 7u64
    var control: [6]curve.Point = zero
    var i = 0usize
    while i < 6usize {
        control[i] = draw_point(&state)
        i += 1usize
    }

    // 1: bezier against BSpline with clamped knots.
    var scratch: [6]curve.Point = zero
    let (b, b_error) = curve.bezier(control[..], scratch[..], 0.37f64)
    if b_error != ok || !near_point(b, 0.7013779003313001f64, 0.5018243443713f64, 0.46886127801919997f64) { os.exit(1i32) }
    let (_, short) = curve.bezier(control[..], scratch[..5usize], 0.37f64)
    if short != curve.TooSmall { os.exit(1i32) }

    // 2: the split halves against a de Casteljau replica.
    var left: [6]curve.Point = zero
    var right: [6]curve.Point = zero
    if curve.bezier_split(control[..], 0.37f64, left[..], right[..]) != ok { os.exit(2i32) }
    if !near_point(left[0usize], 0.278f64, 0.231f64, 0.753f64) { os.exit(2i32) }
    if !near_point(left[3usize], 0.6243094550000001f64, 0.505420971f64, 0.47977638600000005f64) { os.exit(2i32) }
    if !near_point(left[5usize], 0.7013779003313001f64, 0.5018243443713f64, 0.46886127801919997f64) { os.exit(2i32) }
    if !near_point(right[0usize], 0.7013779003313001f64, 0.5018243443713f64, 0.46886127801919997f64) { os.exit(2i32) }
    if !near_point(right[2usize], 0.7305165800000001f64, 0.369906858f64, 0.508908914f64) { os.exit(2i32) }
    if !near_point(right[5usize], 0.962f64, 0.405f64, 0.899f64) { os.exit(2i32) }
    let (on_left, _) = curve.bezier(left[..], scratch[..], 0.5f64)
    let (on_whole, _) = curve.bezier(control[..], scratch[..], 0.185f64)
    if !near_point(on_left, on_whole.x, on_whole.y, on_whole.z) { os.exit(2i32) }

    // 3: cubic B-spline over clamped uniform knots.
    var q: [8]curve.Point = zero
    i = 0usize
    while i < 8usize {
        q[i] = draw_point(&state)
        i += 1usize
    }
    var knots: [12]f64 = zero
    if curve.uniform_knots(8usize, 3usize, knots[..]) != ok { os.exit(3i32) }
    if !near(knots[3usize], 0.0f64) || !near(knots[4usize], 0.2f64) || !near(knots[7usize], 0.8f64) || !near(knots[8usize], 1.0f64) { os.exit(3i32) }
    let (s0, s0_error) = curve.bspline(q[..], knots[..], 3usize, 0.0f64)
    if s0_error != ok || !near_point(s0, 0.796f64, 0.951f64, 0.936f64) { os.exit(3i32) }
    let (s1, _) = curve.bspline(q[..], knots[..], 3usize, 0.25f64)
    if !near_point(s1, 0.7600338541666667f64, 0.7577942708333333f64, 0.23346614583333336f64) { os.exit(3i32) }
    let (s2, _) = curve.bspline(q[..], knots[..], 3usize, 0.5f64)
    if !near_point(s2, 0.8449791666666665f64, 0.6938958333333333f64, 0.4909374999999999f64) { os.exit(3i32) }
    let (s3, _) = curve.bspline(q[..], knots[..], 3usize, 0.999f64)
    if !near_point(s3, 0.7439205671250001f64, 0.44293532747916675f64, 0.3445060579479168f64) { os.exit(3i32) }
    let (s4, _) = curve.bspline(q[..], knots[..], 3usize, 1.0f64)
    if !near_point(s4, 0.752f64, 0.445f64, 0.335f64) { os.exit(3i32) }
    let (_, outside) = curve.bspline(q[..], knots[..], 3usize, 1.5f64)
    if outside != curve.Invalid { os.exit(3i32) }

    // 4: open uniform knots.
    i = 0usize
    while i < 12usize {
        knots[i] = f64(i) / 11.0f64
        i += 1usize
    }
    let (o, o_error) = curve.bspline(q[..], knots[..], 3usize, 0.5f64)
    if o_error != ok || !near_point(o, 0.8449791666666666f64, 0.6938958333333333f64, 0.4909375f64) { os.exit(4i32) }

    // 5: Catmull-Rom at alpha 0.5, 0 and 1.
    var chain: [6]curve.Point = zero
    i = 0usize
    while i < 6usize {
        chain[i] = draw_point(&state)
        i += 1usize
    }
    let (c0, c0_error) = curve.catmull_rom(chain[..], 1.7f64, 0.5f64)
    if c0_error != ok || !near_point(c0, 0.6481814741892842f64, 0.3690055377695578f64, 0.7559029072369323f64) { os.exit(5i32) }
    let (c1, _) = curve.catmull_rom(chain[..], 2.3f64, 0.0f64)
    if !near_point(c1, 0.4876650000000001f64, 0.4792439999999998f64, 0.6882334999999999f64) { os.exit(5i32) }
    let (c2, _) = curve.catmull_rom(chain[..], 3.0f64, 1.0f64)
    if !near_point(c2, 0.074f64, 0.851f64, 0.808f64) { os.exit(5i32) }
    let (_, too_few) = curve.catmull_rom(chain[..3usize], 0.5f64, 0.5f64)
    if too_few != curve.Invalid { os.exit(5i32) }

    // 6: a 4x3 rational surface of degrees 3 and 2.
    var grid: [12]curve.Point = zero
    i = 0usize
    while i < 12usize {
        grid[i] = draw_point(&state)
        i += 1usize
    }
    var weights: [12]f64 = zero
    i = 0usize
    while i < 12usize {
        weights[i] = draw(&state) + 0.5f64
        i += 1usize
    }
    var knots_u: [8]f64 = zero
    var knots_v: [6]f64 = zero
    if curve.uniform_knots(4usize, 3usize, knots_u[..]) != ok || curve.uniform_knots(3usize, 2usize, knots_v[..]) != ok { os.exit(6i32) }
    let (n0, n0_error) = curve.nurbs_surface(grid[..], weights[..], 4usize, 3usize, knots_u[..], knots_v[..], 3usize, 2usize, 0.3f64, 0.6f64)
    if n0_error != ok || !near_point(n0, 0.5269949112286926f64, 0.5349736579836692f64, 0.6126297561714394f64) { os.exit(6i32) }
    let (n1, _) = curve.nurbs_surface(grid[..], weights[..], 4usize, 3usize, knots_u[..], knots_v[..], 3usize, 2usize, 1.0f64, 1.0f64)
    if !near_point(n1, 0.354f64, 0.848f64, 0.758f64) { os.exit(6i32) }
    let (_, bad_degree) = curve.nurbs_surface(grid[..], weights[..], 4usize, 3usize, knots_u[..], knots_v[..], 4usize, 2usize, 0.5f64, 0.5f64)
    if bad_degree != curve.Invalid { os.exit(6i32) }

    try io.print("gfx curve ok\n")
    ret ok
}
