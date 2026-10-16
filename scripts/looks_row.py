"""usage: python -I looks_row.py <sheet> <cell> <y> [x0 x1] [dir]  run-length of ref vs ours along cell-local row y (or col with 'c' prefix: c<x>)"""
import sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import looks_cells
n = sys.argv[1]; ci = int(sys.argv[2]); spec = sys.argv[3]
lo = int(sys.argv[4]) if len(sys.argv) > 4 else 0; hi = int(sys.argv[5]) if len(sys.argv) > 5 else 10000
d = sys.argv[6] if len(sys.argv) > 6 else "windows"
R = looks_cells.ROOT
ref = np.array(Image.open(R + "ref/windows/%s.png" % n).convert("RGB"))
ours = np.array(Image.open(R + "%s/%s.png" % (d, n)).convert("RGB"))
b = looks_cells.cells(ref)[ci]
col = spec[0] == 'c'
k = int(spec[1:] if col else spec)
for nm, im in (("ref", ref), ("our", ours)):
    cell = im[b[1]:b[3], b[0]:b[2]]
    line = cell[:, k] if col else cell[k]
    out = []; i = max(lo, 0); end = min(hi, len(line))
    while i < end:
        j = i
        while j + 1 < end and (line[j + 1] == line[i]).all(): j += 1
        out.append("%d-%d:%02x%02x%02x" % (i, j, *line[i]) if j > i else "%d:%02x%02x%02x" % (i, *line[i]))
        i = j + 1
    print(nm, " ".join(out))
