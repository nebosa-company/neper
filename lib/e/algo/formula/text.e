// The text function group of the formula library (L027): CHAR, UNICHAR, CODE, UNICODE, CONCATENATE, CONTAINS,
// EXACT, SAME, FIND, SEARCH, ISEMAIL, ISURL, LEFT, RIGHT, MID, LEN, LOWER, UPPER, PROPER, REVERSE, REPEAT, REPLACE,
// SUBSTITUTE, TEXTJOIN, TRIM, WORDCOUNT, OCCURANCE, SOUNDEX, REGEXMATCH, REGEXEXTRACT, REGEXREPLACE, STARTS_WITH,
// ENDS_WITH, CASING, CLEAN, DECODE_URL_COMPONENT, INITIALS, PADLEFT, PADRIGHT, PAD, PART, EXTRACTEMAILS,
// EXTRACTNUMBERS, EXTRACTPRICES, EXTRACTHASHTAGS, EXTRACTPHONENUMBERS, EXTRACTDOMAINS, EXTRACTDATES and EXTRACT.
// Each follows appdor's `src/formula/text.js` with the same names, aliases, arities and messages.
//
// Positions and lengths count UTF-16 code units, as JavaScript's do: LEN of an emoji is 2 and LEFT can cut it in
// two (the lone half then reads as U+FFFD in UTF-8 text). Patterns are `e.text.regex`'s backtracking engine, which
// speaks the common subset of JavaScript's syntax; one that engine refuses answers `#VALUE!` with appdor's
// message. Differences: `\s` in a pattern is ASCII white space; case mapping is the simple Unicode one with the
// special cases of sharp s, the `ff`/`fi`/`fl` ligatures, dotted capital I and the final sigma; the replacement
// string of REGEXREPLACE has `$$ $& $` $' $n` but no `$<name>`.

use e.algo.formula as f
use e.math
use e.mem
use e.str
use e.text.regex as regex
use e.text.unicode as unicode
use e.text.utf8 as utf8

fn max_regex_input() -> usize { ret 100000usize }

// --- UTF-16 views -----------------------------------------------------------------------------------------------------

fn utf16_len(s: str) -> usize {
    var n = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            n += 1usize
            if scalar >= 65536u32 { n += 1usize }
        }
    }
    ret n
}

fn units_of(a: *mem.Arena, s: str) -> []u16 {
    var none: []u16 = zero
    let n = utf16_len(s)
    if n == 0usize { ret none }
    let (out, e) = mem.alloc[u16](a, n)
    if e != ok { ret none }
    var w = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else if scalar >= 65536u32 {
            out[w] = u16(55296u32 + ((scalar - 65536u32) >> 10u32))
            out[w + 1usize] = u16(56320u32 + ((scalar - 65536u32) & 1023u32))
            w += 2usize
        } else {
            out[w] = u16(scalar)
            w += 1usize
        }
    }
    ret out
}

// UTF-8 text of UTF-16 units; a lone surrogate is U+FFFD.
fn text_of_units(a: *mem.Arena, units: []const u16) -> str {
    if units.len == 0usize { ret "" }
    let (out, e) = mem.alloc[u8](a, units.len * 3usize)
    if e != ok { ret "" }
    var w = 0usize
    var i = 0usize
    while i < units.len {
        var scalar = u32(units[i])
        if scalar >= 55296u32 && scalar <= 56319u32 && i + 1usize < units.len && u32(units[i + 1usize]) >= 56320u32 && u32(units[i + 1usize]) <= 57343u32 {
            scalar = 65536u32 + ((scalar - 55296u32) << 10u32) + (u32(units[i + 1usize]) - 56320u32)
            i += 1usize
        } else if scalar >= 55296u32 && scalar <= 57343u32 {
            scalar = 65533u32
        }
        var piece: [4]u8 = zero
        let (width, we) = utf8.encode(scalar, piece[0..])
        var k = 0usize
        while k < usize(width) {
            out[w] = piece[k]
            w += 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret out[0usize..w]
}

fn scalar_width(scalar: u32) -> usize {
    if scalar < 128u32 { ret 1usize }
    if scalar < 2048u32 { ret 2usize }
    if scalar < 65536u32 { ret 3usize }
    ret 4usize
}

// A text argument: the text of the value (an error value would already have been returned by the evaluator).
fn text_arg(c: *f.Call, i: usize) -> str {
    let t = f.to_text(c.a, c.args[i])
    if f.is_error(t) { ret f.code_text(t.code) }
    ret t.s
}

// JavaScript white space (WhiteSpace and LineTerminator).
fn js_space(u: u32) -> bool {
    if u == 32u32 || (u >= 9u32 && u <= 13u32) || u == 160u32 || u == 5760u32 || (u >= 8192u32 && u <= 8202u32) { ret true }
    ret u == 8232u32 || u == 8233u32 || u == 8239u32 || u == 8287u32 || u == 12288u32 || u == 65279u32
}

fn is_word_unit(u: u32) -> bool { ret (u >= 48u32 && u <= 57u32) || (u >= 65u32 && u <= 90u32) || (u >= 97u32 && u <= 122u32) || u == 95u32 }

// `Math.trunc(x ?? default)` as a non-negative usize clamp: negative is 0, huge saturates.
fn clamp_index(x: f64) -> usize {
    if x != x { ret 0usize }
    if x <= 0.0f64 { ret 0usize }
    if x >= 4294967295.0f64 { ret 4294967295usize }
    ret usize(math.trunc[f64](x))
}

fn number_or(c: *f.Call, i: usize, fallback: f64) -> (f64, f.Value) {
    let n = f.to_number(c.a, c.args[i])
    if f.is_error(n) { ret (0.0f64, n) }
    if n.kind == .Blank { ret (fallback, f.blank()) }
    ret (math.trunc[f64](n.n), f.blank())
}

// --- case ---------------------------------------------------------------------------------------------------------

fn is_cased(scalar: u32) -> bool {
    let cat = unicode.category(scalar)
    ret cat == unicode.Category.Lu || cat == unicode.Category.Ll || cat == unicode.Category.Lt
}

fn push_scalar(out: []u8, at: usize, scalar: u32) -> usize {
    var piece: [4]u8 = zero
    let (width, e) = utf8.encode(scalar, piece[0..])
    var k = 0usize
    while k < usize(width) {
        out[at + k] = piece[k]
        k += 1usize
    }
    ret at + usize(width)
}

// `toLowerCase`: simple mapping, with dotted capital I and the final sigma.
fn lower_text(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 8usize)
    if e != ok { ret s }
    var w = 0usize
    var prev_cased = false
    var off = 0usize
    while off < s.len {
        let (d, de) = utf8.decode(s, off)
        var scalar = u32(0xFFFDu32)
        var width = 1usize
        if de == ok {
            scalar = d.scalar
            width = usize(d.width)
        }
        if scalar == 304u32 {
            w = push_scalar(out, w, 105u32)
            w = push_scalar(out, w, 775u32)
        } else if scalar == 931u32 {
            // final sigma: after a cased letter and not before one
            var next_cased = false
            var q = off + width
            if q < s.len {
                let (nd, ne) = utf8.decode(s, q)
                if ne == ok { next_cased = is_cased(nd.scalar) }
            }
            if prev_cased && !next_cased { w = push_scalar(out, w, 962u32) } else { w = push_scalar(out, w, 963u32) }
        } else {
            w = push_scalar(out, w, unicode.to_lower_simple(scalar))
        }
        prev_cased = is_cased(scalar)
        off += width
    }
    ret out[0usize..w]
}

// `toUpperCase`: simple mapping with the multi-character cases of sharp s and the Latin ligatures.
fn upper_text(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 8usize)
    if e != ok { ret s }
    var w = 0usize
    var off = 0usize
    while off < s.len {
        let (d, de) = utf8.decode(s, off)
        var scalar = u32(0xFFFDu32)
        var width = 1usize
        if de == ok {
            scalar = d.scalar
            width = usize(d.width)
        }
        if scalar == 223u32 {
            w = push_scalar(out, w, 83u32)
            w = push_scalar(out, w, 83u32)
        } else if scalar == 64256u32 {
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 70u32)
        } else if scalar == 64257u32 {
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 73u32)
        } else if scalar == 64258u32 {
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 76u32)
        } else if scalar == 64259u32 {
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 73u32)
        } else if scalar == 64260u32 {
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 70u32)
            w = push_scalar(out, w, 76u32)
        } else {
            w = push_scalar(out, w, unicode.to_upper_simple(scalar))
        }
        off += width
    }
    ret out[0usize..w]
}

