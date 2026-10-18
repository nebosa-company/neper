"""Probe fonts for the ClearType rasteriser: unhinted glyphs of known geometry, so GDI's pixels show how it samples an outline.

python probe_fonts.py <outdir>

Each font (NProbe0, NProbe1, ...) has up to 191 glyphs on the codes 32..126 and 160..255, upem 1024, no instructions at all. At 16 px per em one font unit
is exactly 1/64 pixel, so a coordinate in the JSON is the 26.6 position the rasteriser gets. Shapes live between x 2 and 12 pixels and y 1 and
11 pixels above the baseline; the pen is at x 0 and the advance is 16 pixels. <outdir>/probe.json lists, per font, the glyph on each code as
a list of contours of [x, y, on] in font units.

Sets: left and right edge of a rectangle swept over a pixel in 64ths (xl, xr), top and bottom edge (yt, yb), thin vertical and horizontal
bars (width 1..64 64ths at four phases), parallelograms of slopes dx/dy, and discs swept in x and y.
"""
import json
import math
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables import ttProgram

UPEM = 1024
PX = 64  # font units per pixel at 16 ppem


# U+0080..U+009F are skipped: GDI does not draw the font's glyph for a C1 control
CODES = list(range(32, 127)) + list(range(160, 256))


def rect(x0, y0, x1, y1):
    return [[(x0, y0, 1), (x0, y1, 1), (x1, y1, 1), (x1, y0, 1)]]  # clockwise for TrueType: outer contours run clockwise


def poly(points):
    return [[(x, y, 1) for x, y in points]]


def disc(cx, cy, r):
    """A circle of radius r as eight off-curve points (a quadratic spline whose on-curve points are implied midpoints)."""
    k = r * math.tan(math.pi / 8)
    pts = []
    for q in range(8):
        a = -q * math.pi / 4  # clockwise
        # off-curve point at the corner of the octagon around the circle
        ang = a - math.pi / 8
        rr = r / math.cos(math.pi / 8)
        pts.append((int(round(cx + rr * math.cos(ang))), int(round(cy + rr * math.sin(ang))), 0))
    return [pts]


