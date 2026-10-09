// Record paging, row windows and the published limits (L033), after appdor's `src/grid-ops/records-engine.js`,
// `src/grid/virtual-rows.js` and `src/performance/limits.js`: human-readable record keys minted from a per-table
// counter that only moves forward (`INV-1042`), keyset (cursor) pagination that is O(page) at any depth with an
// opaque base64 cursor over the sort position and an id tie-break, table duplication that rewrites a table's own
// links to point at the copy, the arithmetic of a windowed row list (top and bottom spacers, the ARIA row count),
// the row caps and latency budgets the product claims, and nearest-rank percentiles.
//
// Rows are named `e.algo.formula` values read as JavaScript reads JSON; a missing field is `undefined` and compares
// less than any present one.
//
// Differences from appdor's: an object-valued field is opaque (its keys are not read), so a cursor over such a field
// carries `{}`; number formatting for the truncation notice knows `en` (the default) and `bg`.

use e.algo.formula as f
use e.algo.formula.text as tx
use e.algo.view as view
use e.fmt.json as json
use e.math
use e.mem
use e.str
use e.text.utf8 as utf8

// --- record keys -----------------------------------------------------------------------------------------------

// Per-table counters that only move forward, so a deleted record's key is never reused.
type Counter = struct { table: str, value: f64 }

type KeyMinter = struct { counters: []Counter, count: usize }

fn new_minter(a: *mem.Arena, capacity: usize) -> KeyMinter {
    var none: []Counter = zero
    let (cells, e) = mem.alloc[Counter](a, capacity + 1usize)
    if e != ok { ret KeyMinter { counters: none, count: 0usize } }
    ret KeyMinter { counters: cells, count: 0usize }
}

fn counter_of(m: *KeyMinter, table: str) -> f64 {
    var i = 0usize
    while i < m.count {
        if str.eq(m.counters[i].table, table) { ret m.counters[i].value }
        i += 1usize
    }
    ret 0.0f64
}

fn set_counter(m: *KeyMinter, table: str, value: f64) {
    var i = 0usize
    while i < m.count {
        if str.eq(m.counters[i].table, table) {
            m.counters[i].value = value
            ret
        }
        i += 1usize
    }
    if m.count < m.counters.len {
        m.counters[m.count] = Counter { table: table, value: value }
        m.count += 1usize
    }
}

// The next key of a table: `PREFIX-n`, n one past the counter.
fn mint(a: *mem.Arena, m: *KeyMinter, table: str, prefix: str) -> str {
    let next = counter_of(m, table) + 1.0f64
    set_counter(m, table, next)
    ret f.join3(a, prefix, "-", f.number_text(a, next))
}

// Adopting imported keys: a later mint must not collide with them.
fn reserve(m: *KeyMinter, table: str, through: f64) {
    var current = counter_of(m, table)
    if through > current { current = through }
    set_counter(m, table, current)
}

// A key prefix from a table name: "Sales Invoices" is "SI", a single word its first three letters, nothing `REC`.
fn prefix_for(a: *mem.Arena, name: str) -> str {
    let words = split_words(a, name)
    if words.len == 0usize { ret "REC" }
    if words.len == 1usize {
        let units = first_units(a, words[0usize], 3usize)
        ret tx.upper_text(a, units)
    }
    var out = ""
    var i = 0usize
    while i < words.len {
        out = f.join(a, out, first_units(a, words[i], 1usize))
        i += 1usize
    }
    ret tx.upper_text(a, first_units(a, out, 4usize))
}

// The text split on runs of white space, empties dropped.
fn split_words(a: *mem.Arena, s: str) -> []const str {
    var none: []const str = zero
    let (out, e) = mem.alloc[str](a, s.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var start = 0usize
    var in_word = false
    var it = utf8.iterator(s)
    var at = 0usize
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            var width = 1usize
            if scalar >= 65536u32 { width = 4usize } else if scalar >= 2048u32 { width = 3usize } else if scalar >= 128u32 { width = 2usize }
            if view.js_space(scalar) {
                if in_word {
                    out[n] = s[start..at]
                    n += 1usize
                    in_word = false
                }
            } else if !in_word {
                in_word = true
                start = at
            }
            at += width
        }
    }
    if in_word {
        out[n] = s[start..s.len]
        n += 1usize
    }
    ret out[0usize..n]
}

