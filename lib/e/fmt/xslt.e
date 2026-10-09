// XSLT 1.0 over `e.fmt.xml` and `e.fmt.xpath`. `load` compiles a stylesheet document into templates,
// instructions and compiled XPath expressions in an arena; `transform` runs it against a source document
// and answers the serialized result.
//
// Covered: xsl:template (match with unions, priorities and conflict resolution, name, mode, params),
// apply-templates (select, mode, sort, with-param), call-template, the built-in rules, for-each, if, choose,
// variable and param (select or content, the latter a result tree fragment), value-of, text, element,
// attribute, comment, processing-instruction, copy, copy-of, sort (data-type, order), message, literal
// result elements with attribute value templates and the stylesheet's in-scope namespaces, xsl:output
// (method xml or text, omit-xml-declaration, encoding is always UTF-8), global variables and parameters,
// and the XPath extensions current() and generate-id(). Namespaces in the result are fixed up on output:
// every element and attribute is declared under the prefix it has.
// Refused at load (`Unsupported`): import, include, key, attribute-set, decimal-format, namespace-alias,
// strip-space and preserve-space, number, apply-imports, fallback and html output; and a result
// tree fragment is only usable as a string or through copy-of, as in XSLT 1.0.

use e.fmt.xml as xml
use e.fmt.xpath as xp
use e.mem
use e.str

error Invalid
error Unsupported
error NoRule
error Terminated
error TooComplex

const NONE: u32 = 4294967295u32

fn xsl_namespace() -> str { ret "http://www.w3.org/1999/XSL/Transform" }

type Avt = struct { literals: []str, exprs: []u32, count: usize }

type Sort = struct { select: u32, numeric: bool, descending: bool }
type WithParam = struct { name: str, select: u32, body: []u32, has_select: bool }

type Instr = struct {
    kind: u8, name: str, expr: u32, expr_b: u32,
    name_avt: Avt, namespace_avt: Avt, attr_names: []str, attr_avts: []Avt, declared: []xp.Binding, scope: []xp.Binding,
    children: []u32, sorts: []Sort, with_params: []WithParam, mode: str, has_mode: bool, node: xml.NodeId,
}

type Param = struct { name: str, select: u32, body: []u32, has_select: bool }

type Template = struct { name: str, has_name: bool, mode: str, body: []u32, params: []Param }
type Rule = struct { expr: u32, priority: f64, template: u32, order: u32, mode: str }

type Output = struct { text: str, omit_declaration: bool, is_text: bool }

type Stylesheet = struct {
    instrs: []Instr, instr_count: usize, exprs: []xp.Compiled, expr_count: usize,
    templates: []Template, template_count: usize, rules: []Rule, rule_count: usize,
    globals: []Param, global_count: usize, output: Output, document: xml.Document,
}

// Instruction kinds.
const I_TEXT: u8 = 1u8
const I_LRE: u8 = 2u8
const I_VALUE_OF: u8 = 3u8
const I_APPLY: u8 = 4u8
const I_CALL: u8 = 5u8
const I_FOR_EACH: u8 = 6u8
const I_IF: u8 = 7u8
const I_CHOOSE: u8 = 8u8
const I_WHEN: u8 = 9u8
const I_OTHERWISE: u8 = 10u8
const I_VARIABLE: u8 = 11u8
const I_ELEMENT: u8 = 12u8
const I_ATTRIBUTE: u8 = 13u8
const I_COMMENT: u8 = 14u8
const I_PI: u8 = 15u8
const I_COPY: u8 = 16u8
const I_COPY_OF: u8 = 17u8
const I_MESSAGE: u8 = 18u8
const I_XSL_TEXT: u8 = 19u8

fn same(a: str, b: str) -> bool { ret str.eq(a, b) }

// ---- stylesheet DOM helpers ----

fn node_of(d: *const xml.Document, id: xml.NodeId) -> xml.Node { ret d.nodes[usize(id)] }

fn split_name(name: str) -> (str, str) {
    let (at, found) = str.find(name, ":")
    if !found { ret ("", name) }
    ret (name[..at], name[at + 1usize..])
}

fn is_xsl(d: *const xml.Document, id: xml.NodeId, local: str) -> bool {
    let n = node_of(d, id)
    if n.kind != .Element { ret false }
    let (prefix, name) = split_name(n.name)
    if !same(name, local) { ret false }
    let (uri, found) = xp.resolve_prefix(d, id, prefix)
    ret found && same(uri, xsl_namespace())
}

fn xsl_local(d: *const xml.Document, id: xml.NodeId) -> (str, bool) {
    let n = node_of(d, id)
    if n.kind != .Element { ret ("", false) }
    let (prefix, name) = split_name(n.name)
    let (uri, found) = xp.resolve_prefix(d, id, prefix)
    if found && same(uri, xsl_namespace()) { ret (name, true) }
    ret ("", false)
}

fn attr_value(d: *const xml.Document, id: xml.NodeId, name: str) -> (str, bool) {
    let n = node_of(d, id)
    let (value, found) = xml.attribute(&n, name)
    ret (value, found)
}

fn first_child(d: *const xml.Document, id: xml.NodeId) -> xml.NodeId { ret node_of(d, id).first_child }
fn next_sibling(d: *const xml.Document, id: xml.NodeId) -> xml.NodeId { ret node_of(d, id).next_sibling }

fn is_blank_text(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if !(c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8) { ret false }
        i += 1usize
    }
    ret true
}

// The prefix bindings in scope at stylesheet element `id`, innermost first, excluding the XSLT namespace.
fn scope_bindings(a: *mem.Arena, d: *const xml.Document, id: xml.NodeId) -> ([]xp.Binding, err) {
    var count = 0usize
    var at = id
    while at != NONE {
        let n = node_of(d, at)
        if n.kind == .Element {
            var i = 0usize
            while i < n.attributes.len {
                let name = n.attributes[i].name
                if same(name, "xmlns") || str.starts_with(name, "xmlns:") { count += 1usize }
                i += 1usize
            }
        }
        at = n.parent
    }
    if count == 0usize { ret (zero, ok) }
    let (list, alloc_error) = mem.alloc[xp.Binding](a, count)
    if alloc_error != ok { ret (zero, alloc_error) }
    var used = 0usize
    at = id
    while at != NONE {
        let n = node_of(d, at)
        if n.kind == .Element {
            var i = 0usize
            while i < n.attributes.len {
                let name = n.attributes[i].name
                var prefix = ""
                var is_decl = false
                if same(name, "xmlns") { is_decl = true } else if str.starts_with(name, "xmlns:") {
                    is_decl = true
                    prefix = name[6usize..]
                }
                if is_decl {
                    // an inner declaration shadows an outer one with the same prefix
                    var shadowed = false
                    var k = 0usize
                    while k < used {
                        if same(list[k].prefix, prefix) { shadowed = true }
                        k += 1usize
                    }
                    if !shadowed {
                        list[used] = xp.Binding { prefix: prefix, uri: n.attributes[i].value }
                        used += 1usize
                    }
                }
                i += 1usize
            }
        }
        at = n.parent
    }
    ret (list[..used], ok)
}

// ---- compilation ----

type Compiler = struct {
    a: *mem.Arena, d: *const xml.Document, s: Stylesheet, excluded: []str, order: u32,
}

fn add_expr(c: *Compiler, id: xml.NodeId, text: str) -> (u32, err) {
    if c.s.expr_count >= c.s.exprs.len { ret (NONE, TooComplex) }
    let (scope, scope_error) = scope_bindings(c.a, c.d, id)
    if scope_error != ok { ret (NONE, scope_error) }
    let (compiled, compile_error) = xp.compile(c.a, text, scope)
    if compile_error != ok { ret (NONE, Invalid) }
    let at = c.s.expr_count
    c.s.exprs[at] = compiled
    c.s.expr_count += 1usize
    ret (u32(at), ok)
}

fn new_instr(c: *Compiler, kind: u8, id: xml.NodeId) -> (u32, err) {
    if c.s.instr_count >= c.s.instrs.len { ret (NONE, TooComplex) }
    let at = c.s.instr_count
    c.s.instrs[at] = Instr {
        kind: kind, name: "", expr: NONE, expr_b: NONE,
        name_avt: Avt { literals: zero, exprs: zero, count: 0usize }, namespace_avt: Avt { literals: zero, exprs: zero, count: 0usize },
        attr_names: zero, attr_avts: zero, declared: zero, scope: zero,
        children: zero, sorts: zero, with_params: zero, mode: "", has_mode: false, node: id,
    }
    c.s.instr_count += 1usize
    ret (u32(at), ok)
}

