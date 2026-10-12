// The column types a synced table infers from sample rows (L037), after appdor's `src/io/infer.js`
// (`detectDateOrder`, `detectDecimalSeparator`, `inferColumnType`), `inferExternalSchema` of `src/connectors/index.js` and the
// inferred half of `proposeMapping` in `src/sync/synced-table.js`:
//
//   * the date order of a column of slash and dot dates, decided by a value no month can be (a day over 12 first or
//     second), else unknown; the decimal separator of a column of numbers, decided by a cell whose separator structure
//     proves it (`19,99`, `1.234.567`, `1,234.56`), conflicting when both appear;
//   * the type ladder: checkbox, percent, currency, number, datetime, date, email, url, phone, then select (at most 20
//     distinct values, fewer than the values and at most half of them), longtext (average length over 100 UTF-16 units)
//     and text; a numeric type carries the column's decimal convention and a date its order;
//   * the schema of a list of records (the keys in JavaScript's object order: array indices first, then insertion order)
//     and the mapping proposed for it, a column of objects or arrays being one `longtext` flagged `structured`.
//
// Values are JSON. A cell is read as `String(v).trim()` (null as empty); the regular expressions and the string
// predicates of the source are written out over code points; the platform's `new Date(text)`, which the ladder asks for
// datetime values and for ambiguous slash dates, is a port of V8's `DateParser` (the ES5 date-time string, then the
// legacy parser) deciding only whether a date comes of the text.
//
// ponytail: lower-casing is the simple (one code point) mapping, which differs from `toLowerCase` only for U+0130; the
// `/i` of the currency suffix folds ASCII and Cyrillic; a lone surrogate cannot arrive in UTF-8.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.formula as f
use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncjob as syncjob
use e.algo.view as view
use e.algo.writeback as wb
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str
use e.text.utf8 as utf8

// --- code points -----------------------------------------------------------------------------------------------------

fn cps_of(a: *mem.Arena, s: str) -> []u32 {
    let (buf, e) = mem.alloc[u32](a, s.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (u, got) = utf8.iterator_next(&it)
        if got {
            buf[n] = u
            n += 1usize
        } else {
            more = false
        }
    }
    ret buf[0usize..n]
}

fn is_digit(u: u32) -> bool { ret u >= 48u32 && u <= 57u32 }

fn is_word(u: u32) -> bool { ret is_digit(u) || (u >= 65u32 && u <= 90u32) || (u >= 97u32 && u <= 122u32) || u == 95u32 }

// UTF-16 code units of a text.
fn utf16_len(s: str) -> usize {
    var n = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (u, got) = utf8.iterator_next(&it)
        if got {
            n += 1usize
            if u >= 65536u32 { n += 1usize }
        } else {
            more = false
        }
    }
    ret n
}

// --- the date order --------------------------------------------------------------------------------------------------

// `^(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})$`: the three numbers' values, or false.
fn slash_parts(c: []const u32) -> (u32, u32, u32, usize, bool) {
    var at = 0usize
    var first = 0u32
    var n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        first = first * 10u32 + (c[at] - 48u32)
        at += 1usize
        n += 1usize
    }
    if n == 0usize || at >= c.len || !(c[at] == 47u32 || c[at] == 46u32) { ret (0u32, 0u32, 0u32, 0usize, false) }
    at += 1usize
    var second = 0u32
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        second = second * 10u32 + (c[at] - 48u32)
        at += 1usize
        n += 1usize
    }
    if n == 0usize || at >= c.len || !(c[at] == 47u32 || c[at] == 46u32) { ret (0u32, 0u32, 0u32, 0usize, false) }
    at += 1usize
    var year = 0u32
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 4usize {
        year = year * 10u32 + (c[at] - 48u32)
        at += 1usize
        n += 1usize
    }
    if n < 2usize || at != c.len { ret (0u32, 0u32, 0u32, 0usize, false) }
    ret (first, second, year, n, true)
}

type Order = struct { order: str, witness: str, sampled: usize }

// `detectDateOrder`: `order` is "dmy", "mdy" or "" (null); `witness` the value that proved it.
fn detect_date_order(a: *mem.Arena, values: []const str) -> Order {
    var out = Order { order: "", witness: "", sampled: 0usize }
    var sampled = 0usize
    var i = 0usize
    while i < values.len {
        let t = view.js_trim(values[i])
        let (d, m, y, yn, matched) = slash_parts(cps_of(a, t))
        if matched { sampled += 1usize }
        i += 1usize
    }
    out.sampled = sampled
    i = 0usize
    while i < values.len {
        let t = view.js_trim(values[i])
        let (d, m, y, yn, matched) = slash_parts(cps_of(a, t))
        if matched && d > 12u32 {
            out.order = "dmy"
            out.witness = t
            ret out
        }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        let t = view.js_trim(values[i])
        let (d, m, y, yn, matched) = slash_parts(cps_of(a, t))
        if matched && m > 12u32 {
            out.order = "mdy"
            out.witness = t
            ret out
        }
        i += 1usize
    }
    ret out
}

// --- units -----------------------------------------------------------------------------------------------------------

// `s` with trailing JS whitespace removed (a prefix of `s`).
fn rtrim_space(s: str) -> str {
    var end = s.len
    var go = true
    while go && end > 0usize {
        var k = end - 1usize
        while k > 0usize && (s[k] & 192u8) == 128u8 { k -= 1usize }
        var it = utf8.iterator(s[k..end])
        let (u, got) = utf8.iterator_next(&it)
        if got && view.js_space(u) { end = k } else { go = false }
    }
    ret s[0usize..end]
}

type Stripped = struct { body: str, marked: bool }

// `s.replace(/\s*%$/, '')` then `.trim()`.
fn strip_percent(s: str) -> Stripped {
    if s.len > 0usize && s[s.len - 1usize] == 37u8 {
        ret Stripped { body: view.js_trim(rtrim_space(s[0usize..s.len - 1usize])), marked: true }
    }
    ret Stripped { body: view.js_trim(s), marked: false }
}

// The length of a currency symbol at the start of `s` (`[$€£¥]`), 0 when there is none.
fn currency_symbol_len(s: str) -> usize {
    if s.len >= 1usize && s[0usize] == 36u8 { ret 1usize }
    if s.len >= 3usize && s[0usize] == 226u8 && s[1usize] == 130u8 && s[2usize] == 172u8 { ret 3usize }
    if s.len >= 2usize && s[0usize] == 194u8 && (s[1usize] == 163u8 || s[1usize] == 165u8) { ret 2usize }
    ret 0usize
}

fn lower_ascii(u: u32) -> u32 {
    if u >= 65u32 && u <= 90u32 { ret u + 32u32 }
    ret u
}

// The code points of the currency suffix `(лв\.?|BGN|USD|EUR)` (any case) at the end of `s`: how many bytes it takes,
// 0 when there is none.
fn currency_suffix_len(a: *mem.Arena, s: str) -> usize {
    let c = cps_of(a, s)
    // лв. / лв (Cyrillic, folded to lower case: U+041B/U+043B, U+0412/U+0432)
    var n = c.len
    if n >= 1usize && c[n - 1usize] == 46u32 { n -= 1usize }
    if n >= 2usize {
        let l = c[n - 2usize]
        let v = c[n - 1usize]
        if (l == 1083u32 || l == 1051u32) && (v == 1074u32 || v == 1042u32) {
            // bytes: each Cyrillic letter is 2 bytes, plus the dot
            var bytes = 4usize
            if n != c.len { bytes = 5usize }
            ret bytes
        }
    }
    if c.len >= 3usize {
        let x = lower_ascii(c[c.len - 3usize])
        let y = lower_ascii(c[c.len - 2usize])
        let z = lower_ascii(c[c.len - 1usize])
        if (x == 98u32 && y == 103u32 && z == 110u32) || (x == 117u32 && y == 115u32 && z == 100u32) || (x == 101u32 && y == 117u32 && z == 114u32) { ret 3usize }
    }
    ret 0usize
}

