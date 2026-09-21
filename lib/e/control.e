// Feedback control in caller storage: a `Pid` (plain and with anti-windup by
// back-calculation), the classic Ziegler-Nichols table, a bang-bang switch
// with hysteresis, a `Feedforward` command over a feedback `Pid`, and the
// discrete-time state-space set over row-major `f64` matrices of `n <= 4`
// states: the infinite-horizon `lqr` gain by Riccati iteration, a
// `sliding_mode` law with a boundary layer, `pole_placement` by Ackermann's
// formula for one input, and the Luenberger `observer` with its gain from the
// dual placement. Scratch sizes are stated per declaration; short storage is
// `TooSmall` and a system that cannot be inverted is `Singular`.

use e.math
use e.math.filter

type Pid = struct { kp: f64, ki: f64, kd: f64, integral: f64, previous_error: f64, out_min: f64, out_max: f64, kb: f64 }
type Tuning = enum u8 { P, PI, PID }
type Feedforward = struct { gain: f64, feedback: Pid }
error TooSmall
error Singular

// A PID with no output limit.
fn pid(kp: f64, ki: f64, kd: f64) -> Pid {
    ret Pid { kp: kp, ki: ki, kd: kd, integral: 0.0f64, previous_error: 0.0f64, out_min: -1.0e300f64, out_max: 1.0e300f64, kb: 0.0f64 }
}

// One step: the integral accumulates `error * dt`, the derivative is the
// error's backward difference (zero when `dt <= 0`).
fn pid_step(p: *Pid, setpoint: f64, measured: f64, dt: f64) -> f64 {
    let e = setpoint - measured
    var d = 0.0f64
    if dt > 0.0f64 { d = (e - p.previous_error) / dt }
    p.integral += e * dt
    p.previous_error = e
    ret p.kp * e + p.ki * p.integral + p.kd * d
}

// A PID whose output is clamped to `[out_min, out_max]`; `kb` is the
// back-calculation gain feeding `kb * (clamped - raw)` into the integrator.
fn pid_anti_windup(kp: f64, ki: f64, kd: f64, out_min: f64, out_max: f64, kb: f64) -> Pid {
    ret Pid { kp: kp, ki: ki, kd: kd, integral: 0.0f64, previous_error: 0.0f64, out_min: out_min, out_max: out_max, kb: kb }
}

fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

// One step answering the clamped output; the integrator sees the error plus
// the back-calculated saturation excess.
fn pid_anti_windup_step(p: *Pid, setpoint: f64, measured: f64, dt: f64) -> f64 {
    let e = setpoint - measured
    var d = 0.0f64
    if dt > 0.0f64 { d = (e - p.previous_error) / dt }
    let raw = p.kp * e + p.ki * p.integral + p.kd * d
    let out = clamp(raw, p.out_min, p.out_max)
    p.integral += (e + p.kb * (out - raw)) * dt
    p.previous_error = e
    ret out
}

fn pid_reset(p: *Pid) {
    p.integral = 0.0f64
    p.previous_error = 0.0f64
}

// The classic table from the ultimate gain `ku` and period `tu`:
// P (0.5 ku), PI (0.45 ku, Ti = tu / 1.2), PID (0.6 ku, Ti = tu / 2, Td = tu / 8);
// answers (kp, ki, kd) with ki = kp / Ti and kd = kp * Td.
fn pid_tune_ziegler_nichols(ku: f64, tu: f64, kind: Tuning) -> (f64, f64, f64) {
    if kind == .P { ret (0.5f64 * ku, 0.0f64, 0.0f64) }
    if kind == .PI {
        let kp = 0.45f64 * ku
        ret (kp, kp / (tu / 1.2f64), 0.0f64)
    }
    let kp = 0.6f64 * ku
    ret (kp, kp / (0.5f64 * tu), kp * 0.125f64 * tu)
}

// A thermostat: an actuator that is on stays on until `measured` reaches
// `setpoint + hysteresis`, one that is off stays off until `measured` falls
// to `setpoint - hysteresis`. Answers the new state.
fn bang_bang(measured: f64, setpoint: f64, hysteresis: f64, on: bool) -> bool {
    if on { ret measured < setpoint + hysteresis }
    ret measured <= setpoint - hysteresis
}

// `gain * setpoint` (the model's command) plus the feedback PID's correction.
fn feedforward(f: *Feedforward, setpoint: f64, measured: f64, dt: f64) -> f64 {
    ret f.gain * setpoint + pid_step(&f.feedback, setpoint, measured, dt)
}

// `s = c * error + error_rate`; the control is `-k * sat(s / boundary)`,
// the plain sign when `boundary <= 0`.
fn sliding_mode(error_value: f64, error_rate: f64, c: f64, k: f64, boundary: f64) -> f64 {
    let s = c * error_value + error_rate
    if boundary <= 0.0f64 {
        if s > 0.0f64 { ret 0.0f64 - k }
        if s < 0.0f64 { ret k }
        ret 0.0f64
    }
    ret 0.0f64 - k * clamp(s / boundary, -1.0f64, 1.0f64)
}

