// The accessibility tree of an HTML document (L040), after Vaper's `a11y/accessibility_builder.dart`: each element's role
// (an explicit `role` attribute from a known set first, else its native role), its accessible name by the order the
// platform standard fixes -- `aria-labelledby` over `aria-label` over the element's native source (an `alt`, a `<label>`,
// a placeholder, a caption, a title) over its text content for the roles that name from content -- its states
// (checked, expanded, selected, disabled, required, invalid), heading level, value range and link referenced, and the tree
// with `aria-hidden` subtrees dropped, a nameless stateless generic container flattened into its children and the
// redundant text leaves of a name-from-content role removed.
//
// A node is numbered in document order from the root, an element or a text node each taking one; text leaves carry the
// number of the text node, a link leaf (text inside an `<a href>`) none.
//
// Memory: the arena is retained; every node and string lives in it.

use e.data.list as list
use e.fmt.html as html
use e.mem
use e.str

type Role = enum u8 { Generic, Text, Heading, Link, Button, Image, TextField, Checkbox, Radio, Combobox, Listbox, Slider, Progressbar, List, ListItem, Table, Row, Cell, ColumnHeader, RowHeader, Navigation, Main, Banner, ContentInfo, Complementary, Form, Search, Region, Article, Dialog, Separator, Figure, Group }

// `node_id` is -1 for a node that stands for no one DOM node (a link leaf). A flag named `has_*` says its value is present.
type Node = struct { role: Role, name: str, has_value: bool, value: str, node_id: i64, has_level: bool, level: i64, has_checked: bool, checked: bool, checked_mixed: bool, disabled: bool, has_expanded: bool, expanded: bool, has_selected: bool, selected: bool, required: bool, invalid: bool, has_now: bool, now: f64, has_min: bool, min: f64, has_max: bool, max: f64, has_url: bool, url: str, focusable: bool, children: []const Node }

type Builder = struct { a: *mem.Arena, doc: *const html.Document, next_id: i64 }

fn role_name(r: Role) -> str {
    switch r {
    case .Generic:
        ret "generic"
    case .Text:
        ret "text"
    case .Heading:
        ret "heading"
    case .Link:
        ret "link"
    case .Button:
        ret "button"
    case .Image:
        ret "image"
    case .TextField:
        ret "textField"
    case .Checkbox:
        ret "checkbox"
    case .Radio:
        ret "radio"
    case .Combobox:
        ret "combobox"
    case .Listbox:
        ret "listbox"
    case .Slider:
        ret "slider"
    case .Progressbar:
        ret "progressbar"
    case .List:
        ret "list"
    case .ListItem:
        ret "listItem"
    case .Table:
        ret "table"
    case .Row:
        ret "row"
    case .Cell:
        ret "cell"
    case .ColumnHeader:
        ret "columnHeader"
    case .RowHeader:
        ret "rowHeader"
    case .Navigation:
        ret "navigation"
    case .Main:
        ret "main"
    case .Banner:
        ret "banner"
    case .ContentInfo:
        ret "contentInfo"
    case .Complementary:
        ret "complementary"
    case .Form:
        ret "form"
    case .Search:
        ret "search"
    case .Region:
        ret "region"
    case .Article:
        ret "article"
    case .Dialog:
        ret "dialog"
    case .Separator:
        ret "separator"
    case .Figure:
        ret "figure"
    case .Group:
        ret "group"
    }
}

fn blank_node(role: Role) -> Node {
    ret Node { role: role, name: "", has_value: false, value: "", node_id: -1i64, has_level: false, level: 0i64, has_checked: false, checked: false, checked_mixed: false, disabled: false, has_expanded: false, expanded: false, has_selected: false, selected: false, required: false, invalid: false, has_now: false, now: 0.0f64, has_min: false, min: 0.0f64, has_max: false, max: 0.0f64, has_url: false, url: "", focusable: false, children: zero }
}

