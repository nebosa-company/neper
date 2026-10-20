"""Round 13: `python -I scripts/looks_nav_top.py` cuts the navigator button bitmaps of the live main window's top grid from the reference sheets
(data_grid_top: a current record, every button on; data_grid_hover: record 0, First / Previous page / Previous off) at the places our own render
puts the collection grid's bitmaps (gridlook.gx_nav_win, found by exact match in docs/ui/looks/windows/data_grid_top.png) and rewrites the generated
block `gx_nav_top_c` (the crisp cut; run it with LOOKS_REF=windows-1to1) of lib/e/ui/gridlook.e. The two grids' bitmaps differ by a few levels (the top grid's panel is one pixel line lighter)."""
import os
import re
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") + os.sep
LOOKS = ROOT + "docs/ui/looks/"
GL = ROOT + "lib/e/ui/gridlook.e"


def hexs(a):
    return "".join("%02X%02X%02X" % tuple(p) for p in a.reshape(-1, 3))


def old_bitmaps():
    text = open(GL, encoding="utf8").read()
    body = text[text.index("fn gx_nav_win(slot"):text.index("fn gx_nav_win_w(slot")]
    out = {}
    for m in re.finditer(r'if slot == (\d)usize && (!?)enabled \{ ret "([0-9A-F]+)" \}', body):
        out[(int(m.group(1)), m.group(2) == "")] = m.group(3)
    widths = {}
    wb = text[text.index("fn gx_nav_win_w(slot"):text.index("fn gx_nav_win_w_if")]
    for m in re.finditer(r"if slot == (\d)usize && (!?)enabled \{ ret (\d+)\.0 \}", wb):
        widths[(int(m.group(1)), m.group(2) == "")] = int(m.group(3))
    return out, widths


def arr(hexstr, w, h=23):
    v = [int(hexstr[i:i + 2], 16) for i in range(0, len(hexstr), 2)]
    return np.array(v).reshape(h, w, 3)


def find(ours, bmp, x0, x1, y0, y1):
    h, w, _ = bmp.shape
    best = None
    for y in range(y0, y1 - h + 1):
        for x in range(x0, x1 - w + 1):
            d = np.abs(ours[y:y + h, x:x + w] - bmp).sum()
            if best is None or d < best[0]:
                best = (d, x, y)
    return best


def main():
    old, widths = old_bitmaps()
    cuts = {}
    # (reference sheet, our render of it, which (slot, enabled) to cut from it)
    sources = [("data_grid_top", [(s, True) for s in range(6)] + [(7, True)]), ("data_grid_hover", [(s, False) for s in range(3)])]
    for sheet, wanted in sources:
        ref = np.array(Image.open(LOOKS + "ref/%s/%s.png" % (os.environ.get("LOOKS_REF", "windows"), sheet)).convert("RGB")).astype(int)
        ours = np.array(Image.open(LOOKS + "windows/%s.png" % sheet).convert("RGB")).astype(int)
        for key in wanted:
            if key not in old:
                continue
            w = widths[key]
            bmp = arr(old[key], w)
            d, x, y = find(ours, bmp, 12, 300, 205, 255)
            cuts[key] = (hexs(ref[y:y + 23, x:x + w]), d, x, y)
    lines = ["// BEGIN GENERATED_C (scripts/looks_nav_top.py)", "fn gx_nav_top_c(slot: usize, enabled: bool) -> str {"]
    for (slot, en), (hx, d, x, y) in sorted(cuts.items()):
        lines.append("    if slot == %dusize && %senabled { ret \"%s\" }" % (slot, "" if en else "!", hx))
    lines += ['    ret ""', "}", "// END GENERATED_C"]
    block = "\n".join(lines)
    text = open(GL, encoding="utf8").read()
    if "// BEGIN GENERATED_C" in text:
        text = re.sub(r"// BEGIN GENERATED_C.*?// END GENERATED_C", lambda m: block, text, flags=re.S)
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    open(GL, "w", encoding="utf8", newline="").write(text)
    for key, (hx, d, x, y) in sorted(cuts.items()):
        print(key, "found at", x, y, "match error", d)


if __name__ == "__main__":
    main()
