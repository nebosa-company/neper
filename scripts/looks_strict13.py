"""Round 13 strict comparison of our Windows dark sheets against the native Windows 11 dark captures.

`python -I scripts/looks_strict13.py [prefix ...]`   (prefix filters capture stems, e.g. edit spin combo-edit)

Metric (reference mask alone; nothing is ANDed with ours, no luminance mask):
  flat   a reference pixel equal to all eight neighbours; OFF when any channel of ours differs by more than 2 levels.
  other  every other reference pixel (borders, corners, anti-aliased edges); OFF by the same rule.
  Excluded: only the text zone = pixels within 2 px of a reference GLYPH pixel. A glyph pixel is a non-flat interior pixel (3 px in
  from the rect) that is not part of a straight run of 13 or more equal pixels (so borders and the straight edges of a selection
  fill are not glyphs). Selection fills, carets, borders and backgrounds are counted everywhere outside that 2 px halo.
  `zone` = off pixels inside the halo, reported but not required to be zero (ClearType against greyscale text).
Placement: the control rect is searched at +-4 px in our cell (the offset with fewest flat+other off outside the zone wins), reported.
Ink: bounding box of the glyph pixels of both images (must agree within 1 px).
"""
import json
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import looks_strict_dark as sd  # native(), load(), the sheet layout tables  # noqa: E402
if os.environ.get("LOOKS_OURS"):
    sd.OURS = os.environ["LOOKS_OURS"].rstrip("/") + "/"

TOL = 2


def runs_mask(img, n=13):
    """pixels that lie in a horizontal or vertical run of n or more equal pixels"""
    h, w, _ = img.shape
    m = np.zeros((h, w), bool)
    for axis in (0, 1):
        a = img if axis == 1 else img.transpose(1, 0, 2)
        hh, ww, _ = a.shape
        mm = np.zeros((hh, ww), bool)
        for y in range(hh):
            x = 0
            while x < ww:
                x2 = x + 1
                while x2 < ww and (a[y, x2] == a[y, x]).all():
                    x2 += 1
                if x2 - x >= n:
                    mm[y, x:x2] = True
                x = x2
        m |= mm if axis == 1 else mm.T
    return m


def dots_mask(img, n=6):
    """pixels of a dotted line: along a row or a column the colour alternates (equal two apart, different one apart) for n or more steps"""
    h, w, _ = img.shape
    m = np.zeros((h, w), bool)
    for axis in (0, 1):
        a = img if axis == 1 else img.transpose(1, 0, 2)
        hh, ww, _ = a.shape
        mm = np.zeros((hh, ww), bool)
        for y in range(hh):
            row = a[y]
            alt = np.zeros(ww, bool)
            for x in range(ww - 2):
                alt[x] = (row[x] == row[x + 2]).all() and not (row[x] == row[x + 1]).all()
            x = 0
            while x < ww:
                if alt[x]:
                    x2 = x
                    while x2 < ww and alt[x2]:
                        x2 += 1
                    if x2 - x >= n:
                        mm[y, x:x2 + 2] = True
                    x = x2
                else:
                    x += 1
        m |= mm if axis == 1 else mm.T
    return m


INSET = [3]  # glyphs are looked for this far in from the rect (0 for a borderless label)


def glyph_pixels(ref):
    h, w, _ = ref.shape
    flat = sd.flat_mask(ref)
    g = ~flat & ~runs_mask(ref) & ~dots_mask(ref)
    inner = np.zeros((h, w), bool)
    k = INSET[0]
    inner[k:h - k, k:w - k] = True
    return g & inner


def zone_of(ref):
    return ndimage.binary_dilation(glyph_pixels(ref), structure=np.ones((3, 3), bool), iterations=2)