// An attribute value template `a{expr}b{{c}}` into literal and expression parts.
fn compile_avt(c: *Compiler, id: xml.NodeId, text: str) -> (Avt, err) {
    // count the expressions first
    var pieces = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == 123u8 {
            if i + 1usize < text.len && text[i + 1usize] == 123u8 {
                i += 2usize
                continue
            }
            pieces += 1usize
        }
        i += 1usize
    }
    let (literals, literals_error) = mem.alloc[str](c.a, pieces + 1usize)
    if literals_error != ok { ret (zero, literals_error) }
    let (exprs, exprs_error) = mem.alloc[u32](c.a, pieces + 1usize)
    if exprs_error != ok { ret (zero, exprs_error) }
    var count = 0usize
    var lit_start = 0usize
    var buffer: [4096]u8 = zero
    var used = 0usize
    i = 0usize
    while i < text.len {
        let ch = text[i]
        if ch == 123u8 {
            if i + 1usize < text.len && text[i + 1usize] == 123u8 {
                buffer[used] = 123u8
                used += 1usize
                i += 2usize
                continue
            }
            // the literal so far, then the expression up to the matching close brace
            let (lit, lit_error) = mem.alloc[u8](c.a, used)
            if lit_error != ok { ret (zero, lit_error) }
            var k = 0usize
            while k < used {
                lit[k] = buffer[k]
                k += 1usize
            }
            used = 0usize
            var j = i + 1usize
            var in_quote = 0u8
            while j < text.len {
                if in_quote != 0u8 {
                    if text[j] == in_quote { in_quote = 0u8 }
                } else if text[j] == 39u8 || text[j] == 34u8 {
                    in_quote = text[j]
                } else if text[j] == 125u8 {
                    break
                }
                j += 1usize
            }
            if j >= text.len { ret (zero, Invalid) }
            let (expr, expr_error) = add_expr(c, id, text[i + 1usize..j])
            if expr_error != ok { ret (zero, expr_error) }
            literals[count] = lit
            exprs[count] = expr
            count += 1usize
            i = j + 1usize
            continue
        }
        if ch == 125u8 {
            if i + 1usize < text.len && text[i + 1usize] == 125u8 {
                buffer[used] = 125u8
                used += 1usize
                i += 2usize
                continue
            }
            ret (zero, Invalid)
        }
        if used >= 4096usize { ret (zero, TooComplex) }
        buffer[used] = ch
        used += 1usize
        i += 1usize
    }
    let (tail, tail_error) = mem.alloc[u8](c.a, used)
    if tail_error != ok { ret (zero, tail_error) }
    var k = 0usize
    while k < used {
        tail[k] = buffer[k]
        k += 1usize
    }
    literals[count] = tail
    exprs[count] = NONE
    count += 1usize
    ret (Avt { literals: literals, exprs: exprs, count: count }, ok)
}

fn static_avt(c: *Compiler, text: str) -> (Avt, err) {
    let (literals, literals_error) = mem.alloc[str](c.a, 1usize)
    if literals_error != ok { ret (zero, literals_error) }
    let (exprs, exprs_error) = mem.alloc[u32](c.a, 1usize)
    if exprs_error != ok { ret (zero, exprs_error) }
    literals[0usize] = text
    exprs[0usize] = NONE
    ret (Avt { literals: literals, exprs: exprs, count: 1usize }, ok)
}

fn count_content(c: *const Compiler, id: xml.NodeId) -> usize {
    var count = 0usize
    var at = first_child(c.d, id)
    while at != NONE {
        let n = node_of(c.d, at)
        if n.kind == .Element || (n.kind == .Text && !is_blank_text(n.value)) { count += 1usize }
        at = n.next_sibling
    }
    ret count
}

fn is_excluded(c: *const Compiler, prefix: str) -> bool {
    var i = 0usize
    while i < c.excluded.len {
        if same(c.excluded[i], prefix) { ret true }
        i += 1usize
    }
    ret false
}

// Compile the content of `id` (its children) as an instruction sequence.
fn compile_body(c: *Compiler, id: xml.NodeId, xsl_text_whitespace: bool) -> ([]u32, err) {
    let count = count_content(c, id) + 1usize
    let (list, list_error) = mem.alloc[u32](c.a, count)
    if list_error != ok { ret (zero, list_error) }
    var used = 0usize
    var at = first_child(c.d, id)
    while at != NONE {
        let n = node_of(c.d, at)
        if n.kind == .Text {
            if xsl_text_whitespace || !is_blank_text(n.value) {
                let (made, made_error) = new_instr(c, I_TEXT, at)
                if made_error != ok { ret (zero, made_error) }
                c.s.instrs[usize(made)].name = n.value
                list[used] = made
                used += 1usize
            }
        } else if n.kind == .Element {
            let (made, made_error) = compile_instruction(c, at)
            if made_error != ok { ret (zero, made_error) }
            if made != NONE {
                list[used] = made
                used += 1usize
            }
        }
        at = n.next_sibling
    }
    ret (list[..used], ok)
}

fn compile_sorts(c: *Compiler, id: xml.NodeId) -> ([]Sort, err) {
    var count = 0usize
    var at = first_child(c.d, id)
    while at != NONE {
        if is_xsl(c.d, at, "sort") { count += 1usize }
        at = next_sibling(c.d, at)
    }
    if count == 0usize { ret (zero, ok) }
    let (list, list_error) = mem.alloc[Sort](c.a, count)
    if list_error != ok { ret (zero, list_error) }
    var used = 0usize
    at = first_child(c.d, id)
    while at != NONE {
        if is_xsl(c.d, at, "sort") {
            let (select_text, has_select) = attr_value(c.d, at, "select")
            var text = "."
            if has_select { text = select_text }
            let (expr, expr_error) = add_expr(c, at, text)
            if expr_error != ok { ret (zero, expr_error) }
            let (data_type, _) = attr_value(c.d, at, "data-type")
            let (order, _) = attr_value(c.d, at, "order")
            list[used] = Sort { select: expr, numeric: same(data_type, "number"), descending: same(order, "descending") }
            used += 1usize
        }
        at = next_sibling(c.d, at)
    }
    ret (list[..used], ok)
}

fn compile_with_params(c: *Compiler, id: xml.NodeId) -> ([]WithParam, err) {
    var count = 0usize
    var at = first_child(c.d, id)
    while at != NONE {
        if is_xsl(c.d, at, "with-param") { count += 1usize }
        at = next_sibling(c.d, at)
    }
    if count == 0usize { ret (zero, ok) }
    let (list, list_error) = mem.alloc[WithParam](c.a, count)
    if list_error != ok { ret (zero, list_error) }
    var used = 0usize
    at = first_child(c.d, id)
    while at != NONE {
        if is_xsl(c.d, at, "with-param") {
            let (name, has_name) = attr_value(c.d, at, "name")
            if !has_name { ret (zero, Invalid) }
            let (select_text, has_select) = attr_value(c.d, at, "select")
            var wp = WithParam { name: name, select: NONE, body: zero, has_select: has_select }
            if has_select {
                let (expr, expr_error) = add_expr(c, at, select_text)
                if expr_error != ok { ret (zero, expr_error) }
                wp.select = expr
            } else {
                let (body, body_error) = compile_body(c, at, false)
                if body_error != ok { ret (zero, body_error) }
                wp.body = body
            }
            list[used] = wp
            used += 1usize
        }
        at = next_sibling(c.d, at)
    }
    ret (list[..used], ok)
}

