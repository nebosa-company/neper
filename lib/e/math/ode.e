// Time stepping for ordinary and stochastic differential equations over `f64`
// state vectors: explicit Euler, classical fourth-order Runge-Kutta, adaptive
// Runge-Kutta-Fehlberg 4(5), velocity Verlet and leapfrog for second-order
// systems, Yoshida's fourth-order symplectic composition, and Euler-Maruyama
// for stochastic equations.
//
// A system is a function `f(ctx, t, y, dydt)` writing the derivative of `y`
// into `dydt`; a second-order system is `acceleration(ctx, x, a)`. Every
// stepper works in place on caller storage and takes its scratch from the
// caller too, sized as each declaration says.

use e.math
use e.mem

error TooSmall
error Invalid

// Whether scratch can hold `vectors` state vectors of `count` entries without
// forming their product first.  The division is deliberate: a caller can pass
// a target-width count that would overflow a `usize` multiplication.
fn has_scratch(scratch_len: usize, count: usize, vectors: usize) -> bool {
    if vectors == 0usize { ret true }
    ret count <= scratch_len / vectors
}

// One explicit Euler step of size `h`; `scratch.len >= y.len`.
fn euler[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, scratch: []f64) -> err {
    let n = y.len
    if scratch.len < n { ret TooSmall }
    var k = scratch[..n]
    f(ctx, t, y, k)
    var i = 0usize
    while i < n {
        y[i] += h * k[i]
        i += 1usize
    }
    ret ok
}

// One classical RK4 step; `scratch.len >= 5 * y.len`.
fn rk4[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, scratch: []f64) -> err {
    let n = y.len
    if !has_scratch(scratch.len, n, 5usize) { ret TooSmall }
    var k1 = scratch[..n]
    var k2 = scratch[n..2usize * n]
    var k3 = scratch[2usize * n..3usize * n]
    var k4 = scratch[3usize * n..4usize * n]
    var tmp = scratch[4usize * n..5usize * n]
    f(ctx, t, y, k1)
    var i = 0usize
    while i < n {
        tmp[i] = y[i] + 0.5f64 * h * k1[i]
        i += 1usize
    }
    f(ctx, t + 0.5f64 * h, tmp, k2)
    i = 0usize
    while i < n {
        tmp[i] = y[i] + 0.5f64 * h * k2[i]
        i += 1usize
    }
    f(ctx, t + 0.5f64 * h, tmp, k3)
    i = 0usize
    while i < n {
        tmp[i] = y[i] + h * k3[i]
        i += 1usize
    }
    f(ctx, t + h, tmp, k4)
    i = 0usize
    while i < n {
        y[i] += h / 6.0f64 * (k1[i] + 2.0f64 * k2[i] + 2.0f64 * k3[i] + k4[i])
        i += 1usize
    }
    ret ok
}

// One Runge-Kutta-Fehlberg 4(5) step attempt: advances `y` by the fifth-order
// estimate when the error estimate is within `tolerance` (absolute, max norm)
// and answers the step taken and a suggested next step size; a rejected step
// leaves `y` alone and answers a taken step of 0. `scratch.len >= 8 * y.len`.
fn rkf45[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, tolerance: f64, scratch: []f64) -> (f64, f64, err) {
    let n = y.len
    if !has_scratch(scratch.len, n, 8usize) { ret (0.0f64, h, TooSmall) }
    var k1 = scratch[..n]
    var k2 = scratch[n..2usize * n]
    var k3 = scratch[2usize * n..3usize * n]
    var k4 = scratch[3usize * n..4usize * n]
    var k5 = scratch[4usize * n..5usize * n]
    var k6 = scratch[5usize * n..6usize * n]
    var tmp = scratch[6usize * n..7usize * n]
    var y5 = scratch[7usize * n..8usize * n]
    f(ctx, t, y, k1)
    var i = 0usize
    while i < n {
        tmp[i] = y[i] + h * (0.25f64 * k1[i])
        i += 1usize
    }
    f(ctx, t + 0.25f64 * h, tmp, k2)
    i = 0usize
    while i < n {
        tmp[i] = y[i] + h * (3.0f64 / 32.0f64 * k1[i] + 9.0f64 / 32.0f64 * k2[i])
        i += 1usize
    }
    f(ctx, t + 3.0f64 / 8.0f64 * h, tmp, k3)
    i = 0usize
    while i < n {
        tmp[i] = y[i] + h * (1932.0f64 / 2197.0f64 * k1[i] - 7200.0f64 / 2197.0f64 * k2[i] + 7296.0f64 / 2197.0f64 * k3[i])
        i += 1usize
    }
    f(ctx, t + 12.0f64 / 13.0f64 * h, tmp, k4)
    i = 0usize
    while i < n {
        tmp[i] = y[i] + h * (439.0f64 / 216.0f64 * k1[i] - 8.0f64 * k2[i] + 3680.0f64 / 513.0f64 * k3[i] - 845.0f64 / 4104.0f64 * k4[i])
        i += 1usize
    }
    f(ctx, t + h, tmp, k5)
    i = 0usize
    while i < n {
        tmp[i] = y[i] + h * (0.0f64 - 8.0f64 / 27.0f64 * k1[i] + 2.0f64 * k2[i] - 3544.0f64 / 2565.0f64 * k3[i] + 1859.0f64 / 4104.0f64 * k4[i] - 11.0f64 / 40.0f64 * k5[i])
        i += 1usize
    }
    f(ctx, t + 0.5f64 * h, tmp, k6)
    var worst = 0.0f64
    i = 0usize
    while i < n {
        let fourth = y[i] + h * (25.0f64 / 216.0f64 * k1[i] + 1408.0f64 / 2565.0f64 * k3[i] + 2197.0f64 / 4104.0f64 * k4[i] - 0.2f64 * k5[i])
        y5[i] = y[i] + h * (16.0f64 / 135.0f64 * k1[i] + 6656.0f64 / 12825.0f64 * k3[i] + 28561.0f64 / 56430.0f64 * k4[i] - 9.0f64 / 50.0f64 * k5[i] + 2.0f64 / 55.0f64 * k6[i])
        var e = y5[i] - fourth
        if e < 0.0f64 { e = 0.0f64 - e }
        if e > worst { worst = e }
        i += 1usize
    }
    var factor = 4.0f64
    if worst > 0.0f64 {
        factor = 0.84f64 * root4(tolerance / worst)
        if factor < 0.1f64 { factor = 0.1f64 }
        if factor > 4.0f64 { factor = 4.0f64 }
    }
    if worst <= tolerance {
        i = 0usize
        while i < n {
            y[i] = y5[i]
            i += 1usize
        }
        ret (h, h * factor, ok)
    }
    ret (0.0f64, h * factor, ok)
}

// The fourth root as two square roots. `math.sqrt` is correctly rounded at every
// magnitude; the hand-rolled Newton loop here was not (1e-100 came back ~4e-25), so
// a tiny step scaled the Euler-Maruyama noise wrongly (#130).
fn root4(x: f64) -> f64 { ret math.sqrt[f64](math.sqrt[f64](x)) }

