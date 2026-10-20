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


def bad_lines(a, o, bg, t):
    """(lines whose ink boxes differ by more than 1 px, lines in the reference) at level t; unequal counts: every reference line."""
    la, lo = lc.lines(a, bg, t), lc.lines(o, bg, t)
    if len(la) != len(lo):
        return len(la), len(la)
    return sum(1 for u, v in zip(la, lo) if max(abs(p - q) for p, q in zip(u, v)) > 1), len(la)


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


def place(a, ours):
    """Where the reference cell `a` sits in `ours` (a sheet with other margins and captions): the offset (dx, dy) at which most of the cell's
    structural pixels (a subsample) are equal, searched over every offset the size difference allows."""
    h, w, _ = a.shape
    H, W, _ = ours.shape
    if h > H or w > W:
        return None
    sm = looks_struct.struct_mask(a)
    ys, xs = np.where(sm)
    if len(ys) == 0:
        ys, xs = np.where(np.ones((h, w), bool))
    step = max(1, len(ys) // 3000)
    ys, xs = ys[::step], xs[::step]
    vals = a[ys, xs]
    best = None
    for dy in range(0, H - h + 1):
        for dx in range(0, W - w + 1):
            eq = float((np.abs(ours[ys + dy, xs + dx].astype(int) - vals.astype(int)).max(axis=1) <= 2).mean())
            if best is None or eq > best[0]:
                best = (eq, dx, dy)
    return best


def audit_placed(name, look, masks, only, cols=None):
    ref = np.array(Image.open(lc.refpath(name)).convert("RGB"))
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, name)).convert("RGB"))
    smask = looks_struct.struct_mask(ref)
    npass = 0
    out = []
    bs = lc.cells(ref)
    # a reference that is one crop (a menu, a list: its text and icons fall apart as cells) is placed as one piece
    bs = [(min(b[0] for b in bs), min(b[1] for b in bs), max(b[2] for b in bs), max(b[3] for b in bs))]
    for i, b in enumerate(bs):
        x0, y0, x1, y1 = b
        a = ref[y0:y1, x0:x1]
        found = place(a, ours)
        if not found:
            out.append("  cell %2d %-20s NOT FOUND in our sheet" % (i, str(b)))
            continue
        eq, dx, dy = found
        o = ours[dy:dy + (y1 - y0), dx:dx + (x1 - x0)]
        sm = smask[y0:y1, x0:x1]
        bg = lc.cellkey(ref, b)
        d = np.abs(a.astype(int) - o.astype(int)).max(axis=2)
        if cols:  # --cols x0,x1: v3's icon column (coloured bitmaps, artwork) painted out of both pieces
            cx0, cx1 = cols
            a = a.copy()
            o = o.copy()
            a[:, cx0 - x0:cx1 - x0] = bg
            o[:, cx0 - x0:cx1 - x0] = bg
            sm = sm.copy()
            sm[:, cx0 - x0:cx1 - x0] = False
        d = np.abs(a.astype(int) - o.astype(int)).max(axis=2)
        off = (d > 2) & sm
        tb = text_boxes(a, bg) | text_boxes(o, bg)
        chrome = off & ~tb
        text = off & tb
        ok = {t: lc.agree(lc.lines(a, bg, t), lc.lines(o, bg, t)) for t in (60, 100, 150)}
        ink = ok[60] and (ok[100] or ok[150])
        good = int(chrome.sum()) == 0 and ink
        npass += good
        wy, wx = np.unravel_index(int(np.where(chrome, d, 0).argmax()), d.shape)
        bl = bad_lines(a, o, bg, 100)
        out.append("  cell %2d %-20s at ours (%d,%d) equal %.3f  chrome_off %4d (max %3d at %d,%d)  text_off %4d (max %3d)  ink60/100/150 %d%d%d  lines bad@100 %d/%d  %s" % (
            i, str(b), dx, dy, eq, int(chrome.sum()), int(np.where(chrome, d, 0).max()), x0 + wx, y0 + wy, int(text.sum()),
            int(np.where(text, d, 0).max()), int(ok[60]), int(ok[100]), int(ok[150]), bl[0], bl[1], "PASS" if good else "FAIL"))
    print("%s [%s] (placed): %d of %d cells pass" % (name, look, npass, len(bs)))
    for l in out:
        print(l)
    return (npass, len(bs))


def audit(name, look="windows", masks=(), only=None, cols=None):
    ref = np.array(Image.open(lc.refpath(name)).convert("RGB"))
    if not os.path.exists(ROOT + "%s/%s.png" % (look, name)):
        print("%s: no render of ours" % name)
        return (0, 0)
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, name)).convert("RGB"))
    if ref.shape[0] == ours.shape[0] and ref.shape[1] < ours.shape[1]:
        ours = ours[:, :ref.shape[1]]
    if ref.shape != ours.shape:
        return audit_placed(name, look, masks, only, cols)
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
    cols = None
    look = "windows"
    if "--cols" in sys.argv:  # sheets whose reference is one crop placed in ours: mask the columns x0..x1 of the reference (v3's icon column)
        i = sys.argv.index("--cols")
        cols = tuple(int(v) for v in sys.argv[i + 1].split(","))
        args = [a for a in args if a != sys.argv[i + 1]]
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
        audit(n, look, masks, only, cols)
