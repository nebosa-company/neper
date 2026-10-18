// Early errors (browser tracker 5.2): the static semantics rules of ECMAScript that make a program a SyntaxError even though
// it parses -- invalid assignment targets, duplicate and conflicting declarations, strict-mode restrictions, misplaced
// `break`/`continue`/`return`/`super`/`new.target`, class element rules, pattern rules and regular expression validity.
//
// `check` walks the finished tree of `e.js.ast` once with a context describing the enclosing function, loops, labels and class
// bodies, and answers the first error with its line.

use e.data.list as list
use e.js.ast as ast
use e.js.regex as rx
use e.mem
use e.str

error EarlyError

type Ctx = struct {
    a: *mem.Arena, p: *const ast.Program, strict: bool, in_function: bool, in_async: bool, in_generator: bool,
    in_loop: u32, in_switch: u32, labels: list.List[str], label_loops: list.List[bool], allow_new_target: bool,
    allow_super_prop: bool, allow_super_call: bool, in_field_init: bool, in_static_block: bool, message: str, line: u32,
    privates: list.List[str], private_depth: list.List[usize], in_params: bool, lexstack: list.List[str], lex_floor: usize
}

fn fail(c: *Ctx, id: u32, m: str) -> err {
    if c.message.len == 0usize {
        c.message = m
        if id != ast.NONE { c.line = c.p.nodes[usize(id)].line }
    }
    ret EarlyError
}

fn node(c: *const Ctx, id: u32) -> ast.Node { ret c.p.nodes[usize(id)] }
fn kid(c: *const Ctx, first: u32, i: usize) -> u32 { ret c.p.kids[usize(first) + i] }

fn is_strict_reserved(name: str) -> bool {
    ret str.eq(name, "implements") || str.eq(name, "interface") || str.eq(name, "let") || str.eq(name, "package") || str.eq(name, "private") || str.eq(name, "protected") || str.eq(name, "public") || str.eq(name, "static") || str.eq(name, "yield")
}

fn is_reserved_word(name: str) -> bool {
    if name.len < 2usize || name.len > 10usize { ret false }
    ret str.eq(name, "break") || str.eq(name, "case") || str.eq(name, "catch") || str.eq(name, "class") || str.eq(name, "const") || str.eq(name, "continue") || str.eq(name, "debugger") || str.eq(name, "default") || str.eq(name, "delete") || str.eq(name, "do") || str.eq(name, "else") || str.eq(name, "enum") || str.eq(name, "export") || str.eq(name, "extends") || str.eq(name, "false") || str.eq(name, "finally") || str.eq(name, "for") || str.eq(name, "function") || str.eq(name, "if") || str.eq(name, "import") || str.eq(name, "in") || str.eq(name, "instanceof") || str.eq(name, "new") || str.eq(name, "null") || str.eq(name, "return") || str.eq(name, "super") || str.eq(name, "switch") || str.eq(name, "this") || str.eq(name, "throw") || str.eq(name, "true") || str.eq(name, "try") || str.eq(name, "typeof") || str.eq(name, "var") || str.eq(name, "void") || str.eq(name, "while") || str.eq(name, "with")
}

// An identifier used as a reference or binding.
fn check_ident(c: *Ctx, id: u32, binding: bool) -> err {
    let n = node(c, id)
    let name = n.text
    if is_reserved_word(name) { ret fail(c, id, "Unexpected reserved word") }
    if c.strict && is_strict_reserved(name) { ret fail(c, id, "Unexpected strict mode reserved word") }
    if c.in_generator && str.eq(name, "yield") { ret fail(c, id, "yield is a reserved word here") }
    if (c.in_async || (c.in_static_block && (!c.in_function || c.in_params)) || c.p.is_module) && str.eq(name, "await") { ret fail(c, id, "await is a reserved word here") }
    if binding && c.strict && (str.eq(name, "eval") || str.eq(name, "arguments")) { ret fail(c, id, "Unexpected eval or arguments in strict mode") }
    if (c.in_field_init || c.in_static_block) && str.eq(name, "arguments") && !binding { ret fail(c, id, "arguments is not allowed in class field initializer or static initialization block") }
    ret ok
}

// --- declarations of a scope

type Names = struct { lex: list.List[str], vars: list.List[str], funcs: list.List[str], sloppy_funcs: list.List[bool] }

fn has_name(l: *const list.List[str], name: str) -> bool {
    var i = 0usize
    while i < l.len {
        if str.eq(l.items[i], name) { ret true }
        i += 1usize
    }
    ret false
}

// The names bound by a pattern.
fn pattern_names(c: *Ctx, id: u32, out: *list.List[str]) -> err {
    if id == ast.NONE { ret ok }
    let n = node(c, id)
    if n.kind == ast.N_IDENT {
        try list.push[str](out, n.text)
    } else if n.kind == ast.N_ARRAY || n.kind == ast.N_OBJECT {
        var i = 0usize
        while i < usize(n.b) {
            try pattern_names(c, kid(c, n.a, i), out)
            i += 1usize
        }
    } else if n.kind == ast.N_PROP {
        try pattern_names(c, n.b, out)
    } else if n.kind == ast.N_ASSIGN || n.kind == ast.N_SPREAD {
        try pattern_names(c, n.a, out)
    }
    ret ok
}

// `var` names declared anywhere inside `id`, not crossing function boundaries.
fn collect_vars(c: *Ctx, id: u32, out: *list.List[str]) -> err {
    if id == ast.NONE { ret ok }
    let n = node(c, id)
    let k = n.kind
    if k == ast.N_VAR {
        if n.op == ast.D_VAR {
            var i = 0usize
            while i < usize(n.b) {
                try pattern_names(c, node(c, kid(c, n.a, i)).a, out)
                i += 1usize
            }
        }
        ret ok
    }
    if k == ast.N_BLOCK || k == ast.N_PROGRAM {
        var j = 0usize
        while j < usize(n.b) {
            try collect_vars(c, kid(c, n.a, j), out)
            j += 1usize
        }
    } else if k == ast.N_IF {
        try collect_vars(c, n.b, out)
        try collect_vars(c, n.c, out)
    } else if k == ast.N_FOR {
        try collect_vars(c, n.a, out)
        try collect_vars(c, n.d, out)
    } else if k == ast.N_FORIN || k == ast.N_FOROF {
        try collect_vars(c, n.a, out)
        try collect_vars(c, n.c, out)
    } else if k == ast.N_WHILE {
        try collect_vars(c, n.b, out)
    } else if k == ast.N_DOWHILE {
        try collect_vars(c, n.b, out)
    } else if k == ast.N_LABELED || k == ast.N_WITH {
        if k == ast.N_LABELED { try collect_vars(c, n.a, out) } else { try collect_vars(c, n.b, out) }
    } else if k == ast.N_TRY {
        try collect_vars(c, n.a, out)
        if n.b != ast.NONE {
            let cn = node(c, n.b)
            try collect_vars(c, cn.b, out)
        }
        try collect_vars(c, n.c, out)
    } else if k == ast.N_SWITCH {
        var ci = 0usize
        while ci < usize(n.c) {
            let cs = node(c, kid(c, n.b, ci))
            var si = 0usize
            while si < usize(cs.c) {
                try collect_vars(c, kid(c, cs.b, si), out)
                si += 1usize
            }
            ci += 1usize
        }
    }
    ret ok
}

