// `e.math.ode` on the harmonic oscillator and the exponential: RK4 and the
// adaptive RKF45 hit the closed forms to many digits where Euler drifts, the
// symplectic steppers conserve the oscillator's energy over a thousand periods
// while Euler's grows, Yoshida is more accurate than leapfrog at the same step,
// and Euler-Maruyama with zero noise reduces to Euler while its variance with
// unit noise matches Brownian motion. Each check exits with its own code.

use e.algo.rand
use e.io
use e.math
use e.math.ode
use e.mem
use e.os

type Nothing = struct { unused: u8 }

// y' = -y.
fn decay(ctx: *Nothing, t: f64, y: []const f64, dydt: []f64) { dydt[0usize] = 0.0f64 - y[0usize] }
// Harmonic oscillator as a first-order system: (x, v)' = (v, -x).
fn oscillator(ctx: *Nothing, t: f64, y: []const f64, dydt: []f64) {
    dydt[0usize] = y[1usize]
    dydt[1usize] = 0.0f64 - y[0usize]
}
fn spring(ctx: *Nothing, x: []const f64, a: []f64) { a[0usize] = 0.0f64 - x[0usize] }
fn zero_drift(ctx: *Nothing, t: f64, y: []const f64, out: []f64) { out[0usize] = 0.0f64 }
fn unit_diffusion(ctx: *Nothing, t: f64, y: []const f64, out: []f64) { out[0usize] = 1.0f64 }

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    var scratch: [32]f64 = zero
    let e_inverse = 0.36787944117144233f64

    // 1: exponential decay from 1 to e^-1 over unit time.
    var y: [1]f64 = zero
    y[0usize] = 1.0f64
    var steps = 0usize
    while steps < 100usize {
        if ode.euler[Nothing](&nothing, decay, f64(steps) * 0.01f64, y[..], 0.01f64, scratch[..]) != ok { os.exit(1i32) }
        steps += 1usize
    }
    if !near(y[0usize], e_inverse, 0.01f64) || near(y[0usize], e_inverse, 0.0001f64) { os.exit(1i32) }
    y[0usize] = 1.0f64
    steps = 0usize
    while steps < 100usize {
        if ode.rk4[Nothing](&nothing, decay, f64(steps) * 0.01f64, y[..], 0.01f64, scratch[..]) != ok { os.exit(1i32) }
        steps += 1usize
    }
    if !near(y[0usize], e_inverse, 0.00000001f64) { os.exit(1i32) }
    if ode.rk4[Nothing](&nothing, decay, 0.0f64, y[..], 0.01f64, scratch[..4usize]) != ode.TooSmall { os.exit(1i32) }

    // 2: adaptive RKF45 integrates to t = 1 within tolerance and adapts its step.
    y[0usize] = 1.0f64
    var t = 0.0f64
    var h = 0.5f64
    var attempts = 0usize
    var rejected = 0usize
    while t < 1.0f64 && attempts < 1000usize {
        if t + h > 1.0f64 { h = 1.0f64 - t }
        let (taken, next, step_error) = ode.rkf45[Nothing](&nothing, decay, t, y[..], h, 0.000000001f64, scratch[..])
        if step_error != ok { os.exit(2i32) }
        if taken == 0.0f64 { rejected += 1usize }
        t += taken
        h = next
        attempts += 1usize
    }
    if !near(t, 1.0f64, 0.000000000001f64) || !near(y[0usize], e_inverse, 0.00000001f64) || rejected == 0usize || attempts > 200usize { os.exit(2i32) }
    let (_, _, small_error) = ode.rkf45[Nothing](&nothing, decay, 0.0f64, y[..], 0.1f64, 0.001f64, scratch[..7usize])
    if small_error != ode.TooSmall { os.exit(2i32) }

    // 3: the oscillator by RK4 over one period returns to its start.
    var state: [2]f64 = zero
    state[0usize] = 1.0f64
    steps = 0usize
    let period = 6.283185307179586f64
    while steps < 1000usize {
        if ode.rk4[Nothing](&nothing, oscillator, f64(steps) * period / 1000.0f64, state[..], period / 1000.0f64, scratch[..]) != ok { os.exit(3i32) }
        steps += 1usize
    }
    if !near(state[0usize], 1.0f64, 0.000000001f64) || !near(state[1usize], 0.0f64, 0.000000001f64) { os.exit(3i32) }

    // 4: symplectic steppers conserve energy over a thousand periods; Euler does not.
    var x: [1]f64 = zero
    var v: [1]f64 = zero
    x[0usize] = 1.0f64
    let dt = 0.05f64
    let long = usize(1000.0f64 * period / dt)
    steps = 0usize
    while steps < long {
        if ode.verlet[Nothing](&nothing, spring, x[..], v[..], dt, scratch[..]) != ok { os.exit(4i32) }
        steps += 1usize
    }
    var energy = 0.5f64 * (x[0usize] * x[0usize] + v[0usize] * v[0usize])
    if !near(energy, 0.5f64, 0.001f64) { os.exit(4i32) }
    x[0usize] = 1.0f64
    v[0usize] = 0.0f64
    steps = 0usize
    while steps < long {
        if ode.leapfrog[Nothing](&nothing, spring, x[..], v[..], dt, scratch[..]) != ok { os.exit(4i32) }
        steps += 1usize
    }
    energy = 0.5f64 * (x[0usize] * x[0usize] + v[0usize] * v[0usize])
    if !near(energy, 0.5f64, 0.001f64) { os.exit(4i32) }
    // Explicit Euler on the same system gains energy without bound.
    state[0usize] = 1.0f64
    state[1usize] = 0.0f64
    steps = 0usize
    while steps < long {
        if ode.euler[Nothing](&nothing, oscillator, 0.0f64, state[..], dt, scratch[..]) != ok { os.exit(4i32) }
        steps += 1usize
    }
    energy = 0.5f64 * (state[0usize] * state[0usize] + state[1usize] * state[1usize])
    if energy < 10.0f64 { os.exit(4i32) }

    // 5: Yoshida beats leapfrog on position after one period at a coarse step.
    x[0usize] = 1.0f64
    v[0usize] = 0.0f64
    let coarse = period / 40.0f64
    steps = 0usize
    while steps < 40usize {
        if ode.leapfrog[Nothing](&nothing, spring, x[..], v[..], coarse, scratch[..]) != ok { os.exit(5i32) }
        steps += 1usize
    }
    var leapfrog_error = x[0usize] - 1.0f64
    if leapfrog_error < 0.0f64 { leapfrog_error = 0.0f64 - leapfrog_error }
    x[0usize] = 1.0f64
    v[0usize] = 0.0f64
    steps = 0usize
    while steps < 40usize {
        if ode.yoshida[Nothing](&nothing, spring, x[..], v[..], coarse, scratch[..]) != ok { os.exit(5i32) }
        steps += 1usize
    }
    var yoshida_error = x[0usize] - 1.0f64
    if yoshida_error < 0.0f64 { yoshida_error = 0.0f64 - yoshida_error }
    if yoshida_error * 10.0f64 > leapfrog_error || leapfrog_error > 0.1f64 { os.exit(5i32) }
    if ode.yoshida[Nothing](&nothing, spring, x[..], v[..], coarse, scratch[..0usize]) != ode.TooSmall { os.exit(5i32) }

    // 6: Euler-Maruyama: no noise is Euler; unit noise has variance t.
    var noise: [1]f64 = zero
    var w: [1]f64 = zero
    w[0usize] = 3.0f64
    if ode.euler_maruyama[Nothing](&nothing, zero_drift, unit_diffusion, 0.0f64, w[..], 0.25f64, noise[..], scratch[..]) != ok { os.exit(6i32) }
    if w[0usize] != 3.0f64 { os.exit(6i32) }
    var r = rand.pcg64(99u64, 7u64)
    var sum2 = 0.0f64
    var paths = 0usize
    while paths < 4000usize {
        w[0usize] = 0.0f64
        steps = 0usize
        while steps < 16usize {
            // A standard normal by the polar method, inline so the fixture depends on nothing else.
            var u = 0.0f64
            var s = 2.0f64
            var q = 0.0f64
            while s >= 1.0f64 || s == 0.0f64 {
                u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                q = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                s = u * u + q * q
            }
            noise[0usize] = u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s) / s)
            if ode.euler_maruyama[Nothing](&nothing, zero_drift, unit_diffusion, 0.0f64, w[..], 0.0625f64, noise[..], scratch[..]) != ok { os.exit(6i32) }
            steps += 1usize
        }
        sum2 += w[0usize] * w[0usize]
        paths += 1usize
    }
    // 16 steps of 1/16: Brownian motion at t = 1 has variance 1.
    if !near(sum2 / 4000.0f64, 1.0f64, 0.08f64) { os.exit(6i32) }
    if ode.euler_maruyama[Nothing](&nothing, zero_drift, unit_diffusion, 0.0f64, w[..], 0.1f64, noise[..], scratch[..1usize]) != ode.TooSmall { os.exit(6i32) }

    try io.print("math ode ok\n")
    ret ok
}
