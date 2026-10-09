// XPath 1.0 over an `e.fmt.xml` document: the expression grammar with every operator, all thirteen
// axes but `namespace`, the node tests, predicates, and the core function library, with the four value
// types (node-set, string, number, boolean) and their conversions as the specification defines them.
// `compile` parses an expression once into an arena; `evaluate` runs it against a context node.
//
// Nodes are the DOM's: an element, text, comment or processing instruction by its `NodeId`, and an
// attribute as its owner element plus an index (`XNode.attribute` is 1 + the index in the owner's
// attribute list; xmlns declarations are not attribute nodes). Node-sets are in document order, which is
// the order the DOM numbers nodes in. A name test with no prefix matches the null namespace, as XPath 1.0
// says, and a prefixed one resolves its prefix through the bindings given to `compile`; the element or
// attribute's own namespace is resolved through the document's xmlns attributes.
//
// Not here: the `namespace` axis (always empty), `id()` (no DTD, so empty) and variables other than the
// ones a caller binds in `Variables`. XSLT's extra functions arrive through `Extensions`.

use e.fmt.xml as xml
use e.math
use e.mem
use e.str
use e.text.utf8

error Invalid
error Unsupported
error UnknownFunction
error UnknownVariable
error WrongArity
error TypeMismatch
error TooComplex

const NONE: u32 = 4294967295u32

type XNode = struct { id: u32, attribute: u32 }
type Kind = enum u8 { NodeSet, String, Number, Boolean }
type Value = struct { kind: Kind, nodes: []XNode, text: str, number: f64, flag: bool }

type Binding = struct { prefix: str, uri: str }
type Variable = struct { name: str, value: Value }
type Variables = struct { items: []Variable, count: usize }

// What the host (XSLT) adds to the language: `current()` and `generate-id()` need the stylesheet's
// current node and a stable identity for a node.
type Extensions = struct { current: XNode, has_current: bool }

type Expr = struct { kind: u8, op: u8, left: u32, right: u32, text: str, number: f64, args: []u32, steps: []Step, absolute: bool, preds: []u32 }
type Step = struct { axis: u8, test: u8, prefix: str, local: str, preds: []u32 }
type Compiled = struct { exprs: []Expr, count: usize, root: u32, bindings: []const Binding }

// Expression kinds.
const E_OR: u8 = 1u8
const E_AND: u8 = 2u8
const E_EQ: u8 = 3u8
const E_NE: u8 = 4u8
const E_LT: u8 = 5u8
const E_LE: u8 = 6u8
const E_GT: u8 = 7u8
const E_GE: u8 = 8u8
const E_ADD: u8 = 9u8
const E_SUB: u8 = 10u8
const E_MUL: u8 = 11u8
const E_DIV: u8 = 12u8
const E_MOD: u8 = 13u8
const E_NEG: u8 = 14u8
const E_UNION: u8 = 15u8
const E_NUMBER: u8 = 16u8
const E_LITERAL: u8 = 17u8
const E_VAR: u8 = 18u8
const E_CALL: u8 = 19u8
const E_PATH: u8 = 20u8

// Axes.
const A_CHILD: u8 = 0u8
const A_DESCENDANT: u8 = 1u8
const A_PARENT: u8 = 2u8
const A_ANCESTOR: u8 = 3u8
const A_FOLLOWING_SIBLING: u8 = 4u8
const A_PRECEDING_SIBLING: u8 = 5u8
const A_FOLLOWING: u8 = 6u8
const A_PRECEDING: u8 = 7u8
const A_ATTRIBUTE: u8 = 8u8
const A_NAMESPACE: u8 = 9u8
const A_SELF: u8 = 10u8
const A_DESCENDANT_OR_SELF: u8 = 11u8
const A_ANCESTOR_OR_SELF: u8 = 12u8

// Node tests.
const T_NAME: u8 = 0u8
const T_ANY: u8 = 1u8
const T_PREFIX_ANY: u8 = 2u8
const T_NODE: u8 = 3u8
const T_TEXT: u8 = 4u8
const T_COMMENT: u8 = 5u8
const T_PI: u8 = 6u8

fn same(a: str, b: str) -> bool { ret str.eq(a, b) }

// ---- tokens ----

type Token = struct { kind: u8, text: str, number: f64 }

const K_END: u8 = 0u8
const K_LPAREN: u8 = 1u8
const K_RPAREN: u8 = 2u8
const K_LBRACKET: u8 = 3u8
const K_RBRACKET: u8 = 4u8
const K_DOT: u8 = 5u8
const K_DOTDOT: u8 = 6u8
const K_AT: u8 = 7u8
const K_COMMA: u8 = 8u8
const K_COLONCOLON: u8 = 9u8
const K_SLASH: u8 = 10u8
const K_SLASHSLASH: u8 = 11u8
const K_PIPE: u8 = 12u8
const K_PLUS: u8 = 13u8
const K_MINUS: u8 = 14u8
const K_EQ: u8 = 15u8
const K_NE: u8 = 16u8
const K_LT: u8 = 17u8
const K_LE: u8 = 18u8
const K_GT: u8 = 19u8
const K_GE: u8 = 20u8
const K_STAR: u8 = 21u8
const K_NUMBER: u8 = 22u8
const K_LITERAL: u8 = 23u8
const K_NAME: u8 = 24u8
const K_VAR: u8 = 25u8
const K_PREFIX_STAR: u8 = 26u8
const K_MUL: u8 = 44u8

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn name_start(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c >= 128u8 }
fn name_byte(c: u8) -> bool { ret name_start(c) || is_digit(c) || c == 45u8 || c == 46u8 }

// An NCName from `at`: the index after it.
fn scan_ncname(text: str, at: usize) -> usize {
    var i = at
    if i >= text.len || !name_start(text[i]) { ret at }
    while i < text.len && name_byte(text[i]) { i += 1usize }
    ret i
}

// Whether the previous token makes the next `*` or name an operator (XPath 1.0 section 3.7).
fn operator_context(prev: u8, has_prev: bool) -> bool {
    if !has_prev { ret false }
    ret !(prev == K_AT || prev == K_COLONCOLON || prev == K_LPAREN || prev == K_LBRACKET || prev == K_COMMA || prev == K_SLASH || prev == K_SLASHSLASH || prev == K_PIPE || prev == K_PLUS || prev == K_MINUS || prev == K_EQ || prev == K_NE || prev == K_LT || prev == K_LE || prev == K_GT || prev == K_GE || prev == K_MUL || prev == K_AND || prev == K_OR || prev == K_MOD || prev == K_DIV)
}

// Token kinds 40..: the operator names, kept apart from K_NAME so the parser sees them as operators.
const K_AND: u8 = 40u8
const K_OR: u8 = 41u8
const K_MOD: u8 = 42u8
const K_DIV: u8 = 43u8

fn tokenize(a: *mem.Arena, text: str) -> ([]Token, usize, err) {
    let (tokens, alloc_error) = mem.alloc[Token](a, text.len + 2usize)
    if alloc_error != ok { ret (zero, 0usize, alloc_error) }
    var count = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_space(c) {
            i += 1usize
            continue
        }
        var prev = K_END
        var has_prev = false
        if count > 0usize {
            prev = tokens[count - 1usize].kind
            has_prev = true
        }
        var kind = K_END
        var width = 1usize
        var lexeme = ""
        var number = 0.0f64
        if c == 40u8 { kind = K_LPAREN } else if c == 41u8 { kind = K_RPAREN } else if c == 91u8 { kind = K_LBRACKET } else if c == 93u8 { kind = K_RBRACKET } else if c == 64u8 { kind = K_AT } else if c == 44u8 { kind = K_COMMA } else if c == 124u8 { kind = K_PIPE } else if c == 43u8 { kind = K_PLUS } else if c == 45u8 { kind = K_MINUS } else if c == 61u8 { kind = K_EQ } else if c == 36u8 {
            let end = scan_ncname(text, i + 1usize)
            if end == i + 1usize { ret (zero, 0usize, Invalid) }
            var stop = end
            if stop < text.len && text[stop] == 58u8 && stop + 1usize < text.len && name_start(text[stop + 1usize]) { stop = scan_ncname(text, stop + 1usize) }
            kind = K_VAR
            lexeme = text[i + 1usize..stop]
            width = stop - i
        } else if c == 33u8 {
            if i + 1usize >= text.len || text[i + 1usize] != 61u8 { ret (zero, 0usize, Invalid) }
            kind = K_NE
            width = 2usize
        } else if c == 60u8 {
            if i + 1usize < text.len && text[i + 1usize] == 61u8 {
                kind = K_LE
                width = 2usize
            } else {
                kind = K_LT
            }
        } else if c == 62u8 {
            if i + 1usize < text.len && text[i + 1usize] == 61u8 {
                kind = K_GE
                width = 2usize
            } else {
                kind = K_GT
            }
        } else if c == 47u8 {
            if i + 1usize < text.len && text[i + 1usize] == 47u8 {
                kind = K_SLASHSLASH
                width = 2usize
            } else {
                kind = K_SLASH
            }
        } else if c == 46u8 {
            if i + 1usize < text.len && text[i + 1usize] == 46u8 {
                kind = K_DOTDOT
                width = 2usize
            } else if i + 1usize < text.len && is_digit(text[i + 1usize]) {
                var j = i + 1usize
                while j < text.len && is_digit(text[j]) { j += 1usize }
                kind = K_NUMBER
                lexeme = text[i..j]
                width = j - i
            } else {
                kind = K_DOT
            }
        } else if c == 58u8 {
            if i + 1usize < text.len && text[i + 1usize] == 58u8 {
                kind = K_COLONCOLON
                width = 2usize
            } else {
                ret (zero, 0usize, Invalid)
            }
        } else if c == 42u8 {
            if operator_context(prev, has_prev) { kind = K_MUL } else { kind = K_STAR }
            lexeme = "*"
        } else if c == 34u8 || c == 39u8 {
            var j = i + 1usize
            while j < text.len && text[j] != c { j += 1usize }
            if j >= text.len { ret (zero, 0usize, Invalid) }
            kind = K_LITERAL
            lexeme = text[i + 1usize..j]
            width = j + 1usize - i
        } else if is_digit(c) {
            var j = i
            while j < text.len && is_digit(text[j]) { j += 1usize }
            if j < text.len && text[j] == 46u8 {
                j += 1usize
                while j < text.len && is_digit(text[j]) { j += 1usize }
            }
            kind = K_NUMBER
            lexeme = text[i..j]
            width = j - i
        } else if name_start(c) {
            let end = scan_ncname(text, i)
            var stop = end
            var prefix_star = false
            if stop < text.len && text[stop] == 58u8 && !(stop + 1usize < text.len && text[stop + 1usize] == 58u8) {
                if stop + 1usize < text.len && text[stop + 1usize] == 42u8 {
                    stop += 2usize
                    prefix_star = true
                } else if stop + 1usize < text.len && name_start(text[stop + 1usize]) {
                    stop = scan_ncname(text, stop + 1usize)
                }
            }
            lexeme = text[i..stop]
            width = stop - i
            if prefix_star {
                kind = K_PREFIX_STAR
            } else {
                kind = K_NAME
                if operator_context(prev, has_prev) {
                    if same(lexeme, "and") { kind = K_AND } else if same(lexeme, "or") { kind = K_OR } else if same(lexeme, "mod") { kind = K_MOD } else if same(lexeme, "div") { kind = K_DIV }
                }
            }
        } else {
            ret (zero, 0usize, Invalid)
        }
        if kind == K_NUMBER {
            var digits = lexeme
            if digits.len > 0usize && digits[digits.len - 1usize] == 46u8 { digits = digits[..digits.len - 1usize] }
            if digits.len > 0usize && digits[0usize] == 46u8 {
                let (padded, pad_error) = str.concat(a, "0", digits)
                if pad_error != ok { ret (zero, 0usize, pad_error) }
                digits = padded
            }
            let (v, parse_error) = str.parse_f64(digits)
            if parse_error != ok { ret (zero, 0usize, Invalid) }
            number = v
        }
        tokens[count] = Token { kind: kind, text: lexeme, number: number }
        count += 1usize
        i += width
    }
    tokens[count] = Token { kind: K_END, text: "", number: 0.0f64 }
    ret (tokens, count, ok)
}

