"""WCAG check of the Neper dark sheets (round 22).

`python -I scripts/neper_dark_contrast.py [--all] [sheet ...]`   (names under docs/ui/looks/neper-dark/, without .png; none = every 1.0 sheet)

The page is the sheet's corner colour. Per sheet, from the 1.0 PNG:
  boundary : each connected group of non-page pixels (grown 2 px, box >= 8 px each way) that has a drawn border or fill must
             show it at >= 3 : 1 against the page (the perimeter colour, else the fill);
  text     : ink is whatever departs from its local background (the 9 px median), merged along the row into runs; a run
             at least 7 px tall and wider than tall is text and needs >= 4.5 : 1 (its core pixel against that background),
             any other ink blob (icon, mark, caret) needs >= 3 : 1; hairlines (1 px wide or tall) are not judged.
A disabled control is exempt in WCAG. Neper draws one as its ink at 38 % (content) and 12 % (container) over what it sits
on (style.disabled_look), so a run or fill that is exactly that mix of the on-surface inks over its background is skipped and
counted as `disabled`. Exit status is the number of sheets with a FAIL line.
"""
import glob
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks", "neper-dark")


def lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lum_arr(img):
    l = lin(img.astype(float))
    return 0.2126 * l[..., 0] + 0.7152 * l[..., 1] + 0.0722 * l[..., 2]


def ratio(a, b):
    hi, lo = np.maximum(a, b), np.minimum(a, b)
    return (hi + 0.05) / (lo + 0.05)


def mode(px):
    v, n = np.unique(px.reshape(-1, 3), axis=0, return_counts=True)
    return tuple(int(x) for x in v[n.argmax()])


def hx(c):
    return "#%02X%02X%02X" % tuple(int(x) for x in c)


def one_lum(c):
    return float(lum_arr(np.array([[c]], dtype=np.uint8))[0, 0])


INKS = [(225, 226, 233), (196, 198, 213), (141, 144, 158)]


def disabled(c, bg, alpha):
    return any(max(abs(c[k] - (bg[k] + alpha * (i[k] - bg[k]))) for k in range(3)) <= 3 for i in INKS)


def groups(img, page):
    m = np.abs(img.astype(int) - np.array(page)).max(axis=2) > 6
    lab, _ = ndimage.label(ndimage.binary_dilation(m, structure=np.ones((3, 3), bool), iterations=2), structure=np.ones((3, 3), bool))
    for ys, xs in ndimage.find_objects(lab):
        yy, xx = np.where(m[ys, xs])
        if len(yy) >= 30:
            yield xs.start + xx.min(), ys.start + yy.min(), xs.start + xx.max(), ys.start + yy.max()


def check(name):
    img = np.array(Image.open(os.path.join(ROOT, name + ".png")).convert("RGB"))
    page = tuple(int(v) for v in img[0, 0])
    lp = one_lum(page)
    fails = []
    for x0, y0, x1, y1 in groups(img, page):
        if x1 - x0 < 8 or y1 - y0 < 8:
            continue
        per = np.concatenate([img[y0, x0:x1 + 1], img[y1, x0:x1 + 1], img[y0:y1 + 1, x0], img[y0:y1 + 1, x1]])
        edge, face = mode(per), mode(img[y0 + 1:y1, x0 + 1:x1])
        shown = edge if edge != page else face
        if shown != page and not disabled(shown, page, 0.12):
            r = float(ratio(one_lum(shown), lp))
            if r < 3.0:
                fails.append("boundary (%d,%d) %dx%d %s on page %s %.2f:1 < 3" % (x0, y0, x1 - x0 + 1, y1 - y0 + 1, hx(shown), hx(page), r))
    # text and glyphs, over the whole sheet
    lum = lum_arr(img)
    bgc = np.stack([ndimage.median_filter(img[..., k], size=9) for k in range(3)], axis=2)
    bg = lum_arr(bgc)
    cr = ratio(lum, bg)
    ink = cr > 1.25
    runs, _ = ndimage.label(ndimage.binary_dilation(ink, structure=np.ones((1, 3), bool), iterations=2), structure=np.ones((3, 3), bool))
    for sl in ndimage.find_objects(runs):
        ys, xs = sl
        h, w = ys.stop - ys.start, xs.stop - xs.start
        sel = ink[sl]
        if sel.sum() < 6 or min(h, w) < 2:
            continue
        near = bg[max(ys.start - 2, 0):ys.stop + 2, max(xs.start - 2, 0):xs.stop + 2]
        if ratio(near.max(), near.min()) > 1.12:
            continue
        i = np.unravel_index(np.where(sel, cr[sl], 0).argmax(), sel.shape)
        core = float(cr[sl][i])
        text = h >= 7 and w > h and sel.sum() >= 12
        need = 4.5 if text else 3.0
        y, x = ys.start + i[0], xs.start + i[1]
        if core < need and not disabled(img[y, x].astype(float), bgc[y, x].astype(float), 0.38):
            fails.append("%s (%d,%d) %dx%d %s on %s %.2f:1 < %.1f" % ("text" if text else "glyph", xs.start, ys.start, w, h, hx(img[y, x]), hx(page) if abs(bg[y, x] - lp) < 1e-3 else hx(bgc[y, x]), core, need))
    return fails


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not names:
        names = sorted(os.path.basename(f)[:-4] for f in glob.glob(os.path.join(ROOT, "*.png")) if "@" not in f and "-vs-" not in f)
    bad = 0
    for n in names:
        f = check(n)
        print("%s: %s" % (n, "ok" if not f else "%d FAIL" % len(f)))
        for line in f:
            print("  FAIL " + line)
        bad += bool(f)
    print("%d of %d sheets with FAIL lines" % (bad, len(names)))
    sys.exit(bad)


if __name__ == "__main__":
    main()
