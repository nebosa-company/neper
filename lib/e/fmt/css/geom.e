// Geometry of a finished layout (tracker 2.11, 2.12, 2.15): document and viewport rectangles with transforms,
// `offset*` / `client*` / `scroll*` measures, scroll containers, sticky offsets, stacking contexts and hit testing by
// geometry. The painter (`e.fmt.css.paint`) and the browser's DOM bindings (`getBoundingClientRect`, `elementFromPoint`)
// both read it.
//
// Coordinates: a box's `x`, `y` are relative to its parent's border box (see `e.fmt.css.layout`); a transform applies to
// the box and everything inside it about its `transform-origin`, before the box is moved to `x`, `y`. An affine is
// `[a, b, c, d, e, f]` with `x' = a x + c y + e`, `y' = b x + d y + f`.
//
// Memory: allocation-free except `rect_text`; results are values.

use e.gfx.cssvalue as cv
use e.fmt.css.layout as layout
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.mem
use e.str

type Rect = struct { x: f64, y: f64, w: f64, h: f64 }

type Point = struct { x: f64, y: f64 }

fn apply(m: [6]f64, x: f64, y: f64) -> Point {
    ret Point { x: m[0] * x + m[2] * y + m[4], y: m[1] * x + m[3] * y + m[5] }
}

// The inverse of an affine; false when it is singular.
fn invert(m: [6]f64) -> ([6]f64, bool) {
    let det = m[0] * m[3] - m[1] * m[2]
    if det > -0.000000001f64 && det < 0.000000001f64 { ret (cv.identity(), false) }
    let ia = m[3] / det
    let ib = -m[1] / det
    let ic = -m[2] / det
    let id = m[0] / det
    ret (cv.six(ia, ib, ic, id, -(ia * m[4] + ic * m[5]), -(ib * m[4] + id * m[5])), true)
}

fn bounds_of(m: [6]f64, w: f64, h: f64) -> Rect {
    let p0 = apply(m, 0.0f64, 0.0f64)
    let p1 = apply(m, w, 0.0f64)
    let p2 = apply(m, 0.0f64, h)
    let p3 = apply(m, w, h)
    var lo_x = p0.x
    var hi_x = p0.x
    var lo_y = p0.y
    var hi_y = p0.y
    if p1.x < lo_x { lo_x = p1.x }
    if p2.x < lo_x { lo_x = p2.x }
    if p3.x < lo_x { lo_x = p3.x }
    if p1.x > hi_x { hi_x = p1.x }
    if p2.x > hi_x { hi_x = p2.x }
    if p3.x > hi_x { hi_x = p3.x }
    if p1.y < lo_y { lo_y = p1.y }
    if p2.y < lo_y { lo_y = p2.y }
    if p3.y < lo_y { lo_y = p3.y }
    if p1.y > hi_y { hi_y = p1.y }
    if p2.y > hi_y { hi_y = p2.y }
    if p3.y > hi_y { hi_y = p3.y }
    ret Rect { x: lo_x, y: lo_y, w: hi_x - lo_x, h: hi_y - lo_y }
}

