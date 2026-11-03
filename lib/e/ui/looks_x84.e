// Round 84, lane x: Windows Dark completion. control.e calls this file, so it takes plain values.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.winpx

error TooLarge

// The dark control frame: the native dark list and tree frame (ref/windows-native/dark tree-rest), 4.5 : 1 on #202020.
fn frame_line() -> paint.Color {
    ret style.hex_raw(0x828790u32)
}

// The native group box leaves a 7 device pixel stub before its caption at 100 % and at 150 % (groupbox-rest@1x and @1.5x: 12 to 19 and 18 to 25).
fn group_stub() -> f32 {
    ret 7.0 / scene.device_scale_now()
}

// The dark chip's remove cross: #C5C5C5 (8.1 : 1 on the #2E2E2E chip), #FF99A4 under the pointer (7.0 : 1).
fn chip_cross(hovered: bool) -> paint.Color {
    if hovered { ret style.hex_raw(0xFF99A4u32) }
    ret style.hex_raw(0xC5C5C5u32)
}

// The dark list's chosen row: focused the native #1A364D in #0078D4, unfocused #3A3A3A in the dark frame #828790.
fn chosen_fill(focused: bool) -> paint.Color {
    if focused { ret style.hex_raw(0x1A364Du32) }
    ret style.hex_raw(0x3A3A3Au32)
}

fn chosen_line(focused: bool) -> paint.Color {
    if focused { ret style.hex_raw(0x0078D4u32) }
    ret frame_line()
}

// A frame line one device pixel thick at the window's scale (1 at 100 %, 0.667 at 150 %).
fn device_line() -> f32 {
    ret 1.0 / scene.device_scale_now()
}

// A derived dark radio (a radio group's row) keeps its unchecked ring at the rest ring while pressed: the captured pressed ring is
// #454545 on #202020 (1.5 : 1, under the 3 : 1 bar). The standalone radio keeps the capture.
fn lit_pressed(lit: bool, chosen: bool, pressed: bool) -> bool {
    if lit && !chosen { ret false }
    ret pressed
}

// A caption longer than the frame is clipped at the frame's right inset, as a Win32 group box clips its text: the cut stays inside
// the top edge, which no longer disappears to the end of the cell.
fn group_clip(cut: style.Style, width: f32, text: f32, cut_x: f32) -> style.Style {
    let room = width - cut_x - 7.0
    var out = cut
    if text + 3.0 > room {
        out.width = style.Length { Px: room }
        out.overflow = .Clip
    }
    ret out
}

type Lines = struct { color: paint.Color, top: f32 }

fn lines_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// Four lines one device pixel thick on whole device pixels (the capture's 1 px at 100 % and at 150 %); `top` is the area's offset to the frame's top edge.
fn lines_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let l = mem.cast[*Lines](ctx)
    let t = 1.0 / scene.builder_scale(b)
    let x = area.x
    let y = area.y + l.top
    let w = area.width
    let h = area.height - l.top
    try winpx.fill(b, x, y, w, t, l.color)
    try winpx.fill(b, x, y + h - t, w, t, l.color)
    try winpx.fill(b, x, y + t, t, h - 2.0 * t, l.color)
    ret winpx.fill(b, x + w - t, y + t, t, h - 2.0 * t, l.color)
}

// The frame as a node that fills its parent stack (the caller puts it under the caption's cut).
fn lines_node(a: *mem.Arena, color: paint.Color, top: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[Lines](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = Lines { color: color, top: top }
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Percent: 100.0 }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&held[0usize]), measure: lines_measure, paint: lines_paint, state: widget.bytes_of[Lines](&held[0usize]) } }, style: fill, children: none }, ok)
}

// A frame of four lines one device pixel thick on whole device pixels, from the point (x, y) to (right, bottom) in logical px: the line
// pixel that holds each fractional edge is the one drawn, so no line is blended over two rows or columns at any scale.
fn thin_frame(b: *scene.Builder, x: f32, y: f32, right: f32, bottom: f32, color: paint.Color) -> err {
    let s = scene.builder_scale(b)
    let t = 1.0 / s
    let fx = f32(i32(x * s + 0.001)) / s
    let fy = f32(i32(y * s + 0.001)) / s
    let lx = f32(i32(right * s - 1.0 + 0.001)) / s
    let ly = f32(i32(bottom * s - 1.0 + 0.001)) / s
    try winpx.fill(b, fx, fy, lx - fx + t, t, color)
    try winpx.fill(b, fx, ly, lx - fx + t, t, color)
    try winpx.fill(b, fx, fy + t, t, ly - fy - t, color)
    ret winpx.fill(b, lx, fy + t, t, ly - fy - t, color)
}

// The focus rectangle of a Windows light category caption (states/vertical-grid-*-deck-properties-general-pressed): a 1 px dotted rectangle on the
// perimeter of w x h, a dot at every pixel whose x + y is even, the colour inverse of the #D1D1D1 category band.
type FocusDots = struct { w: f32, h: f32 }

fn dots_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    let m = mem.cast[*FocusDots](ctx)
    ret geometry.Size { width: m.w, height: m.h }
}

fn dots_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let m = mem.cast[*FocusDots](ctx)
    let x0 = i32(area.x + 0.001)
    let y0 = i32(area.y + 0.001)
    let w = i32(m.w)
    let h = i32(m.h)
    let ink = style.hex_raw(0x2E2E2Eu32)
    var i: i32 = 0
    while i < w {
        if (x0 + i + y0) % 2 == 0 { try winpx.fill(b, f32(x0 + i), f32(y0), 1.0, 1.0, ink) }
        if (x0 + i + y0 + h - 1) % 2 == 0 { try winpx.fill(b, f32(x0 + i), f32(y0 + h - 1), 1.0, 1.0, ink) }
        i += 1
    }
    var j: i32 = 1
    while j < h - 1 {
        if (x0 + y0 + j) % 2 == 0 { try winpx.fill(b, f32(x0), f32(y0 + j), 1.0, 1.0, ink) }
        if (x0 + w - 1 + y0 + j) % 2 == 0 { try winpx.fill(b, f32(x0 + w - 1), f32(y0 + j), 1.0, 1.0, ink) }
        j += 1
    }
    ret ok
}

fn dots_node(a: *mem.Arena, w: f32, h: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[FocusDots](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = FocusDots { w: w, h: h }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&held[0usize]), measure: dots_measure, paint: dots_paint, state: widget.bytes_of[FocusDots](&held[0usize]) } }, style: style.defaults(), children: none }, ok)
}

fn dots_pad_w() -> f32 { ret 5.0 }
fn dots_dx() -> f32 { ret 0.0 - 1.0 }
fn dots_dy() -> f32 { ret 0.0 }