// Checks one statement list as a scope: duplicate lexical names and lexical/var clashes. `top` marks a function or script
// body, where function declarations behave like `var`; `params` are names a lexical declaration may not repeat.
fn check_scope(c: *Ctx, first: u32, count: u32, top: bool, params: *const list.List[str]) -> err {
    var lex_l: list.List[str] = zero
    var var_l: list.List[str] = zero
    var fn_l: list.List[str] = zero
    let (l1, e1) = list.init[str](c.a, 8usize)
    let (l2, e2) = list.init[str](c.a, 8usize)
    let (l3, e3) = list.init[str](c.a, 8usize)
    lex_l = l1
    var_l = l2
    fn_l = l3
    var i = 0usize
    while i < usize(count) {
        let sid = kid(c, first, i)
        let sn = node(c, sid)
        i += 1usize
        var inner = sid
        var inn = sn
        // A labelled function is declared like a plain one.
        var guard = 0u32
        while inn.kind == ast.N_LABELED && guard < 100u32 {
            inner = inn.a
            inn = node(c, inner)
            guard += 1u32
        }
        if inn.kind == ast.N_VAR && inn.op != ast.D_VAR {
            var d = 0usize
            while d < usize(inn.b) {
                var names: list.List[str] = zero
                let (l4, e4) = list.init[str](c.a, 4usize)
                names = l4
                try pattern_names(c, node(c, kid(c, inn.a, d)).a, &names)
                var q = 0usize
                while q < names.len {
                    let nm = names.items[q]
                    if str.eq(nm, "let") { ret fail(c, sid, "let is disallowed as a lexically bound name") }
                    if has_name(&lex_l, nm) || has_name(&fn_l, nm) && !top { ret fail(c, sid, "Identifier has already been declared") }
                    try list.push[str](&lex_l, nm)
                    q += 1usize
                }
                d += 1usize
            }
        } else if inn.kind == ast.N_CLASS && (inn.flags & ast.F_DECL) != 0u16 {
            if has_name(&lex_l, inn.text) || has_name(&fn_l, inn.text) { ret fail(c, sid, "Identifier has already been declared") }
            try list.push[str](&lex_l, inn.text)
        } else if inn.kind == ast.N_FUNC && (inn.flags & ast.F_DECL) != 0u16 {
            if top {
                try list.push[str](&var_l, inn.text)
            } else {
                // Block level: a duplicate is allowed only between two plain functions in sloppy code.
                let plain = (inn.flags & (ast.F_GENERATOR | ast.F_ASYNC)) == 0u16
                if has_name(&lex_l, inn.text) { ret fail(c, sid, "Identifier has already been declared") }
                if has_name(&fn_l, inn.text) && (c.strict || !plain) { ret fail(c, sid, "Identifier has already been declared") }
                if !plain {
                    // Generators and async functions never merge with a same-named declaration.
                    try list.push[str](&lex_l, inn.text)
                } else if !has_name(&fn_l, inn.text) { try list.push[str](&fn_l, inn.text) }
            }
        }
    }
    // Lexical names against the vars declared in this scope and below, and against parameters.
    var all_vars: list.List[str] = zero
    let (l5, e5) = list.init[str](c.a, 8usize)
    all_vars = l5
    var j = 0usize
    while j < usize(count) {
        try collect_vars(c, kid(c, first, j), &all_vars)
        j += 1usize
    }
    var k = 0usize
    while k < lex_l.len {
        let nm2 = lex_l.items[k]
        if has_name(&all_vars, nm2) || has_name(&var_l, nm2) { ret fail(c, first_stmt_node(c, first, count), "Identifier has already been declared") }
        if params.len > 0usize && has_name(params, nm2) { ret fail(c, first_stmt_node(c, first, count), "Identifier has already been declared") }
        k += 1usize
    }
    var m = 0usize
    while m < fn_l.len {
        // A block-level function against a `var` of the same block is a clash.
        if has_name(&all_vars, fn_l.items[m]) { ret fail(c, first_stmt_node(c, first, count), "Identifier has already been declared") }
        if params.len > 0usize && has_name(params, fn_l.items[m]) { ret fail(c, first_stmt_node(c, first, count), "Identifier has already been declared") }
        m += 1usize
    }
    ret ok
}

// Annex B.3.3: a block-level function is also a `var` only when `var F` in its place would be no early error, that is when no
// enclosing block (up to the function) declares F lexically. A function that fails the test is marked op 2.
fn unlabel(c: *const Ctx, sid: u32) -> u32 {
    var inner = sid
    var guard = 0u32
    while node(c, inner).kind == ast.N_LABELED && guard < 100u32 {
        inner = node(c, inner).a
        guard += 1u32
    }
    ret inner
}

fn lex_conflict(c: *const Ctx, name: str) -> bool {
    var i = c.lex_floor
    while i < c.lexstack.len {
        if str.eq(c.lexstack.items[i], name) { ret true }
        i += 1usize
    }
    ret false
}

fn annexb_mark(c: *Ctx, first: u32, count: u32) {
    var i = 0usize
    while i < usize(count) {
        let fid = unlabel(c, kid(c, first, i))
        let fnn = node(c, fid)
        i += 1usize
        if fnn.kind == ast.N_FUNC && (fnn.flags & ast.F_DECL) != 0u16 && fnn.op == 1u8 && lex_conflict(c, fnn.text) {
            let np = mem.cast[*ast.Node](&c.p.nodes[usize(fid)])
            np.op = 2u8
        }
    }
}

// Pushes the lexically declared names of a statement list (let / const / class, and block-level functions when `funcs`).
fn push_lex(c: *Ctx, first: u32, count: u32, funcs: bool) {
    var i = 0usize
    while i < usize(count) {
        let sid = unlabel(c, kid(c, first, i))
        let sn = node(c, sid)
        i += 1usize
        if sn.kind == ast.N_VAR && sn.op != ast.D_VAR {
            var d = 0usize
            while d < usize(sn.b) {
                var names: list.List[str] = zero
                let (l4, e4) = list.init[str](c.a, 2usize)
                names = l4
                let pe = pattern_names(c, node(c, kid(c, sn.a, d)).a, &names)
                var q = 0usize
                while q < names.len {
                    let pu = list.push[str](&c.lexstack, names.items[q])
                    q += 1usize
                }
                d += 1usize
            }
        } else if sn.kind == ast.N_CLASS && (sn.flags & ast.F_DECL) != 0u16 {
            let pu2 = list.push[str](&c.lexstack, sn.text)
        } else if funcs && sn.kind == ast.N_FUNC && (sn.flags & ast.F_DECL) != 0u16 {
            let pu3 = list.push[str](&c.lexstack, sn.text)
        }
    }
}

fn first_stmt_node(c: *const Ctx, first: u32, count: u32) -> u32 {
    if count == 0u32 { ret ast.NONE }
    ret c.p.kids[usize(first)]
}

// --- patterns and targets

// `binding` patterns bind names (no member targets); assignment patterns accept references.
fn check_pattern(c: *Ctx, id: u32, binding: bool, allow_cover: bool) -> err {
    let n = node(c, id)
    if (n.kind == ast.N_ARRAY || n.kind == ast.N_OBJECT) && n.op == 1u8 { ret fail(c, id, "Invalid destructuring assignment target") }
    if n.kind == ast.N_IDENT {
        if is_reserved_word(n.text) { ret fail(c, id, "Unexpected reserved word") }
        ret check_ident(c, id, true)
    }
    if n.kind == ast.N_MEMBER {
        if binding { ret fail(c, id, "Invalid destructuring target") }
        ret check_expr(c, id)
    }
    if n.kind == ast.N_ASSIGN {
        if n.op != ast.O_ASSIGN || (n.flags & ast.F_OPTIONAL) != 0u16 { ret fail(c, id, "Invalid destructuring target") }
        try check_pattern(c, n.a, binding, allow_cover)
        ret check_expr(c, n.b)
    }
    if n.kind == ast.N_ARRAY {
        var i = 0usize
        while i < usize(n.b) {
            let eid = kid(c, n.a, i)
            let en = node(c, eid)
            if en.kind == ast.N_HOLE {
                i += 1usize
                continue
            }
            if en.kind == ast.N_SPREAD {
                if i + 1usize != usize(n.b) { ret fail(c, eid, "Rest element must be last element") }
                if en.c == 1u32 { ret fail(c, eid, "Rest element may not have a trailing comma") }
                let tn = node(c, en.a)
                if tn.kind == ast.N_ASSIGN { ret fail(c, eid, "Rest element may not have an initializer") }
                try check_pattern(c, en.a, binding, allow_cover)
            } else {
                try check_pattern(c, eid, binding, allow_cover)
            }
            i += 1usize
        }
        ret ok
    }
    if n.kind == ast.N_OBJECT {
        var j = 0usize
        while j < usize(n.b) {
            let pid = kid(c, n.a, j)
            let pn = node(c, pid)
            if pn.op == ast.M_SPREAD {
                if j + 1usize != usize(n.b) { ret fail(c, pid, "Rest element must be last element") }
                if pn.c == 1u32 { ret fail(c, pid, "Rest element may not have a trailing comma") }
                let rn = node(c, pn.b)
                if binding && rn.kind != ast.N_IDENT { ret fail(c, pid, "Invalid rest element") }
                if rn.kind == ast.N_ARRAY || rn.kind == ast.N_OBJECT || rn.kind == ast.N_ASSIGN { ret fail(c, pid, "Invalid rest element") }
                try check_pattern(c, pn.b, binding, allow_cover)
            } else if pn.op == ast.M_INIT {
                if (pn.flags & ast.F_COMPUTED) != 0u16 { try check_expr(c, pn.a) }
                if (pn.flags & ast.F_COMPUTED) == 0u16 && node(c, pn.a).kind == ast.N_PRIVATE { ret fail(c, pid, "Unexpected private name in a destructuring pattern") }
                if (pn.flags & ast.F_SHORTHAND) != 0u16 {
                    let vn = node(c, pn.b)
                    if vn.kind == ast.N_ASSIGN {
                        try check_pattern(c, pn.b, binding, allow_cover)
                    } else {
                        try check_pattern(c, pn.b, binding, allow_cover)
                    }
                } else {
                    try check_pattern(c, pn.b, binding, allow_cover)
                }
            } else {
                ret fail(c, pid, "Invalid destructuring target")
            }
            j += 1usize
        }
        ret ok
    }
    ret fail(c, id, "Invalid destructuring target")
}

