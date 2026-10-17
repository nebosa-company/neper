// The cascade kernels of a style resolver (L040), after Vaper's `css/style_resolver.dart`: what ranks one declaration over
// another and which rules an element has to be tested against, with no property parsing or layout around them.
//
//   * `beats` is `_Declared.beats`: !important, then author over user agent, then a presentational hint over the user
//     agent (and under author), then an unlayered rule over a layered one and a later layer over an earlier, then
//     specificity, then `@scope` proximity (the nearer root wins, an unscoped rule is infinitely far) and last source
//     order, a tie going to the declaration visited later;
//   * `build_index` and `candidates` are `_RuleIndex`: a rule is bucketed by the id, else the first class, else the tag
//     of its key (rightmost) compound, and an element visits its id bucket, then each of its classes, then its tag, then
//     the universal bucket;
//   * `containers_match` is `containersMatch` over the ancestor query-container stack: each `@container` query takes the
//     nearest container that carries its name and, for a block-axis feature, has `container-type: size`;
//   * `scope_proximity` is `_scopeMatch`, `_findScopeRoot` and `_insideLimits` (donut scoping) over an `e.fmt.html` tree;
//   * `presentational_hints` is `_presentationalHints`: the legacy attributes (`bgcolor`, `width`, `align`, `border`,
//     `cellpadding`, `<font size>` ...) mapped to declarations;
//   * `resolve` is `_cascade`: hints, then the user agent rules, the author rules and the inline `style` declarations,
//     each ranked by `beats`, and a winning shorthand dropping the longhands it outranks.
//
// Media queries and the value readers are not here: the caller drops a rule whose `@media` fails before it is passed in.

use e.data.list as list
use e.data.map as map
use e.fmt.css.container as container
use e.fmt.css.match as match
use e.fmt.css.selector as selector
use e.fmt.css.syntax as syntax
use e.fmt.html as html
use e.mem
use e.str

const UNSCOPED: i64 = 2147483647i64
const INLINE_SPECIFICITY: i64 = 268435456i64

type Declaration = struct { property: str, value: str, important: bool }

type ContainerKind = enum u8 { None, InlineSize, Size }

type ContainerBox = struct { kind: ContainerKind, names: []const str, has_width: bool, width: f64, has_height: bool, height: f64 }

type ContainerQuery = struct { has_name: bool, name: str, condition: container.Condition }

type Scope = struct { starts: []const selector.Selector, limits: []const selector.Selector }

// `pseudo` is -1 for a rule of the element itself, else the `selector.PseudoElement` it styles.
type Rule = struct { selector: selector.Selector, declarations: []const Declaration, source: i64, has_layer: bool, layer: i64, containers: []const ContainerQuery, scopes: []const Scope, pseudo: i64 }

type Declared = struct { declaration: Declaration, author: bool, hint: bool, specificity: i64, source: i64, has_layer: bool, layer: i64, proximity: i64 }

type Winner = struct { property: str, value: str }

type Bucket = enum u8 { Universal, Id, Klass, Tag }

// Rules chained by bucket: `ids`, `classes` and `tags` map a key to a slot, `head`/`tail` give that slot's first and last rule and
// `next` the following rule with the same key, so a lookup visits only the rules sharing the key, in source order. The
// `universal` chain starts at `universal_head`.
type Index = struct {
    rules: []const Rule, ids: map.Map[str, usize], classes: map.Map[str, usize], tags: map.Map[str, usize],
    head: []usize, tail: []usize, next: []usize, slots: usize, universal_head: usize, universal_tail: usize
}

const END: usize = 18446744073709551615usize

// --- ranking ---------------------------------------------------------------------------------------------------------

fn beats(x: Declared, y: Declared) -> bool {
    if x.declaration.important != y.declaration.important { ret x.declaration.important }
    if x.author != y.author { ret x.author }
    if x.hint != y.hint { ret x.hint }
    if x.has_layer != y.has_layer { ret !x.has_layer }
    if x.has_layer && x.layer != y.layer { ret x.layer > y.layer }
    if x.specificity != y.specificity { ret x.specificity > y.specificity }
    if x.proximity != y.proximity { ret x.proximity < y.proximity }
    ret x.source >= y.source
}

