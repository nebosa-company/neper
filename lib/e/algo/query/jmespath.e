// JMESPath queries over `e.fmt.json` values, after python-jmespath: field and index
// navigation, slices, wildcard and flatten projections, filters, pipes, `||` `&&` `!`
// and the six comparators, multi-select lists and hashes, `@`, JSON and raw-string
// literals, and the standard functions (abs avg ceil contains ends_with floor join keys
// length map max max_by merge min min_by not_null reverse sort sort_by starts_with sum
// to_array to_number to_string type values). An expression compiles once into a flat
// node table in the caller's arena and is evaluated against any number of documents.
//
// Evaluation never mutates its input: every array or object it produces is built in the
// arena, and a result may borrow strings and subtrees from the document.
//
// ponytail: `to_number` reads decimal text only (no `1_000`, `inf`, `nan`); ordering
// comparators between a string and a number are null as the specification says, where
// python-jmespath raises; an expression is at most 128 tokens and 64 deep.

use e.fmt.json
use e.mem
use e.str

error Syntax
error Type
error Arity
error UnknownFunction
error InvalidValue
error TooLarge

// Node kinds.
const K_FIELD: u8 = 0u8
const K_LITERAL: u8 = 1u8
const K_CURRENT: u8 = 2u8
const K_SUBEXPR: u8 = 3u8
const K_INDEX: u8 = 4u8
const K_SLICE: u8 = 5u8
const K_PROJECTION: u8 = 6u8
const K_VALUE_PROJECTION: u8 = 7u8
const K_FILTER: u8 = 8u8
const K_FLATTEN: u8 = 9u8
const K_COMPARE: u8 = 10u8
const K_OR: u8 = 11u8
const K_AND: u8 = 12u8
const K_NOT: u8 = 13u8
const K_MULTI_LIST: u8 = 14u8
const K_MULTI_HASH: u8 = 15u8
const K_KEYVAL: u8 = 16u8
const K_FUNCTION: u8 = 17u8
const K_EXPREF: u8 = 18u8
const K_INDEXEXPR: u8 = 19u8

// Token kinds, in the order the binding powers below are written.
const T_EOF: u8 = 0u8
const T_IDENT: u8 = 1u8
const T_QIDENT: u8 = 2u8
const T_LITERAL: u8 = 3u8
const T_NUMBER: u8 = 4u8
const T_DOT: u8 = 5u8
const T_STAR: u8 = 6u8
const T_RBRACKET: u8 = 7u8
const T_COMMA: u8 = 8u8
const T_COLON: u8 = 9u8
const T_CURRENT: u8 = 10u8
const T_LPAREN: u8 = 11u8
const T_RPAREN: u8 = 12u8
const T_LBRACE: u8 = 13u8
const T_RBRACE: u8 = 14u8
const T_FLATTEN: u8 = 15u8
const T_FILTER: u8 = 16u8
const T_LBRACKET: u8 = 17u8
const T_PIPE: u8 = 18u8
const T_OR: u8 = 19u8
const T_AND: u8 = 20u8
const T_EXPREF: u8 = 21u8
const T_EQ: u8 = 22u8
const T_NE: u8 = 23u8
const T_LT: u8 = 24u8
const T_LTE: u8 = 25u8
const T_GT: u8 = 26u8
const T_GTE: u8 = 27u8
const T_NOT: u8 = 28u8

const MAX_TOKENS: usize = 128usize
const MAX_DEPTH: usize = 64usize

// `a` and `b` are child node indices (or, for lists and calls, the start and count in
// `edges`); `x y z` and `flags` hold a slice's start, stop and step (flag bits 1, 2, 4
// say which are present); `num` is an index or a comparator token.
type Node = struct { kind: u8, a: i32, b: i32, c: i32, num: i64, x: i64, y: i64, z: i64, flags: u8, text: str, value: json.Value }

type Expr = struct { nodes: []const Node, edges: []const i32, root: i32 }

type Token = struct { kind: u8, text: str, num: i64, value: json.Value }

// --- Lexing.

fn is_start(b: u8) -> bool { ret (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) || b == 95u8 }

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn is_blank(b: u8) -> bool { ret b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8 }

fn null_value() -> json.Value {
    var v: json.Value = .Null
    ret v
}

// The index just past the closing `delim`, honouring `\` as an escape; `text.len + 1`
// when it never closes.
fn closing(text: str, open: usize, delim: u8) -> usize {
    var at = open + 1usize
    while at < text.len {
        if text[at] == 92u8 {
            at += 2usize
            continue
        }
        if text[at] == delim { ret at + 1usize }
        at += 1usize
    }
    ret text.len + 1usize
}

// `text` with each `\` + `delim` replaced by `delim`.
fn unescape_delim(a: *mem.Arena, text: str, delim: u8) -> (str, err) {
    var found = false
    var i = 0usize
    while i + 1usize < text.len {
        if text[i] == 92u8 && text[i + 1usize] == delim { found = true }
        i += 1usize
    }
    if !found { ret (text, ok) }
    let (buffer, buffer_error) = mem.alloc[u8](a, text.len)
    if buffer_error != ok { ret ("", buffer_error) }
    var n = 0usize
    i = 0usize
    while i < text.len {
        if text[i] == 92u8 && i + 1usize < text.len && text[i + 1usize] == delim {
            buffer[n] = delim
            n += 1usize
            i += 2usize
            continue
        }
        buffer[n] = text[i]
        n += 1usize
        i += 1usize
    }
    ret (buffer[0usize..n], ok)
}

fn simple(kind: u8, text: str) -> Token {
    var t: Token = zero
    t.kind = kind
    t.text = text
    ret t
}

