"""Finds, for glyphs of a real font on which our hinter disagrees with GDI's ClearType, the first instruction of the glyph program after which they differ.

python firstdiff.py <font file> <weight> <ppem> <code> [code ...]       (e.g. firstdiff.py C:/Windows/Fonts/tahoma.ttf 400 11 36 41 123)

Each round builds one tap font in which every listed glyph's program is cut after K instructions that are not pushes (top level, a CALL is one) with
an IUP[x] on what is left (tapfont.py cutmap=), reads GDI's points back and compares them with `build/t/ctdump.exe ... cut=` (tools/ctdump), K chosen
per glyph by bisection. Prints per glyph the K at which the two first differ, the instruction there with the numbers pushed just before it, and the
points that differ. Needs glyphs.exe (glyphs.ps1) and ctdump.exe.
"""
import gzip
import json
import os
import subprocess
import sys

from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from synth import CTDUMP, WORK, BIN, ours  # noqa: E402

_round = [0]


def nonpush(bc):
    """-> [(offset, opcode, pushed values just before)] of the top-level instructions that are not pushes."""
    out, i, pend = [], 0, []
    while i < len(bc):
        op = bc[i]
        if op == 0x40:
            n = bc[i + 1]
            pend += list(bc[i + 2:i + 2 + n])
            i += 2 + n
        elif op == 0x41:
            n = bc[i + 1]
            pend += [int.from_bytes(bc[i + 2 + 2 * k:i + 4 + 2 * k], "big", signed=True) for k in range(n)]
            i += 2 + 2 * n
        elif 0xB0 <= op <= 0xB7:
            n = op - 0xAF
            pend += list(bc[i + 1:i + 1 + n])
            i += 1 + n
        elif 0xB8 <= op <= 0xBF:
            n = op - 0xB7
            pend += [int.from_bytes(bc[i + 1 + 2 * k:i + 3 + 2 * k], "big", signed=True) for k in range(n)]
            i += 1 + 2 * n
        else:
            out.append((i, op, pend[-6:]))
            pend = []
            i += 1
    return out


def valid_cuts(ops):
    """The K (1-based) to try: every one (Tahoma's glyph programs are one IF ... EIF, so a cut inside an open IF has to be allowed; both
    interpreters simply stop at the end of the code)."""
    return list(range(1, len(ops) + 1))


def gdi_points(fontfile, weight, ppem, cutmap):
    _round[0] += 1
    family = "NBi%d_%d" % (os.getpid(), _round[0])
    os.makedirs(WORK, exist_ok=True)
    cm = os.path.join(WORK, family + ".cut.json")
    json.dump({str(k): v for k, v in cutmap.items()}, open(cm, "w"))
    ttf = os.path.join(WORK, family + ".ttf")
    subprocess.run([sys.executable, os.path.join(HERE, "tapfont.py"), fontfile, ttf, family, str(ppem), "cutmap=" + cm], check=True, stdout=subprocess.DEVNULL)
    atl = []
    for mode in (1, 2):
        scratch = os.path.join(WORK, "out%d_%d" % (os.getpid(), mode))
        os.makedirs(scratch, exist_ok=True)
        env = dict(os.environ, GLYPHS_READER=str(mode), GLYPHS_FONT=ttf, GLYPHS_CELL="200,210,110", GLYPHS_NOOUTLINE="1")
        subprocess.run([os.path.join(BIN, "glyphs.exe"), scratch, family, str(weight), str(ppem), "5"], check=True, env=env, stdout=subprocess.DEVNULL)
        atl.append(os.path.join(scratch, "%s-%d-%d-q5.000000-FFFFFF.bgra" % (family, weight, ppem)))
    out = os.path.join(WORK, family + ".hinted.gz")
    subprocess.run([sys.executable, os.path.join(HERE, "tapread.py"), fontfile, atl[0], atl[1], out], check=True, stdout=subprocess.DEVNULL)
    res = {}
    for ln in gzip.open(out, "rt").read().splitlines():
        t = list(map(int, ln.split()))
        res[t[0]] = [(t[2 + 2 * i], t[3 + 2 * i]) for i in range(t[1])]
    for p in atl + [ttf, out, cm]:
        os.remove(p)
    return res


