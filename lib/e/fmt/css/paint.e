// Painting a finished layout into scene commands (tracker 3.1, 3.4, 3.6): CSS 2.1 Appendix E paint order over stacking
// contexts, backgrounds with radius, borders of every style, outlines, box shadows, text and text decorations,
// inline boxes, list markers, replaced images with object-fit, overflow clips, opacity layers and 2D transforms.
//
// Input: a `Layout`, a `PaintEnv` that supplies text layouts and images (the library knows no fonts or decoders), a
// `scene.Builder` and a `view` rectangle in document coordinates. The commands are in view coordinates (the document
// is shifted by `-view.x`, `-view.y`), boxes outside `view` are skipped, so a tall page is painted tile by tile within
// the scene's limits. Fixed-position boxes keep their viewport position.
//
// Not painted yet: gradients and background images (tracker 3.5), `clip-path`/`mask`/`filter` (3.8, 3.9), collapsed
// border conflict resolution, `text-shadow`, selection, the ellipsis mark of `text-overflow`.
//
// Memory: the arena is retained; paths and extents live in it.

use e.data.list as list
use e.fmt.css.geom as geom
use e.fmt.css.layout as layout
use e.fmt.css.style as style
use e.fmt.html as html
use e.gfx.cssvalue as cv
use e.gfx.geometry as geo
use e.gfx.paint as pt
use e.gfx.scene as scene
use e.mem
use e.str
use e.text.layout as tl

type ImageRef = struct { found: bool, texture: scene.TextureId, width: f32, height: f32 }

// `text` returns the shaped layout of a run in the style's font (an address of 0: nothing to draw); `image` the texture
// of a replaced element's picture.
type PaintEnv = struct {
    ctx: *void,
    text: fn(*void, *const style.Style, str) -> *const tl.Layout,
    image: fn(*void, html.NodeId) -> ImageRef
}

type Entry = struct { box: u32, z: i64, real: bool }

type Painter = struct {
    l: *const layout.Layout, a: *mem.Arena, env: PaintEnv, b: *scene.Builder,
    vx: f64, vy: f64, vw: f64, vh: f64, scroll_x: f64, scroll_y: f64,
    ext: []f64, status: err, moved: usize
}

fn emit(p: *Painter, c: scene.Command) {
    if p.status == ok { p.status = scene.push(p.b, c) }
}

fn color_of(c: u32) -> pt.Color {
    ret pt.srgb8(u8((c >> 16u32) & 255u32), u8((c >> 8u32) & 255u32), u8(c & 255u32), u8((c >> 24u32) & 255u32))
}

fn alpha_of(c: u32) -> u32 { ret (c >> 24u32) & 255u32 }

fn solid(c: u32) -> pt.Brush { ret pt.Brush { Solid: color_of(c) } }

fn grect(x: f64, y: f64, w: f64, h: f64) -> geo.Rect { ret geo.rect(f32(x), f32(y), f32(w), f32(h)) }

fn fill(p: *Painter, x: f64, y: f64, w: f64, h: f64, c: u32) {
    if w <= 0.0f64 || h <= 0.0f64 || alpha_of(c) == 0u32 { ret }
    emit(p, scene.Command { FillRect: scene.FillRect { rect: grect(x, y, w, h), brush: solid(c) } })
}

fn save(p: *Painter) {
    let c: scene.Command = .Save
    emit(p, c)
}

fn restore(p: *Painter) {
    let c: scene.Command = .Restore
    emit(p, c)
}

fn shade(c: u32, factor: f64) -> u32 {
    let a = (c >> 24u32) & 255u32
    let r = u32(f64((c >> 16u32) & 255u32) * factor)
    let g = u32(f64((c >> 8u32) & 255u32) * factor)
    let b = u32(f64(c & 255u32) * factor)
    ret (a << 24u32) | (r << 16u32) | (g << 8u32) | b
}

fn border_color_of(s: *const style.Style, side: usize) -> u32 {
    if s.border_current[side] { ret s.color }
    ret s.border_color[side]
}

fn has_border(s: *const style.Style, side: usize) -> bool {
    ret s.border_width[side] > 0.0f64 && s.border_style[side] != .None && s.border_style[side] != .Hidden
}

// --- Paths.

fn quad_path(a: *mem.Arena, x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) -> geo.Path {
    let (pb, e) = geo.path_builder(a, 8usize, 8usize)
    if e != ok { ret zero }
    var b = pb
    let m = geo.move_to(&b, geo.Point { x: f32(x0), y: f32(y0) })
    let l1 = geo.line_to(&b, geo.Point { x: f32(x1), y: f32(y1) })
    let l2 = geo.line_to(&b, geo.Point { x: f32(x2), y: f32(y2) })
    let l3 = geo.line_to(&b, geo.Point { x: f32(x3), y: f32(y3) })
    let c = geo.close_path(&b)
    ret geo.finish(&b)
}

fn fill_quad(p: *Painter, x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64, c: u32) {
    if alpha_of(c) == 0u32 { ret }
    emit(p, scene.Command { FillPath: scene.FillPath { path: quad_path(p.a, x0, y0, x1, y1, x2, y2, x3, y3), brush: solid(c) } })
}

// A rounded rectangle as a path (cubic corners).
fn rrect_path(a: *mem.Arena, rr: geo.RRect) -> geo.Path {
    let (pb, e) = geo.path_builder(a, 16usize, 32usize)
    if e != ok { ret zero }
    var b = pb
    let k = 0.5522847498f32
    let x0 = rr.rect.x
    let y0 = rr.rect.y
    let x1 = rr.rect.x + rr.rect.width
    let y1 = rr.rect.y + rr.rect.height
    let m = geo.move_to(&b, geo.Point { x: x0 + rr.top_left.x, y: y0 })
    let a1 = geo.line_to(&b, geo.Point { x: x1 - rr.top_right.x, y: y0 })
    let c1 = geo.cubic_to(&b, geo.Point { x: x1 - rr.top_right.x * (1.0f32 - k), y: y0 }, geo.Point { x: x1, y: y0 + rr.top_right.y * (1.0f32 - k) }, geo.Point { x: x1, y: y0 + rr.top_right.y })
    let a2 = geo.line_to(&b, geo.Point { x: x1, y: y1 - rr.bottom_right.y })
    let c2 = geo.cubic_to(&b, geo.Point { x: x1, y: y1 - rr.bottom_right.y * (1.0f32 - k) }, geo.Point { x: x1 - rr.bottom_right.x * (1.0f32 - k), y: y1 }, geo.Point { x: x1 - rr.bottom_right.x, y: y1 })
    let a3 = geo.line_to(&b, geo.Point { x: x0 + rr.bottom_left.x, y: y1 })
    let c3 = geo.cubic_to(&b, geo.Point { x: x0 + rr.bottom_left.x * (1.0f32 - k), y: y1 }, geo.Point { x: x0, y: y1 - rr.bottom_left.y * (1.0f32 - k) }, geo.Point { x: x0, y: y1 - rr.bottom_left.y })
    let a4 = geo.line_to(&b, geo.Point { x: x0, y: y0 + rr.top_left.y })
    let c4 = geo.cubic_to(&b, geo.Point { x: x0, y: y0 + rr.top_left.y * (1.0f32 - k) }, geo.Point { x: x0 + rr.top_left.x * (1.0f32 - k), y: y0 }, geo.Point { x: x0 + rr.top_left.x, y: y0 })
    let cl = geo.close_path(&b)
    ret geo.finish(&b)
}

