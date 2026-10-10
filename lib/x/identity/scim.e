// SCIM 2.0 protocol core, RFC 7643 and RFC 7644 (L045), after Appdor's `src/identity/scim-protocol.js`, over JSON values:
// the filter grammar (`eq ne co sw ew gt ge lt le pr`, `and`, `or`, `not`, groups, value paths `emails[type eq "work"]`)
// parsed to a node tree and evaluated case-insensitively; the PATCH path grammar and `add`/`replace`/`remove`
// applied immutably (Okta's pathless `replace` of `{"active": false}` included); `attributes` and `excludedAttributes`
// projection; the ListResponse and Error envelopes; the content-derived `meta.version`; User and Group serialisation; the
// ServiceProviderConfig and ResourceTypes documents; and attribute sorting.
//
// ponytail: an array used as the value of a pathless `add`, or a string as the value of a filtered `replace`, is not
// spread element by element as JavaScript's `...` does; a patched leaf set to `undefined` is removed, where the
// reference leaves a key that reads as absent; sorting is a stable insertion sort, which agrees with the reference for
// comparators that are consistent (one type per attribute).
//
// Memory: the arena is retained.

use e.algo.chain as chain
use e.algo.formula as f
use e.algo.formula.text as tx
use e.algo.ir as ir
use e.fmt.json as json
use e.mem
use e.str

type Token = struct { kind: u8, value: str }

// kind: 0 and, 1 or, 2 not, 3 present, 4 value path, 5 compare. op: 0 eq .. 8 le.
type Node = struct { kind: u8, op: u8, attribute: str, path: str, left: usize, right: usize, value: json.Value }

type Parser = struct { tokens: []const Token, pos: usize, nodes: []Node, count: usize, failed: bool, message: str }

type Filter = struct { valid: bool, message: str, nodes: []const Node, root: usize }

type PatchPath = struct { attribute: str, has_filter: bool, filter: Filter, has_sub: bool, sub: str, has_error: bool, message: str }

type Patched = struct { valid: bool, message: str, resource: json.Value }

type Page = struct { start_index: f64, total: json.Value, resources: []const json.Value }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn is_sep(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 40u8 || c == 41u8 || c == 91u8 || c == 93u8 }

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn same_lower(a: *mem.Arena, x: str, y: str) -> bool { ret str.eq(lower(a, x), lower(a, y)) }

// --- filter tokens and parser --------------------------------------------------------------------------------

fn tokenize(a: *mem.Arena, s: str) -> []const Token {
    let (out, e) = mem.alloc[Token](a, s.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let ch = s[i]
        if ch == 32u8 || ch == 9u8 || ch == 10u8 {
            i += 1usize
            continue
        }
        if ch == 40u8 || ch == 41u8 || ch == 91u8 || ch == 93u8 {
            out[n] = Token { kind: 0u8, value: s[i..i + 1usize] }
            n += 1usize
            i += 1usize
            continue
        }
        if ch == 34u8 {
            i += 1usize
            let (buf, be) = mem.alloc[u8](a, s.len + 1usize)
            if be != ok { ret zero }
            var len = 0usize
            while i < s.len && s[i] != 34u8 {
                if s[i] == 92u8 && i + 1usize < s.len {
                    buf[len] = s[i + 1usize]
                    len += 1usize
                    i += 2usize
                    continue
                }
                buf[len] = s[i]
                len += 1usize
                i += 1usize
            }
            i += 1usize
            out[n] = Token { kind: 1u8, value: buf[0usize..len] }
            n += 1usize
            continue
        }
        let from = i
        while i < s.len && !is_sep(s[i]) { i += 1usize }
        out[n] = Token { kind: 2u8, value: s[from..i] }
        n += 1usize
    }
    ret out[0usize..n]
}

fn fail(p: *Parser, message: str) -> usize {
    if !p.failed {
        p.failed = true
        p.message = message
    }
    ret 0usize
}

fn new_node(p: *Parser, n: Node) -> usize {
    p.nodes[p.count] = n
    p.count += 1usize
    ret p.count - 1usize
}

fn blank(kind: u8) -> Node {
    ret Node { kind: kind, op: 0u8, attribute: "", path: "", left: 0usize, right: 0usize, value: .Null }
}

fn is_number_literal(s: str) -> bool {
    var i = 0usize
    if i < s.len && s[i] == 45u8 { i += 1usize }
    var digits = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        i += 1usize
        digits += 1usize
    }
    if digits == 0usize { ret false }
    if i == s.len { ret true }
    if s[i] != 46u8 { ret false }
    i += 1usize
    var frac = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        i += 1usize
        frac += 1usize
    }
    ret frac > 0usize && i == s.len
}

fn literal(t: Token) -> json.Value {
    if t.kind == 1u8 { ret sv(t.value) }
    if str.eq(t.value, "true") { ret json.Value{ Bool: true } }
    if str.eq(t.value, "false") { ret json.Value{ Bool: false } }
    if str.eq(t.value, "null") { ret .Null }
    if is_number_literal(t.value) { ret json.Value{ Number: json.Number{ lexeme: t.value } } }
    ret sv(t.value)
}

fn op_code(a: *mem.Arena, s: str) -> i32 {
    let l = lower(a, s)
    let names = [9]str{ "eq", "ne", "co", "sw", "ew", "gt", "ge", "lt", "le" }
    var i = 0usize
    while i < 9usize {
        if str.eq(names[i], l) { ret i32(i) }
        i += 1usize
    }
    ret -1i32
}

fn peek_value_is(p: *Parser, v: str) -> bool {
    ret p.pos < p.tokens.len && str.eq(p.tokens[p.pos].value, v)
}

fn peek_word_is(a: *mem.Arena, p: *Parser, v: str) -> bool {
    ret p.pos < p.tokens.len && p.tokens[p.pos].kind == 2u8 && str.eq(lower(a, p.tokens[p.pos].value), v)
}

fn parse_value_path(a: *mem.Arena, p: *Parser, attr: str) -> usize {
    p.pos += 1usize
    let inner = parse_or(a, p)
    if p.failed { ret 0usize }
    if !peek_value_is(p, "]") { ret fail(p, "unclosed value filter") }
    p.pos += 1usize
    var full = attr
    if p.pos < p.tokens.len && p.tokens[p.pos].kind == 2u8 && p.tokens[p.pos].value.len > 0usize && p.tokens[p.pos].value[0] == 46u8 {
        full = join(a, attr, p.tokens[p.pos].value)
        p.pos += 1usize
    }
    var n = blank(4u8)
    n.attribute = attr
    n.path = full
    n.left = inner
    ret new_node(p, n)
}

