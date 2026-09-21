// `e.robot.motion`: trapezoid and S-curve profiles at 20 sample times (a
// weighted hash against the analytic replica), minimum jerk, a natural cubic
// spline against scipy, pure pursuit and Stanley steering on a circle, the
// dynamic window and velocity-obstacle choices on the replica's grids, ORCA
// velocities for four agents (and an overlapping case through the third
// linear program), potential-field forces and the elastic band's final hash.
// Each check exits with its own code.

use e.io
use e.math
use e.mem
use e.os
use e.robot.kinematics as kin
use e.robot.motion as motion

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

fn trapezoid_hash(p: motion.Profile) -> f64 {
    var h = 0.0f64
    var k = 0usize
    while k < 20usize {
        let (pos, vel) = motion.trapezoid_at(p, p.total * f64(k) / 19.0f64)
        h += f64(k + 1usize) * pos + 0.37f64 * f64(k + 1usize) * vel
        k += 1usize
    }
    ret h
}

fn s_curve_hash(p: motion.SCurve) -> f64 {
    var h = 0.0f64
    var k = 0usize
    while k < 20usize {
        let (pos, vel, acc) = motion.s_curve_at(p, p.total * f64(k) / 19.0f64)
        h += f64(k + 1usize) * pos + 0.37f64 * f64(k + 1usize) * vel + 0.11f64 * f64(k + 1usize) * acc
        k += 1usize
    }
    ret h
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pi = 3.141592653589793f64

    // 1: trapezoid profiles, full and triangular.
    let tp = motion.trapezoid_profile(10.0f64, 2.0f64, 1.5f64)
    let tt = motion.trapezoid_profile(1.0f64, 2.0f64, 1.5f64)
    if !near(tp.total, 6.333333333333334f64, 1.0e-12f64) || !near(tt.total, 1.6329931618554518f64, 1.0e-12f64) { os.exit(1i32) }
    if !near(trapezoid_hash(tp), 1565.7166666666667f64, 1.0e-9f64) || !near(trapezoid_hash(tt), 192.5147304230433f64, 1.0e-9f64) { os.exit(1i32) }
    let (tp_pos, tp_vel) = motion.trapezoid_at(tp, 3.7f64)
    if !near(tp_pos, 6.066666666666667f64, 1.0e-12f64) || !near(tp_vel, 2.0f64, 1.0e-12f64) { os.exit(1i32) }
    let (end_pos, end_vel) = motion.trapezoid_at(tp, 100.0f64)
    if !near(end_pos, 10.0f64, 1.0e-12f64) || end_vel != 0.0f64 { os.exit(1i32) }

    // 2: S-curves: full, triangular with a constant-acceleration phase, and without.
    let sp = motion.s_curve_profile(10.0f64, 2.0f64, 1.5f64, 3.0f64)
    let st = motion.s_curve_profile(1.5f64, 2.0f64, 1.5f64, 3.0f64)
    let sn = motion.s_curve_profile(0.0f64 - 0.05f64, 2.0f64, 1.5f64, 3.0f64)
    if !near(sp.total, 6.833333333333334f64, 1.0e-12f64) || !near(st.total, 2.56155281280883f64, 1.0e-12f64) || !near(sn.total, 0.8109602660764534f64, 1.0e-12f64) { os.exit(2i32) }
    if !near(s_curve_hash(sp), 1562.3842540484793f64, 1.0e-9f64) || !near(s_curve_hash(st), 258.0772455778113f64, 1.0e-9f64) || !near(s_curve_hash(sn), 0.0f64 - 9.024544178351706f64, 1.0e-9f64) { os.exit(2i32) }
    let (sp_pos, sp_vel, sp_acc) = motion.s_curve_at(sp, 2.2f64)
    if !near(sp_pos, 2.5666666666666673f64, 1.0e-12f64) || !near(sp_vel, 2.0f64, 1.0e-12f64) || !near(sp_acc, 0.0f64, 1.0e-12f64) { os.exit(2i32) }
    let (sn_end, sn_vel, sn_acc) = motion.s_curve_at(sn, sn.total)
    if !near(sn_end, 0.0f64 - 0.05f64, 1.0e-9f64) || !near(sn_vel, 0.0f64, 1.0e-9f64) || !near(sn_acc, 0.0f64, 1.0e-9f64) { os.exit(2i32) }

    // 3: minimum jerk.
    let (mj_pos, mj_vel, mj_acc) = motion.min_jerk(1.0f64, 3.0f64, 2.0f64, 0.7f64)
    if !near(mj_pos, 1.4703387499999998f64, 1.0e-12f64) || !near(mj_vel, 1.5526874999999998f64, 1.0e-12f64) || !near(mj_acc, 2.0475000000000008f64, 1.0e-12f64) { os.exit(3i32) }
    let (mj_end, _, _) = motion.min_jerk(1.0f64, 3.0f64, 2.0f64, 5.0f64)
    if mj_end != 3.0f64 { os.exit(3i32) }

    // 4: natural cubic spline against scipy.
    let times: [5]f64 = [5]f64{ 0.0, 1.0, 2.5, 3.0, 4.5 }
    let waypoints: [10]f64 = [10]f64{ 0.0, 1.0, 1.0, 0.5, 2.0, 2.0, 1.5, 3.0, 3.0, 2.5 }
    var m: [10]f64 = zero
    var scratch: [64]f64 = zero
    if motion.spline_trajectory(times[..], waypoints[..], 5usize, 2usize, m[..], scratch[..]) != ok { os.exit(4i32) }
    let queries: [4]f64 = [4]f64{ 0.3, 1.7, 2.9, 4.0 }
    let want_pos: [8]f64 = [8]f64{ 0.27553763440860213, 0.7878655913978495, 1.8175643170051772, 0.8063496614894464, 1.58431541218638, 2.8325878136200715, 2.1232576662684193, 3.075667064914377 }
    let want_vel: [8]f64 = [8]f64{ 0.9345878136200716, -0.666146953405018, 0.9572520908004778, 0.9245758661887695, -0.969247311827957, 1.8239784946236566, 1.5651135005973718, -0.9468339307048981 }
    var pos: [2]f64 = zero
    var vel: [2]f64 = zero
    var q = 0usize
    while q < 4usize {
        if motion.spline_at(times[..], waypoints[..], m[..], 5usize, 2usize, queries[q], pos[..], vel[..]) != ok { os.exit(4i32) }
        if !near(pos[0usize], want_pos[2usize * q], 1.0e-9f64) || !near(pos[1usize], want_pos[2usize * q + 1usize], 1.0e-9f64) { os.exit(4i32) }
        if !near(vel[0usize], want_vel[2usize * q], 1.0e-9f64) || !near(vel[1usize], want_vel[2usize * q + 1usize], 1.0e-9f64) { os.exit(4i32) }
        q += 1usize
    }
    if motion.spline_at(times[..], waypoints[..], m[..], 5usize, 2usize, 9.0f64, pos[..], vel[..]) != ok || !near(pos[0usize], 3.0f64, 1.0e-12f64) || !near(pos[1usize], 2.5f64, 1.0e-12f64) { os.exit(4i32) }
    if motion.spline_trajectory(times[..], waypoints[..], 5usize, 2usize, m[..], scratch[..9usize]) != motion.TooSmall { os.exit(4i32) }
    if motion.spline_trajectory(waypoints[..], waypoints[..], 5usize, 2usize, m[..], scratch[..]) != motion.Invalid { os.exit(4i32) }

    // 5: pure pursuit and Stanley on a circle of radius 5.
    var circle: [80]f64 = zero
    var k = 0usize
    while k < 40usize {
        let angle = 2.0f64 * pi * f64(k) / 40.0f64
        circle[2usize * k] = 5.0f64 * math.cos[f64](angle)
        circle[2usize * k + 1usize] = 5.0f64 * math.sin[f64](angle)
        k += 1usize
    }
    let pose = kin.pose(4.6f64, 0.8f64, pi / 2.0f64 + 0.1f64)
    let (steering, curvature, pp_status) = motion.pure_pursuit(pose, circle[..], 1.5f64, 0.8f64)
    if pp_status != ok || !near(steering, 0.11049979979691162f64, 1.0e-12f64) || !near(curvature, 0.13868968630808087f64, 1.0e-12f64) { os.exit(5i32) }
    let (stanley_steer, stanley_status) = motion.stanley(pose, circle[..], 0.5f64, 1.2f64)
    if stanley_status != ok || !near(stanley_steer, 0.0f64 - 0.0030560032063410847f64, 1.0e-12f64) { os.exit(5i32) }
    let (_, _, pp_empty) = motion.pure_pursuit(pose, circle[..0usize], 1.5f64, 0.8f64)
    if pp_empty != motion.Invalid { os.exit(5i32) }

    // 6: dynamic window.
    let obstacles: [8]f64 = [8]f64{ 1.0, 0.2, 1.5, -0.5, 2.0, 0.8, 0.5, 1.0 }
    let params = motion.DwaParams { v_min: 0.0f64, v_max: 1.0f64, omega_max: 1.5f64, a_max: 0.5f64, alpha_max: 2.0f64, dt: 0.1f64, horizon: 2.0f64, v_samples: 6usize, omega_samples: 11usize, heading_weight: 1.0f64, clearance_weight: 0.8f64, velocity_weight: 0.5f64, radius: 0.3f64, clearance_cap: 1.0f64 }
    let dwa_state = motion.DwaState { x: 0.0f64, y: 0.0f64, theta: 0.0f64, v: 0.5f64, omega: 0.0f64 }
    let (dwa_v, dwa_w) = motion.dynamic_window(dwa_state, 3.0f64, 0.5f64, obstacles[..], params)
    if !near(dwa_v, 0.45f64, 1.0e-12f64) || !near(dwa_w, 0.0f64 - 0.12f64, 1.0e-12f64) { os.exit(6i32) }

    // 7: velocity obstacles.
    let me = motion.agent(0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.5f64, 1.0f64, 0.0f64, 1.5f64)
    var others: [2]motion.Agent = zero
    others[0usize] = motion.agent(3.0f64, 0.0f64, 0.0f64 - 1.0f64, 0.0f64, 0.5f64, 0.0f64, 0.0f64, 1.5f64)
    others[1usize] = motion.agent(2.0f64, 2.0f64, 0.0f64, 0.0f64 - 1.0f64, 0.5f64, 0.0f64, 0.0f64, 1.5f64)
    var candidates: [20]f64 = zero
    k = 0usize
    while k < 9usize {
        let angle = 0.0f64 - pi / 2.0f64 + pi * f64(k) / 8.0f64
        candidates[2usize * k] = math.cos[f64](angle)
        candidates[2usize * k + 1usize] = math.sin[f64](angle)
        k += 1usize
    }
    if motion.velocity_obstacles(me, others[..], candidates[..], 3.0f64) != 2usize { os.exit(7i32) }
    if motion.velocity_obstacles(me, others[..], candidates[..], 0.5f64) != 4usize { os.exit(7i32) }

    // 8: ORCA, four agents on a circle (nearly symmetric) and an overlapping case.
    var agents: [4]motion.Agent = zero
    k = 0usize
    while k < 4usize {
        let angle = pi / 4.0f64 + pi / 2.0f64 * f64(k)
        let b = angle + 0.03f64 * f64(k)
        agents[k] = motion.agent(4.0f64 * math.cos[f64](angle), 4.0f64 * math.sin[f64](angle), 0.0f64 - 0.9f64 * math.cos[f64](b), 0.0f64 - 0.9f64 * math.sin[f64](b), 0.6f64, 0.0f64 - math.cos[f64](b), 0.0f64 - math.sin[f64](b), 1.2f64)
        k += 1usize
    }
    let orca_want: [8]f64 = [8]f64{ -0.5096940162386658, -0.7393896783332453, 0.7341552703172793, -0.46938435136435186, 0.47213098610331444, 0.7376982000751645, -0.7717183004526308, 0.4676928731062712 }
    var out: [2]f64 = zero
    k = 0usize
    while k < 4usize {
        if motion.orca(agents[..], k, 8.0f64, 0.25f64, out[..], scratch[..]) != ok { os.exit(8i32) }
        if !near(out[0usize], orca_want[2usize * k], 1.0e-9f64) || !near(out[1usize], orca_want[2usize * k + 1usize], 1.0e-9f64) { os.exit(8i32) }
        k += 1usize
    }
    agents[0usize] = motion.agent(0.0f64, 0.0f64, 0.5f64, 0.0f64, 0.5f64, 1.0f64, 0.0f64, 1.0f64)
    agents[1usize] = motion.agent(0.7f64, 0.1f64, 0.0f64 - 0.5f64, 0.0f64, 0.5f64, 0.0f64 - 1.0f64, 0.0f64, 1.0f64)
    agents[2usize] = motion.agent(0.2f64, 0.8f64, 0.0f64, 0.0f64 - 0.5f64, 0.5f64, 0.0f64, 0.0f64 - 1.0f64, 1.0f64)
    agents[3usize] = motion.agent(0.3f64, 0.0f64 - 0.7f64, 0.0f64, 0.5f64, 0.5f64, 0.0f64, 1.0f64, 1.0f64)
    if motion.orca(agents[..], 0usize, 2.0f64, 0.1f64, out[..], scratch[..]) != ok { os.exit(8i32) }
    if !near(out[0usize], 0.0f64 - 0.9986858969178134f64, 1.0e-9f64) || !near(out[1usize], 0.051249188261511924f64, 1.0e-9f64) { os.exit(8i32) }
    if motion.orca(agents[..], 0usize, 2.0f64, 0.1f64, out[..], scratch[..31usize]) != motion.TooSmall { os.exit(8i32) }
    if motion.orca(agents[..], 4usize, 2.0f64, 0.1f64, out[..], scratch[..]) != motion.Invalid { os.exit(8i32) }

    // 9: potential field and the elastic band.
    let (fx, fy) = motion.potential_field(0.5f64, 0.3f64, 3.0f64, 2.0f64, obstacles[..], 0.8f64, 0.2f64, 1.2f64)
    if !near(fx, 1.1492874153837263f64, 1.0e-12f64) || !near(fy, 1.2871881923362771f64, 1.0e-12f64) { os.exit(9i32) }
    var band: [24]f64 = zero
    k = 0usize
    while k < 12usize {
        band[2usize * k] = 0.25f64 * f64(k)
        band[2usize * k + 1usize] = 0.15f64 * f64(k)
        if k >= 3usize && k <= 8usize { band[2usize * k + 1usize] += 0.4f64 }
        k += 1usize
    }
    motion.elastic_band(band[..], obstacles[..], 30usize, 0.2f64, 0.01f64, 0.6f64)
    var band_hash = 0.0f64
    k = 0usize
    while k < 24usize {
        band_hash += f64(k + 1usize) * band[k]
        k += 1usize
    }
    if !near(band_hash, 462.8859604065826f64, 1.0e-9f64) || !near(band[6usize], 0.7820400722195994f64, 1.0e-9f64) || !near(band[7usize], 0.6169669349459348f64, 1.0e-9f64) { os.exit(9i32) }
    if band[0usize] != 0.0f64 || !near(band[22usize], 2.75f64, 1.0e-12f64) { os.exit(9i32) }

    try io.print("robot motion ok\n")
    ret ok
}
