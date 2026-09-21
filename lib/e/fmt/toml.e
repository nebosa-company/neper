// TOML as a pull parser: `parse` yields one event per call over the source held whole, and
// every string it hands back borrows either the source or the caller's scratch until the next
// call. Nothing here allocates. The shape is the fence's: table headers and key/value pairs
// are the events; an array or an inline table is a start event, its members one by one, then
// an end event, so a caller who wants a tree builds one and a caller who wants one key
// does not pay for a tree.
//
// A key path is a run of dotted keys -- bare, basic `"..."` or literal `'...'` -- placed in the
// caller's `keys` slots and handed back as a slice of them. A `Key` event's path is relative to
// the table it is in; an array member is a `Value` event with an empty path. A datetime is kept
// as its text, since what to do with one is the caller's business and every choice costs a
// calendar.
//
// ponytail: no duplicate-key or table-redefinition detection; that needs a set of every path
// seen, which is the tree this parser exists not to build. A caller who builds the tree
// detects them there.

use e.mem
use e.str

type Kind = enum u8 { String, Integer, Float, Bool, Datetime, ArrayStart, ArrayEnd, InlineTableStart, InlineTableEnd }
type EventKind = enum u8 { End, TableStart, ArrayTableStart, Key, Value }

type Value = struct { kind: Kind, text: str, integer: i64, float: f64, boolean: bool }

type Event = struct { kind: EventKind, path: []const str, value: Value }

error Invalid
error TooLarge
error TooDeep

const MAX_DEPTH: usize = 32usize

const ARRAY_FIRST: u8 = 1u8
const ARRAY_MORE: u8 = 2u8
const TABLE_FIRST: u8 = 3u8
const TABLE_MORE: u8 = 4u8

const TAB: u8 = 9u8
const LF: u8 = 10u8
const CR: u8 = 13u8
const SPACE: u8 = 32u8
const HASH: u8 = 35u8
const DQUOTE: u8 = 34u8
const SQUOTE: u8 = 39u8
const BACKSLASH: u8 = 92u8

type Parser = struct { source: str, at: usize, keys: []str, scratch: []u8, used: usize, stack: [MAX_DEPTH]u8, depth: usize, need_eol: bool }

fn parser(source: str, keys: []str, scratch: []u8) -> Parser {
    var p: Parser = zero
    p.source = source
    p.keys = keys
    p.scratch = scratch
    ret p
}

fn peek(p: *Parser) -> u8 {
    if p.at >= p.source.len { ret 0u8 }
    ret p.source[p.at]
}

fn peek_at(p: *Parser, ahead: usize) -> u8 {
    if p.at + ahead >= p.source.len { ret 0u8 }
    ret p.source[p.at + ahead]
}

fn skip_space(p: *Parser) {
    while p.at < p.source.len && (p.source[p.at] == SPACE || p.source[p.at] == TAB) { p.at += 1usize }
}

fn skip_comment(p: *Parser) {
    if peek(p) == HASH {
        while p.at < p.source.len && p.source[p.at] != LF { p.at += 1usize }
    }
}

// Whitespace, line endings and comments: what may lie between statements and between the
// members of an array.
fn skip_blank(p: *Parser) {
    while p.at < p.source.len {
        let c = p.source[p.at]
        if c == SPACE || c == TAB || c == LF || c == CR {
            p.at += 1usize
        } else if c == HASH {
            skip_comment(p)
        } else {
            break
        }
    }
}

fn expect_eol(p: *Parser) -> err {
    skip_space(p)
    skip_comment(p)
    if p.at >= p.source.len { ret ok }
    if p.source[p.at] == LF {
        p.at += 1usize
        ret ok
    }
    if p.source[p.at] == CR && peek_at(p, 1usize) == LF {
        p.at += 2usize
        ret ok
    }
    ret Invalid
}

fn put(p: *Parser, byte: u8) -> err {
    if p.used >= p.scratch.len { ret TooLarge }
    p.scratch[p.used] = byte
    p.used += 1usize
    ret ok
}

