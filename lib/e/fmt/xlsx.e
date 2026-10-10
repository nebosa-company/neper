// Spreadsheet sheet-to-table normalisation (L044), after Appdor's `src/io/xlsx.js`: a sheet already read into an array of
// typed cells becomes the `{headers, rows}` table an import wizard consumes. A cell renders as the text it meant (a zero
// stays `0`, a boolean is `true`/`false`, a date is its local wall-clock `YYYY-MM-DD`, with ` HH:MM:SS` only when it is not
// midnight); the header row is found by the first row filling more than half of the widest of the first ten; blank and
// duplicate headings are renamed by the CSV rule (`Column 4`, `Status 2`) so the two formats cannot drift apart; the
// width is the last column that carries something, header or data. Also `parse_cell_ref` (`AB12` to zero-based column and
// row), `sheet_formulas` and `describe_sheets` (which sheet a caller gets, and which it does not).
//
// The OOXML container (zip, shared strings, styles) is not read here: Appdor leaves that to the spreadsheet library at one
// call site, so there is no reference to check a reader against.
//
// ponytail: a cell reference with more than 12 letters or 18 digits overflows i64 where JavaScript loses precision.
//
// Memory: the arena is retained; every table lives in it.

use e.algo.formula as f
use e.algo.formula.text as tx
use e.mem
use e.str
use e.text.utf8 as utf8

type Kind = enum u8 { Empty, Text, Number, Bool, Date, BadDate }

// A typed cell. `Date` carries local wall-clock components; `BadDate` is an invalid `Date` object.
type Cell = struct { kind: Kind, text: str, number: f64, flag: bool, year: i64, month: u32, day: u32, hour: u32, minute: u32, second: u32 }

type Renamed = struct { index: usize, from: str, to: str }

type Table = struct { headers: []const str, rows: []const []const str, header_row: usize, skipped_rows: usize, renamed: []const Renamed }

type Sheet = struct { name: str, grid: []const []const Cell }

// A header-row pin by sheet name.
type Pin = struct { name: str, row: i64 }

type Named = struct { name: str, table: Table }

type Formula = struct { reference: str, column: i64, row: i64, formula: str }

// A worksheet cell's address and its `f` property when that is a string (`has_formula`).
type FormulaCell = struct { reference: str, has_formula: bool, formula: str }

type Description = struct { names: []const str, chosen: str, has_chosen: bool, ignored: []const str, needs_choice: bool }

const HEADER_SCAN_ROWS: usize = 10usize

fn empty_cell() -> Cell {
    ret Cell { kind: .Empty, text: "", number: 0.0f64, flag: false, year: 0i64, month: 0u32, day: 0u32, hour: 0u32, minute: 0u32, second: 0u32 }
}

fn text_cell(s: str) -> Cell {
    var c = empty_cell()
    c.kind = .Text
    c.text = s
    ret c
}

fn number_cell(n: f64) -> Cell {
    var c = empty_cell()
    c.kind = .Number
    c.number = n
    ret c
}

fn bool_cell(b: bool) -> Cell {
    var c = empty_cell()
    c.kind = .Bool
    c.flag = b
    ret c
}

fn date_cell(year: i64, month: u32, day: u32, hour: u32, minute: u32, second: u32) -> Cell {
    var c = empty_cell()
    c.kind = .Date
    c.year = year
    c.month = month
    c.day = day
    c.hour = hour
    c.minute = minute
    c.second = second
    ret c
}

fn bad_date_cell() -> Cell {
    var c = empty_cell()
    c.kind = .BadDate
    ret c
}

