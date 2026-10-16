"""Builds docs/ui/looks/ref/windows/edits_hover.png from the live v3 hover grabs and diffs the render against it.

`python -I scripts/looks_edits_hover_eval.py` (after running examples/looks/edits_hover.e) prints, per cell:
 - `frame`: pixels off by more than 2 levels, and the largest error, outside the text area (rim, foot, buttons, corners);
 - `all`: every pixel of the cell (text anti-aliasing included).
and, for context, the same two numbers for the REST look (the render of the hover-less control is not needed: the rest grab of
the same dialog is diffed against the hover grab to show how much the hover changes: `rest-vs-hover`).
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
# (name, hover capture, rest grab, x, y, DFM width in the capture, x of the control in its cell, top in its cell, columns at the right
# end that hold buttons (the text area ends before them))
CELLS = [("mask hover", "hover-edit-options-old-password", "hover-options-passwords-rest", 215, 89, 495, 8, 9, 5),
         ("btn edit hover", "hover-edit-options-deck-path", "hover-options-decks-rest", 215, 94, 495, 311, 9, 20),
         ("btn ellipsis hover", "hover-edit-button-ellipsis-options-deck-path", "hover-options-decks-rest", 215, 94, 495, 9, 10, 20),
         ("btn ellipsis cardart", "hover-edit-button-ellipsis-options-cardart", "hover-options-cardart-rest", 215, 385, 464, 40, 10, 20),
         ("spin fast edit", "hover-spin-edit-options-max-same-cards", "hover-options-decks-rest", 215, 159, 121, 440, 9, 49),
         ("spin fast up", "hover-spin-edit-arrow-up-options-max-same-cards", "hover-options-decks-rest", 215, 159, 121, 399, 15, 49),
         ("spin fast down", "hover-spin-edit-arrow-down-options-max-same-cards", "hover-options-decks-rest", 215, 159, 121, 399, 5, 49),
         ("spin fast left", "hover-spin-edit-arrow-left-options-max-same-cards", "hover-options-decks-rest", 215, 159, 121, 415, 10, 49),
         ("spin fast right", "hover-spin-edit-arrow-right-options-max-same-cards", "hover-options-decks-rest", 215, 159, 121, 383, 10, 49),
         ("morph edit", "hover-spin-edit-options-morph-speed", "hover-options-morph-rest", 406, 105, 67, 470, 9, 19),
         ("morph up", "hover-spin-edit-arrow-up-options-morph-speed", "hover-options-morph-rest", 406, 105, 67, 438, 15, 19),
         ("morph down", "hover-spin-edit-arrow-down-options-morph-speed", "hover-options-morph-rest", 406, 105, 67, 438, 5, 19),
         ("hot key hover", "hover-edit-options-shortcut-hotkey", "hover-options-shortcuts-rest", 215, 414, 324, 8, 9, 1)]
CELL_W, CELL_H = 990, 40
PITCH = 20 + CELL_H + 10


def origin(i):
    return 12, 12 + i * PITCH + 20


def load(n):
    return np.array(Image.open(R + n + "@1x.png").convert("RGB")).astype(int)


def build():
    n = len(CELLS)
    h = 12 * 2 + n * PITCH - 10
    out = Image.new("RGB", (12 * 2 + CELL_W, h), (240, 240, 240))
    for i, (nm, cap, rest, x, y, w, xo, top, k) in enumerate(CELLS):
        shot = Image.open(R + cap + "@1x.png").convert("RGB")
        ox, oy = origin(i)
        out.paste(shot.crop((x - 2, y - 2, x + w + 3, y + 24)), (ox + xo - 2, oy + top - 2))
    out.save(ROOT + "ref/windows/edits_hover.png")
    return out


def main():
    ref = np.array(build()).astype(int)
    smask = looks_struct.struct_mask(ref.astype(np.uint8))
    ours = np.array(Image.open(ROOT + "windows/edits_hover.png").convert("RGB")).astype(int)
    for i, (nm, cap, rest, x, y, w, xo, top, k) in enumerate(CELLS):
        ox, oy = origin(i)
        a = ref[oy + top - 2:oy + top + 24, ox + xo - 2:ox + xo + w + 3]
        b = ours[oy + top - 2:oy + top + 24, ox + xo - 2:ox + xo + w + 3]
        d = np.abs(a - b).max(axis=2)
        m = np.ones_like(d, bool)
        m[5:21, (3 if k == 1 else 5):2 + w + 1 - k] = False
        hv = load(cap)[y - 2:y + 24, x - 2:x + w + 3]
        rs = load(rest)[y - 2:y + 24, x - 2:x + w + 3]
        dr = np.abs(hv - rs).max(axis=2)
        sm = smask[oy + top - 2:oy + top + 24, ox + xo - 2:ox + xo + w + 3]
        e = np.where(m, d, 0)
        wy, wx = np.unravel_index(int(e.argmax()), e.shape)
        print("%-20s struct >2: %3d max %3d | frame >2: %3d max %3d at (%2d, %2d) | all >2: %4d max %3d | rest-vs-hover frame >2: %3d max %3d" % (nm, int(((d > 2) & sm).sum()), int(d[sm].max()), int(((d > 2) & m).sum()), int(d[m].max()), wx - 2, wy - 2, int((d > 2).sum()), int(d.max()), int(((dr > 2) & m).sum()), int(dr[m].max())))


main()
