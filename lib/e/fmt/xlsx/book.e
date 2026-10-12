// XLSX workbook encode and decode over the `e.fmt.xlsx` cell model (L100). `encode` turns
// `[]xlsx.Sheet` -- the typed grids the import wizard already works on -- into a
// SpreadsheetML package for DataGrid and report export: text through a shared-strings
// table, numbers, booleans, dates (as serials with a date number format), a bold header
// row, column widths and merged ranges. `decode` reads such a package back to the same
// model, and also what Excel and openpyxl write: shared, inline and formula-string cells,
// DEFLATE-compressed parts, date cells found by their number format.
//
// Bounds are Excel's: 1,048,576 rows, 16,384 columns, a sheet name of 1 to 31 characters
// without `: \ / ? * [ ]`, not bracketed by an apostrophe, unique ignoring ASCII case; a
// text of at most 32,767 characters and none of the XML-illegal control characters; merges
// that stay inside the sheet and do not overlap. Dates run from 1900-01-01 (Excel's 1900
// leap-year quirk is honoured: the serial of 1900-03-01 is 61) to 9999-12-31.
//
// Not here: charts, pivots, formulas (a formula cell decodes as its cached value), rich
// text (runs are joined), styles beyond bold-header and date, comments, images, and
// compression of what is written (the package is stored, see `e.fmt.zip.write`). A
// `BadDate` cell is written as an empty cell, as Excel shows an invalid date.
//
// Memory: the package and every result live in the arena passed in.
use e.mem
use e.str
use e.algo.hash as hash
use e.fmt.xlsx as xlsx
use e.fmt.xml as xml
use e.fmt.zip as zip
use e.fmt.zip.write as zipw
use e.fmt.ooxml as ooxml

error BadSheetName
error BadLayout
error BadCell
error BadText
error TooLarge
error NoWorkbook
error BadWorkbook

type Width = struct { column: u32, chars: f64 }
type Merge = struct { row: u32, column: u32, rows: u32, columns: u32 }
type Layout = struct { widths: []const Width, merges: []const Merge, bold_header: bool }

// The shared-strings table while a workbook is written: open addressing over `slots`
// (an index into `strings`, or all ones for a free slot), `references` counting every use.
type Shared = struct { slots: []u32, strings: []str, unique: usize, references: usize }

const MAX_ROWS: usize = 1048576usize
const MAX_COLUMNS: usize = 16384usize
const MAX_TEXT_POINTS: usize = 32767usize
const MAX_NAME_POINTS: usize = 31usize
const MAX_SHEETS: usize = 255usize
const FREE: u32 = 4294967295u32

fn ns_main() -> str {
    ret "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
}

fn no_layout() -> Layout {
    ret Layout { widths: zero, merges: zero, bold_header: false }
}

// ---- dates -------------------------------------------------------------------------------

// Days since 1970-01-01 of a proleptic Gregorian date.
fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    var y = year
    if month <= 2u32 { y -= 1i64 }
    var era = y / 400i64
    if y < 0i64 && y % 400i64 != 0i64 { era -= 1i64 }
    let yoe = y - era * 400i64
    var shifted = i64(month) + 9i64
    if month > 2u32 { shifted = i64(month) - 3i64 }
    let doy = (153i64 * shifted + 2i64) / 5i64 + i64(day) - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

// The inverse: (year, month, day) of a day count since 1970-01-01.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719468i64
    var era = z / 146097i64
    if z < 0i64 && z % 146097i64 != 0i64 { era -= 1i64 }
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    let day = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
    var month = mp - 9i64
    if mp < 10i64 { month = mp + 3i64 }
    var year = yoe + era * 400i64
    if month <= 2i64 { year += 1i64 }
    ret (year, u32(month), u32(day))
}

fn leap_year(year: i64) -> bool {
    ret (year % 4i64 == 0i64 && year % 100i64 != 0i64) || year % 400i64 == 0i64
}

fn month_days(year: i64, month: u32) -> u32 {
    if month == 2u32 {
        if leap_year(year) { ret 29u32 }
        ret 28u32
    }
    if month == 4u32 || month == 6u32 || month == 9u32 || month == 11u32 { ret 30u32 }
    ret 31u32
}

// The Excel day serial of a date and whether it is representable (1900-01-01 .. 9999-12-31).
fn serial_days(year: i64, month: u32, day: u32) -> (i64, bool) {
    if year < 1900i64 || year > 9999i64 || month < 1u32 || month > 12u32 || day < 1u32 { ret (0i64, false) }
    if day > month_days(year, month) { ret (0i64, false) }
    let days = days_from_civil(year, month, day) + 25569i64
    // Excel counts a 1900-02-29 that never was, so dates before March 1900 sit one lower.
    if days <= 60i64 { ret (days - 1i64, true) }
    ret (days, true)
}

