"""Linux look comparer of worker l3 (round 20): toolbar_button, menu_bar, popup_menu, status_bar, hint, scroll_bar,
progress_bar, splitter, page_control.

  python -I scripts/linux_cmp_l3.py compose [sheet ...]    reference crops -> docs/ui/looks/ref/linux/composite/{light,dark}/<sheet>.png
  python -I scripts/linux_cmp_l3.py diff [sheet ...]       strict comparison of docs/ui/looks/linux[-dark]/<sheet>.png with the crops
  python -I scripts/linux_cmp_l3.py diff -v <sheet>        also print every cell with its counts
  python -I scripts/linux_cmp_l3.py offs <sheet> <crop> [dark]   list the off pixels of one cell
  python -I scripts/linux_cmp_l3.py heat <sheet> <crop>    write <tmp>/heat-<sheet>-<scheme>-<crop>.png (ref | ours | off pixels, 4x)

Layout mirrors looks.e (margin 12, spacing 10, caption 16 + 4 above each cell). A cell is a box of cell_w x cell_h with
the crop (or our control, placed by the sheet app at the same whole-pixel offset) centred in it: x = (cell_w - w) // 2.
The strict metric: a reference pixel is flat when its 3 x 3 neighbourhood is within 2 levels; it is off when ours
differs from it by more than 2 levels in any channel. Pixels within 2 px of an `ink` rect (text and icon glyphs, which
Cantarell and the icon theme antialias differently) are left out; nothing else is: borders, fills, shadows and focus rings
count. `edge` counts every pixel outside the ink rects (antialiased corners included), for information.
"""
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = ROOT / "docs/ui/looks"
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
FOLDER = {"light": "linux", "dark": "linux-dark"}
MARGIN, SPACING, CAPTION = 12, 10, 16 + 4

# name -> columns, cell_w, cell_h, cells: [(crop, [ink rects in crop px (x0, y0, x1, y1) inclusive])]
SHEETS = {}


def sheet(name, columns, cell_w, cell_h, cells):
    SHEETS[name] = {"columns": columns, "cell_w": cell_w, "cell_h": cell_h,
                    "cells": [c if isinstance(c, tuple) else (c, []) for c in cells]}


# ---- sheets (kept in step with examples/looks/linux_<name>.e) ----
sheet("progress_bar", 3, 210, 44, [
    "progress-0", "progress-40", "progress-100", "progress-osd", "levelbar",
    ("spinner", [(0, 0, 31, 31)]),
])

sheet("splitter", 2, 210, 90, [
    "separator-h", "separator-v",
    ("paned", [(36, 30, 64, 54), (133, 30, 170, 54)]),
    ("paned-wide", [(36, 30, 64, 54), (133, 30, 170, 54)]),
])

sheet("scroll_bar", 2, 210, 170, [
    "scrollbar-h-normal", "scrollbar-v-normal", "scrollbar-h-hover", "scrollbar-v-hover",
    "scrollbar-h-disabled", "scrollbar-v-disabled", "scrolled-overlay", "scrolled-classic",
])

sheet("hint", 1, 210, 90, [("tooltip-real", [(10, 8, 84, 26)])])


def origin(sh, i):
    col, row = i % sh["columns"], i // sh["columns"]
    return (MARGIN + col * (sh["cell_w"] + SPACING), MARGIN + row * (CAPTION + sh["cell_h"] + SPACING) + CAPTION)


def size(sh):
    n = len(sh["cells"])
    rows = (n + sh["columns"] - 1) // sh["columns"]
    return (MARGIN * 2 + sh["columns"] * sh["cell_w"] + (sh["columns"] - 1) * SPACING,
            MARGIN * 2 + rows * (CAPTION + sh["cell_h"]) + (rows - 1) * SPACING)


def crop_image(scheme, crop):
    return Image.open(REF / scheme / ("%s@1x.png" % crop)).convert("RGBA")


def crop_at(sh, i, c):
    x, y = origin(sh, i)
    return x + (sh["cell_w"] - c.width) // 2, y + (sh["cell_h"] - c.height) // 2


def compose(name):
    sh = SHEETS[name]
    for scheme in ("light", "dark"):
        im = Image.new("RGBA", size(sh), WINDOW[scheme] + (255,))
        for i, (crop, _) in enumerate(sh["cells"]):
            if crop is None:
                continue
            c = crop_image(scheme, crop)
            im.alpha_composite(c, crop_at(sh, i, c))
        out = REF / "composite" / scheme / (name + ".png")
        out.parent.mkdir(parents=True, exist_ok=True)
        im.convert("RGB").save(out, optimize=True)
        print("wrote", out.relative_to(ROOT))


