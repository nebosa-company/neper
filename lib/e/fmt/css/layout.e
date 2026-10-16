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
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.str
use e.text.segment as segment

type FontMetrics = struct { ascent: f64, descent: f64, line_gap: f64, x_height: f64 }

// The intrinsic size of replaced content (`kind` 0: unknown, so a 300x150 box; 1: an image or media with a size and
// maybe a ratio; 2: a form control, whose size the layout derives from its font).
type Intrinsic = struct { kind: u8, has_width: bool, width: f64, has_height: bool, height: f64, ratio: f64 }

// `width` is the raw advance of the text in the style's font (letter and word spacing are added by the layout).
type Measure = struct {
    ctx: *void,
    width: fn(*void, *const style.Style, str) -> f64,
    metrics: fn(*void, *const style.Style) -> FontMetrics,
    intrinsic: fn(*void, html.NodeId) -> Intrinsic
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
    min_c: f64, max_c: f64, has_c: bool, in_layout: bool, proc: str
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
    floats: list.List[FloatRec], tables: list.List[TableData]
}

// A float placed in a block formatting context, in the coordinates of the context's root content box.
type FloatRec = struct { box: u32, x: f64, y: f64, w: f64, h: f64, left: bool, root: u32 }

// --- Accessors.

fn st(l: *const Layout, id: u32) -> *const style.Style {
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
    let pushed = list.push[style.Style](&l.anon, s)
    ret u32(l.styles.len) + u32(l.anon.len) - 1u32
}

// --- Box generation.

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

fn is_out_of_flow(s: *const style.Style) -> bool {
    ret s.floating != .None || s.position == .Absolute || s.position == .Fixed
}

fn gen_children(l: *Layout, node: u32, parent_box: u32) {
    var kid = l.d.nodes[usize(node)].first_child
    while kid != html.NONE {
        gen_node(l, kid, parent_box, node)
        kid = l.d.nodes[usize(kid)].next_sibling
    }
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
    if s.display == .Contents {
        gen_children(l, node, parent_box)
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
        let m = new_box(l, .Marker, s.list_style_position == .Inside, true, node, node)
        bx(l, m).aux = list_ordinal(l, node)
        append(l, b, m)
    }
    gen_children(l, node, b)
    fix_anonymous(l, b)
}

// The value of a list item's counter: `value`, else the previous sibling item's plus one, from `start` (or 1).
fn list_ordinal(l: *Layout, node: u32) -> u32 {
    let (value, has_value) = dom.get_attribute(l.d, node, "value")
    if has_value {
        let (n, good) = str.parse_i64(value)
        if good == ok { ret u32(n) }
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
            ret u32(first - count)
        }
    }
    ret u32(start + count)
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
    let s = bstyle(l, b)
    var out = h
    let (mx, has_max) = resolve_len(s.max_height, cbh)
    if s.max_height.kind == .Px && has_max { out = minf(out, to_content_h(l, b, mx)) }
    let (mn, has_min) = resolve_len(s.min_height, cbh)
    if s.min_height.kind == .Px && has_min { out = maxf(out, to_content_h(l, b, mn)) }
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