fn parse_primary(a: *mem.Arena, p: *Parser) -> usize {
    if p.pos >= p.tokens.len { ret fail(p, "unexpected end of filter") }
    let token = p.tokens[p.pos]
    if str.eq(token.value, "(") {
        p.pos += 1usize
        let node = parse_or(a, p)
        if p.failed { ret 0usize }
        if !peek_value_is(p, ")") { ret fail(p, "unclosed group") }
        p.pos += 1usize
        ret node
    }
    if token.kind == 2u8 && str.eq(lower(a, token.value), "not") {
        p.pos += 1usize
        let operand = parse_primary(a, p)
        if p.failed { ret 0usize }
        var n = blank(2u8)
        n.left = operand
        ret new_node(p, n)
    }
    if token.kind != 2u8 { ret fail(p, join(a, "expected attribute, got ", token.value)) }
    let attr = token.value
    p.pos += 1usize
    if peek_value_is(p, "[") { ret parse_value_path(a, p, attr) }
    if p.pos >= p.tokens.len { ret fail(p, join(a, "expected operator after ", attr)) }
    let op_token = p.tokens[p.pos]
    let op_text = lower(a, op_token.value)
    if str.eq(op_text, "pr") {
        p.pos += 1usize
        var n = blank(3u8)
        n.attribute = attr
        ret new_node(p, n)
    }
    let code = op_code(a, op_token.value)
    if code < 0i32 { ret fail(p, join(a, "unknown operator: ", op_token.value)) }
    p.pos += 1usize
    if p.pos >= p.tokens.len { ret fail(p, join(a, join(a, "expected value after ", op_text), "")) }
    let value_token = p.tokens[p.pos]
    p.pos += 1usize
    var n = blank(5u8)
    n.op = u8(code)
    n.attribute = attr
    n.value = literal(value_token)
    ret new_node(p, n)
}

fn parse_and(a: *mem.Arena, p: *Parser) -> usize {
    var left = parse_primary(a, p)
    if p.failed { ret 0usize }
    while peek_word_is(a, p, "and") {
        p.pos += 1usize
        let right = parse_primary(a, p)
        if p.failed { ret 0usize }
        var n = blank(0u8)
        n.left = left
        n.right = right
        left = new_node(p, n)
    }
    ret left
}

fn parse_or(a: *mem.Arena, p: *Parser) -> usize {
    var left = parse_and(a, p)
    if p.failed { ret 0usize }
    while peek_word_is(a, p, "or") {
        p.pos += 1usize
        let right = parse_and(a, p)
        if p.failed { ret 0usize }
        var n = blank(1u8)
        n.left = left
        n.right = right
        left = new_node(p, n)
    }
    ret left
}

// A filter parsed to a node tree; `valid` false carries the reference's message.
fn parse_filter(a: *mem.Arena, input: str) -> Filter {
    let tokens = tokenize(a, input)
    let none: []const Node = zero
    if tokens.len == 0usize { ret Filter { valid: false, message: "empty filter", nodes: none, root: 0usize } }
    let (nodes, e) = mem.alloc[Node](a, tokens.len * 2usize + 4usize)
    if e != ok { ret Filter { valid: false, message: "invalid filter", nodes: none, root: 0usize } }
    var p = Parser { tokens: tokens, pos: 0usize, nodes: nodes, count: 0usize, failed: false, message: "" }
    let root = parse_or(a, &p)
    if p.failed { ret Filter { valid: false, message: p.message, nodes: none, root: 0usize } }
    if p.pos != tokens.len { ret Filter { valid: false, message: join(a, "unexpected token: ", tokens[p.pos].value), nodes: none, root: 0usize } }
    ret Filter { valid: true, message: "", nodes: nodes[0usize..p.count], root: root }
}

// --- attribute lookup and comparison -------------------------------------------------------------------------

// `key in object`, else the first key equal ignoring case.
fn find_key(a: *mem.Arena, object: json.Value, key: str) -> (json.Value, bool) {
    let (members, is_object) = ir.members_of(object)
    if !is_object { ret (.Null, false) }
    var i = 0usize
    while i < members.len {
        if str.eq(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    let want = lower(a, key)
    i = 0usize
    while i < members.len {
        if str.eq(lower(a, members[i].key), want) { ret (members[i].value, true) }
        i += 1usize
    }
    ret (.Null, false)
}

// A dotted path read out of a resource; found is false for `undefined`. An array maps the part over its elements.
fn get_attribute(a: *mem.Arena, resource: json.Value, path: str) -> (json.Value, bool) {
    var node = resource
    var start = 0usize
    var at = 0usize
    while at <= path.len {
        if at == path.len || path[at] == 46u8 {
            let part = path[start..at]
            if ir.is_null(node) { ret (.Null, false) }
            let (items, is_array) = ir.items_of(node)
            if is_array {
                let (out, e) = mem.alloc[json.Value](a, items.len + 1usize)
                if e != ok { ret (.Null, false) }
                var n = 0usize
                var k = 0usize
                while k < items.len {
                    if !ir.is_null(items[k]) {
                        let (v, found) = find_key(a, items[k], part)
                        if found {
                            out[n] = v
                            n += 1usize
                        }
                    }
                    k += 1usize
                }
                if n == 0usize { ret (.Null, false) }
                node = json.Value{ Array: out[0usize..n] }
            } else {
                let (v, found) = find_key(a, node, part)
                if !found { ret (.Null, false) }
                node = v
            }
            start = at + 1usize
        }
        at += 1usize
    }
    ret (node, true)
}

fn number_of(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret x
    default:
        ret f.nan()
    }
}

// `String(v)` for the scalar kinds a filter compares.
fn text_value(a: *mem.Arena, v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    case .Number as n:
        ret f.number_text(a, number_of(v))
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Null:
        ret "null"
    default:
        ret "[object Object]"
    }
}