// The used corner radii of a box of size w x h, scaled down when they would overlap (CSS Backgrounds 5.5).
fn corner_radii(s: *const style.Style, w: f64, h: f64) -> [4]geo.Radius {
    var out: [4]geo.Radius = zero
    var rx: [4]f64 = zero
    var ry: [4]f64 = zero
    var i = 0usize
    while i < 4usize {
        rx[i] = maxf(0.0f64, layout.resolve_or(s.radius_h[i], w, 0.0f64))
        ry[i] = maxf(0.0f64, layout.resolve_or(s.radius_v[i], h, 0.0f64))
        i += 1usize
    }
    var f = 1.0f64
    if rx[0usize] + rx[1usize] > w && rx[0usize] + rx[1usize] > 0.0f64 { f = minf(f, w / (rx[0usize] + rx[1usize])) }
    if rx[3usize] + rx[2usize] > w && rx[3usize] + rx[2usize] > 0.0f64 { f = minf(f, w / (rx[3usize] + rx[2usize])) }
    if ry[0usize] + ry[3usize] > h && ry[0usize] + ry[3usize] > 0.0f64 { f = minf(f, h / (ry[0usize] + ry[3usize])) }
    if ry[1usize] + ry[2usize] > h && ry[1usize] + ry[2usize] > 0.0f64 { f = minf(f, h / (ry[1usize] + ry[2usize])) }
    i = 0usize
    while i < 4usize {
        out[i] = geo.Radius { x: f32(rx[i] * f), y: f32(ry[i] * f) }
        i += 1usize
    }
    ret out
}

fn has_radius(s: *const style.Style) -> bool {
    var i = 0usize
    while i < 4usize {
        if (s.radius_h[i].kind == .Px && (s.radius_h[i].px > 0.0f64 || s.radius_h[i].pct > 0.0f64)) || (s.radius_v[i].kind == .Px && (s.radius_v[i].px > 0.0f64 || s.radius_v[i].pct > 0.0f64)) { ret true }
        i += 1usize
    }
    ret false
}

fn maxf(x: f64, y: f64) -> f64 {
    if x > y { ret x }
    ret y
}

fn minf(x: f64, y: f64) -> f64 {
    if x < y { ret x }
    ret y
}

// The rounded rectangle of a box region, inset by `inset` on each side from the border box (negative: outset).
fn region_rrect(s: *const style.Style, x: f64, y: f64, w: f64, h: f64, in_t: f64, in_r: f64, in_b: f64, in_l: f64) -> geo.RRect {
    let radii = corner_radii(s, w, h)
    let rw = maxf(0.0f64, w - in_l - in_r)
    let rh = maxf(0.0f64, h - in_t - in_b)
    ret geo.RRect {
        rect: grect(x + in_l, y + in_t, rw, rh),
        top_left: geo.Radius { x: maxf32(0.0f32, radii[0usize].x - f32(in_l)), y: maxf32(0.0f32, radii[0usize].y - f32(in_t)) },
        top_right: geo.Radius { x: maxf32(0.0f32, radii[1usize].x - f32(in_r)), y: maxf32(0.0f32, radii[1usize].y - f32(in_t)) },
        bottom_right: geo.Radius { x: maxf32(0.0f32, radii[2usize].x - f32(in_r)), y: maxf32(0.0f32, radii[2usize].y - f32(in_b)) },
        bottom_left: geo.Radius { x: maxf32(0.0f32, radii[3usize].x - f32(in_l)), y: maxf32(0.0f32, radii[3usize].y - f32(in_b)) }
    }
}

fn maxf32(x: f32, y: f32) -> f32 {
    if x > y { ret x }
    ret y
}

// --- Backgrounds, borders, outlines, shadows.

fn first_token(a: *mem.Arena, s: *const style.Style, name: str) -> str {
    let (v, has) = geom.extra_of(s, name)
    if !has { ret "" }
    let toks = cv.split_top_level_spaces(a, cv.lower(a, v))
    if toks.len == 0usize { ret "" }
    ret toks[0usize]
}

fn paint_background(p: *Painter, b: u32, s: *const style.Style, x: f64, y: f64, w: f64, h: f64) {
    if alpha_of(s.background_color) == 0u32 { ret }
    let bb = &p.l.boxes.items[usize(b)]
    var in_t = 0.0f64
    var in_r = 0.0f64
    var in_b = 0.0f64
    var in_l = 0.0f64
    let clip = first_token(p.a, s, "background-clip")
    if str.eq(clip, "padding-box") || str.eq(clip, "content-box") {
        in_t = bb.border[0usize]
        in_r = bb.border[1usize]
        in_b = bb.border[2usize]
        in_l = bb.border[3usize]
        if str.eq(clip, "content-box") {
            in_t += bb.padding[0usize]
            in_r += bb.padding[1usize]
            in_b += bb.padding[2usize]
            in_l += bb.padding[3usize]
        }
    }
    if has_radius(s) {
        save(p)
        emit(p, scene.Command { Clip: scene.Clip { Rounded: region_rrect(s, x, y, w, h, in_t, in_r, in_b, in_l) } })
        fill(p, x + in_l, y + in_t, w - in_l - in_r, h - in_t - in_b, s.background_color)
        restore(p)
    } else {
        fill(p, x + in_l, y + in_t, w - in_l - in_r, h - in_t - in_b, s.background_color)
    }
}

// One side of a plain border as a band, with the colour already shaded for its style.
fn side_color(s: *const style.Style, side: usize) -> u32 {
    let c = border_color_of(s, side)
    let st = s.border_style[side]
    if st == .Inset {
        if side == 0usize || side == 3usize { ret shade(c, 0.6f64) }
        ret c
    }
    if st == .Outset {
        if side == 2usize || side == 1usize { ret shade(c, 0.6f64) }
        ret c
    }
    ret c
}

