// `e.ml.optim`: one step of each rule on a two-parameter problem against
// hand-worked values (Adam with bias correction, AdamW with its decoupled
// decay, momentum and RMSprop by their formulas), the cosine schedule with
// warm restarts at its landmarks, online gradient descent with its decaying
// step, and the storage and step checks. Each check exits with its own code.

use e.io
use e.mem
use e.ml.optim
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var p: [2]f64 = zero
    var g: [2]f64 = zero
    var s1: [2]f64 = zero
    var s2: [2]f64 = zero

    // 1: SGD and momentum.
    p[0usize] = 1.0f64
    p[1usize] = 0.0f64 - 2.0f64
    g[0usize] = 0.5f64
    g[1usize] = 0.0f64 - 0.25f64
    if optim.sgd(p[..], g[..], 0.1f64) != ok || !near(p[0usize], 0.95f64, 0.000000000001f64) || !near(p[1usize], 0.0f64 - 1.975f64, 0.000000000001f64) { os.exit(1i32) }
    if optim.sgd(p[..], g[..1usize], 0.1f64) != optim.TooSmall { os.exit(1i32) }
    p[0usize] = 1.0f64
    p[1usize] = 0.0f64 - 2.0f64
    if optim.momentum(p[..], g[..], s1[..], 0.1f64, 0.9f64) != ok || !near(p[0usize], 0.95f64, 0.000000000001f64) { os.exit(1i32) }
    // A second identical step: velocity 0.5 + 0.9 * 0.5 = 0.95, so p falls by 0.095.
    if optim.momentum(p[..], g[..], s1[..], 0.1f64, 0.9f64) != ok || !near(p[0usize], 0.855f64, 0.000000000001f64) || !near(s1[0usize], 0.95f64, 0.000000000001f64) { os.exit(1i32) }

    // 2: RMSprop and Adam.
    p[0usize] = 1.0f64
    p[1usize] = 0.0f64 - 2.0f64
    s1[0usize] = 0.0f64
    s1[1usize] = 0.0f64
    if optim.rmsprop(p[..], g[..], s1[..], 0.01f64, 0.9f64, 0.00000001f64) != ok { os.exit(2i32) }
    // cache = 0.1 * 0.25 = 0.025; step = 0.01 * 0.5 / sqrt(0.025).
    if !near(p[0usize], 1.0f64 - 0.01f64 * 0.5f64 / 0.15811388300841897f64, 0.0000001f64) || !near(s1[0usize], 0.025f64, 0.000000000001f64) { os.exit(2i32) }
    p[0usize] = 1.0f64
    p[1usize] = 0.0f64 - 2.0f64
    s1[0usize] = 0.0f64
    s1[1usize] = 0.0f64
    if optim.adam(p[..], g[..], s1[..], s2[..], 1u64, 0.01f64, 0.9f64, 0.999f64, 0.00000001f64) != ok { os.exit(2i32) }
    // The first step is the rate times the sign of the gradient.
    if !near(p[0usize], 0.99f64, 0.0000001f64) || !near(p[1usize], 0.0f64 - 1.99f64, 0.0000001f64) { os.exit(2i32) }
    if optim.adam(p[..], g[..], s1[..], s2[..], 0u64, 0.01f64, 0.9f64, 0.999f64, 0.00000001f64) != optim.Invalid { os.exit(2i32) }
    p[0usize] = 1.0f64
    s1[0usize] = 0.0f64
    s2[0usize] = 0.0f64
    if optim.adamw(p[..1usize], g[..], s1[..], s2[..], 1u64, 0.01f64, 0.9f64, 0.999f64, 0.00000001f64, 0.1f64) != ok { os.exit(2i32) }
    // AdamW adds rate * decay * p: 0.01 * 0.1 * 1.
    if !near(p[0usize], 0.989f64, 0.0000001f64) { os.exit(2i32) }

    // 3: the cosine schedule and online gradient descent.
    if !near(optim.cosine_schedule(0.1f64, 0.001f64, 0u64, 100u64), 0.1f64, 0.000000000001f64) { os.exit(3i32) }
    if !near(optim.cosine_schedule(0.1f64, 0.001f64, 50u64, 100u64), 0.0505f64, 0.000000000001f64) { os.exit(3i32) }
    if !near(optim.cosine_schedule(0.1f64, 0.001f64, 25u64, 100u64), 0.0855017856687341f64, 0.000000000001f64) { os.exit(3i32) }
    if !near(optim.cosine_schedule(0.1f64, 0.001f64, 100u64, 100u64), 0.1f64, 0.000000000001f64) { os.exit(3i32) }
    if optim.cosine_schedule(0.1f64, 0.001f64, 99u64, 100u64) >= 0.0015f64 || optim.cosine_schedule(0.1f64, 0.001f64, 7u64, 0u64) != 0.1f64 { os.exit(3i32) }
    p[0usize] = 1.0f64
    let (rate4, online_error) = optim.online_gd(p[..1usize], g[..], 4u64, 0.2f64)
    if online_error != ok || !near(rate4, 0.1f64, 0.000000000001f64) || !near(p[0usize], 0.95f64, 0.000000000001f64) { os.exit(3i32) }
    let (_, online_invalid) = optim.online_gd(p[..1usize], g[..], 0u64, 0.2f64)
    if online_invalid != optim.Invalid { os.exit(3i32) }

    try io.print("ml optim ok\n")
    ret ok
}
