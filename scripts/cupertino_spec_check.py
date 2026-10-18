#!/usr/bin/env python3
"""Regression test for the Cupertino look (profile CupertinoLike) without an Apple capture.

There is no Apple device or Apple-rendered image in this repository, so nothing here compares a pixel with a
real control. Instead the published iOS 17 / macOS 14 numbers that are known reliably (control sizes, system
colours with their alpha, corner radii) are written down once, below, and measured from the sheets that
`scripts/cup_run.sh` renders into docs/ui/looks/cupertino and cupertino-dark (1x and 1.5x). A change that moves a
control off those numbers, or a Dark colour off its dynamic pair, fails here.

Usage: python scripts/cupertino_spec_check.py [-v]   (run scripts/cup_run.sh first; exits 1 on any failure)
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOOKS = ROOT / "docs" / "ui" / "looks"
APPS = ROOT / "examples" / "looks"
VERBOSE = "-v" in sys.argv

# ------------------------------------------------------------------ the published numbers
# Every colour is (r, g, b, alpha) as UIKit documents it; `over` composites it on a surface.
SYSTEM = {
    "light": dict(
        grouped_bg=(0xF2, 0xF2, 0xF7), cell=(0xFF, 0xFF, 0xFF), blue=(0x00, 0x7A, 0xFF), red=(0xFF, 0x3B, 0x30),
        green=(0x34, 0xC7, 0x59), label=(0, 0, 0), secondary_label=(60, 60, 67, 0.60), placeholder=(60, 60, 67, 0.30),
        separator=(60, 60, 67, 0.29), fill_secondary=(120, 120, 128, 0.16), fill_tertiary=(118, 118, 128, 0.12),
        fill_system=(120, 120, 128, 0.20), bar=(0xF9, 0xF9, 0xF9)),
    "dark": dict(
        grouped_bg=(0x1C, 0x1C, 0x1E), cell=(0x2C, 0x2C, 0x2E), blue=(0x0A, 0x84, 0xFF), red=(0xFF, 0x45, 0x3A),
        green=(0x30, 0xD1, 0x58), label=(255, 255, 255), secondary_label=(235, 235, 245, 0.60),
        placeholder=(235, 235, 245, 0.30), separator=(84, 84, 88, 0.60), fill_secondary=(120, 120, 128, 0.32),
        fill_tertiary=(118, 118, 128, 0.24), fill_system=(120, 120, 128, 0.36), bar=(0x1D, 0x1D, 0x1D)),
}


def over(top, bg):
    """A colour (r, g, b[, alpha]) composited on an opaque surface."""
    a = top[3] if len(top) > 3 else 1.0
    return tuple(round(a * t + (1 - a) * b) for t, b in zip(top[:3], bg))


# ------------------------------------------------------------------ sheets
def sheet_table():
    """name -> (columns, cell_w, cell_h), read from the apps so the geometry has one home."""
    table = {}
    rx = re.compile(r'name: "([a-z_]+)", cells: (\d+)usize, columns: (\d+)usize, cell_w: ([\d.]+), cell_h: ([\d.]+)')
    for f in APPS.glob("cup_*.e"):
        for m in rx.finditer(f.read_text(encoding="utf-8")):
            table[m.group(1)] = (int(m.group(3)), float(m.group(4)), float(m.group(5)))
    return table


SHEETS = sheet_table()
_cache = {}


def sheet(scheme, name, scale):
    key = (scheme, name, scale)
    if key not in _cache:
        folder = "cupertino" if scheme == "light" else "cupertino-dark"
        suffix = "@1.5x" if scale == 1.5 else ""
        _cache[key] = np.array(Image.open(LOOKS / folder / (name + suffix + ".png")).convert("RGB")).astype(int)
    return _cache[key]


def cell(scheme, name, i, scale):
    """The crop of cell i (the harness lays cells out at margin 12, spacing 10, a 20 px caption row)."""
    cols, cw, ch = SHEETS[name]
    r, c = divmod(i, cols)
    x0 = 12 + c * (cw + 10)
    y0 = 12 + r * (16 + 4 + ch + 10) + 20
    img = sheet(scheme, name, scale)
    x, y, w, h = (round(v * scale) for v in (x0, y0, cw, ch))
    return img[y:y + h, x:x + w]


def page(scheme, scale=1.0):
    return tuple(int(v) for v in sheet(scheme, "button", scale)[2, 2])


def mode(crop, exclude=()):
    """The commonest colour of the crop that is not one of `exclude`."""
    flat = crop.reshape(-1, 3)
    vals, counts = np.unique(flat, axis=0, return_counts=True)
    for k in np.argsort(-counts):
        if tuple(int(v) for v in vals[k]) not in exclude:
            return tuple(int(v) for v in vals[k])
    return None


def coverage(px, fill, bg):
    ch = int(np.argmax([abs(f - b) for f, b in zip(fill, bg)]))
    return float(np.clip((px[ch] - bg[ch]) / (fill[ch] - bg[ch]), 0.0, 1.0))


def extent(line, fill, bg):
    """Sub-pixel length along a pixel line of the run of `fill` (flat colour) with its anti-aliased ends."""
    hit = np.where(np.abs(line - np.array(fill)).max(axis=1) <= 1)[0]
    if len(hit) == 0:
        return None
    a, b = int(hit.min()), int(hit.max())
    left = coverage(line[a - 1], fill, bg) if a > 0 else 0.0
    right = coverage(line[b + 1], fill, bg) if b + 1 < len(line) else 0.0
    return (b - a + 1) + left + right, a - left


def size_of(crop, fill, bg, scale):
    """(width, height, x, y) in logical px of the flat `fill` shape in the crop, measured on its centre row and column."""
    ys, xs = np.where(np.abs(crop - np.array(fill)).max(axis=2) <= 1)
    if len(xs) == 0:
        return None
    cy, cx = int(round(np.median(ys))), int(round(np.median(xs)))
    w, x = extent(crop[cy, :, :], fill, bg)
    h, y = extent(crop[:, cx, :], fill, bg)
    return w / scale, h / scale, x / scale, y / scale


def run_width(crop, bg, scale):
    """Logical width of the right-most shape on the centre row (a label, if any, is cut off by a gap of page)."""
    cy = crop.shape[0] // 2
    line = crop[cy]
    non = np.abs(line - np.array(bg)).max(axis=1) > 3
    end = int(np.where(non)[0].max())
    start = end
    while start > 0 and non[start - 1]:
        start -= 1
    fill = mode(crop[:, start:end + 1], (bg,))
    left = coverage(line[start], fill, bg) if fill else 1.0
    right = coverage(line[end], fill, bg) if fill else 1.0
    return (end - start - 1 + left + right) / scale


def rows_of(crop, colour, x):
    """How many rows of the column x hold exactly `colour` (a bar's flat face, which sits within 1 level of the page in Dark)."""
    return int((np.abs(crop[:, x, :] - np.array(colour)).max(axis=1) == 0).sum())


def radius_of(crop, fill, bg):
    """Corner radius (1x only) of the flat `fill` shape from how far its top row starts in from its left edge."""
    ys, xs = np.where(np.abs(crop - np.array(fill)).max(axis=2) <= 1)
    cy, cx = int(round(np.median(ys))), int(round(np.median(xs)))
    _, left = extent(crop[cy, :, :], fill, bg)
    _, top = extent(crop[:, cx, :], fill, bg)
    t = int(np.ceil(top - 1e-6))
    yoff = (t - top) + 0.5
    row = crop[t, :, :]
    start = int(left) - 2
    mid = cx
    covs = [coverage(row[x], fill, bg) for x in range(start, mid)]
    edge = mid - sum(covs)
    inset = edge - left
    best, err = 0.0, 1e9
    for r10 in range(0, 400):
        r = r10 / 10.0
        if r <= yoff:
            d = 0.0
        else:
            d = r - (r * r - (r - yoff) ** 2) ** 0.5
        if abs(d - inset) < err:
            best, err = r, abs(d - inset)
    return best


# ------------------------------------------------------------------ assertions
results = []


def check(name, got, want, tol, unit=""):
    ok = got is not None and abs(got - want) <= tol
    results.append((ok, name, got, want, tol, unit))


def check_rgb(name, got, want, tol=2):
    ok = got is not None and max(abs(g - w) for g, w in zip(got, want)) <= tol
    results.append((ok, name, got, want, tol, ""))


def check_true(name, ok, detail=""):
    results.append((bool(ok), name, detail, "true", 0, ""))


def ink_extreme(crop, dark_ink):
    """The most-inked pixel of text in the crop (darkest on Light, lightest on Dark)."""
    s = crop.sum(axis=2)
    i = np.unravel_index(s.argmax() if dark_ink else s.argmin(), s.shape)
    return tuple(int(v) for v in crop[i])


def run():
    for scheme in ("light", "dark"):
        S = SYSTEM[scheme]
        bg = S["grouped_bg"]
        tag = scheme + ": "
        dark = scheme == "dark"
        check_rgb(tag + "page is systemGroupedBackground (elevated level in Dark)", page(scheme), bg, 0)

        for scale in (1.0, 1.5):
            sc = "@1.5x " if scale == 1.5 else ""
            t = tag + sc

            # --- buttons: iOS configuration heights 44 / 34 / 28, macOS regular push button 22, large 28
            for name, idx, want_h in (("large", 25, 44), ("medium", 26, 34), ("small", 27, 28)):
                crop = cell(scheme, "button", idx, scale)
                m = size_of(crop, S["blue"], bg, scale)
                check(t + "button %s height" % name, m and m[1], want_h, 1.0, "pt")
                if scale == 1.0:
                    check_rgb(t + "button %s fill is systemBlue" % name, mode(crop, (bg,)), S["blue"], 0)
            crop = cell(scheme, "button", 30, scale)
            m = size_of(crop, S["blue"], bg, scale)
            check(t + "macOS regular push button height", m and m[1], 22, 1.0, "pt")
            check(t + "macOS regular push button least width", m and m[0], 64, 1.0, "pt")

            # --- switch 51 x 31, white thumb 27
            crop = cell(scheme, "switch", 5, scale)
            m = size_of(crop, S["green"], bg, scale)
            check(t + "switch height", m and m[1], 31, 1.0, "pt")
            check(t + "on switch width", run_width(crop, bg, scale), 51, 1.5, "pt")
            crop = cell(scheme, "switch", 0, scale)
            off = over(S["fill_secondary"], bg)
            check(t + "off switch width", run_width(crop, bg, scale), 51, 1.5, "pt")
            thumb = size_of(crop, (255, 255, 255), off, scale)
            check(t + "switch thumb diameter", thumb and thumb[1], 27, 1.0, "pt")

            # --- slider: 4 track, 28 round thumb, never clipped at either end
            for row, nm in ((0, "0%"), (2, "100%")):
                crop = cell(scheme, "slider", row * 5, scale)
                white = np.where(np.abs(crop - 255).max(axis=2) <= 1)
                wd = (white[1].max() - white[1].min() + 1) / scale
                hd = (white[0].max() - white[0].min() + 1) / scale
                check(t + "slider thumb at %s is round (w == h)" % nm, wd, hd, 1.5, "pt")
                check(t + "slider thumb at %s height" % nm, hd, 26, 2.0, "pt")  # 28 less its anti-aliased rim
            crop = cell(scheme, "slider", 5, scale)
            m = size_of(crop, S["blue"], bg, scale)
            check(t + "slider track thickness", m and m[1], 4, 1.0, "pt")

            # --- segmented control: 32 high
            crop = cell(scheme, "segmented_control", 0, scale)
            track = over(S["fill_tertiary"], bg)
            m = size_of(crop, track, bg, scale)
            check(t + "segmented control height", m and m[1], 32, 1.0, "pt")

            # --- stepper 94 x 32
            crop = cell(scheme, "spin_edit", 0, scale)
            m = size_of(crop, over(S["fill_tertiary"], bg), bg, scale)
            check(t + "stepper width", m and m[0], 94, 1.0, "pt")
            check(t + "stepper height", m and m[1], 32, 1.0, "pt")

            # --- search field 36 high
            crop = cell(scheme, "search_field", 0, scale)
            m = size_of(crop, over(S["fill_tertiary"], bg), bg, scale)
            check(t + "search field height", m and m[1], 36, 1.0, "pt")

            # --- progress view: 4 pt track (6 thick), activity indicator 20 / 37
            crop = cell(scheme, "progress_bar", 0, scale)
            ground = mode(crop, (bg,))
            check_rgb(t + "progress track is systemFill", ground, over(S["fill_system"], bg), 1)
            m = size_of(crop, ground, bg, scale)
            check(t + "progress track thickness", m and m[1], 4, 1.0, "pt")
            m = size_of(cell(scheme, "progress_bar", 3, scale), mode(cell(scheme, "progress_bar", 3, scale), (bg,)), bg, scale)
            check(t + "thick progress track thickness", m and m[1], 6, 1.0, "pt")

            # --- activity indicator: medium 20, large 37
            for idx, want in ((7, 20), (8, 37)):
                crop = cell(scheme, "progress_bar", idx, scale)
                ys, xs = np.where(np.abs(crop - np.array(bg)).max(axis=2) > 3)
                side = max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) / scale
                check(t + "activity indicator %d diameter" % want, side, want, 2.5, "pt")

            # --- alert 270 wide
            crop = cell(scheme, "dialog", 0, scale)
            face = mode(crop, (bg,))
            m = size_of(crop, face, bg, scale)
            check(t + "alert width", m and m[0], 270, 1.0, "pt")
            # stacked alert: three 44 pt rows under the text
            crop = cell(scheme, "dialog", 2, scale)
            m = size_of(crop, mode(crop, (bg,)), bg, scale)
            check_true(t + "stacked alert is taller than 3 x 44 + 80", m and m[1] > 212, m and round(m[1], 1))

            # --- navigation bar 44 + hairline, tab bar 49 + hairline
            crop = cell(scheme, "toolbar_button", 5, scale)
            check(t + "navigation bar height (44, less its hairline)", rows_of(crop, S["bar"], round(20 * scale)) / scale, 44, 2.0, "pt")
            crop = cell(scheme, "page_control", 5, scale)
            check(t + "tab bar height (49, less its hairline)", rows_of(crop, S["bar"], round(6 * scale)) / scale, 49, 2.0, "pt")

        # ---------------------------------------------- 1x only: colours and radii
        crop = cell(scheme, "switch", 5, 1.0)
        check_rgb(tag + "switch on is systemGreen", mode(crop, (bg,)), S["green"], 0)
        check_rgb(tag + "switch off is secondarySystemFill on the page", mode(cell(scheme, "switch", 0, 1.0), (bg,)), over(S["fill_secondary"], bg), 1)
        crop = cell(scheme, "button", 28, 1.0)
        check_rgb(tag + "destructive button is systemRed", mode(crop, (bg,)), S["red"], 0)
        crop = cell(scheme, "button", 10, 1.0)
        check_rgb(tag + "gray button is tertiarySystemFill", mode(crop, (bg,)), over(S["fill_tertiary"], bg), 1)
        crop = cell(scheme, "button", 5, 1.0)
        tint = mode(crop, (bg,))
        a = [(bg[i] - tint[i]) / (bg[i] - S["blue"][i]) for i in range(3) if bg[i] != S["blue"][i]]
        check_true(tag + "tinted button is the accent at 12 to 30 percent", all(0.12 <= v <= 0.30 for v in a), [round(v, 3) for v in a])

        # disabled filled button: tertiary fill look, label at about 30 percent
        crop = cell(scheme, "button", 4, 1.0)
        face = mode(crop, (bg,))
        lo, hi = over((118, 118, 128, 0.12), bg), over((118, 118, 128, 0.40), bg)
        check_true(tag + "disabled filled button face is a 12 to 40 percent system fill (no accent)",
                   all(min(a, b) - 1 <= f <= max(a, b) + 1 for f, a, b in zip(face, lo, hi)), face)

        # pressed prominent button is darker, hover lighter, than the accent
        rest = mode(cell(scheme, "button", 0, 1.0), (bg,))
        hover = mode(cell(scheme, "button", 1, 1.0), (bg,))
        press = mode(cell(scheme, "button", 2, 1.0), (bg,))
        check_true(tag + "filled button: hover lighter than rest, pressed darker", sum(hover) > sum(rest) > sum(press), (hover, rest, press))

        # focus ring on a button: the accent outside the control
        crop = cell(scheme, "button", 3, 1.0)
        ring = [tuple(int(v) for v in crop[27, x]) for x in range(0, 14)]
        has_ring = any(p[2] > p[0] + 40 for p in ring)
        check_true(tag + "focused button shows an accent ring", has_ring)

        # radii: alert 14 (Dark only: the Light face is 2 levels off the page), search 10, stepper 8
        if dark:
            crop = cell(scheme, "dialog", 0, 1.0)
            check(tag + "alert corner radius", radius_of(crop, mode(crop, (bg,)), bg), 14, 1.5, "pt")
        crop = cell(scheme, "search_field", 0, 1.0)
        check(tag + "search field corner radius", radius_of(crop, over(S["fill_tertiary"], bg), bg), 10, 1.5, "pt")
        crop = cell(scheme, "spin_edit", 0, 1.0)
        check(tag + "stepper corner radius", radius_of(crop, over(S["fill_tertiary"], bg), bg), 8, 1.5, "pt")

        # --- label colours
        crop = cell(scheme, "label", 0, 1.0)
        check_rgb(tag + "label ink is label", ink_extreme(crop, dark), S["label"], 0)
        crop = cell(scheme, "label", 1, 1.0)
        want = over(S["secondary_label"], bg)
        ink = ink_extreme(crop, dark)
        check_true(tag + "secondaryLabel composites on the page (rgba .6)",
                   all(abs(i - w) <= 12 and (i - w) * (1 if not dark else -1) >= -2 for i, w in zip(ink, want)), (ink, want))
        crop = cell(scheme, "label", 7, 1.0)
        check_true(tag + "link text is systemBlue", max(abs(a - b) for a, b in zip(ink_extreme(crop, dark), S["blue"])) <= 40, ink_extreme(crop, dark))

        # placeholder is placeholderText (rgba .3) on the field
        crop = cell(scheme, "text_edit", 0, 1.0)
        field = S["cell"]
        want = over(S["placeholder"], field)
        sub = crop[20:60, 10:190]
        ink = ink_extreme(sub, dark)
        check_true(tag + "placeholder composites placeholderText on the field",
                   all(abs(i - w) <= 14 and (i - w) * (1 if not dark else -1) >= -2 for i, w in zip(ink, want)), (ink, want))
        # text-field states
        crop = cell(scheme, "text_edit", 6, 1.0)
        reds = np.where((np.abs(crop - np.array(S["red"])).max(axis=2) <= 2))
        check_true(tag + "invalid text field draws a systemRed edge", len(reds[0]) > 100, len(reds[0]))
        crop = cell(scheme, "text_edit", 3, 1.0)
        halo = np.where((crop[:, :, 2] > crop[:, :, 0] + 60))
        check_true(tag + "focused text field shows the accent ring", len(halo[0]) > 150, len(halo[0]))
        crop = cell(scheme, "text_edit", 5, 1.0)
        ink = ink_extreme(crop[20:60, 10:190], dark)
        check_true(tag + "disabled text field label is dimmed (about 30 percent)",
                   all(abs(i - w) <= 30 for i, w in zip(ink, over((S["label"][0], S["label"][1], S["label"][2], 0.3), S["cell"]))), ink)

        # --- list rows: separators are a half-pixel line of the separator colour at 1x (the 0.33 pt hairline of a 3x
        # phone), rows are 44 pt apart (the touch minimum)
        crop = cell(scheme, "list_box", 0, 1.0)
        col = crop[:, 150, :]
        cell_rgb = S["cell"]
        full = over(S["separator"], cell_rgb)
        seps = [y for y in range(1, len(col) - 1)
                if tuple(col[y - 1]) == tuple(cell_rgb) and tuple(col[y + 1]) == tuple(cell_rgb) and tuple(col[y]) != tuple(cell_rgb)]
        share = [(cell_rgb[0] - int(col[y][0])) / (cell_rgb[0] - full[0]) for y in seps]
        check_true(tag + "list separators are half a pixel of the separator colour", seps and all(0.35 <= v <= 0.65 for v in share), [round(v, 2) for v in share])
        pitch = [b - a for a, b in zip(seps, seps[1:])]
        check_true(tag + "list rows are 44 pt apart", pitch and all(abs(p - 44) <= 1 for p in pitch), pitch)

        # --- checkbox and radio are 14 pt (macOS)
        crop = cell(scheme, "checkbox", 5, 1.0)
        m = size_of(crop, S["blue"], bg, 1.0)
        check(tag + "checkbox box width", m and m[0], 14, 1.0, "pt")
        check(tag + "checkbox box height", m and m[1], 14, 1.0, "pt")
        crop = cell(scheme, "radio", 5, 1.0)
        m = size_of(crop, S["blue"], bg, 1.0)
        check(tag + "radio disc diameter", m and m[0], 14, 1.0, "pt")

    # ---- every state a control claims is drawn differently from its rest cell (hover, pressed, focus, disabled, error)
    states = {
        "button": [(0, 1, "hover"), (0, 2, "pressed"), (0, 3, "focus"), (0, 4, "disabled"), (5, 7, "tinted pressed"), (5, 9, "tinted disabled"),
                   (10, 12, "gray pressed"), (15, 17, "plain pressed"), (20, 22, "bezel pressed"), (20, 24, "bezel disabled")],
        "switch": [(0, 2, "pressed"), (0, 3, "focus"), (0, 4, "disabled"), (5, 9, "on disabled")],
        "checkbox": [(0, 2, "pressed"), (0, 3, "focus"), (0, 4, "disabled"), (5, 7, "checked pressed"), (5, 9, "checked disabled"),
                     (10, 12, "mixed pressed"), (10, 14, "mixed disabled")],
        "radio": [(0, 2, "pressed"), (0, 3, "focus"), (0, 4, "disabled"), (5, 7, "selected pressed"), (5, 9, "selected disabled")],
        "segmented_control": [(0, 2, "pressed"), (0, 3, "focus"), (0, 4, "disabled")],
        "slider": [(0, 3, "focus"), (0, 4, "disabled")],
        "text_edit": [(1, 3, "focus"), (1, 5, "disabled"), (1, 6, "invalid"), (1, 7, "read only")],
        "search_field": [(0, 3, "focus"), (0, 4, "disabled")],
        "spin_edit": [(0, 3, "hover"), (0, 4, "pressed"), (0, 5, "focus"), (0, 6, "disabled"), (7, 10, "spin box disabled"), (7, 11, "spin box invalid")],
        "combo_box": [(0, 1, "hover"), (0, 2, "pressed"), (0, 3, "focus")],
        "dialog": [(2, 4, "pressed button")],
        "page_control": [(5, 8, "bar pressed"), (5, 9, "bar disabled"), (0, 3, "strip focus"), (0, 4, "strip disabled")],
    }
    for scheme in ("light", "dark"):
        for name, pairs in states.items():
            for rest, other, what in pairs:
                a, b = cell(scheme, name, rest, 1.0), cell(scheme, name, other, 1.0)
                n = int((np.abs(a - b).max(axis=2) > 3).sum()) if a.shape == b.shape else 10 ** 6
                check_true("%s: %s %s differs from rest" % (scheme, name, what), n > 20, n)

    # ---- the dynamic pairs, read straight from the tokens (Light vs Dark must be the documented pairs)
    src = (ROOT / "lib" / "e" / "ui" / "style.e").read_text(encoding="utf-8")
    body = src[src.index("fn cupertino(palette"):src.index("fn cupertino_separator")]
    for name, light, dk in (("blue", "0x007AFF", "0x0A84FF"), ("red", "0xFF3B30", "0xFF453A"), ("green", "0x34C759", "0x30D158"), ("orange", "0xFF9500", "0xFF9F0A")):
        check_true("tokens: system%s pair is %s / %s" % (name.capitalize(), light, dk),
                   re.search(r"var %s = %su32" % (name, light), body) is not None and re.search(r"%s = %su32" % (name, dk), body) is not None)
    check_true("tokens: secondaryLabel is rgba(60,60,67,.6) / rgba(235,235,245,.6)",
               "puta(&t, .TextMuted, 0x3C3C43u32, 0.6)" in body and "puta(&t, .TextMuted, 0xEBEBF5u32, 0.6)" in body)
    check_true("tokens: separator is rgba(60,60,67,.29) / rgba(84,84,88,.6)",
               "hexa_raw(0x3C3C43u32, 0.29)" in src and "hexa_raw(0x545458u32, 0.6)" in src)
    check_true("tokens: tertiary fill is rgba(118,118,128,.12) / .24", "0.24 * strength" in src and "0.12 * strength" in src)


def main():
    run()
    bad = [r for r in results if not r[0]]
    for ok, name, got, want, tol, unit in results:
        if VERBOSE or not ok:
            g = "%.2f" % got if isinstance(got, float) else str(got)
            print("%s  %s: got %s want %s (+/- %s)%s" % ("ok  " if ok else "FAIL", name, g, want, tol, unit and " " + unit))
    print("%d checks, %d failed" % (len(results), len(bad)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
