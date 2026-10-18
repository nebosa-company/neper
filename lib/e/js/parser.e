// The JavaScript parser (browser tracker 5.2): ECMAScript source to the flat tree of `e.js.ast`.
//
// Recursive descent with precedence climbing for binary operators. Covered: statements (var/let/const, if, for, for-in,
// for-of, while, do, switch, try, labels, break/continue/return/throw, with), expressions (all operators, optional chaining,
// templates and tagged templates, regexp literals, spread, destructuring through the cover grammar, arrows, classes with
// fields, private names, accessors and static blocks, generators, async functions, `new.target`, `import()`), automatic
// semicolon insertion and the `"use strict"` directive. Early errors beyond syntax (duplicate declarations, invalid assignment
// targets, strict-mode restrictions) are not checked yet.

use e.data.list as list
use e.js.ast as ast
use e.js.bigint as bigint
use e.js.early as early
use e.js.lex as lex
use e.mem
use e.str

error ParseError

type Parser = struct {
    a: *mem.Arena, lx: lex.Lexer, tok: lex.Tok, prev_end: usize, prev_start: usize, prev_line: u32,
    nodes: list.List[ast.Node], kids: list.List[u32], strs: list.List[ast.TemplateStr], vars: list.List[u32],
    strict: bool, no_in: bool, in_function: bool, in_generator: bool, in_async: bool, uses_args: bool, blk: u32, module: bool, anon_default: bool, top_await: bool, sub_flag: bool,
    message: str, line: u32, parens: list.List[u32]
}

fn fail(p: *Parser, message: str) -> err {
    p.message = message
    p.line = p.tok.line
    ret ParseError
}

fn adv(p: *Parser) -> err {
    p.prev_end = p.tok.end
    p.prev_start = p.tok.start
    p.prev_line = p.tok.line
    let (t, e) = lex.next_token(&p.lx)
    if e != ok {
        p.message = p.lx.message
        p.line = p.lx.line
        ret e
    }
    p.tok = t
    ret ok
}

fn is_p(p: *const Parser, text: str) -> bool { ret p.tok.kind == lex.T_PUNCT && str.eq(p.tok.text, text) }
fn is_k(p: *const Parser, text: str) -> bool { ret p.tok.kind == lex.T_IDENT && !p.tok.escaped && str.eq(p.tok.text, text) }

fn eat_p(p: *Parser, text: str) -> (bool, err) {
    if is_p(p, text) {
        try adv(p)
        ret (true, ok)
    }
    ret (false, ok)
}

fn eat_k(p: *Parser, text: str) -> (bool, err) {
    if is_k(p, text) {
        try adv(p)
        ret (true, ok)
    }
    ret (false, ok)
}

fn expect_p(p: *Parser, text: str) -> err {
    if !is_p(p, text) { ret fail(p, "unexpected token") }
    ret adv(p)
}

fn expect_k(p: *Parser, text: str) -> err {
    if !is_k(p, text) { ret fail(p, "unexpected token") }
    ret adv(p)
}

// Re-reads the lexer position after a speculative scan.
type Mark = struct { pos: usize, line: u32, tok: lex.Tok, prev_end: usize, prev_line: u32 }

fn mark(p: *const Parser) -> Mark { ret Mark { pos: p.lx.pos, line: p.lx.line, tok: p.tok, prev_end: p.prev_end, prev_line: p.prev_line } }

fn restore(p: *Parser, m: Mark) {
    p.lx.pos = m.pos
    p.lx.line = m.line
    p.tok = m.tok
    p.prev_end = m.prev_end
    p.prev_line = m.prev_line
}

fn peek(p: *Parser) -> (lex.Tok, err) {
    let m = mark(p)
    try adv(p)
    let t = p.tok
    restore(p, m)
    ret (t, ok)
}

fn is_reserved(name: str) -> bool {
    if name.len < 2usize || name.len > 10usize { ret false }
    ret str.eq(name, "break") || str.eq(name, "case") || str.eq(name, "catch") || str.eq(name, "class") || str.eq(name, "const") || str.eq(name, "continue") || str.eq(name, "debugger") || str.eq(name, "default") || str.eq(name, "delete") || str.eq(name, "do") || str.eq(name, "else") || str.eq(name, "enum") || str.eq(name, "export") || str.eq(name, "extends") || str.eq(name, "false") || str.eq(name, "finally") || str.eq(name, "for") || str.eq(name, "function") || str.eq(name, "if") || str.eq(name, "import") || str.eq(name, "in") || str.eq(name, "instanceof") || str.eq(name, "new") || str.eq(name, "null") || str.eq(name, "return") || str.eq(name, "super") || str.eq(name, "switch") || str.eq(name, "this") || str.eq(name, "throw") || str.eq(name, "true") || str.eq(name, "try") || str.eq(name, "typeof") || str.eq(name, "var") || str.eq(name, "void") || str.eq(name, "while") || str.eq(name, "with")
}

// --- nodes

fn mk(p: *Parser, kind: u8) -> (u32, err) {
    let n = ast.Node { kind: kind, op: 0u8, flags: 0u16, a: ast.NONE, b: ast.NONE, c: ast.NONE, d: ast.NONE, hoist_first: 0u32, hoist_count: 0u32, line: p.tok.line, text: "", text2: "", num: 0.0f64 }
    let id = u32(p.nodes.len)
    try list.push[ast.Node](&p.nodes, n)
    ret (id, ok)
}

fn node(p: *Parser, id: u32) -> *ast.Node { ret &p.nodes.items[usize(id)] }

// Appends `ids` to the shared child list; the index of the first.
fn commit(p: *Parser, ids: *const list.List[u32]) -> (u32, err) {
    let first = u32(p.kids.len)
    var i = 0usize
    while i < ids.len {
        try list.push[u32](&p.kids, ids.items[i])
        i += 1usize
    }
    ret (first, ok)
}

fn new_ids(p: *Parser) -> (list.List[u32], err) {
    let (l, e) = list.init[u32](p.a, 8usize)
    ret (l, e)
}

// --- binding names, for hoisting `var`

fn collect_names(p: *Parser, id: u32) -> err {
    if id == ast.NONE { ret ok }
    let n = p.nodes.items[usize(id)]
    if n.kind == ast.N_IDENT {
        try list.push[u32](&p.vars, id)
    } else if n.kind == ast.N_ARRAY || n.kind == ast.N_OBJECT {
        var i = 0usize
        while i < usize(n.b) {
            try collect_names(p, p.kids.items[usize(n.a) + i])
            i += 1usize
        }
    } else if n.kind == ast.N_PROP {
        try collect_names(p, n.b)
    } else if n.kind == ast.N_ASSIGN {
        try collect_names(p, n.a)
    } else if n.kind == ast.N_SPREAD {
        try collect_names(p, n.a)
    }
    ret ok
}

// --- operators

fn binary_info(p: *const Parser) -> (u8, u8, bool) {
    // (op, precedence, found)
    if p.tok.kind == lex.T_IDENT && !p.tok.escaped {
        if str.eq(p.tok.text, "instanceof") { ret (ast.O_INSTANCEOF, 9u8, true) }
        if str.eq(p.tok.text, "in") && !p.no_in { ret (ast.O_IN, 9u8, true) }
        ret (0u8, 0u8, false)
    }
    if p.tok.kind != lex.T_PUNCT { ret (0u8, 0u8, false) }
    let t = p.tok.text
    if t.len == 1usize {
        let c = t[0usize]
        if c == 43u8 { ret (ast.O_ADD, 11u8, true) }
        if c == 45u8 { ret (ast.O_SUB, 11u8, true) }
        if c == 42u8 { ret (ast.O_MUL, 12u8, true) }
        if c == 47u8 { ret (ast.O_DIV, 12u8, true) }
        if c == 37u8 { ret (ast.O_MOD, 12u8, true) }
        if c == 60u8 { ret (ast.O_LT, 9u8, true) }
        if c == 62u8 { ret (ast.O_GT, 9u8, true) }
        if c == 38u8 { ret (ast.O_BITAND, 7u8, true) }
        if c == 124u8 { ret (ast.O_BITOR, 5u8, true) }
        if c == 94u8 { ret (ast.O_BITXOR, 6u8, true) }
        ret (0u8, 0u8, false)
    }
    if str.eq(t, "**") { ret (ast.O_EXP, 13u8, true) }
    if str.eq(t, "==") { ret (ast.O_EQ, 8u8, true) }
    if str.eq(t, "!=") { ret (ast.O_NE, 8u8, true) }
    if str.eq(t, "===") { ret (ast.O_SEQ, 8u8, true) }
    if str.eq(t, "!==") { ret (ast.O_SNE, 8u8, true) }
    if str.eq(t, "<=") { ret (ast.O_LE, 9u8, true) }
    if str.eq(t, ">=") { ret (ast.O_GE, 9u8, true) }
    if str.eq(t, "<<") { ret (ast.O_SHL, 10u8, true) }
    if str.eq(t, ">>") { ret (ast.O_SHR, 10u8, true) }
    if str.eq(t, ">>>") { ret (ast.O_USHR, 10u8, true) }
    if str.eq(t, "&&") { ret (ast.O_AND, 4u8, true) }
    if str.eq(t, "||") { ret (ast.O_OR, 3u8, true) }
    if str.eq(t, "??") { ret (ast.O_NULLISH, 2u8, true) }
    ret (0u8, 0u8, false)
}

// The operator of an assignment token (`=` is O_ASSIGN; compound ones their binary operator; logical ones O_AND/O_OR/O_NULLISH
// with `assign_logical`).
fn assign_info(p: *const Parser) -> (u8, bool, bool) {
    if p.tok.kind != lex.T_PUNCT { ret (0u8, false, false) }
    let t = p.tok.text
    if str.eq(t, "=") { ret (ast.O_ASSIGN, false, true) }
    if str.eq(t, "+=") { ret (ast.O_ADD, false, true) }
    if str.eq(t, "-=") { ret (ast.O_SUB, false, true) }
    if str.eq(t, "*=") { ret (ast.O_MUL, false, true) }
    if str.eq(t, "/=") { ret (ast.O_DIV, false, true) }
    if str.eq(t, "%=") { ret (ast.O_MOD, false, true) }
    if str.eq(t, "**=") { ret (ast.O_EXP, false, true) }
    if str.eq(t, "<<=") { ret (ast.O_SHL, false, true) }
    if str.eq(t, ">>=") { ret (ast.O_SHR, false, true) }
    if str.eq(t, ">>>=") { ret (ast.O_USHR, false, true) }
    if str.eq(t, "&=") { ret (ast.O_BITAND, false, true) }
    if str.eq(t, "|=") { ret (ast.O_BITOR, false, true) }
    if str.eq(t, "^=") { ret (ast.O_BITXOR, false, true) }
    if str.eq(t, "&&=") { ret (ast.O_AND, true, true) }
    if str.eq(t, "||=") { ret (ast.O_OR, true, true) }
    if str.eq(t, "??=") { ret (ast.O_NULLISH, true, true) }
    ret (0u8, false, false)
}

// --- expressions

fn parse_expression(p: *Parser) -> (u32, err) {
    let first = try parse_assign(p)
    if !is_p(p, ",") { ret (first, ok) }
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    try list.push[u32](&ids, first)
    while is_p(p, ",") {
        try adv(p)
        let next_expr = try parse_assign(p)
        try list.push[u32](&ids, next_expr)
    }
    let (k, ke) = commit(p, &ids)
    if ke != ok { ret (ast.NONE, ke) }
    let (id, me) = mk(p, ast.N_SEQ)
    if me != ok { ret (ast.NONE, me) }
    node(p, id).a = k
    node(p, id).b = u32(ids.len)
    ret (id, ok)
}