fn lex(a: *mem.Arena, source: str, toks: []Token) -> (usize, err) {
    var n = 0usize
    var at = 0usize
    if source.len == 0usize { ret (0usize, Syntax) }
    while at < source.len {
        if n + 1usize >= toks.len { ret (0usize, TooLarge) }
        let c = source[at]
        if is_blank(c) {
            at += 1usize
            continue
        }
        if is_start(c) {
            let start = at
            while at < source.len && (is_start(source[at]) || is_digit(source[at])) { at += 1usize }
            toks[n] = simple(T_IDENT, source[start..at])
            n += 1usize
            continue
        }
        if is_digit(c) || c == 45u8 {
            let start = at
            at += 1usize
            while at < source.len && is_digit(source[at]) { at += 1usize }
            if at - start == 1usize && c == 45u8 { ret (0usize, Syntax) }
            if at - start > 18usize { ret (0usize, Syntax) }
            var value = 0i64
            var k = start
            if c == 45u8 { k += 1usize }
            while k < at {
                value = value * 10i64 + i64(source[k] - 48u8)
                k += 1usize
            }
            if c == 45u8 { value = 0i64 - value }
            var t = simple(T_NUMBER, source[start..at])
            t.num = value
            toks[n] = t
            n += 1usize
            continue
        }
        if c == 46u8 {
            toks[n] = simple(T_DOT, ".")
            at += 1usize
        } else if c == 42u8 {
            toks[n] = simple(T_STAR, "*")
            at += 1usize
        } else if c == 93u8 {
            toks[n] = simple(T_RBRACKET, "]")
            at += 1usize
        } else if c == 44u8 {
            toks[n] = simple(T_COMMA, ",")
            at += 1usize
        } else if c == 58u8 {
            toks[n] = simple(T_COLON, ":")
            at += 1usize
        } else if c == 64u8 {
            toks[n] = simple(T_CURRENT, "@")
            at += 1usize
        } else if c == 40u8 {
            toks[n] = simple(T_LPAREN, "(")
            at += 1usize
        } else if c == 41u8 {
            toks[n] = simple(T_RPAREN, ")")
            at += 1usize
        } else if c == 123u8 {
            toks[n] = simple(T_LBRACE, "{")
            at += 1usize
        } else if c == 125u8 {
            toks[n] = simple(T_RBRACE, "}")
            at += 1usize
        } else if c == 91u8 {
            if at + 1usize < source.len && source[at + 1usize] == 93u8 {
                toks[n] = simple(T_FLATTEN, "[]")
                at += 2usize
            } else if at + 1usize < source.len && source[at + 1usize] == 63u8 {
                toks[n] = simple(T_FILTER, "[?")
                at += 2usize
            } else {
                toks[n] = simple(T_LBRACKET, "[")
                at += 1usize
            }
        } else if c == 124u8 {
            if at + 1usize < source.len && source[at + 1usize] == 124u8 {
                toks[n] = simple(T_OR, "||")
                at += 2usize
            } else {
                toks[n] = simple(T_PIPE, "|")
                at += 1usize
            }
        } else if c == 38u8 {
            if at + 1usize < source.len && source[at + 1usize] == 38u8 {
                toks[n] = simple(T_AND, "&&")
                at += 2usize
            } else {
                toks[n] = simple(T_EXPREF, "&")
                at += 1usize
            }
        } else if c == 60u8 {
            if at + 1usize < source.len && source[at + 1usize] == 61u8 {
                toks[n] = simple(T_LTE, "<=")
                at += 2usize
            } else {
                toks[n] = simple(T_LT, "<")
                at += 1usize
            }
        } else if c == 62u8 {
            if at + 1usize < source.len && source[at + 1usize] == 61u8 {
                toks[n] = simple(T_GTE, ">=")
                at += 2usize
            } else {
                toks[n] = simple(T_GT, ">")
                at += 1usize
            }
        } else if c == 33u8 {
            if at + 1usize < source.len && source[at + 1usize] == 61u8 {
                toks[n] = simple(T_NE, "!=")
                at += 2usize
            } else {
                toks[n] = simple(T_NOT, "!")
                at += 1usize
            }
        } else if c == 61u8 {
            if at + 1usize < source.len && source[at + 1usize] == 61u8 {
                toks[n] = simple(T_EQ, "==")
                at += 2usize
            } else {
                ret (0usize, Syntax)
            }
        } else if c == 39u8 {
            let end = closing(source, at, 39u8)
            if end > source.len { ret (0usize, Syntax) }
            let (text, text_error) = unescape_delim(a, source[at + 1usize..end - 1usize], 39u8)
            if text_error != ok { ret (0usize, text_error) }
            var t = simple(T_LITERAL, "")
            t.value = json.Value{ String: text }
            toks[n] = t
            at = end
        } else if c == 96u8 {
            let end = closing(source, at, 96u8)
            if end > source.len { ret (0usize, Syntax) }
            let (text, text_error) = unescape_delim(a, source[at + 1usize..end - 1usize], 96u8)
            if text_error != ok { ret (0usize, text_error) }
            var opts: json.Options = zero
            opts.allow_duplicate_keys = true
            var (parsed, parse_error) = json.parse(a, text, opts)
            if parse_error != ok {
                // The deprecated bare-word literal: the text read as a JSON string.
                var start = 0usize
                while start < text.len && is_blank(text[start]) { start += 1usize }
                let (quoted, quoted_error) = str.concat(a, "\"", text[start..text.len])
                if quoted_error != ok { ret (0usize, quoted_error) }
                let (closed, closed_error) = str.concat(a, quoted, "\"")
                if closed_error != ok { ret (0usize, closed_error) }
                let (second, second_error) = json.parse(a, closed, opts)
                if second_error != ok { ret (0usize, Syntax) }
                parsed = second
            }
            var t = simple(T_LITERAL, "")
            t.value = parsed
            toks[n] = t
            at = end
        } else if c == 34u8 {
            let end = closing(source, at, 34u8)
            if end > source.len { ret (0usize, Syntax) }
            var opts: json.Options = zero
            let (parsed, parse_error) = json.parse(a, source[at..end], opts)
            if parse_error != ok { ret (0usize, Syntax) }
            var text = ""
            switch parsed {
            case .String as s:
                text = s
            default:
                ret (0usize, Syntax)
            }
            toks[n] = simple(T_QIDENT, text)
            at = end
        } else {
            ret (0usize, Syntax)
        }
        n += 1usize
    }
    toks[n] = simple(T_EOF, "")
    n += 1usize
    ret (n, ok)
}

// --- Parsing: a Pratt parser with python-jmespath's binding powers.

type Parser = struct { toks: []const Token, n: usize, pos: usize, nodes: []Node, node_n: usize, edges: []i32, edge_n: usize, depth: usize }

fn binding_power(kind: u8) -> i32 {
    if kind == T_PIPE { ret 1i32 }
    if kind == T_OR { ret 2i32 }
    if kind == T_AND { ret 3i32 }
    if kind == T_EQ || kind == T_NE || kind == T_LT || kind == T_LTE || kind == T_GT || kind == T_GTE { ret 5i32 }
    if kind == T_FLATTEN { ret 9i32 }
    if kind == T_STAR { ret 20i32 }
    if kind == T_FILTER { ret 21i32 }
    if kind == T_DOT { ret 40i32 }
    if kind == T_NOT { ret 45i32 }
    if kind == T_LBRACE { ret 50i32 }
    if kind == T_LBRACKET { ret 55i32 }
    if kind == T_LPAREN { ret 60i32 }
    ret 0i32
}

fn current(p: *Parser) -> u8 { ret p.toks[p.pos].kind }

fn lookahead(p: *Parser, offset: usize) -> u8 {
    if p.pos + offset >= p.n { ret T_EOF }
    ret p.toks[p.pos + offset].kind
}

fn add_node(p: *Parser, kind: u8, a: i32, b: i32) -> (i32, err) {
    if p.node_n == p.nodes.len { ret (0i32, TooLarge) }
    var node: Node = zero
    node.kind = kind
    node.a = a
    node.b = b
    p.nodes[p.node_n] = node
    p.node_n += 1usize
    ret (i32(p.node_n - 1usize), ok)
}

fn match_token(p: *Parser, kind: u8) -> err {
    if current(p) != kind { ret Syntax }
    p.pos += 1usize
    ret ok
}

fn identity(p: *Parser) -> (i32, err) {
    let (node, node_error) = add_node(p, K_CURRENT, 0i32, 0i32)
    ret (node, node_error)
}

// `a` and `b` children, appended to the edge table: start index and count.
fn add_edges(p: *Parser, items: []const i32) -> (i32, err) {
    if p.edge_n + items.len > p.edges.len { ret (0i32, TooLarge) }
    let start = p.edge_n
    var i = 0usize
    while i < items.len {
        p.edges[p.edge_n] = items[i]
        p.edge_n += 1usize
        i += 1usize
    }
    ret (i32(start), ok)
}

fn expression(p: *Parser, rbp: i32) -> (i32, err) {
    if p.depth >= MAX_DEPTH { ret (0i32, TooLarge) }
    p.depth += 1usize
    let (node, node_error) = expression_inner(p, rbp)
    p.depth -= 1usize
    ret (node, node_error)
}

fn expression_inner(p: *Parser, rbp: i32) -> (i32, err) {
    let tok = p.toks[p.pos]
    p.pos += 1usize
    var (left, nud_error) = nud(p, tok)
    if nud_error != ok { ret (0i32, nud_error) }
    while rbp < binding_power(current(p)) {
        let kind = current(p)
        if !has_led(kind) { ret (0i32, Syntax) }
        p.pos += 1usize
        let (next, led_error) = led(p, kind, left)
        if led_error != ok { ret (0i32, led_error) }
        left = next
    }
    ret (left, ok)
}

fn has_led(kind: u8) -> bool {
    ret kind == T_DOT || kind == T_PIPE || kind == T_OR || kind == T_AND || kind == T_LPAREN || kind == T_FILTER || kind == T_EQ || kind == T_NE || kind == T_GT || kind == T_GTE || kind == T_LT || kind == T_LTE || kind == T_FLATTEN || kind == T_LBRACKET
}

fn field_node(p: *Parser, text: str) -> (i32, err) {
    let (node, node_error) = add_node(p, K_FIELD, 0i32, 0i32)
    if node_error != ok { ret (0i32, node_error) }
    p.nodes[usize(node)].text = text
    ret (node, ok)
}

