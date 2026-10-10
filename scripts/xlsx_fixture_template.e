// `e.fmt.xlsx` and `x.migrate.typemaps` against Appdor's own src/io/xlsx.js and importer maps: scripts/xlsx_vectors.mjs
// writes one JSON line per case (`{"op", ..., "e": answer}`); integers travel as decimal strings. A date cell carries the
// local components the JavaScript Date reported. The fixture computes the same answer and compares canonical JSON.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.fmt.xlsx as xlsx
use e.io
use e.mem
use e.os
use e.str
use x.migrate.typemaps as maps

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn has_text(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret false }
    let (s, is_text) = ir.string_of(x)
    ret is_text
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn int_text(a: *mem.Arena, n: i64) -> str {
    ret f.number_text(a, f64(n))
}

fn number_of(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret 0.0f64
    }
}

fn cell_of(a: *mem.Arena, v: json.Value) -> xlsx.Cell {
    switch v {
    case .Null:
        ret xlsx.empty_cell()
    case .Bool as b:
        ret xlsx.bool_cell(b)
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret xlsx.number_cell(value)
    case .String as s:
        ret xlsx.text_cell(s)
    case .Object:
        let (d, has_d) = ir.get(v, "d")
        if has_d {
            let parts = items(d)
            if parts.len == 0usize { ret xlsx.bad_date_cell() }
            ret xlsx.date_cell(i64(number_of(parts[0])), u32(number_of(parts[1])), u32(number_of(parts[2])), u32(number_of(parts[3])), u32(number_of(parts[4])), u32(number_of(parts[5])))
        }
        let special = text_of(v, "x")
        if str.eq(special, "NaN") { ret xlsx.number_cell(f.nan()) }
        if str.eq(special, "Infinity") { ret xlsx.number_cell(f.nan() - f.nan() + 1.0f64 / 0.0f64) }
        ret xlsx.number_cell(0.0f64 - 1.0f64 / 0.0f64)
    default:
        ret xlsx.empty_cell()
    }
}

fn grid_of(a: *mem.Arena, v: json.Value) -> []const []const xlsx.Cell {
    let rows = items(v)
    let (out, e) = mem.alloc[[]const xlsx.Cell](a, rows.len + 1usize)
    if e != ok { os.exit(82i32) }
    var r = 0usize
    while r < rows.len {
        let cells = items(rows[r])
        let (row, re) = mem.alloc[xlsx.Cell](a, cells.len + 1usize)
        if re != ok { os.exit(83i32) }
        var c = 0usize
        while c < cells.len {
            row[c] = cell_of(a, cells[c])
            c += 1usize
        }
        out[r] = row[0usize..cells.len]
        r += 1usize
    }
    ret out[0usize..rows.len]
}

