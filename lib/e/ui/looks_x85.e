// Round 85, lane x: Windows and Windows Dark completion. collection.e and control.e call this file with plain values.

use e.mem
use e.gfx.paint
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout

error TooLarge

fn px_box(color: u32, w: f32, h: f32) -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    s.background = paint.Brush { Solid: style.hex_raw(color) }
    var none: []const widget.Node = zero
    ret widget.box(0u64, s, none)
}

// The light 1:1 capture's vertical thumb (ref/windows-1to1/data_grid_top): two crisp columns, #858585 body, one end row of #929292 and #939393 at each end.
fn crisp_thumb(a: *mem.Arena, h: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var s0 = style.defaults()
    parts[0usize] = widget.positioned(0u64, 0.0, 0.0, s0, one_of(a, px_box(0x929292u32, 1.0, 1.0)))
    parts[1usize] = widget.positioned(0u64, 1.0, 0.0, s0, one_of(a, px_box(0x939393u32, 1.0, 1.0)))
    parts[2usize] = widget.positioned(0u64, 0.0, 1.0, s0, one_of(a, px_box(0x858585u32, 2.0, h - 2.0)))
    parts[3usize] = widget.positioned(0u64, 0.0, h - 1.0, s0, one_of(a, px_box(0x929292u32, 1.0, 1.0)))
    parts[4usize] = widget.positioned(0u64, 1.0, h - 1.0, s0, one_of(a, px_box(0x939393u32, 1.0, 1.0)))
    ret (widget.stack(0u64, style.defaults(), parts[0usize..5usize]), ok)
}

fn one_of(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}
