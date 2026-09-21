// Motion planning in caller storage: velocity profiles (trapezoid, 7-segment
// S-curve, minimum jerk), natural cubic spline trajectories through timed
// waypoints, path tracking (pure pursuit, Stanley), local obstacle avoidance
// (dynamic window, velocity obstacles, ORCA) and potential fields with the
// elastic-band smoother.
//
// Poses are `kinematics.Pose` (x, y, heading); a path is a flat `[]f64` of
// (x, y) pairs and so is an obstacle list. Profiles cover a signed distance:
// `sign` carries the direction and every time query clamps into `[0, total]`.
// `orca` is a port of RVO2's `computeNewVelocity`: one half-plane per
// neighbour (with the time-step fallback when already overlapping), then the
// incremental 2-d linear program `linearProgram2` (each violated constraint
// re-solved by `linearProgram1` on its line) and `linearProgram3` (projecting
// onto the least-violating result) when the program is infeasible.

use e.math
use e.robot.kinematics as kin

type Profile = struct { distance: f64, sign: f64, v_peak: f64, a_max: f64, t_acc: f64, t_flat: f64, total: f64 }
type SCurve = struct { distance: f64, sign: f64, v_peak: f64, a_peak: f64, j_max: f64, tj: f64, ta: f64, tv: f64, total: f64 }
type Agent = struct { x: f64, y: f64, vx: f64, vy: f64, radius: f64, pref_vx: f64, pref_vy: f64, v_max: f64 }
type DwaState = struct { x: f64, y: f64, theta: f64, v: f64, omega: f64 }
type DwaParams = struct { v_min: f64, v_max: f64, omega_max: f64, a_max: f64, alpha_max: f64, dt: f64, horizon: f64, v_samples: usize, omega_samples: usize, heading_weight: f64, clearance_weight: f64, velocity_weight: f64, radius: f64, clearance_cap: f64 }
error TooSmall
error Invalid

fn agent(x: f64, y: f64, vx: f64, vy: f64, radius: f64, pref_vx: f64, pref_vy: f64, v_max: f64) -> Agent {
    ret Agent { x: x, y: y, vx: vx, vy: vy, radius: radius, pref_vx: pref_vx, pref_vy: pref_vy, v_max: v_max }
}

fn sign_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

// A trapezoidal velocity profile over `distance` (the triangle when `v_max` is not reached).
fn trapezoid_profile(distance: f64, v_max: f64, a_max: f64) -> Profile {
    let d = math.abs[f64](distance)
    let d_acc = v_max * v_max / (2.0f64 * a_max)
    var v_peak = v_max
    var t_flat = 0.0f64
    if 2.0f64 * d_acc >= d {
        v_peak = math.sqrt[f64](a_max * d)
    } else {
        t_flat = (d - 2.0f64 * d_acc) / v_max
    }
    let t_acc = v_peak / a_max
    ret Profile { distance: d, sign: sign_of(distance), v_peak: v_peak, a_max: a_max, t_acc: t_acc, t_flat: t_flat, total: 2.0f64 * t_acc + t_flat }
}

// (position, velocity) of a trapezoid at `t`.
fn trapezoid_at(p: Profile, t: f64) -> (f64, f64) {
    let tc = math.min[f64](math.max[f64](t, 0.0f64), p.total)
    if tc < p.t_acc {
        ret (p.sign * (0.5f64 * p.a_max * tc * tc), p.sign * (p.a_max * tc))
    }
    if tc < p.t_acc + p.t_flat {
        ret (p.sign * (0.5f64 * p.a_max * p.t_acc * p.t_acc + p.v_peak * (tc - p.t_acc)), p.sign * p.v_peak)
    }
    let rest = p.total - tc
    ret (p.sign * (p.distance - 0.5f64 * p.a_max * rest * rest), p.sign * (p.a_max * rest))
}

