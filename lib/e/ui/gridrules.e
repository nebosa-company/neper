// Conditional formatting rules of the data grid (docs/grid.md 5.5, the rules of
// `dxSpreadSheetConditionalFormattingRules` the grid reuses): a rule says which cells of a
// column it applies to and how they look; `format` answers the look of one cell.
//
// Kinds: `CellIs` (a number against one or two bounds, or text equal to the rule's text),
// `Text` (contains / begins / ends with), `Blank`, `Above` / `Below` the column's average,
// `Top` / `Bottom` N (or N percent) with ties kept, `Duplicate` / `Unique` values, a two- or
// three-colour `Scale`, a data `Bar` and an `Icons` set of up to five buckets.
//
// A cell takes, field by field, the first rule (in the order added) that sets the field, so
// the order is the priority. A rule marked `whole_row` is evaluated on its column but
// formats every cell of the row. Statistics (average, thresholds, minima, duplicate counts)
// are computed over the live rows of the table by `refresh`, which does nothing for a rule
// whose column has not changed since; the grid asks `format` per visible cell, O(rules).
// Text rules over a dictionary column are decided once per distinct entry.
//
// ponytail: statistics are over every live row, not the filtered view (DevExpress agrees).

use e.mem
use e.algo.sort
use e.data.table as table
use e.gfx.paint
use e.ui.style

type Kind = enum u8 { CellIs, Text, Blank, Above, Below, Top, Bottom, Duplicate, Unique, Scale, Bar, Icons }
type Op = enum u8 { Eq, Ne, Lt, Le, Gt, Ge, Between, Contains, Begins, Ends }

type Rule = struct {
    column: usize,
    kind: Kind,
    op: Op,
    a: f64,
    b: f64,
    text: str,
    fold: bool,
    count: usize,
    percent: bool,
    ink: style.ColorRole,
    has_ink: bool,
    fill: paint.Color,
    has_fill: bool,
    bold: bool,
    whole_row: bool,
    low: paint.Color,
    mid: paint.Color,
    high: paint.Color,
    three: bool,
    buckets: u8,
    bar_only: bool,
    stop: bool
}

// The look of one cell. `bar` is the filled fraction 0..1 of a data bar (0 for none); `icon`
// is 1..buckets for an icon set (0 for none).
type Format = struct {
    has_ink: bool,
    ink: style.ColorRole,
    has_fill: bool,
    fill: paint.Color,
    bold: bool,
    has_bar: bool,
    bar_only: bool,
    bar: f32,
    bar_color: paint.Color,
    icon: u8,
    buckets: u8
}

type Stat = struct {
    built: u64,
    structure: u64,
    ready: bool,
    low: f64,
    high: f64,
    average: f64,
    threshold: f64,
    sorted: []f64,
    sorted_len: usize,
    entries: []u32
}

type Rules = struct {
    t: *const table.Table,
    rules: []Rule,
    stats: []Stat,
    total: usize
}

error TooMany
error BadColumn
error BadRule

fn rule(column: usize, kind: Kind) -> Rule {
    let none = paint.rgba(0.0, 0.0, 0.0, 0.0)
    ret Rule { column: column, kind: kind, op: Op.Eq, a: 0.0, b: 0.0, text: "", fold: true, count: 10usize, percent: false, ink: .Text, has_ink: false, fill: none, has_fill: false, bold: false, whole_row: false, low: none, mid: none, high: none, three: false, buckets: 3u8, bar_only: false, stop: false }
}

fn create(a: *mem.Arena, t: *const table.Table, capacity: usize) -> (Rules, err) {
    let (rules, rules_error) = mem.alloc[Rule](a, capacity)
    if rules_error != ok { ret (zero, rules_error) }
    let (stats, stats_error) = mem.alloc[Stat](a, capacity)
    if stats_error != ok { ret (zero, stats_error) }
    ret (Rules { t: t, rules: rules, stats: stats, total: 0usize }, ok)
}

fn count(rs: *const Rules) -> usize { ret rs.total }

fn is_numeric(k: table.Kind) -> bool {
    ret k == table.Kind.I32 || k == table.Kind.I64 || k == table.Kind.F64 || k == table.Kind.Bool
}

fn is_text(k: table.Kind) -> bool { ret k == table.Kind.Str || k == table.Kind.Dict }

fn number(t: *const table.Table, column: usize, kind: table.Kind, row: usize) -> f64 {
    if kind == table.Kind.I32 { ret f64(table.get_i32(t, column, row)) }
    if kind == table.Kind.I64 { ret f64(table.get_i64(t, column, row)) }
    if kind == table.Kind.F64 { ret table.get_f64(t, column, row) }
    if table.get_bool(t, column, row) { ret 1.0f64 }
    ret 0.0f64
}

