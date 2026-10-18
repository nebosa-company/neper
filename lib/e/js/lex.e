// The JavaScript tokenizer (browser tracker 5.2): ECMAScript 2024 lexical grammar over UTF-8 source.
//
// `next` returns one token. Whether a `/` starts a regular expression depends on the grammar around it, so the lexer always
// reads `/` and `/=` as punctuators and the parser calls `regex_at` when it expects an expression there. A template literal
// is read whole: its cooked and raw strings and the source of each `${...}` substitution come back in `Lexer.template`, and
// the parser parses each substitution's source on its own.
//
// Identifiers are ASCII letters, `$`, `_`, any byte of a non-ASCII character and `\u` escapes; names keep their spelling
// with escapes decoded. Numbers are decimal, hex, octal (`0o`, legacy `0`), binary, with exponents and `_` separators; a
// trailing `n` marks a BigInt literal. A line terminator (LF, CR, U+2028, U+2029) before a token sets `nl`.

use e.data.list as list
use e.mem
use e.str
use e.text.unicode as unicode

const T_EOF: u8 = 0u8
const T_IDENT: u8 = 1u8
const T_PUNCT: u8 = 2u8
const T_NUM: u8 = 3u8
const T_STR: u8 = 4u8
const T_TEMPLATE: u8 = 5u8
const T_REGEX: u8 = 6u8
const T_PRIVATE: u8 = 7u8

error SyntaxError

// `text` is the identifier, the punctuator, the cooked string, the regexp body or the private name; `flags` the regexp's flags;
// `escaped` says an identifier or string used an escape (a keyword may not).
type Tok = struct {
    kind: u8, start: usize, end: usize, line: u32, nl: bool, text: str, flags: str, num: f64, big: bool, escaped: bool, legacy_octal: bool
}

// One template literal: `cooked[i]` is invalid (and `valid[i]` false) when the string has a bad escape, which only a tagged
// template may carry; `exprs` are the substitution sources, one fewer than the strings.
type Template = struct { cooked: []const str, raw: []const str, valid: []const bool, exprs: []const str }

type Lexer = struct { a: *mem.Arena, src: str, pos: usize, line: u32, template: Template, message: str, module: bool }

fn new_lexer(a: *mem.Arena, src: str) -> Lexer {
    var lx: Lexer = zero
    lx.a = a
    lx.src = src
    lx.pos = 0usize
    lx.line = 1u32
    lx.message = ""
    if src.len >= 3usize && src[0usize] == 239u8 && src[1usize] == 187u8 && src[2usize] == 191u8 { lx.pos = 3usize }
    ret lx
}

fn is_id_start(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 36u8 || c == 95u8 || c >= 128u8 }
fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_id_part(c: u8) -> bool { ret is_id_start(c) || is_digit(c) }

// The byte length of the non-ASCII whitespace or line terminator at `at` (NBSP, BOM, U+1680, U+2000..200A, U+2028/9, U+202F,
// U+205F, U+3000), or 0: such a character ends an identifier although its bytes look like identifier bytes.
fn uspace_len(s: str, at: usize) -> usize {
    if at >= s.len { ret 0usize }
    let c = s[at]
    if c == 194u8 && at + 1usize < s.len && s[at + 1usize] == 160u8 { ret 2usize }
    if c == 239u8 && at + 2usize < s.len && s[at + 1usize] == 187u8 && s[at + 2usize] == 191u8 { ret 3usize }
    if c == 225u8 && at + 2usize < s.len && s[at + 1usize] == 154u8 && s[at + 2usize] == 128u8 { ret 3usize }
    if c == 226u8 && at + 2usize < s.len && s[at + 1usize] == 128u8 && ((s[at + 2usize] >= 128u8 && s[at + 2usize] <= 138u8) || s[at + 2usize] == 168u8 || s[at + 2usize] == 169u8 || s[at + 2usize] == 175u8) { ret 3usize }
    if c == 226u8 && at + 2usize < s.len && s[at + 1usize] == 129u8 && s[at + 2usize] == 159u8 { ret 3usize }
    if c == 227u8 && at + 2usize < s.len && s[at + 1usize] == 128u8 && s[at + 2usize] == 128u8 { ret 3usize }
    ret 0usize
}

// The scalar value starting at `at` of UTF-8 text.
fn scalar_in(s: str, at: usize) -> u32 {
    let c = s[at]
    if c < 128u8 { ret u32(c) }
    if c >= 240u8 && at + 3usize < s.len { ret ((u32(c) & 7u32) << 18u32) | ((u32(s[at + 1usize]) & 63u32) << 12u32) | ((u32(s[at + 2usize]) & 63u32) << 6u32) | (u32(s[at + 3usize]) & 63u32) }
    if c >= 224u8 && at + 2usize < s.len { ret ((u32(c) & 15u32) << 12u32) | ((u32(s[at + 1usize]) & 63u32) << 6u32) | (u32(s[at + 2usize]) & 63u32) }
    if c >= 192u8 && at + 1usize < s.len { ret ((u32(c) & 31u32) << 6u32) | (u32(s[at + 1usize]) & 63u32) }
    ret u32(c)
}