fn compile_instruction(c: *Compiler, id: xml.NodeId) -> (u32, err) {
    let (local, is_xsl_element) = xsl_local(c.d, id)
    if !is_xsl_element {
        let (literal, literal_error) = compile_literal(c, id)
        ret (literal, literal_error)
    }
    if same(local, "text") {
        let (made, made_error) = new_instr(c, I_XSL_TEXT, id)
        if made_error != ok { ret (NONE, made_error) }
        var buffer = ""
        var at = first_child(c.d, id)
        while at != NONE {
            if node_of(c.d, at).kind == .Text {
                let (joined, join_error) = str.concat(c.a, buffer, node_of(c.d, at).value)
                if join_error != ok { ret (NONE, join_error) }
                buffer = joined
            }
            at = next_sibling(c.d, at)
        }
        c.s.instrs[usize(made)].name = buffer
        ret (made, ok)
    }
    if same(local, "value-of") {
        let (select_text, has_select) = attr_value(c.d, id, "select")
        if !has_select { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_VALUE_OF, id)
        if made_error != ok { ret (NONE, made_error) }
        let (expr, expr_error) = add_expr(c, id, select_text)
        if expr_error != ok { ret (NONE, expr_error) }
        c.s.instrs[usize(made)].expr = expr
        ret (made, ok)
    }
    if same(local, "apply-templates") {
        let (made, made_error) = new_instr(c, I_APPLY, id)
        if made_error != ok { ret (NONE, made_error) }
        let (select_text, has_select) = attr_value(c.d, id, "select")
        var text = "child::node()"
        if has_select { text = select_text }
        let (expr, expr_error) = add_expr(c, id, text)
        if expr_error != ok { ret (NONE, expr_error) }
        let (mode, has_mode) = attr_value(c.d, id, "mode")
        let (sorts, sorts_error) = compile_sorts(c, id)
        if sorts_error != ok { ret (NONE, sorts_error) }
        let (params, params_error) = compile_with_params(c, id)
        if params_error != ok { ret (NONE, params_error) }
        c.s.instrs[usize(made)].expr = expr
        c.s.instrs[usize(made)].mode = mode
        c.s.instrs[usize(made)].has_mode = has_mode
        c.s.instrs[usize(made)].sorts = sorts
        c.s.instrs[usize(made)].with_params = params
        ret (made, ok)
    }
    if same(local, "call-template") {
        let (name, has_name) = attr_value(c.d, id, "name")
        if !has_name { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_CALL, id)
        if made_error != ok { ret (NONE, made_error) }
        let (params, params_error) = compile_with_params(c, id)
        if params_error != ok { ret (NONE, params_error) }
        c.s.instrs[usize(made)].name = name
        c.s.instrs[usize(made)].with_params = params
        ret (made, ok)
    }
    if same(local, "for-each") {
        let (select_text, has_select) = attr_value(c.d, id, "select")
        if !has_select { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_FOR_EACH, id)
        if made_error != ok { ret (NONE, made_error) }
        let (expr, expr_error) = add_expr(c, id, select_text)
        if expr_error != ok { ret (NONE, expr_error) }
        let (sorts, sorts_error) = compile_sorts(c, id)
        if sorts_error != ok { ret (NONE, sorts_error) }
        let (body, body_error) = compile_body_skipping_sort(c, id)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].expr = expr
        c.s.instrs[usize(made)].sorts = sorts
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "if") {
        let (test_text, has_test) = attr_value(c.d, id, "test")
        if !has_test { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_IF, id)
        if made_error != ok { ret (NONE, made_error) }
        let (expr, expr_error) = add_expr(c, id, test_text)
        if expr_error != ok { ret (NONE, expr_error) }
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].expr = expr
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "choose") {
        let (made, made_error) = new_instr(c, I_CHOOSE, id)
        if made_error != ok { ret (NONE, made_error) }
        var count = 0usize
        var at = first_child(c.d, id)
        while at != NONE {
            if node_of(c.d, at).kind == .Element { count += 1usize }
            at = next_sibling(c.d, at)
        }
        let (list, list_error) = mem.alloc[u32](c.a, count + 1usize)
        if list_error != ok { ret (NONE, list_error) }
        var used = 0usize
        at = first_child(c.d, id)
        while at != NONE {
            if node_of(c.d, at).kind == .Element {
                let (child_local, child_xsl) = xsl_local(c.d, at)
                if !child_xsl || !(same(child_local, "when") || same(child_local, "otherwise")) { ret (NONE, Invalid) }
                var kind = I_OTHERWISE
                var expr = NONE
                if same(child_local, "when") {
                    kind = I_WHEN
                    let (test_text, has_test) = attr_value(c.d, at, "test")
                    if !has_test { ret (NONE, Invalid) }
                    let (e, e_error) = add_expr(c, at, test_text)
                    if e_error != ok { ret (NONE, e_error) }
                    expr = e
                }
                let (branch, branch_error) = new_instr(c, kind, at)
                if branch_error != ok { ret (NONE, branch_error) }
                let (body, body_error) = compile_body(c, at, false)
                if body_error != ok { ret (NONE, body_error) }
                c.s.instrs[usize(branch)].expr = expr
                c.s.instrs[usize(branch)].children = body
                list[used] = branch
                used += 1usize
            }
            at = next_sibling(c.d, at)
        }
        c.s.instrs[usize(made)].children = list[..used]
        ret (made, ok)
    }
    if same(local, "variable") || same(local, "param") {
        // a local `param` outside a template head behaves as a variable
        let (name, has_name) = attr_value(c.d, id, "name")
        if !has_name { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_VARIABLE, id)
        if made_error != ok { ret (NONE, made_error) }
        c.s.instrs[usize(made)].name = name
        let (select_text, has_select) = attr_value(c.d, id, "select")
        if has_select {
            let (expr, expr_error) = add_expr(c, id, select_text)
            if expr_error != ok { ret (NONE, expr_error) }
            c.s.instrs[usize(made)].expr = expr
        } else {
            let (body, body_error) = compile_body(c, id, false)
            if body_error != ok { ret (NONE, body_error) }
            c.s.instrs[usize(made)].children = body
        }
        ret (made, ok)
    }
    if same(local, "element") || same(local, "attribute") {
        let (name_text, has_name) = attr_value(c.d, id, "name")
        if !has_name { ret (NONE, Invalid) }
        var kind = I_ELEMENT
        if same(local, "attribute") { kind = I_ATTRIBUTE }
        let (made, made_error) = new_instr(c, kind, id)
        if made_error != ok { ret (NONE, made_error) }
        let (name_avt, name_error) = compile_avt(c, id, name_text)
        if name_error != ok { ret (NONE, name_error) }
        c.s.instrs[usize(made)].name_avt = name_avt
        let (ns_text, has_ns) = attr_value(c.d, id, "namespace")
        if has_ns {
            let (ns_avt, ns_error) = compile_avt(c, id, ns_text)
            if ns_error != ok { ret (NONE, ns_error) }
            c.s.instrs[usize(made)].namespace_avt = ns_avt
            c.s.instrs[usize(made)].has_mode = true
        }
        let (scope, scope_error) = scope_bindings(c.a, c.d, id)
        if scope_error != ok { ret (NONE, scope_error) }
        c.s.instrs[usize(made)].scope = scope
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "comment") {
        let (made, made_error) = new_instr(c, I_COMMENT, id)
        if made_error != ok { ret (NONE, made_error) }
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "processing-instruction") {
        let (name_text, has_name) = attr_value(c.d, id, "name")
        if !has_name { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_PI, id)
        if made_error != ok { ret (NONE, made_error) }
        let (name_avt, name_error) = compile_avt(c, id, name_text)
        if name_error != ok { ret (NONE, name_error) }
        c.s.instrs[usize(made)].name_avt = name_avt
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "copy") {
        let (made, made_error) = new_instr(c, I_COPY, id)
        if made_error != ok { ret (NONE, made_error) }
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "copy-of") {
        let (select_text, has_select) = attr_value(c.d, id, "select")
        if !has_select { ret (NONE, Invalid) }
        let (made, made_error) = new_instr(c, I_COPY_OF, id)
        if made_error != ok { ret (NONE, made_error) }
        let (expr, expr_error) = add_expr(c, id, select_text)
        if expr_error != ok { ret (NONE, expr_error) }
        c.s.instrs[usize(made)].expr = expr
        ret (made, ok)
    }
    if same(local, "message") {
        let (made, made_error) = new_instr(c, I_MESSAGE, id)
        if made_error != ok { ret (NONE, made_error) }
        let (terminate, _) = attr_value(c.d, id, "terminate")
        c.s.instrs[usize(made)].name = terminate
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (NONE, body_error) }
        c.s.instrs[usize(made)].children = body
        ret (made, ok)
    }
    if same(local, "sort") || same(local, "with-param") { ret (NONE, ok) }
    ret (NONE, Unsupported)
}

fn compile_body_skipping_sort(c: *Compiler, id: xml.NodeId) -> ([]u32, err) {
    let (body, body_error) = compile_body(c, id, false)
    ret (body, body_error)
}

// A literal result element: its attributes as templates and the stylesheet's in-scope namespaces.
fn compile_literal(c: *Compiler, id: xml.NodeId) -> (u32, err) {
    let n = node_of(c.d, id)
    let (made, made_error) = new_instr(c, I_LRE, id)
    if made_error != ok { ret (NONE, made_error) }
    c.s.instrs[usize(made)].name = n.name
    var plain = 0usize
    var i = 0usize
    while i < n.attributes.len {
        let name = n.attributes[i].name
        if !(same(name, "xmlns") || str.starts_with(name, "xmlns:")) {
            let (prefix, local) = split_name(name)
            let (uri, _) = xp.resolve_prefix(c.d, id, prefix)
            if !(prefix.len > 0usize && same(uri, xsl_namespace())) { plain += 1usize }
        }
        i += 1usize
    }
    let (names, names_error) = mem.alloc[str](c.a, plain + 1usize)
    if names_error != ok { ret (NONE, names_error) }
    let (avts, avts_error) = mem.alloc[Avt](c.a, plain + 1usize)
    if avts_error != ok { ret (NONE, avts_error) }
    var used = 0usize
    i = 0usize
    while i < n.attributes.len {
        let name = n.attributes[i].name
        if !(same(name, "xmlns") || str.starts_with(name, "xmlns:")) {
            let (prefix, local) = split_name(name)
            let (uri, _) = xp.resolve_prefix(c.d, id, prefix)
            if !(prefix.len > 0usize && same(uri, xsl_namespace())) {
                let (avt, avt_error) = compile_avt(c, id, n.attributes[i].value)
                if avt_error != ok { ret (NONE, avt_error) }
                names[used] = name
                avts[used] = avt
                used += 1usize
            }
        }
        i += 1usize
    }
    c.s.instrs[usize(made)].attr_names = names[..used]
    c.s.instrs[usize(made)].attr_avts = avts[..used]
    // in-scope namespaces (innermost first), minus the XSLT namespace and excluded prefixes
    let (scope, scope_error) = scope_bindings(c.a, c.d, id)
    if scope_error != ok { ret (NONE, scope_error) }
    let (declared, declared_error) = mem.alloc[xp.Binding](c.a, scope.len + 1usize)
    if declared_error != ok { ret (NONE, declared_error) }
    var kept = 0usize
    var k = 0usize
    while k < scope.len {
        if !same(scope[k].uri, xsl_namespace()) && !is_excluded(c, scope[k].prefix) {
            declared[kept] = scope[k]
            kept += 1usize
        }
        k += 1usize
    }
    c.s.instrs[usize(made)].declared = declared[..kept]
    c.s.instrs[usize(made)].scope = scope
    let (body, body_error) = compile_body(c, id, false)
    if body_error != ok { ret (NONE, body_error) }
    c.s.instrs[usize(made)].children = body
    ret (made, ok)
}

// ---- patterns and rules ----