// JavaScript's ToNumber for a scalar.
fn to_number(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        ret number_of(v)
    case .Bool as b:
        if b { ret 1.0f64 }
        ret 0.0f64
    case .Null:
        ret 0.0f64
    case .String as s:
        var t = s
        var from = 0usize
        var to = t.len
        while from < to && (t[from] == 32u8 || t[from] == 9u8 || t[from] == 10u8 || t[from] == 13u8) { from += 1usize }
        while to > from && (t[to - 1usize] == 32u8 || t[to - 1usize] == 9u8 || t[to - 1usize] == 10u8 || t[to - 1usize] == 13u8) { to -= 1usize }
        t = t[from..to]
        if t.len == 0usize { ret 0.0f64 }
        let (x, e) = str.parse_f64(t)
        if e != ok { ret f.nan() }
        ret x
    default:
        ret f.nan()
    }
}

fn is_string(v: json.Value) -> bool {
    switch v {
    case .String as s:
        ret true
    default:
        ret false
    }
}

fn strict_equal(x: json.Value, y: json.Value) -> bool {
    switch x {
    case .String as xs:
        switch y {
        case .String as ys:
            ret str.eq(xs, ys)
        default:
            ret false
        }
    case .Number as xn:
        switch y {
        case .Number as yn:
            ret number_of(x) == number_of(y)
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
    case .Null:
        ret ir.is_null(y)
    default:
        ret false
    }
}

fn lowered_value(a: *mem.Arena, v: json.Value) -> json.Value {
    switch v {
    case .String as s:
        ret sv(lower(a, s))
    default:
        ret v
    }
}

// `a < b` for scalars: two strings by code units, otherwise by number; false when either is NaN.
fn less(x: json.Value, y: json.Value) -> bool {
    if is_string(x) && is_string(y) {
        var xs = ""
        var ys = ""
        switch x {
        case .String as s:
            xs = s
        default:
            xs = ""
        }
        switch y {
        case .String as s:
            ys = s
        default:
            ys = ""
        }
        ret str.compare(xs, ys) < 0i32
    }
    ret to_number(x) < to_number(y)
}

fn compare_values(a: *mem.Arena, actual: json.Value, found: bool, op: u8, expected: json.Value) -> bool {
    if !found || ir.is_null(actual) { ret op == 1u8 }
    let x = lowered_value(a, actual)
    let y = lowered_value(a, expected)
    if op == 0u8 { ret strict_equal(x, y) }
    if op == 1u8 { ret !strict_equal(x, y) }
    if op == 2u8 || op == 3u8 || op == 4u8 {
        let sx = text_value(a, x)
        let sy = text_value(a, y)
        if op == 2u8 { ret str.contains(sx, sy) }
        if op == 3u8 { ret str.starts_with(sx, sy) }
        ret str.ends_with(sx, sy)
    }
    if op == 5u8 { ret less(y, x) }
    if op == 6u8 {
        let nx = to_number(x)
        let ny = to_number(y)
        if is_string(x) && is_string(y) { ret !less(x, y) }
        ret nx >= ny
    }
    if op == 7u8 { ret less(x, y) }
    if is_string(x) && is_string(y) { ret !less(y, x) }
    ret to_number(x) <= to_number(y)
}

fn eval(a: *mem.Arena, nodes: []const Node, at: usize, resource: json.Value) -> bool {
    let n = nodes[at]
    if n.kind == 0u8 { ret eval(a, nodes, n.left, resource) && eval(a, nodes, n.right, resource) }
    if n.kind == 1u8 { ret eval(a, nodes, n.left, resource) || eval(a, nodes, n.right, resource) }
    if n.kind == 2u8 { ret !eval(a, nodes, n.left, resource) }
    let (value, found) = get_attribute(a, resource, n.attribute)
    if n.kind == 3u8 {
        let (items, is_array) = ir.items_of(value)
        if found && is_array { ret items.len > 0usize }
        if !found || ir.is_null(value) { ret false }
        switch value {
        case .String as s:
            ret s.len > 0usize
        default:
            ret true
        }
    }
    if n.kind == 4u8 {
        let (items, is_array) = ir.items_of(value)
        if !found || !is_array { ret false }
        var i = 0usize
        while i < items.len {
            if eval(a, nodes, n.left, items[i]) { ret true }
            i += 1usize
        }
        ret false
    }
    let (items, is_array) = ir.items_of(value)
    if found && is_array {
        var i = 0usize
        while i < items.len {
            if compare_values(a, items[i], true, n.op, n.value) { ret true }
            i += 1usize
        }
        ret false
    }
    ret compare_values(a, value, found, n.op, n.value)
}

// A parsed filter against one resource.
fn evaluate(a: *mem.Arena, filter: Filter, resource: json.Value) -> bool {
    if !filter.valid { ret true }
    ret eval(a, filter.nodes, filter.root, resource)
}

// --- PATCH ---------------------------------------------------------------------------------------------------

fn index_of(s: str, c: u8) -> i64 {
    var i = 0usize
    while i < s.len {
        if s[i] == c { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

fn last_index_of(s: str, c: u8) -> i64 {
    var i = s.len
    while i > 0usize {
        if s[i - 1usize] == c { ret i64(i - 1usize) }
        i -= 1usize
    }
    ret -1i64
}

fn slice_of(s: str, from: i64, to: i64) -> str {
    var lo = from
    var hi = to
    if lo < 0i64 { lo = 0i64 }
    if hi > i64(s.len) { hi = i64(s.len) }
    if lo >= hi { ret "" }
    ret s[usize(lo)..usize(hi)]
}

fn no_filter() -> Filter {
    let none: []const Node = zero
    ret Filter { valid: false, message: "", nodes: none, root: 0usize }
}

// A PATCH `path`: the attribute, an optional value filter and an optional sub-attribute.
fn parse_patch_path(a: *mem.Arena, raw: str) -> PatchPath {
    let bracket = index_of(raw, 91u8)
    if bracket == -1i64 {
        let dot = index_of(raw, 46u8)
        if dot == -1i64 { ret PatchPath { attribute: raw, has_filter: false, filter: no_filter(), has_sub: false, sub: "", has_error: false, message: "" } }
        ret PatchPath { attribute: slice_of(raw, 0i64, dot), has_filter: false, filter: no_filter(), has_sub: true, sub: slice_of(raw, dot + 1i64, i64(raw.len)), has_error: false, message: "" }
    }
    let close = last_index_of(raw, 93u8)
    if close == -1i64 { ret PatchPath { attribute: raw, has_filter: false, filter: no_filter(), has_sub: false, sub: "", has_error: true, message: "unclosed value filter" } }
    let attribute = slice_of(raw, 0i64, bracket)
    let filter_text = slice_of(raw, bracket + 1i64, close)
    let rest = slice_of(raw, close + 1i64, i64(raw.len))
    let parsed = parse_filter(a, filter_text)
    var has_sub = false
    var sub = ""
    if rest.len > 0usize && rest[0] == 46u8 {
        has_sub = true
        sub = rest[1usize..]
    }
    if !parsed.valid { ret PatchPath { attribute: attribute, has_filter: false, filter: no_filter(), has_sub: has_sub, sub: sub, has_error: true, message: parsed.message } }
    ret PatchPath { attribute: attribute, has_filter: true, filter: parsed, has_sub: has_sub, sub: sub, has_error: false, message: "" }
}

fn object_of(a: *mem.Arena, v: json.Value) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    var obj = o
    let ae = ir.assign(&obj, v)
    ret obj
}

fn without(a: *mem.Arena, v: json.Value, key: str) -> json.Value {
    let (members, is_object) = ir.members_of(v)
    let (o, e) = ir.new_obj(a)
    var obj = o
    var i = 0usize
    while i < members.len {
        if !str.eq(members[i].key, key) { let pe = ir.put(&obj, members[i].key, members[i].value) }
        i += 1usize
    }
    ret ir.obj_value(&obj)
}

// `target` with the value at `parts` set (an absent value removes the leaf), copying every object on the way.
fn set_path(a: *mem.Arena, base: json.Value, parts: []const str, at: usize, value: json.Value, has_value: bool) -> json.Value {
    var obj = object_of(a, base)
    if at + 1usize == parts.len {
        if has_value {
            let pe = ir.put(&obj, parts[at], value)
            ret ir.obj_value(&obj)
        }
        ret without(a, ir.obj_value(&obj), parts[at])
    }
    let child = ir.value_of(ir.obj_value(&obj), parts[at])
    let next = set_path(a, child, parts, at + 1usize, value, has_value)
    let pe = ir.put(&obj, parts[at], next)
    ret ir.obj_value(&obj)
}

fn split_dots(a: *mem.Arena, attribute: str, sub: str, has_sub: bool) -> []const str {
    let (out, e) = mem.alloc[str](a, sub.len + 2usize)
    var n = 0usize
    out[0] = attribute
    n = 1usize
    if has_sub {
        var start = 0usize
        var i = 0usize
        while i <= sub.len {
            if i == sub.len || sub[i] == 46u8 {
                out[n] = sub[start..i]
                n += 1usize
                start = i + 1usize
            }
            i += 1usize
        }
    }
    ret out[0usize..n]
}

fn patch_failed(msg: str) -> Patched { ret Patched { valid: false, message: msg, resource: .Null } }

// One PATCH operation (`{op, path?, value?}`) applied to a resource, immutably.
fn apply_patch_op(a: *mem.Arena, resource: json.Value, operation: json.Value) -> Patched {
    let op_value = ir.value_of(operation, "op")
    var op_raw = ""
    if ir.truthy(op_value) { op_raw = text_value(a, op_value) }
    let op = lower(a, op_raw)
    let (path_value, has_path_key) = ir.get(operation, "path")
    var path = ""
    if has_path_key && ir.truthy(path_value) { path = text_value(a, path_value) }
    let (value, has_value) = ir.get(operation, "value")
    if !(str.eq(op, "add") || str.eq(op, "replace") || str.eq(op, "remove")) {
        var shown = "undefined"
        if ir.truthy(operation) {
            let (ov, has_op) = ir.get(operation, "op")
            if has_op { shown = text_value(a, ov) }
        } else if ir.is_null(operation) {
            shown = "null"
        }
        ret patch_failed(join(a, "unsupported op: ", shown))
    }
    if path.len == 0usize {
        if str.eq(op, "remove") { ret patch_failed("remove requires a path") }
        let (members, is_object) = ir.members_of(value)
        if !has_value || ir.is_null(value) || !is_object {
            ret patch_failed(join(a, join(a, op, " without a path needs an object value"), ""))
        }
        var obj = object_of(a, resource)
        let ae = ir.assign(&obj, value)
        ret Patched { valid: true, message: "", resource: ir.obj_value(&obj) }
    }
    let parsed = parse_patch_path(a, path)
    if parsed.has_error { ret patch_failed(parsed.message) }
    let (current, has_current) = find_key(a, resource, parsed.attribute)
    if parsed.has_filter {
        let (items, is_array) = ir.items_of(current)
        if !has_current || !is_array { ret patch_failed(join(a, "not a multi-valued attribute: ", parsed.attribute)) }
        let (out, e) = mem.alloc[json.Value](a, items.len + 1usize)
        if e != ok { ret patch_failed("out of memory") }
        var n = 0usize
        var i = 0usize
        while i < items.len {
            let element = items[i]
            i += 1usize
            if !evaluate(a, parsed.filter, element) {
                out[n] = element
                n += 1usize
                continue
            }
            if str.eq(op, "remove") && !parsed.has_sub { continue }
            if str.eq(op, "remove") {
                out[n] = without(a, element, parsed.sub)
                n += 1usize
                continue
            }
            var copy = object_of(a, element)
            if parsed.has_sub {
                if has_value { let pe = ir.put(&copy, parsed.sub, value) }
            } else {
                let ae = ir.assign(&copy, value)
            }
            out[n] = ir.obj_value(&copy)
            n += 1usize
        }
        var obj = object_of(a, resource)
        let pe = ir.put(&obj, parsed.attribute, json.Value{ Array: out[0usize..n] })
        ret Patched { valid: true, message: "", resource: ir.obj_value(&obj) }
    }
    let parts = split_dots(a, parsed.attribute, parsed.sub, parsed.has_sub)
    if str.eq(op, "remove") {
        if parts.len == 1usize { ret Patched { valid: true, message: "", resource: without(a, resource, parts[0]) } }
        ret Patched { valid: true, message: "", resource: set_path(a, resource, parts, 0usize, .Null, false) }
    }
    let (cur_items, cur_is_array) = ir.items_of(current)
    if str.eq(op, "add") && has_current && cur_is_array && parts.len == 1usize {
        let (adds, value_is_array) = ir.items_of(value)
        var extra = 1usize
        if value_is_array { extra = adds.len }
        let (out, e) = mem.alloc[json.Value](a, cur_items.len + extra + 1usize)
        if e != ok { ret patch_failed("out of memory") }
        var n = 0usize
        var i = 0usize
        while i < cur_items.len {
            out[n] = cur_items[i]
            n += 1usize
            i += 1usize
        }
        if value_is_array {
            i = 0usize
            while i < adds.len {
                out[n] = adds[i]
                n += 1usize
                i += 1usize
            }
        } else {
            out[n] = value
            n += 1usize
        }
        var obj = object_of(a, resource)
        let pe = ir.put(&obj, parts[0], json.Value{ Array: out[0usize..n] })
        ret Patched { valid: true, message: "", resource: ir.obj_value(&obj) }
    }
    ret Patched { valid: true, message: "", resource: set_path(a, resource, parts, 0usize, value, has_value) }
}

// A PatchOp body: every operation in order, stopping at the first invalid one.
fn apply_patch(a: *mem.Arena, resource: json.Value, body: json.Value) -> Patched {
    var ops = ir.value_of(body, "Operations")
    if !ir.truthy(ops) { ops = ir.value_of(body, "operations") }
    let (items, is_array) = ir.items_of(ops)
    if !ir.truthy(ops) || !is_array || items.len == 0usize {
        if !ir.truthy(ops) || !is_array || items.len == 0usize { ret patch_failed("PatchOp requires a non-empty Operations array") }
    }
    var current = resource
    var i = 0usize
    while i < items.len {
        let r = apply_patch_op(a, current, items[i])
        if !r.valid { ret r }
        current = r.resource
        i += 1usize
    }
    ret Patched { valid: true, message: "", resource: current }
}

// --- serialisation -------------------------------------------------------------------------------------------

fn escape_into(a: *mem.Arena, s: str) -> str {
    var out = "\""
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            out = join(a, out, "\\\"")
        } else if c == 92u8 {
            out = join(a, out, "\\\\")
        } else if c == 10u8 {
            out = join(a, out, "\\n")
        } else if c == 13u8 {
            out = join(a, out, "\\r")
        } else if c == 9u8 {
            out = join(a, out, "\\t")
        } else if c == 8u8 {
            out = join(a, out, "\\b")
        } else if c == 12u8 {
            out = join(a, out, "\\f")
        } else if c < 32u8 {
            let hex = "0123456789abcdef"
            out = join(a, out, join(a, "\\u00", join(a, s_of(hex[usize(c >> 4u8)]), s_of(hex[usize(c & 15u8)]))))
        } else {
            out = join(a, out, s[i..i + 1usize])
        }
        i += 1usize
    }
    ret join(a, out, "\"")
}

fn s_of(c: u8) -> str {
    let digits = "0123456789abcdef"
    var i = 0usize
    while i < 16usize {
        if digits[i] == c { ret digits[i..i + 1usize] }
        i += 1usize
    }
    ret ""
}

// `JSON.stringify(value, keys)`: objects keep only `keys`, in that order, at every depth.
fn stringify(a: *mem.Arena, v: json.Value, keys: []const str) -> str {
    switch v {
    case .Null:
        ret "null"
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Number as n:
        ret f.number_text(a, number_of(v))
    case .String as s:
        ret escape_into(a, s)
    case .Array as xs:
        var out = "["
        var i = 0usize
        while i < xs.len {
            if i > 0usize { out = join(a, out, ",") }
            out = join(a, out, stringify(a, xs[i], keys))
            i += 1usize
        }
        ret join(a, out, "]")
    case .Object as members:
        var out = "{"
        var first = true
        var k = 0usize
        while k < keys.len {
            var i = 0usize
            while i < members.len {
                if str.eq(members[i].key, keys[k]) {
                    if !first { out = join(a, out, ",") }
                    first = false
                    out = join(a, out, join(a, escape_into(a, keys[k]), join(a, ":", stringify(a, members[i].value, keys))))
                    break
                }
                i += 1usize
            }
            k += 1usize
        }
        ret join(a, out, "}")
    default:
        ret "null"
    }
}

fn hex_text(a: *mem.Arena, x: u32) -> str {
    if x == 0u32 { ret "0" }
    var digits: [8]u8 = zero
    var n = 0usize
    var rest = x
    while rest > 0u32 {
        let d = u8(rest & 15u32)
        if d < 10u8 {
            digits[n] = 48u8 + d
        } else {
            digits[n] = 87u8 + d
        }
        n += 1usize
        rest = rest >> 4u32
    }
    var out = ""
    while n > 0usize {
        n -= 1usize
        out = join(a, out, digits[n..n + 1usize])
    }
    ret out
}

// A content-derived `W/"..."` version; the arithmetic is the reference's double arithmetic, rounded as it is.
fn resource_version(a: *mem.Arena, resource: json.Value) -> str {
    let (members, is_object) = ir.members_of(resource)
    let (keys, e) = mem.alloc[str](a, members.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < members.len {
        keys[n] = members[i].key
        n += 1usize
        i += 1usize
    }
    // Object.keys(...).sort(): by UTF-16 code units; byte order agrees for the keys a resource has.
    i = 1usize
    while i < n {
        let cur = keys[i]
        var j = i
        while j > 0usize && str.compare(keys[j - 1usize], cur) > 0i32 {
            keys[j] = keys[j - 1usize]
            j -= 1usize
        }
        keys[j] = cur
        i += 1usize
    }
    let text = stringify(a, resource, keys[0usize..n])
    let units = tx.units_of(a, text)
    var h1 = 2166136261u32
    var h2 = 16777619u32
    i = 0usize
    while i < units.len {
        let c = u32(units[i])
        // `h1 ^ c` is a signed 32-bit value in JavaScript, so the product may be negative before `>>> 0`.
        let x = h1 ^ c
        var signed = f64(x)
        if x >= 2147483648u32 { signed = f64(x) - 4294967296.0f64 }
        let m1 = i64(signed * 16777619.0f64)
        var wrapped = m1 % 4294967296i64
        if wrapped < 0i64 { wrapped += 4294967296i64 }
        h1 = u32(wrapped)
        let m2 = f64(u64(h2) + u64(c)) * 2246822507.0f64
        h2 = u32(u64(m2) & 4294967295u64)
        i += 1usize
    }
    ret join(a, join(a, "W/\"", hex_text(a, h1)), join(a, hex_text(a, h2), "\""))
}

fn truthy_text(v: json.Value, key: str) -> (str, bool) {
    let x = ir.value_of(v, key)
    if !ir.truthy(x) { ret ("", false) }
    switch x {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

fn put_opt(o: *ir.Obj, key: str, v: json.Value, has: bool) {
    if has {
        let pe = ir.put(o, key, v)
    }
}

fn sub_text(a: *mem.Arena, v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "undefined" }
    ret text_value(a, x)
}

fn first_truthy(a: *mem.Arena, v: json.Value, k1: str, k2: str, k3: str) -> (json.Value, bool) {
    let x1 = ir.value_of(v, k1)
    if ir.truthy(x1) { ret (x1, true) }
    if k2.len > 0usize {
        let x2 = ir.value_of(v, k2)
        if ir.truthy(x2) { ret (x2, true) }
    }
    if k3.len > 0usize {
        let x3 = ir.value_of(v, k3)
        if ir.truthy(x3) { ret (x3, true) }
    }
    ret (.Null, false)
}

// An internal user as a SCIM 2.0 User resource.
fn to_scim_user(a: *mem.Arena, user: json.Value, base_url: str) -> json.Value {
    var o = object_of(a, .Null)
    let (sa, se) = mem.alloc[json.Value](a, 1usize)
    sa[0] = sv("urn:ietf:params:scim:schemas:core:2.0:User")
    let pe0 = ir.put(&o, "schemas", json.Value{ Array: sa[0usize..1usize] })
    let (id, has_id) = ir.get(user, "id")
    put_opt(&o, "id", id, has_id && !ir.is_null(id))
    let (ext, has_ext) = first_truthy(a, user, "externalId", "", "")
    put_opt(&o, "externalId", ext, has_ext)
    let (uname, has_uname) = first_truthy(a, user, "userName", "email", "")
    put_opt(&o, "userName", uname, has_uname)
    var name = object_of(a, .Null)
    let (nm, has_nm) = first_truthy(a, user, "name", "", "")
    put_opt(&name, "formatted", nm, has_nm)
    let (gn, has_gn) = first_truthy(a, user, "givenName", "", "")
    put_opt(&name, "givenName", gn, has_gn)
    let (fn_, has_fn) = first_truthy(a, user, "familyName", "", "")
    put_opt(&name, "familyName", fn_, has_fn)
    let pe1 = ir.put(&o, "name", ir.obj_value(&name))
    let (dn, has_dn) = first_truthy(a, user, "name", "userName", "email")
    put_opt(&o, "displayName", dn, has_dn)
    let (email, has_email) = first_truthy(a, user, "email", "", "")
    var emails: []const json.Value = zero
    if has_email {
        var em = object_of(a, .Null)
        let p1 = ir.put(&em, "value", email)
        let p2 = ir.put(&em, "type", sv("work"))
        let p3 = ir.put(&em, "primary", json.Value{ Bool: true })
        let (ea, ee) = mem.alloc[json.Value](a, 1usize)
        ea[0] = ir.obj_value(&em)
        emails = ea[0usize..1usize]
    }
    let pe2 = ir.put(&o, "emails", json.Value{ Array: emails })
    var active = true
    switch ir.value_of(user, "active") {
    case .Bool as b:
        active = b
    default:
        active = true
    }
    let pe3 = ir.put(&o, "active", json.Value{ Bool: active })
    let groups = ir.value_of(user, "groups")
    let (gitems, gis) = ir.items_of(groups)
    let (gout, ge) = mem.alloc[json.Value](a, gitems.len + 1usize)
    var gi = 0usize
    while gi < gitems.len {
        var g = object_of(a, .Null)
        let (gid, has_gid) = first_truthy(a, gitems[gi], "id", "", "")
        if has_gid {
            let pv = ir.put(&g, "value", gid)
        } else {
            let pv = ir.put(&g, "value", gitems[gi])
        }
        let (gname, has_gname) = first_truthy(a, gitems[gi], "name", "", "")
        put_opt(&g, "display", gname, has_gname)
        let pt = ir.put(&g, "type", sv("direct"))
        gout[gi] = ir.obj_value(&g)
        gi += 1usize
    }
    let pe4 = ir.put(&o, "groups", json.Value{ Array: gout[0usize..gitems.len] })
    let resource = ir.obj_value(&o)
    var meta = object_of(a, .Null)
    let m1 = ir.put(&meta, "resourceType", sv("User"))
    let (created, has_created) = first_truthy(a, user, "createdAt", "", "")
    put_opt(&meta, "created", created, has_created)
    let (updated, has_updated) = first_truthy(a, user, "updatedAt", "", "")
    put_opt(&meta, "lastModified", updated, has_updated)
    let m2 = ir.put(&meta, "location", sv(join(a, join(a, base_url, "/Users/"), sub_text(a, user, "id"))))
    let m3 = ir.put(&meta, "version", sv(resource_version(a, resource)))
    var out = object_of(a, resource)
    let pm = ir.put(&out, "meta", ir.obj_value(&meta))
    ret ir.obj_value(&out)
}

fn id_or_self(a: *mem.Arena, m: json.Value) -> (json.Value, str) {
    let (id, has) = first_truthy(a, m, "id", "", "")
    if has { ret (id, text_value(a, id)) }
    switch m {
    case .String as s:
        ret (m, s)
    default:
        ret (m, "[object Object]")
    }
}

// An internal group as a SCIM 2.0 Group resource.
fn to_scim_group(a: *mem.Arena, group: json.Value, base_url: str) -> json.Value {
    var o = object_of(a, .Null)
    let (sa, se) = mem.alloc[json.Value](a, 1usize)
    sa[0] = sv("urn:ietf:params:scim:schemas:core:2.0:Group")
    let pe0 = ir.put(&o, "schemas", json.Value{ Array: sa[0usize..1usize] })
    let (id, has_id) = ir.get(group, "id")
    put_opt(&o, "id", id, has_id && !ir.is_null(id))
    let (ext, has_ext) = first_truthy(a, group, "externalId", "", "")
    put_opt(&o, "externalId", ext, has_ext)
    let (dn, has_dn) = first_truthy(a, group, "displayName", "name", "")
    put_opt(&o, "displayName", dn, has_dn)
    let members = ir.value_of(group, "members")
    let (items, is_array) = ir.items_of(members)
    let (out, e) = mem.alloc[json.Value](a, items.len + 1usize)
    var i = 0usize
    while i < items.len {
        var m = object_of(a, .Null)
        let (v, vtext) = id_or_self(a, items[i])
        let p1 = ir.put(&m, "value", v)
        let (name, has_name) = first_truthy(a, items[i], "name", "", "")
        put_opt(&m, "display", name, has_name)
        let p2 = ir.put(&m, "$ref", sv(join(a, join(a, base_url, "/Users/"), vtext)))
        out[i] = ir.obj_value(&m)
        i += 1usize
    }
    let pm = ir.put(&o, "members", json.Value{ Array: out[0usize..items.len] })
    let resource = ir.obj_value(&o)
    var meta = object_of(a, .Null)
    let m1 = ir.put(&meta, "resourceType", sv("Group"))
    let (created, has_created) = first_truthy(a, group, "createdAt", "", "")
    put_opt(&meta, "created", created, has_created)
    let (updated, has_updated) = first_truthy(a, group, "updatedAt", "", "")
    put_opt(&meta, "lastModified", updated, has_updated)
    let m2 = ir.put(&meta, "location", sv(join(a, join(a, base_url, "/Groups/"), sub_text(a, group, "id"))))
    let m3 = ir.put(&meta, "version", sv(resource_version(a, resource)))
    var res = object_of(a, resource)
    let pr = ir.put(&res, "meta", ir.obj_value(&meta))
    ret ir.obj_value(&res)
}

fn split_list(a: *mem.Arena, v: json.Value) -> []const str {
    let (items, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[str](a, 64usize)
    var n = 0usize
    if is_array {
        var i = 0usize
        while i < items.len && n < 63usize {
            let t = js_trim(text_value(a, items[i]))
            if t.len > 0usize {
                out[n] = t
                n += 1usize
            }
            i += 1usize
        }
        ret out[0usize..n]
    }
    if !ir.truthy(v) { ret out[0usize..0usize] }
    let text = text_value(a, v)
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 44u8 {
            let t = js_trim(text[start..i])
            if t.len > 0usize && n < 63usize {
                out[n] = t
                n += 1usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn js_trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && (s[from] == 32u8 || s[from] == 9u8 || s[from] == 10u8 || s[from] == 13u8) { from += 1usize }
    while to > from && (s[to - 1usize] == 32u8 || s[to - 1usize] == 9u8 || s[to - 1usize] == 10u8 || s[to - 1usize] == 13u8) { to -= 1usize }
    ret s[from..to]
}

fn listed(names: []const str, key: str) -> bool {
    var i = 0usize
    while i < names.len {
        if str.eq(names[i], key) { ret true }
        i += 1usize
    }
    ret false
}

fn head_of(s: str) -> str {
    let dot = index_of(s, 46u8)
    if dot < 0i64 { ret s }
    ret s[0usize..usize(dot)]
}

// A resource reduced to `attributes` (an allow-list) or without `excludedAttributes`; `schemas` and `id` always stay.
fn project_attributes(a: *mem.Arena, resource: json.Value, attributes: json.Value, excluded: json.Value) -> json.Value {
    let (members, is_object) = ir.members_of(resource)
    let attrs = split_list(a, attributes)
    if ir.truthy(attributes) && attrs.len > 0usize {
        let (o, e) = ir.new_obj(a)
        var out = o
        var i = 0usize
        while i < members.len {
            let key = members[i].key
            var keep = str.eq(key, "schemas") || str.eq(key, "id")
            var k = 0usize
            while k < attrs.len {
                if str.eq(head_of(attrs[k]), key) { keep = true }
                k += 1usize
            }
            if keep { let pe = ir.put(&out, key, members[i].value) }
            i += 1usize
        }
        ret ir.obj_value(&out)
    }
    let drops = split_list(a, excluded)
    if ir.truthy(excluded) && drops.len > 0usize {
        let (o, e) = ir.new_obj(a)
        var out = o
        var i = 0usize
        while i < members.len {
            let key = members[i].key
            let always = str.eq(key, "schemas") || str.eq(key, "id")
            if always || !listed(drops, key) { let pe = ir.put(&out, key, members[i].value) }
            i += 1usize
        }
        ret ir.obj_value(&out)
    }
    ret resource
}

fn trunc_f64(x: f64) -> f64 {
    if x != x { ret 0.0f64 }
    if x >= 0.0f64 { ret f64(i64(x)) }
    ret 0.0f64 - f64(i64(0.0f64 - x))
}

// A ListResponse: `start_index` is 1-based; `total` and `count` may be absent (null).
fn list_response(a: *mem.Arena, resources: []const json.Value, start_index: json.Value, has_start: bool, count: json.Value, has_count: bool, total_results: json.Value, has_total: bool) -> json.Value {
    var total = f64(resources.len)
    var total_value = json.Value{ Number: json.Number{ lexeme: f.number_text(a, total) } }
    if has_total && !ir.is_null(total_results) { total_value = total_results }
    var start = 1.0f64
    if has_start {
        let n = to_number(start_index)
        if n == n && n != 0.0f64 { start = n }
    }
    if start < 1.0f64 { start = 1.0f64 }
    var size = f64(resources.len)
    if has_count && !ir.is_null(count) {
        size = to_number(count)
        if size < 0.0f64 { size = 0.0f64 }
    }
    var page = resources
    if !(has_total && !ir.is_null(total_results)) {
        var from = trunc_f64(start - 1.0f64)
        var to = trunc_f64(start - 1.0f64 + size)
        if size != size { to = 0.0f64 }
        if from > f64(resources.len) { from = f64(resources.len) }
        if to > f64(resources.len) { to = f64(resources.len) }
        if to < from { to = from }
        page = resources[usize(from)..usize(to)]
    }
    let (o, e) = ir.new_obj(a)
    var out = o
    let (sa, se) = mem.alloc[json.Value](a, 1usize)
    sa[0] = sv("urn:ietf:params:scim:api:messages:2.0:ListResponse")
    let p0 = ir.put(&out, "schemas", json.Value{ Array: sa[0usize..1usize] })
    let p1 = ir.put(&out, "totalResults", total_value)
    let p2 = ir.put(&out, "itemsPerPage", json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(page.len)) } })
    let p3 = ir.put(&out, "startIndex", json.Value{ Number: json.Number{ lexeme: f.number_text(a, start) } })
    let p4 = ir.put(&out, "Resources", json.Value{ Array: page })
    ret ir.obj_value(&out)
}

// A SCIM Error envelope; `scim_type` is added when it is not empty.
fn scim_error(a: *mem.Arena, status: str, detail: str, scim_type: str) -> json.Value {
    let (o, e) = ir.new_obj(a)
    var out = o
    let (sa, se) = mem.alloc[json.Value](a, 1usize)
    sa[0] = sv("urn:ietf:params:scim:api:messages:2.0:Error")
    let p0 = ir.put(&out, "schemas", json.Value{ Array: sa[0usize..1usize] })
    let p1 = ir.put(&out, "status", sv(status))
    let p2 = ir.put(&out, "detail", sv(detail))
    if scim_type.len > 0usize { let p3 = ir.put(&out, "scimType", sv(scim_type)) }
    ret ir.obj_value(&out)
}

fn one_array(a: *mem.Arena, s: str) -> json.Value {
    let (sa, se) = mem.alloc[json.Value](a, 1usize)
    sa[0] = sv(s)
    ret json.Value{ Array: sa[0usize..1usize] }
}

fn flag(a: *mem.Arena, supported: bool) -> json.Value {
    let (o, e) = ir.new_obj(a)
    var out = o
    let p = ir.put(&out, "supported", json.Value{ Bool: supported })
    ret ir.obj_value(&out)
}

fn int_value(a: *mem.Arena, n: i64) -> json.Value {
    ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(n)) } }
}

