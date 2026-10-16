"""Which captured states of a control have a cell in its ref sheets?

`python -I scripts/looks_cover.py <manifest Control substring> <ref sheet prefix> [<prefix> ...]`

For every manifest row of states/manifest.csv whose Control contains the substring, the grab is diffed against its nearest rest grab
(same size, fewest differing pixels among states/*rest*, dialogs/*); the bounding box of the difference (dilated by 3) is cropped from
the grab and searched exactly in the ref sheets docs/ui/looks/ref/windows/<prefix>*.png. Prints one line per grab: covered by
sheet@(x,y), identical to rest (no distinct look), or NO CELL.
"""
import csv
import glob
import os
import sys
import numpy as np
from PIL import Image
from numpy.lib.stride_tricks import sliding_window_view

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "docs", "ui", "looks", "ref", "windows") + os.sep


def load(p):
    return np.array(Image.open(p).convert("RGB"))


def find(tpl, img):
    h, w, _ = tpl.shape
    H, W, _ = img.shape
    if h > H or w > W:
        return None
    # candidates: pixels equal to the template's rarest-looking corner pixels, verified in full
    key = (img[:, :, 0].astype(np.int32) << 16) | (img[:, :, 1].astype(np.int32) << 8) | img[:, :, 2]
    tk = (tpl[:, :, 0].astype(np.int32) << 16) | (tpl[:, :, 1].astype(np.int32) << 8) | tpl[:, :, 2]
    vals, counts = np.unique(key, return_counts=True)
    cnt = dict(zip(vals.tolist(), counts.tolist()))
    flat = [(cnt.get(int(tk[y, x]), 0), y, x) for y in range(0, h, max(1, h // 8)) for x in range(0, w, max(1, w // 8))]
    flat = [t for t in flat if t[0] > 0]
    if not flat:
        return None
    _, py, px = min(flat)
    ys, xs = np.where(key == tk[py, px])
    for y, x in zip(ys, xs):
        y0, x0 = y - py, x - px
        if y0 < 0 or x0 < 0 or y0 + h > H or x0 + w > W:
            continue
        if (key[y0:y0 + h, x0:x0 + w] == tk).all():
            return (int(x0), int(y0))
    return None


def main():
    sub = sys.argv[1].lower()
    prefixes = sys.argv[2:]
    rows = list(csv.DictReader(open(ROOT + "states/manifest.csv", encoding="utf-8-sig")))
    rests = {}
    for p in glob.glob(ROOT + "states/*rest*@1x.png") + glob.glob(ROOT + "dialogs/*@1x.png"):
        a = load(p)
        rests.setdefault(a.shape, []).append((p, a))
    sheets = []
    for pre in prefixes:
        for p in sorted(glob.glob(ROOT + pre + "*.png")):
            sheets.append((os.path.basename(p), load(p)))
    for r in rows:
        if sub not in r["Control"].lower():
            continue
        f = r["File"]
        p = ROOT + "states/" + f
        if not os.path.exists(p):
            continue
        g = load(p)
        best = None
        for q, a in rests.get(g.shape, []):
            if q == p:
                continue
            n = int((np.abs(g.astype(int) - a.astype(int)).max(axis=2) > 0).sum())
            if best is None or n < best[0]:
                best = (n, q, a)
        if best is None:
            print("%-62s no rest grab of the same size" % f)
            continue
        d = np.abs(g.astype(int) - best[2].astype(int)).max(axis=2) > 0
        if not d.any():
            print("%-62s identical to rest (%s)" % (f, os.path.basename(best[1])))
            continue
        from scipy import ndimage
        lab, n = ndimage.label(ndimage.binary_dilation(d, structure=np.ones((3, 3), bool), iterations=3), structure=np.ones((3, 3), bool))
        parts = []
        for sl in ndimage.find_objects(lab):
            ys, xs = sl
            x0, x1, y0, y1 = max(0, xs.start + 2), min(g.shape[1], xs.stop - 2), max(0, ys.start + 2), min(g.shape[0], ys.stop - 2)
            tpl = g[y0:y1, x0:x1]
            hit = None
            for nm, s in sheets:
                pos = find(tpl, s)
                if pos:
                    hit = "%s@%s" % (nm, pos)
                    break
            parts.append("%s %s" % ((int(x0), int(y0), int(x1), int(y1)), hit or "NO CELL"))
        print("%-58s %s (vs %s)" % (f, r["State"][:26], os.path.basename(best[1])[:28]))
        for q in parts:
            print("      " + q)


if __name__ == "__main__":
    main()
