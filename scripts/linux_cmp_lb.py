"""Linux look comparer of worker lb (round 22): button, button_more, checkbox, checkbox_switch, radio, radio_group, label,
group_box, button_edit, progress_bar, vertical_grid, dialog, toolbar_button.

  python -I scripts/linux_cmp_lb.py [sheet ...] [--scheme light|dark] [--list] [--png] [--crop NAME] [--dir DIR] [--scale 1.5]

Geometry (cell boxes, crop names) comes from the earlier comparers (l1, l3, l4, compose_ref). Each reference crop (alpha
composited on the window colour) is centred in its cell and compared with docs/ui/looks/linux[-dark]/<sheet>.png.
Strict metric: a reference pixel is flat when its 8 neighbours are within 2 levels; a pixel is off when ours differs by more
than 2 levels in any channel. Only glyph pixels are set apart (ink of the reference or ours in a compact component, grown by
2 px; borders, dividers, corner features are never ink). Both counts are printed: "flat" (flat reference pixels off, glyphs
excluded), "all" (every pixel off, glyphs excluded) and "gl" (every pixel off, glyphs counted). --png writes
ref | ours | diff strips to <dir> (default D:/Temp/lb).
"""
import sys
import importlib.util
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SC = ROOT / "scripts"
REF = ROOT / "docs/ui/looks/ref/linux"
LOOKS = ROOT / "docs/ui/looks"
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
FOLDER = {"light": "linux", "dark": "linux-dark"}
MARGIN, SPACING, CAPTION = 12, 10, 20


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def sheets():
    l1, l3, l4 = (load("l%d" % k, SC / ("linux_cmp_l%d.py" % k)) for k in (1, 3, 4))
    cr = load("cr", SC / "linux/compose_ref.py")
    out = {}
    for n in ("checkbox", "checkbox_switch", "radio", "radio_group", "label", "group_box", "button_edit", "button_more"):
        s = l1.SHEETS[n]
        t = s.get("text", [])
        out[n] = (s["columns"], s["cell_w"], s["cell_h"], s["cells"], t if callable(t) else (lambda c, t=t: t))
    for n in ("progress_bar", "toolbar_button"):
        s = l3.SHEETS[n]
        ink = {c: r for c, r in s["cells"]}
        out[n] = (s["columns"], s["cell_w"], s["cell_h"], [c for c, _ in s["cells"]], lambda c, ink=ink, n=n: [r for r in ink.get(c, []) if n != "toolbar_button" or c.startswith(("toggle", "headerbar", "toolbar"))])
    for n in ("vertical_grid", "dialog"):
        s = l4.SHEETS[n]
        out[n] = (s["columns"], s["cell_w"], s["cell_h"], s["cells"], lambda c, s=s: s["text"].get(c, []))
    s = cr.SHEETS["button"]
    out["button"] = (s["columns"], s["cell_w"], s["cell_h"], s["cells"], lambda c: [(8, 6, 74, 28)] if not any(k in c for k in ("circular", "icon")) else [])
    return out


