"""Re-cuts the top grid's rarity pictures (examples/looks/data_grid_top.e: rarity_icon_c, _r, _u, 15 x 17 px) from the true 1:1 reference sheet
ref/windows-1to1/data_grid_hover.png: `python -I scripts/gen_gridpics.py`. The pictures sit in the Name column's neighbour at rows 0 (common, on the
selection), 1 (rare, white row) and 2 (uncommon, grey row); a pixel equal to its row's fill is written `ZZZZZZ` (transparent), so the picture takes the
row's own fill. The place is found where our render holds the old picture."""
import os
import re
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") + os.sep
E = ROOT + "examples/looks/data_grid_top.e"
text = open(E, encoding="utf8").read()


def old(name):
    m = re.search(r'fn rarity_icon_%s\(\) -> str \{ ret "([0-9A-FZ]+)" \}' % name, text)
    s = m.group(1)
    return s


ours = np.array(Image.open(ROOT + "docs/ui/looks/windows/data_grid_top.png").convert("RGB")).astype(int)
ref = np.array(Image.open(ROOT + "docs/ui/looks/ref/windows-1to1/data_grid_hover.png").convert("RGB")).astype(int)
# where our render draws the uncommon picture: the pixels of the old string that are not transparent, matched at x 40..70, rows around 2 (y 93..111)
u = old("u")
px = np.array([[int(u[i + k:i + k + 2], 16) if u[i] != "Z" else -1 for k in (0, 2, 4)] for i in range(0, len(u), 6)]).reshape(17, 15, 3)
mask = px[:, :, 0] >= 0
best = None
for y in range(80, 125):
    for x in range(40, 70):
        d = np.abs(ours[y:y + 17, x:x + 15] - px)[mask].sum()
        if best is None or d < best[0]:
            best = (d, x, y)
print("found at", best)
_, x, y0 = best
fills = {0: (0xA6, 0xD2, 0xFF), 1: (0xFF, 0xFF, 0xFF), 2: (0xEF, 0xEF, 0xEF)}
rows = {"c": 0, "r": 1, "u": 2}
for name, row in rows.items():
    y = y0 + (row - 2) * 19
    cut = ref[y:y + 17, x:x + 15]
    out = []
    for yy in range(17):
        for xx in range(15):
            p = tuple(cut[yy, xx])
            out.append("ZZZZZZ" if p == fills[row] else "%02X%02X%02X" % p)
    s = "".join(out)
    text = re.sub(r'(fn rarity_icon_%s\(\) -> str \{ ret ")[0-9A-FZ]+(" \})' % name, lambda m: m.group(1) + s + m.group(2), text)
open(E, "w", encoding="utf8", newline="").write(text)