// --- single functions -----------------------------------------------------------------------------------------------

fn h_char(c: *f.Call) -> f.Value {
    let n = f.to_number(c.a, c.args[0usize])
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.text("") }
    let t = math.trunc[f64](n.n)
    var code = 0u32
    if t == t && t - t == 0.0f64 {
        var m = f.fmod(t, 65536.0f64)
        if m < 0.0f64 { m = m + 65536.0f64 }
        code = u32(m)
    }
    var one: [1]u16 = zero
    one[0usize] = u16(code)
    ret f.text(text_of_units(c.a, one[0..]))
}

fn h_unichar(c: *f.Call) -> f.Value {
    let n = f.to_number(c.a, c.args[0usize])
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.text("") }
    let t = math.trunc[f64](n.n)
    if !(t == t) || t < 0.0f64 || t > 1114111.0f64 {
        ret f.generic_error(f.join(c.a, "Invalid code point ", f.number_text(c.a, t)))
    }
    let code = u32(t)
    if code >= 55296u32 && code <= 57343u32 { ret f.text("\xEF\xBF\xBD") }
    let (out, e) = mem.alloc[u8](c.a, 4usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let used = push_scalar(out, 0usize, code)
    ret f.text(out[0usize..used])
}

fn h_code(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if s.len == 0usize { ret f.value_error("CODE of empty text") }
    let units = units_of(c.a, s)
    ret f.number(f64(units[0usize]))
}

fn h_unicode(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if s.len == 0usize { ret f.value_error("UNICODE of empty text") }
    let units = units_of(c.a, s)
    let first = u32(units[0usize])
    if first >= 55296u32 && first <= 56319u32 && units.len > 1usize {
        let second = u32(units[1usize])
        if second >= 56320u32 && second <= 57343u32 {
            ret f.number(f64(65536u32 + ((first - 55296u32) << 10u32) + (second - 56320u32)))
        }
    }
    ret f.number(f64(first))
}

// Text of an element for concatenation: an error value is its code, as JavaScript writes the error object.
fn element_text(c: *f.Call, v: f.Value) -> str {
    if f.is_blank(v) { ret "" }
    let t = f.to_text(c.a, v)
    if f.is_error(t) { ret f.code_text(t.code) }
    ret t.s
}

fn h_concatenate(c: *f.Call) -> f.Value {
    var out = ""
    var i = 0usize
    while i < c.args.len {
        let a = c.args[i]
        if a.kind == .Array {
            var k = 0usize
            while k < a.items.len {
                out = f.join(c.a, out, element_text(c, a.items[k]))
                k += 1usize
            }
        } else {
            out = f.join(c.a, out, element_text(c, a))
        }
        i += 1usize
    }
    ret f.text(out)
}

fn includes(hay: str, needle: str) -> bool { ret str.contains(hay, needle) }

fn h_contains(c: *f.Call) -> f.Value { ret f.boolean(includes(text_arg(c, 0usize), text_arg(c, 1usize))) }

fn h_exact(c: *f.Call) -> f.Value { ret f.boolean(str.eq(text_arg(c, 0usize), text_arg(c, 1usize))) }

// JavaScript truthiness of a value (for `Boolean(args[i])`).
fn truthy(v: f.Value) -> bool {
    if v.kind == .Blank { ret false }
    if v.kind == .Number { ret v.n != 0.0f64 && v.n == v.n }
    if v.kind == .Bool { ret v.n != 0.0f64 }
    if v.kind == .Text { ret v.s.len > 0usize }
    ret true
}

fn h_same(c: *f.Call) -> f.Value {
    let x = text_arg(c, 0usize)
    let y = text_arg(c, 1usize)
    var sensitive = false
    if c.args.len > 2usize { sensitive = truthy(c.args[2usize]) }
    if sensitive { ret f.boolean(str.eq(x, y)) }
    ret f.boolean(str.eq(lower_text(c.a, x), lower_text(c.a, y)))
}

// The index of `needle` in `hay` from UTF-16 position `from` (indexOf), or -1.
fn index_of_units(hay: []const u16, needle: []const u16, from: usize) -> i64 {
    var start = from
    if start > hay.len { start = hay.len }
    if needle.len == 0usize { ret i64(start) }
    var i = start
    while i + needle.len <= hay.len {
        var j = 0usize
        while j < needle.len && hay[i + j] == needle[j] { j += 1usize }
        if j == needle.len { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

fn find_impl(c: *f.Call, case_sensitive: bool) -> f.Value {
    var needle = text_arg(c, 0usize)
    var hay = text_arg(c, 1usize)
    var start = 1.0f64
    if c.args.len > 2usize {
        let n = f.to_number(c.a, c.args[2usize])
        if f.is_error(n) { ret n }
        if n.kind != .Blank { start = n.n }
    }
    var from_value = math.trunc[f64](start) - 1.0f64
    if from_value < 0.0f64 { from_value = 0.0f64 }
    if !case_sensitive {
        needle = lower_text(c.a, needle)
        hay = lower_text(c.a, hay)
    }
    let idx = index_of_units(units_of(c.a, hay), units_of(c.a, needle), clamp_index(from_value))
    if idx == -1i64 { ret f.number(0.0f64) }
    ret f.number(f64(idx + 1i64))
}

fn h_find(c: *f.Call) -> f.Value { ret find_impl(c, true) }

fn h_search(c: *f.Call) -> f.Value { ret find_impl(c, false) }

fn h_isemail(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    var ats = 0usize
    var at_pos = 0usize
    var it = utf8.iterator(s)
    var more = true
    var pos = 0usize
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            if js_space(scalar) { ret f.boolean(false) }
            if scalar == 64u32 {
                ats += 1usize
                at_pos = pos
            }
            pos += scalar_width(scalar)
        }
    }
    if ats != 1usize || at_pos == 0usize { ret f.boolean(false) }
    let domain = s[at_pos + 1usize..s.len]
    // a '.' with something on both sides
    var i = 1usize
    while i + 1usize < domain.len {
        if domain[i] == 46u8 { ret f.boolean(true) }
        i += 1usize
    }
    ret f.boolean(false)
}

fn is_label_byte(b: u8) -> bool { ret is_word_unit(u32(b)) || b == 45u8 }

fn h_isurl(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    var at = 0usize
    if s.len >= 7usize && str.compare_ascii_fold(s[0usize..7usize], "http://") == 0i32 { at = 7usize }
    if s.len >= 8usize && str.compare_ascii_fold(s[0usize..8usize], "https://") == 0i32 { at = 8usize }
    // the host: the longest run of label bytes and dots
    var end = at
    while end < s.len && (is_label_byte(s[end]) || s[end] == 46u8) { end += 1usize }
    let host = s[at..end]
    if host.len == 0usize { ret f.boolean(false) }
    var labels = 0usize
    var label_len = 0usize
    var i = 0usize
    while i <= host.len {
        if i == host.len || host[i] == 46u8 {
            if label_len == 0usize { ret f.boolean(false) }
            labels += 1usize
            label_len = 0usize
        } else {
            label_len += 1usize
        }
        i += 1usize
    }
    if labels < 2usize { ret f.boolean(false) }
    if end == s.len { ret f.boolean(true) }
    if s[end] != 47u8 { ret f.boolean(false) }
    var p = end + 1usize
    var it = utf8.iterator(s[p..s.len])
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else if js_space(scalar) {
            ret f.boolean(false)
        }
    }
    ret f.boolean(true)
}