// Whether the tokens from the current `(` form arrow parameters: skips to the matching `)` and looks for `=>`.
fn arrow_follows_paren(p: *Parser) -> (bool, err) {
    let m = mark(p)
    var depth = 0usize
    var result = false
    var done = false
    var last_kind = lex.T_PUNCT
    var last_text = "("
    while !done {
        if p.tok.kind == lex.T_EOF {
            done = true
        } else {
            if p.tok.kind == lex.T_PUNCT {
                let t = p.tok.text
                if str.eq(t, "(") || str.eq(t, "[") || str.eq(t, "{") {
                    depth += 1usize
                } else if str.eq(t, ")") || str.eq(t, "]") || str.eq(t, "}") {
                    if depth > 0usize { depth -= 1usize }
                    if depth == 0usize {
                        try adv(p)
                        result = is_p(p, "=>") && !p.tok.nl
                        done = true
                    }
                } else if (str.eq(t, "/") || str.eq(t, "/=")) {
                    // A `/` that cannot be a division (nothing before it ends an expression) opens a regular expression, whose
                    // brackets and quotes must not be counted.
                    var regex_ok = false
                    if last_kind == lex.T_PUNCT {
                        regex_ok = !str.eq(last_text, ")") && !str.eq(last_text, "]") && !str.eq(last_text, "}") && !str.eq(last_text, "++") && !str.eq(last_text, "--")
                    } else if last_kind == lex.T_IDENT {
                        regex_ok = str.eq(last_text, "return") || str.eq(last_text, "typeof") || str.eq(last_text, "instanceof") || str.eq(last_text, "in") || str.eq(last_text, "of") || str.eq(last_text, "new") || str.eq(last_text, "delete") || str.eq(last_text, "void") || str.eq(last_text, "throw") || str.eq(last_text, "case") || str.eq(last_text, "do") || str.eq(last_text, "else") || str.eq(last_text, "yield") || str.eq(last_text, "await")
                    }
                    if regex_ok {
                        let (rt, re) = lex.regex_at(&p.lx, p.tok.start)
                        if re == ok { p.tok = rt }
                    }
                }
            }
            if !done {
                last_kind = p.tok.kind
                last_text = p.tok.text
                try adv(p)
            }
        }
    }
    restore(p, m)
    ret (result, ok)
}

fn parse_arrow_body(p: *Parser, fid: u32, async_flag: bool) -> err {
    let saved_async = p.in_async
    let saved_gen = p.in_generator
    let saved_fn = p.in_function
    let saved_no_in = p.no_in
    p.in_async = async_flag
    p.in_generator = false
    p.in_function = true
    if is_p(p, "{") {
        let body = try parse_function_body(p, fid)
        node(p, fid).c = body
    } else {
        // An expression body: its own `no_in` follows the enclosing context.
        p.no_in = saved_no_in
        let e = try parse_assign(p)
        node(p, fid).c = e
        node(p, fid).flags = node(p, fid).flags | ast.F_EXPR_BODY
    }
    p.in_async = saved_async
    p.in_generator = saved_gen
    p.in_function = saved_fn
    p.no_in = saved_no_in
    ret ok
}

// An arrow function whose parameters are already parsed into `params`.
fn finish_arrow(p: *Parser, params: *const list.List[u32], async_flag: bool, start: usize) -> (u32, err) {
    let (fid, fe) = mk(p, ast.N_FUNC)
    if fe != ok { ret (ast.NONE, fe) }
    let (k, ke) = commit(p, params)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, fid).a = k
    node(p, fid).b = u32(params.len)
    var fl = ast.F_ARROW
    if async_flag { fl = fl | ast.F_ASYNC }
    if p.strict { fl = fl | ast.F_STRICT }
    node(p, fid).flags = fl
    node(p, fid).num = f64(arity(p, params))
    let saved_vars = p.vars.len
    try expect_p(p, "=>")
    try parse_arrow_body(p, fid, async_flag)
    close_hoist(p, fid, saved_vars)
    node(p, fid).text2 = p.lx.src[start..p.prev_end]
    ret (fid, ok)
}

fn arity(p: *const Parser, params: *const list.List[u32]) -> usize {
    var n = 0usize
    var i = 0usize
    while i < params.len {
        let k = p.nodes.items[usize(params.items[i])].kind
        if k == ast.N_ASSIGN || k == ast.N_SPREAD { break }
        n += 1usize
        i += 1usize
    }
    ret n
}

// Moves the `var` names collected since `from` into the function's hoist list.
fn close_hoist(p: *Parser, fid: u32, from: usize) {
    let first = u32(p.kids.len)
    var i = from
    var count = 0u32
    while i < p.vars.len {
        let pushed = list.push[u32](&p.kids, p.vars.items[i])
        count += 1u32
        i += 1usize
    }
    p.vars.len = from
    node(p, fid).hoist_first = first
    node(p, fid).hoist_count = count
}

fn parse_assign(p: *Parser) -> (u32, err) {
    // Arrow functions and yield.
    if p.tok.kind == lex.T_IDENT && !p.tok.escaped {
        if str.eq(p.tok.text, "yield") && p.in_generator {
            let y = try parse_yield(p)
            ret (y, ok)
        }
        if str.eq(p.tok.text, "async") {
            let nx = try peek(p)
            if !nx.nl && nx.kind == lex.T_IDENT && !str.eq(nx.text, "function") && !is_reserved(nx.text) {
                // async x => ...
                let m = mark(p)
                try adv(p)
                let name_tok = p.tok
                try adv(p)
                if is_p(p, "=>") && !p.tok.nl {
                    let (ids_0, ie) = new_ids(p)
                    var ids = ids_0
                    if ie != ok { ret (ast.NONE, ie) }
                    let (pid, pe) = mk(p, ast.N_IDENT)
                    if pe != ok { ret (ast.NONE, pe) }
                    node(p, pid).text = name_tok.text
                    try list.push[u32](&ids, pid)
                    let f = try finish_arrow(p, &ids, true, m.tok.start)
                    ret (f, ok)
                }
                restore(p, m)
            } else if !nx.nl && nx.kind == lex.T_PUNCT && str.eq(nx.text, "(") {
                let m2 = mark(p)
                try adv(p)
                let is_arrow = try arrow_follows_paren(p)
                if is_arrow {
                    let params = try parse_params(p)
                    let f2 = try finish_arrow(p, &params, true, m2.tok.start)
                    ret (f2, ok)
                }
                restore(p, m2)
            }
        } else if !is_reserved(p.tok.text) {
            let nx2 = try peek(p)
            if nx2.kind == lex.T_PUNCT && str.eq(nx2.text, "=>") && !nx2.nl {
                let name_tok2 = p.tok
                try adv(p)
                let (ids2_0, ie2) = new_ids(p)
                var ids2 = ids2_0
                if ie2 != ok { ret (ast.NONE, ie2) }
                let (pid2, pe2) = mk(p, ast.N_IDENT)
                if pe2 != ok { ret (ast.NONE, pe2) }
                node(p, pid2).text = name_tok2.text
                try list.push[u32](&ids2, pid2)
                let f3 = try finish_arrow(p, &ids2, false, name_tok2.start)
                ret (f3, ok)
            }
        }
    } else if is_p(p, "(") {
        let is_arrow2 = try arrow_follows_paren(p)
        if is_arrow2 {
            let paren_start = p.tok.start
            let params2 = try parse_params(p)
            let f4 = try finish_arrow(p, &params2, false, paren_start)
            ret (f4, ok)
        }
    }
    let lhs = try parse_conditional(p)
    let (op, logical, found) = assign_info(p)
    if !found { ret (lhs, ok) }
    try adv(p)
    let rhs = try parse_assign(p)
    let (id, me) = mk(p, ast.N_ASSIGN)
    if me != ok { ret (ast.NONE, me) }
    node(p, id).op = op
    if logical { node(p, id).flags = ast.F_OPTIONAL }
    node(p, id).a = lhs
    node(p, id).b = rhs
    ret (id, ok)
}

fn parse_yield(p: *Parser) -> (u32, err) {
    let (id, me) = mk(p, ast.N_YIELD)
    if me != ok { ret (ast.NONE, me) }
    try adv(p)
    if p.tok.nl || p.tok.kind == lex.T_EOF || is_p(p, ")") || is_p(p, "]") || is_p(p, "}") || is_p(p, ",") || is_p(p, ";") || is_p(p, ":") || is_k(p, "in") || is_k(p, "of") {
        ret (id, ok)
    }
    if is_p(p, "*") {
        try adv(p)
        node(p, id).flags = ast.F_DELEGATE
    }
    let v = try parse_assign(p)
    node(p, id).a = v
    ret (id, ok)
}

fn parse_conditional(p: *Parser) -> (u32, err) {
    let test = try parse_binary(p, 0u8)
    if !is_p(p, "?") { ret (test, ok) }
    try adv(p)
    let saved = p.no_in
    p.no_in = false
    let yes = try parse_assign(p)
    p.no_in = saved
    try expect_p(p, ":")
    let no = try parse_assign(p)
    let (id, me) = mk(p, ast.N_COND)
    if me != ok { ret (ast.NONE, me) }
    node(p, id).a = test
    node(p, id).b = yes
    node(p, id).c = no
    ret (id, ok)
}

fn is_paren(p: *const Parser, id: u32) -> bool {
    var i = 0usize
    while i < p.parens.len {
        if p.parens.items[i] == id { ret true }
        i += 1usize
    }
    ret false
}

fn logical_kind(p: *Parser, id: u32) -> u8 {
    // 1: && or ||, 2: ??, 0: anything else (a parenthesised logical expression is a primary).
    let n = node(p, id)
    if n.kind != ast.N_LOGICAL || is_paren(p, id) { ret 0u8 }
    if n.op == ast.O_NULLISH { ret 2u8 }
    ret 1u8
}

fn parse_binary(p: *Parser, min_prec: u8) -> (u32, err) {
    var left: u32 = ast.NONE
    // `#x in obj`.
    if p.tok.kind == lex.T_PRIVATE {
        let (pid, pe) = mk(p, ast.N_PRIVATE)
        if pe != ok { ret (ast.NONE, pe) }
        node(p, pid).text = p.tok.text
        try adv(p)
        if !is_k(p, "in") { ret (ast.NONE, fail(p, "unexpected private name")) }
        left = pid
    } else {
        left = try parse_unary(p)
    }
    while true {
        let (op, prec, found) = binary_info(p)
        if !found || prec <= min_prec { break }
        try adv(p)
        var right: u32 = ast.NONE
        if op == ast.O_EXP {
            right = try parse_binary(p, prec - 1u8)
        } else {
            right = try parse_binary(p, prec)
        }
        var kind = ast.N_BINARY
        if op == ast.O_AND || op == ast.O_OR || op == ast.O_NULLISH { kind = ast.N_LOGICAL }
        if op == ast.O_EXP {
            let lk = node(p, left).kind
            if (lk == ast.N_UNARY || lk == ast.N_AWAIT) && !is_paren(p, left) { ret (ast.NONE, fail(p, "Unary operator used immediately before exponentiation expression")) }
        }
        if kind == ast.N_LOGICAL {
            let lg = logical_kind(p, left)
            let rg = logical_kind(p, right)
            if op == ast.O_NULLISH && (lg == 1u8 || rg == 1u8) { ret (ast.NONE, fail(p, "Cannot mix ?? with || or && without parentheses")) }
            if op != ast.O_NULLISH && (lg == 2u8 || rg == 2u8) { ret (ast.NONE, fail(p, "Cannot mix ?? with || or && without parentheses")) }
        }
        let (id, me) = mk(p, kind)
        if me != ok { ret (ast.NONE, me) }
        node(p, id).op = op
        node(p, id).a = left
        node(p, id).b = right
        left = id
    }
    ret (left, ok)
}

fn parse_unary(p: *Parser) -> (u32, err) {
    if p.tok.kind == lex.T_PUNCT {
        let t = p.tok.text
        var op = 0u8
        if str.eq(t, "!") { op = ast.O_NOT } else if str.eq(t, "-") { op = ast.O_NEG } else if str.eq(t, "+") { op = ast.O_PLUS } else if str.eq(t, "~") { op = ast.O_BITNOT }
        if op != 0u8 {
            let (id, me) = mk(p, ast.N_UNARY)
            if me != ok { ret (ast.NONE, me) }
            try adv(p)
            let arg = try parse_unary(p)
            node(p, id).op = op
            node(p, id).a = arg
            ret (id, ok)
        }
        if str.eq(t, "++") || str.eq(t, "--") {
            let (id2, me2) = mk(p, ast.N_UPDATE)
            if me2 != ok { ret (ast.NONE, me2) }
            var uop = ast.O_INC
            if str.eq(t, "--") { uop = ast.O_DEC }
            try adv(p)
            let arg2 = try parse_unary(p)
            node(p, id2).op = uop
            node(p, id2).flags = ast.F_PREFIX
            node(p, id2).a = arg2
            ret (id2, ok)
        }
    } else if p.tok.kind == lex.T_IDENT && !p.tok.escaped {
        let t2 = p.tok.text
        var op2 = 0u8
        if str.eq(t2, "typeof") { op2 = ast.O_TYPEOF } else if str.eq(t2, "void") { op2 = ast.O_VOID } else if str.eq(t2, "delete") { op2 = ast.O_DELETE }
        if op2 != 0u8 {
            let (id3, me3) = mk(p, ast.N_UNARY)
            if me3 != ok { ret (ast.NONE, me3) }
            try adv(p)
            let arg3 = try parse_unary(p)
            node(p, id3).op = op2
            node(p, id3).a = arg3
            ret (id3, ok)
        }
        if str.eq(t2, "await") && p.in_async {
            let (id4, me4) = mk(p, ast.N_AWAIT)
            if me4 != ok { ret (ast.NONE, me4) }
            if !p.in_function { p.top_await = true }
            try adv(p)
            let arg4 = try parse_unary(p)
            node(p, id4).a = arg4
            ret (id4, ok)
        }
    }
    let e = try parse_postfix(p)
    ret (e, ok)
}

