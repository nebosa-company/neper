// Scripting host for a browsing context (browser tracker 6): a JavaScript realm (`e.js`) wired to a document (`e.fmt.dom`).
//
// `new_context` makes a realm, hands it the node table through a hidden `__native` object of small primitives (node ids
// are numbers, -1 is "none"), and runs the DOM/window layer written in JavaScript (dom.js, generated into dom_js.e) on top
// of them; that layer is where the DOM Standard's behaviour lives. This file is only storage access, selector matching,
// markup parsing and the clock. `run_script` evaluates a classic script and reports an uncaught exception to the page,
// `pump` runs promise jobs and due timers (the page's event loop) and answers when the next timer is due.

use e.data.list as list
use e.fmt.dom as dom
use e.fmt.html as html
use e.fmt.url as url
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.str
use e.web.dom_js as dom_js

type Host = struct {
    d: *dom.Dom, now: f64, log: list.List[str], base: str, title_hint: str, errors: u32, nav: str, has_nav: bool
}

fn host_of(it: *js.Interp) -> *Host { ret mem.cast[*Host](it.host) }

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

fn nid(v: js.Value) -> u32 {
    switch v {
    case .Num as n:
        if n < 0.0f64 { ret dom.NONE }
        ret u32(n)
    default:
        ret dom.NONE
    }
}

fn idv(id: u32) -> js.Value {
    if id == dom.NONE { ret js.num_value(-1.0f64) }
    ret js.num_value(f64(id))
}

fn valid(h: *Host, id: u32) -> bool { ret id != dom.NONE && usize(id) < h.d.used }

fn sarg(it: *js.Interp, args: []const js.Value, i: usize) -> (str, err) {
    let (s, e) = js.to_string(it, arg(args, i))
    ret (s, e)
}

fn bad_node(it: *js.Interp) -> err { ret js.throw_type(it, "invalid node id") }

fn code_of(e: err) -> f64 {
    if e == ok { ret 0.0f64 }
    if e == dom.HierarchyRequest { ret 1.0f64 }
    if e == dom.NotChild { ret 2.0f64 }
    if e == dom.Full { ret 3.0f64 }
    ret 4.0f64
}

// --- node reads

fn n_kind(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let k = h.d.nodes[usize(id)].kind
    var code = 0.0f64
    if k == .Doctype { code = 1.0f64 }
    if k == .Element { code = 2.0f64 }
    if k == .Text { code = 3.0f64 }
    if k == .Comment { code = 4.0f64 }
    if k == .Document && id != h.d.root { code = 5.0f64 }
    ret (js.num_value(code), ok)
}

fn n_ns(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let ns = h.d.nodes[usize(id)].namespace
    var code = 0.0f64
    if ns == .Svg { code = 1.0f64 }
    if ns == .MathMl { code = 2.0f64 }
    if ns == .Xlink { code = 3.0f64 }
    if ns == .Xml { code = 4.0f64 }
    if ns == .Xmlns { code = 5.0f64 }
    ret (js.num_value(code), ok)
}

fn n_name(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (js.str_value(h.d.nodes[usize(id)].name), ok)
}

fn n_value(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (js.str_value(h.d.nodes[usize(id)].value), ok)
}

fn n_set_value(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    h.d.nodes[usize(id)].value = s
    h.d.version += 1u64
    ret (js.undefv(), ok)
}

fn n_set_name(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    h.d.nodes[usize(id)].name = s
    h.d.version += 1u64
    ret (js.undefv(), ok)
}

fn n_parent(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (idv(h.d.nodes[usize(id)].parent), ok)
}

fn n_first(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (idv(h.d.nodes[usize(id)].first_child), ok)
}

fn n_last(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (idv(h.d.nodes[usize(id)].last_child), ok)
}

fn n_prev(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (idv(h.d.nodes[usize(id)].previous_sibling), ok)
}

fn n_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (idv(h.d.nodes[usize(id)].next_sibling), ok)
}

fn n_root(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (idv(host_of(it).d.root), ok)
}

fn n_version(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.num_value(f64(host_of(it).d.version)), ok)
}

// --- creation and tree changes