fn find_property(best: *const list.List[Declared], property: str) -> i64 {
    var at = 0usize
    while at < best.len {
        if str.eq(best.items[at].declaration.property, property) { ret i64(at) }
        at += 1usize
    }
    ret -1i64
}

// The declaration that wins each property, in the order the properties first appeared.
fn rank(a: *mem.Arena, declared: []const Declared) -> []const Winner {
    let (made, e) = list.init[Declared](a, declared.len + 1usize)
    if e != ok { ret zero }
    var best = made
    var at = 0usize
    while at < declared.len {
        let found = find_property(&best, declared[at].declaration.property)
        if found < 0i64 {
            let pushed = list.push[Declared](&best, declared[at])
        } else if beats(declared[at], best.items[usize(found)]) {
            best.items[usize(found)] = declared[at]
        }
        at += 1usize
    }
    drop_outranked_longhands(&best, "background", "background-color", "background-image")
    drop_outranked_longhands(&best, "text-decoration", "text-decoration-line", "")
    drop_outranked_longhands(&best, "font", "font-size", "font-family")
    let (wmade, we) = list.init[Winner](a, best.len + 1usize)
    if we != ok { ret zero }
    var out = wmade
    var i = 0usize
    while i < best.len {
        let pushed = list.push[Winner](&out, Winner { property: best.items[i].declaration.property, value: best.items[i].declaration.value })
        i += 1usize
    }
    ret list.slice_const[Winner](&out)
}

// A winning shorthand that outranks a longhand drops it, so the reader re-derives the longhand from the shorthand.
fn drop_outranked_longhands(best: *list.List[Declared], shorthand: str, first: str, second: str) {
    let s = find_property(best, shorthand)
    if s < 0i64 { ret }
    let winner = best.items[usize(s)]
    let f = find_property(best, first)
    if f >= 0i64 && beats(winner, best.items[usize(f)]) { let gone = list.remove[Declared](best, usize(f)) }
    if second.len == 0usize { ret }
    let g = find_property(best, second)
    if g >= 0i64 && beats(winner, best.items[usize(g)]) { let gone = list.remove[Declared](best, usize(g)) }
}

// --- the rule index --------------------------------------------------------------------------------------------------

fn chain_add(m: *map.Map[str, usize], idx: *Index, key: str, at: usize) {
    let (slot, found) = map.get[str, usize](m, key)
    if found {
        idx.next[idx.tail[slot]] = at
        idx.tail[slot] = at
    } else {
        let s = idx.slots
        idx.slots += 1usize
        idx.head[s] = at
        idx.tail[s] = at
        let (replaced, put_error) = map.put[str, usize](m, key, s)
    }
}

// `pseudo` selects the rules that style a pseudo-element (the others are left out), so an element's own pass and each pseudo-element
// pass visit only their rules.
fn build_index(a: *mem.Arena, rules: []const Rule, pseudo: bool) -> Index {
    var idx: Index = zero
    idx.rules = rules
    idx.universal_head = END
    idx.universal_tail = END
    let (ids, e1) = map.init[str, usize](a, rules.len / 4usize + 8usize)
    let (classes, e2) = map.init[str, usize](a, rules.len / 2usize + 8usize)
    let (tags, e3) = map.init[str, usize](a, 128usize)
    let (head, e4) = mem.alloc[usize](a, rules.len + 1usize)
    let (tail, e5) = mem.alloc[usize](a, rules.len + 1usize)
    let (next, e6) = mem.alloc[usize](a, rules.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret idx }
    idx.ids = ids
    idx.classes = classes
    idx.tags = tags
    idx.head = head
    idx.tail = tail
    idx.next = next
    var at = 0usize
    while at < rules.len {
        next[at] = END
        if (rules[at].pseudo >= 0i64) != pseudo {
            at += 1usize
            continue
        }
        let sel = rules[at].selector
        var kind = 0u8
        var key = ""
        if sel.compounds.len > 0usize {
            let parts = sel.compounds[sel.compounds.len - 1usize].parts
            var id_name = ""
            var class_name = ""
            var tag_name = ""
            var have_id = false
            var have_class = false
            var have_tag = false
            var p = 0usize
            while p < parts.len {
                if parts[p].kind == .Id && !have_id {
                    have_id = true
                    id_name = parts[p].name
                }
                if parts[p].kind == .Klass && !have_class {
                    have_class = true
                    class_name = parts[p].name
                }
                if parts[p].kind == .Type && !have_tag {
                    have_tag = true
                    tag_name = parts[p].name
                }
                p += 1usize
            }
            if have_id {
                kind = 1u8
                key = id_name
            } else if have_class {
                kind = 2u8
                key = class_name
            } else if have_tag {
                kind = 3u8
                key = tag_name
            }
        }
        if kind == 1u8 { chain_add(&idx.ids, &idx, key, at) } else if kind == 2u8 { chain_add(&idx.classes, &idx, key, at) } else if kind == 3u8 { chain_add(&idx.tags, &idx, key, at) } else {
            if idx.universal_head == END { idx.universal_head = at } else { idx.next[idx.universal_tail] = at }
            idx.universal_tail = at
        }
        at += 1usize
    }
    ret idx
}