// ---- text helpers ------------------------------------------------------------------------

fn push_escaped(b: *str.Builder, s: str, attribute: bool) -> err {
    var i = 0usize
    var run = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 {
            rep = "&amp;"
        } else if c == 60u8 {
            rep = "&lt;"
        } else if c == 62u8 {
            rep = "&gt;"
        } else if attribute && c == 34u8 {
            rep = "&quot;"
        }
        if rep.len > 0usize {
            try str.push(b, s[run..i])
            try str.push(b, rep)
            run = i + 1usize
        }
        i += 1usize
    }
    ret str.push(b, s[run..s.len])
}

fn push_ref(b: *str.Builder, column: usize, row: usize) -> err {
    var letters: [8]u8 = zero
    var n = column + 1usize
    var at = 8usize
    while n > 0usize {
        n -= 1usize
        at -= 1usize
        letters[at] = 65u8 + u8(n % 26usize)
        n /= 26usize
    }
    try str.push(b, letters[at..8usize])
    ret str.push_usize(b, row + 1usize)
}

// A number as the shortest text that reads back: whole values without a point.
fn push_number(b: *str.Builder, v: f64) -> err {
    if v == f64(i64(v)) && v < 1000000000000000.0f64 && v > -1000000000000000.0f64 {
        ret str.push_i64(b, i64(v))
    }
    ret str.push_f64(b, v)
}

fn finite(v: f64) -> bool {
    ret v == v && v < 1.0e300f64 && v > -1.0e300f64
}

fn clean_text(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c < 32u8 && c != 9u8 && c != 10u8 && c != 13u8 { ret false }
        i += 1usize
    }
    ret true
}

fn valid_sheet_name(name: str) -> bool {
    let points = str.count_points(name)
    if points == 0usize || points > MAX_NAME_POINTS { ret false }
    if name[0usize] == 39u8 || name[name.len - 1usize] == 39u8 { ret false }
    var i = 0usize
    while i < name.len {
        let c = name[i]
        if c == 58u8 || c == 92u8 || c == 47u8 || c == 63u8 || c == 42u8 || c == 91u8 || c == 93u8 { ret false }
        if c < 32u8 { ret false }
        i += 1usize
    }
    ret true
}

// ---- shared strings ----------------------------------------------------------------------

fn shared_index(s: *Shared, value: str) -> u32 {
    s.references += 1usize
    let mask = u32(s.slots.len - 1usize)
    var at = hash.fnv1a32(value) & mask
    while true {
        let held = s.slots[usize(at)]
        if held == FREE {
            let index = u32(s.unique)
            s.slots[usize(at)] = index
            s.strings[s.unique] = value
            s.unique += 1usize
            ret index
        }
        if str.eq(s.strings[usize(held)], value) { ret held }
        at = (at + 1u32) & mask
    }
    ret 0u32
}

fn needs_preserve(value: str) -> bool {
    if value.len == 0usize { ret false }
    let first = value[0usize]
    let last = value[value.len - 1usize]
    ret first == 32u8 || first == 9u8 || first == 10u8 || last == 32u8 || last == 9u8 || last == 10u8
}

// ---- encode ------------------------------------------------------------------------------

// Checks one sheet against the bounds and counts its text cells.
fn check_sheet(sheet: xlsx.Sheet, layout: Layout) -> (usize, err) {
    if !valid_sheet_name(sheet.name) { ret (0usize, BadSheetName) }
    if sheet.grid.len > MAX_ROWS { ret (0usize, TooLarge) }
    var texts = 0usize
    var r = 0usize
    while r < sheet.grid.len {
        let row = sheet.grid[r]
        if row.len > MAX_COLUMNS { ret (0usize, TooLarge) }
        var c = 0usize
        while c < row.len {
            let cell = row[c]
            if cell.kind == .Text {
                if str.count_points(cell.text) > MAX_TEXT_POINTS { ret (0usize, BadText) }
                if !clean_text(cell.text) { ret (0usize, BadText) }
                texts += 1usize
            } else if cell.kind == .Number {
                if !finite(cell.number) { ret (0usize, BadCell) }
            } else if cell.kind == .Date {
                let (days, good) = serial_days(cell.year, cell.month, cell.day)
                if !good || cell.hour > 23u32 || cell.minute > 59u32 || cell.second > 59u32 { ret (0usize, BadCell) }
            }
            c += 1usize
        }
        r += 1usize
    }
    var w = 0usize
    while w < layout.widths.len {
        let width = layout.widths[w]
        if usize(width.column) >= MAX_COLUMNS || !finite(width.chars) || width.chars <= 0.0f64 || width.chars > 255.0f64 { ret (0usize, BadLayout) }
        if w > 0usize && width.column <= layout.widths[w - 1usize].column { ret (0usize, BadLayout) }
        w += 1usize
    }
    var m = 0usize
    while m < layout.merges.len {
        let one = layout.merges[m]
        if one.rows == 0u32 || one.columns == 0u32 || (one.rows == 1u32 && one.columns == 1u32) { ret (0usize, BadLayout) }
        if usize(one.row) + usize(one.rows) > MAX_ROWS || usize(one.column) + usize(one.columns) > MAX_COLUMNS { ret (0usize, BadLayout) }
        var k = 0usize
        while k < m {
            let other = layout.merges[k]
            let rows_apart = one.row >= other.row + other.rows || other.row >= one.row + one.rows
            let columns_apart = one.column >= other.column + other.columns || other.column >= one.column + one.columns
            if !rows_apart && !columns_apart { ret (0usize, BadLayout) }
            k += 1usize
        }
        m += 1usize
    }
    ret (texts, ok)
}

