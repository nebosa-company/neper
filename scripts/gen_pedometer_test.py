#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/algo_pedometer/src/main.e: synthetic accelerometer walks (gravity, a stride
oscillation at a given cadence, a second harmonic, sway and noise, 25 Hz) of known step counts fed to
e.algo.pedometer; the count must be within two per cent (plus one step) and the cadence class right; a phone lying
on a table counts nothing."""
import math
import random
from pathlib import Path

RATE = 25


def walk(seconds, cadence, amplitude, seed, noise=0.25):
    rng = random.Random(seed)
    n = int(seconds * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        stride = amplitude * math.sin(2 * math.pi * cadence * t)
        harmonic = 0.35 * amplitude * math.sin(2 * math.pi * 2 * cadence * t + 0.7)
        sway = 0.6 * math.sin(2 * math.pi * 0.3 * t)
        out.append(9.81 + stride + harmonic + sway + rng.gauss(0, noise))
    return out


cases = [
    ("walk_slow", walk(60, 1.6, 2.4, 1), 96, False),
    ("walk_normal", walk(60, 1.9, 3.0, 2), 114, False),
    ("walk_brisk", walk(45, 2.2, 3.4, 3), 99, False),
    ("run", walk(40, 2.9, 6.0, 4), 116, True),
    ("table", [9.81 + random.Random(5).gauss(0, 0.02) for _ in range(25 * 30)], 0, False),
]
lines = []
code = 0
for name, samples, expected, running in cases:
    code += 1
    values = ", ".join("%d" % round(v * 1000) for v in samples)
    lines.append('    let %s: [%d]i32 = [%d]i32{ %s }' % (name, len(samples), len(samples), values))
    lines.append('    if !check(%s[0usize..%dusize], %d, %s) { os.exit(%d) }' % (name, len(samples), expected, "true" if running else "false", code))
head = '''// `e.algo.pedometer`: synthetic accelerometer walks at 25 Hz of known cadence (gravity, a stride oscillation and its
// second harmonic, sway and noise; milli-m/s^2 as integers) counted within two per cent and one step, running told
// from walking by the cadence, and a phone on a table counting nothing. Every check has its own exit code.
use e.os
use e.algo.pedometer as ped

fn check(samples: []const i32, expected: usize, running: bool) -> bool {
    var p = ped.new(25usize)
    var i = 0usize
    while i < samples.len {
        let fed = ped.feed(&p, f64(samples[i]) / 1000.0f64)
        i += 1usize
    }
    let got = ped.steps(&p)
    var diff = got
    if expected > got { diff = expected - got } else { diff = got - expected }
    if diff * 50usize > expected + 50usize { ret false }
    if expected > 0usize && ped.is_running(&p) != running { ret false }
    ret true
}

fn main(args: []str) -> err {
'''
out = head + "\n".join(lines) + "\n    ret ok\n}\n"
out = out.replace("fn main(args: []str) -> err {", "fn main(a: *mem.Arena, args: []str) -> err {").replace("use e.os\n", "use e.os\nuse e.mem\n", 1)
dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/algo_pedometer/src/main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(out, encoding="utf-8", newline="\n")
print(dest, code, "cases", dest.stat().st_size, "bytes")
