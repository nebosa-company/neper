// `e.robot.kinematics`: odometry over 100 LCG tick pairs, dead reckoning and
// Ackermann integration, the drive conversions round-trip, one DH transform,
// forward kinematics of a 3-link planar arm and a 6-DOF PUMA-like arm, and
// both IK loops reaching a target with the replica's joint angles. Each check
// exits with its own code; every expected value comes from a numpy replica.

use e.io
use e.mem
use e.os
use e.robot.kinematics as kin

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: odometry over 100 LCG tick pairs.
    var state = 7u64
    var p = kin.pose(0.0f64, 0.0f64, 0.0f64)
    var i = 0usize
    while i < 100usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let left = i64((state >> 33u32) % 401u64) - 200i64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let right = i64((state >> 33u32) % 401u64) - 200i64
        p = kin.odometry(p, left, right, 1000.0f64, 0.3f64)
        i += 1usize
    }
    if !near(p.x, 0.8867951834340142f64, 1.0e-9f64) || !near(p.y, 0.10323949673277415f64, 1.0e-9f64) || !near(p.theta, 2.4700000000000015f64, 1.0e-9f64) { os.exit(1i32) }

    // 2: dead reckoning and Ackermann steps.
    var q = kin.pose(1.0f64, 2.0f64, 0.5f64)
    i = 0usize
    while i < 50usize {
        q = kin.dead_reckon(q, 0.7f64, 0.3f64, 0.1f64)
        i += 1usize
    }
    if !near(q.x, 2.0030344058501144f64, 1.0e-9f64) || !near(q.y, 5.018701929687539f64, 1.0e-9f64) || !near(q.theta, 2.0000000000000013f64, 1.0e-9f64) { os.exit(2i32) }
    q = kin.pose(0.0f64, 0.0f64, 0.0f64)
    i = 0usize
    while i < 50usize {
        q = kin.ackermann_step(q, 1.5f64, 0.2f64, 2.5f64, 0.05f64)
        i += 1usize
    }
    if !near(q.x, 3.692481815775063f64, 1.0e-9f64) || !near(q.y, 0.5657429111076896f64, 1.0e-9f64) || !near(q.theta, 0.3040650532630086f64, 1.0e-9f64) { os.exit(2i32) }
    let (omega, radius) = kin.ackermann(1.5f64, 0.2f64, 2.5f64)
    if !near(omega, 0.1216260213052035f64, 1.0e-12f64) || !near(radius, 12.332887188967232f64, 1.0e-9f64) { os.exit(2i32) }
    let (_, straight) = kin.ackermann(1.5f64, 0.0f64, 2.5f64)
    if straight != 0.0f64 { os.exit(2i32) }

    // 3: drive conversions round-trip.
    let (vl, vr) = kin.differential_drive(1.2f64, 0.4f64, 0.5f64)
    if !near(vl, 1.1f64, 1.0e-12f64) || !near(vr, 1.3f64, 1.0e-12f64) { os.exit(3i32) }
    let (v, w) = kin.differential_drive_wheels(vl, vr, 0.5f64)
    if !near(v, 1.2f64, 1.0e-12f64) || !near(w, 0.4f64, 1.0e-12f64) { os.exit(3i32) }

    // 4: one DH transform.
    var t: [16]f64 = zero
    if kin.dh_transform(0.3f64, 0.4f64, 0.5f64, 0.6f64, t[..]) != ok { os.exit(4i32) }
    let dh_want: [16]f64 = [16]f64{ 0.955336489125606, -0.24390335148307188, 0.16686326042747077, 0.477668244562803, 0.29552020666133955, 0.7884732286981352, -0.5394235581444115, 0.14776010333066977, 0.0, 0.5646424733950354, 0.8253356149096783, 0.4, 0.0, 0.0, 0.0, 1.0 }
    i = 0usize
    while i < 16usize {
        if !near(t[i], dh_want[i], 1.0e-12f64) { os.exit(4i32) }
        i += 1usize
    }
    if kin.dh_transform(0.3f64, 0.4f64, 0.5f64, 0.6f64, t[..15usize]) != kin.TooSmall { os.exit(4i32) }

    // 5: forward kinematics, planar and PUMA.
    var planar: [3]kin.Dh = zero
    planar[0usize] = kin.dh(0.0f64, 0.0f64, 1.0f64, 0.0f64)
    planar[1usize] = kin.dh(0.0f64, 0.0f64, 0.8f64, 0.0f64)
    planar[2usize] = kin.dh(0.0f64, 0.0f64, 0.5f64, 0.0f64)
    var joints3: [3]f64 = [3]f64{ 0.3, -0.4, 0.5 }
    var scratch: [128]f64 = zero
    if kin.forward(planar[..], joints3[..], t[..], scratch[..]) != ok { os.exit(5i32) }
    if !near(t[3usize], 2.2118703183494692f64, 1.0e-9f64) || !near(t[7usize], 0.4103626444982022f64, 1.0e-9f64) || t[11usize] != 0.0f64 { os.exit(5i32) }
    if !near(t[0usize], 0.9210609940028851f64, 1.0e-9f64) || !near(t[4usize], 0.3894183423086504f64, 1.0e-9f64) { os.exit(5i32) }
    let half_pi = 1.5707963267948966f64
    var puma: [6]kin.Dh = zero
    puma[0usize] = kin.dh(0.0f64, 0.6718f64, 0.0f64, 0.0f64 - half_pi)
    puma[1usize] = kin.dh(0.0f64, 0.0f64, 0.4318f64, 0.0f64)
    puma[2usize] = kin.dh(0.0f64, 0.15f64, 0.0203f64, 0.0f64 - half_pi)
    puma[3usize] = kin.dh(0.0f64, 0.4318f64, 0.0f64, half_pi)
    puma[4usize] = kin.dh(0.0f64, 0.0f64, 0.0f64, 0.0f64 - half_pi)
    puma[5usize] = kin.dh(0.0f64, 0.0f64, 0.0f64, 0.0f64)
    var joints6: [6]f64 = [6]f64{ 0.1, -0.5, 0.3, 0.7, -0.2, 0.4 }
    if kin.forward(puma[..], joints6[..], t[..], scratch[..]) != ok { os.exit(5i32) }
    let puma_want: [16]f64 = [16]f64{ 0.48025898962464814, -0.8022126965857334, 0.3546915453198149, 0.46722482028162854, -0.8356082541946667, -0.5413891477875412, -0.09304104567136742, 0.1976319868932091, 0.26666486158932456, -0.2516993843745472, -0.9303425559969942, 0.45965618667258645, 0.0, 0.0, 0.0, 1.0 }
    i = 0usize
    while i < 16usize {
        if !near(t[i], puma_want[i], 1.0e-9f64) { os.exit(5i32) }
        i += 1usize
    }
    if kin.forward(puma[..], joints6[..], t[..], scratch[..31usize]) != kin.TooSmall { os.exit(5i32) }

    // 6: Jacobian-transpose IK on the planar arm.
    let goal3: [3]f64 = [3]f64{ 0.5495529447687186, 1.7959060391526764, 0.0 }
    joints3 = [3]f64{ 0.3, 0.5, 0.2 }
    let (jt_error, jt_status) = kin.ik_jacobian(planar[..], joints3[..], goal3[..], 200usize, 0.2f64, scratch[..])
    if jt_status != ok || jt_error > 1.0e-4f64 || !near(jt_error, 4.5799050237298015e-08f64, 1.0e-9f64) { os.exit(6i32) }
    if !near(joints3[0usize], 0.5947908144228231f64, 1.0e-6f64) || !near(joints3[1usize], 1.0191730783146138f64, 1.0e-6f64) || !near(joints3[2usize], 0.46706351114510614f64, 1.0e-6f64) { os.exit(6i32) }
    let (_, jt_room) = kin.ik_jacobian(planar[..], joints3[..], goal3[..], 1usize, 0.2f64, scratch[..62usize])
    if jt_room != kin.TooSmall { os.exit(6i32) }

    // 7: damped least-squares IK on the PUMA.
    let goal6: [3]f64 = [3]f64{ 0.3137365297874799, 0.2540628217207097, 0.40828142328389305 }
    joints6 = [6]f64{ 0.0, -0.2, 0.3, 0.2, 0.1, 0.0 }
    let (dls_error, dls_status) = kin.ik_damped_least_squares(puma[..], joints6[..], goal6[..], 30usize, 0.05f64, scratch[..])
    if dls_status != ok || dls_error > 1.0e-4f64 { os.exit(7i32) }
    if !near(joints6[0usize], 0.3f64, 1.0e-6f64) || !near(joints6[1usize], 0.0f64 - 0.4f64, 1.0e-6f64) || !near(joints6[2usize], 0.5f64, 1.0e-6f64) { os.exit(7i32) }
    if !near(joints6[3usize], 0.2f64, 1.0e-6f64) || !near(joints6[4usize], 0.1f64, 1.0e-6f64) || !near(joints6[5usize], 0.0f64, 1.0e-6f64) { os.exit(7i32) }

    try io.print("robot kinematics ok\n")
    ret ok
}
