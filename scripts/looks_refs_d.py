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


STATES = os.path.join(ROOT, "docs/ui/looks/ref/windows/states")


def open_src(src):
    """A dialog capture, or (round 4) a state capture of docs/ui/looks/ref/windows/states."""
    path = os.path.join(DLG, src + "@1x.png")
    if not os.path.exists(path):
        path = os.path.join(STATES, src + "@1x.png")
    if not os.path.exists(path):
        path = os.path.join(ROOT, "docs/ui/looks/ref/windows", src + "@1x.png")
    return Image.open(path).convert("RGB")


def crop_of(cell):
    src, x, y, w, h = cell[:5]
    pad = pad_of(cell)
    im = open_src(src)
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

SHEETS["splitter_dialog"] = (1, 24, 387, [
    ("search-filter-top", 320, 55, 24, 387, 0),         # the Filter window splitter, 8 wide at x 12
])

# ---------------------------------------------------------------------------------------------
# Round 4 composite sheets: ONE cell of cw x ch holding several real crops at fixed offsets
# (a combo head and the list window under it, a tab strip with its page edge...). Each part is
# (capture, x, y, w, h, dx, dy): the capture rectangle pasted at (dx, dy) of the cell, no padding.
PARTS = {}


# combo head open (blue face, bleed row included) and the popup list window right under it
for _n, _head, _hx, _hy, _hw, _list, _lw, _lh in [
    ("combo_box_open_color", "combo-box-open-dialog-options-row-color", 321, 71, 389, "combo-box-open-list-options-row-color", 389, 41),
    ("combo_box_open_color2", "combo-box-open-dialog-options-row-color-row2", 321, 71, 389, "combo-box-open-list-options-row-color-row2", 389, 41),
    ("combo_box_open_size", "combo-box-open-dialog-options-font-size", 321, 159, 389, "combo-box-open-list-options-font-size", 389, 54),
    ("combo_box_open_size2", "combo-box-open-dialog-options-font-size-row2", 321, 159, 389, "combo-box-open-list-options-font-size-row2", 389, 54),
    ("combo_box_open_show", "combo-box-open-dialog-conditional-formatting-show", 149, 41, 143, "combo-box-open-list-conditional-formatting-show", 143, 106),
    ("combo_box_open_show2", "combo-box-open-dialog-conditional-formatting-show-row2", 149, 41, 143, "combo-box-open-list-conditional-formatting-show-row2", 143, 106),
]:
    _skip = "RB" if "row-color" in _list else ""
    PARTS[_n] = (_hw + 8, 4 + 21 + _lh + 4, [(_head, _hx, _hy, _hw + 1, 22, 4, 4), (_list, 0, 0, _lw, _lh, 4, 25, _skip)])
# states of the closed combo: drop button held, focused list-style
for _n, _src in [("combo_box_held", "combo-box-drop-button-pressed-options-row-color"), ("combo_box_focus", "combo-box-focused-options-row-color")]:
    PARTS[_n] = (389 + 8, 29, [(_src, 321, 71, 390, 22, 4, 4)])



# image combo (TcxImageComboBox) heads and their popup lists, 15 px rows
for _n, _head, _hx, _hy, _hw, _list, _lw, _lh, _with_head in [
    ("image_combo_box_open_auth", "combo-box-open-dialog-options-auth-type", 371, 71, 189, "combo-box-open-list-options-auth-type", 189, 32, True),
    ("image_combo_box_open_auth2", "combo-box-open-dialog-options-auth-type-row2", 371, 71, 189, "combo-box-open-list-options-auth-type-row2", 189, 32, True),
    ("image_combo_box_open_art", "combo-box-open-dialog-options-card-art-position", 406, 278, 151, "combo-box-open-list-options-card-art-position", 151, 47, True),
    ("image_combo_box_open_art2", "combo-box-open-dialog-options-card-art-position-row2", 406, 278, 151, "combo-box-open-list-options-card-art-position-row2", 151, 47, True),
    ("image_combo_box_open_condition", "combo-box-open-dialog-options-condition", 371, 99, 335, "combo-box-open-list-options-condition", 335, 227, True),
    ("image_combo_box_open_condition2", "combo-box-open-dialog-options-condition-row2", 371, 99, 335, "combo-box-open-list-options-condition-row2", 335, 227, True),
]:
    _parts = [(_list, 0, 0, _lw, _lh, 4, 25, "RB" if ("condition" in _list or "card-art" in _list) else "")]
    if _with_head:
        _parts.insert(0, (_head, _hx, _hy, _hw + 1, 22, 4, 4))
    PARTS[_n] = (_hw + 8, 4 + 21 + _lh + 4, _parts)


