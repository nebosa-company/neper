// The Windows dark image combo box beside the native Windows 11 dark list-style combo captures (combo-list-rest, -hover, -focus,
// -disabled), round 15. v3's TcxImageComboBox has no dark look, so its dark head is the native list combo: the first four cells carry
// no picture and are compared pixel for pixel with the captures (150 x 23, Segoe UI 9 pt); the fifth shows the head with a picture
// (no native reference for the picture itself). Run with NEPER_LOOKS_OUT=<scratch>; windows-dark/native_dark_icb.png.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 200.0 }
fn cell_h() -> f32 { ret 100.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

fn pick_actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_caret_hidden(true)
    let names = [5]str{ "Alpha", "Bravo", "Charlie", "Delta", "Echo" }
    let captions = [5]str{ "combo-list-rest", "combo-list-hover", "combo-list-disabled", "picture", "combo-list-focus" }
    var i = 0usize
    while i < 5usize {
        var icons: []const widget.Node = zero
        if i == 3usize {
            let (made, made_error) = mem.alloc[widget.Node](a, 5usize)
            if made_error != ok { ret (0usize, made_error) }
            var k = 0usize
            while k < 5usize {
                let (pic, pic_error) = control.mark_glyph(a, style.hex(2263842u32), .Check, 16.0)
                if pic_error != ok { ret (0usize, pic_error) }
                made[k] = pic
                k += 1usize
            }
            icons = made[0usize..5usize]
        }
        let (picks, picks_error) = pick_actions(a, 5usize)
        if picks_error != ok { ret (0usize, picks_error) }
        let (toggle, toggle_error) = pick_actions(a, 1usize)
        if toggle_error != ok { ret (0usize, toggle_error) }
        let (combo, combo_error) = control.image_select_at(a, u64(100usize * (i + 1usize)), t, "Format", names[0usize..5usize], icons, 1usize, false, i != 2usize, &toggle[0usize], picks, 149.0, 0.0, 0.0)
        if combo_error != ok { ret (0usize, combo_error) }
        let (node, node_error) = placed(a, combo, 25.0, 38.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 4usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark_icb", cells: 5usize, columns: 5usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