// A straight run of dashes or dots along a band (x0,y0)-(x1,y1) of thickness `t`; `horizontal` picks the axis.
fn dashed_run(p: *Painter, x: f64, y: f64, len: f64, t: f64, horizontal: bool, dot: bool, c: u32) {
    var step = t * 3.0f64
    var dash = t * 3.0f64
    if dot {
        step = t * 2.0f64
        dash = t
    }
    if step < 1.0f64 { step = 1.0f64 }
    var at = 0.0f64
    var n = 0usize
    while at < len && n < 400usize {
        let seg = minf(dash, len - at)
        if horizontal { fill(p, x + at, y, seg, t, c) } else { fill(p, x, y + at, t, seg, c) }
        at += step
        n += 1usize
    }
}

fn paint_border_side(p: *Painter, s: *const style.Style, side: usize, x: f64, y: f64, w: f64, h: f64, bt: f64, br: f64, bbm: f64, bl: f64, trapezoid: bool) {
    if !has_border(s, side) { ret }
    let st = s.border_style[side]
    let c = side_color(s, side)
    // Band geometry: side 0 top, 1 right, 2 bottom, 3 left.
    var bx = x
    var by = y
    var bw = w
    var bh = bt
    if side == 1usize {
        bx = x + w - br
        by = y
        bw = br
        bh = h
    } else if side == 2usize {
        bx = x
        by = y + h - bbm
        bw = w
        bh = bbm
    } else if side == 3usize {
        bx = x
        by = y
        bw = bl
        bh = h
    }
    var inner_a = 0.0f64
    var inner_b = 0.0f64
    if st == .Dashed || st == .Dotted {
        if side == 0usize || side == 2usize {
            dashed_run(p, bx + bl * 0.0f64, by, bw, bh, true, st == .Dotted, c)
        } else {
            dashed_run(p, bx, by, bh, bw, false, st == .Dotted, c)
        }
        ret
    }
    if st == .Double && s.border_width[side] >= 3.0f64 {
        let third = s.border_width[side] / 3.0f64
        if side == 0usize {
            fill(p, bx, by, bw, third, c)
            fill(p, bx + bl / 3.0f64, by + 2.0f64 * third, bw - bl / 3.0f64 - br / 3.0f64, third, c)
        } else if side == 2usize {
            fill(p, bx, by + 2.0f64 * third, bw, third, c)
            fill(p, bx + bl / 3.0f64, by, bw - bl / 3.0f64 - br / 3.0f64, third, c)
        } else if side == 3usize {
            fill(p, bx, by, third, bh, c)
            fill(p, bx + 2.0f64 * third, by + bt / 3.0f64, third, bh - bt / 3.0f64 - bbm / 3.0f64, c)
        } else {
            fill(p, bx + 2.0f64 * third, by, third, bh, c)
            fill(p, bx, by + bt / 3.0f64, third, bh - bt / 3.0f64 - bbm / 3.0f64, c)
        }
        ret
    }
    if st == .Groove || st == .Ridge {
        // Two halves: the outer and the inner shade swap between groove and ridge.
        let base = border_color_of(s, side)
        var outer = shade(base, 0.6f64)
        var inner = base
        if st == .Ridge {
            outer = base
            inner = shade(base, 0.6f64)
        }
        if side == 0usize {
            fill(p, bx, by, bw, bh / 2.0f64, outer)
            fill(p, bx + bl / 2.0f64, by + bh / 2.0f64, bw - bl / 2.0f64 - br / 2.0f64, bh / 2.0f64, inner)
        } else if side == 2usize {
            fill(p, bx, by + bh / 2.0f64, bw, bh / 2.0f64, outer)
            fill(p, bx + bl / 2.0f64, by, bw - bl / 2.0f64 - br / 2.0f64, bh / 2.0f64, inner)
        } else if side == 3usize {
            fill(p, bx, by, bw / 2.0f64, bh, outer)
            fill(p, bx + bw / 2.0f64, by + bt / 2.0f64, bw / 2.0f64, bh - bt / 2.0f64 - bbm / 2.0f64, inner)
        } else {
            fill(p, bx + bw / 2.0f64, by, bw / 2.0f64, bh, outer)
            fill(p, bx, by + bt / 2.0f64, bw / 2.0f64, bh - bt / 2.0f64 - bbm / 2.0f64, inner)
        }
        ret
    }
    if trapezoid {
        // The corners are cut on the diagonals so that neighbouring colours meet.
        if side == 0usize {
            fill_quad(p, x, y, x + w, y, x + w - br, y + bt, x + bl, y + bt, c)
        } else if side == 1usize {
            fill_quad(p, x + w, y, x + w, y + h, x + w - br, y + h - bbm, x + w - br, y + bt, c)
        } else if side == 2usize {
            fill_quad(p, x + w, y + h, x, y + h, x + bl, y + h - bbm, x + w - br, y + h - bbm, c)
        } else {
            fill_quad(p, x, y + h, x, y, x + bl, y + bt, x + bl, y + h - bbm, c)
        }
        ret
    }
    // Top and bottom run the full width; left and right fit between them.
    if side == 1usize || side == 3usize {
        fill(p, bx, by + bt, bw, h - bt - bbm, c)
    } else {
        fill(p, bx, by, bw, bh, c)
    }
}

fn borders_uniform(s: *const style.Style) -> bool {
    var i = 1usize
    while i < 4usize {
        if s.border_style[i] != s.border_style[0usize] || s.border_width[i] != s.border_width[0usize] || border_color_of(s, i) != border_color_of(s, 0usize) { ret false }
        i += 1usize
    }
    ret true
}