// ---- parser ----

type Parser = struct { a: *mem.Arena, tokens: []Token, count: usize, at: usize, exprs: []Expr, used: usize, depth: u32 }

fn peek_kind(p: *const Parser) -> u8 { ret p.tokens[p.at].kind }

fn new_expr(p: *Parser, kind: u8) -> (u32, err) {
    if p.used >= p.exprs.len { ret (NONE, TooComplex) }
    let at = p.used
    p.exprs[at] = Expr { kind: kind, op: 0u8, left: NONE, right: NONE, text: "", number: 0.0f64, args: zero, steps: zero, absolute: false, preds: zero }
    p.used += 1usize
    ret (u32(at), ok)
}

fn binary(p: *Parser, kind: u8, left: u32, right: u32) -> (u32, err) {
    let (e, e_error) = new_expr(p, kind)
    if e_error != ok { ret (NONE, e_error) }
    p.exprs[usize(e)].left = left
    p.exprs[usize(e)].right = right
    ret (e, ok)
}

fn parse_or(p: *Parser) -> (u32, err) {
    if p.depth > 200u32 { ret (NONE, TooComplex) }
    p.depth += 1u32
    var left = NONE
    let (first, first_error) = parse_and(p)
    if first_error != ok {
        p.depth -= 1u32
        ret (NONE, first_error)
    }
    left = first
    while peek_kind(p) == K_OR {
        p.at += 1usize
        let (right, right_error) = parse_and(p)
        if right_error != ok {
            p.depth -= 1u32
            ret (NONE, right_error)
        }
        let (joined, join_error) = binary(p, E_OR, left, right)
        if join_error != ok {
            p.depth -= 1u32
            ret (NONE, join_error)
        }
        left = joined
    }
    p.depth -= 1u32
    ret (left, ok)
}

fn parse_and(p: *Parser) -> (u32, err) {
    let (first, first_error) = parse_equality(p)
    if first_error != ok { ret (NONE, first_error) }
    var left = first
    while peek_kind(p) == K_AND {
        p.at += 1usize
        let (right, right_error) = parse_equality(p)
        if right_error != ok { ret (NONE, right_error) }
        let (joined, join_error) = binary(p, E_AND, left, right)
        if join_error != ok { ret (NONE, join_error) }
        left = joined
    }
    ret (left, ok)
}

fn parse_equality(p: *Parser) -> (u32, err) {
    let (first, first_error) = parse_relational(p)
    if first_error != ok { ret (NONE, first_error) }
    var left = first
    while peek_kind(p) == K_EQ || peek_kind(p) == K_NE {
        var kind = E_EQ
        if peek_kind(p) == K_NE { kind = E_NE }
        p.at += 1usize
        let (right, right_error) = parse_relational(p)
        if right_error != ok { ret (NONE, right_error) }
        let (joined, join_error) = binary(p, kind, left, right)
        if join_error != ok { ret (NONE, join_error) }
        left = joined
    }
    ret (left, ok)
}

fn parse_relational(p: *Parser) -> (u32, err) {
    let (first, first_error) = parse_additive(p)
    if first_error != ok { ret (NONE, first_error) }
    var left = first
    while peek_kind(p) == K_LT || peek_kind(p) == K_LE || peek_kind(p) == K_GT || peek_kind(p) == K_GE {
        var kind = E_LT
        if peek_kind(p) == K_LE { kind = E_LE } else if peek_kind(p) == K_GT { kind = E_GT } else if peek_kind(p) == K_GE { kind = E_GE }
        p.at += 1usize
        let (right, right_error) = parse_additive(p)
        if right_error != ok { ret (NONE, right_error) }
        let (joined, join_error) = binary(p, kind, left, right)
        if join_error != ok { ret (NONE, join_error) }
        left = joined
    }
    ret (left, ok)
}

fn parse_additive(p: *Parser) -> (u32, err) {
    let (first, first_error) = parse_multiplicative(p)
    if first_error != ok { ret (NONE, first_error) }
    var left = first
    while peek_kind(p) == K_PLUS || peek_kind(p) == K_MINUS {
        var kind = E_ADD
        if peek_kind(p) == K_MINUS { kind = E_SUB }
        p.at += 1usize
        let (right, right_error) = parse_multiplicative(p)
        if right_error != ok { ret (NONE, right_error) }
        let (joined, join_error) = binary(p, kind, left, right)
        if join_error != ok { ret (NONE, join_error) }
        left = joined
    }
    ret (left, ok)
}

fn is_multiply(p: *const Parser) -> bool {
    ret peek_kind(p) == K_DIV || peek_kind(p) == K_MOD || peek_kind(p) == K_MUL
}

fn parse_multiplicative(p: *Parser) -> (u32, err) {
    let (first, first_error) = parse_unary(p)
    if first_error != ok { ret (NONE, first_error) }
    var left = first
    while is_multiply(p) {
        var kind = E_MUL
        if peek_kind(p) == K_DIV { kind = E_DIV } else if peek_kind(p) == K_MOD { kind = E_MOD }
        p.at += 1usize
        let (right, right_error) = parse_unary(p)
        if right_error != ok { ret (NONE, right_error) }
        let (joined, join_error) = binary(p, kind, left, right)
        if join_error != ok { ret (NONE, join_error) }
        left = joined
    }
    ret (left, ok)
}

fn parse_unary(p: *Parser) -> (u32, err) {
    if peek_kind(p) == K_MINUS {
        p.at += 1usize
        let (inner, inner_error) = parse_unary(p)
        if inner_error != ok { ret (NONE, inner_error) }
        let (e, e_error) = new_expr(p, E_NEG)
        if e_error != ok { ret (NONE, e_error) }
        p.exprs[usize(e)].left = inner
        ret (e, ok)
    }
    let (union_expr, union_error) = parse_union(p)
    ret (union_expr, union_error)
}

fn parse_union(p: *Parser) -> (u32, err) {
    let (first, first_error) = parse_path(p)
    if first_error != ok { ret (NONE, first_error) }
    var left = first
    while peek_kind(p) == K_PIPE {
        p.at += 1usize
        let (right, right_error) = parse_path(p)
        if right_error != ok { ret (NONE, right_error) }
        let (joined, join_error) = binary(p, E_UNION, left, right)
        if join_error != ok { ret (NONE, join_error) }
        left = joined
    }
    ret (left, ok)
}

fn axis_named(name: str) -> (u8, bool) {
    if same(name, "child") { ret (A_CHILD, true) }
    if same(name, "descendant") { ret (A_DESCENDANT, true) }
    if same(name, "parent") { ret (A_PARENT, true) }
    if same(name, "ancestor") { ret (A_ANCESTOR, true) }
    if same(name, "following-sibling") { ret (A_FOLLOWING_SIBLING, true) }
    if same(name, "preceding-sibling") { ret (A_PRECEDING_SIBLING, true) }
    if same(name, "following") { ret (A_FOLLOWING, true) }
    if same(name, "preceding") { ret (A_PRECEDING, true) }
    if same(name, "attribute") { ret (A_ATTRIBUTE, true) }
    if same(name, "namespace") { ret (A_NAMESPACE, true) }
    if same(name, "self") { ret (A_SELF, true) }
    if same(name, "descendant-or-self") { ret (A_DESCENDANT_OR_SELF, true) }
    if same(name, "ancestor-or-self") { ret (A_ANCESTOR_OR_SELF, true) }
    ret (0u8, false)
}

fn is_node_type(name: str) -> bool { ret same(name, "node") || same(name, "text") || same(name, "comment") || same(name, "processing-instruction") }

fn parse_predicates(p: *Parser) -> ([]u32, err) {
    var count = 0usize
    var probe = p.at
    var depth = 0usize
    // count the predicate groups first so the list is sized exactly
    while probe < p.count && p.tokens[probe].kind == K_LBRACKET {
        depth = 0usize
        while probe < p.count {
            if p.tokens[probe].kind == K_LBRACKET { depth += 1usize }
            if p.tokens[probe].kind == K_RBRACKET {
                depth -= 1usize
                if depth == 0usize { break }
            }
            probe += 1usize
        }
        probe += 1usize
        count += 1usize
    }
    if count == 0usize { ret (zero, ok) }
    let (list, alloc_error) = mem.alloc[u32](p.a, count)
    if alloc_error != ok { ret (zero, alloc_error) }
    var i = 0usize
    while i < count {
        p.at += 1usize
        let (e, e_error) = parse_or(p)
        if e_error != ok { ret (zero, e_error) }
        if peek_kind(p) != K_RBRACKET { ret (zero, Invalid) }
        p.at += 1usize
        list[i] = e
        i += 1usize
    }
    ret (list, ok)
}

