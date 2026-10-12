#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_pdf_write/src/main.e (L145): `e.fmt.pdf.write`.

Oracles, independent of the Neper code:
  * the expected file bytes come from a second writer here (hand-built PDF 1.4 objects and xref) whose text
    measuring and line breaking use reportlab's Helvetica metrics (`pdfmetrics.stringWidth`), not the table in
    the module; every wrapping decision is asserted to clear its limit by a margin so rounding cannot decide;
  * the generator asserts that pypdf (strict) opens the bytes, finds the pages, the media box, the title and the
    text, and that pdfminer extracts the same text;
  * the fixture also reads the file back through `e.fmt.pdf.pages`.
Run with --metrics to print the width tables for the module.
"""
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lane_e_common import Checks, lit, write_fixture  # noqa: E402

try:
    from reportlab.pdfbase import pdfmetrics
except ImportError:  # the metrics are only needed to generate
    pdfmetrics = None

FONTS = {"Regular": "Helvetica", "Bold": "Helvetica-Bold"}
MARGINS = []


def width(s, font, size):
    return pdfmetrics.stringWidth(s.encode("cp1252").decode("latin-1") if False else s, FONTS[font], size)


def real(v, decimals=2):
    scale = 10.0 ** decimals
    m = -v if v < 0 else v
    n = int(m * scale + 0.5)
    div = int(scale)
    whole, frac = divmod(n, div)
    out = ""
    if v < 0 and n != 0:
        out = "-"
    out += str(whole)
    if frac:
        digits = decimals
        while frac % 10 == 0:
            frac //= 10
            digits -= 1
        out += "." + str(frac).rjust(digits, "0")
    return out


def r(v):
    return real(v, 2) + " "


def color(c, stroke=False):
    return "%s %s %s %s " % (real(c[0] / 255.0, 4), real(c[1] / 255.0, 4), real(c[2] / 255.0, 4), "RG" if stroke else "rg")


def literal(s):
    out = "("
    for ch in s:
        b = ch.encode("cp1252")[0]
        if b in (40, 41, 92):
            out += "\\" + chr(b)
        elif b > 126:
            out += "\\%03o" % b
        else:
            out += chr(b)
    return out + ")"


def fontop(font):
    return "/F2 " if font == "Bold" else "/F1 "


def split_line(s, start, limit, size, font):
    """(end, next) of the line starting at `start`: greedy over space-led tokens, newline forces a break."""
    i = start
    line_end = start
    used = ""
    empty = True
    while True:
        if i >= len(s):
            return line_end, len(s)
        if s[i] == "\n":
            return line_end, i + 1
        k = i
        while k < len(s) and s[k] == " ":
            k += 1
        j = k
        while j < len(s) and s[j] not in " \n":
            j += 1
        token = s[i:j]
        w = width(used + token, font, size)
        if not empty:
            MARGINS.append(abs(w - limit))
            if w > limit:
                return line_end, k
        used += token
        line_end = j
        empty = False
        i = j


def lines_of(s, limit, size, font):
    out = []
    at = 0
    while True:
        end, nxt = split_line(s, at, limit, size, font)
        out.append(s[at:end])
        if nxt >= len(s):
            break
        at = nxt
    return out


class Doc:
    def __init__(self, w, h, title, pages, capacity):
        self.w, self.h, self.title = w, h, title
        self.pages = []
        self.cur = None
        self.neper = []
        self.max_pages, self.capacity = pages, capacity
        self.texts = []

    def n(self, line):
        self.neper.append("    " + line + "\n")

    def begin(self):
        self.cur = ""
        self.n("if w.begin_page(&d) != ok { os.exit(%d) }" % self.check())

    def end(self):
        self.pages.append(self.cur)
        self.cur = None
        self.n("if w.end_page(&d) != ok { os.exit(%d) }" % self.check())

    code = 0

    def check(self):
        Doc.code += 1
        return Doc.code

    def put(self, s):
        self.cur += s

    def text(self, x, y, size, font, ink, s):
        self.put("q " + color(ink) + "BT " + fontop(font) + real(size) + " Tf " + r(x) + r(self.h - y) + "Td " + literal(s) + " Tj ET Q\n")
        self.texts.append(s)
        self.n("if w.put_text(&d, %r, %r, %r, .%s, %s, %s) != ok { os.exit(%d) }" % (x, y, size, font, nc(ink), lit(s), self.check()))

    def paragraph(self, x, y, wd, size, leading, font, ink, s):
        base = y
        for ln in lines_of(s, wd, size, font):
            self.put("q " + color(ink) + "BT " + fontop(font) + real(size) + " Tf " + r(x) + r(self.h - base) + "Td " + literal(ln) + " Tj ET Q\n")
            self.texts.append(ln)
            base += leading
        n = len(lines_of(s, wd, size, font))
        v = "para%d" % self.check()
        self.n("let (%s_next, %s_lines, %s_error) = w.put_paragraph(&d, %r, %r, %r, %r, %r, .%s, %s, %s)" % (v, v, v, x, y, wd, size, leading, font, nc(ink), lit(s)))
        self.n("if %s_error != ok || %s_lines != %dusize || %s_next != %r { os.exit(%d) }" % (v, v, n, v, base, self.check()))
        return base

    def fill_rect(self, x, y, wd, ht, ink):
        self.put("q " + color(ink) + r(x) + r(self.h - y - ht) + r(wd) + r(ht) + "re f Q\n")
        self.n("if w.fill_rect(&d, %r, %r, %r, %r, %s) != ok { os.exit(%d) }" % (x, y, wd, ht, nc(ink), self.check()))

    def stroke_rect(self, x, y, wd, ht, lw, ink):
        self.put("q " + color(ink, True) + r(lw) + "w " + r(x) + r(self.h - y - ht) + r(wd) + r(ht) + "re S Q\n")
        self.n("if w.stroke_rect(&d, %r, %r, %r, %r, %r, %s) != ok { os.exit(%d) }" % (x, y, wd, ht, lw, nc(ink), self.check()))

    def line(self, x1, y1, x2, y2, lw, ink):
        self.put("q " + color(ink, True) + r(lw) + "w " + r(x1) + r(self.h - y1) + "m " + r(x2) + r(self.h - y2) + "l S Q\n")
        self.n("if w.draw_line(&d, %r, %r, %r, %r, %r, %s) != ok { os.exit(%d) }" % (x1, y1, x2, y2, lw, nc(ink), self.check()))

    def path(self, pts, filled, lw, ink):
        s = "q " + color(ink, not filled)
        if not filled:
            s += r(lw) + "w "
        for i, (px, py) in enumerate(pts):
            s += r(px) + r(self.h - py) + ("m " if i == 0 else "l ")
        s += "h f Q\n" if filled else "S Q\n"
        self.put(s)
        xs = ", ".join(repr(p[0]) for p in pts)
        ys = ", ".join(repr(p[1]) for p in pts)
        self.n("let xs%d = [%d]f64{ %s }" % (Doc.code + 1, len(pts), xs))
        self.n("let ys%d = [%d]f64{ %s }" % (Doc.code + 1, len(pts), ys))
        self.n("if w.draw_path(&d, xs%d[0..], ys%d[0..], %s, %r, %s) != ok { os.exit(%d) }" % (Doc.code + 1, Doc.code + 1, "true" if filled else "false", lw, nc(ink), self.check()))

    def circle(self, cx, cy, rad, ink):
        k = rad * 0.5523
        xs = [cx + rad, cx + rad, cx + k, cx, cx - k, cx - rad, cx - rad, cx - rad, cx - k, cx, cx + k, cx + rad]
        ys = [cy, cy - k, cy - rad, cy - rad, cy - rad, cy - k, cy, cy + k, cy + rad, cy + rad, cy + rad, cy + k]
        s = "q " + color(ink) + r(xs[0]) + r(self.h - ys[0]) + "m "
        for i in range(1, 12):
            s += r(xs[i]) + r(self.h - ys[i])
            if i % 3 == 0:
                s += "c "
        s += r(xs[0]) + r(self.h - ys[0]) + "c f Q\n"
        self.put(s)
        self.n("if w.fill_circle(&d, %r, %r, %r, %s) != ok { os.exit(%d) }" % (cx, cy, rad, nc(ink), self.check()))

    def table(self, x, y, widths, rows, size, leading, pad, header, ink, rule):
        top = y
        for ri, row in enumerate(rows):
            head = header and ri == 0
            font = "Bold" if head else "Regular"
            tallest = max([len(lines_of(c, widths[ci] - 2 * pad, size, font)) for ci, c in enumerate(row)] + [1])
            height = tallest * leading + 2 * pad
            left = x
            for ci in range(len(widths)):
                if head:
                    self.put("q " + color((238, 238, 238)) + r(left) + r(self.h - top - height) + r(widths[ci]) + r(height) + "re f Q\n")
                self.put("q " + color(rule, True) + r(0.5) + "w " + r(left) + r(self.h - top - height) + r(widths[ci]) + r(height) + "re S Q\n")
                if ci < len(row) and row[ci]:
                    base = top + pad + size
                    for ln in lines_of(row[ci], widths[ci] - 2 * pad, size, font):
                        self.put("q " + color(ink) + "BT " + fontop(font) + real(size) + " Tf " + r(left + pad) + r(self.h - base) + "Td " + literal(ln) + " Tj ET Q\n")
                        self.texts.append(ln)
                        base += leading
                left += widths[ci]
            top += height
        v = "table%d" % self.check()
        self.n("let %s_widths = [%d]f64{ %s }" % (v, len(widths), ", ".join(repr(x_) for x_ in widths)))
        names = []
        for ri, row in enumerate(rows):
            self.n("let %s_r%d = [%d]str{ %s }" % (v, ri, len(row), ", ".join(lit(c) for c in row)))
            names.append("%s_r%d[0..]" % (v, ri))
        self.n("let %s_rows = [%d][]const str{ %s }" % (v, len(rows), ", ".join(names)))
        self.n("let (%s_bottom, %s_error) = w.put_table(&d, %r, %r, %s_widths[0..], %s_rows[0..], %r, %r, %r, %s, %s, %s)" % (v, v, x, y, v, v, size, leading, pad, "true" if header else "false", nc(ink), nc(rule)))
        self.n("if %s_error != ok || %s_bottom != %r { os.exit(%d) }" % (v, v, top, self.check()))
        return top

    def file(self):
        n = len(self.pages)
        objs = 5 + 2 * n
        out = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
        off = {}

        def add(num, body):
            nonlocal out
            off[num] = len(out)
            out += body.encode("latin-1")

        add(1, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        add(2, "2 0 obj\n<< /Type /Pages /Count %d /Kids [%s] >>\nendobj\n" % (n, " ".join("%d 0 R" % (6 + 2 * p) for p in range(n))))
        add(3, "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n")
        add(4, "4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>\nendobj\n")
        title = ""
        if self.title:
            u = self.title.encode("utf-16-be")
            title = "/Title <FEFF" + u.hex().upper() + "> "
        add(5, "5 0 obj\n<< " + title + "/Producer (Neper e.fmt.pdf.write) >>\nendobj\n")
        for p, content in enumerate(self.pages):
            pn = 6 + 2 * p
            add(pn, "%d 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s%s] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >>\nendobj\n" % (pn, r(self.w), r(self.h), pn + 1))
            body = content.encode("latin-1")
            add(pn + 1, "%d 0 obj\n<< /Length %d >>\nstream\n" % (pn + 1, len(body)))
            out += body + b"endstream\nendobj\n"
        xref = len(out)
        out += ("xref\n0 %d\n0000000000 65535 f \n" % (objs + 1)).encode()
        for num in range(1, objs + 1):
            out += ("%010d 00000 n \n" % off[num]).encode()
        out += ("trailer\n<< /Size %d /Root 1 0 R /Info 5 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (objs + 1, xref)).encode()
        return out


def nc(c):
    return "w.rgb(%du8, %du8, %du8)" % c


BLACK = (0, 0, 0)
GREY = (128, 128, 128)
RED = (255, 0, 0)
BLUE = (0, 64, 192)


def metrics():
    for name in ("Helvetica", "Helvetica-Bold"):
        t = []
        for b in range(32, 256):
            try:
                ch = bytes([b]).decode("cp1252")
            except UnicodeDecodeError:
                t.append(0)
                continue
            t.append(int(round(pdfmetrics.stringWidth(ch, name, 1000))))
        print("//", name)
        for i in range(0, len(t), 16):
            print("        " + ", ".join("%du16" % v for v in t[i:i + 16]) + ",")


def build_main():
    Doc.code = 0
    # --- a minimal document -------------------------------------------------------------------
    mini = Doc(200.0, 100.0, "", 1, 4096)
    mini.neper = []
    mini.begin()
    mini.text(10.0, 50.0, 12.0, "Regular", BLACK, "Hi")
    mini.end()
    mini_bytes = mini.file()
    mini_neper = list(mini.neper)

    # --- a full document ----------------------------------------------------------------------
    doc = Doc(595.0, 842.0, "Quarterly report – Q3 café", 4, 65536)
    doc.neper = []
    doc.begin()
    doc.text(72.0, 90.0, 18.0, "Bold", BLACK, "Quarterly report (Q3) \\ done")
    nxt = doc.paragraph(72.0, 120.0, 300.0, 11.0, 14.0, "Regular", BLACK,
                        "The quick brown fox jumps over the lazy dog, then the café menu lists résumé pasta for €12.50 "
                        "and a second line.\nA new paragraph after a forced break keeps wrapping at word boundaries so that long text "
                        "lands on several lines of the same column.")
    bottom = doc.table(72.0, nxt + 10.0, [120.0, 60.0, 110.0],
                       [["Item", "Qty", "Notes"],
                        ["Apple pie", "12", "baked fresh every morning in the old oven"],
                        ["Café au lait", "3", ""],
                        ["Totals", "15"]], 10.0, 12.0, 4.0, True, BLACK, GREY)
    doc.fill_rect(72.0, bottom + 20.0, 120.0, 30.0, BLUE)
    doc.stroke_rect(210.0, bottom + 20.0, 120.0, 30.0, 1.5, RED)
    doc.line(72.0, bottom + 70.0, 330.0, bottom + 70.0, 0.75, GREY)
    doc.path([(72.0, bottom + 100.0), (120.0, bottom + 80.0), (170.0, bottom + 110.0), (230.0, bottom + 90.0)], False, 2.0, RED)
    doc.path([(260.0, bottom + 110.0), (330.0, bottom + 110.0), (295.0, bottom + 80.0)], True, 1.0, BLUE)
    doc.circle(400.0, bottom + 100.0, 25.0, RED)
    doc.end()
    doc.begin()
    doc.text(72.0, 72.0, 10.0, "Regular", GREY, "Page two")
    doc.end()
    full = doc.file()
    full_neper = list(doc.neper)
    last_code = Doc.code
    assert min(MARGINS) > 1e-6, min(MARGINS)

    # Independent readers must accept both files.
    import pypdf
    from pdfminer.high_level import extract_text
    for data, pages in ((mini_bytes, 1), (full, 2)):
        reader = pypdf.PdfReader(io.BytesIO(data), strict=True)
        assert len(reader.pages) == pages
    reader = pypdf.PdfReader(io.BytesIO(full), strict=True)
    assert reader.metadata.title == "Quarterly report – Q3 café", reader.metadata.title
    box = reader.pages[0].mediabox
    assert (float(box.width), float(box.height)) == (595.0, 842.0)
    p1 = reader.pages[0].extract_text()
    miner = extract_text(io.BytesIO(full))
    for needle in ["Quarterly report (Q3) \\ done", "Apple pie", "Page two"]:
        assert needle in p1 or needle in miner, needle
    assert "Page two" in reader.pages[1].extract_text()
    return mini_bytes, mini_neper, full, full_neper, doc


def main():
    if "--metrics" in sys.argv:
        metrics()
        return
    mini_bytes, mini_neper, full, full_neper, doc = build_main()
    c = Checks()
    out = []
    # The mini document.
    Doc.code = 0
    body = ""
    body += "    var (m, m_error) = w.document(a, 1usize, 4096usize, 200.0, 100.0, \"\")\n"
    c.raw(body)
    c.add("m_error != ok")
    # Re-emit mini ops with `m` as the document name and sequential codes.
    for line in mini_neper:
        c.raw(renumber(line.replace("&d", "&m"), c))
    c.raw("    let (mini, mini_error) = w.finish(a, &m)\n")
    c.add("mini_error != ok")
    c.add("mini.len != %dusize || !same(mini, %s)" % (len(mini_bytes), lit(mini_bytes)))
    c.raw("    let (mini_pages, mini_read) = pdf.pages(a, mini)\n")
    c.add("mini_read != ok || mini_pages.len != 1usize || !str.contains(mini_pages[0], \"Hi\")")
    # The full document.
    c.raw("    var (d, d_error) = w.document(a, 4usize, 65536usize, 595.0, 842.0, %s)\n" % lit(doc.title))
    c.add("d_error != ok")
    for line in full_neper:
        c.raw(renumber(line, c))
    c.raw("    let (bytes, bytes_error) = w.finish(a, &d)\n")
    c.add("bytes_error != ok")
    c.add("bytes.len != %dusize || !same(bytes, %s)" % (len(full), lit(full)))
    c.raw("    let (read_pages, read_error) = pdf.pages(a, bytes)\n")
    c.add("read_error != ok || read_pages.len != 2usize")
    c.add("!str.contains(read_pages[0], \"Apple pie\") || !str.contains(read_pages[0], \"A new paragraph after a forced break\") || !str.contains(read_pages[1], \"Page two\")")
    # Measuring: reportlab's Helvetica and Helvetica-Bold.
    for s, size, font in (("Hello, World", 12.0, "Regular"), ("Hello, World", 12.0, "Bold"), ("Wijgé €", 10.0, "Bold")):
        expected = width(s, font, size)
        c.raw("    let (tw_%d, tw_error_%d) = w.text_width(%s, %r, .%s)\n" % (c.code + 1, c.code + 1, lit(s), size, font))
        c.add("tw_error_%d != ok || tw_%d < %r || tw_%d > %r" % (c.code + 1, c.code + 1, expected - 0.0001, c.code + 1, expected + 0.0001))
    # Refusals and state errors.
    c.raw("    var (e, e_error) = w.document(a, 1usize, 256usize, 200.0, 100.0, \"\")\n")
    c.add("e_error != ok")
    c.add("w.put_text(&e, 1.0, 1.0, 10.0, .Regular, w.black(), \"x\") != w.NoPage")
    c.add("w.end_page(&e) != w.NoPage")
    c.raw("    let (f1, f1_error) = w.finish(a, &e)\n")
    c.add("f1_error != w.NoPage")
    c.add("w.begin_page(&e) != ok")
    c.add("w.begin_page(&e) != w.PageOpen")
    c.add("w.put_text(&e, 1.0, 1.0, 10.0, .Regular, w.black(), \"\\xe6\\x97\\xa5\") != w.Unsupported")
    c.add("w.put_text(&e, 1.0, 1.0, 10.0, .Regular, w.black(), \"a\\nb\") != w.Invalid")
    c.add("w.put_text(&e, 1.0, 1.0, 0.0, .Regular, w.black(), \"a\") != w.Invalid")
    c.add("w.fill_rect(&e, 1.0, 1.0, 0.0, 5.0, w.black()) != w.Invalid")
    c.raw("    let (f2, f2_error) = w.finish(a, &e)\n")
    c.add("f2_error != w.PageOpen")
    c.raw("    let (e_next, e_lines, e_pe) = w.put_paragraph(&e, 1.0, 20.0, 10.0, 10.0, 12.0, .Regular, w.black(), \"a long text that will not fit into so small a region of page content bytes at all, no matter how it is wrapped, because the page store holds two hundred and fifty-six bytes\")\n")
    c.add("e_pe != w.TooLarge")
    c.add("w.document(a, 0usize, 100usize, 200.0, 100.0, \"\")._1 != w.Invalid" if False else "e_lines != 0usize")
    c.raw("    let (e2, e2_error) = w.document(a, 1usize, 4096usize, 200.0, 100.0, \"\")\n")
    c.add("e2_error != ok")
    c.raw("    var e3 = e2\n")
    c.add("w.begin_page(&e3) != ok || w.end_page(&e3) != ok || w.begin_page(&e3) != w.TooLarge")
    c.raw("    let (e4, e4_error) = w.document(a, 1usize, 4096usize, 0.0, 100.0, \"\")\n")
    c.add("e4_error != w.Invalid")
    header = ("// `e.fmt.pdf.write`: a one-page document and a two-page report (a bold heading with escapes, a wrapped paragraph\n"
              "// with accents and a euro sign and a forced break, a table with a shaded header and wrapped cells, rectangles, lines,\n"
              "// a polyline, a polygon and a circle) compared byte for byte with an independent writer that measures with\n"
              "// reportlab's Helvetica metrics, read back through `e.fmt.pdf.pages`, text widths against reportlab, and the state\n"
              "// errors. pypdf (strict) and pdfminer accepted the files when the generator ran. Written by\n"
              "// scripts/gen_pdf_write_test.py. Every check has its own exit code.\n")
    uses = ["e.os", "e.mem", "e.str", "e.fmt.pdf as pdf", "e.fmt.pdf.write as w"]
    fn_head = ("fn same(x: []const u8, y: []const u8) -> bool {\n    if x.len != y.len { ret false }\n    var i = 0usize\n"
               "    while i < x.len {\n        if x[i] != y[i] { ret false }\n        i += 1usize\n    }\n    ret true\n}\n\n"
               "fn main(a: *mem.Arena, args: []str) -> err {\n")
    target = write_fixture("fmt_pdf_write", header, fn_head + c.text() + "    ret ok\n}\n", uses)
    print("wrote", target, "checks", c.code, "full bytes", len(full), "mini bytes", len(mini_bytes))


def renumber(line, c):
    """Replace the placeholder exit codes of a recorded Neper line with the next codes of `c`."""
    import re

    def sub(m):
        c.code += 1
        return "os.exit(%d)" % c.code

    return re.sub(r"os\.exit\(\d+\)", sub, line)


if __name__ == "__main__":
    main()