fn parse_postfix(p: *Parser) -> (u32, err) {
    let e = try parse_lhs(p)
    if p.tok.kind == lex.T_PUNCT && !p.tok.nl && (str.eq(p.tok.text, "++") || str.eq(p.tok.text, "--")) {
        let (id, me) = mk(p, ast.N_UPDATE)
        if me != ok { ret (ast.NONE, me) }
        var op = ast.O_INC
        if str.eq(p.tok.text, "--") { op = ast.O_DEC }
        try adv(p)
        node(p, id).op = op
        node(p, id).a = e
        ret (id, ok)
    }
    ret (e, ok)
}

// Arguments `( a, ...b )` after the current `(`.
fn parse_arguments(p: *Parser) -> (list.List[u32], err) {
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ids, ie) }
    try expect_p(p, "(")
    let saved = p.no_in
    p.no_in = false
    while !is_p(p, ")") {
        if is_p(p, "...") {
            let (sid, se) = mk(p, ast.N_SPREAD)
            if se != ok { ret (ids, se) }
            try adv(p)
            let v = try parse_assign(p)
            node(p, sid).a = v
            try list.push[u32](&ids, sid)
        } else {
            let v2 = try parse_assign(p)
            try list.push[u32](&ids, v2)
        }
        if !is_p(p, ")") { try expect_p(p, ",") }
    }
    p.no_in = saved
    try adv(p)
    ret (ids, ok)
}

fn parse_template(p: *Parser) -> (u32, err) {
    let (id, me) = mk(p, ast.N_TEMPLATE)
    if me != ok { ret (ast.NONE, me) }
    let tpl = p.lx.template
    node(p, id).a = u32(p.strs.len)
    node(p, id).b = u32(tpl.cooked.len)
    var i = 0usize
    while i < tpl.cooked.len {
        try list.push[ast.TemplateStr](&p.strs, ast.TemplateStr { cooked: tpl.cooked[i], raw: tpl.raw[i], valid: tpl.valid[i] })
        i += 1usize
    }
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    var k = 0usize
    while k < tpl.exprs.len {
        let e = try parse_sub(p, tpl.exprs[k])
        try list.push[u32](&ids, e)
        k += 1usize
    }
    try adv(p)
    let (first, ce) = commit(p, &ids)
    if ce != ok { ret (ast.NONE, ce) }
    node(p, id).c = first
    node(p, id).d = u32(ids.len)
    ret (id, ok)
}

// Parses `src` (a template substitution) as an expression with the parser's flags, then resumes the outer source.
fn parse_sub(p: *Parser, src: str) -> (u32, err) {
    let saved_lx = p.lx
    let saved_tok = p.tok
    let saved_prev = p.prev_end
    let saved_line = p.prev_line
    p.lx = lex.new_lexer(p.a, src)
    p.lx.line = saved_tok.line
    try adv(p)
    let saved_no_in = p.no_in
    p.no_in = false
    let e = try parse_expression(p)
    p.no_in = saved_no_in
    if p.tok.kind != lex.T_EOF { ret (ast.NONE, fail(p, "unexpected token in template substitution")) }
    p.lx = saved_lx
    p.tok = saved_tok
    p.prev_end = saved_prev
    p.prev_line = saved_line
    ret (e, ok)
}

// The decimal text of a BigInt literal (`0x1fn`, `1_000n`, ...).
fn bigint_key_text(p: *Parser, text: str) -> (str, err) {
    var digits = text
    if digits.len > 0usize && digits[digits.len - 1usize] == 110u8 { digits = digits[0usize..digits.len - 1usize] }
    var radix = 10u32
    if digits.len > 2usize && digits[0usize] == 48u8 {
        let c = digits[1usize]
        if c == 120u8 || c == 88u8 {
            radix = 16u32
            digits = digits[2usize..]
        } else if c == 111u8 || c == 79u8 {
            radix = 8u32
            digits = digits[2usize..]
        } else if c == 98u8 || c == 66u8 {
            radix = 2u32
            digits = digits[2usize..]
        }
    }
    let (bb, be) = str.builder(p.a, digits.len)
    if be != ok { ret ("", be) }
    var b2 = bb
    var i = 0usize
    while i < digits.len {
        if digits[i] != 95u8 { let pe = str.push_byte(&b2, digits[i]) }
        i += 1usize
    }
    let clean = str.done(&b2)
    let (bv, good, pe2) = bigint.parse_digits(p.a, clean, radix)
    if pe2 != ok || !good { ret ("", fail(p, "Invalid BigInt literal")) }
    let (txt, te) = bigint.to_string(p.a, bv, 10u32)
    if te != ok { ret ("", te) }
    ret (txt, ok)
}

fn parse_property_key(p: *Parser) -> (u32, bool, err) {
    // Keys: identifier names (including reserved words), strings, numbers, `[expr]`, `#private`.
    if is_p(p, "[") {
        try adv(p)
        let saved = p.no_in
        p.no_in = false
        let e = try parse_assign(p)
        p.no_in = saved
        try expect_p(p, "]")
        ret (e, true, ok)
    }
    if p.tok.kind == lex.T_STR {
        let (id, me) = mk(p, ast.N_STR)
        if me != ok { ret (ast.NONE, false, me) }
        node(p, id).text = p.tok.text
        try adv(p)
        ret (id, false, ok)
    }
    if p.tok.kind == lex.T_NUM && p.tok.big {
        // A BigInt literal names the property by its decimal string.
        let (idb, meb) = mk(p, ast.N_STR)
        if meb != ok { ret (ast.NONE, false, meb) }
        node(p, idb).text = try bigint_key_text(p, p.lx.src[p.tok.start..p.tok.end])
        try adv(p)
        ret (idb, false, ok)
    }
    if p.tok.kind == lex.T_NUM {
        let (id2, me2) = mk(p, ast.N_NUM)
        if me2 != ok { ret (ast.NONE, false, me2) }
        node(p, id2).num = p.tok.num
        try adv(p)
        ret (id2, false, ok)
    }
    if p.tok.kind == lex.T_PRIVATE {
        let (id3, me3) = mk(p, ast.N_PRIVATE)
        if me3 != ok { ret (ast.NONE, false, me3) }
        node(p, id3).text = p.tok.text
        try adv(p)
        ret (id3, false, ok)
    }
    if p.tok.kind == lex.T_IDENT {
        let (id4, me4) = mk(p, ast.N_STR)
        if me4 != ok { ret (ast.NONE, false, me4) }
        node(p, id4).text = p.tok.text
        try adv(p)
        ret (id4, false, ok)
    }
    ret (ast.NONE, false, fail(p, "unexpected token in property key"))
}

// A method, getter, setter or generator/async method body: the `(`..`}` after the key; `flags` gives async/generator/method.
fn parse_method(p: *Parser, name: str, flags: u16, start: usize) -> (u32, err) {
    let (fid, fe) = mk(p, ast.N_FUNC)
    if fe != ok { ret (ast.NONE, fe) }
    node(p, fid).text = name
    node(p, fid).flags = flags | ast.F_METHOD
    try parse_function_rest(p, fid)
    node(p, fid).text2 = p.lx.src[start..p.prev_end]
    ret (fid, ok)
}

fn parse_object(p: *Parser) -> (u32, err) {
    let (id, me) = mk(p, ast.N_OBJECT)
    if me != ok { ret (ast.NONE, me) }
    try expect_p(p, "{")
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    let saved = p.no_in
    p.no_in = false
    while !is_p(p, "}") {
        let (pid, pe) = mk(p, ast.N_PROP)
        if pe != ok { ret (ast.NONE, pe) }
        node(p, pid).op = ast.M_INIT
        let member_start = p.tok.start
        if is_p(p, "...") {
            try adv(p)
            let v = try parse_assign(p)
            node(p, pid).op = ast.M_SPREAD
            node(p, pid).b = v
            if is_p(p, ",") { node(p, pid).c = 1u32 }
        } else {
            var is_async = false
            var is_gen = false
            var kind = ast.M_INIT
            // Modifiers: async, *, get, set — only when followed by a property key rather than `,` `:` `(` `}` `=`.
            if is_k(p, "async") {
                let nx = try peek(p)
                if !nx.nl && !(nx.kind == lex.T_PUNCT && (str.eq(nx.text, ",") || str.eq(nx.text, ":") || str.eq(nx.text, "(") || str.eq(nx.text, "}") || str.eq(nx.text, "="))) {
                    try adv(p)
                    is_async = true
                }
            }
            if is_p(p, "*") {
                try adv(p)
                is_gen = true
            }
            if (is_k(p, "get") || is_k(p, "set")) && !is_async && !is_gen {
                let nx2 = try peek(p)
                if !(nx2.kind == lex.T_PUNCT && (str.eq(nx2.text, ",") || str.eq(nx2.text, ":") || str.eq(nx2.text, "(") || str.eq(nx2.text, "}") || str.eq(nx2.text, "="))) {
                    if is_k(p, "get") { kind = 20u8 } else { kind = 21u8 }
                    try adv(p)
                }
            }
            let key_tok = p.tok
            let (key, key_computed) = try parse_property_key(p)
            node(p, pid).a = key
            if key_computed { node(p, pid).flags = node(p, pid).flags | ast.F_COMPUTED }
            if kind != ast.M_INIT || is_async || is_gen || is_p(p, "(") {
                var mf = 0u16
                if is_async { mf = mf | ast.F_ASYNC }
                if is_gen { mf = mf | ast.F_GENERATOR }
                if p.strict { mf = mf | ast.F_STRICT }
                var name = ""
                if !key_computed { name = key_name(p, key) }
                let f = try parse_method(p, name, mf, member_start)
                node(p, pid).b = f
                if kind == 20u8 { node(p, pid).op = ast.M_GET } else if kind == 21u8 { node(p, pid).op = ast.M_SET } else { node(p, pid).op = ast.M_METHOD }
            } else if is_p(p, ":") {
                try adv(p)
                let v2 = try parse_assign(p)
                node(p, pid).b = v2
            } else {
                // Shorthand `x` or `x = default` (cover grammar).
                if key_tok.kind != lex.T_IDENT { ret (ast.NONE, fail(p, "unexpected token in object literal")) }
                let (vid, ve) = mk(p, ast.N_IDENT)
                if ve != ok { ret (ast.NONE, ve) }
                node(p, vid).text = key_tok.text
                if str.eq(key_tok.text, "arguments") { p.uses_args = true }
                node(p, pid).flags = node(p, pid).flags | ast.F_SHORTHAND
                if is_p(p, "=") {
                    try adv(p)
                    let dflt = try parse_assign(p)
                    let (aid, ae) = mk(p, ast.N_ASSIGN)
                    if ae != ok { ret (ast.NONE, ae) }
                    node(p, aid).op = ast.O_ASSIGN
                    node(p, aid).a = vid
                    node(p, aid).b = dflt
                    node(p, aid).flags = ast.F_COVER_INIT
                    node(p, pid).b = aid
                } else {
                    node(p, pid).b = vid
                }
            }
        }
        try list.push[u32](&ids, pid)
        if !is_p(p, "}") { try expect_p(p, ",") }
    }
    p.no_in = saved
    try adv(p)
    let (first, ce) = commit(p, &ids)
    if ce != ok { ret (ast.NONE, ce) }
    node(p, id).a = first
    node(p, id).b = u32(ids.len)
    ret (id, ok)
}

fn key_name(p: *const Parser, key: u32) -> str {
    let n = p.nodes.items[usize(key)]
    if n.kind == ast.N_STR || n.kind == ast.N_PRIVATE { ret n.text }
    ret ""
}

fn parse_array(p: *Parser) -> (u32, err) {
    let (id, me) = mk(p, ast.N_ARRAY)
    if me != ok { ret (ast.NONE, me) }
    try expect_p(p, "[")
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    let saved = p.no_in
    p.no_in = false
    while !is_p(p, "]") {
        if is_p(p, ",") {
            let (hid, he) = mk(p, ast.N_HOLE)
            if he != ok { ret (ast.NONE, he) }
            try list.push[u32](&ids, hid)
            try adv(p)
        } else {
            if is_p(p, "...") {
                let (sid, se) = mk(p, ast.N_SPREAD)
                if se != ok { ret (ast.NONE, se) }
                try adv(p)
                let v = try parse_assign(p)
                node(p, sid).a = v
                try list.push[u32](&ids, sid)
                if is_p(p, ",") { node(p, sid).c = 1u32 }
            } else {
                let v2 = try parse_assign(p)
                try list.push[u32](&ids, v2)
            }
            if !is_p(p, "]") { try expect_p(p, ",") }
        }
    }
    p.no_in = saved
    try adv(p)
    let (first, ce) = commit(p, &ids)
    if ce != ok { ret (ast.NONE, ce) }
    node(p, id).a = first
    node(p, id).b = u32(ids.len)
    ret (id, ok)
}

