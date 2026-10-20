"""Where the chrome differences are: `python -I scripts/looks_1to1_where.py <sheet> [--ref windows-1to1] [--png out.png [scale]]`

Our render is placed in the reference sheet as looks_1to1_eval does; the pixels off by more than 2 levels and outside text boxes are grouped
by row band (runs of rows with more than 3 such pixels) and printed with their x extent and the largest difference; --png writes the
reference, ours and the mask side by side."""
import os
import sys
import numpy as np
import cv2
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
import looks_strict as ls  # noqa: E402


def main(sheet, png, scale):
    ref = np.array(Image.open(lc.refpath(sheet)).convert("RGB"))
    ours = np.array(Image.open(lc.ROOT + "windows/%s.png" % sheet).convert("RGB"))
    if ref.shape == ours.shape:
        o = ours
    else:
        _, dx, dy = ls.place(ref, ours)
        o = ours[dy:dy + ref.shape[0], dx:dx + ref.shape[1]]
    bg = lc.cellkey(ref, (0, 0, ref.shape[1], ref.shape[0]))
    d = np.abs(ref.astype(int) - o.astype(int)).max(axis=2)
    tb = ls.text_boxes(ref, bg) | ls.text_boxes(o, bg)
    ch = (d > 2) & ~tb
    rows = ch.sum(axis=1)
    y = 0
    H = len(rows)
    while y < H:
        if rows[y] > 3:
            e = y
            while e + 1 < H and rows[e + 1] > 3:
                e += 1
            xs = np.where(ch[y:e + 1].any(axis=0))[0]
            print("rows %4d-%4d  n %5d  x %4d-%4d  max %3d" % (y, e, int(ch[y:e + 1].sum()), xs.min(), xs.max(), int(d[y:e + 1][ch[y:e + 1]].max())))
            y = e + 1
        else:
            y += 1
    print("chrome total", int(ch.sum()), "counted", int((d > 2).sum()))
    if png:
        m = np.where(ch[..., None], np.array([255, 0, 0]), (o // 3 + 170)).astype(np.uint8)
        im = np.hstack([ref, o, m])[:, :, ::-1]
        cv2.imwrite(png, cv2.resize(np.ascontiguousarray(im), None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ref = "windows"
    if "--ref" in sys.argv:
        ref = sys.argv[sys.argv.index("--ref") + 1]
        args = [a for a in args if a != ref]
    os.environ["LOOKS_REF"] = ref
    png = None
    scale = 2
    if "--png" in sys.argv:
        i = sys.argv.index("--png")
        png = sys.argv[i + 1]
        args = [a for a in args if a != png]
        if i + 2 < len(sys.argv) and sys.argv[i + 2].isdigit():
            scale = int(sys.argv[i + 2])
            args = [a for a in args if a != sys.argv[i + 2]]
    main(args[0], png, scale)