def build_sets():
    sets = []
    # horizontal edge positions: left/right edges
    sets.append(("xl", [rect(2 * PX + i, 1 * PX, 8 * PX, 11 * PX) for i in range(64)]))
    sets.append(("xr", [rect(2 * PX, 1 * PX, 5 * PX + i, 11 * PX) for i in range(64)]))
    # vertical edge positions: top/bottom edges (rows are 64 high, centre at +32)
    sets.append(("yt", [rect(2 * PX, 1 * PX, 8 * PX, 5 * PX + i) for i in range(64)]))
    sets.append(("yb", [rect(2 * PX, 1 * PX + i, 8 * PX, 5 * PX) for i in range(64)]))
    # thin vertical bars: width w (1..64) at phases p = 0, 16, 32, 48
    sets.append(("vb", [rect(2 * PX + p, 1 * PX, 2 * PX + p + w, 9 * PX) for p in (0, 16, 21, 32, 48) for w in range(1, 33)]))
    # thin horizontal bars: height h at phases
    sets.append(("hb", [rect(2 * PX, 2 * PX + p, 8 * PX, 2 * PX + p + h) for p in (0, 16, 32, 48) for h in range(1, 33)]))
    # parallelograms: left edge slanted by dx over the height (negative and positive), width 3 px
    sets.append(("pg", [poly([(2 * PX + s0, 1 * PX), (2 * PX + s0 + dx, 11 * PX), (5 * PX + s0 + dx, 11 * PX), (5 * PX + s0, 1 * PX)]) for dx in (8, 16, 24, 32, 40, 64, 96, 128) for s0 in (0, 5, 11, 16, 21, 27, 32, 37)]))
    # discs swept in x and y (radius 4 px and 2.5 px)
    sets.append(("dx", [disc(7 * PX + i, 6 * PX, 4 * PX) for i in range(0, 64)] + [disc(7 * PX + i, 6 * PX, 5 * PX // 2) for i in range(0, 64)]))
    sets.append(("dy", [disc(7 * PX, 6 * PX + i, 4 * PX) for i in range(0, 64)] + [disc(7 * PX, 6 * PX + i, 5 * PX // 2) for i in range(0, 64)]))
    # partial rows: a rectangle whose left edge sweeps a pixel while its top edge leaves m of the row's five sample lines inside
    # (lines at .1 .3 .5 .7 .9 of the row), and the same from the bottom edge
    tops = {1: 14, 2: 24, 3: 38, 4: 52}  # 5 + t/64
    for m, t in tops.items():
        sets.append(("xlt%d" % m, [rect(2 * PX + i, 1 * PX, 8 * PX, 5 * PX + t) for i in range(64)]))
    bots = {1: 52, 2: 38, 3: 24, 4: 14}  # 1 + b/64: lines above b/64 stay inside
    for m, b in bots.items():
        sets.append(("xlb%d" % m, [rect(2 * PX + i, 1 * PX + b, 8 * PX, 5 * PX) for i in range(64)]))
    return sets


def save_font(path, family, glyph_defs):
    names = [".notdef"] + ["g%d" % i for i in range(len(glyph_defs))]
    glyphs = {}
    pen = TTGlyphPen(None)
    glyphs[".notdef"] = pen.glyph()
    metrics = {".notdef": (16 * PX, 0)}
    cmap = {}
    for i, contours in enumerate(glyph_defs):
        pen = TTGlyphPen(None)
        xs = []
        for c in contours:
            pts = c
            # build with explicit on/off flags through a plain glyph object
        from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates
        g = Glyph()
        coords = []
        flags = []
        ends = []
        for c in contours:
            for (x, y, on) in c:
                coords.append((x, y))
                flags.append(1 if on else 0)
            ends.append(len(coords) - 1)
        g.numberOfContours = len(contours)
        g.coordinates = GlyphCoordinates(coords)
        g.flags = flags
        g.endPtsOfContours = ends
        g.program = None
        prog = ttProgram.Program()
        prog.fromBytecode(b"")
        g.program = prog
        glyphs["g%d" % i] = g
        xmin = min(x for c in contours for (x, y, on) in c)
        metrics["g%d" % i] = (16 * PX, xmin)
        cmap[CODES[i]] = "g%d" % i
    fb = FontBuilder(UPEM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=16 * PX, descent=-4 * PX)
    fb.setupNameTable({"familyName": family, "styleName": "Regular", "uniqueFontIdentifier": family + "-Regular", "fullName": family, "psName": family + "-Regular", "version": "Version 1.0"})
    fb.setupOS2(sTypoAscender=16 * PX, sTypoDescender=-4 * PX, usWinAscent=16 * PX, usWinDescent=4 * PX, fsType=0)
    fb.setupPost()
    # a trivial prep and fpgm, so that a hinter that wants instructions to run has some (they do nothing)
    from fontTools.ttLib import newTable
    for tag in ("fpgm", "prep"):
        t = newTable(tag)
        t.program = ttProgram.Program()
        t.program.fromBytecode(bytes([0xB0, 0x00, 0x21]))  # PUSHB[1] 0, POP
        fb.font[tag] = t
    fb.font["head"].flags = 0b1011  # baseline at y 0, lsb at x 0, force integer ppem
    fb.save(path)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    flat = []
    for name, glyphs in build_sets():
        for i, g in enumerate(glyphs):
            flat.append((name, i, g))
    manifest = []
    for fi in range(0, (len(flat) + len(CODES) - 1) // len(CODES)):
        chunk = flat[fi * len(CODES):(fi + 1) * len(CODES)]
        family = "NProbe%d" % fi
        save_font(os.path.join(out, family + ".ttf"), family, [g for _, _, g in chunk])
        manifest.append({"family": family, "codes": CODES[:len(chunk)], "glyphs": [{"set": n, "index": i, "contours": g} for n, i, g in chunk]})
    json.dump(manifest, open(os.path.join(out, "probe.json"), "w"))
    print(len(flat), "glyphs in", len(manifest), "fonts")


main()
