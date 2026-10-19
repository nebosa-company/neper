"""Probe of how the Material Web references draw text, and a Python model of it (the one lib/e/gfx/dwtext.e implements).

The references are Chrome for Testing 149 (headless shell, --disable-lcd-text --font-render-hinting=none) ON WINDOWS: Skia over
DirectWrite, not FreeType. Roboto is a web font from C:/Windows/Fonts. The stages, each found by probing isolated glyphs:

  outline   the font's own TrueType instructions at the whole pixel size (tools/ctdump, ClearType mode, glyph end not fitted)
  sampling  6 x 5 samples to the pixel, a sample set when its centre is inside (non-zero winding); the pen x goes to a quarter pixel
            (Skia) and then to a sixth (DirectWrite)
  filter    three channels = boxes of 6 sample columns at columns -2..3, 0..5, 2..7 of the pixel; a column is the sum of the five
            rows weighted 4 9 10 9 4; channel byte = round(255 * sum / 216)
  mask      (r + g + b) / 3 (integer) through Skia's pre-blend table: SkComputeLuminance of the text colour's sRGB bytes, top three
            bits, sRGB transfer curve, contrast 1 (SkTMaskGamma_build_correcting_lut); composed as an A8 mask under the colour

  python -I scripts/material/dwprobe.py CTDUMP.exe [--shot]     (CTDUMP.exe: build tools/ctdump with the compiler)

Writes a probe page (every printable ASCII glyph at 11 .. 32 px, both weights, pen offsets 0 and 1/4) to $TEMP/dwprobe, photographs
it with the reference's Chromium when --shot is given (MATWEB and PLAYWRIGHT_BROWSERS_PATH as for capture.mjs), then compares the
model with the picture and prints the share of ink pixels within 2 levels (98 % on the 2026-10 run, black on white).
"""
import functools
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

FONTS = {400: "C:/Windows/Fonts/Roboto-Regular.ttf", 500: "C:/Windows/Fonts/Roboto-Medium.ttf"}
VW = [4, 9, 10, 9, 4]
TMP = os.path.join(tempfile.gettempdir(), "dwprobe")


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin_to_srgb(l):
    return l * 12.92 if l <= 0.0031308 else 1.055 * l ** (1 / 2.4) - 0.055