// A 7-segment S-curve (jerk-limited) profile over `distance`: constant jerk
// `j_max`, acceleration capped at `a_max`, speed at `v_max`; the constant-
// acceleration and cruise segments vanish when they cannot be reached.
fn s_curve_profile(distance: f64, v_max: f64, a_max: f64, j_max: f64) -> SCurve {
    let d = math.abs[f64](distance)
    var v_peak = v_max
    var a_peak = a_max
    var tj = a_max / j_max
    var ta = 0.0f64
    if v_max * j_max < a_max * a_max {
        a_peak = math.sqrt[f64](v_max * j_max)
        tj = a_peak / j_max
    } else {
        ta = v_max / a_max - tj
    }
    var tv = 0.0f64
    let d_ramp = v_peak * (2.0f64 * tj + ta)
    if d_ramp > d {
        tj = a_max / j_max
        v_peak = a_max * (math.sqrt[f64](tj * tj + 4.0f64 * d / a_max) - tj) * 0.5f64
        if v_peak * j_max >= a_max * a_max {
            a_peak = a_max
            ta = v_peak / a_max - tj
        } else {
            v_peak = math.pow[f64](d * d * j_max * 0.25f64, 1.0f64 / 3.0f64)
            a_peak = math.sqrt[f64](v_peak * j_max)
            tj = a_peak / j_max
            ta = 0.0f64
        }
    } else {
        tv = (d - d_ramp) / v_peak
    }
    ret SCurve { distance: d, sign: sign_of(distance), v_peak: v_peak, a_peak: a_peak, j_max: j_max, tj: tj, ta: ta, tv: tv, total: 4.0f64 * tj + 2.0f64 * ta + tv }
}

// (jerk, duration) of segment `k` (0..6) of an S-curve.
fn s_curve_segment(p: SCurve, k: usize) -> (f64, f64) {
    if k == 0usize || k == 6usize { ret (p.j_max, p.tj) }
    if k == 1usize || k == 5usize { ret (0.0f64, p.ta) }
    if k == 2usize || k == 4usize { ret (0.0f64 - p.j_max, p.tj) }
    ret (0.0f64, p.tv)
}

// (position, velocity, acceleration) of an S-curve at `t`.
fn s_curve_at(p: SCurve, t: f64) -> (f64, f64, f64) {
    var remaining = math.min[f64](math.max[f64](t, 0.0f64), p.total)
    var pos = 0.0f64
    var vel = 0.0f64
    var acc = 0.0f64
    var k = 0usize
    while k < 7usize {
        let (jerk, duration) = s_curve_segment(p, k)
        let tau = math.min[f64](remaining, duration)
        pos += vel * tau + 0.5f64 * acc * tau * tau + jerk * tau * tau * tau / 6.0f64
        vel += acc * tau + 0.5f64 * jerk * tau * tau
        acc += jerk * tau
        remaining -= tau
        if remaining <= 0.0f64 { ret (p.sign * pos, p.sign * vel, p.sign * acc) }
        k += 1usize
    }
    ret (p.sign * pos, p.sign * vel, p.sign * acc)
}

// Minimum-jerk point-to-point motion: (position, velocity, acceleration) at `t`.
fn min_jerk(start: f64, end: f64, duration: f64, t: f64) -> (f64, f64, f64) {
    let tau = math.min[f64](math.max[f64](t / duration, 0.0f64), 1.0f64)
    let span = end - start
    let t2 = tau * tau
    let t3 = t2 * tau
    let pos = start + span * (10.0f64 * t3 - 15.0f64 * t2 * t2 + 6.0f64 * t2 * t3)
    let vel = span * (30.0f64 * t2 - 60.0f64 * t3 + 30.0f64 * t2 * t2) / duration
    let acc = span * (60.0f64 * tau - 180.0f64 * t2 + 120.0f64 * t3) / (duration * duration)
    ret (pos, vel, acc)
}

