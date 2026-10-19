"""A tap font: a copy of a TrueType font whose every glyph can be read back, point by point, from the pixels GDI draws.

python tapfont.py <src.ttf> <out.ttf> <family> <ppem> [none | cut=K | cutiup=K]

`cut=K` keeps only each glyph program's first K instructions that are not pushes (a CALL is one), the state of the hinter part way through;
`cut=iupx` keeps what comes before the first IUP[x]; `cutiup=K` keeps the first K and then runs IUP[x] on what they left.
`none` drops the real glyphs' own programs, so the tap reads the state the hinter starts a glyph from (scaled points, rounded phantom points).

GDI does not hand out the ClearType-hinted outline (GetGlyphOutline answers with the black-and-white machine), so the hinted positions are
read through the hinter itself, in two steps that need nothing but the font.

1. Every glyph with points gets a tail on its own program: after the glyph's instructions have run, GC reads the hinted coordinate of each
   point (26.6, x then y) and WS leaves it in a storage slot of its own. The glyph is otherwise untouched, so it is hinted and drawn as the
   plain font's glyph is (the tap font's atlas cells equal the oracle's for the same font and size, which the reader checks).
2. Two more glyphs per code, the readers (U+E000 + code - 32 for the six low bits of each value, U+E100 + code - 32 for the six bits of
   whole pixels + 16), are fields of small squares with a program that reads the slots back: for each bit b of the value v, MUL and FLOOR
   leave 64 or 0 on the stack, which SHPIX turns into a shift of 3 pixels or none of one square. The reader is drawn after the glyph it reads, and the storage the glyph wrote is still there: GDI runs a glyph program
   against the size's one storage area.

A square sits either in its slot or three pixels above it, and the drawn pixels say which: the low six bits of every hinted coordinate,
exact to 1/64 pixel, and with the second reader the whole value (-16 to 47 pixels).

The squares are two pixels wide at `ppem` (font units are scaled by upem / ppem), pitch three, 40 slots to a row, from 20 pixels right of
the pen, rows six pixels apart going down from 100 pixels above the baseline (a 200 x 210 pixel cell with the baseline at 110 holds them;
GDI draws nothing of a glyph wider than about 150 pixels).
The font's vertical extent is widened to hold them: GDI draws no glyph that leaves it. Slot s of a glyph holds bit s % 6 of coordinate
(s // 6) % 2 of point s // 12; `slot_origin()` is the one place that knows.
"""
import sys

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import ttProgram
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates

BITS = 6
SLOTS_PER_ROW = 40
DOT = 2.0       # px
PITCH = 3.0     # px between slots, and between the two positions of a slot
ROW = 6.0       # px between rows of slots
X0 = 20.0       # px right of the pen
Y0 = 100.0      # px: the top row of slots is this far above the baseline
FUNCTION = 200
# The reader's scratch (three slots) and the glyphs' readouts live in storage above the font's own (the font's programs use the
# low slots and storage is not reset between glyphs).
READER_BASE = 0xE000
READER_HI = 0xE100
CVT_LO = 0xE200
CVT_HI = 0xE300
CVT_CHUNK = 100


def slot_origin(s):
    """Pixel offset (from the pen, from the baseline, y up) of the lower left corner of the square at bit slot s in its resting place."""
    col, row = s % SLOTS_PER_ROW, s // SLOTS_PER_ROW
    return X0 + col * PITCH, Y0 - row * ROW


def push(values):
    out = bytearray()
    i = 0
    while i < len(values):
        chunk = values[i:i + 8]
        i += 8
        if all(0 <= v <= 255 for v in chunk):
            out.append(0xB0 + len(chunk) - 1)
            out += bytes(chunk)
        else:
            out.append(0xB8 + len(chunk) - 1)
            for v in chunk:
                out += (v & 0xFFFF).to_bytes(2, "big")
    return bytes(out)


