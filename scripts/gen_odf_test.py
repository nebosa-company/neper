#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_odf/src/main.e (C142): OpenDocument packages built with zipfile and
read back by e.fmt.odf, the expected paragraphs computed here by an independent ElementTree walk."""
import io
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {
    "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
    "draw": "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0",
    "table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0",
}
HEAD = ('<?xml version="1.0" encoding="UTF-8"?><office:document-content '
        + " ".join('xmlns:%s="%s"' % kv for kv in NS.items()) + ">")


def package(mimetype, body):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), mimetype, compress_type=zipfile.ZIP_STORED)
        z.writestr("content.xml", HEAD + body + "</office:document-content>", compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("meta.xml", "<office:document-meta xmlns:office=\"%s\"/>" % NS["office"])
    return out.getvalue()


ODT = package(
    "application/vnd.oasis.opendocument.text",
    '<office:body><office:text>'
    '<text:h text:style-name="Heading_20_1" text:outline-level="1">Neper phone</text:h>'
    '<text:p text:style-name="Standard">Plain <text:span text:style-name="B">bold</text:span> and a<text:tab/>tab</text:p>'
    '<text:list><text:list-item><text:p text:style-name="List">first item</text:p></text:list-item>'
    '<text:list-item><text:p text:style-name="List">second &amp; last</text:p></text:list-item></text:list>'
    '<text:p>two<text:line-break/>lines</text:p>'
    '<text:p>spaced<text:s text:c="3"/>out<text:s/>once</text:p>'
    '<text:p/>'
    '<text:h text:outline-level="2">Sub heading</text:h>'
    '<table:table><table:table-row><table:table-cell><text:p>cell A</text:p></table:table-cell>'
    '<table:table-cell><text:p>cell B</text:p></table:table-cell></table:table-row></table:table>'
    '</office:text></office:body>',
)

ODP = package(
    "application/vnd.oasis.opendocument.presentation",
    '<office:body><office:presentation>'
    '<draw:page draw:name="one"><draw:frame><draw:text-box><text:p>Title slide</text:p><text:p>A subtitle</text:p></draw:text-box></draw:frame></draw:page>'
    '<draw:page draw:name="two"><draw:frame><draw:text-box><text:p>Second slide</text:p></draw:text-box></draw:frame></draw:page>'
    '</office:presentation></office:body>',
)

PLAIN = io.BytesIO()
with zipfile.ZipFile(PLAIN, "w") as z:
    z.writestr("hello.txt", "no content part\n")
PLAIN = PLAIN.getvalue()


def q(prefix, local):
    return "{%s}%s" % (NS[prefix], local)


def text_of(e):
    out = []

    def walk(node):
        if node.text:
            out.append(node.text)
        for child in node:
            if child.tag == q("text", "s"):
                out.append(" " * int(child.get(q("text", "c"), "1")))
            elif child.tag == q("text", "tab"):
                out.append("\t")
            elif child.tag == q("text", "line-break"):
                out.append("\n")
            else:
                walk(child)
            if child.tail:
                out.append(child.tail)

    walk(e)
    return "".join(out)


def expected(data):
    root = ET.fromstring(zipfile.ZipFile(io.BytesIO(data)).read("content.xml"))
    paras = []

    def walk(node, in_list, page):
        for child in node:
            now_list = in_list or child.tag == q("text", "list-item")
            now_page = child if child.tag == q("draw", "page") else page
            if child.tag in (q("text", "p"), q("text", "h")):
                style = child.get(q("text", "style-name"), "")
                if child.tag == q("text", "h"):
                    style = "Heading" + child.get(q("text", "outline-level"), "")
                paras.append((text_of(child), style, now_list, now_page))
            else:
                walk(child, now_list, now_page)

    walk(root, False, None)
    return paras


def array(name, data):
    return "    let %s: [%d]u8 = [%d]u8{ %s }\n" % (name, len(data), len(data), ", ".join(str(b) for b in data))


def e_string(s):
    out = ""
    for ch in s:
        out += {"\n": "\\n", "\t": "\\t", '"': '\\"', "\\": "\\\\"}.get(ch, ch)
    return '"%s"' % out


def main():
    out = []
    out.append("// `e.fmt.odf`: an OpenDocument text file and presentation built with Python's zipfile and read back: the\n")
    out.append("// paragraphs in order with their styles (a heading is Heading<level>), list items, a tab, a line break, runs\n")
    out.append("// of spaces and an entity; the slides in order with their paragraphs; the refusals for a package with no\n")
    out.append("// content part and for bytes that are not a zip. Written by scripts/gen_odf_test.py, whose expected values come\n")
    out.append("// from an ElementTree walk. Every check has its own exit code.\n")
    out.append("use e.os\nuse e.mem\nuse e.str\nuse e.fmt.odf as odf\nuse e.fmt.ooxml as ooxml\n\n")
    out.append("fn main(a: *mem.Arena, args: []str) -> err {\n")
    out.append(array("odt", ODT))
    out.append(array("odp", ODP))
    out.append(array("plain", PLAIN))
    paras = expected(ODT)
    code = 1
    out.append("    let (ps, p_error) = odf.paragraphs(a, odt[0..])\n")
    out.append("    if p_error != ok { os.exit(%d) }\n" % code)
    code += 1
    out.append("    if ps.len != %dusize { os.exit(%d) }\n" % (len(paras), code))
    code += 1
    for i, (text, style, in_list, page) in enumerate(paras):
        cond = "!str.eq(ps[%d].text, %s) || !str.eq(ps[%d].style, %s)" % (i, e_string(text), i, e_string(style))
        cond += " || %sps[%d].list" % ("!" if in_list else "", i)
        out.append("    if %s { os.exit(%d) }\n" % (cond, code))
        code += 1
    slides = {}
    order = []
    for text, style, in_list, page in expected(ODP):
        if page is None:
            continue
        if id(page) not in slides:
            slides[id(page)] = []
            order.append(id(page))
        slides[id(page)].append(text)
    out.append("    let (ss, s_error) = odf.slides(a, odp[0..])\n")
    out.append("    if s_error != ok { os.exit(%d) }\n" % code)
    code += 1
    out.append("    if ss.len != %dusize { os.exit(%d) }\n" % (len(order), code))
    code += 1
    for si, key in enumerate(order):
        texts = slides[key]
        out.append("    if ss[%d].paragraphs.len != %dusize { os.exit(%d) }\n" % (si, len(texts), code))
        code += 1
        for ti, text in enumerate(texts):
            out.append("    if !str.eq(ss[%d].paragraphs[%d], %s) { os.exit(%d) }\n" % (si, ti, e_string(text), code))
            code += 1
    out.append("    let (np, np_error) = odf.paragraphs(a, plain[0..])\n")
    out.append("    if np_error != odf.NoContent { os.exit(%d) }\n" % code)
    code += 1
    out.append("    let junk: [16]u8 = [16]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }\n")
    out.append("    let (jp, j_error) = odf.paragraphs(a, junk[0..])\n")
    out.append("    if j_error != ooxml.NotAPackage { os.exit(%d) }\n" % code)
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/fmt_odf/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8")
    print("wrote", target, "checks", code)


if __name__ == "__main__":
    main()