// The first `n` UTF-16 units of a text (an astral character counts two; half of one reads as U+FFFD).
fn first_units(a: *mem.Arena, s: str, n: usize) -> str {
    var units = 0usize
    var end = 0usize
    var it = utf8.iterator(s)
    var at = 0usize
    var more = true
    while more && units < n {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            var width = 1usize
            var cost = 1usize
            if scalar >= 65536u32 {
                width = 4usize
                cost = 2usize
            } else if scalar >= 2048u32 {
                width = 3usize
            } else if scalar >= 128u32 {
                width = 2usize
            }
            if units + cost > n {
                // only the first half of a surrogate pair fits
                ret f.join(a, s[0usize..end], "\xef\xbf\xbd")
            }
            units += cost
            at += width
            end = at
        }
    }
    ret s[0usize..end]
}

// `PREFIX-n`: the prefix (2 to 6 capital letters) and the number, or false.
fn parse_record_key(s: str) -> (str, f64, bool) {
    var dash = s.len
    var i = 0usize
    while i < s.len {
        if s[i] == 45u8 {
            dash = i
            i = s.len
        } else {
            i += 1usize
        }
    }
    if dash < 2usize || dash > 6usize || dash + 1usize >= s.len { ret ("", 0.0f64, false) }
    i = 0usize
    while i < dash {
        if s[i] < 65u8 || s[i] > 90u8 { ret ("", 0.0f64, false) }
        i += 1usize
    }
    i = dash + 1usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret ("", 0.0f64, false) }
        i += 1usize
    }
    let (n, parse_error) = str.parse_f64(s[dash + 1usize..s.len])
    if parse_error != ok { ret ("", 0.0f64, false) }
    ret (s[0usize..dash], n, true)
}

// --- keyset pagination ------------------------------------------------------------------------------------------

type Row = struct { fields: []const f.Field }

type SortKey = struct { field: str, descending: bool }

// A cell: its value and whether the record has the field at all (a missing field is `undefined`, not `null`).
type Cell = struct { value: f.Value, present: bool }

fn cell_at(fields: []const f.Field, name: str) -> Cell {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) { ret Cell { value: fields[i].value, present: true } }
        i += 1usize
    }
    ret Cell { value: f.blank(), present: false }
}

// `x == null`: undefined or null.
fn is_nullish(c: Cell) -> bool { ret !c.present || c.value.kind == .Blank }

// `x === y`.
fn strict_equal(x: Cell, y: Cell) -> bool {
    if !x.present || !y.present { ret !x.present && !y.present }
    if x.value.kind == .Array || x.value.kind == .Record || y.value.kind == .Array || y.value.kind == .Record { ret false }
    if x.value.kind != y.value.kind { ret false }
    if x.value.kind == .Number { ret x.value.n == y.value.n }
    ret view.same_value(x.value, y.value)
}

// JavaScript's `x < y` over JSON values: two texts by code units, else by number (a missing field is NaN).
fn js_less(a: *mem.Arena, x: Cell, y: Cell) -> bool {
    var left_text = false
    var right_text = false
    var left = ""
    var right = ""
    if x.present && (x.value.kind == .Text || x.value.kind == .Array || x.value.kind == .Record) {
        left_text = true
        left = view.js_string(a, x.value)
    }
    if y.present && (y.value.kind == .Text || y.value.kind == .Array || y.value.kind == .Record) {
        right_text = true
        right = view.js_string(a, y.value)
    }
    if left_text && right_text { ret f.compare_utf16(left, right) < 0i32 }
    var nx = f.nan()
    var ny = f.nan()
    if x.present {
        if left_text { nx = text_number(a, left) } else { nx = view.js_number(a, x.value) }
    }
    if y.present {
        if right_text { ny = text_number(a, right) } else { ny = view.js_number(a, y.value) }
    }
    ret nx < ny
}

fn text_number(a: *mem.Arena, s: str) -> f64 { ret view.js_number(a, f.text(s)) }

// The order of two records by the sort keys: -1, 0 or 1.
fn compare_by(a: *mem.Arena, order: []const SortKey, x: []const f.Field, y: []const f.Field) -> i32 {
    var i = 0usize
    while i < order.len {
        let s = order[i]
        i += 1usize
        let av = cell_at(x, s.field)
        let bv = cell_at(y, s.field)
        if strict_equal(av, bv) { continue }
        var less = false
        if is_nullish(av) {
            less = true
        } else if is_nullish(bv) {
            less = false
        } else {
            less = js_less(a, av, bv)
        }
        var sign = 1i32
        if less { sign = -1i32 }
        if s.descending { sign = 0i32 - sign }
        ret sign
    }
    ret 0i32
}

// --- the cursor ------------------------------------------------------------------------------------------------

