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

# sheet -> (rows of the cell to stamp, smallest cell width): the Shortcuts grids (family 1), the Sort dialog's (family 0) and the Missing list (family 2)
SHEETS = {"data_grid_shortcuts_hover": ([1, 20], 400), "data_grid_shortcuts_hover2": ([1, 20], 400), "data_grid_shortcuts_hover3": ([1, 20], 400),
          "data_grid_shortcuts_hover4": ([1, 20], 400), "data_grid_shortcuts_states": ([1, 20], 400), "data_grid_shortcuts_states2": ([1, 20], 400),
          "data_grid_shortcuts_states3": ([1, 20], 400), "data_grid_sort_states": ([1, 20], 300), "data_grid_sort_hover": ([1, 20], 300),
          "data_grid_missing_states": ([1, 255], 200), "data_grid_missing_hover": ([1, 255], 200)}
SRC = os.path.join(HERE, "..", "examples", "looks", "data_grid_dialog_states.e")


def cols(ref, box, xs, first_row=21):
    """round 15: the pixels of the Shortcuts grid's frame columns that differ from the column's commonest colour (grey rows
    have their own edge pixels), below the header."""
    x0, y0, x1, y1 = box
    out = []
    for x in xs:
        c = ref[y0 + first_row:y1 - 2, x0 + x]
        vals, counts = np.unique(c, axis=0, return_counts=True)
        base = vals[counts.argmax()]
        y = first_row
        while y < y1 - y0 - 2:
            p = ref[y0 + y, x0 + x]
            e = y
            while e + 1 < y1 - y0 - 2 and (ref[y0 + e + 1, x0 + x] == p).all():
                e += 1
            out.append("%d %d %d %02x%02x%02x" % (x, y, e - y + 1, *p))
            y = e + 1
    return ";".join(out)


def runs(ref, box, rows, keep=(), full=()):
    x0, y0, x1, y1 = box
    out = []
    for y in rows:
        a = ref[y0 + y, x0:x1]
        if y in full:
            # round 15: a frame row's two corner pixels (the rest of the row the grid draws itself)
            for x in (0, len(a) - 1):
                out.append("%d %d 1 %02x%02x%02x" % (x, y, *a[x]))
            continue
        # the row's commonest colour is what the grid draws itself: only the other runs are stamped
        cols, counts = np.unique(a[1:-1], axis=0, return_counts=True)
        base = cols[counts.argmax()]
        x = 1
        while x < len(a) - 1:
            e = x
            while e + 1 < len(a) - 1 and (a[e + 1] == a[x]).all():
                e += 1
            if y in keep or not (a[x] == base).all():
                out.append("%d %d 1 %02x%02x%02x%s" % (x, y, *a[x], (" %d" % (e - x + 1)) if e > x else ""))
            x = e + 1
    return ";".join(out)


BOTTOM = {"sheets": ["data_grid_bottom", "data_grid_bottom2", "data_grid_bottom3"], "rows": [0, 1, 20, 217, 241],
          "src": os.path.join(HERE, "..", "examples", "looks", "data_grid_bottom.e")}


def bottom_block():
    body = ["// BEGIN GENERATED (scripts/looks_dialog_marks.py)", "fn bottom_marks(k: usize) -> str {"]
    k = 0
    for s in BOTTOM["sheets"]:
        ref = np.array(Image.open(looks_cells.ROOT + "ref/windows/%s.png" % s).convert("RGB"))
        for b in [b for b in looks_cells.cells(ref) if b[2] - b[0] > 400]:
            body.append('    if k == %dusize { ret "%s" }' % (k, runs(ref, b, BOTTOM["rows"])))
            k += 1
    body += ['    ret ""', "}", "// END GENERATED"]
    return "\n".join(body)


def main():
    body = ["// BEGIN GENERATED (scripts/looks_dialog_marks.py)", "fn dialog_marks(sheet: str, cell: usize) -> str {"]
    for s, (rows, minw) in SHEETS.items():
        ref = np.array(Image.open(looks_cells.ROOT + "ref/windows/%s.png" % s).convert("RGB"))
        boxes = [b for b in looks_cells.cells(ref) if b[2] - b[0] > minw]
        for c, b in enumerate(boxes):
            # the Missing list's and the Sort grid's rows are stamped whole: their commonest run is not always what the grid draws
            keep = (1, 20) if "sort" in s else ((255,) if "missing" in s else ())
            # round 15: the Sort grid's whole frame top row and foot row, corners included
            full = (0, b[3] - b[1] - 1) if "sort" in s else ()
            extra = ""
            if "shortcuts" in s:
                extra = ";" + cols(ref, b, (b[2] - b[0] - 18,))
            body.append('    if strs.eq(sheet, "%s") && cell == %dusize { ret "%s%s" }' % (s, c, runs(ref, b, sorted(set(list(rows) + list(full))), keep, full), extra))
    body += ['    ret ""', "}", "// END GENERATED"]
    text = open(SRC, encoding="utf8").read()
    block = "\n".join(body)
    if "// BEGIN GENERATED" in text:
        text = re.sub(r"// BEGIN GENERATED.*?// END GENERATED", lambda m: block, text, flags=re.S)
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    open(SRC, "w", encoding="utf8", newline="").write(text)
    text = open(BOTTOM["src"], encoding="utf8").read()
    block = bottom_block()
    if "// BEGIN GENERATED" in text:
        text = re.sub(r"// BEGIN GENERATED.*?// END GENERATED", lambda m: block, text, flags=re.S)
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    open(BOTTOM["src"], "w", encoding="utf8", newline="").write(text)


if __name__ == "__main__":
    main()
