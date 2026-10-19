"""GDI's ClearType sampling model, checked against the probe-font atlases (docs/ui/looks/ref/windows-native/glyphs/NProbe*).

python -I scripts/winnative/probe_model.py [set ...]      (sets: xl xr yt yb xlt1..4 xlb1..4 hb vb pg dx dy; default all)

The model (also `add_glyph` in lib/e/gfx/cleartype.e):
- a pixel row is sampled on five horizontal lines at .1 .3 .5 .7 .9 of the row, weighted 1 2 3 2 1;
- a line is a plain inside test (nonzero winding) of six samples to the pixel, at (g + .5) / 6; a sample exactly on an edge is inside
  (left and right, bottom and top); curves are the quadratics they are;
- the coverage of a subpixel (R, G, B centred on the third of the pixel) is k = (sum of weights of the set samples in the six-sample
  window centred on it + 4) // 9, 0..6 (a pixel row of black on white then shows 255 219 182 144 102 58 0).
What it leaves out: drop-out control (a feature too thin to hold a sample, a horizontal sliver between two lines) turns a sample on in a
way not modelled here, so the thin-bar sets (hb, vb) are expected to differ; and this sketch is half-open in y (the Neper rasteriser takes
an edge exactly on a line both ways), so the one glyph per set with an edge on the .5 line differs. The sets xl xr yb xlt* xlb* pg dx dy
match exactly.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, "..", "..", "docs", "ui", "looks", "ref", "windows-native", "glyphs") + os.sep
LEVEL = {255: 0, 219: 1, 182: 2, 144: 3, 102: 4, 58: 5, 0: 6}
LINES = (0.1, 0.3, 0.5, 0.7, 0.9)
WEIGHTS = (1, 2, 3, 2, 1)


def segments(contour):
    """A TrueType contour of (x, y, on) in 1/64 px as lines and quadratics in px."""
    pts = [(x / 64.0, y / 64.0, on) for x, y, on in contour]
    first = next((i for i, p in enumerate(pts) if p[2]), None)
    if first is None:
        start = ((pts[0][0] + pts[-1][0]) / 2, (pts[0][1] + pts[-1][1]) / 2)
        seq = pts
    else:
        start = (pts[first][0], pts[first][1])
        seq = pts[first + 1:] + pts[:first + 1]
    cur, ctrl, out = start, None, []
    for p in seq:
        if p[2]:
            out.append(("L", cur, (p[0], p[1])) if ctrl is None else ("Q", cur, ctrl, (p[0], p[1])))
            ctrl, cur = None, (p[0], p[1])
        else:
            if ctrl is not None:
                mid = ((ctrl[0] + p[0]) / 2, (ctrl[1] + p[1]) / 2)
                out.append(("Q", cur, ctrl, mid))
                cur = mid
            ctrl = (p[0], p[1])
    if ctrl is not None:
        out.append(("Q", cur, ctrl, start))
    elif cur != start:
        out.append(("L", cur, start))
    return out


def crossings(segs, y):
    out = []
    for s in segs:
        if s[0] == "L":
            (x0, y0), (x1, y1) = s[1], s[2]
            if (y0 <= y) != (y1 <= y):
                out.append((x0 + (y - y0) / (y1 - y0) * (x1 - x0), 1 if y1 > y0 else -1))
        else:
            (x0, y0), (cx, cy), (x1, y1) = s[1], s[2], s[3]
            a, b, c = y0 - 2 * cy + y1, 2 * (cy - y0), y0 - y
            ts = []
            if abs(a) < 1e-12:
                if abs(b) > 1e-12:
                    ts = [-c / b]
            elif b * b - 4 * a * c >= 0:
                r = math.sqrt(b * b - 4 * a * c)
                ts = [(-b + r) / (2 * a), (-b - r) / (2 * a)]
            for t in ts:
                if 0 <= t < 1:
                    dy = 2 * (1 - t) * (cy - y0) + 2 * t * (y1 - cy)
                    if abs(dy) > 1e-12:
                        out.append((x0 * (1 - t) ** 2 + 2 * cx * t * (1 - t) + x1 * t * t, 1 if dy > 0 else -1))
    return out


def predict(contours, cw, ch, asc, pad):
    segs = [segments([(x + pad * 64, y, on) for x, y, on in c]) for c in contours]
    out = np.zeros((ch, cw, 3), int)
    for row in range(ch):
        r = pad + asc - 1 - row
        weight = np.zeros(6 * cw, int)
        for w, off in zip(WEIGHTS, LINES):
            cr = sorted(sum((crossings(s, r + off) for s in segs), []))
            wind = 0
            for i in range(len(cr) - 1):
                wind += cr[i][1]
                if wind:
                    g0 = max(math.ceil(cr[i][0] * 6 - 0.5 - 1e-9), 0)
                    g1 = min(math.floor(cr[i + 1][0] * 6 - 0.5 + 1e-9), 6 * cw - 1)
                    if g1 >= g0:
                        weight[g0:g1 + 1] += w  # one line covers a sample once
        for c in range(cw):
            for m in range(3):
                g0 = 6 * c + 2 * m - 2
                t = int(sum(weight[g] for g in range(g0, g0 + 6) if 0 <= g < 6 * cw))
                out[row, c, m] = (t + 4) // 9
    return out


def main():
    man = json.load(open(BASE + "probe.json"))
    want = sys.argv[1:]
    lut = np.full(256, -1, np.int8)
    for v, k in LEVEL.items():
        lut[v] = k
    atlas = open(BASE + "atlases.txt").read().split("\n")
    sizes = {l.split()[0]: tuple(map(int, l.split()[3:7])) for l in atlas if l.startswith("NProbe")}
    totals = {}
    for fi, font in enumerate(man):
        name = "%s-400-16-q5.000000-FFFFFF" % font["family"]
        cw, ch, asc, pad = sizes[name]
        rgb = np.array(Image.open(BASE + name + ".png").convert("RGB"))
        for gi, g in enumerate(font["glyphs"]):
            if want and g["set"] not in want:
                continue
            code = font["codes"][gi]
            r, c = divmod(code - 32, 16)
            cell = lut[rgb[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]].astype(int)
            bad = int((predict(g["contours"], cw, ch, asc, pad) != cell).sum())
            t = totals.setdefault(g["set"], [0, 0])
            t[0] += 1
            t[1] += bad > 0
    for s, (n, bad) in totals.items():
        print("%-5s %4d glyphs, %4d differ" % (s, n, bad))


main()
