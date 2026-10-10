// Selector matching over an HTML document (L040), after Vaper's `css/selector_matcher.dart`: a parsed selector
// (`e.fmt.css.selector`) tested against an element of an `e.fmt.html` document by walking its combinators right to left
// from the key compound -- child, descendant, adjacent sibling, general sibling -- with the simple selectors, the
// structural pseudo-classes, `:not()`, `:is()`, `:where()`, `:has()` with its relative lookahead, `:nth-*()` with An+B
// and `of S`, the attribute operators with the `i` flag, and the state and form pseudo-classes (`:hover`, `:focus`,
// `:checked`, `:disabled`, `:required`, `:in-range`, `:valid`, ...).
//
// State pseudo-classes read a `State` the host installs (the hovered, focused and active elements and the set a
// `:focus-within` covers); `:scope` matches the scoping root of an `@scope` block when one is given. Pseudo-classes the
// engine has no state for (`:visited`, `:target`, ...) are valid and never match. Form validity is the constraint
// validation of required, pattern, type (email, url, number, range), min and max and length.
//
// A selector argument the parser could not read (an empty sub-selector list) falls back to the raw argument text, as in
// the original: `:not()` with nothing parsed matches everything, `:is()` nothing.

use e.fmt.css.selector as selector
use e.fmt.html as html
use e.mem
use e.str
use e.text.regex as regex

type State = struct { has_hover: bool, hover: html.NodeId, has_focus: bool, focus: html.NodeId, has_active: bool, active: html.NodeId, focus_within: []const html.NodeId, has_scope: bool, scope: html.NodeId }

type Matcher = struct { a: *mem.Arena, doc: *const html.Document, state: State }

fn no_state() -> State {
    ret State { has_hover: false, hover: html.NONE, has_focus: false, focus: html.NONE, has_active: false, active: html.NONE, focus_within: zero, has_scope: false, scope: html.NONE }
}

fn new_matcher(a: *mem.Arena, doc: *const html.Document, state: State) -> Matcher {
    ret Matcher { a: a, doc: doc, state: state }
}

// --- the tree -------------------------------------------------------------------------------------------------------

fn node_of(m: *const Matcher, id: html.NodeId) -> *const html.Node {
    ret &m.doc.nodes[usize(id)]
}

fn is_element(m: *const Matcher, id: html.NodeId) -> bool {
    if id == html.NONE { ret false }
    ret m.doc.nodes[usize(id)].kind == .Element
}

// The parent element, none for the root element (whose parent is the document).
fn parent_element(m: *const Matcher, id: html.NodeId) -> html.NodeId {
    let p = m.doc.nodes[usize(id)].parent
    if p == html.NONE || m.doc.nodes[usize(p)].kind != .Element { ret html.NONE }
    ret p
}

fn next_element(m: *const Matcher, from: html.NodeId) -> html.NodeId {
    var n = from
    while n != html.NONE {
        if m.doc.nodes[usize(n)].kind == .Element { ret n }
        n = m.doc.nodes[usize(n)].next_sibling
    }
    ret html.NONE
}

fn first_child_element(m: *const Matcher, id: html.NodeId) -> html.NodeId {
    ret next_element(m, m.doc.nodes[usize(id)].first_child)
}

fn next_sibling_element(m: *const Matcher, id: html.NodeId) -> html.NodeId {
    ret next_element(m, m.doc.nodes[usize(id)].next_sibling)
}

fn prev_element(m: *const Matcher, from: html.NodeId) -> html.NodeId {
    var n = from
    while n != html.NONE {
        if m.doc.nodes[usize(n)].kind == .Element { ret n }
        n = m.doc.nodes[usize(n)].previous_sibling
    }
    ret html.NONE
}

fn prev_sibling_element(m: *const Matcher, id: html.NodeId) -> html.NodeId {
    ret prev_element(m, m.doc.nodes[usize(id)].previous_sibling)
}

