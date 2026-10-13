"""Writes tests/selfhost/fixtures/link/gfx_svg_filter (L125, D4503).

Each case is an SVG document with a `filter`; the fixture draws it through `e.gfx.svg.draw_filtered` over white at
64 x 64, reduces it to 16 x 16 RGB (4 x 4 cells) and holds the mean and the largest cell difference to a
tolerance against a reference computed here:

  * the *source graphic* (the same document without the `filter` attribute) is rasterised by cairosvg, which
    does not implement blur, colour matrices or composites -- so the filter itself is the SVG / Filter Effects
    text applied in numpy float64 over that raster: premultiplied buffers, linearRGB unless the case says
    sRGB, the filter region in device pixels (rounded outward, clipped to the target), transparent outside it,
    the three-box blur of the SVG text for a deviation of 2 pixels or more and an exact kernel below, the
    compositing-and-blending formulas of the W3C spec, the colour-matrix definitions;
  * a few cases cross-check against cairosvg's own `feOffset`, `feFlood` and `feBlend` (the only primitives it
    has): the generator asserts that the numpy reference and cairosvg agree before it writes either.

    python scripts/gen_svg_filter_test.py
"""
import io
import math
import os
import sys

import cairosvg
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIDE = 64
CELLS = 16
S = SIDE / 100.0          # user units (viewBox 0 0 100 100) to pixels
H = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'


# ---- the reference -----------------------------------------------------------------------------------------
def render(svg):
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=SIDE, output_height=SIDE)
    a = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA"), dtype=np.float64) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def to_linear(p):
    a = p[..., 3:4]
    c = np.where(a > 0, p[..., :3] / np.where(a > 0, a, 1), 0.0)
    c = np.clip(c, 0, 1)
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return np.concatenate([c * a, a], axis=-1)


def to_srgb(p):
    a = p[..., 3:4]
    c = np.where(a > 0, p[..., :3] / np.where(a > 0, a, 1), 0.0)
    c = np.clip(c, 0, 1)
    c = np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
    return np.concatenate([c * a, a], axis=-1)


def box1d(a, axis, lo, hi):
    """Mean of a[i - lo .. i + hi] along `axis`, zero outside."""
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (lo, hi)
    z = np.pad(a, pad)
    c = np.cumsum(z, axis=axis)
    zero_shape = list(c.shape)
    zero_shape[axis] = 1
    c = np.concatenate([np.zeros(zero_shape), c], axis=axis)
    size = lo + hi + 1
    top = np.take(c, np.arange(size, size + n), axis=axis)
    bottom = np.take(c, np.arange(0, n), axis=axis)
    return (top - bottom) / size