PARTS["list_box_focus"] = (164, 300, [("list-box-row-selected-focused-customization", 14, 57, 152, 154, 4, 117)])
PARTS["list_box_blur"] = (164, 300, [("list-box-row-selected-unfocused-customization", 14, 57, 152, 154, 4, 117)])


for _k in range(1, 12):
    PARTS["page_control_stats_%d" % _k] = (905, 24, [("tab-selected-statistics-%d" % _k, 8, 31, 905, 24, 0, 0)])
PARTS["page_control_cards"] = (318, 22, [("tab-selected-filter-cards", 8, 31, 229, 22, 0, 0)])
PARTS["page_control_options"] = (407, 22, [("tab-selected-filter-options", 8, 31, 229, 22, 0, 0)])
PARTS["page_control_held"] = (96, 22, [("tab-pressed-customization-columns", 12, 33, 96, 22, 0, 0)])


PARTS["combo_box_flat"] = (188, 28, [("main-window", 604, 56, 188, 28, 0, 0)])
PARTS["page_control_bottom"] = (282, 29, [("main-window", 8, 546, 282, 29, 0, 0)])
PARTS["page_control_bottom2"] = (192, 23, [("tab-selected-second-main-left", 8, 549, 192, 23, 0, 0)])
PARTS["splitter_live"] = (8, 463, [("main-window", 287, 109, 8, 463, 0, 0)])
PARTS["splitter_live_across"] = (497, 8, [("main-window", 295, 322, 497, 8, 0, 0)])
PARTS["splitter_live_held"] = (8, 463, [("splitter-pressed-main-vertical", 208, 109, 8, 463, 0, 0)])
PARTS["splitter_live_across_held"] = (574, 8, [("splitter-pressed-main-horizontal", 218, 322, 574, 8, 0, 0)])
PARTS["splitter_dialog_held"] = (24, 387, [("splitter-pressed-filter", 320, 55, 24, 387, 0, 0)])

# the popup windows on their own, exact captures
for _n, _src, _w, _h in [
    ("combo_box_list_color", "combo-box-open-list-options-row-color", 389, 41),
    ("combo_box_list_color2", "combo-box-open-list-options-row-color-row2", 389, 41),
    ("combo_box_list_size", "combo-box-open-list-options-font-size", 389, 54),
    ("combo_box_list_size2", "combo-box-open-list-options-font-size-row2", 389, 54),
    ("combo_box_list_show", "combo-box-open-list-conditional-formatting-show", 143, 106),
    ("combo_box_list_show2", "combo-box-open-list-conditional-formatting-show-row2", 143, 106),
    ("image_combo_box_list_auth", "combo-box-open-list-options-auth-type", 189, 32),
    ("image_combo_box_list_auth2", "combo-box-open-list-options-auth-type-row2", 189, 32),
    ("image_combo_box_list_art", "combo-box-open-list-options-card-art-position", 151, 47),
    ("image_combo_box_list_art2", "combo-box-open-list-options-card-art-position-row2", 151, 47),
    ("image_combo_box_list_condition", "combo-box-open-list-options-condition", 335, 227),
    ("image_combo_box_list_condition2", "combo-box-open-list-options-condition-row2", 335, 227),
    ("image_combo_box_list_sort", "image-combo-box-open-list-sort", 153, 56),
]:
    PARTS[_n] = (_w, _h, [(_src, 0, 0, _w, _h, 0, 0)])
PARTS["image_combo_box_cell"] = (155, 21, [("image-combo-box-cell-editor-sort", 175, 98, 155, 21, 0, 0)])
PARTS["image_combo_box_cell_held"] = (155, 21, [("image-combo-box-open-dialog-sort", 175, 98, 155, 21, 0, 0)])

