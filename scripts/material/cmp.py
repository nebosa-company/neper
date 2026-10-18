"""Compares a Neper Android-look sheet with the Material Web reference crops, cell by cell.

  python -I scripts/material/cmp.py <sheet> [--dark] [--png DIR] [--only substr]     (from the repository root)

The sheet's geometry mirrors e.ui.looks (margin 12, spacing 10, caption 16 + 4 above each cell): SHEETS[name] = columns, cell_w,
cell_h and `cells`, the reference crop name of each cell in order (None: no reference). A reference crop is the control's box plus
16 px on every side (docs/ui/looks/ref/material/manifest.csv, `margin=16`); it is placed in our cell centred, and the best
offset within 3 px is searched (reported as `shift`, ideally 0 0).
Strict metric: inside the cell's box (the part of the crop that lies in our cell, so captions and neighbours are not
compared), a reference pixel is STRUCTURAL when its 3 x 3 neighbourhood varies by at most 6 levels (flat fills, state layers and soft
shadow gradients; the anti-aliased rim of a shape does not qualify) and it is OFF when ours differs by more than 2 levels in any
channel. Glyph pixels (text and icon artwork: where the reference differs from its `-notext` render, grown by 2 px) are not counted
in `off`; `off+glyph` counts them. `rim` counts the rim pixels (not structural) that differ by more than 40 levels: a shape that
is too big, too small or in the wrong place shows there. Outside the control's box (+1 px) every pixel is compared (shadows, state layers; nothing else may be drawn there): `shadow` counts the structural ones off by more than 2 levels and the rim pixels (the rim of a shadow or of a state layer's circle) off by more than 24.
`ring` counts the pixels that are not structural but lie on a straight 1 or 2 px line (a 3 px run along x or along y that varies by at most 6 levels: the 2 px outline of a checkbox, a radio ring, a divider, the flat part of a rim) and differ by more than 12 levels (the rasteriser differs from Skia by a few levels on anti-aliased edges): a thin line is never flat in all directions, so the flat count cannot see its colour.
A cell passes with off == 0, shadow == 0 and ring == 0.
"""
import csv
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOOKS = os.path.join(ROOT, "docs/ui/looks")
REF = os.path.join(LOOKS, "ref/material")
MARGIN, SPACING, CAPTION, CROP = 12, 10, 20, 16

sys.path.insert(0, os.path.dirname(__file__))
from sheets import SHEETS  # noqa: E402


def manifest():
    out = {}
    with open(os.path.join(REF, "manifest.csv")) as f:
        for r in csv.DictReader(f):
            out[r["name"]] = (int(r["w_1x"]), int(r["h_1x"]))
    return out


def load(path):
    return np.array(Image.open(path).convert("RGB")).astype(int)


def spread(a):
    """max - min over each 3 x 3 neighbourhood, over all channels"""
    mx = ndimage.maximum_filter(a, size=(3, 3, 1), mode="nearest")
    mn = ndimage.minimum_filter(a, size=(3, 3, 1), mode="nearest")
    return (mx - mn).max(axis=2)


def line_flat(a):
    """3 px runs along x or along y that vary by at most 6 levels in every channel"""
    h = (ndimage.maximum_filter(a, size=(1, 3, 1), mode="nearest") - ndimage.minimum_filter(a, size=(1, 3, 1), mode="nearest")).max(axis=2)
    v = (ndimage.maximum_filter(a, size=(3, 1, 1), mode="nearest") - ndimage.minimum_filter(a, size=(3, 1, 1), mode="nearest")).max(axis=2)
    return (h <= 6) | (v <= 6)