// A text in JavaScript's `trim`.
fn js_trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    var go = true
    while go && from < to {
        var it = utf8.iterator(s[from..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && tx.js_space(scalar) {
            if scalar < 128u32 {
                from += 1usize
            } else if scalar < 2048u32 {
                from += 2usize
            } else {
                from += 3usize
            }
        } else {
            go = false
        }
    }
    go = true
    while go && to > from {
        var k = to - 1usize
        while k > from && (s[k] & 192u8) == 128u8 { k -= 1usize }
        var it = utf8.iterator(s[k..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && tx.js_space(scalar) {
            to = k
        } else {
            go = false
        }
    }
    ret s[from..to]
}

fn pad2(a: *mem.Arena, n: u32) -> str {
    if n < 10u32 { ret f.join(a, "0", f.number_text(a, f64(n))) }
    ret f.number_text(a, f64(n))
}

// One cell as the string the import wizard expects.
fn normalize_cell(a: *mem.Arena, c: Cell) -> str {
    if c.kind == .Empty || c.kind == .BadDate { ret "" }
    if c.kind == .Date {
        let day = f.join(a, f.join(a, f.join(a, f.number_text(a, f64(c.year)), "-"), f.join(a, pad2(a, c.month), "-")), pad2(a, c.day))
        if c.hour == 0u32 && c.minute == 0u32 && c.second == 0u32 { ret day }
        let clock = f.join(a, f.join(a, f.join(a, pad2(a, c.hour), ":"), f.join(a, pad2(a, c.minute), ":")), pad2(a, c.second))
        ret f.join(a, f.join(a, day, " "), clock)
    }
    if c.kind == .Bool {
        if c.flag { ret "true" }
        ret "false"
    }
    if c.kind == .Number {
        if c.number != c.number || c.number - c.number != 0.0f64 { ret "" }
        ret f.number_text(a, c.number)
    }
    ret js_trim(c.text)
}

fn filled_cells(a: *mem.Arena, row: []const Cell) -> usize {
    var n = 0usize
    var i = 0usize
    while i < row.len {
        if normalize_cell(a, row[i]).len != 0usize { n += 1usize }
        i += 1usize
    }
    ret n
}

// Which row of a sheet is the header row: the first of the first ten that fills more than half of the widest of them,
// and row 0 when the widest has fewer than two cells.
fn detect_header_row(a: *mem.Arena, grid: []const []const Cell) -> usize {
    var scan = grid.len
    if scan > HEADER_SCAN_ROWS { scan = HEADER_SCAN_ROWS }
    var best = 0usize
    var i = 0usize
    while i < scan {
        let n = filled_cells(a, grid[i])
        if n > best { best = n }
        i += 1usize
    }
    if best < 2usize { ret 0usize }
    i = 0usize
    while i < scan {
        if filled_cells(a, grid[i]) * 2usize > best { ret i }
        i += 1usize
    }
    ret 0usize
}

// The last column of `row` that carries something, as a width.
fn last_filled(a: *mem.Arena, row: []const Cell) -> usize {
    var i = row.len
    while i > 0usize {
        if normalize_cell(a, row[i - 1usize]).len != 0usize { ret i }
        i -= 1usize
    }
    ret 0usize
}

fn last_filled_text(row: []const str) -> usize {
    var i = row.len
    while i > 0usize {
        if row[i - 1usize].len != 0usize { ret i }
        i -= 1usize
    }
    ret 0usize
}

// Empty and duplicate headings named deterministically: a blank is `Column N`, a repeat `name 2`, `name 3`.
fn resolve_headers(a: *mem.Arena, raw: []const str, width: usize) -> ([]str, err) {
    let (out, oe) = mem.alloc[str](a, width + 1usize)
    if oe != ok { ret (zero, oe) }
    let (seen_names, se) = mem.alloc[str](a, width + 1usize)
    if se != ok { ret (zero, se) }
    let (seen_counts, ce) = mem.alloc[usize](a, width + 1usize)
    if ce != ok { ret (zero, ce) }
    var seen = 0usize
    var i = 0usize
    while i < width {
        var name = ""
        if i < raw.len { name = js_trim(raw[i]) }
        if name.len == 0usize { name = f.join(a, "Column ", f.number_text(a, f64(i + 1usize))) }
        var at = seen
        var k = 0usize
        while k < seen {
            if str.eq(seen_names[k], name) {
                at = k
                break
            }
            k += 1usize
        }
        if at < seen {
            seen_counts[at] += 1usize
            name = f.join(a, f.join(a, name, " "), f.number_text(a, f64(seen_counts[at])))
        } else {
            seen_names[seen] = name
            seen_counts[seen] = 1usize
            seen += 1usize
        }
        out[i] = name
        i += 1usize
    }
    ret (out[0usize..width], ok)
}

fn empty_table() -> Table {
    let none: []const str = zero
    let rows: []const []const str = zero
    let renamed: []const Renamed = zero
    ret Table { headers: none, rows: rows, header_row: 0usize, skipped_rows: 0usize, renamed: renamed }
}

// A sheet as a table. `pin` is the header row (zero-based) or negative to detect it.
fn sheet_to_table(a: *mem.Arena, grid: []const []const Cell, pin: i64) -> (Table, err) {
    var table = empty_table()
    if grid.len == 0usize { ret (table, ok) }
    var header_row = 0usize
    if pin >= 0i64 {
        header_row = usize(pin)
        if header_row > grid.len - 1usize { header_row = grid.len - 1usize }
    } else {
        header_row = detect_header_row(a, grid)
    }
    let head_cells = grid[header_row]
    let (header_text, he) = mem.alloc[str](a, head_cells.len + 1usize)
    if he != ok { ret (table, he) }
    var i = 0usize
    while i < head_cells.len {
        header_text[i] = normalize_cell(a, head_cells[i])
        i += 1usize
    }
    let headers_raw = header_text[0usize..head_cells.len]
    let data = grid[header_row + 1usize..]
    var width = last_filled_text(headers_raw)
    i = 0usize
    while i < data.len {
        let w = last_filled(a, data[i])
        if w > width { width = w }
        i += 1usize
    }
    if width == 0usize {
        table.header_row = header_row
        table.skipped_rows = header_row
        ret (table, ok)
    }
    let (headers, re) = resolve_headers(a, headers_raw, width)
    if re != ok { ret (table, re) }
    var renamed_count = 0usize
    i = 0usize
    while i < width {
        var from = ""
        if i < headers_raw.len { from = headers_raw[i] }
        if !str.eq(headers[i], from) { renamed_count += 1usize }
        i += 1usize
    }
    let (renamed, ne) = mem.alloc[Renamed](a, renamed_count + 1usize)
    if ne != ok { ret (table, ne) }
    var r = 0usize
    i = 0usize
    while i < width {
        var from = ""
        if i < headers_raw.len { from = headers_raw[i] }
        if !str.eq(headers[i], from) {
            renamed[r] = Renamed { index: i, from: from, to: headers[i] }
            r += 1usize
        }
        i += 1usize
    }
    let (rows, oe) = mem.alloc[[]const str](a, data.len + 1usize)
    if oe != ok { ret (table, oe) }
    var rr = 0usize
    while rr < data.len {
        let (values, ve) = mem.alloc[str](a, width)
        if ve != ok { ret (table, ve) }
        var c = 0usize
        while c < width {
            if c < data[rr].len {
                values[c] = normalize_cell(a, data[rr][c])
            } else {
                values[c] = ""
            }
            c += 1usize
        }
        rows[rr] = values
        rr += 1usize
    }
    table.headers = headers
    table.rows = rows[0usize..data.len]
    table.header_row = header_row
    table.skipped_rows = header_row
    table.renamed = renamed[0usize..renamed_count]
    ret (table, ok)
}

// Every sheet of a workbook as its own table; an unnamed sheet is `Sheet N`, a pin applies by the sheet's name.
fn workbook_to_tables(a: *mem.Arena, sheets: []const Sheet, pins: []const Pin) -> ([]Named, err) {
    let (out, oe) = mem.alloc[Named](a, sheets.len + 1usize)
    if oe != ok { ret (zero, oe) }
    var i = 0usize
    while i < sheets.len {
        var name = js_trim(sheets[i].name)
        if name.len == 0usize { name = f.join(a, "Sheet ", f.number_text(a, f64(i + 1usize))) }
        var pin = -1i64
        var k = 0usize
        while k < pins.len {
            if str.eq(pins[k].name, name) {
                pin = pins[k].row
                break
            }
            k += 1usize
        }
        let (table, te) = sheet_to_table(a, sheets[i].grid, pin)
        if te != ok { ret (zero, te) }
        out[i] = Named { name: name, table: table }
        i += 1usize
    }
    ret (out[0usize..sheets.len], ok)
}

// `A1` is column 0, row 0; `$AB$12` is column 27, row 11. False for anything else.
fn parse_cell_ref(ref: str) -> (i64, i64, bool) {
    let s = js_trim(ref)
    var at = 0usize
    if at < s.len && s[at] == 36u8 { at += 1usize }
    var column = 0i64
    var letters = 0usize
    while at < s.len {
        let c = s[at]
        var v = 0i64
        if c >= 65u8 && c <= 90u8 {
            v = i64(c) - 64i64
        } else if c >= 97u8 && c <= 122u8 {
            v = i64(c) - 96i64
        } else {
            break
        }
        column = column * 26i64 + v
        letters += 1usize
        at += 1usize
    }
    if letters == 0usize || letters > 12usize { ret (0i64, 0i64, false) }
    if at < s.len && s[at] == 36u8 { at += 1usize }
    var row = 0i64
    var digits = 0usize
    while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 {
        if digits >= 18usize { ret (0i64, 0i64, false) }
        row = row * 10i64 + i64(s[at] - 48u8)
        digits += 1usize
        at += 1usize
    }
    if digits == 0usize || at != s.len || row == 0i64 { ret (0i64, 0i64, false) }
    ret (column - 1i64, row - 1i64, true)
}

// The formulas a worksheet carries, in cell order.
fn sheet_formulas(a: *mem.Arena, cells: []const FormulaCell) -> ([]Formula, err) {
    let (out, oe) = mem.alloc[Formula](a, cells.len + 1usize)
    if oe != ok { ret (zero, oe) }
    var n = 0usize
    var i = 0usize
    while i < cells.len {
        let c = cells[i]
        if c.reference.len > 0usize && c.reference[0] == 33u8 {
            i += 1usize
            continue
        }
        if !c.has_formula {
            i += 1usize
            continue
        }
        let formula = js_trim(c.formula)
        if formula.len == 0usize {
            i += 1usize
            continue
        }
        let (column, row, good) = parse_cell_ref(c.reference)
        if good {
            out[n] = Formula { reference: c.reference, column: column, row: row, formula: formula }
            n += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// What a workbook offers and which sheet a caller gets: the requested one when it exists, else the first.
fn describe_sheets(a: *mem.Arena, names_in: []const str, requested: str) -> (Description, err) {
    let (names, ne) = mem.alloc[str](a, names_in.len + 1usize)
    if ne != ok { ret (zero, ne) }
    var n = 0usize
    var i = 0usize
    while i < names_in.len {
        if names_in[i].len > 0usize {
            names[n] = names_in[i]
            n += 1usize
        }
        i += 1usize
    }
    var index = 0usize
    if requested.len > 0usize {
        i = 0usize
        while i < n {
            if str.eq(names[i], requested) {
                index = i
                break
            }
            i += 1usize
        }
    }
    let (ignored, ie) = mem.alloc[str](a, n + 1usize)
    if ie != ok { ret (zero, ie) }
    var g = 0usize
    i = 0usize
    while i < n {
        if i != index {
            ignored[g] = names[i]
            g += 1usize
        }
        i += 1usize
    }
    var chosen = ""
    var has = false
    if n > 0usize {
        chosen = names[index]
        has = true
    }
    ret (Description { names: names[0usize..n], chosen: chosen, has_chosen: has, ignored: ignored[0usize..g], needs_choice: n > 1usize }, ok)
}