# the open heads on their own: exact crops of the dialog captures (rectangle plus the bleed column and row)
for _n, _src, _x, _y, _w in [
    ("combo_box_open_color_head", "combo-box-open-dialog-options-row-color", 321, 71, 389),
    ("combo_box_open_color2_head", "combo-box-open-dialog-options-row-color-row2", 321, 71, 389),
    ("combo_box_open_size_head", "combo-box-open-dialog-options-font-size", 321, 159, 389),
    ("combo_box_open_size2_head", "combo-box-open-dialog-options-font-size-row2", 321, 159, 389),
    ("combo_box_open_show_head", "combo-box-open-dialog-conditional-formatting-show", 149, 41, 143),
    ("combo_box_open_show2_head", "combo-box-open-dialog-conditional-formatting-show-row2", 149, 41, 143),
    ("image_combo_box_open_auth_head", "combo-box-open-dialog-options-auth-type", 371, 71, 189),
    ("image_combo_box_open_auth2_head", "combo-box-open-dialog-options-auth-type-row2", 371, 71, 189),
    ("image_combo_box_open_art_head", "combo-box-open-dialog-options-card-art-position", 406, 278, 151),
    ("image_combo_box_open_art2_head", "combo-box-open-dialog-options-card-art-position-row2", 406, 278, 151),
    ("image_combo_box_open_condition_head", "combo-box-open-dialog-options-condition", 371, 99, 335),
    ("image_combo_box_open_condition2_head", "combo-box-open-dialog-options-condition-row2", 371, 99, 335),
]:
    PARTS[_n] = (_w + 1, 22, [(_src, _x, _y, _w + 1, 22, 0, 0)])
PARTS["combo_box_search_held"] = (297, 29, [("combo-box-drop-button-pressed-search", 20, 70, 289, 22, 4, 4)])


def parts_ref(name):
    cw, ch, parts = PARTS[name]
    out = Image.new("RGB", (cw, ch), FACE)
    for part in parts:
        src, x, y, w, h, dx, dy = part[:7]
        out.paste(open_src(src).crop((x, y, x + w, y + h)), (dx, dy))
    return out


def make_parts(name):
    cw, ch, _ = PARTS[name]
    w, h = sheet_size(1, cw, ch, 1)
    out = Image.new("RGB", (w, h), FACE)
    ox, oy = cell_origin(1, cw, ch, 0)
    out.paste(parts_ref(name), (ox, oy))
    path = os.path.join(ROOT, "docs/ui/looks/ref/windows", name + ".png")
    out.save(path)
    print("wrote", path, out.size)


def compare_parts(name, out_dir):
    cw, ch, parts = PARTS[name]
    ref = parts_ref(name)
    ours = Image.open(os.path.join(ROOT, "docs/ui/looks/windows", name + ".png")).convert("RGB")
    ox, oy = cell_origin(1, cw, ch, 0)
    got = ours.crop((ox, oy, ox + cw, oy + ch))
    diff = Image.new("RGB", ref.size)
    for part in parts:
        src, x, y, w, h, dx, dy = part[:7]
        skip = part[7] if len(part) > 7 else ""   # "R" right column, "B" bottom row: grab artefacts
        worst, over2, over16 = 0, 0, 0
        # the frame/border zone (2 px ring) apart from the interior
        ring_worst, ring_n = 0, 0
        for yy in range(dy, dy + h):
            for xx in range(dx, dx + w):
                a, b = ref.getpixel((xx, yy)), got.getpixel((xx, yy))
                d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                if ("R" in skip and xx == dx + w - 1) or ("B" in skip and yy == dy + h - 1):
                    d = 0
                worst = max(worst, d)
                over2 += d > 2
                over16 += d > 16
                if min(xx - dx, yy - dy, dx + w - 1 - xx, dy + h - 1 - yy) < 2:
                    ring_worst = max(ring_worst, d)
                    ring_n += d > 2
                diff.putpixel((xx, yy), (min(255, d * 4),) * 3)
        print("%s part %s @%d,%d %dx%d: max %d, >2: %d, >16: %d of %d; 2px ring max %d (>2: %d)" % (name, src, dx, dy, w, h, worst, over2, over16, w * h, ring_worst, ring_n))
    s = 3
    img = Image.new("RGB", (cw * s, ch * s * 3 + 8), (255, 0, 255))
    img.paste(ref.resize((cw * s, ch * s), Image.NEAREST), (0, 0))
    img.paste(got.resize((cw * s, ch * s), Image.NEAREST), (0, ch * s + 4))
    img.paste(diff.resize((cw * s, ch * s), Image.NEAREST), (0, ch * s * 2 + 8))
    img.save(os.path.join(out_dir, name + "_parts.png"))


if __name__ == "__main__":
    command, name = sys.argv[1], sys.argv[2]
    if command == "refp":
        make_parts(name)
        sys.exit(0)
    if command == "cmpp":
        compare_parts(name, sys.argv[3] if len(sys.argv) > 3 else os.environ.get("TEMP", "."))
        sys.exit(0)
    if command == "ref":
        make_ref(name)
    else:
        compare(name, sys.argv[3] if len(sys.argv) > 3 else os.environ.get("TEMP", "."))
