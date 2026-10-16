// `e.fmt.css.style` and `e.fmt.css.expand`: the cascade over expanded longhands (a later shorthand beats an earlier
// longhand and the other way round), shorthand expansion (margin, padding, border, font, flex, background, text-
// decoration), inheritance with `inherit`, `initial` and em chains, computed lengths (em, calc with a percentage),
// custom properties with var(), `currentcolor`, a border width of 0 under style none, and blockification. Each
// check has its own exit code.
use e.os
use e.mem
use e.str
use e.data.list as list
use e.fmt.css.cascade as cascade
use e.fmt.css.expand as expand
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.fmt.html as html

const BLACK: u32 = 4278190080u32
const BODY_COLOR: u32 = 4279383126u32
const RED: u32 = 4294901760u32
const BLUE: u32 = 4278190335u32

fn options() -> html.Options {
    ret html.Options { max_bytes: 65536usize, max_nodes: 512usize, max_attributes: 32usize, max_depth: 32u16, preserve_comments: false }
}

fn near(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = -d }
    ret d < 0.0001f64
}

fn has_pair(l: *const list.List[expand.Pair], prop: str, value: str) -> bool {
    var i = 0usize
    while i < l.len {
        if str.eq(l.items[i].property, prop) && str.eq(l.items[i].value, value) { ret true }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Shorthand expansion on its own.
    let (pm, pe) = list.init[expand.Pair](a, 16usize)
    if pe != ok { os.exit(1) }
    var pairs = pm
    if !expand.expand(a, "margin", "1px 2px 3px", false, &pairs) { os.exit(2) }
    if pairs.len != 4usize || !has_pair(&pairs, "margin-top", "1px") || !has_pair(&pairs, "margin-right", "2px") || !has_pair(&pairs, "margin-bottom", "3px") || !has_pair(&pairs, "margin-left", "2px") { os.exit(3) }
    list.clear[expand.Pair](&pairs)
    if !expand.expand(a, "margin-inline-start", "5px", true, &pairs) || !has_pair(&pairs, "margin-right", "5px") { os.exit(4) }
    list.clear[expand.Pair](&pairs)
    if !expand.expand(a, "border", "2px solid red", false, &pairs) || !has_pair(&pairs, "border-left-width", "2px") || !has_pair(&pairs, "border-bottom-style", "solid") || !has_pair(&pairs, "border-top-color", "red") { os.exit(5) }
    list.clear[expand.Pair](&pairs)
    if !expand.expand(a, "flex", "1", false, &pairs) || !has_pair(&pairs, "flex-grow", "1") || !has_pair(&pairs, "flex-shrink", "1") || !has_pair(&pairs, "flex-basis", "0%") { os.exit(6) }
    list.clear[expand.Pair](&pairs)
    if !expand.expand(a, "margin", "inherit", false, &pairs) || pairs.len != 4usize || !has_pair(&pairs, "margin-left", "inherit") { os.exit(7) }
    list.clear[expand.Pair](&pairs)
    if !expand.expand(a, "margin", "1px 2px 3px 4px 5px", false, &pairs) || pairs.len != 0usize { os.exit(8) }
    if expand.expand(a, "color", "red", false, &pairs) { os.exit(9) }

    let source = "<html><head></head><body style=\"margin: 0 10px 5px; color: #123456\"><div id=a class=box>text</div><p id=b style=\"font-size: 2em; margin-left: 4px\">x<span id=c>y</span></p><div id=d style=\"border: 2px solid red; padding: 1em 2em; width: calc(50% - 10px); display: flex; flex: 1 2 30px\">z</div><div id=e style=\"border-top: thick dashed; border-left-style: none; border-left-width: 9px\">w</div><ul id=f style=\"--gap: 7px; margin-top: var(--gap); font: italic bold 20px/1.5 Arial, sans-serif\"><li id=g>i</li></ul><div id=h style=\"color: inherit; background: red url(x.png) no-repeat; text-decoration: underline dotted blue; position: absolute; display: inline-block\">q</div><div id=k class=late>l</div><div id=m style=\"font-size: 30px\"><span id=n style=\"font-size: inherit; color: initial\">n</span></div><div id=o style=\"font-size: 150%\">o</div></body></html>"
    let (d, de) = dom.parse(a, source, options(), 16usize)
    if de != ok { os.exit(10) }
    var tree = d
    let css = ".box { margin: 5px; margin-left: 9px; font-size: 20px; line-height: 1.5 } #a { padding-top: 3px } .late { margin-left: 1px } .late { margin: 2px }"
    let (author, ae) = style.parse_rules(a, css, 0i64)
    if ae != ok { os.exit(11) }
    let none: []const cascade.Rule = zero
    var ctx = style.new_context(a, 800.0f64, 600.0f64)
    let (styles, alloc_error) = mem.alloc[style.Style](a, tree.used)
    if alloc_error != ok { os.exit(34) }
    var table = styles
    let ce = style.compute_tree(&ctx, &tree, none, author, table)
    if ce != ok { os.exit(12) }

    let html_el = dom.first_element_child(&tree, tree.root)
    let body_el = dom.last_element_child(&tree, html_el)
    let bs = table[usize(body_el)]
    if !near(bs.margin[0usize].px, 0.0f64) || !near(bs.margin[1usize].px, 10.0f64) || !near(bs.margin[2usize].px, 5.0f64) || !near(bs.margin[3usize].px, 10.0f64) { os.exit(13) }
    if bs.color != BODY_COLOR { os.exit(14) }

    let ida = dom.get_element_by_id(&tree, tree.root, "a")
    let sa = table[usize(ida)]
    if !near(sa.margin[0usize].px, 5.0f64) || !near(sa.margin[1usize].px, 5.0f64) || !near(sa.margin[3usize].px, 9.0f64) { os.exit(15) }
    if !near(sa.font_size, 20.0f64) || sa.line_height.kind != style.LenKind.Number || !near(sa.line_height.px, 1.5f64) { os.exit(16) }
    if sa.color != BODY_COLOR || !near(sa.padding[0usize].px, 3.0f64) { os.exit(17) }

    let idb = dom.get_element_by_id(&tree, tree.root, "b")
    let idc = dom.get_element_by_id(&tree, tree.root, "c")
    if !near(table[usize(idb)].font_size, 32.0f64) || !near(table[usize(idb)].margin[3usize].px, 4.0f64) || !near(table[usize(idc)].font_size, 32.0f64) || table[usize(idc)].color != BODY_COLOR { os.exit(18) }

    let idd = dom.get_element_by_id(&tree, tree.root, "d")
    let sd = table[usize(idd)]
    if !near(sd.border_width[0usize], 2.0f64) || sd.border_style[3usize] != style.BorderStyle.Solid || sd.border_color[1usize] != RED { os.exit(19) }
    if !near(sd.padding[0usize].px, 16.0f64) || !near(sd.padding[1usize].px, 32.0f64) { os.exit(20) }
    if sd.width.kind != style.LenKind.Px || !near(sd.width.px, -10.0f64) || !near(sd.width.pct, 0.5f64) { os.exit(21) }
    if sd.display != style.Display.Flex || !near(sd.flex_grow, 1.0f64) || !near(sd.flex_shrink, 2.0f64) || sd.flex_basis.kind != style.LenKind.Px || !near(sd.flex_basis.px, 30.0f64) { os.exit(22) }

    let ide = dom.get_element_by_id(&tree, tree.root, "e")
    let se = table[usize(ide)]
    if !near(se.border_width[0usize], 5.0f64) || se.border_style[0usize] != style.BorderStyle.Dashed || se.border_color[0usize] != BODY_COLOR { os.exit(23) }
    if se.border_style[3usize] != style.BorderStyle.None || !near(se.border_width[3usize], 0.0f64) { os.exit(24) }

    let idf = dom.get_element_by_id(&tree, tree.root, "f")
    let sf = table[usize(idf)]
    if !near(sf.margin[0usize].px, 7.0f64) || sf.font_style != style.FontStyle.Italic || !near(sf.font_weight, 700.0f64) || !near(sf.font_size, 20.0f64) { os.exit(25) }
    if sf.line_height.kind != style.LenKind.Number || !near(sf.line_height.px, 1.5f64) || !str.eq(sf.font_family, "Arial, sans-serif") { os.exit(26) }
    let idg = dom.get_element_by_id(&tree, tree.root, "g")
    if !near(table[usize(idg)].font_size, 20.0f64) || !near(table[usize(idg)].font_weight, 700.0f64) || table[usize(idg)].custom.len != 1usize { os.exit(27) }

    let idh = dom.get_element_by_id(&tree, tree.root, "h")
    let sh = table[usize(idh)]
    if sh.color != BODY_COLOR || sh.background_color != RED || sh.display != style.Display.Block || sh.position != style.Position.Absolute { os.exit(28) }
    if sh.decoration_line != style.DECORATION_UNDERLINE || sh.decoration_style != style.DecorationStyle.Dotted || sh.decoration_color != BLUE { os.exit(29) }
    var image_seen = false
    var x = 0usize
    while x < sh.extras.len {
        if str.eq(sh.extras[x].name, "background-image") && str.eq(sh.extras[x].value, "url(x.png)") { image_seen = true }
        x += 1usize
    }
    if !image_seen { os.exit(30) }

    let idk = dom.get_element_by_id(&tree, tree.root, "k")
    let sk = table[usize(idk)]
    if !near(sk.margin[3usize].px, 2.0f64) || !near(sk.margin[0usize].px, 2.0f64) { os.exit(31) }

    let idm = dom.get_element_by_id(&tree, tree.root, "m")
    let idn = dom.get_element_by_id(&tree, tree.root, "n")
    let sn = table[usize(idn)]
    if !near(table[usize(idm)].font_size, 30.0f64) || !near(sn.font_size, 30.0f64) || sn.color != BLACK { os.exit(32) }
    let ido = dom.get_element_by_id(&tree, tree.root, "o")
    if !near(table[usize(ido)].font_size, 24.0f64) { os.exit(33) }
    ret ok
}
