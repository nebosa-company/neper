"""Round 22, worker la: the audit's flat-pixel metric for the Linux edit controls.

  python -I scripts/linux_flat_la.py [sheet ...] [--png]

Cuts each cell of docs/ui/looks/linux[-dark]/<sheet>.png (geometry of scripts/linux_cmp_l2.py, whose SHEETS it reuses) and holds it
against its crop in ref/linux/<scheme> composited on the window colour, at the best placement within 3 px. A reference flat pixel has
all 8 neighbours within 2 levels; it is off when ours differs by more than 2 levels in any channel. Set aside only glyph pixels within
2 px of text ink (ink: more than 60 levels from the median of a 25 x 13 window; runs of 13 or more are borders, not ink; a piece is
text when another piece lies within 6 px or it is 12+ wide and at most 16 high). "steep" counts the same off pixels on the reference's
non-flat pixels (edges, corners, antialiasing) outside the glyph mask, for information. --png writes ref | ours | off strips to D:/Temp/la.
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("l2", ROOT / "scripts/linux_cmp_l2.py")
l2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(l2)
l2.SHEETS["spin_edit"]["cells"] = l2.SHEETS["spin_edit"]["cells"] + ["spin-vertical"]  # the 11th cell of linux_spin_edit


def flat_mask(a):
    h, w, _ = a.shape
    ok = np.ones((h, w), bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            ys, ye = max(0, -dy), h - max(0, dy)
            xs, xe = max(0, -dx), w - max(0, dx)
            d = np.abs(a[ys:ye, xs:xe] - a[ys + dy:ye + dy, xs + dx:xe + dx]).max(2)
            ok[ys:ye, xs:xe] &= d <= 2
    return ok


def text_mask(a):
    g = a.mean(2)
    med = ndimage.median_filter(g, size=(13, 25), mode="nearest")
    ink = np.abs(g - med) > 60
    for arr in (ink, ink.T):
        for row in arr:
            run = 0
            for x in range(len(row) + 1):
                if x < len(row) and row[x]:
                    run += 1
                else:
                    if run >= 13:
                        row[x - run:x] = False
                    run = 0
    lab, n = ndimage.label(ink, structure=np.ones((3, 3)))
    keep = np.zeros_like(ink)
    if n:
        for i, sl in enumerate(ndimage.find_objects(lab), 1):
            comp = lab[sl] == i
            h = sl[0].stop - sl[0].start
            w = sl[1].stop - sl[1].start
            # a neighbour piece within 6 px: dilate this piece and look for ink that is not itself
            box = np.zeros_like(ink)
            box[sl] = comp
            grown = ndimage.binary_dilation(box, structure=np.ones((3, 3)), iterations=6)
            if (grown & ink & ~box).any() or (w >= 12 and h <= 16):
                keep |= box
    return ndimage.binary_dilation(keep, structure=np.ones((3, 3)), iterations=2)


# symbolic icons are never text: their rectangles (x0, x1 inclusive, whole height) are held against the reference unmasked
ICONS = {"search-entry": [(8, 26), (186, 204)], "entry-password": [(176, 196)], "dropdown-normal": [(130, 152)], "combo-entry": [(176, 192)],
         "spin50-normal": [(54, 119)], "spin-vertical": [(30, 97)], "entry-with-button": [(172, 196)], "dropdown-ellipsis": [(222, 247)], "date-button": [(96, 114)]}


def cell(sh, ours, i, w, h, dx, dy):
    ox, oy = l2.origin(sh, i)
    x0 = ox + ((sh["cell_w"] - sh["box_w"]) // 2 if "box_w" in sh else (sh["cell_w"] - w) // 2)
    y0 = oy + (sh["cell_h"] - h) // 2
    return np.asarray(ours.crop((x0 + dx, y0 + dy, x0 + dx + w, y0 + dy + h))).astype(int)


def run(name, scheme, png):
    sh = l2.SHEETS[name]
    folder = "linux" if scheme == "light" else "linux-dark"
    ours = Image.open(l2.LOOKS / folder / (name + ".png")).convert("RGB")
    strips = []
    tot = 0
    print(scheme, name)
    for i, crop in enumerate(sh["cells"]):
        if crop is None:
            continue
        ref = np.asarray(l2.ref_crop(scheme, crop)).astype(int)
        h, w, _ = ref.shape
        flat = flat_mask(ref)
        text = text_mask(ref)
        for (ix0, ix1) in ICONS.get(crop, []):
            text[:, ix0:ix1 + 1] = False
        best = None
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                o = cell(sh, ours, i, w, h, dx, dy)
                d = np.abs(o - ref).max(2) > 2
                n = int((d & flat & ~text).sum())
                if best is None or n < best[0] or (n == best[0] and abs(dx) + abs(dy) < abs(best[1]) + abs(best[2])):
                    best = (n, dx, dy)
        n, dx, dy = best
        o0 = cell(sh, ours, i, w, h, 0, 0)
        n0 = int(((np.abs(o0 - ref).max(2) > 2) & flat & ~text).sum())
        o = cell(sh, ours, i, w, h, dx, dy)
        d = np.abs(o - ref).max(2) > 2
        steep = int((d & ~flat & ~text).sum())
        glyphs = int((d & flat).sum())
        worst = int(np.abs(o - ref).max(2)[d & flat & ~text].max()) if n else 0
        tot += n
        print("  %-22s %3dx%-3d flat off %4d (worst %3d, at %+d,%+d; at 0,0 %d)  steep %4d  glyphs counted %4d" % (crop, w, h, n, worst, dx, dy, n0, steep, glyphs))
        off = np.zeros((h, w, 3), np.uint8)
        off[d & flat & ~text] = (255, 0, 0)
        off[d & ~flat & ~text] = (255, 160, 0)
        strips.append((ref.astype(np.uint8), o.astype(np.uint8), off))
    print("  total flat off", tot)
    if png and strips:
        s = 3
        W = max(a.shape[1] for a, _, _ in strips) * s
        Hs = sum(a.shape[0] * s + 6 for a, _, _ in strips)
        out = Image.new("RGB", (W * 3 + 20, Hs), (128, 128, 128))
        y = 0
        for a, b, c in strips:
            for k, im in enumerate((a, b, c)):
                im = Image.fromarray(im)
                out.paste(im.resize((im.width * s, im.height * s), Image.NEAREST), (k * (W + 10), y))
            y += a.shape[0] * s + 6
        Path("D:/Temp/la").mkdir(exist_ok=True)
        out.save("D:/Temp/la/flat_%s_%s.png" % (name, scheme))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for n in args or list(l2.SHEETS):
        for scheme in ("light", "dark"):
            run(n, scheme, "--png" in sys.argv)
