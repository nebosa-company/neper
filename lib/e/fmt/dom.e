// A mutable DOM over the `e.fmt.html` node table: the tree operations a script or an editor
// needs, without events, scripts or a window. A `Dom` owns a node array with spare capacity in
// an arena; every node is an index, so a node keeps its id across moves and the table can be
// handed to the selector matcher (`view`) and the HTML serializer unchanged.
//
//   * creation: `from_document` (copies a parsed document and reserves `spare` more nodes),
//     `parse`, `new_document`, `create_element`, `create_text`, `create_comment`, `create_fragment`;
//   * tree: `append_child`, `insert_before`, `remove_child`, `replace_child`, `remove`,
//     `clone_node`, `import_node`, `normalize`, with the pre-insert checks (a parent is a
//     document, fragment or element, no cycles, a doctype only under a document, the reference
//     child is a child); inserting a fragment moves its children;
//   * text and markup: `text_content`, `set_text_content`, `inner_html`, `outer_html`,
//     `set_inner_html`;
//   * attributes: `get_attribute`, `set_attribute`, `remove_attribute` (names are matched
//     ASCII case-insensitively on HTML elements), the `class` token list (`class_contains`,
//     `class_add`, `class_remove`, `class_toggle`) and `dataset_get`, `dataset_set`, `dataset_remove`;
//   * queries: `get_element_by_id`, `elements_by_tag`, `elements_by_class`, the live `Collection`
//     (`collection_len`, `collection_item`: recomputed on each call, so it is always current),
//     `query_selector`, `query_selector_all`, `matches`, `closest`, and tree order walks
//     (`next_in_tree`, `previous_in_tree`, the element sibling and child helpers);
//   * `Walker`: the DOM TreeWalker for a `what_to_show` mask.
//
// `version` counts mutations, so a style or layout cache can tell that the tree changed.
//
// ponytail: removed and replaced nodes keep their slots (the arena is released as a whole), so a
// long-lived tree that churns needs `spare` sized for the churn or a rebuild from `view`; the
// document's single-element and single-doctype rules are not enforced; a `Walker` has no
// callback filter, only the mask.

use e.fmt.css.match as cssm
use e.fmt.css.selector as selector
use e.fmt.css.syntax as syntax
use e.fmt.html as html
use e.io
use e.mem
use e.str

type NodeId = html.NodeId
const NONE: NodeId = 4294967295u32

error HierarchyRequest
error NotChild
error Full
error SyntaxError

type Dom = struct { a: *mem.Arena, nodes: []html.Node, used: usize, root: NodeId, quirks: u8, version: u64 }

// --- Construction.

fn from_document(a: *mem.Arena, doc: *const html.Document, spare: usize) -> (Dom, err) {
    let table = try mem.alloc[html.Node](a, doc.nodes.len + spare)
    mem.copy[html.Node](table[..doc.nodes.len], doc.nodes)
    ret (Dom { a: a, nodes: table, used: doc.nodes.len, root: doc.root, quirks: doc.quirks, version: 0u64 }, ok)
}

fn parse(a: *mem.Arena, source: str, options: html.Options, spare: usize) -> (Dom, err) {
    let (doc, parse_error) = html.parse(a, source, options)
    if parse_error != ok { ret (zero, parse_error) }
    let (made, made_error) = from_document(a, &doc, spare)
    ret (made, made_error)
}

// As `parse`, with scripting on or off (with it on, `<noscript>` content is raw text, as in a browser that runs scripts).
fn parse_with(a: *mem.Arena, source: str, options: html.Options, spare: usize, scripting: bool) -> (Dom, err) {
    let (doc, parse_error) = html.parse_with(a, source, options, scripting)
    if parse_error != ok { ret (zero, parse_error) }
    let (made, made_error) = from_document(a, &doc, spare)
    ret (made, made_error)
}

fn new_document(a: *mem.Arena, capacity: usize) -> (Dom, err) {
    let table = try mem.alloc[html.Node](a, capacity + 1usize)
    var d = Dom { a: a, nodes: table, used: 0usize, root: 0u32, quirks: 0u8, version: 0u64 }
    let root = try new_node(&d, .Document, .Html, "", "")
    d.root = root
    ret (d, ok)
}

// The table as an `e.fmt.html` document, for the matcher, the serializer and `e.fmt.css`.
fn view(d: *const Dom) -> html.Document {
    ret html.Document { nodes: d.nodes[..d.used], root: d.root, quirks: d.quirks }
}

