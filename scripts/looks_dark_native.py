"""Strict check of the Windows dark look against the native Windows 11 dark captures (docs/ui/looks/ref/windows-native/dark, 1x).

`python -I scripts/looks_dark_native.py [capture-prefix ...]`   (LOOKS_OURS=<folder> reads the dark sheets from there; LOOKS_THEME=light checks the Light captures against the windows sheets)

Metric. Every capture is cut to its control and popup rectangles plus 3 px and searched at whole-pixel offsets in every dark sheet of the
matching control and every native_dark sheet (nothing is cut from our sheet); the offset with the fewest flat px off wins. A reference
FLAT pixel is one in a horizontal or vertical run of 11 or more equal pixels, grown by one pixel (no colour count). It is OFF when any
channel of ours differs by more than 2 levels. Excluded, and only these: glyph pixels within 2 px of text ink, where ink is a pixel more
than 60 levels from the colour of the nearest run pixel (its local background, so white text on a selection fill counts), not in a run of
13 or more and not part of a dotted line; a piece counts as text only when another piece lies within 6 px in its line (a word), so isolated
check ticks, chevrons, radio dots, carets and selection fills stay in. No artwork is cut.
Prints per capture: sheet, offset, flat px, flat px off, flat px excluded as text.
"""
import glob
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
LOOKS = os.path.join(HERE, "..", "docs", "ui", "looks")
NATIVE = os.path.join(LOOKS, "ref", "windows-native")
GLYPHS = bool(os.environ.get("LOOKS_GLYPHS"))  # 1: glyph pixels are counted too (nothing is excluded as text)
THEME = os.environ.get("LOOKS_THEME", "dark")  # "light": the Light captures against the windows sheets
OURS = (os.environ.get("LOOKS_OURS") or os.path.join(LOOKS, "windows-dark" if THEME == "dark" else "windows")).rstrip("/\\")

# capture prefix -> dark sheets (by name prefix) that may hold it, besides every native_dark* sheet
SHEETS = {
    "radio": ["radio"], "label": ["label", "syslink"], "syslink": ["label", "syslink"], "button": ["button"],
    "edit": ["text_edit", "edits", "memo", "spin_edit", "mask_edit"], "spin": ["spin_edit", "edits"],
    "combo": ["combo_box", "image_combo_box"], "menu-popup": ["popup_menu"], "tooltip": ["hint"],
}


def load(p):
    return np.array(Image.open(p).convert("RGB"))


def runs(a, n):
    """Pixels in a horizontal or vertical run of n or more equal pixels."""
    m = np.zeros(a.shape[:2], bool)
    for axis in (0, 1):
        r = a if axis == 1 else a.transpose(1, 0, 2)
        eq = (r[:, 1:] == r[:, :-1]).all(axis=2)
        hh, ww = eq.shape[0], r.shape[1]
        left = np.ones((hh, ww), int)
        for x in range(1, ww):
            left[:, x] = np.where(eq[:, x - 1], left[:, x - 1] + 1, 1)
        right = np.ones((hh, ww), int)
        for x in range(ww - 2, -1, -1):
            right[:, x] = np.where(eq[:, x], right[:, x + 1] + 1, 1)
        k = (left + right - 1) >= n
        m |= k if axis == 1 else k.T
    return m


def dotted(a):
    """Pixels of a dotted line: every second pixel equal for 5 steps along a row or column, neighbours different."""
    m = np.zeros(a.shape[:2], bool)
    for axis in (0, 1):
        r = a if axis == 1 else a.transpose(1, 0, 2)
        hh, ww, _ = r.shape
        k = np.zeros((hh, ww), bool)
        for x in range(ww - 8):
            same = np.logical_and.reduce([(r[:, x + 2 * i] == r[:, x + 2 * i + 2]).all(axis=1) for i in range(4)])
            hit = same & (r[:, x] != r[:, x + 1]).any(axis=1)
            for i in range(9):
                k[:, x + i] |= hit
        m |= k if axis == 1 else k.T
    return m


def flat_mask(a):
    return ndimage.binary_dilation(runs(a, 11), structure=np.ones((3, 3), bool))