fn h_left(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    var n = 1.0f64
    if c.args.len > 1usize {
        let (v, failure) = number_or(c, 1usize, 1.0f64)
        if f.is_error(failure) { ret failure }
        n = v
    }
    let units = units_of(c.a, s)
    var k = n
    if k < 0.0f64 { k = 0.0f64 }
    let take = math.min[f64](k, f64(units.len))
    ret f.text(text_of_units(c.a, units[0usize..usize(take)]))
}

fn h_right(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    var n = 1.0f64
    if c.args.len > 1usize {
        let (v, failure) = number_or(c, 1usize, 1.0f64)
        if f.is_error(failure) { ret failure }
        n = v
    }
    var k = n
    if k < 0.0f64 { k = 0.0f64 }
    if k == 0.0f64 { ret f.text("") }
    let units = units_of(c.a, s)
    let take = math.min[f64](k, f64(units.len))
    ret f.text(text_of_units(c.a, units[units.len - usize(take)..units.len]))
}

fn h_mid(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let start = f.to_number(c.a, c.args[1usize])
    let length = f.to_number(c.a, c.args[2usize])
    if f.is_error(start) { ret start }
    if f.is_error(length) { ret length }
    var st = 0.0f64
    if start.kind != .Blank { st = math.trunc[f64](start.n) }
    var from = st - 1.0f64
    if from < 0.0f64 { from = 0.0f64 }
    var count = 0.0f64
    if length.kind != .Blank { count = math.trunc[f64](length.n) }
    if count < 0.0f64 { count = 0.0f64 }
    let units = units_of(c.a, s)
    if from >= f64(units.len) { ret f.text("") }
    let first = usize(from)
    var stop = f64(first) + count
    if stop > f64(units.len) { stop = f64(units.len) }
    ret f.text(text_of_units(c.a, units[first..usize(stop)]))
}

fn h_len(c: *f.Call) -> f.Value { ret f.number(f64(utf16_len(text_arg(c, 0usize)))) }

fn h_lower(c: *f.Call) -> f.Value { ret f.text(lower_text(c.a, text_arg(c, 0usize))) }

fn h_upper(c: *f.Call) -> f.Value { ret f.text(upper_text(c.a, text_arg(c, 0usize))) }

fn h_proper(c: *f.Call) -> f.Value {
    let units = units_of(c.a, text_arg(c, 0usize))
    if units.len == 0usize { ret f.text("") }
    let (out, e) = mem.alloc[u16](c.a, units.len)
    if e != ok { ret f.generic_error("Out of memory") }
    var i = 0usize
    while i < units.len {
        var u = u32(units[i])
        if is_word_unit(u) {
            let prev_word = i > 0usize && is_word_unit(u32(units[i - 1usize]))
            if prev_word {
                if u >= 65u32 && u <= 90u32 { u += 32u32 }
            } else {
                if u >= 97u32 && u <= 122u32 { u -= 32u32 }
            }
        }
        out[i] = u16(u)
        i += 1usize
    }
    ret f.text(text_of_units(c.a, out))
}

fn h_reverse(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if s.len == 0usize { ret f.text("") }
    let (out, e) = mem.alloc[u8](c.a, s.len)
    if e != ok { ret f.generic_error("Out of memory") }
    var off = 0usize
    var at = s.len
    while off < s.len {
        let (d, de) = utf8.decode(s, off)
        var width = 1usize
        if de == ok { width = usize(d.width) }
        at -= width
        var k = 0usize
        while k < width {
            out[at + k] = s[off + k]
            k += 1usize
        }
        off += width
    }
    ret f.text(out[0usize..s.len])
}