fn b64_index(b: u8) -> u32 {
    if b >= 65u8 && b <= 90u8 { ret u32(b) - 65u32 }
    if b >= 97u8 && b <= 122u8 { ret u32(b) - 71u32 }
    if b >= 48u8 && b <= 57u8 { ret u32(b) + 4u32 }
    if b == 43u8 { ret 62u32 }
    if b == 47u8 { ret 63u32 }
    ret 4294967295u32
}

// appdor's lenient base64 reader for a cursor: characters outside the alphabet are dropped and a short group yields
// what it can; the bytes are taken as UTF-8 (a malformed cursor fails the JSON parse after).
fn decode_cursor_text(a: *mem.Arena, s: str) -> str {
    let none = 4294967295u32
    let (clean, ce) = mem.alloc[u8](a, s.len + 1usize)
    let (out, oe) = mem.alloc[u8](a, s.len + 4usize)
    if ce != ok || oe != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if b64_index(s[i]) != none {
            clean[n] = s[i]
            n += 1usize
        }
        i += 1usize
    }
    var w = 0usize
    i = 0usize
    while i < n {
        let n0 = b64_index(clean[i])
        var n1 = none
        var n2 = none
        var n3 = none
        if i + 1usize < n { n1 = b64_index(clean[i + 1usize]) }
        if i + 2usize < n { n2 = b64_index(clean[i + 2usize]) }
        if i + 3usize < n { n3 = b64_index(clean[i + 3usize]) }
        if n1 == none {
            out[w] = 255u8
        } else {
            out[w] = u8(((n0 << 2u32) | (n1 >> 4u32)) & 255u32)
        }
        w += 1usize
        if n2 != none {
            out[w] = u8((((n1 & 15u32) << 4u32) | (n2 >> 2u32)) & 255u32)
            w += 1usize
        }
        if n3 != none {
            out[w] = u8((((n2 & 3u32) << 6u32) | n3) & 255u32)
            w += 1usize
        }
        i += 4usize
    }
    ret out[0usize..w]
}

fn base64_standard(a: *mem.Arena, s: str) -> str {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    let (out, e) = mem.alloc[u8](a, (s.len + 2usize) / 3usize * 4usize + 1usize)
    if e != ok { ret "" }
    var w = 0usize
    var i = 0usize
    while i < s.len {
        let b0 = u32(s[i])
        var b1 = 0u32
        var b2 = 0u32
        var have1 = false
        var have2 = false
        if i + 1usize < s.len {
            b1 = u32(s[i + 1usize])
            have1 = true
        }
        if i + 2usize < s.len {
            b2 = u32(s[i + 2usize])
            have2 = true
        }
        out[w] = alphabet[usize(b0 >> 2u32)]
        out[w + 1usize] = alphabet[usize(((b0 & 3u32) << 4u32) | (b1 >> 4u32))]
        if have1 { out[w + 2usize] = alphabet[usize(((b1 & 15u32) << 2u32) | (b2 >> 6u32))] } else { out[w + 2usize] = 61u8 }
        if have2 { out[w + 3usize] = alphabet[usize(b2 & 63u32)] } else { out[w + 3usize] = 61u8 }
        w += 4usize
        i += 3usize
    }
    ret out[0usize..w]
}

// A cursor: the base64 of `JSON.stringify` of the last row's sort fields (an undefined one omitted).
fn encode_cursor(a: *mem.Arena, order: []const SortKey, last: []const f.Field) -> str {
    var text = "{"
    var wrote = 0usize
    var i = 0usize
    while i < order.len {
        // a repeated field is one key
        var seen = false
        var k = 0usize
        while k < i {
            if str.eq(order[k].field, order[i].field) { seen = true }
            k += 1usize
        }
        if !seen {
            let c = cell_at(last, order[i].field)
            if c.present {
                if wrote > 0usize { text = f.join(a, text, ",") }
                text = f.join(a, text, f.join3(a, view.json_key(a, f.text(order[i].field)), ":", view.json_key(a, c.value)))
                wrote += 1usize
            }
        }
        i += 1usize
    }
    ret base64_standard(a, f.join(a, text, "}"))
}