fn put_utf8(p: *Parser, point: u32) -> err {
    if point > 1114111u32 || (point >= 55296u32 && point <= 57343u32) { ret Invalid }
    if point < 128u32 { ret put(p, u8(point)) }
    if point < 2048u32 {
        try put(p, u8(192u32 | (point >> 6u32)))
        ret put(p, u8(128u32 | (point & 63u32)))
    }
    if point < 65536u32 {
        try put(p, u8(224u32 | (point >> 12u32)))
        try put(p, u8(128u32 | ((point >> 6u32) & 63u32)))
        ret put(p, u8(128u32 | (point & 63u32)))
    }
    try put(p, u8(240u32 | (point >> 18u32)))
    try put(p, u8(128u32 | ((point >> 12u32) & 63u32)))
    try put(p, u8(128u32 | ((point >> 6u32) & 63u32)))
    ret put(p, u8(128u32 | (point & 63u32)))
}

fn hex_value(byte: u8) -> (u32, bool) {
    if byte >= 48u8 && byte <= 57u8 { ret (u32(byte - 48u8), true) }
    if byte >= 97u8 && byte <= 102u8 { ret (u32(byte - 87u8), true) }
    if byte >= 65u8 && byte <= 70u8 { ret (u32(byte - 55u8), true) }
    ret (0u32, false)
}

// One escape, the backslash already behind. In a multi-line string a backslash before the
// line ending swallows it and every blank up to the next non-blank.
fn escape(p: *Parser, multi: bool) -> err {
    if p.at >= p.source.len { ret Invalid }
    let c = p.source[p.at]
    p.at += 1usize
    if c == 98u8 { ret put(p, 8u8) }
    if c == 116u8 { ret put(p, TAB) }
    if c == 110u8 { ret put(p, LF) }
    if c == 102u8 { ret put(p, 12u8) }
    if c == 114u8 { ret put(p, CR) }
    if c == DQUOTE { ret put(p, DQUOTE) }
    if c == BACKSLASH { ret put(p, BACKSLASH) }
    if c == 117u8 || c == 85u8 {
        var count = 4usize
        if c == 85u8 { count = 8usize }
        var point = 0u32
        var i = 0usize
        while i < count {
            if p.at >= p.source.len { ret Invalid }
            let (nibble, is_hex) = hex_value(p.source[p.at])
            if !is_hex { ret Invalid }
            point = (point << 4u32) | nibble
            p.at += 1usize
            i += 1usize
        }
        ret put_utf8(p, point)
    }
    if multi && (c == SPACE || c == TAB || c == LF || c == CR) {
        // Only blanks may stand between the backslash and the line ending.
        var scan = p.at - 1usize
        while scan < p.source.len && (p.source[scan] == SPACE || p.source[scan] == TAB) { scan += 1usize }
        if scan >= p.source.len || (p.source[scan] != LF && p.source[scan] != CR) { ret Invalid }
        while scan < p.source.len {
            let b = p.source[scan]
            if b != SPACE && b != TAB && b != LF && b != CR { break }
            scan += 1usize
        }
        p.at = scan
        ret ok
    }
    ret Invalid
}

// A basic string, the opening quote behind; decoded into the scratch.
fn basic(p: *Parser) -> (str, err) {
    let start = p.used
    while true {
        if p.at >= p.source.len { ret ("", Invalid) }
        let c = p.source[p.at]
        p.at += 1usize
        if c == DQUOTE { break }
        if c == LF || c == CR { ret ("", Invalid) }
        if c == BACKSLASH {
            let escape_error = escape(p, false)
            if escape_error != ok { ret ("", escape_error) }
            continue
        }
        let put_error = put(p, c)
        if put_error != ok { ret ("", put_error) }
    }
    ret (p.scratch[start..p.used], ok)
}

// A multi-line basic string, the three opening quotes behind. A closing run may carry one or
// two extra quotes that belong to the content.
fn multi_basic(p: *Parser) -> (str, err) {
    let start = p.used
    if peek(p) == CR && peek_at(p, 1usize) == LF { p.at += 2usize } else if peek(p) == LF { p.at += 1usize }
    while true {
        if p.at >= p.source.len { ret ("", Invalid) }
        let c = p.source[p.at]
        if c == DQUOTE && peek_at(p, 1usize) == DQUOTE && peek_at(p, 2usize) == DQUOTE {
            p.at += 3usize
            var extra = 0usize
            while extra < 2usize && peek(p) == DQUOTE {
                let quote_error = put(p, DQUOTE)
                if quote_error != ok { ret ("", quote_error) }
                p.at += 1usize
                extra += 1usize
            }
            break
        }
        p.at += 1usize
        if c == BACKSLASH {
            let escape_error = escape(p, true)
            if escape_error != ok { ret ("", escape_error) }
            continue
        }
        let put_error = put(p, c)
        if put_error != ok { ret ("", put_error) }
    }
    ret (p.scratch[start..p.used], ok)
}