fn paint_borders(p: *Painter, s: *const style.Style, x: f64, y: f64, w: f64, h: f64) {
    var any = false
    var i = 0usize
    while i < 4usize {
        if has_border(s, i) { any = true }
        i += 1usize
    }
    if !any { ret }
    let bt = maxf(0.0f64, s.border_width[0usize])
    let br = maxf(0.0f64, s.border_width[1usize])
    let bbm = maxf(0.0f64, s.border_width[2usize])
    let bl = maxf(0.0f64, s.border_width[3usize])
    let uniform = borders_uniform(s)
    if has_radius(s) {
        if uniform && s.border_style[0usize] == .Solid {
            // One stroke around the rounded box.
            let half = bt / 2.0f64
            let rr = region_rrect(s, x, y, w, h, half, half, half, half)
            emit(p, scene.Command { StrokePath: scene.StrokePath { path: rrect_path(p.a, rr), brush: solid(border_color_of(s, 0usize)), stroke: pt.Stroke { width: f32(bt), cap: .Butt, join: .Miter, miter_limit: 4.0f32 } } })
            ret
        }
        save(p)
        emit(p, scene.Command { Clip: scene.Clip { Rounded: region_rrect(s, x, y, w, h, 0.0f64, 0.0f64, 0.0f64, 0.0f64) } })
    }
    let cut = !uniform && ((has_border(s, 0usize) && has_border(s, 3usize) && border_color_of(s, 0usize) != border_color_of(s, 3usize)) || (has_border(s, 0usize) && has_border(s, 1usize) && border_color_of(s, 0usize) != border_color_of(s, 1usize)) || (has_border(s, 2usize) && has_border(s, 3usize) && border_color_of(s, 2usize) != border_color_of(s, 3usize)) || (has_border(s, 2usize) && has_border(s, 1usize) && border_color_of(s, 2usize) != border_color_of(s, 1usize)))
    i = 0usize
    while i < 4usize {
        paint_border_side(p, s, i, x, y, w, h, bt, br, bbm, bl, cut)
        i += 1usize
    }
    if has_radius(s) { restore(p) }
}

fn paint_outline(p: *Painter, s: *const style.Style, x: f64, y: f64, w: f64, h: f64) {
    if s.outline_style == .None || s.outline_style == .Hidden || s.outline_width <= 0.0f64 { ret }
    var c = s.outline_color
    if s.outline_current { c = s.color }
    let t = s.outline_width
    let o = s.outline_offset
    let ox = x - o - t
    let oy = y - o - t
    let ow = w + 2.0f64 * (o + t)
    let oh = h + 2.0f64 * (o + t)
    fill(p, ox, oy, ow, t, c)
    fill(p, ox, oy + oh - t, ow, t, c)
    fill(p, ox, oy + t, t, oh - 2.0f64 * t, c)
    fill(p, ox + ow - t, oy + t, t, oh - 2.0f64 * t, c)
}

// `box-shadow: <x> <y> <blur> <spread> <color>` (outer shadows): the blur is approximated by stacked translucent bands.
fn paint_box_shadow(p: *Painter, s: *const style.Style, x: f64, y: f64, w: f64, h: f64) {
    let (raw, has) = geom.extra_of(s, "box-shadow")
    if !has { ret }
    let text = cv.trim_ws(raw)
    if text.len == 0usize || str.eq(cv.lower(p.a, text), "none") { ret }
    let shadows = cv.split_top_level_commas(p.a, text)
    let ctx = style.new_context(p.a, p.l.viewport_width, p.l.viewport_height)
    var si = shadows.len
    while si > 0usize {
        si -= 1usize
        let toks = cv.split_top_level_spaces(p.a, shadows[si])
        var nums: [4]f64 = zero
        var count = 0usize
        var color = s.color
        var inset = false
        var k = 0usize
        while k < toks.len {
            let t = toks[k]
            k += 1usize
            if str.eq(cv.lower(p.a, t), "inset") {
                inset = true
                continue
            }
            let (len, good) = style.parse_len(&ctx, t, s.font_size, style.A_NEGATIVE)
            if good && len.kind == .Px && count < 4usize {
                nums[count] = len.px
                count += 1usize
            } else {
                let (col, cgood) = cv.parse_color(p.a, t)
                if cgood { color = col }
            }
        }
        if inset || count < 2usize { continue }
        let dx = nums[0usize]
        let dy = nums[1usize]
        let blur = maxf(0.0f64, nums[2usize])
        let spread = nums[3usize]
        let base_alpha = f64(alpha_of(color)) / 255.0f64
        let rgb = color & 16777215u32
        let steps = 6usize
        var n = 0usize
        // Layers from the widest, faintest to the core.
        while n < steps {
            let t = f64(n) / f64(steps)
            let grow = spread + blur * (1.0f64 - t) / 2.0f64
            let a = u32(255.0f64 * base_alpha / f64(steps) * (0.5f64 + t))
            let col = (a << 24u32) | rgb
            let rx = x + dx - grow
            let ry = y + dy - grow
            let rw = w + 2.0f64 * grow
            let rh = h + 2.0f64 * grow
            if has_radius(s) {
                save(p)
                emit(p, scene.Command { Clip: scene.Clip { Rounded: region_rrect(s, rx, ry, rw, rh, 0.0f64, 0.0f64, 0.0f64, 0.0f64) } })
                fill(p, rx, ry, rw, rh, col)
                restore(p)
            } else {
                fill(p, rx, ry, rw, rh, col)
            }
            n += 1usize
        }
    }
}

// Background, border and shadow of a box with its border box at (x, y).
fn paint_decor(p: *Painter, b: u32, x: f64, y: f64) {
    let bb = &p.l.boxes.items[usize(b)]
    if bb.inner == .Text || bb.inner == .Marker || bb.inner == .Column || bb.inner == .ColumnGroup { ret }
    let s = layout.st(p.l, bb.style)
    if s.visibility != .Visible { ret }
    paint_box_shadow(p, s, x, y, bb.w, bb.h)
    paint_background(p, b, s, x, y, bb.w, bb.h)
    paint_borders(p, s, x, y, bb.w, bb.h)
}

// --- Text and inline content.

fn font_metrics_of(p: *Painter, s: *const style.Style) -> layout.FontMetrics {
    ret p.l.measure.metrics(p.l.measure.ctx, s)
}

// The text decoration lines in force for a run: the nearest ancestor up to the block container that sets any.
fn decoration_in_force(p: *Painter, text_box: u32) -> (u8, u32, style.DecorationStyle) {
    var cur = text_box
    while cur != layout.NONE {
        let cb = &p.l.boxes.items[usize(cur)]
        let cs = layout.st(p.l, cb.style)
        if cs.decoration_line != 0u8 {
            var c = cs.decoration_color
            if cs.decoration_current { c = cs.color }
            ret (cs.decoration_line, c, cs.decoration_style)
        }
        if !cb.inline_level && cb.inner != .Text { break }
        cur = cb.parent
    }
    ret (0u8, 0u32, .Solid)
}

fn paint_decoration_line(p: *Painter, x: f64, y: f64, w: f64, t: f64, c: u32, how: style.DecorationStyle) {
    if how == .Double {
        fill(p, x, y, w, t, c)
        fill(p, x, y + 2.0f64 * t, w, t, c)
    } else if how == .Dotted {
        dashed_run(p, x, y, w, t, true, true, c)
    } else if how == .Dashed {
        dashed_run(p, x, y, w, t, true, false, c)
    } else {
        fill(p, x, y, w, t, c)
    }
}

