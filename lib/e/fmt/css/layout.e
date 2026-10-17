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
    coll: bool, cbd: [4]f64
}

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
    vmode: u8, tr1: []style.Style, tr2: []style.Style, grids: list.List[GridGeom]
}

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

// Applies `counter-reset`, `counter-increment` and `counter-set` (in that order) of an element.
fn apply_counter_props(l: *Layout, s: *const style.Style) {
    let (reset, has_reset) = extra_text(s, "counter-reset")
    let (incr, has_incr) = extra_text(s, "counter-increment")
    let (set, has_set) = extra_text(s, "counter-set")
    if has_reset && !str.eq(cv.lower(l.a, cv.trim_ws(reset)), "none") { counter_pairs(l, reset, 0u8, 0i64) }
    if has_incr && !str.eq(cv.lower(l.a, cv.trim_ws(incr)), "none") { counter_pairs(l, incr, 1u8, 1i64) }
    if has_set && !str.eq(cv.lower(l.a, cv.trim_ws(set)), "none") { counter_pairs(l, set, 2u8, 0i64) }
}

// `name [integer]` pairs; op 0 reset, 1 increment, 2 set.
fn counter_pairs(l: *Layout, text: str, op: u8, default_value: i64) {
    let toks = cv.split_top_level_spaces(l.a, text)
    var i = 0usize
    while i < toks.len {
        let name = toks[i]
        i += 1usize
        var v = default_value
        if i < toks.len {
            let (n, good) = str.parse_i64(toks[i])
            if good == ok {
                v = n
                i += 1usize
            }
        }
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
    apply_counter_props(l, ps)
    let (text, has) = eval_content(l, ps, node)
    if !has { ret }
    let id = push_style(l, ps)
    let pd = l.anon.items[usize(id) - l.styles.len].display
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
    ret d == .Block || d == .Flex || d == .Grid || d == .Table || d == .ListItem || d == .FlowRoot
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
    apply_counter_props(l, s)
    if s.display == .Contents {
        // The element has no box of its own, but its ::before and ::after still generate boxes in its parent.
        gen_pseudo(l, node, parent_box, 0usize)
        gen_children(l, node, parent_box)
        gen_pseudo(l, node, parent_box, 1usize)
        ret
    }
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
    gen_pseudo(l, node, b, 0usize)
    gen_children(l, node, b)
    gen_pseudo(l, node, b, 1usize)
    let fl = s.pseudo[3usize]
    if mem.address_of(fl) != 0usize && !inline_level { apply_first_letter(l, b, fl) }
    fix_anonymous(l, b)
}

// The value of a list item's counter: `value`, else the previous sibling item's plus one, from `start` (or 1).
fn list_ordinal(l: *Layout, node: u32) -> i64 {
    let (value, has_value) = dom.get_attribute(l.d, node, "value")
    if has_value {
        let (n, good) = str.parse_i64(value)
        if good == ok { ret n }
    }
    let parent = l.d.nodes[usize(node)].parent
    var reversed = false
    var start = 1i64
    var count = 0i64
    if parent != html.NONE {
        if dom.is_html_named(l.d, parent, "ol") {
            let (rev, has_rev) = dom.get_attribute(l.d, parent, "reversed")
            reversed = has_rev
            let (sv, has_start) = dom.get_attribute(l.d, parent, "start")
            if has_start {
                let (n, good) = str.parse_i64(sv)
                if good == ok { start = n }
            }
        }
        var kid = l.d.nodes[usize(parent)].first_child
        while kid != html.NONE && kid != node {
            if l.d.nodes[usize(kid)].kind == .Element && l.styles[usize(kid)].display == .ListItem { count += 1i64 }
            kid = l.d.nodes[usize(kid)].next_sibling
        }
        if reversed {
            var total = 0i64
            var k2 = l.d.nodes[usize(parent)].first_child
            while k2 != html.NONE {
                if l.d.nodes[usize(k2)].kind == .Element && l.styles[usize(k2)].display == .ListItem { total += 1i64 }
                k2 = l.d.nodes[usize(k2)].next_sibling
            }
            var first = total
            if has_start_attr(l, parent) { first = start }
            ret first - count
        }
    }
    ret start + count
}

fn has_start_attr(l: *Layout, parent: u32) -> bool {
    let (_, has) = dom.get_attribute(l.d, parent, "start")
    ret has
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
        if !(kb.inner == .Text && is_ws_only(kb.text) && collapses(l, k)) { all_ws = false }
        if k == last { break }
        k = kb.next
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

type Flag = struct { v: bool }

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

fn is_bfc_root(l: *const Layout, b: u32) -> bool {
    let bb = &l.boxes.items[usize(b)]
    if bb.parent == NONE { ret true }
    if l.boxes.items[usize(bb.parent)].parent == NONE { ret true }
    let s = st(l, bb.style)
    if bb.inner == .FlowRoot || bb.inner == .Flex || bb.inner == .Grid || bb.inner == .Table || bb.inner == .Cell || bb.inner == .Replaced { ret true }
    if s.floating != .None || s.position == .Absolute || s.position == .Fixed { ret true }
    if s.overflow_x != .Visible || s.overflow_y != .Visible { ret true }
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
    ret (num / den, true)
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
    if s.text_transform == .None || s.text_transform == .FullWidth { ret text }
    let (out, e) = mem.alloc[u8](l.a, text.len)
    if e != ok { ret text }
    mem.copy[u8](out, text)
    var i = 0usize
    var word_start = true
    while i < out.len {
        let c = out[i]
        if s.text_transform == .Uppercase && c >= 97u8 && c <= 122u8 { out[i] = c - 32u8 }
        if s.text_transform == .Lowercase && c >= 65u8 && c <= 90u8 { out[i] = c + 32u8 }
        if s.text_transform == .Capitalize {
            if word_start && c >= 97u8 && c <= 122u8 { out[i] = c - 32u8 }
            word_start = is_space_byte(c) || c == 45u8 || c == 40u8
        }
        i += 1usize
    }
    ret out
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
    ret (fm.ascent + half, lh - (fm.ascent + half))
}

type Flow = struct { base: usize, ox: f64, oy: f64 }

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
    var seg = 0usize
    var k = 1usize
    while k <= n {
        // break-all adds a break between any two letters, never before a space.
        let all_here = s.word_break == .BreakAll && !(k < n && scal[k] == 32u32)
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
                while content_end > 0usize && seg_text[content_end - 1usize] == 32u8 { content_end -= 1usize }
            }
            let content = seg_text[..content_end]
            let trail_text = seg_text[content_end..]
            let w = text_advance(l, s, content)
            let tr = text_advance(l, s, trail_text)
            if seg_text.len > 0usize {
                // The break after this piece is a soft wrap opportunity when the style wraps.
                var soft = wrap && (k < n || true) && (opp[k] != 0u8 || all_here || bspace)
                // The end of a text run is a break opportunity only after a space (atomics mark the piece before them).
                if k == n { soft = wrap && (trail_text.len > 0usize || seg_text.len == 0usize) }
                push_piece(bd, Piece { kind: .Text, box: b, text: seg_text, w: w, trail: tr, soft: soft, ink: content_end > 0usize || preserve, start: offs[seg], clen: content_end })
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
    if s.vertical_align == .TextTop { ret a - pfm.ascent }
    if s.vertical_align == .TextBottom { ret pfm.descent - d }
    if s.vertical_align == .Middle { ret -pfm.x_height / 2.0f64 + (a - d) / 2.0f64 }
    // A length or percentage.
    let l2 = s.vertical_align_length
    ret -(l2.px + l2.pct * lh)
}

fn line_align_x(s: *const style.Style, last_line: bool, avail: f64, width: f64, left: f64) -> f64 {
    var align = s.text_align
    if align == .MatchParent { align = .Start }
    let rtl = s.direction == .Rtl
    if align == .Start { if rtl { align = .Right } else { align = .Left } }
    if align == .End { if rtl { align = .Left } else { align = .Right } }
    if align == .Justify && last_line { if rtl { align = .Right } else { align = .Left } }
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
}


// --- Inline layout: lines.

type Ifc = struct {
    l: *Layout, bd: Builder, cont: u32, cs: *const style.Style, cbw: f64, fc: *Flow,
    y: f64, first_line: bool, open: [64]u32, open_count: usize, sa: f64, sd: f64,
    own: list.List[u32]
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
            // A block-level box's static position is the container's content edge; an inline-level one follows the line.
            if l.boxes.items[usize(p.box)].inline_level {
                l.boxes.items[usize(p.box)].x = out.line_x + pos
            } else {
                l.boxes.items[usize(p.box)].x = 0.0f64
            }
            l.boxes.items[usize(p.box)].y = x.y
            j += 1usize
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
        pos += needed
        if p.soft { last_soft = u32(j) }
        pos += p.trail
        j += 1usize
        out.end = j
    }
    ret out
}

fn flush_text_frag(l: *Layout, bxid: u32, x: f64, text: str, w: f64, shift: f64, baseline: f64) {
    if bxid == NONE || text.len == 0usize { ret }
    let fm = l.measure.metrics(l.measure.ctx, bstyle(l, bxid))
    let pushed = list.push[Frag](&l.frags, Frag { kind: .Text, box: bxid, x: x, y: baseline + shift - fm.ascent, w: w, h: fm.ascent + fm.descent, text: text, first: true, last: true })
}

fn emit_segment(l: *Layout, ob: u32, x0: f64, x1: f64, baseline: f64, shift: f64, first: bool, last: bool) {
    let obm = &l.boxes.items[usize(ob)]
    let fm = l.measure.metrics(l.measure.ctx, bstyle(l, ob))
    var top_edge = obm.padding[0usize] + obm.border[0usize]
    var bottom_edge = obm.padding[2usize] + obm.border[2usize]
    let pushed = list.push[Frag](&l.frags, Frag { kind: .Segment, box: ob, x: x0, y: baseline + shift - fm.ascent - top_edge, w: x1 - x0, h: fm.ascent + fm.descent + top_edge + bottom_edge, text: "", first: first, last: last })
}

// Lays out the pieces of an inline formatting context into lines of `cont`. Returns the content height.
fn layout_inline_content(l: *Layout, cont: u32, cbw: f64, cbh: f64, fc: *Flow) -> f64 {
    let cs = bstyle(l, cont)
    let (made, me) = list.init[Piece](l.a, 32usize)
    if me != ok { ret 0.0f64 }
    var bd = Builder { l: l, pieces: made, last_space: true, ws_pending: false, cbw: cbw, cbh: cbh }
    var ends = Flag { v: true }
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
    var x = Ifc { l: l, bd: bd, cont: cont, cs: cs, cbw: cbw, fc: fc, y: 0.0f64, first_line: true, open: zero, open_count: 0usize, sa: sa, sd: sd, own: own_made }
    var i = 0usize
    var guard = 0usize
    while i < x.bd.pieces.len && guard < 400000usize {
        guard += 1usize
        let scan = scan_line(&x, i)
        if scan.restart { continue }
        var end = scan.end
        if end <= i { end = i + 1usize }
        let lh = emit_line(&x, scan, end)
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
    // The container's own lines, contiguous: lines of inline-blocks laid out in between are not part of its range.
    let n_own = x.own.len
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
    ret x.y
}

// Vertical metrics and fragments of the line made of pieces[scan.lead..end). Returns the line height, or -1 for a line
// that held nothing to draw (only floats, absolutes or empty inline boxes).
fn emit_line(x: *Ifc, scan: Scan, end: usize) -> f64 {
    let l = x.l
    let cs = x.cs
    let lead = scan.lead
    var trim_end = end
    while trim_end > lead && x.bd.pieces.items[trim_end - 1usize].kind == .Text && !x.bd.pieces.items[trim_end - 1usize].ink && x.bd.pieces.items[trim_end - 1usize].w == 0.0f64 { trim_end -= 1usize }
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
            top = minf(top, sh - ta)
            bottom = maxf(bottom, sh + td)
        } else if p.kind == .Atomic {
            any_content = true
            let ab = &l.boxes.items[usize(p.box)]
            let asty = bstyle(l, p.box)
            let margin_h = ab.h + ab.margin[0usize] + ab.margin[2usize]
            var ba = ab.margin[0usize] + ab.h
            if ab.has_baseline { ba = ab.margin[0usize] + ab.baseline }
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
        }
        if k + 1usize < trim_end { used_w += p.trail }
        k += 1usize
    }
    let last_line = end >= x.bd.pieces.len
    let hard = scan.forced
    let ax = line_align_x(cs, last_line || hard, scan.avail, used_w, scan.line_x)
    var spread = 0.0f64
    if cs.text_align == .Justify && !last_line && !hard && scan.avail > used_w {
        var gaps = 0usize
        k = lead
        while k + 1usize < trim_end {
            if x.bd.pieces.items[k].trail > 0.0f64 { gaps += 1usize }
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
            let proc = l.boxes.items[usize(p.box)].proc
            var this_to = p.start + p.text.len
            var this_w = p.w
            if k + 1usize < trim_end {
                this_w += p.trail
                if p.trail > 0.0f64 { this_w += spread }
            } else {
                this_to = p.start + p.clen
            }
            if tf_box == p.box && tf_to == p.start && cur_shift == tf_shift {
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
            cx += obm.margin[3usize]
            if sp < 64usize {
                let obs = bstyle(l, ob)
                let (oa, od) = font_ad(l, obs)
                var psh = 0.0f64
                if sp > 0usize { psh = sshift[sp - 1usize] }
                sbox[sp] = ob
                sshift[sp] = psh + valign_shift(l, obs, bstyle(l, obm.parent), oa, od, oa + od)
                s_x[sp] = cx
                sfirst[sp] = true
                sp += 1usize
            }
            cx += obm.border[3usize] + obm.padding[3usize]
        } else if p.kind == .Close {
            if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
            tf_box = NONE
            let ob = p.box
            let obm = &l.boxes.items[usize(ob)]
            cx += obm.padding[1usize] + obm.border[1usize]
            if sp > 0usize {
                sp -= 1usize
                emit_segment(l, ob, s_x[sp], cx, baseline, sshift[sp], sfirst[sp], true)
            }
            cx += obm.margin[1usize]
        } else if p.kind == .Atomic {
            if tf_box != NONE { flush_text_frag(l, tf_box, tf_start, l.boxes.items[usize(tf_box)].proc[tf_from..tf_to], tf_w, tf_shift, baseline) }
            tf_box = NONE
            let ab = &l.boxes.items[usize(p.box)]
            let asty = bstyle(l, p.box)
            let margin_h = ab.h + ab.margin[0usize] + ab.margin[2usize]
            var ba = ab.margin[0usize] + ab.h
            if ab.has_baseline { ba = ab.margin[0usize] + ab.baseline }
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
    var ends = Flag { v: true }
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
    var i = 0usize
    while i < bd.pieces.len {
        let p = bd.pieces.items[i]
        i += 1usize
        if p.kind == .Hard {
            mx = maxf(mx, line)
            mn = maxf(mn, run)
            line = 0.0f64
            run = 0.0f64
            continue
        }
        if p.kind == .Float || p.kind == .Abs { continue }
        var w = p.w
        var minw = p.w
        if p.kind == .Atomic { minw = p.trail }
        line += w + (if_trail(p))
        run += minw
        if p.soft {
            mn = maxf(mn, run)
            run = 0.0f64
        }
    }
    mx = maxf(mx, line)
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

fn used_margins_vertical(l: *Layout, c: u32, cbw: f64) {
    let s = bstyle(l, c)
    let cb = bx(l, c)
    var base = cbw
    if base < 0.0f64 { base = 0.0f64 }
    cb.margin[0usize] = resolve_or(s.margin[0usize], base, 0.0f64)
    cb.margin[2usize] = resolve_or(s.margin[2usize], base, 0.0f64)
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
fn peek_top(l: *Layout, c: u32, cbw: f64) -> Margin {
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
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner == .Marker || (!kb.inline_level && is_out_of_flow(st(l, kb.style))) {
            kid = kb.next
            continue
        }
        if kb.inner == .Text && is_ws_only(kb.text) && collapses(l, kid) {
            kid = kb.next
            continue
        }
        if kb.inline_level || kb.inner == .Text { ret m }
        // The child's width decides its own percentage edges; its parent's content width is a close enough base.
        used_margins_vertical(l, kid, cbw)
        if self_collapsing(l, kid, cbw) {
            m = collapse(m, margin_of(l.boxes.items[usize(kid)].margin[0usize]))
            m = collapse(m, margin_of(l.boxes.items[usize(kid)].margin[2usize]))
            kid = kb.next
            continue
        }
        ret collapse(m, peek_top(l, kid, cbw))
    }
    ret m
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
                h = layout_multicol(l, b, cw, ch, cols, &fc)
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
    let (found, y) = last_baseline(l, b)
    if found {
        bb.baseline = y
        bb.has_baseline = true
    }
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
    var consumed = Flag { v: through_top }
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
    // The last child's bottom margin collapses through when nothing separates it from the parent's.
    let s = bstyle(l, b)
    var base = cw
    let closed = is_bfc_root(l, b) || bb.border[2usize] != 0.0f64 || bb.padding[2usize] != 0.0f64 || s.height.kind == .Px
    if closed {
        y += margin_value(acc)
        ret (y, no_margin())
    }
    ret (y, acc)
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
        ret y
    }
    // Width, and the room beside floats for a context root.
    var avail = cw
    var shift_x = 0.0f64
    let orth = is_orthogonal(l, c)
    let bfc = is_bfc_root(l, c) || orth
    // The collapsed margin above the border edge, through first children and empty blocks.
    var m_chain = peek_top(l, c, cw)
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
    var auto_h = 0.0f64
    var out_margin = no_margin()
    if orth {
        spec_h = -1.0f64
        ratio_h = -1.0f64
        layout_orthogonal(l, c, cw, ch)
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
    collapsed: bool, hedge: []Edge, vedge: []Edge
}

fn is_ws_text(l: *const Layout, k: u32) -> bool {
    let kb = &l.boxes.items[usize(k)]
    ret kb.inner == .Text && is_ws_only(kb.text) && collapses(l, k)
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
    let anon = new_box(l, inner, false, true, NONE, anon_style(l, l.boxes.items[usize(parent)].style, display))
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
        if !allowed && !kb.inline_level && is_out_of_flow(st(l, kb.style)) { allowed = true }
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
    let td = TableData { cols: ncols, rows: nrows, cells: cells, col_min: cmin, col_max: cmax, col_w: cw, col_pct: cpct, col_spec: cspec, row_h: rh, row_y: ry, row_box: rb, row_above: rab, row_below: rbe, sh: sh, sv: sv, sum_min: sum_min, sum_max: sum_max, collapsed: collapsed, hedge: hedge, vedge: vedge }
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
            cap.w = maxf(0.0f64, cw - cap.margin[1usize] - cap.margin[3usize])
            let content_w = maxf(0.0f64, cap.w - horizontal_extras(cap))
            let h = layout_in_new_bfc(l, kid, content_w, -1.0f64)
            let cap2 = bx(l, kid)
            cap2.h = h + vertical_extras(cap2)
            let outer = cap2.h + cap2.margin[0usize] + cap2.margin[2usize]
            if cs.caption_side == .Bottom { cap_bottom += outer } else { cap_top += outer }
        }
        kid = l.boxes.items[usize(kid)].next
    }
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
    var cur_top = tb2.border[0usize] + tb2.padding[0usize]
    var cur_bottom = cur_top + cap_top + grid_h
    kid = tb2.first
    while kid != NONE {
        if l.boxes.items[usize(kid)].inner == .Caption {
            let cs = bstyle(l, kid)
            let cap = bx(l, kid)
            cap.x = gx + cap.margin[3usize]
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
    ret cap_top + grid_h + cap_bottom
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
            let (kmn, kmx) = outer_content_widths(l, kid)
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
    bb.w = w + ex_h
    let auto_h = layout_in_new_bfc(l, id, w, hspec)
    var h = auto_h
    if hspec >= 0.0f64 { h = hspec }
    h = maxf(0.0f64, clamp_height_auto(l, id, h, -1.0f64, auto_h))
    let nb = bx(l, id)
    nb.overflow_w = maxf(nb.overflow_w, w)
    nb.overflow_h = maxf(nb.overflow_h, auto_h)
    nb.h = h + ex_v
    set_baseline(l, id)
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
        items[i].align = flex_item_align(cs, ks)
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
    }
    let (line_start, ls_e) = mem.alloc[usize](l.a, n + 1usize)
    let (line_cross, lc_e) = mem.alloc[f64](l.a, n + 1usize)
    let (line_up, lu_e) = mem.alloc[f64](l.a, n + 1usize)
    let (line_pos, lp_e) = mem.alloc[f64](l.a, n + 1usize)
    if ls_e != ok || lc_e != ok || lu_e != ok || lp_e != ok { ret 0.0f64 }
    var nlines = 0usize
    var used = 0.0f64
    i = 0usize
    while i < n {
        let outer = items[i].hyp + items[i].main_ex + items[i].ms + items[i].me
        if i == 0usize {
            line_start[0usize] = 0usize
            nlines = 1usize
            used = outer
        } else if wrap && used + gap_main + outer > avail + 0.001f64 {
            line_start[nlines] = i
            nlines += 1usize
            used = outer
        } else {
            used += gap_main + outer
        }
        i += 1usize
    }
    line_start[nlines] = n
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
                flex_place_item(l, id, items[i].target, hspec)
                items[i].cross = bx(l, id).h + items[i].cs + items[i].ce
            } else {
                let w = flex_cross_width(l, id, cw, items[i].align == .Stretch)
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
                    flex_place_item(l, id, items[i].target, hs)
                } else {
                    let ib2 = bx(l, id)
                    let ws = ib2.w - horizontal_extras(ib2) + room
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
            if jc == .FlexEnd || jc == .End || jc == .Right {
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

type GridParse = struct { c: style.Context, em: f64, avail: f64, gap: f64 }

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
    cnames: list.List[GName], rnames: list.List[GName], ec: i32, er: i32
}

// A laid-out grid's track geometry, kept so absolutely positioned children can use their grid area as containing block.
type GridGeom = struct {
    box: u32, nc: usize, nr: usize, cpos: []f64, csz: []f64, rpos: []f64, rsz: []f64,
    cnames: list.List[GName], rnames: list.List[GName], ec: i32, er: i32
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
fn grid_build(l: *Layout, b: u32, avail_w: f64, avail_h: f64) -> (*Grid, bool) {
    let cs = bstyle(l, b)
    let (gcell, ge) = mem.alloc[Grid](l.a, 1usize)
    if ge != ok { ret (zero, false) }
    let g = &gcell[0usize]
    let ctx = style.new_context(l.a, l.viewport_width, l.viewport_height)
    var gp = GridParse { c: ctx, em: cs.font_size, avail: avail_w, gap: 0.0f64 }
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
    let (ctext, has_ct) = extra_text(cs, "grid-template-columns")
    if has_ct { gp_list(&gp, ctext, &ctr, &cnames) }
    gp.gap = g.gap_r
    gp.avail = avail_h
    let (rtext, has_rt) = extra_text(cs, "grid-template-rows")
    if has_rt { gp_list(&gp, rtext, &rtr, &rnames) }
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
        size_tracks(g.cols, g.nc, g.gap_c, -1.0f64, g.items, g.n, true, pass == 0usize, false)
        let total = tracks_total(g.cols, g.nc, g.gap_c)
        if pass == 0usize { mn = total } else { mx = total }
        pass += 1usize
    }
    ret (mn, mx)
}

fn layout_grid(l: *Layout, b: u32, cw: f64, ch: f64) -> f64 {
    let cs = bstyle(l, b)
    let (g, built) = grid_build(l, b, cw, ch)
    if !built { ret 0.0f64 }
    let stretch_cols = cs.justify_content == .Normal || cs.justify_content == .Stretch
    let stretch_rows = cs.align_content == .Normal || cs.align_content == .Stretch
    size_tracks(g.cols, g.nc, g.gap_c, cw, g.items, g.n, true, false, stretch_cols)
    // Row contributions are the items' heights at their column widths.
    var i = 0usize
    while i < g.n {
        let id = g.items[i].box
        let area_w = grid_area_size(g.cols, g.items[i].cs, g.items[i].cn, g.gap_c)
        let w = grid_item_width(l, id, cs, area_w)
        let is0 = bstyle(l, id)
        var hs0 = -1.0f64
        let (hv0, has_h0) = resolve_len(is0.height, -1.0f64)
        if is0.height.kind == .Px && has_h0 { hs0 = to_content_h(l, id, hv0) }
        flex_place_item(l, id, w, hs0)
        let ib = bx(l, id)
        let outer = ib.h + ib.margin[0usize] + ib.margin[2usize]
        g.items[i].rmin = outer
        g.items[i].rmax = outer
        i += 1usize
    }
    size_tracks(g.rows, g.nr, g.gap_r, ch, g.items, g.n, false, false, stretch_rows && ch >= 0.0f64)
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
        } else if (align == .Normal || align == .Stretch) && is.margin[0usize].kind != .Auto && is.margin[2usize].kind != .Auto && ib.inner != .Replaced {
            hspec = maxf(0.0f64, area_h - ib.margin[0usize] - ib.margin[2usize] - vertical_extras(ib))
        }
        flex_place_item(l, id, w, hspec)
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
        let gg = GridGeom { box: b, nc: g.nc, nr: g.nr, cpos: cpos, csz: csz, rpos: rpos, rsz: rsz, cnames: g.cnames, rnames: g.rnames, ec: g.ec, er: g.er }
        let gp2 = list.push[GridGeom](&l.grids, gg)
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
    ret bb.inner == .Replaced || bb.inner == .Table || bb.inner == .Flex || bb.inner == .Grid || bb.inner == .Marker || bb.inner == .Text || bb.inner == .Break
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
                let dx = f64(k) * stride
                let dy = f64(k) * colh
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
                if k0 == k1 || unbreakable(l, kid) || (kb.first == NONE && kb.line_count == 0u32) {
                    if k0 > maxk { maxk = k0 }
                    if apply && k0 > 0usize {
                        l.boxes.items[usize(kid)].x += f64(k0) * stride
                        l.boxes.items[usize(kid)].y -= f64(k0) * colh
                    }
                } else {
                    let m = colify(l, kid, ky, colh, stride, apply)
                    if m > maxk { maxk = m }
                }
            }
        }
        kid = nxt
    }
    ret maxk
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
    if ch >= 0.0f64 && fill_auto {
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
    let _used = colify(l, b, origin, colh, stride, true)
    ret colh
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
    if bb.aux == 3u32 {
        let pb = &l.boxes.items[usize(bb.parent)]
        let (px, py) = abs_origin(l, bb.parent)
        static_x = px + pb.border[3usize] + pb.padding[3usize] + bb.x - pad_x
        static_y = py + pb.border[0usize] + pb.padding[0usize] + bb.y - pad_y
    } else {
        let (px, py) = abs_origin(l, bb.parent)
        static_x = px + bb.x - pad_x
        static_y = py + bb.y - pad_y
    }
    // In a grid area the static position is the area's start corner.
    if grid_cb {
        static_x = 0.0f64
        static_y = 0.0f64
    }
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
    }
    // Height.
    var spec_h = -1.0f64
    let (hv, has_hv) = resolve_len(s.height, cb_h)
    if bb.inner == .Replaced {
        let (_rw2, rh) = used_replaced_size(l, b, cb_w, cb_h)
        spec_h = rh
    } else if s.height.kind == .Px && has_hv {
        spec_h = to_content_h(l, b, hv)
    } else if has_t && has_b {
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
    var top = static_y
    if has_t {
        top = tv
    } else if has_b {
        top = cb_h - bv - bbh.h - mb - mt
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
fn layout_orthogonal(l: *Layout, c: u32, pbase: f64, pch: f64) {
    let old = l.vmode
    let code = mode_code(bstyle(l, c))
    let bb = bx(l, c)
    let pm = bb.margin
    var room = pch
    if room < 0.0f64 {
        room = l.viewport_height
        if old != 0u8 { room = l.viewport_width }
    }
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
    if s.width.kind == .Px && has_w {
        inline = to_content_w(l, c, wv)
    } else {
        // Automatic inline size of an orthogonal flow: shrink-to-fit against the container's block space (Writing Modes 3 7.3).
        clear_widths(l, c)
        let (mn, mx) = content_widths(l, c)
        inline = minf(mx, maxf(mn, maxf(0.0f64, room - outer_i - ext_i)))
    }
    inline = maxf(0.0f64, clamp_width(l, c, inline, pbase))
    var spec_b = -1.0f64
    if s.height.kind == .Px && s.height.pct == 0.0f64 { spec_b = to_content_h(l, c, s.height.px) }
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
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (zero, TooBig) }
    var l = Layout { a: a, d: d, styles: styles, measure: measure, boxes: boxes, lines: lines, frags: frags, anon: anon, root: NONE, viewport_width: viewport_width, viewport_height: viewport_height, doc_width: 0.0f64, doc_height: 0.0f64, floats: floats, tables: tables, counters: counters, quote_depth: 0i64, gen_depth: 0usize, vmode: 0u8, tr1: zero, tr2: zero, grids: grids }
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
    positioned_pass(&l, vp)
    extent_pass(&l, vp, 0.0f64, 0.0f64)
    l.doc_width = maxf(l.doc_width, viewport_width)
    l.doc_height = maxf(l.doc_height, viewport_height)
    ret (l, ok)
}

error TooBig