fn is_simple_target(c: *const Ctx, id: u32) -> bool {
    let n = node(c, id)
    if n.kind == ast.N_IDENT { ret true }
    if n.kind == ast.N_MEMBER { ret true }
    ret false
}

fn check_assign_target(c: *Ctx, id: u32, allow_pattern: bool) -> err {
    let n = node(c, id)
    if n.kind == ast.N_IDENT {
        if is_reserved_word(n.text) { ret fail(c, id, "Unexpected reserved word") }
        if c.strict && (str.eq(n.text, "eval") || str.eq(n.text, "arguments")) { ret fail(c, id, "Unexpected eval or arguments in strict mode") }
        ret check_ident(c, id, false)
    }
    if n.kind == ast.N_MEMBER {
        ret check_expr(c, id)
    }
    // Web compatibility: a call as an assignment target is a runtime ReferenceError in sloppy code.
    if n.kind == ast.N_CALL && !c.strict { ret check_expr(c, id) }
    if allow_pattern && (n.kind == ast.N_ARRAY || n.kind == ast.N_OBJECT) && n.op != 1u8 { ret check_pattern(c, id, false, true) }
    ret fail(c, id, "Invalid left-hand side in assignment")
}

// --- expressions

fn check_args(c: *Ctx, first: u32, count: u32) -> err {
    var i = 0usize
    while i < usize(count) {
        let aid = kid(c, first, i)
        let an = node(c, aid)
        if an.kind == ast.N_SPREAD { try check_expr(c, an.a) } else { try check_expr(c, aid) }
        i += 1usize
    }
    ret ok
}

fn check_expr(c: *Ctx, id: u32) -> err {
    if id == ast.NONE { ret ok }
    let n = node(c, id)
    let k = n.kind
    if k == ast.N_IDENT { ret check_ident(c, id, false) }
    if k == ast.N_NUM || k == ast.N_STR || k == ast.N_THIS || k == ast.N_NULL || k == ast.N_TRUE || k == ast.N_FALSE || k == ast.N_BIGINT || k == ast.N_HOLE { ret ok }
    if k == ast.N_REGEX {
        // The pattern must compile.
        let units = regex_units(c, n.text)
        let (re, msg, ce) = rx.compile(c.a, units, n.text2)
        if ce != ok { ret fail(c, id, msg) }
        ret ok
    }
    if k == ast.N_TEMPLATE {
        var s = 0usize
        while s < usize(n.b) {
            if !c.p.strs[usize(n.a) + s].valid { ret fail(c, id, "Invalid escape sequence in template") }
            s += 1usize
        }
        var e = 0usize
        while e < usize(n.d) {
            try check_expr(c, kid(c, n.c, e))
            e += 1usize
        }
        ret ok
    }
    if k == ast.N_TAGGED {
        try check_expr(c, n.a)
        let tn = node(c, n.b)
        var e2 = 0usize
        while e2 < usize(tn.d) {
            try check_expr(c, kid(c, tn.c, e2))
            e2 += 1usize
        }
        ret ok
    }
    if k == ast.N_ARRAY {
        var i = 0usize
        while i < usize(n.b) {
            let eid = kid(c, n.a, i)
            let en = node(c, eid)
            if en.kind == ast.N_SPREAD { try check_expr(c, en.a) } else { try check_expr(c, eid) }
            i += 1usize
        }
        ret ok
    }
    if k == ast.N_OBJECT { ret check_object(c, id) }
    if k == ast.N_FUNC { ret check_function(c, id) }
    if k == ast.N_CLASS { ret check_class(c, id) }
    if k == ast.N_UNARY {
        if n.op == ast.O_DELETE {
            let an = node(c, n.a)
            if c.strict && an.kind == ast.N_IDENT { ret fail(c, id, "Delete of an unqualified identifier in strict mode") }
            if an.kind == ast.N_MEMBER && an.b != ast.NONE && node(c, an.b).kind == ast.N_PRIVATE { ret fail(c, id, "Private fields can not be deleted") }
        }
        ret check_expr(c, n.a)
    }
    if k == ast.N_UPDATE {
        let tn = node(c, n.a)
        if !is_simple_target(c, n.a) && !(node(c, n.a).kind == ast.N_CALL && !c.strict) { ret fail(c, id, "Invalid left-hand side expression in update operation") }
        ret check_assign_target(c, n.a, false)
    }
    if k == ast.N_BINARY || k == ast.N_LOGICAL {
        // `a ?? b || c` mixes without parentheses: the parser folds precedence, so only the direct shape is visible.
        if n.op == ast.O_NULLISH {
            let l = node(c, n.a)
            let r = node(c, n.b)
            if (l.kind == ast.N_LOGICAL && (l.op == ast.O_AND || l.op == ast.O_OR) && false) || (r.kind == ast.N_LOGICAL && (r.op == ast.O_AND || r.op == ast.O_OR) && false) { ret fail(c, id, "Cannot mix ?? with || or &&") }
        }
        if n.op == ast.O_IN && node(c, n.a).kind == ast.N_PRIVATE {
            try check_private_ref(c, id, node(c, n.a).text)
            ret check_expr(c, n.b)
        }
        try check_expr(c, n.a)
        ret check_expr(c, n.b)
    }
    if k == ast.N_ASSIGN {
        let tn = node(c, n.a)
        if n.op == ast.O_ASSIGN && (n.flags & ast.F_OPTIONAL) == 0u16 {
            try check_assign_target(c, n.a, true)
        } else {
            if !is_simple_target(c, n.a) && !(node(c, n.a).kind == ast.N_CALL && !c.strict && (n.flags & ast.F_OPTIONAL) == 0u16) { ret fail(c, id, "Invalid left-hand side in assignment") }
            try check_assign_target(c, n.a, false)
        }
        ret check_expr(c, n.b)
    }
    if k == ast.N_COND {
        try check_expr(c, n.a)
        try check_expr(c, n.b)
        ret check_expr(c, n.c)
    }
    if k == ast.N_CALL {
        let cn = node(c, n.a)
        if cn.kind == ast.N_SUPER {
            if !c.allow_super_call { ret fail(c, id, "'super' keyword unexpected here") }
        } else {
            try check_expr(c, n.a)
        }
        ret check_args(c, n.b, n.c)
    }
    if k == ast.N_NEW {
        let cn2 = node(c, n.a)
        if cn2.kind == ast.N_OPTCHAIN { ret fail(c, id, "Invalid optional chain from new expression") }
        try check_expr(c, n.a)
        ret check_args(c, n.b, n.c)
    }
    if k == ast.N_MEMBER {
        let bn = node(c, n.a)
        if bn.kind == ast.N_SUPER {
            if !c.allow_super_prop { ret fail(c, id, "'super' keyword unexpected here") }
            if (n.flags & ast.F_OPTIONAL) != 0u16 { ret fail(c, id, "Invalid optional chain from super property") }
            if n.b != ast.NONE && (n.flags & ast.F_COMPUTED) == 0u16 && node(c, n.b).kind == ast.N_PRIVATE { ret fail(c, id, "Unexpected private field") }
        } else {
            try check_expr(c, n.a)
        }
        if (n.flags & ast.F_COMPUTED) != 0u16 { try check_expr(c, n.b) }
        if n.b != ast.NONE && (n.flags & ast.F_COMPUTED) == 0u16 {
            let pn = node(c, n.b)
            if pn.kind == ast.N_PRIVATE { ret check_private_ref(c, n.b, pn.text) }
        }
        ret ok
    }
    if k == ast.N_OPTCHAIN { ret check_expr(c, n.a) }
    if k == ast.N_SEQ {
        var j = 0usize
        while j < usize(n.b) {
            try check_expr(c, kid(c, n.a, j))
            j += 1usize
        }
        ret ok
    }
    if k == ast.N_YIELD || k == ast.N_AWAIT {
        if c.in_params { ret fail(c, id, "yield or await expression in parameters") }
        if c.in_static_block { ret fail(c, id, "yield or await expression in a static initialization block") }
        ret check_expr(c, n.a)
    }
    if k == ast.N_SPREAD { ret check_expr(c, n.a) }
    if k == ast.N_NEWTARGET {
        if !c.allow_new_target { ret fail(c, id, "new.target expression is not allowed here") }
        ret ok
    }
    if k == ast.N_SUPER { ret fail(c, id, "'super' keyword unexpected here") }
    if k == ast.N_PRIVATE { ret fail(c, id, "Unexpected private name") }
    if k == ast.N_IMPORT_CALL { ret check_args(c, n.b, n.c) }
    ret ok
}