// One location step from the current token.
fn parse_step(p: *Parser) -> (Step, err) {
    var step = Step { axis: A_CHILD, test: T_NAME, prefix: "", local: "", preds: zero }
    let k = peek_kind(p)
    if k == K_DOT {
        p.at += 1usize
        step.axis = A_SELF
        step.test = T_NODE
        let (preds, preds_error) = parse_predicates(p)
        if preds_error != ok { ret (zero, preds_error) }
        step.preds = preds
        ret (step, ok)
    }
    if k == K_DOTDOT {
        p.at += 1usize
        step.axis = A_PARENT
        step.test = T_NODE
        let (preds, preds_error) = parse_predicates(p)
        if preds_error != ok { ret (zero, preds_error) }
        step.preds = preds
        ret (step, ok)
    }
    if k == K_AT {
        p.at += 1usize
        step.axis = A_ATTRIBUTE
    } else if k == K_NAME && p.tokens[p.at + 1usize].kind == K_COLONCOLON {
        let (axis, found) = axis_named(p.tokens[p.at].text)
        if !found { ret (zero, Invalid) }
        step.axis = axis
        p.at += 2usize
    }
    let t = p.tokens[p.at]
    if t.kind == K_STAR {
        step.test = T_ANY
        p.at += 1usize
    } else if t.kind == K_PREFIX_STAR {
        step.test = T_PREFIX_ANY
        step.prefix = t.text[..t.text.len - 2usize]
        p.at += 1usize
    } else if t.kind == K_NAME {
        if p.tokens[p.at + 1usize].kind == K_LPAREN && is_node_type(t.text) {
            if same(t.text, "node") { step.test = T_NODE } else if same(t.text, "text") { step.test = T_TEXT } else if same(t.text, "comment") { step.test = T_COMMENT } else { step.test = T_PI }
            p.at += 2usize
            if same(t.text, "processing-instruction") && peek_kind(p) == K_LITERAL {
                step.local = p.tokens[p.at].text
                p.at += 1usize
            }
            if peek_kind(p) != K_RPAREN { ret (zero, Invalid) }
            p.at += 1usize
        } else {
            let (colon, has_colon) = str.find(t.text, ":")
            if has_colon {
                step.prefix = t.text[..colon]
                step.local = t.text[colon + 1usize..]
            } else {
                step.local = t.text
            }
            p.at += 1usize
        }
    } else {
        ret (zero, Invalid)
    }
    let (preds, preds_error) = parse_predicates(p)
    if preds_error != ok { ret (zero, preds_error) }
    step.preds = preds
    ret (step, ok)
}

fn starts_step(k: u8) -> bool { ret k == K_DOT || k == K_DOTDOT || k == K_AT || k == K_NAME || k == K_STAR || k == K_PREFIX_STAR }

