"""Builds the OpenType MATH test font for the text_math fixture (L098, D3101).

A subset of the repository's Montserrat ExtraBold (OFL) with two additions: a format 12
cmap subtable that maps Mathematical Italic a, b, x, y to the glyphs of the capitals
A, B, X, Y (so a test can tell the italic form was used), and a MATH table with chosen
constants, italic corrections, a variant list for the radical sign and an assembly for
the parenthesis. Everything else is the original font, so the numbers the generator
(`gen_math_render_test.py`) predicts come from fontTools reading this same file.

    python scripts/gen_math_font.py
"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "docs", "video", "neper-capabilities", "fonts", "Montserrat-ExtraBold.ttf")
TARGET = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "text_math", "assets", "mathfont.ttf")

# Design units (upem 1000), by MathConstants field.
CONSTANTS = {
    "ScriptPercentScaleDown": 75, "ScriptScriptPercentScaleDown": 55,
    "DelimitedSubFormulaMinHeight": 1300, "DisplayOperatorMinHeight": 1500,
    "MathLeading": 0, "AxisHeight": 300, "AccentBaseHeight": 500, "FlattenedAccentBaseHeight": 700,
    "SubscriptShiftDown": 180, "SubscriptTopMax": 400, "SubscriptBaselineDropMin": 60,
    "SuperscriptShiftUp": 400, "SuperscriptShiftUpCramped": 300, "SuperscriptBottomMin": 120,
    "SuperscriptBaselineDropMax": 350, "SubSuperscriptGapMin": 200, "SuperscriptBottomMaxWithSubscript": 380,
    "SpaceAfterScript": 30, "UpperLimitGapMin": 100, "UpperLimitBaselineRiseMin": 0,
    "LowerLimitGapMin": 140, "LowerLimitBaselineDropMin": 0,
    "StackTopShiftUp": 0, "StackTopDisplayStyleShiftUp": 0, "StackBottomShiftDown": 0,
    "StackBottomDisplayStyleShiftDown": 0, "StackGapMin": 0, "StackDisplayStyleGapMin": 0,
    "StretchStackTopShiftUp": 0, "StretchStackBottomShiftDown": 0, "StretchStackGapAboveMin": 0,
    "StretchStackGapBelowMin": 0,
    "FractionNumeratorShiftUp": 450, "FractionNumeratorDisplayStyleShiftUp": 700,
    "FractionDenominatorShiftDown": 400, "FractionDenominatorDisplayStyleShiftDown": 720,
    "FractionNumeratorGapMin": 50, "FractionNumDisplayStyleGapMin": 130, "FractionRuleThickness": 60,
    "FractionDenominatorGapMin": 50, "FractionDenomDisplayStyleGapMin": 130,
    "SkewedFractionHorizontalGap": 0, "SkewedFractionVerticalGap": 0,
    "OverbarVerticalGap": 0, "OverbarRuleThickness": 0, "OverbarExtraAscender": 0,
    "UnderbarVerticalGap": 0, "UnderbarRuleThickness": 0, "UnderbarExtraDescender": 0,
    "RadicalVerticalGap": 70, "RadicalDisplayStyleVerticalGap": 110, "RadicalRuleThickness": 55,
    "RadicalExtraAscender": 80, "RadicalKernBeforeDegree": 100, "RadicalKernAfterDegree": -400,
    "RadicalDegreeBottomRaisePercent": 55,
}
ITALIC_CORRECTION = {"X": 40, "Y": 55}
MIN_CONNECTOR_OVERLAP = 20
# Italic scalar -> the capital whose glyph it takes.
ITALIC = {0x1D44E: "A", 0x1D44F: "B", 0x1D465: "X", 0x1D466: "Y"}


def value(v):
    r = ot.MathValueRecord()
    r.Value = v
    r.DeviceTable = None
    return r


def coverage(names):
    c = ot.Coverage()
    c.glyphs = list(names)
    return c


def build():
    options = subset.Options()
    options.layout_features = []
    options.notdef_outline = True
    options.name_IDs = [1, 2]
    options.glyph_names = True
    options.hinting = False
    font = subset.load_font(SOURCE, options)
    text = "abcdefghijklmnopqrstuvwxyzABXY0123456789+-=()[]{}|.,√∑∫− "
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    # Drop the tables the library does not need so the asset stays small.
    for tag in ("GSUB", "GPOS", "GDEF", "kern", "hdmx", "VDMX", "fpgm", "prep", "cvt ", "gasp", "DSIG"):
        if tag in font:
            del font[tag]
    cmap = font.getBestCmap()
    merged = dict(cmap)
    for scalar, cap in ITALIC.items():
        merged[scalar] = cmap[ord(cap)]
    # One format 12 subtable in place of the old ones.
    table = newTable("cmap")
    table.tableVersion = 0
    sub = CmapSubtable.newSubtable(12)
    sub.platformID = 3
    sub.platEncID = 10
    sub.format = 12
    sub.reserved = 0
    sub.length = 0
    sub.language = 0
    sub.nGroups = 0
    sub.cmap = merged
    table.tables = [sub]
    font["cmap"] = table

    order = font.getGlyphOrder()
    name_of = {ch: cmap[ord(ch)] for ch in "abxyABXY()[]{}|,.=√∑∫"}
    math = newTable("MATH")
    m = ot.MATH()
    m.Version = 0x00010000
    c = ot.MathConstants()
    for field, v in CONSTANTS.items():
        if field in ("ScriptPercentScaleDown", "ScriptScriptPercentScaleDown", "DelimitedSubFormulaMinHeight",
                     "DisplayOperatorMinHeight", "RadicalDegreeBottomRaisePercent"):
            setattr(c, field, v)
        else:
            setattr(c, field, value(v))
    m.MathConstants = c
    info = ot.MathGlyphInfo()
    ic = ot.MathItalicsCorrectionInfo()
    names = sorted((name_of[ch] for ch in ITALIC_CORRECTION), key=order.index)
    ic.Coverage = coverage(names)
    ic.ItalicsCorrectionCount = len(names)
    inverse = {name_of[ch]: v for ch, v in ITALIC_CORRECTION.items()}
    ic.ItalicsCorrection = [value(inverse[n]) for n in names]
    info.MathItalicsCorrectionInfo = ic
    info.MathTopAccentAttachment = None
    info.ExtendedShapeCoverage = None
    info.MathKernInfo = None
    m.MathGlyphInfo = info

    glyf = font["glyf"]
    hmtx = font["hmtx"]

    def height(name):
        g = glyf[name]
        return (g.yMax - g.yMin) if g.numberOfContours else 0

    variants = ot.MathVariants()
    variants.MinConnectorOverlap = MIN_CONNECTOR_OVERLAP
    # The radical sign: itself, then two glyphs standing in as taller variants (the advance
    # measurements are declared, not the glyphs' own), no assembly.
    radical = ot.MathGlyphConstruction()
    radical.GlyphAssembly = None
    records = []
    for ch, declared in (("√", 936), ("∫", 1500), ("∑", 2400)):
        r = ot.MathGlyphVariantRecord()
        r.VariantGlyph = name_of[ch]
        r.AdvanceMeasurement = declared
        records.append(r)
    radical.VariantCount = len(records)
    radical.MathGlyphVariantRecord = records
    # The parenthesis: no larger variant, an assembly of a comma, a repeatable equals sign
    # and a period (their glyph heights are the parts' advances).
    paren = ot.MathGlyphConstruction()
    parts = []
    for ch, extender in ((",", False), ("=", True), (".", False)):
        p = ot.GlyphPartRecord()
        p.glyph = name_of[ch]
        p.StartConnectorLength = 100
        p.EndConnectorLength = 100
        p.FullAdvance = height(name_of[ch])
        p.PartFlags = 1 if extender else 0
        parts.append(p)
    assembly = ot.GlyphAssembly()
    assembly.ItalicsCorrection = value(0)
    assembly.PartCount = len(parts)
    assembly.PartRecords = parts
    paren.GlyphAssembly = assembly
    paren.VariantCount = 0
    paren.MathGlyphVariantRecord = []
    pairs = sorted([(name_of["√"], radical), (name_of["("], paren)], key=lambda kv: order.index(kv[0]))
    variants.VertGlyphCoverage = coverage([n for n, _ in pairs])
    variants.HorizGlyphCoverage = None
    variants.VertGlyphCount = len(pairs)
    variants.HorizGlyphCount = 0
    variants.VertGlyphConstruction = [con for _, con in pairs]
    variants.HorizGlyphConstruction = []
    m.MathVariants = variants
    math.table = m
    font["MATH"] = math
    os.makedirs(os.path.dirname(TARGET), exist_ok=True)
    font.save(TARGET)
    return TARGET


if __name__ == "__main__":
    path = build()
    print("wrote", path, os.path.getsize(path), "bytes")
