#!/usr/bin/env python3
"""A Word document with tables for the fmt_ooxml fixture (C152): a 3 x 3 table with a two-paragraph cell and a short
row, a paragraph either side, and a second table whose one cell holds a nested table. Prints the byte array main.e
embeds."""
import io
import zipfile

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'


def p(text):
    return f"<w:p><w:r><w:t>{text}</w:t></w:r></w:p>"


def tc(*paragraphs):
    return "<w:tc>" + "".join(paragraphs) + "</w:tc>"


def tr(*cells):
    return "<w:tr>" + "".join(cells) + "</w:tr>"


def tbl(*rows):
    return "<w:tbl>" + "".join(rows) + "</w:tbl>"


body = (p("Before") +
        tbl(tr(tc(p("Name")), tc(p("Qty")), tc(p("Note"))),
            tr(tc(p("Tea")), tc(p("2")), tc(p("a"), p("b"))),
            tr(tc(p("Only")))) +
        p("After") +
        tbl(tr(tc(p("outer"), tbl(tr(tc(p("inner"))))))))
document = f'<?xml version="1.0" encoding="UTF-8"?><w:document {W}><w:body>{body}</w:body></w:document>'
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", "<Types/>")
    z.writestr("word/document.xml", document)
data = buf.getvalue()
print(len(data))
print(", ".join(str(b) for b in data))