// A literal string borrows the source: nothing in it is decoded.
fn literal(p: *Parser) -> (str, err) {
    let start = p.at
    while true {
        if p.at >= p.source.len { ret ("", Invalid) }
        let c = p.source[p.at]
        if c == SQUOTE { break }
        if c == LF || c == CR { ret ("", Invalid) }
        p.at += 1usize
    }
    let stop = p.at
    p.at += 1usize
    ret (p.source[start..stop], ok)
}

fn multi_literal(p: *Parser) -> (str, err) {
    if peek(p) == CR && peek_at(p, 1usize) == LF { p.at += 2usize } else if peek(p) == LF { p.at += 1usize }
    let start = p.at
    while true {
        if p.at >= p.source.len { ret ("", Invalid) }
        if p.source[p.at] == SQUOTE && peek_at(p, 1usize) == SQUOTE && peek_at(p, 2usize) == SQUOTE {
            var stop = p.at + 3usize
            while stop - p.at < 5usize && stop < p.source.len && p.source[stop] == SQUOTE { stop += 1usize }
            let text = p.source[start..stop - 3usize]
            p.at = stop
            ret (text, ok)
        }
        p.at += 1usize
    }
    ret ("", Invalid)
}

fn is_bare(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 45u8
}

// A dotted key path into the caller's slots. Blanks may surround each dot.
fn key_path(p: *Parser) -> ([]const str, err) {
    var count = 0usize
    while true {
        skip_space(p)
        if count >= p.keys.len { ret (zero, TooLarge) }
        let c = peek(p)
        if c == DQUOTE {
            p.at += 1usize
            let (text, text_error) = basic(p)
            if text_error != ok { ret (zero, text_error) }
            p.keys[count] = text
        } else if c == SQUOTE {
            p.at += 1usize
            let (text, text_error) = literal(p)
            if text_error != ok { ret (zero, text_error) }
            p.keys[count] = text
        } else {
            let start = p.at
            while p.at < p.source.len && is_bare(p.source[p.at]) { p.at += 1usize }
            if p.at == start { ret (zero, Invalid) }
            p.keys[count] = p.source[start..p.at]
        }
        count += 1usize
        skip_space(p)
        if peek(p) != 46u8 { break }
        p.at += 1usize
    }
    ret (p.keys[0usize..count], ok)
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

// Digits with `_` only between two of them, copied to the scratch without them.
fn strip_underscores(p: *Parser, text: str) -> (str, err) {
    let start = p.used
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 95u8 {
            if i == 0usize || i + 1usize == text.len { ret ("", Invalid) }
            if !str.is_ascii_alnum(text[i - 1usize]) || !str.is_ascii_alnum(text[i + 1usize]) { ret ("", Invalid) }
        } else {
            let put_error = put(p, c)
            if put_error != ok { ret ("", put_error) }
        }
        i += 1usize
    }
    ret (p.scratch[start..p.used], ok)
}

fn looks_like_datetime(text: str) -> bool {
    if text.len >= 5usize && is_digit(text[0usize]) && is_digit(text[1usize]) {
        if text[2usize] == 58u8 { ret true }
        if text.len >= 10usize && is_digit(text[2usize]) && is_digit(text[3usize]) && text[4usize] == 45u8 { ret true }
    }
    ret false
}

fn datetime_ok(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        let c = text[i]
        let allowed = is_digit(c) || c == 45u8 || c == 58u8 || c == 46u8 || c == 43u8 || c == 84u8 || c == 116u8 || c == 90u8 || c == 122u8 || c == SPACE
        if !allowed { ret false }
        i += 1usize
    }
    ret true
}