SPVTCA_Y, SPVTCA_X, SFVTCA_Y = 0x02, 0x03, 0x04
SLOOP, GC0, WS, RS, MUL, FLOOR, ADD, SUB, DUP, SWAP, SHPIX, FDEF, ENDF, CALL, RCVT, GETINFO, MPPEM = 0x17, 0x46, 0x42, 0x43, 0x63, 0x66, 0x60, 0x61, 0x20, 0x23, 0x38, 0x2C, 0x2D, 0x2B, 0x45, 0x88, 0x4B
SVTCA_Y, SVTCA_X = 0x00, 0x01
# GETINFO selectors asked in turn, after the control values (the answers follow the table in the readout)
INFO_SELECTORS = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8191]


def reader_function(t0):
    """fpgm addition: function 200 takes (d0, K) with K = 4096 >> b and shifts the four points d0..d0+3 up by 3 pixels when bit b of the
    value in storage[t0] is set (SHPIX by 3 * (FLOOR(v * K / 64) - 2 * FLOOR(v * (K / 2) / 64)) / 64 * 64)."""
    code = bytearray(push([FUNCTION]) + bytes([FDEF]))
    code += push([t0 + 1]) + bytes([SWAP, WS]) + push([t0 + 2]) + bytes([SWAP, WS])  # storage[t0 + 1] = K, storage[t0 + 2] = d0
    code += push([4]) + bytes([SLOOP])
    code += push([t0 + 2]) + bytes([RS])
    for k in (1, 2, 3):
        code += push([t0 + 2]) + bytes([RS]) + push([k]) + bytes([ADD])
    code += push([t0]) + bytes([RS]) + push([t0 + 1]) + bytes([RS, MUL, FLOOR])
    code += push([t0]) + bytes([RS]) + push([t0 + 1]) + bytes([RS]) + push([32]) + bytes([MUL, MUL, FLOOR])
    code += bytes([DUP, ADD, SUB]) + push([192]) + bytes([MUL, SHPIX, ENDF])
    return bytes(code)


def tail_program(npoints, base):
    """Appended to a glyph's program: leaves the hinted coordinates in storage[base + 2 p + axis]."""
    code = bytearray()
    for axis in (0, 1):
        code.append(SPVTCA_X if axis == 0 else SPVTCA_Y)
        for p in range(npoints):
            code += push([base + 2 * p + axis, p]) + bytes([GC0, WS])
    return bytes(code)


def cvt_tail(count, base):
    """Appended to one glyph's program: leaves cvt[i] in storage[base + 2 i] and storage[base + 2 i + 1] (the readers read points of x and y)."""
    code = bytearray()
    for i in range(count):
        for axis in (0, 1):
            code += push([base + 2 * i + axis, i]) + bytes([RCVT, WS])
    return bytes(code)


def info_tail(base):
    """Leaves GETINFO's answers (INFO_SELECTORS) and MPPEM along x and along y in storage[base + 2 i] (and + 1)."""
    code = bytearray()
    for i, sel in enumerate(INFO_SELECTORS):
        for axis in (0, 1):
            code += push([base + 2 * i + axis, sel]) + bytes([GETINFO, WS])
    k = len(INFO_SELECTORS)
    for j, svtca in enumerate((SVTCA_X, SVTCA_Y)):
        for axis in (0, 1):
            code += bytes([svtca]) + push([base + 2 * (k + j) + axis]) + bytes([MPPEM, WS])
    return bytes(code)


def storage_tail(count, base):
    code = bytearray()
    for i in range(count):
        for axis in (0, 1):
            code += push([base + 2 * i + axis, i]) + bytes([RS, WS])
    return bytes(code)


def reader_program(npoints, base, t0, level=0):
    code = bytearray([SFVTCA_Y])
    for p in range(npoints):
        for axis in (0, 1):
            code += push([base + 2 * p + axis]) + bytes([RS])
            for _ in range(level):  # u >> 6: FLOOR(u) is a multiple of 64, MUL by 1 (1/64) divides it by 64
                code += bytes([FLOOR]) + push([1]) + bytes([MUL])
            if level:
                code += push([16]) + bytes([ADD])  # biased, so that a negative value fits six bits
            code += push([t0]) + bytes([SWAP, WS])
            for b in range(BITS):
                s = (p * 2 + axis) * BITS + b
                code += bytes([0xBA]) + (4 * s).to_bytes(2, "big") + (4096 >> b).to_bytes(2, "big") + FUNCTION.to_bytes(2, "big") + bytes([CALL])
    return bytes(code)


