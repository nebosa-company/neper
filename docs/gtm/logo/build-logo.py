#!/usr/bin/env python3
"""Generate the neper logo family, beside this script in docs/gtm/logo/.

    python docs/gtm/logo/build-logo.py

The mark is a lowercase italic 'e' -- Euler's number, which Napier (Neper in
its Latin form) put within reach, and the extension every neper source file
carries. It is drawn here rather than set in a font: one broad-nib model
produces the mark and the matching 'neper' wordmark from a shared skeleton, so
the two always share weight, contrast axis and slant, and no font licence or
outline conversion is involved.

SVG generation needs nothing but the standard library. PNG copies are written
too when reportlab is importable (it is, in .venv-docs-pdf).
"""

from __future__ import annotations

import math
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent          # docs/gtm/logo
REPO_ROOT = OUT_DIR.parents[2]

# --- palette ----------------------------------------------------------------
INK = "#1B3A6B"      # deep blue: the mark on light backgrounds
PAPER = "#FFFFFF"    # the mark reversed out of the icon tile

# --- writing grid -----------------------------------------------------------
XTOP, BASE = 140.0, 372.0            # x-height band
DESC = 486.0                         # descender depth for 'p'
R = (BASE - XTOP) / 2                # 116.0 -- bowl radius
MID = (XTOP + BASE) / 2              # 256.0

# Display pen: full contrast, for sizes above roughly 32 px.
PEN = dict(w_max=56.0, w_min=9.0, nib=-36.0, power=1.3, slant=12.0)
# Small-size pen: the hairlines are opened up so they survive an icon.
PEN_SMALL = dict(w_max=54.0, w_min=17.0, nib=-36.0, power=1.05, slant=12.0)


# --- geometry primitives ----------------------------------------------------
def line(p0, p1, n):
    return [(p0[0] + (p1[0] - p0[0]) * i / n,
             p0[1] + (p1[1] - p0[1]) * i / n) for i in range(n + 1)]


def arc(cx, cy, r, a0, a1, n):
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((cx + r * math.cos(a), cy - r * math.sin(a)))
    return out