fn nud(p: *Parser, tok: Token) -> (i32, err) {
    if tok.kind == T_LITERAL {
        let (node, node_error) = add_node(p, K_LITERAL, 0i32, 0i32)
        if node_error != ok { ret (0i32, node_error) }
        p.nodes[usize(node)].value = tok.value
        ret (node, ok)
    }
    if tok.kind == T_IDENT {
        let (node, node_error) = field_node(p, tok.text)
        ret (node, node_error)
    }
    if tok.kind == T_QIDENT {
        if current(p) == T_LPAREN { ret (0i32, Syntax) }
        let (node, node_error) = field_node(p, tok.text)
        ret (node, node_error)
    }
    if tok.kind == T_STAR {
        let (left, left_error) = identity(p)
        if left_error != ok { ret (0i32, left_error) }
        var right = 0i32
        if current(p) == T_RBRACKET {
            let (id, id_error) = identity(p)
            if id_error != ok { ret (0i32, id_error) }
            right = id
        } else {
            let (rhs, rhs_error) = projection_rhs(p, 20i32)
            if rhs_error != ok { ret (0i32, rhs_error) }
            right = rhs
        }
        let (node, node_error) = add_node(p, K_VALUE_PROJECTION, left, right)
        ret (node, node_error)
    }
    if tok.kind == T_FILTER {
        let (left, left_error) = identity(p)
        if left_error != ok { ret (0i32, left_error) }
        let (node, node_error) = filter_led(p, left)
        ret (node, node_error)
    }
    if tok.kind == T_LBRACE {
        let (node, node_error) = multi_select_hash(p)
        ret (node, node_error)
    }
    if tok.kind == T_LPAREN {
        let (inner, inner_error) = expression(p, 0i32)
        if inner_error != ok { ret (0i32, inner_error) }
        let close_error = match_token(p, T_RPAREN)
        if close_error != ok { ret (0i32, close_error) }
        ret (inner, ok)
    }
    if tok.kind == T_FLATTEN {
        let (id, id_error) = identity(p)
        if id_error != ok { ret (0i32, id_error) }
        let (flat, flat_error) = add_node(p, K_FLATTEN, id, 0i32)
        if flat_error != ok { ret (0i32, flat_error) }
        let (right, right_error) = projection_rhs(p, 9i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_PROJECTION, flat, right)
        ret (node, node_error)
    }
    if tok.kind == T_NOT {
        let (inner, inner_error) = expression(p, 45i32)
        if inner_error != ok { ret (0i32, inner_error) }
        let (node, node_error) = add_node(p, K_NOT, inner, 0i32)
        ret (node, node_error)
    }
    if tok.kind == T_LBRACKET {
        if current(p) == T_NUMBER || current(p) == T_COLON {
            let (right, right_error) = index_expression(p)
            if right_error != ok { ret (0i32, right_error) }
            let (id, id_error) = identity(p)
            if id_error != ok { ret (0i32, id_error) }
            let (node, node_error) = project_if_slice(p, id, right)
            ret (node, node_error)
        }
        if current(p) == T_STAR && lookahead(p, 1usize) == T_RBRACKET {
            p.pos += 2usize
            let (right, right_error) = projection_rhs(p, 20i32)
            if right_error != ok { ret (0i32, right_error) }
            let (id, id_error) = identity(p)
            if id_error != ok { ret (0i32, id_error) }
            let (node, node_error) = add_node(p, K_PROJECTION, id, right)
            ret (node, node_error)
        }
        let (node, node_error) = multi_select_list(p)
        ret (node, node_error)
    }
    if tok.kind == T_CURRENT {
        let (node, node_error) = identity(p)
        ret (node, node_error)
    }
    if tok.kind == T_EXPREF {
        let (inner, inner_error) = expression(p, 0i32)
        if inner_error != ok { ret (0i32, inner_error) }
        let (node, node_error) = add_node(p, K_EXPREF, inner, 0i32)
        ret (node, node_error)
    }
    ret (0i32, Syntax)
}

fn led(p: *Parser, kind: u8, left: i32) -> (i32, err) {
    if kind == T_DOT {
        if current(p) != T_STAR {
            let (right, right_error) = dot_rhs(p, 40i32)
            if right_error != ok { ret (0i32, right_error) }
            let (node, node_error) = add_node(p, K_SUBEXPR, left, right)
            ret (node, node_error)
        }
        p.pos += 1usize
        let (right, right_error) = projection_rhs(p, 40i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_VALUE_PROJECTION, left, right)
        ret (node, node_error)
    }
    if kind == T_PIPE {
        let (right, right_error) = expression(p, 1i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_SUBEXPR, left, right)
        ret (node, node_error)
    }
    if kind == T_OR {
        let (right, right_error) = expression(p, 2i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_OR, left, right)
        ret (node, node_error)
    }
    if kind == T_AND {
        let (right, right_error) = expression(p, 3i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_AND, left, right)
        ret (node, node_error)
    }
    if kind == T_LPAREN {
        if p.nodes[usize(left)].kind != K_FIELD { ret (0i32, Syntax) }
        let name = p.nodes[usize(left)].text
        var args: [16]i32 = zero
        var count = 0usize
        while current(p) != T_RPAREN {
            let (arg, arg_error) = expression(p, 0i32)
            if arg_error != ok { ret (0i32, arg_error) }
            if current(p) == T_COMMA { p.pos += 1usize }
            if count == 16usize { ret (0i32, TooLarge) }
            args[count] = arg
            count += 1usize
        }
        p.pos += 1usize
        let (start, edges_error) = add_edges(p, args[0usize..count])
        if edges_error != ok { ret (0i32, edges_error) }
        let (node, node_error) = add_node(p, K_FUNCTION, start, i32(count))
        if node_error != ok { ret (0i32, node_error) }
        p.nodes[usize(node)].text = name
        ret (node, ok)
    }
    if kind == T_FILTER {
        let (node, node_error) = filter_led(p, left)
        ret (node, node_error)
    }
    if kind == T_FLATTEN {
        let (flat, flat_error) = add_node(p, K_FLATTEN, left, 0i32)
        if flat_error != ok { ret (0i32, flat_error) }
        let (right, right_error) = projection_rhs(p, 9i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_PROJECTION, flat, right)
        ret (node, node_error)
    }
    if kind == T_LBRACKET {
        if current(p) == T_NUMBER || current(p) == T_COLON {
            let (right, right_error) = index_expression(p)
            if right_error != ok { ret (0i32, right_error) }
            if p.nodes[usize(left)].kind == K_INDEXEXPR {
                let (node, node_error) = add_node(p, K_INDEXEXPR, left, right)
                ret (node, node_error)
            }
            let (node, node_error) = project_if_slice(p, left, right)
            ret (node, node_error)
        }
        let star_error = match_token(p, T_STAR)
        if star_error != ok { ret (0i32, star_error) }
        let close_error = match_token(p, T_RBRACKET)
        if close_error != ok { ret (0i32, close_error) }
        let (right, right_error) = projection_rhs(p, 20i32)
        if right_error != ok { ret (0i32, right_error) }
        let (node, node_error) = add_node(p, K_PROJECTION, left, right)
        ret (node, node_error)
    }
    // A comparator.
    let (right, right_error) = expression(p, 5i32)
    if right_error != ok { ret (0i32, right_error) }
    let (node, node_error) = add_node(p, K_COMPARE, left, right)
    if node_error != ok { ret (0i32, node_error) }
    p.nodes[usize(node)].num = i64(kind)
    ret (node, ok)
}

fn filter_led(p: *Parser, left: i32) -> (i32, err) {
    let (condition, condition_error) = expression(p, 0i32)
    if condition_error != ok { ret (0i32, condition_error) }
    let close_error = match_token(p, T_RBRACKET)
    if close_error != ok { ret (0i32, close_error) }
    var right = 0i32
    if current(p) == T_FLATTEN {
        let (id, id_error) = identity(p)
        if id_error != ok { ret (0i32, id_error) }
        right = id
    } else {
        let (rhs, rhs_error) = projection_rhs(p, 21i32)
        if rhs_error != ok { ret (0i32, rhs_error) }
        right = rhs
    }
    let (node, node_error) = add_node(p, K_FILTER, left, right)
    if node_error != ok { ret (0i32, node_error) }
    p.nodes[usize(node)].c = condition
    ret (node, ok)
}

fn projection_rhs(p: *Parser, bp: i32) -> (i32, err) {
    let kind = current(p)
    if binding_power(kind) < 10i32 {
        let (node, node_error) = identity(p)
        ret (node, node_error)
    }
    if kind == T_LBRACKET || kind == T_FILTER {
        let (node, node_error) = expression(p, bp)
        ret (node, node_error)
    }
    if kind == T_DOT {
        p.pos += 1usize
        let (node, node_error) = dot_rhs(p, bp)
        ret (node, node_error)
    }
    ret (0i32, Syntax)
}

fn dot_rhs(p: *Parser, bp: i32) -> (i32, err) {
    let kind = current(p)
    if kind == T_QIDENT || kind == T_IDENT || kind == T_STAR {
        let (node, node_error) = expression(p, bp)
        ret (node, node_error)
    }
    if kind == T_LBRACKET {
        p.pos += 1usize
        let (node, node_error) = multi_select_list(p)
        ret (node, node_error)
    }
    if kind == T_LBRACE {
        p.pos += 1usize
        let (node, node_error) = multi_select_hash(p)
        ret (node, node_error)
    }
    ret (0i32, Syntax)
}