def measure(name, scheme, verbose, only=None):
    sh = SHEETS[name]
    ref = Image.open(REF / "composite" / scheme / (name + ".png")).convert("RGB")
    ours = Image.open(LOOKS / FOLDER[scheme] / (name + ".png")).convert("RGB")
    rp, op = ref.load(), ours.load()
    tot = {"flat": 0, "bad": 0, "edge": 0, "edge_bad": 0}
    worst_cell = ("", 0)
    rows = []
    for i, (crop, inks) in enumerate(sh["cells"]):
        if crop is None or (only and crop != only):
            continue
        c = crop_image(scheme, crop)
        x0, y0 = crop_at(sh, i, c)
        w, h = c.size
        masked = set()
        for (a, b, cc, d) in inks:
            for y in range(b - 2, d + 3):
                for x in range(a - 2, cc + 3):
                    masked.add((x, y))
        flat = bad = edge = edge_bad = mx = 0
        for y in range(-3, h + 3):
            for x in range(-3, w + 3):
                if (x, y) in masked:
                    continue
                px, py = x0 + x, y0 + y
                p = rp[px, py]
                d = max(abs(op[px, py][k] - p[k]) for k in range(3))
                edge += 1
                edge_bad += d > 2
                if any(max(abs(rp[px + dx, py + dy][k] - p[k]) for k in range(3)) > 2
                       for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                    continue
                flat += 1
                mx = max(mx, d)
                bad += d > 2
        tot["flat"] += flat
        tot["bad"] += bad
        tot["edge"] += edge
        tot["edge_bad"] += edge_bad
        if bad >= worst_cell[1]:
            worst_cell = (crop, bad)
        rows.append("  %-28s %3dx%-3d flat %5d  off %5d (max %3d) | all %5d off %5d" % (crop, w, h, flat, bad, mx, edge, edge_bad))
    if verbose or only:
        print("\n".join(rows))
    print("%s %-5s %-13s flat %6d  off %5d | all-px off %5d | worst %s %d" % (
        name, scheme, "", tot["flat"], tot["bad"], tot["edge_bad"], worst_cell[0], worst_cell[1]))


def heat(name, crop):
    sh = SHEETS[name]
    for scheme in ("light", "dark"):
        idx = [c for c, _ in sh["cells"]].index(crop)
        c = crop_image(scheme, crop)
        x0, y0 = crop_at(sh, idx, c)
        ours = Image.open(LOOKS / FOLDER[scheme] / (name + ".png")).convert("RGB")
        w, h = c.size
        box = (x0 - 3, y0 - 3, x0 + w + 3, y0 + h + 3)
        ref = Image.open(REF / "composite" / scheme / (name + ".png")).convert("RGB")
        a, b = ref.crop(box), ours.crop(box)
        d = Image.new("RGB", a.size)
        ap, bp, dp = a.load(), b.load(), d.load()
        for y in range(a.height):
            for x in range(a.width):
                m = max(abs(ap[x, y][k] - bp[x, y][k]) for k in range(3))
                dp[x, y] = (0, 0, 0) if m <= 2 else (255, min(255, 80 + m * 3), 0)
        k = 4 if a.width < 300 else 2
        out = Image.new("RGB", (a.width * k * 3 + 20, a.height * k), (200, 0, 200))
        for j, im in enumerate((a, b, d)):
            out.paste(im.resize((a.width * k, a.height * k), Image.NEAREST), (j * (a.width * k + 10), 0))
        path = Path(tempfile.gettempdir()) / ("heat-%s-%s-%s.png" % (name, scheme, crop))
        out.save(path)
        print("wrote", path)


def offs(name, crop, scheme="light"):
    """List the pixels of one cell that are off by more than 2 levels: crop x, y, reference, ours."""
    sh = SHEETS[name]
    idx = [c for c, _ in sh["cells"]].index(crop)
    c = crop_image(scheme, crop)
    x0, y0 = crop_at(sh, idx, c)
    ref = Image.open(REF / "composite" / scheme / (name + ".png")).convert("RGB")
    ours = Image.open(LOOKS / FOLDER[scheme] / (name + ".png")).convert("RGB")
    for y in range(-3, c.height + 3):
        for x in range(-3, c.width + 3):
            p, q = ref.getpixel((x0 + x, y0 + y)), ours.getpixel((x0 + x, y0 + y))
            if max(abs(p[k] - q[k]) for k in range(3)) > 2:
                print("%3d,%3d ref %02x%02x%02x ours %02x%02x%02x" % ((x, y) + p + q))


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args.pop(0)
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    if cmd == "offs":
        offs(*args)
    elif cmd == "heat":
        heat(args[0], args[1])
    else:
        for n in (args or list(SHEETS)):
            if cmd == "compose":
                compose(n)
            else:
                for scheme in ("light", "dark"):
                    measure(n, scheme, verbose)