fn new_node(d: *Dom, kind: html.NodeKind, ns: html.Namespace, name: str, value: str) -> (NodeId, err) {
    if d.used >= d.nodes.len { ret (NONE, Full) }
    let id = u32(d.used)
    d.nodes[d.used] = html.Node { kind: kind, namespace: ns, name: name, value: value, attributes: zero, parent: NONE, first_child: NONE, last_child: NONE, previous_sibling: NONE, next_sibling: NONE }
    d.used += 1usize
    d.version += 1u64
    ret (id, ok)
}

fn create_element_ns(d: *Dom, ns: html.Namespace, name: str) -> (NodeId, err) {
    let (id, e) = new_node(d, .Element, ns, name, "")
    ret (id, e)
}

// An HTML element; the name is lower-cased.
fn create_element(d: *Dom, name: str) -> (NodeId, err) {
    let lowered = try lower_copy(d.a, name)
    let (id, e) = new_node(d, .Element, .Html, lowered, "")
    ret (id, e)
}

fn create_text(d: *Dom, data: str) -> (NodeId, err) {
    let (id, e) = new_node(d, .Text, .Html, "", data)
    ret (id, e)
}

fn create_comment(d: *Dom, data: str) -> (NodeId, err) {
    let (id, e) = new_node(d, .Comment, .Html, "", data)
    ret (id, e)
}

// A detached document fragment: a `Document` node other than the root.
fn create_fragment(d: *Dom) -> (NodeId, err) {
    let (id, e) = new_node(d, .Document, .Html, "", "")
    ret (id, e)
}

fn lower_copy(a: *mem.Arena, s: str) -> (str, err) {
    var upper = false
    var i = 0usize
    while i < s.len {
        if s[i] >= 65u8 && s[i] <= 90u8 { upper = true }
        i += 1usize
    }
    if !upper { ret (s, ok) }
    let out = try mem.alloc[u8](a, s.len)
    mem.copy[u8](out, s)
    str.ascii_lower_in_place(out)
    ret (out, ok)
}

// --- Reading the tree.

fn kind_of(d: *const Dom, id: NodeId) -> html.NodeKind { ret d.nodes[usize(id)].kind }
fn name_of(d: *const Dom, id: NodeId) -> str { ret d.nodes[usize(id)].name }
fn value_of(d: *const Dom, id: NodeId) -> str { ret d.nodes[usize(id)].value }
fn parent_of(d: *const Dom, id: NodeId) -> NodeId { ret d.nodes[usize(id)].parent }
fn first_child(d: *const Dom, id: NodeId) -> NodeId { ret d.nodes[usize(id)].first_child }
fn last_child(d: *const Dom, id: NodeId) -> NodeId { ret d.nodes[usize(id)].last_child }
fn next_sibling(d: *const Dom, id: NodeId) -> NodeId { ret d.nodes[usize(id)].next_sibling }
fn previous_sibling(d: *const Dom, id: NodeId) -> NodeId { ret d.nodes[usize(id)].previous_sibling }

fn is_element(d: *const Dom, id: NodeId) -> bool { ret d.nodes[usize(id)].kind == .Element }

fn is_html_named(d: *const Dom, id: NodeId, name: str) -> bool {
    ret d.nodes[usize(id)].kind == .Element && d.nodes[usize(id)].namespace == .Html && str.eq(d.nodes[usize(id)].name, name)
}

fn first_element_child(d: *const Dom, id: NodeId) -> NodeId {
    var kid = d.nodes[usize(id)].first_child
    while kid != NONE && d.nodes[usize(kid)].kind != .Element { kid = d.nodes[usize(kid)].next_sibling }
    ret kid
}

fn last_element_child(d: *const Dom, id: NodeId) -> NodeId {
    var kid = d.nodes[usize(id)].last_child
    while kid != NONE && d.nodes[usize(kid)].kind != .Element { kid = d.nodes[usize(kid)].previous_sibling }
    ret kid
}

fn next_element_sibling(d: *const Dom, id: NodeId) -> NodeId {
    var sib = d.nodes[usize(id)].next_sibling
    while sib != NONE && d.nodes[usize(sib)].kind != .Element { sib = d.nodes[usize(sib)].next_sibling }
    ret sib
}

fn previous_element_sibling(d: *const Dom, id: NodeId) -> NodeId {
    var sib = d.nodes[usize(id)].previous_sibling
    while sib != NONE && d.nodes[usize(sib)].kind != .Element { sib = d.nodes[usize(sib)].previous_sibling }
    ret sib
}

fn child_count(d: *const Dom, id: NodeId) -> usize {
    var count = 0usize
    var kid = d.nodes[usize(id)].first_child
    while kid != NONE {
        count += 1usize
        kid = d.nodes[usize(kid)].next_sibling
    }
    ret count
}

