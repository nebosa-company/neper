// The Android look's scroll bar: a thin 4 dp thumb along the edge of the scrolled content, fading in while the content moves
// (docs/ui/looks/material/scroll_bar.png). Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

// The scrolled content: a surface box `extent` long along the axis, 40 across.
fn content(a: *mem.Arena, t: *const control.Theme, vertical: bool, extent: f32) -> ([]widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var s = style.defaults()
    s.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
    s.width = style.Length { Px: 40.0 }
    s.height = style.Length { Px: extent }
    if !vertical {
        s.width = style.Length { Px: extent }
        s.height = style.Length { Px: 40.0 }
    }
    nodes[0usize] = widget.box(0u64, s, zero)
    ret (nodes, ok)
}

// Eight cells: the vertical bar at rest, hovered, pressed, scrolled half way, with content that
// fits (no thumb); the horizontal bar at rest, hovered and scrolled to the end. The harness
// points at a cell's centre, so a spacer beside the control puts the centre on the bar.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Rest", "Hovered", "Pressed (dragged)", "Scrolled", "Fits (no thumb)", "Horizontal", "Horizontal, hovered", "Horizontal, scrolled" }
    var gap: f32 = 28.0
    if t.tokens.profile == .Windows { gap = 40.0 }
    var i = 0usize
    while i < 8usize {
        let vertical = i < 5usize
        var offset: f32 = 0.0
        var extent: f32 = 400.0
        if i == 3usize { offset = 150.0 }
        if i == 4usize { extent = 90.0 }
        if i == 7usize { offset = 280.0 }
        var width: f32 = 40.0
        var height: f32 = 100.0
        var axis: ui_layout.Axis = .Vertical
        var direction: ui_layout.Axis = .Horizontal
        if t.tokens.profile == .Windows {
            if vertical { width = 56.0 } else { height = 56.0 }
        }
        if !vertical {
            axis = .Horizontal
            direction = .Vertical
            if t.tokens.profile != .Windows { height = 40.0 }
            width = 120.0
        }
        let (kids, kids_error) = content(a, t, vertical, extent)
        if kids_error != ok { ret (0usize, kids_error) }
        let (bar, bar_error) = control.scroll_area(a, u64(10000usize * (i + 1usize)), t, axis, width, height, offset, extent, kids[0usize..1usize])
        if bar_error != ok { ret (0usize, bar_error) }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (0usize, pair_error) }
        pair[0usize] = bar
        pair[1usize] = widget.spacer(0u64, gap)
        var holder = style.defaults()
        holder.width = style.Length { Px: width + gap }
        holder.height = style.Length { Px: height }
        if !vertical {
            holder.width = style.Length { Px: width }
            holder.height = style.Length { Px: height + gap }
        }
        let node = widget.flex(0u64, ui_layout.Flex { axis: direction, main: .Start, cross: .Start, gap: 0.0 }, holder, pair[0usize..2usize])
        var drive: looks.Drive = .None
        if i == 1usize || i == 6usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "scroll_bar", cells: 8usize, columns: 4usize, cell_w: 150.0, cell_h: 110.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
