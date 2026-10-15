"""Reference composites and pixel diffs for the Windows looks of group b of round 4 (check box, radio
button, radio group, group box, check list box) from the live v3 captures, state grabs included.

  python -I scripts/looks_refs_b.py ref <sheet>      write docs/ui/looks/ref/windows/<sheet>.png
  python -I scripts/looks_refs_b.py cmp <sheet> [out_dir]
                                                     compare docs/ui/looks/windows/<sheet>.png with the crops;
                                                     print per-cell errors on flat (non anti-aliased) pixels and
                                                     write <out_dir>/<sheet>_<n>.png (ref over ours over 4x diff)

A sheet is a grid of cells exactly as lib/e/ui/looks.e lays them out (margin 12, gap 10, a 20 px caption
row above every cell). A cell is (capture, x, y, w, h[, pad[, shift_x, shift_y]]): `capture` is a path under
docs/ui/looks/ref/windows (a dialog grab or a state grab), the rectangle the control's own, `pad` px of the
dialog around it are pasted at the cell's top-left (the Neper app places the control at (pad, pad)).
'Flat' pixels are those on a straight run of 8 or more equal pixels (within 1 level) in the reference: borders,
frame lines and fills; text, soft edges and ink are anti-aliased and reported separately.
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs/ui/looks/ref/windows")
PAD = 4
FACE = (240, 240, 240)
MARGIN, GAP, CAPTION = 12, 10, 20

SHEETS = {}
# Sheets whose reference composite was built earlier: name -> (columns, cell_w, cell_h, [(w, h), ...]) of the
# area of each cell that holds the control (compared against docs/ui/looks/ref/windows/<name>.png as it is).
EXISTING = {}


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
    return (cell[6], cell[7]) if len(cell) > 7 else (0, 0)


def crop_of(cell):
    src, x, y, w, h = cell[:5]
    pad = pad_of(cell)
    im = Image.open(os.path.join(REF, src)).convert("RGB")
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
    path = os.path.join(REF, name + ".png")
    out.save(path)
    print("wrote", path, out.size)


def flat_mask(ref):
    """Structural pixels: those on a straight run of 8 or more pixels (a row or a column) that stay
    within 1 level of one another: borders, frame lines and fills (text, soft edges and ink are not)."""
    w, h = ref.size
    px = ref.load()
    mask = [[False] * w for _ in range(h)]

    def same(p, q):
        return max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2])) <= 1

    for y in range(h):
        x = 0
        while x < w:
            e = x
            while e + 1 < w and same(px[e + 1, y], px[x, y]):
                e += 1
            if e - x + 1 >= 8:
                for k in range(x, e + 1):
                    mask[y][k] = True
            x = e + 1
    for x in range(w):
        y = 0
        while y < h:
            e = y
            while e + 1 < h and same(px[x, e + 1], px[x, y]):
                e += 1
            if e - y + 1 >= 8:
                for k in range(y, e + 1):
                    mask[k][x] = True
            y = e + 1
    return mask


def compare(name, out_dir):
    existing = name in EXISTING
    if existing:
        columns, cw, ch, cells = EXISTING[name]
        whole = Image.open(os.path.join(REF, name + ".png")).convert("RGB")
    else:
        columns, cw, ch, cells = SHEETS[name]
    ours = Image.open(os.path.join(ROOT, "docs/ui/looks/windows", name + ".png")).convert("RGB")
    for i, cell in enumerate(cells):
        if cell is None:
            continue
        ox, oy = cell_origin(columns, cw, ch, i)
        if existing:
            ref = whole.crop((ox, oy, ox + cell[0], oy + cell[1]))
            cell = (name,)
        else:
            sx, sy = shift_of(cell)
            ox, oy = ox + sx, oy + sy
            ref = crop_of(cell)
        got = ours.crop((ox, oy, ox + ref.width, oy + ref.height))
        mask = flat_mask(ref)
        flat = flat_off = flat_worst = soft_worst = soft_over = 0
        diff = Image.new("RGB", ref.size)
        where = []
        for yy in range(ref.height):
            for xx in range(ref.width):
                a, b = ref.getpixel((xx, yy)), got.getpixel((xx, yy))
                d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                diff.putpixel((xx, yy), (min(255, d * 4),) * 3)
                if mask[yy][xx]:
                    flat += 1
                    flat_worst = max(flat_worst, d)
                    if d > 2:
                        flat_off += 1
                        where.append((xx, yy, d))
                else:
                    soft_worst = max(soft_worst, d)
                    soft_over += d > 2
        print("%s cell %d %s: flat px %d, off by >2: %d, max %d; anti-aliased: max %d, >2: %d" % (
            name, i, cell[0], flat, flat_off, flat_worst, soft_worst, soft_over))
        if where:
            import numpy as np
            from scipy import ndimage
            grid = np.zeros((ref.height, ref.width), bool)
            for (xx, yy, dd) in where:
                grid[yy, xx] = True
            lab, n = ndimage.label(ndimage.binary_dilation(grid, iterations=2))
            boxes = []
            for k, sl in enumerate(ndimage.find_objects(lab)):
                hit = [(xx, yy, dd) for (xx, yy, dd) in where if sl[0].start <= yy < sl[0].stop and sl[1].start <= xx < sl[1].stop]
                boxes.append((sl[1].start + 2, sl[0].start + 2, sl[1].stop - 2, sl[0].stop - 2, len(hit), max(h[2] for h in hit)))
            boxes.sort(key=lambda b: -b[4])
            print("   flat mismatch groups (x0,y0,x1,y1,count,max): " + " ".join("%d,%d,%d,%d,%d,%d" % b for b in boxes[:14]))
        s = 4
        sheet = Image.new("RGB", (ref.width * s, ref.height * s * 3 + 8), (255, 0, 255))
        sheet.paste(ref.resize((ref.width * s, ref.height * s), Image.NEAREST), (0, 0))
        sheet.paste(got.resize((ref.width * s, ref.height * s), Image.NEAREST), (0, ref.height * s + 4))
        sheet.paste(diff.resize((ref.width * s, ref.height * s), Image.NEAREST), (0, ref.height * s * 2 + 8))
        sheet.save(os.path.join(out_dir, "%s_%d.png" % (name, i)))


# ---------------------------------------------------------------------------------------------
# The sheets. Rectangles are the controls.json rectangles (window-relative, 100 %).
S = "states/"
D = "states/"  # the rest grabs live beside the state grabs


def trio(rest, pressed, focused, x, y, w, h):
    return [(D + rest, x, y, w, h), (S + pressed, x, y, w, h), (S + focused, x, y, w, h)]


# Check box: rest, pressed (mouse down), keyboard focus; rows of the Options pages. Show Foil Symbol's
# pressed grab shows no pressed face (focus rectangle only), so its cell is left out.
SHEETS["checkbox_states"] = (3, 160, 29,
    trio("dialog-options-interface-rest@1x.png", "checkbox-pressed-options-hide-splash@1x.png",
         "checkbox-focused-options-hide-splash@1x.png", 215, 74, 152, 21)
    + [(D + "dialog-options-grids-rest@1x.png", 224, 132, 106, 21),
       (S + "checkbox-pressed-options-show-filter-row@1x.png", 224, 132, 106, 21), None]
    + [(D + "dialog-options-grids-rest@1x.png", 224, 102, 106, 21), None,
       (S + "checkbox-focused-options-show-foil@1x.png", 224, 102, 106, 21)]
    + trio("dialog-options-morph-rest@1x.png", "checkbox-pressed-options-morph-use@1x.png",
           "checkbox-focused-options-morph-use@1x.png", 215, 71, 108, 21)
    + trio("dialog-options-interface-rest@1x.png", "checkbox-pressed-options-show-tooltips@1x.png",
           "checkbox-focused-options-show-tooltips@1x.png", 215, 155, 90, 21))

EXISTING["checkbox_dialog"] = (3, 290, 117, [(220, 117), (290, 64), (290, 32)])
EXISTING["radio_dialog"] = (2, 280, 120, [(254, 120), (280, 36)])
EXISTING["radio_group_dialog"] = (1, 496, 224, [(496, 224), (302, 116)])
EXISTING["group_box_dialog"] = (1, 525, 108, [(525, 108), (510, 28), (510, 28), (510, 28)])
EXISTING["check_list_box_dialog"] = (1, 500, 348, [(500, 348)])

if __name__ == "__main__":
    command, name = sys.argv[1], sys.argv[2]
    if command == "ref":
        make_ref(name)
    else:
        compare(name, sys.argv[3] if len(sys.argv) > 3 else os.environ.get("TEMP", "."))