fn newer_than_tables(cp: u32, cat: unicode.Category) -> bool {
    if cat != .Cn { ret false }
    ret (cp & 65534u32) != 65534u32 && !(cp >= 64976u32 && cp <= 65007u32)
}

// ID_Start for non-ASCII scalars: the letter categories and Nl, plus Other_ID_Start.
fn id_start_cp(cp: u32) -> bool {
    if cp < 128u32 { ret is_id_start(u8(cp)) }
    if cp == 11823u32 { ret false }
    if cp == 8472u32 || cp == 8494u32 || cp == 12443u32 || cp == 12444u32 || cp == 6277u32 || cp == 6278u32 { ret true }
    let cat = unicode.category(cp)
    // Code points newer than the bundled tables are accepted rather than rejected.
    ret cat == .Lu || cat == .Ll || cat == .Lt || cat == .Lm || cat == .Lo || cat == .Nl || newer_than_tables(cp, cat)
}

// ID_Continue (plus ZWNJ / ZWJ, which identifiers allow).
fn id_part_cp(cp: u32) -> bool {
    if cp < 128u32 { ret is_id_part(u8(cp)) }
    if cp == 11823u32 { ret false }
    if id_start_cp(cp) { ret true }
    if cp == 8204u32 || cp == 8205u32 || cp == 183u32 || cp == 903u32 || (cp >= 4969u32 && cp <= 4977u32) || cp == 6618u32 || cp == 12539u32 || cp == 65381u32 { ret true }
    let cat = unicode.category(cp)
    ret cat == .Mn || cat == .Mc || cat == .Nd || cat == .Pc || newer_than_tables(cp, cat)
}

