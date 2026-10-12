// A small expression language in the family of JEXL, SpEL and MVEL: property navigation,
// method calls and operators over values and caller-owned objects, evaluated by a tree walk
// under limits. It is not a formula engine (`e.algo.formula` is the cell-formula shape) and
// it does not compile to bytecode.
//
// Values. `Null`, `Bool`, `Int` (i64), `Float` (f64), `Str`, `List`, `Map` (string keys,
// insertion order) and `Object`, an opaque handle (`u32`) to something the host owns. Objects
// are only ever touched through the `Host` callbacks, which is the sandbox: an expression
// cannot reach anything the host did not give it a callback for, a callback may refuse
// (`Denied`), and every evaluation is bounded by `Limits` (steps, nesting, string and
// collection sizes).
//
// Syntax. Literals `1`, `1.5`, `1e3`, `'str'`/`"str"` (escapes \n \t \r \\ \' \" \uXXXX), `true`,
// `false`, `null`, lists `[1, 2]`, maps `{'a': 1, b: 2}`, ranges `1..5`. Names are variables
// from the scope. `a.b`, `a?.b`, `a['b']`, `a[0]`, `a?[0]`, calls `f(x)` (host then built-in
// functions) and method calls `a.m(x)`. Operators, loosest first: `?:` ternary and elvis
// `a ?: b`, `??` null coalescing; `||` `or`; `&&` `and`; `==` `!=` `eq` `ne` `=~` `!~`
// `=^` `=$`; `<` `<=` `>` `>=` `lt` `le` `gt` `ge`; `..`; `+` `-`; `*` `/` `%` `div` `mod`;
// unary `!` `not` `-` `+` `empty` `size`; postfix `.` `[` `(`.
//
// Semantics. Arithmetic promotes Int to Float when mixed; Int `/` is exact (an Int when the
// division is exact, else a Float), `%` is Java's truncated remainder; Int overflow is
// `Overflow`; `+` with a string on either side concatenates the text forms; `==` compares
// numbers by value across Int and Float, strings, lists and maps deeply, objects by handle.
// Truthiness (for `!`, `&&`, `||`, `?:`, `?:`): null, false, 0, 0.0, `""`, empty list and
// empty map are false. `a =~ b` is membership (a in list b, key in map b, substring in string
// b); `=^` starts-with, `=$` ends-with. `&&`/`||` short-circuit and answer a Bool. A missing
// map key or unknown object property is `Null`, or `Undefined` under `strict`.

use e.mem
use e.str

type Pair = struct { key: str, value: Value }
type Value = union enum u8 { Null, Bool: bool, Int: i64, Float: f64, Str: str, List: []const Value, Map: []const Pair, Object: u32 }
type Binding = struct { name: str, value: Value }
type Host = struct {
    ctx: *void,
    get: fn(*void, *mem.Arena, u32, str) -> (Value, bool),
    call: fn(*void, *mem.Arena, u32, str, []const Value) -> (Value, err),
    function: fn(*void, *mem.Arena, str, []const Value) -> (Value, err)
}
type Limits = struct { max_steps: u32, max_depth: u32, max_string: usize, max_collection: usize, strict: bool }
type Token = struct { kind: u8, start: usize, end: usize, int_value: i64, float_value: f64, text: str }
type Node = struct { kind: u8, op: u8, a: u32, b: u32, c: u32, text: str, value: Value }
type Program = struct { nodes: []Node, kids: []u32, root: u32 }
type Interp = struct { arena: *mem.Arena, host: Host, scope: []const Binding, program: *const Program, limits: Limits, steps: u32, depth: u32 }
error Syntax
error Type
error DivideByZero
error Index
error Undefined
error Limit
error Denied
error Overflow

const T_END: u8 = 0u8
const T_INT: u8 = 1u8
const T_FLOAT: u8 = 2u8
const T_STR: u8 = 3u8
const T_NAME: u8 = 4u8
const T_PUNCT: u8 = 5u8

const N_LIT: u8 = 0u8
const N_VAR: u8 = 1u8
const N_LIST: u8 = 2u8
const N_MAP: u8 = 3u8
const N_UNARY: u8 = 4u8
const N_BINARY: u8 = 5u8
const N_AND: u8 = 6u8
const N_OR: u8 = 7u8
const N_TERNARY: u8 = 8u8
const N_ELVIS: u8 = 9u8
const N_COALESCE: u8 = 10u8
const N_PROP: u8 = 11u8
const N_INDEX: u8 = 12u8
const N_CALL: u8 = 13u8
const N_METHOD: u8 = 14u8
const N_RANGE: u8 = 15u8

fn no_value() -> Value {
    var v: Value = .Null
    ret v
}

fn default_limits() -> Limits {
    var l: Limits = zero
    l.max_steps = 100000u32
    l.max_depth = 64u32
    l.max_string = 65536usize
    l.max_collection = 10000usize
    ret l
}

// ---- lexer ----

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_name_start(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 95u8 || c == 36u8 }
fn is_name(c: u8) -> bool { ret is_name_start(c) || is_digit(c) }

fn hex_of(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i32(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret i32(c - 55u8) }
    ret -1i32
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn put_utf8(buf: []u8, n: usize, cp: u32) -> usize {
    if cp < 128u32 {
        buf[n] = u8(cp)
        ret n + 1usize
    }
    if cp < 2048u32 {
        buf[n] = u8(192u32 + (cp >> 6u32))
        buf[n + 1usize] = u8(128u32 + (cp & 63u32))
        ret n + 2usize
    }
    buf[n] = u8(224u32 + (cp >> 12u32))
    buf[n + 1usize] = u8(128u32 + ((cp >> 6u32) & 63u32))
    buf[n + 2usize] = u8(128u32 + (cp & 63u32))
    ret n + 3usize
}

// A quoted string at `at` (the quote), decoded into the arena; returns the text and the index after it.
fn lex_string(a: *mem.Arena, src: str, at: usize, max: usize) -> (str, usize, err) {
    let q = src[at]
    let (buf, alloc_error) = mem.alloc[u8](a, src.len - at + 1usize)
    if alloc_error != ok { ret ("", at, alloc_error) }
    var n = 0usize
    var i = at + 1usize
    while i < src.len && src[i] != q {
        var c = src[i]
        if c == 92u8 {
            i += 1usize
            if i >= src.len { ret ("", at, Syntax) }
            let e = src[i]
            if e == 110u8 {
                c = 10u8
            } else if e == 116u8 {
                c = 9u8
            } else if e == 114u8 {
                c = 13u8
            } else if e == 117u8 {
                if i + 4usize >= src.len { ret ("", at, Syntax) }
                var cp = 0u32
                var k = 1usize
                while k <= 4usize {
                    let h = hex_of(src[i + k])
                    if h < 0i32 { ret ("", at, Syntax) }
                    cp = cp * 16u32 + u32(h)
                    k += 1usize
                }
                n = put_utf8(buf, n, cp)
                i += 5usize
                continue
            } else {
                c = e
            }
        }
        buf[n] = c
        n += 1usize
        i += 1usize
        if n > max { ret ("", at, Limit) }
    }
    if i >= src.len { ret ("", at, Syntax) }
    ret (buf[0usize..n], i + 1usize, ok)
}

// Tokens into `out`; returns the count (the last is T_END).
fn lex(a: *mem.Arena, src: str, limits: Limits, out: []Token) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < src.len {
        let c = src[i]
        if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 {
            i += 1usize
            continue
        }
        if n + 2usize >= out.len { ret (0usize, Limit) }
        var t: Token = zero
        t.start = i
        if is_digit(c) || (c == 46u8 && i + 1usize < src.len && is_digit(src[i + 1usize]) && (n == 0usize || out[n - 1usize].kind == T_PUNCT)) {
            var j = i
            var is_float = false
            while j < src.len && is_digit(src[j]) { j += 1usize }
            // `1..5` is a range: a dot followed by a dot is not a fraction
            if j < src.len && src[j] == 46u8 && !(j + 1usize < src.len && src[j + 1usize] == 46u8) && !(j + 1usize < src.len && is_name_start(src[j + 1usize])) {
                is_float = true
                j += 1usize
                while j < src.len && is_digit(src[j]) { j += 1usize }
            }
            if j < src.len && (src[j] == 101u8 || src[j] == 69u8) {
                var k = j + 1usize
                if k < src.len && (src[k] == 43u8 || src[k] == 45u8) { k += 1usize }
                if k < src.len && is_digit(src[k]) {
                    is_float = true
                    while k < src.len && is_digit(src[k]) { k += 1usize }
                    j = k
                }
            }
            let text = src[i..j]
            t.end = j
            if is_float {
                var number_text = text
                if text.len > 0usize && text[0usize] == 46u8 {
                    // `.5` reads as `0.5`
                    let (padded, padded_error) = mem.alloc[u8](a, text.len + 1usize)
                    if padded_error != ok { ret (0usize, padded_error) }
                    padded[0usize] = 48u8
                    var q = 0usize
                    while q < text.len {
                        padded[q + 1usize] = text[q]
                        q += 1usize
                    }
                    number_text = padded[0usize..text.len + 1usize]
                }
                let (f, f_error) = str.parse_f64(number_text)
                if f_error != ok { ret (0usize, Syntax) }
                t.kind = T_FLOAT
                t.float_value = f
            } else {
                let (v, v_error) = str.parse_i64(text)
                if v_error != ok { ret (0usize, Overflow) }
                t.kind = T_INT
                t.int_value = v
            }
            // JEXL's numeric suffixes L l D d F f H h are accepted and ignored
            if j < src.len && (src[j] == 76u8 || src[j] == 108u8) && !(j + 1usize < src.len && is_name(src[j + 1usize])) { j += 1usize }
            i = j
        } else if c == 39u8 || c == 34u8 {
            let (text, next, e) = lex_string(a, src, i, limits.max_string)
            if e != ok { ret (0usize, e) }
            t.kind = T_STR
            t.text = text
            t.end = next
            i = next
        } else if is_name_start(c) {
            var j = i
            while j < src.len && is_name(src[j]) { j += 1usize }
            t.kind = T_NAME
            t.text = src[i..j]
            t.end = j
            i = j
        } else {
            // punctuation: longest first
            var len = 1usize
            if len == 1usize && i + 1usize < src.len {
                let two = src[i..i + 2usize]
                if same(two, "&&") || same(two, "||") || same(two, "==") || same(two, "!=") || same(two, "<=") || same(two, ">=") || same(two, "?.") || same(two, "?[") || same(two, "??") || same(two, "?:") || same(two, "=~") || same(two, "!~") || same(two, "=^") || same(two, "=$") || same(two, "..") { len = 2usize }
            }
            t.kind = T_PUNCT
            t.text = src[i..i + len]
            t.end = i + len
            i += len
        }
        out[n] = t
        n += 1usize
    }
    var end: Token = zero
    end.kind = T_END
    end.start = src.len
    end.end = src.len
    out[n] = end
    ret (n + 1usize, ok)
}

