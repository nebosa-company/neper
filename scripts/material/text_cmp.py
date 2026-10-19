"""Text-ink exactness of a Neper Android-look sheet against the Material Web reference, cell by cell.

  python -I scripts/material/text_cmp.py <sheet> ... [--dark] [--all] [--cells]     (from the repository root)

Placement is cmp.py's (the cell's reference crop centred in our cell, best offset within 3 px). The text ink of a cell is the set of
reference pixels that change when the text is made transparent (`<cell>@1x-textmask.png`, made by capture_textonly.mjs and
textmask.py: the icons stay visible, so this is the ink of the text alone). Over those pixels a pixel is EXACT when every channel of ours is within
2 levels of the reference and FAR when one is more than 12 levels off. `--corrected` first takes the fill's own error off (see
`background_corrected`). `--all` runs every sheet in sheets.SHEETS; `--cells`
prints one line per cell, not per sheet.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import cmp as mcmp  # noqa: E402
from sheets import SHEETS  # noqa: E402

LOOKS, REF, MARGIN, SPACING, CAPTION, CROP = mcmp.LOOKS, mcmp.REF, mcmp.MARGIN, mcmp.SPACING, mcmp.CAPTION, mcmp.CROP


def load(path):
    return np.array(Image.open(path).convert("RGB")).astype(int)


def cells(name, dark, only=None):
    """yield (ref_name, ink mask, reference crop, our crop) for each cell of the sheet"""
    sheet = SHEETS[name]
    scheme = "dark" if dark else "light"
    ours = load(os.path.join(LOOKS, "material-dark" if dark else "material", name + ".png"))
    PAD = 32
    ours = np.pad(ours, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
    for i, ref_name in enumerate(sheet["cells"]):
        if ref_name is None or (only and only not in ref_name):
            continue
        twin = os.path.join(REF, scheme, ref_name + "@1x-textmask.png")
        if not os.path.exists(twin):
            continue
        ref = load(os.path.join(REF, scheme, ref_name + "@1x.png"))
        ink = np.array(Image.open(twin).convert("L")) > 127
        w, h = ref.shape[1] - 2 * CROP, ref.shape[0] - 2 * CROP
        col, row = i % sheet["columns"], i // sheet["columns"]
        x0 = MARGIN + col * (sheet["cell_w"] + SPACING) + PAD
        y0 = MARGIN + row * (CAPTION + sheet["cell_h"] + SPACING) + CAPTION + PAD
        cx = x0 + (sheet["cell_w"] - w) / 2.0 - CROP
        cy = y0 + (sheet["cell_h"] - h) / 2.0 - CROP
        if "at" in sheet:
            at = sheet["at"][i] if isinstance(sheet["at"][0], tuple) else sheet["at"]
            cx, cy = x0 + at[0] - CROP, y0 + at[1] - CROP
        rx0, ry0 = max(0, int(round(x0 - cx))), max(0, int(round(y0 - cy)))
        rx1 = min(ref.shape[1], int(round(x0 + sheet["cell_w"] - cx)))
        ry1 = min(ref.shape[0], int(round(y0 + sheet["cell_h"] - cy)))
        if sheet.get("full"):
            rx0, ry0, rx1, ry1 = 0, 0, ref.shape[1], ref.shape[0]
        win = np.zeros(ink.shape, bool)
        win[ry0:ry1, rx0:rx1] = True
        best = None
        bx, by = int(round(cx)), int(round(cy))
        for dx, dy in sorted(((a, b) for a in range(-3, 4) for b in range(-3, 4)), key=lambda p: abs(p[0]) + abs(p[1])):
            X0, Y0 = bx + dx, by + dy
            if X0 < 0 or Y0 < 0 or X0 + ref.shape[1] > ours.shape[1] or Y0 + ref.shape[0] > ours.shape[0]:
                continue
            o = ours[Y0:Y0 + ref.shape[0], X0:X0 + ref.shape[1]]
            score = int(((np.abs(o - ref).max(axis=2) <= 2) & win).sum())  # cmp.py's score: the text steers the placement as it does there
            if best is None or score > best[0] + 12:
                best = (score, X0, Y0)
        if best is None:
            continue
        _, X0, Y0 = best
        yield ref_name, ink & win, ref, ours[Y0:Y0 + ref.shape[0], X0:X0 + ref.shape[1]]


CORRECT = False


def background_corrected(ink, ref, o):
    """ours with, per text line, the median difference to the reference on the ring of plain pixels around the ink taken off: what is
    left is the text, not the fill (a state layer or a ripple that is a level or two off) that it stands on"""
    lines, count = ndimage.label(ndimage.binary_dilation(ink, structure=np.ones((3, 25), bool)))
    out = o.copy()
    for i in range(1, count + 1):
        m = (lines == i) & ink
        ring = ndimage.binary_dilation(m, iterations=4) & ~ndimage.binary_dilation(m, iterations=2) & ~ink
        if ring.sum() >= 8:
            out[lines == i] = o[lines == i] - np.median((o - ref)[ring], axis=0).astype(int)
    return out


def run(name, dark, only=None, per_cell=False):
    n = ex = far = 0
    for ref_name, ink, ref, o in cells(name, dark, only):
        if CORRECT:
            o = background_corrected(ink, ref, o)
        d = np.abs(o - ref).max(axis=2)
        k = int(ink.sum())
        e = int(((d <= 2) & ink).sum())
        f = int(((d > 12) & ink).sum())
        n += k
        ex += e
        far += f
        if per_cell and k:
            print("  %-36s ink %5d  exact %5.1f%%  far %5.1f%%" % (ref_name, k, 100.0 * e / k, 100.0 * f / k))
    return n, ex, far


if __name__ == "__main__":
    args = sys.argv[1:]
    dark = "--dark" in args
    CORRECT = "--corrected" in args
    names = [a for a in args if not a.startswith("--")]
    if "--all" in args:
        names = list(SHEETS)
    tn = te = tf = 0
    for nm in names:
        n, e, f = run(nm, dark, per_cell="--cells" in args)
        if n:
            print("%-16s %s  text ink %6d  exact %5.1f%%  far %5.1f%%" % (nm, "dark " if dark else "light", n, 100.0 * e / n, 100.0 * f / n))
        tn, te, tf = tn + n, te + e, tf + f
    if tn:
        print("%-16s %s  text ink %6d  exact %5.1f%%  far %5.1f%%" % ("TOTAL", "dark " if dark else "light", tn, 100.0 * te / tn, 100.0 * tf / tn))
