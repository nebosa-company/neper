"""Re-cuts small grid bitmaps of lib/e/ui/gridlook.e (gx_list, gx_star, gx_row_arrow, ...) from the true 1:1 reference sheet:
`python -I scripts/gen_gridglyphs.py <sheet> <fn> [<fn> ...]`   e.g. data_grid_hover gx_list gx_star gx_row_arrow

The bitmap is found in our render of the sheet (docs/ui/looks/windows/<sheet>.png) by the smallest sum of differences over the left grid, the same
rectangle of ref/windows-1to1/<sheet>.png replaces its pixel string. Our render has the old bitmap exactly where the capture has the glyph (looks_1to1_grid.py
shows the placement is right), so the cut is the crisp glyph."""
import os
import re
import sys
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") + os.sep
GL = ROOT + "lib/e/ui/gridlook.e"
sheet = sys.argv[1]
text = open(GL, encoding="utf8").read()
ours = np.array(Image.open(ROOT + "docs/ui/looks/windows/%s.png" % sheet).convert("RGB")).astype(int)
ref = np.array(Image.open(ROOT + "docs/ui/looks/ref/windows-1to1/%s.png" % sheet).convert("RGB")).astype(int)
for fn in sys.argv[2:]:
    m = re.search(r'fn %s\(\) -> str \{ ret "([0-9A-F]+)" \}' % fn, text)
    w = int(float(re.search(r"fn %s_w\(\) -> f32 \{ ret ([0-9.]+) \}" % fn, text).group(1)))
    h = int(float(re.search(r"fn %s_h\(\) -> f32 \{ ret ([0-9.]+) \}" % fn, text).group(1)))
    s = m.group(1)
    bmp = np.array([int(s[i:i + 2], 16) for i in range(0, len(s), 2)]).reshape(h, w, 3)
    best = None
    for y in range(30, 250 - h):
        for x in range(10, 590 - w):
            d = np.abs(ours[y:y + h, x:x + w] - bmp).sum()
            if best is None or d < best[0]:
                best = (d, x, y)
    d, x, y = best
    cut = ref[y:y + h, x:x + w]
    new = "".join("%02X%02X%02X" % tuple(p) for p in cut.reshape(-1, 3))
    print(fn, "at", x, y, "old error", d)
    text = text.replace('fn %s() -> str { ret "%s" }' % (fn, s), 'fn %s() -> str { ret "%s" }' % (fn, new), 1)
open(GL, "w", encoding="utf8", newline="").write(text)