// ---- parser ----

type Parser = struct { tokens: []const Token, at: usize, nodes: []Node, node_count: usize, kids: []u32, kid_count: usize, depth: u32, max_depth: u32 }

fn add_node(p: *Parser, n: Node) -> (u32, err) {
    if p.node_count >= p.nodes.len { ret (0u32, Limit) }
    p.nodes[p.node_count] = n
    p.node_count += 1usize
    ret (u32(p.node_count - 1usize), ok)
}

fn peek_is(p: *const Parser, text: str) -> bool {
    let t = p.tokens[p.at]
    if t.kind == T_PUNCT || t.kind == T_NAME { ret same(t.text, text) }
    ret false
}

fn punct_is(p: *const Parser, text: str) -> bool {
    let t = p.tokens[p.at]
    ret t.kind == T_PUNCT && same(t.text, text)
}

fn word_is(p: *const Parser, text: str) -> bool {
    let t = p.tokens[p.at]
    ret t.kind == T_NAME && same(t.text, text)
}

fn expect_punct(p: *Parser, text: str) -> err {
    if !punct_is(p, text) { ret Syntax }
    p.at += 1usize
    ret ok
}

fn push_kid(p: *Parser, id: u32) -> err {
    if p.kid_count >= p.kids.len { ret Limit }
    p.kids[p.kid_count] = id
    p.kid_count += 1usize
    ret ok
}

fn binary(p: *Parser, op: u8, left: u32, right: u32) -> (u32, err) {
    var n: Node = zero
    n.kind = N_BINARY
    n.op = op
    n.a = left
    n.b = right
    let (rv1, re1) = add_node(p, n)
    ret (rv1, re1)
}

// Operator codes for N_BINARY / N_UNARY.
const OP_ADD: u8 = 1u8
const OP_SUB: u8 = 2u8
const OP_MUL: u8 = 3u8
const OP_DIV: u8 = 4u8
const OP_MOD: u8 = 5u8
const OP_EQ: u8 = 6u8
const OP_NE: u8 = 7u8
const OP_LT: u8 = 8u8
const OP_LE: u8 = 9u8
const OP_GT: u8 = 10u8
const OP_GE: u8 = 11u8
const OP_IN: u8 = 12u8
const OP_NIN: u8 = 13u8
const OP_STARTS: u8 = 14u8
const OP_ENDS: u8 = 15u8
const OP_NOT: u8 = 20u8
const OP_NEG: u8 = 21u8
const OP_POS: u8 = 22u8
const OP_EMPTY: u8 = 23u8
const OP_SIZE: u8 = 24u8

fn parse_expr(p: *Parser) -> (u32, err) {
    if p.depth >= p.max_depth { ret (0u32, Limit) }
    p.depth += 1u32
    let (r, e) = parse_ternary(p)
    p.depth -= 1u32
    ret (r, e)
}

fn parse_ternary(p: *Parser) -> (u32, err) {
    let (cond, e1) = parse_or(p)
    if e1 != ok { ret (0u32, e1) }
    if punct_is(p, "?:") {
        p.at += 1usize
        let (alt, e2) = parse_ternary(p)
        if e2 != ok { ret (0u32, e2) }
        var n: Node = zero
        n.kind = N_ELVIS
        n.a = cond
        n.b = alt
        let (rv2, re2) = add_node(p, n)
        ret (rv2, re2)
    }
    if punct_is(p, "??") {
        p.at += 1usize
        let (alt, e2) = parse_ternary(p)
        if e2 != ok { ret (0u32, e2) }
        var n: Node = zero
        n.kind = N_COALESCE
        n.a = cond
        n.b = alt
        let (rv3, re3) = add_node(p, n)
        ret (rv3, re3)
    }
    if punct_is(p, "?") {
        p.at += 1usize
        let (yes, e2) = parse_ternary(p)
        if e2 != ok { ret (0u32, e2) }
        // `a ? b : c`; a lone `:` is a one-byte punctuation token
        if !punct_is(p, ":") { ret (0u32, Syntax) }
        p.at += 1usize
        let (no, e3) = parse_ternary(p)
        if e3 != ok { ret (0u32, e3) }
        var n: Node = zero
        n.kind = N_TERNARY
        n.a = cond
        n.b = yes
        n.c = no
        let (rv4, re4) = add_node(p, n)
        ret (rv4, re4)
    }
    ret (cond, ok)
}

fn parse_or(p: *Parser) -> (u32, err) {
    let (left_first5, e) = parse_and(p)
    var left = left_first5
    if e != ok { ret (0u32, e) }
    while punct_is(p, "||") || word_is(p, "or") {
        p.at += 1usize
        let (right, e2) = parse_and(p)
        if e2 != ok { ret (0u32, e2) }
        var n: Node = zero
        n.kind = N_OR
        n.a = left
        n.b = right
        let (id, e3) = add_node(p, n)
        if e3 != ok { ret (0u32, e3) }
        left = id
    }
    ret (left, ok)
}

fn parse_and(p: *Parser) -> (u32, err) {
    let (left_first6, e) = parse_equality(p)
    var left = left_first6
    if e != ok { ret (0u32, e) }
    while punct_is(p, "&&") || word_is(p, "and") {
        p.at += 1usize
        let (right, e2) = parse_equality(p)
        if e2 != ok { ret (0u32, e2) }
        var n: Node = zero
        n.kind = N_AND
        n.a = left
        n.b = right
        let (id, e3) = add_node(p, n)
        if e3 != ok { ret (0u32, e3) }
        left = id
    }
    ret (left, ok)
}