fn sheet_xml(a: *mem.Arena, sheet: xlsx.Sheet, layout: Layout, sst_table: *Shared) -> (str, err) {
    var rows_used = 0usize
    var widest = 0usize
    var r = 0usize
    while r < sheet.grid.len {
        let row = sheet.grid[r]
        var last = 0usize
        var c = 0usize
        while c < row.len {
            let kind = row[c].kind
            if kind != .Empty && kind != .BadDate { last = c + 1usize }
            c += 1usize
        }
        if last > 0usize {
            rows_used = r + 1usize
            if last > widest { widest = last }
        }
        r += 1usize
    }
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"")
    try str.push(&b, ns_main())
    try str.push(&b, "\">")
    if widest > 0usize {
        try str.push(&b, "<dimension ref=\"A1:")
        try push_ref(&b, widest - 1usize, rows_used - 1usize)
        try str.push(&b, "\"/>")
    }
    if layout.widths.len > 0usize {
        try str.push(&b, "<cols>")
        var w = 0usize
        while w < layout.widths.len {
            let width = layout.widths[w]
            try str.push(&b, "<col min=\"")
            try str.push_usize(&b, usize(width.column) + 1usize)
            try str.push(&b, "\" max=\"")
            try str.push_usize(&b, usize(width.column) + 1usize)
            try str.push(&b, "\" width=\"")
            try push_number(&b, width.chars)
            try str.push(&b, "\" customWidth=\"1\"/>")
            w += 1usize
        }
        try str.push(&b, "</cols>")
    }
    try str.push(&b, "<sheetData>")
    r = 0usize
    while r < rows_used {
        let row = sheet.grid[r]
        var any = false
        var c = 0usize
        while c < row.len {
            let kind = row[c].kind
            if kind != .Empty && kind != .BadDate { any = true }
            c += 1usize
        }
        if any {
            try str.push(&b, "<row r=\"")
            try str.push_usize(&b, r + 1usize)
            try str.push(&b, "\">")
            c = 0usize
            while c < row.len {
                let cell = row[c]
                var written = true
                var type_attr = ""
                var style = 0usize
                if layout.bold_header && r == 0usize { style = 1usize }
                if cell.kind == .Text {
                    type_attr = " t=\"s\""
                } else if cell.kind == .Bool {
                    type_attr = " t=\"b\""
                } else if cell.kind == .Date {
                    style = 2usize
                } else if cell.kind != .Number {
                    written = false
                }
                if written {
                    try str.push(&b, "<c r=\"")
                    try push_ref(&b, c, r)
                    try str.push(&b, "\"")
                    if style > 0usize {
                        try str.push(&b, " s=\"")
                        try str.push_usize(&b, style)
                        try str.push(&b, "\"")
                    }
                    try str.push(&b, type_attr)
                    try str.push(&b, "><v>")
                    if cell.kind == .Text {
                        try str.push_u32(&b, shared_index(sst_table, cell.text))
                    } else if cell.kind == .Bool {
                        if cell.flag { try str.push(&b, "1") } else { try str.push(&b, "0") }
                    } else if cell.kind == .Number {
                        try push_number(&b, cell.number)
                    } else {
                        let (days, good) = serial_days(cell.year, cell.month, cell.day)
                        let seconds = i64(cell.hour) * 3600i64 + i64(cell.minute) * 60i64 + i64(cell.second)
                        if seconds == 0i64 {
                            try str.push_i64(&b, days)
                        } else {
                            try str.push_f64(&b, f64(days) + f64(seconds) / 86400.0f64)
                        }
                    }
                    try str.push(&b, "</v></c>")
                }
                c += 1usize
            }
            try str.push(&b, "</row>")
        }
        r += 1usize
    }
    try str.push(&b, "</sheetData>")
    if layout.merges.len > 0usize {
        try str.push(&b, "<mergeCells count=\"")
        try str.push_usize(&b, layout.merges.len)
        try str.push(&b, "\">")
        var m = 0usize
        while m < layout.merges.len {
            let one = layout.merges[m]
            try str.push(&b, "<mergeCell ref=\"")
            try push_ref(&b, usize(one.column), usize(one.row))
            try str.push(&b, ":")
            try push_ref(&b, usize(one.column + one.columns - 1u32), usize(one.row + one.rows - 1u32))
            try str.push(&b, "\"/>")
            m += 1usize
        }
        try str.push(&b, "</mergeCells>")
    }
    try str.push(&b, "</worksheet>")
    ret (str.done(&b), ok)
}

