// A CSS Syntax Level 3 tokenizer and rule grammar (L038), after Vaper's `css_tokenizer.dart` and `css_syntax.dart`
// (https://www.w3.org/TR/css-syntax-3/). `tokenize` never fails on input: malformed text becomes recovery tokens
// (`BadString`, `BadUrl`, `Delim`) and scanning goes on, and every token carries byte offsets into the source so a
// declaration value or a rule prelude can be sliced out byte-faithfully (`raw_text`). The grammar turns the token stream
// into qualified rules, at-rules and simple blocks and a block's contents into declarations, recovering rather than
// stopping: an unbalanced block ends at the end of input, a bad declaration is skipped to the next `;`, a qualified
// rule with no block is dropped.
//
// Input is UTF-8; a byte of 0x80 or more is a name code point, so a multibyte letter is part of an identifier whole.
// A NUL byte and an escape that names no code point both decode to U+FFFD. Offsets count bytes.
//
// Memory: the arena is retained; every token list and string lives in it.

use e.data.list as list
use e.mem
use e.str

error Invalid

type Kind = enum u8 { Ident, Function, AtKeyword, Hash, String, BadString, Url, BadUrl, Delim, Number, Percentage, Dimension, Whitespace, Cdo, Cdc, Colon, Semicolon, Comma, LeftSquare, RightSquare, LeftParen, RightParen, LeftCurly, RightCurly, Eof }

// One token. `value` is the decoded text where it means something (a name, a string or url body, the delim); a numeric
// token carries `number`, a dimension or percentage its `unit`, `integer` and a hash `hash_id` (the name would start an
// identifier).
type Token = struct { kind: Kind, start: usize, end: usize, value: str, number: f64, unit: str, integer: bool, hash_id: bool }

type Block = struct { open: Kind, inner: []const Token }

// A rule: a qualified rule (`at` false, `name` empty) or an at-rule; `has_block` is false for the `@import x;` form.
type Rule = struct { at: bool, name: str, prelude: []const Token, has_block: bool, block: Block }

type Declaration = struct { name: str, value: []const Token, important: bool }

fn kind_name(k: Kind) -> str {
    switch k {
    case .Ident:
        ret "ident"
    case .Function:
        ret "function"
    case .AtKeyword:
        ret "atKeyword"
    case .Hash:
        ret "hash"
    case .String:
        ret "string"
    case .BadString:
        ret "badString"
    case .Url:
        ret "url"
    case .BadUrl:
        ret "badUrl"
    case .Delim:
        ret "delim"
    case .Number:
        ret "number"
    case .Percentage:
        ret "percentage"
    case .Dimension:
        ret "dimension"
    case .Whitespace:
        ret "whitespace"
    case .Cdo:
        ret "cdo"
    case .Cdc:
        ret "cdc"
    case .Colon:
        ret "colon"
    case .Semicolon:
        ret "semicolon"
    case .Comma:
        ret "comma"
    case .LeftSquare:
        ret "leftSquare"
    case .RightSquare:
        ret "rightSquare"
    case .LeftParen:
        ret "leftParen"
    case .RightParen:
        ret "rightParen"
    case .LeftCurly:
        ret "leftCurly"
    case .RightCurly:
        ret "rightCurly"
    case .Eof:
        ret "eof"
    }
}

// --- code points -----------------------------------------------------------------------------------------------------

fn is_space(c: i32) -> bool { ret c == 10 || c == 9 || c == 32 }

fn is_newline_like(c: i32) -> bool { ret c == 10 || c == 12 || c == 13 }

fn is_ws(c: i32) -> bool { ret is_space(c) || c == 12 || c == 13 }

fn is_digit(c: i32) -> bool { ret c >= 48 && c <= 57 }

fn is_hex(c: i32) -> bool { ret is_digit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102) }