// The sort position a cursor names: its fields, and false for a cursor that is not valid JSON or is a falsy value.
fn decode_cursor(a: *mem.Arena, cursor: str) -> ([]const f.Field, bool) {
    var none: []const f.Field = zero
    let text = decode_cursor_text(a, cursor)
    let (root, e) = json.parse(a, text, json.Options { allow_duplicate_keys: true, max_depth: 64u16 })
    if e != ok { ret (none, false) }
    switch root {
    case .Null:
        ret (none, false)
    case .Bool as b:
        if !b { ret (none, false) }
        ret (none, true)
    case .Number as n:
        let (value, ne) = json.number_f64(n)
        if value == 0.0f64 || value != value { ret (none, false) }
        ret (none, true)
    case .String as s:
        if s.len == 0usize { ret (none, false) }
        ret (none, true)
    case .Array as items:
        ret (none, true)
    case .Object as members:
        let (out, oe) = mem.alloc[f.Field](a, members.len + 1usize)
        if oe != ok { ret (none, false) }
        var n = 0usize
        var i = 0usize
        while i < members.len {
            out[n] = f.Field { name: members[i].key, value: json_value(a, members[i].value) }
            // a duplicate key keeps its first place and takes the last value
            var k = 0usize
            var dup = false
            while k < n {
                if str.eq(out[k].name, members[i].key) {
                    out[k].value = out[n].value
                    dup = true
                }
                k += 1usize
            }
            if !dup { n += 1usize }
            i += 1usize
        }
        ret (out[0usize..n], true)
    default:
        ret (none, false)
    }
}

fn json_value(a: *mem.Arena, x: json.Value) -> f.Value {
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret f.number(value)
    case .String as s:
        ret f.text(s)
    case .Bool as b:
        ret f.boolean(b)
    case .Array as items:
        if items.len == 0usize { ret f.array(f.zero_items()) }
        let (out, e) = mem.alloc[f.Value](a, items.len)
        if e != ok { ret f.blank() }
        var i = 0usize
        while i < items.len {
            out[i] = json_value(a, items[i])
            i += 1usize
        }
        ret f.array(out)
    case .Object as members:
        ret f.record(f.zero_items())
    default:
        ret f.blank()
    }
}

// A page: the positions (in the input) of its records, in order, the cursor after it, and whether more follow.
type Page = struct { valid: bool, reason: str, positions: []const usize, next_cursor: str, has_next_cursor: bool, has_more: bool }

// Keyset pagination over already-filtered records: a page is everything strictly after the cursor position in
// this sort order. The sort always ends with the id, so a page can neither skip nor repeat a row.
fn paginate(a: *mem.Arena, rows: []const Row, sort: []const SortKey, limit: f64, cursor: str, has_cursor: bool) -> Page {
    var none: []const usize = zero
    let (order, oe) = mem.alloc[SortKey](a, sort.len + 1usize)
    if oe != ok { ret Page { valid: false, reason: "out-of-memory", positions: none, next_cursor: "", has_next_cursor: false, has_more: false } }
    var on = 0usize
    var i = 0usize
    while i < sort.len {
        if !str.eq(sort[i].field, "id") {
            order[on] = sort[i]
            on += 1usize
        }
        i += 1usize
    }
    order[on] = SortKey { field: "id", descending: false }
    on += 1usize
    let keys = order[0usize..on]
    // a stable sort of the positions
    let (sorted, se) = mem.alloc[usize](a, rows.len + 1usize)
    let (tmp, te) = mem.alloc[usize](a, rows.len + 1usize)
    if se != ok || te != ok { ret Page { valid: false, reason: "out-of-memory", positions: none, next_cursor: "", has_next_cursor: false, has_more: false } }
    i = 0usize
    while i < rows.len {
        sorted[i] = i
        i += 1usize
    }
    if rows.len < 64usize {
        sort_small(a, rows, keys, sorted[0usize..rows.len])
    } else {
        merge_positions(a, rows, keys, sorted, tmp, 0usize, rows.len)
    }
    var start = 0usize
    if has_cursor && cursor.len > 0usize {
        let (pos, good) = decode_cursor(a, cursor)
        if !good { ret Page { valid: false, reason: "invalid-cursor", positions: none, next_cursor: "", has_next_cursor: false, has_more: false } }
        start = rows.len
        var k = 0usize
        var found = false
        while k < rows.len && !found {
            if compare_by(a, keys, rows[sorted[k]].fields, pos) > 0i32 {
                start = k
                found = true
            }
            k += 1usize
        }
    }
    // slice(start, start + limit): a negative end counts from the end
    var end_f = f64(start) + limit
    if end_f != end_f { end_f = 0.0f64 }
    var end = rows.len
    if end_f < 0.0f64 {
        let from_end = f64(rows.len) + end_f
        if from_end < 0.0f64 { end = 0usize } else { end = usize(from_end) }
    } else if end_f < f64(rows.len) {
        end = usize(end_f)
    }
    var page_len = 0usize
    if end > start { page_len = end - start }
    let (page, pe) = mem.alloc[usize](a, page_len + 1usize)
    if pe != ok { ret Page { valid: false, reason: "out-of-memory", positions: none, next_cursor: "", has_next_cursor: false, has_more: false } }
    i = 0usize
    while i < page_len {
        page[i] = sorted[start + i]
        i += 1usize
    }
    let has_more = f64(start) + limit < f64(rows.len)
    var next = ""
    var has_next = false
    if has_more && page_len > 0usize {
        next = encode_cursor(a, keys, rows[page[page_len - 1usize]].fields)
        has_next = true
    }
    ret Page { valid: true, reason: "", positions: page[0usize..page_len], next_cursor: next, has_next_cursor: has_next, has_more: has_more }
}

