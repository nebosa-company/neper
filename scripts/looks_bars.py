"""Scroll bar reference composites and whole pixel comparison (round 13): `python -I scripts/looks_bars.py [sheet ...] [--build]`.

Each CASES entry is one sheet of examples/looks/scroll_bar.e (cells of cw x ch px in `columns` columns, laid out by lib/e/ui/looks.e:
margin 12, spacing 10, caption 16 + 4) and, per cell, the capture it is compared with: (name, capture file under ref/windows or
ref/windows-native, crop x y w h). `--build` writes ref/windows/<sheet>.png: the crops pasted at the cells of a sheet of the size
of ours, on the sheet's own background. Every pixel of a cell is compared (no mask, no structural filter): a pixel is off when ours
differs by more than 2 levels in a channel. `EXCLUDE` lists rectangles (cell relative) painted out of both: only v3 artwork.
"""
import os
import sys
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks") + os.sep
M, SP, CAP = 12, 10, 20

MAIN = "states/%s@1x.png"
CASES = {
    "scroll_bar_main": dict(columns=7, cw=16, ch=186, cells=[
        ("rest", "main-window@1x.png", (775, 111, 16, 186)),
        ("hover thumb", MAIN % "hover-scroll-bar-vertical-thumb", (775, 111, 16, 186)),
        ("hover upper arrow", MAIN % "hover-scroll-bar-vertical-arrow-up", (775, 111, 16, 186)),
        ("hover lower arrow", MAIN % "hover-scroll-bar-vertical-arrow-down", (775, 111, 16, 186)),
        ("hover track", MAIN % "hover-scroll-bar-vertical-track", (775, 111, 16, 186)),
        ("pressed thumb", MAIN % "scroll-bar-thumb-pressed-main-vertical", (775, 111, 16, 186)),
        ("pressed lower arrow", MAIN % "scroll-bar-arrow-pressed-main-vertical", (775, 111, 16, 186)),
    ]),
    "scroll_bar_main_h": dict(columns=1, cw=196, ch=16, cells=[
        ("rest", MAIN % "hover-scroll-bar-vertical-thumb", (441, 303, 196, 16)),
        ("hover thumb", MAIN % "hover-scroll-bar-horizontal-thumb", (441, 303, 196, 16)),
        ("pressed thumb", MAIN % "scroll-bar-thumb-pressed-main-horizontal", (441, 303, 196, 16)),
    ]),
}
EXCLUDE = {}


def origin(c, i):
    col, row = i % c["columns"], i // c["columns"]
    return (M + col * (c["cw"] + SP), M + row * (16 + 4 + c["ch"] + SP) + CAP)


def load(path):
    for base in ("ref/windows/", "ref/windows-native/light/", ""):
        p = ROOT + base + path
        if os.path.exists(p):
            return np.array(Image.open(p).convert("RGB"))
    raise SystemExit("missing " + path)


def run(sheet, build, look="windows"):
    c = CASES[sheet]
    ours = np.array(Image.open(ROOT + "%s/%s.png" % (look, sheet)).convert("RGB"))
    comp = np.full(ours.shape, ours[0, 0], np.uint8)
    total = 0
    rows = []
    for i, (name, path, (x, y, w, h)) in enumerate(c["cells"]):
        ox, oy = origin(c, i)
        crop = load(path)[y:y + h, x:x + w]
        comp[oy:oy + h, ox:ox + w] = crop
        mine = ours[oy:oy + h, ox:ox + w]
        d = np.abs(crop.astype(int) - mine.astype(int)).max(axis=2)
        off = d > 2
        for (ex0, ey0, ex1, ey1) in EXCLUDE.get((sheet, name), []):
            off[ey0:ey1, ex0:ex1] = False
        ys, xs = np.where(off)
        where = "" if not len(ys) else " rows %d-%d cols %d-%d max %d" % (ys.min(), ys.max(), xs.min(), xs.max(), d[off].max())
        rows.append("  %-22s %4d px off%s" % (name, int(off.sum()), where))
        total += int(off.sum())
    if build:
        Image.fromarray(comp).save(ROOT + "ref/windows/%s.png" % sheet)
    print("%s [%s]: %d px off over %d cells" % (sheet, look, total, len(c["cells"])))
    print("\n".join(rows))
    return total


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")] or list(CASES)
    look = "windows-dark" if "--dark" in sys.argv else "windows"
    for s in args:
        run(s, "--build" in sys.argv, look)
