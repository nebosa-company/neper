"""Worker l4's Linux look comparer (round 20): list_box, check_list_box, tree_list, vertical_grid, data_grid, dialog.

  python -I scripts/linux_cmp_l4.py compose [sheet ...]     write ref/linux/composite/{light,dark}/<sheet>.png (the harness puts it beside ours)
  python -I scripts/linux_cmp_l4.py cmp [sheet ...]         strict compare of docs/ui/looks/linux[-dark]/<sheet>.png with the crops, per cell
  python -I scripts/linux_cmp_l4.py cmp --png [sheet ...]   also write ref | ours | off-pixels strips to $L4OUT (default D:/Temp/l4out)
  python -I scripts/linux_cmp_l4.py ink <sheet> <cell>      print the ink components of a reference crop (to write the `text` rects)

Strict metric: a reference pixel is off when any channel of ours differs by more than 2 levels. Only glyph pixels are set aside: the
reference's ink inside a cell's `text` rectangles (pixels that differ from the rectangle's flat colour by more than 2 levels) grown by
2 px, and coloured artwork inside `art` rectangles (a tick, a disclosure arrow, an icon) grown by 1 px. Borders, fills, rules, shadows
and rings are never set aside. The crop is compared whole (the library's pictures are clipped to the widget, so there is nothing outside).
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = ROOT / "docs/ui/looks"
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
MARGIN, SPACING, CAPTION = 12, 10, 16 + 4
OUT = Path(os.environ.get("L4OUT", "D:/Temp/l4out"))

# cells: crop names; text / art: {crop: [(x0, y0, x1, y1)]} in crop pixels (x1, y1 exclusive).
SHEETS = {
    "list_box": {
        "columns": 3, "cell_w": 240, "cell_h": 211,
        "cells": ["listbox", "listbox-selected", "listbox-hover"],
        "text": {c: [(8, 8, 90, 40), (8, 56, 90, 88), (8, 104, 90, 136), (8, 152, 90, 184)] for c in ("listbox", "listbox-selected", "listbox-hover")},
        "art": {},
    },
    "check_list_box": {"columns": 1, "cell_w": 240, "cell_h": 112, "cells": ["check-list"], "text": {"check-list": [(30, 5, 66, 25), (30, 36, 66, 56), (30, 67, 76, 87)]}, "art": {"check-list": [(8, 39, 22, 52)]}},
    "tree_list": {"columns": 2, "cell_w": 280, "cell_h": 210, "cells": ["treeview", "treeview-selected"],
                  "text": {c: [(4, 5, 60, 27), (112, 5, 152, 27)] + [(r, 32 + 23 * i + 3, w, 32 + 23 * i + 21) for i in range(7) for (r, w) in ((22, 108), (112, 170))] for c in ("treeview", "treeview-selected")},
                  "art": {c: [(3, 32 + 23 * i + 6, 19, 32 + 23 * i + 17) for i in (0, 3, 6)] for c in ("treeview", "treeview-selected")}},
    "vertical_grid": {"columns": 2, "cell_w": 340, "cell_h": 349, "cells": ["action-rows", "preferences-group"], "text": {}, "art": {}},
    "data_grid": {"columns": 1, "cell_w": 300, "cell_h": 220, "cells": ["columnview"],
                  "text": {"columnview": [(4, 6, 56, 26), (58, 6, 108, 26)] + [(r, 31 + 35 * i + 3, w, 31 + 35 * i + 32) for i in range(6) for (r, w) in ((4, 56), (58, 108))]}, "art": {}},
    "dialog": {"columns": 1, "cell_w": 570, "cell_h": 430, "cells": ["alert-dialog"],
                  "text": {"alert-dialog": [(215, 158, 336, 182), (196, 190, 352, 210), (172, 245, 232, 264), (318, 245, 378, 264)]}, "art": {}},
}


def origin(sheet, i):
    col, row = i % sheet["columns"], i // sheet["columns"]
    x = MARGIN + col * (sheet["cell_w"] + SPACING)
    y = MARGIN + row * (CAPTION + sheet["cell_h"] + SPACING) + CAPTION
    return x, y


def size(sheet):
    n = len(sheet["cells"])
    rows = (n + sheet["columns"] - 1) // sheet["columns"]
    w = MARGIN * 2 + sheet["columns"] * sheet["cell_w"] + (sheet["columns"] - 1) * SPACING
    h = MARGIN * 2 + rows * (CAPTION + sheet["cell_h"]) + (rows - 1) * SPACING
    return w, h


def crop_of(scheme, name):
    return Image.open(REF / scheme / ("%s@1x.png" % name)).convert("RGB")


def compose(name):
    sheet = SHEETS[name]
    for scheme in ("light", "dark"):
        im = Image.new("RGB", size(sheet), WINDOW[scheme])
        for i, crop in enumerate(sheet["cells"]):
            c = crop_of(scheme, crop)
            x, y = origin(sheet, i)
            im.paste(c, (x + (sheet["cell_w"] - c.width) // 2, y + (sheet["cell_h"] - c.height) // 2))
        out = REF / "composite" / scheme / (name + ".png")
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out, optimize=True)
        print("wrote", out.relative_to(ROOT))


def dilate(mask, r):
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
            xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
            out[yd, xd] |= mask[ys, xs]
    return out


def flat_colour(a):
    flat = a.reshape(-1, 3)
    vals, counts = np.unique(flat, axis=0, return_counts=True)
    return vals[counts.argmax()]


def ink_mask(ref, rects, grow, coloured=False):
    mask = np.zeros(ref.shape[:2], bool)
    for (x0, y0, x1, y1) in rects:
        x1, y1 = min(x1, ref.shape[1]), min(y1, ref.shape[0])
        if x1 <= x0 or y1 <= y0:
            continue
        part = ref[y0:y1, x0:x1].astype(int)
        base = flat_colour(part).astype(int)
        diff = np.abs(part - base).max(axis=2) > 2
        mask[y0:y1, x0:x1] |= diff
    return dilate(mask, grow)


def cmp_cell(sheet, scheme, folder, ours_im, i, crop, png):
    ref = np.asarray(crop_of(scheme, crop)).astype(int)
    h, w = ref.shape[:2]
    x0, y0 = origin(sheet, i)
    x0 += (sheet["cell_w"] - w) // 2
    y0 += (sheet["cell_h"] - h) // 2
    ours = np.asarray(ours_im).astype(int)[y0:y0 + h, x0:x0 + w]
    d = np.abs(ours - ref).max(axis=2)
    skip = ink_mask(ref, sheet["text"].get(crop, []), 2) | ink_mask(ref, sheet["art"].get(crop, []), 1)
    off = (d > 2) & ~skip
    if os.environ.get("L4BOX"):
        for (rx0, ry0, rx1, ry1) in sheet["text"].get(crop, []):
            box = []
            for img in (ref, ours):
                part = img[ry0:min(ry1, img.shape[0]), rx0:min(rx1, img.shape[1])]
                if part.size == 0:
                    continue
                bgc = flat_colour(part).astype(int)
                m = np.abs(part - bgc).max(axis=2) > 40
                ys, xs = np.nonzero(m)
                box.append((int(xs.min()) + rx0, int(ys.min()) + ry0, int(xs.max()) + rx0, int(ys.max()) + ry0) if len(xs) else None)
            if len(box) == 2:
                print("    text %s ref %s ours %s" % ((rx0, ry0), box[0], box[1]))
    if png:
        OUT.mkdir(parents=True, exist_ok=True)
        strip = np.zeros((h, w * 3 + 8, 3), np.uint8)
        strip[:, :w] = ref
        strip[:, w + 4:2 * w + 4] = ours
        vis = np.zeros((h, w, 3), np.uint8)
        vis[skip] = (60, 60, 120)
        vis[off] = (255, 0, 0)
        strip[:, 2 * w + 8:] = vis
        Image.fromarray(strip).resize((strip.shape[1] * 2, h * 2), Image.NEAREST).save(OUT / ("%s_%s_%s.png" % (folder, crop, scheme)))
    return int(off.sum()), int((~skip).sum()), int(d[~skip].max()), int(skip.sum())


def cmp(name, png):
    sheet = SHEETS[name]
    total = {}
    for scheme, folder in (("light", "linux"), ("dark", "linux-dark")):
        ours = Image.open(LOOKS / folder / (name + ".png")).convert("RGB")
        worst = 0
        print(scheme)
        for i, crop in enumerate(sheet["cells"]):
            off, n, mx, masked = cmp_cell(sheet, scheme, name, ours, i, crop, png)
            worst = max(worst, off)
            print("  %-28s off %5d of %6d compared (max %3d, %d masked)" % (crop, off, n, mx, masked))
        total[scheme] = worst
    print("%s worst state: light %d, dark %d" % (name, total["light"], total["dark"]))


def ink(name, cell):
    sheet = SHEETS[name]
    crop = sheet["cells"][int(cell)]
    ref = np.asarray(crop_of("light", crop)).astype(int)
    base = flat_colour(ref).astype(int)
    mask = dilate(np.abs(ref - base).max(axis=2) > 24, 3)
    seen = np.zeros(mask.shape, bool)
    h, w = mask.shape
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not seen[y, x]:
                stack, xs, ys = [(y, x)], [], []
                seen[y, x] = True
                while stack:
                    cy, cx = stack.pop()
                    xs.append(cx)
                    ys.append(cy)
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
                print("  (%d, %d, %d, %d)" % (min(xs), min(ys), max(xs) + 1, max(ys) + 1))


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args.pop(0) if args else "cmp"
    png = "--png" in args
    args = [a for a in args if a != "--png"]
    if cmd == "ink":
        ink(args[0], args[1])
    else:
        for n in (args or SHEETS):
            (compose if cmd == "compose" else (lambda s: cmp(s, png)))(n)