// Natural cubic spline through `n` waypoints of `d` dimensions (row-major
// `n x d`) at increasing `times`: the second derivatives into `m` (`n x d`);
// `scratch.len >= 2 * n`.
fn spline_trajectory(times: []const f64, waypoints: []const f64, n: usize, d: usize, m: []f64, scratch: []f64) -> err {
    if n < 2usize { ret Invalid }
    if times.len < n || waypoints.len < n * d || m.len < n * d || scratch.len < 2usize * n { ret TooSmall }
    var i = 1usize
    while i < n {
        if times[i] <= times[i - 1usize] { ret Invalid }
        i += 1usize
    }
    var upper = scratch[..n]
    var rhs = scratch[n..2usize * n]
    var dim = 0usize
    while dim < d {
        m[dim] = 0.0f64
        m[(n - 1usize) * d + dim] = 0.0f64
        if n > 2usize {
            // Thomas algorithm on rows 1..n-2.
            i = 1usize
            while i + 1usize < n {
                let h0 = times[i] - times[i - 1usize]
                let h1 = times[i + 1usize] - times[i]
                let diag = 2.0f64 * (h0 + h1)
                let r = 6.0f64 * ((waypoints[(i + 1usize) * d + dim] - waypoints[i * d + dim]) / h1 - (waypoints[i * d + dim] - waypoints[(i - 1usize) * d + dim]) / h0)
                if i == 1usize {
                    upper[i] = h1 / diag
                    rhs[i] = r / diag
                } else {
                    let denominator = diag - h0 * upper[i - 1usize]
                    upper[i] = h1 / denominator
                    rhs[i] = (r - h0 * rhs[i - 1usize]) / denominator
                }
                i += 1usize
            }
            i = n - 2usize
            m[i * d + dim] = rhs[i]
            while i > 1usize {
                i -= 1usize
                m[i * d + dim] = rhs[i] - upper[i] * m[(i + 1usize) * d + dim]
            }
        }
        dim += 1usize
    }
    ret ok
}

// The spline's position and velocity at `t` (clamped to the time range) into `pos` and `vel` (`d` each).
fn spline_at(times: []const f64, waypoints: []const f64, m: []const f64, n: usize, d: usize, t: f64, pos: []f64, vel: []f64) -> err {
    if n < 2usize { ret Invalid }
    if times.len < n || waypoints.len < n * d || m.len < n * d || pos.len < d || vel.len < d { ret TooSmall }
    var i = 0usize
    while i + 2usize < n && t >= times[i + 1usize] { i += 1usize }
    let h = times[i + 1usize] - times[i]
    let tc = math.min[f64](math.max[f64](t, times[0usize]), times[n - 1usize])
    let a = (times[i + 1usize] - tc) / h
    let b = (tc - times[i]) / h
    var dim = 0usize
    while dim < d {
        let y0 = waypoints[i * d + dim]
        let y1 = waypoints[(i + 1usize) * d + dim]
        let m0 = m[i * d + dim]
        let m1 = m[(i + 1usize) * d + dim]
        pos[dim] = a * y0 + b * y1 + ((a * a * a - a) * m0 + (b * b * b - b) * m1) * h * h / 6.0f64
        vel[dim] = (y1 - y0) / h - (3.0f64 * a * a - 1.0f64) / 6.0f64 * h * m0 + (3.0f64 * b * b - 1.0f64) / 6.0f64 * h * m1
        dim += 1usize
    }
    ret ok
}

fn nearest_point(p: kin.Pose, path: []const f64) -> usize {
    var best = 0usize
    var best_d = 0.0f64
    var i = 0usize
    while 2usize * i + 1usize < path.len {
        let dx = path[2usize * i] - p.x
        let dy = path[2usize * i + 1usize] - p.y
        let dist = dx * dx + dy * dy
        if i == 0usize || dist < best_d {
            best = i
            best_d = dist
        }
        i += 1usize
    }
    ret best
}

// Pure pursuit: (steering angle, curvature) toward the first path point at
// least `lookahead` ahead of the nearest one (the last point when none is).
fn pure_pursuit(p: kin.Pose, path: []const f64, lookahead: f64, wheel_base: f64) -> (f64, f64, err) {
    let count = path.len / 2usize
    if count == 0usize { ret (0.0f64, 0.0f64, Invalid) }
    var i = nearest_point(p, path)
    var goal = count - 1usize
    while i < count {
        let dx = path[2usize * i] - p.x
        let dy = path[2usize * i + 1usize] - p.y
        if dx * dx + dy * dy >= lookahead * lookahead {
            goal = i
            i = count
        }
        i += 1usize
    }
    let dx = path[2usize * goal] - p.x
    let dy = path[2usize * goal + 1usize] - p.y
    let lx = math.cos[f64](p.theta) * dx + math.sin[f64](p.theta) * dy
    let ly = math.cos[f64](p.theta) * dy - math.sin[f64](p.theta) * dx
    let dist_sq = lx * lx + ly * ly
    if dist_sq < 1.0e-18f64 { ret (0.0f64, 0.0f64, ok) }
    let curvature = 2.0f64 * ly / dist_sq
    ret (math.atan[f64](wheel_base * curvature), curvature, ok)
}