// Split a match pattern at top-level `|`.
fn split_pattern(a: *mem.Arena, text: str) -> ([]str, err) {
    var count = 1usize
    var i = 0usize
    var depth = 0usize
    var quote = 0u8
    while i < text.len {
        let ch = text[i]
        if quote != 0u8 {
            if ch == quote { quote = 0u8 }
        } else if ch == 39u8 || ch == 34u8 {
            quote = ch
        } else if ch == 91u8 || ch == 40u8 {
            depth += 1usize
        } else if ch == 93u8 || ch == 41u8 {
            if depth > 0usize { depth -= 1usize }
        } else if ch == 124u8 && depth == 0usize {
            count += 1usize
        }
        i += 1usize
    }
    let (parts, alloc_error) = mem.alloc[str](a, count)
    if alloc_error != ok { ret (zero, alloc_error) }
    var used = 0usize
    var start = 0usize
    i = 0usize
    depth = 0usize
    quote = 0u8
    while i <= text.len {
        var cut = i == text.len
        if !cut {
            let ch = text[i]
            if quote != 0u8 {
                if ch == quote { quote = 0u8 }
            } else if ch == 39u8 || ch == 34u8 {
                quote = ch
            } else if ch == 91u8 || ch == 40u8 {
                depth += 1usize
            } else if ch == 93u8 || ch == 41u8 {
                if depth > 0usize { depth -= 1usize }
            } else if ch == 124u8 && depth == 0usize {
                cut = true
            }
        }
        if cut {
            parts[used] = str.trim(text[start..i])
            used += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret (parts[..used], ok)
}

// The default priority of a single pattern alternative (XSLT 1.0 section 5.5).
fn default_priority(compiled: *const xp.Compiled) -> f64 {
    let root = compiled.exprs[usize(compiled.root)]
    if root.kind != xp.E_PATH || root.absolute || root.left != NONE || root.steps.len != 1usize { ret 0.5f64 }
    let step = root.steps[0usize]
    if step.preds.len > 0usize { ret 0.5f64 }
    if step.axis != xp.A_CHILD && step.axis != xp.A_ATTRIBUTE { ret 0.5f64 }
    if step.test == xp.T_NAME { ret 0.0f64 }
    if step.test == xp.T_PREFIX_ANY { ret -0.25f64 }
    if step.test == xp.T_PI && step.local.len > 0usize { ret 0.0f64 }
    ret -0.5f64
}

fn add_rule(c: *Compiler, id: xml.NodeId, match_text: str, priority_text: str, has_priority: bool, template: u32, mode: str) -> err {
    let (alts, alts_error) = split_pattern(c.a, match_text)
    if alts_error != ok { ret alts_error }
    var i = 0usize
    while i < alts.len {
        if c.s.rule_count >= c.s.rules.len { ret TooComplex }
        let (expr, expr_error) = add_expr(c, id, alts[i])
        if expr_error != ok { ret expr_error }
        var priority = default_priority(&c.s.exprs[usize(expr)])
        if has_priority {
            let n = xp.text_number(priority_text)
            if n == n { priority = n }
        }
        c.s.rules[c.s.rule_count] = Rule { expr: expr, priority: priority, template: template, order: c.order, mode: mode }
        c.s.rule_count += 1usize
        c.order += 1u32
        i += 1usize
    }
    ret ok
}

fn compile_param(c: *Compiler, id: xml.NodeId) -> (Param, err) {
    let (name, has_name) = attr_value(c.d, id, "name")
    if !has_name { ret (zero, Invalid) }
    let (select_text, has_select) = attr_value(c.d, id, "select")
    var p = Param { name: name, select: NONE, body: zero, has_select: has_select }
    if has_select {
        let (expr, expr_error) = add_expr(c, id, select_text)
        if expr_error != ok { ret (zero, expr_error) }
        p.select = expr
    } else {
        let (body, body_error) = compile_body(c, id, false)
        if body_error != ok { ret (zero, body_error) }
        p.body = body
    }
    ret (p, ok)
}

// Compile a stylesheet document. The result lives in `a`.
fn load(a: *mem.Arena, source: []const u8) -> (Stylesheet, err) {
    let (d, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, parse_error) }
    if d.root == NONE { ret (zero, Invalid) }
    let (root_local, root_is_xsl) = xsl_local(&d, d.root)
    if !root_is_xsl || !(same(root_local, "stylesheet") || same(root_local, "transform")) { ret (zero, Invalid) }
    let size = d.nodes.len + 1usize
    let (instrs, instrs_error) = mem.alloc[Instr](a, size * 2usize + 16usize)
    if instrs_error != ok { ret (zero, instrs_error) }
    let (exprs, exprs_error) = mem.alloc[xp.Compiled](a, size * 2usize + 16usize)
    if exprs_error != ok { ret (zero, exprs_error) }
    let (templates, templates_error) = mem.alloc[Template](a, size)
    if templates_error != ok { ret (zero, templates_error) }
    let (rules, rules_error) = mem.alloc[Rule](a, size * 4usize + 4usize)
    if rules_error != ok { ret (zero, rules_error) }
    let (globals, globals_error) = mem.alloc[Param](a, size)
    if globals_error != ok { ret (zero, globals_error) }
    var c = Compiler {
        a: a, d: &d,
        s: Stylesheet {
            instrs: instrs, instr_count: 0usize, exprs: exprs, expr_count: 0usize, templates: templates, template_count: 0usize,
            rules: rules, rule_count: 0usize, globals: globals, global_count: 0usize,
            output: Output { text: "xml", omit_declaration: false, is_text: false }, document: d,
        },
        excluded: zero, order: 0u32,
    }
    // exclude-result-prefixes on the stylesheet element
    let (exclude_text, has_exclude) = attr_value(&d, d.root, "exclude-result-prefixes")
    if has_exclude {
        let (parts, split_error) = str.split(str.trim(exclude_text), " ")
        if split_error != ok { ret (zero, split_error) }
        var it = parts
        var count = 0usize
        while true {
            let (piece, more) = str.split_next(&it)
            if !more { break }
            if piece.len > 0usize { count += 1usize }
        }
        let (list, list_error) = mem.alloc[str](a, count + 1usize)
        if list_error != ok { ret (zero, list_error) }
        let (parts2, split2_error) = str.split(str.trim(exclude_text), " ")
        if split2_error != ok { ret (zero, split2_error) }
        var it2 = parts2
        var used = 0usize
        while true {
            let (piece, more) = str.split_next(&it2)
            if !more { break }
            if piece.len > 0usize {
                if same(piece, "#default") { list[used] = "" } else { list[used] = piece }
                used += 1usize
            }
        }
        c.excluded = list[..used]
    }
    var at = first_child(&d, d.root)
    while at != NONE {
        let (local, is_x) = xsl_local(&d, at)
        if node_of(&d, at).kind == .Element {
            if !is_x { ret (zero, Invalid) }
            if same(local, "template") {
                let (name, has_name) = attr_value(&d, at, "name")
                let (match_text, has_match) = attr_value(&d, at, "match")
                let (mode, _) = attr_value(&d, at, "mode")
                let (priority_text, has_priority) = attr_value(&d, at, "priority")
                if !has_name && !has_match { ret (zero, Invalid) }
                let t_index = c.s.template_count
                if t_index >= c.s.templates.len { ret (zero, TooComplex) }
                // parameters first (leading xsl:param children), then the body
                var param_count = 0usize
                var child = first_child(&d, at)
                while child != NONE {
                    if is_xsl(&d, child, "param") { param_count += 1usize }
                    child = next_sibling(&d, child)
                }
                let (params, params_alloc_error) = mem.alloc[Param](a, param_count + 1usize)
                if params_alloc_error != ok { ret (zero, params_alloc_error) }
                var pu = 0usize
                child = first_child(&d, at)
                while child != NONE {
                    if is_xsl(&d, child, "param") {
                        let (p, p_error) = compile_param(&c, child)
                        if p_error != ok { ret (zero, p_error) }
                        params[pu] = p
                        pu += 1usize
                    }
                    child = next_sibling(&d, child)
                }
                let (body, body_error) = compile_template_body(&c, at)
                if body_error != ok { ret (zero, body_error) }
                c.s.templates[t_index] = Template { name: name, has_name: has_name, mode: mode, body: body, params: params[..pu] }
                c.s.template_count += 1usize
                if has_match {
                    let rule_error = add_rule(&c, at, match_text, priority_text, has_priority, u32(t_index), mode)
                    if rule_error != ok { ret (zero, rule_error) }
                }
            } else if same(local, "variable") || same(local, "param") {
                let (p, p_error) = compile_param(&c, at)
                if p_error != ok { ret (zero, p_error) }
                c.s.globals[c.s.global_count] = p
                c.s.global_count += 1usize
            } else if same(local, "output") {
                let (method, has_method) = attr_value(&d, at, "method")
                if has_method {
                    if same(method, "text") { c.s.output.is_text = true } else if !same(method, "xml") { ret (zero, Unsupported) }
                }
                let (omit, has_omit) = attr_value(&d, at, "omit-xml-declaration")
                if has_omit && same(omit, "yes") { c.s.output.omit_declaration = true }
                let (indent, has_indent) = attr_value(&d, at, "indent")
                if has_indent && same(indent, "yes") { ret (zero, Unsupported) }
            } else {
                ret (zero, Unsupported)
            }
        }
        at = next_sibling(&d, at)
    }
    ret (c.s, ok)
}

// A template's body: its children without the leading params.
fn compile_template_body(c: *Compiler, id: xml.NodeId) -> ([]u32, err) {
    let count = count_content(c, id) + 1usize
    let (list, list_error) = mem.alloc[u32](c.a, count)
    if list_error != ok { ret (zero, list_error) }
    var used = 0usize
    var at = first_child(c.d, id)
    while at != NONE {
        let n = node_of(c.d, at)
        if n.kind == .Text {
            if !is_blank_text(n.value) {
                let (made, made_error) = new_instr(c, I_TEXT, at)
                if made_error != ok { ret (zero, made_error) }
                c.s.instrs[usize(made)].name = n.value
                list[used] = made
                used += 1usize
            }
        } else if n.kind == .Element && !is_xsl(c.d, at, "param") {
            let (made, made_error) = compile_instruction(c, at)
            if made_error != ok { ret (zero, made_error) }
            if made != NONE {
                list[used] = made
                used += 1usize
            }
        }
        at = n.next_sibling
    }
    ret (list[..used], ok)
}

// ---- the result tree ----

type ResNode = struct {
    kind: u8, name: str, ns: str, value: str, parent: u32, first_child: u32, last_child: u32, next_sibling: u32,
    first_attr: u32, last_attr: u32, first_decl: u32, last_decl: u32,
}
type ResAttr = struct { name: str, ns: str, value: str, next: u32 }
type ResDecl = struct { prefix: str, uri: str, next: u32 }
type Tree = struct { nodes: []ResNode, count: usize, attrs: []ResAttr, attr_count: usize, decls: []ResDecl, decl_count: usize }

const R_ELEMENT: u8 = 1u8
const R_TEXT: u8 = 2u8
const R_COMMENT: u8 = 3u8
const R_PI: u8 = 4u8
const R_ROOT: u8 = 5u8

fn new_tree(a: *mem.Arena) -> (Tree, err) {
    let (nodes, nodes_error) = mem.alloc[ResNode](a, 32usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (attrs, attrs_error) = mem.alloc[ResAttr](a, 16usize)
    if attrs_error != ok { ret (zero, attrs_error) }
    let (decls, decls_error) = mem.alloc[ResDecl](a, 16usize)
    if decls_error != ok { ret (zero, decls_error) }
    var t = Tree { nodes: nodes, count: 0usize, attrs: attrs, attr_count: 0usize, decls: decls, decl_count: 0usize }
    t.nodes[0usize] = ResNode { kind: R_ROOT, name: "", ns: "", value: "", parent: NONE, first_child: NONE, last_child: NONE, next_sibling: NONE, first_attr: NONE, last_attr: NONE, first_decl: NONE, last_decl: NONE }
    t.count = 1usize
    ret (t, ok)
}

fn grow_nodes(a: *mem.Arena, t: *Tree) -> err {
    if t.count < t.nodes.len { ret ok }
    let (bigger, alloc_error) = mem.alloc[ResNode](a, t.nodes.len * 2usize)
    if alloc_error != ok { ret alloc_error }
    var i = 0usize
    while i < t.count {
        bigger[i] = t.nodes[i]
        i += 1usize
    }
    t.nodes = bigger
    ret ok
}

fn add_node(a: *mem.Arena, t: *Tree, parent: u32, kind: u8, name: str, ns: str, value: str) -> (u32, err) {
    try grow_nodes(a, t)
    let id = u32(t.count)
    t.nodes[t.count] = ResNode { kind: kind, name: name, ns: ns, value: value, parent: parent, first_child: NONE, last_child: NONE, next_sibling: NONE, first_attr: NONE, last_attr: NONE, first_decl: NONE, last_decl: NONE }
    t.count += 1usize
    let last = t.nodes[usize(parent)].last_child
    if last == NONE { t.nodes[usize(parent)].first_child = id } else { t.nodes[usize(last)].next_sibling = id }
    t.nodes[usize(parent)].last_child = id
    ret (id, ok)
}

fn add_attr(a: *mem.Arena, t: *Tree, owner: u32, name: str, ns: str, value: str) -> err {
    if t.nodes[usize(owner)].kind != R_ELEMENT { ret ok }
    // a later attribute of the same name replaces the earlier
    var at = t.nodes[usize(owner)].first_attr
    while at != NONE {
        if same(t.attrs[usize(at)].name, name) {
            t.attrs[usize(at)].value = value
            t.attrs[usize(at)].ns = ns
            ret ok
        }
        at = t.attrs[usize(at)].next
    }
    if t.attr_count == t.attrs.len {
        let (bigger, alloc_error) = mem.alloc[ResAttr](a, t.attrs.len * 2usize)
        if alloc_error != ok { ret alloc_error }
        var i = 0usize
        while i < t.attr_count {
            bigger[i] = t.attrs[i]
            i += 1usize
        }
        t.attrs = bigger
    }
    let id = u32(t.attr_count)
    t.attrs[t.attr_count] = ResAttr { name: name, ns: ns, value: value, next: NONE }
    t.attr_count += 1usize
    let last = t.nodes[usize(owner)].last_attr
    if last == NONE { t.nodes[usize(owner)].first_attr = id } else { t.attrs[usize(last)].next = id }
    t.nodes[usize(owner)].last_attr = id
    ret ok
}

fn add_decl(a: *mem.Arena, t: *Tree, owner: u32, prefix: str, uri: str) -> err {
    var at = t.nodes[usize(owner)].first_decl
    while at != NONE {
        if same(t.decls[usize(at)].prefix, prefix) {
            t.decls[usize(at)].uri = uri
            ret ok
        }
        at = t.decls[usize(at)].next
    }
    if t.decl_count == t.decls.len {
        let (bigger, alloc_error) = mem.alloc[ResDecl](a, t.decls.len * 2usize)
        if alloc_error != ok { ret alloc_error }
        var i = 0usize
        while i < t.decl_count {
            bigger[i] = t.decls[i]
            i += 1usize
        }
        t.decls = bigger
    }
    let id = u32(t.decl_count)
    t.decls[t.decl_count] = ResDecl { prefix: prefix, uri: uri, next: NONE }
    t.decl_count += 1usize
    let last = t.nodes[usize(owner)].last_decl
    if last == NONE { t.nodes[usize(owner)].first_decl = id } else { t.decls[usize(last)].next = id }
    t.nodes[usize(owner)].last_decl = id
    ret ok
}

// The string-value of a tree: its text, in order.
fn tree_text(a: *mem.Arena, t: *const Tree) -> (str, err) {
    var total = 0usize
    var i = 0usize
    while i < t.count {
        if t.nodes[i].kind == R_TEXT { total += t.nodes[i].value.len }
        i += 1usize
    }
    let (buffer, alloc_error) = mem.alloc[u8](a, total)
    if alloc_error != ok { ret ("", alloc_error) }
    var used = 0usize
    i = 0usize
    while i < t.count {
        if t.nodes[i].kind == R_TEXT {
            var k = 0usize
            while k < t.nodes[i].value.len {
                buffer[used] = t.nodes[i].value[k]
                used += 1usize
                k += 1usize
            }
        }
        i += 1usize
    }
    ret (buffer[..used], ok)
}

// ---- serialization with namespace fixup ----

type Scope = struct { prefixes: []str, uris: []str, count: usize }

fn scope_lookup(s: *const Scope, prefix: str) -> (str, bool) {
    var i = s.count
    while i > 0usize {
        i -= 1usize
        if same(s.prefixes[i], prefix) { ret (s.uris[i], true) }
    }
    ret ("", false)
}

type Sink = struct { buffer: []u8, used: usize, a: *mem.Arena }

fn put(sink: *Sink, text: str) -> err {
    if sink.used + text.len > sink.buffer.len {
        var capacity = sink.buffer.len * 2usize
        while capacity < sink.used + text.len { capacity *= 2usize }
        let (bigger, alloc_error) = mem.alloc[u8](sink.a, capacity)
        if alloc_error != ok { ret alloc_error }
        var i = 0usize
        while i < sink.used {
            bigger[i] = sink.buffer[i]
            i += 1usize
        }
        sink.buffer = bigger
    }
    var k = 0usize
    while k < text.len {
        sink.buffer[sink.used] = text[k]
        sink.used += 1usize
        k += 1usize
    }
    ret ok
}

fn put_escaped(sink: *Sink, text: str, attribute: bool) -> err {
    var from = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        var rep = ""
        if c == 38u8 { rep = "&amp;" } else if c == 60u8 { rep = "&lt;" } else if c == 62u8 && !attribute { rep = "&gt;" } else if c == 34u8 && attribute { rep = "&quot;" } else if c == 13u8 { rep = "&#13;" } else if attribute && c == 10u8 { rep = "&#10;" } else if attribute && c == 9u8 { rep = "&#9;" }
        if rep.len > 0usize {
            try put(sink, text[from..i])
            try put(sink, rep)
            from = i + 1usize
        }
        i += 1usize
    }
    ret put(sink, text[from..])
}

fn prefix_of(name: str) -> str {
    let (prefix, _) = split_name(name)
    ret prefix
}

fn write_node(a: *mem.Arena, t: *const Tree, id: u32, sink: *Sink, scope: *Scope) -> err {
    let node = t.nodes[usize(id)]
    if node.kind == R_TEXT { ret put_escaped(sink, node.value, false) }
    if node.kind == R_COMMENT {
        try put(sink, "<!--")
        try put(sink, node.value)
        ret put(sink, "-->")
    }
    if node.kind == R_PI {
        try put(sink, "<?")
        try put(sink, node.name)
        if node.value.len > 0usize {
            try put(sink, " ")
            try put(sink, node.value)
        }
        ret put(sink, "?>")
    }
    // an element: declarations in force, then any the names need
    let mark = scope.count
    try put(sink, "<")
    try put(sink, node.name)
    var decl = node.first_decl
    while decl != NONE {
        let dd = t.decls[usize(decl)]
        scope.prefixes[scope.count] = dd.prefix
        scope.uris[scope.count] = dd.uri
        scope.count += 1usize
        if dd.prefix.len == 0usize {
            try put(sink, " xmlns=\"")
        } else {
            try put(sink, " xmlns:")
            try put(sink, dd.prefix)
            try put(sink, "=\"")
        }
        try put_escaped(sink, dd.uri, true)
        try put(sink, "\"")
        decl = dd.next
    }
    // fixup for the element's own name
    let eprefix = prefix_of(node.name)
    let (bound, has_bound) = scope_lookup(scope, eprefix)
    var need = false
    if has_bound { need = !same(bound, node.ns) } else { need = node.ns.len > 0usize }
    if need {
        scope.prefixes[scope.count] = eprefix
        scope.uris[scope.count] = node.ns
        scope.count += 1usize
        if eprefix.len == 0usize {
            try put(sink, " xmlns=\"")
        } else {
            try put(sink, " xmlns:")
            try put(sink, eprefix)
            try put(sink, "=\"")
        }
        try put_escaped(sink, node.ns, true)
        try put(sink, "\"")
    }
    var attr = node.first_attr
    while attr != NONE {
        let aa = t.attrs[usize(attr)]
        let aprefix = prefix_of(aa.name)
        if aprefix.len > 0usize {
            let (abound, ahas) = scope_lookup(scope, aprefix)
            var aneed = false
            if ahas { aneed = !same(abound, aa.ns) } else { aneed = true }
            if aneed {
                scope.prefixes[scope.count] = aprefix
                scope.uris[scope.count] = aa.ns
                scope.count += 1usize
                try put(sink, " xmlns:")
                try put(sink, aprefix)
                try put(sink, "=\"")
                try put_escaped(sink, aa.ns, true)
                try put(sink, "\"")
            }
        }
        try put(sink, " ")
        try put(sink, aa.name)
        try put(sink, "=\"")
        try put_escaped(sink, aa.value, true)
        try put(sink, "\"")
        attr = aa.next
    }
    if node.first_child == NONE {
        try put(sink, "/>")
    } else {
        try put(sink, ">")
        var child = node.first_child
        while child != NONE {
            try write_node(a, t, child, sink, scope)
            child = t.nodes[usize(child)].next_sibling
        }
        try put(sink, "</")
        try put(sink, node.name)
        try put(sink, ">")
    }
    scope.count = mark
    ret ok
}

fn serialize(a: *mem.Arena, t: *const Tree, is_text: bool, omit_declaration: bool) -> (str, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 4096usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var sink = Sink { buffer: buffer, used: 0usize, a: a }
    if is_text {
        let (text, text_error) = tree_text(a, t)
        ret (text, text_error)
    }
    if !omit_declaration {
        let declaration_error = put(&sink, "<?xml version=\"1.0\"?>\n")
        if declaration_error != ok { ret ("", declaration_error) }
    }
    let (prefixes, prefixes_error) = mem.alloc[str](a, t.count * 4usize + 16usize)
    if prefixes_error != ok { ret ("", prefixes_error) }
    let (uris, uris_error) = mem.alloc[str](a, t.count * 4usize + 16usize)
    if uris_error != ok { ret ("", uris_error) }
    var scope = Scope { prefixes: prefixes, uris: uris, count: 0usize }
    var child = t.nodes[0usize].first_child
    while child != NONE {
        let write_error = write_node(a, t, child, &sink, &scope)
        if write_error != ok { ret ("", write_error) }
        if t.nodes[usize(child)].kind == R_ELEMENT {
            let nl_error = put(&sink, "\n")
            if nl_error != ok { ret ("", nl_error) }
        }
        child = t.nodes[usize(child)].next_sibling
    }
    ret (sink.buffer[..sink.used], ok)
}

// ---- running ----

type Run = struct {
    a: *mem.Arena, ss: *const Stylesheet, d: *const xml.Document, vars: xp.Variables,
    trees: []Tree, tree_count: usize, out: u32, cur: u32, depth: u32,
}

fn out_tree(r: *Run) -> *Tree { ret &r.trees[usize(r.out)] }

fn push_variable(r: *Run, name: str, value: xp.Value) -> err {
    if r.vars.count >= r.vars.items.len { ret TooComplex }
    r.vars.items[r.vars.count] = xp.Variable { name: name, value: value }
    r.vars.count += 1usize
    ret ok
}

fn eval_expr(r: *Run, index: u32, ctx: xp.Context) -> (xp.Value, err) {
    let ext = xp.Extensions { current: ctx.node, has_current: true }
    let (v, v_error) = xp.evaluate(r.a, &r.ss.exprs[usize(index)], r.d, ctx, &r.vars, &ext)
    if v_error != ok { ret (zero, Invalid) }
    ret (v, ok)
}

fn eval_string(r: *Run, index: u32, ctx: xp.Context) -> (str, err) {
    let (v, v_error) = eval_expr(r, index, ctx)
    if v_error != ok { ret ("", v_error) }
    if v.kind == xp.Kind.String { ret (v.text, ok) }
    let (text, text_error) = xp.to_string(r.a, r.d, v)
    if text_error != ok { ret ("", Invalid) }
    ret (text, ok)
}

fn eval_avt(r: *Run, avt: Avt, ctx: xp.Context) -> (str, err) {
    if avt.count == 1usize && avt.exprs[0usize] == NONE { ret (avt.literals[0usize], ok) }
    var total = 0usize
    let (parts, parts_error) = mem.alloc[str](r.a, avt.count * 2usize)
    if parts_error != ok { ret ("", parts_error) }
    var n = 0usize
    var i = 0usize
    while i < avt.count {
        parts[n] = avt.literals[i]
        total += avt.literals[i].len
        n += 1usize
        if avt.exprs[i] != NONE {
            let (text, text_error) = eval_string(r, avt.exprs[i], ctx)
            if text_error != ok { ret ("", text_error) }
            parts[n] = text
            total += text.len
            n += 1usize
        }
        i += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](r.a, total)
    if buffer_error != ok { ret ("", buffer_error) }
    var used = 0usize
    var p = 0usize
    while p < n {
        var k = 0usize
        while k < parts[p].len {
            buffer[used] = parts[p][k]
            used += 1usize
            k += 1usize
        }
        p += 1usize
    }
    ret (buffer[..used], ok)
}

fn add_text(r: *Run, text: str) -> err {
    if text.len == 0usize { ret ok }
    let t = out_tree(r)
    let last = t.nodes[usize(r.cur)].last_child
    if last != NONE && t.nodes[usize(last)].kind == R_TEXT {
        let (joined, join_error) = str.concat(r.a, t.nodes[usize(last)].value, text)
        if join_error != ok { ret join_error }
        t.nodes[usize(last)].value = joined
        ret ok
    }
    let (_, add_error) = add_node(r.a, t, r.cur, R_TEXT, "", "", text)
    ret add_error
}

fn ns_of_prefix(scope: []const xp.Binding, prefix: str) -> (str, bool) {
    var i = 0usize
    while i < scope.len {
        if same(scope[i].prefix, prefix) { ret (scope[i].uri, true) }
        i += 1usize
    }
    ret ("", false)
}

// The source node as a copy in the result tree under the current output element.
fn copy_node(r: *Run, n: xp.XNode, deep: bool) -> err {
    let node = node_of(r.d, n.id)
    if n.attribute != 0u32 {
        let at = node.attributes[usize(n.attribute) - 1usize]
        let (uri, _) = xp.expanded_name(r.d, n)
        let t = out_tree(r)
        ret add_attr(r.a, t, r.cur, at.name, uri, at.value)
    }
    if node.kind == .Text { ret add_text(r, node.value) }
    if node.kind == .Comment {
        let t = out_tree(r)
        let (_, e) = add_node(r.a, t, r.cur, R_COMMENT, "", "", node.value)
        ret e
    }
    if node.kind == .Processing {
        let t = out_tree(r)
        let (_, e) = add_node(r.a, t, r.cur, R_PI, node.name, "", node.value)
        ret e
    }
    if node.kind == .Document {
        if !deep { ret ok }
        var child = node.first_child
        while child != NONE {
            try copy_node(r, xp.XNode { id: child, attribute: 0u32 }, true)
            child = node_of(r.d, child).next_sibling
        }
        ret ok
    }
    // an element
    let (uri, _) = xp.expanded_name(r.d, n)
    let t = out_tree(r)
    let (made, made_error) = add_node(r.a, t, r.cur, R_ELEMENT, node.name, uri, "")
    if made_error != ok { ret made_error }
    var i = 0usize
    while i < node.attributes.len {
        let name = node.attributes[i].name
        if same(name, "xmlns") {
            try add_decl(r.a, out_tree(r), made, "", node.attributes[i].value)
        } else if str.starts_with(name, "xmlns:") {
            try add_decl(r.a, out_tree(r), made, name[6usize..], node.attributes[i].value)
        } else if deep {
            let (auri, _) = xp.expanded_name(r.d, xp.XNode { id: n.id, attribute: u32(i) + 1u32 })
            try add_attr(r.a, out_tree(r), made, name, auri, node.attributes[i].value)
        }
        i += 1usize
    }
    if deep {
        let saved = r.cur
        r.cur = made
        var child = node.first_child
        while child != NONE {
            let child_error = copy_node(r, xp.XNode { id: child, attribute: 0u32 }, true)
            if child_error != ok {
                r.cur = saved
                ret child_error
            }
            child = node_of(r.d, child).next_sibling
        }
        r.cur = saved
    }
    ret ok
}

// Copy the children of a result tree (a result tree fragment) into the current output.
fn copy_tree_children(r: *Run, source: u32, from: u32) -> err {
    var child = r.trees[usize(source)].nodes[usize(from)].first_child
    while child != NONE {
        let node = r.trees[usize(source)].nodes[usize(child)]
        if node.kind == R_TEXT {
            try add_text(r, node.value)
        } else if node.kind == R_COMMENT || node.kind == R_PI {
            let (_, e) = add_node(r.a, out_tree(r), r.cur, node.kind, node.name, "", node.value)
            if e != ok { ret e }
        } else {
            let (made, made_error) = add_node(r.a, out_tree(r), r.cur, R_ELEMENT, node.name, node.ns, "")
            if made_error != ok { ret made_error }
            var d = node.first_decl
            while d != NONE {
                let dd = r.trees[usize(source)].decls[usize(d)]
                try add_decl(r.a, out_tree(r), made, dd.prefix, dd.uri)
                d = dd.next
            }
            var at = node.first_attr
            while at != NONE {
                let aa = r.trees[usize(source)].attrs[usize(at)]
                try add_attr(r.a, out_tree(r), made, aa.name, aa.ns, aa.value)
                at = aa.next
            }
            let saved = r.cur
            r.cur = made
            let inner_error = copy_tree_children(r, source, child)
            r.cur = saved
            if inner_error != ok { ret inner_error }
        }
        child = node.next_sibling
    }
    ret ok
}

// Run `body` with output going to a fresh tree; answers the tree's index.
fn run_to_tree(r: *Run, body: []const u32, ctx: xp.Context) -> (u32, err) {
    if r.tree_count >= r.trees.len { ret (NONE, TooComplex) }
    let (tree, tree_error) = new_tree(r.a)
    if tree_error != ok { ret (NONE, tree_error) }
    let index = u32(r.tree_count)
    r.trees[r.tree_count] = tree
    r.tree_count += 1usize
    let saved_out = r.out
    let saved_cur = r.cur
    r.out = index
    r.cur = 0u32
    let exec_error = exec_body(r, body, ctx)
    r.out = saved_out
    r.cur = saved_cur
    if exec_error != ok { ret (NONE, exec_error) }
    ret (index, ok)
}

fn rtf_value(r: *Run, index: u32) -> (xp.Value, err) {
    let (text, text_error) = tree_text(r.a, &r.trees[usize(index)])
    if text_error != ok { ret (zero, text_error) }
    ret (xp.Value { kind: xp.Kind.String, nodes: zero, text: text, number: f64(index), flag: true }, ok)
}

fn eval_binding(r: *Run, select: u32, has_select: bool, body: []const u32, ctx: xp.Context) -> (xp.Value, err) {
    if has_select {
        let (v, v_error) = eval_expr(r, select, ctx)
        ret (v, v_error)
    }
    if body.len == 0usize { ret (xp.string_value(""), ok) }
    let (index, tree_error) = run_to_tree(r, body, ctx)
    if tree_error != ok { ret (zero, tree_error) }
    let (v, v_error) = rtf_value(r, index)
    ret (v, v_error)
}

// ---- rule selection ----

fn pattern_matches(r: *Run, rule: Rule, n: xp.XNode) -> bool {
    let checkpoint = mem.mark(r.a)
    let compiled = &r.ss.exprs[usize(rule.expr)]
    let root = compiled.exprs[usize(compiled.root)]
    var found = false
    var context = n
    var first = true
    var done = false
    while !done {
        let ext = xp.no_extensions()
        let (v, v_error) = xp.evaluate(r.a, compiled, r.d, xp.Context { node: context, position: 1usize, size: 1usize }, &r.vars, &ext)
        if v_error == ok && v.kind == xp.Kind.NodeSet {
            var i = 0usize
            while i < v.nodes.len {
                if v.nodes[i].id == n.id && v.nodes[i].attribute == n.attribute { found = true }
                i += 1usize
            }
        }
        if found || (root.kind == xp.E_PATH && root.absolute) { done = true }
        if !done {
            // widen the context to the parent (an attribute's parent is its owner element)
            if first && n.attribute != 0u32 {
                context = xp.XNode { id: n.id, attribute: 0u32 }
            } else {
                let parent = node_of(r.d, context.id).parent
                if context.attribute != 0u32 {
                    context = xp.XNode { id: context.id, attribute: 0u32 }
                } else if parent == NONE {
                    done = true
                } else {
                    context = xp.XNode { id: parent, attribute: 0u32 }
                }
            }
            first = false
        }
    }
    mem.reset(r.a, checkpoint)
    ret found
}

fn find_rule(r: *Run, n: xp.XNode, mode: str) -> u32 {
    var best = NONE
    var i = 0usize
    while i < r.ss.rule_count {
        let rule = r.ss.rules[i]
        if same(rule.mode, mode) {
            var better = best == NONE
            if !better {
                let current = r.ss.rules[usize(best)]
                better = rule.priority > current.priority || (rule.priority == current.priority && rule.order > current.order)
            }
            if better && pattern_matches(r, rule, n) { best = u32(i) }
        }
        i += 1usize
    }
    ret best
}

// ---- sorting ----

fn sort_nodes(r: *Run, nodes: []xp.XNode, sorts: []const Sort) -> ([]xp.XNode, err) {
    if sorts.len == 0usize || nodes.len < 2usize { ret (nodes, ok) }
    let n = nodes.len
    let (keys, keys_error) = mem.alloc[str](r.a, n * sorts.len)
    if keys_error != ok { ret (zero, keys_error) }
    let (nums, nums_error) = mem.alloc[f64](r.a, n * sorts.len)
    if nums_error != ok { ret (zero, nums_error) }
    var i = 0usize
    while i < n {
        var s = 0usize
        while s < sorts.len {
            let (text, text_error) = eval_string(r, sorts[s].select, xp.Context { node: nodes[i], position: i + 1usize, size: n })
            if text_error != ok { ret (zero, text_error) }
            keys[i * sorts.len + s] = text
            nums[i * sorts.len + s] = xp.text_number(text)
            s += 1usize
        }
        i += 1usize
    }
    let (order, order_error) = mem.alloc[usize](r.a, n)
    if order_error != ok { ret (zero, order_error) }
    i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    // insertion sort keeps equal keys in document order
    i = 1usize
    while i < n {
        let held = order[i]
        var j = i
        while j > 0usize && sort_before(keys, nums, sorts, held, order[j - 1usize]) {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = held
        i += 1usize
    }
    let (out, out_error) = mem.alloc[xp.XNode](r.a, n)
    if out_error != ok { ret (zero, out_error) }
    i = 0usize
    while i < n {
        out[i] = nodes[order[i]]
        i += 1usize
    }
    ret (out, ok)
}

fn text_compare(x: str, y: str) -> i32 {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] {
            if x[i] < y[i] { ret -1i32 }
            ret 1i32
        }
        i += 1usize
    }
    if x.len == y.len { ret 0i32 }
    if x.len < y.len { ret -1i32 }
    ret 1i32
}

