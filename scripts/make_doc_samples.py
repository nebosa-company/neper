#!/usr/bin/env python3
"""Sample documents for the Document fixtures of D4800 onward (C152, C172, C150): standard library only.

usage: make_doc_samples.py <directory>

  zimg.pdf    two pages: a heading, a 32 x 24 Flate RGB image, a text run through a font with a ToUnicode map (the
              codes 1..6 are "Neper!"), an outline of two bookmarks; the second page says "The needle is here"
"""
import io
import os
import struct
import sys
import zipfile
import zlib


def pdf_assemble(objects):
    out = bytearray(b"%PDF-1.4\n")
    for number, body in enumerate(objects, 1):
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    out += b"trailer\n<< /Root 1 0 R >>\n%%EOF\n"
    return bytes(out)


def pdf_stream(dictionary, data):
    return b"<< " + dictionary + b" /Length %d >>\nstream\n" % len(data) + data + b"\nendstream"


def zimg_pdf():
    w, h = 32, 24
    rows = bytearray()
    for y in range(h):
        for x in range(w):
            checker = ((x // 8) + (y // 8)) % 2
            rows += bytes((x * 8 % 256, y * 10 % 256, 200 if checker else 40))
    cmap = (b"/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n"
            b"1 begincodespacerange <00> <FF> endcodespacerange\n"
            b"6 beginbfchar <01> <004E> <02> <0065> <03> <0070> <04> <0065> <05> <0072> <06> <0021> endbfchar\n"
            b"endcmap end end")
    page1 = (b"BT /F1 24 Tf 30 350 Td (Image page) Tj ET\n"
             b"q 120 0 0 90 30 230 cm /Im1 Do Q\n"
             b"BT /F2 18 Tf 30 180 Td <010203040506> Tj ET\n")
    page2 = (b"BT /F1 20 Tf 30 350 Td (The needle is here) Tj ET\n"
             b"BT /F1 12 Tf 30 320 Td (haystack haystack haystack) Tj ET\n")
    resources = b"/Resources << /Font << /F1 8 0 R /F2 9 0 R >> /XObject << /Im1 10 0 R >> >>"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R /Outlines 5 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 300 400] >>",
        b"<< /Type /Page /Parent 2 0 R /Contents 11 0 R " + resources + b" >>",
        b"<< /Type /Page /Parent 2 0 R /Contents 12 0 R " + resources + b" >>",
        b"<< /Type /Outlines /First 6 0 R /Last 7 0 R /Count 2 >>",
        b"<< /Title (Pictures) /Parent 5 0 R /Next 7 0 R /Dest [3 0 R /Fit] >>",
        b"<< /Title (Needle) /Parent 5 0 R /Prev 6 0 R /Dest [4 0 R /Fit] >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Type /Font /Subtype /TrueType /BaseFont /Sub /FirstChar 1 /LastChar 6 /Widths [700 600 600 600 500 300] /ToUnicode 13 0 R >>",
        pdf_stream(b"/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode" % (w, h),
                   zlib.compress(bytes(rows))),
        pdf_stream(b"", page1),
        pdf_stream(b"", page2),
        pdf_stream(b"", cmap),
    ]
    return pdf_assemble(objects)


