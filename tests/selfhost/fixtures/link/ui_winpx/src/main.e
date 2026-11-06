// #779: winpx.sprite/dither validate their pixel contracts before constructing a node.

use e.gfx.paint
use e.io
use e.mem
use e.os
use e.ui.winpx

fn main(a: *mem.Arena, args: []str) -> err {
    var no_codes: [0]u8 = zero
    var no_colors: [0]paint.Color = zero
    let (_, empty_error) = winpx.sprite(a, no_codes[0..], no_colors[0..], 4.0f32, 4.0f32)
    if empty_error != winpx.Invalid { os.exit(1i32) }
    var codes: [2]u8 = zero
    codes[0usize] = 0u8
    codes[1usize] = 1u8
    var one_color: [1]paint.Color = zero
    one_color[0usize] = paint.Color { red: 1.0f32, green: 0.0f32, blue: 0.0f32, alpha: 1.0f32 }
    let (_, short_error) = winpx.sprite(a, codes[0..], one_color[0..], 2.0f32, 1.0f32)
    if short_error != winpx.Invalid { os.exit(2i32) }
    let color = paint.Color { red: 0.0f32, green: 1.0f32, blue: 0.0f32, alpha: 1.0f32 }
    let (_, parity_error) = winpx.dither(a, 2u32, 2u32, 2u32, color)
    if parity_error != winpx.Invalid { os.exit(3i32) }
    // The well-formed shapes still build.
    var two_colors: [2]paint.Color = zero
    two_colors[0usize] = one_color[0usize]
    two_colors[1usize] = color
    let (_, sprite_error) = winpx.sprite(a, codes[0..], two_colors[0..], 2.0f32, 1.0f32)
    if sprite_error != ok { os.exit(4i32) }
    let (_, dither_error) = winpx.dither(a, 2u32, 2u32, 1u32, color)
    if dither_error != ok { os.exit(5i32) }
    try io.print("ui winpx ok\n")
    ret ok
}
