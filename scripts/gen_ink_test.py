"""Reference numbers for tests/selfhost/fixtures/link/ui_ink (L099, D2844).

The fixture builds three strokes with formulas written here too, in doubles:

  A  40 samples, t = 1000 + 10 i, x = 5 i, y = 50 + 20 sin(0.3 i),
     pressure 0.2 + 0.6 i / 39, width 4
  B  11 samples on the line (0, 0) -> (100, 60), t = 2000 + 50 i, pressure i / 10, width 6
  C  one sample at (30, 30), t = 3000, pressure 1, width 8

and this prints their bounds, lengths, the decimated count of A at several
min_distance values (a model of the capture rule), replay counts, duration and hits.
"""
import math

A = [(5.0 * i, 50.0 + 20.0 * math.sin(0.3 * i), 0.2 + 0.6 * i / 39.0, 1000 + 10 * i) for i in range(40)]
B = [(10.0 * i, 6.0 * i, i / 10.0, 2000 + 50 * i) for i in range(11)]
C = [(30.0, 30.0, 1.0, 3000)]
STROKES = [(A, 4.0), (B, 6.0), (C, 8.0)]


def bounds(samples, width):
    xs = [s[0] for s in samples]
    ys = [s[1] for s in samples]
    pad = width / 2
    return (min(xs) - pad, min(ys) - pad, max(xs) - min(xs) + width, max(ys) - min(ys) + width)


def length(samples):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(samples, samples[1:]))


def kept(samples, min_distance):
    """Samples stored by begin + extend + end for a min_distance."""
    out = [samples[0]]
    for s in samples[1:-1]:
        if (s[0] - out[-1][0]) ** 2 + (s[1] - out[-1][1]) ** 2 < min_distance ** 2:
            continue
        out.append(s)
    last = samples[-1]
    if (last[0], last[1]) != (out[-1][0], out[-1][1]):
        out.append(last)
    return out


def seg_d2(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    cx, cy = ax + t * dx - px, ay + t * dy - py
    return cx * cx + cy * cy


def hit(px, py, radius):
    for i in reversed(range(len(STROKES))):
        samples, width = STROKES[i]
        reach = radius + width / 2
        for k in range(len(samples)):
            a = samples[k]
            b = samples[k + 1] if k + 1 < len(samples) else a
            if seg_d2(px, py, a[0], a[1], b[0], b[1]) <= reach * reach:
                return i
    return None


for name, (samples, width) in zip("ABC", STROKES):
    b = bounds(samples, width)
    print(name, "bounds x=%.4f y=%.4f w=%.4f h=%.4f" % b, "length=%.4f" % length(samples))
ext = [bounds(s, w) for s, w in STROKES]
x0 = min(e[0] for e in ext)
y0 = min(e[1] for e in ext)
x1 = max(e[0] + e[2] for e in ext)
y1 = max(e[1] + e[3] for e in ext)
print("extent x=%.4f y=%.4f w=%.4f h=%.4f" % (x0, y0, x1 - x0, y1 - y0))
for d in (0.0, 8.0, 12.0, 30.0):
    print("A kept at min_distance %.1f: %d" % (d, len(kept(A, d))))
origin = A[0][3]
for elapsed in (0, 105, 389, 1000, 1500, 2000):
    counts = [sum(1 for s in smp if 0 <= s[3] - origin <= elapsed) for smp, _ in STROKES]
    print("replay at", elapsed, counts)
print("duration", C[0][3] - origin)
for p, r in [((40.0, 50.0), 0.0), ((50.0, 30.0), 2.0), ((30.0, 30.0), 0.0), ((30.0, 30.0), -3.0), ((190.0, 190.0), 5.0), ((150.0, 90.0), 3.0)]:
    print("hit", p, r, hit(p[0], p[1], r))
print("widths A[0] %.4f A[39] %.4f B[5] %.4f" % (4 * (0.25 + 0.75 * A[0][2]), 4 * (0.25 + 0.75 * A[39][2]), 6 * (0.25 + 0.75 * B[5][2])))
