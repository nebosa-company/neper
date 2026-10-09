// Spreadsheet-style formula engine core (L026), a port of appdor's `src/formula` tokenizer, parser, evaluator,
// registry and value model: `{Field}` references, bare names, `let` variables, `//` comments, the operators
// `+ - * / % ^ & = == != <> < <= > >= && || !`, `cond ? a : b`, array literals `[...]`, and calls to registered
// functions. It is pure and deterministic: nothing here reads a clock, a random source or a file; the host passes
// them in through the context.
//
// Errors are values, never thrown. A `Value` of kind `Error` carries one of the eight spreadsheet codes and a
// message; it flows through operators and eagerly evaluated arguments, and only a function registered with
// `pass_errors` (ISERROR, IFERROR's handler, TYPEOF ...) sees it. Blank is its own kind: it propagates through
// arithmetic as blank (not zero) and is equal only to blank or the empty text. A budget of evaluation steps ends
// a runaway expression with `#LIMIT!`, and the parser refuses a formula of more than `max_nodes` nodes with the
// same code.
//
// Functions live in a `Registry` of `Entry`s: a canonical upper-case name, aliases, arity, flags (`lazy`: the
// handler gets the argument nodes and evaluates what it needs; `pass_errors`; `volatile`; `generate_once`) and a
// `Handler`. Names are matched case- and underscore-insensitively (`IS_BLANK` is `ISBLANK`). The standard function
// library is registered by the `e.algo.formula.*` modules, not here; the language forms `LET` and `LETS` are
// registered by `register_core`.
//
// Resolution of a name or `{Field}` goes: the `let` scope; then the host's field values, with the formulas of the
// sibling fields evaluated on demand and a circular reference answered as `#REF!` naming the cycle; then a function
// that takes no arguments (`PI`, `NOW` ...) used bare; then `#REF!` under `strict_refs`, else blank.
//
// Differences from the JavaScript original, all in the edges: `Date` text parsing is ISO-8601 only (`YYYY[-MM[-DD]]`
// with an optional time and zone) where JavaScript falls back to a legacy parser; text lower-casing uses the simple
// Unicode mapping; offsets in a diagnostic count UTF-16 units as JavaScript does; and a field named like a
// JavaScript object property (`constructor`) is an ordinary field.

use e.math
use e.mem
use e.str
use e.text.unicode as unicode
use e.text.utf8 as utf8
use e.time

// --- Values ---------------------------------------------------------------------------------------------------

type Kind = enum u8 { Blank, Number, Text, Bool, Date, Array, Error, Record }

// A formula value. `n` is the number, the date in milliseconds since the epoch, or 1/0 for a boolean; `s` is the
// text or an error's message; `items` the elements of an array; `code` an error's code.
type Value = struct { kind: Kind, n: f64, s: str, items: []const Value, code: u8 }

const E_DIV0: u8 = 0u8
const E_VALUE: u8 = 1u8
const E_NA: u8 = 2u8
const E_NAME: u8 = 3u8
const E_NUM: u8 = 4u8
const E_REF: u8 = 5u8
const E_ERROR: u8 = 6u8
const E_LIMIT: u8 = 7u8

// The spelling of an error code: `#DIV/0!` ... `#LIMIT!`.
fn code_text(code: u8) -> str {
    if code == E_DIV0 { ret "#DIV/0!" }
    if code == E_VALUE { ret "#VALUE!" }
    if code == E_NA { ret "#N/A" }
    if code == E_NAME { ret "#NAME?" }
    if code == E_NUM { ret "#NUM!" }
    if code == E_REF { ret "#REF!" }
    if code == E_LIMIT { ret "#LIMIT!" }
    ret "#ERROR!"
}

fn blank() -> Value { ret Value { kind: .Blank, n: 0.0f64, s: "", items: zero_items(), code: 0u8 } }

fn zero_items() -> []const Value {
    var none: []const Value = zero
    ret none
}

fn number(n: f64) -> Value { ret Value { kind: .Number, n: n, s: "", items: zero_items(), code: 0u8 } }

fn text(s: str) -> Value { ret Value { kind: .Text, n: 0.0f64, s: s, items: zero_items(), code: 0u8 } }

fn boolean(b: bool) -> Value {
    var n = 0.0f64
    if b { n = 1.0f64 }
    ret Value { kind: .Bool, n: n, s: "", items: zero_items(), code: 0u8 }
}

// A date as milliseconds since 1970-01-01T00:00:00Z.
fn date(ms: f64) -> Value { ret Value { kind: .Date, n: ms, s: "", items: zero_items(), code: 0u8 } }

fn array(items: []const Value) -> Value { ret Value { kind: .Array, n: 0.0f64, s: "", items: items, code: 0u8 } }

// A two-field range record (DATERANGE): `items` are its start and end.
fn record(items: []const Value) -> Value { ret Value { kind: .Record, n: 0.0f64, s: "", items: items, code: 0u8 } }

fn make_error(code: u8, message: str) -> Value { ret Value { kind: .Error, n: 0.0f64, s: message, items: zero_items(), code: code } }

fn div_zero() -> Value { ret make_error(E_DIV0, "Division by zero") }

fn div_zero_message(message: str) -> Value { ret make_error(E_DIV0, message) }

fn value_error(message: str) -> Value { ret make_error(E_VALUE, message) }

fn na_error(message: str) -> Value { ret make_error(E_NA, message) }

fn name_error(message: str) -> Value { ret make_error(E_NAME, message) }

fn num_error(message: str) -> Value { ret make_error(E_NUM, message) }

fn ref_error(message: str) -> Value { ret make_error(E_REF, message) }

fn generic_error(message: str) -> Value { ret make_error(E_ERROR, message) }

fn limit_error(message: str) -> Value { ret make_error(E_LIMIT, message) }

fn is_error(v: Value) -> bool { ret v.kind == .Error }

fn is_na(v: Value) -> bool { ret v.kind == .Error && v.code == E_NA }

// Blank is the blank kind or the empty text.
fn is_blank(v: Value) -> bool { ret v.kind == .Blank || (v.kind == .Text && v.s.len == 0usize) }

// `blank | number | text | boolean | date | array | error`.
fn type_of(v: Value) -> str {
    if v.kind == .Error { ret "error" }
    if is_blank(v) { ret "blank" }
    if v.kind == .Bool { ret "boolean" }
    if v.kind == .Number { ret "number" }
    if v.kind == .Date { ret "date" }
    if v.kind == .Array { ret "array" }
    ret "text"
}

// Excel's TYPE code: 1 number, 2 text, 4 boolean, 16 error, 64 array, 32 date, 0 blank.
fn type_code(v: Value) -> i64 {
    if v.kind == .Error { ret 16i64 }
    if is_blank(v) { ret 0i64 }
    if v.kind == .Number { ret 1i64 }
    if v.kind == .Bool { ret 4i64 }
    if v.kind == .Date { ret 32i64 }
    if v.kind == .Array { ret 64i64 }
    ret 2i64
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret x }
    ret out
}

fn join3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    ret join(a, join(a, x, y), z)
}

// --- Numbers as text --------------------------------------------------------------------------------------------

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// The text of a number as JavaScript's `String(n)` writes it: shortest round-trip digits, fixed notation from
// 1e-6 up to 1e21, otherwise `1.5e-7` or `1e+21`; `NaN`, `Infinity`, `-Infinity`; negative zero is `0`.
fn number_text(a: *mem.Arena, x: f64) -> str {
    if x != x { ret "NaN" }
    if x - x != 0.0f64 {
        if x < 0.0f64 { ret "-Infinity" }
        ret "Infinity"
    }
    if x == 0.0f64 { ret "0" }
    let (b, be) = str.builder(a, 40usize)
    if be != ok { ret "0" }
    var builder = b
    if str.push_f64(&builder, x) != ok { ret "0" }
    let raw = str.done(&builder)
    var negative = false
    var at = 0usize
    if raw[0usize] == 45u8 {
        negative = true
        at = 1usize
    }
    // The mantissa digits (integer part then fraction), how many are the integer part, and the exponent.
    var all: [40]u8 = zero
    var total = 0usize
    var integer_digits = 0usize
    var in_fraction = false
    var exponent = 0i64
    while at < raw.len {
        let c = raw[at]
        if c == 101u8 {
            var p = at + 1usize
            var exp_negative = false
            if p < raw.len && raw[p] == 45u8 {
                exp_negative = true
                p += 1usize
            } else if p < raw.len && raw[p] == 43u8 {
                p += 1usize
            }
            var v = 0i64
            while p < raw.len {
                v = v * 10i64 + i64(raw[p] - 48u8)
                p += 1usize
            }
            if exp_negative { v = 0i64 - v }
            exponent = v
            at = raw.len
        } else if c == 46u8 {
            in_fraction = true
            at += 1usize
        } else {
            all[total] = c
            total += 1usize
            if !in_fraction { integer_digits += 1usize }
            at += 1usize
        }
    }
    // value = 0.SIG * 10^n, with SIG the digits without leading or trailing zeros.
    var lead = 0usize
    while lead < total && all[lead] == 48u8 { lead += 1usize }
    var end = total
    while end > lead + 1usize && all[end - 1usize] == 48u8 { end -= 1usize }
    let count = end - lead
    let n = i64(integer_digits) - i64(lead) + exponent
    let k = i64(count)
    let (out, oe) = mem.alloc[u8](a, 64usize)
    if oe != ok { ret "0" }
    var w = 0usize
    if negative {
        out[w] = 45u8
        w += 1usize
    }
    if k <= n && n <= 21i64 {
        var i = 0usize
        while i < count {
            out[w] = all[lead + i]
            w += 1usize
            i += 1usize
        }
        var z = k
        while z < n {
            out[w] = 48u8
            w += 1usize
            z += 1i64
        }
    } else if 0i64 < n && n <= 21i64 {
        var i = 0usize
        while i < count {
            if i64(i) == n {
                out[w] = 46u8
                w += 1usize
            }
            out[w] = all[lead + i]
            w += 1usize
            i += 1usize
        }
    } else if -6i64 < n && n <= 0i64 {
        out[w] = 48u8
        out[w + 1usize] = 46u8
        w += 2usize
        var z = n
        while z < 0i64 {
            out[w] = 48u8
            w += 1usize
            z += 1i64
        }
        var i = 0usize
        while i < count {
            out[w] = all[lead + i]
            w += 1usize
            i += 1usize
        }
    } else {
        out[w] = all[lead]
        w += 1usize
        if count > 1usize {
            out[w] = 46u8
            w += 1usize
            var i = 1usize
            while i < count {
                out[w] = all[lead + i]
                w += 1usize
                i += 1usize
            }
        }
        out[w] = 101u8
        w += 1usize
        var e10 = n - 1i64
        if e10 < 0i64 {
            out[w] = 45u8
            e10 = 0i64 - e10
        } else {
            out[w] = 43u8
        }
        w += 1usize
        var ed: [8]u8 = zero
        var en = 0usize
        while e10 > 0i64 {
            ed[en] = u8(48i64 + e10 % 10i64)
            en += 1usize
            e10 = e10 / 10i64
        }
        if en == 0usize {
            ed[0usize] = 48u8
            en = 1usize
        }
        while en > 0usize {
            en -= 1usize
            out[w] = ed[en]
            w += 1usize
        }
    }
    ret out[0usize..w]
}