// `stripCurrency`: the prefix symbol and its spaces, the suffix word and the spaces before it, then trimmed.
fn strip_currency(a: *mem.Arena, s: str) -> Stripped {
    var start = 0usize
    let sym = currency_symbol_len(s)
    var changed = false
    if sym > 0usize {
        changed = true
        start = sym
        var go = true
        while go && start < s.len {
            var it = utf8.iterator(s[start..s.len])
            let (u, got) = utf8.iterator_next(&it)
            if got && view.js_space(u) {
                if u < 128u32 {
                    start += 1usize
                } else if u < 2048u32 {
                    start += 2usize
                } else {
                    start += 3usize
                }
            } else {
                go = false
            }
        }
    }
    var rest = s[start..s.len]
    let suffix = currency_suffix_len(a, rest)
    if suffix > 0usize {
        changed = true
        rest = rtrim_space(rest[0usize..rest.len - suffix])
    }
    ret Stripped { body: view.js_trim(rest), marked: changed }
}

fn strip_units(a: *mem.Arena, s: str) -> str {
    let c = strip_currency(a, s)
    ret strip_percent(c.body).body
}

// --- the shape of a number -------------------------------------------------------------------------------------------

// `decimal`: 0 none, 1 comma, 2 dot.
type Shape = struct { valid: bool, decimal: u8, ambiguous: bool, has_fraction: bool, lead_zero: bool, safe: bool }

fn no_shape() -> Shape {
    ret Shape { valid: false, decimal: 0u8, ambiguous: false, has_fraction: false, lead_zero: false, safe: true }
}

// `readNumericShape`: the separator structure of one numeric-looking cell.
fn read_shape(a: *mem.Arena, raw: str) -> Shape {
    let all = cps_of(a, view.js_trim(raw))
    // `.replace(/\s/g, '')`
    let (buf, e) = mem.alloc[u32](a, all.len + 1usize)
    if e != ok { ret no_shape() }
    var n = 0usize
    var i = 0usize
    while i < all.len {
        if !view.js_space(all[i]) {
            buf[n] = all[i]
            n += 1usize
        }
        i += 1usize
    }
    let s = buf[0usize..n]
    // NUMERIC_SHAPE: -?(\d+([.,]\d+)*|[.,]\d+)
    var at = 0usize
    if at < s.len && s[at] == 45u32 { at += 1usize }
    let body = s[at..s.len]
    if body.len == 0usize { ret no_shape() }
    // Groups and separators.
    var group_len: [64]usize = zero
    var group_start: [64]usize = zero
    var seps: [64]u32 = zero
    var groups = 1usize
    var sep_count = 0usize
    var p = 0usize
    group_start[0usize] = 0usize
    if body[0usize] == 46u32 || body[0usize] == 44u32 {
        // `[.,]\d+` then the end: one separator, one digit run
        seps[0usize] = body[0usize]
        sep_count = 1usize
        group_len[0usize] = 0usize
        groups = 2usize
        group_start[1usize] = 1usize
        p = 1usize
        var digits = 0usize
        while p < body.len && is_digit(body[p]) {
            p += 1usize
            digits += 1usize
        }
        if digits == 0usize || p != body.len { ret no_shape() }
        group_len[1usize] = digits
    } else {
        var go = true
        while go {
            var digits = 0usize
            while p < body.len && is_digit(body[p]) {
                p += 1usize
                digits += 1usize
            }
            if digits == 0usize { ret no_shape() }
            group_len[groups - 1usize] = digits
            if p == body.len {
                go = false
            } else if body[p] == 46u32 || body[p] == 44u32 {
                if sep_count >= 62usize { ret no_shape() }
                seps[sep_count] = body[p]
                sep_count += 1usize
                p += 1usize
                group_start[groups] = p
                groups += 1usize
            } else {
                ret no_shape()
            }
        }
    }
    var kinds_comma = false
    var kinds_dot = false
    i = 0usize
    while i < sep_count {
        if seps[i] == 44u32 { kinds_comma = true } else { kinds_dot = true }
        i += 1usize
    }
    let lead_ok = group_len[0usize] <= 3usize
    // /^[1-9]\d{0,2}$/ on the first group
    var lead_can_group = false
    if group_len[0usize] >= 1usize && group_len[0usize] <= 3usize && body[group_start[0usize]] >= 49u32 && body[group_start[0usize]] <= 57u32 { lead_can_group = true }
    var out = no_shape()
    out.valid = true
    var decimal = 0u8
    var ambiguous = false
    var has_fraction = false
    if sep_count == 0usize {
        decimal = 0u8
    } else if kinds_comma && kinds_dot {
        let last = seps[sep_count - 1usize]
        let other = 46u32
        var other_ok = true
        var wanted = other
        if last == 46u32 { wanted = 44u32 }
        i = 0usize
        while i + 1usize < sep_count {
            if seps[i] != wanted { other_ok = false }
            i += 1usize
        }
        if !other_ok || !lead_ok { ret no_shape() }
        i = 1usize
        while i + 1usize < groups {
            if group_len[i] != 3usize { ret no_shape() }
            i += 1usize
        }
        if last == 44u32 { decimal = 1u8 } else { decimal = 2u8 }
        has_fraction = true
    } else if sep_count > 1usize {
        if !lead_ok { ret no_shape() }
        i = 1usize
        while i < groups {
            if group_len[i] != 3usize { ret no_shape() }
            i += 1usize
        }
        if seps[0usize] == 44u32 { decimal = 2u8 } else { decimal = 1u8 }
    } else if group_len[1usize] != 3usize || !lead_can_group {
        if seps[0usize] == 44u32 { decimal = 1u8 } else { decimal = 2u8 }
        has_fraction = true
    } else {
        ambiguous = true
    }
    out.decimal = decimal
    out.ambiguous = ambiguous
    out.has_fraction = has_fraction
    // intDigits: the groups' digits without the last when there is a fraction.
    var digit_count = 0usize
    var first_group_digit = 0u32
    var second_digit = 0u32
    var seen = 0usize
    var upto = groups
    if has_fraction { upto = groups - 1usize }
    var g = 0usize
    var lead_text: [16]u32 = zero
    while g < upto {
        var k = 0usize
        while k < group_len[g] {
            let d = body[group_start[g] + k]
            if digit_count < 16usize { lead_text[digit_count] = d }
            digit_count += 1usize
            k += 1usize
        }
        g += 1usize
    }
    // /^0\d/ on intDigits
    out.lead_zero = digit_count >= 2usize && lead_text[0usize] == 48u32
    // Number.isSafeInteger(Number(intDigits)) when there is no fraction
    var safe = true
    if !has_fraction {
        if digit_count > 16usize {
            safe = false
        } else if digit_count == 16usize {
            // compare with 9007199254740991
            let limit = "9007199254740991"
            var cmp = 0i32
            var k = 0usize
            while k < 16usize && cmp == 0i32 {
                if lead_text[k] < u32(limit[k]) { cmp = 0i32 - 1i32 }
                if lead_text[k] > u32(limit[k]) { cmp = 1i32 }
                k += 1usize
            }
            safe = cmp <= 0i32
        }
    }
    out.safe = safe
    ret out
}