@functools.lru_cache(None)
def lut(key):
    """Skia's pre-blend table for luminance key 0..7 (black text is key 0)"""
    src = (key * 32 + key * 4 + key // 2) / 255.0
    dst = 1 - src
    ls, ld = srgb_to_lin(src), srgb_to_lin(dst)
    t = []
    for i in range(256):
        c = i / 255.0
        s = c + (1 - c) * ld * c  # contrast 1
        res = (lin_to_srgb(ls * s + (1 - s) * ld) - dst) / (src - dst) if abs(src - dst) >= 1 / 256 else c
        t.append(min(255, max(0, math.floor(255 * res + 0.5))))
    return t


def lut_key(r, g, b):
    return ((r * 54 + g * 183 + b * 19) >> 8) >> 5


@functools.lru_cache(None)
def outlines(ctdump, weight, size):
    """code -> contours of (x, y, on) in pixels, y down, from tools/ctdump"""
    txt = subprocess.run([ctdump, FONTS[weight], str(size)], capture_output=True, text=True).stdout
    out = {}
    for line in txt.splitlines():
        v = list(map(int, line.split()))
        i, cs = 4, []
        for _ in range(v[3]):
            n = v[i]
            i += 1
            cs.append([(v[i + 3 * k] / 64.0, -v[i + 3 * k + 1] / 64.0, v[i + 3 * k + 2] & 1) for k in range(n)])
            i += 3 * n
        out[v[0]] = cs
    return out


def segments(contour, xoff, steps=16):
    pts = []
    n = len(contour)
    for k in range(n):
        x, y, on = contour[k]
        pts.append((x + xoff, y, on))
        nx, ny, non = contour[(k + 1) % n]
        if not on and not non:
            pts.append(((x + nx) / 2 + xoff, (y + ny) / 2, 1))
    s = next((k for k, p in enumerate(pts) if p[2]), None)
    if s is None:
        return
    pts = pts[s:] + pts[:s]
    cur, i, m = pts[0], 1, len(pts)
    while i <= m:
        p = pts[i % m]
        if p[2]:
            yield cur[:2], p[:2]
            cur, i = p, i + 1
        else:
            e = pts[(i + 1) % m]
            a = cur
            for j in range(1, steps + 1):
                u = j / steps
                q = ((1 - u) ** 2 * a[0] + 2 * u * (1 - u) * p[0] + u * u * e[0], (1 - u) ** 2 * a[1] + 2 * u * (1 - u) * p[1] + u * u * e[1])
                yield cur[:2], q
                cur = q
            cur, i = e, i + 2


def mask(contours, xfrac, table):
    """alpha bytes of one glyph: (rows of ints, x0, y0) from the pen's pixel, baseline at y = 0"""
    segs = [s for c in contours for s in segments(c, xfrac)]
    xs = [p[0] for s in segs for p in s]
    ys = [p[1] for s in segs for p in s]
    x0, x1, y0, y1 = math.floor(min(xs)) - 2, math.ceil(max(xs)) + 2, math.floor(min(ys)) - 1, math.ceil(max(ys)) + 1
    W, H = (x1 - x0) * 6, (y1 - y0) * 5
    g = np.zeros((H, W), int)
    for r in range(H):
        y = y0 + (r + 0.5) / 5
        cr = sorted(((a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])), 1 if b[1] > a[1] else -1) for a, b in segs if min(a[1], b[1]) <= y < max(a[1], b[1]))
        w = 0
        for k in range(len(cr) - 1):
            w += cr[k][1]
            if w:
                g[r, max(0, math.ceil((cr[k][0] - x0) * 6 - 0.5)):min(W, math.ceil((cr[k + 1][0] - x0) * 6 - 0.5))] = 1
    v = np.pad(np.einsum("hrw,r->hw", g.reshape(y1 - y0, 5, W), VW), ((0, 0), (2, 2)))
    out = np.zeros((y1 - y0, x1 - x0), int)
    for p in range(x1 - x0):
        ch = [(255 * v[:, 6 * p + 2 * c:6 * p + 2 * c + 6].sum(1) + 108) // 216 for c in range(3)]
        out[:, p] = np.array(table)[(ch[0] + ch[1] + ch[2]) // 3]
    return out, x0, y0


def quant(x):
    q = math.floor(x * 4 + 0.5) / 4
    ix = math.floor(q)
    return ix, math.floor((q - ix) * 6 + 0.5) / 6


def page(cfg):
    css = "".join('@font-face { font-family: R%d; font-weight: %d; src: url("file:///%s"); }' % (w, w, p) for w, p in FONTS.items())
    body = "".join('<div style="left:%spx;top:%dpx;font:%d %dpx/%dpx R%d">%s</div>' % (i["x"], i["y"], i["w"], i["size"], i["size"] * 2, i["w"], i["ch"].replace("&", "&amp;").replace("<", "&lt;")) for i in cfg)
    return "<style>%s html,body{margin:0;background:#fff}div{position:absolute;white-space:pre;letter-spacing:0}</style>%s" % (css, body)


SHOT = """import { createRequire } from "node:module";
const require = createRequire((process.env.MATWEB || "D:/Temp/matweb") + "/x.js");
const { chromium } = require("playwright-core");
const b = await chromium.launch({ args: ["--disable-lcd-text", "--font-render-hinting=none"], executablePath: process.env.CHROMIUM || "D:/tools/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-win64/chrome-headless-shell.exe" });
const p = await (await b.newContext({ deviceScaleFactor: 1, viewport: { width: 2000, height: 900 } })).newPage();
await p.goto("file:///" + process.argv[2].split("\\\\").join("/"));
await p.evaluate(() => document.fonts.ready);
await p.waitForTimeout(300);
await p.screenshot({ path: process.argv[3], fullPage: true });
await b.close();
"""


def main():
    ctdump = sys.argv[1]
    os.makedirs(TMP, exist_ok=True)
    cfg, n = [], 0
    for w in (400, 500):
        for size in (11, 12, 14, 16, 22, 24, 28, 32):
            for off in (0.0, 0.25):
                for c in range(33, 127):
                    cfg.append(dict(ch=chr(c), size=size, w=w, x=6 + (n % 44) * 44 + off, y=6 + (n // 44) * 44))
                    n += 1
    html, png = os.path.join(TMP, "probe.html"), os.path.join(TMP, "probe.png")
    open(html, "w").write(page(cfg))
    if "--shot" in sys.argv:
        open(os.path.join(TMP, "shot.mjs"), "w").write(SHOT)
        subprocess.run(["node", os.path.join(TMP, "shot.mjs"), html, png], check=True)
    ref = 255 - np.array(Image.open(png).convert("L")).astype(int)
    tot = ok = 0
    t = lut(0)
    for it in cfg:
        ix, xf = quant(it["x"])
        a, x0, y0 = mask(outlines(ctdump, it["w"], it["size"])[ord(it["ch"])], xf, t)
        h, w = a.shape
        best = min(((np.abs(ref[dy + y0:dy + y0 + h, ix + x0:ix + x0 + w] - a).sum(), dy) for dy in range(it["y"], it["y"] + 2 * it["size"]) if ref[dy + y0:dy + y0 + h, ix + x0:ix + x0 + w].shape == a.shape), default=None)
        if best is None:
            continue
        r = ref[best[1] + y0:best[1] + y0 + h, ix + x0:ix + x0 + w]
        ink = (r > 2) | (a > 2)
        tot += ink.sum()
        ok += ((np.abs(r - a) <= 2) & ink).sum()
    print("ink pixels within 2 levels: %.2f %% of %d" % (100.0 * ok / tot, tot))


if __name__ == "__main__":
    main()