// The number a text means as JavaScript's `Number(text)` reads it (the text already trimmed and not empty):
// decimal with optional sign, fraction and exponent, `Infinity`, or an unsigned `0x`, `0o` or `0b` literal.
fn parse_number_text(s: str) -> (f64, bool) {
    if s.len == 0usize { ret (0.0f64, false) }
    var at = 0usize
    var negative = false
    if s[0usize] == 43u8 || s[0usize] == 45u8 {
        negative = s[0usize] == 45u8
        at = 1usize
    }
    let rest = s[at..s.len]
    if rest.len == 8usize && rest[0usize] == 73u8 && str.eq(rest, "Infinity") {
        if negative { ret (0.0f64 - infinity(), true) }
        ret (infinity(), true)
    }
    if at == 0usize && s.len > 2usize && s[0usize] == 48u8 {
        var radix = 0u8
        if s[1usize] == 120u8 || s[1usize] == 88u8 { radix = 16u8 }
        if s[1usize] == 111u8 || s[1usize] == 79u8 { radix = 8u8 }
        if s[1usize] == 98u8 || s[1usize] == 66u8 { radix = 2u8 }
        if radix != 0u8 {
            let (v, e) = str.parse_u64_radix(s[2usize..s.len], radix)
            if e != ok { ret (0.0f64, false) }
            ret (f64(v), true)
        }
    }
    // Decimal: digits [. digits] [e[+-]digits], with at least one digit in the mantissa.
    var p = at
    var mantissa_digits = 0usize
    while p < s.len && is_digit(s[p]) {
        p += 1usize
        mantissa_digits += 1usize
    }
    if p < s.len && s[p] == 46u8 {
        p += 1usize
        while p < s.len && is_digit(s[p]) {
            p += 1usize
            mantissa_digits += 1usize
        }
    }
    if mantissa_digits == 0usize { ret (0.0f64, false) }
    if p < s.len && (s[p] == 101u8 || s[p] == 69u8) {
        p += 1usize
        if p < s.len && (s[p] == 43u8 || s[p] == 45u8) { p += 1usize }
        var exp_digits = 0usize
        while p < s.len && is_digit(s[p]) {
            p += 1usize
            exp_digits += 1usize
        }
        if exp_digits == 0usize { ret (0.0f64, false) }
    }
    if p != s.len { ret (0.0f64, false) }
    // The exponent marker is read in lower case.
    var lowered: [128]u8 = zero
    if s.len > 120usize { ret (0.0f64, false) }
    var k = 0usize
    while k < s.len {
        var c = s[k]
        if c == 69u8 { c = 101u8 }
        lowered[k] = c
        k += 1usize
    }
    let (v, e) = str.parse_f64(lowered[0usize..s.len])
    if e != ok { ret (0.0f64, false) }
    ret (v, true)
}

// --- Dates ------------------------------------------------------------------------------------------------------

fn ms_per_day() -> f64 { ret 86400000.0f64 }

// The ISO text of a date value: `2026-01-15T23:30:00.000Z` (years beyond 9999 as `+YYYYYY`).
fn date_iso(a: *mem.Arena, ms: f64) -> str {
    let days = math.floor[f64](ms / ms_per_day())
    let into_day = ms - days * ms_per_day()
    let (year, month, day) = time.civil_from_days(i64(days))
    let whole = i64(into_day)
    let hour = whole / 3600000i64
    let minute = whole / 60000i64 % 60i64
    let second = whole / 1000i64 % 60i64
    let milli = whole % 1000i64
    let (out, e) = mem.alloc[u8](a, 40usize)
    if e != ok { ret "" }
    var w = 0usize
    var y = year
    if year >= 0i64 && year <= 9999i64 {
        w = put_int(out, w, y, 4usize)
    } else {
        if year < 0i64 {
            out[w] = 45u8
            y = 0i64 - year
        } else {
            out[w] = 43u8
        }
        w += 1usize
        w = put_int(out, w, y, 6usize)
    }
    out[w] = 45u8
    w = put_int(out, w + 1usize, month, 2usize)
    out[w] = 45u8
    w = put_int(out, w + 1usize, day, 2usize)
    out[w] = 84u8
    w = put_int(out, w + 1usize, hour, 2usize)
    out[w] = 58u8
    w = put_int(out, w + 1usize, minute, 2usize)
    out[w] = 58u8
    w = put_int(out, w + 1usize, second, 2usize)
    out[w] = 46u8
    w = put_int(out, w + 1usize, milli, 3usize)
    out[w] = 90u8
    ret out[0usize..w + 1usize]
}

// `value` as `width` decimal digits at `at`; the position after.
fn put_int(out: []u8, at: usize, value: i64, width: usize) -> usize {
    var v = value
    var i = width
    while i > 0usize {
        i -= 1usize
        out[at + i] = u8(48i64 + v % 10i64)
        v = v / 10i64
    }
    ret at + width
}

fn digits_value(s: str, from: usize, count: usize) -> (i64, bool) {
    if from + count > s.len { ret (0i64, false) }
    var v = 0i64
    var i = 0usize
    while i < count {
        if !is_digit(s[from + i]) { ret (0i64, false) }
        v = v * 10i64 + i64(s[from + i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

// An ISO-8601 date or date-time as milliseconds since the epoch (UTC; a text with no zone is UTC). The forms:
// `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, each optionally followed by `T` or a space and `HH:MM[:SS[.fff]]` and `Z` or
// `+HH:MM`, `-HH:MM`, `+HHMM`. `ok` is false for anything else.
fn parse_iso(s: str) -> (f64, bool) {
    if s.len < 4usize { ret (0.0f64, false) }
    let (year, year_ok) = digits_value(s, 0usize, 4usize)
    if !year_ok { ret (0.0f64, false) }
    var month = 1i64
    var day = 1i64
    var at = 4usize
    if at < s.len && s[at] == 45u8 {
        let (m, m_ok) = digits_value(s, at + 1usize, 2usize)
        if !m_ok { ret (0.0f64, false) }
        month = m
        at += 3usize
        if at < s.len && s[at] == 45u8 {
            let (d, d_ok) = digits_value(s, at + 1usize, 2usize)
            if !d_ok { ret (0.0f64, false) }
            day = d
            at += 3usize
        }
    }
    if month < 1i64 || month > 12i64 { ret (0.0f64, false) }
    if day < 1i64 || day > time.days_in_month(year, month) { ret (0.0f64, false) }
    var millis = f64(time.days_from_civil(year, month, day)) * ms_per_day()
    if at == s.len { ret (millis, true) }
    if s[at] != 84u8 && s[at] != 32u8 && s[at] != 116u8 { ret (0.0f64, false) }
    let (hour, hour_ok) = digits_value(s, at + 1usize, 2usize)
    if !hour_ok || at + 3usize >= s.len || s[at + 3usize] != 58u8 { ret (0.0f64, false) }
    let (minute, minute_ok) = digits_value(s, at + 4usize, 2usize)
    if !minute_ok { ret (0.0f64, false) }
    at += 6usize
    var second = 0i64
    var fraction = 0.0f64
    if at < s.len && s[at] == 58u8 {
        let (sec, sec_ok) = digits_value(s, at + 1usize, 2usize)
        if !sec_ok { ret (0.0f64, false) }
        second = sec
        at += 3usize
        if at < s.len && s[at] == 46u8 {
            at += 1usize
            var scale = 100.0f64
            var any = false
            while at < s.len && is_digit(s[at]) {
                fraction += f64(s[at] - 48u8) * scale
                scale = scale / 10.0f64
                any = true
                at += 1usize
            }
            if !any { ret (0.0f64, false) }
            fraction = math.floor[f64](fraction)
        }
    }
    if hour > 24i64 || minute > 59i64 || second > 59i64 { ret (0.0f64, false) }
    if hour == 24i64 && (minute != 0i64 || second != 0i64 || fraction != 0.0f64) { ret (0.0f64, false) }
    millis += f64(hour) * 3600000.0f64 + f64(minute) * 60000.0f64 + f64(second) * 1000.0f64 + fraction
    if at < s.len {
        if s[at] == 90u8 || s[at] == 122u8 {
            at += 1usize
        } else if s[at] == 43u8 || s[at] == 45u8 {
            let sign = s[at] == 45u8
            let (zh, zh_ok) = digits_value(s, at + 1usize, 2usize)
            if !zh_ok { ret (0.0f64, false) }
            var zp = at + 3usize
            if zp < s.len && s[zp] == 58u8 { zp += 1usize }
            let (zm, zm_ok) = digits_value(s, zp, 2usize)
            if !zm_ok { ret (0.0f64, false) }
            at = zp + 2usize
            var offset = f64(zh * 60i64 + zm) * 60000.0f64
            if sign { offset = 0.0f64 - offset }
            millis -= offset
        } else {
            ret (0.0f64, false)
        }
    }
    if at != s.len { ret (0.0f64, false) }
    ret (millis, true)
}

// The legacy reading JavaScript gives to text that is only numbers and separators (`/ - , . space`), after V8's
// DayComposer: one to three numbers; the first is a year when it is not a day (1..31), else the month, then the
// day, then the year; a missing day or month is 1 and a missing year is 2001; a year of 0..49 is 20xx and 50..99
// is 19xx. `1` is 1 January 2001, `5` is 1 May 2001, `12/31/1999` and `1999-12-31` are what they look like.
fn parse_legacy_numeric(s: str) -> (f64, bool) {
    var comps: [3]f64 = zero
    var count = 0usize
    var i = 0usize
    var any = false
    while i < s.len {
        let b = s[i]
        if is_digit(b) {
            var v = 0.0f64
            var digits = 0usize
            while i < s.len && is_digit(s[i]) {
                v = v * 10.0f64 + f64(s[i] - 48u8)
                digits += 1usize
                i += 1usize
            }
            if digits > 9usize || count >= 3usize { ret (0.0f64, false) }
            comps[count] = v
            count += 1usize
            any = true
        } else if b == 47u8 || b == 45u8 || b == 44u8 || b == 46u8 || b == 32u8 {
            i += 1usize
        } else {
            ret (0.0f64, false)
        }
    }
    if !any { ret (0.0f64, false) }
    while count < 3usize {
        comps[count] = 1.0f64
        count += 1usize
    }
    var year = 0.0f64
    var month = 0.0f64
    var day = 0.0f64
    let first_is_day = comps[0usize] >= 1.0f64 && comps[0usize] <= 31.0f64
    if !first_is_day {
        year = comps[0usize]
        month = comps[1usize]
        day = comps[2usize]
    } else {
        month = comps[0usize]
        day = comps[1usize]
        year = comps[2usize]
    }
    if year >= 0.0f64 && year <= 49.0f64 { year += 2000.0f64 } else if year >= 50.0f64 && year <= 99.0f64 { year += 1900.0f64 }
    if month < 1.0f64 || month > 12.0f64 || day < 1.0f64 || day > 31.0f64 { ret (0.0f64, false) }
    // The day rolls over a short month the way `Date.UTC` does (31 April is 1 May).
    let first = f64(time.days_from_civil(i64(year), i64(month), 1i64))
    let ms = (first + day - 1.0f64) * ms_per_day()
    if ms > 8640000000000000.0f64 || ms < -8640000000000000.0f64 { ret (0.0f64, false) }
    ret (ms, true)
}

// The instant a date text names: ISO-8601, or the numeric legacy form above.
fn parse_date_text(s: str) -> (f64, bool) {
    let (iso, good) = parse_iso(s)
    if good { ret (iso, true) }
    if is_naive_datetime(s) { ret (0.0f64, false) }
    let (legacy, legacy_ok) = parse_legacy_numeric(s)
    ret (legacy, legacy_ok)
}

// A date-time text that names no zone: `YYYY-MM-DD[T ]HH:MM[:SS[.f+]]`.
fn is_naive_datetime(s: str) -> bool {
    if s.len < 16usize { ret false }
    if !is_digit(s[0usize]) || !is_digit(s[1usize]) || !is_digit(s[2usize]) || !is_digit(s[3usize]) { ret false }
    if s[4usize] != 45u8 || s[7usize] != 45u8 { ret false }
    if s[10usize] != 84u8 && s[10usize] != 32u8 { ret false }
    let (hour, hour_ok) = digits_value(s, 11usize, 2usize)
    if !hour_ok || s[13usize] != 58u8 { ret false }
    let (minute, minute_ok) = digits_value(s, 14usize, 2usize)
    if !minute_ok { ret false }
    var p = 16usize
    if p == s.len { ret true }
    if s[p] != 58u8 { ret false }
    let (second, second_ok) = digits_value(s, p + 1usize, 2usize)
    if !second_ok { ret false }
    p += 3usize
    if p == s.len { ret true }
    if s[p] != 46u8 { ret false }
    p += 1usize
    if p == s.len { ret false }
    while p < s.len {
        if !is_digit(s[p]) { ret false }
        p += 1usize
    }
    ret true
}

// A complete ISO-8601 date or timestamp: the shape two texts must both have to be compared as instants.
fn is_iso_temporal(s: str) -> bool {
    if s.len < 10usize { ret false }
    if !is_digit(s[0usize]) || !is_digit(s[1usize]) || !is_digit(s[2usize]) || !is_digit(s[3usize]) { ret false }
    if s[4usize] != 45u8 || s[7usize] != 45u8 { ret false }
    if !is_digit(s[5usize]) || !is_digit(s[6usize]) || !is_digit(s[8usize]) || !is_digit(s[9usize]) { ret false }
    if s.len == 10usize { ret true }
    if s[10usize] != 84u8 && s[10usize] != 32u8 { ret false }
    if s.len < 16usize { ret false }
    let (hour, hour_ok) = digits_value(s, 11usize, 2usize)
    if !hour_ok || s[13usize] != 58u8 { ret false }
    let (minute, minute_ok) = digits_value(s, 14usize, 2usize)
    if !minute_ok { ret false }
    var p = 16usize
    if p < s.len && s[p] == 58u8 {
        let (second, second_ok) = digits_value(s, p + 1usize, 2usize)
        if !second_ok { ret false }
        p += 3usize
        if p < s.len && s[p] == 46u8 {
            p += 1usize
            let start = p
            while p < s.len && is_digit(s[p]) { p += 1usize }
            if p == start { ret false }
        }
    }
    if p == s.len { ret true }
    if s[p] == 90u8 { ret p + 1usize == s.len }
    if s[p] == 43u8 || s[p] == 45u8 {
        let (zh, zh_ok) = digits_value(s, p + 1usize, 2usize)
        if !zh_ok { ret false }
        var q = p + 3usize
        if q < s.len && s[q] == 58u8 { q += 1usize }
        let (zm, zm_ok) = digits_value(s, q, 2usize)
        ret zm_ok && q + 2usize == s.len
    }
    ret false
}

// --- Coercions --------------------------------------------------------------------------------------------------

fn trim_text(s: str) -> str {
    ret str.trim(s)
}

// A number, blank (the blank value, which propagates), or an error. Text must read as a JavaScript number.
fn to_number(a: *mem.Arena, v: Value) -> Value {
    if v.kind == .Error { ret v }
    if is_blank(v) { ret blank() }
    if v.kind == .Number {
        if v.n != v.n { ret value_error("Wrong type of argument") }
        ret v
    }
    if v.kind == .Bool { ret number(v.n) }
    if v.kind == .Date { ret number(v.n) }
    if v.kind == .Text {
        let trimmed = trim_text(v.s)
        if trimmed.len == 0usize { ret blank() }
        let (n, good) = parse_number_text(trimmed)
        if good { ret number(n) }
        ret value_error(join3(a, "Cannot convert \"", v.s, "\" to a number"))
    }
    ret value_error("Wrong type of argument")
}

// The text of a value; an error passes through as an error value.
fn to_text(a: *mem.Arena, v: Value) -> Value {
    if v.kind == .Error { ret v }
    if is_blank(v) { ret text("") }
    if v.kind == .Text { ret v }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret text("true") }
        ret text("false")
    }
    if v.kind == .Number { ret text(number_text(a, v.n)) }
    if v.kind == .Date {
        if v.n != v.n { ret generic_error("Invalid time value") }
        ret text(date_iso(a, v.n))
    }
    if v.kind == .Record { ret text("[object Object]") }
    // An array: the elements as text, blank as empty, joined by commas.
    var out = ""
    var i = 0usize
    while i < v.items.len {
        if i > 0usize { out = join(a, out, ",") }
        if !is_blank(v.items[i]) {
            let piece = to_text(a, v.items[i])
            // An error element is written as its code, as JavaScript's join does with an error object.
            if piece.kind == .Error {
                out = join(a, out, code_text(piece.code))
            } else {
                out = join(a, out, piece.s)
            }
        }
        i += 1usize
    }
    ret text(out)
}

fn lower_text(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 2usize + 4usize)
    if e != ok { ret s }
    var w = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            var piece: [4]u8 = zero
            let (width, we) = utf8.encode(unicode.to_lower_simple(scalar), piece[0..])
            var k = 0usize
            while k < usize(width) {
                out[w] = piece[k]
                w += 1usize
                k += 1usize
            }
        }
    }
    ret out[0usize..w]
}