// `isNumberCell`: a number, not an identifier made of digits.
fn is_number_cell(a: *mem.Arena, s: str) -> bool {
    let shape = read_shape(a, s)
    if !shape.valid { ret false }
    if shape.lead_zero { ret false }
    if !shape.has_fraction && !shape.safe { ret false }
    ret true
}

type Decimal = struct { decimal: str, witness: str, sampled: usize, conflicting: bool }

fn convention_of(d: u8) -> str {
    if d == 1u8 { ret "comma" }
    if d == 2u8 { ret "dot" }
    ret ""
}

// `detectDecimalSeparator`.
fn detect_decimal(a: *mem.Arena, values: []const str) -> Decimal {
    var comma_witness = ""
    var have_comma = false
    var dot_witness = ""
    var have_dot = false
    var sampled = 0usize
    var i = 0usize
    while i < values.len {
        let raw = view.js_trim(values[i])
        let shape = read_shape(a, strip_units(a, raw))
        if shape.valid && (shape.decimal != 0u8 || shape.ambiguous) {
            sampled += 1usize
            if shape.decimal == 1u8 && !have_comma {
                have_comma = true
                comma_witness = raw
            }
            if shape.decimal == 2u8 && !have_dot {
                have_dot = true
                dot_witness = raw
            }
        }
        i += 1usize
    }
    if have_comma && have_dot { ret Decimal { decimal: "", witness: "", sampled: sampled, conflicting: true } }
    if have_comma { ret Decimal { decimal: "comma", witness: comma_witness, sampled: sampled, conflicting: false } }
    if have_dot { ret Decimal { decimal: "dot", witness: dot_witness, sampled: sampled, conflicting: false } }
    ret Decimal { decimal: "", witness: "", sampled: sampled, conflicting: false }
}

// --- V8's date parser ------------------------------------------------------------------------------------------------

const K_NONE: i32 = -1i32
const T_END: u8 = 1u8
const T_NUMBER: u8 = 2u8
const T_SYMBOL: u8 = 3u8
const T_KEYWORD: u8 = 4u8
const T_SPACE: u8 = 5u8
const T_UNKNOWN: u8 = 6u8
const T_INVALID: u8 = 7u8
const KW_INVALID: u8 = 0u8
const KW_MONTH: u8 = 1u8
const KW_ZONE: u8 = 2u8
const KW_TSEP: u8 = 3u8
const KW_AMPM: u8 = 4u8

// A token: `value` is the number, the symbol or the keyword's value; `length` the characters it spans.
type Token = struct { tag: u8, value: i32, length: i32, kw: u8 }

type Day = struct { comp: [3]i32, index: i32, named_month: i32, iso: bool }
type Clock = struct { comp: [4]i32, index: i32, hour_offset: i32 }
type Zone = struct { sign: i32, hour: i32, minute: i32 }
// `tok` is the one token of lookahead; `first`, when `has_first`, is the token the legacy loop starts with (a sign the
// ES5 parser handed back after looking past it).
type Scan = struct { c: []const u32, at: usize, tok: Token, first: Token, has_first: bool }

fn is_hour(n: i32) -> bool { ret n >= 0i32 && n <= 23i32 }
fn is_minute(n: i32) -> bool { ret n >= 0i32 && n <= 59i32 }
fn is_second(n: i32) -> bool { ret n >= 0i32 && n <= 59i32 }
fn is_millisecond(n: i32) -> bool { ret n >= 0i32 && n <= 999i32 }
fn is_month(n: i32) -> bool { ret n >= 1i32 && n <= 12i32 }
fn is_day(n: i32) -> bool { ret n >= 1i32 && n <= 31i32 }

fn at_end(s: *Scan) -> bool { ret s.at >= s.c.len }

// KeywordTable lookup: `word` is the first three characters lowered (0 padded), `length` the word's length.
fn keyword_of(w0: u32, w1: u32, w2: u32, length: usize) -> Token {
    // (name, type, value)
    var names: [30]u32 = zero
    var kinds: [10]u8 = zero
    // months jan..dec
    let months = "janfebmaraprmayjunjulaugsepoctnovdec"
    var i = 0usize
    while i < 12usize {
        if w0 == u32(months[i * 3usize]) && w1 == u32(months[i * 3usize + 1usize]) && w2 == u32(months[i * 3usize + 2usize]) {
            ret Token { tag: T_KEYWORD, value: i32(i) + 1i32, length: i32(length), kw: KW_MONTH }
        }
        i += 1usize
    }
    // Word longer than three characters is only a month name.
    if length > 3usize { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_INVALID } }
    if w0 == 97u32 && w1 == 109u32 && w2 == 0u32 { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_AMPM } }
    if w0 == 112u32 && w1 == 109u32 && w2 == 0u32 { ret Token { tag: T_KEYWORD, value: 12i32, length: i32(length), kw: KW_AMPM } }
    if w0 == 117u32 && w1 == 116u32 && w2 == 0u32 { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_ZONE } }
    if w0 == 117u32 && w1 == 116u32 && w2 == 99u32 { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_ZONE } }
    if w0 == 122u32 && w1 == 0u32 && w2 == 0u32 { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_ZONE } }
    if w0 == 103u32 && w1 == 109u32 && w2 == 116u32 { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_ZONE } }
    if w0 == 116u32 && w1 == 0u32 && w2 == 0u32 { ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_TSEP } }
    // cdt cst edt est mdt mst pdt pst: the first letter, then `dt`/`st`
    if w2 == 116u32 && (w1 == 100u32 || w1 == 115u32) {
        var offset = 0i32
        if w0 == 99u32 { offset = 0i32 - 6i32 }
        if w0 == 101u32 { offset = 0i32 - 5i32 }
        if w0 == 109u32 { offset = 0i32 - 7i32 }
        if w0 == 112u32 { offset = 0i32 - 8i32 }
        if w0 == 99u32 || w0 == 101u32 || w0 == 109u32 || w0 == 112u32 {
            if w1 == 100u32 { offset += 1i32 }
            ret Token { tag: T_KEYWORD, value: offset, length: i32(length), kw: KW_ZONE }
        }
    }
    ret Token { tag: T_KEYWORD, value: 0i32, length: i32(length), kw: KW_INVALID }
}

