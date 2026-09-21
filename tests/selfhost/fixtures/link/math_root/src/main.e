// `e.math.root`: every method finds sqrt(2) from x^2 - 2 and the root of
// cos(x) - x, Newton and Halley converge in a handful of steps where bisection
// needs dozens, a bracket without a sign change is refused, a flat derivative is
// reported, and Brent handles the cubic that defeats plain secant steps. Each
// check exits with its own code.

use e.io
use e.math
use e.math.root
use e.mem
use e.os

type Calls = struct { count: u32 }

fn square_minus_two(ctx: *Calls, x: f64) -> f64 {
    ctx.count += 1u32
    ret x * x - 2.0f64
}
fn two_x(ctx: *Calls, x: f64) -> f64 { ret 2.0f64 * x }
fn two(ctx: *Calls, x: f64) -> f64 { ret 2.0f64 }
fn cos_minus_x(ctx: *Calls, x: f64) -> f64 {
    ctx.count += 1u32
    ret math.cos[f64](x) - x
}
fn neg_sin_minus_one(ctx: *Calls, x: f64) -> f64 { ret 0.0f64 - math.sin[f64](x) - 1.0f64 }
fn neg_cos(ctx: *Calls, x: f64) -> f64 { ret 0.0f64 - math.cos[f64](x) }
fn cubic(ctx: *Calls, x: f64) -> f64 {
    ctx.count += 1u32
    ret (x + 3.0f64) * (x - 1.0f64) * (x - 1.0f64)
}
fn always_positive(ctx: *Calls, x: f64) -> f64 { ret x * x + 1.0f64 }
fn zero_slope(ctx: *Calls, x: f64) -> f64 { ret 0.0f64 }

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    let root2 = 1.4142135623730951f64
    let dottie = 0.7390851332151607f64
    var calls = Calls { count: 0u32 }

    // 1: bisection.
    let b1 = root.bisect[Calls](&calls, square_minus_two, 0.0f64, 2.0f64, 0.0000000001f64, 100u32)
    if !b1.converged || !near(b1.x, root2, 0.000000001f64) || b1.iterations < 20u32 { os.exit(1i32) }
    let b2 = root.bisect[Calls](&calls, cos_minus_x, 0.0f64, 1.0f64, 0.0000000001f64, 100u32)
    if !b2.converged || !near(b2.x, dottie, 0.000000001f64) { os.exit(1i32) }
    let b3 = root.bisect[Calls](&calls, always_positive, 0.0f64, 1.0f64, 0.0001f64, 100u32)
    if b3.converged || b3.iterations != 0u32 { os.exit(1i32) }
    let b4 = root.bisect[Calls](&calls, square_minus_two, 0.0f64, 2.0f64, 0.0000000001f64, 3u32)
    if b4.converged || b4.iterations != 3u32 { os.exit(1i32) }
    let b5 = root.bisect[Calls](&calls, cubic, 1.0f64, 4.0f64, 0.0001f64, 100u32)
    if !b5.converged || b5.x != 1.0f64 || b5.iterations != 0u32 { os.exit(1i32) }

    // 2: Newton, fast from a good start and refusing a flat slope.
    let n1 = root.newton[Calls](&calls, square_minus_two, two_x, 1.0f64, 0.000000000001f64, 50u32)
    if !n1.converged || !near(n1.x, root2, 0.000000000001f64) || n1.iterations > 8u32 { os.exit(2i32) }
    let n2 = root.newton[Calls](&calls, cos_minus_x, neg_sin_minus_one, 1.0f64, 0.000000000001f64, 50u32)
    if !n2.converged || !near(n2.x, dottie, 0.000000000001f64) || n2.iterations > 8u32 { os.exit(2i32) }
    let n3 = root.newton[Calls](&calls, square_minus_two, zero_slope, 1.0f64, 0.000000001f64, 50u32)
    if n3.converged || n3.iterations != 0u32 { os.exit(2i32) }
    let n4 = root.newton[Calls](&calls, square_minus_two, two_x, 100.0f64, 0.000000000001f64, 2u32)
    if n4.converged || n4.iterations != 2u32 { os.exit(2i32) }

    // 3: Halley converges in fewer steps than Newton.
    let h1 = root.halley[Calls](&calls, square_minus_two, two_x, two, 1.0f64, 0.000000000001f64, 50u32)
    if !h1.converged || !near(h1.x, root2, 0.000000000001f64) || h1.iterations > n1.iterations { os.exit(3i32) }
    let h2 = root.halley[Calls](&calls, cos_minus_x, neg_sin_minus_one, neg_cos, 1.0f64, 0.000000000001f64, 50u32)
    if !h2.converged || !near(h2.x, dottie, 0.000000000001f64) || h2.iterations > n2.iterations { os.exit(3i32) }

    // 4: secant.
    let s1 = root.secant[Calls](&calls, square_minus_two, 1.0f64, 2.0f64, 0.000000000001f64, 50u32)
    if !s1.converged || !near(s1.x, root2, 0.000000000001f64) || s1.iterations > 12u32 { os.exit(4i32) }
    let s2 = root.secant[Calls](&calls, cos_minus_x, 0.0f64, 1.0f64, 0.000000000001f64, 50u32)
    if !s2.converged || !near(s2.x, dottie, 0.000000000001f64) { os.exit(4i32) }
    let s3 = root.secant[Calls](&calls, always_positive, 1.0f64, 0.0f64 - 1.0f64, 0.000000001f64, 50u32)
    if s3.converged { os.exit(4i32) }

    // 5: Brent on the standard examples and the flat-shouldered cubic.
    calls.count = 0u32
    let r1 = root.brent[Calls](&calls, square_minus_two, 0.0f64, 2.0f64, 0.000000000001f64, 100u32)
    if !r1.converged || !near(r1.x, root2, 0.000000000001f64) || r1.iterations >= b1.iterations { os.exit(5i32) }
    let r2 = root.brent[Calls](&calls, cos_minus_x, 0.0f64, 1.0f64, 0.000000000001f64, 100u32)
    if !r2.converged || !near(r2.x, dottie, 0.000000000001f64) { os.exit(5i32) }
    calls.count = 0u32
    let r3 = root.brent[Calls](&calls, cubic, 0.0f64 - 4.0f64, 4.0f64 / 3.0f64, 0.0000000000001f64, 100u32)
    if !r3.converged || !near(r3.x, 0.0f64 - 3.0f64, 0.000000001f64) || calls.count > 40u32 { os.exit(5i32) }
    let r4 = root.brent[Calls](&calls, always_positive, 0.0f64, 1.0f64, 0.0001f64, 100u32)
    if r4.converged { os.exit(5i32) }
    let r5 = root.brent[Calls](&calls, square_minus_two, 0.0f64, 2.0f64, 0.000000000001f64, 2u32)
    if r5.converged { os.exit(5i32) }

    try io.print("math root ok\n")
    ret ok
}
