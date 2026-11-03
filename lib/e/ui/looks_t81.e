// Round 81, lane t: Windows Dark group box, drawn like docs/ui/looks/ref/windows-native/dark/groupbox-rest: a 1 px #DCDCDC frame, the caption one
// ink for every state (the capture's disabled picture is its rest picture). control.e calls this file, so it takes plain values.

use e.gfx.paint
use e.mem
use e.ui.style
use e.ui.widget

// The capture's frame line.
fn group_line(dark: bool, line: paint.Color) -> paint.Color {
    if dark { ret style.hex_raw(0xDCDCDCu32) }
    ret line
}

// The frame's top margin; Dark puts the top edge on a whole pixel (the light 6.35 is v3's 150 % fit). The padding below it keeps the sum.
fn group_margin_top(dark: bool, fit: f32) -> f32 {
    if dark { ret 6.0 }
    ret fit
}

fn group_padding_top(dark: bool, fit: f32) -> f32 {
    if dark { ret 14.0 }
    ret fit
}

// Dark caption: white, disabled included (a choice for legibility; the capture draws black, the same black when disabled).
fn group_caption_ink(dark: bool, ink: paint.Color) -> paint.Color {
    if dark { ret style.hex_raw(0xFFFFFFu32) }
    ret ink
}

// A sheet cell that puts `node` at whole logical pixels (x, y) in a w x h box: the harness centres a cell's node, which puts a box of
// the other parity on a half pixel, and a 1 px frame then smears over two rows.
fn pinned(a: *mem.Arena, node: widget.Node, w: f32, h: f32, x: f32, y: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 2usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    held[1usize] = widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize])
    var box = style.defaults()
    box.width = style.Length { Px: w }
    box.height = style.Length { Px: h }
    ret (widget.stack(0u64, box, held[1usize..2usize]), ok)
}

// The caption's cut in the top edge: 2 in from the gap's start (the capture's text stands 9 in, the gap starts 7 in), 1 behind the text,
// a whole number of pixels wide so the frame line shows no part-covered pixel at the gap's end.
fn group_cut(cut: style.Style, text_width: f32) -> style.Style {
    var out = cut
    out.padding = style.EdgeLengths { left: style.Length { Px: 2.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 1.0 }, bottom: style.Length { Px: 0.0 } }
    out.width = style.Length { Px: f32(i32(text_width + 0.999)) + 3.0 }
    ret out
}