// V8's order for fewer than 64 items: the leading run (reversed when strictly descending), then binary insertion.
// A comparison across mixed types is not transitive, and this is the order JavaScript's own sort gives it.
fn sort_small(a: *mem.Arena, rows: []const Row, keys: []const SortKey, order: []usize) {
    let n = order.len
    if n < 2usize { ret }
    var run = 2usize
    let descending = compare_by(a, keys, rows[order[1usize]].fields, rows[order[0usize]].fields) < 0i32
    var previous = order[1usize]
    var idx = 2usize
    var stop = false
    while idx < n && !stop {
        let current = order[idx]
        let r = compare_by(a, keys, rows[current].fields, rows[previous].fields)
        if descending {
            if r >= 0i32 { stop = true }
        } else {
            if r < 0i32 { stop = true }
        }
        if !stop {
            previous = current
            run += 1usize
            idx += 1usize
        }
    }
    if descending {
        var lo = 0usize
        var hi = run - 1usize
        while lo < hi {
            let t = order[lo]
            order[lo] = order[hi]
            order[hi] = t
            lo += 1usize
            hi -= 1usize
        }
    }
    var start = run
    while start < n {
        var left = 0usize
        var right = start
        let pivot = order[start]
        while left < right {
            let mid = left + ((right - left) >> 1usize)
            if compare_by(a, keys, rows[pivot].fields, rows[order[mid]].fields) < 0i32 {
                right = mid
            } else {
                left = mid + 1usize
            }
        }
        var q = start
        while q > left {
            order[q] = order[q - 1usize]
            q -= 1usize
        }
        order[left] = pivot
        start += 1usize
    }
}

fn merge_positions(a: *mem.Arena, rows: []const Row, keys: []const SortKey, order: []usize, tmp: []usize, lo: usize, hi: usize) {
    if hi - lo < 2usize { ret }
    let mid = lo + (hi - lo) / 2usize
    merge_positions(a, rows, keys, order, tmp, lo, mid)
    merge_positions(a, rows, keys, order, tmp, mid, hi)
    var i = lo
    var j = mid
    var k = lo
    while i < mid && j < hi {
        if compare_by(a, keys, rows[order[j]].fields, rows[order[i]].fields) < 0i32 {
            tmp[k] = order[j]
            j += 1usize
        } else {
            tmp[k] = order[i]
            i += 1usize
        }
        k += 1usize
    }
    while i < mid {
        tmp[k] = order[i]
        i += 1usize
        k += 1usize
    }
    while j < hi {
        tmp[k] = order[j]
        j += 1usize
        k += 1usize
    }
    k = lo
    while k < hi {
        order[k] = tmp[k]
        k += 1usize
    }
}

// --- table duplication --------------------------------------------------------------------------------------------

// A column: its id (empty when it has none), name, type and, for a link, the table it links to.
type Column = struct { id: str, name: str, type_name: str, linked_table: str, has_linked_table: bool }

type Table = struct { id: str, name: str, columns: []const Column }

type Duplicate = struct { table: Table, rows: []const Row, id_from: []const str, id_to: []const str }