fn paint_text_run(p: *Painter, text_box: u32, text: str, x: f64, y: f64, w: f64) {
    if layout.st(p.l, p.l.boxes.items[usize(text_box)].style).visibility != .Visible { ret }
    if text.len > 0usize {
        let env = p.env
        let lay = env.text(env.ctx, layout.st(p.l, p.l.boxes.items[usize(text_box)].style), text)
        let ts0 = layout.st(p.l, p.l.boxes.items[usize(text_box)].style)
        if mem.address_of(lay) != 0usize {
            emit(p, scene.Command { Text: scene.DrawText { layout: lay, origin: geo.Point { x: f32(x), y: f32(y) }, brush: solid(ts0.color) } })
        }
    }
    let ts = layout.st(p.l, p.l.boxes.items[usize(text_box)].style)
    let (bits, col, how) = decoration_in_force(p, text_box)
    if bits != 0u8 {
        let fm = font_metrics_of(p, ts)
        let t = maxf(1.0f64, ts.font_size / 16.0f64)
        let baseline = y + fm.ascent
        if (bits & style.DECORATION_UNDERLINE) != 0u8 { paint_decoration_line(p, x, baseline + t, w, t, col, how) }
        if (bits & style.DECORATION_OVERLINE) != 0u8 { paint_decoration_line(p, x, y, w, t, col, how) }
        if (bits & style.DECORATION_LINE_THROUGH) != 0u8 { paint_decoration_line(p, x, baseline - fm.x_height / 2.0f64 - t / 2.0f64, w, t, col, how) }
    }
}

// A list marker: the classic bullets are drawn as shapes, numbers as text.
fn paint_marker(p: *Painter, mb: u32, text: str, x: f64, y: f64, w: f64) {
    let ms = layout.st(p.l, p.l.boxes.items[usize(mb)].style)
    if ms.visibility != .Visible { ret }
    let kind = cv.lower(p.a, ms.list_style_type)
    if str.eq(kind, "none") { ret }
    let fm = font_metrics_of(p, ms)
    if str.eq(kind, "disc") || str.eq(kind, "circle") || str.eq(kind, "square") {
        let size = maxf(3.0f64, ms.font_size * 0.35f64)
        let mx = x + (w - size) / 2.0f64 - ms.font_size * 0.1f64
        let my = y + fm.ascent - fm.x_height / 2.0f64 - size / 2.0f64
        if str.eq(kind, "square") {
            fill(p, mx, my, size, size, ms.color)
        } else {
            let r = f32(size / 2.0f64)
            let rr = geo.RRect { rect: grect(mx, my, size, size), top_left: geo.Radius { x: r, y: r }, top_right: geo.Radius { x: r, y: r }, bottom_right: geo.Radius { x: r, y: r }, bottom_left: geo.Radius { x: r, y: r } }
            if str.eq(kind, "disc") {
                emit(p, scene.Command { FillPath: scene.FillPath { path: rrect_path(p.a, rr), brush: solid(ms.color) } })
            } else {
                emit(p, scene.Command { StrokePath: scene.StrokePath { path: rrect_path(p.a, rr), brush: solid(ms.color), stroke: pt.Stroke { width: 1.0f32, cap: .Butt, join: .Miter, miter_limit: 4.0f32 } } })
            }
        }
        ret
    }
    paint_text_run(p, mb, text, x, y, w)
}

fn paint_inline_decor(p: *Painter, ob: u32, fr: layout.Frag, cx: f64, cy: f64) {
    let s = layout.st(p.l, p.l.boxes.items[usize(ob)].style)
    if s.visibility != .Visible { ret }
    let x = cx + fr.x
    let y = cy + fr.y
    fill(p, x, y, fr.w, fr.h, s.background_color)
    var bt = 0.0f64
    var bbm = 0.0f64
    var bl = 0.0f64
    var br = 0.0f64
    if has_border(s, 0usize) { bt = s.border_width[0usize] }
    if has_border(s, 2usize) { bbm = s.border_width[2usize] }
    if fr.first && has_border(s, 3usize) { bl = s.border_width[3usize] }
    if fr.last && has_border(s, 1usize) { br = s.border_width[1usize] }
    if bt > 0.0f64 { fill(p, x, y, fr.w, bt, border_color_of(s, 0usize)) }
    if bbm > 0.0f64 { fill(p, x, y + fr.h - bbm, fr.w, bbm, border_color_of(s, 2usize)) }
    if bl > 0.0f64 { fill(p, x, y + bt, bl, fr.h - bt - bbm, border_color_of(s, 3usize)) }
    if br > 0.0f64 { fill(p, x + fr.w - br, y + bt, br, fr.h - bt - bbm, border_color_of(s, 1usize)) }
}

// The lines of block container `b`, whose border box is at (ax, ay).
fn paint_lines(p: *Painter, b: u32, ax: f64, ay: f64) {
    let bb = &p.l.boxes.items[usize(b)]
    if bb.line_count == 0u32 { ret }
    let cx = ax + bb.border[3usize] + bb.padding[3usize]
    let cy = ay + bb.border[0usize] + bb.padding[0usize]
    var li = 0usize
    while li < usize(bb.line_count) {
        let ln = p.l.lines.items[usize(bb.line_first) + li]
        li += 1usize
        if p.moved == 0usize && (cy + ln.y > p.vy + p.vh + 2.0f64 || cy + ln.y + ln.h < p.vy - 2.0f64) { continue }
        // Inline box backgrounds first, outer boxes under inner ones (inner boxes close first, so run backwards).
        var fi = usize(ln.frag_count)
        while fi > 0usize {
            fi -= 1usize
            let fr = p.l.frags.items[usize(ln.frag_first) + fi]
            if fr.kind == .Segment { paint_inline_decor(p, fr.box, fr, cx, cy) }
        }
        fi = 0usize
        while fi < usize(ln.frag_count) {
            let fr = p.l.frags.items[usize(ln.frag_first) + fi]
            fi += 1usize
            if fr.kind == .Text {
                paint_text_run(p, fr.box, fr.text, cx + fr.x, cy + fr.y, fr.w)
            } else if fr.kind == .Marker {
                paint_marker(p, fr.box, fr.text, cx + fr.x, cy + fr.y, fr.w)
            } else if fr.kind == .Atomic {
                let ab = &p.l.boxes.items[usize(fr.box)]
                paint_atomic(p, fr.box, ax + ab.x, ay + ab.y)
            }
        }
    }
}

