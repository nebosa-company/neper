// `e.fmt.css.layout` with an Ahem-like measure (every character is one em wide, ascent 0.8 em, descent 0.2 em): block
// stacking and margin collapsing, auto margins, percentages and box-sizing, min/max sizes, text wrapping and alignment,
// floats and clearance, inline-blocks, relative and absolute positioning, list markers, replaced content. Each check
// has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.css.layout as layout
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

fn main(a: *mem.Arena, args: []str) -> err {
    // 1. Stacking and margin collapsing between siblings.
    let (p1, ok1) = build(a, "<div id=a style=\"height:50px;margin-bottom:10px\"></div><div id=b style=\"height:30px;margin-top:20px\"></div>", "")
    if !ok1 { os.exit(1) }
    if !is_rect(rect_of(p1, "a"), 0.0f64, 0.0f64, 800.0f64, 50.0f64) { os.exit(2) }
    if !is_rect(rect_of(p1, "b"), 0.0f64, 70.0f64, 800.0f64, 30.0f64) { os.exit(3) }
    // 2. Auto margins centre.
    let (p2, ok2) = build(a, "<div id=a style=\"width:200px;height:10px;margin:0 auto\"></div>", "")
    if !ok2 || !is_rect(rect_of(p2, "a"), 300.0f64, 0.0f64, 200.0f64, 10.0f64) { os.exit(4) }
    // 3. Padding, border, box-sizing.
    let (p3, ok3) = build(a, "<div id=a style=\"width:100px;height:20px;padding:10px;border:2px solid\"></div><div id=b style=\"box-sizing:border-box;width:100px;height:50px;padding:10px;border:2px solid\"></div>", "")
    if !ok3 { os.exit(5) }
    if !is_rect(rect_of(p3, "a"), 0.0f64, 0.0f64, 124.0f64, 44.0f64) { os.exit(6) }
    if !is_rect(rect_of(p3, "b"), 0.0f64, 44.0f64, 100.0f64, 50.0f64) { os.exit(7) }
    // 4. Percentages and min/max.
    let (p4, ok4) = build(a, "<div id=a style=\"width:50%;height:10px;max-width:300px\"></div><div id=b style=\"width:10px;min-width:40px;height:10px\"></div>", "")
    if !ok4 { os.exit(8) }
    if !is_rect(rect_of(p4, "a"), 0.0f64, 0.0f64, 300.0f64, 10.0f64) { os.exit(9) }
    if !is_rect(rect_of(p4, "b"), 0.0f64, 10.0f64, 40.0f64, 10.0f64) { os.exit(10) }
    // 5. A child's top margin collapses through its parent.
    let (p5, ok5) = build(a, "<div id=p><div id=c style=\"margin-top:30px;height:10px\"></div></div><div id=q style=\"height:5px\"></div>", "")
    if !ok5 { os.exit(11) }
    if !is_rect(rect_of(p5, "p"), 0.0f64, 30.0f64, 800.0f64, 10.0f64) { os.exit(12) }
    if !is_rect(rect_of(p5, "c"), 0.0f64, 30.0f64, 800.0f64, 10.0f64) { os.exit(13) }
    if !is_rect(rect_of(p5, "q"), 0.0f64, 40.0f64, 800.0f64, 5.0f64) { os.exit(14) }
    // 6. An empty block's margins join the others.
    let (p6, ok6) = build(a, "<div id=a style=\"height:10px;margin-bottom:20px\"></div><div id=e style=\"margin-top:5px;margin-bottom:30px\"></div><div id=b style=\"height:10px;margin-top:10px\"></div>", "")
    if !ok6 || !is_rect(rect_of(p6, "b"), 0.0f64, 40.0f64, 800.0f64, 10.0f64) { os.exit(15) }
    // 7. Text wraps at spaces; the trailing space is not part of the line.
    let (p7, ok7) = build(a, "<div id=t style=\"width:100px;font-size:10px\">aaaa bbbb cccc</div>", "")
    if !ok7 { os.exit(16) }
    if !is_rect(rect_of(p7, "t"), 0.0f64, 0.0f64, 100.0f64, 20.0f64) { os.exit(17) }
    if p7.lay.lines.len != 2usize || !near(p7.lay.lines.items[0usize].w, 90.0f64) || !near(p7.lay.lines.items[1usize].y, 10.0f64) { os.exit(18) }
    // 8. Centred text.
    let (p8, ok8) = build(a, "<div id=t style=\"width:100px;font-size:10px;text-align:center\">aaaa</div>", "")
    if !ok8 || p8.lay.lines.len != 1usize || !near(p8.lay.lines.items[0usize].x, 30.0f64) { os.exit(19) }
    // 9. A float shortens the lines beside it.
    let (p9, ok9) = build(a, "<div id=w style=\"width:200px;font-size:10px\"><div id=f style=\"float:left;width:50px;height:50px\"></div>aaaa bbbb cccc dddd</div>", "")
    if !ok9 { os.exit(20) }
    if !is_rect(rect_of(p9, "f"), 0.0f64, 0.0f64, 50.0f64, 50.0f64) { os.exit(21) }
    if !is_rect(rect_of(p9, "w"), 0.0f64, 0.0f64, 200.0f64, 20.0f64) { os.exit(22) }
    if p9.lay.lines.len != 2usize || !near(p9.lay.lines.items[0usize].x, 50.0f64) { os.exit(23) }
    // 10. Clearance.
    let (p10, ok10) = build(a, "<div id=f style=\"float:left;width:50px;height:40px\"></div><div id=c style=\"clear:left;height:10px\"></div>", "")
    if !ok10 || !is_rect(rect_of(p10, "c"), 0.0f64, 40.0f64, 800.0f64, 10.0f64) { os.exit(24) }
    // 11. An inline-block sits on the baseline of its line.
    let (p11, ok11) = build(a, "<div id=d style=\"font-size:10px\"><span id=i style=\"display:inline-block;width:30px;height:20px\"></span>aa</div>", "")
    if !ok11 { os.exit(25) }
    if !is_rect(rect_of(p11, "i"), 0.0f64, 0.0f64, 30.0f64, 20.0f64) { os.exit(26) }
    if !is_rect(rect_of(p11, "d"), 0.0f64, 0.0f64, 800.0f64, 22.0f64) { os.exit(27) }
    // 12. Relative positioning moves the box only.
    let (p12, ok12) = build(a, "<div id=a style=\"position:relative;left:10px;top:5px;height:10px;width:50px\"></div><div id=b style=\"height:10px\"></div>", "")
    if !ok12 || !is_rect(rect_of(p12, "a"), 10.0f64, 5.0f64, 50.0f64, 10.0f64) || !is_rect(rect_of(p12, "b"), 0.0f64, 10.0f64, 800.0f64, 10.0f64) { os.exit(28) }
    // 13. Absolute positioning against the positioned parent.
    let (p13, ok13) = build(a, "<div id=p style=\"position:relative;width:200px;height:100px\"><div id=c style=\"position:absolute;right:10px;bottom:10px;width:50px;height:20px\"></div></div>", "")
    if !ok13 || !is_rect(rect_of(p13, "c"), 140.0f64, 70.0f64, 50.0f64, 20.0f64) { os.exit(29) }
    // 14. A list item has an outside marker.
    let (p14, ok14) = build(a, "<ul id=u style=\"padding-left:40px;font-size:10px\"><li id=l1>aaaa</li></ul>", "")
    if !ok14 { os.exit(30) }
    if !is_rect(rect_of(p14, "l1"), 40.0f64, 0.0f64, 760.0f64, 10.0f64) { os.exit(31) }
    var markers = 0usize
    var mi = 0usize
    while mi < p14.lay.boxes.len {
        if p14.lay.boxes.items[mi].inner == layout.Inner.Marker && near(p14.lay.boxes.items[mi].w, 20.0f64) { markers += 1usize }
        mi += 1usize
    }
    if markers != 1usize { os.exit(32) }
    // 15. line-height.
    let (p15, ok15) = build(a, "<div id=t style=\"font-size:10px;line-height:20px\">aaaa</div>", "")
    if !ok15 || !is_rect(rect_of(p15, "t"), 0.0f64, 0.0f64, 800.0f64, 20.0f64) { os.exit(33) }
    // 16. A replaced inline box.
    let (p16, ok16) = build(a, "<img id=i width=100 height=50>", "")
    if !ok16 || !is_rect(rect_of(p16, "i"), 0.0f64, 0.0f64, 100.0f64, 50.0f64) { os.exit(34) }
    // 17. A block inside an inline splits the line.
    let (p17, ok17) = build(a, "<span id=s>a<div id=d style=\"height:10px\"></div>b</span>", "")
    if !ok17 || !rect_of(p17, "d").found { os.exit(35) }
    let tcss = "table { border-spacing: 0; font-size: 10px; } td, th { padding: 0; }"
    // 18. Table columns take their content widths.
    let (p18, ok18) = build(a, "<table id=t><tr><td id=a>aaaa</td><td id=b>bb</td></tr></table>", tcss)
    if !ok18 { os.exit(36) }
    if !is_rect(rect_of(p18, "t"), 0.0f64, 0.0f64, 60.0f64, 10.0f64) { os.exit(37) }
    if !is_rect(rect_of(p18, "a"), 0.0f64, 0.0f64, 40.0f64, 10.0f64) || !is_rect(rect_of(p18, "b"), 40.0f64, 0.0f64, 20.0f64, 10.0f64) { os.exit(38) }
    // 19. Cell spacing surrounds the cells.
    let (p19, ok19) = build(a, "<table id=t style=\"border-spacing:5px\"><tr><td id=a>aaaa</td><td id=b>bb</td></tr></table>", tcss)
    if !ok19 || !is_rect(rect_of(p19, "t"), 0.0f64, 0.0f64, 75.0f64, 20.0f64) { os.exit(39) }
    if !is_rect(rect_of(p19, "a"), 5.0f64, 5.0f64, 40.0f64, 10.0f64) || !is_rect(rect_of(p19, "b"), 50.0f64, 5.0f64, 20.0f64, 10.0f64) { os.exit(40) }
    // 20. A spanning cell widens the columns it covers.
    let (p20, ok20) = build(a, "<table id=t><tr><td id=a colspan=2>aaaaaaaaaa</td></tr><tr><td id=b>aa</td><td id=c>aa</td></tr></table>", tcss)
    if !ok20 || !is_rect(rect_of(p20, "a"), 0.0f64, 0.0f64, 100.0f64, 10.0f64) { os.exit(41) }
    if !is_rect(rect_of(p20, "b"), 0.0f64, 10.0f64, 50.0f64, 10.0f64) || !is_rect(rect_of(p20, "c"), 50.0f64, 10.0f64, 50.0f64, 10.0f64) { os.exit(42) }
    // 21. A row-spanning cell stretches the last row it covers.
    let (p21, ok21) = build(a, "<table id=t><tr><td id=a rowspan=2 style=\"height:30px\">x</td><td id=b>y</td></tr><tr><td id=c>z</td></tr></table>", tcss)
    if !ok21 || !is_rect(rect_of(p21, "a"), 0.0f64, 0.0f64, 10.0f64, 30.0f64) { os.exit(43) }
    if !is_rect(rect_of(p21, "b"), 10.0f64, 0.0f64, 10.0f64, 10.0f64) || !is_rect(rect_of(p21, "c"), 10.0f64, 10.0f64, 10.0f64, 20.0f64) { os.exit(44) }
    // 22. Middle alignment moves the content down.
    let (p22, ok22) = build(a, "<table><tr><td id=a style=\"vertical-align:middle\">aa</td><td id=b style=\"height:30px\">b</td></tr></table>", tcss)
    if !ok22 { os.exit(45) }
    let (found22, base22) = layout.first_baseline(&p22.lay, box_of(p22, "a"))
    if !found22 { os.exit(60) }
    if !near(base22, 18.0f64) { os.exit(45) }
    // 23. Display values alone make a table, with anonymous boxes filled in where parts are missing.
    let (p23, ok23) = build(a, "<div id=t style=\"display:table;font-size:10px\"><div id=a style=\"display:table-cell\">aaaa</div></div>", "")
    if !ok23 || !is_rect(rect_of(p23, "t"), 0.0f64, 0.0f64, 40.0f64, 10.0f64) || !is_rect(rect_of(p23, "a"), 0.0f64, 0.0f64, 40.0f64, 10.0f64) { os.exit(46) }
    // 24. Fixed layout: specified column widths, the rest shared.
    let (p24, ok24) = build(a, "<table id=t style=\"table-layout:fixed;width:200px\"><tr><td id=a style=\"width:50px\">a</td><td id=b>b</td></tr></table>", tcss)
    if !ok24 || !is_rect(rect_of(p24, "a"), 0.0f64, 0.0f64, 50.0f64, 10.0f64) || !is_rect(rect_of(p24, "b"), 50.0f64, 0.0f64, 150.0f64, 10.0f64) { os.exit(47) }
    // 25. A wider table hands the surplus to the columns in proportion to their widths.
    let (p25, ok25) = build(a, "<table id=t style=\"width:200px\"><tr><td id=a>aa</td><td id=b>aaaa</td></tr></table>", tcss)
    if !ok25 || !is_rect(rect_of(p25, "a"), 0.0f64, 0.0f64, 66.67f64, 10.0f64) || !is_rect(rect_of(p25, "b"), 66.67f64, 0.0f64, 133.33f64, 10.0f64) { os.exit(48) }
    // 26. A caption sits above the rows.
    let (p26, ok26) = build(a, "<table id=t><caption id=c>cc</caption><tr><td id=a>aaaa</td></tr></table>", tcss)
    if !ok26 || !is_rect(rect_of(p26, "c"), 0.0f64, 0.0f64, 40.0f64, 10.0f64) || !is_rect(rect_of(p26, "a"), 0.0f64, 10.0f64, 40.0f64, 10.0f64) { os.exit(49) }
    let fcss = "div { font-size: 10px; }"
    // 27. Flex items share a row by their grow factors, and stretch to a definite height.
    let (p27, ok27) = build(a, "<div style=\"display:flex;width:200px;height:20px\"><div id=a style=\"flex:1\"></div><div id=b style=\"flex:1\"></div></div>", fcss)
    if !ok27 || !is_rect(rect_of(p27, "a"), 0.0f64, 0.0f64, 100.0f64, 20.0f64) || !is_rect(rect_of(p27, "b"), 100.0f64, 0.0f64, 100.0f64, 20.0f64) { os.exit(50) }
    // 28. A basis plus one growing item.
    let (p28, ok28) = build(a, "<div style=\"display:flex;width:300px\"><div id=a style=\"width:100px;height:10px\"></div><div id=b style=\"flex-grow:1;height:10px\"></div></div>", fcss)
    if !ok28 || !is_rect(rect_of(p28, "a"), 0.0f64, 0.0f64, 100.0f64, 10.0f64) || !is_rect(rect_of(p28, "b"), 100.0f64, 0.0f64, 200.0f64, 10.0f64) { os.exit(51) }
    // 29. Items shrink to fit.
    let (p29, ok29) = build(a, "<div style=\"display:flex;width:100px\"><div id=a style=\"width:80px;height:10px\"></div><div id=b style=\"width:80px;height:10px\"></div></div>", fcss)
    if !ok29 || !is_rect(rect_of(p29, "a"), 0.0f64, 0.0f64, 50.0f64, 10.0f64) || !is_rect(rect_of(p29, "b"), 50.0f64, 0.0f64, 50.0f64, 10.0f64) { os.exit(52) }
    // 30. justify-content: center and space-between.
    let (p30, ok30) = build(a, "<div style=\"display:flex;width:200px;justify-content:center\"><div id=a style=\"width:50px;height:10px\"></div></div>", fcss)
    if !ok30 || !is_rect(rect_of(p30, "a"), 75.0f64, 0.0f64, 50.0f64, 10.0f64) { os.exit(53) }
    let (p31, ok31) = build(a, "<div style=\"display:flex;width:200px;justify-content:space-between\"><div id=a style=\"width:20px;height:10px\"></div><div id=b style=\"width:20px;height:10px\"></div><div id=c style=\"width:20px;height:10px\"></div></div>", fcss)
    if !ok31 || !is_rect(rect_of(p31, "b"), 90.0f64, 0.0f64, 20.0f64, 10.0f64) || !is_rect(rect_of(p31, "c"), 180.0f64, 0.0f64, 20.0f64, 10.0f64) { os.exit(54) }
    // 32. A column container shares its height.
    let (p32, ok32) = build(a, "<div style=\"display:flex;flex-direction:column;height:100px\"><div id=a style=\"flex:1\"></div><div id=b style=\"height:20px\"></div></div>", fcss)
    if !ok32 || !is_rect(rect_of(p32, "a"), 0.0f64, 0.0f64, 800.0f64, 80.0f64) || !is_rect(rect_of(p32, "b"), 0.0f64, 80.0f64, 800.0f64, 20.0f64) { os.exit(55) }
    // 33. Wrapping makes a second line.
    let (p33, ok33) = build(a, "<div style=\"display:flex;flex-wrap:wrap;width:100px\"><div id=a style=\"width:60px;height:10px\"></div><div id=b style=\"width:60px;height:10px\"></div></div>", fcss)
    if !ok33 || !is_rect(rect_of(p33, "b"), 0.0f64, 10.0f64, 60.0f64, 10.0f64) { os.exit(56) }
    // 34. align-items: center, gaps, auto margins.
    let (p34, ok34) = build(a, "<div style=\"display:flex;height:40px;align-items:center\"><div id=a style=\"width:20px;height:10px\"></div></div>", fcss)
    if !ok34 || !is_rect(rect_of(p34, "a"), 0.0f64, 15.0f64, 20.0f64, 10.0f64) { os.exit(57) }
    let (p35, ok35) = build(a, "<div style=\"display:flex;gap:10px\"><div id=a style=\"width:20px;height:10px\"></div><div id=b style=\"width:20px;height:10px\"></div></div>", fcss)
    if !ok35 || !is_rect(rect_of(p35, "b"), 30.0f64, 0.0f64, 20.0f64, 10.0f64) { os.exit(58) }
    let (p36, ok36) = build(a, "<div style=\"display:flex;width:200px\"><div id=a style=\"margin-left:auto;width:50px;height:10px\"></div></div>", fcss)
    if !ok36 || !is_rect(rect_of(p36, "a"), 150.0f64, 0.0f64, 50.0f64, 10.0f64) { os.exit(59) }
    // 37. Text items size to their content.
    let (p37, ok37) = build(a, "<div style=\"display:flex\"><div id=a>aaaa</div><div id=b>bb</div></div>", fcss)
    if !ok37 || !is_rect(rect_of(p37, "a"), 0.0f64, 0.0f64, 40.0f64, 10.0f64) || !is_rect(rect_of(p37, "b"), 40.0f64, 0.0f64, 20.0f64, 10.0f64) { os.exit(61) }
    // 38. order and row-reverse.
    let (p38, ok38) = build(a, "<div style=\"display:flex\"><div id=a style=\"width:20px;height:10px\"></div><div id=b style=\"order:-1;width:20px;height:10px\"></div></div>", fcss)
    if !ok38 || !is_rect(rect_of(p38, "b"), 0.0f64, 0.0f64, 20.0f64, 10.0f64) || !is_rect(rect_of(p38, "a"), 20.0f64, 0.0f64, 20.0f64, 10.0f64) { os.exit(62) }
    let (p39, ok39) = build(a, "<div style=\"display:flex;flex-direction:row-reverse;width:200px\"><div id=a style=\"width:20px;height:10px\"></div></div>", fcss)
    if !ok39 || !is_rect(rect_of(p39, "a"), 180.0f64, 0.0f64, 20.0f64, 10.0f64) { os.exit(63) }
    // 40. An inline flex container shrinks to its items.
    let (p40, ok40) = build(a, "<div><div style=\"display:inline-flex\" id=f><div style=\"width:30px;height:10px\"></div><div style=\"width:20px;height:10px\"></div></div></div>", fcss)
    if !ok40 || !is_rect(rect_of(p40, "f"), 0.0f64, 0.0f64, 50.0f64, 10.0f64) { os.exit(64) }
    ret ok
}