fn equality_op(p: *const Parser) -> u8 {
    if punct_is(p, "==") || word_is(p, "eq") { ret OP_EQ }
    if punct_is(p, "!=") || word_is(p, "ne") { ret OP_NE }
    if punct_is(p, "=~") { ret OP_IN }
    if punct_is(p, "!~") { ret OP_NIN }
    if punct_is(p, "=^") { ret OP_STARTS }
    if punct_is(p, "=$") { ret OP_ENDS }
    ret 0u8
}

fn parse_equality(p: *Parser) -> (u32, err) {
    let (left_first7, e) = parse_relational(p)
    var left = left_first7
    if e != ok { ret (0u32, e) }
    while equality_op(p) != 0u8 {
        let op = equality_op(p)
        p.at += 1usize
        let (right, e2) = parse_relational(p)
        if e2 != ok { ret (0u32, e2) }
        let (id, e3) = binary(p, op, left, right)
        if e3 != ok { ret (0u32, e3) }
        left = id
    }
    ret (left, ok)
}

fn relational_op(p: *const Parser) -> u8 {
    if punct_is(p, "<") || word_is(p, "lt") { ret OP_LT }
    if punct_is(p, "<=") || word_is(p, "le") { ret OP_LE }
    if punct_is(p, ">") || word_is(p, "gt") { ret OP_GT }
    if punct_is(p, ">=") || word_is(p, "ge") { ret OP_GE }
    ret 0u8
}

fn parse_relational(p: *Parser) -> (u32, err) {
    let (left_first8, e) = parse_range(p)
    var left = left_first8
    if e != ok { ret (0u32, e) }
    while relational_op(p) != 0u8 {
        let op = relational_op(p)
        p.at += 1usize
        let (right, e2) = parse_range(p)
        if e2 != ok { ret (0u32, e2) }
        let (id, e3) = binary(p, op, left, right)
        if e3 != ok { ret (0u32, e3) }
        left = id
    }
    ret (left, ok)
}

fn parse_range(p: *Parser) -> (u32, err) {
    let (left, e) = parse_additive(p)
    if e != ok { ret (0u32, e) }
    if punct_is(p, "..") {
        p.at += 1usize
        let (right, e2) = parse_additive(p)
        if e2 != ok { ret (0u32, e2) }
        var n: Node = zero
        n.kind = N_RANGE
        n.a = left
        n.b = right
        let (rv9, re9) = add_node(p, n)
        ret (rv9, re9)
    }
    ret (left, ok)
}

fn parse_additive(p: *Parser) -> (u32, err) {
    let (left_first10, e) = parse_multiplicative(p)
    var left = left_first10
    if e != ok { ret (0u32, e) }
    while punct_is(p, "+") || punct_is(p, "-") {
        var op = OP_ADD
        if punct_is(p, "-") { op = OP_SUB }
        p.at += 1usize
        let (right, e2) = parse_multiplicative(p)
        if e2 != ok { ret (0u32, e2) }
        let (id, e3) = binary(p, op, left, right)
        if e3 != ok { ret (0u32, e3) }
        left = id
    }
    ret (left, ok)
}

fn multiplicative_op(p: *const Parser) -> u8 {
    if punct_is(p, "*") { ret OP_MUL }
    if punct_is(p, "/") || word_is(p, "div") { ret OP_DIV }
    if punct_is(p, "%") || word_is(p, "mod") { ret OP_MOD }
    ret 0u8
}

fn parse_multiplicative(p: *Parser) -> (u32, err) {
    let (left_first11, e) = parse_unary(p)
    var left = left_first11
    if e != ok { ret (0u32, e) }
    while multiplicative_op(p) != 0u8 {
        let op = multiplicative_op(p)
        p.at += 1usize
        let (right, e2) = parse_unary(p)
        if e2 != ok { ret (0u32, e2) }
        let (id, e3) = binary(p, op, left, right)
        if e3 != ok { ret (0u32, e3) }
        left = id
    }
    ret (left, ok)
}

fn parse_unary(p: *Parser) -> (u32, err) {
    var op = 0u8
    if punct_is(p, "!") || word_is(p, "not") { op = OP_NOT }
    if punct_is(p, "-") { op = OP_NEG }
    if punct_is(p, "+") { op = OP_POS }
    // `empty x` and `size x` (the call forms `empty(x)` / `size(x)` are functions)
    if word_is(p, "empty") && !(p.tokens[p.at + 1usize].kind == T_PUNCT && same(p.tokens[p.at + 1usize].text, "(")) { op = OP_EMPTY }
    if word_is(p, "size") && !(p.tokens[p.at + 1usize].kind == T_PUNCT && same(p.tokens[p.at + 1usize].text, "(")) { op = OP_SIZE }
    if op != 0u8 {
        p.at += 1usize
        if p.depth >= p.max_depth { ret (0u32, Limit) }
        p.depth += 1u32
        let (operand, e) = parse_unary(p)
        p.depth -= 1u32
        if e != ok { ret (0u32, e) }
        var n: Node = zero
        n.kind = N_UNARY
        n.op = op
        n.a = operand
        let (rv12, re12) = add_node(p, n)
        ret (rv12, re12)
    }
    let (rv13, re13) = parse_postfix(p)
    ret (rv13, re13)
}

fn parse_args(p: *Parser, first_kid: *usize, count: *u32) -> err {
    // after `(`: expressions separated by commas up to `)`
    var start = 0usize
    var n = 0u32
    var ids: [32]u32 = zero
    if !punct_is(p, ")") {
        while true {
            let (arg, e) = parse_expr(p)
            if e != ok { ret e }
            if n >= 32u32 { ret Limit }
            ids[usize(n)] = arg
            n += 1u32
            if punct_is(p, ",") {
                p.at += 1usize
                continue
            }
            break
        }
    }
    try expect_punct(p, ")")
    // the kids of nested calls were pushed while parsing; this call's own come after them
    start = p.kid_count
    var i = 0usize
    while i < usize(n) {
        try push_kid(p, ids[i])
        i += 1usize
    }
    *first_kid = start
    *count = n
    ret ok
}

fn parse_postfix(p: *Parser) -> (u32, err) {
    let (base_first14, e) = parse_primary(p)
    var base = base_first14
    if e != ok { ret (0u32, e) }
    while true {
        if punct_is(p, ".") || punct_is(p, "?.") {
            var safe = 0u32
            if punct_is(p, "?.") { safe = 1u32 }
            p.at += 1usize
            let t = p.tokens[p.at]
            if t.kind != T_NAME { ret (0u32, Syntax) }
            p.at += 1usize
            if punct_is(p, "(") {
                p.at += 1usize
                var first = 0usize
                var count = 0u32
                let args_error = parse_args(p, &first, &count)
                if args_error != ok { ret (0u32, args_error) }
                var n: Node = zero
                n.kind = N_METHOD
                n.a = base
                n.b = u32(first)
                n.c = count
                n.op = u8(safe)
                n.text = t.text
                let (id, e2) = add_node(p, n)
                if e2 != ok { ret (0u32, e2) }
                base = id
            } else {
                var n: Node = zero
                n.kind = N_PROP
                n.a = base
                n.op = u8(safe)
                n.text = t.text
                let (id, e2) = add_node(p, n)
                if e2 != ok { ret (0u32, e2) }
                base = id
            }
        } else if punct_is(p, "[") || punct_is(p, "?[") {
            var safe = 0u8
            if punct_is(p, "?[") { safe = 1u8 }
            p.at += 1usize
            let (index, e2) = parse_expr(p)
            if e2 != ok { ret (0u32, e2) }
            let close_error = expect_punct(p, "]")
            if close_error != ok { ret (0u32, close_error) }
            var n: Node = zero
            n.kind = N_INDEX
            n.a = base
            n.b = index
            n.op = safe
            let (id, e3) = add_node(p, n)
            if e3 != ok { ret (0u32, e3) }
            base = id
        } else {
            break
        }
    }
    ret (base, ok)
}

