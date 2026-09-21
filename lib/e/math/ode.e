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

error TooSmall

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
    if scratch.len < 5usize * n { ret TooSmall }
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
    if scratch.len < 8usize * n { ret (0.0f64, h, TooSmall) }
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

// The fourth root by two square roots of Newton's iteration.
fn root4(x: f64) -> f64 { ret sqrt_f64(sqrt_f64(x)) }

fn sqrt_f64(x: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var r = x
    if r > 1.0f64 { r = x / 2.0f64 }
    var i = 0usize
    while i < 80usize {
        let next = (r + x / r) / 2.0f64
        if next == r { break }
        r = next
        i += 1usize
    }
    ret r
}

// One velocity Verlet step for `x'' = acceleration(x)`: positions `x` and
// velocities `v` of equal length; `scratch.len >= 2 * x.len` holds the
// accelerations at the two ends.
fn verlet[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err {
    let n = x.len
    if v.len != n || scratch.len < 2usize * n { ret TooSmall }
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
    let n = y.len
    if noise.len < n || scratch.len < 2usize * n { ret TooSmall }
    var a = scratch[..n]
    var b = scratch[n..2usize * n]
    drift(ctx, t, y, a)
    diffusion(ctx, t, y, b)
    let root_h = sqrt_f64(h)
    var i = 0usize
    while i < n {
        y[i] += h * a[i] + b[i] * root_h * noise[i]
        i += 1usize
    }
    ret ok
}