fn id_part_at(s: str, at: usize) -> bool {
    let c = s[at]
    if c >= 128u8 {
        // Continuation bytes belong to the scalar whose lead byte was checked.
        if c < 192u8 { ret true }
        ret id_part_cp(scalar_in(s, at))
    }
    ret is_id_part(c)
}
fn hex_value(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

fn fail(lx: *Lexer, message: str) -> err {
    lx.message = message
    ret SyntaxError
}

fn put_cp(b: *str.Builder, c: u32) {
    var e: err = ok
    if c < 128u32 {
        e = str.push_byte(b, u8(c))
    } else if c < 2048u32 {
        e = str.push_byte(b, u8(192u32 | (c >> 6u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    } else if c < 65536u32 {
        e = str.push_byte(b, u8(224u32 | (c >> 12u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    } else {
        e = str.push_byte(b, u8(240u32 | (c >> 18u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 12u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    }
}

// The line terminator starting at `at` (its byte length), or 0.
fn line_terminator(src: str, at: usize) -> usize {
    if at >= src.len { ret 0usize }
    let c = src[at]
    if c == 10u8 || c == 13u8 { ret 1usize }
    if c == 226u8 && at + 2usize < src.len && src[at + 1usize] == 128u8 && (src[at + 2usize] == 168u8 || src[at + 2usize] == 169u8) { ret 3usize }
    ret 0usize
}

// Skips whitespace and comments; whether a line terminator was crossed.
fn skip_space(lx: *Lexer) -> (bool, err) {
    var nl = false
    let at_start = lx.pos == 0usize
    while lx.pos < lx.src.len {
        let c = lx.src[lx.pos]
        let lt = line_terminator(lx.src, lx.pos)
        if lt > 0usize {
            if c == 13u8 && lx.pos + 1usize < lx.src.len && lx.src[lx.pos + 1usize] == 10u8 { lx.pos += 1usize }
            lx.pos += lt
            lx.line += 1u32
            nl = true
        } else if c == 32u8 || c == 9u8 || c == 11u8 || c == 12u8 {
            lx.pos += 1usize
        } else if c == 194u8 && lx.pos + 1usize < lx.src.len && lx.src[lx.pos + 1usize] == 160u8 {
            lx.pos += 2usize
        } else if c == 239u8 && lx.pos + 2usize < lx.src.len && lx.src[lx.pos + 1usize] == 187u8 && lx.src[lx.pos + 2usize] == 191u8 {
            lx.pos += 3usize
        } else if c == 225u8 && lx.pos + 2usize < lx.src.len && lx.src[lx.pos + 1usize] == 154u8 && lx.src[lx.pos + 2usize] == 128u8 {
            lx.pos += 3usize
        } else if c == 226u8 && lx.pos + 2usize < lx.src.len && lx.src[lx.pos + 1usize] == 128u8 && ((lx.src[lx.pos + 2usize] >= 128u8 && lx.src[lx.pos + 2usize] <= 138u8) || lx.src[lx.pos + 2usize] == 175u8) {
            lx.pos += 3usize
        } else if c == 226u8 && lx.pos + 2usize < lx.src.len && lx.src[lx.pos + 1usize] == 129u8 && lx.src[lx.pos + 2usize] == 159u8 {
            lx.pos += 3usize
        } else if c == 227u8 && lx.pos + 2usize < lx.src.len && lx.src[lx.pos + 1usize] == 128u8 && lx.src[lx.pos + 2usize] == 128u8 {
            lx.pos += 3usize
        } else if c == 47u8 && lx.pos + 1usize < lx.src.len && lx.src[lx.pos + 1usize] == 47u8 {
            while lx.pos < lx.src.len && line_terminator(lx.src, lx.pos) == 0usize { lx.pos += 1usize }
        } else if c == 47u8 && lx.pos + 1usize < lx.src.len && lx.src[lx.pos + 1usize] == 42u8 {
            lx.pos += 2usize
            var closed = false
            while lx.pos < lx.src.len && !closed {
                if lx.src[lx.pos] == 42u8 && lx.pos + 1usize < lx.src.len && lx.src[lx.pos + 1usize] == 47u8 {
                    lx.pos += 2usize
                    closed = true
                } else {
                    let l2 = line_terminator(lx.src, lx.pos)
                    if l2 > 0usize {
                        nl = true
                        lx.line += 1u32
                        lx.pos += l2
                    } else {
                        lx.pos += 1usize
                    }
                }
            }
            if !closed { ret (nl, fail(lx, "unterminated comment")) }
        } else if c == 35u8 && lx.pos == 0usize && lx.src.len > 1usize && lx.src[1usize] == 33u8 {
            while lx.pos < lx.src.len && line_terminator(lx.src, lx.pos) == 0usize { lx.pos += 1usize }
        } else if !lx.module && (nl || at_start) && c == 45u8 && lx.pos + 2usize < lx.src.len && lx.src[lx.pos + 1usize] == 45u8 && lx.src[lx.pos + 2usize] == 62u8 {
            // `-->` at the start of a line is a single-line comment (Annex B).
            while lx.pos < lx.src.len && line_terminator(lx.src, lx.pos) == 0usize { lx.pos += 1usize }
        } else if !lx.module && c == 60u8 && lx.pos + 3usize < lx.src.len && lx.src[lx.pos + 1usize] == 33u8 && lx.src[lx.pos + 2usize] == 45u8 && lx.src[lx.pos + 3usize] == 45u8 {
            while lx.pos < lx.src.len && line_terminator(lx.src, lx.pos) == 0usize { lx.pos += 1usize }
        } else {
            ret (nl, ok)
        }
    }
    ret (nl, ok)
}

// `\uXXXX` or `\u{X...}` at `pos` (just past the `\u`): the code point and the new position, or -1.
fn read_unicode_escape(src: str, pos: usize) -> (i64, usize) {
    if pos < src.len && src[pos] == 123u8 {
        var at = pos + 1usize
        var v = 0i64
        var any = false
        while at < src.len && src[at] != 125u8 {
            let h = hex_value(src[at])
            if h < 0i32 { ret (-1i64, pos) }
            v = v * 16i64 + i64(h)
            if v > 1114111i64 { ret (-1i64, pos) }
            any = true
            at += 1usize
        }
        if at >= src.len || !any { ret (-1i64, pos) }
        ret (v, at + 1usize)
    }
    if pos + 4usize > src.len { ret (-1i64, pos) }
    var v2 = 0i64
    var k = 0usize
    while k < 4usize {
        let h2 = hex_value(src[pos + k])
        if h2 < 0i32 { ret (-1i64, pos) }
        v2 = v2 * 16i64 + i64(h2)
        k += 1usize
    }
    ret (v2, pos + 4usize)
}

// Lone surrogates have no UTF-8 spelling: a high one followed by `\uDC00..DFFF` joins into one code point, any other is
// written as U+FFFD (a documented ceiling of the UTF-8 string representation).
fn put_unit(b: *str.Builder, src: str, c: i64, after: usize) -> usize {
    var cp = c
    var end = after
    if c >= 55296i64 && c <= 56319i64 {
        if after + 1usize < src.len && src[after] == 92u8 && src[after + 1usize] == 117u8 {
            let (lo, lo_end) = read_unicode_escape(src, after + 2usize)
            if lo >= 56320i64 && lo <= 57343i64 {
                cp = 65536i64 + (c - 55296i64) * 1024i64 + (lo - 56320i64)
                end = lo_end
            }
        }
    }
    put_cp(b, u32(cp))
    ret end
}

fn read_ident(lx: *Lexer) -> (str, bool, err) {
    let start = lx.pos
    var at = start
    if start < lx.src.len && lx.src[start] >= 192u8 && !id_start_cp(scalar_in(lx.src, start)) { ret ("", false, fail(lx, "invalid character in identifier")) }
    while at < lx.src.len && id_part_at(lx.src, at) { at += 1usize }
    if at >= lx.src.len || lx.src[at] != 92u8 {
        lx.pos = at
        ret (lx.src[start..at], false, ok)
    }
    let (b, be) = str.builder(lx.a, 32usize)
    if be != ok { ret ("", false, be) }
    var out = b
    var pos = start
    while pos < lx.src.len {
        let c = lx.src[pos]
        if id_part_at(lx.src, pos) {
            let pe = str.push_byte(&out, c)
            pos += 1usize
        } else if c == 92u8 && pos + 1usize < lx.src.len && lx.src[pos + 1usize] == 117u8 {
            let (cp, after) = read_unicode_escape(lx.src, pos + 2usize)
            if cp < 0i64 { ret ("", true, fail(lx, "bad unicode escape in identifier")) }
            // The escaped character must be allowed at that position of an identifier.
            var cp_ok = false
            if pos == start { cp_ok = id_start_cp(u32(cp)) } else { cp_ok = id_part_cp(u32(cp)) }
            if cp == 8204i64 || cp == 8205i64 { cp_ok = pos != start }
            if !cp_ok { ret ("", true, fail(lx, "invalid escaped character in identifier")) }
            put_cp(&out, u32(cp))
            pos = after
        } else {
            break
        }
    }
    lx.pos = pos
    ret (str.done(&out), true, ok)
}

fn digits_value(lx: *Lexer, radix: u32, pos: usize) -> (f64, bool, usize, err) {
    var v = 0.0f64
    var at = pos
    var any = false
    var last_sep = false
    while at < lx.src.len {
        let c = lx.src[at]
        if c == 95u8 {
            if !any || last_sep { ret (0.0f64, false, pos, fail(lx, "bad numeric separator")) }
            last_sep = true
            at += 1usize
        } else {
            let h = hex_value(c)
            if h < 0i32 || u32(h) >= radix { break }
            v = v * f64(radix) + f64(h)
            any = true
            last_sep = false
            at += 1usize
        }
    }
    if last_sep { ret (0.0f64, false, pos, fail(lx, "bad numeric separator")) }
    ret (v, any, at, ok)
}

fn read_number(lx: *Lexer, t: *Tok) -> err {
    let src = lx.src
    let start = lx.pos
    var at = start
    if src[at] == 48u8 && at + 1usize < src.len && (src[at + 1usize] == 120u8 || src[at + 1usize] == 88u8 || src[at + 1usize] == 111u8 || src[at + 1usize] == 79u8 || src[at + 1usize] == 98u8 || src[at + 1usize] == 66u8) {
        var radix = 16u32
        if src[at + 1usize] == 111u8 || src[at + 1usize] == 79u8 { radix = 8u32 }
        if src[at + 1usize] == 98u8 || src[at + 1usize] == 66u8 { radix = 2u32 }
        let (v, any, digits_end, ve) = digits_value(lx, radix, at + 2usize)
        if ve != ok { ret ve }
        if !any { ret fail(lx, "missing digits") }
        at = digits_end
        t.num = v
        if at < src.len && src[at] == 110u8 {
            t.big = true
            at += 1usize
        }
        if at < src.len && id_part_at(src, at) { ret fail(lx, "identifier directly after number") }
        lx.pos = at
        t.end = at
        ret ok
    }
    // Legacy octal: 0 followed by octal digits (decimal when an 8 or 9 appears).
    if src[at] == 48u8 && at + 1usize < src.len && is_digit(src[at + 1usize]) {
        var k = at + 1usize
        var octal = true
        while k < src.len && is_digit(src[k]) {
            if src[k] >= 56u8 { octal = false }
            k += 1usize
        }
        t.legacy_octal = true
        if octal {
            var v2 = 0.0f64
            var j = at + 1usize
            while j < k {
                v2 = v2 * 8.0f64 + f64(src[j] - 48u8)
                j += 1usize
            }
            t.num = v2
            lx.pos = k
            t.end = k
            if k < src.len && (src[k] == 95u8 || src[k] == 110u8) { ret fail(lx, "legacy octal literals cannot have separators or be BigInts") }
            if k < src.len && id_part_at(src, k) { ret fail(lx, "identifier directly after number") }
            ret ok
        }
    }
    // Decimal: digits, fraction, exponent, with `_` separators removed before parsing.
    let (b, be) = str.builder(lx.a, 32usize)
    if be != ok { ret be }
    var out = b
    var seen_dot = false
    var seen_exp = false
    var last_digit = false
    var is_big = false
    var lead_zero = src[at] == 48u8
    while at < src.len {
        let c = src[at]
        if is_digit(c) {
            let pe = str.push_byte(&out, c)
            last_digit = true
            at += 1usize
        } else if c == 95u8 {
            if !last_digit || at + 1usize >= src.len || !is_digit(src[at + 1usize]) { ret fail(lx, "bad numeric separator") }
            if lead_zero && !seen_dot && !seen_exp { ret fail(lx, "numeric separators are not allowed after a leading zero") }
            last_digit = false
            at += 1usize
        } else if c == 46u8 && !seen_dot && !seen_exp {
            seen_dot = true
            last_digit = false
            let pe2 = str.push_byte(&out, c)
            at += 1usize
        } else if (c == 101u8 || c == 69u8) && !seen_exp && (last_digit || (seen_dot && out.len > 1usize)) {
            seen_exp = true
            last_digit = false
            let pe3 = str.push_byte(&out, 101u8)
            at += 1usize
            if at < src.len && (src[at] == 43u8 || src[at] == 45u8) {
                let pe4 = str.push_byte(&out, src[at])
                at += 1usize
            }
            if at >= src.len || !is_digit(src[at]) { ret fail(lx, "missing exponent") }
        } else if c == 110u8 && !seen_dot && !seen_exp {
            if lead_zero && out.len > 1usize { ret fail(lx, "BigInt literals cannot have a leading zero") }
            is_big = true
            at += 1usize
            break
        } else {
            break
        }
    }
    var text = str.done(&out)
    if text.len > 0usize && text[text.len - 1usize] == 46u8 {
        // `1.` is the number 1.
        var shorter = text[0usize..text.len - 1usize]
        text = shorter
    }
    if text.len == 0usize || (text.len == 1usize && text[0usize] == 46u8) { ret fail(lx, "bad number") }
    // `.5` and `1.e3` are not spellings `parse_f64` reads.
    if text.len > 0usize && text[0usize] == 46u8 {
        let (fixed, fe) = str.concat(lx.a, "0", text)
        if fe == ok { text = fixed }
    }
    let (dot_e, has_dot_e) = str.find(text, ".e")
    if has_dot_e {
        let (left, le) = str.concat(lx.a, text[0usize..usize(dot_e)], text[usize(dot_e) + 1usize..])
        if le == ok { text = left }
    }
    var (v3, pe5) = str.parse_f64(text)
    if pe5 != ok {
        // Out of range: a huge exponent overflows to Infinity, a tiny one underflows to 0.
        let (epos, has_e) = str.find(text, "e")
        if !has_e { ret fail(lx, "bad number") }
        if epos + 1usize < text.len && text[epos + 1usize] == 45u8 { v3 = 0.0f64 } else { v3 = 1.0f64 / (0.0f64 * 1.0f64) }
    }
    t.num = v3
    t.big = is_big
    if at < src.len && id_part_at(src, at) { ret fail(lx, "identifier directly after number") }
    lx.pos = at
    t.end = at
    ret ok
}

// The escape after a `\` at `pos` in a string or template: appended to `b`; `next` the position after it. `template` marks a
// template (no octal escapes, `\0` only before a non-digit); false from `ok` result means a bad escape (the caller decides).
type Esc = struct { good: bool, next: usize, octal: bool }

fn read_escape(lx: *Lexer, b: *str.Builder, pos: usize, template: bool) -> Esc {
    let src = lx.src
    var r = Esc { good: true, next: pos + 1usize, octal: false }
    if pos >= src.len {
        r.good = false
        ret r
    }
    let c = src[pos]
    var e: err = ok
    if c == 110u8 { e = str.push_byte(b, 10u8) } else if c == 116u8 { e = str.push_byte(b, 9u8) } else if c == 114u8 { e = str.push_byte(b, 13u8) } else if c == 98u8 { e = str.push_byte(b, 8u8) } else if c == 102u8 { e = str.push_byte(b, 12u8) } else if c == 118u8 { e = str.push_byte(b, 11u8) } else if c == 120u8 {
        if pos + 2usize >= src.len { r.good = false
        ret r }
        let h1 = hex_value(src[pos + 1usize])
        let h2 = hex_value(src[pos + 2usize])
        if h1 < 0i32 || h2 < 0i32 { r.good = false
        ret r }
        put_cp(b, u32(h1 * 16i32 + h2))
        r.next = pos + 3usize
    } else if c == 117u8 {
        let (cp, after) = read_unicode_escape(src, pos + 1usize)
        if cp < 0i64 { r.good = false
        ret r }
        r.next = put_unit(b, src, cp, after)
    } else if c >= 48u8 && c <= 55u8 {
        if template {
            if c == 48u8 && !(pos + 1usize < src.len && is_digit(src[pos + 1usize])) {
                e = str.push_byte(b, 0u8)
            } else {
                r.good = false
        ret r
            }
        } else {
            if c != 48u8 || (pos + 1usize < src.len && is_digit(src[pos + 1usize])) { r.octal = true }
            var v = i32(c) - 48i32
            var n = 1usize
            while n < 3usize && pos + n < src.len && src[pos + n] >= 48u8 && src[pos + n] <= 55u8 && v * 8i32 + (i32(src[pos + n]) - 48i32) <= 255i32 {
                v = v * 8i32 + (i32(src[pos + n]) - 48i32)
                n += 1usize
            }
            put_cp(b, u32(v))
            r.next = pos + n
        }
    } else if c == 56u8 || c == 57u8 {
        if template { r.good = false
        ret r }
        r.octal = true
        e = str.push_byte(b, c)
    } else if line_terminator(src, pos) > 0usize {
        // Line continuation.
        var l = line_terminator(src, pos)
        if c == 13u8 && pos + 1usize < src.len && src[pos + 1usize] == 10u8 { l = 2usize }
        r.next = pos + l
        lx.line += 1u32
    } else {
        // Any other character stands for itself (a multi-byte one is copied whole).
        var n2 = 1usize
        if c >= 192u8 {
            n2 = 2usize
            if c >= 224u8 { n2 = 3usize }
            if c >= 240u8 { n2 = 4usize }
        }
        var k = 0usize
        while k < n2 && pos + k < src.len {
            e = str.push_byte(b, src[pos + k])
            k += 1usize
        }
        r.next = pos + n2
    }
    ret r
}

fn read_string(lx: *Lexer, t: *Tok, quote: u8) -> err {
    let src = lx.src
    let (b, be) = str.builder(lx.a, 32usize)
    if be != ok { ret be }
    var out = b
    var pos = lx.pos + 1usize
    var closed = false
    while pos < src.len && !closed {
        let c = src[pos]
        if c == quote {
            pos += 1usize
            closed = true
        } else if c == 92u8 {
            t.escaped = true
            let esc = read_escape(lx, &out, pos + 1usize, false)
            if !esc.good { ret fail(lx, "bad escape sequence") }
            pos = esc.next
            if esc.octal { t.legacy_octal = true }
        } else if c == 10u8 || c == 13u8 {
            ret fail(lx, "unterminated string")
        } else {
            let pe = str.push_byte(&out, c)
            pos += 1usize
        }
    }
    if !closed { ret fail(lx, "unterminated string") }
    t.text = str.done(&out)
    lx.pos = pos
    t.end = pos
    ret ok
}

// A template literal starting at the backtick at `lx.pos`.
fn read_template(lx: *Lexer, t: *Tok) -> err {
    let src = lx.src
    let (cooked_made, ce1) = list.init[str](lx.a, 4usize)
    let (raw_made, ce2) = list.init[str](lx.a, 4usize)
    let (valid_made, ce3) = list.init[bool](lx.a, 4usize)
    let (expr_made, ce4) = list.init[str](lx.a, 4usize)
    if ce1 != ok || ce2 != ok || ce3 != ok || ce4 != ok { ret ce1 }
    var cooked = cooked_made
    var raw = raw_made
    var valid = valid_made
    var exprs = expr_made
    var pos = lx.pos + 1usize
    var finished = false
    while !finished {
        // One string part, up to `${` or the closing backtick.
        let raw_start = pos
        var good = true
        var piece: str = ""
        let (b, be) = str.builder(lx.a, 32usize)
        if be != ok { ret be }
        var out = b
        var ended = false
        while pos < src.len && !ended {
            let c = src[pos]
            if c == 96u8 || (c == 36u8 && pos + 1usize < src.len && src[pos + 1usize] == 123u8) {
                ended = true
            } else if c == 92u8 {
                let esc2 = read_escape(lx, &out, pos + 1usize, true)
                if !esc2.good {
                    good = false
                    // Skip the backslash and the next character; the string is invalid but still delimited.
                    pos += 2usize
                } else {
                    pos = esc2.next
                }
            } else if c == 13u8 {
                // CR and CRLF read as LF in both cooked and raw strings.
                let pe = str.push_byte(&out, 10u8)
                lx.line += 1u32
                if pos + 1usize < src.len && src[pos + 1usize] == 10u8 { pos += 1usize }
                pos += 1usize
            } else {
                if c == 10u8 { lx.line += 1u32 }
                let pe2 = str.push_byte(&out, c)
                pos += 1usize
            }
        }
        if !ended { ret fail(lx, "unterminated template") }
        piece = str.done(&out)
        let raw_text = src[raw_start..pos]
        // Raw text: CRLF and CR become LF.
        var raw_clean = raw_text
        var has_cr = false
        var q = 0usize
        while q < raw_text.len {
            if raw_text[q] == 13u8 { has_cr = true }
            q += 1usize
        }
        if has_cr {
            let (rb, rbe) = str.builder(lx.a, raw_text.len)
            if rbe != ok { ret rbe }
            var rout = rb
            var r = 0usize
            while r < raw_text.len {
                if raw_text[r] == 13u8 {
                    let pe3 = str.push_byte(&rout, 10u8)
                    if r + 1usize < raw_text.len && raw_text[r + 1usize] == 10u8 { r += 1usize }
                } else {
                    let pe4 = str.push_byte(&rout, raw_text[r])
                }
                r += 1usize
            }
            raw_clean = str.done(&rout)
        }
        try list.push[str](&cooked, piece)
        try list.push[str](&raw, raw_clean)
        try list.push[bool](&valid, good)
        if src[pos] == 96u8 {
            pos += 1usize
            finished = true
        } else {
            // `${`: find the matching `}` skipping nested strings, templates, comments and braces.
            pos += 2usize
            let expr_start = pos
            var depth = 0usize
            var found = false
            while pos < src.len && !found {
                let c2 = src[pos]
                if c2 == 123u8 {
                    depth += 1usize
                    pos += 1usize
                } else if c2 == 125u8 {
                    if depth == 0usize {
                        found = true
                    } else {
                        depth -= 1usize
                        pos += 1usize
                    }
                } else if c2 == 34u8 || c2 == 39u8 {
                    pos += 1usize
                    while pos < src.len && src[pos] != c2 {
                        if src[pos] == 92u8 { pos += 1usize }
                        pos += 1usize
                    }
                    pos += 1usize
                } else if c2 == 96u8 {
                    var sub = new_lexer(lx.a, src)
                    sub.pos = pos
                    sub.line = lx.line
                    var dummy: Tok = zero
                    try read_template(&sub, &dummy)
                    pos = sub.pos
                } else if c2 == 47u8 && regex_may_start(src, expr_start, pos) {
                    pos += 1usize
                    var in_class = false
                    while pos < src.len && (in_class || src[pos] != 47u8) && line_terminator(src, pos) == 0usize {
                        if src[pos] == 92u8 { pos += 1usize } else if src[pos] == 91u8 { in_class = true } else if src[pos] == 93u8 { in_class = false }
                        pos += 1usize
                    }
                    pos += 1usize
                } else if c2 == 47u8 && pos + 1usize < src.len && src[pos + 1usize] == 47u8 {
                    while pos < src.len && line_terminator(src, pos) == 0usize { pos += 1usize }
                } else if c2 == 47u8 && pos + 1usize < src.len && src[pos + 1usize] == 42u8 {
                    pos += 2usize
                    while pos + 1usize < src.len && !(src[pos] == 42u8 && src[pos + 1usize] == 47u8) { pos += 1usize }
                    pos += 2usize
                } else {
                    if c2 == 10u8 { lx.line += 1u32 }
                    pos += 1usize
                }
            }
            if !found { ret fail(lx, "unterminated template substitution") }
            try list.push[str](&exprs, src[expr_start..pos])
            pos += 1usize
        }
    }
    lx.template = Template { cooked: list.slice_const[str](&cooked), raw: list.slice_const[str](&raw), valid: list.slice_const[bool](&valid), exprs: list.slice_const[str](&exprs) }
    lx.pos = pos
    t.end = pos
    ret ok
}

// Whether a `/` at `at` inside a template substitution (which starts at `from`) opens a regular expression rather than dividing.
fn regex_may_start(src: str, from: usize, at: usize) -> bool {
    if at + 1usize < src.len && (src[at + 1usize] == 47u8 || src[at + 1usize] == 42u8) { ret false }
    var p = at
    while p > from && (src[p - 1usize] == 32u8 || src[p - 1usize] == 9u8) { p -= 1usize }
    if p == from { ret true }
    let c = src[p - 1usize]
    ret c == 40u8 || c == 44u8 || c == 61u8 || c == 58u8 || c == 91u8 || c == 33u8 || c == 38u8 || c == 124u8 || c == 63u8 || c == 123u8 || c == 125u8 || c == 59u8 || c == 43u8 || c == 45u8 || c == 42u8 || c == 37u8 || c == 60u8 || c == 62u8 || c == 126u8 || c == 94u8
}

fn punct_len(src: str, at: usize) -> usize {
    let c = src[at]
    var c1 = 0u8
    var c2 = 0u8
    var c3 = 0u8
    if at + 1usize < src.len { c1 = src[at + 1usize] }
    if at + 2usize < src.len { c2 = src[at + 2usize] }
    if at + 3usize < src.len { c3 = src[at + 3usize] }
    if c == 62u8 && c1 == 62u8 && c2 == 62u8 && c3 == 61u8 { ret 4usize }
    if c == 46u8 && c1 == 46u8 && c2 == 46u8 { ret 3usize }
    if c == 61u8 && c1 == 61u8 && c2 == 61u8 { ret 3usize }
    if c == 33u8 && c1 == 61u8 && c2 == 61u8 { ret 3usize }
    if c == 42u8 && c1 == 42u8 && c2 == 61u8 { ret 3usize }
    if c == 60u8 && c1 == 60u8 && c2 == 61u8 { ret 3usize }
    if c == 62u8 && c1 == 62u8 && c2 == 61u8 { ret 3usize }
    if c == 62u8 && c1 == 62u8 && c2 == 62u8 { ret 3usize }
    if c == 38u8 && c1 == 38u8 && c2 == 61u8 { ret 3usize }
    if c == 124u8 && c1 == 124u8 && c2 == 61u8 { ret 3usize }
    if c == 63u8 && c1 == 63u8 && c2 == 61u8 { ret 3usize }
    if c == 61u8 && c1 == 62u8 { ret 2usize }
    if c == 61u8 && c1 == 61u8 { ret 2usize }
    if c == 33u8 && c1 == 61u8 { ret 2usize }
    if c == 60u8 && c1 == 61u8 { ret 2usize }
    if c == 62u8 && c1 == 61u8 { ret 2usize }
    if c == 60u8 && c1 == 60u8 { ret 2usize }
    if c == 62u8 && c1 == 62u8 { ret 2usize }
    if c == 43u8 && (c1 == 43u8 || c1 == 61u8) { ret 2usize }
    if c == 45u8 && (c1 == 45u8 || c1 == 61u8) { ret 2usize }
    if c == 42u8 && (c1 == 42u8 || c1 == 61u8) { ret 2usize }
    if (c == 47u8 || c == 37u8 || c == 94u8) && c1 == 61u8 { ret 2usize }
    if c == 38u8 && (c1 == 38u8 || c1 == 61u8) { ret 2usize }
    if c == 124u8 && (c1 == 124u8 || c1 == 61u8) { ret 2usize }
    if c == 63u8 && c1 == 63u8 { ret 2usize }
    if c == 63u8 && c1 == 46u8 && !is_digit(c2) { ret 2usize }
    ret 1usize
}

fn is_punct_start(c: u8) -> bool {
    ret c == 123u8 || c == 125u8 || c == 40u8 || c == 41u8 || c == 91u8 || c == 93u8 || c == 59u8 || c == 44u8 || c == 60u8 || c == 62u8 || c == 61u8 || c == 33u8 || c == 43u8 || c == 45u8 || c == 42u8 || c == 47u8 || c == 37u8 || c == 38u8 || c == 124u8 || c == 94u8 || c == 126u8 || c == 63u8 || c == 58u8 || c == 46u8 || c == 64u8
}

// The next token.
fn next_token(lx: *Lexer) -> (Tok, err) {
    var t: Tok = zero
    let (nl, se) = skip_space(lx)
    if se != ok { ret (t, se) }
    t.nl = nl
    t.start = lx.pos
    t.line = lx.line
    if lx.pos >= lx.src.len {
        t.kind = T_EOF
        t.end = lx.pos
        ret (t, ok)
    }
    let c = lx.src[lx.pos]
    if is_id_start(c) || c == 92u8 {
        t.kind = T_IDENT
        let (name, esc, ie) = read_ident(lx)
        if ie != ok { ret (t, ie) }
        t.text = name
        t.escaped = esc
        t.end = lx.pos
        ret (t, ok)
    }
    if is_digit(c) || (c == 46u8 && lx.pos + 1usize < lx.src.len && is_digit(lx.src[lx.pos + 1usize])) {
        t.kind = T_NUM
        let ne = read_number(lx, &t)
        ret (t, ne)
    }
    if c == 34u8 || c == 39u8 {
        t.kind = T_STR
        let se2 = read_string(lx, &t, c)
        ret (t, se2)
    }
    if c == 96u8 {
        t.kind = T_TEMPLATE
        let te = read_template(lx, &t)
        ret (t, te)
    }
    if c == 35u8 {
        if lx.pos + 1usize < lx.src.len && (is_id_start(lx.src[lx.pos + 1usize]) || lx.src[lx.pos + 1usize] == 92u8) {
            lx.pos += 1usize
            let (name2, esc2, ie2) = read_ident(lx)
            if ie2 != ok { ret (t, ie2) }
            t.kind = T_PRIVATE
            t.text = name2
            t.end = lx.pos
            ret (t, ok)
        }
        ret (t, fail(lx, "unexpected #"))
    }
    if is_punct_start(c) {
        let n = punct_len(lx.src, lx.pos)
        t.kind = T_PUNCT
        t.text = lx.src[lx.pos..lx.pos + n]
        lx.pos += n
        t.end = lx.pos
        ret (t, ok)
    }
    ret (t, fail(lx, "unexpected character"))
}

// Re-reads the `/` or `/=` token that starts at `start` as a regular expression literal.
fn regex_at(lx: *Lexer, start: usize) -> (Tok, err) {
    var t: Tok = zero
    t.kind = T_REGEX
    t.start = start
    t.line = lx.line
    let src = lx.src
    var pos = start + 1usize
    var in_class = false
    var closed = false
    while pos < src.len && !closed {
        let c = src[pos]
        if line_terminator(src, pos) > 0usize { ret (t, fail(lx, "unterminated regular expression")) }
        if c == 92u8 {
            if pos + 1usize < src.len && line_terminator(src, pos + 1usize) > 0usize { ret (t, fail(lx, "unterminated regular expression")) }
            pos += 2usize
        } else if c == 91u8 {
            in_class = true
            pos += 1usize
        } else if c == 93u8 {
            in_class = false
            pos += 1usize
        } else if c == 47u8 && !in_class {
            closed = true
        } else {
            pos += 1usize
        }
    }
    if !closed || pos > src.len { ret (t, fail(lx, "unterminated regular expression")) }
    t.text = src[start + 1usize..pos]
    pos += 1usize
    let flag_start = pos
    while pos < src.len && id_part_at(src, pos) { pos += 1usize }
    t.flags = src[flag_start..pos]
    lx.pos = pos
    t.end = pos
    ret (t, ok)
}
