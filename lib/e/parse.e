// Parsing over caller storage. `lex` is a table-driven scanner over bytes
// (identifiers, integers, double-quoted strings with backslash escapes,
// operators from a caller list of multi-character spellings, single
// punctuation bytes, `//` comments and whitespace skipped) into
// `Token { kind, start, len }`; `lex_indent` is the off-side rule: `INDENT` and
// `DEDENT` tokens from a stack of space widths, `Invalid` on a dedent to a
// width never opened. `shunting_yard` turns infix tokens into RPN over an
// operator table; `pratt` and `recursive_descent` build the same AST in an
// `Ast` node pool (`ast_node`, `ast_child`) and `evaluate` folds it to an f64.
// `cyk` decides a CNF grammar, `earley` any grammar, and `next_terminals`
// answers which terminals may follow a prefix (Earley predict sets).
// `peg` is a packrat matcher over a PEG expression table.
//
// Grammar representation (shared with e.parse.ll and e.parse.lr): symbols are
// small integer ids, a symbol `s` is a terminal iff `s < terminals`; rule `i`
// is `lhs[i] -> rhs[rule_start[i]..rule_start[i + 1]]` (an empty range is an
// epsilon rule), `rule_start.len == rules + 1`. Bitset helpers cap symbol ids
// at 64 in `cyk` and terminals at 64 in `next_terminals`.

use e.math

type Token = struct { kind: u8, start: usize, len: usize }
type Op = struct { text: str, kind: u8, prec: u8, right: bool }
type Ast = struct { kind: []u8, a: []u32, b: []u32, tok: []u32, used: usize }
type Grammar = struct { lhs: []const u32, rhs: []const u32, rule_start: []const usize, terminals: u32 }
type Item = struct { rule: u32, dot: u32, origin: u32 }
type Peg = struct { op: []const u8, a: []const u32, b: []const u32, rules: []const u32 }
type Parser = struct { tokens: []const Token, text: str, ops: []const Op, pos: usize }
error TooSmall
error Invalid

// Token kinds.
const IDENT: u8 = 1u8
const INT: u8 = 2u8
const STRING: u8 = 3u8
const OP: u8 = 4u8
const INDENT: u8 = 5u8
const DEDENT: u8 = 6u8

// Operator kinds in an `Op` table; `prec` must stay below 128.
const PREFIX: u8 = 0u8
const INFIX: u8 = 1u8
const POSTFIX: u8 = 2u8

// AST node kinds: a LEAF holds its token; PREFIX/POSTFIX use child `a`;
// INFIX uses `a` and `b`. Node 0 is "none".
const LEAF: u8 = 1u8
const NODE_PREFIX: u8 = 2u8
const NODE_INFIX: u8 = 3u8
const NODE_POSTFIX: u8 = 4u8

// PEG expression ops: CHAR `a` is a byte; RANGE is bytes `a..=b`; ANY is one
// byte; SEQ/CHOICE combine nodes `a` and `b`; STAR/PLUS/OPT/NOT/AND wrap `a`;
// RULE refers to rule `a` (memoised); EMPTY matches nothing.
const PEG_CHAR: u8 = 1u8
const PEG_RANGE: u8 = 2u8
const PEG_ANY: u8 = 3u8
const PEG_SEQ: u8 = 4u8
const PEG_CHOICE: u8 = 5u8
const PEG_STAR: u8 = 6u8
const PEG_PLUS: u8 = 7u8
const PEG_OPT: u8 = 8u8
const PEG_NOT: u8 = 9u8
const PEG_AND: u8 = 10u8
const PEG_RULE: u8 = 11u8
const PEG_EMPTY: u8 = 12u8

fn is_ident_start(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 95u8 }
fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_punct(c: u8) -> bool { ret (c >= 33u8 && c <= 47u8) || (c >= 58u8 && c <= 64u8) || (c >= 91u8 && c <= 96u8) || (c >= 123u8 && c <= 126u8) }