fn styles_xml() -> str {
    ret r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\-mm\-dd\ hh:mm:ss"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#
}

fn content_types_xml(a: *mem.Arena, sheet_count: usize) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">")
    try str.push(&b, "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>")
    try str.push(&b, "<Default Extension=\"xml\" ContentType=\"application/xml\"/>")
    try str.push(&b, "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>")
    var i = 0usize
    while i < sheet_count {
        try str.push(&b, "<Override PartName=\"/xl/worksheets/sheet")
        try str.push_usize(&b, i + 1usize)
        try str.push(&b, ".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>")
        i += 1usize
    }
    try str.push(&b, "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>")
    try str.push(&b, "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>")
    try str.push(&b, "</Types>")
    ret (str.done(&b), ok)
}

fn root_rels_xml() -> str {
    ret r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#
}

fn workbook_xml(a: *mem.Arena, sheets: []const xlsx.Sheet) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<workbook xmlns=\"")
    try str.push(&b, ns_main())
    try str.push(&b, "\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>")
    var i = 0usize
    while i < sheets.len {
        try str.push(&b, "<sheet name=\"")
        try push_escaped(&b, sheets[i].name, true)
        try str.push(&b, "\" sheetId=\"")
        try str.push_usize(&b, i + 1usize)
        try str.push(&b, "\" r:id=\"rId")
        try str.push_usize(&b, i + 1usize)
        try str.push(&b, "\"/>")
        i += 1usize
    }
    try str.push(&b, "</sheets></workbook>")
    ret (str.done(&b), ok)
}

fn workbook_rels_xml(a: *mem.Arena, sheet_count: usize) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">")
    var i = 0usize
    while i < sheet_count {
        try str.push(&b, "<Relationship Id=\"rId")
        try str.push_usize(&b, i + 1usize)
        try str.push(&b, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet")
        try str.push_usize(&b, i + 1usize)
        try str.push(&b, ".xml\"/>")
        i += 1usize
    }
    try str.push(&b, "<Relationship Id=\"rId")
    try str.push_usize(&b, sheet_count + 1usize)
    try str.push(&b, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>")
    try str.push(&b, "<Relationship Id=\"rId")
    try str.push_usize(&b, sheet_count + 2usize)
    try str.push(&b, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>")
    try str.push(&b, "</Relationships>")
    ret (str.done(&b), ok)
}

fn shared_strings_xml(a: *mem.Arena, sst_table: *const Shared) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<sst xmlns=\"")
    try str.push(&b, ns_main())
    try str.push(&b, "\" count=\"")
    try str.push_usize(&b, sst_table.references)
    try str.push(&b, "\" uniqueCount=\"")
    try str.push_usize(&b, sst_table.unique)
    try str.push(&b, "\">")
    var i = 0usize
    while i < sst_table.unique {
        let value = sst_table.strings[i]
        if needs_preserve(value) {
            try str.push(&b, "<si><t xml:space=\"preserve\">")
        } else {
            try str.push(&b, "<si><t>")
        }
        try push_escaped(&b, value, false)
        try str.push(&b, "</t></si>")
        i += 1usize
    }
    try str.push(&b, "</sst>")
    ret (str.done(&b), ok)
}