// --- text helpers -------------------------------------------------------------------------------------------------------

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn trim(s: str) -> str {
    var start = 0usize
    var end = s.len
    while start < end && is_space(s[start]) { start += 1usize }
    while end > start && is_space(s[end - 1usize]) { end -= 1usize }
    ret s[start..end]
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

// Collapse runs of space, tab, CR, LF, FF and the zero-width space to one space and trim.
fn collapse(a: *mem.Arena, s: str) -> str {
    let (b, e) = str.builder(a, s.len + 1usize)
    if e != ok { ret s }
    var out = b
    var pending = false
    var wrote = false
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var skip = 0usize
        if c == 32u8 || c == 9u8 || c == 13u8 || c == 10u8 || c == 12u8 {
            skip = 1usize
        } else if c == 226u8 && i + 2usize < s.len && s[i + 1usize] == 128u8 && s[i + 2usize] == 139u8 {
            skip = 3usize
        }
        if skip > 0usize {
            pending = true
            i += skip
        } else {
            if pending && wrote {
                let p = str.push_byte(&out, 32u8)
            }
            pending = false
            let q = str.push_byte(&out, c)
            wrote = true
            i += 1usize
        }
    }
    ret str.done(&out)
}

fn int_of(s: str) -> (i64, bool) {
    if s.len == 0usize { ret (0i64, false) }
    var at = 0usize
    var negative = false
    if s[0] == 45u8 {
        negative = true
        at = 1usize
    } else if s[0] == 43u8 {
        at = 1usize
    }
    if at >= s.len { ret (0i64, false) }
    var v = 0i64
    while at < s.len {
        if s[at] < 48u8 || s[at] > 57u8 { ret (0i64, false) }
        v = v * 10i64 + i64(s[at] - 48u8)
        at += 1usize
    }
    if negative { ret (-v, true) }
    ret (v, true)
}

fn number_of(a: *mem.Arena, s: str) -> (f64, bool) {
    let t = trim(s)
    if t.len == 0usize { ret (0.0f64, false) }
    var at = 0usize
    var text = ""
    if t[0] == 45u8 {
        text = "-"
        at = 1usize
    } else if t[0] == 43u8 {
        at = 1usize
    }
    let int_start = at
    while at < t.len && t[at] >= 48u8 && t[at] <= 57u8 { at += 1usize }
    let int_digits = t[int_start..at]
    var frac = ""
    if at < t.len && t[at] == 46u8 {
        at += 1usize
        let f = at
        while at < t.len && t[at] >= 48u8 && t[at] <= 57u8 { at += 1usize }
        frac = t[f..at]
    }
    if int_digits.len == 0usize && frac.len == 0usize { ret (0.0f64, false) }
    var exp = ""
    if at < t.len && (t[at] == 101u8 || t[at] == 69u8) {
        var j = at + 1usize
        var sign = ""
        if j < t.len && (t[j] == 43u8 || t[j] == 45u8) {
            if t[j] == 45u8 { sign = "-" }
            j += 1usize
        }
        let e0 = j
        while j < t.len && t[j] >= 48u8 && t[j] <= 57u8 { j += 1usize }
        if j == e0 { ret (0.0f64, false) }
        exp = cat(a, cat(a, "e", sign), t[e0..j])
        at = j
    }
    if at != t.len { ret (0.0f64, false) }
    var body = int_digits
    if body.len == 0usize { body = "0" }
    text = cat(a, text, body)
    if frac.len > 0usize { text = cat(a, cat(a, text, "."), frac) }
    text = cat(a, text, exp)
    let (v, e) = str.parse_f64(text)
    if e != ok { ret (0.0f64, false) }
    ret (v, true)
}

// --- the element ----------------------------------------------------------------------------------------------------------

fn node_of(b: *const Builder, id: html.NodeId) -> *const html.Node {
    ret &b.doc.nodes[usize(id)]
}

fn attr(b: *const Builder, id: html.NodeId, name: str) -> (str, bool) {
    let (v, found) = html.attribute(&b.doc.nodes[usize(id)], name)
    ret (v, found)
}