// --- Replaced content.

fn paint_replaced(p: *Painter, b: u32, x: f64, y: f64) {
    let node = p.l.boxes.items[usize(b)].node
    if node == layout.NONE { ret }
    let env = p.env
    let img = env.image(env.ctx, node)
    if !img.found || img.width <= 0.0f32 || img.height <= 0.0f32 { ret }
    let bb = &p.l.boxes.items[usize(b)]
    let s = layout.st(p.l, bb.style)
    if s.visibility != .Visible { ret }
    let cx = x + bb.border[3usize] + bb.padding[3usize]
    let cy = y + bb.border[0usize] + bb.padding[0usize]
    let cw = maxf(0.0f64, bb.w - bb.border[1usize] - bb.border[3usize] - bb.padding[1usize] - bb.padding[3usize])
    let ch = maxf(0.0f64, bb.h - bb.border[0usize] - bb.border[2usize] - bb.padding[0usize] - bb.padding[2usize])
    if cw <= 0.0f64 || ch <= 0.0f64 { ret }
    let iw = f64(img.width)
    let ih = f64(img.height)
    let fit = first_token(p.a, s, "object-fit")
    var dw = cw
    var dh = ch
    if str.eq(fit, "contain") || str.eq(fit, "scale-down") {
        var k = minf(cw / iw, ch / ih)
        if str.eq(fit, "scale-down") && k > 1.0f64 { k = 1.0f64 }
        dw = iw * k
        dh = ih * k
    } else if str.eq(fit, "cover") {
        let k2 = maxf(cw / iw, ch / ih)
        dw = iw * k2
        dh = ih * k2
    } else if str.eq(fit, "none") {
        dw = iw
        dh = ih
    }
    // object-position defaults to the centre.
    var fx = 0.5f64
    var fy = 0.5f64
    let (pos, has_pos) = geom.extra_of(s, "object-position")
    if has_pos {
        let (px, py) = cv.parse_transform_origin(p.a, pos)
        fx = px
        fy = py
    }
    let dx = cx + (cw - dw) * fx
    let dy = cy + (ch - dh) * fy
    save(p)
    emit(p, scene.Command { Clip: scene.Clip { Rect: grect(cx, cy, cw, ch) } })
    emit(p, scene.Command { Image: scene.DrawImage { texture: img.texture, source: geo.rect(0.0f32, 0.0f32, img.width, img.height), destination: grect(dx, dy, dw, dh), opacity: 1.0f32 } })
    restore(p)
}

// --- Extents, clips and culling.

fn is_plain_inline(l: *const layout.Layout, b: u32) -> bool {
    let bb = &l.boxes.items[usize(b)]
    ret bb.inline_level && bb.inner == .Flow
}

fn clips_overflow(s: *const style.Style) -> bool { ret s.overflow_x != .Visible || s.overflow_y != .Visible }

// The union of a box's border box, its lines and its descendants' extents, in its own border-box coordinates
// (`ext[4b..4b+4]` = x0, y0, x1, y1). A clipping box bounds its content.
fn compute_ext(p: *Painter, b: u32) {
    let bb = &p.l.boxes.items[usize(b)]
    var x0 = 0.0f64
    var y0 = 0.0f64
    var x1 = bb.w
    var y1 = bb.h
    let s = layout.st(p.l, bb.style)
    var pad = 2.0f64
    let (sh, has_sh) = geom.extra_of(s, "box-shadow")
    if (has_sh && !str.eq(cv.lower(p.a, cv.trim_ws(sh)), "none")) || s.outline_style != .None { pad = 96.0f64 }
    let clip = clips_overflow(s) && bb.parent != layout.NONE && p.l.boxes.items[usize(bb.parent)].parent != layout.NONE
    var kid = bb.first
    while kid != layout.NONE {
        compute_ext(p, kid)
        let kb = &p.l.boxes.items[usize(kid)]
        if !clip && kb.inner != .Text {
            let k = usize(kid) * 4usize
            x0 = minf(x0, kb.x + p.ext[k])
            y0 = minf(y0, kb.y + p.ext[k + 1usize])
            x1 = maxf(x1, kb.x + p.ext[k + 2usize])
            y1 = maxf(y1, kb.y + p.ext[k + 3usize])
        }
        kid = kb.next
    }
    if !clip {
        var li = 0usize
        while li < usize(bb.line_count) {
            let ln = p.l.lines.items[usize(bb.line_first) + li]
            let ox = bb.border[3usize] + bb.padding[3usize]
            let oy = bb.border[0usize] + bb.padding[0usize]
            x0 = minf(x0, ox + ln.x)
            y0 = minf(y0, oy + ln.y)
            x1 = maxf(x1, ox + ln.x + ln.w)
            y1 = maxf(y1, oy + ln.y + ln.h)
            li += 1usize
        }
    }
    let k2 = usize(b) * 4usize
    p.ext[k2] = x0 - pad
    p.ext[k2 + 1usize] = y0 - pad
    p.ext[k2 + 2usize] = x1 + pad
    p.ext[k2 + 3usize] = y1 + pad
}

// Whether box `b` at (ax, ay) lies wholly outside the view (not decided inside a transformed space).
fn outside_view(p: *Painter, b: u32, ax: f64, ay: f64) -> bool {
    if p.moved > 0usize { ret false }
    let k = usize(b) * 4usize
    if ax + p.ext[k + 2usize] < p.vx || ax + p.ext[k] > p.vx + p.vw { ret true }
    if ay + p.ext[k + 3usize] < p.vy || ay + p.ext[k + 1usize] > p.vy + p.vh { ret true }
    ret false
}

// Starts the clip of a box that clips its overflow (the padding box, rounded with the border radius); the root
// element's overflow belongs to the viewport and is not applied.
fn push_overflow_clip(p: *Painter, b: u32, ax: f64, ay: f64) -> bool {
    let bb = &p.l.boxes.items[usize(b)]
    let s = layout.st(p.l, bb.style)
    if !clips_overflow(s) || bb.parent == layout.NONE || p.l.boxes.items[usize(bb.parent)].parent == layout.NONE { ret false }
    if bb.inner == .Table || bb.inner == .Row || bb.inner == .RowGroup { ret false }
    if bb.first == layout.NONE && bb.line_count == 0u32 { ret false }
    save(p)
    if has_radius(s) {
        emit(p, scene.Command { Clip: scene.Clip { Rounded: region_rrect(s, ax, ay, bb.w, bb.h, bb.border[0usize], bb.border[1usize], bb.border[2usize], bb.border[3usize]) } })
    } else {
        emit(p, scene.Command { Clip: scene.Clip { Rect: grect(ax + bb.border[3usize], ay + bb.border[0usize], bb.w - bb.border[1usize] - bb.border[3usize], bb.h - bb.border[0usize] - bb.border[2usize]) } })
    }
    ret true
}

