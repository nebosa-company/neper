"""Reads the hinted points of a tap font's glyphs back from the atlases GDI drew (see tapfont.py).

python tapread.py <src.ttf> <low.bgra> <high.bgra> <out.hinted.gz>

`low.bgra` is the atlas drawn with GLYPHS_READER=1 (the six low bits of every coordinate), `high.bgra` the one drawn with GLYPHS_READER=2
(the whole pixels + 16). The result, one line per glyph:

    code npoints x0 y0 x1 y1 ...        (26.6 pixels, every point of the glyph in the order of its program, composites flattened, then
                                         the four phantom points: left, right, top, bottom)

These are the zone coordinates after the glyph's program, which is what GDI rasterises after moving the left phantom point to the pen
(x - x_left_phantom): rendered that way they give the oracle's pixels exactly.
"""
import gzip
import struct
import sys
import os

import numpy as np
from fontTools.ttLib import TTFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tapfont import BITS, DOT, point_count, slot_origin

LEVEL = {255: 0, 219: 1, 182: 2, 144: 3, 102: 4, 58: 5, 0: 6}


def load(path):
    d = open(path, "rb").read()
    w, h, cw, ch, asc, pad = struct.unpack("<6i", d[:24])
    a = np.frombuffer(d[24:], np.uint8).reshape(h, w, 4)[:, :, 2::-1]
    lut = np.full(256, -1, np.int8)
    for v, k in LEVEL.items():
        lut[v] = k
    return lut[np.ascontiguousarray(a)].astype(int), (cw, ch, asc, pad)


def read_cell(cell, meta, n):
    """-> a list of n (x, y) values of the six bits, None for a coordinate that could not be decoded"""
    cw, ch, asc, pad = meta
    base = asc + pad
    pts = []
    for p in range(n):
        vals = []
        for axis in range(2):
            v = 0
            ok = True
            for b in range(BITS):
                s = (p * 2 + axis) * BITS + b
                sx, sy = slot_origin(s)
                res = []
                for shift in (0, 3):
                    cx = pad + int(sx + DOT / 2)
                    r = int(sy + shift + DOT / 2)
                    row = base - 1 - r
                    box = cell[row - 1:row + 2, cx - 1:cx + 2, 1]  # the G stripe around the dot's centre
                    res.append(int(box.max()) if box.size else -1)
                if res[1] >= 5 and res[0] < 5:
                    v |= 1 << b
                elif not (res[0] >= 5 and res[1] < 5):
                    ok = False
            vals.append(v if ok else None)
        pts.append(tuple(vals))
    return pts


def read_values(lo, hi, meta, n):
    a = read_cell(lo, meta, n)
    b = read_cell(hi, meta, n)
    out = []
    for (lx, ly), (hx, hy) in zip(a, b):
        out.append(tuple(None if l is None or h is None else ((h - 16) << 6) | l for l, h in ((lx, hx), (ly, hy))))
    return out


def main():
    src, low, high, out = sys.argv[1:5]
    font = TTFont(src)
    glyf, cmap = font["glyf"], font.getBestCmap()
    klo, meta = load(low)
    khi, _ = load(high)
    cw, ch, asc, pad = meta
    lines = []
    bad = 0
    for code in list(range(32, 127)) + list(range(160, 256)):
        if code not in cmap:
            continue
        n = point_count(glyf, cmap[code])
        if n == 4:
            continue
        r, c = divmod(code - 32, 16)
        sl = (slice(r * ch, (r + 1) * ch), slice(c * cw, (c + 1) * cw))
        vals = read_values(klo[sl], khi[sl], meta, n)
        if any(v is None for pt in vals for v in pt):
            bad += 1
            continue
        lines.append("%d %d %s" % (code, n, " ".join("%d %d" % pt for pt in vals)))
    with gzip.open(out, "wt", encoding="ascii", compresslevel=9) as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %d glyphs read, %d unreadable" % (os.path.basename(out), len(lines), bad))


if __name__ == "__main__":
    main()
