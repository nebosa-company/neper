// The view query pipeline (L032), after appdor's `src/views/query.js`, `src/grid/{filter-tree,multi-sort}.js` and the
// bucket identity of `src/charts/buckets.js`: nested AND/OR filters over field-type operator tables (text, number,
// select, multiselect, checkbox, date with relative operands, user, bucket and formula conditions), a stable
// multi-level sort with empty cells last and select options in option order, grouping with an explicit "No value"
// group, the summary functions of a grid footer, row coloring, quick search, `apply_view` over a view config, the
// immutable filter-tree edits (add, remove, replace, toggle, prune, count, depth) and the multi-sort level edits.
//
// Records are rows of named `e.algo.formula` values read as JavaScript reads JSON: a missing cell is `undefined`
// (its text is "undefined") and a JSON null is `null`. Text comparison for sorting and grouping is a root-collation
// approximation (see `collate_text`): ASCII punctuation, digits, then letters with case as the last tie-break, with
// Latin-1 accents as a secondary difference; other scripts order by code point after the Latin letters.
//
// Differences from appdor's: an object value (an attachment descriptor) is a record value whose first item is its
// `size`; the formula conditions run through the registry passed in; the clock is `Context.now` (a missing clock is
// the epoch, not the machine's); `move_sort_level` and `append_sort_level` return the new levels and leave the
// view state's sort mode to the caller.

use e.algo.formula as f
use e.math
use e.mem
use e.str
use e.time
use e.text.utf8 as utf8

fn day_ms() -> f64 { ret 86400000.0f64 }

// --- value helpers ---------------------------------------------------------------------------------------------

type Row = struct { fields: []const f.Field }

// A column descriptor: name, type, and for a select its options (in order) and per-option colors.
type FieldDef = struct { name: str, type_name: str, has_options: bool, options: []const f.Value, option_colors: []const f.Field }

fn cell_of(row: Row, name: str) -> (f.Value, bool) {
    var i = 0usize
    while i < row.fields.len {
        if str.eq(row.fields[i].name, name) { ret (row.fields[i].value, true) }
        i += 1usize
    }
    ret (f.blank(), false)
}

// A missing cell is blank for every emptiness test.
fn value_at(row: Row, name: str) -> f.Value {
    let (v, found) = cell_of(row, name)
    ret v
}

fn is_empty(v: f.Value) -> bool {
    if v.kind == .Blank { ret true }
    if v.kind == .Text && v.s.len == 0usize { ret true }
    ret v.kind == .Array && v.items.len == 0usize
}

fn is_nan(x: f64) -> bool { ret x != x }

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn js_space(u: u32) -> bool {
    if u == 32u32 || (u >= 9u32 && u <= 13u32) || u == 160u32 || u == 5760u32 || (u >= 8192u32 && u <= 8202u32) { ret true }
    ret u == 8232u32 || u == 8233u32 || u == 8239u32 || u == 8287u32 || u == 12288u32 || u == 65279u32
}

fn js_trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    var go = true
    while go && from < to {
        var it = utf8.iterator(s[from..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && js_space(scalar) {
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
        if got && js_space(scalar) {
            to = k
        } else {
            go = false
        }
    }
    ret s[from..to]
}

// JavaScript's `String(value)`.
fn js_string(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Text { ret v.s }
    if v.kind == .Number { ret f.number_text(a, v.n) }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "true" }
        ret "false"
    }
    if v.kind == .Blank { ret "null" }
    if v.kind == .Date { ret f.date_js_string(a, v.n) }
    if v.kind == .Array {
        var out = ""
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, ",") }
            if v.items[i].kind != .Blank { out = f.join(a, out, js_string(a, v.items[i])) }
            i += 1usize
        }
        ret out
    }
    ret "[object Object]"
}

// `String(row[name])`: a missing cell is "undefined", a null one "null".
fn cell_string(a: *mem.Arena, row: Row, name: str) -> str {
    let (v, found) = cell_of(row, name)
    if !found { ret "undefined" }
    ret js_string(a, v)
}

// `String(v).toLowerCase()`.
fn lc(a: *mem.Arena, s: str) -> str { ret f.lower_text(a, s) }

// JavaScript's `Number(v)`.
fn js_number(a: *mem.Arena, v: f.Value) -> f64 {
    if v.kind == .Number || v.kind == .Date || v.kind == .Bool { ret v.n }
    if v.kind == .Blank { ret 0.0f64 }
    if v.kind == .Text {
        let t = js_trim(v.s)
        if t.len == 0usize { ret 0.0f64 }
        let (n, good) = f.parse_number_text(t)
        if good { ret n }
        ret f.nan()
    }
    if v.kind == .Array {
        if v.items.len == 0usize { ret 0.0f64 }
        if v.items.len > 1usize { ret f.nan() }
        let one = v.items[0usize]
        if one.kind == .Bool || one.kind == .Date || one.kind == .Record { ret f.nan() }
        ret js_number(a, one)
    }
    ret f.nan()
}

// `toNum`: null for an empty or non-numeric value.
fn to_num(a: *mem.Arena, v: f.Value) -> (f64, bool) {
    if is_empty(v) { ret (0.0f64, false) }
    let n = js_number(a, v)
    if is_nan(n) { ret (0.0f64, false) }
    ret (n, true)
}

// SameValueZero over scalars: arrays and records are equal only to themselves, which a value copy cannot say, so
// they never are.
fn same_value(a: f.Value, b: f.Value) -> bool {
    if a.kind != b.kind { ret false }
    if a.kind == .Blank { ret true }
    if a.kind == .Number || a.kind == .Date {
        if is_nan(a.n) && is_nan(b.n) { ret true }
        ret a.n == b.n
    }
    if a.kind == .Bool { ret a.n == b.n }
    if a.kind == .Text { ret str.eq(a.s, b.s) }
    ret false
}

// `asArray`: an array as is, an empty value none, anything else one element.
fn as_array(a: *mem.Arena, v: f.Value) -> []const f.Value {
    if v.kind == .Array { ret v.items }
    if is_empty(v) { ret f.zero_items() }
    let (cell, e) = mem.alloc[f.Value](a, 1usize)
    if e != ok { ret f.zero_items() }
    cell[0usize] = v
    ret cell[0usize..1usize]
}

fn includes(list: []const f.Value, v: f.Value) -> bool {
    var i = 0usize
    while i < list.len {
        if same_value(list[i], v) { ret true }
        i += 1usize
    }
    ret false
}

// --- dates ------------------------------------------------------------------------------------------------------

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// `YYYY-MM-DD[T ]hh:mm[:ss[.fff]]`: a date-time that names no zone.
fn is_naive_datetime(s: str) -> bool {
    if s.len < 16usize { ret false }
    var i = 0usize
    while i < 4usize {
        if !is_digit(s[i]) { ret false }
        i += 1usize
    }
    if s[4usize] != 45u8 || !is_digit(s[5usize]) || !is_digit(s[6usize]) || s[7usize] != 45u8 || !is_digit(s[8usize]) || !is_digit(s[9usize]) { ret false }
    if s[10usize] != 84u8 && s[10usize] != 32u8 { ret false }
    if !is_digit(s[11usize]) || !is_digit(s[12usize]) || s[13usize] != 58u8 || !is_digit(s[14usize]) || !is_digit(s[15usize]) { ret false }
    if s.len == 16usize { ret true }
    if s[16usize] != 58u8 || s.len < 19usize || !is_digit(s[17usize]) || !is_digit(s[18usize]) { ret false }
    if s.len == 19usize { ret true }
    if s[19usize] != 46u8 || s.len < 21usize { ret false }
    i = 20usize
    while i < s.len {
        if !is_digit(s[i]) { ret false }
        i += 1usize
    }
    ret true
}

// `toDate`: milliseconds since the epoch, or false. A naive date-time is read as UTC.
fn to_date(a: *mem.Arena, v: f.Value) -> (f64, bool) {
    if is_empty(v) { ret (0.0f64, false) }
    if v.kind == .Date {
        if is_nan(v.n) { ret (0.0f64, false) }
        ret (v.n, true)
    }
    if v.kind == .Number || v.kind == .Bool {
        if !is_finite(v.n) || v.n > 8640000000000000.0f64 || v.n < -8640000000000000.0f64 { ret (0.0f64, false) }
        ret (math.trunc[f64](v.n), true)
    }
    var text = js_string(a, v)
    if v.kind == .Text && is_naive_datetime(text) {
        let (out, e) = mem.alloc[u8](a, text.len + 2usize)
        if e != ok { ret (0.0f64, false) }
        var i = 0usize
        while i < text.len {
            out[i] = text[i]
            if i == 10usize { out[i] = 84u8 }
            i += 1usize
        }
        out[text.len] = 90u8
        text = out[0usize..text.len + 1usize]
    }
    let (ms, good) = f.parse_date_text(js_trim(text))
    if !good || is_nan(ms) { ret (0.0f64, false) }
    ret (ms, true)
}