// `[` was consumed and the current token is a number or colon.
fn index_expression(p: *Parser) -> (i32, err) {
    if lookahead(p, 0usize) == T_COLON || lookahead(p, 1usize) == T_COLON {
        // [start:stop:step]
        var parts: [3]i64 = zero
        var flags = 0u8
        var index = 0usize
        while current(p) != T_RBRACKET && index < 3usize {
            if current(p) == T_COLON {
                index += 1usize
                if index == 3usize { ret (0i32, Syntax) }
                p.pos += 1usize
            } else if current(p) == T_NUMBER {
                parts[index] = p.toks[p.pos].num
                flags |= 1u8 << u32(index)
                p.pos += 1usize
            } else {
                ret (0i32, Syntax)
            }
        }
        let close_error = match_token(p, T_RBRACKET)
        if close_error != ok { ret (0i32, close_error) }
        let (node, node_error) = add_node(p, K_SLICE, 0i32, 0i32)
        if node_error != ok { ret (0i32, node_error) }
        p.nodes[usize(node)].x = parts[0usize]
        p.nodes[usize(node)].y = parts[1usize]
        p.nodes[usize(node)].z = parts[2usize]
        p.nodes[usize(node)].flags = flags
        ret (node, ok)
    }
    if current(p) != T_NUMBER { ret (0i32, Syntax) }
    let value = p.toks[p.pos].num
    p.pos += 1usize
    let close_error = match_token(p, T_RBRACKET)
    if close_error != ok { ret (0i32, close_error) }
    let (node, node_error) = add_node(p, K_INDEX, 0i32, 0i32)
    if node_error != ok { ret (0i32, node_error) }
    p.nodes[usize(node)].num = value
    ret (node, ok)
}

fn project_if_slice(p: *Parser, left: i32, right: i32) -> (i32, err) {
    let (index_expr, index_error) = add_node(p, K_INDEXEXPR, left, right)
    if index_error != ok { ret (0i32, index_error) }
    if p.nodes[usize(right)].kind != K_SLICE { ret (index_expr, ok) }
    let (rhs, rhs_error) = projection_rhs(p, 20i32)
    if rhs_error != ok { ret (0i32, rhs_error) }
    let (node, node_error) = add_node(p, K_PROJECTION, index_expr, rhs)
    ret (node, node_error)
}

fn multi_select_list(p: *Parser) -> (i32, err) {
    var items: [32]i32 = zero
    var count = 0usize
    while true {
        let (item, item_error) = expression(p, 0i32)
        if item_error != ok { ret (0i32, item_error) }
        if count == 32usize { ret (0i32, TooLarge) }
        items[count] = item
        count += 1usize
        if current(p) == T_RBRACKET { break }
        let comma_error = match_token(p, T_COMMA)
        if comma_error != ok { ret (0i32, comma_error) }
    }
    p.pos += 1usize
    let (start, edges_error) = add_edges(p, items[0usize..count])
    if edges_error != ok { ret (0i32, edges_error) }
    let (node, node_error) = add_node(p, K_MULTI_LIST, start, i32(count))
    ret (node, node_error)
}

fn multi_select_hash(p: *Parser) -> (i32, err) {
    var items: [32]i32 = zero
    var count = 0usize
    while true {
        let key_kind = current(p)
        if key_kind != T_QIDENT && key_kind != T_IDENT { ret (0i32, Syntax) }
        let key = p.toks[p.pos].text
        p.pos += 1usize
        let colon_error = match_token(p, T_COLON)
        if colon_error != ok { ret (0i32, colon_error) }
        let (value, value_error) = expression(p, 0i32)
        if value_error != ok { ret (0i32, value_error) }
        let (pair, pair_error) = add_node(p, K_KEYVAL, value, 0i32)
        if pair_error != ok { ret (0i32, pair_error) }
        p.nodes[usize(pair)].text = key
        if count == 32usize { ret (0i32, TooLarge) }
        items[count] = pair
        count += 1usize
        if current(p) == T_COMMA {
            p.pos += 1usize
        } else if current(p) == T_RBRACE {
            p.pos += 1usize
            break
        }
    }
    let (start, edges_error) = add_edges(p, items[0usize..count])
    if edges_error != ok { ret (0i32, edges_error) }
    let (node, node_error) = add_node(p, K_MULTI_HASH, start, i32(count))
    ret (node, node_error)
}

