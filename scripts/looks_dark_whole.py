"""Whole-capture check of the Windows dark look against a native Windows 11 dark capture (docs/ui/looks/ref/windows-native/dark, 1x).

`python -I scripts/looks_dark_whole.py <capture>=<sheet>[@x0,y0,x1,y1] ...`   (LOOKS_THEME=light for the Light captures against the windows sheets;
LOOKS_DIFF=<folder> writes a 3x diff picture of each capture: reference, ours, off pixels in red)

Metric (looks_dark_native.py's, applied to every pixel of the capture or of the given rectangle instead of the flat ones only). The capture is
placed in the sheet at the whole-pixel offset with the fewest off pixels (nothing is cut from our sheet). A pixel is OFF when any channel of
ours differs by more than 2 levels. TEXT pixels are those within 2 px of text ink (looks_dark_native.text_zone); the rest are STRUCTURE.
Prints: capture, sheet, offset, pixels, structure off, text off. A row is matched under the stated rule when structure off is 0 and the text
off pixels are glyph pixels of the text engine (hinting, greyscale against ClearType), which the caller checks by eye on the diff picture.
"""
import importlib.util
import os
import sys

import cv2
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ldn", os.path.join(HERE, "looks_dark_native.py"))
ldn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ldn)

THEME = ldn.THEME


def run(capture, sheet, rect):
    ref = ldn.load(os.path.join(ldn.NATIVE, THEME, capture + "@1x.png"))
    if rect:
        x0, y0, x1, y1 = rect
        ref = ref[y0:y1, x0:x1]
    s = ldn.load(os.path.join(ldn.OURS, sheet + ".png"))
    h, w = ref.shape[:2]
    if s.shape[0] < h or s.shape[1] < w:
        print("%-28s %-22s sheet smaller than the capture" % (capture, sheet))
        return 0, 0
    r = cv2.matchTemplate(s.astype(np.float32), ref.astype(np.float32), cv2.TM_SQDIFF)
    best = None
    for _ in range(4):
        dy, dx = np.unravel_index(int(r.argmin()), r.shape)
        for ey in range(max(0, dy - 3), dy + 4):
            for ex in range(max(0, dx - 3), dx + 4):
                o = s[ey:ey + h, ex:ex + w]
                if o.shape[:2] != (h, w):
                    continue
                off = (np.abs(ref.astype(int) - o.astype(int)).max(axis=2) > 2)
                if best is None or off.sum() < best[0].sum():
                    best = (off, ex, ey, o)
        r[max(0, dy - 2):dy + 3, max(0, dx - 2):dx + 3] = np.inf
    off, dx, dy, o = best
    txt = ldn.text_zone(ref)
    st = int((off & ~txt).sum())
    tx = int((off & txt).sum())
    print("%-28s %-22s at %4d,%-4d px %6d  structure off %5d  text off %5d" % (capture, sheet, dx, dy, h * w, st, tx))
    d = os.environ.get("LOOKS_DIFF")
    if d:
        os.makedirs(d, exist_ok=True)
        red = o.copy()
        red[off & ~txt] = (255, 0, 0)
        red[off & txt] = (255, 160, 0)
        img = np.concatenate([ref, o, red], axis=1)
        Image.fromarray(img).resize((img.shape[1] * 3, img.shape[0] * 3), Image.NEAREST).save(os.path.join(d, capture + ".png"))
    ys, xs = np.where(off & ~txt)
    if len(xs):
        print("   structure off bbox x %d..%d y %d..%d" % (xs.min(), xs.max(), ys.min(), ys.max()))
    return st, tx


def main():
    for arg in sys.argv[1:]:
        rect = None
        if "@" in arg:
            arg, r = arg.split("@")
            rect = tuple(int(v) for v in r.split(","))
        cap, sheet = arg.split("=")
        run(cap, sheet, rect)


if __name__ == "__main__":
    main()