// Whether item `a` sorts strictly before item `b` under every key in turn.
fn sort_before(keys: []const str, nums: []const f64, sorts: []const Sort, a: usize, b: usize) -> bool {
    var s = 0usize
    while s < sorts.len {
        var c = 0i32
        if sorts[s].numeric {
            let x = nums[a * sorts.len + s]
            let y = nums[b * sorts.len + s]
            // NaN sorts before every number
            if x != x && y != y { c = 0i32 } else if x != x { c = -1i32 } else if y != y { c = 1i32 } else if x < y { c = -1i32 } else if x > y { c = 1i32 }
        } else {
            c = text_compare(keys[a * sorts.len + s], keys[b * sorts.len + s])
        }
        if sorts[s].descending { c = 0i32 - c }
        if c < 0i32 { ret true }
        if c > 0i32 { ret false }
        s += 1usize
    }
    ret false
}

// ---- executing instructions ----

fn exec_body(r: *Run, body: []const u32, ctx: xp.Context) -> err {
    let saved_vars = r.vars.count
    var i = 0usize
    while i < body.len {
        let e = exec(r, body[i], ctx)
        if e != ok {
            r.vars.count = saved_vars
            ret e
        }
        i += 1usize
    }
    r.vars.count = saved_vars
    ret ok
}