fn child_index(d: *const Dom, id: NodeId) -> usize {
    var count = 0usize
    var sib = d.nodes[usize(id)].previous_sibling
    while sib != NONE {
        count += 1usize
        sib = d.nodes[usize(sib)].previous_sibling
    }
    ret count
}

// `ancestor` is `id` or one of its ancestors.
fn contains(d: *const Dom, ancestor: NodeId, id: NodeId) -> bool {
    var cur = id
    while cur != NONE {
        if cur == ancestor { ret true }
        cur = d.nodes[usize(cur)].parent
    }
    ret false
}

fn root_of(d: *const Dom, id: NodeId) -> NodeId {
    var cur = id
    while d.nodes[usize(cur)].parent != NONE { cur = d.nodes[usize(cur)].parent }
    ret cur
}

fn is_connected(d: *const Dom, id: NodeId) -> bool { ret root_of(d, id) == d.root }

// The node after `id` in tree order inside `root` (NONE at the end).
fn next_in_tree(d: *const Dom, root: NodeId, id: NodeId) -> NodeId {
    let first = d.nodes[usize(id)].first_child
    if first != NONE { ret first }
    var cur = id
    while cur != root && cur != NONE {
        let sib = d.nodes[usize(cur)].next_sibling
        if sib != NONE { ret sib }
        cur = d.nodes[usize(cur)].parent
    }
    ret NONE
}

// The node before `id` in tree order inside `root` (NONE before `root`).
fn previous_in_tree(d: *const Dom, root: NodeId, id: NodeId) -> NodeId {
    if id == root { ret NONE }
    let sib = d.nodes[usize(id)].previous_sibling
    if sib == NONE { ret d.nodes[usize(id)].parent }
    var cur = sib
    while d.nodes[usize(cur)].last_child != NONE { cur = d.nodes[usize(cur)].last_child }
    ret cur
}

// --- Mutation.

fn unlink(d: *Dom, id: NodeId) {
    let parent = d.nodes[usize(id)].parent
    if parent == NONE { ret }
    let prev = d.nodes[usize(id)].previous_sibling
    let next = d.nodes[usize(id)].next_sibling
    if prev == NONE { d.nodes[usize(parent)].first_child = next } else { d.nodes[usize(prev)].next_sibling = next }
    if next == NONE { d.nodes[usize(parent)].last_child = prev } else { d.nodes[usize(next)].previous_sibling = prev }
    d.nodes[usize(id)].parent = NONE
    d.nodes[usize(id)].previous_sibling = NONE
    d.nodes[usize(id)].next_sibling = NONE
}

fn link(d: *Dom, parent: NodeId, id: NodeId, before: NodeId) {
    d.nodes[usize(id)].parent = parent
    if before == NONE {
        let last = d.nodes[usize(parent)].last_child
        d.nodes[usize(id)].previous_sibling = last
        d.nodes[usize(id)].next_sibling = NONE
        if last == NONE { d.nodes[usize(parent)].first_child = id } else { d.nodes[usize(last)].next_sibling = id }
        d.nodes[usize(parent)].last_child = id
        ret
    }
    let prev = d.nodes[usize(before)].previous_sibling
    d.nodes[usize(id)].previous_sibling = prev
    d.nodes[usize(id)].next_sibling = before
    d.nodes[usize(before)].previous_sibling = id
    if prev == NONE { d.nodes[usize(parent)].first_child = id } else { d.nodes[usize(prev)].next_sibling = id }
}

fn is_fragment(d: *const Dom, id: NodeId) -> bool {
    ret d.nodes[usize(id)].kind == .Document && id != d.root
}

fn check_insert(d: *const Dom, parent: NodeId, child: NodeId, before: NodeId) -> err {
    let pk = d.nodes[usize(parent)].kind
    if pk != .Document && pk != .Element { ret HierarchyRequest }
    if contains(d, child, parent) { ret HierarchyRequest }
    if before != NONE && d.nodes[usize(before)].parent != parent { ret NotChild }
    let ck = d.nodes[usize(child)].kind
    if ck == .Doctype && !(pk == .Document) { ret HierarchyRequest }
    if ck == .Text && parent == d.root { ret HierarchyRequest }
    if ck == .Document && child == d.root { ret HierarchyRequest }
    ret ok
}

// Inserts `child` (a node, or a fragment whose children move) under `parent` before `before`
// (NONE: last). A node already in the tree is moved.
fn insert_before(d: *Dom, parent: NodeId, child: NodeId, before: NodeId) -> err {
    try check_insert(d, parent, child, before)
    if child == before {
        d.version += 1u64
        ret ok
    }
    if is_fragment(d, child) {
        // The fragment's children, in order, before the reference.
        while d.nodes[usize(child)].first_child != NONE {
            let kid = d.nodes[usize(child)].first_child
            unlink(d, kid)
            link(d, parent, kid, before)
        }
        d.version += 1u64
        ret ok
    }
    unlink(d, child)
    link(d, parent, child, before)
    d.version += 1u64
    ret ok
}

