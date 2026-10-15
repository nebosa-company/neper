"""Builds docs/ui/looks/ref/windows/edits_states.png from the live v3 state captures and diffs the render against it.

`python -I scripts/looks_edits_states_eval.py` (after running examples/looks/edits_states.e) prints, per cell, the
number of pixels off by more than 2 levels outside the text area (the rim, foot, buttons) and the largest error.
Also scripts/looks_winedit_gen.py explains the foot's drift with the control's y.
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks") + os.sep
R = ROOT + "ref/windows/states/"
# (name, capture, x, y, w in the capture, x of the control in its cell, columns of the right end that hold buttons)
CELLS = [("mask focus", "edit-focused-options-new-password", 215, 144, 495, 8, 5),
         ("spin fast focus", "spin-edit-focused-options-max-same-cards", 215, 159, 121, 440, 49),
         ("spin focus", "spin-edit-focused-options-morph-speed", 406, 105, 67, 460, 19),
         ("btn focus", "edit-focused-options-deck-path", 215, 94, 495, 395, 20),
         ("btn selected", "edit-selected-options-deck-path", 215, 94, 495, 395, 20),
         ("btn pressed", "edit-button-ellipsis-pressed-options-deck-path", 215, 94, 495, 8, 20),
         ("btn disabled", "edit-button-ellipsis-pressed-options-cardart", 215, 385, 464, 8, 20)]
CELL_W, CELL_H = 990, 30


def origin(i):
    return 12, 12 + i * 60 + 20


def build():
    h = 12 * 2 + 8 * 50 + 7 * 10
    out = Image.new("RGB", (12 * 2 + CELL_W, h), (240, 240, 240))
    for i, (nm, cap, x, y, w, xo, k) in enumerate(CELLS):
        shot = Image.open(R + cap + "@1x.png").convert("RGB")
        ox, oy = origin(i)
        out.paste(shot.crop((x - 2, y - 2, x + w + 3, y + 24)), (ox + xo - 2, oy + 4 - 2))
    out.save(ROOT + "ref/windows/edits_states.png")
    return out


def main():
    ref = np.array(build()).astype(int)
    ours = np.array(Image.open(ROOT + "windows/edits_states.png").convert("RGB")).astype(int)
    for i, (nm, cap, x, y, w, xo, k) in enumerate(CELLS):
        ox, oy = origin(i)
        a = ref[oy + 2:oy + 28, ox + xo - 2:ox + xo + w + 3]
        b = ours[oy + 2:oy + 28, ox + xo - 2:ox + xo + w + 3]
        d = np.abs(a - b).max(axis=2)
        m = np.ones_like(d, bool)
        m[5:21, 5:2 + w + 1 - k] = False
        e = np.where(m, d, 0)
        wy, wx = np.unravel_index(int(e.argmax()), e.shape)
        print("%-16s off by >2: %4d, max %3d at (%d, %d)" % (nm, int(((d > 2) & m).sum()), int(d[m].max()), wx - 2, wy - 2))


main()
