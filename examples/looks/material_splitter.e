// The Android look's splitter: a 1 dp outline-variant divider with a 48 x 4 dp drag handle (docs/ui/looks/material/splitter.png)
// between two surface panes. Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

// A pane: a white box with a grey frame, standing for the panels v3 splits.
fn pane(t: *const control.Theme) -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Percent: 100.0 }
    s.height = style.Length { Percent: 100.0 }
    s.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    s.border = style.Border { width: 1.0, color: style.color(t.tokens, .OutlineVariant) }
    ret widget.box(0u64, s, zero)
}

// Eight cells, a split of 200 x 120: the sash standing upright (panes side by side) at rest,
// hovered, dragged and keyboard-focused, then the same four lying down (panes above and below).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Vertical divider, rest", "Hovered", "Dragged", "Focused", "Horizontal divider, rest", "Hovered", "Dragged", "Focused" }
    var i = 0usize
    while i < 8usize {
        var axis: ui_layout.Axis = .Horizontal
        var position: f32 = 225.0
        if i >= 4usize {
            axis = .Vertical
            position = 150.0
        }
        let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
        let (node, node_error) = control.split_view(a, u64(1000usize * (i + 1usize)), t, axis, pane(t), pane(t), position, 40.0, 40.0, change, 158.0, 110.0)
        if node_error != ok { ret (0usize, node_error) }
        // The sash stands 0.06 of the split's length left of its middle: padding on the near side puts it under the pointer.
        var lead = style.defaults()
        if i < 4usize { lead.padding.left = style.Length { Px: 19.0 } } else { lead.padding.top = style.Length { Px: 20.0 } }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = node
        let shifted = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, lead, held[0usize..1usize])
        var drive: looks.Drive = .None
        let step = i % 4usize
        if step == 1usize { drive = .Hover }
        if step == 2usize { drive = .Press }
        if step == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: shifted, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "splitter", cells: 8usize, columns: 4usize, cell_w: 200.0, cell_h: 120.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
