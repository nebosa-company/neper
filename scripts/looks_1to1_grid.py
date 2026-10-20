"""Differences of a top grid sheet cell by region: `python -I scripts/looks_1to1_grid.py <sheet> [x0 y0]` (default: the left grid at 12, 32).

The grid's columns (indicator, star, picture, Name, Edition, Color, Type, Rarity, tail, bar) against its parts (header, rows, navigator),
pixels more than 2 levels off against the windows-1to1 reference sheet."""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402

os.environ["LOOKS_REF"] = "windows-1to1"
sheet = sys.argv[1]
x0 = int(sys.argv[2]) if len(sys.argv) > 2 else 12
y0 = int(sys.argv[3]) if len(sys.argv) > 3 else 32
ref = np.array(Image.open(lc.refpath(sheet)).convert("RGB")).astype(int)
ours = np.array(Image.open(os.environ.get("LOOKS_OURS", lc.ROOT + "windows") + "/%s.png" % sheet).convert("RGB")).astype(int)
d = np.abs(ref - ours).max(axis=2) > 2
cols = [("frame", 0, 1), ("ind", 1, 12), ("star", 12, 35), ("pic", 35, 56), ("Name", 56, 206), ("Edition", 206, 276), ("Color", 276, 336), ("Type", 336, 486), ("Rarity", 486, 536), ("tail", 536, 558), ("bar", 558, 576)]
parts = [("frame", 0, 1), ("header", 1, 23), ("rows", 23, 188), ("nav", 188, 212), ("frame", 212, 213)]
print("%-8s" % "" + "".join("%9s" % p[0] for p in parts))
for cname, ca, cb in cols:
    row = []
    for pname, pa, pb in parts:
        row.append(int(d[y0 + pa:y0 + pb, x0 + ca:x0 + cb].sum()))
    print("%-8s" % cname + "".join("%9d" % v for v in row))
print("total", int(d[y0:y0 + 213, x0:x0 + 576].sum()))