def our_points(fontfile, ppem, cutmap):
    cf = os.path.join(WORK, "ours_%d.cut.txt" % os.getpid())
    open(cf, "w").write("".join("%d %d\n" % kv for kv in cutmap.items()))
    out = subprocess.run([CTDUMP, fontfile, str(ppem), "cut=" + cf], check=True, capture_output=True, text=True).stdout
    os.remove(cf)
    res = {}
    for ln in out.splitlines():
        t = list(map(int, ln.split()))
        code, nc = t[0], t[3]
        p, pts = 4, []
        for _ in range(nc):
            m = t[p]
            p += 1
            pts += [(t[p + 3 * i], t[p + 3 * i + 1]) for i in range(m)]
            p += 3 * m
        pts += [(t[p + 2 * i], t[p + 2 * i + 1]) for i in range(4)]
        res[code] = pts
    return res


def main():
    fontfile, weight, ppem = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    codes = [int(c) for c in sys.argv[4:]]
    font = TTFont(fontfile)
    cmap, glyf = font.getBestCmap(), font["glyf"]
    ops = {}
    for c in codes:
        g = glyf[cmap[c]]
        ops[c] = nonpush(g.program.getBytecode()) if getattr(g, 'program', None) is not None else []
    valid = {c: valid_cuts(ops[c]) + [len(ops[c]) + 1] for c in codes}   # the last: the whole program with one IUP[x] more, which differs
    lo = {c: 0 for c in codes}                 # indexes into valid[c]
    hi = {c: len(valid[c]) - 1 for c in codes}
    diff = {}
    while any(hi[c] - lo[c] > 1 for c in codes):
        cutmap = {c: valid[c][(lo[c] + hi[c]) // 2] for c in codes if hi[c] - lo[c] > 1}
        g = gdi_points(fontfile, weight, ppem, cutmap)
        o = our_points(fontfile, ppem, cutmap)
        for c, k in cutmap.items():
            if g.get(c) is None or o.get(c) is None or len(g[c]) != len(o[c]):
                print("code", c, "unreadable at K", k, file=sys.stderr)
                hi[c] = lo[c] + 1
                continue
            # the body and the left and right phantom points (the vertical pair is not compared)
            if g[c][:-2] == o[c][:-2]:
                lo[c] = valid[c].index(k)
            else:
                hi[c] = valid[c].index(k)
                diff[c] = (g[c], o[c])
        print("round", _round[0], {c: (valid[c][lo[c]], valid[c][hi[c]]) for c in codes}, flush=True)
    # lo is equal, hi differs: the instructions after lo up to hi hold the culprit
    for c in codes:
        k = valid[c][hi[c]]
        if c not in diff:
            g = gdi_points(fontfile, weight, ppem, {c: k})
            o = our_points(fontfile, ppem, {c: k})
            diff[c] = (g[c], o[c])
        gp, op = diff[c]
        bad = [(i, gp[i], op[i]) for i in range(len(gp) - 2) if gp[i] != op[i]]
        if k - 1 < len(ops[c]):
            first = valid[c][lo[c]]
            span = ["#%d off %d op 0x%02X pushed %s" % (j + 1, ops[c][j][0], ops[c][j][1], ops[c][j][2]) for j in range(first, k)]
            print("code %d %r: equal after instruction %d, differs after %d of %d: %s" % (c, chr(c), first, k, len(ops[c]), "; ".join(span)))
        else:
            print("code %d %r: differs only after the whole program (IUP[x] twice)" % (c, chr(c)))
        print("    points differing (index, gdi, ours):", bad[:12], "of", len(bad))


if __name__ == "__main__":
    main()
