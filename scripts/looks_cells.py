"""Per-cell audit of a Windows sheet against its ref sheet, the way audit 3 counts it.

`python -I scripts/looks_cells.py <sheet> [<sheet> ...] [--dir windows|windows-dark] [-v]`

The ref sheet (docs/ui/looks/ref/windows/<sheet>.png) and our render (docs/ui/looks/windows/<sheet>.png) have the same size;
the ref's connected non-background regions (dilated by 2 px) are the cells. Per cell: structural pixels off (scripts/looks_struct.py,
tolerance 2 levels) with the worst error and its position, and whether the text ink boxes agree (pixels more than 60, 100 or 150 levels
from the cell background, lines grouped by rows; within 1 px at 60 and at one of the other two). A cell passes with 0 structural
pixels off and ink agreement.
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_struct  # noqa: E402

ROOT = os.path.join(HERE, "..", "docs", "ui", "looks") + os.sep


def lines(a, bg, t):
    d = np.abs(a.astype(int) - np.array(bg)).max(axis=2) > t
    rows = d.any(axis=1)
    out = []
    y = 0
    h = len(rows)
    while y < h:
        if rows[y]:
            e = y
            while e + 1 < h and rows[e + 1]:
                e += 1
            xs = np.where(d[y:e + 1].any(axis=0))[0]
            out.append((int(xs.min()), y, int(xs.max()), e))
            y = e + 1
        else:
            y += 1
    return out


def agree(la, lb):
    if len(la) != len(lb):
        return False
    return all(max(abs(p - q) for p, q in zip(u, v)) <= 1 for u, v in zip(la, lb))


def cells(ref):
    bg = tuple(int(v) for v in ref[0, 0])  # the sheet's own background is its corner pixel
    m = (np.abs(ref.astype(int) - np.array(bg)).max(axis=2) > 0)
    m = ndimage.binary_dilation(m, structure=np.ones((3, 3), bool), iterations=2)
    lab, n = ndimage.label(m, structure=np.ones((3, 3), bool))
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        boxes.append((xs.start + 2, ys.start + 2, xs.stop - 2, ys.stop - 2))
    boxes.sort(key=lambda b: (b[1] // 8, b[0]))
    return boxes


def cellkey(ref, box):
    x0, y0, x1, y1 = box
    c = ref[y0:y1, x0:x1].reshape(-1, 3)
    key = (c[:, 0].astype(np.int64) << 16) | (c[:, 1].astype(np.int64) << 8) | c[:, 2]
    vals, counts = np.unique(key, return_counts=True)
    k = vals[counts.argmax()]
    return ((k >> 16) & 255, (k >> 8) & 255, k & 255)


def audit(name, look="windows", verbose=False, refname=None):
    ref = np.array(Image.open(ROOT + "ref/windows/%s.png" % (refname or name)).convert("RGB"))
    if not os.path.exists(ROOT + "%s/%s.png" % (look, name)):
        print("%s: no render of ours" % name)
        return
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, name)).convert("RGB"))
    if ref.shape != ours.shape:
        print("%s: SIZE ref %s ours %s" % (name, ref.shape, ours.shape))
        return
    smask = looks_struct.struct_mask(ref)
    omask = looks_struct.struct_mask(ours)  # text antialiasing of ours leaking into a ref flat pixel is text, not chrome
    npass = 0
    out = []
    bs = cells(ref)
    for i, b in enumerate(bs):
        x0, y0, x1, y1 = b
        a = ref[y0:y1, x0:x1]
        o = ours[y0:y1, x0:x1]
        d = np.abs(a.astype(int) - o.astype(int)).max(axis=2)
        sm = smask[y0:y1, x0:x1] & omask[y0:y1, x0:x1]
        sm_ref_only = int((smask[y0:y1, x0:x1] & ~omask[y0:y1, x0:x1] & (np.abs(a.astype(int) - o.astype(int)).max(axis=2) > 2)).sum())
        e = np.where(sm, d, 0)
        bad = int(((d > 2) & sm).sum())
        wy, wx = np.unravel_index(int(e.argmax()), e.shape)
        bg = cellkey(ref, b)
        ok = {t: agree(lines(a, bg, t), lines(o, bg, t)) for t in (60, 100, 150)}
        ink = ok[60] and (ok[100] or ok[150])
        allbad = int((d > 2).sum())
        good = bad == 0 and ink
        npass += good
        if verbose or not good:
            out.append("  cell %2d %-16s struct_off %4d max %3d at (%d,%d)  ink60/100/150 %s%s%s  any_off %d  (text-AA leaks excluded %d)" % (
                i, str(b), bad, int(e.max()), x0 + wx, y0 + wy, int(ok[60]), int(ok[100]), int(ok[150]), allbad, sm_ref_only))
    print("%s [%s]: %d of %d cells pass" % (name, look, npass, len(bs)))
    for l in out:
        print(l)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    look = "windows"
    if "--dir" in sys.argv:
        i = sys.argv.index("--dir")
        look = sys.argv[i + 1]
        args = [a for a in args if a != look]
    for n in args:
        audit(n, look, "-v" in sys.argv)