fn parse_primary(p: *Parser) -> (u32, err) {
    if is_p(p, "@") {
        let (pdf, pdc) = try parse_decorators(p)
        if !is_k(p, "class") { ret (ast.NONE, fail(p, "decorators must precede a class")) }
        let dc = try parse_class(p, false, pdf, pdc)
        ret (dc, ok)
    }
    let t = p.tok
    if t.kind == lex.T_NUM {
        var kind = ast.N_NUM
        if t.big { kind = ast.N_BIGINT }
        let (id, me) = mk(p, kind)
        if me != ok { ret (ast.NONE, me) }
        node(p, id).num = t.num
        if t.big { node(p, id).text = p.lx.src[t.start..t.end] }
        if t.legacy_octal && p.strict { ret (ast.NONE, fail(p, "octal literal in strict mode")) }
        try adv(p)
        ret (id, ok)
    }
    if t.kind == lex.T_STR {
        let (id2, me2) = mk(p, ast.N_STR)
        if me2 != ok { ret (ast.NONE, me2) }
        node(p, id2).text = t.text
        if t.legacy_octal && p.strict { ret (ast.NONE, fail(p, "octal escape in strict mode")) }
        try adv(p)
        ret (id2, ok)
    }
    if t.kind == lex.T_TEMPLATE {
        let id3 = try parse_template(p)
        ret (id3, ok)
    }
    if t.kind == lex.T_PUNCT {
        if str.eq(t.text, "(") {
            try adv(p)
            let saved = p.no_in
            p.no_in = false
            let e = try parse_expression(p)
            p.no_in = saved
            try expect_p(p, ")")
            // A parenthesised object or array literal is no longer a destructuring pattern; `op` = 1 marks it for the early
            // error pass (a name or member stays assignable and needs no mark).
            let ek = node(p, e).kind
            if ek == ast.N_ARRAY || ek == ast.N_OBJECT { node(p, e).op = 1u8 }
            // A parenthesised name assigned to takes no inferred function name: `d` = 1 marks it.
            if ek == ast.N_IDENT { node(p, e).d = 1u32 }
            try list.push[u32](&p.parens, e)
            ret (e, ok)
        }
        if str.eq(t.text, "[") {
            let a = try parse_array(p)
            ret (a, ok)
        }
        if str.eq(t.text, "{") {
            let o = try parse_object(p)
            ret (o, ok)
        }
        if str.eq(t.text, "/") || str.eq(t.text, "/=") {
            let (rt, re) = lex.regex_at(&p.lx, t.start)
            if re != ok {
                p.message = p.lx.message
                ret (ast.NONE, re)
            }
            let (id4, me4) = mk(p, ast.N_REGEX)
            if me4 != ok { ret (ast.NONE, me4) }
            node(p, id4).text = rt.text
            node(p, id4).text2 = rt.flags
            p.tok = rt
            try adv(p)
            ret (id4, ok)
        }
        ret (ast.NONE, fail(p, "unexpected token"))
    }
    if t.kind == lex.T_IDENT {
        if !t.escaped {
            let w = t.text
            if str.eq(w, "function") {
                let f = try parse_function(p, false, false)
                ret (f, ok)
            }
            if str.eq(w, "class") {
                let c = try parse_class(p, false, 0u32, 0u32)
                ret (c, ok)
            }
            if str.eq(w, "this") {
                let (id5, me5) = mk(p, ast.N_THIS)
                if me5 != ok { ret (ast.NONE, me5) }
                try adv(p)
                ret (id5, ok)
            }
            if str.eq(w, "null") || str.eq(w, "true") || str.eq(w, "false") {
                var k5 = ast.N_NULL
                if str.eq(w, "true") { k5 = ast.N_TRUE }
                if str.eq(w, "false") { k5 = ast.N_FALSE }
                let (id6, me6) = mk(p, k5)
                if me6 != ok { ret (ast.NONE, me6) }
                try adv(p)
                ret (id6, ok)
            }
            if str.eq(w, "async") {
                let nx = try peek(p)
                if nx.kind == lex.T_IDENT && str.eq(nx.text, "function") && !nx.nl {
                    try adv(p)
                    let af = try parse_function(p, false, true)
                    ret (af, ok)
                }
            }
            if str.eq(w, "super") {
                let (id7, me7) = mk(p, ast.N_SUPER)
                if me7 != ok { ret (ast.NONE, me7) }
                try adv(p)
                ret (id7, ok)
            }
            if is_reserved(w) { ret (ast.NONE, fail(p, "unexpected reserved word")) }
        }
        let (id8, me8) = mk(p, ast.N_IDENT)
        if me8 != ok { ret (ast.NONE, me8) }
        node(p, id8).text = t.text
        if str.eq(t.text, "arguments") { p.uses_args = true }
        try adv(p)
        ret (id8, ok)
    }
    ret (ast.NONE, fail(p, "unexpected token"))
}

// Member expressions and calls: `a.b`, `a[b]`, `a(b)`, `a?.b`, tagged templates, `new`.
fn parse_lhs(p: *Parser) -> (u32, err) {
    var e: u32 = ast.NONE
    if is_k(p, "new") {
        e = try parse_new(p)
    } else if is_k(p, "import") {
        e = try parse_import(p)
    } else {
        e = try parse_primary(p)
    }
    var optional = false
    while true {
        if is_p(p, ".") {
            try adv(p)
            let (id, me) = mk(p, ast.N_MEMBER)
            if me != ok { ret (ast.NONE, me) }
            node(p, id).a = e
            if p.tok.kind == lex.T_PRIVATE {
                let (pid, pe) = mk(p, ast.N_PRIVATE)
                if pe != ok { ret (ast.NONE, pe) }
                node(p, pid).text = p.tok.text
                node(p, id).b = pid
            } else if p.tok.kind == lex.T_IDENT {
                node(p, id).text = p.tok.text
            } else {
                ret (ast.NONE, fail(p, "expected a property name"))
            }
            try adv(p)
            e = id
        } else if is_p(p, "?.") {
            optional = true
            try adv(p)
            if is_p(p, "(") {
                let args = try parse_arguments(p)
                let (cid, ce) = mk(p, ast.N_CALL)
                if ce != ok { ret (ast.NONE, ce) }
                let (first, ke) = commit(p, &args)
                if ke != ok { ret (ast.NONE, ke) }
                node(p, cid).a = e
                node(p, cid).b = first
                node(p, cid).c = u32(args.len)
                node(p, cid).flags = ast.F_OPTIONAL
                e = cid
            } else if is_p(p, "[") {
                try adv(p)
                let saved = p.no_in
                p.no_in = false
                let idx = try parse_expression(p)
                p.no_in = saved
                try expect_p(p, "]")
                let (mid, mie) = mk(p, ast.N_MEMBER)
                if mie != ok { ret (ast.NONE, mie) }
                node(p, mid).a = e
                node(p, mid).b = idx
                node(p, mid).flags = ast.F_COMPUTED | ast.F_OPTIONAL
                e = mid
            } else {
                let (mid2, mie2) = mk(p, ast.N_MEMBER)
                if mie2 != ok { ret (ast.NONE, mie2) }
                node(p, mid2).a = e
                node(p, mid2).flags = ast.F_OPTIONAL
                if p.tok.kind == lex.T_PRIVATE {
                    let (pid2, pe2) = mk(p, ast.N_PRIVATE)
                    if pe2 != ok { ret (ast.NONE, pe2) }
                    node(p, pid2).text = p.tok.text
                    node(p, mid2).b = pid2
                } else if p.tok.kind == lex.T_IDENT {
                    node(p, mid2).text = p.tok.text
                } else {
                    ret (ast.NONE, fail(p, "expected a property name"))
                }
                try adv(p)
                e = mid2
            }
        } else if is_p(p, "[") {
            try adv(p)
            let saved2 = p.no_in
            p.no_in = false
            let idx2 = try parse_expression(p)
            p.no_in = saved2
            try expect_p(p, "]")
            let (mid3, mie3) = mk(p, ast.N_MEMBER)
            if mie3 != ok { ret (ast.NONE, mie3) }
            node(p, mid3).a = e
            node(p, mid3).b = idx2
            node(p, mid3).flags = ast.F_COMPUTED
            e = mid3
        } else if is_p(p, "(") {
            let args2 = try parse_arguments(p)
            let (cid2, ce2) = mk(p, ast.N_CALL)
            if ce2 != ok { ret (ast.NONE, ce2) }
            let (first2, ke2) = commit(p, &args2)
            if ke2 != ok { ret (ast.NONE, ke2) }
            node(p, cid2).a = e
            node(p, cid2).b = first2
            node(p, cid2).c = u32(args2.len)
            e = cid2
        } else if p.tok.kind == lex.T_TEMPLATE {
            if optional { ret (ast.NONE, fail(p, "Invalid tagged template on optional chain")) }
            let tpl = try parse_template(p)
            let (tid, te) = mk(p, ast.N_TAGGED)
            if te != ok { ret (ast.NONE, te) }
            node(p, tid).a = e
            node(p, tid).b = tpl
            e = tid
        } else {
            break
        }
    }
    if optional {
        let (oid, oe) = mk(p, ast.N_OPTCHAIN)
        if oe != ok { ret (ast.NONE, oe) }
        node(p, oid).a = e
        e = oid
    }
    ret (e, ok)
}

fn parse_new(p: *Parser) -> (u32, err) {
    try adv(p)
    if is_p(p, ".") {
        try adv(p)
        if !is_k(p, "target") { ret (ast.NONE, fail(p, "expected new.target")) }
        try adv(p)
        let (id, me) = mk(p, ast.N_NEWTARGET)
        if me != ok { ret (ast.NONE, me) }
        ret (id, ok)
    }
    // The callee is a member expression without calls.
    var callee: u32 = ast.NONE
    if is_k(p, "new") {
        callee = try parse_new(p)
    } else if is_k(p, "import") {
        callee = try parse_import(p)
        if p.nodes.items[usize(callee)].kind == ast.N_IMPORT_CALL { ret (ast.NONE, fail(p, "cannot use new with import()")) }
    } else {
        callee = try parse_primary(p)
    }
    while true {
        if is_p(p, ".") {
            try adv(p)
            let (mid, me2) = mk(p, ast.N_MEMBER)
            if me2 != ok { ret (ast.NONE, me2) }
            node(p, mid).a = callee
            if p.tok.kind == lex.T_PRIVATE {
                let (pid, pe) = mk(p, ast.N_PRIVATE)
                if pe != ok { ret (ast.NONE, pe) }
                node(p, pid).text = p.tok.text
                node(p, mid).b = pid
            } else if p.tok.kind == lex.T_IDENT {
                node(p, mid).text = p.tok.text
            } else {
                ret (ast.NONE, fail(p, "expected a property name"))
            }
            try adv(p)
            callee = mid
        } else if is_p(p, "[") {
            try adv(p)
            let idx = try parse_expression(p)
            try expect_p(p, "]")
            let (mid2, me3) = mk(p, ast.N_MEMBER)
            if me3 != ok { ret (ast.NONE, me3) }
            node(p, mid2).a = callee
            node(p, mid2).b = idx
            node(p, mid2).flags = ast.F_COMPUTED
            callee = mid2
        } else {
            break
        }
    }
    let (nid, ne) = mk(p, ast.N_NEW)
    if ne != ok { ret (ast.NONE, ne) }
    node(p, nid).a = callee
    node(p, nid).b = 0u32
    node(p, nid).c = 0u32
    if is_p(p, "(") {
        let args = try parse_arguments(p)
        let (first, ke) = commit(p, &args)
        if ke != ok { ret (ast.NONE, ke) }
        node(p, nid).b = first
        node(p, nid).c = u32(args.len)
    }
    ret (nid, ok)
}

