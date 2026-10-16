"""WCAG contrast of the Windows dark sheets (round 12), for the controls with no native dark reference.

`python -I scripts/looks_contrast_dark.py <sheet> [<sheet> ...]`   (names under docs/ui/looks/windows-dark/, without .png)

The page is the sheet's corner colour. Each connected group of pixels that differ from the page (grown by 2 px) is a cell's control; per cell:
  border  : the most common colour on the 1 px perimeter of the group's box, and its contrast against the page (WCAG 2.x: (L1 + .05) / (L2 + .05));
            a perimeter that is the page colour itself or the face colour means no drawn border (reported `none`);
  face    : the most common colour inside the box;
  text    : the interior colour farthest in luminance from the face (the glyph core), its contrast against the face.
Requirements the round 12 brief sets: text >= 4.5 : 1 against its face, a control's border >= 3 : 1 against the page, in every state.
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks", "windows-dark") + os.sep


def lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lum(rgb):
    r, g, b = (float(lin(np.array(v))) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def mode(pixels):
    vals, counts = np.unique(pixels.reshape(-1, 3), axis=0, return_counts=True)
    return tuple(int(v) for v in vals[counts.argmax()])


def hx(c):
    return "#%02X%02X%02X" % c


def cells(img):
    page = tuple(int(v) for v in img[0, 0])
    m = np.abs(img.astype(int) - np.array(page)).max(axis=2) > 6
    grown = ndimage.binary_dilation(m, structure=np.ones((3, 3), bool), iterations=2)
    lab, n = ndimage.label(grown, structure=np.ones((3, 3), bool))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        ys, xs = sl
        sub = m[sl]
        yy, xx = np.where(sub)
        if len(yy) < 30:
            continue
        y0, y1, x0, x1 = ys.start + yy.min(), ys.start + yy.max(), xs.start + xx.min(), xs.start + xx.max()
        out.append((x0, y0, x1, y1))
    return page, out


def main():
    for name in sys.argv[1:]:
        img = np.array(Image.open(ROOT + name + ".png").convert("RGB"))
        page, boxes = cells(img)
        print("%s: page %s, %d groups" % (name, hx(page), len(boxes)))
        for x0, y0, x1, y1 in boxes:
            w, h = x1 - x0 + 1, y1 - y0 + 1
            if w < 8 or h < 8:
                continue
            per = np.concatenate([img[y0, x0:x1 + 1], img[y1, x0:x1 + 1], img[y0:y1 + 1, x0], img[y0:y1 + 1, x1]])
            border = mode(per)
            inner = img[y0 + 1:y1, x0 + 1:x1]
            face = mode(inner)
            flat = inner.reshape(-1, 3)
            ls = np.array([lum(tuple(int(v) for v in c)) for c in np.unique(flat, axis=0)])
            cols = np.unique(flat, axis=0)
            lf = lum(face)
            far = cols[np.abs(ls - lf).argmax()]
            text = tuple(int(v) for v in far)
            bnote = "none" if border in (page, face) else "%s %.2f:1" % (hx(border), ratio(border, page))
            print("  (%4d,%4d) %3dx%-3d face %s page-border %-16s text %s on face %.2f:1" % (x0, y0, w, h, hx(face), bnote, hx(text), ratio(text, face)))


if __name__ == "__main__":
    main()