fn number(p: *Parser, text: str) -> (Value, err) {
    var out: Value = zero
    out.text = text
    var body = text
    var negative = false
    if body.len > 0usize && (body[0usize] == 43u8 || body[0usize] == 45u8) {
        negative = body[0usize] == 45u8
        body = body[1usize..]
    }
    if body.len == 0usize { ret (out, Invalid) }
    if str.eq(body, "inf") || str.eq(body, "nan") {
        out.kind = .Float
        let (special, special_error) = str.parse_f64(body)
        if special_error != ok { ret (out, Invalid) }
        out.float = special
        if negative { out.float = mem.bitcast[f64](mem.bitcast[u64](special) | 9223372036854775808u64) }
        ret (out, ok)
    }
    if looks_like_datetime(text) {
        if !datetime_ok(text) { ret (out, Invalid) }
        out.kind = .Datetime
        ret (out, ok)
    }
    if body.len > 2usize && body[0usize] == 48u8 && (body[1usize] == 120u8 || body[1usize] == 111u8 || body[1usize] == 98u8) {
        if text.len != body.len { ret (out, Invalid) }
        var radix = 16u8
        if body[1usize] == 111u8 { radix = 8u8 }
        if body[1usize] == 98u8 { radix = 2u8 }
        let (digits, digits_error) = strip_underscores(p, body[2usize..])
        if digits_error != ok { ret (out, digits_error) }
        let (magnitude, magnitude_error) = str.parse_u64_radix(digits, radix)
        if magnitude_error != ok || magnitude > 9223372036854775807u64 { ret (out, Invalid) }
        out.kind = .Integer
        out.integer = i64(magnitude)
        ret (out, ok)
    }
    if !is_digit(body[0usize]) { ret (out, Invalid) }
    if body.len > 1usize && body[0usize] == 48u8 && is_digit(body[1usize]) { ret (out, Invalid) }
    var is_float = false
    var i = 0usize
    while i < body.len {
        let c = body[i]
        if c == 46u8 || c == 101u8 || c == 69u8 { is_float = true }
        i += 1usize
    }
    let (digits, digits_error) = strip_underscores(p, body)
    if digits_error != ok { ret (out, digits_error) }
    if is_float {
        // `e.str` reads a lowercase exponent and no `+` before it, so the copy is folded to
        // that form: it is the scratch's own bytes already.
        let bytes = p.scratch[p.used - digits.len..p.used]
        var kept = 0usize
        i = 0usize
        while i < bytes.len {
            var c = bytes[i]
            if c == 69u8 { c = 101u8 }
            if c == 43u8 {
                if i == 0usize || bytes[i - 1usize] != 69u8 && bytes[i - 1usize] != 101u8 { ret (out, Invalid) }
            } else {
                bytes[kept] = c
                kept += 1usize
            }
            i += 1usize
        }
        let (parsed, parse_error) = str.parse_f64(bytes[0usize..kept])
        if parse_error != ok { ret (out, Invalid) }
        out.kind = .Float
        out.float = parsed
        if negative { out.float = 0.0f64 - parsed }
        ret (out, ok)
    }
    let (magnitude, magnitude_error) = str.parse_u64(digits)
    if magnitude_error != ok { ret (out, Invalid) }
    if negative {
        if magnitude > 9223372036854775808u64 { ret (out, Invalid) }
        out.kind = .Integer
        if magnitude == 9223372036854775808u64 { out.integer = -9223372036854775807i64 - 1i64 } else { out.integer = 0i64 - i64(magnitude) }
        ret (out, ok)
    }
    if magnitude > 9223372036854775807u64 { ret (out, Invalid) }
    out.kind = .Integer
    out.integer = i64(magnitude)
    ret (out, ok)
}

fn push_container(p: *Parser, state: u8) -> err {
    if p.depth >= MAX_DEPTH { ret TooDeep }
    p.stack[p.depth] = state
    p.depth += 1usize
    ret ok
}

// One value. A container start pushes it; its members come from the calls that follow.
fn value(p: *Parser) -> (Value, err) {
    var out: Value = zero
    let c = peek(p)
    if c == DQUOTE {
        out.kind = .String
        if peek_at(p, 1usize) == DQUOTE && peek_at(p, 2usize) == DQUOTE {
            p.at += 3usize
            let (text, text_error) = multi_basic(p)
            out.text = text
            ret (out, text_error)
        }
        p.at += 1usize
        let (text, text_error) = basic(p)
        out.text = text
        ret (out, text_error)
    }
    if c == SQUOTE {
        out.kind = .String
        if peek_at(p, 1usize) == SQUOTE && peek_at(p, 2usize) == SQUOTE {
            p.at += 3usize
            let (text, text_error) = multi_literal(p)
            out.text = text
            ret (out, text_error)
        }
        p.at += 1usize
        let (text, text_error) = literal(p)
        out.text = text
        ret (out, text_error)
    }
    if c == 91u8 {
        p.at += 1usize
        out.kind = .ArrayStart
        ret (out, push_container(p, ARRAY_FIRST))
    }
    if c == 123u8 {
        p.at += 1usize
        out.kind = .InlineTableStart
        ret (out, push_container(p, TABLE_FIRST))
    }
    // Everything else is one run of the bytes a number, a bool or a datetime is made of; a
    // datetime alone may hold a space, between its date and its time.
    let start = p.at
    while p.at < p.source.len {
        let b = p.source[p.at]
        if str.is_ascii_alnum(b) || b == 95u8 || b == 43u8 || b == 45u8 || b == 46u8 || b == 58u8 {
            p.at += 1usize
        } else if b == SPACE && p.at - start == 10usize && looks_like_datetime(p.source[start..p.at]) && is_digit(peek_at(p, 1usize)) {
            p.at += 1usize
        } else {
            break
        }
    }
    let text = p.source[start..p.at]
    if str.eq(text, "true") || str.eq(text, "false") {
        out.kind = .Bool
        out.text = text
        out.boolean = text.len == 4usize
        ret (out, ok)
    }
    let (parsed, parse_error) = number(p, text)
    ret (parsed, parse_error)
}

