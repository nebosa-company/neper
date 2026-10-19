"""Synthetic hinted fonts read back through GDI's ClearType hinter: what a chosen glyph program does to chosen points, in GDI's own words.

python synth.py            (self test: one rectangle with no program)

    from synth import Glyph, run
    pts = run([Glyph(contours=[[(200, 0, 1), (200, 640, 1), (400, 640, 1), (400, 0, 1)]], adv=545, asm="SVTCA[x-axis]\\nPUSHB[ ] 0\\nMDAP[rnd]\\nIUP[x]")])
    pts[0]   # -> [(x, y) in 26.6 pixels for each point, then the four phantom points]

The font has upem 1024 and is read at 16 ppem by default, so one font unit is one 1/64 pixel and a coordinate in the glyph is the 26.6 value
the hinter starts from. Glyph k answers on code CODES[k]. The glyph programs are the ones given (fontTools assembly), with the tap tail of
tapfont.py appended: GC of every point after the program ran, drawn as squares and decoded by tapread.py. Needs glyphs.exe from glyphs.ps1.
"""
import dataclasses
import gzip
import os
import subprocess
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import ttProgram
from fontTools.ttLib.tables._g_l_y_f import Glyph as TTGlyph, GlyphCoordinates

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = r"D:\Temp\claude\winnative"
WORK = os.path.join(BIN, "synth")
UPEM = 1024
CODES = list(range(33, 127)) + list(range(160, 256))
_counter = [0]


@dataclasses.dataclass
class Glyph:
    contours: list
    adv: int = 1024
    asm: str = ""
    prep: str = ""
    components: list = None   # a composite: [(index of the glyph in the list, dx, dy, flags)], flags like 0x0004 ROUND_XY_TO_GRID, 0x0200 USE_MY_METRICS


OPS = {}
for _n, _b in (
    ("SVTCA", 0x00), ("SPVTCA", 0x02), ("SFVTCA", 0x04), ("SPVTL", 0x06), ("SFVTL", 0x08), ("SPVFS", 0x0A), ("SFVFS", 0x0B), ("GPV", 0x0C),
    ("GFV", 0x0D), ("SFVTPV", 0x0E), ("ISECT", 0x0F), ("SRP0", 0x10), ("SRP1", 0x11), ("SRP2", 0x12), ("SZP0", 0x13), ("SZP1", 0x14),
    ("SZP2", 0x15), ("SZPS", 0x16), ("SLOOP", 0x17), ("RTG", 0x18), ("RTHG", 0x19), ("SMD", 0x1A), ("ELSE", 0x1B), ("JMPR", 0x1C),
    ("SCVTCI", 0x1D), ("SSWCI", 0x1E), ("SSW", 0x1F), ("DUP", 0x20), ("POP", 0x21), ("CLEAR", 0x22), ("SWAP", 0x23), ("DEPTH", 0x24),
    ("CINDEX", 0x25), ("MINDEX", 0x26), ("ALIGNPTS", 0x27), ("UTP", 0x29), ("LOOPCALL", 0x2A), ("CALL", 0x2B), ("FDEF", 0x2C),
    ("ENDF", 0x2D), ("MDAP", 0x2E), ("IUP", 0x30), ("SHP", 0x32), ("SHC", 0x34), ("SHZ", 0x36), ("SHPIX", 0x38), ("IP", 0x39),
    ("MSIRP", 0x3A), ("ALIGNRP", 0x3C), ("RTDG", 0x3D), ("MIAP", 0x3E), ("WS", 0x42), ("RS", 0x43), ("WCVTP", 0x44), ("RCVT", 0x45),
    ("GC", 0x46), ("SCFS", 0x48), ("MD", 0x49), ("MPPEM", 0x4B), ("MPS", 0x4C), ("FLIPON", 0x4D), ("FLIPOFF", 0x4E), ("LT", 0x50),
    ("LTEQ", 0x51), ("GT", 0x52), ("GTEQ", 0x53), ("EQ", 0x54), ("NEQ", 0x55), ("ODD", 0x56), ("EVEN", 0x57), ("IF", 0x58), ("EIF", 0x59),
    ("AND", 0x5A), ("OR", 0x5B), ("NOT", 0x5C), ("DELTAP1", 0x5D), ("SDB", 0x5E), ("SDS", 0x5F), ("ADD", 0x60), ("SUB", 0x61),
    ("DIV", 0x62), ("MUL", 0x63), ("ABS", 0x64), ("NEG", 0x65), ("FLOOR", 0x66), ("CEILING", 0x67), ("ROUND", 0x68), ("NROUND", 0x6C),
    ("WCVTF", 0x70), ("DELTAP2", 0x71), ("DELTAP3", 0x72), ("DELTAC1", 0x73), ("DELTAC2", 0x74), ("DELTAC3", 0x75), ("SROUND", 0x76),
    ("S45ROUND", 0x77), ("JROT", 0x78), ("JROF", 0x79), ("ROFF", 0x7A), ("RUTG", 0x7C), ("RDTG", 0x7D), ("SANGW", 0x7E), ("AA", 0x7F),
    ("FLIPPT", 0x80), ("FLIPRGON", 0x81), ("FLIPRGOFF", 0x82), ("SCANCTRL", 0x85), ("SDPVTL", 0x86), ("GETINFO", 0x88), ("IDEF", 0x89),
    ("ROLL", 0x8A), ("MAX", 0x8B), ("MIN", 0x8C), ("SCANTYPE", 0x8D), ("INSTCTRL", 0x8E), ("MDRP", 0xC0), ("MIRP", 0xE0)):
    OPS[_n] = _b


