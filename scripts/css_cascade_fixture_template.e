// `e.fmt.css.cascade` against Vaper's own StyleResolver (style_resolver.dart): scripts/css_cascade_vectors.mjs writes random
// documents with user-agent and author rule sets (selectors, !important, source ties, layers, @container queries over a
// container stack, @scope donuts) and inline styles, with for every element in document order Vaper's winning
// declaration per property (`w`), its presentational hints (`h`), and the order in which its rule index offers the
// author (`a`) and user-agent (`u`) rules. The fixture builds the same rules and compares each.
use e.algo.ir as ir
use e.fmt.css.cascade as cascade
use e.fmt.css.container as container
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

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn is_null_at(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret true }
    ret ir.is_null(x)
}

fn int_of(v: json.Value, key: str) -> i64 {
    let (x, found) = ir.get(v, key)
    if !found { ret 0i64 }
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        if e == ok { ret value }
        ret 0i64
    default:
        ret 0i64
    }
}

fn f64_of(v: json.Value, key: str) -> f64 {
    let (x, found) = ir.get(v, key)
    if !found { ret 0.0f64 }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        if e == ok { ret value }
        ret 0.0f64
    default:
        ret 0.0f64
    }
}

fn bool_of(v: json.Value) -> bool {
    switch v {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn condition(a: *mem.Arena, j: json.Value) -> container.Condition {
    let t = text_of(j, "t")
    if str.eq(t, "and") || str.eq(t, "or") {
        let (ps, is_array) = ir.items_of(ir.value_of(j, "p"))
        let (out, e) = mem.alloc[container.Condition](a, ps.len + 1usize)
        if e != ok { os.exit(80i32) }
        var at = 0usize
        while at < ps.len {
            out[at] = condition(a, ps[at])
            at += 1usize
        }
        var kind: container.CondKind = .And
        if str.eq(t, "or") { kind = .Or }
        ret container.Condition { kind: kind, parts: out[0usize..ps.len], feature: .Width, op: .Eq, value: 0.0f64 }
    }
    if str.eq(t, "not") {
        let (out, e) = mem.alloc[container.Condition](a, 1usize)
        if e != ok { os.exit(81i32) }
        out[0] = condition(a, ir.value_of(j, "p"))
        ret container.Condition { kind: .Not, parts: out[0usize..1usize], feature: .Width, op: .Eq, value: 0.0f64 }
    }
    if str.eq(t, "unknown") { ret container.unknown_condition() }
    var feature: container.FeatureKind = .Width
    let f = text_of(j, "f")
    if str.eq(f, "height") { feature = .Height }
    if str.eq(f, "aspectRatio") { feature = .AspectRatio }
    if str.eq(f, "orientationPortrait") { feature = .OrientationPortrait }
    if str.eq(f, "orientationLandscape") { feature = .OrientationLandscape }
    var op: container.Op = .Eq
    let o = text_of(j, "o")
    if str.eq(o, "lt") { op = .Lt }
    if str.eq(o, "le") { op = .Le }
    if str.eq(o, "gt") { op = .Gt }
    if str.eq(o, "ge") { op = .Ge }
    ret container.Condition { kind: .Feature, parts: zero, feature: feature, op: op, value: f64_of(j, "v") }
}

fn parse_selector(a: *mem.Arena, src: str) -> selector.Selector {
    let (tokens, te) = syntax.tokenize(a, src)
    if te != ok { os.exit(82i32) }
    let (rules, re) = selector.parse_selector_list_for_rule(a, src, tokens)
    if re != ok || rules.len == 0usize { os.exit(83i32) }
    ret rules[0].selector
}

fn selectors(a: *mem.Arena, v: json.Value) -> []const selector.Selector {
    let (items, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[selector.Selector](a, items.len + 1usize)
    if e != ok { os.exit(84i32) }
    var at = 0usize
    while at < items.len {
        let (s, is_text) = ir.string_of(items[at])
        out[at] = parse_selector(a, s)
        at += 1usize
    }
    ret out[0usize..items.len]
}

fn build_rule(a: *mem.Arena, j: json.Value) -> cascade.Rule {
    let (ds, d_array) = ir.items_of(ir.value_of(j, "d"))
    let (decls, de) = mem.alloc[cascade.Declaration](a, ds.len + 1usize)
    if de != ok { os.exit(85i32) }
    var at = 0usize
    while at < ds.len {
        let (parts, p_array) = ir.items_of(ds[at])
        let (property, pt) = ir.string_of(parts[0])
        let (val, vt) = ir.string_of(parts[1])
        decls[at] = cascade.Declaration { property: property, value: val, important: bool_of(parts[2]) }
        at += 1usize
    }
    let (cs, c_array) = ir.items_of(ir.value_of(j, "cont"))
    let (queries, qe) = mem.alloc[cascade.ContainerQuery](a, cs.len + 1usize)
    if qe != ok { os.exit(86i32) }
    var q = 0usize
    while q < cs.len {
        queries[q] = cascade.ContainerQuery { has_name: !is_null_at(cs[q], "n"), name: text_of(cs[q], "n"), condition: condition(a, ir.value_of(cs[q], "c")) }
        q += 1usize
    }
    let (ss, s_array) = ir.items_of(ir.value_of(j, "sc"))
    let (scopes, se) = mem.alloc[cascade.Scope](a, ss.len + 1usize)
    if se != ok { os.exit(87i32) }
    var s = 0usize
    while s < ss.len {
        scopes[s] = cascade.Scope { starts: selectors(a, ir.value_of(ss[s], "s")), limits: selectors(a, ir.value_of(ss[s], "l")) }
        s += 1usize
    }
    ret cascade.Rule { selector: parse_selector(a, text_of(j, "sel")), declarations: decls[0usize..ds.len], source: int_of(j, "src"), has_layer: !is_null_at(j, "layer"), layer: int_of(j, "layer"), containers: queries[0usize..cs.len], scopes: scopes[0usize..ss.len] }
}

fn build_rules(a: *mem.Arena, v: json.Value) -> []const cascade.Rule {
    let (items, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[cascade.Rule](a, items.len + 1usize)
    if e != ok { os.exit(88i32) }
    var at = 0usize
    while at < items.len {
        out[at] = build_rule(a, items[at])
        at += 1usize
    }
    ret out[0usize..items.len]
}

fn build_stack(a: *mem.Arena, v: json.Value) -> []const cascade.ContainerBox {
    let (items, is_array) = ir.items_of(v)
    let (out, e) = mem.alloc[cascade.ContainerBox](a, items.len + 1usize)
    if e != ok { os.exit(89i32) }
    var at = 0usize
    while at < items.len {
        let (ns, n_array) = ir.items_of(ir.value_of(items[at], "n"))
        let (names, ne) = mem.alloc[str](a, ns.len + 1usize)
        if ne != ok { os.exit(90i32) }
        var k = 0usize
        while k < ns.len {
            let (name, is_text) = ir.string_of(ns[k])
            names[k] = name
            k += 1usize
        }
        var kind: cascade.ContainerKind = .InlineSize
        if str.eq(text_of(items[at], "k"), "size") { kind = .Size }
        out[at] = cascade.ContainerBox { kind: kind, names: names[0usize..ns.len], has_width: !is_null_at(items[at], "w"), width: f64_of(items[at], "w"), has_height: !is_null_at(items[at], "h"), height: f64_of(items[at], "h") }
        at += 1usize
    }
    ret out[0usize..items.len]
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

fn winner_of(ws: []const cascade.Winner, property: str) -> (str, bool) {
    var at = 0usize
    while at < ws.len {
        if str.eq(ws[at].property, property) { ret (ws[at].value, true) }
        at += 1usize
    }
    ret ("", false)
}

fn same_indices(got: []const usize, want: json.Value) -> bool {
    let (items, is_array) = ir.items_of(want)
    if !is_array || items.len != got.len { ret false }
    var at = 0usize
    while at < got.len {
        let (x, e) = json.number_i64(match_number(items[at]))
        if e != ok || usize(x) != got[at] { ret false }
        at += 1usize
    }
    ret true
}

fn match_number(v: json.Value) -> json.Number {
    switch v {
    case .Number as n:
        ret n
    default:
        ret json.Number { lexeme: "-1" }
    }
}

fn check_element(a: *mem.Arena, m: *const match.Matcher, ua: []const cascade.Rule, author: []const cascade.Rule, stack: []const cascade.ContainerBox, elements: []const html.NodeId, el: html.NodeId, want: json.Value) -> bool {
    if !str.eq(text_of(want, "t"), m.doc.nodes[usize(el)].name) {
        let shown = io.print("tag differs")
        ret false
    }
    let parent = match.parent_element(m, el)
    var parent_at = -1i64
    var pe = 0usize
    while pe < elements.len {
        if elements[pe] == parent { parent_at = i64(pe) }
        pe += 1usize
    }
    if parent_at != int_of(want, "p") {
        let shown = io.print("parent differs")
        ret false
    }
    var inline: []const cascade.Declaration = zero
    let (style, have_style) = match.attr(m, el, "style")
    if have_style { inline = cascade.inline_declarations(a, style) }
    let winners = cascade.resolve(m, ua, author, el, stack, inline)
    let (expected, is_object) = ir.members_of(ir.value_of(want, "w"))
    if !is_object || expected.len != winners.len {
        let shown = io.print("winner count differs; got:")
        var g = 0usize
        while g < winners.len {
            let s1 = io.print(" ")
            let s2 = io.print(winners[g].property)
            let s3 = io.print("=")
            let s4 = io.print(winners[g].value)
            g += 1usize
        }
        let s5 = io.print("\nwant:")
        var w = 0usize
        while w < expected.len {
            let s1 = io.print(" ")
            let s2 = io.print(expected[w].key)
            let s3 = io.print("=")
            let (wt, is_text) = ir.string_of(expected[w].value)
            let s4 = io.print(wt)
            w += 1usize
        }
        let s6 = io.print("\n")
        ret false
    }
    var at = 0usize
    while at < expected.len {
        let (value, found) = winner_of(winners, expected[at].key)
        let (want_text, is_text) = ir.string_of(expected[at].value)
        if !found || !is_text || !str.eq(value, want_text) {
            let shown = io.print(expected[at].key)
            ret false
        }
        at += 1usize
    }
    let hints = cascade.presentational_hints(m, el)
    let (hs, h_array) = ir.items_of(ir.value_of(want, "h"))
    if !h_array || hs.len != hints.len {
        let shown = io.print("hint count differs")
        ret false
    }
    var h = 0usize
    while h < hs.len {
        let (pair, p_array) = ir.items_of(hs[h])
        let (property, pt) = ir.string_of(pair[0])
        let (value, vt) = ir.string_of(pair[1])
        if !str.eq(property, hints[h].property) || !str.eq(value, hints[h].value) {
            let shown = io.print(property)
            ret false
        }
        h += 1usize
    }
    let author_index = cascade.build_index(a, author)
    let ua_index = cascade.build_index(a, ua)
    if !same_indices(cascade.candidates(m, &author_index, el), ir.value_of(want, "a")) {
        let shown = io.print("author candidates differ")
        ret false
    }
    if !same_indices(cascade.candidates(m, &ua_index, el), ir.value_of(want, "u")) {
        let shown = io.print("ua candidates differ")
        ret false
    }
    ret true
}

fn run_one(a: *mem.Arena, root: json.Value) -> bool {
    let options = html.Options { max_bytes: 4194304usize, max_nodes: 100000usize, max_attributes: 64usize, max_depth: 256u16, preserve_comments: true }
    let (doc, de) = html.parse(a, text_of(root, "html"), options)
    if de != ok { os.exit(91i32) }
    let (made, me) = list.init[html.NodeId](a, 64usize)
    if me != ok { os.exit(92i32) }
    var els = made
    var top = doc.nodes[usize(doc.root)].first_child
    while top != html.NONE {
        collect(&doc, top, &els)
        top = doc.nodes[usize(top)].next_sibling
    }
    let elements = list.slice_const[html.NodeId](&els)
    let ua = build_rules(a, ir.value_of(root, "ua"))
    let author = build_rules(a, ir.value_of(root, "author"))
    let stack = build_stack(a, ir.value_of(root, "stack"))
    let m = match.new_matcher(a, &doc, match.no_state())
    let (wants, w_array) = ir.items_of(ir.value_of(root, "e"))
    if !w_array || wants.len != elements.len {
        let shown = io.print("element count differs")
        ret false
    }
    var at = 0usize
    while at < elements.len {
        if !check_element(a, &m, ua, author, stack, elements, elements[at], wants[at]) {
            let (made_b, mb) = str.builder(a, 32usize)
            var nb = made_b
            let p1 = str.push(&nb, "FAIL element index ")
            let p2 = str.push_u64(&nb, u64(at))
            let p3 = str.push(&nb, " tag ")
            let p4 = str.push(&nb, doc.nodes[usize(elements[at])].name)
            let shown = io.print(str.done(&nb))
            ret false
        }
        at += 1usize
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
                let shown = io.print("FAIL case\n")
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
    try io.print("css cascade ok")
    ret ok
}
