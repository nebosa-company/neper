"""Strict per-cell audit (round 12): `python -I scripts/looks_strict.py <sheet> ... [--dir windows-dark] [x0,y0,x1,y1 ...]`.

A reference flat pixel (scripts/looks_struct.py: in a run of 11 or more equal pixels, colour seen 30 or more times, not within 1 px of
ink) counts as off whenever OURS differs by more than 2 levels there. Unlike looks_cells.py before round 12 it does not AND the
reference's mask with ours' (that hid a reference flat pixel where ours is not flat, e.g. an anti-aliased corner).
Each off pixel is classed `text` when it lies inside a text line box (the ink lines of the reference or of ours at 100 levels from the cell
background, widened by 2 px; glyph shapes, ClearType against grayscale) and `chrome` otherwise. A cell passes with 0 chrome px off and
its ink boxes in agreement (looks_cells.agree at 60 and at 100 or 150). `x0,y0,x1,y1` arguments paint v3 artwork out of both images.
`--lum` measures ink boxes on luminance (ClearType fringes); `--only x0,y0,x1,y1` compares one rectangle. Prints every cell with its numbers: chrome off, text off, max error of each, where the worst chrome pixel is.
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
import looks_struct  # noqa: E402

ROOT = lc.ROOT


def text_boxes(a, bg, grow=2):
    """Pixels near glyphs: ink (more than 100 levels from the cell background) is merged by a 2 px dilation into words and lines;
    a component counts as text when its ink bounding box is 5 to 16 px tall (a line of glyphs; a 1 px rule or a big frame is not)
    and its ink fills 8 to 70 % of that box. The mask is the component grown by `grow` px. Row stripes are NOT text boxes."""
    ink = np.abs(a.astype(int) - np.array(bg)).max(axis=2) > 100
    ink &= ~looks_struct.run_mask(a)  # rules and frame edges (runs of 11 equal pixels) are chrome, not glyphs
    lab, n = ndimage.label(ndimage.binary_dilation(ink, structure=np.ones((3, 3), bool), iterations=2), structure=np.ones((3, 3), bool))
    m = np.zeros(ink.shape, bool)
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        part = ink[sl] & (lab[sl] == i)
        if not part.any():
            continue
        ys, xs = np.where(part)
        h = ys.max() - ys.min() + 1
        w = xs.max() - xs.min() + 1
        dens = part.sum() / float(h * w)
        if 5 <= h <= 16 and 0.08 <= dens <= 0.7:
            y0, y1 = sl[0].start + ys.min(), sl[0].start + ys.max()
            x0, x1 = sl[1].start + xs.min(), sl[1].start + xs.max()
            m[max(0, y0 - grow):y1 + grow + 1, max(0, x0 - grow):x1 + grow + 1] = True
    return m


def audit(name, look="windows", masks=(), only=None):
    ref = np.array(Image.open(ROOT + "ref/windows/%s.png" % name).convert("RGB"))
    if not os.path.exists(ROOT + "%s/%s.png" % (look, name)):
        print("%s: no render of ours" % name)
        return (0, 0)
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, name)).convert("RGB"))
    if ref.shape[0] == ours.shape[0] and ref.shape[1] < ours.shape[1]:
        ours = ours[:, :ref.shape[1]]
    if ref.shape != ours.shape:
        print("%s: SIZE ref %s ours %s" % (name, ref.shape, ours.shape))
        return (0, 1)
    if only:  # --only x0,y0,x1,y1: compare inside this rectangle alone (everything else painted with the sheet background)
        keep_r, keep_o = ref.copy(), ours.copy()
        ref[:] = ref[0, 0]
        ours[:] = ref[0, 0]
        x0, y0, x1, y1 = only
        ref[y0:y1, x0:x1] = keep_r[y0:y1, x0:x1]
        ours[y0:y1, x0:x1] = keep_o[y0:y1, x0:x1]
    for (x0, y0, x1, y1) in masks:
        ref[y0:y1, x0:x1] = ref[0, 0]
        ours[y0:y1, x0:x1] = ref[0, 0]
    smask = looks_struct.struct_mask(ref)
    npass = 0
    out = []
    bs = lc.cells(ref)
    for i, b in enumerate(bs):
        x0, y0, x1, y1 = b
        a = ref[y0:y1, x0:x1]
        o = ours[y0:y1, x0:x1]
        bg = lc.cellkey(ref, b)
        d = np.abs(a.astype(int) - o.astype(int)).max(axis=2)
        off = (d > 2) & smask[y0:y1, x0:x1]
        tb = text_boxes(a, bg) | text_boxes(o, bg)
        chrome = off & ~tb
        text = off & tb
        ok = {t: lc.agree(lc.lines(a, bg, t), lc.lines(o, bg, t)) for t in (60, 100, 150)}
        ink = ok[60] and (ok[100] or ok[150])
        good = int(chrome.sum()) == 0 and ink
        npass += good
        wy, wx = np.unravel_index(int(np.where(chrome, d, 0).argmax()), d.shape)
        out.append("  cell %2d %-20s chrome_off %4d (max %3d at %d,%d)  text_off %4d (max %3d)  ink60/100/150 %d%d%d  %s" % (
            i, str(b), int(chrome.sum()), int(np.where(chrome, d, 0).max()), x0 + wx, y0 + wy, int(text.sum()),
            int(np.where(text, d, 0).max()), int(ok[60]), int(ok[100]), int(ok[150]), "PASS" if good else "FAIL"))
    print("%s [%s]: %d of %d cells pass" % (name, look, npass, len(bs)))
    for l in out:
        print(l)
    return (npass, len(bs))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    masks = []
    only = None
    look = "windows"
    if "--lum" in sys.argv:
        lc.LUM = True  # ink boxes on luminance: ClearType colour fringes (a text artefact) do not count as ink
    if "--only" in sys.argv:
        i = sys.argv.index("--only")
        only = tuple(int(v) for v in sys.argv[i + 1].split(","))
        args = [a for a in args if a != sys.argv[i + 1]]
    if "--dir" in sys.argv:
        look = sys.argv[sys.argv.index("--dir") + 1]
        args = [a for a in args if a != look]
    for a_ in list(args):
        if a_.count(",") == 3 and a_.replace(",", "").isdigit():
            masks.append(tuple(int(v) for v in a_.split(",")))
            args.remove(a_)
    for n in args:
        audit(n, look, masks, only)
