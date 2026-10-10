// A read-only HCL2 parser (L041), enough of the native syntax to read Terraform: a body of attributes and blocks, with
// the expression forms the language has -- null, booleans, numbers, quoted strings and heredocs as templates with
// `${ }` interpolations and `%{ }` directives, tuples, objects, `for` expressions, function calls (with a namespace and a
// spread final argument), variables, traversals (attributes, `.0` legacy indexes, `[expr]` indexes, `.*` and `[*]`
// splats), parentheses, `? :` conditionals and unary and binary operators. It follows `hcl-rs` where that differs from
// the specification: a chain of binary operators nests to the right without precedence, a minus before a number literal
// is the negative number, and a heredoc's indent is stripped when it is read.
//
// The parser answers the tree and refuses what it cannot read (`Invalid`); it does not write HCL.
//
// Memory: the arena is retained; every tree and string lives in it.

use e.data.list as list
use e.mem
use e.str

error Invalid
error TooDeep

type Kind = enum u8 { Null, Bool, Number, String, Array, Object, Template, Variable, Traversal, FuncCall, Parens, Conditional, Unary, Binary, For }

type OpKind = enum u8 { GetAttr, LegacyIndex, Index, AttrSplat, FullSplat }

type PartKind = enum u8 { Literal, Interpolation, Directive }

// A traversal operator: `name` is the attribute or the legacy index digits; an `Index` carries its expression in `index`.
type Operator = struct { kind: OpKind, name: str, index: []const Expr }

// An object key: a bare identifier, or any expression (a quoted string, a parenthesised expression, a number).
type Key = struct { identifier: bool, name: str, expr: []const Expr }

// A template element: literal text, an interpolated expression, or a directive (read, not interpreted).
type Part = struct { kind: PartKind, text: str, expr: []const Expr }

// `text` is a string's value, a name, an operator spelling or a number's lexeme; `items` the operands (array items,
// call arguments, the three of a conditional, the one of a unary or parenthesis, the two of a binary, the root of a
// traversal); `flag` a boolean's value or a call's spread; `names` a call's namespace.
type Expr = struct { kind: Kind, text: str, flag: bool, items: []const Expr, keys: []const Key, ops: []const Operator, parts: []const Part, names: []const str }

// An attribute (`value` has one expression) or a block (`labels` and `body`).
type Item = struct { is_block: bool, name: str, labels: []const str, value: []const Expr, body: []const Item }

type Parser = struct { a: *mem.Arena, src: str, at: usize, depth: usize, nest: usize }

fn blank(kind: Kind) -> Expr {
    ret Expr { kind: kind, text: "", flag: false, items: zero, keys: zero, ops: zero, parts: zero, names: zero }
}

fn peek(p: *const Parser) -> u8 {
    if p.at < p.src.len { ret p.src[p.at] }
    ret 0u8
}

fn peek_at(p: *const Parser, offset: usize) -> u8 {
    if p.at + offset < p.src.len { ret p.src[p.at + offset] }
    ret 0u8
}

fn at_end(p: *const Parser) -> bool { ret p.at >= p.src.len }

fn is_ident_start(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c >= 128u8 }

fn is_ident_char(c: u8) -> bool { ret is_ident_start(c) || (c >= 48u8 && c <= 57u8) || c == 45u8 }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// Skip spaces, tabs, carriage returns and comments; newlines too when `newlines`.
fn skip(p: *Parser, newlines: bool) {
    var more = true
    while more && !at_end(p) {
        let c = peek(p)
        if c == 32u8 || c == 9u8 || c == 13u8 {
            p.at += 1usize
        } else if c == 10u8 {
            if newlines { p.at += 1usize } else { more = false }
        } else if c == 35u8 || (c == 47u8 && peek_at(p, 1usize) == 47u8) {
            while !at_end(p) && peek(p) != 10u8 { p.at += 1usize }
        } else if c == 47u8 && peek_at(p, 1usize) == 42u8 {
            p.at += 2usize
            var closed = false
            while !at_end(p) && !closed {
                if peek(p) == 42u8 && peek_at(p, 1usize) == 47u8 {
                    p.at += 2usize
                    closed = true
                } else {
                    p.at += 1usize
                }
            }
        } else {
            more = false
        }
    }
}

fn identifier(p: *Parser) -> (str, bool) {
    if !is_ident_start(peek(p)) { ret ("", false) }
    let start = p.at
    while !at_end(p) && is_ident_char(peek(p)) { p.at += 1usize }
    ret (p.src[start..p.at], true)
}

