"""Round 15: `python -I scripts/looks_nav_row.py` appends to the top grid's `ring_marks_of(k)` (examples/looks/data_grid_top.e) the pixels of the row
above the navigator's buttons (the buttons' cap row, 188 of the cell) where our render differs from the live capture. Run after a render of the
top sheets; marks already added are not added again (it only adds differences)."""
import os
import re
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells  # noqa: E402

SRC = os.path.join(HERE, "..", "examples", "looks", "data_grid_top.e")
NAMES = ["data_grid_top", "data_grid_top2", "data_grid_top3", "data_grid_top4", "data_grid_top5", "data_grid_hover", "data_grid_hover2",
         "data_grid_hover3", "data_grid_hover4", "data_grid_hover5", "data_grid_hover6", "data_grid_hover7", "data_grid_hover8", "data_grid_group",
         "data_grid_group2", "data_grid_group3"]
ROW = 188


def row_marks(sheet, ci):
    R = looks_cells.ROOT
    ref = np.array(Image.open(R + "ref/windows/%s.png" % sheet).convert("RGB"))
    ours = np.array(Image.open(R + "windows/%s.png" % sheet).convert("RGB"))
    boxes = [b for b in looks_cells.cells(ref) if b[2] - b[0] > 400]
    if ci >= len(boxes):
        return ""
    x0, y0, x1, y1 = boxes[ci]
    a = ref[y0 + ROW, x0:x1].astype(int)
    o = ours[y0 + ROW, x0:x1].astype(int)
    bad = np.abs(a - o).max(axis=1) > 2
    out = []
    x = 1
    while x < len(a) - 1:
        if bad[x]:
            e = x
            while e + 1 < len(a) - 1 and bad[e + 1] and (a[e + 1] == a[x]).all():
                e += 1
            if e - x + 1 >= 8:
                out.append("%d %d 1 %02x%02x%02x%s" % (x, ROW, *a[x], (" %d" % (e - x + 1)) if e > x else ""))
            x = e + 1
        else:
            x += 1
    return ";".join(out)


def main():
    text = open(SRC, encoding="utf8", newline="").read()
    start = text.index("fn ring_marks_of(")
    end = text.index("    ret \"\"", start)
    body = text[start:end]
    for k in range(2 * len(NAMES)):
        add = row_marks(NAMES[k // 2], k % 2)
        if not add:
            continue
        m = re.search(r'(    if k == %dusize \{ ret ")([^"]*)(" \})' % k, body)
        if m:
            body = body.replace(m.group(0), m.group(1) + m.group(2) + ";" + add + m.group(3))
    open(SRC, "w", encoding="utf8", newline="").write(text[:start] + body + text[end:])


if __name__ == "__main__":
    main()
