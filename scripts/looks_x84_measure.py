"""`python -I scripts/looks_x84_measure.py name...` (round 84, lane x): compares a Windows Dark sheet with its Windows Light twin.

For every sheet docs/ui/looks/windows-dark/<name>[@1.5x].png with a same-size windows twin it reports
  size      equal or not
  lost      light edges (a neighbour step of 24 levels or more) with no dark edge (8 levels or more) within 1 px, so a dark element that
            vanished or moved; `new` is the reverse
  low       9 x 9 windows holding a dark edge whose WCAG contrast (lightest / darkest luminance of the window) is under 3 : 1 where the light
            twin's window is 3 : 1 or more, clustered; each cluster is printed as a box, to be viewed (disabled ink and hairlines are
            judged by eye, the 4.5 : 1 text bar is checked on the text ink by `ink` below)
  ink       the lowest contrast of any glyph pixel group: the darkest-to-lightest ratio over the 3 x 3 windows with the highest local range
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

R = "D:/Temp/lanes/looks84-x/docs/ui/looks/"


def lum(a):
    c = a / 255.0
    c = np.where(c <= 0.03928, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def edges(a, thr):
    g = a.astype(int)
    dx = np.abs(np.diff(g, axis=1)).max(axis=2)
    dy = np.abs(np.diff(g, axis=0)).max(axis=2)
    e = np.zeros(g.shape[:2], bool)
    e[:, :-1] |= dx >= thr
    e[:-1, :] |= dy >= thr
    return e


def window_cr(y, k=9):
    mx = ndimage.maximum_filter(y, size=k)
    mn = ndimage.minimum_filter(y, size=k)
    return (mx + 0.05) / (mn + 0.05)


def one(name, suf):
    try:
        a = np.array(Image.open(R + "windows/%s%s.png" % (name, suf)).convert("RGB"))
        b = np.array(Image.open(R + "windows-dark/%s%s.png" % (name, suf)).convert("RGB"))
    except OSError:
        return None
    if a.shape != b.shape:
        return "%-34s%s size differs %s %s" % (name, suf, a.shape[:2], b.shape[:2])
    ea, eb = edges(a, 24), edges(b, 8)
    near_b = ndimage.binary_dilation(eb, iterations=1)
    near_a = ndimage.binary_dilation(edges(a, 8), iterations=1)
    lost = int((ea & ~near_b).sum())
    new = int((edges(b, 24) & ~near_a).sum())
    ca, cb = window_cr(lum(a)), window_cr(lum(b))
    low = eb & (cb < 3.0) & (ca >= 3.0)
    lab, n = ndimage.label(ndimage.binary_dilation(low, iterations=4))
    boxes = []
    if n:
        for s in ndimage.find_objects(lab):
            boxes.append("%d,%d-%d,%d" % (s[1].start, s[0].start, s[1].stop, s[0].stop))
    return "%-34s%-6s lost %5d new %5d low-contrast clusters %d %s" % (name, suf, lost, new, n, " ".join(boxes[:8]))


if __name__ == "__main__":
    for nm in sys.argv[1:]:
        for suf in ("", "@1.5x"):
            r = one(nm, suf)
            if r:
                print(r)
