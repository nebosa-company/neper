// Robot kinematics in caller storage: planar pose integration (dead
// reckoning, wheel-tick odometry, differential-drive and Ackermann models)
// and serial-arm kinematics over Denavit-Hartenberg parameters (a 4 x 4
// row-major transform per link, forward kinematics, and inverse kinematics by
// a finite-difference Jacobian, either its transpose or damped least squares).
//
// Planar integration uses the exact arc model: a step of distance `s` and
// turn `w` moves along a circle of radius `s / w`, a straight line when the
// turn is below `1e-12`. A `Dh` row is the standard (Craig-free) convention
// `Rz(theta) Tz(d) Tx(a) Rx(alpha)`; `forward` adds each joint value to the
// row's `theta` (revolute joints). The IK loops run exactly `iterations`
// steps with the Jacobian estimated by forward differences of `1e-6` and
// answer the final position error norm; joints are updated in place.

use e.math
use e.math.filter as filter

type Pose = struct { x: f64, y: f64, theta: f64 }
type Dh = struct { theta: f64, d: f64, a: f64, alpha: f64 }
error TooSmall
error Singular

fn pose(x: f64, y: f64, theta: f64) -> Pose { ret Pose { x: x, y: y, theta: theta } }
fn dh(theta: f64, d: f64, a: f64, alpha: f64) -> Dh { ret Dh { theta: theta, d: d, a: a, alpha: alpha } }

// Wrap an angle into (-pi, pi].
fn wrap_angle(angle: f64) -> f64 {
    let two_pi = 6.283185307179586f64
    var a = angle
    while a > 3.141592653589793f64 { a -= two_pi }
    while a <= 0.0f64 - 3.141592653589793f64 { a += two_pi }
    ret a
}

// Move `distance` along an arc that turns by `turn` (radians).
fn arc_step(p: Pose, distance: f64, turn: f64) -> Pose {
    if math.abs[f64](turn) < 1.0e-12f64 {
        ret Pose { x: p.x + distance * math.cos[f64](p.theta), y: p.y + distance * math.sin[f64](p.theta), theta: p.theta }
    }
    let radius = distance / turn
    let heading = p.theta + turn
    let x = p.x + radius * (math.sin[f64](heading) - math.sin[f64](p.theta))
    let y = p.y - radius * (math.cos[f64](heading) - math.cos[f64](p.theta))
    ret Pose { x: x, y: y, theta: wrap_angle(heading) }
}

// Integrate `speed` and `heading_rate` over `dt`.
fn dead_reckon(p: Pose, speed: f64, heading_rate: f64, dt: f64) -> Pose {
    ret arc_step(p, speed * dt, heading_rate * dt)
}

// Wheel-encoder odometry: tick deltas of both wheels to a new pose.
fn odometry(p: Pose, left_ticks: i64, right_ticks: i64, ticks_per_metre: f64, wheel_base: f64) -> Pose {
    let left = f64(left_ticks) / ticks_per_metre
    let right = f64(right_ticks) / ticks_per_metre
    ret arc_step(p, (left + right) * 0.5f64, (right - left) / wheel_base)
}

// Body velocity to (left, right) wheel speeds.
fn differential_drive(v: f64, omega: f64, wheel_base: f64) -> (f64, f64) {
    let half = omega * wheel_base * 0.5f64
    ret (v - half, v + half)
}

// Wheel speeds to body (v, omega).
fn differential_drive_wheels(v_left: f64, v_right: f64, wheel_base: f64) -> (f64, f64) {
    ret ((v_left + v_right) * 0.5f64, (v_right - v_left) / wheel_base)
}

// Bicycle model: (yaw rate, turning radius); the radius is `0` when driving straight.
fn ackermann(speed: f64, steering_angle: f64, wheel_base: f64) -> (f64, f64) {
    let t = math.tan[f64](steering_angle)
    if math.abs[f64](t) < 1.0e-12f64 { ret (0.0f64, 0.0f64) }
    ret (speed * t / wheel_base, wheel_base / t)
}

fn ackermann_step(p: Pose, speed: f64, steering_angle: f64, wheel_base: f64, dt: f64) -> Pose {
    let (omega, _) = ackermann(speed, steering_angle, wheel_base)
    ret arc_step(p, speed * dt, omega * dt)
}

// The 4 x 4 row-major transform of one DH row into `out` (16 entries).
fn dh_transform(theta: f64, d: f64, a: f64, alpha: f64, out: []f64) -> err {
    if out.len < 16usize { ret TooSmall }
    let ct = math.cos[f64](theta)
    let st = math.sin[f64](theta)
    let ca = math.cos[f64](alpha)
    let sa = math.sin[f64](alpha)
    out[0usize] = ct
    out[1usize] = 0.0f64 - st * ca
    out[2usize] = st * sa
    out[3usize] = a * ct
    out[4usize] = st
    out[5usize] = ct * ca
    out[6usize] = 0.0f64 - ct * sa
    out[7usize] = a * st
    out[8usize] = 0.0f64
    out[9usize] = sa
    out[10usize] = ca
    out[11usize] = d
    out[12usize] = 0.0f64
    out[13usize] = 0.0f64
    out[14usize] = 0.0f64
    out[15usize] = 1.0f64
    ret ok
}

