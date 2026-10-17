"""Round 15 check of the Windows dark editors against the native Windows 11 dark captures (docs/ui/looks/ref/windows-native/dark).

`python -I scripts/looks_w1.py [prefix ...]`   (LOOKS_OURS=<folder> reads the dark sheets from there instead of docs/ui/looks/windows-dark)

Metric. A reference pixel is OFF when any channel of ours differs by more than 2 levels (reference rect only, nothing ANDed with ours).
Excluded, and counted apart as `ink`: the pixels within 2 px of a glyph pixel of the reference, where a glyph pixel is a pixel that
differs by more than 40 levels from one of its eight neighbours and is not part of a run of 12 or more equal pixels (borders, selection
edges), not a dotted focus line, and not at the rect's edge. Never excluded, even inside that halo: a pixel in a run of 12 or more equal
pixels of colour other than the crop's most common one in the reference or in ours (selection fills, the caret, the scroll column).
`chrome` is what has to be zero; `ink` is ClearType against greyscale text. The control is placed at the cell's anchor (no search),
except the spin edit, whose pointer cell is searched around its aim.
"""
import json
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_strict_dark as sd  # noqa: E402
import looks_strict13 as s13  # noqa: E402

OURS = (os.environ.get("LOOKS_OURS") or os.path.join(HERE, "..", "docs", "ui", "looks", "windows-dark")).rstrip("/\\") + os.sep


def runs(a, axis, n=12):
    r = a if axis == 1 else a.transpose(1, 0, 2)
    hh, ww, _ = r.shape
    eq = (r[:, 1:] == r[:, :-1]).all(axis=2)
    left = np.ones((hh, ww), int)
    for x in range(1, ww):
        left[:, x] = np.where(eq[:, x - 1], left[:, x - 1] + 1, 1)
    right = np.ones((hh, ww), int)
    for x in range(ww - 2, -1, -1):
        right[:, x] = np.where(eq[:, x], right[:, x + 1] + 1, 1)
    m = (left + right - 1) >= n
    return m if axis == 1 else m.T