fn compile(a: *mem.Arena, source: str) -> (Expr, err) {
    var toks: [128]Token = zero
    let (n, lex_error) = lex(a, source, toks[0usize..128usize])
    if lex_error != ok { ret (zero, lex_error) }
    let (nodes, nodes_error) = mem.alloc[Node](a, n * 4usize + 8usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (edges, edges_error) = mem.alloc[i32](a, n * 2usize + 8usize)
    if edges_error != ok { ret (zero, edges_error) }
    var p: Parser = zero
    p.toks = toks[0usize..n]
    p.n = n
    p.nodes = nodes
    p.edges = edges
    let (root, parse_error) = expression(&p, 0i32)
    if parse_error != ok { ret (zero, parse_error) }
    if current(&p) != T_EOF { ret (zero, Syntax) }
    var out: Expr = zero
    out.nodes = nodes[0usize..p.node_n]
    out.edges = edges[0usize..p.edge_n]
    out.root = root
    ret (out, ok)
}

// --- Values.

// 0 null, 1 boolean, 2 number, 3 string, 4 array, 5 object.
fn kind_of(v: json.Value) -> u8 {
    switch v {
    case .Null:
        ret 0u8
    case .Bool as flag:
        ret 1u8
    case .Number as n:
        ret 2u8
    case .String as s:
        ret 3u8
    case .Array as items:
        ret 4u8
    case .Object as members:
        ret 5u8
    default:
        ret 0u8
    }
}

fn type_name(v: json.Value) -> str {
    let k = kind_of(v)
    if k == 1u8 { ret "boolean" }
    if k == 2u8 { ret "number" }
    if k == 3u8 { ret "string" }
    if k == 4u8 { ret "array" }
    if k == 5u8 { ret "object" }
    ret "null"
}

fn as_array(v: json.Value) -> []const json.Value {
    switch v {
    case .Array as items:
        ret items
    default:
        var empty: []const json.Value = zero
        ret empty
    }
}

fn as_object(v: json.Value) -> []const json.Member {
    switch v {
    case .Object as members:
        ret members
    default:
        var empty: []const json.Member = zero
        ret empty
    }
}

fn as_string(v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn as_number(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (value, value_error) = json.number_f64(n)
        if value_error != ok { ret 0.0f64 }
        ret value
    default:
        ret 0.0f64
    }
}

fn number_lexeme(v: json.Value) -> str {
    switch v {
    case .Number as n:
        ret n.lexeme
    default:
        ret ""
    }
}

fn is_true_bool(v: json.Value) -> bool {
    switch v {
    case .Bool as flag:
        ret flag
    default:
        ret false
    }
}

// Null, false, "", [] and {} are false; 0 is true.
fn is_false(v: json.Value) -> bool {
    switch v {
    case .Null:
        ret true
    case .Bool as flag:
        ret !flag
    case .String as s:
        ret s.len == 0usize
    case .Array as items:
        ret items.len == 0usize
    case .Object as members:
        ret members.len == 0usize
    default:
        ret false
    }
}

fn find_member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if str.eq(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    ret (null_value(), false)
}

fn same_number(x: json.Value, y: json.Value) -> bool {
    let lx = number_lexeme(x)
    let ly = number_lexeme(y)
    if str.eq(lx, ly) { ret true }
    ret as_number(x) == as_number(y)
}

// Deep equality as python-jmespath has it: numbers by value, objects as unordered maps.
fn equals(x: json.Value, y: json.Value) -> bool {
    let kx = kind_of(x)
    if kx != kind_of(y) { ret false }
    if kx == 0u8 { ret true }
    if kx == 1u8 { ret is_true_bool(x) == is_true_bool(y) }
    if kx == 2u8 { ret same_number(x, y) }
    if kx == 3u8 { ret str.eq(as_string(x), as_string(y)) }
    if kx == 4u8 {
        let ax = as_array(x)
        let ay = as_array(y)
        if ax.len != ay.len { ret false }
        var i = 0usize
        while i < ax.len {
            if !equals(ax[i], ay[i]) { ret false }
            i += 1usize
        }
        ret true
    }
    let ox = as_object(x)
    let oy = as_object(y)
    if ox.len != oy.len { ret false }
    var j = 0usize
    while j < ox.len {
        let (other, found) = find_member(oy, ox[j].key)
        if !found || !equals(ox[j].value, other) { ret false }
        j += 1usize
    }
    ret true
}

fn values_of(a: *mem.Arena, n: usize) -> ([]json.Value, err) {
    let (items, items_error) = mem.alloc[json.Value](a, n)
    ret (items, items_error)
}

fn array_value(items: []const json.Value) -> json.Value {
    ret json.Value{ Array: items }
}

fn number_value(a: *mem.Arena, value: f64) -> (json.Value, err) {
    let (n, n_error) = json.number_from_f64(a, value)
    if n_error != ok { ret (null_value(), InvalidValue) }
    ret (json.Value{ Number: n }, ok)
}

fn bool_value(flag: bool) -> json.Value { ret json.Value{ Bool: flag } }

// Code points in a UTF-8 string.
fn code_points(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn reverse_string(a: *mem.Arena, s: str) -> (str, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, s.len)
    if buffer_error != ok { ret ("", buffer_error) }
    var out = s.len
    var i = 0usize
    while i < s.len {
        var j = i + 1usize
        while j < s.len && (s[j] & 192u8) == 128u8 { j += 1usize }
        out -= j - i
        var k = i
        while k < j {
            buffer[out + (k - i)] = s[k]
            k += 1usize
        }
        i = j
    }
    ret (buffer[0usize..s.len], ok)
}

fn compare_strings(x: str, y: str) -> i32 {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] {
            if x[i] < y[i] { ret -1i32 }
            ret 1i32
        }
        i += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

// -1/0/1 for two numbers or two strings; 2 when they are not comparable.
fn order(x: json.Value, y: json.Value) -> i32 {
    let kx = kind_of(x)
    let ky = kind_of(y)
    if kx == 2u8 && ky == 2u8 {
        let fx = as_number(x)
        let fy = as_number(y)
        if fx < fy { ret -1i32 }
        if fx > fy { ret 1i32 }
        ret 0i32
    }
    if kx == 3u8 && ky == 3u8 { ret compare_strings(as_string(x), as_string(y)) }
    ret 2i32
}

// --- Compact JSON, ASCII-only, as python's `json.dumps(separators=(",", ":"))`.

fn hex4(b: *str.Builder, v: u32) -> err {
    var shift = 12u32
    while true {
        let nibble = u8((v >> shift) & 15u32)
        var c = 48u8 + nibble
        if nibble >= 10u8 { c = 87u8 + nibble }
        try str.push_byte(b, c)
        if shift == 0u32 { break }
        shift -= 4u32
    }
    ret ok
}

fn write_string(b: *str.Builder, s: str) -> err {
    try str.push_byte(b, 34u8)
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            try str.push(b, "\\\"")
            i += 1usize
        } else if c == 92u8 {
            try str.push(b, "\\\\")
            i += 1usize
        } else if c == 10u8 {
            try str.push(b, "\\n")
            i += 1usize
        } else if c == 13u8 {
            try str.push(b, "\\r")
            i += 1usize
        } else if c == 9u8 {
            try str.push(b, "\\t")
            i += 1usize
        } else if c == 8u8 {
            try str.push(b, "\\b")
            i += 1usize
        } else if c == 12u8 {
            try str.push(b, "\\f")
            i += 1usize
        } else if c < 32u8 || c == 127u8 {
            if c == 127u8 {
                try str.push_byte(b, c)
            } else {
                try str.push(b, "\\u")
                try hex4(b, u32(c))
            }
            i += 1usize
        } else if c < 128u8 {
            try str.push_byte(b, c)
            i += 1usize
        } else {
            var point = 0u32
            var extra = 0usize
            if (c & 224u8) == 192u8 {
                point = u32(c & 31u8)
                extra = 1usize
            } else if (c & 240u8) == 224u8 {
                point = u32(c & 15u8)
                extra = 2usize
            } else {
                point = u32(c & 7u8)
                extra = 3usize
            }
            var k = 1usize
            while k <= extra && i + k < s.len {
                point = (point << 6u32) | u32(s[i + k] & 63u8)
                k += 1usize
            }
            i += 1usize + extra
            if point >= 65536u32 {
                let adjusted = point - 65536u32
                try str.push(b, "\\u")
                try hex4(b, 55296u32 + (adjusted >> 10u32))
                try str.push(b, "\\u")
                try hex4(b, 56320u32 + (adjusted & 1023u32))
            } else {
                try str.push(b, "\\u")
                try hex4(b, point)
            }
        }
    }
    try str.push_byte(b, 34u8)
    ret ok
}

fn write_value(b: *str.Builder, v: json.Value) -> err {
    switch v {
    case .Null:
        ret str.push(b, "null")
    case .Bool as flag:
        if flag { ret str.push(b, "true") }
        ret str.push(b, "false")
    case .Number as n:
        ret str.push(b, n.lexeme)
    case .String as s:
        ret write_string(b, s)
    case .Array as items:
        try str.push_byte(b, 91u8)
        var i = 0usize
        while i < items.len {
            if i > 0usize { try str.push_byte(b, 44u8) }
            try write_value(b, items[i])
            i += 1usize
        }
        ret str.push_byte(b, 93u8)
    case .Object as members:
        try str.push_byte(b, 123u8)
        var j = 0usize
        while j < members.len {
            if j > 0usize { try str.push_byte(b, 44u8) }
            try write_string(b, members[j].key)
            try str.push_byte(b, 58u8)
            try write_value(b, members[j].value)
            j += 1usize
        }
        ret str.push_byte(b, 125u8)
    default:
        ret ok
    }
}

fn stringify(a: *mem.Arena, v: json.Value) -> (str, err) {
    var (b, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret ("", builder_error) }
    let write_error = write_value(&b, v)
    if write_error != ok { ret ("", write_error) }
    ret (str.done(&b), ok)
}

// --- Evaluation.

type Ctx = struct { a: *mem.Arena, nodes: []const Node, edges: []const i32 }

// Python's slice normalization for a step and optional bounds over `len` elements:
// the first index, the (exclusive) stop, and the step.
fn slice_bounds(len: i64, has_start: bool, start: i64, has_stop: bool, stop: i64, step: i64) -> (i64, i64) {
    var lo = start
    var hi = stop
    if step > 0i64 {
        if !has_start { lo = 0i64 } else {
            if lo < 0i64 {
                lo += len
                if lo < 0i64 { lo = 0i64 }
            } else if lo > len { lo = len }
        }
        if !has_stop { hi = len } else {
            if hi < 0i64 {
                hi += len
                if hi < 0i64 { hi = 0i64 }
            } else if hi > len { hi = len }
        }
    } else {
        if !has_start { lo = len - 1i64 } else {
            if lo < 0i64 {
                lo += len
                if lo < 0i64 { lo = -1i64 }
            } else if lo >= len { lo = len - 1i64 }
        }
        if !has_stop { hi = -1i64 } else {
            if hi < 0i64 {
                hi += len
                if hi < 0i64 { hi = -1i64 }
            } else if hi >= len { hi = len - 1i64 }
        }
    }
    ret (lo, hi)
}

fn eval_slice(c: *Ctx, node: Node, v: json.Value) -> (json.Value, err) {
    let items = as_array(v)
    if kind_of(v) != 4u8 { ret (null_value(), ok) }
    var step = 1i64
    if (node.flags & 4u8) != 0u8 { step = node.z }
    if step == 0i64 { ret (null_value(), InvalidValue) }
    let (lo, hi) = slice_bounds(i64(items.len), (node.flags & 1u8) != 0u8, node.x, (node.flags & 2u8) != 0u8, node.y, step)
    let (out, out_error) = values_of(c.a, items.len)
    if out_error != ok { ret (null_value(), out_error) }
    var n = 0usize
    var i = lo
    if step > 0i64 {
        while i < hi {
            if i >= 0i64 && i < i64(items.len) {
                out[n] = items[usize(i)]
                n += 1usize
            }
            i += step
        }
    } else {
        while i > hi {
            if i >= 0i64 && i < i64(items.len) {
                out[n] = items[usize(i)]
                n += 1usize
            }
            i += step
        }
    }
    ret (array_value(out[0usize..n]), ok)
}

