#!/usr/bin/env python3
# Cuts the static, subset fonts the NeperOS shell draws with from the variable Google Fonts sources
# (SIL Open Font License; the licence texts sit beside the output). The e.text shaper and the scene's
# glyph flattener read plain TrueType outlines, so each wanted weight is instanced from the
# variable font, hinting is dropped, and the glyph set is cut to Basic Latin plus the few marks the
# UI uses -- the files are a few KB each instead of a few hundred.
# Usage: python scripts/make_fonts.py <dir holding the downloaded *[wght].ttf and *-OFL.txt files>
#   (the layout that fetched them: jost-Jost[wght].ttf, jost-OFL.txt, ... as in D2204)
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

source = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out_dir = os.path.join(root, "neperos", "assets", "fonts")
# (output name, source family dir, file stem, weight)
WANTED = [
    ("jost-regular", "jost", "Jost", 400),
    ("jost-bold", "jost", "Jost", 700),
    ("sora-medium", "sora", "Sora", 500),
    ("spacegrotesk-regular", "spacegrotesk", "SpaceGrotesk", 400),
    ("exo2-regular", "exo2", "Exo2", 400),
]
# Basic Latin, the degree sign, middle dot, dashes, curly quotes, ellipsis and a few arrows.
UNICODES = list(range(0x20, 0x7F)) + [0xB0, 0xB1, 0xB7, 0xD7, 0xF7, 0x2212, 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026, 0x2190, 0x2192]

for name, family, stem, weight in WANTED:
    path = os.path.join(source, "%s-%s[wght].ttf" % (family, stem))
    font = TTFont(path)
    static = instancer.instantiateVariableFont(font, {"wght": weight})
    options = subset.Options()
    options.hinting = False
    options.layout_features = ["kern", "liga", "calt"]
    options.name_IDs = [1, 2, 3, 4, 6]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=UNICODES)
    subsetter.subset(static)
    target = os.path.join(out_dir, name + ".ttf")
    static.save(target)
    print("wrote", target, os.path.getsize(target), "bytes")
for family in ("jost", "sora", "spacegrotesk", "exo2"):
    licence = open(os.path.join(source, family + "-OFL.txt"), encoding="utf-8").read()
    open(os.path.join(out_dir, family + "-OFL.txt"), "w", encoding="utf-8", newline="\n").write(licence)