fn repeat_text(a: *mem.Arena, s: str, count: usize) -> str {
    if s.len == 0usize || count == 0usize { ret "" }
    let (out, e) = mem.alloc[u8](a, s.len * count)
    if e != ok { ret "" }
    var w = 0usize
    var i = 0usize
    while i < count {
        var k = 0usize
        while k < s.len {
            out[w] = s[k]
            w += 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret out[0usize..w]
}

fn h_repeat(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let n = f.to_number(c.a, c.args[1usize])
    if f.is_error(n) { ret n }
    var count = 0.0f64
    if n.kind != .Blank { count = math.trunc[f64](n.n) }
    if count < 0.0f64 { count = 0.0f64 }
    let units = f64(utf16_len(s))
    if units * count > f64(max_regex_input()) { ret f.value_error("REPEAT result too large") }
    ret f.text(repeat_text(c.a, s, usize(count)))
}

fn h_replace(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let start = f.to_number(c.a, c.args[1usize])
    let count = f.to_number(c.a, c.args[2usize])
    let repl = text_arg(c, 3usize)
    if f.is_error(start) { ret start }
    if f.is_error(count) { ret count }
    var st = 0.0f64
    if start.kind != .Blank { st = math.trunc[f64](start.n) }
    var from = st - 1.0f64
    if from < 0.0f64 { from = 0.0f64 }
    var n = 0.0f64
    if count.kind != .Blank { n = math.trunc[f64](count.n) }
    if n < 0.0f64 { n = 0.0f64 }
    let units = units_of(c.a, s)
    let len = f64(units.len)
    let head = usize(math.min[f64](from, len))
    let tail_from = usize(math.min[f64](from + n, len))
    let h = text_of_units(c.a, units[0usize..head])
    let t = text_of_units(c.a, units[tail_from..units.len])
    ret f.text(f.join(c.a, f.join(c.a, h, repl), t))
}

fn h_substitute(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let old_text = text_arg(c, 1usize)
    let new_text = text_arg(c, 2usize)
    if old_text.len == 0usize { ret f.text(s) }
    if c.args.len > 3usize {
        let inst = f.to_number(c.a, c.args[3usize])
        if f.is_error(inst) { ret inst }
        var wanted = 0.0f64
        if inst.kind != .Blank { wanted = math.trunc[f64](inst.n) }
        let hay = units_of(c.a, s)
        let needle = units_of(c.a, old_text)
        var idx = -1i64
        var count = 0.0f64
        var more = true
        while more {
            let found = index_of_units(hay, needle, usize(idx + 1i64))
            if found == -1i64 {
                more = false
            } else {
                idx = found
                count += 1.0f64
                if count == wanted {
                    let head = text_of_units(c.a, hay[0usize..usize(idx)])
                    let tail = text_of_units(c.a, hay[usize(idx) + needle.len..hay.len])
                    ret f.text(f.join(c.a, f.join(c.a, head, new_text), tail))
                }
            }
        }
        ret f.text(s)
    }
    let (replaced, e) = str.replace(c.a, s, old_text, new_text)
    if e != ok { ret f.generic_error("Out of memory") }
    ret f.text(replaced)
}

fn h_textjoin(c: *f.Call) -> f.Value {
    let delim = text_arg(c, 0usize)
    let ignore_empty = truthy(c.args[1usize])
    var out = ""
    var first = true
    var i = 2usize
    while i < c.args.len {
        let a = c.args[i]
        if a.kind == .Array {
            var k = 0usize
            while k < a.items.len {
                let v = a.items[k]
                if f.is_blank(v) {
                    if !ignore_empty {
                        if !first { out = f.join(c.a, out, delim) }
                        first = false
                    }
                } else {
                    if !first { out = f.join(c.a, out, delim) }
                    out = f.join(c.a, out, element_text(c, v))
                    first = false
                }
                k += 1usize
            }
        } else {
            if f.is_blank(a) {
                if !ignore_empty {
                    if !first { out = f.join(c.a, out, delim) }
                    first = false
                }
            } else {
                if !first { out = f.join(c.a, out, delim) }
                out = f.join(c.a, out, element_text(c, a))
                first = false
            }
        }
        i += 1usize
    }
    ret f.text(out)
}

// `s.replace(/\s+/g, ' ').trim()`
fn trim_units(a: *mem.Arena, s: str) -> str {
    let units = units_of(a, s)
    if units.len == 0usize { ret "" }
    let (out, e) = mem.alloc[u16](a, units.len)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    var in_space = false
    while i < units.len {
        if js_space(u32(units[i])) {
            if !in_space {
                out[n] = 32u16
                n += 1usize
            }
            in_space = true
        } else {
            out[n] = units[i]
            n += 1usize
            in_space = false
        }
        i += 1usize
    }
    var from = 0usize
    var to = n
    if to > from && out[from] == 32u16 { from += 1usize }
    if to > from && out[to - 1usize] == 32u16 { to -= 1usize }
    ret text_of_units(a, out[from..to])
}

fn h_trim(c: *f.Call) -> f.Value { ret f.text(trim_units(c.a, text_arg(c, 0usize))) }

fn h_wordcount(c: *f.Call) -> f.Value {
    let t = trim_units(c.a, text_arg(c, 0usize))
    if t.len == 0usize { ret f.number(0.0f64) }
    var n = 1usize
    var i = 0usize
    while i < t.len {
        if t[i] == 32u8 { n += 1usize }
        i += 1usize
    }
    ret f.number(f64(n))
}

fn h_occurance(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let sub = text_arg(c, 1usize)
    if sub.len == 0usize { ret f.number(0.0f64) }
    let hay = units_of(c.a, s)
    let needle = units_of(c.a, sub)
    var count = 0.0f64
    var idx = -1i64
    var more = true
    while more {
        let found = index_of_units(hay, needle, usize(idx + 1i64))
        if found == -1i64 {
            more = false
        } else {
            idx = found
            count += 1.0f64
        }
    }
    ret f.number(count)
}

fn soundex_code(b: u8) -> u8 {
    if b == 66u8 || b == 70u8 || b == 80u8 || b == 86u8 { ret 1u8 }
    if b == 67u8 || b == 71u8 || b == 74u8 || b == 75u8 || b == 81u8 || b == 83u8 || b == 88u8 || b == 90u8 { ret 2u8 }
    if b == 68u8 || b == 84u8 { ret 3u8 }
    if b == 76u8 { ret 4u8 }
    if b == 77u8 || b == 78u8 { ret 5u8 }
    if b == 82u8 { ret 6u8 }
    ret 0u8
}

fn h_soundex(c: *f.Call) -> f.Value {
    let upper = upper_text(c.a, text_arg(c, 0usize))
    var letters: [512]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < upper.len && n < 512usize {
        if upper[i] >= 65u8 && upper[i] <= 90u8 {
            letters[n] = upper[i]
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize { ret f.text("") }
    var out: [4]u8 = zero
    out[0usize] = letters[0usize]
    var len = 1usize
    var prev = soundex_code(letters[0usize])
    var k = 1usize
    while k < n && len < 4usize {
        let code = soundex_code(letters[k])
        if code != 0u8 && code != prev {
            out[len] = 48u8 + code
            len += 1usize
        }
        if letters[k] != 72u8 && letters[k] != 87u8 { prev = code }
        k += 1usize
    }
    while len < 4usize {
        out[len] = 48u8
        len += 1usize
    }
    let (result, e) = mem.alloc[u8](c.a, 4usize)
    if e != ok { ret f.generic_error("Out of memory") }
    var j = 0usize
    while j < 4usize {
        result[j] = out[j]
        j += 1usize
    }
    ret f.text(result[0usize..4usize])
}

// --- regular expressions --------------------------------------------------------------------------------------------

// JavaScript's sloppy-mode pattern syntax (Annex B) takes a `{` that does not open a valid `{n}`, `{n,}` or
// `{n,m}` quantifier as a literal, and a stray `}` or `]` too; the engine wants those escaped.
fn annex_b(a: *mem.Arena, pattern: str) -> str {
    let (out, e) = mem.alloc[u8](a, pattern.len * 2usize + 1usize)
    if e != ok { ret pattern }
    var w = 0usize
    var i = 0usize
    var in_class = false
    while i < pattern.len {
        let b = pattern[i]
        if b == 92u8 && i + 1usize < pattern.len {
            out[w] = b
            out[w + 1usize] = pattern[i + 1usize]
            w += 2usize
            i += 2usize
        } else if in_class {
            if b == 93u8 { in_class = false }
            out[w] = b
            w += 1usize
            i += 1usize
        } else if b == 91u8 {
            in_class = true
            out[w] = b
            w += 1usize
            i += 1usize
        } else if b == 123u8 {
            // a quantifier: digits, optionally a comma and digits, then a closing brace
            var q = i + 1usize
            var digits = 0usize
            while q < pattern.len && pattern[q] >= 48u8 && pattern[q] <= 57u8 {
                q += 1usize
                digits += 1usize
            }
            var valid = false
            if digits > 0usize && q < pattern.len {
                if pattern[q] == 125u8 {
                    valid = true
                } else if pattern[q] == 44u8 {
                    q += 1usize
                    while q < pattern.len && pattern[q] >= 48u8 && pattern[q] <= 57u8 { q += 1usize }
                    valid = q < pattern.len && pattern[q] == 125u8
                }
            }
            if valid {
                var k = i
                while k <= q {
                    out[w] = pattern[k]
                    w += 1usize
                    k += 1usize
                }
                i = q + 1usize
            } else {
                out[w] = 92u8
                out[w + 1usize] = 123u8
                w += 2usize
                i += 1usize
            }
        } else if b == 125u8 || b == 93u8 {
            out[w] = 92u8
            out[w + 1usize] = b
            w += 2usize
            i += 1usize
        } else {
            out[w] = b
            w += 1usize
            i += 1usize
        }
    }
    ret out[0usize..w]
}

// A compiled pattern, or the `#VALUE!` error appdor answers.
fn compile_pattern(c: *f.Call, pattern: str, ignore_case: bool) -> (regex.Regex, f.Value) {
    let (re, e) = regex.compile_backtracking(c.a, annex_b(c.a, pattern), regex.Options { case_insensitive: ignore_case, multiline: false, dot_matches_newline: false })
    if e != ok {
        var none: regex.Regex = zero
        ret (none, f.value_error(f.join(c.a, "Invalid regular expression: ", pattern)))
    }
    ret (re, f.blank())
}

fn h_regexmatch(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if utf16_len(s) > max_regex_input() { ret f.value_error("Input too large for regex") }
    let (re, failure) = compile_pattern(c, text_arg(c, 1usize), false)
    if f.is_error(failure) { ret failure }
    ret f.boolean(regex.is_match(&re, s))
}

fn h_regexextract(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if utf16_len(s) > max_regex_input() { ret f.value_error("Input too large for regex") }
    let (re, failure) = compile_pattern(c, text_arg(c, 1usize), false)
    if f.is_error(failure) { ret failure }
    let (caps, found, ce) = regex.captures(c.a, &re, s, 0usize)
    if !found { ret f.text("") }
    var group = 0.0f64
    if c.args.len > 2usize {
        let n = f.to_number(c.a, c.args[2usize])
        // unconvertible text is an error object, which truncates to NaN and indexes nothing
        if f.is_error(n) { ret f.text("") }
        if n.kind != .Blank { group = math.trunc[f64](n.n) }
    } else if caps.groups.len > 0usize {
        group = 1.0f64
    }
    if group < 0.0f64 || group > f64(caps.groups.len) { ret f.text("") }
    var m = caps.whole
    if group >= 1.0f64 { m = caps.groups[usize(group) - 1usize] }
    if m.start == regex.NONE || m.end == regex.NONE { ret f.text("") }
    ret f.text(s[m.start..m.end])
}

// JavaScript's expansion of a replacement string against one match.
fn expand_replacement(a: *mem.Arena, s: str, caps: regex.Captures, replacement: str) -> str {
    var out = ""
    var i = 0usize
    let groups = caps.groups.len
    while i < replacement.len {
        let b = replacement[i]
        if b == 36u8 && i + 1usize < replacement.len {
            let n = replacement[i + 1usize]
            if n == 36u8 {
                out = f.join(a, out, "$")
                i += 2usize
                continue
            }
            if n == 38u8 {
                out = f.join(a, out, s[caps.whole.start..caps.whole.end])
                i += 2usize
                continue
            }
            if n == 96u8 {
                out = f.join(a, out, s[0usize..caps.whole.start])
                i += 2usize
                continue
            }
            if n == 39u8 {
                out = f.join(a, out, s[caps.whole.end..s.len])
                i += 2usize
                continue
            }
            if n >= 48u8 && n <= 57u8 {
                var two = 0usize
                var used = 0usize
                if i + 2usize < replacement.len && replacement[i + 2usize] >= 48u8 && replacement[i + 2usize] <= 57u8 {
                    two = usize(n - 48u8) * 10usize + usize(replacement[i + 2usize] - 48u8)
                }
                var group = 0usize
                if two >= 1usize && two <= groups {
                    group = two
                    used = 3usize
                } else {
                    let one_digit = usize(n - 48u8)
                    if one_digit >= 1usize && one_digit <= groups {
                        group = one_digit
                        used = 2usize
                    }
                }
                if used > 0usize {
                    let m = caps.groups[group - 1usize]
                    if m.start != regex.NONE && m.end != regex.NONE { out = f.join(a, out, s[m.start..m.end]) }
                    i += used
                    continue
                }
            }
        }
        out = f.join(a, out, replacement[i..i + 1usize])
        i += 1usize
    }
    ret out
}

fn h_regexreplace(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if utf16_len(s) > max_regex_input() { ret f.value_error("Input too large for regex") }
    let (re, failure) = compile_pattern(c, text_arg(c, 1usize), false)
    if f.is_error(failure) { ret failure }
    let replacement = text_arg(c, 2usize)
    var out = ""
    var pos = 0usize
    var copied = 0usize
    var more = true
    while more && pos <= s.len {
        let (caps, found, ce) = regex.captures(c.a, &re, s, pos)
        if !found {
            more = false
        } else {
            out = f.join(c.a, out, s[copied..caps.whole.start])
            out = f.join(c.a, out, expand_replacement(c.a, s, caps, replacement))
            copied = caps.whole.end
            if caps.whole.end == caps.whole.start {
                // advance one code point past an empty match
                if caps.whole.end >= s.len {
                    pos = s.len + 1usize
                } else {
                    let (d, de) = utf8.decode(s, caps.whole.end)
                    var w = 1usize
                    if de == ok { w = usize(d.width) }
                    pos = caps.whole.end + w
                }
            } else {
                pos = caps.whole.end
            }
        }
    }
    if copied <= s.len { out = f.join(c.a, out, s[copied..s.len]) }
    ret f.text(out)
}

// --- the remaining names --------------------------------------------------------------------------------------------

fn h_starts_with(c: *f.Call) -> f.Value {
    var hay = text_arg(c, 0usize)
    var needle = text_arg(c, 1usize)
    var sensitive = false
    if c.args.len > 2usize { sensitive = f.to_bool(c.args[2usize]) }
    if !sensitive {
        hay = lower_text(c.a, hay)
        needle = lower_text(c.a, needle)
    }
    ret f.boolean(str.starts_with(hay, needle))
}

fn h_ends_with(c: *f.Call) -> f.Value {
    var hay = text_arg(c, 0usize)
    var needle = text_arg(c, 1usize)
    var sensitive = false
    if c.args.len > 2usize { sensitive = f.to_bool(c.args[2usize]) }
    if !sensitive {
        hay = lower_text(c.a, hay)
        needle = lower_text(c.a, needle)
    }
    ret f.boolean(str.ends_with(hay, needle))
}

// The words of the casing module: cut at non-letters and digits, at lower-to-upper, and before the last capital
// of a run that is followed by a lower-case letter.
fn casing_words(a: *mem.Arena, s: str, out: []str) -> usize {
    // First pass: a text with a space where the two regex replacements put one.
    let (buffer, e) = mem.alloc[u8](a, s.len * 2usize + 8usize)
    if e != ok { ret 0usize }
    var w = 0usize
    // scalars with categories
    var scalars: []u32 = zero
    var count = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got { more = false } else { count += 1usize }
    }
    if count == 0usize { ret 0usize }
    let (sc, se) = mem.alloc[u32](a, count)
    if se != ok { ret 0usize }
    scalars = sc
    it = utf8.iterator(s)
    var k = 0usize
    more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            scalars[k] = scalar
            k += 1usize
        }
    }
    let (marks, me) = mem.alloc[bool](a, count + 1usize)
    if me != ok { ret 0usize }
    var i = 0usize
    while i <= count {
        marks[i] = false
        i += 1usize
    }
    // ([\p{Ll}\p{N}])(\p{Lu}) -> a space between
    i = 0usize
    while i + 1usize < count {
        let c1 = unicode.category(scalars[i])
        let c2 = unicode.category(scalars[i + 1usize])
        let lower_or_number = c1 == unicode.Category.Ll || c1 == unicode.Category.Nd || c1 == unicode.Category.Nl || c1 == unicode.Category.No
        if lower_or_number && c2 == unicode.Category.Lu {
            marks[i + 1usize] = true
            i += 2usize
        } else {
            i += 1usize
        }
    }
    // (\p{Lu}+)(\p{Lu}\p{Ll}) -> a space before the last capital of the run
    i = 0usize
    while i < count {
        if unicode.category(scalars[i]) == unicode.Category.Lu {
            var j = i
            while j < count && unicode.category(scalars[j]) == unicode.Category.Lu { j += 1usize }
            if j < count && unicode.category(scalars[j]) == unicode.Category.Ll && j - i >= 2usize {
                marks[j - 1usize] = true
                i = j + 1usize
            } else {
                i = j
            }
        } else {
            i += 1usize
        }
    }
    // split on [^\p{L}\p{N}]+ and marks
    var n = 0usize
    var start = 0usize
    var in_word = false
    var byte_pos = 0usize
    var word_start_byte = 0usize
    i = 0usize
    while i <= count {
        var boundary = false
        var letter_or_digit = false
        if i < count {
            let cat = unicode.category(scalars[i])
            letter_or_digit = cat == unicode.Category.Lu || cat == unicode.Category.Ll || cat == unicode.Category.Lt || cat == unicode.Category.Lm || cat == unicode.Category.Lo || cat == unicode.Category.Nd || cat == unicode.Category.Nl || cat == unicode.Category.No
        }
        if i == count || !letter_or_digit || marks[i] { boundary = true }
        if boundary {
            if in_word {
                if n < out.len {
                    out[n] = s[word_start_byte..byte_pos]
                    n += 1usize
                }
                in_word = false
            }
            if i < count && letter_or_digit {
                in_word = true
                word_start_byte = byte_pos
            }
        } else if !in_word {
            in_word = true
            word_start_byte = byte_pos
        }
        if i < count { byte_pos += scalar_width(scalars[i]) }
        i += 1usize
    }
    ret n
}

// `w.charAt(0).toLocaleUpperCase() + w.slice(1).toLocaleLowerCase()` (the first UTF-16 unit).
fn upper_first(a: *mem.Arena, w: str) -> str {
    let units = units_of(a, w)
    if units.len == 0usize { ret "" }
    let head = upper_text(a, text_of_units(a, units[0usize..1usize]))
    let tail = lower_text(a, text_of_units(a, units[1usize..units.len]))
    ret f.join(a, head, tail)
}

fn join_words(a: *mem.Arena, words: []const str, mode: str) -> str {
    var out = ""
    var i = 0usize
    while i < words.len {
        var piece = ""
        var sep = " "
        if str.eq(mode, "lower") || str.eq(mode, "dot") || str.eq(mode, "kebab") || str.eq(mode, "snake") {
            piece = lower_text(a, words[i])
            if str.eq(mode, "dot") { sep = "." }
            if str.eq(mode, "kebab") { sep = "-" }
            if str.eq(mode, "snake") { sep = "_" }
        } else if str.eq(mode, "upper") || str.eq(mode, "screaming-snake") {
            piece = upper_text(a, words[i])
            if str.eq(mode, "screaming-snake") { sep = "_" }
        } else if str.eq(mode, "camel") {
            sep = ""
            if i == 0usize { piece = lower_text(a, words[i]) } else { piece = upper_first(a, words[i]) }
        } else if str.eq(mode, "pascal") {
            sep = ""
            piece = upper_first(a, words[i])
        } else if str.eq(mode, "word") {
            piece = upper_first(a, words[i])
        } else {
            // sentence
            if i == 0usize { piece = upper_first(a, words[i]) } else { piece = lower_text(a, words[i]) }
        }
        if i > 0usize { out = f.join(a, out, sep) }
        out = f.join(a, out, piece)
        i += 1usize
    }
    ret out
}

fn is_casing_mode(mode: str) -> bool {
    ret str.eq(mode, "none") || str.eq(mode, "lower") || str.eq(mode, "upper") || str.eq(mode, "camel") || str.eq(mode, "dot") || str.eq(mode, "kebab") || str.eq(mode, "pascal") || str.eq(mode, "screaming-snake") || str.eq(mode, "sentence") || str.eq(mode, "snake") || str.eq(mode, "word")
}

fn h_casing(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let mode = text_arg(c, 1usize)
    if !is_casing_mode(mode) {
        ret f.value_error(f.join3(c.a, f.join(c.a, "Unknown casing mode: ", mode), ". One of: ", "none, lower, upper, camel, dot, kebab, pascal, screaming-snake, sentence, snake, word"))
    }
    if str.eq(mode, "none") { ret f.text(s) }
    let (storage, e) = mem.alloc[str](c.a, s.len + 1usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let n = casing_words(c.a, s, storage)
    if n == 0usize { ret f.text(s) }
    ret f.text(join_words(c.a, storage[0usize..n], mode))
}

fn h_clean(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if s.len == 0usize { ret f.text("") }
    let (out, e) = mem.alloc[u8](c.a, s.len)
    if e != ok { ret f.generic_error("Out of memory") }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let b = s[i]
        let control = (b <= 8u8) || b == 11u8 || b == 12u8 || (b >= 14u8 && b <= 31u8) || b == 127u8
        if !control {
            out[n] = b
            n += 1usize
        }
        i += 1usize
    }
    ret f.text(out[0usize..n])
}

fn hex_value(b: u8) -> i32 {
    if b >= 48u8 && b <= 57u8 { ret i32(b - 48u8) }
    if b >= 97u8 && b <= 102u8 { ret i32(b - 87u8) }
    if b >= 65u8 && b <= 70u8 { ret i32(b - 55u8) }
    ret -1i32
}

// `decodeURIComponent`: `%XX` sequences that must form well-formed UTF-8.
fn h_decode_url_component(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    let (decoded, good) = decode_component(c.a, s)
    if !good { ret f.value_error(f.join(c.a, "Not a valid URL-encoded string: ", s)) }
    ret f.text(decoded)
}

// `decodeURIComponent`: the decoded text, or false for a malformed escape or ill-formed UTF-8.
fn decode_component(a: *mem.Arena, s: str) -> (str, bool) {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret ("", false) }
    var n = 0usize
    var i = 0usize
    var bad = false
    while i < s.len && !bad {
        if s[i] == 37u8 {
            if i + 2usize >= s.len { bad = true }
            if !bad {
                let hi = hex_value(s[i + 1usize])
                let lo = hex_value(s[i + 2usize])
                if hi < 0i32 || lo < 0i32 {
                    bad = true
                } else {
                    out[n] = u8(hi * 16i32 + lo)
                    n += 1usize
                    i += 3usize
                }
            }
        } else {
            out[n] = s[i]
            n += 1usize
            i += 1usize
        }
    }
    if bad || !utf8.validate(out[0usize..n]) { ret ("", false) }
    ret (out[0usize..n], true)
}