fn has_attr(b: *const Builder, id: html.NodeId, name: str) -> bool {
    let (v, found) = attr(b, id, name)
    ret found
}

fn tag(b: *const Builder, id: html.NodeId) -> str { ret b.doc.nodes[usize(id)].name }

fn parent_element(b: *const Builder, id: html.NodeId) -> html.NodeId {
    let p = b.doc.nodes[usize(id)].parent
    if p == html.NONE || b.doc.nodes[usize(p)].kind != .Element { ret html.NONE }
    ret p
}

// `aria-<name>` trimmed, absent when missing or empty.
fn aria(b: *const Builder, el: html.NodeId, name: str) -> (str, bool) {
    let (v, found) = attr(b, el, cat(b.a, "aria-", name))
    if !found { ret ("", false) }
    let t = trim(v)
    if t.len == 0usize { ret ("", false) }
    ret (t, true)
}

// `true`, `false` or absent.
fn aria_bool(b: *const Builder, el: html.NodeId, name: str) -> (bool, bool) {
    let (v, found) = aria(b, el, name)
    if !found { ret (false, false) }
    let l = lower(b.a, v)
    if str.eq(l, "true") { ret (true, true) }
    if str.eq(l, "false") { ret (false, true) }
    ret (false, false)
}

fn is_aria_hidden(b: *const Builder, el: html.NodeId) -> bool {
    let (v, found) = attr(b, el, "aria-hidden")
    if !found { ret false }
    ret str.eq(lower(b.a, trim(v)), "true")
}

fn flat_text(b: *const Builder, el: html.NodeId) -> str {
    let (t, e) = html.text_content(b.a, b.doc, el)
    if e != ok { ret "" }
    ret collapse(b.a, t)
}

fn input_type(b: *const Builder, el: html.NodeId) -> str {
    let (t, found) = attr(b, el, "type")
    if !found { ret "text" }
    ret lower(b.a, trim(t))
}

fn explicit_role(name: str) -> (Role, bool) {
    if str.eq(name, "button") { ret (.Button, true) }
    if str.eq(name, "link") { ret (.Link, true) }
    if str.eq(name, "heading") { ret (.Heading, true) }
    if str.eq(name, "img") || str.eq(name, "image") { ret (.Image, true) }
    if str.eq(name, "textbox") || str.eq(name, "searchbox") { ret (.TextField, true) }
    if str.eq(name, "checkbox") || str.eq(name, "switch") { ret (.Checkbox, true) }
    if str.eq(name, "radio") { ret (.Radio, true) }
    if str.eq(name, "combobox") { ret (.Combobox, true) }
    if str.eq(name, "listbox") { ret (.Listbox, true) }
    if str.eq(name, "slider") { ret (.Slider, true) }
    if str.eq(name, "progressbar") || str.eq(name, "meter") { ret (.Progressbar, true) }
    if str.eq(name, "list") { ret (.List, true) }
    if str.eq(name, "listitem") { ret (.ListItem, true) }
    if str.eq(name, "table") || str.eq(name, "grid") { ret (.Table, true) }
    if str.eq(name, "row") { ret (.Row, true) }
    if str.eq(name, "cell") || str.eq(name, "gridcell") { ret (.Cell, true) }
    if str.eq(name, "columnheader") { ret (.ColumnHeader, true) }
    if str.eq(name, "rowheader") { ret (.RowHeader, true) }
    if str.eq(name, "navigation") { ret (.Navigation, true) }
    if str.eq(name, "main") { ret (.Main, true) }
    if str.eq(name, "banner") { ret (.Banner, true) }
    if str.eq(name, "contentinfo") { ret (.ContentInfo, true) }
    if str.eq(name, "complementary") { ret (.Complementary, true) }
    if str.eq(name, "form") { ret (.Form, true) }
    if str.eq(name, "search") { ret (.Search, true) }
    if str.eq(name, "region") { ret (.Region, true) }
    if str.eq(name, "article") { ret (.Article, true) }
    if str.eq(name, "dialog") || str.eq(name, "alertdialog") { ret (.Dialog, true) }
    if str.eq(name, "separator") { ret (.Separator, true) }
    if str.eq(name, "figure") { ret (.Figure, true) }
    if str.eq(name, "group") || str.eq(name, "radiogroup") { ret (.Group, true) }
    if str.eq(name, "presentation") || str.eq(name, "none") { ret (.Generic, true) }
    ret (.Generic, false)
}

