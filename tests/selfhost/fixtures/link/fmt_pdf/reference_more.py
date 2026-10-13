#!/usr/bin/env python3
"""PDFs for the fmt_pdf fixture's image, font and outline checks (D4800), made by independent producers.

  images  -- hand-assembled objects around a JPEG from Pillow (an 8 x 8 solid red-ish block) and the IDAT of a
             Pillow-written PNG used as a FlateDecode image with /Predictor 15 (the five PNG filters are chosen by
             Pillow's encoder), plus a 1-bit stencil mask and a Form XObject that draws a rectangle
  fonts   -- reportlab with an embedded TrueType subset (ToUnicode CMap written by reportlab) and a hand-built Type0
             font with /W widths and a bfrange ToUnicode
  outline -- reportlab bookmarks (an /Outlines tree with /Dest page references, nested one level)

Usage: reference_more.py <name> prints the byte count and the bytes as a comma separated list.
"""
import io
import struct
import sys
import zlib

from PIL import Image


def assemble(objects, extra_trailer=b""):
    out = bytearray(b"%PDF-1.4\n")
    for number, body in enumerate(objects, 1):
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    out += b"trailer\n<< /Root 1 0 R >>\n%%EOF\n"
    return bytes(out)


def stream(dictionary, data):
    return b"<< " + dictionary + b" /Length %d >>\nstream\n" % len(data) + data + b"\nendstream"


def png_idat(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=False)
    png = buf.getvalue()
    pos = 8
    idat = b""
    while pos < len(png):
        length, kind = struct.unpack(">I4s", png[pos:pos + 8])
        if kind == b"IDAT":
            idat += png[pos + 8:pos + 8 + length]
        pos += 12 + length
    return idat


def rgb_image():
    # 6 x 4, a gradient with structure so every PNG filter type appears and Paeth matters.
    img = Image.new("RGB", (6, 4))
    for y in range(4):
        for x in range(6):
            img.putpixel((x, y), ((x * 40 + y * 7) % 256, (y * 60 + x * 3) % 256, (x * y * 20 + 17) % 256))
    return img


def images():
    jpeg = io.BytesIO()
    Image.new("RGB", (8, 8), (200, 40, 30)).save(jpeg, "JPEG", quality=95)
    rgb = rgb_image()
    # 1-bit stencil: 8 x 2, rows 10101010 and 11110000 (0 paints).
    mask = bytes([0b10101010, 0b11110000])
    content = (b"q 100 0 0 100 10 20 cm /Im1 Do Q\n"
               b"q 60 0 0 40 130 150 cm /Im2 Do Q\n"
               b"q 16 0 0 4 10 150 cm 0 0 1 rg /Im3 Do Q\n"
               b"/Fm1 Do\n")
    form = b"0 1 0 rg 150 10 30 30 re f"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 200 200] >>",
        b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R /Resources << /XObject << /Im1 5 0 R /Im2 6 0 R /Im3 7 0 R /Fm1 8 0 R >> >> >>",
        stream(b"", content),
        stream(b"/Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode", jpeg.getvalue()),
        stream(b"/Type /XObject /Subtype /Image /Width 6 /Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode "
               b"/DecodeParms << /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns 6 >>", png_idat(rgb)),
        stream(b"/Type /XObject /Subtype /Image /Width 8 /Height 2 /ImageMask true /BitsPerComponent 1", mask),
        stream(b"/Type /XObject /Subtype /Form /BBox [0 0 200 200]", form),
    ]
    return assemble(objects)


def fonts():
    from reportlab.pdfgen import canvas
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    # A TrueType face cut down to the letters used (fontTools), so the embedded font is a few KB.
    from fontTools import subset
    options = subset.Options()
    options.hinting = False
    font = subset.load_font("C:/Windows/Fonts/arial.ttf", options)
    sub = subset.Subsetter(options)
    sub.populate(text="Helo fiwrd")
    sub.subset(font)
    subset.save_font(font, "D:/Temp/lanes/K_scratch/sub.ttf", options)
    pdfmetrics.registerFont(TTFont("Face", "D:/Temp/lanes/K_scratch/sub.ttf"))
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pageCompression=0, invariant=1)
    c.setFont("Face", 12)
    c.drawString(72, 700, "Hello fi world")
    c.save()
    return buf.getvalue()


def type0():
    cmap = (b"/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n"
            b"1 begincodespacerange <0000> <FFFF> endcodespacerange\n"
            b"2 beginbfchar <0001> <0048> <0002> <0069> endbfchar\n"
            b"1 beginbfrange <0003> <0005> <0041> endbfrange\n"
            b"endcmap end end")
    cmap1 = (b"1 begincodespacerange <00> <FF> endcodespacerange\n"
             b"1 beginbfchar <01> <005A> endbfchar\nendcmap")
    content = (b"BT /F1 10 Tf 10 100 Td (ABC) Tj ET\n"
               b"BT /F2 12 Tf 10 50 Td <00010002000300040005> Tj ET\n"
               b"BT /F3 10 Tf 10 20 Td <0101> Tj ET\n")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 200 200] >>",
        b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 9 0 R >> >> >>",
        stream(b"", content),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 65 /LastChar 67 /Widths [700 600 500] >>",
        b"<< /Type /Font /Subtype /Type0 /BaseFont /Cid /Encoding /Identity-H /DescendantFonts [7 0 R] /ToUnicode 8 0 R >>",
        b"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Cid /DW 1000 /W [1 [400 500] 3 5 250] >>",
        stream(b"", cmap),
        b"<< /Type /Font /Subtype /TrueType /BaseFont /Sub /FirstChar 1 /LastChar 1 /Widths [600] /ToUnicode 10 0 R >>",
        stream(b"", cmap1),
    ]
    return assemble(objects)


def outline():
    from reportlab.pdfgen import canvas
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pageCompression=0, invariant=1)
    for number, title in enumerate(["Intro", "Method", "Result"]):
        c.bookmarkPage("p%d" % number)
        c.addOutlineEntry(title, "p%d" % number, level=0)
        if title == "Method":
            c.bookmarkPage("details")
            c.addOutlineEntry("Details", "details", level=1)
        c.drawString(72, 700, "Page %d" % (number + 1))
        c.showPage()
    c.save()
    return buf.getvalue()


if __name__ == "__main__":
    data = {"images": images, "fonts": fonts, "type0": type0, "outline": outline}[sys.argv[1]]()
    open("D:/Temp/lanes/K_scratch/ref_%s.pdf" % sys.argv[1], "wb").write(data)
    print(len(data))
    print(", ".join(str(b) for b in data))
