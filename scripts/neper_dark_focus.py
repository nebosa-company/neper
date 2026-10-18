"""WCAG 2.2 non-text contrast of the focus rings in the Neper dark sheets (round 24).

`python -I scripts/neper_dark_focus.py [sheet ...]`   (names under docs/ui/looks/neper-dark/, without .png; none = every 1.0 sheet)

Independent of neper_dark_contrast.py and of the renderer: it reads only the PNGs and the FocusRing colour (the token's #B3C5FF).
A focus indicator is a connected group of pixels of that colour, at least 20 x 20 px in its box, 100 px, and at most 6 px thick
(a filled face, a glyph, a bar or a checkbox mark is not one). Every colour that touches it (15 % of its edge pixels or more, so
the page, the gap and the face on either side, not the blends along a curve) and spreads over a face (5 px across, within
3 px of the ring) must be >= 3 : 1 against it. A light face further in, behind a dark gap, is a two-tone ring.
Exit status is the number of sheets with a FAIL line.
"""
import glob
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks", "neper-dark")
RING = np.array([179, 197, 255])
SKIP = ("native_dark", "title_bar")  # Windows-only pixel replicas the harness also renders under Neper dark


def lum(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def ratio(a, b):
    la, lb = float(lum(a)), float(lum(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def mode(px):
    v, n = np.unique(px.reshape(-1, 3), axis=0, return_counts=True)
    return v[n.argmax()]


def hx(c):
    return "#%02X%02X%02X" % tuple(int(x) for x in c)


def rings(img):
    m = np.abs(img.astype(int) - RING).max(axis=2) <= 3
    lab, _ = ndimage.label(m, structure=np.ones((3, 3), bool))
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        comp = lab == i
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if h < 20 or w < 20 or comp.sum() < 100 or ndimage.binary_erosion(comp, iterations=3).any():
            continue
        yield sl, comp


def check(name):
    return judge(np.array(Image.open(os.path.join(ROOT, name + ".png")).convert("RGB")))


def judge(img):
    fails, n = [], 0
    for sl, comp in rings(img):
        n += 1
        near = ndimage.binary_dilation(comp, structure=np.ones((3, 3), bool)) & ~comp
        px = img[near]
        zone = ndimage.binary_dilation(comp, structure=np.ones((3, 3), bool), iterations=3)
        v, k = np.unique(px.reshape(-1, 3), axis=0, return_counts=True)
        for c, cnt in zip(v, k):
            if cnt < 0.15 * len(px):  # blends along curves, not a side
                continue
            r = ratio(RING, c)
            # a thin line of a near colour is the ring's own antialiasing or edge; a face (>= 5 px across) within 3 px is not
            side = ndimage.binary_erosion(np.abs(img.astype(int) - c).max(axis=2) <= 3, iterations=2) & zone
            if r < 3.0 and side.sum() >= 10:
                fails.append("ring (%d,%d) %dx%d touches %s (%d%% of its edge) %.2f:1 < 3" % (sl[1].start, sl[0].start, sl[1].stop - sl[1].start, sl[0].stop - sl[0].start, hx(c), 100 * cnt // len(px), r))
    return fails, n


def selftest():
    """A ring straight on a light face fails; the same ring behind a 2 px dark gap passes."""
    for gap, want in ((0, 1), (2, 0)):
        img = np.zeros((60, 100, 3), np.uint8)
        img[:] = (18, 19, 24)
        img[10:50, 10:90] = RING
        img[12:48, 12:88] = (18, 19, 24) if gap else RING - 14
        img[12 + gap:48 - gap, 12 + gap:88 - gap] = RING - 14
        f, n = judge(img)
        assert n == 1 and len(f) == want, (gap, n, f)


def main():
    selftest()
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not names:
        names = sorted(os.path.basename(f)[:-4] for f in glob.glob(os.path.join(ROOT, "*.png")) if "@" not in f and "-vs-" not in f and not os.path.basename(f).startswith(SKIP))
    bad = total = 0
    for nm in names:
        f, n = check(nm)
        total += n
        if n or f:
            print("%s: %d rings, %s" % (nm, n, "ok" if not f else "%d FAIL" % len(f)))
        for line in f:
            print("  FAIL " + line)
        bad += bool(f)
    print("%d rings in %d sheets, %d sheets with FAIL lines" % (total, len(names), bad))
    sys.exit(bad)


if __name__ == "__main__":
    main()