def asm(text):
    """A glyph program from words: NAME or NAME[flags] (flags a Python integer: SVTCA[1] is x, IUP[1] is x, MDAP[1] rounds, MDRP[0b10100]...)
    and integers, which are pushed (a run of them becomes one PUSHB or PUSHW). Lines may carry # comments."""
    out = bytearray()
    run = []

    def flush():
        i = 0
        while i < len(run):
            chunk = run[i:i + 8]
            i += 8
            if all(0 <= v <= 255 for v in chunk):
                out.append(0xB0 + len(chunk) - 1)
                out.extend(chunk)
            else:
                out.append(0xB8 + len(chunk) - 1)
                for v in chunk:
                    out.extend((v & 0xFFFF).to_bytes(2, "big"))
        run.clear()

    for line in text.splitlines():
        for w in line.split("#")[0].replace(";", " ").split():
            if w.lstrip("-").isdigit():
                run.append(int(w))
                continue
            flush()
            name, _, fl = w.partition("[")
            out.append(OPS[name] + (int(fl.rstrip("]"), 0) if fl else 0))
    flush()
    return bytes(out)


def build(path, family, glyphs, fpgm="", prep="", hdmx=None, ppem=16, extra_cvt=None, gasp=None):
    order = [".notdef"] + ["g%d" % i for i in range(len(glyphs))]
    tt = {}
    metrics = {".notdef": (UPEM, 0)}
    tt[".notdef"] = TTGlyph()
    tt[".notdef"].numberOfContours = 0
    cmap = {}
    from fontTools.ttLib.tables._g_l_y_f import GlyphComponent
    for i, g in enumerate(glyphs):
        t = TTGlyph()
        if g.components:
            t.numberOfContours = -1
            t.components = []
            for (idx, cdx, cdy, cfl) in g.components:
                comp = GlyphComponent()
                comp.glyphName = "g%d" % idx
                comp.x, comp.y = cdx, cdy
                comp.flags = cfl | 0x2 | (0x1 if not (-128 <= cdx < 128 and -128 <= cdy < 128) else 0)
                t.components.append(comp)
            if g.asm:
                t.components[-1].flags |= 0x100
            t.program = ttProgram.Program()
            t.program.fromBytecode(asm(g.asm))
            tt["g%d" % i] = t
            xmin = min((x + c[1] for c in g.components for cc in glyphs[c[0]].contours for (x, y, on) in cc), default=0)
            metrics["g%d" % i] = (g.adv, xmin)
            cmap[CODES[i]] = "g%d" % i
            continue
        coords, flags, ends = [], [], []
        for c in g.contours:
            for (x, y, on) in c:
                coords.append((x, y))
                flags.append(1 if on else 0)
            ends.append(len(coords) - 1)
        t.numberOfContours = len(g.contours)
        t.coordinates = GlyphCoordinates(coords)
        t.flags = flags
        t.endPtsOfContours = ends
        t.program = ttProgram.Program()
        t.program.fromBytecode(asm(g.asm))
        tt["g%d" % i] = t
        xmin = min((x for c in g.contours for (x, y, on) in c), default=0)
        metrics["g%d" % i] = (g.adv, xmin)
        cmap[CODES[i]] = "g%d" % i
    fb = FontBuilder(UPEM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(tt)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=16 * 64, descent=-4 * 64)
    fb.setupNameTable({"familyName": family, "styleName": "Regular", "uniqueFontIdentifier": family + "-Regular", "fullName": family, "psName": family + "-Regular", "version": "Version 1.0"})
    fb.setupOS2(sTypoAscender=16 * 64, sTypoDescender=-4 * 64, usWinAscent=16 * 64, usWinDescent=4 * 64, fsType=0)
    fb.setupPost()
    for tag, text in (("fpgm", fpgm), ("prep", prep)):
        t = newTable(tag)
        t.program = ttProgram.Program()
        t.program.fromBytecode(asm(text) if text else bytes([0xB0, 0x00, 0x21]))
        fb.font[tag] = t
    c = newTable("cvt ")
    import array
    c.values = array.array("h", list(extra_cvt or [0]))
    fb.font["cvt "] = c
    if hdmx:
        h = newTable("hdmx")
        h.hdmx = hdmx
        fb.font["hdmx"] = h
    if gasp is not None:
        g = newTable("gasp")
        g.version = 1
        g.gaspRange = dict(gasp)
        fb.font["gasp"] = g
    fb.font["head"].flags = 0b1011
    fb.save(path)
    # generous limits: a test program must not trap on the size of the stack or the number of functions
    from fontTools.ttLib import TTFont
    f = TTFont(path)
    m = f["maxp"]
    m.maxStackElements = max(m.maxStackElements, 1024)
    m.maxFunctionDefs = max(m.maxFunctionDefs, 64)
    m.maxStorage = max(m.maxStorage, 64)
    m.maxTwilightPoints = max(m.maxTwilightPoints, 16)
    m.maxSizeOfInstructions = max(m.maxSizeOfInstructions, 4096)
    m.maxInstructionDefs = max(m.maxInstructionDefs, 0)
    f.save(path)


