"""Compares the hinted points GDI gave through a tap font (tapfont.py, tapread.py: a .hinted.gz file) with a dump of our hinter.

python tapcmp.py <gdi.hinted.gz> <ours.ct.txt> [-v] [code ...]

`ours.ct.txt` is the oracle tool's --dump output (`code adv pp1x ncont { npts { x y on } } { x y }*4`, 26.6, the points as the hinter has them,
then its four phantom points). Prints per glyph how many x and y coordinates agree, the first points that do not, and at the end how many
glyphs and points agree and a histogram of the differences (GDI minus ours, in 1/64 pixel).
"""
import collections
import gzip
import sys


def parse_ours(path):
    ours = {}
    for ln in open(path).read().splitlines():
        t = list(map(int, ln.split()))
        code, adv, pp1x, nc = t[0], t[1], t[2], t[3]
        p, pts = 4, []
        for _ in range(nc):
            m = t[p]
            p += 1
            pts += [(t[p + 3 * i], t[p + 3 * i + 1]) for i in range(m)]
            p += 3 * m
        pts += [(t[p + 2 * i], t[p + 2 * i + 1]) for i in range(2)]  # the left and right phantom points (the vertical pair is not compared)
        ours[code] = pts
    return ours


def parse_gdi(path):
    gdi = {}
    for ln in gzip.open(path, "rt").read().splitlines():
        t = list(map(int, ln.split()))
        gdi[t[0]] = [(t[2 + 2 * i], t[3 + 2 * i]) for i in range(t[1] - 2)]
    return gdi


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "-v" in sys.argv
    gdi = parse_gdi(args[0])
    ours = parse_ours(args[1])
    only = set(int(a) for a in args[2:])
    hx, hy = collections.Counter(), collections.Counter()
    exact = total = 0
    for code in sorted(gdi):
        if only and code not in only:
            continue
        if code not in ours or len(ours[code]) != len(gdi[code]):
            continue
        g, o = gdi[code], ours[code]
        dx = [a[0] - b[0] for a, b in zip(g, o)]
        dy = [a[1] - b[1] for a, b in zip(g, o)]
        total += 1
        exact += all(d == 0 for d in dx) and all(d == 0 for d in dy)
        hx.update(dx)
        hy.update(dy)
        if verbose or only:
            bad = [(i, o[i][0], o[i][1], dx[i], dy[i]) for i in range(len(g)) if dx[i] or dy[i]]
            print("%3d %r points %3d x agree %3d y agree %3d  %s" % (code, chr(code), len(g), sum(1 for d in dx if d == 0), sum(1 for d in dy if d == 0), bad[:10]))
    print("glyphs exact (every point incl. phantoms, x and y): %d of %d" % (exact, total))
    print("x agrees %d of %d points; y agrees %d of %d" % (hx[0], sum(hx.values()), hy[0], sum(hy.values())))
    print("x difference (GDI minus ours, 1/64 px):", sorted(hx.items(), key=lambda kv: -kv[1])[:16])
    print("y difference:", sorted(hy.items(), key=lambda kv: -kv[1])[:10])


if __name__ == "__main__":
    main()
