// The Windows-look painters and the Looks sheet geometry: each painter builds a node and paints into a
// scene builder, producing commands without an error. Looks' sheet maths and its look/theme tables are
// pure and checked directly. Each check has its own exit code.
use e.os
use e.mem
use e.str as strs
use e.gfx.geometry as geo
use e.gfx.scene as scene
use e.ui.widget as widget
use e.ui.looks as looks
use e.ui.winbutton as winbutton
use e.ui.winchrome as winchrome
use e.ui.winedit as winedit
use e.ui.winmark as winmark
use e.ui.vgridlook as vgridlook

// Paints a custom node into a fresh builder and returns how many commands it made.
fn painted(a: *mem.Arena, n: widget.Node, w: f32, h: f32) -> (usize, err) {
    let (b, be) = scene.builder(a, 4096usize)
    if be != ok { ret (0usize, be) }
    var builder = b
    var made = 0usize
    var failure: err = ok
    switch n.kind {
    case .Custom as c:
        failure = c.paint(c.ctx, &builder, geo.rect(0.0, 0.0, w, h))
        made = scene.builder_count(&builder)
    default:
        failure = scene.Invalid
    }
    ret (made, failure)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // winchrome: the window icon, the close tool and a glyph
    let (n1, e1) = painted(a, winchrome.icon_node(), 16.0, 16.0)
    if e1 != ok || n1 == 0usize { os.exit(1) }
    let (n2, e2) = painted(a, winchrome.tool_close_node(), 23.0, 23.0)
    if e2 != ok || n2 == 0usize { os.exit(2) }
    let (g, ge) = winchrome.glyph_node(a, 0u32, 0xFF000000u32, 1.0, 11.0)
    if ge != ok { os.exit(3) }
    let (n3, e3) = painted(a, g, 11.0, 11.0)
    if e3 != ok || n3 == 0usize { os.exit(4) }

    // winbutton: a ring and a focus rectangle, light and dark
    let (r, re) = winbutton.ring_node(a, 0u32, 0xFFFDFDFDu32, 75.0, 23.0, 0.0, 0.0, 0.0, 0.0, 0u32, false)
    if re != ok { os.exit(5) }
    let (n4, e4) = painted(a, r, 75.0, 23.0)
    if e4 != ok || n4 == 0usize { os.exit(6) }
    let (f, fe) = winbutton.focus_node(a, false, 75.0, 23.0, true)
    if fe != ok { os.exit(7) }
    let (n5, e5) = painted(a, f, 75.0, 23.0)
    if e5 != ok || n5 == 0usize { os.exit(8) }

    // winedit: the edit chrome at rest, a token chrome and the native combo
    let (c, ce) = winedit.chrome(a, 0u32, 0u32, 121.0, 21.0, 100.0, 0u32, false)
    if ce != ok { os.exit(9) }
    let (n6, e6) = painted(a, c, 121.0, 21.0)
    if e6 != ok || n6 == 0usize { os.exit(10) }
    let (t, te) = winedit.token_chrome(a, 121.0, 21.0, true, false)
    if te != ok { os.exit(11) }
    let (n7, e7) = painted(a, t, 121.0, 21.0)
    if e7 != ok || n7 == 0usize { os.exit(12) }

    // winmark: a check mark
    let (m, me) = winmark.mark_node(a, 0u32, 0u32, 0.0, false)
    if me != ok { os.exit(13) }
    let (n8, e8) = painted(a, m, 14.0, 14.0)
    if e8 != ok || n8 == 0usize { os.exit(14) }

    // vgridlook: a frame with no bands paints without an error
    var empty_f: []const f32 = zero
    var empty_b: []const bool = zero
    var empty_s: []const f32 = zero
    let frame = vgridlook.Frame { width: 328.0, height: 40.0, bands: empty_f, firsts: empty_b, opens: empty_b, rows: empty_s, selected: empty_b, tops: empty_b, lasts: empty_b, name_width: 100.0, stops: zero, heights: empty_s, hs1: empty_s, hs2: empty_s, vs1: empty_s, vs2: empty_s }
    let (v, ve) = vgridlook.node(a, frame)
    if ve != ok { os.exit(15) }
    let (n9, e9) = painted(a, v, 328.0, 40.0)
    if e9 != ok || n9 == 0usize { os.exit(16) }

    // looks: the sheet maths and the look tables
    if looks.rows_of(7usize, 3usize) != 3usize { os.exit(17) }
    if !strs.eq(looks.look_dir(.WindowsDark), "windows-dark") || !strs.eq(looks.look_dir(.Linux), "linux") { os.exit(18) }
    if !strs.eq(looks.scale_suffix(2.0), "@2x") || !strs.eq(looks.scale_suffix(1.0), "") { os.exit(19) }
    var s: looks.Sheet = zero
    s.cells = 6usize
    s.columns = 3usize
    s.cell_w = 100.0
    s.cell_h = 40.0
    let width = looks.sheet_width(&s)
    if width < 343.9 || width > 344.1 { os.exit(20) }
    let origin = looks.cell_origin(&s, 4usize)
    if origin.x < 121.9 || origin.x > 122.1 { os.exit(21) }
    ret ok
}
