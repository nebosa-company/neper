"""`python -I scripts/looks_x84_pairs.py look name [min]` (round 84, lane x): the colour pairs that meet along an edge of a sheet, with their
WCAG contrast, most frequent first (pairs seen fewer than `min` times, default 12, are skipped). The contrast of every drawn boundary of a
dark sheet in one list: frames, grips, rules, glyph cores (anti-aliased blends are rare pairs and fall under `min`)."""
import sys
from collections import Counter
import numpy as np
from PIL import Image

R = "D:/Temp/lanes/looks84-x/docs/ui/looks/"


def lum(c):
    v = [x / 255.0 for x in c]
    v = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in v]
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]


def cr(a, b):
    x, y = lum(a), lum(b)
    if x < y:
        x, y = y, x
    return (x + 0.05) / (y + 0.05)


def pairs(path, floor=12):
    im = np.array(Image.open(path).convert("RGB"))
    key = (im[..., 0].astype(np.int64) << 16) | (im[..., 1].astype(np.int64) << 8) | im[..., 2]
    c = Counter()
    for a, b in ((key[:, :-1], key[:, 1:]), (key[:-1, :], key[1:, :])):
        m = a != b
        lo = np.minimum(a[m], b[m])
        hi = np.maximum(a[m], b[m])
        u, n = np.unique(lo * (1 << 24) + hi, return_counts=True)
        for k, v in zip(u, n):
            c[int(k)] += int(v)
    out = []
    for k, v in c.most_common():
        if v < floor:
            break
        lo, hi = k >> 24, k & 0xFFFFFF
        ca = ((lo >> 16) & 255, (lo >> 8) & 255, lo & 255)
        cb = ((hi >> 16) & 255, (hi >> 8) & 255, hi & 255)
        out.append((v, "%02X%02X%02X" % ca, "%02X%02X%02X" % cb, cr(ca, cb)))
    return out


if __name__ == "__main__":
    look, name = sys.argv[1], sys.argv[2]
    floor = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    for suf in ("", "@1.5x"):
        print(name + suf)
        for v, a, b, r in pairs(R + "%s/%s%s.png" % (look, name, suf), floor)[:14]:
            print("  %6d  %s | %s  %5.2f : 1" % (v, a, b, r))