CTDUMP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "t", "ctdump.exe")


CTDUMP_BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "t", "ctdump_base.exe")


def ours(src, ppem, exe=None):
    """Our hinter's points for every code of the font `src` (build/t/ctdump.exe from tools/ctdump), in the shape run() returns."""
    out = subprocess.run([exe or CTDUMP, src, str(ppem)], check=True, capture_output=True, text=True).stdout
    res = {}
    for ln in out.splitlines():
        t = list(map(int, ln.split()))
        code, nc = t[0], t[3]
        p, pts = 4, []
        for _ in range(nc):
            m = t[p]
            p += 1
            pts += [(t[p + 3 * i], t[p + 3 * i + 1]) for i in range(m)]
            p += 3 * m
        pts += [(t[p + 2 * i], t[p + 2 * i + 1]) for i in range(4)]
        res[code] = pts
    return res


def run(glyphs, ppem=16, fpgm="", prep="", hdmx=None, cvt=None, gasp=None, weight=400, keep=False, compare=False):
    """-> a list per glyph of (x, y) in 26.6 pixels: its points, then the left, right, top and bottom phantom points. With compare=True a
    pair of such lists, GDI's and our hinter's."""
    assert len(glyphs) <= len(CODES)
    os.makedirs(WORK, exist_ok=True)
    _counter[0] += 1
    family = "NSy%d_%d" % (os.getpid(), _counter[0])
    src = os.path.join(WORK, family + ".src.ttf")
    tap = os.path.join(WORK, family + ".ttf")
    build(src, family, glyphs, fpgm, prep, hdmx, ppem, cvt, gasp)
    subprocess.run([sys.executable, os.path.join(HERE, "tapfont.py"), src, tap, family, str(ppem)], check=True, stdout=subprocess.DEVNULL)
    atl = []
    for mode in (1, 2):
        scratch = os.path.join(WORK, "out%d_%d" % (os.getpid(), mode))
        os.makedirs(scratch, exist_ok=True)
        env = dict(os.environ, GLYPHS_READER=str(mode), GLYPHS_FONT=tap, GLYPHS_CELL="200,210,110", GLYPHS_NOOUTLINE="1")
        subprocess.run([os.path.join(BIN, "glyphs.exe"), scratch, family, str(weight), str(ppem), "5"], check=True, env=env, stdout=subprocess.DEVNULL)
        atl.append(os.path.join(scratch, "%s-%d-%d-q5.000000-FFFFFF.bgra" % (family, weight, ppem)))
    out = os.path.join(WORK, family + ".hinted.gz")
    subprocess.run([sys.executable, os.path.join(HERE, "tapread.py"), src, atl[0], atl[1], out], check=True, stdout=subprocess.DEVNULL)
    res = {}
    for ln in gzip.open(out, "rt").read().splitlines():
        t = list(map(int, ln.split()))
        res[t[0]] = [(t[2 + 2 * i], t[3 + 2 * i]) for i in range(t[1])]
    for a in atl:
        os.remove(a)
    mine = ours(src, ppem) if compare else None
    base = ours(src, ppem, CTDUMP_BASE) if compare == "all" else None
    if not keep:
        for p in (src, tap, out):
            os.remove(p)
    gdi = [res.get(CODES[i]) for i in range(len(glyphs))]
    if compare == "all":
        return gdi, [mine.get(CODES[i]) for i in range(len(glyphs))], [base.get(CODES[i]) for i in range(len(glyphs))]
    if compare:
        return gdi, [mine.get(CODES[i]) for i in range(len(glyphs))]
    return gdi