fn identity(out: []f64, n: usize) {
    var i = 0usize
    while i < n * n {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i * n + i] = 1.0f64
        i += 1usize
    }
}

// Discrete infinite-horizon LQR for `x' = A x + B u` (`A` n x n, `B` n x m)
// with cost `x'Qx + u'Ru`: iterates the Riccati difference equation from
// `P = Q` until no entry moves more than `tolerance` or `iterations` pass,
// then answers the gain `K` (m x n, `u = -K x`) and the iterations used.
// `scratch.len >= 5 * n * n + 4 * n * m + 4 * m * m`.
fn lqr(a: []const f64, b: []const f64, q: []const f64, r: []const f64, n: usize, m: usize, k: []f64, scratch: []f64, iterations: usize, tolerance: f64) -> (usize, err) {
    let nn = n * n
    let nm = n * m
    let mm = m * m
    if a.len < nn || b.len < nm || q.len < nn || r.len < mm || k.len < nm { ret (0usize, TooSmall) }
    if scratch.len < 5usize * nn + 4usize * nm + 4usize * mm { ret (0usize, TooSmall) }
    var p = scratch[..nn]
    var a_t = scratch[nn..2usize * nn]
    var pa = scratch[2usize * nn..3usize * nn]
    var atpa = scratch[3usize * nn..4usize * nn]
    var atpbk = scratch[4usize * nn..5usize * nn]
    let base = 5usize * nn
    var bt = scratch[base..base + nm]
    var pb = scratch[base + nm..base + 2usize * nm]
    var btpa = scratch[base + 2usize * nm..base + 3usize * nm]
    var atpb = scratch[base + 3usize * nm..base + 4usize * nm]
    let base_m = base + 4usize * nm
    var s = scratch[base_m..base_m + mm]
    var s_inverse = scratch[base_m + mm..base_m + 2usize * mm]
    var inverse_scratch = scratch[base_m + 2usize * mm..base_m + 4usize * mm]
    filter.mat_transpose(a, a_t, n, n)
    filter.mat_transpose(b, bt, n, m)
    var i = 0usize
    while i < nn {
        p[i] = q[i]
        i += 1usize
    }
    var used = 0usize
    while used < iterations {
        used += 1usize
        filter.mat_mul(p, a, pa, n, n, n)
        filter.mat_mul(p, b, pb, n, n, m)
        filter.mat_mul(bt, pb, s, m, n, m)
        i = 0usize
        while i < mm {
            s[i] += r[i]
            i += 1usize
        }
        if filter.mat_inverse(s, s_inverse, m, inverse_scratch) != ok { ret (used, Singular) }
        filter.mat_mul(bt, pa, btpa, m, n, n)
        filter.mat_mul(s_inverse, btpa, k, m, m, n)
        filter.mat_mul(a_t, pa, atpa, n, n, n)
        filter.mat_mul(a_t, pb, atpb, n, n, m)
        filter.mat_mul(atpb, k, atpbk, n, m, n)
        var delta = 0.0f64
        i = 0usize
        while i < nn {
            let value = q[i] + atpa[i] - atpbk[i]
            let move = math.abs[f64](value - p[i])
            if move > delta { delta = move }
            p[i] = value
            i += 1usize
        }
        if delta < tolerance { ret (used, ok) }
    }
    ret (used, ok)
}