fn parse_primary(p: *Parser) -> (u32, err) {
    let t = p.tokens[p.at]
    if t.kind == T_INT {
        p.at += 1usize
        var n: Node = zero
        n.kind = N_LIT
        n.value = Value { Int: t.int_value }
        let (rv15, re15) = add_node(p, n)
        ret (rv15, re15)
    }
    if t.kind == T_FLOAT {
        p.at += 1usize
        var n: Node = zero
        n.kind = N_LIT
        n.value = Value { Float: t.float_value }
        let (rv16, re16) = add_node(p, n)
        ret (rv16, re16)
    }
    if t.kind == T_STR {
        p.at += 1usize
        var n: Node = zero
        n.kind = N_LIT
        n.value = Value { Str: t.text }
        let (rv17, re17) = add_node(p, n)
        ret (rv17, re17)
    }
    if t.kind == T_NAME {
        p.at += 1usize
        if same(t.text, "true") || same(t.text, "false") {
            var n: Node = zero
            n.kind = N_LIT
            n.value = Value { Bool: same(t.text, "true") }
            let (rv18, re18) = add_node(p, n)
            ret (rv18, re18)
        }
        if same(t.text, "null") {
            var n: Node = zero
            n.kind = N_LIT
            let (rv19, re19) = add_node(p, n)
            ret (rv19, re19)
        }
        // a call `f(args)` or a variable
        if punct_is(p, "(") {
            p.at += 1usize
            var first = 0usize
            var count = 0u32
            let args_error = parse_args(p, &first, &count)
            if args_error != ok { ret (0u32, args_error) }
            var n: Node = zero
            n.kind = N_CALL
            n.b = u32(first)
            n.c = count
            n.text = t.text
            let (rv20, re20) = add_node(p, n)
            ret (rv20, re20)
        }
        var n: Node = zero
        n.kind = N_VAR
        n.text = t.text
        let (rv21, re21) = add_node(p, n)
        ret (rv21, re21)
    }
    if t.kind == T_PUNCT && same(t.text, "(") {
        p.at += 1usize
        let (inner, e) = parse_expr(p)
        if e != ok { ret (0u32, e) }
        let close_error = expect_punct(p, ")")
        if close_error != ok { ret (0u32, close_error) }
        ret (inner, ok)
    }
    if t.kind == T_PUNCT && same(t.text, "[") {
        p.at += 1usize
        var start = 0usize
        var ids: [64]u32 = zero
        var n = 0usize
        if !punct_is(p, "]") {
            while true {
                let (item, e) = parse_expr(p)
                if e != ok { ret (0u32, e) }
                if n >= 64usize { ret (0u32, Limit) }
                ids[n] = item
                n += 1usize
                if punct_is(p, ",") {
                    p.at += 1usize
                    continue
                }
                break
            }
        }
        let close_error = expect_punct(p, "]")
        if close_error != ok { ret (0u32, close_error) }
        start = p.kid_count
        var k = 0usize
        while k < n {
            let pe = push_kid(p, ids[k])
            if pe != ok { ret (0u32, pe) }
            k += 1usize
        }
        var node: Node = zero
        node.kind = N_LIST
        node.b = u32(start)
        node.c = u32(n)
        let (rv22, re22) = add_node(p, node)
        ret (rv22, re22)
    }
    if t.kind == T_PUNCT && same(t.text, "{") {
        p.at += 1usize
        var start = 0usize
        var ids: [64]u32 = zero
        var n = 0usize
        if !punct_is(p, "}") {
            while true {
                let key = p.tokens[p.at]
                var key_node: Node = zero
                key_node.kind = N_LIT
                if key.kind == T_STR || key.kind == T_NAME {
                    key_node.value = Value { Str: key.text }
                } else if key.kind == T_INT {
                    // numeric keys read as their decimal text
                    key_node.value = Value { Str: p.tokens[p.at].text }
                } else {
                    ret (0u32, Syntax)
                }
                p.at += 1usize
                let (key_id, ke) = add_node(p, key_node)
                if ke != ok { ret (0u32, ke) }
                let colon_error = expect_punct(p, ":")
                if colon_error != ok { ret (0u32, colon_error) }
                let (value, ve) = parse_expr(p)
                if ve != ok { ret (0u32, ve) }
                if n + 2usize > 64usize { ret (0u32, Limit) }
                ids[n] = key_id
                ids[n + 1usize] = value
                n += 2usize
                if punct_is(p, ",") {
                    p.at += 1usize
                    continue
                }
                break
            }
        }
        let close_error = expect_punct(p, "}")
        if close_error != ok { ret (0u32, close_error) }
        start = p.kid_count
        var k = 0usize
        while k < n {
            let pe = push_kid(p, ids[k])
            if pe != ok { ret (0u32, pe) }
            k += 1usize
        }
        var node: Node = zero
        node.kind = N_MAP
        node.b = u32(start)
        node.c = u32(n / 2usize)
        let (rv23, re23) = add_node(p, node)
        ret (rv23, re23)
    }
    ret (0u32, Syntax)
}

// Parses `source` into a program held in the arena.
fn compile(a: *mem.Arena, source: str, limits: Limits) -> (Program, err) {
    var prog: Program = zero
    let (tokens, tokens_error) = mem.alloc[Token](a, source.len + 2usize)
    if tokens_error != ok { ret (prog, tokens_error) }
    let (count, lex_error) = lex(a, source, limits, tokens)
    if lex_error != ok { ret (prog, lex_error) }
    let (nodes, nodes_error) = mem.alloc[Node](a, count * 3usize + 8usize)
    if nodes_error != ok { ret (prog, nodes_error) }
    let (kids, kids_error) = mem.alloc[u32](a, count * 2usize + 8usize)
    if kids_error != ok { ret (prog, kids_error) }
    var p: Parser = zero
    p.tokens = tokens[0usize..count]
    p.nodes = nodes
    p.kids = kids
    p.max_depth = limits.max_depth
    if p.max_depth == 0u32 { p.max_depth = 64u32 }
    let (root, parse_error) = parse_expr(&p)
    if parse_error != ok { ret (prog, parse_error) }
    if p.tokens[p.at].kind != T_END { ret (prog, Syntax) }
    prog.nodes = nodes[0usize..p.node_count]
    prog.kids = kids[0usize..p.kid_count]
    prog.root = root
    ret (prog, ok)
}

// ---- evaluation ----

fn truthy(v: Value) -> bool {
    switch v {
    case .Null:
        ret false
    case .Bool as b:
        ret b
    case .Int as i:
        ret i != 0i64
    case .Float as f:
        ret f != 0.0f64 && f == f
    case .Str as s:
        ret s.len > 0usize
    case .List as l:
        ret l.len > 0usize
    case .Map as m:
        ret m.len > 0usize
    case .Object as o:
        ret true
    default:
        ret false
    }
}

fn is_number(v: Value) -> bool {
    switch v {
    case .Int as i:
        ret true
    case .Float as f:
        ret true
    default:
        ret false
    }
}

fn as_float(v: Value) -> f64 {
    switch v {
    case .Int as i:
        ret f64(i)
    case .Float as f:
        ret f
    default:
        ret 0.0f64
    }
}

fn map_get(m: []const Pair, key: str) -> (Value, bool) {
    var i = 0usize
    while i < m.len {
        if same(m[i].key, key) { ret (m[i].value, true) }
        i += 1usize
    }
    ret (no_value(), false)
}

fn equals(x: Value, y: Value) -> bool {
    if is_number(x) && is_number(y) {
        switch x {
        case .Int as xi:
            switch y {
            case .Int as yi:
                ret xi == yi
            default:
                ret f64(xi) == as_float(y)
            }
        default:
            ret as_float(x) == as_float(y)
        }
    }
    switch x {
    case .Null:
        switch y {
        case .Null:
            ret true
        default:
            ret false
        }
    case .Bool as xb:
        switch y {
        case .Bool as yb:
            ret xb == yb
        default:
            ret false
        }
    case .Str as xs:
        switch y {
        case .Str as ys:
            ret same(xs, ys)
        default:
            ret false
        }
    case .List as xl:
        switch y {
        case .List as yl:
            if xl.len != yl.len { ret false }
            var i = 0usize
            while i < xl.len {
                if !equals(xl[i], yl[i]) { ret false }
                i += 1usize
            }
            ret true
        default:
            ret false
        }
    case .Map as xm:
        switch y {
        case .Map as ym:
            if xm.len != ym.len { ret false }
            var i = 0usize
            while i < xm.len {
                let (other, found) = map_get(ym, xm[i].key)
                if !found || !equals(xm[i].value, other) { ret false }
                i += 1usize
            }
            ret true
        default:
            ret false
        }
    case .Object as xo:
        switch y {
        case .Object as yo:
            ret xo == yo
        default:
            ret false
        }
    default:
        ret false
    }
}