type Builder = struct { l: *Layout, pieces: list.List[Piece], last_space: bool, ws_pending: bool, cbw: f64 }

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
    let (out, e) = mem.alloc[u8](l.a, raw.len * 2usize + 8usize)
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
        let cut_here = k == n || opp[k] != 0u8 || s.word_break == .BreakAll || scal[k - 1usize] == 10u32
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
            if !preserve {
                while content_end > 0usize && seg_text[content_end - 1usize] == 32u8 { content_end -= 1usize }
            }
            let content = seg_text[..content_end]
            let trail_text = seg_text[content_end..]
            let w = text_advance(l, s, content)
            let tr = text_advance(l, s, trail_text)
            if seg_text.len > 0usize {
                // The break after this piece is a soft wrap opportunity when the style wraps.
                var soft = wrap && (k < n || true) && (opp[k] != 0u8 || s.word_break == .BreakAll)
                if k == n { soft = wrap }
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
    layout_atomic(l, b, bd.cbw)
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
    let s = bstyle(l, b)
    let kind = s.list_style_type
    let n = i64(l.boxes.items[usize(b)].aux)
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
    y: f64, first_line: bool, open: [64]u32, open_count: usize, sa: f64, sd: f64
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
    let est = x.sa + x.sd
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
                layout_atomic(l, p.box, x.cbw)
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
            l.boxes.items[usize(p.box)].x = out.line_x + pos
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
fn layout_inline_content(l: *Layout, cont: u32, cbw: f64, fc: *Flow) -> f64 {
    let cs = bstyle(l, cont)
    let (made, me) = list.init[Piece](l.a, 32usize)
    if me != ok { ret 0.0f64 }
    var bd = Builder { l: l, pieces: made, last_space: true, ws_pending: false, cbw: cbw }
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
    if bd.pieces.len == 0usize { ret 0.0f64 }
    let (sa, sd) = font_ad(l, cs)
    var x = Ifc { l: l, bd: bd, cont: cont, cs: cs, cbw: cbw, fc: fc, y: 0.0f64, first_line: true, open: zero, open_count: 0usize, sa: sa, sd: sd }
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
            ab.x = cx + ab.margin[3usize]
            ab.y = x.y + margin_top_y + ab.margin[0usize]
            ab.aux = 2u32
            let pushed = list.push[Frag](&l.frags, Frag { kind: .Atomic, box: p.box, x: ab.x, y: ab.y, w: ab.w, h: ab.h, text: "", first: true, last: true })
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
    let overflow = used_w > scan.avail + 0.5f64 && cs.text_overflow == .Ellipsis && cs.overflow_x != .Visible
    let pushed = list.push[Line](&l.lines, Line { x: ax, y: x.y, w: used_w, h: line_h, baseline: x.y + baseline, frag_first: first_frag, frag_count: u32(l.frags.len) - first_frag, overflow_ellipsis: overflow })
    ret line_h
}

// --- Intrinsic widths.

fn replaced_intrinsic(l: *Layout, b: u32) -> Intrinsic {
    ret l.measure.intrinsic(l.measure.ctx, l.boxes.items[usize(b)].node)
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
    var bd = Builder { l: l, pieces: made, last_space: true, ws_pending: false, cbw: -1.0f64 }
    var ends = Flag { v: true }
    var kid = l.boxes.items[usize(cont)].first
    while kid != NONE {
        let kb = &l.boxes.items[usize(kid)]
        if kb.inner != .Marker {
            if kb.inline_level || kb.inner == .Text || kb.inner == .Break { collect_inline_intrinsic(&bd, kid, &ends) }
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
    } else if s.direction == .Rtl {
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
        } else if !is_out_of_flow(st(l, kb.style)) {
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
    let inner = l.boxes.items[usize(b)].inner
    if inner == .Table {
        h = layout_table(l, b, cw, ch)
    } else if inner == .Flex {
        h = layout_flex(l, b, cw, ch)
    } else if inner == .Grid {
        h = layout_grid(l, b, cw, ch)
    } else {
        let (ch2, _m) = layout_children(l, b, cw, ch, &fc, false)
        h = ch2
    }
    h = maxf(h, float_bottom(l, base, 2u32, 0.0f64))
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
fn layout_atomic(l: *Layout, b: u32, cbw: f64) {
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
    if s.width.kind == .Px && has_w {
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
    layout_contents_height(l, b, cw, -1.0f64)
}

// Lays out the contents of `b` (content width `cw`) as a formatting context root and sets its height from the style.
fn layout_contents_height(l: *Layout, b: u32, cw: f64, cbh: f64) {
    let s = bstyle(l, b)
    let bb = bx(l, b)
    var spec = -1.0f64
    let (hv, has_h) = resolve_len(s.height, cbh)
    if s.height.kind == .Px && has_h { spec = to_content_h(l, b, hv) }
    let first_line = l.lines.len
    let auto_h = layout_in_new_bfc(l, b, cw, spec)
    var h = auto_h
    if spec >= 0.0f64 { h = spec }
    h = maxf(0.0f64, clamp_height(l, b, h, cbh))
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
        let first_line = l.lines.len
        let h = layout_inline_content(l, b, cw, fc)
        let bb2 = bx(l, b)
        bb2.line_first = u32(first_line)
        bb2.line_count = u32(l.lines.len - first_line)
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
                layout_atomic(l, kid, cw)
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
    let bfc = is_bfc_root(l, c)
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
        let need = cb3.w + cb3.margin[1usize] + cb3.margin[3usize]
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
    var auto_h = 0.0f64
    var out_margin = no_margin()
    if bfc || cb4.inner != .Flow {
        auto_h = layout_in_new_bfc(l, c, content_w, spec_h)
    } else {
        var sub = Flow { base: fc.base, ox: content_ox, oy: content_oy }
        let (h2, m2) = layout_children(l, c, content_w, spec_h, &sub, through_top)
        auto_h = h2
        out_margin = m2
    }
    var ch_used = auto_h
    if spec_h >= 0.0f64 { ch_used = spec_h }
    ch_used = maxf(0.0f64, clamp_height(l, c, ch_used, ch))
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
}

// `position: relative` shifts the box after layout; sticky and the rest stay in place.
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

fn grid_widths(l: *Layout, b: u32) -> (f64, f64) {
    let (mn, mx) = block_widths(l, b)
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
    sh: f64, sv: f64, sum_min: f64, sum_max: f64
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
    let td = TableData { cols: ncols, rows: nrows, cells: cells, col_min: cmin, col_max: cmax, col_w: cw, col_pct: cpct, col_spec: cspec, row_h: rh, row_y: ry, row_box: rb, row_above: rab, row_below: rbe, sh: sh, sv: sv, sum_min: sum_min, sum_max: sum_max }
    let pushed = list.push[TableData](&l.tables, td)
    let index = u32(l.tables.len) - 1u32
    l.boxes.items[usize(t)].aux2 = index + 1u32
    ret index
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
    h = maxf(0.0f64, clamp_height(l, id, h, -1.0f64))
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
            if basis < 0.0f64 || spec_main < 0.0f64 {
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
        } else if min_len.kind == .Auto && ks.overflow_x == .Visible && ks.overflow_y == .Visible {
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

fn layout_grid(l: *Layout, b: u32, cw: f64, ch: f64) -> f64 {
    var fc = Flow { base: l.floats.len, ox: 0.0f64, oy: 0.0f64 }
    let (h, _m) = layout_children(l, b, cw, ch, &fc, false)
    ret h
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
    if w_auto {
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
    var content_h = 0.0f64
    if bb.inner != .Replaced {
        content_h = layout_in_new_bfc(l, b, cw, spec_h)
    }
    var h = content_h
    if spec_h >= 0.0f64 { h = spec_h }
    h = maxf(0.0f64, clamp_height(l, b, h, cb_h))
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
    let (qx, qy) = abs_origin(l, bbh.parent)
    bbh.x = pad_x + left + ml - qx
    bbh.y = pad_y + top + mt - qy
    bbh.aux = 4u32
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
fn layout_document(a: *mem.Arena, d: *const dom.Dom, styles: []const style.Style, measure: Measure, viewport_width: f64, viewport_height: f64) -> (Layout, err) {
    var cap = d.used * 2usize + 64usize
    let (boxes, e1) = list.init[Box](a, cap)
    let (lines, e2) = list.init[Line](a, 64usize)
    let (frags, e3) = list.init[Frag](a, 256usize)
    let (anon, e4) = list.init[style.Style](a, 64usize)
    let (floats, e5) = list.init[FloatRec](a, 16usize)
    let (tables, e6) = list.init[TableData](a, 8usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, TooBig) }
    var l = Layout { a: a, d: d, styles: styles, measure: measure, boxes: boxes, lines: lines, frags: frags, anon: anon, root: NONE, viewport_width: viewport_width, viewport_height: viewport_height, doc_width: 0.0f64, doc_height: 0.0f64, floats: floats, tables: tables }
    let root_el = dom.first_element_child(d, d.root)
    if root_el == html.NONE { ret (l, ok) }
    let vp = new_box(&l, .Flow, false, true, NONE, anon_style(&l, root_el, .Block))
    l.root = vp
    gen_node(&l, root_el, vp, d.root)
    fix_anonymous(&l, vp)
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
