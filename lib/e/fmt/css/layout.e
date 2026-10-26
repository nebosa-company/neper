// CSS box layout (tracker phase P2), after CSS 2.1 chapters 8 to 11 and the CSS Display, Flexbox, Grid and Tables
// modules: the box tree of a styled `e.fmt.dom` tree and the geometry of every box.
//
// Input: a `Dom`, the `Style` of every node (`e.fmt.css.style`), a `Measure` (text advance and font metrics, the
// intrinsic size of replaced content: the library does not know fonts or images) and the viewport. Output: a `Layout`
// holding `Box`es (a tree of arena indices), the `Line`s and `Frag`ments of every inline formatting context, and the
// document size. All positions are CSS pixels; a box's `x`, `y` are its border box's top left relative to its parent
// box's border box, `w`, `h` its border box size.
//
// What is laid out: block formatting contexts with margin collapsing and clearance, floats, inline formatting contexts
// (line breaking by UAX 14 opportunities, collapsing and preserving white space, `text-align`, `text-indent`,
// `vertical-align`, `line-height`, atomic inlines, `<br>`, `text-overflow: ellipsis` marking), replaced elements,
// list markers, relative, absolute, fixed and sticky positioning, `min`/`max` size constraints, `box-sizing`.
//
// Memory: the arena is retained; every array lives in it.

use e.data.list as list
use e.gfx.cssvalue as cv
use e.fmt.css.style as style
use e.fmt.css.syntax as syntax
use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.str
use e.text.bidi as bidi
use e.text.segment as segment
use e.text.unicode as unicode
use e.text.utf8 as utf8

type FontMetrics = struct { ascent: f64, descent: f64, line_gap: f64, x_height: f64 }

// The intrinsic size of replaced content (`kind` 0: unknown, so a 300x150 box; 1: an image or media with a size and
// maybe a ratio; 2: a form control, whose size the layout derives from its font).
type Intrinsic = struct { kind: u8, has_width: bool, width: f64, has_height: bool, height: f64, ratio: f64 }

// `width` is the raw advance of the text in the style's font (letter and word spacing are added by the layout).
type Measure = struct {
    ctx: *void,
    width: fn(*void, *const style.Style, str) -> f64,
    metrics: fn(*void, *const style.Style) -> FontMetrics,
    intrinsic: fn(*void, html.NodeId, *const style.Style) -> Intrinsic
}

type Inner = enum u8 { Flow, FlowRoot, Flex, Grid, Table, Replaced, Text, Break, Marker, RowGroup, Row, Cell, Caption, ColumnGroup, Column }

const NONE: u32 = 4294967295u32

type Box = struct {
    inner: Inner, inline_level: bool, anonymous: bool, positioned_out: bool,
    node: u32, style: u32,
    parent: u32, first: u32, last: u32, prev: u32, next: u32,
    x: f64, y: f64, w: f64, h: f64,
    margin: [4]f64, border: [4]f64, padding: [4]f64,
    text: str, line_first: u32, line_count: u32,
    baseline: f64, has_baseline: bool,
    overflow_w: f64, overflow_h: f64,
    aux: u32, aux2: u32,
    min_c: f64, max_c: f64, has_c: bool, in_layout: bool, proc: str,
    coll: bool, cbd: [4]f64, cf_first: u32, cf_count: u32
}

// One column's slice of a box that a multicol container breaks: offset from the box's border-box origin, and height.
type ColFrag = struct { dx: f64, dy: f64, h: f64 }

type FragKind = enum u8 { Text, Segment, Atomic, Marker }

// A text run (`Text`), the part of an inline box on one line (`Segment`; `first`/`last` say whether it carries the box's
// start and end edges), a positioned atomic inline (`Atomic`) or a list marker (`Marker`). Coordinates are relative to
// the border box of the box that owns the formatting context.
type Frag = struct { kind: FragKind, box: u32, x: f64, y: f64, w: f64, h: f64, text: str, first: bool, last: bool }

type Line = struct { x: f64, y: f64, w: f64, h: f64, baseline: f64, frag_first: u32, frag_count: u32, overflow_ellipsis: bool }

type Layout = struct {
    a: *mem.Arena, d: *const dom.Dom, styles: []const style.Style, measure: Measure,
    boxes: list.List[Box], lines: list.List[Line], frags: list.List[Frag], anon: list.List[style.Style],
    root: u32, viewport_width: f64, viewport_height: f64, doc_width: f64, doc_height: f64,
    floats: list.List[FloatRec], tables: list.List[TableData],
    counters: list.List[CounterInst], quote_depth: i64, gen_depth: usize,
    orth_fb: f64, vmode: u8, tr1: []style.Style, tr2: []style.Style, grids: list.List[GridGeom], rules: list.List[ColRule],
    sub_c: []const f64, sub_r: []const f64, sub_gc: f64, sub_gr: f64, sub_has_c: bool, sub_has_r: bool, mc_count: usize, mc_rgap: f64, cfrags: list.List[ColFrag]
}

// A column rule: a filled rectangle in the border box of multicol container `box` (see `layout_multicol`).
type ColRule = struct { box: u32, x: f64, y: f64, w: f64, h: f64, color: u32 }

// A float placed in a block formatting context, in the coordinates of the context's root content box.
type FloatRec = struct { box: u32, x: f64, y: f64, w: f64, h: f64, left: bool, root: u32 }

// --- Accessors.

fn st(l: *const Layout, id: u32) -> *const style.Style {
    // Inside an orthogonal flow every style is read in that flow's logical frame (see `transpose_style`).
    if l.vmode == 1u8 && usize(id) < l.tr1.len { ret &l.tr1[usize(id)] }
    if l.vmode == 2u8 && usize(id) < l.tr2.len { ret &l.tr2[usize(id)] }
    if usize(id) < l.styles.len { ret &l.styles[usize(id)] }
    ret &l.anon.items[usize(id) - l.styles.len]
}

fn bx(l: *Layout, id: u32) -> *Box { ret &l.boxes.items[usize(id)] }

fn bstyle(l: *const Layout, id: u32) -> *const style.Style { ret st(l, l.boxes.items[usize(id)].style) }

fn new_box(l: *Layout, inner: Inner, inline_level: bool, anonymous: bool, node: u32, style_id: u32) -> u32 {
    var b: Box = zero
    b.inner = inner
    b.inline_level = inline_level
    b.anonymous = anonymous
    b.node = node
    b.style = style_id
    b.parent = NONE
    b.first = NONE
    b.last = NONE
    b.prev = NONE
    b.next = NONE
    b.line_first = NONE
    let pushed = list.push[Box](&l.boxes, b)
    ret u32(l.boxes.len) - 1u32
}

fn append(l: *Layout, parent: u32, child: u32) {
    let last = l.boxes.items[usize(parent)].last
    l.boxes.items[usize(child)].parent = parent
    l.boxes.items[usize(child)].prev = last
    l.boxes.items[usize(child)].next = NONE
    if last == NONE { l.boxes.items[usize(parent)].first = child } else { l.boxes.items[usize(last)].next = child }
    l.boxes.items[usize(parent)].last = child
}

fn detach(l: *Layout, child: u32) {
    let parent = l.boxes.items[usize(child)].parent
    if parent == NONE { ret }
    let prev = l.boxes.items[usize(child)].prev
    let next = l.boxes.items[usize(child)].next
    if prev == NONE { l.boxes.items[usize(parent)].first = next } else { l.boxes.items[usize(prev)].next = next }
    if next == NONE { l.boxes.items[usize(parent)].last = prev } else { l.boxes.items[usize(next)].prev = prev }
    l.boxes.items[usize(child)].parent = NONE
    l.boxes.items[usize(child)].prev = NONE
    l.boxes.items[usize(child)].next = NONE
}

fn anon_style(l: *Layout, parent_style: u32, display: style.Display) -> u32 {
    var s = style.inherit_from(st(l, parent_style))
    s.display = display
    // The inherited properties without a field of their own pass through.
    let (kept, ke) = list.init[style.Extra](l.a, 4usize)
    if ke == ok {
        var klist = kept
        let pe = st(l, parent_style).extras
        var xi = 0usize
        while xi < pe.len {
            if style.inherited_extra(pe[xi].name) {
                let pushed = list.push[style.Extra](&klist, pe[xi])
            }
            xi += 1usize
        }
        s.extras = list.slice_const[style.Extra](&klist)
    }
    // An anonymous box has no borders: the initial width of `medium` must not become a used width.
    var bi = 0usize
    while bi < 4usize {
        s.border_width[bi] = 0.0f64
        bi += 1usize
    }
    let pushed = list.push[style.Style](&l.anon, s)
    ret u32(l.styles.len) + u32(l.anon.len) - 1u32
}

// --- Box generation.

// --- ::first-letter: the first letter of the first line (with the punctuation around it) becomes an inline box of its own.

fn is_punct(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Pc || k == .Pd || k == .Ps || k == .Pe || k == .Pi || k == .Pf || k == .Po
}

fn is_combining(c: u32) -> bool {
    let k = unicode.category(c)
    ret k == .Mn || k == .Mc || k == .Me
}

// The text box holding the first letter's line of `b`: the first non-blank text of its inline content, looking into
// inline boxes and the first block child. NONE when the first thing is a break, a picture or an atomic inline.
fn find_first_text(l: *Layout, b: u32) -> u32 {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let ks = st(l, kb.style)
        if kb.inner == .Marker || is_out_of_flow(ks) {
            kid = kb.next
            continue
        }
        if kb.inner == .Text {
            if is_ws_only(kb.text) && collapses(l, kid) {
                kid = kb.next
                continue
            }
            ret kid
        }
        if kb.inner == .Break || kb.inner == .Replaced { ret NONE }
        if kb.inline_level && kb.inner != .Flow { ret NONE }
        if kb.inner == .Table || kb.inner == .Flex || kb.inner == .Grid { ret NONE }
        // An inline box or a block: its first text counts.
        let inner_found = find_first_text(l, kid)
        ret inner_found
    }
    ret NONE
}

fn apply_first_letter(l: *Layout, b: u32, ps: *const style.Style) {
    let t = find_first_text(l, b)
    if t == NONE { ret }
    let text = l.boxes.items[usize(t)].text
    // Skip collapsible leading white space, then punctuation, one letter with its marks, then punctuation.
    var at = 0usize
    if collapses(l, t) {
        while at < text.len && is_space_byte(text[at]) { at += 1usize }
    }
    let start = at
    var seen_letter = false
    var done = false
    while at < text.len && !done {
        let (d, de) = utf8.decode(text, at)
        if de != ok { break }
        let c = d.scalar
        if !seen_letter {
            if is_punct(c) {
                at += usize(d.width)
            } else if c < 128u32 && is_space_byte(u8(c)) {
                done = true
            } else {
                seen_letter = true
                at += usize(d.width)
                while at < text.len {
                    let (m, me) = utf8.decode(text, at)
                    if me != ok || !is_combining(m.scalar) { break }
                    at += usize(m.width)
                }
            }
        } else {
            if is_punct(d.scalar) { at += usize(d.width) } else { done = true }
        }
    }
    if !seen_letter || at <= start { ret }
    let id = push_style(l, ps)
    let pd = l.anon.items[usize(id) - l.styles.len].display
    var inline = true
    if l.anon.items[usize(id) - l.styles.len].floating != .None { inline = false }
    let fb = new_box(l, .Flow, inline, true, l.boxes.items[usize(t)].node, id)
    let ft = new_box(l, .Text, true, false, l.boxes.items[usize(t)].node, id)
    bx(l, ft).text = text[start..at]
    append(l, fb, ft)
    // The rest of the run stays where it was; the new box goes in front of it.
    l.boxes.items[usize(t)].text = text[at..]
    if collapses(l, t) && start > 0usize {
        // Keep the skipped white space with the remainder's collapsing context (it collapses away anyway).
        l.boxes.items[usize(t)].text = text[at..]
    }
    let parent = l.boxes.items[usize(t)].parent
    let prev = l.boxes.items[usize(t)].prev
    l.boxes.items[usize(fb)].parent = parent
    l.boxes.items[usize(fb)].prev = prev
    l.boxes.items[usize(fb)].next = t
    if prev == NONE { l.boxes.items[usize(parent)].first = fb } else { l.boxes.items[usize(prev)].next = fb }
    l.boxes.items[usize(t)].prev = fb
}

// --- Generated content: counters, quotes and the `content` property of ::before, ::after and ::marker.

type CounterInst = struct { name: str, value: i64, depth: usize }

fn find_counter(l: *const Layout, name: str) -> i64 {
    var i = l.counters.len
    while i > 0usize {
        i -= 1usize
        if str.eq(l.counters.items[i].name, name) { ret i64(i) }
    }
    ret -1i64
}

fn counter_instantiate(l: *Layout, name: str, value: i64) {
    // A reset by a sibling of the element that made the counter replaces it rather than nesting.
    var i = l.counters.len
    while i > 0usize {
        i -= 1usize
        if str.eq(l.counters.items[i].name, name) {
            if l.counters.items[i].depth == l.gen_depth {
                l.counters.items[i].value = value
                ret
            }
            break
        }
    }
    let pushed = list.push[CounterInst](&l.counters, CounterInst { name: name, value: value, depth: l.gen_depth })
}

type RevAcc = struct { sum: i64, last: i64 }

// The `counter-increment` of `name` in `text` (default 1), when it names the counter.
fn incr_of(l: *Layout, text: str, name: str) -> (i64, bool) {
    let toks = cv.split_top_level_spaces(l.a, text)
    var i = 0usize
    while i < toks.len {
        let t = toks[i]
        i += 1usize
        var v = 1i64
        if i < toks.len {
            let (n, good) = str.parse_i64(toks[i])
            if good == ok {
                v = n
                i += 1usize
            }
        }
        if str.eq(t, name) { ret (v, true) }
    }
    ret (0i64, false)
}

// Whether a `counter-reset` list creates a counter called `name` (plain or `reversed(name)`).
fn resets_name(l: *Layout, text: str, name: str) -> bool {
    let toks = cv.split_top_level_spaces(l.a, text)
    var i = 0usize
    while i < toks.len {
        var t = toks[i]
        i += 1usize
        if str.starts_with(t, "reversed(") && t.len > 10usize { t = str.trim(t[9usize..t.len - 1usize]) }
        if str.eq(t, name) { ret true }
    }
    ret false
}

fn rev_style(l: *Layout, s: *const style.Style, name: str, acc: *RevAcc) {
    let (incr, has) = extra_text(s, "counter-increment")
    if !has { ret }
    let (v, found) = incr_of(l, incr, name)
    if found {
        acc.sum += v
        acc.last = v
    }
}

// The increments of `name` in the scope of element `e`: its own, its ::before and ::after, and its descendants' (an
// element that resets the name starts a counter of its own and is left out).
fn rev_walk(l: *Layout, e: u32, name: str, acc: *RevAcc, origin: bool) {
    let s = &l.styles[usize(e)]
    if s.display == .None { ret }
    if !origin {
        let (rs, has_rs) = extra_text(s, "counter-reset")
        if has_rs && resets_name(l, rs, name) { ret }
    }
    let pb = s.pseudo[0usize]
    if mem.address_of(pb) != 0usize && pb.display != .None { rev_style(l, pb, name, acc) }
    rev_style(l, s, name, acc)
    var kid = l.d.nodes[usize(e)].first_child
    while kid != html.NONE {
        if l.d.nodes[usize(kid)].kind == .Element { rev_walk(l, kid, name, acc, false) }
        kid = l.d.nodes[usize(kid)].next_sibling
    }
    let pa = s.pseudo[1usize]
    if mem.address_of(pa) != 0usize && pa.display != .None { rev_style(l, pa, name, acc) }
}

// The initial value of `reversed(name)` on `node`: the counter reaches the size of its last step on the last item that steps it.
fn rev_initial(l: *Layout, node: u32, name: str) -> i64 {
    var acc = RevAcc { sum: 0i64, last: 0i64 }
    rev_walk(l, node, name, &acc, true)
    var sib = l.d.nodes[usize(node)].next_sibling
    while sib != html.NONE {
        if l.d.nodes[usize(sib)].kind == .Element {
            let (rs, has_rs) = extra_text(&l.styles[usize(sib)], "counter-reset")
            if has_rs && resets_name(l, rs, name) { break }
            rev_walk(l, sib, name, &acc, false)
        }
        sib = l.d.nodes[usize(sib)].next_sibling
    }
    ret 0i64 - acc.sum - acc.last
}

// Applies `counter-reset`, `counter-increment` and `counter-set` (in that order) of an element.
fn apply_counter_props(l: *Layout, s: *const style.Style, node: u32) {
    let (reset, has_reset) = extra_text(s, "counter-reset")
    let (incr, has_incr) = extra_text(s, "counter-increment")
    let (set, has_set) = extra_text(s, "counter-set")
    if has_reset && !str.eq(cv.lower(l.a, cv.trim_ws(reset)), "none") { counter_pairs(l, reset, 0u8, 0i64, node) }
    if has_incr && !str.eq(cv.lower(l.a, cv.trim_ws(incr)), "none") { counter_pairs(l, incr, 1u8, 1i64, NONE) }
    if has_set && !str.eq(cv.lower(l.a, cv.trim_ws(set)), "none") { counter_pairs(l, set, 2u8, 0i64, NONE) }
}

// `name [integer]` pairs; op 0 reset, 1 increment, 2 set.
fn counter_pairs(l: *Layout, text: str, op: u8, default_value: i64, node: u32) {
    let toks = cv.split_top_level_spaces(l.a, text)
    var i = 0usize
    while i < toks.len {
        var name = toks[i]
        var rev = false
        if op == 0u8 && str.starts_with(name, "reversed(") && name.len > 10usize {
            name = str.trim(name[9usize..name.len - 1usize])
            rev = true
        }
        i += 1usize
        var v = default_value
        var explicit = false
        if i < toks.len {
            let (n, good) = str.parse_i64(toks[i])
            if good == ok {
                v = n
                explicit = true
                i += 1usize
            }
        }
        if rev && !explicit && node != NONE { v = rev_initial(l, node, name) }
        if op == 0u8 {
            counter_instantiate(l, name, v)
        } else {
            var at = find_counter(l, name)
            if at < 0i64 {
                counter_instantiate(l, name, 0i64)
                at = i64(l.counters.len) - 1i64
            }
            if op == 1u8 { l.counters.items[usize(at)].value += v } else { l.counters.items[usize(at)].value = v }
        }
    }
}

fn format_counter(l: *Layout, value: i64, kind: str) -> str {
    if str.eq(kind, "none") { ret "" }
    if str.eq(kind, "disc") { ret "\xe2\x80\xa2" }
    if str.eq(kind, "circle") { ret "\xe2\x97\xa6" }
    if str.eq(kind, "square") { ret "\xe2\x96\xaa" }
    if str.eq(kind, "decimal-leading-zero") { ret number_text(l, value, 2usize) }
    if str.eq(kind, "lower-alpha") || str.eq(kind, "lower-latin") { ret alpha_text(l, value, false) }
    if str.eq(kind, "upper-alpha") || str.eq(kind, "upper-latin") { ret alpha_text(l, value, true) }
    if str.eq(kind, "lower-roman") { ret roman_text(l, value, false) }
    if str.eq(kind, "upper-roman") { ret roman_text(l, value, true) }
    ret number_text(l, value, 0usize)
}

fn join_parts(a: *mem.Arena, parts: []const str) -> str {
    var total = 0usize
    var i = 0usize
    while i < parts.len {
        total += parts[i].len
        i += 1usize
    }
    let (d, e) = mem.alloc[u8](a, total + 1usize)
    if e != ok { ret "" }
    var at = 0usize
    i = 0usize
    while i < parts.len {
        var k = 0usize
        while k < parts[i].len {
            d[at] = parts[i][k]
            at += 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret d[0usize..total]
}

// The quotation mark pair for nesting `depth` (`quotes` of the style, else the typographic defaults).
fn quote_pair(l: *Layout, s: *const style.Style, depth: i64, close: bool) -> str {
    var open0 = "\xe2\x80\x9c"
    var close0 = "\xe2\x80\x9d"
    var open1 = "\xe2\x80\x98"
    var close1 = "\xe2\x80\x99"
    let (q, has) = extra_text(s, "quotes")
    if has {
        let low = cv.lower(l.a, cv.trim_ws(q))
        if str.eq(low, "none") { ret "" }
        let (toks, te) = syntax.tokenize(l.a, q)
        if te == ok {
            var strings: [8]str = zero
            var n = 0usize
            var i = 0usize
            while i < toks.len && n < 8usize {
                if toks[i].kind == .String {
                    strings[n] = toks[i].value
                    n += 1usize
                }
                i += 1usize
            }
            if n >= 2usize {
                open0 = strings[0usize]
                close0 = strings[1usize]
                open1 = open0
                close1 = close0
                if n >= 4usize {
                    open1 = strings[2usize]
                    close1 = strings[3usize]
                }
            }
        }
    }
    if depth <= 0i64 {
        if close { ret close0 }
        ret open0
    }
    if close { ret close1 }
    ret open1
}

// The text of a `content` value for the element `node`; `has` is false for `none`, `normal` or no value.
fn eval_content(l: *Layout, s: *const style.Style, node: u32) -> (str, bool) {
    let (raw, has) = extra_text(s, "content")
    if !has { ret ("", false) }
    let low = cv.lower(l.a, cv.trim_ws(raw))
    if str.eq(low, "none") || str.eq(low, "normal") || low.len == 0usize { ret ("", false) }
    let (toks, te) = syntax.tokenize(l.a, raw)
    if te != ok { ret ("", false) }
    let (pm, pe) = list.init[str](l.a, 8usize)
    if pe != ok { ret ("", false) }
    var parts = pm
    var any = false
    var i = 0usize
    while i < toks.len {
        let t = toks[i]
        i += 1usize
        if t.kind == .Whitespace { continue }
        if t.kind == .String {
            let pushed = list.push[str](&parts, t.value)
            any = true
        } else if t.kind == .Delim && str.eq(t.value, "/") {
            break
        } else if t.kind == .Ident {
            let name = cv.lower(l.a, t.value)
            if str.eq(name, "open-quote") {
                let mark = quote_pair(l, s, l.quote_depth, false)
                let pushed = list.push[str](&parts, mark)
                l.quote_depth += 1i64
                any = true
            } else if str.eq(name, "close-quote") {
                if l.quote_depth > 0i64 { l.quote_depth -= 1i64 }
                let mark2 = quote_pair(l, s, l.quote_depth, true)
                let pushed = list.push[str](&parts, mark2)
                any = true
            } else if str.eq(name, "no-open-quote") {
                l.quote_depth += 1i64
            } else if str.eq(name, "no-close-quote") {
                if l.quote_depth > 0i64 { l.quote_depth -= 1i64 }
            }
        } else if t.kind == .Function {
            // The arguments up to the matching parenthesis, split at commas.
            var args: [4]str = zero
            var kinds: [4]syntax.Kind = zero
            var n = 0usize
            var depth = 1i64
            var cur: str = ""
            var cur_kind = syntax.Kind.Ident
            var have = false
            while i < toks.len && depth > 0i64 {
                let u = toks[i]
                i += 1usize
                if u.kind == .LeftParen || u.kind == .Function {
                    depth += 1i64
                } else if u.kind == .RightParen {
                    depth -= 1i64
                    if depth == 0i64 {
                        if have && n < 4usize {
                            args[n] = cur
                            kinds[n] = cur_kind
                            n += 1usize
                        }
                        break
                    }
                } else if u.kind == .Comma && depth == 1i64 {
                    if have && n < 4usize {
                        args[n] = cur
                        kinds[n] = cur_kind
                        n += 1usize
                    }
                    have = false
                } else if (u.kind == .Ident || u.kind == .String) && !have {
                    cur = u.value
                    cur_kind = u.kind
                    have = true
                }
            }
            let fname = cv.lower(l.a, t.value)
            if str.eq(fname, "attr") && n >= 1usize {
                let (v, got) = dom.get_attribute(l.d, node, cv.lower(l.a, args[0usize]))
                if got {
                    let pushed = list.push[str](&parts, v)
                }
                any = true
            } else if str.eq(fname, "counter") && n >= 1usize {
                var kind = "decimal"
                if n >= 2usize { kind = cv.lower(l.a, args[1usize]) }
                let at = find_counter(l, args[0usize])
                var value = 0i64
                if at >= 0i64 { value = l.counters.items[usize(at)].value }
                let pushed = list.push[str](&parts, format_counter(l, value, kind))
                any = true
            } else if str.eq(fname, "counters") && n >= 2usize {
                var kind2 = "decimal"
                if n >= 3usize { kind2 = cv.lower(l.a, args[2usize]) }
                var first = true
                var ci = 0usize
                while ci < l.counters.len {
                    if str.eq(l.counters.items[ci].name, args[0usize]) {
                        if !first {
                            let pushed = list.push[str](&parts, args[1usize])
                        }
                        let pushed2 = list.push[str](&parts, format_counter(l, l.counters.items[ci].value, kind2))
                        first = false
                    }
                    ci += 1usize
                }
                any = true
            }
        }
    }
    if !any { ret ("", false) }
    ret (join_parts(l.a, list.slice_const[str](&parts)), true)
}

fn push_style(l: *Layout, s: *const style.Style) -> u32 {
    let pushed = list.push[style.Style](&l.anon, *s)
    ret u32(l.styles.len) + u32(l.anon.len) - 1u32
}

fn inner_for_display(d: style.Display) -> Inner {
    if d == .InlineBlock || d == .FlowRoot { ret .FlowRoot }
    if d == .Flex || d == .InlineFlex { ret .Flex }
    if d == .Grid || d == .InlineGrid { ret .Grid }
    if d == .Table || d == .InlineTable { ret .Table }
    if d == .TableRow { ret .Row }
    if d == .TableRowGroup || d == .TableHeaderGroup || d == .TableFooterGroup { ret .RowGroup }
    if d == .TableCell { ret .Cell }
    if d == .TableCaption { ret .Caption }
    ret .Flow
}

// The box of an element's ::before (kind 0) or ::after (kind 1), if its content produces one.
fn gen_pseudo(l: *Layout, node: u32, parent_box: u32, kind: usize) {
    let ps = l.styles[usize(node)].pseudo[kind]
    if mem.address_of(ps) == 0usize { ret }
    if ps.display == .None { ret }
    apply_counter_props(l, ps, NONE)
    let (text, has) = eval_content(l, ps, node)
    if !has { ret }
    let id = push_style(l, ps)
    let pd = l.anon.items[usize(id) - l.styles.len].display
    // `display: contents` leaves only the generated text, in the parent.
    if pd == .Contents {
        if text.len > 0usize {
            let tc = new_box(l, .Text, true, false, node, id)
            bx(l, tc).text = text
            append(l, parent_box, tc)
        }
        ret
    }
    let b = new_box(l, inner_for_display(pd), is_inline_level_display(pd), true, node, id)
    append(l, parent_box, b)
    // Counters of the pseudo-element itself apply inside it.
    if text.len > 0usize {
        let t = new_box(l, .Text, true, false, node, id)
        bx(l, t).text = text
        append(l, b, t)
    }
    fix_anonymous(l, b)
}

fn is_replaced_tag(name: str) -> bool {
    ret name_in(",img,video,canvas,iframe,embed,object,audio,svg,input,textarea,select,meter,progress,", name)
}

fn name_in(set: str, name: str) -> bool {
    var i = 1usize
    while i < set.len {
        var j = i
        while j < set.len && set[j] != 44u8 { j += 1usize }
        if j - i == name.len && str.eq(set[i..j], name) { ret true }
        i = j + 1usize
    }
    ret false
}

fn is_block_level(d: style.Display) -> bool {
    ret d == .Block || d == .Flex || d == .Grid || d == .Table || d == .ListItem || d == .FlowRoot || d == .RunIn
}

fn is_inline_level_display(d: style.Display) -> bool {
    ret d == .Inline || d == .InlineBlock || d == .InlineFlex || d == .InlineGrid || d == .InlineTable || d == .Ruby || d == .RubyText || d == .RubyBase || d == .RubyTextContainer || d == .RubyBaseContainer
}

fn is_abs_positioned(s: *const style.Style) -> bool { ret s.position == .Absolute || s.position == .Fixed }

fn is_out_of_flow(s: *const style.Style) -> bool {
    ret s.floating != .None || s.position == .Absolute || s.position == .Fixed
}

fn gen_children(l: *Layout, node: u32, parent_box: u32) {
    l.gen_depth += 1usize
    var kid = l.d.nodes[usize(node)].first_child
    while kid != html.NONE {
        gen_node(l, kid, parent_box, node)
        kid = l.d.nodes[usize(kid)].next_sibling
    }
    // The counters the children made go out of scope with their parent's contents.
    while l.counters.len > 0usize && l.counters.items[l.counters.len - 1usize].depth >= l.gen_depth { l.counters.len -= 1usize }
    l.gen_depth -= 1usize
}

// The block a run-in element runs into: its next sibling, when that is a plain block and not floated or positioned.
fn run_in_target(l: *Layout, node: u32) -> u32 {
    var nx = l.d.nodes[usize(node)].next_sibling
    while nx != html.NONE {
        let nn = &l.d.nodes[usize(nx)]
        if nn.kind == .Text {
            if !is_ws_only(nn.value) { ret NONE }
        } else if nn.kind == .Element {
            let ns = &l.styles[usize(nx)]
            if ns.display == .None || ns.floating != .None || ns.position == .Absolute || ns.position == .Fixed {
                // skipped over: it does not stop the run-in
            } else if (ns.display == .Block || ns.display == .FlowRoot) && ns.clear == .None {
                ret nx
            } else {
                ret NONE
            }
        }
        nx = nn.next_sibling
    }
    ret NONE
}

// The run-in element that runs into `node`, or NONE.
fn run_in_before(l: *Layout, node: u32) -> u32 {
    var pv = l.d.nodes[usize(node)].previous_sibling
    while pv != html.NONE {
        let pn = &l.d.nodes[usize(pv)]
        if pn.kind == .Text {
            if !is_ws_only(pn.value) { ret NONE }
        } else if pn.kind == .Element {
            let ps = &l.styles[usize(pv)]
            if ps.display == .RunIn {
                if run_in_target(l, pv) == node { ret pv }
                ret NONE
            }
            if !(ps.display == .None || ps.floating != .None || ps.position == .Absolute || ps.position == .Fixed) { ret NONE }
        }
        pv = pn.previous_sibling
    }
    ret NONE
}

// A run-in element becomes an inline box at the start of the block it runs into.
fn gen_run_in(l: *Layout, rnode: u32, target_box: u32) {
    let rs = &l.styles[usize(rnode)]
    apply_counter_props(l, rs, rnode)
    let rb = new_box(l, .Flow, true, false, rnode, rnode)
    append(l, target_box, rb)
    gen_pseudo(l, rnode, rb, 0usize)
    gen_children(l, rnode, rb)
    gen_pseudo(l, rnode, rb, 1usize)
    fix_anonymous(l, rb)
}

fn gen_node(l: *Layout, node: u32, parent_box: u32, parent_node: u32) {
    let n = &l.d.nodes[usize(node)]
    if n.kind == .Text {
        if n.value.len == 0usize { ret }
        let b = new_box(l, .Text, true, false, node, parent_node)
        bx(l, b).text = n.value
        append(l, parent_box, b)
        ret
    }
    if n.kind != .Element { ret }
    let s = &l.styles[usize(node)]
    if s.display == .None { ret }
    apply_counter_props(l, s, node)
    // The implicit `list-item` counter: a list starts one and each item steps it (see `list_ordinal`).
    if n.namespace == .Html && (str.eq(n.name, "ol") || str.eq(n.name, "ul") || str.eq(n.name, "menu")) { counter_instantiate(l, "list-item", 0i64) }
    if s.display == .ListItem {
        var li_at = find_counter(l, "list-item")
        if li_at < 0i64 {
            counter_instantiate(l, "list-item", 0i64)
            li_at = i64(l.counters.len) - 1i64
        }
        l.counters.items[usize(li_at)].value = list_ordinal(l, node)
    }
    if s.display == .Contents {
        // The element has no box of its own, but its ::before and ::after still generate boxes in its parent.
        gen_pseudo(l, node, parent_box, 0usize)
        gen_children(l, node, parent_box)
        gen_pseudo(l, node, parent_box, 1usize)
        ret
    }
    if s.display == .RunIn && run_in_target(l, node) != NONE { ret }
    if n.namespace == .Html && str.eq(n.name, "br") {
        let b = new_box(l, .Break, true, false, node, node)
        append(l, parent_box, b)
        ret
    }
    var inner: Inner = .Flow
    var inline_level = is_inline_level_display(s.display)
    var replaced = false
    if n.namespace == .Html && is_replaced_tag(n.name) {
        replaced = true
        inner = .Replaced
    } else if n.namespace == .Svg && str.eq(n.name, "svg") {
        replaced = true
        inner = .Replaced
    }
    if !replaced {
        if s.display == .InlineBlock || s.display == .FlowRoot { inner = .FlowRoot }
        if s.display == .Flex || s.display == .InlineFlex { inner = .Flex }
        if s.display == .Grid || s.display == .InlineGrid { inner = .Grid }
        if s.display == .Table || s.display == .InlineTable { inner = .Table }
        if s.display == .TableRow { inner = .Row }
        if s.display == .TableRowGroup || s.display == .TableHeaderGroup || s.display == .TableFooterGroup { inner = .RowGroup }
        if s.display == .TableCell { inner = .Cell }
        if s.display == .TableCaption { inner = .Caption }
        if s.display == .TableColumnGroup { inner = .ColumnGroup }
        if s.display == .TableColumn { inner = .Column }
    }
    let b = new_box(l, inner, inline_level, false, node, node)
    append(l, parent_box, b)
    if replaced { ret }
    if s.display == .ListItem {
        var marker_style = node
        let ms = s.pseudo[2usize]
        if mem.address_of(ms) != 0usize { marker_style = push_style(l, ms) }
        let m = new_box(l, .Marker, s.list_style_position == .Inside, true, node, marker_style)
        bx(l, m).aux = u32(list_ordinal(l, node) & 4294967295i64)
        if mem.address_of(ms) != 0usize {
            let (custom, has_custom) = eval_content(l, ms, node)
            if has_custom {
                bx(l, m).text = custom
                bx(l, m).aux2 = 1u32
            }
        }
        append(l, b, m)
    }
    let rin = run_in_before(l, node)
    if rin != NONE { gen_run_in(l, rin, b) }
    gen_pseudo(l, node, b, 0usize)
    gen_children(l, node, b)
    gen_pseudo(l, node, b, 1usize)
    let fl = s.pseudo[3usize]
    if mem.address_of(fl) != 0usize && !inline_level { apply_first_letter(l, b, fl) }
    fix_anonymous(l, b)
}

// The step of a list item: its own `counter-increment` of `list-item`, else 1 (-1 in a reversed list).
fn list_step(l: *Layout, kid: u32, reversed: bool) -> i64 {
    let (incr, has) = extra_text(&l.styles[usize(kid)], "counter-increment")
    if has {
        let (v, found) = incr_of(l, incr, "list-item")
        if found { ret v }
    }
    if reversed { ret 0i64 - 1i64 }
    ret 1i64
}

// The value of a list item's counter: a `value` attribute sets it, every other item steps it from the list's start (or, in a
// reversed list without `start`, from where the last step lands on its own size).
fn list_ordinal(l: *Layout, node: u32) -> i64 {
    let parent = l.d.nodes[usize(node)].parent
    var reversed = false
    var start = 1i64
    var has_start = false
    if parent != html.NONE && dom.is_html_named(l.d, parent, "ol") {
        let (rev, has_rev) = dom.get_attribute(l.d, parent, "reversed")
        reversed = has_rev
        let (sv, hs) = dom.get_attribute(l.d, parent, "start")
        if hs {
            let (n, good) = str.parse_i64(sv)
            if good == ok {
                start = n
                has_start = true
            }
        }
    }
    if parent == html.NONE {
        let (value, has_value) = dom.get_attribute(l.d, node, "value")
        if has_value {
            let (n, good) = str.parse_i64(value)
            if good == ok { ret n }
        }
        ret 1i64
    }
    var init = start - 1i64
    if reversed {
        if has_start {
            init = start + 1i64
        } else {
            var sum = 0i64
            var last = 0i64
            var k2 = l.d.nodes[usize(parent)].first_child
            while k2 != html.NONE {
                if l.d.nodes[usize(k2)].kind == .Element && l.styles[usize(k2)].display == .ListItem {
                    last = list_step(l, k2, true)
                    sum += last
                }
                k2 = l.d.nodes[usize(k2)].next_sibling
            }
            init = 0i64 - sum - last
        }
    }
    var cur = init
    var kid = l.d.nodes[usize(parent)].first_child
    while kid != html.NONE {
        if l.d.nodes[usize(kid)].kind == .Element && l.styles[usize(kid)].display == .ListItem {
            let (value, has_value) = dom.get_attribute(l.d, kid, "value")
            var set = false
            if has_value {
                let (n, good) = str.parse_i64(value)
                if good == ok {
                    cur = n
                    set = true
                }
            }
            if !set { cur += list_step(l, kid, reversed) }
            if kid == node { ret cur }
        }
        kid = l.d.nodes[usize(kid)].next_sibling
    }
    ret cur
}

fn is_ws_only(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c != 32u8 && c != 9u8 && c != 10u8 && c != 12u8 && c != 13u8 { ret false }
        i += 1usize
    }
    ret true
}

fn is_block_container(l: *const Layout, b: u32) -> bool {
    let inner = l.boxes.items[usize(b)].inner
    ret inner == .Flow || inner == .FlowRoot || inner == .Cell || inner == .Caption
}

// The display of the anonymous table around orphan parts: inline inside an inline box.
fn orphan_display(l: *const Layout, parent: u32) -> style.Display {
    if l.boxes.items[usize(parent)].inline_level { ret .InlineTable }
    ret .Table
}

fn is_table_part(inner: Inner) -> bool {
    ret inner == .Cell || inner == .Row || inner == .RowGroup || inner == .Column || inner == .ColumnGroup
}

// Table cells, rows, row groups and columns outside a table get an anonymous table around each run of them (CSS 2.1 17.2.1).
fn wrap_orphan_table_parts(l: *Layout, b: u32) {
    var run_first = NONE
    var run_last = NONE
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let nxt = l.boxes.items[usize(kid)].next
        let part = is_table_part(l.boxes.items[usize(kid)].inner)
        if part {
            if run_first == NONE { run_first = kid }
            run_last = kid
        } else if run_first != NONE {
            // White space between the parts belongs to the run; anything else ends it.
            let kb = &l.boxes.items[usize(kid)]
            // (CSS 2.1 17.2.1: a white-space-only run between table parts is dropped whatever `white-space` says.)
            if kb.inner == .Text && is_ws_only(kb.text) {
                // keep scanning
            } else {
                wrap_table_run(l, b, run_first, run_last, .Table, orphan_display(l, b))
                let anon = l.boxes.items[usize(run_first)].parent
                if anon != b && anon != NONE { fix_table_like(l, anon) }
                run_first = NONE
                run_last = NONE
            }
        }
        kid = nxt
    }
    if run_first != NONE {
        wrap_table_run(l, b, run_first, run_last, .Table, orphan_display(l, b))
        let anon2 = l.boxes.items[usize(run_first)].parent
        if anon2 != b && anon2 != NONE { fix_table_like(l, anon2) }
    }
}

// A block container with block-level children wraps its inline-level runs in anonymous blocks; a container of only
// inline-level children keeps them (one inline formatting context). White-space-only text between blocks goes.
fn fix_anonymous(l: *Layout, b: u32) {
    let inner = l.boxes.items[usize(b)].inner
    if inner == .Table || inner == .RowGroup || inner == .Row {
        fix_table_like(l, b)
        ret
    }
    if inner == .ColumnGroup { ret }
    if inner == .Flex || inner == .Grid {
        wrap_flex_items(l, b)
        ret
    }
    if !is_block_container(l, b) { ret }
    wrap_orphan_table_parts(l, b)
    var has_block = false
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let nxt = l.boxes.items[usize(kid)].next
        promote_inline_with_blocks(l, kid)
        let kb = &l.boxes.items[usize(kid)]
        if !kb.inline_level && kb.inner != .Marker && !is_out_of_flow(st(l, kb.style)) { has_block = true }
        kid = nxt
    }
    if !has_block { ret }
    kid = l.boxes.items[usize(b)].first
    var run_first = NONE
    var run_last = NONE
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let nxt = kb.next
        let neutral = !kb.inline_level && is_out_of_flow(st(l, kb.style))
        if kb.inline_level {
            if run_first == NONE { run_first = kid }
            run_last = kid
        } else if neutral && run_first != NONE {
            run_last = kid
        } else if !neutral {
            flush_run(l, b, run_first, run_last)
            run_first = NONE
            run_last = NONE
        }
        kid = nxt
    }
    flush_run(l, b, run_first, run_last)
}

fn promote_inline_with_blocks(l: *Layout, b: u32) {
    let bb = &l.boxes.items[usize(b)]
    if !bb.inline_level || bb.inner != .Flow { ret }
    var has_block = false
    var kid = bb.first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if !kb.inline_level && kb.inner != .Marker && !is_out_of_flow(st(l, kb.style)) { has_block = true }
        kid = kb.next
    }
    if !has_block { ret }
    l.boxes.items[usize(b)].inline_level = false
    fix_anonymous(l, b)
}

// Moves the inline-level siblings first..last into one anonymous block, unless they are all collapsible white space.
fn flush_run(l: *Layout, parent: u32, first: u32, last: u32) {
    if first == NONE { ret }
    var all_ws = true
    var k = first
    while true {
        let kb = &l.boxes.items[usize(k)]
        let out_of_flow = !kb.inline_level && is_out_of_flow(st(l, kb.style))
        if !out_of_flow && !(kb.inner == .Text && is_ws_only(kb.text) && collapses(l, k)) { all_ws = false }
        if k == last { break }
        k = kb.next
    }
    if all_ws {
        k = first
        while true {
            let nxt = l.boxes.items[usize(k)].next
            let kb = &l.boxes.items[usize(k)]
            if kb.inline_level || !is_out_of_flow(st(l, kb.style)) { detach(l, k) }
            if k == last { break }
            k = nxt
        }
        ret
    }
    let anon = new_box(l, .Flow, false, true, NONE, anon_style(l, l.boxes.items[usize(parent)].style, .Block))
    // Insert before `first` among parent's children.
    let before = first
    let prev = l.boxes.items[usize(before)].prev
    l.boxes.items[usize(anon)].parent = parent
    l.boxes.items[usize(anon)].prev = prev
    l.boxes.items[usize(anon)].next = before
    if prev == NONE { l.boxes.items[usize(parent)].first = anon } else { l.boxes.items[usize(prev)].next = anon }
    l.boxes.items[usize(before)].prev = anon
    k = first
    while true {
        let nxt = l.boxes.items[usize(k)].next
        detach(l, k)
        append(l, anon, k)
        if k == last { break }
        k = nxt
    }
}

fn collapses(l: *const Layout, b: u32) -> bool {
    let ws = bstyle(l, b).white_space
    ret ws == .Normal || ws == .Nowrap || ws == .PreLine
}

// Flex and grid containers: every in-flow child is an item; contiguous text becomes an anonymous item, white space goes.
fn wrap_flex_items(l: *Layout, b: u32) {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let nxt = l.boxes.items[usize(kid)].next
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Text {
            if is_ws_only(kb.text) && collapses(l, kid) {
                detach(l, kid)
            } else {
                // A run of text becomes an anonymous block item.
                var last = kid
                var scan = nxt
                while scan != NONE && l.boxes.items[usize(scan)].inner == .Text {
                    last = scan
                    scan = l.boxes.items[usize(scan)].next
                }
                flush_run(l, b, kid, last)
                kid = scan
                continue
            }
        } else if kb.inline_level && kb.inner == .Flow {
            // An inline-level child of a flex container is blockified (its display is already blockified by the style).
            l.boxes.items[usize(kid)].inline_level = false
        } else if kb.inline_level {
            l.boxes.items[usize(kid)].inline_level = false
        }
        kid = nxt
    }
}

type Flag = struct { v: bool, cleared: bool }

// --- Lengths and the box model.

// `len` against `basis`; false when it has a percentage and the basis is not known (negative).
fn resolve_len(len: style.Len, basis: f64) -> (f64, bool) {
    if len.kind != .Px { ret (0.0f64, false) }
    if len.pct != 0.0f64 {
        if basis < 0.0f64 { ret (0.0f64, false) }
        ret (len.px + len.pct * basis, true)
    }
    ret (len.px, true)
}

fn resolve_or(len: style.Len, basis: f64, fallback: f64) -> f64 {
    let (v, good) = resolve_len(len, basis)
    if good { ret v }
    ret fallback
}

fn maxf(x: f64, y: f64) -> f64 {
    if x > y { ret x }
    ret y
}

fn minf(x: f64, y: f64) -> f64 {
    if x < y { ret x }
    ret y
}

// Margin collapsing: the largest positive and the most negative adjoining margin.
type Margin = struct { pos: f64, neg: f64 }

fn margin_of(v: f64) -> Margin {
    if v >= 0.0f64 { ret Margin { pos: v, neg: 0.0f64 } }
    ret Margin { pos: 0.0f64, neg: v }
}

fn collapse(x: Margin, y: Margin) -> Margin {
    ret Margin { pos: maxf(x.pos, y.pos), neg: minf(x.neg, y.neg) }
}

fn margin_value(m: Margin) -> f64 { ret m.pos + m.neg }

fn no_margin() -> Margin { ret Margin { pos: 0.0f64, neg: 0.0f64 } }

// The `body` whose overflow went to the viewport (the root element's own is `visible`): it is an ordinary block.
fn overflow_propagated(l: *const Layout, b: u32) -> bool {
    let bb = &l.boxes.items[usize(b)]
    if bb.node == NONE || bb.parent == NONE { ret false }
    if !str.eq(l.d.nodes[usize(bb.node)].name, "body") { ret false }
    let pb = &l.boxes.items[usize(bb.parent)]
    if pb.node == NONE || pb.parent == NONE { ret false }
    if !str.eq(l.d.nodes[usize(pb.node)].name, "html") { ret false }
    let ps = st(l, pb.style)
    ret ps.overflow_x == .Visible && ps.overflow_y == .Visible
}

fn is_bfc_root(l: *const Layout, b: u32) -> bool {
    let bb = &l.boxes.items[usize(b)]
    if bb.parent == NONE { ret true }
    if l.boxes.items[usize(bb.parent)].parent == NONE { ret true }
    let s = st(l, bb.style)
    if bb.inner == .FlowRoot || bb.inner == .Flex || bb.inner == .Grid || bb.inner == .Table || bb.inner == .Cell || bb.inner == .Replaced { ret true }
    if s.floating != .None || s.position == .Absolute || s.position == .Fixed { ret true }
    if (s.overflow_x != .Visible || s.overflow_y != .Visible) && !overflow_propagated(l, b) { ret true }
    if has_columns(s) { ret true }
    if s.display == .FlowRoot || s.display == .InlineBlock { ret true }
    ret false
}

fn border_px(s: *const style.Style, side: usize) -> f64 { ret s.border_width[side] }

// Sets the used border and padding of `b` (padding percentages are of the containing block's width).
fn resolve_edges(l: *Layout, b: u32, cbw: f64) {
    let s = bstyle(l, b)
    let bb = bx(l, b)
    var i = 0usize
    while i < 4usize {
        bb.border[i] = border_px(s, i)
        var base = cbw
        if base < 0.0f64 { base = 0.0f64 }
        bb.padding[i] = maxf(0.0f64, resolve_or(s.padding[i], base, 0.0f64))
        i += 1usize
    }
    // A table, row, cell... of a collapsed-border table takes the half of each collapsed edge that falls inside it.
    if bb.coll { bb.border = bb.cbd }
    if bb.inner == .Table && s.border_collapse == .Collapse && !bb.coll {
        let ti = build_table(l, b)
        let bb2 = bx(l, b)
        if bb2.coll { bb2.border = bb2.cbd }
    }
    // The collapsed-border model gives the table no padding.
    if bb.inner == .Table && bx(l, b).coll {
        var pi = 0usize
        while pi < 4usize {
            bx(l, b).padding[pi] = 0.0f64
            pi += 1usize
        }
    }
}

fn resolve_margins_fixed(l: *Layout, b: u32, cbw: f64) {
    let s = bstyle(l, b)
    let bb = bx(l, b)
    var base = cbw
    if base < 0.0f64 { base = 0.0f64 }
    var i = 0usize
    while i < 4usize {
        bb.margin[i] = resolve_or(s.margin[i], base, 0.0f64)
        i += 1usize
    }
}

fn is_auto(len: style.Len) -> bool { ret len.kind == .Auto }

fn horizontal_extras(bb: *const Box) -> f64 {
    ret bb.border[1usize] + bb.border[3usize] + bb.padding[1usize] + bb.padding[3usize]
}

fn vertical_extras(bb: *const Box) -> f64 {
    ret bb.border[0usize] + bb.border[2usize] + bb.padding[0usize] + bb.padding[2usize]
}

// A content-box size from a border-box one and back, per `box-sizing`.
fn to_content_w(l: *const Layout, b: u32, outer: f64) -> f64 {
    let s = bstyle(l, b)
    let bb = &l.boxes.items[usize(b)]
    if s.box_sizing == .BorderBox { ret maxf(0.0f64, outer - horizontal_extras(bb)) }
    ret outer
}

fn to_content_h(l: *const Layout, b: u32, outer: f64) -> f64 {
    let s = bstyle(l, b)
    let bb = &l.boxes.items[usize(b)]
    if s.box_sizing == .BorderBox { ret maxf(0.0f64, outer - vertical_extras(bb)) }
    ret outer
}

// The `aspect-ratio` of a box (`auto`-only and unparsable values give none): width divided by height.
fn box_ratio(l: *const Layout, b: u32) -> (f64, bool) {
    let s = bstyle(l, b)
    var text: str = ""
    var found = false
    var i = 0usize
    while i < s.extras.len {
        if str.eq(s.extras[i].name, "aspect-ratio") {
            text = s.extras[i].value
            found = true
        }
        i += 1usize
    }
    if !found { ret (0.0f64, false) }
    var t = str.trim(text)
    if str.starts_with(t, "auto") { t = str.trim(t[4usize..]) }
    if t.len == 0usize { ret (0.0f64, false) }
    var slash = t.len
    var k = 0usize
    while k < t.len {
        if t[k] == 47u8 { slash = k }
        k += 1usize
    }
    let (num, ne) = str.parse_f64(str.trim(t[0usize..slash]))
    if ne != ok || num <= 0.0f64 { ret (0.0f64, false) }
    var den = 1.0f64
    if slash < t.len {
        let (d2, de) = str.parse_f64(str.trim(t[slash + 1usize..]))
        if de != ok || d2 <= 0.0f64 { ret (0.0f64, false) }
        den = d2
    }
    if l.vmode != 0u8 { ret (den / num, true) }
    ret (num / den, true)
}

fn has_box_ratio(l: *const Layout, b: u32) -> bool {
    let (r, has) = box_ratio(l, b)
    ret has
}

// The content height the ratio gives box `b` of content width `cw` (border-box width `bb.w`): false when it has no ratio.
fn ratio_height(l: *const Layout, b: u32, cw: f64) -> (f64, bool) {
    let (r, has) = box_ratio(l, b)
    if !has { ret (0.0f64, false) }
    let s = bstyle(l, b)
    let bb = &l.boxes.items[usize(b)]
    if s.box_sizing == .BorderBox { ret (maxf(0.0f64, bb.w / r - vertical_extras(bb)), true) }
    ret (cw / r, true)
}

// The content width the ratio gives a box of content height `ch`.
fn ratio_width(l: *const Layout, b: u32, ch: f64) -> (f64, bool) {
    let (r, has) = box_ratio(l, b)
    if !has { ret (0.0f64, false) }
    let s = bstyle(l, b)
    let bb = &l.boxes.items[usize(b)]
    if s.box_sizing == .BorderBox { ret (maxf(0.0f64, (ch + vertical_extras(bb)) * r - horizontal_extras(bb)), true) }
    ret (ch * r, true)
}

// min-width / max-width applied to a content width.
fn clamp_width(l: *const Layout, b: u32, w: f64, cbw: f64) -> f64 {
    let s = bstyle(l, b)
    var out = w
    let (mx, has_max) = resolve_len(s.max_width, cbw)
    if s.max_width.kind == .Px && has_max { out = minf(out, to_content_w(l, b, mx)) }
    let (mn, has_min) = resolve_len(s.min_width, cbw)
    if s.min_width.kind == .Px && has_min { out = maxf(out, to_content_w(l, b, mn)) }
    ret out
}

fn clamp_height(l: *const Layout, b: u32, h: f64, cbh: f64) -> f64 {
    ret clamp_height_auto(l, b, h, cbh, -1.0f64)
}

// As `clamp_height`, with the content height `auto_h` (negative: unknown) for the content keywords of min/max-height.
fn clamp_height_auto(l: *const Layout, b: u32, h: f64, cbh: f64, auto_h: f64) -> f64 {
    let s = bstyle(l, b)
    var out = h
    let (mx, has_max) = resolve_len(s.max_height, cbh)
    if s.max_height.kind == .Px && has_max { out = minf(out, to_content_h(l, b, mx)) }
    if auto_h >= 0.0f64 && (s.max_height.kind == .MinContent || s.max_height.kind == .MaxContent || s.max_height.kind == .FitContent) { out = minf(out, auto_h) }
    let (mn, has_min) = resolve_len(s.min_height, cbh)
    if s.min_height.kind == .Px && has_min { out = maxf(out, to_content_h(l, b, mn)) }
    if auto_h >= 0.0f64 && (s.min_height.kind == .MinContent || s.min_height.kind == .MaxContent || s.min_height.kind == .FitContent) { out = maxf(out, auto_h) }
    ret out
}

// --- Floats in a block formatting context. Coordinates are relative to the context root's content box.

fn float_edge_left(l: *const Layout, base: usize, y0: f64, y1: f64, floor_x: f64) -> f64 {
    var x = floor_x
    var i = base
    while i < l.floats.len {
        let f = l.floats.items[i]
        i += 1usize
        if !f.left { continue }
        if f.y < y1 && f.y + f.h > y0 && f.h > 0.0f64 { x = maxf(x, f.x + f.w) }
    }
    ret x
}

fn float_edge_right(l: *const Layout, base: usize, y0: f64, y1: f64, ceil_x: f64) -> f64 {
    var x = ceil_x
    var i = base
    while i < l.floats.len {
        let f = l.floats.items[i]
        i += 1usize
        if f.left { continue }
        if f.y < y1 && f.y + f.h > y0 && f.h > 0.0f64 { x = minf(x, f.x) }
    }
    ret x
}

// The lowest bottom of the floats on a side (0: left, 1: right, 2: both); `floor` when there are none.
fn float_bottom(l: *const Layout, base: usize, side: u32, floor: f64) -> f64 {
    var y = floor
    var i = base
    while i < l.floats.len {
        let f = l.floats.items[i]
        i += 1usize
        if side == 0u32 && !f.left { continue }
        if side == 1u32 && f.left { continue }
        y = maxf(y, f.y + f.h)
    }
    ret y
}

// The next y below `y` where a float ends (the next place the available width can grow), or `y` when none.
fn next_float_end(l: *const Layout, base: usize, y: f64) -> f64 {
    var best = y
    var found = false
    var i = base
    while i < l.floats.len {
        let f = l.floats.items[i]
        i += 1usize
        let end = f.y + f.h
        if end > y && (!found || end < best) {
            best = end
            found = true
        }
    }
    ret best
}

fn float_top_floor(l: *const Layout, base: usize, floor: f64) -> f64 {
    var y = floor
    var i = base
    while i < l.floats.len {
        y = maxf(y, l.floats.items[i].y)
        i += 1usize
    }
    ret y
}

// --- Text: pieces of an inline formatting context.

type PieceKind = enum u8 { Text, Space, Hard, Atomic, Open, Close, Float, Abs, Marker }

// `w` is the advance of the piece without its trailing collapsible space, `trail` that space's advance. `soft` says a
// line may end after the piece. Text pieces point into the processed text of their box.
type Piece = struct { kind: PieceKind, box: u32, text: str, w: f64, trail: f64, soft: bool, ink: bool, start: usize, clen: usize }

type Builder = struct { l: *Layout, pieces: list.List[Piece], last_space: bool, ws_pending: bool, cbw: f64, cbh: f64 }

fn push_piece(bd: *Builder, p: Piece) {
    let pushed = list.push[Piece](&bd.pieces, p)
}

fn is_space_byte(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 12u8 || c == 13u8 }

fn spacing_extra(s: *const style.Style, text: str) -> f64 {
    if s.letter_spacing == 0.0f64 && s.word_spacing == 0.0f64 { ret 0.0f64 }
    var chars = 0usize
    var spaces = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if (c & 192u8) != 128u8 { chars += 1usize }
        if c == 32u8 { spaces += 1usize }
        i += 1usize
    }
    ret s.letter_spacing * f64(chars) + s.word_spacing * f64(spaces)
}

fn text_advance(l: *const Layout, s: *const style.Style, text: str) -> f64 {
    if text.len == 0usize { ret 0.0f64 }
    ret l.measure.width(l.measure.ctx, s, text) + spacing_extra(s, text)
}

fn apply_transform(l: *const Layout, s: *const style.Style, text: str) -> str {
    if s.text_transform == .None { ret text }
    let (out, e) = mem.alloc[u8](l.a, text.len * 3usize + 4usize)
    if e != ok { ret text }
    var used = 0usize
    var at = 0usize
    var word_start = true
    while at < text.len {
        let (scalar, width) = unicode.read_utf8(text, at)
        at += width
        var mapped = scalar
        if s.text_transform == .Uppercase {
            if scalar == 223u32 {
                out[used] = 83u8
                out[used + 1usize] = 83u8
                used += 2usize
                continue
            }
            mapped = unicode.to_upper_simple(scalar)
        } else if s.text_transform == .Lowercase {
            mapped = unicode.to_lower_simple(scalar)
        } else if s.text_transform == .Capitalize {
            if word_start { mapped = unicode.to_upper_simple(scalar) }
            word_start = scalar == 32u32 || scalar == 9u32 || scalar == 10u32 || scalar == 45u32 || scalar == 40u32
        } else if s.text_transform == .FullWidth {
            if scalar == 32u32 { mapped = 12288u32 } else if scalar >= 33u32 && scalar <= 126u32 { mapped = scalar + 65248u32 }
        }
        used = unicode.write_utf8(mapped, out, used)
    }
    ret out[..used]
}

// The text of a text box with white space processed for its style (`white-space`), hard breaks marked by '\n'.
// `ends_space` carries whether the previous output ended in a collapsible space.
fn process_text(l: *const Layout, b: u32, ends_space: *Flag) -> str {
    let s = bstyle(l, b)
    let raw = apply_transform(l, s, l.boxes.items[usize(b)].text)
    // Each tab may expand to `tab-size` spaces.
    var tabs = 0usize
    var tk = 0usize
    while tk < raw.len {
        if raw[tk] == 9u8 { tabs += 1usize }
        tk += 1usize
    }
    let tab_cells = usize(maxf(1.0f64, s.tab_size))
    let (out, e) = mem.alloc[u8](l.a, raw.len * 2usize + 8usize + tabs * tab_cells)
    if e != ok { ret "" }
    var n = 0usize
    var i = 0usize
    let preserve = s.white_space == .Pre || s.white_space == .PreWrap || s.white_space == .BreakSpaces
    while i < raw.len {
        let c = raw[i]
        if preserve {
            if c == 13u8 {
                i += 1usize
                continue
            }
            if c == 9u8 {
                var t = 0usize
                let stops = usize(maxf(1.0f64, s.tab_size))
                while t < stops {
                    out[n] = 32u8
                    n += 1usize
                    t += 1usize
                }
                i += 1usize
                continue
            }
            out[n] = c
            n += 1usize
            ends_space.v = false
            i += 1usize
            continue
        }
        if c == 10u8 && s.white_space == .PreLine {
            // Spaces around a preserved newline are removed.
            while n > 0usize && out[n - 1usize] == 32u8 { n -= 1usize }
            out[n] = 10u8
            n += 1usize
            ends_space.v = true
            i += 1usize
            while i < raw.len && (raw[i] == 32u8 || raw[i] == 9u8 || raw[i] == 13u8) { i += 1usize }
            continue
        }
        if is_space_byte(c) {
            if !ends_space.v {
                out[n] = 32u8
                n += 1usize
                ends_space.v = true
            }
            i += 1usize
            continue
        }
        out[n] = c
        n += 1usize
        ends_space.v = false
        i += 1usize
    }
    ret out[..n]
}

// --- Inline formatting context: pieces.

fn font_ad(l: *const Layout, s: *const style.Style) -> (f64, f64) {
    let fm = l.measure.metrics(l.measure.ctx, s)
    let content = fm.ascent + fm.descent
    var lh = content + fm.line_gap
    if s.line_height.kind == .Number { lh = s.line_height.px * s.font_size }
    if s.line_height.kind == .Px { lh = s.line_height.px }
    let half = (lh - content) / 2.0f64
    let asc = text_ascent(s, fm)
    ret (asc + half, lh - (asc + half))
}

// The ascent text is placed with: vertical (non-sideways) text sits on the central baseline, so its glyph box is centred on it.
fn text_ascent(s: *const style.Style, fm: FontMetrics) -> f64 {
    if s.writing_mode == .VerticalRl || s.writing_mode == .VerticalLr { ret (fm.ascent + fm.descent) / 2.0f64 }
    ret fm.ascent
}

type Flow = struct { base: usize, ox: f64, oy: f64 }

// The byte length of the hanging space ending `s[..end]`: U+0020, or another space separator that does not break words
// (U+3000, the U+2000 to U+200A spaces but U+2007, U+1680, U+205F); 0 when it ends otherwise.
fn hang_tail_len(s: str, end: usize) -> usize {
    if end >= 1usize && s[end - 1usize] == 32u8 { ret 1usize }
    if end >= 3usize {
        let a = s[end - 3usize]
        let b = s[end - 2usize]
        let c = s[end - 1usize]
        if a == 227u8 && b == 128u8 && c == 128u8 { ret 3usize }
        if a == 226u8 && b == 128u8 && c >= 128u8 && c <= 138u8 && c != 135u8 { ret 3usize }
        if a == 225u8 && b == 154u8 && c == 128u8 { ret 3usize }
        if a == 226u8 && b == 129u8 && c == 159u8 { ret 3usize }
    }
    ret 0usize
}

// Whether `s` holds a hanging space that is painted (anything but U+0020).
fn has_painted_hang(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] != 32u8 { ret true }
        i += 1usize
    }
    ret false
}

fn emit_text_pieces(bd: *Builder, b: u32, ends_space: *Flag) {
    let l = bd.l
    let s = bstyle(l, b)
    let text = process_text(l, b, ends_space)
    bx(l, b).proc = text
    if text.len == 0usize { ret }
    let preserve = s.white_space == .Pre || s.white_space == .PreWrap || s.white_space == .BreakSpaces
    let wrap = s.white_space != .Nowrap && s.white_space != .Pre
    // Scalars and their byte offsets.
    let (scal, e1) = mem.alloc[u32](l.a, text.len + 1usize)
    let (offs, e2) = mem.alloc[usize](l.a, text.len + 2usize)
    let (opp, e3) = mem.alloc[u8](l.a, text.len + 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret }
    var n = 0usize
    var at = 0usize
    while at < text.len {
        let c0 = text[at]
        var w = 1usize
        var cp = u32(c0)
        if c0 >= 240u8 && at + 3usize < text.len {
            w = 4usize
            cp = (u32(c0 & 7u8) << 18u32) | (u32(text[at + 1usize] & 63u8) << 12u32) | (u32(text[at + 2usize] & 63u8) << 6u32) | u32(text[at + 3usize] & 63u8)
        } else if c0 >= 224u8 && at + 2usize < text.len {
            w = 3usize
            cp = (u32(c0 & 15u8) << 12u32) | (u32(text[at + 1usize] & 63u8) << 6u32) | u32(text[at + 2usize] & 63u8)
        } else if c0 >= 192u8 && at + 1usize < text.len {
            w = 2usize
            cp = (u32(c0 & 31u8) << 6u32) | u32(text[at + 1usize] & 63u8)
        }
        scal[n] = cp
        offs[n] = at
        n += 1usize
        at += w
    }
    offs[n] = text.len
    let lbe = segment.line_breaks(scal[..n], opp[..n + 1usize])
    if lbe != ok {
        var k = 0usize
        while k <= n {
            opp[k] = 0u8
            k += 1usize
        }
    }
    // `hyphens: none` takes the soft hyphens out of the break opportunities.
    let (hyv, has_hyv) = extra_text(s, "hyphens")
    if has_hyv && str.eq(cv.lower(l.a, cv.trim_ws(hyv)), "none") {
        var hk = 1usize
        while hk <= n {
            if scal[hk - 1usize] == 173u32 { opp[hk] = 0u8 }
            hk += 1usize
        }
    }
    var seg = 0usize
    var k = 1usize
    // `line-break: anywhere`: a wrap opportunity after every character.
    let (lbv, has_lbv) = extra_text(s, "line-break")
    let lb_anywhere = has_lbv && str.eq(cv.lower(l.a, cv.trim_ws(lbv)), "anywhere")
    while k <= n {
        // break-all adds a break between any two letters, never before a space.
        // break-spaces: every preserved space can end a line.
        // `anywhere` and `word-break: break-word` count in the intrinsic (min-content) sizes too; `break-word` only when needed.
        let intrinsic_any = bd.cbw < 0.0f64 && (s.overflow_wrap == .Anywhere || s.word_break == .BreakWord)
        let all_here = lb_anywhere || intrinsic_any || (s.word_break == .BreakAll && !(k < n && scal[k] == 32u32)) || (s.white_space == .BreakSpaces && scal[k - 1usize] == 32u32)
        // `break-spaces`: every preserved space is a wrap opportunity of its own and takes up room.
        let bspace = s.white_space == .BreakSpaces && scal[k - 1usize] == 32u32
        let cut_here = k == n || opp[k] != 0u8 || all_here || scal[k - 1usize] == 10u32 || bspace
        let is_nl = scal[k - 1usize] == 10u32
        if cut_here || is_nl {
            var seg_end = k
            var hard = false
            if is_nl {
                hard = true
                seg_end = k - 1usize
            }
            let seg_text = text[offs[seg]..offs[seg_end]]
            // Split the trailing collapsible spaces.
            var content_end = seg_text.len
            // Collapsible spaces end a piece's content; so do the preserved ones of `pre-wrap`, which hang at the line end.
            if !preserve || s.white_space == .PreWrap {
                var more = true
                while more && content_end > 0usize {
                    let hk = hang_tail_len(seg_text, content_end)
                    if hk == 0usize { more = false } else { content_end -= hk }
                }
            }
            let content = seg_text[..content_end]
            let trail_text = seg_text[content_end..]
            var w = text_advance(l, s, content)
            // A piece that ends at a soft hyphen reserves the room of the hyphen it shows when the line ends there.
            if content.len >= 2usize && content[content.len - 2usize] == 194u8 && content[content.len - 1usize] == 173u8 { w += text_advance(l, s, "-") }
            let tr = text_advance(l, s, trail_text)
            if seg_text.len > 0usize {
                // The break after this piece is a soft wrap opportunity when the style wraps.
                var soft = wrap && (k < n || true) && (opp[k] != 0u8 || all_here || bspace)
                // The end of a text run is a break opportunity only after a space (atomics mark the piece before them).
                if k == n { soft = wrap && (trail_text.len > 0usize || seg_text.len == 0usize) }
                push_piece(bd, Piece { kind: .Text, box: b, text: seg_text, w: w, trail: tr, soft: soft, ink: content_end > 0usize || preserve || has_painted_hang(trail_text), start: offs[seg], clen: content_end })
            }
            if hard { push_piece(bd, Piece { kind: .Hard, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: false, ink: true, start: 0usize, clen: 0usize }) }
            seg = k
        }
        k += 1usize
    }
}

fn collect_inline(bd: *Builder, b: u32, ends_space: *Flag) {
    let l = bd.l
    let bb = &l.boxes.items[usize(b)]
    let s = bstyle(l, b)
    if bb.inner == .Text {
        emit_text_pieces(bd, b, ends_space)
        ret
    }
    if bb.inner == .Break {
        push_piece(bd, Piece { kind: .Hard, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: false, ink: true, start: 0usize, clen: 0usize })
        ends_space.v = true
        ret
    }
    if bb.inner == .Marker {
        push_piece(bd, Piece { kind: .Marker, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: false, ink: true, start: 0usize, clen: 0usize })
        ends_space.v = false
        ret
    }
    if !bb.inline_level {
        if s.floating != .None {
            bx(l, b).aux = 0u32
            push_piece(bd, Piece { kind: .Float, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        } else {
            bx(l, b).aux = 0u32
            push_piece(bd, Piece { kind: .Abs, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        }
        ret
    }
    if s.position == .Absolute || s.position == .Fixed {
        push_piece(bd, Piece { kind: .Abs, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        ret
    }
    if bb.inner == .Flow && bb.inline_level {
        // An inline box: its open edge, its children, its close edge.
        resolve_edges(l, b, bd.cbw)
        resolve_margins_fixed(l, b, bd.cbw)
        let bm = bx(l, b)
        let open_w = bm.margin[3usize] + bm.border[3usize] + bm.padding[3usize]
        let close_w = bm.margin[1usize] + bm.border[1usize] + bm.padding[1usize]
        push_piece(bd, Piece { kind: .Open, box: b, text: "", w: open_w, trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        var kid = bx(l, b).first
        while kid != NONE {
            collect_inline(bd, kid, ends_space)
            kid = l.boxes.items[usize(kid)].next
        }
        push_piece(bd, Piece { kind: .Close, box: b, text: "", w: close_w, trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        ret
    }
    // An atomic inline: laid out now, as a block of its own, to learn its size.
    layout_atomic(l, b, bd.cbw, bd.cbh)
    let am = &l.boxes.items[usize(b)]
    let outer_w = am.w + am.margin[1usize] + am.margin[3usize]
    // A break may precede it.
    if bd.pieces.len > 0usize {
        let lastp = bd.pieces.items[bd.pieces.len - 1usize]
        if lastp.kind == .Text || lastp.kind == .Atomic { bd.pieces.items[bd.pieces.len - 1usize].soft = true }
    }
    push_piece(bd, Piece { kind: .Atomic, box: b, text: "", w: outer_w, trail: 0.0f64, soft: true, ink: true, start: 0usize, clen: 0usize })
    ends_space.v = false
}

// --- List markers.

fn alpha_text(l: *const Layout, n: i64, upper: bool) -> str {
    if n <= 0i64 { ret "" }
    var buf: [16]u8 = zero
    var at = 16usize
    var v = n
    while v > 0i64 && at > 0usize {
        v -= 1i64
        at -= 1usize
        var c = u8(97i64 + v % 26i64)
        if upper { c -= 32u8 }
        buf[at] = c
        v = v / 26i64
    }
    let (out, e) = mem.alloc[u8](l.a, 16usize - at)
    if e != ok { ret "" }
    mem.copy[u8](out, buf[at..])
    ret out
}

fn roman_text(l: *const Layout, n: i64, upper: bool) -> str {
    if n <= 0i64 || n >= 4000i64 { ret "" }
    let vals = [_]i64{ 1000i64, 900i64, 500i64, 400i64, 100i64, 90i64, 50i64, 40i64, 10i64, 9i64, 5i64, 4i64, 1i64 }
    let sym = [_]str{ "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" }
    let symu = [_]str{ "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" }
    var out: str = ""
    var v = n
    var i = 0usize
    while i < 13usize {
        while v >= vals[i] {
            var piece = sym[i]
            if upper { piece = symu[i] }
            let (joined, e) = str.concat(l.a, out, piece)
            if e == ok { out = joined }
            v -= vals[i]
        }
        i += 1usize
    }
    ret out
}

fn number_text(l: *const Layout, n: i64, pad: usize) -> str {
    var b = new_text(l.a, 24usize)
    var neg = n < 0i64
    var v = n
    if neg { v = -n }
    var digits: [20]u8 = zero
    var cnt = 0usize
    if v == 0i64 {
        digits[0usize] = 48u8
        cnt = 1usize
    }
    while v > 0i64 {
        digits[cnt] = u8(48i64 + v % 10i64)
        cnt += 1usize
        v = v / 10i64
    }
    if neg { text_put(&b, "-") }
    var z = cnt
    while z < pad {
        text_put(&b, "0")
        z += 1usize
    }
    while cnt > 0usize {
        cnt -= 1usize
        text_put_byte(&b, digits[cnt])
    }
    ret text_take(&b)
}

type TextBuf = struct { b: str.Builder, bad: bool }

fn new_text(a: *mem.Arena, cap: usize) -> TextBuf {
    let (made, e) = str.builder(a, cap)
    var t: TextBuf = zero
    t.b = made
    t.bad = e != ok
    ret t
}

fn text_put(t: *TextBuf, s: str) {
    if t.bad { ret }
    let e = str.push(&t.b, s)
    if e != ok { t.bad = true }
}

fn text_put_byte(t: *TextBuf, c: u8) {
    if t.bad { ret }
    let e = str.push_byte(&t.b, c)
    if e != ok { t.bad = true }
}

fn text_take(t: *TextBuf) -> str {
    if t.bad { ret "" }
    ret str.done(&t.b)
}

// The marker text of a list item for its `list-style-type`, including the gap after it.
fn marker_string(l: *const Layout, b: u32) -> str {
    if l.boxes.items[usize(b)].aux2 == 1u32 { ret l.boxes.items[usize(b)].text }
    let s = bstyle(l, b)
    let kind = s.list_style_type
    var n = i64(l.boxes.items[usize(b)].aux)
    if n >= 2147483648i64 { n -= 4294967296i64 }
    if str.eq(kind, "none") { ret "" }
    if str.eq(kind, "disc") { ret "\xe2\x80\xa2 " }
    if str.eq(kind, "circle") { ret "\xe2\x97\xa6 " }
    if str.eq(kind, "square") { ret "\xe2\x96\xaa " }
    var body: str = ""
    if str.eq(kind, "decimal") {
        body = number_text(l, n, 0usize)
    } else if str.eq(kind, "decimal-leading-zero") {
        body = number_text(l, n, 2usize)
    } else if str.eq(kind, "lower-alpha") || str.eq(kind, "lower-latin") {
        body = alpha_text(l, n, false)
    } else if str.eq(kind, "upper-alpha") || str.eq(kind, "upper-latin") {
        body = alpha_text(l, n, true)
    } else if str.eq(kind, "lower-roman") {
        body = roman_text(l, n, false)
    } else if str.eq(kind, "upper-roman") {
        body = roman_text(l, n, true)
    } else if kind.len >= 2usize && kind[0usize] == 34u8 {
        ret kind[1usize..kind.len - 1usize]
    } else {
        body = number_text(l, n, 0usize)
    }
    if body.len == 0usize { ret "" }
    let (joined, e) = str.concat(l.a, body, ". ")
    if e != ok { ret body }
    ret joined
}

// --- Inline layout: lines.

type Open = struct { box: u32, shift: f64, start: f64 }

// The vertical-align shift (down is positive) of an inline box relative to its parent's baseline.
fn valign_shift(l: *const Layout, s: *const style.Style, ps: *const style.Style, a: f64, d: f64, lh: f64) -> f64 {
    let pfm = l.measure.metrics(l.measure.ctx, ps)
    if s.vertical_align == .Baseline || s.vertical_align == .Top || s.vertical_align == .Bottom { ret 0.0f64 }
    if s.vertical_align == .Sub { ret 0.2f64 * ps.font_size }
    if s.vertical_align == .Super { ret -0.33f64 * ps.font_size }
    let pasc = text_ascent(ps, pfm)
    if s.vertical_align == .TextTop { ret a - pasc }
    if s.vertical_align == .TextBottom { ret (pfm.ascent + pfm.descent - pasc) - d }
    if s.vertical_align == .Middle { ret -pfm.x_height / 2.0f64 + (a - d) / 2.0f64 }
    // A length or percentage.
    let l2 = s.vertical_align_length
    ret -(l2.px + l2.pct * lh)
}

// The alignment in force on a line: `text-align`, or on the last line (and lines ended by a break) `text-align-last`.
fn line_align_of(l: *Layout, s: *const style.Style, last_line: bool) -> style.TextAlign {
    var align = s.text_align
    if align == .MatchParent { align = .Start }
    if !last_line { ret align }
    if align == .Justify { align = .Start }
    let (tv, has_tv) = extra_text(s, "text-align-last")
    if !has_tv { ret align }
    let v = cv.lower(l.a, cv.trim_ws(tv))
    if str.eq(v, "start") { ret .Start }
    if str.eq(v, "end") { ret .End }
    if str.eq(v, "left") { ret .Left }
    if str.eq(v, "right") { ret .Right }
    if str.eq(v, "center") { ret .Center }
    if str.eq(v, "justify") { ret .Justify }
    ret align
}

fn line_align_x(s: *const style.Style, base: style.TextAlign, last_line: bool, explicit_justify: bool, avail: f64, width: f64, left: f64) -> f64 {
    var align = base
    let rtl = s.direction == .Rtl
    if align == .Start { if rtl { align = .Right } else { align = .Left } }
    if align == .End { if rtl { align = .Left } else { align = .Right } }
    if align == .Justify && last_line && !explicit_justify { if rtl { align = .Right } else { align = .Left } }
    if align == .Justify && explicit_justify { if rtl { align = .Right } else { align = .Left } }
    if align == .Right { ret left + maxf(0.0f64, avail - width) }
    if align == .Center { ret left + maxf(0.0f64, (avail - width) / 2.0f64) }
    ret left
}

fn place_float(l: *Layout, fc: *Flow, f: u32, cbx: f64, cbw: f64, y_min: f64, parent: u32) {
    let fb = bx(l, f)
    let s = bstyle(l, f)
    let outer_w = fb.w + fb.margin[1usize] + fb.margin[3usize]
    let outer_h = fb.h + fb.margin[0usize] + fb.margin[2usize]
    var y = maxf(y_min, float_top_floor(l, fc.base, fc.oy))
    if s.clear == .Left || s.clear == .Both || s.clear == .InlineStart { y = maxf(y, float_bottom(l, fc.base, 0u32, y)) }
    if s.clear == .Right || s.clear == .Both || s.clear == .InlineEnd { y = maxf(y, float_bottom(l, fc.base, 1u32, y)) }
    var guard = 0usize
    while guard < 256usize {
        guard += 1usize
        let lx = float_edge_left(l, fc.base, y, y + outer_h, cbx)
        let rx = float_edge_right(l, fc.base, y, y + outer_h, cbx + cbw)
        if rx - lx + 0.001f64 >= outer_w || outer_h <= 0.0f64 && rx - lx >= 0.0f64 { break }
        let nxt = next_float_end(l, fc.base, y)
        if nxt <= y { break }
        y = nxt
    }
    let lx = float_edge_left(l, fc.base, y, y + outer_h, cbx)
    let rx = float_edge_right(l, fc.base, y, y + outer_h, cbx + cbw)
    var left_side = s.floating == .Left || s.floating == .InlineStart
    var x = lx
    if !left_side { x = rx - outer_w }
    let pushed = list.push[FloatRec](&l.floats, FloatRec { box: f, x: x, y: y, w: outer_w, h: outer_h, left: left_side, root: 0u32 })
    // The float's box position is relative to the container the caller reports; store BFC coordinates in aux fields.
    let pb = &l.boxes.items[usize(parent)]
    fb.x = x + fb.margin[3usize] - fc.ox + pb.border[3usize] + pb.padding[3usize]
    fb.y = y + fb.margin[0usize] - fc.oy + pb.border[0usize] + pb.padding[0usize]
    fb.aux = 1u32
    apply_relative(l, f, cbw, -1.0f64)
}


// --- Inline layout: lines.

type Ifc = struct {
    l: *Layout, bd: Builder, cont: u32, cs: *const style.Style, cbw: f64, fc: *Flow,
    y: f64, first_line: bool, open: [64]u32, open_count: usize, sa: f64, sd: f64,
    own: list.List[u32], shift: i64, prev_strong: u8
}

type Scan = struct { restart: bool, end: usize, lead: usize, forced: bool, line_x: f64, avail: f64 }

// Splits piece `j` at the last scalar boundary whose prefix fits `max_w` (at least one scalar). False when it all fits.
fn split_piece(x: *Ifc, j: usize, max_w: f64) -> bool {
    let l = x.l
    let p = x.bd.pieces.items[j]
    if p.kind != .Text || p.clen == 0usize { ret false }
    let s = bstyle(l, p.box)
    let proc = l.boxes.items[usize(p.box)].proc
    var cut = 0usize
    var k = 0usize
    var best = 0usize
    while k < p.clen {
        var w = 1usize
        let c0 = proc[p.start + k]
        if c0 >= 240u8 { w = 4usize } else if c0 >= 224u8 { w = 3usize } else if c0 >= 192u8 { w = 2usize }
        if k + w > p.clen { w = p.clen - k }
        let advance = text_advance(l, s, proc[p.start..p.start + k + w])
        if advance > max_w && best > 0usize { break }
        k += w
        best = k
        if advance > max_w { break }
    }
    cut = best
    if cut == 0usize || cut >= p.clen { ret false }
    let head_w = text_advance(l, s, proc[p.start..p.start + cut])
    let tail_text = proc[p.start + cut..p.start + p.text.len]
    let tail_clen = p.clen - cut
    let tail_w = text_advance(l, s, proc[p.start + cut..p.start + p.clen])
    x.bd.pieces.items[j] = Piece { kind: .Text, box: p.box, text: proc[p.start..p.start + cut], w: head_w, trail: 0.0f64, soft: true, ink: true, start: p.start, clen: cut }
    let inserted = list.insert[Piece](&x.bd.pieces, j + 1usize, Piece { kind: .Text, box: p.box, text: tail_text, w: tail_w, trail: p.trail, soft: p.soft, ink: p.ink, start: p.start + cut, clen: tail_clen })
    ret inserted == ok
}

// Scans one line starting at piece `i`: where it ends, whether a hard break ended it, its bounds beside the floats.
// A float met on the way is placed and the scan asks to restart (the bounds changed).
fn scan_line(x: *Ifc, i: usize) -> Scan {
    let l = x.l
    let cs = x.cs
    var out = Scan { restart: false, end: i, lead: i, forced: false, line_x: 0.0f64, avail: x.cbw }
    let est = maxf(x.sa + x.sd, 1.0f64)
    let fc = x.fc
    let lx = float_edge_left(l, fc.base, fc.oy + x.y, fc.oy + x.y + est, fc.ox) - fc.ox
    let rx = float_edge_right(l, fc.base, fc.oy + x.y, fc.oy + x.y + est, fc.ox + x.cbw) - fc.ox
    var indent = 0.0f64
    if x.first_line { indent = resolve_or(cs.text_indent, x.cbw, 0.0f64) }
    out.line_x = lx + indent
    out.avail = rx - lx - indent
    var pos = 0.0f64
    var last_soft = NONE
    var j = i
    var has_content = false
    while j < x.bd.pieces.len {
        let p = x.bd.pieces.items[j]
        if p.kind == .Float {
            if l.boxes.items[usize(p.box)].aux != 1u32 {
                layout_atomic(l, p.box, x.cbw, x.bd.cbh)
                let fb = &l.boxes.items[usize(p.box)]
                let fw = fb.w + fb.margin[1usize] + fb.margin[3usize]
                if has_content && fw > out.avail - pos + 0.01f64 {
                    j += 1usize
                    continue
                }
                place_float(l, fc, p.box, fc.ox, x.cbw, fc.oy + x.y, x.cont)
                out.restart = true
                ret out
            }
            j += 1usize
            continue
        }
        if p.kind == .Abs {
            // A block-level box's static position is the container's content edge; one that was inline-level follows the line.
            let ab = &l.boxes.items[usize(p.box)]
            let owner = &l.boxes.items[usize(x.cont)]
            if ab.aux == 2u32 {
                j += 1usize
                out.end = j
                continue
            }
            if ab.inline_level || st(l, ab.style).was_inline {
                ab.x = out.line_x + pos
            } else {
                ab.x = 0.0f64
            }
            ab.y = x.y
            if owner.inner == .Flow || owner.inner == .FlowRoot {
                ab.x += owner.border[3usize] + owner.padding[3usize]
                ab.y += owner.border[0usize] + owner.padding[0usize]
            }
            ab.aux = 2u32
            j += 1usize
            out.end = j
            continue
        }
        if p.kind == .Hard {
            out.end = j + 1usize
            out.forced = true
            ret out
        }
        if p.kind == .Open || p.kind == .Close {
            pos += p.w
            j += 1usize
            out.end = j
            continue
        }
        if p.kind == .Text && !has_content && p.w == 0.0f64 && !p.ink {
            j += 1usize
            out.lead = j
            out.end = j
            continue
        }
        var needed = p.w
        if p.kind == .Marker {
            needed = text_advance(l, bstyle(l, p.box), marker_string(l, p.box))
        }
        // Preserved spaces at the end of a pre-wrap line hang: they never make the line overflow.
        var hangs = false
        if p.kind == .Text && has_content && bstyle(l, p.box).white_space == .PreWrap {
            hangs = p.text.len > 0usize
            var hi = 0usize
            while hi < p.text.len && hangs {
                if p.text[hi] != 32u8 { hangs = false }
                hi += 1usize
            }
        }
        if hangs { needed = 0.0f64 }
        // Nothing fits beside the floats: the line moves down to where they end (CSS 2.1 9.5).
        if pos + needed > out.avail + 0.01f64 && !has_content && (lx > 0.0f64 || rx < x.cbw - 0.01f64) && !(p.kind == .Text && (cs.overflow_wrap != .Normal || cs.word_break == .BreakWord)) {
            let below = next_float_end(l, fc.base, fc.oy + x.y)
            if below > fc.oy + x.y + 0.01f64 {
                x.y = below - fc.oy
                out.restart = true
                ret out
            }
        }
        if pos + needed > out.avail + 0.01f64 && has_content {
            if last_soft != NONE {
                out.end = usize(last_soft) + 1usize
                ret out
            }
            if p.kind == .Text && (cs.overflow_wrap != .Normal || cs.word_break == .BreakWord) {
                if split_piece(x, j, out.avail - pos) { continue }
            }
        } else if pos + needed > out.avail + 0.01f64 && !has_content && p.kind == .Text && (cs.overflow_wrap != .Normal || cs.word_break == .BreakWord) {
            if split_piece(x, j, out.avail) { continue }
        }
        has_content = has_content || p.ink || p.kind == .Atomic || p.kind == .Marker
        if hangs { pos += p.w } else { pos += needed }
        if p.soft { last_soft = u32(j) }
        pos += p.trail
        j += 1usize
        out.end = j
    }
    ret out
}

// The room of the hyphen a text piece reserves for a soft hyphen at its end (0 when it does not end in one).
fn shy_hyphen_w(l: *Layout, p: Piece) -> f64 {
    if p.kind != .Text || p.clen < 2usize { ret 0.0f64 }
    let proc = l.boxes.items[usize(p.box)].proc
    if p.start + p.clen > proc.len { ret 0.0f64 }
    if proc[p.start + p.clen - 2usize] == 194u8 && proc[p.start + p.clen - 1usize] == 173u8 { ret text_advance(l, bstyle(l, p.box), "-") }
    ret 0.0f64
}

fn flush_text_frag(l: *Layout, bxid: u32, x: f64, text: str, w: f64, shift: f64, baseline: f64) {
    if bxid == NONE || text.len == 0usize { ret }
    let fm = l.measure.metrics(l.measure.ctx, bstyle(l, bxid))
    var shown = text
    var shown_w = w
    // A line that ends at a soft hyphen shows a hyphen there.
    if text.len >= 2usize && text[text.len - 2usize] == 194u8 && text[text.len - 1usize] == 173u8 {
        let (cat_text, ce) = str.concat(l.a, text[..text.len - 2usize], "-")
        if ce == ok {
            shown = cat_text
            shown_w = w
        }
    }
    let pushed = list.push[Frag](&l.frags, Frag { kind: .Text, box: bxid, x: x, y: baseline + shift - text_ascent(bstyle(l, bxid), fm), w: shown_w, h: fm.ascent + fm.descent, text: shown, first: true, last: true })
}

fn emit_segment(l: *Layout, ob: u32, x0: f64, x1: f64, baseline: f64, shift: f64, first: bool, last: bool) {
    let obm = &l.boxes.items[usize(ob)]
    let fm = l.measure.metrics(l.measure.ctx, bstyle(l, ob))
    var top_edge = obm.padding[0usize] + obm.border[0usize]
    var bottom_edge = obm.padding[2usize] + obm.border[2usize]
    let pushed = list.push[Frag](&l.frags, Frag { kind: .Segment, box: ob, x: x0, y: baseline + shift - text_ascent(bstyle(l, ob), fm) - top_edge, w: x1 - x0, h: fm.ascent + fm.descent + top_edge + bottom_edge, text: "", first: first, last: last })
}

// Lays out the pieces of an inline formatting context into lines of `cont`. Returns the content height.
fn layout_inline_content(l: *Layout, cont: u32, cbw: f64, cbh: f64, fc: *Flow) -> f64 {
    let cs = bstyle(l, cont)
    let (made, me) = list.init[Piece](l.a, 32usize)
    if me != ok { ret 0.0f64 }
    var bd = Builder { l: l, pieces: made, last_space: true, ws_pending: false, cbw: cbw, cbh: cbh }
    var ends = Flag { v: true, cleared: false }
    var kid = l.boxes.items[usize(cont)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker && !kb.inline_level {
            kid = kb.next
            continue
        }
        collect_inline(&bd, kid, &ends)
        kid = l.boxes.items[usize(kid)].next
    }
    l.boxes.items[usize(cont)].line_first = NONE
    l.boxes.items[usize(cont)].line_count = 0u32
    if bd.pieces.len == 0usize { ret 0.0f64 }
    let (sa, sd) = font_ad(l, cs)
    let (own_made, own_error) = list.init[u32](l.a, 16usize)
    if own_error != ok { ret 0.0f64 }
    var x = Ifc { l: l, bd: bd, cont: cont, cs: cs, cbw: cbw, fc: fc, y: 0.0f64, first_line: true, open: zero, open_count: 0usize, sa: sa, sd: sd, own: own_made, shift: 0i64, prev_strong: 0u8 }
    var i = 0usize
    var guard = 0usize
    while i < x.bd.pieces.len && guard < 400000usize {
        guard += 1usize
        let scan = scan_line(&x, i)
        if scan.restart { continue }
        var end = scan.end
        if end <= i { end = i + 1usize }
        let lh = emit_line(&x, scan, end)
        end = usize(i64(end) + x.shift)
        // Floats that waited for this line are placed below it.
        var df = scan.lead
        while df < end {
            let p2 = x.bd.pieces.items[df]
            if p2.kind == .Float && l.boxes.items[usize(p2.box)].aux != 1u32 {
                place_float(l, fc, p2.box, fc.ox, cbw, fc.oy + x.y + lh, cont)
            }
            df += 1usize
        }
        if lh >= 0.0f64 {
            x.y += lh
            x.first_line = false
        }
        i = end
    }
    // `line-clamp` / `-webkit-line-clamp`: only the first N lines stay, the last one marked to end with an ellipsis.
    var n_own = x.own.len
    var end_y = x.y
    var clamp_n = line_clamp_count(cs)
    if clamp_n == 0usize && n_own > 1usize && line_clamp_is_auto(cs) {
        // `line-clamp: auto` keeps the lines that fit the container's `max-height`, and at least one.
        let (mxv, has_mx) = resolve_len(cs.max_height, cbh)
        if cs.max_height.kind == .Px && has_mx {
            let room = to_content_h(l, cont, mxv)
            let top = l.lines.items[usize(x.own.items[0usize])].y
            var fit = 1usize
            while fit < n_own {
                let nl = &l.lines.items[usize(x.own.items[fit])]
                if nl.y + nl.h - top > room + 0.001f64 { break }
                fit += 1usize
            }
            if fit < n_own { clamp_n = fit }
        }
    }
    if clamp_n > 0usize && n_own > clamp_n {
        n_own = clamp_n
        let kept = &l.lines.items[usize(x.own.items[clamp_n - 1usize])]
        kept.overflow_ellipsis = true
        end_y = kept.y + kept.h
    }
    // The container's own lines, contiguous: lines of inline-blocks laid out in between are not part of its range.
    if n_own > 0usize {
        let first_own = usize(x.own.items[0usize])
        if usize(x.own.items[n_own - 1usize]) - first_own + 1usize == n_own {
            l.boxes.items[usize(cont)].line_first = u32(first_own)
        } else {
            let start = l.lines.len
            var q = 0usize
            while q < n_own {
                let copy = l.lines.items[usize(x.own.items[q])]
                let pushed = list.push[Line](&l.lines, copy)
                q += 1usize
            }
            l.boxes.items[usize(cont)].line_first = u32(start)
        }
        l.boxes.items[usize(cont)].line_count = u32(n_own)
    }
    ret end_y
}

// Whether `line-clamp` is `auto` (the lines that fit `max-height`).
fn line_clamp_is_auto(s: *const style.Style) -> bool {
    var i = 0usize
    var auto = false
    while i < s.extras.len {
        if str.eq(s.extras[i].name, "line-clamp") { auto = str.eq(str.trim(s.extras[i].value), "auto") }
        i += 1usize
    }
    ret auto
}

// The line count of `line-clamp` (or `-webkit-line-clamp`), 0 when there is none.
fn line_clamp_count(s: *const style.Style) -> usize {
    var text: str = ""
    var found = false
    var i = 0usize
    while i < s.extras.len {
        if str.eq(s.extras[i].name, "line-clamp") || str.eq(s.extras[i].name, "-webkit-line-clamp") {
            text = s.extras[i].value
            found = true
        }
        i += 1usize
    }
    if !found { ret 0usize }
    let t = str.trim(text)
    let (n, ne) = str.parse_i64(t)
    if ne == ok && n > 0i64 { ret usize(n) }
    // `line-clamp: <n> <block-ellipsis>`
    var sp = 0usize
    while sp < t.len && t[sp] != 32u8 { sp += 1usize }
    let (n2, ne2) = str.parse_i64(t[0usize..sp])
    if ne2 == ok && n2 > 0i64 { ret usize(n2) }
    ret 0usize
}

// Vertical metrics and fragments of the line made of pieces[scan.lead..end). Returns the line height, or -1 for a line
// that held nothing to draw (only floats, absolutes or empty inline boxes).
// Visual order of a line (UAX #9 over the characters of its pieces, inline boxes included). A box's `direction` and
// `unicode-bidi` stand in the paragraph as the formatting characters they mean (`bidi_marks`). Words are cut at level
// changes and from their trailing space, put in visual order, and the boxes are opened and closed again around the
// words they hold; a box that visual order splits becomes several fragments, the edges on the outermost ones.
//
// `unicode-bidi` flags: 1 embed, 2 isolate, 4 override, 8 plaintext.
fn bidi_flags(l: *const Layout, s: *const style.Style) -> u8 {
    let (v, has) = extra_text(s, "unicode-bidi")
    if !has { ret 0u8 }
    let t = cv.lower(l.a, cv.trim_ws(v))
    var f = 0u8
    if str.contains(t, "plaintext") { f = f | 8u8 }
    if str.contains(t, "embed") { f = f | 1u8 }
    if str.contains(t, "isolate") { f = f | 2u8 }
    if str.contains(t, "override") { f = f | 4u8 }
    ret f
}

// The characters that open (or close) a box with these flags, and how many.
fn bidi_marks(flags: u8, rtl: bool, closing: bool, out: []u32) -> usize {
    var n = 0usize
    if (flags & 8u8) != 0u8 {
        if closing { out[0usize] = 8297u32 } else { out[0usize] = 8296u32 }
        ret 1usize
    }
    if !closing {
        if (flags & 2u8) != 0u8 {
            if rtl { out[n] = 8295u32 } else { out[n] = 8294u32 }
            n += 1usize
        }
        if (flags & 1u8) != 0u8 {
            if rtl { out[n] = 8235u32 } else { out[n] = 8234u32 }
            n += 1usize
        }
        if (flags & 4u8) != 0u8 {
            if rtl { out[n] = 8238u32 } else { out[n] = 8237u32 }
            n += 1usize
        }
    } else {
        if (flags & 5u8) != 0u8 {
            out[n] = 8236u32
            n += 1usize
        }
        if (flags & 2u8) != 0u8 {
            out[n] = 8297u32
            n += 1usize
        }
    }
    ret n
}

fn bidi_is_rtl_mark(cp: u32) -> bool { ret cp == 8235u32 || cp == 8238u32 || cp == 8295u32 || cp == 8296u32 }

fn bidi_index_of(items: []const u32, n: usize, b: u32) -> usize {
    var i = 0usize
    while i < n {
        if items[i] == b { ret i }
        i += 1usize
    }
    ret n
}

// A visual run: bytes [a, b) of piece `piece` (relative to the line), all at one level, all word or all trailing space.
type BidiItem = struct { piece: usize, a: usize, b: usize, level: u8, trail: bool }

type BidiOut = struct {
    out: list.List[Piece], stk: [64]u32, ns: usize,
    inset: [64]u32, nset: usize, has_open: [64]bool, has_close: [64]bool, open_w: [64]f64, close_w: [64]f64
}

fn bidi_open_box(o: *BidiOut, b: u32) {
    let pushed = list.push[Piece](&o.out, Piece { kind: .Open, box: b, text: "", w: 0.0f64, trail: 0.0f64, soft: true, ink: false, start: 0usize, clen: 0usize })
    if o.ns < 64usize {
        o.stk[o.ns] = b
        o.ns += 1usize
    }
}

fn bidi_close_box(o: *BidiOut) {
    if o.ns == 0usize { ret }
    o.ns -= 1usize
    let pushed = list.push[Piece](&o.out, Piece { kind: .Close, box: o.stk[o.ns], text: "", w: 0.0f64, trail: 0.0f64, soft: true, ink: false, start: 0usize, clen: 0usize })
}

// Leaves exactly the boxes of `chain` (outermost first) open.
fn bidi_enter(o: *BidiOut, chain: []const u32, m: usize) {
    var k = 0usize
    while k < o.ns && k < m && o.stk[k] == chain[k] { k += 1usize }
    while o.ns > k { bidi_close_box(o) }
    while k < m {
        bidi_open_box(o, chain[k])
        k += 1usize
    }
}

// The boxes of the line that hold box `b`, outermost first.
fn bidi_chain(l: *const Layout, cont: u32, b: u32, o: *const BidiOut, out: []u32) -> usize {
    var tmp: [64]u32 = zero
    var m = 0usize
    var q = l.boxes.items[usize(b)].parent
    while q != NONE && q != cont && m < 64usize {
        if bidi_index_of(o.inset[0usize..], o.nset, q) < o.nset {
            tmp[m] = q
            m += 1usize
        }
        q = l.boxes.items[usize(q)].parent
    }
    var i = 0usize
    while i < m {
        out[i] = tmp[m - 1usize - i]
        i += 1usize
    }
    ret m
}

fn inline_depth(l: *const Layout, cont: u32, b: u32) -> usize {
    var d = 0usize
    var q = b
    while q != NONE && q != cont {
        d += 1usize
        q = l.boxes.items[usize(q)].parent
    }
    ret d
}

// L4 for bytes [from, to) of box `b`'s processed text: mirrored characters of the same width are swapped in a private copy.
fn bidi_mirror(l: *Layout, b: u32, from: usize, to: usize) {
    let proc = l.boxes.items[usize(b)].proc
    if to > proc.len { ret }
    var need = false
    var at = from
    while at < to {
        let (cp, w) = unicode.read_utf8(proc, at)
        if bidi.is_mirrored(cp) { need = true }
        at += w
    }
    if !need { ret }
    let (copy, e) = mem.alloc[u8](l.a, proc.len)
    if e != ok { ret }
    mem.copy[u8](copy, proc)
    at = from
    while at < to {
        let (cp, w) = unicode.read_utf8(proc, at)
        if bidi.is_mirrored(cp) {
            let (n, ee) = utf8.encode(bidi.mirror(cp), copy[at..])
            if ee != ok || usize(n) != w {
                let (rn, re2) = utf8.encode(cp, copy[at..])
            }
        }
        at += w
    }
    l.boxes.items[usize(b)].proc = copy
}

// Emits one visual run (and the box boundaries before it).
fn bidi_emit_item(x: *Ifc, o: *BidiOut, lead: usize, it: BidiItem) {
    let l = x.l
    let p = x.bd.pieces.items[lead + it.piece]
    var chain: [64]u32 = zero
    var m = bidi_chain(l, x.cont, p.box, o, chain[0usize..])
    if p.kind == .Open && m < 64usize {
        chain[m] = p.box
        m += 1usize
    }
    bidi_enter(o, chain[0usize..], m)
    if p.kind == .Open {
        ret
    }
    if p.kind != .Text {
        let pushed = list.push[Piece](&o.out, p)
        ret
    }
    if it.level % 2u8 == 1u8 { bidi_mirror(l, p.box, p.start + it.a, p.start + it.b) }
    let proc = l.boxes.items[usize(p.box)].proc
    let s = bstyle(l, p.box)
    let slice = proc[p.start + it.a..p.start + it.b]
    if it.trail {
        var tw = p.trail
        if it.a != p.clen || it.b != p.text.len { tw = text_advance(l, s, slice) }
        let pushed = list.push[Piece](&o.out, Piece { kind: .Text, box: p.box, text: slice, w: 0.0f64, trail: tw, soft: false, ink: false, start: p.start + it.a, clen: 0usize })
        ret
    }
    var w = p.w
    if it.a != 0usize || it.b != p.clen {
        w = text_advance(l, s, slice)
        let cut = Piece { kind: .Text, box: p.box, text: slice, w: w, trail: 0.0f64, soft: false, ink: p.ink, start: p.start + it.a, clen: it.b - it.a }
        w += shy_hyphen_w(l, cut)
    }
    let pushed = list.push[Piece](&o.out, Piece { kind: .Text, box: p.box, text: slice, w: w, trail: 0.0f64, soft: p.soft && it.b == p.clen, ink: p.ink, start: p.start + it.a, clen: it.b - it.a })
}

fn bidi_order_pieces(x: *Ifc, lead: usize, tail: usize) -> (bool, usize) {
    let l = x.l
    let n = tail - lead
    if n < 1usize { ret (false, tail) }
    var cap = x.open_count * 3usize + 80usize
    var j = lead
    while j < tail {
        let p = x.bd.pieces.items[j]
        if p.kind == .Marker { ret (false, tail) }
        if p.kind == .Text { cap += p.text.len + 1usize } else { cap += 4usize }
        j += 1usize
    }
    let (text32, e1) = mem.alloc[u32](l.a, cap)
    let (ownp, e2) = mem.alloc[u32](l.a, cap)
    let (owno, e3) = mem.alloc[u32](l.a, cap)
    let (levels, e4) = mem.alloc[u8](l.a, cap)
    let (scratch, e5) = mem.alloc[u32](l.a, 6usize * cap + 6usize)
    let (cord, e6) = mem.alloc[usize](l.a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (false, tail) }
    let (made, me) = list.init[Piece](l.a, n + 8usize)
    if me != ok { ret (false, tail) }
    var o = BidiOut { out: made, stk: zero, ns: 0usize, inset: zero, nset: 0usize, has_open: zero, has_close: zero, open_w: zero, close_w: zero }
    var marks: [4]u32 = zero
    var total = 0usize
    var rtl_seen = x.cs.direction == .Rtl
    var base = 0i8
    if x.cs.direction == .Rtl { base = 1i8 }
    let cflags = bidi_flags(l, x.cs)
    if (cflags & 8u8) != 0u8 { base = -1i8 }
    if (cflags & 4u8) != 0u8 {
        if x.cs.direction == .Rtl { text32[total] = 8238u32 } else { text32[total] = 8237u32 }
        ownp[total] = NONE
        owno[total] = 0u32
        total += 1usize
        if x.cs.direction == .Rtl { rtl_seen = true }
    }
    // The boxes already open at the start of the line come first.
    var c = 0usize
    while c < x.open_count && o.nset < 64usize {
        let ob = x.open[c]
        o.inset[o.nset] = ob
        o.nset += 1usize
        let os = bstyle(l, ob)
        let mn = bidi_marks(bidi_flags(l, os), os.direction == .Rtl, false, marks[0usize..])
        var mi = 0usize
        while mi < mn {
            text32[total] = marks[mi]
            ownp[total] = NONE
            owno[total] = 0u32
            total += 1usize
            if bidi_is_rtl_mark(marks[mi]) { rtl_seen = true }
            mi += 1usize
        }
        c += 1usize
    }
    // The text before the line is context for its levels: what the last line ended on.
    var seg_start = total
    if x.prev_strong != 0u8 {
        if x.prev_strong == 2u8 { text32[total] = 1488u32 } else { text32[total] = 97u32 }
        ownp[total] = NONE
        owno[total] = 0u32
        total += 1usize
        seg_start = total
    }
    var last_strong = 0u8
    j = 0usize
    while j < n {
        let p = x.bd.pieces.items[lead + j]
        if p.kind == .Text {
            var tlen = p.text.len
            // The last word of the line loses its trailing space, wherever it ends up.
            if j + 1usize == n { tlen = p.clen }
            var at = 0usize
            while at < tlen {
                let (cp, w) = unicode.read_utf8(p.text, at)
                text32[total] = cp
                ownp[total] = u32(j)
                owno[total] = u32(at)
                total += 1usize
                let cls = bidi.class_of(cp)
                if cls == .R || cls == .AL || cls == .AN { rtl_seen = true }
                if cls == .L { last_strong = 1u8 }
                if cls == .R || cls == .AL { last_strong = 2u8 }
                at += w
            }
        } else if p.kind == .Open || p.kind == .Close {
            let si0 = bidi_index_of(o.inset[0usize..], o.nset, p.box)
            var si = si0
            if si0 >= o.nset && o.nset < 64usize {
                o.inset[o.nset] = p.box
                si = o.nset
                o.nset += 1usize
            }
            if si >= 64usize { ret (false, tail) }
            let bs = bstyle(l, p.box)
            let bf = bidi_flags(l, bs)
            let empty = p.kind == .Open && j + 1usize < n && x.bd.pieces.items[lead + j + 1usize].kind == .Close && x.bd.pieces.items[lead + j + 1usize].box == p.box
            if p.kind == .Open {
                o.has_open[si] = true
                o.open_w[si] = p.w
                let mn = bidi_marks(bf, bs.direction == .Rtl, false, marks[0usize..])
                var mi = 0usize
                while mi < mn {
                    text32[total] = marks[mi]
                    ownp[total] = NONE
                    owno[total] = 0u32
                    total += 1usize
                    if bidi_is_rtl_mark(marks[mi]) { rtl_seen = true }
                    mi += 1usize
                }
                if empty {
                    text32[total] = 65532u32
                    ownp[total] = u32(j)
                    owno[total] = 0u32
                    total += 1usize
                }
            } else {
                o.has_close[si] = true
                o.close_w[si] = p.w
                let mn = bidi_marks(bf, bs.direction == .Rtl, true, marks[0usize..])
                var mi = 0usize
                while mi < mn {
                    text32[total] = marks[mi]
                    ownp[total] = NONE
                    owno[total] = 0u32
                    total += 1usize
                    mi += 1usize
                }
            }
        } else {
            // Atomic inlines are objects, a forced break a line separator, floats and absolutes take no room.
            var cp = 65532u32
            if p.kind == .Hard { cp = 8232u32 }
            if p.kind == .Float || p.kind == .Abs { cp = 8203u32 }
            text32[total] = cp
            ownp[total] = u32(j)
            owno[total] = 0u32
            total += 1usize
        }
        j += 1usize
    }
    let seg_end = total
    if last_strong != 0u8 { x.prev_strong = last_strong }
    // And the text after it, up to the first strong character.
    var sj = tail
    var scount = 0usize
    var sfound = false
    while sj < x.bd.pieces.len && scount < 64usize && !sfound {
        let sp = x.bd.pieces.items[sj]
        if sp.kind != .Text { break }
        var sat = 0usize
        while sat < sp.text.len && scount < 64usize && !sfound {
            let (scp, sw) = unicode.read_utf8(sp.text, sat)
            text32[total] = scp
            ownp[total] = NONE
            owno[total] = 0u32
            total += 1usize
            scount += 1usize
            let scls = bidi.class_of(scp)
            if scls == .L || scls == .R || scls == .AL { sfound = true }
            sat += sw
        }
        sj += 1usize
    }
    if total == 0usize || !rtl_seen { ret (false, tail) }
    let (para, re) = bidi.resolve_levels(text32[..total], base, levels[..total], scratch)
    if re != ok { ret (false, tail) }
    let le = bidi.reorder_line(text32[..total], levels[..total], para, seg_start, seg_end, cord)
    if le != ok { ret (false, tail) }
    // Visual runs.
    var cur = BidiItem { piece: 0usize, a: 0usize, b: 0usize, level: 0u8, trail: false }
    var has_cur = false
    var v = 0usize
    while v < seg_end - seg_start {
        let ci = cord[v]
        if ownp[ci] != NONE {
            let pj = usize(ownp[ci])
            let p = x.bd.pieces.items[lead + pj]
            let off = usize(owno[ci])
            var w = 1usize
            var tr = false
            if p.kind == .Text {
                let (cp0, w0) = unicode.read_utf8(p.text, off)
                w = w0
                tr = off >= p.clen
            }
            let lv = levels[ci]
            var extend = false
            if has_cur && cur.piece == pj && cur.level == lv && cur.trail == tr && p.kind == .Text {
                if lv % 2u8 == 0u8 { extend = off == cur.b } else { extend = off + w == cur.a }
            }
            if extend {
                if lv % 2u8 == 0u8 { cur.b = off + w } else { cur.a = off }
            } else {
                if has_cur { bidi_emit_item(x, &o, lead, cur) }
                cur = BidiItem { piece: pj, a: off, b: off + w, level: lv, trail: tr }
                has_cur = true
            }
        }
        v += 1usize
    }
    if has_cur { bidi_emit_item(x, &o, lead, cur) }
    // Close what is open; the boxes that go on past the line open again, outermost first.
    while o.ns > 0usize { bidi_close_box(&o) }
    var done: [64]bool = zero
    var picked = 0usize
    var cont_n = 0usize
    var k = 0usize
    while k < o.nset {
        if !o.has_close[k] { cont_n += 1usize }
        k += 1usize
    }
    while picked < cont_n {
        var best = 64usize
        var best_d = 4294967295usize
        k = 0usize
        while k < o.nset {
            if !o.has_close[k] && !done[k] {
                let d = inline_depth(l, x.cont, o.inset[k])
                if d < best_d {
                    best_d = d
                    best = k
                }
            }
            k += 1usize
        }
        if best >= 64usize { break }
        done[best] = true
        bidi_open_box(&o, o.inset[best])
        picked += 1usize
    }
    // The edges of a box go on its first opening and its last closing.
    k = 0usize
    while k < o.nset {
        let b = o.inset[k]
        if o.has_open[k] {
            var oi = 0usize
            var found = false
            while oi < o.out.len && !found {
                if o.out.items[oi].kind == .Open && o.out.items[oi].box == b {
                    o.out.items[oi].soft = false
                    o.out.items[oi].w = o.open_w[k]
                    found = true
                }
                oi += 1usize
            }
        }
        if o.has_close[k] {
            var ci2 = o.out.len
            var found2 = false
            while ci2 > 0usize && !found2 {
                ci2 -= 1usize
                if o.out.items[ci2].kind == .Close && o.out.items[ci2].box == b {
                    o.out.items[ci2].soft = false
                    o.out.items[ci2].w = o.close_w[k]
                    found2 = true
                }
            }
        }
        k += 1usize
    }
    // Put the new pieces where the line's were.
    let m = o.out.len
    if m > n {
        let grown = list.reserve[Piece](&x.bd.pieces, x.bd.pieces.len + (m - n))
        if grown != ok { ret (false, tail) }
        var s = x.bd.pieces.len
        while s > tail {
            s -= 1usize
            x.bd.pieces.items[s + (m - n)] = x.bd.pieces.items[s]
        }
        x.bd.pieces.len += m - n
    } else if m < n {
        var s = tail
        while s < x.bd.pieces.len {
            x.bd.pieces.items[s - (n - m)] = x.bd.pieces.items[s]
            s += 1usize
        }
        x.bd.pieces.len -= n - m
    }
    var q = 0usize
    while q < m {
        x.bd.pieces.items[lead + q] = o.out.items[q]
        q += 1usize
    }
    x.open_count = 0usize
    ret (true, lead + m)
}

fn emit_line(x: *Ifc, scan: Scan, end0: usize) -> f64 {
    let l = x.l
    let cs = x.cs
    let lead = scan.lead
    var end = end0
    var trim_end = end
    while trim_end > lead && x.bd.pieces.items[trim_end - 1usize].kind == .Text && !x.bd.pieces.items[trim_end - 1usize].ink && x.bd.pieces.items[trim_end - 1usize].w == 0.0f64 { trim_end -= 1usize }
    x.shift = 0i64
    let (tail_keep, new_tail) = bidi_order_pieces(x, lead, trim_end)
    if tail_keep {
        x.shift = i64(new_tail) - i64(trim_end)
        end = usize(i64(end) + x.shift)
        trim_end = new_tail
    }
    // The last piece that takes room on the line: spaces that end it hang (boxes closing after it do not count).
    var last_content = lead
    var lcj = lead
    while lcj < trim_end {
        let lck = x.bd.pieces.items[lcj].kind
        if lck == .Text || lck == .Atomic || lck == .Marker { last_content = lcj }
        lcj += 1usize
    }
    // Inline-box stack: the boxes carried in, then those opened on this line.
    var sbox: [64]u32 = zero
    var sshift: [64]f64 = zero
    var sx: [64]f64 = zero
    var sfirst: [64]bool = zero
    var sp = 0usize
    var c = 0usize
    while c < x.open_count && sp < 64usize {
        let ob = x.open[c]
        let obs = bstyle(l, ob)
        let (oa, od) = font_ad(l, obs)
        var psh = 0.0f64
        if sp > 0usize { psh = sshift[sp - 1usize] }
        sbox[sp] = ob
        sshift[sp] = psh + valign_shift(l, obs, bstyle(l, l.boxes.items[usize(ob)].parent), oa, od, oa + od)
        sfirst[sp] = false
        sp += 1usize
        c += 1usize
    }
    let carried = sp
    // Extents.
    var top = -x.sa
    var bottom = x.sd
    var any_content = false
    var tb_h: [16]f64 = zero
    var tb_top: [16]bool = zero
    var tb_n = 0usize
    var k = 0usize
    while k < carried {
        let (oa, od) = font_ad(l, bstyle(l, sbox[k]))
        top = minf(top, sshift[k] - oa)
        bottom = maxf(bottom, sshift[k] + od)
        k += 1usize
    }
    var sim = sp
    k = lead
    while k < end {
        let p = x.bd.pieces.items[k]
        if p.kind == .Open {
            let obs = bstyle(l, p.box)
            let (oa, od) = font_ad(l, obs)
            var psh = 0.0f64
            if sim > 0usize { psh = sshift[sim - 1usize] }
            if sim < 64usize {
                sbox[sim] = p.box
                sshift[sim] = psh + valign_shift(l, obs, bstyle(l, l.boxes.items[usize(p.box)].parent), oa, od, oa + od)
                top = minf(top, sshift[sim] - oa)
                bottom = maxf(bottom, sshift[sim] + od)
                sim += 1usize
            }
        } else if p.kind == .Close {
            if sim > 0usize { sim -= 1usize }
        } else if (p.kind == .Text && k < trim_end) || p.kind == .Marker {
            if p.ink { any_content = true }
            let (ta, td) = font_ad(l, bstyle(l, p.box))
            var sh = 0.0f64
            if sim > 0usize { sh = sshift[sim - 1usize] }
            let va_owner = va_edge_owner(l, p.box, x.cont)
            if va_owner != NONE && tb_n < 16usize {
                let (sa, sd) = subtree_ad(l, va_owner)
                tb_h[tb_n] = sa + sd
                tb_top[tb_n] = bstyle(l, va_owner).vertical_align == .Top
                tb_n += 1usize
            } else {
                top = minf(top, sh - ta)
                bottom = maxf(bottom, sh + td)
            }
        } else if p.kind == .Atomic {
            any_content = true
            let ab = &l.boxes.items[usize(p.box)]
            let asty = bstyle(l, p.box)
            let margin_h = ab.h + ab.margin[0usize] + ab.margin[2usize]
            var ba = ab.margin[0usize] + ab.h
            if ab.has_baseline { ba = ab.margin[0usize] + ab.baseline }
            let cws = bstyle(l, x.cont).writing_mode
            if cws == .VerticalRl || cws == .VerticalLr { ba = (ab.h + ab.margin[0usize] + ab.margin[2usize]) / 2.0f64 }
            var sh = 0.0f64
            if sim > 0usize { sh = sshift[sim - 1usize] }
            if asty.vertical_align == .Top || asty.vertical_align == .Bottom {
                if tb_n < 16usize {
                    tb_h[tb_n] = margin_h
                    tb_top[tb_n] = asty.vertical_align == .Top
                    tb_n += 1usize
                }
            } else {
                let ash = sh + valign_shift(l, asty, bstyle(l, ab.parent), ba, margin_h - ba, margin_h)
                top = minf(top, ash - ba)
                bottom = maxf(bottom, ash + (margin_h - ba))
            }
        } else if p.kind == .Hard {
            any_content = true
        }
        k += 1usize
    }
    var t2 = 0usize
    while t2 < tb_n {
        if tb_h[t2] > bottom - top {
            if tb_top[t2] { bottom = top + tb_h[t2] } else { top = bottom - tb_h[t2] }
        }
        t2 += 1usize
    }
    if !any_content { ret -1.0f64 }
    let line_h = bottom - top
    let baseline = -top
    // Width and alignment.
    var used_w = 0.0f64
    k = lead
    while k < trim_end {
        let p = x.bd.pieces.items[k]
        if p.kind == .Marker {
            used_w += text_advance(l, bstyle(l, p.box), marker_string(l, p.box))
        } else {
            used_w += p.w
            if k < last_content || (tail_keep && p.trail > 0.0f64) { used_w -= shy_hyphen_w(l, p) }
        }
        if k < last_content || (tail_keep && p.trail > 0.0f64) { used_w += p.trail }
        k += 1usize
    }
    let last_line = end >= x.bd.pieces.len
    let hard = scan.forced
    let end_line = last_line || hard
    let line_align = line_align_of(l, cs, end_line)
    let justify_last = end_line && line_align == .Justify
    let ax = line_align_x(cs, line_align, end_line, justify_last, scan.avail, used_w, scan.line_x)
    // Where an inline-level absolutely positioned box sat on the line: after the content before it, which in a right-to-left line is to its right.
    var abs_off = 0.0f64
    k = lead
    while k < end {
        let ap = x.bd.pieces.items[k]
        if ap.kind == .Abs {
            let ab = &l.boxes.items[usize(ap.box)]
            if (ab.inline_level || st(l, ab.style).was_inline) && ab.aux == 2u32 {
                let owner = &l.boxes.items[usize(x.cont)]
                var nx = ax + abs_off
                if cs.direction == .Rtl && !tail_keep { nx = ax + used_w - abs_off }
                if owner.inner == .Flow || owner.inner == .FlowRoot { nx += owner.border[3usize] + owner.padding[3usize] }
                ab.x = nx
            }
        } else if k < trim_end {
            abs_off += ap.w
            if k < last_content || (tail_keep && ap.trail > 0.0f64) { abs_off += ap.trail }
        }
        k += 1usize
    }
    var spread = 0.0f64
    if line_align == .Justify && scan.avail > used_w {
        var gaps = 0usize
        k = lead
        while k < trim_end {
            if (k < last_content || tail_keep) && x.bd.pieces.items[k].trail > 0.0f64 { gaps += 1usize }
            k += 1usize
        }
        if gaps > 0usize { spread = (scan.avail - used_w) / f64(gaps) }
    }
    // Fragments.
    let first_frag = u32(l.frags.len)
    sp = carried
    var s_x: [64]f64 = zero
    var si = 0usize
    while si < carried {
        s_x[si] = ax
        si += 1usize
    }
    var cx = ax
    var tf_box = NONE
    var tf_start = 0.0f64
    var tf_from = 0usize
    var tf_to = 0usize
    var tf_w = 0.0f64
    var tf_shift = 0.0f64
    k = lead
    while k < end {
        let p = x.bd.pieces.items[k]
        if p.kind == .Text {
            if k >= trim_end {
                k += 1usize
                continue
            }
            var cur_shift = 0.0f64
            if sp > 0usize { cur_shift = sshift[sp - 1usize] }
            let va_owner = va_edge_owner(l, p.box, x.cont)
            if va_owner != NONE {
                let (sa, sd) = subtree_ad(l, va_owner)
                if bstyle(l, va_owner).vertical_align == .Top { cur_shift = sa - baseline } else { cur_shift = line_h - sd - baseline }
            }
            let proc = l.boxes.items[usize(p.box)].proc
            var this_to = p.start + p.text.len
            var this_w = p.w
            if k < last_content || (tail_keep && p.trail > 0.0f64) {
                this_w -= shy_hyphen_w(l, p)
                this_w += p.trail
                if p.trail > 0.0f64 { this_w += spread }
            } else {
                this_to = p.start + p.clen
                // A hanging space separator at the line end is painted but takes no room in the line.
                let hang_text = proc[p.start + p.clen..p.start + p.text.len]
                if hang_text.len > 0usize && (has_painted_hang(hang_text) || bstyle(l, p.box).white_space == .PreWrap) {
                    this_to = p.start + p.text.len
                    this_w += text_advance(l, bstyle(l, p.box), hang_text)
                }
            }
            if tf_box == p.box && tf_to == p.start && cur_shift == tf_shift && spread == 0.0f64 && !tail_keep {
                tf_to = this_to
                tf_w += this_w
            } else {
                if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
                tf_box = p.box
                tf_start = cx
                tf_from = p.start
                tf_to = this_to
                tf_w = this_w
                tf_shift = cur_shift
            }
            cx += this_w
        } else if p.kind == .Marker {
            if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
            tf_box = NONE
            let mtxt = marker_string(l, p.box)
            let mw = text_advance(l, bstyle(l, p.box), mtxt)
            flush_text_frag(l, p.box, cx, mtxt, mw, 0.0f64, baseline)
            cx += mw
        } else if p.kind == .Open {
            if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
            tf_box = NONE
            let ob = p.box
            let obm = &l.boxes.items[usize(ob)]
            if !p.soft { cx += obm.margin[3usize] }
            if sp < 64usize {
                let obs = bstyle(l, ob)
                let (oa, od) = font_ad(l, obs)
                var psh = 0.0f64
                if sp > 0usize { psh = sshift[sp - 1usize] }
                sbox[sp] = ob
                sshift[sp] = psh + valign_shift(l, obs, bstyle(l, obm.parent), oa, od, oa + od)
                s_x[sp] = cx
                sfirst[sp] = !p.soft
                sp += 1usize
            }
            if !p.soft { cx += obm.border[3usize] + obm.padding[3usize] }
        } else if p.kind == .Close {
            if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
            tf_box = NONE
            let ob = p.box
            let obm = &l.boxes.items[usize(ob)]
            if !p.soft { cx += obm.padding[1usize] + obm.border[1usize] }
            if sp > 0usize {
                sp -= 1usize
                emit_segment(l, ob, s_x[sp], cx, baseline, sshift[sp], sfirst[sp], !p.soft)
            }
            if !p.soft { cx += obm.margin[1usize] }
        } else if p.kind == .Atomic {
            if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
            tf_box = NONE
            let ab = &l.boxes.items[usize(p.box)]
            let asty = bstyle(l, p.box)
            let margin_h = ab.h + ab.margin[0usize] + ab.margin[2usize]
            var ba = ab.margin[0usize] + ab.h
            if ab.has_baseline { ba = ab.margin[0usize] + ab.baseline }
            let cws = bstyle(l, x.cont).writing_mode
            if cws == .VerticalRl || cws == .VerticalLr { ba = (ab.h + ab.margin[0usize] + ab.margin[2usize]) / 2.0f64 }
            var sh = 0.0f64
            if sp > 0usize { sh = sshift[sp - 1usize] }
            var margin_top_y = baseline + sh - ba
            if asty.vertical_align == .Top {
                margin_top_y = 0.0f64
            } else if asty.vertical_align == .Bottom {
                margin_top_y = line_h - margin_h
            } else {
                let ash = sh + valign_shift(l, asty, bstyle(l, ab.parent), ba, margin_h - ba, margin_h)
                margin_top_y = baseline + ash - ba
            }
            // The box sits in its parent's border box; the fragment keeps content-box coordinates like the line.
            let fx = cx + ab.margin[3usize]
            let fy = x.y + margin_top_y + ab.margin[0usize]
            let owner = &l.boxes.items[usize(x.cont)]
            ab.x = fx + owner.border[3usize] + owner.padding[3usize]
            ab.y = fy + owner.border[0usize] + owner.padding[0usize]
            ab.aux = 2u32
            let pushed = list.push[Frag](&l.frags, Frag { kind: .Atomic, box: p.box, x: fx, y: fy, w: ab.w, h: ab.h, text: "", first: true, last: true })
            cx += p.w
        }
        k += 1usize
    }
    if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
    // Boxes still open continue on the next line.
    var nxt = 0usize
    var q = 0usize
    var carry: [64]u32 = zero
    while q < sp {
        emit_segment(l, sbox[q], s_x[q], cx, baseline, sshift[q], sfirst[q], false)
        carry[nxt] = sbox[q]
        nxt += 1usize
        q += 1usize
    }
    var z = 0usize
    while z < nxt {
        x.open[z] = carry[z]
        z += 1usize
    }
    x.open_count = nxt
    var fi = usize(first_frag)
    while fi < l.frags.len {
        if l.frags.items[fi].kind != .Atomic { l.frags.items[fi].y += x.y }
        fi += 1usize
    }
    // Relatively positioned inline boxes (and atomics) move with their fragments.
    fi = usize(first_frag)
    while fi < l.frags.len {
        let (rdx, rdy) = relative_chain(l, l.frags.items[fi].box, x.cont, scan.avail)
        if rdx != 0.0f64 || rdy != 0.0f64 {
            l.frags.items[fi].x += rdx
            l.frags.items[fi].y += rdy
            if l.frags.items[fi].kind == .Atomic {
                let rab = &l.boxes.items[usize(l.frags.items[fi].box)]
                rab.x += rdx
                rab.y += rdy
            }
        }
        fi += 1usize
    }
    let overflow = used_w > scan.avail + 0.5f64 && cs.text_overflow == .Ellipsis && cs.overflow_x != .Visible
    let own_index = u32(l.lines.len)
    let own_pushed = list.push[u32](&x.own, own_index)
    let pushed = list.push[Line](&l.lines, Line { x: ax, y: x.y, w: used_w, h: line_h, baseline: x.y + baseline, frag_first: first_frag, frag_count: u32(l.frags.len) - first_frag, overflow_ellipsis: overflow })
    ret line_h
}

// --- Intrinsic widths.

fn replaced_intrinsic(l: *Layout, b: u32) -> Intrinsic {
    ret l.measure.intrinsic(l.measure.ctx, l.boxes.items[usize(b)].node, st(l, l.boxes.items[usize(b)].style))
}

// The default object size of replaced content with no size of its own.
fn default_replaced(i: Intrinsic) -> (f64, f64) {
    var w = 300.0f64
    var h = 150.0f64
    if i.has_width { w = i.width }
    if i.has_height { h = i.height }
    if i.has_width && !i.has_height && i.ratio > 0.0f64 { h = i.width / i.ratio }
    if !i.has_width && i.has_height && i.ratio > 0.0f64 { w = i.height * i.ratio }
    if i.kind == 1u8 && !i.has_width && !i.has_height { ret (0.0f64, 0.0f64) }
    ret (w, h)
}

// A child's outer width for sizing its parent: explicit width, else its content widths, with its edges.
fn outer_content_widths(l: *Layout, c: u32) -> (f64, f64) {
    let s = bstyle(l, c)
    resolve_edges(l, c, 0.0f64)
    resolve_margins_fixed(l, c, 0.0f64)
    let cb = &l.boxes.items[usize(c)]
    let extras = horizontal_extras(cb) + cb.margin[1usize] + cb.margin[3usize]
    var mn = 0.0f64
    var mx = 0.0f64
    let (w, has_w) = resolve_len(s.width, -1.0f64)
    if s.width.kind == .Px && has_w {
        let cw = to_content_w(l, c, w)
        mn = cw
        mx = cw
    } else if cb.inner == .Replaced {
        let (rw, _rh) = default_replaced(replaced_intrinsic(l, c))
        mn = rw
        mx = rw
        if s.width.kind == .Px && s.width.pct != 0.0f64 { mn = 0.0f64 }
    } else {
        let (a, b) = content_widths(l, c)
        mn = a
        mx = b
    }
    mn = clamp_width(l, c, mn, -1.0f64)
    mx = clamp_width(l, c, mx, -1.0f64)
    ret (mn + extras, mx + extras)
}

// The min-content and max-content widths of the content box of `b`.
fn content_widths(l: *Layout, b: u32) -> (f64, f64) {
    let bb = &l.boxes.items[usize(b)]
    if bb.has_c { ret (bb.min_c, bb.max_c) }
    var mn = 0.0f64
    var mx = 0.0f64
    if bb.inner == .Table {
        let (tmn, tmx) = table_widths(l, b)
        mn = tmn
        mx = tmx
    } else if bb.inner == .Flex {
        let (fmn, fmx) = flex_widths(l, b)
        mn = fmn
        mx = fmx
    } else if bb.inner == .Grid {
        let (gmn, gmx) = grid_widths(l, b)
        mn = gmn
        mx = gmx
    } else if has_inline_content(l, b) {
        let (imn, imx) = inline_widths(l, b)
        mn = imn
        mx = imx
    } else {
        var kid = bb.first
        while kid != NONE {
            let kb = &l.boxes.items[usize(kid)]
            if kb.inner != .Marker {
                let (kmn, kmx) = outer_content_widths(l, kid)
                mn = maxf(mn, kmn)
                mx = maxf(mx, kmx)
            }
            kid = l.boxes.items[usize(kid)].next
        }
    }
    let bb2 = bx(l, b)
    bb2.min_c = mn
    bb2.max_c = mx
    bb2.has_c = true
    ret (mn, mx)
}

fn has_inline_content(l: *const Layout, b: u32) -> bool {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inline_level && kb.inner != .Marker { ret true }
        if kb.inner == .Text || kb.inner == .Break { ret true }
        kid = kb.next
    }
    ret false
}

// Min and max content width of an inline formatting context: the widest unbreakable run and the one-line width.
fn inline_widths(l: *Layout, cont: u32) -> (f64, f64) {
    let (made, me) = list.init[Piece](l.a, 32usize)
    if me != ok { ret (0.0f64, 0.0f64) }
    var bd = Builder { l: l, pieces: made, last_space: true, ws_pending: false, cbw: -1.0f64, cbh: -1.0f64 }
    var ends = Flag { v: true, cleared: false }
    var kid = l.boxes.items[usize(cont)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner != .Marker {
            if kb.inline_level || kb.inner == .Text || kb.inner == .Break || (bstyle(l, kid).floating != .None && !is_abs_positioned(bstyle(l, kid))) { collect_inline_intrinsic(&bd, kid, &ends) }
        }
        kid = l.boxes.items[usize(kid)].next
    }
    var mn = 0.0f64
    var line = 0.0f64
    var mx = 0.0f64
    var run = 0.0f64
    var tail_trail = 0.0f64
    var i = 0usize
    while i < bd.pieces.len {
        let p = bd.pieces.items[i]
        i += 1usize
        if p.kind == .Hard {
            // A line's trailing collapsible space hangs: it is not part of the line's width.
            mx = maxf(mx, line - tail_trail)
            mn = maxf(mn, run)
            line = 0.0f64
            run = 0.0f64
            tail_trail = 0.0f64
            continue
        }
        if p.kind == .Float || p.kind == .Abs { continue }
        var w = p.w
        var minw = p.w
        if p.kind == .Atomic { minw = p.trail }
        line += w + (if_trail(p))
        if p.kind == .Text { tail_trail = p.trail } else if p.kind == .Atomic { tail_trail = 0.0f64 }
        run += minw
        if p.soft {
            mn = maxf(mn, run)
            run = 0.0f64
        }
    }
    mx = maxf(mx, line - tail_trail)
    mn = maxf(mn, run)
    ret (mn, mx)
}

fn if_trail(p: Piece) -> f64 {
    if p.kind == .Text { ret p.trail }
    ret 0.0f64
}

// Like `collect_inline`, but atomic inlines are sized from their content widths instead of being laid out.
fn collect_inline_intrinsic(bd: *Builder, b: u32, ends_space: *Flag) {
    let l = bd.l
    let bb = &l.boxes.items[usize(b)]
    let s = bstyle(l, b)
    if bb.inner == .Text || bb.inner == .Break || bb.inner == .Marker {
        collect_inline(bd, b, ends_space)
        ret
    }
    if !bb.inline_level || s.position == .Absolute || s.position == .Fixed || s.floating != .None {
        if s.floating != .None {
            let (fmn, fmx) = outer_content_widths(l, b)
            push_piece(bd, Piece { kind: .Atomic, box: b, text: "", w: fmx, trail: fmn, soft: true, ink: true, start: 0usize, clen: 0usize })
        }
        ret
    }
    if bb.inner == .Flow {
        resolve_edges(l, b, 0.0f64)
        resolve_margins_fixed(l, b, 0.0f64)
        let bm = bx(l, b)
        push_piece(bd, Piece { kind: .Open, box: b, text: "", w: bm.margin[3usize] + bm.border[3usize] + bm.padding[3usize], trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        var kid = bx(l, b).first
        while kid != NONE {
            collect_inline_intrinsic(bd, kid, ends_space)
            kid = l.boxes.items[usize(kid)].next
        }
        push_piece(bd, Piece { kind: .Close, box: b, text: "", w: bm.margin[1usize] + bm.border[1usize] + bm.padding[1usize], trail: 0.0f64, soft: false, ink: false, start: 0usize, clen: 0usize })
        ret
    }
    let (amn, amx) = outer_content_widths(l, b)
    if bd.pieces.len > 0usize {
        let lastp = bd.pieces.items[bd.pieces.len - 1usize]
        if lastp.kind == .Text || lastp.kind == .Atomic { bd.pieces.items[bd.pieces.len - 1usize].soft = true }
    }
    push_piece(bd, Piece { kind: .Atomic, box: b, text: "", w: amx, trail: amn, soft: true, ink: true, start: 0usize, clen: 0usize })
    ends_space.v = false
}

// --- Replaced sizing.

fn used_replaced_size(l: *Layout, b: u32, cbw: f64, cbh: f64) -> (f64, f64) {
    let s = bstyle(l, b)
    let intr = replaced_intrinsic(l, b)
    let (iw0, ih0) = default_replaced(intr)
    var iw = iw0
    var ih = ih0
    var ratio = intr.ratio
    if ratio <= 0.0f64 && iw > 0.0f64 && ih > 0.0f64 { ratio = iw / ih }
    let (w_css, has_w) = resolve_len(s.width, cbw)
    let (h_css, has_h) = resolve_len(s.height, cbh)
    var w = iw
    var h = ih
    let known_w = s.width.kind == .Px && has_w
    let known_h = s.height.kind == .Px && has_h
    if known_w { w = to_content_w(l, b, w_css) }
    if known_h { h = to_content_h(l, b, h_css) }
    if known_w && !known_h {
        if ratio > 0.0f64 { h = w / ratio } else { h = ih }
    }
    if !known_w && known_h {
        if ratio > 0.0f64 { w = h * ratio } else { w = iw }
    }
    // min and max constraints, keeping the ratio when only one axis is constrained.
    let wc = clamp_width(l, b, w, cbw)
    let hc = clamp_height(l, b, h, cbh)
    if wc != w && hc == h && ratio > 0.0f64 && !known_h { h = clamp_height(l, b, wc / ratio, cbh) }
    if hc != h && wc == w && ratio > 0.0f64 && !known_w { w = clamp_width(l, b, hc * ratio, cbw) }
    if wc != w { w = wc }
    if hc != h { h = hc }
    ret (w, h)
}

// --- Block layout.

fn auto_margin_h(s: *const style.Style, side: usize) -> bool { ret s.margin[side].kind == .Auto }

// Fills the used width and horizontal margins of a block-level box in normal flow (CSS 2.1 10.3.3). `avail` is the
// width its margin box may take (the containing block's content width, less floats for a context root).
fn used_width_block(l: *Layout, c: u32, cbw: f64, avail: f64) {
    let s = bstyle(l, c)
    let cb = bx(l, c)
    var base = cbw
    if base < 0.0f64 { base = 0.0f64 }
    resolve_edges(l, c, base)
    let extras = horizontal_extras(cb)
    var ml = 0.0f64
    var mr = 0.0f64
    let aml = auto_margin_h(s, 3usize)
    let amr = auto_margin_h(s, 1usize)
    if !aml { ml = resolve_or(s.margin[3usize], base, 0.0f64) }
    if !amr { mr = resolve_or(s.margin[1usize], base, 0.0f64) }
    let tf_h = trim_flags(l, cb.parent)
    if (tf_h & 4u8) != 0u8 { ml = 0.0f64 }
    if (tf_h & 8u8) != 0u8 { mr = 0.0f64 }
    // Which margin absorbs the slack follows the direction of the containing block, not of the box itself.
    var cb_rtl = s.direction == .Rtl
    if cb.parent != NONE { cb_rtl = st(l, l.boxes.items[usize(cb.parent)].style).direction == .Rtl }
    var cw = 0.0f64
    var w_auto = s.width.kind != .Px
    if s.width.kind == .MinContent || s.width.kind == .MaxContent || s.width.kind == .FitContent {
        let (mn, mx) = content_widths(l, c)
        w_auto = false
        if s.width.kind == .MinContent { cw = mn } else if s.width.kind == .MaxContent { cw = mx } else { cw = minf(maxf(mn, avail - ml - mr - extras), mx) }
    } else if !w_auto {
        let (wv, good) = resolve_len(s.width, base)
        if good { cw = to_content_w(l, c, wv) } else { w_auto = true }
    }
    if w_auto {
        cw = avail - ml - mr - extras
        if aml || amr {
            cw = avail - ml - mr - extras
        }
    }
    cw = maxf(0.0f64, clamp_width(l, c, cw, base))
    // Distribute any remaining space onto auto margins, else the end margin.
    let rest = avail - (ml + mr + extras + cw)
    if aml && amr {
        if rest > 0.0f64 {
            ml = rest / 2.0f64
            mr = rest / 2.0f64
        }
    } else if aml {
        ml = maxf(0.0f64, rest)
    } else if amr {
        mr = maxf(0.0f64, rest)
    } else if cb_rtl {
        ml = avail - (mr + extras + cw)
    } else {
        mr = avail - (ml + extras + cw)
    }
    cb.margin[3usize] = ml
    cb.margin[1usize] = mr
    cb.w = cw + extras
}

// `margin-trim` of a block container: bit 1 block-start, 2 block-end, 4 inline-start, 8 inline-end.
fn trim_flags(l: *Layout, p: u32) -> u8 {
    if p == NONE { ret 0u8 }
    let (tv, has_tv) = extra_text(bstyle(l, p), "margin-trim")
    if !has_tv { ret 0u8 }
    let toks = cv.split_top_level_spaces(l.a, cv.lower(l.a, cv.trim_ws(tv)))
    var f = 0u8
    var i = 0usize
    while i < toks.len {
        let t = toks[i]
        i += 1usize
        if str.eq(t, "block") { f |= 3u8 }
        if str.eq(t, "inline") { f |= 12u8 }
        if str.eq(t, "block-start") { f |= 1u8 }
        if str.eq(t, "block-end") { f |= 2u8 }
        if str.eq(t, "inline-start") { f |= 4u8 }
        if str.eq(t, "inline-end") { f |= 8u8 }
    }
    ret f
}

fn is_flow_sibling(l: *const Layout, k: u32) -> bool {
    let kb = &l.boxes.items[usize(k)]
    ret kb.inner != .Marker && kb.inner != .Text && !kb.inline_level && !is_out_of_flow(st(l, kb.style))
}

fn used_margins_vertical(l: *Layout, c: u32, cbw: f64) {
    let s = bstyle(l, c)
    let cb = bx(l, c)
    var base = cbw
    if base < 0.0f64 { base = 0.0f64 }
    cb.margin[0usize] = resolve_or(s.margin[0usize], base, 0.0f64)
    cb.margin[2usize] = resolve_or(s.margin[2usize], base, 0.0f64)
    let par = cb.parent
    let tf = trim_flags(l, par)
    if (tf & 3u8) != 0u8 {
        if (tf & 1u8) != 0u8 {
            var first = true
            var k = l.boxes.items[usize(par)].first
            while k != c && k != NONE {
                if is_flow_sibling(l, k) && !self_collapsing(l, k, cbw) { first = false }
                k = l.boxes.items[usize(k)].next
            }
            if first { bx(l, c).margin[0usize] = 0.0f64 }
        }
        if (tf & 2u8) != 0u8 {
            var last = true
            var k2 = l.boxes.items[usize(c)].next
            while k2 != NONE {
                if is_flow_sibling(l, k2) && !self_collapsing(l, k2, cbw) { last = false }
                k2 = l.boxes.items[usize(k2)].next
            }
            if last { bx(l, c).margin[2usize] = 0.0f64 }
        }
    }
}

fn in_flow_block(l: *const Layout, c: u32) -> bool {
    let cb = &l.boxes.items[usize(c)]
    if cb.inline_level || cb.inner == .Marker { ret false }
    ret !is_out_of_flow(st(l, cb.style))
}

// Whether `c` collapses its own top and bottom margins together and holds nothing in flow.
fn self_collapsing(l: *Layout, c: u32, cbw: f64) -> bool {
    let cb = &l.boxes.items[usize(c)]
    if cb.inner != .Flow || cb.inline_level { ret false }
    let s = st(l, cb.style)
    if is_bfc_root(l, c) { ret false }
    let (ratio_known, has_ratio) = box_ratio(l, c)
    if has_ratio { ret false }
    if s.height.kind == .Px {
        let (hv, good) = resolve_len(s.height, -1.0f64)
        // A percentage height may resolve to a real height against a definite container.
        if s.height.pct != 0.0f64 { ret false }
        if !good || hv != 0.0f64 { if s.height.pct == 0.0f64 { ret false } }
        if s.height.pct == 0.0f64 && hv != 0.0f64 { ret false }
    }
    if s.min_height.kind == .Px && (s.min_height.px != 0.0f64 || s.min_height.pct != 0.0f64) { ret false }
    if st(l, cb.style).border_width[0usize] != 0.0f64 || s.border_width[2usize] != 0.0f64 { ret false }
    let pt = resolve_or(s.padding[0usize], maxf(cbw, 0.0f64), 0.0f64)
    let pb = resolve_or(s.padding[2usize], maxf(cbw, 0.0f64), 0.0f64)
    if pt != 0.0f64 || pb != 0.0f64 { ret false }
    var kid = cb.first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker {
            kid = kb.next
            continue
        }
        // An absolutely positioned child is laid out by the positioned pass and takes no part in the flow.
        let kps = st(l, kb.style).position
        if kb.inner != .Text && (kps == .Absolute || kps == .Fixed) {
            kid = kb.next
            continue
        }
        if kb.inner == .Text {
            if !(is_ws_only(kb.text) && collapses(l, kid)) { ret false }
        } else if kb.inline_level {
            ret false
        } else if is_out_of_flow(st(l, kb.style)) {
            // Floats and positioned boxes still have to be laid out inside it.
            ret false
        } else {
            if !self_collapsing(l, kid, cbw) { ret false }
        }
        kid = kb.next
    }
    ret true
}

// The collapsed top margin of `c` and of the chain of first children it adjoins.
fn peek_top(l: *Layout, c: u32, cbw: f64, floats: bool) -> Margin {
    used_margins_vertical(l, c, cbw)
    let cb = &l.boxes.items[usize(c)]
    var m = margin_of(cb.margin[0usize])
    let s = st(l, cb.style)
    if is_bfc_root(l, c) || cb.inner != .Flow { ret m }
    var base = cbw
    if base < 0.0f64 { base = 0.0f64 }
    if s.border_width[0usize] != 0.0f64 || resolve_or(s.padding[0usize], base, 0.0f64) != 0.0f64 { ret m }
    // The first in-flow block child, past empty blocks whose margins adjoin.
    var kid = cb.first
    var seen_float = floats
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker || (!kb.inline_level && is_out_of_flow(st(l, kb.style))) {
            if !kb.inline_level && st(l, kb.style).floating != .None { seen_float = true }
            kid = kb.next
            continue
        }
        if kb.inner == .Text && is_ws_only(kb.text) && collapses(l, kid) {
            kid = kb.next
            continue
        }
        if kb.inline_level || kb.inner == .Text { ret m }
        // A child that clears an earlier float is likely to get clearance, which stops its margin collapsing upward.
        if seen_float && st(l, kb.style).clear != .None { ret m }
        // The child's width decides its own percentage edges; its parent's content width is a close enough base.
        used_margins_vertical(l, kid, cbw)
        if self_collapsing(l, kid, cbw) {
            m = collapse(m, margin_of(l.boxes.items[usize(kid)].margin[0usize]))
            m = collapse(m, margin_of(l.boxes.items[usize(kid)].margin[2usize]))
            kid = kb.next
            continue
        }
        ret collapse(m, peek_top(l, kid, cbw, seen_float))
    }
    ret m
}

// The nearest ancestor-or-self inline box of the text box `b` aligned to a line edge (`NONE` when there is none).
fn va_edge_owner(l: *const Layout, b: u32, cont: u32) -> u32 {
    var owner = b
    if l.boxes.items[usize(b)].inner == .Text { owner = l.boxes.items[usize(b)].parent }
    while owner != NONE && owner != cont {
        let va = bstyle(l, owner).vertical_align
        if va == .Top || va == .Bottom { ret owner }
        owner = l.boxes.items[usize(owner)].parent
    }
    ret NONE
}

// The largest ascent and descent of the text in the subtree of inline box `o`, leaving out the sub-subtrees aligned to an edge themselves.
fn subtree_ad(l: *const Layout, o: u32) -> (f64, f64) {
    var ta = -1000000.0f64
    var td = -1000000.0f64
    var kid = l.boxes.items[usize(o)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Text {
            let (a, d) = font_ad(l, bstyle(l, kid))
            ta = maxf(ta, a)
            td = maxf(td, d)
        } else if kb.inline_level && kb.inner != .Break {
            let va = bstyle(l, kid).vertical_align
            if va != .Top && va != .Bottom {
                let (a2, d2) = subtree_ad(l, kid)
                ta = maxf(ta, a2)
                td = maxf(td, d2)
            }
        }
        kid = kb.next
    }
    if ta < -999999.0f64 { ret (0.0f64, 0.0f64) }
    ret (ta, td)
}

// --- Baselines.

// The baseline of the last line in `b`, relative to `b`'s border box top (false when it holds no line).
fn last_baseline(l: *const Layout, b: u32) -> (bool, f64) {
    let bb = &l.boxes.items[usize(b)]
    if bb.line_count > 0u32 {
        let ln = l.lines.items[usize(bb.line_first + bb.line_count - 1u32)]
        ret (true, bb.border[0usize] + bb.padding[0usize] + ln.baseline)
    }
    var kid = bb.last
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner != .Marker && !is_out_of_flow(st(l, kb.style)) {
            let (found, y) = last_baseline(l, kid)
            if found { ret (true, kb.y + y) }
        }
        kid = kb.prev
    }
    ret (false, 0.0f64)
}

fn first_baseline(l: *const Layout, b: u32) -> (bool, f64) {
    let bb = &l.boxes.items[usize(b)]
    if bb.line_count > 0u32 {
        let ln = l.lines.items[usize(bb.line_first)]
        ret (true, bb.border[0usize] + bb.padding[0usize] + ln.baseline)
    }
    var kid = bb.first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner != .Marker && !is_out_of_flow(st(l, kb.style)) {
            let (found, y) = first_baseline(l, kid)
            if found { ret (true, kb.y + y) }
        }
        kid = kb.next
    }
    ret (false, 0.0f64)
}

// --- Contents of a box in a new formatting context.

fn layout_in_new_bfc(l: *Layout, b: u32, cw: f64, ch: f64) -> f64 {
    let base = l.floats.len
    var fc = Flow { base: base, ox: 0.0f64, oy: 0.0f64 }
    var h = 0.0f64
    var done = false
    let inner = l.boxes.items[usize(b)].inner
    if inner == .Table {
        h = layout_table(l, b, cw, ch)
    } else if inner == .Flex {
        h = layout_flex(l, b, cw, ch)
    } else if inner == .Grid {
        h = layout_grid(l, b, cw, ch)
    } else {
        let bs = st(l, l.boxes.items[usize(b)].style)
        if (inner == .Flow || inner == .FlowRoot) && has_columns(bs) {
            let cols = columns_for(l, bs, cw)
            if cols.count > 1usize {
                var has_span = false
                var sk = l.boxes.items[usize(b)].first
                while sk != NONE {
                    if is_spanner(l, sk) { has_span = true }
                    sk = l.boxes.items[usize(sk)].next
                }
                if has_span {
                    h = layout_multicol_spans(l, b, cw, cols, &fc)
                } else {
                    h = layout_multicol(l, b, cw, ch, cols, &fc)
                }
                done = true
            }
        }
        if !done {
            let (ch2, _m) = layout_children(l, b, cw, ch, &fc, false)
            h = ch2
        }
    }
    if !done { h = maxf(h, float_bottom(l, base, 2u32, 0.0f64)) }
    l.floats.len = base
    ret h
}

fn set_baseline(l: *Layout, b: u32) {
    let bb = bx(l, b)
    let s = st(l, bb.style)
    bb.has_baseline = false
    if bb.inner == .Replaced { ret }
    if s.overflow_x != .Visible || s.overflow_y != .Visible { ret }
    if bb.inner == .Flex || (bb.inner == .Grid && !s.lanes) {
        let (ff, fy) = flex_baseline(l, b)
        bb.baseline = fy
        bb.has_baseline = ff
        ret
    }
    let (found, y) = last_baseline(l, b)
    if found {
        bb.baseline = y
        bb.has_baseline = true
    }
}

// The baseline of a flex container: that of its first in-flow item (synthesized from the item's border box when it has none).
fn flex_baseline(l: *const Layout, b: u32) -> (bool, f64) {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner != .Marker && !is_out_of_flow(st(l, kb.style)) && kb.inner != .Text && kb.inner != .Break {
            let (found, y) = first_baseline(l, kid)
            if found { ret (true, kb.y + y) }
            ret (true, kb.y + kb.h)
        }
        kid = kb.next
    }
    ret (false, 0.0f64)
}

// Lays out `b` on its own: an inline-level atomic, a float, an absolutely positioned or replaced box. `cbw` is the
// width its containing block offers (negative: unknown). Sets `w`, `h`, the margins and the baseline.
fn layout_atomic(l: *Layout, b: u32, cbw: f64, cbh: f64) {
    let s = bstyle(l, b)
    let bb = bx(l, b)
    var base = cbw
    if base < 0.0f64 { base = 0.0f64 }
    resolve_edges(l, b, base)
    var i = 0usize
    resolve_margins_fixed(l, b, base)
    let extras_h = horizontal_extras(bb)
    let extras_v = vertical_extras(bb)
    if bb.inner == .Replaced {
        let (w, h) = used_replaced_size(l, b, cbw, -1.0f64)
        bb.w = w + extras_h
        bb.h = h + extras_v
        bb.has_baseline = false
        bb.line_count = 0u32
        ret
    }
    if bb.inline_level && (l.tr1.len != 0usize || l.tr2.len != 0usize) && (mode_code(s) != 0u8) != (l.vmode != 0u8) {
        layout_orthogonal(l, b, cbw, cbh, -1.0f64, -1.0f64)
        ret
    }
    var cw = 0.0f64
    let (wv, has_w) = resolve_len(s.width, base)
    var from_ratio = false
    if !(s.width.kind == .Px && has_w) && s.height.kind == .Px {
        let (hv2, has_h2) = resolve_len(s.height, cbh)
        if has_h2 {
            let (rw, has_rw) = ratio_width(l, b, to_content_h(l, b, hv2))
            if has_rw {
                cw = rw
                from_ratio = true
            }
        }
    }
    if from_ratio {
        // width taken from the ratio
    } else if s.width.kind == .Px && has_w {
        cw = to_content_w(l, b, wv)
    } else {
        let (mn, mx) = content_widths(l, b)
        var avail = 1000000.0f64
        if cbw >= 0.0f64 { avail = cbw - bb.margin[1usize] - bb.margin[3usize] - extras_h }
        if s.width.kind == .MinContent { cw = mn } else if s.width.kind == .MaxContent { cw = mx } else { cw = minf(maxf(mn, avail), mx) }
        if bb.inner == .Table { cw = mx }
    }
    cw = maxf(0.0f64, clamp_width(l, b, cw, base))
    bb.w = cw + extras_h
    layout_contents_height(l, b, cw, cbh)
}

// Lays out the contents of `b` (content width `cw`) as a formatting context root and sets its height from the style.
fn layout_contents_height(l: *Layout, b: u32, cw: f64, cbh: f64) {
    let s = bstyle(l, b)
    let bb = bx(l, b)
    var spec = -1.0f64
    let (hv, has_h) = resolve_len(s.height, cbh)
    if s.height.kind == .Px && has_h { spec = to_content_h(l, b, hv) }
    var ratio_h = -1.0f64
    if spec < 0.0f64 && bb.inner != .Replaced {
        let (rh, has_r) = ratio_height(l, b, cw)
        if has_r {
            ratio_h = rh
            spec = rh
        }
    }
    let first_line = l.lines.len
    let auto_h = layout_in_new_bfc(l, b, cw, spec)
    var h = auto_h
    if spec >= 0.0f64 { h = spec }
    if ratio_h >= 0.0f64 && s.overflow_x == .Visible && s.overflow_y == .Visible { h = maxf(ratio_h, auto_h) }
    h = maxf(0.0f64, clamp_height_auto(l, b, h, cbh, auto_h))
    bb.overflow_w = maxf(bb.overflow_w, cw)
    bb.overflow_h = maxf(bb.overflow_h, auto_h)
    bb.h = h + vertical_extras(bb)
    set_baseline(l, b)
}

// --- The normal flow of a block container.

// Lays out the children of block container `b` with content width `cw`. Returns the content height and, when the box
// does not contain its last child's bottom margin, that margin (still pending for the parent).
fn layout_children(l: *Layout, b: u32, cw: f64, ch: f64, fc: *Flow, through_top: bool) -> (f64, Margin) {
    let bb = bx(l, b)
    // Inline content: one inline formatting context.
    if has_inline_content(l, b) {
        let h = layout_inline_content(l, b, cw, ch, fc)
        position_markers(l, b)
        ret (h, no_margin())
    }
    let ox0 = bb.border[3usize] + bb.padding[3usize]
    let oy0 = bb.border[0usize] + bb.padding[0usize]
    var y = 0.0f64
    var acc = no_margin()
    var consumed = Flag { v: through_top, cleared: false }
    var kid = bb.first
    while kid != NONE {
        let nxt = l.boxes.items[usize(kid)].next
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker {
            kid = nxt
            continue
        }
        let ks = st(l, kb.style)
        if kb.inner == .Text {
            kid = nxt
            continue
        }
        if is_out_of_flow(ks) {
            if ks.floating != .None {
                layout_atomic(l, kid, cw, ch)
                place_float(l, fc, kid, fc.ox, cw, fc.oy + y + margin_value(acc), b)
            } else {
                let ab = bx(l, kid)
                ab.x = ox0
                ab.y = oy0 + y + margin_value(acc)
                ab.aux = 3u32
            }
            kid = nxt
            continue
        }
        y = layout_block_child(l, b, kid, cw, ch, fc, y, &acc, &consumed, ox0, oy0)
        kid = nxt
    }
    position_markers(l, b)
    // `line-clamp` over the lines of the block children (the container's own inline content is clamped with its lines).
    let clamp_n = line_clamp_count(bstyle(l, b))
    var scan_c = ClampScan { seen: 0usize, n: clamp_n, tail: false }
    if clamp_n > 0usize { clamp_scan(l, b, &scan_c) }
    if clamp_n > 0usize && (scan_c.seen > clamp_n || scan_c.tail) {
        var ctr = Counter { n: clamp_n }
        let cut = clamp_children(l, b, &ctr)
        if cut >= 0.0f64 {
            y = cut - oy0
            acc = no_margin()
        }
    }
    // The last child's bottom margin collapses through when nothing separates it from the parent's.
    let s = bstyle(l, b)
    var base = cw
    let closed = consumed.cleared || is_bfc_root(l, b) || bb.border[2usize] != 0.0f64 || bb.padding[2usize] != 0.0f64 || s.height.kind == .Px
    if closed {
        y += margin_value(acc)
        ret (y, no_margin())
    }
    ret (y, acc)
}

type Counter = struct { n: usize }

// Empties a box and everything in it: it takes no room and paints nothing.
fn clamp_hide(l: *Layout, b: u32) {
    let bb = bx(l, b)
    bb.h = 0.0f64
    bb.line_count = 0u32
    var kid = bb.first
    while kid != NONE {
        clamp_hide(l, kid)
        kid = l.boxes.items[usize(kid)].next
    }
}

// Keeps the first `ctr.n` more lines under box `b`, in document order, and hides the rest. Returns where the kept content
// ends, relative to the top of `b`'s border box, or -1 when everything fit.
fn clamp_walk(l: *Layout, b: u32, ctr: *Counter) -> f64 {
    let bb = bx(l, b)
    if bb.line_count > 0u32 {
        let cnt = usize(bb.line_count)
        if cnt < ctr.n {
            ctr.n -= cnt
            ret -1.0f64
        }
        let keep = ctr.n
        let last = &l.lines.items[usize(bb.line_first) + keep - 1usize]
        last.overflow_ellipsis = true
        let end_y = bb.border[0usize] + bb.padding[0usize] + last.y + last.h
        bb.line_count = u32(keep)
        bb.h = end_y + bb.padding[2usize] + bb.border[2usize]
        ctr.n = 0usize
        ret end_y
    }
    ret clamp_children(l, b, ctr)
}

type ClampScan = struct { seen: usize, n: usize, tail: bool }

// Counts the lines `line-clamp` sees under `b` (in-flow descendants sharing its formatting context) and notes any content
// that follows the last line it keeps.
fn clamp_scan(l: *Layout, b: u32, sc: *ClampScan) {
    var kid = bx(l, b).first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let nxt = kb.next
        if kb.inner == .Marker || kb.inner == .Text || kb.inline_level || is_out_of_flow(st(l, kb.style)) {
            kid = nxt
            continue
        }
        if sc.seen >= sc.n {
            if kb.h > 0.0f64 || kb.line_count > 0u32 { sc.tail = true }
        } else if !is_bfc_root(l, kid) {
            if kb.line_count > 0u32 { sc.seen += usize(kb.line_count) } else { clamp_scan(l, kid, sc) }
        }
        kid = nxt
    }
}

fn clamp_children(l: *Layout, b: u32, ctr: *Counter) -> f64 {
    var cut = -1.0f64
    var kid = bx(l, b).first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let nxt = kb.next
        if kb.inner == .Marker || kb.inner == .Text || kb.inline_level || is_out_of_flow(st(l, kb.style)) {
            kid = nxt
            continue
        }
        if cut >= 0.0f64 {
            clamp_hide(l, kid)
        } else if is_bfc_root(l, kid) {
            // Its lines belong to a formatting context of its own and are not counted.
        } else {
            let r = clamp_walk(l, kid, ctr)
            if r >= 0.0f64 { cut = l.boxes.items[usize(kid)].y + r }
        }
        kid = nxt
    }
    if cut >= 0.0f64 {
        let bb = bx(l, b)
        bb.h = cut + bb.padding[2usize] + bb.border[2usize]
    }
    ret cut
}

// The outside marker of a list item sits left of its first line.
fn position_markers(l: *Layout, b: u32) {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker && !kb.inline_level {
            let txt = marker_string(l, kid)
            let ms = bstyle(l, kid)
            let mw = text_advance(l, ms, txt)
            let (found, base) = first_baseline(l, b)
            let (ma, md) = font_ad(l, ms)
            let mb = bx(l, kid)
            mb.w = mw
            mb.h = ma + md
            mb.x = -mw
            if found { mb.y = base - ma } else { mb.y = 0.0f64 }
            mb.text = txt
        }
        kid = l.boxes.items[usize(kid)].next
    }
}

// One in-flow block-level child: its position (margin collapsing, clearance, floats), size and contents. Returns the
// new content-relative y of the parent's flow.
fn layout_block_child(l: *Layout, p: u32, c: u32, cw: f64, ch: f64, fc: *Flow, y_in: f64, acc: *Margin, consumed: *Flag, ox0: f64, oy0: f64) -> f64 {
    let s = bstyle(l, c)
    let cb = bx(l, c)
    var y = y_in
    used_margins_vertical(l, c, cw)
    let m_top_own = margin_of(l.boxes.items[usize(c)].margin[0usize])
    let m_bottom_own = margin_of(l.boxes.items[usize(c)].margin[2usize])
    consumed.cleared = false
    // Self-collapsing: it takes no height and its margins join the pending ones.
    if self_collapsing(l, c, cw) && s.clear == .None {
        var m_in = m_top_own
        if consumed.v { m_in = no_margin() }
        acc.pos = maxf(acc.pos, maxf(m_in.pos, m_bottom_own.pos))
        acc.neg = minf(acc.neg, minf(m_in.neg, m_bottom_own.neg))
        used_width_block(l, c, cw, cw)
        let cb2 = bx(l, c)
        cb2.x = ox0 + cb2.margin[3usize]
        cb2.y = oy0 + y + margin_value(Margin { pos: acc.pos, neg: acc.neg })
        cb2.h = 0.0f64
        position_markers(l, c)
        ret y
    }
    // Width, and the room beside floats for a context root.
    var avail = cw
    var shift_x = 0.0f64
    let orth = is_orthogonal(l, c)
    let bfc = is_bfc_root(l, c) || orth
    // The collapsed margin above the border edge, through first children and empty blocks.
    let float_low = maxf(float_bottom(l, fc.base, 0u32, -1000000.0f64), float_bottom(l, fc.base, 1u32, -1000000.0f64)) - fc.oy
    var m_chain = peek_top(l, c, cw, false)
    if float_low > y + margin_value(collapse(Margin { pos: acc.pos, neg: acc.neg }, m_chain)) { m_chain = peek_top(l, c, cw, true) }
    if consumed.v { m_chain = no_margin() }
    var total = collapse(Margin { pos: acc.pos, neg: acc.neg }, m_chain)
    var y_top = y + margin_value(total)
    // Clearance.
    if s.clear != .None {
        var clear_to = y_top
        let fbot_l = float_bottom(l, fc.base, 0u32, -1000000.0f64) - fc.oy
        let fbot_r = float_bottom(l, fc.base, 1u32, -1000000.0f64) - fc.oy
        if s.clear == .Left || s.clear == .Both || s.clear == .InlineStart { clear_to = maxf(clear_to, fbot_l) }
        if s.clear == .Right || s.clear == .Both || s.clear == .InlineEnd { clear_to = maxf(clear_to, fbot_r) }
        if clear_to > y_top {
            y_top = clear_to
            total = no_margin()
            consumed.cleared = true
        }
    }
    // A context root (or a replaced or table box) must not overlap floats: narrow it, or move it down.
    var guard = 0usize
    var used_before = false
    while guard < 64usize {
        guard += 1usize
        var offer = cw
        shift_x = 0.0f64
        if bfc && fc.base < l.floats.len {
            let lx = float_edge_left(l, fc.base, fc.oy + y_top, fc.oy + y_top + 1.0f64, fc.ox)
            let rx = float_edge_right(l, fc.base, fc.oy + y_top, fc.oy + y_top + 1.0f64, fc.ox + cw)
            offer = rx - lx
            shift_x = lx - fc.ox
        }
        avail = offer
        size_block_box(l, c, cw, offer)
        let cb3 = &l.boxes.items[usize(c)]
        // The end margin of an over-constrained box is the (possibly negative) rest, so measure with its specified margin.
        var mr_need = 0.0f64
        if s.margin[1usize].kind != .Auto { mr_need = resolve_or(s.margin[1usize], maxf(cw, 0.0f64), 0.0f64) }
        let need = cb3.w + mr_need + cb3.margin[3usize]
        if need <= offer + 0.01f64 || !bfc || fc.base >= l.floats.len { break }
        let nxt = next_float_end(l, fc.base, fc.oy + y_top)
        if nxt <= fc.oy + y_top { break }
        y_top = nxt - fc.oy
    }
    let cb4 = bx(l, c)
    cb4.x = ox0 + shift_x + cb4.margin[3usize]
    cb4.y = oy0 + y_top
    // Contents. A box that adjoins its first child's margin starts that child at its content top.
    let through_top = !bfc && cb4.inner == .Flow && cb4.border[0usize] == 0.0f64 && cb4.padding[0usize] == 0.0f64
    var content_oy = fc.oy + y_top + cb4.border[0usize] + cb4.padding[0usize]
    var content_ox = fc.ox + shift_x + cb4.margin[3usize] + cb4.border[3usize] + cb4.padding[3usize]
    let content_w = cb4.w - horizontal_extras(cb4)
    var spec_h = -1.0f64
    let (hv, has_h) = resolve_len(s.height, ch)
    if s.height.kind == .Px && has_h { spec_h = to_content_h(l, c, hv) }
    var ratio_h = -1.0f64
    if spec_h < 0.0f64 && cb4.inner != .Replaced {
        let (rh, has_r) = ratio_height(l, c, content_w)
        if has_r {
            ratio_h = rh
            spec_h = rh
        }
    }
    if spec_h < 0.0f64 && cb4.inner == .Replaced {
        // A block-level replaced element with an auto height takes the height its intrinsic size and ratio give.
        let (rw2, rh2) = used_replaced_size(l, c, content_w, ch)
        spec_h = rh2
    }
    var auto_h = 0.0f64
    var out_margin = no_margin()
    if orth {
        spec_h = -1.0f64
        ratio_h = -1.0f64
        layout_orthogonal(l, c, cw, ch, -1.0f64, -1.0f64)
        let ob = bx(l, c)
        auto_h = maxf(0.0f64, ob.h - vertical_extras(ob))
        // The root of a vertical-rl document starts at the right edge.
        if mode_code(bstyle(l, c)) == 1u8 && l.boxes.items[usize(p)].parent == NONE { ob.x = ox0 + maxf(0.0f64, cw - ob.w) }
    } else if bfc || cb4.inner != .Flow {
        auto_h = layout_in_new_bfc(l, c, content_w, spec_h)
    } else {
        var sub = Flow { base: fc.base, ox: content_ox, oy: content_oy }
        let (h2, m2) = layout_children(l, c, content_w, spec_h, &sub, through_top)
        auto_h = h2
        out_margin = m2
    }
    var ch_used = auto_h
    if spec_h >= 0.0f64 { ch_used = spec_h }
    if cb4.inner == .Table && spec_h >= 0.0f64 {
        // A table's height is the height of its grid; the captions come on top of it.
        var caps = 0.0f64
        var ck = cb4.first
        while ck != NONE {
            let cbx = &l.boxes.items[usize(ck)]
            if cbx.inner == .Caption { caps += cbx.h + cbx.margin[0usize] + cbx.margin[2usize] }
            ck = cbx.next
        }
        ch_used = maxf(spec_h, auto_h - caps) + caps
    }
    // A ratio-derived height is a preferred size: the content (min-height: auto) can make it larger.
    if ratio_h >= 0.0f64 && (s.overflow_x == .Visible && s.overflow_y == .Visible) { ch_used = maxf(ratio_h, auto_h) }
    ch_used = maxf(0.0f64, clamp_height_auto(l, c, ch_used, ch, auto_h))
    let cb5 = bx(l, c)
    cb5.h = ch_used + vertical_extras(cb5)
    cb5.overflow_w = maxf(cb5.overflow_w, content_w)
    cb5.overflow_h = maxf(cb5.overflow_h, auto_h)
    set_baseline(l, c)
    apply_relative(l, c, cw, ch)
    // The margin below: its own, joined with the last child's when that collapsed through.
    var below = m_bottom_own
    if !bfc && cb5.border[2usize] == 0.0f64 && cb5.padding[2usize] == 0.0f64 && s.height.kind != .Px { below = collapse(m_bottom_own, out_margin) }
    consumed.v = false
    acc.pos = below.pos
    acc.neg = below.neg
    ret y_top + cb5.h
}

// Width and horizontal margins of a block-level box (and its edges) for a given offer.
fn size_block_box(l: *Layout, c: u32, cbw: f64, offer: f64) {
    let cb = bx(l, c)
    let s = bstyle(l, c)
    if cb.inner == .Replaced {
        resolve_edges(l, c, cbw)
        resolve_margins_fixed(l, c, cbw)
        let (w, h) = used_replaced_size(l, c, cbw, -1.0f64)
        let extras = horizontal_extras(bx(l, c))
        let bb = bx(l, c)
        bb.w = w + extras
        // Auto margins centre it.
        let aml = s.margin[3usize].kind == .Auto
        let amr = s.margin[1usize].kind == .Auto
        let rest = offer - bb.w - (bb.margin[1usize] + bb.margin[3usize])
        if aml && amr && rest > 0.0f64 {
            bb.margin[3usize] = rest / 2.0f64
            bb.margin[1usize] = rest / 2.0f64
        } else if aml && rest > 0.0f64 {
            bb.margin[3usize] = rest
        }
        ret
    }
    if cb.inner == .Table || ((cb.inner == .Flex || cb.inner == .Grid) && false) {
        // A table is as wide as its columns need, within the offer.
        resolve_edges(l, c, cbw)
        resolve_margins_fixed(l, c, cbw)
        let bb = bx(l, c)
        let extras = horizontal_extras(bb)
        var cw = 0.0f64
        let (wv, has_w) = resolve_len(s.width, cbw)
        if s.width.kind == .Px && has_w {
            cw = to_content_w(l, c, wv)
            if cb.inner == .Table { cw = maxf(cw, table_min_width(l, c)) }
        } else {
            let (mn, mx) = content_widths(l, c)
            let room = offer - bb.margin[1usize] - bb.margin[3usize] - extras
            cw = minf(maxf(mn, room), mx)
        }
        cw = maxf(0.0f64, clamp_width(l, c, cw, cbw))
        bb.w = cw + extras
        let aml = s.margin[3usize].kind == .Auto
        let amr = s.margin[1usize].kind == .Auto
        let rest = offer - bb.w - (bb.margin[1usize] + bb.margin[3usize])
        if aml && amr && rest > 0.0f64 {
            bb.margin[3usize] = rest / 2.0f64
            bb.margin[1usize] = rest / 2.0f64
        } else if aml && rest > 0.0f64 {
            bb.margin[3usize] = rest
        }
        ret
    }
    used_width_block(l, c, cbw, offer)
    // A definite height and a ratio give an automatic width (instead of filling the container).
    let s2 = bstyle(l, c)
    if s2.width.kind != .Px && s2.height.kind == .Px && s2.height.pct == 0.0f64 {
        let b2 = bx(l, c)
        if b2.inner == .Flow {
            let (rw, has_rw) = ratio_width(l, c, to_content_h(l, c, s2.height.px))
            if has_rw { b2.w = maxf(0.0f64, clamp_width(l, c, rw, cbw)) + horizontal_extras(b2) }
        }
    }
}

// `position: relative` shifts the box after layout; sticky and the rest stay in place.
// The offset of a relatively positioned box from its `inset` (left wins over right, top over bottom).
fn relative_offset(s: *const style.Style, cbw: f64, cbh: f64) -> (f64, f64) {
    var dx = 0.0f64
    var dy = 0.0f64
    if s.position != .Relative { ret (dx, dy) }
    if s.inset[3usize].kind != .Auto {
        dx = resolve_or(s.inset[3usize], maxf(cbw, 0.0f64), 0.0f64)
    } else if s.inset[1usize].kind != .Auto {
        dx = -resolve_or(s.inset[1usize], maxf(cbw, 0.0f64), 0.0f64)
    }
    if s.inset[0usize].kind != .Auto {
        dy = resolve_or(s.inset[0usize], cbh, 0.0f64)
    } else if s.inset[2usize].kind != .Auto {
        dy = -resolve_or(s.inset[2usize], cbh, 0.0f64)
    }
    ret (dx, dy)
}

// The summed relative offsets of `b` and its ancestors below `stop` (the inline container).
fn relative_chain(l: *const Layout, b: u32, stop: u32, cbw: f64) -> (f64, f64) {
    var dx = 0.0f64
    var dy = 0.0f64
    var cur = b
    var guard = 0usize
    while cur != NONE && cur != stop && guard < 64usize {
        let s = st(l, l.boxes.items[usize(cur)].style)
        if s.position == .Relative && l.boxes.items[usize(cur)].inner != .Text {
            let (ox, oy) = relative_offset(s, cbw, -1.0f64)
            dx += ox
            dy += oy
        }
        cur = l.boxes.items[usize(cur)].parent
        guard += 1usize
    }
    ret (dx, dy)
}

fn apply_relative(l: *Layout, c: u32, cbw: f64, cbh: f64) {
    let s = bstyle(l, c)
    if s.position != .Relative { ret }
    let cb = bx(l, c)
    var dx = 0.0f64
    var dy = 0.0f64
    // With both given, `left` wins in a left-to-right container and `right` in a right-to-left one.
    var right_wins = false
    if cb.parent != NONE && bstyle(l, cb.parent).direction == .Rtl && s.inset[1usize].kind != .Auto { right_wins = true }
    if s.inset[3usize].kind != .Auto && !right_wins {
        dx = resolve_or(s.inset[3usize], maxf(cbw, 0.0f64), 0.0f64)
    } else if s.inset[1usize].kind != .Auto {
        dx = -resolve_or(s.inset[1usize], maxf(cbw, 0.0f64), 0.0f64)
    }
    if s.inset[0usize].kind != .Auto {
        dy = resolve_or(s.inset[0usize], cbh, 0.0f64)
    } else if s.inset[2usize].kind != .Auto {
        dy = -resolve_or(s.inset[2usize], cbh, 0.0f64)
    }
    cb.x += dx
    cb.y += dy
}

// --- Stand-ins until the table, flex and grid algorithms land: those boxes lay out as blocks.

fn block_widths(l: *Layout, b: u32) -> (f64, f64) {
    var mn = 0.0f64
    var mx = 0.0f64
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner != .Marker {
            let (kmn, kmx) = outer_content_widths(l, kid)
            mn = maxf(mn, kmn)
            mx = maxf(mx, kmx)
        }
        kid = l.boxes.items[usize(kid)].next
    }
    ret (mn, mx)
}

// --- Tables (CSS 2.1 17): anonymous boxes, the cell grid, column widths, row heights, vertical alignment.
// Captions live inside the table box (no wrapper). `border-collapse: collapse` drops the spacing but keeps each cell's own
// borders; conflict resolution between neighbouring borders is not done.

type CellInfo = struct { box: u32, row: usize, col: usize, rs: usize, cs: usize, min: f64, max: f64, spec: f64, pct: f64 }

type TableData = struct {
    cols: usize, rows: usize, cells: list.List[CellInfo],
    col_min: []f64, col_max: []f64, col_w: []f64, col_pct: []f64, col_spec: []f64,
    row_h: []f64, row_y: []f64, row_box: []u32, row_above: []f64, row_below: []f64,
    sh: f64, sv: f64, sum_min: f64, sum_max: f64,
    collapsed: bool, hedge: []Edge, vedge: []Edge, cap_t: f64, cap_b: f64
}

fn is_ws_text(l: *const Layout, k: u32) -> bool {
    let kb = &l.boxes.items[usize(k)]
    ret kb.inner == .Text && is_ws_only(kb.text)
}

// Wraps the siblings first..last into one anonymous box (white-space-only runs just go).
fn wrap_table_run(l: *Layout, parent: u32, first: u32, last: u32, inner: Inner, display: style.Display) {
    if first == NONE { ret }
    var all_ws = true
    var k = first
    while true {
        if !is_ws_text(l, k) { all_ws = false }
        if k == last { break }
        k = l.boxes.items[usize(k)].next
    }
    if all_ws {
        k = first
        while true {
            let nxt = l.boxes.items[usize(k)].next
            detach(l, k)
            if k == last { break }
            k = nxt
        }
        ret
    }
    let anon = new_box(l, inner, display == .InlineTable, true, NONE, anon_style(l, l.boxes.items[usize(parent)].style, display))
    let prev = l.boxes.items[usize(first)].prev
    l.boxes.items[usize(anon)].parent = parent
    l.boxes.items[usize(anon)].prev = prev
    l.boxes.items[usize(anon)].next = first
    if prev == NONE { l.boxes.items[usize(parent)].first = anon } else { l.boxes.items[usize(prev)].next = anon }
    l.boxes.items[usize(first)].prev = anon
    k = first
    while true {
        let nxt = l.boxes.items[usize(k)].next
        detach(l, k)
        append(l, anon, k)
        if k == last { break }
        k = nxt
    }
    fix_anonymous(l, anon)
}

// A table, row group or row keeps only the children the table model allows; runs of the rest go into anonymous rows
// (in tables and groups) or cells (in rows).
fn fix_table_like(l: *Layout, b: u32) {
    let inner = l.boxes.items[usize(b)].inner
    var wrap_kind = Inner.Row
    var wrap_display = style.Display.TableRow
    if inner == .Row {
        wrap_kind = .Cell
        wrap_display = .TableCell
    }
    var run_first = NONE
    var run_last = NONE
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let nxt = kb.next
        var allowed = false
        if inner == .Row {
            allowed = kb.inner == .Cell
        } else if inner == .RowGroup {
            allowed = kb.inner == .Row
        } else {
            allowed = kb.inner == .RowGroup || kb.inner == .Row || kb.inner == .Caption || kb.inner == .ColumnGroup || kb.inner == .Column
        }
        // Positioned boxes stay where they are (the positioned pass lays them out); floats are wrapped like any other child.
        if !allowed && !kb.inline_level && (st(l, kb.style).position == .Absolute || st(l, kb.style).position == .Fixed) { allowed = true }
        if allowed {
            wrap_table_run(l, b, run_first, run_last, wrap_kind, wrap_display)
            run_first = NONE
            run_last = NONE
        } else {
            if run_first == NONE { run_first = kid }
            run_last = kid
        }
        kid = nxt
    }
    wrap_table_run(l, b, run_first, run_last, wrap_kind, wrap_display)
}

fn span_attr(l: *const Layout, node: u32, name: str) -> usize {
    if node == NONE { ret 1usize }
    let (v, has) = dom.get_attribute(l.d, node, name)
    if !has { ret 1usize }
    let (n, good) = str.parse_i64(v)
    if good != ok || n < 1i64 { ret 1usize }
    if n > 1000i64 { ret 1000usize }
    ret usize(n)
}

// Header groups first, then the other groups and loose rows in order, footer groups last.
fn row_order(l: *const Layout, table: u32, out: *list.List[u32]) {
    var pass = 0usize
    while pass < 3usize {
        var kid = l.boxes.items[usize(table)].first
        while kid != NONE {
            let kb = &l.boxes.items[usize(kid)]
            if kb.inner == .Row && pass == 1usize {
                let pushed = list.push[u32](out, kid)
            } else if kb.inner == .RowGroup {
                let ks = st(l, kb.style)
                var which = 1usize
                if ks.display == .TableHeaderGroup { which = 0usize }
                if ks.display == .TableFooterGroup { which = 2usize }
                if which == pass {
                    var r = kb.first
                    while r != NONE {
                        if l.boxes.items[usize(r)].inner == .Row {
                            let pushed = list.push[u32](out, r)
                        }
                        r = l.boxes.items[usize(r)].next
                    }
                }
            }
            kid = kb.next
        }
        pass += 1usize
    }
}

fn is_pct_width(len: style.Len) -> bool { ret len.kind == .Px && len.pct > 0.0f64 && len.px == 0.0f64 }

// The cell grid and the per-column minimum and maximum widths of table box `t` (cached in `aux2`).
fn build_table(l: *Layout, t: u32) -> u32 {
    if l.boxes.items[usize(t)].aux2 != 0u32 { ret l.boxes.items[usize(t)].aux2 - 1u32 }
    let ts = bstyle(l, t)
    let (rows_made, re) = list.init[u32](l.a, 16usize)
    let (cells_made, ce) = list.init[CellInfo](l.a, 32usize)
    if re != ok || ce != ok { ret 0u32 }
    var rows = rows_made
    var cells = cells_made
    row_order(l, t, &rows)
    let nrows = rows.len
    let wcap = 128usize
    let (occ, oe) = mem.alloc[bool](l.a, nrows * wcap + 1usize)
    if oe != ok { ret 0u32 }
    var z = 0usize
    while z < nrows * wcap + 1usize {
        occ[z] = false
        z += 1usize
    }
    var ncols = 0usize
    var r = 0usize
    while r < nrows {
        var col = 0usize
        var c = l.boxes.items[usize(rows.items[r])].first
        while c != NONE {
            if l.boxes.items[usize(c)].inner == .Cell {
                while col < wcap && occ[r * wcap + col] { col += 1usize }
                if col >= wcap { break }
                let node = l.boxes.items[usize(c)].node
                var cs = span_attr(l, node, "colspan")
                var rs = span_attr(l, node, "rowspan")
                if col + cs > wcap { cs = wcap - col }
                if r + rs > nrows { rs = nrows - r }
                var rr = 0usize
                while rr < rs {
                    var cc = 0usize
                    while cc < cs {
                        occ[(r + rr) * wcap + col + cc] = true
                        cc += 1usize
                    }
                    rr += 1usize
                }
                let pushed = list.push[CellInfo](&cells, CellInfo { box: c, row: r, col: col, rs: rs, cs: cs, min: 0.0f64, max: 0.0f64, spec: -1.0f64, pct: -1.0f64 })
                if col + cs > ncols { ncols = col + cs }
                col += cs
            }
            c = l.boxes.items[usize(c)].next
        }
        r += 1usize
    }
    // Columns declared by <col> and <colgroup> may add empty columns.
    var dcol = 0usize
    var kid = l.boxes.items[usize(t)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Column {
            dcol += span_attr(l, kb.node, "span")
        } else if kb.inner == .ColumnGroup {
            var inner_cols = 0usize
            var cc = kb.first
            while cc != NONE {
                if l.boxes.items[usize(cc)].inner == .Column { inner_cols += span_attr(l, l.boxes.items[usize(cc)].node, "span") }
                cc = l.boxes.items[usize(cc)].next
            }
            if inner_cols == 0usize { dcol += span_attr(l, kb.node, "span") } else { dcol += inner_cols }
        }
        kid = kb.next
    }
    if dcol > ncols && dcol <= wcap { ncols = dcol }
    let (cmin, e1) = mem.alloc[f64](l.a, ncols + 1usize)
    let (cmax, e2) = mem.alloc[f64](l.a, ncols + 1usize)
    let (cw, e3) = mem.alloc[f64](l.a, ncols + 1usize)
    let (cpct, e4) = mem.alloc[f64](l.a, ncols + 1usize)
    let (cspec, e5) = mem.alloc[f64](l.a, ncols + 1usize)
    let (rh, e6) = mem.alloc[f64](l.a, nrows + 1usize)
    let (ry, e7) = mem.alloc[f64](l.a, nrows + 1usize)
    let (rb, e8) = mem.alloc[u32](l.a, nrows + 1usize)
    let (rab, e9) = mem.alloc[f64](l.a, nrows + 1usize)
    let (rbe, e10) = mem.alloc[f64](l.a, nrows + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret 0u32 }
    var k = 0usize
    while k < ncols + 1usize {
        cmin[k] = 0.0f64
        cmax[k] = 0.0f64
        cw[k] = 0.0f64
        cpct[k] = -1.0f64
        cspec[k] = -1.0f64
        k += 1usize
    }
    k = 0usize
    while k < nrows + 1usize {
        rh[k] = 0.0f64
        ry[k] = 0.0f64
        rab[k] = 0.0f64
        rbe[k] = 0.0f64
        if k < nrows { rb[k] = rows.items[k] } else { rb[k] = NONE }
        k += 1usize
    }
    var sh = ts.border_spacing_h
    var sv = ts.border_spacing_v
    if ts.border_collapse == .Collapse {
        sh = 0.0f64
        sv = 0.0f64
    }
    var hedge: []Edge = zero
    var vedge: []Edge = zero
    var collapsed = false
    if ts.border_collapse == .Collapse {
        let (he2, ve2) = collapse_edges(l, t, &cells, rb[0usize..nrows], nrows, ncols)
        hedge = he2
        vedge = ve2
        collapsed = true
    }
    // Per-cell content widths.
    var ci = 0usize
    while ci < cells.len {
        let c = cells.items[ci].box
        let cs = bstyle(l, c)
        resolve_edges(l, c, 0.0f64)
        let extras = horizontal_extras(&l.boxes.items[usize(c)])
        let (mn, mx) = content_widths(l, c)
        var min_w = mn + extras
        var max_w = mx + extras
        let (wv, has_w) = resolve_len(cs.width, -1.0f64)
        if cs.width.kind == .Px && has_w {
            let spec = to_content_w(l, c, wv) + extras
            cells.items[ci].spec = spec
            max_w = maxf(min_w, spec)
        } else if is_pct_width(cs.width) {
            cells.items[ci].pct = cs.width.pct
        }
        cells.items[ci].min = min_w
        cells.items[ci].max = max_w
        ci += 1usize
    }
    // <col width> hints.
    var cursor = 0usize
    kid = l.boxes.items[usize(t)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Column {
            let span = span_attr(l, kb.node, "span")
            let ws = st(l, kb.style)
            let (wv, has_w) = resolve_len(ws.width, -1.0f64)
            var q = 0usize
            while q < span && cursor + q < ncols {
                if ws.width.kind == .Px && has_w { cspec[cursor + q] = wv }
                q += 1usize
            }
            cursor += span
        } else if kb.inner == .ColumnGroup {
            // The <col> children of a <colgroup>; a group without any stands for `span` columns itself.
            var gkid = kb.first
            var had_cols = false
            while gkid != NONE {
                let gk = &l.boxes.items[usize(gkid)]
                if gk.inner == .Column {
                    had_cols = true
                    let gspan = span_attr(l, gk.node, "span")
                    let gws = st(l, gk.style)
                    let (gwv, ghas) = resolve_len(gws.width, -1.0f64)
                    var gq = 0usize
                    while gq < gspan && cursor + gq < ncols {
                        if gws.width.kind == .Px && ghas { cspec[cursor + gq] = gwv }
                        gq += 1usize
                    }
                    cursor += gspan
                }
                gkid = gk.next
            }
            if !had_cols {
                let gspan2 = span_attr(l, kb.node, "span")
                let gws2 = st(l, kb.style)
                let (gwv2, ghas2) = resolve_len(gws2.width, -1.0f64)
                var gq2 = 0usize
                while gq2 < gspan2 && cursor + gq2 < ncols {
                    if gws2.width.kind == .Px && ghas2 { cspec[cursor + gq2] = gwv2 }
                    gq2 += 1usize
                }
                cursor += gspan2
            }
        }
        kid = kb.next
    }
    // Single-column cells first, then the spanning ones top up what the columns lack.
    var pass = 0usize
    while pass < 2usize {
        ci = 0usize
        while ci < cells.len {
            let info = cells.items[ci]
            ci += 1usize
            if (pass == 0usize) != (info.cs == 1usize) { continue }
            if info.cs == 1usize {
                cmin[info.col] = maxf(cmin[info.col], info.min)
                cmax[info.col] = maxf(cmax[info.col], info.max)
                if info.spec >= 0.0f64 { cspec[info.col] = maxf(cspec[info.col], info.spec) }
                if info.pct >= 0.0f64 { cpct[info.col] = maxf(cpct[info.col], info.pct) }
            } else {
                var smin = sh * f64(info.cs - 1usize)
                var smax = smin
                var q = 0usize
                while q < info.cs {
                    smin += cmin[info.col + q]
                    smax += cmax[info.col + q]
                    q += 1usize
                }
                if info.min > smin {
                    let add = (info.min - smin) / f64(info.cs)
                    q = 0usize
                    while q < info.cs {
                        cmin[info.col + q] += add
                        q += 1usize
                    }
                }
                if info.max > smax {
                    let add = (info.max - smax) / f64(info.cs)
                    q = 0usize
                    while q < info.cs {
                        cmax[info.col + q] += add
                        q += 1usize
                    }
                }
            }
        }
        pass += 1usize
    }
    var sum_min = 0.0f64
    var sum_max = 0.0f64
    k = 0usize
    while k < ncols {
        if cspec[k] >= 0.0f64 { cmax[k] = maxf(cmax[k], cspec[k]) }
        cmax[k] = maxf(cmax[k], cmin[k])
        sum_min += cmin[k]
        sum_max += cmax[k]
        k += 1usize
    }
    let td = TableData { cols: ncols, rows: nrows, cells: cells, col_min: cmin, col_max: cmax, col_w: cw, col_pct: cpct, col_spec: cspec, row_h: rh, row_y: ry, row_box: rb, row_above: rab, row_below: rbe, sh: sh, sv: sv, sum_min: sum_min, sum_max: sum_max, collapsed: collapsed, hedge: hedge, vedge: vedge, cap_t: 0.0f64, cap_b: 0.0f64 }
    let pushed = list.push[TableData](&l.tables, td)
    let index = u32(l.tables.len) - 1u32
    l.boxes.items[usize(t)].aux2 = index + 1u32
    ret index
}

// --- Collapsed borders (CSS 2.1 17.6.2).

// One grid-line segment's border after conflict resolution; `prio` ranks the element it came from (cell 5, row 4, row group 3,
// column 2, column group 1, table 0).
type Edge = struct { w: f64, bs: style.BorderStyle, color: u32, prio: u8, set: bool }

fn style_rank(b: style.BorderStyle) -> u8 {
    if b == .Double { ret 9u8 }
    if b == .Solid { ret 8u8 }
    if b == .Dashed { ret 7u8 }
    if b == .Dotted { ret 6u8 }
    if b == .Ridge { ret 5u8 }
    if b == .Outset { ret 4u8 }
    if b == .Groove { ret 3u8 }
    if b == .Inset { ret 2u8 }
    ret 0u8
}

fn edge_of(l: *const Layout, b: u32, side: usize, prio: u8) -> Edge {
    if b == NONE { ret Edge { w: 0.0f64, bs: .None, color: 0u32, prio: prio, set: false } }
    let s = st(l, l.boxes.items[usize(b)].style)
    var c = s.border_color[side]
    if s.border_current[side] { c = s.color }
    ret Edge { w: s.border_width[side], bs: s.border_style[side], color: c, prio: prio, set: s.border_style[side] != .None || s.border_width[side] > 0.0f64 }
}

// Whether `a` beats `b` for a shared grid line: hidden wins, then the wider, then the style, then the element's rank.
fn edge_wins(a: Edge, b: Edge) -> bool {
    if !a.set { ret false }
    if !b.set { ret true }
    if b.bs == .Hidden { ret false }
    if a.bs == .Hidden { ret true }
    if a.bs == .None { ret false }
    if b.bs == .None { ret true }
    if a.w != b.w { ret a.w > b.w }
    let ra = style_rank(a.bs)
    let rb = style_rank(b.bs)
    if ra != rb { ret ra > rb }
    ret a.prio > b.prio
}

fn put_edge(arr: []Edge, at: usize, e: Edge) {
    if edge_wins(e, arr[at]) { arr[at] = e }
}

// Resolves the collapsed edges of table `t` (grid `ncols` x `nrows`, `rows[r]` the row boxes) into `hedge` ((nrows + 1) x ncols,
// the line above row r) and `vedge` (nrows x (ncols + 1), the line left of column c), and gives every cell, row, group and the
// table the half of each edge that lies inside it.
fn collapse_edges(l: *Layout, t: u32, cells: *const list.List[CellInfo], rows: []const u32, nrows: usize, ncols: usize) -> ([]Edge, []Edge) {
    let none = Edge { w: 0.0f64, bs: .None, color: 0u32, prio: 0u8, set: false }
    let (hedge, he) = mem.alloc[Edge](l.a, (nrows + 1usize) * (ncols + 1usize))
    let (vedge, ve) = mem.alloc[Edge](l.a, (nrows + 1usize) * (ncols + 1usize))
    if he != ok || ve != ok { ret (zero, zero) }
    var k = 0usize
    while k < hedge.len {
        hedge[k] = none
        vedge[k] = none
        k += 1usize
    }
    let hw = ncols + 1usize
    // The table itself.
    var c = 0usize
    while c < ncols {
        put_edge(hedge, c, edge_of(l, t, 0usize, 0u8))
        put_edge(hedge, nrows * hw + c, edge_of(l, t, 2usize, 0u8))
        c += 1usize
    }
    var r = 0usize
    while r < nrows {
        put_edge(vedge, r * hw, edge_of(l, t, 3usize, 0u8))
        put_edge(vedge, r * hw + ncols, edge_of(l, t, 1usize, 0u8))
        r += 1usize
    }
    // Column groups and columns.
    var cursor = 0usize
    var kid = l.boxes.items[usize(t)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Column || kb.inner == .ColumnGroup {
            var gstart = cursor
            var gcols = 0usize
            if kb.inner == .Column {
                gcols = span_attr(l, kb.node, "span")
            } else {
                var cc = kb.first
                while cc != NONE {
                    if l.boxes.items[usize(cc)].inner == .Column { gcols += span_attr(l, l.boxes.items[usize(cc)].node, "span") }
                    cc = l.boxes.items[usize(cc)].next
                }
                if gcols == 0usize { gcols = span_attr(l, kb.node, "span") }
            }
            var prio = 2u8
            if kb.inner == .ColumnGroup { prio = 1u8 }
            var j = 0usize
            while j < gcols && gstart + j < ncols {
                var rr = 0usize
                while rr < nrows {
                    if j == 0usize { put_edge(vedge, rr * hw + gstart, edge_of(l, kid, 3usize, prio)) }
                    if j + 1usize == gcols { put_edge(vedge, rr * hw + gstart + j + 1usize, edge_of(l, kid, 1usize, prio)) }
                    rr += 1usize
                }
                put_edge(hedge, gstart + j, edge_of(l, kid, 0usize, prio))
                put_edge(hedge, nrows * hw + gstart + j, edge_of(l, kid, 2usize, prio))
                j += 1usize
            }
            if kb.inner == .ColumnGroup {
                // The columns inside a group add their own edges.
                var cc2 = kb.first
                var cj = gstart
                while cc2 != NONE {
                    if l.boxes.items[usize(cc2)].inner == .Column {
                        let sp = span_attr(l, l.boxes.items[usize(cc2)].node, "span")
                        var q = 0usize
                        while q < sp && cj + q < ncols {
                            var rr2 = 0usize
                            while rr2 < nrows {
                                if q == 0usize { put_edge(vedge, rr2 * hw + cj, edge_of(l, cc2, 3usize, 2u8)) }
                                if q + 1usize == sp { put_edge(vedge, rr2 * hw + cj + q + 1usize, edge_of(l, cc2, 1usize, 2u8)) }
                                rr2 += 1usize
                            }
                            put_edge(hedge, cj + q, edge_of(l, cc2, 0usize, 2u8))
                            put_edge(hedge, nrows * hw + cj + q, edge_of(l, cc2, 2usize, 2u8))
                            q += 1usize
                        }
                        cj += sp
                    }
                    cc2 = l.boxes.items[usize(cc2)].next
                }
                cursor += gcols
            } else {
                cursor += gcols
            }
        }
        kid = kb.next
    }
    // Rows and row groups.
    r = 0usize
    while r < nrows {
        let rb = rows[r]
        if rb != NONE {
            var cj2 = 0usize
            while cj2 < ncols {
                put_edge(hedge, r * hw + cj2, edge_of(l, rb, 0usize, 4u8))
                put_edge(hedge, (r + 1usize) * hw + cj2, edge_of(l, rb, 2usize, 4u8))
                cj2 += 1usize
            }
            put_edge(vedge, r * hw, edge_of(l, rb, 3usize, 4u8))
            put_edge(vedge, r * hw + ncols, edge_of(l, rb, 1usize, 4u8))
            let grp = l.boxes.items[usize(rb)].parent
            if grp != NONE && grp != t && l.boxes.items[usize(grp)].inner == .RowGroup {
                var first_row = r
                while first_row > 0usize && rows[first_row - 1usize] != NONE && l.boxes.items[usize(rows[first_row - 1usize])].parent == grp { first_row -= 1usize }
                var last_row = r
                while last_row + 1usize < nrows && rows[last_row + 1usize] != NONE && l.boxes.items[usize(rows[last_row + 1usize])].parent == grp { last_row += 1usize }
                var gj = 0usize
                while gj < ncols {
                    if r == first_row { put_edge(hedge, r * hw + gj, edge_of(l, grp, 0usize, 3u8)) }
                    if r == last_row { put_edge(hedge, (r + 1usize) * hw + gj, edge_of(l, grp, 2usize, 3u8)) }
                    gj += 1usize
                }
                put_edge(vedge, r * hw, edge_of(l, grp, 3usize, 3u8))
                put_edge(vedge, r * hw + ncols, edge_of(l, grp, 1usize, 3u8))
            }
        }
        r += 1usize
    }
    // Cells (document order: on a tie the earlier one stays).
    var ci = 0usize
    while ci < cells.len {
        let info = cells.items[ci]
        ci += 1usize
        var j2 = 0usize
        while j2 < info.cs && info.col + j2 < ncols {
            put_edge(hedge, info.row * hw + info.col + j2, edge_of(l, info.box, 0usize, 5u8))
            put_edge(hedge, (info.row + info.rs) * hw + info.col + j2, edge_of(l, info.box, 2usize, 5u8))
            j2 += 1usize
        }
        var i2 = 0usize
        while i2 < info.rs && info.row + i2 < nrows {
            put_edge(vedge, (info.row + i2) * hw + info.col, edge_of(l, info.box, 3usize, 5u8))
            put_edge(vedge, (info.row + i2) * hw + info.col + info.cs, edge_of(l, info.box, 1usize, 5u8))
            i2 += 1usize
        }
    }
    // Each cell's border is half of the widest edge along each of its sides; the table keeps half of the outer ones.
    ci = 0usize
    while ci < cells.len {
        let info2 = cells.items[ci]
        ci += 1usize
        var top = 0.0f64
        var bottom = 0.0f64
        var left = 0.0f64
        var right = 0.0f64
        var j3 = 0usize
        while j3 < info2.cs && info2.col + j3 < ncols {
            let a = hedge[info2.row * hw + info2.col + j3]
            let b2 = hedge[(info2.row + info2.rs) * hw + info2.col + j3]
            if a.set && a.bs != .Hidden && a.bs != .None { top = maxf(top, a.w) }
            if b2.set && b2.bs != .Hidden && b2.bs != .None { bottom = maxf(bottom, b2.w) }
            j3 += 1usize
        }
        var i3 = 0usize
        while i3 < info2.rs && info2.row + i3 < nrows {
            let a2 = vedge[(info2.row + i3) * hw + info2.col]
            let b3 = vedge[(info2.row + i3) * hw + info2.col + info2.cs]
            if a2.set && a2.bs != .Hidden && a2.bs != .None { left = maxf(left, a2.w) }
            if b3.set && b3.bs != .Hidden && b3.bs != .None { right = maxf(right, b3.w) }
            i3 += 1usize
        }
        let cb = &l.boxes.items[usize(info2.box)]
        cb.coll = true
        cb.cbd[0usize] = top / 2.0f64
        cb.cbd[1usize] = right / 2.0f64
        cb.cbd[2usize] = bottom / 2.0f64
        cb.cbd[3usize] = left / 2.0f64
    }
    var tt = 0.0f64
    var tb = 0.0f64
    var tl = 0.0f64
    var tr = 0.0f64
    c = 0usize
    while c < ncols {
        let a3 = hedge[c]
        let b4 = hedge[nrows * hw + c]
        if a3.set && a3.bs != .Hidden && a3.bs != .None { tt = maxf(tt, a3.w) }
        if b4.set && b4.bs != .Hidden && b4.bs != .None { tb = maxf(tb, b4.w) }
        c += 1usize
    }
    r = 0usize
    while r < nrows {
        let a4 = vedge[r * hw]
        let b5 = vedge[r * hw + ncols]
        if a4.set && a4.bs != .Hidden && a4.bs != .None { tl = maxf(tl, a4.w) }
        if b5.set && b5.bs != .Hidden && b5.bs != .None { tr = maxf(tr, b5.w) }
        r += 1usize
    }
    let tbx = &l.boxes.items[usize(t)]
    tbx.coll = true
    tbx.cbd[0usize] = tt / 2.0f64
    tbx.cbd[1usize] = tr / 2.0f64
    tbx.cbd[2usize] = tb / 2.0f64
    tbx.cbd[3usize] = tl / 2.0f64
    tbx.border = tbx.cbd
    // Rows, row groups and columns have no border box of their own in the collapsing model.
    r = 0usize
    while r < nrows {
        if rows[r] != NONE {
            let rbx = &l.boxes.items[usize(rows[r])]
            rbx.coll = true
            let g = rbx.parent
            if g != NONE && g != t && l.boxes.items[usize(g)].inner == .RowGroup { l.boxes.items[usize(g)].coll = true }
        }
        r += 1usize
    }
    ret (hedge, vedge)
}

// The min and max content widths of a table box's content: the columns plus the spacing.
fn table_widths(l: *Layout, t: u32) -> (f64, f64) {
    let ti = build_table(l, t)
    let td = l.tables.items[usize(ti)]
    let gaps = td.sh * f64(td.cols + 1usize)
    // A fixed layout ignores the cells' content: only the columns with a specified width count towards the minimum.
    let ts = bstyle(l, t)
    if ts.table_layout == .Fixed && ts.width.kind == .Px {
        var spec_sum = 0.0f64
        var k = 0usize
        while k < td.cols {
            if td.col_spec[k] >= 0.0f64 { spec_sum += td.col_spec[k] }
            k += 1usize
        }
        ret (spec_sum + gaps, td.sum_max + gaps)
    }
    ret (td.sum_min + gaps, td.sum_max + gaps)
}

fn table_min_width(l: *Layout, t: u32) -> f64 {
    let (mn, _mx) = table_widths(l, t)
    ret mn
}

// Column widths for a table content width `tw` (spacing included).
fn distribute_columns(l: *Layout, ti: u32, tw: f64, fixed_layout: bool) {
    let td = l.tables.items[usize(ti)]
    if td.cols == 0usize { ret }
    let avail = maxf(0.0f64, tw - td.sh * f64(td.cols + 1usize))
    var k = 0usize
    if fixed_layout {
        var used = 0.0f64
        var autos = 0usize
        while k < td.cols {
            if td.col_spec[k] >= 0.0f64 {
                td.col_w[k] = td.col_spec[k]
                used += td.col_spec[k]
            } else {
                td.col_w[k] = -1.0f64
                autos += 1usize
            }
            k += 1usize
        }
        k = 0usize
        while k < td.cols {
            if td.col_w[k] < 0.0f64 {
                if autos > 0usize { td.col_w[k] = maxf(0.0f64, (avail - used) / f64(autos)) } else { td.col_w[k] = 0.0f64 }
            }
            k += 1usize
        }
        ret
    }
    // Percentage columns take their share, the rest share what is left.
    var pct_sum = 0.0f64
    var pct_w = 0.0f64
    while k < td.cols {
        td.col_w[k] = -1.0f64
        if td.col_pct[k] >= 0.0f64 && pct_sum + td.col_pct[k] <= 1.0001f64 {
            let w = maxf(td.col_min[k], td.col_pct[k] * avail)
            td.col_w[k] = w
            pct_sum += td.col_pct[k]
            pct_w += w
        }
        k += 1usize
    }
    var rem_min = 0.0f64
    var rem_max = 0.0f64
    var auto_max = 0.0f64
    var auto_n = 0usize
    var rem_n = 0usize
    k = 0usize
    while k < td.cols {
        if td.col_w[k] < 0.0f64 {
            rem_min += td.col_min[k]
            rem_max += td.col_max[k]
            rem_n += 1usize
            if td.col_spec[k] < 0.0f64 {
                auto_max += td.col_max[k]
                auto_n += 1usize
            }
        }
        k += 1usize
    }
    let room = avail - pct_w
    k = 0usize
    while k < td.cols {
        if td.col_w[k] < 0.0f64 {
            var w = td.col_min[k]
            if room >= rem_max {
                // Extra width goes to the columns without a specified width, in proportion to their widths.
                let extra = room - rem_max
                w = td.col_max[k]
                if auto_n > 0usize {
                    if td.col_spec[k] < 0.0f64 {
                        if auto_max > 0.0f64 { w += extra * td.col_max[k] / auto_max } else { w += extra / f64(auto_n) }
                    }
                } else if rem_max > 0.0f64 {
                    w += extra * td.col_max[k] / rem_max
                } else {
                    w += extra / f64(rem_n)
                }
            } else if room > rem_min && rem_max > rem_min {
                w = td.col_min[k] + (td.col_max[k] - td.col_min[k]) * (room - rem_min) / (rem_max - rem_min)
            }
            td.col_w[k] = w
        }
        k += 1usize
    }
}

fn is_baseline_valign(v: style.VAlign) -> bool {
    ret v != .Top && v != .Middle && v != .Bottom
}

// Lays out table box `t` with content width `cw` (`ch`: the specified content height or negative); returns the content
// height: top captions, the row grid, bottom captions.
fn layout_table(l: *Layout, t: u32, cw: f64, ch: f64) -> f64 {
    let ti = build_table(l, t)
    let ts = bstyle(l, t)
    distribute_columns(l, ti, cw, ts.table_layout == .Fixed && ts.width.kind == .Px)
    let td = l.tables.items[usize(ti)]
    let sh = td.sh
    let sv = td.sv
    let (cx, e1) = mem.alloc[f64](l.a, td.cols + 1usize)
    let (cell_h, e2) = mem.alloc[f64](l.a, td.cells.len + 1usize)
    let (cell_up, e3) = mem.alloc[f64](l.a, td.cells.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 }
    var x = sh
    var k = 0usize
    while k < td.cols {
        cx[k] = x
        x += td.col_w[k] + sh
        k += 1usize
    }
    let grid_w = x
    // Rows start at their specified heights.
    var r = 0usize
    while r < td.rows {
        td.row_h[r] = 0.0f64
        td.row_above[r] = 0.0f64
        td.row_below[r] = 0.0f64
        let rs = st(l, l.boxes.items[usize(td.row_box[r])].style)
        let (rv, has_rv) = resolve_len(rs.height, -1.0f64)
        if rs.height.kind == .Px && has_rv { td.row_h[r] = rv }
        r += 1usize
    }
    // Lay out the cells at their column widths; remember the heights and baselines.
    var ci = 0usize
    while ci < td.cells.len {
        let info = td.cells.items[ci]
        let c = info.box
        let cs = bstyle(l, c)
        var w = sh * f64(info.cs - 1usize)
        var q = 0usize
        while q < info.cs {
            w += td.col_w[info.col + q]
            q += 1usize
        }
        resolve_edges(l, c, cw)
        let cb = bx(l, c)
        cb.margin[0usize] = 0.0f64
        cb.margin[1usize] = 0.0f64
        cb.margin[2usize] = 0.0f64
        cb.margin[3usize] = 0.0f64
        cb.w = w
        let content_w = maxf(0.0f64, w - horizontal_extras(cb))
        let auto_h = layout_in_new_bfc(l, c, content_w, -1.0f64)
        var content_h = auto_h
        let (hv, has_h) = resolve_len(cs.height, -1.0f64)
        if cs.height.kind == .Px && has_h { content_h = maxf(content_h, to_content_h(l, c, hv)) }
        let cb2 = bx(l, c)
        cell_h[ci] = content_h + vertical_extras(cb2)
        cell_up[ci] = -1.0f64
        if info.rs == 1usize {
            if is_baseline_valign(cs.vertical_align) {
                let (found, by) = first_baseline(l, c)
                var up = cb2.border[0usize] + cb2.padding[0usize]
                if found { up = by }
                cell_up[ci] = up
                td.row_above[info.row] = maxf(td.row_above[info.row], up)
                td.row_below[info.row] = maxf(td.row_below[info.row], cell_h[ci] - up)
            } else {
                td.row_h[info.row] = maxf(td.row_h[info.row], cell_h[ci])
            }
        }
        ci += 1usize
    }
    r = 0usize
    while r < td.rows {
        td.row_h[r] = maxf(td.row_h[r], td.row_above[r] + td.row_below[r])
        r += 1usize
    }
    // Spanning cells add what the rows they cover lack, to the last of them.
    ci = 0usize
    while ci < td.cells.len {
        let info = td.cells.items[ci]
        if info.rs > 1usize {
            var have = sv * f64(info.rs - 1usize)
            var q = 0usize
            while q < info.rs {
                have += td.row_h[info.row + q]
                q += 1usize
            }
            if cell_h[ci] > have { td.row_h[info.row + info.rs - 1usize] += cell_h[ci] - have }
        }
        ci += 1usize
    }
    // A specified table height spreads its surplus over the rows.
    var rows_h = sv
    r = 0usize
    while r < td.rows {
        rows_h += td.row_h[r] + sv
        r += 1usize
    }
    if ch >= 0.0f64 && td.rows > 0usize && ch > rows_h {
        let extra = (ch - rows_h) / f64(td.rows)
        r = 0usize
        while r < td.rows {
            td.row_h[r] += extra
            r += 1usize
        }
        rows_h = ch
    }
    // Captions: laid out at the table's content width, above or below the grid.
    var cap_top = 0.0f64
    var cap_bottom = 0.0f64
    var kid = bx(l, t).first
    while kid != NONE {
        if l.boxes.items[usize(kid)].inner == .Caption {
            let cs = bstyle(l, kid)
            resolve_edges(l, kid, cw)
            resolve_margins_fixed(l, kid, cw)
            let cap = bx(l, kid)
            cap.w = maxf(0.0f64, cw + horizontal_extras(bx(l, t)) - cap.margin[1usize] - cap.margin[3usize])
            let content_w = maxf(0.0f64, cap.w - horizontal_extras(cap))
            var cap_spec_h = -1.0f64
            let (cap_hv, cap_has_h) = resolve_len(cs.height, -1.0f64)
            if cs.height.kind == .Px && cap_has_h { cap_spec_h = to_content_h(l, kid, cap_hv) }
            let h = layout_in_new_bfc(l, kid, content_w, cap_spec_h)
            let cap2 = bx(l, kid)
            var cap_content_h = h
            if cap_spec_h >= 0.0f64 { cap_content_h = cap_spec_h }
            cap2.h = cap_content_h + vertical_extras(cap2)
            let outer = cap2.h + cap2.margin[0usize] + cap2.margin[2usize]
            if cs.caption_side == .Bottom { cap_bottom += outer } else { cap_top += outer }
        }
        kid = l.boxes.items[usize(kid)].next
    }
    l.tables.items[usize(ti)].cap_t = cap_top
    l.tables.items[usize(ti)].cap_b = cap_bottom
    // Positions in the table's border-box coordinates.
    let tb = bx(l, t)
    let gx = tb.border[3usize] + tb.padding[3usize]
    let gy = tb.border[0usize] + tb.padding[0usize] + cap_top
    var y = sv
    r = 0usize
    while r < td.rows {
        td.row_y[r] = y
        y += td.row_h[r] + sv
        r += 1usize
    }
    var grid_h = y
    if td.rows == 0usize { grid_h = 0.0f64 }
    var group = NONE
    var group_top = 0.0f64
    r = 0usize
    while r < td.rows {
        let rbx = td.row_box[r]
        let parent = l.boxes.items[usize(rbx)].parent
        let rb = bx(l, rbx)
        rb.w = grid_w
        rb.h = td.row_h[r]
        if parent != t {
            if parent != group {
                group = parent
                group_top = td.row_y[r]
                let gb = bx(l, group)
                gb.x = gx
                gb.y = gy + group_top
                gb.w = grid_w
            }
            let gb2 = bx(l, group)
            gb2.h = td.row_y[r] + td.row_h[r] - group_top
            let rb2 = bx(l, rbx)
            rb2.x = 0.0f64
            rb2.y = td.row_y[r] - group_top
        } else {
            group = NONE
            rb.x = gx
            rb.y = gy + td.row_y[r]
        }
        r += 1usize
    }
    // Cells: the border box fills the spanned rows; the content moves down for middle/bottom/baseline alignment.
    ci = 0usize
    while ci < td.cells.len {
        let info = td.cells.items[ci]
        let c = info.box
        let cs = bstyle(l, c)
        var span_h = sv * f64(info.rs - 1usize)
        var q = 0usize
        while q < info.rs {
            span_h += td.row_h[info.row + q]
            q += 1usize
        }
        var dy = 0.0f64
        if info.rs == 1usize && cell_up[ci] >= 0.0f64 {
            dy = td.row_above[info.row] - cell_up[ci]
        } else if cs.vertical_align == .Middle {
            dy = (span_h - cell_h[ci]) / 2.0f64
        } else if cs.vertical_align == .Bottom {
            dy = span_h - cell_h[ci]
        }
        let cb = bx(l, c)
        cb.x = cx[info.col]
        cb.y = 0.0f64
        cb.h = span_h
        if dy > 0.5f64 {
            // Re-lay the contents with the alignment offset added to the top padding; the used padding keeps it, which
            // is where the content starts.
            cb.padding[0usize] += dy
            let content_w = maxf(0.0f64, cb.w - horizontal_extras(cb))
            let discard = layout_in_new_bfc(l, c, content_w, -1.0f64)
            let cb3 = bx(l, c)
            cb3.h = span_h
        }
        set_baseline(l, c)
        ci += 1usize
    }
    // Captions go above and below the grid.
    let tb2 = bx(l, t)
    var cur_top = 0.0f64
    var cur_bottom = cap_top + tb2.border[0usize] + tb2.padding[0usize] + grid_h + tb2.padding[2usize] + tb2.border[2usize]
    kid = tb2.first
    while kid != NONE {
        if l.boxes.items[usize(kid)].inner == .Caption {
            let cs = bstyle(l, kid)
            let cap = bx(l, kid)
            cap.x = cap.margin[3usize]
            if cs.caption_side == .Bottom {
                cap.y = cur_bottom + cap.margin[0usize]
                cur_bottom += cap.h + cap.margin[0usize] + cap.margin[2usize]
            } else {
                cap.y = cur_top + cap.margin[0usize]
                cur_top += cap.h + cap.margin[0usize] + cap.margin[2usize]
            }
        }
        kid = l.boxes.items[usize(kid)].next
    }
    let tb3 = bx(l, t)
    tb3.overflow_w = maxf(tb3.overflow_w, grid_w)
    // Row groups, rows, cells and captions can be relatively positioned too.
    relative_table_parts(l, t, grid_w)
    ret cap_top + grid_h + cap_bottom
}

fn relative_table_parts(l: *Layout, b: u32, w: f64) {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let ki = l.boxes.items[usize(kid)].inner
        if ki == .RowGroup || ki == .Row || ki == .Cell || ki == .Caption {
            apply_relative(l, kid, w, -1.0f64)
            relative_table_parts(l, kid, w)
        }
        kid = l.boxes.items[usize(kid)].next
    }
}

// --- Flex layout (CSS Flexbox 9): items, flex lines, flexing lengths, cross sizing, alignment.
// Logical order is main-start to main-end with the start margins being left/top; reversed directions and wrap-reverse
// mirror the finished positions.

type FlexItem = struct {
    box: u32, order: i64, grow: f64, shrink: f64,
    basis: f64, hyp: f64, target: f64, min_main: f64, max_main: f64, frozen: bool,
    ms: f64, me: f64, cs: f64, ce: f64, ams: bool, ame: bool, acs: bool, ace: bool,
    main_ex: f64, cross_ex: f64, cross: f64, up: f64, align: style.Align,
    pos_main: f64, pos_cross: f64
}

fn flex_is_row(s: *const style.Style) -> bool { ret s.flex_direction == .Row || s.flex_direction == .RowReverse }

fn flex_gap(len: style.Len, basis: f64) -> f64 { ret maxf(0.0f64, resolve_or(len, basis, 0.0f64)) }

// A scroll container (`hidden`, `scroll`, `auto`): `visible` and `clip` do not make one.
fn is_scroll_container(s: *const style.Style) -> bool {
    ret s.overflow_x == .Hidden || s.overflow_x == .Scroll || s.overflow_x == .Auto || s.overflow_y == .Hidden || s.overflow_y == .Scroll || s.overflow_y == .Auto
}

fn flex_item_align(cs: *const style.Style, is: *const style.Style) -> style.Align {
    var a = is.align_self
    if a == .Auto { a = cs.align_items }
    if a == .Normal { a = .Stretch }
    ret a
}

fn flex_in(l: *const Layout, kid: u32) -> bool {
    let kb = &l.boxes.items[usize(kid)]
    ret kb.inner != .Marker && !is_out_of_flow(st(l, kb.style))
}

fn flex_widths(l: *Layout, b: u32) -> (f64, f64) {
    let cs = bstyle(l, b)
    let row = flex_is_row(cs)
    let wrap = cs.flex_wrap != .Nowrap
    var mn = 0.0f64
    var mx = 0.0f64
    var n = 0usize
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        if flex_in(l, kid) {
            let (kmn, kmx0) = outer_content_widths(l, kid)
            var kmx = kmx0
            let ks = bstyle(l, kid)
            if row && ks.flex_basis.kind == .Px && ks.flex_basis.pct == 0.0f64 {
                let kb = &l.boxes.items[usize(kid)]
                let extras = horizontal_extras(kb) + kb.margin[1usize] + kb.margin[3usize]
                kmx = clamp_width(l, kid, to_content_w(l, kid, ks.flex_basis.px), -1.0f64) + extras
                kmx = maxf(kmx, kmn)
            }
            if row {
                mx += kmx
                if wrap { mn = maxf(mn, kmn) } else { mn += kmn }
            } else {
                mx = maxf(mx, kmx)
                mn = maxf(mn, kmn)
            }
            n += 1usize
        }
        kid = l.boxes.items[usize(kid)].next
    }
    // A wrapping column container of definite height: its max-content width is the widths of the columns the items fill.
    if !row && wrap && cs.height.kind == .Px && cs.height.pct == 0.0f64 {
        let avail_h = to_content_h(l, b, cs.height.px)
        let rgap = flex_gap(cs.row_gap, avail_h)
        let cgap = flex_gap(cs.column_gap, 0.0f64)
        var cols_w = 0.0f64
        var col_w = 0.0f64
        var used_h = 0.0f64
        var cols = 0usize
        var k2 = l.boxes.items[usize(b)].first
        while k2 != NONE {
            if flex_in(l, k2) {
                let ks2 = bstyle(l, k2)
                let kb2 = &l.boxes.items[usize(k2)]
                let (kmn2, kmx2) = outer_content_widths(l, k2)
                var item_h = 0.0f64
                if ks2.flex_basis.kind == .Px && ks2.flex_basis.pct == 0.0f64 {
                    item_h = ks2.flex_basis.px
                } else if ks2.height.kind == .Px && ks2.height.pct == 0.0f64 {
                    item_h = ks2.height.px
                }
                item_h += kb2.margin[0usize] + kb2.margin[2usize]
                if cols > 0usize && used_h + rgap + item_h > avail_h + 0.001f64 {
                    cols_w += col_w
                    col_w = 0.0f64
                    used_h = 0.0f64
                    cols += 1usize
                }
                if cols == 0usize { cols = 1usize }
                if used_h > 0.0f64 { used_h += rgap }
                used_h += item_h
                col_w = maxf(col_w, kmx2)
            }
            k2 = l.boxes.items[usize(k2)].next
        }
        cols_w += col_w
        if cols > 1usize { cols_w += cgap * f64(cols - 1usize) }
        mx = maxf(mx, cols_w)
    }
    if row && n > 1usize {
        let gap = flex_gap(cs.column_gap, 0.0f64)
        mx += gap * f64(n - 1usize)
        if !wrap { mn += gap * f64(n - 1usize) }
    }
    ret (mn, mx)
}

// The content width a column-flex item (or any item whose width is the cross size) gets.
fn flex_cross_width(l: *Layout, id: u32, cw: f64, stretch: bool) -> f64 {
    let s = bstyle(l, id)
    let bb = bx(l, id)
    let extras = horizontal_extras(bb)
    let avail = cw - bb.margin[3usize] - bb.margin[1usize] - extras
    let (wv, has_w) = resolve_len(s.width, cw)
    if s.width.kind == .Px && has_w { ret maxf(0.0f64, clamp_width(l, id, to_content_w(l, id, wv), cw)) }
    if stretch && s.margin[3usize].kind != .Auto && s.margin[1usize].kind != .Auto { ret maxf(0.0f64, clamp_width(l, id, avail, cw)) }
    if bb.inner == .Replaced {
        let (rw, _rh) = used_replaced_size(l, id, cw, -1.0f64)
        ret rw
    }
    let (mn, mx) = content_widths(l, id)
    ret maxf(0.0f64, clamp_width(l, id, minf(maxf(mn, avail), mx), cw))
}

// Lays item `id` out at content width `w` and content height `hspec` (negative: from its content).
fn flex_place_item(l: *Layout, id: u32, w: f64, hspec: f64) {
    let bb = bx(l, id)
    let ex_h = horizontal_extras(bb)
    let ex_v = vertical_extras(bb)
    if bb.inner == .Replaced {
        let (rw, rh) = used_replaced_size(l, id, w, -1.0f64)
        var h = hspec
        if h < 0.0f64 {
            if rw > 0.0f64 { h = rh * w / rw } else { h = rh }
        }
        let rb = bx(l, id)
        rb.w = w + ex_h
        rb.h = h + ex_v
        rb.has_baseline = false
        ret
    }
    if is_orthogonal(l, id) {
        // Its block size runs across the container: the item takes the size its own content gives it.
        let stretched = l.orth_fb
        l.orth_fb = -1.0f64
        layout_orthogonal(l, id, w, -1.0f64, hspec, stretched)
        set_baseline(l, id)
        ret
    }
    l.orth_fb = -1.0f64
    bb.w = w + ex_h
    // An automatic height follows the aspect ratio from the width the item was given.
    var spec = hspec
    var ratio_h = -1.0f64
    if spec < 0.0f64 {
        let (rh, has_r) = ratio_height(l, id, w)
        if has_r {
            ratio_h = rh
            spec = rh
        }
    }
    let auto_h = layout_in_new_bfc(l, id, w, spec)
    var h = auto_h
    if spec >= 0.0f64 { h = spec }
    if ratio_h >= 0.0f64 { h = maxf(ratio_h, auto_h) }
    h = maxf(0.0f64, clamp_height_auto(l, id, h, -1.0f64, auto_h))
    let nb = bx(l, id)
    nb.overflow_w = maxf(nb.overflow_w, w)
    nb.overflow_h = maxf(nb.overflow_h, auto_h)
    nb.h = h + ex_v
    set_baseline(l, id)
}

// The flex lines of `items[0..n)` broken greedily at `limit` (a single line when `wrap` is false); answers the line count and
// writes the first item of each line (and the end) to `line_start`.
fn flex_breaks(items: []const FlexItem, n: usize, gap_main: f64, limit: f64, wrap: bool, line_start: []usize) -> usize {
    var nlines = 0usize
    var used = 0.0f64
    var i = 0usize
    while i < n {
        let outer = items[i].hyp + items[i].main_ex + items[i].ms + items[i].me
        if i == 0usize {
            line_start[0usize] = 0usize
            nlines = 1usize
            used = outer
        } else if wrap && used + gap_main + outer > limit + 0.001f64 {
            line_start[nlines] = i
            nlines += 1usize
            used = outer
        } else {
            used += gap_main + outer
        }
        i += 1usize
    }
    line_start[nlines] = n
    ret nlines
}

fn layout_flex(l: *Layout, b: u32, cw: f64, ch: f64) -> f64 {
    let cs = bstyle(l, b)
    let row = flex_is_row(cs)
    var rev = cs.flex_direction == .RowReverse || cs.flex_direction == .ColumnReverse
    if row && cs.direction == .Rtl { rev = !rev }
    let wrap = cs.flex_wrap != .Nowrap
    let wrap_rev = cs.flex_wrap == .WrapReverse
    var main_def = ch
    var cross_def = cw
    if row {
        main_def = cw
        cross_def = ch
    }
    var gap_main = flex_gap(cs.row_gap, maxf(ch, 0.0f64))
    var gap_cross = flex_gap(cs.column_gap, cw)
    if row {
        gap_main = flex_gap(cs.column_gap, cw)
        gap_cross = flex_gap(cs.row_gap, maxf(ch, 0.0f64))
    }
    let bb0 = bx(l, b)
    let ox0 = bb0.border[3usize] + bb0.padding[3usize]
    let oy0 = bb0.border[0usize] + bb0.padding[0usize]
    // Collect the items in `order` (ties keep document order).
    var n = 0usize
    var kid = bb0.first
    while kid != NONE {
        if flex_in(l, kid) { n += 1usize }
        kid = l.boxes.items[usize(kid)].next
    }
    if n == 0usize { ret 0.0f64 }
    let (items, ie) = mem.alloc[FlexItem](l.a, n)
    if ie != ok { ret 0.0f64 }
    var count = 0usize
    kid = bx(l, b).first
    while kid != NONE {
        if flex_in(l, kid) {
            let ks = bstyle(l, kid)
            var it: FlexItem = zero
            it.box = kid
            it.order = ks.order
            it.grow = ks.flex_grow
            it.shrink = ks.flex_shrink
            // Insertion sort by order.
            var at = count
            while at > 0usize && items[at - 1usize].order > it.order {
                items[at] = items[at - 1usize]
                at -= 1usize
            }
            items[at] = it
            count += 1usize
        }
        kid = l.boxes.items[usize(kid)].next
    }
    // Margins, edges, flex basis and the hypothetical main size of every item.
    var i = 0usize
    while i < n {
        let id = items[i].box
        let ks = bstyle(l, id)
        resolve_edges(l, id, cw)
        resolve_margins_fixed(l, id, cw)
        let ib = bx(l, id)
        if row {
            items[i].ms = ib.margin[3usize]
            items[i].me = ib.margin[1usize]
            items[i].cs = ib.margin[0usize]
            items[i].ce = ib.margin[2usize]
            items[i].ams = ks.margin[3usize].kind == .Auto
            items[i].ame = ks.margin[1usize].kind == .Auto
            items[i].acs = ks.margin[0usize].kind == .Auto
            items[i].ace = ks.margin[2usize].kind == .Auto
            items[i].main_ex = ib.border[1usize] + ib.border[3usize] + ib.padding[1usize] + ib.padding[3usize]
            items[i].cross_ex = ib.border[0usize] + ib.border[2usize] + ib.padding[0usize] + ib.padding[2usize]
        } else {
            items[i].ms = ib.margin[0usize]
            items[i].me = ib.margin[2usize]
            items[i].cs = ib.margin[3usize]
            items[i].ce = ib.margin[1usize]
            items[i].ams = ks.margin[0usize].kind == .Auto
            items[i].ame = ks.margin[2usize].kind == .Auto
            items[i].acs = ks.margin[3usize].kind == .Auto
            items[i].ace = ks.margin[1usize].kind == .Auto
            items[i].main_ex = ib.border[0usize] + ib.border[2usize] + ib.padding[0usize] + ib.padding[2usize]
            items[i].cross_ex = ib.border[1usize] + ib.border[3usize] + ib.padding[1usize] + ib.padding[3usize]
        }
        if items[i].ams { items[i].ms = 0.0f64 }
        if items[i].ame { items[i].me = 0.0f64 }
        if items[i].acs { items[i].cs = 0.0f64 }
        if items[i].ace { items[i].ce = 0.0f64 }
        // `margin-trim`: the margins that adjoin the container's edges (single-line containers; wrapping ones keep theirs).
        let trim = trim_flags(l, b)
        if trim != 0u8 {
            let single = cs.flex_wrap == .Nowrap
            if row {
                if single && (trim & 1u8) != 0u8 { items[i].cs = 0.0f64 }
                if single && (trim & 2u8) != 0u8 { items[i].ce = 0.0f64 }
                if (trim & 4u8) != 0u8 && i == 0usize { items[i].ms = 0.0f64 }
                if (trim & 8u8) != 0u8 && i + 1usize == n { items[i].me = 0.0f64 }
            } else {
                if (trim & 1u8) != 0u8 && i == 0usize { items[i].ms = 0.0f64 }
                if (trim & 2u8) != 0u8 && i + 1usize == n { items[i].me = 0.0f64 }
                if single && (trim & 4u8) != 0u8 { items[i].cs = 0.0f64 }
                if single && (trim & 8u8) != 0u8 { items[i].ce = 0.0f64 }
            }
        }
        items[i].align = flex_item_align(cs, ks)
        if l.vmode == 0u8 && (items[i].align == .SelfStart || items[i].align == .SelfEnd) {
            // The item's own start and end edges on the cross axis, against the container's.
            var cross_end_far = cs.flex_wrap != .WrapReverse
            var item_end_far = true
            if row {
                if mode_code(ks) != 0u8 { item_end_far = ks.direction != .Rtl }
            } else {
                cross_end_far = cs.direction != .Rtl
                if mode_code(ks) == 0u8 { item_end_far = ks.direction != .Rtl } else { item_end_far = mode_code(ks) == 2u8 }
            }
            let end_side = item_end_far == cross_end_far
            if (items[i].align == .SelfEnd) == end_side { items[i].align = .FlexEnd } else { items[i].align = .FlexStart }
        }
        // Content-box main size: the flex basis, else the main size property, else the content.
        var basis = -1.0f64
        var content_min = 0.0f64
        let fb = ks.flex_basis
        let (fv, has_fb) = resolve_len(fb, main_def)
        var main_len = ks.width
        if !row { main_len = ks.height }
        let (mv, has_m) = resolve_len(main_len, main_def)
        var spec_main = -1.0f64
        if main_len.kind == .Px && has_m {
            if row { spec_main = to_content_w(l, id, mv) } else { spec_main = to_content_h(l, id, mv) }
        }
        if fb.kind == .Px && has_fb {
            if row { basis = to_content_w(l, id, fv) } else { basis = to_content_h(l, id, fv) }
        } else if spec_main >= 0.0f64 {
            basis = spec_main
        }
        // A box with a preferred aspect ratio takes its main size from its definite cross size.
        if basis < 0.0f64 && ib.inner != .Replaced {
            let (rr, has_rr) = box_ratio(l, id)
            if has_rr {
                if row && ks.height.kind == .Px {
                    let (hv3, g3) = resolve_len(ks.height, -1.0f64)
                    if g3 {
                        let (rw3, ok3) = ratio_width(l, id, to_content_h(l, id, hv3))
                        if ok3 { basis = rw3 }
                    }
                } else if row && ks.height.kind != .Px && items[i].align == .Stretch && ch >= 0.0f64 && ks.margin[0usize].kind != .Auto && ks.margin[2usize].kind != .Auto {
                    // Stretched in a container of definite height: that height is the item's cross size.
                    let stretched = maxf(0.0f64, ch - ib.margin[0usize] - ib.margin[2usize] - vertical_extras(ib))
                    let (rw4, ok4) = ratio_width(l, id, stretched)
                    if ok4 { basis = rw4 }
                } else if !row && ks.width.kind == .Px {
                    let (wv3, g4) = resolve_len(ks.width, -1.0f64)
                    if g4 {
                        let cwv = to_content_w(l, id, wv3)
                        if ks.box_sizing == .BorderBox {
                            basis = maxf(0.0f64, (cwv + horizontal_extras(ib)) / rr - vertical_extras(ib))
                        } else {
                            basis = cwv / rr
                        }
                    }
                }
            }
        }
        if row {
            if ib.inner == .Replaced {
                let (rw, _rh) = used_replaced_size(l, id, cw, -1.0f64)
                content_min = rw
                if basis < 0.0f64 { basis = rw }
            } else {
                let (mn, mx) = content_widths(l, id)
                content_min = mn
                if basis < 0.0f64 { basis = mx }
            }
        } else {
            // A column item's content height depends on its width.
            let stretch = items[i].align == .Stretch
            let w = flex_cross_width(l, id, cw, stretch)
            if stretch { l.orth_fb = w }
            if basis < 0.0f64 || spec_main < 0.0f64 || (ks.min_height.kind == .Auto && !is_scroll_container(ks)) {
                flex_place_item(l, id, w, -1.0f64)
                let auto_h = bx(l, id).h - vertical_extras(bx(l, id))
                content_min = auto_h
                if basis < 0.0f64 { basis = auto_h }
            }
        }
        // Automatic minimum size: the content, capped by a specified size; not for scroll containers.
        var min_main = 0.0f64
        var max_main = 1000000000.0f64
        var min_len = ks.min_width
        var max_len = ks.max_width
        if !row {
            min_len = ks.min_height
            max_len = ks.max_height
        }
        let (minv, has_min) = resolve_len(min_len, main_def)
        let (maxv, has_max) = resolve_len(max_len, main_def)
        if min_len.kind == .Px && has_min {
            if row { min_main = to_content_w(l, id, minv) } else { min_main = to_content_h(l, id, minv) }
        } else if min_len.kind == .Auto && !is_scroll_container(ks) {
            min_main = content_min
            if spec_main >= 0.0f64 { min_main = minf(min_main, spec_main) }
        }
        if max_len.kind == .Px && has_max {
            if row { max_main = to_content_w(l, id, maxv) } else { max_main = to_content_h(l, id, maxv) }
        }
        // The automatic minimum size is clamped by a definite max-width / max-height.
        if min_len.kind == .Auto && max_len.kind == .Px && has_max { min_main = minf(min_main, max_main) }
        items[i].basis = maxf(0.0f64, basis)
        items[i].min_main = min_main
        items[i].max_main = maxf(max_main, min_main)
        items[i].hyp = minf(maxf(items[i].basis, min_main), items[i].max_main)
        i += 1usize
    }
    // Flex lines: everything on one line without wrapping, else break when the next item no longer fits.
    var avail = main_def
    if avail < 0.0f64 {
        avail = 0.0f64
        i = 0usize
        while i < n {
            avail += items[i].hyp + items[i].main_ex + items[i].ms + items[i].me
            i += 1usize
        }
        avail += gap_main * f64(n - 1usize)
        // An auto-height column container still grows to its min-height (and stops at its max-height).
        if !row {
            let (cmin, has_cmin) = resolve_len(cs.min_height, ch)
            let (cmax, has_cmax) = resolve_len(cs.max_height, ch)
            if cs.max_height.kind == .Px && has_cmax { avail = minf(avail, to_content_h(l, b, cmax)) }
            if cs.min_height.kind == .Px && has_cmin { avail = maxf(avail, to_content_h(l, b, cmin)) }
        }
    }
    let (line_start, ls_e) = mem.alloc[usize](l.a, n + 1usize)
    let (line_cross, lc_e) = mem.alloc[f64](l.a, n + 1usize)
    let (line_up, lu_e) = mem.alloc[f64](l.a, n + 1usize)
    let (line_pos, lp_e) = mem.alloc[f64](l.a, n + 1usize)
    if ls_e != ok || lc_e != ok || lu_e != ok || lp_e != ok { ret 0.0f64 }
    var nlines = flex_breaks(items, n, gap_main, avail, wrap, line_start)
    // `flex-wrap: balance`: as few lines as `wrap` makes, but the shortest width that still makes no more, so they come out even.
    if cs.flex_wrap == .Balance && nlines > 1usize {
        var lo_w = 0.0f64
        i = 0usize
        while i < n {
            lo_w = maxf(lo_w, items[i].hyp + items[i].main_ex + items[i].ms + items[i].me)
            i += 1usize
        }
        var hi_w = avail
        var step = 0usize
        while step < 24usize {
            let mid = (lo_w + hi_w) / 2.0f64
            if flex_breaks(items, n, gap_main, mid, true, line_start) <= nlines { hi_w = mid } else { lo_w = mid }
            step += 1usize
        }
        nlines = flex_breaks(items, n, gap_main, hi_w, true, line_start)
    }
    // Resolve the flexible lengths of each line.
    var ln = 0usize
    while ln < nlines {
        let lo = line_start[ln]
        let hi = line_start[ln + 1usize]
        var sum_hyp = gap_main * f64(hi - lo - 1usize)
        i = lo
        while i < hi {
            sum_hyp += items[i].hyp + items[i].main_ex + items[i].ms + items[i].me
            i += 1usize
        }
        let grow_mode = sum_hyp < avail
        i = lo
        while i < hi {
            items[i].frozen = false
            items[i].target = items[i].basis
            let factor = if_factor(grow_mode, items[i].grow, items[i].shrink)
            if factor == 0.0f64 || (grow_mode && items[i].basis > items[i].hyp) || (!grow_mode && items[i].basis < items[i].hyp) {
                items[i].frozen = true
                items[i].target = items[i].hyp
            }
            i += 1usize
        }
        var init_free = avail - gap_main * f64(hi - lo - 1usize)
        i = lo
        while i < hi {
            var seed = items[i].basis
            if items[i].frozen { seed = items[i].target }
            init_free -= seed + items[i].main_ex + items[i].ms + items[i].me
            i += 1usize
        }
        var round = 0usize
        while round < 32usize {
            var open_n = 0usize
            var free = avail - gap_main * f64(hi - lo - 1usize)
            var sum_factor = 0.0f64
            i = lo
            while i < hi {
                var seed2 = items[i].basis
                if items[i].frozen { seed2 = items[i].target } else {
                    open_n += 1usize
                    if grow_mode { sum_factor += items[i].grow } else { sum_factor += items[i].shrink * items[i].basis }
                }
                free -= seed2 + items[i].main_ex + items[i].ms + items[i].me
                i += 1usize
            }
            if open_n == 0usize { break }
            if grow_mode && sum_factor < 1.0f64 {
                let scaled = init_free * sum_factor
                if scaled < free { free = scaled }
            }
            i = lo
            while i < hi {
                if !items[i].frozen && sum_factor > 0.0f64 && free != 0.0f64 {
                    if grow_mode {
                        items[i].target = items[i].basis + free * items[i].grow / sum_factor
                    } else {
                        items[i].target = items[i].basis + free * items[i].shrink * items[i].basis / sum_factor
                    }
                }
                i += 1usize
            }
            // Clamp to min/max and freeze the violators.
            var total_violation = 0.0f64
            i = lo
            while i < hi {
                if !items[i].frozen {
                    let clamped = minf(maxf(items[i].target, items[i].min_main), items[i].max_main)
                    total_violation += clamped - items[i].target
                    items[i].target = clamped
                }
                i += 1usize
            }
            i = lo
            while i < hi {
                if !items[i].frozen {
                    let at_min = items[i].target <= items[i].min_main + 0.0001f64
                    let at_max = items[i].target >= items[i].max_main - 0.0001f64
                    if total_violation == 0.0f64 || (total_violation > 0.0f64 && at_min) || (total_violation < 0.0f64 && at_max) { items[i].frozen = true }
                }
                i += 1usize
            }
            if total_violation == 0.0f64 { break }
            round += 1usize
        }
        ln += 1usize
    }
    // Cross sizes: lay every item out at its main size and find the line cross sizes.
    ln = 0usize
    while ln < nlines {
        let from2 = line_start[ln]
        let to2 = line_start[ln + 1usize]
        var tallest = 0.0f64
        var above = 0.0f64
        var below = 0.0f64
        i = from2
        while i < to2 {
            let id = items[i].box
            let ks = bstyle(l, id)
            if row {
                var hspec = -1.0f64
                let (hv, has_h) = resolve_len(ks.height, cross_def)
                if ks.height.kind == .Px && has_h { hspec = to_content_h(l, id, hv) }
                l.orth_fb = items[i].target
                flex_place_item(l, id, items[i].target, hspec)
                items[i].cross = bx(l, id).h + items[i].cs + items[i].ce
            } else {
                let w = flex_cross_width(l, id, cw, items[i].align == .Stretch)
                if items[i].align == .Stretch { l.orth_fb = w }
                flex_place_item(l, id, w, items[i].target)
                items[i].cross = bx(l, id).w + items[i].cs + items[i].ce
            }
            if row && (items[i].align == .Baseline || items[i].align == .FirstBaseline || items[i].align == .LastBaseline) {
                let (found, by) = first_baseline(l, id)
                var up = 0.0f64
                if found { up = by }
                items[i].up = items[i].cs + up
                above = maxf(above, items[i].up)
                below = maxf(below, items[i].cross - items[i].up)
            } else {
                tallest = maxf(tallest, items[i].cross)
            }
            i += 1usize
        }
        line_cross[ln] = maxf(tallest, above + below)
        line_up[ln] = above
        ln += 1usize
    }
    if nlines == 1usize && cross_def >= 0.0f64 { line_cross[0usize] = cross_def }
    var cross_total = gap_cross * f64(nlines - 1usize)
    ln = 0usize
    while ln < nlines {
        cross_total += line_cross[ln]
        ln += 1usize
    }
    // align-content spreads the lines over a definite cross size.
    var lead = 0.0f64
    var between = 0.0f64
    if nlines > 1usize && cross_def > cross_total {
        let spare = cross_def - cross_total
        let ac = cs.align_content
        if ac == .Normal || ac == .Stretch {
            ln = 0usize
            while ln < nlines {
                line_cross[ln] += spare / f64(nlines)
                ln += 1usize
            }
        } else if ac == .FlexEnd || ac == .End {
            lead = spare
        } else if ac == .Center {
            lead = spare / 2.0f64
        } else if ac == .SpaceBetween {
            between = spare / f64(nlines - 1usize)
        } else if ac == .SpaceAround {
            between = spare / f64(nlines)
            lead = between / 2.0f64
        } else if ac == .SpaceEvenly {
            between = spare / f64(nlines + 1usize)
            lead = between
        }
        cross_total = cross_def
    }
    var cross_cursor = lead
    ln = 0usize
    while ln < nlines {
        line_pos[ln] = cross_cursor
        cross_cursor += line_cross[ln] + gap_cross + between
        ln += 1usize
    }
    if cross_def > cross_total { cross_total = cross_def }
    // Alignment inside each line, then the main-axis distribution.
    var main_end = 0.0f64
    ln = 0usize
    while ln < nlines {
        let from3 = line_start[ln]
        let to3 = line_start[ln + 1usize]
        i = from3
        while i < to3 {
            let id = items[i].box
            let ks = bstyle(l, id)
            let room = line_cross[ln] - items[i].cross
            let auto_cross = (row && ks.height.kind != .Px) || (!row && ks.width.kind != .Px)
            var off = 0.0f64
            if items[i].acs || items[i].ace {
                if room > 0.0f64 {
                    if items[i].acs && items[i].ace {
                        items[i].cs += room / 2.0f64
                        items[i].ce += room / 2.0f64
                    } else if items[i].acs { items[i].cs += room } else { items[i].ce += room }
                }
            } else if items[i].align == .Stretch && auto_cross && room > 0.0f64 {
                // Stretch the cross size to fill the line and lay the item out again.
                if row {
                    let ib = bx(l, id)
                    let hs = ib.h - vertical_extras(ib) + room
                    l.orth_fb = items[i].target
                    flex_place_item(l, id, items[i].target, hs)
                } else {
                    let ib2 = bx(l, id)
                    let ws = ib2.w - horizontal_extras(ib2) + room
                    l.orth_fb = ws
                    flex_place_item(l, id, ws, items[i].target)
                }
                items[i].cross += room
            } else if items[i].align == .FlexEnd || items[i].align == .End || items[i].align == .SelfEnd {
                off = room
            } else if items[i].align == .Center {
                off = room / 2.0f64
            } else if row && (items[i].align == .Baseline || items[i].align == .FirstBaseline || items[i].align == .LastBaseline) {
                off = line_up[ln] - items[i].up
            }
            items[i].pos_cross = line_pos[ln] + off
            i += 1usize
        }
        // Main axis: auto margins take the free space, else justify-content.
        var line_used = gap_main * f64(to3 - from3 - 1usize)
        var auto_count = 0usize
        i = from3
        while i < to3 {
            line_used += items[i].target + items[i].main_ex + items[i].ms + items[i].me
            if items[i].ams { auto_count += 1usize }
            if items[i].ame { auto_count += 1usize }
            i += 1usize
        }
        let free2 = avail - line_used
        var start_off = 0.0f64
        var spacing = 0.0f64
        if auto_count > 0usize && free2 > 0.0f64 {
            let share = free2 / f64(auto_count)
            i = from3
            while i < to3 {
                if items[i].ams { items[i].ms += share }
                if items[i].ame { items[i].me += share }
                i += 1usize
            }
        } else {
            let jc = cs.justify_content
            let cnt = to3 - from3
            if jc == .FlexEnd || jc == .End || (jc == .Right && row) {
                start_off = free2
            } else if jc == .Center {
                start_off = free2 / 2.0f64
            } else if free2 > 0.0f64 {
                if jc == .SpaceBetween && cnt > 1usize {
                    spacing = free2 / f64(cnt - 1usize)
                } else if jc == .SpaceAround {
                    spacing = free2 / f64(cnt)
                    start_off = spacing / 2.0f64
                } else if jc == .SpaceEvenly {
                    spacing = free2 / f64(cnt + 1usize)
                    start_off = spacing
                }
            }
        }
        var cursor = start_off
        i = from3
        while i < to3 {
            items[i].pos_main = cursor
            cursor += items[i].ms + items[i].target + items[i].main_ex + items[i].me + gap_main + spacing
            i += 1usize
        }
        main_end = maxf(main_end, cursor - gap_main - spacing)
        ln += 1usize
    }
    // Final positions, mirrored for reversed directions.
    i = 0usize
    while i < n {
        let id = items[i].box
        let ib = bx(l, id)
        let outer_main = items[i].ms + items[i].target + items[i].main_ex + items[i].me
        var pm = items[i].pos_main
        var pc = items[i].pos_cross
        if rev { pm = avail - pm - outer_main }
        if wrap_rev { pc = cross_total - pc - items[i].cross }
        if row {
            ib.x = ox0 + pm + items[i].ms
            ib.y = oy0 + pc + items[i].cs
        } else {
            ib.x = ox0 + pc + items[i].cs
            ib.y = oy0 + pm + items[i].ms
        }
        if row {
            ib.margin[0usize] = items[i].cs
            ib.margin[3usize] = items[i].ms
            ib.margin[1usize] = items[i].me
            ib.margin[2usize] = items[i].ce
        } else {
            ib.margin[2usize] = items[i].me
            ib.margin[1usize] = items[i].ce
            ib.margin[0usize] = items[i].ms
            ib.margin[3usize] = items[i].cs
        }
        i += 1usize
    }
    if row { ret cross_total }
    if main_def >= 0.0f64 { ret main_def }
    ret main_end
}

fn if_factor(grow_mode: bool, grow: f64, shrink: f64) -> f64 {
    if grow_mode { ret grow }
    ret shrink
}

// --- Grid layout (CSS Grid 6 to 12): templates, named lines and areas, auto placement, track sizing, alignment.
// Templates and placements come from the declared text in `extras` (the style module keeps them as text). Not done:
// subgrid, masonry, dense packing of explicit-row items beyond the sparse rule, baseline-aligned items.

fn inf() -> f64 { ret 1000000000.0f64 }

// A track sizing function: kind 0 length, 1 percentage (0..1), 2 flexible (fr), 3 auto, 4 min-content, 5 max-content,
// 6 fit-content(limit).
type SizeFn = struct { kind: u8, v: f64 }

type GTrack = struct { min: SizeFn, max: SizeFn, base: f64, limit: f64, pos: f64, collapsed: bool, fit: bool }

type GName = struct { name: str, line: i32 }

type GArea = struct { name: str, r0: i32, r1: i32, c0: i32, c1: i32 }

// A line reference: kind 0 auto, 1 line number, 2 span, 3 named line (`n` is the occurrence or span count).
type LineSpec = struct { kind: u8, n: i32, name: str, span_name: bool }

type GItem = struct {
    box: u32, order: i64,
    rs: i32, rn: i32, cs: i32, cn: i32,
    cmin: f64, cmax: f64, rmin: f64, rmax: f64
}

type GridParse = struct { c: style.Context, em: f64, avail: f64, gap: f64, item_min: f64 }

fn extra_text(s: *const style.Style, name: str) -> (str, bool) {
    var i = 0usize
    while i < s.extras.len {
        if str.eq(s.extras[i].name, name) { ret (s.extras[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn push_name(names: *list.List[GName], name: str, line: i32) {
    let pushed = list.push[GName](names, GName { name: name, line: line })
}

// Splits on spaces outside parentheses, keeping a [bracketed group] as one token.
fn grid_split(a: *mem.Arena, s: str) -> []const str {
    var out = cv.strings_list(a)
    var depth = 0i64
    var start = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 40u8 || c == 91u8 {
            depth += 1i64
        } else if c == 41u8 || c == 93u8 {
            if depth > 0i64 { depth -= 1i64 }
        } else if depth == 0i64 && (c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8) {
            if i > start { cv.push_str(&out, s[start..i]) }
            start = i + 1usize
        }
        i += 1usize
    }
    if start < s.len { cv.push_str(&out, s[start..]) }
    ret list.slice_const[str](&out)
}

fn gp_size(gp: *GridParse, tok: str) -> (SizeFn, bool) {
    let t = cv.lower(gp.c.a, cv.trim_ws(tok))
    if str.eq(t, "auto") { ret (SizeFn { kind: 3u8, v: 0.0f64 }, true) }
    if str.eq(t, "min-content") { ret (SizeFn { kind: 4u8, v: 0.0f64 }, true) }
    if str.eq(t, "max-content") { ret (SizeFn { kind: 5u8, v: 0.0f64 }, true) }
    if str.ends_with(t, "fr") {
        let (n, good) = cv.try_parse(gp.c.a, t[..t.len - 2usize])
        if good && n >= 0.0f64 { ret (SizeFn { kind: 2u8, v: n }, true) }
        ret (SizeFn { kind: 3u8, v: 0.0f64 }, false)
    }
    let (len, parsed) = style.parse_len(&gp.c, t, gp.em, style.A_PERCENT)
    if !parsed { ret (SizeFn { kind: 3u8, v: 0.0f64 }, false) }
    if len.pct != 0.0f64 && len.px == 0.0f64 { ret (SizeFn { kind: 1u8, v: len.pct }, true) }
    ret (SizeFn { kind: 0u8, v: len.px }, true)
}

fn gp_track(gp: *GridParse, tok: str, out: *list.List[GTrack]) -> bool {
    let t = cv.lower(gp.c.a, cv.trim_ws(tok))
    var tr = GTrack { min: SizeFn { kind: 3u8, v: 0.0f64 }, max: SizeFn { kind: 3u8, v: 0.0f64 }, base: 0.0f64, limit: inf(), pos: 0.0f64, collapsed: false, fit: false }
    if str.starts_with(t, "minmax(") && str.ends_with(t, ")") {
        let parts = cv.split_top_level_commas(gp.c.a, t[7usize..t.len - 1usize])
        if parts.len != 2usize { ret false }
        let (lo, ok_lo) = gp_size(gp, parts[0usize])
        let (hi, ok_hi) = gp_size(gp, parts[1usize])
        if !ok_lo || !ok_hi { ret false }
        tr.min = lo
        tr.max = hi
        if lo.kind == 2u8 { tr.min = SizeFn { kind: 3u8, v: 0.0f64 } }
    } else if str.starts_with(t, "fit-content(") && str.ends_with(t, ")") {
        let (lim, ok_lim) = gp_size(gp, t[12usize..t.len - 1usize])
        if !ok_lim { ret false }
        tr.max = SizeFn { kind: 6u8, v: lim.v }
        if lim.kind == 1u8 && gp.avail >= 0.0f64 { tr.max.v = lim.v * gp.avail }
    } else {
        let (sz, ok_sz) = gp_size(gp, t)
        if !ok_sz { ret false }
        tr.max = sz
        if sz.kind == 2u8 {
            tr.min = SizeFn { kind: 3u8, v: 0.0f64 }
        } else {
            tr.min = sz
        }
    }
    let pushed = list.push[GTrack](out, tr)
    ret true
}

// The tokens of a track list; `[name]` groups and `repeat()` are expanded.
fn gp_list(gp: *GridParse, text: str, out: *list.List[GTrack], names: *list.List[GName]) {
    let toks = grid_split(gp.c.a, text)
    var i = 0usize
    while i < toks.len {
        let tok = toks[i]
        i += 1usize
        if out.len >= 1000usize { break }
        if tok.len >= 2usize && tok[0usize] == 91u8 {
            let inner = tok[1usize..tok.len - 1usize]
            let words = cv.split_top_level_spaces(gp.c.a, inner)
            var w = 0usize
            while w < words.len {
                push_name(names, words[w], i32(out.len) + 1i32)
                w += 1usize
            }
        } else if str.starts_with(cv.lower(gp.c.a, tok), "repeat(") && str.ends_with(tok, ")") {
            let parts = cv.split_top_level_commas(gp.c.a, tok[7usize..tok.len - 1usize])
            if parts.len < 2usize { continue }
            let count_text = cv.lower(gp.c.a, cv.trim_ws(parts[0usize]))
            var body = parts[1usize]
            var pj = 2usize
            while pj < parts.len {
                body = cv.cat(gp.c.a, cv.cat(gp.c.a, body, ","), parts[pj])
                pj += 1usize
            }
            var n = 1i64
            if str.eq(count_text, "auto-fill") || str.eq(count_text, "auto-fit") {
                // As many repetitions as fit the available size.
                let (tmp, te) = list.init[GTrack](gp.c.a, 8usize)
                let (nm2, ne2) = list.init[GName](gp.c.a, 4usize)
                if te != ok || ne2 != ok { continue }
                var tl = tmp
                var tmp_names = nm2
                gp_list(gp, body, &tl, &tmp_names)
                var per = 0.0f64
                var tk = 0usize
                while tk < tl.len {
                    var sz = tl.items[tk].min
                    if sz.kind == 3u8 || sz.kind == 4u8 || sz.kind == 5u8 { sz = tl.items[tk].max }
                    if sz.kind == 0u8 { per += sz.v } else if sz.kind == 1u8 && gp.avail >= 0.0f64 { per += sz.v * gp.avail }
                    tk += 1usize
                }
                if per == 0.0f64 && gp.item_min > 0.0f64 { per = gp.item_min }
                n = 1i64
                if gp.avail >= 0.0f64 && tl.len > 0usize && per > 0.0f64 {
                    let each = per + gp.gap * f64(tl.len)
                    let fit = (gp.avail + gp.gap) / each
                    n = i64(fit)
                    if n < 1i64 { n = 1i64 }
                }
            } else {
                let (cnt, good) = str.parse_i64(count_text)
                if good == ok && cnt >= 1i64 { n = cnt }
            }
            var rep = 0i64
            let first_rep = out.len
            while rep < n && out.len < 1000usize {
                gp_list(gp, body, out, names)
                rep += 1i64
            }
            if str.eq(count_text, "auto-fit") {
                var fk = first_rep
                while fk < out.len {
                    out.items[fk].fit = true
                    fk += 1usize
                }
            }
        } else {
            let added = gp_track(gp, tok, out)
        }
    }
}

// grid-template-areas: the quoted rows; "." is an empty cell.
type Dims = struct { rows: i32, cols: i32 }

fn parse_areas(a: *mem.Arena, text: str, areas: *list.List[GArea], dims: *Dims) {
    var row = 0i32
    var i = 0usize
    while i < text.len {
        if text[i] != 34u8 && text[i] != 39u8 {
            i += 1usize
            continue
        }
        let quote = text[i]
        var j = i + 1usize
        while j < text.len && text[j] != quote { j += 1usize }
        let words = cv.split_top_level_spaces(a, text[i + 1usize..j])
        var col = 0usize
        while col < words.len {
            let name = words[col]
            if !str.eq(name, ".") {
                var found = false
                var k = 0usize
                while k < areas.len {
                    if str.eq(areas.items[k].name, name) {
                        found = true
                        areas.items[k].r1 = row + 2i32
                        if i32(col) + 2i32 > areas.items[k].c1 { areas.items[k].c1 = i32(col) + 2i32 }
                    }
                    k += 1usize
                }
                if !found {
                    let pushed = list.push[GArea](areas, GArea { name: name, r0: row + 1i32, r1: row + 2i32, c0: i32(col) + 1i32, c1: i32(col) + 2i32 })
                }
            }
            col += 1usize
        }
        if i32(words.len) > dims.cols { dims.cols = i32(words.len) }
        row += 1i32
        dims.rows = row
        i = j + 1usize
    }
}

fn parse_line_spec(a: *mem.Arena, text: str) -> LineSpec {
    var out = LineSpec { kind: 0u8, n: 0i32, name: "", span_name: false }
    let t = cv.trim_ws(text)
    if t.len == 0usize || str.eq(cv.lower(a, t), "auto") { ret out }
    // Keywords are case-insensitive; line and area names are not.
    let toks = cv.split_top_level_spaces(a, t)
    var span = false
    var n = 0i32
    var has_n = false
    var name = ""
    var i = 0usize
    while i < toks.len {
        let tk = toks[i]
        i += 1usize
        if str.eq(cv.lower(a, tk), "span") {
            span = true
            continue
        }
        let (v, good) = str.parse_i64(tk)
        if good == ok {
            n = i32(v)
            has_n = true
        } else {
            name = tk
        }
    }
    if span {
        out.kind = 2u8
        out.n = 1i32
        if has_n && n > 0i32 { out.n = n }
        out.name = name
        ret out
    }
    if name.len > 0usize {
        out.kind = 3u8
        out.name = name
        out.n = 1i32
        if has_n && n != 0i32 { out.n = n }
        ret out
    }
    if has_n && n != 0i32 {
        out.kind = 1u8
        out.n = n
    }
    ret out
}

// The line number a line reference stands for on this axis (0: none found). `end` selects the implicit `-end` name.
fn resolve_line(names: *const list.List[GName], explicit: i32, spec: LineSpec, end: bool, a: *mem.Arena) -> i32 {
    if spec.kind == 1u8 {
        if spec.n > 0i32 { ret spec.n }
        ret explicit + 2i32 + spec.n
    }
    if spec.kind != 3u8 { ret 0i32 }
    var pass = 0usize
    while pass < 2usize {
        var want = spec.name
        if pass == 1usize {
            if end { want = cv.cat(a, spec.name, "-end") } else { want = cv.cat(a, spec.name, "-start") }
        }
        var count = 0i32
        var found = 0i32
        var k = 0usize
        if spec.n > 0i32 {
            while k < names.len {
                if str.eq(names.items[k].name, want) {
                    count += 1i32
                    if count == spec.n { found = names.items[k].line }
                }
                k += 1usize
            }
        } else {
            k = names.len
            while k > 0usize {
                k -= 1usize
                if str.eq(names.items[k].name, want) {
                    count += 1i32
                    if count == -spec.n { found = names.items[k].line }
                }
            }
        }
        if found > 0i32 { ret found }
        pass += 1usize
    }
    ret 0i32
}

// Start track (0-based, -1: auto) and span from a start and an end reference.
fn resolve_axis(names: *const list.List[GName], explicit: i32, s: LineSpec, e: LineSpec, a: *mem.Arena) -> (i32, i32) {
    let sl = resolve_line(names, explicit, s, false, a)
    let el = resolve_line(names, explicit, e, true, a)
    var s_line = s.kind == 1u8 || s.kind == 3u8
    var e_line = e.kind == 1u8 || e.kind == 3u8
    if s_line && sl <= 0i32 { s_line = false }
    if e_line && el <= 0i32 { e_line = false }
    if s_line && e_line {
        var lo = sl
        var hi = el
        if hi < lo {
            lo = el
            hi = sl
        }
        if hi == lo { hi = lo + 1i32 }
        ret (lo - 1i32, hi - lo)
    }
    if s_line {
        if e.kind == 2u8 { ret (sl - 1i32, e.n) }
        ret (sl - 1i32, 1i32)
    }
    if e_line {
        if s.kind == 2u8 {
            var st0 = el - s.n
            if st0 < 1i32 { st0 = 1i32 }
            ret (st0 - 1i32, s.n)
        }
        if el - 2i32 < 0i32 { ret (0i32, 1i32) }
        ret (el - 2i32, 1i32)
    }
    if s.kind == 2u8 { ret (-1i32, s.n) }
    if e.kind == 2u8 { ret (-1i32, e.n) }
    ret (-1i32, 1i32)
}

// The two halves of "a / b" (the second empty when there is no slash).
fn split_slash(text: str) -> (str, str, bool) {
    var i = 0usize
    while i < text.len {
        if text[i] == 47u8 { ret (str.trim(text[..i]), str.trim(text[i + 1usize..]), true) }
        i += 1usize
    }
    ret (str.trim(text), "", false)
}

// grid-row-start/-end (or grid-column-*) of an item, from the longhands, else the shorthand, else grid-area.
fn item_axis_specs(a: *mem.Arena, s: *const style.Style, col: bool) -> (LineSpec, LineSpec) {
    var start_name = "grid-row-start"
    var end_name = "grid-row-end"
    var short_name = "grid-row"
    if col {
        start_name = "grid-column-start"
        end_name = "grid-column-end"
        short_name = "grid-column"
    }
    var sp = parse_line_spec(a, "")
    var ep = parse_line_spec(a, "")
    let (area, has_area) = extra_text(s, "grid-area")
    if has_area {
        // row-start / column-start / row-end / column-end
        let (p1, rest1, sl1) = split_slash(area)
        let (p2, rest2, sl2) = split_slash(rest1)
        let (p3, p4, sl3) = split_slash(rest2)
        if !sl1 {
            // One name: it stands for all four edges.
            let one = parse_line_spec(a, p1)
            sp = one
            ep = one
        } else {
            var rs = parse_line_spec(a, p1)
            var cs = parse_line_spec(a, p2)
            var re = parse_line_spec(a, p3)
            var ce = parse_line_spec(a, p4)
            if !sl2 {
                cs = rs
                re = rs
                ce = cs
            } else if !sl3 {
                re = rs
                ce = cs
            }
            if col {
                sp = cs
                ep = ce
            } else {
                sp = rs
                ep = re
            }
        }
    }
    let (short, has_short) = extra_text(s, short_name)
    if has_short {
        let (h1, h2, hs) = split_slash(short)
        sp = parse_line_spec(a, h1)
        if hs { ep = parse_line_spec(a, h2) } else {
            ep = parse_line_spec(a, "")
            if sp.kind == 3u8 { ep = sp }
        }
    }
    let (st_text, has_st) = extra_text(s, start_name)
    if has_st { sp = parse_line_spec(a, st_text) }
    let (en_text, has_en) = extra_text(s, end_name)
    if has_en { ep = parse_line_spec(a, en_text) }
    ret (sp, ep)
}

// --- The grid: explicit and implicit tracks, item placement.

type Grid = struct {
    cols: []GTrack, rows: []GTrack, nc: usize, nr: usize,
    items: []GItem, n: usize, gap_c: f64, gap_r: f64,
    cnames: list.List[GName], rnames: list.List[GName], ec: i32, er: i32, c_dummy: bool, r_dummy: bool
}

// A laid-out grid's track geometry, kept so absolutely positioned children can use their grid area as containing block.
type GridGeom = struct {
    box: u32, nc: usize, nr: usize, cpos: []f64, csz: []f64, rpos: []f64, rsz: []f64,
    cnames: list.List[GName], rnames: list.List[GName], ec: i32, er: i32, w: f64, rtl: bool
}

fn occ_free(occ: []bool, ncols: usize, rows_cap: usize, r: usize, c: usize, rn: usize, cn: usize) -> bool {
    if r + rn > rows_cap || c + cn > ncols { ret false }
    var rr = 0usize
    while rr < rn {
        var cc = 0usize
        while cc < cn {
            if occ[(r + rr) * ncols + c + cc] { ret false }
            cc += 1usize
        }
        rr += 1usize
    }
    ret true
}

fn occ_mark(occ: []bool, ncols: usize, rows_cap: usize, r: usize, c: usize, rn: usize, cn: usize) {
    var rr = 0usize
    while rr < rn {
        var cc = 0usize
        while cc < cn {
            if r + rr < rows_cap && c + cc < ncols { occ[(r + rr) * ncols + c + cc] = true }
            cc += 1usize
        }
        rr += 1usize
    }
}

// Auto placement in row flow (CSS Grid 8.5); column flow runs on transposed items. Fills every item's rs/cs.
fn grid_autoplace(a: *mem.Arena, items: []GItem, n: usize, ec: i32, er: i32, dense: bool) -> bool {
    var ncols = ec
    if ncols < 1i32 { ncols = 1i32 }
    var rows_sum = er + i32(n) + 8i32
    var i = 0usize
    while i < n {
        if items[i].cn > ncols { ncols = items[i].cn }
        if items[i].cs >= 0i32 && items[i].cs + items[i].cn > ncols { ncols = items[i].cs + items[i].cn }
        rows_sum += items[i].rn
        if items[i].rs >= 0i32 && items[i].rs + items[i].rn > rows_sum { rows_sum = items[i].rs + items[i].rn + 8i32 }
        i += 1usize
    }
    if ncols > 1000i32 { ncols = 1000i32 }
    if rows_sum > 5000i32 { rows_sum = 5000i32 }
    let rows_cap = usize(rows_sum)
    let nc = usize(ncols)
    let (occ, oe) = mem.alloc[bool](a, rows_cap * nc + 1usize)
    let (rowcur, re) = mem.alloc[usize](a, rows_cap + 1usize)
    if oe != ok || re != ok { ret false }
    var z = 0usize
    while z < rows_cap * nc + 1usize {
        occ[z] = false
        z += 1usize
    }
    z = 0usize
    while z < rows_cap + 1usize {
        rowcur[z] = 0usize
        z += 1usize
    }
    // 1. Definite in both axes.
    i = 0usize
    while i < n {
        if items[i].rs >= 0i32 && items[i].cs >= 0i32 {
            occ_mark(occ, nc, rows_cap, usize(items[i].rs), usize(items[i].cs), usize(items[i].rn), usize(items[i].cn))
        }
        i += 1usize
    }
    // 2. A definite row, an automatic column.
    i = 0usize
    while i < n {
        if items[i].rs >= 0i32 && items[i].cs < 0i32 {
            let r = usize(items[i].rs)
            var c = 0usize
            if !dense && r < rows_cap { c = rowcur[r] }
            var placed = false
            while c + usize(items[i].cn) <= nc {
                if occ_free(occ, nc, rows_cap, r, c, usize(items[i].rn), usize(items[i].cn)) {
                    placed = true
                    break
                }
                c += 1usize
            }
            if !placed { c = 0usize }
            items[i].cs = i32(c)
            occ_mark(occ, nc, rows_cap, r, c, usize(items[i].rn), usize(items[i].cn))
            if r < rows_cap { rowcur[r] = c + usize(items[i].cn) }
        }
        i += 1usize
    }
    // 3. The rest, by the auto-placement cursor.
    var cr = 0usize
    var cc2 = 0usize
    i = 0usize
    while i < n {
        if items[i].rs < 0i32 {
            if dense {
                cr = 0usize
                cc2 = 0usize
            }
            let rn = usize(items[i].rn)
            let cn = usize(items[i].cn)
            if items[i].cs >= 0i32 {
                if usize(items[i].cs) < cc2 { cr += 1usize }
                cc2 = usize(items[i].cs)
                while cr < rows_cap && !occ_free(occ, nc, rows_cap, cr, cc2, rn, cn) { cr += 1usize }
            } else {
                var found = false
                while !found && cr < rows_cap {
                    while cc2 + cn <= nc {
                        if occ_free(occ, nc, rows_cap, cr, cc2, rn, cn) {
                            found = true
                            break
                        }
                        cc2 += 1usize
                    }
                    if !found {
                        cr += 1usize
                        cc2 = 0usize
                    }
                }
            }
            if cr >= rows_cap { cr = rows_cap - 1usize }
            items[i].rs = i32(cr)
            items[i].cs = i32(cc2)
            occ_mark(occ, nc, rows_cap, cr, cc2, rn, cn)
        }
        i += 1usize
    }
    ret true
}

fn swap_axes(items: []GItem, n: usize) {
    var i = 0usize
    while i < n {
        let r0 = items[i].rs
        let rn = items[i].rn
        items[i].rs = items[i].cs
        items[i].rn = items[i].cn
        items[i].cs = r0
        items[i].cn = rn
        i += 1usize
    }
}

fn auto_track_list(gp: *GridParse, s: *const style.Style, prop: str) -> list.List[GTrack] {
    let (tl, te) = list.init[GTrack](gp.c.a, 4usize)
    let (nl, ne) = list.init[GName](gp.c.a, 1usize)
    var out = tl
    var scratch = nl
    let (txt, has) = extra_text(s, prop)
    if te == ok && ne == ok && has { gp_list(gp, txt, &out, &scratch) }
    if out.len == 0usize {
        let added = gp_track(gp, "auto", &out)
    }
    ret out
}

fn grid_make_track(auto_list: *const list.List[GTrack], index: usize) -> GTrack {
    var t = auto_list.items[index % auto_list.len]
    t.base = 0.0f64
    t.pos = 0.0f64
    ret t
}

// Builds the grid of container `b`: tracks, items (margins resolved, contributions measured) and their placement.
// `subgrid` as a track list (optionally followed by line names).
fn subgrid_axis(text: str) -> bool {
    let t = str.trim(text)
    ret str.starts_with(t, "subgrid") && (t.len == 7usize || t[7usize] == 32u8)
}

// A subgrid in an orthogonal writing mode does not share the parent's axes: it is an independent grid.
fn subgrid_axes_match(l: *Layout, id: u32) -> bool {
    let p = l.boxes.items[usize(id)].parent
    if p == NONE { ret false }
    ret bstyle(l, id).writing_mode == bstyle(l, p).writing_mode && !bstyle(l, id).lanes && !bstyle(l, p).lanes
}

// A grid item that is itself a grid with `subgrid` in an axis takes its tracks from the lines it spans: the parent leaves their
// sizes (and its gap) for `grid_build` to pick up when the item is laid out.
fn subgrid_prepare(l: *Layout, g: *Grid, i: usize, cols: bool, rows: bool) {
    l.sub_has_c = false
    l.sub_has_r = false
    let id = g.items[i].box
    if bx(l, id).inner != .Grid || !subgrid_axes_match(l, id) || bstyle(l, id).lanes { ret }
    let ks = bstyle(l, id)
    if cols && !g.c_dummy {
        let (ct, hct) = extra_text(ks, "grid-template-columns")
        if hct && subgrid_axis(ct) && g.items[i].cn > 0i32 {
            let (sz, e) = mem.alloc[f64](l.a, usize(g.items[i].cn))
            if e == ok {
                var k = 0usize
                while k < usize(g.items[i].cn) {
                    sz[k] = g.cols[usize(g.items[i].cs) + k].base
                    k += 1usize
                }
                l.sub_c = sz
                l.sub_gc = g.gap_c
                l.sub_has_c = true
            }
        }
    }
    if rows && !g.r_dummy {
        let (rt, hrt) = extra_text(ks, "grid-template-rows")
        if hrt && subgrid_axis(rt) && g.items[i].rn > 0i32 {
            let (sz, e) = mem.alloc[f64](l.a, usize(g.items[i].rn))
            if e == ok {
                var k = 0usize
                while k < usize(g.items[i].rn) {
                    sz[k] = g.rows[usize(g.items[i].rs) + k].base
                    k += 1usize
                }
                l.sub_r = sz
                l.sub_gr = g.gap_r
                l.sub_has_r = true
            }
        }
    }
}

// The tracks of a subgrid: the parent's tracks it spans, moved by the difference of the two gaps and by its own edges.
fn subgrid_tracks(a: *mem.Arena, sizes: []const f64, parent_gap: f64, own_gap: f64, edge_start: f64, edge_end: f64, out: *list.List[GTrack]) {
    var k = 0usize
    while k < sizes.len {
        var sz = sizes[k]
        if k > 0usize { sz += (parent_gap - own_gap) / 2.0f64 }
        if k + 1usize < sizes.len { sz += (parent_gap - own_gap) / 2.0f64 }
        if k == 0usize { sz -= edge_start }
        if k + 1usize == sizes.len { sz -= edge_end }
        let t = GTrack { min: SizeFn { kind: 0u8, v: maxf(0.0f64, sz) }, max: SizeFn { kind: 0u8, v: maxf(0.0f64, sz) }, base: 0.0f64, limit: 0.0f64, pos: 0.0f64, collapsed: false, fit: false }
        let pushed = list.push[GTrack](out, t)
        k += 1usize
    }
}

// The items of the grid's subgrids (in the column axis) count towards the tracks they span, as if they were its own items:
// answers the grid's items followed by those, and the count.
fn subgrid_contributions(l: *Layout, g: *Grid) -> ([]GItem, usize) {
    if g.c_dummy { ret (g.items, g.n) }
    var extra = 0usize
    var i = 0usize
    while i < g.n {
        let id = g.items[i].box
        if bx(l, id).inner == .Grid && subgrid_axes_match(l, id) {
            let (ct, hct) = extra_text(bstyle(l, id), "grid-template-columns")
            if hct && subgrid_axis(ct) { extra += 64usize }
        }
        i += 1usize
    }
    let (out, e) = mem.alloc[GItem](l.a, g.n + extra + 1usize)
    if e != ok { ret (g.items, g.n) }
    var n = 0usize
    i = 0usize
    while i < g.n {
        out[n] = g.items[i]
        n += 1usize
        i += 1usize
    }
    // A subgrid has no width of its own to give its tracks: its items stand in for it.
    i = 0usize
    while i < g.n {
        let id = g.items[i].box
        if bx(l, id).inner == .Grid && subgrid_axes_match(l, id) {
            let (ct, hct) = extra_text(bstyle(l, id), "grid-template-columns")
            if hct && subgrid_axis(ct) {
                out[i].cmin = 0.0f64
                out[i].cmax = 0.0f64
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let ks = bstyle(l, id)
        if bx(l, id).inner == .Grid && g.items[i].cn > 0i32 && subgrid_axes_match(l, id) {
            let (ct, hct) = extra_text(ks, "grid-template-columns")
            if hct && subgrid_axis(ct) {
                let span = usize(g.items[i].cn)
                let (zero_sizes, ze) = mem.alloc[f64](l.a, span)
                if ze == ok {
                    var z = 0usize
                    while z < span {
                        zero_sizes[z] = 0.0f64
                        z += 1usize
                    }
                    l.sub_c = zero_sizes
                    l.sub_gc = g.gap_c
                    l.sub_has_c = true
                    let (cg, built) = grid_build(l, id, -1.0f64, -1.0f64)
                    l.sub_has_c = false
                    if built {
                        let sbb = bx(l, id)
                        let edge_s = sbb.margin[3usize] + sbb.border[3usize] + sbb.padding[3usize]
                        let edge_e = sbb.margin[1usize] + sbb.border[1usize] + sbb.padding[1usize]
                        var j = 0usize
                        while j < cg.n && n < g.n + extra {
                            var it: GItem = zero
                            it.box = cg.items[j].box
                            it.cs = g.items[i].cs + cg.items[j].cs
                            it.cn = cg.items[j].cn
                            it.rs = 0i32
                            it.rn = 1i32
                            it.cmin = cg.items[j].cmin
                            it.cmax = cg.items[j].cmax
                            if cg.items[j].cs == 0i32 {
                                it.cmin += edge_s
                                it.cmax += edge_s
                            }
                            if usize(cg.items[j].cs + cg.items[j].cn) >= span {
                                it.cmin += edge_e
                                it.cmax += edge_e
                            }
                            // The subgrid's own gap against the parent's: half the difference sits on each side that faces a gap.
                            let half_gap = (cg.gap_c - g.gap_c) / 2.0f64
                            if cg.items[j].cs > 0i32 {
                                it.cmin += half_gap
                                it.cmax += half_gap
                            }
                            if usize(cg.items[j].cs + cg.items[j].cn) < span {
                                it.cmin += half_gap
                                it.cmax += half_gap
                            }
                            out[n] = it
                            n += 1usize
                            j += 1usize
                        }
                    }
                }
            }
        }
        i += 1usize
    }
    ret (out, n)
}

fn grid_build(l: *Layout, b: u32, avail_w: f64, avail_h: f64) -> (*Grid, bool) {
    let cs = bstyle(l, b)
    let (gcell, ge) = mem.alloc[Grid](l.a, 1usize)
    if ge != ok { ret (zero, false) }
    let g = &gcell[0usize]
    g.c_dummy = false
    g.r_dummy = false
    let ctx = style.new_context(l.a, l.viewport_width, l.viewport_height)
    var gp = GridParse { c: ctx, em: cs.font_size, avail: avail_w, gap: 0.0f64, item_min: 0.0f64 }
    g.gap_c = flex_gap(cs.column_gap, maxf(avail_w, 0.0f64))
    g.gap_r = flex_gap(cs.row_gap, maxf(avail_h, 0.0f64))
    // Explicit tracks and line names.
    let (cl, e1) = list.init[GTrack](l.a, 8usize)
    let (rl, e2) = list.init[GTrack](l.a, 8usize)
    let (cnl, e3) = list.init[GName](l.a, 8usize)
    let (rnl, e4) = list.init[GName](l.a, 8usize)
    let (al, e5) = list.init[GArea](l.a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (g, false) }
    var ctr = cl
    var rtr = rl
    var cnames = cnl
    var rnames = rnl
    var areas = al
    gp.gap = g.gap_c
    gp.avail = avail_w
    // Masonry: an `auto-fill` of intrinsic tracks is as many as the widest minimum item allows.
    if cs.lanes {
        var ik = l.boxes.items[usize(b)].first
        while ik != NONE {
            let (isc, iec) = item_axis_specs(l.a, bstyle(l, ik), true)
            if flex_in(l, ik) && isc.kind == 0u8 && iec.kind == 0u8 {
                let iks = bstyle(l, ik)
                resolve_edges(l, ik, maxf(avail_w, 0.0f64))
                resolve_margins_fixed(l, ik, maxf(avail_w, 0.0f64))
                let (imn, imx) = content_widths(l, ik)
                var iw = imn
                let (iwv, ihas) = resolve_len(iks.width, avail_w)
                if iks.width.kind == .Px && ihas { iw = to_content_w(l, ik, iwv) }
                let ibx = bx(l, ik)
                iw = iw + horizontal_extras(ibx) + ibx.margin[3usize] + ibx.margin[1usize]
                if iw > gp.item_min { gp.item_min = iw }
            }
            ik = l.boxes.items[usize(ik)].next
        }
    }
    let (ctext, has_ct) = extra_text(cs, "grid-template-columns")
    let sbb = bx(l, b)
    if has_ct && subgrid_axis(ctext) && l.sub_has_c {
        // A subgrid's tracks are the ones of the parent grid it spans.
        if l.sub_has_c {
            if cs.column_gap.kind == .Normal { g.gap_c = l.sub_gc }
            gp.gap = g.gap_c
            subgrid_tracks(l.a, l.sub_c, l.sub_gc, g.gap_c, sbb.margin[3usize] + sbb.border[3usize] + sbb.padding[3usize], sbb.margin[1usize] + sbb.border[1usize] + sbb.padding[1usize], &ctr)
        }
        l.sub_has_c = false
    } else if has_ct {
        // `subgrid` with no parent tracks to take is left to the auto tracks, and so are the grids nested in it.
        if subgrid_axis(ctext) { g.c_dummy = true }
        gp_list(&gp, ctext, &ctr, &cnames)
    }
    gp.item_min = 0.0f64
    gp.gap = g.gap_r
    gp.avail = avail_h
    let (rtext, has_rt) = extra_text(cs, "grid-template-rows")
    if has_rt && subgrid_axis(rtext) && l.sub_has_r {
        if l.sub_has_r {
            if cs.row_gap.kind == .Normal { g.gap_r = l.sub_gr }
            gp.gap = g.gap_r
            subgrid_tracks(l.a, l.sub_r, l.sub_gr, g.gap_r, sbb.margin[0usize] + sbb.border[0usize] + sbb.padding[0usize], sbb.margin[2usize] + sbb.border[2usize] + sbb.padding[2usize], &rtr)
        }
        l.sub_has_r = false
    } else if has_rt {
        if subgrid_axis(rtext) { g.r_dummy = true }
        gp_list(&gp, rtext, &rtr, &rnames)
    }
    var dims = Dims { rows: 0i32, cols: 0i32 }
    let (atext, has_at) = extra_text(cs, "grid-template-areas")
    if has_at { parse_areas(l.a, atext, &areas, &dims) }
    var k = 0usize
    while k < areas.len {
        push_name(&rnames, cv.cat(l.a, areas.items[k].name, "-start"), areas.items[k].r0)
        push_name(&rnames, cv.cat(l.a, areas.items[k].name, "-end"), areas.items[k].r1)
        push_name(&cnames, cv.cat(l.a, areas.items[k].name, "-start"), areas.items[k].c0)
        push_name(&cnames, cv.cat(l.a, areas.items[k].name, "-end"), areas.items[k].c1)
        k += 1usize
    }
    var ec = i32(ctr.len)
    var er = i32(rtr.len)
    if dims.cols > ec { ec = dims.cols }
    if dims.rows > er { er = dims.rows }
    gp.avail = avail_w
    gp.gap = g.gap_c
    var auto_cols = auto_track_list(&gp, cs, "grid-auto-columns")
    gp.avail = avail_h
    gp.gap = g.gap_r
    var auto_rows = auto_track_list(&gp, cs, "grid-auto-rows")
    // Items.
    var n = 0usize
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        if flex_in(l, kid) { n += 1usize }
        kid = l.boxes.items[usize(kid)].next
    }
    g.n = n
    if n == 0usize {
        g.nc = usize(ec)
        g.nr = usize(er)
    }
    let (items, ie) = mem.alloc[GItem](l.a, n + 1usize)
    if ie != ok { ret (g, false) }
    g.items = items
    var count = 0usize
    kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        if flex_in(l, kid) {
            let ks = bstyle(l, kid)
            resolve_edges(l, kid, maxf(avail_w, 0.0f64))
            resolve_margins_fixed(l, kid, maxf(avail_w, 0.0f64))
            let (sc, ecs) = item_axis_specs(l.a, ks, true)
            let (sr, ers) = item_axis_specs(l.a, ks, false)
            let (c0, cn) = resolve_axis(&cnames, ec, sc, ecs, l.a)
            let (r0, rn) = resolve_axis(&rnames, er, sr, ers, l.a)
            var it: GItem = zero
            it.box = kid
            it.order = ks.order
            it.cs = c0
            it.cn = cn
            it.rs = r0
            it.rn = rn
            let (mn, mx) = outer_content_widths(l, kid)
            it.cmin = mn
            it.cmax = mx
            var at = count
            while at > 0usize && items[at - 1usize].order > it.order {
                items[at] = items[at - 1usize]
                at -= 1usize
            }
            items[at] = it
            count += 1usize
        }
        kid = l.boxes.items[usize(kid)].next
    }
    // Placement: column flow runs the row-flow algorithm on transposed items.
    let (flow_raw, has_flow) = extra_text(cs, "grid-auto-flow")
    var flow_col = false
    var dense = false
    if has_flow {
        let ft = cv.lower(l.a, flow_raw)
        flow_col = str.contains(ft, "column")
        dense = str.contains(ft, "dense")
    }
    var placed_ok = true
    if flow_col {
        swap_axes(items, n)
        placed_ok = grid_autoplace(l.a, items, n, er, ec, dense)
        swap_axes(items, n)
    } else {
        placed_ok = grid_autoplace(l.a, items, n, ec, er, dense)
    }
    if !placed_ok { ret (g, false) }
    var nc = usize(ec)
    var nr = usize(er)
    var i = 0usize
    while i < n {
        if usize(items[i].cs + items[i].cn) > nc { nc = usize(items[i].cs + items[i].cn) }
        if usize(items[i].rs + items[i].rn) > nr { nr = usize(items[i].rs + items[i].rn) }
        i += 1usize
    }
    if nc > 1000usize { nc = 1000usize }
    if nr > 5000usize { nr = 5000usize }
    g.nc = nc
    g.nr = nr
    // `margin-trim`: the margins of the items that touch the container's edges.
    let gtrim = trim_flags(l, b)
    if gtrim != 0u8 {
        var ti = 0usize
        while ti < n {
            let tb = bx(l, items[ti].box)
            if (gtrim & 1u8) != 0u8 && items[ti].rs == 0i32 { tb.margin[0usize] = 0.0f64 }
            if (gtrim & 2u8) != 0u8 && usize(items[ti].rs + items[ti].rn) >= nr { tb.margin[2usize] = 0.0f64 }
            if (gtrim & 4u8) != 0u8 && items[ti].cs == 0i32 { tb.margin[3usize] = 0.0f64 }
            if (gtrim & 8u8) != 0u8 && usize(items[ti].cs + items[ti].cn) >= nc { tb.margin[1usize] = 0.0f64 }
            ti += 1usize
        }
    }
    let (ct, ce) = mem.alloc[GTrack](l.a, nc + 1usize)
    let (rt, re) = mem.alloc[GTrack](l.a, nr + 1usize)
    if ce != ok || re != ok { ret (g, false) }
    k = 0usize
    while k < nc {
        if k < ctr.len { ct[k] = ctr.items[k] } else if k >= usize(ec) { ct[k] = grid_make_track(&auto_cols, k - usize(ec)) } else { ct[k] = grid_make_track(&auto_cols, 0usize) }
        k += 1usize
    }
    k = 0usize
    while k < nr {
        if k < rtr.len { rt[k] = rtr.items[k] } else if k >= usize(er) { rt[k] = grid_make_track(&auto_rows, k - usize(er)) } else { rt[k] = grid_make_track(&auto_rows, 0usize) }
        k += 1usize
    }
    // `auto-fit` tracks no item lands in collapse to nothing.
    k = 0usize
    while k < nc {
        if ct[k].fit {
            var used = false
            var ii = 0usize
            while ii < n {
                if usize(items[ii].cs) <= k && k < usize(items[ii].cs + items[ii].cn) { used = true }
                ii += 1usize
            }
            if !used {
                ct[k].collapsed = true
                ct[k].min = SizeFn { kind: 0u8, v: 0.0f64 }
                ct[k].max = SizeFn { kind: 0u8, v: 0.0f64 }
            }
        }
        k += 1usize
    }
    k = 0usize
    while k < nr {
        if rt[k].fit {
            var used2 = false
            var ij = 0usize
            while ij < n {
                if usize(items[ij].rs) <= k && k < usize(items[ij].rs + items[ij].rn) { used2 = true }
                ij += 1usize
            }
            if !used2 {
                rt[k].collapsed = true
                rt[k].min = SizeFn { kind: 0u8, v: 0.0f64 }
                rt[k].max = SizeFn { kind: 0u8, v: 0.0f64 }
            }
        }
        k += 1usize
    }
    g.cols = ct
    g.rows = rt
    g.cnames = cnames
    g.rnames = rnames
    g.ec = ec
    g.er = er
    ret (g, true)
}

// --- Track sizing (CSS Grid 12): base sizes and growth limits, intrinsic contributions, flexible tracks.

fn is_intrinsic_min(k: u8) -> bool { ret k == 3u8 || k == 4u8 || k == 5u8 }

fn is_intrinsic_max(k: u8) -> bool { ret k == 3u8 || k == 4u8 || k == 5u8 || k == 6u8 }

fn size_tracks(tr: []GTrack, n: usize, gap: f64, avail: f64, items: []GItem, nitems: usize, is_col: bool, min_mode: bool, stretch: bool) {
    if n == 0usize { ret }
    var t = 0usize
    while t < n {
        var base = 0.0f64
        let sf = tr[t].min
        if sf.kind == 0u8 { base = sf.v } else if sf.kind == 1u8 && avail >= 0.0f64 { base = sf.v * avail }
        var limit = inf()
        let mf = tr[t].max
        if mf.kind == 0u8 { limit = mf.v } else if mf.kind == 1u8 && avail >= 0.0f64 { limit = mf.v * avail }
        if limit < base { limit = base }
        tr[t].base = base
        tr[t].limit = limit
        tr[t].pos = 0.0f64
        t += 1usize
    }
    // Items covering one track.
    var i = 0usize
    while i < nitems {
        var start = items[i].rs
        var span = items[i].rn
        var mn = items[i].rmin
        var mx = items[i].rmax
        if is_col {
            start = items[i].cs
            span = items[i].cn
            mn = items[i].cmin
            mx = items[i].cmax
        }
        if min_mode { mx = mn }
        if span == 1i32 && usize(start) < n {
            let c = usize(start)
            let sk = tr[c].min.kind
            if sk == 3u8 || sk == 4u8 { tr[c].base = maxf(tr[c].base, mn) } else if sk == 5u8 { tr[c].base = maxf(tr[c].base, mx) }
            let mk = tr[c].max.kind
            if is_intrinsic_max(mk) {
                var contribution = mx
                if mk == 4u8 { contribution = mn }
                if tr[c].limit >= inf() { tr[c].limit = contribution } else { tr[c].limit = maxf(tr[c].limit, contribution) }
            }
        }
        i += 1usize
    }
    t = 0usize
    while t < n {
        if tr[t].limit >= inf() && is_intrinsic_max(tr[t].max.kind) { tr[t].limit = tr[t].base }
        if tr[t].max.kind == 6u8 { tr[t].limit = minf(tr[t].limit, maxf(tr[t].max.v, tr[t].base)) }
        if tr[t].limit < tr[t].base { tr[t].limit = tr[t].base }
        t += 1usize
    }
    // Items covering several tracks (those touching flexible tracks size those tracks later).
    i = 0usize
    while i < nitems {
        var start2 = items[i].rs
        var span2 = items[i].rn
        var mn2 = items[i].rmin
        var mx2 = items[i].rmax
        if is_col {
            start2 = items[i].cs
            span2 = items[i].cn
            mn2 = items[i].cmin
            mx2 = items[i].cmax
        }
        if min_mode { mx2 = mn2 }
        if span2 > 1i32 && usize(start2 + span2) <= n {
            var has_flex = false
            var cover = gap * f64(span2 - 1i32)
            var cover_limit = cover
            var intrinsic = 0usize
            var q = usize(start2)
            while q < usize(start2 + span2) {
                if tr[q].max.kind == 2u8 { has_flex = true }
                cover += tr[q].base
                cover_limit += tr[q].limit
                if is_intrinsic_min(tr[q].min.kind) { intrinsic += 1usize }
                q += 1usize
            }
            if !has_flex {
                if mn2 > cover && intrinsic > 0usize {
                    let share = (mn2 - cover) / f64(intrinsic)
                    q = usize(start2)
                    while q < usize(start2 + span2) {
                        if is_intrinsic_min(tr[q].min.kind) { tr[q].base += share }
                        q += 1usize
                    }
                }
                var growable = 0usize
                q = usize(start2)
                while q < usize(start2 + span2) {
                    if is_intrinsic_max(tr[q].max.kind) { growable += 1usize }
                    q += 1usize
                }
                if mx2 > cover_limit && growable > 0usize {
                    let share2 = (mx2 - cover_limit) / f64(growable)
                    q = usize(start2)
                    while q < usize(start2 + span2) {
                        if is_intrinsic_max(tr[q].max.kind) { tr[q].limit += share2 }
                        q += 1usize
                    }
                }
                q = usize(start2)
                while q < usize(start2 + span2) {
                    if tr[q].limit < tr[q].base { tr[q].limit = tr[q].base }
                    q += 1usize
                }
            }
        }
        i += 1usize
    }
    // Maximise: share the free space among the tracks that can still grow.
    if avail >= 0.0f64 {
        var round = 0usize
        while round < 16usize {
            var used = gaps_of(tr, n, gap)
            var growing = 0usize
            t = 0usize
            while t < n {
                used += tr[t].base
                if tr[t].base < tr[t].limit - 0.0001f64 && tr[t].max.kind != 2u8 { growing += 1usize }
                t += 1usize
            }
            let free = avail - used
            if free <= 0.0001f64 || growing == 0usize { break }
            let share = free / f64(growing)
            t = 0usize
            while t < n {
                if tr[t].base < tr[t].limit - 0.0001f64 && tr[t].max.kind != 2u8 { tr[t].base = minf(tr[t].limit, tr[t].base + share) }
                t += 1usize
            }
            round += 1usize
        }
    }
    // Flexible tracks.
    var sum_fr = 0.0f64
    t = 0usize
    while t < n {
        if tr[t].max.kind == 2u8 {
            sum_fr += tr[t].max.v
            tr[t].pos = 1.0f64
        }
        t += 1usize
    }
    if sum_fr > 0.0f64 {
        var fr_size = 0.0f64
        if avail >= 0.0f64 {
            var guard = 0usize
            while guard < 16usize {
                var left = avail - gaps_of(tr, n, gap)
                var factors = 0.0f64
                t = 0usize
                while t < n {
                    if tr[t].pos > 0.5f64 { factors += tr[t].max.v } else { left -= tr[t].base }
                    t += 1usize
                }
                if factors < 1.0f64 { factors = 1.0f64 }
                fr_size = maxf(0.0f64, left) / factors
                var changed = false
                t = 0usize
                while t < n {
                    if tr[t].pos > 0.5f64 && fr_size * tr[t].max.v < tr[t].base {
                        tr[t].pos = 0.0f64
                        changed = true
                    }
                    t += 1usize
                }
                if !changed { break }
                guard += 1usize
            }
        } else {
            // No definite size: the largest need per fr, from the tracks' own bases and the items' contributions.
            t = 0usize
            while t < n {
                if tr[t].max.kind == 2u8 && tr[t].max.v > 0.0f64 { fr_size = maxf(fr_size, tr[t].base / tr[t].max.v) }
                t += 1usize
            }
            i = 0usize
            while i < nitems {
                var start3 = items[i].rs
                var span3 = items[i].rn
                var mx3 = items[i].rmax
                if is_col {
                    start3 = items[i].cs
                    span3 = items[i].cn
                    mx3 = items[i].cmax
                    if min_mode { mx3 = items[i].cmin }
                }
                if usize(start3 + span3) <= n {
                    var fsum = 0.0f64
                    var fixed = gap * f64(span3 - 1i32)
                    var q2 = usize(start3)
                    while q2 < usize(start3 + span3) {
                        if tr[q2].max.kind == 2u8 { fsum += tr[q2].max.v } else { fixed += tr[q2].base }
                        q2 += 1usize
                    }
                    if fsum > 0.0f64 { fr_size = maxf(fr_size, (mx3 - fixed) / maxf(fsum, 1.0f64)) }
                }
                i += 1usize
            }
        }
        t = 0usize
        while t < n {
            if tr[t].max.kind == 2u8 && (tr[t].pos > 0.5f64 || avail < 0.0f64) { tr[t].base = maxf(tr[t].base, fr_size * tr[t].max.v) }
            t += 1usize
        }
    }
    // Stretch the auto tracks over any space left.
    if stretch && avail >= 0.0f64 {
        var used2 = gaps_of(tr, n, gap)
        var autos = 0usize
        t = 0usize
        while t < n {
            used2 += tr[t].base
            if tr[t].max.kind == 3u8 { autos += 1usize }
            t += 1usize
        }
        if avail > used2 && autos > 0usize {
            let each = (avail - used2) / f64(autos)
            t = 0usize
            while t < n {
                if tr[t].max.kind == 3u8 { tr[t].base += each }
                t += 1usize
            }
        }
    }
}

// The tracks that take part in the gutters: a collapsed track merges its two gutters into one.
fn gaps_of(tr: []GTrack, n: usize, gap: f64) -> f64 {
    var v = 0usize
    var t = 0usize
    while t < n {
        if !tr[t].collapsed { v += 1usize }
        t += 1usize
    }
    if v > 1usize { ret gap * f64(v - 1usize) }
    ret 0.0f64
}

fn visible_tracks(tr: []GTrack, from: usize, to: usize) -> usize {
    var v = 0usize
    var t = from
    while t < to {
        if !tr[t].collapsed { v += 1usize }
        t += 1usize
    }
    ret v
}

fn tracks_total(tr: []GTrack, n: usize, gap: f64) -> f64 {
    var sum = 0.0f64
    var t = 0usize
    while t < n {
        sum += tr[t].base
        t += 1usize
    }
    let vis = visible_tracks(tr, 0usize, n)
    if vis > 1usize { sum += gap * f64(vis - 1usize) }
    ret sum
}

fn position_tracks(tr: []GTrack, n: usize, gap: f64, avail: f64, mode: style.Align) {
    var lead = 0.0f64
    var spacing = 0.0f64
    let free = avail - tracks_total(tr, n, gap)
    let vis = visible_tracks(tr, 0usize, n)
    if avail >= 0.0f64 && n > 0usize {
        if mode == .End || mode == .FlexEnd || mode == .Right {
            lead = free
        } else if mode == .Center {
            lead = free / 2.0f64
        } else if free > 0.0f64 {
            if mode == .SpaceBetween && vis > 1usize {
                spacing = free / f64(vis - 1usize)
            } else if mode == .SpaceAround && vis > 0usize {
                spacing = free / f64(vis)
                lead = spacing / 2.0f64
            } else if mode == .SpaceEvenly {
                spacing = free / f64(vis + 1usize)
                lead = spacing
            }
        }
    }
    var cursor = lead
    var t = 0usize
    while t < n {
        tr[t].pos = cursor
        if tr[t].collapsed {
            cursor += tr[t].base
        } else {
            cursor += tr[t].base + gap + spacing
        }
        t += 1usize
    }
}

fn grid_area_size(tr: []GTrack, start: i32, span: i32, gap: f64) -> f64 {
    var sum = 0.0f64
    var q = usize(start)
    while q < usize(start + span) {
        sum += tr[q].base
        q += 1usize
    }
    let vis = visible_tracks(tr, usize(start), usize(start + span))
    if vis > 1usize { sum += gap * f64(vis - 1usize) }
    ret sum
}

// The content width item `id` takes in an area `area_w` wide (the margins are in the box already).
fn grid_item_width(l: *Layout, id: u32, cs: *const style.Style, area_w: f64) -> f64 {
    let is = bstyle(l, id)
    let ib = bx(l, id)
    var just = is.justify_self
    if just == .Auto { just = cs.justify_items }
    let extras = horizontal_extras(ib)
    let avail = area_w - ib.margin[3usize] - ib.margin[1usize] - extras
    let (wv, has_w) = resolve_len(is.width, area_w)
    if is.width.kind == .Px && has_w { ret maxf(0.0f64, clamp_width(l, id, to_content_w(l, id, wv), area_w)) }
    let stretch = (just == .Normal || just == .Stretch) && is.margin[3usize].kind != .Auto && is.margin[1usize].kind != .Auto
    if ib.inner == .Replaced {
        let (rw, _rh) = used_replaced_size(l, id, area_w, -1.0f64)
        if just == .Stretch && stretch { ret maxf(0.0f64, avail) }
        ret rw
    }
    if stretch { ret maxf(0.0f64, clamp_width(l, id, avail, area_w)) }
    let (mn, mx) = content_widths(l, id)
    ret maxf(0.0f64, clamp_width(l, id, minf(maxf(mn, avail), mx), area_w))
}

fn grid_axis_offset(mode: style.Align, free: f64) -> f64 {
    if free <= 0.0f64 { ret 0.0f64 }
    if mode == .End || mode == .FlexEnd || mode == .SelfEnd || mode == .Right { ret free }
    if mode == .Center { ret free / 2.0f64 }
    ret 0.0f64
}

fn grid_widths(l: *Layout, b: u32) -> (f64, f64) {
    var mn = 0.0f64
    var mx = 0.0f64
    var pass = 0usize
    while pass < 2usize {
        let (g, built) = grid_build(l, b, -1.0f64, -1.0f64)
        if !built { ret (0.0f64, 0.0f64) }
        let (wide_items, wide_n) = subgrid_contributions(l, g)
        size_tracks(g.cols, g.nc, g.gap_c, -1.0f64, wide_items, wide_n, true, pass == 0usize, false)
        let total = tracks_total(g.cols, g.nc, g.gap_c)
        if pass == 0usize { mn = total } else { mx = total }
        pass += 1usize
    }
    ret (mn, mx)
}

// `grid-lanes-direction: ... fill-reverse track-reverse`: the lanes are laid out in their normal order and flow, then the
// layout is mirrored across the lane axis (track-reverse) and across the stacking axis (fill-reverse).
fn lanes_reversal(cs: *const style.Style) -> (bool, bool) {
    let (v, has) = extra_text(cs, "grid-lanes-direction")
    if !has { ret (false, false) }
    ret (str.contains(v, "fill-reverse"), str.contains(v, "track-reverse"))
}

// Where the lanes holding an item whose margin box starts at `at` begin along the lane axis, and how far they run.
fn lane_area(tr: []GTrack, n: usize, gap: f64, at: f64, span: usize) -> (f64, f64) {
    var k = 0usize
    var q = 0usize
    while q < n {
        if tr[q].pos <= at + 0.01f64 { k = q }
        q += 1usize
    }
    var sp = span
    if sp < 1usize { sp = 1usize }
    if k + sp > n { sp = n - k }
    ret (tr[k].pos, grid_area_size(tr, i32(k), i32(sp), gap))
}

fn lanes_mirror(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, columns: bool, lane_extent: f64, stack_extent: f64) {
    let (fill_rev, track_rev) = lanes_reversal(cs)
    if !fill_rev && !track_rev { ret }
    let bb = bx(l, b)
    let ox0 = bb.border[3usize] + bb.padding[3usize]
    let oy0 = bb.border[0usize] + bb.padding[0usize]
    var i = 0usize
    while i < g.n {
        let pb = bx(l, g.items[i].box)
        if columns {
            if track_rev && g.nc > 0usize {
                // The lane area moves to the other end; the item keeps its place inside it.
                let (top, size) = lane_area(g.cols, g.nc, g.gap_c, pb.x - ox0 - pb.margin[3usize], usize(maxf(1.0f64, f64(g.items[i].cn))))
                pb.x = ox0 + (lane_extent - top - size) + (pb.x - ox0 - top)
            }
            if fill_rev { pb.y = oy0 + stack_extent - (pb.y - oy0) - pb.h }
        } else {
            if track_rev && g.nr > 0usize {
                let (top, size) = lane_area(g.rows, g.nr, g.gap_r, pb.y - oy0 - pb.margin[0usize], usize(maxf(1.0f64, f64(g.items[i].rn))))
                pb.y = oy0 + (lane_extent - top - size) + (pb.y - oy0 - top)
            }
            if fill_rev { pb.x = ox0 + stack_extent - (pb.x - ox0) - pb.w }
        }
        i += 1usize
    }
}

fn layout_grid(l: *Layout, b: u32, cw: f64, ch: f64) -> f64 {
    let cs = bstyle(l, b)
    let (g, built) = grid_build(l, b, cw, ch)
    if !built { ret 0.0f64 }
    let stretch_cols = cs.justify_content == .Normal || cs.justify_content == .Stretch
    let stretch_rows = cs.align_content == .Normal || cs.align_content == .Stretch
    // Lanes are the explicit tracks: the implicit ones auto-placement made up are not lanes.
    if cs.lanes && g.ec > 0i32 && usize(g.ec) < g.nc { g.nc = usize(g.ec) }
    if cs.lanes && g.er > 0i32 && g.ec == 0i32 && usize(g.er) < g.nr { g.nr = usize(g.er) }
    if cs.lanes && g.er > 0i32 && g.ec == 0i32 {
        let rows_h = layout_lanes_rows(l, b, g, cs, cw, ch)
        var rows_lane = ch
        if rows_lane < 0.0f64 { rows_lane = rows_h }
        lanes_mirror(l, b, g, cs, false, rows_lane, cw)
        ret rows_h
    }
    if cs.lanes {
        // A masonry item may land in any lane, so each one counts towards the size of every lane it could occupy.
        let (ex, exe) = mem.alloc[GItem](l.a, g.n * (g.nc + 1usize) + 1usize)
        if exe == ok {
            var exn = 0usize
            var xi = 0usize
            while xi < g.n {
                let item = g.items[xi]
                var s0 = 0usize
                // (an item spanning several lanes does not size any of them)
                while s0 + usize(maxf(1.0f64, f64(item.cn))) <= g.nc && item.cn <= 1i32 {
                    var copy = item
                    copy.cs = i32(s0)
                    ex[exn] = copy
                    exn += 1usize
                    s0 += 1usize
                }
                xi += 1usize
            }
            // (items only size lanes when the container's width is not definite; here `auto` lanes share it equally)
            if cs.width.kind == .Px || cs.display == .Grid { exn = 0usize }
            size_tracks(g.cols, g.nc, g.gap_c, cw, ex, exn, true, false, stretch_cols)
        } else {
            size_tracks(g.cols, g.nc, g.gap_c, cw, g.items, g.n, true, false, stretch_cols)
        }
        if lanes_dense(cs) {
            let dense_h = layout_lanes_dense(l, b, g, cs, cw)
            var dense_stack = ch
            if dense_stack < 0.0f64 { dense_stack = dense_h }
            lanes_mirror(l, b, g, cs, true, cw, dense_stack)
            ret dense_h
        }
        let lanes_h = layout_lanes(l, b, g, cs, cw, ch)
        var lane_h = ch
        if lane_h < 0.0f64 { lane_h = lanes_h }
        lanes_mirror(l, b, g, cs, true, cw, lane_h)
        ret lanes_h
    }
    let (sized_items, sized_n) = subgrid_contributions(l, g)
    size_tracks(g.cols, g.nc, g.gap_c, cw, sized_items, sized_n, true, false, stretch_cols)
    // Row contributions are the items' heights at their column widths.
    let (row_made, ree) = list.init[GItem](l.a, 8usize)
    var row_extra = row_made
    // Items aligned on their first baseline line up with the lowest one of their row.
    let (bl_up, bl_e1) = mem.alloc[f64](l.a, g.n + 1usize)
    let (bl_on, bl_e2) = mem.alloc[bool](l.a, g.n + 1usize)
    let (grp, bl_e3) = mem.alloc[f64](l.a, g.nr + 1usize)
    if bl_e1 != ok || bl_e2 != ok || bl_e3 != ok { ret 0.0f64 }
    var gk = 0usize
    while gk <= g.nr {
        grp[gk] = 0.0f64
        gk += 1usize
    }
    if ree != ok { ret 0.0f64 }
    var i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let area_w = grid_area_size(g.cols, g.items[i].cs, g.items[i].cn, g.gap_c)
        let w = grid_item_width(l, id, cs, area_w)
        let is0 = bstyle(l, id)
        var hs0 = -1.0f64
        let (hv0, has_h0) = resolve_len(is0.height, -1.0f64)
        if is0.height.kind == .Px && has_h0 { hs0 = to_content_h(l, id, hv0) }
        subgrid_prepare(l, g, i, true, false)
        flex_place_item(l, id, w, hs0)
        l.sub_has_c = false
        l.sub_has_r = false
        let ib = bx(l, id)
        let outer = ib.h + ib.margin[0usize] + ib.margin[2usize]
        g.items[i].rmin = outer
        g.items[i].rmax = outer
        bl_on[i] = false
        var al0 = is0.align_self
        if al0 == .Auto { al0 = cs.align_items }
        if al0 == .Baseline || al0 == .FirstBaseline {
            let (bfound, bby) = first_baseline(l, id)
            var bup = ib.h
            if bfound { bup = bby }
            bl_up[i] = ib.margin[0usize] + bup
            bl_on[i] = true
            let brow = usize(g.items[i].rs)
            if brow < g.nr && bl_up[i] > grp[brow] { grp[brow] = bl_up[i] }
        }
        // A subgrid in the rows has no height of its own to give: its own rows (sized by its content) stand in for it.
        if bx(l, id).inner == .Grid && g.items[i].rn > 0i32 && subgrid_axes_match(l, id) {
            let (rt0, hrt0) = extra_text(is0, "grid-template-rows")
            if hrt0 && subgrid_axis(rt0) && l.grids.len > 0usize {
                var gi = l.grids.len
                var gfound = false
                var geom: GridGeom = zero
                while gi > 0usize && !gfound {
                    gi -= 1usize
                    if l.grids.items[gi].box == id {
                        geom = l.grids.items[gi]
                        gfound = true
                    }
                }
                if gfound && geom.nr > 0usize {
                    g.items[i].rmin = 0.0f64
                    g.items[i].rmax = 0.0f64
                    let sb2 = bx(l, id)
                    var rk = 0usize
                    while rk < geom.nr && rk < usize(g.items[i].rn) {
                        var rv = geom.rsz[rk]
                        if rk == 0usize { rv += sb2.margin[0usize] + sb2.border[0usize] + sb2.padding[0usize] }
                        if rk + 1usize == geom.nr || rk + 1usize == usize(g.items[i].rn) { rv += sb2.margin[2usize] + sb2.border[2usize] + sb2.padding[2usize] }
                        var rit: GItem = zero
                        rit.box = id
                        rit.cs = 0i32
                        rit.cn = 1i32
                        rit.rs = g.items[i].rs + i32(rk)
                        rit.rn = 1i32
                        rit.rmin = rv
                        rit.rmax = rv
                        let rp = list.push[GItem](&row_extra, rit)
                        rk += 1usize
                    }
                }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < g.n {
        if bl_on[i] && usize(g.items[i].rs) < g.nr {
            let bb1 = bx(l, g.items[i].box)
            let bouter = bb1.h + bb1.margin[0usize] + bb1.margin[2usize] + (grp[usize(g.items[i].rs)] - bl_up[i])
            g.items[i].rmin = bouter
            g.items[i].rmax = bouter
        }
        i += 1usize
    }
    // An automatic height still stretches the rows up to the container's `min-height`.
    var ch_fill = ch
    if ch_fill < 0.0f64 && cs.min_height.kind == .Px {
        let (mhv, has_mh) = resolve_len(cs.min_height, -1.0f64)
        if has_mh && mhv > 0.0f64 { ch_fill = to_content_h(l, b, mhv) }
    }
    var row_items = g.items
    var row_n = g.n
    if row_extra.len > 0usize {
        let (merged, me) = mem.alloc[GItem](l.a, g.n + row_extra.len)
        if me == ok {
            var mi = 0usize
            while mi < g.n {
                merged[mi] = g.items[mi]
                mi += 1usize
            }
            var mj = 0usize
            while mj < row_extra.len {
                merged[g.n + mj] = row_extra.items[mj]
                mj += 1usize
            }
            row_items = merged
            row_n = g.n + row_extra.len
        }
    }
    size_tracks(g.rows, g.nr, g.gap_r, ch_fill, row_items, row_n, false, false, stretch_rows && ch_fill >= 0.0f64)
    position_tracks(g.cols, g.nc, g.gap_c, cw, cs.justify_content)
    position_tracks(g.rows, g.nr, g.gap_r, ch, cs.align_content)
    let bb0 = bx(l, b)
    let ox0 = bb0.border[3usize] + bb0.padding[3usize]
    let oy0 = bb0.border[0usize] + bb0.padding[0usize]
    let rtl = cs.direction == .Rtl
    i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let area_w = grid_area_size(g.cols, g.items[i].cs, g.items[i].cn, g.gap_c)
        let area_h = grid_area_size(g.rows, g.items[i].rs, g.items[i].rn, g.gap_r)
        let ax = g.cols[usize(g.items[i].cs)].pos
        let ay = g.rows[usize(g.items[i].rs)].pos
        let w = grid_item_width(l, id, cs, area_w)
        // Height: specified, stretched to the area, or from the content.
        var align = is.align_self
        if align == .Auto { align = cs.align_items }
        let ib = bx(l, id)
        var hspec = -1.0f64
        let (hv, has_h) = resolve_len(is.height, area_h)
        if is.height.kind == .Px && has_h {
            hspec = to_content_h(l, id, hv)
        } else if (align == .Normal || align == .Stretch) && is.height.kind == .Auto && is.margin[0usize].kind != .Auto && is.margin[2usize].kind != .Auto && ib.inner != .Replaced {
            hspec = maxf(0.0f64, area_h - ib.margin[0usize] - ib.margin[2usize] - vertical_extras(ib))
        }
        var just0 = is.justify_self
        if just0 == .Auto { just0 = cs.justify_items }
        if (just0 == .Normal || just0 == .Stretch) && is.width.kind == .Auto && is.margin[3usize].kind != .Auto && is.margin[1usize].kind != .Auto { l.orth_fb = w }
        subgrid_prepare(l, g, i, true, true)
        flex_place_item(l, id, w, hspec)
        l.sub_has_c = false
        l.sub_has_r = false
        let pb = bx(l, id)
        // Auto margins and the alignment offsets.
        var just = is.justify_self
        if just == .Auto { just = cs.justify_items }
        let free_w = area_w - pb.w - pb.margin[3usize] - pb.margin[1usize]
        var dx = grid_axis_offset(just, free_w)
        if is.margin[3usize].kind == .Auto || is.margin[1usize].kind == .Auto {
            dx = 0.0f64
            if is.margin[3usize].kind == .Auto && is.margin[1usize].kind == .Auto { dx = maxf(0.0f64, free_w) / 2.0f64 } else if is.margin[3usize].kind == .Auto { dx = maxf(0.0f64, free_w) }
        }
        let free_h = area_h - pb.h - pb.margin[0usize] - pb.margin[2usize]
        var dy = grid_axis_offset(align, free_h)
        if bl_on[i] && usize(g.items[i].rs) < g.nr { dy = grp[usize(g.items[i].rs)] - bl_up[i] }
        if is.margin[0usize].kind == .Auto || is.margin[2usize].kind == .Auto {
            dy = 0.0f64
            if is.margin[0usize].kind == .Auto && is.margin[2usize].kind == .Auto { dy = maxf(0.0f64, free_h) / 2.0f64 } else if is.margin[0usize].kind == .Auto { dy = maxf(0.0f64, free_h) }
        }
        var px = ax + dx + pb.margin[3usize]
        if rtl { px = cw - (ax + dx) - pb.w - pb.margin[1usize] - 0.0f64 }
        pb.x = ox0 + px
        pb.y = oy0 + ay + dy + pb.margin[0usize]
        i += 1usize
    }
    var total = tracks_total(g.rows, g.nr, g.gap_r)
    if g.nr > 0usize {
        let last = g.rows[g.nr - 1usize]
        total = maxf(total, last.pos + last.base)
    }
    // Keep the track geometry for absolutely positioned children.
    let (cpos, cpe) = mem.alloc[f64](l.a, g.nc + 1usize)
    let (csz, cse) = mem.alloc[f64](l.a, g.nc + 1usize)
    let (rpos, rpe) = mem.alloc[f64](l.a, g.nr + 1usize)
    let (rsz, rse) = mem.alloc[f64](l.a, g.nr + 1usize)
    if cpe == ok && cse == ok && rpe == ok && rse == ok {
        var q = 0usize
        while q < g.nc {
            cpos[q] = g.cols[q].pos
            csz[q] = g.cols[q].base
            q += 1usize
        }
        q = 0usize
        while q < g.nr {
            rpos[q] = g.rows[q].pos
            rsz[q] = g.rows[q].base
            q += 1usize
        }
        let gg = GridGeom { box: b, nc: g.nc, nr: g.nr, cpos: cpos, csz: csz, rpos: rpos, rsz: rsz, cnames: g.cnames, rnames: g.rnames, ec: g.ec, er: g.er, w: cw, rtl: rtl }
        let gp2 = list.push[GridGeom](&l.grids, gg)
    }
    ret total
}

// Whether an item of a lane container fills its lane in the lane axis: `stretch` and the `normal` default do.
fn cross_stretches(is: *const style.Style, cs: *const style.Style) -> bool {
    var al = is.align_self
    if al == .Auto { al = cs.align_items }
    ret al == .Stretch || al == .Normal
}

// How far an item of a lane container moves along the lane axis inside `free` room: centred or against the end.
fn cross_offset(is: *const style.Style, cs: *const style.Style, free: f64) -> f64 {
    if free <= 0.0f64 { ret 0.0f64 }
    var al = is.align_self
    if al == .Auto { al = cs.align_items }
    if al == .Center { ret free / 2.0f64 }
    if al == .End || al == .FlexEnd || al == .SelfEnd { ret free }
    ret 0.0f64
}

// The same for a plain grid with `subgrid` rows laid out in row lanes: the lanes it spans are its row tracks.
fn subgrid_prepare_lane_rows(l: *Layout, g: *Grid, id: u32, start: usize, span: usize) {
    l.sub_has_c = false
    l.sub_has_r = false
    if bx(l, id).inner != .Grid || bstyle(l, id).lanes || span == 0usize || start + span > g.nr { ret }
    let (rt, hrt) = extra_text(bstyle(l, id), "grid-template-rows")
    if !hrt || !subgrid_axis(rt) { ret }
    let (sz, e) = mem.alloc[f64](l.a, span)
    if e != ok { ret }
    var k = 0usize
    while k < span {
        sz[k] = g.rows[start + k].base
        k += 1usize
    }
    l.sub_r = sz
    l.sub_gr = g.gap_r
    l.sub_has_r = true
}

// `display: grid-lanes` with the lanes along the rows: items flow sideways, each into the lane (or run of lanes) whose
// content ends furthest left, and take their width from their content.
fn layout_lanes_rows(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, cw: f64, ch: f64) -> f64 {
    let bb0 = bx(l, b)
    let ox0 = bb0.border[3usize] + bb0.padding[3usize]
    let oy0 = bb0.border[0usize] + bb0.padding[0usize]
    // Natural heights (at a fit-content width) size the lanes when the container's height is not definite.
    var i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let ib = bx(l, id)
        let (mn, mx) = content_widths(l, id)
        let w = maxf(mn, minf(mx, cw - ib.margin[3usize] - ib.margin[1usize] - horizontal_extras(ib)))
        flex_place_item(l, id, w, -1.0f64)
        let outer = bx(l, id).h + ib.margin[0usize] + ib.margin[2usize]
        g.items[i].rmin = outer
        g.items[i].rmax = outer
        i += 1usize
    }
    let stretch_rows = cs.align_content == .Normal || cs.align_content == .Stretch
    if ch < 0.0f64 {
        let (ex, exe) = mem.alloc[GItem](l.a, g.n * (g.nr + 1usize) + 1usize)
        var exn = 0usize
        if exe == ok {
            var xi = 0usize
            while xi < g.n {
                let item = g.items[xi]
                var s0 = 0usize
                while s0 < g.nr && item.rn <= 1i32 {
                    var copy = item
                    copy.rs = i32(s0)
                    ex[exn] = copy
                    exn += 1usize
                    s0 += 1usize
                }
                xi += 1usize
            }
        }
        size_tracks(g.rows, g.nr, g.gap_r, ch, ex, exn, false, false, false)
    } else {
        size_tracks(g.rows, g.nr, g.gap_r, ch, g.items, 0usize, false, false, stretch_rows)
    }
    position_tracks(g.rows, g.nr, g.gap_r, ch, cs.align_content)
    let (ends, ee) = mem.alloc[f64](l.a, g.nr + 1usize)
    let (lefts, le1) = mem.alloc[f64](l.a, g.n + 1usize)
    let (rstart, re1) = mem.alloc[usize](l.a, g.n + 1usize)
    let (rspan, re2) = mem.alloc[usize](l.a, g.n + 1usize)
    if le1 != ok || re1 != ok || re2 != ok { ret 0.0f64 }
    if ee != ok { ret 0.0f64 }
    var q = 0usize
    while q < g.nr {
        ends[q] = 0.0f64 - g.gap_c
        q += 1usize
    }
    var tol = 0.0f64
    let (tv, has_tv) = extra_text(cs, "flow-tolerance")
    if has_tv {
        let tl = cv.lower(l.a, cv.trim_ws(tv))
        tol = 0.0f64
        if str.ends_with(tl, "px") {
            let (nv, ne) = str.parse_i64(tl[..tl.len - 2usize])
            if ne == ok { tol = f64(nv) }
        }
    }
    i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let (sr, ers) = item_axis_specs(l.a, is, false)
        let span = usize(maxf(1.0f64, f64(g.items[i].rn)))
        var start = usize(g.items[i].rs)
        if sr.kind == 0u8 {
            var best = 0usize
            var best_end = 1000000000.0f64
            var s0 = 0usize
            while s0 + span <= g.nr {
                var e = -1000000000.0f64
                var t = s0
                while t < s0 + span {
                    if ends[t] > e { e = ends[t] }
                    t += 1usize
                }
                if e < best_end - tol {
                    best_end = e
                    best = s0
                }
                s0 += 1usize
            }
            start = best
        }
        if start + span > g.nr { start = 0usize }
        var left = -1000000000.0f64
        var t2 = start
        while t2 < start + span && t2 < g.nr {
            if ends[t2] > left { left = ends[t2] }
            t2 += 1usize
        }
        let area_h = grid_area_size(g.rows, i32(start), i32(span), g.gap_r)
        let ib = bx(l, id)
        let (mn, mx) = content_widths(l, id)
        var w = maxf(mn, minf(mx, cw - ib.margin[3usize] - ib.margin[1usize] - horizontal_extras(ib)))
        let (wv, has_w) = resolve_len(is.width, cw)
        if is.width.kind == .Px && has_w { w = to_content_w(l, id, wv) }
        var hs = -1.0f64
        let (hv, has_h) = resolve_len(is.height, area_h)
        if is.height.kind == .Px && has_h {
            hs = to_content_h(l, id, hv)
        } else if is.margin[0usize].kind != .Auto && is.margin[2usize].kind != .Auto && ib.inner != .Replaced && cross_stretches(is, cs) {
            hs = maxf(0.0f64, area_h - ib.margin[0usize] - ib.margin[2usize] - vertical_extras(ib))
        }
        subgrid_prepare_lane_rows(l, g, id, start, span)
        flex_place_item(l, id, w, hs)
        l.sub_has_c = false
        l.sub_has_r = false
        let pb = bx(l, id)
        let x0 = left + g.gap_c
        pb.x = ox0 + x0 + pb.margin[3usize]
        pb.y = oy0 + g.rows[start].pos + pb.margin[0usize] + cross_offset(is, cs, area_h - pb.h - pb.margin[0usize] - pb.margin[2usize])
        let right = x0 + pb.margin[3usize] + pb.w + pb.margin[1usize]
        lefts[i] = x0
        rstart[i] = start
        rspan[i] = span
        var t3 = start
        while t3 < start + span && t3 < g.nr {
            ends[t3] = right
            t3 += 1usize
        }
        i += 1usize
    }
    // Items of a lane aligned on their first baseline line up with the lowest one of the lane.
    var lane_up: [64]f64 = zero
    var bi = 0usize
    while bi < g.n {
        let bs = bstyle(l, g.items[bi].box)
        var bal = bs.align_self
        if bal == .Auto { bal = cs.align_items }
        if (bal == .Baseline || bal == .FirstBaseline) && rstart[bi] < 64usize {
            let bpb = bx(l, g.items[bi].box)
            let (bfound, bby) = first_baseline(l, g.items[bi].box)
            var bup = bpb.h
            if bfound { bup = bby }
            let bu = bpb.margin[0usize] + bup
            if bu > lane_up[rstart[bi]] { lane_up[rstart[bi]] = bu }
        }
        bi += 1usize
    }
    bi = 0usize
    while bi < g.n {
        let bs = bstyle(l, g.items[bi].box)
        var bal = bs.align_self
        if bal == .Auto { bal = cs.align_items }
        if (bal == .Baseline || bal == .FirstBaseline) && rstart[bi] < 64usize {
            let bpb = bx(l, g.items[bi].box)
            let (bfound, bby) = first_baseline(l, g.items[bi].box)
            var bup = bpb.h
            if bfound { bup = bby }
            bpb.y = oy0 + g.rows[rstart[bi]].pos + bpb.margin[0usize] + (lane_up[rstart[bi]] - bpb.margin[0usize] - bup)
        }
        bi += 1usize
    }
    // An item is aligned within the room it has along the lane: from its own end to just before the next item laid after it
    // in any of its lanes, or to the end of the container for the last one.
    i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let pb = bx(l, id)
        var limit = cw
        var j = i + 1usize
        while j < g.n {
            if rstart[j] < rstart[i] + rspan[i] && rstart[i] < rstart[j] + rspan[j] {
                let cand = lefts[j] - g.gap_c
                if cand < limit { limit = cand }
            }
            j += 1usize
        }
        let right = (pb.x - ox0) + pb.w + pb.margin[1usize]
        let free = limit - right
        if free > 0.0f64 {
            var just = is.justify_self
            if just == .Auto { just = cs.justify_items }
            if just == .Center {
                pb.x += free / 2.0f64
            } else if just == .End || just == .FlexEnd || just == .SelfEnd {
                pb.x += free
            } else if just == .Stretch && is.width.kind == .Auto {
                let hcontent = pb.h - vertical_extras(pb)
                flex_place_item(l, id, pb.w - horizontal_extras(pb) + free, hcontent)
            }
        }
        i += 1usize
    }
    var total = tracks_total(g.rows, g.nr, g.gap_r)
    if g.nr > 0usize {
        let last = g.rows[g.nr - 1usize]
        total = maxf(total, last.pos + last.base)
    }
    ret total
}

// `display: grid-lanes` (masonry) with the lanes along the columns: each item goes to the lane, or run of lanes, whose
// content ends highest (within `flow-tolerance`, the first such lane), and the container's height is the tallest lane.
fn lanes_dense(cs: *const style.Style) -> bool {
    let (pv, has_pv) = extra_text(cs, "grid-lanes-pack")
    if has_pv && str.contains(pv, "dense") { ret true }
    let (fv, has_fv) = extra_text(cs, "grid-auto-flow")
    ret has_fv && str.contains(fv, "dense")
}

// Dense packing: each item goes to the earliest free spot, holes beside spanning items included.
fn layout_lanes_dense(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, cw: f64) -> f64 {
    position_tracks(g.cols, g.nc, g.gap_c, cw, cs.justify_content)
    let bb0 = bx(l, b)
    let ox0 = bb0.border[3usize] + bb0.padding[3usize]
    let oy0 = bb0.border[0usize] + bb0.padding[0usize]
    let cap = g.n + 1usize
    let (os, e1) = mem.alloc[f64](l.a, (g.nc + 1usize) * cap)
    let (oe, e2) = mem.alloc[f64](l.a, (g.nc + 1usize) * cap)
    let (on, e3) = mem.alloc[usize](l.a, g.nc + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 }
    var q = 0usize
    while q < g.nc {
        on[q] = 0usize
        q += 1usize
    }
    var tol = 0.0f64
    let (tv, has_tv) = extra_text(cs, "flow-tolerance")
    if has_tv {
        let tl = cv.lower(l.a, cv.trim_ws(tv))
        if str.ends_with(tl, "px") {
            let (nv, ne) = str.parse_i64(tl[..tl.len - 2usize])
            if ne == ok { tol = f64(nv) }
        }
    }
    var total = 0.0f64
    var i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let (sc, ecs) = item_axis_specs(l.a, is, true)
        let span = usize(maxf(1.0f64, f64(g.items[i].cn)))
        var s_lo = 0usize
        var s_hi = 0usize
        if g.nc >= span { s_hi = g.nc - span }
        if sc.kind != 0u8 {
            s_lo = usize(g.items[i].cs)
            s_hi = s_lo
        }
        var best_y = 1000000000.0f64
        var best_s = s_lo
        var s0 = s_lo
        while s0 <= s_hi && s0 + span <= g.nc {
            let area_w = grid_area_size(g.cols, i32(s0), i32(span), g.gap_c)
            let w = grid_item_width(l, id, cs, area_w)
            var hs = -1.0f64
            let (hv, has_h) = resolve_len(is.height, -1.0f64)
            if is.height.kind == .Px && has_h { hs = to_content_h(l, id, hv) }
            subgrid_prepare_lane(l, g, id, s0, span)
            flex_place_item(l, id, w, hs)
            l.sub_has_c = false
            l.sub_has_r = false
            let ib = bx(l, id)
            let outer = ib.h + ib.margin[0usize] + ib.margin[2usize]
            // Candidate tops: 0 and just below every interval end in the spanned lanes.
            var cand_best = 1000000000.0f64
            var ci = -1i64
            while ci < i64(g.nc * cap) {
                var y = 0.0f64
                var valid = true
                if ci >= 0i64 {
                    let lane = usize(ci) / cap
                    let k = usize(ci) % cap
                    if lane < s0 || lane >= s0 + span || k >= on[lane] { valid = false } else { y = oe[lane * cap + k] + g.gap_r }
                }
                if valid && y < cand_best {
                    var free = true
                    var t = s0
                    while t < s0 + span && free {
                        var k2 = 0usize
                        while k2 < on[t] {
                            let a0 = os[t * cap + k2]
                            let b0 = oe[t * cap + k2]
                            if y < b0 + g.gap_r && y + outer + g.gap_r > a0 { free = false }
                            k2 += 1usize
                        }
                        t += 1usize
                    }
                    if free { cand_best = y }
                }
                ci += 1i64
            }
            if cand_best < best_y - tol {
                best_y = cand_best
                best_s = s0
            }
            s0 += 1usize
        }
        let area_w = grid_area_size(g.cols, i32(best_s), i32(span), g.gap_c)
        let w = grid_item_width(l, id, cs, area_w)
        var hs2 = -1.0f64
        let (hv2, has_h2) = resolve_len(is.height, -1.0f64)
        if is.height.kind == .Px && has_h2 { hs2 = to_content_h(l, id, hv2) }
        subgrid_prepare_lane(l, g, id, best_s, span)
        flex_place_item(l, id, w, hs2)
        l.sub_has_c = false
        l.sub_has_r = false
        let pb = bx(l, id)
        pb.x = ox0 + g.cols[best_s].pos + pb.margin[3usize]
        pb.y = oy0 + best_y + pb.margin[0usize]
        let bottom = best_y + pb.margin[0usize] + pb.h + pb.margin[2usize]
        var t3 = best_s
        while t3 < best_s + span && t3 < g.nc {
            os[t3 * cap + on[t3]] = best_y
            oe[t3 * cap + on[t3]] = bottom
            on[t3] += 1usize
            t3 += 1usize
        }
        if bottom > total { total = bottom }
        i += 1usize
    }
    ret total
}

// A plain grid laid out in grid-lanes with `subgrid` columns takes the lanes it spans as its tracks.
fn subgrid_prepare_lane(l: *Layout, g: *Grid, id: u32, start: usize, span: usize) {
    l.sub_has_c = false
    l.sub_has_r = false
    if bx(l, id).inner != .Grid || bstyle(l, id).lanes || span == 0usize || start + span > g.nc { ret }
    let (ct, hct) = extra_text(bstyle(l, id), "grid-template-columns")
    if !hct || !subgrid_axis(ct) { ret }
    let (sz, e) = mem.alloc[f64](l.a, span)
    if e != ok { ret }
    var k = 0usize
    while k < span {
        sz[k] = g.cols[start + k].base
        k += 1usize
    }
    l.sub_c = sz
    l.sub_gc = g.gap_c
    l.sub_has_c = true
}

fn layout_lanes(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, cw: f64, ch: f64) -> f64 {
    position_tracks(g.cols, g.nc, g.gap_c, cw, cs.justify_content)
    let bb0 = bx(l, b)
    let ox0 = bb0.border[3usize] + bb0.padding[3usize]
    let oy0 = bb0.border[0usize] + bb0.padding[0usize]
    let (ends, ee) = mem.alloc[f64](l.a, g.nc + 1usize)
    if ee != ok { ret 0.0f64 }
    let (lastin, le) = mem.alloc[usize](l.a, g.nc + 1usize)
    let (tops, te1) = mem.alloc[f64](l.a, g.n + 1usize)
    let (sstart, se1) = mem.alloc[usize](l.a, g.n + 1usize)
    let (sspan, se2) = mem.alloc[usize](l.a, g.n + 1usize)
    if te1 != ok || se1 != ok || se2 != ok { ret 0.0f64 }
    if le != ok { ret 0.0f64 }
    var q = 0usize
    while q < g.nc {
        ends[q] = 0.0f64 - g.gap_r
        lastin[q] = 1000000usize
        q += 1usize
    }
    var tol = 0.0f64
    let (tv, has_tv) = extra_text(cs, "flow-tolerance")
    if has_tv {
        let tl = cv.lower(l.a, cv.trim_ws(tv))
        tol = 0.0f64
        if str.ends_with(tl, "px") {
            let (nv, ne) = str.parse_i64(tl[..tl.len - 2usize])
            if ne == ok { tol = f64(nv) }
        }
    }
    var total = 0.0f64
    var i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let (sc, ecs) = item_axis_specs(l.a, is, true)
        let span = usize(maxf(1.0f64, f64(g.items[i].cn)))
        var start = usize(g.items[i].cs)
        if sc.kind == 0u8 && ecs.kind != 0u8 && g.nc >= span { start = 0usize }
        if sc.kind == 0u8 {
            // Auto placement: the lane whose spanned run ends highest.
            var best = 0usize
            var best_end = 1000000000.0f64
            var s0 = 0usize
            while s0 + span <= g.nc {
                var e = -1000000000.0f64
                var t = s0
                while t < s0 + span {
                    if ends[t] > e { e = ends[t] }
                    t += 1usize
                }
                if e < best_end - tol {
                    best_end = e
                    best = s0
                }
                s0 += 1usize
            }
            start = best
        }
        if start + span > g.nc { start = 0usize }
        var top = -1000000000.0f64
        var t2 = start
        while t2 < start + span && t2 < g.nc {
            if ends[t2] > top { top = ends[t2] }
            t2 += 1usize
        }
        let area_w = grid_area_size(g.cols, i32(start), i32(span), g.gap_c)
        let w = grid_item_width(l, id, cs, area_w)
        var hs = -1.0f64
        let (hv, has_h) = resolve_len(is.height, -1.0f64)
        if is.height.kind == .Px && has_h { hs = to_content_h(l, id, hv) }
        subgrid_prepare_lane(l, g, id, start, span)
        flex_place_item(l, id, w, hs)
        l.sub_has_c = false
        l.sub_has_r = false
        let pb = bx(l, id)
        let y0 = top + g.gap_r
        pb.x = ox0 + g.cols[start].pos + pb.margin[3usize]
        pb.y = oy0 + y0 + pb.margin[0usize]
        let bottom = y0 + pb.margin[0usize] + pb.h + pb.margin[2usize]
        tops[i] = y0
        sstart[i] = start
        sspan[i] = span
        var t3 = start
        while t3 < start + span && t3 < g.nc {
            ends[t3] = bottom
            lastin[t3] = i
            t3 += 1usize
        }
        if bottom > total { total = bottom }
        i += 1usize
    }
    // An item is aligned within the room it has in the stacking direction: from its own end to just before the next item laid
    // below it in any of its lanes, or to the end of the container for the last one.
    var container_end = total
    if ch >= 0.0f64 { container_end = ch }
    i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let is = bstyle(l, id)
        let pb = bx(l, id)
        var limit = container_end
        var j = i + 1usize
        while j < g.n {
            if sstart[j] < sstart[i] + sspan[i] && sstart[i] < sstart[j] + sspan[j] {
                let cand = tops[j] - g.gap_r
                if cand < limit { limit = cand }
            }
            j += 1usize
        }
        let bottom = (pb.y - oy0) + pb.h + pb.margin[2usize]
        let free = limit - bottom
        if free > 0.0f64 {
            var al = is.align_self
            if al == .Auto { al = cs.align_items }
            if al == .Center {
                pb.y += free / 2.0f64
            } else if al == .End || al == .FlexEnd || al == .SelfEnd {
                pb.y += free
            } else if al == .Stretch && is.height.kind == .Auto {
                let wcontent = pb.w - horizontal_extras(pb)
                flex_place_item(l, id, wcontent, pb.h - vertical_extras(pb) + free)
            }
        }
        i += 1usize
    }
    ret total
}

// The grid area an absolutely positioned child of grid container `gb` names, as (found, x0, x1, y0, y1) relative to the
// container's content box; an `auto` edge falls back to the padding box (`pw` x `ph` around the content box).
fn grid_abs_area(l: *Layout, gb: u32, child: u32, pw: f64, ph: f64, ox: f64, oy: f64) -> (bool, f64, f64, f64, f64) {
    var gi = l.grids.len
    var found = false
    var geom: GridGeom = zero
    while gi > 0usize && !found {
        gi -= 1usize
        if l.grids.items[gi].box == gb {
            geom = l.grids.items[gi]
            found = true
        }
    }
    if !found || geom.nc == 0usize || geom.nr == 0usize { ret (false, 0.0f64, 0.0f64, 0.0f64, 0.0f64) }
    let ks = bstyle(l, child)
    let (sc, ecs) = item_axis_specs(l.a, ks, true)
    let (sr, ers) = item_axis_specs(l.a, ks, false)
    var x0 = -ox
    var x1 = pw - ox
    var y0 = -oy
    var y1 = ph - oy
    var cnl = geom.cnames
    var rnl = geom.rnames
    let c0 = resolve_line(&cnl, geom.ec, sc, false, l.a)
    let c1 = resolve_line(&cnl, geom.ec, ecs, true, l.a)
    let r0 = resolve_line(&rnl, geom.er, sr, false, l.a)
    let r1 = resolve_line(&rnl, geom.er, ers, true, l.a)
    if c0 >= 1i32 && usize(c0) <= geom.nc + 1usize {
        let i0 = usize(c0 - 1i32)
        if i0 < geom.nc { x0 = geom.cpos[i0] } else { x0 = geom.cpos[geom.nc - 1usize] + geom.csz[geom.nc - 1usize] }
    }
    if c1 >= 1i32 && usize(c1) <= geom.nc + 1usize {
        let i1 = usize(c1 - 1i32)
        if i1 < geom.nc { x1 = geom.cpos[i1] } else { x1 = geom.cpos[geom.nc - 1usize] + geom.csz[geom.nc - 1usize] }
    }
    if r0 >= 1i32 && usize(r0) <= geom.nr + 1usize {
        let j0 = usize(r0 - 1i32)
        if j0 < geom.nr { y0 = geom.rpos[j0] } else { y0 = geom.rpos[geom.nr - 1usize] + geom.rsz[geom.nr - 1usize] }
    }
    if r1 >= 1i32 && usize(r1) <= geom.nr + 1usize {
        let j1 = usize(r1 - 1i32)
        if j1 < geom.nr { y1 = geom.rpos[j1] } else { y1 = geom.rpos[geom.nr - 1usize] + geom.rsz[geom.nr - 1usize] }
    }
    // A right-to-left grid lays its columns out from the right edge: the lines named are mirrored across the content box.
    if geom.rtl {
        var nx0 = -ox
        var nx1 = pw - ox
        if c1 >= 1i32 && usize(c1) <= geom.nc + 1usize { nx0 = geom.w - x1 }
        if c0 >= 1i32 && usize(c0) <= geom.nc + 1usize { nx1 = geom.w - x0 }
        x0 = nx0
        x1 = nx1
    }
    ret (true, x0, x1, y0, y1)
}


// --- Multi-column layout (CSS Multicol 3): the content is laid out as one tall column at the column width and its
// lines and blocks are then moved into balanced columns. Boxes are not fragmented: a block that straddles a column break
// stays in the first column it starts in (its lines and children move on), and tables, flex and grid boxes, replaced
// elements move whole. `column-span` and the break properties are not honoured.

type Cols = struct { count: usize, width: f64, gap: f64 }

fn has_columns(s: *const style.Style) -> bool {
    let (cc, has_cc) = extra_text(s, "column-count")
    if has_cc && !str.eq(cc, "auto") { ret true }
    let (cwid, has_cw) = extra_text(s, "column-width")
    ret has_cw && !str.eq(cwid, "auto")
}

// The used column count, width and gap for a content width `cw` (count 1: a plain block).
fn columns_for(l: *Layout, s: *const style.Style, cw: f64) -> Cols {
    var out = Cols { count: 1usize, width: cw, gap: 0.0f64 }
    if cw <= 0.0f64 { ret out }
    let ctx = style.new_context(l.a, l.viewport_width, l.viewport_height)
    var count = 0usize
    var wid = -1.0f64
    let (cc, has_cc) = extra_text(s, "column-count")
    if has_cc {
        let (n, good) = str.parse_i64(cv.trim_ws(cc))
        if good == ok && n >= 1i64 { count = usize(n) }
    }
    let (cwid, has_cw) = extra_text(s, "column-width")
    if has_cw && !str.eq(cwid, "auto") {
        let (len, parsed) = style.parse_len(&ctx, cwid, s.font_size, 0u32)
        if parsed && len.kind == .Px && len.pct == 0.0f64 && len.px > 0.0f64 { wid = len.px }
    }
    if count == 0usize && wid < 0.0f64 { ret out }
    var gap = s.font_size
    let (gv, has_g) = resolve_len(s.column_gap, cw)
    if s.column_gap.kind == .Px && has_g { gap = maxf(0.0f64, gv) }
    var n2 = count
    if wid >= 0.0f64 {
        var fit = usize(maxf(1.0f64, (cw + gap) / (wid + gap)))
        if fit < 1usize { fit = 1usize }
        if n2 == 0usize || fit < n2 { n2 = fit }
    }
    if n2 < 1usize { n2 = 1usize }
    if n2 > 64usize { n2 = 64usize }
    out.count = n2
    out.gap = gap
    out.width = maxf(0.0f64, (cw - gap * f64(n2 - 1usize)) / f64(n2))
    ret out
}

fn column_of(y: f64, colh: f64) -> usize {
    if y <= 0.0f64 || colh <= 0.0f64 { ret 0usize }
    ret usize((y + 0.01f64) / colh)
}

fn unbreakable(l: *const Layout, b: u32) -> bool {
    let bb = &l.boxes.items[usize(b)]
    if bb.inner == .Replaced || bb.inner == .Table || bb.inner == .Flex || bb.inner == .Grid || bb.inner == .Marker || bb.inner == .Text || bb.inner == .Break { ret true }
    let us = st(l, bb.style)
    if us.overflow_x != .Visible || us.overflow_y != .Visible { ret true }
    let (bi, has_bi) = extra_text(us, "break-inside")
    ret has_bi && str.starts_with(str.trim(bi), "avoid")
}

// Where column `k` of a multicol container sits: across a row of `mc_count` columns (a wrapping container, `column-wrap: wrap`) or in one row.
fn col_dx(l: *const Layout, k: usize, stride: f64) -> f64 {
    if l.mc_count > 0usize { ret f64(k % l.mc_count) * stride }
    ret f64(k) * stride
}

fn col_dy(l: *const Layout, k: usize, colh: f64) -> f64 {
    if l.mc_count > 0usize { ret f64(k) * colh - f64(k / l.mc_count) * (colh + l.mc_rgap) }
    ret f64(k) * colh
}

// Records the slices of box `kid` (top at `ky` in the one-column layout, columns of height `colh`) that fall in each column it crosses.
fn record_col_frags(l: *Layout, kid: u32, ky: f64, k0: usize, k1: usize, colh: f64, stride: f64) {
    let kb = &l.boxes.items[usize(kid)]
    kb.cf_first = u32(l.cfrags.len)
    kb.cf_count = 0u32
    var k = k0
    while k <= k1 {
        let s0 = maxf(ky, f64(k) * colh)
        let s1 = minf(ky + kb.h, f64(k + 1usize) * colh)
        if s1 > s0 + 0.01f64 {
            let pushed = list.push[ColFrag](&l.cfrags, ColFrag { dx: col_dx(l, k, stride), dy: s0 - col_dy(l, k, colh) - ky, h: s1 - s0 })
            l.boxes.items[usize(kid)].cf_count += 1u32
        }
        k += 1usize
    }
}

// Moves the lines and blocks of `b` into columns of height `colh` (apply) or only finds the last column used.
// `abs_y` is `b`'s border box top in the one-column layout, measured from the multicol content top.
fn colify(l: *Layout, b: u32, abs_y: f64, colh: f64, stride: f64, apply: bool) -> usize {
    var maxk = 0usize
    let bb0 = &l.boxes.items[usize(b)]
    let top = abs_y + bb0.border[0usize] + bb0.padding[0usize]
    if bb0.line_count > 0u32 {
        let first = usize(bb0.line_first)
        var li = 0usize
        while li < usize(bb0.line_count) {
            let ln = l.lines.items[first + li]
            let k = column_of(top + ln.y, colh)
            if k > maxk { maxk = k }
            if apply && k > 0usize {
                let dx = col_dx(l, k, stride)
                let dy = col_dy(l, k, colh)
                l.lines.items[first + li].x += dx
                l.lines.items[first + li].y -= dy
                l.lines.items[first + li].baseline -= dy
                var fi = 0usize
                while fi < usize(ln.frag_count) {
                    let fr = usize(ln.frag_first) + fi
                    l.frags.items[fr].x += dx
                    l.frags.items[fr].y -= dy
                    if l.frags.items[fr].kind == .Atomic {
                        let ab = usize(l.frags.items[fr].box)
                        l.boxes.items[ab].x += dx
                        l.boxes.items[ab].y -= dy
                    }
                    fi += 1usize
                }
            }
            li += 1usize
        }
    }
    var kid = bb0.first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let nxt = kb.next
        if !kb.inline_level && kb.inner != .Marker && !(kb.positioned_out) {
            let ks = st(l, kb.style)
            if ks.position != .Absolute && ks.position != .Fixed {
                let ky = abs_y + kb.y
                let k0 = column_of(ky, colh)
                let k1 = column_of(ky + kb.h - 0.02f64, colh)
                if k0 == k1 || unbreakable(l, kid) {
                    if k0 > maxk { maxk = k0 }
                    if apply { l.boxes.items[usize(kid)].cf_count = 0u32 }
                    if apply && k0 > 0usize {
                        l.boxes.items[usize(kid)].x += col_dx(l, k0, stride)
                        l.boxes.items[usize(kid)].y -= col_dy(l, k0, colh)
                    }
                } else {
                    if apply { record_col_frags(l, kid, ky, k0, k1, colh, stride) }
                    var m = k1
                    if l.boxes.items[usize(kid)].first != NONE || l.boxes.items[usize(kid)].line_count != 0u32 { m = colify(l, kid, ky, colh, stride, apply) }
                    if m > maxk { maxk = m }
                }
            }
        }
        kid = nxt
    }
    ret maxk
}

// The `column-rule` of a container: (width, colour, drawn). Only the solid look is drawn, whatever the style.
fn column_rule_of(l: *Layout, s: *const style.Style) -> (f64, u32, bool) {
    var width = 3.0f64
    var color = s.color
    var kind = ""
    let ctx = style.new_context(l.a, l.viewport_width, l.viewport_height)
    let (sh, has_sh) = extra_text(s, "column-rule")
    if has_sh {
        let toks = cv.split_top_level_spaces(l.a, cv.trim_ws(sh))
        var i = 0usize
        while i < toks.len {
            let t = cv.lower(l.a, toks[i])
            i += 1usize
            if str.eq(t, "none") || str.eq(t, "hidden") || str.eq(t, "solid") || str.eq(t, "dashed") || str.eq(t, "dotted") || str.eq(t, "double") || str.eq(t, "groove") || str.eq(t, "ridge") || str.eq(t, "inset") || str.eq(t, "outset") {
                kind = t
            } else if str.eq(t, "thin") {
                width = 1.0f64
            } else if str.eq(t, "medium") {
                width = 3.0f64
            } else if str.eq(t, "thick") {
                width = 5.0f64
            } else {
                let (len, good) = style.parse_len(&ctx, t, s.font_size, 0u32)
                if good && len.kind == .Px && len.pct == 0.0f64 {
                    width = len.px
                } else {
                    let (c, cgood) = style.parse_color_value(&ctx, t, s.color)
                    if cgood { color = c }
                }
            }
        }
    }
    let (ks, has_ks) = extra_text(s, "column-rule-style")
    if has_ks { kind = cv.lower(l.a, cv.trim_ws(ks)) }
    let (ws, has_ws) = extra_text(s, "column-rule-width")
    if has_ws {
        let (len2, good2) = style.parse_len(&ctx, ws, s.font_size, 0u32)
        if good2 && len2.kind == .Px { width = len2.px }
    }
    let (cs, has_cs) = extra_text(s, "column-rule-color")
    if has_cs {
        let (c2, cgood2) = style.parse_color_value(&ctx, cs, s.color)
        if cgood2 { color = c2 }
    }
    if kind.len == 0usize || str.eq(kind, "none") || str.eq(kind, "hidden") || width <= 0.0f64 { ret (0.0f64, 0u32, false) }
    ret (width, color, true)
}

// Records the rules between the `used` columns of a run that starts at content-relative `y` and is `colh` high.
fn record_rules(l: *Layout, b: u32, cols: Cols, used: usize, y: f64, colh: f64) {
    let bb = &l.boxes.items[usize(b)]
    let (w, color, on) = column_rule_of(l, st(l, bb.style))
    if !on || used < 2usize || colh <= 0.0f64 { ret }
    let stride = cols.width + cols.gap
    let ox0 = bb.border[3usize] + bb.padding[3usize]
    let oy0 = bb.border[0usize] + bb.padding[0usize]
    var i = 1usize
    while i < used && i < 64usize {
        let x = ox0 + f64(i) * stride - cols.gap / 2.0f64 - w / 2.0f64
        let pushed = list.push[ColRule](&l.rules, ColRule { box: b, x: x, y: oy0 + y, w: w, h: colh, color: color })
        i += 1usize
    }
}

// Whether child box `c` spans every column (`column-span: all`).
fn is_spanner(l: *const Layout, c: u32) -> bool {
    let cb = &l.boxes.items[usize(c)]
    if cb.inline_level || cb.inner == .Marker || cb.inner == .Text || cb.positioned_out { ret false }
    let (v, has) = extra_text(st(l, cb.style), "column-span")
    ret has && str.eq(cv.lower(l.a, cv.trim_ws(v)), "all")
}

// The columns a run of children needs (the highest column index) at column height `colh`; with `apply` the run is moved
// into its columns and down by `shift`. `base` is the content-relative y where the run starts in the single-column layout.
fn colify_run(l: *Layout, first: u32, stop: u32, origin: f64, base: f64, colh: f64, stride: f64, apply: bool, shift: f64) -> usize {
    var maxk = 0usize
    var kid = first
    while kid != stop && kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let nxt = kb.next
        if !kb.inline_level && kb.inner != .Marker && !(kb.positioned_out) {
            let ks = st(l, kb.style)
            if ks.position != .Absolute && ks.position != .Fixed {
                let ky = origin + kb.y - base
                let k0 = column_of(ky, colh)
                let k1 = column_of(ky + kb.h - 0.02f64, colh)
                var k = k0
                if k0 == k1 || unbreakable(l, kid) {
                    if k0 > maxk { maxk = k0 }
                    if apply { l.boxes.items[usize(kid)].cf_count = 0u32 }
                    if apply && k0 > 0usize {
                        l.boxes.items[usize(kid)].x += f64(k0) * stride
                        l.boxes.items[usize(kid)].y -= f64(k0) * colh
                    }
                } else {
                    if apply { record_col_frags(l, kid, ky, k0, k1, colh, stride) }
                    var m = k1
                    if l.boxes.items[usize(kid)].first != NONE || l.boxes.items[usize(kid)].line_count != 0u32 { m = colify(l, kid, ky, colh, stride, apply) }
                    if m > maxk { maxk = m }
                }
                if apply { l.boxes.items[usize(kid)].y += shift }
            }
        }
        kid = nxt
    }
    ret maxk
}

// A container with `column-span: all` children: each run of children between them is balanced into the columns on its own and
// each spanner is laid out across the full width.
fn layout_multicol_spans(l: *Layout, b: u32, cw: f64, cols: Cols, fc: *Flow) -> f64 {
    let (h0, _m) = layout_children(l, b, cols.width, -1.0f64, fc, false)
    let bb = bx(l, b)
    let origin = -(bb.border[0usize] + bb.padding[0usize])
    let ox0 = bb.border[3usize] + bb.padding[3usize]
    let oy0 = bb.border[0usize] + bb.padding[0usize]
    let stride = cols.width + cols.gap
    var cursor = 0.0f64
    var kid = bb.first
    var guard = 0usize
    while kid != NONE && guard < 100000usize {
        guard += 1usize
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker || kb.positioned_out {
            kid = kb.next
            continue
        }
        if is_spanner(l, kid) {
            var acc = no_margin()
            var consumed = Flag { v: false, cleared: false }
            var sub = Flow { base: l.floats.len, ox: ox0, oy: oy0 }
            cursor = layout_block_child(l, b, kid, cw, -1.0f64, &sub, cursor, &acc, &consumed, ox0, oy0)
            cursor += margin_value(acc)
            kid = l.boxes.items[usize(kid)].next
            continue
        }
        // A run: from `kid` to the next spanner.
        let run_first = kid
        var run_stop = kid
        while run_stop != NONE && !is_spanner(l, run_stop) { run_stop = l.boxes.items[usize(run_stop)].next }
        let base = l.boxes.items[usize(run_first)].y - oy0
        var run_end = base
        var q = run_first
        while q != run_stop {
            let qb = &l.boxes.items[usize(q)]
            if !qb.positioned_out && qb.inner != .Marker { run_end = maxf(run_end, qb.y - oy0 + qb.h) }
            q = qb.next
        }
        let total = maxf(0.0f64, run_end - base)
        var colh = total / f64(cols.count)
        if total > 0.0f64 {
            var step = maxf(1.0f64, total / 64.0f64)
            var iter = 0usize
            while iter < 80usize && colify_run(l, run_first, run_stop, origin, base + 0.0f64 - 0.0f64, colh, stride, false, 0.0f64) >= cols.count && colh < total {
                colh += step
                iter += 1usize
            }
            if colh > total { colh = total }
        }
        let shift = cursor - base
        let used_r = colify_run(l, run_first, run_stop, origin, base, colh, stride, true, shift)
        record_rules(l, b, cols, used_r + 1usize, cursor, colh)
        cursor += colh
        kid = run_stop
    }
    ret maxf(cursor, h0 * 0.0f64)
}

fn layout_multicol(l: *Layout, b: u32, cw: f64, ch: f64, cols: Cols, fc: *Flow) -> f64 {
    let (h0, _m) = layout_children(l, b, cols.width, -1.0f64, fc, false)
    let total = maxf(h0, float_bottom(l, fc.base, 2u32, 0.0f64))
    if total <= 0.0f64 { ret 0.0f64 }
    let bb = bx(l, b)
    let origin = -(bb.border[0usize] + bb.padding[0usize])
    let stride = cols.width + cols.gap
    var colh = total / f64(cols.count)
    let s = st(l, bb.style)
    let (fill, has_fill) = extra_text(s, "column-fill")
    let fill_auto = has_fill && str.eq(cv.lower(l.a, cv.trim_ws(fill)), "auto")
    // `column-height` fixes the columns' height; `column-wrap: wrap` starts another row of columns when they run out.
    let (chv, has_chv) = extra_text(s, "column-height")
    var col_fixed = -1.0f64
    if has_chv {
        let ctxh = style.new_context(l.a, l.viewport_width, l.viewport_height)
        let (hlen, hgood) = style.parse_len(&ctxh, cv.trim_ws(chv), s.font_size, 0u32)
        if hgood && hlen.kind == .Px && hlen.pct == 0.0f64 && hlen.px > 0.0f64 { col_fixed = hlen.px }
    }
    let (cwr, has_cwr) = extra_text(s, "column-wrap")
    let col_wrap = col_fixed >= 0.0f64 && has_cwr && str.eq(cv.lower(l.a, cv.trim_ws(cwr)), "wrap")
    if col_fixed >= 0.0f64 && fill_auto {
        colh = col_fixed
    } else if col_fixed >= 0.0f64 && !col_wrap {
        colh = col_fixed
    } else if col_fixed >= 0.0f64 {
        // Wrapping and balancing: as short as the columns of one row allow, no taller than `column-height`.
        var stepw = maxf(1.0f64, total / 64.0f64)
        var iterw = 0usize
        while iterw < 80usize && colify(l, b, origin, colh, stride, false) >= cols.count && colh < col_fixed {
            colh += stepw
            iterw += 1usize
        }
        if colh > col_fixed { colh = col_fixed }
    } else if ch >= 0.0f64 && fill_auto {
        colh = ch
    } else {
        // Balance: the least column height under which everything fits in the available columns.
        var step = maxf(1.0f64, total / 64.0f64)
        var iter = 0usize
        while iter < 80usize && colify(l, b, origin, colh, stride, false) >= cols.count && colh < total {
            colh += step
            iter += 1usize
        }
        if colh > total { colh = total }
        if ch >= 0.0f64 && colh > ch { colh = ch }
    }
    var used_k = colify(l, b, origin, colh, stride, false)
    var result_h = colh
    if col_wrap {
        let rows = used_k / cols.count + 1usize
        let rgap = flex_gap(s.row_gap, maxf(ch, 0.0f64))
        l.mc_count = cols.count
        l.mc_rgap = rgap
        result_h = f64(rows) * colh + f64(rows - 1usize) * rgap
    }
    used_k = colify(l, b, origin, colh, stride, true)
    l.mc_count = 0usize
    record_rules(l, b, cols, used_k + 1usize, 0.0f64, colh)
    ret result_h
}

// --- Positioned boxes.

fn abs_origin(l: *const Layout, b: u32) -> (f64, f64) {
    var x = 0.0f64
    var y = 0.0f64
    var cur = b
    while cur != NONE {
        x += l.boxes.items[usize(cur)].x
        y += l.boxes.items[usize(cur)].y
        cur = l.boxes.items[usize(cur)].parent
    }
    ret (x, y)
}

fn containing_block_of(l: *const Layout, b: u32, fixed: bool) -> u32 {
    if fixed { ret l.root }
    var cur = l.boxes.items[usize(b)].parent
    while cur != NONE && cur != l.root {
        if st(l, l.boxes.items[usize(cur)].style).position != .Static { ret cur }
        cur = l.boxes.items[usize(cur)].parent
    }
    ret l.root
}

fn layout_abs(l: *Layout, b: u32) {
    // A vertical box is solved in its own logical frame (see the orthogonal flows) and mapped back at the end.
    let swap_code = mode_code(bstyle(l, b))
    l.vmode = swap_code
    let s = bstyle(l, b)
    let fixed = s.position == .Fixed
    let cbid = containing_block_of(l, b, fixed)
    let (cbx, cby) = abs_origin(l, cbid)
    let cbb = &l.boxes.items[usize(cbid)]
    var pad_x = cbx + cbb.border[3usize]
    var pad_y = cby + cbb.border[0usize]
    var cb_w = cbb.w - cbb.border[1usize] - cbb.border[3usize]
    var cb_h = cbb.h - cbb.border[0usize] - cbb.border[2usize]
    // An inline containing block that holds blocks starts at the line its first fragment sits on: the line of the inline content just before it.
    if !fixed && cbid != l.root && (bstyle(l, cbid).was_inline || bstyle(l, cbid).display == .Inline) && !cbb.inline_level && cbb.prev != NONE {
        let pvb = &l.boxes.items[usize(cbb.prev)]
        if pvb.line_count > 0u32 && !pvb.inline_level {
            let last = l.lines.items[usize(pvb.line_first) + usize(pvb.line_count) - 1usize]
            let (pvx, pvy) = abs_origin(l, cbb.prev)
            let top_abs = pvy + pvb.border[0usize] + pvb.padding[0usize] + last.y
            if top_abs < cby {
                pad_y -= cby - top_abs
                cb_h += cby - top_abs
            }
        }
    }
    if cbid == l.root {
        pad_x = 0.0f64
        pad_y = 0.0f64
        cb_w = l.viewport_width
        cb_h = l.viewport_height
    }
    var grid_cb = false
    // A child of a grid container is placed against the grid area its `grid-row`/`grid-column` name.
    if cbid != l.root && l.boxes.items[usize(cbid)].inner == .Grid && l.boxes.items[usize(b)].parent == cbid {
        let gpad = &l.boxes.items[usize(cbid)]
        let (gfound, gx0, gx1, gy0, gy1) = grid_abs_area(l, cbid, b, cb_w, cb_h, gpad.padding[3usize], gpad.padding[0usize])
        if gfound {
            let sx = gx0 + gpad.padding[3usize]
            let sy = gy0 + gpad.padding[0usize]
            pad_x += sx
            pad_y += sy
            cb_w = maxf(0.0f64, gx1 - gx0)
            cb_h = maxf(0.0f64, gy1 - gy0)
            grid_cb = true
        }
    }
    let phys_cb_w = cb_w
    let phys_cb_h = cb_h
    if swap_code != 0u8 {
        cb_w = phys_cb_h
        cb_h = phys_cb_w
    }
    let bb = bx(l, b)
    resolve_edges(l, b, cb_w)
    let extras_h = horizontal_extras(bb)
    let extras_v = vertical_extras(bb)
    // The static position, in the containing block's padding box.
    var static_x = bb.x
    var static_y = bb.y
    let pb = &l.boxes.items[usize(bb.parent)]
    let (px, py) = abs_origin(l, bb.parent)
    static_x = px + bb.x - pad_x
    static_y = py + bb.y - pad_y
    // Beside inline content in a block container the box has no flow position yet: use the content edge.
    var rect_w = -1.0f64
    var rect_h = -1.0f64
    var flex_ja: style.Align = .Start
    var flex_aa: style.Align = .Start
    var flex_rect = false
    if bb.aux == 0u32 && bb.x == 0.0f64 && bb.y == 0.0f64 && (pb.inner == .Flow || pb.inner == .Grid || pb.inner == .Flex) && !pb.inline_level {
        static_x += pb.border[3usize] + pb.padding[3usize]
        static_y += pb.border[0usize] + pb.padding[0usize]
        if pb.inner == .Flex && swap_code == 0u8 && bstyle(l, bb.parent).direction != .Rtl && (bstyle(l, bb.parent).flex_direction == .Row || bstyle(l, bb.parent).flex_direction == .Column) {
            // The static position of a child of a flex container is where a lone flex item would sit.
            rect_w = pb.w - pb.border[3usize] - pb.border[1usize] - pb.padding[3usize] - pb.padding[1usize]
            rect_h = pb.h - pb.border[0usize] - pb.border[2usize] - pb.padding[0usize] - pb.padding[2usize]
            let fps = bstyle(l, bb.parent)
            var cross = s.align_self
            if cross == .Auto { cross = fps.align_items }
            if fps.flex_direction == .Row {
                flex_ja = flex_static_align(fps.justify_content)
                flex_aa = flex_static_align(cross)
            } else {
                flex_ja = flex_static_align(cross)
                flex_aa = flex_static_align(fps.justify_content)
            }
            flex_rect = true
        }
        if pb.inner == .Grid && !grid_cb && swap_code == 0u8 {
            rect_w = pb.w - pb.border[3usize] - pb.border[1usize] - pb.padding[3usize] - pb.padding[1usize]
            rect_h = pb.h - pb.border[0usize] - pb.border[2usize] - pb.padding[0usize] - pb.padding[2usize]
        }
    }
    // In a grid area the static position is the area's start corner.
    if grid_cb {
        static_x = 0.0f64
        static_y = 0.0f64
        if swap_code == 0u8 {
            rect_w = cb_w
            rect_h = cb_h
        }
    }
    let phys_sx = static_x
    let phys_sy = static_y
    if swap_code != 0u8 {
        let (sx, sy, sw0, sh0) = remap_rect(0u8, swap_code, phys_cb_w, phys_cb_h, static_x, static_y, 0.0f64, 0.0f64)
        static_x = sx
        static_y = sy
    }
    let has_l = s.inset[3usize].kind != .Auto
    let has_r = s.inset[1usize].kind != .Auto
    let has_t = s.inset[0usize].kind != .Auto
    let has_b = s.inset[2usize].kind != .Auto
    let lv = resolve_or(s.inset[3usize], cb_w, 0.0f64)
    let rv = resolve_or(s.inset[1usize], cb_w, 0.0f64)
    let tv = resolve_or(s.inset[0usize], cb_h, 0.0f64)
    let bv = resolve_or(s.inset[2usize], cb_h, 0.0f64)
    var ml = resolve_or(s.margin[3usize], cb_w, 0.0f64)
    var mr = resolve_or(s.margin[1usize], cb_w, 0.0f64)
    var mt = resolve_or(s.margin[0usize], cb_w, 0.0f64)
    var mb = resolve_or(s.margin[2usize], cb_w, 0.0f64)
    let aml = s.margin[3usize].kind == .Auto
    let amr = s.margin[1usize].kind == .Auto
    // Width.
    var cw = 0.0f64
    var w_auto = true
    let (wv, has_wv) = resolve_len(s.width, cb_w)
    if bb.inner == .Replaced {
        let (rw, _rh) = used_replaced_size(l, b, cb_w, cb_h)
        cw = rw
        w_auto = false
    } else if s.width.kind == .Px && has_wv {
        cw = to_content_w(l, b, wv)
        w_auto = false
    }
    var ratio_w = false
    if w_auto && !(has_l && has_r) && s.height.kind == .Px {
        let (hv0, has_hv0) = resolve_len(s.height, cb_h)
        if has_hv0 {
            let (rw0, has_rw0) = ratio_width(l, b, to_content_h(l, b, hv0))
            if has_rw0 {
                cw = rw0
                ratio_w = true
            }
        }
    }
    if !ratio_w && w_auto && !(has_l && has_r) && has_t && has_b && s.height.kind != .Px && bb.inner != .Replaced {
        // `top` and `bottom` fix the height: a box with a preferred ratio takes its width from it.
        let h_from_insets = maxf(0.0f64, cb_h - tv - bv - mt - mb - extras_v)
        let (rw1, has_rw1) = ratio_width(l, b, to_content_h(l, b, h_from_insets + extras_v) )
        if has_rw1 {
            cw = rw1
            ratio_w = true
        }
    }
    if ratio_w {
        // the width came from the ratio
    } else if w_auto {
        if has_l && has_r {
            cw = cb_w - lv - rv - ml - mr - extras_h
        } else {
            let (mn, mx) = content_widths(l, b)
            var room = cb_w - ml - mr - extras_h - static_x
            if has_l { room = cb_w - lv - ml - mr - extras_h }
            if has_r { room = cb_w - rv - ml - mr - extras_h }
            if !has_l && !has_r && flex_rect && flex_ja == .Center {
                // A centred box may use twice the distance from the middle of its static rectangle to the nearer edge.
                let mid = static_x + rect_w / 2.0f64
                room = 2.0f64 * minf(mid, cb_w - mid) - ml - mr - extras_h
            }
            if s.width.kind == .MinContent { cw = mn } else if s.width.kind == .MaxContent { cw = mx } else { cw = minf(maxf(mn, room), mx) }
        }
    }
    cw = maxf(0.0f64, clamp_width(l, b, cw, cb_w))
    if has_l && has_r && !w_auto {
        let rest = cb_w - lv - rv - cw - extras_h - ml - mr
        if aml && amr {
            ml = maxf(0.0f64, rest / 2.0f64)
            mr = maxf(0.0f64, rest / 2.0f64)
        } else if aml {
            ml = maxf(0.0f64, rest)
        } else if amr {
            mr = maxf(0.0f64, rest)
        }
    }
    bb.margin[3usize] = ml
    bb.margin[1usize] = mr
    bb.w = cw + extras_h
    var left = static_x
    if has_l {
        left = lv
    } else if has_r {
        left = cb_w - rv - bb.w - mr - ml
    } else if rect_w >= 0.0f64 {
        var ja = s.justify_self
        if flex_rect { ja = flex_ja }
        if ja == .Auto && !flex_rect { ja = bstyle(l, bb.parent).justify_items }
        let ja_room = rect_w - bb.w - ml - mr
        var ja_off = static_align_offset(ja, ja_room, true)
        // In a right-to-left container the start edge is the right one; `left` and `right` stay physical.
        if bstyle(l, bb.parent).direction == .Rtl && swap_code == 0u8 && ja != .Left && ja != .Right { ja_off = ja_room - ja_off }
        left += ja_off
    } else if bb.aux == 2u32 && (bb.inline_level || bstyle(l, b).was_inline) && !grid_cb && bstyle(l, bb.parent).direction == .Rtl && mode_code(bstyle(l, bb.parent)) == swap_code && (pb.inner == .Flow || pb.inner == .FlowRoot) {
        // Inline-level in a right-to-left line: the static position is where the content before it starts, and the box ends there.
        left = static_x - bb.w - ml - mr
    } else if swap_code == 0u8 && !grid_cb && (bb.aux == 0u32 || bb.aux == 3u32) && bstyle(l, bb.parent).direction == .Rtl && (pb.inner == .Flow || pb.inner == .FlowRoot) && !bb.inline_level {
        // In a right-to-left container the static position is the right edge: the box ends there.
        let room = pb.w - pb.border[1usize] - pb.border[3usize] - pb.padding[1usize] - pb.padding[3usize]
        left = static_x + room - bb.w - ml - mr
    }
    // Height.
    var spec_h = -1.0f64
    let (hv, has_hv) = resolve_len(s.height, cb_h)
    if bb.inner == .Replaced {
        let (_rw2, rh) = used_replaced_size(l, b, cb_w, cb_h)
        spec_h = rh
    } else if s.height.kind == .Px && has_hv {
        spec_h = to_content_h(l, b, hv)
    } else if has_t && has_b && !has_box_ratio(l, b) {
        // (a box with a preferred ratio takes its height from its width instead of stretching)
        spec_h = maxf(0.0f64, cb_h - tv - bv - mt - mb - extras_v)
    }
    var ratio_h_abs = -1.0f64
    if spec_h < 0.0f64 && bb.inner != .Replaced {
        let (rh0, has_rh0) = ratio_height(l, b, cw)
        if has_rh0 {
            ratio_h_abs = rh0
            spec_h = rh0
        }
    }
    var content_h = 0.0f64
    if bb.inner != .Replaced {
        content_h = layout_in_new_bfc(l, b, cw, spec_h)
    }
    var h = content_h
    if spec_h >= 0.0f64 { h = spec_h }
    if ratio_h_abs >= 0.0f64 && s.overflow_x == .Visible && s.overflow_y == .Visible { h = maxf(ratio_h_abs, content_h) }
    h = maxf(0.0f64, clamp_height_auto(l, b, h, cb_h, content_h))
    let bbh = bx(l, b)
    bbh.h = h + extras_v
    set_baseline(l, b)
    if has_t && has_b && s.height.kind != .Px && !(bbh.inner == .Replaced) {
        let restv = cb_h - tv - bv - bbh.h - mt - mb
        if s.margin[0usize].kind == .Auto && s.margin[2usize].kind == .Auto {
            mt = maxf(0.0f64, restv / 2.0f64)
            mb = maxf(0.0f64, restv / 2.0f64)
        }
    }
    bbh.margin[0usize] = mt
    bbh.margin[2usize] = mb
    if swap_code != 0u8 && mode_code(bstyle(l, bb.parent)) == 0u8 && bstyle(l, bb.parent).direction != .Rtl {
        // A mirrored frame inside a horizontal parent needs the box's size to place its static position: re-map the static point as the box's rectangle.
        let (fx, fy, fw0, fh0) = remap_rect(0u8, swap_code, phys_cb_w, phys_cb_h, phys_sx, phys_sy, bbh.h, bbh.w)
        static_y = fy
        if !has_l && !has_r && rect_w < 0.0f64 { left = fx }
    }
    var top = static_y
    if has_t {
        top = tv
    } else if has_b {
        top = cb_h - bv - bbh.h - mb - mt
    } else if rect_h >= 0.0f64 {
        var aa = s.align_self
        if flex_rect { aa = flex_aa }
        if aa == .Auto && !flex_rect { aa = bstyle(l, bbh.parent).align_items }
        top += static_align_offset(aa, rect_h - bbh.h - mt - mb, false)
    }
    // To the parent's border box.
    var rx = left + ml
    var ry = top + mt
    if swap_code != 0u8 {
        l.vmode = 0u8
        let tw = bbh.w
        let th = bbh.h
        let (nx, ny, nw, nh) = remap_rect(swap_code, 0u8, cb_w, cb_h, rx, ry, tw, th)
        remap_children(l, b, tw, th, swap_code, 0u8)
        let b9 = bx(l, b)
        b9.border = remap_edges(swap_code, 0u8, b9.border)
        b9.padding = remap_edges(swap_code, 0u8, b9.padding)
        b9.margin = remap_edges(swap_code, 0u8, b9.margin)
        b9.w = nw
        b9.h = nh
        rx = nx
        ry = ny
    }
    let bf = bx(l, b)
    let (qx, qy) = abs_origin(l, bf.parent)
    bf.x = pad_x + rx - qx
    bf.y = pad_y + ry - qy
    bf.aux = 4u32
}

// How far an absolutely positioned box moves inside its static-position rectangle for alignment `a`, `room` being the free space.
fn static_align_offset(a: style.Align, room: f64, inline_axis: bool) -> f64 {
    if a == .Center { ret room / 2.0f64 }
    if a == .End || a == .FlexEnd || a == .SelfEnd || a == .LastBaseline { ret room }
    if a == .Right && inline_axis { ret room }
    ret 0.0f64
}

fn positioned_pass(l: *Layout, b: u32) {
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        let nxt = l.boxes.items[usize(kid)].next
        let ks = st(l, l.boxes.items[usize(kid)].style)
        if (ks.position == .Absolute || ks.position == .Fixed) && l.boxes.items[usize(kid)].inner != .Text {
            layout_abs(l, kid)
        }
        positioned_pass(l, kid)
        kid = nxt
    }
}

fn extent_pass(l: *Layout, b: u32, ox: f64, oy: f64) {
    let bb = &l.boxes.items[usize(b)]
    let x = ox + bb.x
    let y = oy + bb.y
    if bb.inner != .Text {
        l.doc_width = maxf(l.doc_width, x + bb.w + bb.margin[1usize])
        l.doc_height = maxf(l.doc_height, y + bb.h + bb.margin[2usize])
    }
    var kid = bb.first
    while kid != NONE {
        extent_pass(l, kid, x, y)
        kid = l.boxes.items[usize(kid)].next
    }
}

// The layout of a styled tree for a viewport. `styles[i]` is the style of node `i`.
// --- Orthogonal flows (writing-mode: vertical-rl / vertical-lr).
//
// A box whose writing mode runs perpendicular to its container's is laid out in its own logical frame: `l.vmode` names the
// frame (1: vertical-rl, 2: vertical-lr, 0: horizontal), `st` then returns styles transposed into it (width and height,
// margins, padding, borders and insets swap, so the horizontal layout code reads the block axis as "vertical" and the inline
// axis as "horizontal"). When the subtree is done its geometry is mapped back into the frame of the container by `remap_children`.

fn mode_code(s: *const style.Style) -> u8 {
    if s.writing_mode == .VerticalRl || s.writing_mode == .SidewaysRl { ret 1u8 }
    if s.writing_mode == .VerticalLr || s.writing_mode == .SidewaysLr { ret 2u8 }
    ret 0u8
}

// The physical side that logical side `i` (top, right, bottom, left) of frame `code` reads.
fn frame_side(code: u8, i: usize) -> usize {
    if code == 1u8 {
        if i == 0usize { ret 1usize }
        if i == 1usize { ret 2usize }
        if i == 2usize { ret 3usize }
        ret 0usize
    }
    if i == 0usize { ret 3usize }
    if i == 1usize { ret 2usize }
    if i == 2usize { ret 1usize }
    ret 0usize
}

fn transpose_style(s: style.Style, code: u8) -> style.Style {
    var t = s
    t.width = s.height
    t.height = s.width
    t.min_width = s.min_height
    t.min_height = s.min_width
    t.max_width = s.max_height
    t.max_height = s.max_width
    t.overflow_x = s.overflow_y
    t.overflow_y = s.overflow_x
    var i = 0usize
    while i < 4usize {
        let src = frame_side(code, i)
        t.inset[i] = s.inset[src]
        t.margin[i] = s.margin[src]
        t.padding[i] = s.padding[src]
        t.border_width[i] = s.border_width[src]
        t.border_style[i] = s.border_style[src]
        t.border_color[i] = s.border_color[src]
        t.border_current[i] = s.border_current[src]
        i += 1usize
    }
    ret t
}

fn style_value(l: *const Layout, k: usize) -> style.Style {
    if k < l.styles.len { ret l.styles[k] }
    ret l.anon.items[k - l.styles.len]
}

fn build_transposed(l: *Layout) {
    var any1 = false
    var any2 = false
    var i = 0usize
    let total = l.styles.len + l.anon.len
    while i < total {
        let sv = style_value(l, i)
        let code = mode_code(&sv)
        if code == 1u8 { any1 = true }
        if code == 2u8 { any2 = true }
        i += 1usize
    }
    if any1 {
        let (arr, e) = mem.alloc[style.Style](l.a, total)
        if e == ok {
            var k = 0usize
            while k < total {
                arr[k] = transpose_style(style_value(l, k), 1u8)
                k += 1usize
            }
            l.tr1 = arr
        }
    }
    if any2 {
        let (arr2, e2) = mem.alloc[style.Style](l.a, total)
        if e2 == ok {
            var k2 = 0usize
            while k2 < total {
                arr2[k2] = transpose_style(style_value(l, k2), 2u8)
                k2 += 1usize
            }
            l.tr2 = arr2
        }
    }
}

// Whether `b` runs perpendicular to the current frame.
fn is_orthogonal(l: *const Layout, b: u32) -> bool {
    if l.tr1.len == 0usize && l.tr2.len == 0usize { ret false }
    let bb = &l.boxes.items[usize(b)]
    if bb.inner == .Text || bb.inner == .Break || bb.inner == .Marker || bb.inline_level { ret false }
    let code = mode_code(st(l, bb.style))
    ret (code != 0u8) != (l.vmode != 0u8)
}

// Maps a rectangle between frames (`from` -> `to`, one of them 0) given the size (`sw`, `sh`) of its container in the source frame.
fn remap_rect(from: u8, to: u8, sw: f64, sh: f64, x: f64, y: f64, w: f64, h: f64) -> (f64, f64, f64, f64) {
    if to == 0u8 {
        if from == 1u8 { ret (sh - (y + h), x, h, w) }
        ret (y, x, h, w)
    }
    if to == 1u8 { ret (y, sw - x - w, h, w) }
    ret (y, x, h, w)
}

fn remap_edges(from: u8, to: u8, e: [4]f64) -> [4]f64 {
    var out: [4]f64 = zero
    var i = 0usize
    if to == 0u8 {
        while i < 4usize {
            out[frame_side(from, i)] = e[i]
            i += 1usize
        }
    } else {
        while i < 4usize {
            out[i] = e[frame_side(to, i)]
            i += 1usize
        }
    }
    ret out
}

// Maps the geometry of everything below `p` (whose border box is `sw` x `sh` in the `from` frame) into the `to` frame.
fn remap_children(l: *Layout, p: u32, sw: f64, sh: f64, from: u8, to: u8) {
    let pb = &l.boxes.items[usize(p)]
    // Lines are placed in the content box.
    let cw_src = sw - (pb.border[1usize] + pb.border[3usize] + pb.padding[1usize] + pb.padding[3usize])
    let ch_src = sh - (pb.border[0usize] + pb.border[2usize] + pb.padding[0usize] + pb.padding[2usize])
    var li = 0usize
    while li < usize(pb.line_count) {
        let ln = &l.lines.items[usize(pb.line_first) + li]
        let (lx, ly, lw, lh) = remap_rect(from, to, cw_src, ch_src, ln.x, ln.y, ln.w, ln.h)
        var fi = 0usize
        while fi < usize(ln.frag_count) {
            let fr = &l.frags.items[usize(ln.frag_first) + fi]
            let (fx, fy, fw, fh) = remap_rect(from, to, cw_src, ch_src, fr.x, fr.y, fr.w, fr.h)
            fr.x = fx
            fr.y = fy
            fr.w = fw
            fr.h = fh
            fi += 1usize
        }
        ln.x = lx
        ln.y = ly
        ln.w = lw
        ln.h = lh
        li += 1usize
    }
    var kid = pb.first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        let kw = kb.w
        let kh = kb.h
        let (nx, ny, nw, nh) = remap_rect(from, to, sw, sh, kb.x, kb.y, kw, kh)
        remap_children(l, kid, kw, kh, from, to)
        let kb2 = &l.boxes.items[usize(kid)]
        kb2.x = nx
        kb2.y = ny
        kb2.w = nw
        kb2.h = nh
        kb2.margin = remap_edges(from, to, kb2.margin)
        kb2.border = remap_edges(from, to, kb2.border)
        kb2.padding = remap_edges(from, to, kb2.padding)
        let ow = kb2.overflow_w
        kb2.overflow_w = kb2.overflow_h
        kb2.overflow_h = ow
        kid = kb2.next
    }
}

// Forgets the cached intrinsic widths of `b` and everything below it (they depend on the frame they were measured in).
fn clear_widths(l: *Layout, b: u32) {
    l.boxes.items[usize(b)].has_c = false
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        clear_widths(l, kid)
        kid = l.boxes.items[usize(kid)].next
    }
}

// Lays out block `c`, which is orthogonal to the current frame, as a formatting context root. Its edges (resolved in the
// frame of the container) are kept; the result is its border box in that frame with every descendant mapped into it.
// `pbase` is the percentage base and `pch` the definite height of the container (negative: none).
// `fi` and `fb` (negative: none) force the inline size (physical height) and block size (physical width) of the content box.
// The content block size of `b` from its own `height`, else its `max-height`, raised by `min-height`; negative when it has neither.
fn fixed_block_size(l: *const Layout, b: u32) -> f64 {
    let s = bstyle(l, b)
    var h = -1.0f64
    let (hv, has_h) = resolve_len(s.height, -1.0f64)
    let (mv, has_m) = resolve_len(s.max_height, -1.0f64)
    if s.height.kind == .Px && has_h {
        h = to_content_h(l, b, hv)
    } else if s.max_height.kind == .Px && has_m {
        h = to_content_h(l, b, mv)
    }
    if h < 0.0f64 { ret h }
    ret clamp_height(l, b, h, -1.0f64)
}

// The block space an orthogonal flow sizes its inline axis against (Writing Modes 3 7.3, WPT available-size-*): the containing
// block's block size, else its max size, else that of the nearest scroll container ancestor; the last two no larger than the ICB.
fn orthogonal_room(l: *const Layout, c: u32, pch: f64) -> f64 {
    let p = l.boxes.items[usize(c)].parent
    if pch >= 0.0f64 {
        if p == NONE { ret pch }
        ret clamp_height(l, p, pch, -1.0f64)
    }
    var icb = l.viewport_height
    if l.vmode != 0u8 { icb = l.viewport_width }
    if p == NONE { ret icb }
    var room = fixed_block_size(l, p)
    if room < 0.0f64 {
        var a = p
        while a != NONE && !is_scroll_container(bstyle(l, a)) { a = l.boxes.items[usize(a)].parent }
        if a != NONE { room = fixed_block_size(l, a) }
    }
    if room < 0.0f64 { ret icb }
    ret minf(room, icb)
}

fn layout_orthogonal(l: *Layout, c: u32, pbase: f64, pch: f64, fi: f64, fb: f64) {
    let old = l.vmode
    let code = mode_code(bstyle(l, c))
    let bb = bx(l, c)
    let pm = bb.margin
    let room = orthogonal_room(l, c, pch)
    // The edges along the container's block axis are the box's inline edges.
    let outer_i = pm[0usize] + pm[2usize] + bb.border[0usize] + bb.border[2usize] + bb.padding[0usize] + bb.padding[2usize]
    l.vmode = code
    resolve_edges(l, c, pbase)
    let s = bstyle(l, c)
    let bb2 = bx(l, c)
    let ext_i = horizontal_extras(bb2)
    let ext_b = vertical_extras(bb2)
    var inline = 0.0f64
    let (wv, has_w) = resolve_len(s.width, pbase)
    if fi >= 0.0f64 {
        inline = fi
    } else if s.width.kind == .Px && has_w {
        inline = to_content_w(l, c, wv)
    } else {
        // Automatic inline size of an orthogonal flow: shrink-to-fit against the container's block space (Writing Modes 3 7.3).
        clear_widths(l, c)
        let (mn, mx) = content_widths(l, c)
        inline = minf(mx, maxf(mn, maxf(0.0f64, room - outer_i - ext_i)))
    }
    inline = maxf(0.0f64, clamp_width(l, c, inline, pbase))
    var spec_b = -1.0f64
    if fb >= 0.0f64 {
        spec_b = fb
    } else if s.height.kind == .Px && s.height.pct == 0.0f64 {
        spec_b = to_content_h(l, c, s.height.px)
    }
    let auto_b = layout_in_new_bfc(l, c, inline, spec_b)
    var block = auto_b
    if spec_b >= 0.0f64 { block = spec_b }
    block = maxf(0.0f64, clamp_height_auto(l, c, block, -1.0f64, auto_b))
    let tw = inline + ext_i
    let th = block + ext_b
    l.vmode = old
    clear_widths(l, c)
    remap_children(l, c, tw, th, code, old)
    let bb3 = bx(l, c)
    bb3.border = remap_edges(code, old, bb3.border)
    bb3.padding = remap_edges(code, old, bb3.padding)
    bb3.margin = pm
    bb3.w = th
    bb3.h = tw
    bb3.overflow_w = th
    bb3.overflow_h = tw
    bb3.has_baseline = false
}

// Flex and grid items are laid out and painted in `order` order (stable): reorder the sibling lists once, after generation.
fn order_items(l: *Layout, b: u32) {
    let inner = l.boxes.items[usize(b)].inner
    if inner == .Flex || inner == .Grid {
        var any = false
        var k = l.boxes.items[usize(b)].first
        while k != NONE {
            if st(l, l.boxes.items[usize(k)].style).order != 0i64 { any = true }
            k = l.boxes.items[usize(k)].next
        }
        if any {
            // Stable insertion sort into a new chain.
            var head = NONE
            var tail = NONE
            var cur = l.boxes.items[usize(b)].first
            while cur != NONE {
                let nxt = l.boxes.items[usize(cur)].next
                let ord = st(l, l.boxes.items[usize(cur)].style).order
                // Find the last box in the chain whose order is <= ord.
                var at = tail
                while at != NONE && st(l, l.boxes.items[usize(at)].style).order > ord { at = l.boxes.items[usize(at)].prev }
                if at == NONE {
                    l.boxes.items[usize(cur)].prev = NONE
                    l.boxes.items[usize(cur)].next = head
                    if head != NONE { l.boxes.items[usize(head)].prev = cur }
                    head = cur
                    if tail == NONE { tail = cur }
                } else {
                    let after = l.boxes.items[usize(at)].next
                    l.boxes.items[usize(cur)].prev = at
                    l.boxes.items[usize(cur)].next = after
                    l.boxes.items[usize(at)].next = cur
                    if after != NONE { l.boxes.items[usize(after)].prev = cur } else { tail = cur }
                }
                cur = nxt
            }
            l.boxes.items[usize(b)].first = head
            l.boxes.items[usize(b)].last = tail
        }
    }
    var kid = l.boxes.items[usize(b)].first
    while kid != NONE {
        order_items(l, kid)
        kid = l.boxes.items[usize(kid)].next
    }
}

fn layout_document(a: *mem.Arena, d: *const dom.Dom, styles: []const style.Style, measure: Measure, viewport_width: f64, viewport_height: f64) -> (Layout, err) {
    var cap = d.used * 2usize + 64usize
    let (boxes, e1) = list.init[Box](a, cap)
    let (lines, e2) = list.init[Line](a, 64usize)
    let (frags, e3) = list.init[Frag](a, 256usize)
    let (anon, e4) = list.init[style.Style](a, 64usize)
    let (floats, e5) = list.init[FloatRec](a, 16usize)
    let (tables, e6) = list.init[TableData](a, 8usize)
    let (counters, e7) = list.init[CounterInst](a, 16usize)
    let (grids, e8) = list.init[GridGeom](a, 4usize)
    let (rules_made, e9r) = list.init[ColRule](a, 8usize)
    let (cfrags_made, e9c) = list.init[ColFrag](a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9r != ok { ret (zero, TooBig) }
    var l = Layout { a: a, d: d, styles: styles, measure: measure, boxes: boxes, lines: lines, frags: frags, anon: anon, root: NONE, viewport_width: viewport_width, viewport_height: viewport_height, doc_width: 0.0f64, doc_height: 0.0f64, floats: floats, tables: tables, counters: counters, quote_depth: 0i64, gen_depth: 0usize, orth_fb: -1.0f64, vmode: 0u8, tr1: zero, tr2: zero, grids: grids, rules: rules_made, sub_c: zero, sub_r: zero, sub_gc: 0.0f64, sub_gr: 0.0f64, sub_has_c: false, sub_has_r: false, mc_count: 0usize, mc_rgap: 0.0f64, cfrags: cfrags_made }
    let root_el = dom.first_element_child(d, d.root)
    if root_el == html.NONE { ret (l, ok) }
    let vp = new_box(&l, .Flow, false, true, NONE, anon_style(&l, root_el, .Block))
    l.root = vp
    gen_node(&l, root_el, vp, d.root)
    fix_anonymous(&l, vp)
    order_items(&l, vp)
    build_transposed(&l)
    let vb = bx(&l, vp)
    vb.w = viewport_width
    vb.h = viewport_height
    var fc = Flow { base: 0usize, ox: 0.0f64, oy: 0.0f64 }
    let (h, _m) = layout_children(&l, vp, viewport_width, viewport_height, &fc, false)
    let vb2 = bx(&l, vp)
    vb2.h = maxf(viewport_height, h)
    // A page whose principal flow is vertical-rl starts at the right edge of the viewport.
    var rk = vb2.first
    while rk != NONE {
        let rb = bx(&l, rk)
        if rb.inner != .Text && rb.inner != .Marker && mode_code(bstyle(&l, rk)) == 1u8 {
            rb.x = maxf(0.0f64, viewport_width - rb.w - rb.margin[1usize])
        }
        rk = bx(&l, rk).next
    }
    positioned_pass(&l, vp)
    extent_pass(&l, vp, 0.0f64, 0.0f64)
    l.doc_width = maxf(l.doc_width, viewport_width)
    l.doc_height = maxf(l.doc_height, viewport_height)
    ret (l, ok)
}

error TooBig

// The alignment of a lone flex item's static position along an axis: the three centring values centre, the end values end.
fn flex_static_align(a: style.Align) -> style.Align {
    if a == .Center || a == .SpaceAround || a == .SpaceEvenly { ret .Center }
    if a == .End || a == .FlexEnd { ret .End }
    ret .Start
}