// The text form used by `+` with a string and by `str()`: null `null`, floats with a `.0` when integral.
fn push_value(b: *str.Builder, v: Value, depth: u32) -> err {
    if depth > 32u32 { ret Limit }
    switch v {
    case .Null:
        ret str.push(b, "null")
    case .Bool as x:
        if x { ret str.push(b, "true") }
        ret str.push(b, "false")
    case .Int as i:
        ret str.push_i64(b, i)
    case .Float as f:
        if f == f && f - f == 0.0f64 && f == f64(i64(f)) && f < 1000000000000000.0f64 && f > -1000000000000000.0f64 {
            try str.push_i64(b, i64(f))
            ret str.push(b, ".0")
        }
        ret str.push_f64(b, f)
    case .Str as s:
        ret str.push(b, s)
    case .List as l:
        try str.push(b, "[")
        var i = 0usize
        while i < l.len {
            if i > 0usize { try str.push(b, ", ") }
            try push_value(b, l[i], depth + 1u32)
            i += 1usize
        }
        ret str.push(b, "]")
    case .Map as m:
        try str.push(b, "{")
        var i = 0usize
        while i < m.len {
            if i > 0usize { try str.push(b, ", ") }
            try str.push(b, m[i].key)
            try str.push(b, "=")
            try push_value(b, m[i].value, depth + 1u32)
            i += 1usize
        }
        ret str.push(b, "}")
    case .Object as o:
        try str.push(b, "#")
        ret str.push_u32(b, o)
    default:
        ret Type
    }
}

fn text_of(a: *mem.Arena, v: Value, max: usize) -> (str, err) {
    switch v {
    case .Str as s:
        ret (s, ok)
    default:
        let (b0, builder_error) = str.builder(a, 256usize)
        if builder_error != ok { ret ("", builder_error) }
        var b = b0
        let e = push_value(&b, v, 0u32)
        if e != ok { ret ("", e) }
        let text = str.done(&b)
        if text.len > max { ret ("", Limit) }
        ret (text, ok)
    }
}

fn tick(it: *Interp) -> err {
    it.steps += 1u32
    if it.limits.max_steps != 0u32 && it.steps > it.limits.max_steps { ret Limit }
    ret ok
}

fn lookup(it: *const Interp, name: str) -> (Value, bool) {
    var i = it.scope.len
    while i > 0usize {
        i -= 1usize
        if same(it.scope[i].name, name) { ret (it.scope[i].value, true) }
    }
    ret (no_value(), false)
}

fn make_list(it: *Interp, items: []const Value) -> (Value, err) {
    if items.len > it.limits.max_collection { ret (no_value(), Limit) }
    let (out, alloc_error) = mem.alloc[Value](it.arena, items.len + 1usize)
    if alloc_error != ok { ret (no_value(), alloc_error) }
    var i = 0usize
    while i < items.len {
        out[i] = items[i]
        i += 1usize
    }
    ret (Value { List: out[0usize..items.len] }, ok)
}

fn arith(it: *Interp, op: u8, x: Value, y: Value) -> (Value, err) {
    // string concatenation
    if op == OP_ADD {
        var is_text = false
        switch x {
        case .Str as s:
            is_text = true
        default:
            is_text = false
        }
        switch y {
        case .Str as s:
            is_text = true
        default:
            is_text = is_text
        }
        if is_text {
            let (left, le) = text_of(it.arena, x, it.limits.max_string)
            if le != ok { ret (no_value(), le) }
            let (right, re) = text_of(it.arena, y, it.limits.max_string)
            if re != ok { ret (no_value(), re) }
            if left.len + right.len > it.limits.max_string { ret (no_value(), Limit) }
            let (buf, alloc_error) = mem.alloc[u8](it.arena, left.len + right.len + 1usize)
            if alloc_error != ok { ret (no_value(), alloc_error) }
            var k = 0usize
            while k < left.len {
                buf[k] = left[k]
                k += 1usize
            }
            k = 0usize
            while k < right.len {
                buf[left.len + k] = right[k]
                k += 1usize
            }
            ret (Value { Str: buf[0usize..left.len + right.len] }, ok)
        }
    }
    if !is_number(x) || !is_number(y) { ret (no_value(), Type) }
    var both_int = false
    var xi = 0i64
    var yi = 0i64
    switch x {
    case .Int as v:
        xi = v
        switch y {
        case .Int as w:
            yi = w
            both_int = true
        default:
            both_int = false
        }
    default:
        both_int = false
    }
    if both_int {
        if op == OP_ADD {
            if (yi > 0i64 && xi > 9223372036854775807i64 - yi) || (yi < 0i64 && xi < -9223372036854775807i64 - 1i64 - yi) { ret (no_value(), Overflow) }
            ret (Value { Int: xi + yi }, ok)
        }
        if op == OP_SUB {
            if (yi < 0i64 && xi > 9223372036854775807i64 + yi) || (yi > 0i64 && xi < -9223372036854775807i64 - 1i64 + yi) { ret (no_value(), Overflow) }
            ret (Value { Int: xi - yi }, ok)
        }
        if op == OP_MUL {
            if xi == 0i64 || yi == 0i64 { ret (Value { Int: 0i64 }, ok) }
            let min = -9223372036854775807i64 - 1i64
            let max = 9223372036854775807i64
            if xi > 0i64 {
                if yi > 0i64 {
                    if xi > max / yi { ret (no_value(), Overflow) }
                } else {
                    if yi < min / xi { ret (no_value(), Overflow) }
                }
            } else {
                if yi > 0i64 {
                    if xi < min / yi { ret (no_value(), Overflow) }
                } else {
                    if yi < max / xi { ret (no_value(), Overflow) }
                }
            }
            ret (Value { Int: xi * yi }, ok)
        }
        if op == OP_DIV {
            if yi == 0i64 { ret (no_value(), DivideByZero) }
            if xi == -9223372036854775807i64 - 1i64 && yi == -1i64 { ret (no_value(), Overflow) }
            if xi % yi == 0i64 { ret (Value { Int: xi / yi }, ok) }
            ret (Value { Float: f64(xi) / f64(yi) }, ok)
        }
        if op == OP_MOD {
            if yi == 0i64 { ret (no_value(), DivideByZero) }
            if yi == -1i64 { ret (Value { Int: 0i64 }, ok) }
            ret (Value { Int: xi % yi }, ok)
        }
    }
    let fx = as_float(x)
    let fy = as_float(y)
    if op == OP_ADD { ret (Value { Float: fx + fy }, ok) }
    if op == OP_SUB { ret (Value { Float: fx - fy }, ok) }
    if op == OP_MUL { ret (Value { Float: fx * fy }, ok) }
    if op == OP_DIV {
        if fy == 0.0f64 { ret (no_value(), DivideByZero) }
        ret (Value { Float: fx / fy }, ok)
    }
    if op == OP_MOD {
        if fy == 0.0f64 { ret (no_value(), DivideByZero) }
        // Java's truncated remainder: x - trunc(x / y) * y
        let q = fx / fy
        var t = f64(i64(q))
        if q > 9.0e15f64 || q < -9.0e15f64 { ret (no_value(), Overflow) }
        ret (Value { Float: fx - t * fy }, ok)
    }
    ret (no_value(), Type)
}

fn compare(x: Value, y: Value) -> (i32, err) {
    if is_number(x) && is_number(y) {
        var both_int = false
        var xi = 0i64
        var yi = 0i64
        switch x {
        case .Int as v:
            xi = v
            switch y {
            case .Int as w:
                yi = w
                both_int = true
            default:
                both_int = false
            }
        default:
            both_int = false
        }
        if both_int {
            if xi < yi { ret (-1i32, ok) }
            if xi > yi { ret (1i32, ok) }
            ret (0i32, ok)
        }
        let fx = as_float(x)
        let fy = as_float(y)
        if fx < fy { ret (-1i32, ok) }
        if fx > fy { ret (1i32, ok) }
        if fx == fy { ret (0i32, ok) }
        ret (2i32, ok)
    }
    switch x {
    case .Str as xs:
        switch y {
        case .Str as ys:
            var i = 0usize
            while i < xs.len && i < ys.len {
                if xs[i] != ys[i] {
                    if xs[i] < ys[i] { ret (-1i32, ok) }
                    ret (1i32, ok)
                }
                i += 1usize
            }
            if xs.len < ys.len { ret (-1i32, ok) }
            if xs.len > ys.len { ret (1i32, ok) }
            ret (0i32, ok)
        default:
            ret (0i32, Type)
        }
    default:
        ret (0i32, Type)
    }
}

