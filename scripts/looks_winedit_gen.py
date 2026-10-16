"""Generates lib/e/ui/winedit.e's tables from the live v3 captures (docs/ui/looks/ref/windows/states).

`python -I scripts/looks_winedit_gen.py` rewrites the GENERATED block of lib/e/ui/winedit.e.

What the captures show (100 %, Windows 11 native edit, v3 is DPI unaware):
- An edit of DFM size W x 21 draws a frame of (W + 1) x 22 pixels. Its inner rows 2..18 are white; the rim
  columns are constant, but the top two rows and the three foot rows are anti-aliased and drift LINEARLY with the
  control's y in the window (rest: row 20 is 179 at y = 89 and 206 at y = 385, row 21 the mirror, the pair summing
  to ~377; focus: the 2 px accent line moves the same way), so the foot "varies between instances" only because
  the instances sit at different y. Each row's colour is therefore a + b * y per channel (`models`).
- Tiles hold the left rim (3 columns) and the right end (the rim, plus the ellipsis button or the spin buttons)
  as captured, rows 0..21; a cell of 0 is not painted (the face shows); rows 0, 1, 19, 20, 21 are re-based on the
  model at the drawn y (tile value + model(y) - model(y of the capture)).
"""
import re
import numpy as np
from PIL import Image

import os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") + os.sep
R = ROOT + "docs/ui/looks/ref/windows/states/"
OUT = ROOT + "lib/e/ui/winedit.e"
SPECIAL = [0, 1, 19, 20, 21]
H = 22


def load(n):
    return np.array(Image.open(R + n + "@1x.png").convert("RGB")).astype(int)


# (capture, x, y, w) of every plain-frame instance per state; the model of a row is fitted over them.
REST = [("dialog-options-passwords-rest", 215, 89, 495), ("dialog-options-passwords-rest", 215, 144, 495),
        ("dialog-options-passwords-rest", 215, 198, 495), ("dialog-options-decks-rest", 215, 94, 495),
        ("dialog-options-decks-rest", 215, 159, 121), ("dialog-options-morph-rest", 406, 105, 67),
        ("dialog-options-morph-rest", 406, 169, 67), ("dialog-options-cardart-rest", 215, 385, 464)]
FOCUS = [("edit-focused-options-old-password", 215, 89, 495), ("edit-focused-options-new-password", 215, 144, 495),
         ("edit-focused-options-deck-path", 215, 94, 495), ("spin-edit-focused-options-max-same-cards", 215, 159, 121),
         ("spin-edit-focused-options-morph-speed", 406, 105, 67)]
DISABLED = [("edit-button-ellipsis-pressed-options-cardart", 215, 385, 464)]
STATES = [REST, FOCUS, DISABLED]

# Tile sources per (kind, state): capture, x, y, w, columns taken from the right end.
# kinds: 0 plain, 1 spin with fast buttons, 2 spin (stacked arrows), 3 button edit (ellipsis)
RIGHT_K = {0: 5, 1: 49, 2: 19, 3: 20}
SRC = {
    (0, 0): ("dialog-options-passwords-rest", 215, 144, 495),
    (0, 1): ("edit-focused-options-new-password", 215, 144, 495),
    (1, 0): ("dialog-options-decks-rest", 215, 159, 121),
    (1, 1): ("spin-edit-focused-options-max-same-cards", 215, 159, 121),
    (2, 0): ("dialog-options-morph-rest", 406, 105, 67),
    (2, 1): ("spin-edit-focused-options-morph-speed", 406, 105, 67),
    (3, 0): ("dialog-options-decks-rest", 215, 94, 495),
    (3, 1): ("edit-focused-options-deck-path", 215, 94, 495),
    (3, 2): ("edit-button-ellipsis-pressed-options-cardart", 215, 385, 464),
    (3, 3): ("edit-button-ellipsis-pressed-options-deck-path", 215, 94, 495),
    (0, 2): ("edit-button-ellipsis-pressed-options-cardart", 215, 385, 464),
}
LEFT_K = 3
# More instances of a tile, to fit each cell's drift with y (the first is SRC's).
EXTRA = {
    (0, 0): [("dialog-options-passwords-rest", 215, 89, 495), ("dialog-options-passwords-rest", 215, 198, 495)],
    (0, 1): [("edit-focused-options-old-password", 215, 89, 495)],
    (2, 0): [("dialog-options-morph-rest", 406, 169, 67)],
    (3, 0): [("dialog-options-cardart-rest", 215, 385, 464)],
}