fn starts_at(text: str, at_pos: usize, s: str) -> bool {
    if at_pos + s.len > text.len { ret false }
    var i = 0usize
    while i < s.len {
        if text[at_pos + i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn push_token(out: []Token, n: usize, kind: u8, start: usize, len: usize) -> err {
    if n >= out.len { ret TooSmall }
    out[n] = Token { kind: kind, start: start, len: len }
    ret ok
}

// Scan `text` into tokens; `operators` lists the multi-byte operator
// spellings (longest match wins), any other punctuation byte is a one-byte OP.
fn lex(text: str, operators: []const str, out: []Token) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 {
            i += 1usize
            continue
        }
        if c == 47u8 && i + 1usize < text.len && text[i + 1usize] == 47u8 {
            while i < text.len && text[i] != 10u8 { i += 1usize }
            continue
        }
        let start = i
        var kind = OP
        if is_ident_start(c) {
            kind = IDENT
            while i < text.len && (is_ident_start(text[i]) || is_digit(text[i])) { i += 1usize }
        } else if is_digit(c) {
            kind = INT
            while i < text.len && is_digit(text[i]) { i += 1usize }
        } else if c == 34u8 {
            kind = STRING
            i += 1usize
            while i < text.len && text[i] != 34u8 {
                if text[i] == 92u8 { i += 1usize }
                i += 1usize
            }
            if i >= text.len { ret (n, Invalid) }
            i += 1usize
        } else if is_punct(c) {
            i += 1usize
            var k = 0usize
            while k < operators.len {
                let o = operators[k]
                if o.len > i - start && starts_at(text, start, o) { i = start + o.len }
                k += 1usize
            }
        } else {
            ret (n, Invalid)
        }
        let e = push_token(out, n, kind, start, i - start)
        if e != ok { ret (n, e) }
        n += 1usize
    }
    ret (n, ok)
}

// The off-side rule over lines indented by spaces: an INDENT token (start =
// line start, len = width) when a non-blank line is deeper than the top of
// `stack`, one DEDENT per level closed (start = line start, len = new
// width), and the levels still open at the end close at `text.len`.
fn lex_indent(text: str, stack: []usize, out: []Token) -> (usize, err) {
    var n = 0usize
    var depth = 0usize
    var i = 0usize
    while i < text.len {
        let line = i
        var width = 0usize
        while i < text.len && text[i] == 32u8 {
            i += 1usize
            width += 1usize
        }
        if i >= text.len || text[i] == 10u8 || text[i] == 13u8 {
            while i < text.len && text[i] != 10u8 { i += 1usize }
            if i < text.len { i += 1usize }
            continue
        }
        var current = 0usize
        if depth > 0usize { current = stack[depth - 1usize] }
        if width > current {
            if depth >= stack.len { ret (n, TooSmall) }
            stack[depth] = width
            depth += 1usize
            let e = push_token(out, n, INDENT, line, width)
            if e != ok { ret (n, e) }
            n += 1usize
        } else {
            while width < current {
                depth -= 1usize
                current = 0usize
                if depth > 0usize { current = stack[depth - 1usize] }
                let e = push_token(out, n, DEDENT, line, current)
                if e != ok { ret (n, e) }
                n += 1usize
            }
            if width != current { ret (n, Invalid) }
        }
        while i < text.len && text[i] != 10u8 { i += 1usize }
        if i < text.len { i += 1usize }
    }
    while depth > 0usize {
        depth -= 1usize
        let e = push_token(out, n, DEDENT, text.len, 0usize)
        if e != ok { ret (n, e) }
        n += 1usize
    }
    ret (n, ok)
}

fn is_char(text: str, t: Token, c: u8) -> bool { ret t.kind == OP && t.len == 1usize && text[t.start] == c }

fn find_op(ops: []const Op, text: str, t: Token, kind: u8) -> (usize, bool) {
    if t.kind != OP { ret (0usize, false) }
    var k = 0usize
    while k < ops.len {
        if ops[k].kind == kind && ops[k].text.len == t.len && starts_at(text, t.start, ops[k].text) { ret (k, true) }
        k += 1usize
    }
    ret (0usize, false)
}

// Infix `tokens` to RPN in `out`; INFIX entries of `ops` are the operators,
// `(` and `)` group, operands pass through; `stack.len` bounds the nesting.
// ponytail: no function calls or unary minus; the Pratt parser has them.
fn shunting_yard(tokens: []const Token, text: str, ops: []const Op, out: []Token, stack: []Token) -> (usize, err) {
    var n = 0usize
    var depth = 0usize
    var i = 0usize
    while i < tokens.len {
        let t = tokens[i]
        i += 1usize
        if t.kind != OP {
            let e = push_token(out, n, t.kind, t.start, t.len)
            if e != ok { ret (n, e) }
            n += 1usize
            continue
        }
        if is_char(text, t, 40u8) {
            if depth >= stack.len { ret (n, TooSmall) }
            stack[depth] = t
            depth += 1usize
            continue
        }
        if is_char(text, t, 41u8) {
            while depth > 0usize && !is_char(text, stack[depth - 1usize], 40u8) {
                depth -= 1usize
                let e = push_token(out, n, OP, stack[depth].start, stack[depth].len)
                if e != ok { ret (n, e) }
                n += 1usize
            }
            if depth == 0usize { ret (n, Invalid) }
            depth -= 1usize
            continue
        }
        let (k, found) = find_op(ops, text, t, INFIX)
        if !found { ret (n, Invalid) }
        while depth > 0usize && !is_char(text, stack[depth - 1usize], 40u8) {
            let (top, _) = find_op(ops, text, stack[depth - 1usize], INFIX)
            if ops[top].prec < ops[k].prec || (ops[top].prec == ops[k].prec && ops[k].right) { break }
            depth -= 1usize
            let e = push_token(out, n, OP, stack[depth].start, stack[depth].len)
            if e != ok { ret (n, e) }
            n += 1usize
        }
        if depth >= stack.len { ret (n, TooSmall) }
        stack[depth] = t
        depth += 1usize
    }
    while depth > 0usize {
        depth -= 1usize
        if is_char(text, stack[depth], 40u8) { ret (n, Invalid) }
        let e = push_token(out, n, OP, stack[depth].start, stack[depth].len)
        if e != ok { ret (n, e) }
        n += 1usize
    }
    ret (n, ok)
}

// An AST pool over parallel arrays of one capacity; node 0 stays "none".
fn ast(kind: []u8, a: []u32, b: []u32, tok: []u32) -> Ast {
    ret Ast { kind: kind, a: a, b: b, tok: tok, used: 1usize }
}

// A node of `kind` with children `a`, `b` (0 = none) and token index `tok`.
fn ast_node(t: *Ast, kind: u8, a: u32, b: u32, tok: u32) -> (u32, err) {
    if t.used >= t.kind.len || t.used >= t.a.len || t.used >= t.b.len || t.used >= t.tok.len { ret (0u32, TooSmall) }
    let id = t.used
    t.used += 1usize
    t.kind[id] = kind
    t.a[id] = a
    t.b[id] = b
    t.tok[id] = tok
    ret (u32(id), ok)
}

// Child `which` (0 = a, 1 = b) of `node`.
fn ast_child(t: *const Ast, node: u32, which: usize) -> u32 {
    if which == 0usize { ret t.a[usize(node)] }
    ret t.b[usize(node)]
}

// Pratt: `ops` gives PREFIX, INFIX and POSTFIX entries with precedences
// (higher binds tighter; a PREFIX entry binds tighter than an INFIX entry of
// the same `prec`); `(` `)` group. Answers the root node.
fn pratt(tokens: []const Token, text: str, ops: []const Op, t: *Ast) -> (u32, err) {
    var p = Parser { tokens: tokens, text: text, ops: ops, pos: 0usize }
    let (root, e) = pratt_expr(&p, t, 0u8)
    if e != ok { ret (0u32, e) }
    if p.pos != tokens.len { ret (0u32, Invalid) }
    ret (root, ok)
}

fn pratt_expr(p: *Parser, t: *Ast, min_bp: u8) -> (u32, err) {
    if p.pos >= p.tokens.len { ret (0u32, Invalid) }
    let first = p.tokens[p.pos]
    p.pos += 1usize
    var lhs = 0u32
    if first.kind != OP {
        let (leaf, e) = ast_node(t, LEAF, 0u32, 0u32, u32(p.pos - 1usize))
        if e != ok { ret (0u32, e) }
        lhs = leaf
    } else if is_char(p.text, first, 40u8) {
        let (inner, e) = pratt_expr(p, t, 0u8)
        if e != ok { ret (0u32, e) }
        if p.pos >= p.tokens.len || !is_char(p.text, p.tokens[p.pos], 41u8) { ret (0u32, Invalid) }
        p.pos += 1usize
        lhs = inner
    } else {
        let (k, found) = find_op(p.ops, p.text, first, PREFIX)
        if !found { ret (0u32, Invalid) }
        let op_at = u32(p.pos - 1usize)
        let (rhs, e) = pratt_expr(p, t, 2u8 * p.ops[k].prec + 1u8)
        if e != ok { ret (0u32, e) }
        let (node, node_error) = ast_node(t, NODE_PREFIX, rhs, 0u32, op_at)
        if node_error != ok { ret (0u32, node_error) }
        lhs = node
    }
    while p.pos < p.tokens.len {
        let tok = p.tokens[p.pos]
        let (post, is_post) = find_op(p.ops, p.text, tok, POSTFIX)
        if is_post {
            if 2u8 * p.ops[post].prec < min_bp { break }
            p.pos += 1usize
            let (node, node_error) = ast_node(t, NODE_POSTFIX, lhs, 0u32, u32(p.pos - 1usize))
            if node_error != ok { ret (0u32, node_error) }
            lhs = node
            continue
        }
        let (k, found) = find_op(p.ops, p.text, tok, INFIX)
        if !found { break }
        let lbp = 2u8 * p.ops[k].prec
        if lbp < min_bp { break }
        var rbp = lbp + 1u8
        if p.ops[k].right { rbp = lbp - 1u8 }
        let op_at = u32(p.pos)
        p.pos += 1usize
        let (rhs, e) = pratt_expr(p, t, rbp)
        if e != ok { ret (0u32, e) }
        let (node, node_error) = ast_node(t, NODE_INFIX, lhs, rhs, op_at)
        if node_error != ok { ret (0u32, node_error) }
        lhs = node
    }
    ret (lhs, ok)
}

// Recursive descent over the fixed grammar
//   expr = term (('+' | '-') term)* ; term = unary (('*' | '/') unary)* ;
//   unary = '-' unary | power ; power = atom ('^' unary)? ; atom = INT | IDENT | '(' expr ')'
// producing the same AST shapes as `pratt`.
fn recursive_descent(tokens: []const Token, text: str, t: *Ast) -> (u32, err) {
    var p: Parser = zero
    p.tokens = tokens
    p.text = text
    let (root, e) = rd_expr(&p, t)
    if e != ok { ret (0u32, e) }
    if p.pos != tokens.len { ret (0u32, Invalid) }
    ret (root, ok)
}

fn peek_char(p: *const Parser, c: u8) -> bool {
    ret p.pos < p.tokens.len && is_char(p.text, p.tokens[p.pos], c)
}

fn rd_binary(p: *Parser, t: *Ast, lhs: u32, rhs: u32) -> (u32, err) {
    let (node, e) = ast_node(t, NODE_INFIX, lhs, rhs, u32(p.pos - 1usize))
    ret (node, e)
}

fn rd_expr(p: *Parser, t: *Ast) -> (u32, err) {
    var (lhs, e) = rd_term(p, t)
    if e != ok { ret (0u32, e) }
    while peek_char(p, 43u8) || peek_char(p, 45u8) {
        p.pos += 1usize
        let op_at = p.pos
        let (rhs, rhs_error) = rd_term(p, t)
        if rhs_error != ok { ret (0u32, rhs_error) }
        let (node, node_error) = ast_node(t, NODE_INFIX, lhs, rhs, u32(op_at - 1usize))
        if node_error != ok { ret (0u32, node_error) }
        lhs = node
    }
    ret (lhs, ok)
}

fn rd_term(p: *Parser, t: *Ast) -> (u32, err) {
    var (lhs, e) = rd_unary(p, t)
    if e != ok { ret (0u32, e) }
    while peek_char(p, 42u8) || peek_char(p, 47u8) {
        p.pos += 1usize
        let op_at = p.pos
        let (rhs, rhs_error) = rd_unary(p, t)
        if rhs_error != ok { ret (0u32, rhs_error) }
        let (node, node_error) = ast_node(t, NODE_INFIX, lhs, rhs, u32(op_at - 1usize))
        if node_error != ok { ret (0u32, node_error) }
        lhs = node
    }
    ret (lhs, ok)
}

fn rd_unary(p: *Parser, t: *Ast) -> (u32, err) {
    if peek_char(p, 45u8) {
        p.pos += 1usize
        let op_at = p.pos
        let (inner, e) = rd_unary(p, t)
        if e != ok { ret (0u32, e) }
        let (node, node_error) = ast_node(t, NODE_PREFIX, inner, 0u32, u32(op_at - 1usize))
        ret (node, node_error)
    }
    let (node, e) = rd_power(p, t)
    ret (node, e)
}

fn rd_power(p: *Parser, t: *Ast) -> (u32, err) {
    let (base, e) = rd_atom(p, t)
    if e != ok { ret (0u32, e) }
    if !peek_char(p, 94u8) { ret (base, ok) }
    p.pos += 1usize
    let op_at = p.pos
    let (exponent, exponent_error) = rd_unary(p, t)
    if exponent_error != ok { ret (0u32, exponent_error) }
    let (node, node_error) = ast_node(t, NODE_INFIX, base, exponent, u32(op_at - 1usize))
    ret (node, node_error)
}

fn rd_atom(p: *Parser, t: *Ast) -> (u32, err) {
    if p.pos >= p.tokens.len { ret (0u32, Invalid) }
    let tok = p.tokens[p.pos]
    if tok.kind == INT || tok.kind == IDENT {
        p.pos += 1usize
        let (leaf, e) = ast_node(t, LEAF, 0u32, 0u32, u32(p.pos - 1usize))
        ret (leaf, e)
    }
    if !is_char(p.text, tok, 40u8) { ret (0u32, Invalid) }
    p.pos += 1usize
    let (inner, e) = rd_expr(p, t)
    if e != ok { ret (0u32, e) }
    if !peek_char(p, 41u8) { ret (0u32, Invalid) }
    p.pos += 1usize
    ret (inner, ok)
}

// Fold an arithmetic AST: INT leaves, prefix `-`, infix `+ - * / ^`;
// anything else (an identifier, a postfix) is `Invalid`.
fn evaluate(t: *const Ast, node: u32, tokens: []const Token, text: str) -> (f64, err) {
    if node == 0u32 { ret (0.0f64, Invalid) }
    let n = usize(node)
    let tok = tokens[usize(t.tok[n])]
    let kind = t.kind[n]
    if kind == LEAF {
        if tok.kind != INT { ret (0.0f64, Invalid) }
        var value = 0.0f64
        var i = 0usize
        while i < tok.len {
            value = value * 10.0f64 + f64(text[tok.start + i] - 48u8)
            i += 1usize
        }
        ret (value, ok)
    }
    let (x, x_error) = evaluate(t, t.a[n], tokens, text)
    if x_error != ok { ret (0.0f64, x_error) }
    let c = text[tok.start]
    if kind == NODE_PREFIX {
        if tok.len != 1usize || c != 45u8 { ret (0.0f64, Invalid) }
        ret (0.0f64 - x, ok)
    }
    if kind != NODE_INFIX || tok.len != 1usize { ret (0.0f64, Invalid) }
    let (y, y_error) = evaluate(t, t.b[n], tokens, text)
    if y_error != ok { ret (0.0f64, y_error) }
    if c == 43u8 { ret (x + y, ok) }
    if c == 45u8 { ret (x - y, ok) }
    if c == 42u8 { ret (x * y, ok) }
    if c == 47u8 { ret (x / y, ok) }
    if c == 94u8 { ret (math.pow[f64](x, y), ok) }
    ret (0.0f64, Invalid)
}

// A grammar over the arrays described at the top of the module.
fn grammar(lhs: []const u32, rhs: []const u32, rule_start: []const usize, terminals: u32) -> Grammar {
    ret Grammar { lhs: lhs, rhs: rhs, rule_start: rule_start, terminals: terminals }
}

fn rule_count(g: *const Grammar) -> usize { ret g.rule_start.len - 1usize }
fn rule_len(g: *const Grammar, rule: usize) -> usize { ret g.rule_start[rule + 1usize] - g.rule_start[rule] }
fn rule_symbol(g: *const Grammar, rule: usize, at_pos: usize) -> u32 { ret g.rhs[g.rule_start[rule] + at_pos] }

// CYK over a grammar in Chomsky normal form (every rule `A -> B C` over
// non-terminals or `A -> a`); symbol ids below 64. `chart.len >= n * n`
// receives, at `(len - 1) * n + i`, the bitset of symbols deriving
// `sentence[i..i + len]`. Answers whether `start` derives the sentence.
fn cyk(g: *const Grammar, start: u32, sentence: []const u32, chart: []u64) -> (bool, err) {
    let n = sentence.len
    if chart.len < n * n { ret (false, TooSmall) }
    let rules = rule_count(g)
    var r = 0usize
    while r < rules {
        let len = rule_len(g, r)
        if g.lhs[r] >= 64u32 || (len != 1usize && len != 2usize) { ret (false, Invalid) }
        if rule_symbol(g, r, 0usize) >= 64u32 || (len == 2usize && rule_symbol(g, r, 1usize) >= 64u32) { ret (false, Invalid) }
        r += 1usize
    }
    if n == 0usize { ret (false, ok) }
    var i = 0usize
    while i < n * n {
        chart[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < n {
        r = 0usize
        while r < rules {
            if rule_len(g, r) == 1usize && rule_symbol(g, r, 0usize) == sentence[i] { chart[i] |= 1u64 << g.lhs[r] }
            r += 1usize
        }
        i += 1usize
    }
    var len = 2usize
    while len <= n {
        i = 0usize
        while i + len <= n {
            var split_at = 1usize
            var cell = 0u64
            while split_at < len {
                let left = chart[(split_at - 1usize) * n + i]
                let right = chart[(len - split_at - 1usize) * n + i + split_at]
                r = 0usize
                while r < rules {
                    if rule_len(g, r) == 2usize && ((left >> rule_symbol(g, r, 0usize)) & 1u64) == 1u64 && ((right >> rule_symbol(g, r, 1usize)) & 1u64) == 1u64 {
                        cell |= 1u64 << g.lhs[r]
                    }
                    r += 1usize
                }
                split_at += 1usize
            }
            chart[(len - 1usize) * n + i] = cell
            i += 1usize
        }
        len += 1usize
    }
    ret (((chart[(n - 1usize) * n] >> start) & 1u64) == 1u64, ok)
}

// Bit `s` set when non-terminal `s` derives the empty string (symbols
// beyond 64 never count as nullable).
fn nullable_set(g: *const Grammar) -> u64 {
    var mask = 0u64
    var changed = true
    let rules = rule_count(g)
    while changed {
        changed = false
        var r = 0usize
        while r < rules {
            if g.lhs[r] < 64u32 && ((mask >> g.lhs[r]) & 1u64) == 0u64 {
                var all = true
                var k = 0usize
                while k < rule_len(g, r) {
                    let s = rule_symbol(g, r, k)
                    if s >= 64u32 || ((mask >> s) & 1u64) == 0u64 { all = false }
                    k += 1usize
                }
                if all {
                    mask |= 1u64 << g.lhs[r]
                    changed = true
                }
            }
            r += 1usize
        }
    }
    ret mask
}

// Append `it` to the set starting at `items[from..]` unless already present.
fn earley_add(items: []Item, from: usize, used: usize, it: Item) -> (usize, err) {
    var m = from
    while m < used {
        if items[m].rule == it.rule && items[m].dot == it.dot && items[m].origin == it.origin { ret (used, ok) }
        m += 1usize
    }
    if used >= items.len { ret (used, TooSmall) }
    items[used] = it
    ret (used + 1usize, ok)
}

// Fill the Earley chart for `sentence`: set `k` is `items[sets[k]..sets[k + 1]]`
// for `k` in `0..=n`, `sets.len >= n + 2`. Answers the item count.
fn earley_run(g: *const Grammar, start: u32, sentence: []const u32, items: []Item, sets: []usize) -> (usize, err) {
    let n = sentence.len
    if sets.len < n + 2usize { ret (0usize, TooSmall) }
    let nullable = nullable_set(g)
    let rules = rule_count(g)
    var used = 0usize
    sets[0usize] = 0usize
    var r = 0usize
    while r < rules {
        if g.lhs[r] == start {
            let (grown, e) = earley_add(items, 0usize, used, Item { rule: u32(r), dot: 0u32, origin: 0u32 })
            if e != ok { ret (used, e) }
            used = grown
        }
        r += 1usize
    }
    var k = 0usize
    while k <= n {
        var j = sets[k]
        while j < used {
            let it = items[j]
            let rule = usize(it.rule)
            if usize(it.dot) < rule_len(g, rule) {
                let sym = rule_symbol(g, rule, usize(it.dot))
                if sym >= g.terminals {
                    r = 0usize
                    while r < rules {
                        if g.lhs[r] == sym {
                            let (grown, e) = earley_add(items, sets[k], used, Item { rule: u32(r), dot: 0u32, origin: u32(k) })
                            if e != ok { ret (used, e) }
                            used = grown
                        }
                        r += 1usize
                    }
                    if sym < 64u32 && ((nullable >> sym) & 1u64) == 1u64 {
                        let (grown, e) = earley_add(items, sets[k], used, Item { rule: it.rule, dot: it.dot + 1u32, origin: it.origin })
                        if e != ok { ret (used, e) }
                        used = grown
                    }
                }
            } else {
                let lhs = g.lhs[rule]
                let origin = usize(it.origin)
                var m = sets[origin]
                while true {
                    var bound = used
                    if origin != k { bound = sets[origin + 1usize] }
                    if m >= bound { break }
                    let parent = items[m]
                    let parent_rule = usize(parent.rule)
                    if usize(parent.dot) < rule_len(g, parent_rule) && rule_symbol(g, parent_rule, usize(parent.dot)) == lhs {
                        let (grown, e) = earley_add(items, sets[k], used, Item { rule: parent.rule, dot: parent.dot + 1u32, origin: parent.origin })
                        if e != ok { ret (used, e) }
                        used = grown
                    }
                    m += 1usize
                }
            }
            j += 1usize
        }
        sets[k + 1usize] = used
        if k < n {
            j = sets[k]
            while j < sets[k + 1usize] {
                let it = items[j]
                let rule = usize(it.rule)
                if usize(it.dot) < rule_len(g, rule) && rule_symbol(g, rule, usize(it.dot)) == sentence[k] {
                    if used >= items.len { ret (used, TooSmall) }
                    items[used] = Item { rule: it.rule, dot: it.dot + 1u32, origin: it.origin }
                    used += 1usize
                }
                j += 1usize
            }
        }
        k += 1usize
    }
    ret (used, ok)
}

// Earley recognition of `sentence` from `start` over any grammar (epsilon
// rules and ambiguity included); answers (derived, chart item count).
fn earley(g: *const Grammar, start: u32, sentence: []const u32, items: []Item, sets: []usize) -> (bool, usize, err) {
    let (used, e) = earley_run(g, start, sentence, items, sets)
    if e != ok { ret (false, used, e) }
    let n = sentence.len
    var j = sets[n]
    while j < sets[n + 1usize] {
        let it = items[j]
        if it.origin == 0u32 && g.lhs[usize(it.rule)] == start && usize(it.dot) == rule_len(g, usize(it.rule)) { ret (true, used, ok) }
        j += 1usize
    }
    ret (false, used, ok)
}

// The bitmask of terminals (fewer than 64) that may follow `prefix`.
fn viable_mask(g: *const Grammar, start: u32, prefix: []const u32, items: []Item, sets: []usize) -> (u64, err) {
    if g.terminals > 64u32 { ret (0u64, Invalid) }
    let (_, e) = earley_run(g, start, prefix, items, sets)
    if e != ok { ret (0u64, e) }
    let n = prefix.len
    var mask = 0u64
    var j = sets[n]
    while j < sets[n + 1usize] {
        let it = items[j]
        let rule = usize(it.rule)
        if usize(it.dot) < rule_len(g, rule) {
            let sym = rule_symbol(g, rule, usize(it.dot))
            if sym < g.terminals { mask |= 1u64 << sym }
        }
        j += 1usize
    }
    ret (mask, ok)
}

// Constrained decoding: the terminals (ascending, fewer than 64 of them)
// that may follow `prefix` in some sentence of `start`; none when the prefix
// is not viable.
fn next_terminals(g: *const Grammar, start: u32, prefix: []const u32, out: []u32, items: []Item, sets: []usize) -> (usize, err) {
    let (mask, e) = viable_mask(g, start, prefix, items, sets)
    if e != ok { ret (0usize, e) }
    var count = 0usize
    var s = 0u32
    while s < g.terminals {
        if ((mask >> s) & 1u64) == 1u64 {
            if count >= out.len { ret (count, TooSmall) }
            out[count] = s
            count += 1usize
        }
        s += 1u32
    }
    ret (count, ok)
}

// Packrat match of `rules[rule]` at the start of `text`; `memo.len >=
// rules.len * (text.len + 1)`. Answers (length, matched).
// ponytail: a left-recursive rule recurses forever; rewrite it with STAR.
fn peg(p: *const Peg, rule: usize, text: str, memo: []i64) -> (usize, bool, err) {
    if rule >= p.rules.len { ret (0usize, false, Invalid) }
    if memo.len < p.rules.len * (text.len + 1usize) { ret (0usize, false, TooSmall) }
    var i = 0usize
    while i < p.rules.len * (text.len + 1usize) {
        memo[i] = -2i64
        i += 1usize
    }
    let (len, matched) = peg_rule(p, rule, text, 0usize, memo)
    ret (len, matched, ok)
}

fn peg_rule(p: *const Peg, rule: usize, text: str, pos: usize, memo: []i64) -> (usize, bool) {
    let key = rule * (text.len + 1usize) + pos
    if memo[key] == -1i64 { ret (0usize, false) }
    if memo[key] >= 0i64 { ret (usize(memo[key]), true) }
    let (len, matched) = peg_match(p, p.rules[rule], text, pos, memo)
    if matched { memo[key] = i64(len) } else { memo[key] = -1i64 }
    ret (len, matched)
}

fn peg_match(p: *const Peg, node: u32, text: str, pos: usize, memo: []i64) -> (usize, bool) {
    let n = usize(node)
    let op = p.op[n]
    let a = p.a[n]
    if op == PEG_CHAR { ret (1usize, pos < text.len && u32(text[pos]) == a) }
    if op == PEG_RANGE { ret (1usize, pos < text.len && u32(text[pos]) >= a && u32(text[pos]) <= p.b[n]) }
    if op == PEG_ANY { ret (1usize, pos < text.len) }
    if op == PEG_EMPTY { ret (0usize, true) }
    if op == PEG_RULE {
        let (len, matched) = peg_rule(p, usize(a), text, pos, memo)
        ret (len, matched)
    }
    if op == PEG_SEQ {
        let (first, first_ok) = peg_match(p, a, text, pos, memo)
        if !first_ok { ret (0usize, false) }
        let (second, second_ok) = peg_match(p, p.b[n], text, pos + first, memo)
        ret (first + second, second_ok)
    }
    if op == PEG_CHOICE {
        let (first, first_ok) = peg_match(p, a, text, pos, memo)
        if first_ok { ret (first, true) }
        let (second, second_ok) = peg_match(p, p.b[n], text, pos, memo)
        ret (second, second_ok)
    }
    if op == PEG_STAR || op == PEG_PLUS {
        var total = 0usize
        var count = 0usize
        while true {
            let (len, matched) = peg_match(p, a, text, pos + total, memo)
            if !matched || len == 0usize { break }
            total += len
            count += 1usize
        }
        ret (total, op == PEG_STAR || count > 0usize)
    }
    if op == PEG_OPT {
        let (len, matched) = peg_match(p, a, text, pos, memo)
        if matched { ret (len, true) }
        ret (0usize, true)
    }
    if op == PEG_NOT || op == PEG_AND {
        let (_, matched) = peg_match(p, a, text, pos, memo)
        ret (0usize, matched == (op == PEG_AND))
    }
    ret (0usize, false)
}

// #1537 Grammar-constrained decoding: `allowed[i]` becomes whether the
// vocabulary token `vocab[i]` (a terminal id) may follow `prefix` in some
// sentence of `start`; answers how many are allowed (none when the prefix
// is not viable). Terminals are capped at 64 by the bitset.
fn constrained_decode(g: *const Grammar, start: u32, prefix: []const u32, vocab: []const u32, allowed: []bool, items: []Item, sets: []usize) -> (usize, err) {
    if allowed.len < vocab.len { ret (0usize, TooSmall) }
    let (mask, e) = viable_mask(g, start, prefix, items, sets)
    if e != ok { ret (0usize, e) }
    var count = 0usize
    var i = 0usize
    while i < vocab.len {
        allowed[i] = vocab[i] < g.terminals && ((mask >> vocab[i]) & 1u64) == 1u64
        if allowed[i] { count += 1usize }
        i += 1usize
    }
    ret (count, ok)
}