fn ns_of_code(c: f64) -> html.Namespace {
    if c == 1.0f64 { ret .Svg }
    if c == 2.0f64 { ret .MathMl }
    if c == 3.0f64 { ret .Xlink }
    if c == 4.0f64 { ret .Xml }
    if c == 5.0f64 { ret .Xmlns }
    ret .Html
}

fn n_mk_element(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (name, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (nc, ne) = js.to_number(it, arg(args, 1usize))
    if ne != ok { ret (js.undefv(), ne) }
    let (id, e) = dom.create_element_ns(h.d, ns_of_code(nc), name)
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (idv(id), ok)
}

fn n_mk_text(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (s, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (id, e) = dom.create_text(h.d, s)
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (idv(id), ok)
}

fn n_mk_comment(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (s, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (id, e) = dom.create_comment(h.d, s)
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (idv(id), ok)
}

fn n_mk_fragment(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (id, e) = dom.create_fragment(h.d)
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (idv(id), ok)
}

fn n_mk_doctype(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (s, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (id, e) = dom.new_node(h.d, .Doctype, .Html, s, "")
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (idv(id), ok)
}

// insert(parent, child, before): 0 or an error code (1 hierarchy, 2 not a child, 3 full). `before` -1 appends.
fn n_insert(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let p = nid(arg(args, 0usize))
    let c = nid(arg(args, 1usize))
    let b = nid(arg(args, 2usize))
    if !valid(h, p) || !valid(h, c) { ret (js.undefv(), bad_node(it)) }
    if b != dom.NONE && !valid(h, b) { ret (js.undefv(), bad_node(it)) }
    ret (js.num_value(code_of(dom.insert_before(h.d, p, c, b))), ok)
}

fn n_remove(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    dom.remove(h.d, id)
    ret (js.undefv(), ok)
}

fn n_clone(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (c, e) = dom.clone_node(h.d, id, js.to_boolean(arg(args, 1usize)))
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (idv(c), ok)
}

// --- attributes

fn n_attr_count(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (js.num_value(f64(h.d.nodes[usize(id)].attributes.len)), ok)
}

fn attr_at(it: *js.Interp, h: *Host, args: []const js.Value) -> (usize, bool, u32) {
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (0usize, false, id) }
    let (n, ne) = js.to_number(it, arg(args, 1usize))
    if ne != ok || n < 0.0f64 { ret (0usize, false, id) }
    let at = usize(n)
    if at >= h.d.nodes[usize(id)].attributes.len { ret (0usize, false, id) }
    ret (at, true, id)
}

fn n_attr_name(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (at, found, id) = attr_at(it, h, args)
    if !found { ret (js.undefv(), ok) }
    ret (js.str_value(h.d.nodes[usize(id)].attributes[at].name), ok)
}

fn n_attr_value(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (at, found, id) = attr_at(it, h, args)
    if !found { ret (js.undefv(), ok) }
    ret (js.str_value(h.d.nodes[usize(id)].attributes[at].value), ok)
}

fn n_attr_ns(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (at, found, id) = attr_at(it, h, args)
    if !found { ret (js.undefv(), ok) }
    let ns = h.d.nodes[usize(id)].attributes[at].namespace
    var code = 0.0f64
    if ns == .Svg { code = 1.0f64 }
    if ns == .MathMl { code = 2.0f64 }
    if ns == .Xlink { code = 3.0f64 }
    if ns == .Xml { code = 4.0f64 }
    if ns == .Xmlns { code = 5.0f64 }
    ret (js.num_value(code), ok)
}

// attr_find(id, name): index of the attribute `name` (case-folded on HTML elements) or -1.
fn n_attr_find(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (name, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (at, found) = dom.find_attr(h.d, id, name)
    if !found { ret (js.num_value(-1.0f64), ok) }
    ret (js.num_value(f64(at)), ok)
}

fn n_attr_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (name, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (v, found) = dom.get_attribute(h.d, id, name)
    if !found { ret (js.undefv(), ok) }
    ret (js.str_value(v), ok)
}

fn n_attr_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (name, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (value, ve) = sarg(it, args, 2usize)
    if ve != ok { ret (js.undefv(), ve) }
    let e = dom.set_attribute(h.d, id, name, value)
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (js.undefv(), ok)
}

// attr_put(id, name, value, ns): appends or replaces the attribute with exactly this stored name (no case folding).
fn n_attr_put(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (name, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (value, ve) = sarg(it, args, 2usize)
    if ve != ok { ret (js.undefv(), ve) }
    let (nc, ne) = js.to_number(it, arg(args, 3usize))
    if ne != ok { ret (js.undefv(), ne) }
    let old = h.d.nodes[usize(id)].attributes
    var at = old.len
    var i = 0usize
    while i < old.len {
        if str.eq(old[i].name, name) && old[i].namespace == ns_of_code(nc) { at = i }
        i += 1usize
    }
    var grown_len = old.len
    if at == old.len { grown_len = old.len + 1usize }
    let (copy, ce) = mem.alloc[html.Attribute](h.d.a, grown_len)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    mem.copy[html.Attribute](copy[..old.len], old)
    copy[at] = html.Attribute { namespace: ns_of_code(nc), name: name, value: value }
    h.d.nodes[usize(id)].attributes = copy
    h.d.version += 1u64
    ret (js.num_value(f64(at)), ok)
}

fn n_attr_del_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (at, found, id) = attr_at(it, h, args)
    if !found { ret (js.undefv(), ok) }
    let old = h.d.nodes[usize(id)].attributes
    let (shrunk, ce) = mem.alloc[html.Attribute](h.d.a, old.len - 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    mem.copy[html.Attribute](shrunk[..at], old[..at])
    mem.copy[html.Attribute](shrunk[at..], old[at + 1usize..])
    h.d.nodes[usize(id)].attributes = shrunk
    h.d.version += 1u64
    ret (js.undefv(), ok)
}

fn n_attr_set_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (at, found, id) = attr_at(it, h, args)
    if !found { ret (js.undefv(), ok) }
    let (value, ve) = sarg(it, args, 2usize)
    if ve != ok { ret (js.undefv(), ve) }
    let old = h.d.nodes[usize(id)].attributes
    let (copy, ce) = mem.alloc[html.Attribute](h.d.a, old.len)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    mem.copy[html.Attribute](copy, old)
    copy[at] = html.Attribute { namespace: old[at].namespace, name: old[at].name, value: value }
    h.d.nodes[usize(id)].attributes = copy
    h.d.version += 1u64
    ret (js.undefv(), ok)
}

// --- content

fn n_text_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, e) = dom.text_content(h.d.a, h.d, id)
    if e != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    ret (js.str_value(s), ok)
}

fn n_text_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let e = dom.set_text_content(h.d, id, s)
    if e != ok { ret (js.undefv(), js.throw_range(it, "document is full")) }
    ret (js.undefv(), ok)
}

fn n_inner_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, e) = dom.inner_html(h.d.a, h.d, id)
    if e != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    ret (js.str_value(s), ok)
}

