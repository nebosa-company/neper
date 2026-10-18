"""Round 24 (worker lf) Linux comparer: every manifest crop searched in the control's committed 1x sheets (template search), then
  ring/strict : every pixel off by more than 2 levels (thin rings, lines and icons included), with the largest level difference
  ink        : reference text-ink pixels (greyscale ink over the local background, compact components) that differ by more than 2 levels

  python -I scripts/linux_cmp_lf.py [control ...] [--scheme light|dark] [-v] [--png DIR]
Sheets searched: docs/ui/looks/<linux|linux-dark>/<control>*.png (no -vs-ref, no @1.5x). Unreliable crops (forced flags, popovers) are listed but flagged.
"""
import csv
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
import os
REF = Path(os.environ.get("LF_REF", ROOT / "docs/ui/looks/ref/linux"))
LOOKS = Path(os.environ.get("LF_LOOKS", ROOT / "docs/ui/looks"))
WINDOW = {"light": (250, 250, 250), "dark": (36, 36, 36)}
FOLDER = {"light": "linux", "dark": "linux-dark"}
SKIP = ("spin-hover", "spin-active", "dropdown-open", "popover-menu-open", "tooltip", "spin-focus", "spin-focus-ring")


def ref_crop(scheme, name):
    c = Image.open(REF / scheme / ("%s@1x.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", c.size, WINDOW[scheme] + (255,))
    bg.alpha_composite(c)
    return np.asarray(bg.convert("RGB")).astype(np.uint8)


def sheets(scheme, control):
    d = LOOKS / FOLDER[scheme]
    out = []
    for p in sorted(d.glob(control + "*.png")):
        n = p.stem
        if "-vs-ref" in n or "@" in n or "composite" in n:
            continue
        if control != n and not n.startswith(control + "_"):
            continue
        out.append(p)
    return out


def ink_of(a):
    """Greyscale text ink: pixels more than 12 levels (sum) from their 9 x 9 median in compact components, away from the crop edge."""
    a = a.astype(int)
    h, w, _ = a.shape
    med = np.stack([ndimage.median_filter(a[:, :, k], size=9, mode="nearest") for k in range(3)], axis=2)
    cand = np.abs(a - med).sum(axis=2) > 12
    lab, n = ndimage.label(cand, structure=np.ones((3, 3)))
    ink = np.zeros((h, w), bool)
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        m = lab[sl] == i
        bh, bw = m.shape
        cnt = int(m.sum())
        if bh > 20 or bw > 30 and cnt > 0.8 * bw * bh or (cnt > 12 and (bw >= 8 * bh or bh >= 8 * bw)):
            continue
        if sl[1].start < 3 or sl[0].start < 3 or sl[1].stop > w - 3 or sl[0].stop > h - 3:
            continue
        ink[sl][m] = True
    return ink


def locate(ref, scheme, control, name):
    best = None
    for p in sheets(scheme, control):
        im = np.asarray(Image.open(p).convert("RGB"))
        if im.shape[0] < ref.shape[0] or im.shape[1] < ref.shape[1]:
            continue
        for _try in range(30):
            try:
                r = cv2.matchTemplate(im, ref, cv2.TM_SQDIFF)
                break
            except cv2.error:
                __import__('time').sleep(2)
        mn, _, loc, _ = cv2.minMaxLoc(r)
        if best is None or mn < best[0]:
            best = (mn, p, loc, im)
    return best


def place(ref, scheme, control, name):
    """Best placement of the reference crop in the control's sheets: (sheet image, x, y, cut)."""
    b = locate(ref, scheme, control, name)
    if b is None:
        return None
    _, p, (x, y), im = b
    h, w, _ = ref.shape
    inkd = ndimage.binary_dilation(ink_of(ref), structure=np.ones((3, 3)))
    best = None
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if y + dy < 0 or x + dx < 0:
                continue
            cut = im[y + dy:y + dy + h, x + dx:x + dx + w]
            if cut.shape != ref.shape:
                continue
            off = np.abs(cut.astype(int) - ref.astype(int)).max(axis=2) > 2
            n = (int((off & ~inkd).sum()), int(off.sum()))
            if best is None or n < best[0]:
                best = (n, cut, x + dx, y + dy)
    return im, best[2], best[3], best[1]


def flat_of(a):
    """Reference pixels whose 8 neighbours are within 2 levels (the audit's flat pixels)."""
    a = a.astype(int)
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    f = np.ones((h, w), bool)
    for dy in range(3):
        for dx in range(3):
            f &= np.abs(p[dy:dy + h, dx:dx + w] - a).max(axis=2) <= 2
    return f


def all_rows():
    out, seen = [], set()
    for f in ("manifest.csv", "manifest-l2.csv", "manifest-l3.csv"):
        for r in csv.DictReader(open(REF / f)):
            if (r["scheme"], r["name"]) not in seen:
                seen.add((r["scheme"], r["name"]))
                out.append(r)
    return out


def measure(scheme, control, verbose, png=None):
    rows = [r for r in all_rows() if r["scheme"] == scheme and r["neper_control"] == control]
    tot = dict(n=0, strict=0, ink=0, inkdiff=0, worst=0, ring=0, flat=0)
    for r in rows:
        name = r["name"]
        if name.startswith(SKIP):
            continue
        ref = ref_crop(scheme, name)
        b = locate(ref, scheme, control, name)
        if b is None:
            continue
        p = b[1]
        im, ax, ay, cut = place(ref, scheme, control, name)
        h, w, _ = ref.shape
        at = (ax, ay)
        d = np.abs(cut.astype(int) - ref.astype(int)).max(axis=2)
        ink = ink_of(ref)
        inkd = ndimage.binary_dilation(ink, structure=np.ones((3, 3)))
        # text shift: the placement of ours that best fits the reference ink alone (dx, dy) and what is left of the ink diff there
        shift = (0, 0, int(((d > 2) & ndimage.binary_dilation(ink, structure=np.ones((3, 3)))).sum()))
        if ink.any():
            for ty in range(-2, 3):
                for tx in range(-2, 3):
                    ys, xs = at[1] + ty, at[0] + tx
                    if ys < 0 or xs < 0:
                        continue
                    c2 = im[ys:ys + h, xs:xs + w]
                    if c2.shape != ref.shape:
                        continue
                    dd = np.abs(c2.astype(int) - ref.astype(int)).max(axis=2)
                    k = int(((dd > 2) & ndimage.binary_dilation(ink, structure=np.ones((3, 3)))).sum())
                    if k < shift[2]:
                        shift = (tx - 0, ty - 0, k)
        strict = int((d > 2).sum())
        tot['flat'] += int(((d > 2) & flat_of(ref)).sum())
        inkoff = int(((d > 2) & inkd).sum())
        nonink = int(((d > 2) & ~inkd).sum())
        tot["n"] += 1
        tot["strict"] += strict
        tot["ink"] += int(ink.sum())
        tot["inkdiff"] += inkoff
        tot["ring"] += nonink
        tot["worst"] = max(tot["worst"], int(d.max()))
        if verbose:
            print("  %-26s %-24s @%-9s strict %4d  non-ink %4d  ink %4d/%-4d  max %3d  best text shift %+d,%+d -> %d" % (name, p.stem, "%d,%d" % at, strict, nonink, inkoff, int(inkd.sum()), int(d.max()), shift[0], shift[1], shift[2]))
        if png:
            Path(png).mkdir(parents=True, exist_ok=True)
            df = np.zeros((h, w, 3), np.uint8)
            df[d > 2] = (255, 0, 0)
            strip = np.concatenate([ref, cut, df], axis=1)
            Image.fromarray(strip).resize((strip.shape[1] * 4, strip.shape[0] * 4), Image.NEAREST).save(Path(png) / ("%s_%s_%s.png" % (control, scheme, name)))
    print("%-16s %-5s crops %2d  strict %5d  flat %4d  non-ink %5d  ink-region diff %5d of ink px %5d  max %3d" % (control, scheme, tot["n"], tot["strict"], tot["flat"], tot["ring"], tot["inkdiff"], tot["ink"], tot["worst"]))
    return tot


if __name__ == "__main__":
    a = sys.argv[1:]
    verbose = "-v" in a
    png = None
    schemes = ["light", "dark"]
    names = []
    i = 0
    while i < len(a):
        if a[i] == "--scheme":
            schemes = [a[i + 1]]; i += 1
        elif a[i] == "--png":
            png = a[i + 1]; i += 1
        elif a[i] != "-v":
            names.append(a[i])
        i += 1
    if not names:
        names = sorted({r["neper_control"] for r in all_rows()})
    for n in names:
        for s in schemes:
            measure(s, n, verbose, png)