// The next token of the input.
fn scan_next(s: *Scan) -> Token {
    if s.at >= s.c.len { ret Token { tag: T_END, value: 0i32, length: 0i32, kw: 0u8 } }
    let start = s.at
    let ch = s.c[s.at]
    if is_digit(ch) {
        // ReadUnsignedNumeral: leading zeros skipped, the first nine significant digits kept.
        var n = 0i32
        var seen = 0i32
        while s.at < s.c.len && s.c[s.at] == 48u32 { s.at += 1usize }
        while s.at < s.c.len && is_digit(s.c[s.at]) {
            if seen < 9i32 { n = n * 10i32 + i32(s.c[s.at] - 48u32) }
            seen += 1i32
            s.at += 1usize
        }
        ret Token { tag: T_NUMBER, value: n, length: i32(s.at - start), kw: 0u8 }
    }
    if ch == 58u32 || ch == 45u32 || ch == 43u32 || ch == 46u32 || ch == 41u32 {
        s.at += 1usize
        ret Token { tag: T_SYMBOL, value: i32(ch), length: 1i32, kw: 0u8 }
    }
    if ch >= 65u32 && !view.js_space(ch) {
        var w0 = 0u32
        var w1 = 0u32
        var w2 = 0u32
        var len = 0usize
        while s.at < s.c.len && s.c[s.at] >= 65u32 && !view.js_space(s.c[s.at]) {
            let low = s.c[s.at] | 32u32
            if len == 0usize { w0 = low }
            if len == 1usize { w1 = low }
            if len == 2usize { w2 = low }
            len += 1usize
            s.at += 1usize
        }
        ret keyword_of(w0, w1, w2, len)
    }
    if view.js_space(ch) {
        while s.at < s.c.len && view.js_space(s.c[s.at]) { s.at += 1usize }
        ret Token { tag: T_SPACE, value: 0i32, length: i32(s.at - start), kw: 0u8 }
    }
    if ch == 40u32 {
        var balance = 0i32
        var go = true
        while go {
            if s.c[s.at] == 41u32 { balance -= 1i32 } else if s.c[s.at] == 40u32 { balance += 1i32 }
            s.at += 1usize
            if !(balance > 0i32 && s.at < s.c.len) { go = false }
        }
        ret Token { tag: T_UNKNOWN, value: 0i32, length: 0i32, kw: 0u8 }
    }
    s.at += 1usize
    ret Token { tag: T_UNKNOWN, value: 0i32, length: 0i32, kw: 0u8 }
}

fn next_token(s: *Scan) -> Token {
    let r = s.tok
    s.tok = scan_next(s)
    ret r
}

fn skip_symbol(s: *Scan, sym: u32) -> bool {
    if s.tok.tag == T_SYMBOL && s.tok.value == i32(sym) {
        s.tok = scan_next(s)
        ret true
    }
    ret false
}

fn is_sign(t: Token) -> bool { ret t.tag == T_SYMBOL && (t.value == 45i32 || t.value == 43i32) }
fn is_zone_z(t: Token) -> bool { ret t.tag == T_KEYWORD && t.kw == KW_ZONE && t.length == 1i32 }
fn fixed_number(t: Token, len: i32) -> bool { ret t.tag == T_NUMBER && t.length == len }

fn read_milliseconds(t: Token) -> i32 {
    var number = t.value
    var length = t.length
    if length < 3i32 {
        if length == 1i32 { number = number * 100i32 } else if length == 2i32 { number = number * 10i32 }
    } else if length > 3i32 {
        if length > 9i32 { length = 9i32 }
        var factor = 1i32
        while length > 3i32 {
            factor = factor * 10i32
            length -= 1i32
        }
        number = number / factor
    }
    ret number
}

fn day_add(d: *Day, n: i32) -> bool {
    if d.index < 3i32 {
        d.comp[usize(d.index)] = n
        d.index += 1i32
        ret true
    }
    ret false
}

fn clock_add(t: *Clock, n: i32) -> bool {
    if t.index < 4i32 {
        t.comp[usize(t.index)] = n
        t.index += 1i32
        ret true
    }
    ret false
}

fn clock_final(t: *Clock, n: i32) -> bool {
    if !clock_add(t, n) { ret false }
    while t.index < 4i32 {
        t.comp[usize(t.index)] = 0i32
        t.index += 1i32
    }
    ret true
}

fn clock_expecting(t: *Clock, n: i32) -> bool {
    ret (t.index == 1i32 && is_minute(n)) || (t.index == 2i32 && is_second(n)) || (t.index == 3i32 && is_millisecond(n))
}

fn zone_set(z: *Zone, hours: i32) {
    if hours < 0i32 {
        z.sign = 0i32 - 1i32
        z.hour = 0i32 - hours
    } else {
        z.sign = 1i32
        z.hour = hours
    }
    z.minute = 0i32
}

fn zone_expecting(z: *Zone, n: i32) -> bool { ret z.hour != K_NONE && z.minute == K_NONE && is_minute(n) }

fn zone_is_utc(z: *Zone) -> bool { ret z.hour == 0i32 && z.minute == 0i32 }

// ParseES5DateTime: false on an invalid token; `done` true when the whole input was an ES5 date-time (or that the
// legacy loop continues from `s.tok`, the first token not handled).
fn parse_es5(s: *Scan, day: *Day, time: *Clock, zone: *Zone, invalid: *bool, finished: *bool) {
    *invalid = false
    *finished = false
    if is_sign(s.tok) {
        let sign_token = next_token(s)
        if !fixed_number(s.tok, 6i32) {
            // The sign is the first unhandled token: the legacy loop begins with it.
            s.first = sign_token
            s.has_first = true
            ret
        }
        var sign = 1i32
        if sign_token.value == 45i32 { sign = 0i32 - 1i32 }
        let year = next_token(s).value
        if sign < 0i32 && year == 0i32 {
            s.first = sign_token
            s.has_first = true
            ret
        }
        let _ = day_add(day, sign * year)
    } else if fixed_number(s.tok, 4i32) {
        let _ = day_add(day, next_token(s).value)
    } else {
        ret
    }
    if skip_symbol(s, 45u32) {
        if !fixed_number(s.tok, 2i32) || !is_month(s.tok.value) { ret }
        let _ = day_add(day, next_token(s).value)
        if skip_symbol(s, 45u32) {
            if !fixed_number(s.tok, 2i32) || !is_day(s.tok.value) { ret }
            let _ = day_add(day, next_token(s).value)
        }
    }
    if !(s.tok.tag == T_KEYWORD && s.tok.kw == KW_TSEP) {
        if s.tok.tag != T_END { ret }
    } else {
        let _ = next_token(s)
        if !fixed_number(s.tok, 2i32) || s.tok.value < 0i32 || s.tok.value > 24i32 {
            *invalid = true
            ret
        }
        let hour_is_24 = s.tok.value == 24i32
        let _ = clock_add(time, next_token(s).value)
        if !skip_symbol(s, 58u32) {
            *invalid = true
            ret
        }
        if !fixed_number(s.tok, 2i32) || !is_minute(s.tok.value) || (hour_is_24 && s.tok.value > 0i32) {
            *invalid = true
            ret
        }
        let _ = clock_add(time, next_token(s).value)
        if skip_symbol(s, 58u32) {
            if !fixed_number(s.tok, 2i32) || !is_second(s.tok.value) || (hour_is_24 && s.tok.value > 0i32) {
                *invalid = true
                ret
            }
            let _ = clock_add(time, next_token(s).value)
            if skip_symbol(s, 46u32) {
                if s.tok.tag != T_NUMBER || (hour_is_24 && s.tok.value > 0i32) {
                    *invalid = true
                    ret
                }
                let _ = clock_add(time, read_milliseconds(next_token(s)))
            }
        }
        if is_zone_z(s.tok) {
            let _ = next_token(s)
            zone_set(zone, 0i32)
        } else if s.tok.tag == T_SYMBOL && (s.tok.value == 43i32 || s.tok.value == 45i32) {
            let sign_symbol = next_token(s)
            if sign_symbol.value == 43i32 { zone.sign = 1i32 } else { zone.sign = 0i32 - 1i32 }
            if fixed_number(s.tok, 4i32) {
                let hourmin = next_token(s).value
                let hour = hourmin / 100i32
                let minute = hourmin % 100i32
                if !is_hour(hour) || !is_minute(minute) {
                    *invalid = true
                    ret
                }
                zone.hour = hour
                zone.minute = minute
            } else {
                if !fixed_number(s.tok, 2i32) || !is_hour(s.tok.value) {
                    *invalid = true
                    ret
                }
                zone.hour = next_token(s).value
                if !skip_symbol(s, 58u32) {
                    *invalid = true
                    ret
                }
                if !fixed_number(s.tok, 2i32) || !is_minute(s.tok.value) {
                    *invalid = true
                    ret
                }
                zone.minute = next_token(s).value
            }
        }
        if s.tok.tag != T_END {
            *invalid = true
            ret
        }
    }
    if zone.hour == K_NONE && time.index == 0i32 { zone_set(zone, 0i32) }
    day.iso = true
    *finished = true
}

