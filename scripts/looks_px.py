"""usage: python -I looks_px.py <sheet> <cell> <x0> <y0> <x1> <y1> [dir]  prints hex ref / ours of cell-local pixels"""
import sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import looks_cells
n = sys.argv[1]; ci = int(sys.argv[2]); x0, y0, x1, y1 = [int(v) for v in sys.argv[3:7]]
d = sys.argv[7] if len(sys.argv) > 7 else "windows"
R = looks_cells.ROOT
ref = np.array(Image.open(R + "ref/windows/%s.png" % n).convert("RGB"))
ours = np.array(Image.open(R + "%s/%s.png" % (d, n)).convert("RGB"))
b = looks_cells.cells(ref)[ci]
for nm, im in (("ref", ref), ("our", ours)):
    print(nm)
    for y in range(y0, y1):
        print("%3d " % y + " ".join("%02x%02x%02x" % tuple(im[b[1] + y, b[0] + x]) for x in range(x0, x1)))