def png(width, height, pixel):
    """A truecolour PNG written by hand; `pixel(x, y)` gives (r, g, b)."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(width)) for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def stripes(x, y):
    return ((x * 8) % 256, (y * 16) % 256, 160 if (x // 4 + y // 4) % 2 else 60)


def package(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files:
            z.writestr(name, data)
    return buf.getvalue()


def zpic_docx():
    ns = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"')

    def para(text, style=None):
        props = '<w:pPr><w:pStyle w:val="%s"/></w:pPr>' % style if style else ""
        return '<w:p>%s<w:r><w:t>%s</w:t></w:r></w:p>' % (props, text)
    drawing = ('<w:p><w:r><w:drawing><wp:inline><wp:extent cx="1371600" cy="685800"/><a:graphic><a:graphicData>'
               '<pic:pic><pic:blipFill><a:blip r:embed="rId5"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>'
               '</wp:inline></w:drawing></w:r></w:p>')
    body = (para("Field notes", "Title") + para("Morning", "Heading1") + para("We walked the ridge before breakfast.")
            + drawing + para("Afternoon", "Heading2") + para("The valley was quiet."))
    return package([
        ("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'),
        ("word/document.xml", '<?xml version="1.0"?><w:document %s><w:body>%s</w:body></w:document>' % (ns, body)),
        ("word/_rels/document.xml.rels", '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId5" Type="image" Target="media/image1.png"/></Relationships>'),
        ("word/media/image1.png", png(32, 16, stripes)),
    ])


def zshape_pptx():
    p = ('xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
         'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
         'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')

    def sp(x, y, cx, cy, prst, fill, text):
        paragraphs = "".join('<a:p><a:r><a:t>%s</a:t></a:r></a:p>' % t for t in text)
        return ('<p:sp><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="%s"/>%s</p:spPr>'
                '<p:txBody>%s</p:txBody></p:sp>' % (x, y, cx, cy, prst,
                '<a:solidFill><a:srgbClr val="%s"/></a:solidFill>' % fill if fill else "", paragraphs))
    pic = ('<p:pic><p:blipFill><a:blip r:embed="rId2"/></p:blipFill><p:spPr><a:xfrm><a:off x="6400000" y="3600000"/>'
           '<a:ext cx="4800000" cy="2400000"/></a:xfrm></p:spPr></p:pic>')
    slide1 = (sp(600000, 400000, 6000000, 1200000, "rect", "1F4E79", ["Quarterly shapes"])
              + sp(900000, 2200000, 2400000, 2400000, "ellipse", "C0392B", ["Round"])
              + sp(3800000, 2600000, 2200000, 1000000, "rect", "F4D03F", ["Tea", "bags"]) + pic
              + '<p:cxnSp><p:spPr><a:xfrm><a:off x="600000" y="5600000"/><a:ext cx="5000000" cy="0"/></a:xfrm>'
                '<a:prstGeom prst="line"/></p:spPr></p:cxnSp>')
    slide2 = sp(1000000, 1000000, 4000000, 800000, "rect", None, ["Second slide"])
    sld = '<?xml version="1.0"?><p:sld %s><p:cSld><p:spTree>%s</p:spTree></p:cSld></p:sld>'
    return package([
        ("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'),
        ("ppt/presentation.xml", '<?xml version="1.0"?><p:presentation %s><p:sldSz cx="12192000" cy="6858000"/></p:presentation>' % p),
        ("ppt/slides/slide1.xml", sld % (p, slide1)),
        ("ppt/slides/_rels/slide1.xml.rels", '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId2" Type="image" Target="../media/image2.png"/></Relationships>'),
        ("ppt/slides/slide2.xml", sld % (p, slide2)),
        ("ppt/media/image2.png", png(24, 12, stripes)),
    ])


def zcalc_ods():
    ns = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
          'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"')

    def row(*cells):
        out = ""
        for cell in cells:
            if isinstance(cell, (int, float)):
                out += '<table:table-cell office:value-type="float" office:value="%s"><text:p>%s</text:p></table:table-cell>' % (cell, cell)
            else:
                out += '<table:table-cell office:value-type="string"><text:p>%s</text:p></table:table-cell>' % cell
        return "<table:table-row>%s</table:table-row>" % out
    content = ('<?xml version="1.0"?><office:document-content %s><office:body><office:spreadsheet><table:table table:name="Tea">'
               % ns + row("Blend", "Grams", "Price") + row("Assam", 250, 4.5) + row("Darjeeling", 100, 6) + row("Earl Grey", 500, 3.25)
               + '<table:table-row table:number-rows-repeated="1000"><table:table-cell table:number-columns-repeated="16"/></table:table-row>'
               '</table:table></office:spreadsheet></office:body></office:document-content>')
    return package([("mimetype", "application/vnd.oasis.opendocument.spreadsheet"), ("content.xml", content)])


def zpage_html():
    return (b"<!doctype html><html><head><title>Neper notes</title><style>body{color:#000}</style></head><body>"
            b"<h1>Neper notes</h1><p>A page with <b>bold</b> words, a <a href=\"https://neper.dev/docs\">link</a> and a list.</p>"
            b"<h2>Steps</h2><ul><li>Build the app</li><li>Boot it</li><li>Open the page</li></ul>"
            b"<table><tr><th>Tool</th><th>Use</th></tr><tr><td>neper</td><td>compile</td></tr></table>"
            b"<pre>neper build main.e</pre><script>alert(1)</script></body></html>")


def znested_zip():
    return package([("readme.txt", "top level"), ("docs/guide.md", "# Guide\n\nHello"), ("docs/notes/todo.txt", "buy tea\nsend mail")])


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    files = {"zimg.pdf": zimg_pdf(), "zpic.docx": zpic_docx(), "zshape.pptx": zshape_pptx(), "zcalc.ods": zcalc_ods(),
             "zpage.html": zpage_html(), "znested.zip": znested_zip()}
    for name, data in files.items():
        with open(os.path.join(out, name), "wb") as handle:
            handle.write(data)


if __name__ == "__main__":
    main()
