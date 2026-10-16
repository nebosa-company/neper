"""Builds docs/ui/looks/ref/windows/edits_states.png from the live v3 state captures and diffs the render against it.

`python -I scripts/looks_edits_states_eval.py` (after running examples/looks/edits_states.e) prints, per cell:
 - `frame`: pixels off by more than 2 levels, and the largest error, outside the text area (the rim, foot, buttons);
 - `struct`: the same over the structural pixels only (flat runs of 11 or more, away from ink: scripts/looks_struct.py);
 - `all`: every pixel of the cell (text anti-aliasing included, so ClearType against grayscale shows here).
Also scripts/looks_winedit_gen.py explains the foot's drift with the control's y.
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_struct  # noqa: E402

ROOT = os.path.join(HERE, "..", "docs", "ui", "looks") + os.sep
R = ROOT + "ref/windows/states/"
# (name, capture, x, y, w in the capture, x of the control in its cell, columns of the right end that hold buttons)
CELLS = [("mask focus new", "edit-focused-options-new-password", 215, 144, 495, 8, 5),
         ("mask focus old", "edit-focused-options-old-password", 215, 89, 495, 8, 5),
         ("spin fast focus", "spin-edit-focused-options-max-same-cards", 215, 159, 121, 440, 49),
         ("spin up pressed", "spin-edit-arrow-up-pressed-options-max-same-cards", 215, 159, 121, 440, 49),
         ("spin down pressed", "spin-edit-arrow-down-pressed-options-max-same-cards", 215, 159, 121, 440, 49),
         ("spin left pressed", "spin-edit-arrow-left-pressed-options-max-same-cards", 215, 159, 121, 440, 49),
         ("spin right pressed", "spin-edit-arrow-right-pressed-options-max-same-cards", 215, 159, 121, 440, 49),
         ("spin focus", "spin-edit-focused-options-morph-speed", 406, 105, 67, 480, 19),
         ("morph up pressed", "spin-edit-arrow-up-pressed-options-morph-speed", 406, 105, 67, 460, 19),
         ("morph down pressed", "spin-edit-arrow-down-pressed-options-morph-speed", 406, 105, 67, 460, 19),
         ("btn focus", "edit-focused-options-deck-path", 215, 94, 495, 311, 20),
         ("btn selected", "edit-selected-options-deck-path", 215, 94, 495, 311, 20),
         ("btn pressed", "edit-button-ellipsis-pressed-options-deck-path", 215, 94, 495, 9, 20),
         ("btn disabled", "edit-button-ellipsis-pressed-options-cardart", 215, 385, 464, 8, 20),
         ("hotkey rest", "dialog-options-shortcuts-rest", 215, 414, 324, 8, 1),
         ("hotkey focus", "edit-focused-options-shortcut-hotkey", 215, 414, 324, 8, 1)]
CELL_W, CELL_H = 990, 30


def origin(i):
    return 12, 12 + i * 60 + 20


def build():
    n = len(CELLS)
    h = 12 * 2 + n * 50 + (n - 1) * 10
    out = Image.new("RGB", (12 * 2 + CELL_W, h), (240, 240, 240))
    for i, (nm, cap, x, y, w, xo, k) in enumerate(CELLS):
        shot = Image.open(R + cap + "@1x.png").convert("RGB")
        ox, oy = origin(i)
        out.paste(shot.crop((x - 2, y - 2, x + w + 3, y + 24)), (ox + xo - 2, oy + 4 - 2))
    out.save(ROOT + "ref/windows/edits_states.png")
    return out


def ink_box(c, w, k, selected):
    """Bounding box (x0, y0, x1, y1) of the text ink of a cell crop (rows 4..19, columns 3..w-k); None when there is none."""
    t = c[4:20, 3:max(4, w - k)]
    if selected:
        m = (t[:, :, 2] > 150) & (t[:, :, 0] < 120)
    else:
        m = t.mean(axis=2) < 150
    ys, xs = np.where(m)
    if not len(xs):
        return None
    return (int(xs.min()) + 3, int(ys.min()) + 4, int(xs.max()) + 3, int(ys.max()) + 4)


def main():
    ref = np.array(build()).astype(int)
    ours = np.array(Image.open(ROOT + "windows/edits_states.png").convert("RGB")).astype(int)
    total = 0
    mask = looks_struct.struct_mask(ref.astype(np.uint8))
    for i, (nm, cap, x, y, w, xo, k) in enumerate(CELLS):
        ox, oy = origin(i)
        a = ref[oy + 2:oy + 28, ox + xo - 2:ox + xo + w + 3]
        b = ours[oy + 2:oy + 28, ox + xo - 2:ox + xo + w + 3]
        d = np.abs(a - b).max(axis=2)
        m = np.ones_like(d, bool)
        m[5:21, 5:2 + w + 1 - k] = False
        e = np.where(m, d, 0)
        wy, wx = np.unravel_index(int(e.argmax()), e.shape)
        sm = mask[oy + 2:oy + 28, ox + xo - 2:ox + xo + w + 3]
        bad = int(((d > 2) & sm).sum())
        worst = int(np.where(sm, d, 0).max())
        total += bad
        ia = ink_box(a, w, k, "selected" in nm or "pressed" in nm and "btn" in nm)
        ib = ink_box(b, w, k, "selected" in nm or "pressed" in nm and "btn" in nm)
        ink = "ink ref %s ours %s" % (ia, ib)
        print("%-19s frame >2: %4d max %3d at (%d, %d) | struct >2: %3d max %3d | all >2: %4d | %s" % (nm, int(((d > 2) & m).sum()), int(d[m].max()), wx - 2, wy - 2, bad, worst, int((d > 2).sum()), ink))
    print("structural pixels off in total:", total)


main()