fn append_child(d: *Dom, parent: NodeId, child: NodeId) -> err {
    ret insert_before(d, parent, child, NONE)
}

fn remove_child(d: *Dom, parent: NodeId, child: NodeId) -> err {
    if d.nodes[usize(child)].parent != parent { ret NotChild }
    unlink(d, child)
    d.version += 1u64
    ret ok
}

// Removes `id` from its parent, if it has one.
fn remove(d: *Dom, id: NodeId) {
    if d.nodes[usize(id)].parent == NONE { ret }
    unlink(d, id)
    d.version += 1u64
}

fn replace_child(d: *Dom, parent: NodeId, new_child: NodeId, old_child: NodeId) -> err {
    if d.nodes[usize(old_child)].parent != parent { ret NotChild }
    if new_child == old_child { ret ok }
    let after = d.nodes[usize(old_child)].next_sibling
    var anchor = after
    if anchor == new_child { anchor = d.nodes[usize(new_child)].next_sibling }
    try check_insert(d, parent, new_child, anchor)
    unlink(d, old_child)
    try insert_before(d, parent, new_child, anchor)
    ret ok
}

fn remove_children(d: *Dom, id: NodeId) {
    while d.nodes[usize(id)].first_child != NONE { unlink(d, d.nodes[usize(id)].first_child) }
    d.version += 1u64
}

fn clone_node(d: *Dom, id: NodeId, deep: bool) -> (NodeId, err) {
    let copy = try new_node(d, d.nodes[usize(id)].kind, d.nodes[usize(id)].namespace, d.nodes[usize(id)].name, d.nodes[usize(id)].value)
    d.nodes[usize(copy)].attributes = d.nodes[usize(id)].attributes
    if deep {
        var kid = d.nodes[usize(id)].first_child
        while kid != NONE {
            let inner = try clone_node(d, kid, true)
            link(d, copy, inner, NONE)
            kid = d.nodes[usize(kid)].next_sibling
        }
    }
    ret (copy, ok)
}

// A deep copy of node `id` of another document into this one.
fn import_node(d: *Dom, from: *const html.Document, id: NodeId) -> (NodeId, err) {
    let n = &from.nodes[usize(id)]
    let copy = try new_node(d, n.kind, n.namespace, n.name, n.value)
    d.nodes[usize(copy)].attributes = n.attributes
    var kid = n.first_child
    while kid != NONE {
        let inner = try import_node(d, from, kid)
        link(d, copy, inner, NONE)
        kid = from.nodes[usize(kid)].next_sibling
    }
    ret (copy, ok)
}

// Merges adjacent text nodes under `id` (and below) and drops empty ones.
fn normalize(d: *Dom, id: NodeId) -> err {
    var kid = d.nodes[usize(id)].first_child
    while kid != NONE {
        let next = d.nodes[usize(kid)].next_sibling
        if d.nodes[usize(kid)].kind == .Text {
            if d.nodes[usize(kid)].value.len == 0usize {
                unlink(d, kid)
                d.version += 1u64
            } else {
                var merged = d.nodes[usize(kid)].value
                var follow = next
                var absorbed = false
                while follow != NONE && d.nodes[usize(follow)].kind == .Text {
                    merged = try str.concat(d.a, merged, d.nodes[usize(follow)].value)
                    let after_follow = d.nodes[usize(follow)].next_sibling
                    unlink(d, follow)
                    follow = after_follow
                    absorbed = true
                }
                if absorbed {
                    d.nodes[usize(kid)].value = merged
                    d.version += 1u64
                }
                kid = follow
                continue
            }
        } else {
            try normalize(d, kid)
        }
        kid = next
    }
    ret ok
}

// --- Text and markup.

fn text_content(a: *mem.Arena, d: *const Dom, id: NodeId) -> (str, err) {
    let k = d.nodes[usize(id)].kind
    if k == .Text || k == .Comment || k == .Doctype { ret (d.nodes[usize(id)].value, ok) }
    let doc = view(d)
    let (out, e) = html.text_content(a, &doc, id)
    ret (out, e)
}

fn set_text_content(d: *Dom, id: NodeId, data: str) -> err {
    let k = d.nodes[usize(id)].kind
    if k == .Text || k == .Comment {
        d.nodes[usize(id)].value = data
        d.version += 1u64
        ret ok
    }
    if k == .Doctype { ret ok }
    remove_children(d, id)
    if data.len > 0usize {
        let text = try create_text(d, data)
        link(d, id, text, NONE)
    }
    ret ok
}