fn native_role(b: *const Builder, el: html.NodeId) -> Role {
    let t = tag(b, el)
    if str.eq(t, "a") {
        if has_attr(b, el, "href") { ret .Link }
        ret .Generic
    }
    if str.eq(t, "button") || str.eq(t, "summary") { ret .Button }
    if str.eq(t, "h1") || str.eq(t, "h2") || str.eq(t, "h3") || str.eq(t, "h4") || str.eq(t, "h5") || str.eq(t, "h6") { ret .Heading }
    if str.eq(t, "img") || str.eq(t, "svg") || str.eq(t, "canvas") { ret .Image }
    if str.eq(t, "input") {
        let it = input_type(b, el)
        if str.eq(it, "checkbox") { ret .Checkbox }
        if str.eq(it, "radio") { ret .Radio }
        if str.eq(it, "range") { ret .Slider }
        if str.eq(it, "submit") || str.eq(it, "reset") || str.eq(it, "button") || str.eq(it, "file") || str.eq(it, "image") { ret .Button }
        if str.eq(it, "hidden") { ret .Generic }
        ret .TextField
    }
    if str.eq(t, "textarea") { ret .TextField }
    if str.eq(t, "select") {
        if has_attr(b, el, "multiple") { ret .Listbox }
        ret .Combobox
    }
    if str.eq(t, "progress") || str.eq(t, "meter") { ret .Progressbar }
    if str.eq(t, "ul") || str.eq(t, "ol") || str.eq(t, "menu") || str.eq(t, "dl") { ret .List }
    if str.eq(t, "li") { ret .ListItem }
    if str.eq(t, "table") { ret .Table }
    if str.eq(t, "tr") { ret .Row }
    if str.eq(t, "td") { ret .Cell }
    if str.eq(t, "th") { ret .ColumnHeader }
    if str.eq(t, "thead") || str.eq(t, "tbody") || str.eq(t, "tfoot") || str.eq(t, "fieldset") || str.eq(t, "details") { ret .Group }
    if str.eq(t, "nav") { ret .Navigation }
    if str.eq(t, "main") { ret .Main }
    if str.eq(t, "header") { ret .Banner }
    if str.eq(t, "footer") { ret .ContentInfo }
    if str.eq(t, "aside") { ret .Complementary }
    if str.eq(t, "form") { ret .Form }
    if str.eq(t, "search") { ret .Search }
    if str.eq(t, "section") { ret .Region }
    if str.eq(t, "article") { ret .Article }
    if str.eq(t, "dialog") { ret .Dialog }
    if str.eq(t, "hr") { ret .Separator }
    if str.eq(t, "figure") { ret .Figure }
    ret .Generic
}

// The element's role: the first token of `role` that is known, else its native role.
fn role_of(b: *const Builder, el: html.NodeId) -> Role {
    let (raw, found) = attr(b, el, "role")
    if found {
        let explicit = lower(b.a, trim(raw))
        if explicit.len > 0usize {
            var start = 0usize
            var i = 0usize
            while i <= explicit.len {
                if i == explicit.len || is_space(explicit[i]) {
                    if i > start {
                        let (r, known) = explicit_role(explicit[start..i])
                        if known { ret r }
                    }
                    start = i + 1usize
                }
                i += 1usize
            }
        }
    }
    ret native_role(b, el)
}

fn names_from_content(r: Role) -> bool {
    ret r == .Button || r == .Link || r == .Heading || r == .Cell || r == .ColumnHeader || r == .RowHeader || r == .Checkbox || r == .Radio
}

