"""Strict comparison of our Windows dark sheets against the native Windows 11 dark captures (round 12).

`python -I scripts/looks_strict_dark.py <capture> <sheet.png> <x> <y> <w> <h> [--rect i] [--search N] [--dump out.png]`

<capture>: stem under docs/ui/looks/ref/windows-native/dark/ (e.g. edit-rest, taken at @1x).
<sheet>: our dark sheet (docs/ui/looks/windows-dark/<name>.png), <x> <y> <w> <h> the region of it to search (a cell).
The reference rectangle is the capture's control rect `--rect i` of controls.json (default 0), grown by --pad (default 0).
Headline (`flat off`): reference pixels equal to all eight neighbours (text anti-aliasing is never flat) where any channel of ours
differs by more than 2 levels, over the whole rect, nothing cut. Secondary: a reference pixel is OFF when any channel of ours differs by more than 2 levels.
Pixels within 2 px of text ink (interior of the control, more than 40 levels from the interior's most common colour, found on the
reference) are counted apart as `text`, since ClearType fringes cannot be reproduced by greyscale text; every other pixel is
`chrome` and the number that has to be zero for matched. Nothing is cut: the whole rect counts. The best offset in the search
window (fewest chrome off) is reported with it: the offset is a free parameter, size and inner geometry are tested.
"""
import json
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
NATIVE = os.path.join(HERE, "..", "docs", "ui", "looks", "ref", "windows-native") + os.sep
OURS = os.path.join(HERE, "..", "docs", "ui", "looks", "windows-dark") + os.sep
if os.environ.get("LOOKS_OURS"):  # round 13: render into a scratch folder instead of the committed sheets
    OURS = os.environ["LOOKS_OURS"].rstrip("/") + "/"


def load(p):
    return np.array(Image.open(p).convert("RGB")).astype(int)


def native(stem, scale="1x", rect=0, pad=0):
    key = "dark/%s@%s.png" % (stem, scale)
    img = load(NATIVE + key)
    cs = json.load(open(NATIVE + "controls.json"))[key]["controls"]
    if rect < 0:  # the union of the control rects (a spin edit: the edit and its up-down), without popups
        cs = [c for c in cs if c["class"] not in ("ComboLBox", "tooltips_class32")]
        x0, y0 = min(c["x"] for c in cs), min(c["y"] for c in cs)
        x1, y1 = max(c["x"] + c["w"] for c in cs), max(c["y"] + c["h"] for c in cs)
        c = {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}
    else:
        c = cs[rect]
    x, y, w, h = c["x"] - pad, c["y"] - pad, c["w"] + 2 * pad, c["h"] + 2 * pad
    return img, (x, y, w, h)


def text_mask(ref):
    h, w, _ = ref.shape
    inner = ref[3:h - 3, 3:w - 3].reshape(-1, 3)
    vals, counts = np.unique(inner, axis=0, return_counts=True)
    bg = vals[counts.argmax()]
    ink = np.zeros((h, w), bool)
    ink[3:h - 3, 3:w - 3] = np.abs(ref[3:h - 3, 3:w - 3] - bg).max(axis=2) > 12
    return ndimage.binary_dilation(ink, structure=np.ones((3, 3), bool), iterations=2)