// The monic polynomial with the given roots (`re[i] + i im[i]`, conjugates
// paired so the coefficients are real) into `out[0..count]`: `out[j]` is
// the coefficient of `z^(count - 1 - j)`, the leading 1 implied.
// `scratch.len >= 2 * (count + 1)`.
fn characteristic(re: []const f64, im: []const f64, out: []f64, scratch: []f64) -> err {
    let count = re.len
    if im.len < count || out.len < count || scratch.len < 2usize * (count + 1usize) { ret TooSmall }
    // Coefficients of prod (z - p_i), highest first, as (real, imaginary) pairs.
    var cr = scratch[..count + 1usize]
    var ci = scratch[count + 1usize..2usize * (count + 1usize)]
    cr[0usize] = 1.0f64
    ci[0usize] = 0.0f64
    var degree = 0usize
    var i = 0usize
    while i < count {
        degree += 1usize
        cr[degree] = 0.0f64
        ci[degree] = 0.0f64
        var j = degree
        while j > 0usize {
            // c[j] = c[j] - p * c[j-1]
            let pr = re[i] * cr[j - 1usize] - im[i] * ci[j - 1usize]
            let pi = re[i] * ci[j - 1usize] + im[i] * cr[j - 1usize]
            cr[j] -= pr
            ci[j] -= pi
            j -= 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < count {
        out[i] = cr[i + 1usize]
        i += 1usize
    }
    ret ok
}

// Ackermann's formula for `x' = A x + B u` with one input (`B` n x 1):
// the gain row `k` (n entries, `u = -k x`) placing the closed-loop poles a_t
// `poles_re[i] + i poles_im[i]` (complex ones in conjugate pairs).
// `Singular` when the pair is not controllable. `scratch.len >= 6 * n * n + 4 * n`.
fn pole_placement(a: []const f64, b: []const f64, n: usize, poles_re: []const f64, poles_im: []const f64, k: []f64, scratch: []f64) -> err {
    let nn = n * n
    if a.len < nn || b.len < n || poles_re.len < n || poles_im.len < n || k.len < n { ret TooSmall }
    if scratch.len < 6usize * nn + 4usize * n { ret TooSmall }
    var ctrl = scratch[..nn]
    var ctrl_inverse = scratch[nn..2usize * nn]
    var phi = scratch[2usize * nn..3usize * nn]
    var product = scratch[3usize * nn..4usize * nn]
    var inverse_scratch = scratch[4usize * nn..5usize * nn]
    var column = scratch[5usize * nn..5usize * nn + n]
    var next_column = scratch[5usize * nn + n..5usize * nn + 2usize * n]
    var alpha = scratch[5usize * nn + 2usize * n..5usize * nn + 3usize * n]
    var poly_scratch = scratch[5usize * nn + 3usize * n..6usize * nn + 4usize * n]
    // Controllability matrix [B, AB, A^2 B, ...] by columns.
    var i = 0usize
    while i < n {
        column[i] = b[i]
        i += 1usize
    }
    var j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            ctrl[i * n + j] = column[i]
            i += 1usize
        }
        filter.mat_mul(a, column, next_column, n, n, 1usize)
        i = 0usize
        while i < n {
            column[i] = next_column[i]
            i += 1usize
        }
        j += 1usize
    }
    if filter.mat_inverse(ctrl, ctrl_inverse, n, inverse_scratch) != ok { ret Singular }
    let poly_error = characteristic(poles_re[..n], poles_im[..n], alpha, poly_scratch)
    if poly_error != ok { ret poly_error }
    // phi(A) = A^n + alpha[0] A^(n-1) + ... + alpha[n-1] I by Horner.
    identity(phi, n)
    i = 0usize
    while i < n {
        filter.mat_mul(phi, a, product, n, n, n)
        j = 0usize
        while j < nn {
            phi[j] = product[j]
            j += 1usize
        }
        j = 0usize
        while j < n {
            phi[j * n + j] += alpha[i]
            j += 1usize
        }
        i += 1usize
    }
    // k = (last row of ctrl^-1) phi(A).
    filter.mat_mul(ctrl_inverse[(n - 1usize) * n..nn], phi, k, 1usize, n, n)
    ret ok
}

// The Luenberger gain `l` (n entries) for `x' = A x + B u, y = C x` with
// one output (`C` 1 x n): pole placement on the dual pair (A', C').
// `scratch.len >= 8 * n * n + 4 * n`.
fn observer_gain(a: []const f64, c: []const f64, n: usize, poles_re: []const f64, poles_im: []const f64, l: []f64, scratch: []f64) -> err {
    let nn = n * n
    if a.len < nn || c.len < n || scratch.len < 8usize * nn + 4usize * n { ret TooSmall }
    var a_t = scratch[..nn]
    var ct = scratch[nn..2usize * nn]
    filter.mat_transpose(a, a_t, n, n)
    var i = 0usize
    while i < n {
        ct[i] = c[i]
        i += 1usize
    }
    ret pole_placement(a_t, ct[..n], n, poles_re, poles_im, l, scratch[2usize * nn..])
}

// One observer step: `x_hat' = A x_hat + B u + L (y - C x_hat)` with `n`
// states, `m` inputs (`B` n x m, `u` m entries) and `p` outputs (`C` p x n,
// `L` n x p, `y` p entries). `scratch.len >= 3 * n + p`.
fn observer_step(x_hat: []f64, a: []const f64, b: []const f64, c: []const f64, l: []const f64, n: usize, m: usize, p: usize, u: []const f64, y: []const f64, scratch: []f64) -> err {
    if x_hat.len < n || a.len < n * n || b.len < n * m || c.len < p * n || l.len < n * p || u.len < m || y.len < p { ret TooSmall }
    if scratch.len < 3usize * n + p { ret TooSmall }
    var predicted = scratch[..n]
    var bu = scratch[n..2usize * n]
    var correction = scratch[2usize * n..3usize * n]
    var innovation = scratch[3usize * n..3usize * n + p]
    filter.mat_mul(a, x_hat, predicted, n, n, 1usize)
    filter.mat_mul(b, u, bu, n, m, 1usize)
    filter.mat_mul(c, x_hat, innovation, p, n, 1usize)
    var i = 0usize
    while i < p {
        innovation[i] = y[i] - innovation[i]
        i += 1usize
    }
    filter.mat_mul(l, innovation, correction, n, p, 1usize)
    i = 0usize
    while i < n {
        x_hat[i] = predicted[i] + bu[i] + correction[i]
        i += 1usize
    }
    ret ok
}