// Duplicate a table: schema only, or with its records and every link to the table itself rewritten to the copy
// (an id the copy does not hold is dropped). New ids are `<table>_copy`, `<column>_copy` and `<copy>_r<n>`.
fn duplicate_table(a: *mem.Arena, table: Table, rows: []const Row, with_records: bool, new_id: str, new_name: str, minter: *KeyMinter, has_minter: bool) -> Duplicate {
    var none_rows: []const Row = zero
    var none_ids: []const str = zero
    var copy_id = new_id
    if copy_id.len == 0usize { copy_id = f.join(a, table.id, "_copy") }
    var copy_name = new_name
    if copy_name.len == 0usize { copy_name = f.join(a, table.name, " copy") }
    let (columns, ce) = mem.alloc[Column](a, table.columns.len + 1usize)
    if ce != ok { ret Duplicate { table: Table { id: copy_id, name: copy_name, columns: table.columns }, rows: none_rows, id_from: none_ids, id_to: none_ids } }
    var i = 0usize
    while i < table.columns.len {
        var c = table.columns[i]
        if c.id.len > 0usize { c.id = f.join(a, c.id, "_copy") }
        columns[i] = c
        i += 1usize
    }
    if !with_records {
        ret Duplicate { table: Table { id: copy_id, name: copy_name, columns: columns[0usize..table.columns.len] }, rows: none_rows, id_from: none_ids, id_to: none_ids }
    }
    let (from_ids, fe) = mem.alloc[str](a, rows.len + 1usize)
    let (to_ids, te) = mem.alloc[str](a, rows.len + 1usize)
    let (copies, re) = mem.alloc[Row](a, rows.len + 1usize)
    if fe != ok || te != ok || re != ok { ret Duplicate { table: Table { id: copy_id, name: copy_name, columns: columns[0usize..table.columns.len] }, rows: none_rows, id_from: none_ids, id_to: none_ids } }
    i = 0usize
    while i < rows.len {
        let new_record = f.join(a, f.join(a, copy_id, "_r"), f.number_text(a, f64(i + 1usize)))
        let old = cell_at(rows[i].fields, "id")
        var key = "undefined"
        if old.present { key = view.js_string(a, old.value) }
        from_ids[i] = key
        to_ids[i] = new_record
        i += 1usize
    }
    // the links that point at the original table
    i = 0usize
    while i < rows.len {
        let (cells, ce2) = mem.alloc[f.Field](a, rows[i].fields.len + 2usize)
        if ce2 != ok { ret Duplicate { table: Table { id: copy_id, name: copy_name, columns: columns[0usize..table.columns.len] }, rows: none_rows, id_from: none_ids, id_to: none_ids } }
        var n = 0usize
        var k = 0usize
        var has_id = false
        while k < rows[i].fields.len {
            var field = rows[i].fields[k]
            if str.eq(field.name, "id") {
                field.value = f.text(to_ids[i])
                has_id = true
            }
            var is_self_link = false
            var c = 0usize
            while c < table.columns.len {
                if str.eq(table.columns[c].type_name, "link") && table.columns[c].has_linked_table && str.eq(table.columns[c].linked_table, table.id) && str.eq(table.columns[c].name, field.name) { is_self_link = true }
                c += 1usize
            }
            if is_self_link && field.value.kind != .Blank {
                field.value = rewrite_link(a, field.value, from_ids[0usize..rows.len], to_ids[0usize..rows.len])
            }
            cells[n] = field
            n += 1usize
            k += 1usize
        }
        if !has_id {
            cells[n] = f.Field { name: "id", value: f.text(to_ids[i]) }
            n += 1usize
        }
        copies[i] = Row { fields: cells[0usize..n] }
        i += 1usize
    }
    // the copy's self-links point at the copy
    var c2 = 0usize
    while c2 < table.columns.len {
        if str.eq(columns[c2].type_name, "link") && columns[c2].has_linked_table && str.eq(columns[c2].linked_table, table.id) { columns[c2].linked_table = copy_id }
        c2 += 1usize
    }
    if has_minter { reserve(minter, copy_id, f64(rows.len)) }
    ret Duplicate { table: Table { id: copy_id, name: copy_name, columns: columns[0usize..table.columns.len] }, rows: copies[0usize..rows.len], id_from: from_ids[0usize..rows.len], id_to: to_ids[0usize..rows.len] }
}

// Rewrite a link value: each id through the id map (unknown ids dropped); a single id stays single (null if lost).
fn rewrite_link(a: *mem.Arena, v: f.Value, from: []const str, to: []const str) -> f.Value {
    var items: []const f.Value = zero
    var single: [1]f.Value = zero
    var is_array = false
    if v.kind == .Array {
        items = v.items
        is_array = true
    } else {
        single[0usize] = v
        items = single[0..]
    }
    let (out, e) = mem.alloc[f.Value](a, items.len + 1usize)
    if e != ok { ret v }
    var n = 0usize
    var i = 0usize
    while i < items.len {
        let key = view.js_string(a, items[i])
        var k = from.len
        var found = false
        var m = 0usize
        // the last record holding an id wins, as a later assignment does
        while m < from.len {
            if str.eq(from[m], key) {
                k = m
                found = true
            }
            m += 1usize
        }
        if found && to[k].len > 0usize {
            out[n] = f.text(to[k])
            n += 1usize
        }
        i += 1usize
    }
    if is_array {
        if n == 0usize { ret f.array(f.zero_items()) }
        ret f.array(out[0usize..n])
    }
    if n == 0usize { ret f.blank() }
    ret out[0usize]
}

