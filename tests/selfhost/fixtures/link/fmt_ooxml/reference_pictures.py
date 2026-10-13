#!/usr/bin/env python3
"""Packages for the fmt_ooxml fixture's picture and shape checks (D4802), written with Python's zipfile and
zlib (the PNG is written by hand, an 8 x 2 image).

  docx -- a Heading1 paragraph, a paragraph, a paragraph holding an inline drawing (extent 1828800 x 914400 EMU,
          blip rId5 -> media/image1.png), a last paragraph
  pptx -- slide size 12192000 x 6858000; slide 1 has a red rectangle "Box" (its run is green: the run's colour is not the
          fill), a blue ellipse with two paragraphs "A" and "B", and a picture (rels target ../media/image2.png); slide 2
          one unfilled rectangle

usage: reference_pictures.py docx|pptx   prints the byte count and the bytes as a comma separated list.
"""
import io
import struct
import sys
import zipfile
import zlib

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"'
P = 'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
REL = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"'


def png(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def image(seed):
    return png(8, 2, [[(x * 30 + seed) % 256 for x in range(24)], [(x * 7 + seed * 2) % 256 for x in range(24)]])


def docx():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
        z.writestr("word/document.xml", '<?xml version="1.0"?><w:document %s><w:body>'
                   '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Title</w:t></w:r></w:p>'
                   '<w:p><w:r><w:t>Before</w:t></w:r></w:p>'
                   '<w:p><w:r><w:drawing><wp:inline><wp:extent cx="1828800" cy="914400"/><a:graphic><a:graphicData>'
                   '<pic:pic><pic:blipFill><a:blip r:embed="rId5"/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
                   '<w:p><w:r><w:t>After</w:t></w:r></w:p></w:body></w:document>' % W)
        z.writestr("word/_rels/document.xml.rels", '<?xml version="1.0"?><Relationships %s>'
                   '<Relationship Id="rId1" Type="x" Target="styles.xml"/>'
                   '<Relationship Id="rId5" Type="image" Target="media/image1.png"/></Relationships>' % REL)
        z.writestr("word/media/image1.png", image(1))
    return buf.getvalue()


def slide(shapes):
    return '<?xml version="1.0"?><p:sld %s><p:cSld><p:spTree>%s</p:spTree></p:cSld></p:sld>' % (P, shapes)


def pptx():
    box = ('<p:sp><p:nvSpPr><p:cNvPr id="2" name="Box"/></p:nvSpPr><p:spPr><a:xfrm><a:off x="914400" y="457200"/>'
           '<a:ext cx="2743200" cy="914400"/></a:xfrm><a:prstGeom prst="rect"/><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>'
           '<a:ln><a:solidFill><a:srgbClr val="111111"/></a:solidFill></a:ln></p:spPr>'
           '<p:txBody><a:p><a:r><a:rPr><a:solidFill><a:srgbClr val="00FF00"/></a:solidFill></a:rPr><a:t>Box</a:t></a:r></a:p></p:txBody></p:sp>')
    disc = ('<p:sp><p:spPr><a:xfrm><a:off x="4572000" y="1828800"/><a:ext cx="1828800" cy="1828800"/></a:xfrm>'
            '<a:prstGeom prst="ellipse"/><a:solidFill><a:srgbClr val="0000FF"/></a:solidFill></p:spPr>'
            '<p:txBody><a:p><a:r><a:t>A</a:t></a:r></a:p><a:p><a:r><a:t>B</a:t></a:r></a:p></p:txBody></p:sp>')
    picture = ('<p:pic><p:blipFill><a:blip r:embed="rId2"/></p:blipFill><p:spPr><a:xfrm><a:off x="100" y="200"/>'
               '<a:ext cx="300" cy="400"/></a:xfrm></p:spPr></p:pic>')
    plain = ('<p:sp><p:spPr><a:xfrm><a:off x="10" y="20"/><a:ext cx="30" cy="40"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr></p:sp>')
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
        z.writestr("ppt/presentation.xml", '<?xml version="1.0"?><p:presentation %s><p:sldSz cx="12192000" cy="6858000"/></p:presentation>' % P)
        z.writestr("ppt/slides/slide1.xml", slide(box + disc + picture))
        z.writestr("ppt/slides/_rels/slide1.xml.rels", '<?xml version="1.0"?><Relationships %s>'
                   '<Relationship Id="rId2" Type="image" Target="../media/image2.png"/></Relationships>' % REL)
        z.writestr("ppt/slides/slide2.xml", slide(plain))
        z.writestr("ppt/media/image2.png", image(9))
    return buf.getvalue()


if __name__ == "__main__":
    data = {"docx": docx, "pptx": pptx}[sys.argv[1]]()
    print(len(data))
    print(", ".join(str(b) for b in data))
