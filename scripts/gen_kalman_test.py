#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/control_kalman/src/main.e (C162): e.control's two-state Kalman filter against
an independent Python implementation (the covariance as an explicit 2x2 matrix product, not the unrolled form), on a
simulated tilting device with a gyroscope bias and a noisy accelerometer; and noise_bias against statistics."""
import math
import random
import statistics
from pathlib import Path


def kalman(trace, q_angle, q_bias, r_measure, dt):
    # State x = [angle, bias]; F = [[1, -dt], [0, 1]]; B = [dt, 0]; H = [1, 0].
    angle, bias = trace[0][0], 0.0
    P = [[0.0, 0.0], [0.0, 0.0]]
    out = []
    for measured, rate in trace:
        angle = angle + dt * (rate - bias)
        F = [[1.0, -dt], [0.0, 1.0]]
        Q = [[q_angle * dt, 0.0], [0.0, q_bias * dt]]
        FP = [[sum(F[i][k] * P[k][j] for k in range(2)) for j in range(2)] for i in range(2)]
        P = [[sum(FP[i][k] * F[j][k] for k in range(2)) + Q[i][j] for j in range(2)] for i in range(2)]
        S = P[0][0] + r_measure
        K = [P[0][0] / S, P[1][0] / S]
        y = measured - angle
        angle += K[0] * y
        bias += K[1] * y
        P = [[P[i][j] - K[i] * P[0][j] for j in range(2)] for i in range(2)]
        out.append(angle)
    return out


def main():
    rng = random.Random(20261011)
    dt = 0.02
    n = 120
    trace = []
    truth = []
    for i in range(n):
        t = i * dt
        angle = 20.0 * math.sin(2 * math.pi * 0.4 * t)
        rate = 20.0 * 2 * math.pi * 0.4 * math.cos(2 * math.pi * 0.4 * t)
        truth.append(angle)
        trace.append((round(angle + rng.gauss(0, 1.5), 4), round(rate + 1.2 + rng.gauss(0, 0.3), 4)))
    q_angle, q_bias, r_measure = 0.001, 0.003, 0.03
    expected = kalman(trace, q_angle, q_bias, r_measure, dt)
    flat = [round(0.35 + rng.gauss(0, 0.08), 5) for _ in range(200)]
    mean = statistics.fmean(flat)
    sd = statistics.stdev(flat)

    def arr(name, values):
        return "    let %s: [%d]f64 = [%d]f64{ %s }\n" % (name, len(values), len(values), ", ".join(repr(float(v)) + "f64" for v in values))

    out = ["// `e.control`'s two-state Kalman filter against an independent Python implementation (the covariance as an\n",
           "// explicit 2x2 matrix product) on a tilting device with a gyroscope bias and a noisy accelerometer, and\n",
           "// `noise_bias` against statistics.fmean and statistics.stdev. Written by scripts/gen_kalman_test.py. Every check\n",
           "// has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.control as control\nuse e.math\n\n",
           "fn close(a: f64, b: f64, tolerance: f64) -> bool {\n    var d = a - b\n    if d < 0.0f64 { d = 0.0f64 - d }\n    ret d <= tolerance\n}\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    out.append(arr("measured", [m for m, r in trace]))
    out.append(arr("rate", [r for m, r in trace]))
    out.append(arr("want", expected))
    out.append(arr("flat", flat))
    out.append("    var k = control.kalman_new(%rf64, %rf64, %rf64)\n" % (q_angle, q_bias, r_measure))
    out.append("    control.kalman_start(&k, measured[0])\n")
    out.append("    var worst = 0.0f64\n    var i = 0usize\n")
    out.append("    while i < %dusize {\n" % n)
    out.append("        let got = control.kalman_step(&k, measured[i], rate[i], %rf64)\n" % dt)
    out.append("        var d = got - want[i]\n        if d < 0.0f64 { d = 0.0f64 - d }\n        if d > worst { worst = d }\n        i += 1usize\n    }\n")
    out.append("    if worst > 0.000001f64 { os.exit(1) }\n")
    out.append("    if !close(k.bias, %rf64, 0.00001f64) { os.exit(2) }\n" % 0.0)  # replaced below
    out.append("    let (mean, sd) = control.noise_bias(flat[0..])\n")
    out.append("    if !close(mean, %rf64, 0.0000001f64) { os.exit(3) }\n" % mean)
    out.append("    if !close(sd, %rf64, 0.0000001f64) { os.exit(4) }\n" % sd)
    out.append("    let (m0, s0) = control.noise_bias(flat[0..1])\n")
    out.append("    if m0 != 0.0f64 || s0 != 0.0f64 { os.exit(5) }\n")
    out.append("    ret ok\n}\n")
    text = "".join(out)
    # The final bias the independent implementation reaches, for check 2.
    angle, bias = trace[0][0], 0.0
    P = [[0.0, 0.0], [0.0, 0.0]]
    for m, r in trace:
        angle += dt * (r - bias)
        F = [[1.0, -dt], [0.0, 1.0]]
        Q = [[q_angle * dt, 0.0], [0.0, q_bias * dt]]
        FP = [[sum(F[i][k] * P[k][j] for k in range(2)) for j in range(2)] for i in range(2)]
        P = [[sum(FP[i][k] * F[j][k] for k in range(2)) + Q[i][j] for j in range(2)] for i in range(2)]
        S = P[0][0] + r_measure
        K = [P[0][0] / S, P[1][0] / S]
        y = m - angle
        angle += K[0] * y
        bias += K[1] * y
        P = [[P[i][j] - K[i] * P[0][j] for j in range(2)] for i in range(2)]
    text = text.replace("if !close(k.bias, 0.0f64, 0.00001f64)", "if !close(k.bias, %rf64, 0.00001f64)" % bias)
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/control_kalman/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")
    print("wrote", target, "final bias", bias, "mean", mean, "sd", sd)


main()