def cut_program(bc, k):
    """The bytes of `bc` up to and including its k-th instruction that is not a push (all of them when it has fewer); for k = -1, up to
    but not including the first IUP[x]."""
    i, n = 0, 0
    while i < len(bc):
        op = bc[i]
        if k < 0 and op == 0x31:
            return bc[:i]
        if op == 0x40:
            i += 2 + bc[i + 1]
        elif op == 0x41:
            i += 2 + 2 * bc[i + 1]
        elif 0xB0 <= op <= 0xB7:
            i += 2 + (op - 0xB0)
        elif 0xB8 <= op <= 0xBF:
            i += 3 + 2 * (op - 0xB8)
        else:
            i += 1
            n += 1
            if 0 <= k <= n:
                return bc[:i]
    return bc


def point_count(glyf, name):
    """The points of the glyph, composites flattened, and the four phantom points that follow them (left, right, top, bottom)."""
    return outline_points(glyf, name) + 4


def outline_points(glyf, name):
    g = glyf[name]
    if g.isComposite():
        return sum(outline_points(glyf, c.glyphName) for c in g.components)
    return g.numberOfContours and len(g.coordinates) or 0


def reader_glyph(npoints, upem, ppem, program):
    k = upem / ppem  # font units per pixel
    coords, flags, ends = [], [], []
    for s in range(npoints * 2 * BITS):
        x, y = slot_origin(s)
        x0, y0, x1, y1 = [round(v * k) for v in (x, y, x + DOT, y + DOT)]
        coords += [(x0, y0), (x0, y1), (x1, y1), (x1, y0)]
        flags += [1, 1, 1, 1]
        ends.append(len(coords) - 1)
    g = Glyph()
    g.numberOfContours = len(ends)
    g.coordinates = GlyphCoordinates(coords)
    g.flags = flags
    g.endPtsOfContours = ends
    prog = ttProgram.Program()
    prog.fromBytecode(program)
    g.program = prog
    return g