fn is_entry(p: *Painter, b: u32) -> bool {
    let bb = &p.l.boxes.items[usize(b)]
    if bb.inner == .Text || bb.inner == .Marker { ret false }
    let s = layout.st(p.l, bb.style)
    ret s.position != .Static || geom.is_stacking_context(p.a, p.l, b)
}

// --- The paint layers of CSS 2.1 Appendix E.

// Step 3: backgrounds and borders of in-flow, non-positioned block-level descendants, and their replaced content.
fn paint_block_backgrounds(p: *Painter, b: u32, ax: f64, ay: f64) {
    var kid = p.l.boxes.items[usize(b)].first
    while kid != layout.NONE {
        let kb = &p.l.boxes.items[usize(kid)]
        let nxt = kb.next
        let ks = layout.st(p.l, kb.style)
        if kb.inner != .Text && kb.inner != .Marker && !kb.inline_level && ks.floating == .None && !is_entry(p, kid) {
            let cx = ax + kb.x
            let cy = ay + kb.y
            if !outside_view(p, kid, cx, cy) {
                paint_decor(p, kid, cx, cy)
                if kb.inner == .Replaced { paint_replaced(p, kid, cx, cy) }
                let clip = push_overflow_clip(p, kid, cx, cy)
                paint_block_backgrounds(p, kid, cx, cy)
                if clip { restore(p) }
            }
        }
        kid = nxt
    }
}

// Step 4: floats, each painted as if it were a stacking context of its own.
fn paint_floats(p: *Painter, b: u32, ax: f64, ay: f64) {
    var kid = p.l.boxes.items[usize(b)].first
    while kid != layout.NONE {
        let kb = &p.l.boxes.items[usize(kid)]
        let nxt = kb.next
        let ks = layout.st(p.l, kb.style)
        if kb.inner != .Text && kb.inner != .Marker && !is_entry(p, kid) {
            let cx = ax + kb.x
            let cy = ay + kb.y
            if ks.floating != .None && ks.position != .Absolute && ks.position != .Fixed {
                paint_atomic(p, kid, cx, cy)
            } else if (!kb.inline_level || is_plain_inline(p.l, kid)) && !outside_view(p, kid, cx, cy) {
                let clip = push_overflow_clip(p, kid, cx, cy)
                paint_floats(p, kid, cx, cy)
                if clip { restore(p) }
            }
        }
        kid = nxt
    }
}

// Step 5: inline content of the container and of its in-flow block descendants: lines, markers, outlines.
fn paint_inline_layer(p: *Painter, b: u32, ax: f64, ay: f64) {
    let bb = &p.l.boxes.items[usize(b)]
    paint_lines(p, b, ax, ay)
    var kid = bb.first
    while kid != layout.NONE {
        let kb = &p.l.boxes.items[usize(kid)]
        let nxt = kb.next
        let ks = layout.st(p.l, kb.style)
        if kb.inner == .Marker && !kb.inline_level {
            paint_marker(p, kid, kb.text, ax + kb.x, ay + kb.y, kb.w)
        } else if kb.inner != .Text && !kb.inline_level && ks.floating == .None && !is_entry(p, kid) {
            let cx = ax + kb.x
            let cy = ay + kb.y
            if !outside_view(p, kid, cx, cy) {
                let clip = push_overflow_clip(p, kid, cx, cy)
                paint_inline_layer(p, kid, cx, cy)
                if clip { restore(p) }
                paint_outline(p, layout.st(p.l, kb.style), cx, cy, kb.w, kb.h)
            }
        }
        kid = nxt
    }
}

// A float, an inline-block or a positioned box with z-index auto: its own background, then the layers inside it.
fn paint_atomic(p: *Painter, b: u32, x: f64, y: f64) {
    if outside_view(p, b, x, y) { ret }
    let bb = &p.l.boxes.items[usize(b)]
    paint_decor(p, b, x, y)
    if bb.inner == .Replaced {
        paint_replaced(p, b, x, y)
        paint_outline(p, layout.st(p.l, bb.style), x, y, bb.w, bb.h)
        ret
    }
    let clip = push_overflow_clip(p, b, x, y)
    paint_block_backgrounds(p, b, x, y)
    paint_floats(p, b, x, y)
    paint_inline_layer(p, b, x, y)
    if clip { restore(p) }
    paint_outline(p, layout.st(p.l, bb.style), x, y, bb.w, bb.h)
}

// --- Stacking contexts.

fn collect(p: *Painter, root: u32, out: *list.List[Entry]) {
    var kid = p.l.boxes.items[usize(root)].first
    while kid != layout.NONE {
        let kb = &p.l.boxes.items[usize(kid)]
        let nxt = kb.next
        if kb.inner != .Text && kb.inner != .Marker {
            let ks = layout.st(p.l, kb.style)
            if geom.is_stacking_context(p.a, p.l, kid) {
                var z = 0i64
                if ks.position != .Static && !ks.z_index_auto { z = ks.z_index }
                let pushed = list.push[Entry](out, Entry { box: kid, z: z, real: true })
            } else if ks.position != .Static {
                let pushed = list.push[Entry](out, Entry { box: kid, z: 0i64, real: false })
                collect(p, kid, out)
            } else {
                collect(p, kid, out)
            }
        }
        kid = nxt
    }
}

// Insertion sort by z (stable), for the small lists a context has.
fn sort_entries(items: []Entry, n: usize) {
    var i = 1usize
    while i < n {
        let e = items[i]
        var j = i
        while j > 0usize && items[j - 1usize].z > e.z {
            items[j] = items[j - 1usize]
            j -= 1usize
        }
        items[j] = e
        i += 1usize
    }
}

