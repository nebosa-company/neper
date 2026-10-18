"""Round 20, worker l2: strict per-state comparison of a Linux look sheet with the GTK crops (edit controls).

  python -I scripts/linux_cmp_l2.py <sheet> [--scheme light|dark] [--png]

Cuts each cell of docs/ui/looks/linux[-dark]/<sheet>.png (geometry of looks.e: margin 12, spacing 10, caption 20, the control
centred in its box) and compares it with its crop in docs/ui/looks/ref/linux/<scheme>/<crop>@1x.png over the window colour.
A pixel is off when any channel differs by more than 2. Only glyph pixels are set apart: ink (a pixel that differs from the median
of its 9 x 9 neighbourhood by more than 40 in sum, in a compact component: lines such as borders and dividers are not ink) of the
reference or of ours, grown by 2 px. Borders, fills, shadows and rings are never excluded. --png writes ref | ours | diff strips
to D:/Temp/l2/cmp_<sheet>_<scheme>.png.
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = ROOT / "docs/ui/looks"
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
MARGIN, SPACING, CAPTION = 12, 10, 20
STATES = ["normal", "hover", "active", "focus", "disabled"]


def grid(prefix, extra=()):
    return [prefix + "-" + s for s in STATES] + list(extra)


SHEETS = {
    "text_edit": dict(columns=3, cell_w=222, cell_h=44, cells=[
        "entry-normal", "entry-hover", "entry-focus-ring", "entry-selected", "entry-disabled", "entry-placeholder",
        "entry-error", "entry-error-focus", "entry-warning", "entry-success", "entry-password", "search-entry"]),
    "spin_edit": dict(columns=4, cell_w=130, cell_h=44, cells=[
        "spin50-normal", "spin50-hover-up", "spin50-hover-down", "spin50-active-up", "spin50-active-down", "spin50-focus-ring",
        "spin50-disabled", "spin-normal", "spin-disabled", "spin-max"]),
    "combo_box": dict(columns=3, box_w=203, cell_w=213, cell_h=44, cells=[
        "dropdown-normal", "dropdown-hover", "dropdown-active", "dropdown-focus-ring", "dropdown-disabled", "combo-entry",
        "combo-entry-focus", "combo-entry-disabled"]),
    "image_combo_box": dict(columns=2, box_w=270, cell_w=280, cell_h=44, cells=["dropdown-ellipsis", None, None, None, None]),
    "date_edit": dict(columns=3, cell_w=140, cell_h=44, cells=["date-button", None, None]),
    "date_edit_calendar": dict(columns=1, cell_w=281, cell_h=246, cells=["calendar"]),
}


def origin(sh, i):
    col, row = i % sh["columns"], i // sh["columns"]
    return (MARGIN + col * (sh["cell_w"] + SPACING), MARGIN + row * (CAPTION + sh["cell_h"] + SPACING) + CAPTION)


def ref_crop(scheme, name):
    c = Image.open(REF / scheme / ("%s@1x.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", c.size, WINDOW[scheme] + (255,))
    bg.alpha_composite(c)
    return bg.convert("RGB")


def ink_mask(im):
    """Boolean grid: pixels of compact components that stand out from their 9 x 9 median."""
    w, h = im.size
    px = im.load()
    cand = set()
    for y in range(h):
        for x in range(w):
            vals = []
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    xx, yy = min(max(x + dx, 0), w - 1), min(max(y + dy, 0), h - 1)
                    vals.append(px[xx, yy])
            med = tuple(sorted(v[k] for v in vals)[40] for k in range(3))
            if sum(abs(px[x, y][k] - med[k]) for k in range(3)) > 40:
                cand.add((x, y))
    seen, ink = set(), set()
    for p in cand:
        if p in seen:
            continue
        comp, stack = [], [p]
        seen.add(p)
        while stack:
            q = stack.pop()
            comp.append(q)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    r = (q[0] + dx, q[1] + dy)
                    if r in cand and r not in seen:
                        seen.add(r)
                        stack.append(r)
        xs = [q[0] for q in comp]
        ys = [q[1] for q in comp]
        bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        if bw > 40 or bh > 24 or (len(comp) > 12 and (bw >= 8 * bh or bh >= 8 * bw)):
            continue  # a border, divider or edge, not a glyph
        if min(xs) < 3 or min(ys) < 3 or max(xs) >= w - 3 or max(ys) >= h - 3:
            continue  # a corner or an edge feature of the frame: never excluded
        ink.update(comp)
    return ink


def grow(ink, r, size):
    w, h = size
    out = set()
    for (x, y) in ink:
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if 0 <= x + dx < w and 0 <= y + dy < h:
                    out.add((x + dx, y + dy))
    return out


def run(name, scheme, png):
    sh = SHEETS[name]
    folder = "linux" if scheme == "light" else "linux-dark"
    ours = Image.open(LOOKS / folder / (name + ".png")).convert("RGB")
    total = {"off": 0, "off_all": 0, "px": 0}
    strips = []
    print(scheme, name)
    for i, crop in enumerate(sh["cells"]):
        if crop is None:
            continue
        ref = ref_crop(scheme, crop)
        w, h = ref.size
        ox, oy = origin(sh, i)
        # a sheet whose controls differ in width puts them at the left of a `box_w` wide box that the harness centres
        x0 = ox + (sh["cell_w"] - sh["box_w"]) // 2 if "box_w" in sh else ox + (sh["cell_w"] - w) // 2
        y0 = oy + (sh["cell_h"] - h) // 2
        cut = ours.crop((x0, y0, x0 + w, y0 + h))
        rp, op = ref.load(), cut.load()
        mask = grow(ink_mask(ref) | ink_mask(cut), 2, (w, h))
        off = off_all = 0
        worst = 0
        diff = Image.new("RGB", (w, h), (0, 0, 0))
        dp = diff.load()
        for y in range(h):
            for x in range(w):
                d = max(abs(rp[x, y][k] - op[x, y][k]) for k in range(3))
                if d > 2:
                    off_all += 1
                    if (x, y) not in mask:
                        off += 1
                        worst = max(worst, d)
                        dp[x, y] = (255, 0, 0)
                    else:
                        dp[x, y] = (90, 90, 0)
        total["off"] += off
        total["off_all"] += off_all
        total["px"] += w * h - len(mask)
        print("  %-22s %3dx%-3d off %4d (worst %3d)  incl glyphs %4d  of %d" % (crop, w, h, off, worst, off_all, w * h - len(mask)))
        strips.append((ref, cut, diff))
    print("  total off %d of %d; incl glyphs %d" % (total["off"], total["px"], total["off_all"]))
    if png and strips:
        s = 3
        W = max(a.width for a, _, _ in strips) * s
        Hs = sum(a.height * s + 6 for a, _, _ in strips)
        out = Image.new("RGB", (W * 3 + 20, Hs), (128, 128, 128))
        y = 0
        for a, b, c in strips:
            for k, im in enumerate((a, b, c)):
                out.paste(im.resize((im.width * s, im.height * s), Image.NEAREST), (k * (W + 10), y))
            y += a.height * s + 6
        p = "D:/Temp/l2/cmp_%s_%s.png" % (name, scheme)
        out.save(p)
        print("  wrote", p)


POPUP = {"combo_box_open": ("dropdown-open", {"light": (255, 255, 255), "dark": (56, 56, 56)})}


def run_popup(name, scheme, png):
    """The open list: the popover is found in our sheet by its colour, the reference crop (shadow margin included, transparent
    corners over the window colour) is laid on it by the popover's top-left, and the rows from 6 px above the popover down are
    compared (the button above it is not the reference's)."""
    crop, colour = POPUP[name]
    colour = colour[scheme]
    ref = ref_crop(scheme, crop)
    rw, rh = ref.size
    # the reference's own popover rectangle: its fully opaque pixels
    raw = Image.open(REF / scheme / ("%s@1x.png" % crop)).convert("RGBA")
    ox_, oy_ = 24, 28
    pw, ph = 158, 117
    folder = "linux" if scheme == "light" else "linux-dark"
    ours = Image.open(LOOKS / folder / (name + ".png")).convert("RGB")
    W, H = ours.size
    pix = ours.load()
    seen = set()
    best = []
    for y in range(H):
        for x in range(W):
            if pix[x, y] != colour or (x, y) in seen:
                continue
            comp, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                q = stack.pop()
                comp.append(q)
                for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    r = (q[0] + d[0], q[1] + d[1])
                    if 0 <= r[0] < W and 0 <= r[1] < H and r not in seen and pix[r[0], r[1]] == colour:
                        seen.add(r)
                        stack.append(r)
            if len(comp) > len(best):
                best = comp
    bx0, bx1 = min(p[0] for p in best), max(p[0] for p in best)
    by0, by1 = min(p[1] for p in best), max(p[1] for p in best)
    print(scheme, name, "popover found", bx1 - bx0 + 1, "x", by1 - by0 + 1, "at", bx0, by0, "(reference 158 x 117)")
    x0, y0 = bx0 - ox_, by0 - oy_
    cut = ours.crop((x0, y0, x0 + rw, y0 + rh))
    rp, op = ref.load(), cut.load()
    mask = grow(ink_mask(ref) | ink_mask(cut), 2, (rw, rh))
    off = body = inside = 0
    worst = 0
    diff = Image.new("RGB", (rw, rh), (0, 0, 0))
    dp = diff.load()
    for y in range(oy_ - 6, rh):
        for x in range(rw):
            d = max(abs(rp[x, y][k] - op[x, y][k]) for k in range(3))
            if d > 2 and (x, y) not in mask:
                off += 1
                worst = max(worst, d)
                dp[x, y] = (255, 0, 0)
                if ox_ <= x < ox_ + pw and oy_ <= y < oy_ + ph:
                    body += 1
    print("  off %d (worst %d); inside the popover %d; the rest (shadow, corners) %d" % (off, worst, body, off - body))
    if png:
        s = 3
        out = Image.new("RGB", (rw * s * 3 + 20, rh * s), (128, 128, 128))
        for k, im in enumerate((ref, cut, diff)):
            out.paste(im.resize((rw * s, rh * s), Image.NEAREST), (k * (rw * s + 10), 0))
        p = "D:/Temp/l2/cmp_%s_%s.png" % (name, scheme)
        out.save(p)
        print("  wrote", p)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    schemes = ["light", "dark"]
    if "--scheme" in sys.argv:
        schemes = [sys.argv[sys.argv.index("--scheme") + 1]]
        args = [a for a in args if a not in schemes]
    for n in args:
        for sc in schemes:
            if n in POPUP:
                run_popup(n, sc, "--png" in sys.argv)
            else:
                run(n, sc, "--png" in sys.argv)