// One velocity Verlet step for `x'' = acceleration(x)`: positions `x` and
// velocities `v` of equal length; `scratch.len >= 2 * x.len` holds the
// accelerations at the two ends.
fn verlet[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err {
    let n = x.len
    if v.len != n || !has_scratch(scratch.len, n, 2usize) { ret TooSmall }
    var a0 = scratch[..n]
    var a1 = scratch[n..2usize * n]
    acceleration(ctx, x, a0)
    var i = 0usize
    while i < n {
        x[i] += h * v[i] + 0.5f64 * h * h * a0[i]
        i += 1usize
    }
    acceleration(ctx, x, a1)
    i = 0usize
    while i < n {
        v[i] += 0.5f64 * h * (a0[i] + a1[i])
        i += 1usize
    }
    ret ok
}

// One leapfrog (kick-drift-kick) step, the same trajectory as Verlet with the
// velocity at whole steps; `scratch.len >= x.len`.
fn leapfrog[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err {
    let n = x.len
    if v.len != n || scratch.len < n { ret TooSmall }
    var acc = scratch[..n]
    acceleration(ctx, x, acc)
    var i = 0usize
    while i < n {
        v[i] += 0.5f64 * h * acc[i]
        x[i] += h * v[i]
        i += 1usize
    }
    acceleration(ctx, x, acc)
    i = 0usize
    while i < n {
        v[i] += 0.5f64 * h * acc[i]
        i += 1usize
    }
    ret ok
}

// Yoshida's fourth-order symplectic step: three leapfrog substeps with the
// weights `w1, w0, w1` where `w0 = -2^(1/3) / (2 - 2^(1/3))`.
fn yoshida[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err {
    let cube_root_two = 1.2599210498948732f64
    let w1 = 1.0f64 / (2.0f64 - cube_root_two)
    let w0 = 0.0f64 - cube_root_two / (2.0f64 - cube_root_two)
    let first = leapfrog[Ctx](ctx, acceleration, x, v, w1 * h, scratch)
    if first != ok { ret first }
    let second = leapfrog[Ctx](ctx, acceleration, x, v, w0 * h, scratch)
    if second != ok { ret second }
    ret leapfrog[Ctx](ctx, acceleration, x, v, w1 * h, scratch)
}

// One Euler-Maruyama step of `dy = drift(t, y) dt + diffusion(t, y) dW`, with
// `noise` the standard normal increments for this step (one per component);
// `scratch.len >= 2 * y.len`.
fn euler_maruyama[Ctx: type](ctx: *Ctx, drift: fn(*Ctx, f64, []const f64, []f64), diffusion: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, noise: []const f64, scratch: []f64) -> err {
    if h < 0.0f64 { ret Invalid }
    let n = y.len
    if noise.len < n || !has_scratch(scratch.len, n, 2usize) { ret TooSmall }
    var a = scratch[..n]
    var b = scratch[n..2usize * n]
    drift(ctx, t, y, a)
    diffusion(ctx, t, y, b)
    let root_h = math.sqrt[f64](h)
    var i = 0usize
    while i < n {
        y[i] += h * a[i] + b[i] * root_h * noise[i]
        i += 1usize
    }
    ret ok
}

// ---- deSolve's rk() family (rk_auto.c): adaptive embedded Runge-Kutta with output at the
// requested times. Methods: 0 rk23bs (ode23), 1 rk45dp7 (ode45, dense output), 2 rk45f
// (Fehlberg), 3 rk45ck (Cash-Karp, dense output), 4 rk45dp6, 5 rk45e, 6 rk23, 7 rk34f.

type RkTab = struct { stage: usize, qerr: usize, fsal: bool, dense: usize }

type RkRun = struct { t: f64, dt: f64, errold: f64, it_ext: usize, it_tot: usize, it_rej: usize, istate: i64 }

fn rk_a(a: []f64, stage: usize, j: usize, k: usize, v: f64) { a[j + stage * k] = v }

fn rk_vec(x: []f64, v0: f64, v1: f64, v2: f64, v3: f64, v4: f64, v5: f64, v6: f64) {
    x[0usize] = v0
    x[1usize] = v1
    x[2usize] = v2
    x[3usize] = v3
    x[4usize] = v4
    x[5usize] = v5
    x[6usize] = v6
}

// Fills the Butcher tableau (A column-major stage x stage, b1, b2, c, d) of a method.
fn rk_method(id: usize, a: []f64, b1: []f64, b2: []f64, c: []f64, d: []f64) -> RkTab {
    var tab = RkTab { stage: 4usize, qerr: 2usize, fsal: false, dense: 0usize }
    var i = 0usize
    while i < 49usize {
        a[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 7usize {
        b1[i] = 0.0f64
        b2[i] = 0.0f64
        c[i] = 0.0f64
        d[i] = 0.0f64
        i += 1usize
    }
    if id == 0usize {
        tab.fsal = true
        rk_a(a, 4usize, 1usize, 0usize, 1.0f64 / 2.0f64)
        rk_a(a, 4usize, 2usize, 1usize, 3.0f64 / 4.0f64)
        rk_a(a, 4usize, 3usize, 0usize, 2.0f64 / 9.0f64)
        rk_a(a, 4usize, 3usize, 1usize, 1.0f64 / 3.0f64)
        rk_a(a, 4usize, 3usize, 2usize, 4.0f64 / 9.0f64)
        rk_vec(b1, 7.0f64 / 24.0f64, 1.0f64 / 4.0f64, 1.0f64 / 3.0f64, 1.0f64 / 8.0f64, 0.0f64, 0.0f64, 0.0f64)
        rk_vec(b2, 2.0f64 / 9.0f64, 1.0f64 / 3.0f64, 4.0f64 / 9.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 2.0f64, 3.0f64 / 4.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64)
    }
    if id == 6usize {
        tab.stage = 3usize
        rk_a(a, 3usize, 1usize, 0usize, 1.0f64 / 2.0f64)
        rk_a(a, 3usize, 2usize, 0usize, 0.0f64 - 1.0f64)
        rk_a(a, 3usize, 2usize, 1usize, 2.0f64)
        rk_vec(b1, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
        rk_vec(b2, 1.0f64 / 6.0f64, 2.0f64 / 3.0f64, 1.0f64 / 6.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 2.0f64, 2.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64)
    }
    if id == 7usize {
        tab.stage = 5usize
        tab.qerr = 3usize
        rk_a(a, 5usize, 1usize, 0usize, 2.0f64 / 7.0f64)
        rk_a(a, 5usize, 2usize, 0usize, 77.0f64 / 900.0f64)
        rk_a(a, 5usize, 2usize, 1usize, 343.0f64 / 900.0f64)
        rk_a(a, 5usize, 3usize, 0usize, 805.0f64 / 1444.0f64)
        rk_a(a, 5usize, 3usize, 1usize, 0.0f64 - 77175.0f64 / 54872.0f64)
        rk_a(a, 5usize, 3usize, 2usize, 97125.0f64 / 54872.0f64)
        rk_a(a, 5usize, 4usize, 0usize, 79.0f64 / 490.0f64)
        rk_a(a, 5usize, 4usize, 2usize, 2175.0f64 / 3626.0f64)
        rk_a(a, 5usize, 4usize, 3usize, 2166.0f64 / 9065.0f64)
        rk_vec(b1, 79.0f64 / 490.0f64, 0.0f64, 2175.0f64 / 3626.0f64, 2166.0f64 / 9065.0f64, 0.0f64, 0.0f64, 0.0f64)
        rk_vec(b2, 229.0f64 / 1470.0f64, 0.0f64, 1125.0f64 / 1813.0f64, 13718.0f64 / 81585.0f64, 1.0f64 / 18.0f64, 0.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 2.0f64 / 7.0f64, 7.0f64 / 15.0f64, 35.0f64 / 38.0f64, 1.0f64, 0.0f64, 0.0f64)
    }
    if id == 2usize || id == 3usize || id == 4usize || id == 5usize {
        tab.stage = 6usize
        tab.qerr = 4usize
    }
    if id == 2usize {
        rk_a(a, 6usize, 1usize, 0usize, 1.0f64 / 4.0f64)
        rk_a(a, 6usize, 2usize, 0usize, 3.0f64 / 32.0f64)
        rk_a(a, 6usize, 2usize, 1usize, 9.0f64 / 32.0f64)
        rk_a(a, 6usize, 3usize, 0usize, 1932.0f64 / 2197.0f64)
        rk_a(a, 6usize, 3usize, 1usize, 0.0f64 - 7200.0f64 / 2197.0f64)
        rk_a(a, 6usize, 3usize, 2usize, 7296.0f64 / 2197.0f64)
        rk_a(a, 6usize, 4usize, 0usize, 439.0f64 / 216.0f64)
        rk_a(a, 6usize, 4usize, 1usize, 0.0f64 - 8.0f64)
        rk_a(a, 6usize, 4usize, 2usize, 3680.0f64 / 513.0f64)
        rk_a(a, 6usize, 4usize, 3usize, 0.0f64 - 845.0f64 / 4104.0f64)
        rk_a(a, 6usize, 5usize, 0usize, 0.0f64 - 8.0f64 / 27.0f64)
        rk_a(a, 6usize, 5usize, 1usize, 2.0f64)
        rk_a(a, 6usize, 5usize, 2usize, 0.0f64 - 3544.0f64 / 2565.0f64)
        rk_a(a, 6usize, 5usize, 3usize, 1859.0f64 / 4104.0f64)
        rk_a(a, 6usize, 5usize, 4usize, 0.0f64 - 11.0f64 / 40.0f64)
        rk_vec(b1, 25.0f64 / 216.0f64, 0.0f64, 1408.0f64 / 2565.0f64, 2197.0f64 / 4104.0f64, 0.0f64 - 1.0f64 / 5.0f64, 0.0f64, 0.0f64)
        rk_vec(b2, 16.0f64 / 135.0f64, 0.0f64, 6656.0f64 / 12825.0f64, 28561.0f64 / 56430.0f64, 0.0f64 - 9.0f64 / 50.0f64, 2.0f64 / 55.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 4.0f64, 3.0f64 / 8.0f64, 12.0f64 / 13.0f64, 1.0f64, 1.0f64 / 2.0f64, 0.0f64)
    }
    if id == 3usize {
        tab.fsal = true
        tab.dense = 2usize
        rk_a(a, 6usize, 1usize, 0usize, 1.0f64 / 5.0f64)
        rk_a(a, 6usize, 2usize, 0usize, 3.0f64 / 40.0f64)
        rk_a(a, 6usize, 2usize, 1usize, 9.0f64 / 40.0f64)
        rk_a(a, 6usize, 3usize, 0usize, 3.0f64 / 10.0f64)
        rk_a(a, 6usize, 3usize, 1usize, 0.0f64 - 9.0f64 / 10.0f64)
        rk_a(a, 6usize, 3usize, 2usize, 6.0f64 / 5.0f64)
        rk_a(a, 6usize, 4usize, 0usize, 0.0f64 - 11.0f64 / 54.0f64)
        rk_a(a, 6usize, 4usize, 1usize, 5.0f64 / 2.0f64)
        rk_a(a, 6usize, 4usize, 2usize, 0.0f64 - 70.0f64 / 27.0f64)
        rk_a(a, 6usize, 4usize, 3usize, 35.0f64 / 27.0f64)
        rk_a(a, 6usize, 5usize, 0usize, 1631.0f64 / 55296.0f64)
        rk_a(a, 6usize, 5usize, 1usize, 175.0f64 / 512.0f64)
        rk_a(a, 6usize, 5usize, 2usize, 575.0f64 / 13824.0f64)
        rk_a(a, 6usize, 5usize, 3usize, 44275.0f64 / 110592.0f64)
        rk_a(a, 6usize, 5usize, 4usize, 253.0f64 / 4096.0f64)
        rk_vec(b1, 2825.0f64 / 27648.0f64, 0.0f64, 18575.0f64 / 48384.0f64, 13525.0f64 / 55296.0f64, 277.0f64 / 14336.0f64, 1.0f64 / 4.0f64, 0.0f64)
        rk_vec(b2, 37.0f64 / 378.0f64, 0.0f64, 250.0f64 / 621.0f64, 125.0f64 / 594.0f64, 0.0f64, 512.0f64 / 1771.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 5.0f64, 3.0f64 / 10.0f64, 3.0f64 / 5.0f64, 1.0f64, 7.0f64 / 8.0f64, 0.0f64)
    }
    if id == 4usize {
        rk_a(a, 6usize, 1usize, 0usize, 1.0f64 / 5.0f64)
        rk_a(a, 6usize, 2usize, 0usize, 3.0f64 / 40.0f64)
        rk_a(a, 6usize, 2usize, 1usize, 9.0f64 / 40.0f64)
        rk_a(a, 6usize, 3usize, 0usize, 3.0f64 / 10.0f64)
        rk_a(a, 6usize, 3usize, 1usize, 0.0f64 - 9.0f64 / 10.0f64)
        rk_a(a, 6usize, 3usize, 2usize, 6.0f64 / 5.0f64)
        rk_a(a, 6usize, 4usize, 0usize, 226.0f64 / 729.0f64)
        rk_a(a, 6usize, 4usize, 1usize, 0.0f64 - 25.0f64 / 27.0f64)
        rk_a(a, 6usize, 4usize, 2usize, 880.0f64 / 729.0f64)
        rk_a(a, 6usize, 4usize, 3usize, 55.0f64 / 729.0f64)
        rk_a(a, 6usize, 5usize, 0usize, 0.0f64 - 181.0f64 / 270.0f64)
        rk_a(a, 6usize, 5usize, 1usize, 5.0f64 / 2.0f64)
        rk_a(a, 6usize, 5usize, 2usize, 0.0f64 - 266.0f64 / 297.0f64)
        rk_a(a, 6usize, 5usize, 3usize, 0.0f64 - 91.0f64 / 27.0f64)
        rk_a(a, 6usize, 5usize, 4usize, 189.0f64 / 55.0f64)
        rk_vec(b1, 31.0f64 / 540.0f64, 0.0f64, 190.0f64 / 297.0f64, 0.0f64 - 145.0f64 / 108.0f64, 351.0f64 / 220.0f64, 1.0f64 / 20.0f64, 0.0f64)
        rk_vec(b2, 19.0f64 / 216.0f64, 0.0f64, 1000.0f64 / 2079.0f64, 0.0f64 - 125.0f64 / 216.0f64, 81.0f64 / 88.0f64, 5.0f64 / 56.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 5.0f64, 3.0f64 / 10.0f64, 3.0f64 / 5.0f64, 2.0f64 / 3.0f64, 1.0f64, 0.0f64)
    }
    if id == 5usize {
        rk_a(a, 6usize, 1usize, 0usize, 1.0f64 / 2.0f64)
        rk_a(a, 6usize, 2usize, 0usize, 1.0f64 / 4.0f64)
        rk_a(a, 6usize, 2usize, 1usize, 1.0f64 / 4.0f64)
        rk_a(a, 6usize, 3usize, 1usize, 0.0f64 - 1.0f64)
        rk_a(a, 6usize, 3usize, 2usize, 2.0f64)
        rk_a(a, 6usize, 4usize, 0usize, 7.0f64 / 27.0f64)
        rk_a(a, 6usize, 4usize, 1usize, 10.0f64 / 27.0f64)
        rk_a(a, 6usize, 4usize, 3usize, 1.0f64 / 27.0f64)
        rk_a(a, 6usize, 5usize, 0usize, 28.0f64 / 625.0f64)
        rk_a(a, 6usize, 5usize, 1usize, 0.0f64 - 125.0f64 / 625.0f64)
        rk_a(a, 6usize, 5usize, 2usize, 546.0f64 / 625.0f64)
        rk_a(a, 6usize, 5usize, 3usize, 54.0f64 / 625.0f64)
        rk_a(a, 6usize, 5usize, 4usize, 0.0f64 - 378.0f64 / 625.0f64)
        rk_vec(b1, 1.0f64 / 6.0f64, 0.0f64, 4.0f64 / 6.0f64, 1.0f64 / 6.0f64, 0.0f64, 0.0f64, 0.0f64)
        rk_vec(b2, 14.0f64 / 336.0f64, 0.0f64, 0.0f64, 35.0f64 / 336.0f64, 162.0f64 / 336.0f64, 125.0f64 / 336.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 2.0f64, 1.0f64 / 2.0f64, 1.0f64, 2.0f64 / 3.0f64, 1.0f64 / 5.0f64, 0.0f64)
    }
    if id == 1usize {
        tab.stage = 7usize
        tab.qerr = 4usize
        tab.fsal = true
        tab.dense = 1usize
        rk_a(a, 7usize, 1usize, 0usize, 1.0f64 / 5.0f64)
        rk_a(a, 7usize, 2usize, 0usize, 3.0f64 / 40.0f64)
        rk_a(a, 7usize, 2usize, 1usize, 9.0f64 / 40.0f64)
        rk_a(a, 7usize, 3usize, 0usize, 44.0f64 / 45.0f64)
        rk_a(a, 7usize, 3usize, 1usize, 0.0f64 - 56.0f64 / 15.0f64)
        rk_a(a, 7usize, 3usize, 2usize, 32.0f64 / 9.0f64)
        rk_a(a, 7usize, 4usize, 0usize, 19372.0f64 / 6561.0f64)
        rk_a(a, 7usize, 4usize, 1usize, 0.0f64 - 25360.0f64 / 2187.0f64)
        rk_a(a, 7usize, 4usize, 2usize, 64448.0f64 / 6561.0f64)
        rk_a(a, 7usize, 4usize, 3usize, 0.0f64 - 212.0f64 / 729.0f64)
        rk_a(a, 7usize, 5usize, 0usize, 9017.0f64 / 3168.0f64)
        rk_a(a, 7usize, 5usize, 1usize, 0.0f64 - 355.0f64 / 33.0f64)
        rk_a(a, 7usize, 5usize, 2usize, 46732.0f64 / 5247.0f64)
        rk_a(a, 7usize, 5usize, 3usize, 49.0f64 / 176.0f64)
        rk_a(a, 7usize, 5usize, 4usize, 0.0f64 - 5103.0f64 / 18656.0f64)
        rk_a(a, 7usize, 6usize, 0usize, 35.0f64 / 384.0f64)
        rk_a(a, 7usize, 6usize, 2usize, 500.0f64 / 1113.0f64)
        rk_a(a, 7usize, 6usize, 3usize, 125.0f64 / 192.0f64)
        rk_a(a, 7usize, 6usize, 4usize, 0.0f64 - 2187.0f64 / 6784.0f64)
        rk_a(a, 7usize, 6usize, 5usize, 11.0f64 / 84.0f64)
        rk_vec(b1, 5179.0f64 / 57600.0f64, 0.0f64, 7571.0f64 / 16695.0f64, 393.0f64 / 640.0f64, 0.0f64 - 92097.0f64 / 339200.0f64, 187.0f64 / 2100.0f64, 1.0f64 / 40.0f64)
        rk_vec(b2, 35.0f64 / 384.0f64, 0.0f64, 500.0f64 / 1113.0f64, 125.0f64 / 192.0f64, 0.0f64 - 2187.0f64 / 6784.0f64, 11.0f64 / 84.0f64, 0.0f64)
        rk_vec(c, 0.0f64, 1.0f64 / 5.0f64, 3.0f64 / 10.0f64, 4.0f64 / 5.0f64, 8.0f64 / 9.0f64, 1.0f64, 1.0f64)
        rk_vec(d, 0.0f64 - 12715105075.0f64 / 11282082432.0f64, 0.0f64, 87487479700.0f64 / 32700410799.0f64, 0.0f64 - 10690763975.0f64 / 1880347072.0f64, 701980252875.0f64 / 199316789632.0f64, 0.0f64 - 1453857185.0f64 / 822651844.0f64, 69997945.0f64 / 29380423.0f64)
    }
    ret tab
}

fn rk_fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn rk_fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn rk_maxerr(y0: []const f64, y1: []const f64, y2: []const f64, atol: []const f64, rtol: []const f64, n: usize) -> f64 {
    var serr = 0.0f64
    var i = 0usize
    while i < n {
        let scal = atol[i] + rk_fmax(math.abs[f64](y0[i]), math.abs[f64](y2[i])) * rtol[i]
        let delta = math.abs[f64](y2[i] - y1[i])
        if scal > 0.0f64 {
            let q = delta / scal
            serr += q * q
        }
        i += 1usize
    }
    ret math.sqrt[f64](serr / f64(n))
}

// rk_auto.c main loop over [run.t, tmax]; the slices are blocks of scratch laid out by rk_solve.
fn rk_core[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), tab: RkTab, n: usize, nt: usize, interpolate: bool, tmax: f64, hmin: f64, hmax: f64, alpha: f64, beta: f64, maxsteps: usize, tt: []const f64, yout: []f64, run: *RkRun, y0: []f64, y1: []f64, y2: []f64, dy1: []f64, dy2: []f64, fj: []f64, tmp: []f64, ff: []f64, rr: []f64, a: []const f64, b1: []const f64, b2: []const f64, c: []const f64, d: []const f64, atol: []const f64, rtol: []const f64) {
    let stage = tab.stage
    var accept = false
    var t = run.t
    var dt = run.dt
    var errold = run.errold
    var dtnew = dt
    let eps = 2.220446049250313e-16f64
    while true {
        var j1 = 0usize
        var i = 0usize
        if tab.fsal && accept {
            j1 = 1usize
            while i < n {
                ff[i] = ff[i + n * (stage - 1usize)]
                i += 1usize
            }
        }
        var j = j1
        while j < stage {
            i = 0usize
            while i < n {
                fj[i] = 0.0f64
                i += 1usize
            }
            var k = 0usize
            while k < j {
                i = 0usize
                while i < n {
                    fj[i] = fj[i] + a[j + stage * k] * ff[i + n * k] * dt
                    i += 1usize
                }
                k += 1usize
            }
            i = 0usize
            while i < n {
                tmp[i] = fj[i] + y0[i]
                i += 1usize
            }
            f(ctx, t + dt * c[j], tmp, ff[n * j..n * (j + 1usize)])
            j += 1usize
        }
        i = 0usize
        while i < n {
            var s1 = 0.0f64
            var s2 = 0.0f64
            var k = 0usize
            while k < stage {
                s1 += ff[i + n * k] * b1[k]
                s2 += ff[i + n * k] * b2[k]
                k += 1usize
            }
            dy1[i] = s1
            dy2[i] = s2
            i += 1usize
        }
        run.it_tot += 1usize
        i = 0usize
        while i < n {
            y1[i] = y0[i] + dt * dy1[i]
            y2[i] = y0[i] + dt * dy2[i]
            i += 1usize
        }
        let rerr = rk_maxerr(y0, y1, y2, atol, rtol, n)
        dtnew = dt
        if rerr == 0.0f64 {
            dtnew = rk_fmin(dt * 10.0f64, hmax)
            errold = rk_fmax(rerr, 1.0e-4f64)
            accept = true
        } else {
            if rerr < 1.0f64 {
                if accept {
                    dtnew = rk_fmin(hmax, dt * rk_fmin(0.9f64 * math.pow[f64](rerr, 0.0f64 - alpha) * math.pow[f64](errold, beta), 10.0f64))
                }
                errold = rk_fmax(rerr, 1.0e-4f64)
                accept = true
            } else {
                if rerr > 1.0f64 {
                    run.it_rej += 1usize
                    accept = false
                    dtnew = dt * rk_fmax(0.9f64 * math.pow[f64](rerr, 0.0f64 - alpha), 0.2f64)
                }
            }
        }
        if dtnew < hmin {
            accept = true
            run.istate = 0i64 - 2i64
            dtnew = hmin
        }
        if accept {
            if interpolate {
                if tab.dense == 1usize {
                    i = 0usize
                    while i < n {
                        rr[i] = y0[i]
                        let ydiff = y2[i] - y0[i]
                        rr[i + n] = ydiff
                        let bspl = dt * ff[i] - ydiff
                        rr[i + 2usize * n] = bspl
                        rr[i + 3usize * n] = ydiff - dt * ff[i + (stage - 1usize) * n] - bspl
                        var s = 0.0f64
                        var k = 0usize
                        while k < stage {
                            s = s + d[k] * ff[i + k * n]
                            k += 1usize
                        }
                        rr[i + 4usize * n] = s * dt
                        i += 1usize
                    }
                } else {
                    f(ctx, t + dt, y2, dy2)
                }
                var t_ext = tt[run.it_ext]
                while t_ext <= t + dt {
                    let s = (t_ext - t) / dt
                    if tab.dense == 1usize {
                        let s1 = 1.0f64 - s
                        i = 0usize
                        while i < n {
                            tmp[i] = rr[i] + s * (rr[i + n] + s1 * (rr[i + 2usize * n] + s * (rr[i + 3usize * n] + s1 * (rr[i + 4usize * n]))))
                            i += 1usize
                        }
                    } else {
                        let s2 = s * s
                        let s3 = s2 * s
                        let s4 = s3 * s
                        let b3 = 500.0f64 / 161.0f64 * s2 - 20000.0f64 / 4347.0f64 * s3 + 2750.0f64 / 1449.0f64 * s4
                        let b4 = 125.0f64 / 132.0f64 * s2 - 625.0f64 / 594.0f64 * s3 + 125.0f64 / 396.0f64 * s4
                        let b5 = 15.0f64 / 28.0f64 * s2 - 15.0f64 / 14.0f64 * s3 + 15.0f64 / 28.0f64 * s4
                        let b6 = 0.0f64 - 6144.0f64 / 1771.0f64 * s2 + 2048.0f64 / 253.0f64 * s3 - 7680.0f64 / 1771.0f64 * s4
                        let b7 = 3.0f64 / 2.0f64 * s2 - 4.0f64 * s3 + 5.0f64 / 2.0f64 * s4
                        let bb1 = s - b3 - b4 - b5 - b6 - b7
                        i = 0usize
                        while i < n {
                            tmp[i] = y0[i] + bb1 * dt * ff[i] + b3 * dt * ff[i + 2usize * n] + b4 * dt * ff[i + 3usize * n] + b5 * dt * ff[i + 4usize * n] + b6 * dt * ff[i + 5usize * n] + b7 * dt * dy2[i]
                            i += 1usize
                        }
                    }
                    if run.it_ext < nt {
                        yout[run.it_ext] = t_ext
                        i = 0usize
                        while i < n {
                            yout[run.it_ext + nt * (1usize + i)] = tmp[i]
                            i += 1usize
                        }
                    }
                    if run.it_ext + 1usize < nt {
                        run.it_ext += 1usize
                        t_ext = tt[run.it_ext]
                    } else {
                        break
                    }
                }
                if tab.dense == 2usize {
                    i = 0usize
                    while i < n {
                        ff[i + n * (stage - 1usize)] = dy2[i]
                        i += 1usize
                    }
                }
            }
            t = t + dt
            i = 0usize
            while i < n {
                y0[i] = y2[i]
                i += 1usize
            }
        }
        dt = rk_fmin(dtnew, tmax - t)
        if run.it_tot > maxsteps {
            run.istate = 0i64 - 1i64
            break
        }
        if !(t < tmax - 100.0f64 * eps * dt) { break }
    }
    run.t = t
    run.dt = dtnew
    run.errold = errold
}

// deSolve ode(y0, times, f, method = ...) for the rk methods above. `out` is column-major
// times.len x (n + 1): time then the n states, as deSolve returns them. hmax <= 0 and
// hini < 0 take deSolve's defaults (largest time gap); tcrit < 0 means none.
// `scratch.len >= 19 * n + 80`. Returns Invalid for an unknown method or a failed run.
// deSolve 1.42 hands rk_auto its tolerances in the wrong order (rk.R passes atol where
// call_rkAuto reads Rtol), so the step control runs with the roles swapped; reproduced here.
fn rk_solve[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), method: usize, times: []const f64, y: []const f64, rtol: []const f64, atol: []const f64, hmin: f64, hmax_in: f64, hini_in: f64, tcrit_in: f64, maxsteps: usize, out: []f64, scratch: []f64) -> err {
    let n = y.len
    let nt = times.len
    if method > 7usize || nt < 2usize { ret Invalid }
    if scratch.len < 19usize * n + 80usize || out.len < nt * (n + 1usize) { ret TooSmall }
    let tb = 19usize * n
    let tab = rk_method(method, scratch[tb..tb + 49usize], scratch[tb + 49usize..tb + 56usize], scratch[tb + 56usize..tb + 63usize], scratch[tb + 63usize..tb + 70usize], scratch[tb + 70usize..tb + 77usize])
    let stage = tab.stage
    var hmax = hmax_in
    var i = 1usize
    if hmax <= 0.0f64 {
        while i < nt {
            hmax = rk_fmax(hmax, math.abs[f64](times[i] - times[i - 1usize]))
            i += 1usize
        }
    }
    var hini = hini_in
    if hini < 0.0f64 { hini = hmax }
    var tcrit = tcrit_in
    if tcrit < 0.0f64 { tcrit = times[nt - 1usize] }
    var y0 = scratch[..n]
    var y1 = scratch[n..2usize * n]
    var y2 = scratch[2usize * n..3usize * n]
    var dy1 = scratch[3usize * n..4usize * n]
    var dy2 = scratch[4usize * n..5usize * n]
    var fj = scratch[5usize * n..6usize * n]
    var tmp = scratch[6usize * n..7usize * n]
    var ff = scratch[7usize * n..14usize * n]
    var rr = scratch[14usize * n..19usize * n]
    let a = scratch[tb..tb + 49usize]
    let b1 = scratch[tb + 49usize..tb + 56usize]
    let b2 = scratch[tb + 56usize..tb + 63usize]
    let c = scratch[tb + 63usize..tb + 70usize]
    let d = scratch[tb + 70usize..tb + 77usize]
    let beta = 0.0f64
    let alpha = 1.0f64 / f64(tab.qerr) - 0.75f64 * beta
    let interpolate = tab.dense > 0usize
    out[0usize] = times[0usize]
    i = 0usize
    while i < n {
        y0[i] = y[i]
        out[(i + 1usize) * nt] = y[i]
        y1[i] = 0.0f64
        y2[i] = 0.0f64
        fj[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * stage {
        ff[i] = 0.0f64
        i += 1usize
    }
    var tmax = rk_fmax(times[nt - 1usize], tcrit)
    var run = RkRun { t: times[0usize], dt: rk_fmin(hmax, hini), errold: 0.0f64, it_ext: 0usize, it_tot: 0usize, it_rej: 0usize, istate: 0i64 }
    hmax = rk_fmin(hmax, tmax - run.t)
    if interpolate {
        rk_core[Ctx](ctx, f, tab, n, nt, true, tmax, hmin, hmax, alpha, beta, maxsteps, times, out, &run, y0, y1, y2, dy1, dy2, fj, tmp, ff, rr, a, b1, b2, c, d, rtol, atol)
    } else {
        var j = 0usize
        while j + 1usize < nt {
            run.t = times[j]
            tmax = rk_fmin(times[j + 1usize], tcrit)
            run.dt = tmax - run.t
            rk_core[Ctx](ctx, f, tab, n, nt, false, tmax, hmin, hmax, alpha, beta, maxsteps, times, out, &run, y0, y1, y2, dy1, dy2, fj, tmp, ff, rr, a, b1, b2, c, d, rtol, atol)
            out[j + 1usize] = tmax
            i = 0usize
            while i < n {
                out[j + 1usize + nt * (1usize + i)] = y2[i]
                i += 1usize
            }
            j += 1usize
        }
    }
    if run.istate != 0i64 { ret Invalid }
    ret ok
}

// ---- ODEPACK DLSODA (Petzold/Hindmarsh), the engine behind deSolve's lsoda(): Adams/BDF
// auto-switching with the full internal finite-difference Jacobian (jt = 2), itask = 1,
// scalar tolerances (itol = 1). A line-by-line port of dlsoda/dstoda/dprja/dcfode/dintdy/
// dgefa/dgesl; the Fortran GOTOs become a label variable stepped through a loop.

type Lsoda = struct {
    n: usize, nyh: usize,
    conit: f64, crate: f64, hold: f64, rmax: f64, ccmax: f64, el0: f64, h: f64, hmin: f64, hmxi: f64,
    hu: f64, rc: f64, tn: f64, uround: f64,
    ialth: usize, ipup: usize, lmax: usize, nqnyh: usize, nslp: usize,
    icf: i64, ierpj: i64, iersl: i64, jcur: usize, jstart: i64, kflag: i64, l: usize,
    meth: usize, miter: usize, maxord: usize, maxcor: usize, msbp: usize, mxncf: usize,
    nq: usize, nst: usize, nfe: usize, nje: usize, nqu: usize,
    pdest: f64, pdlast: f64, ratio: f64, pdnorm: f64, icount: i64, irflag: usize, jtyp: usize,
    mused: usize, mxordn: usize, mxords: usize, tsw: f64,
    mxstep: usize, nslast: usize, initd: bool, tolsf: f64,
    rtol: f64, atol: f64, mode: usize, tret: f64,
    ngc: usize, nge: usize, imax: usize, last: usize, irfnd: usize, itaskc: usize, one: bool,
    alpha: f64, x2: f64, t0: f64, t1: f64, tlast: f64, toutc: f64, xroot: f64,
    g0: []f64, g1: []f64, gx: []f64, jroot: []usize,
    yh: []f64, ewt: []f64, savf: []f64, acor: []f64, wm: []f64, el: []f64, elco: []f64, tesco: []f64,
    cm1: []f64, cm2: []f64, sm1: []f64, ipvt: []usize, ytmp: []f64, ftem: []f64
}

fn ls_elco(s: *Lsoda, i: usize, q: usize) -> f64 { ret s.elco[(q - 1usize) * 13usize + i - 1usize] }
fn ls_tesco(s: *Lsoda, k: usize, q: usize) -> f64 { ret s.tesco[(q - 1usize) * 3usize + k - 1usize] }

fn ls_sign(a: f64, b: f64) -> f64 {
    var m = math.abs[f64](a)
    if b < 0.0f64 { m = 0.0f64 - m }
    ret m
}

fn ls_dmnorm(n: usize, v: []const f64, w: []const f64) -> f64 {
    var vm = 0.0f64
    var i = 0usize
    while i < n {
        vm = rk_fmax(vm, math.abs[f64](v[i]) * w[i])
        i += 1usize
    }
    ret vm
}

fn ls_dcfode(meth: usize, elco: []f64, tesco: []f64) {
    var pc: [13]f64 = zero
    if meth == 1usize {
        elco[0usize] = 1.0f64
        elco[1usize] = 1.0f64
        tesco[0usize] = 0.0f64
        tesco[1usize] = 2.0f64
        tesco[3usize] = 1.0f64
        tesco[35usize] = 0.0f64
        pc[1usize] = 1.0f64
        var rqfac = 1.0f64
        var nq = 2usize
        while nq <= 12usize {
            let rq1fac = rqfac
            rqfac = rqfac / f64(nq)
            let nqm1 = nq - 1usize
            let fnqm1 = f64(nqm1)
            let nqp1 = nq + 1usize
            pc[nq] = 0.0f64
            var ib = 1usize
            while ib <= nqm1 {
                let i = nqp1 - ib
                pc[i] = pc[i - 1usize] + fnqm1 * pc[i]
                ib += 1usize
            }
            pc[1usize] = fnqm1 * pc[1usize]
            var pint = pc[1usize]
            var xpin = pc[1usize] / 2.0f64
            var tsign = 1.0f64
            var i = 2usize
            while i <= nq {
                tsign = 0.0f64 - tsign
                pint = pint + tsign * pc[i] / f64(i)
                xpin = xpin + tsign * pc[i] / f64(i + 1usize)
                i += 1usize
            }
            elco[(nq - 1usize) * 13usize] = pint * rq1fac
            elco[(nq - 1usize) * 13usize + 1usize] = 1.0f64
            i = 2usize
            while i <= nq {
                elco[(nq - 1usize) * 13usize + i] = rq1fac * pc[i] / f64(i)
                i += 1usize
            }
            let agamq = rqfac * xpin
            let ragq = 1.0f64 / agamq
            tesco[(nq - 1usize) * 3usize + 1usize] = ragq
            if nq < 12usize { tesco[nq * 3usize] = ragq * rqfac / f64(nqp1) }
            tesco[(nqm1 - 1usize) * 3usize + 2usize] = ragq
            nq += 1usize
        }
    } else {
        pc[1usize] = 1.0f64
        var rq1fac = 1.0f64
        var nq = 1usize
        while nq <= 5usize {
            let fnq = f64(nq)
            let nqp1 = nq + 1usize
            pc[nqp1] = 0.0f64
            var ib = 1usize
            while ib <= nq {
                let i = nq + 2usize - ib
                pc[i] = pc[i - 1usize] + fnq * pc[i]
                ib += 1usize
            }
            pc[1usize] = fnq * pc[1usize]
            var i = 1usize
            while i <= nqp1 {
                elco[(nq - 1usize) * 13usize + i - 1usize] = pc[i] / pc[2usize]
                i += 1usize
            }
            elco[(nq - 1usize) * 13usize + 1usize] = 1.0f64
            tesco[(nq - 1usize) * 3usize] = rq1fac
            tesco[(nq - 1usize) * 3usize + 1usize] = f64(nqp1) / elco[(nq - 1usize) * 13usize]
            tesco[(nq - 1usize) * 3usize + 2usize] = f64(nq + 2usize) / elco[(nq - 1usize) * 13usize]
            rq1fac = rq1fac / fnq
            nq += 1usize
        }
    }
}

// DGEFA on the n x n column-major matrix at wm[2..]; returns info (0 = fine).
fn ls_dgefa(a: []f64, n: usize, ipvt: []usize) -> usize {
    var info = 0usize
    var k = 0usize
    while k + 1usize < n {
        var l = k
        var big = math.abs[f64](a[k + k * n])
        var i = k + 1usize
        while i < n {
            let v = math.abs[f64](a[i + k * n])
            if v > big {
                big = v
                l = i
            }
            i += 1usize
        }
        ipvt[k] = l
        if a[l + k * n] == 0.0f64 {
            info = k + 1usize
        } else {
            if l != k {
                let t = a[l + k * n]
                a[l + k * n] = a[k + k * n]
                a[k + k * n] = t
            }
            let t = 0.0f64 - 1.0f64 / a[k + k * n]
            i = k + 1usize
            while i < n {
                a[i + k * n] = t * a[i + k * n]
                i += 1usize
            }
            var j = k + 1usize
            while j < n {
                let tj = a[l + j * n]
                if l != k {
                    a[l + j * n] = a[k + j * n]
                    a[k + j * n] = tj
                }
                i = k + 1usize
                while i < n {
                    a[i + j * n] = a[i + j * n] + tj * a[i + k * n]
                    i += 1usize
                }
                j += 1usize
            }
        }
        k += 1usize
    }
    ipvt[n - 1usize] = n - 1usize
    if a[n - 1usize + (n - 1usize) * n] == 0.0f64 { info = n }
    ret info
}

fn ls_dgesl(a: []const f64, n: usize, ipvt: []const usize, b: []f64) {
    var k = 0usize
    while k + 1usize < n {
        let l = ipvt[k]
        let t = b[l]
        if l != k {
            b[l] = b[k]
            b[k] = t
        }
        var i = k + 1usize
        while i < n {
            b[i] = b[i] + t * a[i + k * n]
            i += 1usize
        }
        k += 1usize
    }
    var kb = 1usize
    while kb <= n {
        let kk = n - kb
        b[kk] = b[kk] / a[kk + kk * n]
        let t = 0.0f64 - b[kk]
        var i = 0usize
        while i < kk {
            b[i] = b[i] + t * a[i + kk * n]
            i += 1usize
        }
        kb += 1usize
    }
}

// DINTDY with k = 0: the interpolated solution at t into dky. Returns 0, or -2 when t is outside the step.
fn ls_intdy0(s: *Lsoda, t: f64, dky: []f64) -> i64 {
    let n = s.n
    let tp = s.tn - s.hu - 100.0f64 * s.uround * ls_sign(math.abs[f64](s.tn) + math.abs[f64](s.hu), s.hu)
    if (t - tp) * (t - s.tn) > 0.0f64 { ret 0i64 - 2i64 }
    let sv = (t - s.tn) / s.h
    var i = 0usize
    while i < n {
        dky[i] = 1.0f64 * s.yh[(s.l - 1usize) * n + i]
        i += 1usize
    }
    var jb = 1usize
    while jb <= s.nq {
        let jp1 = s.nq - jb + 1usize
        i = 0usize
        while i < n {
            dky[i] = 1.0f64 * s.yh[(jp1 - 1usize) * n + i] + sv * dky[i]
            i += 1usize
        }
        jb += 1usize
    }
    ret 0i64
}

// DPRJA with miter = 2: finite-difference Jacobian, scaled, I - hl0*J, LU.
fn ls_prja[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Lsoda, y: []f64) {
    let n = s.n
    s.nje += 1usize
    s.ierpj = 0i64
    s.jcur = 1usize
    let hl0 = s.h * s.el0
    var fac = ls_dmnorm(n, s.savf, s.ewt)
    var r0 = 1000.0f64 * math.abs[f64](s.h) * s.uround * f64(n) * fac
    if r0 == 0.0f64 { r0 = 1.0f64 }
    let srur = s.wm[0usize]
    var j1 = 2usize
    var j = 0usize
    while j < n {
        let yj = y[j]
        let r = rk_fmax(srur * math.abs[f64](yj), r0 / s.ewt[j])
        y[j] = y[j] + r
        fac = (0.0f64 - hl0) / r
        f(ctx, s.tn, y, s.ftem)
        var i = 0usize
        while i < n {
            s.wm[i + j1] = (s.ftem[i] - s.savf[i]) * fac
            i += 1usize
        }
        y[j] = yj
        j1 += n
        j += 1usize
    }
    s.nfe += n
    // dfnorm
    var an = 0.0f64
    var i = 0usize
    while i < n {
        var sum = 0.0f64
        j = 0usize
        while j < n {
            sum = sum + math.abs[f64](s.wm[2usize + i + j * n]) / s.ewt[j]
            j += 1usize
        }
        an = rk_fmax(an, sum * s.ewt[i])
        i += 1usize
    }
    s.pdnorm = an / math.abs[f64](hl0)
    i = 0usize
    while i < n {
        s.wm[2usize + i + i * n] = s.wm[2usize + i + i * n] + 1.0f64
        i += 1usize
    }
    let info = ls_dgefa(s.wm[2usize..2usize + n * n], n, s.ipvt)
    if info != 0usize { s.ierpj = 1i64 }
}

fn ls_pascal(s: *Lsoda, sign: f64) {
    let n = s.n
    var i1 = s.nqnyh + 1usize
    var jb = 1usize
    while jb <= s.nq {
        i1 -= n
        var i = i1
        while i <= s.nqnyh {
            s.yh[i - 1usize] = s.yh[i - 1usize] + sign * s.yh[i - 1usize + n]
            i += 1usize
        }
        jb += 1usize
    }
}

// One step of DSTODA (the GOTO web as a label loop); `y` is the work vector.
fn ls_stoda[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Lsoda, y: []f64) {
    let n = s.n
    var iredo = 0usize
    var rh = 1.0f64
    s.kflag = 0i64
    let told = s.tn
    var ncf = 0usize
    s.ierpj = 0i64
    s.iersl = 0i64
    s.jcur = 0usize
    s.icf = 0i64
    var delp = 0.0f64
    var iret = 0usize
    var m = 0usize
    var rate = 0.0f64
    var del = 0.0f64
    var dsm = 0.0f64
    var pnorm = 0.0f64
    var pdh = 0.0f64
    var rhup = 0.0f64
    var rhsm = 0.0f64
    var rhdn = 0.0f64
    var rh1 = 0.0f64
    var rh2 = 0.0f64
    var nqm2 = 0usize
    var newq = 0usize
    var lbl = 0usize
    var i = 0usize
    var j = 0usize
    if s.jstart > 0i64 {
        lbl = 200usize
    } else {
        if s.jstart == 0i64 - 1i64 {
            lbl = 100usize
        } else {
            if s.jstart == 0i64 - 2i64 {
                lbl = 160usize
            } else {
                s.lmax = s.maxord + 1usize
                s.nq = 1usize
                s.l = 2usize
                s.ialth = 2usize
                s.rmax = 10000.0f64
                s.rc = 0.0f64
                s.el0 = 1.0f64
                s.crate = 0.7f64
                s.hold = s.h
                s.nslp = 0usize
                s.ipup = s.miter
                iret = 3usize
                s.icount = 20i64
                s.irflag = 0usize
                s.pdest = 0.0f64
                s.pdlast = 0.0f64
                s.ratio = 5.0f64
                ls_dcfode(2usize, s.elco, s.tesco)
                i = 1usize
                while i <= 5usize {
                    s.cm2[i - 1usize] = ls_tesco(s, 2usize, i) * ls_elco(s, i + 1usize, i)
                    i += 1usize
                }
                ls_dcfode(1usize, s.elco, s.tesco)
                i = 1usize
                while i <= 12usize {
                    s.cm1[i - 1usize] = ls_tesco(s, 2usize, i) * ls_elco(s, i + 1usize, i)
                    i += 1usize
                }
                lbl = 150usize
            }
        }
    }
    while true {
        if lbl == 100usize {
            s.ipup = s.miter
            s.lmax = s.maxord + 1usize
            if s.ialth == 1usize { s.ialth = 2usize }
            if s.meth == s.mused {
                lbl = 160usize
            } else {
                ls_dcfode(s.meth, s.elco, s.tesco)
                s.ialth = s.l
                iret = 1usize
                lbl = 150usize
            }
        }
        if lbl == 150usize {
            i = 1usize
            while i <= s.l {
                s.el[i - 1usize] = ls_elco(s, i, s.nq)
                i += 1usize
            }
            s.nqnyh = s.nq * n
            s.rc = s.rc * s.el[0usize] / s.el0
            s.el0 = s.el[0usize]
            s.conit = 0.5f64 / f64(s.nq + 2usize)
            if iret == 1usize { lbl = 160usize }
            if iret == 2usize { lbl = 170usize }
            if iret == 3usize { lbl = 200usize }
        }
        if lbl == 160usize {
            if s.h == s.hold {
                lbl = 200usize
            } else {
                rh = s.h / s.hold
                s.h = s.hold
                iredo = 3usize
                lbl = 175usize
            }
        }
        if lbl == 170usize {
            rh = rk_fmax(rh, s.hmin / math.abs[f64](s.h))
            lbl = 175usize
        }
        if lbl == 175usize {
            rh = rk_fmin(rh, s.rmax)
            rh = rh / rk_fmax(1.0f64, math.abs[f64](s.h) * s.hmxi * rh)
            if s.meth != 2usize {
                s.irflag = 0usize
                pdh = rk_fmax(math.abs[f64](s.h) * s.pdlast, 0.000001f64)
                if !(rh * pdh * 1.00001f64 < s.sm1[s.nq - 1usize]) {
                    rh = s.sm1[s.nq - 1usize] / pdh
                    s.irflag = 1usize
                }
            }
            var r = 1.0f64
            j = 2usize
            while j <= s.l {
                r = r * rh
                i = 0usize
                while i < n {
                    s.yh[(j - 1usize) * n + i] = s.yh[(j - 1usize) * n + i] * r
                    i += 1usize
                }
                j += 1usize
            }
            s.h = s.h * rh
            s.rc = s.rc * rh
            s.ialth = s.l
            if iredo == 0usize {
                lbl = 690usize
            } else {
                lbl = 200usize
            }
        }
        if lbl == 200usize {
            if math.abs[f64](s.rc - 1.0f64) > s.ccmax { s.ipup = s.miter }
            if s.nst >= s.nslp + s.msbp { s.ipup = s.miter }
            s.tn = s.tn + s.h
            ls_pascal(s, 1.0f64)
            pnorm = ls_dmnorm(n, s.yh, s.ewt)
            lbl = 220usize
        }
        if lbl == 220usize {
            m = 0usize
            rate = 0.0f64
            del = 0.0f64
            i = 0usize
            while i < n {
                y[i] = s.yh[i]
                i += 1usize
            }
            f(ctx, s.tn, y, s.savf)
            s.nfe += 1usize
            lbl = 250usize
            if s.ipup > 0usize {
                ls_prja[Ctx](ctx, f, s, y)
                s.ipup = 0usize
                s.rc = 1.0f64
                s.nslp = s.nst
                s.crate = 0.7f64
                if s.ierpj != 0i64 { lbl = 430usize }
            }
        }
        if lbl == 250usize {
            i = 0usize
            while i < n {
                s.acor[i] = 0.0f64
                i += 1usize
            }
            lbl = 270usize
        }
        if lbl == 270usize {
            lbl = 400usize
            if s.miter != 0usize {
                i = 0usize
                while i < n {
                    y[i] = s.h * s.savf[i] - (s.yh[n + i] + s.acor[i])
                    i += 1usize
                }
                ls_dgesl(s.wm[2usize..2usize + n * n], n, s.ipvt, y)
                del = ls_dmnorm(n, y, s.ewt)
                i = 0usize
                while i < n {
                    s.acor[i] = s.acor[i] + y[i]
                    y[i] = s.yh[i] + s.el[0usize] * s.acor[i]
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < n {
                    s.savf[i] = s.h * s.savf[i] - s.yh[n + i]
                    y[i] = s.savf[i] - s.acor[i]
                    i += 1usize
                }
                del = ls_dmnorm(n, y, s.ewt)
                i = 0usize
                while i < n {
                    y[i] = s.yh[i] + s.el[0usize] * s.savf[i]
                    s.acor[i] = s.savf[i]
                    i += 1usize
                }
            }
        }
        if lbl == 400usize {
            if del <= 100.0f64 * pnorm * s.uround {
                lbl = 450usize
            } else {
                if m == 0usize && s.meth == 1usize {
                    lbl = 405usize
                } else {
                    if m != 0usize {
                        var rm = 1024.0f64
                        if del <= 1024.0f64 * delp { rm = del / delp }
                        rate = rk_fmax(rate, rm)
                        s.crate = rk_fmax(0.2f64 * s.crate, rm)
                    }
                    let dcon = del * rk_fmin(1.0f64, 1.5f64 * s.crate) / (ls_tesco(s, 2usize, s.nq) * s.conit)
                    if dcon > 1.0f64 {
                        lbl = 405usize
                    } else {
                        s.pdest = rk_fmax(s.pdest, rate / math.abs[f64](s.h * s.el[0usize]))
                        if s.pdest != 0.0f64 { s.pdlast = s.pdest }
                        lbl = 450usize
                    }
                }
            }
        }
        if lbl == 405usize {
            m += 1usize
            lbl = 270usize
            if m == s.maxcor { lbl = 410usize }
            if lbl == 270usize && m >= 2usize && del > 2.0f64 * delp { lbl = 410usize }
            if lbl == 270usize {
                delp = del
                f(ctx, s.tn, y, s.savf)
                s.nfe += 1usize
            }
        }
        if lbl == 410usize {
            if s.miter == 0usize || s.jcur == 1usize {
                lbl = 430usize
            } else {
                s.icf = 1i64
                s.ipup = s.miter
                lbl = 220usize
            }
        }
        if lbl == 430usize {
            s.icf = 2i64
            ncf += 1usize
            s.rmax = 2.0f64
            s.tn = told
            ls_pascal(s, 0.0f64 - 1.0f64)
            if s.ierpj < 0i64 || s.iersl < 0i64 {
                lbl = 680usize
            } else {
                if math.abs[f64](s.h) <= s.hmin * 1.00001f64 {
                    lbl = 670usize
                } else {
                    if ncf == s.mxncf {
                        lbl = 670usize
                    } else {
                        rh = 0.25f64
                        s.ipup = s.miter
                        iredo = 1usize
                        lbl = 170usize
                    }
                }
            }
        }
        if lbl == 450usize {
            s.jcur = 0usize
            if m == 0usize { dsm = del / ls_tesco(s, 2usize, s.nq) }
            if m > 0usize { dsm = ls_dmnorm(n, s.acor, s.ewt) / ls_tesco(s, 2usize, s.nq) }
            if dsm > 1.0f64 {
                lbl = 500usize
            } else {
                s.kflag = 0i64
                iredo = 0usize
                s.nst += 1usize
                s.hu = s.h
                s.nqu = s.nq
                s.mused = s.meth
                j = 1usize
                while j <= s.l {
                    i = 0usize
                    while i < n {
                        s.yh[(j - 1usize) * n + i] = s.yh[(j - 1usize) * n + i] + s.el[j - 1usize] * s.acor[i]
                        i += 1usize
                    }
                    j += 1usize
                }
                s.icount = s.icount - 1i64
                lbl = 488usize
                if s.icount < 0i64 {
                    if s.meth == 2usize {
                        lbl = 480usize
                    } else {
                        if s.nq > 5usize {
                            lbl = 488usize
                        } else {
                            if dsm > 100.0f64 * pnorm * s.uround && s.pdest != 0.0f64 {
                                lbl = 470usize
                            } else {
                                if s.irflag == 0usize {
                                    lbl = 488usize
                                } else {
                                    rh2 = 2.0f64
                                    nqm2 = s.nq
                                    if s.mxords < nqm2 { nqm2 = s.mxords }
                                    lbl = 478usize
                                }
                            }
                        }
                    }
                }
            }
        }
        if lbl == 470usize {
            let exsm = 1.0f64 / f64(s.l)
            rh1 = 1.0f64 / (1.2f64 * dd_pow(dsm, exsm) + 0.0000012f64)
            var rh1it = 2.0f64 * rh1
            pdh = s.pdlast * math.abs[f64](s.h)
            if pdh * rh1 > 0.00001f64 { rh1it = s.sm1[s.nq - 1usize] / pdh }
            rh1 = rk_fmin(rh1, rh1it)
            if s.nq <= s.mxords {
                let dm2 = dsm * (s.cm1[s.nq - 1usize] / s.cm2[s.nq - 1usize])
                rh2 = 1.0f64 / (1.2f64 * dd_pow(dm2, exsm) + 0.0000012f64)
                nqm2 = s.nq
            } else {
                nqm2 = s.mxords
                let lm2 = s.mxords + 1usize
                let exm2 = 1.0f64 / f64(lm2)
                let dm2 = ls_dmnorm(n, s.yh[lm2 * n..lm2 * n + n], s.ewt) / s.cm2[s.mxords - 1usize]
                rh2 = 1.0f64 / (1.2f64 * dd_pow(dm2, exm2) + 0.0000012f64)
            }
            if rh2 < s.ratio * rh1 {
                lbl = 488usize
            } else {
                lbl = 478usize
            }
        }
        if lbl == 478usize {
            rh = rh2
            s.icount = 20i64
            s.meth = 2usize
            s.miter = s.jtyp
            s.pdlast = 0.0f64
            s.nq = nqm2
            s.l = s.nq + 1usize
            lbl = 170usize
        }
        if lbl == 480usize {
            let exsm = 1.0f64 / f64(s.l)
            var nqm1 = s.nq
            var exm1 = exsm
            var dm1 = 0.0f64
            if s.mxordn >= s.nq {
                dm1 = dsm * (s.cm2[s.nq - 1usize] / s.cm1[s.nq - 1usize])
                rh1 = 1.0f64 / (1.2f64 * dd_pow(dm1, exsm) + 0.0000012f64)
            } else {
                nqm1 = s.mxordn
                let lm1 = s.mxordn + 1usize
                exm1 = 1.0f64 / f64(lm1)
                dm1 = ls_dmnorm(n, s.yh[lm1 * n..lm1 * n + n], s.ewt) / s.cm1[s.mxordn - 1usize]
                rh1 = 1.0f64 / (1.2f64 * dd_pow(dm1, exm1) + 0.0000012f64)
            }
            var rh1it = 2.0f64 * rh1
            pdh = s.pdnorm * math.abs[f64](s.h)
            if pdh * rh1 > 0.00001f64 { rh1it = s.sm1[nqm1 - 1usize] / pdh }
            rh1 = rk_fmin(rh1, rh1it)
            rh2 = 1.0f64 / (1.2f64 * dd_pow(dsm, exsm) + 0.0000012f64)
            lbl = 488usize
            if !(rh1 * s.ratio < 5.0f64 * rh2) {
                let alpha = rk_fmax(0.001f64, rh1)
                dm1 = dd_pow(alpha, exm1) * dm1
                if !(dm1 <= 1000.0f64 * s.uround * pnorm) {
                    rh = rh1
                    s.icount = 20i64
                    s.meth = 1usize
                    s.miter = 0usize
                    s.pdlast = 0.0f64
                    s.nq = nqm1
                    s.l = s.nq + 1usize
                    lbl = 170usize
                }
            }
        }
        if lbl == 488usize {
            s.ialth -= 1usize
            lbl = 700usize
            if s.ialth == 0usize {
                lbl = 520usize
            } else {
                if s.ialth <= 1usize && s.l != s.lmax {
                    i = 0usize
                    while i < n {
                        s.yh[(s.lmax - 1usize) * n + i] = s.acor[i]
                        i += 1usize
                    }
                }
            }
        }
        if lbl == 500usize {
            s.kflag = s.kflag - 1i64
            s.tn = told
            ls_pascal(s, 0.0f64 - 1.0f64)
            s.rmax = 2.0f64
            if math.abs[f64](s.h) <= s.hmin * 1.00001f64 {
                lbl = 660usize
            } else {
                if s.kflag <= 0i64 - 3i64 {
                    lbl = 640usize
                } else {
                    iredo = 2usize
                    rhup = 0.0f64
                    lbl = 540usize
                }
            }
        }
        if lbl == 520usize {
            rhup = 0.0f64
            if s.l != s.lmax {
                i = 0usize
                while i < n {
                    s.savf[i] = s.acor[i] - s.yh[(s.lmax - 1usize) * n + i]
                    i += 1usize
                }
                let dup = ls_dmnorm(n, s.savf, s.ewt) / ls_tesco(s, 3usize, s.nq)
                let exup = 1.0f64 / f64(s.l + 1usize)
                rhup = 1.0f64 / (1.4f64 * dd_pow(dup, exup) + 0.0000014f64)
            }
            lbl = 540usize
        }
        if lbl == 540usize {
            let exsm = 1.0f64 / f64(s.l)
            rhsm = 1.0f64 / (1.2f64 * dd_pow(dsm, exsm) + 0.0000012f64)
            rhdn = 0.0f64
            if s.nq != 1usize {
                let ddn = ls_dmnorm(n, s.yh[(s.l - 1usize) * n..(s.l - 1usize) * n + n], s.ewt) / ls_tesco(s, 1usize, s.nq)
                let exdn = 1.0f64 / f64(s.nq)
                rhdn = 1.0f64 / (1.3f64 * dd_pow(ddn, exdn) + 0.0000013f64)
            }
            if s.meth != 2usize {
                pdh = rk_fmax(math.abs[f64](s.h) * s.pdlast, 0.000001f64)
                if s.l < s.lmax { rhup = rk_fmin(rhup, s.sm1[s.l - 1usize] / pdh) }
                rhsm = rk_fmin(rhsm, s.sm1[s.nq - 1usize] / pdh)
                if s.nq > 1usize { rhdn = rk_fmin(rhdn, s.sm1[s.nq - 2usize] / pdh) }
                s.pdest = 0.0f64
            }
            lbl = 560usize
        }
        if lbl == 560usize {
            if rhsm >= rhup {
                if rhsm < rhdn {
                    lbl = 580usize
                } else {
                    newq = s.nq
                    rh = rhsm
                    lbl = 620usize
                }
            } else {
                if rhup > rhdn {
                    lbl = 590usize
                } else {
                    lbl = 580usize
                }
            }
        }
        if lbl == 580usize {
            newq = s.nq - 1usize
            rh = rhdn
            if s.kflag < 0i64 && rh > 1.0f64 { rh = 1.0f64 }
            lbl = 620usize
        }
        if lbl == 590usize {
            newq = s.l
            rh = rhup
            if rh < 1.1f64 {
                lbl = 610usize
            } else {
                let r = s.el[s.l - 1usize] / f64(s.l)
                i = 0usize
                while i < n {
                    s.yh[newq * n + i] = s.acor[i] * r
                    i += 1usize
                }
                lbl = 630usize
            }
        }
        if lbl == 610usize {
            s.ialth = 3usize
            lbl = 700usize
        }
        if lbl == 620usize {
            lbl = 625usize
            if s.meth != 2usize {
                if !(rh * pdh * 1.00001f64 >= s.sm1[newq - 1usize]) { lbl = 622usize }
            } else {
                lbl = 622usize
            }
            if lbl == 622usize {
                if s.kflag == 0i64 && rh < 1.1f64 {
                    lbl = 610usize
                } else {
                    lbl = 625usize
                }
            }
        }
        if lbl == 625usize {
            if s.kflag <= 0i64 - 2i64 { rh = rk_fmin(rh, 0.2f64) }
            if newq == s.nq {
                lbl = 170usize
            } else {
                lbl = 630usize
            }
        }
        if lbl == 630usize {
            s.nq = newq
            s.l = s.nq + 1usize
            iret = 2usize
            lbl = 150usize
        }
        if lbl == 640usize {
            if s.kflag == 0i64 - 10i64 {
                lbl = 660usize
            } else {
                rh = 0.1f64
                rh = rk_fmax(s.hmin / math.abs[f64](s.h), rh)
                s.h = s.h * rh
                i = 0usize
                while i < n {
                    y[i] = s.yh[i]
                    i += 1usize
                }
                f(ctx, s.tn, y, s.savf)
                s.nfe += 1usize
                i = 0usize
                while i < n {
                    s.yh[n + i] = s.h * s.savf[i]
                    i += 1usize
                }
                s.ipup = s.miter
                s.ialth = 5usize
                if s.nq == 1usize {
                    lbl = 200usize
                } else {
                    s.nq = 1usize
                    s.l = 2usize
                    iret = 3usize
                    lbl = 150usize
                }
            }
        }
        if lbl == 660usize {
            s.kflag = 0i64 - 1i64
            lbl = 720usize
        }
        if lbl == 670usize {
            s.kflag = 0i64 - 2i64
            lbl = 720usize
        }
        if lbl == 680usize {
            s.kflag = 0i64 - 3i64
            lbl = 720usize
        }
        if lbl == 690usize {
            s.rmax = 10.0f64
            lbl = 700usize
        }
        if lbl == 700usize {
            let r = 1.0f64 / ls_tesco(s, 2usize, s.nqu)
            i = 0usize
            while i < n {
                s.acor[i] = s.acor[i] * r
                i += 1usize
            }
            lbl = 720usize
        }
        if lbl == 720usize {
            s.hold = s.h
            s.jstart = 1i64
            break
        }
    }
}

fn ls_dvnorm(n: usize, v: []const f64, w: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < n {
        let p = v[i] * w[i]
        sum = sum + p * p
        i += 1usize
    }
    ret math.sqrt[f64](sum / f64(n))
}

// DPREPJ with miter = 2: finite-difference Jacobian with the root-mean-square norm.
fn ls_prje[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Lsoda, y: []f64) {
    let n = s.n
    s.nje += 1usize
    s.ierpj = 0i64
    s.jcur = 1usize
    let hl0 = s.h * s.el0
    var fac = ls_dvnorm(n, s.savf, s.ewt)
    var r0 = 1000.0f64 * math.abs[f64](s.h) * s.uround * f64(n) * fac
    if r0 == 0.0f64 { r0 = 1.0f64 }
    let srur = s.wm[0usize]
    var j1 = 2usize
    var j = 0usize
    while j < n {
        let yj = y[j]
        let r = rk_fmax(srur * math.abs[f64](yj), r0 / s.ewt[j])
        y[j] = y[j] + r
        fac = (0.0f64 - hl0) / r
        f(ctx, s.tn, y, s.ftem)
        var i = 0usize
        while i < n {
            s.wm[i + j1] = (s.ftem[i] - s.savf[i]) * fac
            i += 1usize
        }
        y[j] = yj
        j1 += n
        j += 1usize
    }
    s.nfe += n
    var i = 0usize
    while i < n {
        s.wm[2usize + i + i * n] = s.wm[2usize + i + i * n] + 1.0f64
        i += 1usize
    }
    let info = ls_dgefa(s.wm[2usize..2usize + n * n], n, s.ipvt)
    if info != 0usize { s.ierpj = 1i64 }
}

// One step of DSTODE (DLSODE's stepper: fixed method, no switching).
fn ls_stode[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Lsoda, y: []f64) {
    let n = s.n
    var iredo = 0usize
    var rh = 0.0f64
    s.kflag = 0i64
    let told = s.tn
    var ncf = 0usize
    s.ierpj = 0i64
    s.iersl = 0i64
    s.jcur = 0usize
    s.icf = 0i64
    var delp = 0.0f64
    var iret = 0usize
    var m = 0usize
    var del = 0.0f64
    var dsm = 0.0f64
    var rhup = 0.0f64
    var rhsm = 0.0f64
    var rhdn = 0.0f64
    var newq = 0usize
    var lbl = 0usize
    var i = 0usize
    var j = 0usize
    if s.jstart > 0i64 {
        lbl = 200usize
    } else {
        if s.jstart == 0i64 - 1i64 {
            lbl = 100usize
        } else {
            if s.jstart == 0i64 - 2i64 {
                lbl = 160usize
            } else {
                s.lmax = s.maxord + 1usize
                s.nq = 1usize
                s.l = 2usize
                s.ialth = 2usize
                s.rmax = 10000.0f64
                s.rc = 0.0f64
                s.el0 = 1.0f64
                s.crate = 0.7f64
                s.hold = s.h
                s.nslp = 0usize
                s.ipup = s.miter
                iret = 3usize
                lbl = 140usize
            }
        }
    }
    while true {
        if lbl == 100usize {
            s.ipup = s.miter
            s.lmax = s.maxord + 1usize
            if s.ialth == 1usize { s.ialth = 2usize }
            lbl = 160usize
            if s.nq > s.maxord { lbl = 120usize }
        }
        if lbl == 120usize {
            s.nq = s.maxord
            s.l = s.lmax
            i = 1usize
            while i <= s.l {
                s.el[i - 1usize] = ls_elco(s, i, s.nq)
                i += 1usize
            }
            s.nqnyh = s.nq * n
            s.rc = s.rc * s.el[0usize] / s.el0
            s.el0 = s.el[0usize]
            s.conit = 0.5f64 / f64(s.nq + 2usize)
            let ddn = ls_dvnorm(n, s.savf, s.ewt) / ls_tesco(s, 1usize, s.l)
            let exdn = 1.0f64 / f64(s.l)
            rh = rk_fmin(1.0f64 / (1.3f64 * dd_pow(ddn, exdn) + 0.0000013f64), 1.0f64)
            iredo = 3usize
            lbl = 170usize
            if s.h != s.hold {
                rh = rk_fmin(rh, math.abs[f64](s.h / s.hold))
                s.h = s.hold
                lbl = 175usize
            }
        }
        if lbl == 140usize {
            ls_dcfode(s.meth, s.elco, s.tesco)
            lbl = 150usize
        }
        if lbl == 150usize {
            i = 1usize
            while i <= s.l {
                s.el[i - 1usize] = ls_elco(s, i, s.nq)
                i += 1usize
            }
            s.nqnyh = s.nq * n
            s.rc = s.rc * s.el[0usize] / s.el0
            s.el0 = s.el[0usize]
            s.conit = 0.5f64 / f64(s.nq + 2usize)
            if iret == 1usize { lbl = 160usize }
            if iret == 2usize { lbl = 170usize }
            if iret == 3usize { lbl = 200usize }
        }
        if lbl == 160usize {
            if s.h == s.hold {
                lbl = 200usize
            } else {
                rh = s.h / s.hold
                s.h = s.hold
                iredo = 3usize
                lbl = 175usize
            }
        }
        if lbl == 170usize {
            rh = rk_fmax(rh, s.hmin / math.abs[f64](s.h))
            lbl = 175usize
        }
        if lbl == 175usize {
            rh = rk_fmin(rh, s.rmax)
            rh = rh / rk_fmax(1.0f64, math.abs[f64](s.h) * s.hmxi * rh)
            var r = 1.0f64
            j = 2usize
            while j <= s.l {
                r = r * rh
                i = 0usize
                while i < n {
                    s.yh[(j - 1usize) * n + i] = s.yh[(j - 1usize) * n + i] * r
                    i += 1usize
                }
                j += 1usize
            }
            s.h = s.h * rh
            s.rc = s.rc * rh
            s.ialth = s.l
            lbl = 200usize
            if iredo == 0usize { lbl = 690usize }
        }
        if lbl == 200usize {
            if math.abs[f64](s.rc - 1.0f64) > s.ccmax { s.ipup = s.miter }
            if s.nst >= s.nslp + s.msbp { s.ipup = s.miter }
            s.tn = s.tn + s.h
            ls_pascal(s, 1.0f64)
            lbl = 220usize
        }
        if lbl == 220usize {
            m = 0usize
            i = 0usize
            while i < n {
                y[i] = s.yh[i]
                i += 1usize
            }
            f(ctx, s.tn, y, s.savf)
            s.nfe += 1usize
            lbl = 270usize
            if s.ipup > 0usize {
                ls_prje[Ctx](ctx, f, s, y)
                s.ipup = 0usize
                s.rc = 1.0f64
                s.nslp = s.nst
                s.crate = 0.7f64
                if s.ierpj != 0i64 { lbl = 430usize }
            }
            if lbl == 270usize {
                i = 0usize
                while i < n {
                    s.acor[i] = 0.0f64
                    i += 1usize
                }
            }
        }
        if lbl == 270usize {
            lbl = 400usize
            if s.miter == 0usize {
                i = 0usize
                while i < n {
                    s.savf[i] = s.h * s.savf[i] - s.yh[n + i]
                    y[i] = s.savf[i] - s.acor[i]
                    i += 1usize
                }
                del = ls_dvnorm(n, y, s.ewt)
                i = 0usize
                while i < n {
                    y[i] = s.yh[i] + s.el[0usize] * s.savf[i]
                    s.acor[i] = s.savf[i]
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < n {
                    y[i] = s.h * s.savf[i] - (s.yh[n + i] + s.acor[i])
                    i += 1usize
                }
                ls_dgesl(s.wm[2usize..2usize + n * n], n, s.ipvt, y)
                del = ls_dvnorm(n, y, s.ewt)
                i = 0usize
                while i < n {
                    s.acor[i] = s.acor[i] + y[i]
                    y[i] = s.yh[i] + s.el[0usize] * s.acor[i]
                    i += 1usize
                }
            }
        }
        if lbl == 400usize {
            if m != 0usize { s.crate = rk_fmax(0.2f64 * s.crate, del / delp) }
            let dcon = del * rk_fmin(1.0f64, 1.5f64 * s.crate) / (ls_tesco(s, 2usize, s.nq) * s.conit)
            if dcon <= 1.0f64 {
                lbl = 450usize
            } else {
                m += 1usize
                lbl = 270usize
                if m == s.maxcor { lbl = 410usize }
                if lbl == 270usize && m >= 2usize && del > 2.0f64 * delp { lbl = 410usize }
                if lbl == 270usize {
                    delp = del
                    f(ctx, s.tn, y, s.savf)
                    s.nfe += 1usize
                }
            }
        }
        if lbl == 410usize {
            if s.miter == 0usize || s.jcur == 1usize {
                lbl = 430usize
            } else {
                s.icf = 1i64
                s.ipup = s.miter
                lbl = 220usize
            }
        }
        if lbl == 430usize {
            s.icf = 2i64
            ncf += 1usize
            s.rmax = 2.0f64
            s.tn = told
            ls_pascal(s, 0.0f64 - 1.0f64)
            if s.ierpj < 0i64 || s.iersl < 0i64 {
                lbl = 680usize
            } else {
                if math.abs[f64](s.h) <= s.hmin * 1.00001f64 {
                    lbl = 670usize
                } else {
                    if ncf == s.mxncf {
                        lbl = 670usize
                    } else {
                        rh = 0.25f64
                        s.ipup = s.miter
                        iredo = 1usize
                        lbl = 170usize
                    }
                }
            }
        }
        if lbl == 450usize {
            s.jcur = 0usize
            if m == 0usize { dsm = del / ls_tesco(s, 2usize, s.nq) }
            if m > 0usize { dsm = ls_dvnorm(n, s.acor, s.ewt) / ls_tesco(s, 2usize, s.nq) }
            if dsm > 1.0f64 {
                lbl = 500usize
            } else {
                s.kflag = 0i64
                iredo = 0usize
                s.nst += 1usize
                s.hu = s.h
                s.nqu = s.nq
                j = 1usize
                while j <= s.l {
                    i = 0usize
                    while i < n {
                        s.yh[(j - 1usize) * n + i] = s.yh[(j - 1usize) * n + i] + s.el[j - 1usize] * s.acor[i]
                        i += 1usize
                    }
                    j += 1usize
                }
                s.ialth = s.ialth - 1usize
                lbl = 700usize
                if s.ialth == 0usize { lbl = 520usize }
                if lbl == 700usize && s.ialth <= 1usize && s.l != s.lmax {
                    i = 0usize
                    while i < n {
                        s.yh[(s.lmax - 1usize) * n + i] = s.acor[i]
                        i += 1usize
                    }
                }
            }
        }
        if lbl == 500usize {
            s.kflag = s.kflag - 1i64
            s.tn = told
            ls_pascal(s, 0.0f64 - 1.0f64)
            s.rmax = 2.0f64
            if math.abs[f64](s.h) <= s.hmin * 1.00001f64 {
                lbl = 660usize
            } else {
                if s.kflag <= 0i64 - 3i64 {
                    lbl = 640usize
                } else {
                    iredo = 2usize
                    rhup = 0.0f64
                    lbl = 540usize
                }
            }
        }
        if lbl == 520usize {
            rhup = 0.0f64
            if s.l != s.lmax {
                i = 0usize
                while i < n {
                    s.savf[i] = s.acor[i] - s.yh[(s.lmax - 1usize) * n + i]
                    i += 1usize
                }
                let dup = ls_dvnorm(n, s.savf, s.ewt) / ls_tesco(s, 3usize, s.nq)
                let exup = 1.0f64 / f64(s.l + 1usize)
                rhup = 1.0f64 / (1.4f64 * dd_pow(dup, exup) + 0.0000014f64)
            }
            lbl = 540usize
        }
        if lbl == 540usize {
            let exsm = 1.0f64 / f64(s.l)
            rhsm = 1.0f64 / (1.2f64 * dd_pow(dsm, exsm) + 0.0000012f64)
            rhdn = 0.0f64
            if s.nq != 1usize {
                let ddn = ls_dvnorm(n, s.yh[(s.l - 1usize) * n..(s.l - 1usize) * n + n], s.ewt) / ls_tesco(s, 1usize, s.nq)
                let exdn = 1.0f64 / f64(s.nq)
                rhdn = 1.0f64 / (1.3f64 * dd_pow(ddn, exdn) + 0.0000013f64)
            }
            lbl = 560usize
        }
        if lbl == 560usize {
            // 580 lower the order, 590 raise it, 620 keep it
            if rhsm >= rhup {
                if rhsm < rhdn {
                    lbl = 580usize
                } else {
                    newq = s.nq
                    rh = rhsm
                    lbl = 620usize
                }
            } else {
                if rhup > rhdn {
                    lbl = 590usize
                } else {
                    lbl = 580usize
                }
            }
        }
        if lbl == 580usize {
            newq = s.nq - 1usize
            rh = rhdn
            if s.kflag < 0i64 && rh > 1.0f64 { rh = 1.0f64 }
            lbl = 620usize
        }
        if lbl == 590usize {
            newq = s.l
            rh = rhup
            if rh < 1.1f64 {
                lbl = 610usize
            } else {
                let r = s.el[s.l - 1usize] / f64(s.l)
                i = 0usize
                while i < n {
                    s.yh[newq * n + i] = s.acor[i] * r
                    i += 1usize
                }
                lbl = 630usize
            }
        }
        if lbl == 610usize {
            s.ialth = 3usize
            lbl = 700usize
        }
        if lbl == 620usize {
            if s.kflag == 0i64 && rh < 1.1f64 {
                s.ialth = 3usize
                lbl = 700usize
            } else {
                if s.kflag <= 0i64 - 2i64 { rh = rk_fmin(rh, 0.2f64) }
                if newq == s.nq {
                    lbl = 170usize
                } else {
                    lbl = 630usize
                }
            }
        }
        if lbl == 630usize {
            s.nq = newq
            s.l = s.nq + 1usize
            iret = 2usize
            lbl = 150usize
        }
        if lbl == 640usize {
            if s.kflag == 0i64 - 10i64 {
                lbl = 660usize
            } else {
                rh = rk_fmax(s.hmin / math.abs[f64](s.h), 0.1f64)
                s.h = s.h * rh
                i = 0usize
                while i < n {
                    y[i] = s.yh[i]
                    i += 1usize
                }
                f(ctx, s.tn, y, s.savf)
                s.nfe += 1usize
                i = 0usize
                while i < n {
                    s.yh[n + i] = s.h * s.savf[i]
                    i += 1usize
                }
                s.ipup = s.miter
                s.ialth = 5usize
                if s.nq == 1usize {
                    lbl = 200usize
                } else {
                    s.nq = 1usize
                    s.l = 2usize
                    iret = 3usize
                    lbl = 150usize
                }
            }
        }
        if lbl == 660usize {
            s.kflag = 0i64 - 1i64
            s.hold = s.h
            s.jstart = 1i64
            break
        }
        if lbl == 670usize {
            s.kflag = 0i64 - 2i64
            s.hold = s.h
            s.jstart = 1i64
            break
        }
        if lbl == 680usize {
            s.kflag = 0i64 - 3i64
            s.hold = s.h
            s.jstart = 1i64
            break
        }
        if lbl == 690usize {
            s.rmax = 10.0f64
            lbl = 700usize
        }
        if lbl == 700usize {
            let r = 1.0f64 / ls_tesco(s, 2usize, s.nqu)
            i = 0usize
            while i < n {
                s.acor[i] = s.acor[i] * r
                i += 1usize
            }
            s.hold = s.h
            s.jstart = 1i64
            break
        }
    }
}

// ---- DLSODAR root finding: DRCHEK and DROOTS. g(ctx, t, y, out) fills ng values.

fn ls_anyzero(s: *Lsoda, v: []const f64) -> bool {
    var i = 0usize
    while i < s.ngc {
        if v[i] == 0.0f64 { ret true }
        i += 1usize
    }
    ret false
}

fn ls_sgn1(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

// DROOTS: x0 = s.t0, x1 = s.t1; the answer abscissa goes to s.xroot; returns jflag.
fn ls_droots(s: *Lsoda, hming: f64, jflag_in: i64) -> i64 {
    let ng = s.ngc
    var xroot = false
    var nxlast = 0usize
    var i = 0usize
    var sgnchg = false
    var zroot = false
    var tmax = 0.0f64
    if jflag_in != 1i64 {
        s.imax = 0usize
        tmax = 0.0f64
        zroot = false
        i = 0usize
        while i < ng {
            if s.g1[i] > 0.0f64 || s.g1[i] < 0.0f64 {
                if ls_sgn1(s.g0[i]) != ls_sgn1(s.g1[i]) {
                    let t2 = math.abs[f64](s.g1[i] / (s.g1[i] - s.g0[i]))
                    if t2 > tmax {
                        tmax = t2
                        s.imax = i + 1usize
                    }
                }
            } else {
                zroot = true
            }
            i += 1usize
        }
        if s.imax == 0usize {
            s.xroot = s.t1
            i = 0usize
            while i < ng {
                s.gx[i] = s.g1[i]
                i += 1usize
            }
            if !zroot { ret 4i64 }
            i = 0usize
            while i < ng {
                s.jroot[i] = 0usize
                if math.abs[f64](s.g1[i]) <= 0.0f64 { s.jroot[i] = 1usize }
                i += 1usize
            }
            ret 3i64
        }
        xroot = false
        nxlast = 0usize
        s.last = 1usize
    } else {
        let imxold = s.imax
        s.imax = 0usize
        tmax = 0.0f64
        zroot = false
        i = 0usize
        while i < ng {
            if s.gx[i] > 0.0f64 || s.gx[i] < 0.0f64 {
                if ls_sgn1(s.g0[i]) != ls_sgn1(s.gx[i]) {
                    let t2 = math.abs[f64](s.gx[i] / (s.gx[i] - s.g0[i]))
                    if t2 > tmax {
                        tmax = t2
                        s.imax = i + 1usize
                    }
                }
            } else {
                zroot = true
            }
            i += 1usize
        }
        sgnchg = s.imax > 0usize
        if !sgnchg { s.imax = imxold }
        nxlast = s.last
        if sgnchg {
            s.t1 = s.x2
            i = 0usize
            while i < ng {
                s.g1[i] = s.gx[i]
                i += 1usize
            }
            s.last = 1usize
            xroot = false
        } else {
            if zroot {
                s.t1 = s.x2
                i = 0usize
                while i < ng {
                    s.g1[i] = s.gx[i]
                    i += 1usize
                }
                xroot = true
            } else {
                i = 0usize
                while i < ng {
                    s.g0[i] = s.gx[i]
                    i += 1usize
                }
                s.t0 = s.x2
                s.last = 0usize
                xroot = false
            }
        }
        if math.abs[f64](s.t1 - s.t0) <= hming { xroot = true }
    }
    if xroot {
        s.xroot = s.t1
        i = 0usize
        while i < ng {
            s.gx[i] = s.g1[i]
            s.jroot[i] = 0usize
            if math.abs[f64](s.g1[i]) > 0.0f64 {
                if ls_sgn1(s.g0[i]) != ls_sgn1(s.g1[i]) { s.jroot[i] = 1usize }
            } else {
                s.jroot[i] = 1usize
            }
            i += 1usize
        }
        ret 2i64
    }
    if nxlast == s.last {
        if s.last == 0usize { s.alpha = 2.0f64 * s.alpha } else { s.alpha = 0.5f64 * s.alpha }
    } else {
        s.alpha = 1.0f64
    }
    let im = s.imax - 1usize
    s.x2 = s.t1 - (s.t1 - s.t0) * s.g1[im] / (s.g1[im] - s.alpha * s.g0[im])
    if math.abs[f64](s.x2 - s.t0) < 0.5f64 * hming {
        let fracint = math.abs[f64](s.t1 - s.t0) / hming
        var fracsub = 0.1f64
        if fracint <= 5.0f64 { fracsub = 0.5f64 / fracint }
        s.x2 = s.t0 + fracsub * (s.t1 - s.t0)
    }
    if math.abs[f64](s.t1 - s.x2) < 0.5f64 * hming {
        let fracint = math.abs[f64](s.t1 - s.t0) / hming
        var fracsub = 0.1f64
        if fracint <= 5.0f64 { fracsub = 0.5f64 / fracint }
        s.x2 = s.t1 - fracsub * (s.t1 - s.t0)
    }
    s.xroot = s.x2
    ret 1i64
}

// DRCHEK: job 1 at the start, 2 before stepping, 3 after a step. Returns irt: 1 root found
// (s.jroot says which), -1 root at the start.
fn ls_drchek[Ctx: type](ctx: *Ctx, g: fn(*Ctx, f64, []const f64, []f64), s: *Lsoda, job: usize, y: []f64) -> i64 {
    let n = s.n
    var i = 0usize
    while i < s.ngc {
        s.jroot[i] = 0usize
        i += 1usize
    }
    let hming = (math.abs[f64](s.tn) + math.abs[f64](s.h)) * s.uround * 100.0f64
    if job == 1usize {
        s.t0 = s.tn
        g(ctx, s.t0, y, s.g0)
        s.nge = 1usize
        if !ls_anyzero(s, s.g0) { ret 0i64 }
        let temp2 = rk_fmax(hming / math.abs[f64](s.h), 0.1f64)
        s.t0 = s.t0 + temp2 * s.h
        i = 0usize
        while i < n {
            y[i] = y[i] + temp2 * s.yh[n + i]
            i += 1usize
        }
        g(ctx, s.t0, y, s.g0)
        s.nge += 1usize
        if !ls_anyzero(s, s.g0) { ret 0i64 }
        ret 0i64 - 1i64
    }
    if job == 2usize {
        if s.irfnd != 0usize {
            let _ = ls_intdy0(s, s.t0, y)
            g(ctx, s.t0, y, s.g0)
            s.nge += 1usize
            if ls_anyzero(s, s.g0) {
                let temp1 = ls_sign(hming, s.h)
                s.t0 = s.t0 + temp1
                if (s.t0 - s.tn) * s.h < 0.0f64 {
                    let _ = ls_intdy0(s, s.t0, y)
                } else {
                    let temp2 = temp1 / s.h
                    i = 0usize
                    while i < n {
                        y[i] = y[i] + temp2 * s.yh[n + i]
                        i += 1usize
                    }
                }
                g(ctx, s.t0, y, s.g0)
                s.nge += 1usize
                var zr = false
                i = 0usize
                while i < s.ngc {
                    if !(math.abs[f64](s.g0[i]) > 0.0f64) {
                        s.jroot[i] = 1usize
                        zr = true
                    }
                    i += 1usize
                }
                if zr { ret 1i64 }
            }
        }
        if s.tn == s.tlast { ret 0i64 }
    }
    var t1 = s.tn
    var viaintdy = false
    if !(s.itaskc == 2usize || s.itaskc == 3usize || s.itaskc == 5usize) {
        if (s.toutc - s.tn) * s.h < 0.0f64 {
            t1 = s.toutc
            if (t1 - s.t0) * s.h <= 0.0f64 { ret 0i64 }
            viaintdy = true
        }
    }
    s.t1 = t1
    if viaintdy {
        let _ = ls_intdy0(s, t1, y)
    } else {
        i = 0usize
        while i < n {
            y[i] = s.yh[i]
            i += 1usize
        }
    }
    g(ctx, s.t1, y, s.g1)
    s.nge += 1usize
    var jflag = 0i64
    while true {
        jflag = ls_droots(s, hming, jflag)
        if jflag > 1i64 { break }
        let _ = ls_intdy0(s, s.xroot, y)
        g(ctx, s.xroot, y, s.gx)
        s.nge += 1usize
    }
    s.t0 = s.xroot
    i = 0usize
    while i < s.ngc {
        s.g0[i] = s.gx[i]
        i += 1usize
    }
    if jflag == 4i64 { ret 0i64 }
    let _ = ls_intdy0(s, s.xroot, y)
    ret 1i64
}

fn ls_nrm(s: *Lsoda, n: usize, v: []const f64) -> f64 {
    if s.mode == 0usize { ret ls_dmnorm(n, v, s.ewt) }
    ret ls_dvnorm(n, v, s.ewt)
}

fn ls_dewset(s: *Lsoda) {
    var i = 0usize
    while i < s.n {
        s.ewt[i] = s.rtol * math.abs[f64](s.yh[i]) + s.atol
        i += 1usize
    }
}

// Inverts ewt in place; returns false when some weight is not positive.
fn ls_ewt_invert(s: *Lsoda) -> bool {
    var i = 0usize
    while i < s.n {
        if s.ewt[i] <= 0.0f64 { ret false }
        s.ewt[i] = 1.0f64 / s.ewt[i]
        i += 1usize
    }
    ret true
}

// DLSODA with itask = 1: integrate until the internal step passes `tout`, then interpolate
// into y. `first` starts the problem (istate 1) from y at tin. Returns 2 on success, DLSODA's
// negative istate otherwise: -1 too much work, -2 too much accuracy, -3 bad input, -4 error
// test failures, -5 convergence failures, -6 zero error weight.
fn ls_call[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Lsoda, y: []f64, tin: f64, tout: f64, first: bool, hini_in: f64, hmax: f64, hmin_in: f64, itask4: bool, tcrit: f64, ng: usize, g: fn(*Ctx, f64, []const f64, []f64)) -> i64 {
    let n = s.n
    var lbl = 200usize
    var i = 0usize
    var ihit = false
    var hini = hini_in
    s.ngc = ng
    s.itaskc = 1usize
    if itask4 { s.itaskc = 4usize }
    if s.one { s.itaskc = 5usize }
    if first {
        if tout == tin {
            s.tret = tin
            ret 2i64
        }
        s.hmxi = 0.0f64
        if hmax > 0.0f64 { s.hmxi = 1.0f64 / hmax }
        s.hmin = hmin_in
        s.uround = 2.220446049250313e-16f64
        s.tn = tin
        s.tsw = tin
        if s.mode == 0usize { s.maxord = s.mxordn }
        s.jstart = 0i64
        s.nst = 0usize
        s.nje = 0usize
        s.nslast = 0usize
        s.hu = 0.0f64
        s.nqu = 0usize
        s.mused = 0usize
        if s.mode == 0usize { s.miter = 0usize }
        s.ccmax = 0.3f64
        s.maxcor = 3usize
        s.msbp = 20usize
        s.mxncf = 10usize
        if s.mode == 0usize { s.meth = 1usize }
        if s.mode == 1usize && s.miter > 0usize { s.wm[0usize] = math.sqrt[f64](s.uround) }
        f(ctx, tin, y, s.yh[n..2usize * n])
        s.nfe = 1usize
        i = 0usize
        while i < n {
            s.yh[i] = y[i]
            i += 1usize
        }
        s.nq = 1usize
        s.h = 1.0f64
        ls_dewset(s)
        if !ls_ewt_invert(s) { ret 0i64 - 3i64 }
        if itask4 {
            if (tcrit - tout) * (tout - tin) < 0.0f64 { ret 0i64 - 3i64 }
            if hini != 0.0f64 && (tin + hini - tcrit) * hini > 0.0f64 { hini = tcrit - tin }
        }
        var h0 = hini
        let tdist = math.abs[f64](tout - tin)
        let w0 = rk_fmax(math.abs[f64](tin), math.abs[f64](tout))
        if h0 == 0.0f64 {
            if tdist < 2.0f64 * s.uround * w0 { ret 0i64 - 3i64 }
            var tol = s.rtol
            if !(tol > 0.0f64) {
                i = 0usize
                while i < n {
                    let ayi = math.abs[f64](y[i])
                    if ayi != 0.0f64 { tol = rk_fmax(tol, s.atol / ayi) }
                    i += 1usize
                }
            }
            tol = rk_fmax(tol, 100.0f64 * s.uround)
            tol = rk_fmin(tol, 0.001f64)
            var sum = ls_nrm(s, n, s.yh[n..2usize * n])
            sum = 1.0f64 / (tol * w0 * w0) + tol * (sum * sum)
            h0 = 1.0f64 / math.sqrt[f64](sum)
            h0 = rk_fmin(h0, tdist)
            h0 = ls_sign(h0, tout - tin)
        }
        let rh = math.abs[f64](h0) * s.hmxi
        if rh > 1.0f64 { h0 = h0 / rh }
        s.h = h0
        i = 0usize
        while i < n {
            s.yh[n + i] = h0 * s.yh[n + i]
            i += 1usize
        }
        s.irfnd = 0usize
        s.toutc = tout
        if s.ngc > 0usize {
            if ls_drchek[Ctx](ctx, g, s, 1usize, y) != 0i64 { ret 0i64 - 3i64 }
        }
        lbl = 270usize
    }
    var istate = 2i64
    while true {
        if lbl == 200usize {
            s.nslast = s.nst
            if s.ngc > 0usize {
                s.toutc = tout
                if ls_drchek[Ctx](ctx, g, s, 2usize, y) == 1i64 {
                    s.irfnd = 1usize
                    s.tret = s.t0
                    s.tlast = s.tret
                    ret 3i64
                }
            }
            s.irfnd = 0usize
            lbl = 210usize
            if itask4 { lbl = 230usize }
            if s.one {
                if (s.tn - tcrit) * s.h > 0.0f64 { ret 0i64 - 3i64 }
                lbl = 245usize
            }
        }
        if lbl == 210usize {
            if (s.tn - tout) * s.h < 0.0f64 {
                lbl = 250usize
            } else {
                if ls_intdy0(s, tout, y) != 0i64 { ret 0i64 - 3i64 }
                s.tret = tout
                break
            }
        }
        if lbl == 230usize {
            if (s.tn - tcrit) * s.h > 0.0f64 { ret 0i64 - 3i64 }
            if (tcrit - tout) * s.h < 0.0f64 { ret 0i64 - 3i64 }
            if (s.tn - tout) * s.h < 0.0f64 {
                lbl = 245usize
            } else {
                if ls_intdy0(s, tout, y) != 0i64 { ret 0i64 - 3i64 }
                s.tret = tout
                break
            }
        }
        if lbl == 245usize {
            let hmx = math.abs[f64](s.tn) + math.abs[f64](s.h)
            ihit = math.abs[f64](s.tn - tcrit) <= 100.0f64 * s.uround * hmx
            lbl = 250usize
            if ihit {
                lbl = 400usize
            } else {
                let tnext = s.tn + s.h * (1.0f64 + 4.0f64 * s.uround)
                if (tnext - tcrit) * s.h > 0.0f64 {
                    s.h = (tcrit - s.tn) * (1.0f64 - 4.0f64 * s.uround)
                    if s.mode == 1usize || s.jstart >= 0i64 { s.jstart = 0i64 - 2i64 }
                }
            }
        }
        if lbl == 250usize {
            if s.nst - s.nslast >= s.mxstep {
                istate = 0i64 - 1i64
                lbl = 580usize
            } else {
                ls_dewset(s)
                if !ls_ewt_invert(s) {
                    istate = 0i64 - 6i64
                    lbl = 580usize
                } else {
                    lbl = 270usize
                }
            }
        }
        if lbl == 270usize {
            s.tolsf = s.uround * ls_nrm(s, n, s.yh)
            if s.tolsf > 1.0f64 {
                s.tolsf = s.tolsf * 2.0f64
                if s.nst == 0usize { ret 0i64 - 3i64 }
                istate = 0i64 - 2i64
                lbl = 580usize
            } else {
                lbl = 290usize
            }
        }
        if lbl == 290usize {
            if s.mode == 0usize { ls_stoda[Ctx](ctx, f, s, s.ytmp) } else { ls_stode[Ctx](ctx, f, s, s.ytmp) }
            if s.kflag == 0i64 - 1i64 {
                istate = 0i64 - 4i64
                lbl = 580usize
            } else {
                if s.kflag != 0i64 {
                    istate = 0i64 - 5i64
                    lbl = 580usize
                } else {
                    if s.mode == 0usize && s.meth != s.mused {
                        s.tsw = s.tn
                        s.maxord = s.mxordn
                        if s.meth == 2usize { s.maxord = s.mxords }
                        if s.meth == 2usize { s.wm[0usize] = math.sqrt[f64](s.uround) }
                        s.jstart = 0i64 - 1i64
                    }
                    lbl = 310usize
                }
            }
        }
        if lbl == 310usize {
            lbl = 320usize
            if s.ngc > 0usize {
                if ls_drchek[Ctx](ctx, g, s, 3usize, y) == 1i64 {
                    s.irfnd = 1usize
                    s.tret = s.t0
                    s.tlast = s.tret
                    ret 3i64
                }
            }
        }
        if lbl == 320usize && s.one {
            let hmx = math.abs[f64](s.tn) + math.abs[f64](s.h)
            ihit = math.abs[f64](s.tn - tcrit) <= 100.0f64 * s.uround * hmx
            lbl = 400usize
        }
        if lbl == 320usize {
            if (s.tn - tout) * s.h < 0.0f64 {
                lbl = 250usize
                if itask4 { lbl = 245usize }
            } else {
                let _ = ls_intdy0(s, tout, y)
                s.tret = tout
                break
            }
        }
        if lbl == 400usize {
            i = 0usize
            while i < n {
                y[i] = s.yh[i]
                i += 1usize
            }
            s.tret = s.tn
            if ihit { s.tret = tcrit }
            break
        }
        if lbl == 580usize {
            i = 0usize
            while i < n {
                y[i] = s.yh[i]
                i += 1usize
            }
            s.tret = s.tn
            s.tlast = s.tret
            ret istate
        }
    }
    s.tlast = s.tret
    ret 2i64
}

// deSolve lsoda(y0, times, f): `out` is column-major times.len x (n + 1). rtol and atol are
// scalars (itol = 1); hmax <= 0 means the largest gap between output times (deSolve's
// default), hmin 0 and hini 0 are the usual defaults. maxsteps is per output interval.
// Returns Invalid when DLSODA reports an error.
// History of past states for delay equations (deSolve lags.c, interpol = 1 Hermite). `t`, `y`
// and `dy` are caller storage for `cap` entries (y and dy n wide each); no ring wrap, so a run
// that needs more than `cap` accepted steps stops with TooSmall. cap == 0 means no history.
type Hist = struct { n: usize, cnt: usize, cap: usize, t: []f64, y: []f64, dy: []f64 }

type RootRec = struct { ng: usize, rootevent: bool, termmask: usize, rows: usize, nroot: usize, stopped: bool, troot: [100]f64, ind: [100]usize, val: [300]f64, lag: bool, hist: *Hist }

fn hist_push[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), h: *Hist, t: f64, y: []const f64) -> bool {
    if h.cnt >= h.cap { ret false }
    let n = h.n
    f(ctx, t, y, h.dy[h.cnt * n..(h.cnt + 1usize) * n])
    var i = 0usize
    while i < n {
        h.y[h.cnt * n + i] = y[i]
        i += 1usize
    }
    h.t[h.cnt] = t
    h.cnt += 1usize
    ret true
}

fn hist_find(h: *Hist, t: f64) -> usize {
    let last = h.cnt - 1usize
    if t >= h.t[last] { ret last }
    var lo = 0usize
    var hi = last
    while true {
        let mid = (lo + hi) / 2usize
        if mid == lo { ret lo }
        if t >= h.t[mid] { lo = mid } else { hi = mid }
    }
    ret lo
}

// deSolve lagvalue(t, i + 1) (deriv false) or lagderiv (deriv true). NaN when t lies before the
// first stored time (deSolve stops with an error there).
fn hist_past(h: *Hist, t: f64, i: usize, deriv: bool) -> f64 {
    if h.cnt == 0usize || t < h.t[0usize] { ret math.nan64() }
    let n = h.n
    let j = hist_find(h, t)
    let last = h.cnt - 1usize
    let t0 = h.t[j]
    let y0 = h.y[j * n + i]
    let dy0 = h.dy[j * n + i]
    if j == last {
        if deriv { ret dy0 }
        if t == t0 { ret y0 }
        ret y0 + dy0 * (t - t0)
    }
    let t1 = h.t[j + 1usize]
    let y1 = h.y[(j + 1usize) * n + i]
    let dy1 = h.dy[(j + 1usize) * n + i]
    let tt0 = t - t0
    let tt1 = t - t1
    let tt12 = tt1 * tt1
    let tt02 = tt0 * tt0
    let hh = t1 - t0
    if hh == 0.0f64 {
        if deriv { ret dy0 }
        ret y0
    }
    if deriv { ret (dy0 * (tt12 + 2.0f64 * tt0 * tt1) + dy1 * (tt02 + 2.0f64 * tt0 * tt1) + (y0 * 2.0f64 * tt1 * (2.0f64 * tt0 + hh + tt1) - y1 * 2.0f64 * tt0 * (2.0f64 * tt1 - hh + tt0)) / hh) / (hh * hh) }
    ret (dy0 * tt0 * tt12 + dy1 * tt1 * tt02 + (y0 * (2.0f64 * tt0 + hh) * tt12 - y1 * (2.0f64 * tt1 - hh) * tt02) / hh) / (hh * hh)
}

fn ls_run[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, mxordn: usize, mxords: usize, mode: usize, meth0: usize, miter0: usize, maxord0: usize, evt: []const f64, evf: fn(*Ctx, f64, []f64), rr: *RootRec, g: fn(*Ctx, f64, []const f64, []f64), out: []f64) -> err {
    let n = y0.len
    let nt = times.len
    let ng = rr.ng
    if nt < 2usize || n == 0usize || out.len < nt * (n + 1usize) { ret Invalid }
    var s: Lsoda = zero
    let (blk, be) = mem.alloc[f64](a, 13usize * n + 3usize * n + n * n + 2usize + 13usize + 156usize + 36usize + 12usize + 5usize + 12usize + 2usize * n + 3usize * ng)
    if be != ok { ret be }
    let (piv, pe) = mem.alloc[usize](a, n + ng)
    if pe != ok { ret pe }
    var z = 0usize
    while z < blk.len {
        blk[z] = 0.0f64
        z += 1usize
    }
    var at = 0usize
    s.yh = blk[at..at + 13usize * n]
    at += 13usize * n
    s.ewt = blk[at..at + n]
    at += n
    s.savf = blk[at..at + n]
    at += n
    s.acor = blk[at..at + n]
    at += n
    s.wm = blk[at..at + n * n + 2usize]
    at += n * n + 2usize
    s.el = blk[at..at + 13usize]
    at += 13usize
    s.elco = blk[at..at + 156usize]
    at += 156usize
    s.tesco = blk[at..at + 36usize]
    at += 36usize
    s.cm1 = blk[at..at + 12usize]
    at += 12usize
    s.cm2 = blk[at..at + 5usize]
    at += 5usize
    s.sm1 = blk[at..at + 12usize]
    at += 12usize
    s.ytmp = blk[at..at + n]
    at += n
    s.ftem = blk[at..at + n]
    at += n
    s.g0 = blk[at..at + ng]
    at += ng
    s.g1 = blk[at..at + ng]
    at += ng
    s.gx = blk[at..at + ng]
    s.ipvt = piv[0usize..n]
    s.jroot = piv[n..n + ng]
    s.sm1[0usize] = 0.5f64
    s.sm1[1usize] = 0.575f64
    s.sm1[2usize] = 0.55f64
    s.sm1[3usize] = 0.45f64
    s.sm1[4usize] = 0.35f64
    s.sm1[5usize] = 0.25f64
    s.sm1[6usize] = 0.20f64
    s.sm1[7usize] = 0.15f64
    s.sm1[8usize] = 0.10f64
    s.sm1[9usize] = 0.075f64
    s.sm1[10usize] = 0.050f64
    s.sm1[11usize] = 0.025f64
    s.n = n
    s.nyh = n
    s.rtol = rtol
    s.atol = atol
    s.mxstep = maxsteps
    s.mxordn = mxordn
    s.mxords = mxords
    s.jtyp = 2usize
    s.mode = mode
    s.one = rr.lag
    if mode == 1usize {
        s.meth = meth0
        s.miter = miter0
        s.maxord = maxord0
    }
    var hmax = hmax_in
    if hmax <= 0.0f64 {
        var k = 1usize
        while k < nt {
            hmax = rk_fmax(hmax, math.abs[f64](times[k] - times[k - 1usize]))
            k += 1usize
        }
    }
    var y: [64]f64 = zero
    if n > 64usize { ret TooSmall }
    var i = 0usize
    out[0usize] = times[0usize]
    while i < n {
        y[i] = y0[i]
        out[(i + 1usize) * nt] = y0[i]
        i += 1usize
    }
    var it = 0usize
    var iev = 0usize
    var restart = true
    if rr.lag {
        if !hist_push[Ctx](ctx, f, rr.hist, times[0usize], y[0usize..n]) { ret TooSmall }
    }
    rr.rows = nt
    while it + 1usize < nt {
        var tcrit = times[nt - 1usize]
        if evt.len > 0usize {
            if iev < evt.len && evt[iev] == times[it] {
                evf(ctx, times[it], y[0usize..n])
                iev += 1usize
                restart = true
            }
            if iev < evt.len && evt[iev] > times[it + 1usize] { tcrit = evt[iev] }
        }
        let tout = times[it + 1usize]
        if rr.lag { tcrit = tout }
        var tcur = times[it]
        var reps = 0usize
        var stop = false
        while true {
            let st = ls_call[Ctx](ctx, f, &s, y[0usize..n], tcur, tout, restart, hini, hmax, hmin, evt.len > 0usize || rr.rootevent, tcrit, ng, g)
            if tcur != tout { restart = false }
            if st < 0i64 { ret Invalid }
            tcur = s.tret
            reps += 1usize
            if rr.lag {
                if !hist_push[Ctx](ctx, f, rr.hist, tcur, y[0usize..n]) { ret TooSmall }
                reps = 0usize
            }
            if st == 3i64 {
                if rr.rootevent {
                    var terminal = false
                    var last = 0usize
                    var j = 0usize
                    while j < ng {
                        if s.jroot[j] == 1usize {
                            last = j + 1usize
                            if (rr.termmask >> j) % 2usize == 1usize { terminal = true }
                        }
                        j += 1usize
                    }
                    let k = rr.nroot
                    if k < 100usize {
                        rr.troot[k] = tcur
                        rr.ind[k] = last
                        j = 0usize
                        while j < n {
                            rr.val[k * 3usize + j] = y[j]
                            j += 1usize
                        }
                    }
                    rr.nroot += 1usize
                    if terminal {
                        stop = true
                        break
                    }
                    evf(ctx, tcur, y[0usize..n])
                    restart = true
                    reps = 0usize
                } else {
                    stop = true
                    rr.nroot = 1usize
                    rr.troot[0usize] = tcur
                    var j = 0usize
                    rr.ind[0usize] = 0usize
                    while j < ng {
                        if s.jroot[j] == 1usize { rr.ind[0usize] = j + 1usize }
                        j += 1usize
                    }
                    break
                }
            }
            if !(tcur < tout && reps < 10usize) { break }
        }
        out[it + 1usize] = tcur
        i = 0usize
        while i < n {
            out[it + 1usize + nt * (1usize + i)] = y[i]
            i += 1usize
        }
        if stop {
            rr.rows = it + 2usize
            rr.stopped = true
            ret ok
        }
        it += 1usize
    }
    ret ok
}

// lsoda with time events (deSolve events = list(func, time) or data): `evt` are the sorted unique
// event times, all contained in `times`; `evf(ctx, t, y)` modifies the state at each; hmax_in > 0
// must be the largest gap of the caller's own output times (deSolve takes it before merging).
fn lsoda_event_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, mxordn: usize, mxords: usize, evt: []const f64, evf: fn(*Ctx, f64, []f64), out: []f64) -> err {
    var rr: RootRec = zero
    ret ls_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, mxordn, mxords, 0usize, 0usize, 0usize, 0usize, evt, evf, &rr, f, out)
}

fn lsode_event_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, adams: bool, evt: []const f64, evf: fn(*Ctx, f64, []f64), out: []f64) -> err {
    var meth = 2usize
    var miter = 2usize
    var maxord = 5usize
    if adams {
        meth = 1usize
        miter = 0usize
        maxord = 12usize
    }
    var rr: RootRec = zero
    ret ls_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, 12usize, 5usize, 1usize, meth, miter, maxord, evt, evf, &rr, f, out)
}

fn ev_none[Ctx: type](c: *Ctx, t: f64, y: []f64) {}

// deSolve lsodar (lsoda plus root functions): `g(ctx, t, y, out)` fills `ng` values. Without
// `rootevent` the run stops at the first root (the last output row is the root time and state);
// with it, each root calls `evf` and integration continues unless the root's bit (j) is set in
// `termmask`. `rr` receives rows written, roots found (troot, ind = last root index 1-based, val).
fn lsodar_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), g: fn(*Ctx, f64, []const f64, []f64), ng: usize, rootevent: bool, termmask: usize, evf: fn(*Ctx, f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, mxordn: usize, mxords: usize, rr: *RootRec, out: []f64) -> err {
    rr.ng = ng
    rr.rootevent = rootevent
    rr.termmask = termmask
    let evt: []const f64 = times[0usize..0usize]
    ret ls_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, mxordn, mxords, 0usize, 0usize, 0usize, 0usize, evt, evf, rr, g, out)
}

// deSolve dede(y0, times, f, method = "lsoda"): lsoda in one-step mode with tcrit = the next
// output time, the accepted state and derivative stored in `hist` after every step; f reaches
// the past through hist_past (lagvalue / lagderiv), so the caller's Ctx keeps a pointer to `hist`.
fn dede_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), hist: *Hist, times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, mxordn: usize, mxords: usize, out: []f64) -> err {
    var rr: RootRec = zero
    rr.lag = true
    rr.hist = hist
    hist.n = y0.len
    hist.cnt = 0usize
    let evt: []const f64 = times[0usize..0usize]
    ret ls_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, mxordn, mxords, 0usize, 0usize, 0usize, 0usize, evt, ev_none[Ctx], &rr, f, out)
}

