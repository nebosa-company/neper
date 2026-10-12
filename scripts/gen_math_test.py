"""Reference geometry for the text_math fixture (L098, D2842).

Glyph advances and bounding boxes come from the same font file read with fontTools
(hmtx, cmap, glyf); the layout rules are the TeXbook's (Appendix G rules 11, 15, 18)
and the inter-atom space table, written here as direct formulas for each expression
rather than as a general engine, so the numbers do not come from the library's code.
Prints the Neper constants for tests/selfhost/fixtures/link/text_math.

    python scripts/gen_math_test.py [path/to/font.ttf]
"""
import sys
from fontTools.ttLib import TTFont

PATH = sys.argv[1] if len(sys.argv) > 1 else "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf"
font = TTFont(PATH)
cmap = font.getBestCmap()
hmtx = font["hmtx"]
glyf = font["glyf"]
upem = font["head"].unitsPerEm
SIZE = 20.0


def adv(ch, size=SIZE):
    return hmtx[cmap[ord(ch)]][0] / upem * size


def box(ch, size=SIZE):
    g = glyf[cmap[ord(ch)]]
    if not hasattr(g, "yMax") or g.numberOfContours == 0:
        return 0.0, 0.0
    return g.yMin / upem * size, g.yMax / upem * size


def gid(ch):
    return font.getGlyphID(cmap[ord(ch)])


AXIS, THETA = 0.25 * SIZE, 0.04 * SIZE
XH = box("x", 1.0)[1]
S7 = 0.7 * SIZE


def out(name, **kv):
    print("//", name)
    for k, v in kv.items():
        print("    %s = %.4f" % (k, v))


# 1. "ab" -- two ordinary atoms, no space.
out("ab", width=adv("a") + adv("b"), ascent=max(box("a")[1], box("b")[1]), descent=max(-box("a")[0], -box("b")[0], 0), second_x=adv("a"))

# 2. "a+b" in text style: the binary operator takes a medium space (4/18 em) each side.
m = 4.0 / 18.0 * SIZE
out("a+b", width=adv("a") + m + adv("+") + m + adv("b"), plus_x=adv("a") + m, b_x=adv("a") + 2 * m + adv("+"), plus_glyph=gid("+"))

# 3. "x^2": nucleus is a single character so the drop terms are zero; shift is the
# maximum of sigma13 (0.363 em, text, uncramped) and depth(sup) + |x-height| / 4.
sup_depth = max(-box("2", S7)[0], 0.0)
up = max(0.363 * SIZE, sup_depth + 0.25 * XH * SIZE)
sup_h = box("2", S7)[1]
out("x^2", sup_x=adv("x"), sup_y=-up, sup_size=S7, width=adv("x") + adv("2", S7) + 0.05 * SIZE, ascent=max(box("x")[1], up + sup_h))

# 4. "\frac{1}{2}" in text style: numerator and denominator in script style (0.7),
# shifts 0.394 / 0.345 em lifted to keep a clearance of one rule thickness.
n_d = max(-box("1", S7)[0], 0.0)
n_h = box("1", S7)[1]
d_h = box("2", S7)[1]
u = 0.394 * SIZE
v = 0.345 * SIZE
phi = THETA
if (u - n_d) - (AXIS + THETA / 2) < phi:
    u += phi - ((u - n_d) - (AXIS + THETA / 2))
if (AXIS - THETA / 2) - (d_h - v) < phi:
    v += phi - ((AXIS - THETA / 2) - (d_h - v))
w = max(adv("1", S7), adv("2", S7))
side = 0.12 * SIZE
out("frac", num_y=-u, den_y=v, bar_y=-(AXIS + THETA / 2), bar_w=w, bar_h=THETA, width=w + 2 * side, ascent=u + n_h,
    num_x=side + (w - adv("1", S7)) / 2, den_x=side + (w - adv("2", S7)) / 2)

# 5. Display style fraction: children in text style, shifts 0.677 / 0.686 em, clearance 3 theta.
n_d = max(-box("1")[0], 0.0)
n_h = box("1")[1]
d_h = box("2")[1]
u = 0.677 * SIZE
v = 0.686 * SIZE
phi = 3 * THETA
if (u - n_d) - (AXIS + THETA / 2) < phi:
    u += phi - ((u - n_d) - (AXIS + THETA / 2))
if (AXIS - THETA / 2) - (d_h - v) < phi:
    v += phi - ((AXIS - THETA / 2) - (d_h - v))
out("frac display", num_y=-u, den_y=v, num_size=SIZE, ascent=u + n_h)

# 6. "\sqrt{x}" in text style: clearance psi = theta + theta / 4, bar above the radicand
# by psi + theta, radical sign grown to the radicand's height + depth + psi + theta.
xh_, xd_ = box("x")[1], max(-box("x")[0], 0.0)
psi = THETA + THETA / 4
need = xh_ + xd_ + psi + THETA
sy0, sy1 = box("√")
ink = sy1 - sy0
k = need / ink if ink > 0 and need > ink else 1.0
sign_w = adv("√", SIZE * k)
top = xh_ + psi + THETA
out("sqrt", sign_size=SIZE * k, sign_w=sign_w, bar_x=sign_w, bar_y=-top, bar_h=THETA, body_x=sign_w, ascent=top)

# 7. 2x2 matrix in parentheses (text style cells): column width is the widest cell, columns a
# full em apart, rows tall enough for a 0.7/0.3 split of a 1.2 em baseline skip.
cells = [["1", "2"], ["3", "4"]]
col_w = [max(adv(cells[r][c]) for r in range(2)) for c in range(2)]
row_h = [max(0.84 * SIZE, max(box(cells[r][c])[1] for c in range(2))) for r in range(2)]
row_d = [max(0.36 * SIZE, max(-box(cells[r][c])[0] for c in range(2))) for r in range(2)]
H = sum(row_h) + sum(row_d)
top = AXIS + H / 2
y0 = top - row_h[0]
y1 = top - row_h[0] - row_d[0] - row_h[1]
x1 = col_w[0] + SIZE
out("pmatrix", row0_y=-y0, row1_y=-y1, total_h=H, ascent=top, body_width=col_w[0] + SIZE + col_w[1],
    cell01_x=x1 + (col_w[1] - adv("2")) / 2, cell00_x=(col_w[0] - adv("1")) / 2)
