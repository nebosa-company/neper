"""Round 21 (shadow worker): the strict compare of the data grid, dialog and combo box Linux sheets with the GTK crops, every state.

  python -I scripts/linux_cmp_shadow.py [sheet ...]        sheets: data_grid dialog combo_box combo_box_open (default: all four)
  python -I scripts/linux_cmp_shadow.py --png [sheet ...]  also write ref | ours | off strips to $SHADOWOUT (default D:/Temp/l21/cmp)

Each cell of docs/ui/looks/linux[-dark]/<sheet>.png is cut out where the harness puts it (the geometry of scripts/linux_cmp_l4.py and
linux_cmp_l2.py) and held against its crop in docs/ui/looks/ref/linux/<scheme>/<crop>@1x.png over the window colour. A reference pixel is
FLAT when its 8 neighbours are all within 2 levels of it (a crop's own edge: the neighbours it has); it is OFF when ours differs from it by
more than 2 levels in any channel. Only two things are set apart: glyph pixels (ink of the reference or of ours, a compact component that
stands out from its 9 x 9 median, grown by 2 px) and nothing else: borders, fills, shadows and focus rings are always compared. The
count reported per state is flat pixels off; "any" also counts the steep pixels (an edge, an arc) that are not flat in the reference.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import linux_cmp_l2 as l2  # noqa: E402
import linux_cmp_l4 as l4  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = Path(os.environ.get("SHADOWLOOKS", ROOT / "docs/ui/looks"))
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
OUT = Path(os.environ.get("SHADOWOUT", "D:/Temp/l21/cmp"))


def ref_over(scheme, name):
    c = Image.open(REF / scheme / ("%s@1x.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", c.size, WINDOW[scheme] + (255,))
    bg.alpha_composite(c)
    return np.asarray(bg.convert("RGB")).astype(int)


def flat_of(ref):
    h, w = ref.shape[:2]
    pad = np.pad(ref, ((1, 1), (1, 1), (0, 0)), mode="edge")
    flat = np.ones((h, w), bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            nb = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            flat &= np.abs(nb - ref).max(axis=2) <= 2
    return flat


def ink_of(img):
    """Compact components that stand out from the 9 x 9 median (as linux_cmp_l2.ink_mask, vectorised)."""
    h, w = img.shape[:2]
    med = np.stack([ndimage.median_filter(img[:, :, k], size=9, mode="nearest") for k in range(3)], axis=2)
    cand = np.abs(img - med).sum(axis=2) > 40
    lab, n = ndimage.label(cand, structure=np.ones((3, 3)))
    ink = np.zeros((h, w), bool)
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        comp = lab[sl] == i
        size = int(comp.sum())
        bh, bw = comp.shape
        if bw > 120 or bh > 24 or (bw > 30 and size > 0.8 * bw * bh) or (size > 12 and (bw >= 8 * bh or bh >= 8 * bw)):
            continue
        if sl[1].start < 3 or sl[0].start < 3 or sl[1].stop > w - 3 or sl[0].stop > h - 3:
            continue
        ink[sl] |= comp
    return ink


def grow(mask, r):
    return ndimage.binary_dilation(mask, structure=np.ones((2 * r + 1, 2 * r + 1), bool))


def judge(name, ref, ours, skip_rows=0):
    d = np.abs(ours - ref).max(axis=2)
    glyph = grow(ink_of(ref) | ink_of(ours), 2)
    flat = flat_of(ref)
    use = ~glyph
    use[:skip_rows] = False
    off = (d > 2) & use & flat
    anyoff = (d > 2) & use
    return int(off.sum()), int(anyoff.sum()), int((use & flat).sum()), off, glyph


def strip(ref, ours, off, glyph, path):
    h, w = ref.shape[:2]
    vis = np.zeros((h, w, 3), np.uint8)
    vis[glyph] = (60, 60, 120)
    vis[off] = (255, 0, 0)
    both = np.concatenate([ref.astype(np.uint8), np.zeros((h, 4, 3), np.uint8), ours.astype(np.uint8), np.zeros((h, 4, 3), np.uint8), vis], axis=1)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(both).resize((both.shape[1] * 2, h * 2), Image.NEAREST).save(path)


def run_l4(name, scheme, png):
    sheet = l4.SHEETS[name]
    folder = "linux" if scheme == "light" else "linux-dark"
    ours_im = np.asarray(Image.open(LOOKS / folder / (name + ".png")).convert("RGB")).astype(int)
    rows = []
    for i, crop in enumerate(sheet["cells"]):
        ref = ref_over(scheme, crop)
        h, w = ref.shape[:2]
        x0, y0 = l4.origin(sheet, i)
        x0 += (sheet["cell_w"] - w) // 2
        y0 += (sheet["cell_h"] - h) // 2
        ours = ours_im[y0:y0 + h, x0:x0 + w]
        off, anyoff, nflat, offm, glyph = judge(name, ref, ours)
        rows.append((crop, off, anyoff, nflat))
        if png:
            strip(ref, ours, offm, glyph, OUT / ("%s_%s_%s.png" % (name, scheme, crop)))
    return rows


def run_l2(name, scheme, png):
    sheet = l2.SHEETS[name]
    folder = "linux" if scheme == "light" else "linux-dark"
    ours_im = np.asarray(Image.open(LOOKS / folder / (name + ".png")).convert("RGB")).astype(int)
    rows = []
    for i, crop in enumerate(sheet["cells"]):
        if crop is None:
            continue
        ref = ref_over(scheme, crop)
        h, w = ref.shape[:2]
        ox, oy = l2.origin(sheet, i)
        x0 = ox + (sheet["cell_w"] - sheet["box_w"]) // 2 if "box_w" in sheet else ox + (sheet["cell_w"] - w) // 2
        y0 = oy + (sheet["cell_h"] - h) // 2
        ours = ours_im[y0:y0 + h, x0:x0 + w]
        off, anyoff, nflat, offm, glyph = judge(name, ref, ours)
        rows.append((crop, off, anyoff, nflat))
        if png:
            strip(ref, ours, offm, glyph, OUT / ("%s_%s_%s.png" % (name, scheme, crop)))
    return rows


def run_open(scheme, png):
    """The open list: the popover is found in our sheet by its colour, the reference crop (shadow margin included) is laid on it by the
    popover's first full row and column, and the rows from 6 px above the popover down are compared (the button above is not the reference's)."""
    crop = "dropdown-open"
    colour = {"light": (255, 255, 255), "dark": (56, 56, 56)}[scheme]
    ref = ref_over(scheme, crop)
    rh, rw = ref.shape[:2]
    folder = "linux" if scheme == "light" else "linux-dark"
    ours_im = np.asarray(Image.open(LOOKS / folder / "combo_box_open.png").convert("RGB")).astype(int)
    lab, n = ndimage.label((ours_im == np.array(colour)).all(axis=2))
    sizes = ndimage.sum(np.ones_like(lab), lab, index=range(1, n + 1))
    k = int(np.argmax(sizes)) + 1
    ys, xs = np.nonzero(lab == k)
    bx0, by0 = int(xs.min()), int(ys.min())
    x0, y0 = bx0 - 24, by0 - 28
    ours = ours_im[y0:y0 + rh, x0:x0 + rw]
    off, anyoff, nflat, offm, glyph = judge("open", ref, ours, skip_rows=22)
    if png:
        strip(ref, ours, offm, glyph, OUT / ("combo_box_open_%s_%s.png" % (scheme, crop)))
    return [(crop + " (popover at %d,%d)" % (bx0, by0), off, anyoff, nflat)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    png = "--png" in sys.argv
    names = args or ["data_grid", "dialog", "combo_box", "combo_box_open"]
    grand = {}
    for name in names:
        for scheme in ("light", "dark"):
            if name in l4.SHEETS:
                rows = run_l4(name, scheme, png)
            elif name == "combo_box_open":
                rows = run_open(scheme, png)
            else:
                rows = run_l2(name, scheme, png)
            print("%s %s" % (name, scheme))
            for crop, off, anyoff, nflat in rows:
                print("  %-44s flat off %5d of %6d flat compared; any off %5d" % (crop, off, nflat, anyoff))
            grand[(name, scheme)] = (sum(r[1] for r in rows), max(r[1] for r in rows), sum(r[2] for r in rows))
    print("sum of flat off / worst state / sum of any off")
    for (name, scheme), v in grand.items():
        print("  %-16s %-5s %6d %6d %6d" % (name, scheme, v[0], v[1], v[2]))


if __name__ == "__main__":
    main()
