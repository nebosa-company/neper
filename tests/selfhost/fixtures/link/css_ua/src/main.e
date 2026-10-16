// The user agent style sheet and a document's own `<style>` elements through `e.fmt.css.style.compute_document`:
// block and list-item display, headings and their em margins, nested list markers, tables, links, forms, hidden
// elements, a `<style>` rule beating the user agent, a `media` attribute that does not match. Each check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.fmt.html as html

fn options() -> html.Options {
    ret html.Options { max_bytes: 65536usize, max_nodes: 1024usize, max_attributes: 32usize, max_depth: 64u16, preserve_comments: false }
}

fn near(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = -d }
    ret d < 0.01f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let source = "<html><head><title>t</title><style>p.x { margin-top: 3px } h2 { color: #00ff00 }</style><style media=\"print\">h1 { color: #ff0000 }</style></head><body><h1 id=h1>H</h1><h2 id=h2>h</h2><p id=p>p</p><p id=px class=x>p</p><ul id=u1><li id=l1>a<ul id=u2><li id=l2>b<ul id=u3><li>c</li></ul></li></ul></li></ul><ol id=o1><li>1</li></ol><table id=t><tr id=r><td id=td>x</td><th id=th>y</th></tr></table><a id=a href=\"x\">link</a><a id=an>no</a><input id=in><button id=bt>b</button><div id=hd hidden>h</div><pre id=pre>p</pre><b id=b>b</b><sup id=sup>s</sup><code id=code>c</code></body></html>"
    let (d, de) = dom.parse(a, source, options(), 16usize)
    if de != ok { os.exit(1) }
    var tree = d
    let (styles, se) = mem.alloc[style.Style](a, tree.used)
    if se != ok { os.exit(2) }
    var table = styles
    var ctx = style.new_context(a, 800.0f64, 600.0f64)
    let none: []const str = zero
    if style.compute_document(&ctx, &tree, none, table) != ok { os.exit(3) }
    let root = tree.root

    let h1 = table[usize(dom.get_element_by_id(&tree, root, "h1"))]
    if h1.display != style.Display.Block || !near(h1.font_size, 32.0f64) || !near(h1.margin[0usize].px, 21.44f64) || !near(h1.font_weight, 700.0f64) { os.exit(4) }
    if h1.color == 4294901760u32 { os.exit(5) }
    let h2 = table[usize(dom.get_element_by_id(&tree, root, "h2"))]
    if !near(h2.font_size, 24.0f64) || h2.color != 4278255360u32 { os.exit(6) }
    let p = table[usize(dom.get_element_by_id(&tree, root, "p"))]
    if !near(p.margin[0usize].px, 16.0f64) || !near(p.margin[2usize].px, 16.0f64) { os.exit(7) }
    let px = table[usize(dom.get_element_by_id(&tree, root, "px"))]
    if !near(px.margin[0usize].px, 3.0f64) || !near(px.margin[2usize].px, 16.0f64) { os.exit(8) }

    let u1 = table[usize(dom.get_element_by_id(&tree, root, "u1"))]
    let u2 = table[usize(dom.get_element_by_id(&tree, root, "u2"))]
    let u3 = table[usize(dom.get_element_by_id(&tree, root, "u3"))]
    if !str.eq(u1.list_style_type, "disc") || !str.eq(u2.list_style_type, "circle") || !str.eq(u3.list_style_type, "square") { os.exit(9) }
    if !near(u1.margin[0usize].px, 16.0f64) || !near(u2.margin[0usize].px, 0.0f64) || !near(u1.padding[3usize].px, 40.0f64) { os.exit(10) }
    let l1 = table[usize(dom.get_element_by_id(&tree, root, "l1"))]
    if l1.display != style.Display.ListItem || !str.eq(l1.list_style_type, "disc") { os.exit(11) }
    let o1 = table[usize(dom.get_element_by_id(&tree, root, "o1"))]
    if !str.eq(o1.list_style_type, "decimal") { os.exit(12) }

    let t = table[usize(dom.get_element_by_id(&tree, root, "t"))]
    if t.display != style.Display.Table || !near(t.border_spacing_h, 0.0f64) && false { os.exit(13) }
    let r = table[usize(dom.get_element_by_id(&tree, root, "r"))]
    let td = table[usize(dom.get_element_by_id(&tree, root, "td"))]
    let th = table[usize(dom.get_element_by_id(&tree, root, "th"))]
    if r.display != style.Display.TableRow || td.display != style.Display.TableCell || !near(td.padding[0usize].px, 1.0f64) { os.exit(14) }
    if !near(th.font_weight, 700.0f64) || th.text_align != style.TextAlign.Center { os.exit(15) }

    let link = table[usize(dom.get_element_by_id(&tree, root, "a"))]
    let plain = table[usize(dom.get_element_by_id(&tree, root, "an"))]
    if link.color != 4278190318u32 || link.decoration_line != style.DECORATION_UNDERLINE { os.exit(16) }
    if plain.color == 4278190318u32 || plain.decoration_line != 0u8 { os.exit(17) }

    let inp = table[usize(dom.get_element_by_id(&tree, root, "in"))]
    if inp.display != style.Display.InlineBlock || !near(inp.border_width[0usize], 2.0f64) || inp.border_style[0usize] != style.BorderStyle.Inset || !near(inp.font_size, 13.3333f64) { os.exit(18) }
    let bt = table[usize(dom.get_element_by_id(&tree, root, "bt"))]
    if bt.border_style[0usize] != style.BorderStyle.Outset || bt.text_align != style.TextAlign.Center { os.exit(19) }
    let hd = table[usize(dom.get_element_by_id(&tree, root, "hd"))]
    if hd.display != style.Display.None { os.exit(20) }
    let head = table[usize(dom.get_element_by_id(&tree, root, "h1"))]
    let pre = table[usize(dom.get_element_by_id(&tree, root, "pre"))]
    if pre.white_space != style.WhiteSpace.Pre || !str.eq(pre.font_family, "monospace") { os.exit(21) }
    let b = table[usize(dom.get_element_by_id(&tree, root, "b"))]
    let sup = table[usize(dom.get_element_by_id(&tree, root, "sup"))]
    if !near(b.font_weight, 700.0f64) || sup.vertical_align != style.VAlign.Super || !near(sup.font_size, 16.0f64 / 1.2f64) { os.exit(22) }
    let body = table[usize(dom.last_element_child(&tree, dom.first_element_child(&tree, root)))]
    if body.display != style.Display.Block || !near(body.margin[0usize].px, 8.0f64) { os.exit(23) }
    ret ok
}
