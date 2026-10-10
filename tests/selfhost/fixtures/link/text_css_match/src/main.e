// `e.fmt.css.match` against Vaper's own selector matcher (selector_matcher.dart): scripts/css_match_vectors.mjs writes
// random HTML documents and selector lists with, per parsed selector, a string of 0/1 for each element in document order
// (`e.r`) and the element tags (`e.tags`). The fixture parses the document with `e.fmt.html`, numbers the elements the
// same way and matches each parsed selector.
use e.algo.ir as ir
use e.fmt.css.match as match
use e.fmt.css.selector as selector
use e.fmt.css.syntax as syntax
use e.fmt.html as html
use e.fmt.json as json
use e.data.list as list
use e.io
use e.mem
use e.os
use e.str

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn index_of(v: json.Value, key: str) -> (i64, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret (0i64, false) }
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        if e == ok { ret (value, true) }
        ret (0i64, false)
    default:
        ret (0i64, false)
    }
}

fn collect(doc: *const html.Document, id: html.NodeId, out: *list.List[html.NodeId]) {
    let node = html.node(doc, id)
    if node.kind == .Element {
        let pushed = list.push[html.NodeId](out, id)
    }
    var child = node.first_child
    while child != html.NONE {
        collect(doc, child, out)
        child = doc.nodes[usize(child)].next_sibling
    }
}

fn str_index(a: *mem.Arena, n: usize) -> str {
    var digits: [20]u8 = zero
    var at = 20usize
    var v = n
    if v == 0usize {
        at -= 1usize
        digits[at] = 48u8
    }
    while v > 0usize {
        at -= 1usize
        digits[at] = 48u8 + u8(v % 10usize)
        v = v / 10usize
    }
    let (out, e) = mem.alloc[u8](a, 20usize - at)
    if e != ok { ret "" }
    var i = 0usize
    while i < 20usize - at {
        out[i] = digits[at + i]
        i += 1usize
    }
    ret out[0usize..20usize - at]
}

fn pick(els: []const html.NodeId, v: i64) -> html.NodeId {
    if els.len == 0usize { ret html.NONE }
    var i = v % i64(els.len)
    if i < 0i64 { i += i64(els.len) }
    ret els[usize(i)]
}

fn run_one(a: *mem.Arena, root: json.Value) -> bool {
    let options = html.Options { max_bytes: 4194304usize, max_nodes: 100000usize, max_attributes: 64usize, max_depth: 256u16, preserve_comments: true }
    let (doc, de) = html.parse(a, text_field(root, "html"), options)
    if de != ok { os.exit(81i32) }
    let (made, me) = list.init[html.NodeId](a, 64usize)
    if me != ok { os.exit(82i32) }
    var els = made
    // the root element is the document's one element child
    var top = doc.nodes[usize(doc.root)].first_child
    while top != html.NONE {
        collect(&doc, top, &els)
        top = doc.nodes[usize(top)].next_sibling
    }
    let elements = list.slice_const[html.NodeId](&els)
    var state = match.no_state()
    let st = ir.value_of(root, "state")
    let (hover, have_hover) = index_of(st, "hover")
    if have_hover {
        state.has_hover = true
        state.hover = pick(elements, hover)
    }
    let (focus, have_focus) = index_of(st, "focus")
    if have_focus {
        state.has_focus = true
        state.focus = pick(elements, focus)
    }
    let (active, have_active) = index_of(st, "active")
    if have_active {
        state.has_active = true
        state.active = pick(elements, active)
    }
    let within = ir.value_of(st, "focusWithin")
    let (ws, is_array) = ir.items_of(within)
    if is_array {
        let (ids, ie) = mem.alloc[html.NodeId](a, ws.len + 1usize)
        if ie != ok { os.exit(83i32) }
        var k = 0usize
        while k < ws.len {
            var v = 0i64
            switch ws[k] {
            case .Number as n:
                let (x, e) = json.number_i64(n)
                if e == ok { v = x }
            default:
                v = 0i64
            }
            ids[k] = pick(elements, v)
            k += 1usize
        }
        state.focus_within = ids[0usize..ws.len]
    }
    let m = match.new_matcher(a, &doc, state)
    let src = text_field(root, "selector")
    let (tokens, te) = syntax.tokenize(a, src)
    if te != ok { os.exit(84i32) }
    let (rules, re) = selector.parse_selector_list_for_rule(a, src, tokens)
    if re != ok { os.exit(85i32) }
    let want = ir.value_of(root, "e")
    let (wr, wr_array) = ir.items_of(ir.value_of(want, "r"))
    if !wr_array || wr.len != rules.len { ret false }
    let (wt, wt_array) = ir.items_of(ir.value_of(want, "tags"))
    if !wt_array || wt.len != elements.len { ret false }
    var t = 0usize
    while t < elements.len {
        let (name, is_text) = ir.string_of(wt[t])
        if !is_text || !str.eq(name, doc.nodes[usize(elements[t])].name) { ret false }
        t += 1usize
    }
    var r = 0usize
    while r < rules.len {
        let (expected, is_text) = ir.string_of(wr[r])
        if !is_text || expected.len != elements.len { ret false }
        var e = 0usize
        while e < elements.len {
            var bit = 48u8
            if match.selector_matches(&m, rules[r].selector, elements[e]) { bit = 49u8 }
            if expected[e] != bit {
                let shown = io.print(join(a, join(a, join(a, "FAIL selector ", src), " element index "), str_index(a, e)))
                ret false
            }
            e += 1usize
        }
        r += 1usize
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("css match ok")
    ret ok
}