fn expect(p: *Parser, c: u8) -> bool {
    if peek(p) != c { ret false }
    p.at += 1usize
    ret true
}

fn new_exprs(a: *mem.Arena) -> list.List[Expr] {
    let (l, e) = list.init[Expr](a, 4usize)
    if e != ok { ret list.List[Expr] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn one(a: *mem.Arena, e: Expr) -> []const Expr {
    let (out, err_alloc) = mem.alloc[Expr](a, 1usize)
    if err_alloc != ok { ret zero }
    out[0] = e
    ret out[0usize..1usize]
}

fn push_byte(b: *list.List[u8], c: u8) {
    let e = list.push[u8](b, c)
}

fn new_bytes(a: *mem.Arena) -> list.List[u8] {
    let (l, e) = list.init[u8](a, 16usize)
    if e != ok { ret list.List[u8] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn bytes_text(b: *const list.List[u8]) -> str { ret list.slice_const[u8](b) }

fn push_text(b: *list.List[u8], t: str) {
    var at = 0usize
    while at < t.len {
        push_byte(b, t[at])
        at += 1usize
    }
}

fn push_code_point(b: *list.List[u8], c: u32) {
    if c < 128u32 {
        push_byte(b, u8(c))
    } else if c < 2048u32 {
        push_byte(b, u8(192u32 | (c >> 6u32)))
        push_byte(b, u8(128u32 | (c & 63u32)))
    } else if c < 65536u32 {
        push_byte(b, u8(224u32 | (c >> 12u32)))
        push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        push_byte(b, u8(128u32 | (c & 63u32)))
    } else {
        push_byte(b, u8(240u32 | (c >> 18u32)))
        push_byte(b, u8(128u32 | ((c >> 12u32) & 63u32)))
        push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        push_byte(b, u8(128u32 | (c & 63u32)))
    }
}

fn hex_value(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i64(c - 97u8) + 10i64 }
    if c >= 65u8 && c <= 70u8 { ret i64(c - 65u8) + 10i64 }
    ret -1i64
}

// --- templates ------------------------------------------------------------------------------------------------------

type Template = struct { good: bool, parts: []const Part }

fn new_parts(a: *mem.Arena) -> list.List[Part] {
    let (l, e) = list.init[Part](a, 4usize)
    if e != ok { ret list.List[Part] { items: zero, len: 0usize, arena: a } }
    ret l
}

// Read a template body up to `close` (a `"` for a quoted string, 0 for the end of the source): literal text with the
// escapes of a quoted string when `quoted`, `${ expr }` interpolations and `%{ ... }` directives.
fn parse_template(p: *Parser, quoted: bool) -> Template {
    var parts = new_parts(p.a)
    var lit = new_bytes(p.a)
    var have_lit = false
    var done = false
    var ok_parse = true
    while !done && ok_parse {
        if at_end(p) {
            if quoted { ok_parse = false }
            done = true
        } else {
            let c = peek(p)
            if quoted && c == 34u8 {
                done = true
            } else if quoted && c == 10u8 {
                ok_parse = false
            } else if c == 36u8 && peek_at(p, 1usize) == 36u8 && peek_at(p, 2usize) == 123u8 {
                // `$${` is a literal `${`
                push_byte(&lit, 36u8)
                push_byte(&lit, 123u8)
                have_lit = true
                p.at += 3usize
            } else if c == 37u8 && peek_at(p, 1usize) == 37u8 && peek_at(p, 2usize) == 123u8 {
                push_byte(&lit, 37u8)
                push_byte(&lit, 123u8)
                have_lit = true
                p.at += 3usize
            } else if c == 36u8 && peek_at(p, 1usize) == 123u8 {
                if have_lit {
                    let pushed = list.push[Part](&parts, Part { kind: .Literal, text: bytes_text(&lit), expr: zero })
                    lit = new_bytes(p.a)
                    have_lit = false
                }
                p.at += 2usize
                if peek(p) == 126u8 { p.at += 1usize }
                p.nest += 1usize
                skip(p, true)
                let (expr, good) = parse_expression(p)
                p.nest -= 1usize
                if !good { ok_parse = false } else {
                    skip(p, true)
                    if peek(p) == 126u8 { p.at += 1usize }
                    if !expect(p, 125u8) {
                        ok_parse = false
                    } else {
                        let pushed = list.push[Part](&parts, Part { kind: .Interpolation, text: "", expr: one(p.a, expr) })
                    }
                }
            } else if c == 37u8 && peek_at(p, 1usize) == 123u8 {
                if have_lit {
                    let pushed = list.push[Part](&parts, Part { kind: .Literal, text: bytes_text(&lit), expr: zero })
                    lit = new_bytes(p.a)
                    have_lit = false
                }
                // a directive: read to the closing brace, nesting counted
                var depth = 0i64
                let start = p.at
                var closed = false
                while !at_end(p) && !closed {
                    if peek(p) == 123u8 {
                        depth += 1i64
                    } else if peek(p) == 125u8 {
                        depth -= 1i64
                        if depth == 0i64 { closed = true }
                    }
                    p.at += 1usize
                }
                if !closed { ok_parse = false } else {
                    let pushed = list.push[Part](&parts, Part { kind: .Directive, text: p.src[start..p.at], expr: zero })
                }
            } else if quoted && c == 92u8 {
                p.at += 1usize
                let n = peek(p)
                p.at += 1usize
                if n == 110u8 {
                    push_byte(&lit, 10u8)
                } else if n == 114u8 {
                    push_byte(&lit, 13u8)
                } else if n == 116u8 {
                    push_byte(&lit, 9u8)
                } else if n == 34u8 {
                    push_byte(&lit, 34u8)
                } else if n == 92u8 {
                    push_byte(&lit, 92u8)
                } else if n == 117u8 || n == 85u8 {
                    var count = 4usize
                    if n == 85u8 { count = 8usize }
                    var v = 0i64
                    var k = 0usize
                    while k < count {
                        let h = hex_value(peek(p))
                        if h < 0i64 {
                            ok_parse = false
                            k = count
                        } else {
                            v = v * 16i64 + h
                            p.at += 1usize
                            k += 1usize
                        }
                    }
                    if ok_parse { push_code_point(&lit, u32(v)) }
                } else {
                    ok_parse = false
                }
                have_lit = true
            } else {
                push_byte(&lit, c)
                have_lit = true
                p.at += 1usize
            }
        }
    }
    if !ok_parse { ret Template { good: false, parts: zero } }
    if have_lit || parts.len == 0usize {
        let pushed = list.push[Part](&parts, Part { kind: .Literal, text: bytes_text(&lit), expr: zero })
    }
    ret Template { good: true, parts: list.slice_const[Part](&parts) }
}

// A template as an expression: a plain string when it has no interpolation or directive, else a template.
fn template_expr(parts: []const Part) -> Expr {
    var plain = true
    var at = 0usize
    while at < parts.len {
        if parts[at].kind != .Literal { plain = false }
        at += 1usize
    }
    if plain {
        var e = blank(.String)
        if parts.len > 0usize { e.text = parts[0].text }
        ret e
    }
    var e = blank(.Template)
    e.parts = parts
    ret e
}

fn parse_quoted(p: *Parser) -> (Expr, bool) {
    // the opening quote is at `at`
    p.at += 1usize
    let t = parse_template(p, true)
    if !t.good { ret (blank(.Null), false) }
    if !expect(p, 34u8) { ret (blank(.Null), false) }
    ret (template_expr(t.parts), true)
}

// A heredoc `<<ID` or `<<-ID`: its template, the indent stripped for `<<-`.
fn parse_heredoc(p: *Parser) -> (Expr, bool) {
    p.at += 2usize
    var strip = false
    if peek(p) == 45u8 {
        strip = true
        p.at += 1usize
    }
    let (delim, good) = identifier(p)
    if !good { ret (blank(.Null), false) }
    // to the end of the line
    while !at_end(p) && peek(p) != 10u8 { p.at += 1usize }
    if at_end(p) { ret (blank(.Null), false) }
    p.at += 1usize
    // collect the lines up to the delimiter line
    let (made, e) = list.init[str](p.a, 8usize)
    if e != ok { ret (blank(.Null), false) }
    var lines = made
    var found = false
    while !at_end(p) && !found {
        let line_start = p.at
        while !at_end(p) && peek(p) != 10u8 { p.at += 1usize }
        var line = p.src[line_start..p.at]
        if str.ends_with(line, "\r") { line = line[0usize..line.len - 1usize] }
        var lead = 0usize
        while lead < line.len && (line[lead] == 32u8 || line[lead] == 9u8) { lead += 1usize }
        let rest = line[lead..]
        if str.starts_with(rest, delim) && (rest.len == delim.len || !is_ident_char(rest[delim.len])) {
            found = true
            // the rest of the line (a closing parenthesis, a comma) is read on as source
            p.at = line_start + lead + delim.len
        } else {
            let pushed = list.push[str](&lines, line)
            if !at_end(p) { p.at += 1usize }
        }
    }
    if !found { ret (blank(.Null), false) }
    var indent = 0usize
    if strip {
        var first = true
        var i = 0usize
        while i < lines.len {
            let l = lines.items[i]
            var n = 0usize
            while n < l.len && (l[n] == 32u8 || l[n] == 9u8) { n += 1usize }
            if n < l.len {
                if first || n < indent { indent = n }
                first = false
            }
            i += 1usize
        }
    }
    var body = new_bytes(p.a)
    var i = 0usize
    while i < lines.len {
        var l = lines.items[i]
        if strip && indent > 0usize {
            var n = 0usize
            while n < l.len && n < indent && (l[n] == 32u8 || l[n] == 9u8) { n += 1usize }
            l = l[n..]
        }
        push_text(&body, l)
        push_byte(&body, 10u8)
        i += 1usize
    }
    let text = bytes_text(&body)
    var inner = Parser { a: p.a, src: text, at: 0usize, depth: p.depth, nest: 0usize }
    let t = parse_template(&inner, false)
    if !t.good { ret (blank(.Null), false) }
    ret (template_expr(t.parts), true)
}

// --- expressions ----------------------------------------------------------------------------------------------------

fn parse_number(p: *Parser, negative: bool) -> (Expr, bool) {
    let start = p.at
    while !at_end(p) && is_digit(peek(p)) { p.at += 1usize }
    if peek(p) == 46u8 && is_digit(peek_at(p, 1usize)) {
        p.at += 1usize
        while !at_end(p) && is_digit(peek(p)) { p.at += 1usize }
    }
    if peek(p) == 101u8 || peek(p) == 69u8 {
        var j = 1usize
        if peek_at(p, j) == 43u8 || peek_at(p, j) == 45u8 { j += 1usize }
        if is_digit(peek_at(p, j)) {
            p.at += j
            while !at_end(p) && is_digit(peek(p)) { p.at += 1usize }
        }
    }
    var e = blank(.Number)
    if negative { e.text = cat2(p.a, "-", p.src[start..p.at]) } else { e.text = p.src[start..p.at] }
    ret (e, true)
}

fn cat2(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

// A `for` expression: only its end is needed, so its parts are parsed and dropped.
fn parse_for(p: *Parser, object: bool) -> (Expr, bool) {
    // `for` has been seen at `at`
    p.at += 3usize
    skip(p, true)
    let (first, ok_first) = identifier(p)
    if !ok_first { ret (blank(.Null), false) }
    skip(p, true)
    if peek(p) == 44u8 {
        p.at += 1usize
        skip(p, true)
        let (second, ok_second) = identifier(p)
        if !ok_second { ret (blank(.Null), false) }
        skip(p, true)
    }
    if !(peek(p) == 105u8 && peek_at(p, 1usize) == 110u8) { ret (blank(.Null), false) }
    p.at += 2usize
    skip(p, true)
    let (coll, ok_coll) = parse_expression(p)
    if !ok_coll { ret (blank(.Null), false) }
    skip(p, true)
    if !expect(p, 58u8) { ret (blank(.Null), false) }
    skip(p, true)
    let (value, ok_value) = parse_expression(p)
    if !ok_value { ret (blank(.Null), false) }
    skip(p, true)
    if object && peek(p) == 61u8 && peek_at(p, 1usize) == 62u8 {
        p.at += 2usize
        skip(p, true)
        let (v2, ok_v2) = parse_expression(p)
        if !ok_v2 { ret (blank(.Null), false) }
        skip(p, true)
        if peek(p) == 46u8 && peek_at(p, 1usize) == 46u8 && peek_at(p, 2usize) == 46u8 {
            p.at += 3usize
            skip(p, true)
        }
    }
    if peek(p) == 105u8 && peek_at(p, 1usize) == 102u8 && !is_ident_char(peek_at(p, 2usize)) {
        p.at += 2usize
        skip(p, true)
        let (cond, ok_cond) = parse_expression(p)
        if !ok_cond { ret (blank(.Null), false) }
        skip(p, true)
    }
    ret (blank(.For), true)
}

fn is_for(p: *const Parser) -> bool {
    var j = p.at
    while j < p.src.len && (p.src[j] == 32u8 || p.src[j] == 9u8 || p.src[j] == 10u8 || p.src[j] == 13u8) { j += 1usize }
    ret j + 3usize <= p.src.len && str.eq(p.src[j..j + 3usize], "for") && (j + 3usize == p.src.len || !is_ident_char(p.src[j + 3usize]))
}

fn parse_array(p: *Parser) -> (Expr, bool) {
    p.at += 1usize
    p.nest += 1usize
    skip(p, true)
    if is_for(p) {
        skip(p, true)
        let (f, good) = parse_for(p, false)
        p.nest -= 1usize
        if !good || !expect(p, 93u8) { ret (blank(.Null), false) }
        ret (f, true)
    }
    var items = new_exprs(p.a)
    var more = true
    while more {
        skip(p, true)
        if peek(p) == 93u8 {
            p.at += 1usize
            more = false
        } else {
            let (item, good) = parse_expression(p)
            if !good {
                p.nest -= 1usize
                ret (blank(.Null), false)
            }
            let pushed = list.push[Expr](&items, item)
            skip(p, true)
            if peek(p) == 44u8 {
                p.at += 1usize
            } else if peek(p) != 93u8 {
                p.nest -= 1usize
                ret (blank(.Null), false)
            }
        }
    }
    p.nest -= 1usize
    var e = blank(.Array)
    e.items = list.slice_const[Expr](&items)
    ret (e, true)
}

fn new_keys(a: *mem.Arena) -> list.List[Key] {
    let (l, e) = list.init[Key](a, 4usize)
    if e != ok { ret list.List[Key] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn parse_object(p: *Parser) -> (Expr, bool) {
    p.at += 1usize
    p.nest += 1usize
    skip(p, true)
    if is_for(p) {
        let (f, good) = parse_for(p, true)
        p.nest -= 1usize
        if !good || !expect(p, 125u8) { ret (blank(.Null), false) }
        ret (f, true)
    }
    var keys = new_keys(p.a)
    var values = new_exprs(p.a)
    var more = true
    while more {
        skip(p, true)
        if peek(p) == 125u8 {
            p.at += 1usize
            more = false
        } else {
            // a key: a bare identifier followed by `=` or `:`, else an expression
            var key = Key { identifier: false, name: "", expr: zero }
            let save = p.at
            let (id, have_id) = identifier(p)
            var used = false
            if have_id {
                skip(p, false)
                let sep = peek(p)
                if (sep == 61u8 && peek_at(p, 1usize) != 61u8) || sep == 58u8 {
                    key = Key { identifier: true, name: id, expr: zero }
                    used = true
                }
            }
            if !used {
                p.at = save
                let (k, good) = parse_expression(p)
                if !good {
                    p.nest -= 1usize
                    ret (blank(.Null), false)
                }
                key = Key { identifier: false, name: "", expr: one(p.a, k) }
            }
            skip(p, true)
            if !(peek(p) == 61u8 || peek(p) == 58u8) {
                p.nest -= 1usize
                ret (blank(.Null), false)
            }
            p.at += 1usize
            skip(p, true)
            let (v, ok_v) = parse_expression(p)
            if !ok_v {
                p.nest -= 1usize
                ret (blank(.Null), false)
            }
            let pk = list.push[Key](&keys, key)
            let pv = list.push[Expr](&values, v)
            skip(p, true)
            if peek(p) == 44u8 { p.at += 1usize }
        }
    }
    p.nest -= 1usize
    var e = blank(.Object)
    e.keys = list.slice_const[Key](&keys)
    e.items = list.slice_const[Expr](&values)
    ret (e, true)
}

// Function-call arguments up to the `)`; the spread `...` after the last one is noted.
fn parse_args(p: *Parser) -> (list.List[Expr], bool, bool) {
    var args = new_exprs(p.a)
    var spread = false
    var more = true
    p.nest += 1usize
    while more {
        skip(p, true)
        if peek(p) == 41u8 {
            p.at += 1usize
            more = false
        } else {
            let (arg, good) = parse_expression(p)
            if !good {
                p.nest -= 1usize
                ret (args, false, false)
            }
            let pushed = list.push[Expr](&args, arg)
            skip(p, true)
            if peek(p) == 46u8 && peek_at(p, 1usize) == 46u8 && peek_at(p, 2usize) == 46u8 {
                p.at += 3usize
                spread = true
                skip(p, true)
            }
            if peek(p) == 44u8 {
                p.at += 1usize
            } else if peek(p) != 41u8 {
                p.nest -= 1usize
                ret (args, false, false)
            }
        }
    }
    p.nest -= 1usize
    ret (args, spread, true)
}

fn parse_postfix(p: *Parser, root: Expr) -> (Expr, bool) {
    let (made, e) = list.init[Operator](p.a, 4usize)
    if e != ok { ret (root, false) }
    var ops = made
    var more = true
    while more {
        let c = peek(p)
        if c == 46u8 && peek_at(p, 1usize) == 42u8 {
            p.at += 2usize
            let pushed = list.push[Operator](&ops, Operator { kind: .AttrSplat, name: "", index: zero })
        } else if c == 46u8 && is_digit(peek_at(p, 1usize)) {
            p.at += 1usize
            let start = p.at
            while !at_end(p) && is_digit(peek(p)) { p.at += 1usize }
            let pushed = list.push[Operator](&ops, Operator { kind: .LegacyIndex, name: p.src[start..p.at], index: zero })
        } else if c == 46u8 && is_ident_start(peek_at(p, 1usize)) {
            p.at += 1usize
            let (name, good) = identifier(p)
            if !good { ret (root, false) }
            let pushed = list.push[Operator](&ops, Operator { kind: .GetAttr, name: name, index: zero })
        } else if c == 91u8 && peek_at(p, 1usize) == 42u8 && peek_at(p, 2usize) == 93u8 {
            p.at += 3usize
            let pushed = list.push[Operator](&ops, Operator { kind: .FullSplat, name: "", index: zero })
        } else if c == 91u8 {
            p.at += 1usize
            p.nest += 1usize
            skip(p, true)
            let (idx, good) = parse_expression(p)
            p.nest -= 1usize
            if !good { ret (root, false) }
            skip(p, true)
            if !expect(p, 93u8) { ret (root, false) }
            let pushed = list.push[Operator](&ops, Operator { kind: .Index, name: "", index: one(p.a, idx) })
        } else {
            more = false
        }
    }
    if ops.len == 0usize { ret (root, true) }
    var t = blank(.Traversal)
    t.items = one(p.a, root)
    t.ops = list.slice_const[Operator](&ops)
    ret (t, true)
}

// A primary expression, without its postfix operators.
fn parse_primary(p: *Parser) -> (Expr, bool) {
    if p.depth > 200usize { ret (blank(.Null), false) }
    let c = peek(p)
    if c == 34u8 {
        let (e, good) = parse_quoted(p)
        if !good { ret (e, false) }
        ret (e, true)
    }
    if c == 60u8 && peek_at(p, 1usize) == 60u8 {
        let (e, good) = parse_heredoc(p)
        ret (e, good)
    }
    if is_digit(c) {
        let (e, good) = parse_number(p, false)
        ret (e, true)
    }
    if c == 91u8 {
        let (e, good) = parse_array(p)
        if !good { ret (e, false) }
        ret (e, true)
    }
    if c == 123u8 {
        let (e, good) = parse_object(p)
        if !good { ret (e, false) }
        ret (e, true)
    }
    if c == 40u8 {
        p.at += 1usize
        p.nest += 1usize
        skip(p, true)
        let (inner, good) = parse_expression(p)
        p.nest -= 1usize
        if !good { ret (blank(.Null), false) }
        skip(p, true)
        if !expect(p, 41u8) { ret (blank(.Null), false) }
        var e = blank(.Parens)
        e.items = one(p.a, inner)
        ret (e, true)
    }
    if is_ident_start(c) {
        let start = p.at
        let (name, good) = identifier(p)
        if !good { ret (blank(.Null), false) }
        // a namespaced or plain function call
        let (nl, ne) = list.init[str](p.a, 2usize)
        if ne != ok { ret (blank(.Null), false) }
        var names = nl
        var last = name
        var is_call = false
        var probing = true
        while probing {
            if peek(p) == 58u8 && peek_at(p, 1usize) == 58u8 && is_ident_start(peek_at(p, 2usize)) {
                let pushed = list.push[str](&names, last)
                p.at += 2usize
                let (next, ok_next) = identifier(p)
                if !ok_next { ret (blank(.Null), false) }
                last = next
            } else {
                probing = false
            }
        }
        if peek(p) == 40u8 {
            is_call = true
            p.at += 1usize
        }
        if is_call {
            let (args, spread, ok_args) = parse_args(p)
            if !ok_args { ret (blank(.Null), false) }
            var e = blank(.FuncCall)
            e.text = last
            e.flag = spread
            e.items = list.slice_const[Expr](&args)
            e.names = list.slice_const[str](&names)
            ret (e, true)
        }
        if names.len > 0usize { ret (blank(.Null), false) }
        if str.eq(name, "null") {
            ret (blank(.Null), true)
        }
        if str.eq(name, "true") || str.eq(name, "false") {
            var e = blank(.Bool)
            e.flag = str.eq(name, "true")
            ret (e, true)
        }
        var e = blank(.Variable)
        e.text = name
        ret (e, true)
    }
    ret (blank(.Null), false)
}

// A prefix operator applies to the next primary and the postfix operators then apply to that result, as hcl-rs reads
// `-a.b` (the traversal's root is the negation).
fn parse_prefix(p: *Parser) -> (Expr, bool) {
    let c = peek(p)
    if c == 45u8 || c == 33u8 {
        p.at += 1usize
        skip(p, false)
        if c == 45u8 && is_digit(peek(p)) {
            let (n, good) = parse_number(p, true)
            ret (n, good)
        }
        let (inner, good) = parse_prefix(p)
        if !good { ret (blank(.Null), false) }
        var e = blank(.Unary)
        if c == 45u8 { e.text = "-" } else { e.text = "!" }
        e.items = one(p.a, inner)
        ret (e, true)
    }
    let (e, good) = parse_primary(p)
    ret (e, good)
}

fn parse_unary(p: *Parser) -> (Expr, bool) {
    let (e, good) = parse_prefix(p)
    if !good { ret (blank(.Null), false) }
    let (r0, r1) = parse_postfix(p, e)
    ret (r0, r1)
}

// The binary operator at the cursor, as its spelling; empty when there is none.
fn binary_operator(p: *const Parser) -> str {
    let c = peek(p)
    let d = peek_at(p, 1usize)
    if c == 124u8 && d == 124u8 { ret "||" }
    if c == 38u8 && d == 38u8 { ret "&&" }
    if c == 61u8 && d == 61u8 { ret "==" }
    if c == 33u8 && d == 61u8 { ret "!=" }
    if c == 60u8 && d == 61u8 { ret "<=" }
    if c == 62u8 && d == 61u8 { ret ">=" }
    if c == 60u8 && d != 60u8 { ret "<" }
    if c == 62u8 { ret ">" }
    if c == 43u8 { ret "+" }
    if c == 45u8 { ret "-" }
    if c == 42u8 { ret "*" }
    if c == 47u8 && d != 47u8 && d != 42u8 { ret "/" }
    if c == 37u8 { ret "%" }
    ret ""
}

// `term (op term)*`, nested to the right as hcl-rs nests it, then an optional `? true : false`.
fn parse_expression(p: *Parser) -> (Expr, bool) {
    if p.depth > 200usize { ret (blank(.Null), false) }
    p.depth += 1usize
    let (lhs, good) = parse_unary(p)
    if !good {
        p.depth -= 1usize
        ret (blank(.Null), false)
    }
    var result = lhs
    skip(p, p.nest > 0usize)
    let op = binary_operator(p)
    if op.len > 0usize {
        p.at += op.len
        skip(p, true)
        let (rhs, ok_rhs) = parse_binary_tail(p)
        if !ok_rhs {
            p.depth -= 1usize
            ret (blank(.Null), false)
        }
        var b = blank(.Binary)
        b.text = op
        let (items, e) = mem.alloc[Expr](p.a, 2usize)
        if e != ok {
            p.depth -= 1usize
            ret (blank(.Null), false)
        }
        items[0] = lhs
        items[1] = rhs
        b.items = items[0usize..2usize]
        result = b
    }
    skip(p, p.nest > 0usize)
    if peek(p) == 63u8 {
        p.at += 1usize
        skip(p, true)
        let (yes, ok_yes) = parse_expression(p)
        if !ok_yes {
            p.depth -= 1usize
            ret (blank(.Null), false)
        }
        skip(p, true)
        if !expect(p, 58u8) {
            p.depth -= 1usize
            ret (blank(.Null), false)
        }
        skip(p, true)
        let (no, ok_no) = parse_expression(p)
        if !ok_no {
            p.depth -= 1usize
            ret (blank(.Null), false)
        }
        var c = blank(.Conditional)
        let (items, e) = mem.alloc[Expr](p.a, 3usize)
        if e != ok {
            p.depth -= 1usize
            ret (blank(.Null), false)
        }
        items[0] = result
        items[1] = yes
        items[2] = no
        c.items = items[0usize..3usize]
        result = c
    }
    p.depth -= 1usize
    ret (result, true)
}

// The right operand of a binary operator: a term chain without a conditional (the `?` belongs to the whole chain).
fn parse_binary_tail(p: *Parser) -> (Expr, bool) {
    let (lhs, good) = parse_unary(p)
    if !good { ret (blank(.Null), false) }
    skip(p, p.nest > 0usize)
    let op = binary_operator(p)
    if op.len == 0usize { ret (lhs, true) }
    p.at += op.len
    skip(p, true)
    let (rhs, ok_rhs) = parse_binary_tail(p)
    if !ok_rhs { ret (blank(.Null), false) }
    var b = blank(.Binary)
    b.text = op
    let (items, e) = mem.alloc[Expr](p.a, 2usize)
    if e != ok { ret (blank(.Null), false) }
    items[0] = lhs
    items[1] = rhs
    b.items = items[0usize..2usize]
    ret (b, true)
}

// --- the body -----------------------------------------------------------------------------------------------------------

fn parse_label(p: *Parser) -> (str, bool) {
    if peek(p) == 34u8 {
        p.at += 1usize
        var out = new_bytes(p.a)
        var closed = false
        while !at_end(p) && !closed {
            let c = peek(p)
            if c == 34u8 {
                closed = true
                p.at += 1usize
            } else if c == 10u8 {
                ret ("", false)
            } else if c == 92u8 {
                p.at += 1usize
                let n = peek(p)
                p.at += 1usize
                if n == 110u8 { push_byte(&out, 10u8) } else if n == 116u8 { push_byte(&out, 9u8) } else if n == 34u8 { push_byte(&out, 34u8) } else if n == 92u8 { push_byte(&out, 92u8) } else { ret ("", false) }
            } else {
                push_byte(&out, c)
                p.at += 1usize
            }
        }
        if !closed { ret ("", false) }
        ret (bytes_text(&out), true)
    }
    let (r0, r1) = identifier(p)
    ret (r0, r1)
}

// A body up to `}` (consumed) when `nested`, else to the end of the source.
fn parse_body(p: *Parser, nested: bool) -> ([]const Item, bool) {
    let (made, e) = list.init[Item](p.a, 8usize)
    if e != ok { ret (zero, false) }
    var items = made
    var more = true
    while more {
        skip(p, true)
        if at_end(p) {
            if nested { ret (zero, false) }
            more = false
        } else if peek(p) == 125u8 {
            if !nested { ret (zero, false) }
            p.at += 1usize
            more = false
        } else {
            let (name, good) = identifier(p)
            if !good { ret (zero, false) }
            skip(p, false)
            if peek(p) == 61u8 && peek_at(p, 1usize) != 61u8 {
                p.at += 1usize
                skip(p, false)
                let (value, ok_value) = parse_expression(p)
                if !ok_value { ret (zero, false) }
                skip(p, false)
                if !at_end(p) && peek(p) != 10u8 && peek(p) != 125u8 { ret (zero, false) }
                let pushed = list.push[Item](&items, Item { is_block: false, name: name, labels: zero, value: one(p.a, value), body: zero })
            } else {
                let (lm, le) = list.init[str](p.a, 2usize)
                if le != ok { ret (zero, false) }
                var labels = lm
                var reading = true
                while reading {
                    skip(p, false)
                    if peek(p) == 123u8 {
                        reading = false
                    } else {
                        let (label, ok_label) = parse_label(p)
                        if !ok_label { ret (zero, false) }
                        let pushed = list.push[str](&labels, label)
                    }
                }
                p.at += 1usize
                let (body, ok_body) = parse_body(p, true)
                if !ok_body { ret (zero, false) }
                let pushed = list.push[Item](&items, Item { is_block: true, name: name, labels: list.slice_const[str](&labels), value: zero, body: body })
            }
        }
    }
    ret (list.slice_const[Item](&items), true)
}

// Parse HCL source into its top-level body; `Invalid` when the text is not valid.
fn parse(a: *mem.Arena, source: str) -> ([]const Item, err) {
    var p = Parser { a: a, src: source, at: 0usize, depth: 0usize, nest: 0usize }
    let (body, good) = parse_body(&p, false)
    if !good { ret (zero, Invalid) }
    ret (body, ok)
}