fn is_letter(c: i32) -> bool { ret (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }

// A name-start code point: a letter, `_`, a byte of 0x80 or more, or NUL (decoded as U+FFFD, itself non-ASCII).
fn is_name_start(c: i32) -> bool { ret is_letter(c) || c == 95 || c >= 128 || c == 0 }

fn is_name(c: i32) -> bool { ret is_name_start(c) || is_digit(c) || c == 45 }

fn hex_value(c: i32) -> i32 {
    if is_digit(c) { ret c - 48 }
    if c >= 65 && c <= 70 { ret c - 65 + 10 }
    ret c - 97 + 10
}

// --- the tokenizer ---------------------------------------------------------------------------------------------------

type Scan = struct { a: *mem.Arena, src: str, n: usize, i: usize, out: list.List[Token] }

fn cp(s: *const Scan, at: usize) -> i32 {
    if at < s.n { ret i32(s.src[at]) }
    ret -1
}

fn peek(s: *const Scan, offset: usize) -> i32 { ret cp(s, s.i + offset) }

fn plain(kind: Kind, start: usize, end: usize) -> Token {
    ret Token { kind: kind, start: start, end: end, value: "", number: 0.0f64, unit: "", integer: false, hash_id: false }
}

fn add(s: *Scan, t: Token) {
    let e = list.push[Token](&s.out, t)
}

fn add_plain(s: *Scan, kind: Kind, start: usize) {
    add(s, plain(kind, start, s.i))
}

fn add_valued(s: *Scan, kind: Kind, start: usize, value: str) {
    var t = plain(kind, start, s.i)
    t.value = value
    add(s, t)
}

// Push a code point as UTF-8 (a surrogate or an out-of-range value has already become U+FFFD).
fn push_code_point(b: *str.Builder, c: u32) {
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

// Push a source byte, NUL becoming U+FFFD.
fn push_source_byte(b: *str.Builder, c: i32) {
    if c == 0 {
        push_code_point(b, 65533u32)
    } else {
        let e = str.push_byte(b, u8(c))
    }
}

fn is_valid_escape(s: *const Scan, at: usize) -> bool {
    if cp(s, at) != 92 { ret false }
    let next = cp(s, at + 1usize)
    ret next != 10 && next != 13 && next != 12
}

fn is_ident_start_seq(s: *const Scan, at: usize) -> bool {
    let c0 = cp(s, at)
    if is_name_start(c0) { ret true }
    if c0 == 45 {
        let c1 = cp(s, at + 1usize)
        if is_name_start(c1) || c1 == 45 { ret true }
        ret is_valid_escape(s, at + 1usize)
    }
    if c0 == 92 { ret is_valid_escape(s, at) }
    ret false
}

fn starts_number(s: *const Scan, at: usize) -> bool {
    let c0 = cp(s, at)
    if c0 == 43 || c0 == 45 {
        let c1 = cp(s, at + 1usize)
        if is_digit(c1) { ret true }
        ret c1 == 46 && is_digit(cp(s, at + 2usize))
    }
    if c0 == 46 { ret is_digit(cp(s, at + 1usize)) }
    ret is_digit(c0)
}

// Consume an escape (the backslash at `i` is known valid) and answer the code point.
fn consume_escape(s: *Scan) -> u32 {
    s.i += 1usize
    let c = peek(s, 0usize)
    if is_hex(c) {
        var value = 0u32
        var count = 0i32
        while count < 6i32 && is_hex(peek(s, 0usize)) {
            value = value * 16u32 + u32(hex_value(peek(s, 0usize)))
            s.i += 1usize
            count += 1i32
        }
        if peek(s, 0usize) == 13 && peek(s, 1usize) == 10 {
            s.i += 2usize
        } else if is_ws(peek(s, 0usize)) {
            s.i += 1usize
        }
        if value == 0u32 || value > 1114111u32 || (value >= 55296u32 && value <= 57343u32) { ret 65533u32 }
        ret value
    }
    if c == -1 { ret 65533u32 }
    // An escaped literal: a multibyte lead keeps its bytes together (the caller sees the whole character).
    s.i += 1usize
    if c >= 128 {
        var code = 0u32
        var extra = 0usize
        if c >= 240 {
            code = u32(c) & 7u32
            extra = 3usize
        } else if c >= 224 {
            code = u32(c) & 15u32
            extra = 2usize
        } else if c >= 192 {
            code = u32(c) & 31u32
            extra = 1usize
        } else {
            ret 65533u32
        }
        var k = 0usize
        while k < extra && cp(s, s.i) >= 128 && cp(s, s.i) < 192 {
            code = (code << 6u32) | (u32(cp(s, s.i)) & 63u32)
            s.i += 1usize
            k += 1usize
        }
        ret code
    }
    ret u32(c)
}

fn consume_name(s: *Scan) -> str {
    let (b, e) = str.builder(s.a, 16usize)
    if e != ok { ret "" }
    var out = b
    var more = true
    while more && s.i < s.n {
        let c = peek(s, 0usize)
        if is_name(c) {
            push_source_byte(&out, c)
            s.i += 1usize
        } else if is_valid_escape(s, s.i) {
            push_code_point(&out, consume_escape(s))
        } else {
            more = false
        }
    }
    ret str.done(&out)
}

// A number: `(value, is_integer)`. The decimal text is parsed to the nearest double.
fn consume_number(s: *Scan) -> (f64, bool) {
    var is_int = true
    let (b, e) = str.builder(s.a, 16usize)
    if e != ok { ret (0.0f64, true) }
    var out = b
    let sign = peek(s, 0usize)
    if sign == 43 || sign == 45 {
        if sign == 45 { let p = str.push_byte(&out, 45u8) }
        s.i += 1usize
    }
    var digits = 0usize
    while is_digit(peek(s, 0usize)) {
        let p = str.push_byte(&out, u8(peek(s, 0usize)))
        s.i += 1usize
        digits += 1usize
    }
    if peek(s, 0usize) == 46 && is_digit(peek(s, 1usize)) {
        is_int = false
        if digits == 0usize { let z = str.push_byte(&out, 48u8) }
        let p = str.push_byte(&out, 46u8)
        s.i += 1usize
        while is_digit(peek(s, 0usize)) {
            let q = str.push_byte(&out, u8(peek(s, 0usize)))
            s.i += 1usize
        }
    }
    let marker = peek(s, 0usize)
    if marker == 69 || marker == 101 {
        var j = s.i + 1usize
        if cp(s, j) == 43 || cp(s, j) == 45 { j += 1usize }
        if is_digit(cp(s, j)) {
            is_int = false
            let p = str.push_byte(&out, 101u8)
            s.i += 1usize
            if peek(s, 0usize) == 45 {
                let m = str.push_byte(&out, 45u8)
                s.i += 1usize
            } else if peek(s, 0usize) == 43 {
                s.i += 1usize
            }
            while is_digit(peek(s, 0usize)) {
                let q = str.push_byte(&out, u8(peek(s, 0usize)))
                s.i += 1usize
            }
        }
    }
    let text = str.done(&out)
    let (value, parse_error) = str.parse_f64(text)
    if parse_error != ok { ret (0.0f64, is_int) }
    ret (value, is_int)
}

fn consume_numeric(s: *Scan) {
    let start = s.i
    let (value, is_int) = consume_number(s)
    if is_ident_start_seq(s, s.i) {
        let unit = consume_name(s)
        var t = plain(.Dimension, start, s.i)
        t.number = value
        t.unit = unit
        t.integer = is_int
        add(s, t)
        ret
    }
    if peek(s, 0usize) == 37 {
        s.i += 1usize
        var t = plain(.Percentage, start, s.i)
        t.number = value
        t.unit = "%"
        t.integer = is_int
        add(s, t)
        ret
    }
    var t = plain(.Number, start, s.i)
    t.number = value
    t.integer = is_int
    add(s, t)
}

fn consume_bad_url_remnants(s: *Scan, start: usize) {
    var more = true
    while more && s.i < s.n {
        let c = peek(s, 0usize)
        if c == 41 {
            s.i += 1usize
            more = false
        } else if is_valid_escape(s, s.i) {
            let ignored = consume_escape(s)
        } else {
            s.i += 1usize
        }
    }
    add_plain(s, .BadUrl, start)
}

fn consume_url(s: *Scan, start: usize) {
    while s.i < s.n && is_ws(peek(s, 0usize)) { s.i += 1usize }
    let (b, e) = str.builder(s.a, 16usize)
    if e != ok { ret }
    var out = b
    while s.i < s.n {
        let c = peek(s, 0usize)
        if c == 41 {
            s.i += 1usize
            add_valued(s, .Url, start, str.done(&out))
            ret
        }
        if is_ws(c) {
            while s.i < s.n && is_ws(peek(s, 0usize)) { s.i += 1usize }
            if peek(s, 0usize) == 41 {
                s.i += 1usize
                add_valued(s, .Url, start, str.done(&out))
                ret
            }
            consume_bad_url_remnants(s, start)
            ret
        }
        if c == 34 || c == 39 || c == 40 {
            consume_bad_url_remnants(s, start)
            ret
        }
        if (c >= 1 && c <= 8) || c == 11 || (c >= 14 && c <= 31) || c == 127 {
            consume_bad_url_remnants(s, start)
            ret
        }
        if c == 92 {
            if is_valid_escape(s, s.i) {
                push_code_point(&out, consume_escape(s))
            } else {
                consume_bad_url_remnants(s, start)
                ret
            }
        } else {
            push_source_byte(&out, c)
            s.i += 1usize
        }
    }
    add_valued(s, .Url, start, str.done(&out))
}

fn consume_ident_like(s: *Scan) {
    let start = s.i
    let name = consume_name(s)
    if name.len == 3usize && peek(s, 0usize) == 40 && lower_eq(name, "url") {
        s.i += 1usize
        var j = s.i
        while j < s.n && is_ws(cp(s, j)) { j += 1usize }
        let q = cp(s, j)
        if q == 34 || q == 39 {
            add_valued(s, .Function, start, name)
            ret
        }
        consume_url(s, start)
        ret
    }
    if peek(s, 0usize) == 40 {
        s.i += 1usize
        add_valued(s, .Function, start, name)
        ret
    }
    add_valued(s, .Ident, start, name)
}

fn lower_eq(s: str, lower: str) -> bool {
    if s.len != lower.len { ret false }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c != lower[at] { ret false }
        at += 1usize
    }
    ret true
}

fn consume_string(s: *Scan, quote: i32) {
    let start = s.i
    s.i += 1usize
    let (b, e) = str.builder(s.a, 16usize)
    if e != ok { ret }
    var out = b
    while s.i < s.n {
        let c = peek(s, 0usize)
        if c == quote {
            s.i += 1usize
            add_valued(s, .String, start, str.done(&out))
            ret
        }
        if is_newline_like(c) {
            add_valued(s, .BadString, start, str.done(&out))
            ret
        }
        if c == 92 {
            let next = peek(s, 1usize)
            if next == -1 {
                s.i += 1usize
            } else if is_newline_like(next) {
                s.i += 2usize
            } else {
                push_code_point(&out, consume_escape(s))
            }
        } else {
            push_source_byte(&out, c)
            s.i += 1usize
        }
    }
    add_valued(s, .String, start, str.done(&out))
}

fn consume_hash(s: *Scan) {
    let start = s.i
    s.i += 1usize
    let next = peek(s, 0usize)
    if is_name(next) || is_valid_escape(s, s.i) {
        let is_id = is_ident_start_seq(s, s.i)
        let name = consume_name(s)
        var t = plain(.Hash, start, s.i)
        t.value = name
        t.hash_id = is_id
        add(s, t)
    } else {
        add_valued(s, .Delim, start, "#")
    }
}

fn delim_of(c: i32, s: *Scan) -> str {
    let (b, e) = str.builder(s.a, 4usize)
    if e != ok { ret "" }
    var out = b
    push_source_byte(&out, c)
    ret str.done(&out)
}

fn consume_token(s: *Scan) {
    let start = s.i
    let c = peek(s, 0usize)
    if c == 47 && peek(s, 1usize) == 42 {
        s.i += 2usize
        while s.i < s.n {
            if peek(s, 0usize) == 42 && peek(s, 1usize) == 47 {
                s.i += 2usize
                ret
            }
            s.i += 1usize
        }
        ret
    }
    if is_ws(c) {
        while s.i < s.n && is_ws(peek(s, 0usize)) { s.i += 1usize }
        add_plain(s, .Whitespace, start)
        ret
    }
    if c == 34 || c == 39 {
        consume_string(s, c)
        ret
    }
    if c == 35 {
        consume_hash(s)
        ret
    }
    if c == 40 {
        s.i += 1usize
        add_plain(s, .LeftParen, start)
        ret
    }
    if c == 41 {
        s.i += 1usize
        add_plain(s, .RightParen, start)
        ret
    }
    if c == 91 {
        s.i += 1usize
        add_plain(s, .LeftSquare, start)
        ret
    }
    if c == 93 {
        s.i += 1usize
        add_plain(s, .RightSquare, start)
        ret
    }
    if c == 123 {
        s.i += 1usize
        add_plain(s, .LeftCurly, start)
        ret
    }
    if c == 125 {
        s.i += 1usize
        add_plain(s, .RightCurly, start)
        ret
    }
    if c == 44 {
        s.i += 1usize
        add_plain(s, .Comma, start)
        ret
    }
    if c == 58 {
        s.i += 1usize
        add_plain(s, .Colon, start)
        ret
    }
    if c == 59 {
        s.i += 1usize
        add_plain(s, .Semicolon, start)
        ret
    }
    if c == 43 {
        if starts_number(s, s.i) {
            consume_numeric(s)
        } else {
            s.i += 1usize
            add_valued(s, .Delim, start, "+")
        }
        ret
    }
    if c == 45 {
        if starts_number(s, s.i) {
            consume_numeric(s)
        } else if peek(s, 1usize) == 45 && peek(s, 2usize) == 62 {
            s.i += 3usize
            add_plain(s, .Cdc, start)
        } else if is_ident_start_seq(s, s.i) {
            consume_ident_like(s)
        } else {
            s.i += 1usize
            add_valued(s, .Delim, start, "-")
        }
        ret
    }
    if c == 46 {
        if starts_number(s, s.i) {
            consume_numeric(s)
        } else {
            s.i += 1usize
            add_valued(s, .Delim, start, ".")
        }
        ret
    }
    if c == 60 {
        if peek(s, 1usize) == 33 && peek(s, 2usize) == 45 && peek(s, 3usize) == 45 {
            s.i += 4usize
            add_plain(s, .Cdo, start)
        } else {
            s.i += 1usize
            add_valued(s, .Delim, start, "<")
        }
        ret
    }
    if c == 64 {
        if is_ident_start_seq(s, s.i + 1usize) {
            s.i += 1usize
            let name = consume_name(s)
            add_valued(s, .AtKeyword, start, name)
        } else {
            s.i += 1usize
            add_valued(s, .Delim, start, "@")
        }
        ret
    }
    if c == 92 {
        if is_valid_escape(s, s.i) {
            consume_ident_like(s)
        } else {
            s.i += 1usize
            add_valued(s, .Delim, start, "\\")
        }
        ret
    }
    if is_digit(c) {
        consume_numeric(s)
        ret
    }
    if is_name_start(c) {
        consume_ident_like(s)
        ret
    }
    s.i += 1usize
    add_valued(s, .Delim, start, delim_of(c, s))
}

// Tokenize `input`; the list ends in an `Eof` token.
fn tokenize(a: *mem.Arena, input: str) -> ([]const Token, err) {
    let (out, e) = list.init[Token](a, 64usize)
    if e != ok { ret (zero, e) }
    var s = Scan { a: a, src: input, n: input.len, i: 0usize, out: out }
    while s.i < s.n { consume_token(&s) }
    add(&s, plain(.Eof, s.n, s.n))
    ret (list.slice_const[Token](&s.out), ok)
}

// --- the grammar -----------------------------------------------------------------------------------------------------

type Grammar = struct { a: *mem.Arena, t: []const Token, pos: usize }

fn closer_for(k: Kind) -> Kind {
    if k == .LeftParen { ret .RightParen }
    if k == .LeftSquare { ret .RightSquare }
    ret .RightCurly
}

fn is_opener(k: Kind) -> bool { ret k == .LeftCurly || k == .LeftParen || k == .LeftSquare }

fn cur(g: *const Grammar) -> Token {
    if g.pos < g.t.len { ret g.t[g.pos] }
    ret plain(.Eof, 0usize, 0usize)
}

fn at_eof(g: *const Grammar) -> bool { ret cur(g).kind == .Eof }

fn push_token(l: *list.List[Token], t: Token) {
    let e = list.push[Token](l, t)
}

fn new_tokens(a: *mem.Arena) -> list.List[Token] {
    let (l, e) = list.init[Token](a, 8usize)
    if e != ok { ret list.List[Token] { items: zero, len: 0usize, arena: a } }
    ret l
}

// Drop leading and trailing whitespace tokens.
fn trim(toks: []const Token) -> []const Token {
    var start = 0usize
    var end = toks.len
    while start < end && toks[start].kind == .Whitespace { start += 1usize }
    while end > start && toks[end - 1usize].kind == .Whitespace { end -= 1usize }
    ret toks[start..end]
}

// Append a balanced bracket group (opener to its closer, nested groups included) and step past it.
fn append_balanced(g: *Grammar, out: *list.List[Token]) {
    var stack = new_tokens(g.a)
    push_token(&stack, plain(closer_for(cur(g).kind), 0usize, 0usize))
    push_token(out, cur(g))
    g.pos += 1usize
    while !at_eof(g) && stack.len > 0usize {
        let t = cur(g)
        if is_opener(t.kind) {
            push_token(&stack, plain(closer_for(t.kind), 0usize, 0usize))
        } else if t.kind == stack.items[stack.len - 1usize].kind {
            stack.len -= 1usize
        }
        push_token(out, t)
        g.pos += 1usize
    }
}

// The block at the cursor (an opening bracket): its inner tokens, the cursor left past the closer or at the end.
fn consume_simple_block(g: *Grammar) -> Block {
    let open = cur(g).kind
    let closer = closer_for(open)
    g.pos += 1usize
    var inner = new_tokens(g.a)
    var stack = new_tokens(g.a)
    while !at_eof(g) {
        let t = cur(g)
        if stack.len == 0usize && t.kind == closer {
            g.pos += 1usize
            ret Block { open: open, inner: list.slice_const[Token](&inner) }
        }
        if is_opener(t.kind) {
            push_token(&stack, plain(closer_for(t.kind), 0usize, 0usize))
        } else if stack.len > 0usize && t.kind == stack.items[stack.len - 1usize].kind {
            stack.len -= 1usize
        }
        push_token(&inner, t)
        g.pos += 1usize
    }
    ret Block { open: open, inner: list.slice_const[Token](&inner) }
}

fn lower_text(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn empty_block() -> Block { ret Block { open: .LeftCurly, inner: zero } }

fn consume_at_rule(g: *Grammar) -> Rule {
    let name = lower_text(g.a, cur(g).value)
    g.pos += 1usize
    var prelude = new_tokens(g.a)
    while !at_eof(g) {
        let t = cur(g)
        if t.kind == .Semicolon {
            g.pos += 1usize
            ret Rule { at: true, name: name, prelude: trim(list.slice_const[Token](&prelude)), has_block: false, block: empty_block() }
        }
        if t.kind == .LeftCurly {
            let block = consume_simple_block(g)
            ret Rule { at: true, name: name, prelude: trim(list.slice_const[Token](&prelude)), has_block: true, block: block }
        }
        if t.kind == .LeftParen || t.kind == .LeftSquare {
            append_balanced(g, &prelude)
        } else {
            push_token(&prelude, t)
            g.pos += 1usize
        }
    }
    ret Rule { at: true, name: name, prelude: trim(list.slice_const[Token](&prelude)), has_block: false, block: empty_block() }
}

// A qualified rule at the cursor, absent when the input ends before its block.
fn consume_qualified_rule(g: *Grammar) -> (Rule, bool) {
    var prelude = new_tokens(g.a)
    while !at_eof(g) {
        let t = cur(g)
        if t.kind == .LeftCurly {
            let block = consume_simple_block(g)
            ret (Rule { at: false, name: "", prelude: trim(list.slice_const[Token](&prelude)), has_block: true, block: block }, true)
        }
        if t.kind == .LeftParen || t.kind == .LeftSquare {
            append_balanced(g, &prelude)
        } else {
            push_token(&prelude, t)
            g.pos += 1usize
        }
    }
    ret (Rule { at: false, name: "", prelude: zero, has_block: false, block: empty_block() }, false)
}

// Parse a token stream into rules; `top_level` discards `<!--` and `-->`.
fn parse_rules(a: *mem.Arena, tokens: []const Token, top_level: bool) -> ([]const Rule, err) {
    var g = Grammar { a: a, t: tokens, pos: 0usize }
    let (made, e) = list.init[Rule](a, 8usize)
    if e != ok { ret (zero, e) }
    var rules = made
    while !at_eof(&g) {
        let t = cur(&g)
        if t.kind == .Whitespace {
            g.pos += 1usize
        } else if t.kind == .Cdo || t.kind == .Cdc {
            if top_level {
                g.pos += 1usize
            } else {
                let (q, have) = consume_qualified_rule(&g)
                if have { try list.push[Rule](&rules, q) }
            }
        } else if t.kind == .AtKeyword {
            try list.push[Rule](&rules, consume_at_rule(&g))
        } else {
            let (q, have) = consume_qualified_rule(&g)
            if have { try list.push[Rule](&rules, q) }
        }
    }
    ret (list.slice_const[Rule](&rules), ok)
}

// One declaration out of its tokens: `name : value [! important]`, absent when it is not one.
fn parse_one_declaration(g: *Grammar, toks: []const Token) -> (Declaration, bool) {
    let t = trim(toks)
    let none = Declaration { name: "", value: zero, important: false }
    if t.len == 0usize || t[0].kind != .Ident { ret (none, false) }
    var i = 1usize
    while i < t.len && t[i].kind == .Whitespace { i += 1usize }
    if i >= t.len || t[i].kind != .Colon { ret (none, false) }
    i += 1usize
    var value = trim(t[i..])
    var important = false
    if value.len > 0usize && value[value.len - 1usize].kind == .Ident && lower_eq(value[value.len - 1usize].value, "important") {
        var j = i64(value.len) - 2i64
        while j >= 0i64 && value[usize(j)].kind == .Whitespace { j -= 1i64 }
        if j >= 0i64 && value[usize(j)].kind == .Delim && str.eq(value[usize(j)].value, "!") {
            important = true
            value = trim(value[0usize..usize(j)])
        }
    }
    ret (Declaration { name: t[0].value, value: value, important: important }, true)
}

// A declaration list (a block's contents, an inline `style`, a keyframe stop); nested rules are skipped.
fn parse_declarations(a: *mem.Arena, tokens: []const Token) -> ([]const Declaration, err) {
    var g = Grammar { a: a, t: tokens, pos: 0usize }
    let (made, e) = list.init[Declaration](a, 8usize)
    if e != ok { ret (zero, e) }
    var decls = made
    while !at_eof(&g) {
        let t = cur(&g)
        if t.kind == .Whitespace || t.kind == .Semicolon {
            g.pos += 1usize
        } else if t.kind == .AtKeyword {
            let skipped = consume_at_rule(&g)
        } else {
            var temp = new_tokens(a)
            var nested = false
            var more = true
            while more && !at_eof(&g) && cur(&g).kind != .Semicolon {
                let c = cur(&g)
                if c.kind == .LeftCurly {
                    let skipped = consume_simple_block(&g)
                    nested = true
                    more = false
                } else if c.kind == .LeftParen || c.kind == .LeftSquare {
                    append_balanced(&g, &temp)
                } else {
                    push_token(&temp, c)
                    g.pos += 1usize
                }
            }
            if cur(&g).kind == .Semicolon { g.pos += 1usize }
            if !nested {
                let (d, have) = parse_one_declaration(&g, list.slice_const[Token](&temp))
                if have { try list.push[Declaration](&decls, d) }
            }
        }
    }
    ret (list.slice_const[Declaration](&decls), ok)
}

// The source text of a token range (the empty text for none).
fn raw_text(source: str, tokens: []const Token) -> str {
    if tokens.len == 0usize { ret "" }
    ret source[tokens[0].start..tokens[tokens.len - 1usize].end]
}
