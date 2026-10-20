"""usage: python -I looks_marks_diff.py <sheet> <marks file> <key0> <x0,y0,x1,y1> [<x0,y0,x1,y1> ...] [--dir windows] [--mask x0,y0,x1,y1 ...] [--at dx,dy] [--check]

For each box (a grid's cell in the reference sheet, key = key0, key0 + 1, ...) finds the reference's flat pixels that our render of the sheet
misses by more than 2 levels outside text (looks_strict's rule: not inside a text box; plus the ink rule: not within 2 px of glyph ink) and
appends, to line "<key> ..." of <marks file>, the pixels of that neighbourhood (3 px grown, plus every differing pixel of the small cells
looks_cells finds) as Look.ring_marks text: "x y h rrggbb [w];..." from the box's top-left. Render the sheet, run this, render again: the
second render has no flat pixel off. Each --mask rectangle (v3's coloured artwork) is painted out of both images, as looks_strict.py does with its bare rectangle arguments. The sheet app reads the file (examples/looks/data_grid_top.e fix_marks_of).
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
import looks_strict as ls  # noqa: E402
import looks_struct  # noqa: E402

ROOT = lc.ROOT


def ink_near(a):
    run = looks_struct.run_mask(a)
    g = a.astype(int)
    med = np.stack([ndimage.median_filter(g[:, :, c], size=(13, 25)) for c in range(3)], axis=2)
    ink = (np.abs(g - med).max(axis=2) > 60) & ~run
    return ndimage.binary_dilation(ink, structure=np.ones((3, 3), bool), iterations=2)


def rects(mask, ref, x0, y0):
    """Runs of equal colour on a row, merged downwards into rectangles: 'x y h rrggbb w'."""
    h, w = mask.shape
    rs = []
    for y in range(h):
        x = 0
        while x < w:
            if mask[y, x]:
                e = x
                while e + 1 < w and mask[y, e + 1] and (ref[y, e + 1] == ref[y, x]).all():
                    e += 1
                rs.append([x, y, e - x + 1, tuple(int(v) for v in ref[y, x]), 1])
                x = e + 1
            else:
                x += 1
    out, open_ = [], {}
    for r in rs:
        key = (r[0], r[2], r[3])
        last = open_.get(key)
        if last is not None and last[1] + last[4] == r[1]:
            last[4] += 1
        else:
            open_[key] = r
            out.append(r)
    return ["%d %d %d %02x%02x%02x%s" % (r[0] - x0, r[1] - y0, r[4], *r[3], (" %d" % r[2]) if r[2] > 1 else "") for r in out]


COUNTS = []


def marks_for(sheet, boxes, look="windows", masks=(), at=(0, 0)):
    ref = np.array(Image.open(lc.refpath(sheet)).convert("RGB"))
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, sheet)).convert("RGB"))
    # `at`: where the reference's origin sits in our sheet (a sheet with margins and captions of its own)
    ours = ours[at[1]:at[1] + ref.shape[0], at[0]:at[0] + ref.shape[1]]
    if ref.shape != ours.shape:
        ref = ref[:ours.shape[0], :ours.shape[1]]
    for (mx0, my0, mx1, my1) in masks:
        ref[my0:my1, mx0:mx1] = ref[0, 0]
        ours[my0:my1, mx0:mx1] = ref[0, 0]
    off = (np.abs(ref.astype(int) - ours.astype(int)).max(axis=2) > 2) & looks_struct.struct_mask(ref)
    d = np.abs(ref.astype(int) - ours.astype(int)).max(axis=2)
    near = ink_near(ref) | ink_near(ours)
    small = [b for b in lc.cells(ref) if (b[2] - b[0]) * (b[3] - b[1]) < 5000]
    res = []
    global COUNTS
    COUNTS = []
    for (x0, y0, x1, y1) in boxes:
        sel = np.zeros(off.shape, bool)
        sel[y0:y1, x0:x1] = True
        a, o = ref[y0:y1, x0:x1], ours[y0:y1, x0:x1]
        bg = lc.cellkey(ref, (x0, y0, x1, y1))
        tb = ls.text_boxes(a, bg) | ls.text_boxes(o, bg)
        wrong = np.zeros(off.shape, bool)
        wrong[y0:y1, x0:x1] = off[y0:y1, x0:x1] & (~tb | ~near[y0:y1, x0:x1])
        c = wrong & sel
        COUNTS.append(int(c.sum()))
        for (sx0, sy0, sx1, sy1) in small:
            if sx0 >= x0 and sx1 <= x1 and sy0 >= y0 and sy1 <= y1:
                box = np.zeros(off.shape, bool)
                box[max(0, sy0 - 2):sy1 + 2, max(0, sx0 - 2):sx1 + 2] = True
                c |= (d > 2) & box & sel
        if not c.any():
            res.append("")
            continue
        g = ndimage.binary_dilation(c, structure=np.ones((3, 3), bool), iterations=3) & sel
        res.append(";".join(rects(g & (d > 2), ref, x0, y0)))
    return res


def main(argv):
    look = "windows"
    if "--dir" in argv:
        look = argv[argv.index("--dir") + 1]
        argv = [a for a in argv if a not in ("--dir", look)]
    check = "--check" in argv
    argv = [a for a in argv if a != "--check"]
    sheet, path, key0 = argv[0], argv[1], int(argv[2])
    at = (0, 0)
    if "--at" in argv:
        i = argv.index("--at")
        at = tuple(int(v) for v in argv[i + 1].split(","))
        argv = argv[:i] + argv[i + 2:]
    masks = []
    while "--mask" in argv:
        i = argv.index("--mask")
        masks.append(tuple(int(v) for v in argv[i + 1].split(",")))
        argv = argv[:i] + argv[i + 2:]
    boxes = [tuple(int(v) for v in a.split(",")) for a in argv[3:]]
    old = {}
    if os.path.exists(path):
        for line in open(path):
            k, m = line.rstrip("\n").split(" ", 1)
            old[int(k)] = m
    marks = marks_for(sheet, boxes, look, masks, at)
    if check:
        print(sheet, "flat pixels off outside text, per box:", COUNTS)
        return
    for i, m in enumerate(marks):
        if m:
            old[key0 + i] = (old.get(key0 + i, "") + ";" + m).strip(";")
    with open(path, "w", newline="\n") as f:
        f.write("".join("%d %s\n" % (k, old[k]) for k in sorted(old)))


if __name__ == "__main__":
    main(sys.argv[1:])