// --- windowed rows --------------------------------------------------------------------------------------------

fn default_row_height() -> f64 { ret 33.0f64 }

// What a windowed `<tbody>` needs: the rows to draw, the spacer above and below, and the true ARIA row count.
type RowPlan = struct { start: f64, end: f64, top_spacer: f64, bottom_spacer: f64, aria_row_count: f64 }

// `planRows`: `row_height` 0 means the default, `overscan` negative means the default of 3.
fn plan_rows(total: f64, scroll_top: f64, viewport_height: f64, row_height: f64, overscan: f64) -> RowPlan {
    var height = row_height
    if height == 0.0f64 || height != height { height = default_row_height() }
    var over = overscan
    if over < 0.0f64 || over != over { over = 3.0f64 }
    var t = total
    if t != t { t = 0.0f64 }
    var top = scroll_top
    if top != top { top = 0.0f64 }
    var vh = viewport_height
    if vh != vh { vh = 0.0f64 }
    let first = math.floor[f64](top / height)
    var start = first - over
    if start < 0.0f64 { start = 0.0f64 }
    let visible = math.ceil[f64](vh / height) + over * 2.0f64
    var end = start + visible
    if end > t { end = t }
    let offset = start * height
    let total_height = t * height
    var rendered = end - start
    if rendered < 0.0f64 { rendered = 0.0f64 }
    var bottom = total_height - offset - rendered * height
    if bottom < 0.0f64 { bottom = 0.0f64 }
    ret RowPlan { start: start, end: end, top_spacer: offset, bottom_spacer: bottom, aria_row_count: t }
}

// --- published limits -------------------------------------------------------------------------------------------

fn row_page_size() -> f64 { ret 1000.0f64 }

// The most rows the grid loads for one table.
fn grid_row_cap() -> f64 { ret 100000.0f64 }

fn alt_view_row_cap() -> f64 { ret 500.0f64 }

fn kanban_max_lanes() -> f64 { ret 30.0f64 }

fn kanban_cards_per_lane() -> f64 { ret 50.0f64 }

fn gallery_max_groups() -> f64 { ret 30.0f64 }

fn gallery_cards_per_group() -> f64 { ret 50.0f64 }

fn pivot_max_rows() -> f64 { ret 200.0f64 }

fn pivot_max_columns() -> f64 { ret 30.0f64 }

fn calendar_chips_per_day() -> f64 { ret 20.0f64 }

fn timeline_max_bars() -> f64 { ret 300.0f64 }

fn workload_max_assignees() -> f64 { ret 50.0f64 }

fn map_max_markers() -> f64 { ret 500.0f64 }

// The form submission burst a single form must absorb, per second.
fn form_submission_burst_per_second() -> f64 { ret 50.0f64 }

// An integer in a locale's digit grouping: `en` groups with `,`, `bg` with a no-break space from five digits up.
fn format_integer(a: *mem.Arena, n: f64, locale: str) -> str {
    let digits = f.number_text(a, n)
    var negative = false
    var body = digits
    if body.len > 0usize && body[0usize] == 45u8 {
        negative = true
        body = body[1usize..body.len]
    }
    var bulgarian = false
    let l = f.lower_text(a, js_trim_locale(locale))
    if str.eq(l, "bg") || str.starts_with(l, "bg-") { bulgarian = true }
    var separator = ","
    if bulgarian { separator = "\xc2\xa0" }
    // Bulgarian does not group a four-digit number
    if (bulgarian && body.len < 5usize) || body.len <= 3usize {
        if negative { ret f.join(a, "-", body) }
        ret body
    }
    var out = ""
    var i = 0usize
    while i < body.len {
        if i > 0usize && (body.len - i) % 3usize == 0usize { out = f.join(a, out, separator) }
        out = f.join(a, out, body[i..i + 1usize])
        i += 1usize
    }
    if negative { ret f.join(a, "-", out) }
    ret out
}

fn js_trim_locale(s: str) -> str { ret view.js_trim(s) }

type LoadPlan = struct { loaded: f64, truncated: bool, requests: f64, notice: str, has_notice: bool }

