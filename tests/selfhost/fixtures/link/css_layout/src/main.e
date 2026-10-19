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

fn ahem_intrinsic(ctx: *void, node: html.NodeId, s: *const style.Style) -> layout.Intrinsic {
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

// Whether some text fragment holds exactly `text`.
fn frag_has(pg: *const Page, text: str) -> bool {
    var i = 0usize
    while i < pg.lay.frags.len {
        if pg.lay.frags.items[i].kind == layout.FragKind.Text && str.eq(pg.lay.frags.items[i].text, text) { ret true }
        i += 1usize
    }
    ret false
}

// The text of all text fragments, in order.
fn all_text(a: *mem.Arena, pg: *const Page) -> str {
    var out: str = ""
    var i = 0usize
    while i < pg.lay.frags.len {
        if pg.lay.frags.items[i].kind == layout.FragKind.Text {
            let (joined, e) = str.concat(a, out, pg.lay.frags.items[i].text)
            if e == ok { out = joined }
        }
        i += 1usize
    }
    ret out
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
    let gcss = "div { font-size: 10px; }"
    // 41. Fixed and flexible columns.
    let (p41, ok41) = build(a, "<div style=\"display:grid;grid-template-columns:100px 1fr;width:300px\"><div id=a style=\"height:10px\"></div><div id=b style=\"height:10px\"></div></div>", gcss)
    if !ok41 || !is_rect(rect_of(p41, "a"), 0.0f64, 0.0f64, 100.0f64, 10.0f64) || !is_rect(rect_of(p41, "b"), 100.0f64, 0.0f64, 200.0f64, 10.0f64) { os.exit(70) }
    // 42. Rows from the template; items fill the cells in order and stretch.
    let (p42, ok42) = build(a, "<div style=\"display:grid;grid-template-columns:1fr 1fr;grid-template-rows:20px 30px;width:200px\"><div id=a></div><div id=b></div><div id=c></div><div id=d></div></div>", gcss)
    if !ok42 || !is_rect(rect_of(p42, "c"), 0.0f64, 20.0f64, 100.0f64, 30.0f64) || !is_rect(rect_of(p42, "d"), 100.0f64, 20.0f64, 100.0f64, 30.0f64) { os.exit(71) }
    // 43. Gaps.
    let (p43, ok43) = build(a, "<div style=\"display:grid;grid-template-columns:50px 50px;gap:10px\"><div id=a style=\"height:10px\"></div><div id=b style=\"height:10px\"></div><div id=c style=\"height:10px\"></div></div>", gcss)
    if !ok43 || !is_rect(rect_of(p43, "b"), 60.0f64, 0.0f64, 50.0f64, 10.0f64) || !is_rect(rect_of(p43, "c"), 0.0f64, 20.0f64, 50.0f64, 10.0f64) { os.exit(72) }
    // 44. Spanning columns, and line numbers.
    let (p44, ok44) = build(a, "<div style=\"display:grid;grid-template-columns:50px 50px 50px\"><div id=a style=\"grid-column:1 / span 2;height:10px\"></div><div id=b style=\"grid-column:2 / 4;grid-row:2;height:10px\"></div></div>", gcss)
    if !ok44 || !is_rect(rect_of(p44, "a"), 0.0f64, 0.0f64, 100.0f64, 10.0f64) || !is_rect(rect_of(p44, "b"), 50.0f64, 10.0f64, 100.0f64, 10.0f64) { os.exit(73) }
    // 45. Named areas.
    let (p45, ok45) = build(a, "<div style=\"display:grid;grid-template-columns:50px 150px;grid-template-areas:'h h' 's m'\"><div id=m style=\"grid-area:m;height:20px\"></div><div id=h style=\"grid-area:h;height:10px\"></div><div id=s style=\"grid-area:s\"></div></div>", gcss)
    if !ok45 || !is_rect(rect_of(p45, "h"), 0.0f64, 0.0f64, 200.0f64, 10.0f64) || !is_rect(rect_of(p45, "s"), 0.0f64, 10.0f64, 50.0f64, 20.0f64) || !is_rect(rect_of(p45, "m"), 50.0f64, 10.0f64, 150.0f64, 20.0f64) { os.exit(74) }
    // 46. repeat() and auto-fill.
    let (p46, ok46) = build(a, "<div style=\"display:grid;grid-template-columns:repeat(3,1fr);width:300px\"><div id=a style=\"height:10px\"></div><div id=b style=\"height:10px\"></div><div id=c style=\"height:10px\"></div></div>", gcss)
    if !ok46 || !is_rect(rect_of(p46, "c"), 200.0f64, 0.0f64, 100.0f64, 10.0f64) { os.exit(75) }
    let (p47, ok47) = build(a, "<div style=\"display:grid;grid-template-columns:repeat(auto-fill,100px);width:350px\"><div id=a style=\"height:10px\"></div><div id=b style=\"height:10px\"></div><div id=c style=\"height:10px\"></div><div id=d style=\"height:10px\"></div></div>", gcss)
    if !ok47 || !is_rect(rect_of(p47, "c"), 200.0f64, 0.0f64, 100.0f64, 10.0f64) || !is_rect(rect_of(p47, "d"), 0.0f64, 10.0f64, 100.0f64, 10.0f64) { os.exit(76) }
    // 48. Implicit rows size to their content.
    let (p48, ok48) = build(a, "<div style=\"display:grid\"><div id=a style=\"height:10px\"></div><div id=b style=\"height:20px\"></div><div id=c style=\"height:5px\"></div></div>", gcss)
    if !ok48 || !is_rect(rect_of(p48, "b"), 0.0f64, 10.0f64, 800.0f64, 20.0f64) || !is_rect(rect_of(p48, "c"), 0.0f64, 30.0f64, 800.0f64, 5.0f64) { os.exit(77) }
    // 49. Centred items.
    let (p49, ok49) = build(a, "<div style=\"display:grid;grid-template-columns:100px;grid-template-rows:50px;align-items:center;justify-items:center\"><div id=a style=\"width:20px;height:10px\"></div></div>", gcss)
    if !ok49 || !is_rect(rect_of(p49, "a"), 40.0f64, 20.0f64, 20.0f64, 10.0f64) { os.exit(78) }
    // 50. Column flow.
    let (p50, ok50) = build(a, "<div style=\"display:grid;grid-template-rows:20px 20px;grid-auto-flow:column;grid-auto-columns:50px\"><div id=a></div><div id=b></div><div id=c></div></div>", gcss)
    if !ok50 || !is_rect(rect_of(p50, "b"), 0.0f64, 20.0f64, 50.0f64, 20.0f64) || !is_rect(rect_of(p50, "c"), 50.0f64, 0.0f64, 50.0f64, 20.0f64) { os.exit(79) }
    // 51. An inline grid shrinks to its tracks; auto tracks share the leftover space.
    let (p51, ok51) = build(a, "<div><div id=g style=\"display:inline-grid;grid-template-columns:30px 20px\"><div style=\"height:10px\"></div><div style=\"height:10px\"></div></div></div>", gcss)
    if !ok51 || !is_rect(rect_of(p51, "g"), 0.0f64, 0.0f64, 50.0f64, 10.0f64) { os.exit(80) }
    let (p52, ok52) = build(a, "<div style=\"display:grid;grid-template-columns:auto auto;width:100px\"><div id=a>aaaa</div><div id=b>bb</div></div>", gcss)
    if !ok52 || !is_rect(rect_of(p52, "a"), 0.0f64, 0.0f64, 60.0f64, 10.0f64) || !is_rect(rect_of(p52, "b"), 60.0f64, 0.0f64, 40.0f64, 10.0f64) { os.exit(81) }
    let mcss = "div { font-size: 10px; }"
    // 53. Columns split block children and balance their height.
    let (p53, ok53) = build(a, "<div id=m style=\"column-count:2;width:200px\"><div id=a style=\"height:20px\"></div><div id=b style=\"height:20px\"></div></div>", mcss)
    if !ok53 || !is_rect(rect_of(p53, "m"), 0.0f64, 0.0f64, 200.0f64, 20.0f64) { os.exit(82) }
    if !is_rect(rect_of(p53, "a"), 0.0f64, 0.0f64, 95.0f64, 20.0f64) || !is_rect(rect_of(p53, "b"), 105.0f64, 0.0f64, 95.0f64, 20.0f64) { os.exit(83) }
    // 54. Lines of a paragraph move into the next column.
    let (p54, ok54) = build(a, "<div id=m style=\"column-count:2;width:200px\">aaaa bbbb cccc dddd</div>", mcss)
    if !ok54 || p54.lay.lines.len != 2usize || !near(p54.lay.lines.items[1usize].x, 105.0f64) || !near(p54.lay.lines.items[1usize].y, 0.0f64) { os.exit(84) }
    if !is_rect(rect_of(p54, "m"), 0.0f64, 0.0f64, 200.0f64, 10.0f64) { os.exit(85) }
    // 55. column-width decides the count.
    let (p55, ok55) = build(a, "<div id=m style=\"column-width:60px;width:200px\"><div id=a style=\"height:10px\"></div><div id=b style=\"height:10px\"></div><div id=c style=\"height:10px\"></div></div>", mcss)
    if !ok55 || !is_rect(rect_of(p55, "c"), 140.0f64, 0.0f64, 60.0f64, 10.0f64) { os.exit(86) }
    // 56. An inline-block inside a padded block is offset by the padding.
    let (p56, ok56) = build(a, "<div style=\"padding:10px;font-size:10px\"><span id=i style=\"display:inline-block;width:30px;height:20px\"></span></div>", mcss)
    if !ok56 || !is_rect(rect_of(p56, "i"), 10.0f64, 10.0f64, 30.0f64, 20.0f64) { os.exit(87) }
    // 57. ::before and ::after produce boxes from `content`.
    let (p57, ok57) = build(a, "<div id=d style=\"font-size:10px\"></div>", "#d::before { content: \"ab\"; } #d::after { content: \"c\"; }")
    if !ok57 || p57.lay.lines.len != 1usize || !near(p57.lay.lines.items[0usize].w, 30.0f64) { os.exit(88) }
    // 58. Counters count in document order, scoped by the resets.
    let (p58, ok58) = build(a, "<div class=i>x</div><div class=i>y</div><div class=i>z</div>", ".i { font-size: 10px; counter-increment: n; } .i::before { content: counter(n) \". \"; } body { counter-reset: n; }")
    if !ok58 || !frag_has(p58, "1. ") || !frag_has(p58, "2. ") || !frag_has(p58, "3. ") { os.exit(89) }
    // 59. attr() and quotes.
    let (p59, ok59) = build(a, "<div style=\"font-size:10px\"><a href=\"/x\">l</a></div>", "a::after { content: \" (\" attr(href) \")\"; } a::before { content: open-quote; }")
    if !ok59 { os.exit(90) }
    let t59 = all_text(a, p59)
    if !str.eq(t59, "\xe2\x80\x9cl (/x)") { os.exit(93) }
    // 60. A custom ::marker.
    let (p60, ok60) = build(a, "<ul><li>a</li></ul>", "li::marker { content: \"* \"; }")
    if !ok60 { os.exit(91) }
    var found_marker = false
    var mi2 = 0usize
    while mi2 < p60.lay.boxes.len {
        if p60.lay.boxes.items[mi2].inner == layout.Inner.Marker && str.eq(p60.lay.boxes.items[mi2].text, "* ") { found_marker = true }
        mi2 += 1usize
    }
    if !found_marker { os.exit(92) }
    // 61. ::first-letter styles the first letter, with the punctuation before it.
    let (p61, ok61) = build(a, "<p id=p>Hello</p><p id=q>\"Hi\"</p>", "p { font-size: 10px; } p::first-letter { font-size: 20px; }")
    if !ok61 || p61.lay.lines.len != 2usize || !near(p61.lay.lines.items[0usize].w, 60.0f64) { os.exit(95) }
    if !frag_has(p61, "H") || !frag_has(p61, "ello") || !frag_has(p61, "\"H") || !frag_has(p61, "i\"") { os.exit(96) }
    // 62. The lines of an inline-block do not count as lines of the container around it.
    let (p62, ok62) = build(a, "<div id=d style=\"font-size:10px\"><span id=i style=\"display:inline-block;padding:4px 8px\">aa</span></div>", "")
    if !ok62 { os.exit(97) }
    let db = &p62.lay.boxes.items[usize(box_of(p62, "d"))]
    let ib = &p62.lay.boxes.items[usize(box_of(p62, "i"))]
    if db.line_count != 1u32 || ib.line_count != 1u32 { os.exit(98) }
    if p62.lay.frags.items[usize(p62.lay.lines.items[usize(db.line_first)].frag_first)].kind != layout.FragKind.Atomic { os.exit(99) }
    // 63. An absolutely positioned child does not stop an empty block collapsing its margins through.
    let (p63, ok63) = build(a, "<div id=w><div><div style=\"position:absolute\"></div></div><p id=p style=\"margin:24px 0;height:10px\"></p></div>", "")
    if !ok63 || !is_rect(rect_of(p63, "w"), 0.0f64, 24.0f64, 800.0f64, 10.0f64) { os.exit(100) }
    // 64. A float between blocks is not wrapped in an anonymous block that would stop margins collapsing across it.
    let (p64, ok64) = build(a, "<div id=w><div style=\"height:10px;margin-bottom:20px\"></div> <div style=\"float:left;height:10px\"></div> <div id=c style=\"clear:left;margin-top:80px;height:10px\"></div></div>", "")
    if !ok64 || !is_rect(rect_of(p64, "c"), 0.0f64, 90.0f64, 800.0f64, 10.0f64) { os.exit(101) }
    // 65. A last child with clearance keeps its bottom margin inside its parent.
    let (p65, ok65) = build(a, "<div id=w style=\"margin-bottom:40px\"><div style=\"height:20px;margin-bottom:20px\"></div><div style=\"float:left;height:20px\"></div><div style=\"clear:both;margin:30px 0 20px\"></div></div><div id=n style=\"height:10px\"></div>", "")
    if !ok65 || !is_rect(rect_of(p65, "n"), 0.0f64, 120.0f64, 800.0f64, 10.0f64) { os.exit(102) }
    // 66. A first child that clears a float does not pull its top margin out of its parent.
    let (p66, ok66) = build(a, "<div style=\"height:20px\"></div><div id=w><div style=\"float:left;height:60px\"></div><div style=\"clear:both;margin-top:20px\"></div></div>", "")
    if !ok66 || !is_rect(rect_of(p66, "w"), 0.0f64, 20.0f64, 800.0f64, 60.0f64) { os.exit(103) }
    // 67. Position absolute makes float compute to none: the box keeps its static position.
    let (p67, ok67) = build(a, "<div id=a style=\"position:absolute;float:right;width:10px;height:10px\"></div>", "")
    if !ok67 || !is_rect(rect_of(p67, "a"), 0.0f64, 0.0f64, 10.0f64, 10.0f64) { os.exit(104) }
    // 68. A vertical-rl absolute box keeps its static position when its own frame is mirrored.
    let (p68, ok68) = build(a, "<div style=\"position:relative;width:100px;height:100px\"><span id=a style=\"position:absolute;writing-mode:vertical-rl;font-size:10px\">X</span></div>", "")
    if !ok68 || !near(rect_of(p68, "a").x, 0.0f64) { os.exit(105) }
    // 69. An absolute child of a grid in a named area aligns its static position inside that area.
    let (p69, ok69) = build(a, "<div style=\"display:grid;position:relative;width:22px;height:30px;grid:2px 20px 2px / 3px 14px 3px;align-items:center\"><div id=a style=\"position:absolute;grid-area:2/2/3/3;width:8px;height:6px\"></div></div>", "")
    if !ok69 || !near(rect_of(p69, "a").y, 9.0f64) { os.exit(106) }
    // 70. A grid item with a content-sized height does not stretch.
    let (p70, ok70) = build(a, "<div style=\"display:grid;width:100px;height:100px\"><div id=a style=\"height:max-content\"></div></div>", "")
    if !ok70 || !near(rect_of(p70, "a").h, 0.0f64) { os.exit(107) }
    // 71. In an XHTML document `<div/>` is an empty element, not an open tag.
    html.set_xml_syntax(true)
    let (p71, ok71) = build(a, "<div id=w><div id=a style=\"height:10px\"/><div id=b style=\"height:20px\"></div></div>", "")
    html.set_xml_syntax(false)
    if !ok71 || !is_rect(rect_of(p71, "b"), 0.0f64, 10.0f64, 800.0f64, 20.0f64) { os.exit(108) }
    // 72. In a column flex container `justify-content: right` is the start of the block axis.
    let (p72, ok72) = build(a, "<div style=\"display:flex;flex-direction:column;height:100px;justify-content:right\"><div id=a style=\"height:10px\"></div></div>", "")
    if !ok72 || !near(rect_of(p72, "a").y, 0.0f64) { os.exit(109) }
    // 73. An auto-height column flexbox justifies within its min-height.
    let (p73, ok73) = build(a, "<div style=\"display:flex;flex-direction:column;min-height:100px;justify-content:center\"><div id=a style=\"height:10px\"></div></div>", "")
    if !ok73 || !near(rect_of(p73, "a").y, 45.0f64) { os.exit(110) }
    // 74. A flex item's automatic minimum size is capped by its max-width.
    let (p74, ok74) = build(a, "<div style=\"display:flex;width:1px\"><div id=a style=\"width:100px;max-width:50px\"><div style=\"width:80px;height:5px\"></div></div></div>", "")
    if !ok74 || !near(rect_of(p74, "a").w, 50.0f64) { os.exit(111) }
    // 75. An escaped identifier in a value is decoded (`\31 00px` is `100px`).
    let (p75, ok75) = build(a, "<div id=a></div>", "#a { width: \\31 00px; height: 10px; }")
    if !ok75 || !near(rect_of(p75, "a").w, 100.0f64) { os.exit(112) }
    // 76. A block-level image with an auto height takes its intrinsic height.
    let (p76, ok76) = build(a, "<div><img id=a width=15 height=12 style=\"display:block\"></div>", "")
    if !ok76 || !is_rect(rect_of(p76, "a"), 0.0f64, 0.0f64, 15.0f64, 12.0f64) { os.exit(113) }
    // 77. In an XHTML document a prefixed `svg:svg` is the SVG element, a replaced box.
    html.set_xml_syntax(true)
    let (p77, ok77) = build(a, "<svg:svg id=a height=\"50\"></svg:svg>", "")
    html.set_xml_syntax(false)
    if !ok77 || p77.lay.boxes.items[usize(box_of(p77, "a"))].inner != layout.Inner.Replaced { os.exit(114) }
    // 78. The trailing space of a line does not widen a shrink-to-fit box.
    let (p78, ok78) = build(a, "<div id=a style=\"position:absolute\"><span style=\"display:inline-block;width:100px;height:10px\"></span> </div>", "")
    if !ok78 || !near(rect_of(p78, "a").w, 100.0f64) { os.exit(115) }
    // 79. A table caption honours its height.
    let (p79, ok79) = build(a, "<div style=\"display:table;width:100px\"><div id=a style=\"display:table-caption;height:30px\"></div></div>", "")
    if !ok79 || !near(rect_of(p79, "a").h, 30.0f64) { os.exit(116) }
    // 80. :lang() matches the language of the element or its nearest ancestor with one, by prefix.
    let (p80, ok80) = build(a, "<div lang=\"en-US\"><p id=a>x</p></div><p id=b>y</p>", "p:lang(en) { width: 50px; }")
    if !ok80 || !near(rect_of(p80, "a").w, 50.0f64) || near(rect_of(p80, "b").w, 50.0f64) { os.exit(117) }
    // 81. An absolute box with auto left and right in a right-to-left container ends at the static right edge.
    let (p81, ok81) = build(a, "<div style=\"direction:rtl;position:relative;width:200px;height:50px\"><div id=a style=\"position:absolute;width:30px;height:10px\"></div></div>", "")
    if !ok81 || !near(rect_of(p81, "a").x, 170.0f64) { os.exit(118) }
    // 82. With left and right both given, right wins in a right-to-left container.
    let (p82, ok82) = build(a, "<div style=\"direction:rtl;width:200px\"><div id=a style=\"position:relative;left:30px;right:10px;width:50px;height:10px\"></div></div>", "")
    if !ok82 || !near(rect_of(p82, "a").x, 140.0f64) { os.exit(119) }
    ret ok
}