fn fold_byte(b: u8) -> u8 {
    if b >= 97u8 && b <= 122u8 { ret b - 32u8 }
    ret b
}

fn same_at(s: str, at: usize, needle: str, fold: bool) -> bool {
    var i = 0usize
    while i < needle.len {
        var x = s[at + i]
        var y = needle[i]
        if fold {
            x = fold_byte(x)
            y = fold_byte(y)
        }
        if x != y { ret false }
        i += 1usize
    }
    ret true
}

// Does `s` equal / contain / begin / end with `needle` (the rule's op).
fn text_hit(s: str, needle: str, op: Op, fold: bool) -> bool {
    if op == Op.Eq { ret s.len == needle.len && same_at(s, 0usize, needle, fold) }
    if op == Op.Ne { ret !(s.len == needle.len && same_at(s, 0usize, needle, fold)) }
    if needle.len > s.len { ret false }
    if op == Op.Begins { ret same_at(s, 0usize, needle, fold) }
    if op == Op.Ends { ret same_at(s, s.len - needle.len, needle, fold) }
    var at = 0usize
    while at + needle.len <= s.len {
        if same_at(s, at, needle, fold) { ret true }
        at += 1usize
    }
    ret false
}

fn number_hit(v: f64, op: Op, a: f64, b: f64) -> bool {
    if op == Op.Eq { ret v == a }
    if op == Op.Ne { ret v != a }
    if op == Op.Lt { ret v < a }
    if op == Op.Le { ret v <= a }
    if op == Op.Gt { ret v > a }
    if op == Op.Ge { ret v >= a }
    if op == Op.Between {
        var lo = a
        var hi = b
        if lo > hi {
            lo = b
            hi = a
        }
        ret v >= lo && v <= hi
    }
    ret false
}