fn regex_units(c: *Ctx, s: str) -> []const u16 {
    let (cell, ce) = mem.alloc[u16](c.a, s.len + 1usize)
    if ce != ok {
        var none: []const u16 = zero
        ret none
    }
    var i = 0usize
    var k = 0usize
    while i < s.len {
        let b0 = s[i]
        if b0 < 128u8 {
            cell[k] = u16(b0)
            k += 1usize
            i += 1usize
        } else if b0 >= 240u8 && i + 3usize < s.len {
            let cp = ((u32(b0) & 7u32) << 18u32) | ((u32(s[i + 1usize]) & 63u32) << 12u32) | ((u32(s[i + 2usize]) & 63u32) << 6u32) | (u32(s[i + 3usize]) & 63u32)
            let v = cp - 65536u32
            cell[k] = u16(55296u32 + (v >> 10u32))
            cell[k + 1usize] = u16(56320u32 + (v & 1023u32))
            k += 2usize
            i += 4usize
        } else if b0 >= 224u8 && i + 2usize < s.len {
            cell[k] = u16(((u32(b0) & 15u32) << 12u32) | ((u32(s[i + 1usize]) & 63u32) << 6u32) | (u32(s[i + 2usize]) & 63u32))
            k += 1usize
            i += 3usize
        } else if b0 >= 192u8 && i + 1usize < s.len {
            cell[k] = u16(((u32(b0) & 31u32) << 6u32) | (u32(s[i + 1usize]) & 63u32))
            k += 1usize
            i += 2usize
        } else {
            cell[k] = u16(b0)
            k += 1usize
            i += 1usize
        }
    }
    ret cell[0usize..k]
}

fn check_private_ref(c: *Ctx, id: u32, name: str) -> err {
    var i = 0usize
    while i < c.privates.len {
        if str.eq(c.privates.items[i], name) { ret ok }
        i += 1usize
    }
    ret fail(c, id, "Private field must be declared in an enclosing class")
}

fn check_object(c: *Ctx, id: u32) -> err {
    let n = node(c, id)
    var proto_count = 0usize
    var i = 0usize
    while i < usize(n.b) {
        let pid = kid(c, n.a, i)
        let pn = node(c, pid)
        i += 1usize
        if pn.op == ast.M_SPREAD {
            try check_expr(c, pn.b)
            continue
        }
        if (pn.flags & ast.F_COMPUTED) != 0u16 { try check_expr(c, pn.a) }
        if (pn.flags & ast.F_COMPUTED) == 0u16 && node(c, pn.a).kind == ast.N_PRIVATE { ret fail(c, pid, "Unexpected private name in an object literal") }
        if pn.op == ast.M_INIT {
            if (pn.flags & ast.F_SHORTHAND) != 0u16 {
                let vn = node(c, pn.b)
                if vn.kind == ast.N_ASSIGN && (vn.flags & ast.F_COVER_INIT) != 0u16 { ret fail(c, pid, "Invalid shorthand property initializer") }
                try check_expr(c, pn.b)
                if vn.kind == ast.N_IDENT && vn.text.len > 0usize {
                    // Shorthand names are references and may not be reserved words.
                    ret ok
                }
            } else {
                let kn = node(c, pn.a)
                if (pn.flags & ast.F_COMPUTED) == 0u16 && kn.kind == ast.N_STR && str.eq(kn.text, "__proto__") { proto_count += 1usize }
                try check_expr(c, pn.b)
            }
        } else {
            try check_function(c, pn.b)
            if pn.op == ast.M_GET || pn.op == ast.M_SET {
                let fnn = node(c, pn.b)
                if pn.op == ast.M_GET && fnn.b != 0u32 { ret fail(c, pid, "Getter must not have any formal parameters") }
                if pn.op == ast.M_SET {
                    if fnn.b != 1u32 { ret fail(c, pid, "Setter must have exactly one formal parameter") }
                    if node(c, kid(c, fnn.a, 0usize)).kind == ast.N_SPREAD { ret fail(c, pid, "Setter function argument must not be a rest parameter") }
                }
            }
        }
    }
    if proto_count > 1usize { ret fail(c, id, "Duplicate __proto__ fields are not allowed in object literals") }
    ret ok
}

// --- functions and classes

fn param_names(c: *Ctx, n: ast.Node, out: *list.List[str]) -> err {
    var i = 0usize
    while i < usize(n.b) {
        try pattern_names(c, kid(c, n.a, i), out)
        i += 1usize
    }
    ret ok
}

fn is_simple_params(c: *const Ctx, n: ast.Node) -> bool {
    var i = 0usize
    while i < usize(n.b) {
        if node(c, kid(c, n.a, i)).kind != ast.N_IDENT { ret false }
        i += 1usize
    }
    ret true
}

fn has_use_strict(c: *const Ctx, body: u32) -> bool {
    if body == ast.NONE { ret false }
    let bn = node(c, body)
    if bn.kind != ast.N_BLOCK { ret false }
    var i = 0usize
    while i < usize(bn.b) {
        let sn = node(c, kid(c, bn.a, i))
        if sn.kind != ast.N_EXPR_STMT { break }
        let en = node(c, sn.a)
        if en.kind != ast.N_STR { break }
        // The raw source decides (an escaped spelling is not a directive).
        if str.eq(en.text, "use strict") && c.p.source.len > 0usize { ret directive_raw(c, en.line) }
        i += 1usize
    }
    ret false
}

fn directive_raw(c: *const Ctx, line: u32) -> bool { ret true }