fn lsoda_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, mxordn: usize, mxords: usize, out: []f64) -> err {
    var rr: RootRec = zero
    let evt: []const f64 = times[0usize..0usize]
    ret ls_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, mxordn, mxords, 0usize, 0usize, 0usize, 0usize, evt, ev_none[Ctx], &rr, f, out)
}

// deSolve lsode(y0, times, f, mf): `adams` selects mf 10 (functional iteration, maxord 12 by
// default) otherwise mf 22 (BDF, internal finite-difference Jacobian, maxord 5); maxord 0 means the default.
fn lsode_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, adams: bool, maxord_in: usize, out: []f64) -> err {
    var meth = 2usize
    var miter = 2usize
    var maxord = 5usize
    if adams {
        meth = 1usize
        miter = 0usize
        maxord = 12usize
    }
    if maxord_in > 0usize && maxord_in < maxord { maxord = maxord_in }
    var rr: RootRec = zero
    ret ls_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, 12usize, 5usize, 1usize, meth, miter, maxord, times[0usize..0usize], ev_none[Ctx], &rr, f, out)
}

// ---- correctly rounded pow through double-double arithmetic. deSolve's Fortran calls the C
// library pow, which on the reference platform is (nearly) correctly rounded; fdlibm's pow
// is off by an ulp often enough to flip the step-size decisions of lsoda, so the solver uses
// this one. Falls back to math.pow outside x > 0, finite, |y log x| < 600.