// The ServiceProviderConfig an IdP reads before it provisions.
fn service_provider_config(a: *mem.Arena, base_url: str, documentation_uri: str) -> json.Value {
    let (o, e) = ir.new_obj(a)
    var out = o
    let p0 = ir.put(&out, "schemas", one_array(a, "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"))
    if documentation_uri.len > 0usize { let p1 = ir.put(&out, "documentationUri", sv(documentation_uri)) }
    let p2 = ir.put(&out, "patch", flag(a, true))
    var bulk = object_of(a, .Null)
    let b0 = ir.put(&bulk, "supported", json.Value{ Bool: false })
    let b1 = ir.put(&bulk, "maxOperations", int_value(a, 0i64))
    let b2 = ir.put(&bulk, "maxPayloadSize", int_value(a, 0i64))
    let p3 = ir.put(&out, "bulk", ir.obj_value(&bulk))
    var filter = object_of(a, .Null)
    let f0 = ir.put(&filter, "supported", json.Value{ Bool: true })
    let f1 = ir.put(&filter, "maxResults", int_value(a, 200i64))
    let p4 = ir.put(&out, "filter", ir.obj_value(&filter))
    let p5 = ir.put(&out, "changePassword", flag(a, false))
    let p6 = ir.put(&out, "sort", flag(a, true))
    let p7 = ir.put(&out, "etag", flag(a, true))
    var scheme = object_of(a, .Null)
    let s0 = ir.put(&scheme, "type", sv("oauthbearertoken"))
    let s1 = ir.put(&scheme, "name", sv("OAuth Bearer Token"))
    let s2 = ir.put(&scheme, "description", sv("Authentication via the tenant provisioning token in the Authorization header."))
    let s3 = ir.put(&scheme, "primary", json.Value{ Bool: true })
    let (sa, se) = mem.alloc[json.Value](a, 1usize)
    sa[0] = ir.obj_value(&scheme)
    let p8 = ir.put(&out, "authenticationSchemes", json.Value{ Array: sa[0usize..1usize] })
    var meta = object_of(a, .Null)
    let m0 = ir.put(&meta, "resourceType", sv("ServiceProviderConfig"))
    let m1 = ir.put(&meta, "location", sv(join(a, base_url, "/ServiceProviderConfig")))
    let p9 = ir.put(&out, "meta", ir.obj_value(&meta))
    ret ir.obj_value(&out)
}

