import sys
from fontTools.ttLib import TTFont, newTable
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
def conv(src,dst):
    f=TTFont(src)
    gs=f.getGlyphSet(); order=f.getGlyphOrder()
    glyf={}
    for n in order:
        pen=TTGlyphPen(gs)
        gs[n].draw(Cu2QuPen(pen,1.0,reverse_direction=True))
        glyf[n]=pen.glyph()
    f["loca"]=newTable("loca")
    g=f["glyf"]=newTable("glyf"); g.glyphOrder=order; g.glyphs=glyf
    del f["CFF "]
    if "VORG" in f: del f["VORG"]
    g.compile(f)
    f["maxp"]=maxp=newTable("maxp")
    maxp.tableVersion=0x00010000
    for a in ("maxZones","maxTwilightPoints","maxStorage","maxFunctionDefs","maxInstructionDefs","maxStackElements","maxSizeOfInstructions","maxComponentElements"): setattr(maxp,a,0)
    maxp.maxZones=1
    maxp.numGlyphs=len(order)
    maxp.maxPoints=maxp.maxContours=maxp.maxCompositePoints=maxp.maxCompositeContours=maxp.maxComponentDepth=0
    f["head"].glyphDataFormat=0
    f["post"].formatType=2.0; f["post"].extraNames=[]; f["post"].mapping={}; f["post"].glyphOrder=order
    f.sfntVersion="\x00\x01\x00\x00"
    f.save(dst)
d="D:/Temp/lanes/looks9-linfra/docs/ui/looks/ref/linux/fonts/"
for n in ("Regular","Bold"):
    conv(d+f"Cantarell-{n}.otf", d+f"Cantarell-{n}.ttf")