fn contains(container: Value, item: Value) -> (bool, err) {
    switch container {
    case .List as l:
        var i = 0usize
        while i < l.len {
            if equals(l[i], item) { ret (true, ok) }
            i += 1usize
        }
        ret (false, ok)
    case .Map as m:
        switch item {
        case .Str as key:
            let (v, found) = map_get(m, key)
            ret (found, ok)
        default:
            ret (false, ok)
        }
    case .Str as s:
        switch item {
        case .Str as needle:
            if needle.len > s.len { ret (false, ok) }
            var i = 0usize
            while i + needle.len <= s.len {
                if same(s[i..i + needle.len], needle) { ret (true, ok) }
                i += 1usize
            }
            ret (false, ok)
        default:
            ret (false, Type)
        }
    default:
        ret (false, Type)
    }
}

fn size_of(v: Value) -> (i64, err) {
    switch v {
    case .Str as s:
        ret (i64(s.len), ok)
    case .List as l:
        ret (i64(l.len), ok)
    case .Map as m:
        ret (i64(m.len), ok)
    case .Null:
        ret (0i64, ok)
    default:
        ret (0i64, Type)
    }
}

fn eval(it: *Interp, id: u32) -> (Value, err) {
    try tick(it)
    if it.depth >= it.limits.max_depth && it.limits.max_depth != 0u32 { ret (no_value(), Limit) }
    it.depth += 1u32
    let (v, e) = eval_node(it, id)
    it.depth -= 1u32
    ret (v, e)
}

fn eval_args(it: *Interp, first: u32, count: u32, out: []Value) -> err {
    var i = 0usize
    while i < usize(count) {
        let (v, e) = eval(it, it.program.kids[usize(first) + i])
        if e != ok { ret e }
        out[i] = v
        i += 1usize
    }
    ret ok
}

fn eval_node(it: *Interp, id: u32) -> (Value, err) {
    let n = it.program.nodes[usize(id)]
    if n.kind == N_LIT { ret (n.value, ok) }
    if n.kind == N_VAR {
        let (v, found) = lookup(it, n.text)
        if !found && it.limits.strict { ret (no_value(), Undefined) }
        ret (v, ok)
    }
    if n.kind == N_LIST {
        var items: [64]Value = zero
        try eval_args(it, n.b, n.c, items[0usize..64usize])
        let (rv24, re24) = make_list(it, items[0usize..usize(n.c)])
        ret (rv24, re24)
    }
    if n.kind == N_MAP {
        let (pairs, alloc_error) = mem.alloc[Pair](it.arena, usize(n.c) + 1usize)
        if alloc_error != ok { ret (no_value(), alloc_error) }
        var i = 0usize
        while i < usize(n.c) {
            let (k, ke) = eval(it, it.program.kids[usize(n.b) + i * 2usize])
            if ke != ok { ret (no_value(), ke) }
            let (v, ve) = eval(it, it.program.kids[usize(n.b) + i * 2usize + 1usize])
            if ve != ok { ret (no_value(), ve) }
            var key: str = ""
            switch k {
            case .Str as s:
                key = s
            default:
                ret (no_value(), Type)
            }
            pairs[i] = Pair { key: key, value: v }
            i += 1usize
        }
        ret (Value { Map: pairs[0usize..usize(n.c)] }, ok)
    }
    if n.kind == N_AND {
        let (l, le) = eval(it, n.a)
        if le != ok { ret (no_value(), le) }
        if !truthy(l) { ret (Value { Bool: false }, ok) }
        let (r, re) = eval(it, n.b)
        if re != ok { ret (no_value(), re) }
        ret (Value { Bool: truthy(r) }, ok)
    }
    if n.kind == N_OR {
        let (l, le) = eval(it, n.a)
        if le != ok { ret (no_value(), le) }
        if truthy(l) { ret (Value { Bool: true }, ok) }
        let (r, re) = eval(it, n.b)
        if re != ok { ret (no_value(), re) }
        ret (Value { Bool: truthy(r) }, ok)
    }
    if n.kind == N_TERNARY {
        let (c, ce) = eval(it, n.a)
        if ce != ok { ret (no_value(), ce) }
        if truthy(c) {
            let (v, e) = eval(it, n.b)
            ret (v, e)
        }
        let (v, e) = eval(it, n.c)
        ret (v, e)
    }
    if n.kind == N_ELVIS {
        let (l, le) = eval(it, n.a)
        if le != ok { ret (no_value(), le) }
        if truthy(l) { ret (l, ok) }
        let (v, e) = eval(it, n.b)
        ret (v, e)
    }
    if n.kind == N_COALESCE {
        let (l, le) = eval(it, n.a)
        if le != ok { ret (no_value(), le) }
        switch l {
        case .Null:
            let (v, e) = eval(it, n.b)
            ret (v, e)
        default:
            ret (l, ok)
        }
    }
    if n.kind == N_RANGE {
        let (lo, le) = eval(it, n.a)
        if le != ok { ret (no_value(), le) }
        let (hi, he) = eval(it, n.b)
        if he != ok { ret (no_value(), he) }
        var from = 0i64
        var to = 0i64
        switch lo {
        case .Int as v:
            from = v
        default:
            ret (no_value(), Type)
        }
        switch hi {
        case .Int as v:
            to = v
        default:
            ret (no_value(), Type)
        }
        var count = 0i64
        if to >= from { count = to - from + 1i64 } else { count = from - to + 1i64 }
        if count > i64(it.limits.max_collection) { ret (no_value(), Limit) }
        let (items, alloc_error) = mem.alloc[Value](it.arena, usize(count) + 1usize)
        if alloc_error != ok { ret (no_value(), alloc_error) }
        var i = 0i64
        while i < count {
            var v = from + i
            if to < from { v = from - i }
            items[usize(i)] = Value { Int: v }
            i += 1i64
        }
        ret (Value { List: items[0usize..usize(count)] }, ok)
    }
    if n.kind == N_UNARY {
        let (x, xe) = eval(it, n.a)
        if xe != ok { ret (no_value(), xe) }
        if n.op == OP_NOT { ret (Value { Bool: !truthy(x) }, ok) }
        if n.op == OP_EMPTY { ret (Value { Bool: !truthy(x) }, ok) }
        if n.op == OP_SIZE {
            let (s, se) = size_of(x)
            if se != ok { ret (no_value(), se) }
            ret (Value { Int: s }, ok)
        }
        if n.op == OP_NEG {
            switch x {
            case .Int as i:
                if i == -9223372036854775807i64 - 1i64 { ret (no_value(), Overflow) }
                ret (Value { Int: 0i64 - i }, ok)
            case .Float as f:
                ret (Value { Float: 0.0f64 - f }, ok)
            default:
                ret (no_value(), Type)
            }
        }
        if n.op == OP_POS {
            if is_number(x) { ret (x, ok) }
            ret (no_value(), Type)
        }
        ret (no_value(), Type)
    }
    if n.kind == N_BINARY {
        let (x, xe) = eval(it, n.a)
        if xe != ok { ret (no_value(), xe) }
        let (y, ye) = eval(it, n.b)
        if ye != ok { ret (no_value(), ye) }
        if n.op == OP_EQ { ret (Value { Bool: equals(x, y) }, ok) }
        if n.op == OP_NE { ret (Value { Bool: !equals(x, y) }, ok) }
        if n.op == OP_IN || n.op == OP_NIN {
            let (found, ce) = contains(y, x)
            if ce != ok { ret (no_value(), ce) }
            if n.op == OP_NIN { ret (Value { Bool: !found }, ok) }
            ret (Value { Bool: found }, ok)
        }
        if n.op == OP_STARTS || n.op == OP_ENDS {
            var s: str = ""
            var t: str = ""
            switch x {
            case .Str as v:
                s = v
            default:
                ret (no_value(), Type)
            }
            switch y {
            case .Str as v:
                t = v
            default:
                ret (no_value(), Type)
            }
            if t.len > s.len { ret (Value { Bool: false }, ok) }
            if n.op == OP_STARTS { ret (Value { Bool: same(s[0usize..t.len], t) }, ok) }
            ret (Value { Bool: same(s[s.len - t.len..s.len], t) }, ok)
        }
        if n.op == OP_LT || n.op == OP_LE || n.op == OP_GT || n.op == OP_GE {
            let (c, ce) = compare(x, y)
            if ce != ok { ret (no_value(), ce) }
            if c == 2i32 { ret (Value { Bool: false }, ok) }
            if n.op == OP_LT { ret (Value { Bool: c < 0i32 }, ok) }
            if n.op == OP_LE { ret (Value { Bool: c <= 0i32 }, ok) }
            if n.op == OP_GT { ret (Value { Bool: c > 0i32 }, ok) }
            ret (Value { Bool: c >= 0i32 }, ok)
        }
        let (v, e) = arith(it, n.op, x, y)
        ret (v, e)
    }
    if n.kind == N_PROP {
        let (base, be) = eval(it, n.a)
        if be != ok { ret (no_value(), be) }
        switch base {
        case .Null:
            if n.op == 1u8 { ret (no_value(), ok) }
            if it.limits.strict { ret (no_value(), Undefined) }
            ret (no_value(), ok)
        case .Map as m:
            let (v, found) = map_get(m, n.text)
            if !found && it.limits.strict { ret (no_value(), Undefined) }
            ret (v, ok)
        case .Object as handle:
            let (v, found) = it.host.get(it.host.ctx, it.arena, handle, n.text)
            if !found && it.limits.strict { ret (no_value(), Undefined) }
            if !found { ret (no_value(), ok) }
            ret (v, ok)
        default:
            ret (no_value(), Type)
        }
    }
    if n.kind == N_INDEX {
        let (base, be) = eval(it, n.a)
        if be != ok { ret (no_value(), be) }
        let (index, ie) = eval(it, n.b)
        if ie != ok { ret (no_value(), ie) }
        switch base {
        case .Null:
            if n.op == 1u8 { ret (no_value(), ok) }
            ret (no_value(), Type)
        case .List as l:
            switch index {
            case .Int as i:
                if i < 0i64 || i >= i64(l.len) { ret (no_value(), Index) }
                ret (l[usize(i)], ok)
            default:
                ret (no_value(), Type)
            }
        case .Str as s:
            switch index {
            case .Int as i:
                if i < 0i64 || i >= i64(s.len) { ret (no_value(), Index) }
                let (buf, alloc_error) = mem.alloc[u8](it.arena, 1usize)
                if alloc_error != ok { ret (no_value(), alloc_error) }
                buf[0usize] = s[usize(i)]
                ret (Value { Str: buf[0usize..1usize] }, ok)
            default:
                ret (no_value(), Type)
            }
        case .Map as m:
            switch index {
            case .Str as key:
                let (v, found) = map_get(m, key)
                if !found && it.limits.strict { ret (no_value(), Undefined) }
                ret (v, ok)
            default:
                ret (no_value(), Type)
            }
        case .Object as handle:
            switch index {
            case .Str as key:
                let (v, found) = it.host.get(it.host.ctx, it.arena, handle, key)
                if !found && it.limits.strict { ret (no_value(), Undefined) }
                ret (v, ok)
            default:
                ret (no_value(), Type)
            }
        default:
            ret (no_value(), Type)
        }
    }
    if n.kind == N_CALL {
        var args: [32]Value = zero
        try eval_args(it, n.b, n.c, args[0usize..32usize])
        let (v, e) = call_function(it, n.text, args[0usize..usize(n.c)])
        ret (v, e)
    }
    if n.kind == N_METHOD {
        let (base, be) = eval(it, n.a)
        if be != ok { ret (no_value(), be) }
        var args: [32]Value = zero
        try eval_args(it, n.b, n.c, args[0usize..32usize])
        switch base {
        case .Null:
            if n.op == 1u8 { ret (no_value(), ok) }
            ret (no_value(), Type)
        case .Object as handle:
            let (v, e) = it.host.call(it.host.ctx, it.arena, handle, n.text, args[0usize..usize(n.c)])
            ret (v, e)
        default:
            let (v, e) = builtin_method(it, base, n.text, args[0usize..usize(n.c)])
            ret (v, e)
        }
    }
    ret (no_value(), Type)
}