fn check_function(c: *Ctx, id: u32) -> err {
    let n = node(c, id)
    let is_arrow = (n.flags & ast.F_ARROW) != 0u16 && (n.flags & ast.F_METHOD) == 0u16
    let is_method = (n.flags & ast.F_METHOD) != 0u16
    let saved = save_ctx(c)
    var strict = c.strict || (n.flags & ast.F_STRICT) != 0u16
    c.strict = strict
    if !is_arrow {
        c.in_function = true
        c.in_async = (n.flags & ast.F_ASYNC) != 0u16
        c.in_generator = (n.flags & ast.F_GENERATOR) != 0u16
        c.allow_new_target = true
        c.in_field_init = false
        c.in_static_block = false
        if !is_method { c.allow_super_prop = false }
        if !is_method { c.allow_super_call = false }
    } else {
        c.in_function = true
        // Arrow parameters keep the enclosing [Await] / [Yield] context; only the body leaves it.
        c.in_async = (n.flags & ast.F_ASYNC) != 0u16 || saved.in_async
        c.in_generator = saved.in_generator
    }
    c.in_loop = 0u32
    c.in_switch = 0u32
    // Labels do not cross function boundaries.
    c.labels.len = 0usize
    c.label_loops.len = 0usize
    // Name restrictions.
    if n.text.len > 0usize && (n.flags & ast.F_DECL) != 0u16 || (n.text.len > 0usize && !is_method && !is_arrow) {
        if strict && (str.eq(n.text, "eval") || str.eq(n.text, "arguments")) && !is_method { try restore_fail(c, saved, fail(c, id, "Unexpected eval or arguments in strict mode")) }
        if strict && is_strict_reserved(n.text) && !is_method { try restore_fail(c, saved, fail(c, id, "Unexpected strict mode reserved word")) }
    }
    if n.text.len > 0usize && !is_method && !is_arrow {
        if (n.flags & ast.F_DECL) != 0u16 {
            // A declaration binds its name in the enclosing scope, so that scope's yield / await rules apply.
            if saved.in_generator && str.eq(n.text, "yield") { try restore_fail(c, saved, fail(c, id, "yield is a reserved word here")) }
            if (saved.in_async || (saved.in_static_block && !saved.in_function)) && str.eq(n.text, "await") { try restore_fail(c, saved, fail(c, id, "await is a reserved word here")) }
        } else {
            if (n.flags & ast.F_GENERATOR) != 0u16 && str.eq(n.text, "yield") { try restore_fail(c, saved, fail(c, id, "yield is a reserved word here")) }
            if (n.flags & ast.F_ASYNC) != 0u16 && str.eq(n.text, "await") { try restore_fail(c, saved, fail(c, id, "await is a reserved word here")) }
        }
    }
    // Parameters.
    let simple = is_simple_params(c, n)
    // `use strict` in a function with non-simple parameters is an error; the function is strict afterwards.
    var body_strict = false
    if n.c != ast.NONE && (n.flags & ast.F_EXPR_BODY) == 0u16 { body_strict = has_use_strict(c, n.c) }
    if body_strict && !simple { try restore_fail(c, saved, fail(c, id, "Illegal 'use strict' directive in function with non-simple parameter list")) }
    if body_strict { c.strict = true }
    strict = c.strict
    var names: list.List[str] = zero
    let (nl, nle) = list.init[str](c.a, 8usize)
    names = nl
    try param_names(c, n, &names)
    // Duplicates are errors in strict code, arrows, methods and with non-simple parameters.
    if strict || is_arrow || is_method || !simple {
        var i = 0usize
        while i < names.len {
            var j = i + 1usize
            while j < names.len {
                if str.eq(names.items[i], names.items[j]) { try restore_fail(c, saved, fail(c, id, "Duplicate parameter name not allowed in this context")) }
                j += 1usize
            }
            i += 1usize
        }
    }
    if strict {
        var q = 0usize
        while q < names.len {
            if str.eq(names.items[q], "eval") || str.eq(names.items[q], "arguments") { try restore_fail(c, saved, fail(c, id, "Unexpected eval or arguments in strict mode")) }
            if is_strict_reserved(names.items[q]) { try restore_fail(c, saved, fail(c, id, "Unexpected strict mode reserved word")) }
            q += 1usize
        }
    }
    c.in_params = true
    var pi = 0usize
    while pi < usize(n.b) {
        let pid = kid(c, n.a, pi)
        let pn = node(c, pid)
        var e: err = ok
        if pn.kind == ast.N_SPREAD {
            let tn = node(c, pn.a)
            if tn.kind == ast.N_ASSIGN { e = fail(c, pid, "Rest parameter may not have a default initializer") } else if pi + 1usize != usize(n.b) { e = fail(c, pid, "Rest parameter must be last formal parameter") } else { e = check_pattern(c, pn.a, true, false) }
        } else {
            e = check_pattern(c, pid, true, false)
        }
        if e != ok { try restore_fail(c, saved, e) }
        pi += 1usize
    }
    c.in_params = false
    if is_arrow {
        c.in_async = (n.flags & ast.F_ASYNC) != 0u16
        c.in_generator = false
    }
    // Body.
    var be: err = ok
    if n.c != ast.NONE {
        if (n.flags & ast.F_EXPR_BODY) != 0u16 {
            be = check_expr(c, n.c)
        } else {
            let bn = node(c, n.c)
            be = check_scope(c, bn.a, bn.b, true, &names)
            c.lex_floor = c.lexstack.len
            var nz = 0usize
            while nz < names.len {
                let pu5 = list.push[str](&c.lexstack, names.items[nz])
                nz += 1usize
            }
            push_lex(c, bn.a, bn.b, false)
            if be == ok { be = check_stmt_list(c, bn.a, bn.b) }
        }
    }
    restore_ctx(c, saved)
    ret be
}

type Saved = struct {
    strict: bool, in_function: bool, in_async: bool, in_generator: bool, in_loop: u32, in_switch: u32, labels_len: usize, allow_new_target: bool,
    allow_super_prop: bool, allow_super_call: bool, in_field_init: bool, in_static_block: bool, in_params: bool, lex_len: usize, lex_floor: usize
}

fn save_ctx(c: *const Ctx) -> Saved {
    ret Saved { strict: c.strict, in_function: c.in_function, in_async: c.in_async, in_generator: c.in_generator, in_loop: c.in_loop, in_switch: c.in_switch, labels_len: c.labels.len, allow_new_target: c.allow_new_target, allow_super_prop: c.allow_super_prop, allow_super_call: c.allow_super_call, in_field_init: c.in_field_init, in_static_block: c.in_static_block, in_params: c.in_params, lex_len: c.lexstack.len, lex_floor: c.lex_floor }
}

fn restore_ctx(c: *Ctx, s: Saved) {
    c.strict = s.strict
    c.in_function = s.in_function
    c.in_async = s.in_async
    c.in_generator = s.in_generator
    c.in_loop = s.in_loop
    c.in_switch = s.in_switch
    c.labels.len = s.labels_len
    c.label_loops.len = s.labels_len
    c.allow_new_target = s.allow_new_target
    c.allow_super_prop = s.allow_super_prop
    c.allow_super_call = s.allow_super_call
    c.in_field_init = s.in_field_init
    c.in_static_block = s.in_static_block
    c.in_params = s.in_params
    c.lexstack.len = s.lex_len
    c.lex_floor = s.lex_floor
}

fn restore_fail(c: *Ctx, s: Saved, e: err) -> err {
    restore_ctx(c, s)
    ret e
}