fn resource_type(a: *mem.Arena, base_url: str, name: str, endpoint: str, schema: str) -> json.Value {
    var o = object_of(a, .Null)
    let p0 = ir.put(&o, "schemas", one_array(a, "urn:ietf:params:scim:schemas:core:2.0:ResourceType"))
    let p1 = ir.put(&o, "id", sv(name))
    let p2 = ir.put(&o, "name", sv(name))
    let p3 = ir.put(&o, "endpoint", sv(endpoint))
    let p4 = ir.put(&o, "schema", sv(schema))
    var meta = object_of(a, .Null)
    let m0 = ir.put(&meta, "resourceType", sv("ResourceType"))
    let m1 = ir.put(&meta, "location", sv(join(a, join(a, base_url, "/ResourceTypes/"), name)))
    let p5 = ir.put(&o, "meta", ir.obj_value(&meta))
    ret ir.obj_value(&o)
}

// The ResourceTypes an IdP discovers.
fn resource_types(a: *mem.Arena, base_url: str) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, 2usize)
    out[0] = resource_type(a, base_url, "User", "/Users", "urn:ietf:params:scim:schemas:core:2.0:User")
    out[1] = resource_type(a, base_url, "Group", "/Groups", "urn:ietf:params:scim:schemas:core:2.0:Group")
    ret json.Value{ Array: out[0usize..2usize] }
}

