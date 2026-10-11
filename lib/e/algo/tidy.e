// Tidy-data verbs over the table rows of `e.algo.view` (L032): rows of named
// `e.algo.formula` values, one `view.Row` per record. Every verb takes the arena
// that owns its result and answers new rows in the order dplyr/tidyr/pandas
// give; the inputs are never changed.
//
// - Column selection with tidy-select semantics (`Selector`: name, `from:to`
//   range, starts_with, ends_with, contains, everything, by type, each
//   negatable): `select`, `rename`, `relocate`, `mutate`.
// - Joins by one or more key columns (`join`: inner, left, right, full, semi,
//   anti) planned over `e.db.query`'s hash join and anti join on interned
//   integer keys; a missing key matches a missing key, as dplyr's default does.
//   Colliding non-key names take the `.x` / `.y` suffixes.
// - `pivot_wider` and `pivot_longer`.
// - Window functions per partition in order: row number, rank, dense rank, lag,
//   lead, cumulative sum/mean/max/min, rolling sum/mean and difference.
// - Missing-value verbs: `drop_na`, `replace_na`, `fill` down or up.
//
// A value is missing when it is blank or a NaN number. Window and fill order is
// the stable order of `order_by` (numbers and dates), or the row order when it
// is empty.

use e.algo.formula as f
use e.algo.view as view
use e.db.query as query
use e.math
use e.mem
use e.str

error Invalid
error Missing
error Duplicates

const SELECT_NAME: u8 = 0u8
const SELECT_RANGE: u8 = 1u8
const SELECT_STARTS: u8 = 2u8
const SELECT_ENDS: u8 = 3u8
const SELECT_CONTAINS: u8 = 4u8
const SELECT_EVERYTHING: u8 = 5u8
const SELECT_TYPE: u8 = 6u8

const JOIN_INNER: u8 = 0u8
const JOIN_LEFT: u8 = 1u8
const JOIN_RIGHT: u8 = 2u8
const JOIN_FULL: u8 = 3u8
const JOIN_SEMI: u8 = 4u8
const JOIN_ANTI: u8 = 5u8

const WINDOW_ROW_NUMBER: u8 = 0u8
const WINDOW_RANK: u8 = 1u8
const WINDOW_DENSE_RANK: u8 = 2u8
const WINDOW_LAG: u8 = 3u8
const WINDOW_LEAD: u8 = 4u8
const WINDOW_CUMSUM: u8 = 5u8
const WINDOW_CUMMEAN: u8 = 6u8
const WINDOW_CUMMAX: u8 = 7u8
const WINDOW_CUMMIN: u8 = 8u8
const WINDOW_ROLLSUM: u8 = 9u8
const WINDOW_ROLLMEAN: u8 = 10u8
const WINDOW_DIFF: u8 = 11u8

const FILL_DOWN: u8 = 0u8
const FILL_UP: u8 = 1u8

// One tidy-select term: a kind, its operands, and whether it removes.
type Selector = struct { kind: u8, first: str, second: str, negate: bool }

// One window computation: `output` is the new column, `size` the lag/lead
// offset or rolling width.
type Window = struct { function: u8, input: str, output: str, partition: []const str, order_by: str, descending: bool, size: usize }

fn by_name(name: str) -> Selector { ret Selector { kind: SELECT_NAME, first: name, second: "", negate: false } }

fn by_range(from: str, to: str) -> Selector { ret Selector { kind: SELECT_RANGE, first: from, second: to, negate: false } }

fn starts_with(prefix: str) -> Selector { ret Selector { kind: SELECT_STARTS, first: prefix, second: "", negate: false } }

fn ends_with(suffix: str) -> Selector { ret Selector { kind: SELECT_ENDS, first: suffix, second: "", negate: false } }

fn contains(part: str) -> Selector { ret Selector { kind: SELECT_CONTAINS, first: part, second: "", negate: false } }

fn everything() -> Selector { ret Selector { kind: SELECT_EVERYTHING, first: "", second: "", negate: false } }

// Columns whose first non-missing value is of `type_name`: "number", "text", "bool" or "date".
fn of_type(type_name: str) -> Selector { ret Selector { kind: SELECT_TYPE, first: type_name, second: "", negate: false } }

// The same term, removing instead of adding (dplyr's `-x`).
fn without(s: Selector) -> Selector { ret Selector { kind: s.kind, first: s.first, second: s.second, negate: true } }

fn is_missing(v: f.Value) -> bool {
    if v.kind == .Blank { ret true }
    ret v.kind == .Number && v.n != v.n
}

// The cell of `row` named `name`; a missing cell is blank.
fn cell_value(row: view.Row, name: str) -> f.Value { ret view.value_at(row, name) }

fn has_column(names: []const str, name: str) -> bool { ret column_index(names, name) < names.len }

fn column_index(names: []const str, name: str) -> usize {
    var i = 0usize
    while i < names.len {
        if str.eq(names[i], name) { ret i }
        i += 1usize
    }
    ret names.len
}