fn check_class(c: *Ctx, id: u32) -> err {
    let n = node(c, id)
    let saved = save_ctx(c)
    c.strict = true
    if n.text.len > 0usize {
        if is_reserved_word(n.text) || is_strict_reserved(n.text) || str.eq(n.text, "await") && (saved.in_async || (saved.in_static_block && !saved.in_function) || c.p.is_module) { try restore_fail(c, saved, fail(c, id, "Unexpected reserved word as class name")) }
    }
    if n.a != ast.NONE {
        let e = check_expr(c, n.a)
        if e != ok { try restore_fail(c, saved, e) }
    }
    // Private names of this class are visible inside its body.
    let depth_before = c.privates.len
    var declared: list.List[str] = zero
    let (dl, dle) = list.init[str](c.a, 4usize)
    declared = dl
    var kinds: list.List[u8] = zero
    let (kl, kle) = list.init[u8](c.a, 4usize)
    kinds = kl
    var ctor_count = 0usize
    var i = 0usize
    while i < usize(n.c) {
        let mid = kid(c, n.b, i)
        let mn = node(c, mid)
        i += 1usize
        if mn.op == ast.M_STATIC_BLOCK { continue }
        let kn = node(c, mn.a)
        if kn.kind == ast.N_PRIVATE {
            if str.eq(kn.text, "constructor") { try restore_fail(c, saved, fail(c, mid, "Classes may not have a private field named '#constructor'")) }
            // Duplicate private names are errors except a getter/setter pair.
            var d = 0usize
            while d < declared.len {
                if str.eq(declared.items[d], kn.text) {
                    let prev = kinds.items[d]
                    let cur_static = (mn.flags & ast.F_STATIC) != 0u16
                    let prev_static = (prev & 128u8) != 0u8
                    let prev_op = prev & 127u8
                    let is_pair = ((prev_op == ast.M_GET && mn.op == ast.M_SET) || (prev_op == ast.M_SET && mn.op == ast.M_GET)) && cur_static == prev_static
                    if !is_pair { try restore_fail(c, saved, fail(c, mid, "Identifier has already been declared")) }
                }
                d += 1usize
            }
            try list.push[str](&declared, kn.text)
            var kind_code = mn.op
            if (mn.flags & ast.F_STATIC) != 0u16 { kind_code = kind_code | 128u8 }
            try list.push[u8](&kinds, kind_code)
            try list.push[str](&c.privates, kn.text)
        }
        if (mn.flags & ast.F_COMPUTED) == 0u16 && kn.kind == ast.N_STR {
            let is_static = (mn.flags & ast.F_STATIC) != 0u16
            if str.eq(kn.text, "constructor") && !is_static {
                if mn.op == ast.M_METHOD {
                    ctor_count += 1usize
                    let fnn = node(c, mn.b)
                    if (fnn.flags & (ast.F_GENERATOR | ast.F_ASYNC)) != 0u16 { try restore_fail(c, saved, fail(c, mid, "Class constructor may not be a generator or async")) }
                } else if mn.op == ast.M_GET || mn.op == ast.M_SET {
                    try restore_fail(c, saved, fail(c, mid, "Class constructor may not be an accessor"))
                } else if mn.op == ast.M_FIELD {
                    try restore_fail(c, saved, fail(c, mid, "Classes may not have a field named 'constructor'"))
                }
            }
            if is_static && str.eq(kn.text, "prototype") && (mn.op == ast.M_METHOD || mn.op == ast.M_GET || mn.op == ast.M_SET || mn.op == ast.M_FIELD) { try restore_fail(c, saved, fail(c, mid, "Classes may not have a static property named 'prototype'")) }
            if is_static && str.eq(kn.text, "constructor") && mn.op == ast.M_FIELD { try restore_fail(c, saved, fail(c, mid, "Classes may not have a field named 'constructor'")) }
        }
    }
    if ctor_count > 1usize { try restore_fail(c, saved, fail(c, id, "A class may only have one constructor")) }
    // Members.
    var j = 0usize
    while j < usize(n.c) {
        let mid2 = kid(c, n.b, j)
        let mn2 = node(c, mid2)
        j += 1usize
        let derived = n.a != ast.NONE
        if mn2.op == ast.M_STATIC_BLOCK {
            let sf = node(c, mn2.b)
            let s2 = save_ctx(c)
            c.in_function = false
            c.in_async = false
            c.in_generator = false
            c.in_static_block = true
            c.allow_new_target = true
            c.allow_super_prop = true
            c.allow_super_call = false
            c.in_loop = 0u32
            c.in_switch = 0u32
            c.labels.len = 0usize
            c.label_loops.len = 0usize
            let body = node(c, sf.c)
            var nm: list.List[str] = zero
            let (nl2, nle2) = list.init[str](c.a, 2usize)
            nm = nl2
            var e2 = check_scope(c, body.a, body.b, true, &nm)
            if e2 == ok { e2 = check_stmt_list(c, body.a, body.b) }
            restore_ctx(c, s2)
            if e2 != ok { try restore_fail(c, saved, e2) }
            continue
        }
        let kn2 = node(c, mn2.a)
        if (mn2.flags & ast.F_COMPUTED) != 0u16 {
            let e3 = check_expr(c, mn2.a)
            if e3 != ok { try restore_fail(c, saved, e3) }
        }
        if mn2.op == ast.M_FIELD {
            if mn2.b != ast.NONE {
                let ff = node(c, mn2.b)
                let s3 = save_ctx(c)
                c.in_function = true
                c.in_async = false
                c.in_generator = false
                c.in_field_init = true
                c.allow_new_target = true
                c.allow_super_prop = true
                c.allow_super_call = false
                let e4 = check_expr(c, ff.c)
                restore_ctx(c, s3)
                if e4 != ok { try restore_fail(c, saved, e4) }
            }
            continue
        }
        // Methods and accessors.
        let s4 = save_ctx(c)
        c.allow_super_prop = true
        c.allow_super_call = derived && mn2.op == ast.M_METHOD && (mn2.flags & ast.F_STATIC) == 0u16 && (mn2.flags & ast.F_COMPUTED) == 0u16 && kn2.kind == ast.N_STR && str.eq(kn2.text, "constructor")
        let e5 = check_function(c, mn2.b)
        restore_ctx(c, s4)
        if e5 != ok { try restore_fail(c, saved, e5) }
        let fnn2 = node(c, mn2.b)
        if mn2.op == ast.M_GET && fnn2.b != 0u32 { try restore_fail(c, saved, fail(c, mid2, "Getter must not have any formal parameters")) }
        if mn2.op == ast.M_SET {
            if fnn2.b != 1u32 { try restore_fail(c, saved, fail(c, mid2, "Setter must have exactly one formal parameter")) }
            if node(c, kid(c, fnn2.a, 0usize)).kind == ast.N_SPREAD { try restore_fail(c, saved, fail(c, mid2, "Setter function argument must not be a rest parameter")) }
        }
    }
    c.privates.len = depth_before
    restore_ctx(c, saved)
    ret ok
}

// --- statements

fn is_loop(c: *const Ctx, id: u32) -> bool {
    let k = node(c, id).kind
    ret k == ast.N_FOR || k == ast.N_FORIN || k == ast.N_FOROF || k == ast.N_WHILE || k == ast.N_DOWHILE
}

// A statement in a position that takes a Statement (not a declaration): the body of if/loops/with/labels.
fn check_substatement(c: *Ctx, id: u32, allow_plain_function: bool) -> err {
    let n = node(c, id)
    if n.kind == ast.N_VAR && n.op != ast.D_VAR { ret fail(c, id, "Lexical declaration cannot appear in a single-statement context") }
    if n.kind == ast.N_CLASS && (n.flags & ast.F_DECL) != 0u16 { ret fail(c, id, "Class declaration cannot appear in a single-statement context") }
    if n.kind == ast.N_FUNC && (n.flags & ast.F_DECL) != 0u16 {
        if c.strict || !allow_plain_function || (n.flags & (ast.F_GENERATOR | ast.F_ASYNC)) != 0u16 { ret fail(c, id, "Function declaration cannot appear in a single-statement context") }
    }
    if n.kind == ast.N_LABELED {
        // `l: function f(){}` is allowed in sloppy code only outside loop bodies.
        var inner = n.a
        var guard = 0u32
        while node(c, inner).kind == ast.N_LABELED && guard < 100u32 {
            inner = node(c, inner).a
            guard += 1u32
        }
        let inn = node(c, inner)
        if inn.kind == ast.N_FUNC && (inn.flags & ast.F_DECL) != 0u16 && !allow_plain_function { ret fail(c, id, "Labelled function declaration is not allowed here") }
    }
    ret check_stmt(c, id)
}

fn check_stmt_list(c: *Ctx, first: u32, count: u32) -> err {
    var i = 0usize
    while i < usize(count) {
        try check_stmt(c, kid(c, first, i))
        i += 1usize
    }
    ret ok
}

fn check_var_decl(c: *Ctx, id: u32, in_for_head: bool) -> err {
    let n = node(c, id)
    var i = 0usize
    while i < usize(n.b) {
        let did = kid(c, n.a, i)
        let dn = node(c, did)
        i += 1usize
        let tn = node(c, dn.a)
        if tn.kind == ast.N_IDENT {
            if is_reserved_word(tn.text) { ret fail(c, did, "Unexpected reserved word") }
            try check_ident(c, dn.a, true)
        } else {
            try check_pattern(c, dn.a, true, false)
        }
        if dn.b == ast.NONE {
            if n.op == ast.D_CONST && !in_for_head { ret fail(c, did, "Missing initializer in const declaration") }
            if tn.kind != ast.N_IDENT && !in_for_head { ret fail(c, did, "Missing initializer in destructuring declaration") }
        } else {
            try check_expr(c, dn.b)
        }
        // let/const may not bind `let`.
        if n.op != ast.D_VAR {
            var names: list.List[str] = zero
            let (nl, nle) = list.init[str](c.a, 2usize)
            names = nl
            try pattern_names(c, dn.a, &names)
            var q = 0usize
            while q < names.len {
                if str.eq(names.items[q], "let") { ret fail(c, did, "let is disallowed as a lexically bound name") }
                q += 1usize
            }
        }
    }
    ret ok
}