fn parse_import(p: *Parser) -> (u32, err) {
    try adv(p)
    var phase = 0u32
    if is_p(p, ".") {
        try adv(p)
        if is_k(p, "defer") || is_k(p, "source") {
            if is_k(p, "defer") { phase = 1u32 } else { phase = 2u32 }
            try adv(p)
            if !is_p(p, "(") { ret (ast.NONE, fail(p, "import.defer and import.source must be called")) }
        } else {
        if !is_k(p, "meta") { ret (ast.NONE, fail(p, "expected import.meta")) }
        if !p.module { ret (ast.NONE, fail(p, "import.meta is only valid in modules")) }
        try adv(p)
        let (id, me) = mk(p, ast.N_IMPORT_META)
        if me != ok { ret (ast.NONE, me) }
        ret (id, ok)
        }
    }
    if !is_p(p, "(") { ret (ast.NONE, fail(p, "unexpected import")) }
    let args = try parse_arguments(p)
    if args.len == 0usize || args.len > 2usize { ret (ast.NONE, fail(p, "import() takes one or two arguments")) }
    var ai = 0usize
    while ai < args.len {
        if p.nodes.items[usize(args.items[ai])].kind == ast.N_SPREAD { ret (ast.NONE, fail(p, "import() does not take spread arguments")) }
        ai += 1usize
    }
    let (id2, me2) = mk(p, ast.N_IMPORT_CALL)
    if me2 != ok { ret (ast.NONE, me2) }
    let (first, ke) = commit(p, &args)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, id2).a = phase
    node(p, id2).b = first
    node(p, id2).c = u32(args.len)
    ret (id2, ok)
}

// --- functions and classes

// Binding patterns for parameters and declarations use the expression forms.
fn parse_binding_element(p: *Parser) -> (u32, err) {
    var tgt: u32 = ast.NONE
    if is_p(p, "[") {
        tgt = try parse_array(p)
    } else if is_p(p, "{") {
        tgt = try parse_object(p)
    } else if p.tok.kind == lex.T_IDENT {
        let (id, me) = mk(p, ast.N_IDENT)
        if me != ok { ret (ast.NONE, me) }
        node(p, id).text = p.tok.text
        if str.eq(p.tok.text, "arguments") { p.uses_args = true }
        try adv(p)
        tgt = id
    } else {
        ret (ast.NONE, fail(p, "expected a binding"))
    }
    if is_p(p, "=") {
        try adv(p)
        let saved = p.no_in
        p.no_in = false
        let dflt = try parse_assign(p)
        p.no_in = saved
        let (aid, ae) = mk(p, ast.N_ASSIGN)
        if ae != ok { ret (ast.NONE, ae) }
        node(p, aid).op = ast.O_ASSIGN
        node(p, aid).a = tgt
        node(p, aid).b = dflt
        ret (aid, ok)
    }
    ret (tgt, ok)
}

fn parse_params(p: *Parser) -> (list.List[u32], err) {
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ids, ie) }
    try expect_p(p, "(")
    while !is_p(p, ")") {
        if is_p(p, "...") {
            let (sid, se) = mk(p, ast.N_SPREAD)
            if se != ok { ret (ids, se) }
            try adv(p)
            let tgt = try parse_binding_element(p)
            node(p, sid).a = tgt
            try list.push[u32](&ids, sid)
            if is_p(p, ",") { ret (ids, fail(p, "Rest parameter must be last formal parameter")) }
        } else {
            let el = try parse_binding_element(p)
            try list.push[u32](&ids, el)
        }
        if !is_p(p, ")") { try expect_p(p, ",") }
    }
    try adv(p)
    ret (ids, ok)
}

// Statements of a function body or program up to `end` (`}` or EOF), with the directive prologue.
fn parse_statements(p: *Parser, closing: bool, ids: *list.List[u32]) -> err {
    var prologue = true
    var octal_directive = false
    while true {
        if closing && is_p(p, "}") { break }
        if !closing && p.tok.kind == lex.T_EOF { break }
        if p.tok.kind == lex.T_EOF { ret fail(p, "unexpected end of input") }
        if prologue {
            if p.tok.kind == lex.T_STR {
                let raw = p.lx.src[p.tok.start..p.tok.end]
                if p.tok.legacy_octal { octal_directive = true }
                if raw.len == 12usize && (str.eq(raw, "\"use strict\"") || str.eq(raw, "'use strict'")) {
                    if octal_directive { ret fail(p, "octal escape in a directive before use strict") }
                    p.strict = true
                }
            } else {
                prologue = false
            }
        }
        var s: u32 = ast.NONE
        var handled = false
        if p.module && !closing && p.tok.kind == lex.T_IDENT && !p.tok.escaped {
            if str.eq(p.tok.text, "import") {
                let nx0 = try peek(p)
                if !(nx0.kind == lex.T_PUNCT && (str.eq(nx0.text, "(") || str.eq(nx0.text, "."))) {
                    s = try parse_import_decl(p)
                    handled = true
                }
            } else if str.eq(p.tok.text, "export") {
                s = try parse_export_decl(p)
                handled = true
            }
        }
        if !handled { s = try parse_statement(p) }
        try list.push[u32](ids, s)
        if prologue {
            let k = p.nodes.items[usize(s)].kind
            if k != ast.N_EXPR_STMT { prologue = false }
        }
    }
    ret ok
}

fn parse_function_body(p: *Parser, fid: u32) -> (u32, err) {
    let (bid, be) = mk(p, ast.N_BLOCK)
    if be != ok { ret (ast.NONE, be) }
    try expect_p(p, "{")
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    let saved_strict = p.strict
    try parse_statements(p, true, &ids)
    if p.strict { node(p, fid).flags = node(p, fid).flags | ast.F_STRICT }
    p.strict = saved_strict
    try expect_p(p, "}")
    let (first, ce) = commit(p, &ids)
    if ce != ok { ret (ast.NONE, ce) }
    node(p, bid).a = first
    node(p, bid).b = u32(ids.len)
    ret (bid, ok)
}

// `(params) { body }` of a function whose node `fid` already carries name and flags.
fn parse_function_rest(p: *Parser, fid: u32) -> err {
    let saved_async = p.in_async
    let saved_gen = p.in_generator
    let saved_fn = p.in_function
    let saved_args = p.uses_args
    let saved_no_in = p.no_in
    let saved_vars = p.vars.len
    let saved_blk = p.blk
    p.blk = 0u32
    let fl = node(p, fid).flags
    p.in_async = (fl & ast.F_ASYNC) != 0u16
    p.in_generator = (fl & ast.F_GENERATOR) != 0u16
    p.in_function = true
    p.uses_args = false
    p.no_in = false
    let params = try parse_params(p)
    let (k, ke) = commit(p, &params)
    if ke != ok { ret ke }
    node(p, fid).a = k
    node(p, fid).b = u32(params.len)
    node(p, fid).num = f64(arity(p, &params))
    let body = try parse_function_body(p, fid)
    node(p, fid).c = body
    if p.uses_args { node(p, fid).flags = node(p, fid).flags | ast.F_USES_ARGS }
    close_hoist(p, fid, saved_vars)
    p.blk = saved_blk
    p.in_async = saved_async
    p.in_generator = saved_gen
    p.in_function = saved_fn
    p.uses_args = saved_args
    p.no_in = saved_no_in
    ret ok
}

// `function [*] [name] (...) {...}`; the current token is `function`.
fn parse_function(p: *Parser, decl: bool, is_async: bool) -> (u32, err) {
    let (fid, fe) = mk(p, ast.N_FUNC)
    if fe != ok { ret (ast.NONE, fe) }
    var fn_start = p.tok.start
    if is_async { fn_start = p.prev_start }
    try expect_k(p, "function")
    var fl = 0u16
    if is_async { fl = fl | ast.F_ASYNC }
    if is_p(p, "*") {
        try adv(p)
        fl = fl | ast.F_GENERATOR
    }
    if decl { fl = fl | ast.F_DECL }
    if p.strict { fl = fl | ast.F_STRICT }
    node(p, fid).flags = fl
    if p.tok.kind == lex.T_IDENT && !is_p(p, "(") {
        node(p, fid).text = p.tok.text
        try adv(p)
    } else if decl && p.anon_default {
        node(p, fid).text = "*default*"
        p.anon_default = false
    } else if decl {
        ret (ast.NONE, fail(p, "function declaration needs a name"))
    }
    try parse_function_rest(p, fid)
    node(p, fid).text2 = p.lx.src[fn_start..p.prev_end]
    // Annex B.3.3: a plain function declaration in a sloppy block also declares a `var` of the same name.
    if decl && !p.strict && p.blk > 0u32 && (fl & (ast.F_ASYNC | ast.F_GENERATOR)) == 0u16 {
        node(p, fid).op = 1u8
        try list.push[u32](&p.vars, fid)
    }
    ret (fid, ok)
}

// `@expr` decorators: the expressions as a run of the shared child list (first index, count).
fn parse_decorators(p: *Parser) -> (u32, u32, err) {
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (0u32, 0u32, ie) }
    while is_p(p, "@") {
        try adv(p)
        let dec = try parse_lhs(p)
        try list.push[u32](&ids, dec)
    }
    if ids.len == 0usize { ret (0u32, 0u32, ok) }
    let (first, ke) = commit(p, &ids)
    if ke != ok { ret (0u32, 0u32, ke) }
    ret (first, u32(ids.len), ok)
}

fn parse_class(p: *Parser, decl: bool, dfirst: u32, dcount: u32) -> (u32, err) {
    let (cid, ce) = mk(p, ast.N_CLASS)
    if ce != ok { ret (ast.NONE, ce) }
    node(p, cid).hoist_first = dfirst
    node(p, cid).hoist_count = dcount
    let class_start = p.tok.start
    try expect_k(p, "class")
    if decl { node(p, cid).flags = ast.F_DECL }
    let saved_strict = p.strict
    p.strict = true
    if p.tok.kind == lex.T_IDENT && !is_k(p, "extends") {
        node(p, cid).text = p.tok.text
        try adv(p)
    } else if decl && p.anon_default {
        node(p, cid).text = "*default*"
        p.anon_default = false
    } else if decl {
        ret (ast.NONE, fail(p, "class declaration needs a name"))
    }
    if is_k(p, "extends") {
        try adv(p)
        let sup = try parse_lhs(p)
        node(p, cid).a = sup
        node(p, cid).flags = node(p, cid).flags | ast.F_DERIVED
    }
    try expect_p(p, "{")
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    while !is_p(p, "}") {
        if is_p(p, ";") {
            try adv(p)
            continue
        }
        let (mdf, mdc) = try parse_decorators(p)
        let (mid, me) = mk(p, ast.N_PROP)
        if me != ok { ret (ast.NONE, me) }
        node(p, mid).hoist_first = mdf
        node(p, mid).hoist_count = mdc
        var is_static = false
        if is_k(p, "static") {
            let nx = try peek(p)
            if !(nx.kind == lex.T_PUNCT && (str.eq(nx.text, "(") || str.eq(nx.text, "=") || str.eq(nx.text, ";") || str.eq(nx.text, "}"))) {
                try adv(p)
                is_static = true
            }
        }
        if is_static { node(p, mid).flags = ast.F_STATIC }
        if is_static && is_p(p, "{") {
            // Static initialisation block: a function body run with `this` the class.
            let (fid, fe) = mk(p, ast.N_FUNC)
            if fe != ok { ret (ast.NONE, fe) }
            node(p, fid).flags = ast.F_METHOD | ast.F_STRICT
            node(p, fid).a = 0u32
            node(p, fid).b = 0u32
            let saved_vars = p.vars.len
            let saved_fn = p.in_function
            p.in_function = true
            let body = try parse_function_body(p, fid)
            p.in_function = saved_fn
            node(p, fid).c = body
            close_hoist(p, fid, saved_vars)
            node(p, mid).op = ast.M_STATIC_BLOCK
            node(p, mid).b = fid
            try list.push[u32](&ids, mid)
            continue
        }
        let member_start2 = p.tok.start
        var is_async = false
        var is_gen = false
        var kind = ast.M_METHOD
        if is_k(p, "async") {
            let nx2 = try peek(p)
            if !nx2.nl && !(nx2.kind == lex.T_PUNCT && (str.eq(nx2.text, "(") || str.eq(nx2.text, "=") || str.eq(nx2.text, ";") || str.eq(nx2.text, "}"))) {
                try adv(p)
                is_async = true
            }
        }
        if is_p(p, "*") {
            try adv(p)
            is_gen = true
        }
        var is_auto = false
        if is_k(p, "accessor") && !is_async && !is_gen {
            let nx4 = try peek(p)
            if !nx4.nl && !(nx4.kind == lex.T_PUNCT && (str.eq(nx4.text, "(") || str.eq(nx4.text, "=") || str.eq(nx4.text, ";") || str.eq(nx4.text, "}"))) {
                try adv(p)
                is_auto = true
            }
        }
        var accessor = 0u8
        if !is_auto && (is_k(p, "get") || is_k(p, "set")) && !is_async && !is_gen {
            let nx3 = try peek(p)
            if !(nx3.kind == lex.T_PUNCT && (str.eq(nx3.text, "(") || str.eq(nx3.text, "=") || str.eq(nx3.text, ";") || str.eq(nx3.text, "}") || (nx3.nl && str.eq(nx3.text, "*")))) {
                if is_k(p, "get") { accessor = 1u8 } else { accessor = 2u8 }
                try adv(p)
            }
        }
        let (key, key_computed) = try parse_property_key(p)
        node(p, mid).a = key
        if key_computed { node(p, mid).flags = node(p, mid).flags | ast.F_COMPUTED }
        if is_p(p, "(") {
            var mf = ast.F_STRICT
            if is_async { mf = mf | ast.F_ASYNC }
            if is_gen { mf = mf | ast.F_GENERATOR }
            var name = ""
            if !key_computed { name = key_name(p, key) }
            let f = try parse_method(p, name, mf, member_start2)
            node(p, mid).b = f
            if accessor == 1u8 { kind = ast.M_GET } else if accessor == 2u8 { kind = ast.M_SET }
            node(p, mid).op = kind
        } else {
            // A field: `key [= value] ;` — the initialiser runs as a method with `this` the instance.
            node(p, mid).op = ast.M_FIELD
            if is_auto { node(p, mid).c = 1u32 }
            if is_p(p, "=") {
                try adv(p)
                let (fid2, fe2) = mk(p, ast.N_FUNC)
                if fe2 != ok { ret (ast.NONE, fe2) }
                node(p, fid2).flags = ast.F_METHOD | ast.F_STRICT | ast.F_ARROW | ast.F_EXPR_BODY
                node(p, fid2).a = 0u32
                node(p, fid2).b = 0u32
                let saved_fn2 = p.in_function
                let saved_vars2 = p.vars.len
                p.in_function = true
                let saved_args = p.uses_args
                let init = try parse_assign(p)
                p.uses_args = saved_args
                p.in_function = saved_fn2
                node(p, fid2).c = init
                close_hoist(p, fid2, saved_vars2)
                node(p, mid).b = fid2
            }
            if is_p(p, ";") {
                try adv(p)
            } else if !is_p(p, "}") && !p.tok.nl {
                ret (ast.NONE, fail(p, "expected ; after a class field"))
            }
        }
        try list.push[u32](&ids, mid)
    }
    try adv(p)
    p.strict = saved_strict
    node(p, cid).text2 = p.lx.src[class_start..p.prev_end]
    let (first, ke) = commit(p, &ids)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, cid).b = first
    node(p, cid).c = u32(ids.len)
    ret (cid, ok)
}

