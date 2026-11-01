// control.scroll_area under all ten looks: docs/ui/looks/<look>/scroll_area.png. Vertical and horizontal areas at rest,
// hovered, pressed, scrolled and with content that fits (no bar). The bar is drawn from the theme's tokens by the shared
// control; the sheet shows what every look makes of it and does not claim a platform reference (derived, not measured).
// Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_f
use e.ui.style
use e.ui.widget

fn content(a: *mem.Arena, t: *const control.Theme, vertical: bool, extent: f32) -> ([]widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (stripes, stripes_error) = mem.alloc[widget.Node](a, 8usize)
    if stripes_error != ok { ret (zero, stripes_error) }
    var i = 0usize
    while i < 8usize {
        var s = style.defaults()
        var tone: style.ColorRole = .SurfaceContainerHigh
        if i % 2usize == 1usize { tone = .PrimaryContainer }
        s.background = paint.Brush { Solid: style.color(t.tokens, tone) }
        if vertical {
            s.width = style.Length { Px: 90.0 }
            s.height = style.Length { Px: extent / 8.0 }
        } else {
            s.width = style.Length { Px: extent / 8.0 }
            s.height = style.Length { Px: 60.0 }
        }
        stripes[i] = widget.box(0u64, s, zero)
        i += 1usize
    }
    var axis: ui_layout.Axis = .Vertical
    if !vertical { axis = .Horizontal }
    var frame = style.defaults()
    if vertical {
        frame.width = style.Length { Px: 90.0 }
        frame.height = style.Length { Px: extent }
    } else {
        frame.width = style.Length { Px: extent }
        frame.height = style.Length { Px: 60.0 }
    }
    nodes[0usize] = widget.flex(0u64, ui_layout.Flex { axis: axis, main: .Start, cross: .Start, gap: 0.0 }, frame, stripes[0usize..8usize])
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
        let (kids, kids_error) = content(a, t, vertical, extent)
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
    let sheet = looks.Sheet { name: "scroll_area", cells: 7usize, columns: 4usize, cell_w: 150.0, cell_h: 130.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
