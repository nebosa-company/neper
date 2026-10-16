"""Structural diff of two same-size images (the audit's method): ref pixels in a flat fill or a
straight run of 11 or more equal pixels whose colour occurs at least 30 times, outside a 1 px
halo round every non-structural pixel (text, anti-aliasing, artwork), compared with a
tolerance of 2 levels per channel. Prints the count and the worst (ref -> ours) colour pairs.

  python -I scripts/looks_struct_d.py <ref.png> <ours.png> [x0 y0 x1 y1]   (ours is cropped to ref's size
                                                                         at x0,y0 when given)
  python -I scripts/looks_struct_d.py sheet <name>   (sheet of looks_refs_d: ref/windows/<name>.png vs windows/<name>.png)
"""
import os
import sys
from collections import Counter, defaultdict

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def structural(im):
    w, h = im.size
    px = im.load()
    count = Counter(px[x, y] for y in range(h) for x in range(w))
    flat = [[False] * w for _ in range(h)]
    for y in range(h):
        x = 0
        while x < w:
            e = x
            while e + 1 < w and px[e + 1, y] == px[x, y]:
                e += 1
            if e - x + 1 >= 11 and count[px[x, y]] >= 30:
                for i in range(x, e + 1):
                    flat[y][i] = True
            x = e + 1
    for x in range(w):
        y = 0
        while y < h:
            e = y
            while e + 1 < h and px[x, e + 1] == px[x, y]:
                e += 1
            if e - y + 1 >= 11 and count[px[x, y]] >= 30:
                for i in range(y, e + 1):
                    flat[i][x] = True
            y = e + 1
    mask = [[flat[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if not flat[y][x]:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if 0 <= y + dy < h and 0 <= x + dx < w:
                            mask[y + dy][x + dx] = False
    return mask


def diff(ref, got, top=14, quiet=False):
    w, h = ref.size
    mask = structural(ref)
    a, b = ref.load(), got.load()
    bad = 0
    total = 0
    worst = 0
    pairs = defaultdict(list)
    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            total += 1
            p, q = a[x, y], b[x, y]
            d = max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2]))
            if d > 2:
                bad += 1
                worst = max(worst, d)
                pairs[(p, q)].append((x, y))
    if not quiet:
        print("structural px %d, off %d, max level %d" % (total, bad, worst))
        for (p, q), pts in sorted(pairs.items(), key=lambda kv: -len(kv[1]))[:top]:
            xs = [pt[0] for pt in pts]
            ys = [pt[1] for pt in pts]
            print("  %3d x  ref %02x%02x%02x -> ours %02x%02x%02x  at x %d-%d y %d-%d" % (len(pts), *p, *q, min(xs), max(xs), min(ys), max(ys)))
    return bad, total, worst


def table(names):
    """One line per sheet: structural px, px more than 2 levels off, the worst level."""
    for name in names:
        refp = os.path.join(ROOT, "docs/ui/looks/ref/windows", name + ".png")
        gotp = os.path.join(ROOT, "docs/ui/looks/windows", name + ".png")
        if not (os.path.exists(refp) and os.path.exists(gotp)):
            continue
        ref = Image.open(refp).convert("RGB")
        got = Image.open(gotp).convert("RGB")
        got = got.crop((0, 0) + ref.size)
        bad, total, worst = diff(ref, got, quiet=True)
        print("%-40s structural %6d  off %5d  max %3d" % (name, total, bad, worst))


if __name__ == "__main__":
    if sys.argv[1] == "table":
        table(sys.argv[2:])
    elif sys.argv[1] == "sheet":
        name = sys.argv[2]
        ref = Image.open(os.path.join(ROOT, "docs/ui/looks/ref/windows", name + ".png")).convert("RGB")
        got = Image.open(os.path.join(ROOT, "docs/ui/looks/windows", name + ".png")).convert("RGB")
        if ref.size != got.size:
            print("size differs", ref.size, got.size)
            got = got.crop((0, 0) + ref.size)
        diff(ref, got)
    else:
        ref = Image.open(sys.argv[1]).convert("RGB")
        got = Image.open(sys.argv[2]).convert("RGB")
        if len(sys.argv) > 3:
            x0, y0 = int(sys.argv[3]), int(sys.argv[4])
            got = got.crop((x0, y0, x0 + ref.width, y0 + ref.height))
        diff(ref, got)