// Would `new Date(text)` be a valid date? V8's DateParser: the ES5 date-time string, then the legacy parser.
fn date_ok(a: *mem.Arena, text: str) -> bool {
    let blank = Token { tag: T_END, value: 0i32, length: 0i32, kw: 0u8 }
    var s = Scan { c: cps_of(a, text), at: 0usize, tok: blank, first: blank, has_first: false }
    s.tok = scan_next(&s)
    var day = Day { comp: zero, index: 0i32, named_month: K_NONE, iso: false }
    var time = Clock { comp: zero, index: 0i32, hour_offset: K_NONE }
    var zone = Zone { sign: K_NONE, hour: K_NONE, minute: K_NONE }
    var invalid = false
    var finished = false
    parse_es5(&s, &day, &time, &zone, &invalid, &finished)
    if invalid { ret false }
    var has_read_number = day.index != 0i32
    if !finished {
        // The legacy loop, from the token the ES5 parser left (`s.tok`).
        var token = s.first
        if !s.has_first { token = next_token(&s) }
        var go = token.tag != T_END
        while go {
            if token.tag == T_NUMBER {
                has_read_number = true
                let n = token.value
                if skip_symbol(&s, 58u32) {
                    if skip_symbol(&s, 58u32) {
                        if time.index != 0i32 { ret false }
                        let _ = clock_add(&time, n)
                        let _ = clock_add(&time, 0i32)
                    } else {
                        if !clock_add(&time, n) { ret false }
                        if s.tok.tag == T_SYMBOL && s.tok.value == 46i32 { let _ = next_token(&s) }
                    }
                } else if skip_symbol(&s, 46u32) && clock_expecting(&time, n) {
                    let _ = clock_add(&time, n)
                    if s.tok.tag != T_NUMBER { ret false }
                    let ms = read_milliseconds(next_token(&s))
                    if ms < 0i32 { ret false }
                    let _ = clock_final(&time, ms)
                } else if zone_expecting(&zone, n) {
                    zone.minute = n
                } else if clock_expecting(&time, n) {
                    let _ = clock_final(&time, n)
                    let peek = s.tok
                    if peek.tag != T_END && peek.tag != T_SPACE && !is_zone_z(peek) && !is_sign(peek) { ret false }
                } else {
                    if !day_add(&day, n) { ret false }
                    let _ = skip_symbol(&s, 45u32)
                }
            } else if token.tag == T_KEYWORD {
                if token.kw == KW_AMPM && time.index != 0i32 {
                    time.hour_offset = token.value
                } else if token.kw == KW_MONTH {
                    day.named_month = token.value
                    let _ = skip_symbol(&s, 45u32)
                } else if token.kw == KW_ZONE && has_read_number {
                    zone_set(&zone, token.value)
                } else {
                    if has_read_number { ret false }
                    if s.tok.tag == T_NUMBER { ret false }
                }
            } else if is_sign(token) && (zone_is_utc(&zone) || time.index != 0i32) {
                if token.value == 43i32 { zone.sign = 1i32 } else { zone.sign = 0i32 - 1i32 }
                var n = 0i32
                var length = 0i32
                if s.tok.tag == T_NUMBER {
                    let nt = next_token(&s)
                    length = nt.length
                    n = nt.value
                }
                has_read_number = true
                if s.tok.tag == T_SYMBOL && s.tok.value == 58i32 {
                    zone.hour = n
                    zone.minute = K_NONE
                } else if length == 2i32 || length == 1i32 {
                    zone.hour = n
                    zone.minute = 0i32
                } else if length == 4i32 || length == 3i32 {
                    zone.hour = n / 100i32
                    zone.minute = n % 100i32
                } else {
                    ret false
                }
            } else if (is_sign(token) || (token.tag == T_SYMBOL && token.value == 41i32)) && has_read_number {
                ret false
            }
            token = next_token(&s)
            go = token.tag != T_END
        }
    }
    // DayComposer::Write
    if day.index < 1i32 { ret false }
    while day.index < 3i32 {
        day.comp[usize(day.index)] = 1i32
        day.index += 1i32
    }
    var year = 0i32
    var month = K_NONE
    var dom = K_NONE
    if day.named_month == K_NONE {
        if day.iso || !is_day(day.comp[0usize]) {
            year = day.comp[0usize]
            month = day.comp[1usize]
            dom = day.comp[2usize]
        } else {
            month = day.comp[0usize]
            dom = day.comp[1usize]
            year = day.comp[2usize]
        }
    } else {
        month = day.named_month
        if day.index == 1i32 {
            dom = day.comp[0usize]
        } else if !is_day(day.comp[0usize]) {
            year = day.comp[0usize]
            dom = day.comp[1usize]
        } else {
            dom = day.comp[0usize]
            year = day.comp[1usize]
        }
    }
    if !day.iso {
        if year >= 0i32 && year <= 49i32 {
            year += 2000i32
        } else if year >= 50i32 && year <= 99i32 {
            year += 1900i32
        }
    }
    if !is_month(month) || !is_day(dom) { ret false }
    // TimeComposer::Write
    while time.index < 4i32 {
        time.comp[usize(time.index)] = 0i32
        time.index += 1i32
    }
    var hour = time.comp[0usize]
    let minute = time.comp[1usize]
    let second = time.comp[2usize]
    let milli = time.comp[3usize]
    if time.hour_offset != K_NONE {
        if !(hour >= 0i32 && hour <= 12i32) { ret false }
        hour = hour % 12i32
        hour += time.hour_offset
    }
    if !is_hour(hour) || !is_minute(minute) || !is_second(second) || !is_millisecond(milli) {
        if hour != 24i32 || minute != 0i32 || second != 0i32 || milli != 0i32 { ret false }
    }
    // No range check: a year here has at most four digits, and a zone offset is at most a hundred hours, so the
    // instant is always inside the time clip.
    ret true
}

// --- toCalendarDate --------------------------------------------------------------------------------------------------

fn days_in_month(year: i64, month: i64) -> i64 {
    if month == 2i64 {
        var leap = year % 4i64 == 0i64
        if year % 100i64 == 0i64 { leap = year % 400i64 == 0i64 }
        if leap { ret 29i64 }
        ret 28i64
    }
    if month == 4i64 || month == 6i64 || month == 9i64 || month == 11i64 { ret 30i64 }
    ret 31i64
}

