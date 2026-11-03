"""`python -I scripts/looks_x84_place.py capture.png sheet.png [anchor R,G,B]` (round 84, lane x): places a whole capture in a sheet at the whole-pixel
offset with the fewest differing pixels and prints that count, the count outside the text (pixels more than 2 px from a pixel whose colour
is outside the capture's two most frequent colours' band is not used: every differing pixel is counted), and the bounding box of the
differences. A pixel differs when any channel is off by more than 2 levels. The anchor colour (default: the capture's first pixel that is
not its most frequent colour) limits the candidate offsets to the sheet pixels of that colour."""
import sys
from collections import Counter
import numpy as np
from PIL import Image


def main(cap_path, sheet_path, anchor=None):
    cap = np.array(Image.open(cap_path).convert("RGB")).astype(int)
    sh = np.array(Image.open(sheet_path).convert("RGB")).astype(int)
    h, w = cap.shape[:2]
    flat = [tuple(p) for p in cap.reshape(-1, 3)]
    common = Counter(flat).most_common(1)[0][0]
    if anchor is None:
        for i, p in enumerate(flat):
            if p != common:
                anchor = p
                ay, ax = divmod(i, w)
                break
    else:
        ay, ax = next(divmod(i, w) for i, p in enumerate(flat) if p == anchor)
    ys, xs = np.nonzero((sh == np.array(anchor)).all(axis=2))
    best = None
    for y, x in zip(ys, xs):
        oy, ox = y - ay, x - ax
        if oy < 0 or ox < 0 or oy + h > sh.shape[0] or ox + w > sh.shape[1]:
            continue
        d = (np.abs(sh[oy:oy + h, ox:ox + w] - cap).max(axis=2) > 2)
        n = int(d.sum())
        if best is None or n < best[0]:
            best = (n, ox, oy, d)
    if best is None:
        print("no placement")
        return
    n, ox, oy, d = best
    yy, xx = np.nonzero(d)
    box = (int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max())) if n else None
    print("placed at %d,%d of %dx%d: %d px differ, box %s" % (ox, oy, w, h, n, box))


if __name__ == "__main__":
    a = None
    if len(sys.argv) > 3:
        a = tuple(int(v) for v in sys.argv[3].split(","))
    main(sys.argv[1], sys.argv[2], a)