fn builder_write(ctx: *void, src: []const u8) -> (usize, err) {
    var b = mem.cast[*str.Builder](ctx)
    try str.push(b, src)
    ret (src.len, ok)
}

fn outer_html(a: *mem.Arena, d: *const Dom, id: NodeId) -> (str, err) {
    var b = try str.builder(a, 256usize)
    var w = io.writer(mem.cast[*void](&b), builder_write)
    let doc = view(d)
    try html.write_node(&w, &doc, id)
    ret (str.done(&b), ok)
}

fn inner_html(a: *mem.Arena, d: *const Dom, id: NodeId) -> (str, err) {
    var b = try str.builder(a, 256usize)
    var w = io.writer(mem.cast[*void](&b), builder_write)
    let doc = view(d)
    var kid = d.nodes[usize(id)].first_child
    while kid != NONE {
        try html.write_node(&w, &doc, kid)
        kid = d.nodes[usize(kid)].next_sibling
    }
    ret (str.done(&b), ok)
}

// Replaces the children of element `id` with the parse of `markup` in its context.
fn set_inner_html(d: *Dom, id: NodeId, markup: str, options: html.Options) -> err {
    let (frag, frag_error) = html.parse_fragment(d.a, markup, d.nodes[usize(id)].name, d.nodes[usize(id)].namespace, options)
    if frag_error != ok { ret frag_error }
    remove_children(d, id)
    var kid = frag.nodes[usize(frag.root)].first_child
    while kid != NONE {
        let copy = try import_node(d, &frag, kid)
        link(d, id, copy, NONE)
        kid = frag.nodes[usize(kid)].next_sibling
    }
    ret ok
}

// --- Attributes.

fn find_attr(d: *const Dom, id: NodeId, name: str) -> (usize, bool) {
    let n = &d.nodes[usize(id)]
    var fold = n.namespace == .Html
    var i = 0usize
    while i < n.attributes.len {
        if fold {
            if str.compare_ascii_fold(n.attributes[i].name, name) == 0i32 { ret (i, true) }
        } else {
            if str.eq(n.attributes[i].name, name) { ret (i, true) }
        }
        i += 1usize
    }
    ret (0usize, false)
}

fn get_attribute(d: *const Dom, id: NodeId, name: str) -> (str, bool) {
    let (at, found) = find_attr(d, id, name)
    if !found { ret ("", false) }
    ret (d.nodes[usize(id)].attributes[at].value, true)
}

fn has_attribute(d: *const Dom, id: NodeId, name: str) -> bool {
    let (_, found) = find_attr(d, id, name)
    ret found
}

fn attribute_count(d: *const Dom, id: NodeId) -> usize { ret d.nodes[usize(id)].attributes.len }

fn set_attribute(d: *Dom, id: NodeId, name: str, value: str) -> err {
    let old = d.nodes[usize(id)].attributes
    let (at, found) = find_attr(d, id, name)
    if found {
        let copy = try mem.alloc[html.Attribute](d.a, old.len)
        mem.copy[html.Attribute](copy, old)
        copy[at] = html.Attribute { namespace: old[at].namespace, name: old[at].name, value: value }
        d.nodes[usize(id)].attributes = copy
        d.version += 1u64
        ret ok
    }
    var stored = name
    if d.nodes[usize(id)].namespace == .Html { stored = try lower_copy(d.a, name) }
    let grown = try mem.alloc[html.Attribute](d.a, old.len + 1usize)
    mem.copy[html.Attribute](grown[..old.len], old)
    grown[old.len] = html.Attribute { namespace: .Html, name: stored, value: value }
    d.nodes[usize(id)].attributes = grown
    d.version += 1u64
    ret ok
}

fn remove_attribute(d: *Dom, id: NodeId, name: str) -> err {
    let old = d.nodes[usize(id)].attributes
    let (at, found) = find_attr(d, id, name)
    if !found { ret ok }
    let shrunk = try mem.alloc[html.Attribute](d.a, old.len - 1usize)
    mem.copy[html.Attribute](shrunk[..at], old[..at])
    mem.copy[html.Attribute](shrunk[at..], old[at + 1usize..])
    d.nodes[usize(id)].attributes = shrunk
    d.version += 1u64
    ret ok
}

// --- The class token list.

fn is_class_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 12u8 || c == 13u8 }