def rect(x0, y0, x1, y1):
    return [(x0, y0, 1), (x0, y1, 1), (x1, y1, 1), (x1, y0, 1)]


if __name__ == "__main__":
    for p in run([Glyph(contours=[rect(200, 0, 400, 640)], adv=545), Glyph(contours=[rect(200, 0, 400, 640)], adv=545, asm="SVTCA[1] 0 MDAP[1] IUP[1]")]):
        print(p)


def run_variants(srcfont, ppem, variants, weight=400, compare=True, keep=False):
    """Glyph variants of a real font through GDI's ClearType hinter: variants is a list of (template glyph name, edit) where edit(glyph) changes a
    copy of the template glyph in place (a composite's component offsets, say). Variant k answers on code CODES[k]; every other glyph of the font is
    dropped from the cmap. -> the list of GDI's point lists (and ours with compare=True), like run()."""
    import copy
    from fontTools.ttLib import TTFont
    os.makedirs(WORK, exist_ok=True)
    _counter[0] += 1
    family = "NVr%d_%d" % (os.getpid(), _counter[0])
    f = TTFont(srcfont)
    glyf, hmtx = f["glyf"], f["hmtx"]
    order = list(f.getGlyphOrder())
    if "hdmx" in f:
        f["hdmx"].hdmx = {pk: {g: w[g] for g in order} for pk, w in f["hdmx"].hdmx.items()}
    cmap = {}

    def add_copy(tmpl, name):
        g2 = copy.deepcopy(glyf[tmpl])
        glyf.glyphs[name] = g2
        order.append(name)
        hmtx.metrics[name] = hmtx.metrics[tmpl]
        if "hdmx" in f:
            for ppem_key, widths in f["hdmx"].hdmx.items():
                widths[name] = widths[tmpl]
        return g2

    class Ctx:
        """edit(glyph, ctx): ctx.copy(template name) -> (new glyph name, glyph) adds a copy of another glyph to the font (a component to cut, say)"""
        n = 0

        def copy(self, tmpl):
            Ctx.n += 1
            name = "aux%d" % Ctx.n
            return name, add_copy(tmpl, name)

    ctx = Ctx()
    for k, (tmpl, edit) in enumerate(variants):
        name = "var%d" % k
        g = add_copy(tmpl, name)
        try:
            edit(g, ctx)
        except TypeError:
            edit(g)
        cmap[CODES[k]] = name
    f.setGlyphOrder(order)
    glyf.glyphOrder = order
    f["maxp"].numGlyphs = len(order)
    f["hhea"].numberOfHMetrics = len(order)
    for t in f["cmap"].tables:
        t.ensureDecompiled()
        t.cmap = dict(cmap) if t.isUnicode() else {}
    f["post"].formatType = 3.0
    for tag in ("LTSH", "VDMX", "GPOS", "GSUB", "GDEF", "kern", "meta", "MERG", "DSIG"):
        if tag in f:
            del f[tag]
    src = os.path.join(WORK, family + ".src.ttf")
    f.save(src)
    tap = os.path.join(WORK, family + ".ttf")
    subprocess.run([sys.executable, os.path.join(HERE, "tapfont.py"), src, tap, family, str(ppem)], check=True, stdout=subprocess.DEVNULL)
    atl = []
    for mode in (1, 2):
        scratch = os.path.join(WORK, "out%d_%d" % (os.getpid(), mode))
        os.makedirs(scratch, exist_ok=True)
        env = dict(os.environ, GLYPHS_READER=str(mode), GLYPHS_FONT=tap, GLYPHS_CELL="200,210,110", GLYPHS_NOOUTLINE="1")
        subprocess.run([os.path.join(BIN, "glyphs.exe"), scratch, family, str(weight), str(ppem), "5"], check=True, env=env, stdout=subprocess.DEVNULL)
        atl.append(os.path.join(scratch, "%s-%d-%d-q5.000000-FFFFFF.bgra" % (family, weight, ppem)))
    out = os.path.join(WORK, family + ".hinted.gz")
    subprocess.run([sys.executable, os.path.join(HERE, "tapread.py"), src, atl[0], atl[1], out], check=True, stdout=subprocess.DEVNULL)
    res = {}
    for ln in gzip.open(out, "rt").read().splitlines():
        t = list(map(int, ln.split()))
        res[t[0]] = [(t[2 + 2 * i], t[3 + 2 * i]) for i in range(t[1])]
    mine = ours(src, ppem) if compare else None
    for p in atl + ([] if keep else [src, tap, out]):
        os.remove(p)
    gdi = [res.get(CODES[i]) for i in range(len(variants))]
    if compare:
        return gdi, [mine.get(CODES[i]) for i in range(len(variants))]
    return gdi
