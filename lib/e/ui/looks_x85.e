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

// A dark-palette ink read on the dark list face #2B2B2B: lifted toward white, keeping its hue, until it reaches 4.6 : 1 (the mapped v3 card colours were 2.5 to 4.1 : 1). The light palette is untouched.
fn lift_dark(c: paint.Color) -> paint.Color {
    if !style.windark_active() { ret c }
    let face = style.hex_raw(0x2B2B2Bu32)
    let white = style.hex_raw(0xFFFFFFu32)
    var out = c
    var share: f32 = 0.0
    while style.contrast_ratio(out, face) < 5.0 && share < 1.0 {
        share += 0.04
        out = style.mix(c, white, share)
    }
    ret out
}

// The same lift on the dark selection fill (#264F78 focused, the lightest of the dark row fills), 4.6 : 1.
fn lift_on_selection(c: paint.Color) -> paint.Color {
    if !style.windark_active() { ret c }
    let face = style.hex_raw(0x264F78u32)
    let white = style.hex_raw(0xFFFFFFu32)
    var out = c
    var share: f32 = 0.0
    while style.contrast_ratio(out, face) < 5.0 && share < 1.0 {
        share += 0.04
        out = style.mix(c, white, share)
    }
    ret out
}

// v3's toolbar picture (a 16 x 17 tile of 0xAARRGGBB, alpha 0 = the bar face) for the dark bar #2B2B2B: a neutral pixel keeps its coverage of ink over the light face
// (black outline to white, face to the dark face; a pale disabled tile to a #6F grey), a coloured pixel keeps its colour, a very dark colour is lifted halfway to white.
fn dark_tile(a: *mem.Arena, src: []const u32, disabled: bool) -> ([]u32, err) {
    let (out, out_error) = mem.alloc[u32](a, src.len)
    if out_error != ok { ret (zero, TooLarge) }
    // a tile captured on a disabled button is pale for the whole picture (mean over its pixels above 170): drawn as disabled whatever the button says
    var sum: i32 = 0
    var count: i32 = 0
    var i = 0usize
    while i < src.len {
        let px = src[i]
        if (px >> 24u32) != 0u32 {
            sum += (i32((px >> 16u32) & 255u32) + i32((px >> 8u32) & 255u32) + i32(px & 255u32)) / 3
            count += 1
        }
        i += 1usize
    }
    var pale = disabled
    if count > 0 && sum / count >= 170 { pale = true }
    i = 0usize
    while i < src.len {
        let px = src[i]
        if (px >> 24u32) == 0u32 {
            out[i] = px
            i += 1usize
            continue
        }
        let r = i32((px >> 16u32) & 255u32)
        let g = i32((px >> 8u32) & 255u32)
        let b = i32(px & 255u32)
        let hi = max_i(r, max_i(g, b))
        let lo = min_i(r, min_i(g, b))
        let mean = (r + g + b) / 3
        var nr = r
        var ng = g
        var nb = b
        if pale || hi - lo <= 28 {
            var cover = (240 - mean) * 1000 / 240
            if cover < 0 { cover = 0 }
            if pale { cover = cover * 3 }
            if cover > 1000 { cover = 1000 }
            let v = 43 + (255 - 43) * cover / 1000
            nr = v
            ng = v
            nb = v
        } else if mean < 90 {
            nr = r + (255 - r) * 55 / 100
            ng = g + (255 - g) * 55 / 100
            nb = b + (255 - b) * 55 / 100
        }
        out[i] = 0xFF000000u32 | (u32(nr) << 16u32) | (u32(ng) << 8u32) | u32(nb)
        i += 1usize
    }
    ret (out, ok)
}

fn max_i(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn min_i(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}
