"""Builds docs/ui/looks/ref/windows/combo_hover.png from the live v3 hover grabs and diffs the render against it.

`python -I scripts/looks_combo_hover_eval.py` (after running examples/looks/combo_hover.e) prints, per cell, the pixels off by
more than 2 levels and the largest error over the frame (rim, face, drop button; the text rows are left out: ClearType against
gray scale), plus the same for the REST look (the rest grab of the same dialog against the hover grab, to show what changes).
"""
import os
import sys
import numpy as np
from PIL import Image

HERE0 = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE0)
import looks_struct  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "docs", "ui", "looks") + os.sep
R = ROOT + "ref/windows/states/"
# (name, hover capture, rest grab, x, y, DFM width, x of the control in its cell)
CELLS = [("row color drop", "hover-combo-box-drop-options-row-color", "hover-options-grids-rest", 321, 71, 389, 20),
         ("row color edit", "hover-combo-box-edit-options-row-color", "hover-options-grids-rest", 321, 71, 389, 300),
         ("show drop", "hover-combo-box-drop-conditional-formatting-show", "hover-conditional-formatting-rest", 149, 41, 143, 266),
         ("auth drop (image)", "hover-combo-box-drop-options-auth-type", "hover-options-internet-rest", 371, 71, 189, 220),
         ("auth edit = rest", "hover-combo-box-edit-options-auth-type", "hover-options-internet-rest", 371, 71, 189, 300),
         ("condition drop (image)", "hover-combo-box-drop-options-condition", "hover-options-defaults-rest", 371, 99, 335, 74),
         ("card art drop (image)", "hover-combo-box-drop-options-card-art-position", "hover-options-morph-rest", 406, 278, 151, 258),
         ("search drop", "hover-combo-box-drop-search", "hover-search-rest", 20, 70, 289, 120),
         ("search edit = rest", "hover-combo-box-edit-search", "hover-search-rest", 20, 70, 289, 300)]
CELL_W, CELL_H = 800, 29
PITCH = 20 + CELL_H + 10


def origin(i):
    return 12, 12 + i * PITCH + 20


def load(n):
    return np.array(Image.open(R + n + "@1x.png").convert("RGB")).astype(int)


def build():
    n = len(CELLS)
    h = 12 * 2 + n * PITCH - 10
    out = Image.new("RGB", (12 * 2 + CELL_W, h), (240, 240, 240))
    for i, (nm, cap, rest, x, y, w, xo) in enumerate(CELLS):
        shot = Image.open(R + cap + "@1x.png").convert("RGB")
        ox, oy = origin(i)
        out.paste(shot.crop((x - 2, y - 2, x + w + 4, y + 25)), (ox + xo - 2, oy + 4 - 2))
    out.save(ROOT + "ref/windows/combo_hover.png")
    return out


def main():
    ref = np.array(build()).astype(int)
    smask = looks_struct.struct_mask(ref.astype(np.uint8))
    ours = np.array(Image.open(ROOT + "windows/combo_hover.png").convert("RGB")).astype(int)
    for i, (nm, cap, rest, x, y, w, xo) in enumerate(CELLS):
        ox, oy = origin(i)
        a = ref[oy + 4 - 2:oy + 4 + 25, ox + xo - 2:ox + xo + w + 4]
        b = ours[oy + 4 - 2:oy + 4 + 25, ox + xo - 2:ox + xo + w + 4]
        d = np.abs(a - b).max(axis=2)
        m = np.ones_like(d, bool)
        m[5:21, 5:min(w - 20, 150)] = False  # the text rows
        hv = load(cap)[y - 2:y + 25, x - 2:x + w + 4]
        rs = load(rest)[y - 2:y + 25, x - 2:x + w + 4]
        dr = np.abs(hv - rs).max(axis=2)
        sm = smask[oy + 4 - 2:oy + 4 + 25, ox + xo - 2:ox + xo + w + 4] & m
        e = np.where(m, d, 0)
        wy, wx = np.unravel_index(int(e.argmax()), e.shape)
        print("%-22s struct >2: %3d max %3d | frame >2: %3d max %3d at (%3d, %2d) | rest-vs-hover frame >2: %3d max %3d | all >2: %4d" % (nm, int(((d > 2) & sm).sum()), int(d[sm].max()), int(((d > 2) & m).sum()), int(d[m].max()), wx - 2, wy - 2, int(((dr > 2) & m).sum()), int(dr[m].max()), int((d > 2).sum())))


main()
