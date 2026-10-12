#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_xlsx_book/src/main.e (L100): `e.fmt.xlsx.book` encode and decode.

Oracles, all independent of the Neper code:
  * the expected bytes of `encode` come from a second writer written here against the same package layout
    (hand-built XML and Python's zipfile in ZIP_STORED with a fixed date), and the generator asserts that
    openpyxl loads those bytes back to the model (values, widths, merges, bold header, date formats);
  * `decode` reads a workbook written by openpyxl (DEFLATE, shared strings, merged cells, dates) and one written
    by XlsxWriter in constant-memory mode (inline strings, formulas with cached values), expectations being the
    values that went in, confirmed by reading the files back with openpyxl.
"""
import datetime as dt
import io
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import openpyxl  # noqa: E402
import xlsxwriter  # noqa: E402
from lane_e_common import Checks, lit, write_fixture  # noqa: E402

BAD = "BADDATE"


def col_letters(i):
    s = ""
    n = i + 1
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def esc(s, attr=False):
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s.replace('"', "&quot;") if attr else s


def num(v):
    v = float(v)
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    return repr(v)


def serial(d):
    days = (d.date() - dt.date(1899, 12, 30)).days
    if days <= 60:
        days -= 1
    secs = d.hour * 3600 + d.minute * 60 + d.second
    if secs == 0:
        return str(days)
    return repr(days + secs / 86400)


NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


def writable(v):
    return v is not None and v != BAD


def py_encode(sheets, layouts):
    strings, index, refs = [], {}, 0
    parts = []
    sheet_parts = []
    for si, (name, grid) in enumerate(sheets):
        widths, merges, bold = layouts[si]
        rows_used = widest = 0
        for r, row in enumerate(grid):
            last = max([c + 1 for c, v in enumerate(row) if writable(v)] or [0])
            if last:
                rows_used = r + 1
                widest = max(widest, last)
        x = XML + '<worksheet xmlns="%s">' % NS
        if widest:
            x += '<dimension ref="A1:%s%d"/>' % (col_letters(widest - 1), rows_used)
        if widths:
            x += "<cols>" + "".join('<col min="%d" max="%d" width="%s" customWidth="1"/>' % (c + 1, c + 1, num(w)) for c, w in widths) + "</cols>"
        x += "<sheetData>"
        for r in range(rows_used):
            row = grid[r]
            if not any(writable(v) for v in row):
                continue
            x += '<row r="%d">' % (r + 1)
            for c, v in enumerate(row):
                if not writable(v):
                    continue
                style = 1 if (bold and r == 0) else 0
                t = ""
                if isinstance(v, bool):
                    t = ' t="b"'
                    body = "1" if v else "0"
                elif isinstance(v, str):
                    t = ' t="s"'
                    if v not in index:
                        index[v] = len(strings)
                        strings.append(v)
                    refs += 1
                    body = str(index[v])
                elif isinstance(v, dt.datetime):
                    style = 2
                    body = serial(v)
                else:
                    body = num(v)
                s_attr = ' s="%d"' % style if style else ""
                x += '<c r="%s%d"%s%s><v>%s</v></c>' % (col_letters(c), r + 1, s_attr, t, body)
            x += "</row>"
        x += "</sheetData>"
        if merges:
            x += '<mergeCells count="%d">' % len(merges)
            for (r, c, nr, nc) in merges:
                x += '<mergeCell ref="%s%d:%s%d"/>' % (col_letters(c), r + 1, col_letters(c + nc - 1), r + nr)
            x += "</mergeCells>"
        x += "</worksheet>"
        sheet_parts.append(("xl/worksheets/sheet%d.xml" % (si + 1), x))
    ct = XML + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    ct += '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    ct += '<Default Extension="xml" ContentType="application/xml"/>'
    ct += '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    for i in range(len(sheets)):
        ct += '<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % (i + 1)
    ct += '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    ct += '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
    ct += "</Types>"
    rels = XML + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    wb = XML + '<workbook xmlns="%s" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' % NS
    for i, (name, _) in enumerate(sheets):
        wb += '<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % (esc(name, True), i + 1, i + 1)
    wb += "</sheets></workbook>"
    wr = XML + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    for i in range(len(sheets)):
        wr += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % (i + 1, i + 1)
    n = len(sheets)
    wr += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' % (n + 1)
    wr += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>' % (n + 2)
    wr += "</Relationships>"
    styles = XML + ('<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd\\ hh:mm:ss"/></numFmts>'
                    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
                    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
                    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
                    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
                    '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
                    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
                    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
                    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>')
    sst = XML + '<sst xmlns="%s" count="%d" uniqueCount="%d">' % (NS, refs, len(strings))
    for s in strings:
        keep = s[0] in " \t\n" or s[-1] in " \t\n"
        sst += '<si><t%s>%s</t></si>' % (' xml:space="preserve"' if keep else "", esc(s))
    sst += "</sst>"
    parts = [("[Content_Types].xml", ct), ("_rels/.rels", rels), ("xl/workbook.xml", wb), ("xl/_rels/workbook.xml.rels", wr),
             ("xl/styles.xml", styles), ("xl/sharedStrings.xml", sst)] + sheet_parts
    return py_zip([(n, t.encode("utf-8")) for n, t in parts])


def py_zip(parts):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        for name, data in parts:
            zi = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_STORED
            zi.create_system = 0
            z.writestr(zi, data)
    return out.getvalue()


# ---- the model ---------------------------------------------------------------------------------------

D1 = dt.datetime(2024, 2, 29, 13, 30, 15)
D2 = dt.datetime(1900, 3, 1)
D3 = dt.datetime(1900, 1, 1)
D4 = dt.datetime(9999, 12, 31, 23, 59, 59)

DATA = [
    ["Name", "Qty", "When", "Ok"],
    ["apple & <pear> \"x\"", 2.5, D1, True],
    [" lead and tail ", 100, D2, False, "tail"],
    [None, -0.25, D3, None, None, 1234567.891],
    ["line1\nline2", 0, D4, BAD],
    [],
    ["after a gap", 0.1, None, None, "é ü 日本 \U0001F600"],
]
SECOND = [["only"], ["x"], ["x"], [7], ["x"]]
SHEETS = [("Data", DATA), ("Second", SECOND)]
LAYOUTS = [([(0, 24.5), (2, 20), (5, 8.25)], [(5, 0, 1, 2), (1, 4, 2, 2)], True), ([], [], False)]


def to_py(v):
    return v


def neper_cell(v):
    if v is None:
        return "xlsx.empty_cell()"
    if v == BAD:
        return "xlsx.bad_date_cell()"
    if isinstance(v, bool):
        return "xlsx.bool_cell(%s)" % ("true" if v else "false")
    if isinstance(v, str):
        return "xlsx.text_cell(%s)" % lit(v)
    if isinstance(v, dt.datetime):
        return "xlsx.date_cell(%di64, %du32, %du32, %du32, %du32, %du32)" % (v.year, v.month, v.day, v.hour, v.minute, v.second)
    return "xlsx.number_cell(%s)" % f64(v)


def f64(v):
    return repr(float(v)) + "f64"


def cell_cond(expr, v):
    """A condition that is true when the decoded cell `expr` does NOT hold the expected value."""
    if v is None or v == BAD:
        return "%s.kind != .Empty" % expr if v is None else "%s.kind != .BadDate" % expr
    if isinstance(v, bool):
        return "%s.kind != .Bool || %s%s.flag" % (expr, "!" if v else "", expr)
    if isinstance(v, str):
        return "%s.kind != .Text || !str.eq(%s.text, %s)" % (expr, expr, lit(v))
    if isinstance(v, dt.datetime):
        return ("%s.kind != .Date || %s.year != %di64 || %s.month != %du32 || %s.day != %du32 || %s.hour != %du32 || %s.minute != %du32 || %s.second != %du32"
                % (expr, expr, v.year, expr, v.month, expr, v.day, expr, v.hour, expr, v.minute, expr, v.second))
    return "%s.kind != .Number || %s.number != %s" % (expr, expr, f64(v))


def grid_checks(c, var, grid, trim=True):
    """Row-by-row checks of a decoded grid (`var` is a `[]const xlsx.Sheet` element's grid)."""
    rows = [list(r) for r in grid]
    if trim:
        while rows and not any(v is not None and v != BAD for v in rows[-1]):
            rows.pop()
        for r in rows:
            while r and (r[-1] is None or r[-1] == BAD) and False:
                r.pop()
    c.add("%s.len != %dusize" % (var, len(rows)))
    for r, row in enumerate(rows):
        width = len(row)
        # The decoder's width is the last cell the file carries; Empty cells are not written, so
        # compare through the last written cell and let the rest be absent.
        last = 0
        for i, v in enumerate(row):
            if v is not None and v != BAD:
                last = i + 1
        c.add("%s[%d].len != %dusize" % (var, r, last))
        for i in range(last):
            pass
        conds = []
        for i in range(last):
            conds.append("(%s)" % cell_cond("%s[%d][%d]" % (var, r, i), row[i] if (row[i] != BAD) else None))
        if conds:
            c.add(" || ".join(conds))


def main():
    c = Checks()
    out = []
    # Model arrays.
    for si, (name, grid) in enumerate(SHEETS):
        for r, row in enumerate(grid):
            n = len(row)
            if n == 0:
                continue
            out.append("    let s%dr%d = [%d]xlsx.Cell{ %s }\n" % (si, r, n, ", ".join(neper_cell(v) for v in row)))
        out.append("    let s%dg = [%d][]const xlsx.Cell{ %s }\n" % (si, len(grid), ", ".join(("s%dr%d[0..]" % (si, r)) if len(row) else "s%dr%d[0..0]" % (si, r) for r, row in enumerate(grid))))
    # Empty rows: a zero-length slice taken from a neighbour keeps the literal simple.
    text = "".join(out)
    for si, (name, grid) in enumerate(SHEETS):
        for r, row in enumerate(grid):
            if len(row) == 0:
                text = text.replace("s%dr%d[0..0]" % (si, r), "s%dr%d[0..0]" % (si, 0))
    body = text
    body += "    let sheets = [2]xlsx.Sheet{ xlsx.Sheet { name: %s, grid: s0g[0..] }, xlsx.Sheet { name: %s, grid: s1g[0..] } }\n" % (lit(SHEETS[0][0]), lit(SHEETS[1][0]))
    widths0 = LAYOUTS[0][0]
    merges0 = LAYOUTS[0][1]
    body += "    let widths0 = [%d]book.Width{ %s }\n" % (len(widths0), ", ".join("book.Width { column: %du32, chars: %s }" % (col, f64(w)) for col, w in widths0))
    body += "    let merges0 = [%d]book.Merge{ %s }\n" % (len(merges0), ", ".join("book.Merge { row: %du32, column: %du32, rows: %du32, columns: %du32 }" % m for m in merges0))
    body += "    let layouts = [2]book.Layout{ book.Layout { widths: widths0[0..], merges: merges0[0..], bold_header: true }, book.no_layout() }\n"
    expected = py_encode(SHEETS, LAYOUTS)
    # openpyxl must accept the bytes and see the model.
    wb = openpyxl.load_workbook(io.BytesIO(expected))
    ws = wb["Data"]
    assert ws["A2"].value == DATA[1][0] and ws["B2"].value == 2.5 and ws["C2"].value == D1 and ws["D2"].value is True
    assert ws["A1"].font.b and not ws["A2"].font.b
    assert ws.column_dimensions["A"].width == 24.5 and ws.column_dimensions["C"].width == 20
    assert sorted(str(m) for m in ws.merged_cells.ranges) == sorted(["A6:B6", "E2:F3"]), ws.merged_cells.ranges
    assert ws["C3"].value == D2 and ws["C4"].value == D3 and ws["C5"].value == D4
    assert wb["Second"]["A4"].value == 7
    body += "    let want = %s\n" % lit(expected)
    body += "    let (bytes, encode_error) = book.encode(a, sheets[0..], layouts[0..])\n"
    c.raw(body)
    c.add("encode_error != ok")
    c.add("bytes.len != %dusize" % len(expected))
    c.add("!same(bytes, want)")
    # Decode own output.
    c.raw("    let (back, back_error) = book.decode(a, bytes)\n")
    c.add("back_error != ok")
    c.add("back.len != 2usize")
    c.add("!str.eq(back[0].name, \"Data\") || !str.eq(back[1].name, \"Second\")")
    grid_checks(c, "back[0].grid", DATA)
    grid_checks(c, "back[1].grid", SECOND)

    # openpyxl-written workbook.
    ob = openpyxl.Workbook()
    w1 = ob.active
    w1.title = "Sheet"
    OP1 = [
        ["Äpfel & Birnen", 3.14159, True, dt.datetime(2021, 12, 31, 23, 59, 59)],
        ["line1\nline2", -0.5, False, dt.datetime(2020, 1, 2)],
        [],
        [],
        [None, None, None, None, "far"],
        [],
        ["merged", None],
    ]
    for r, row in enumerate(OP1):
        for ci, v in enumerate(row):
            if v is not None:
                w1.cell(row=r + 1, column=ci + 1, value=v)
    w1.merge_cells("A7:B7")
    ob.create_sheet("Sheet 2")
    bio = io.BytesIO()
    ob.save(bio)
    op_bytes = bio.getvalue()
    check = openpyxl.load_workbook(io.BytesIO(op_bytes), data_only=True)
    for r, row in enumerate(OP1):
        for ci, v in enumerate(row):
            got = check["Sheet"].cell(row=r + 1, column=ci + 1).value
            assert got == v, (r, ci, got, v)
    c.raw("    let (op, op_error) = book.decode(a, %s)\n" % lit(op_bytes))
    c.add("op_error != ok")
    c.add("op.len != 2usize || !str.eq(op[0].name, \"Sheet\") || !str.eq(op[1].name, \"Sheet 2\")")
    grid_checks(c, "op[0].grid", OP1)
    c.add("op[1].grid.len != 0usize")

    # XlsxWriter, constant-memory mode: inline strings, formulas with cached values.
    xb = io.BytesIO()
    xw = xlsxwriter.Workbook(xb, {"in_memory": True, "constant_memory": True})
    sh = xw.add_worksheet("Inline")
    datefmt = xw.add_format({"num_format": "dd/mm/yyyy hh:mm"})
    sh.write_string(0, 0, "inline text & more")
    sh.write_number(0, 1, 7)
    sh.write_boolean(0, 2, True)
    sh.write_datetime(1, 0, dt.datetime(2022, 7, 4, 6, 5, 0), datefmt)
    sh.write_formula(1, 1, "=B1*2", None, 14)
    sh.write_formula(1, 2, '="a"&"b"', None, "ab")
    sh.write_string(3, 4, "last")
    xw.close()
    xl_bytes = xb.getvalue()
    XL = [
        ["inline text & more", 7, True],
        [dt.datetime(2022, 7, 4, 6, 5, 0), 14, "ab"],
        [],
        [None, None, None, None, "last"],
    ]
    check = openpyxl.load_workbook(io.BytesIO(xl_bytes), data_only=True)["Inline"]
    for r, row in enumerate(XL):
        for ci, v in enumerate(row):
            if v is not None:
                assert check.cell(row=r + 1, column=ci + 1).value == v, (r, ci)
    c.raw("    let (xl, xl_error) = book.decode(a, %s)\n" % lit(xl_bytes))
    c.add("xl_error != ok")
    c.add("xl.len != 1usize || !str.eq(xl[0].name, \"Inline\")")
    grid_checks(c, "xl[0].grid", XL)

    # The zip writer on its own, against zipfile, and read back through e.fmt.zip.
    zdata = py_zip([("a.txt", b"hello"), ("dir/b.bin", b"\x00\x01\x02\xff")])
    c.raw('    let zparts = [2]zipw.Part{ zipw.Part { name: "a.txt", data: "hello" }, zipw.Part { name: "dir/b.bin", data: "\\x00\\x01\\x02\\xff" } }\n')
    c.raw("    let (zbytes, zerror) = zipw.store(a, zparts[0..])\n")
    c.add("zerror != ok")
    c.add("zbytes.len != %dusize || !same(zbytes, %s)" % (len(zdata), lit(zdata)))
    c.raw("    let (zarchive, zopen) = ooxml.open_package(a, zbytes)\n")
    c.add("zopen != ok")
    c.raw('    var zar = zarchive\n    let (zindex, zfound) = ooxml.find(&zar, "dir/b.bin")\n')
    c.add("!zfound || zindex != 1usize")
    c.raw("    let (zextract, zextract_error) = zip.extract(a, &zar, zindex)\n")
    c.add("zextract_error != ok || zextract.len != 4usize || zextract[3] != 255u8")
    c.raw('    let bad_part = [1]zipw.Part{ zipw.Part { name: "../x", data: "d" } }\n')
    c.raw("    let (zb, zb_error) = zipw.store(a, bad_part[0..])\n")
    c.add("zb_error != zipw.BadName")
    c.raw("    let (zn, zn_error) = zipw.store(a, zparts[0..0])\n")
    c.add("zn_error != zipw.TooLarge")

    # Refusals.
    c.raw("    let one = [1]xlsx.Cell{ xlsx.number_cell(1.0) }\n")
    c.raw("    let one_grid = [1][]const xlsx.Cell{ one[0..] }\n")

    # (the counter is bumped inside add, so name probes by the code the check will carry)
    def refusal(name_expr, error, grid_expr="one_grid[0..]", layouts="zero"):
        n = c.code + 1
        c.raw("    let probe_%d = [1]xlsx.Sheet{ xlsx.Sheet { name: %s, grid: %s } }\n" % (n, name_expr, grid_expr))
        c.raw("    let (junk_%d, junk_error_%d) = book.encode(a, probe_%d[0..], %s)\n" % (n, n, n, layouts))
        c.add("junk_error_%d != %s" % (n, error))

    refusal(lit("a:b"), "book.BadSheetName")
    refusal(lit(""), "book.BadSheetName")
    refusal(lit("0123456789012345678901234567890X"), "book.BadSheetName")
    refusal(lit("'quoted'"), "book.BadSheetName")
    # A duplicate name ignoring case.
    n = c.code + 1
    c.raw("    let dup_%d = [2]xlsx.Sheet{ xlsx.Sheet { name: \"Data\", grid: one_grid[0..] }, xlsx.Sheet { name: \"DATA\", grid: one_grid[0..] } }\n" % n)
    c.raw("    let (junk_%d, junk_error_%d) = book.encode(a, dup_%d[0..], zero)\n" % (n, n, n))
    c.add("junk_error_%d != book.BadSheetName" % n)
    # Text with a control character; a date before 1900; a Feb 30; overlapping merges; merge of one cell;
    # widths out of order; layouts of the wrong count.
    c.raw("    let bad_text = [1]xlsx.Cell{ xlsx.text_cell(\"a\\x01b\") }\n    let bad_text_grid = [1][]const xlsx.Cell{ bad_text[0..] }\n")
    refusal(lit("T"), "book.BadText", "bad_text_grid[0..]")
    c.raw("    let early = [1]xlsx.Cell{ xlsx.date_cell(1899i64, 12u32, 31u32, 0u32, 0u32, 0u32) }\n    let early_grid = [1][]const xlsx.Cell{ early[0..] }\n")
    refusal(lit("T"), "book.BadCell", "early_grid[0..]")
    c.raw("    let feb = [1]xlsx.Cell{ xlsx.date_cell(2023i64, 2u32, 29u32, 0u32, 0u32, 0u32) }\n    let feb_grid = [1][]const xlsx.Cell{ feb[0..] }\n")
    refusal(lit("T"), "book.BadCell", "feb_grid[0..]")
    c.raw("    let overlap = [2]book.Merge{ book.Merge { row: 0u32, column: 0u32, rows: 2u32, columns: 2u32 }, book.Merge { row: 1u32, column: 1u32, rows: 2u32, columns: 2u32 } }\n")
    c.raw("    let overlap_layout = [1]book.Layout{ book.Layout { widths: zero, merges: overlap[0..], bold_header: false } }\n")
    refusal(lit("T"), "book.BadLayout", "one_grid[0..]", "overlap_layout[0..]")
    c.raw("    let single = [1]book.Merge{ book.Merge { row: 0u32, column: 0u32, rows: 1u32, columns: 1u32 } }\n")
    c.raw("    let single_layout = [1]book.Layout{ book.Layout { widths: zero, merges: single[0..], bold_header: false } }\n")
    refusal(lit("T"), "book.BadLayout", "one_grid[0..]", "single_layout[0..]")
    c.raw("    let unsorted = [2]book.Width{ book.Width { column: 3u32, chars: 10.0f64 }, book.Width { column: 1u32, chars: 10.0f64 } }\n")
    c.raw("    let unsorted_layout = [1]book.Layout{ book.Layout { widths: unsorted[0..], merges: zero, bold_header: false } }\n")
    refusal(lit("T"), "book.BadLayout", "one_grid[0..]", "unsorted_layout[0..]")
    c.raw("    let out_of_sheet = [1]book.Merge{ book.Merge { row: 1048575u32, column: 0u32, rows: 2u32, columns: 1u32 } }\n")
    c.raw("    let out_layout = [1]book.Layout{ book.Layout { widths: zero, merges: out_of_sheet[0..], bold_header: false } }\n")
    refusal(lit("T"), "book.BadLayout", "one_grid[0..]", "out_layout[0..]")
    # Sixteen thousand three hundred eighty-five columns.
    c.raw("    let (wide, wide_error) = mem.alloc[xlsx.Cell](a, 16385usize)\n")
    c.add("wide_error != ok")
    c.raw("    var wi = 0usize\n    while wi < wide.len {\n        wide[wi] = xlsx.empty_cell()\n        wi += 1usize\n    }\n")
    c.raw("    let wide_grid = [1][]const xlsx.Cell{ wide[0..] }\n")
    refusal(lit("T"), "book.TooLarge", "wide_grid[0..]")
    # No workbook part and not a zip.
    c.raw("    let (nb, nb_error) = book.decode(a, %s)\n" % lit(plain_zip()))
    c.add("nb_error != book.NoWorkbook")
    c.raw("    let (nj, nj_error) = book.decode(a, \"\\x01\\x02\\x03\\x04\\x05\\x06\\x07\\x08\")\n")
    c.add("nj_error != ooxml.NotAPackage")

    header = ("// `e.fmt.xlsx.book`: a two-sheet workbook (text with entities and edge whitespace, numbers, booleans, dates across the\n"
              "// 1900 leap-year quirk and to 9999, a bold header row, column widths, merged ranges) encoded and compared byte for\n"
              "// byte with an independent writer, then decoded back; workbooks written by openpyxl (DEFLATE, shared strings,\n"
              "// merges) and XlsxWriter (inline strings, formulas) decoded; and the refusals. Written by\n"
              "// scripts/gen_xlsx_book_test.py. Every check has its own exit code.\n")
    uses = ["e.os", "e.mem", "e.str", "e.fmt.xlsx as xlsx", "e.fmt.xlsx.book as book", "e.fmt.ooxml as ooxml", "e.fmt.zip as zip", "e.fmt.zip.write as zipw"]
    fn_head = ("fn same(x: []const u8, y: []const u8) -> bool {\n    if x.len != y.len { ret false }\n    var i = 0usize\n"
               "    while i < x.len {\n        if x[i] != y[i] { ret false }\n        i += 1usize\n    }\n    ret true\n}\n\n"
               "fn main(a: *mem.Arena, args: []str) -> err {\n")
    target = write_fixture("fmt_xlsx_book", header, fn_head + c.text() + "    ret ok\n}\n", uses)
    print("wrote", target, "checks", c.code)


def plain_zip():
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        z.writestr("hello.txt", "no workbook here\n")
    return out.getvalue()


if __name__ == "__main__":
    main()