fn attr(m: *const Matcher, id: html.NodeId, name: str) -> (str, bool) {
    let (v, found) = html.attribute(&m.doc.nodes[usize(id)], name)
    ret (v, found)
}

fn has_attr(m: *const Matcher, id: html.NodeId, name: str) -> bool {
    let (v, found) = attr(m, id, name)
    ret found
}

fn local_name(m: *const Matcher, id: html.NodeId) -> str { ret m.doc.nodes[usize(id)].name }

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

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn trim(s: str) -> str {
    var start = 0usize
    var end = s.len
    while start < end && is_space(s[start]) { start += 1usize }
    while end > start && is_space(s[end - 1usize]) { end -= 1usize }
    ret s[start..end]
}

fn class_contains(m: *const Matcher, id: html.NodeId, name: str) -> bool {
    let (value, found) = attr(m, id, "class")
    if !found { ret false }
    var start = 0usize
    var i = 0usize
    while i <= value.len {
        if i == value.len || is_space(value[i]) {
            if i > start && str.eq(value[start..i], name) { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

fn element_id(m: *const Matcher, id: html.NodeId) -> str {
    let (value, found) = attr(m, id, "id")
    if !found { ret "" }
    ret value
}

fn in_ids(ids: []const html.NodeId, id: html.NodeId) -> bool {
    var at = 0usize
    while at < ids.len {
        if ids[at] == id { ret true }
        at += 1usize
    }
    ret false
}

// --- the combinator walk ---------------------------------------------------------------------------------------------

// Does the complex selector match `el`? The key compound is tested first, then each combinator leftward.
fn selector_matches(m: *const Matcher, sel: selector.Selector, el: html.NodeId) -> bool {
    if sel.compounds.len == 0usize { ret false }
    if !matches_compound(m, sel.compounds[sel.compounds.len - 1usize], el) { ret false }
    var current = el
    var i = i64(sel.combinators.len) - 1i64
    while i >= 0i64 {
        let combinator = sel.combinators[usize(i)]
        let left = sel.compounds[usize(i)]
        switch combinator {
        case .Child:
            let parent = parent_element(m, current)
            if parent == html.NONE || !matches_compound(m, left, parent) { ret false }
            current = parent
        case .Descendant:
            var ancestor = parent_element(m, current)
            while ancestor != html.NONE && !matches_compound(m, left, ancestor) {
                ancestor = parent_element(m, ancestor)
            }
            if ancestor == html.NONE { ret false }
            current = ancestor
        case .AdjacentSibling:
            if parent_element(m, current) == html.NONE { ret false }
            let prev = prev_sibling_element(m, current)
            if prev == html.NONE || !matches_compound(m, left, prev) { ret false }
            current = prev
        case .GeneralSibling:
            if parent_element(m, current) == html.NONE { ret false }
            // the element nearest `current` going backward is the last match the forward walk finds
            var found = html.NONE
            var p = prev_sibling_element(m, current)
            while p != html.NONE && found == html.NONE {
                if matches_compound(m, left, p) { found = p }
                p = prev_sibling_element(m, p)
            }
            if found == html.NONE { ret false }
            current = found
        }
        i -= 1i64
    }
    ret true
}

fn matches_compound(m: *const Matcher, c: selector.Compound, el: html.NodeId) -> bool {
    var at = 0usize
    while at < c.parts.len {
        if !matches_part(m, c.parts[at], el) { ret false }
        at += 1usize
    }
    ret true
}

fn any_sub_matches(m: *const Matcher, subs: []const selector.Selector, el: html.NodeId) -> bool {
    var at = 0usize
    while at < subs.len {
        if selector_matches(m, subs[at], el) { ret true }
        at += 1usize
    }
    ret false
}

fn matches_part(m: *const Matcher, part: selector.Simple, el: html.NodeId) -> bool {
    switch part.kind {
    case .Universal:
        ret true
    case .Type:
        ret str.eq(local_name(m, el), part.name)
    case .Klass:
        ret class_contains(m, el, part.name)
    case .Id:
        ret str.eq(element_id(m, el), part.name)
    case .PseudoClass:
        ret matches_pseudo_class(m, part.name, el)
    case .FirstChild:
        ret is_first_child(m, el)
    case .LastChild:
        ret is_last_child(m, el)
    case .OnlyChild:
        ret is_first_child(m, el) && is_last_child(m, el)
    case .NthChild:
        ret matches_nth_child(m, part, el, false, false)
    case .NthLastChild:
        ret matches_nth_child(m, part, el, true, false)
    case .NthOfType:
        ret matches_nth_child(m, part, el, false, true)
    case .NthLastOfType:
        ret matches_nth_child(m, part, el, true, true)
    case .FirstOfType:
        ret child_index_of_type(m, el) == 1i64
    case .LastOfType:
        ret is_last_of_type(m, el)
    case .OnlyOfType:
        ret child_index_of_type(m, el) == 1i64 && is_last_of_type(m, el)
    case .Empty:
        ret m.doc.nodes[usize(el)].first_child == html.NONE
    case .Root:
        ret parent_element(m, el) == html.NONE
    case .Scope:
        ret false
    case .Not:
        if part.subs.len > 0usize { ret !any_sub_matches(m, part.subs, el) }
        ret !matches_arg_selector(m, el, part.argument)
    case .Is, .Where:
        if part.subs.len > 0usize { ret any_sub_matches(m, part.subs, el) }
        ret matches_arg_selector_list(m, el, part.argument)
    case .Has:
        ret matches_has(m, el, part.subs)
    case .AttrPresent:
        ret has_attr(m, el, part.name)
    case .AttrEquals:
        ret attr_compare(m, el, part, 0u8)
    case .AttrIncludes:
        ret attr_compare(m, el, part, 1u8)
    case .AttrDash:
        ret attr_compare(m, el, part, 2u8)
    case .AttrPrefix:
        ret attr_compare(m, el, part, 3u8)
    case .AttrSuffix:
        ret attr_compare(m, el, part, 4u8)
    case .AttrSubstring:
        ret attr_compare(m, el, part, 5u8)
    }
}

fn includes_word(a: str, b: str) -> bool {
    var start = 0usize
    var i = 0usize
    while i <= a.len {
        if i == a.len || is_space(a[i]) {
            if str.eq(a[start..i], b) { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

fn attr_compare(m: *const Matcher, el: html.NodeId, part: selector.Simple, op: u8) -> bool {
    let (raw, found) = attr(m, el, part.name)
    if !found { ret false }
    var actual = raw
    var expected = part.argument
    if part.attr_ci {
        actual = lower(m.a, actual)
        expected = lower(m.a, expected)
    }
    if op == 0u8 { ret str.eq(actual, expected) }
    if op == 1u8 { ret expected.len > 0usize && includes_word(actual, expected) }
    if op == 2u8 {
        if str.eq(actual, expected) { ret true }
        let dashed = cat2(m.a, expected, "-")
        ret str.starts_with(actual, dashed)
    }
    if op == 3u8 { ret expected.len > 0usize && str.starts_with(actual, expected) }
    if op == 4u8 { ret expected.len > 0usize && str.ends_with(actual, expected) }
    ret expected.len > 0usize && str.contains(actual, expected)
}

// --- structure --------------------------------------------------------------------------------------------------------

fn is_first_child(m: *const Matcher, el: html.NodeId) -> bool {
    if parent_element(m, el) == html.NONE { ret false }
    ret prev_sibling_element(m, el) == html.NONE
}

fn is_last_child(m: *const Matcher, el: html.NodeId) -> bool {
    if parent_element(m, el) == html.NONE { ret false }
    ret next_sibling_element(m, el) == html.NONE
}

// The 1-based index among siblings of the same tag; 1 for the root.
fn child_index_of_type(m: *const Matcher, el: html.NodeId) -> i64 {
    if parent_element(m, el) == html.NONE { ret 1i64 }
    let parent = m.doc.nodes[usize(el)].parent
    var idx = 0i64
    var child = first_child_element(m, parent)
    while child != html.NONE {
        if str.eq(local_name(m, child), local_name(m, el)) {
            idx += 1i64
            if child == el { ret idx }
        }
        child = next_sibling_element(m, child)
    }
    ret 1i64
}

fn is_last_of_type(m: *const Matcher, el: html.NodeId) -> bool {
    if parent_element(m, el) == html.NONE { ret true }
    var sib = next_sibling_element(m, el)
    while sib != html.NONE {
        if str.eq(local_name(m, sib), local_name(m, el)) { ret false }
        sib = next_sibling_element(m, sib)
    }
    ret true
}

fn counts_for_nth(m: *const Matcher, part: selector.Simple, el: html.NodeId, c: html.NodeId, of_type: bool) -> bool {
    if part.subs.len > 0usize { ret any_sub_matches(m, part.subs, c) }
    if of_type { ret str.eq(local_name(m, c), local_name(m, el)) }
    ret true
}

fn matches_nth_child(m: *const Matcher, part: selector.Simple, el: html.NodeId, from_end: bool, of_type: bool) -> bool {
    if parent_element(m, el) == html.NONE { ret matches_nth(m, part.argument, 1i64) }
    if !counts_for_nth(m, part, el, el, of_type) { ret false }
    let parent = m.doc.nodes[usize(el)].parent
    var index = 0i64
    if from_end {
        var c = last_element_child(m, parent)
        while c != html.NONE {
            if counts_for_nth(m, part, el, c, of_type) {
                index += 1i64
                if c == el { ret matches_nth(m, part.argument, index) }
            }
            c = prev_sibling_element(m, c)
        }
    } else {
        var c = first_child_element(m, parent)
        while c != html.NONE {
            if counts_for_nth(m, part, el, c, of_type) {
                index += 1i64
                if c == el { ret matches_nth(m, part.argument, index) }
            }
            c = next_sibling_element(m, c)
        }
    }
    ret false
}

fn last_element_child(m: *const Matcher, id: html.NodeId) -> html.NodeId {
    ret prev_element(m, m.doc.nodes[usize(id)].last_child)
}

// Dart's `int.tryParse`: an optional sign and decimal digits.
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

// `An+B`, `odd`, `even` or a plain integer, against a 1-based index.
fn matches_nth(m: *const Matcher, arg: str, index: i64) -> bool {
    let s = lower(m.a, trim(arg))
    if str.eq(s, "odd") { ret index % 2i64 == 1i64 }
    if str.eq(s, "even") { ret index % 2i64 == 0i64 }
    let (plain, is_plain) = int_of(s)
    if is_plain { ret index == plain }
    // ^([+-]?\d*)?n\s*([+-]\s*\d+)?$
    var at = 0usize
    if at < s.len && (s[at] == 43u8 || s[at] == 45u8) { at += 1usize }
    while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 { at += 1usize }
    let a_part = s[0usize..at]
    if at >= s.len || s[at] != 110u8 { ret false }
    at += 1usize
    while at < s.len && is_space(s[at]) { at += 1usize }
    var b_text = ""
    if at < s.len {
        if s[at] != 43u8 && s[at] != 45u8 { ret false }
        let sign_at = at
        at += 1usize
        while at < s.len && is_space(s[at]) { at += 1usize }
        let digits_start = at
        while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 { at += 1usize }
        if at == digits_start || at != s.len { ret false }
        b_text = cat2(m.a, s[sign_at..sign_at + 1usize], s[digits_start..at])
    }
    var a = 1i64
    if str.eq(a_part, "") || str.eq(a_part, "+") {
        a = 1i64
    } else if str.eq(a_part, "-") {
        a = -1i64
    } else {
        let (v, good) = int_of(a_part)
        if good { a = v } else { a = 1i64 }
    }
    var b = 0i64
    let (bv, b_ok) = int_of(b_text)
    if b_ok { b = bv }
    if a == 0i64 { ret index == b }
    let rem = index - b
    if a > 0i64 { ret rem >= 0i64 && rem % a == 0i64 }
    ret rem <= 0i64 && rem % a == 0i64
}

fn cat2(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

// --- the legacy argument fallback ----------------------------------------------------------------------------------------

fn matches_arg_selector(m: *const Matcher, el: html.NodeId, arg: str) -> bool {
    let s = trim(arg)
    if s.len == 0usize { ret false }
    if s[0] == 46u8 { ret class_contains(m, el, s[1usize..]) }
    if s[0] == 35u8 { ret str.eq(element_id(m, el), s[1usize..]) }
    if str.eq(s, "*") { ret true }
    if s[0] != 58u8 && s[0] != 91u8 { ret str.eq(local_name(m, el), lower(m.a, s)) }
    ret false
}

fn matches_arg_selector_list(m: *const Matcher, el: html.NodeId, arg: str) -> bool {
    var start = 0usize
    var i = 0usize
    while i <= arg.len {
        if i == arg.len || arg[i] == 44u8 {
            if matches_arg_selector(m, el, trim(arg[start..i])) { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

// --- :has() -------------------------------------------------------------------------------------------------------------

fn matches_in_subtree(m: *const Matcher, sel: selector.Selector, root: html.NodeId) -> bool {
    if selector_matches(m, sel, root) { ret true }
    var child = first_child_element(m, root)
    while child != html.NONE {
        if matches_in_subtree(m, sel, child) { ret true }
        child = next_sibling_element(m, child)
    }
    ret false
}

// A candidate satisfies the tail: itself for a single compound, anything in its subtree for a longer one.
fn candidate_matches(m: *const Matcher, tail: selector.Selector, candidate: html.NodeId) -> bool {
    if tail.compounds.len == 1usize { ret selector_matches(m, tail, candidate) }
    ret matches_in_subtree(m, tail, candidate)
}

fn matches_has(m: *const Matcher, el: html.NodeId, relatives: []const selector.Selector) -> bool {
    var r = 0usize
    while r < relatives.len {
        let rel = relatives[r]
        if rel.compounds.len >= 2usize && rel.combinators.len >= 1usize {
            let lead = rel.combinators[0]
            let tail = selector.Selector { compounds: rel.compounds[1usize..], combinators: rel.combinators[1usize..] }
            switch lead {
            case .Descendant:
                if has_in_descendants(m, el, tail) { ret true }
            case .Child:
                var c = first_child_element(m, el)
                while c != html.NONE {
                    if candidate_matches(m, tail, c) { ret true }
                    c = next_sibling_element(m, c)
                }
            case .AdjacentSibling:
                let next = next_sibling_element(m, el)
                if next != html.NONE && parent_element(m, el) != html.NONE && candidate_matches(m, tail, next) { ret true }
            case .GeneralSibling:
                if parent_element(m, el) != html.NONE {
                    var s = next_sibling_element(m, el)
                    while s != html.NONE {
                        if candidate_matches(m, tail, s) { ret true }
                        s = next_sibling_element(m, s)
                    }
                }
            }
        }
        r += 1usize
    }
    ret false
}

// The descendants in document order: each child, then that child's descendants.
fn has_in_descendants(m: *const Matcher, el: html.NodeId, tail: selector.Selector) -> bool {
    var c = first_child_element(m, el)
    while c != html.NONE {
        if candidate_matches(m, tail, c) { ret true }
        if has_in_descendants(m, c, tail) { ret true }
        c = next_sibling_element(m, c)
    }
    ret false
}

// --- pseudo-classes ------------------------------------------------------------------------------------------------------

fn is_formish(name: str) -> bool {
    ret str.eq(name, "input") || str.eq(name, "button") || str.eq(name, "select") || str.eq(name, "textarea") || str.eq(name, "option") || str.eq(name, "optgroup") || str.eq(name, "fieldset")
}

fn input_type(m: *const Matcher, el: html.NodeId) -> str {
    let (t, found) = attr(m, el, "type")
    if !found { ret "text" }
    ret lower(m.a, t)
}

// Dart's `double.tryParse` over what an attribute holds: an optional sign, digits, a point, an exponent.
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
        exp = cat2(a, cat2(a, "e", sign), t[e0..j])
        at = j
    }
    if at != t.len { ret (0.0f64, false) }
    var body = int_digits
    if body.len == 0usize { body = "0" }
    text = cat2(a, text, body)
    if frac.len > 0usize { text = cat2(a, cat2(a, text, "."), frac) }
    text = cat2(a, text, exp)
    let (v, e) = str.parse_f64(text)
    if e != ok { ret (0.0f64, false) }
    ret (v, true)
}

fn attr_number(m: *const Matcher, el: html.NodeId, name: str) -> (f64, bool) {
    let (raw, found) = attr(m, el, name)
    if !found { ret (0.0f64, false) }
    let (v, good) = number_of(m.a, raw)
    ret (v, good)
}

// Whether the control takes part in constraint validation.
fn control_is_validatable(m: *const Matcher, el: html.NodeId) -> bool {
    let name = local_name(m, el)
    if !str.eq(name, "input") && !str.eq(name, "select") && !str.eq(name, "textarea") { ret false }
    if has_attr(m, el, "disabled") || has_attr(m, el, "readonly") { ret false }
    if str.eq(name, "input") {
        let t = input_type(m, el)
        if str.eq(t, "hidden") || str.eq(t, "button") || str.eq(t, "submit") || str.eq(t, "reset") || str.eq(t, "image") { ret false }
    }
    ret true
}

fn email_ok(value: str) -> bool {
    var at_count = 0usize
    var at_pos = 0usize
    var i = 0usize
    while i < value.len {
        if is_space(value[i]) { ret false }
        if value[i] == 64u8 {
            at_count += 1usize
            at_pos = i
        }
        i += 1usize
    }
    if at_count != 1usize || at_pos == 0usize { ret false }
    let domain = value[at_pos + 1usize..]
    var p = 1usize
    while p + 1usize < domain.len {
        if domain[p] == 46u8 { ret true }
        p += 1usize
    }
    ret false
}

fn url_ok(value: str) -> bool {
    if str.contains(value, "#") { ret false }
    var i = 0usize
    while i < value.len && value[i] != 58u8 {
        let c = value[i]
        let alpha = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
        let more = alpha || (c >= 48u8 && c <= 57u8) || c == 43u8 || c == 45u8 || c == 46u8
        if i == 0usize && !alpha { ret false }
        if !more { ret false }
        i += 1usize
    }
    ret i > 0usize && i < value.len
}

// Is the control's current value invalid under its constraints?
fn control_invalid(m: *const Matcher, el: html.NodeId) -> bool {
    var value = ""
    let (v, have_value) = attr(m, el, "value")
    if have_value { value = v }
    if has_attr(m, el, "required") && value.len == 0usize { ret true }
    if value.len == 0usize { ret false }
    let (pattern, have_pattern) = attr(m, el, "pattern")
    if have_pattern && pattern.len > 0usize {
        let source = cat2(m.a, cat2(m.a, "^(?:", pattern), ")$")
        let (re, re_error) = regex.compile(m.a, source, regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: false })
        if re_error == ok {
            if !regex.is_match(&re, value) { ret true }
        }
    }
    let t = input_type(m, el)
    if str.eq(t, "email") {
        if !email_ok(value) { ret true }
    } else if str.eq(t, "url") {
        if !url_ok(value) { ret true }
    } else if str.eq(t, "number") || str.eq(t, "range") {
        let (n, n_ok) = number_of(m.a, value)
        if !n_ok { ret true }
        let (mn, have_mn) = attr_number(m, el, "min")
        let (mx, have_mx) = attr_number(m, el, "max")
        if have_mn && n < mn { ret true }
        if have_mx && n > mx { ret true }
    }
    let (max_len_text, have_max_len) = attr(m, el, "maxlength")
    if have_max_len {
        let (max_len, ok_len) = int_of(max_len_text)
        if ok_len && i64(value.len) > max_len { ret true }
    }
    let (min_len_text, have_min_len) = attr(m, el, "minlength")
    if have_min_len {
        let (min_len, ok_len) = int_of(min_len_text)
        if ok_len && i64(value.len) < min_len { ret true }
    }
    ret false
}

fn matches_pseudo_class(m: *const Matcher, pseudo: str, el: html.NodeId) -> bool {
    let name = local_name(m, el)
    if str.eq(pseudo, "scope") { ret m.state.has_scope && m.state.scope == el }
    if str.eq(pseudo, "hover") { ret m.state.has_hover && m.state.hover == el }
    if str.eq(pseudo, "focus") || str.eq(pseudo, "focus-visible") { ret m.state.has_focus && m.state.focus == el }
    if str.eq(pseudo, "focus-within") { ret in_ids(m.state.focus_within, el) }
    if str.eq(pseudo, "active") { ret m.state.has_active && m.state.active == el }
    if str.eq(pseudo, "disabled") { ret has_attr(m, el, "disabled") }
    if str.eq(pseudo, "enabled") { ret is_formish(name) && !has_attr(m, el, "disabled") }
    if str.eq(pseudo, "checked") || str.eq(pseudo, "default") { ret has_attr(m, el, "checked") || has_attr(m, el, "selected") }
    if str.eq(pseudo, "required") { ret has_attr(m, el, "required") }
    if str.eq(pseudo, "optional") {
        ret (str.eq(name, "input") || str.eq(name, "select") || str.eq(name, "textarea")) && !has_attr(m, el, "required")
    }
    if str.eq(pseudo, "read-only") { ret has_attr(m, el, "readonly") }
    if str.eq(pseudo, "read-write") {
        if str.eq(name, "input") || str.eq(name, "textarea") { ret !has_attr(m, el, "readonly") && !has_attr(m, el, "disabled") }
        let (ce, have_ce) = attr(m, el, "contenteditable")
        ret have_ce && !str.eq(lower(m.a, ce), "false")
    }
    if str.eq(pseudo, "placeholder-shown") {
        if !str.eq(name, "input") && !str.eq(name, "textarea") { ret false }
        let (ph, have_ph) = attr(m, el, "placeholder")
        if !have_ph || ph.len == 0usize { ret false }
        let (val, have_val) = attr(m, el, "value")
        ret !have_val || val.len == 0usize
    }
    if str.eq(pseudo, "in-range") || str.eq(pseudo, "out-of-range") {
        if !str.eq(name, "input") { ret false }
        let t = input_type(m, el)
        if !str.eq(t, "number") && !str.eq(t, "range") { ret false }
        let (v, have_v) = attr_number(m, el, "value")
        if !have_v { ret false }
        let (mn, have_mn) = attr_number(m, el, "min")
        let (mx, have_mx) = attr_number(m, el, "max")
        if !have_mn && !have_mx { ret false }
        let in_range = (!have_mn || v >= mn) && (!have_mx || v <= mx)
        if str.eq(pseudo, "in-range") { ret in_range }
        ret !in_range
    }
    if str.eq(pseudo, "valid") || str.eq(pseudo, "invalid") {
        if !control_is_validatable(m, el) { ret false }
        let invalid = control_invalid(m, el)
        if str.eq(pseudo, "invalid") { ret invalid }
        ret !invalid
    }
    if str.eq(pseudo, "link") || str.eq(pseudo, "any-link") {
        ret (str.eq(name, "a") || str.eq(name, "area") || str.eq(name, "link")) && has_attr(m, el, "href")
    }
    ret false
}
