"""Round 13: `python -I scripts/looks_dialog_marks.py` rewrites the generated block of examples/looks/data_grid_dialog_states.e: for each cell of the
Shortcuts sheets the live capture's pixels of the grid frame's top row, the line under the header and the bottom row, as `Look.ring_marks`
text ("x y h rrggbb [w];...", runs of equal colour, grid relative). The hot header's tint, the column notches and the scroll bar's
edge pixels move along these rows with the pointer state, which a rule cannot yet draw."""
import os
import re
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells  # noqa: E402

SHEETS = ["data_grid_shortcuts_hover", "data_grid_shortcuts_hover2", "data_grid_shortcuts_hover3", "data_grid_shortcuts_hover4",
          "data_grid_shortcuts_states", "data_grid_shortcuts_states2", "data_grid_shortcuts_states3"]
ROWS = [1, 20]
SRC = os.path.join(HERE, "..", "examples", "looks", "data_grid_dialog_states.e")


def runs(ref, box, rows):
    x0, y0, x1, y1 = box
    out = []
    for y in rows:
        a = ref[y0 + y, x0:x1]
        # the row's commonest colour is what the grid draws itself: only the other runs are stamped
        cols, counts = np.unique(a[1:-1], axis=0, return_counts=True)
        base = cols[counts.argmax()]
        x = 1
        while x < len(a) - 1:
            e = x
            while e + 1 < len(a) - 1 and (a[e + 1] == a[x]).all():
                e += 1
            if not (a[x] == base).all():
                out.append("%d %d 1 %02x%02x%02x%s" % (x, y, *a[x], (" %d" % (e - x + 1)) if e > x else ""))
            x = e + 1
    return ";".join(out)


def main():
    body = ["// BEGIN GENERATED (scripts/looks_dialog_marks.py)", "fn dialog_marks(sheet: str, cell: usize) -> str {"]
    for s in SHEETS:
        ref = np.array(Image.open(looks_cells.ROOT + "ref/windows/%s.png" % s).convert("RGB"))
        boxes = [b for b in looks_cells.cells(ref) if b[2] - b[0] > 400]
        for c, b in enumerate(boxes):
            body.append('    if strs.eq(sheet, "%s") && cell == %dusize { ret "%s" }' % (s, c, runs(ref, b, ROWS)))
    body += ['    ret ""', "}", "// END GENERATED"]
    text = open(SRC, encoding="utf8").read()
    block = "\n".join(body)
    if "// BEGIN GENERATED" in text:
        text = re.sub(r"// BEGIN GENERATED.*?// END GENERATED", lambda m: block, text, flags=re.S)
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    open(SRC, "w", encoding="utf8", newline="").write(text)


if __name__ == "__main__":
    main()
