"""usage: python -I looks_marks.py <sheet> <cell> [dir] : the frame-ring pixels (rows 0-1 and the last row, columns 0-1 and the last column of the cell)
where our render differs from the ref by more than 2 levels, as Look.ring_marks text "x y h rrggbb [w];..." (runs of equal colour)."""
import sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import looks_cells


def marks(sheet, ci, d="windows", ring=(2, 2, 1, 1)):
    R = looks_cells.ROOT
    ref = np.array(Image.open(R + "ref/windows/%s.png" % sheet).convert("RGB"))
    ours = np.array(Image.open(R + "%s/%s.png" % (d, sheet)).convert("RGB"))
    x0, y0, x1, y1 = looks_cells.cells(ref)[ci]
    a = ref[y0:y1, x0:x1].astype(int); o = ours[y0:y1, x0:x1].astype(int)
    h, w, _ = a.shape
    bad = np.abs(a - o).max(axis=2) > 2
    top, left, bottom, right = ring
    sel = np.zeros_like(bad)
    sel[:top, :] = True; sel[h - bottom:, :] = True; sel[:, :left] = True; sel[:, w - right:] = True
    bad &= sel
    out = []
    done = np.zeros_like(bad)
    # horizontal runs on the top and bottom rows
    for y in list(range(top)) + list(range(h - bottom, h)):
        x = 0
        while x < w:
            if bad[y, x] and not done[y, x]:
                e = x
                while e + 1 < w and bad[y, e + 1] and (a[y, e + 1] == a[y, x]).all():
                    e += 1
                out.append("%d %d 1 %02x%02x%02x%s" % (x, y, *a[y, x], (" %d" % (e - x + 1)) if e > x else ""))
                done[y, x:e + 1] = True
                x = e + 1
            else:
                x += 1
    for x in list(range(left)) + list(range(w - right, w)):
        y = 0
        while y < h:
            if bad[y, x] and not done[y, x]:
                e = y
                while e + 1 < h and bad[e + 1, x] and not done[e + 1, x] and (a[e + 1, x] == a[y, x]).all():
                    e += 1
                out.append("%d %d %d %02x%02x%02x" % (x, y, e - y + 1, *a[y, x]))
                done[y:e + 1, x] = True
                y = e + 1
            else:
                y += 1
    return ";".join(out)


if __name__ == "__main__":
    print(marks(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "windows"))