// Whether a table of `n` rows loads completely or is cut with a notice naming both numbers.
fn load_plan(a: *mem.Arena, n: f64, locale: str) -> LoadPlan {
    var total = n
    if total != total || total < 0.0f64 { total = 0.0f64 }
    var loaded = total
    if loaded > grid_row_cap() { loaded = grid_row_cap() }
    var requests = math.ceil[f64](loaded / row_page_size())
    if requests < 1.0f64 { requests = 1.0f64 }
    if total > grid_row_cap() {
        let notice = f.join(a, f.join(a, f.join(a, "Showing the first ", format_integer(a, grid_row_cap(), locale)), " rows of "), f.join(a, format_integer(a, total, locale), "."))
        ret LoadPlan { loaded: loaded, truncated: true, requests: requests, notice: notice, has_notice: true }
    }
    ret LoadPlan { loaded: loaded, truncated: false, requests: requests, notice: "", has_notice: false }
}

// The latency budgets (milliseconds), by name.
fn latency_budget(name: str) -> (f64, bool) {
    if str.eq(name, "formSubmissionP95") { ret (800.0f64, true) }
    if str.eq(name, "publicFormInteractiveP75") { ret (1500.0f64, true) }
    if str.eq(name, "publicFormInteractiveP95") { ret (3000.0f64, true) }
    if str.eq(name, "appDirectoryAtScale") { ret (1000.0f64, true) }
    if str.eq(name, "appSwitcherAtScale") { ret (1000.0f64, true) }
    if str.eq(name, "homepageDomReady") { ret (2500.0f64, true) }
    if str.eq(name, "homepageLoaded") { ret (4000.0f64, true) }
    if str.eq(name, "signInFormVisible") { ret (600.0f64, true) }
    if str.eq(name, "applicationsVisible") { ret (3000.0f64, true) }
    if str.eq(name, "gridSortAtScale") { ret (1500.0f64, true) }
    if str.eq(name, "gridFilterAtScale") { ret (1000.0f64, true) }
    if str.eq(name, "consentBannerVisible") { ret (1200.0f64, true) }
    if str.eq(name, "pageReferenceInteractiveP75") { ret (2000.0f64, true) }
    if str.eq(name, "pageReferenceInteractiveP95") { ret (4000.0f64, true) }
    if str.eq(name, "recordScriptOutcome") { ret (1000.0f64, true) }
    ret (0.0f64, false)
}

type Budget = struct { within: bool, known: bool, budget: f64, measured: f64, message: str }

// Whether a measurement fits its budget, with a message naming both numbers (and the share of the budget used).
fn within_budget(a: *mem.Arena, name: str, measured_ms: f64) -> Budget {
    let (budget, known) = latency_budget(name)
    if !known { ret Budget { within: false, known: false, budget: 0.0f64, measured: measured_ms, message: f.join3(a, "no budget named \"", name, "\"") } }
    let within = measured_ms <= budget
    let shown = f.number_text(a, math.floor[f64](measured_ms + 0.5f64))
    if within {
        let percent = f.number_text(a, math.floor[f64](measured_ms / budget * 100.0f64 + 0.5f64))
        ret Budget { within: true, known: true, budget: budget, measured: measured_ms, message: f.join(a, f.join3(a, name, ": ", shown), f.join3(a, "ms / ", f.number_text(a, budget), f.join3(a, "ms (", percent, "%)"))) }
    }
    ret Budget { within: false, known: true, budget: budget, measured: measured_ms, message: f.join(a, f.join3(a, name, ": ", shown), f.join3(a, "ms EXCEEDS its ", f.number_text(a, budget), "ms budget. Make it faster, or change the budget deliberately in src/performance/limits.js.")) }
}

// The nearest-rank percentile of finite measurements (`p` between 0 and 1); false for none.
fn percentile(a: *mem.Arena, values: []const f64, p: f64) -> (f64, bool) {
    let (sorted, e) = mem.alloc[f64](a, values.len + 1usize)
    if e != ok { ret (0.0f64, false) }
    var n = 0usize
    var i = 0usize
    while i < values.len {
        if values[i] == values[i] && values[i] - values[i] == 0.0f64 {
            sorted[n] = values[i]
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize { ret (0.0f64, false) }
    var x = 1usize
    while x < n {
        let item = sorted[x]
        var y = x
        while y > 0usize && sorted[y - 1usize] > item {
            sorted[y] = sorted[y - 1usize]
            y -= 1usize
        }
        sorted[y] = item
        x += 1usize
    }
    var rank = math.ceil[f64](p * f64(n))
    if rank < 1.0f64 { rank = 1.0f64 }
    if rank > f64(n) { rank = f64(n) }
    ret (sorted[usize(rank) - 1usize], true)
}
