// `e.gfx.svg`: a small document drawn through `e.gfx.scene` over the e.gpu CPU backend into a
// 64x64 target, then probed pixel by pixel -- a filled rect, a stroked circle, a transformed
// group with an inherited fill, a path with arcs and relative commands, `currentColor`,
// `style=` declarations, and the document's own size. Each check exits with its own code.

use e.gfx.svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.mem
use e.os

const SIDE: usize = 64usize
const RED: u32 = 4294901760u32
const BLUE: u32 = 4278190335u32
const GREEN: u32 = 4278222848u32
const WHITE: u32 = 4294967295u32
const BLACK: u32 = 4278190080u32

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

// Draw `text` fitted to the whole target on a white background and return the pixels.
fn render(a: *mem.Arena, text: str) -> ([]u32, err) {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { ret (zero, open_error) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, queue_error) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok { ret (zero, frames_error) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret (zero, canvas_error) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret (zero, renderer_error) }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    let background = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 64.0, 64.0), brush: paint.Brush { Solid: paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } } } })
    try svg.draw(a, &builder, text, geometry.rect(0.0, 0.0, 64.0, 64.0), paint.Color { red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0 })
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret (zero, compile_error) }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: 64.0, height: 64.0 })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret (zero, presented_error) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret (zero, pixels_error) }
    if gpu.read_image(q, image, pixels) != ok { ret (zero, gpu.OutOfMemory) }
    ret (pixels, ok)
}

fn probe(pixels: []u32, x: usize, y: usize) -> u32 {
    ret pixels[y * SIDE + x]
}

fn is(pixels: []u32, x: usize, y: usize, want: u32) -> bool {
    ret probe(pixels, x, y) == want
}

// A document that must draw: its pixels, or exit with `code`.
fn draw_or_exit(a: *mem.Arena, text: str, code: i32) -> []u32 {
    let (pixels, pixels_error) = render(a, text)
    if pixels_error != ok { os.exit(code) }
    ret pixels
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: a red rect and a blue ring, viewBox 100 onto 64 (scale 0.64).
    let one = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><rect x=\"10\" y=\"10\" width=\"40\" height=\"40\" fill=\"#ff0000\"/><circle cx=\"70\" cy=\"70\" r=\"20\" fill=\"none\" stroke=\"blue\" stroke-width=\"6\"/></svg>", 1i32)
    if !is(one, 19usize, 19usize, RED) || !is(one, 4usize, 4usize, WHITE) { os.exit(1i32) }
    if !is(one, 58usize, 45usize, BLUE) || !is(one, 45usize, 45usize, WHITE) { os.exit(1i32) }

    // 2: a group's transform and inherited fill.
    let two = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><g fill=\"#0000ff\" transform=\"translate(50 0)\"><rect x=\"0\" y=\"0\" width=\"50\" height=\"100\"/></g></svg>", 2i32)
    if !is(two, 48usize, 32usize, BLUE) || !is(two, 16usize, 32usize, WHITE) { os.exit(2i32) }

    // 3: a path with relative commands, and one made of arcs.
    let three = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><path d=\"M10 10 h80 v80 h-80 z\" fill=\"#008000\"/></svg>", 3i32)
    if !is(three, 32usize, 32usize, GREEN) { os.exit(31i32) }
    if !is(three, 2usize, 2usize, WHITE) { os.exit(32i32) }
    let arcs = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><path d=\"M50 10 a40 40 0 1 1 0 80 a40 40 0 1 1 0 -80 z\" fill=\"red\"/></svg>", 3i32)
    if !is(arcs, 32usize, 32usize, RED) { os.exit(33i32) }
    if !is(arcs, 3usize, 3usize, WHITE) { os.exit(34i32) }
    if !is(arcs, 32usize, 9usize, RED) { os.exit(35i32) }

    // 4: currentColor takes the caller's colour (blue here).
    let four = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\" fill=\"currentColor\"/></svg>", 4i32)
    if !is(four, 32usize, 32usize, BLUE) { os.exit(4i32) }

    // 5: style declarations beat nothing and set the fill.
    let five = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\" style=\"fill:#ff0000; stroke:none\"/></svg>", 5i32)
    if !is(five, 32usize, 32usize, RED) { os.exit(5i32) }

    // 6: the document's size, the viewBox first, then width and height.
    let (w, h, sized) = svg.size("<svg width=\"24\" height=\"48\"></svg>")
    if !sized || w != 24.0 || h != 48.0 { os.exit(6i32) }
    let (vw, vh, view_sized) = svg.size("<svg width=\"1\" height=\"1\" viewBox=\"0 0 412 915\"></svg>")
    if !view_sized || vw != 412.0 || vh != 915.0 { os.exit(6i32) }

    // 7: opacity lightens black over white to a mid tone.
    let seven = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\" fill=\"#000000\" opacity=\"0.5\"/></svg>", 7i32)
    let mid = probe(seven, 32usize, 32usize)
    let mid_red = (mid >> 16u32) & 255u32
    if mid_red < 100u32 || mid_red > 200u32 || (mid >> 24u32) != 255u32 { os.exit(7i32) }

    // 8: elements inside <defs> are not drawn.
    let eight = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><defs><rect width=\"100\" height=\"100\" fill=\"red\"/></defs></svg>", 8i32)
    if !is(eight, 32usize, 32usize, WHITE) { os.exit(8i32) }

    // 9: a polygon.
    let nine = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><polygon points=\"0,0 100,0 0,100\" fill=\"red\"/></svg>", 9i32)
    if !is(nine, 10usize, 10usize, RED) || !is(nine, 58usize, 58usize, WHITE) { os.exit(9i32) }

    // 10: a rotated bar and a rounded rect.
    let ten = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><rect x=\"40\" y=\"0\" width=\"20\" height=\"100\" fill=\"red\" transform=\"rotate(90 50 50)\"/></svg>", 10i32)
    if !is(ten, 5usize, 32usize, RED) { os.exit(101i32) }
    if !is(ten, 32usize, 5usize, WHITE) { os.exit(102i32) }
    let round = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\" rx=\"40\" fill=\"red\"/></svg>", 10i32)
    if !is(round, 32usize, 32usize, RED) { os.exit(103i32) }
    if !is(round, 1usize, 1usize, WHITE) { os.exit(104i32) }

    // 11: a stroked line.
    let eleven = draw_or_exit(a, "<svg viewBox=\"0 0 100 100\"><line x1=\"0\" y1=\"50\" x2=\"100\" y2=\"50\" stroke=\"red\" stroke-width=\"10\"/></svg>", 11i32)
    if !is(eleven, 32usize, 32usize, RED) || !is(eleven, 32usize, 10usize, WHITE) { os.exit(11i32) }

    // 12: no <svg> at all is refused.
    let (nothing, nothing_error) = render(a, "<rect width=\"10\" height=\"10\"/>")
    if nothing_error == ok { os.exit(12i32) }
    ret ok
}