def text_zone(a):
    """Pixels within 2 px of text ink (see the module text)."""
    run = runs(a, 11)
    if not run.any():
        return np.zeros(run.shape, bool)
    idx = ndimage.distance_transform_edt(~run, return_distances=False, return_indices=True)
    bg = a[idx[0], idx[1]]
    ink = (np.abs(a.astype(int) - bg.astype(int)).max(axis=2) > 60) & ~runs(a, 13) & ~dotted(a)
    pieces, n = ndimage.label(ink, structure=np.ones((3, 3), bool))
    if n == 0:
        return np.zeros(ink.shape, bool)
    near = ndimage.binary_dilation(ink, structure=np.ones((1, 13), bool))
    groups, _ = ndimage.label(near, structure=np.ones((3, 3), bool))
    text = np.zeros(ink.shape, bool)
    for g in range(1, groups.max() + 1):
        inside = groups == g
        if len(np.unique(pieces[inside & ink])) >= 2:
            text |= inside & ink
    return ndimage.binary_dilation(text, structure=np.ones((5, 5), bool))


def crop_of(meta, rects=None):
    rects = rects or meta["controls"]
    return (max(0, min(r["x"] for r in rects) - 3), max(0, min(r["y"] for r in rects) - 3),
            max(r["x"] + r["w"] for r in rects) + 3, max(r["y"] + r["h"] for r in rects) + 3)


def sheets_for(capture):
    out = []
    for key, prefixes in SHEETS.items():
        if capture.startswith(key):
            for f in sorted(glob.glob(OURS + "/*.png")):
                b = os.path.basename(f)[:-4]
                if "@" in b or b.endswith("-vs-ref"):
                    continue
                if f not in out and (b.startswith("native_" + THEME) or any(b.startswith(p) for p in prefixes)):
                    out.append(f)
    return out


def check(capture, meta, cache, rects=None):
    ref = load(os.path.join(NATIVE, THEME, capture))
    x0, y0, x1, y1 = crop_of(meta, rects)
    a = ref[y0:y1, x0:x1]
    flat = flat_mask(a)
    txt = np.zeros(a.shape[:2], bool) if GLYPHS else text_zone(a)
    use = flat & ~txt
    h, w = a.shape[:2]
    best = None
    m = np.repeat(use[:, :, None], 3, axis=2).astype(np.float32)
    af = a.astype(np.float32)
    for f in sheets_for(capture):
        if f not in cache:
            cache[f] = load(f)
        s = cache[f]
        if s.shape[0] < h or s.shape[1] < w:
            continue
        r = cv2.matchTemplate(s.astype(np.float32), af, cv2.TM_SQDIFF, mask=m)
        for _ in range(3):  # the squared-error winners are re-scored with the real metric
            dy, dx = np.unravel_index(int(r.argmin()), r.shape)
            o = s[dy:dy + h, dx:dx + w]
            off = int((use & (np.abs(a.astype(int) - o.astype(int)).max(axis=2) > 2)).sum())
            if best is None or off < best[0]:
                best = (off, os.path.basename(f)[:-4], int(dx), int(dy))
            r[max(0, dy - 2):dy + 3, max(0, dx - 2):dx + 3] = np.inf
    return best, int(use.sum()), int((flat & txt).sum())


def main():
    meta = json.load(open(os.path.join(NATIVE, "controls.json")))
    prefixes = sys.argv[1:]
    cache = {}
    for key in sorted(meta):
        if not key.startswith(THEME + "/") or "@1x" not in key:
            continue
        cap = key[len(THEME) + 1:]
        if prefixes and not any(cap.startswith(p) for p in prefixes):
            continue
        if not any(cap.startswith(k) for k in SHEETS):
            continue
        jobs = [(cap, None)]
        if len(meta[key]["controls"]) > 1:  # a popup is placed on its own too: the gap to its owner differs from sheet to sheet
            jobs += [("%s [%s]" % (cap, r["class"]), [r]) for r in meta[key]["controls"]]
        for name, rects in jobs:
            best, nflat, ntext = check(cap, meta[key], cache, rects)
            if best is None:
                print("%-40s no placement" % name)
            else:
                print("%-40s %-24s at %4d,%-4d flat %5d  off %4d  text-excluded %4d" % (name, best[1], best[2], best[3], nflat, best[0], ntext))


if __name__ == "__main__":
    main()
