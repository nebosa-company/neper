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
          ("hscroll-pressed-thumb", 1, 0, (16, 20), None), ("tooltip-balloon", 8, 1, (30, 40), None)]
# not compared: hscroll-hover-track (the whole bar rect is the #202020 window colour: the bar was not painted in that capture)


# native_dark3 (examples/looks/native_dark3.e): the control's face (rect grown by -1 for a button) at (20, 20) of its 260 x 200 cell
SHEET3 = [("button-split", 0, 0, (20, 20), None), ("button-split-pressed", 1, 0, (20, 20), None), ("button-split-disabled", 2, 0, (20, 20), None),
          ("button-split-hover-main", 0, 0, (20, 20), None), ("button-split-hover-arrow", 0, 0, (20, 20), None),
          ("button-icon", 3, 0, (20, 20), None), ("button-icon-disabled", 4, 0, (20, 20), None), ("button-icon-hover", 3, 0, (20, 20), None)]


# native_dark4 (examples/looks/native_dark4.e): list box (16, 10), check list (16, 10) and the popup menu (20, 20) in 260 x 200 cells
SHEET4 = [("listbox-rest", 0, 0, (16, 10), (99, 110)), ("listbox-selected-focused", 1, 0, (16, 10), (99, 110)),
          ("listbox-selected-unfocused", 2, 0, (16, 10), (99, 110)), ("listbox-hover", 2, 0, (16, 10), (99, 110))]
# (the check list keeps v3's 15 px rows, so it is compared by element: check_list_elements)
# listbox: only the 99 columns left of the scroll column are compared (the capture's scroll column is the light unthemed one)


def check_list_elements():
    """Element comparison of the dark check list (v3's 15 px rows kept, so no whole-control diff): the two check box tiles pixel for pixel,
    the face, border and chosen-row colours (focused and unfocused) against checklist-* of the native dark captures."""
    sh = sd.load(sd.OURS + "native_dark4.png")
    cl = sd.load(sd.NATIVE + "dark/checklist-rest@1x.png")[10:120, 16:174]
    fo = sd.load(sd.NATIVE + "dark/checklist-selected-focused@1x.png")[10:120, 16:174]
    un = sd.load(sd.NATIVE + "dark/checklist-selected-unfocused@1x.png")[10:120, 16:174]
    # cell 3 (rest) at (822, 32) and cell 4 (focused) at (12, 262), the list at (16, 10) in its cell
    rest = sh[32 + 10:32 + 120, 822 + 16:822 + 16 + 158]
    foc = sh[262 + 10:262 + 120, 12 + 16:12 + 16 + 158]
    unf = sh[262 + 10:262 + 120, 282 + 16:282 + 16 + 158]  # cell 5
    res = []

    def tile(name, ref, ours, rx, ry):
        best = None
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                o = ours[ry + dy:ry + dy + 13, rx + dx:rx + dx + 13]
                if o.shape[:2] != (13, 13):
                    continue
                d = int((np.abs(o - ref).max(axis=2) > TOL).sum())
                if best is None or d < best[0]:
                    best = (d, dx, dy)
        print("%-34s %-4s px off %3d of 169 at offset %s" % (name, "PASS" if best[0] == 0 else "FAIL", best[0], best[1:]))
        res.append(best[0] == 0)

    tile("check tile unchecked (row 1)", cl[5:18, 6:19], rest, 3, 3)
    tile("check tile checked (row 2, rest)", cl[24:37, 6:19], rest, 3, 18)
    # the chosen row of the focused cell: fill and outline colours at a fill pixel and an outline pixel of the bar (ours: row 2 = rows 17..31)
    def colour(name, ref_px, ours_px):
        d = max(abs(a - b) for a, b in zip(ref_px, ours_px))
        print("%-34s %-4s ref %s ours %s (max %d)" % (name, "PASS" if d <= TOL else "FAIL", ref_px, ours_px, d))
        res.append(d <= TOL)

    colour("face", cl[8, 100].tolist(), rest[8, 100].tolist())
    colour("border line", cl[50, 0].tolist(), rest[50, 0].tolist())
    colour("chosen row fill (focused)", fo[30, 100].tolist(), foc[24, 100].tolist())
    colour("chosen row fill (unfocused)", un[30, 100].tolist(), unf[24, 100].tolist())
    colour("chosen row line (unfocused)", un[30, 2].tolist(), unf[24, 2].tolist())
    colour("chosen row line (focused)", fo[30, 2].tolist(), foc[24, 2].tolist())
    return res


