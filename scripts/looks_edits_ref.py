"""Builds docs/ui/looks/ref/windows/edits_dialog.png and diffs our render against it.

The composite pastes the real edits of the v3 dialog captures (docs/ui/looks/ref/windows/dialogs)
into the layout of examples/looks/edits_dialog.e: one column of 520 x 30 cells, each control at
(8, 4) in its cell. `python -I scripts/looks_edits_ref.py` writes the composite; with a second
argument (a scale, 1 or 1.5) it also prints the per-cell error of docs/ui/looks/windows/edits_dialog.png
and writes docs/ui/looks/windows/edits_dialog-diff.png (reference, ours, 4x |difference|).
"""
import sys
from PIL import Image

import os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks") + os.sep
DIALOGS = ROOT + "ref/windows/dialogs/"
# (caption, dialog, x, y, w, h): the control's window rectangle in the dialog capture.
CELLS = [
    ("mask 89", "options-04-passwords", 215, 89, 495, 21),
    ("mask 144", "options-04-passwords", 215, 144, 495, 21),
    ("mask 198", "options-04-passwords", 215, 198, 495, 21),
    ("spin fast", "options-02-decks", 215, 159, 121, 21),
    ("spin 650", "options-11-morph", 406, 105, 67, 21),
    ("spin 500", "options-11-morph", 406, 169, 67, 21),
    ("button edit decks", "options-02-decks", 215, 94, 495, 21),
    ("button edit card art", "options-10-card-art", 215, 385, 464, 21),
]
CELL_W, CELL_H, MARGIN, SPACING, CAPTION = 520, 30, 12, 10, 20
BG = (240, 240, 240)


def origin(i):
    return MARGIN, MARGIN + i * (CAPTION + CELL_H + SPACING) + CAPTION


def size():
    return MARGIN * 2 + CELL_W, MARGIN * 2 + len(CELLS) * (CAPTION + CELL_H) + (len(CELLS) - 1) * SPACING


def build():
    w, h = size()
    out = Image.new("RGB", (w, h), BG)
    for i, (name, dialog, x, y, cw, ch) in enumerate(CELLS):
        shot = Image.open(DIALOGS + dialog + "@1x.png").convert("RGB")
        # the control's 22 visible rows and 2 px of the face round it
        box = (x - 2, y - 2, x + cw + 2, y + 24)
        ox, oy = origin(i)
        out.paste(shot.crop(box), (ox + 8 - 2, oy + 4 - 2))
    out.save(ROOT + "ref/windows/edits_dialog.png")
    return out


def diff(scale):
    ref = build()
    suffix = "" if scale == 1 else "@1.5x"
    ours = Image.open(ROOT + "windows/edits_dialog" + suffix + ".png").convert("RGB")
    if scale != 1:
        ref = ref.resize((round(ref.width * scale), round(ref.height * scale)), Image.NEAREST)
    strips = []
    for i, (name, dialog, x, y, cw, ch) in enumerate(CELLS):
        ox, oy = origin(i)
        box = tuple(round(v * scale) for v in (ox + 6, oy + 2, ox + 8 + cw + 2, oy + 28))
        a = ref.crop(box)
        b = ours.crop(box)
        worst = 0
        total = 0
        count = 0
        for yy in range(a.height):
            for xx in range(a.width):
                pa = a.getpixel((xx, yy))
                pb = b.getpixel((xx, yy))
                d = max(abs(pa[k] - pb[k]) for k in range(3))
                worst = max(worst, d)
                total += d
                count += 1
        # the frame and buttons alone: leave out the text area (ClearType ink cannot be matched)
        text_end = cw - (48 if cw > 100 and "spin" in name else 18 if "spin" in name else 18 if "button" in name else 0)
        frame = 0
        for yy in range(a.height):
            for xx in range(a.width):
                lx = xx / scale - 2
                ly = yy / scale - 2
                if "mask" in name or (3 <= ly <= 17 and 3 <= lx <= text_end):
                    if 3 <= ly <= 17 and 3 <= lx <= text_end:
                        continue
                pa = a.getpixel((xx, yy))
                pb = b.getpixel((xx, yy))
                frame = max(frame, max(abs(pa[k] - pb[k]) for k in range(3)))
        print("%-22s max error %3d (frame and buttons only %3d), mean %.2f" % (name, worst, frame, total / count))
        d = Image.new("RGB", a.size)
        for yy in range(a.height):
            for xx in range(a.width):
                pa = a.getpixel((xx, yy))
                pb = b.getpixel((xx, yy))
                d.putpixel((xx, yy), tuple(min(255, abs(pa[k] - pb[k]) * 4) for k in range(3)))
        strips.append((a, b, d))
    zoom = 4 if scale == 1 else 3
    width = max(s[0].width for s in strips) * zoom
    height = sum(3 * (s[0].height * zoom + 4) + 8 for s in strips)
    sheet = Image.new("RGB", (width, height), (255, 0, 255))
    top = 0
    for a, b, d in strips:
        for img in (a, b, d):
            sheet.paste(img.resize((img.width * zoom, img.height * zoom), Image.NEAREST), (0, top))
            top += img.height * zoom + 4
        top += 8
    sheet.save(ROOT + "windows/edits_dialog-diff.png")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        diff(float(sys.argv[1]))
    else:
        build()
