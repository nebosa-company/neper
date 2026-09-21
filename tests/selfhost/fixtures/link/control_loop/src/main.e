// `e.control`: a PID drives a first-order plant to the state Python reaches,
// back-calculation anti-windup overshoots less than a bare clamp, the
// Ziegler-Nichols table is exact, a bang-bang thermostat switches as often
// as the model, feedforward plus feedback lands where Python does, the LQR
// gains of a double integrator and a two-input system match a numpy Riccati
// iteration, Ackermann places the poles scipy places, the observer gain
// comes from the dual placement and its estimate converges, sliding mode
// saturates in the boundary layer, and short storage is refused. Each check
// exits with its own code.

use e.control
use e.io
use e.math
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool { ret math.abs[f64](x - want) <= eps }

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: PID on x' = -x + 2u, Euler dt 0.01, 500 steps.
    var p = control.pid(2.0f64, 1.5f64, 0.1f64)
    var x = 0.0f64
    var step = 0usize
    while step < 500usize {
        let u = control.pid_step(&p, 1.0f64, x, 0.01f64)
        x += 0.01f64 * (0.0f64 - x + 2.0f64 * u)
        step += 1usize
    }
    if !near(x, 0.99771753697900456f64, 1.0e-9f64) || !near(p.integral, 0.33016490907903601f64, 1.0e-9f64) { os.exit(1i32) }

    // 2: anti-windup by back-calculation against a bare clamp.
    var aw = control.pid_anti_windup(8.0f64, 6.0f64, 0.0f64, -0.6f64, 0.6f64, 1.0f64)
    var clamped = control.pid_anti_windup(8.0f64, 6.0f64, 0.0f64, -0.6f64, 0.6f64, 0.0f64)
    x = 0.0f64
    var y = 0.0f64
    var peak_aw = 0.0f64
    var peak_clamped = 0.0f64
    step = 0usize
    while step < 500usize {
        let u = control.pid_anti_windup_step(&aw, 1.0f64, x, 0.01f64)
        if u > 0.6f64 || u < -0.6f64 { os.exit(2i32) }
        x += 0.01f64 * (0.0f64 - x + 2.0f64 * u)
        if x > peak_aw { peak_aw = x }
        let v = control.pid_anti_windup_step(&clamped, 1.0f64, y, 0.01f64)
        y += 0.01f64 * (0.0f64 - y + 2.0f64 * v)
        if y > peak_clamped { peak_clamped = y }
        step += 1usize
    }
    if !near(x, 0.98136546878131581f64, 1.0e-9f64) || !near(aw.integral, 0.058080302135858575f64, 1.0e-9f64) { os.exit(2i32) }
    if !near(y, 1.1059264879382498f64, 1.0e-9f64) || !near(peak_clamped, 1.1824626544546002f64, 1.0e-9f64) { os.exit(2i32) }
    if peak_aw >= peak_clamped { os.exit(2i32) }
    control.pid_reset(&aw)
    if aw.integral != 0.0f64 || aw.previous_error != 0.0f64 { os.exit(2i32) }

    // 3: the Ziegler-Nichols table.
    let (kp_p, ki_p, kd_p) = control.pid_tune_ziegler_nichols(3.0f64, 0.8f64, .P)
    if kp_p != 1.5f64 || ki_p != 0.0f64 || kd_p != 0.0f64 { os.exit(3i32) }
    let (kp_pi, ki_pi, kd_pi) = control.pid_tune_ziegler_nichols(3.0f64, 0.8f64, .PI)
    if !near(kp_pi, 1.35f64, 1.0e-12f64) || !near(ki_pi, 2.025f64, 1.0e-12f64) || kd_pi != 0.0f64 { os.exit(3i32) }
    let (kp_pid, ki_pid, kd_pid) = control.pid_tune_ziegler_nichols(3.0f64, 0.8f64, .PID)
    if !near(kp_pid, 1.8f64, 1.0e-12f64) || !near(ki_pid, 4.5f64, 1.0e-12f64) || !near(kd_pid, 0.18f64, 1.0e-12f64) { os.exit(3i32) }

    // 4: a thermostat, heating 0.3 a step when on and cooling 0.2 when off.
    var temperature = 15.0f64
    var on = false
    var switches = 0usize
    step = 0usize
    while step < 200usize {
        let want = control.bang_bang(temperature, 20.0f64, 1.0f64, on)
        if want != on { switches += 1usize }
        on = want
        if on { temperature += 0.3f64 } else { temperature -= 0.2f64 }
        step += 1usize
    }
    if switches != 20usize || on || !near(temperature, 21.0f64, 1.0e-9f64) { os.exit(4i32) }

    // 5: feedforward with the plant's inverse gain plus a feedback PID.
    var ff = control.Feedforward { gain: 0.5f64, feedback: control.pid(1.0f64, 0.5f64, 0.0f64) }
    x = 0.0f64
    step = 0usize
    while step < 500usize {
        let u = control.feedforward(&ff, 1.0f64, x, 0.01f64)
        x += 0.01f64 * (0.0f64 - x + 2.0f64 * u)
        step += 1usize
    }
    if !near(x, 1.025157248205864f64, 1.0e-9f64) || !near(ff.feedback.integral, 0.066161149655747736f64, 1.0e-9f64) { os.exit(5i32) }

    // 6: LQR of a double integrator (dt 0.1, Q = I, R = 1).
    var scratch: [256]f64 = zero
    var a2: [4]f64 = zero
    a2[0usize] = 1.0f64
    a2[1usize] = 0.1f64
    a2[3usize] = 1.0f64
    var b2: [2]f64 = zero
    b2[0usize] = 0.005f64
    b2[1usize] = 0.1f64
    var q2: [4]f64 = zero
    q2[0usize] = 1.0f64
    q2[3usize] = 1.0f64
    var r1: [1]f64 = zero
    r1[0usize] = 1.0f64
    var k2: [2]f64 = zero
    let (used, lqr_error) = control.lqr(a2[..], b2[..], q2[..], r1[..], 2usize, 1usize, k2[..], scratch[..], 10000usize, 1.0e-12f64)
    if lqr_error != ok || used != 174usize { os.exit(6i32) }
    if !near(k2[0usize], 0.9170745631136652f64, 1.0e-9f64) || !near(k2[1usize], 1.6355961850461285f64, 1.0e-9f64) { os.exit(6i32) }
    let (_, lqr_short) = control.lqr(a2[..], b2[..], q2[..], r1[..], 2usize, 1usize, k2[..], scratch[..30usize], 10usize, 1.0e-12f64)
    if lqr_short != control.TooSmall { os.exit(6i32) }

    // 7: LQR with three states and two inputs.
    var a3: [9]f64 = zero
    a3[0usize] = 1.0f64
    a3[1usize] = 0.1f64
    a3[4usize] = 1.0f64
    a3[5usize] = 0.1f64
    a3[6usize] = 0.02f64
    a3[8usize] = 0.9f64
    var b3: [6]f64 = zero
    b3[1usize] = 0.05f64
    b3[2usize] = 0.1f64
    b3[5usize] = 0.1f64
    var q3: [9]f64 = zero
    q3[0usize] = 1.0f64
    q3[4usize] = 0.5f64
    q3[8usize] = 0.2f64
    var r3: [4]f64 = zero
    r3[0usize] = 0.5f64
    r3[3usize] = 1.0f64
    var k3: [6]f64 = zero
    let (used3, lqr3_error) = control.lqr(a3[..], b3[..], q3[..], r3[..], 3usize, 2usize, k3[..], scratch[..], 10000usize, 1.0e-12f64)
    if lqr3_error != ok || used3 != 150usize { os.exit(7i32) }
    if !near(k3[0usize], 0.95867355723449699f64, 1.0e-9f64) || !near(k3[1usize], 1.5489527629084809f64, 1.0e-9f64) || !near(k3[2usize], 0.57120308640278639f64, 1.0e-9f64) { os.exit(7i32) }
    if !near(k3[3usize], 0.63153847929067608f64, 1.0e-9f64) || !near(k3[4usize], 0.53646901804704283f64, 1.0e-9f64) || !near(k3[5usize], 0.29181553158297879f64, 1.0e-9f64) { os.exit(7i32) }

    // 8: pole placement, two real poles then a conjugate pair and a real one.
    var ap2: [4]f64 = zero
    ap2[0usize] = 1.0f64
    ap2[1usize] = 1.0f64
    ap2[3usize] = 1.0f64
    var bp2: [2]f64 = zero
    bp2[0usize] = 0.5f64
    bp2[1usize] = 1.0f64
    var re2: [2]f64 = zero
    re2[0usize] = 0.5f64
    re2[1usize] = 0.6f64
    var im2: [2]f64 = zero
    if control.pole_placement(ap2[..], bp2[..], 2usize, re2[..], im2[..], k2[..], scratch[..]) != ok { os.exit(8i32) }
    if !near(k2[0usize], 0.2f64, 1.0e-9f64) || !near(k2[1usize], 0.8f64, 1.0e-9f64) { os.exit(8i32) }
    var ap3: [9]f64 = zero
    ap3[0usize] = 1.0f64
    ap3[1usize] = 0.1f64
    ap3[4usize] = 1.0f64
    ap3[5usize] = 0.1f64
    ap3[8usize] = 1.0f64
    var bp3: [3]f64 = zero
    bp3[2usize] = 0.1f64
    var re3: [3]f64 = zero
    re3[0usize] = 0.5f64
    re3[1usize] = 0.5f64
    re3[2usize] = 0.3f64
    var im3: [3]f64 = zero
    im3[0usize] = 0.2f64
    im3[1usize] = -0.2f64
    var kp3: [3]f64 = zero
    if control.pole_placement(ap3[..], bp3[..], 3usize, re3[..], im3[..], kp3[..], scratch[..]) != ok { os.exit(8i32) }
    if !near(kp3[0usize], 203.0f64, 1.0e-8f64) || !near(kp3[1usize], 99.0f64, 1.0e-8f64) || !near(kp3[2usize], 17.0f64, 1.0e-8f64) { os.exit(8i32) }
    // An uncontrollable pair: B in the kernel of every power's reach.
    var b_dead: [3]f64 = zero
    b_dead[0usize] = 1.0f64
    if control.pole_placement(ap3[..], b_dead[..], 3usize, re3[..], im3[..], kp3[..], scratch[..]) != control.Singular { os.exit(8i32) }

    // 9: the observer gain from the dual system, then the estimate converges.
    var c3: [3]f64 = zero
    c3[0usize] = 1.0f64
    var obs_re: [3]f64 = zero
    obs_re[0usize] = 0.2f64
    obs_re[1usize] = 0.3f64
    obs_re[2usize] = 0.4f64
    var l3: [3]f64 = zero
    if control.observer_gain(ap3[..], c3[..], 3usize, obs_re[..], im2[..0usize], l3[..], scratch[..]) != control.TooSmall { os.exit(9i32) }
    var obs_im: [3]f64 = zero
    if control.observer_gain(ap3[..], c3[..], 3usize, obs_re[..], obs_im[..], l3[..], scratch[..]) != ok { os.exit(9i32) }
    if !near(l3[0usize], 2.1f64, 1.0e-8f64) || !near(l3[1usize], 14.6f64, 1.0e-8f64) || !near(l3[2usize], 33.6f64, 1.0e-8f64) { os.exit(9i32) }
    var truth: [3]f64 = zero
    truth[0usize] = 1.0f64
    truth[1usize] = -0.5f64
    truth[2usize] = 0.25f64
    var estimate: [3]f64 = zero
    var input: [1]f64 = zero
    var output: [1]f64 = zero
    var next_truth: [3]f64 = zero
    step = 0usize
    while step < 30usize {
        output[0usize] = truth[0usize]
        if control.observer_step(estimate[..], ap3[..], bp3[..], c3[..], l3[..], 3usize, 1usize, 1usize, input[..], output[..], scratch[..]) != ok { os.exit(9i32) }
        var i = 0usize
        while i < 3usize {
            next_truth[i] = ap3[i * 3usize] * truth[0usize] + ap3[i * 3usize + 1usize] * truth[1usize] + ap3[i * 3usize + 2usize] * truth[2usize] + bp3[i] * input[0usize]
            i += 1usize
        }
        truth[0usize] = next_truth[0usize]
        truth[1usize] = next_truth[1usize]
        truth[2usize] = next_truth[2usize]
        input[0usize] = 0.1f64 * (f64(step % 5usize) - 2.0f64)
        step += 1usize
    }
    if !near(estimate[0usize], 0.50929999997738518f64, 1.0e-8f64) || !near(estimate[1usize], 0.19199999966076114f64, 1.0e-8f64) || !near(estimate[2usize], 0.22999999873346108f64, 1.0e-8f64) { os.exit(9i32) }
    if !near(estimate[0usize], truth[0usize], 1.0e-6f64) || !near(estimate[1usize], truth[1usize], 1.0e-6f64) || !near(estimate[2usize], truth[2usize], 1.0e-6f64) { os.exit(9i32) }
    if control.observer_step(estimate[..], ap3[..], bp3[..], c3[..], l3[..], 3usize, 1usize, 1usize, input[..], output[..], scratch[..9usize]) != control.TooSmall { os.exit(9i32) }

    // 10: sliding mode: the sign outside the boundary layer, linear inside.
    if control.sliding_mode(1.0f64, 0.5f64, 2.0f64, 3.0f64, 0.0f64) != -3.0f64 { os.exit(10i32) }
    if control.sliding_mode(-1.0f64, 0.5f64, 2.0f64, 3.0f64, 0.0f64) != 3.0f64 { os.exit(10i32) }
    if control.sliding_mode(0.0f64, 0.0f64, 2.0f64, 3.0f64, 0.0f64) != 0.0f64 { os.exit(10i32) }
    if !near(control.sliding_mode(0.1f64, 0.05f64, 2.0f64, 3.0f64, 1.0f64), -0.75f64, 1.0e-12f64) { os.exit(10i32) }
    if control.sliding_mode(1.0f64, 0.5f64, 2.0f64, 3.0f64, 1.0f64) != -3.0f64 { os.exit(10i32) }

    try io.print("control ok\n")
    ret ok
}