// Variables stay visible to the later siblings in a body, so a variable instruction pushes without popping
// and `exec_body` drops them all at the end.
fn exec(r: *Run, index: u32, ctx: xp.Context) -> err {
    if r.depth > 120u32 { ret TooComplex }
    r.depth += 1u32
    let e = exec_inner(r, index, ctx)
    r.depth -= 1u32
    ret e
}

fn apply_to_node(r: *Run, n: xp.XNode, mode: str, position: usize, size: usize, params: []const WithParam, caller: xp.Context) -> err {
    let rule_index = find_rule(r, n, mode)
    if rule_index == NONE { ret builtin_rule(r, n, mode, position, size) }
    let template = r.ss.templates[usize(r.ss.rules[usize(rule_index)].template)]
    ret exec_template(r, template, n, position, size, params, caller)
}

fn builtin_rule(r: *Run, n: xp.XNode, mode: str, position: usize, size: usize) -> err {
    let node = node_of(r.d, n.id)
    if n.attribute != 0u32 { ret add_text(r, node.attributes[usize(n.attribute) - 1usize].value) }
    if node.kind == .Text { ret add_text(r, node.value) }
    if node.kind == .Element || node.kind == .Document {
        var count = 0usize
        var child = node.first_child
        while child != NONE {
            count += 1usize
            child = node_of(r.d, child).next_sibling
        }
        var k = 0usize
        child = node.first_child
        while child != NONE {
            k += 1usize
            let e = apply_to_node(r, xp.XNode { id: child, attribute: 0u32 }, mode, k, count, zero, xp.Context { node: n, position: position, size: size })
            if e != ok { ret e }
            child = node_of(r.d, child).next_sibling
        }
    }
    ret ok
}

