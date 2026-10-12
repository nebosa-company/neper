// JSON5 over `e.fmt.json`: `parse` transcodes JSON5 text to strict JSON and hands it to the
// JSON parser, so the value tree, numbers-as-lexemes and depth limits are the JSON module's
// own; `write` emits a tree as JSON5 with identifier keys left unquoted.
//
// Accepted beyond JSON (json5.org, ES5): `//` and `/* */` comments; trailing commas in arrays
// and objects; single- or double-quoted strings with `\xHH`, `\v`, `\0`, `\'`, line
// continuations and any other escaped character standing for itself; unquoted object keys
// (an IdentifierName: ASCII letters, `$`, `_`, digits after the first, raw non-ASCII bytes,
// and `\uXXXX` escapes); numbers with a leading `+`, a bare leading or trailing `.`, and
// hexadecimal integers (up to 64 digits); the extra whitespace characters (no-break space,
// BOM, line and paragraph separators, the Zs spaces). A document's numbers keep their value,
// not their spelling: `0xFF` reads as `255`, `.5` as `0.5`.
//
// `Infinity` and `NaN` (which JSON5 allows) have no `e.fmt.json` representation and are
// refused as `NonFinite`. Anything else outside the grammar is `Invalid`.

use e.io
use e.mem
use e.fmt.json

type Out = struct { buf: []u8, n: usize, bad: bool }
error Invalid
error NonFinite

fn put(o: *Out, c: u8) {
    if o.n >= o.buf.len {
        o.bad = true
        ret
    }
    o.buf[o.n] = c
    o.n += 1usize
}

fn put_text(o: *Out, s: str) {
    var i = 0usize
    while i < s.len {
        put(o, s[i])
        i += 1usize
    }
}