fn class_contains(d: *const Dom, id: NodeId, token: str) -> bool {
    let (value, found) = get_attribute(d, id, "class")
    if !found || token.len == 0usize { ret false }
    var i = 0usize
    while i < value.len {
        while i < value.len && is_class_space(value[i]) { i += 1usize }
        let start = i
        while i < value.len && !is_class_space(value[i]) { i += 1usize }
        if i > start && str.eq(value[start..i], token) { ret true }
    }
    ret false
}

fn class_add(d: *Dom, id: NodeId, token: str) -> err {
    if token.len == 0usize || class_contains(d, id, token) { ret ok }
    let (value, found) = get_attribute(d, id, "class")
    if !found || str.trim(value).len == 0usize { ret set_attribute(d, id, "class", token) }
    let joined = try str.concat(d.a, str.trim_end(value), " ")
    let grown = try str.concat(d.a, joined, token)
    ret set_attribute(d, id, "class", grown)
}

fn class_remove(d: *Dom, id: NodeId, token: str) -> err {
    if !class_contains(d, id, token) { ret ok }
    let (value, _) = get_attribute(d, id, "class")
    var b = try str.builder(d.a, value.len + 1usize)
    var first = true
    var i = 0usize
    while i < value.len {
        while i < value.len && is_class_space(value[i]) { i += 1usize }
        let start = i
        while i < value.len && !is_class_space(value[i]) { i += 1usize }
        if i > start && !str.eq(value[start..i], token) {
            if !first { try str.push(&b, " ") }
            try str.push(&b, value[start..i])
            first = false
        }
    }
    let rebuilt = str.done(&b)
    ret set_attribute(d, id, "class", rebuilt)
}

// Adds the token if absent, removes it if present; true when it is present afterwards.
fn class_toggle(d: *Dom, id: NodeId, token: str) -> (bool, err) {
    if class_contains(d, id, token) {
        let e = class_remove(d, id, token)
        ret (false, e)
    }
    let e = class_add(d, id, token)
    ret (true, e)
}

// --- dataset: `fooBar` is the attribute `data-foo-bar`.

fn dataset_name(a: *mem.Arena, key: str) -> (str, err) {
    var b = try str.builder(a, key.len * 2usize + 6usize)
    try str.push(&b, "data-")
    var i = 0usize
    while i < key.len {
        let c = key[i]
        if c >= 65u8 && c <= 90u8 {
            try str.push(&b, "-")
            try str.push_byte(&b, c + 32u8)
        } else {
            try str.push_byte(&b, c)
        }
        i += 1usize
    }
    ret (str.done(&b), ok)
}

fn dataset_get(a: *mem.Arena, d: *const Dom, id: NodeId, key: str) -> (str, bool, err) {
    let (name, e) = dataset_name(a, key)
    if e != ok { ret ("", false, e) }
    let (value, found) = get_attribute(d, id, name)
    ret (value, found, ok)
}

fn dataset_set(d: *Dom, id: NodeId, key: str, value: str) -> err {
    let name = try dataset_name(d.a, key)
    ret set_attribute(d, id, name, value)
}

fn dataset_remove(d: *Dom, id: NodeId, key: str) -> err {
    let name = try dataset_name(d.a, key)
    ret remove_attribute(d, id, name)
}

// --- Queries.

fn get_element_by_id(d: *const Dom, root: NodeId, wanted: str) -> NodeId {
    var cur = next_in_tree(d, root, root)
    while cur != NONE {
        if d.nodes[usize(cur)].kind == .Element {
            let (value, found) = get_attribute(d, cur, "id")
            if found && str.eq(value, wanted) { ret cur }
        }
        cur = next_in_tree(d, root, cur)
    }
    ret NONE
}

fn tag_matches(d: *const Dom, id: NodeId, name: str) -> bool {
    if d.nodes[usize(id)].kind != .Element { ret false }
    if str.eq(name, "*") { ret true }
    if d.nodes[usize(id)].namespace == .Html { ret str.compare_ascii_fold(d.nodes[usize(id)].name, name) == 0i32 }
    ret str.eq(d.nodes[usize(id)].name, name)
}

// Every class token of `classes` (space separated) is on the element.
fn classes_match(d: *const Dom, id: NodeId, classes: str) -> bool {
    if d.nodes[usize(id)].kind != .Element { ret false }
    var any = false
    var i = 0usize
    while i < classes.len {
        while i < classes.len && is_class_space(classes[i]) { i += 1usize }
        let start = i
        while i < classes.len && !is_class_space(classes[i]) { i += 1usize }
        if i > start {
            any = true
            if !class_contains(d, id, classes[start..i]) { ret false }
        }
    }
    ret any
}