// `^\d{4}-\d{1,2}-\d{1,2}$`.
fn iso_date(c: []const u32) -> bool {
    var at = 0usize
    var n = 0usize
    while at < c.len && is_digit(c[at]) && n < 4usize {
        at += 1usize
        n += 1usize
    }
    if n != 4usize || at >= c.len || c[at] != 45u32 { ret false }
    at += 1usize
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        at += 1usize
        n += 1usize
    }
    if n == 0usize || at >= c.len || c[at] != 45u32 { ret false }
    at += 1usize
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        at += 1usize
        n += 1usize
    }
    ret n != 0usize && at == c.len
}

// `toCalendarDate(s, order) !== null` for a string `DATE_RE` accepted.
fn calendar_date_ok(a: *mem.Arena, s: str, order: str) -> bool {
    let c = cps_of(a, s)
    if iso_date(c) { ret true }
    let (d, m, y, yn, matched) = slash_parts(c)
    if matched && (str.eq(order, "dmy") || str.eq(order, "mdy")) {
        var day = i64(m)
        var month = i64(d)
        if str.eq(order, "dmy") {
            day = i64(d)
            month = i64(m)
        }
        var year = i64(y)
        if yn == 2usize { year = 2000i64 + i64(y) }
        // `new Date(year, ...)` maps the years 0..99 to 1900..1999, which then differ from `year`.
        if year < 100i64 { ret false }
        if month < 1i64 || month > 12i64 { ret false }
        ret day >= 1i64 && day <= days_in_month(year, month)
    }
    ret date_ok(a, s)
}

// --- the regular expressions -----------------------------------------------------------------------------------------

// `DATE_RE`: an ISO-like date or a slash or dot date.
fn date_shape(c: []const u32) -> bool {
    if iso_date(c) { ret true }
    let (d, m, y, yn, matched) = slash_parts(c)
    ret matched
}

// `DATETIME_RE`: `^\d{4}-\d{1,2}-\d{1,2}[ T]\d{1,2}:\d{2}`.
fn datetime_shape(c: []const u32) -> bool {
    var at = 0usize
    var n = 0usize
    while at < c.len && is_digit(c[at]) && n < 4usize {
        at += 1usize
        n += 1usize
    }
    if n != 4usize || at >= c.len || c[at] != 45u32 { ret false }
    at += 1usize
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        at += 1usize
        n += 1usize
    }
    if n == 0usize || at >= c.len || c[at] != 45u32 { ret false }
    at += 1usize
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        at += 1usize
        n += 1usize
    }
    if n == 0usize || at >= c.len || (c[at] != 32u32 && c[at] != 84u32) { ret false }
    at += 1usize
    n = 0usize
    while at < c.len && is_digit(c[at]) && n < 2usize {
        at += 1usize
        n += 1usize
    }
    if n == 0usize || at >= c.len || c[at] != 58u32 { ret false }
    at += 1usize
    ret at + 1usize < c.len && is_digit(c[at]) && is_digit(c[at + 1usize])
}

// `EMAIL_RE`: `^[^\s@]+@[^\s@]+\.[^\s@]+$`.
fn email_shape(c: []const u32) -> bool {
    var i = 0usize
    var at_sign = c.len
    while i < c.len {
        if view.js_space(c[i]) { ret false }
        if c[i] == 64u32 {
            if at_sign != c.len { ret false }
            at_sign = i
        }
        i += 1usize
    }
    if at_sign == c.len || at_sign == 0usize { ret false }
    let domain_start = at_sign + 1usize
    let n = c.len - domain_start
    if n < 3usize { ret false }
    // a '.' at position p of the domain with 1 <= p <= n - 2
    var p = 1usize
    while p + 2usize <= n {
        if c[domain_start + p] == 46u32 { ret true }
        p += 1usize
    }
    ret false
}

// `URL_RE`: `^(https?:\/\/)?([\w-]+\.)+[\w-]+(:\d+)?(\/[^\s]*)?$`, case-insensitive.
fn url_shape(c: []const u32) -> bool {
    var at = 0usize
    // optional scheme
    var scheme = false
    if c.len >= 7usize && lower_ascii(c[0usize]) == 104u32 && lower_ascii(c[1usize]) == 116u32 && lower_ascii(c[2usize]) == 116u32 && lower_ascii(c[3usize]) == 112u32 {
        var p = 4usize
        if lower_ascii(c[p]) == 115u32 { p += 1usize }
        if p + 2usize < c.len + 0usize && c[p] == 58u32 && c[p + 1usize] == 47u32 && c[p + 2usize] == 47u32 {
            scheme = true
            at = p + 3usize
        }
    }
    var labels = 0usize
    var go = true
    while go {
        var run = 0usize
        while at < c.len && (is_word(c[at]) || c[at] == 45u32) {
            at += 1usize
            run += 1usize
        }
        if run == 0usize { ret false }
        labels += 1usize
        if at < c.len && c[at] == 46u32 {
            at += 1usize
        } else {
            go = false
        }
    }
    if labels < 2usize { ret false }
    if at < c.len && c[at] == 58u32 {
        at += 1usize
        var digits = 0usize
        while at < c.len && is_digit(c[at]) {
            at += 1usize
            digits += 1usize
        }
        if digits == 0usize { ret false }
    }
    if at < c.len && c[at] == 47u32 {
        at += 1usize
        while at < c.len {
            if view.js_space(c[at]) { ret false }
            at += 1usize
        }
        ret true
    }
    ret at == c.len
}

// `PHONE_RE.test(v.replace(/[\s()-]/g, ''))`.
fn phone_shape(a: *mem.Arena, c: []const u32) -> bool {
    let (buf, e) = mem.alloc[u32](a, c.len + 1usize)
    if e != ok { ret false }
    var n = 0usize
    var i = 0usize
    while i < c.len {
        let u = c[i]
        if !(view.js_space(u) || u == 40u32 || u == 41u32 || u == 45u32) {
            buf[n] = u
            n += 1usize
        }
        i += 1usize
    }
    let p = buf[0usize..n]
    var at = 0usize
    var plus = false
    if at < p.len && p[at] == 43u32 {
        plus = true
        at += 1usize
    }
    var digits = 0usize
    var k = at
    while k < p.len && is_digit(p[k]) {
        k += 1usize
        digits += 1usize
    }
    if k != p.len || digits == 0usize { ret false }
    // ^\+?[1-9]\d{1,14}$
    if p[at] >= 49u32 && p[at] <= 57u32 && digits >= 2usize && digits <= 15usize { ret true }
    // ^0\d{6,14}$
    if !plus && p[at] == 48u32 && digits >= 7usize && digits <= 15usize { ret true }
    ret false
}

fn is_bytes4(l: str, b0: u8, b1: u8, b2: u8, b3: u8) -> bool {
    ret l.len == 4usize && l[0usize] == b0 && l[1usize] == b1 && l[2usize] == b2 && l[3usize] == b3
}

// `BOOL_TRUE.has(v.toLowerCase()) || BOOL_FALSE.has(...)`: true yes y 1 да, false no n 0 не.
fn bool_word(a: *mem.Arena, v: str) -> bool {
    let l = f.lower_text(a, v)
    if is_bytes4(l, 208u8, 180u8, 208u8, 176u8) || is_bytes4(l, 208u8, 189u8, 208u8, 181u8) { ret true }
    ret str.eq(l, "true") || str.eq(l, "yes") || str.eq(l, "y") || str.eq(l, "1") || str.eq(l, "false") || str.eq(l, "no") || str.eq(l, "n") || str.eq(l, "0")
}