// --- the name ---------------------------------------------------------------------------------------------------------

// The first element with this `id` in document order; none when there is no such element.
fn find_by_id(b: *const Builder, from: html.NodeId, id: str) -> html.NodeId {
    let node = &b.doc.nodes[usize(from)]
    if node.kind == .Element {
        let (v, found) = html.attribute(node, "id")
        if found && v.len > 0usize && str.eq(v, id) { ret from }
    }
    var child = node.first_child
    while child != html.NONE {
        let r = find_by_id(b, child, id)
        if r != html.NONE { ret r }
        child = b.doc.nodes[usize(child)].next_sibling
    }
    ret html.NONE
}

// The first `<label for=id>` in document order whose `for` is non-empty.
fn find_label_for(b: *const Builder, from: html.NodeId, id: str) -> html.NodeId {
    let node = &b.doc.nodes[usize(from)]
    if node.kind == .Element && str.eq(node.name, "label") {
        let (v, found) = html.attribute(node, "for")
        if found {
            let t = trim(v)
            if t.len > 0usize && str.eq(t, id) { ret from }
        }
    }
    var child = node.first_child
    while child != html.NONE {
        let r = find_label_for(b, child, id)
        if r != html.NONE { ret r }
        child = b.doc.nodes[usize(child)].next_sibling
    }
    ret html.NONE
}

fn label_text(b: *const Builder, control: html.NodeId) -> (str, bool) {
    let (id, have_id) = attr(b, control, "id")
    if have_id && id.len > 0usize {
        let label = find_label_for(b, b.doc.root, id)
        if label != html.NONE {
            let text = flat_text(b, label)
            if text.len > 0usize { ret (text, true) }
        }
    }
    var p = parent_element(b, control)
    while p != html.NONE {
        if str.eq(tag(b, p), "label") {
            let text = flat_text(b, p)
            if text.len > 0usize { ret (text, true) }
        }
        p = parent_element(b, p)
    }
    ret ("", false)
}

fn child_text(b: *const Builder, el: html.NodeId, name: str) -> (str, bool) {
    var child = b.doc.nodes[usize(el)].first_child
    while child != html.NONE {
        if b.doc.nodes[usize(child)].kind == .Element && str.eq(tag(b, child), name) {
            let text = flat_text(b, child)
            if text.len == 0usize { ret ("", false) }
            ret (text, true)
        }
        child = b.doc.nodes[usize(child)].next_sibling
    }
    ret ("", false)
}

fn trimmed_attr(b: *const Builder, el: html.NodeId, name: str) -> (str, bool) {
    let (v, found) = attr(b, el, name)
    if !found { ret ("", false) }
    ret (trim(v), true)
}

fn native_name(b: *const Builder, el: html.NodeId) -> (str, bool) {
    let t = tag(b, el)
    if str.eq(t, "img") || str.eq(t, "area") {
        let (r0, r1) = trimmed_attr(b, el, "alt")
        ret (r0, r1)
    }
    if str.eq(t, "input") {
        let it = input_type(b, el)
        if str.eq(it, "submit") || str.eq(it, "reset") || str.eq(it, "button") {
            let (v, found) = trimmed_attr(b, el, "value")
            if found && v.len > 0usize { ret (v, true) }
            if str.eq(it, "submit") { ret ("Submit", true) }
            if str.eq(it, "reset") { ret ("Reset", true) }
            ret ("", false)
        }
        if str.eq(it, "image") {
            let (r0, r1) = trimmed_attr(b, el, "alt")
            ret (r0, r1)
        }
    }
    if str.eq(t, "input") || str.eq(t, "textarea") || str.eq(t, "select") {
        let (label, have_label) = label_text(b, el)
        if have_label { ret (label, true) }
        let (ph, have_ph) = trimmed_attr(b, el, "placeholder")
        if have_ph { ret (ph, true) }
        let (r0, r1) = trimmed_attr(b, el, "title")
        ret (r0, r1)
    }
    if str.eq(t, "table") {
        let (r0, r1) = child_text(b, el, "caption")
        ret (r0, r1)
    }
    if str.eq(t, "fieldset") {
        let (r0, r1) = child_text(b, el, "legend")
        ret (r0, r1)
    }
    if str.eq(t, "figure") {
        let (r0, r1) = child_text(b, el, "figcaption")
        ret (r0, r1)
    }
    if str.eq(t, "svg") {
        let (r0, r1) = child_text(b, el, "title")
        ret (r0, r1)
    }
    let (r0, r1) = trimmed_attr(b, el, "title")
    ret (r0, r1)
}

