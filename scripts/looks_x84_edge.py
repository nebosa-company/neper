"""`python -I scripts/looks_x84_edge.py capture.png sheet.png x0,y0,x1,y1 [bg]` (round 84, lane x): compares the frame of a native edit capture with the frame
of one field of a sheet. Both images are cut to the tight box of their pixels that differ from the background `bg` (default #F0F0F0) inside the given search
window (the capture is searched whole), then the 6 x 6 corners, the 40 px of the top and bottom edge from the left, the 40 px from the right and the left and
right edge columns (the middle 8 rows) are compared pixel by pixel. Prints the box sizes and the largest and the count of levels off (more than 2) per part."""
import sys
import numpy as np
from PIL import Image


def box(a, win, bg):
    x0, y0, x1, y1 = win
    sub = a[y0:y1, x0:x1]
    m = (np.abs(sub - np.array(bg)).max(axis=2) > 2)
    ys, xs = np.nonzero(m)
    return xs.min() + x0, ys.min() + y0, xs.max() + x0 + 1, ys.max() + y0 + 1


def parts(a, bx):
    x0, y0, x1, y1 = bx
    w, h = x1 - x0, y1 - y0
    P = {}
    P["tl"] = a[y0:y0 + 6, x0:x0 + 6]
    P["tr"] = a[y0:y0 + 6, x1 - 6:x1]
    P["bl"] = a[y1 - 6:y1, x0:x0 + 6]
    P["br"] = a[y1 - 6:y1, x1 - 6:x1]
    P["top"] = a[y0:y0 + 3, x0 + 6:x0 + 40]
    P["bot"] = a[y1 - 3:y1, x0 + 6:x0 + 40]
    P["left"] = a[y0 + h // 2 - 4:y0 + h // 2 + 4, x0:x0 + 3]
    P["right"] = a[y0 + h // 2 - 4:y0 + h // 2 + 4, x1 - 3:x1]
    return P


if __name__ == "__main__":
    cap = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(int)
    sh = np.array(Image.open(sys.argv[2]).convert("RGB")).astype(int)
    win = tuple(int(v) for v in sys.argv[3].split(","))
    bg = (240, 240, 240)
    if len(sys.argv) > 4:
        bg = tuple(int(v) for v in sys.argv[4].split(","))
    cb = box(cap, (0, 0, cap.shape[1], cap.shape[0]), bg)
    sb = box(sh, win, bg)
    print("capture box %s (%dx%d)  sheet box %s (%dx%d)" % (cb, cb[2] - cb[0], cb[3] - cb[1], sb, sb[2] - sb[0], sb[3] - sb[1]))
    pc, ps = parts(cap, cb), parts(sh, sb)
    out = []
    for k in pc:
        if pc[k].shape != ps[k].shape:
            out.append("%s shape" % k)
            continue
        d = np.abs(pc[k] - ps[k]).max(axis=2)
        out.append("%s max %d off %d" % (k, d.max(), int((d > 2).sum())))
    print("  ".join(out))
