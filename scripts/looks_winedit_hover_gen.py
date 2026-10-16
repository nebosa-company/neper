"""Generates the HOVER block at the end of lib/e/ui/winedit.e from the live v3 hover grabs (round 6).

`python -I scripts/looks_winedit_hover_gen.py` rewrites the block between the `GENERATED hover` markers.

What docs/ui/looks/ref/windows/states/hover-*@1x.png show against the rest grab of the same dialog (a pixel diff):
- Any hover over an edit (the text, a spin arrow, the ellipsis) darkens its rim ring by 2 levels (1 to 3): rows 1, 2, 19
  and 20 across and two columns at each side. The white face and the text do not change (no #F9F9F9 face).
- The bottom right corner (3 columns x 4 rows) is re-drawn: kept as the captured pixels per kind.
- The button under the pointer is re-drawn blue (ellipsis, spin up / down / left / right arrow of the fast spin). The
  stacked arrows of the Morph spin edit (kind 2) draw NO hover look of their own: only the rim and the corner change.
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") + os.sep
R = ROOT + "docs/ui/looks/ref/windows/states/"
OUT = ROOT + "lib/e/ui/winedit.e"
BEGIN = "// ---- GENERATED hover by scripts/looks_winedit_hover_gen.py (do not edit) ----\n"
END = "// ---- END GENERATED hover ----\n"


def load(n):
    return np.array(Image.open(R + n + "@1x.png").convert("RGB")).astype(int)


# kind: (hover capture over the edit, x, y, DFM width)
CORNER = {0: ("hover-edit-options-old-password", 215, 89, 495),
          1: ("hover-spin-edit-options-max-same-cards", 215, 159, 121),
          2: ("hover-spin-edit-options-morph-speed", 406, 105, 67),
          3: ("hover-edit-options-deck-path", 215, 94, 495)}
# zone: (hover capture, x, y, DFM width, bbox of the button in the capture (x0, y0, x1, y1))
ZONES = {1: ("hover-spin-edit-arrow-up-options-max-same-cards", 215, 159, 121, (304, 161, 319, 169)),
         2: ("hover-spin-edit-arrow-down-options-max-same-cards", 215, 159, 121, (304, 170, 319, 178)),
         3: ("hover-spin-edit-arrow-left-options-max-same-cards", 215, 159, 121, (289, 161, 303, 178)),
         4: ("hover-spin-edit-arrow-right-options-max-same-cards", 215, 159, 121, (320, 161, 336, 180)),
         5: ("hover-edit-button-ellipsis-options-deck-path", 215, 94, 495, (693, 96, 710, 114)),
         # the same button 291 px lower in the Card Art page: the rows that touch the foot drift with the control's y
         6: ("hover-edit-button-ellipsis-options-cardart", 215, 385, 464, (662, 387, 679, 406))}


def word(p):
    return "0xFF%02X%02X%02Xu32" % (p[0], p[1], p[2])


def array(name, cells):
    body = ", ".join(word(p) for p in cells)
    return "fn %s() -> [%d]u32 { ret [%d]u32{ %s } }\n" % (name, len(cells), len(cells), body)


def main():
    out = [BEGIN, "// Bottom right corner (3 columns x 4 rows, rows 18..21) of a hovered edit, per kind.\n"]
    for kind, (cap, x, y, w) in sorted(CORNER.items()):
        a = load(cap)
        w1 = w + 1
        cells = [a[y + r, x + w1 - 3 + c] for r in range(18, 22) for c in range(3)]
        out.append(array("whover_corner_%d" % kind, cells))
    out.append("// The hovered button as captured: zone 1 up, 2 down, 3 left, 4 right (kind 1), 5 ellipsis (kind 3, y 94), 6 the same at y 385. Box: x from the\n// frame's width, y from its top, width, height; then the pixels row by row.\n")
    for zone, (cap, x, y, w, box) in sorted(ZONES.items()):
        a = load(cap)
        w1 = w + 1
        x0, y0, x1, y1 = box
        cells = [a[yy, xx] for yy in range(y0, y1 + 1) for xx in range(x0, x1 + 1)]
        out.append("fn whover_box_%d() -> [4]i32 { ret [4]i32{ %d, %d, %d, %d } }\n" % (zone, (x0 - x) - w1, y0 - y, x1 - x0 + 1, y1 - y0 + 1))
        out.append(array("whover_button_%d" % zone, cells))
    out.append(END)
    text = open(OUT, encoding="utf-8").read()
    if BEGIN in text:
        head = text[:text.index(BEGIN)]
        tail = text[text.index(END) + len(END):]
    else:
        head, tail = text, ""
    open(OUT, "w", encoding="utf-8", newline="\n").write(head + "".join(out) + tail)


main()
