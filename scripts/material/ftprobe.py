"""Checks the AndroidSkia text mode (lib/e/gfx/dwtext.e rasterize_ft) against FreeType itself, and writes the side-by-side sheet.

AndroidSkia is a device's Skia over FreeType: unhinted outline, FreeType's smooth rasteriser (exact area, 256 levels), the pen at a
quarter pixel, Skia's A8 pre-blend table with Android's constants (contrast 0, exponent 1.4). This script runs the real FreeType
(freetype-py, FT_LOAD_NO_HINTING, FT_RENDER_MODE_NORMAL, the outline translated by 16/64 per quarter like Skia) over the same
glyphs as the probe sheet, applies the same table, blends black text onto the cell's background and counts the share of ink pixels
within 2 levels of what the Neper renderer drew.

  build and run:  neper-self emit-executable examples/looks/material_android_text.e . x64 windows OUT.exe --arena 4g
                  OUT.exe probe ; OUT.exe          (writes docs/ui/looks/android-text/{probe,words}_{chromewin,androidskia}.png)
  check:          python -I scripts/material/ftprobe.py        (needs freetype-py, numpy, Pillow; Roboto from C:/Windows/Fonts)

The glyph's whole pixel placement is searched (+-2 px around the ink's corner) and, for the one-glyph cells, the quarter too: placement is
the layout's business, the coverage model is what is under test. Two-glyph cells put the second pen at the advance, quarter rounded.
"""
import ctypes
import math
import os
import sys

import freetype
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "docs", "ui", "looks", "android-text")
ROBOTO = "C:/Windows/Fonts/Roboto-Regular.ttf"
CONTRAST, EXPONENT = 0.0, 1.4
GLYPHS = ["A", "g", "R", "o", "e", "&", "1", "Q", "W", "y", "@", "%", "t", "s", "k", "8"]
WORDS = ["ao", "ii", "ty", "re", "ow", "ft", "il", "rk"] * 2
SIZES = [11, 12, 14, 16, 22, 28, 14, 16]
COLS, CELL_W, CELL_H, MARGIN, SPACING, CAPTION = 16, 44, 40, 12, 10, 16 + 4


def build_lut():
    """Skia's SkTMaskGamma_build_correcting_lut for black text (luminance key 0)"""
    src, dst = 0.0, 1.0
    ls, ld = src ** EXPONENT, dst ** EXPONENT
    t = []
    for i in range(256):
        c = i / 255.0
        a = c + (1 - c) * (CONTRAST * ld) * c
        out = (ls * a + (1 - a) * ld) ** (1 / EXPONENT)
        t.append(min(255, max(0, math.floor(255 * (out - dst) / (src - dst) + 0.5))))
    return t


LUT = build_lut()
FACE = freetype.Face(ROBOTO)


def render(ch, size, quarter):
    """(alpha 0..255 after the table, left, top) of one glyph at a quarter-pixel pen"""
    FACE.set_char_size(int(round(size * 64)))
    FACE.load_char(ch, freetype.FT_LOAD_NO_HINTING | freetype.FT_LOAD_NO_BITMAP)
    slot = FACE.glyph
    freetype.FT_Outline_Translate(ctypes.byref(slot._FT_GlyphSlot.contents.outline), 16 * quarter, 0)
    slot.render(freetype.FT_RENDER_MODE_NORMAL)
    bm = slot.bitmap
    a = np.array(bm.buffer, dtype=np.uint8).reshape(bm.rows, bm.pitch)[:, : bm.width] if bm.rows else np.zeros((0, 0), np.uint8)
    return np.array(LUT, dtype=np.uint8)[a], slot.bitmap_left, slot.bitmap_top


def advance(ch, size):
    FACE.set_char_size(int(round(size * 64)))
    FACE.load_char(ch, freetype.FT_LOAD_NO_HINTING | freetype.FT_LOAD_NO_BITMAP)
    return FACE.glyph.linearHoriAdvance / 65536.0


