"""usage: python -I looks_offs.py <sheet> <cell index> [dir]: list struct-off pixels of one cell, grouped into rows and columns (cell-local coords)."""
import sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import looks_struct, looks_cells
n = sys.argv[1]; ci = int(sys.argv[2]); d = sys.argv[3] if len(sys.argv) > 3 else "windows"
R = looks_cells.ROOT
ref = np.array(Image.open(R + "ref/windows/%s.png" % n).convert("RGB"))
ours = np.array(Image.open(R + "%s/%s.png" % (d, n)).convert("RGB"))
b = looks_cells.cells(ref)[ci]
x0, y0, x1, y1 = b
sm = looks_struct.struct_mask(ref)[y0:y1, x0:x1] & looks_struct.struct_mask(ours)[y0:y1, x0:x1]
a = ref[y0:y1, x0:x1].astype(int); o = ours[y0:y1, x0:x1].astype(int)
bad = (np.abs(a - o).max(axis=2) > 2) & sm
print("cell", b, "bad", int(bad.sum()))
ys, xs = np.where(bad)
# rows with >= 20 bad px, columns with >= 12
rows = np.bincount(ys, minlength=bad.shape[0]); cols = np.bincount(xs, minlength=bad.shape[1])
print("rows:", [(int(y), int(rows[y])) for y in np.where(rows >= 12)[0]])
print("cols:", [(int(x), int(cols[x])) for x in np.where(cols >= 8)[0]])
rest = bad.copy()
rest[rows >= 12, :] = False
rest[:, cols >= 8] = False
print("scattered:", int(rest.sum()))