def ink_box(ref):
    ys, xs = np.where(glyph_pixels(ref))
    return None if len(xs) == 0 else (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def measure(ref, ours):
    d = np.abs(ref - ours).max(axis=2)
    flat = sd.flat_mask(ref)
    zone = zone_of(ref)
    off = d > TOL
    return {
        "flat": int(flat.sum()),
        "flat_off": int((off & flat & ~zone).sum()),
        "other_off": int((off & ~flat & ~zone).sum()),
        "zone_off": int((off & zone).sum()),
        "max": int(d[~zone].max()),
        "zone_mean": float(d[zone].mean()) if zone.any() else 0.0,
    }


def place(ref, sheet, cx, cy, cw, ch, search=4, anchor=None):
    rh, rw, _ = ref.shape
    zone = zone_of(ref)
    top = None
    for dy in range(-search, search + 1):
        for dx in range(-search, search + 1):
            if anchor:
                px, py = cx + anchor[0] + dx, cy + anchor[1] + dy
            else:
                px, py = cx + (cw - rw) // 2 + dx, cy + (ch - rh) // 2 + dy
            if px < 0 or py < 0 or px + rw > sheet.shape[1] or py + rh > sheet.shape[0]:
                continue
            d = np.abs(ref - sheet[py:py + rh, px:px + rw]).max(axis=2) > TOL
            score = int((d & ~zone).sum())
            if top is None or score < top[0]:
                top = (score, px, py)
    return top[1], top[2]


def row(label, ref, ours, at):
    r = measure(ref, ours)
    bb_r, bb_o = ink_box(ref), ink_box(ours)
    ink = "ink n/a" if bb_r is None or bb_o is None else ("ink ok" if max(abs(p - q) for p, q in zip(bb_r, bb_o)) <= 1 else "INK %s/%s" % (bb_r, bb_o))
    ok = r["flat_off"] == 0 and r["other_off"] == 0
    print("%-34s %-4s flat off %4d/%5d other off %4d zone off %4d (mean %4.1f) max %3d  %s  at %s" % (
        label, "PASS" if ok else "FAIL", r["flat_off"], r["flat"], r["other_off"], r["zone_off"], r["zone_mean"], r["max"], ink, at))
    return ok


def dump(ref, ours, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w, _ = ref.shape
    im = np.concatenate([ref, np.full((h, 3, 3), 255), ours, np.full((h, 3, 3), 255), np.minimum(255, np.abs(ref - ours) * 20)], axis=1)
    Image.fromarray(im.astype(np.uint8)).resize((im.shape[1] * 4, im.shape[0] * 4), Image.NEAREST).save(path)


def native_dark_table(only, outdir):
    sh = sd.load(sd.OURS + "native_dark.png")
    cols, cw, ch = 7, 200, 100
    results = []
    for stem, idx, rect in sd.NATIVE_DARK:
        if only and not any(stem.startswith(o) for o in only):
            continue
        img, (rx, ry, rw, rh) = sd.native(stem, rect=rect, pad=-1 if stem.startswith("button") else 0)
        if stem.startswith("edit-multiline"):
            rw = 148
        ref = img[ry:ry + rh, rx:rx + rw]
        col, r_ = idx % cols, idx // cols
        x, y = 12 + col * (cw + 10), 12 + r_ * (16 + 4 + ch + 10) + 20
        INSET[0] = 0 if stem.startswith("label") else 3
        anchor = (40, 39) if stem.startswith(("checkbox", "radio", "label")) else ((45, 34) if stem.startswith("button") else ((15, 5) if stem.startswith("edit-multiline") else None))
        wide = 40 if any(k in stem for k in ("hover-up", "hover-down", "pressed", "arrow")) and not stem.startswith(("button", "checkbox", "radio")) else 0
        # the spin cells sit anywhere in a wider cell: search wider in x
        best = None
        for extra in ([0] if not wide else [0]):
            px, py = place(ref, sh, x, y, cw, ch, 0 if stem.startswith("label") else 4, anchor) if not wide else place_wide(ref, sh, x, y, cw, ch, wide)
            best = (px, py)
        px, py = best
        ours = sh[py:py + rh, px:px + rw]
        ok = row(stem, ref, ours, (px, py))
        if outdir:
            dump(ref, ours, os.path.join(outdir, stem + ".png"))
        results.append((stem, ok))
    return results


def place_wide(ref, sheet, cx, cy, cw, ch, wide):
    rh, rw, _ = ref.shape
    zone = zone_of(ref)
    top = None
    for dy in range(-6, 7):
        for dx in range(-wide, wide + 1):
            px, py = cx + (cw - rw) // 2 + dx, cy + (ch - rh) // 2 + dy
            if px < 0 or py < 0 or px + rw > sheet.shape[1] or py + rh > sheet.shape[0]:
                continue
            d = np.abs(ref - sheet[py:py + rh, px:px + rw]).max(axis=2) > TOL
            score = int((d & ~zone).sum())
            if top is None or score < top[0]:
                top = (score, px, py)
    return top[1], top[2]


def mask_table(outdir):
    """native_dark_mask (examples/looks/native_dark_mask.e): a formatted field in the six edit states against the native edit captures."""
    sh = sd.load(sd.OURS + "native_dark_mask.png")
    cols, cw, ch = 6, 200, 100
    res = []
    for idx, stem in enumerate(("edit-rest", "edit-hover", "edit-focus", "edit-selected", "edit-readonly", "edit-disabled")):
        img, (rx, ry, rw, rh) = sd.native(stem)
        ref = img[ry:ry + rh, rx:rx + rw]
        col, r_ = idx % cols, idx // cols
        x, y = 12 + col * (cw + 10), 12 + r_ * (16 + 4 + ch + 10) + 20
        px, py = place(ref, sh, x, y, cw, ch, 4)
        ours = sh[py:py + rh, px:px + rw]
        res.append(row("mask-" + stem[5:] + " vs " + stem, ref, ours, (px, py)))
        if outdir:
            dump(ref, ours, os.path.join(outdir, "mask-" + stem + ".png"))
    return res


def sheet_table(sheet, cols, cw, ch, spec, outdir, only=None, search=2):
    """spec: (capture stem, cell index, rect index of controls.json, (x, y) of the control in its cell [or None], (w, h) crop override [or None])"""
    sh = sd.load(sd.OURS + sheet + ".png")
    res = []
    for stem, idx, rect, anchor, over in spec:
        if only and not any(stem.startswith(o) for o in only):
            continue
        img, (rx, ry, rw, rh) = sd.native(stem, rect=rect, pad=-1 if stem.startswith('button') else 0)  # a button's window rect has a 1 px margin
        if over:
            rw, rh = over
        ref = img[ry:ry + rh, rx:rx + rw]
        col, r_ = idx % cols, idx // cols
        x, y = 12 + col * (cw + 10), 12 + r_ * (16 + 4 + ch + 10) + 20
        px, py = place(ref, sh, x, y, cw, ch, search, anchor)
        ours = sh[py:py + rh, px:px + rw]
        res.append(row(stem, ref, ours, (px, py)))
        if outdir:
            dump(ref, ours, os.path.join(outdir, stem + ".png"))
    return res


# native_dark2 (examples/looks/native_dark2.e)
SHEET2 = [("vscroll-rest", 0, 0, (20, 10), None), ("hscroll-rest", 1, 0, (16, 20), None), ("tooltip-rest", 2, 1, (30, 40), None),
          ("vscroll-pressed-arrow", 3, 0, (20, 10), None), ("vscroll-disabled", 4, 0, (20, 10), None),
          ("hscroll-pressed-arrow", 5, 0, (16, 20), None), ("hscroll-disabled", 6, 0, (16, 20), None),
          # captures pixel-identical to rest (the pointer did not make the bar hot): compared against the rest cell
          ("vscroll-hover-arrow", 0, 0, (20, 10), None), ("vscroll-hover-thumb", 0, 0, (20, 10), None),
          ("vscroll-hover-track", 0, 0, (20, 10), None), ("vscroll-pressed-thumb", 0, 0, (20, 10), None),
          ("hscroll-hover-arrow", 1, 0, (16, 20), None), ("hscroll-hover-thumb", 1, 0, (16, 20), None),
          ("hscroll-pressed-thumb", 1, 0, (16, 20), None)]
# not compared: hscroll-hover-track (the whole bar rect is the #202020 window colour: the bar was not painted in that capture)


# native_dark3 (examples/looks/native_dark3.e): the control's face (rect grown by -1 for a button) at (20, 20) of its 260 x 200 cell
SHEET3 = [("button-split", 0, 0, (20, 20), None), ("button-split-pressed", 1, 0, (20, 20), None), ("button-split-disabled", 2, 0, (20, 20), None),
          ("button-split-hover-main", 0, 0, (20, 20), None), ("button-split-hover-arrow", 0, 0, (20, 20), None),
          ("button-icon", 3, 0, (20, 20), None), ("button-icon-disabled", 4, 0, (20, 20), None), ("button-icon-hover", 3, 0, (20, 20), None)]


# native_dark4 (examples/looks/native_dark4.e): list box (16, 10), check list (16, 10) and the popup menu (20, 20) in 260 x 200 cells
SHEET4 = [("listbox-rest", 0, 0, (16, 10), (99, 110)), ("listbox-selected-focused", 1, 0, (16, 10), (99, 110)),
          ("listbox-selected-unfocused", 2, 0, (16, 10), (99, 110)), ("listbox-hover", 2, 0, (16, 10), (99, 110)),
          ("checklist-rest", 3, 0, (16, 10), None), ("checklist-selected-focused", 4, 0, (16, 10), None)]
# listbox: only the 99 columns left of the scroll column are compared (the capture's scroll column is the light unthemed one)


def open_table(outdir):
    """combo-*-open captures: the head (150 x 23) and its list (150 x 122) against native_dark_open<n> (head at (20, 8) of a cell at (12, 32))."""
    ok_all = []
    for n, stem in enumerate(("combo-edit-open", "combo-edit-open-hover-row", "combo-list-open", "combo-list-open-hover-row")):
        sh = sd.load(sd.OURS + "native_dark_open%d.png" % n)
        key = "dark/%s@1x.png" % stem
        img = sd.load(sd.NATIVE + key)
        cs = json.load(open(sd.NATIVE + "controls.json"))[key]["controls"]
        x0, y0 = cs[0]["x"], cs[0]["y"]
        h = cs[0]["h"] + cs[1]["h"]
        ref = img[y0:y0 + h, x0:x0 + 150]
        # the head and the list are compared as two parts: the list rows are text-free flat bands plus text
        px, py = place(ref, sh, 12, 32, 190, 200, 2, (20, 8))
        ours = sh[py:py + h, px:px + 150]
        ok_all.append(row(stem + " (head+list)", ref, ours, (px, py)))
        if outdir:
            dump(ref, ours, os.path.join(outdir, stem + ".png"))
    return ok_all


if __name__ == "__main__":
    if "--two" in sys.argv:
        r = sheet_table("native_dark2", 4, 260, 200, SHEET2, ([a.split("=", 1)[1] for a in sys.argv if a.startswith("--dump=")] or [None])[0])
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    if "--three" in sys.argv:
        r = sheet_table("native_dark3", 4, 260, 200, SHEET3, ([a.split("=", 1)[1] for a in sys.argv if a.startswith("--dump=")] or [None])[0])
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    if "--four" in sys.argv:
        r = sheet_table("native_dark4", 4, 260, 200, SHEET4, ([a.split("=", 1)[1] for a in sys.argv if a.startswith("--dump=")] or [None])[0], search=4)
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    if "--mask" in sys.argv:
        r = mask_table(([a.split("=", 1)[1] for a in sys.argv if a.startswith("--dump=")] or [None])[0])
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    if "--open" in sys.argv:
        r = open_table(([a.split("=", 1)[1] for a in sys.argv if a.startswith("--dump=")] or [None])[0])
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    outdir = None
    for a in sys.argv[1:]:
        if a.startswith("--dump="):
            outdir = a.split("=", 1)[1]
    res = native_dark_table(only, outdir)
    print("PASS %d / %d" % (sum(1 for _, ok in res if ok), len(res)))