fn exec_template(r: *Run, template: Template, n: xp.XNode, position: usize, size: usize, params: []const WithParam, caller: xp.Context) -> err {
    let saved = r.vars.count
    let ctx = xp.Context { node: n, position: position, size: size }
    // every supplied value is computed before any parameter is bound: they see the caller's variables only
    var given: []xp.Value = zero
    if params.len > 0usize {
        let (values, values_error) = mem.alloc[xp.Value](r.a, params.len)
        if values_error != ok { ret values_error }
        var j = 0usize
        while j < params.len {
            let (v, v_error) = eval_binding(r, params[j].select, params[j].has_select, params[j].body, caller)
            if v_error != ok { ret v_error }
            values[j] = v
            j += 1usize
        }
        given = values
    }
    var i = 0usize
    while i < template.params.len {
        let p = template.params[i]
        var supplied = false
        var k = 0usize
        while k < params.len {
            if same(params[k].name, p.name) {
                let v = given[k]
                let push_error = push_variable(r, p.name, v)
                if push_error != ok {
                    r.vars.count = saved
                    ret push_error
                }
                supplied = true
            }
            k += 1usize
        }
        if !supplied {
            let (v, v_error) = eval_binding(r, p.select, p.has_select, p.body, ctx)
            if v_error != ok {
                r.vars.count = saved
                ret v_error
            }
            let push_error = push_variable(r, p.name, v)
            if push_error != ok {
                r.vars.count = saved
                ret push_error
            }
        }
        i += 1usize
    }
    let body_error = exec_body(r, template.body, ctx)
    r.vars.count = saved
    ret body_error
}