// The ancestor clips that apply to a positioned box: from its parent up to its containing block.
fn push_entry_clips(p: *Painter, e: u32, root: u32, rx: f64, ry: f64) -> usize {
    let (rox, roy) = layout.abs_origin(p.l, root)
    var chain: [32]u32 = zero
    var n = 0usize
    var cur = p.l.boxes.items[usize(e)].parent
    var fixed = layout.st(p.l, p.l.boxes.items[usize(e)].style).position == .Fixed
    while cur != layout.NONE && cur != root && n < 32usize && !fixed {
        let cs = layout.st(p.l, p.l.boxes.items[usize(cur)].style)
        if clips_overflow(cs) {
            chain[n] = cur
            n += 1usize
        }
        if cs.position != .Static { break }
        cur = p.l.boxes.items[usize(cur)].parent
    }
    var pushed = 0usize
    var i = n
    while i > 0usize {
        i -= 1usize
        let cb = chain[i]
        let (ox, oy) = layout.abs_origin(p.l, cb)
        if push_overflow_clip(p, cb, rx + ox - rox, ry + oy - roy) { pushed += 1usize }
    }
    ret pushed
}

fn paint_entry(p: *Painter, en: Entry, root: u32, rx: f64, ry: f64) {
    let (rox, roy) = layout.abs_origin(p.l, root)
    let (eox, eoy) = layout.abs_origin(p.l, en.box)
    var ex = rx + eox - rox
    var ey = ry + eoy - roy
    let eb = &p.l.boxes.items[usize(en.box)]
    let es = layout.st(p.l, eb.style)
    if es.position == .Fixed && p.moved == 0usize {
        ex += p.scroll_x
        ey += p.scroll_y
    }
    if es.visibility != .Visible && !en.real && eb.first == layout.NONE { ret }
    if outside_view(p, en.box, ex, ey) { ret }
    let clips = push_entry_clips(p, en.box, root, rx, ry)
    if !en.real {
        paint_atomic(p, en.box, ex, ey)
    } else {
        let (m, has_t) = geom.box_transform(p.a, p.l, en.box)
        if es.opacity < 1.0f64 {
            // The layer covers the subtree's extent, kept to the view when untransformed.
            let k = usize(en.box) * 4usize
            var lx = ex + p.ext[k]
            var ly = ey + p.ext[k + 1usize]
            var lw = p.ext[k + 2usize] - p.ext[k]
            var lh = p.ext[k + 3usize] - p.ext[k + 1usize]
            if has_t || p.moved > 0usize {
                lx = -100000.0f64
                ly = -100000.0f64
                lw = 200000.0f64
                lh = 200000.0f64
            } else {
                let x0 = maxf(lx, p.vx)
                let y0 = maxf(ly, p.vy)
                let x1 = minf(lx + lw, p.vx + p.vw)
                let y1 = minf(ly + lh, p.vy + p.vh)
                lx = x0
                ly = y0
                lw = maxf(0.0f64, x1 - x0)
                lh = maxf(0.0f64, y1 - y0)
            }
            emit(p, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: grect(lx, ly, lw, lh), opacity: f32(es.opacity) } })
        } else {
            save(p)
        }
        if has_t {
            let t = geo.Transform { m00: f32(m[0usize]), m01: f32(m[2usize]), m02: f32(m[4usize] + ex), m10: f32(m[1usize]), m11: f32(m[3usize]), m12: f32(m[5usize] + ey) }
            emit(p, scene.Command { Transform: t })
            p.moved += 1usize
            paint_context(p, en.box, 0.0f64, 0.0f64)
            p.moved -= 1usize
        } else {
            paint_context(p, en.box, ex, ey)
        }
        restore(p)
    }
    var i = 0usize
    while i < clips {
        restore(p)
        i += 1usize
    }
}

// Paints stacking context `root` with its border box at (x, y): its own decor, negative layers, the normal-flow
// layers, then the z-index 0 and positive ones.
fn paint_context(p: *Painter, root: u32, x: f64, y: f64) {
    let (lm, le) = list.init[Entry](p.a, 16usize)
    if le != ok {
        p.status = le
        ret
    }
    var entries = lm
    collect(p, root, &entries)
    sort_entries(entries.items, entries.len)
    let rb = &p.l.boxes.items[usize(root)]
    if rb.parent != layout.NONE { paint_decor(p, root, x, y) }
    let clip = push_overflow_clip(p, root, x, y)
    var i = 0usize
    while i < entries.len {
        if entries.items[i].z < 0i64 { paint_entry(p, entries.items[i], root, x, y) }
        i += 1usize
    }
    if rb.inner == .Replaced { paint_replaced(p, root, x, y) }
    paint_block_backgrounds(p, root, x, y)
    paint_floats(p, root, x, y)
    paint_inline_layer(p, root, x, y)
    i = 0usize
    while i < entries.len {
        if entries.items[i].z >= 0i64 { paint_entry(p, entries.items[i], root, x, y) }
        i += 1usize
    }
    if clip { restore(p) }
    if rb.parent != layout.NONE { paint_outline(p, layout.st(p.l, rb.style), x, y, rb.w, rb.h) }
}

// The canvas background: the root element's, else the body's, over the whole view.
fn paint_canvas(p: *Painter) {
    let vp = p.l.root
    let html_box = p.l.boxes.items[usize(vp)].first
    if html_box == layout.NONE { ret }
    let hs = layout.st(p.l, p.l.boxes.items[usize(html_box)].style)
    var c = hs.background_color
    if alpha_of(c) == 0u32 {
        var kid = p.l.boxes.items[usize(html_box)].first
        while kid != layout.NONE {
            let kb = &p.l.boxes.items[usize(kid)]
            if kb.node != layout.NONE && str.eq(p.l.d.nodes[usize(kb.node)].name, "body") {
                c = layout.st(p.l, kb.style).background_color
                break
            }
            kid = kb.next
        }
    }
    fill(p, p.vx, p.vy, p.vw, p.vh, c)
}

// Paints `view` (document coordinates) of the layout into `b`. `scroll_x`, `scroll_y` is where fixed boxes sit.
fn paint(a: *mem.Arena, l: *const layout.Layout, env: PaintEnv, b: *scene.Builder, view: geo.Rect, scroll_x: f64, scroll_y: f64) -> err {
    if l.root == layout.NONE { ret ok }
    let (ext, ee) = mem.alloc[f64](a, l.boxes.len * 4usize + 4usize)
    if ee != ok { ret ee }
    var p = Painter { l: l, a: a, env: env, b: b, vx: f64(view.x), vy: f64(view.y), vw: f64(view.width), vh: f64(view.height), scroll_x: scroll_x, scroll_y: scroll_y, ext: ext, status: ok, moved: 0usize }
    compute_ext(&p, l.root)
    save(&p)
    emit(&p, scene.Command { Transform: geo.transform_translate(0.0f32 - view.x, 0.0f32 - view.y) })
    paint_canvas(&p)
    paint_context(&p, l.root, 0.0f64, 0.0f64)
    restore(&p)
    ret p.status
}