def models():
    out = []
    for st in STATES:
        rows = []
        for r in SPECIAL:
            chans = []
            for ch in range(3):
                ys = []
                vs = []
                for (n, x, y, w) in st:
                    a = load(n)
                    ys.append(y)
                    vs.append(a[y + r, x + 30, ch])
                if len(set(ys)) > 1:
                    b, a0 = np.polyfit(np.array(ys, float), np.array(vs, float), 1)
                else:
                    b, a0 = 0.0, float(vs[0])
                chans.append((a0, b))
            rows.append(chans)
        out.append(rows)
    return out


def model_at(m, state, row_i, ch, y):
    a0, b = m[state][row_i][ch]
    return int(round(min(255.0, max(0.0, a0 + b * y))))


def tile(n, x, y, cols, right, w, plain_rim=False):
    a = load(n)
    x0 = x + (w + 1 - cols if right else 0)
    cells = []
    for r in range(H):
        for c in range(cols):
            p = a[y + r, x0 + c]
            if plain_rim and c < cols - 2:
                # a button edit's capture: keep only the rim (the last two columns), the mid rows elsewhere
                p = a[y + r, x0 - 1] if r in SPECIAL else np.array([255, 255, 255])
            white = (p[0] == 255 and p[1] == 255 and p[2] == 255)
            if 2 <= r <= 18 and white:
                cells.append(0)
            else:
                cells.append(0xFF000000 | (int(p[0]) << 16) | (int(p[1]) << 8) | int(p[2]))
    return cells


def slopes(insts, cols, right, plain_rim=False):
    """Per cell and channel, the drift per px of y fitted over the instances (empty for a single instance)."""
    if len(insts) < 2:
        return []
    ys = np.array([i[2] for i in insts], float)
    vals = []
    for (n, x, y, w) in insts:
        a = load(n)
        x0 = x + (w + 1 - cols if right else 0)
        vals.append(a[y:y + H, x0:x0 + cols, :])
    vals = np.array(vals, float)
    out = []
    for r in range(H):
        for c in range(cols):
            for ch in range(3):
                out.append(float(np.polyfit(ys, vals[:, r, c, ch], 1)[0]))
    return out


def arrows(cells, cols, face):
    """Dark components (ink < 200 in the button interior rows 3..17) as x, y, w, h boxes."""
    ink = set()
    for r in range(3, 18):
        for c in range(cols):
            v = cells[r * cols + c]
            if v and ((v >> 16) & 255) < 200 and ((v >> 8) & 255) < 200:
                ink.add((c, r))
    boxes = []
    seen = set()
    for p in sorted(ink):
        if p in seen:
            continue
        stack = [p]
        seen.add(p)
        pts = []
        while stack:
            q = stack.pop()
            pts.append(q)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                s = (q[0] + d[0], q[1] + d[1])
                if s in ink and s not in seen:
                    seen.add(s)
                    stack.append(s)
        xs = [t[0] for t in pts]
        ys = [t[1] for t in pts]
        boxes.append((min(xs) - 1, min(ys) - 1, max(xs) - min(xs) + 3, max(ys) - min(ys) + 3))
    return boxes


def fmt_u32(vals):
    return ", ".join("0u32" if v == 0 else "0x%08Xu32" % v for v in vals)


ARR = {}
SLOPED = set()
LSLOPED = set()