def halo(ref):
    h, w, _ = ref.shape
    big = np.zeros((h, w), bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                big |= np.abs(np.roll(np.roll(ref, dy, 0), dx, 1) - ref).max(axis=2) > 40
    seed = big & ~runs(ref, 1) & ~runs(ref, 0) & ~s13.dots_mask(ref)
    seed[0, :] = seed[-1, :] = False
    seed[:, 0] = seed[:, -1] = False
    return ndimage.binary_dilation(seed, structure=np.ones((3, 3), bool), iterations=2)


def solid(a):
    v, c = np.unique(a.reshape(-1, 3), axis=0, return_counts=True)
    return (runs(a, 0) | runs(a, 1)) & ~(a == v[c.argmax()]).all(axis=2)


def compare(ref, ours):
    d = np.abs(ref - ours).max(axis=2) > 2
    ex = halo(ref) & ~(solid(ref) | solid(ours))
    return int((d & ~ex).sum()), int((d & ex).sum())


def cell_xy(idx, cols=7, cw=200, ch=100):
    col, row = idx % cols, idx // cols
    return 12 + col * (cw + 10), 12 + row * (16 + 4 + ch + 10) + 20


def sheet(name):
    return sd.load(OURS + name + ".png")


def row(label, chrome, ink, at):
    print("%-34s chrome off %4d   ink %4d   at %s" % (label, chrome, ink, at))
    return chrome


def native_dark_table(only):
    sh = sheet("native_dark")
    tot = 0
    for stem, idx, rect in sd.NATIVE_DARK[:24]:
        if only and not stem.startswith(only):
            continue
        img, (rx, ry, rw, rh) = sd.native(stem, rect=rect)
        ref = img[ry:ry + rh, rx:rx + rw]
        x, y = cell_xy(idx)
        best = None
        spin = any(k in stem for k in ("hover-up", "hover-down", "pressed", "arrow"))
        for dy in range(-30 if spin else 0, 31 if spin else 1):
            for dx in range(-30 if spin else 0, 31 if spin else 1):
                px, py = x + (200 - rw) // 2 + dx, y + (100 - rh) // 2 + dy
                if px < 0 or py < 0 or px + rw > sh.shape[1] or py + rh > sh.shape[0]:
                    continue
                d = int((np.abs(ref - sh[py:py + rh, px:px + rw]).max(axis=2) > 2).sum())
                if best is None or d < best[0]:
                    best = (d, px, py)
        _, px, py = best
        tot += row(stem, *compare(ref, sh[py:py + rh, px:px + rw]), (px, py))
    return tot


def multiline():
    sh = sheet("native_dark")
    tot = 0
    for k, stem in enumerate(("edit-multiline-rest", "edit-multiline-focus", "edit-multiline-selected", "edit-multiline-readonly", "edit-multiline-disabled")):
        img, (rx, ry, rw, rh) = sd.native(stem, rect=0)
        x, y = cell_xy(55 + k)
        tot += row(stem, *compare(img[ry:ry + rh, rx:rx + rw], sh[y + 5:y + 5 + rh, x + 15:x + 15 + rw]), (x + 15, y + 5))
    # the scroll bar: the Explorer themed capture inside its (white) frame, the border against the CFD capture's
    x, y = cell_xy(51)
    img, (rx, ry, rw, rh) = sd.native("edit-multiline-explorer", rect=0)
    ours = sh[y + 5:y + 5 + rh, x + 15:x + 15 + rw]
    tot += row("edit-multiline-explorer (inside)", *compare(img[ry + 2:ry + rh - 2, rx + 2:rx + rw - 2], ours[2:rh - 2, 2:rw - 2]), (x + 17, y + 7))
    img, (rx, ry, rw, rh) = sd.native("edit-multiline-vscroll", rect=0)
    ref = img[ry:ry + rh, rx:rx + rw]
    frame = np.ones((rh, rw), bool)
    frame[2:rh - 2, 2:rw - 2] = False
    d = (np.abs(ref - ours).max(axis=2) > 2) & frame
    tot += row("edit-multiline-vscroll (frame only)", int(d.sum()), 0, (x + 15, y + 5))
    return tot


def opens():
    tot = 0
    for n, stem in ((0, "combo-edit-open"), (1, "combo-edit-open-hover-row"), (2, "combo-list-open"), (3, "combo-list-open-hover-row"),
                    (4, "combo-list-open"), (5, "combo-list-open-hover-row")):
        sh = sheet("native_dark_open%d" % n)
        key = "dark/%s@1x.png" % stem
        img = sd.load(sd.NATIVE + key)
        cs = json.load(open(sd.NATIVE + "controls.json"))[key]["controls"]
        h = cs[0]["h"] + cs[1]["h"]
        ref = img[cs[0]["y"]:cs[0]["y"] + h, cs[0]["x"]:cs[0]["x"] + 150]
        best = None
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                o = sh[40 + dy:40 + dy + h, 32 + dx:32 + dx + 150]
                if o.shape != ref.shape:
                    continue
                d = int((np.abs(ref - o).max(axis=2) > 2).sum())
                if best is None or d < best[0]:
                    best = (d, 32 + dx, 40 + dy)
        _, px, py = best
        tot += row("%s%s" % (stem, " (image combo)" if n >= 4 else ""), *compare(ref, sh[py:py + h, px:px + 150]), (px, py))
    return tot


def icb_and_button_edit():
    sh = sheet("native_dark_icb")
    tot = 0
    # cells of 200 x 100 in 5 columns: 0 rest, 1 hover, 2 disabled, 3 picture, 4 focus; then 5 to 9 the button edit
    for idx, stem in ((0, "combo-list-rest"), (1, "combo-list-hover"), (2, "combo-list-disabled"), (4, "combo-list-focus")):
        img, (rx, ry, rw, rh) = sd.native(stem, rect=0)
        x, y = cell_xy(idx, cols=5)
        tot += row("image combo vs " + stem, *compare(img[ry:ry + rh, rx:rx + rw], sh[y + 38:y + 38 + rh, x + 25:x + 25 + rw]), (x + 25, y + 38))
    for k, stem in enumerate(("edit-rest", "edit-hover", "edit-disabled", "edit-readonly", "edit-focus")):
        img, (rx, ry, rw, rh) = sd.native(stem, rect=0)
        x, y = cell_xy(5 + k, cols=5)
        # the field only: the ellipsis button (the last 28 columns) has no native counterpart
        tot += row("button edit field vs " + stem, *compare(img[ry:ry + rh, rx:rx + 122], sh[y + 38:y + 38 + rh, x + 25:x + 25 + 122]), (x + 25, y + 38))
    return tot


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    total = 0
    if not only or "edit" in only or "spin" in only or "combo" in only:
        total += native_dark_table(only[0] if only else None)
    if not only or "multi" in only:
        total += multiline()
    if not only or "open" in only:
        total += opens()
    if not only or "icb" in only:
        total += icb_and_button_edit()
    print("total chrome off", total)


if __name__ == "__main__":
    main()
