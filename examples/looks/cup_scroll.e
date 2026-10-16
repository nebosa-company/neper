// The Cupertino scroll indicator: docs/ui/looks/cupertino/scroll_bar.png (and cupertino-dark). iOS and macOS overlay
// scrollers draw a thin rounded thumb in the label colour at 35 % over the content, no track; it widens under the pointer.
// The vertical one at rest, hovered, pressed, scrolled half way and with content that fits (no thumb); the horizontal one
// at rest and scrolled. The harness points at a cell's centre, so a spacer beside the control puts the centre on the bar.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn content(a: *mem.Arena, vertical: bool, extent: f32) -> ([]widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var s = style.defaults()
    s.background = paint.Brush { Solid: style.hex(0xFFFFFFu32) }
    s.width = style.Length { Px: 90.0 }
    s.height = style.Length { Px: extent }
    if !vertical {
        s.width = style.Length { Px: extent }
        s.height = style.Length { Px: 60.0 }
    }
    nodes[0usize] = widget.box(0u64, s, zero)
    ret (nodes, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [7]str{ "Rest", "Hover", "Pressed", "Scrolled", "Fits", "Horizontal", "H scrolled" }
    var i = 0usize
    while i < 7usize {
        let vertical = i < 5usize
        var offset: f32 = 0.0
        var extent: f32 = 400.0
        if i == 3usize { offset = 150.0 }
        if i == 4usize { extent = 90.0 }
        if i == 6usize { offset = 220.0 }
        var width: f32 = 100.0
        var height: f32 = 110.0
        var axis: ui_layout.Axis = .Vertical
        var direction: ui_layout.Axis = .Horizontal
        if !vertical {
            axis = .Horizontal
            direction = .Vertical
            width = 150.0
            height = 60.0
        }
        let (kids, kids_error) = content(a, vertical, extent)
        if kids_error != ok { ret (0usize, kids_error) }
        let (bar, bar_error) = control.scroll_area(a, u64(10000usize * (i + 1usize)), t, axis, width, height, offset, extent, kids[0usize..1usize])
        if bar_error != ok { ret (0usize, bar_error) }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (0usize, pair_error) }
        pair[0usize] = bar
        pair[1usize] = widget.spacer(0u64, 28.0)
        var holder = style.defaults()
        holder.width = style.Length { Px: width + 28.0 }
        holder.height = style.Length { Px: height }
        if !vertical {
            holder.width = style.Length { Px: width }
            holder.height = style.Length { Px: height + 28.0 }
        }
        var tray = style.defaults()
        tray.background = paint.Brush { Solid: style.hex(0xFFFFFFu32) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = widget.flex(0u64, ui_layout.Flex { axis: direction, main: .Start, cross: .Start, gap: 0.0 }, holder, pair[0usize..2usize])
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: held[0usize], drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "scroll_bar", cells: 7usize, columns: 4usize, cell_w: 150.0, cell_h: 130.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
