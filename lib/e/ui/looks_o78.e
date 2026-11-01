// Round 78, lane o: Windows Dark helpers. control.e calls this file, so it takes tokens and plain values, never `control`.

use e.gfx.paint
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

error TooLarge

// The native Windows 11 dark edit frame (docs/ui/looks/ref/windows-native/dark/edit-*) round `inner`: a 1 px outer line (#9B9B9B rest,
// #FFFFFF focused), a 1 px #383838 ring, the #202020 face. It grows with its content, so a wrapped token edit keeps the frame.
fn dark_edit_frame(a: *mem.Arena, width: f32, focused: bool, inner: widget.Node) -> (widget.Node, err) {
    var outer = style.hex_raw(0x9B9B9Bu32)
    if focused { outer = style.hex_raw(0xFFFFFFu32) }
    var ring_style = style.defaults()
    ring_style.width = style.Length { Percent: 100.0 }
    ring_style.background = paint.Brush { Solid: style.hex_raw(0x202020u32) }
    ring_style.border = style.Border { width: 1.0, color: style.hex_raw(0x383838u32) }
    // a border is painted inside the box and does not move the content, so each line adds its own padding
    ring_style.padding = style.EdgeLengths { left: style.Length { Px: 2.0 }, top: style.Length { Px: 1.0 }, right: style.Length { Px: 2.0 }, bottom: style.Length { Px: 1.0 } }
    let (kids, kids_error) = mem.alloc[widget.Node](a, 1usize)
    if kids_error != ok { ret (zero, TooLarge) }
    kids[0usize] = inner
    let ring = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, ring_style, kids[0usize..1usize])
    var frame_style = style.defaults()
    frame_style.width = style.Length { Px: width }
    frame_style.min_height = style.Length { Px: 22.0 }
    frame_style.background = paint.Brush { Solid: style.hex_raw(0x202020u32) }
    frame_style.border = style.Border { width: 1.0, color: outer }
    frame_style.padding = style.EdgeLengths { left: style.Length { Px: 1.0 }, top: style.Length { Px: 1.0 }, right: style.Length { Px: 1.0 }, bottom: style.Length { Px: 1.0 } }
    let (rings, rings_error) = mem.alloc[widget.Node](a, 1usize)
    if rings_error != ok { ret (zero, TooLarge) }
    rings[0usize] = ring
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame_style, rings[0usize..1usize]), ok)
}

// The dark radio group's frame line: #707070, 3.3 : 1 on the #202020 page (the muted #333333 was 1.29 : 1, under the 3 : 1 bar).
// Derived, no capture (the native group box stays #DCDCDC and unreadable in dark); quieter than the edit's #9B9B9B line.
fn dark_group_line(dark: bool, base: paint.Color) -> paint.Color {
    if dark { ret style.hex_raw(0x707070u32) }
    ret base
}
