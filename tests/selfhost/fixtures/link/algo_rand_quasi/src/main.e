// `e.algo.rand.quasi`: the first 64 Sobol points in eight dimensions agree
// with SciPy's unscrambled `Sobol` exactly (a weighted sum and two spot
// points), the incremental generator walks the same points, the first 64
// Halton points in three dimensions agree with `Halton` to 1e-15, and the
// radical inverse and bounds behave. Each check exits with its own code.

use e.algo.rand.quasi
use e.io
use e.mem
use e.os

fn near(a: f64, b: f64, tolerance: f64) -> bool {
    let d = a - b
    ret d <= tolerance && d >= 0.0f64 - tolerance
}

fn main(a: *mem.Arena, args: []str) -> err {
    var point: [8]f64 = zero
    var step: [8]f64 = zero

    // 1: 64 x 8 Sobol points against SciPy: sum (i+1)(d+1)x[i][d] = 37367 exactly.
    var weighted = 0.0f64
    var i = 0u64
    while i < 64u64 {
        if quasi.sobol(i, point[..]) != ok { os.exit(1i32) }
        var d = 0usize
        while d < 8usize {
            weighted += f64(i + 1u64) * f64(d + 1usize) * point[d]
            d += 1usize
        }
        i += 1u64
    }
    if weighted != 37367.0f64 { os.exit(1i32) }
    if quasi.sobol(0u64, point[..]) != ok || point[0usize] != 0.0f64 || point[7usize] != 0.0f64 { os.exit(1i32) }
    if quasi.sobol(37u64, point[..]) != ok || point[0usize] != 0.921875f64 || point[1usize] != 0.640625f64 || point[2usize] != 0.578125f64 || point[3usize] != 0.921875f64 { os.exit(1i32) }
    if point[4usize] != 0.765625f64 || point[5usize] != 0.296875f64 || point[6usize] != 0.171875f64 || point[7usize] != 0.796875f64 { os.exit(1i32) }
    if quasi.sobol(63u64, point[..]) != ok || point[0usize] != 0.015625f64 || point[4usize] != 0.859375f64 || point[7usize] != 0.140625f64 { os.exit(1i32) }
    if quasi.sobol(1000u64, point[..]) != ok || point[0usize] != 0.2197265625f64 || point[5usize] != 0.9072265625f64 || point[7usize] != 0.8994140625f64 { os.exit(1i32) }

    // 2: the incremental generator reproduces the indexed points.
    let (s0, start_error) = quasi.sobol_start(8usize)
    if start_error != ok { os.exit(2i32) }
    var s = s0
    i = 0u64
    while i < 1100u64 {
        if quasi.sobol_next(&s, step[..]) != ok || quasi.sobol(i, point[..]) != ok { os.exit(2i32) }
        var d = 0usize
        while d < 8usize {
            if step[d] != point[d] { os.exit(2i32) }
            d += 1usize
        }
        i += 1u64
    }
    if quasi.sobol_next(&s, step[..4usize]) != quasi.TooSmall { os.exit(2i32) }
    var nine: [9]f64 = zero
    if quasi.sobol(1u64, nine[..]) != quasi.Invalid { os.exit(2i32) }
    let (_, nine_error) = quasi.sobol_start(9usize)
    if nine_error != quasi.Invalid { os.exit(2i32) }

    // 3: 64 x 3 Halton points against SciPy: weighted sum and point 37.
    weighted = 0.0f64
    i = 0u64
    while i < 64u64 {
        if quasi.halton_point(i, point[..3usize]) != ok { os.exit(3i32) }
        var d = 0usize
        while d < 3usize {
            weighted += f64(i + 1u64) * f64(d + 1usize) * point[d]
            d += 1usize
        }
        i += 1u64
    }
    if !near(weighted, 6133.446790123457f64, 0.000000001f64) { os.exit(3i32) }
    if quasi.halton_point(37u64, point[..3usize]) != ok { os.exit(3i32) }
    if !near(point[0usize], 0.640625f64, 0.000000000000001f64) || !near(point[1usize], 0.38271604938271603f64, 0.000000000000001f64) || !near(point[2usize], 0.48800000000000004f64, 0.000000000000001f64) { os.exit(3i32) }
    if quasi.halton_point(100u64, point[..5usize]) != ok { os.exit(3i32) }
    if !near(point[3usize], 0.29154518950437314f64, 0.000000000000001f64) || !near(point[4usize], 0.1652892561983471f64, 0.000000000000001f64) { os.exit(3i32) }
    var wide: [17]f64 = zero
    if quasi.halton_point(1u64, wide[..]) != quasi.Invalid { os.exit(3i32) }

    // 4: the radical inverse.
    if quasi.van_der_corput(6u64, 2u64) != 0.375f64 || quasi.van_der_corput(0u64, 2u64) != 0.0f64 { os.exit(4i32) }
    if !near(quasi.van_der_corput(100u64, 10u64), 0.001f64, 0.000000000000001f64) { os.exit(4i32) }
    if quasi.halton(37u64, 2u64) != 0.640625f64 { os.exit(4i32) }

    try io.print("algo rand quasi ok\n")
    ret ok
}