// --- the ladder ------------------------------------------------------------------------------------------------------

// Candidate index: 0 checkbox, 1 percent, 2 currency, 3 number, 4 datetime, 5 date, 6 email, 7 url, 8 phone.
fn candidate_name(i: usize) -> str {
    if i == 0usize { ret "checkbox" }
    if i == 1usize { ret "percent" }
    if i == 2usize { ret "currency" }
    if i == 3usize { ret "number" }
    if i == 4usize { ret "datetime" }
    if i == 5usize { ret "date" }
    if i == 6usize { ret "email" }
    if i == 7usize { ret "url" }
    ret "phone"
}

fn candidate_test(a: *mem.Arena, i: usize, v: str, date_order: str) -> bool {
    if i == 0usize { ret bool_word(a, v) }
    if i == 1usize {
        let p = strip_percent(v)
        ret p.marked && read_shape(a, p.body).valid
    }
    if i == 2usize {
        let c = strip_currency(a, v)
        ret c.marked && read_shape(a, c.body).valid
    }
    if i == 3usize { ret is_number_cell(a, v) }
    let c = cps_of(a, v)
    if i == 4usize { ret datetime_shape(c) && date_ok(a, v) }
    if i == 5usize { ret date_shape(c) && calendar_date_ok(a, v, date_order) }
    if i == 6usize { ret email_shape(c) }
    if i == 7usize { ret url_shape(c) && !read_shape(a, v).valid }
    ret phone_shape(a, c)
}

type Inferred = struct { kind: str, options: []const str, has_options: bool, date_order: str, decimal: str }

fn is_numeric_type(kind: str) -> bool { ret str.eq(kind, "number") || str.eq(kind, "currency") || str.eq(kind, "percent") }

// `inferColumnType` over cells already converted to text (`String(v)`; null as ""). `pinned` is a mapping template's
// decimal convention ("comma", "dot" or anything else for none); `max_select` is `opts.maxSelectOptions || 20`.
fn infer_column(a: *mem.Arena, raw: []const str, pinned: str, max_select: usize) -> Inferred {
    var out = Inferred { kind: "text", options: zero, has_options: false, date_order: "", decimal: "" }
    let (kept_buf, e) = mem.alloc[str](a, raw.len + 1usize)
    if e != ok { ret out }
    var n = 0usize
    var i = 0usize
    while i < raw.len {
        let t = view.js_trim(raw[i])
        if t.len > 0usize {
            kept_buf[n] = t
            n += 1usize
        }
        i += 1usize
    }
    let values = kept_buf[0usize..n]
    if values.len == 0usize { ret out }
    let order = detect_date_order(a, values)
    var decimal = ""
    if str.eq(pinned, "comma") || str.eq(pinned, "dot") {
        decimal = pinned
    } else {
        decimal = detect_decimal(a, values).decimal
    }
    var cand = 0usize
    while cand < 9usize {
        var all = true
        i = 0usize
        while all && i < values.len {
            if !candidate_test(a, cand, values[i], order.order) { all = false }
            i += 1usize
        }
        if all {
            let kind = candidate_name(cand)
            out.kind = kind
            if str.eq(kind, "date") && order.order.len > 0usize {
                out.date_order = order.order
                ret out
            }
            if is_numeric_type(kind) && decimal.len > 0usize {
                out.decimal = decimal
                ret out
            }
            ret out
        }
        cand += 1usize
    }
    // select: distinct values in first-seen order
    let (dist_buf, de) = mem.alloc[str](a, values.len + 1usize)
    if de != ok { ret out }
    var distinct = 0usize
    i = 0usize
    while i < values.len {
        var seen = false
        var k = 0usize
        while k < distinct && !seen {
            if str.eq(dist_buf[k], values[i]) { seen = true }
            k += 1usize
        }
        if !seen {
            dist_buf[distinct] = values[i]
            distinct += 1usize
        }
        i += 1usize
    }
    if distinct <= max_select && distinct < values.len && distinct * 2usize <= values.len {
        out.kind = "select"
        out.options = dist_buf[0usize..distinct]
        out.has_options = true
        ret out
    }
    var total = 0usize
    i = 0usize
    while i < values.len {
        total += utf16_len(values[i])
        i += 1usize
    }
    // avgLen > 100  <=>  total > 100 * count
    if total > 100usize * values.len { out.kind = "longtext" }
    ret out
}

// --- records ---------------------------------------------------------------------------------------------------------

// `String(v)` of a cell: null and an absent member as empty (`v == null`), arrays and objects as JavaScript spells them.
fn cell_text(a: *mem.Arena, v: json.Value, present: bool) -> str {
    if !present { ret "" }
    switch v {
    case .Null:
        ret ""
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret n.lexeme }
        ret f.number_text(a, x)
    default:
        ret wb.js_string(a, v, true)
    }
}

// A canonical array index (`0`, `7`, `4294967294`): JavaScript lists these keys first, ascending.
fn array_index(key: str) -> (u64, bool) {
    if key.len == 0usize || key.len > 10usize { ret (0u64, false) }
    if key.len > 1usize && key[0usize] == 48u8 { ret (0u64, false) }
    var n = 0u64
    var i = 0usize
    while i < key.len {
        if key[i] < 48u8 || key[i] > 57u8 { ret (0u64, false) }
        n = n * 10u64 + u64(key[i] - 48u8)
        i += 1usize
    }
    if n > 4294967294u64 { ret (0u64, false) }
    ret (n, true)
}

// The keys of the records in order of first appearance, each record's keys in JavaScript's property order (array
// indices ascending, then the rest as written).
fn column_names(a: *mem.Arena, rows: []const json.Value) -> []const str {
    var names = list.List[str] { items: zero, len: 0usize, arena: a }
    var r = 0usize
    while r < rows.len {
        let (members, is_object) = ir.members_of(rows[r])
        if is_object {
            let (order, e) = mem.alloc[usize](a, members.len + 1usize)
            if e != ok { ret zero }
            var n = 0usize
            var m = 0usize
            while m < members.len {
                let (value, is_index) = array_index(members[m].key)
                if is_index {
                    // insertion sort by index value
                    var at = n
                    while at > 0usize {
                        let (prior, prior_ok) = array_index(members[order[at - 1usize]].key)
                        if prior > value {
                            order[at] = order[at - 1usize]
                            at -= 1usize
                        } else {
                            break
                        }
                    }
                    order[at] = m
                    n += 1usize
                }
                m += 1usize
            }
            var k = 0usize
            while k < n {
                add_name(&names, members[order[k]].key)
                k += 1usize
            }
            m = 0usize
            while m < members.len {
                let (value, is_index) = array_index(members[m].key)
                if !is_index { add_name(&names, members[m].key) }
                m += 1usize
            }
        }
        r += 1usize
    }
    ret list.slice_const[str](&names)
}

fn add_name(names: *list.List[str], key: str) {
    let held = list.slice_const[str](names)
    var i = 0usize
    while i < held.len {
        if str.eq(held[i], key) { ret }
        i += 1usize
    }
    let pushed = list.push[str](names, key)
}

fn is_structured(v: json.Value) -> bool {
    switch v {
    case .Array as xs:
        ret true
    case .Object as ms:
        ret true
    default:
        ret false
    }
}