fn strings_json(a: *mem.Arena, xs: []const str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    if e != ok { os.exit(84i32) }
    var i = 0usize
    while i < xs.len {
        out[i] = sv(xs[i])
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let xs = items(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(85i32) }
    var i = 0usize
    while i < xs.len {
        let (s, is_text) = ir.string_of(xs[i])
        out[i] = s
        i += 1usize
    }
    ret out[0usize..xs.len]
}

// One row in header order; a repeated heading answers its last column, as the JavaScript record does.
fn table_json(a: *mem.Arena, t: xlsx.Table) -> json.Value {
    var o = obj(a)
    put(&o, "headers", strings_json(a, t.headers))
    let (rows, e) = mem.alloc[json.Value](a, t.rows.len + 1usize)
    if e != ok { os.exit(86i32) }
    var r = 0usize
    while r < t.rows.len {
        let (cells, ce) = mem.alloc[str](a, t.headers.len + 1usize)
        if ce != ok { os.exit(87i32) }
        var c = 0usize
        while c < t.headers.len {
            var last = c
            var k = c + 1usize
            while k < t.headers.len {
                if str.eq(t.headers[k], t.headers[c]) { last = k }
                k += 1usize
            }
            cells[c] = t.rows[r][last]
            c += 1usize
        }
        rows[r] = strings_json(a, cells[0usize..t.headers.len])
        r += 1usize
    }
    put(&o, "rows", json.Value{ Array: rows[0usize..t.rows.len] })
    put(&o, "headerRow", sv(int_text(a, i64(t.header_row))))
    put(&o, "skippedRows", sv(int_text(a, i64(t.skipped_rows))))
    let (ren, re) = mem.alloc[json.Value](a, t.renamed.len + 1usize)
    if re != ok { os.exit(88i32) }
    var i = 0usize
    while i < t.renamed.len {
        var r2 = obj(a)
        put(&r2, "index", sv(int_text(a, i64(t.renamed[i].index))))
        put(&r2, "from", sv(t.renamed[i].from))
        put(&r2, "to", sv(t.renamed[i].to))
        ren[i] = ir.obj_value(&r2)
        i += 1usize
    }
    put(&o, "renamed", json.Value{ Array: ren[0usize..t.renamed.len] })
    ret ir.obj_value(&o)
}

fn answer(a: *mem.Arena, c: json.Value) -> json.Value {
    let op = text_of(c, "op")
    if str.eq(op, "sheet") {
        var pin = -1i64
        let (p, has_pin) = ir.get(c, "pin")
        if has_pin { pin = i64(number_of(p)) }
        let (t, e) = xlsx.sheet_to_table(a, grid_of(a, ir.value_of(c, "aoa")), pin)
        if e != ok { os.exit(89i32) }
        ret table_json(a, t)
    }
    if str.eq(op, "detect") {
        ret sv(int_text(a, i64(xlsx.detect_header_row(a, grid_of(a, ir.value_of(c, "aoa"))))))
    }
    if str.eq(op, "workbook") {
        let sheets = items(ir.value_of(c, "sheets"))
        let (list, le) = mem.alloc[xlsx.Sheet](a, sheets.len + 1usize)
        if le != ok { os.exit(90i32) }
        var i = 0usize
        while i < sheets.len {
            list[i] = xlsx.Sheet { name: text_of(sheets[i], "name"), grid: grid_of(a, ir.value_of(sheets[i], "aoa")) }
            i += 1usize
        }
        let raw = items(ir.value_of(c, "pins"))
        let (pins, pe) = mem.alloc[xlsx.Pin](a, raw.len + 1usize)
        if pe != ok { os.exit(91i32) }
        i = 0usize
        while i < raw.len {
            pins[i] = xlsx.Pin { name: text_of(raw[i], "name"), row: i64(number_of(ir.value_of(raw[i], "row"))) }
            i += 1usize
        }
        let (named, ne) = xlsx.workbook_to_tables(a, list[0usize..sheets.len], pins[0usize..raw.len])
        if ne != ok { os.exit(92i32) }
        let (out, oe) = mem.alloc[json.Value](a, named.len + 1usize)
        if oe != ok { os.exit(93i32) }
        i = 0usize
        while i < named.len {
            let t = table_json(a, named[i].table)
            var o = obj(a)
            put(&o, "name", sv(named[i].name))
            switch t {
            case .Object as members:
                var k = 0usize
                while k < members.len {
                    put(&o, members[k].key, members[k].value)
                    k += 1usize
                }
            default:
                let skip = 0usize
            }
            out[i] = ir.obj_value(&o)
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..named.len] }
    }
    if str.eq(op, "ref") {
        let (column, row, good) = xlsx.parse_cell_ref(text_of(c, "ref"))
        if !good { ret .Null }
        var o = obj(a)
        put(&o, "column", sv(int_text(a, column)))
        put(&o, "row", sv(int_text(a, row)))
        ret ir.obj_value(&o)
    }
    if str.eq(op, "formulas") {
        let raw = items(ir.value_of(c, "cells"))
        let (cells, ce) = mem.alloc[xlsx.FormulaCell](a, raw.len + 1usize)
        if ce != ok { os.exit(94i32) }
        var i = 0usize
        while i < raw.len {
            let (hv, has_flag) = ir.get(raw[i], "has")
            var has = false
            switch hv {
            case .Bool as b:
                has = b
            default:
                let skip = 0usize
            }
            cells[i] = xlsx.FormulaCell { reference: text_of(raw[i], "ref"), has_formula: has, formula: text_of(raw[i], "f") }
            i += 1usize
        }
        let (found, fe) = xlsx.sheet_formulas(a, cells[0usize..raw.len])
        if fe != ok { os.exit(95i32) }
        let (out, oe) = mem.alloc[json.Value](a, found.len + 1usize)
        if oe != ok { os.exit(96i32) }
        i = 0usize
        while i < found.len {
            var o = obj(a)
            put(&o, "ref", sv(found[i].reference))
            put(&o, "column", sv(int_text(a, found[i].column)))
            put(&o, "row", sv(int_text(a, found[i].row)))
            put(&o, "formula", sv(found[i].formula))
            out[i] = ir.obj_value(&o)
            i += 1usize
        }
        ret json.Value{ Array: out[0usize..found.len] }
    }
    if str.eq(op, "describe") {
        let (d, de) = xlsx.describe_sheets(a, strings_of(a, ir.value_of(c, "names")), text_of(c, "requested"))
        if de != ok { os.exit(97i32) }
        var o = obj(a)
        put(&o, "names", strings_json(a, d.names))
        if d.has_chosen {
            put(&o, "chosen", sv(d.chosen))
        } else {
            put(&o, "chosen", .Null)
        }
        put(&o, "ignored", strings_json(a, d.ignored))
        put(&o, "needsChoice", json.Value{ Bool: d.needs_choice })
        ret ir.obj_value(&o)
    }
    // map
    let which = text_of(c, "map")
    let key = text_of(c, "key")
    if str.eq(which, "airtable_view_type") { ret sv(maps.airtable_view_type(key)) }
    if str.eq(which, "monday_view_type") { ret sv(maps.monday_view_type(key)) }
    var value = ""
    var found = false
    if str.eq(which, "monday_type") {
        let (v, g) = maps.monday_type(key)
        value = v
        found = g
    } else if str.eq(which, "airtable_type") {
        let (v, g) = maps.airtable_type(key)
        value = v
        found = g
    } else {
        let (v, g) = maps.quickbase_type(key)
        value = v
        found = g
    }
    if !found { ret .Null }
    ret sv(value)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let (got, ge) = chain.canonical_json(a, answer(a, c))
    let (want, we) = chain.canonical_json(a, ir.value_of(c, "e"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got, want) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", got), f.join(a, "\nWANT ", want)))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("fmt xlsx ok")
    ret ok
}
