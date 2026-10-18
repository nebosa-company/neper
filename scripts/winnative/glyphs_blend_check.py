"""Checks GDI's ClearType blend model against the glyph oracle (docs/ui/looks/ref/windows-native/glyphs).

python -I scripts/winnative/glyphs_blend_check.py

The model (also `blend_byte` in lib/e/gfx/cleartype.e): per channel, bg and fg go through an 8-bit table (255 * (i / 255) ^ 1.2,
rounded), are mixed with a = round(65536 * k / 6) / 65536 (k the coverage 0..6, the sixths a ClearType sample window gives), rounded
to a byte and sent back through the inverse table (255 * (i / 255) ^ (1 / 1.2), rounded). A pixel no channel covers is left alone; in a
covered pixel a channel with k = 0 still goes through the tables. The coverage of each channel is read off the black-on-white atlas (seven
levels 255 219 182 144 102 58 0 for k = 0..6) and the model must give every other atlas of the same font and size byte for byte, and
the 256 x 4 ramp blend2.q5.png.
"""
import glob
import math
import os
import struct

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, "..", "..", "docs", "ui", "looks", "ref", "windows-native", "glyphs") + os.sep
DEC = [math.floor(255 * (i / 255) ** 1.2 + 0.5) for i in range(256)]
ENC = [min(255, math.floor(255 * (i / 255) ** (1 / 1.2) + 0.5)) for i in range(256)]
ALPHA = [(k * 65536 + 3) // 6 for k in range(7)]
LEVEL = {255: 0, 219: 1, 182: 2, 144: 3, 102: 4, 58: 5, 0: 6}


def blend(f, b, k):
    return ENC[(DEC[b] * (65536 - ALPHA[k]) + DEC[f] * ALPHA[k] + 32768) >> 16]


def main():
    bad = 0
    total = 0
    tags = sorted({os.path.basename(p).split(".")[0] for p in glob.glob(BASE + "*.png") if "blend" not in p})
    for tag in tags:
        ref = np.array(Image.open(BASE + tag + ".000000-FFFFFF.png").convert("RGB"))
        k = np.vectorize(lambda v: LEVEL[int(v)])(ref)
        touched = k.sum(axis=2) > 0
        for p in sorted(glob.glob(BASE + tag + ".*.png")):
            fg, bg = os.path.basename(p).split(".")[-2].split("-")
            f = [int(fg[i:i + 2], 16) for i in (0, 2, 4)]
            b = [int(bg[i:i + 2], 16) for i in (0, 2, 4)]
            im = np.array(Image.open(p).convert("RGB"))
            out = np.zeros_like(im)
            for c in range(3):
                lut = np.array([blend(f[c], b[c], q) for q in range(7)])
                out[:, :, c] = np.where(touched, lut[k[:, :, c]], b[c])
            bad += int((out != im).sum())
            total += im.size
    ramp = np.array(Image.open(BASE + "blend2.q5.png").convert("RGB")).astype(int)
    cw, ch = 24, 32
    ref = ramp[255 * ch:256 * ch, 2 * cw:3 * cw]  # text 0 on background 255
    k = np.vectorize(lambda v: LEVEL[int(v)])(ref)
    for col in range(4):
        for v in range(256):
            f, b = [(v, 0), (v, 255), (0, v), (255, v)][col]
            cell = ramp[v * ch:(v + 1) * ch, col * cw:(col + 1) * cw]
            for q in range(7):
                sel = np.unique(cell[:, :, 0][k[:, :, 0] == q])
                total += 1
                # a covered pixel of coverage 0 may also show the untouched background
                if blend(f, b, q) not in sel:
                    bad += 1
    print("blend model: %d of %d samples off" % (bad, total))
    raise SystemExit(1 if bad else 0)


main()
