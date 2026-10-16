// `e.fmt.css.layout` with an Ahem-like measure (every character is one em wide, ascent 0.8 em, descent 0.2 em): block
// stacking and margin collapsing, auto margins, percentages and box-sizing, min/max sizes, text wrapping and alignment,
// floats and clearance, inline-blocks, relative and absolute positioning, list markers, replaced content. Each check
// has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.css.layout as layout
use e.fmt.css.paint as cpaint
use e.gfx.geometry as geo
use e.gfx.scene as scene
use e.text.layout as tl
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.fmt.html as html

fn chars_of(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn ahem_width(ctx: *void, s: *const style.Style, text: str) -> f64 { ret f64(chars_of(text)) * s.font_size }

fn ahem_metrics(ctx: *void, s: *const style.Style) -> layout.FontMetrics {
    ret layout.FontMetrics { ascent: 0.8f64 * s.font_size, descent: 0.2f64 * s.font_size, line_gap: 0.0f64, x_height: 0.5f64 * s.font_size }
}

fn ahem_intrinsic(ctx: *void, node: html.NodeId) -> layout.Intrinsic {
    let d = mem.cast[*const dom.Dom](ctx)
    var out = layout.Intrinsic { kind: 1u8, has_width: false, width: 0.0f64, has_height: false, height: 0.0f64, ratio: 0.0f64 }
    let (w, has_w) = dom.get_attribute(d, node, "width")
    let (h, has_h) = dom.get_attribute(d, node, "height")
    if has_w {
        let (n, good) = str.parse_i64(w)
        if good == ok {
            out.has_width = true
            out.width = f64(n)
        }
    }
    if has_h {
        let (n, good) = str.parse_i64(h)
        if good == ok {
            out.has_height = true
            out.height = f64(n)
        }
    }
    if out.has_width && out.has_height && out.height > 0.0f64 { out.ratio = out.width / out.height }
    ret out
}

fn near(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = -d }
    ret d < 0.01f64
}

fn options() -> html.Options {
    ret html.Options { max_bytes: 65536usize, max_nodes: 1024usize, max_attributes: 32usize, max_depth: 64u16, preserve_comments: false }
}

type Page = struct { tree: dom.Dom, styles: []style.Style, lay: layout.Layout }

// Parses, styles (a reset plus `css`) and lays out `body` in an 800x600 viewport.
fn build(a: *mem.Arena, body: str, css: str) -> (*Page, bool) {
    let (cell, ce) = mem.alloc[Page](a, 1usize)
    if ce != ok { ret (zero, false) }
    let pg = &cell[0usize]
    let (src1, e0) = str.concat(a, "<html><head></head><body>", body)
    if e0 != ok { ret (pg, false) }
    let (src, e1) = str.concat(a, src1, "</body></html>")
    if e1 != ok { ret (pg, false) }
    let (d, de) = dom.parse(a, src, options(), 16usize)
    if de != ok { ret (pg, false) }
    pg.tree = d
    let (styles, se) = mem.alloc[style.Style](a, pg.tree.used)
    if se != ok { ret (pg, false) }
    pg.styles = styles
    var ctx = style.new_context(a, 800.0f64, 600.0f64)
    let reset = "html, body, div, p, ul, ol, li, h1, h2 { margin: 0; padding: 0; }"
    var sheets: [2]str = zero
    sheets[0usize] = reset
    sheets[1usize] = css
    if style.compute_document(&ctx, &pg.tree, sheets[0..], pg.styles) != ok { ret (pg, false) }
    let m = layout.Measure { ctx: mem.cast[*void](&pg.tree), width: ahem_width, metrics: ahem_metrics, intrinsic: ahem_intrinsic }
    let (lay, le) = layout.layout_document(a, &pg.tree, pg.styles, m, 800.0f64, 600.0f64)
    if le != ok { ret (pg, false) }
    pg.lay = lay
    ret (pg, true)
}

type Rect = struct { x: f64, y: f64, w: f64, h: f64, found: bool }