def ref_crop(scheme, name):
    c = Image.open(REF / scheme / ("%s@1x.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", c.size, WINDOW[scheme] + (255,))
    bg.alpha_composite(c)
    return np.asarray(bg.convert("RGB")).astype(int)


def ink_mask(a):
    """Compact components that stand out (sum of channels > 40) from their 9 x 9 median, not near the crop edge."""
    h, w, _ = a.shape
    med = np.stack([ndimage.median_filter(a[:, :, k], size=9, mode="nearest") for k in range(3)], axis=2)
    cand = np.abs(a - med).sum(axis=2) > 40
    lab, n = ndimage.label(cand, structure=np.ones((3, 3)))
    ink = np.zeros((h, w), bool)
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        m = lab[sl] == i
        bh, bw = m.shape
        cnt = int(m.sum())
        if bw > 120 or bh > 24 or (bw > 30 and cnt > 0.8 * bw * bh) or (cnt > 12 and (bw >= 8 * bh or bh >= 8 * bw)):
            continue
        if sl[1].start < 3 or sl[0].start < 3 or sl[1].stop > w - 3 or sl[0].stop > h - 3:
            continue
        ink[sl][m] = True
    return ink


def flat_mask(a):
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    f = np.ones((h, w), bool)
    for dy in range(3):
        for dx in range(3):
            f &= np.abs(p[dy:dy + h, dx:dx + w] - a).max(axis=2) <= 2
    return f


def cell_box(cols, cw, ch, i):
    c, r = i % cols, i // cols
    return MARGIN + c * (cw + SPACING), MARGIN + r * (CAPTION + ch + SPACING) + CAPTION


def rect_ink(ref, ours, rects):
    """Pixels inside the text rectangles (x0, y0, x1, y1 inclusive) whose sum of channels is more than 40 off the rectangle's
    corner pixel in the reference or in ours, grown by 2 px."""
    h, w, _ = ref.shape
    ink = np.zeros((h, w), bool)
    for (x0, y0, x1, y1) in rects:
        for im in (ref, ours):
            bg = im[y0, x0]
            sub = np.abs(im[y0:y1 + 1, x0:x1 + 1] - bg).sum(axis=2) > 40
            ink[y0:y1 + 1, x0:x1 + 1] |= sub
    return ndimage.binary_dilation(ink, structure=np.ones((5, 5)))


def compare(ref, ours, rects):
    d = np.abs(ref - ours).max(axis=2)
    off = d > 2
    if rects:
        ink = rect_ink(ref, ours, rects)
    else:
        ink = ndimage.binary_dilation(ink_mask(ref) | ink_mask(ours), structure=np.ones((5, 5)))
    flat = flat_mask(ref)
    return d, off, ink, flat


def run(name, scheme, a):
    cols, cw, ch, cells, texts = SH[name]
    folder = a.get("dir")
    p = LOOKS / FOLDER[scheme] / (name + ".png")
    ours = np.asarray(Image.open(p).convert("RGB")).astype(int)
    tot = [0, 0, 0]
    strips = []
    print(scheme, name)
    for i, crop in enumerate(cells):
        if crop is None or (a.get("crop") and crop != a["crop"]):
            continue
        ref = ref_crop(scheme, crop)
        h, w, _ = ref.shape
        ox, oy = cell_box(cols, cw, ch, i)
        x0, y0 = ox + (cw - w) // 2, oy + (ch - h) // 2
        cut = ours[y0:y0 + h, x0:x0 + w]
        d, off, ink, flat = compare(ref, cut, texts(crop))
        n_flat = int((off & flat & ~ink).sum())
        n_all = int((off & ~ink).sum())
        n_gl = int(off.sum())
        tot[0] += n_flat
        tot[1] += n_all
        tot[2] += n_gl
        worst = int(d[~ink].max()) if (~ink).any() else 0
        print("  %-28s %3dx%-3d flat %4d  all %4d (worst %3d)  gl %4d" % (crop, w, h, n_flat, n_all, worst, n_gl))
        if a.get("png"):
            df = np.zeros((h, w, 3), np.uint8)
            df[off & ~ink] = (255, 0, 0)
            df[off & ink] = (110, 110, 0)
            strips.append((ref.astype(np.uint8), cut.astype(np.uint8), df))
    print("  total flat %d  all %d  gl %d" % tuple(tot))
    if strips:
        s = 4
        W = max(r.shape[1] for r, _, _ in strips) * s
        H = sum(r.shape[0] * s + 6 for r, _, _ in strips)
        out = Image.new("RGB", (W * 3 + 20, H), (128, 128, 128))
        y = 0
        for r, o, df in strips:
            for k, im in enumerate((r, o, df)):
                I = Image.fromarray(im)
                out.paste(I.resize((I.width * s, I.height * s), Image.NEAREST), (k * (W + 10), y))
            y += r.shape[0] * s + 6
        d = Path(folder or "D:/Temp/lb")
        d.mkdir(parents=True, exist_ok=True)
        pth = d / ("cmp_%s_%s.png" % (name, scheme))
        out.save(pth)
        print("  wrote", pth)
    return tot


if __name__ == "__main__":
    argv = sys.argv[1:]
    opts = {}
    names = []
    schemes = ["light", "dark"]
    i = 0
    while i < len(argv):
        t = argv[i]
        if t == "--scheme":
            schemes = [argv[i + 1]]
            i += 1
        elif t == "--crop":
            opts["crop"] = argv[i + 1]
            i += 1
        elif t == "--dir":
            opts["dir"] = argv[i + 1]
            i += 1
        elif t == "--png":
            opts["png"] = True
        elif t == "--list":
            opts["list"] = True
        else:
            names.append(t)
        i += 1
    SH = sheets()
    if opts.get("list"):
        print(" ".join(SH))
        sys.exit(0)
    grand = [0, 0, 0]
    for n in names or SH:
        for sc in schemes:
            t = run(n, sc, opts)
            grand = [g + x for g, x in zip(grand, t)]
    print("GRAND flat %d all %d gl %d" % tuple(grand))