fn dd_two_sum(a: f64, b: f64) -> (f64, f64) {
    let s = a + b
    let bb = s - a
    let e = (a - (s - bb)) + (b - bb)
    ret (s, e)
}

fn dd_norm(h: f64, l: f64) -> (f64, f64) {
    let s = h + l
    let e = l - (s - h)
    ret (s, e)
}

fn dd_add(ah: f64, al: f64, bh: f64, bl: f64) -> (f64, f64) {
    let (s, e) = dd_two_sum(ah, bh)
    let (t, f) = dd_two_sum(al, bl)
    let (u, g) = dd_norm(s, e + t)
    let (nh, nl) = dd_norm(u, g + f)
    ret (nh, nl)
}

fn dd_mul(ah: f64, al: f64, bh: f64, bl: f64) -> (f64, f64) {
    let p = ah * bh
    let e = math.fma[f64](ah, bh, 0.0f64 - p) + (ah * bl + al * bh)
    let (nh, nl) = dd_norm(p, e)
    ret (nh, nl)
}

fn dd_div_d(ah: f64, al: f64, d: f64) -> (f64, f64) {
    let q1 = ah / d
    let p = q1 * d
    let pe = math.fma[f64](q1, d, 0.0f64 - p)
    let r = ((ah - p) - pe + al) / d
    let (nh, nl) = dd_norm(q1, r)
    ret (nh, nl)
}

