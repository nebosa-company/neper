#!/usr/bin/env python3
"""The PDF painted by `pdf.page_painting` in the fmt_pdf fixture (C152): a MediaBox 400 x 800 page whose content
fills a red rectangle, strokes a blue 3-unit line, prints "Hello" at 18 pt after a Td, fills a grey rectangle under
a `0.5 0 0 0.5 10 20 cm` and a CMYK-black text. Prints the byte array main.e embeds."""
content = (b"q 1 0 0 rg 100 600 200 50 re f Q\n"
           b"0 0 1 RG 3 w 100 500 m 300 500 l S\n"
           b"BT /F1 18 Tf 72 700 Td (Hello) Tj ET\n"
           b"q 0.5 0 0 0.5 10 20 cm 0.5 g 0 0 40 40 re f Q\n"
           b"BT /F1 10 Tf 0 0 0 1 k 50 400 Td [(Tea) -300 (bags)] TJ ET\n")
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 400 800] >>",
    b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
]
pdf = bytearray(b"%PDF-1.4\n")
for number, body in enumerate(objects, 1):
    pdf += b"%d 0 obj\n" % number + body + b"\nendobj\n"
pdf += b"trailer\n<< /Root 1 0 R >>\n%%EOF\n"
print(len(pdf))
print(", ".join(str(b) for b in pdf))
