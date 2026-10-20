"""Best (dx, dy) of our text against the reference, region by region: `python -I scripts/looks_shift.py <sheet> x0,y0,x1,y1 [...]`
(reference coordinates; our sheet is placed first like looks_1to1_eval). Prints, per region, the number of pixels off by more than 2 levels
at every shift from -2 to 2 in x and y, best first, and the figure at no shift."""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
import looks_strict as ls  # noqa: E402


def main(sheet, boxes):
    ref = np.array(Image.open(lc.refpath(sheet)).convert("RGB")).astype(int)
    ours = np.array(Image.open(lc.ROOT + "windows/%s.png" % sheet).convert("RGB")).astype(int)
    if ref.shape == ours.shape:
        ox = oy = 0
    else:
        f = ls.place(ref.astype(np.uint8), ours.astype(np.uint8))
        _, ox, oy = f
    for b in boxes:
        x0, y0, x1, y1 = b
        a = ref[y0:y1, x0:x1]
        res = []
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                o = ours[oy + y0 + dy:oy + y1 + dy, ox + x0 + dx:ox + x1 + dx]
                res.append((int((np.abs(a - o).max(axis=2) > 2).sum()), dx, dy))
        zero = [r for r in res if r[1] == 0 and r[2] == 0][0]
        res.sort()
        print("%s  none %d  best %s" % (b, zero[0], res[:3]))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--ref" in sys.argv:
        i = sys.argv.index("--ref")
        os.environ["LOOKS_REF"] = sys.argv[i + 1]
        args = [a for a in args if a != sys.argv[i + 1]]
    main(args[0], [tuple(int(v) for v in a.split(",")) for a in args[1:]])
