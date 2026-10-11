#!/usr/bin/env python3
"""Write report.docx and deck.pptx (small Office Open XML files made with zipfile) to a directory, for the
Document app's fixtures: make_office_samples.py DIR"""
import io
import sys
import zipfile
from pathlib import Path

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'


def para(text, style=None, listed=False):
    props = ""
    if style:
        props += f'<w:pStyle w:val="{style}"/>'
    if listed:
        props += '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'
    ppr = f"<w:pPr>{props}</w:pPr>" if props else ""
    return f"<w:p>{ppr}<w:r><w:t>{text}</w:t></w:r></w:p>"


def zipped(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as z:
        for name, text in files:
            z.writestr(name, text)
    return buffer.getvalue()


def slide(*paragraphs):
    ps = "".join(f"<a:p><a:r><a:t>{t}</a:t></a:r></a:p>" for t in paragraphs)
    return f'<?xml version="1.0"?><p:sld {A}><p:cSld><p:spTree><p:sp><p:txBody>{ps}</p:txBody></p:sp></p:spTree></p:cSld></p:sld>'


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    body = (para("Quarterly report", "Heading1") + para("Revenue grew in every region.") +
            para("North America", None, True) + para("Europe", None, True) + para("Asia Pacific", None, True))
    document = f'<?xml version="1.0" encoding="UTF-8"?><w:document {W}><w:body>{body}</w:body></w:document>'
    (out / "report.docx").write_bytes(zipped([("[Content_Types].xml", "<Types/>"), ("word/document.xml", document)]))
    (out / "deck.pptx").write_bytes(zipped([("[Content_Types].xml", "<Types/>"),
                                            ("ppt/slides/slide1.xml", slide("Neper phone", "Everything runs on Neper")),
                                            ("ppt/slides/slide2.xml", slide("Apps", "Calc, Clock, Files"))]))
    print("wrote", out)


main()