fn pop(p: *Parser) {
    p.depth -= 1usize
    if p.depth == 0usize { p.need_eol = true }
}

// The next event. `End` once the source is spent; every string in the event is valid until
// the next call.
fn parse(p: *Parser) -> (Event, err) {
    var event: Event = zero
    p.used = 0usize
    if p.depth > 0usize {
        let state = p.stack[p.depth - 1usize]
        if state == ARRAY_FIRST || state == ARRAY_MORE {
            skip_blank(p)
            if state == ARRAY_MORE {
                if peek(p) == 44u8 {
                    p.at += 1usize
                    skip_blank(p)
                } else if peek(p) != 93u8 {
                    ret (event, Invalid)
                }
            }
            if peek(p) == 93u8 {
                p.at += 1usize
                pop(p)
                event.kind = .Value
                event.value.kind = .ArrayEnd
                ret (event, ok)
            }
            p.stack[p.depth - 1usize] = ARRAY_MORE
            let (member, member_error) = value(p)
            if member_error != ok { ret (event, member_error) }
            event.kind = .Value
            event.value = member
            ret (event, ok)
        }
        skip_space(p)
        if state == TABLE_FIRST && peek(p) == 125u8 {
            p.at += 1usize
            pop(p)
            event.kind = .Value
            event.value.kind = .InlineTableEnd
            ret (event, ok)
        }
        if state == TABLE_MORE {
            if peek(p) == 125u8 {
                p.at += 1usize
                pop(p)
                event.kind = .Value
                event.value.kind = .InlineTableEnd
                ret (event, ok)
            }
            if peek(p) != 44u8 { ret (event, Invalid) }
            p.at += 1usize
        }
        p.stack[p.depth - 1usize] = TABLE_MORE
        let (path, path_error) = key_path(p)
        if path_error != ok { ret (event, path_error) }
        if peek(p) != 61u8 { ret (event, Invalid) }
        p.at += 1usize
        skip_space(p)
        let (member, member_error) = value(p)
        if member_error != ok { ret (event, member_error) }
        event.kind = .Key
        event.path = path
        event.value = member
        ret (event, ok)
    }
    if p.need_eol {
        p.need_eol = false
        let eol_error = expect_eol(p)
        if eol_error != ok { ret (event, eol_error) }
    }
    skip_blank(p)
    if p.at >= p.source.len {
        event.kind = .End
        ret (event, ok)
    }
    if peek(p) == 91u8 {
        p.at += 1usize
        var closing = 1usize
        event.kind = .TableStart
        if peek(p) == 91u8 {
            p.at += 1usize
            closing = 2usize
            event.kind = .ArrayTableStart
        }
        let (path, path_error) = key_path(p)
        if path_error != ok { ret (event, path_error) }
        var i = 0usize
        while i < closing {
            if peek(p) != 93u8 { ret (event, Invalid) }
            p.at += 1usize
            i += 1usize
        }
        event.path = path
        p.need_eol = true
        ret (event, ok)
    }
    let (path, path_error) = key_path(p)
    if path_error != ok { ret (event, path_error) }
    if peek(p) != 61u8 { ret (event, Invalid) }
    p.at += 1usize
    skip_space(p)
    let (member, member_error) = value(p)
    if member_error != ok { ret (event, member_error) }
    event.kind = .Key
    event.path = path
    event.value = member
    if p.depth == 0usize { p.need_eol = true }
    ret (event, ok)
}