// The steps of a path from the current token: a step, then (`/` | `//`) step ... where a `//` stands for
// descendant-or-self::node() between. `required` says whether at least one step must be there.
fn parse_steps(p: *Parser, required: bool) -> ([]Step, err) {
    if !starts_step(peek_kind(p)) {
        if required { ret (zero, Invalid) }
        ret (zero, ok)
    }
    let (buffer, alloc_error) = mem.alloc[Step](p.a, p.count + 2usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var used = 0usize
    let (first, first_error) = parse_step(p)
    if first_error != ok { ret (zero, first_error) }
    buffer[used] = first
    used += 1usize
    while peek_kind(p) == K_SLASH || peek_kind(p) == K_SLASHSLASH {
        if peek_kind(p) == K_SLASHSLASH {
            buffer[used] = Step { axis: A_DESCENDANT_OR_SELF, test: T_NODE, prefix: "", local: "", preds: zero }
            used += 1usize
        }
        p.at += 1usize
        let (next, next_error) = parse_step(p)
        if next_error != ok { ret (zero, next_error) }
        buffer[used] = next
        used += 1usize
    }
    ret (buffer[..used], ok)
}

fn parse_primary(p: *Parser) -> (u32, err) {
    let t = p.tokens[p.at]
    if t.kind == K_LPAREN {
        p.at += 1usize
        let (inner, inner_error) = parse_or(p)
        if inner_error != ok { ret (NONE, inner_error) }
        if peek_kind(p) != K_RPAREN { ret (NONE, Invalid) }
        p.at += 1usize
        ret (inner, ok)
    }
    if t.kind == K_LITERAL {
        p.at += 1usize
        let (e, e_error) = new_expr(p, E_LITERAL)
        if e_error != ok { ret (NONE, e_error) }
        p.exprs[usize(e)].text = t.text
        ret (e, ok)
    }
    if t.kind == K_NUMBER {
        p.at += 1usize
        let (e, e_error) = new_expr(p, E_NUMBER)
        if e_error != ok { ret (NONE, e_error) }
        p.exprs[usize(e)].number = t.number
        ret (e, ok)
    }
    if t.kind == K_VAR {
        p.at += 1usize
        let (e, e_error) = new_expr(p, E_VAR)
        if e_error != ok { ret (NONE, e_error) }
        p.exprs[usize(e)].text = t.text
        ret (e, ok)
    }
    // a function call: NAME '('
    p.at += 2usize
    var argc = 0usize
    var probe = p.at
    var depth = 0usize
    if p.tokens[probe].kind != K_RPAREN {
        argc = 1usize
        while probe < p.count {
            let k = p.tokens[probe].kind
            if k == K_LPAREN || k == K_LBRACKET { depth += 1usize }
            if k == K_RPAREN || k == K_RBRACKET {
                if depth == 0usize { break }
                depth -= 1usize
            }
            if k == K_COMMA && depth == 0usize { argc += 1usize }
            probe += 1usize
        }
    }
    var args: []u32 = zero
    if argc > 0usize {
        let (list, alloc_error) = mem.alloc[u32](p.a, argc)
        if alloc_error != ok { ret (NONE, alloc_error) }
        args = list
        var i = 0usize
        while i < argc {
            let (arg, arg_error) = parse_or(p)
            if arg_error != ok { ret (NONE, arg_error) }
            args[i] = arg
            i += 1usize
            if i < argc {
                if peek_kind(p) != K_COMMA { ret (NONE, Invalid) }
                p.at += 1usize
            }
        }
    }
    if peek_kind(p) != K_RPAREN { ret (NONE, Invalid) }
    p.at += 1usize
    let (e, e_error) = new_expr(p, E_CALL)
    if e_error != ok { ret (NONE, e_error) }
    p.exprs[usize(e)].text = t.text
    p.exprs[usize(e)].args = args
    ret (e, ok)
}

fn is_primary_start(p: *const Parser) -> bool {
    let k = peek_kind(p)
    if k == K_LPAREN || k == K_LITERAL || k == K_NUMBER || k == K_VAR { ret true }
    ret k == K_NAME && p.tokens[p.at + 1usize].kind == K_LPAREN && !is_node_type(p.tokens[p.at].text)
}

fn parse_path(p: *Parser) -> (u32, err) {
    let k = peek_kind(p)
    if k == K_SLASH || k == K_SLASHSLASH {
        var absolute_steps: []Step = zero
        var descendant = false
        if k == K_SLASHSLASH { descendant = true }
        p.at += 1usize
        let (steps, steps_error) = parse_steps(p, descendant)
        if steps_error != ok { ret (NONE, steps_error) }
        absolute_steps = steps
        if descendant && absolute_steps.len == 0usize { ret (NONE, Invalid) }
        var all = absolute_steps
        if descendant {
            let (extended, alloc_error) = mem.alloc[Step](p.a, absolute_steps.len + 1usize)
            if alloc_error != ok { ret (NONE, alloc_error) }
            extended[0usize] = Step { axis: A_DESCENDANT_OR_SELF, test: T_NODE, prefix: "", local: "", preds: zero }
            var i = 0usize
            while i < absolute_steps.len {
                extended[i + 1usize] = absolute_steps[i]
                i += 1usize
            }
            all = extended
        }
        let (e, e_error) = new_expr(p, E_PATH)
        if e_error != ok { ret (NONE, e_error) }
        p.exprs[usize(e)].absolute = true
        p.exprs[usize(e)].steps = all
        ret (e, ok)
    }
    if is_primary_start(p) {
        let (primary, primary_error) = parse_primary(p)
        if primary_error != ok { ret (NONE, primary_error) }
        let (preds, preds_error) = parse_predicates(p)
        if preds_error != ok { ret (NONE, preds_error) }
        if preds.len == 0usize && peek_kind(p) != K_SLASH && peek_kind(p) != K_SLASHSLASH { ret (primary, ok) }
        // a filter expression, optionally continued with a relative path
        var rest: []Step = zero
        if peek_kind(p) == K_SLASH || peek_kind(p) == K_SLASHSLASH {
            var lead = false
            if peek_kind(p) == K_SLASHSLASH { lead = true }
            p.at += 1usize
            let (steps, steps_error) = parse_steps(p, true)
            if steps_error != ok { ret (NONE, steps_error) }
            if lead {
                let (extended, alloc_error) = mem.alloc[Step](p.a, steps.len + 1usize)
                if alloc_error != ok { ret (NONE, alloc_error) }
                extended[0usize] = Step { axis: A_DESCENDANT_OR_SELF, test: T_NODE, prefix: "", local: "", preds: zero }
                var i = 0usize
                while i < steps.len {
                    extended[i + 1usize] = steps[i]
                    i += 1usize
                }
                rest = extended
            } else {
                rest = steps
            }
        }
        let (e, e_error) = new_expr(p, E_PATH)
        if e_error != ok { ret (NONE, e_error) }
        p.exprs[usize(e)].left = primary
        p.exprs[usize(e)].preds = preds
        p.exprs[usize(e)].steps = rest
        ret (e, ok)
    }
    if !starts_step(k) { ret (NONE, Invalid) }
    let (steps, steps_error) = parse_steps(p, true)
    if steps_error != ok { ret (NONE, steps_error) }
    let (e, e_error) = new_expr(p, E_PATH)
    if e_error != ok { ret (NONE, e_error) }
    p.exprs[usize(e)].steps = steps
    ret (e, ok)
}

// Parse `text` into an arena. `bindings` map the prefixes the expression uses to namespace URIs.
fn compile(a: *mem.Arena, text: str, bindings: []const Binding) -> (Compiled, err) {
    let (tokens, count, token_error) = tokenize(a, text)
    if token_error != ok { ret (zero, token_error) }
    if count == 0usize { ret (zero, Invalid) }
    let (exprs, exprs_error) = mem.alloc[Expr](a, count * 4usize + 8usize)
    if exprs_error != ok { ret (zero, exprs_error) }
    var p = Parser { a: a, tokens: tokens, count: count, at: 0usize, exprs: exprs, used: 0usize, depth: 0u32 }
    let (root, root_error) = parse_or(&p)
    if root_error != ok { ret (zero, root_error) }
    if peek_kind(&p) != K_END { ret (zero, Invalid) }
    ret (Compiled { exprs: exprs, count: p.used, root: root, bindings: bindings }, ok)
}

// ---- values ----

fn nodeset_value(nodes: []XNode) -> Value { ret Value { kind: Kind.NodeSet, nodes: nodes, text: "", number: 0.0f64, flag: false } }
fn string_value(text: str) -> Value { ret Value { kind: Kind.String, nodes: zero, text: text, number: 0.0f64, flag: false } }
fn number_value(n: f64) -> Value { ret Value { kind: Kind.Number, nodes: zero, text: "", number: n, flag: false } }
fn boolean_value(b: bool) -> Value { ret Value { kind: Kind.Boolean, nodes: zero, text: "", number: 0.0f64, flag: b } }

fn infinity() -> f64 {
    var zero_value = 0.0f64
    ret 1.0f64 / zero_value
}

fn not_a_number() -> f64 {
    var zero_value = 0.0f64
    ret zero_value / zero_value
}

fn is_nan(x: f64) -> bool { ret x != x }

fn node_key(n: XNode) -> u64 { ret (u64(n.id) << 24u64) | u64(n.attribute) }

type Context = struct { node: XNode, position: usize, size: usize }

fn node_of(d: *const xml.Document, id: u32) -> xml.Node { ret d.nodes[usize(id)] }

fn split_name(name: str) -> (str, str) {
    let (at, found) = str.find(name, ":")
    if !found { ret ("", name) }
    ret (name[..at], name[at + 1usize..])
}

fn declares(attribute_name: str, prefix: str) -> bool {
    if prefix.len == 0usize { ret same(attribute_name, "xmlns") }
    ret attribute_name.len == prefix.len + 6usize && str.starts_with(attribute_name, "xmlns:") && same(attribute_name[6usize..], prefix)
}

// The namespace bound to `prefix` at element `id` through the document's xmlns attributes.
fn resolve_prefix(d: *const xml.Document, id: u32, prefix: str) -> (str, bool) {
    if same(prefix, "xml") { ret ("http://www.w3.org/XML/1998/namespace", true) }
    var at = id
    while at != NONE {
        let n = node_of(d, at)
        if n.kind == .Element {
            var i = 0usize
            while i < n.attributes.len {
                if declares(n.attributes[i].name, prefix) { ret (n.attributes[i].value, true) }
                i += 1usize
            }
        }
        at = n.parent
    }
    if prefix.len == 0usize { ret ("", true) }
    ret ("", false)
}

fn is_xmlns_name(name: str) -> bool { ret same(name, "xmlns") || str.starts_with(name, "xmlns:") }

// The qualified name of a node ("" for text, comment, document).
fn qname_of(d: *const xml.Document, n: XNode) -> str {
    let node = node_of(d, n.id)
    if n.attribute != 0u32 { ret node.attributes[usize(n.attribute) - 1usize].name }
    if node.kind == .Element || node.kind == .Processing { ret node.name }
    ret ""
}

// (namespace URI, local name) of an element or attribute node; a processing instruction has only a name.
fn expanded_name(d: *const xml.Document, n: XNode) -> (str, str) {
    let node = node_of(d, n.id)
    if n.attribute != 0u32 {
        let name = node.attributes[usize(n.attribute) - 1usize].name
        let (prefix, local) = split_name(name)
        if prefix.len == 0usize { ret ("", local) }
        let (uri, _) = resolve_prefix(d, n.id, prefix)
        ret (uri, local)
    }
    if node.kind == .Element {
        let (prefix, local) = split_name(node.name)
        let (uri, _) = resolve_prefix(d, n.id, prefix)
        ret (uri, local)
    }
    if node.kind == .Processing { ret ("", node.name) }
    ret ("", "")
}

fn subtree_end(d: *const xml.Document, id: u32) -> u32 {
    var at = id
    while node_of(d, at).last_child != NONE { at = node_of(d, at).last_child }
    ret at
}

// The string-value of a node: an element's or the document's descendant text, otherwise its own value.
fn string_of(a: *mem.Arena, d: *const xml.Document, n: XNode) -> (str, err) {
    let node = node_of(d, n.id)
    if n.attribute != 0u32 { ret (node.attributes[usize(n.attribute) - 1usize].value, ok) }
    if node.kind == .Text || node.kind == .Comment || node.kind == .Processing { ret (node.value, ok) }
    let last = subtree_end(d, n.id)
    var total = 0usize
    var k = n.id + 1u32
    var texts = 0usize
    var only = 0u32
    while k <= last {
        let t = node_of(d, k)
        if t.kind == .Text {
            total += t.value.len
            texts += 1usize
            only = k
        }
        k += 1u32
    }
    if texts == 0usize { ret ("", ok) }
    if texts == 1usize { ret (node_of(d, only).value, ok) }
    let (buffer, alloc_error) = mem.alloc[u8](a, total)
    if alloc_error != ok { ret ("", alloc_error) }
    var used = 0usize
    k = n.id + 1u32
    while k <= last {
        let t = node_of(d, k)
        if t.kind == .Text {
            var i = 0usize
            while i < t.value.len {
                buffer[used] = t.value[i]
                used += 1usize
                i += 1usize
            }
        }
        k += 1u32
    }
    ret (buffer[..used], ok)
}

// ---- node lists ----

type NodeList = struct { items: []XNode, count: usize }

fn push_node(a: *mem.Arena, list: *NodeList, n: XNode) -> err {
    if list.count == list.items.len {
        var capacity = list.items.len * 2usize
        if capacity < 16usize { capacity = 16usize }
        let (grown, alloc_error) = mem.alloc[XNode](a, capacity)
        if alloc_error != ok { ret alloc_error }
        var i = 0usize
        while i < list.count {
            grown[i] = list.items[i]
            i += 1usize
        }
        list.items = grown
    }
    list.items[list.count] = n
    list.count += 1usize
    ret ok
}

// Document order with duplicates removed.
fn sort_unique(a: *mem.Arena, nodes: []XNode) -> ([]XNode, err) {
    let n = nodes.len
    if n < 2usize { ret (nodes, ok) }
    var sorted = true
    var i = 1usize
    while i < n {
        if node_key(nodes[i - 1usize]) >= node_key(nodes[i]) { sorted = false }
        i += 1usize
    }
    if sorted { ret (nodes, ok) }
    let (buffer, alloc_error) = mem.alloc[XNode](a, n)
    if alloc_error != ok { ret (zero, alloc_error) }
    i = 0usize
    while i < n {
        buffer[i] = nodes[i]
        i += 1usize
    }
    let (scratch, scratch_error) = mem.alloc[XNode](a, n)
    if scratch_error != ok { ret (zero, scratch_error) }
    var width = 1usize
    while width < n {
        var start = 0usize
        while start < n {
            var mid = start + width
            if mid > n { mid = n }
            var finish = start + 2usize * width
            if finish > n { finish = n }
            var left = start
            var right = mid
            var out = start
            while left < mid && right < finish {
                if node_key(buffer[left]) <= node_key(buffer[right]) {
                    scratch[out] = buffer[left]
                    left += 1usize
                } else {
                    scratch[out] = buffer[right]
                    right += 1usize
                }
                out += 1usize
            }
            while left < mid {
                scratch[out] = buffer[left]
                left += 1usize
                out += 1usize
            }
            while right < finish {
                scratch[out] = buffer[right]
                right += 1usize
                out += 1usize
            }
            start += 2usize * width
        }
        i = 0usize
        while i < n {
            buffer[i] = scratch[i]
            i += 1usize
        }
        width *= 2usize
    }
    var used = 0usize
    i = 0usize
    while i < n {
        if used == 0usize || node_key(buffer[used - 1usize]) != node_key(buffer[i]) {
            buffer[used] = buffer[i]
            used += 1usize
        }
        i += 1usize
    }
    ret (buffer[..used], ok)
}

// ---- axes ----

fn is_reverse(axis: u8) -> bool { ret axis == A_PARENT || axis == A_ANCESTOR || axis == A_ANCESTOR_OR_SELF || axis == A_PRECEDING || axis == A_PRECEDING_SIBLING }

// The nodes along `axis` from `n`, in the axis's proximity order (nearest first for reverse axes).
fn axis_nodes(a: *mem.Arena, d: *const xml.Document, n: XNode, axis: u8, list: *NodeList) -> err {
    let node = node_of(d, n.id)
    var attribute_context = n.attribute != 0u32
    if axis == A_SELF { ret push_node(a, list, n) }
    if axis == A_CHILD {
        if attribute_context { ret ok }
        var at = node.first_child
        while at != NONE {
            try push_node(a, list, XNode { id: at, attribute: 0u32 })
            at = node_of(d, at).next_sibling
        }
        ret ok
    }
    if axis == A_ATTRIBUTE {
        if attribute_context || node.kind != .Element { ret ok }
        var i = 0usize
        while i < node.attributes.len {
            if !is_xmlns_name(node.attributes[i].name) { try push_node(a, list, XNode { id: n.id, attribute: u32(i) + 1u32 }) }
            i += 1usize
        }
        ret ok
    }
    if axis == A_DESCENDANT || axis == A_DESCENDANT_OR_SELF {
        if axis == A_DESCENDANT_OR_SELF { try push_node(a, list, n) }
        if attribute_context { ret ok }
        let last = subtree_end(d, n.id)
        var k = n.id + 1u32
        while k <= last {
            try push_node(a, list, XNode { id: k, attribute: 0u32 })
            k += 1u32
        }
        ret ok
    }
    if axis == A_PARENT {
        if attribute_context { ret push_node(a, list, XNode { id: n.id, attribute: 0u32 }) }
        if node.parent != NONE { try push_node(a, list, XNode { id: node.parent, attribute: 0u32 }) }
        ret ok
    }
    if axis == A_ANCESTOR || axis == A_ANCESTOR_OR_SELF {
        if axis == A_ANCESTOR_OR_SELF { try push_node(a, list, n) }
        var at = n.id
        if attribute_context { try push_node(a, list, XNode { id: n.id, attribute: 0u32 }) }
        at = node.parent
        while at != NONE {
            try push_node(a, list, XNode { id: at, attribute: 0u32 })
            at = node_of(d, at).parent
        }
        ret ok
    }
    if axis == A_FOLLOWING_SIBLING {
        if attribute_context { ret ok }
        var at = node.next_sibling
        while at != NONE {
            try push_node(a, list, XNode { id: at, attribute: 0u32 })
            at = node_of(d, at).next_sibling
        }
        ret ok
    }
    if axis == A_PRECEDING_SIBLING {
        if attribute_context || node.parent == NONE { ret ok }
        // siblings before `n`, nearest first
        var before = 0usize
        var at = node_of(d, node.parent).first_child
        while at != NONE && at != n.id {
            before += 1usize
            at = node_of(d, at).next_sibling
        }
        if before == 0usize { ret ok }
        let (ids, alloc_error) = mem.alloc[u32](a, before)
        if alloc_error != ok { ret alloc_error }
        var k = 0usize
        at = node_of(d, node.parent).first_child
        while at != NONE && at != n.id {
            ids[k] = at
            k += 1usize
            at = node_of(d, at).next_sibling
        }
        while k > 0usize {
            k -= 1usize
            try push_node(a, list, XNode { id: ids[k], attribute: 0u32 })
        }
        ret ok
    }
    if axis == A_FOLLOWING {
        var start = subtree_end(d, n.id) + 1u32
        if attribute_context { start = n.id + 1u32 }
        var k = start
        while usize(k) < d.nodes.len {
            try push_node(a, list, XNode { id: k, attribute: 0u32 })
            k += 1u32
        }
        ret ok
    }
    if axis == A_PRECEDING {
        // everything before the node in document order that is not an ancestor
        let (marks, alloc_error) = mem.alloc[bool](a, d.nodes.len + 1usize)
        if alloc_error != ok { ret alloc_error }
        var i = 0usize
        while i < d.nodes.len {
            marks[i] = false
            i += 1usize
        }
        var up = node.parent
        while up != NONE {
            marks[usize(up)] = true
            up = node_of(d, up).parent
        }
        var k = n.id
        while k > 1u32 {
            k -= 1u32
            if !marks[usize(k)] { try push_node(a, list, XNode { id: k, attribute: 0u32 }) }
        }
        ret ok
    }
    ret ok
}

// ---- node tests ----

fn lookup_binding(c: *const Compiled, prefix: str) -> (str, bool) {
    var i = 0usize
    while i < c.bindings.len {
        if same(c.bindings[i].prefix, prefix) { ret (c.bindings[i].uri, true) }
        i += 1usize
    }
    ret ("", false)
}

fn matches_test(d: *const xml.Document, c: *const Compiled, step: Step, n: XNode) -> bool {
    let node = node_of(d, n.id)
    let is_attribute = n.attribute != 0u32
    if step.test == T_NODE { ret true }
    if step.test == T_TEXT { ret !is_attribute && node.kind == .Text }
    if step.test == T_COMMENT { ret !is_attribute && node.kind == .Comment }
    if step.test == T_PI {
        if is_attribute || node.kind != .Processing { ret false }
        ret step.local.len == 0usize || same(node.name, step.local)
    }
    var principal_ok = false
    if step.axis == A_ATTRIBUTE { principal_ok = is_attribute } else { principal_ok = !is_attribute && node.kind == .Element }
    if !principal_ok { ret false }
    if step.test == T_ANY { ret true }
    let (uri, local) = expanded_name(d, n)
    if step.test == T_PREFIX_ANY {
        let (want, bound) = lookup_binding(c, step.prefix)
        ret bound && same(uri, want)
    }
    if !same(local, step.local) { ret false }
    if step.prefix.len == 0usize { ret uri.len == 0usize }
    let (want, bound) = lookup_binding(c, step.prefix)
    ret bound && same(uri, want)
}

// ---- conversions ----

fn char_count(text: str) -> usize {
    var count = 0usize
    var at = 0usize
    while at < text.len {
        let (dec, decode_error) = utf8.decode(text, at)
        if decode_error != ok { at += 1usize } else { at += usize(dec.width) }
        count += 1usize
    }
    ret count
}

// The byte offset of the `k`-th character (0-based), or the length when there are fewer.
fn char_offset(text: str, k: usize) -> usize {
    var count = 0usize
    var at = 0usize
    while at < text.len && count < k {
        let (dec, decode_error) = utf8.decode(text, at)
        if decode_error != ok { at += 1usize } else { at += usize(dec.width) }
        count += 1usize
    }
    ret at
}

// A number as XPath writes it: no exponent, no trailing zeros, NaN, Infinity, -Infinity, and 0 for -0.
fn number_text(a: *mem.Arena, x: f64) -> (str, err) {
    if is_nan(x) { ret ("NaN", ok) }
    if x == infinity() { ret ("Infinity", ok) }
    if x == -infinity() { ret ("-Infinity", ok) }
    if x == 0.0f64 { ret ("0", ok) }
    let (builder, builder_error) = str.builder(a, 48usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = builder
    try str.push_f64(&b, x)
    let raw = str.done(&b)
    var e_at = raw.len
    var i = 0usize
    while i < raw.len {
        if raw[i] == 101u8 || raw[i] == 69u8 {
            e_at = i
            break
        }
        i += 1usize
    }
    if e_at == raw.len { ret (strip_integer_fraction(raw), ok) }
    // scientific: mantissa digits and a decimal exponent
    var mantissa = raw[..e_at]
    var negative = false
    if mantissa.len > 0usize && mantissa[0usize] == 45u8 {
        negative = true
        mantissa = mantissa[1usize..]
    }
    var exponent = 0i64
    var neg_exp = false
    var j = e_at + 1usize
    if j < raw.len && (raw[j] == 43u8 || raw[j] == 45u8) {
        neg_exp = raw[j] == 45u8
        j += 1usize
    }
    while j < raw.len {
        exponent = exponent * 10i64 + i64(raw[j] - 48u8)
        j += 1usize
    }
    if neg_exp { exponent = 0i64 - exponent }
    var digits_before = mantissa.len
    var dot = 0usize
    var has_dot = false
    var k = 0usize
    while k < mantissa.len {
        if mantissa[k] == 46u8 {
            dot = k
            has_dot = true
            break
        }
        k += 1usize
    }
    var digits: str = mantissa
    if has_dot {
        let (joined, join_error) = str.concat(a, mantissa[..dot], mantissa[dot + 1usize..])
        if join_error != ok { ret ("", join_error) }
        digits = joined
        digits_before = dot
    }
    // value = 0.DIGITS * 10^(digits_before + exponent)
    let point = i64(digits_before) + exponent
    let (out, out_error) = str.builder(a, digits.len + 40usize)
    if out_error != ok { ret ("", out_error) }
    var ob = out
    if negative { try str.push(&ob, "-") }
    if point <= 0i64 {
        try str.push(&ob, "0.")
        var z = 0i64
        while z < 0i64 - point {
            try str.push(&ob, "0")
            z += 1i64
        }
        try str.push(&ob, digits)
    } else if usize(point) >= digits.len {
        try str.push(&ob, digits)
        var z = digits.len
        while z < usize(point) {
            try str.push(&ob, "0")
            z += 1usize
        }
    } else {
        try str.push(&ob, digits[..usize(point)])
        try str.push(&ob, ".")
        try str.push(&ob, digits[usize(point)..])
    }
    ret (strip_integer_fraction(str.done(&ob)), ok)
}

// "12.0" is not how XPath writes 12: drop a fraction that is all zeros.
fn strip_integer_fraction(text: str) -> str {
    let (dot, has_dot) = str.find(text, ".")
    if !has_dot { ret text }
    var end = text.len
    while end > dot + 1usize && text[end - 1usize] == 48u8 { end -= 1usize }
    if end == dot + 1usize { ret text[..dot] }
    ret text[..end]
}

// XPath's string to number: optional blanks, an optional minus, digits with an optional fraction, blanks.
fn text_number(text: str) -> f64 {
    var start = 0usize
    var end = text.len
    while start < end && is_space(text[start]) { start += 1usize }
    while end > start && is_space(text[end - 1usize]) { end -= 1usize }
    let t = text[start..end]
    if t.len == 0usize { ret not_a_number() }
    var i = 0usize
    if t[0usize] == 45u8 { i = 1usize }
    var digits = 0usize
    var dots = 0usize
    var j = i
    while j < t.len {
        if is_digit(t[j]) {
            digits += 1usize
        } else if t[j] == 46u8 {
            dots += 1usize
        } else {
            ret not_a_number()
        }
        j += 1usize
    }
    if digits == 0usize || dots > 1usize { ret not_a_number() }
    var body = t
    var sign = 1.0f64
    if i == 1usize {
        sign = -1.0f64
        body = t[1usize..]
    }
    // parse_f64 wants digits on both sides of a point
    var arena_buffer: [512]u8 = zero
    if body.len + 2usize > 512usize { ret not_a_number() }
    var used = 0usize
    if body[0usize] == 46u8 {
        arena_buffer[0usize] = 48u8
        used = 1usize
    }
    var m = 0usize
    while m < body.len {
        arena_buffer[used] = body[m]
        used += 1usize
        m += 1usize
    }
    if body[body.len - 1usize] == 46u8 { used -= 1usize }
    let (value, value_error) = str.parse_f64(arena_buffer[..used])
    if value_error != ok { ret not_a_number() }
    ret sign * value
}

fn to_string(a: *mem.Arena, d: *const xml.Document, v: Value) -> (str, err) {
    if v.kind == Kind.String { ret (v.text, ok) }
    if v.kind == Kind.Boolean {
        if v.flag { ret ("true", ok) }
        ret ("false", ok)
    }
    if v.kind == Kind.Number {
        let (text, text_error) = number_text(a, v.number)
        ret (text, text_error)
    }
    if v.nodes.len == 0usize { ret ("", ok) }
    let (text, text_error) = string_of(a, d, v.nodes[0usize])
    ret (text, text_error)
}

fn to_number(a: *mem.Arena, d: *const xml.Document, v: Value) -> (f64, err) {
    if v.kind == Kind.Number { ret (v.number, ok) }
    if v.kind == Kind.Boolean {
        if v.flag { ret (1.0f64, ok) }
        ret (0.0f64, ok)
    }
    let (text, text_error) = to_string(a, d, v)
    if text_error != ok { ret (0.0f64, text_error) }
    ret (text_number(text), ok)
}

fn to_boolean(v: Value) -> bool {
    if v.kind == Kind.Boolean { ret v.flag }
    if v.kind == Kind.Number { ret v.number != 0.0f64 && !is_nan(v.number) }
    if v.kind == Kind.String { ret v.text.len > 0usize }
    ret v.nodes.len > 0usize
}

// ---- comparisons ----

fn compare_numbers(op: u8, x: f64, y: f64) -> bool {
    if op == E_EQ { ret x == y }
    if op == E_NE { ret x != y }
    if op == E_LT { ret x < y }
    if op == E_LE { ret x <= y }
    if op == E_GT { ret x > y }
    ret x >= y
}

fn compare_strings(op: u8, x: str, y: str) -> bool {
    if op == E_EQ { ret same(x, y) }
    ret !same(x, y)
}

// The comparison of two values by XPath 1.0 section 3.4, including the existential rules for node-sets.
fn compare(a: *mem.Arena, d: *const xml.Document, op: u8, x: Value, y: Value) -> (bool, err) {
    let relational = op == E_LT || op == E_LE || op == E_GT || op == E_GE
    if x.kind == Kind.NodeSet && y.kind == Kind.NodeSet {
        var i = 0usize
        while i < x.nodes.len {
            let (xs, xe) = string_of(a, d, x.nodes[i])
            if xe != ok { ret (false, xe) }
            var j = 0usize
            while j < y.nodes.len {
                let (ys, ye) = string_of(a, d, y.nodes[j])
                if ye != ok { ret (false, ye) }
                if relational {
                    if compare_numbers(op, text_number(xs), text_number(ys)) { ret (true, ok) }
                } else if compare_strings(op, xs, ys) {
                    ret (true, ok)
                }
                j += 1usize
            }
            i += 1usize
        }
        ret (false, ok)
    }
    if x.kind == Kind.NodeSet || y.kind == Kind.NodeSet {
        var set = x
        var other = y
        var flipped = false
        if y.kind == Kind.NodeSet {
            set = y
            other = x
            flipped = true
        }
        if other.kind == Kind.Boolean {
            let left = set.nodes.len > 0usize
            if relational {
                var set_number = 0.0f64
                if left { set_number = 1.0f64 }
                var other_number = 0.0f64
                if other.flag { other_number = 1.0f64 }
                if flipped { ret (compare_numbers(op, other_number, set_number), ok) }
                ret (compare_numbers(op, set_number, other_number), ok)
            }
            if flipped { ret (compare_bools(op, other.flag, left), ok) }
            ret (compare_bools(op, left, other.flag), ok)
        }
        var i = 0usize
        while i < set.nodes.len {
            let (text, text_error) = string_of(a, d, set.nodes[i])
            if text_error != ok { ret (false, text_error) }
            var result = false
            if other.kind == Kind.Number {
                if flipped { result = compare_numbers(op, other.number, text_number(text)) } else { result = compare_numbers(op, text_number(text), other.number) }
            } else if relational {
                let (on, on_error) = to_number(a, d, other)
                if on_error != ok { ret (false, on_error) }
                if flipped { result = compare_numbers(op, on, text_number(text)) } else { result = compare_numbers(op, text_number(text), on) }
            } else {
                result = compare_strings(op, text, other.text)
            }
            if result { ret (true, ok) }
            i += 1usize
        }
        ret (false, ok)
    }
    if relational {
        let (xn, xe) = to_number(a, d, x)
        if xe != ok { ret (false, xe) }
        let (yn, ye) = to_number(a, d, y)
        if ye != ok { ret (false, ye) }
        ret (compare_numbers(op, xn, yn), ok)
    }
    if x.kind == Kind.Boolean || y.kind == Kind.Boolean { ret (compare_bools(op, to_boolean(x), to_boolean(y)), ok) }
    if x.kind == Kind.Number || y.kind == Kind.Number {
        let (xn, xe) = to_number(a, d, x)
        if xe != ok { ret (false, xe) }
        let (yn, ye) = to_number(a, d, y)
        if ye != ok { ret (false, ye) }
        ret (compare_numbers(op, xn, yn), ok)
    }
    ret (compare_strings(op, x.text, y.text), ok)
}

fn compare_bools(op: u8, x: bool, y: bool) -> bool {
    if op == E_EQ { ret x == y }
    ret x != y
}

// ---- evaluation ----

type Env = struct {
    a: *mem.Arena, d: *const xml.Document, c: *const Compiled, vars: *const Variables, ext: *const Extensions, depth: u32,
}

fn lookup_variable(vars: *const Variables, name: str) -> (Value, bool) {
    var i = vars.count
    while i > 0usize {
        i -= 1usize
        if same(vars.items[i].name, name) { ret (vars.items[i].value, true) }
    }
    ret (zero, false)
}

fn eval(env: *Env, id: u32, ctx: Context) -> (Value, err) {
    if env.depth > 400u32 { ret (zero, TooComplex) }
    env.depth += 1u32
    let (value, value_error) = eval_inner(env, id, ctx)
    env.depth -= 1u32
    ret (value, value_error)
}

fn apply_predicates(env: *Env, preds: []const u32, list: []XNode) -> ([]XNode, err) {
    var current = list
    var p = 0usize
    while p < preds.len {
        let (kept, kept_error) = mem.alloc[XNode](env.a, current.len)
        if kept_error != ok { ret (zero, kept_error) }
        var used = 0usize
        var j = 0usize
        while j < current.len {
            let (v, v_error) = eval(env, preds[p], Context { node: current[j], position: j + 1usize, size: current.len })
            if v_error != ok { ret (zero, v_error) }
            var keep = false
            if v.kind == Kind.Number { keep = v.number == f64(j + 1usize) } else { keep = to_boolean(v) }
            if keep {
                kept[used] = current[j]
                used += 1usize
            }
            j += 1usize
        }
        current = kept[..used]
        p += 1usize
    }
    ret (current, ok)
}

fn eval_path(env: *Env, e: Expr, ctx: Context) -> (Value, err) {
    var current: []XNode = zero
    if e.absolute {
        let (one, alloc_error) = mem.alloc[XNode](env.a, 1usize)
        if alloc_error != ok { ret (zero, alloc_error) }
        one[0usize] = XNode { id: 0u32, attribute: 0u32 }
        current = one
    } else if e.left != NONE {
        let (primary, primary_error) = eval(env, e.left, ctx)
        if primary_error != ok { ret (zero, primary_error) }
        if e.preds.len == 0usize && e.steps.len == 0usize { ret (primary, ok) }
        if primary.kind != Kind.NodeSet { ret (zero, TypeMismatch) }
        let (sorted, sort_error) = sort_unique(env.a, primary.nodes)
        if sort_error != ok { ret (zero, sort_error) }
        let (filtered, filter_error) = apply_predicates(env, e.preds, sorted)
        if filter_error != ok { ret (zero, filter_error) }
        current = filtered
    } else {
        let (one, alloc_error) = mem.alloc[XNode](env.a, 1usize)
        if alloc_error != ok { ret (zero, alloc_error) }
        one[0usize] = ctx.node
        current = one
    }
    var s = 0usize
    while s < e.steps.len {
        let step = e.steps[s]
        var gathered = NodeList { items: zero, count: 0usize }
        var i = 0usize
        while i < current.len {
            var axis_list = NodeList { items: zero, count: 0usize }
            let axis_error = axis_nodes(env.a, env.d, current[i], step.axis, &axis_list)
            if axis_error != ok { ret (zero, axis_error) }
            // node test, keeping the axis order for the predicates
            let (tested, tested_error) = mem.alloc[XNode](env.a, axis_list.count + 1usize)
            if tested_error != ok { ret (zero, tested_error) }
            var kept = 0usize
            var k = 0usize
            while k < axis_list.count {
                if matches_test(env.d, env.c, step, axis_list.items[k]) {
                    tested[kept] = axis_list.items[k]
                    kept += 1usize
                }
                k += 1usize
            }
            let (filtered, filter_error) = apply_predicates(env, step.preds, tested[..kept])
            if filter_error != ok { ret (zero, filter_error) }
            k = 0usize
            while k < filtered.len {
                let push_error = push_node(env.a, &gathered, filtered[k])
                if push_error != ok { ret (zero, push_error) }
                k += 1usize
            }
            i += 1usize
        }
        let (sorted, sort_error) = sort_unique(env.a, gathered.items[..gathered.count])
        if sort_error != ok { ret (zero, sort_error) }
        current = sorted
        s += 1usize
    }
    let (final_nodes, final_error) = sort_unique(env.a, current)
    if final_error != ok { ret (zero, final_error) }
    ret (nodeset_value(final_nodes), ok)
}

fn eval_inner(env: *Env, id: u32, ctx: Context) -> (Value, err) {
    let e = env.c.exprs[usize(id)]
    if e.kind == E_NUMBER { ret (number_value(e.number), ok) }
    if e.kind == E_LITERAL { ret (string_value(e.text), ok) }
    if e.kind == E_VAR {
        let (v, found) = lookup_variable(env.vars, e.text)
        if !found { ret (zero, UnknownVariable) }
        ret (v, ok)
    }
    if e.kind == E_PATH {
        let (path_value, path_error) = eval_path(env, e, ctx)
        ret (path_value, path_error)
    }
    if e.kind == E_OR {
        let (left, left_error) = eval(env, e.left, ctx)
        if left_error != ok { ret (zero, left_error) }
        if to_boolean(left) { ret (boolean_value(true), ok) }
        let (right, right_error) = eval(env, e.right, ctx)
        if right_error != ok { ret (zero, right_error) }
        ret (boolean_value(to_boolean(right)), ok)
    }
    if e.kind == E_AND {
        let (left, left_error) = eval(env, e.left, ctx)
        if left_error != ok { ret (zero, left_error) }
        if !to_boolean(left) { ret (boolean_value(false), ok) }
        let (right, right_error) = eval(env, e.right, ctx)
        if right_error != ok { ret (zero, right_error) }
        ret (boolean_value(to_boolean(right)), ok)
    }
    if e.kind == E_NEG {
        let (inner, inner_error) = eval(env, e.left, ctx)
        if inner_error != ok { ret (zero, inner_error) }
        let (n, n_error) = to_number(env.a, env.d, inner)
        if n_error != ok { ret (zero, n_error) }
        ret (number_value(-n), ok)
    }
    if e.kind == E_UNION {
        let (left, left_error) = eval(env, e.left, ctx)
        if left_error != ok { ret (zero, left_error) }
        let (right, right_error) = eval(env, e.right, ctx)
        if right_error != ok { ret (zero, right_error) }
        if left.kind != Kind.NodeSet || right.kind != Kind.NodeSet { ret (zero, TypeMismatch) }
        let (both, alloc_error) = mem.alloc[XNode](env.a, left.nodes.len + right.nodes.len)
        if alloc_error != ok { ret (zero, alloc_error) }
        var i = 0usize
        while i < left.nodes.len {
            both[i] = left.nodes[i]
            i += 1usize
        }
        var j = 0usize
        while j < right.nodes.len {
            both[left.nodes.len + j] = right.nodes[j]
            j += 1usize
        }
        let (merged, merge_error) = sort_unique(env.a, both)
        if merge_error != ok { ret (zero, merge_error) }
        ret (nodeset_value(merged), ok)
    }
    if e.kind == E_CALL {
        let (result, call_error) = call_function(env, e, ctx)
        ret (result, call_error)
    }
    // binary comparison and arithmetic
    let (left, left_error) = eval(env, e.left, ctx)
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = eval(env, e.right, ctx)
    if right_error != ok { ret (zero, right_error) }
    if e.kind == E_EQ || e.kind == E_NE || e.kind == E_LT || e.kind == E_LE || e.kind == E_GT || e.kind == E_GE {
        let (answer, answer_error) = compare(env.a, env.d, e.kind, left, right)
        if answer_error != ok { ret (zero, answer_error) }
        ret (boolean_value(answer), ok)
    }
    let (x, x_error) = to_number(env.a, env.d, left)
    if x_error != ok { ret (zero, x_error) }
    let (y, y_error) = to_number(env.a, env.d, right)
    if y_error != ok { ret (zero, y_error) }
    if e.kind == E_ADD { ret (number_value(x + y), ok) }
    if e.kind == E_SUB { ret (number_value(x - y), ok) }
    if e.kind == E_MUL { ret (number_value(x * y), ok) }
    if e.kind == E_DIV { ret (number_value(x / y), ok) }
    // mod: the remainder keeps the dividend's sign (fmod)
    ret (number_value(fmod(x, y)), ok)
}

// The remainder of x / y with the dividend's sign, exact: subtract y * 2^k from the dividend, largest first.
fn fmod(x: f64, y: f64) -> f64 {
    if is_nan(x) || is_nan(y) || y == 0.0f64 || x == infinity() || x == -infinity() { ret not_a_number() }
    if y == infinity() || y == -infinity() { ret x }
    if x == 0.0f64 { ret x }
    var ay = y
    if ay < 0.0f64 { ay = -ay }
    var r = x
    if r < 0.0f64 { r = -r }
    while r >= ay {
        var t = ay
        while t * 2.0f64 <= r && t * 2.0f64 != infinity() { t = t * 2.0f64 }
        r = r - t
    }
    if x < 0.0f64 { ret -r }
    ret r
}

fn arg_value(env: *Env, e: Expr, k: usize, ctx: Context) -> (Value, err) {
    let (v, v_error) = eval(env, e.args[k], ctx)
    ret (v, v_error)
}

fn arg_string(env: *Env, e: Expr, k: usize, ctx: Context) -> (str, err) {
    let (v, v_error) = eval(env, e.args[k], ctx)
    if v_error != ok { ret ("", v_error) }
    let (text, text_error) = to_string(env.a, env.d, v)
    ret (text, text_error)
}

fn arg_number(env: *Env, e: Expr, k: usize, ctx: Context) -> (f64, err) {
    let (v, v_error) = eval(env, e.args[k], ctx)
    if v_error != ok { ret (0.0f64, v_error) }
    let (n, n_error) = to_number(env.a, env.d, v)
    ret (n, n_error)
}

fn xpath_round(x: f64) -> f64 {
    if is_nan(x) || x == infinity() || x == -infinity() { ret x }
    if x >= 4503599627370496.0f64 || x <= -4503599627370496.0f64 { ret x }
    if x < 0.0f64 && x >= -0.5f64 { ret -0.0f64 }
    ret math.floor[f64](x + 0.5f64)
}

fn context_nodeset(ctx: Context, a: *mem.Arena) -> (Value, err) {
    let (one, alloc_error) = mem.alloc[XNode](a, 1usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    one[0usize] = ctx.node
    ret (nodeset_value(one), ok)
}

// The first node (document order) of a node-set argument, or of the context when the argument is omitted.
fn first_node(env: *Env, e: Expr, ctx: Context) -> (XNode, bool, err) {
    if e.args.len == 0usize { ret (ctx.node, true, ok) }
    let (v, v_error) = eval(env, e.args[0usize], ctx)
    if v_error != ok { ret (zero, false, v_error) }
    if v.kind != Kind.NodeSet { ret (zero, false, TypeMismatch) }
    if v.nodes.len == 0usize { ret (zero, false, ok) }
    ret (v.nodes[0usize], true, ok)
}

fn call_function(env: *Env, e: Expr, ctx: Context) -> (Value, err) {
    let name = e.text
    let n = e.args.len
    if same(name, "last") {
        if n != 0usize { ret (zero, WrongArity) }
        ret (number_value(f64(ctx.size)), ok)
    }
    if same(name, "position") {
        if n != 0usize { ret (zero, WrongArity) }
        ret (number_value(f64(ctx.position)), ok)
    }
    if same(name, "count") {
        if n != 1usize { ret (zero, WrongArity) }
        let (v, v_error) = arg_value(env, e, 0usize, ctx)
        if v_error != ok { ret (zero, v_error) }
        if v.kind != Kind.NodeSet { ret (zero, TypeMismatch) }
        ret (number_value(f64(v.nodes.len)), ok)
    }
    if same(name, "id") {
        if n != 1usize { ret (zero, WrongArity) }
        ret (nodeset_value(zero), ok)
    }
    if same(name, "local-name") || same(name, "namespace-uri") || same(name, "name") {
        if n > 1usize { ret (zero, WrongArity) }
        let (chosen, has_chosen, chosen_error) = first_node(env, e, ctx)
        if chosen_error != ok { ret (zero, chosen_error) }
        if !has_chosen { ret (string_value(""), ok) }
        let (uri, local) = expanded_name(env.d, chosen)
        if same(name, "local-name") { ret (string_value(local), ok) }
        if same(name, "namespace-uri") { ret (string_value(uri), ok) }
        ret (string_value(qname_of(env.d, chosen)), ok)
    }
    if same(name, "string") {
        if n > 1usize { ret (zero, WrongArity) }
        if n == 0usize {
            let (text, text_error) = string_of(env.a, env.d, ctx.node)
            if text_error != ok { ret (zero, text_error) }
            ret (string_value(text), ok)
        }
        let (text, text_error) = arg_string(env, e, 0usize, ctx)
        if text_error != ok { ret (zero, text_error) }
        ret (string_value(text), ok)
    }
    if same(name, "concat") {
        if n < 2usize { ret (zero, WrongArity) }
        let (parts, parts_error) = mem.alloc[str](env.a, n)
        if parts_error != ok { ret (zero, parts_error) }
        var total = 0usize
        var i = 0usize
        while i < n {
            let (text, text_error) = arg_string(env, e, i, ctx)
            if text_error != ok { ret (zero, text_error) }
            parts[i] = text
            total += text.len
            i += 1usize
        }
        let (buffer, alloc_error) = mem.alloc[u8](env.a, total)
        if alloc_error != ok { ret (zero, alloc_error) }
        var used = 0usize
        i = 0usize
        while i < n {
            var k = 0usize
            while k < parts[i].len {
                buffer[used] = parts[i][k]
                used += 1usize
                k += 1usize
            }
            i += 1usize
        }
        ret (string_value(buffer[..used]), ok)
    }
    if same(name, "starts-with") || same(name, "contains") || same(name, "substring-before") || same(name, "substring-after") {
        if n != 2usize { ret (zero, WrongArity) }
        let (x, x_error) = arg_string(env, e, 0usize, ctx)
        if x_error != ok { ret (zero, x_error) }
        let (y, y_error) = arg_string(env, e, 1usize, ctx)
        if y_error != ok { ret (zero, y_error) }
        if same(name, "starts-with") { ret (boolean_value(str.starts_with(x, y)), ok) }
        if same(name, "contains") { ret (boolean_value(str.contains(x, y)), ok) }
        let (at, found) = str.find(x, y)
        if same(name, "substring-before") {
            if !found { ret (string_value(""), ok) }
            ret (string_value(x[..at]), ok)
        }
        if !found { ret (string_value(""), ok) }
        ret (string_value(x[at + y.len..]), ok)
    }
    if same(name, "substring") {
        if n != 2usize && n != 3usize { ret (zero, WrongArity) }
        let (text, text_error) = arg_string(env, e, 0usize, ctx)
        if text_error != ok { ret (zero, text_error) }
        let (start, start_error) = arg_number(env, e, 1usize, ctx)
        if start_error != ok { ret (zero, start_error) }
        var first = xpath_round(start)
        var last = infinity()
        if n == 3usize {
            let (length, length_error) = arg_number(env, e, 2usize, ctx)
            if length_error != ok { ret (zero, length_error) }
            last = first + xpath_round(length)
        }
        if is_nan(first) || is_nan(last) { ret (string_value(""), ok) }
        let total = char_count(text)
        // characters at 1-based positions p with first <= p < last
        var from = 1usize
        if first > 1.0f64 {
            if first > f64(total) { ret (string_value(""), ok) }
            from = usize(first)
        }
        var to = total + 1usize
        if last < f64(total) + 1.0f64 {
            if last <= 1.0f64 { ret (string_value(""), ok) }
            to = usize(last)
            if f64(to) < last { to += 1usize }
        }
        if to <= from { ret (string_value(""), ok) }
        let begin = char_offset(text, from - 1usize)
        let finish = char_offset(text, to - 1usize)
        ret (string_value(text[begin..finish]), ok)
    }
    if same(name, "string-length") {
        if n > 1usize { ret (zero, WrongArity) }
        var text = ""
        if n == 0usize {
            let (own, own_error) = string_of(env.a, env.d, ctx.node)
            if own_error != ok { ret (zero, own_error) }
            text = own
        } else {
            let (given, given_error) = arg_string(env, e, 0usize, ctx)
            if given_error != ok { ret (zero, given_error) }
            text = given
        }
        ret (number_value(f64(char_count(text))), ok)
    }
    if same(name, "normalize-space") {
        if n > 1usize { ret (zero, WrongArity) }
        var text = ""
        if n == 0usize {
            let (own, own_error) = string_of(env.a, env.d, ctx.node)
            if own_error != ok { ret (zero, own_error) }
            text = own
        } else {
            let (given, given_error) = arg_string(env, e, 0usize, ctx)
            if given_error != ok { ret (zero, given_error) }
            text = given
        }
        let (buffer, alloc_error) = mem.alloc[u8](env.a, text.len + 1usize)
        if alloc_error != ok { ret (zero, alloc_error) }
        var used = 0usize
        var pending = false
        var i = 0usize
        while i < text.len {
            if is_space(text[i]) {
                pending = used > 0usize
            } else {
                if pending {
                    buffer[used] = 32u8
                    used += 1usize
                    pending = false
                }
                buffer[used] = text[i]
                used += 1usize
            }
            i += 1usize
        }
        ret (string_value(buffer[..used]), ok)
    }
    if same(name, "translate") {
        if n != 3usize { ret (zero, WrongArity) }
        let (text, text_error) = arg_string(env, e, 0usize, ctx)
        if text_error != ok { ret (zero, text_error) }
        let (from_set, from_error) = arg_string(env, e, 1usize, ctx)
        if from_error != ok { ret (zero, from_error) }
        let (to_set, to_error) = arg_string(env, e, 2usize, ctx)
        if to_error != ok { ret (zero, to_error) }
        let (buffer, alloc_error) = mem.alloc[u8](env.a, text.len * 4usize + 4usize)
        if alloc_error != ok { ret (zero, alloc_error) }
        var used = 0usize
        var at = 0usize
        while at < text.len {
            let (dec, decode_error) = utf8.decode(text, at)
            var width = 1usize
            if decode_error == ok { width = usize(dec.width) }
            let piece = text[at..at + width]
            // the index of this character in the from-set
            var index = 0usize
            var found = false
            var from_at = 0usize
            while from_at < from_set.len && !found {
                let (fd, fe) = utf8.decode(from_set, from_at)
                var fw = 1usize
                if fe == ok { fw = usize(fd.width) }
                if same(from_set[from_at..from_at + fw], piece) { found = true } else {
                    index += 1usize
                    from_at += fw
                }
            }
            if !found {
                var i = 0usize
                while i < piece.len {
                    buffer[used] = piece[i]
                    used += 1usize
                    i += 1usize
                }
            } else {
                let begin = char_offset(to_set, index)
                if begin < to_set.len {
                    let finish = char_offset(to_set, index + 1usize)
                    var i = begin
                    while i < finish {
                        buffer[used] = to_set[i]
                        used += 1usize
                        i += 1usize
                    }
                }
            }
            at += width
        }
        ret (string_value(buffer[..used]), ok)
    }
    if same(name, "boolean") {
        if n != 1usize { ret (zero, WrongArity) }
        let (v, v_error) = arg_value(env, e, 0usize, ctx)
        if v_error != ok { ret (zero, v_error) }
        ret (boolean_value(to_boolean(v)), ok)
    }
    if same(name, "not") {
        if n != 1usize { ret (zero, WrongArity) }
        let (v, v_error) = arg_value(env, e, 0usize, ctx)
        if v_error != ok { ret (zero, v_error) }
        ret (boolean_value(!to_boolean(v)), ok)
    }
    if same(name, "true") {
        if n != 0usize { ret (zero, WrongArity) }
        ret (boolean_value(true), ok)
    }
    if same(name, "false") {
        if n != 0usize { ret (zero, WrongArity) }
        ret (boolean_value(false), ok)
    }
    if same(name, "lang") {
        if n != 1usize { ret (zero, WrongArity) }
        let (wanted, wanted_error) = arg_string(env, e, 0usize, ctx)
        if wanted_error != ok { ret (zero, wanted_error) }
        var at = ctx.node.id
        if ctx.node.attribute != 0u32 { at = ctx.node.id }
        while at != NONE {
            let node = node_of(env.d, at)
            if node.kind == .Element {
                let (value, found) = xml.attribute(&node, "xml:lang")
                if found {
                    if str.compare_ascii_fold(value, wanted) == 0i32 { ret (boolean_value(true), ok) }
                    if value.len > wanted.len && value[wanted.len] == 45u8 && str.compare_ascii_fold(value[..wanted.len], wanted) == 0i32 { ret (boolean_value(true), ok) }
                    ret (boolean_value(false), ok)
                }
            }
            at = node.parent
        }
        ret (boolean_value(false), ok)
    }
    if same(name, "number") {
        if n > 1usize { ret (zero, WrongArity) }
        if n == 0usize {
            let (text, text_error) = string_of(env.a, env.d, ctx.node)
            if text_error != ok { ret (zero, text_error) }
            ret (number_value(text_number(text)), ok)
        }
        let (x, x_error) = arg_number(env, e, 0usize, ctx)
        if x_error != ok { ret (zero, x_error) }
        ret (number_value(x), ok)
    }
    if same(name, "sum") {
        if n != 1usize { ret (zero, WrongArity) }
        let (v, v_error) = arg_value(env, e, 0usize, ctx)
        if v_error != ok { ret (zero, v_error) }
        if v.kind != Kind.NodeSet { ret (zero, TypeMismatch) }
        var total = 0.0f64
        var i = 0usize
        while i < v.nodes.len {
            let (text, text_error) = string_of(env.a, env.d, v.nodes[i])
            if text_error != ok { ret (zero, text_error) }
            total += text_number(text)
            i += 1usize
        }
        ret (number_value(total), ok)
    }
    if same(name, "floor") || same(name, "ceiling") || same(name, "round") {
        if n != 1usize { ret (zero, WrongArity) }
        let (x, x_error) = arg_number(env, e, 0usize, ctx)
        if x_error != ok { ret (zero, x_error) }
        if is_nan(x) || x == infinity() || x == -infinity() { ret (number_value(x), ok) }
        if same(name, "floor") { ret (number_value(math.floor[f64](x)), ok) }
        if same(name, "ceiling") { ret (number_value(math.ceil[f64](x)), ok) }
        ret (number_value(xpath_round(x)), ok)
    }
    if same(name, "current") && env.ext.has_current {
        if n != 0usize { ret (zero, WrongArity) }
        let (one, alloc_error) = mem.alloc[XNode](env.a, 1usize)
        if alloc_error != ok { ret (zero, alloc_error) }
        one[0usize] = env.ext.current
        ret (nodeset_value(one), ok)
    }
    if same(name, "generate-id") {
        if n > 1usize { ret (zero, WrongArity) }
        let (chosen, has_chosen, chosen_error) = first_node(env, e, ctx)
        if chosen_error != ok { ret (zero, chosen_error) }
        if !has_chosen { ret (string_value(""), ok) }
        let (builder, builder_error) = str.builder(env.a, 24usize)
        if builder_error != ok { ret (zero, builder_error) }
        var b = builder
        let p1 = str.push(&b, "id")
        if p1 != ok { ret (zero, p1) }
        let p2 = str.push_u64(&b, node_key(chosen))
        if p2 != ok { ret (zero, p2) }
        ret (string_value(str.done(&b)), ok)
    }
    ret (zero, UnknownFunction)
}

// ---- public interface ----

// Evaluate a compiled expression at `ctx` (position and size are those of the context node in its list).
fn evaluate(a: *mem.Arena, c: *const Compiled, d: *const xml.Document, ctx: Context, vars: *const Variables, ext: *const Extensions) -> (Value, err) {
    var env = Env { a: a, d: d, c: c, vars: vars, ext: ext, depth: 0u32 }
    let (v, v_error) = eval(&env, c.root, ctx)
    ret (v, v_error)
}

fn no_variables() -> Variables { ret Variables { items: zero, count: 0usize } }
fn no_extensions() -> Extensions { ret Extensions { current: XNode { id: 0u32, attribute: 0u32 }, has_current: false } }

// Convenience: compile and evaluate with the document node as context.
fn run(a: *mem.Arena, d: *const xml.Document, text: str, bindings: []const Binding) -> (Value, err) {
    let (c, c_error) = compile(a, text, bindings)
    if c_error != ok { ret (zero, c_error) }
    let vars = no_variables()
    let ext = no_extensions()
    let (v, v_error) = evaluate(a, &c, d, Context { node: XNode { id: d.root, attribute: 0u32 }, position: 1usize, size: 1usize }, &vars, &ext)
    ret (v, v_error)
}
