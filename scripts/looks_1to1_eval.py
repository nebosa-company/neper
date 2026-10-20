"""Counted and chrome-only differences of our Windows sheets against a reference set: `python -I scripts/looks_1to1_eval.py [--ref windows|windows-1to1] <sheet> ...`

Per sheet, each reference cell (scripts/looks_cells.py) is compared with the same place of our render (placed by looks_strict.place when the
two sheets differ in size). counted = pixels whose largest channel difference is more than 2 levels, glyphs included; text = those inside
a text box of either image (looks_strict.text_boxes); chrome = the rest. The last column is the sheet's sum. LOOKS_OURS=<dir> compares
that folder's renders instead of docs/ui/looks/windows (a baseline taken from git).
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
import looks_strict as ls  # noqa: E402


def run(sheet, verbose=True):
    ref = np.array(Image.open(lc.refpath(sheet)).convert("RGB"))
    ours = np.array(Image.open(os.environ.get("LOOKS_OURS", lc.ROOT + "windows") + "/%s.png" % sheet).convert("RGB"))
    same = ref.shape == ours.shape
    bs = lc.cells(ref)
    if not same:  # one crop placed in our sheet: the whole reference, not the cell box (which the dilation shrinks at the edges)
        bs = [(0, 0, ref.shape[1], ref.shape[0])]
    tot = [0, 0, 0]
    for b in bs:
        x0, y0, x1, y1 = b
        a = ref[y0:y1, x0:x1]
        if same:
            o = ours[y0:y1, x0:x1]
        else:
            f = ls.place(a, ours)
            if not f:
                print("  %s cell %s not found" % (sheet, b))
                continue
            o = ours[f[2]:f[2] + y1 - y0, f[1]:f[1] + x1 - x0]
        bg = lc.cellkey(ref, b)
        d = np.abs(a.astype(int) - o.astype(int)).max(axis=2) > 2
        tb = ls.text_boxes(a, bg) | ls.text_boxes(o, bg)
        c = [int(d.sum()), int((d & tb).sum()), int((d & ~tb).sum())]
        tot = [u + v for u, v in zip(tot, c)]
        if verbose:
            print("  %-22s %-22s counted %6d  text %6d  chrome %6d  (area %d)" % (sheet, str(b), c[0], c[1], c[2], a.shape[0] * a.shape[1]))
    return tot


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--ref" in sys.argv:
        i = sys.argv.index("--ref")
        os.environ["LOOKS_REF"] = sys.argv[i + 1]
        args = [a for a in args if a != sys.argv[i + 1]]
    quiet = "--sum" in sys.argv
    for s in args:
        t = run(s, not quiet)
        print("%-26s counted %6d  text %6d  chrome %6d" % (s, t[0], t[1], t[2]), flush=True)