def compose(word, size, quarters, bg, shape):
    """black glyphs blended one after another (Skia blends each A8 mask) over `bg`; glyph pen 0 at column 24, baseline row 32 of `shape`"""
    img = np.full(shape, float(bg))
    pen = 0.0
    for i, ch in enumerate(word):
        q = quarters[i] if quarters is not None else None
        whole = math.floor(pen)
        quarter = math.floor((pen - whole) * 4 + 0.5) if i else 0
        if q is not None:
            quarter = q
        if quarter == 4:
            whole, quarter = whole + 1, 0
        a, left, top = render(ch, size, quarter)
        for y in range(a.shape[0]):
            for x in range(a.shape[1]):
                if a[y, x]:
                    yy, xx = 32 - top + y, 24 + whole + left + x
                    if 0 <= yy < shape[0] and 0 <= xx < shape[1]:
                        img[yy, xx] *= 1 - a[y, x] / 255.0
        pen += advance(ch, size)
    return img


def cell_box(i):
    col, row = i % COLS, i // COLS
    return MARGIN + col * (CELL_W + SPACING), MARGIN + row * (CAPTION + CELL_H + SPACING) + CAPTION


def check(path):
    ours = np.array(Image.open(path).convert("RGB"))[..., 1].astype(float)
    totals = {}
    for i in range(128):
        x0, y0 = cell_box(i)
        crop = ours[y0 : y0 + CELL_H, x0 : x0 + CELL_W]
        bg = crop[0, 0]
        ink = np.argwhere(np.abs(crop - bg) > 0)
        if len(ink) == 0:
            continue
        word = GLYPHS[i % 16] if i < 96 else WORDS[i % 16]
        size = SIZES[i // 16]
        top, left = ink.min(0)
        best = None
        for q0, q1 in [(q, None) for q in range(4)] if len(word) == 1 else [(0, q) for q in (None, 0, 1, 2, 3)]:
            model = compose(word, size, [q0] + [q1] * (len(word) - 1), bg, (80, 100))
            m_ink = np.argwhere(np.abs(model - bg) > 0.5)
            if len(m_ink) == 0:
                continue
            mt, ml = m_ink.min(0)
            for sy in range(-2, 3):
                for sx in range(-2, 3):
                    # put the model's ink corner at ours (+ shift)
                    oy, ox = top - mt + sy, left - ml + sx
                    pred = np.full(crop.shape, bg)
                    ys, xs = np.arange(model.shape[0]) + oy, np.arange(model.shape[1]) + ox
                    ok_y, ok_x = (ys >= 0) & (ys < CELL_H), (xs >= 0) & (xs < CELL_W)
                    pred[np.ix_(ys[ok_y], xs[ok_x])] = model[np.ix_(ok_y, ok_x)]
                    diff = np.abs(np.round(pred) - crop)
                    mask = (np.abs(crop - bg) > 0) | (np.abs(pred - bg) > 0.5)
                    good = int(((diff <= 2) & mask).sum())
                    cand = (good, int(mask.sum()), int(diff[mask].max()), (q0, q1, sx, sy))
                    if best is None or cand[0] - cand[1] > best[0] - best[1]:
                        best = cand
        g = totals.setdefault(size if i < 96 else -size, [0, 0, 0])
        g[0] += best[0]
        g[1] += best[1]
        g[2] = max(g[2], best[2])
    return totals


def side_by_side(name):
    a = Image.open(os.path.join(OUT, f"{name}_chromewin.png")).convert("RGB")
    b = Image.open(os.path.join(OUT, f"{name}_androidskia.png")).convert("RGB")
    sheet = Image.new("RGB", (a.width, a.height * 2 + 4), (200, 200, 200))
    sheet.paste(a, (0, 0))
    sheet.paste(b, (0, a.height + 4))
    sheet.save(os.path.join(OUT, f"{name}_side.png"))


if __name__ == "__main__":
    t = check(os.path.join(OUT, "probe_androidskia.png"))
    good = sum(v[0] for v in t.values())
    ink = sum(v[1] for v in t.values())
    for k in sorted(t):
        print(("%d px glyphs" if k > 0 else "%d px two-glyph words") % abs(k), "%d/%d = %.1f%%" % (t[k][0], t[k][1], 100.0 * t[k][0] / t[k][1]), "worst diff", t[k][2])
    print("all: %d of %d ink pixels within 2 levels = %.2f%%" % (good, ink, 100.0 * good / ink))
    for n in ("words", "probe"):
        side_by_side(n)