// Evaluates `node` once per element, dropping nulls: the projection body.
fn project(c: *Ctx, right: i32, items: []const json.Value) -> (json.Value, err) {
    let (out, out_error) = values_of(c.a, items.len)
    if out_error != ok { ret (null_value(), out_error) }
    var n = 0usize
    var i = 0usize
    while i < items.len {
        let (item, item_error) = eval(c, right, items[i])
        if item_error != ok { ret (null_value(), item_error) }
        if kind_of(item) != 0u8 {
            out[n] = item
            n += 1usize
        }
        i += 1usize
    }
    ret (array_value(out[0usize..n]), ok)
}

fn eval(c: *Ctx, idx: i32, v: json.Value) -> (json.Value, err) {
    let node = c.nodes[usize(idx)]
    let kind = node.kind
    if kind == K_FIELD {
        if kind_of(v) != 5u8 { ret (null_value(), ok) }
        let (found, present) = find_member(as_object(v), node.text)
        ret (found, ok)
    }
    if kind == K_LITERAL { ret (node.value, ok) }
    if kind == K_CURRENT { ret (v, ok) }
    if kind == K_SUBEXPR || kind == K_INDEXEXPR {
        let (left, left_error) = eval(c, node.a, v)
        if left_error != ok { ret (null_value(), left_error) }
        let (right, right_error) = eval(c, node.b, left)
        ret (right, right_error)
    }
    if kind == K_INDEX {
        if kind_of(v) != 4u8 { ret (null_value(), ok) }
        let items = as_array(v)
        var at = node.num
        if at < 0i64 { at += i64(items.len) }
        if at < 0i64 || at >= i64(items.len) { ret (null_value(), ok) }
        ret (items[usize(at)], ok)
    }
    if kind == K_SLICE {
        let (sliced, slice_error) = eval_slice(c, node, v)
        ret (sliced, slice_error)
    }
    if kind == K_PROJECTION {
        let (base, base_error) = eval(c, node.a, v)
        if base_error != ok { ret (null_value(), base_error) }
        if kind_of(base) != 4u8 { ret (null_value(), ok) }
        let (out, out_error) = project(c, node.b, as_array(base))
        ret (out, out_error)
    }
    if kind == K_VALUE_PROJECTION {
        let (base, base_error) = eval(c, node.a, v)
        if base_error != ok { ret (null_value(), base_error) }
        if kind_of(base) != 5u8 { ret (null_value(), ok) }
        let members = as_object(base)
        let (values, values_error) = values_of(c.a, members.len)
        if values_error != ok { ret (null_value(), values_error) }
        var i = 0usize
        while i < members.len {
            values[i] = members[i].value
            i += 1usize
        }
        let (out, out_error) = project(c, node.b, values)
        ret (out, out_error)
    }
    if kind == K_FILTER {
        let (base, base_error) = eval(c, node.a, v)
        if base_error != ok { ret (null_value(), base_error) }
        if kind_of(base) != 4u8 { ret (null_value(), ok) }
        let items = as_array(base)
        let (out, out_error) = values_of(c.a, items.len)
        if out_error != ok { ret (null_value(), out_error) }
        var n = 0usize
        var i = 0usize
        while i < items.len {
            let (test, test_error) = eval(c, node.c, items[i])
            if test_error != ok { ret (null_value(), test_error) }
            if !is_false(test) {
                let (item, item_error) = eval(c, node.b, items[i])
                if item_error != ok { ret (null_value(), item_error) }
                if kind_of(item) != 0u8 {
                    out[n] = item
                    n += 1usize
                }
            }
            i += 1usize
        }
        ret (array_value(out[0usize..n]), ok)
    }
    if kind == K_FLATTEN {
        let (base, base_error) = eval(c, node.a, v)
        if base_error != ok { ret (null_value(), base_error) }
        if kind_of(base) != 4u8 { ret (null_value(), ok) }
        let items = as_array(base)
        var total = 0usize
        var i = 0usize
        while i < items.len {
            if kind_of(items[i]) == 4u8 {
                total += as_array(items[i]).len
            } else {
                total += 1usize
            }
            i += 1usize
        }
        let (out, out_error) = values_of(c.a, total)
        if out_error != ok { ret (null_value(), out_error) }
        var n = 0usize
        i = 0usize
        while i < items.len {
            if kind_of(items[i]) == 4u8 {
                let inner = as_array(items[i])
                var j = 0usize
                while j < inner.len {
                    out[n] = inner[j]
                    n += 1usize
                    j += 1usize
                }
            } else {
                out[n] = items[i]
                n += 1usize
            }
            i += 1usize
        }
        ret (array_value(out[0usize..n]), ok)
    }
    if kind == K_COMPARE {
        let (left, left_error) = eval(c, node.a, v)
        if left_error != ok { ret (null_value(), left_error) }
        let (right, right_error) = eval(c, node.b, v)
        if right_error != ok { ret (null_value(), right_error) }
        let op = u8(node.num)
        if op == T_EQ { ret (bool_value(equals(left, right)), ok) }
        if op == T_NE { ret (bool_value(!equals(left, right)), ok) }
        let o = order(left, right)
        if o == 2i32 { ret (null_value(), ok) }
        if op == T_LT { ret (bool_value(o < 0i32), ok) }
        if op == T_LTE { ret (bool_value(o <= 0i32), ok) }
        if op == T_GT { ret (bool_value(o > 0i32), ok) }
        ret (bool_value(o >= 0i32), ok)
    }
    if kind == K_OR {
        let (left, left_error) = eval(c, node.a, v)
        if left_error != ok { ret (null_value(), left_error) }
        if !is_false(left) { ret (left, ok) }
        let (right, right_error) = eval(c, node.b, v)
        ret (right, right_error)
    }
    if kind == K_AND {
        let (left, left_error) = eval(c, node.a, v)
        if left_error != ok { ret (null_value(), left_error) }
        if is_false(left) { ret (left, ok) }
        let (right, right_error) = eval(c, node.b, v)
        ret (right, right_error)
    }
    if kind == K_NOT {
        let (inner, inner_error) = eval(c, node.a, v)
        if inner_error != ok { ret (null_value(), inner_error) }
        ret (bool_value(is_false(inner)), ok)
    }
    if kind == K_MULTI_LIST {
        if kind_of(v) == 0u8 { ret (null_value(), ok) }
        let count = usize(node.b)
        let (out, out_error) = values_of(c.a, count)
        if out_error != ok { ret (null_value(), out_error) }
        var i = 0usize
        while i < count {
            let (item, item_error) = eval(c, c.edges[usize(node.a) + i], v)
            if item_error != ok { ret (null_value(), item_error) }
            out[i] = item
            i += 1usize
        }
        ret (array_value(out), ok)
    }
    if kind == K_MULTI_HASH {
        if kind_of(v) == 0u8 { ret (null_value(), ok) }
        let count = usize(node.b)
        let (members, members_error) = mem.alloc[json.Member](c.a, count)
        if members_error != ok { ret (null_value(), members_error) }
        var n = 0usize
        var i = 0usize
        while i < count {
            let pair = c.nodes[usize(c.edges[usize(node.a) + i])]
            let (item, item_error) = eval(c, pair.a, v)
            if item_error != ok { ret (null_value(), item_error) }
            var slot = n
            var j = 0usize
            while j < n {
                if str.eq(members[j].key, pair.text) { slot = j }
                j += 1usize
            }
            members[slot] = json.Member{ key: pair.text, value: item }
            if slot == n { n += 1usize }
            i += 1usize
        }
        ret (json.Value{ Object: members[0usize..n] }, ok)
    }
    if kind == K_FUNCTION {
        let (out, out_error) = call(c, node, v)
        ret (out, out_error)
    }
    // An expression reference outside a function argument is not a value.
    ret (null_value(), Type)
}

// --- Functions.

type Arg = struct { is_ref: bool, node: i32, value: json.Value }


fn array_of_numbers(v: json.Value) -> bool {
    let items = as_array(v)
    var i = 0usize
    while i < items.len {
        if kind_of(items[i]) != 2u8 { ret false }
        i += 1usize
    }
    ret true
}

fn array_of_strings(v: json.Value) -> bool {
    let items = as_array(v)
    var i = 0usize
    while i < items.len {
        if kind_of(items[i]) != 3u8 { ret false }
        i += 1usize
    }
    ret true
}