// The UTC midnight of a time.
fn day_start(ms: f64) -> f64 { ret math.floor[f64](ms / day_ms()) * day_ms() }

// A filter operand: a plain value, or a relative date (`today`, `lastNDays` with `days`, ...) or a `start`/`end`
// range given as members.
type Operand = struct {
    present: bool,
    value: f.Value,
    relative: str,
    days: f64,
    has_start: bool,
    start: f.Value,
    has_end: bool,
    end: f.Value,
    is_object: bool,
}

fn plain_operand(v: f.Value) -> Operand {
    ret Operand { present: true, value: v, relative: "", days: 0.0f64, has_start: false, start: f.blank(), has_end: false, end: f.blank(), is_object: false }
}

// The clock and the signed-in user a filter reads.
type Context = struct { now: f64, has_now: bool, user_id: f.Value, has_user: bool, base: f.Context }

fn clock(ctx: *const Context) -> f64 {
    if ctx.has_now { ret ctx.now }
    ret 0.0f64
}

// A date operand resolved to a time, or false.
fn resolve_date(a: *mem.Arena, op: Operand, ctx: *const Context) -> (f64, bool) {
    if op.is_object && op.relative.len > 0usize {
        let now = clock(ctx)
        let base = day_start(now)
        if str.eq(op.relative, "today") { ret (base, true) }
        if str.eq(op.relative, "yesterday") { ret (base - day_ms(), true) }
        if str.eq(op.relative, "tomorrow") { ret (base + day_ms(), true) }
        ret (now, true)
    }
    if op.value.kind == .Text {
        let now = clock(ctx)
        let base = day_start(now)
        if str.eq(op.value.s, "today") { ret (base, true) }
        if str.eq(op.value.s, "yesterday") { ret (base - day_ms(), true) }
        if str.eq(op.value.s, "tomorrow") { ret (base + day_ms(), true) }
    }
    if op.is_object { ret (0.0f64, false) }
    let (parsed, parsed_ok) = to_date(a, op.value)
    ret (parsed, parsed_ok)
}

// `[start, end)` for `within`, or false when the operand names no usable range.
fn resolve_range(a: *mem.Arena, op: Operand, ctx: *const Context) -> (f64, f64, bool) {
    let now = clock(ctx)
    let base = day_start(now)
    if op.is_object {
        if str.eq(op.relative, "today") { ret (base, base + day_ms(), true) }
        if str.eq(op.relative, "yesterday") { ret (base - day_ms(), base, true) }
        if str.eq(op.relative, "tomorrow") { ret (base + day_ms(), base + 2.0f64 * day_ms(), true) }
        if str.eq(op.relative, "lastNDays") { ret (base - op.days * day_ms(), base + day_ms(), true) }
        if str.eq(op.relative, "nextNDays") { ret (base, base + (op.days + 1.0f64) * day_ms(), true) }
        if op.has_start || op.has_end {
            var s = 0.0f64
            var s_ok = false
            var e = 0.0f64
            var e_ok = false
            if op.has_start && op.start.kind != .Blank {
                let (v, good) = to_date(a, op.start)
                s = v
                s_ok = good
            }
            if op.has_end && op.end.kind != .Blank {
                let (v, good) = to_date(a, op.end)
                e = v
                e_ok = good
            }
            let start_given = op.has_start && op.start.kind != .Blank
            let end_given = op.has_end && op.end.kind != .Blank
            if (start_given && !s_ok) || (end_given && !e_ok) { ret (0.0f64, 0.0f64, false) }
            var lo = 0.0f64 - f.infinity()
            var hi = f.infinity()
            if s_ok { lo = s }
            if e_ok { hi = e + day_ms() }
            ret (lo, hi, true)
        }
    }
    let (d, good) = resolve_date(a, op, ctx)
    if !good { ret (0.0f64, 0.0f64, false) }
    ret (day_start(d), day_start(d) + day_ms(), true)
}

// --- bucket identity (charts/buckets.js) -------------------------------------------------------------------------

// The key a group with no x value is filed under: a NUL byte no stored cell can hold.
fn no_value() -> str { ret "\x00no-value" }

fn pad2(a: *mem.Arena, n: i64) -> str {
    if n < 10i64 { ret f.join(a, "0", f.number_text(a, f64(n))) }
    ret f.number_text(a, f64(n))
}

// A bucket: a named date bucket, or a numeric width.
type Bucket = struct { name: str, size: f64, has_size: bool }

fn no_bucket() -> Bucket { ret Bucket { name: "", size: 0.0f64, has_size: false } }

// `bucketKey`: the group key as text, and whether it is the no-value key.
fn bucket_key(a: *mem.Arena, v: f.Value, bucket: Bucket) -> (str, bool) {
    if is_empty(v) { ret (no_value(), true) }
    let named = bucket.name.len > 0usize
    if named && (str.eq(bucket.name, "year") || str.eq(bucket.name, "month") || str.eq(bucket.name, "quarter") || str.eq(bucket.name, "day") || str.eq(bucket.name, "week")) {
        var ms = 0.0f64
        var good = false
        if v.kind == .Number || v.kind == .Bool {
            if is_finite(v.n) && v.n <= 8640000000000000.0f64 && v.n >= -8640000000000000.0f64 {
                ms = math.trunc[f64](v.n)
                good = true
            }
        } else if v.kind == .Date {
            ms = v.n
            good = !is_nan(v.n)
        } else {
            let (t, ok_date) = f.parse_date_text(js_trim(js_string(a, v)))
            ms = t
            good = ok_date && !is_nan(t)
        }
        if !good { ret (no_value(), true) }
        let (y, m, d) = time.civil_from_days(i64(math.floor[f64](ms / day_ms())))
        if str.eq(bucket.name, "year") { ret (f.number_text(a, f64(y)), false) }
        if str.eq(bucket.name, "month") { ret (f.join3(a, f.number_text(a, f64(y)), "-", pad2(a, m)), false) }
        if str.eq(bucket.name, "quarter") { ret (f.join3(a, f.number_text(a, f64(y)), "-Q", f.number_text(a, f64((m - 1i64) / 3i64 + 1i64))), false) }
        if str.eq(bucket.name, "day") {
            let iso = f.date_iso(a, ms)
            if iso.len >= 10usize { ret (iso[0usize..10usize], false) }
            ret (iso, false)
        }
        let start = f64(time.days_from_civil(y, 1i64, 1i64)) * day_ms()
        let week = math.floor[f64]((ms - start) / (7.0f64 * day_ms())) + 1.0f64
        ret (f.join3(a, f.number_text(a, f64(y)), "-W", pad2(a, i64(week))), false)
    }
    if bucket.has_size && bucket.size != 0.0f64 {
        let n = js_number(a, v)
        if is_nan(n) { ret (no_value(), true) }
        let lo = math.floor[f64](n / bucket.size) * bucket.size
        ret (f.join(a, f.join(a, f.number_text(a, lo), "\xe2\x80\x93"), f.number_text(a, lo + bucket.size)), false)
    }
    ret (js_string(a, v), false)
}

// --- filter nodes ---------------------------------------------------------------------------------------------------

// A filter tree node: a group (`operator` `and` or `or`, with `children`) or a condition. A condition names a
// `field` and an operator `op` over `type_name` (empty: the field's own), and carries an `operand`; `expr` is a
// formula condition; a bucket condition has `bucket`, `values` and its operand in `operand`.
type Node = struct {
    operator: str,
    children: []const Node,
    field: str,
    op: str,
    type_name: str,
    operand: Operand,
    expr: str,
    bucket: Bucket,
    values: []const f.Value,
    has_values: bool,
}

fn empty_group(operator: str) -> Node {
    var none: []const Node = zero
    var op = "and"
    if str.eq(operator, "or") { op = "or" }
    ret Node { operator: op, children: none, field: "", op: "", type_name: "", operand: plain_operand(f.blank()), expr: "", bucket: no_bucket(), values: f.zero_items(), has_values: false }
}

fn is_group(n: Node) -> bool { ret str.eq(n.operator, "and") || str.eq(n.operator, "or") }

// --- operators ------------------------------------------------------------------------------------------------------

fn truthy(v: f.Value) -> bool {
    if v.kind == .Error { ret false }
    if v.kind == .Bool { ret v.n != 0.0f64 }
    if v.kind == .Blank { ret false }
    if v.kind == .Text { ret v.s.len > 0usize }
    if v.kind == .Number { ret v.n != 0.0f64 }
    if v.kind == .Array { ret v.items.len > 0usize }
    ret true
}

fn same_day(a: *mem.Arena, cell: f.Value, other: f64, has_other: bool) -> bool {
    let (d, good) = to_date(a, cell)
    if !good || !has_other { ret false }
    ret day_start(d) == day_start(other)
}

// `dayStart(a) - dayStart(b)`, NaN when either side is unusable.
fn cmp_day(a: *mem.Arena, cell: f.Value, other: f64, has_other: bool) -> f64 {
    let (d, good) = to_date(a, cell)
    if !good || !has_other { ret f.nan() }
    ret day_start(d) - day_start(other)
}

