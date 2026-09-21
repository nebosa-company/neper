// `e.math.filter`: a constant-velocity Kalman filter tracks a straight line
// through noisy positions and its covariance settles; the extended and
// unscented forms track a range-only observer of the same line; a particle
// filter's weighted mean follows the truth and resamples when the weights
// collapse; the complementary, Madgwick and Mahony filters converge on a
// tilted accelerometer from an upright start; a singular innovation is
// refused. Each check exits with its own code.

use e.algo.rand
use e.io
use e.math
use e.math.filter
use e.mem
use e.os

type Model = struct { dt: f64, noise: f64 }

// Constant velocity in one dimension: state (position, velocity).
fn move(ctx: *Model, x: []const f64, next: []f64) {
    next[0usize] = x[0usize] + ctx.dt * x[1usize]
    next[1usize] = x[1usize]
}
fn move_jacobian(ctx: *Model, x: []const f64, f: []f64) {
    f[0usize] = 1.0f64
    f[1usize] = ctx.dt
    f[2usize] = 0.0f64
    f[3usize] = 1.0f64
}
// Range from the origin, a nonlinear observation of position.
fn range(ctx: *Model, x: []const f64, z: []f64) { z[0usize] = math.sqrt[f64](x[0usize] * x[0usize] + 100.0f64) }
fn range_jacobian(ctx: *Model, x: []const f64, h: []f64) {
    let d = math.sqrt[f64](x[0usize] * x[0usize] + 100.0f64)
    h[0usize] = x[0usize] / d
    h[1usize] = 0.0f64
}
fn jitter(ctx: *Model, r: *rand.Pcg64, particle: []f64) {
    particle[0usize] += ctx.dt * particle[1usize] + ctx.noise * (rand.pcg64_f64(r) - 0.5f64)
    particle[1usize] += ctx.noise * 0.2f64 * (rand.pcg64_f64(r) - 0.5f64)
}
fn gaussian_likelihood(ctx: *Model, particle: []const f64, z: []const f64) -> f64 {
    let d = particle[0usize] - z[0usize]
    ret math.exp[f64](0.0f64 - d * d / 2.0f64)
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var model = Model { dt: 0.1f64, noise: 0.3f64 }
    var r = rand.pcg64(3u64, 5u64)
    var scratch: [1024]f64 = zero
    // The truth: position 0 + 2 t.
    var f: [4]f64 = zero
    f[0usize] = 1.0f64
    f[1usize] = 0.1f64
    f[2usize] = 0.0f64
    f[3usize] = 1.0f64
    var q: [4]f64 = zero
    q[0usize] = 0.0001f64
    q[3usize] = 0.0001f64
    var h: [2]f64 = zero
    h[0usize] = 1.0f64
    var rn: [1]f64 = zero
    rn[0usize] = 0.25f64

    // 1: the linear Kalman filter.
    var x: [2]f64 = zero
    var p: [4]f64 = zero
    p[0usize] = 10.0f64
    p[3usize] = 10.0f64
    var z: [1]f64 = zero
    var step = 0usize
    while step < 200usize {
        if filter.kalman_predict(x[..], p[..], f[..], q[..], 2usize, scratch[..]) != ok { os.exit(1i32) }
        let t = f64(step + 1usize) * 0.1f64
        z[0usize] = 2.0f64 * t + 0.5f64 * (rand.pcg64_f64(&r) - 0.5f64)
        if filter.kalman_update(x[..], p[..], h[..], rn[..], z[..], 2usize, 1usize, scratch[..]) != ok { os.exit(1i32) }
        step += 1usize
    }
    if !near(x[0usize], 40.0f64, 0.3f64) || !near(x[1usize], 2.0f64, 0.1f64) { os.exit(1i32) }
    if p[0usize] >= 1.0f64 || p[0usize] <= 0.0f64 || p[3usize] >= 1.0f64 { os.exit(1i32) }
    if filter.kalman_predict(x[..], p[..], f[..], q[..], 2usize, scratch[..5usize]) != filter.TooSmall { os.exit(1i32) }
    var zero_noise: [1]f64 = zero
    var flat_p: [4]f64 = zero
    if filter.kalman_update(x[..], flat_p[..], h[..], zero_noise[..], z[..], 2usize, 1usize, scratch[..]) != filter.Singular { os.exit(1i32) }

    // 2: the extended filter over the range observation.
    x[0usize] = 1.0f64
    x[1usize] = 0.0f64
    p[0usize] = 10.0f64
    p[1usize] = 0.0f64
    p[2usize] = 0.0f64
    p[3usize] = 10.0f64
    rn[0usize] = 0.05f64
    step = 0usize
    while step < 300usize {
        if filter.ekf_predict[Model](&model, move, move_jacobian, x[..], p[..], q[..], 2usize, scratch[..]) != ok { os.exit(2i32) }
        let t = f64(step + 1usize) * 0.1f64
        let truth = 2.0f64 * t
        z[0usize] = math.sqrt[f64](truth * truth + 100.0f64) + 0.2f64 * (rand.pcg64_f64(&r) - 0.5f64)
        if filter.ekf_update[Model](&model, range, range_jacobian, x[..], p[..], rn[..], z[..], 2usize, 1usize, scratch[..]) != ok { os.exit(2i32) }
        step += 1usize
    }
    if !near(x[0usize], 60.0f64, 1.0f64) || !near(x[1usize], 2.0f64, 0.2f64) { os.exit(2i32) }

    // 3: the unscented filter on the same problem, started on the right side of the
    // origin (the range is even in position, so a wide prior could settle at -60).
    x[0usize] = 5.0f64
    x[1usize] = 0.0f64
    p[0usize] = 4.0f64
    p[1usize] = 0.0f64
    p[2usize] = 0.0f64
    p[3usize] = 4.0f64
    step = 0usize
    while step < 300usize {
        let t = f64(step + 1usize) * 0.1f64
        let truth = 2.0f64 * t
        z[0usize] = math.sqrt[f64](truth * truth + 100.0f64) + 0.2f64 * (rand.pcg64_f64(&r) - 0.5f64)
        if filter.ukf_step[Model](&model, move, range, x[..], p[..], q[..], rn[..], z[..], 2usize, 1usize, scratch[..]) != ok { os.exit(3i32) }
        step += 1usize
    }
    if !near(x[0usize], 60.0f64, 1.0f64) || !near(x[1usize], 2.0f64, 0.2f64) { os.exit(3i32) }
    if filter.ukf_step[Model](&model, move, range, x[..], p[..], q[..], rn[..], z[..], 2usize, 1usize, scratch[..10usize]) != filter.TooSmall { os.exit(3i32) }

    // 4: the particle filter follows the line and resamples.
    var particles: [400]f64 = zero
    var weights: [200]f64 = zero
    var i = 0usize
    while i < 200usize {
        particles[2usize * i] = 20.0f64 * (rand.pcg64_f64(&r) - 0.5f64)
        particles[2usize * i + 1usize] = 4.0f64 * (rand.pcg64_f64(&r) - 0.5f64) + 2.0f64
        weights[i] = 1.0f64 / 200.0f64
        i += 1usize
    }
    step = 0usize
    while step < 150usize {
        let t = f64(step + 1usize) * 0.1f64
        z[0usize] = 2.0f64 * t + 0.3f64 * (rand.pcg64_f64(&r) - 0.5f64)
        if filter.particle_step[Model](&model, &r, jitter, gaussian_likelihood, particles[..], weights[..], 200usize, 2usize, z[..], scratch[..]) != ok { os.exit(4i32) }
        step += 1usize
    }
    var mean: [2]f64 = zero
    if filter.particle_mean(particles[..], weights[..], 200usize, 2usize, mean[..]) != ok { os.exit(4i32) }
    if !near(mean[0usize], 30.0f64, 0.5f64) { os.exit(4i32) }
    // A degenerate set (every likelihood zero) resets to uniform weights.
    z[0usize] = 1000000.0f64
    if filter.particle_step[Model](&model, &r, jitter, gaussian_likelihood, particles[..], weights[..], 200usize, 2usize, z[..], scratch[..]) != ok { os.exit(4i32) }
    if !near(weights[0usize], 0.005f64, 0.0000000001f64) { os.exit(4i32) }

    // 5: attitude filters converge on a 30-degree roll from upright.
    let roll_target = 0.5235987755982988f64
    let ay = math.sin[f64](roll_target) * 9.81f64
    let az = math.cos[f64](roll_target) * 9.81f64
    var quaternion: [4]f64 = zero
    quaternion[0usize] = 1.0f64
    step = 0usize
    while step < 2000usize {
        if filter.madgwick(quaternion[..], 0.0f64, 0.0f64, 0.0f64, 0.0f64, ay, az, 0.01f64, 0.1f64) != ok { os.exit(5i32) }
        step += 1usize
    }
    let (roll_m, pitch_m, _) = filter.quaternion_to_euler(quaternion[..])
    if !near(roll_m, roll_target, 0.01f64) || !near(pitch_m, 0.0f64, 0.01f64) { os.exit(5i32) }
    quaternion[0usize] = 1.0f64
    quaternion[1usize] = 0.0f64
    quaternion[2usize] = 0.0f64
    quaternion[3usize] = 0.0f64
    var integral: [3]f64 = zero
    step = 0usize
    while step < 2000usize {
        if filter.mahony(quaternion[..], integral[..], 0.0f64, 0.0f64, 0.0f64, 0.0f64, ay, az, 0.01f64, 2.0f64, 0.1f64) != ok { os.exit(5i32) }
        step += 1usize
    }
    let (roll_h, pitch_h, _) = filter.quaternion_to_euler(quaternion[..])
    if !near(roll_h, roll_target, 0.01f64) || !near(pitch_h, 0.0f64, 0.01f64) { os.exit(5i32) }
    // The complementary filter with a steady gyro rate and an agreeing accelerometer.
    var angle = 0.0f64
    step = 0usize
    while step < 1000usize {
        angle = filter.complementary(angle, 0.5f64, f64(step + 1usize) * 0.005f64, 0.01f64, 0.98f64)
        step += 1usize
    }
    if !near(angle, 5.0f64, 0.05f64) { os.exit(5i32) }
    if filter.madgwick(quaternion[..3usize], 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.01f64, 0.1f64) != filter.TooSmall { os.exit(5i32) }

    try io.print("math filter ok\n")
    ret ok
}
