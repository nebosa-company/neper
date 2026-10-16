"""State coverage and match per windowed control rectangle.

`python -I scripts/looks_rects.py <manifest Control substring> <class,class> <ref sheet prefix> [<prefix> ...] [--look windows|windows-dark]`

For every manifest row whose Control contains the substring: the grab is paired with its nearest rest grab (same size, fewest differing
pixels); each rest `controls.json` rectangle of the given classes is cropped from the grab and from the rest grab. A rectangle that is
identical in both is not a visible state change. Otherwise the tight ink box of the grab crop is searched exactly in the ref sheets and, where
found, compared with our render at the same place: pixels off by more than 2 levels in total and outside the text rows (ink lines are
excluded by dilating the dark text pixels), with the worst error. `NO CELL` = the changed control appears in no ref sheet.
"""
import csv
import glob
import json
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cover as lc  # noqa: E402  (find, load)

ROOT = lc.ROOT
OUT = os.path.join(HERE, "..", "docs", "ui", "looks") + os.sep


def tight(crop):
    flat = crop.reshape(-1, 3)
    key = (flat[:, 0].astype(np.int64) << 16) | (flat[:, 1].astype(np.int64) << 8) | flat[:, 2]
    vals, counts = np.unique(key, return_counts=True)
    k = vals[counts.argmax()]
    bg = np.array([(k >> 16) & 255, (k >> 8) & 255, k & 255])
    m = np.abs(crop.astype(int) - bg).max(axis=2) > 0
    if not m.any():
        return None
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def main():
    args = [a for a in sys.argv[1:]]
    look = "windows"
    if "--look" in args:
        i = args.index("--look")
        look = args[i + 1]
        del args[i:i + 2]
    sub, classes, prefixes = args[0].lower(), set(args[1].split(",")), args[2:]
    rows = list(csv.DictReader(open(ROOT + "states/manifest.csv", encoding="utf-8-sig")))
    rests = {}
    for p in glob.glob(ROOT + "states/*rest*@1x.png"):
        rests.setdefault(lc.load(p).shape, []).append(p)
    sheets = []
    for pre in prefixes:
        for p in sorted(glob.glob(ROOT + pre + "*.png")):
            n = os.path.basename(p)
            sheets.append((n, lc.load(p), lc.load(OUT + look + "/" + n)))
    tot = ok = 0
    for r in rows:
        if sub not in r["Control"].lower():
            continue
        f = r["File"]
        p = ROOT + "states/" + f
        g = lc.load(p)
        best = None
        for q in rests.get(g.shape, []):
            a = lc.load(q)
            n = int((np.abs(g.astype(int) - a.astype(int)).max(axis=2) > 0).sum())
            if best is None or n < best[0]:
                best = (n, q, a)
        if best is None:
            print(f, "no rest")
            continue
        meta = json.load(open(best[1].replace("@1x.png", ".controls.json")))
        for c in meta["controls"]:
            if c["class"] not in classes or not c.get("visible", True):
                continue
            x, y, w, h = c["x"], c["y"], c["w"], c["h"]
            a = g[y:y + h, x:x + w]
            b = best[2][y:y + h, x:x + w]
            if a.shape != b.shape or (a == b).all():
                continue
            t = tight(a)
            if t is None:
                continue
            x0, y0, x1, y1 = t
            tpl = a[y0:y1, x0:x1]
            hit = None
            for nm, s, o in sheets:
                pos = lc.find(tpl, s)
                if pos:
                    hit = (nm, pos, s, o)
                    break
            tot += 1
            label = "%s %-22s %s" % (f[:48], c["text"][:18], r["State"][:22])
            if not hit:
                print("NO CELL  %s  box %s" % (label, (x + x0, y + y0, x + x1, y + y1)))
                continue
            nm, (sx, sy), s, o = hit
            ref = s[sy:sy + tpl.shape[0], sx:sx + tpl.shape[1]]
            our = o[sy:sy + tpl.shape[0], sx:sx + tpl.shape[1]]
            d = np.abs(ref.astype(int) - our.astype(int)).max(axis=2)
            dark = ndimage.binary_dilation(ref.mean(axis=2) < 150, structure=np.ones((3, 3), bool), iterations=1)
            # text rows: whole rows holding dark ink right of the first 16 columns
            textrows = np.zeros(d.shape, bool)
            tm = ndimage.binary_dilation(ref[:, 14:].mean(axis=2) < 170, structure=np.ones((3, 3), bool), iterations=2)
            textrows[:, 14:] = tm
            non = d.copy()
            non[textrows] = 0
            good = int((non > 2).sum()) == 0
            ok += good
            print("%s  %s@%s  non-text off %d max %d  (all off %d)  %s" % ("ok     " if good else "MISMATCH", nm, (sx, sy), int((non > 2).sum()), int(non.max()), int((d > 2).sum()), label))
    print("covered+compared ok: %d of %d changed-control states" % (ok, tot))


main()