// Stanley steering from the front-axle pose: heading error plus
// `atan2(k * cross_track, speed)`, cross-track positive when the path is to the left.
fn stanley(p: kin.Pose, path: []const f64, k: f64, speed: f64) -> (f64, err) {
    let count = path.len / 2usize
    if count < 2usize { ret (0.0f64, Invalid) }
    let i = nearest_point(p, path)
    var from = i
    var to = i + 1usize
    if to >= count {
        from = i - 1usize
        to = i
    }
    let yaw = math.atan2[f64](path[2usize * to + 1usize] - path[2usize * from + 1usize], path[2usize * to] - path[2usize * from])
    let heading_error = kin.wrap_angle(yaw - p.theta)
    let cross = (p.x - path[2usize * i]) * math.sin[f64](p.theta) - (p.y - path[2usize * i + 1usize]) * math.cos[f64](p.theta)
    ret (kin.wrap_angle(heading_error + math.atan2[f64](k * cross, speed)), ok)
}

fn sample(lo: f64, hi: f64, index: usize, count: usize) -> f64 {
    if count < 2usize { ret lo }
    ret lo + (hi - lo) * f64(index) / f64(count - 1usize)
}

// Dynamic window approach: sample the reachable (v, omega) window, roll each
// pair out for `horizon` by Euler steps of `dt`, drop the ones that touch an
// obstacle (`radius` inflated), and score the rest by heading toward the goal
// (`pi - |error|`), clearance (capped) and speed; answers the best pair, or
// (0, 0) when every sample collides.
fn dynamic_window(s: DwaState, goal_x: f64, goal_y: f64, obstacles: []const f64, params: DwaParams) -> (f64, f64) {
    let v_lo = math.max[f64](params.v_min, s.v - params.a_max * params.dt)
    let v_hi = math.min[f64](params.v_max, s.v + params.a_max * params.dt)
    let w_lo = math.max[f64](0.0f64 - params.omega_max, s.omega - params.alpha_max * params.dt)
    let w_hi = math.min[f64](params.omega_max, s.omega + params.alpha_max * params.dt)
    let steps = usize(params.horizon / params.dt)
    var best_v = 0.0f64
    var best_w = 0.0f64
    var best_score = 0.0f64
    var found = false
    var iv = 0usize
    while iv < params.v_samples {
        let v = sample(v_lo, v_hi, iv, params.v_samples)
        var iw = 0usize
        while iw < params.omega_samples {
            let w = sample(w_lo, w_hi, iw, params.omega_samples)
            var x = s.x
            var y = s.y
            var theta = s.theta
            var clearance = params.clearance_cap
            var step = 0usize
            while step < steps {
                theta += w * params.dt
                x += v * math.cos[f64](theta) * params.dt
                y += v * math.sin[f64](theta) * params.dt
                var o = 0usize
                while 2usize * o + 1usize < obstacles.len {
                    let dx = obstacles[2usize * o] - x
                    let dy = obstacles[2usize * o + 1usize] - y
                    let gap = math.sqrt[f64](dx * dx + dy * dy) - params.radius
                    if gap < clearance { clearance = gap }
                    o += 1usize
                }
                step += 1usize
            }
            if clearance > 0.0f64 {
                let heading = 3.141592653589793f64 - math.abs[f64](kin.wrap_angle(math.atan2[f64](goal_y - y, goal_x - x) - theta))
                let score = params.heading_weight * heading + params.clearance_weight * clearance + params.velocity_weight * v
                if !found || score > best_score {
                    found = true
                    best_score = score
                    best_v = v
                    best_w = w
                }
            }
            iw += 1usize
        }
        iv += 1usize
    }
    ret (best_v, best_w)
}

// Time until discs `a` and `b` touch when `a` moves at (vx, vy); negative when never.
fn time_to_collision(a: Agent, b: Agent, vx: f64, vy: f64) -> f64 {
    let rx = b.x - a.x
    let ry = b.y - a.y
    let rvx = vx - b.vx
    let rvy = vy - b.vy
    let radius = a.radius + b.radius
    let c = rx * rx + ry * ry - radius * radius
    if c <= 0.0f64 { ret 0.0f64 }
    let qa = rvx * rvx + rvy * rvy
    let qb = 0.0f64 - 2.0f64 * (rx * rvx + ry * rvy)
    let disc = qb * qb - 4.0f64 * qa * c
    if qa < 1.0e-18f64 || disc < 0.0f64 { ret 0.0f64 - 1.0f64 }
    let t = (0.0f64 - qb - math.sqrt[f64](disc)) / (2.0f64 * qa)
    if t < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret t
}

