"""Reference crops and pixel diffs for the Windows looks of group d (combo box, image combo
box, list box, page control, splitter, hint), from the live v3 dialog captures.

  python -I scripts/looks_refs_d.py ref <sheet>      write docs/ui/looks/ref/windows/<sheet>.png
  python -I scripts/looks_refs_d.py cmp <sheet> [scale]
                                                     compare docs/ui/looks/windows/<sheet>.png
                                                     with the crops; print per-cell errors and
                                                     write <out>/<sheet>_<n>.png (ref over ours
                                                     over 4x diff), <out> = argv[3] or the temp dir

A sheet is a grid of cells exactly as lib/e/ui/looks.e lays them out (margin 12, gap 10, a 20 px
caption row above every cell). A cell shows the capture's rectangle plus PAD px of the
dialog around it, pasted at the cell's top-left; the Neper app places its control at (PAD, PAD)
in the same cell, so the two images can be compared pixel for pixel at 100 %.
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DLG = os.path.join(ROOT, "docs/ui/looks/ref/windows/dialogs")
PAD = 4
FACE = (240, 240, 240)
MARGIN, GAP, CAPTION = 12, 10, 20

# name -> (columns, cell_w, cell_h, [(capture, x, y, w, h), ...])
SHEETS = {}


def cell_origin(columns, cw, ch, i):
    col, row = i % columns, i // columns
    return MARGIN + col * (cw + GAP), MARGIN + row * (CAPTION + ch + GAP) + CAPTION


def sheet_size(columns, cw, ch, n):
    rows = (n + columns - 1) // columns
    return (MARGIN * 2 + columns * cw + (columns - 1) * GAP,
            MARGIN * 2 + rows * (CAPTION + ch) + (rows - 1) * GAP)


def pad_of(cell):
    return cell[5] if len(cell) > 5 else PAD


def shift_of(cell):
    """Where the crop's top-left sits inside its cell (default the cell's corner)."""
    return (cell[6], cell[7]) if len(cell) > 7 else (0, 0)


def crop_of(cell):
    src, x, y, w, h = cell[:5]
    pad = pad_of(cell)
    im = Image.open(os.path.join(DLG, src + "@1x.png")).convert("RGB")
    return im.crop((x - pad, y - pad, x + w + pad, y + h + pad))


def make_ref(name):
    columns, cw, ch, cells = SHEETS[name]
    w, h = sheet_size(columns, cw, ch, len(cells))
    out = Image.new("RGB", (w, h), FACE)
    for i, cell in enumerate(cells):
        if cell is None:
            continue
        ox, oy = cell_origin(columns, cw, ch, i)
        sx, sy = shift_of(cell)
        out.paste(crop_of(cell), (ox + sx, oy + sy))
    path = os.path.join(ROOT, "docs/ui/looks/ref/windows", name + ".png")
    out.save(path)
    print("wrote", path, out.size)


def compare(name, out_dir):
    columns, cw, ch, cells = SHEETS[name]
    ours = Image.open(os.path.join(ROOT, "docs/ui/looks/windows", name + ".png")).convert("RGB")
    for i, cell in enumerate(cells):
        if cell is None:
            continue
        ox, oy = cell_origin(columns, cw, ch, i)
        sx, sy = shift_of(cell)
        ox, oy = ox + sx, oy + sy
        ref = crop_of(cell)
        got = ours.crop((ox, oy, ox + ref.width, oy + ref.height))
        worst, over2, over16, total = 0, 0, 0, 0
        diff = Image.new("RGB", ref.size)
        for yy in range(ref.height):
            for xx in range(ref.width):
                a, b = ref.getpixel((xx, yy)), got.getpixel((xx, yy))
                d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                worst = max(worst, d)
                over2 += d > 2
                over16 += d > 16
                total += 1
                diff.putpixel((xx, yy), (min(255, d * 4),) * 3)
        print("%s cell %d %s: max %d, >2: %d, >16: %d of %d" % (name, i, cell[0], worst, over2, over16, total))
        zones = {}
        w, h = cell[3:5]
        pad = pad_of(cell)
        for yy in range(ref.height):
            for xx in range(ref.width):
                rx, ry = xx - pad, yy - pad
                edge = min(rx, ry, w - rx, h - ry)
                zone = "ring" if edge <= 2 else ("button" if rx >= w - 17 else "inside")
                a, b = ref.getpixel((xx, yy)), got.getpixel((xx, yy))
                d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                m, n = zones.get(zone, (0, 0))
                zones[zone] = (max(m, d), n + (d > 2))
        print("   zones (max, count>2): " + ", ".join("%s %s" % (k, zones[k]) for k in sorted(zones)))
        s = 4
        sheet = Image.new("RGB", (ref.width * s, ref.height * s * 3 + 8), (255, 0, 255))
        sheet.paste(ref.resize((ref.width * s, ref.height * s), Image.NEAREST), (0, 0))
        sheet.paste(got.resize((ref.width * s, ref.height * s), Image.NEAREST), (0, ref.height * s + 4))
        sheet.paste(diff.resize((ref.width * s, ref.height * s), Image.NEAREST), (0, ref.height * s * 2 + 8))
        sheet.save(os.path.join(out_dir, "%s_%d.png" % (name, i)))


# ---------------------------------------------------------------------------------------------
# The sheets. Rectangles are the controls.json rectangles (window-relative, 100 %).
SHEETS["combo_box_dialog"] = (2, 397, 29, [
    ("options-08-grids", 321, 71, 389, 21),            # Row Color, rest
    ("options-08-grids", 321, 159, 389, 21),           # Font Size, rest
])
SHEETS["combo_box_edit"] = (1, 297, 29, [
    ("search-search", 20, 70, 289, 21),                # Card, focused editable (accent underline)
])
SHEETS["combo_box_pick"] = (1, 151, 29, [
    ("view-conditional-formatting", 149, 41, 143, 21),  # Show formatting rules for, focused list
])

SHEETS["image_combo_box_dialog"] = (1, 343, 29, [
    ("options-09-defaults", 371, 99, 335, 21),         # Condition
    ("options-05-internet-authentication", 371, 71, 189, 21),  # Authentication
    ("options-11-morph", 406, 278, 151, 21),           # Stretch
])

SHEETS["list_box_dialog"] = (1, 152, 287, [
    # Customization > Columns: the 8 row list, first row chosen and focused (control at (0, 133)
    # of its cell so that the harness's pointer, at the cell centre, lands on the first row)
    ("view-show-columns", 14, 57, 152, 154, 0, 0, 133),
])

SHEETS["page_control_filter"] = (1, 229, 22, [
    ("search-filter-top", 8, 31, 229, 22, 0),           # Blocks / Formats / Editions, Cards, Options
])
SHEETS["page_control_custom"] = (1, 96, 22, [
    ("view-show-columns", 12, 33, 96, 22, 0),           # Bands, Columns (chosen)
])

SHEETS["page_control_stats"] = (1, 126, 24, [
    ("deck-statistics", 8, 31, 126, 24, 0),             # Colors (chosen, focused), Rarity
])
SHEETS["page_control_about"] = (1, 120, 24, [
    ("help-about", 8, 31, 120, 24, 0),                  # MTG Studio (chosen), Details
])

if __name__ == "__main__":
    command, name = sys.argv[1], sys.argv[2]
    if command == "ref":
        make_ref(name)
    else:
        compare(name, sys.argv[3] if len(sys.argv) > 3 else os.environ.get("TEMP", "."))
