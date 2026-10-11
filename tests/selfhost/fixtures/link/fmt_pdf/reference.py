#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/fmt_pdf/src/main.e: PDFs written here (plain and zlib-compressed streams, a
nested page tree, a contents array, escapes, hex strings, TJ kerning) read by e.fmt.pdf. The expectations are the
text the generator put in."""
import zlib
from pathlib import Path


def pdf(objects, root):
    """objects: {number: bytes body}. Written in order; the catalog is object `root`."""
    out = bytearray(b"%PDF-1.4\n")
    offsets = {}
    for number in sorted(objects):
        offsets[number] = len(out)
        out += f"{number} 0 obj\n".encode() + objects[number] + b"\nendobj\n"
    xref = len(out)
    size = max(objects) + 1
    out += f"xref\n0 {size}\n".encode() + b"0000000000 65535 f \n"
    for n in range(1, size):
        out += f"{offsets.get(n, 0):010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {size} /Root {root} 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def stream(data, compress=False):
    if compress:
        z = zlib.compress(data)
        return f"<< /Length {len(z)} /Filter /FlateDecode >>\nstream\n".encode() + z + b"\nendstream"
    return f"<< /Length {len(data)} >>\nstream\n".encode() + data + b"\nendstream"


FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

# 1: two pages, plain streams. Page 1: Tj, Td down a line, TJ with a word-space kern, an escaped parenthesis and an
# octal escape; page 2: a hex string and T*.
c1 = (b"BT /F1 12 Tf 72 700 Td (Hello, PDF world) Tj 0 -14 Td [(Neper) -320 (phone) 20 (!)] TJ "
      b"0 -14 Td (a \\(paren\\) and \\101 and caf\\351) Tj ET")
c2 = b"BT /F1 12 Tf 72 700 Td <48656c6c6f> Tj T* (second line) Tj ET"
plain = pdf({
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
    3: b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R /Resources << /Font << /F1 7 0 R >> >> /MediaBox [0 0 612 792] >>",
    4: stream(c1),
    5: b"<< /Type /Page /Parent 2 0 R /Contents 6 0 R /Resources << /Font << /F1 7 0 R >> >> /MediaBox [0 0 612 792] >>",
    6: stream(c2),
    7: FONT,
}, 1)

# 2: a nested page tree and a compressed stream; the pages are stored out of order (page object 9 is first in the
# tree, object 4 second).
c3 = b"BT /F1 12 Tf 72 700 Td (Compressed stream text) Tj ET"
c4 = b"BT /F1 12 Tf 72 700 Td (Tree order first) Tj ET"
nested = pdf({
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [8 0 R 3 0 R] /Count 2 >>",
    3: b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
    4: stream(c3, True),
    8: b"<< /Type /Pages /Parent 2 0 R /Kids [9 0 R] /Count 1 >>",
    9: b"<< /Type /Page /Parent 8 0 R /Contents 10 0 R >>",
    10: stream(c4),
}, 1)

# 3: a contents array of two streams on one page.
array = pdf({
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    3: b"<< /Type /Page /Parent 2 0 R /Contents [4 0 R 5 0 R] >>",
    4: stream(b"BT 72 700 Td (first part) Tj ET"),
    5: stream(b"BT 72 600 Td (second part) Tj ET"),
}, 1)


def arr(name, data):
    return f"    let {name}: [{len(data)}]u8 = [{len(data)}]u8{{ " + ", ".join(str(b) for b in data) + " }\n"


out = ["// `e.fmt.pdf`: PDFs written by reference.py -- plain and zlib-compressed streams, a nested page tree stored\n",
       "// out of order, a contents array, a literal string with escapes, a hex string, TJ kerning and T* -- read back\n",
       "// page by page, and the refusals for bytes that are no PDF and for a PDF with no pages.\n",
       "// Every check has its own exit code.\n",
       "use e.os\nuse e.mem\nuse e.str\nuse e.fmt.pdf as pdf\n\n",
       "fn main(a: *mem.Arena, args: []str) -> err {\n",
       arr("plain", plain), arr("nested", nested), arr("array", array)]
out.append('''    let (p, p_error) = pdf.pages(a, plain[0..])
    if p_error != ok { os.exit(1) }
    if p.len != 2usize { os.exit(2) }
    if !str.eq(p[0], "Hello, PDF world\\nNeper phone!\\na (paren) and A and caf\\xc3\\xa9") { os.exit(3) }
    if !str.eq(p[1], "Hello\\nsecond line") { os.exit(4) }
    let (n, n_error) = pdf.pages(a, nested[0..])
    if n_error != ok { os.exit(5) }
    if n.len != 2usize { os.exit(6) }
    if !str.eq(n[0], "Tree order first") { os.exit(7) }
    if !str.eq(n[1], "Compressed stream text") { os.exit(8) }
    let (r, r_error) = pdf.pages(a, array[0..])
    if r_error != ok { os.exit(9) }
    if r.len != 1usize || !str.eq(r[0], "first part\\nsecond part") { os.exit(10) }
    let junk: [20]u8 = [20]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }
    let (j, j_error) = pdf.pages(a, junk[0..])
    if j_error != pdf.NotPdf { os.exit(11) }
    let empty = "%PDF-1.4\\n1 0 obj\\n<< /Type /Catalog >>\\nendobj\\n"
    let (e, e_error) = pdf.pages(a, empty)
    if e_error != pdf.NoPages { os.exit(12) }
    ret ok
}
''')
dest = Path(__file__).resolve().parent / "src" / "main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text("".join(out), encoding="utf-8", newline="\n")
print("wrote", dest)