fn n_outer_get(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, e) = dom.outer_html(h.d.a, h.d, id)
    if e != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    ret (js.str_value(s), ok)
}

fn parse_options() -> html.Options {
    ret html.Options { max_bytes: 67108864usize, max_nodes: 1000000usize, max_attributes: 256usize, max_depth: 512u16, preserve_comments: true }
}

fn n_inner_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (s, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let e = dom.set_inner_html(h.d, id, s, parse_options())
    if e != ok { ret (js.undefv(), js.throw_range(it, "could not parse markup")) }
    ret (js.undefv(), ok)
}

// --- selectors

fn collect(it: *js.Interp, h: *Host, ids: []dom.NodeId, n: usize) -> (js.Value, err) {
    let arr = js.new_array(it)
    var i = 0usize
    while i < n {
        try js.array_push(it, arr, idv(ids[i]))
        i += 1usize
    }
    ret (js.obj_value(arr), ok)
}

// qs(scope, selector): the first match, -1 for none, -2 for a selector syntax error.
fn n_qs(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (sel, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let mark = mem.mark(it.a)
    let (found, e) = dom.query_selector(it.a, h.d, id, sel)
    if e != ok { ret (js.num_value(-2.0f64), ok) }
    ret (idv(found), ok)
}

// qsa(scope, selector): an array of ids, or null for a syntax error.
fn n_qsa(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (sel, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (buf, be) = mem.alloc[dom.NodeId](it.a, h.d.used + 1usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let (n, e) = dom.query_selector_all(it.a, h.d, id, sel, buf)
    if e != ok { ret (js.null_value(), ok) }
    let (arr, ae) = collect(it, h, buf, n)
    if ae != ok { ret (js.undefv(), ae) }
    ret (arr, ok)
}

// matches(id, selector): true/false, or null for a syntax error.
fn n_matches(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (sel, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (m, e) = dom.matches(it.a, h.d, id, sel)
    if e != ok { ret (js.null_value(), ok) }
    ret (js.bool_value(m), ok)
}

fn n_closest(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (sel, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let (c, e) = dom.closest(it.a, h.d, id, sel)
    if e != ok { ret (js.num_value(-2.0f64), ok) }
    ret (idv(c), ok)
}

// --- the clock and the console

fn n_now(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.num_value(host_of(it).now), ok)
}

fn n_log(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (level, le) = sarg(it, args, 0usize)
    if le != ok { ret (js.undefv(), le) }
    let (text, te) = sarg(it, args, 1usize)
    if te != ok { ret (js.undefv(), te) }
    try list.push[str](&h.log, js.str_concat3(it, level, ": ", text))
    ret (js.undefv(), ok)
}

fn n_base(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.str_value(host_of(it).base), ok)
}

// --- URLs

fn url_components(it: *js.Interp, u: *const url.Url) -> (js.Value, err) {
    let arr = js.new_array(it)
    var host_text = ""
    if u.has_host { host_text = u.host }
    try js.array_push(it, arr, js.str_value(url.href(it.a, u, false)))
    try js.array_push(it, arr, js.str_value(url.protocol(it.a, u)))
    try js.array_push(it, arr, js.str_value(u.username))
    try js.array_push(it, arr, js.str_value(u.password))
    try js.array_push(it, arr, js.str_value(url.host_port(it.a, u)))
    try js.array_push(it, arr, js.str_value(host_text))
    try js.array_push(it, arr, js.str_value(url.port_text(it.a, u)))
    try js.array_push(it, arr, js.str_value(u.path))
    try js.array_push(it, arr, js.str_value(url.search(it.a, u)))
    try js.array_push(it, arr, js.str_value(url.hash(it.a, u)))
    try js.array_push(it, arr, js.str_value(url.origin(it.a, u)))
    ret (js.obj_value(arr), ok)
}

// urlParse(input, base|null): [href, protocol, username, password, host, hostname, port, pathname, search, hash, origin] or null.
fn n_url_parse(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (input, ie) = sarg(it, args, 0usize)
    if ie != ok { ret (js.undefv(), ie) }
    var u: url.Url = zero
    var pe: err = ok
    if js.is_nullish(arg(args, 1usize)) {
        let (u0, pe0) = url.parse(it.a, input, &u, false)
        u = u0
        pe = pe0
    } else {
        let (base_text, be) = sarg(it, args, 1usize)
        if be != ok { ret (js.undefv(), be) }
        let (u1, pe1) = url.parse_against(it.a, input, base_text)
        u = u1
        pe = pe1
    }
    if pe != ok { ret (js.null_value(), ok) }
    let (c, ce) = url_components(it, &u)
    if ce != ok { ret (js.undefv(), ce) }
    ret (c, ok)
}

// urlSet(href, component, value): the components after the URL API setter ran, or null if href does not parse.
fn n_url_set(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (href, he) = sarg(it, args, 0usize)
    if he != ok { ret (js.undefv(), he) }
    let (comp, ce0) = sarg(it, args, 1usize)
    if ce0 != ok { ret (js.undefv(), ce0) }
    let (value, ve) = sarg(it, args, 2usize)
    if ve != ok { ret (js.undefv(), ve) }
    var none: url.Url = zero
    let (u, pe) = url.parse(it.a, href, &none, false)
    if pe != ok { ret (js.null_value(), ok) }
    var out = u
    if str.eq(comp, "protocol") { out = url.set_protocol(it.a, &u, value) } else if str.eq(comp, "username") { out = url.set_username(it.a, &u, value) } else if str.eq(comp, "password") { out = url.set_password(it.a, &u, value) } else if str.eq(comp, "host") { out = url.set_host(it.a, &u, value) } else if str.eq(comp, "hostname") { out = url.set_hostname(it.a, &u, value) } else if str.eq(comp, "port") { out = url.set_port(it.a, &u, value) } else if str.eq(comp, "pathname") { out = url.set_pathname(it.a, &u, value) } else if str.eq(comp, "search") { out = url.set_search(it.a, &u, value) } else if str.eq(comp, "searchRaw") { out = url.set_search(it.a, &u, value) } else if str.eq(comp, "hash") { out = url.set_hash(it.a, &u, value) }
    let (c, ce) = url_components(it, &out)
    if ce != ok { ret (js.undefv(), ce) }
    ret (c, ok)
}

// navigate(href): records the requested navigation for the page that owns the context.
fn n_navigate(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (href, he) = sarg(it, args, 0usize)
    if he != ok { ret (js.undefv(), he) }
    h.nav = href
    h.has_nav = true
    ret (js.undefv(), ok)
}

// runScript(source, name): evaluates a classic script; false after an uncaught exception (already reported to the page).
fn n_run_script(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (src, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (name, ne) = sarg(it, args, 1usize)
    if ne != ok { ret (js.undefv(), ne) }
    ret (js.bool_value(run_script(it, src, name)), ok)
}

// --- the context

fn install_natives(it: *js.Interp) {
    let n = js.new_plain(it)
    let e0 = js.define_data(it, it.global, js.key_of("__native"), js.obj_value(n), js.P_HIDDEN)
    js.add_method(it, n, "kind", 1u32, n_kind)
    js.add_method(it, n, "ns", 1u32, n_ns)
    js.add_method(it, n, "name", 1u32, n_name)
    js.add_method(it, n, "setName", 2u32, n_set_name)
    js.add_method(it, n, "value", 1u32, n_value)
    js.add_method(it, n, "setValue", 2u32, n_set_value)
    js.add_method(it, n, "parent", 1u32, n_parent)
    js.add_method(it, n, "first", 1u32, n_first)
    js.add_method(it, n, "last", 1u32, n_last)
    js.add_method(it, n, "prev", 1u32, n_prev)
    js.add_method(it, n, "next", 1u32, n_next)
    js.add_method(it, n, "root", 0u32, n_root)
    js.add_method(it, n, "version", 0u32, n_version)
    js.add_method(it, n, "mkElement", 2u32, n_mk_element)
    js.add_method(it, n, "mkText", 1u32, n_mk_text)
    js.add_method(it, n, "mkComment", 1u32, n_mk_comment)
    js.add_method(it, n, "mkFragment", 0u32, n_mk_fragment)
    js.add_method(it, n, "mkDoctype", 1u32, n_mk_doctype)
    js.add_method(it, n, "insert", 3u32, n_insert)
    js.add_method(it, n, "remove", 1u32, n_remove)
    js.add_method(it, n, "clone", 2u32, n_clone)
    js.add_method(it, n, "attrCount", 1u32, n_attr_count)
    js.add_method(it, n, "attrName", 2u32, n_attr_name)
    js.add_method(it, n, "attrValue", 2u32, n_attr_value)
    js.add_method(it, n, "attrNs", 2u32, n_attr_ns)
    js.add_method(it, n, "attrFind", 2u32, n_attr_find)
    js.add_method(it, n, "attrGet", 2u32, n_attr_get)
    js.add_method(it, n, "attrSet", 3u32, n_attr_set)
    js.add_method(it, n, "attrPut", 4u32, n_attr_put)
    js.add_method(it, n, "attrDelAt", 2u32, n_attr_del_at)
    js.add_method(it, n, "attrSetAt", 3u32, n_attr_set_at)
    js.add_method(it, n, "textGet", 1u32, n_text_get)
    js.add_method(it, n, "textSet", 2u32, n_text_set)
    js.add_method(it, n, "innerGet", 1u32, n_inner_get)
    js.add_method(it, n, "innerSet", 2u32, n_inner_set)
    js.add_method(it, n, "outerGet", 1u32, n_outer_get)
    js.add_method(it, n, "qs", 2u32, n_qs)
    js.add_method(it, n, "qsa", 2u32, n_qsa)
    js.add_method(it, n, "matches", 2u32, n_matches)
    js.add_method(it, n, "closest", 2u32, n_closest)
    js.add_method(it, n, "now", 0u32, n_now)
    js.add_method(it, n, "log", 2u32, n_log)
    js.add_method(it, n, "base", 0u32, n_base)
    js.add_method(it, n, "urlParse", 2u32, n_url_parse)
    js.add_method(it, n, "urlSet", 3u32, n_url_set)
    js.add_method(it, n, "navigate", 1u32, n_navigate)
    js.add_method(it, n, "runScript", 2u32, n_run_script)
}

// A realm bound to `d`. `base` is the document's URL (location.href).
fn new_context(a: *mem.Arena, d: *dom.Dom, base: str) -> (*js.Interp, err) {
    let it = try realm.new_realm(a)
    let (cell, ce) = mem.alloc[Host](a, 1usize)
    if ce != ok { ret (it, ce) }
    var blank: Host = zero
    cell[0usize] = blank
    cell[0usize].d = d
    cell[0usize].base = base
    let (l, le) = list.init[str](a, 64usize)
    if le != ok { ret (it, le) }
    cell[0usize].log = l
    it.host = mem.cast[*void](&cell[0usize])
    install_natives(it)
    let (src, se) = dom_js.source(a)
    if se != ok { ret (it, se) }
    it.step_limit = 300000000u64
    let (v, e) = js.eval_source(it, src)
    it.step_limit = 0u64
    it.steps = 0u64
    if e != ok { ret (it, e) }
    ret (it, ok)
}

// --- running code

// A description of the pending exception, for diagnostics.
fn describe_thrown(it: *js.Interp) -> str {
    let (s, e) = js.to_string(it, it.thrown)
    if e != ok { ret "uncaught exception" }
    ret s
}

// Hands the pending exception to `window.__reportError`.
fn report_thrown(it: *js.Interp, name: str) {
    let thrown = it.thrown
    let (rep, re) = js.get_prop(it, it.global, js.key_of("__reportError"), js.obj_value(it.global))
    if re == ok && js.is_callable(rep) {
        let (cell, ce) = mem.alloc[js.Value](it.a, 2usize)
        if ce == ok {
            cell[0usize] = thrown
            cell[1usize] = js.str_value(name)
            let (rv, rve) = js.call_function(it, rep, js.obj_value(it.global), cell[0usize..2usize])
        }
    }
    host_of(it).errors += 1u32
}

// Evaluates a classic script; an uncaught exception goes to `window.__reportError`, then false is answered.
fn run_script(it: *js.Interp, source: str, name: str) -> bool {
    let (v, e) = js.eval_source(it, source)
    if e == ok { ret true }
    report_thrown(it, name)
    ret false
}

// Calls `__lifecycle[name]()`: the document's readyState changes and its load events.
fn lifecycle(it: *js.Interp, name: str) {
    let (lc, le) = js.get_prop(it, it.global, js.key_of("__lifecycle"), js.obj_value(it.global))
    if le != ok || !js.is_object(lc) { ret }
    let (f, fe) = js.get_prop(it, js.as_object(lc), js.key_of(name), lc)
    if fe != ok || !js.is_callable(f) { ret }
    let (r, re) = js.call_function(it, f, lc, js.zero_args())
    if re != ok { report_thrown(it, name) }
}

// One turn of the event loop at the current clock: promise jobs, then the timers that are due. Answers the clock time of the
// next pending timer, or -1 when nothing is scheduled.
fn pump_once(it: *js.Interp) -> f64 {
    let je = js.run_jobs(it)
    let (run, re) = js.get_prop(it, it.global, js.key_of("__runTimers"), js.obj_value(it.global))
    if re != ok || !js.is_callable(run) { ret -1.0f64 }
    let (nv, ne) = js.call_function(it, run, js.obj_value(it.global), js.zero_args())
    if ne != ok { ret -1.0f64 }
    let je2 = js.run_jobs(it)
    switch nv {
    case .Num as n:
        ret n
    default:
        ret -1.0f64
    }
    ret -1.0f64
}

// Runs the event loop with a virtual clock until nothing is scheduled or `limit_ms` of virtual time has passed.
fn pump(it: *js.Interp, limit_ms: f64) {
    let h = host_of(it)
    let deadline = h.now + limit_ms
    var guard = 0u32
    while guard < 1000000u32 {
        guard += 1u32
        let next = pump_once(it)
        if next < 0.0f64 { break }
        if next > deadline { break }
        if next > h.now { h.now = next }
    }
}

fn advance(it: *js.Interp, ms: f64) { host_of(it).now += ms }
