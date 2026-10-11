#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/fmt_ooxml/src/main.e: a Word document and a PowerPoint deck made with
Python's zipfile (DEFLATE), read by e.fmt.ooxml. The expectations are the strings the generator put in."""
import io
import zipfile
from pathlib import Path

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'

DOC = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document {W}><w:body>
<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Neper phone</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">Plain text with </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r><w:r><w:t xml:space="preserve"> and a tab</w:t></w:r><w:r><w:tab/><w:t>after</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>first item</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>second &amp; last</w:t></w:r></w:p>
<w:p><w:r><w:t>line one</w:t><w:br/><w:t>line two</w:t></w:r></w:p>
<w:p/>
</w:body></w:document>'''


def slide(*paragraphs):
    ps = "".join(f"<a:p><a:r><a:t>{t}</a:t></a:r></a:p>" for t in paragraphs)
    return f'<?xml version="1.0"?><p:sld {A}><p:cSld><p:spTree><p:sp><p:txBody>{ps}</p:txBody></p:sp></p:spTree></p:cSld></p:sld>'


def build(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as z:
        for name, text in files:
            z.writestr(name, text)
    return buffer.getvalue()


def array(name, data):
    return f"    let {name}: [{len(data)}]u8 = [{len(data)}]u8{{ " + ", ".join(str(b) for b in data) + " }\n"


docx = build([("[Content_Types].xml", "<Types/>"), ("word/document.xml", DOC)])
# Slides written out of order on purpose: 10 before 2, and 1.
pptx = build([("[Content_Types].xml", "<Types/>"),
              ("ppt/slides/slide10.xml", slide("Ten")),
              ("ppt/slides/slide2.xml", slide("Second slide", "with two paragraphs")),
              ("ppt/slides/slide1.xml", slide("Title slide", "A subtitle")),
              ("ppt/presentation.xml", "<p/>")])
plain = build([("hello.txt", "no word part here")])

out = []
out.append("// `e.fmt.ooxml`: a Word document and a PowerPoint deck built with Python's zipfile and read back: the\n")
out.append("// paragraphs in order with their styles, a list item, a tab, a line break and an entity; the slides in\n")
out.append("// slide-number order with their paragraphs; and the refusals for a zip with no word part, for bytes that\n")
out.append("// are not a zip. Written by reference.py. Every check has its own exit code.\n")
out.append("use e.os\nuse e.mem\nuse e.str\nuse e.fmt.ooxml as ooxml\n\n")
out.append("fn main(a: *mem.Arena, args: []str) -> err {\n")
out.append(array("docx", docx))
out.append(array("pptx", pptx))
out.append(array("plain", plain))
out.append('''    let (ps, p_error) = ooxml.paragraphs(a, docx[0..])
    if p_error != ok { os.exit(1) }
    if ps.len != 6usize { os.exit(2) }
    if !str.eq(ps[0].text, "Neper phone") || !str.eq(ps[0].style, "Heading1") || ps[0].list { os.exit(3) }
    if !str.eq(ps[1].text, "Plain text with bold and a tab\\tafter") || ps[1].style.len != 0usize { os.exit(4) }
    if !str.eq(ps[2].text, "first item") || !str.eq(ps[2].style, "ListParagraph") || !ps[2].list { os.exit(5) }
    if !str.eq(ps[3].text, "second & last") || !ps[3].list { os.exit(6) }
    if !str.eq(ps[4].text, "line one\\nline two") { os.exit(7) }
    if ps[5].text.len != 0usize { os.exit(8) }
    let (ss, s_error) = ooxml.slides(a, pptx[0..])
    if s_error != ok { os.exit(9) }
    if ss.len != 3usize { os.exit(10) }
    if ss[0].paragraphs.len != 2usize || !str.eq(ss[0].paragraphs[0], "Title slide") || !str.eq(ss[0].paragraphs[1], "A subtitle") { os.exit(11) }
    if ss[1].paragraphs.len != 2usize || !str.eq(ss[1].paragraphs[0], "Second slide") { os.exit(12) }
    if ss[2].paragraphs.len != 1usize || !str.eq(ss[2].paragraphs[0], "Ten") { os.exit(13) }
    let (np, np_error) = ooxml.paragraphs(a, plain[0..])
    if np_error != ooxml.NoMainPart { os.exit(14) }
    let (ns, ns_error) = ooxml.slides(a, plain[0..])
    if ns_error != ooxml.NoMainPart { os.exit(15) }
    let junk: [16]u8 = [16]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
    let (jp, j_error) = ooxml.paragraphs(a, junk[0..])
    if j_error != ooxml.NotAPackage { os.exit(16) }
    ret ok
}
''')
dest = Path(__file__).resolve().parent / "src" / "main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text("".join(out), encoding="utf-8", newline="\n")
print("wrote", dest)