// The element kind of a number-or-string array: 2, 3, or 0 when it is neither (or mixed).
fn homogeneous(v: json.Value) -> u8 {
    let items = as_array(v)
    if items.len == 0usize { ret 2u8 }
    let first = kind_of(items[0usize])
    if first != 2u8 && first != 3u8 { ret 0u8 }
    var i = 1usize
    while i < items.len {
        if kind_of(items[i]) != first { ret 0u8 }
        i += 1usize
    }
    ret first
}

// Stable sort of `items` by `keys` (numbers or strings of one kind), in place.
fn sort_pairs(items: []json.Value, keys: []json.Value) {
    var i = 1usize
    while i < items.len {
        var j = i
        while j > 0usize && order(keys[j - 1usize], keys[j]) > 0i32 {
            let ti = items[j]
            items[j] = items[j - 1usize]
            items[j - 1usize] = ti
            let tk = keys[j]
            keys[j] = keys[j - 1usize]
            keys[j - 1usize] = tk
            j -= 1usize
        }
        i += 1usize
    }
}

fn parse_number_text(a: *mem.Arena, s: str) -> (json.Value, bool) {
    var start = 0usize
    var end = s.len
    while start < end && is_blank(s[start]) { start += 1usize }
    while end > start && is_blank(s[end - 1usize]) { end -= 1usize }
    let t = s[start..end]
    if t.len == 0usize { ret (null_value(), false) }
    var at = 0usize
    var negative = false
    if t[at] == 45u8 || t[at] == 43u8 {
        negative = t[at] == 45u8
        at += 1usize
    }
    var int_digits = 0usize
    let int_start = at
    while at < t.len && is_digit(t[at]) {
        at += 1usize
        int_digits += 1usize
    }
    var frac_digits = 0usize
    var has_point = false
    if at < t.len && t[at] == 46u8 {
        has_point = true
        at += 1usize
        while at < t.len && is_digit(t[at]) {
            at += 1usize
            frac_digits += 1usize
        }
    }
    if int_digits == 0usize && frac_digits == 0usize { ret (null_value(), false) }
    var has_exp = false
    if at < t.len && (t[at] == 101u8 || t[at] == 69u8) {
        has_exp = true
        at += 1usize
        if at < t.len && (t[at] == 45u8 || t[at] == 43u8) { at += 1usize }
        var exp_digits = 0usize
        while at < t.len && is_digit(t[at]) {
            at += 1usize
            exp_digits += 1usize
        }
        if exp_digits == 0usize { ret (null_value(), false) }
    }
    if at != t.len { ret (null_value(), false) }
    // A canonical JSON lexeme for the same value.
    var (b, builder_error) = str.builder(a, t.len + 4usize)
    if builder_error != ok { ret (null_value(), false) }
    if negative { if str.push_byte(&b, 45u8) != ok { ret (null_value(), false) } }
    if int_digits == 0usize {
        if str.push_byte(&b, 48u8) != ok { ret (null_value(), false) }
    } else {
        // Leading zeros are dropped, as int() does.
        var k = int_start
        while k + 1usize < int_start + int_digits && t[k] == 48u8 { k += 1usize }
        if str.push(&b, t[k..int_start + int_digits]) != ok { ret (null_value(), false) }
    }
    if has_point && frac_digits > 0usize {
        if str.push_byte(&b, 46u8) != ok { ret (null_value(), false) }
        let frac_start = int_start + int_digits + 1usize
        if str.push(&b, t[frac_start..frac_start + frac_digits]) != ok { ret (null_value(), false) }
    }
    if has_exp {
        let exp_start = int_start + int_digits
        var from = exp_start
        if has_point { from = exp_start + 1usize + frac_digits }
        if str.push(&b, t[from..t.len]) != ok { ret (null_value(), false) }
    }
    let lexeme = str.done(&b)
    let (n, n_error) = json.number(lexeme)
    if n_error != ok { ret (null_value(), false) }
    ret (json.Value{ Number: n }, true)
}