fn push_chain(out: *list.List[usize], idx: *const Index, m: *const map.Map[str, usize], key: str) {
    let (slot, found) = map.get[str, usize](m, key)
    if !found { ret }
    var at = idx.head[slot]
    while at != END {
        let pushed = list.push[usize](out, at)
        at = idx.next[at]
    }
}

fn is_blank_byte(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

// Whether `name` is one of the whitespace-separated classes before byte `end`.
fn class_seen(classes: str, end: usize, name: str) -> bool {
    var start = 0usize
    var i = 0usize
    while i <= end {
        if i == end || is_blank_byte(classes[i]) {
            if i > start && str.eq(classes[start..i], name) { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}
// The indices of the rules an element could match, in the order the resolver visits them.
fn candidates(m: *const match.Matcher, idx: *const Index, el: html.NodeId) -> []const usize {
    let (made, e) = list.init[usize](m.a, 8usize)
    if e != ok { ret zero }
    var out = made
    let element_id = match.element_id(m, el)
    if element_id.len > 0usize { push_chain(&out, idx, &idx.ids, element_id) }
    let (classes, have_classes) = match.attr(m, el, "class")
    if have_classes {
        var start = 0usize
        var i = 0usize
        while i <= classes.len {
            if i == classes.len || is_blank_byte(classes[i]) {
                if i > start {
                    let name = classes[start..i]
                    let seen = class_seen(classes, start, name)
                    if !seen { push_chain(&out, idx, &idx.classes, name) }
                }
                start = i + 1usize
            }
            i += 1usize
        }
    }
    let tag = match.local_name(m, el)
    if tag.len > 0usize { push_chain(&out, idx, &idx.tags, tag) }
    var u = idx.universal_head
    while u != END {
        let pushed = list.push[usize](&out, u)
        u = idx.next[u]
    }
    ret list.slice_const[usize](&out)
}

// --- @container ------------------------------------------------------------------------------------------------------

fn names_contain(names: []const str, name: str) -> bool {
    var at = 0usize
    while at < names.len {
        if str.eq(names[at], name) { ret true }
        at += 1usize
    }
    ret false
}

fn containers_match(stack: []const ContainerBox, queries: []const ContainerQuery) -> bool {
    var q = 0usize
    while q < queries.len {
        let query = queries[q]
        var found = false
        var box: ContainerBox = zero
        var i = stack.len
        while i > 0usize && !found {
            i -= 1usize
            let c = stack[i]
            if query.has_name && !names_contain(c.names, query.name) { continue }
            if c.kind == .InlineSize && container.uses_block_axis(query.condition) { continue }
            found = true
            box = c
        }
        if !found { ret false }
        let size = container.Size { has_width: box.has_width, width: box.width, has_height: box.has_height, height: box.height }
        if !container.matches(query.condition, size) { ret false }
        q += 1usize
    }
    ret true
}

// --- @scope ----------------------------------------------------------------------------------------------------------

fn scoped(m: *const match.Matcher, root: html.NodeId) -> match.Matcher {
    var st = m.state
    st.has_scope = true
    st.scope = root
    ret match.new_matcher(m.a, m.doc, st)
}

fn unscoped(m: *const match.Matcher) -> match.Matcher {
    var st = m.state
    st.has_scope = false
    st.scope = html.NONE
    ret match.new_matcher(m.a, m.doc, st)
}

fn any_matches(m: *const match.Matcher, sels: []const selector.Selector, el: html.NodeId) -> bool {
    var at = 0usize
    while at < sels.len {
        if match.selector_matches(m, sels[at], el) { ret true }
        at += 1usize
    }
    ret false
}

// True when `el` lies in the donut of `scope` rooted at `root`: no limit sits on the path from `el` up to, not including,
// the root.
fn inside_limits(m: *const match.Matcher, sc: Scope, root: html.NodeId, el: html.NodeId) -> bool {
    if sc.limits.len == 0usize { ret true }
    let rooted = scoped(m, root)
    var n = el
    while n != html.NONE && n != root {
        if any_matches(&rooted, sc.limits, n) { ret false }
        n = match.parent_element(m, n)
    }
    ret true
}

// The nearest scoping root of `sc` that has `el` in scope and the hops up to it.
fn find_scope_root(m: *const match.Matcher, sc: Scope, el: html.NodeId) -> (html.NodeId, i64, bool) {
    let bare = unscoped(m)
    if sc.starts.len == 0usize {
        var root = el
        var hops = 0i64
        while match.parent_element(m, root) != html.NONE {
            root = match.parent_element(m, root)
            hops += 1i64
        }
        if inside_limits(m, sc, root, el) { ret (root, hops, true) }
        ret (html.NONE, 0i64, false)
    }
    var hops = 0i64
    var r = el
    while r != html.NONE {
        if any_matches(&bare, sc.starts, r) && inside_limits(m, sc, r, el) { ret (r, hops, true) }
        r = match.parent_element(m, r)
        hops += 1i64
    }
    ret (html.NONE, 0i64, false)
}

// Whether `el` is in every enclosing scope and `sel` matches it with `:scope` bound to the innermost root; the proximity
// is the hops to that root.
fn scope_proximity(m: *const match.Matcher, scopes: []const Scope, sel: selector.Selector, el: html.NodeId) -> (i64, bool) {
    var root = html.NONE
    var proximity = 0i64
    var at = 0usize
    while at < scopes.len {
        let (found, hops, ok_root) = find_scope_root(m, scopes[at], el)
        if !ok_root { ret (0i64, false) }
        root = found
        proximity = hops
        at += 1usize
    }
    let rooted = scoped(m, root)
    if match.selector_matches(&rooted, sel, el) { ret (proximity, true) }
    ret (0i64, false)
}

// --- presentational hints --------------------------------------------------------------------------------------------

fn hint(property: str, value: str) -> Declaration {
    ret Declaration { property: property, value: value, important: false }
}

fn trimmed_attr(m: *const match.Matcher, el: html.NodeId, name: str) -> (str, bool) {
    let (v, found) = match.attr(m, el, name)
    if !found { ret ("", false) }
    let t = str.trim(v)
    if t.len == 0usize { ret ("", false) }
    ret (t, true)
}

// Dart's int.tryParse over plain decimal text: an optional sign and one or more digits.
fn try_int(s: str) -> (i64, bool) {
    if s.len == 0usize || s.len > 18usize { ret (0i64, false) }
    var at = 0usize
    var negative = false
    if s[0] == 43u8 || s[0] == 45u8 {
        negative = s[0] == 45u8
        at = 1usize
    }
    if at == s.len { ret (0i64, false) }
    var v = 0i64
    while at < s.len {
        if s[at] < 48u8 || s[at] > 57u8 { ret (0i64, false) }
        v = v * 10i64 + i64(s[at] - 48u8)
        at += 1usize
    }
    if negative { ret (0i64 - v, true) }
    ret (v, true)
}

fn int_text(a: *mem.Arena, v: i64) -> str {
    let (made, e) = str.builder(a, 24usize)
    if e != ok { ret "" }
    var b = made
    let pushed = str.push_i64(&b, v)
    ret str.done(&b)
}

fn join3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    let (xy, e1) = str.concat(a, x, y)
    if e1 != ok { ret "" }
    let (all, e2) = str.concat(a, xy, z)
    if e2 != ok { ret "" }
    ret all
}

// A presentational length: a bare number is px (written the way Dart prints a double), a percentage passes through.
fn length_hint(a: *mem.Arena, v: str) -> str {
    let t = str.trim(v)
    if str.ends_with(t, "%") { ret t }
    let (n, e) = str.parse_f64(t)
    if e != ok { ret t }
    let (made, be) = str.builder(a, 40usize)
    if be != ok { ret t }
    var b = made
    let pushed = str.push_f64(&b, n)
    let shown = str.done(&b)
    if str.contains(shown, ".") || str.contains(shown, "e") { ret join3(a, shown, "px", "") }
    ret join3(a, shown, ".0px", "")
}

fn legacy_font_size(s: str) -> (str, bool) {
    let t = str.trim(s)
    let (n, good) = try_int(t)
    if !good { ret ("", false) }
    var idx = n
    if t[0] == 43u8 || t[0] == 45u8 { idx = 3i64 + n }
    if idx < 1i64 { idx = 1i64 }
    if idx > 7i64 { idx = 7i64 }
    if idx == 1i64 { ret ("10px", true) }
    if idx == 2i64 { ret ("13px", true) }
    if idx == 3i64 { ret ("16px", true) }
    if idx == 4i64 { ret ("18px", true) }
    if idx == 5i64 { ret ("24px", true) }
    if idx == 6i64 { ret ("32px", true) }
    ret ("48px", true)
}

fn one_of(name: str, a: str, b: str, c: str, d: str, e: str, f: str, g: str, h: str) -> bool {
    ret str.eq(name, a) || str.eq(name, b) || str.eq(name, c) || str.eq(name, d) || str.eq(name, e) || str.eq(name, f) || str.eq(name, g) || str.eq(name, h)
}

fn ancestor_named(m: *const match.Matcher, el: html.NodeId, name: str) -> html.NodeId {
    var p = match.parent_element(m, el)
    while p != html.NONE && !str.eq(match.lower(m.a, match.local_name(m, p)), name) {
        p = match.parent_element(m, p)
    }
    ret p
}

fn push_hint(out: *list.List[Declaration], property: str, value: str) {
    let pushed = list.push[Declaration](out, hint(property, value))
}

fn presentational_hints(m: *const match.Matcher, el: html.NodeId) -> []const Declaration {
    let a = m.a
    let (made, e) = list.init[Declaration](a, 8usize)
    if e != ok { ret zero }
    var out = made
    let tag = match.lower(a, match.local_name(m, el))
    if tag.len == 0usize { ret zero }
    let (dir_raw, have_dir) = trimmed_attr(m, el, "dir")
    if have_dir {
        let dir = match.lower(a, dir_raw)
        if str.eq(dir, "rtl") || str.eq(dir, "ltr") { push_hint(&out, "direction", dir) }
    }
    if one_of(tag, "body", "table", "tr", "td", "th", "thead", "tbody", "tfoot") {
        let (bg, have_bg) = trimmed_attr(m, el, "bgcolor")
        if have_bg { push_hint(&out, "background-color", bg) }
    }
    if str.eq(tag, "body") || str.eq(tag, "font") {
        let (c, have_c) = trimmed_attr(m, el, "color")
        if have_c {
            push_hint(&out, "color", c)
        } else {
            let (t, have_t) = trimmed_attr(m, el, "text")
            if have_t { push_hint(&out, "color", t) }
        }
    }
    if str.eq(tag, "a") && match.has_attr(m, el, "href") {
        let body = ancestor_named(m, el, "body")
        if body != html.NONE {
            let (link, have_link) = match.attr(m, body, "link")
            let l = str.trim(link)
            if have_link && l.len > 0usize { push_hint(&out, "color", l) }
        }
    }
    if str.eq(tag, "font") {
        let (face, have_face) = trimmed_attr(m, el, "face")
        if have_face { push_hint(&out, "font-family", face) }
        let (size, have_size) = trimmed_attr(m, el, "size")
        if have_size {
            let (px, good) = legacy_font_size(size)
            if good { push_hint(&out, "font-size", px) }
        }
    }
    if one_of(tag, "table", "td", "th", "img", "col", "colgroup", "hr", "canvas") || one_of(tag, "object", "svg", "iframe", "embed", "", "", "", "") {
        let (w, have_w) = trimmed_attr(m, el, "width")
        if have_w { push_hint(&out, "width", length_hint(a, w)) }
        let (h, have_h) = trimmed_attr(m, el, "height")
        if have_h { push_hint(&out, "height", length_hint(a, h)) }
    }
    if str.eq(tag, "hr") {
        let (sz, have_sz) = trimmed_attr(m, el, "size")
        if have_sz { push_hint(&out, "height", length_hint(a, sz)) }
    }
    if str.eq(tag, "img") {
        let (b, have_b) = trimmed_attr(m, el, "border")
        if have_b {
            let (bn, good) = try_int(b)
            if good && bn > 0i64 { push_hint(&out, "border", join3(a, int_text(a, bn), "px solid gray", "")) }
        }
        let (al, have_al) = trimmed_attr(m, el, "align")
        if have_al {
            let align = match.lower(a, al)
            if str.eq(align, "left") { push_hint(&out, "float", "left") }
            if str.eq(align, "right") { push_hint(&out, "float", "right") }
            if str.eq(align, "top") || str.eq(align, "texttop") { push_hint(&out, "vertical-align", "top") }
            if str.eq(align, "middle") || str.eq(align, "absmiddle") { push_hint(&out, "vertical-align", "middle") }
            if str.eq(align, "bottom") || str.eq(align, "absbottom") { push_hint(&out, "vertical-align", "bottom") }
        }
    }
    if (str.eq(tag, "td") || str.eq(tag, "th")) && match.has_attr(m, el, "nowrap") {
        push_hint(&out, "white-space", "nowrap")
    }
    if str.eq(tag, "td") || str.eq(tag, "th") || str.eq(tag, "tr") {
        let (v, have_v) = trimmed_attr(m, el, "valign")
        if have_v {
            let va = match.lower(a, v)
            if str.eq(va, "top") || str.eq(va, "middle") || str.eq(va, "bottom") { push_hint(&out, "vertical-align", va) }
        }
    }
    if one_of(tag, "td", "th", "tr", "p", "div", "caption", "col", "") {
        let (al, have_al) = trimmed_attr(m, el, "align")
        if have_al {
            let align = match.lower(a, al)
            if str.eq(align, "left") || str.eq(align, "right") || str.eq(align, "center") || str.eq(align, "justify") {
                let table_internal = one_of(tag, "td", "th", "tr", "caption", "col", "", "", "")
                if str.eq(align, "center") && !table_internal {
                    push_hint(&out, "text-align", "-webkit-center")
                } else {
                    push_hint(&out, "text-align", align)
                }
            }
        }
    }
    if str.eq(tag, "table") {
        let (al, have_al) = trimmed_attr(m, el, "align")
        if have_al {
            let align = match.lower(a, al)
            if str.eq(align, "center") {
                push_hint(&out, "margin-left", "auto")
                push_hint(&out, "margin-right", "auto")
            }
            if str.eq(align, "left") { push_hint(&out, "float", "left") }
            if str.eq(align, "right") { push_hint(&out, "float", "right") }
        }
        let (csraw, have_cs) = match.attr(m, el, "cellspacing")
        if have_cs {
            let (cs, good) = try_int(str.trim(csraw))
            if good && cs >= 0i64 { push_hint(&out, "border-spacing", join3(a, int_text(a, cs), "px", "")) }
        }
        let (braw, have_b) = match.attr(m, el, "border")
        let bv = str.trim(braw)
        if have_b && !str.eq(bv, "0") {
            var n = 1i64
            let (parsed, good) = try_int(bv)
            if good { n = parsed }
            if n > 0i64 { push_hint(&out, "border", join3(a, int_text(a, n), "px solid gray", "")) }
        }
    }
    if str.eq(tag, "td") || str.eq(tag, "th") {
        let table = ancestor_named(m, el, "table")
        if table != html.NONE {
            let (tbraw, have_tb) = match.attr(m, table, "border")
            let tb = str.trim(tbraw)
            if have_tb && !str.eq(tb, "0") { push_hint(&out, "border", "1px solid gray") }
            let (cpraw, have_cp) = match.attr(m, table, "cellpadding")
            if have_cp {
                let (cp, good) = try_int(str.trim(cpraw))
                if good && cp >= 0i64 { push_hint(&out, "padding", join3(a, int_text(a, cp), "px", "")) }
            }
        }
    }
    if str.eq(tag, "ol") || str.eq(tag, "li") {
        let (tv, have_t) = trimmed_attr(m, el, "type")
        if have_t {
            if str.eq(tv, "1") { push_hint(&out, "list-style-type", "decimal") }
            if str.eq(tv, "a") { push_hint(&out, "list-style-type", "lower-alpha") }
            if str.eq(tv, "A") { push_hint(&out, "list-style-type", "upper-alpha") }
            if str.eq(tv, "i") { push_hint(&out, "list-style-type", "lower-roman") }
            if str.eq(tv, "I") { push_hint(&out, "list-style-type", "upper-roman") }
        }
    }
    ret list.slice_const[Declaration](&out)
}

// --- the cascade -----------------------------------------------------------------------------------------------------

// The declarations of a `style` attribute: a property name lowercased (a custom property keeps its case), its value text
// trimmed, and a declaration with an empty name or value dropped.
fn inline_declarations(a: *mem.Arena, source: str) -> []const Declaration {
    if str.trim(source).len == 0usize { ret zero }
    let (tokens, te) = syntax.tokenize(a, source)
    if te != ok { ret zero }
    let (parsed, pe) = syntax.parse_declarations(a, tokens)
    if pe != ok { ret zero }
    let (made, e) = list.init[Declaration](a, parsed.len + 1usize)
    if e != ok { ret zero }
    var out = made
    var at = 0usize
    while at < parsed.len {
        var name = parsed[at].name
        if !str.starts_with(name, "--") { name = match.lower(a, name) }
        let value = str.trim(syntax.raw_text(source, parsed[at].value))
        if name.len > 0usize && value.len > 0usize {
            let pushed = list.push[Declaration](&out, Declaration { property: name, value: value, important: parsed[at].important })
        }
        at += 1usize
    }
    ret list.slice_const[Declaration](&out)
}

fn collect(m: *const match.Matcher, out: *list.List[Declared], rules: []const Rule, author: bool, el: html.NodeId, stack: []const ContainerBox) {
    let idx = build_index(m.a, rules, false)
    let visit = candidates(m, &idx, el)
    var v = 0usize
    while v < visit.len {
        let rule = rules[visit[v]]
        v += 1usize
        if !containers_match(stack, rule.containers) { continue }
        var proximity = UNSCOPED
        if rule.scopes.len > 0usize {
            let (p, in_scope) = scope_proximity(m, rule.scopes, rule.selector, el)
            if !in_scope { continue }
            proximity = p
        } else if !match.selector_matches(m, rule.selector, el) {
            continue
        }
        let spec = selector.ordinal(selector.specificity(rule.selector))
        var d = 0usize
        while d < rule.declarations.len {
            let pushed = list.push[Declared](out, Declared { declaration: rule.declarations[d], author: author, hint: false, specificity: spec, source: rule.source, has_layer: rule.has_layer, layer: rule.layer, proximity: proximity })
            d += 1usize
        }
    }
}

// The winning declaration of every property for `el`: hints, user-agent rules, author rules, then `inline` (the parsed
// `style` attribute, which outranks any selector and ranks by position).
fn resolve(m: *const match.Matcher, ua: []const Rule, author: []const Rule, el: html.NodeId, stack: []const ContainerBox, inline: []const Declaration) -> []const Winner {
    let (made, e) = list.init[Declared](m.a, 16usize)
    if e != ok { ret zero }
    var declared = made
    let hints = presentational_hints(m, el)
    var h = 0usize
    while h < hints.len {
        let pushed = list.push[Declared](&declared, Declared { declaration: hints[h], author: false, hint: true, specificity: 0i64, source: -1i64, has_layer: false, layer: 0i64, proximity: UNSCOPED })
        h += 1usize
    }
    collect(m, &declared, ua, false, el, stack)
    collect(m, &declared, author, true, el, stack)
    var i = 0usize
    while i < inline.len {
        let pushed = list.push[Declared](&declared, Declared { declaration: inline[i], author: true, hint: false, specificity: INLINE_SPECIFICITY, source: i64(i), has_layer: false, layer: 0i64, proximity: UNSCOPED })
        i += 1usize
    }
    ret rank(m.a, list.slice_const[Declared](&declared))
}