// The border box of the element with this id in document coordinates.
fn rect_of(pg: *const Page, id: str) -> Rect {
    let node = dom.get_element_by_id(&pg.tree, pg.tree.root, id)
    var none = Rect { x: 0.0f64, y: 0.0f64, w: 0.0f64, h: 0.0f64, found: false }
    if node == html.NONE { ret none }
    var i = 0usize
    while i < pg.lay.boxes.len {
        let b = &pg.lay.boxes.items[i]
        if b.node == node && !b.anonymous && b.inner != layout.Inner.Text {
            let (ax, ay) = layout.abs_origin(&pg.lay, u32(i))
            ret Rect { x: ax, y: ay, w: b.w, h: b.h, found: true }
        }
        i += 1usize
    }
    ret none
}

// The index of the (non-anonymous) box of the element with this id, or the box count when there is none.
fn box_of(pg: *const Page, id: str) -> u32 {
    let node = dom.get_element_by_id(&pg.tree, pg.tree.root, id)
    var i = 0usize
    while i < pg.lay.boxes.len {
        let b = &pg.lay.boxes.items[i]
        if b.node == node && !b.anonymous && b.inner != layout.Inner.Text { ret u32(i) }
        i += 1usize
    }
    ret u32(pg.lay.boxes.len)
}

fn is_rect(r: Rect, x: f64, y: f64, w: f64, h: f64) -> bool {
    ret r.found && near(r.x, x) && near(r.y, y) && near(r.w, w) && near(r.h, h)
}

type Counter = struct { texts: usize, last: str }

fn env_text(ctx: *void, s: *const style.Style, t: str) -> *const tl.Layout {
    let c = mem.cast[*Counter](ctx)
    c.texts += 1usize
    c.last = t
    ret zero
}

fn env_image(ctx: *void, n: html.NodeId) -> cpaint.ImageRef { ret zero }

fn env_url_image(ctx: *void, url: str) -> cpaint.ImageRef { ret zero }

// Paints the page into a fresh builder and returns the commands.
fn paint_page(a: *mem.Arena, pg: *Page, counter: *Counter, view: geo.Rect) -> ([]const scene.Command, bool) {
    let (bv, be) = scene.builder(a, 4096usize)
    if be != ok { ret (zero, false) }
    var b = bv
    let env = cpaint.PaintEnv { ctx: mem.cast[*void](counter), text: env_text, image: env_image, url_image: env_url_image }
    if cpaint.paint(a, &pg.lay, env, &b, view, 0.0f64, 0.0f64) != ok { ret (zero, false) }
    let dl = scene.finish(&b)
    ret (dl.commands, true)
}

fn fill_count(cmds: []const scene.Command) -> usize {
    var n = 0usize
    var i = 0usize
    while i < cmds.len {
        if cmds[i].tag == .FillRect { n += 1usize }
        i += 1usize
    }
    ret n
}

// The n-th FillRect (0-based), as a rectangle and a red channel.
fn nth_fill(cmds: []const scene.Command, n: usize) -> (geo.Rect, f32, f32, bool) {
    var seen = 0usize
    var i = 0usize
    while i < cmds.len {
        switch cmds[i] {
        case .FillRect as f:
            if seen == n {
                var red = 0.0f32
                var green = 0.0f32
                switch f.brush {
                case .Solid as c:
                    red = c.red
                    green = c.green
                default:
                    red += 0.0f32
                }
                ret (f.rect, red, green, true)
            }
            seen += 1usize
        default:
            seen += 0usize
        }
        i += 1usize
    }
    ret (geo.rect(0.0, 0.0, 0.0, 0.0), 0.0, 0.0, false)
}

fn count_opacity(cmds: []const scene.Command) -> usize {
    var n = 0usize
    var i = 0usize
    while i < cmds.len {
        if cmds[i].tag == .OpacityLayer { n += 1usize }
        i += 1usize
    }
    ret n
}

fn count_transform(cmds: []const scene.Command) -> usize {
    var n = 0usize
    var i = 0usize
    while i < cmds.len {
        if cmds[i].tag == .Transform { n += 1usize }
        i += 1usize
    }
    ret n
}