// Whether `op` is one of the space-separated names in `list`.
fn op_known(list: str, op: str) -> bool {
    if op.len == 0usize { ret false }
    var start = 0usize
    var i = 0usize
    while i <= list.len {
        if i == list.len || list[i] == 32u8 {
            if str.eq(list[start..i], op) { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

// The operators the engine applies to a field of `type_name`, in table order, space separated
// (`filterOperatorsFor`): an unknown type filters with the text operators.
fn operator_list(type_name: str) -> str {
    if str.eq(type_name, "number") || str.eq(type_name, "currency") || str.eq(type_name, "percent") || str.eq(type_name, "rating") { ret "= != < <= > >= isEmpty isNotEmpty" }
    if str.eq(type_name, "select") { ret "is isNot isAnyOf isNoneOf isEmpty isNotEmpty" }
    if str.eq(type_name, "multiselect") { ret "hasAnyOf hasAllOf hasNoneOf isEmpty isNotEmpty" }
    if str.eq(type_name, "checkbox") { ret "isChecked isUnchecked" }
    if str.eq(type_name, "date") || str.eq(type_name, "datetime") { ret "on before after onOrBefore onOrAfter within isEmpty isNotEmpty" }
    if str.eq(type_name, "user") { ret "is isNot isCurrentUser isEmpty isNotEmpty" }
    ret "contains notContains is isNot startsWith endsWith isEmpty isNotEmpty"
}

// --- text collation --------------------------------------------------------------------------------------------

fn punct_order() -> str { ret "_-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$" }

// The primary weight of a character: whitespace, punctuation and symbols in root-collation order, digits, then
// letters (case folded), then everything else by code point. Also the accent (secondary) and case (tertiary) rank.
type Weight = struct { primary: u32, secondary: u32, tertiary: u32 }

fn letter_weight(base: u8, accent: u32, upper: bool) -> Weight {
    var t = 0u32
    if upper { t = 1u32 }
    ret Weight { primary: 2000u32 + u32(base - 97u8) * 4u32, secondary: accent, tertiary: t }
}

// Latin-1 letters as a base letter with an accent rank (0 none).
fn latin1_base(scalar: u32) -> (u8, u32, bool, bool) {
    if scalar >= 192u32 && scalar <= 197u32 { ret (97u8, scalar - 190u32, true, true) }
    if scalar >= 224u32 && scalar <= 229u32 { ret (97u8, scalar - 222u32, false, true) }
    if scalar == 199u32 { ret (99u8, 2u32, true, true) }
    if scalar == 231u32 { ret (99u8, 2u32, false, true) }
    if scalar >= 200u32 && scalar <= 203u32 { ret (101u8, scalar - 198u32, true, true) }
    if scalar >= 232u32 && scalar <= 235u32 { ret (101u8, scalar - 230u32, false, true) }
    if scalar >= 204u32 && scalar <= 207u32 { ret (105u8, scalar - 202u32, true, true) }
    if scalar >= 236u32 && scalar <= 239u32 { ret (105u8, scalar - 234u32, false, true) }
    if scalar == 209u32 { ret (110u8, 4u32, true, true) }
    if scalar == 241u32 { ret (110u8, 4u32, false, true) }
    if scalar >= 210u32 && scalar <= 214u32 { ret (111u8, scalar - 208u32, true, true) }
    if scalar >= 242u32 && scalar <= 246u32 { ret (111u8, scalar - 240u32, false, true) }
    if scalar == 216u32 { ret (111u8, 8u32, true, true) }
    if scalar == 248u32 { ret (111u8, 8u32, false, true) }
    if scalar >= 217u32 && scalar <= 220u32 { ret (117u8, scalar - 215u32, true, true) }
    if scalar >= 249u32 && scalar <= 252u32 { ret (117u8, scalar - 247u32, false, true) }
    if scalar == 221u32 { ret (121u8, 2u32, true, true) }
    if scalar == 253u32 || scalar == 255u32 { ret (121u8, 2u32, false, true) }
    ret (0u8, 0u32, false, false)
}

// The weights of a character (a sharp s is two).
fn char_weights(scalar: u32, out: []Weight) -> usize {
    if scalar < 128u32 {
        let c = u8(scalar)
        if c >= 97u8 && c <= 122u8 {
            out[0usize] = letter_weight(c, 0u32, false)
            ret 1usize
        }
        if c >= 65u8 && c <= 90u8 {
            out[0usize] = letter_weight(c + 32u8, 0u32, true)
            ret 1usize
        }
        if c >= 48u8 && c <= 57u8 {
            out[0usize] = Weight { primary: 1000u32 + u32(c - 48u8), secondary: 0u32, tertiary: 0u32 }
            ret 1usize
        }
        if c == 9u8 || c == 10u8 || c == 11u8 || c == 12u8 || c == 13u8 {
            out[0usize] = Weight { primary: 1u32 + u32(c - 9u8), secondary: 0u32, tertiary: 0u32 }
            ret 1usize
        }
        if c == 32u8 {
            out[0usize] = Weight { primary: 10u32, secondary: 0u32, tertiary: 0u32 }
            ret 1usize
        }
        let order = punct_order()
        var k = 0usize
        while k < order.len {
            if order[k] == c {
                out[0usize] = Weight { primary: 20u32 + u32(k), secondary: 0u32, tertiary: 0u32 }
                ret 1usize
            }
            k += 1usize
        }
        out[0usize] = Weight { primary: 500u32 + scalar, secondary: 0u32, tertiary: 0u32 }
        ret 1usize
    }
    if scalar == 223u32 {
        out[0usize] = letter_weight(115u8, 0u32, false)
        out[1usize] = letter_weight(115u8, 0u32, false)
        out[1usize].tertiary = 2u32
        ret 2usize
    }
    let (base, accent, upper, found) = latin1_base(scalar)
    if found {
        out[0usize] = letter_weight(base, accent, upper)
        ret 1usize
    }
    out[0usize] = Weight { primary: 5000u32 + scalar, secondary: 0u32, tertiary: 0u32 }
    ret 1usize
}

// The root-collation order of two texts: -1, 0 or 1 (`localeCompare`).
fn collate_text(x: str, y: str) -> i32 {
    var left = utf8.iterator(x)
    var right = utf8.iterator(y)
    var secondary = 0i32
    var tertiary = 0i32
    var lw: [2]Weight = zero
    var rw: [2]Weight = zero
    var ln = 0usize
    var rn = 0usize
    var li = 0usize
    var ri = 0usize
    while true {
        if li >= ln {
            let (scalar, got) = utf8.iterator_next(&left)
            if got {
                ln = char_weights(scalar, lw[0..])
                li = 0usize
            } else {
                ln = 0usize
                li = 0usize
            }
        }
        if ri >= rn {
            let (scalar, got) = utf8.iterator_next(&right)
            if got {
                rn = char_weights(scalar, rw[0..])
                ri = 0usize
            } else {
                rn = 0usize
                ri = 0usize
            }
        }
        let left_done = ln == 0usize || li >= ln
        let right_done = rn == 0usize || ri >= rn
        if left_done && right_done { break }
        if left_done { ret -1i32 }
        if right_done { ret 1i32 }
        let l = lw[li]
        let r = rw[ri]
        if l.primary != r.primary {
            if l.primary < r.primary { ret -1i32 }
            ret 1i32
        }
        if secondary == 0i32 && l.secondary != r.secondary {
            if l.secondary < r.secondary { secondary = -1i32 } else { secondary = 1i32 }
        }
        if tertiary == 0i32 && l.tertiary != r.tertiary {
            if l.tertiary < r.tertiary { tertiary = -1i32 } else { tertiary = 1i32 }
        }
        li += 1usize
        ri += 1usize
    }
    if secondary != 0i32 { ret secondary }
    ret tertiary
}

// --- evaluating a filter ----------------------------------------------------------------------------------------

fn find_field(fields: []const FieldDef, name: str) -> (FieldDef, bool) {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) { ret (fields[i], true) }
        i += 1usize
    }
    var none: FieldDef = zero
    ret (none, false)
}

// `a === b` over cells where "missing" is `undefined`.
fn strict_equal(av: f.Value, a_present: bool, bv: f.Value, b_present: bool) -> bool {
    if !a_present || !b_present { ret !a_present && !b_present }
    ret same_value(av, bv) && !(av.kind == .Number && is_nan(av.n))
}

// The truth of one condition against a row.
fn eval_condition(a: *mem.Arena, reg: *const f.Registry, node: Node, row: Row, fields: []const FieldDef, ctx: *const Context) -> bool {
    if node.expr.len > 0usize {
        var fc = ctx.base
        fc.fields = row.fields
        ret truthy(f.evaluate(a, node.expr, &fc, reg))
    }
    let (cell, present) = cell_of(row, node.field)
    if str.eq(node.op, "inBucket") || str.eq(node.op, "notInBuckets") { ret matches_bucket(a, cell, node) }
    let (def, has_def) = find_field(fields, node.field)
    var type_name = node.type_name
    if type_name.len == 0usize {
        if has_def && def.type_name.len > 0usize { type_name = def.type_name } else { type_name = "text" }
    }
    let list = operator_list(type_name)
    if !op_known(list, node.op) { ret false }
    let op = node.op
    let operand = node.operand
    let b = operand.value
    // the checkbox family
    if str.eq(type_name, "checkbox") {
        if str.eq(op, "isChecked") { ret cell.kind == .Bool && cell.n != 0.0f64 }
        ret !(cell.kind == .Bool && cell.n != 0.0f64)
    }
    if str.eq(op, "isEmpty") && !str.eq(type_name, "multiselect") { ret is_empty(cell) }
    if str.eq(op, "isNotEmpty") && !str.eq(type_name, "multiselect") { ret !is_empty(cell) }
    if str.eq(type_name, "number") || str.eq(type_name, "currency") || str.eq(type_name, "percent") || str.eq(type_name, "rating") {
        let (na, a_ok) = to_num(a, cell)
        let (nb, b_ok) = to_num(a, b)
        if str.eq(op, "=") { ret (a_ok == b_ok) && (!a_ok || na == nb) }
        if str.eq(op, "!=") { ret !((a_ok == b_ok) && (!a_ok || na == nb)) }
        var bound = 0.0f64
        if b_ok { bound = nb }
        if !a_ok { ret false }
        if str.eq(op, "<") { ret na < bound }
        if str.eq(op, "<=") { ret na <= bound }
        if str.eq(op, ">") { ret na > bound }
        ret na >= bound
    }
    if str.eq(type_name, "select") {
        if str.eq(op, "is") { ret strict_equal(cell, present, b, operand.present) }
        if str.eq(op, "isNot") { ret !strict_equal(cell, present, b, operand.present) }
        let list_b = as_array(a, b)
        if str.eq(op, "isAnyOf") { ret includes(list_b, cell) }
        ret !includes(list_b, cell)
    }
    if str.eq(type_name, "multiselect") {
        let left = as_array(a, cell)
        let right = as_array(a, b)
        if str.eq(op, "hasAnyOf") {
            var i = 0usize
            while i < left.len {
                if includes(right, left[i]) { ret true }
                i += 1usize
            }
            ret false
        }
        if str.eq(op, "hasAllOf") {
            var i = 0usize
            while i < right.len {
                if !includes(left, right[i]) { ret false }
                i += 1usize
            }
            ret true
        }
        if str.eq(op, "hasNoneOf") {
            var i = 0usize
            while i < left.len {
                if includes(right, left[i]) { ret false }
                i += 1usize
            }
            ret true
        }
        if str.eq(op, "isEmpty") { ret left.len == 0usize }
        ret left.len > 0usize
    }
    if str.eq(type_name, "date") || str.eq(type_name, "datetime") {
        if str.eq(op, "within") {
            let (d, good) = to_date(a, cell)
            if !good { ret false }
            let (lo, hi, has_range) = resolve_range(a, operand, ctx)
            if !has_range { ret false }
            ret d >= lo && d < hi
        }
        let (resolved, has_resolved) = resolve_date(a, operand, ctx)
        if str.eq(op, "on") { ret same_day(a, cell, resolved, has_resolved) }
        let diff = cmp_day(a, cell, resolved, has_resolved)
        if str.eq(op, "before") { ret diff < 0.0f64 }
        if str.eq(op, "after") { ret diff > 0.0f64 }
        if str.eq(op, "onOrBefore") { ret diff <= 0.0f64 }
        ret diff >= 0.0f64
    }
    if str.eq(type_name, "user") {
        if str.eq(op, "is") { ret strict_equal(cell, present, b, operand.present) }
        if str.eq(op, "isNot") { ret !strict_equal(cell, present, b, operand.present) }
        ret strict_equal(cell, present, ctx.user_id, ctx.has_user)
    }
    // text
    var left = "undefined"
    if present { left = js_string(a, cell) }
    var right = "undefined"
    if operand.present { right = js_string(a, b) }
    let l = lc(a, left)
    let r = lc(a, right)
    if str.eq(op, "contains") { ret str.contains(l, r) }
    if str.eq(op, "notContains") { ret !str.contains(l, r) }
    if str.eq(op, "is") { ret str.eq(l, r) }
    if str.eq(op, "isNot") { ret !str.eq(l, r) }
    if str.eq(op, "startsWith") { ret str.starts_with(l, r) }
    ret str.ends_with(l, r)
}

// `matchesBucket`: the cell's bucket against the condition's value or value list.
fn matches_bucket(a: *mem.Arena, cell: f.Value, node: Node) -> bool {
    let (key, is_none) = bucket_key(a, cell, node.bucket)
    if str.eq(node.op, "notInBuckets") {
        var i = 0usize
        while i < node.values.len {
            let v = node.values[i]
            if v.kind == .Text && !is_none && str.eq(v.s, key) { ret false }
            if v.kind == .Blank && is_none { ret false }
            i += 1usize
        }
        ret true
    }
    let want = node.operand.value
    if is_none { ret !node.operand.present || want.kind == .Blank }
    if !node.operand.present || want.kind == .Blank { ret false }
    ret str.eq(js_string(a, want), key)
}

fn eval_tree(a: *mem.Arena, reg: *const f.Registry, node: Node, row: Row, fields: []const FieldDef, ctx: *const Context) -> bool {
    if is_group(node) {
        if node.children.len == 0usize { ret true }
        var i = 0usize
        if str.eq(node.operator, "and") {
            while i < node.children.len {
                if !eval_tree(a, reg, node.children[i], row, fields, ctx) { ret false }
                i += 1usize
            }
            ret true
        }
        while i < node.children.len {
            if eval_tree(a, reg, node.children[i], row, fields, ctx) { ret true }
            i += 1usize
        }
        ret false
    }
    ret eval_condition(a, reg, node, row, fields, ctx)
}

// Whether one row passes a (possibly nested) filter; no filter passes everything.
fn matches_filter(a: *mem.Arena, reg: *const f.Registry, node: Node, has_filter: bool, row: Row, fields: []const FieldDef, ctx: *const Context) -> bool {
    if !has_filter { ret true }
    ret eval_tree(a, reg, node, row, fields, ctx)
}

// The rows passing a filter, in order.
fn filter_rows(a: *mem.Arena, reg: *const f.Registry, rows: []const Row, node: Node, has_filter: bool, fields: []const FieldDef, ctx: *const Context) -> []const Row {
    let (out, e) = mem.alloc[Row](a, rows.len + 1usize)
    if e != ok { ret rows }
    var n = 0usize
    var i = 0usize
    while i < rows.len {
        if matches_filter(a, reg, node, has_filter, rows[i], fields, ctx) {
            out[n] = rows[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- sorting --------------------------------------------------------------------------------------------------

type SortSpec = struct { field: str, direction: str }

fn is_numeric_type(t: str) -> bool { ret str.eq(t, "number") || str.eq(t, "currency") || str.eq(t, "percent") || str.eq(t, "rating") }

// `collate`: the order of two non-empty cells under the field's type (NaN when two unknown select values meet,
// which a sort reads as a tie).
fn collate(a: *mem.Arena, x: f.Value, y: f.Value, def: FieldDef, has_def: bool) -> f64 {
    if has_def && str.eq(def.type_name, "select") && def.has_options {
        var ix = f.infinity()
        var iy = f.infinity()
        var i = 0usize
        var found_x = false
        var found_y = false
        while i < def.options.len {
            if !found_x && same_value(def.options[i], x) {
                ix = f64(i)
                found_x = true
            }
            if !found_y && same_value(def.options[i], y) {
                iy = f64(i)
                found_y = true
            }
            i += 1usize
        }
        ret ix - iy
    }
    if has_def && is_numeric_type(def.type_name) {
        let (nx, x_ok) = to_num(a, x)
        let (ny, y_ok) = to_num(a, y)
        if !x_ok && !y_ok { ret 0.0f64 }
        if !x_ok { ret 1.0f64 }
        if !y_ok { ret -1.0f64 }
        ret nx - ny
    }
    if has_def && (str.eq(def.type_name, "date") || str.eq(def.type_name, "datetime")) {
        let (dx, x_ok) = to_date(a, x)
        let (dy, y_ok) = to_date(a, y)
        if !x_ok && !y_ok { ret 0.0f64 }
        if !x_ok { ret 1.0f64 }
        if !y_ok { ret -1.0f64 }
        ret dx - dy
    }
    if is_empty(x) && is_empty(y) { ret 0.0f64 }
    if is_empty(x) { ret 1.0f64 }
    if is_empty(y) { ret -1.0f64 }
    ret f64(collate_text(js_string(a, x), js_string(a, y)))
}

// A sort job: what the comparator reads.
type SortJob = struct {
    a: *mem.Arena,
    mode: u8,
    rows: []const Row,
    sorts: []const SortSpec,
    fields: []const FieldDef,
    keys: []const f.Value,
    key_none: []const bool,
    def: FieldDef,
    has_def: bool,
    descending: bool,
}

type Compare = fn(*SortJob, usize, usize) -> f64

// The order of rows x and y by the sort levels, ties by position (NaN reads as equal).
fn compare_rows(job: *SortJob, x: usize, y: usize) -> f64 {
    var i = 0usize
    while i < job.sorts.len {
        let s = job.sorts[i]
        i += 1usize
        let va = value_at(job.rows[x], s.field)
        let vb = value_at(job.rows[y], s.field)
        let ea = is_empty(va)
        let eb = is_empty(vb)
        if ea && eb { continue }
        if ea { ret 1.0f64 }
        if eb { ret -1.0f64 }
        let (def, has_def) = find_field(job.fields, s.field)
        var c = collate(job.a, va, vb, def, has_def)
        if str.eq(s.direction, "desc") { c = 0.0f64 - c }
        if c != 0.0f64 { ret c }
    }
    ret f64(x) - f64(y)
}

// The order of two group keys: "No value" last, then the field's collation (reversed for descending).
fn compare_keys(job: *SortJob, x: usize, y: usize) -> f64 {
    if job.key_none[x] { ret 1.0f64 }
    if job.key_none[y] { ret -1.0f64 }
    var c = collate(job.a, job.keys[x], job.keys[y], job.def, job.has_def)
    if job.descending { c = 0.0f64 - c }
    ret c
}

fn order_of(job: *SortJob, cmp: Compare, x: usize, y: usize) -> f64 {
    let c = cmp(job, x, y)
    if c != c { ret 0.0f64 }
    ret c
}

// V8's order for fewer than 64 items (the leading run, reversed when strictly descending, then binary insertion)
// and a stable merge above, which agree for a consistent comparison.
fn sort_small(job: *SortJob, cmp: Compare, order: []usize) {
    let n = order.len
    if n < 2usize { ret }
    var run = 2usize
    let descending = order_of(job, cmp, order[1usize], order[0usize]) < 0.0f64
    var previous = order[1usize]
    var idx = 2usize
    var stop = false
    while idx < n && !stop {
        let current = order[idx]
        let r = order_of(job, cmp, current, previous)
        if descending {
            if r >= 0.0f64 { stop = true }
        } else {
            if r < 0.0f64 { stop = true }
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
            if order_of(job, cmp, pivot, order[mid]) < 0.0f64 {
                right = mid
            } else {
                left = mid + 1usize
            }
        }
        var p = start
        while p > left {
            order[p] = order[p - 1usize]
            p -= 1usize
        }
        order[left] = pivot
        start += 1usize
    }
}

fn merge_sort(job: *SortJob, cmp: Compare, order: []usize, tmp: []usize, lo: usize, hi: usize) {
    if hi - lo < 2usize { ret }
    let mid = lo + (hi - lo) / 2usize
    merge_sort(job, cmp, order, tmp, lo, mid)
    merge_sort(job, cmp, order, tmp, mid, hi)
    var i = lo
    var j = mid
    var k = lo
    while i < mid && j < hi {
        if order_of(job, cmp, order[j], order[i]) < 0.0f64 {
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

fn sorted_order(job: *SortJob, cmp: Compare, n: usize) -> []usize {
    var none: []usize = zero
    if n == 0usize { ret none }
    let (order, e) = mem.alloc[usize](job.a, n)
    if e != ok { ret none }
    var i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    if n < 64usize {
        sort_small(job, cmp, order)
    } else {
        let (tmp, te) = mem.alloc[usize](job.a, n)
        if te == ok { merge_sort(job, cmp, order, tmp, 0usize, n) }
    }
    ret order
}

// Stable multi-level sort; empty cells sort last regardless of direction.
fn sort_rows(a: *mem.Arena, rows: []const Row, sorts: []const SortSpec, fields: []const FieldDef) -> []const Row {
    if sorts.len == 0usize { ret rows }
    var job = SortJob { a: a, mode: 0u8, rows: rows, sorts: sorts, fields: fields, keys: f.zero_items(), key_none: zero, def: zero, has_def: false, descending: false }
    let order = sorted_order(&job, compare_rows, rows.len)
    let (out, e) = mem.alloc[Row](a, rows.len + 1usize)
    if e != ok { ret rows }
    var i = 0usize
    while i < order.len {
        out[i] = rows[order[i]]
        i += 1usize
    }
    ret out[0usize..rows.len]
}

// --- grouping -------------------------------------------------------------------------------------------------------

type Group = struct { value: f.Value, is_none: bool, label: str, rows: []const Row, count: usize }

// Group rows by one field; empty values form an explicit "No value" group, last; groups are ordered by the field's
// collation (descending when asked).
fn group_rows(a: *mem.Arena, rows: []const Row, field: str, direction: str, fields: []const FieldDef) -> []const Group {
    var none: []const Group = zero
    let (keys, ke) = mem.alloc[f.Value](a, rows.len + 1usize)
    let (key_none, ne) = mem.alloc[bool](a, rows.len + 1usize)
    let (member_of, me) = mem.alloc[usize](a, rows.len + 1usize)
    if ke != ok || ne != ok || me != ok { ret none }
    var key_count = 0usize
    var i = 0usize
    while i < rows.len {
        let raw = value_at(rows[i], field)
        var at = key_count
        var found = false
        var k = 0usize
        if is_empty(raw) {
            while k < key_count && !found {
                if key_none[k] {
                    at = k
                    found = true
                }
                k += 1usize
            }
            if !found {
                keys[key_count] = f.blank()
                key_none[key_count] = true
                key_count += 1usize
            }
        } else {
            while k < key_count && !found {
                if !key_none[k] && same_value(keys[k], raw) {
                    at = k
                    found = true
                }
                k += 1usize
            }
            if !found {
                keys[key_count] = raw
                key_none[key_count] = false
                key_count += 1usize
            }
        }
        member_of[i] = at
        i += 1usize
    }
    let (def, has_def) = find_field(fields, field)
    var job = SortJob { a: a, mode: 1u8, rows: rows, sorts: zero, fields: fields, keys: keys[0usize..key_count], key_none: key_none[0usize..key_count], def: def, has_def: has_def, descending: str.eq(direction, "desc") }
    let order = sorted_order(&job, compare_keys, key_count)
    let (groups, ge) = mem.alloc[Group](a, key_count + 1usize)
    if ge != ok { ret none }
    var g = 0usize
    while g < order.len {
        let k = order[g]
        // count then collect, preserving row order
        var count = 0usize
        i = 0usize
        while i < rows.len {
            if member_of[i] == k { count += 1usize }
            i += 1usize
        }
        let (members, mre) = mem.alloc[Row](a, count + 1usize)
        if mre != ok { ret none }
        var n = 0usize
        i = 0usize
        while i < rows.len {
            if member_of[i] == k {
                members[n] = rows[i]
                n += 1usize
            }
            i += 1usize
        }
        var label = "No value"
        var value = f.blank()
        if !key_none[k] {
            label = js_string(a, keys[k])
            value = keys[k]
        }
        groups[g] = Group { value: value, is_none: key_none[k], label: label, rows: members[0usize..n], count: n }
        g += 1usize
    }
    ret groups[0usize..key_count]
}

// --- summaries ------------------------------------------------------------------------------------------------------

// A summary's value: nothing, a number, a date, a per-option distribution or a byte total.
type Summary = struct { kind: u8, n: f64, entries: []const Tally }

type Tally = struct { label: str, count: usize }

fn summary_none() -> Summary {
    var none: []const Tally = zero
    ret Summary { kind: 0u8, n: 0.0f64, entries: none }
}

fn summary_number(n: f64) -> Summary {
    var none: []const Tally = zero
    ret Summary { kind: 1u8, n: n, entries: none }
}

fn summary_date(ms: f64) -> Summary {
    var none: []const Tally = zero
    ret Summary { kind: 2u8, n: ms, entries: none }
}

// `JSON.stringify` of a cell: the identity `unique` counts by.
fn json_key(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Blank { ret "null" }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "true" }
        ret "false"
    }
    if v.kind == .Number {
        if !is_finite(v.n) { ret "null" }
        ret f.number_text(a, v.n)
    }
    if v.kind == .Text {
        var out = "\""
        var i = 0usize
        while i < v.s.len {
            let c = v.s[i]
            if c == 34u8 {
                out = f.join(a, out, "\\\"")
            } else if c == 92u8 {
                out = f.join(a, out, "\\\\")
            } else if c == 10u8 {
                out = f.join(a, out, "\\n")
            } else if c == 13u8 {
                out = f.join(a, out, "\\r")
            } else if c == 9u8 {
                out = f.join(a, out, "\\t")
            } else if c == 8u8 {
                out = f.join(a, out, "\\b")
            } else if c == 12u8 {
                out = f.join(a, out, "\\f")
            } else if c < 32u8 {
                let digit = "0123456789abcdef"
                out = f.join(a, out, f.join3(a, "\\u00", digit[usize(c >> 4u8)..usize(c >> 4u8) + 1usize], digit[usize(c & 15u8)..usize(c & 15u8) + 1usize]))
            } else {
                out = f.join(a, out, v.s[i..i + 1usize])
            }
            i += 1usize
        }
        ret f.join(a, out, "\"")
    }
    if v.kind == .Array {
        var out = "["
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, ",") }
            out = f.join(a, out, json_key(a, v.items[i]))
            i += 1usize
        }
        ret f.join(a, out, "]")
    }
    ret "{}"
}

fn unique_count(a: *mem.Arena, vals: []const f.Value) -> usize {
    let (seen, e) = mem.alloc[str](a, vals.len + 1usize)
    if e != ok { ret 0usize }
    var n = 0usize
    var i = 0usize
    while i < vals.len {
        if !is_empty(vals[i]) {
            let key = json_key(a, vals[i])
            var found = false
            var k = 0usize
            while k < n {
                if str.eq(seen[k], key) { found = true }
                k += 1usize
            }
            if !found {
                seen[n] = key
                n += 1usize
            }
        }
        i += 1usize
    }
    ret n
}

fn filled_count(vals: []const f.Value) -> usize {
    var n = 0usize
    var i = 0usize
    while i < vals.len {
        if !is_empty(vals[i]) { n += 1usize }
        i += 1usize
    }
    ret n
}

// The numeric values of a column, empties and non-numbers dropped.
fn nums_of(a: *mem.Arena, vals: []const f.Value, out: []f64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < vals.len {
        let (v, good) = to_num(a, vals[i])
        if good {
            out[n] = v
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// Whether a cell reads as a date for min and max: a date value, or text starting `YYYY-MM-DD` or holding `d/d`.
fn is_date_like(v: f.Value) -> bool {
    if v.kind == .Date { ret true }
    if v.kind != .Text { ret false }
    let s = v.s
    if s.len >= 10usize && is_digit(s[0usize]) && is_digit(s[1usize]) && is_digit(s[2usize]) && is_digit(s[3usize]) && s[4usize] == 45u8 && is_digit(s[5usize]) && is_digit(s[6usize]) && s[7usize] == 45u8 && is_digit(s[8usize]) && is_digit(s[9usize]) { ret true }
    var i = 1usize
    while i + 1usize < s.len {
        if s[i] == 47u8 && is_digit(s[i - 1usize]) && is_digit(s[i + 1usize]) { ret true }
        i += 1usize
    }
    ret false
}

// `minMax`: a date (kind 2) when every non-empty value is date-like, else a number (kind 1), else nothing.
fn min_max(a: *mem.Arena, vals: []const f.Value, want_min: bool) -> Summary {
    var non_empty = 0usize
    var all_dates = true
    var i = 0usize
    while i < vals.len {
        if !is_empty(vals[i]) {
            non_empty += 1usize
            if !is_date_like(vals[i]) { all_dates = false }
        }
        i += 1usize
    }
    if non_empty > 0usize && all_dates {
        var have = false
        var best = 0.0f64
        i = 0usize
        while i < vals.len {
            if !is_empty(vals[i]) {
                let (t, good) = to_date(a, vals[i])
                if good {
                    if !have || (want_min && t < best) || (!want_min && t > best) { best = t }
                    have = true
                }
            }
            i += 1usize
        }
        if !have { ret summary_none() }
        ret summary_date(best)
    }
    let (buffer, e) = mem.alloc[f64](a, vals.len + 1usize)
    if e != ok { ret summary_none() }
    let n = nums_of(a, vals, buffer)
    if n == 0usize { ret summary_none() }
    var best = buffer[0usize]
    i = 1usize
    while i < n {
        if (want_min && buffer[i] < best) || (!want_min && buffer[i] > best) { best = buffer[i] }
        i += 1usize
    }
    ret summary_number(best)
}

fn is_checked(v: f.Value) -> bool {
    if v.kind == .Bool { ret v.n != 0.0f64 }
    if v.kind == .Text { ret str.eq(v.s, "true") || str.eq(v.s, "1") }
    if v.kind == .Number { ret v.n == 1.0f64 }
    ret false
}

fn month_ms() -> f64 { ret 30.436875f64 * 86400000.0f64 }

// One summary function over a column's values (`none`, `count`, `filled`, ... `distribution`, `totalSize`). An
// unknown function is no summary. An attachment's `size` is the first item of its record value.
fn summarize_values(a: *mem.Arena, vals: []const f.Value, name: str) -> Summary {
    let total = f64(vals.len)
    if str.eq(name, "none") { ret summary_none() }
    if str.eq(name, "count") { ret summary_number(total) }
    if str.eq(name, "filled") { ret summary_number(f64(filled_count(vals))) }
    if str.eq(name, "empty") { ret summary_number(total - f64(filled_count(vals))) }
    if str.eq(name, "unique") { ret summary_number(f64(unique_count(a, vals))) }
    if str.eq(name, "percentFilled") {
        if vals.len == 0usize { ret summary_number(0.0f64) }
        ret summary_number(f64(filled_count(vals)) / total * 100.0f64)
    }
    if str.eq(name, "percentEmpty") {
        if vals.len == 0usize { ret summary_number(0.0f64) }
        ret summary_number((total - f64(filled_count(vals))) / total * 100.0f64)
    }
    if str.eq(name, "percentUnique") {
        if vals.len == 0usize { ret summary_number(0.0f64) }
        ret summary_number(f64(unique_count(a, vals)) / total * 100.0f64)
    }
    if str.eq(name, "checked") || str.eq(name, "unchecked") || str.eq(name, "percentChecked") || str.eq(name, "percentUnchecked") {
        var checked = 0usize
        var i = 0usize
        while i < vals.len {
            if is_checked(vals[i]) { checked += 1usize }
            i += 1usize
        }
        if str.eq(name, "checked") { ret summary_number(f64(checked)) }
        if str.eq(name, "unchecked") { ret summary_number(total - f64(checked)) }
        if vals.len == 0usize { ret summary_number(0.0f64) }
        if str.eq(name, "percentChecked") { ret summary_number(f64(checked) / total * 100.0f64) }
        ret summary_number((total - f64(checked)) / total * 100.0f64)
    }
    if str.eq(name, "min") || str.eq(name, "earliest") { ret min_max(a, vals, true) }
    if str.eq(name, "max") || str.eq(name, "latest") { ret min_max(a, vals, false) }
    if str.eq(name, "range") {
        let lo = min_max(a, vals, true)
        let hi = min_max(a, vals, false)
        if lo.kind == 0u8 || hi.kind == 0u8 { ret summary_none() }
        if lo.kind == 2u8 && hi.kind == 2u8 { ret summary_number((hi.n - lo.n) / day_ms()) }
        ret summary_number(hi.n - lo.n)
    }
    if str.eq(name, "rangeDays") || str.eq(name, "rangeMonths") {
        let lo = min_max(a, vals, true)
        let hi = min_max(a, vals, false)
        if lo.kind != 2u8 || hi.kind != 2u8 { ret summary_none() }
        if str.eq(name, "rangeDays") { ret summary_number((hi.n - lo.n) / day_ms()) }
        ret summary_number((hi.n - lo.n) / month_ms())
    }
    if str.eq(name, "distribution") {
        let (labels, le) = mem.alloc[str](a, vals.len * 4usize + 4usize)
        let (counts, ce) = mem.alloc[usize](a, vals.len * 4usize + 4usize)
        if le != ok || ce != ok { ret summary_none() }
        var n = 0usize
        var i = 0usize
        while i < vals.len {
            let v = vals[i]
            i += 1usize
            if is_empty(v) { continue }
            var items: []const f.Value = zero
            var single: [1]f.Value = zero
            if v.kind == .Array {
                items = v.items
            } else {
                single[0usize] = v
                items = single[0..]
            }
            var k = 0usize
            while k < items.len {
                if !is_empty(items[k]) {
                    let label = js_string(a, items[k])
                    var found = false
                    var m = 0usize
                    while m < n {
                        if str.eq(labels[m], label) {
                            counts[m] += 1usize
                            found = true
                        }
                        m += 1usize
                    }
                    if !found && n < labels.len {
                        labels[n] = label
                        counts[n] = 1usize
                        n += 1usize
                    }
                }
                k += 1usize
            }
        }
        if n == 0usize { ret summary_none() }
        let (entries, ee) = mem.alloc[Tally](a, n)
        if ee != ok { ret summary_none() }
        var x = 0usize
        while x < n {
            entries[x] = Tally { label: labels[x], count: counts[x] }
            x += 1usize
        }
        // commonest first, then by label
        x = 1usize
        while x < n {
            let item = entries[x]
            var y = x
            while y > 0usize && (entries[y - 1usize].count < item.count || (entries[y - 1usize].count == item.count && collate_text(entries[y - 1usize].label, item.label) > 0i32)) {
                entries[y] = entries[y - 1usize]
                y -= 1usize
            }
            entries[y] = item
            x += 1usize
        }
        ret Summary { kind: 3u8, n: 0.0f64, entries: entries[0usize..n] }
    }
    if str.eq(name, "totalSize") {
        var sum = 0.0f64
        var i = 0usize
        while i < vals.len {
            let v = vals[i]
            i += 1usize
            if is_empty(v) { continue }
            var items: []const f.Value = zero
            var single: [1]f.Value = zero
            if v.kind == .Array {
                items = v.items
            } else {
                single[0usize] = v
                items = single[0..]
            }
            var k = 0usize
            while k < items.len {
                if items[k].kind == .Record && items[k].items.len > 0usize {
                    let size = js_number(a, items[k].items[0usize])
                    if is_finite(size) { sum += size }
                }
                k += 1usize
            }
        }
        var none: []const Tally = zero
        ret Summary { kind: 4u8, n: sum, entries: none }
    }
    // the numeric family: sum, average, median, stdev, variance
    if str.eq(name, "sum") || str.eq(name, "average") || str.eq(name, "median") || str.eq(name, "stdev") || str.eq(name, "variance") {
        let (buffer, e) = mem.alloc[f64](a, vals.len + 1usize)
        if e != ok { ret summary_none() }
        let n = nums_of(a, vals, buffer)
        var sum = 0.0f64
        var i = 0usize
        while i < n {
            sum += buffer[i]
            i += 1usize
        }
        if str.eq(name, "sum") { ret summary_number(sum) }
        if str.eq(name, "average") {
            if n == 0usize { ret summary_none() }
            ret summary_number(sum / f64(n))
        }
        if str.eq(name, "median") {
            if n == 0usize { ret summary_none() }
            // ascending order
            var x = 1usize
            while x < n {
                let item = buffer[x]
                var y = x
                while y > 0usize && buffer[y - 1usize] > item {
                    buffer[y] = buffer[y - 1usize]
                    y -= 1usize
                }
                buffer[y] = item
                x += 1usize
            }
            let mid = n / 2usize
            if n % 2usize == 1usize { ret summary_number(buffer[mid]) }
            ret summary_number((buffer[mid - 1usize] + buffer[mid]) / 2.0f64)
        }
        if n < 2usize { ret summary_none() }
        let mean = sum / f64(n)
        var acc = 0.0f64
        i = 0usize
        while i < n {
            acc += (buffer[i] - mean) * (buffer[i] - mean)
            i += 1usize
        }
        let variance = acc / f64(n - 1usize)
        if str.eq(name, "variance") { ret summary_number(variance) }
        ret summary_number(math.sqrt[f64](variance))
    }
    ret summary_none()
}

// A summary over one field of a set of rows.
fn summarize(a: *mem.Arena, rows: []const Row, field: str, name: str) -> Summary {
    let (vals, e) = mem.alloc[f.Value](a, rows.len + 1usize)
    if e != ok { ret summary_none() }
    var i = 0usize
    while i < rows.len {
        vals[i] = value_at(rows[i], field)
        i += 1usize
    }
    ret summarize_values(a, vals[0usize..rows.len], name)
}

// --- row color and quick search ---------------------------------------------------------------------------------

type ColorRule = struct { has_filter: bool, filter: Node, expr: str, color: str }

// A view's color configuration: none, by a select field's option colors, or the first matching rule.
type ColorConfig = struct { mode: str, field: str, rules: []const ColorRule }

// The row's color, or empty.
fn row_color(a: *mem.Arena, reg: *const f.Registry, row: Row, color: ColorConfig, fields: []const FieldDef, ctx: *const Context) -> (str, bool) {
    if color.mode.len == 0usize || str.eq(color.mode, "none") { ret ("", false) }
    if str.eq(color.mode, "select") {
        let (def, has_def) = find_field(fields, color.field)
        let value = value_at(row, color.field)
        if is_empty(value) || !has_def || def.option_colors.len == 0usize { ret ("", false) }
        let key = js_string(a, value)
        var i = 0usize
        while i < def.option_colors.len {
            if str.eq(def.option_colors[i].name, key) && def.option_colors[i].value.kind == .Text && def.option_colors[i].value.s.len > 0usize {
                ret (def.option_colors[i].value.s, true)
            }
            i += 1usize
        }
        ret ("", false)
    }
    if str.eq(color.mode, "rules") {
        var i = 0usize
        while i < color.rules.len {
            let rule = color.rules[i]
            var matched = false
            if rule.has_filter {
                matched = eval_tree(a, reg, rule.filter, row, fields, ctx)
            } else if rule.expr.len > 0usize {
                var fc = ctx.base
                fc.fields = row.fields
                matched = truthy(f.evaluate(a, rule.expr, &fc, reg))
            }
            if matched { ret (rule.color, true) }
            i += 1usize
        }
    }
    ret ("", false)
}

// Substring search across the given fields (all of a row's when none are named); a blank term keeps every row.
fn quick_search(a: *mem.Arena, rows: []const Row, term: str, names: []const str) -> []const Row {
    if term.len == 0usize { ret rows }
    let needle = lc(a, term)
    let (out, e) = mem.alloc[Row](a, rows.len + 1usize)
    if e != ok { ret rows }
    var n = 0usize
    var i = 0usize
    while i < rows.len {
        var hit = false
        var count = names.len
        if names.len == 0usize { count = rows[i].fields.len }
        var k = 0usize
        while k < count && !hit {
            var v = f.blank()
            if names.len == 0usize {
                v = rows[i].fields[k].value
            } else {
                v = value_at(rows[i], names[k])
            }
            if !is_empty(v) {
                var text = ""
                if v.kind == .Array {
                    var j = 0usize
                    while j < v.items.len {
                        if j > 0usize { text = f.join(a, text, " ") }
                        if v.items[j].kind != .Blank { text = f.join(a, text, js_string(a, v.items[j])) }
                        j += 1usize
                    }
                } else {
                    text = js_string(a, v)
                }
                if str.contains(lc(a, text), needle) { hit = true }
            }
            k += 1usize
        }
        if hit {
            out[n] = rows[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- the whole view -------------------------------------------------------------------------------------------

type SummarySpec = struct { field: str, function: str }

type SummaryEntry = struct { field: str, value: Summary }

type SubGroup = struct { group: Group, summaries: []const SummaryEntry }

type ViewGroup = struct { group: Group, subgroups: []const Group, summaries: []const SummaryEntry }

// A saved view: a filter, a search, sorts, summaries, up to two group levels, and which fields to return.
type ViewConfig = struct {
    has_filter: bool,
    filter: Node,
    search: str,
    search_fields: []const str,
    sorts: []const SortSpec,
    group_by: []const str,
    summaries: []const SummarySpec,
    visible_fields: []const str,
    hide_new_fields: bool,
}

type ViewResult = struct {
    rows: []const Row,
    projected: bool,
    summaries: []const SummaryEntry,
    groups: []const ViewGroup,
}

fn summary_entries(a: *mem.Arena, rows: []const Row, specs: []const SummarySpec) -> []const SummaryEntry {
    var none: []const SummaryEntry = zero
    if specs.len == 0usize { ret none }
    let (out, e) = mem.alloc[SummaryEntry](a, specs.len)
    if e != ok { ret none }
    var i = 0usize
    while i < specs.len {
        out[i] = SummaryEntry { field: specs[i].field, value: summarize(a, rows, specs[i].field, specs[i].function) }
        i += 1usize
    }
    ret out
}

// Apply a view config: filter, search, sort, the field projection, the summaries and the group levels (two levels
// give the primary groups their subgroups; one gives each group its own summaries).
fn apply_view(a: *mem.Arena, reg: *const f.Registry, rows: []const Row, config: ViewConfig, fields: []const FieldDef, ctx: *const Context) -> ViewResult {
    var current = rows
    if config.has_filter { current = filter_rows(a, reg, current, config.filter, true, fields, ctx) }
    if config.search.len > 0usize { current = quick_search(a, current, config.search, config.search_fields) }
    if config.sorts.len > 0usize { current = sort_rows(a, current, config.sorts, fields) }
    var projected = false
    var shown = current
    if config.visible_fields.len > 0usize && config.hide_new_fields {
        let (out, e) = mem.alloc[Row](a, current.len + 1usize)
        if e == ok {
            var i = 0usize
            while i < current.len {
                let (cells, ce) = mem.alloc[f.Field](a, config.visible_fields.len + 1usize)
                var n = 0usize
                if ce == ok {
                    var k = 0usize
                    while k < config.visible_fields.len {
                        let (v, present) = cell_of(current[i], config.visible_fields[k])
                        if present {
                            cells[n] = f.Field { name: config.visible_fields[k], value: v }
                            n += 1usize
                        }
                        k += 1usize
                    }
                }
                out[i] = Row { fields: cells[0usize..n] }
                i += 1usize
            }
            shown = out[0usize..current.len]
            projected = true
        }
    }
    var summaries: []const SummaryEntry = zero
    if config.summaries.len > 0usize { summaries = summary_entries(a, current, config.summaries) }
    var groups: []const ViewGroup = zero
    if config.group_by.len > 0usize {
        let top = group_rows(a, current, config.group_by[0usize], "", fields)
        let (out, e) = mem.alloc[ViewGroup](a, top.len + 1usize)
        if e == ok {
            var g = 0usize
            while g < top.len {
                var subgroups: []const Group = zero
                var group_summaries: []const SummaryEntry = zero
                if config.group_by.len >= 2usize {
                    subgroups = group_rows(a, top[g].rows, config.group_by[1usize], "", fields)
                } else if config.summaries.len > 0usize {
                    group_summaries = summary_entries(a, top[g].rows, config.summaries)
                }
                out[g] = ViewGroup { group: top[g], subgroups: subgroups, summaries: group_summaries }
                g += 1usize
            }
            groups = out[0usize..top.len]
        }
    }
    ret ViewResult { rows: shown, projected: projected, summaries: summaries, groups: groups }
}

// --- the filter tree: edits that return a new tree ---------------------------------------------------------------

// The node at `path` (child indexes from the root), or false.
fn node_at(tree: Node, path: []const usize) -> (Node, bool) {
    var node = tree
    var i = 0usize
    while i < path.len {
        if !is_group(node) || path[i] >= node.children.len { ret (empty_group("and"), false) }
        node = node.children[path[i]]
        i += 1usize
    }
    ret (node, true)
}

fn with_children(node: Node, children: []const Node) -> Node {
    var out = node
    out.children = children
    ret out
}

// Replace the node at `path` by applying `edit` along it: a copy of the tree with the group at depth `at` rebuilt.
fn replace_at(a: *mem.Arena, tree: Node, path: []const usize, depth: usize, replacement: Node, remove: bool) -> Node {
    if depth == path.len { ret replacement }
    if !is_group(tree) || path[depth] >= tree.children.len { ret tree }
    if remove && depth + 1usize == path.len {
        let (out, e) = mem.alloc[Node](a, tree.children.len)
        if e != ok { ret tree }
        var n = 0usize
        var i = 0usize
        while i < tree.children.len {
            if i != path[depth] {
                out[n] = tree.children[i]
                n += 1usize
            }
            i += 1usize
        }
        ret with_children(tree, out[0usize..n])
    }
    let (out, e) = mem.alloc[Node](a, tree.children.len)
    if e != ok { ret tree }
    var i = 0usize
    while i < tree.children.len {
        out[i] = tree.children[i]
        if i == path[depth] { out[i] = replace_at(a, tree.children[i], path, depth + 1usize, replacement, remove) }
        i += 1usize
    }
    ret with_children(tree, out[0usize..tree.children.len])
}

// Add a condition or group under the group at `path`; a missing or non-group group_node leaves the tree as it was.
fn add_node(a: *mem.Arena, tree: Node, path: []const usize, node: Node) -> Node {
    let (group_node, found) = node_at(tree, path)
    if !found || !is_group(group_node) { ret tree }
    let (out, e) = mem.alloc[Node](a, group_node.children.len + 1usize)
    if e != ok { ret tree }
    var i = 0usize
    while i < group_node.children.len {
        out[i] = group_node.children[i]
        i += 1usize
    }
    out[group_node.children.len] = node
    ret replace_at(a, tree, path, 0usize, with_children(group_node, out[0usize..group_node.children.len + 1usize]), false)
}

// Remove the node at `path`; the root is never removed, only emptied.
fn remove_node(a: *mem.Arena, tree: Node, path: []const usize) -> Node {
    if path.len == 0usize { ret with_children(tree, zero_nodes()) }
    let (group_node, found) = node_at(tree, path)
    if !found { ret tree }
    ret replace_at(a, tree, path, 0usize, group_node, true)
}

fn zero_nodes() -> []const Node {
    var none: []const Node = zero
    ret none
}

// Replace the node at `path`; an empty path replaces the whole tree.
fn replace_node(a: *mem.Arena, tree: Node, path: []const usize, node: Node) -> Node {
    if path.len == 0usize { ret node }
    ret replace_at(a, tree, path, 0usize, node, false)
}

// Flip the group at `path` between AND and OR; false when it is not a group.
fn toggle_group_operator(a: *mem.Arena, tree: Node, path: []const usize) -> (Node, bool) {
    let (group_node, found) = node_at(tree, path)
    if !found || !is_group(group_node) { ret (tree, false) }
    var flipped = group_node
    if str.eq(group_node.operator, "and") { flipped.operator = "or" } else { flipped.operator = "and" }
    if path.len == 0usize { ret (flipped, true) }
    ret (replace_at(a, tree, path, 0usize, flipped, false), true)
}

// Drop empty groups and unwrap groups of one; false when nothing is left.
fn prune_tree(a: *mem.Arena, tree: Node) -> (Node, bool) {
    if !is_group(tree) { ret (tree, true) }
    let (out, e) = mem.alloc[Node](a, tree.children.len + 1usize)
    if e != ok { ret (tree, true) }
    var n = 0usize
    var i = 0usize
    while i < tree.children.len {
        let (child, keep) = prune_tree(a, tree.children[i])
        if keep {
            out[n] = child
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize { ret (tree, false) }
    if n == 1usize { ret (out[0usize], true) }
    ret (with_children(tree, out[0usize..n]), true)
}

// How many condition leaves are in force.
fn count_conditions(tree: Node) -> usize {
    if !is_group(tree) { ret 1usize }
    var n = 0usize
    var i = 0usize
    while i < tree.children.len {
        n += count_conditions(tree.children[i])
        i += 1usize
    }
    ret n
}

// How deep the nesting goes: 0 for a condition, 1 for a flat group.
fn tree_depth(tree: Node) -> usize {
    if !is_group(tree) { ret 0usize }
    var deepest = 0usize
    var i = 0usize
    while i < tree.children.len {
        let d = tree_depth(tree.children[i])
        if d > deepest { deepest = d }
        i += 1usize
    }
    ret 1usize + deepest
}

// --- multi-column sort levels ------------------------------------------------------------------------------------

// This field's 1-based position in the sort order, or 0.
fn sort_level(sorts: []const SortSpec, field: str) -> usize {
    var i = 0usize
    while i < sorts.len {
        if str.eq(sorts[i].field, field) { ret i + 1usize }
        i += 1usize
    }
    ret 0usize
}

// Add or cycle a field as a sort level, keeping the others: new at the end ascending, then descending, then gone
// (the gap closes). The new direction is "asc", "desc" or "" when removed.
fn append_sort_level(a: *mem.Arena, sorts: []const SortSpec, field: str) -> ([]const SortSpec, str) {
    let (out, e) = mem.alloc[SortSpec](a, sorts.len + 1usize)
    if e != ok { ret (sorts, "") }
    var n = 0usize
    var found = false
    var direction = ""
    var i = 0usize
    while i < sorts.len {
        if str.eq(sorts[i].field, field) {
            found = true
            if str.eq(sorts[i].direction, "asc") {
                out[n] = SortSpec { field: field, direction: "desc" }
                n += 1usize
                direction = "desc"
            }
        } else {
            out[n] = sorts[i]
            n += 1usize
        }
        i += 1usize
    }
    if !found {
        out[n] = SortSpec { field: field, direction: "asc" }
        n += 1usize
        direction = "asc"
    }
    ret (out[0usize..n], direction)
}

// Drop one level, closing the gap.
fn remove_sort_level(a: *mem.Arena, sorts: []const SortSpec, field: str) -> []const SortSpec {
    let (out, e) = mem.alloc[SortSpec](a, sorts.len + 1usize)
    if e != ok { ret sorts }
    var n = 0usize
    var i = 0usize
    while i < sorts.len {
        if !str.eq(sorts[i].field, field) {
            out[n] = sorts[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// Move a level earlier (-1) or later (+1), clamped; false when nothing moved.
fn move_sort_level(a: *mem.Arena, sorts: []const SortSpec, field: str, delta: i64) -> ([]const SortSpec, bool) {
    let at = sort_level(sorts, field)
    if at == 0usize { ret (sorts, false) }
    var to = i64(at - 1usize) + delta
    if to < 0i64 { to = 0i64 }
    if to > i64(sorts.len) - 1i64 { to = i64(sorts.len) - 1i64 }
    if usize(to) == at - 1usize { ret (sorts, false) }
    let (out, e) = mem.alloc[SortSpec](a, sorts.len)
    if e != ok { ret (sorts, false) }
    let moved = sorts[at - 1usize]
    var n = 0usize
    var i = 0usize
    // the list without the moved level, then the level inserted at `to`
    var rest: [32]SortSpec = zero
    var rn = 0usize
    while i < sorts.len && rn < 32usize {
        if i != at - 1usize {
            rest[rn] = sorts[i]
            rn += 1usize
        }
        i += 1usize
    }
    var r = 0usize
    while n < sorts.len {
        if i64(n) == to {
            out[n] = moved
        } else {
            out[n] = rest[r]
            r += 1usize
        }
        n += 1usize
    }
    ret (out[0usize..sorts.len], true)
}

// Is more than one level in force?
fn is_multi_sorted(sorts: []const SortSpec) -> bool { ret sorts.len > 1usize }
