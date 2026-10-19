// The Windows dark look beside the native Windows 11 dark captures, sixth sheet (round 35): the group box (groupbox-rest and
// groupbox-disabled, 200 x 90). A classic Button group box is unthemed in dark mode: a 1 px #DCDCDC frame, a caption in black
// (unreadable on #202020, and the same in the disabled state) and a white static inside. scripts/looks_dark_whole.py diffs each cell.
// Only windows-dark matters. Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn at(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    ret widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
}

fn solid(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, value: u32) -> widget.Node {
    var s = control.sized_style(w, h)
    s.background = paint.Brush { Solid: style.hex_raw(value) }
    ret at(a, x, y, widget.box(0u64, s, zero))
}

fn group(a: *mem.Arena, t: *const control.Theme) -> (widget.Node, err) {
    var options = control.text_options()
    options.face = 7u32
    options.size = 12.0
    options.wrap = .None
    let (dark_t, dark_error) = control.windows_edit_theme(a, t, 13.0)
    if dark_error != ok { ret (zero, dark_error) }
    let (caption, caption_error) = control.colored_text(a, 0u64, "Group", &dark_t, options, style.hex_raw(0x000000u32))
    if caption_error != ok { ret (zero, caption_error) }
    let (body, body_error) = control.windows_label_faced(a, t, "Inside the group", 12.0, 400u32, style.hex_raw(0xFFFFFFu32), false, 0.0, 7u32, 0.0, 0.0, false)
    if body_error != ok { ret (zero, body_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 8usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = solid(a, 0.0, 0.0, 200.0, 90.0, 0x202020u32)
    parts[1usize] = solid(a, 12.0, 15.0, 7.0, 1.0, 0xDCDCDCu32)
    parts[2usize] = solid(a, 56.0, 15.0, 132.0, 1.0, 0xDCDCDCu32)
    parts[3usize] = solid(a, 12.0, 15.0, 1.0, 64.0, 0xDCDCDCu32)
    parts[4usize] = solid(a, 187.0, 15.0, 1.0, 64.0, 0xDCDCDCu32)
    parts[5usize] = solid(a, 12.0, 78.0, 176.0, 1.0, 0xDCDCDCu32)
    parts[6usize] = at(a, 21.0, 7.0, caption)
    parts[7usize] = at(a, 28.0, 36.0, body)
    ret (widget.stack(0u64, control.sized_style(200.0, 90.0), parts[0usize..8usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var i = 0usize
    while i < 2usize {
        let (node, node_error) = group(a, t)
        if node_error != ok { ret (0usize, node_error) }
        var name = "groupbox-rest"
        if i == 1usize { name = "groupbox-disabled" }
        cells[i] = looks.Cell { caption: name, node: node, drive: .None }
        i += 1usize
    }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark6", cells: 2usize, columns: 1usize, cell_w: 204.0, cell_h: 92.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