// The workbook as a package: one worksheet per sheet, in order. `layouts` is empty or one
// per sheet.
fn encode(a: *mem.Arena, sheets: []const xlsx.Sheet, layouts: []const Layout) -> ([]u8, err) {
    if sheets.len == 0usize || sheets.len > MAX_SHEETS { ret (zero, TooLarge) }
    if layouts.len != 0usize && layouts.len != sheets.len { ret (zero, BadLayout) }
    var texts = 0usize
    var i = 0usize
    while i < sheets.len {
        var layout = no_layout()
        if layouts.len != 0usize { layout = layouts[i] }
        let (count, check_error) = check_sheet(sheets[i], layout)
        if check_error != ok { ret (zero, check_error) }
        texts += count
        var k = 0usize
        while k < i {
            if str.compare_ascii_fold(sheets[k].name, sheets[i].name) == 0i32 { ret (zero, BadSheetName) }
            k += 1usize
        }
        i += 1usize
    }
    var slot_count = 16usize
    while slot_count < texts * 2usize { slot_count *= 2usize }
    let (slots, slots_error) = mem.alloc[u32](a, slot_count)
    if slots_error != ok { ret (zero, slots_error) }
    i = 0usize
    while i < slot_count {
        slots[i] = FREE
        i += 1usize
    }
    let (strings, strings_error) = mem.alloc[str](a, texts + 1usize)
    if strings_error != ok { ret (zero, strings_error) }
    var sst_table = Shared { slots: slots, strings: strings, unique: 0usize, references: 0usize }
    let (parts, parts_error) = mem.alloc[zipw.Part](a, sheets.len + 6usize)
    if parts_error != ok { ret (zero, parts_error) }
    i = 0usize
    while i < sheets.len {
        var layout = no_layout()
        if layouts.len != 0usize { layout = layouts[i] }
        let (xml_text, xml_error) = sheet_xml(a, sheets[i], layout, &sst_table)
        if xml_error != ok { ret (zero, xml_error) }
        let (name, name_error) = sheet_part_name(a, i)
        if name_error != ok { ret (zero, name_error) }
        parts[6usize + i] = zipw.Part { name: name, data: xml_text }
        i += 1usize
    }
    let (types_text, types_error) = content_types_xml(a, sheets.len)
    if types_error != ok { ret (zero, types_error) }
    let (book_text, book_error) = workbook_xml(a, sheets)
    if book_error != ok { ret (zero, book_error) }
    let (rels_text, rels_error) = workbook_rels_xml(a, sheets.len)
    if rels_error != ok { ret (zero, rels_error) }
    let (sst_text, sst_error) = shared_strings_xml(a, &sst_table)
    if sst_error != ok { ret (zero, sst_error) }
    parts[0usize] = zipw.Part { name: "[Content_Types].xml", data: types_text }
    parts[1usize] = zipw.Part { name: "_rels/.rels", data: root_rels_xml() }
    parts[2usize] = zipw.Part { name: "xl/workbook.xml", data: book_text }
    parts[3usize] = zipw.Part { name: "xl/_rels/workbook.xml.rels", data: rels_text }
    parts[4usize] = zipw.Part { name: "xl/styles.xml", data: styles_xml() }
    parts[5usize] = zipw.Part { name: "xl/sharedStrings.xml", data: sst_text }
    let (package, package_error) = zipw.store(a, parts[0usize..sheets.len + 6usize])
    ret (package, package_error)
}

fn sheet_part_name(a: *mem.Arena, index: usize) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "xl/worksheets/sheet")
    try str.push_usize(&b, index + 1usize)
    try str.push(&b, ".xml")
    ret (str.done(&b), ok)
}

// ---- decode ------------------------------------------------------------------------------

fn local(name: str) -> str {
    ret ooxml.local(name)
}

fn is_element(nodes: []const xml.Node, n: usize, name: str) -> bool {
    ret nodes[n].kind == .Element && str.eq(local(nodes[n].name), name)
}

