// `e.fmt.css.layout` with an Ahem-like measure (every character is one em wide, ascent 0.8 em, descent 0.2 em): block
// stacking and margin collapsing, auto margins, percentages and box-sizing, min/max sizes, text wrapping and alignment,
// floats and clearance, inline-blocks, relative and absolute positioning, list markers, replaced content. Each check
// has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.css.layout as layout
use e.fmt.css.geom as geom
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

fn near_rect(r: geom.Rect, x: f64, y: f64, w: f64, h: f64) -> bool {
    ret near(r.x, x) && near(r.y, y) && near(r.w, w) && near(r.h, h)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1. A translation moves the bounding box.
    let (p1, ok1) = build(a, "<div id=a style=\"width:100px;height:50px;transform:translate(10px,20px)\"></div>", "")
    if !ok1 || !near_rect(geom.bounding_rect(a, &p1.lay, box_of(p1, "a")), 10.0f64, 20.0f64, 100.0f64, 50.0f64) { os.exit(1) }
    // 2. Scaling is about the centre; the layout rectangle does not change.
    let (p2, ok2) = build(a, "<div id=a style=\"width:100px;height:50px;transform:scale(2)\"></div>", "")
    if !ok2 || !near_rect(geom.bounding_rect(a, &p2.lay, box_of(p2, "a")), -50.0f64, -25.0f64, 200.0f64, 100.0f64) { os.exit(2) }
    if !near_rect(geom.layout_rect(&p2.lay, box_of(p2, "a")), 0.0f64, 0.0f64, 100.0f64, 50.0f64) { os.exit(3) }
    // 3. A quarter turn swaps the extents about the centre.
    let (p3, ok3) = build(a, "<div id=a style=\"width:100px;height:50px;transform:rotate(90deg)\"></div>", "")
    if !ok3 || !near_rect(geom.bounding_rect(a, &p3.lay, box_of(p3, "a")), 25.0f64, -25.0f64, 50.0f64, 100.0f64) { os.exit(4) }
    // 4. Transforms compose down the tree, and transform-origin moves the pivot.
    let (p4, ok4) = build(a, "<div style=\"transform:translate(10px,0)\"><div id=c style=\"width:20px;height:20px;transform-origin:0 0;transform:scale(2)\"></div></div>", "")
    if !ok4 || !near_rect(geom.bounding_rect(a, &p4.lay, box_of(p4, "c")), 10.0f64, 0.0f64, 40.0f64, 40.0f64) { os.exit(5) }
    // 5. offset* is relative to the padding edge of the positioned ancestor.
    let (p5, ok5) = build(a, "<div id=p style=\"position:relative;margin-left:20px;padding:5px;border:2px solid\"><div id=c style=\"height:10px;margin:3px\"></div></div>", "")
    if !ok5 { os.exit(6) }
    let off5 = geom.offset_pos(&p5.lay, box_of(p5, "c"))
    if !near(off5.x, 8.0f64) || !near(off5.y, 8.0f64) { os.exit(7) }
    // 6. Scroll sizes.
    let (p6, ok6) = build(a, "<div id=s style=\"width:100px;height:50px;overflow:auto\"><div style=\"width:300px;height:200px\"></div></div>", "")
    if !ok6 { os.exit(8) }
    let sc6 = geom.scroll_size(&p6.lay, box_of(p6, "s"))
    let cl6 = geom.client_size(&p6.lay, box_of(p6, "s"))
    if !near(sc6.x, 300.0f64) || !near(sc6.y, 200.0f64) || !near(cl6.x, 100.0f64) || !near(cl6.y, 50.0f64) { os.exit(9) }
    if !geom.is_scroll_container(&p6.lay, box_of(p6, "s")) { os.exit(10) }
    // 7. Hit testing prefers the positioned box on top, and respects transforms and clipping.
    let (p7, ok7) = build(a, "<div id=a style=\"width:100px;height:100px\"></div><div id=b style=\"position:absolute;left:0;top:0;width:50px;height:50px\"></div>", "")
    if !ok7 { os.exit(11) }
    if geom.hit_test(a, &p7.lay, p7.lay.root, 25.0f64, 25.0f64) != box_of(p7, "b") { os.exit(12) }
    if geom.hit_test(a, &p7.lay, p7.lay.root, 75.0f64, 75.0f64) != box_of(p7, "a") { os.exit(13) }
    let (p8, ok8) = build(a, "<div id=a style=\"width:100px;height:100px;transform:scale(0.5);transform-origin:0 0\"></div>", "")
    if !ok8 || geom.hit_test(a, &p8.lay, p8.lay.root, 40.0f64, 40.0f64) != box_of(p8, "a") || geom.hit_test(a, &p8.lay, p8.lay.root, 60.0f64, 60.0f64) == box_of(p8, "a") { os.exit(14) }
    let (p9, ok9) = build(a, "<div style=\"width:50px;height:50px;overflow:hidden\"><div id=c style=\"width:200px;height:200px\"></div></div>", "")
    if !ok9 || geom.hit_test(a, &p9.lay, p9.lay.root, 100.0f64, 100.0f64) == box_of(p9, "c") { os.exit(15) }
    // 10. Sticky offsets keep the box inside the scrollport and its containing block.
    let (p10, ok10) = build(a, "<div style=\"height:100px\"></div><div id=s style=\"position:sticky;top:0;height:20px\"></div><div style=\"height:300px\"></div>", "")
    if !ok10 { os.exit(16) }
    let sh10 = geom.sticky_shift(&p10.lay, box_of(p10, "s"), geom.Rect { x: 0.0f64, y: 150.0f64, w: 800.0f64, h: 600.0f64 }, geom.Rect { x: 0.0f64, y: 0.0f64, w: 800.0f64, h: 1000.0f64 })
    if !near(sh10.y, 50.0f64) { os.exit(17) }
    // 11. Stacking contexts.
    let (p11, ok11) = build(a, "<div id=a style=\"opacity:0.5\"></div><div id=b></div><div id=c style=\"position:relative;z-index:1\"></div>", "")
    if !ok11 || !geom.is_stacking_context(a, &p11.lay, box_of(p11, "a")) || geom.is_stacking_context(a, &p11.lay, box_of(p11, "b")) || !geom.is_stacking_context(a, &p11.lay, box_of(p11, "c")) { os.exit(18) }
    ret ok
}
