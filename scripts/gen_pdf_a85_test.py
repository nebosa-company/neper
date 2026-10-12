#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_pdf_a85/src/main.e: e.fmt.pdf reads page contents filtered with
ASCII85Decode alone and with ASCII85Decode then FlateDecode (what reportlab writes), the encodings made by Python's
base64.a85encode and zlib."""
import base64
import zlib
from pathlib import Path


def pdf(content_filter, stream):
    objs = []
    objs.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objs.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objs.append(b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>")
    objs.append(b"<< /Length %d /Filter %s >>\nstream\n" % (len(stream), content_filter) + stream + b"\nendstream")
    out = b"%PDF-1.4\n"
    for i, o in enumerate(objs, start=1):
        out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    out += b"trailer\n<< /Root 1 0 R /Size 5 >>\n%%EOF\n"
    return out


TEXT = b"BT /F1 12 Tf 72 720 Td (Hello ASCII85 world) Tj 0 -14 Td (second line, with a z: zzzz and ~ tilde) Tj ET"
# Several lengths so every partial-group size and the 'z' shortcut occur.
A85_ONLY = pdf(b"/ASCII85Decode", base64.a85encode(TEXT, adobe=True))
BOTH = pdf(b"[/ASCII85Decode /FlateDecode]", base64.a85encode(zlib.compress(TEXT), adobe=True, wrapcol=60))
ZEROS = pdf(b"/ASCII85Decode", base64.a85encode(b"BT (" + bytes(8) + b"ok) Tj ET", adobe=True, ))
# Same text, the stream's encoding broken by white space and no '<~' prefix.
RAW = base64.a85encode(TEXT)
SPACED = pdf(b"/ASCII85Decode", b" ".join(RAW[i:i + 7] for i in range(0, len(RAW), 7)) + b"~>")


def array(name, data):
    return "    let %s: [%d]u8 = [%d]u8{ %s }\n" % (name, len(data), len(data), ", ".join(str(b) for b in data))


def main():
    out = ["// `e.fmt.pdf`: page contents filtered with ASCII85Decode alone, with ASCII85Decode then FlateDecode (as reportlab\n",
           "// writes them), with a zero group (the `z` shortcut) and with white space inside and no `<~`. The encodings come\n",
           "// from Python's base64.a85encode and zlib (scripts/gen_pdf_a85_test.py). Every check has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.str\nuse e.fmt.pdf as pdf\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    for name, data in (("only", A85_ONLY), ("both", BOTH), ("zeros", ZEROS), ("spaced", SPACED)):
        out.append(array(name, data))
    want = "Hello ASCII85 world"
    out.append("    let (p1, e1) = pdf.pages(a, only[0..])\n")
    out.append("    if e1 != ok || p1.len != 1usize { os.exit(1) }\n")
    out.append("    if !str.contains(p1[0], \"Hello ASCII85 world\") || !str.contains(p1[0], \"second line, with a z: zzzz and ~ tilde\") { os.exit(2) }\n")
    out.append("    let (p2, e2) = pdf.pages(a, both[0..])\n")
    out.append("    if e2 != ok || p2.len != 1usize { os.exit(3) }\n")
    out.append("    if !str.contains(p2[0], \"Hello ASCII85 world\") || !str.contains(p2[0], \"second line\") { os.exit(4) }\n")
    out.append("    let (p3, e3) = pdf.pages(a, zeros[0..])\n")
    out.append("    if e3 != ok || p3.len != 1usize || !str.contains(p3[0], \"ok\") { os.exit(5) }\n")
    out.append("    let (p4, e4) = pdf.pages(a, spaced[0..])\n")
    out.append("    if e4 != ok || p4.len != 1usize { os.exit(6) }\n")
    out.append("    if !str.contains(p4[0], \"Hello ASCII85 world\") { os.exit(7) }\n")
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/fmt_pdf_a85/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target)


main()