fn call(c: *Ctx, node: Node, v: json.Value) -> (json.Value, err) {
    let count = usize(node.b)
    var args: [16]Arg = zero
    var i = 0usize
    while i < count {
        let child = c.edges[usize(node.a) + i]
        if c.nodes[usize(child)].kind == K_EXPREF {
            args[i].is_ref = true
            args[i].node = c.nodes[usize(child)].a
        } else {
            let (value, value_error) = eval(c, child, v)
            if value_error != ok { ret (null_value(), value_error) }
            args[i].value = value
        }
        i += 1usize
    }
    let name = node.text
    let a = c.a
    // Validate the arity first, then the types, the way python does per signature.
    if str.eq(name, "abs") || str.eq(name, "ceil") || str.eq(name, "floor") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || kind_of(args[0usize].value) != 2u8 { ret (null_value(), Type) }
        let x = as_number(args[0usize].value)
        var r = x
        if str.eq(name, "abs") {
            if x < 0.0f64 { r = 0.0f64 - x }
        } else if str.eq(name, "ceil") {
            r = math_ceil(x)
        } else {
            r = math_floor(x)
        }
        // An integral input keeps its spelling when `abs` leaves it alone.
        if str.eq(name, "abs") && x >= 0.0f64 { ret (args[0usize].value, ok) }
        let (out, out_error) = number_value(a, r)
        ret (out, out_error)
    }
    if str.eq(name, "avg") || str.eq(name, "sum") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || kind_of(args[0usize].value) != 4u8 || !array_of_numbers(args[0usize].value) { ret (null_value(), Type) }
        let items = as_array(args[0usize].value)
        if items.len == 0usize && str.eq(name, "avg") { ret (null_value(), ok) }
        var total = 0.0f64
        var k = 0usize
        while k < items.len {
            total += as_number(items[k])
            k += 1usize
        }
        if str.eq(name, "avg") { total = total / f64(items.len) }
        let (out, out_error) = number_value(a, total)
        ret (out, out_error)
    }
    if str.eq(name, "not_null") {
        if count < 1usize { ret (null_value(), Arity) }
        var k = 0usize
        while k < count {
            if args[k].is_ref { ret (null_value(), Type) }
            if kind_of(args[k].value) != 0u8 { ret (args[k].value, ok) }
            k += 1usize
        }
        ret (null_value(), ok)
    }
    if str.eq(name, "to_array") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref { ret (null_value(), Type) }
        if kind_of(args[0usize].value) == 4u8 { ret (args[0usize].value, ok) }
        let (one, one_error) = values_of(a, 1usize)
        if one_error != ok { ret (null_value(), one_error) }
        one[0usize] = args[0usize].value
        ret (array_value(one), ok)
    }
    if str.eq(name, "to_string") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref { ret (null_value(), Type) }
        if kind_of(args[0usize].value) == 3u8 { ret (args[0usize].value, ok) }
        let (text, text_error) = stringify(a, args[0usize].value)
        if text_error != ok { ret (null_value(), text_error) }
        ret (json.Value{ String: text }, ok)
    }
    if str.eq(name, "to_number") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref { ret (null_value(), Type) }
        let k = kind_of(args[0usize].value)
        if k == 2u8 { ret (args[0usize].value, ok) }
        if k != 3u8 { ret (null_value(), ok) }
        let (parsed, parsed_ok) = parse_number_text(a, as_string(args[0usize].value))
        if !parsed_ok { ret (null_value(), ok) }
        ret (parsed, ok)
    }
    if str.eq(name, "type") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref { ret (null_value(), Type) }
        ret (json.Value{ String: type_name(args[0usize].value) }, ok)
    }
    if str.eq(name, "contains") {
        if count != 2usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || args[1usize].is_ref { ret (null_value(), Type) }
        let subject = args[0usize].value
        let needle = args[1usize].value
        if kind_of(subject) == 3u8 {
            if kind_of(needle) != 3u8 { ret (null_value(), Type) }
            let (at, found) = str.find(as_string(subject), as_string(needle))
            ret (bool_value(found), ok)
        }
        if kind_of(subject) != 4u8 { ret (null_value(), Type) }
        let items = as_array(subject)
        var k = 0usize
        while k < items.len {
            if equals(items[k], needle) { ret (bool_value(true), ok) }
            k += 1usize
        }
        ret (bool_value(false), ok)
    }
    if str.eq(name, "length") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref { ret (null_value(), Type) }
        let k = kind_of(args[0usize].value)
        var n = 0usize
        if k == 3u8 {
            n = code_points(as_string(args[0usize].value))
        } else if k == 4u8 {
            n = as_array(args[0usize].value).len
        } else if k == 5u8 {
            n = as_object(args[0usize].value).len
        } else {
            ret (null_value(), Type)
        }
        let (out, out_error) = number_value(a, f64(n))
        ret (out, out_error)
    }
    if str.eq(name, "ends_with") || str.eq(name, "starts_with") {
        if count != 2usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || args[1usize].is_ref || kind_of(args[0usize].value) != 3u8 || kind_of(args[1usize].value) != 3u8 { ret (null_value(), Type) }
        let text = as_string(args[0usize].value)
        let part = as_string(args[1usize].value)
        if part.len > text.len { ret (bool_value(false), ok) }
        var offset = 0usize
        if str.eq(name, "ends_with") { offset = text.len - part.len }
        ret (bool_value(str.eq(text[offset..offset + part.len], part)), ok)
    }
    if str.eq(name, "reverse") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref { ret (null_value(), Type) }
        let k = kind_of(args[0usize].value)
        if k == 3u8 {
            let (text, text_error) = reverse_string(a, as_string(args[0usize].value))
            if text_error != ok { ret (null_value(), text_error) }
            ret (json.Value{ String: text }, ok)
        }
        if k != 4u8 { ret (null_value(), Type) }
        let items = as_array(args[0usize].value)
        let (out, out_error) = values_of(a, items.len)
        if out_error != ok { ret (null_value(), out_error) }
        var k2 = 0usize
        while k2 < items.len {
            out[k2] = items[items.len - 1usize - k2]
            k2 += 1usize
        }
        ret (array_value(out), ok)
    }
    if str.eq(name, "join") {
        if count != 2usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || args[1usize].is_ref || kind_of(args[0usize].value) != 3u8 || kind_of(args[1usize].value) != 4u8 || !array_of_strings(args[1usize].value) { ret (null_value(), Type) }
        let glue = as_string(args[0usize].value)
        let items = as_array(args[1usize].value)
        var (b, builder_error) = str.builder(a, 64usize)
        if builder_error != ok { ret (null_value(), builder_error) }
        var k = 0usize
        while k < items.len {
            if k > 0usize { try str.push(&b, glue) }
            try str.push(&b, as_string(items[k]))
            k += 1usize
        }
        ret (json.Value{ String: str.done(&b) }, ok)
    }
    if str.eq(name, "keys") || str.eq(name, "values") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || kind_of(args[0usize].value) != 5u8 { ret (null_value(), Type) }
        let members = as_object(args[0usize].value)
        let (out, out_error) = values_of(a, members.len)
        if out_error != ok { ret (null_value(), out_error) }
        var k = 0usize
        while k < members.len {
            if str.eq(name, "keys") {
                out[k] = json.Value{ String: members[k].key }
            } else {
                out[k] = members[k].value
            }
            k += 1usize
        }
        ret (array_value(out), ok)
    }
    if str.eq(name, "merge") {
        if count < 1usize { ret (null_value(), Arity) }
        var total = 0usize
        var k = 0usize
        while k < count {
            if args[k].is_ref || kind_of(args[k].value) != 5u8 { ret (null_value(), Type) }
            total += as_object(args[k].value).len
            k += 1usize
        }
        let (members, members_error) = mem.alloc[json.Member](a, total)
        if members_error != ok { ret (null_value(), members_error) }
        var n = 0usize
        k = 0usize
        while k < count {
            let source = as_object(args[k].value)
            var m = 0usize
            while m < source.len {
                var slot = n
                var j = 0usize
                while j < n {
                    if str.eq(members[j].key, source[m].key) { slot = j }
                    j += 1usize
                }
                members[slot] = source[m]
                if slot == n { n += 1usize }
                m += 1usize
            }
            k += 1usize
        }
        ret (json.Value{ Object: members[0usize..n] }, ok)
    }
    if str.eq(name, "max") || str.eq(name, "min") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || kind_of(args[0usize].value) != 4u8 { ret (null_value(), Type) }
        if homogeneous(args[0usize].value) == 0u8 { ret (null_value(), Type) }
        let items = as_array(args[0usize].value)
        if items.len == 0usize { ret (null_value(), ok) }
        var best = items[0usize]
        var k = 1usize
        while k < items.len {
            let o = order(items[k], best)
            if str.eq(name, "max") && o > 0i32 { best = items[k] }
            if str.eq(name, "min") && o < 0i32 { best = items[k] }
            k += 1usize
        }
        ret (best, ok)
    }
    if str.eq(name, "sort") {
        if count != 1usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || kind_of(args[0usize].value) != 4u8 { ret (null_value(), Type) }
        if homogeneous(args[0usize].value) == 0u8 { ret (null_value(), Type) }
        let items = as_array(args[0usize].value)
        let (out, out_error) = values_of(a, items.len)
        if out_error != ok { ret (null_value(), out_error) }
        let (keys, keys_error) = values_of(a, items.len)
        if keys_error != ok { ret (null_value(), keys_error) }
        var k = 0usize
        while k < items.len {
            out[k] = items[k]
            keys[k] = items[k]
            k += 1usize
        }
        sort_pairs(out, keys)
        ret (array_value(out), ok)
    }
    if str.eq(name, "map") {
        if count != 2usize { ret (null_value(), Arity) }
        if !args[0usize].is_ref || args[1usize].is_ref || kind_of(args[1usize].value) != 4u8 { ret (null_value(), Type) }
        let items = as_array(args[1usize].value)
        let (out, out_error) = values_of(a, items.len)
        if out_error != ok { ret (null_value(), out_error) }
        var k = 0usize
        while k < items.len {
            let (item, item_error) = eval(c, args[0usize].node, items[k])
            if item_error != ok { ret (null_value(), item_error) }
            out[k] = item
            k += 1usize
        }
        ret (array_value(out), ok)
    }
    if str.eq(name, "sort_by") || str.eq(name, "min_by") || str.eq(name, "max_by") {
        if count != 2usize { ret (null_value(), Arity) }
        if args[0usize].is_ref || kind_of(args[0usize].value) != 4u8 || !args[1usize].is_ref { ret (null_value(), Type) }
        let items = as_array(args[0usize].value)
        if items.len == 0usize {
            if str.eq(name, "sort_by") { ret (args[0usize].value, ok) }
            ret (null_value(), ok)
        }
        let (keys, keys_error) = values_of(a, items.len)
        if keys_error != ok { ret (null_value(), keys_error) }
        var k = 0usize
        var first_kind = 0u8
        while k < items.len {
            let (key, key_error) = eval(c, args[1usize].node, items[k])
            if key_error != ok { ret (null_value(), key_error) }
            let kk = kind_of(key)
            if kk != 2u8 && kk != 3u8 { ret (null_value(), Type) }
            if k == 0usize { first_kind = kk }
            // sort_by requires the first key's type throughout; min_by and max_by compare
            // across the array and refuse a mix.
            if kk != first_kind { ret (null_value(), Type) }
            keys[k] = key
            k += 1usize
        }
        if str.eq(name, "sort_by") {
            let (out, out_error) = values_of(a, items.len)
            if out_error != ok { ret (null_value(), out_error) }
            k = 0usize
            while k < items.len {
                out[k] = items[k]
                k += 1usize
            }
            sort_pairs(out, keys)
            ret (array_value(out), ok)
        }
        var best = 0usize
        k = 1usize
        while k < items.len {
            let o = order(keys[k], keys[best])
            if str.eq(name, "max_by") && o > 0i32 { best = k }
            if str.eq(name, "min_by") && o < 0i32 { best = k }
            k += 1usize
        }
        ret (items[best], ok)
    }
    ret (null_value(), UnknownFunction)
}

fn math_floor(x: f64) -> f64 {
    let t = f64(i64(x))
    if t > x { ret t - 1.0f64 }
    ret t
}

fn math_ceil(x: f64) -> f64 {
    let t = f64(i64(x))
    if t < x { ret t + 1.0f64 }
    ret t
}

fn eval_expr(a: *mem.Arena, expr: Expr, data: json.Value) -> (json.Value, err) {
    var c: Ctx = zero
    c.a = a
    c.nodes = expr.nodes
    c.edges = expr.edges
    let (out, out_error) = eval(&c, expr.root, data)
    ret (out, out_error)
}

// Compile and run in one step.
fn search(a: *mem.Arena, source: str, data: json.Value) -> (json.Value, err) {
    let (expr, compile_error) = compile(a, source)
    if compile_error != ok { ret (null_value(), compile_error) }
    let (out, out_error) = eval_expr(a, expr, data)
    ret (out, out_error)
}