// `proposeMapping`'s second half: `{columns, downgradeCount, inferred: true}` for sample records; `ok` is false when a
// record is not an object (appdor throws there).
fn propose_inferred(a: *mem.Arena, sample: json.Value, translate: *const syncjob.Translate) -> (json.Value, bool) {
    let (rows, is_array) = ir.items_of(sample)
    var records: []const json.Value = zero
    if is_array { records = rows }
    var r = 0usize
    while r < records.len {
        let (members, is_object) = ir.members_of(records[r])
        if !is_object { ret (.Null, false) }
        r += 1usize
    }
    let names = column_names(a, records)
    var columns = sync.empty_list(a)
    var downgrades = 0i64
    var c = 0usize
    while c < names.len {
        let name = names[c]
        var structured = false
        let (texts, e) = mem.alloc[str](a, records.len + 1usize)
        if e != ok { ret (.Null, false) }
        r = 0usize
        while r < records.len {
            let (v, present) = ir.get(records[r], name)
            if present && is_structured(v) { structured = true }
            texts[r] = cell_text(a, v, present)
            r += 1usize
        }
        var col = sync.obj(a)
        sync.put(&col, "name", sync.text(name))
        if structured {
            downgrades += 1i64
            sync.put(&col, "nativeType", sync.text("json"))
            sync.put(&col, "lc8Type", sync.text("longtext"))
            sync.put(&col, "downgraded", sync.flag(true))
            sync.put(&col, "diagnostic", sync.text(translate.run(translate.ctx, "sync.mapping.structuredValue", name)))
            sync.put(&col, "structured", sync.flag(true))
        } else {
            let inferred = infer_column(a, texts[0usize..records.len], "", 20usize)
            sync.put(&col, "nativeType", sync.text(inferred.kind))
            sync.put(&col, "lc8Type", sync.text(inferred.kind))
            sync.put(&col, "downgraded", sync.flag(false))
            sync.put(&col, "diagnostic", .Null)
            sync.put(&col, "structured", sync.flag(false))
        }
        sync.push_value(&columns, ir.obj_value(&col))
        c += 1usize
    }
    var o = sync.obj(a)
    sync.put(&o, "columns", json.Value{ Array: list.slice_const[json.Value](&columns) })
    sync.put(&o, "downgradeCount", sync.number(a, downgrades))
    sync.put(&o, "inferred", sync.flag(true))
    ret (ir.obj_value(&o), true)
}

// --- the JSON surface ------------------------------------------------------------------------------------------------

// The cells of a column given as a JSON array, each as `String(v)` (an element that is not there is empty).
fn cells_of(a: *mem.Arena, values: json.Value) -> []const str {
    let (xs, is_array) = ir.items_of(values)
    if !is_array { ret zero }
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { ret zero }
    var i = 0usize
    while i < xs.len {
        out[i] = cell_text(a, xs[i], true)
        i += 1usize
    }
    ret out[0usize..xs.len]
}

fn texts_json(a: *mem.Arena, xs: []const str) -> json.Value {
    var l = sync.empty_list(a)
    var i = 0usize
    while i < xs.len {
        sync.push_value(&l, sync.text(xs[i]))
        i += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&l) }
}

// `{type, options?, dateOrder?, decimal?}` of an inference.
fn inferred_into(a: *mem.Arena, o: *ir.Obj, i: Inferred) {
    sync.put(o, "type", sync.text(i.kind))
    if i.has_options { sync.put(o, "options", texts_json(a, i.options)) }
    if i.date_order.len > 0usize { sync.put(o, "dateOrder", sync.text(i.date_order)) }
    if i.decimal.len > 0usize { sync.put(o, "decimal", sync.text(i.decimal)) }
}

// `opts.maxSelectOptions || 20`, as a count (a negative limit selects nothing).
fn max_select_of(opts: json.Value) -> usize {
    let (v, present) = ir.get(opts, "maxSelectOptions")
    if !present { ret 20usize }
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok || x == 0.0f64 || x != x { ret 20usize }
        if x < 0.0f64 { ret 0usize }
        if x > 1000000.0f64 { ret 1000000usize }
        ret usize(x)
    case .String as s:
        ret 20usize
    default:
        ret 20usize
    }
}

fn pinned_of(opts: json.Value) -> str {
    let (v, present) = ir.get(opts, "decimal")
    if !present { ret "" }
    let (s, is_text) = ir.string_of(v)
    if is_text { ret s }
    ret ""
}

// `inferColumnType(values, opts)`.
fn infer_column_type(a: *mem.Arena, values: json.Value, opts: json.Value) -> json.Value {
    let cells = cells_of(a, values)
    let inferred = infer_column(a, cells, pinned_of(opts), max_select_of(opts))
    var o = sync.obj(a)
    inferred_into(a, &o, inferred)
    ret ir.obj_value(&o)
}

// `detectDateOrder(values)`: `{order, witness, sampled}`.
fn date_order_of(a: *mem.Arena, values: json.Value) -> json.Value {
    let found = detect_date_order(a, cells_of(a, values))
    var o = sync.obj(a)
    if found.order.len > 0usize {
        sync.put(&o, "order", sync.text(found.order))
        sync.put(&o, "witness", sync.text(found.witness))
    } else {
        sync.put(&o, "order", .Null)
        sync.put(&o, "witness", .Null)
    }
    sync.put(&o, "sampled", sync.number(a, i64(found.sampled)))
    ret ir.obj_value(&o)
}

// `detectDecimalSeparator(values)`: `{decimal, witness, sampled, conflicting}`.
fn decimal_separator_of(a: *mem.Arena, values: json.Value) -> json.Value {
    let found = detect_decimal(a, cells_of(a, values))
    var o = sync.obj(a)
    if found.decimal.len > 0usize {
        sync.put(&o, "decimal", sync.text(found.decimal))
        sync.put(&o, "witness", sync.text(found.witness))
    } else {
        sync.put(&o, "decimal", .Null)
        sync.put(&o, "witness", .Null)
    }
    sync.put(&o, "sampled", sync.number(a, i64(found.sampled)))
    sync.put(&o, "conflicting", sync.flag(found.conflicting))
    ret ir.obj_value(&o)
}

// `inferExternalSchema(records)`: `[{name, type, options?, dateOrder?, decimal?}]`; `ok` is false for a record that is
// not an object (appdor throws there).
fn infer_external_schema(a: *mem.Arena, records: json.Value) -> (json.Value, bool) {
    let (rows, is_array) = ir.items_of(records)
    if !is_array { ret (.Null, false) }
    var r = 0usize
    while r < rows.len {
        let (members, is_object) = ir.members_of(rows[r])
        if !is_object { ret (.Null, false) }
        r += 1usize
    }
    let names = column_names(a, rows)
    var out = sync.empty_list(a)
    var c = 0usize
    while c < names.len {
        let (texts, e) = mem.alloc[str](a, rows.len + 1usize)
        if e != ok { ret (.Null, false) }
        r = 0usize
        while r < rows.len {
            let (v, present) = ir.get(rows[r], names[c])
            texts[r] = cell_text(a, v, present)
            r += 1usize
        }
        let inferred = infer_column(a, texts[0usize..rows.len], "", 20usize)
        var col = sync.obj(a)
        sync.put(&col, "name", sync.text(names[c]))
        inferred_into(a, &col, inferred)
        sync.push_value(&out, ir.obj_value(&col))
        c += 1usize
    }
    ret (json.Value{ Array: list.slice_const[json.Value](&out) }, true)
}