// --- statements

fn consume_semi(p: *Parser) -> err {
    if is_p(p, ";") { ret adv(p) }
    if is_p(p, "}") || p.tok.kind == lex.T_EOF || p.tok.nl { ret ok }
    ret fail(p, "expected ;")
}

fn parse_block(p: *Parser) -> (u32, err) {
    let (id, me) = mk(p, ast.N_BLOCK)
    if me != ok { ret (ast.NONE, me) }
    try expect_p(p, "{")
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    p.blk += 1u32
    while !is_p(p, "}") {
        if p.tok.kind == lex.T_EOF { ret (ast.NONE, fail(p, "unexpected end of input")) }
        let s = try parse_statement(p)
        try list.push[u32](&ids, s)
    }
    p.blk -= 1u32
    try adv(p)
    let (first, ke) = commit(p, &ids)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, id).a = first
    node(p, id).b = u32(ids.len)
    ret (id, ok)
}

// `var`/`let`/`const` declarations; the current token is the keyword. `for_head` stops before `in`/`of`/`;`.
fn parse_var(p: *Parser, for_head: bool) -> (u32, err) {
    let (id, me) = mk(p, ast.N_VAR)
    if me != ok { ret (ast.NONE, me) }
    var kind = ast.D_VAR
    if is_k(p, "let") { kind = ast.D_LET }
    if is_k(p, "const") { kind = ast.D_CONST }
    node(p, id).op = kind
    try adv(p)
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    while true {
        let (did, de) = mk(p, ast.N_DECL)
        if de != ok { ret (ast.NONE, de) }
        var tgt: u32 = ast.NONE
        if is_p(p, "[") {
            tgt = try parse_array(p)
        } else if is_p(p, "{") {
            tgt = try parse_object(p)
        } else if p.tok.kind == lex.T_IDENT {
            let (nid, ne) = mk(p, ast.N_IDENT)
            if ne != ok { ret (ast.NONE, ne) }
            node(p, nid).text = p.tok.text
            if str.eq(p.tok.text, "arguments") { p.uses_args = true }
            try adv(p)
            tgt = nid
        } else {
            ret (ast.NONE, fail(p, "expected a variable name"))
        }
        node(p, did).a = tgt
        if is_p(p, "=") {
            try adv(p)
            let init = try parse_assign(p)
            node(p, did).b = init
        }
        if kind == ast.D_VAR { try collect_names(p, tgt) }
        try list.push[u32](&ids, did)
        if is_p(p, ",") {
            try adv(p)
        } else {
            break
        }
    }
    let (first, ke) = commit(p, &ids)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, id).a = first
    node(p, id).b = u32(ids.len)
    ret (id, ok)
}

// Whether the current token starts a `using` (1) or `await using` (2) declaration, or neither (0). The name must follow on the same line.
fn using_ahead(p: *Parser, for_head: bool) -> (u8, err) {
    if p.tok.kind != lex.T_IDENT || p.tok.escaped { ret (0u8, ok) }
    if str.eq(p.tok.text, "using") {
        let t1 = try peek(p)
        if t1.kind != lex.T_IDENT || t1.nl || is_reserved(t1.text) { ret (0u8, ok) }
        if for_head && str.eq(t1.text, "of") {
            // `for (using of = ...;;)` declares `of`; any other `using of` in a head is the identifier `using` then the for-of keyword.
            let m1 = mark(p)
            try adv(p)
            try adv(p)
            let t3 = p.tok
            restore(p, m1)
            if t3.kind == lex.T_PUNCT && str.eq(t3.text, "=") { ret (1u8, ok) }
            ret (0u8, ok)
        }
        ret (1u8, ok)
    }
    if str.eq(p.tok.text, "await") && (p.in_async || (p.module && !p.in_function)) {
        let t1 = try peek(p)
        if t1.kind != lex.T_IDENT || t1.nl || t1.escaped || !str.eq(t1.text, "using") { ret (0u8, ok) }
        let m = mark(p)
        try adv(p)
        try adv(p)
        let t2 = p.tok
        restore(p, m)
        if t2.kind != lex.T_IDENT || t2.nl || is_reserved(t2.text) { ret (0u8, ok) }
        ret (2u8, ok)
    }
    ret (0u8, ok)
}

fn parse_using(p: *Parser, kind: u8) -> (u32, err) {
    let (id, me) = mk(p, ast.N_VAR)
    if me != ok { ret (ast.NONE, me) }
    node(p, id).op = ast.D_CONST
    node(p, id).flags = ast.F_USING
    if kind == 2u8 {
        node(p, id).flags = ast.F_USING | ast.F_AWAIT_USING
        if !p.in_function { p.top_await = true }
        try adv(p)
    }
    try adv(p)
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    while true {
        let (did, de) = mk(p, ast.N_DECL)
        if de != ok { ret (ast.NONE, de) }
        if p.tok.kind != lex.T_IDENT { ret (ast.NONE, fail(p, "a using declaration binds plain names")) }
        let (nid, ne) = mk(p, ast.N_IDENT)
        if ne != ok { ret (ast.NONE, ne) }
        node(p, nid).text = p.tok.text
        if str.eq(p.tok.text, "arguments") { p.uses_args = true }
        try adv(p)
        node(p, did).a = nid
        if is_p(p, "=") {
            try adv(p)
            let init = try parse_assign(p)
            node(p, did).b = init
        }
        try list.push[u32](&ids, did)
        if is_p(p, ",") {
            try adv(p)
        } else {
            break
        }
    }
    let (first, ke) = commit(p, &ids)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, id).a = first
    node(p, id).b = u32(ids.len)
    ret (id, ok)
}

fn is_let_decl(p: *Parser) -> (bool, err) {
    if !is_k(p, "let") { ret (false, ok) }
    let nx = try peek(p)
    if nx.kind == lex.T_IDENT && !str.eq(nx.text, "in") && !str.eq(nx.text, "instanceof") && !str.eq(nx.text, "of") { ret (true, ok) }
    if nx.kind == lex.T_IDENT && str.eq(nx.text, "of") { ret (true, ok) }
    if nx.kind == lex.T_PUNCT && (str.eq(nx.text, "[") || str.eq(nx.text, "{")) { ret (true, ok) }
    ret (false, ok)
}

fn parse_for(p: *Parser) -> (u32, err) {
    try adv(p)
    var is_await = false
    if is_k(p, "await") {
        try adv(p)
        is_await = true
        if !p.in_function { p.top_await = true }
    }
    try expect_p(p, "(")
    var init: u32 = ast.NONE
    let saved = p.no_in
    p.no_in = true
    var decl_kind = 0u8
    if is_p(p, ";") {
        // no init
    } else {
        let let_decl = try is_let_decl(p)
        let using_kind = try using_ahead(p, true)
        if using_kind != 0u8 {
            init = try parse_using(p, using_kind)
        } else if is_k(p, "var") || is_k(p, "const") || let_decl {
            init = try parse_var(p, true)
        } else {
            let starts_async = is_k(p, "async") && !p.tok.escaped
            init = try parse_expression(p)
            if starts_async && is_k(p, "of") && !is_await && node(p, init).kind == ast.N_IDENT && str.eq(node(p, init).text, "async") && !is_paren(p, init) { ret (ast.NONE, fail(p, "The left-hand side of a for-of loop may not be 'async'")) }
        }
    }
    p.no_in = saved
    if init != ast.NONE && (is_k(p, "of") || is_k(p, "in")) {
        let of = is_k(p, "of")
        try adv(p)
        var right: u32 = ast.NONE
        if of { right = try parse_assign(p) } else { right = try parse_expression(p) }
        try expect_p(p, ")")
        p.sub_flag = true
        let body = try parse_statement(p)
        var kind = ast.N_FORIN
        if of { kind = ast.N_FOROF }
        let (id, me) = mk(p, kind)
        if me != ok { ret (ast.NONE, me) }
        node(p, id).a = init
        node(p, id).b = right
        node(p, id).c = body
        if is_await { node(p, id).flags = ast.F_ASYNC }
        // `for (var x of ...)` hoists x.
        let ik = p.nodes.items[usize(init)]
        if ik.kind == ast.N_VAR && ik.op == ast.D_VAR {
            // already collected by parse_var
        }
        ret (id, ok)
    }
    try expect_p(p, ";")
    var test: u32 = ast.NONE
    if !is_p(p, ";") { test = try parse_expression(p) }
    try expect_p(p, ";")
    var update: u32 = ast.NONE
    if !is_p(p, ")") { update = try parse_expression(p) }
    try expect_p(p, ")")
    p.sub_flag = true
    let body2 = try parse_statement(p)
    let (id2, me2) = mk(p, ast.N_FOR)
    if me2 != ok { ret (ast.NONE, me2) }
    node(p, id2).a = init
    node(p, id2).b = test
    node(p, id2).c = update
    node(p, id2).d = body2
    ret (id2, ok)
}

// Annex B.3.4: `if (x) function f() {}` behaves as if the declaration were wrapped in a block.
fn parse_if_body(p: *Parser) -> (u32, err) {
    if !is_k(p, "function") || p.strict {
        p.sub_flag = true
        let r = try parse_statement(p)
        var inner = r
        var guard = 0u32
        while node(p, inner).kind == ast.N_LABELED && guard < 100u32 {
            inner = node(p, inner).a
            guard += 1u32
        }
        if node(p, inner).kind == ast.N_FUNC && (node(p, inner).flags & ast.F_DECL) != 0u16 { ret (ast.NONE, fail(p, "function declaration is not allowed as an if body here")) }
        ret (r, ok)
    }
    let (bid, me) = mk(p, ast.N_BLOCK)
    if me != ok { ret (ast.NONE, me) }
    let (ids_0, ie) = new_ids(p)
    var ids = ids_0
    if ie != ok { ret (ast.NONE, ie) }
    p.blk += 1u32
    let s = try parse_statement(p)
    p.blk -= 1u32
    if (node(p, s).flags & (ast.F_GENERATOR | ast.F_ASYNC)) != 0u16 { ret (ast.NONE, fail(p, "generator or async function declaration is not allowed as an if body")) }
    try list.push[u32](&ids, s)
    let (first, ke) = commit(p, &ids)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, bid).a = first
    node(p, bid).b = 1u32
    ret (bid, ok)
}

