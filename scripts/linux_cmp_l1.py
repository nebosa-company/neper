"""Linux look comparer (round 20, worker l1): GTK reference crops against the sheets of docs/ui/looks/linux[-dark].

  python -I scripts/linux_cmp_l1.py compose [sheet ...]      write docs/ui/looks/ref/linux/composite/{light,dark}/<sheet>.png
  python -I scripts/linux_cmp_l1.py diff [sheet ...]         strict per-cell counts (see below)
  python -I scripts/linux_cmp_l1.py view <sheet> <scheme> <cell> [zoom] [out.png]   reference | ours | difference, enlarged

The strict metric: every pixel of the reference crop grown by 3 px is off when ours differs from it by more than 2 levels in any
channel. Not counted: pixels within 2 px of text ink and within 1 px of coloured artwork (tick, icon) inside the rectangles the sheet
names, since Cantarell is hinted by GTK and not here. Borders, fills, shadows and focus rings are always counted. The sheet geometry
(margin 12, spacing 10, caption 20) is looks.e's, shared with scripts/linux/compose_ref.py.
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = ROOT / "docs/ui/looks"
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
FOLDER = {"light": "linux", "dark": "linux-dark"}
MARGIN, SPACING, CAPTION = 12, 10, 20
STATES = ["normal", "hover", "active", "focus", "disabled"]


def grid(prefix_rows, states=STATES):
    return ["%s-%s" % (r, s) for r in prefix_rows for s in states]


# rects are (x0, y0, x1, y1) inclusive, in crop coordinates. text: where the label's ink is; art: coloured artwork.
SHEETS = {
    "checkbox": dict(columns=5, cell_w=101, cell_h=44, cells=grid(["check-off", "check-on", "check-mixed"]),
                     text=[(26, 4, 70, 24)], art=lambda c: [] if "-off-" in c else [(6, 6, 21, 21)]),
    "radio": dict(columns=5, cell_w=101, cell_h=44, cells=grid(["radio-off", "radio-on"]),
                  text=[(26, 4, 68, 24)], art=lambda c: []),
    "label": dict(columns=3, cell_w=116, cell_h=29, cells=["label", "label-dim", "label-heading"], text=[(0, 0, 95, 18)], art=None),
    "group_box": dict(columns=2, cell_w=220, cell_h=101, cells=["card", "frame"], text=[(40, 20, 160, 50), (4, 7, 60, 26), (60, 46, 140, 70)], art=None, grow=0),
    "button_edit": dict(columns=4, cell_w=221, cell_h=44, cells=["entry-with-button", None, None, None], text=[(4, 8, 160, 26)], art=lambda c: [(172, 6, 196, 28)]),
    "button_more": dict(columns=3, cell_w=212, cell_h=54, cells=grid(["button-pill"]) + ["button-linked"], text=lambda c: [(4, 4, 194, 30)] if "linked" in c else [(8, 6, 104, 38)], art=None),
    "checkbox_switch": dict(columns=5, cell_w=66, cell_h=46, cells=grid(["switch-off", "switch-on"]), text=[], art=None, grow=0),
    "radio_group": dict(columns=1, cell_w=101, cell_h=96, cells=["radio-group"], text=[(26, 4, 78, 90)], art=lambda c: []),
}


def origin(sheet, i):
    col, row = i % sheet["columns"], i // sheet["columns"]
    return (MARGIN + col * (sheet["cell_w"] + SPACING), MARGIN + row * (CAPTION + sheet["cell_h"] + SPACING) + CAPTION)


def size(sheet):
    n = len(sheet["cells"])
    rows = (n + sheet["columns"] - 1) // sheet["columns"]
    return (MARGIN * 2 + sheet["columns"] * sheet["cell_w"] + (sheet["columns"] - 1) * SPACING,
            MARGIN * 2 + rows * (CAPTION + sheet["cell_h"]) + (rows - 1) * SPACING)


def crop_image(scheme, name):
    return Image.open(REF / scheme / ("%s@1x.png" % name)).convert("RGB")


def crop_origin(sheet, i, c):
    x, y = origin(sheet, i)
    return x + (sheet["cell_w"] - c.width) // 2, y + (sheet["cell_h"] - c.height) // 2


def compose(name):
    sheet = SHEETS[name]
    for scheme in ("light", "dark"):
        im = Image.new("RGB", size(sheet), WINDOW[scheme])
        for i, crop in enumerate(sheet["cells"]):
            if crop is None:
                continue
            c = crop_image(scheme, crop)
            im.paste(c, crop_origin(sheet, i, c))
        out = REF / "composite" / scheme / (name + ".png")
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out, optimize=True)
        print("wrote", out.relative_to(ROOT))


def texts(sheet, crop):
    t = sheet.get("text", [])
    return t(crop) if callable(t) else t


def cell_diff(sheet, scheme, i, ref, ours):
    crop = sheet["cells"][i]
    c = crop_image(scheme, crop)
    ox, oy = crop_origin(sheet, i, c)
    rp, op = ref.load(), ours.load()

    def d(x, y):
        return max(abs(rp[x, y][k] - op[x, y][k]) for k in range(3))

    def far(p, q):
        return sum(abs(p[k] - q[k]) for k in range(3)) > 40

    masked = set()

    def mask(rects, grow):
        for (x0, y0, x1, y1) in rects:
            bgp = rp[ox + x0, oy + y0]
            ink = [(x, y) for y in range(oy + y0, oy + y1 + 1) for x in range(ox + x0, ox + x1 + 1)
                   if far(rp[x, y], bgp) or far(op[x, y], bgp)]
            for (x, y) in ink:
                for dy in range(-grow, grow + 1):
                    for dx in range(-grow, grow + 1):
                        masked.add((x + dx, y + dy))
    mask(texts(sheet, crop), 2)
    # where the label's ink stands: bounding boxes in the reference and ours, and the pixels inside the text rectangles that differ by more than 40
    boxes = []
    glyph_off = 0
    for (x0, y0, x1, y1) in texts(sheet, crop):
        bgp = rp[ox + x0, oy + y0]
        for im in (rp, op):
            pts = [(x, y) for y in range(oy + y0, oy + y1 + 1) for x in range(ox + x0, ox + x1 + 1) if far(im[x, y], bgp)]
            boxes.append((min(p[0] for p in pts) - ox, max(p[0] for p in pts) - ox, min(p[1] for p in pts) - oy, max(p[1] for p in pts) - oy) if pts else None)
        glyph_off += sum(1 for y in range(oy + y0, oy + y1 + 1) for x in range(ox + x0, ox + x1 + 1) if d(x, y) > 40)
    art = sheet.get("art")
    if art:
        mask(art(crop), 1)
    g = sheet.get("grow", 3)
    off = worst = flat = flat_off = 0
    for y in range(max(oy - g, 0), min(oy + c.height + g, ref.height)):
        for x in range(max(ox - g, 0), min(ox + c.width + g, ref.width)):
            if (x, y) in masked:
                continue
            v = d(x, y)
            worst = max(worst, v)
            off += v > 2
            if all(max(abs(rp[x + a, y + b][k] - rp[x, y][k]) for k in range(3)) <= 2 for a in (-1, 0, 1) for b in (-1, 0, 1)):
                flat += 1
                flat_off += v > 2
    return off, worst, flat, flat_off, len(masked), boxes, glyph_off


def diff(name):
    sheet = SHEETS[name]
    for scheme in ("light", "dark"):
        ref = Image.open(REF / "composite" / scheme / (name + ".png")).convert("RGB")
        ours = Image.open(LOOKS / FOLDER[scheme] / (name + ".png")).convert("RGB")
        total = flat_total = 0
        print(name, scheme)
        for i, crop in enumerate(sheet["cells"]):
            if crop is None:
                continue
            off, worst, flat, flat_off, masked, boxes, glyph_off = cell_diff(sheet, scheme, i, ref, ours)
            total += off
            flat_total += flat_off
            print("  %-26s off %4d (worst %3d)  flat %5d off %4d  masked %d  text ink ref %s ours %s, glyph px off %d" % (crop, off, worst, flat, flat_off, masked, boxes[0] if boxes else "-", boxes[1] if boxes else "-", glyph_off))
        print("  total off %d, flat off %d" % (total, flat_total))


def view(name, scheme, i, zoom=6, out=None):
    sheet = SHEETS[name]
    ref = Image.open(REF / "composite" / scheme / (name + ".png")).convert("RGB")
    ours = Image.open(LOOKS / FOLDER[scheme] / (name + ".png")).convert("RGB")
    c = crop_image(scheme, sheet["cells"][i])
    ox, oy = crop_origin(sheet, i, c)
    box = (ox - 3, oy - 3, ox + c.width + 3, oy + c.height + 3)
    a, b = ref.crop(box), ours.crop(box)
    df = Image.new("RGB", a.size)
    ap, bp, dp = a.load(), b.load(), df.load()
    for y in range(a.height):
        for x in range(a.width):
            m = max(abs(ap[x, y][k] - bp[x, y][k]) for k in range(3))
            dp[x, y] = (0, 0, 0) if m <= 2 else (255, 0, 0) if m > 16 else (255, 200, 0)
    w, h = a.size
    sheet_im = Image.new("RGB", (w * zoom * 3 + 20, h * zoom), (128, 0, 128))
    for k, im in enumerate((a, b, df)):
        sheet_im.paste(im.resize((w * zoom, h * zoom), Image.NEAREST), (k * (w * zoom + 10), 0))
    out = out or str(ROOT.parent / "l1scratch" / "view.png")
    sheet_im.save(out)
    print(out)


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "compose":
        for n in args or SHEETS:
            compose(n)
    elif cmd == "diff":
        for n in args or SHEETS:
            diff(n)
    elif cmd == "view":
        view(args[0], args[1], int(args[2]), int(args[3]) if len(args) > 3 else 6, args[4] if len(args) > 4 else None)