// exp(ah + al) as a double-double.
fn dd_exp(ah: f64, al: f64) -> (f64, f64) {
    let ln2h = 0.6931471805599452862f64
    let ln2l = 2.319046813846299558e-17f64
    var half = 0.5f64
    if ah < 0.0f64 { half = 0.0f64 - 0.5f64 }
    let k = i64(ah * 1.4426950408889634074f64 + half)
    let kf = f64(k)
    let p = kf * ln2h
    let pe = math.fma[f64](kf, ln2h, 0.0f64 - p)
    let (r1h, r1l) = dd_add(ah, al, 0.0f64 - p, 0.0f64 - pe)
    let (rh, rl) = dd_add(r1h, r1l, 0.0f64 - kf * ln2l, 0.0f64)
    let sh = rh * 0.00390625f64
    let sl = rl * 0.00390625f64
    // expm1(s) by the series, then eight squarings in the (1 + x)^2 - 1 = 2x + x^2 form
    var th = sh
    var tl = sl
    var eh = sh
    var el = sl
    var nterm = 2usize
    while nterm <= 11usize {
        let (mh, ml) = dd_mul(th, tl, sh, sl)
        let (dh, dl) = dd_div_d(mh, ml, f64(nterm))
        th = dh
        tl = dl
        let (ah2, al2) = dd_add(eh, el, th, tl)
        eh = ah2
        el = al2
        nterm += 1usize
    }
    var sq = 0usize
    while sq < 8usize {
        let (mh, ml) = dd_mul(eh, el, eh, el)
        let (dh, dl) = dd_add(2.0f64 * eh, 2.0f64 * el, mh, ml)
        eh = dh
        el = dl
        sq += 1usize
    }
    let (fh, fl) = dd_add(1.0f64, 0.0f64, eh, el)
    let scale = math.power_of_two(k)
    ret (fh * scale, fl * scale)
}

fn dd_pow(x: f64, y: f64) -> f64 {
    if !(x > 0.0f64) || x > 1.0e300f64 || x < 1.0e-300f64 || y == 0.0f64 || x == 1.0f64 { ret math.pow[f64](x, y) }
    let y0 = math.log[f64](x)
    if math.abs[f64](y * y0) > 600.0f64 { ret math.pow[f64](x, y) }
    let (eh, el) = dd_exp(0.0f64 - y0, 0.0f64)
    let p = x * eh
    let pe = math.fma[f64](x, eh, 0.0f64 - p)
    let (t1h, t1l) = dd_add(p, pe, x * el, 0.0f64)
    let (th, tl) = dd_add(t1h, t1l, 0.0f64 - 1.0f64, 0.0f64)
    let (lh, ll) = dd_add(y0, 0.0f64, th, tl)
    let zp = y * lh
    let zpe = math.fma[f64](y, lh, 0.0f64 - zp)
    let (zh, zl) = dd_norm(zp, zpe + y * ll)
    let (rh, rl) = dd_exp(zh, zl)
    ret rh + rl
}

// ---- deSolve radau(y0, times, f, mass): Hairer-Wanner RADAU5 (3-stage Radau IIA, order 5) with the
// internal finite-difference Jacobian, scalar tolerances, nind = (n, 0, 0) (so index-1 DAEs through
// a constant full mass matrix, M y' = f), the predictive Gustafsson controller and deSolve's own
// output through the collocation polynomial. Line-by-line port of radau5.f (RADAU5, RADCOR,
// CONTR5) and the full-matrix branches (ijob 1 and 5) of radau5a.f (DECOMR/C, SLVRAD, ESTRAD,
// DEC, SOL, DECC, SOLC). Matrices are column-major n x n.

fn rad_dec(n: usize, a: []f64, ip: []usize) -> usize {
    var k = 0usize
    while k + 1usize < n {
        var m = k
        var i = k + 1usize
        while i < n {
            if math.abs[f64](a[i + k * n]) > math.abs[f64](a[m + k * n]) { m = i }
            i += 1usize
        }
        ip[k] = m
        var t = a[m + k * n]
        if m != k {
            a[m + k * n] = a[k + k * n]
            a[k + k * n] = t
        }
        if t == 0.0f64 { ret k + 1usize }
        t = 1.0f64 / t
        i = k + 1usize
        while i < n {
            a[i + k * n] = (0.0f64 - a[i + k * n]) * t
            i += 1usize
        }
        var j = k + 1usize
        while j < n {
            t = a[m + j * n]
            a[m + j * n] = a[k + j * n]
            a[k + j * n] = t
            if t != 0.0f64 {
                i = k + 1usize
                while i < n {
                    a[i + j * n] = a[i + j * n] + a[i + k * n] * t
                    i += 1usize
                }
            }
            j += 1usize
        }
        k += 1usize
    }
    if a[(n - 1usize) + (n - 1usize) * n] == 0.0f64 { ret n }
    ret 0usize
}

fn rad_sol(n: usize, a: []const f64, b: []f64, ip: []const usize) {
    var k = 0usize
    while k + 1usize < n {
        let m = ip[k]
        let t = b[m]
        b[m] = b[k]
        b[k] = t
        var i = k + 1usize
        while i < n {
            b[i] = b[i] + a[i + k * n] * t
            i += 1usize
        }
        k += 1usize
    }
    var kb = 1usize
    while kb < n {
        let km1 = n - kb
        b[km1] = b[km1] / a[km1 + km1 * n]
        let t = 0.0f64 - b[km1]
        var i = 0usize
        while i < km1 {
            b[i] = b[i] + a[i + km1 * n] * t
            i += 1usize
        }
        kb += 1usize
    }
    b[0usize] = b[0usize] / a[0usize]
}

fn rad_decc(n: usize, ar: []f64, ai: []f64, ip: []usize) -> usize {
    var k = 0usize
    while k + 1usize < n {
        var m = k
        var i = k + 1usize
        while i < n {
            if math.abs[f64](ar[i + k * n]) + math.abs[f64](ai[i + k * n]) > math.abs[f64](ar[m + k * n]) + math.abs[f64](ai[m + k * n]) { m = i }
            i += 1usize
        }
        ip[k] = m
        var tr = ar[m + k * n]
        var ti = ai[m + k * n]
        if m != k {
            ar[m + k * n] = ar[k + k * n]
            ai[m + k * n] = ai[k + k * n]
            ar[k + k * n] = tr
            ai[k + k * n] = ti
        }
        if math.abs[f64](tr) + math.abs[f64](ti) == 0.0f64 { ret k + 1usize }
        let den = tr * tr + ti * ti
        tr = tr / den
        ti = (0.0f64 - ti) / den
        i = k + 1usize
        while i < n {
            let pr = ar[i + k * n] * tr - ai[i + k * n] * ti
            let pi = ai[i + k * n] * tr + ar[i + k * n] * ti
            ar[i + k * n] = 0.0f64 - pr
            ai[i + k * n] = 0.0f64 - pi
            i += 1usize
        }
        var j = k + 1usize
        while j < n {
            tr = ar[m + j * n]
            ti = ai[m + j * n]
            ar[m + j * n] = ar[k + j * n]
            ai[m + j * n] = ai[k + j * n]
            ar[k + j * n] = tr
            ai[k + j * n] = ti
            if math.abs[f64](tr) + math.abs[f64](ti) != 0.0f64 {
                i = k + 1usize
                while i < n {
                    let pr = ar[i + k * n] * tr - ai[i + k * n] * ti
                    let pi = ai[i + k * n] * tr + ar[i + k * n] * ti
                    ar[i + j * n] = ar[i + j * n] + pr
                    ai[i + j * n] = ai[i + j * n] + pi
                    i += 1usize
                }
            }
            j += 1usize
        }
        k += 1usize
    }
    if math.abs[f64](ar[(n - 1usize) + (n - 1usize) * n]) + math.abs[f64](ai[(n - 1usize) + (n - 1usize) * n]) == 0.0f64 { ret n }
    ret 0usize
}

fn rad_solc(n: usize, ar: []const f64, ai: []const f64, br: []f64, bi: []f64, ip: []const usize) {
    var k = 0usize
    while k + 1usize < n {
        let m = ip[k]
        let tr = br[m]
        let ti = bi[m]
        br[m] = br[k]
        bi[m] = bi[k]
        br[k] = tr
        bi[k] = ti
        var i = k + 1usize
        while i < n {
            let pr = ar[i + k * n] * tr - ai[i + k * n] * ti
            let pi = ai[i + k * n] * tr + ar[i + k * n] * ti
            br[i] = br[i] + pr
            bi[i] = bi[i] + pi
            i += 1usize
        }
        k += 1usize
    }
    var kb = 1usize
    while kb < n {
        let km1 = n - kb
        let den = ar[km1 + km1 * n] * ar[km1 + km1 * n] + ai[km1 + km1 * n] * ai[km1 + km1 * n]
        let pr = br[km1] * ar[km1 + km1 * n] + bi[km1] * ai[km1 + km1 * n]
        let pi = bi[km1] * ar[km1 + km1 * n] - br[km1] * ai[km1 + km1 * n]
        br[km1] = pr / den
        bi[km1] = pi / den
        let tr = 0.0f64 - br[km1]
        let ti = 0.0f64 - bi[km1]
        var i = 0usize
        while i < km1 {
            let qr = ar[i + km1 * n] * tr - ai[i + km1 * n] * ti
            let qi = ai[i + km1 * n] * tr + ar[i + km1 * n] * ti
            br[i] = br[i] + qr
            bi[i] = bi[i] + qi
            i += 1usize
        }
        kb += 1usize
    }
    let den = ar[0usize] * ar[0usize] + ai[0usize] * ai[0usize]
    let pr = br[0usize] * ar[0usize] + bi[0usize] * ai[0usize]
    let pi = bi[0usize] * ar[0usize] - br[0usize] * ai[0usize]
    br[0usize] = pr / den
    bi[0usize] = pi / den
}

fn rad_powi(x_in: f64, m: usize) -> f64 {
    var x = x_in
    var y = 1.0f64
    if m % 2usize == 1usize { y = x }
    var e = m / 2usize
    while e > 0usize {
        x = x * x
        if e % 2usize == 1usize { y = y * x }
        e = e / 2usize
    }
    ret y
}

fn rad_scal(n: usize, atol: f64, rtol: f64, y: []const f64, scal: []f64) {
    var i = 0usize
    while i < n {
        scal[i] = atol + rtol * math.abs[f64](y[i])
        i += 1usize
    }
}