fn parse_statement(p: *Parser) -> (u32, err) {
    let sub = p.sub_flag
    p.sub_flag = false
    if is_p(p, "@") {
        let (sdf, sdc) = try parse_decorators(p)
        if !is_k(p, "class") { ret (ast.NONE, fail(p, "decorators must precede a class")) }
        let dc2 = try parse_class(p, true, sdf, sdc)
        ret (dc2, ok)
    }
    if p.tok.kind == lex.T_PUNCT {
        if is_p(p, "{") {
            let b = try parse_block(p)
            ret (b, ok)
        }
        if is_p(p, ";") {
            let (id, me) = mk(p, ast.N_EMPTY)
            if me != ok { ret (ast.NONE, me) }
            try adv(p)
            ret (id, ok)
        }
    } else if p.tok.kind == lex.T_IDENT && !p.tok.escaped {
        let w = p.tok.text
        if str.eq(w, "var") || str.eq(w, "const") {
            let v = try parse_var(p, false)
            try consume_semi(p)
            ret (v, ok)
        }
        if str.eq(w, "let") {
            var ld = try is_let_decl(p)
            if ld && sub {
                // In a single-statement position `let` followed by a line break and no `[` is an identifier (ASI applies).
                let lnx = try peek(p)
                if lnx.nl && !(lnx.kind == lex.T_PUNCT && str.eq(lnx.text, "[")) { ld = false }
            }
            if ld {
                let v2 = try parse_var(p, false)
                try consume_semi(p)
                ret (v2, ok)
            }
        }
        if str.eq(w, "using") || str.eq(w, "await") {
            let using_kind = try using_ahead(p, false)
            if using_kind != 0u8 {
                let v3 = try parse_using(p, using_kind)
                try consume_semi(p)
                ret (v3, ok)
            }
        }
        if str.eq(w, "function") {
            let f = try parse_function(p, true, false)
            ret (f, ok)
        }
        if str.eq(w, "async") {
            let nx = try peek(p)
            if nx.kind == lex.T_IDENT && str.eq(nx.text, "function") && !nx.nl {
                try adv(p)
                let af = try parse_function(p, true, true)
                ret (af, ok)
            }
        }
        if str.eq(w, "class") {
            let c = try parse_class(p, true, 0u32, 0u32)
            ret (c, ok)
        }
        if str.eq(w, "if") {
            let (id2, me2) = mk(p, ast.N_IF)
            if me2 != ok { ret (ast.NONE, me2) }
            try adv(p)
            try expect_p(p, "(")
            let test = try parse_expression(p)
            try expect_p(p, ")")
            let yes = try parse_if_body(p)
            node(p, id2).a = test
            node(p, id2).b = yes
            if is_k(p, "else") {
                try adv(p)
                let no = try parse_if_body(p)
                node(p, id2).c = no
            }
            ret (id2, ok)
        }
        if str.eq(w, "for") {
            let fr = try parse_for(p)
            ret (fr, ok)
        }
        if str.eq(w, "while") {
            let (id3, me3) = mk(p, ast.N_WHILE)
            if me3 != ok { ret (ast.NONE, me3) }
            try adv(p)
            try expect_p(p, "(")
            let test2 = try parse_expression(p)
            try expect_p(p, ")")
            p.sub_flag = true
            let body = try parse_statement(p)
            node(p, id3).a = test2
            node(p, id3).b = body
            ret (id3, ok)
        }
        if str.eq(w, "do") {
            let (id4, me4) = mk(p, ast.N_DOWHILE)
            if me4 != ok { ret (ast.NONE, me4) }
            try adv(p)
            p.sub_flag = true
            let body2 = try parse_statement(p)
            try expect_k(p, "while")
            try expect_p(p, "(")
            let test3 = try parse_expression(p)
            try expect_p(p, ")")
            if is_p(p, ";") { try adv(p) }
            node(p, id4).a = test3
            node(p, id4).b = body2
            ret (id4, ok)
        }
        if str.eq(w, "return") {
            let (id5, me5) = mk(p, ast.N_RETURN)
            if me5 != ok { ret (ast.NONE, me5) }
            try adv(p)
            if !is_p(p, ";") && !is_p(p, "}") && p.tok.kind != lex.T_EOF && !p.tok.nl {
                let v3 = try parse_expression(p)
                node(p, id5).a = v3
            }
            try consume_semi(p)
            ret (id5, ok)
        }
        if str.eq(w, "break") || str.eq(w, "continue") {
            var kind = ast.N_BREAK
            if str.eq(w, "continue") { kind = ast.N_CONTINUE }
            let (id6, me6) = mk(p, kind)
            if me6 != ok { ret (ast.NONE, me6) }
            try adv(p)
            if p.tok.kind == lex.T_IDENT && !p.tok.nl && !is_reserved(p.tok.text) {
                node(p, id6).text = p.tok.text
                try adv(p)
            }
            try consume_semi(p)
            ret (id6, ok)
        }
        if str.eq(w, "throw") {
            let (id7, me7) = mk(p, ast.N_THROW)
            if me7 != ok { ret (ast.NONE, me7) }
            try adv(p)
            if p.tok.nl { ret (ast.NONE, fail(p, "newline after throw")) }
            let v4 = try parse_expression(p)
            node(p, id7).a = v4
            try consume_semi(p)
            ret (id7, ok)
        }
        if str.eq(w, "try") {
            let (id8, me8) = mk(p, ast.N_TRY)
            if me8 != ok { ret (ast.NONE, me8) }
            try adv(p)
            let block = try parse_block(p)
            node(p, id8).a = block
            if is_k(p, "catch") {
                let (cid, ce) = mk(p, ast.N_CATCH)
                if ce != ok { ret (ast.NONE, ce) }
                try adv(p)
                if is_p(p, "(") {
                    try adv(p)
                    let param = try parse_binding_element(p)
                    node(p, cid).a = param
                    try expect_p(p, ")")
                }
                let cb = try parse_block(p)
                node(p, cid).b = cb
                node(p, id8).b = cid
            }
            if is_k(p, "finally") {
                try adv(p)
                let fb = try parse_block(p)
                node(p, id8).c = fb
            }
            if node(p, id8).b == ast.NONE && node(p, id8).c == ast.NONE { ret (ast.NONE, fail(p, "try needs catch or finally")) }
            ret (id8, ok)
        }
        if str.eq(w, "switch") {
            let (id9, me9) = mk(p, ast.N_SWITCH)
            if me9 != ok { ret (ast.NONE, me9) }
            try adv(p)
            try expect_p(p, "(")
            let disc = try parse_expression(p)
            try expect_p(p, ")")
            try expect_p(p, "{")
            node(p, id9).a = disc
            let (cases_0, cie) = new_ids(p)
            var cases = cases_0
            if cie != ok { ret (ast.NONE, cie) }
            while !is_p(p, "}") {
                let (kid, ke) = mk(p, ast.N_CASE)
                if ke != ok { ret (ast.NONE, ke) }
                if is_k(p, "case") {
                    try adv(p)
                    let test4 = try parse_expression(p)
                    node(p, kid).a = test4
                } else if is_k(p, "default") {
                    try adv(p)
                } else {
                    ret (ast.NONE, fail(p, "expected case or default"))
                }
                try expect_p(p, ":")
                let (body_ids_0, bie) = new_ids(p)
                var body_ids = body_ids_0
                if bie != ok { ret (ast.NONE, bie) }
    p.blk += 1u32
                while !is_p(p, "}") && !is_k(p, "case") && !is_k(p, "default") {
                    if p.tok.kind == lex.T_EOF { ret (ast.NONE, fail(p, "unexpected end of input")) }
                    let s = try parse_statement(p)
                    try list.push[u32](&body_ids, s)
                }
                p.blk -= 1u32
                let (bfirst, bke) = commit(p, &body_ids)
                if bke != ok { ret (ast.NONE, bke) }
                node(p, kid).b = bfirst
                node(p, kid).c = u32(body_ids.len)
                try list.push[u32](&cases, kid)
            }
            try adv(p)
            let (cfirst, cke) = commit(p, &cases)
            if cke != ok { ret (ast.NONE, cke) }
            node(p, id9).b = cfirst
            node(p, id9).c = u32(cases.len)
            ret (id9, ok)
        }
        if str.eq(w, "debugger") {
            let (id10, me10) = mk(p, ast.N_DEBUGGER)
            if me10 != ok { ret (ast.NONE, me10) }
            try adv(p)
            try consume_semi(p)
            ret (id10, ok)
        }
        if str.eq(w, "with") {
            if p.strict { ret (ast.NONE, fail(p, "with in strict mode")) }
            let (id11, me11) = mk(p, ast.N_WITH)
            if me11 != ok { ret (ast.NONE, me11) }
            try adv(p)
            try expect_p(p, "(")
            let obj = try parse_expression(p)
            try expect_p(p, ")")
            p.sub_flag = true
            let body3 = try parse_statement(p)
            node(p, id11).a = obj
            node(p, id11).b = body3
            ret (id11, ok)
        }
        // A label: `name :`.
        if !is_reserved(w) {
            let nx2 = try peek(p)
            if nx2.kind == lex.T_PUNCT && str.eq(nx2.text, ":") && !(str.eq(w, "yield") && p.in_generator) && !(str.eq(w, "await") && p.in_async) {
                let (id12, me12) = mk(p, ast.N_LABELED)
                if me12 != ok { ret (ast.NONE, me12) }
                node(p, id12).text = w
                try adv(p)
                try adv(p)
                p.sub_flag = true
                let body4 = try parse_statement(p)
                node(p, id12).a = body4
                ret (id12, ok)
            }
        }
    }
    // Expression statement.
    let (sid, se) = mk(p, ast.N_EXPR_STMT)
    if se != ok { ret (ast.NONE, se) }
    let e = try parse_expression(p)
    node(p, sid).a = e
    try consume_semi(p)
    ret (sid, ok)
}

// --- modules

// An IdentifierName or a string literal naming an export or import: (name, was a string).
fn parse_module_name(p: *Parser) -> (str, bool, err) {
    if p.tok.kind == lex.T_STR {
        let s = p.tok.text
        // A module export name must be well-formed Unicode: a surrogate code point (U+D800..U+DFFF, 0xED 0xA0..0xBF in WTF-8) is lone.
        var q = 0usize
        while q + 1usize < s.len {
            if s[q] == 237u8 && s[q + 1usize] >= 160u8 { ret ("", false, fail(p, "a module export name must be well-formed Unicode")) }
            q += 1usize
        }
        try adv(p)
        ret (s, true, ok)
    }
    if p.tok.kind == lex.T_IDENT {
        let s2 = p.tok.text
        try adv(p)
        ret (s2, false, ok)
    }
    ret ("", false, fail(p, "expected a module export name"))
}

fn parse_module_binding(p: *Parser) -> (str, err) {
    if p.tok.kind != lex.T_IDENT || is_reserved(p.tok.text) || str.eq(p.tok.text, "await") || str.eq(p.tok.text, "yield") || str.eq(p.tok.text, "eval") || str.eq(p.tok.text, "arguments") || str.eq(p.tok.text, "let") || str.eq(p.tok.text, "static") || str.eq(p.tok.text, "implements") || str.eq(p.tok.text, "interface") || str.eq(p.tok.text, "package") || str.eq(p.tok.text, "private") || str.eq(p.tok.text, "protected") || str.eq(p.tok.text, "public") {
        ret ("", fail(p, "expected a binding identifier"))
    }
    let s = p.tok.text
    try adv(p)
    ret (s, ok)
}

// The specifier with its import attribute `type` after a NUL byte.
fn typed_spec(a: *mem.Arena, spec: str, kind: str) -> str {
    let (b, be) = str.builder(a, spec.len + kind.len + 2usize)
    if be != ok { ret spec }
    var out = b
    let e1 = str.push(&out, spec)
    let e2 = str.push_byte(&out, 0u8)
    let e3 = str.push(&out, kind)
    ret str.done(&out)
}

fn parse_module_source(p: *Parser) -> (str, err) {
    if p.tok.kind != lex.T_STR { ret ("", fail(p, "expected a module specifier")) }
    var s = p.tok.text
    try adv(p)
    // Import attributes (`with { type: "json" }`) are checked for shape and duplicate keys; `type` rides on the specifier after a NUL.
    if is_k(p, "with") {
        try adv(p)
        try expect_p(p, "{")
        let (kl, kle) = list.init[str](p.a, 4usize)
        var keys = kl
        while !is_p(p, "}") {
            if p.tok.kind != lex.T_IDENT && p.tok.kind != lex.T_STR { ret ("", fail(p, "expected an import attribute key")) }
            let key = p.tok.text
            var k = 0usize
            while k < keys.len {
                if str.eq(keys.items[k], key) { ret ("", fail(p, "Duplicate import attribute key")) }
                k += 1usize
            }
            try list.push[str](&keys, key)
            try adv(p)
            try expect_p(p, ":")
            if p.tok.kind != lex.T_STR { ret ("", fail(p, "an import attribute value must be a string")) }
            if str.eq(key, "type") { s = typed_spec(p.a, s, p.tok.text) }
            try adv(p)
            if is_p(p, ",") { try adv(p) } else if !is_p(p, "}") { ret ("", fail(p, "expected , or } in import attributes")) }
        }
        try adv(p)
    }
    ret (s, ok)
}

