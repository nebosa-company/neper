#!/usr/bin/env python3
# (C167, D5004) Adds Cyrillic and Greek to the Jost Regular the NeperOS apps draw with, so Translate (and every app
# that shows a name or a message) can set Russian and Greek text. The glyphs are DejaVu Sans's (a free licence, the
# text sits beside the output as dejavu-LICENSE.txt): subset to the two scripts without hinting, scaled to Jost's
# units and a little smaller (DejaVu's x-height is large next to Jost's), then merged into jost-regular.ttf, whose
# Latin glyphs, kerning and name stay. Run once; the output is committed.
# Usage: python scripts/make_script_fonts.py [path to DejaVuSans.ttf and LICENSE_DEJAVU's directory]
import os
import shutil
import sys

from fontTools import subset
from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fonts = os.path.join(root, "neperos", "assets", "fonts")
if len(sys.argv) > 1:
    source = sys.argv[1]
else:
    import matplotlib

    source = os.path.join(os.path.dirname(matplotlib.__file__), "mpl-data", "fonts", "ttf")

# Cyrillic: the capitals and small letters of Russian, Ukrainian and Serbian plus the extras of the block's start (U+0400-U+045F);
# Greek: the tonos letters and the capitals and small letters (U+0386-U+03CE, without the gaps).
UNICODES = list(range(0x0400, 0x0460)) + [0x0386] + list(range(0x0388, 0x038B)) + [0x038C] + list(range(0x038E, 0x03A2)) + list(range(0x03A3, 0x03CF))

dejavu = TTFont(os.path.join(source, "DejaVuSans.ttf"))
options = subset.Options()
options.hinting = False
options.layout_features = []
options.notdef_outline = False
options.name_IDs = [1, 2, 3, 4, 6]
subsetter = subset.Subsetter(options)
subsetter.populate(unicodes=UNICODES)
subsetter.subset(dejavu)
# To Jost's 1000 units, at nine tenths of DejaVu's size: scale to 1111 units and call them 1000.
scale_upem(dejavu, 1111)
dejavu["head"].unitsPerEm = 1000
KEEP = {"head", "hhea", "maxp", "OS/2", "hmtx", "cmap", "loca", "glyf", "name", "post", "GlyphOrder"}
for table in list(dejavu.keys()):
    if table not in KEEP:
        del dejavu[table]
staged = os.path.join(fonts, "_dejavu_stage.ttf")
dejavu.save(staged)

jost = os.path.join(fonts, "jost-regular.ttf")
merger = Merger()
merged = merger.merge([jost, staged])
os.remove(staged)
merged.save(jost)
shutil.copyfile(os.path.join(source, "LICENSE_DEJAVU"), os.path.join(fonts, "dejavu-LICENSE.txt"))
print("wrote", jost, os.path.getsize(jost), "bytes;", len(merged.getBestCmap()), "code points")