// `mass` is empty for M = I, else the full n x n column-major matrix. maxsteps is the total
// step budget (deSolve passes maxsteps * length(times)). hmax_in <= 0: largest gap of `times`.
// Returns Invalid when RADAU5 reports an error (idid < 0). `out` is nt x (n + 1) column-major.
fn radau_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0in: []const f64, rtol_in: f64, atol_in: f64, hmax_in: f64, hini: f64, maxsteps: usize, mass: []const f64, out: []f64) -> err {
    let n = y0in.len
    let nt = times.len
    if nt < 2usize || n == 0usize || out.len < nt * (n + 1usize) { ret Invalid }
    let implct = mass.len > 0usize
    let (blk, be) = mem.alloc[f64](a, 5usize * n * n + 14usize * n)
    if be != ok { ret be }
    let (piv, pe) = mem.alloc[usize](a, 2usize * n)
    if pe != ok { ret pe }
    var zi = 0usize
    while zi < blk.len {
        blk[zi] = 0.0f64
        zi += 1usize
    }
    var at = 0usize
    let fjac = blk[at..at + n * n]
    at += n * n
    let e1 = blk[at..at + n * n]
    at += n * n
    let e2r = blk[at..at + n * n]
    at += n * n
    let e2i = blk[at..at + n * n]
    at += n * n
    let fmas = blk[at..at + n * n]
    at += n * n
    let y = blk[at..at + n]
    at += n
    let z1 = blk[at..at + n]
    at += n
    let z2 = blk[at..at + n]
    at += n
    let z3 = blk[at..at + n]
    at += n
    let yy0 = blk[at..at + n]
    at += n
    let scal = blk[at..at + n]
    at += n
    let f1 = blk[at..at + n]
    at += n
    let f2 = blk[at..at + n]
    at += n
    let f3 = blk[at..at + n]
    at += n
    let cont = blk[at..at + 4usize * n]
    let ip1 = piv[0usize..n]
    let ip2 = piv[n..2usize * n]
    var i = 0usize
    while i < n {
        y[i] = y0in[i]
        i += 1usize
    }
    if implct {
        zi = 0usize
        while zi < n * n {
            fmas[zi] = mass[zi]
            zi += 1usize
        }
    }
    let uround = 1.1102230246251565e-16f64
    if atol_in <= 0.0f64 || rtol_in <= 10.0f64 * uround { ret Invalid }
    let quot0 = atol_in / rtol_in
    let rtol = 0.1f64 * dd_pow(rtol_in, 2.0f64 / 3.0f64)
    let atol = rtol * quot0
    let nmax = maxsteps
    let nit = 7usize
    let safe = 0.9f64
    let thet = 0.001f64
    let fnewt = rk_fmax(10.0f64 * uround / rtol, rk_fmin(0.03f64, math.sqrt[f64](rtol)))
    let quot1 = 1.0f64
    let quot2 = 1.2f64
    var hmax = hmax_in
    if hmax <= 0.0f64 {
        var k = 1usize
        while k < nt {
            hmax = rk_fmax(hmax, math.abs[f64](times[k] - times[k - 1usize]))
            k += 1usize
        }
    }
    let facl = 5.0f64
    let facr = 1.0f64 / 8.0f64
    let sq6 = math.sqrt[f64](6.0f64)
    let c1 = (4.0f64 - sq6) / 10.0f64
    let c2 = (4.0f64 + sq6) / 10.0f64
    let c1m1 = c1 - 1.0f64
    let c2m1 = c2 - 1.0f64
    let c1mc2 = c1 - c2
    let dd1 = 0.0f64 - (13.0f64 + 7.0f64 * sq6) / 3.0f64
    let dd2 = (0.0f64 - 13.0f64 + 7.0f64 * sq6) / 3.0f64
    let dd3 = 0.0f64 - 1.0f64 / 3.0f64
    let r81 = dd_pow(81.0f64, 1.0f64 / 3.0f64)
    let r9 = dd_pow(9.0f64, 1.0f64 / 3.0f64)
    var u1 = (6.0f64 + r81 - r9) / 30.0f64
    var alph = (12.0f64 - r81 + r9) / 60.0f64
    var beta = (r81 + r9) * math.sqrt[f64](3.0f64) / 60.0f64
    let cno = alph * alph + beta * beta
    u1 = 1.0f64 / u1
    alph = alph / cno
    beta = beta / cno
    let t11 = 9.1232394870892942792e-2f64
    let t12 = 0.0f64 - 0.14125529502095420843f64
    let t13 = 0.0f64 - 3.0029194105147424492e-2f64
    let t21 = 0.24171793270710701896f64
    let t22 = 0.20412935229379993199f64
    let t23 = 0.38294211275726193779f64
    let t31 = 0.96604818261509293619f64
    let ti11 = 4.3255798900631553510f64
    let ti12 = 0.33919925181580986954f64
    let ti13 = 0.54177053993587487119f64
    let ti21 = 0.0f64 - 4.1787185915519047273f64
    let ti22 = 0.0f64 - 0.32768282076106238708f64
    let ti23 = 0.47662355450055045196f64
    let ti31 = 0.0f64 - 0.50287263494578687595f64
    let ti32 = 2.5719269498556054292f64
    let ti33 = 0.0f64 - 0.59603920482822492497f64
    let xend = times[nt - 1usize]
    var x = times[0usize]
    let posneg = 1.0f64
    let hmaxn = rk_fmin(math.abs[f64](hmax), math.abs[f64](xend - x))
    var h = hini
    if math.abs[f64](h) <= 10.0f64 * uround { h = 1.0e-6f64 }
    h = rk_fmin(math.abs[f64](h), hmaxn)
    var hold = h
    var reject = false
    var first = true
    var last = false
    if (x + h * 1.0001f64 - xend) * posneg >= 0.0f64 {
        h = xend - x
        last = true
    }
    var faccon = 1.0f64
    let cfac = safe * f64(1usize + 2usize * nit)
    var nsing = 0usize
    var xold = x
    var xsol = x
    var hsol = hold
    var hacc = 1.0f64
    var erracc = 1.0f64
    var dynold = 1.0f64
    var thqold = 1.0f64
    var naccpt = 0usize
    var nstep = 0usize
    var theta = 0.0f64
    var hnew = 0.0f64
    var quot = 0.0f64
    var rerr = 0.0f64
    var ier = 0usize
    var caljac = false
    var itn = 1usize
    out[0usize] = times[0usize]
    i = 0usize
    while i < n {
        out[(i + 1usize) * nt] = y[i]
        i += 1usize
    }
    rad_scal(n, atol, rtol, y, scal)
    f(ctx, x, y, yy0)
    let n3 = f64(3usize * n)
    var lbl = 10usize
    var idid = 0i64
    while idid == 0i64 {
        if lbl == 10usize {
            i = 0usize
            while i < n {
                let ysafe = y[i]
                let delt = math.sqrt[f64](uround * rk_fmax(1.0e-5f64, math.abs[f64](ysafe)))
                y[i] = ysafe + delt
                f(ctx, x, y, cont[0usize..n])
                var j = 0usize
                while j < n {
                    fjac[j + i * n] = (cont[j] - yy0[j]) / delt
                    j += 1usize
                }
                y[i] = ysafe
                i += 1usize
            }
            caljac = true
            lbl = 20usize
        }
        if lbl == 20usize {
            let fac1 = u1 / h
            let alphn = alph / h
            let betan = beta / h
            var j = 0usize
            while j < n {
                i = 0usize
                while i < n {
                    let ix = i + j * n
                    if implct {
                        e1[ix] = fmas[ix] * fac1 - fjac[ix]
                        e2r[ix] = fmas[ix] * alphn - fjac[ix]
                        e2i[ix] = fmas[ix] * betan
                    } else {
                        e1[ix] = 0.0f64 - fjac[ix]
                        e2r[ix] = 0.0f64 - fjac[ix]
                        e2i[ix] = 0.0f64
                        if i == j {
                            e1[ix] = e1[ix] + fac1
                            e2r[ix] = e2r[ix] + alphn
                            e2i[ix] = betan
                        }
                    }
                    i += 1usize
                }
                j += 1usize
            }
            ier = rad_dec(n, e1, ip1)
            if ier == 0usize { ier = rad_decc(n, e2r, e2i, ip2) }
            if ier != 0usize {
                lbl = 78usize
            } else {
                lbl = 30usize
            }
        }
        if lbl == 30usize {
            nstep += 1usize
            if nstep > nmax {
                idid = 0i64 - 2i64
            } else if 0.1f64 * math.abs[f64](h) <= math.abs[f64](x) * uround {
                idid = 0i64 - 3i64
            }
        }
        if lbl == 30usize && idid == 0i64 {
            let fac1 = u1 / h
            let alphn = alph / h
            let betan = beta / h
            let xph = x + h
            if first {
                i = 0usize
                while i < n {
                    z1[i] = 0.0f64
                    z2[i] = 0.0f64
                    z3[i] = 0.0f64
                    f1[i] = 0.0f64
                    f2[i] = 0.0f64
                    f3[i] = 0.0f64
                    i += 1usize
                }
            } else {
                let c3q = h / hold
                let c1q = c1 * c3q
                let c2q = c2 * c3q
                i = 0usize
                while i < n {
                    let ak1 = cont[i + n]
                    let ak2 = cont[i + 2usize * n]
                    let ak3 = cont[i + 3usize * n]
                    let z1i = c1q * (ak1 + (c1q - c2m1) * (ak2 + (c1q - c1m1) * ak3))
                    let z2i = c2q * (ak1 + (c2q - c2m1) * (ak2 + (c2q - c1m1) * ak3))
                    let z3i = c3q * (ak1 + (c3q - c2m1) * (ak2 + (c3q - c1m1) * ak3))
                    z1[i] = z1i
                    z2[i] = z2i
                    z3[i] = z3i
                    f1[i] = ti11 * z1i + ti12 * z2i + ti13 * z3i
                    f2[i] = ti21 * z1i + ti22 * z2i + ti23 * z3i
                    f3[i] = ti31 * z1i + ti32 * z2i + ti33 * z3i
                    i += 1usize
                }
            }
            var newt = 0usize
            var dyno = 1.0f64
            faccon = dd_pow(rk_fmax(faccon, uround), 0.8f64)
            theta = math.abs[f64](thet)
            var nxt = 0usize
            var go = true
            while go {
                go = false
                if newt >= nit {
                    nxt = 78usize
                } else if !(dyno > 0.0f64) {
                    nxt = 78usize
                } else {
                    i = 0usize
                    while i < n {
                        cont[i] = y[i] + z1[i]
                        i += 1usize
                    }
                    f(ctx, x + c1 * h, cont[0usize..n], z1)
                    i = 0usize
                    while i < n {
                        cont[i] = y[i] + z2[i]
                        i += 1usize
                    }
                    f(ctx, x + c2 * h, cont[0usize..n], z2)
                    i = 0usize
                    while i < n {
                        cont[i] = y[i] + z3[i]
                        i += 1usize
                    }
                    f(ctx, xph, cont[0usize..n], z3)
                    i = 0usize
                    while i < n {
                        let a1 = z1[i]
                        let a2 = z2[i]
                        let a3 = z3[i]
                        z1[i] = ti11 * a1 + ti12 * a2 + ti13 * a3
                        z2[i] = ti21 * a1 + ti22 * a2 + ti23 * a3
                        z3[i] = ti31 * a1 + ti32 * a2 + ti33 * a3
                        i += 1usize
                    }
                    i = 0usize
                    while i < n {
                        var s1 = 0.0f64 - f1[i]
                        var s2 = 0.0f64 - f2[i]
                        var s3 = 0.0f64 - f3[i]
                        if implct {
                            s1 = 0.0f64
                            s2 = 0.0f64
                            s3 = 0.0f64
                            var jj = 0usize
                            while jj < n {
                                let bb = fmas[i + jj * n]
                                s1 = s1 - bb * f1[jj]
                                s2 = s2 - bb * f2[jj]
                                s3 = s3 - bb * f3[jj]
                                jj += 1usize
                            }
                            z1[i] = z1[i] + s1 * fac1
                        } else {
                            z1[i] = z1[i] - f1[i] * fac1
                        }
                        z2[i] = z2[i] + s2 * alphn - s3 * betan
                        z3[i] = z3[i] + s3 * alphn + s2 * betan
                        i += 1usize
                    }
                    rad_sol(n, e1, z1, ip1)
                    rad_solc(n, e2r, e2i, z2, z3, ip2)
                    newt += 1usize
                    dyno = 0.0f64
                    i = 0usize
                    while i < n {
                        let denom = scal[i]
                        dyno = dyno + (z1[i] / denom) * (z1[i] / denom) + (z2[i] / denom) * (z2[i] / denom) + (z3[i] / denom) * (z3[i] / denom)
                        i += 1usize
                    }
                    dyno = math.sqrt[f64](dyno / n3)
                    var bad = false
                    if newt > 1usize && newt < nit {
                        let thq = dyno / dynold
                        if newt == 2usize {
                            theta = thq
                        } else {
                            theta = math.sqrt[f64](thq * thqold)
                        }
                        thqold = thq
                        if theta < 0.99f64 {
                            faccon = theta / (1.0f64 - theta)
                            let dyth = faccon * dyno * rad_powi(theta, nit - 1usize - newt) / fnewt
                            if dyth >= 1.0f64 {
                                let qnewt = rk_fmax(1.0e-4f64, rk_fmin(20.0f64, dyth))
                                let hhfac = 0.8f64 * dd_pow(qnewt, (0.0f64 - 1.0f64) / (4.0f64 + f64(nit - 1usize - newt)))
                                h = hhfac * h
                                reject = true
                                last = false
                                if caljac { nxt = 20usize } else { nxt = 10usize }
                                bad = true
                            }
                        } else {
                            nxt = 78usize
                            bad = true
                        }
                    }
                    if !bad {
                        dynold = rk_fmax(dyno, uround)
                        i = 0usize
                        while i < n {
                            let f1i = f1[i] + z1[i]
                            let f2i = f2[i] + z2[i]
                            let f3i = f3[i] + z3[i]
                            f1[i] = f1i
                            f2[i] = f2i
                            f3[i] = f3i
                            z1[i] = t11 * f1i + t12 * f2i + t13 * f3i
                            z2[i] = t21 * f1i + t22 * f2i + t23 * f3i
                            z3[i] = t31 * f1i + f2i
                            i += 1usize
                        }
                        if faccon * dyno > fnewt { go = true }
                    }
                }
            }
            if nxt != 0usize {
                lbl = nxt
            } else {
                let hee1 = dd1 / h
                let hee2 = dd2 / h
                let hee3 = dd3 / h
                i = 0usize
                while i < n {
                    f1[i] = hee1 * z1[i] + hee2 * z2[i] + hee3 * z3[i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    if implct {
                        var sum = 0.0f64
                        var jj = 0usize
                        while jj < n {
                            sum = sum + fmas[i + jj * n] * f1[jj]
                            jj += 1usize
                        }
                        f2[i] = sum
                    } else {
                        f2[i] = f1[i]
                    }
                    cont[i] = f2[i] + yy0[i]
                    i += 1usize
                }
                rad_sol(n, e1, cont[0usize..n], ip1)
                rerr = 0.0f64
                i = 0usize
                while i < n {
                    rerr = rerr + (cont[i] / scal[i]) * (cont[i] / scal[i])
                    i += 1usize
                }
                rerr = rk_fmax(math.sqrt[f64](rerr / f64(n)), 1.0e-10f64)
                if rerr >= 1.0f64 && (first || reject) {
                    i = 0usize
                    while i < n {
                        cont[i] = y[i] + cont[i]
                        i += 1usize
                    }
                    f(ctx, x, cont[0usize..n], f1)
                    i = 0usize
                    while i < n {
                        cont[i] = f1[i] + f2[i]
                        i += 1usize
                    }
                    rad_sol(n, e1, cont[0usize..n], ip1)
                    rerr = 0.0f64
                    i = 0usize
                    while i < n {
                        rerr = rerr + (cont[i] / scal[i]) * (cont[i] / scal[i])
                        i += 1usize
                    }
                    rerr = rk_fmax(math.sqrt[f64](rerr / f64(n)), 1.0e-10f64)
                }
                let fac = rk_fmin(safe, cfac / f64(newt + 2usize * nit))
                quot = rk_fmax(facr, rk_fmin(facl, dd_pow(rerr, 0.25f64) / fac))
                hnew = h / quot
                if rerr < 1.0f64 {
                    first = false
                    naccpt += 1usize
                    if naccpt > 1usize {
                        var facgus = (hacc / h) * dd_pow(rerr * rerr / erracc, 0.25f64) / safe
                        facgus = rk_fmax(facr, rk_fmin(facl, facgus))
                        quot = rk_fmax(quot, facgus)
                        hnew = h / quot
                    }
                    hacc = h
                    erracc = rk_fmax(1.0e-2f64, rerr)
                    xold = x
                    hold = h
                    x = xph
                    i = 0usize
                    while i < n {
                        y[i] = y[i] + z3[i]
                        let z2i = z2[i]
                        let z1i = z1[i]
                        cont[i + n] = (z2i - z3[i]) / c2m1
                        let ak = (z1i - z2i) / c1mc2
                        var acont3 = z1i / c1
                        acont3 = (ak - acont3) / c2
                        cont[i + 2usize * n] = (ak - cont[i + n]) / c1m1
                        cont[i + 3usize * n] = cont[i + 2usize * n] - acont3
                        i += 1usize
                    }
                    rad_scal(n, atol, rtol, y, scal)
                    xsol = x
                    hsol = hold
                    i = 0usize
                    while i < n {
                        cont[i] = y[i]
                        i += 1usize
                    }
                    if xold != x {
                        while itn < nt && xold <= times[itn] && times[itn] < x {
                            let s = (times[itn] - xsol) / hsol
                            out[itn] = times[itn]
                            i = 0usize
                            while i < n {
                                out[itn + nt * (1usize + i)] = cont[i] + s * (cont[i + n] + (s - c2m1) * (cont[i + 2usize * n] + (s - c1m1) * cont[i + 3usize * n]))
                                i += 1usize
                            }
                            itn += 1usize
                        }
                    }
                    caljac = false
                    if last {
                        idid = 1i64
                    } else {
                        f(ctx, x, y, yy0)
                        hnew = posneg * rk_fmin(math.abs[f64](hnew), hmaxn)
                        if reject { hnew = posneg * rk_fmin(math.abs[f64](hnew), math.abs[f64](h)) }
                        reject = false
                        var skip = false
                        if (x + hnew / quot1 - xend) * posneg >= 0.0f64 {
                            h = xend - x
                            last = true
                        } else {
                            let qt = hnew / h
                            if theta <= thet && qt >= quot1 && qt <= quot2 { skip = true }
                            if !skip { h = hnew }
                        }
                        if skip {
                            lbl = 30usize
                        } else if theta <= thet {
                            lbl = 20usize
                        } else {
                            lbl = 10usize
                        }
                    }
                } else {
                    reject = true
                    last = false
                    if first {
                        h = h * 0.1f64
                    } else {
                        h = hnew
                    }
                    if caljac { lbl = 20usize } else { lbl = 10usize }
                }
            }
        }
        if lbl == 78usize && idid == 0i64 {
            if ier != 0usize {
                nsing += 1usize
                if nsing >= 5usize { idid = 0i64 - 4i64 }
            }
            if idid == 0i64 {
                h = h * 0.5f64
                reject = true
                last = false
                if caljac { lbl = 20usize } else { lbl = 10usize }
            }
        }
    }
    if idid < 0i64 { ret Invalid }
    if itn < nt {
        out[itn] = x
        i = 0usize
        while i < n {
            out[itn + nt * (1usize + i)] = y[i]
            i += 1usize
        }
    }
    ret ok
}

// ---- deSolve vode(y0, times, f): Brown-Byrne-Hindmarsh DVODE with scalar tolerances and itask = 1.
// `adams` selects mf = 10 (functional iteration, maxord 12) or mf = 22 (BDF, chord iteration with the
// internal finite-difference Jacobian saved for reuse, maxord 5), both with a positive mf (jsv = 1).
// A line-by-line port of dvode.f (DVODE, DVHIN, DVINDY, DVSTEP, DVSET, DVJUST, DVNLSD, DVJAC, DVSOL).
// Vectors el, tau and tq are indexed from 1 as in the Fortran; yh(i, j) is yh[i + (j - 1) * n].

type Vode = struct {
    n: usize, meth: usize, miter: usize, maxord: usize, mxstep: usize,
    acnrm: f64, ccmxj: f64, conp: f64, crate: f64, drc: f64, eta: f64, etamax: f64, h: f64,
    hmin: f64, hmxi: f64, hnew: f64, hscal: f64, prl1: f64, rc: f64, rl1: f64, tn: f64, uround: f64, hu: f64,
    rtol: f64, atol: f64, h0: f64,
    el: [14]f64, tau: [14]f64, tq: [6]f64,
    icf: i64, jcur: usize, jstart: i64, kflag: i64, kuth: usize, l: usize, lmax: usize, msbj: usize,
    newh: usize, newq: usize, nq: usize, nqwait: usize, nslj: usize, nslp: usize, ipup: usize,
    nst: usize, nfe: usize, nje: usize, nlu: usize, nni: usize, niter: usize,
    yh: []f64, ewt: []f64, savf: []f64, acor: []f64, y: []f64, wm: []f64, jsave: []f64, ipvt: []usize
}

fn vo_dewset(s: *Vode) {
    var i = 0usize
    while i < s.n {
        s.ewt[i] = s.rtol * math.abs[f64](s.yh[i]) + s.atol
        i += 1usize
    }
}

fn vo_ewt_invert(s: *Vode) -> bool {
    var i = 0usize
    while i < s.n {
        if s.ewt[i] <= 0.0f64 { ret false }
        s.ewt[i] = 1.0f64 / s.ewt[i]
        i += 1usize
    }
    ret true
}

// DVHIN: first step size in s.h0 (and the extra derivative evaluations in s.niter); -1 when tout is too close.
fn vo_hin[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Vode, tout: f64, t0: f64) -> i64 {
    let n = s.n
    s.niter = 0usize
    let tdist = math.abs[f64](tout - t0)
    let tround = s.uround * rk_fmax(math.abs[f64](t0), math.abs[f64](tout))
    if tdist < 2.0f64 * tround { ret 0i64 - 1i64 }
    let hlb = 100.0f64 * tround
    var hub = 0.1f64 * tdist
    var i = 0usize
    while i < n {
        let delyi = 0.1f64 * math.abs[f64](s.yh[i]) + s.atol
        let afi = math.abs[f64](s.yh[n + i])
        if afi * hub > delyi { hub = delyi / afi }
        i += 1usize
    }
    var iter = 0usize
    var hg = math.sqrt[f64](hlb * hub)
    var hnew = 0.0f64
    if hub < hlb {
        s.h0 = hg
        s.h0 = ls_sign(s.h0, tout - t0)
        ret 0i64
    }
    var go = true
    while go {
        go = false
        let hh = ls_sign(hg, tout - t0)
        let t1 = t0 + hh
        i = 0usize
        while i < n {
            s.y[i] = s.yh[i] + hh * s.yh[n + i]
            i += 1usize
        }
        f(ctx, t1, s.y, s.acor)
        i = 0usize
        while i < n {
            s.acor[i] = (s.acor[i] - s.yh[n + i]) / hh
            i += 1usize
        }
        let yddnrm = ls_dvnorm(n, s.acor, s.ewt)
        if yddnrm * hub * hub > 2.0f64 {
            hnew = math.sqrt[f64](2.0f64 / yddnrm)
        } else {
            hnew = math.sqrt[f64](hg * hub)
        }
        iter += 1usize
        if iter < 4usize {
            let hrat = hnew / hg
            if !(hrat > 0.5f64 && hrat < 2.0f64) {
                if iter >= 2usize && hnew > 2.0f64 * hg {
                    hnew = hg
                } else {
                    hg = hnew
                    go = true
                }
            }
        }
    }
    s.h0 = hnew * 0.5f64
    if s.h0 < hlb { s.h0 = hlb }
    if s.h0 > hub { s.h0 = hub }
    s.h0 = ls_sign(s.h0, tout - t0)
    s.niter = iter
    ret 0i64
}

// DVINDY with k = 0: interpolate at t into dky; nonzero when t is outside the last step.
fn vo_indy0(s: *Vode, t: f64, dky: []f64) -> i64 {
    let n = s.n
    let tfuzz = 100.0f64 * s.uround * (s.tn + s.hu)
    let tp = s.tn - s.hu - tfuzz
    let tn1 = s.tn + tfuzz
    if (t - tp) * (t - tn1) > 0.0f64 { ret 0i64 - 2i64 }
    let sv = (t - s.tn) / s.h

    var c = 1.0f64
    var i = 0usize
    while i < n {
        dky[i] = c * s.yh[i + (s.l - 1usize) * n]
        i += 1usize
    }
    if s.nq == 0usize { ret 0i64 }
    var jb = 1usize
    while jb <= s.nq {
        let j = s.nq - jb
        let jp1 = j + 1usize
        c = 1.0f64
        i = 0usize
        while i < n {
            dky[i] = c * s.yh[i + (jp1 - 1usize) * n] + sv * dky[i]
            i += 1usize
        }
        jb += 1usize
    }
    ret 0i64
}

fn vo_set(s: *Vode) {
    let flotl = f64(s.l)
    let nqm1 = s.nq - 1usize
    var em: [14]f64 = zero
    var i = 0usize
    if s.meth == 1usize {
        if s.nq == 1usize {
            s.el[1usize] = 1.0f64
            s.el[2usize] = 1.0f64
            s.tq[1usize] = 1.0f64
            s.tq[2usize] = 2.0f64
            s.tq[3usize] = 6.0f64 * s.tq[2usize]
            s.tq[5usize] = 1.0f64
        } else {
            var hsum = s.h
            em[1usize] = 1.0f64
            let flotnq = flotl - 1.0f64
            i = 2usize
            while i <= s.l {
                em[i] = 0.0f64
                i += 1usize
            }
            var j = 1usize
            while j <= nqm1 {
                if j == nqm1 && s.nqwait == 1usize {
                    var sg = 1.0f64
                    var csum = 0.0f64
                    i = 1usize
                    while i <= nqm1 {
                        csum = csum + sg * em[i] / f64(i + 1usize)
                        sg = 0.0f64 - sg
                        i += 1usize
                    }
                    s.tq[1usize] = em[nqm1] / (flotnq * csum)
                }
                let rxi = s.h / hsum
                var iback = 1usize
                while iback <= j {
                    i = (j + 2usize) - iback
                    em[i] = em[i] + em[i - 1usize] * rxi
                    iback += 1usize
                }
                hsum = hsum + s.tau[j]
                j += 1usize
            }
            var sg = 1.0f64
            var em0 = 0.0f64
            var csum = 0.0f64
            i = 1usize
            while i <= s.nq {
                let floti = f64(i)
                em0 = em0 + sg * em[i] / floti
                csum = csum + sg * em[i] / (floti + 1.0f64)
                sg = 0.0f64 - sg
                i += 1usize
            }
            sg = 1.0f64 / em0
            s.el[1usize] = 1.0f64
            i = 1usize
            while i <= s.nq {
                s.el[i + 1usize] = sg * em[i] / f64(i)
                i += 1usize
            }
            let xi = hsum / s.h
            s.tq[2usize] = xi * em0 / csum
            s.tq[5usize] = xi / s.el[s.l]
            if s.nqwait == 1usize {
                let rxi = 1.0f64 / xi
                var iback = 1usize
                while iback <= s.nq {
                    i = (s.l + 1usize) - iback
                    em[i] = em[i] + em[i - 1usize] * rxi
                    iback += 1usize
                }
                sg = 1.0f64
                csum = 0.0f64
                i = 1usize
                while i <= s.l {
                    csum = csum + sg * em[i] / f64(i + 1usize)
                    sg = 0.0f64 - sg
                    i += 1usize
                }
                s.tq[3usize] = flotl * em0 / csum
            }
        }
    } else {
        var nqm2 = 0usize
        if s.nq >= 2usize { nqm2 = s.nq - 2usize }
        i = 3usize
        while i <= s.l {
            s.el[i] = 0.0f64
            i += 1usize
        }
        s.el[1usize] = 1.0f64
        s.el[2usize] = 1.0f64
        var alph0 = 0.0f64 - 1.0f64
        var ahatn0 = 0.0f64 - 1.0f64
        var hsum = s.h
        var rxi = 1.0f64
        var rxis = 1.0f64
        if s.nq != 1usize {
            var j = 1usize
            while j <= nqm2 {
                hsum = hsum + s.tau[j]
                rxi = s.h / hsum
                let jp1 = j + 1usize
                alph0 = alph0 - 1.0f64 / f64(jp1)
                var iback = 1usize
                while iback <= jp1 {
                    i = (j + 3usize) - iback
                    s.el[i] = s.el[i] + s.el[i - 1usize] * rxi
                    iback += 1usize
                }
                j += 1usize
            }
            alph0 = alph0 - 1.0f64 / f64(s.nq)
            rxis = (0.0f64 - s.el[2usize]) - alph0
            hsum = hsum + s.tau[nqm1]
            rxi = s.h / hsum
            ahatn0 = (0.0f64 - s.el[2usize]) - rxi
            var iback = 1usize
            while iback <= s.nq {
                i = (s.nq + 2usize) - iback
                s.el[i] = s.el[i] + s.el[i - 1usize] * rxis
                iback += 1usize
            }
        }
        let t1 = 1.0f64 - ahatn0 + alph0
        let t2 = 1.0f64 + f64(s.nq) * t1
        s.tq[2usize] = math.abs[f64](alph0 * t2 / t1)
        s.tq[5usize] = math.abs[f64](t2 / (s.el[s.l] * rxi / rxis))
        if s.nqwait == 1usize {
            let cnqm1 = rxis / s.el[s.l]
            let t3 = alph0 + 1.0f64 / f64(s.nq)
            let t4 = ahatn0 + rxi
            var elp = t3 / (1.0f64 - t4 + t3)
            s.tq[1usize] = math.abs[f64](elp / cnqm1)
            hsum = hsum + s.tau[s.nq]
            rxi = s.h / hsum
            let t5 = alph0 - 1.0f64 / f64(s.nq + 1usize)
            let t6 = ahatn0 - rxi
            elp = t2 / (1.0f64 - t6 + t5)
            s.tq[3usize] = math.abs[f64](elp * rxi * (flotl + 1.0f64) * t5)
        }
    }
    s.tq[4usize] = 0.1f64 * s.tq[2usize]
}

fn vo_just(s: *Vode, iord: i64) {
    let n = s.n
    if s.nq == 2usize && iord != 1i64 { ret }
    let nqm1 = s.nq - 1usize
    var nqm2 = 0usize
    if s.nq >= 2usize { nqm2 = s.nq - 2usize }
    var i = 0usize
    var j = 1usize
    if s.meth == 1usize {
        if iord == 1i64 {
            let lp1 = s.l + 1usize
            i = 0usize
            while i < n {
                s.yh[i + lp1 * n - n] = 0.0f64
                i += 1usize
            }
            ret
        }
        j = 1usize
        while j <= s.lmax {
            s.el[j] = 0.0f64
            j += 1usize
        }
        s.el[2usize] = 1.0f64
        var hsum = 0.0f64
        j = 1usize
        while j <= nqm2 {
            hsum = hsum + s.tau[j]
            let xi = hsum / s.hscal
            let jp1 = j + 1usize
            var iback = 1usize
            while iback <= jp1 {
                i = (j + 3usize) - iback
                s.el[i] = s.el[i] * xi + s.el[i - 1usize]
                iback += 1usize
            }
            j += 1usize
        }
        j = 2usize
        while j <= nqm1 {
            s.el[j + 1usize] = f64(s.nq) * s.el[j] / f64(j)
            j += 1usize
        }
        j = 3usize
        while j <= s.nq {
            i = 0usize
            while i < n {
                s.yh[i + (j - 1usize) * n] = s.yh[i + (j - 1usize) * n] - s.yh[i + (s.l - 1usize) * n] * s.el[j]
                i += 1usize
            }
            j += 1usize
        }
        ret
    }
    if iord != 1i64 {
        j = 1usize
        while j <= s.lmax {
            s.el[j] = 0.0f64
            j += 1usize
        }
        s.el[3usize] = 1.0f64
        var hsum = 0.0f64
        j = 1usize
        while j <= nqm2 {
            hsum = hsum + s.tau[j]
            let xi = hsum / s.hscal
            let jp1 = j + 1usize
            var iback = 1usize
            while iback <= jp1 {
                i = (j + 4usize) - iback
                s.el[i] = s.el[i] * xi + s.el[i - 1usize]
                iback += 1usize
            }
            j += 1usize
        }
        j = 3usize
        while j <= s.nq {
            i = 0usize
            while i < n {
                s.yh[i + (j - 1usize) * n] = s.yh[i + (j - 1usize) * n] - s.yh[i + (s.l - 1usize) * n] * s.el[j]
                i += 1usize
            }
            j += 1usize
        }
        ret
    }
    j = 1usize
    while j <= s.lmax {
        s.el[j] = 0.0f64
        j += 1usize
    }
    s.el[3usize] = 1.0f64
    var alph0 = 0.0f64 - 1.0f64
    var alph1 = 1.0f64
    var prod = 1.0f64
    var xiold = 1.0f64
    var hsum = s.hscal
    if s.nq != 1usize {
        j = 1usize
        while j <= nqm1 {
            let jp1 = j + 1usize
            hsum = hsum + s.tau[jp1]
            let xi = hsum / s.hscal
            prod = prod * xi
            alph0 = alph0 - 1.0f64 / f64(jp1)
            alph1 = alph1 + 1.0f64 / xi
            var iback = 1usize
            while iback <= jp1 {
                i = (j + 4usize) - iback
                s.el[i] = s.el[i] * xiold + s.el[i - 1usize]
                iback += 1usize
            }
            xiold = xi
            j += 1usize
        }
    }
    let t1 = ((0.0f64 - alph0) - alph1) / prod
    let lp1 = s.l + 1usize
    i = 0usize
    while i < n {
        s.yh[i + (lp1 - 1usize) * n] = t1 * s.yh[i + (s.lmax - 1usize) * n]
        i += 1usize
    }
    j = 3usize
    while j <= s.nq + 1usize {
        i = 0usize
        while i < n {
            s.yh[i + (j - 1usize) * n] = s.yh[i + (j - 1usize) * n] + s.el[j] * s.yh[i + (lp1 - 1usize) * n]
            i += 1usize
        }
        j += 1usize
    }
}

// DVJAC, miter = 2, jsv = 1: returns 0 or 1 (singular matrix).
fn vo_jac[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Vode) -> i64 {
    let n = s.n
    let hrl1 = s.h * s.rl1
    var jok = 1i64
    if s.nst == 0usize || s.nst > s.nslj + s.msbj { jok = 0i64 - 1i64 }
    if s.icf == 1i64 && s.drc < s.ccmxj { jok = 0i64 - 1i64 }
    if s.icf == 2i64 { jok = 0i64 - 1i64 }
    let lenp = n * n
    if jok == 0i64 - 1i64 {
        s.nje += 1usize
        s.nslj = s.nst
        s.jcur = 1usize
        var fac = ls_dvnorm(n, s.savf, s.ewt)
        var r0 = 1000.0f64 * math.abs[f64](s.h) * s.uround * f64(n) * fac
        if r0 == 0.0f64 { r0 = 1.0f64 }
        let srur = s.wm[0usize]
        var j = 0usize
        while j < n {
            let yj = s.y[j]
            let r = rk_fmax(srur * math.abs[f64](yj), r0 / s.ewt[j])
            s.y[j] = s.y[j] + r
            fac = 1.0f64 / r
            f(ctx, s.tn, s.y, s.acor)
            var i = 0usize
            while i < n {
                s.wm[2usize + i + j * n] = (s.acor[i] - s.savf[i]) * fac
                i += 1usize
            }
            s.y[j] = yj
            j += 1usize
        }
        s.nfe += n
        var z = 0usize
        while z < lenp {
            s.jsave[z] = s.wm[2usize + z]
            z += 1usize
        }
    } else {
        s.jcur = 0usize
        var z = 0usize
        while z < lenp {
            s.wm[2usize + z] = s.jsave[z]
            z += 1usize
        }
    }
    let con = 0.0f64 - hrl1
    var z = 0usize
    while z < lenp {
        s.wm[2usize + z] = s.wm[2usize + z] * con
        z += 1usize
    }
    var i = 0usize
    while i < n {
        s.wm[2usize + i + i * n] = s.wm[2usize + i + i * n] + 1.0f64
        i += 1usize
    }
    s.nlu += 1usize
    let info = ls_dgefa(s.wm[2usize..2usize + lenp], n, s.ipvt)
    if info != 0usize { ret 1i64 }
    ret 0i64
}

// DVNLSD: 0 converged, -1 failed (convergence), as nflag.
fn vo_nlsd[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Vode, nflag: i64) -> i64 {
    let n = s.n
    let ccmax = 0.3f64
    let crdown = 0.3f64
    let maxcor = 3usize
    let msbp = 20usize
    let rdiv = 2.0f64
    if s.jstart == 0i64 { s.nslp = 0usize }
    if nflag == 0i64 { s.icf = 0i64 }
    if nflag == 0i64 - 2i64 { s.ipup = s.miter }
    if s.jstart == 0i64 || s.jstart == 0i64 - 1i64 { s.ipup = s.miter }
    var lbl = 220usize
    if s.miter == 0usize {
        s.crate = 1.0f64
    } else {
        s.drc = math.abs[f64](s.rc - 1.0f64)
        if s.drc > ccmax || s.nst >= s.nslp + msbp { s.ipup = s.miter }
    }
    var m = 0usize
    var delp = 0.0f64
    var del = 0.0f64
    var i = 0usize
    while true {
        if lbl == 220usize {
            m = 0usize
            delp = 0.0f64
            i = 0usize
            while i < n {
                s.y[i] = s.yh[i]
                i += 1usize
            }
            f(ctx, s.tn, s.y, s.savf)
            s.nfe += 1usize
            lbl = 250usize
            if s.ipup > 0usize {
                let ierpj = vo_jac[Ctx](ctx, f, s)
                s.ipup = 0usize
                s.rc = 1.0f64
                s.drc = 0.0f64
                s.crate = 1.0f64
                s.nslp = s.nst
                if ierpj != 0i64 { lbl = 430usize }
            }
        }
        if lbl == 250usize {
            i = 0usize
            while i < n {
                s.acor[i] = 0.0f64
                i += 1usize
            }
            lbl = 270usize
        }
        if lbl == 270usize {
            if s.miter == 0usize {
                i = 0usize
                while i < n {
                    s.savf[i] = s.rl1 * (s.h * s.savf[i] - s.yh[n + i])
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    s.y[i] = s.savf[i] - s.acor[i]
                    i += 1usize
                }
                del = ls_dvnorm(n, s.y, s.ewt)
                i = 0usize
                while i < n {
                    s.y[i] = s.yh[i] + s.savf[i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    s.acor[i] = s.savf[i]
                    i += 1usize
                }
                lbl = 400usize
            } else {
                i = 0usize
                while i < n {
                    s.y[i] = (s.rl1 * s.h) * s.savf[i] - (s.rl1 * s.yh[n + i] + s.acor[i])
                    i += 1usize
                }
                ls_dgesl(s.wm[2usize..2usize + n * n], n, s.ipvt, s.y)
                s.nni += 1usize
                if s.meth == 2usize && s.rc != 1.0f64 {
                    let cscale = 2.0f64 / (1.0f64 + s.rc)
                    i = 0usize
                    while i < n {
                        s.y[i] = cscale * s.y[i]
                        i += 1usize
                    }
                }
                del = ls_dvnorm(n, s.y, s.ewt)
                i = 0usize
                while i < n {
                    s.acor[i] = s.acor[i] + s.y[i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    s.y[i] = s.yh[i] + s.acor[i]
                    i += 1usize
                }
                lbl = 400usize
            }
        }
        if lbl == 400usize {
            if m != 0usize { s.crate = rk_fmax(crdown * s.crate, del / delp) }
            let dcon = del * rk_fmin(1.0f64, s.crate) / s.tq[4usize]
            if dcon <= 1.0f64 {
                lbl = 450usize
            } else {
                m += 1usize
                if m == maxcor {
                    lbl = 410usize
                } else if m >= 2usize && del > rdiv * delp {
                    lbl = 410usize
                } else {
                    delp = del
                    f(ctx, s.tn, s.y, s.savf)
                    s.nfe += 1usize
                    lbl = 270usize
                }
            }
        }
        if lbl == 410usize {
            if s.miter == 0usize || s.jcur == 1usize {
                lbl = 430usize
            } else {
                s.icf = 1i64
                s.ipup = s.miter
                lbl = 220usize
            }
        }
        if lbl == 430usize {
            s.icf = 2i64
            s.ipup = s.miter
            ret 0i64 - 1i64
        }
        if lbl == 450usize {
            s.jcur = 0usize
            s.icf = 0i64
            if m == 0usize { s.acnrm = del }
            if m > 0usize { s.acnrm = ls_dvnorm(n, s.acor, s.ewt) }
            ret 0i64
        }
    }
    ret 0i64
}

fn vo_pascal(s: *Vode, sign: f64) {
    let n = s.n
    var jb = 1usize
    while jb <= s.nq {
        var c = s.nq - jb + 1usize
        while c <= s.nq {
            var i = 0usize
            while i < n {
                s.yh[i + (c - 1usize) * n] = s.yh[i + (c - 1usize) * n] + sign * s.yh[i + c * n]
                i += 1usize
            }
            c += 1usize
        }
        jb += 1usize
    }
}

// DVSTEP: one step; s.kflag 0 on success, negative on failure.
fn vo_step[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), s: *Vode) {
    let n = s.n
    let addon = 1.0e-6f64
    let bias1 = 6.0f64
    let bias2 = 6.0f64
    let bias3 = 10.0f64
    let etacf = 0.25f64
    let etamin = 0.1f64
    let etamxf = 0.2f64
    let etamx1 = 1.0e4f64
    let etamx2 = 10.0f64
    let etamx3 = 10.0f64
    let onepsm = 1.00001f64
    let thresh = 1.5f64
    s.kflag = 0i64
    let told = s.tn
    var ncf = 0usize
    s.jcur = 0usize
    var nflag = 0i64
    var etaq = 0.0f64
    var etaqm1 = 0.0f64
    var etaqp1 = 0.0f64
    var dsm = 0.0f64
    var lbl = 20usize
    if s.jstart <= 0i64 {
        s.lmax = s.maxord + 1usize
        s.nq = 1usize
        s.l = 2usize
        s.tau[1usize] = s.h
        s.prl1 = 1.0f64
        s.rc = 0.0f64
        s.etamax = etamx1
        s.nqwait = 2usize
        s.hscal = s.h
        lbl = 200usize
    }
    var i = 0usize
    while true {
        if lbl == 20usize {
            if s.kuth == 1usize {
                s.eta = rk_fmin(s.eta, s.h / s.hscal)
                s.newh = 1usize
            }
            lbl = 50usize
        }
        if lbl == 50usize {
            if s.newh == 0usize {
                lbl = 200usize
            } else if s.newq == s.nq {
                lbl = 150usize
            } else if s.newq < s.nq {
                vo_just(s, 0i64 - 1i64)
                s.nq = s.newq
                s.l = s.nq + 1usize
                s.nqwait = s.l
                lbl = 150usize
            } else {
                vo_just(s, 1i64)
                s.nq = s.newq
                s.l = s.nq + 1usize
                s.nqwait = s.l
                lbl = 150usize
            }
        }
        if lbl == 150usize {
            var r = 1.0f64
            var j = 2usize
            while j <= s.l {
                r = r * s.eta
                i = 0usize
                while i < n {
                    s.yh[i + (j - 1usize) * n] = r * s.yh[i + (j - 1usize) * n]
                    i += 1usize
                }
                j += 1usize
            }
            s.h = s.hscal * s.eta
            s.hscal = s.h
            s.rc = s.rc * s.eta
            lbl = 200usize
        }
        if lbl == 200usize {
            s.tn = s.tn + s.h
            vo_pascal(s, 1.0f64)
            vo_set(s)
            s.rl1 = 1.0f64 / s.el[2usize]
            s.rc = s.rc * (s.rl1 / s.prl1)
            s.prl1 = s.rl1
            nflag = vo_nlsd[Ctx](ctx, f, s, nflag)
            if nflag == 0i64 {
                lbl = 450usize
            } else {
                ncf += 1usize
                s.etamax = 1.0f64
                s.tn = told
                vo_pascal(s, 0.0f64 - 1.0f64)
                if nflag < 0i64 - 1i64 {
                    lbl = 680usize
                } else if math.abs[f64](s.h) <= s.hmin * onepsm {
                    lbl = 670usize
                } else if ncf == 10usize {
                    lbl = 670usize
                } else {
                    s.eta = etacf
                    s.eta = rk_fmax(s.eta, s.hmin / math.abs[f64](s.h))
                    nflag = 0i64 - 1i64
                    lbl = 150usize
                }
            }
        }
        if lbl == 450usize {
            dsm = s.acnrm / s.tq[2usize]
            if dsm > 1.0f64 {
                lbl = 500usize
            } else {
                s.kflag = 0i64
                s.nst += 1usize
                s.hu = s.h
                var iback = 1usize
                while iback <= s.nq {
                    let ii = s.l - iback
                    s.tau[ii + 1usize] = s.tau[ii]
                    iback += 1usize
                }
                s.tau[1usize] = s.h
                var j = 1usize
                while j <= s.l {
                    i = 0usize
                    while i < n {
                        s.yh[i + (j - 1usize) * n] = s.yh[i + (j - 1usize) * n] + s.el[j] * s.acor[i]
                        i += 1usize
                    }
                    j += 1usize
                }
                s.nqwait -= 1usize
                if !(s.l == s.lmax || s.nqwait != 1usize) {
                    i = 0usize
                    while i < n {
                        s.yh[i + (s.lmax - 1usize) * n] = s.acor[i]
                        i += 1usize
                    }
                    s.conp = s.tq[5usize]
                }
                if s.etamax != 1.0f64 {
                    lbl = 560usize
                } else {
                    if s.nqwait < 2usize { s.nqwait = 2usize }
                    s.newq = s.nq
                    s.newh = 0usize
                    s.eta = 1.0f64
                    s.hnew = s.h
                    lbl = 690usize
                }
            }
        }
        if lbl == 500usize {
            s.kflag -= 1i64
            nflag = 0i64 - 2i64
            s.tn = told
            vo_pascal(s, 0.0f64 - 1.0f64)
            if math.abs[f64](s.h) <= s.hmin * onepsm {
                lbl = 660usize
            } else {
                s.etamax = 1.0f64
                if s.kflag <= 0i64 - 3i64 {
                    lbl = 530usize
                } else {
                    let flotl = f64(s.l)
                    s.eta = 1.0f64 / (dd_pow(bias2 * dsm, 1.0f64 / flotl) + addon)
                    s.eta = rk_fmax(rk_fmax(s.eta, s.hmin / math.abs[f64](s.h)), etamin)
                    if s.kflag <= 0i64 - 2i64 && s.eta > etamxf { s.eta = etamxf }
                    lbl = 150usize
                }
            }
        }
        if lbl == 530usize {
            if s.kflag == 0i64 - 7i64 {
                lbl = 660usize
            } else if s.nq == 1usize {
                lbl = 540usize
            } else {
                s.eta = rk_fmax(etamin, s.hmin / math.abs[f64](s.h))
                vo_just(s, 0i64 - 1i64)
                s.l = s.nq
                s.nq = s.nq - 1usize
                s.nqwait = s.l
                lbl = 150usize
            }
        }
        if lbl == 540usize {
            s.eta = rk_fmax(etamin, s.hmin / math.abs[f64](s.h))
            s.h = s.h * s.eta
            s.hscal = s.h
            s.tau[1usize] = s.h
            f(ctx, s.tn, s.y, s.savf)
            s.nfe += 1usize
            i = 0usize
            while i < n {
                s.yh[n + i] = s.h * s.savf[i]
                i += 1usize
            }
            s.nqwait = 10usize
            lbl = 200usize
        }
        if lbl == 560usize {
            let flotl = f64(s.l)
            etaq = 1.0f64 / (dd_pow(bias2 * dsm, 1.0f64 / flotl) + addon)
            lbl = 600usize
            if s.nqwait == 0usize {
                s.nqwait = 2usize
                etaqm1 = 0.0f64
                if s.nq != 1usize {
                    let ddn = ls_dvnorm(n, s.yh[(s.l - 1usize) * n..s.l * n], s.ewt) / s.tq[1usize]
                    etaqm1 = 1.0f64 / (dd_pow(bias1 * ddn, 1.0f64 / (flotl - 1.0f64)) + addon)
                }
                etaqp1 = 0.0f64
                if s.l != s.lmax {
                    let cnquot = (s.tq[5usize] / s.conp) * rad_powi(s.h / s.tau[2usize], s.l)
                    i = 0usize
                    while i < n {
                        s.savf[i] = s.acor[i] - cnquot * s.yh[i + (s.lmax - 1usize) * n]
                        i += 1usize
                    }
                    let dup = ls_dvnorm(n, s.savf, s.ewt) / s.tq[3usize]
                    etaqp1 = 1.0f64 / (dd_pow(bias3 * dup, 1.0f64 / (flotl + 1.0f64)) + addon)
                }
                if etaq >= etaqp1 {
                    if etaq < etaqm1 { lbl = 610usize }
                } else if etaqp1 > etaqm1 {
                    lbl = 620usize
                } else {
                    lbl = 610usize
                }
            }
        }
        if lbl == 600usize {
            s.eta = etaq
            s.newq = s.nq
            lbl = 630usize
        }
        if lbl == 610usize {
            s.eta = etaqm1
            s.newq = s.nq - 1usize
            lbl = 630usize
        }
        if lbl == 620usize {
            s.eta = etaqp1
            s.newq = s.nq + 1usize
            i = 0usize
            while i < n {
                s.yh[i + (s.lmax - 1usize) * n] = s.acor[i]
                i += 1usize
            }
            lbl = 630usize
        }
        if lbl == 630usize {
            if s.eta < thresh || s.etamax == 1.0f64 {
                s.newq = s.nq
                s.newh = 0usize
                s.eta = 1.0f64
                s.hnew = s.h
            } else {
                s.eta = rk_fmin(s.eta, s.etamax)
                s.eta = s.eta / rk_fmax(1.0f64, math.abs[f64](s.h) * s.hmxi * s.eta)
                s.newh = 1usize
                s.hnew = s.h * s.eta
            }
            lbl = 690usize
        }
        if lbl == 660usize {
            s.kflag = 0i64 - 1i64
            lbl = 720usize
        }
        if lbl == 670usize {
            s.kflag = 0i64 - 2i64
            lbl = 720usize
        }
        if lbl == 680usize {
            if nflag == 0i64 - 2i64 { s.kflag = 0i64 - 3i64 }
            if nflag == 0i64 - 3i64 { s.kflag = 0i64 - 4i64 }
            lbl = 720usize
        }
        if lbl == 690usize {
            s.etamax = etamx3
            if s.nst <= 10usize { s.etamax = etamx2 }
            let r = 1.0f64 / s.tq[2usize]
            i = 0usize
            while i < n {
                s.acor[i] = r * s.acor[i]
                i += 1usize
            }
            lbl = 720usize
        }
        if lbl == 720usize {
            s.jstart = 1i64
            ret
        }
    }
}

// Integrate over `times` (itask 1: step past each output time, interpolate). `out` is nt x (n + 1)
// column-major. maxsteps is per output interval. hmax_in <= 0: largest gap of `times`.
// DVODE itask 4 helper after a step short of tout: true when tcrit is reached (T = tcrit); otherwise
// shrinks H to land on tcrit when the next step would pass it.
fn vo_hit(s: *Vode, tcrit: f64) -> bool {
    let hmx = math.abs[f64](s.tn) + math.abs[f64](s.h)
    if math.abs[f64](s.tn - tcrit) <= 100.0f64 * s.uround * hmx { ret true }
    let tnext = s.tn + s.hnew * (1.0f64 + 4.0f64 * s.uround)
    if (tnext - tcrit) * s.h > 0.0f64 {
        s.h = (tcrit - s.tn) * (1.0f64 - 4.0f64 * s.uround)
        s.kuth = 1usize
    }
    ret false
}

fn vo_run[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, adams: bool, maxord_in: usize, evt: []const f64, evf: fn(*Ctx, f64, []f64), out: []f64) -> err {
    let n = y0.len
    let nt = times.len
    if nt < 2usize || n == 0usize || out.len < nt * (n + 1usize) { ret Invalid }
    var s: Vode = zero
    let (blk, be) = mem.alloc[f64](a, 13usize * n + 5usize * n + 2usize * n * n + 4usize)
    if be != ok { ret be }
    let (piv, pe) = mem.alloc[usize](a, n)
    if pe != ok { ret pe }
    var z = 0usize
    while z < blk.len {
        blk[z] = 0.0f64
        z += 1usize
    }
    var at = 0usize
    s.yh = blk[at..at + 13usize * n]
    at += 13usize * n
    s.ewt = blk[at..at + n]
    at += n
    s.savf = blk[at..at + n]
    at += n
    s.acor = blk[at..at + n]
    at += n
    s.y = blk[at..at + n]
    at += n
    s.wm = blk[at..at + n * n + 2usize]
    at += n * n + 2usize
    s.jsave = blk[at..at + n * n]
    s.ipvt = piv[0usize..n]
    s.n = n
    s.rtol = rtol
    s.atol = atol
    s.uround = 2.220446049250313e-16f64
    s.meth = 2usize
    s.miter = 2usize
    s.maxord = 5usize
    if adams {
        s.meth = 1usize
        s.miter = 0usize
        s.maxord = 12usize
    }
    if maxord_in > 0usize && maxord_in < s.maxord { s.maxord = maxord_in }
    s.mxstep = maxsteps
    s.hmin = hmin
    var hmax = hmax_in
    if hmax <= 0.0f64 {
        var k = 1usize
        while k < nt {
            hmax = rk_fmax(hmax, math.abs[f64](times[k] - times[k - 1usize]))
            k += 1usize
        }
    }
    s.hmxi = 0.0f64
    if hmax > 0.0f64 { s.hmxi = 1.0f64 / hmax }
    s.msbj = 50usize
    s.ccmxj = 0.2f64
    var i = 0usize
    out[0usize] = times[0usize]
    while i < n {
        out[(i + 1usize) * nt] = y0[i]
        i += 1usize
    }
    var yv: [64]f64 = zero
    if n > 64usize { ret TooSmall }
    i = 0usize
    while i < n {
        yv[i] = y0[i]
        i += 1usize
    }
    var it = 0usize
    var first = true
    var iev = 0usize
    while it + 1usize < nt {
        var tcrit = times[nt - 1usize]
        if evt.len > 0usize {
            if iev < evt.len && evt[iev] == times[it] {
                evf(ctx, times[it], yv[0usize..n])
                iev += 1usize
                first = true
            }
            if iev < evt.len && evt[iev] > times[it + 1usize] { tcrit = evt[iev] }
        }
        let tout = times[it + 1usize]
        let itask4 = evt.len > 0usize
        var tcur = times[it]
        var reps = 0usize
        while true {
            let tin = tcur
            if first && tout == tin { break }
            var nslast = s.nst
            var pre = false
            if first {
                // istate = 1
                if itask4 && (tcrit - tout) * (tout - tin) < 0.0f64 { ret Invalid }
                s.tn = tin
                if s.miter > 0usize { s.wm[0usize] = math.sqrt[f64](s.uround) }
                s.jstart = 0i64
                s.nst = 0usize
                nslast = 0usize
                s.hu = 0.0f64
                f(ctx, tin, yv[0usize..n], s.yh[n..2usize * n])
                s.nfe = 1usize
                i = 0usize
                while i < n {
                    s.yh[i] = yv[i]
                    i += 1usize
                }
                s.nq = 1usize
                s.h = 1.0f64
                vo_dewset(&s)
                if !vo_ewt_invert(&s) { ret Invalid }
                var h0 = hini
                if itask4 && h0 != 0.0f64 && (tin + h0 - tcrit) * h0 > 0.0f64 { h0 = tcrit - tin }
                if h0 == 0.0f64 {
                    if vo_hin[Ctx](ctx, f, &s, tout, tin) != 0i64 { ret Invalid }
                    s.nfe += s.niter
                    h0 = s.h0
                }
                let rh = math.abs[f64](h0) * s.hmxi
                if rh > 1.0f64 { h0 = h0 / rh }
                s.h = h0
                i = 0usize
                while i < n {
                    s.yh[n + i] = h0 * s.yh[n + i]
                    i += 1usize
                }
                first = false
                pre = true
            } else {
                nslast = s.nst
                s.kuth = 0usize
            }
            var stepping = true
            if !pre {
                if itask4 {
                    if (s.tn - tcrit) * s.h > 0.0f64 { ret Invalid }
                    if (tcrit - tout) * s.h < 0.0f64 { ret Invalid }
                    if (s.tn - tout) * s.h >= 0.0f64 {
                        if vo_indy0(&s, tout, yv[0usize..n]) != 0i64 { ret Invalid }
                        tcur = tout
                        stepping = false
                    } else if vo_hit(&s, tcrit) {
                        i = 0usize
                        while i < n {
                            yv[i] = s.yh[i]
                            i += 1usize
                        }
                        tcur = tcrit
                        stepping = false
                    }
                } else if (s.tn - tout) * s.h >= 0.0f64 {
                    if vo_indy0(&s, tout, yv[0usize..n]) != 0i64 { ret Invalid }
                    tcur = tout
                    stepping = false
                }
            }
            while stepping {
                if !pre {
                    if s.nst - nslast >= s.mxstep { ret Invalid }
                    vo_dewset(&s)
                    if !vo_ewt_invert(&s) { ret Invalid }
                }
                pre = false
                let tolsf = s.uround * ls_dvnorm(n, s.yh[0usize..n], s.ewt)
                if tolsf > 1.0f64 { ret Invalid }
                vo_step[Ctx](ctx, f, &s)
                if s.kflag != 0i64 { ret Invalid }
                s.kuth = 0usize
                if (s.tn - tout) * s.h >= 0.0f64 {
                    let _ = vo_indy0(&s, tout, yv[0usize..n])
                    tcur = tout
                    stepping = false
                } else if itask4 {
                    if vo_hit(&s, tcrit) {
                        i = 0usize
                        while i < n {
                            yv[i] = s.yh[i]
                            i += 1usize
                        }
                        tcur = tcrit
                        stepping = false
                    }
                }
            }
            reps += 1usize
            if !(tcur < tout && reps < 10usize) { break }
        }
        if tcur < tout { ret Invalid }
        out[it + 1usize] = tout
        i = 0usize
        while i < n {
            out[it + 1usize + nt * (1usize + i)] = yv[i]
            i += 1usize
        }
        it += 1usize
    }
    ret ok
}

fn vode_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, adams: bool, maxord_in: usize, out: []f64) -> err {
    let evt: []const f64 = times[0usize..0usize]
    ret vo_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, adams, maxord_in, evt, ev_none[Ctx], out)
}