def run(name, dark, png_dir, only):
    sheet = SHEETS[name]
    scheme = "dark" if dark else "light"
    ours = load(os.path.join(LOOKS, "material-dark" if dark else "material", name + ".png"))
    PAD = 32  # a control that overhangs its cell (a dialog) is compared over the sheet's edge pixels
    ours = np.pad(ours, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
    totals = [0, 0, 0, 0, 0, 0]
    results = []
    for i, ref_name in enumerate(sheet["cells"]):
        if ref_name is None or (only and only not in ref_name):
            continue
        ref = load(os.path.join(REF, scheme, ref_name + "@1x.png"))
        w, h = ref.shape[1] - 2 * CROP, ref.shape[0] - 2 * CROP
        raw = os.path.join(REF, scheme, ref_name + "@1x-notext.png")
        glyph = np.zeros(ref.shape[:2], bool)
        if os.path.exists(raw):
            glyph = ndimage.binary_dilation((np.abs(ref - load(raw)).max(axis=2) > 2), structure=np.ones((3, 3), bool), iterations=2)
        col, row = i % sheet["columns"], i // sheet["columns"]
        x0 = MARGIN + col * (sheet["cell_w"] + SPACING) + PAD
        y0 = MARGIN + row * (CAPTION + sheet["cell_h"] + SPACING) + CAPTION + PAD
        # the crop's origin in the sheet if the control is centred in the cell
        cx = x0 + (sheet["cell_w"] - w) / 2.0 - CROP
        cy = y0 + (sheet["cell_h"] - h) / 2.0 - CROP
        if "at" in sheet:  # a control that is placed, not centred (a menu under its anchor): its top left in the cell
            at = sheet["at"][i] if isinstance(sheet["at"][0], tuple) else sheet["at"]  # one point, or one per cell
            cx = x0 + at[0] - CROP
            cy = y0 + at[1] - CROP
        # the compared window: our cell box within the crop
        rx0 = max(0, int(round(x0 - cx)))
        ry0 = max(0, int(round(y0 - cy)))
        rx1 = min(ref.shape[1], int(round(x0 + sheet["cell_w"] - cx)))
        ry1 = min(ref.shape[0], int(round(y0 + sheet["cell_h"] - cy)))
        if sheet.get("full"):  # the control overhangs its cell (a tooltip or a dialog): compare its whole crop
            rx0, ry0, rx1, ry1 = 0, 0, ref.shape[1], ref.shape[0]
        st = spread(ref) <= 6
        win = np.zeros(st.shape, bool)
        win[ry0:ry1, rx0:rx1] = True
        # one pixel in from the window edge so the spread filter is not cut
        best = None
        bx, by = int(round(cx)), int(round(cy))
        # the centred position first; another offset wins only by more than 12 matching pixels (flat cells tie)
        for dx, dy in sorted(((a, b) for a in range(-3, 4) for b in range(-3, 4)), key=lambda p: abs(p[0]) + abs(p[1])):
            X0, Y0 = bx + dx, by + dy
            if X0 < 0 or Y0 < 0 or X0 + ref.shape[1] > ours.shape[1] or Y0 + ref.shape[0] > ours.shape[0]:
                continue
            o = ours[Y0:Y0 + ref.shape[0], X0:X0 + ref.shape[1]]
            d = np.abs(o - ref).max(axis=2)
            score = int(((d <= 2) & win).sum())
            if best is None or score > best[0] + 12:
                best = (score, dx, dy, d)
        if best is None:
            print("  %-34s outside the sheet" % ref_name)
            continue
        _, dx, dy, d = best
        X0, Y0 = bx + dx, by + dy
        m = win & st
        # our own ink next to the reference's glyphs (another icon drawing, another hinting) is glyph too: where ours differs from the
        # reference's glyph-less twin by more than 40 levels within 5 px of its glyph ink
        if os.path.exists(raw):
            o2 = ours[Y0:Y0 + ref.shape[0], X0:X0 + ref.shape[1]]
            near = ndimage.binary_dilation(np.abs(ref - load(raw)).max(axis=2) > 2, structure=np.ones((3, 3), bool), iterations=5)
            glyph = glyph | (near & (np.abs(o2 - load(raw)).max(axis=2) > 40))
        off = int(((d > 2) & m & ~glyph).sum())
        offg = int(((d > 2) & m).sum())
        zone = np.zeros(st.shape, bool)
        zone[CROP - 1:CROP + h + 1, CROP - 1:CROP + w + 1] = True
        rim = int(((d > 40) & win & ~st & ~glyph & zone).sum())
        outside_off = win & ~zone & (((d > 2) & st) | ((d > 24) & ~st))
        shadow = int(outside_off.sum())
        ring = int(((d > 12) & win & ~st & line_flat(ref) & ~glyph).sum())
        n = int((m & ~glyph).sum())
        totals[0] += n
        totals[1] += off
        totals[2] += offg
        totals[3] += rim
        totals[4] += shadow
        totals[5] += ring
        results.append((ref_name, dx, dy, n, off, offg, rim, shadow, int(d[m & ~glyph].max()) if (m & ~glyph).any() else 0, ring))
        print("  %-34s shift %2d %2d  structural px %5d  off %5d  off+glyph %5d  rim>40 %4d  shadow %5d  max %3d  ring %5d" % results[-1])
        if png_dir:
            os.makedirs(png_dir, exist_ok=True)
            X0, Y0 = bx + dx, by + dy
            o = ours[Y0:Y0 + ref.shape[0], X0:X0 + ref.shape[1]]
            mark = np.zeros_like(ref)
            mark[(d > 2) & m & ~glyph] = (255, 0, 0)
            mark[(d > 2) & m & glyph] = (255, 160, 0)
            mark[(d > 40) & win & ~st & ~glyph & zone] = (255, 0, 255)
            mark[outside_off] = (0, 120, 255)
            mark[(d > 2) & win & ~st & line_flat(ref) & ~glyph] = (0, 200, 0)
            tile = np.concatenate([ref, o, 255 - np.minimum(255, np.abs(o - ref) * 4), mark], axis=1)
            im = Image.fromarray(tile.astype(np.uint8))
            im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
            im.save(os.path.join(png_dir, "%s-%s-%s.png" % (scheme, name, ref_name)))
    print("%s %s: structural %d, off %d, off+glyph %d, rim>40 %d, shadow/outside %d, ring %d" % (name, scheme, *totals))
    return results


if __name__ == "__main__":
    args = sys.argv[1:]
    dark = "--dark" in args
    png = args[args.index("--png") + 1] if "--png" in args else None
    only = args[args.index("--only") + 1] if "--only" in args else None
    names = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--png", "--only"))]
    for n in names:
        run(n, dark, png, only)