fn name_of(b: *const Builder, el: html.NodeId, role: Role) -> str {
    let (labelled_by, have_lb) = trimmed_attr(b, el, "aria-labelledby")
    if have_lb && labelled_by.len > 0usize {
        var joined = ""
        var first = true
        var start = 0usize
        var i = 0usize
        while i <= labelled_by.len {
            if i == labelled_by.len || is_space(labelled_by[i]) {
                if i > start {
                    let referenced = find_by_id(b, b.doc.root, labelled_by[start..i])
                    if referenced != html.NONE {
                        if !first { joined = cat(b.a, joined, " ") }
                        joined = cat(b.a, joined, flat_text(b, referenced))
                        first = false
                    }
                }
                start = i + 1usize
            }
            i += 1usize
        }
        let collapsed = collapse(b.a, joined)
        if collapsed.len > 0usize { ret collapsed }
    }
    let (label, have_label) = trimmed_attr(b, el, "aria-label")
    if have_label && label.len > 0usize { ret label }
    let (native, have_native) = native_name(b, el)
    if have_native && native.len > 0usize { ret native }
    if names_from_content(role) { ret flat_text(b, el) }
    ret ""
}

// --- the tree ----------------------------------------------------------------------------------------------------------

fn heading_level_of_tag(b: *const Builder, el: html.NodeId) -> (i64, bool) {
    let t = tag(b, el)
    if t.len != 2usize || t[0] != 104u8 { ret (0i64, false) }
    if t[1] < 48u8 || t[1] > 57u8 { ret (0i64, false) }
    let lv = i64(t[1] - 48u8)
    if lv >= 1i64 && lv <= 6i64 { ret (lv, true) }
    ret (0i64, false)
}

fn num_attr(b: *const Builder, el: html.NodeId, name: str, fallback: f64) -> f64 {
    let (raw, found) = attr(b, el, name)
    if !found { ret fallback }
    let (v, good) = number_of(b.a, raw)
    if good { ret v }
    ret fallback
}

fn push_node(l: *list.List[Node], n: Node) {
    let e = list.push[Node](l, n)
}