fn extra_of(s: *const style.Style, name: str) -> (str, bool) {
    var i = 0usize
    while i < s.extras.len {
        if str.eq(s.extras[i].name, name) { ret (s.extras[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// The transform of box `b` in the coordinate space of its own border box, about its transform origin (false: none).
fn box_transform(a: *mem.Arena, l: *const layout.Layout, b: u32) -> ([6]f64, bool) {
    let bb = &l.boxes.items[usize(b)]
    if bb.inner == .Text || bb.inner == .Marker { ret (cv.identity(), false) }
    let s = layout.st(l, bb.style)
    let (raw, has) = extra_of(s, "transform")
    var m = cv.identity()
    var any = false
    if has {
        let (t, good) = cv.parse_transform(a, raw)
        if good {
            m = t
            any = true
        }
        let (px, py) = cv.parse_translate_percent(a, raw)
        if px != 0.0f64 || py != 0.0f64 {
            m = cv.affine_mul(cv.six(1.0f64, 0.0f64, 0.0f64, 1.0f64, px * bb.w, py * bb.h), m)
            any = true
        }
    }
    let (traw, has_t) = extra_of(s, "translate")
    if has_t && !str.eq(traw, "none") {
        let (tt, good) = cv.parse_transform(a, cv.cat(a, "translate(", cv.cat(a, cv.lower(a, cv.trim_ws(traw)), ")")))
        if good {
            m = cv.affine_mul(tt, m)
            any = true
        }
    }
    let (rraw, has_r) = extra_of(s, "rotate")
    if has_r && !str.eq(rraw, "none") {
        let (rr, good) = cv.parse_transform(a, cv.cat(a, "rotate(", cv.cat(a, cv.lower(a, cv.trim_ws(rraw)), ")")))
        if good {
            m = cv.affine_mul(m, rr)
            any = true
        }
    }
    let (sraw, has_s) = extra_of(s, "scale")
    if has_s && !str.eq(sraw, "none") {
        let (ss, good) = cv.parse_transform(a, cv.cat(a, "scale(", cv.cat(a, cv.lower(a, cv.trim_ws(sraw)), ")")))
        if good {
            m = cv.affine_mul(m, ss)
            any = true
        }
    }
    if !any { ret (cv.identity(), false) }
    var cx = 0.5f64 * bb.w
    var cy = 0.5f64 * bb.h
    let (oraw, has_o) = extra_of(s, "transform-origin")
    if has_o {
        let ctx = style.new_context(a, l.viewport_width, l.viewport_height)
        let toks = cv.split_top_level_spaces(a, cv.lower(a, cv.trim_ws(oraw)))
        var have_x = false
        var have_y = false
        var k = 0usize
        while k < toks.len {
            let t = toks[k]
            k += 1usize
            if str.eq(t, "left") {
                cx = 0.0f64
                have_x = true
            } else if str.eq(t, "right") {
                cx = bb.w
                have_x = true
            } else if str.eq(t, "top") {
                cy = 0.0f64
                have_y = true
            } else if str.eq(t, "bottom") {
                cy = bb.h
                have_y = true
            } else if !str.eq(t, "center") {
                let (len, good) = style.parse_len(&ctx, t, s.font_size, style.A_PERCENT)
                if good {
                    if !have_x {
                        cx = len.px + len.pct * bb.w
                        have_x = true
                    } else {
                        cy = len.px + len.pct * bb.h
                        have_y = true
                    }
                }
            }
        }
    }
    let about = cv.affine_mul(cv.six(1.0f64, 0.0f64, 0.0f64, 1.0f64, cx, cy), cv.affine_mul(m, cv.six(1.0f64, 0.0f64, 0.0f64, 1.0f64, -cx, -cy)))
    ret (about, true)
}

// The affine taking points in `b`'s border box space to document space: every ancestor's transform and offset.
fn to_document(a: *mem.Arena, l: *const layout.Layout, b: u32) -> [6]f64 {
    var m = cv.identity()
    var cur = b
    while cur != layout.NONE {
        let cb = &l.boxes.items[usize(cur)]
        let (t, has) = box_transform(a, l, cur)
        var local = cv.six(1.0f64, 0.0f64, 0.0f64, 1.0f64, cb.x, cb.y)
        if has { local = cv.affine_mul(local, t) }
        m = cv.affine_mul(local, m)
        cur = cb.parent
    }
    ret m
}

// The border box in document coordinates, ignoring transforms.
fn layout_rect(l: *const layout.Layout, b: u32) -> Rect {
    let (ax, ay) = layout.abs_origin(l, b)
    let bb = &l.boxes.items[usize(b)]
    ret Rect { x: ax, y: ay, w: bb.w, h: bb.h }
}

// The bounding box of the transformed border box in document coordinates (`getBoundingClientRect` before scrolling).
fn bounding_rect(a: *mem.Arena, l: *const layout.Layout, b: u32) -> Rect {
    let m = to_document(a, l, b)
    let bb = &l.boxes.items[usize(b)]
    ret bounds_of(m, bb.w, bb.h)
}

// --- offset*, client*, scroll*.

fn is_positioned(l: *const layout.Layout, b: u32) -> bool {
    let s = layout.st(l, l.boxes.items[usize(b)].style)
    ret s.position != .Static
}

// The nearest ancestor that is positioned, a table part or the root element's box (HTML `offsetParent`).
fn offset_parent(l: *const layout.Layout, b: u32) -> u32 {
    var cur = l.boxes.items[usize(b)].parent
    while cur != layout.NONE {
        let cb = &l.boxes.items[usize(cur)]
        if cb.parent == layout.NONE { ret cur }
        if is_positioned(l, cur) || cb.inner == .Table || cb.inner == .Cell { ret cur }
        cur = cb.parent
    }
    ret layout.NONE
}

// `offsetLeft`, `offsetTop`: the border box's position relative to the padding edge of its offset parent.
fn offset_pos(l: *const layout.Layout, b: u32) -> Point {
    let op = offset_parent(l, b)
    let (bx, by) = layout.abs_origin(l, b)
    if op == layout.NONE { ret Point { x: bx, y: by } }
    let (px, py) = layout.abs_origin(l, op)
    let pb = &l.boxes.items[usize(op)]
    ret Point { x: bx - px - pb.border[3usize], y: by - py - pb.border[0usize] }
}

// `clientWidth`, `clientHeight`: the padding box.
fn client_size(l: *const layout.Layout, b: u32) -> Point {
    let bb = &l.boxes.items[usize(b)]
    ret Point { x: bb.w - bb.border[1usize] - bb.border[3usize], y: bb.h - bb.border[0usize] - bb.border[2usize] }
}

fn is_scroll_container(l: *const layout.Layout, b: u32) -> bool {
    let s = layout.st(l, l.boxes.items[usize(b)].style)
    ret s.overflow_x != .Visible || s.overflow_y != .Visible
}

fn union_descendants(l: *const layout.Layout, b: u32, ox: f64, oy: f64, out: *Rect) {
    var kid = l.boxes.items[usize(b)].first
    while kid != layout.NONE {
        let kb = &l.boxes.items[usize(kid)]
        let ks = layout.st(l, kb.style)
        if kb.inner != .Text && kb.inner != .Marker && ks.position != .Fixed {
            let x = ox + kb.x
            let y = oy + kb.y
            if x < out.x { out.x = x }
            if y < out.y { out.y = y }
            if x + kb.w > out.x + out.w { out.w = x + kb.w - out.x }
            if y + kb.h > out.y + out.h { out.h = y + kb.h - out.y }
            if !is_scroll_container(l, kid) { union_descendants(l, kid, x, y, out) }
        }
        kid = kb.next
    }
}

// `scrollWidth`, `scrollHeight`: the scrollable overflow of `b` (at least its padding box).
fn scroll_size(l: *const layout.Layout, b: u32) -> Point {
    let bb = &l.boxes.items[usize(b)]
    let pad = client_size(l, b)
    var r = Rect { x: 0.0f64, y: 0.0f64, w: pad.x, h: pad.y }
    union_descendants(l, b, -bb.border[3usize], -bb.border[0usize], &r)
    var w = pad.x
    var h = pad.y
    if r.x + r.w > w { w = r.x + r.w }
    if r.y + r.h > h { h = r.y + r.h }
    // Lines of inline content count too.
    var li = 0usize
    while li < usize(bb.line_count) {
        let ln = l.lines.items[usize(bb.line_first) + li]
        if ln.x + ln.w + bb.padding[3usize] > w { w = ln.x + ln.w + bb.padding[3usize] }
        if ln.y + ln.h + bb.padding[0usize] > h { h = ln.y + ln.h + bb.padding[0usize] }
        li += 1usize
    }
    ret Point { x: w, y: h }
}

// --- Sticky positioning.

// How far a `position: sticky` box moves for a scrollport `port` (the nearest scroll container's padding box in document
// coordinates, scrolled to its current offset) and its containing block `cb` (document coordinates).
fn sticky_shift(l: *const layout.Layout, b: u32, port: Rect, cb: Rect) -> Point {
    let bb = &l.boxes.items[usize(b)]
    let s = layout.st(l, bb.style)
    if s.position != .Sticky { ret Point { x: 0.0f64, y: 0.0f64 } }
    let (ax, ay) = layout.abs_origin(l, b)
    var dx = 0.0f64
    var dy = 0.0f64
    if s.inset[0usize].kind == .Px {
        let top = port.y + layout.resolve_or(s.inset[0usize], port.h, 0.0f64)
        if ay < top { dy = top - ay }
    } else if s.inset[2usize].kind == .Px {
        let bottom = port.y + port.h - layout.resolve_or(s.inset[2usize], port.h, 0.0f64)
        if ay + bb.h > bottom { dy = bottom - ay - bb.h }
    }
    if s.inset[3usize].kind == .Px {
        let left = port.x + layout.resolve_or(s.inset[3usize], port.w, 0.0f64)
        if ax < left { dx = left - ax }
    } else if s.inset[1usize].kind == .Px {
        let right = port.x + port.w - layout.resolve_or(s.inset[1usize], port.w, 0.0f64)
        if ax + bb.w > right { dx = right - ax - bb.w }
    }
    // It never leaves its containing block.
    if ay + dy + bb.h > cb.y + cb.h { dy = cb.y + cb.h - ay - bb.h }
    if ay + dy < cb.y { dy = cb.y - ay }
    if ax + dx + bb.w > cb.x + cb.w { dx = cb.x + cb.w - ax - bb.w }
    if ax + dx < cb.x { dx = cb.x - ax }
    ret Point { x: dx, y: dy }
}

// --- Stacking contexts.

fn is_stacking_context(a: *mem.Arena, l: *const layout.Layout, b: u32) -> bool {
    let bb = &l.boxes.items[usize(b)]
    if bb.parent == layout.NONE { ret true }
    if bb.inner == .Text || bb.inner == .Marker { ret false }
    let s = layout.st(l, bb.style)
    if s.opacity < 1.0f64 { ret true }
    if (s.position == .Absolute || s.position == .Relative) && !s.z_index_auto { ret true }
    if s.position == .Fixed || s.position == .Sticky { ret true }
    // A flex or grid item with a z-index is a stacking context whether or not it is positioned.
    if !s.z_index_auto && l.boxes.items[usize(bb.parent)].parent != layout.NONE && (l.boxes.items[usize(bb.parent)].inner == .Flex || l.boxes.items[usize(bb.parent)].inner == .Grid) { ret true }
    let (_t, has) = box_transform(a, l, b)
    if has { ret true }
    let (flt, has_f) = extra_of(s, "filter")
    if has_f && !str.eq(flt, "none") { ret true }
    let (iso, has_i) = extra_of(s, "isolation")
    if has_i && str.eq(iso, "isolate") { ret true }
    let (cp, has_c) = extra_of(s, "clip-path")
    if has_c && !str.eq(cp, "none") { ret true }
    let (mk, has_m) = extra_of(s, "mask-image")
    if has_m && !str.eq(mk, "none") { ret true }
    ret false
}

// --- Hit testing by geometry.

fn contains_point(r: Rect, x: f64, y: f64) -> bool {
    ret x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

// The deepest box whose border box (through its transform) contains the document point, preferring later siblings and
// positioned or floated boxes over earlier in-flow ones (an approximation of paint order); `NONE` when nothing does.
fn hit_test(a: *mem.Arena, l: *const layout.Layout, b: u32, x: f64, y: f64) -> u32 {
    let bb = &l.boxes.items[usize(b)]
    if bb.inner == .Text || bb.inner == .Marker { ret layout.NONE }
    let s = layout.st(l, bb.style)
    if s.visibility != .Visible && bb.first == layout.NONE { ret layout.NONE }
    // Into the box's own space.
    var px = x
    var py = y
    if bb.parent != layout.NONE {
        let (t, has) = box_transform(a, l, b)
        px = x - bb.x
        py = y - bb.y
        if has {
            let (inv, good_inv) = invert(t)
            if !good_inv { ret layout.NONE }
            let q = apply(inv, px, py)
            px = q.x
            py = q.y
        }
    }
    let inside = px >= 0.0f64 && py >= 0.0f64 && px < bb.w && py < bb.h
    // A clipping box hides what lies outside it.
    if !inside && is_scroll_container(l, b) && bb.parent != layout.NONE { ret layout.NONE }
    var best = layout.NONE
    // Later children paint over earlier ones; positioned and floated boxes over in-flow blocks; negative z-index last.
    var pass = 0usize
    while pass < 4usize && best == layout.NONE {
        var kid = bb.last
        while kid != layout.NONE {
            let kb = &l.boxes.items[usize(kid)]
            let ks = layout.st(l, kb.style)
            var rank = 0usize
            if ks.position != .Static && !ks.z_index_auto { rank = 2usize } else if ks.position != .Static || ks.floating != .None { rank = 1usize }
            if (pass == 0usize && rank == 2usize && ks.z_index >= 0i64) || (pass == 1usize && rank == 1usize) || (pass == 2usize && rank == 0usize) || (pass == 3usize && rank == 2usize && ks.z_index < 0i64) {
                let h = hit_test(a, l, kid, px, py)
                if h != layout.NONE {
                    best = h
                    break
                }
            }
            kid = kb.prev
        }
        pass += 1usize
    }
    if best != layout.NONE { ret best }
    // Text and inline boxes live in the lines of the container: the text run under the point, else the inline box.
    if inside && bb.line_count > 0u32 {
        let cx = px - bb.border[3usize] - bb.padding[3usize]
        let cy = py - bb.border[0usize] - bb.padding[0usize]
        var seg = layout.NONE
        var li = 0usize
        while li < usize(bb.line_count) {
            let ln = l.lines.items[usize(bb.line_first) + li]
            var fi = 0usize
            while fi < usize(ln.frag_count) {
                let fr = l.frags.items[usize(ln.frag_first) + fi]
                if cx >= fr.x && cx < fr.x + fr.w && cy >= fr.y && cy < fr.y + fr.h {
                    if fr.kind == .Text || fr.kind == .Marker { ret fr.box }
                    if fr.kind == .Segment { seg = fr.box }
                }
                fi += 1usize
            }
            li += 1usize
        }
        if seg != layout.NONE { ret seg }
    }
    if inside && s.visibility == .Visible { ret b }
    ret layout.NONE
}