// vode with time events (deSolve events = list(func, time)): same contract as lsoda_event_solve.
fn vode_event_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), times: []const f64, y0: []const f64, rtol: f64, atol: f64, hmin: f64, hmax_in: f64, hini: f64, maxsteps: usize, adams: bool, maxord_in: usize, evt: []const f64, evf: fn(*Ctx, f64, []f64), out: []f64) -> err {
    ret vo_run[Ctx](a, ctx, f, times, y0, rtol, atol, hmin, hmax_in, hini, maxsteps, adams, maxord_in, evt, evf, out)
}

// ---- deSolve daspk(y0, dy0, times, res): DASPK 2.0 (Brown, Hindmarsh, Petzold) with the direct dense
// method (info(12) = 0, internal finite-difference Jacobian, info(5) = 0), scalar tolerances, a
// consistent (y0, dy0) as input (estini = NULL), nind = (n, 0, 0) and no tstop. The residual is
// F(t, y, y') = 0 written into `delta`; an index-1 DAE is any F with a singular d F / d y'.
// A port of ddaspk.f (DDASPK, DDSTP, DNEDD, DNSD, DMATD, DSLVD, DDAWTS, DINVWT, DDATRP, DDWNRM).
// vectors alpha, beta, gamma, psi, sigma are indexed from 1; phi(i, j) is phi[i + (j - 1) * n].