def main():
    m = models()
    lines = []
    flat = []
    for st in range(3):
        for ri in range(5):
            for ch in range(3):
                flat.extend(m[st][ri][ch])
    lines.append("// models: state (rest, focus, disabled) x row (0, 1, 19, 20, 21) x channel (r, g, b) x (a, b): value = a + b * y")
    lines.append("fn wedit_models() -> [90]f32 { ret [90]f32{ %s } }" % ", ".join("%.5f" % v for v in flat))
    for (kind, state), (n, x, y, w) in sorted(SRC.items()):
        k = RIGHT_K[kind]
        cells = tile(n, x, y, k, True, w, kind == 0 and state == 2)
        lines.append("// kind %d state %d: %s at (%d, %d), width %d; last %d columns, 22 rows; capture y = %d" % (kind, state, n, x, y, w, k, y))
        lines.append("fn wedit_right_%d_%d() -> [%d]u32 { ret [%d]u32{ %s } }" % (kind, state, k * H, k * H, fmt_u32(cells)))
        lines.append("fn wedit_right_%d_%d_y() -> f32 { ret %d.0 }" % (kind, state, y))
        sl = slopes([SRC[(kind, state)]] + EXTRA.get((kind, state), []), k, True) if (kind, state) in EXTRA else []
        if sl:
            SLOPED.add((kind, state))
            lines.append("fn wedit_slope_%d_%d() -> [%d]f32 { ret [%d]f32{ %s } }" % (kind, state, len(sl), len(sl), ", ".join("%.4f" % v for v in sl)))
        if kind in (1, 2) and state == 0:
            bx = arrows(cells, k, 250)
            flatb = [v for b in bx for v in b]
            lines.append("// arrow boxes (x, y, w, h in tile columns / rows), left to right: %s" % bx)
            lines.append("fn wedit_arrows_%d() -> [%d]u32 { ret [%d]u32{ %s } }" % (kind, len(flatb), len(flatb), ", ".join("%du32" % v for v in flatb)))
            ARR[kind] = len(flatb)
    for state in (0, 1, 2):
        src = (0, state)
        n, x, y, w = SRC[src]
        cells = tile(n, x, y, LEFT_K, False, w)
        lines.append("// left rim, state %d: %s" % (state, n))
        lines.append("fn wedit_left_%d() -> [%d]u32 { ret [%d]u32{ %s } }" % (state, LEFT_K * H, LEFT_K * H, fmt_u32(cells)))
        lines.append("fn wedit_left_%d_y() -> f32 { ret %d.0 }" % (state, y))
        sl = slopes(STATES[state], LEFT_K, False)
        if sl:
            LSLOPED.add(state)
            lines.append("fn wedit_left_slope_%d() -> [%d]f32 { ret [%d]f32{ %s } }" % (state, len(sl), len(sl), ", ".join("%.4f" % v for v in sl)))
    # The morph spin edits stand at x = 406 where the left rim column 1 is 3 levels darker than at x = 215: their own tiles.
    for state, (n, x, y, w) in ((0, ("dialog-options-morph-rest", 406, 105, 67)), (1, ("spin-edit-focused-options-morph-speed", 406, 105, 67))):
        cells = tile(n, x, y, LEFT_K, False, w)
        lines.append("// left rim of the morph spin edits, state %d: %s" % (state, n))
        lines.append("fn wedit_left2_%d() -> [%d]u32 { ret [%d]u32{ %s } }" % (state, LEFT_K * H, LEFT_K * H, fmt_u32(cells)))
        lines.append("fn wedit_left2_%d_y() -> f32 { ret %d.0 }" % (state, y))
    lines.append("fn wedit_left2(state: u32, out: []u32) -> f32 {")
    for state in (0, 1):
        lines.append("    if state == %du32 {" % state)
        lines.append("        let t = wedit_left2_%d()" % state)
        lines.append("        var i = 0usize")
        lines.append("        while i < %dusize {\n            out[i] = t[i]\n            i += 1usize\n        }" % (LEFT_K * H))
        lines.append("        ret wedit_left2_%d_y()" % state)
        lines.append("    }")
    lines.append("    ret 0.0")
    lines.append("}")
    lines.append("// the right end of kind `kind` in `state` copied into `out` (K columns x 22 rows, row-major): answers K * 22 and the capture's y")
    lines.append("fn wedit_right(kind: u32, state: u32, out: []u32) -> (usize, f32) {")
    for (kind, state), (n, x, y, w) in sorted(SRC.items()):
        k = RIGHT_K[kind] * H
        lines.append("    if kind == %du32 && state == %du32 {" % (kind, state))
        lines.append("        let t = wedit_right_%d_%d()" % (kind, state))
        lines.append("        var i = 0usize")
        lines.append("        while i < %dusize {\n            out[i] = t[i]\n            i += 1usize\n        }" % k)
        lines.append("        ret (%dusize, wedit_right_%d_%d_y())" % (k, kind, state))
        lines.append("    }")
    lines.append("    ret (0usize, 0.0)")
    lines.append("}")
    lines.append("fn wedit_arrows(kind: u32, out: []u32) -> usize {")
    for kind, n in sorted(ARR.items()):
        lines.append("    if kind == %du32 {" % kind)
        lines.append("        let t = wedit_arrows_%d()" % kind)
        lines.append("        var i = 0usize")
        lines.append("        while i < %dusize {\n            out[i] = t[i]\n            i += 1usize\n        }" % n)
        lines.append("        ret %dusize" % n)
        lines.append("    }")
    lines.append("    ret 0usize")
    lines.append("}")
    lines.append("fn wedit_left(state: u32, out: []u32) -> f32 {")
    for state in (0, 1, 2):
        lines.append("    if state == %du32 {" % state)
        lines.append("        let t = wedit_left_%d()" % state)
        lines.append("        var i = 0usize")
        lines.append("        while i < %dusize {\n            out[i] = t[i]\n            i += 1usize\n        }" % (LEFT_K * H))
        lines.append("        ret wedit_left_%d_y()" % state)
        lines.append("    }")
    lines.append("    ret 0.0")
    lines.append("}")
    lines.append("// the per-cell drift per px of y of a right tile (false: none, the foot rows follow the models)")
    lines.append("fn wedit_slopes(kind: u32, state: u32, out: []f32) -> bool {")
    for (kind, state) in sorted(SLOPED):
        k = RIGHT_K[kind] * H * 3
        lines.append("    if kind == %du32 && state == %du32 {" % (kind, state))
        lines.append("        let t = wedit_slope_%d_%d()" % (kind, state))
        lines.append("        var i = 0usize")
        lines.append("        while i < %dusize {" % k)
        lines.append("            out[i] = t[i]")
        lines.append("            i += 1usize")
        lines.append("        }")
        lines.append("        ret true")
        lines.append("    }")
    lines.append("    ret false")
    lines.append("}")
    lines.append("fn wedit_left_slopes(state: u32, out: []f32) -> bool {")
    for state in sorted(LSLOPED):
        lines.append("    if state == %du32 {" % state)
        lines.append("        let t = wedit_left_slope_%d()" % state)
        lines.append("        var i = 0usize")
        lines.append("        while i < %dusize {" % (LEFT_K * H * 3))
        lines.append("            out[i] = t[i]")
        lines.append("            i += 1usize")
        lines.append("        }")
        lines.append("        ret true")
        lines.append("    }")
    lines.append("    ret false")
    lines.append("}")
    block = "\n".join(lines)
    src = open(OUT, encoding="utf-8").read()
    start = src.index("// ---- GENERATED")
    end = src.index("// ---- END GENERATED")
    src = src[:start] + "// ---- GENERATED by scripts/looks_winedit_gen.py (do not edit) ----\n" + block + "\n" + src[end:]
    open(OUT, "w", encoding="utf-8", newline="\n").write(src)
    print("tiles", len(SRC), "arrows", {k: arrows(tile(*SRC[(k, 0)][:3], RIGHT_K[k], True, SRC[(k, 0)][3]), RIGHT_K[k], 250) for k in (1, 2)})


main()