// Resources ordered by a SCIM attribute path; absent values sort last, equal keys keep their order.
fn sort_resources(a: *mem.Arena, resources: []const json.Value, sort_by: str, descending: bool) -> []const json.Value {
    let (out, e) = mem.alloc[json.Value](a, resources.len + 1usize)
    var i = 0usize
    while i < resources.len {
        out[i] = resources[i]
        i += 1usize
    }
    if sort_by.len == 0usize { ret out[0usize..resources.len] }
    var direction = 1i32
    if descending { direction = -1i32 }
    i = 1usize
    while i < resources.len {
        let cur = out[i]
        var j = i
        while j > 0usize {
            let before = out[j - 1usize]
            // `compare(before, cur) > 0` moves `cur` ahead.
            let (va, fa) = get_attribute(a, before, sort_by)
            let (vb, fb) = get_attribute(a, cur, sort_by)
            var result = 0i32
            let a_missing = !fa || ir.is_null(va)
            let b_missing = !fb || ir.is_null(vb)
            if (!fa && !fb) || (fa && fb && strict_equal(va, vb)) {
                result = 0i32
            } else if a_missing {
                result = 1i32
            } else if b_missing {
                result = -1i32
            } else if less(va, vb) {
                result = -1i32 * direction
            } else {
                result = direction
            }
            if result > 0i32 {
                out[j] = out[j - 1usize]
                j -= 1usize
            } else {
                break
            }
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..resources.len]
}