def menu_elements():
    """Element comparison of the dark popup menu (v3's Tahoma rows kept): border, face, divider lines and the text peaks against menu-popup-rest."""
    ref_full = sd.load(sd.NATIVE + "dark/menu-popup-rest@1x.png")
    ours_full = sd.load(sd.OURS + "native_dark5.png")

    def rect_of(img):
        m = (img == np.array([128, 128, 128])).all(axis=2)
        rows = np.where(m.sum(axis=1) >= 60)[0]
        cols = np.where(m.sum(axis=0) >= 60)[0]
        return cols.min(), rows.min(), cols.max(), rows.max()

    res = []
    out = []
    for nm, img in (("ref", ref_full), ("ours", ours_full)):
        x0, y0, x1, y1 = rect_of(img)
        r = img[y0:y1 + 1, x0:x1 + 1]
        lum = r.sum(axis=2) / 3
        flat_rows = set()
        for y in range(2, r.shape[0] - 2):
            row = r[y, 2:r.shape[1] - 2]
            other = [tuple(p) for p in row.tolist() if tuple(p) not in ((43, 43, 43), (44, 44, 44))]
            if len(other) > 60 and len(set(other)) == 1:
                flat_rows.add(other[0])
        flat_rows = sorted(flat_rows)
        peaks = []
        runs, start, prev = [], None, None
        for y in range(r.shape[0]):
            on = (lum[y, 30:100] > 70).any()
            if on and start is None:
                start = y
            if not on and start is not None:
                runs.append((start, y - 1))
                start = None
        for a_, b_ in runs:
            peaks.append(int(lum[a_:b_ + 1, 30:100].max()))
        out.append((nm, (x1 - x0 + 1, y1 - y0 + 1), tuple(r[0, 5].tolist()), flat_rows, peaks))
    print("ref  size %s border %s flat rows %s text peaks %s" % out[0][1:])
    print("ours size %s border %s flat rows %s text peaks %s" % out[1][1:])
    ok_border = out[0][2] == out[1][2]
    ref_flat, our_flat = set(out[0][3]), set(out[1][3])
    # face rows differ by one level at most (#2B2B2B and #2C2C2C are both the face); the divider line colour must agree
    ref_div = {c for c in ref_flat if c != (43, 43, 43) and c != (44, 44, 44)}
    our_div = {c for c in our_flat if c != (43, 43, 43) and c != (44, 44, 44)}
    print("border %s, divider colours %s / %s, disabled text peak %s / %s" % ("PASS" if ok_border else "FAIL", ref_div, our_div, min(out[0][4]), min(out[1][4])))
    res.append(ok_border)
    res.append(ref_div == our_div)
    res.append(abs(min(out[0][4]) - min(out[1][4])) <= TOL)
    res.append(max(out[0][4]) == max(out[1][4]))
    return res


def palette_presence():
    """Presence of the native dark list view and tree colours in our dark sheets (v3's stripes and geometry stay, so this is a palette
    check, not a pixel diff): each colour must occur in the native captures and in at least one of our grid or tree sheets."""
    import collections

    def counts(path, box=None):
        a = sd.load(path)
        if box:
            a = a[box[1]:box[3], box[0]:box[2]]
        return collections.Counter(map(tuple, a.reshape(-1, 3).tolist()))

    lv = counts(sd.NATIVE + "dark/listview-selected-focused@1x.png", (12, 10, 238, 140))
    lu = counts(sd.NATIVE + "dark/listview-selected-unfocused@1x.png", (12, 10, 238, 140))
    tf = counts(sd.NATIVE + "dark/tree-selected-focused@1x.png", (16, 10, 184, 140))
    tu = counts(sd.NATIVE + "dark/tree-selected-unfocused@1x.png", (16, 10, 184, 140))
    ours = collections.Counter()
    for name in ("data_grid", "data_grid_states", "data_grid_hover", "tree_list", "tree_list_focus", "tree_list_hover"):
        path = sd.OURS + name + ".png"
        if os.path.exists(path):
            ours.update(counts(path))
    want = [("list view header #191919", (25, 25, 25), lv), ("list view face #202020", (32, 32, 32), lv), ("list view frame #828790", (130, 135, 144), lv),
            ("list view chosen row focused #1A364D", (26, 54, 77), lv), ("list view chosen line focused #0078D4", (0, 120, 212), lv),
            ("list view chosen row unfocused #1B1B1B", (27, 27, 27), lu), ("list view chosen line unfocused #131313", (19, 19, 19), lu),
            ("list view track #171717", (23, 23, 23), lv), ("tree row focused #626262", (98, 98, 98), tf), ("tree row unfocused #333333", (51, 51, 51), tu)]
    res = []
    for name, colour, native in want:
        ok = native.get(colour, 0) > 0 and ours.get(colour, 0) > 0
        print("%-42s %-4s native %5d px, ours %6d px" % (name, "PASS" if ok else "FAIL", native.get(colour, 0), ours.get(colour, 0)))
        res.append(ok)
    return res


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
    if "--checklist" in sys.argv:
        r = check_list_elements()
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    if "--menu" in sys.argv:
        r = menu_elements()
        print("PASS %d / %d" % (sum(r), len(r)))
        sys.exit(0)
    if "--palette" in sys.argv:
        r = palette_presence()
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