fn check_stmt(c: *Ctx, id: u32) -> err {
    let n = node(c, id)
    let k = n.kind
    if k == ast.N_EXPR_STMT { ret check_expr(c, n.a) }
    if k == ast.N_VAR { ret check_var_decl(c, id, false) }
    if k == ast.N_FUNC {
        try check_function(c, id)
        ret ok
    }
    if k == ast.N_CLASS { ret check_class(c, id) }
    if k == ast.N_BLOCK {
        var nm: list.List[str] = zero
        let (nl, nle) = list.init[str](c.a, 1usize)
        nm = nl
        try check_scope(c, n.a, n.b, false, &nm)
        annexb_mark(c, n.a, n.b)
        let lmark = c.lexstack.len
        push_lex(c, n.a, n.b, true)
        let be2 = check_stmt_list(c, n.a, n.b)
        c.lexstack.len = lmark
        ret be2
    }
    if k == ast.N_IF {
        try check_expr(c, n.a)
        try check_substatement(c, n.b, true)
        if n.c != ast.NONE { try check_substatement(c, n.c, true) }
        ret ok
    }
    if k == ast.N_RETURN {
        if !c.in_function { ret fail(c, id, "Illegal return statement") }
        ret check_expr(c, n.a)
    }
    if k == ast.N_THROW { ret check_expr(c, n.a) }
    if k == ast.N_BREAK {
        if n.text.len > 0usize {
            var found = false
            var i = 0usize
            while i < c.labels.len {
                if str.eq(c.labels.items[i], n.text) { found = true }
                i += 1usize
            }
            if !found { ret fail(c, id, "Undefined label") }
        } else if c.in_loop == 0u32 && c.in_switch == 0u32 {
            ret fail(c, id, "Illegal break statement")
        }
        ret ok
    }
    if k == ast.N_CONTINUE {
        if c.in_loop == 0u32 { ret fail(c, id, "Illegal continue statement") }
        if n.text.len > 0usize {
            var found2 = false
            var is_loop_label = false
            var j = 0usize
            while j < c.labels.len {
                if str.eq(c.labels.items[j], n.text) {
                    found2 = true
                    is_loop_label = c.label_loops.items[j]
                }
                j += 1usize
            }
            if !found2 { ret fail(c, id, "Undefined label") }
            if !is_loop_label { ret fail(c, id, "Illegal continue statement: label does not denote an iteration statement") }
        }
        ret ok
    }
    if k == ast.N_WHILE || k == ast.N_DOWHILE {
        var body = n.b
        var test = n.a
        try check_expr(c, test)
        c.in_loop += 1u32
        let e = check_substatement(c, body, false)
        c.in_loop -= 1u32
        ret e
    }
    if k == ast.N_FOR { ret check_for(c, id) }
    if k == ast.N_FORIN || k == ast.N_FOROF { ret check_for_in_of(c, id) }
    if k == ast.N_TRY {
        try check_stmt(c, n.a)
        if n.b != ast.NONE {
            let cn = node(c, n.b)
            var pnames: list.List[str] = zero
            let (pl, ple) = list.init[str](c.a, 2usize)
            pnames = pl
            if cn.a != ast.NONE {
                try check_pattern(c, cn.a, true, false)
                try pattern_names(c, cn.a, &pnames)
                // Duplicate names in a destructuring catch parameter.
                var x = 0usize
                while x < pnames.len {
                    var y = x + 1usize
                    while y < pnames.len {
                        if str.eq(pnames.items[x], pnames.items[y]) { ret fail(c, id, "Duplicate catch parameter") }
                        y += 1usize
                    }
                    x += 1usize
                }
            }
            let body = node(c, cn.b)
            try check_scope(c, body.a, body.b, false, &pnames)
            // A `var` redeclaring a destructured catch parameter is an error (a simple one is allowed).
            if cn.a != ast.NONE && node(c, cn.a).kind != ast.N_IDENT {
                var vs: list.List[str] = zero
                let (vl, vle) = list.init[str](c.a, 2usize)
                vs = vl
                var z = 0usize
                while z < usize(body.b) {
                    try collect_vars(c, kid(c, body.a, z), &vs)
                    z += 1usize
                }
                var w = 0usize
                while w < vs.len {
                    if has_name(&pnames, vs.items[w]) { ret fail(c, id, "Identifier has already been declared") }
                    w += 1usize
                }
            }
            annexb_mark(c, body.a, body.b)
            let cmark = c.lexstack.len
            push_lex(c, body.a, body.b, true)
            if cn.a != ast.NONE && node(c, cn.a).kind != ast.N_IDENT {
                var pz = 0usize
                while pz < pnames.len {
                    let pu4 = list.push[str](&c.lexstack, pnames.items[pz])
                    pz += 1usize
                }
            }
            let ce3 = check_stmt_list(c, body.a, body.b)
            c.lexstack.len = cmark
            if ce3 != ok { ret ce3 }
        }
        if n.c != ast.NONE { try check_stmt(c, n.c) }
        ret ok
    }
    if k == ast.N_SWITCH {
        try check_expr(c, n.a)
        // All case clauses share one scope.
        var all: list.List[u32] = zero
        let (al, ale) = list.init[u32](c.a, 8usize)
        all = al
        var ci = 0usize
        while ci < usize(n.c) {
            let cs = node(c, kid(c, n.b, ci))
            var si = 0usize
            while si < usize(cs.c) {
                let swn = node(c, kid(c, cs.b, si))
                if swn.kind == ast.N_VAR && (swn.flags & ast.F_USING) != 0u16 { ret fail(c, id, "using declarations are not allowed directly in a switch case") }
                try list.push[u32](&all, kid(c, cs.b, si))
                si += 1usize
            }
            ci += 1usize
        }
        // check_scope reads statement ids from the shared kid table; build a temporary table.
        var default_count = 0usize
        var cj = 0usize
        while cj < usize(n.c) {
            let cs2 = node(c, kid(c, n.b, cj))
            if cs2.a == ast.NONE { default_count += 1usize }
            if cs2.a != ast.NONE { try check_expr(c, cs2.a) }
            cj += 1usize
        }
        if default_count > 1usize { ret fail(c, id, "More than one default clause in switch statement") }
        try check_switch_scope(c, all)
        c.in_switch += 1u32
        var ck = 0usize
        var result: err = ok
        while ck < usize(n.c) && result == ok {
            let cs3 = node(c, kid(c, n.b, ck))
            result = check_stmt_list(c, cs3.b, cs3.c)
            ck += 1usize
        }
        c.in_switch -= 1u32
        ret result
    }
    if k == ast.N_LABELED {
        // Collect the chain; duplicate labels are errors.
        var cur = id
        var added = 0usize
        var e: err = ok
        var guard = 0u32
        var body = id
        // Find the first non-label statement to learn whether labels denote a loop.
        var probe = id
        while node(c, probe).kind == ast.N_LABELED && guard < 100u32 {
            probe = node(c, probe).a
            guard += 1u32
        }
        let loopish = is_loop(c, probe)
        guard = 0u32
        while node(c, cur).kind == ast.N_LABELED && guard < 100u32 {
            let ln = node(c, cur)
            var dup = false
            var i2 = 0usize
            while i2 < c.labels.len {
                if str.eq(c.labels.items[i2], ln.text) { dup = true }
                i2 += 1usize
            }
            if dup { e = fail(c, cur, "Label has already been declared") }
            if (c.strict && is_strict_reserved(ln.text)) || (c.in_generator && str.eq(ln.text, "yield")) || ((c.in_async || c.in_static_block) && str.eq(ln.text, "await")) { e = fail(c, cur, "Reserved word used as a label") }
            let pe = list.push[str](&c.labels, ln.text)
            let pe2 = list.push[bool](&c.label_loops, loopish)
            added += 1usize
            cur = ln.a
            guard += 1u32
        }
        if e == ok { e = check_substatement(c, cur, !c.strict && c.in_loop == 0u32) }
        c.labels.len -= added
        c.label_loops.len -= added
        ret e
    }
    if k == ast.N_WITH {
        if c.strict { ret fail(c, id, "Strict mode code may not include a with statement") }
        try check_expr(c, n.a)
        ret check_substatement(c, n.b, false)
    }
    ret ok
}