fn hex_value(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i32(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret i32(c - 55u8) }
    ret -1i32
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_id_start(c: u8) -> bool {
    ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 36u8 || c == 95u8 || c >= 128u8
}

fn is_id_part(c: u8) -> bool { ret is_id_start(c) || is_digit(c) }

// Length of a multi-byte whitespace character at `at` (0 when there is none).
fn wide_space(src: str, at: usize) -> usize {
    if at + 1usize < src.len && src[at] == 194u8 && src[at + 1usize] == 160u8 { ret 2usize }
    if at + 2usize < src.len {
        let b0 = src[at]
        let b1 = src[at + 1usize]
        let b2 = src[at + 2usize]
        if b0 == 239u8 && b1 == 187u8 && b2 == 191u8 { ret 3usize }
        if b0 == 226u8 && b1 == 128u8 && ((b2 >= 128u8 && b2 <= 138u8) || b2 == 168u8 || b2 == 169u8 || b2 == 175u8) { ret 3usize }
        if b0 == 226u8 && b1 == 129u8 && b2 == 159u8 { ret 3usize }
        if b0 == 227u8 && b1 == 128u8 && b2 == 128u8 { ret 3usize }
        if b0 == 225u8 && b1 == 154u8 && b2 == 128u8 { ret 3usize }
    }
    ret 0usize
}

fn id_part_at(src: str, at: usize) -> bool { ret is_id_part(src[at]) && wide_space(src, at) == 0usize }

// Skips whitespace and comments; false on an unterminated block comment.
fn skip(src: str, at: usize) -> (usize, bool) {
    var i = at
    while i < src.len {
        let c = src[i]
        if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 11u8 || c == 12u8 {
            i += 1usize
        } else if c == 47u8 && i + 1usize < src.len && src[i + 1usize] == 47u8 {
            i += 2usize
            while i < src.len && src[i] != 10u8 && src[i] != 13u8 {
                // U+2028 and U+2029 also end a line comment
                if i + 2usize < src.len && src[i] == 226u8 && src[i + 1usize] == 128u8 && (src[i + 2usize] == 168u8 || src[i + 2usize] == 169u8) { break }
                i += 1usize
            }
        } else if c == 47u8 && i + 1usize < src.len && src[i + 1usize] == 42u8 {
            i += 2usize
            var closed = false
            while i + 1usize < src.len {
                if src[i] == 42u8 && src[i + 1usize] == 47u8 {
                    closed = true
                    i += 2usize
                    break
                }
                i += 1usize
            }
            if !closed { ret (i, false) }
        } else {
            let w = wide_space(src, i)
            if w == 0usize { break }
            i += w
        }
    }
    ret (i, true)
}

fn put_u_escape(o: *Out, unit: u32) {
    put(o, 92u8)
    put(o, 117u8)
    var shift = 12u32
    while true {
        let nib = (unit >> shift) & 15u32
        if nib < 10u32 {
            put(o, u8(48u32 + nib))
        } else {
            put(o, u8(87u32 + nib))
        }
        if shift == 0u32 { break }
        shift -= 4u32
    }
}

fn put_utf8(o: *Out, cp: u32) {
    if cp < 128u32 {
        put(o, u8(cp))
    } else if cp < 2048u32 {
        put(o, u8(192u32 + (cp >> 6u32)))
        put(o, u8(128u32 + (cp & 63u32)))
    } else if cp < 65536u32 {
        put(o, u8(224u32 + (cp >> 12u32)))
        put(o, u8(128u32 + ((cp >> 6u32) & 63u32)))
        put(o, u8(128u32 + (cp & 63u32)))
    } else {
        put(o, u8(240u32 + (cp >> 18u32)))
        put(o, u8(128u32 + ((cp >> 12u32) & 63u32)))
        put(o, u8(128u32 + ((cp >> 6u32) & 63u32)))
        put(o, u8(128u32 + (cp & 63u32)))
    }
}

// `\uXXXX` at src[at] (the `u`); returns the unit and the index after it.
fn read_u4(src: str, at: usize) -> (u32, usize, bool) {
    if at + 4usize >= src.len { ret (0u32, at, false) }
    var v = 0u32
    var i = 1usize
    while i <= 4usize {
        let h = hex_value(src[at + i])
        if h < 0i32 { ret (0u32, at, false) }
        v = v * 16u32 + u32(h)
        i += 1usize
    }
    ret (v, at + 5usize, true)
}

// A quoted string at src[at] re-emitted as a JSON string; returns the index after it.
fn string_token(o: *Out, src: str, at: usize) -> (usize, bool) {
    let q = src[at]
    var i = at + 1usize
    put(o, 34u8)
    while i < src.len && src[i] != q {
        let c = src[i]
        if c == 92u8 {
            i += 1usize
            if i >= src.len { ret (i, false) }
            let e = src[i]
            if e == 110u8 || e == 114u8 || e == 116u8 || e == 98u8 || e == 102u8 || e == 34u8 || e == 92u8 || e == 47u8 {
                put(o, 92u8)
                put(o, e)
                i += 1usize
            } else if e == 118u8 {
                put_u_escape(o, 11u32)
                i += 1usize
            } else if e == 48u8 {
                if i + 1usize < src.len && is_digit(src[i + 1usize]) { ret (i, false) }
                put_u_escape(o, 0u32)
                i += 1usize
            } else if e == 120u8 {
                if i + 2usize >= src.len { ret (i, false) }
                let h1 = hex_value(src[i + 1usize])
                let h2 = hex_value(src[i + 2usize])
                if h1 < 0i32 || h2 < 0i32 { ret (i, false) }
                let cp = u32(h1 * 16i32 + h2)
                if cp < 32u32 || cp == 34u32 || cp == 92u32 {
                    put_u_escape(o, cp)
                } else {
                    put_utf8(o, cp)
                }
                i += 3usize
            } else if e == 117u8 {
                let (unit, next, good) = read_u4(src, i)
                if !good { ret (i, false) }
                put_u_escape(o, unit)
                i = next
            } else if e == 10u8 {
                i += 1usize
            } else if e == 13u8 {
                i += 1usize
                if i < src.len && src[i] == 10u8 { i += 1usize }
            } else if e >= 49u8 && e <= 57u8 {
                ret (i, false)
            } else if e == 226u8 && i + 2usize < src.len && src[i + 1usize] == 128u8 && (src[i + 2usize] == 168u8 || src[i + 2usize] == 169u8) {
                i += 3usize
            } else {
                // any other escaped character stands for itself
                if e == 39u8 {
                    put(o, 39u8)
                } else if e < 32u8 {
                    ret (i, false)
                } else {
                    put(o, e)
                }
                i += 1usize
            }
        } else if c == 10u8 || c == 13u8 {
            ret (i, false)
        } else if c == 34u8 {
            put(o, 92u8)
            put(o, 34u8)
            i += 1usize
        } else if c < 32u8 {
            put_u_escape(o, u32(c))
            i += 1usize
        } else {
            put(o, c)
            i += 1usize
        }
    }
    if i >= src.len { ret (i, false) }
    put(o, 34u8)
    ret (i + 1usize, true)
}

// An unquoted key: IdentifierName with `\uXXXX` escapes, emitted as a JSON string.
fn identifier_token(o: *Out, src: str, at: usize) -> (usize, bool) {
    var i = at
    put(o, 34u8)
    var first = true
    while i < src.len {
        let c = src[i]
        if c == 92u8 {
            if i + 1usize >= src.len || src[i + 1usize] != 117u8 { ret (i, false) }
            let (unit, next, good) = read_u4(src, i + 1usize)
            if !good { ret (i, false) }
            if unit == 34u32 || unit == 92u32 || unit < 32u32 {
                put_u_escape(o, unit)
            } else {
                put_utf8(o, unit)
            }
            i = next
        } else if (first && is_id_start(c)) || (!first && is_id_part(c)) {
            if wide_space(src, i) > 0usize { break }
            put(o, c)
            i += 1usize
        } else {
            break
        }
        first = false
    }
    if first { ret (i, false) }
    put(o, 34u8)
    ret (i, true)
}

fn word_at(src: str, at: usize, word: str) -> bool {
    if at + word.len > src.len { ret false }
    var i = 0usize
    while i < word.len {
        if src[at + i] != word[i] { ret false }
        i += 1usize
    }
    if at + word.len < src.len && id_part_at(src, at + word.len) { ret false }
    ret true
}

// Number at src[at]; returns the index after it, or sets `nonfinite` for NaN / Infinity.
fn number_token(o: *Out, src: str, at: usize, nonfinite: *bool) -> (usize, bool) {
    var i = at
    var negative = false
    if src[i] == 45u8 || src[i] == 43u8 {
        negative = src[i] == 45u8
        i += 1usize
    }
    if i >= src.len { ret (i, false) }
    if word_at(src, i, "Infinity") || word_at(src, i, "NaN") {
        *nonfinite = true
        ret (i, false)
    }
    if negative { put(o, 45u8) }
    if src[i] == 48u8 && i + 1usize < src.len && (src[i + 1usize] == 120u8 || src[i + 1usize] == 88u8) {
        i += 2usize
        // little-endian decimal digits of the value, grown by x16 + digit per hex digit
        var dec: [80]u8 = zero
        var used = 1usize
        var count = 0usize
        while i < src.len && hex_value(src[i]) >= 0i32 {
            if count >= 64usize { ret (i, false) }
            var carry = u32(hex_value(src[i]))
            var d = 0usize
            while d < used {
                let t = u32(dec[d]) * 16u32 + carry
                dec[d] = u8(t % 10u32)
                carry = t / 10u32
                d += 1usize
            }
            while carry > 0u32 {
                dec[used] = u8(carry % 10u32)
                carry = carry / 10u32
                used += 1usize
            }
            count += 1usize
            i += 1usize
        }
        if count == 0usize { ret (i, false) }
        if i < src.len && id_part_at(src, i) { ret (i, false) }
        var k = used
        while k > 0usize {
            k -= 1usize
            put(o, 48u8 + dec[k])
        }
        ret (i, true)
    }
    var int_digits = 0usize
    var lead = i
    while i < src.len && is_digit(src[i]) {
        i += 1usize
        int_digits += 1usize
    }
    if int_digits > 1usize && src[lead] == 48u8 { ret (i, false) }
    if int_digits == 0usize {
        put(o, 48u8)
    } else {
        var k = lead
        while k < i {
            put(o, src[k])
            k += 1usize
        }
    }
    var frac_digits = 0usize
    if i < src.len && src[i] == 46u8 {
        i += 1usize
        let start = i
        while i < src.len && is_digit(src[i]) { i += 1usize }
        frac_digits = i - start
        if frac_digits > 0usize {
            put(o, 46u8)
            var k = start
            while k < i {
                put(o, src[k])
                k += 1usize
            }
        }
    }
    if int_digits == 0usize && frac_digits == 0usize { ret (i, false) }
    if i < src.len && (src[i] == 101u8 || src[i] == 69u8) {
        put(o, 101u8)
        i += 1usize
        if i < src.len && (src[i] == 43u8 || src[i] == 45u8) {
            if src[i] == 45u8 { put(o, 45u8) }
            i += 1usize
        }
        let start = i
        while i < src.len && is_digit(src[i]) {
            put(o, src[i])
            i += 1usize
        }
        if i == start { ret (i, false) }
    }
    if i < src.len && id_part_at(src, i) { ret (i, false) }
    ret (i, true)
}

// Strict JSON text for `source`, in `buf`; the caller's `parse` is the usual way in.
fn transcode(source: str, buf: []u8) -> (usize, err) {
    var o: Out = zero
    o.buf = buf
    var i = 0usize
    // container stack: 1 array, 2 object; `expect_key` tracks object positions
    var kinds: [256]u8 = zero
    var depth = 0usize
    var after_value = false
    var key_next = false
    var nonfinite = false
    while true {
        let (next, closed) = skip(source, i)
        if !closed { ret (0usize, Invalid) }
        i = next
        if i >= source.len { break }
        let c = source[i]
        if c == 123u8 || c == 91u8 {
            if after_value { ret (0usize, Invalid) }
            if depth >= 256usize { ret (0usize, Invalid) }
            kinds[depth] = 1u8
            if c == 123u8 { kinds[depth] = 2u8 }
            depth += 1usize
            put(&o, c)
            i += 1usize
            key_next = c == 123u8
            after_value = false
        } else if c == 125u8 || c == 93u8 {
            if depth == 0usize { ret (0usize, Invalid) }
            let want = 1u8
            var expect = 93u8
            if kinds[depth - 1usize] == 2u8 { expect = 125u8 }
            if c != expect { ret (0usize, Invalid) }
            // a key without a value, or a comma then nothing, is checked by the JSON parser
            depth -= 1usize
            put(&o, c)
            i += 1usize
            after_value = true
            key_next = false
        } else if c == 44u8 {
            if !after_value || depth == 0usize { ret (0usize, Invalid) }
            // trailing comma: look ahead past whitespace and comments for a closer
            let (peek, peek_closed) = skip(source, i + 1usize)
            if !peek_closed { ret (0usize, Invalid) }
            if peek < source.len && (source[peek] == 125u8 || source[peek] == 93u8) {
                i = peek
                continue
            }
            put(&o, 44u8)
            i += 1usize
            after_value = false
            key_next = kinds[depth - 1usize] == 2u8
        } else if c == 58u8 {
            if depth == 0usize || kinds[depth - 1usize] != 2u8 || !after_value { ret (0usize, Invalid) }
            put(&o, 58u8)
            i += 1usize
            after_value = false
            key_next = false
        } else {
            if after_value { ret (0usize, Invalid) }
            var good = false
            var after = i
            if c == 34u8 || c == 39u8 {
                let (n2, ok2) = string_token(&o, source, i)
                after = n2
                good = ok2
            } else if depth > 0usize && kinds[depth - 1usize] == 2u8 && key_next {
                let (n2, ok2) = identifier_token(&o, source, i)
                after = n2
                good = ok2
            } else if is_digit(c) || c == 46u8 || c == 45u8 || c == 43u8 {
                let (n2, ok2) = number_token(&o, source, i, &nonfinite)
                after = n2
                good = ok2
                if nonfinite { ret (0usize, NonFinite) }
            } else if word_at(source, i, "true") {
                put_text(&o, "true")
                after = i + 4usize
                good = true
            } else if word_at(source, i, "false") {
                put_text(&o, "false")
                after = i + 5usize
                good = true
            } else if word_at(source, i, "null") {
                put_text(&o, "null")
                after = i + 4usize
                good = true
            } else if word_at(source, i, "Infinity") || word_at(source, i, "NaN") {
                ret (0usize, NonFinite)
            }
            if !good { ret (0usize, Invalid) }
            i = after
            // a key is followed by a colon; any other token is a value
            after_value = true
            key_next = false
        }
    }
    if depth != 0usize || o.bad { ret (0usize, Invalid) }
    ret (o.n, ok)
}

fn parse(a: *mem.Arena, source: str, options: json.Options) -> (json.Value, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, source.len * 6usize + 16usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    let (n, transcode_error) = transcode(source, buf)
    if transcode_error != ok { ret (zero, transcode_error) }
    let (value, parse_error) = json.parse(a, buf[0usize..n], options)
    ret (value, parse_error)
}

// ---- writing ----

fn is_identifier(key: str) -> bool {
    if key.len == 0usize { ret false }
    var i = 0usize
    while i < key.len {
        let c = key[i]
        let letter = (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 36u8 || c == 95u8
        if !(letter || (i > 0usize && is_digit(c))) { ret false }
        i += 1usize
    }
    ret true
}

fn write_indent(w: *io.Writer, spaces: usize) -> err {
    var n = spaces
    while n > 0usize {
        try io.write_all(w, " ")
        n -= 1usize
    }
    ret ok
}

fn write_value(w: *io.Writer, value: *const json.Value, indent: u8, depth: usize) -> err {
    switch *value {
    case .Null:
        ret io.write_all(w, "null")
    case .Bool as flag:
        if flag { ret io.write_all(w, "true") }
        ret io.write_all(w, "false")
    case .Number as n:
        ret io.write_all(w, n.lexeme)
    case .String as text:
        ret json.write_string(w, text)
    case .Array as items:
        if items.len == 0usize { ret io.write_all(w, "[]") }
        try io.write_all(w, "[")
        var at = 0usize
        while at < items.len {
            if at > 0usize { try io.write_all(w, ",") }
            if indent != 0u8 {
                try io.write_all(w, "\n")
                try write_indent(w, usize(indent) * (depth + 1usize))
            }
            try write_value(w, &items[at], indent, depth + 1usize)
            at += 1usize
        }
        if indent != 0u8 {
            try io.write_all(w, "\n")
            try write_indent(w, usize(indent) * depth)
        }
        ret io.write_all(w, "]")
    case .Object as members:
        if members.len == 0usize { ret io.write_all(w, "{}") }
        try io.write_all(w, "{")
        var at = 0usize
        while at < members.len {
            if at > 0usize { try io.write_all(w, ",") }
            if indent != 0u8 {
                try io.write_all(w, "\n")
                try write_indent(w, usize(indent) * (depth + 1usize))
            }
            if is_identifier(members[at].key) {
                try io.write_all(w, members[at].key)
            } else {
                try json.write_string(w, members[at].key)
            }
            try io.write_all(w, ":")
            if indent != 0u8 { try io.write_all(w, " ") }
            try write_value(w, &members[at].value, indent, depth + 1usize)
            at += 1usize
        }
        if indent != 0u8 {
            try io.write_all(w, "\n")
            try write_indent(w, usize(indent) * depth)
        }
        ret io.write_all(w, "}")
    default:
        ret Invalid
    }
}

// Compact JSON5: identifier keys bare, every other key and every string double quoted.
fn write(w: *io.Writer, value: *const json.Value) -> err { ret write_value(w, value, 0u8, 0usize) }

fn write_pretty(w: *io.Writer, value: *const json.Value, indent: u8) -> err { ret write_value(w, value, indent, 0usize) }