// The boolean a value means; an error is returned in `err_value` with `is_err` true.
fn to_bool(v: Value) -> bool {
    if v.kind == .Error { ret false }
    if is_blank(v) { ret false }
    if v.kind == .Bool { ret v.n != 0.0f64 }
    if v.kind == .Number { ret v.n != 0.0f64 }
    if v.kind == .Text {
        let t = str.trim(v.s)
        if str.compare_ascii_fold(t, "true") == 0i32 || str.eq(t, "1") || str.compare_ascii_fold(t, "yes") == 0i32 { ret true }
        if str.compare_ascii_fold(t, "false") == 0i32 || str.eq(t, "0") || str.compare_ascii_fold(t, "no") == 0i32 || t.len == 0usize { ret false }
        ret true
    }
    if v.kind == .Date { ret true }
    if v.kind == .Record { ret true }
    ret v.items.len > 0usize
}

// A date value (or blank, or an error): text must be ISO-8601, a number is milliseconds.
fn to_date(a: *mem.Arena, v: Value) -> Value {
    if v.kind == .Error { ret v }
    if is_blank(v) { ret blank() }
    if v.kind == .Date {
        if v.n != v.n { ret value_error("Invalid date") }
        ret v
    }
    if v.kind == .Number {
        if v.n != v.n || v.n > 8640000000000000.0f64 || v.n < -8640000000000000.0f64 { ret value_error("Invalid date") }
        ret date(math.trunc[f64](v.n))
    }
    if v.kind == .Text {
        let (ms, good) = parse_date_text(v.s)
        if good { ret date(ms) }
        ret value_error(join3(a, "Cannot convert \"", v.s, "\" to a date"))
    }
    ret value_error("Wrong type of argument")
}

// --- Equality and order -----------------------------------------------------------------------------------------

// `=` and MATCH: numbers by value, text without regard to case, booleans by truth, dates by instant; mixed kinds
// compare as text.
fn loose_equals(a: *mem.Arena, x: Value, y: Value) -> bool {
    if is_blank(x) && is_blank(y) { ret true }
    if is_blank(x) || is_blank(y) { ret false }
    if x.kind == .Date && y.kind == .Date { ret x.n == y.n }
    if x.kind == .Number && y.kind == .Number { ret x.n == y.n }
    if x.kind == .Bool || y.kind == .Bool { ret to_bool(x) == to_bool(y) }
    if x.kind == .Text && y.kind == .Text { ret str.eq(lower_text(a, x.s), lower_text(a, y.s)) }
    let tx = to_text(a, x)
    let ty = to_text(a, y)
    if tx.kind == .Error || ty.kind == .Error { ret false }
    ret str.eq(tx.s, ty.s)
}

// UTF-16 code unit order of two UTF-8 texts: -1, 0 or 1.
fn compare_utf16(x: str, y: str) -> i32 {
    var ix = utf8.iterator(x)
    var iy = utf8.iterator(y)
    var more = true
    var pending_x: u32 = 0u32
    var pending_y: u32 = 0u32
    var has_x = false
    var has_y = false
    while more {
        var ux = 0u32
        var uy = 0u32
        var got_x = false
        var got_y = false
        if has_x {
            ux = pending_x
            has_x = false
            got_x = true
        } else {
            let (sx, gx) = utf8.iterator_next(&ix)
            got_x = gx
            if gx {
                if sx >= 65536u32 {
                    ux = 55296u32 + ((sx - 65536u32) >> 10u32)
                    pending_x = 56320u32 + ((sx - 65536u32) & 1023u32)
                    has_x = true
                } else {
                    ux = sx
                }
            }
        }
        if has_y {
            uy = pending_y
            has_y = false
            got_y = true
        } else {
            let (sy, gy) = utf8.iterator_next(&iy)
            got_y = gy
            if gy {
                if sy >= 65536u32 {
                    uy = 55296u32 + ((sy - 65536u32) >> 10u32)
                    pending_y = 56320u32 + ((sy - 65536u32) & 1023u32)
                    has_y = true
                } else {
                    uy = sy
                }
            }
        }
        if !got_x && !got_y { ret 0i32 }
        if !got_x { ret -1i32 }
        if !got_y { ret 1i32 }
        if ux != uy {
            if ux < uy { ret -1i32 }
            ret 1i32
        }
    }
    ret 0i32
}

// Ordering for the comparison operators and SORT: a number (<0, 0, >0) in `n`, or an error value.
fn compare_values(a: *mem.Arena, x: Value, y: Value) -> Value {
    if is_blank(x) && is_blank(y) { ret number(0.0f64) }
    if is_blank(x) { ret number(-1.0f64) }
    if is_blank(y) { ret number(1.0f64) }
    if x.kind == .Date && y.kind == .Date { ret number(x.n - y.n) }
    if x.kind == .Text && y.kind == .Text && is_iso_temporal(x.s) && is_iso_temporal(y.s) {
        let dx = to_date(a, x)
        let dy = to_date(a, y)
        if dx.kind == .Date && dy.kind == .Date { ret number(dx.n - dy.n) }
    }
    if x.kind == .Number && y.kind == .Number { ret number(x.n - y.n) }
    if x.kind == .Bool && y.kind == .Bool { ret number(x.n - y.n) }
    let tx = to_text(a, x)
    if tx.kind == .Error { ret tx }
    let ty = to_text(a, y)
    if ty.kind == .Error { ret ty }
    ret number(f64(compare_utf16(tx.s, ty.s)))
}

// The numbers of an argument list, flattened, with blanks and unconvertible text skipped; an error value in the
// arguments is returned in `failure` (the first one met).
fn collect_numbers(a: *mem.Arena, args: []const Value, out: []f64) -> (usize, Value) {
    var n = 0usize
    var i = 0usize
    while i < args.len {
        let (count, failure) = collect_into(a, args[i], out, n)
        if failure.kind == .Error { ret (count, failure) }
        n = count
        i += 1usize
    }
    ret (n, blank())
}