// Velocity obstacles: among `candidates` ((vx, vy) pairs) the one closest to
// the agent's preferred velocity that collides with no other within `horizon`;
// when all collide, the one with the latest collision. Answers the index.
fn velocity_obstacles(a: Agent, others: []const Agent, candidates: []const f64, horizon: f64) -> usize {
    var best = 0usize
    var best_safe = false
    var best_cost = 0.0f64
    var best_ttc = 0.0f64
    var i = 0usize
    while 2usize * i + 1usize < candidates.len {
        let vx = candidates[2usize * i]
        let vy = candidates[2usize * i + 1usize]
        var ttc = horizon
        var j = 0usize
        while j < others.len {
            let t = time_to_collision(a, others[j], vx, vy)
            if t >= 0.0f64 && t < ttc { ttc = t }
            j += 1usize
        }
        let safe = ttc >= horizon
        let cost = (vx - a.pref_vx) * (vx - a.pref_vx) + (vy - a.pref_vy) * (vy - a.pref_vy)
        var better = false
        if i == 0usize {
            better = true
        } else if safe {
            better = !best_safe || cost < best_cost
        } else if !best_safe {
            better = ttc > best_ttc
        }
        if better {
            best = i
            best_safe = safe
            best_cost = cost
            best_ttc = ttc
        }
        i += 1usize
    }
    ret best
}

fn det(ax: f64, ay: f64, bx: f64, by: f64) -> f64 { ret ax * by - ay * bx }

// RVO2 linearProgram1: optimise along line `line_no` under lines `0..line_no`.
fn lp1(lines: []const f64, line_no: usize, radius: f64, opt_x: f64, opt_y: f64, direction_opt: bool, result: []f64) -> bool {
    let px = lines[4usize * line_no]
    let py = lines[4usize * line_no + 1usize]
    let dx = lines[4usize * line_no + 2usize]
    let dy = lines[4usize * line_no + 3usize]
    let dot = px * dx + py * dy
    let discriminant = dot * dot + radius * radius - (px * px + py * py)
    if discriminant < 0.0f64 { ret false }
    let root = math.sqrt[f64](discriminant)
    var t_left = 0.0f64 - dot - root
    var t_right = 0.0f64 - dot + root
    var i = 0usize
    while i < line_no {
        let qx = lines[4usize * i]
        let qy = lines[4usize * i + 1usize]
        let ex = lines[4usize * i + 2usize]
        let ey = lines[4usize * i + 3usize]
        let denominator = det(dx, dy, ex, ey)
        let numerator = det(ex, ey, px - qx, py - qy)
        if math.abs[f64](denominator) <= 1.0e-5f64 {
            if numerator < 0.0f64 { ret false }
            i += 1usize
            continue
        }
        let t = numerator / denominator
        if denominator >= 0.0f64 {
            t_right = math.min[f64](t_right, t)
        } else {
            t_left = math.max[f64](t_left, t)
        }
        if t_left > t_right { ret false }
        i += 1usize
    }
    var t = 0.0f64
    if direction_opt {
        if opt_x * dx + opt_y * dy > 0.0f64 { t = t_right } else { t = t_left }
    } else {
        t = dx * (opt_x - px) + dy * (opt_y - py)
        if t < t_left { t = t_left } else if t > t_right { t = t_right }
    }
    result[0usize] = px + t * dx
    result[1usize] = py + t * dy
    ret true
}