fn elements_by_tag(d: *const Dom, root: NodeId, name: str, out: []NodeId) -> usize {
    var count = 0usize
    var cur = next_in_tree(d, root, root)
    while cur != NONE && count < out.len {
        if tag_matches(d, cur, name) {
            out[count] = cur
            count += 1usize
        }
        cur = next_in_tree(d, root, cur)
    }
    ret count
}

fn elements_by_class(d: *const Dom, root: NodeId, classes: str, out: []NodeId) -> usize {
    var count = 0usize
    var cur = next_in_tree(d, root, root)
    while cur != NONE && count < out.len {
        if classes_match(d, cur, classes) {
            out[count] = cur
            count += 1usize
        }
        cur = next_in_tree(d, root, cur)
    }
    ret count
}

// A live collection: `CollectionTag` (getElementsByTagName), `CollectionClass`
// (getElementsByClassName), `CollectionChildren` (element children). It holds no results, so
// every call sees the tree as it is.
const CollectionTag: u8 = 0u8
const CollectionClass: u8 = 1u8
const CollectionChildren: u8 = 2u8

type Collection = struct { kind: u8, root: NodeId, key: str }

fn collection_next(d: *const Dom, c: Collection, after: NodeId) -> NodeId {
    if c.kind == CollectionChildren {
        if after == NONE { ret first_element_child(d, c.root) }
        ret next_element_sibling(d, after)
    }
    var cur = after
    if cur == NONE { cur = c.root }
    cur = next_in_tree(d, c.root, cur)
    while cur != NONE {
        if c.kind == CollectionTag && tag_matches(d, cur, c.key) { ret cur }
        if c.kind == CollectionClass && classes_match(d, cur, c.key) { ret cur }
        cur = next_in_tree(d, c.root, cur)
    }
    ret NONE
}

fn collection_len(d: *const Dom, c: Collection) -> usize {
    var count = 0usize
    var cur = collection_next(d, c, NONE)
    while cur != NONE {
        count += 1usize
        cur = collection_next(d, c, cur)
    }
    ret count
}

fn collection_item(d: *const Dom, c: Collection, index: usize) -> NodeId {
    var cur = collection_next(d, c, NONE)
    var at = 0usize
    while cur != NONE && at < index {
        cur = collection_next(d, c, cur)
        at += 1usize
    }
    ret cur
}

// --- Selectors.

fn compile_selectors(a: *mem.Arena, text: str) -> ([]const selector.RuleSelector, err) {
    let (tokens, token_error) = syntax.tokenize(a, text)
    if token_error != ok { ret (zero, SyntaxError) }
    let (chosen, chosen_error) = selector.parse_selector_list_for_rule(a, text, tokens)
    if chosen_error != ok || chosen.len == 0usize { ret (zero, SyntaxError) }
    ret (chosen, ok)
}

fn any_selector(m: *const cssm.Matcher, chosen: []const selector.RuleSelector, el: NodeId) -> bool {
    var i = 0usize
    while i < chosen.len {
        if !chosen[i].has_pseudo && cssm.selector_matches(m, chosen[i].selector, el) { ret true }
        i += 1usize
    }
    ret false
}

fn scoped_matcher(a: *mem.Arena, doc: *const html.Document, scope: NodeId) -> cssm.Matcher {
    var st = cssm.no_state()
    st.has_scope = true
    st.scope = scope
    ret cssm.new_matcher(a, doc, st)
}

// The first element under `root` that matches `text`; `a` is scratch space.
fn query_selector(a: *mem.Arena, d: *const Dom, root: NodeId, text: str) -> (NodeId, err) {
    let chosen = try compile_selectors(a, text)
    let doc = view(d)
    let m = scoped_matcher(a, &doc, root)
    var cur = next_in_tree(d, root, root)
    while cur != NONE {
        if d.nodes[usize(cur)].kind == .Element && any_selector(&m, chosen, cur) { ret (cur, ok) }
        cur = next_in_tree(d, root, cur)
    }
    ret (NONE, ok)
}

fn query_selector_all(a: *mem.Arena, d: *const Dom, root: NodeId, text: str, out: []NodeId) -> (usize, err) {
    let chosen = try compile_selectors(a, text)
    let doc = view(d)
    let m = scoped_matcher(a, &doc, root)
    var count = 0usize
    var cur = next_in_tree(d, root, root)
    while cur != NONE && count < out.len {
        if d.nodes[usize(cur)].kind == .Element && any_selector(&m, chosen, cur) {
            out[count] = cur
            count += 1usize
        }
        cur = next_in_tree(d, root, cur)
    }
    ret (count, ok)
}

fn matches(a: *mem.Arena, d: *const Dom, id: NodeId, text: str) -> (bool, err) {
    let chosen = try compile_selectors(a, text)
    let doc = view(d)
    let m = scoped_matcher(a, &doc, id)
    ret (any_selector(&m, chosen, id), ok)
}