def tangents(pts, closed=False):
    out, n = [], len(pts)
    for i in range(n):
        a = pts[(i - 1) % n] if closed else pts[max(0, i - 1)]
        b = pts[(i + 1) % n] if closed else pts[min(n - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        m = math.hypot(dx, dy) or 1.0
        out.append((dx / m, dy / m))
    return out


def smoothstep(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def slanted(pts, slant):
    """Italic slant about the x-height centre line, so the top leans right."""
    k = math.tan(math.radians(slant))
    return [(x - k * (y - MID), y) for (x, y) in pts]


def bar_thickness(pen):
    return pen["w_min"] + (pen["w_max"] - pen["w_min"]) * 0.44


def widths_for(pts, closed=False, taper=None, pen=PEN):
    """Broad-nib width per sample. taper = (share of the run, end factor)."""
    out, tg, n = [], tangents(pts, closed), len(pts)
    for i, t in enumerate(tg):
        psi = math.atan2(t[1], t[0])
        s = abs(math.sin(psi - math.radians(pen["nib"])))
        w = pen["w_min"] + (pen["w_max"] - pen["w_min"]) * s ** pen["power"]
        if taper:
            span, end = taper
            u = (n - 1 - i) / (n - 1) / span
            if u < 1.0:
                w *= end + (1 - end) * smoothstep(u)
        out.append(w)
    return out


def _cut(edge, anchor, tangent, axis):
    """Slide an outline end point along the stroke onto a flat cut line."""
    i = 0 if axis == "v" else 1
    if abs(tangent[i]) < 1e-6:
        return edge
    t = (anchor[i] - edge[i]) / tangent[i]
    return (edge[0] + tangent[0] * t, edge[1] + tangent[1] * t)


def offset(pts, widths, closed=False, cuts=(None, None)):
    """Open stroke -> one contour; closed stroke -> outer + inner contours.

    cuts = (start, end), each None, "h" or "v": square that end off on the
    given axis instead of perpendicular to the stroke, the way an italic
    stem meets the baseline.
    """
    tg = tangents(pts, closed)
    left, right = [], []
    for p, t, w in zip(pts, tg, widths):
        nx, ny = -t[1], t[0]
        left.append((p[0] + nx * w / 2, p[1] + ny * w / 2))
        right.append((p[0] - nx * w / 2, p[1] - ny * w / 2))
    if closed:
        return [left, right[::-1]]
    for index, axis in ((0, cuts[0]), (-1, cuts[1])):
        if axis:
            left[index] = _cut(left[index], pts[index], tg[index], axis)
            right[index] = _cut(right[index], pts[index], tg[index], axis)
    return [left + right[::-1]]


def stroke(pts, closed=False, taper=None, pen=PEN, cuts=(None, None)):
    pts = slanted(pts, pen["slant"])
    return offset(pts, widths_for(pts, closed, taper, pen), closed, cuts)


# --- letters ----------------------------------------------------------------
# (reach, rise, end width as a fraction of the bowl's, samples)
SWASH = (1.30, 0.60, 0.09, 30)
# Shorter and blunter, so the tail still reads at icon sizes.
SWASH_SMALL = (0.95, 0.46, 0.24, 30)


def glyph_e(a_end=300.0, taper=(0.13, 0.72), pen=PEN, swash=SWASH):
    """Single-storey italic e: a crossbar and a bowl of about 310 degrees.

    The bowl starts just below the bar, at exactly the bar's lower edge, so
    the two meet in one clean horizontal cut on the right. Its terminal then
    keeps going as a rising tail -- the exponential curve the letter names.
    """
    thick = bar_thickness(pen)
    a_start = -math.degrees(math.asin((thick / 2) / R))
    pts = slanted(arc(R, MID, R, a_start, a_end, 80), pen["slant"])
    widths = widths_for(pts, taper=taper, pen=pen)
    if swash:
        reach, rise, tail_w, steps = swash
        p0, t0, w0 = pts[-1], tangents(pts)[-1], widths[-1]
        p3 = (p0[0] + reach * R, p0[1] - rise * R)
        p1 = (p0[0] + t0[0] * 0.50 * R, p0[1] + t0[1] * 0.50 * R)
        p2 = (p3[0] - 0.42 * R, p3[1] + 0.10 * R)
        for i in range(1, steps + 1):
            u, v = i / steps, 1 - i / steps
            pts.append((v ** 3 * p0[0] + 3 * v * v * u * p1[0]
                        + 3 * v * u * u * p2[0] + u ** 3 * p3[0],
                        v ** 3 * p0[1] + 3 * v * v * u * p1[1]
                        + 3 * v * u * u * p2[1] + u ** 3 * p3[1]))
            widths.append(w0 * (tail_w + (1 - tail_w) * (1 - smoothstep(u))))
    bowl = offset(pts, widths, cuts=("h", None))
    bar_pts = slanted(line((0.0, MID), (2 * R, MID), 16), pen["slant"])
    bar = offset(bar_pts, [thick] * len(bar_pts), cuts=(None, "v"))
    return [bowl, bar], 2 * R + pen["w_max"] * 0.62


def glyph_n(r=97.0, pen=PEN):
    stem = line((0.0, XTOP), (0.0, BASE), 20)
    shoulder = arc(r, XTOP + r, r, 186.0, 0.0, 40)
    shoulder += line((2 * r, XTOP + r), (2 * r, BASE), 18)[1:]
    return ([stroke(stem, pen=pen, cuts=("h", "h")),
             stroke(shoulder, pen=pen, cuts=(None, "h"))],
            2 * r + pen["w_max"] * 0.62)


def glyph_p(pen=PEN):
    stem = line((0.0, XTOP), (0.0, DESC), 26)
    bowl = arc(R, MID, R, 180.0, -180.0, 84)[:-1]
    return ([stroke(stem, pen=pen, cuts=("h", "h")),
             stroke(bowl, closed=True, pen=pen)],
            2 * R + pen["w_max"] * 0.62)


def glyph_r(r=94.0, pen=PEN):
    stem = line((0.0, XTOP), (0.0, BASE), 20)
    arm = arc(r, XTOP + r, r, 186.0, 34.0, 34)
    return ([stroke(stem, pen=pen, cuts=("h", "h")),
             stroke(arm, taper=(0.40, 0.34), pen=pen)],
            r + pen["w_max"] * 0.95)


def mark(pen=PEN, swash=SWASH):
    return glyph_e(pen=pen, swash=swash)[0]


def stem_width(pen):
    """Width the pen gives a vertical stem -- the join target for a tail."""
    pts = slanted(line((0.0, XTOP), (0.0, BASE), 4), pen["slant"])
    return widths_for(pts, pen=pen)[2]


def tail_origin(pen, a_end=300.0):
    """Where the bowl ends and the tail begins, in glyph coordinates."""
    thick = bar_thickness(pen)
    a_start = -math.degrees(math.asin((thick / 2) / R))
    return slanted(arc(R, MID, R, a_start, a_end, 80), pen["slant"])[-1]


def wordmark(pen=PEN, gap=34.0, join=0.5):
    """n-e-p-e-r, with both e's carrying the tail.

    Spacing is one constant gap between the letters' ink, measured with each
    e's tail excluded, so the rhythm of the word is even. The tail then
    overlaps the letter that follows, and its reach is solved so the tip lands
    `join` of the way into that letter's stem: it reads as an italic join
    rather than a collision or an amputated flourish.
    """
    builds = (glyph_n, glyph_e, glyph_p, glyph_e, glyph_r)
    cores = [(glyph_e(pen=pen, swash=None) if b is glyph_e else b(pen=pen))[0]
             for b in builds]

    origins, x = [], 0.0
    for i, core in enumerate(cores):
        origins.append(x)
        if i + 1 < len(cores):
            x = bbox(shift(core, x))[2] + gap - bbox(cores[i + 1])[0]

    reach0, rise0, tail_w, steps = SWASH
    p0x = tail_origin(pen)[0]
    shapes = []
    for i, build in enumerate(builds):
        if build is not glyph_e:
            shapes += shift(build(pen=pen)[0], origins[i])
            continue
        if i + 1 < len(builds):
            target = (origins[i + 1] + bbox(cores[i + 1])[0]
                      + join * stem_width(pen))
            reach = (target - origins[i] - p0x) / R
        else:
            reach = reach0
        rise = rise0 * reach / reach0
        shapes += shift(glyph_e(pen=pen,
                                swash=(reach, rise, tail_w, steps))[0],
                        origins[i])
    return shapes


# --- layout -----------------------------------------------------------------
def shift(shapes, dx, dy=0.0):
    return [[[(x + dx, y + dy) for (x, y) in c] for c in s] for s in shapes]


def bbox(shapes):
    pts = [p for s in shapes for c in s for p in c]
    return (min(p[0] for p in pts), min(p[1] for p in pts),
            max(p[0] for p in pts), max(p[1] for p in pts))


def transform(shapes, scale, ox, oy):
    return [[[(x * scale + ox, y * scale + oy) for (x, y) in c] for c in s]
            for s in shapes]


def fit(shapes, w, h, pad, core=None):
    """Scale and centre shapes inside a w x h box with pad on every side.

    With `core`, centring follows that subset -- the letter body, ignoring the
    hairline tail, which carries little visual weight -- while the scale and a
    final clamp still keep all the ink inside the box.
    """
    x0, y0, x1, y1 = bbox(shapes)
    sw, sh = x1 - x0, y1 - y0
    s = min((w - 2 * pad) / sw, (h - 2 * pad) / sh)
    if core is None:
        return transform(shapes, s, (w - sw * s) / 2 - x0 * s,
                         (h - sh * s) / 2 - y0 * s)
    cx0, cy0, cx1, cy1 = bbox(core)
    ox = w / 2 - s * (cx0 + cx1) / 2
    oy = h / 2 - s * (cy0 + cy1) / 2
    ox = min(max(ox, pad - s * x0), w - pad - s * x1)
    oy = min(max(oy, pad - s * y0), h - pad - s * y1)
    return transform(shapes, s, ox, oy)


# --- SVG --------------------------------------------------------------------
CORNER_COS = math.cos(math.radians(38.0))


def dedupe(points, epsilon=0.01):
    out = []
    for p in points:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > epsilon:
            out.append(p)
    while len(out) > 1 and math.hypot(out[0][0] - out[-1][0],
                                     out[0][1] - out[-1][1]) <= epsilon:
        out.pop()
    return out


def corners_of(points):
    """Vertices where the contour turns sharply: a flat cut, not a curve."""
    n = len(points)
    flags = []
    for i in range(n):
        ax, ay = (points[i][0] - points[i - 1][0],
                  points[i][1] - points[i - 1][1])
        bx, by = (points[(i + 1) % n][0] - points[i][0],
                  points[(i + 1) % n][1] - points[i][1])
        la, lb = math.hypot(ax, ay), math.hypot(bx, by)
        if la < 1e-9 or lb < 1e-9:
            flags.append(True)
            continue
        flags.append((ax * bx + ay * by) / (la * lb) < CORNER_COS)
    return flags


def cubic_path(points):
    """Closed Catmull-Rom through the contour, emitted as SVG cubics.

    Tangents are clamped at corners so the spline cannot overshoot a squared
    stroke end into a bulge.
    """
    points = dedupe(points)
    n = len(points)
    sharp = corners_of(points)
    out = ["M %.2f %.2f" % points[0]]
    for i in range(n):
        p0, p1 = points[(i - 1) % n], points[i % n]
        p2, p3 = points[(i + 1) % n], points[(i + 2) % n]
        if sharp[i % n]:
            c1 = (p1[0] + (p2[0] - p1[0]) / 3.0, p1[1] + (p2[1] - p1[1]) / 3.0)
        else:
            c1 = (p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0)
        if sharp[(i + 1) % n]:
            c2 = (p2[0] - (p2[0] - p1[0]) / 3.0, p2[1] - (p2[1] - p1[1]) / 3.0)
        else:
            c2 = (p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0)
        out.append("C %.2f %.2f %.2f %.2f %.2f %.2f"
                   % (c1[0], c1[1], c2[0], c2[1], p2[0], p2[1]))
    return " ".join(out) + " Z"


def paths(shapes, fill):
    out = []
    for shape in shapes:
        d = " ".join(cubic_path(c) for c in shape)
        rule = ' fill-rule="evenodd"' if len(shape) > 1 else ""
        out.append('  <path fill="%s"%s d="%s"/>' % (fill, rule, d))
    return out


def svg_document(width, height, body, label):
    return ('<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 %g %g" width="%g" height="%g" '
            'role="img" aria-label="%s">\n%s\n</svg>\n'
            % (width, height, width, height, label, "\n".join(body)))


# --- the deliverables -------------------------------------------------------
def build_mark(fill=INK, box=512.0, pad=30.0, pen=PEN, swash=SWASH):
    shapes = fit(mark(pen=pen, swash=swash), box, box, pad,
                 core=mark(pen=pen, swash=None))
    return svg_document(box, box, paths(shapes, fill), "neper")


def small_mark(pen=PEN_SMALL, swash=SWASH_SMALL, box=512.0, pad=30.0):
    """The mark at the icon cut, without a tile: for headers and small sizes."""
    return fit(mark(pen=pen, swash=swash), box, box, pad,
               core=mark(pen=pen, swash=None))


def build_wordmark(fill=INK, height=320.0, pad=24.0):
    shapes = wordmark()
    x0, y0, x1, y1 = bbox(shapes)
    scale = (height - 2 * pad) / (y1 - y0)
    width = (x1 - x0) * scale + 2 * pad
    shapes = transform(shapes, scale, pad - x0 * scale, pad - y0 * scale)
    return svg_document(width, height, paths(shapes, fill), "neper")


def icon_tile(box=512.0, radius_ratio=0.22, inset=0.15, bg=INK, fg=PAPER):
    """Rounded-square app icon with the mark reversed out."""
    body = ['  <rect width="%g" height="%g" rx="%g" ry="%g" fill="%s"/>'
            % (box, box, box * radius_ratio, box * radius_ratio, bg)]
    glyph = fit(mark(pen=PEN_SMALL, swash=SWASH_SMALL), box, box, box * inset,
                core=mark(pen=PEN_SMALL, swash=None))
    body += paths(shift(glyph, -box * 0.012), fg)
    return body


def build_icon(box=512.0):
    return svg_document(box, box, icon_tile(box), "neper")


def lockup_layout(tile=400.0, gap_ratio=0.40, pad=30.0):
    """Icon tile at the left, wordmark centred on the tile's midline.

    Returns (width, height, tile_origin, tile, glyph_shapes, word_shapes),
    with the tile's own contour available from rounded_rect.
    """
    gap = tile * gap_ratio
    word = shift(wordmark(), 0.0, 0.0)
    x0, _y0, _x1, _y1 = bbox(word)
    word = shift(word, tile + gap - x0, tile / 2 - MID)
    glyph = shift(fit(mark(pen=PEN_SMALL, swash=SWASH_SMALL), tile, tile,
                      tile * 0.15, core=mark(pen=PEN_SMALL, swash=None)),
                  -tile * 0.012)

    tx0, ty0, tx1, ty1 = 0.0, 0.0, tile, tile
    wx0, wy0, wx1, wy1 = bbox(word)
    x_min, y_min = min(tx0, wx0), min(ty0, wy0)
    width = max(tx1, wx1) - x_min + 2 * pad
    height = max(ty1, wy1) - y_min + 2 * pad
    dx, dy = pad - x_min, pad - y_min
    return (width, height, (dx, dy), tile,
            shift(glyph, dx, dy), shift(word, dx, dy))


def build_lockup(fill=INK):
    width, height, (tx, ty), tile, glyph, word = lockup_layout()
    radius = tile * 0.22
    body = ['  <rect x="%g" y="%g" width="%g" height="%g" rx="%g" ry="%g" '
            'fill="%s"/>' % (tx, ty, tile, tile, radius, radius, fill)]
    body += paths(glyph, PAPER)
    body += paths(word, fill)
    return svg_document(round(width), round(height), body, "neper")


# --- PNG ---------------------------------------------------------------------
# A small anti-aliased scanline rasteriser, so PNG copies need no native
# imaging library. Contours are filled by the nonzero winding rule, which is
# what the stroke outlines and the ring of 'p' are built for.
SUBSAMPLES = 5


def coverage(shapes, width, height):
    """Per-pixel coverage in [0, 1] for a list of contour lists."""
    edges = []
    for shape in shapes:
        for contour in shape:
            for i in range(len(contour)):
                x0, y0 = contour[i]
                x1, y1 = contour[(i + 1) % len(contour)]
                if y0 != y1:
                    edges.append((min(y0, y1), max(y0, y1), x0, y0, x1, y1))
    rows = []
    for py in range(height):
        acc = [0.0] * width
        for sub in range(SUBSAMPLES):
            sy = py + (sub + 0.5) / SUBSAMPLES
            hits = []
            for ymin, ymax, x0, y0, x1, y1 in edges:
                if ymin <= sy < ymax:
                    hits.append((x0 + (x1 - x0) * (sy - y0) / (y1 - y0),
                                 1 if y1 > y0 else -1))
            if not hits:
                continue
            hits.sort()
            winding, span_start = 0, 0.0
            for x, direction in hits:
                if winding == 0:
                    span_start = x
                winding += direction
                if winding == 0:
                    add_span(acc, span_start, x, width)
        rows.append([a / SUBSAMPLES for a in acc])
    return rows


def add_span(acc, xa, xb, width):
    xa, xb = max(0.0, xa), min(float(width), xb)
    if xb <= xa:
        return
    first, last = int(xa), min(int(xb), width - 1)
    if first == last:
        acc[first] += xb - xa
        return
    acc[first] += first + 1 - xa
    for px in range(first + 1, last):
        acc[px] += 1.0
    acc[last] += xb - last


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def write_png(path, width, height, pixels):
    """pixels: rows of (r, g, b, a) tuples."""
    import struct
    import zlib

    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                     + chunk(b"IEND", b""))


def render_png(name, width, height, layers):
    """layers: [(shapes, colour)] painted in order over transparency."""
    width, height = int(round(width)), int(round(height))
    painted = [coverage(shapes, width, height) for shapes, _c in layers]
    colours = [rgb(colour) for _s, colour in layers]
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            pr = pg = pb = pa = 0.0
            for (cr, cg, cb), cov in zip(colours, painted):
                a = cov[y][x]
                if a <= 0.0:
                    continue
                inv = 1.0 - a
                pr = cr * a + pr * inv
                pg = cg * a + pg * inv
                pb = cb * a + pb * inv
                pa = a + pa * inv
            if pa <= 0.0:
                row.append((0, 0, 0, 0))
            else:
                row.append((int(pr / pa + 0.5), int(pg / pa + 0.5),
                            int(pb / pa + 0.5), int(pa * 255 + 0.5)))
        rows.append(row)
    target = OUT_DIR / name
    write_png(target, width, height, rows)
    return target


def rounded_rect(width, height, radius, steps=16):
    """Contour of a rounded rectangle, for the icon tile's alpha."""
    pts = []
    corners = ((width - radius, height - radius, 0.0),
               (radius, height - radius, 90.0),
               (radius, radius, 180.0),
               (width - radius, radius, 270.0))
    for cx, cy, a0 in corners:
        for i in range(steps + 1):
            a = math.radians(a0 + 90.0 * i / steps)
            pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return pts


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    documents = {
        "neper-mark.svg": build_mark(),
        "neper-mark-mono.svg": build_mark(fill="currentColor"),
        "neper-mark-small.svg": build_mark(pen=PEN_SMALL, swash=SWASH_SMALL),
        "neper-wordmark.svg": build_wordmark(),
        "neper-icon.svg": build_icon(),
        "neper-lockup.svg": build_lockup(),
    }
    for name, text in documents.items():
        (OUT_DIR / name).write_text(text, encoding="utf-8")
        print("wrote %s" % (OUT_DIR / name).relative_to(REPO_ROOT).as_posix())

    icon_glyph = shift(fit(mark(pen=PEN_SMALL, swash=SWASH_SMALL), 512, 512,
                           512 * 0.15, core=mark(pen=PEN_SMALL, swash=None)),
                       -512 * 0.012)
    width, height, (tx, ty), tile, glyph, word = lockup_layout()
    raster = [
        ("neper-mark.png", 512, 512,
         [(fit(mark(), 512, 512, 30, core=mark(swash=None)), INK)]),
        ("neper-mark-small.png", 512, 512, [(small_mark(), INK)]),
        ("neper-icon.png", 512, 512,
         [([[rounded_rect(512, 512, 512 * 0.22)]], INK),
          (icon_glyph, PAPER)]),
        ("neper-lockup.png", width, height,
         [(shift([[rounded_rect(tile, tile, tile * 0.22)]], tx, ty), INK),
          (glyph, PAPER), (word, INK)]),
    ]
    for name, w, h, layers in raster:
        path = render_png(name, w, h, layers)
        print("wrote %s" % path.relative_to(REPO_ROOT).as_posix())


if __name__ == "__main__":
    main()