// RVO2 linearProgram2: the velocity closest to (opt_x, opt_y) within `radius`
// satisfying `count` lines; answers `count`, or the first failing line.
fn lp2(lines: []const f64, count: usize, radius: f64, opt_x: f64, opt_y: f64, direction_opt: bool, result: []f64) -> usize {
    if direction_opt {
        result[0usize] = opt_x * radius
        result[1usize] = opt_y * radius
    } else if opt_x * opt_x + opt_y * opt_y > radius * radius {
        let length = math.sqrt[f64](opt_x * opt_x + opt_y * opt_y)
        result[0usize] = opt_x / length * radius
        result[1usize] = opt_y / length * radius
    } else {
        result[0usize] = opt_x
        result[1usize] = opt_y
    }
    var i = 0usize
    while i < count {
        if det(lines[4usize * i + 2usize], lines[4usize * i + 3usize], lines[4usize * i] - result[0usize], lines[4usize * i + 1usize] - result[1usize]) > 0.0f64 {
            let keep_x = result[0usize]
            let keep_y = result[1usize]
            if !lp1(lines, i, radius, opt_x, opt_y, direction_opt, result) {
                result[0usize] = keep_x
                result[1usize] = keep_y
                ret i
            }
        }
        i += 1usize
    }
    ret count
}

// RVO2 linearProgram3: from `begin` on, project onto the least-violating velocity; `proj` holds `4 * count`.
fn lp3(lines: []const f64, count: usize, begin: usize, radius: f64, result: []f64, proj: []f64) {
    var distance = 0.0f64
    var i = begin
    while i < count {
        let px = lines[4usize * i]
        let py = lines[4usize * i + 1usize]
        let dx = lines[4usize * i + 2usize]
        let dy = lines[4usize * i + 3usize]
        if det(dx, dy, px - result[0usize], py - result[1usize]) > distance {
            var used = 0usize
            var j = 0usize
            while j < i {
                let qx = lines[4usize * j]
                let qy = lines[4usize * j + 1usize]
                let ex = lines[4usize * j + 2usize]
                let ey = lines[4usize * j + 3usize]
                let determinant = det(dx, dy, ex, ey)
                var nx = 0.0f64
                var ny = 0.0f64
                var skip = false
                if math.abs[f64](determinant) <= 1.0e-5f64 {
                    if dx * ex + dy * ey > 0.0f64 {
                        skip = true
                    } else {
                        nx = 0.5f64 * (px + qx)
                        ny = 0.5f64 * (py + qy)
                    }
                } else {
                    let s = det(ex, ey, px - qx, py - qy) / determinant
                    nx = px + s * dx
                    ny = py + s * dy
                }
                if !skip {
                    let fx = ex - dx
                    let fy = ey - dy
                    let length = math.sqrt[f64](fx * fx + fy * fy)
                    proj[4usize * used] = nx
                    proj[4usize * used + 1usize] = ny
                    proj[4usize * used + 2usize] = fx / length
                    proj[4usize * used + 3usize] = fy / length
                    used += 1usize
                }
                j += 1usize
            }
            let keep_x = result[0usize]
            let keep_y = result[1usize]
            if lp2(proj, used, radius, 0.0f64 - dy, dx, true, result) < used {
                result[0usize] = keep_x
                result[1usize] = keep_y
            }
            distance = det(dx, dy, px - result[0usize], py - result[1usize])
        }
        i += 1usize
    }
}