// Forward kinematics: the end-effector transform into `out_pose` (16); `scratch.len >= 32`.
fn forward(params: []const Dh, joints: []const f64, out_pose: []f64, scratch: []f64) -> err {
    if out_pose.len < 16usize || scratch.len < 32usize || joints.len < params.len { ret TooSmall }
    var i = 0usize
    while i < 16usize {
        out_pose[i] = 0.0f64
        i += 1usize
    }
    out_pose[0usize] = 1.0f64
    out_pose[5usize] = 1.0f64
    out_pose[10usize] = 1.0f64
    out_pose[15usize] = 1.0f64
    var link = 0usize
    while link < params.len {
        let row = params[link]
        try dh_transform(row.theta + joints[link], row.d, row.a, row.alpha, scratch[..16usize])
        filter.mat_mul(out_pose[..16usize], scratch[..16usize], scratch[16usize..32usize], 4usize, 4usize, 4usize)
        i = 0usize
        while i < 16usize {
            out_pose[i] = scratch[16usize + i]
            i += 1usize
        }
        link += 1usize
    }
    ret ok
}

// The position error `goal - fk(joints)` into `err_out` (3) and the forward-difference
// Jacobian (3 x n, row-major) into `jac`; `scratch.len >= 48 + n`.
fn jacobian(params: []const Dh, joints: []f64, goal: []const f64, jac: []f64, err_out: []f64, scratch: []f64) -> err {
    let n = params.len
    if scratch.len < 48usize + n || jac.len < 3usize * n || err_out.len < 3usize || goal.len < 3usize { ret TooSmall }
    let h = 1.0e-6f64
    try forward(params, joints, scratch[..16usize], scratch[16usize..48usize])
    err_out[0usize] = goal[0usize] - scratch[3usize]
    err_out[1usize] = goal[1usize] - scratch[7usize]
    err_out[2usize] = goal[2usize] - scratch[11usize]
    let base_x = scratch[3usize]
    let base_y = scratch[7usize]
    let base_z = scratch[11usize]
    var probe = scratch[48usize..48usize + n]
    var j = 0usize
    while j < n {
        var k = 0usize
        while k < n {
            probe[k] = joints[k]
            k += 1usize
        }
        probe[j] = joints[j] + h
        try forward(params, probe, scratch[..16usize], scratch[16usize..48usize])
        jac[j] = (scratch[3usize] - base_x) / h
        jac[n + j] = (scratch[7usize] - base_y) / h
        jac[2usize * n + j] = (scratch[11usize] - base_z) / h
        j += 1usize
    }
    ret ok
}

fn norm3(v: []const f64) -> f64 {
    ret math.sqrt[f64](v[0usize] * v[0usize] + v[1usize] * v[1usize] + v[2usize] * v[2usize])
}

// Jacobian-transpose IK toward `goal` (x, y, z): `joints += step * J' e` for
// `iterations` steps; answers the final error norm. `scratch.len >= 51 + 4 * n`.
fn ik_jacobian(params: []const Dh, joints: []f64, goal: []const f64, iterations: usize, step: f64, scratch: []f64) -> (f64, err) {
    let n = params.len
    if scratch.len < 51usize + 4usize * n || joints.len < n { ret (0.0f64, TooSmall) }
    var jac = scratch[..3usize * n]
    var e = scratch[3usize * n..3usize * n + 3usize]
    var work = scratch[3usize * n + 3usize..]
    var it = 0usize
    while it < iterations {
        let jac_error = jacobian(params, joints, goal, jac, e, work)
        if jac_error != ok { ret (0.0f64, jac_error) }
        var j = 0usize
        while j < n {
            joints[j] += step * (jac[j] * e[0usize] + jac[n + j] * e[1usize] + jac[2usize * n + j] * e[2usize])
            j += 1usize
        }
        it += 1usize
    }
    let final_error = jacobian(params, joints, goal, jac, e, work)
    if final_error != ok { ret (0.0f64, final_error) }
    ret (norm3(e), ok)
}

// Damped least-squares IK: `joints += J' (J J' + lambda^2 I)^-1 e` for `iterations`
// steps; answers the final error norm. `scratch.len >= 81 + 7 * n`.
fn ik_damped_least_squares(params: []const Dh, joints: []f64, goal: []const f64, iterations: usize, lambda: f64, scratch: []f64) -> (f64, err) {
    let n = params.len
    if scratch.len < 81usize + 7usize * n || joints.len < n { ret (0.0f64, TooSmall) }
    var jac = scratch[..3usize * n]
    var jac_t = scratch[3usize * n..6usize * n]
    var e = scratch[6usize * n..6usize * n + 3usize]
    var jjt = scratch[6usize * n + 3usize..6usize * n + 12usize]
    var inv = scratch[6usize * n + 12usize..6usize * n + 21usize]
    var inv_scratch = scratch[6usize * n + 21usize..6usize * n + 30usize]
    var g = scratch[6usize * n + 30usize..6usize * n + 33usize]
    var work = scratch[6usize * n + 33usize..]
    var it = 0usize
    while it < iterations {
        let jac_error = jacobian(params, joints, goal, jac, e, work)
        if jac_error != ok { ret (0.0f64, jac_error) }
        filter.mat_transpose(jac, jac_t, 3usize, n)
        filter.mat_mul(jac, jac_t, jjt, 3usize, n, 3usize)
        jjt[0usize] += lambda * lambda
        jjt[4usize] += lambda * lambda
        jjt[8usize] += lambda * lambda
        if filter.mat_inverse(jjt, inv, 3usize, inv_scratch) != ok { ret (0.0f64, Singular) }
        filter.mat_mul(inv, e, g, 3usize, 3usize, 1usize)
        var j = 0usize
        while j < n {
            joints[j] += jac[j] * g[0usize] + jac[n + j] * g[1usize] + jac[2usize * n + j] * g[2usize]
            j += 1usize
        }
        it += 1usize
    }
    let final_error = jacobian(params, joints, goal, jac, e, work)
    if final_error != ok { ret (0.0f64, final_error) }
    ret (norm3(e), ok)
}