fn exec_inner(r: *Run, index: u32, ctx: xp.Context) -> err {
    let ins = r.ss.instrs[usize(index)]
    if ins.kind == I_TEXT || ins.kind == I_XSL_TEXT { ret add_text(r, ins.name) }
    if ins.kind == I_VALUE_OF {
        let (text, text_error) = eval_string(r, ins.expr, ctx)
        if text_error != ok { ret text_error }
        ret add_text(r, text)
    }
    if ins.kind == I_VARIABLE {
        let (v, v_error) = eval_binding(r, ins.expr, ins.expr != NONE, ins.children, ctx)
        if v_error != ok { ret v_error }
        ret push_variable(r, ins.name, v)
    }
    if ins.kind == I_IF {
        let (v, v_error) = eval_expr(r, ins.expr, ctx)
        if v_error != ok { ret v_error }
        if xp.to_boolean(v) { ret exec_body(r, ins.children, ctx) }
        ret ok
    }
    if ins.kind == I_CHOOSE {
        var i = 0usize
        while i < ins.children.len {
            let branch = r.ss.instrs[usize(ins.children[i])]
            if branch.kind == I_OTHERWISE { ret exec_body(r, branch.children, ctx) }
            let (v, v_error) = eval_expr(r, branch.expr, ctx)
            if v_error != ok { ret v_error }
            if xp.to_boolean(v) { ret exec_body(r, branch.children, ctx) }
            i += 1usize
        }
        ret ok
    }
    if ins.kind == I_FOR_EACH {
        let (v, v_error) = eval_expr(r, ins.expr, ctx)
        if v_error != ok { ret v_error }
        if v.kind != xp.Kind.NodeSet { ret Invalid }
        let (sorted, sort_error) = sort_nodes(r, v.nodes, ins.sorts)
        if sort_error != ok { ret sort_error }
        var i = 0usize
        while i < sorted.len {
            let e = exec_body(r, ins.children, xp.Context { node: sorted[i], position: i + 1usize, size: sorted.len })
            if e != ok { ret e }
            i += 1usize
        }
        ret ok
    }
    if ins.kind == I_APPLY {
        let (v, v_error) = eval_expr(r, ins.expr, ctx)
        if v_error != ok { ret v_error }
        if v.kind != xp.Kind.NodeSet { ret Invalid }
        let (sorted, sort_error) = sort_nodes(r, v.nodes, ins.sorts)
        if sort_error != ok { ret sort_error }
        var i = 0usize
        while i < sorted.len {
            let e = apply_to_node(r, sorted[i], ins.mode, i + 1usize, sorted.len, ins.with_params, ctx)
            if e != ok { ret e }
            i += 1usize
        }
        ret ok
    }
    if ins.kind == I_CALL {
        var found = NONE
        var i = 0usize
        while i < r.ss.template_count {
            if r.ss.templates[i].has_name && same(r.ss.templates[i].name, ins.name) { found = u32(i) }
            i += 1usize
        }
        if found == NONE { ret NoRule }
        ret exec_template(r, r.ss.templates[usize(found)], ctx.node, ctx.position, ctx.size, ins.with_params, ctx)
    }
    if ins.kind == I_LRE || ins.kind == I_ELEMENT {
        var name = ins.name
        var uri = ""
        if ins.kind == I_LRE {
            let (found_uri, _) = ns_of_prefix(ins.scope, prefix_of(name))
            uri = found_uri
        } else {
            let (computed, name_error) = eval_avt(r, ins.name_avt, ctx)
            if name_error != ok { ret name_error }
            name = computed
            if ins.has_mode {
                let (explicit, explicit_error) = eval_avt(r, ins.namespace_avt, ctx)
                if explicit_error != ok { ret explicit_error }
                uri = explicit
            } else {
                let (found_uri, _) = ns_of_prefix(ins.scope, prefix_of(name))
                uri = found_uri
            }
        }
        let t = out_tree(r)
        let (made, made_error) = add_node(r.a, t, r.cur, R_ELEMENT, name, uri, "")
        if made_error != ok { ret made_error }
        if ins.kind == I_LRE {
            var i = 0usize
            while i < ins.declared.len {
                let decl_error = add_decl(r.a, out_tree(r), made, ins.declared[i].prefix, ins.declared[i].uri)
                if decl_error != ok { ret decl_error }
                i += 1usize
            }
            i = 0usize
            while i < ins.attr_names.len {
                let (value, value_error) = eval_avt(r, ins.attr_avts[i], ctx)
                if value_error != ok { ret value_error }
                let (auri, _) = ns_of_prefix(ins.scope, prefix_of(ins.attr_names[i]))
                var attr_ns = ""
                if prefix_of(ins.attr_names[i]).len > 0usize { attr_ns = auri }
                let attr_error = add_attr(r.a, out_tree(r), made, ins.attr_names[i], attr_ns, value)
                if attr_error != ok { ret attr_error }
                i += 1usize
            }
        }
        let saved = r.cur
        r.cur = made
        let body_error = exec_body(r, ins.children, ctx)
        r.cur = saved
        ret body_error
    }
    if ins.kind == I_ATTRIBUTE {
        let (name, name_error) = eval_avt(r, ins.name_avt, ctx)
        if name_error != ok { ret name_error }
        var uri = ""
        if ins.has_mode {
            let (explicit, explicit_error) = eval_avt(r, ins.namespace_avt, ctx)
            if explicit_error != ok { ret explicit_error }
            uri = explicit
        } else if prefix_of(name).len > 0usize {
            let (found_uri, _) = ns_of_prefix(ins.scope, prefix_of(name))
            uri = found_uri
        }
        let (tree_index, tree_error) = run_to_tree(r, ins.children, ctx)
        if tree_error != ok { ret tree_error }
        let (value, value_error) = tree_text(r.a, &r.trees[usize(tree_index)])
        if value_error != ok { ret value_error }
        ret add_attr(r.a, out_tree(r), r.cur, name, uri, value)
    }
    if ins.kind == I_COMMENT || ins.kind == I_PI {
        var name = ""
        if ins.kind == I_PI {
            let (computed, name_error) = eval_avt(r, ins.name_avt, ctx)
            if name_error != ok { ret name_error }
            name = computed
        }
        let (tree_index, tree_error) = run_to_tree(r, ins.children, ctx)
        if tree_error != ok { ret tree_error }
        let (value, value_error) = tree_text(r.a, &r.trees[usize(tree_index)])
        if value_error != ok { ret value_error }
        var kind = R_COMMENT
        if ins.kind == I_PI { kind = R_PI }
        let (_, add_error) = add_node(r.a, out_tree(r), r.cur, kind, name, "", value)
        ret add_error
    }
    if ins.kind == I_COPY {
        let node = node_of(r.d, ctx.node.id)
        if ctx.node.attribute == 0u32 && (node.kind == .Element || node.kind == .Document) {
            if node.kind == .Document { ret exec_body(r, ins.children, ctx) }
            let copy_error = copy_node(r, ctx.node, false)
            if copy_error != ok { ret copy_error }
            let t = out_tree(r)
            let made = t.nodes[usize(r.cur)].last_child
            let saved = r.cur
            r.cur = made
            let body_error = exec_body(r, ins.children, ctx)
            r.cur = saved
            ret body_error
        }
        ret copy_node(r, ctx.node, false)
    }
    if ins.kind == I_COPY_OF {
        let (v, v_error) = eval_expr(r, ins.expr, ctx)
        if v_error != ok { ret v_error }
        if v.kind == xp.Kind.NodeSet {
            var i = 0usize
            while i < v.nodes.len {
                let e = copy_node(r, v.nodes[i], true)
                if e != ok { ret e }
                i += 1usize
            }
            ret ok
        }
        if v.kind == xp.Kind.String && v.flag { ret copy_tree_children(r, u32(v.number), 0u32) }
        let (text, text_error) = xp.to_string(r.a, r.d, v)
        if text_error != ok { ret Invalid }
        ret add_text(r, text)
    }
    if ins.kind == I_MESSAGE {
        if same(ins.name, "yes") { ret Terminated }
        ret ok
    }
    ret Unsupported
}

// Transform `doc` by the stylesheet. `params` override global parameters by name (string values).
fn transform(a: *mem.Arena, ss: *const Stylesheet, doc: *const xml.Document, params: []const xp.Variable) -> (Output, err) {
    let (variables, variables_error) = mem.alloc[xp.Variable](a, 8192usize)
    if variables_error != ok { ret (zero, variables_error) }
    let (trees, trees_error) = mem.alloc[Tree](a, 4096usize)
    if trees_error != ok { ret (zero, trees_error) }
    var r = Run { a: a, ss: ss, d: doc, vars: xp.Variables { items: variables, count: 0usize }, trees: trees, tree_count: 0usize, out: 0u32, cur: 0u32, depth: 0u32 }
    let (main_tree, main_error) = new_tree(a)
    if main_error != ok { ret (zero, main_error) }
    r.trees[0usize] = main_tree
    r.tree_count = 1usize
    let root_ctx = xp.Context { node: xp.XNode { id: 0u32, attribute: 0u32 }, position: 1usize, size: 1usize }
    var g = 0usize
    while g < ss.global_count {
        let p = ss.globals[g]
        var overridden = false
        var k = 0usize
        while k < params.len {
            if same(params[k].name, p.name) {
                let push_error = push_variable(&r, p.name, params[k].value)
                if push_error != ok { ret (zero, push_error) }
                overridden = true
            }
            k += 1usize
        }
        if !overridden {
            let (v, v_error) = eval_binding(&r, p.select, p.has_select, p.body, root_ctx)
            if v_error != ok { ret (zero, v_error) }
            let push_error = push_variable(&r, p.name, v)
            if push_error != ok { ret (zero, push_error) }
        }
        g += 1usize
    }
    let start_error = apply_to_node(&r, xp.XNode { id: 0u32, attribute: 0u32 }, "", 1usize, 1usize, zero, root_ctx)
    if start_error != ok { ret (zero, start_error) }
    let (text, serialize_error) = serialize(a, &r.trees[0usize], ss.output.is_text, ss.output.omit_declaration)
    if serialize_error != ok { ret (zero, serialize_error) }
    ret (Output { text: text, omit_declaration: ss.output.omit_declaration, is_text: ss.output.is_text }, ok)
}