def main():
    src, out, family, ppem = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    no_program = len(sys.argv) > 5 and sys.argv[5] == "none"
    cut = None
    cut_iup = False
    if len(sys.argv) > 5 and sys.argv[5].startswith("cutiup="):
        cut, cut_iup = int(sys.argv[5][7:]), True
    elif len(sys.argv) > 5 and sys.argv[5].startswith("cut="):
        cut = -1 if sys.argv[5] == "cut=iupx" else int(sys.argv[5][4:])
    font = TTFont(src)
    glyf = font["glyf"]
    upem = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    order = list(font.getGlyphOrder())
    orig_order = list(order)
    codes = [c for c in list(range(32, 127)) + list(range(160, 256)) if c in cmap]
    t0 = font["maxp"].maxStorage
    slot_base = t0 + 3
    tapped = {}
    cvt_values = len(font["cvt "].values)
    cvt_base = None
    for code in codes:
        name = cmap[code]
        n = point_count(glyf, name)
        if n == 4 or name in tapped:
            continue
        g = glyf[name]
        old = g.program.getBytecode() if getattr(g, "program", None) and not no_program else b""
        if cut is not None:
            old = cut_program(old, cut) + (bytes([0x31]) if cut_iup else b"")
        tail = tail_program(n, slot_base)
        tapped[name] = slot_base
        slot_base += 2 * n
        if code == 33:  # this glyph also leaves the control value table in storage
            cvt_base = slot_base
            tail += cvt_tail(cvt_values, cvt_base) + info_tail(cvt_base + 2 * cvt_values)
            slot_base += 2 * (cvt_values + len(INFO_SELECTORS) + 2)
            prep_base = slot_base  # the same questions asked at the end of `prep`
            prep = font["prep"]
            stor_base = prep_base + 2 * (len(INFO_SELECTORS) + 2)  # and the font's own storage as `prep` leaves it
            start_base = stor_base + 2 * t0  # and at the very start of `prep`
            prep.program.fromBytecode(info_tail(start_base) + prep.program.getBytecode() + info_tail(prep_base) + storage_tail(t0, stor_base))
            slot_base += 2 * (len(INFO_SELECTORS) + 2) + 2 * t0 + 2 * (len(INFO_SELECTORS) + 2)
        prog = ttProgram.Program()
        prog.fromBytecode(old + tail)
        g.program = prog
    new_cmap = {}

    def add_reader(rname, npoints, base, level, unicode_point):
        glyf[rname] = reader_glyph(npoints, upem, ppem, reader_program(npoints, base, t0, level))
        order.append(rname)
        font["hmtx"].metrics[rname] = (0, min(x for x, y in glyf[rname].coordinates))  # lsb = xMin: the left phantom point stays on the pen
        new_cmap[unicode_point] = rname

    for code in codes:
        name = cmap[code]
        if name not in tapped:
            continue
        n = point_count(glyf, name)
        add_reader("tapr%d" % code, n, tapped[name], 0, READER_BASE + code - 32)
        add_reader("taph%d" % code, n, tapped[name], 1, READER_HI + code - 32)
    if cvt_base is not None:
        total = cvt_values + 4 * (len(INFO_SELECTORS) + 2) + t0
        for j in range((total + CVT_CHUNK - 1) // CVT_CHUNK):
            count = min(CVT_CHUNK, total - j * CVT_CHUNK)
            for level in range(4):
                add_reader("tapc%d_%d" % (level, j), count, cvt_base + 2 * CVT_CHUNK * j, level, CVT_LO + 0x100 * level + j)
    if "hdmx" in font:
        for ppem_key, widths in list(font["hdmx"].hdmx.items()):
            plain = {g: widths[g] for g in orig_order}
            for r in new_cmap.values():
                plain[r] = 0
            font["hdmx"].hdmx[ppem_key] = plain
    fpgm = font["fpgm"]
    fpgm.program.fromBytecode(fpgm.program.getBytecode() + reader_function(t0))
    maxp = font["maxp"]
    maxp.maxFunctionDefs = max(maxp.maxFunctionDefs, FUNCTION + 1)
    maxp.maxStorage = max(maxp.maxStorage, slot_base)
    font.setGlyphOrder(order)
    glyf.glyphOrder = order
    maxp.numGlyphs = len(order)
    font["hhea"].numberOfHMetrics = len(order)
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap.update(new_cmap)
    font["post"].formatType = 3.0
    for tag in ("LTSH", "VDMX", "GPOS", "GSUB", "GDEF", "kern", "meta", "MERG"):
        if tag in font:
            del font[tag]
    # the squares sit up to 100 pixels from the pen: widen the font's vertical extent to hold them
    k = upem / ppem
    up, down, right = round(130 * k), round(110 * k), round(190 * k)
    font["hhea"].ascent, font["hhea"].descent = up, -down
    font["OS/2"].usWinAscent, font["OS/2"].usWinDescent = up, down
    font["OS/2"].sTypoAscender, font["OS/2"].sTypoDescender, font["OS/2"].sTypoLineGap = up, -down, 0
    font["head"].yMax, font["head"].yMin, font["head"].xMax = up, -down, max(font["head"].xMax, right)
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 4, 16):
            rec.string = family
        elif rec.nameID == 6:
            rec.string = family.replace(" ", "") + "-Regular"
        elif rec.nameID in (2, 17):
            rec.string = "Regular"
        elif rec.nameID == 3:
            rec.string = family + "-tap"
    font.save(out)
    print("tap font", out, len(tapped), "glyphs,", slot_base, "storage slots")


if __name__ == "__main__":
    main()