fn collect_into(a: *mem.Arena, v: Value, out: []f64, at: usize) -> (usize, Value) {
    if v.kind == .Error { ret (at, v) }
    if is_blank(v) { ret (at, blank()) }
    if v.kind == .Array {
        var n = at
        var i = 0usize
        while i < v.items.len {
            let (count, failure) = collect_into(a, v.items[i], out, n)
            if failure.kind == .Error { ret (count, failure) }
            n = count
            i += 1usize
        }
        ret (n, blank())
    }
    let converted = to_number(a, v)
    if converted.kind == .Error { ret (at, blank()) }
    if converted.kind == .Blank { ret (at, blank()) }
    if at < out.len { out[at] = converted.n }
    ret (at + 1usize, blank())
}

// Nested arrays flattened into one list, blanks kept; `out` receives up to its length and the count is returned.
fn flatten_values(args: []const Value, out: []Value, at: usize) -> usize {
    var n = at
    var i = 0usize
    while i < args.len {
        if args[i].kind == .Array {
            n = flatten_values(args[i].items, out, n)
        } else {
            if n < out.len { out[n] = args[i] }
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

// JavaScript's `%` on numbers: the remainder with the sign of the dividend, computed exactly.
fn fmod(x: f64, y: f64) -> f64 {
    let xb = mem.bitcast[u64](x)
    let yb = mem.bitcast[u64](y)
    var ex = i64((xb >> 52u64) & 2047u64)
    var ey = i64((yb >> 52u64) & 2047u64)
    let sx = xb >> 63u64
    var uxi = xb
    var uyi = yb
    if (yb << 1u64) == 0u64 || y != y || ex == 2047i64 { ret nan() }
    if (uxi << 1u64) <= (uyi << 1u64) {
        if (uxi << 1u64) == (uyi << 1u64) { ret 0.0f64 * x }
        ret x
    }
    if ex == 0i64 {
        var i = uxi << 12u64
        while (i >> 63u64) == 0u64 {
            ex -= 1i64
            i = i << 1u64
        }
        uxi = uxi << u64(0i64 - ex + 1i64)
    } else {
        uxi = uxi & 4503599627370495u64
        uxi = uxi | 4503599627370496u64
    }
    if ey == 0i64 {
        var i = uyi << 12u64
        while (i >> 63u64) == 0u64 {
            ey -= 1i64
            i = i << 1u64
        }
        uyi = uyi << u64(0i64 - ey + 1i64)
    } else {
        uyi = uyi & 4503599627370495u64
        uyi = uyi | 4503599627370496u64
    }
    while ex > ey {
        let i = uxi -% uyi
        if (i >> 63u64) == 0u64 {
            if i == 0u64 { ret 0.0f64 * x }
            uxi = i
        }
        uxi = uxi << 1u64
        ex -= 1i64
    }
    let last = uxi -% uyi
    if (last >> 63u64) == 0u64 {
        if last == 0u64 { ret 0.0f64 * x }
        uxi = last
    }
    while (uxi >> 52u64) == 0u64 {
        uxi = uxi << 1u64
        ex -= 1i64
    }
    if ex > 0i64 {
        uxi = uxi -% 4503599627370496u64
        uxi = uxi | (u64(ex) << 52u64)
    } else {
        uxi = uxi >> u64(0i64 - ex + 1i64)
    }
    uxi = uxi | (sx << 63u64)
    ret mem.bitcast[f64](uxi)
}
// --- Diagnostics ------------------------------------------------------------------------------------------------

// What a failed tokenize or parse says: a message and the position of the problem, counted in UTF-16 code units
// as JavaScript counts. `complexity` marks the refusal of a formula over the node cap (a resource limit, not a
// typo): `evaluate` answers it with `#LIMIT!`, not `#ERROR!`.
type Diag = struct { good: bool, message: str, offset: usize, complexity: bool }

// The offset of a lexical error, which carries none (JavaScript's tokenizer error has no position field).
fn no_offset() -> usize { ret 18446744073709551615usize }

fn diag_ok() -> Diag { ret Diag { good: true, message: "", offset: 0usize, complexity: false } }

// The UTF-16 offset of byte `pos` in `src`.
fn utf16_offset(src: str, pos: usize) -> usize {
    var units = 0usize
    var off = 0usize
    while off < pos && off < src.len {
        let (d, d_error) = utf8.decode(src, off)
        if d_error != ok {
            off += 1usize
            units += 1usize
        } else {
            off += usize(d.width)
            units += 1usize
            if d.scalar >= 65536u32 { units += 1usize }
        }
    }
    ret units
}

// --- Tokens -----------------------------------------------------------------------------------------------------

const T_NUMBER: u8 = 0u8
const T_STRING: u8 = 1u8
const T_BOOL: u8 = 2u8
const T_NULL: u8 = 3u8
const T_IDENT: u8 = 4u8
const T_FIELD: u8 = 5u8
const T_OP: u8 = 6u8
const T_PUNCT: u8 = 7u8
const T_EOF: u8 = 8u8

type Token = struct { kind: u8, s: str, n: f64, b: bool, pos: usize }

fn is_ident_start(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 36u8 }

fn is_ident_part(c: u8) -> bool { ret is_ident_start(c) || is_digit(c) || c == 46u8 }

fn is_ws(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 13u8 || c == 10u8 }

// The text of a number literal as JavaScript's `Number()` reads it: a literal with an exponent marker and no digits
// is NaN.
fn literal_value(a: *mem.Arena, s: str) -> f64 {
    var buffer: [80]u8 = zero
    if s.len == 0usize || s.len > 70usize { ret nan() }
    var n = 0usize
    var i = 0usize
    if s[0usize] == 46u8 {
        buffer[n] = 48u8
        n += 1usize
    }
    while i < s.len {
        let c = s[i]
        buffer[n] = c
        n += 1usize
        if c == 46u8 && (i + 1usize == s.len || s[i + 1usize] == 101u8 || s[i + 1usize] == 69u8) {
            buffer[n] = 48u8
            n += 1usize
        }
        i += 1usize
    }
    let (v, good) = parse_number_text(buffer[0usize..n])
    if !good { ret nan() }
    ret v
}

// The tokens of `src`, the last of them `T_EOF`; or the first lexical error.
fn tokenize(a: *mem.Arena, src: str) -> ([]Token, Diag) {
    var none: []Token = zero
    let (tokens, tokens_error) = mem.alloc[Token](a, src.len + 1usize)
    if tokens_error != ok { ret (none, Diag { good: false, message: "Out of memory", offset: 0usize, complexity: false }) }
    var count = 0usize
    var i = 0usize
    let n = src.len
    while i < n {
        let c = src[i]
        if is_ws(c) {
            i += 1usize
        } else if c == 47u8 && i + 1usize < n && src[i + 1usize] == 47u8 {
            i += 2usize
            while i < n && src[i] != 10u8 { i += 1usize }
        } else if c == 123u8 {
            let start = i
            i += 1usize
            let body = i
            while i < n && src[i] != 125u8 { i += 1usize }
            if i >= n { ret (none, Diag { good: false, message: "Unterminated field reference {\xE2\x80\xA6}", offset: no_offset(), complexity: false }) }
            tokens[count] = Token { kind: T_FIELD, s: str.trim(src[body..i]), n: 0.0f64, b: false, pos: start }
            count += 1usize
            i += 1usize
        } else if c == 34u8 || c == 39u8 {
            let quote = c
            let start = i
            i += 1usize
            let (buffer, buffer_error) = mem.alloc[u8](a, n - i + 1usize)
            if buffer_error != ok { ret (none, Diag { good: false, message: "Out of memory", offset: 0usize, complexity: false }) }
            var w = 0usize
            while i < n && src[i] != quote {
                if src[i] == 92u8 {
                    if i + 1usize >= n {
                        // JavaScript appends the text "undefined" for a backslash at the very end.
                        i += 2usize
                    } else {
                        let next = src[i + 1usize]
                        if next == 110u8 {
                            buffer[w] = 10u8
                        } else if next == 116u8 {
                            buffer[w] = 9u8
                        } else if next == 114u8 {
                            buffer[w] = 13u8
                        } else {
                            buffer[w] = next
                        }
                        w += 1usize
                        i += 2usize
                    }
                } else {
                    buffer[w] = src[i]
                    w += 1usize
                    i += 1usize
                }
            }
            if i >= n { ret (none, Diag { good: false, message: "Unterminated string literal", offset: no_offset(), complexity: false }) }
            i += 1usize
            tokens[count] = Token { kind: T_STRING, s: buffer[0usize..w], n: 0.0f64, b: false, pos: start }
            count += 1usize
        } else if is_digit(c) || (c == 46u8 && i + 1usize < n && is_digit(src[i + 1usize])) {
            let start = i
            while i < n && is_digit(src[i]) { i += 1usize }
            if i < n && src[i] == 46u8 {
                i += 1usize
                while i < n && is_digit(src[i]) { i += 1usize }
            }
            if i < n && (src[i] == 101u8 || src[i] == 69u8) {
                i += 1usize
                if i < n && (src[i] == 43u8 || src[i] == 45u8) { i += 1usize }
                while i < n && is_digit(src[i]) { i += 1usize }
            }
            tokens[count] = Token { kind: T_NUMBER, s: src[start..i], n: literal_value(a, src[start..i]), b: false, pos: start }
            count += 1usize
        } else if is_ident_start(c) {
            let start = i
            while i < n && is_ident_part(src[i]) { i += 1usize }
            let word = src[start..i]
            if str.compare_ascii_fold(word, "true") == 0i32 {
                tokens[count] = Token { kind: T_BOOL, s: word, n: 0.0f64, b: true, pos: start }
            } else if str.compare_ascii_fold(word, "false") == 0i32 {
                tokens[count] = Token { kind: T_BOOL, s: word, n: 0.0f64, b: false, pos: start }
            } else if str.compare_ascii_fold(word, "null") == 0i32 {
                tokens[count] = Token { kind: T_NULL, s: word, n: 0.0f64, b: false, pos: start }
            } else {
                tokens[count] = Token { kind: T_IDENT, s: word, n: 0.0f64, b: false, pos: start }
            }
            count += 1usize
        } else {
            var two = false
            if i + 1usize < n {
                let d = src[i + 1usize]
                two = (c == 60u8 && (d == 62u8 || d == 61u8)) || (c == 62u8 && d == 61u8) || (c == 61u8 && d == 61u8) || (c == 33u8 && d == 61u8) || (c == 38u8 && d == 38u8) || (c == 124u8 && d == 124u8)
            }
            if two {
                tokens[count] = Token { kind: T_OP, s: src[i..i + 2usize], n: 0.0f64, b: false, pos: i }
                count += 1usize
                i += 2usize
            } else if c == 43u8 || c == 45u8 || c == 42u8 || c == 47u8 || c == 37u8 || c == 94u8 || c == 38u8 || c == 61u8 || c == 60u8 || c == 62u8 || c == 33u8 {
                tokens[count] = Token { kind: T_OP, s: src[i..i + 1usize], n: 0.0f64, b: false, pos: i }
                count += 1usize
                i += 1usize
            } else if c == 40u8 || c == 41u8 || c == 44u8 || c == 91u8 || c == 93u8 || c == 63u8 || c == 58u8 {
                tokens[count] = Token { kind: T_PUNCT, s: src[i..i + 1usize], n: 0.0f64, b: false, pos: i }
                count += 1usize
                i += 1usize
            } else {
                // The character as JavaScript names it: one code point (two UTF-16 units for an astral one).
                var width = 1usize
                var shown = src[i..i + 1usize]
                let (d, d_error) = utf8.decode(src, i)
                if d_error == ok {
                    width = usize(d.width)
                    shown = src[i..i + width]
                    // JavaScript names the first half of a surrogate pair, which text can only carry as U+FFFD.
                    if d.scalar >= 65536u32 { shown = "\xEF\xBF\xBD" }
                }
                let message = join(a, join(a, "Unexpected character '", shown), join(a, "' at position ", number_text(a, f64(utf16_offset(src, i)))))
                ret (none, Diag { good: false, message: message, offset: no_offset(), complexity: false })
            }
        }
    }
    tokens[count] = Token { kind: T_EOF, s: "", n: 0.0f64, b: false, pos: n }
    count += 1usize
    ret (tokens[0usize..count], diag_ok())
}

// --- The syntax tree and the parser -----------------------------------------------------------------------------

type NodeKind = enum u8 { Number, String, Bool, Null, Field, Name, Call, Unary, Binary, Ternary, Array }

// A node. A number has `n`; a string `s`; a boolean `b`; a field or name `s`; a call `s` (the function name as
// written) and its arguments in `kids`; a unary or binary node `op` (the operator as written) and its operands;
// a ternary node condition, then and else in `kids`; an array literal its elements.
type Node = struct { kind: NodeKind, n: f64, s: str, b: bool, op: str, kids: []const Node }

fn leaf(kind: NodeKind) -> Node { ret Node { kind: kind, n: 0.0f64, s: "", b: false, op: "", kids: zero_nodes() } }

fn zero_nodes() -> []const Node {
    var none: []const Node = zero
    ret none
}

type Parser = struct { a: *mem.Arena, src: str, tokens: []const Token, at: usize, failed: bool, message: str, pos: usize }

fn fail(p: *Parser, message: str, pos: usize) {
    if !p.failed {
        p.failed = true
        p.message = message
        p.pos = pos
    }
}

fn describe(p: *Parser, t: Token) -> str {
    if t.kind == T_EOF { ret "end of formula" }
    if t.kind == T_NUMBER { ret number_text(p.a, t.n) }
    if t.kind == T_NULL { ret "null" }
    if t.kind == T_BOOL {
        if t.b { ret "true" }
        ret "false"
    }
    ret t.s
}

fn peek(p: *Parser) -> Token { ret p.tokens[p.at] }

fn is_op(p: *Parser, v: str) -> bool {
    let t = p.tokens[p.at]
    ret t.kind == T_OP && str.eq(t.s, v)
}

fn is_punct(p: *Parser, v: str) -> bool {
    let t = p.tokens[p.at]
    ret t.kind == T_PUNCT && str.eq(t.s, v)
}

fn expect_punct(p: *Parser, v: str) {
    if is_punct(p, v) {
        p.at += 1usize
        ret
    }
    let t = p.tokens[p.at]
    fail(p, join(p.a, join(p.a, join(p.a, "Expected '", v), "' but found '"), join(p.a, describe(p, t), "'")), t.pos)
}

fn node2(p: *Parser, kind: NodeKind, op: str, left: Node, right: Node) -> Node {
    let (kids, e) = mem.alloc[Node](p.a, 2usize)
    if e != ok {
        fail(p, "Out of memory", 0usize)
        ret leaf(kind)
    }
    kids[0usize] = left
    kids[1usize] = right
    ret Node { kind: kind, n: 0.0f64, s: "", b: false, op: op, kids: kids }
}

fn parse_ternary(p: *Parser) -> Node {
    let cond = parse_or(p)
    if p.failed { ret cond }
    if is_punct(p, "?") {
        p.at += 1usize
        let then = parse_ternary_entry(p)
        if p.failed { ret then }
        expect_punct(p, ":")
        if p.failed { ret then }
        let alt = parse_ternary_entry(p)
        if p.failed { ret alt }
        let (kids, e) = mem.alloc[Node](p.a, 3usize)
        if e != ok {
            fail(p, "Out of memory", 0usize)
            ret cond
        }
        kids[0usize] = cond
        kids[1usize] = then
        kids[2usize] = alt
        ret Node { kind: .Ternary, n: 0.0f64, s: "", b: false, op: "", kids: kids }
    }
    ret cond
}

fn parse_ternary_entry(p: *Parser) -> Node { ret parse_ternary(p) }

fn parse_or(p: *Parser) -> Node {
    var left = parse_and(p)
    while !p.failed && is_op(p, "||") {
        p.at += 1usize
        let right = parse_and(p)
        if p.failed { ret left }
        left = node2(p, .Binary, "||", left, right)
    }
    ret left
}

fn parse_and(p: *Parser) -> Node {
    var left = parse_comparison(p)
    while !p.failed && is_op(p, "&&") {
        p.at += 1usize
        let right = parse_comparison(p)
        if p.failed { ret left }
        left = node2(p, .Binary, "&&", left, right)
    }
    ret left
}

fn is_comparison_op(t: Token) -> bool {
    if t.kind != T_OP { ret false }
    ret str.eq(t.s, "=") || str.eq(t.s, "==") || str.eq(t.s, "!=") || str.eq(t.s, "<>") || str.eq(t.s, "<") || str.eq(t.s, "<=") || str.eq(t.s, ">") || str.eq(t.s, ">=")
}

fn parse_comparison(p: *Parser) -> Node {
    var left = parse_concat(p)
    while !p.failed && is_comparison_op(peek(p)) {
        let op = peek(p).s
        p.at += 1usize
        let right = parse_concat(p)
        if p.failed { ret left }
        left = node2(p, .Binary, op, left, right)
    }
    ret left
}

fn parse_concat(p: *Parser) -> Node {
    var left = parse_additive(p)
    while !p.failed && is_op(p, "&") {
        p.at += 1usize
        let right = parse_additive(p)
        if p.failed { ret left }
        left = node2(p, .Binary, "&", left, right)
    }
    ret left
}

fn parse_additive(p: *Parser) -> Node {
    var left = parse_multiplicative(p)
    while !p.failed && (is_op(p, "+") || is_op(p, "-")) {
        let op = peek(p).s
        p.at += 1usize
        let right = parse_multiplicative(p)
        if p.failed { ret left }
        left = node2(p, .Binary, op, left, right)
    }
    ret left
}

fn parse_multiplicative(p: *Parser) -> Node {
    var left = parse_exponent(p)
    while !p.failed && (is_op(p, "*") || is_op(p, "/") || is_op(p, "%")) {
        let op = peek(p).s
        p.at += 1usize
        let right = parse_exponent(p)
        if p.failed { ret left }
        left = node2(p, .Binary, op, left, right)
    }
    ret left
}

fn parse_exponent(p: *Parser) -> Node {
    let left = parse_unary(p)
    if p.failed { ret left }
    if is_op(p, "^") {
        p.at += 1usize
        let right = parse_exponent(p)
        if p.failed { ret left }
        ret node2(p, .Binary, "^", left, right)
    }
    ret left
}

fn parse_unary(p: *Parser) -> Node {
    if is_op(p, "-") || is_op(p, "+") || is_op(p, "!") {
        let op = peek(p).s
        p.at += 1usize
        let operand = parse_unary(p)
        if p.failed { ret operand }
        let (kids, e) = mem.alloc[Node](p.a, 1usize)
        if e != ok {
            fail(p, "Out of memory", 0usize)
            ret operand
        }
        kids[0usize] = operand
        ret Node { kind: .Unary, n: 0.0f64, s: "", b: false, op: op, kids: kids }
    }
    ret parse_primary(p)
}

// The arguments between `open` and `close`; a trailing comma is tolerated.
fn parse_arg_list(p: *Parser, open: str, close: str) -> []const Node {
    expect_punct(p, open)
    if p.failed { ret zero_nodes() }
    // Collected into a growing buffer, then trimmed.
    var capacity = 8usize
    let (first, first_error) = mem.alloc[Node](p.a, capacity)
    if first_error != ok {
        fail(p, "Out of memory", 0usize)
        ret zero_nodes()
    }
    var items = first
    var count = 0usize
    if is_punct(p, close) {
        p.at += 1usize
        ret zero_nodes()
    }
    var more = true
    var first_arg = true
    while more && !p.failed {
        if !first_arg {
            // after a comma
            if is_punct(p, close) {
                more = false
            }
        }
        if more {
            let item = parse_ternary(p)
            if p.failed { ret zero_nodes() }
            if count == capacity {
                let (grown, grown_error) = mem.alloc[Node](p.a, capacity * 2usize)
                if grown_error != ok {
                    fail(p, "Out of memory", 0usize)
                    ret zero_nodes()
                }
                var k = 0usize
                while k < count {
                    grown[k] = items[k]
                    k += 1usize
                }
                items = grown
                capacity = capacity * 2usize
            }
            items[count] = item
            count += 1usize
            first_arg = false
            if is_punct(p, ",") {
                p.at += 1usize
            } else {
                more = false
            }
        }
    }
    expect_punct(p, close)
    if p.failed { ret zero_nodes() }
    ret items[0usize..count]
}

fn parse_primary(p: *Parser) -> Node {
    let t = peek(p)
    if t.kind == T_NUMBER {
        p.at += 1usize
        var node = leaf(.Number)
        node.n = t.n
        ret node
    }
    if t.kind == T_STRING {
        p.at += 1usize
        var node = leaf(.String)
        node.s = t.s
        ret node
    }
    if t.kind == T_BOOL {
        p.at += 1usize
        var node = leaf(.Bool)
        node.b = t.b
        ret node
    }
    if t.kind == T_NULL {
        p.at += 1usize
        ret leaf(.Null)
    }
    if t.kind == T_FIELD {
        p.at += 1usize
        var node = leaf(.Field)
        node.s = t.s
        ret node
    }
    if t.kind == T_IDENT {
        p.at += 1usize
        if is_punct(p, "(") {
            let args = parse_arg_list(p, "(", ")")
            var node = leaf(.Call)
            node.s = t.s
            node.kids = args
            ret node
        }
        var node = leaf(.Name)
        node.s = t.s
        ret node
    }
    if t.kind == T_PUNCT && str.eq(t.s, "(") {
        p.at += 1usize
        let inner = parse_ternary(p)
        if p.failed { ret inner }
        expect_punct(p, ")")
        ret inner
    }
    if t.kind == T_PUNCT && str.eq(t.s, "[") {
        let elements = parse_arg_list(p, "[", "]")
        var node = leaf(.Array)
        node.kids = elements
        ret node
    }
    fail(p, join3(p.a, "Unexpected '", describe(p, t), "'"), t.pos)
    ret leaf(.Null)
}

fn count_nodes(node: Node) -> usize {
    var n = 1usize
    var i = 0usize
    while i < node.kids.len {
        n += count_nodes(node.kids[i])
        i += 1usize
    }
    ret n
}

// Parse formula source into a tree. `max_nodes` caps the node count (0 is the default, 10,000); a longer formula
// is refused with `complexity` set.
fn parse(a: *mem.Arena, source: str, max_nodes: usize) -> (Node, Diag) {
    let (tokens, tokenize_diag) = tokenize(a, source)
    if !tokenize_diag.good { ret (leaf(.Null), tokenize_diag) }
    var p = Parser { a: a, src: source, tokens: tokens, at: 0usize, failed: false, message: "", pos: 0usize }
    if tokens[0usize].kind == T_EOF { ret (leaf(.Null), Diag { good: false, message: "Empty formula", offset: 0usize, complexity: false }) }
    let node = parse_ternary(&p)
    if p.failed { ret (node, Diag { good: false, message: p.message, offset: utf16_offset(source, p.pos), complexity: false }) }
    if tokens[p.at].kind != T_EOF {
        let t = tokens[p.at]
        let message = join3(a, "Unexpected '", describe(&p, t), "' after expression")
        ret (node, Diag { good: false, message: message, offset: utf16_offset(source, t.pos), complexity: false })
    }
    var cap = max_nodes
    if cap == 0usize { cap = 10000usize }
    if count_nodes(node) > cap { ret (node, Diag { good: false, message: "Formula exceeds maximum complexity", offset: 0usize, complexity: true }) }
    ret (node, diag_ok())
}

// The distinct field and bare-name references of a tree, in the order first met, for the dependency graph.
fn collect_references(a: *mem.Arena, node: Node) -> []const str {
    var none: []const str = zero
    let total = count_nodes(node)
    let (names, e) = mem.alloc[str](a, total)
    if e != ok { ret none }
    var n = 0usize
    n = collect_into_names(node, names, n)
    ret names[0usize..n]
}

fn collect_into_names(node: Node, names: []str, at: usize) -> usize {
    var n = at
    if node.kind == .Field || node.kind == .Name {
        var seen = false
        var i = 0usize
        while i < n {
            if str.eq(names[i], node.s) { seen = true }
            i += 1usize
        }
        if !seen {
            names[n] = node.s
            n += 1usize
        }
    }
    var k = 0usize
    while k < node.kids.len {
        n = collect_into_names(node.kids[k], names, n)
        k += 1usize
    }
    ret n
}
// --- The registry -----------------------------------------------------------------------------------------------

error Collision
error RegistryFull

// What a handler is given. `args` are the evaluated arguments of an eager function; a `lazy` function gets `nodes`
// instead and evaluates them with `eval_node` under `scope`.
type Call = struct { ev: *Evaluator, entry: *const Entry, args: []const Value, nodes: []const Node, scope: *const Scope, has_scope: bool, a: *mem.Arena }

type Handler = fn(*Call) -> Value

type Entry = struct {
    name: str,
    key: str,
    aliases: []const str,
    category: str,
    lazy: bool,
    pass_errors: bool,
    volatile_fn: bool,
    generate_once: bool,
    min_args: i32,
    max_args: i32,
    handler: Handler,
}

type Registry = struct { entries: []Entry, keys: []str, count: usize, key_count: usize, owners: []usize }

// A name for lookup: upper case with underscores removed.
fn normalize_name(a: *mem.Arena, name: str) -> str {
    let (out, e) = mem.alloc[u8](a, name.len)
    if e != ok { ret name }
    var n = 0usize
    var i = 0usize
    while i < name.len {
        var c = name[i]
        if c == 95u8 {
            i += 1usize
        } else {
            if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
            out[n] = c
            n += 1usize
            i += 1usize
        }
    }
    ret out[0usize..n]
}

// An empty registry for up to `capacity` functions (counting each alias as a name).
fn registry(a: *mem.Arena, capacity: usize) -> (Registry, err) {
    var r: Registry = zero
    let (entries, entries_error) = mem.alloc[Entry](a, capacity)
    if entries_error != ok { ret (r, entries_error) }
    let (keys, keys_error) = mem.alloc[str](a, capacity * 3usize)
    if keys_error != ok { ret (r, keys_error) }
    let (owners, owners_error) = mem.alloc[usize](a, capacity * 3usize)
    if owners_error != ok { ret (r, owners_error) }
    r.entries = entries
    r.keys = keys
    r.owners = owners
    ret (r, ok)
}

fn find_key(r: *const Registry, key: str) -> usize {
    var i = 0usize
    while i < r.key_count {
        if str.eq(r.keys[i], key) { ret i }
        i += 1usize
    }
    ret r.key_count
}

// Add a function under its name and aliases. A name already taken is `Collision`.
fn register(r: *Registry, a: *mem.Arena, entry: Entry) -> err {
    if r.count >= r.entries.len { ret RegistryFull }
    var e = entry
    // The canonical name is upper case.
    let (upper, upper_error) = mem.alloc[u8](a, entry.name.len)
    if upper_error != ok { ret upper_error }
    var i = 0usize
    while i < entry.name.len {
        var c = entry.name[i]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        upper[i] = c
        i += 1usize
    }
    e.name = upper[0usize..entry.name.len]
    e.key = normalize_name(a, e.name)
    if find_key(r, e.key) < r.key_count { ret Collision }
    var k = 0usize
    while k < entry.aliases.len {
        let alias_key = normalize_name(a, entry.aliases[k])
        if find_key(r, alias_key) < r.key_count && !str.eq(alias_key, e.key) { ret Collision }
        k += 1usize
    }
    if r.key_count + 1usize + entry.aliases.len > r.keys.len { ret RegistryFull }
    r.entries[r.count] = e
    r.keys[r.key_count] = e.key
    r.owners[r.key_count] = r.count
    r.key_count += 1usize
    k = 0usize
    while k < entry.aliases.len {
        let alias_key = normalize_name(a, entry.aliases[k])
        if find_key(r, alias_key) >= r.key_count {
            r.keys[r.key_count] = alias_key
            r.owners[r.key_count] = r.count
            r.key_count += 1usize
        }
        k += 1usize
    }
    r.count += 1usize
    ret ok
}

// The entry a (possibly aliased, any-case, underscored) name resolves to.
fn resolve(a: *mem.Arena, r: *const Registry, name: str) -> (usize, bool) {
    let mark = mem.mark(a)
    let key = normalize_name(a, name)
    let at = find_key(r, key)
    mem.reset(a, mark)
    if at >= r.key_count { ret (0usize, false) }
    ret (r.owners[at], true)
}

fn entry_at(r: *const Registry, index: usize) -> *const Entry { ret &r.entries[index] }

// `min`/`max` argument check: an empty string when the count is fine, else the message.
fn check_arity(a: *mem.Arena, entry: *const Entry, count: usize) -> str {
    let low = entry.min_args
    if i64(count) < i64(low) {
        let m1 = join3(a, entry.name, " expects at least ", number_text(a, f64(low)))
        ret join3(a, m1, " argument(s), got ", number_text(a, f64(count)))
    }
    if entry.max_args != -1i32 && i64(count) > i64(entry.max_args) {
        let m1 = join3(a, entry.name, " expects at most ", number_text(a, f64(entry.max_args)))
        ret join3(a, m1, " argument(s), got ", number_text(a, f64(count)))
    }
    ret ""
}

// --- The evaluator ----------------------------------------------------------------------------------------------

// A `let` binding: the variable, its value, and the scope outside it.
type Scope = struct { name: str, value: Value, parent: *const Scope, has_parent: bool }

type Field = struct { name: str, value: Value }

// A formula field's source text.
type Formula = struct { name: str, source: str }

type FieldGetter = fn(*void, str) -> (Value, bool)

// The evaluation context. `fields` are the host's cell values by display name (matched exactly, then without
// regard to case); `get_field` overrides them when set. `formulas` are the other formula fields beside this one
// and `field_name` the one being evaluated, which is what lets a cycle be named. `now` is the clock for the
// volatile functions, in milliseconds since the epoch; `user` is for the host's own handlers. `host` holds the
// host's named values for the reference functions (rowId, tableId, appId, realmId, userId, createdOn, updatedOn,
// createdBy, updatedBy, browserAgent, currentUser, userName); `prior` and `changed` are the record before the
// change, for ISCHANGED and PRIORVALUE, `is_new` is ISNEW and `meta` the field configuration for PROPERTY. A zero
// `max_steps` is 2,000,000 and a zero `max_nodes` 10,000.
type Context = struct {
    fields: []const Field,
    get_field: FieldGetter,
    has_get_field: bool,
    get_user: *void,
    formulas: []const Formula,
    field_name: str,
    has_field_name: bool,
    max_steps: usize,
    max_nodes: usize,
    strict_refs: bool,
    now: f64,
    has_now: bool,
    random_seed: u64,
    user: *void,
    host: []const Field,
    prior: []const Field,
    has_prior: bool,
    changed: []const str,
    has_changed: bool,
    is_new: bool,
    meta: []const FieldMeta,
}

// The configured properties of one field, for PROPERTY and PROPERTIES.
type FieldMeta = struct { field: str, props: []const Field }

type Cached = struct { name: str, node: Node, parsed: bool }

type Evaluator = struct {
    a: *mem.Arena,
    reg: *const Registry,
    ctx: *const Context,
    steps: usize,
    max_steps: usize,
    aborted: bool,
    resolving: []str,
    resolving_count: usize,
    cache: []Cached,
    cache_count: usize,
    empty: Scope,
    rng: u64,
}

fn evaluator(a: *mem.Arena, reg: *const Registry, ctx: *const Context) -> Evaluator {
    var ev: Evaluator = zero
    ev.a = a
    ev.reg = reg
    ev.ctx = ctx
    ev.max_steps = ctx.max_steps
    ev.rng = ctx.random_seed
    if ev.rng == 0u64 { ev.rng = 88172645463325252u64 }
    if ev.max_steps == 0usize { ev.max_steps = 2000000usize }
    let (stack, stack_error) = mem.alloc[str](a, 64usize)
    if stack_error == ok { ev.resolving = stack }
    let (cache, cache_error) = mem.alloc[Cached](a, 16usize)
    if cache_error == ok { ev.cache = cache }
    if ctx.has_field_name && ctx.field_name.len > 0usize && ev.resolving.len > 0usize {
        ev.resolving[0usize] = ctx.field_name
        ev.resolving_count = 1usize
    }
    ret ev
}

// One step of the budget; false once it is spent (and then always).
fn tick(ev: *Evaluator) -> bool {
    ev.steps += 1usize
    if ev.steps > ev.max_steps {
        ev.aborted = true
        ret false
    }
    ret true
}

fn budget_error() -> Value { ret limit_error("Evaluation budget exceeded") }

// Evaluate a node under `scope` (`has_scope` false for none).
fn eval(ev: *Evaluator, node: Node, scope: *const Scope, has_scope: bool) -> Value {
    if !tick(ev) { ret budget_error() }
    if node.kind == .Number { ret number(node.n) }
    if node.kind == .String { ret text(node.s) }
    if node.kind == .Bool { ret boolean(node.b) }
    if node.kind == .Null { ret blank() }
    if node.kind == .Array {
        if node.kids.len == 0usize { ret array(zero_items()) }
        let (items, e) = mem.alloc[Value](ev.a, node.kids.len)
        if e != ok { ret generic_error("Out of memory") }
        var i = 0usize
        while i < node.kids.len {
            items[i] = eval(ev, node.kids[i], scope, has_scope)
            i += 1usize
        }
        ret array(items)
    }
    if node.kind == .Field { ret resolve_field(ev, node.s) }
    if node.kind == .Name { ret resolve_name(ev, node.s, scope, has_scope) }
    if node.kind == .Unary { ret eval_unary(ev, node, scope, has_scope) }
    if node.kind == .Binary { ret eval_binary(ev, node, scope, has_scope) }
    if node.kind == .Ternary {
        let cond = eval(ev, node.kids[0usize], scope, has_scope)
        if is_error(cond) { ret cond }
        if to_bool(cond) { ret eval(ev, node.kids[1usize], scope, has_scope) }
        ret eval(ev, node.kids[2usize], scope, has_scope)
    }
    ret eval_call(ev, node, scope, has_scope)
}

// Evaluate one argument node of a lazy function.
fn eval_node(c: *Call, node: Node) -> Value {
    ret eval(c.ev, node, c.scope, c.has_scope)
}

fn resolving_index(ev: *Evaluator, name: str) -> usize {
    var i = 0usize
    while i < ev.resolving_count {
        if str.compare_ascii_fold(ev.resolving[i], name) == 0i32 { ret i }
        i += 1usize
    }
    ret ev.resolving_count
}

fn formula_index(ev: *Evaluator, name: str) -> usize {
    var i = 0usize
    while i < ev.ctx.formulas.len {
        if str.eq(ev.ctx.formulas[i].name, name) { ret i }
        i += 1usize
    }
    i = 0usize
    while i < ev.ctx.formulas.len {
        if str.compare_ascii_fold(ev.ctx.formulas[i].name, name) == 0i32 { ret i }
        i += 1usize
    }
    ret ev.ctx.formulas.len
}

// Whether `value` is "found": the second result of a lookup.
fn lookup_field(ev: *Evaluator, name: str) -> (Value, bool) {
    if ev.ctx.has_get_field {
        let (v, found) = ev.ctx.get_field(ev.ctx.get_user, name)
        ret (v, found)
    }
    var i = 0usize
    while i < ev.ctx.fields.len {
        if str.eq(ev.ctx.fields[i].name, name) { ret (ev.ctx.fields[i].value, true) }
        i += 1usize
    }
    i = 0usize
    while i < ev.ctx.fields.len {
        if str.compare_ascii_fold(ev.ctx.fields[i].name, name) == 0i32 { ret (ev.ctx.fields[i].value, true) }
        i += 1usize
    }
    ret (blank(), false)
}

fn circular_error(ev: *Evaluator, from: usize, name: str) -> Value {
    var path = ""
    var i = from
    while i < ev.resolving_count {
        if i > from { path = join(ev.a, path, " \xE2\x86\x92 ") }
        path = join(ev.a, path, ev.resolving[i])
        i += 1usize
    }
    path = join(ev.a, join(ev.a, path, " \xE2\x86\x92 "), ev.resolving[from])
    ret ref_error(join(ev.a, "Circular reference: ", path))
}

fn push_name(ev: *Evaluator, name: str) {
    if ev.resolving_count < ev.resolving.len {
        ev.resolving[ev.resolving_count] = name
        ev.resolving_count += 1usize
    }
}

fn pop_name(ev: *Evaluator) {
    if ev.resolving_count > 0usize { ev.resolving_count -= 1usize }
}

// A sibling formula evaluated with its name on the resolution stack.
fn eval_formula(ev: *Evaluator, name: str, source: str) -> Value {
    var cached = ev.cache_count
    var i = 0usize
    while i < ev.cache_count {
        if str.eq(ev.cache[i].name, name) { cached = i }
        i += 1usize
    }
    if cached == ev.cache_count {
        let (node, diag) = parse(ev.a, source, ev.ctx.max_nodes)
        if !diag.good { ret generic_error(diag.message) }
        if ev.cache_count < ev.cache.len {
            ev.cache[ev.cache_count] = Cached { name: name, node: node, parsed: true }
            ev.cache_count += 1usize
        }
        push_name(ev, name)
        let result = eval(ev, node, &ev.empty, false)
        pop_name(ev)
        ret result
    }
    push_name(ev, ev.cache[cached].name)
    let result = eval(ev, ev.cache[cached].node, &ev.empty, false)
    pop_name(ev)
    ret result
}

// The value of one cell (cycle-aware): `found` is false when no field or formula answers to the name.
fn resolve_cell(ev: *Evaluator, name: str) -> (Value, bool) {
    let at = resolving_index(ev, name)
    if at < ev.resolving_count { ret (circular_error(ev, at, name), true) }
    let f = formula_index(ev, name)
    if f < ev.ctx.formulas.len {
        let source = ev.ctx.formulas[f].source
        if str.trim(source).len > 0usize { ret (eval_formula(ev, ev.ctx.formulas[f].name, source), true) }
    }
    let (v, found) = lookup_field(ev, name)
    ret (v, found)
}

fn resolve_field(ev: *Evaluator, name: str) -> Value {
    let (v, found) = resolve_cell(ev, name)
    if found { ret v }
    if ev.ctx.strict_refs { ret ref_error(join3(ev.a, "Unknown field \"", name, "\"")) }
    ret blank()
}

fn scope_lookup(scope: *const Scope, has_scope: bool, name: str) -> (Value, bool) {
    if !has_scope { ret (blank(), false) }
    var cur = scope
    var more = true
    while more {
        if str.eq(cur.name, name) { ret (cur.value, true) }
        if cur.has_parent {
            cur = cur.parent
        } else {
            more = false
        }
    }
    ret (blank(), false)
}

fn resolve_name(ev: *Evaluator, name: str, scope: *const Scope, has_scope: bool) -> Value {
    let (bound, is_bound) = scope_lookup(scope, has_scope, name)
    if is_bound { ret bound }
    let (v, found) = resolve_cell(ev, name)
    if found { ret v }
    let (index, known) = resolve(ev.a, ev.reg, name)
    if known {
        let entry = entry_at(ev.reg, index)
        if entry.min_args <= 0i32 { ret invoke(ev, entry, zero_nodes(), scope, has_scope) }
    }
    if ev.ctx.strict_refs { ret ref_error(join3(ev.a, "Unknown reference \"", name, "\"")) }
    ret blank()
}

fn eval_unary(ev: *Evaluator, node: Node, scope: *const Scope, has_scope: bool) -> Value {
    let v = eval(ev, node.kids[0usize], scope, has_scope)
    if is_error(v) { ret v }
    if str.eq(node.op, "-") {
        if is_blank(v) { ret blank() }
        let n = to_number(ev.a, v)
        if is_error(n) { ret n }
        if n.kind == .Blank { ret blank() }
        ret number(0.0f64 - n.n)
    }
    if str.eq(node.op, "+") {
        if is_blank(v) { ret blank() }
        ret to_number(ev.a, v)
    }
    ret boolean(!to_bool(v))
}

fn arithmetic(a: *mem.Arena, op: str, left: Value, right: Value) -> Value {
    if is_blank(left) || is_blank(right) { ret blank() }
    let x = to_number(a, left)
    if is_error(x) { ret x }
    let y = to_number(a, right)
    if is_error(y) { ret y }
    if x.kind == .Blank || y.kind == .Blank { ret blank() }
    if str.eq(op, "+") { ret number(x.n + y.n) }
    if str.eq(op, "-") { ret number(x.n - y.n) }
    if str.eq(op, "*") { ret number(x.n * y.n) }
    if str.eq(op, "/") {
        if y.n == 0.0f64 { ret div_zero() }
        ret number(x.n / y.n)
    }
    if str.eq(op, "%") {
        if y.n == 0.0f64 { ret div_zero() }
        ret number(fmod(x.n, y.n))
    }
    let r = math.pow[f64](x.n, y.n)
    if r != r { ret value_error("Invalid exponentiation") }
    ret number(r)
}

fn eval_binary(ev: *Evaluator, node: Node, scope: *const Scope, has_scope: bool) -> Value {
    let op = node.op
    if str.eq(op, "||") {
        let l = eval(ev, node.kids[0usize], scope, has_scope)
        if is_error(l) { ret l }
        if to_bool(l) { ret boolean(true) }
        let r = eval(ev, node.kids[1usize], scope, has_scope)
        if is_error(r) { ret r }
        ret boolean(to_bool(r))
    }
    if str.eq(op, "&&") {
        let l = eval(ev, node.kids[0usize], scope, has_scope)
        if is_error(l) { ret l }
        if !to_bool(l) { ret boolean(false) }
        let r = eval(ev, node.kids[1usize], scope, has_scope)
        if is_error(r) { ret r }
        ret boolean(to_bool(r))
    }
    let left = eval(ev, node.kids[0usize], scope, has_scope)
    if is_error(left) { ret left }
    let right = eval(ev, node.kids[1usize], scope, has_scope)
    if is_error(right) { ret right }
    if str.eq(op, "&") {
        let tl = to_text(ev.a, left)
        if is_error(tl) { ret tl }
        let tr = to_text(ev.a, right)
        if is_error(tr) { ret tr }
        ret text(join(ev.a, tl.s, tr.s))
    }
    if str.eq(op, "=") || str.eq(op, "==") { ret boolean(loose_equals(ev.a, left, right)) }
    if str.eq(op, "!=") || str.eq(op, "<>") { ret boolean(!loose_equals(ev.a, left, right)) }
    if str.eq(op, "<") || str.eq(op, "<=") || str.eq(op, ">") || str.eq(op, ">=") {
        let c = compare_values(ev.a, left, right)
        if is_error(c) { ret c }
        if str.eq(op, "<") { ret boolean(c.n < 0.0f64) }
        if str.eq(op, "<=") { ret boolean(c.n <= 0.0f64) }
        if str.eq(op, ">") { ret boolean(c.n > 0.0f64) }
        ret boolean(c.n >= 0.0f64)
    }
    ret arithmetic(ev.a, op, left, right)
}

fn eval_call(ev: *Evaluator, node: Node, scope: *const Scope, has_scope: bool) -> Value {
    let (index, known) = resolve(ev.a, ev.reg, node.s)
    if !known { ret name_error(join3(ev.a, "Unknown function \"", node.s, "\"")) }
    let entry = entry_at(ev.reg, index)
    let message = check_arity(ev.a, entry, node.kids.len)
    if message.len > 0usize { ret value_error(message) }
    ret invoke(ev, entry, node.kids, scope, has_scope)
}

fn invoke(ev: *Evaluator, entry: *const Entry, nodes: []const Node, scope: *const Scope, has_scope: bool) -> Value {
    var call = Call { ev: ev, entry: entry, args: zero_items(), nodes: nodes, scope: scope, has_scope: has_scope, a: ev.a }
    if entry.lazy {
        let result = entry.handler(&call)
        if ev.aborted { ret budget_error() }
        ret result
    }
    var args: []Value = zero_items_mut()
    if nodes.len > 0usize {
        let (storage, e) = mem.alloc[Value](ev.a, nodes.len)
        if e != ok { ret generic_error("Out of memory") }
        args = storage
        var i = 0usize
        while i < nodes.len {
            let v = eval(ev, nodes[i], scope, has_scope)
            if ev.aborted { ret budget_error() }
            if is_error(v) && !entry.pass_errors { ret v }
            args[i] = v
            i += 1usize
        }
    }
    call.args = args
    let result = entry.handler(&call)
    if ev.aborted { ret budget_error() }
    ret result
}

fn zero_items_mut() -> []Value {
    var none: []Value = zero
    ret none
}
// --- The language forms LET and LETS ----------------------------------------------------------------------------

// The variable a LET names: a bare name, a `{field}` or a string literal.
fn variable_name(node: Node) -> (str, bool) {
    if node.kind == .Name || node.kind == .Field || node.kind == .String { ret (node.s, true) }
    ret ("", false)
}

fn bind(a: *mem.Arena, parent: *const Scope, has_parent: bool, name: str, value: Value) -> *const Scope {
    let (cell, e) = mem.alloc[Scope](a, 1usize)
    if e != ok { ret parent }
    cell[0usize] = Scope { name: name, value: value, parent: parent, has_parent: has_parent }
    ret &cell[0usize]
}

fn let_handler(c: *Call) -> Value {
    let (name, named) = variable_name(c.nodes[0usize])
    if !named { ret value_error("LET expects a variable name as its first argument") }
    let v = eval_node(c, c.nodes[1usize])
    if is_error(v) { ret v }
    let inner = bind(c.a, c.scope, c.has_scope, name, v)
    ret eval(c.ev, c.nodes[2usize], inner, true)
}

fn lets_handler(c: *Call) -> Value {
    if c.nodes.len % 2usize == 0usize { ret value_error("LETS expects name/value pairs followed by a body expression") }
    var scope = c.scope
    var has = c.has_scope
    var i = 0usize
    while i + 1usize < c.nodes.len {
        let (name, named) = variable_name(c.nodes[i])
        if !named { ret value_error("LETS variable names must be identifiers") }
        let v = eval(c.ev, c.nodes[i + 1usize], scope, has)
        if is_error(v) { ret v }
        scope = bind(c.a, scope, has, name, v)
        has = true
        i += 2usize
    }
    ret eval(c.ev, c.nodes[c.nodes.len - 1usize], scope, has)
}

// Register the language forms `LET` and `LETS` (the rest of the library is registered by the function modules).
fn register_core(r: *Registry, a: *mem.Arena) -> err {
    var none: []const str = zero
    try register(r, a, Entry { name: "LET", key: "", aliases: none, category: "core", lazy: true, pass_errors: false, volatile_fn: false, generate_once: false, min_args: 3i32, max_args: 3i32, handler: let_handler })
    try register(r, a, Entry { name: "LETS", key: "", aliases: none, category: "core", lazy: true, pass_errors: false, volatile_fn: false, generate_once: false, min_args: 3i32, max_args: -1i32, handler: lets_handler })
    ret ok
}

// --- The public functions ---------------------------------------------------------------------------------------

// Evaluate formula source. Never fails: a syntax problem or a runtime one is an error value.
fn evaluate(a: *mem.Arena, source: str, ctx: *const Context, reg: *const Registry) -> Value {
    let (node, diag) = parse(a, source, ctx.max_nodes)
    if !diag.good {
        if diag.complexity { ret limit_error(diag.message) }
        ret generic_error(diag.message)
    }
    ret evaluate_ast(a, node, ctx, reg)
}

fn evaluate_ast(a: *mem.Arena, node: Node, ctx: *const Context, reg: *const Registry) -> Value {
    var ev = evaluator(a, reg, ctx)
    let v = eval(&ev, node, &ev.empty, false)
    if ev.aborted { ret budget_error() }
    ret v
}

// The references of a formula, or its syntax diagnostic.
fn dependencies(a: *mem.Arena, source: str) -> ([]const str, Diag) {
    let (node, diag) = parse(a, source, 0usize)
    var none: []const str = zero
    if !diag.good { ret (none, diag) }
    ret (collect_references(a, node), diag)
}

fn has_formula(formulas: []const Formula, name: str) -> bool {
    var i = 0usize
    while i < formulas.len {
        if str.eq(formulas[i].name, name) { ret true }
        i += 1usize
    }
    ret false
}

// For each formula, its references that name another formula (an unparsable one has none): `edges[i]` indexes.
fn formula_edges(a: *mem.Arena, formulas: []const Formula) -> ([]const []const usize, err) {
    var none: []const []const usize = zero
    let (edges, e) = mem.alloc[[]const usize](a, formulas.len + 1usize)
    if e != ok { ret (none, e) }
    var i = 0usize
    while i < formulas.len {
        let (refs, diag) = dependencies(a, formulas[i].source)
        var list: []usize = zero
        var n = 0usize
        if diag.good && refs.len > 0usize {
            let (storage, se) = mem.alloc[usize](a, refs.len)
            if se != ok { ret (none, se) }
            list = storage
            var r = 0usize
            while r < refs.len {
                var k = 0usize
                while k < formulas.len {
                    if str.eq(formulas[k].name, refs[r]) {
                        list[n] = k
                        n += 1usize
                        k = formulas.len
                    } else {
                        k += 1usize
                    }
                }
                r += 1usize
            }
        }
        edges[i] = list[0usize..n]
        i += 1usize
    }
    ret (edges[0usize..formulas.len], ok)
}

// A circular reference among formula fields, as the names in order closed on the first (`a`, `b`, `a`); false
// when there is none.
fn detect_cycle(a: *mem.Arena, formulas: []const Formula) -> ([]const str, bool) {
    var none: []const str = zero
    let (edges, edges_error) = formula_edges(a, formulas)
    if edges_error != ok { ret (none, false) }
    let n = formulas.len
    if n == 0usize { ret (none, false) }
    let (color, color_error) = mem.alloc[u8](a, n)
    let (stack, stack_error) = mem.alloc[usize](a, n + 1usize)
    if color_error != ok || stack_error != ok { ret (none, false) }
    var i = 0usize
    while i < n {
        color[i] = 0u8
        i += 1usize
    }
    var depth = 0usize
    var found = false
    var cycle_from = 0usize
    var cycle_to = 0usize
    var start = 0usize
    while start < n && !found {
        if color[start] == 0u8 {
            // An iterative depth-first search with an explicit position per stack frame.
            let (position, position_error) = mem.alloc[usize](a, n + 1usize)
            if position_error != ok { ret (none, false) }
            depth = 0usize
            stack[0usize] = start
            position[0usize] = 0usize
            depth = 1usize
            color[start] = 1u8
            while depth > 0usize && !found {
                let node = stack[depth - 1usize]
                if position[depth - 1usize] < edges[node].len {
                    let m = edges[node][position[depth - 1usize]]
                    position[depth - 1usize] += 1usize
                    if color[m] == 1u8 {
                        var at = 0usize
                        while stack[at] != m { at += 1usize }
                        cycle_from = at
                        cycle_to = depth
                        found = true
                        stack[depth] = m
                    } else if color[m] == 0u8 {
                        color[m] = 1u8
                        stack[depth] = m
                        position[depth] = 0usize
                        depth += 1usize
                    }
                } else {
                    color[node] = 2u8
                    depth -= 1usize
                }
            }
        }
        start += 1usize
    }
    if !found { ret (none, false) }
    let length = cycle_to - cycle_from + 1usize
    let (names, names_error) = mem.alloc[str](a, length)
    if names_error != ok { ret (none, false) }
    var k = 0usize
    while k < length {
        names[k] = formulas[stack[cycle_from + k]].name
        k += 1usize
    }
    ret (names, true)
}

// The formula fields in an order that evaluates every dependency first; false if there is a cycle.
fn evaluation_order(a: *mem.Arena, formulas: []const Formula) -> ([]const str, bool) {
    var none: []const str = zero
    let (cycle, cyclic) = detect_cycle(a, formulas)
    if cyclic { ret (none, false) }
    let (edges, edges_error) = formula_edges(a, formulas)
    if edges_error != ok { ret (none, false) }
    let n = formulas.len
    if n == 0usize { ret (none, true) }
    let (seen, seen_error) = mem.alloc[bool](a, n)
    let (order, order_error) = mem.alloc[str](a, n)
    if seen_error != ok || order_error != ok { ret (none, false) }
    var i = 0usize
    while i < n {
        seen[i] = false
        i += 1usize
    }
    var count = 0usize
    var root = 0usize
    while root < n {
        count = visit_order(root, edges, seen, formulas, order, count)
        root += 1usize
    }
    ret (order[0usize..count], true)
}

fn visit_order(node: usize, edges: []const []const usize, seen: []bool, formulas: []const Formula, order: []str, at: usize) -> usize {
    if seen[node] { ret at }
    seen[node] = true
    var n = at
    var i = 0usize
    while i < edges[node].len {
        n = visit_order(edges[node][i], edges, seen, formulas, order, n)
        i += 1usize
    }
    order[n] = formulas[node].name
    ret n + 1usize
}

// The output type of a formula for a sample context: `number`, `text`, `boolean`, `date`, `array`, `blank`
// or `error`.
fn infer_type(a: *mem.Arena, source: str, ctx: *const Context, reg: *const Registry) -> str {
    ret type_of(evaluate(a, source, ctx, reg))
}

// A pseudo-random number in [0, 1) from the evaluator's own generator (xorshift64*, seeded from the context), so
// the volatile functions are reproducible for a given `random_seed`.
fn random(ev: *Evaluator) -> f64 {
    var x = ev.rng
    x = x ^ (x >> 12u64)
    x = x ^ (x << 25u64)
    x = x ^ (x >> 27u64)
    ev.rng = x
    let r = x *% 2685821657736338717u64
    ret f64(r >> 11u64) / 9007199254740992.0f64
}

fn weekday_name(index: i64) -> str {
    if index == 0i64 { ret "Sun" }
    if index == 1i64 { ret "Mon" }
    if index == 2i64 { ret "Tue" }
    if index == 3i64 { ret "Wed" }
    if index == 4i64 { ret "Thu" }
    if index == 5i64 { ret "Fri" }
    ret "Sat"
}

fn month_name(month: i64) -> str {
    if month == 1i64 { ret "Jan" }
    if month == 2i64 { ret "Feb" }
    if month == 3i64 { ret "Mar" }
    if month == 4i64 { ret "Apr" }
    if month == 5i64 { ret "May" }
    if month == 6i64 { ret "Jun" }
    if month == 7i64 { ret "Jul" }
    if month == 8i64 { ret "Aug" }
    if month == 9i64 { ret "Sep" }
    if month == 10i64 { ret "Oct" }
    if month == 11i64 { ret "Nov" }
    ret "Dec"
}

// JavaScript's `Date.prototype.toString()` for a UTC host: `Wed Mar 01 2026 12:30:45 GMT+0000 (Coordinated
// Universal Time)`.
fn date_js_string(a: *mem.Arena, ms: f64) -> str {
    if ms != ms { ret "Invalid Date" }
    let days = math.floor[f64](ms / ms_per_day())
    let into_day = ms - days * ms_per_day()
    let (year, month, day) = time.civil_from_days(i64(days))
    let whole = i64(into_day)
    var weekday = (i64(days) + 4i64) % 7i64
    if weekday < 0i64 { weekday += 7i64 }
    let (out, e) = mem.alloc[u8](a, 80usize)
    if e != ok { ret "" }
    var w = 0usize
    let w1 = weekday_name(weekday)
    var i = 0usize
    while i < 3usize {
        out[w] = w1[i]
        w += 1usize
        i += 1usize
    }
    out[w] = 32u8
    w += 1usize
    let m1 = month_name(month)
    i = 0usize
    while i < 3usize {
        out[w] = m1[i]
        w += 1usize
        i += 1usize
    }
    out[w] = 32u8
    w = put_int(out, w + 1usize, day, 2usize)
    out[w] = 32u8
    w = put_int(out, w + 1usize, year, 4usize)
    out[w] = 32u8
    w = put_int(out, w + 1usize, whole / 3600000i64, 2usize)
    out[w] = 58u8
    w = put_int(out, w + 1usize, whole / 60000i64 % 60i64, 2usize)
    out[w] = 58u8
    w = put_int(out, w + 1usize, whole / 1000i64 % 60i64, 2usize)
    let tail = " GMT+0000 (Coordinated Universal Time)"
    i = 0usize
    while i < tail.len {
        out[w] = tail[i]
        w += 1usize
        i += 1usize
    }
    ret out[0usize..w]
}