def blur1d(a, axis, sigma):
    if not sigma > 0: return a
    if sigma >= 2.0:
        d = int(math.floor(sigma * 3 * math.sqrt(2 * math.pi) / 4 + 0.5))
        if d % 2 == 1:
            for _ in range(3): a = box1d(a, axis, d // 2, d // 2)
        else:
            a = box1d(a, axis, d // 2, d // 2 - 1)
            a = box1d(a, axis, d // 2 - 1, d // 2)
            a = box1d(a, axis, d // 2, d // 2)
        return a
    r = int(math.ceil(sigma * 3))
    k = np.exp(-((np.arange(-r, r + 1)) ** 2) / (2 * sigma * sigma))
    k /= k.sum()
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r, r)
    z = np.pad(a, pad)
    out = np.zeros_like(a)
    for t in range(2 * r + 1):
        out += k[t] * np.take(z, np.arange(t, t + n), axis=axis)
    return out


def blend_sep(mode, cb, cs):
    if mode == "normal": return cs
    if mode == "multiply": return cb * cs
    if mode == "screen": return cb + cs - cb * cs
    if mode == "darken": return np.minimum(cb, cs)
    if mode == "lighten": return np.maximum(cb, cs)
    if mode == "difference": return np.abs(cb - cs)
    if mode == "exclusion": return cb + cs - 2 * cb * cs
    if mode in ("overlay", "hard-light"):
        b, s = (cs, cb) if mode == "overlay" else (cb, cs)    # overlay is hard-light with the arguments swapped
        return np.where(s <= 0.5, b * 2 * s, b + (2 * s - 1) - b * (2 * s - 1))
    if mode == "color-dodge":
        return np.where(cb == 0, 0.0, np.where(cs >= 1, 1.0, np.minimum(1.0, cb / np.where(cs >= 1, 1, 1 - cs))))
    if mode == "color-burn":
        return np.where(cb >= 1, 1.0, np.where(cs <= 0, 0.0, 1 - np.minimum(1.0, (1 - cb) / np.where(cs <= 0, 1, cs))))
    if mode == "soft-light":
        d = np.where(cb <= 0.25, ((16 * cb - 12) * cb + 4) * cb, np.sqrt(cb))
        return np.where(cs <= 0.5, cb - (1 - 2 * cs) * cb * (1 - cb), cb + (2 * cs - 1) * (d - cb))
    raise ValueError(mode)


def lum(c): return 0.3 * c[..., 0] + 0.59 * c[..., 1] + 0.11 * c[..., 2]


def clip_color(c):
    l = lum(c)[..., None]
    n = c.min(axis=-1, keepdims=True)
    x = c.max(axis=-1, keepdims=True)
    c = np.where(n < 0, l + (c - l) * l / np.where(l - n == 0, 1, l - n), c)
    c = np.where(x > 1, l + (c - l) * (1 - l) / np.where(x - l == 0, 1, x - l), c)
    return c


def set_lum(c, l):
    return clip_color(c + (l - lum(c))[..., None])


def sat(c): return c.max(axis=-1) - c.min(axis=-1)


def set_sat(c, s):
    mn = c.min(axis=-1, keepdims=True)
    mx = c.max(axis=-1, keepdims=True)
    rng = mx - mn
    return np.where(rng > 0, (c - mn) * s[..., None] / np.where(rng > 0, rng, 1), 0.0)


def blend(mode, src, back):
    sa, ba = src[..., 3:4], back[..., 3:4]
    cs = np.where(sa > 0, src[..., :3] / np.where(sa > 0, sa, 1), 0.0)
    cb = np.where(ba > 0, back[..., :3] / np.where(ba > 0, ba, 1), 0.0)
    cs, cb = np.clip(cs, 0, 1), np.clip(cb, 0, 1)
    if mode == "hue": mixed = set_lum(set_sat(cs, sat(cb)), lum(cb))
    elif mode == "saturation": mixed = set_lum(set_sat(cb, sat(cs)), lum(cb))
    elif mode == "color": mixed = set_lum(cs, lum(cb))
    elif mode == "luminosity": mixed = set_lum(cb, lum(cs))
    else: mixed = blend_sep(mode, cb, cs)
    rgb = (1 - ba) * src[..., :3] + (1 - sa) * back[..., :3] + sa * ba * np.clip(mixed, 0, 1)
    return np.concatenate([rgb, sa + ba - sa * ba], axis=-1)


def composite(op, a, b, k=(0, 0, 0, 0)):
    a1, a2 = a[..., 3:4], b[..., 3:4]
    if op == "over": r = a + b * (1 - a1)
    elif op == "in": r = a * a2
    elif op == "out": r = a * (1 - a2)
    elif op == "atop": r = a * a2 + b * (1 - a1)
    elif op == "xor": r = a * (1 - a2) + b * (1 - a1)
    else: r = k[0] * a * b + k[1] * a + k[2] * b + k[3]
    r = np.clip(r, 0, 1)
    if op == "arithmetic": r[..., :3] = np.minimum(r[..., :3], r[..., 3:4])
    return r


def color_matrix(p, m):
    a = p[..., 3:4]
    c = np.where(a > 0, p[..., :3] / np.where(a > 0, a, 1), 0.0)
    v = np.concatenate([np.clip(c, 0, 1), a, np.ones_like(a)], axis=-1)
    o = np.clip(v @ np.asarray(m, dtype=np.float64).reshape(4, 5).T, 0, 1)
    return np.concatenate([o[..., :3] * o[..., 3:4], o[..., 3:4]], axis=-1)


def matrix_for(kind, v):
    if kind == "matrix": return list(v)
    if kind == "saturate":
        s = v[0]
        return [0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
                0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
                0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, 0, 0, 0, 1, 0]
    if kind == "hueRotate":
        r = math.radians(v[0])
        c, s = math.cos(r), math.sin(r)
        return [0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
                0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
                0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0, 0, 0, 0, 1, 0]
    return [0] * 15 + [0.2125, 0.7154, 0.0721, 0, 0]       # luminanceToAlpha


def shift(p, dx, dy):
    h, w = p.shape[:2]
    out = np.zeros_like(p)
    for y in range(h):
        sy = y - dy
        if not 0 <= sy < h: continue
        for x in range(w):
            sx = x - dx
            if 0 <= sx < w: out[y, x] = p[sy, sx]
    return out


def device_rect(rect, ctm):
    sx, sy, tx, ty = ctm
    x, y, w, h = rect
    return ((x * sx + tx) * S, (y * sy + ty) * S, (x * sx + tx + w * sx) * S, (y * sy + ty + h * sy) * S)


def pixel_rect(dev, w=SIDE, h=SIDE):
    x0, y0, x1, y1 = (int(math.floor(dev[0])), int(math.floor(dev[1])), int(math.ceil(dev[2])), int(math.ceil(dev[3])))
    return max(0, x0), max(0, y0), min(w, x1), min(h, y1)


def reference_pixels(case):
    """The filtered element over white: (SIDE, SIDE, 3) floats in 0..1."""
    ctm = case.get("ctm", (1, 1, 0, 0))
    sx, sy = S * ctm[0], S * ctm[1]
    bx, by, bw, bh = case["bbox"]
    if case.get("units", "obb") == "obb":
        fx, fy, fw, fh = case.get("region", (-0.1, -0.1, 1.2, 1.2))
        region = (bx + fx * bw, by + fy * bh, fw * bw, fh * bh)
    else:
        region = case.get("region", (-10, -10, 120, 120))
    x0, y0, x1, y1 = pixel_rect(device_rect(region, ctm))
    src = render(case["src"])
    out = np.zeros((SIDE, SIDE, 4))
    if x1 > x0 and y1 > y0:
        w, h = x1 - x0, y1 - y0
        source = src[y0:y1, x0:x1].copy()
        alpha = np.zeros_like(source)
        alpha[..., 3] = source[..., 3]
        results = []
        names = {}
        linear_default = case.get("space", "linear") == "linear"

        def ref(r, n):
            if r is None: return results[n - 1] if n > 0 else source
            if r == "SourceGraphic": return source
            if r == "SourceAlpha": return alpha
            if r in ("BackgroundImage", "BackgroundAlpha", "FillPaint", "StrokePaint"): return np.zeros_like(source)
            return results[names[r]] if r in names else (results[n - 1] if n > 0 else source)

        def subregion(prim):
            if "sub" not in prim: return None
            sr = list(region)
            for k, name in enumerate(("x", "y", "w", "h")):
                if name in prim["sub"]: sr[k] = prim["sub"][name]
            if case.get("prim_units", "user") == "obb":
                sr = [bx + prim["sub"].get("x", 0) * bw if "x" in prim["sub"] else region[0],
                      by + prim["sub"].get("y", 0) * bh if "y" in prim["sub"] else region[1],
                      prim["sub"]["w"] * bw if "w" in prim["sub"] else region[2],
                      prim["sub"]["h"] * bh if "h" in prim["sub"] else region[3]]
            d = device_rect(tuple(sr), ctm)
            return (int(math.floor(d[0])) - x0, int(math.floor(d[1])) - y0, int(math.ceil(d[2])) - x0, int(math.ceil(d[3])) - y0)

        unit_x = bw if case.get("prim_units", "user") == "obb" else 1.0
        unit_y = bh if case.get("prim_units", "user") == "obb" else 1.0
        for n, prim in enumerate(case["program"]):
            kind = prim["kind"]
            linear = prim.get("space", "linear" if linear_default else "srgb") == "linear"
            i1 = ref(prim.get("in"), n)
            i2 = ref(prim.get("in2"), n)
            neutral = kind in ("offset", "flood", "merge")
            conv = linear and not neutral
            if conv: i1, i2 = to_linear(i1), to_linear(i2)
            if kind == "blur":
                r = i1.copy()
                r = np.moveaxis(blur1d(np.moveaxis(r, 1, 0), 0, prim["sx"] * unit_x * sx), 0, 1)
                r = blur1d(r, 0, prim["sy"] * unit_y * sy)
            elif kind == "offset":
                dx, dy = prim.get("dx", 0) * unit_x, prim.get("dy", 0) * unit_y
                r = shift(i1, int(round(dx * sx)), int(round(dy * sy)))
            elif kind == "flood":
                c = prim["color"]
                a = prim.get("opacity", 1.0)
                r = np.zeros_like(source)
                r[...] = (c[0] * a, c[1] * a, c[2] * a, a)
            elif kind == "blend":
                r = blend(prim.get("mode", "normal"), i1, i2)
            elif kind == "composite":
                r = composite(prim.get("op", "over"), i1, i2, prim.get("k", (0, 0, 0, 0)))
            elif kind == "matrix":
                r = color_matrix(i1, matrix_for(prim.get("type", "matrix"), prim.get("values", [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0])))
            elif kind == "merge":
                r = np.zeros_like(source)
                for node in prim["nodes"]:
                    t = ref(node, n)
                    r = t + r * (1 - t[..., 3:4])
            elif kind == "shadow":
                a_only = np.zeros_like(i1)
                a_only[..., 3] = i1[..., 3]
                s = np.moveaxis(blur1d(np.moveaxis(a_only, 1, 0), 0, prim["sx"] * unit_x * sx), 0, 1)
                s = blur1d(s, 0, prim["sy"] * unit_y * sy)
                s = shift(s, int(round(prim["dx"] * unit_x * sx)), int(round(prim["dy"] * unit_y * sy)))
                c = prim["color"]
                if conv: c = [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c]
                k = s[..., 3:4] * prim.get("opacity", 1.0)
                shadow = np.concatenate([np.array(c) * k, k], axis=-1)
                r = i1 + shadow * (1 - i1[..., 3:4])
            else:
                raise ValueError(kind)
            if conv: r = to_srgb(r)
            sub = subregion(prim)
            if sub is not None:
                cut = np.zeros_like(r)
                sx0, sy0, sx1, sy1 = max(0, sub[0]), max(0, sub[1]), min(w, sub[2]), min(h, sub[3])
                if sx1 > sx0 and sy1 > sy0: cut[sy0:sy1, sx0:sx1] = r[sy0:sy1, sx0:sx1]
                r = cut
            if "result" in prim: names[prim["result"]] = n
            results.append(r)
        final = results[-1] if results else source
        out[y0:y1, x0:x1] = final
    op = case.get("opacity", 1.0)
    clip = case.get("clip")
    if clip is not None:
        cx0, cy0, cx1, cy1 = pixel_rect(device_rect(clip, (1, 1, 0, 0)))
        mask = np.zeros((SIDE, SIDE, 1))
        mask[cy0:cy1, cx0:cx1] = 1.0
        out = out * mask
    out = out * op
    return np.clip(out[..., :3] + (1.0 - out[..., 3:4]), 0, 1)


def reduce_pixels(img):
    """16 x 16 RGB, each cell the mean of 4 x 4 pixels of 8-bit values (as the other fixtures)."""
    b = np.floor(img * 255.0 + 0.5).astype(np.int64)
    cell = SIDE // CELLS
    out = bytearray()
    for cy in range(CELLS):
        for cx in range(CELLS):
            block = b[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell].reshape(-1, 3).sum(axis=0)
            out.extend(int(v) // (cell * cell) for v in block)
    return bytes(out)


def cairo_reference(svg):
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=SIDE, output_height=SIDE, background_color="white")
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGB"), dtype=np.float64) / 255.0


# ---- cases ---------------------------------------------------------------------------------------------------
def doc(defs, body, attrs=' filter="url(#f)"'):
    return H + ('<defs>%s</defs>' % defs if defs else '') + body.replace("{F}", attrs) + '</svg>'


def case(label, filt, body, bbox, program, src_body=None, **kw):
    c = dict(label=label, svg=doc(filt, body), src=doc("", src_body if src_body is not None else body, ""), bbox=bbox, program=program)
    c.update(kw)
    return c


RED = (1.0, 0.0, 0.0)
CASES = []

CASES.append(case("gaussian blur, three boxes (deviation 2.56 px)",
                  '<filter id="f"><feGaussianBlur stdDeviation="4"/></filter>',
                  '<rect x="30" y="30" width="40" height="40" fill="#ff0000"{F}/>', (30, 30, 40, 40),
                  [dict(kind="blur", sx=4, sy=4)]))
CASES.append(case("gaussian blur, exact kernel, different deviations (0.96 and 3.84 px)",
                  '<filter id="f"><feGaussianBlur stdDeviation="1.5 6"/></filter>',
                  '<circle cx="50" cy="50" r="22" fill="#2060c0"{F}/>', (28, 28, 44, 44),
                  [dict(kind="blur", sx=1.5, sy=6)]))
CASES.append(case("blur in sRGB space",
                  '<filter id="f" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="5"/></filter>',
                  '<g{F}><rect x="20" y="25" width="30" height="50" fill="#ff0000"/><rect x="50" y="25" width="30" height="50" fill="#0000ff"/></g>',
                  (20, 25, 60, 50), [dict(kind="blur", sx=5, sy=5, space="srgb")], space="srgb"))
CASES.append(case("blur in linearRGB space (the default)",
                  '<filter id="f"><feGaussianBlur stdDeviation="5"/></filter>',
                  '<g{F}><rect x="20" y="25" width="30" height="50" fill="#ff0000"/><rect x="50" y="25" width="30" height="50" fill="#0000ff"/></g>',
                  (20, 25, 60, 50), [dict(kind="blur", sx=5, sy=5)]))
CASES.append(case("offset",
                  '<filter id="f" x="0" y="0" width="2" height="2"><feOffset dx="12" dy="-8"/></filter>',
                  '<circle cx="35" cy="45" r="18" fill="#00a000"{F}/>', (17, 27, 36, 36),
                  [dict(kind="offset", dx=12, dy=-8)], region=(0, 0, 2, 2)))
CASES.append(case("flood in the silhouette of the source",
                  '<filter id="f"><feFlood flood-color="#2060c0" flood-opacity="0.6" result="c"/><feComposite in="c" in2="SourceAlpha" operator="in"/></filter>',
                  '<g{F}><circle cx="40" cy="45" r="20" fill="#ff8000"/><rect x="50" y="50" width="30" height="30" fill="#800080"/></g>', (20, 25, 60, 55),
                  [dict(kind="flood", color=(0x20 / 255, 0x60 / 255, 0xc0 / 255), opacity=0.6, result="c"),
                   dict(kind="composite", **{"in": "c", "in2": "SourceAlpha", "op": "in"})]))
CASES.append(case("drop shadow built from blur, offset, flood, composite and merge",
                  '<filter id="f" x="-20%" y="-20%" width="150%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="3" result="b"/><feOffset in="b" dx="6" dy="6" result="o"/>'
                  '<feFlood flood-color="#000000" flood-opacity="0.5" result="c"/><feComposite in="c" in2="o" operator="in" result="s"/>'
                  '<feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
                  '<g{F}><rect x="20" y="20" width="35" height="35" fill="#ffcc00"/><circle cx="62" cy="58" r="16" fill="#cc3300"/></g>', (20, 20, 58, 54),
                  [dict(kind="blur", sx=3, sy=3, **{"in": "SourceAlpha", "result": "b"}),
                   dict(kind="offset", dx=6, dy=6, **{"in": "b", "result": "o"}),
                   dict(kind="flood", color=(0, 0, 0), opacity=0.5, result="c"),
                   dict(kind="composite", **{"in": "c", "in2": "o", "op": "in", "result": "s"}),
                   dict(kind="merge", nodes=["s", "SourceGraphic"])], region=(-0.2, -0.2, 1.5, 1.5)))
CASES.append(case("feDropShadow",
                  '<filter id="f" x="-30%" y="-30%" width="180%" height="180%"><feDropShadow dx="5" dy="4" stdDeviation="2.5" flood-color="#800000" flood-opacity="0.8"/></filter>',
                  '<rect x="25" y="25" width="40" height="40" rx="8" fill="#e0e0ff"{F}/>', (25, 25, 40, 40),
                  [dict(kind="shadow", dx=5, dy=4, sx=2.5, sy=2.5, color=(0.5, 0, 0), opacity=0.8)], region=(-0.3, -0.3, 1.8, 1.8)))
MIXED = ('<g{F}><rect x="15" y="15" width="40" height="40" fill="#ff0000"/><circle cx="62" cy="55" r="22" fill="#00c000"/>'
         '<rect x="35" y="60" width="50" height="25" fill="#3040ff"/></g>')
for kind, values, label in (("saturate", [0.2], "saturate 0.2"), ("hueRotate", [120], "hueRotate 120"),
                            ("luminanceToAlpha", [], "luminanceToAlpha")):
    attrs = 'type="%s"' % kind + (' values="%s"' % values[0] if values else '')
    CASES.append(case("colour matrix: " + label,
                      '<filter id="f"><feColorMatrix %s/></filter>' % attrs, MIXED, (15, 15, 70, 70),
                      [dict(kind="matrix", type=kind, values=values)]))
CASES.append(case("colour matrix: a full 4x5 matrix (swap red and blue, halve alpha, lift green)",
                  '<filter id="f"><feColorMatrix type="matrix" values="0 0 1 0 0  0 1 0 0 0.1  1 0 0 0 0  0 0 0 0.5 0"/></filter>', MIXED, (15, 15, 70, 70),
                  [dict(kind="matrix", type="matrix", values=[0, 0, 1, 0, 0, 0, 1, 0, 0, 0.1, 1, 0, 0, 0, 0, 0, 0, 0, 0.5, 0])]))
BACKDROP = '<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffd040"/><stop offset="1" stop-color="#2040ff"/></linearGradient>'
for mode in ("multiply", "screen", "darken", "overlay", "difference", "hard-light", "color-dodge", "hue", "luminosity"):
    CASES.append(case("blend " + mode + " of a gradient square over a flood",
                      '<filter id="f"><feFlood flood-color="#80c040" flood-opacity="0.9" result="c"/><feBlend in="SourceGraphic" in2="c" mode="%s"/></filter>' % mode,
                      '<defs>' + BACKDROP + '</defs><rect x="20" y="20" width="60" height="60" fill="url(#g)"{F}/>', (20, 20, 60, 60),
                      [dict(kind="flood", color=(0x80 / 255, 0xc0 / 255, 0x40 / 255), opacity=0.9, result="c"),
                       dict(kind="blend", mode=mode, **{"in": "SourceGraphic", "in2": "c"})]))
for op in ("over", "in", "out", "atop", "xor"):
    CASES.append(case("composite " + op + " of the source and its offset copy",
                      '<filter id="f" x="-30%%" y="-30%%" width="160%%" height="160%%"><feOffset in="SourceGraphic" dx="9" dy="7" result="o"/><feComposite in="SourceGraphic" in2="o" operator="%s"/></filter>' % op,
                      '<circle cx="45" cy="45" r="22" fill="#cc2288"{F}/>', (23, 23, 44, 44),
                      [dict(kind="offset", dx=9, dy=7, **{"in": "SourceGraphic", "result": "o"}),
                       dict(kind="composite", op=op, **{"in": "SourceGraphic", "in2": "o"})], region=(-0.3, -0.3, 1.6, 1.6)))
CASES.append(case("composite arithmetic of the source and its blur",
                  '<filter id="f"><feGaussianBlur in="SourceGraphic" stdDeviation="3" result="b"/><feComposite in="SourceGraphic" in2="b" operator="arithmetic" k1="0" k2="1.5" k3="-0.5" k4="0"/></filter>',
                  '<g{F}><rect x="25" y="25" width="50" height="50" fill="#306090"/><circle cx="50" cy="50" r="14" fill="#f0e060"/></g>', (25, 25, 50, 50),
                  [dict(kind="blur", sx=3, sy=3, **{"in": "SourceGraphic", "result": "b"}),
                   dict(kind="composite", op="arithmetic", k=(0, 1.5, -0.5, 0), **{"in": "SourceGraphic", "in2": "b"})]))
CASES.append(case("merge of three offsets",
                  '<filter id="f" x="-30%" y="-30%" width="160%" height="160%"><feOffset dx="-10" dy="0" result="a"/><feOffset dx="10" dy="0" result="b"/>'
                  '<feMerge><feMergeNode in="a"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
                  '<rect x="38" y="35" width="24" height="30" fill="#40a040" fill-opacity="0.7"{F}/>', (38, 35, 24, 30),
                  [dict(kind="offset", dx=-10, dy=0, result="a"), dict(kind="offset", dx=10, dy=0, result="b"),
                   dict(kind="merge", nodes=["a", "b", "SourceGraphic"])], region=(-0.3, -0.3, 1.6, 1.6)))
CASES.append(case("user-space region clips the blur; a primitive subregion bounds a flood",
                  '<filter id="f" filterUnits="userSpaceOnUse" x="22.3" y="18.7" width="55.4" height="60.2"><feGaussianBlur stdDeviation="3.5" result="b"/>'
                  '<feFlood flood-color="#ffff00" x="30.5" y="30.5" width="20" height="10" result="y"/><feMerge><feMergeNode in="b"/><feMergeNode in="y"/></feMerge></filter>',
                  '<rect x="15" y="15" width="70" height="70" rx="12" fill="#3366aa"{F}/>', (15, 15, 70, 70),
                  [dict(kind="blur", sx=3.5, sy=3.5, result="b"),
                   dict(kind="flood", color=(1, 1, 0), result="y", sub=dict(x=30.5, y=30.5, w=20, h=10)),
                   dict(kind="merge", nodes=["b", "y"])], units="user", region=(22.3, 18.7, 55.4, 60.2)))
CASES.append(case("primitive units are fractions of the bounding box",
                  '<filter id="f" primitiveUnits="objectBoundingBox"><feGaussianBlur stdDeviation="0.08"/></filter>',
                  '<rect x="30" y="30" width="40" height="40" fill="#cc0066"{F}/>', (30, 30, 40, 40),
                  [dict(kind="blur", sx=0.08, sy=0.08)], prim_units="obb"))
CASES.append(case("the element's transform: the filter works in its own user space",
                  '<filter id="f" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3"/></filter>',
                  '<rect x="0" y="0" width="30" height="20" fill="#ff8000" transform="translate(30 25) scale(1.5 2)"{F}/>', (0, 0, 30, 20),
                  [dict(kind="blur", sx=3, sy=3)], ctm=(1.5, 2.0, 30, 25), region=(-0.2, -0.2, 1.4, 1.4)))
CASES.append(case("opacity and clip-path apply after the filter",
                  '<filter id="f"><feGaussianBlur stdDeviation="4"/></filter><clipPath id="c"><rect x="0" y="0" width="50" height="100"/></clipPath>',
                  '<rect x="30" y="30" width="40" height="40" fill="#0000ff" opacity="0.5" clip-path="url(#c)"{F}/>', (30, 30, 40, 40),
                  [dict(kind="blur", sx=4, sy=4)], src_body='<rect x="30" y="30" width="40" height="40" fill="#0000ff"/>', opacity=0.5, clip=(0, 0, 50, 100)))
CASES.append(case("an unknown filter draws nothing",
                  '', '<rect x="30" y="30" width="40" height="40" fill="#ff0000" filter="url(#missing)"/>', (30, 30, 40, 40), [], missing=True))

# Direct cross-check against cairosvg's own filters (offset, flood, blend), in sRGB as cairosvg works.
DIRECT = [
    ("cairosvg feOffset",
     H + '<defs><filter id="f" x="0" y="0" width="2" height="2"><feOffset dx="15" dy="9"/></filter></defs><rect x="20" y="25" width="30" height="30" fill="#ff0000" filter="url(#f)"/></svg>',
     dict(bbox=(20, 25, 30, 30), program=[dict(kind="offset", dx=15, dy=9)], region=(0, 0, 2, 2))),
]


def case_pixels_cross_check():
    for label, svg, spec in DIRECT:
        src = svg.replace(' filter="url(#f)"', '')
        c = dict(svg=svg, src=src, **spec)
        ref = reference_pixels(c)
        cairo = cairo_reference(svg)
        diff = np.abs(ref - cairo).mean() * 255
        print("cross-check %-28s mean difference %.2f/255" % (label, diff))
        assert diff < 2.5, (label, diff)


def neper_string(data):
    return "".join("\\x%02x" % b for b in data)


def neper_text(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    case_pixels_cross_check()
    lines = []
    for index, c in enumerate(CASES):
        if c.get("missing"):
            out = np.ones((SIDE, SIDE, 3))
        else:
            out = reference_pixels(c)
        ref = reduce_pixels(out)
        lines.append("    // %d: %s." % (index + 1, c["label"]))
        lines.append('    if !matches(a, device, "%s", "%s") { os.exit(%di32) }' % (neper_text(c["svg"]), neper_string(ref), index + 1))
    path = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "gfx_svg_filter", "src", "main.e")
    with open(path, encoding="utf-8") as f:
        src = f.read()
    a = src.index("    // BEGIN CASES")
    b = src.index("    // END CASES")
    new = src[:a] + "    // BEGIN CASES (scripts/gen_svg_filter_test.py)\n" + "\n".join(lines) + "\n" + src[b:]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(new)
    print("%d cases written" % len(CASES))


if __name__ == "__main__":
    main()