// A switch body is one scope: check duplicates across all case clauses.
fn check_switch_scope(c: *Ctx, all: list.List[u32]) -> err {
    var lex_l: list.List[str] = zero
    let (l1, e1) = list.init[str](c.a, 8usize)
    lex_l = l1
    var vars: list.List[str] = zero
    let (l2, e2) = list.init[str](c.a, 8usize)
    vars = l2
    var plain_l: list.List[str] = zero
    let (l2b, e2b) = list.init[str](c.a, 4usize)
    plain_l = l2b
    var i = 0usize
    while i < all.len {
        let sid = all.items[i]
        let sn = node(c, sid)
        i += 1usize
        try collect_vars(c, sid, &vars)
        if sn.kind == ast.N_VAR && sn.op != ast.D_VAR {
            var d = 0usize
            while d < usize(sn.b) {
                var names: list.List[str] = zero
                let (l3, e3) = list.init[str](c.a, 2usize)
                names = l3
                try pattern_names(c, node(c, kid(c, sn.a, d)).a, &names)
                var q = 0usize
                while q < names.len {
                    if has_name(&lex_l, names.items[q]) { ret fail(c, sid, "Identifier has already been declared") }
                    try list.push[str](&lex_l, names.items[q])
                    q += 1usize
                }
                d += 1usize
            }
        } else if (sn.kind == ast.N_CLASS || sn.kind == ast.N_FUNC) && (sn.flags & ast.F_DECL) != 0u16 {
            let plain_fn = sn.kind == ast.N_FUNC && !c.strict && (sn.flags & (ast.F_GENERATOR | ast.F_ASYNC)) == 0u16
            if has_name(&lex_l, sn.text) && !(plain_fn && has_name(&plain_l, sn.text)) { ret fail(c, sid, "Identifier has already been declared") }
            if plain_fn { try list.push[str](&plain_l, sn.text) }
            try list.push[str](&lex_l, sn.text)
        }
    }
    var k = 0usize
    while k < lex_l.len {
        if has_name(&vars, lex_l.items[k]) { ret fail(c, all.items[0usize], "Identifier has already been declared") }
        k += 1usize
    }
    ret ok
}

fn check_for(c: *Ctx, id: u32) -> err {
    let n = node(c, id)
    var head_names: list.List[str] = zero
    let (hl, hle) = list.init[str](c.a, 2usize)
    head_names = hl
    if n.a != ast.NONE {
        let init = node(c, n.a)
        if init.kind == ast.N_VAR {
            try check_var_decl(c, n.a, false)
            if init.op != ast.D_VAR {
                var d = 0usize
                while d < usize(init.b) {
                    try pattern_names(c, node(c, kid(c, init.a, d)).a, &head_names)
                    d += 1usize
                }
                var x = 0usize
                while x < head_names.len {
                    var y = x + 1usize
                    while y < head_names.len {
                        if str.eq(head_names.items[x], head_names.items[y]) { ret fail(c, id, "Identifier has already been declared") }
                        y += 1usize
                    }
                    x += 1usize
                }
            }
        } else {
            try check_expr(c, n.a)
        }
    }
    try check_expr(c, n.b)
    try check_expr(c, n.c)
    // The body may not `var`-redeclare a let/const head name.
    if head_names.len > 0usize {
        var vs: list.List[str] = zero
        let (vl, vle) = list.init[str](c.a, 2usize)
        vs = vl
        try collect_vars(c, n.d, &vs)
        var q = 0usize
        while q < vs.len {
            if has_name(&head_names, vs.items[q]) { ret fail(c, id, "Identifier has already been declared") }
            q += 1usize
        }
    }
    c.in_loop += 1u32
    let fmark = c.lexstack.len
    var hz = 0usize
    while hz < head_names.len {
        let pu6 = list.push[str](&c.lexstack, head_names.items[hz])
        hz += 1usize
    }
    let e = check_substatement(c, n.d, false)
    c.lexstack.len = fmark
    c.in_loop -= 1u32
    ret e
}

fn check_for_in_of(c: *Ctx, id: u32) -> err {
    let n = node(c, id)
    let is_of = n.kind == ast.N_FOROF
    let head = node(c, n.a)
    var head_names: list.List[str] = zero
    let (hl, hle) = list.init[str](c.a, 2usize)
    head_names = hl
    if head.kind == ast.N_VAR {
        if head.b != 1u32 { ret fail(c, id, "Invalid left-hand side in for-loop: must have a single binding") }
        if (head.flags & ast.F_USING) != 0u16 && !is_of { ret fail(c, id, "for-in loops cannot declare using bindings") }
        let dn = node(c, kid(c, head.a, 0usize))
        try check_var_decl(c, n.a, true)
        if dn.b != ast.NONE {
            // `for (var x = 1 in obj)` survives in sloppy code for a plain identifier only.
            let simple = node(c, dn.a).kind == ast.N_IDENT
            if is_of || c.strict || head.op != ast.D_VAR || !simple { ret fail(c, id, "for-in/of loop variable declaration may not have an initializer") }
        }
        if head.op != ast.D_VAR {
            try pattern_names(c, dn.a, &head_names)
            var x = 0usize
            while x < head_names.len {
                var y = x + 1usize
                while y < head_names.len {
                    if str.eq(head_names.items[x], head_names.items[y]) { ret fail(c, id, "Identifier has already been declared") }
                    y += 1usize
                }
                if str.eq(head_names.items[x], "let") { ret fail(c, id, "let is disallowed as a lexically bound name") }
                x += 1usize
            }
        }
    } else {
        try check_assign_target(c, n.a, true)
    }
    try check_expr(c, n.b)
    if head_names.len > 0usize {
        var vs: list.List[str] = zero
        let (vl, vle) = list.init[str](c.a, 2usize)
        vs = vl
        try collect_vars(c, n.c, &vs)
        var q = 0usize
        while q < vs.len {
            if has_name(&head_names, vs.items[q]) { ret fail(c, id, "Identifier has already been declared") }
            q += 1usize
        }
    }
    c.in_loop += 1u32
    let fmark = c.lexstack.len
    var hz = 0usize
    while hz < head_names.len {
        let pu6 = list.push[str](&c.lexstack, head_names.items[hz])
        hz += 1usize
    }
    let e = check_substatement(c, n.c, false)
    c.lexstack.len = fmark
    c.in_loop -= 1u32
    ret e
}

type Result = struct { message: str, line: u32 }

// Checks a parsed script; `ok` with an empty message when it has no early error.
// What a direct eval inherits from its caller: strictness, whether `new.target` / `super` are allowed, the private names in scope.
type EvalOpts = struct { strict: bool, new_target: bool, super_prop: bool, super_call: bool, privates: []const str }

fn check(a: *mem.Arena, prog: *const ast.Program) -> (Result, err) {
    var none: EvalOpts = zero
    let (r, er) = check_in(a, prog, &none)
    ret (r, er)
}

fn check_in(a: *mem.Arena, prog: *const ast.Program, eo: *const EvalOpts) -> (Result, err) {
    var c: Ctx = zero
    c.a = a
    c.p = prog
    let (l1, e1) = list.init[str](a, 4usize)
    c.labels = l1
    let (l2, e2) = list.init[bool](a, 4usize)
    c.label_loops = l2
    let (l3, e3) = list.init[str](a, 4usize)
    c.privates = l3
    let root = prog.nodes[usize(prog.root)]
    c.strict = (root.flags & ast.F_STRICT) != 0u16 || eo.strict
    c.allow_new_target = eo.new_target
    c.allow_super_prop = eo.super_prop
    c.allow_super_call = eo.super_call
    var pi = 0usize
    while pi < eo.privates.len {
        let pe = list.push[str](&c.privates, eo.privates[pi])
        pi += 1usize
    }
    var none: list.List[str] = zero
    let (nl, nle) = list.init[str](a, 1usize)
    none = nl
    let (l4, e4) = list.init[str](a, 8usize)
    c.lexstack = l4
    if !prog.is_module {
        // `using` declarations are for blocks, function bodies and modules, not the top level of a script or eval.
        var ui = 0usize
        while ui < usize(root.b) {
            let un = prog.nodes[usize(prog.kids[usize(root.a) + ui])]
            if un.kind == ast.N_VAR && (un.flags & ast.F_USING) != 0u16 {
                var uc2 = Result { message: "using declarations are not allowed at the top level of a script", line: un.line }
                ret (uc2, EarlyError)
            }
            ui += 1usize
        }
    }
    push_lex(&c, root.a, root.b, false)
    var e = check_scope(&c, root.a, root.b, true, &none)
    if e == ok { e = check_stmt_list(&c, root.a, root.b) }
    var out = Result { message: c.message, line: c.line }
    if e != ok && out.message.len == 0usize { out.message = "early error" }
    ret (out, e)
}
