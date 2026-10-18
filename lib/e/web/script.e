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
use e.gfx.cssvalue as cv
use e.js.interp as js
use e.js.module as module
use e.js.realm as realm
use e.mem
use e.str
use e.web.dom_js as dom_js

// A synchronous fetch supplied by the page: (context, url, referrer) -> (body text, status, reached the server).
type FetchFn = fn(*void, str, str) -> (str, u16, bool)

// Layout and style answers from the page that owns the view: node geometry (`what` 0 bounding client rect, 1 offset box,
// 2 client box, 3 scroll size, 4 viewport and scroll position; results in the 8 numbers) and computed style text.
type GeomFn = fn(*void, u32, u8, []f64) -> bool
type StyleFn = fn(*void, u32, str) -> (str, bool)

// A full request for the page's network: (context, method, url, header lines "Name: value" joined by newlines, body bytes).
// Fills the result and answers false when the request could not be made.
type NetResult = struct { status: u16, status_text: str, url: str, headers: str, body: []const u8 }
type NetFn = fn(*void, str, str, str, []const u8, *NetResult) -> bool

type Host = struct {
    d: *dom.Dom, now: f64, log: list.List[str], base: str, title_hint: str, errors: u32, nav: str, has_nav: bool,
    fetch_ctx: *void, fetch_fn: FetchFn, has_fetch: bool, dirty: bool,
    view_ctx: *void, geom_fn: GeomFn, style_fn: StyleFn, has_view: bool,
    net_ctx: *void, net_fn: NetFn, has_net: bool, inline_modules: u32,
    parent: *js.Interp, has_parent: bool, children: list.List[*js.Interp], dom_prog: *void, has_dom_prog: bool
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
    // The selector and matcher are scratch: the answer is a number, so the arena goes back to where it was.
    let mark = mem.mark(it.a)
    let (found, e) = dom.query_selector(it.a, h.d, id, sel)
    mem.reset(it.a, mark)
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
    // Pass one counts the matches in scratch memory; pass two fills an array sized for them, again in scratch memory.
    let mark1 = mem.mark(it.a)
    let (buf1, be1) = mem.alloc[dom.NodeId](it.a, h.d.used + 1usize)
    if be1 != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let (n, e) = dom.query_selector_all(it.a, h.d, id, sel, buf1)
    mem.reset(it.a, mark1)
    if e != ok { ret (js.null_value(), ok) }
    let arr = js.new_array(it)
    js.reserve_elems(it, arr, n)
    let mark2 = mem.mark(it.a)
    let (buf, be) = mem.alloc[dom.NodeId](it.a, h.d.used + 1usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let (n2, e2) = dom.query_selector_all(it.a, h.d, id, sel, buf)
    var i = 0usize
    while i < n2 {
        try js.array_push(it, arr, idv(buf[i]))
        i += 1usize
    }
    mem.reset(it.a, mark2)
    ret (js.obj_value(arr), ok)
}

// matches(id, selector): true/false, or null for a syntax error.
fn n_matches(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (sel, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let mark = mem.mark(it.a)
    let (m, e) = dom.matches(it.a, h.d, id, sel)
    mem.reset(it.a, mark)
    if e != ok { ret (js.null_value(), ok) }
    ret (js.bool_value(m), ok)
}

fn n_closest(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (sel, se) = sarg(it, args, 1usize)
    if se != ok { ret (js.undefv(), se) }
    let mark = mem.mark(it.a)
    let (c, e) = dom.closest(it.a, h.d, id, sel)
    mem.reset(it.a, mark)
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

fn n_run_jobs(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let e = js.run_jobs(it)
    if e != ok { ret (js.undefv(), e) }
    ret (js.undefv(), ok)
}

// fetchText(url): [status, text] or null when the page has no network or the request failed.
fn n_fetch_text(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    if !h.has_fetch { ret (js.null_value(), ok) }
    let (u, ue) = sarg(it, args, 0usize)
    if ue != ok { ret (js.undefv(), ue) }
    let (text, status, reached) = h.fetch_fn(h.fetch_ctx, u, h.base)
    if !reached { ret (js.null_value(), ok) }
    let arr = js.new_array(it)
    try js.array_push(it, arr, js.num_value(f64(status)))
    try js.array_push(it, arr, js.str_value(text))
    ret (js.obj_value(arr), ok)
}

// geom(id, what): an array of numbers for the node, or null when it has no box.
fn n_geom(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    if !h.has_view { ret (js.null_value(), ok) }
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (what, we) = js.to_number(it, arg(args, 1usize))
    if we != ok { ret (js.undefv(), we) }
    var out: [8]f64 = zero
    if !h.geom_fn(h.view_ctx, id, u8(what), out[0usize..8usize]) { ret (js.null_value(), ok) }
    let arr = js.new_array(it)
    var i = 0usize
    while i < 8usize {
        try js.array_push(it, arr, js.num_value(out[i]))
        i += 1usize
    }
    ret (js.obj_value(arr), ok)
}

// computed(id, property): the computed value text, or undefined when the property is not modelled.
fn n_computed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    if !h.has_view { ret (js.undefv(), ok) }
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (prop, pe) = sarg(it, args, 1usize)
    if pe != ok { ret (js.undefv(), pe) }
    let (text, known) = h.style_fn(h.view_ctx, id, prop)
    if !known { ret (js.undefv(), ok) }
    ret (js.str_value(text), ok)
}

// --- binary strings: one code point (0..255) per byte, the form bodies take inside scripts

fn latin1_to_bytes(a: *mem.Arena, s: str) -> ([]u8, err) {
    let out = try mem.alloc[u8](a, s.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c < 128u8 {
            out[n] = c
            i += 1usize
        } else if c == 194u8 && i + 1usize < s.len {
            out[n] = s[i + 1usize]
            i += 2usize
        } else if c == 195u8 && i + 1usize < s.len {
            out[n] = s[i + 1usize] + 64u8
            i += 2usize
        } else {
            out[n] = 63u8
            i += 1usize
        }
        n += 1usize
    }
    ret (out[0usize..n], ok)
}

fn bytes_to_latin1(a: *mem.Arena, b: []const u8) -> (str, err) {
    var bb = try str.builder(a, b.len * 2usize + 8usize)
    var i = 0usize
    while i < b.len {
        let c = b[i]
        if c < 128u8 {
            try str.push_byte(&bb, c)
        } else if c < 192u8 {
            try str.push_byte(&bb, 194u8)
            try str.push_byte(&bb, c)
        } else {
            try str.push_byte(&bb, 195u8)
            try str.push_byte(&bb, c - 64u8)
        }
        i += 1usize
    }
    ret (str.done(&bb), ok)
}

// UTF-8 decoding with U+FFFD for invalid sequences.
fn decode_utf8_lossy(a: *mem.Arena, b: []const u8) -> (str, err) {
    var bb = try str.builder(a, b.len + 16usize)
    var i = 0usize
    while i < b.len {
        let c = b[i]
        var len = 0usize
        if c < 128u8 { len = 1usize } else if c >= 194u8 && c <= 223u8 { len = 2usize } else if c >= 224u8 && c <= 239u8 { len = 3usize } else if c >= 240u8 && c <= 244u8 { len = 4usize }
        var good = len > 0usize && i + len <= b.len
        if good && len > 1usize {
            var k = 1usize
            while k < len {
                if (b[i + k] & 192u8) != 128u8 { good = false }
                k += 1usize
            }
            if good && len == 3usize {
                if c == 224u8 && b[i + 1usize] < 160u8 { good = false }
                if c == 237u8 && b[i + 1usize] > 159u8 { good = false }
            }
            if good && len == 4usize {
                if c == 240u8 && b[i + 1usize] < 144u8 { good = false }
                if c == 244u8 && b[i + 1usize] > 143u8 { good = false }
            }
        }
        if good {
            var k2 = 0usize
            while k2 < len {
                try str.push_byte(&bb, b[i + k2])
                k2 += 1usize
            }
            i += len
        } else {
            try str.push_byte(&bb, 239u8)
            try str.push_byte(&bb, 191u8)
            try str.push_byte(&bb, 189u8)
            i += 1usize
        }
    }
    ret (str.done(&bb), ok)
}

fn n_utf8_encode(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (out, oe) = bytes_to_latin1(it.a, s)
    if oe != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    ret (js.str_value(out), ok)
}

fn n_utf8_decode(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = sarg(it, args, 0usize)
    if se != ok { ret (js.undefv(), se) }
    let (bytes, be) = latin1_to_bytes(it.a, s)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let (out, oe) = decode_utf8_lossy(it.a, bytes)
    if oe != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    ret (js.str_value(out), ok)
}

// net(method, url, headerLines, bodyBinary): the response as {status, statusText, url, headers: [[name, value]], body}, or null.
fn n_net(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    if !h.has_net { ret (js.null_value(), ok) }
    let (method, me) = sarg(it, args, 0usize)
    if me != ok { ret (js.undefv(), me) }
    let (u, ue) = sarg(it, args, 1usize)
    if ue != ok { ret (js.undefv(), ue) }
    let (hdrs, he) = sarg(it, args, 2usize)
    if he != ok { ret (js.undefv(), he) }
    let (body_text, be) = sarg(it, args, 3usize)
    if be != ok { ret (js.undefv(), be) }
    let (body, bye) = latin1_to_bytes(it.a, body_text)
    if bye != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var res: NetResult = zero
    if !h.net_fn(h.net_ctx, method, u, hdrs, body, &res) { ret (js.null_value(), ok) }
    let o = js.new_plain(it)
    try js.set_named(it, o, "status", js.num_value(f64(res.status)))
    try js.set_named(it, o, "statusText", js.str_value(res.status_text))
    try js.set_named(it, o, "url", js.str_value(res.url))
    let harr = js.new_array(it)
    var pos = 0usize
    while pos < res.headers.len {
        var end = pos
        while end < res.headers.len && res.headers[end] != 10u8 { end += 1usize }
        let line = res.headers[pos..end]
        pos = end + 1usize
        let (name, value, found) = str.split_once(line, ":")
        if found {
            let pair = js.new_array(it)
            try js.array_push(it, pair, js.str_value(str.trim(name)))
            try js.array_push(it, pair, js.str_value(str.trim(value)))
            try js.array_push(it, harr, js.obj_value(pair))
        }
    }
    try js.set_named(it, o, "headers", js.obj_value(harr))
    let (binary, ble) = bytes_to_latin1(it.a, res.body)
    if ble != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    try js.set_named(it, o, "body", js.str_value(binary))
    ret (js.obj_value(o), ok)
}

// --- modules

// The module loader of a page: a specifier is a URL resolved against the referring module, fetched through the page.
fn load_module_hook(it: *js.Interp, referrer: str, spec: str) -> (*void, err) {
    let h = host_of(it)
    if !h.has_fetch { ret (zero, js.throw_type(it, "modules cannot be loaded here")) }
    var rel_ok = false
    if spec.len > 0usize && spec[0usize] == 47u8 { rel_ok = true }
    if spec.len > 1usize && spec[0usize] == 46u8 && (spec[1usize] == 47u8 || spec[1usize] == 46u8) { rel_ok = true }
    if str.starts_with(spec, "http:") || str.starts_with(spec, "https:") || str.starts_with(spec, "file:") || str.starts_with(spec, "data:") || str.starts_with(spec, "blob:") { rel_ok = true }
    if !rel_ok { ret (zero, js.throw_type(it, js.str_concat3(it, "Failed to resolve module specifier '", spec, "': relative references must start with / ./ or ../"))) }
    var base = referrer
    let (hash_at, has_hash) = str.find(referrer, "#")
    if has_hash { base = referrer[0usize..hash_at] }
    var none: url.Url = zero
    let (b, be) = url.parse(it.a, base, &none, false)
    if be != ok { ret (zero, js.throw_type(it, "invalid base URL")) }
    let (u, ue) = url.parse(it.a, spec, &b, true)
    if ue != ok { ret (zero, js.throw_type(it, js.str_concat3(it, "Failed to resolve module specifier '", spec, "'"))) }
    let href = url.href(it.a, &u, true)
    let (found, has) = module.find(it, href)
    if has { ret (mem.cast[*void](found), ok) }
    let (text, status, reached) = h.fetch_fn(h.fetch_ctx, href, referrer)
    if !reached || status < 200u16 || status >= 300u16 { ret (zero, js.throw_type(it, js.str_concat3(it, "Failed to fetch dynamically imported module: ", href, ""))) }
    let (m, me) = module.new_module(it, href, text)
    if me != ok { ret (zero, me) }
    ret (mem.cast[*void](m), ok)
}

fn module_rejected(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    it.thrown = arg(args, 0usize)
    report_thrown(it, "module")
    ret (js.undefv(), ok)
}

// runModule(url, source): runs the module at `url`, or the inline module `source` (named after the document); errors, also
// those of its evaluation, are reported to the page. Answers true when it was started.
fn n_run_module(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (u, ue) = sarg(it, args, 0usize)
    if ue != ok { ret (js.undefv(), ue) }
    var m: *module.Module = zero
    if js.is_undefined(arg(args, 1usize)) {
        let (mp, le) = load_module_hook(it, h.base, u)
        if le != ok {
            if le == js.Throw { report_thrown(it, u) }
            ret (js.bool_value(false), ok)
        }
        m = module.module_of(mp)
    } else {
        let (src, se) = sarg(it, args, 1usize)
        if se != ok { ret (js.undefv(), se) }
        h.inline_modules += 1u32
        let (nm, nme) = module.new_module(it, js.str_concat3(it, u, "#module", js.number_to_string(it.a, f64(h.inline_modules))), src)
        if nme != ok {
            if nme == js.Throw { report_thrown(it, u) }
            ret (js.bool_value(false), ok)
        }
        m = nm
    }
    it.script_url = m.url
    let (p, pe) = module.run_module(it, m)
    if pe != ok {
        if pe == js.Throw { report_thrown(it, u) }
        ret (js.bool_value(false), ok)
    }
    let on_rej = js.make_native(it, "", 1u32, module_rejected)
    let te = js.promise_then_raw(it, js.as_object(p), js.undefv(), js.obj_value(on_rej))
    ret (js.bool_value(true), ok)
}

// --- frames
//
// An iframe is a context of its own (a document and a realm that share the arena); the parent keeps the child's interpreter
// so its event loop turns with the parent's, and the scripts of either reach the other's global through ordinary property
// access: calls into a function of the other realm run in that realm (js.call_function).

fn child_of(h: *Host, g: js.Value) -> (*js.Interp, bool) {
    var i = 0usize
    while i < h.children.len {
        let c = h.children.items[i]
        if js.is_object(g) && js.strict_equals(js.obj_value(c.global), g) { ret (c, true) }
        i += 1usize
    }
    ret (js.null_interp(), false)
}

// frameCreate(markup, url): a new context over the document parsed from `markup`; answers its global object.
fn n_frame_create(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (markup, me) = sarg(it, args, 0usize)
    if me != ok { ret (js.undefv(), me) }
    let (address, ue) = sarg(it, args, 1usize)
    if ue != ok { ret (js.undefv(), ue) }
    let (cell, ce) = mem.alloc[dom.Dom](it.a, 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let (tree, pe) = dom.parse(it.a, markup, parse_options(), 1024usize)
    if pe != ok { ret (js.undefv(), js.throw_range(it, "could not parse the frame document")) }
    cell[0usize] = tree
    let (cit, xe) = new_context_in(it.a, &cell[0usize], address, it)
    if xe != ok { ret (js.undefv(), js.throw_range(it, "could not create the frame context")) }
    let ch = host_of(cit)
    ch.fetch_ctx = h.fetch_ctx
    ch.fetch_fn = h.fetch_fn
    ch.has_fetch = h.has_fetch
    ch.net_ctx = h.net_ctx
    ch.net_fn = h.net_fn
    ch.has_net = h.has_net
    ch.now = h.now
    ch.parent = it
    ch.has_parent = true
    try list.push[*js.Interp](&h.children, cit)
    ret (js.obj_value(cit.global), ok)
}

// frameStart(window): runs the frame document's scripts and fires its load events.
fn n_frame_start(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let (c, found) = child_of(h, arg(args, 0usize))
    if !found { ret (js.bool_value(false), ok) }
    lifecycle(c, "run")
    let nx = pump_once(c)
    ret (js.bool_value(true), ok)
}

// frameDrop(window): the browsing context is discarded; its timers stop.
fn n_frame_drop(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    var i = 0usize
    while i < h.children.len {
        if js.is_object(arg(args, 0usize)) && js.strict_equals(js.obj_value(h.children.items[i].global), arg(args, 0usize)) {
            var j = i
            while j + 1usize < h.children.len {
                h.children.items[j] = h.children.items[j + 1usize]
                j += 1usize
            }
            h.children.len -= 1usize
            ret (js.bool_value(true), ok)
        }
        i += 1usize
    }
    ret (js.bool_value(false), ok)
}

fn n_parent_window(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    if h.has_parent { ret (js.obj_value(h.parent.global), ok) }
    ret (js.obj_value(it.global), ok)
}

fn n_top_window(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var cur = it
    var guard = 0u32
    while host_of(cur).has_parent && guard < 64u32 {
        cur = host_of(cur).parent
        guard += 1u32
    }
    ret (js.obj_value(cur.global), ok)
}

// callerWindow(): the global of the realm whose script called into this one, or this one's own.
fn n_caller_window(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if it.has_caller { ret (js.obj_value(it.caller.global), ok) }
    ret (js.obj_value(it.global), ok)
}

// frameCount(): how many frames are children of this window.
fn n_frame_count(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.num_value(f64(host_of(it).children.len)), ok)
}

// realmOf(object): the global of the realm the object was made in when that is not this one, else undefined.
fn n_realm_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_object(v) { ret (js.undefv(), ok) }
    let o = js.as_object(v)
    if o.realm == it || o.realm == js.null_interp() { ret (js.undefv(), ok) }
    ret (js.obj_value(o.realm.global), ok)
}

// parseColor(text): the CSS colour as "#rrggbb" (alpha dropped), or null when it is not one.
fn n_parse_color(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (t, te) = sarg(it, args, 0usize)
    if te != ok { ret (js.undefv(), te) }
    let (argb, good) = cv.parse_color(it.a, t)
    if !good { ret (js.null_value(), ok) }
    let digits = "0123456789abcdef"
    var bb = try str.builder(it.a, 16usize)
    try str.push_byte(&bb, 35u8)
    var shift = 20u32
    while true {
        try str.push_byte(&bb, digits[usize((argb >> shift) & 15u32)])
        if shift == 0u32 { break }
        shift -= 4u32
    }
    ret (js.str_value(str.done(&bb)), ok)
}

// flags(id) / setFlags(id, mask, on): the dynamic selector states of a node (checkedness, :popover-open, :defined, focus).
fn n_flags(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    ret (js.num_value(f64(h.d.nodes[usize(id)].flags)), ok)
}

fn n_set_flags(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let h = host_of(it)
    let id = nid(arg(args, 0usize))
    if !valid(h, id) { ret (js.undefv(), bad_node(it)) }
    let (mv, me) = js.to_number(it, arg(args, 1usize))
    if me != ok { ret (js.undefv(), me) }
    let mask = u32(mv)
    let cur = h.d.nodes[usize(id)].flags
    var next = cur & (4294967295u32 - mask)
    if js.to_boolean(arg(args, 2usize)) { next = next | mask }
    if next != cur {
        h.d.nodes[usize(id)].flags = next
        h.d.version += 1u64
    }
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
    js.add_method(it, n, "runJobs", 0u32, n_run_jobs)
    js.add_method(it, n, "fetchText", 1u32, n_fetch_text)
    js.add_method(it, n, "geom", 2u32, n_geom)
    js.add_method(it, n, "runModule", 2u32, n_run_module)
    js.add_method(it, n, "frameCreate", 2u32, n_frame_create)
    js.add_method(it, n, "frameStart", 1u32, n_frame_start)
    js.add_method(it, n, "frameDrop", 1u32, n_frame_drop)
    js.add_method(it, n, "parentWindow", 0u32, n_parent_window)
    js.add_method(it, n, "topWindow", 0u32, n_top_window)
    js.add_method(it, n, "callerWindow", 0u32, n_caller_window)
    js.add_method(it, n, "frameCount", 0u32, n_frame_count)
    js.add_method(it, n, "realmOf", 1u32, n_realm_of)
    js.add_method(it, n, "parseColor", 1u32, n_parse_color)
    js.add_method(it, n, "flags", 1u32, n_flags)
    js.add_method(it, n, "setFlags", 3u32, n_set_flags)
    js.add_method(it, n, "utf8Encode", 1u32, n_utf8_encode)
    js.add_method(it, n, "utf8Decode", 1u32, n_utf8_decode)
    js.add_method(it, n, "net", 4u32, n_net)
    js.add_method(it, n, "computed", 2u32, n_computed)
    js.add_method(it, n, "urlParse", 2u32, n_url_parse)
    js.add_method(it, n, "urlSet", 3u32, n_url_set)
    js.add_method(it, n, "navigate", 1u32, n_navigate)
    js.add_method(it, n, "runScript", 2u32, n_run_script)
}

// A realm bound to `d`. `base` is the document's URL (location.href).
fn new_context(a: *mem.Arena, d: *dom.Dom, base: str) -> (*js.Interp, err) {
    let (it0, e0) = new_context_in(a, d, base, js.null_interp())
    ret (it0, e0)
}

// As `new_context`, for a frame: the realm shares the well-known symbols of `donor`, the embedder's realm.
fn new_context_in(a: *mem.Arena, d: *dom.Dom, base: str, donor: *js.Interp) -> (*js.Interp, err) {
    let (it, rne) = realm.new_realm_with(a, donor)
    if rne != ok { ret (it, rne) }
    let (cell, ce) = mem.alloc[Host](a, 1usize)
    if ce != ok { ret (it, ce) }
    var blank: Host = zero
    cell[0usize] = blank
    cell[0usize].d = d
    cell[0usize].base = base
    let (l, le) = list.init[str](a, 64usize)
    if le != ok { ret (it, le) }
    cell[0usize].log = l
    let (kids, ke) = list.init[*js.Interp](a, 4usize)
    cell[0usize].children = kids
    let mie = module.install(it, load_module_hook)
    // Scripts get no collector: past 80% of the arena a call throws a RangeError instead of exhausting memory the page still needs.
    it.mem_limit = a.cap - a.cap / 5usize
    it.host = mem.cast[*void](&cell[0usize])
    install_natives(it)
    // The page runtime is parsed once and shared by every frame's context.
    if donor != js.null_interp() && host_of(donor).has_dom_prog {
        cell[0usize].dom_prog = host_of(donor).dom_prog
        cell[0usize].has_dom_prog = true
    } else {
        let (src, se) = dom_js.source(a)
        if se != ok { ret (it, se) }
        let (pp, ppe) = js.parse_shared(it, src)
        if ppe != ok { ret (it, ppe) }
        cell[0usize].dom_prog = pp
        cell[0usize].has_dom_prog = true
    }
    it.step_limit = 300000000u64
    let (v, e) = js.run_shared(it, cell[0usize].dom_prog)
    it.step_limit = 0u64
    it.steps = 0u64
    if e != ok { ret (it, e) }
    ret (it, ok)
}

// Gives the page's network to scripts (script loading, XMLHttpRequest, fetch).
fn set_fetch(it: *js.Interp, ctx: *void, f: FetchFn) {
    let h = host_of(it)
    h.fetch_ctx = ctx
    h.fetch_fn = f
    h.has_fetch = true
}

// Gives scripts the page's network (XMLHttpRequest, fetch).
fn set_net(it: *js.Interp, ctx: *void, f: NetFn) {
    let h = host_of(it)
    h.net_ctx = ctx
    h.net_fn = f
    h.has_net = true
}

// Gives scripts the page's layout and style (getBoundingClientRect, getComputedStyle, offset and client sizes).
fn set_view(it: *js.Interp, ctx: *void, g: GeomFn, st: StyleFn) {
    let h = host_of(it)
    h.view_ctx = ctx
    h.geom_fn = g
    h.style_fn = st
    h.has_view = true
}

// The pending navigation requested by `location` assignments: (address, requested).
fn take_navigation(it: *js.Interp) -> (str, bool) {
    let h = host_of(it)
    if !h.has_nav { ret ("", false) }
    h.has_nav = false
    ret (h.nav, true)
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
    it.script_url = name
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
    var best = -1.0f64
    var ci = 0usize
    let hh = host_of(it)
    while ci < hh.children.len {
        let c = hh.children.items[ci]
        host_of(c).now = hh.now
        let cn = pump_once(c)
        if cn >= 0.0f64 && (best < 0.0f64 || cn < best) { best = cn }
        ci += 1usize
    }
    let own = pump_self(it)
    if own >= 0.0f64 && (best < 0.0f64 || own < best) { best = own }
    ret best
}

fn pump_self(it: *js.Interp) -> f64 {
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

// Moves the clock to `ms` (never back).
fn set_clock(it: *js.Interp, ms: f64) {
    let h = host_of(it)
    if ms > h.now { h.now = ms }
}

// The clock time of the next pending timer, or -1.
fn next_due(it: *js.Interp) -> f64 {
    var best = -1.0f64
    let hh = host_of(it)
    var ci = 0usize
    while ci < hh.children.len {
        let cn = next_due(hh.children.items[ci])
        if cn >= 0.0f64 && (best < 0.0f64 || cn < best) { best = cn }
        ci += 1usize
    }
    let (nd, ne) = js.get_prop(it, it.global, js.key_of("__nextTimer"), js.obj_value(it.global))
    if ne != ok || !js.is_callable(nd) { ret best }
    let (v, ve) = js.call_function(it, nd, js.obj_value(it.global), js.zero_args())
    if ve != ok { ret best }
    switch v {
    case .Num as n:
        if n >= 0.0f64 && (best < 0.0f64 || n < best) { best = n }
    default:
        best = best
    }
    ret best
}

// Delivers a mouse event of `kind` at (x, y) to node `node`; false when a handler cancelled it.
fn dispatch_mouse(it: *js.Interp, node: u32, kind: str, x: f64, y: f64) -> bool {
    let (lc, le) = js.get_prop(it, it.global, js.key_of("__lifecycle"), js.obj_value(it.global))
    if le != ok || !js.is_object(lc) { ret true }
    let (f, fe) = js.get_prop(it, js.as_object(lc), js.key_of("mouse"), lc)
    if fe != ok || !js.is_callable(f) { ret true }
    let (cell, ce) = mem.alloc[js.Value](it.a, 4usize)
    if ce != ok { ret true }
    cell[0usize] = js.num_value(f64(node))
    cell[1usize] = js.str_value(kind)
    cell[2usize] = js.num_value(x)
    cell[3usize] = js.num_value(y)
    let (r, re) = js.call_function(it, f, lc, cell[0usize..4usize])
    if re != ok {
        report_thrown(it, "mouse")
        ret true
    }
    let go = js.to_boolean(r)
    let jr = js.run_jobs(it)
    ret go
}