// The nearest inclusive ancestor of `id` that matches `text`.
fn closest(a: *mem.Arena, d: *const Dom, id: NodeId, text: str) -> (NodeId, err) {
    let chosen = try compile_selectors(a, text)
    let doc = view(d)
    let m = scoped_matcher(a, &doc, id)
    var cur = id
    while cur != NONE {
        if d.nodes[usize(cur)].kind == .Element && any_selector(&m, chosen, cur) { ret (cur, ok) }
        cur = d.nodes[usize(cur)].parent
    }
    ret (NONE, ok)
}

// --- The TreeWalker.

const ShowAll: u32 = 4294967295u32
const ShowElement: u32 = 1u32
const ShowText: u32 = 4u32
const ShowComment: u32 = 128u32
const ShowDocument: u32 = 256u32
const ShowDoctype: u32 = 512u32

type Walker = struct { root: NodeId, current: NodeId, mask: u32 }

fn walker(root: NodeId, mask: u32) -> Walker {
    ret Walker { root: root, current: root, mask: mask }
}

fn shown(d: *const Dom, w: *const Walker, id: NodeId) -> bool {
    var bit = 0u32
    let k = d.nodes[usize(id)].kind
    if k == .Element { bit = ShowElement }
    if k == .Text { bit = ShowText }
    if k == .Comment { bit = ShowComment }
    if k == .Document { bit = ShowDocument }
    if k == .Doctype { bit = ShowDoctype }
    ret (w.mask & bit) != 0u32
}

fn walker_parent(d: *const Dom, w: *Walker) -> NodeId {
    var cur = w.current
    while cur != w.root && cur != NONE {
        cur = d.nodes[usize(cur)].parent
        if cur != NONE && shown(d, w, cur) {
            w.current = cur
            ret cur
        }
    }
    ret NONE
}

// firstChild / lastChild: the first (last) shown descendant reached through hidden nodes.
fn walker_child(d: *const Dom, w: *Walker, from_end: bool) -> NodeId {
    var cur = d.nodes[usize(w.current)].first_child
    if from_end { cur = d.nodes[usize(w.current)].last_child }
    while cur != NONE {
        if shown(d, w, cur) {
            w.current = cur
            ret cur
        }
        var inner = d.nodes[usize(cur)].first_child
        if from_end { inner = d.nodes[usize(cur)].last_child }
        if inner != NONE {
            cur = inner
            continue
        }
        while cur != NONE {
            var sib = d.nodes[usize(cur)].next_sibling
            if from_end { sib = d.nodes[usize(cur)].previous_sibling }
            if sib != NONE {
                cur = sib
                break
            }
            let up = d.nodes[usize(cur)].parent
            if up == NONE || up == w.root || up == w.current { ret NONE }
            cur = up
        }
    }
    ret NONE
}

fn walker_sibling(d: *const Dom, w: *Walker, backwards: bool) -> NodeId {
    var cur = w.current
    if cur == w.root { ret NONE }
    while true {
        var sib = d.nodes[usize(cur)].next_sibling
        if backwards { sib = d.nodes[usize(cur)].previous_sibling }
        while sib != NONE {
            if shown(d, w, sib) {
                w.current = sib
                ret sib
            }
            var inner = d.nodes[usize(sib)].first_child
            if backwards { inner = d.nodes[usize(sib)].last_child }
            if inner != NONE && !shown(d, w, sib) {
                sib = inner
            } else {
                if backwards { sib = d.nodes[usize(sib)].previous_sibling } else { sib = d.nodes[usize(sib)].next_sibling }
            }
        }
        cur = d.nodes[usize(cur)].parent
        if cur == NONE || cur == w.root || shown(d, w, cur) { ret NONE }
    }
    ret NONE
}

// nextNode: the next shown node in tree order inside the root.
fn walker_next(d: *const Dom, w: *Walker) -> NodeId {
    var cur = next_in_tree(d, w.root, w.current)
    while cur != NONE {
        if shown(d, w, cur) {
            w.current = cur
            ret cur
        }
        cur = next_in_tree(d, w.root, cur)
    }
    ret NONE
}

// previousNode: the previous shown node in tree order inside the root.
fn walker_previous(d: *const Dom, w: *Walker) -> NodeId {
    var cur = previous_in_tree(d, w.root, w.current)
    while cur != NONE {
        if cur != w.root && shown(d, w, cur) {
            w.current = cur
            ret cur
        }
        if cur == w.root { ret NONE }
        cur = previous_in_tree(d, w.root, cur)
    }
    ret NONE
}