fn h_initials(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    var upper = true
    if c.args.len > 1usize { upper = f.to_bool(c.args[1usize]) }
    let (storage, e) = mem.alloc[str](c.a, s.len + 1usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let n = casing_words(c.a, s, storage)
    var units_all: []u16 = zero
    var total = 3usize
    if n < 3usize { total = n }
    let (letters, le) = mem.alloc[u16](c.a, total + 1usize)
    if le != ok { ret f.generic_error("Out of memory") }
    var i = 0usize
    while i < total {
        let units = units_of(c.a, storage[i])
        letters[i] = units[0usize]
        i += 1usize
    }
    let joined = text_of_units(c.a, letters[0usize..total])
    if upper { ret f.text(upper_text(c.a, joined)) }
    ret f.text(joined)
}

// PADLEFT (side 0), PADRIGHT (side 1) and PAD (side 2, centred).
fn pad_with(c: *f.Call, side: u8) -> f.Value {
    let s = text_arg(c, 0usize)
    let width_arg = f.to_number(c.a, c.args[1usize])
    if f.is_error(width_arg) { ret width_arg }
    var fill = " "
    if c.args.len > 2usize { fill = text_arg(c, 2usize) }
    if fill.len == 0usize { ret f.value_error("PAD needs a non-empty fill character") }
    var width = 0.0f64
    if width_arg.kind != .Blank { width = math.trunc[f64](width_arg.n) }
    let units = units_of(c.a, s)
    if width <= f64(units.len) { ret f.text(s) }
    if width > 536870888.0f64 { ret f.generic_error("Invalid string length") }
    let fill_units = units_of(c.a, fill)
    let total = usize(width) - units.len
    let (out, e) = mem.alloc[u16](c.a, usize(width))
    if e != ok { ret f.generic_error("Invalid string length") }
    var left = 0usize
    var right = 0usize
    if side == 0u8 {
        left = total
    } else if side == 1u8 {
        right = total
    } else {
        left = total / 2usize
        right = total - left
    }
    var w = 0usize
    var k = 0usize
    while k < left {
        out[w] = fill_units[k % fill_units.len]
        w += 1usize
        k += 1usize
    }
    k = 0usize
    while k < units.len {
        out[w] = units[k]
        w += 1usize
        k += 1usize
    }
    k = 0usize
    while k < right {
        out[w] = fill_units[k % fill_units.len]
        w += 1usize
        k += 1usize
    }
    ret f.text(text_of_units(c.a, out[0usize..w]))
}

fn h_padleft(c: *f.Call) -> f.Value { ret pad_with(c, 0u8) }

fn h_padright(c: *f.Call) -> f.Value { ret pad_with(c, 1u8) }

fn h_pad(c: *f.Call) -> f.Value { ret pad_with(c, 2u8) }

fn h_part(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    var delimiter = " "
    var index_at = 1usize
    if c.args.len > 2usize {
        delimiter = text_arg(c, 1usize)
        index_at = 2usize
    }
    let index_arg = f.to_number(c.a, c.args[index_at])
    if f.is_error(index_arg) { ret index_arg }
    var n = 0.0f64
    if index_arg.kind != .Blank { n = math.trunc[f64](index_arg.n) }
    if n == 0.0f64 { ret f.value_error("PART is 1-based; there is no part 0") }
    // split(delimiter): an empty delimiter splits into UTF-16 units
    var segments: []str = zero
    var count = 0usize
    if delimiter.len == 0usize {
        let units = units_of(c.a, s)
        let (storage, e) = mem.alloc[str](c.a, units.len + 1usize)
        if e != ok { ret f.generic_error("Out of memory") }
        var i = 0usize
        while i < units.len {
            storage[i] = text_of_units(c.a, units[i..i + 1usize])
            i += 1usize
        }
        segments = storage
        count = units.len
    } else {
        let (storage, e) = mem.alloc[str](c.a, s.len + 2usize)
        if e != ok { ret f.generic_error("Out of memory") }
        var start = 0usize
        var p = 0usize
        while p + delimiter.len <= s.len {
            if str.eq(s[p..p + delimiter.len], delimiter) {
                storage[count] = s[start..p]
                count += 1usize
                p += delimiter.len
                start = p
            } else {
                p += 1usize
            }
        }
        storage[count] = s[start..s.len]
        count += 1usize
        segments = storage
    }
    var picked_index = 0.0f64
    if n < 0.0f64 { picked_index = f64(count) + n } else { picked_index = n - 1.0f64 }
    if picked_index < 0.0f64 || picked_index >= f64(count) { ret f.text("") }
    ret f.text(segments[usize(picked_index)])
}

// --- extractors -----------------------------------------------------------------------------------------------------

// Every non-overlapping match of a global pattern, as JavaScript's `match(/g)` and `matchAll` walk them.
fn match_all(c: *f.Call, re: *const regex.Regex, s: str, out: []regex.Captures) -> usize {
    var n = 0usize
    var pos = 0usize
    var more = true
    while more && pos <= s.len && n < out.len {
        let (caps, found, ce) = regex.captures(c.a, re, s, pos)
        if !found {
            more = false
        } else {
            out[n] = caps
            n += 1usize
            if caps.whole.end == caps.whole.start {
                if caps.whole.end >= s.len {
                    pos = s.len + 1usize
                } else {
                    let (d, de) = utf8.decode(s, caps.whole.end)
                    var w = 1usize
                    if de == ok { w = usize(d.width) }
                    pos = caps.whole.end + w
                }
            } else {
                pos = caps.whole.end
            }
        }
    }
    ret n
}

// kind 0 text, 1 number (parsed), 2 trimmed text
fn extract_with(c: *f.Call, pattern: str, ignore_case: bool, kind: u8) -> f.Value {
    let s = text_arg(c, 0usize)
    if utf16_len(s) > max_regex_input() { ret f.value_error("Input too large for regex") }
    let (re, failure) = compile_pattern(c, pattern, ignore_case)
    if f.is_error(failure) { ret failure }
    let (found, e) = mem.alloc[regex.Captures](c.a, s.len + 2usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let n = match_all(c, &re, s, found)
    if n == 0usize { ret f.array(f.zero_items()) }
    let (items, ie) = mem.alloc[f.Value](c.a, n)
    if ie != ok { ret f.generic_error("Out of memory") }
    var i = 0usize
    while i < n {
        let piece = s[found[i].whole.start..found[i].whole.end]
        if kind == 1u8 {
            let (x, good) = f.parse_number_text(piece)
            items[i] = f.number(x)
        } else if kind == 2u8 {
            items[i] = f.text(str.trim(piece))
        } else {
            items[i] = f.text(piece)
        }
        i += 1usize
    }
    ret f.array(items)
}

fn h_extractemails(c: *f.Call) -> f.Value {
    ret extract_with(c, "[^\\s@<>()\\[\\]{},;:\"']+@[^\\s@<>()\\[\\]{},;:\"']+\\.[a-z]{2,}", true, 0u8)
}

fn h_extractnumbers(c: *f.Call) -> f.Value { ret extract_with(c, "-?\\d+(?:\\.\\d+)?", false, 1u8) }

fn h_extractprices(c: *f.Call) -> f.Value {
    ret extract_with(c, "[$\xE2\x82\xAC\xC2\xA3\xC2\xA5]\\s?-?\\d+(?:[.,]\\d+)?|-?\\d+(?:[.,]\\d+)?\\s?[$\xE2\x82\xAC\xC2\xA3\xC2\xA5]", false, 0u8)
}

fn h_extractphonenumbers(c: *f.Call) -> f.Value { ret extract_with(c, "\\+?\\d[\\d\\s().-]{6,}\\d", false, 2u8) }

fn h_extractdomains(c: *f.Call) -> f.Value {
    ret extract_with(c, "(?:https?://)?(?:[\\w-]+\\.)+[a-z]{2,}(?=[/\\s]|$)", true, 0u8)
}

fn h_extractdates(c: *f.Call) -> f.Value {
    ret extract_with(c, "\\d{4}-\\d{2}-\\d{2}|\\d{1,2}/\\d{1,2}/\\d{2,4}|\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}", false, 0u8)
}

fn h_extracthashtags(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if utf16_len(s) > max_regex_input() { ret f.value_error("Input too large for regex") }
    let (items, e) = mem.alloc[f.Value](c.a, s.len + 1usize)
    if e != ok { ret f.generic_error("Out of memory") }
    var n = 0usize
    var off = 0usize
    while off < s.len {
        if s[off] == 35u8 {
            var q = off + 1usize
            var any = false
            var more = true
            while more && q < s.len {
                let (d, de) = utf8.decode(s, q)
                if de != ok {
                    more = false
                } else {
                    let cat = unicode.category(d.scalar)
                    let ok_char = cat == unicode.Category.Lu || cat == unicode.Category.Ll || cat == unicode.Category.Lt || cat == unicode.Category.Lm || cat == unicode.Category.Lo || cat == unicode.Category.Nd || cat == unicode.Category.Nl || cat == unicode.Category.No || d.scalar == 95u32
                    if ok_char {
                        any = true
                        q += usize(d.width)
                    } else {
                        more = false
                    }
                }
            }
            if any {
                items[n] = f.text(s[off..q])
                n += 1usize
                off = q
            } else {
                off += 1usize
            }
        } else {
            off += 1usize
        }
    }
    if n == 0usize { ret f.array(f.zero_items()) }
    ret f.array(items[0usize..n])
}

fn h_extract(c: *f.Call) -> f.Value {
    let s = text_arg(c, 0usize)
    if utf16_len(s) > max_regex_input() { ret f.value_error("Input too large for regex") }
    let (re, failure) = compile_pattern(c, text_arg(c, 1usize), false)
    if f.is_error(failure) { ret failure }
    let (found, e) = mem.alloc[regex.Captures](c.a, s.len + 2usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let n = match_all(c, &re, s, found)
    if n == 0usize { ret f.array(f.zero_items()) }
    let (items, ie) = mem.alloc[f.Value](c.a, n)
    if ie != ok { ret f.generic_error("Out of memory") }
    var i = 0usize
    while i < n {
        var m = found[i].whole
        if found[i].groups.len > 0usize {
            let g = found[i].groups[0usize]
            if g.start != regex.NONE && g.end != regex.NONE { m = g }
        }
        items[i] = f.text(s[m.start..m.end])
        i += 1usize
    }
    ret f.array(items)
}

// --- registration ---------------------------------------------------------------------------------------------------

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: "text", lazy: false, pass_errors: false, volatile_fn: false, generate_once: false, min_args: low, max_args: high, handler: handler })
}