// First index of `sorted[..n]` whose value is >= v (lower bound) or > v (upper bound).
fn bound(sorted: []const f64, n: usize, v: f64, upper: bool) -> usize {
    var lo = 0usize
    var hi = n
    while lo < hi {
        let mid = (lo + hi) >> 1usize
        let x = sorted[mid]
        var go_right = x < v
        if upper { go_right = x <= v }
        if go_right { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

type Order = struct { unused: u8 }

fn by_value(c: *Order, x: f64, y: f64) -> i32 {
    if x < y { ret -1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn needs_sorted(k: Kind) -> bool { ret k == Kind.Duplicate || k == Kind.Unique }

// Adds a rule at the lowest priority; the answer is its index.
fn add(a: *mem.Arena, rs: *Rules, r: Rule) -> (usize, err) {
    if rs.total >= rs.rules.len { ret (0usize, TooMany) }
    let t = rs.t
    if r.column >= table.column_count(t) { ret (0usize, BadColumn) }
    let kind = table.column_kind(t, r.column)
    var ok_kind = true
    if r.kind == Kind.CellIs {
        if is_text(kind) { ok_kind = r.op == Op.Eq || r.op == Op.Ne } else { ok_kind = r.op != Op.Contains && r.op != Op.Begins && r.op != Op.Ends }
    }
    if r.kind == Kind.Text { ok_kind = is_text(kind) && (r.op == Op.Contains || r.op == Op.Begins || r.op == Op.Ends) }
    if r.kind == Kind.Above || r.kind == Kind.Below || r.kind == Kind.Top || r.kind == Kind.Bottom || r.kind == Kind.Scale || r.kind == Kind.Bar || r.kind == Kind.Icons { ok_kind = is_numeric(kind) && kind != table.Kind.Bool }
    if r.kind == Kind.Duplicate || r.kind == Kind.Unique { ok_kind = is_numeric(kind) || kind == table.Kind.Dict }
    if !ok_kind { ret (0usize, BadRule) }
    if r.kind == Kind.Icons && (r.buckets < 2u8 || r.buckets > 5u8) { ret (0usize, BadRule) }
    var stat: Stat = zero
    if needs_sorted(r.kind) && is_numeric(kind) {
        let (sorted, sorted_error) = mem.alloc[f64](a, table.capacity(t))
        if sorted_error != ok { ret (0usize, sorted_error) }
        stat.sorted = sorted
    }
    if kind == table.Kind.Dict && (needs_sorted(r.kind) || r.kind == Kind.Text || r.kind == Kind.CellIs) {
        let (entries, entries_error) = mem.alloc[u32](a, table.dict_capacity(t, r.column))
        if entries_error != ok { ret (0usize, entries_error) }
        stat.entries = entries
    }
    let at = rs.total
    rs.rules[at] = r
    rs.stats[at] = stat
    rs.total += 1usize
    ret (at, ok)
}

fn remove_all(rs: *Rules) { rs.total = 0usize }

// Takes rule `at` out; the rules after it move up (statistics with them).
fn remove(rs: *Rules, at: usize) {
    if at >= rs.total { ret }
    var i = at
    while i + 1usize < rs.total {
        rs.rules[i] = rs.rules[i + 1usize]
        rs.stats[i] = rs.stats[i + 1usize]
        i += 1usize
    }
    rs.total -= 1usize
}

// Exchanges two rules (their order is the order they are applied in).
fn swap(rs: *Rules, x: usize, y: usize) {
    if x >= rs.total || y >= rs.total { ret }
    let r = rs.rules[x]
    rs.rules[x] = rs.rules[y]
    rs.rules[y] = r
    let st = rs.stats[x]
    rs.stats[x] = rs.stats[y]
    rs.stats[y] = st
}

// Recomputes the statistics of the rules whose column (or row set) changed.
fn refresh(rs: *Rules, scratch: *mem.Arena) -> err {
    let t = rs.t
    var i = 0usize
    while i < rs.total {
        let r = rs.rules[i]
        let version = table.column_version(t, r.column)
        let structure = table.structure_version(t)
        let s = &rs.stats[i]
        if !s.ready || s.built != version || s.structure != structure {
            try build_stat(rs, scratch, i)
            s.built = version
            s.structure = structure
            s.ready = true
        }
        i += 1usize
    }
    ret ok
}

fn build_stat(rs: *Rules, scratch: *mem.Arena, index: usize) -> err {
    let t = rs.t
    let r = rs.rules[index]
    let s = &rs.stats[index]
    let kind = table.column_kind(t, r.column)
    let rows = table.row_count(t)
    if kind == table.Kind.Dict && s.entries.len != 0usize {
        let n = table.dict_len(t, r.column)
        var id = 0usize
        while id < n {
            var verdict = 0u32
            let text = table.dict_str(t, r.column, u32(id))
            if r.kind == Kind.Text || r.kind == Kind.CellIs {
                if text_hit(text, r.text, r.op, r.fold) { verdict = 1u32 }
            }
            s.entries[id] = verdict
            id += 1usize
        }
        if needs_sorted(r.kind) {
            id = 0usize
            while id < n {
                s.entries[id] = 0u32
                id += 1usize
            }
            var row = 0usize
            while row < rows {
                if table.is_live(t, row) && !table.is_null(t, r.column, row) { s.entries[usize(table.dict_id(t, r.column, row))] += 1u32 }
                row += 1usize
            }
        }
        ret ok
    }
    if !is_numeric(kind) { ret ok }
    // numeric statistics over the live, non-null rows
    var live = 0usize
    var sum = 0.0f64
    var low = 0.0f64
    var high = 0.0f64
    var row = 0usize
    while row < rows {
        if table.is_live(t, row) && !table.is_null(t, r.column, row) {
            let v = number(t, r.column, kind, row)
            if live == 0usize {
                low = v
                high = v
            }
            if v < low { low = v }
            if v > high { high = v }
            sum += v
            live += 1usize
        }
        row += 1usize
    }
    s.low = low
    s.high = high
    s.average = 0.0f64
    if live != 0usize { s.average = sum / f64(live) }
    let want_sorted = needs_sorted(r.kind) || r.kind == Kind.Top || r.kind == Kind.Bottom
    if !want_sorted { ret ok }
    let marker = mem.mark(scratch)
    var values: []f64 = s.sorted
    if s.sorted.len == 0usize {
        let (spare, spare_error) = mem.alloc[f64](scratch, live + 1usize)
        if spare_error != ok { ret spare_error }
        values = spare
    }
    var n = 0usize
    row = 0usize
    while row < rows {
        if table.is_live(t, row) && !table.is_null(t, r.column, row) {
            values[n] = number(t, r.column, kind, row)
            n += 1usize
        }
        row += 1usize
    }
    var by: Order = Order { unused: 0u8 }
    sort.in_place_by[f64, Order](values[0usize..n], &by, by_value)
    s.sorted_len = n
    if r.kind == Kind.Top || r.kind == Kind.Bottom {
        var take = r.count
        if r.percent { take = (n * r.count + 99usize) / 100usize }
        if take < 1usize { take = 1usize }
        if take > n { take = n }
        if n != 0usize {
            if r.kind == Kind.Top { s.threshold = values[n - take] } else { s.threshold = values[take - 1usize] }
        }
    }
    mem.reset(scratch, marker)
    ret ok
}

fn merge_ink(f: *Format, r: *const Rule) {
    if r.has_ink && !f.has_ink {
        f.has_ink = true
        f.ink = r.ink
    }
    if r.has_fill && !f.has_fill {
        f.has_fill = true
        f.fill = r.fill
    }
    if r.bold { f.bold = true }
}

fn lerp(x: paint.Color, y: paint.Color, t: f32) -> paint.Color {
    ret paint.rgba(x.red + (y.red - x.red) * t, x.green + (y.green - x.green) * t, x.blue + (y.blue - x.blue) * t, x.alpha + (y.alpha - x.alpha) * t)
}

// Does rule `i` hold for the row's cell of its column?
fn holds(rs: *const Rules, i: usize, row: usize) -> bool {
    let t = rs.t
    let r = &rs.rules[i]
    let s = &rs.stats[i]
    let kind = table.column_kind(t, r.column)
    let null = table.is_null(t, r.column, row)
    if r.kind == Kind.Blank { ret null }
    if null { ret false }
    if is_text(kind) && (r.kind == Kind.Text || r.kind == Kind.CellIs) {
        if kind == table.Kind.Dict && s.entries.len != 0usize { ret s.entries[usize(table.dict_id(t, r.column, row))] == 1u32 }
        ret text_hit(table.get_str(t, r.column, row), r.text, r.op, r.fold)
    }
    if kind == table.Kind.Dict && needs_sorted(r.kind) {
        let c = s.entries[usize(table.dict_id(t, r.column, row))]
        if r.kind == Kind.Duplicate { ret c > 1u32 }
        ret c == 1u32
    }
    if !is_numeric(kind) { ret false }
    let v = number(t, r.column, kind, row)
    if r.kind == Kind.CellIs { ret number_hit(v, r.op, r.a, r.b) }
    if r.kind == Kind.Above { ret v > s.average }
    if r.kind == Kind.Below { ret v < s.average }
    if r.kind == Kind.Top { ret s.sorted_len != 0usize && v >= s.threshold }
    if r.kind == Kind.Bottom { ret s.sorted_len != 0usize && v <= s.threshold }
    if needs_sorted(r.kind) {
        let n = bound(s.sorted, s.sorted_len, v, true) - bound(s.sorted, s.sorted_len, v, false)
        if r.kind == Kind.Duplicate { ret n > 1usize }
        ret n == 1usize
    }
    ret true
}

// The look of the cell of `column` in storage `row`. Call `refresh` after the table changes.
fn format(rs: *const Rules, row: usize, column: usize) -> Format {
    var f: Format = zero
    var i = 0usize
    while i < rs.total {
        let r = &rs.rules[i]
        if r.column == column || r.whole_row {
            if holds(rs, i, row) {
                if r.kind == Kind.Scale || r.kind == Kind.Bar || r.kind == Kind.Icons {
                    apply_range(rs, i, row, &f)
                } else {
                    merge_ink(&f, r)
                }
                // Stop If True (v3): the rules after this one are not applied to the cell
                if r.stop { break }
            }
        }
        i += 1usize
    }
    ret f
}

fn apply_range(rs: *const Rules, i: usize, row: usize, f: *Format) {
    let t = rs.t
    let r = &rs.rules[i]
    let s = &rs.stats[i]
    let v = number(t, r.column, table.column_kind(t, r.column), row)
    var x = 1.0f32
    if s.high > s.low { x = f32((v - s.low) / (s.high - s.low)) }
    if r.kind == Kind.Scale {
        if f.has_fill { ret }
        var c = lerp(r.low, r.high, x)
        if r.three {
            if x < 0.5f32 { c = lerp(r.low, r.mid, x * 2.0f32) } else { c = lerp(r.mid, r.high, (x - 0.5f32) * 2.0f32) }
        }
        f.has_fill = true
        f.fill = c
        ret
    }
    if r.kind == Kind.Bar {
        if f.has_bar { ret }
        f.has_bar = true
        f.bar_only = r.bar_only
        f.bar = x
        f.bar_color = r.fill
        ret
    }
    if f.icon != 0u8 { ret }
    var bucket = u8(x * f32(r.buckets)) + 1u8
    if bucket > r.buckets { bucket = r.buckets }
    f.icon = bucket
    f.buckets = r.buckets
}