// ORCA: the new velocity of `agents[i]` for time horizon `tau` into `out`
// (vx, vy); `time_step` governs the escape when discs already overlap;
// `scratch.len >= 8 * agents.len`.
fn orca(agents: []const Agent, i: usize, tau: f64, time_step: f64, out: []f64, scratch: []f64) -> err {
    if i >= agents.len { ret Invalid }
    if out.len < 2usize || scratch.len < 8usize * agents.len { ret TooSmall }
    let me = agents[i]
    var lines = scratch[..4usize * agents.len]
    var count = 0usize
    var j = 0usize
    while j < agents.len {
        if j == i {
            j += 1usize
            continue
        }
        let other = agents[j]
        let rx = other.x - me.x
        let ry = other.y - me.y
        let vx = me.vx - other.vx
        let vy = me.vy - other.vy
        let dist_sq = rx * rx + ry * ry
        let radius = me.radius + other.radius
        let radius_sq = radius * radius
        var dx = 0.0f64
        var dy = 0.0f64
        var ux = 0.0f64
        var uy = 0.0f64
        if dist_sq > radius_sq {
            let inv_tau = 1.0f64 / tau
            let wx = vx - inv_tau * rx
            let wy = vy - inv_tau * ry
            let w_sq = wx * wx + wy * wy
            let dot1 = wx * rx + wy * ry
            if dot1 < 0.0f64 && dot1 * dot1 > radius_sq * w_sq {
                let w_len = math.sqrt[f64](w_sq)
                let unit_x = wx / w_len
                let unit_y = wy / w_len
                dx = unit_y
                dy = 0.0f64 - unit_x
                ux = (radius * inv_tau - w_len) * unit_x
                uy = (radius * inv_tau - w_len) * unit_y
            } else {
                let leg = math.sqrt[f64](dist_sq - radius_sq)
                if det(rx, ry, wx, wy) > 0.0f64 {
                    dx = (rx * leg - ry * radius) / dist_sq
                    dy = (rx * radius + ry * leg) / dist_sq
                } else {
                    dx = 0.0f64 - (rx * leg + ry * radius) / dist_sq
                    dy = 0.0f64 - (ry * leg - rx * radius) / dist_sq
                }
                let dot2 = vx * dx + vy * dy
                ux = dot2 * dx - vx
                uy = dot2 * dy - vy
            }
        } else {
            let inv_step = 1.0f64 / time_step
            let wx = vx - inv_step * rx
            let wy = vy - inv_step * ry
            let w_len = math.sqrt[f64](wx * wx + wy * wy)
            let unit_x = wx / w_len
            let unit_y = wy / w_len
            dx = unit_y
            dy = 0.0f64 - unit_x
            ux = (radius * inv_step - w_len) * unit_x
            uy = (radius * inv_step - w_len) * unit_y
        }
        lines[4usize * count] = me.vx + 0.5f64 * ux
        lines[4usize * count + 1usize] = me.vy + 0.5f64 * uy
        lines[4usize * count + 2usize] = dx
        lines[4usize * count + 3usize] = dy
        count += 1usize
        j += 1usize
    }
    let failed = lp2(lines, count, me.v_max, me.pref_vx, me.pref_vy, false, out)
    if failed < count {
        lp3(lines, count, failed, me.v_max, out, scratch[4usize * agents.len..8usize * agents.len])
    }
    ret ok
}

// The repulsive force at (x, y) from obstacles within `rho0`.
fn repulsive(x: f64, y: f64, obstacles: []const f64, k_rep: f64, rho0: f64) -> (f64, f64) {
    var fx = 0.0f64
    var fy = 0.0f64
    var o = 0usize
    while 2usize * o + 1usize < obstacles.len {
        let dx = x - obstacles[2usize * o]
        let dy = y - obstacles[2usize * o + 1usize]
        let rho = math.sqrt[f64](dx * dx + dy * dy)
        if rho < rho0 && rho > 1.0e-12f64 {
            let magnitude = k_rep * (1.0f64 / rho - 1.0f64 / rho0) / (rho * rho)
            fx += magnitude * dx / rho
            fy += magnitude * dy / rho
        }
        o += 1usize
    }
    ret (fx, fy)
}

// Artificial potential field: attraction `k_att * (goal - p)` plus the
// repulsion `k_rep * (1/rho - 1/rho0) / rho^2` from every obstacle within `rho0`.
fn potential_field(x: f64, y: f64, goal_x: f64, goal_y: f64, obstacles: []const f64, k_att: f64, k_rep: f64, rho0: f64) -> (f64, f64) {
    let (rx, ry) = repulsive(x, y, obstacles, k_rep, rho0)
    ret (k_att * (goal_x - x) + rx, k_att * (goal_y - y) + ry)
}

// Elastic band: relax the interior points of `path` in place for `iterations`
// Gauss-Seidel sweeps under the internal spring `k_internal * (prev + next - 2p)`
// and the obstacle repulsion scaled by `k_external`; the endpoints stay.
fn elastic_band(path: []f64, obstacles: []const f64, iterations: usize, k_internal: f64, k_external: f64, rho0: f64) {
    let count = path.len / 2usize
    if count < 3usize { ret }
    var it = 0usize
    while it < iterations {
        var i = 1usize
        while i + 1usize < count {
            let x = path[2usize * i]
            let y = path[2usize * i + 1usize]
            let (rx, ry) = repulsive(x, y, obstacles, k_external, rho0)
            path[2usize * i] = x + k_internal * (path[2usize * i - 2usize] + path[2usize * i + 2usize] - 2.0f64 * x) + rx
            path[2usize * i + 1usize] = y + k_internal * (path[2usize * i - 1usize] + path[2usize * i + 3usize] - 2.0f64 * y) + ry
            i += 1usize
        }
        it += 1usize
    }
}