type Daspk = struct {
    n: usize, maxord: usize, x: f64, h: f64, hold: f64, cj: f64, cjold: f64, sv: f64, hmin: f64, uround: f64,
    k: usize, kold: usize, ns: usize, iphase: usize, jstart: i64, jcalc: i64, idid: i64, nst: usize,
    alpha: [8]f64, beta: [8]f64, gamma: [8]f64, psi: [8]f64, sigma: [8]f64,
    phi: []f64, wt: []f64, delta: []f64, e: []f64, y: []f64, yp: []f64, wm: []f64, ipvt: []usize
}

fn dp_wnrm(n: usize, v: []const f64, rwt: []const f64) -> f64 {
    var vmax = 0.0f64
    var i = 0usize
    while i < n {
        if math.abs[f64](v[i] * rwt[i]) > vmax { vmax = math.abs[f64](v[i] * rwt[i]) }
        i += 1usize
    }
    if vmax <= 0.0f64 { ret 0.0f64 }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        let q = (v[i] * rwt[i]) / vmax
        sum = sum + q * q
        i += 1usize
    }
    ret vmax * math.sqrt[f64](sum / f64(n))
}

// DDAWTS + DINVWT: false when a weight is not positive.
fn dp_weights(s: *Daspk, rtol: f64, atol: f64, y: []const f64) -> bool {
    var i = 0usize
    while i < s.n {
        s.wt[i] = rtol * math.abs[f64](y[i]) + atol
        i += 1usize
    }
    i = 0usize
    while i < s.n {
        if s.wt[i] <= 0.0f64 { ret false }
        i += 1usize
    }
    i = 0usize
    while i < s.n {
        s.wt[i] = 1.0f64 / s.wt[i]
        i += 1usize
    }
    ret true
}

// DDATRP: values and derivatives at xout from the Nordsieck-like history.
fn dp_trp(s: *Daspk, x: f64, xout: f64, kold: usize, yout: []f64, ypout: []f64) {
    let n = s.n
    let temp1 = xout - x
    var i = 0usize
    while i < n {
        yout[i] = s.phi[i]
        ypout[i] = 0.0f64
        i += 1usize
    }
    var c = 1.0f64
    var d = 0.0f64
    var gamma = temp1 / s.psi[1usize]
    var j = 2usize
    while j <= kold + 1usize {
        d = d * gamma + c / s.psi[j - 1usize]
        c = c * gamma
        gamma = (temp1 + s.psi[j - 1usize]) / s.psi[j]
        i = 0usize
        while i < n {
            yout[i] = yout[i] + c * s.phi[i + (j - 1usize) * n]
            ypout[i] = ypout[i] + d * s.phi[i + (j - 1usize) * n]
            i += 1usize
        }
        j += 1usize
    }
}

// DNSD: modified Newton iteration; 0 converged, 1 failed.
fn dp_nsd[Ctx: type](ctx: *Ctx, res: fn(*Ctx, f64, []const f64, []const f64, []f64), s: *Daspk, confac: f64, tolnew: f64) -> i64 {
    let n = s.n
    let epcon = 0.33f64
    var m = 0usize
    var i = 0usize
    var oldnrm = 0.0f64
    while i < n {
        s.e[i] = 0.0f64
        i += 1usize
    }
    while true {
        i = 0usize
        while i < n {
            s.delta[i] = s.delta[i] * confac
            i += 1usize
        }
        ls_dgesl(s.wm[0usize..n * n], n, s.ipvt, s.delta)
        i = 0usize
        while i < n {
            s.y[i] = s.y[i] - s.delta[i]
            s.e[i] = s.e[i] - s.delta[i]
            s.yp[i] = s.yp[i] - s.cj * s.delta[i]
            i += 1usize
        }
        let delnrm = dp_wnrm(n, s.delta, s.wt)
        if delnrm <= tolnew { ret 0i64 }
        if m == 0usize {
            oldnrm = delnrm
        } else {
            let rate = dd_pow(delnrm / oldnrm, 1.0f64 / f64(m))
            if rate > 0.9f64 { ret 1i64 }
            s.sv = rate / (1.0f64 - rate)
        }
        if s.sv * delnrm <= epcon { ret 0i64 }
        m += 1usize
        if m >= 4usize { ret 1i64 }
        res(ctx, s.x, s.y, s.yp, s.delta)
    }
    ret 1i64
}

// DMATD (mtype 2): finite-difference iteration matrix, LU factored in s.wm; nonzero when singular.
fn dp_matd[Ctx: type](ctx: *Ctx, res: fn(*Ctx, f64, []const f64, []const f64, []f64), s: *Daspk) -> usize {
    let n = s.n
    let squr = math.sqrt[f64](s.uround)
    var i = 0usize
    while i < n {
        var del = squr * rk_fmax(rk_fmax(math.abs[f64](s.y[i]), math.abs[f64](s.h * s.yp[i])), math.abs[f64](1.0f64 / s.wt[i]))
        del = ls_sign(del, s.h * s.yp[i])
        del = (s.y[i] + del) - s.y[i]
        let ysave = s.y[i]
        let ypsave = s.yp[i]
        s.y[i] = s.y[i] + del
        s.yp[i] = s.yp[i] + s.cj * del
        res(ctx, s.x, s.y, s.yp, s.e)
        let delinv = 1.0f64 / del
        var l = 0usize
        while l < n {
            s.wm[i * n + l] = (s.e[l] - s.delta[l]) * delinv
            l += 1usize
        }
        s.y[i] = ysave
        s.yp[i] = ypsave
        i += 1usize
    }
    ret ls_dgefa(s.wm[0usize..n * n], n, s.ipvt)
}

// DNEDD (nonnegativity off): 0 success, 1 failure (s.idid set as in DASPK).
fn dp_nedd[Ctx: type](ctx: *Ctx, res: fn(*Ctx, f64, []const f64, []const f64, []f64), s: *Daspk, kp1: usize, cjlast: f64) -> i64 {
    let n = s.n
    if s.jstart == 0i64 {
        s.cjold = s.cj
        s.jcalc = 0i64 - 1i64
    }
    let temp1 = (1.0f64 - 0.25f64) / (1.0f64 + 0.25f64)
    let temp2 = 1.0f64 / temp1
    if s.cj / s.cjold < temp1 || s.cj / s.cjold > temp2 { s.jcalc = 0i64 - 1i64 }
    if s.cj != cjlast { s.sv = 100.0f64 }
    var iernls = 0i64
    var go = true
    while go {
        go = false
        var ierj = 0usize
        var fail = false
        var i = 0usize
        while i < n {
            s.y[i] = s.phi[i]
            s.yp[i] = 0.0f64
            i += 1usize
        }
        var j = 2usize
        while j <= kp1 {
            i = 0usize
            while i < n {
                s.y[i] = s.y[i] + s.phi[i + (j - 1usize) * n]
                s.yp[i] = s.yp[i] + s.gamma[j] * s.phi[i + (j - 1usize) * n]
                i += 1usize
            }
            j += 1usize
        }
        let pnorm = dp_wnrm(n, s.y, s.wt)
        let tolnew = 100.0f64 * s.uround * pnorm
        res(ctx, s.x, s.y, s.yp, s.delta)
        if s.jcalc == 0i64 - 1i64 {
            s.jcalc = 0i64
            ierj = dp_matd[Ctx](ctx, res, s)
            s.cjold = s.cj
            s.sv = 100.0f64
            if ierj != 0usize { fail = true }
        }
        if !fail {
            let confac = 2.0f64 / (1.0f64 + s.cj / s.cjold)
            let iernew = dp_nsd[Ctx](ctx, res, s, confac, tolnew)
            if iernew > 0i64 && s.jcalc != 0i64 {
                s.jcalc = 0i64 - 1i64
                go = true
            } else if iernew != 0i64 {
                fail = true
            }
        }
        if fail {
            iernls = 1i64
            if ierj != 0usize { s.idid = 0i64 - 8i64 }
        }
    }
    s.jcalc = 1i64
    ret iernls
}

// DDSTP: one step of size s.h (changed on return); s.idid < 0 on failure.
fn dp_step[Ctx: type](ctx: *Ctx, res: fn(*Ctx, f64, []const f64, []const f64, []f64), s: *Daspk) {
    let n = s.n
    let xold = s.x
    var ncf = 0usize
    var nef = 0usize
    var knew = 1usize
    var erkm1 = 1.0f64
    var terkm1 = 0.0f64
    var est = 0.0f64
    var r = 0.0f64
    if s.jstart == 0i64 {
        s.k = 1usize
        s.kold = 0usize
        s.hold = 0.0f64
        s.psi[1usize] = s.h
        s.cj = 1.0f64 / s.h
        s.iphase = 0usize
        s.ns = 0usize
    }
    var i = 0usize
    while true {
        let kp1 = s.k + 1usize
        let kp2 = s.k + 2usize
        let km1 = s.k - 1usize
        if s.h != s.hold || s.k != s.kold { s.ns = 0usize }
        s.ns = rk_min_us(s.ns + 1usize, s.kold + 2usize)
        let nsp1 = s.ns + 1usize
        if kp1 >= s.ns {
            s.beta[1usize] = 1.0f64
            s.alpha[1usize] = 1.0f64
            var temp1 = s.h
            s.gamma[1usize] = 0.0f64
            s.sigma[1usize] = 1.0f64
            var q = 2usize
            while q <= kp1 {
                let temp2 = s.psi[q - 1usize]
                s.psi[q - 1usize] = temp1
                s.beta[q] = s.beta[q - 1usize] * s.psi[q - 1usize] / temp2
                temp1 = temp2 + s.h
                s.alpha[q] = s.h / temp1
                s.sigma[q] = f64(q - 1usize) * s.sigma[q - 1usize] * s.alpha[q]
                s.gamma[q] = s.gamma[q - 1usize] + s.alpha[q - 1usize] / s.h
                q += 1usize
            }
            s.psi[kp1] = temp1
        }
        var alphas = 0.0f64
        var alpha0 = 0.0f64
        var q = 1usize
        while q <= s.k {
            alphas = alphas - 1.0f64 / f64(q)
            alpha0 = alpha0 - s.alpha[q]
            q += 1usize
        }
        let cjlast = s.cj
        s.cj = (0.0f64 - alphas) / s.h
        var ck = math.abs[f64](s.alpha[kp1] + alphas - alpha0)
        ck = rk_fmax(ck, s.alpha[kp1])
        if kp1 >= nsp1 {
            var j = nsp1
            while j <= kp1 {
                i = 0usize
                while i < n {
                    s.phi[i + (j - 1usize) * n] = s.beta[j] * s.phi[i + (j - 1usize) * n]
                    i += 1usize
                }
                j += 1usize
            }
        }
        s.x = s.x + s.h
        s.idid = 1i64
        let iernls = dp_nedd[Ctx](ctx, res, s, kp1, cjlast)
        var failed = iernls != 0i64
        var iepoch = 0usize
        if !failed {
            let enorm = dp_wnrm(n, s.e, s.wt)
            let erk = s.sigma[s.k + 1usize] * enorm
            let terk = f64(s.k + 1usize) * erk
            est = erk
            knew = s.k
            var lower = false
            if s.k != 1usize {
                i = 0usize
                while i < n {
                    s.delta[i] = s.phi[i + (kp1 - 1usize) * n] + s.e[i]
                    i += 1usize
                }
                erkm1 = s.sigma[s.k] * dp_wnrm(n, s.delta, s.wt)
                terkm1 = f64(s.k) * erkm1
                if s.k <= 2usize {
                    if terkm1 <= 0.5f64 * terk { lower = true }
                } else {
                    i = 0usize
                    while i < n {
                        s.delta[i] = s.phi[i + (s.k - 1usize) * n] + s.delta[i]
                        i += 1usize
                    }
                    let erkm2 = s.sigma[s.k - 1usize] * dp_wnrm(n, s.delta, s.wt)
                    let terkm2 = f64(s.k - 1usize) * erkm2
                    if !(rk_fmax(terkm1, terkm2) > terk) { lower = true }
                }
            }
            if lower {
                knew = s.k - 1usize
                est = erkm1
            }
            let errv = ck * enorm
            if errv > 1.0f64 {
                failed = true
            } else {
                s.idid = 1i64
                s.nst += 1usize
                var kdiff1 = false
                if s.k == s.kold + 1usize { kdiff1 = true }
                s.kold = s.k
                s.hold = s.h
                if knew == km1 || s.k == s.maxord { s.iphase = 1usize }
                var dir = 0usize
                var hset = true
                if s.iphase == 0usize {
                    s.k = kp1
                    s.h = s.h * 2.0f64
                    hset = false
                } else if knew == km1 {
                    dir = 1usize
                } else if s.k == s.maxord {
                    dir = 0usize
                } else if kp1 >= s.ns || kdiff1 {
                    dir = 0usize
                } else {
                    i = 0usize
                    while i < n {
                        s.delta[i] = s.e[i] - s.phi[i + (kp2 - 1usize) * n]
                        i += 1usize
                    }
                    let erkp1 = (1.0f64 / f64(s.k + 2usize)) * dp_wnrm(n, s.delta, s.wt)
                    let terkp1 = f64(s.k + 2usize) * erkp1
                    if s.k > 1usize {
                        if terkm1 <= rk_fmin(terk, terkp1) {
                            dir = 1usize
                        } else if terkp1 >= terk || s.k == s.maxord {
                            dir = 0usize
                        } else {
                            dir = 2usize
                            est = erkp1
                        }
                    } else if terkp1 >= 0.5f64 * terk {
                        dir = 0usize
                    } else {
                        dir = 2usize
                        est = erkp1
                    }
                }
                if dir == 1usize {
                    s.k = km1
                    est = erkm1
                }
                if dir == 2usize { s.k = kp1 }
                if hset {
                    var hnew = s.h
                    let temp2 = f64(s.k + 1usize)
                    r = dd_pow(2.0f64 * est + 0.0001f64, (0.0f64 - 1.0f64) / temp2)
                    if r >= 2.0f64 {
                        hnew = 2.0f64 * s.h
                    } else if !(r > 1.0f64) {
                        r = rk_fmax(0.5f64, rk_fmin(0.9f64, r))
                        hnew = s.h * r
                    }
                    s.h = hnew
                }
                if s.kold != s.maxord {
                    i = 0usize
                    while i < n {
                        s.phi[i + (kp2 - 1usize) * n] = s.e[i]
                        i += 1usize
                    }
                }
                i = 0usize
                while i < n {
                    s.phi[i + (kp1 - 1usize) * n] = s.phi[i + (kp1 - 1usize) * n] + s.e[i]
                    i += 1usize
                }
                var j1 = 2usize
                while j1 <= kp1 {
                    let j = kp1 - j1 + 1usize
                    i = 0usize
                    while i < n {
                        s.phi[i + (j - 1usize) * n] = s.phi[i + (j - 1usize) * n] + s.phi[i + j * n]
                        i += 1usize
                    }
                    j1 += 1usize
                }
                s.jstart = 1i64
                ret
            }
        }
        // 600: failed step
        s.iphase = 1usize
        s.x = xold
        if kp1 >= nsp1 {
            var j = nsp1
            while j <= kp1 {
                let temp1 = 1.0f64 / s.beta[j]
                i = 0usize
                while i < n {
                    s.phi[i + (j - 1usize) * n] = temp1 * s.phi[i + (j - 1usize) * n]
                    i += 1usize
                }
                j += 1usize
            }
        }
        var qq = 2usize
        while qq <= kp1 {
            s.psi[qq - 1usize] = s.psi[qq] - s.h
            qq += 1usize
        }
        var retry = false
        if iernls != 0i64 {
            ncf += 1usize
            r = 0.25f64
            s.h = s.h * r
            if ncf < 10usize && math.abs[f64](s.h) >= s.hmin {
                retry = true
            } else {
                if s.idid == 1i64 { s.idid = 0i64 - 7i64 }
                if nef >= 3usize { s.idid = 0i64 - 9i64 }
            }
        } else {
            nef += 1usize
            if nef == 1usize {
                s.k = knew
                let temp2 = f64(s.k + 1usize)
                r = 0.9f64 * dd_pow(2.0f64 * est + 0.0001f64, (0.0f64 - 1.0f64) / temp2)
                r = rk_fmax(0.25f64, rk_fmin(0.9f64, r))
                s.h = s.h * r
            } else if nef == 2usize {
                s.k = knew
                r = 0.25f64
                s.h = r * s.h
            } else {
                s.k = 1usize
                r = 0.25f64
                s.h = r * s.h
            }
            if math.abs[f64](s.h) >= s.hmin {
                retry = true
            } else {
                s.idid = 0i64 - 6i64
            }
        }
        if !retry {
            dp_trp(s, s.x, s.x, s.k, s.y, s.yp)
            s.jstart = 1i64
            if s.idid >= 0i64 { s.idid = 0i64 - 7i64 }
            ret
        }
        if s.kold == 0usize {
            s.psi[1usize] = s.h
            i = 0usize
            while i < n {
                s.phi[i + n] = r * s.phi[i + n]
                i += 1usize
            }
        }
        iepoch += 1usize
    }
}

fn rk_min_us(a: usize, b: usize) -> usize {
    if a < b { ret a }
    ret b
}

// Integrate over `times` from the consistent state (y0, dy0). `out` is nt x (n + 1) column-major;
// maxsteps is per output interval (DASPK itself counts 500 steps per call; intervals needing more are
// not covered). hmax_in <= 0: largest gap of `times`; hini 0: DASPK's own first step. maxord <= 0: 5.
fn daspk_solve[Ctx: type](a: *mem.Arena, ctx: *Ctx, res: fn(*Ctx, f64, []const f64, []const f64, []f64), times: []const f64, y0: []const f64, dy0: []const f64, rtol: f64, atol: f64, hmax_in: f64, hini: f64, maxord_in: usize, maxsteps: usize, out: []f64) -> err {
    let n = y0.len
    let nt = times.len
    if nt < 2usize || n == 0usize || out.len < nt * (n + 1usize) || dy0.len < n { ret Invalid }
    var s: Daspk = zero
    let (blk, be) = mem.alloc[f64](a, 7usize * n + n * n + 8usize * n)
    if be != ok { ret be }
    let (piv, pe) = mem.alloc[usize](a, n)
    if pe != ok { ret pe }
    var z = 0usize
    while z < blk.len {
        blk[z] = 0.0f64
        z += 1usize
    }
    s.maxord = 5usize
    if maxord_in > 0usize && maxord_in < 5usize { s.maxord = maxord_in }
    var at = 0usize
    s.phi = blk[at..at + (s.maxord + 2usize) * n]
    at += (s.maxord + 2usize) * n
    s.wt = blk[at..at + n]
    at += n
    s.delta = blk[at..at + n]
    at += n
    s.e = blk[at..at + n]
    at += n
    s.y = blk[at..at + n]
    at += n
    s.yp = blk[at..at + n]
    at += n
    s.wm = blk[at..at + n * n]
    s.ipvt = piv[0usize..n]
    s.n = n
    s.uround = 2.220446049250313e-16f64
    var hmax = hmax_in
    if hmax <= 0.0f64 {
        var kk = 1usize
        while kk < nt {
            hmax = rk_fmax(hmax, math.abs[f64](times[kk] - times[kk - 1usize]))
            kk += 1usize
        }
    }
    var i = 0usize
    out[0usize] = times[0usize]
    while i < n {
        s.y[i] = y0[i]
        s.yp[i] = dy0[i]
        out[(i + 1usize) * nt] = y0[i]
        i += 1usize
    }
    var it = 0usize
    s.jstart = 0i64
    while it + 1usize < nt {
        let tout = times[it + 1usize]
        let t = times[it]
        var done = false
        var tn = s.x
        var h = s.h
        if s.jstart == 0i64 {
            // first call
            tn = t
            s.x = t
            if !dp_weights(&s, rtol, atol, s.y) { ret Invalid }
            s.hmin = 4.0f64 * s.uround * rk_fmax(math.abs[f64](t), math.abs[f64](tout))
            let tdist = math.abs[f64](tout - t)
            if tdist < s.hmin { ret Invalid }
            var h0 = hini
            if hini == 0.0f64 {
                h0 = 0.001f64 * tdist
                let ypnorm = dp_wnrm(n, s.yp, s.wt)
                if ypnorm > 0.5f64 / h0 { h0 = 0.5f64 / ypnorm }
                h0 = ls_sign(h0, tout - t)
            } else {
                if (tout - t) * h0 < 0.0f64 { ret Invalid }
            }
            let rh = math.abs[f64](h0) / hmax
            if rh > 1.0f64 { h0 = h0 / rh }
            h = h0
            i = 0usize
            while i < n {
                s.phi[i] = s.y[i]
                s.phi[n + i] = h * s.yp[i]
                i += 1usize
            }
        } else {
            let rh = math.abs[f64](h) / hmax
            if rh > 1.0f64 { h = h / rh }
            if (tn - tout) * h >= 0.0f64 {
                dp_trp(&s, tn, tout, s.kold, s.y, s.yp)
                done = true
            }
        }
        var nstep = 0usize
        while !done {
            if nstep >= maxsteps { ret Invalid }
            nstep += 1usize
            if !dp_weights(&s, rtol, atol, s.phi[0usize..n]) { ret Invalid }
            let r = dp_wnrm(n, s.phi[0usize..n], s.wt) * 100.0f64 * s.uround
            if r > 1.0f64 { ret Invalid }
            s.hmin = 4.0f64 * s.uround * rk_fmax(math.abs[f64](tn), math.abs[f64](tout))
            let rh = math.abs[f64](h) / hmax
            if rh > 1.0f64 { h = h / rh }
            s.h = h
            s.x = tn
            dp_step[Ctx](ctx, res, &s)
            h = s.h
            tn = s.x
            if s.idid < 0i64 { ret Invalid }
            if (tn - tout) * h >= 0.0f64 {
                dp_trp(&s, tn, tout, s.kold, s.y, s.yp)
                done = true
            }
        }
        s.h = h
        s.x = tn
        out[it + 1usize] = tout
        i = 0usize
        while i < n {
            out[it + 1usize + nt * (1usize + i)] = s.y[i]
            i += 1usize
        }
        it += 1usize
    }
    ret ok
}
