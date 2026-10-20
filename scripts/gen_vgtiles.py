"""Replaces the 160 px wide row pictures of the Computed rows (Windows light) by small tiles: `python -I scripts/gen_vgtiles.py`.

Run once on examples/looks/vertical_grid.e while vg_colors_c, vg_strip_c and vg_legality_c are still in it; they are cut from the 1:1 capture
(v3 artwork). What is not artwork is drawn by the sheet (the strip's gradient, the tag boxes' fills); what stays baked is the four colour
discs (18 x 18), the strip's marker (9 x 10) and the five tag letters (about 13 x 13 each).
"""
import os
import re

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "examples", "looks", "vertical_grid.e")
s = open(PATH, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"


def get(name, w, h):
    m = re.search(r"fn %s\(\) -> str \{ ret \"([0-9A-Fa-f]*)\" \}" % name, s)
    d = m.group(1)
    return [[d[(y * w + x) * 6:(y * w + x) * 6 + 6] for x in range(w)] for y in range(h)]


def tile(rows, x0, x1, y0, y1):
    return "".join(rows[y][x] for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)), x1 - x0 + 1, y1 - y0 + 1


colors = get("vg_colors_c", 160, 18)
strip = get("vg_strip_c", 160, 11)
legal = get("vg_legality_c", 160, 17)
out = []
for i, (a, b) in enumerate(((43, 60), (62, 79), (81, 98), (100, 117))):
    d, w, h = tile(colors, a, b, 0, 17)
    out.append('fn vg_disc_c%d() -> str { ret "%s" }' % (i, d))
d, w, h = tile(strip, 0, 8, 1, 10)
out.append('fn vg_marker_c() -> str { ret "%s" }' % d)
for i, (a, b, c, e) in enumerate(((44, 55, 2, 15), (58, 70, 2, 14), (75, 84, 2, 14), (90, 99, 2, 14), (104, 114, 2, 14))):
    d, w, h = tile(legal, a, b, c, e)
    out.append('fn vg_letter_c%d() -> str { ret "%s" }' % (i, d))
for name in ("vg_colors_c", "vg_strip_c", "vg_legality_c"):
    s = re.sub(r"fn %s\(\) -> str \{ ret \"[0-9A-Fa-f]*\" \}%s" % (name, nl), "", s)
s = s.rstrip() + nl + nl + "// round 46: the 1:1 capture's tiles of the Computed rows (see scripts/gen_vgtiles.py)" + nl + nl.join(out) + nl
open(PATH, "w", encoding="utf-8", newline="").write(s)
