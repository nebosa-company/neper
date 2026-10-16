"""Reference composites and diffs for the edit sheets that compare a capture crop per cell (token edits, the dialog edits).

`python -I scripts/looks_edits_more.py [sheet ...]` rebuilds docs/ui/looks/ref/windows/<sheet>.png from the live captures and
prints per cell the pixels off by more than 2 levels (all, and structural: flat runs of 11 or more away from ink, scripts/
looks_struct.py) of docs/ui/looks/windows/<sheet>.png, plus the ink bounding boxes. Cells stand in one column (the harness'
margin 12, caption 20, spacing 10), the control at (8, 4) of its cell unless a cell says otherwise.
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_struct  # noqa: E402

ROOT = os.path.join(HERE, "..", "docs", "ui", "looks") + os.sep
CAP = ROOT + "ref/windows/"
MARGIN, CAPTION, SPACING = 12, 20, 10

# sheet -> (cell_w, cell_h, [(name, capture path under ref/windows without @1x.png, x, y, w, h (DFM size), x of the control in its cell)])
SHEETS = {
    "token_edit_dialog": (340, 54, [
        ("token 315x46 (Filter Cards, 1)", "states/tab-selected-filter-cards", 277, 86, 314, 45, 8),
        ("token 315x46 (Filter Cards, 2)", "states/tab-selected-filter-cards", 277, 137, 314, 45, 8),
        ("token 315x27 (Filter Cards, 3)", "states/tab-selected-filter-cards", 277, 188, 314, 26, 8),
    ]),
}


def origin(sheet, i):
    cell_h = SHEETS[sheet][1]
    return MARGIN, MARGIN + i * (CAPTION + cell_h + SPACING) + CAPTION


def build(sheet):
    cw, ch, cells = SHEETS[sheet]
    n = len(cells)
    out = Image.new("RGB", (MARGIN * 2 + cw, MARGIN * 2 + n * (CAPTION + ch) + (n - 1) * SPACING), (240, 240, 240))
    for i, (nm, cap, x, y, w, h, xo) in enumerate(cells):
        shot = Image.open(CAP + cap + "@1x.png").convert("RGB")
        ox, oy = origin(sheet, i)
        out.paste(shot.crop((x - 2, y - 2, x + w + 3, y + h + 4)), (ox + xo - 2, oy + 4 - 2))
    out.save(CAP + sheet + ".png")
    return out


def ink_box(c):
    m = c.mean(axis=2) < 150
    ys, xs = np.where(m)
    if not len(xs):
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def diff(sheet):
    cw, ch, cells = SHEETS[sheet]
    ref = np.array(build(sheet)).astype(int)
    ours = np.array(Image.open(ROOT + "windows/" + sheet + ".png").convert("RGB")).astype(int)
    mask = looks_struct.struct_mask(ref.astype(np.uint8))
    total = 0
    for i, (nm, cap, x, y, w, h, xo) in enumerate(cells):
        ox, oy = origin(sheet, i)
        box = (oy + 4, oy + 4 + h + 1, ox + xo, ox + xo + w + 1)
        a = ref[box[0]:box[1], box[2]:box[3]]
        b = ours[box[0]:box[1], box[2]:box[3]]
        d = np.abs(a - b).max(axis=2)
        sm = mask[box[0]:box[1], box[2]:box[3]]
        bad = int(((d > 2) & sm).sum())
        total += bad
        print("%-34s all >2: %4d (max %3d) | struct >2: %3d (max %3d) | ink ref %s ours %s" % (nm, int((d > 2).sum()), int(d.max()), bad, int(np.where(sm, d, 0).max()), ink_box(a), ink_box(b)))
    print(sheet, "structural pixels off in total:", total)


if __name__ == "__main__":
    for s in (sys.argv[1:] or list(SHEETS)):
        diff(s)