// The attribute of an element whose local name is `name`, whatever its prefix.
fn attr(node: *const xml.Node, name: str) -> (str, bool) {
    var i = 0usize
    while i < node.attributes.len {
        if str.eq(local(node.attributes[i].name), name) { ret (node.attributes[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn parent_index(nodes: []const xml.Node, n: usize) -> usize {
    ret usize(nodes[n].parent)
}

// Whether a custom number-format code shows a date or a time: a y, d, h or s (or an m)
// outside quotes, brackets and backslash escapes.
fn code_is_date(code: str) -> bool {
    var i = 0usize
    var quoted = false
    var bracket = false
    var seen = false
    while i < code.len {
        let c = code[i]
        if c == 92u8 || c == 95u8 {
            i += 2usize
            continue
        }
        if quoted {
            if c == 34u8 { quoted = false }
        } else if bracket {
            if c == 93u8 { bracket = false }
        } else if c == 34u8 {
            quoted = true
        } else if c == 91u8 {
            bracket = true
        } else if c == 121u8 || c == 89u8 || c == 100u8 || c == 68u8 || c == 104u8 || c == 72u8 || c == 115u8 || c == 83u8 || c == 109u8 || c == 77u8 {
            seen = true
        }
        i += 1usize
    }
    ret seen
}

fn builtin_date_format(id: u64) -> bool {
    ret (id >= 14u64 && id <= 22u64) || (id >= 45u64 && id <= 47u64)
}

// Per cell-format index: whether the format shows a date.
fn date_styles(a: *mem.Arena, nodes: []const xml.Node) -> ([]bool, err) {
    var xf_count = 0usize
    var i = 0usize
    while i < nodes.len {
        if is_element(nodes, i, "xf") && usize(nodes[i].parent) < nodes.len && is_element(nodes, usize(nodes[i].parent), "cellXfs") { xf_count += 1usize }
        i += 1usize
    }
    let (flags, flags_error) = mem.alloc[bool](a, xf_count + 1usize)
    if flags_error != ok { ret (zero, flags_error) }
    var k = 0usize
    i = 0usize
    while i < nodes.len {
        if is_element(nodes, i, "xf") && usize(nodes[i].parent) < nodes.len && is_element(nodes, usize(nodes[i].parent), "cellXfs") {
            var date = false
            let (id_text, has_id) = attr(&nodes[i], "numFmtId")
            if has_id {
                let (id, id_error) = str.parse_u64(id_text)
                if id_error == ok {
                    if builtin_date_format(id) { date = true }
                    var j = 0usize
                    while j < nodes.len && !date {
                        if is_element(nodes, j, "numFmt") {
                            let (fid_text, has_fid) = attr(&nodes[j], "numFmtId")
                            let (code, has_code) = attr(&nodes[j], "formatCode")
                            if has_fid && has_code && str.eq(fid_text, id_text) && code_is_date(code) { date = true }
                        }
                        j += 1usize
                    }
                }
            }
            flags[k] = date
            k += 1usize
        }
        i += 1usize
    }
    ret (flags[0usize..xf_count], ok)
}

// The shared strings in order: every text under an `si`, phonetic runs left out.
fn shared_strings(a: *mem.Arena, nodes: []const xml.Node) -> ([]str, err) {
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if is_element(nodes, i, "si") { count += 1usize }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[str](a, count + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var written = 0usize
    i = 0usize
    while i < nodes.len {
        if is_element(nodes, i, "si") {
            var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
            var j = i + 1usize
            // Document order: the item ends at the next `si`.
            while j < nodes.len && !is_element(nodes, j, "si") {
                if nodes[j].kind == .Text {
                    var phonetic = false
                    var up = parent_index(nodes, j)
                    while up < nodes.len && up != i {
                        if is_element(nodes, up, "rPh") { phonetic = true }
                        up = parent_index(nodes, up)
                    }
                    if !phonetic && up == i { try str.push(&b, nodes[j].value) }
                }
                j += 1usize
            }
            out[written] = str.done(&b)
            written += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..count], ok)
}

fn part_of(a: *mem.Arena, archive: *zip.Archive, name: str) -> ([]u8, bool, err) {
    let (index, found) = ooxml.find(archive, name)
    if !found { ret (zero, false, ok) }
    let (data, extract_error) = zip.extract(a, archive, index)
    if extract_error != ok { ret (zero, false, extract_error) }
    ret (data, true, ok)
}

fn floor_f64(v: f64) -> f64 {
    var whole = f64(i64(v))
    if whole > v { whole -= 1.0f64 }
    ret whole
}

// A day serial as local wall-clock components, or a `BadDate` cell.
fn date_from_serial(serial: f64) -> xlsx.Cell {
    if !finite(serial) || serial < 0.0f64 || serial >= 2958466.0f64 { ret xlsx.bad_date_cell() }
    var day = floor_f64(serial)
    var seconds = i64((serial - day) * 86400.0f64 + 0.5f64)
    var whole = i64(day)
    if seconds >= 86400i64 {
        seconds -= 86400i64
        whole += 1i64
    }
    if whole == 60i64 || whole >= 2958466i64 { ret xlsx.bad_date_cell() }
    var days = whole
    if whole < 60i64 { days = whole + 1i64 }
    let (year, month, dom) = civil_from_days(days - 25569i64)
    ret xlsx.date_cell(year, month, dom, u32(seconds / 3600i64), u32((seconds / 60i64) % 60i64), u32(seconds % 60i64))
}

type Raw = struct { column: usize, row: usize, kind: str, style: usize, value: str, inline: str }

// The cells of a worksheet part, placed in a grid.
fn read_sheet(a: *mem.Arena, part: []const u8, sst_table: []const str, dates: []const bool) -> ([]const []const xlsx.Cell, err) {
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, BadWorkbook) }
    let nodes = doc.nodes
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if is_element(nodes, i, "c") { count += 1usize }
        i += 1usize
    }
    let (raws, raws_error) = mem.alloc[Raw](a, count + 1usize)
    if raws_error != ok { ret (zero, raws_error) }
    var k = 0usize
    var row_number = 0usize
    var next_column = 0usize
    var max_row = 0usize
    var have_cells = false
    i = 0usize
    while i < nodes.len {
        if is_element(nodes, i, "row") {
            let (r_text, has_r) = attr(&nodes[i], "r")
            if has_r {
                let (parsed, parse_r_error) = str.parse_u64(r_text)
                if parse_r_error != ok || parsed == 0u64 || parsed > u64(MAX_ROWS) { ret (zero, BadWorkbook) }
                row_number = usize(parsed) - 1usize
            } else if have_cells || k > 0usize {
                row_number += 1usize
            }
            next_column = 0usize
        } else if is_element(nodes, i, "c") {
            var column = next_column
            let (ref_text, has_ref) = attr(&nodes[i], "r")
            var cell_row = row_number
            if has_ref {
                let (col_i, row_i, good) = xlsx.parse_cell_ref(ref_text)
                if !good || col_i >= i64(MAX_COLUMNS) || row_i >= i64(MAX_ROWS) { ret (zero, BadWorkbook) }
                column = usize(col_i)
                cell_row = usize(row_i)
            }
            if column >= MAX_COLUMNS { ret (zero, BadWorkbook) }
            next_column = column + 1usize
            var kind = ""
            let (t_text, has_t) = attr(&nodes[i], "t")
            if has_t { kind = t_text }
            var style = 0usize
            let (s_text, has_s) = attr(&nodes[i], "s")
            if has_s {
                let (parsed_style, style_error) = str.parse_u64(s_text)
                if style_error == ok { style = usize(parsed_style) }
            }
            raws[k] = Raw { column: column, row: cell_row, kind: kind, style: style, value: "", inline: "" }
            have_cells = true
            if cell_row + 1usize > max_row { max_row = cell_row + 1usize }
            k += 1usize
        } else if nodes[i].kind == .Text && k > 0usize {
            // Text under `v` is the value; text under a `t` inside `is` is inline text.
            let owner = parent_index(nodes, i)
            if owner < nodes.len {
                if is_element(nodes, owner, "v") {
                    raws[k - 1usize].value = nodes[i].value
                } else if is_element(nodes, owner, "t") {
                    let (joined, join_error) = str.concat(a, raws[k - 1usize].inline, nodes[i].value)
                    if join_error != ok { ret (zero, join_error) }
                    raws[k - 1usize].inline = joined
                }
            }
        }
        i += 1usize
    }
    if max_row == 0usize { ret (zero, ok) }
    // Widths of each row: the last column that carries a cell, plus one.
    let (widths, widths_error) = mem.alloc[usize](a, max_row)
    if widths_error != ok { ret (zero, widths_error) }
    i = 0usize
    while i < max_row {
        widths[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < k {
        if raws[i].column + 1usize > widths[raws[i].row] { widths[raws[i].row] = raws[i].column + 1usize }
        i += 1usize
    }
    let (grid, grid_error) = mem.alloc[[]const xlsx.Cell](a, max_row)
    if grid_error != ok { ret (zero, grid_error) }
    let (muts, muts_error) = mem.alloc[[]xlsx.Cell](a, max_row)
    if muts_error != ok { ret (zero, muts_error) }
    i = 0usize
    while i < max_row {
        let (row, row_error) = mem.alloc[xlsx.Cell](a, widths[i] + 1usize)
        if row_error != ok { ret (zero, row_error) }
        var c = 0usize
        while c < widths[i] {
            row[c] = xlsx.empty_cell()
            c += 1usize
        }
        muts[i] = row[0usize..widths[i]]
        grid[i] = muts[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        let raw = raws[i]
        var cell = xlsx.empty_cell()
        if str.eq(raw.kind, "s") {
            let (index, index_error) = str.parse_u64(raw.value)
            if index_error != ok || index >= u64(sst_table.len) { ret (zero, BadWorkbook) }
            cell = xlsx.text_cell(sst_table[usize(index)])
        } else if str.eq(raw.kind, "b") {
            cell = xlsx.bool_cell(str.eq(raw.value, "1"))
        } else if str.eq(raw.kind, "inlineStr") {
            cell = xlsx.text_cell(raw.inline)
        } else if str.eq(raw.kind, "str") || str.eq(raw.kind, "e") || str.eq(raw.kind, "d") {
            cell = xlsx.text_cell(raw.value)
        } else if raw.value.len > 0usize {
            let (number, number_error) = str.parse_f64(raw.value)
            if number_error != ok { ret (zero, BadWorkbook) }
            if raw.style < dates.len && dates[raw.style] {
                cell = date_from_serial(number)
            } else {
                cell = xlsx.number_cell(number)
            }
        }
        muts[raw.row][raw.column] = cell
        i += 1usize
    }
    ret (grid[0usize..max_row], ok)
}

// The sheets of a package, in workbook order.
fn decode(a: *mem.Arena, data: []const u8) -> ([]xlsx.Sheet, err) {
    let (archive, open_error) = ooxml.open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (book, has_book, book_error) = part_of(a, &ar, "xl/workbook.xml")
    if book_error != ok { ret (zero, book_error) }
    if !has_book { ret (zero, NoWorkbook) }
    let (book_doc, book_parse) = xml.parse(a, book)
    if book_parse != ok { ret (zero, BadWorkbook) }
    let (rels, has_rels, rels_error) = part_of(a, &ar, "xl/_rels/workbook.xml.rels")
    if rels_error != ok { ret (zero, rels_error) }
    if !has_rels { ret (zero, BadWorkbook) }
    let (rels_doc, rels_parse) = xml.parse(a, rels)
    if rels_parse != ok { ret (zero, BadWorkbook) }
    var sst_table: []const str = zero
    let (sst, has_sst, sst_error) = part_of(a, &ar, "xl/sharedStrings.xml")
    if sst_error != ok { ret (zero, sst_error) }
    if has_sst {
        let (sst_doc, sst_parse) = xml.parse(a, sst)
        if sst_parse != ok { ret (zero, BadWorkbook) }
        let (strings, strings_error) = shared_strings(a, sst_doc.nodes)
        if strings_error != ok { ret (zero, strings_error) }
        sst_table = strings
    }
    var dates: []const bool = zero
    let (styles, has_styles, styles_error) = part_of(a, &ar, "xl/styles.xml")
    if styles_error != ok { ret (zero, styles_error) }
    if has_styles {
        let (styles_doc, styles_parse) = xml.parse(a, styles)
        if styles_parse != ok { ret (zero, BadWorkbook) }
        let (flags, flags_error) = date_styles(a, styles_doc.nodes)
        if flags_error != ok { ret (zero, flags_error) }
        dates = flags
    }
    let book_nodes = book_doc.nodes
    var count = 0usize
    var i = 0usize
    while i < book_nodes.len {
        if is_element(book_nodes, i, "sheet") { count += 1usize }
        i += 1usize
    }
    if count == 0usize { ret (zero, BadWorkbook) }
    let (out, out_error) = mem.alloc[xlsx.Sheet](a, count)
    if out_error != ok { ret (zero, out_error) }
    var written = 0usize
    i = 0usize
    while i < book_nodes.len {
        if is_element(book_nodes, i, "sheet") {
            let (name, has_name) = attr(&book_nodes[i], "name")
            let (rid, has_rid) = attr(&book_nodes[i], "id")
            if !has_name || !has_rid { ret (zero, BadWorkbook) }
            // The target of relationship `rid`, relative to xl/.
            var target_path = ""
            var j = 0usize
            while j < rels_doc.nodes.len {
                if is_element(rels_doc.nodes, j, "Relationship") {
                    let (id_text, has_id) = attr(&rels_doc.nodes[j], "Id")
                    let (target_text, has_target) = attr(&rels_doc.nodes[j], "Target")
                    if has_id && has_target && str.eq(id_text, rid) { target_path = target_text }
                }
                j += 1usize
            }
            if target_path.len == 0usize { ret (zero, BadWorkbook) }
            var full = target_path
            if target_path[0usize] == 47u8 {
                full = target_path[1usize..target_path.len]
            } else {
                let (joined, join_error) = str.concat(a, "xl/", target_path)
                if join_error != ok { ret (zero, join_error) }
                full = joined
            }
            let (part, has_part, part_error) = part_of(a, &ar, full)
            if part_error != ok { ret (zero, part_error) }
            if !has_part { ret (zero, BadWorkbook) }
            let (grid, grid_error) = read_sheet(a, part, sst_table, dates)
            if grid_error != ok { ret (zero, grid_error) }
            out[written] = xlsx.Sheet { name: name, grid: grid }
            written += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}
