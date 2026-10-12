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
    # A two-page PDF, written by hand (no library): the Document app's PDF fixture.
    c1 = b"BT /F1 12 Tf 72 700 Td (Neper phone handbook) Tj 0 -16 Td (Chapter one) Tj ET"
    c2 = b"BT /F1 12 Tf 72 700 Td (Chapter two) Tj ET"
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
        3: b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
        4: b"<< /Length %d >>\nstream\n" % len(c1) + c1 + b"\nendstream",
        5: b"<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>",
        6: b"<< /Length %d >>\nstream\n" % len(c2) + c2 + b"\nendstream",
    }
    pdf = bytearray(b"%PDF-1.4\n")
    for number in sorted(objects):
        pdf += b"%d 0 obj\n" % number + objects[number] + b"\nendobj\n"
    pdf += b"trailer\n<< /Root 1 0 R >>\n%%EOF\n"
    (out / "zz.pdf").write_bytes(bytes(pdf))
    # A Markdown file and a Python file: shown as rendered Markdown and highlighted code.
    (out / "zznotes.md").write_text("# Handbook\n\nWelcome to **Neper**.\n\n## Apps\n- Calc\n- Files\n\n| App | Kind | Size |\n|---|:-:|--:|\n| Calc | tool | 12 |\n| Files | system | 48 |\n", encoding="utf-8")
    # A spreadsheet (C172): a header row, a sparse row and booleans; the first sheet is drawn as a grid.
    sheet_ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    (out / "budget.xlsx").write_bytes(zipped([
        ("[Content_Types].xml", "<Types/>"),
        ("xl/workbook.xml", f'<workbook {sheet_ns}><sheets><sheet name="Budget" sheetId="1"/></sheets></workbook>'),
        ("xl/sharedStrings.xml", f'<sst {sheet_ns}><si><t>Item</t></si><si><t>Rent</t></si><si><t>Food</t></si><si><t>Paid</t></si></sst>'),
        ("xl/worksheets/sheet1.xml", f'<worksheet {sheet_ns}><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><t>Cost</t></is></c><c r="C1" t="s"><v>3</v></c></row>'
            '<row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>1200.5</v></c><c r="C2" t="b"><v>1</v></c></row>'
            '<row r="4"><c r="A4" t="s"><v>2</v></c><c r="B4"><v>310</v></c><c r="C4" t="b"><v>0</v></c></row>'
            '</sheetData></worksheet>')]))
    # A long text file (120 lines, a few pages in Document).
    (out / "zzzlong.txt").write_text("".join(f"line {i + 1} of a long file\n" for i in range(120)), encoding="utf-8")
    (out / "otpauth.txt").write_text("otpauth://totp/Neper%20Bank:sam.rivera?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Neper%20Bank&algorithm=SHA256&digits=8&period=45\notpauth://hotp/Mail:sam@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Mail&counter=3\n", encoding="utf-8")
    # An OpenDocument text file: a heading and two paragraphs (named to sort after the other samples).
    odt = io.BytesIO()
    with zipfile.ZipFile(odt, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/vnd.oasis.opendocument.text", compress_type=zipfile.ZIP_STORED)
        z.writestr("content.xml", '<?xml version="1.0" encoding="UTF-8"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:text><text:h text:outline-level="1">Open letter</text:h><text:p>Written in OpenDocument.</text:p></office:text></office:body></office:document-content>')
    (out / "zzzzodf.odt").write_bytes(odt.getvalue())
    # A zip archive (C150): a file, a directory and a file inside it; named to sort last.
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("hello.txt", "hello")
        z.writestr("docs/", "")
        z.writestr("docs/notes.md", "# Notes here")
    (out / "zzzzzzzip.zip").write_bytes(zbuf.getvalue())
    (out / "zzcode.py").write_text("# count words\nimport sys\n\nclass Counter:\n    def add(self, word):\n        return 1\n", encoding="utf-8")
    print("wrote", out)


main()
