#!/usr/bin/env python3
"""Sample documents for the Document fixtures of D4800 onward (C152, C172, C150): standard library only.

usage: make_doc_samples.py <directory>

  zimg.pdf    two pages: a heading, a 32 x 24 Flate RGB image, a text run through a font with a ToUnicode map (the
              codes 1..6 are "Neper!"), an outline of two bookmarks; the second page says "The needle is here"
"""
import os
import struct
import sys
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


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    files = {"zimg.pdf": zimg_pdf()}
    for name, data in files.items():
        with open(os.path.join(out, name), "wb") as handle:
            handle.write(data)


if __name__ == "__main__":
    main()