fn new_nodes(a: *mem.Arena) -> list.List[Node] {
    let (l, e) = list.init[Node](a, 4usize)
    if e != ok { ret list.List[Node] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn link_href_above(b: *const Builder, id: html.NodeId) -> (str, bool) {
    var p = parent_element(b, id)
    while p != html.NONE {
        if str.eq(tag(b, p), "a") {
            let (href, found) = attr(b, p, "href")
            if found { ret (href, true) }
        }
        p = parent_element(b, p)
    }
    ret ("", false)
}

// The leaves of one text node: static text, or a link when the text sits inside an `<a href>`.
fn text_leaves(b: *Builder, id: html.NodeId, node_id: i64) -> []const Node {
    var out = new_nodes(b.a)
    let text = collapse(b.a, b.doc.nodes[usize(id)].value)
    if text.len == 0usize { ret list.slice_const[Node](&out) }
    let (href, in_link) = link_href_above(b, id)
    if in_link {
        var n = blank_node(.Link)
        n.name = text
        n.has_url = true
        n.url = href
        n.focusable = true
        push_node(&out, n)
    } else {
        var n = blank_node(.Text)
        n.name = text
        n.node_id = node_id
        push_node(&out, n)
    }
    ret list.slice_const[Node](&out)
}

// The tree of the children of `parent` (an element), numbering nodes in document order.
fn build_children(b: *Builder, parent: html.NodeId) -> []const Node {
    var out = new_nodes(b.a)
    var child = b.doc.nodes[usize(parent)].first_child
    while child != html.NONE {
        let kind = b.doc.nodes[usize(child)].kind
        if kind == .Element {
            let id = b.next_id
            b.next_id += 1i64
            let nodes = build_element(b, child, id)
            var k = 0usize
            while k < nodes.len {
                push_node(&out, nodes[k])
                k += 1usize
            }
        } else if kind == .Text {
            let id = b.next_id
            b.next_id += 1i64
            let leaves = text_leaves(b, child, id)
            var k = 0usize
            while k < leaves.len {
                push_node(&out, leaves[k])
                k += 1usize
            }
        }
        child = b.doc.nodes[usize(child)].next_sibling
    }
    ret list.slice_const[Node](&out)
}

// Number the subtree of an element without producing nodes (an `aria-hidden` subtree still consumes its numbers).
fn skip_ids(b: *Builder, el: html.NodeId) {
    var child = b.doc.nodes[usize(el)].first_child
    while child != html.NONE {
        let kind = b.doc.nodes[usize(child)].kind
        if kind == .Element {
            b.next_id += 1i64
            skip_ids(b, child)
        } else if kind == .Text {
            b.next_id += 1i64
        }
        child = b.doc.nodes[usize(child)].next_sibling
    }
}

fn with_node_id(n: Node, id: i64) -> Node {
    if n.role == .Link { ret n }
    var out = n
    out.node_id = id
    ret out
}

fn build_element(b: *Builder, el: html.NodeId, id: i64) -> []const Node {
    if is_aria_hidden(b, el) {
        skip_ids(b, el)
        ret zero
    }
    let children = build_children(b, el)
    let role = role_of(b, el)
    let name = name_of(b, el, role)
    var n = blank_node(role)
    n.name = name
    n.node_id = id
    let (dis, have_dis) = aria_bool(b, el, "disabled")
    if have_dis { n.disabled = dis } else { n.disabled = has_attr(b, el, "disabled") }
    let (ac, have_ac) = aria(b, el, "checked")
    var checked_mixed = false
    if have_ac {
        let l = lower(b.a, ac)
        checked_mixed = str.eq(l, "mixed")
        n.has_checked = true
        n.checked = str.eq(l, "true")
    } else if role == .Checkbox || role == .Radio {
        n.has_checked = true
        n.checked = has_attr(b, el, "checked")
    }
    n.checked_mixed = checked_mixed
    let (ex, have_ex) = aria_bool(b, el, "expanded")
    if have_ex {
        n.has_expanded = true
        n.expanded = ex
    } else if str.eq(tag(b, el), "details") {
        n.has_expanded = true
        n.expanded = has_attr(b, el, "open")
    }
    let (sel, have_sel) = aria_bool(b, el, "selected")
    if have_sel {
        n.has_selected = true
        n.selected = sel
    }
    let (req, have_req) = aria_bool(b, el, "required")
    if have_req { n.required = req } else { n.required = has_attr(b, el, "required") }
    let (inv, have_inv) = aria(b, el, "invalid")
    n.invalid = have_inv && !str.eq(lower(b.a, inv), "false")
    if role == .Heading {
        let (lv_text, have_lv) = aria(b, el, "level")
        var level = 0i64
        var have_level = false
        if have_lv {
            let (v, good) = int_of(lv_text)
            if good {
                level = v
                have_level = true
            }
        }
        if !have_level {
            let (v, good) = heading_level_of_tag(b, el)
            if good {
                level = v
                have_level = true
            }
        }
        if !have_level { level = 2i64 }
        n.has_level = true
        n.level = level
    }
    let (now_text, have_now_attr) = aria(b, el, "valuenow")
    if have_now_attr {
        let (v, good) = number_of(b.a, now_text)
        if good {
            n.has_now = true
            n.now = v
        }
    }
    let (min_text, have_min_attr) = aria(b, el, "valuemin")
    if have_min_attr {
        let (v, good) = number_of(b.a, min_text)
        if good {
            n.has_min = true
            n.min = v
        }
    }
    let (max_text, have_max_attr) = aria(b, el, "valuemax")
    if have_max_attr {
        let (v, good) = number_of(b.a, max_text)
        if good {
            n.has_max = true
            n.max = v
        }
    }
    if !n.has_now {
        let t = tag(b, el)
        if str.eq(t, "input") && str.eq(input_type(b, el), "range") {
            let mn = num_attr(b, el, "min", 0.0f64)
            let mx = num_attr(b, el, "max", 100.0f64)
            n.has_min = true
            n.min = mn
            n.has_max = true
            n.max = mx
            n.has_now = true
            n.now = num_attr(b, el, "value", (mn + mx) / 2.0f64)
        } else if str.eq(t, "progress") {
            n.has_min = true
            n.min = 0.0f64
            n.has_max = true
            n.max = num_attr(b, el, "max", 1.0f64)
            if has_attr(b, el, "value") {
                n.has_now = true
                n.now = num_attr(b, el, "value", 0.0f64)
            }
        } else if str.eq(t, "meter") {
            n.has_min = true
            n.min = num_attr(b, el, "min", 0.0f64)
            n.has_max = true
            n.max = num_attr(b, el, "max", 1.0f64)
            n.has_now = true
            n.now = num_attr(b, el, "value", 0.0f64)
        }
    }
    if role == .TextField {
        if str.eq(tag(b, el), "textarea") {
            let (t, e) = html.text_content(b.a, b.doc, el)
            if e == ok {
                n.has_value = true
                n.value = t
            }
        } else {
            let (v, found) = attr(b, el, "value")
            if found {
                n.has_value = true
                n.value = v
            }
        }
    }
    if role == .Link {
        let (href, found) = trimmed_attr(b, el, "href")
        if found && href.len > 0usize {
            n.has_url = true
            n.url = href
        }
    }
    var kids = children
    if name.len > 0usize && names_from_content(role) {
        var kept = new_nodes(b.a)
        var k = 0usize
        while k < children.len {
            if children[k].role != .Text { push_node(&kept, children[k]) }
            k += 1usize
        }
        kids = list.slice_const[Node](&kept)
    }
    n.children = kids
    let has_state = n.has_checked || n.checked_mixed || n.disabled || n.has_expanded || n.has_selected || n.required || n.invalid || n.has_now
    if role == .Generic && name.len == 0usize && !has_state && !n.focusable {
        if kids.len == 0usize { ret zero }
        if kids.len == 1usize {
            var only = kids[0]
            if only.node_id < 0i64 { only = with_node_id(only, id) }
            let (single, e) = mem.alloc[Node](b.a, 1usize)
            if e != ok { ret zero }
            single[0] = only
            ret single[0usize..1usize]
        }
        var wrap = blank_node(.Generic)
        wrap.node_id = id
        wrap.children = kids
        let (single, e) = mem.alloc[Node](b.a, 1usize)
        if e != ok { ret zero }
        single[0] = wrap
        ret single[0usize..1usize]
    }
    let (single, e) = mem.alloc[Node](b.a, 1usize)
    if e != ok { ret zero }
    single[0] = n
    ret single[0usize..1usize]
}

// The accessibility tree under `root` (an element, typically `<body>`): a generic root node numbered 0 holding the
// tree of its children, or a bare generic node when the root is `aria-hidden`.
fn build_tree(a: *mem.Arena, doc: *const html.Document, root: html.NodeId) -> Node {
    var b = Builder { a: a, doc: doc, next_id: 1i64 }
    var out = blank_node(.Generic)
    out.node_id = 0i64
    if is_aria_hidden(&b, root) { ret out }
    out.children = build_children(&b, root)
    ret out
}
