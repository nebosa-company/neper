"""Compose GTK reference crops into a sheet laid out like an e.ui.looks sheet, so the harness can put it beside ours.

  python -I scripts/linux/compose_ref.py <sheet> [...]      (from anywhere; paths are derived from this file)

Writes docs/ui/looks/ref/linux/composite/{light,dark}/<sheet>.png: the sheet's window colour, each reference crop
(docs/ui/looks/ref/linux/<scheme>/<crop>@1x.png) centred in its cell. The geometry mirrors looks.e (margin 12, spacing 10,
caption 16 + 4 above each cell); keep the SHEETS entry in step with the sheet app's Sheet{...} and the cell order.
`cells` is a list of crop names (None: an empty cell). Only 100 % exists: the library was rendered at 1x and 2x.

  python -I scripts/linux/compose_ref.py --diff <sheet>     compare docs/ui/looks/linux[-dark]/<sheet>.png with the composite
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = ROOT / "docs/ui/looks"
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
MARGIN, SPACING, CAPTION = 12, 10, 16 + 4

BUTTON_ROWS = ["default", "suggested", "destructive", "flat", "circular", "icon", "flat-icon", None]
BUTTON_STATES = ["normal", "hover", "active", "focus", "disabled"]
SHEETS = {
    "button": {
        "columns": 5, "cell_w": 100, "cell_h": 44,
        "cells": [None if r is None else "button-%s-%s" % (r, s) for r in BUTTON_ROWS for s in BUTTON_STATES],
    },
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


def compose(name):
    sheet = SHEETS[name]
    for scheme in ("light", "dark"):
        im = Image.new("RGB", size(sheet), WINDOW[scheme])
        for i, crop in enumerate(sheet["cells"]):
            if crop is None:
                continue
            c = Image.open(REF / scheme / ("%s@1x.png" % crop)).convert("RGB")
            x, y = origin(sheet, i)
            im.paste(c, (x + (sheet["cell_w"] - c.width) // 2, y + (sheet["cell_h"] - c.height) // 2))
        out = REF / "composite" / scheme / (name + ".png")
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out, optimize=True)
        print("wrote", out.relative_to(ROOT))


def diff(name):
    """Per cell: on pixels that are flat in the reference (its 3 x 3 neighbourhood within 2 levels) and outside the
    reference's ink box (the label or icon, grown by 3 px), the largest per-channel difference and how many pixels are
    off by more than 2 levels (the 3 px around the box count: a box too big or too small shows there). Rounded corners and ring edges are not flat, so they are left out too."""
    sheet = SHEETS[name]
    for scheme, folder in (("light", "linux"), ("dark", "linux-dark")):
        ref = Image.open(REF / "composite" / scheme / (name + ".png")).convert("RGB")
        ours = Image.open(LOOKS / folder / (name + ".png")).convert("RGB")
        rp, op = ref.load(), ours.load()
        total_flat = total_bad = total_edge = worst_edge = 0
        worst = 0
        print(scheme)
        for i, crop in enumerate(sheet["cells"]):
            if crop is None:
                continue
            x0, y0 = origin(sheet, i)
            cw, ch = sheet["cell_w"], sheet["cell_h"]
            # the control's box: the non-window part of the reference cell
            bg = WINDOW[scheme]
            xs, ys = [], []
            ink = []
            for y in range(y0, y0 + ch):
                for x in range(x0, x0 + cw):
                    if rp[x, y] != bg:
                        xs.append(x)
                        ys.append(y)
            if not xs:
                continue
            bx0, bx1, by0, by1 = min(xs), max(xs), min(ys), max(ys)
            face = rp[(bx0 + bx1) // 2, by0 + 3]
            for y in range(by0 + 4, by1 - 3):
                for x in range(bx0 + 4, bx1 - 3):
                    if sum(abs(rp[x, y][k] - face[k]) for k in range(3)) > 60:
                        ink.append((x, y))
            if ink:
                ix0 = min(p[0] for p in ink) - 3
                ix1 = max(p[0] for p in ink) + 3
                iy0 = min(p[1] for p in ink) - 3
                iy1 = max(p[1] for p in ink) + 3
            else:
                ix0 = ix1 = iy0 = iy1 = -10
            flat = bad = mx = edge_max = edge_bad = 0
            for y in range(by0 - 3, by1 + 4):
                for x in range(bx0 - 3, bx1 + 4):
                    if ix0 <= x <= ix1 and iy0 <= y <= iy1:
                        continue
                    p = rp[x, y]
                    d_all = max(abs(op[x, y][k] - p[k]) for k in range(3))
                    edge_max = max(edge_max, d_all)
                    edge_bad += d_all > 2
                    if any(max(abs(rp[x + dx, y + dy][k] - p[k]) for k in range(3)) > 2
                           for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                        continue
                    flat += 1
                    d = max(abs(op[x, y][k] - p[k]) for k in range(3))
                    mx = max(mx, d)
                    bad += d > 2
            total_flat += flat
            total_bad += bad
            total_edge += edge_bad
            worst_edge = max(worst_edge, edge_max)
            worst = max(worst, mx)
            print("  %-26s box %3dx%-3d flat px %5d  max %3d  over 2: %d   | all non-ink px: max %3d  over 2: %d" % (crop, bx1 - bx0 + 1, by1 - by0 + 1, flat, mx, bad, edge_max, edge_bad))
        print("  total flat px %d, over 2 levels: %d, worst %d | all non-ink px over 2 levels: %d, worst %d" % (total_flat, total_bad, worst, total_edge, worst_edge))


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--diff":
        for n in args[1:]:
            diff(n)
    else:
        for n in (args or SHEETS):
            compose(n)