fn int_arg(args: []const Value, i: usize) -> (i64, bool) {
    if i >= args.len { ret (0i64, false) }
    switch args[i] {
    case .Int as v:
        ret (v, true)
    default:
        ret (0i64, false)
    }
}

fn str_arg(args: []const Value, i: usize) -> (str, bool) {
    if i >= args.len { ret ("", false) }
    switch args[i] {
    case .Str as v:
        ret (v, true)
    default:
        ret ("", false)
    }
}

fn lower_of(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn upper_of(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}

fn new_string(it: *Interp, len: usize) -> ([]u8, err) {
    if len > it.limits.max_string { ret (zero, Limit) }
    let (buf, alloc_error) = mem.alloc[u8](it.arena, len + 1usize)
    ret (buf, alloc_error)
}

fn find_text(s: str, needle: str, from: usize) -> i64 {
    var i = from
    while i + needle.len <= s.len {
        if same(s[i..i + needle.len], needle) { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

// Whitelisted methods of the built-in value kinds.
fn builtin_method(it: *Interp, base: Value, name: str, args: []const Value) -> (Value, err) {
    switch base {
    case .Str as s:
        if same(name, "length") || same(name, "size") { ret (Value { Int: i64(s.len) }, ok) }
        if same(name, "isEmpty") { ret (Value { Bool: s.len == 0usize }, ok) }
        if same(name, "toUpperCase") || same(name, "toLowerCase") {
            let (buf, e) = new_string(it, s.len)
            if e != ok { ret (no_value(), e) }
            var i = 0usize
            while i < s.len {
                if same(name, "toUpperCase") {
                    buf[i] = upper_of(s[i])
                } else {
                    buf[i] = lower_of(s[i])
                }
                i += 1usize
            }
            ret (Value { Str: buf[0usize..s.len] }, ok)
        }
        if same(name, "trim") {
            var a = 0usize
            var b = s.len
            while a < b && (s[a] == 32u8 || s[a] == 9u8 || s[a] == 10u8 || s[a] == 13u8) { a += 1usize }
            while b > a && (s[b - 1usize] == 32u8 || s[b - 1usize] == 9u8 || s[b - 1usize] == 10u8 || s[b - 1usize] == 13u8) { b -= 1usize }
            ret (Value { Str: s[a..b] }, ok)
        }
        if same(name, "contains") || same(name, "startsWith") || same(name, "endsWith") || same(name, "indexOf") {
            let (needle, good) = str_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            if same(name, "contains") { ret (Value { Bool: find_text(s, needle, 0usize) >= 0i64 }, ok) }
            if same(name, "indexOf") { ret (Value { Int: find_text(s, needle, 0usize) }, ok) }
            if needle.len > s.len { ret (Value { Bool: false }, ok) }
            if same(name, "startsWith") { ret (Value { Bool: same(s[0usize..needle.len], needle) }, ok) }
            ret (Value { Bool: same(s[s.len - needle.len..s.len], needle) }, ok)
        }
        if same(name, "substring") {
            let (from, good) = int_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            var to = i64(s.len)
            if args.len > 1usize {
                let (t, tg) = int_arg(args, 1usize)
                if !tg { ret (no_value(), Type) }
                to = t
            }
            if from < 0i64 || to > i64(s.len) || from > to { ret (no_value(), Index) }
            ret (Value { Str: s[usize(from)..usize(to)] }, ok)
        }
        if same(name, "charAt") {
            let (i, good) = int_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            if i < 0i64 || i >= i64(s.len) { ret (no_value(), Index) }
            ret (Value { Str: s[usize(i)..usize(i) + 1usize] }, ok)
        }
        if same(name, "concat") {
            let (other, good) = str_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            let (buf, e) = new_string(it, s.len + other.len)
            if e != ok { ret (no_value(), e) }
            var i = 0usize
            while i < s.len {
                buf[i] = s[i]
                i += 1usize
            }
            i = 0usize
            while i < other.len {
                buf[s.len + i] = other[i]
                i += 1usize
            }
            ret (Value { Str: buf[0usize..s.len + other.len] }, ok)
        }
        ret (no_value(), Denied)
    case .List as l:
        if same(name, "size") || same(name, "length") { ret (Value { Int: i64(l.len) }, ok) }
        if same(name, "isEmpty") { ret (Value { Bool: l.len == 0usize }, ok) }
        if same(name, "contains") {
            if args.len != 1usize { ret (no_value(), Type) }
            let (found, e) = contains(base, args[0usize])
            if e != ok { ret (no_value(), e) }
            ret (Value { Bool: found }, ok)
        }
        if same(name, "get") {
            let (i, good) = int_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            if i < 0i64 || i >= i64(l.len) { ret (no_value(), Index) }
            ret (l[usize(i)], ok)
        }
        if same(name, "indexOf") {
            if args.len != 1usize { ret (no_value(), Type) }
            var i = 0usize
            while i < l.len {
                if equals(l[i], args[0usize]) { ret (Value { Int: i64(i) }, ok) }
                i += 1usize
            }
            ret (Value { Int: -1i64 }, ok)
        }
        if same(name, "join") {
            let (sep, good) = str_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            let (b0, be) = str.builder(it.arena, 256usize)
            if be != ok { ret (no_value(), be) }
            var b = b0
            var i = 0usize
            while i < l.len {
                if i > 0usize {
                    let pe = str.push(&b, sep)
                    if pe != ok { ret (no_value(), pe) }
                }
                let ve = push_value(&b, l[i], 0u32)
                if ve != ok { ret (no_value(), ve) }
                i += 1usize
            }
            let text = str.done(&b)
            if text.len > it.limits.max_string { ret (no_value(), Limit) }
            ret (Value { Str: text }, ok)
        }
        ret (no_value(), Denied)
    case .Map as m:
        if same(name, "size") { ret (Value { Int: i64(m.len) }, ok) }
        if same(name, "isEmpty") { ret (Value { Bool: m.len == 0usize }, ok) }
        if same(name, "containsKey") {
            let (key, good) = str_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            let (v, found) = map_get(m, key)
            ret (Value { Bool: found }, ok)
        }
        if same(name, "get") {
            let (key, good) = str_arg(args, 0usize)
            if !good { ret (no_value(), Type) }
            let (v, found) = map_get(m, key)
            ret (v, ok)
        }
        if same(name, "keys") || same(name, "values") {
            let (items, e) = mem.alloc[Value](it.arena, m.len + 1usize)
            if e != ok { ret (no_value(), e) }
            var i = 0usize
            while i < m.len {
                if same(name, "keys") {
                    items[i] = Value { Str: m[i].key }
                } else {
                    items[i] = m[i].value
                }
                i += 1usize
            }
            ret (Value { List: items[0usize..m.len] }, ok)
        }
        ret (no_value(), Denied)
    default:
        ret (no_value(), Denied)
    }
}

fn call_function(it: *Interp, name: str, args: []const Value) -> (Value, err) {
    // built-ins first: a host cannot be asked to redefine them, which keeps the whitelist fixed
    if same(name, "size") {
        if args.len != 1usize { ret (no_value(), Type) }
        let (n, e) = size_of(args[0usize])
        if e != ok { ret (no_value(), e) }
        ret (Value { Int: n }, ok)
    }
    if same(name, "empty") {
        if args.len != 1usize { ret (no_value(), Type) }
        ret (Value { Bool: !truthy(args[0usize]) }, ok)
    }
    if same(name, "str") {
        if args.len != 1usize { ret (no_value(), Type) }
        let (text, e) = text_of(it.arena, args[0usize], it.limits.max_string)
        if e != ok { ret (no_value(), e) }
        ret (Value { Str: text }, ok)
    }
    if same(name, "int") {
        if args.len != 1usize { ret (no_value(), Type) }
        switch args[0usize] {
        case .Int as i:
            ret (Value { Int: i }, ok)
        case .Float as f:
            if !(f == f) || f > 9.2e18f64 || f < -9.2e18f64 { ret (no_value(), Overflow) }
            ret (Value { Int: i64(f) }, ok)
        case .Str as s:
            let (v, e) = str.parse_i64(s)
            if e != ok { ret (no_value(), Type) }
            ret (Value { Int: v }, ok)
        case .Bool as b:
            if b { ret (Value { Int: 1i64 }, ok) }
            ret (Value { Int: 0i64 }, ok)
        default:
            ret (no_value(), Type)
        }
    }
    if same(name, "float") {
        if args.len != 1usize { ret (no_value(), Type) }
        switch args[0usize] {
        case .Int as i:
            ret (Value { Float: f64(i) }, ok)
        case .Float as f:
            ret (Value { Float: f }, ok)
        case .Str as s:
            let (v, e) = str.parse_f64(s)
            if e != ok { ret (no_value(), Type) }
            ret (Value { Float: v }, ok)
        default:
            ret (no_value(), Type)
        }
    }
    if same(name, "abs") {
        if args.len != 1usize { ret (no_value(), Type) }
        switch args[0usize] {
        case .Int as i:
            if i == -9223372036854775807i64 - 1i64 { ret (no_value(), Overflow) }
            if i < 0i64 { ret (Value { Int: 0i64 - i }, ok) }
            ret (Value { Int: i }, ok)
        case .Float as f:
            if f < 0.0f64 { ret (Value { Float: 0.0f64 - f }, ok) }
            ret (Value { Float: f }, ok)
        default:
            ret (no_value(), Type)
        }
    }
    if same(name, "min") || same(name, "max") {
        if args.len != 2usize { ret (no_value(), Type) }
        let (c, e) = compare(args[0usize], args[1usize])
        if e != ok { ret (no_value(), e) }
        if c == 2i32 { ret (no_value(), Type) }
        if same(name, "min") {
            if c <= 0i32 { ret (args[0usize], ok) }
            ret (args[1usize], ok)
        }
        if c >= 0i32 { ret (args[0usize], ok) }
        ret (args[1usize], ok)
    }
    if same(name, "floor") || same(name, "ceil") || same(name, "round") {
        if args.len != 1usize { ret (no_value(), Type) }
        switch args[0usize] {
        case .Int as i:
            ret (Value { Int: i }, ok)
        case .Float as f:
            if !(f == f) || f > 9.0e15f64 || f < -9.0e15f64 { ret (no_value(), Overflow) }
            var t = i64(f)
            if same(name, "floor") {
                if f64(t) > f { t -= 1i64 }
            } else if same(name, "ceil") {
                if f64(t) < f { t += 1i64 }
            } else {
                // round half up, as Math.round does
                var r = f + 0.5f64
                var u = i64(r)
                if f64(u) > r { u -= 1i64 }
                t = u
            }
            ret (Value { Int: t }, ok)
        default:
            ret (no_value(), Type)
        }
    }
    let (v, e) = it.host.function(it.host.ctx, it.arena, name, args)
    ret (v, e)
}

// Evaluates `source` over `scope` and `host` under `limits`, results allocated in `a`.
fn evaluate(a: *mem.Arena, source: str, scope: []const Binding, host: Host, limits: Limits) -> (Value, err) {
    let (prog, compile_error) = compile(a, source, limits)
    if compile_error != ok { ret (no_value(), compile_error) }
    let (rv25, re25) = run(a, &prog, scope, host, limits)
    ret (rv25, re25)
}

// Runs a compiled program (compile once, run against many scopes).
fn run(a: *mem.Arena, prog: *const Program, scope: []const Binding, host: Host, limits: Limits) -> (Value, err) {
    var it: Interp = zero
    it.arena = a
    it.host = host
    it.scope = scope
    it.program = prog
    it.limits = limits
    if it.limits.max_depth == 0u32 { it.limits.max_depth = 64u32 }
    if it.limits.max_string == 0usize { it.limits.max_string = 65536usize }
    if it.limits.max_collection == 0usize { it.limits.max_collection = 10000usize }
    let (v, e) = eval(&it, prog.root)
    ret (v, e)
}