fn count_clip(cmds: []const scene.Command) -> usize {
    var n = 0usize
    var i = 0usize
    while i < cmds.len {
        if cmds[i].tag == .Clip { n += 1usize }
        i += 1usize
    }
    ret n
}

// The first FillRect whose brush is a linear gradient: its start x, end x and stop count.
fn first_linear(cmds: []const scene.Command) -> (f32, f32, usize, bool) {
    var i = 0usize
    while i < cmds.len {
        switch cmds[i] {
        case .FillRect as f:
            switch f.brush {
            case .Linear as g:
                ret (g.start.x, g.end.x, g.stops.len, true)
            default:
                i += 0usize
            }
        default:
            i += 0usize
        }
        i += 1usize
    }
    ret (0.0, 0.0, 0usize, false)
}

fn has_radial(cmds: []const scene.Command) -> bool {
    var i = 0usize
    while i < cmds.len {
        switch cmds[i] {
        case .FillRect as f:
            switch f.brush {
            case .Radial as g:
                ret true
            default:
                i += 0usize
            }
        default:
            i += 0usize
        }
        i += 1usize
    }
    ret false
}

fn rect_is(r: geo.Rect, x: f32, y: f32, w: f32, h: f32) -> bool {
    ret near(f64(r.x), f64(x)) && near(f64(r.y), f64(y)) && near(f64(r.width), f64(w)) && near(f64(r.height), f64(h))
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter = Counter { texts: 0usize, last: "" }
    let view = geo.rect(0.0, 0.0, 800.0, 600.0)
    // 1. A background colour is one filled rectangle.
    let (p1, ok1) = build(a, "<div style=\"width:100px;height:50px;background:#f00\"></div>", "")
    if !ok1 { os.exit(1) }
    let (c1, pc1) = paint_page(a, p1, &counter, view)
    if !pc1 || fill_count(c1) != 1usize { os.exit(2) }
    let (r1, red1, green1, f1) = nth_fill(c1, 0usize)
    if !f1 || !rect_is(r1, 0.0, 0.0, 100.0, 50.0) || red1 < 0.99 || green1 > 0.01 { os.exit(3) }
    // 2. A solid border is four bands.
    let (p2, ok2) = build(a, "<div style=\"width:10px;height:10px;border:2px solid #00f\"></div>", "")
    if !ok2 { os.exit(4) }
    let (c2, pc2) = paint_page(a, p2, &counter, view)
    if !pc2 || fill_count(c2) != 4usize { os.exit(5) }
    let (top2, _r, _g, t2) = nth_fill(c2, 0usize)
    let (left2, _r2, _g2, l2) = nth_fill(c2, 3usize)
    if !t2 || !rect_is(top2, 0.0, 0.0, 14.0, 2.0) || !l2 || !rect_is(left2, 0.0, 2.0, 2.0, 10.0) { os.exit(6) }
    // 3. Positioned boxes paint by z-index, lowest first.
    let (p3, ok3) = build(a, "<div style=\"position:absolute;z-index:2;left:0;top:0;width:10px;height:10px;background:#f00\"></div><div style=\"position:absolute;z-index:1;left:20px;top:0;width:10px;height:10px;background:#0f0\"></div>", "")
    if !ok3 { os.exit(7) }
    let (c3, pc3) = paint_page(a, p3, &counter, view)
    if !pc3 || fill_count(c3) != 2usize { os.exit(8) }
    let (first3, fr3, fg3, f3) = nth_fill(c3, 0usize)
    if !f3 || fg3 < 0.99 || fr3 > 0.01 || !rect_is(first3, 20.0, 0.0, 10.0, 10.0) { os.exit(9) }
    // 4. Opacity opens a layer; a transform adds a Transform command.
    let (p4, ok4) = build(a, "<div style=\"opacity:0.5;width:10px;height:10px;background:#000\"></div>", "")
    if !ok4 { os.exit(10) }
    let (c4, pc4) = paint_page(a, p4, &counter, view)
    if !pc4 || count_opacity(c4) != 1usize { os.exit(11) }
    let (p5, ok5) = build(a, "<div style=\"transform:translate(10px,20px);width:10px;height:10px;background:#000\"></div>", "")
    if !ok5 { os.exit(12) }
    let (c5, pc5) = paint_page(a, p5, &counter, view)
    if !pc5 || count_transform(c5) != 2usize { os.exit(13) }
    // 5. Boxes outside the view are skipped.
    let (p6, ok6) = build(a, "<div style=\"height:2000px\"></div><div style=\"height:10px;background:#f00\"></div>", "")
    if !ok6 { os.exit(14) }
    let (c6, pc6) = paint_page(a, p6, &counter, view)
    if !pc6 || fill_count(c6) != 0usize { os.exit(15) }
    let (c6b, pc6b) = paint_page(a, p6, &counter, geo.rect(0.0, 1900.0, 800.0, 600.0))
    if !pc6b || fill_count(c6b) != 1usize { os.exit(16) }
    // 6. A radius clips the background; overflow clips the children.
    let (p7, ok7) = build(a, "<div style=\"width:20px;height:20px;border-radius:5px;background:#f00\"></div>", "")
    if !ok7 { os.exit(17) }
    let (c7, pc7) = paint_page(a, p7, &counter, view)
    if !pc7 || count_clip(c7) != 1usize { os.exit(18) }
    let (p8, ok8) = build(a, "<div style=\"width:20px;height:20px;overflow:hidden\"><div style=\"width:50px;height:50px;background:#f00\"></div></div>", "")
    if !ok8 { os.exit(19) }
    let (c8, pc8) = paint_page(a, p8, &counter, view)
    if !pc8 || count_clip(c8) == 0usize || fill_count(c8) != 1usize { os.exit(20) }
    // 7. An inline background covers its text; text is handed to the environment.
    let (p9, ok9) = build(a, "<div style=\"font-size:10px\"><span style=\"background:#0f0\">aaaa</span></div>", "")
    if !ok9 { os.exit(21) }
    counter.texts = 0usize
    let (c9, pc9) = paint_page(a, p9, &counter, view)
    if !pc9 || fill_count(c9) != 1usize || counter.texts != 1usize || !str.eq(counter.last, "aaaa") { os.exit(22) }
    let (r9, _r9r, g9, f9) = nth_fill(c9, 0usize)
    if !f9 || !near(f64(r9.width), 40.0f64) || g9 < 0.99 { os.exit(23) }
    // 8. The canvas takes the body background over the whole view.
    let (p10, ok10) = build(a, "<div style=\"height:10px\"></div>", "body { background: #0f0; }")
    if !ok10 { os.exit(24) }
    let (c10, pc10) = paint_page(a, p10, &counter, view)
    let (r10, _a10, g10, f10) = nth_fill(c10, 0usize)
    if !pc10 || !f10 || !rect_is(r10, 0.0, 0.0, 800.0, 600.0) || g10 < 0.99 { os.exit(25) }
    // 9. A linear gradient is one fill with a Linear brush along the gradient line; a radial one a Radial brush; a
    // background-size tiles the layer.
    let (p11, ok11) = build(a, "<div style=\"width:100px;height:50px;background:linear-gradient(to right, #f00, #00f)\"></div>", "")
    if !ok11 { os.exit(26) }
    let (c11, pc11) = paint_page(a, p11, &counter, view)
    let (gs, ge, gn, gf) = first_linear(c11)
    if !pc11 || !gf || !near(f64(gs), 0.0f64) || !near(f64(ge), 100.0f64) || gn < 2usize { os.exit(27) }
    let (p12, ok12) = build(a, "<div style=\"width:100px;height:50px;background:radial-gradient(circle at center, #fff, #000)\"></div>", "")
    if !ok12 { os.exit(28) }
    let (c12, pc12) = paint_page(a, p12, &counter, view)
    if !pc12 || !has_radial(c12) { os.exit(29) }
    let (p13, ok13) = build(a, "<div style=\"width:100px;height:50px;background:linear-gradient(#f00, #00f) 0 0 / 10px 10px\"></div>", "")
    if !ok13 { os.exit(30) }
    let (c13, pc13) = paint_page(a, p13, &counter, view)
    if !pc13 || fill_count(c13) != 50usize { os.exit(31) }
    ret ok
}