def flat_mask(ref):
    """Reference pixels equal to all eight neighbours (the rect's own edge pixels count against the outside as non-flat)."""
    h, w, _ = ref.shape
    m = np.zeros((h, w), bool)
    c = ref[1:h - 1, 1:w - 1]
    ok = np.ones(c.shape[:2], bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                ok &= (ref[1 + dy:h - 1 + dy, 1 + dx:w - 1 + dx] == c).all(axis=2)
    m[1:h - 1, 1:w - 1] = ok
    return m


def glyph_mask(img):
    """Text glyph pixels: luminance above 90 inside the text zone (3 px in from the rect, 22 px short of the right end, where the
    button or chevron tile starts), grown by 1. Text is excluded from the flat count (ClearType against greyscale cannot agree)."""
    h, w, _ = img.shape
    lum = (img * np.array([0.299, 0.587, 0.114])).sum(axis=2)
    m = np.zeros((h, w), bool)
    m[ZONE[1]:h - ZONE[1], ZONE[0]:max(4, w - ZONE[2])] = lum[ZONE[1]:h - ZONE[1], ZONE[0]:max(4, w - ZONE[2])] > 70
    return ndimage.binary_dilation(m, structure=np.ones((3, 3), bool))


ZONE = [3, 3, 22]  # text zone: x start, y inset, right margin (the button or chevron tile)
FLAT = [0, 0, 0]
_CACHE = {}


def compare(ref, ours, tol=2):
    """-> (chrome off, text off, chrome px, max level over chrome); FLAT gets (flat px, flat off, max level over flat off)"""
    d = np.abs(ref - ours).max(axis=2)
    key = ref.tobytes()
    if key not in _CACHE:
        _CACHE.clear()
        _CACHE[key] = (flat_mask(ref) & ~glyph_mask(ref), glyph_mask(ref), text_mask(ref))
    fr, gr, tr = _CACHE[key]
    fm = fr & ~glyph_mask(ours)
    FLAT[0], FLAT[1], FLAT[2] = int(fm.sum()), int(((d > tol) & fm).sum()), int(d[fm].max())
    tm = tr | text_mask(ours)
    off = d > tol
    chrome = ~tm
    return int((off & chrome).sum()), int((off & tm).sum()), int(chrome.sum()), int(d[chrome].max())


def ink_box(img):
    """Bounding box (x0, y0, x1, y1) of glyph pixels (luminance above 50, text zone), None without any."""
    m = glyph_mask(img)
    lum = (img * np.array([0.299, 0.587, 0.114])).sum(axis=2)
    h, w, _ = img.shape
    z = np.zeros((h, w), bool)
    z[ZONE[1]:h - ZONE[1], ZONE[0]:max(4, w - ZONE[2])] = lum[ZONE[1]:h - ZONE[1], ZONE[0]:max(4, w - ZONE[2])] > 70
    ys, xs = np.where(z)
    return None if len(xs) == 0 else (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def best(ref, sheet, x, y, w, h, search, wide=0, anchor=None):
    rh, rw, _ = ref.shape
    top = None
    for dy in range(-search - wide // 2, search + wide // 2 + 1):
        for dx in range(-search - wide, search + wide + 1):
            px, py = (x + anchor[0] + dx, y + anchor[1] + dy) if anchor else (x + (w - rw) // 2 + dx, y + (h - rh) // 2 + dy)
            if px < 0 or py < 0 or px + rw > sheet.shape[1] or py + rh > sheet.shape[0]:
                continue
            r = compare(ref, sheet[py:py + rh, px:px + rw])
            r = r + tuple(FLAT)
            if top is None or r[5] + r[0] < top[0][5] + top[0][0]:
                top = (r, (px, py))
    return top


# native_dark sheet (examples/looks/native_dark.e): capture stem -> cell index, rect (-1 the union)
NATIVE_DARK = [("edit-rest", 0, 0), ("edit-hover", 1, 0), ("edit-focus", 2, 0), ("edit-selected", 3, 0), ("edit-readonly", 4, 0),
               ("edit-disabled", 5, 0), ("edit-password", 6, 0),
               ("spin-rest", 7, -1), ("spin-hover-up", 8, -1), ("spin-hover-down", 9, -1), ("spin-pressed-up", 10, -1),
               ("spin-pressed-down", 11, -1), ("spin-focus", 12, -1), ("spin-disabled", 13, -1),
               ("combo-edit-rest", 14, 0), ("combo-edit-hover", 15, 0), ("combo-edit-hover-arrow", 16, 0), ("combo-edit-focus", 17, 0),
               ("combo-edit-disabled", 18, 0),
               ("combo-list-rest", 19, 0), ("combo-list-hover", 20, 0), ("combo-list-hover-arrow", 21, 0), ("combo-list-focus", 22, 0),
               ("combo-list-disabled", 23, 0)]


NATIVE_DARK += [("button-rest", 24, 0), ("button-default", 25, 0), ("button-focus", 26, 0), ("button-default-focus", 27, 0),
                ("button-pressed", 28, 0), ("button-default-pressed", 29, 0), ("button-disabled", 30, 0)]
_i = 31
for _kind, _states in (("checkbox", ("unchecked", "checked", "indeterminate")), ("radio", ("unchecked", "checked"))):
    for _st in _states:
        for _col in ("rest", "focus", "pressed", "disabled"):
            NATIVE_DARK.append(("%s-%s-%s" % (_kind, _st, _col), _i, 0))
            _i += 1


NATIVE_DARK += [("edit-multiline-vscroll", 51, 0), ("label-rest", 52, 0), ("label-disabled", 53, 0), ("button-hover-pressed", 54, 0)]


def table(sheet="native_dark", spec=None, cols=7, cw=200, ch=100, only=None):
    sh = load(OURS + sheet + ".png")
    tot = 0
    for stem, idx, rect in (spec or NATIVE_DARK):
        if only and not stem.startswith(only):
            continue
        img, (rx, ry, rw, rh) = native(stem, rect=rect, pad=-1 if stem.startswith("button") else 0)  # a button's window rect has a 1 px margin
        ref = img[ry:ry + rh, rx:rx + rw]
        col, row = idx % cols, idx // cols
        x, y = 12 + col * (cw + 10), 12 + row * (16 + 4 + ch + 10) + 20
        ZONE[:] = [0, 0, 0] if stem.startswith('label') else [3, 3, 22]
        _CACHE.clear()
        anchor = (40, 39) if stem.startswith(("checkbox", "radio", "label")) else ((45, 34) if stem.startswith("button") else ((15, 5) if stem.startswith("edit-multiline") else None))
        if stem.startswith("edit-multiline"):
            rw = 148  # left of the (light, unthemed) scroll bar of the capture
            ref = img[ry:ry + rh, rx:rx + rw]
        anchor = (40, 39) if stem.startswith(("checkbox", "radio", "label")) else ((45, 34) if stem.startswith("button") else ((15, 5) if stem.startswith("edit-multiline") else None))
        if stem.startswith("edit-multiline"):
            rw = 148  # left of the (light, unthemed) scroll bar of the capture
            ref = img[ry:ry + rh, rx:rx + rw]
        r, at = best(ref, sh, x, y, cw, ch, 0 if stem.startswith('label') else 4, 0 if anchor else (40 if any(k in stem for k in ('hover-up', 'hover-down', 'pressed', 'arrow')) else 0), anchor)
        tot += r[5] + r[0]
        o = sh[at[1]:at[1] + rh, at[0]:at[0] + rw]
        bb_r, bb_o = ink_box(ref), ink_box(o)
        agree = bb_r is not None and bb_o is not None and max(abs(p - q) for p, q in zip(bb_r, bb_o)) <= 1
        pk = lambda im: int(((im * np.array([0.299, 0.587, 0.114])).sum(axis=2)[3:rh - 3, 3:max(4, rw - 22)]).max())
        print("ink %s %s %s peak %d/%d" % (bb_r, bb_o, "ok" if agree else "DIFF", pk(ref), pk(o)), end="  ")
        print("%-24s %3dx%-3d flat off %4d / %4d (max %3d)  chrome off %4d (text-adjacent %4d)  at %s" % (stem, rw, rh, r[5], r[4], r[6], r[0], r[1], at))
    print("total (flat + chrome) off", tot)


# native_dark2 sheet (examples/looks/native_dark2.e): (capture, cell index, rect index, (x, y) of the control in its cell, ref (x, y, w, h) override or None)
SHEET2 = [("vscroll-rest", 0, 0, (20, 10), None), ("hscroll-rest", 1, 0, (16, 20), None), ("tooltip-rest", 2, 1, (30, 40), None)]


def table2(only=None, cols=4, cw=260, ch=200):
    sh = load(OURS + "native_dark2.png")
    tot = 0
    for stem, idx, rect, anchor, over in SHEET2:
        if only and not stem.startswith(only):
            continue
        img, (rx, ry, rw, rh) = native(stem, rect=rect)
        ref = img[ry:ry + rh, rx:rx + rw]
        col, row = idx % cols, idx // cols
        x, y = 12 + col * (cw + 10), 12 + row * (16 + 4 + ch + 10) + 20
        ZONE[:] = [3, 3, 22]
        _CACHE.clear()
        r, at = best(ref, sh, x, y, cw, ch, 2, 0, anchor)
        o = sh[at[1]:at[1] + rh, at[0]:at[0] + rw]
        tot += r[5] + r[0]
        print("%-26s %3dx%-3d flat off %5d / %5d (max %3d)  chrome off %5d  at %s" % (stem, rw, rh, r[5], r[4], r[6], r[0], at))
    print("total (flat + chrome) off", tot)


def open_table():
    """combo-*-open captures (150 x 23 head + 150 x 122 list) against native_dark_open<n> (head at (20, 8) of its cell, 214 x 244 sheet)."""
    for n, stem in enumerate(("combo-edit-open", "combo-edit-open-hover-row", "combo-list-open", "combo-list-open-hover-row")):
        sh = load(OURS + "native_dark_open%d.png" % n)
        key = "dark/%s@1x.png" % stem
        img = load(NATIVE + key)
        cs = json.load(open(NATIVE + "controls.json"))[key]["controls"]
        x0, y0 = cs[0]["x"], cs[0]["y"]
        h = cs[0]["h"] + cs[1]["h"]
        ref = img[y0:y0 + h, x0:x0 + 150]
        ZONE[:] = [3, 3, 22]
        _CACHE.clear()
        r, at = best(ref, sh, 12, 32, 190, 200, 2, 0, (20, 8))  # cell origin (12, 32), the head at (20, 8) in it
        print("%-28s flat off %4d / %4d (max %3d)  chrome off %4d  at %s" % (stem, r[5], r[4], r[6], r[0], at))


def cmp_cell(sheet, cols, cw, ch, idx, stem, rect=0):
    """One cell of any dark sheet (cells cw x ch in `cols` columns, the sheet's own layout) against a native capture, the control centred in it."""
    sh = load(OURS + sheet + ".png")
    img, (rx, ry, rw, rh) = native(stem, rect=rect)
    ref = img[ry:ry + rh, rx:rx + rw]
    col, row = idx % cols, idx // cols
    x, y = 12 + col * (cw + 10), 12 + row * (16 + 4 + ch + 10) + 20
    ZONE[:] = [3, 3, 22]
    _CACHE.clear()
    r, at = best(ref, sh, x, y, cw, ch, 4)
    print("%-20s cell %2d vs %-14s flat off %4d / %4d (max %3d)  chrome off %4d  at %s" % (sheet, idx, stem, r[5], r[4], r[6], r[0], at))


def main():
    if "--cell" in sys.argv:
        a = [v for v in sys.argv[1:] if not v.startswith("--")]
        cmp_cell(a[0], int(a[1]), int(a[2]), int(a[3]), int(a[4]), a[5])
        return
    if "--two" in sys.argv:
        table2(only=([a for a in sys.argv[1:] if not a.startswith("--")] or [None])[0])
        return
    if "--open" in sys.argv:
        open_table()
        return
    if "--table" in sys.argv:
        table(only=([a for a in sys.argv[1:] if not a.startswith("--")] or [None])[0])
        return
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opt = {a.split("=")[0]: a.split("=")[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
    stem, sheetp = args[0], args[1]
    x, y, w, h = (int(v) for v in args[2:6])
    img, (rx, ry, rw, rh) = native(stem, rect=int(opt.get("--rect", 0)), pad=int(opt.get("--pad", 0)))
    ref = img[ry:ry + rh, rx:rx + rw]
    sheet = load(sheetp if os.path.exists(sheetp) else OURS + sheetp + ".png")
    r, at = best(ref, sheet, x, y, w, h, int(opt.get("--search", 4)))
    print("%s: ref %dx%d at ours %s: flat off %d of %d (max %d), chrome off %d, text-adjacent off %d" % (stem, rw, rh, at, r[5], r[4], r[6], r[0], r[1]))
    if "--dump" in opt:
        o = sheet[at[1]:at[1] + rh, at[0]:at[0] + rw]
        im = np.concatenate([ref, np.full((rh, 3, 3), 255), o, np.full((rh, 3, 3), 255), np.minimum(255, np.abs(ref - o) * 20)], axis=1)
        Image.fromarray(im.astype(np.uint8)).resize((im.shape[1] * 4, im.shape[0] * 4), Image.NEAREST).save(opt["--dump"])


if __name__ == "__main__":
    main()