// Column names in order of first appearance across the rows.
fn column_names(a: *mem.Arena, rows: []const view.Row) -> ([]str, err) {
    var total = 0usize
    var i = 0usize
    while i < rows.len {
        total += rows[i].fields.len
        i += 1usize
    }
    let (names, e) = mem.alloc[str](a, total + 1usize)
    if e != ok { ret (names, e) }
    var count = 0usize
    i = 0usize
    while i < rows.len {
        var j = 0usize
        while j < rows[i].fields.len {
            if !has_column(names[..count], rows[i].fields[j].name) {
                names[count] = rows[i].fields[j].name
                count += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (names[..count], ok)
}

fn kind_name(v: f.Value) -> str {
    if v.kind == .Number { ret "number" }
    if v.kind == .Text { ret "text" }
    if v.kind == .Bool { ret "bool" }
    if v.kind == .Date { ret "date" }
    ret "other"
}

fn matches_type(rows: []const view.Row, name: str, type_name: str) -> bool {
    var i = 0usize
    while i < rows.len {
        let v = cell_value(rows[i], name)
        if !is_missing(v) { ret str.eq(kind_name(v), type_name) }
        i += 1usize
    }
    ret false
}

fn term_matches(s: Selector, names: []const str, rows: []const view.Row, i: usize, range_from: usize, range_to: usize) -> bool {
    let name = names[i]
    if s.kind == SELECT_NAME { ret str.eq(name, s.first) }
    if s.kind == SELECT_RANGE { ret i >= range_from && i <= range_to }
    if s.kind == SELECT_STARTS { ret str.starts_with(name, s.first) }
    if s.kind == SELECT_ENDS { ret str.ends_with(name, s.first) }
    if s.kind == SELECT_CONTAINS {
        let (at_index, found) = str.find(name, s.first)
        ret found
    }
    if s.kind == SELECT_EVERYTHING { ret true }
    if s.kind == SELECT_TYPE { ret matches_type(rows, name, s.first) }
    ret false
}

// The columns the selectors choose, in dplyr's order: terms add in the order
// written (each column once, in column order within a term), negated terms
// remove, and a leading negated term starts from every column.
fn select_columns(a: *mem.Arena, rows: []const view.Row, selectors: []const Selector) -> ([]str, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (names, ne) }
    let (chosen, ce) = mem.alloc[str](a, names.len + 1usize)
    if ce != ok { ret (chosen, ce) }
    var count = 0usize
    if selectors.len > 0usize && selectors[0usize].negate {
        var k = 0usize
        while k < names.len {
            chosen[k] = names[k]
            k += 1usize
        }
        count = names.len
    }
    var t = 0usize
    while t < selectors.len {
        let s = selectors[t]
        var from = 0usize
        var to = 0usize
        if s.kind == SELECT_RANGE {
            from = column_index(names, s.first)
            to = column_index(names, s.second)
            if from >= names.len || to >= names.len { ret (chosen[..0usize], Missing) }
            if from > to {
                let swap = from
                from = to
                to = swap
            }
        }
        if s.kind == SELECT_NAME && !has_column(names, s.first) { ret (chosen[..0usize], Missing) }
        var i = 0usize
        while i < names.len {
            if term_matches(s, names, rows, i, from, to) {
                let at_chosen = column_index(chosen[..count], names[i])
                if s.negate {
                    if at_chosen < count {
                        var k = at_chosen
                        while k + 1usize < count {
                            chosen[k] = chosen[k + 1usize]
                            k += 1usize
                        }
                        count -= 1usize
                    }
                } else if at_chosen == count {
                    chosen[count] = names[i]
                    count += 1usize
                }
            }
            i += 1usize
        }
        t += 1usize
    }
    ret (chosen[..count], ok)
}

// A row with the given names and values.
fn make_row(a: *mem.Arena, names: []const str, values: []const f.Value) -> (view.Row, err) {
    let (fields, e) = mem.alloc[f.Field](a, names.len + 1usize)
    if e != ok { ret (view.Row{ fields: fields }, e) }
    var i = 0usize
    while i < names.len {
        fields[i] = f.Field { name: names[i], value: values[i] }
        i += 1usize
    }
    ret (view.Row{ fields: fields[..names.len] }, ok)
}

// `rows` restricted to `names`, in that order (a missing cell is blank).
fn project(a: *mem.Arena, rows: []const view.Row, names: []const str) -> ([]view.Row, err) {
    let (out, e) = mem.alloc[view.Row](a, rows.len + 1usize)
    if e != ok { ret (out, e) }
    let (values, ve) = mem.alloc[f.Value](a, names.len + 1usize)
    if ve != ok { ret (out, ve) }
    var i = 0usize
    while i < rows.len {
        var j = 0usize
        while j < names.len {
            values[j] = cell_value(rows[i], names[j])
            j += 1usize
        }
        let (row, re) = make_row(a, names, values[..names.len])
        if re != ok { ret (out, re) }
        out[i] = row
        i += 1usize
    }
    ret (out[..rows.len], ok)
}

// dplyr `select`.
fn select(a: *mem.Arena, rows: []const view.Row, selectors: []const Selector) -> ([]view.Row, err) {
    let (names, e) = select_columns(a, rows, selectors)
    if e != ok { ret (zero, e) }
    let (projected, pe) = project(a, rows, names)
    ret (projected, pe)
}

// dplyr `rename`: `from[i]` becomes `to[i]`; every column is kept in place.
fn rename(a: *mem.Arena, rows: []const view.Row, from: []const str, to: []const str) -> ([]view.Row, err) {
    if from.len != to.len { ret (zero, Invalid) }
    let (names, e) = column_names(a, rows)
    if e != ok { ret (zero, e) }
    let (renamed, re) = mem.alloc[str](a, names.len + 1usize)
    if re != ok { ret (zero, re) }
    var k = 0usize
    while k < from.len {
        if !has_column(names, from[k]) { ret (zero, Missing) }
        k += 1usize
    }
    var i = 0usize
    while i < names.len {
        renamed[i] = names[i]
        k = 0usize
        while k < from.len {
            if str.eq(names[i], from[k]) { renamed[i] = to[k] }
            k += 1usize
        }
        i += 1usize
    }
    let (out, oe) = mem.alloc[view.Row](a, rows.len + 1usize)
    if oe != ok { ret (zero, oe) }
    let (values, ve) = mem.alloc[f.Value](a, names.len + 1usize)
    if ve != ok { ret (zero, ve) }
    var r = 0usize
    while r < rows.len {
        i = 0usize
        while i < names.len {
            values[i] = cell_value(rows[r], names[i])
            i += 1usize
        }
        let (row, me) = make_row(a, renamed[..names.len], values[..names.len])
        if me != ok { ret (zero, me) }
        out[r] = row
        r += 1usize
    }
    ret (out[..rows.len], ok)
}

// dplyr `relocate`: the selected columns move to the front, or before `before`
// or after `after` (at most one is non-empty), keeping their selection order.
fn relocate(a: *mem.Arena, rows: []const view.Row, selectors: []const Selector, before: str, after: str) -> ([]view.Row, err) {
    let (names, e) = column_names(a, rows)
    if e != ok { ret (zero, e) }
    let (moved, me) = select_columns(a, rows, selectors)
    if me != ok { ret (zero, me) }
    if before.len > 0usize && after.len > 0usize { ret (zero, Invalid) }
    var anchor = names.len
    if before.len > 0usize { anchor = column_index(names, before) }
    if after.len > 0usize { anchor = column_index(names, after) }
    if (before.len > 0usize || after.len > 0usize) && anchor >= names.len { ret (zero, Missing) }
    let (order, oe) = mem.alloc[str](a, names.len + 1usize)
    if oe != ok { ret (zero, oe) }
    var count = 0usize
    var i = 0usize
    var placed = false
    if before.len == 0usize && after.len == 0usize {
        var k = 0usize
        while k < moved.len {
            order[count] = moved[k]
            count += 1usize
            k += 1usize
        }
        placed = true
    }
    while i < names.len {
        let is_moved = has_column(moved, names[i])
        if i == anchor && before.len > 0usize && !placed {
            var k = 0usize
            while k < moved.len {
                order[count] = moved[k]
                count += 1usize
                k += 1usize
            }
            placed = true
        }
        if !is_moved {
            order[count] = names[i]
            count += 1usize
        }
        if i == anchor && after.len > 0usize && !placed {
            var k = 0usize
            while k < moved.len {
                order[count] = moved[k]
                count += 1usize
                k += 1usize
            }
            placed = true
        }
        i += 1usize
    }
    let (placed_rows, pe2) = project(a, rows, order[..count])
    ret (placed_rows, pe2)
}

// dplyr `mutate` for one column: `compute(ctx, row, index)` gives the value, the
// column replaces an existing one of the same name or is appended.
fn mutate[Ctx: type](a: *mem.Arena, rows: []const view.Row, name: str, ctx: *Ctx, compute: fn(*Ctx, view.Row, usize) -> f.Value) -> ([]view.Row, err) {
    let (names, e) = column_names(a, rows)
    if e != ok { ret (zero, e) }
    let existing = column_index(names, name)
    var width = names.len
    if existing == names.len { width += 1usize }
    let (all, ae) = mem.alloc[str](a, width + 1usize)
    if ae != ok { ret (zero, ae) }
    var i = 0usize
    while i < names.len {
        all[i] = names[i]
        i += 1usize
    }
    if existing == names.len { all[names.len] = name }
    let (out, oe) = mem.alloc[view.Row](a, rows.len + 1usize)
    if oe != ok { ret (zero, oe) }
    let (values, ve) = mem.alloc[f.Value](a, width + 1usize)
    if ve != ok { ret (zero, ve) }
    var r = 0usize
    while r < rows.len {
        i = 0usize
        while i < names.len {
            values[i] = cell_value(rows[r], names[i])
            i += 1usize
        }
        let made = compute(ctx, rows[r], r)
        if existing == names.len { values[names.len] = made } else { values[existing] = made }
        let (row, re) = make_row(a, all[..width], values[..width])
        if re != ok { ret (zero, re) }
        out[r] = row
        r += 1usize
    }
    ret (out[..rows.len], ok)
}

// --- keys ------------------------------------------------------------------------------------------------------

// The identity of a value for matching: a type letter and its text.
fn value_key(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Blank { ret "b" }
    if v.kind == .Number { ret f.join(a, "n", f.number_text(a, v.n)) }
    if v.kind == .Text { ret f.join(a, "t", v.s) }
    if v.kind == .Bool { ret f.join(a, "o", f.number_text(a, v.n)) }
    if v.kind == .Date { ret f.join(a, "d", f.number_text(a, v.n)) }
    ret f.join(a, "x", v.s)
}

// The text of a value as a column name or label.
fn value_text(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Text { ret v.s }
    if v.kind == .Blank { ret "" }
    ret f.number_text(a, v.n)
}

fn row_key(a: *mem.Arena, row: view.Row, cols: []const str) -> str {
    var key = ""
    var i = 0usize
    while i < cols.len {
        key = f.join(a, key, f.join(a, value_key(a, cell_value(row, cols[i])), "\x1f"))
        i += 1usize
    }
    ret key
}

fn hash_text(s: str) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < s.len {
        h = (h ^ u64(s[i])) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

// Dense ids by first appearance for `keys`, and how many distinct there are.
fn intern(a: *mem.Arena, keys: []const str) -> ([]usize, usize, err) {
    let (ids, ie) = mem.alloc[usize](a, keys.len + 1usize)
    if ie != ok { ret (ids, 0usize, ie) }
    var size = 16usize
    while size < 2usize * keys.len + 2usize { size = size * 2usize }
    let (slots, se) = mem.alloc[usize](a, size)
    if se != ok { ret (ids, 0usize, se) }
    let (firsts, fe) = mem.alloc[usize](a, keys.len + 1usize)
    if fe != ok { ret (ids, 0usize, fe) }
    var i = 0usize
    while i < size {
        slots[i] = 0usize
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < keys.len {
        var h = usize(hash_text(keys[i]) % u64(size))
        var found = false
        while slots[h] != 0usize && !found {
            if str.eq(keys[firsts[slots[h] - 1usize]], keys[i]) {
                ids[i] = slots[h] - 1usize
                found = true
            } else {
                h = (h + 1usize) % size
            }
        }
        if !found {
            slots[h] = count + 1usize
            firsts[count] = i
            ids[i] = count
            count += 1usize
        }
        i += 1usize
    }
    ret (ids[..keys.len], count, ok)
}

// Dense ids by first appearance of each row's key over `cols`.
fn group_ids(a: *mem.Arena, rows: []const view.Row, cols: []const str) -> ([]usize, usize, err) {
    let (keys, ke) = mem.alloc[str](a, rows.len + 1usize)
    if ke != ok { ret (zero, 0usize, ke) }
    var i = 0usize
    while i < rows.len {
        keys[i] = row_key(a, rows[i], cols)
        i += 1usize
    }
    let (ids, total, ie) = intern(a, keys[..rows.len])
    ret (ids, total, ie)
}

// --- joins -----------------------------------------------------------------------------------------------------

// Shell sort of packed `u64` pairs.
fn sort_pairs(values: []u64) {
    var gap = values.len / 2usize
    while gap > 0usize {
        var i = gap
        while i < values.len {
            let held = values[i]
            var j = i
            while j >= gap && values[j - gap] > held {
                values[j] = values[j - gap]
                j -= gap
            }
            values[j] = held
            i += 1usize
        }
        gap = gap / 2usize
    }
}

// The row pairs `(left, right)` of an inner join on interned keys, sorted by
// left then right row, through `e.db.query`'s hash join. Answers the count.
fn join_pairs(a: *mem.Arena, left_ids: []const usize, right_ids: []const usize, out: []u64) -> (usize, err) {
    let (left_cells, lce) = mem.alloc[i64](a, 2usize * left_ids.len + 2usize)
    if lce != ok { ret (0usize, lce) }
    let (right_cells, rce) = mem.alloc[i64](a, 2usize * right_ids.len + 2usize)
    if rce != ok { ret (0usize, rce) }
    var i = 0usize
    while i < left_ids.len {
        left_cells[2usize * i] = i64(left_ids[i])
        left_cells[2usize * i + 1usize] = i64(i)
        i += 1usize
    }
    i = 0usize
    while i < right_ids.len {
        right_cells[2usize * i] = i64(right_ids[i])
        right_cells[2usize * i + 1usize] = i64(i)
        i += 1usize
    }
    let left = query.table(left_cells[..2usize * left_ids.len], 2usize)
    let right = query.table(right_cells[..2usize * right_ids.len], 2usize)
    let (buckets, be) = mem.alloc[u32](a, 2usize * (left_ids.len + right_ids.len) + 4usize)
    if be != ok { ret (0usize, be) }
    let (chain, ce) = mem.alloc[u32](a, left_ids.len + right_ids.len + 2usize)
    if ce != ok { ret (0usize, ce) }
    let (cells, ocr) = mem.alloc[i64](a, 4usize * out.len + 4usize)
    if ocr != ok { ret (0usize, ocr) }
    let (n, e) = query.join_hash(left, 0usize, right, 0usize, cells[..4usize * out.len], buckets, chain)
    if e != ok { ret (0usize, e) }
    i = 0usize
    while i < n {
        out[i] = (u64(cells[4usize * i + 1usize]) << 32u32) | u64(cells[4usize * i + 3usize])
        i += 1usize
    }
    sort_pairs(out[..n])
    ret (n, ok)
}

// Rows of `from` whose key has no match among `against` (an anti join through
// `e.db.query`), as row indices in order.
fn unmatched(a: *mem.Arena, from_ids: []const usize, against_ids: []const usize, out: []usize) -> (usize, err) {
    let (from_cells, fce) = mem.alloc[i64](a, 2usize * from_ids.len + 2usize)
    if fce != ok { ret (0usize, fce) }
    let (against_cells, ace) = mem.alloc[i64](a, 2usize * against_ids.len + 2usize)
    if ace != ok { ret (0usize, ace) }
    var i = 0usize
    while i < from_ids.len {
        from_cells[2usize * i] = i64(from_ids[i])
        from_cells[2usize * i + 1usize] = i64(i)
        i += 1usize
    }
    i = 0usize
    while i < against_ids.len {
        against_cells[2usize * i] = i64(against_ids[i])
        against_cells[2usize * i + 1usize] = i64(i)
        i += 1usize
    }
    let from_table = query.table(from_cells[..2usize * from_ids.len], 2usize)
    let against_table = query.table(against_cells[..2usize * against_ids.len], 2usize)
    let (buckets, be) = mem.alloc[u32](a, 2usize * (from_ids.len + against_ids.len) + 4usize)
    if be != ok { ret (0usize, be) }
    let (chain, ce) = mem.alloc[u32](a, from_ids.len + against_ids.len + 2usize)
    if ce != ok { ret (0usize, ce) }
    let (cells, oe) = mem.alloc[i64](a, 2usize * from_ids.len + 2usize)
    if oe != ok { ret (0usize, oe) }
    let (n, e) = query.join_anti(from_table, 0usize, against_table, 0usize, cells, buckets, chain)
    if e != ok { ret (0usize, e) }
    i = 0usize
    while i < n {
        out[i] = usize(cells[2usize * i + 1usize])
        i += 1usize
    }
    ret (n, ok)
}

// The join of `left` and `right` on `by_left[i] == by_right[i]`. Columns are
// the left's, then the right's non-key columns (a name that collides takes
// `suffix_left` / `suffix_right` on both sides). Row order follows dplyr: left
// rows with their right matches for inner/left/semi/anti; right rows for right;
// matched pairs in left order then unmatched right rows for full. A right-only
// row takes its key values into the left's key columns.
fn join(a: *mem.Arena, left: []const view.Row, right: []const view.Row, by_left: []const str, by_right: []const str, kind: u8, suffix_left: str, suffix_right: str) -> ([]view.Row, err) {
    if by_left.len == 0usize || by_left.len != by_right.len { ret (zero, Invalid) }
    let (left_names, lne) = column_names(a, left)
    if lne != ok { ret (zero, lne) }
    let (right_names, rne) = column_names(a, right)
    if rne != ok { ret (zero, rne) }
    var k = 0usize
    while k < by_left.len {
        if !has_column(left_names, by_left[k]) || !has_column(right_names, by_right[k]) { ret (zero, Missing) }
        k += 1usize
    }
    let (left_ids, _, lie) = group_ids_pair(a, left, right, by_left, by_right)
    if lie != ok { ret (zero, lie) }
    let nl = left.len
    let nr = right.len
    // Output columns.
    let (cols, ce) = mem.alloc[str](a, left_names.len + right_names.len + 1usize)
    if ce != ok { ret (zero, ce) }
    var width = 0usize
    var i = 0usize
    while i < left_names.len {
        var out_name = left_names[i]
        let clash = has_column(right_names, left_names[i]) && !has_column(by_right, left_names[i]) && kind != JOIN_SEMI && kind != JOIN_ANTI
        if clash { out_name = f.join(a, left_names[i], suffix_left) }
        cols[width] = out_name
        width += 1usize
        i += 1usize
    }
    let left_width = width
    // Right columns appended (excluding right keys) for the value-carrying joins.
    let (right_source, rse) = mem.alloc[usize](a, right_names.len + 1usize)
    if rse != ok { ret (zero, rse) }
    var right_count = 0usize
    if kind != JOIN_SEMI && kind != JOIN_ANTI {
        i = 0usize
        while i < right_names.len {
            if !has_column(by_right, right_names[i]) {
                var out_name = right_names[i]
                if has_column(left_names, right_names[i]) { out_name = f.join(a, right_names[i], suffix_right) }
                cols[width] = out_name
                right_source[right_count] = i
                width += 1usize
                right_count += 1usize
            }
            i += 1usize
        }
    }
    // Row pairs: `pairs` packs (left << 32 | right); an unmatched side is `0xFFFFFFFF`.
    let miss = 4294967295u64
    let (distinct_left, dle) = mem.alloc[usize](a, nl + nr + 1usize)
    if dle != ok { ret (zero, dle) }
    let (distinct_right, dre) = mem.alloc[usize](a, nl + nr + 1usize)
    if dre != ok { ret (zero, dre) }
    i = 0usize
    while i < nl + nr + 1usize {
        distinct_left[i] = 0usize
        distinct_right[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < nl {
        distinct_left[left_ids[i]] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < nr {
        distinct_right[left_ids[nl + i]] += 1usize
        i += 1usize
    }
    var capacity = 0usize
    i = 0usize
    while i < nl + nr {
        capacity += distinct_left[i] * distinct_right[i]
        i += 1usize
    }
    let (matched, me) = mem.alloc[u64](a, capacity + 1usize)
    if me != ok { ret (zero, me) }
    let (total, jie) = join_pairs(a, left_ids[..nl], left_ids[nl..nl + nr], matched)
    if jie != ok { ret (zero, jie) }
    let (lonely_left, lle) = mem.alloc[usize](a, nl + 1usize)
    if lle != ok { ret (zero, lle) }
    let (lonely_right, lre) = mem.alloc[usize](a, nr + 1usize)
    if lre != ok { ret (zero, lre) }
    var n_lonely_left = 0usize
    var n_lonely_right = 0usize
    let (ull, ue1) = unmatched(a, left_ids[..nl], left_ids[nl..nl + nr], lonely_left)
    if ue1 != ok { ret (zero, ue1) }
    n_lonely_left = ull
    let (url, ue2) = unmatched(a, left_ids[nl..nl + nr], left_ids[..nl], lonely_right)
    if ue2 != ok { ret (zero, ue2) }
    n_lonely_right = url
    // Assemble the output pair list.
    let (pairs, pe) = mem.alloc[u64](a, total + nl + nr + 2usize)
    if pe != ok { ret (zero, pe) }
    var count = 0usize
    if kind == JOIN_SEMI || kind == JOIN_ANTI {
        // Semi keeps left rows with a match, anti those without, in left order.
        let (flags, fe) = mem.alloc[bool](a, nl + 1usize)
        if fe != ok { ret (zero, fe) }
        i = 0usize
        while i < nl {
            flags[i] = kind == JOIN_SEMI
            i += 1usize
        }
        i = 0usize
        while i < n_lonely_left {
            flags[lonely_left[i]] = kind == JOIN_ANTI
            i += 1usize
        }
        i = 0usize
        while i < nl {
            if flags[i] {
                pairs[count] = (u64(i) << 32u32) | miss
                count += 1usize
            }
            i += 1usize
        }
    } else {
        // Matched pairs are already left-major; fold in the unmatched rows by kind.
        if kind == JOIN_RIGHT {
            // Right order: for each right row its matches in left order, or the lone right row.
            let (by_right_start, bre) = mem.alloc[usize](a, nr + 2usize)
            if bre != ok { ret (zero, bre) }
            var m = 0usize
            var rr = 0usize
            // Counting pass over right rows.
            i = 0usize
            while i < nr + 2usize {
                by_right_start[i] = 0usize
                i += 1usize
            }
            m = 0usize
            while m < total {
                by_right_start[usize(matched[m] & miss) + 1usize] += 1usize
                m += 1usize
            }
            rr = 0usize
            while rr < nr {
                by_right_start[rr + 1usize] += by_right_start[rr]
                rr += 1usize
            }
            // Fill right-major, keeping left order within a right row (matched is left-major).
            let (cursor, cue) = mem.alloc[usize](a, nr + 1usize)
            if cue != ok { ret (zero, cue) }
            i = 0usize
            while i < nr {
                cursor[i] = by_right_start[i]
                i += 1usize
            }
            let (ordered, oe) = mem.alloc[u64](a, total + 1usize)
            if oe != ok { ret (zero, oe) }
            m = 0usize
            while m < total {
                let r = usize(matched[m] & miss)
                ordered[cursor[r]] = matched[m]
                cursor[r] += 1usize
                m += 1usize
            }
            let (lone_flag, lfe) = mem.alloc[bool](a, nr + 1usize)
            if lfe != ok { ret (zero, lfe) }
            i = 0usize
            while i < nr {
                lone_flag[i] = false
                i += 1usize
            }
            i = 0usize
            while i < n_lonely_right {
                lone_flag[lonely_right[i]] = true
                i += 1usize
            }
            rr = 0usize
            while rr < nr {
                if lone_flag[rr] {
                    pairs[count] = (miss << 32u32) | u64(rr)
                    count += 1usize
                } else {
                    var q = by_right_start[rr]
                    while q < by_right_start[rr + 1usize] {
                        pairs[count] = ordered[q]
                        count += 1usize
                        q += 1usize
                    }
                }
                rr += 1usize
            }
        } else {
            // Inner, left, full: left-major with lone left rows in place for left and full.
            let (lone_left_flag, llf) = mem.alloc[bool](a, nl + 1usize)
            if llf != ok { ret (zero, llf) }
            i = 0usize
            while i < nl {
                lone_left_flag[i] = false
                i += 1usize
            }
            i = 0usize
            while i < n_lonely_left {
                lone_left_flag[lonely_left[i]] = true
                i += 1usize
            }
            var m = 0usize
            i = 0usize
            while i < nl {
                if lone_left_flag[i] {
                    if kind == JOIN_LEFT || kind == JOIN_FULL {
                        pairs[count] = (u64(i) << 32u32) | miss
                        count += 1usize
                    }
                } else {
                    while m < total && usize(matched[m] >> 32u32) == i {
                        pairs[count] = matched[m]
                        count += 1usize
                        m += 1usize
                    }
                }
                i += 1usize
            }
            if kind == JOIN_FULL {
                i = 0usize
                while i < n_lonely_right {
                    pairs[count] = (miss << 32u32) | u64(lonely_right[i])
                    count += 1usize
                    i += 1usize
                }
            }
        }
    }
    // Materialise.
    let (out, oe2) = mem.alloc[view.Row](a, count + 1usize)
    if oe2 != ok { ret (zero, oe2) }
    let (values, ve) = mem.alloc[f.Value](a, width + 1usize)
    if ve != ok { ret (zero, ve) }
    var p = 0usize
    while p < count {
        let li = pairs[p] >> 32u32
        let ri = pairs[p] & miss
        i = 0usize
        while i < left_width {
            values[i] = f.blank()
            if li != miss {
                values[i] = cell_value(left[usize(li)], left_names[i])
            } else if ri != miss {
                // A right-only row: key columns come from the right's keys.
                k = 0usize
                while k < by_left.len {
                    if str.eq(left_names[i], by_left[k]) { values[i] = cell_value(right[usize(ri)], by_right[k]) }
                    k += 1usize
                }
            }
            i += 1usize
        }
        i = 0usize
        while i < right_count {
            values[left_width + i] = f.blank()
            if ri != miss { values[left_width + i] = cell_value(right[usize(ri)], right_names[right_source[i]]) }
            i += 1usize
        }
        let (row, re) = make_row(a, cols[..width], values[..width])
        if re != ok { ret (zero, re) }
        out[p] = row
        p += 1usize
    }
    ret (out[..count], ok)
}

// Interned key ids of the left rows followed by the right rows, over a shared
// dictionary so equal keys share an id.
fn group_ids_pair(a: *mem.Arena, left: []const view.Row, right: []const view.Row, by_left: []const str, by_right: []const str) -> ([]usize, usize, err) {
    let (keys, ke) = mem.alloc[str](a, left.len + right.len + 1usize)
    if ke != ok { ret (zero, 0usize, ke) }
    var i = 0usize
    while i < left.len {
        keys[i] = row_key(a, left[i], by_left)
        i += 1usize
    }
    i = 0usize
    while i < right.len {
        keys[left.len + i] = row_key(a, right[i], by_right)
        i += 1usize
    }
    let (ids, total, ie) = intern(a, keys[..left.len + right.len])
    ret (ids, total, ie)
}

// --- pivots ----------------------------------------------------------------------------------------------------

// tidyr `pivot_wider`: one row per distinct `id_cols` combination (every other
// column when empty) in order of first appearance, one column per distinct
// `names_from` value in order of first appearance; cells with no row are `fill_value`.
// Two rows for one cell are `Duplicates`.
fn pivot_wider(a: *mem.Arena, rows: []const view.Row, id_cols: []const str, names_from: str, values_from: str, fill_value: f.Value) -> ([]view.Row, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (zero, ne) }
    if !has_column(names, names_from) || !has_column(names, values_from) { ret (zero, Missing) }
    let (ids, ide) = mem.alloc[str](a, names.len + 1usize)
    if ide != ok { ret (zero, ide) }
    var id_count = 0usize
    var i = 0usize
    if id_cols.len == 0usize {
        while i < names.len {
            if !str.eq(names[i], names_from) && !str.eq(names[i], values_from) {
                ids[id_count] = names[i]
                id_count += 1usize
            }
            i += 1usize
        }
    } else {
        while i < id_cols.len {
            if !has_column(names, id_cols[i]) { ret (zero, Missing) }
            ids[id_count] = id_cols[i]
            id_count += 1usize
            i += 1usize
        }
    }
    let id_names = ids[..id_count]
    let (row_ids, row_total, re) = group_ids(a, rows, id_names)
    if re != ok { ret (zero, re) }
    let (labels, le) = mem.alloc[str](a, rows.len + 1usize)
    if le != ok { ret (zero, le) }
    i = 0usize
    while i < rows.len {
        labels[i] = value_key(a, cell_value(rows[i], names_from))
        i += 1usize
    }
    let (col_ids, col_total, ce) = intern(a, labels[..rows.len])
    if ce != ok { ret (zero, ce) }
    // First row of each id and each column label, for the output text.
    let (id_first, ife) = mem.alloc[usize](a, row_total + 1usize)
    if ife != ok { ret (zero, ife) }
    let (col_first, cfe) = mem.alloc[usize](a, col_total + 1usize)
    if cfe != ok { ret (zero, cfe) }
    var seen_ids = 0usize
    var seen_cols = 0usize
    i = 0usize
    while i < rows.len {
        if row_ids[i] == seen_ids {
            id_first[seen_ids] = i
            seen_ids += 1usize
        }
        if col_ids[i] == seen_cols {
            col_first[seen_cols] = i
            seen_cols += 1usize
        }
        i += 1usize
    }
    let out_width = id_count + col_total
    let (out_names, one) = mem.alloc[str](a, out_width + 1usize)
    if one != ok { ret (zero, one) }
    i = 0usize
    while i < id_count {
        out_names[i] = id_names[i]
        i += 1usize
    }
    i = 0usize
    while i < col_total {
        out_names[id_count + i] = value_text(a, cell_value(rows[col_first[i]], names_from))
        i += 1usize
    }
    let (cells, cee) = mem.alloc[f.Value](a, row_total * col_total + 1usize)
    if cee != ok { ret (zero, cee) }
    let (filled, fie) = mem.alloc[bool](a, row_total * col_total + 1usize)
    if fie != ok { ret (zero, fie) }
    i = 0usize
    while i < row_total * col_total {
        cells[i] = fill_value
        filled[i] = false
        i += 1usize
    }
    i = 0usize
    while i < rows.len {
        let at_cell = row_ids[i] * col_total + col_ids[i]
        if filled[at_cell] { ret (zero, Duplicates) }
        filled[at_cell] = true
        cells[at_cell] = cell_value(rows[i], values_from)
        i += 1usize
    }
    let (out, oe) = mem.alloc[view.Row](a, row_total + 1usize)
    if oe != ok { ret (zero, oe) }
    let (values, ve) = mem.alloc[f.Value](a, out_width + 1usize)
    if ve != ok { ret (zero, ve) }
    var r = 0usize
    while r < row_total {
        i = 0usize
        while i < id_count {
            values[i] = cell_value(rows[id_first[r]], id_names[i])
            i += 1usize
        }
        i = 0usize
        while i < col_total {
            values[id_count + i] = cells[r * col_total + i]
            i += 1usize
        }
        let (row, mre) = make_row(a, out_names[..out_width], values[..out_width])
        if mre != ok { ret (zero, mre) }
        out[r] = row
        r += 1usize
    }
    ret (out[..row_total], ok)
}

// tidyr `pivot_longer`: the selected columns become `names_to` / `values_to`
// pairs, row by row in selection order, the other columns repeating;
// `omit_missing` leaves out missing values.
fn pivot_longer(a: *mem.Arena, rows: []const view.Row, selectors: []const Selector, names_to: str, values_to: str, omit_missing: bool) -> ([]view.Row, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (zero, ne) }
    let (chosen, se) = select_columns(a, rows, selectors)
    if se != ok { ret (zero, se) }
    if chosen.len == 0usize { ret (zero, Invalid) }
    let (keep, ke) = mem.alloc[str](a, names.len + 1usize)
    if ke != ok { ret (zero, ke) }
    var keep_count = 0usize
    var i = 0usize
    while i < names.len {
        if !has_column(chosen, names[i]) {
            keep[keep_count] = names[i]
            keep_count += 1usize
        }
        i += 1usize
    }
    let width = keep_count + 2usize
    let (out_names, one) = mem.alloc[str](a, width + 1usize)
    if one != ok { ret (zero, one) }
    i = 0usize
    while i < keep_count {
        out_names[i] = keep[i]
        i += 1usize
    }
    out_names[keep_count] = names_to
    out_names[keep_count + 1usize] = values_to
    let (out, oe) = mem.alloc[view.Row](a, rows.len * chosen.len + 1usize)
    if oe != ok { ret (zero, oe) }
    let (values, ve) = mem.alloc[f.Value](a, width + 1usize)
    if ve != ok { ret (zero, ve) }
    var count = 0usize
    var r = 0usize
    while r < rows.len {
        var c = 0usize
        while c < chosen.len {
            let v = cell_value(rows[r], chosen[c])
            if !(omit_missing && is_missing(v)) {
                i = 0usize
                while i < keep_count {
                    values[i] = cell_value(rows[r], keep[i])
                    i += 1usize
                }
                values[keep_count] = f.text(chosen[c])
                values[keep_count + 1usize] = v
                let (row, re) = make_row(a, out_names[..width], values[..width])
                if re != ok { ret (zero, re) }
                out[count] = row
                count += 1usize
            }
            c += 1usize
        }
        r += 1usize
    }
    ret (out[..count], ok)
}

// --- window functions ------------------------------------------------------------------------------------------

// Row indices ordered by partition id, then `key` (ascending or descending),
// then row number: a total order, so the result is stable.
fn order_rows(order: []usize, part: []const usize, key: []const f64, descending: bool) {
    var gap = order.len / 2usize
    while gap > 0usize {
        var i = gap
        while i < order.len {
            let held = order[i]
            var j = i
            while j >= gap && row_after(order[j - gap], held, part, key, descending) {
                order[j] = order[j - gap]
                j -= gap
            }
            order[j] = held
            i += 1usize
        }
        gap = gap / 2usize
    }
}

fn row_after(x: usize, y: usize, part: []const usize, key: []const f64, descending: bool) -> bool {
    if part[x] != part[y] { ret part[x] > part[y] }
    // A missing key sorts last whichever way the order runs.
    let x_nan = key[x] != key[x]
    let y_nan = key[y] != key[y]
    if x_nan || y_nan {
        if x_nan && y_nan { ret x > y }
        ret x_nan
    }
    if key[x] != key[y] {
        if descending { ret key[x] < key[y] }
        ret key[x] > key[y]
    }
    ret x > y
}

fn number_or_nan(v: f.Value) -> f64 {
    if v.kind == .Number || v.kind == .Date || v.kind == .Bool { ret v.n }
    ret 0.0f64 / 0.0f64
}

// Apply a window function and add (or replace) `spec.output`. The values are
// numbers; a missing input yields a blank output, and rolling functions are
// blank until `size` non-missing values are in the window (pandas'
// `min_periods = window`).
fn window(a: *mem.Arena, rows: []const view.Row, spec: Window) -> ([]view.Row, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (zero, ne) }
    if !has_column(names, spec.input) && spec.function != WINDOW_ROW_NUMBER { ret (zero, Missing) }
    if spec.order_by.len > 0usize && !has_column(names, spec.order_by) { ret (zero, Missing) }
    if (spec.function == WINDOW_ROLLSUM || spec.function == WINDOW_ROLLMEAN) && spec.size == 0usize { ret (zero, Invalid) }
    let n = rows.len
    let (part, _, pe) = group_ids(a, rows, spec.partition)
    if pe != ok { ret (zero, pe) }
    let (input, ie) = mem.alloc[f64](a, n + 1usize)
    if ie != ok { ret (zero, ie) }
    let (key, ke) = mem.alloc[f64](a, n + 1usize)
    if ke != ok { ret (zero, ke) }
    let (order, oe) = mem.alloc[usize](a, n + 1usize)
    if oe != ok { ret (zero, oe) }
    let (result, re) = mem.alloc[f64](a, n + 1usize)
    if re != ok { ret (zero, re) }
    var i = 0usize
    while i < n {
        input[i] = 0.0f64 / 0.0f64
        if has_column(names, spec.input) { input[i] = number_or_nan(cell_value(rows[i], spec.input)) }
        key[i] = 0.0f64
        if spec.order_by.len > 0usize { key[i] = number_or_nan(cell_value(rows[i], spec.order_by)) }
        order[i] = i
        i += 1usize
    }
    let ranking = spec.function == WINDOW_RANK || spec.function == WINDOW_DENSE_RANK
    if ranking {
        // Rank the input itself within each partition; the output stays in row order.
        order_rows(order[..n], part, input, spec.descending)
    } else {
        var no_desc = spec.descending
        if spec.order_by.len == 0usize { no_desc = false }
        order_rows(order[..n], part, key, no_desc)
    }
    // Walk each partition's run.
    var start = 0usize
    while start < n {
        var end = start
        while end < n && part[order[end]] == part[order[start]] { end += 1usize }
        var running = 0.0f64
        var count = 0usize
        var best = 0.0f64
        var rank = 0usize
        var dense = 0usize
        var q = start
        while q < end {
            let at_row = order[q]
            let pos = q - start
            var out = 0.0f64 / 0.0f64
            let x = input[at_row]
            if spec.function == WINDOW_ROW_NUMBER {
                out = f64(pos + 1usize)
            } else if ranking {
                if x == x {
                    if q == start || !(input[order[q - 1usize]] == x) {
                        rank = pos + 1usize
                        dense += 1usize
                    }
                    if spec.function == WINDOW_RANK { out = f64(rank) } else { out = f64(dense) }
                }
            } else if spec.function == WINDOW_LAG {
                if pos >= spec.size { out = input[order[q - spec.size]] }
            } else if spec.function == WINDOW_LEAD {
                if q + spec.size < end { out = input[order[q + spec.size]] }
            } else if spec.function == WINDOW_DIFF {
                if pos >= 1usize { out = x - input[order[q - 1usize]] }
            } else if spec.function == WINDOW_CUMSUM || spec.function == WINDOW_CUMMEAN || spec.function == WINDOW_CUMMAX || spec.function == WINDOW_CUMMIN {
                if x == x {
                    if count == 0usize { best = x }
                    count += 1usize
                    running += x
                    if x > best && spec.function == WINDOW_CUMMAX { best = x }
                    if x < best && spec.function == WINDOW_CUMMIN { best = x }
                    if spec.function == WINDOW_CUMSUM { out = running }
                    if spec.function == WINDOW_CUMMEAN { out = running / f64(count) }
                    if spec.function == WINDOW_CUMMAX || spec.function == WINDOW_CUMMIN { out = best }
                }
            } else if spec.function == WINDOW_ROLLSUM || spec.function == WINDOW_ROLLMEAN {
                if pos + 1usize >= spec.size {
                    var sum = 0.0f64
                    var seen = 0usize
                    var w = q + 1usize - spec.size
                    while w <= q {
                        let y = input[order[w]]
                        if y == y {
                            sum += y
                            seen += 1usize
                        }
                        w += 1usize
                    }
                    if seen == spec.size {
                        if spec.function == WINDOW_ROLLSUM { out = sum } else { out = sum / f64(spec.size) }
                    }
                }
            }
            result[at_row] = out
            q += 1usize
        }
        start = end
    }
    // Rebuild the rows with the new column.
    let existing = column_index(names, spec.output)
    var width = names.len
    if existing == names.len { width += 1usize }
    let (all, ae) = mem.alloc[str](a, width + 1usize)
    if ae != ok { ret (zero, ae) }
    i = 0usize
    while i < names.len {
        all[i] = names[i]
        i += 1usize
    }
    if existing == names.len { all[names.len] = spec.output }
    let (out_rows, ore) = mem.alloc[view.Row](a, n + 1usize)
    if ore != ok { ret (zero, ore) }
    let (values, ve) = mem.alloc[f.Value](a, width + 1usize)
    if ve != ok { ret (zero, ve) }
    var r = 0usize
    while r < n {
        i = 0usize
        while i < names.len {
            values[i] = cell_value(rows[r], names[i])
            i += 1usize
        }
        var made = f.blank()
        if result[r] == result[r] { made = f.number(result[r]) }
        if existing == names.len { values[names.len] = made } else { values[existing] = made }
        let (row, mre) = make_row(a, all[..width], values[..width])
        if mre != ok { ret (zero, mre) }
        out_rows[r] = row
        r += 1usize
    }
    ret (out_rows[..n], ok)
}

// --- missing values --------------------------------------------------------------------------------------------

// tidyr `drop_na`: rows with a missing value in any of `columns` (every column
// when empty) are dropped.
fn drop_na(a: *mem.Arena, rows: []const view.Row, columns: []const str) -> ([]view.Row, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (zero, ne) }
    var k = 0usize
    while k < columns.len {
        if !has_column(names, columns[k]) { ret (zero, Missing) }
        k += 1usize
    }
    let (out, oe) = mem.alloc[view.Row](a, rows.len + 1usize)
    if oe != ok { ret (zero, oe) }
    var count = 0usize
    var i = 0usize
    while i < rows.len {
        var drop = false
        if columns.len == 0usize {
            k = 0usize
            while k < names.len {
                if is_missing(cell_value(rows[i], names[k])) { drop = true }
                k += 1usize
            }
        } else {
            k = 0usize
            while k < columns.len {
                if is_missing(cell_value(rows[i], columns[k])) { drop = true }
                k += 1usize
            }
        }
        if !drop {
            out[count] = rows[i]
            count += 1usize
        }
        i += 1usize
    }
    ret (out[..count], ok)
}

// Rows with `column`'s missing values replaced by `value` (tidyr `replace_na`).
fn replace_na(a: *mem.Arena, rows: []const view.Row, column: str, value: f.Value) -> ([]view.Row, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (zero, ne) }
    let at_column = column_index(names, column)
    if at_column == names.len { ret (zero, Missing) }
    let (out, oe) = mem.alloc[view.Row](a, rows.len + 1usize)
    if oe != ok { ret (zero, oe) }
    let (values, ve) = mem.alloc[f.Value](a, names.len + 1usize)
    if ve != ok { ret (zero, ve) }
    var r = 0usize
    while r < rows.len {
        var i = 0usize
        while i < names.len {
            values[i] = cell_value(rows[r], names[i])
            i += 1usize
        }
        if is_missing(values[at_column]) { values[at_column] = value }
        let (row, re) = make_row(a, names, values[..names.len])
        if re != ok { ret (zero, re) }
        out[r] = row
        r += 1usize
    }
    ret (out[..rows.len], ok)
}

// tidyr `fill`: each missing value in `columns` takes the previous (`FILL_DOWN`)
// or next (`FILL_UP`) non-missing value of the same column within its
// `partition`, in row order.
fn fill(a: *mem.Arena, rows: []const view.Row, columns: []const str, partition: []const str, direction: u8) -> ([]view.Row, err) {
    let (names, ne) = column_names(a, rows)
    if ne != ok { ret (zero, ne) }
    let n = rows.len
    var k = 0usize
    while k < columns.len {
        if !has_column(names, columns[k]) { ret (zero, Missing) }
        k += 1usize
    }
    let (part, parts, pe) = group_ids(a, rows, partition)
    if pe != ok { ret (zero, pe) }
    let (cells, ce) = mem.alloc[f.Value](a, n * names.len + 1usize)
    if ce != ok { ret (zero, ce) }
    var r = 0usize
    while r < n {
        var i = 0usize
        while i < names.len {
            cells[r * names.len + i] = cell_value(rows[r], names[i])
            i += 1usize
        }
        r += 1usize
    }
    let (last, le) = mem.alloc[f.Value](a, parts + 1usize)
    if le != ok { ret (zero, le) }
    let (has_last, he) = mem.alloc[bool](a, parts + 1usize)
    if he != ok { ret (zero, he) }
    k = 0usize
    while k < columns.len {
        let c = column_index(names, columns[k])
        var g = 0usize
        while g < parts {
            has_last[g] = false
            g += 1usize
        }
        var step = 0usize
        while step < n {
            r = step
            if direction == FILL_UP { r = n - 1usize - step }
            let v = cells[r * names.len + c]
            if is_missing(v) {
                if has_last[part[r]] { cells[r * names.len + c] = last[part[r]] }
            } else {
                last[part[r]] = v
                has_last[part[r]] = true
            }
            step += 1usize
        }
        k += 1usize
    }
    let (out, oe) = mem.alloc[view.Row](a, n + 1usize)
    if oe != ok { ret (zero, oe) }
    r = 0usize
    while r < n {
        let (row, re) = make_row(a, names, cells[r * names.len..r * names.len + names.len])
        if re != ok { ret (zero, re) }
        out[r] = row
        r += 1usize
    }
    ret (out[..n], ok)
}