fn parse_import_decl(p: *Parser) -> (u32, err) {
    let (imp, me) = mk(p, ast.N_IMPORT)
    if me != ok { ret (ast.NONE, me) }
    try adv(p)
    let (specs_0, se) = new_ids(p)
    var specs = specs_0
    if se != ok { ret (ast.NONE, se) }
    var phase = 0u8
    if is_k(p, "defer") {
        let nx = try peek(p)
        if nx.kind == lex.T_PUNCT && str.eq(nx.text, "*") {
            phase = 1u8
            try adv(p)
        }
    } else if is_k(p, "source") {
        let nx2 = try peek(p)
        if nx2.kind == lex.T_IDENT && !str.eq(nx2.text, "from") {
            phase = 2u8
            try adv(p)
        } else if nx2.kind == lex.T_IDENT {
            // `import source from "m"` imports the default export as `source`; `import source from from "m"` is a source-phase import.
            let m0 = mark(p)
            try adv(p)
            try adv(p)
            if p.tok.kind != lex.T_STR { phase = 2u8 }
            restore(p, m0)
            if phase == 2u8 { try adv(p) }
        }
    }
    if p.tok.kind != lex.T_STR {
        if p.tok.kind == lex.T_IDENT {
            let (ds, de) = mk(p, ast.N_IMPORT_SPEC)
            if de != ok { ret (ast.NONE, de) }
            let local = try parse_module_binding(p)
            node(p, ds).op = 1u8
            node(p, ds).text = "default"
            node(p, ds).text2 = local
            if phase == 2u8 { node(p, ds).op = 4u8 }
            try list.push[u32](&specs, ds)
            if phase != 0u8 && is_p(p, ",") { ret (ast.NONE, fail(p, "a defer or source import takes a single binding")) }
            if is_p(p, ",") {
                try adv(p)
                if !is_p(p, "*") && !is_p(p, "{") { ret (ast.NONE, fail(p, "expected * or { after the default import")) }
            }
        }
        if phase == 2u8 && is_p(p, "*") { ret (ast.NONE, fail(p, "a source import takes a binding, not a namespace")) }
        if phase == 1u8 && !is_p(p, "*") { ret (ast.NONE, fail(p, "a defer import takes a namespace")) }
        if is_p(p, "*") {
            try adv(p)
            if !is_k(p, "as") { ret (ast.NONE, fail(p, "expected as")) }
            try adv(p)
            let (ns, ne) = mk(p, ast.N_IMPORT_SPEC)
            if ne != ok { ret (ast.NONE, ne) }
            let local2 = try parse_module_binding(p)
            node(p, ns).op = 2u8
            node(p, ns).text = "*"
            node(p, ns).text2 = local2
            try list.push[u32](&specs, ns)
        } else if is_p(p, "{") {
            if phase != 0u8 { ret (ast.NONE, fail(p, "a defer or source import takes no named bindings")) }
            try adv(p)
            while !is_p(p, "}") {
                let (sp, spe) = mk(p, ast.N_IMPORT_SPEC)
                if spe != ok { ret (ast.NONE, spe) }
                let was_reserved = p.tok.kind == lex.T_IDENT && (is_reserved(p.tok.text) || str.eq(p.tok.text, "await"))
                let (imported, was_str, nme) = parse_module_name(p)
                if nme != ok { ret (ast.NONE, nme) }
                var local3 = imported
                if is_k(p, "as") {
                    try adv(p)
                    local3 = try parse_module_binding(p)
                } else if was_str || was_reserved || str.eq(imported, "eval") || str.eq(imported, "arguments") || str.eq(imported, "yield") {
                    ret (ast.NONE, fail(p, "an imported name that is not a valid binding needs as"))
                }
                node(p, sp).op = 3u8
                node(p, sp).text = imported
                node(p, sp).text2 = local3
                try list.push[u32](&specs, sp)
                if !is_p(p, "}") { try expect_p(p, ",") }
            }
            try adv(p)
        } else if specs.len == 0usize {
            ret (ast.NONE, fail(p, "expected an import clause"))
        }
        if !is_k(p, "from") { ret (ast.NONE, fail(p, "expected from")) }
        try adv(p)
    }
    let source = try parse_module_source(p)
    try consume_semi(p)
    let (first, ke) = commit(p, &specs)
    if ke != ok { ret (ast.NONE, ke) }
    node(p, imp).a = first
    node(p, imp).b = u32(specs.len)
    node(p, imp).text = source
    node(p, imp).op = phase
    ret (imp, ok)
}

fn parse_export_decl(p: *Parser) -> (u32, err) {
    let (ex, me) = mk(p, ast.N_EXPORT)
    if me != ok { ret (ast.NONE, me) }
    try adv(p)
    if is_k(p, "default") {
        try adv(p)
        var is_decl = false
        if is_k(p, "function") || is_k(p, "class") { is_decl = true }
        if is_k(p, "async") {
            let nx = try peek(p)
            if nx.kind == lex.T_IDENT && str.eq(nx.text, "function") && !nx.nl { is_decl = true }
        }
        if is_decl {
            p.anon_default = true
            let d = try parse_statement(p)
            p.anon_default = false
            node(p, ex).op = ast.X_DEFAULT_DECL
            node(p, ex).a = d
            node(p, ex).text = p.nodes.items[usize(d)].text
            ret (ex, ok)
        }
        let saved = p.no_in
        p.no_in = false
        let e = try parse_assign(p)
        p.no_in = saved
        try consume_semi(p)
        node(p, ex).op = ast.X_DEFAULT_EXPR
        node(p, ex).a = e
        ret (ex, ok)
    }
    if is_p(p, "*") {
        try adv(p)
        var star_as = false
        var exported = ""
        if is_k(p, "as") {
            try adv(p)
            let (nm, ws, nme) = parse_module_name(p)
            if nme != ok { ret (ast.NONE, nme) }
            exported = nm
            star_as = true
        }
        if !is_k(p, "from") { ret (ast.NONE, fail(p, "expected from")) }
        try adv(p)
        let source = try parse_module_source(p)
        try consume_semi(p)
        node(p, ex).op = ast.X_STAR
        if star_as {
            node(p, ex).op = ast.X_STAR_AS
            node(p, ex).text2 = exported
        }
        node(p, ex).text = source
        ret (ex, ok)
    }
    if is_p(p, "{") {
        try adv(p)
        let (specs_0, se) = new_ids(p)
        var specs = specs_0
        if se != ok { ret (ast.NONE, se) }
        var strings = false
        var reserved_local = false
        while !is_p(p, "}") {
            let (sp, spe) = mk(p, ast.N_EXPORT_SPEC)
            if spe != ok { ret (ast.NONE, spe) }
            if p.tok.kind == lex.T_IDENT && (is_reserved(p.tok.text) || str.eq(p.tok.text, "await")) { reserved_local = true }
            let (local, was_str, nme) = parse_module_name(p)
            if nme != ok { ret (ast.NONE, nme) }
            if was_str { strings = true }
            var exported2 = local
            if is_k(p, "as") {
                try adv(p)
                let (nm2, ws2, nme2) = parse_module_name(p)
                if nme2 != ok { ret (ast.NONE, nme2) }
                exported2 = nm2
            }
            node(p, sp).text = local
            node(p, sp).text2 = exported2
            try list.push[u32](&specs, sp)
            if !is_p(p, "}") { try expect_p(p, ",") }
        }
        try adv(p)
        node(p, ex).op = ast.X_LIST
        if is_k(p, "from") {
            try adv(p)
            let source2 = try parse_module_source(p)
            node(p, ex).text = source2
            node(p, ex).c = 1u32
        } else {
            if strings || reserved_local { ret (ast.NONE, fail(p, "a local export must name a binding")) }
        }
        try consume_semi(p)
        let (first, ke) = commit(p, &specs)
        if ke != ok { ret (ast.NONE, ke) }
        node(p, ex).a = first
        node(p, ex).b = u32(specs.len)
        ret (ex, ok)
    }
    // export var / let / const / function / class
    var allowed = false
    if is_k(p, "var") || is_k(p, "const") || is_k(p, "function") || is_k(p, "class") { allowed = true }
    if is_k(p, "let") { allowed = true }
    if is_k(p, "async") {
        let nx2 = try peek(p)
        if nx2.kind == lex.T_IDENT && str.eq(nx2.text, "function") && !nx2.nl { allowed = true }
    }
    if !allowed { ret (ast.NONE, fail(p, "unexpected token after export")) }
    let d2 = try parse_statement(p)
    node(p, ex).op = ast.X_DECL
    node(p, ex).a = d2
    ret (ex, ok)
}

// Parses a script; `Program.root` is the N_PROGRAM node. On failure `message` and `line` describe the error.
type Parsed = struct { program: ast.Program, message: str, line: u32 }

fn parse_program(a: *mem.Arena, source: str) -> (Parsed, err) {
    let (r, e) = parse_goal(a, source, false)
    ret (r, e)
}

// Parses a module: strict code in which `await` works at the top level and `import` / `export` declarations are allowed.
fn parse_module(a: *mem.Arena, source: str) -> (Parsed, err) {
    let (r, e) = parse_goal(a, source, true)
    ret (r, e)
}

// Parses the source of a direct eval, which inherits strictness and the `super` / `new.target` / private-name context of its caller.
fn parse_eval(a: *mem.Arena, source: str, eo: *const early.EvalOpts) -> (Parsed, err) {
    let (r, e) = parse_goal_in(a, source, false, eo)
    ret (r, e)
}

fn parse_goal(a: *mem.Arena, source: str, module: bool) -> (Parsed, err) {
    var none: early.EvalOpts = zero
    let (r, e) = parse_goal_in(a, source, module, &none)
    ret (r, e)
}

fn parse_goal_in(a: *mem.Arena, source: str, module: bool, eo: *const early.EvalOpts) -> (Parsed, err) {
    var p: Parser = zero
    p.a = a
    p.module = module
    p.strict = eo.strict
    let (pl, ple) = list.init[u32](a, 8usize)
    p.parens = pl
    if module {
        p.strict = true
        p.in_async = true
    }
    p.lx = lex.new_lexer(a, source)
    p.lx.module = module
    let (nodes, e1) = list.init[ast.Node](a, 256usize)
    let (kids, e2) = list.init[u32](a, 256usize)
    let (strs, e3) = list.init[ast.TemplateStr](a, 16usize)
    let (vars, e4) = list.init[u32](a, 32usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (zero, e1) }
    p.nodes = nodes
    p.kids = kids
    p.strs = strs
    p.vars = vars
    var out: Parsed = zero
    let first = adv(&p)
    if first != ok {
        out.message = p.message
        out.line = p.line
        ret (out, first)
    }
    let (root, re) = mk(&p, ast.N_PROGRAM)
    if re != ok { ret (out, re) }
    let (ids_0, ie) = new_ids(&p)
    var ids = ids_0
    if ie != ok { ret (out, ie) }
    let se = parse_statements(&p, false, &ids)
    if se != ok {
        out.message = p.message
        out.line = p.line
        ret (out, se)
    }
    let (kfirst, ke) = commit(&p, &ids)
    if ke != ok { ret (out, ke) }
    p.nodes.items[usize(root)].a = kfirst
    p.nodes.items[usize(root)].b = u32(ids.len)
    if p.strict { p.nodes.items[usize(root)].flags = ast.F_STRICT }
    if p.top_await { p.nodes.items[usize(root)].flags = p.nodes.items[usize(root)].flags | ast.F_ASYNC }
    close_hoist(&p, root, 0usize)
    out.program = ast.Program { nodes: list.slice_const[ast.Node](&p.nodes), kids: list.slice_const[u32](&p.kids), strs: list.slice_const[ast.TemplateStr](&p.strs), root: root, source: source, url: "", module: zero, is_module: module, internal: false }
    // Static semantics beyond the grammar.
    let (early_result, early_error) = early.check_in(a, &out.program, eo)
    if early_error != ok {
        out.message = early_result.message
        out.line = early_result.line
        ret (out, ParseError)
    }
    ret (out, ok)
}