fn al1(a: *mem.Arena, x: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 1usize)
    s[0usize] = x
    ret s
}

fn al2(a: *mem.Arena, x: str, y: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 2usize)
    s[0usize] = x
    s[1usize] = y
    ret s
}

// Register the text functions.
fn register(r: *f.Registry, a: *mem.Arena) -> err {
    var none: []const str = zero
    try add(r, a, "CHAR", none, 1i32, 1i32, h_char)
    try add(r, a, "UNICHAR", none, 1i32, 1i32, h_unichar)
    try add(r, a, "CODE", none, 1i32, 1i32, h_code)
    try add(r, a, "UNICODE", none, 1i32, 1i32, h_unicode)
    try add(r, a, "CONCATENATE", al1(a, "CONCAT"), 1i32, -1i32, h_concatenate)
    try add(r, a, "CONTAINS", none, 2i32, 2i32, h_contains)
    try add(r, a, "EXACT", none, 2i32, 2i32, h_exact)
    try add(r, a, "SAME", none, 2i32, 3i32, h_same)
    try add(r, a, "FIND", none, 2i32, 3i32, h_find)
    try add(r, a, "SEARCH", none, 2i32, 3i32, h_search)
    try add(r, a, "ISEMAIL", none, 1i32, 1i32, h_isemail)
    try add(r, a, "ISURL", none, 1i32, 1i32, h_isurl)
    try add(r, a, "LEFT", none, 1i32, 2i32, h_left)
    try add(r, a, "RIGHT", none, 1i32, 2i32, h_right)
    try add(r, a, "MID", none, 3i32, 3i32, h_mid)
    try add(r, a, "LEN", al1(a, "LENGTH"), 1i32, 1i32, h_len)
    try add(r, a, "LOWER", al1(a, "LOWERCASE"), 1i32, 1i32, h_lower)
    try add(r, a, "UPPER", al1(a, "UPPERCASE"), 1i32, 1i32, h_upper)
    try add(r, a, "PROPER", al1(a, "PROPERCASE"), 1i32, 1i32, h_proper)
    try add(r, a, "REVERSE", none, 1i32, 1i32, h_reverse)
    try add(r, a, "REPEAT", al1(a, "REPT"), 2i32, 2i32, h_repeat)
    try add(r, a, "REPLACE", none, 4i32, 4i32, h_replace)
    try add(r, a, "SUBSTITUTE", none, 3i32, 4i32, h_substitute)
    try add(r, a, "TEXTJOIN", none, 3i32, -1i32, h_textjoin)
    try add(r, a, "TRIM", none, 1i32, 1i32, h_trim)
    try add(r, a, "WORDCOUNT", none, 1i32, 1i32, h_wordcount)
    try add(r, a, "OCCURANCE", al1(a, "OCCURRENCE"), 2i32, 2i32, h_occurance)
    try add(r, a, "SOUNDEX", none, 1i32, 1i32, h_soundex)
    try add(r, a, "REGEXMATCH", none, 2i32, 2i32, h_regexmatch)
    try add(r, a, "REGEXEXTRACT", none, 2i32, 3i32, h_regexextract)
    try add(r, a, "REGEXREPLACE", none, 3i32, 3i32, h_regexreplace)
    try add(r, a, "STARTS_WITH", none, 2i32, 3i32, h_starts_with)
    try add(r, a, "ENDS_WITH", none, 2i32, 3i32, h_ends_with)
    try add(r, a, "CASING", none, 2i32, 2i32, h_casing)
    try add(r, a, "CLEAN", none, 1i32, 1i32, h_clean)
    try add(r, a, "DECODE_URL_COMPONENT", al2(a, "DECODEURL", "URLDECODE"), 1i32, 1i32, h_decode_url_component)
    try add(r, a, "INITIALS", none, 1i32, 2i32, h_initials)
    try add(r, a, "PADLEFT", al1(a, "PADSTART"), 2i32, 3i32, h_padleft)
    try add(r, a, "PADRIGHT", al1(a, "PADEND"), 2i32, 3i32, h_padright)
    try add(r, a, "PAD", none, 2i32, 3i32, h_pad)
    try add(r, a, "PART", none, 2i32, 3i32, h_part)
    try add(r, a, "EXTRACTEMAILS", none, 1i32, 1i32, h_extractemails)
    try add(r, a, "EXTRACTNUMBERS", none, 1i32, 1i32, h_extractnumbers)
    try add(r, a, "EXTRACTPRICES", none, 1i32, 1i32, h_extractprices)
    try add(r, a, "EXTRACTHASHTAGS", none, 1i32, 1i32, h_extracthashtags)
    try add(r, a, "EXTRACTPHONENUMBERS", none, 1i32, 1i32, h_extractphonenumbers)
    try add(r, a, "EXTRACTDOMAINS", none, 1i32, 1i32, h_extractdomains)
    try add(r, a, "EXTRACTDATES", none, 1i32, 1i32, h_extractdates)
    try add(r, a, "EXTRACT", none, 2i32, 2i32, h_extract)
    ret ok
}
