// `e.gfx.geometry`, `e.gfx.paint` and `e.gfx.image`: rectangles and their edges,
// transforms, a bounded path builder, the sRGB transfer both ways over every byte,
// brush validation, pixel views, clears in each format and a clipped blit.

use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.io
use e.mem
use e.os

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.0005 && d > -0.0005
}

fn pt(x: f32, y: f32) -> geometry.Point {
    ret geometry.Point { x: x, y: y }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Rectangles: clamped dimensions, half-open edges, intersection and union.
    let r = geometry.rect(10.0, 20.0, 30.0, -5.0)
    if r.width != 30.0 || r.height != 0.0 { os.exit(1i32) }
    let box = geometry.rect(0.0, 0.0, 10.0, 10.0)
    if !geometry.contains(box, pt(0.0, 0.0)) || geometry.contains(box, pt(10.0, 5.0)) || geometry.contains(box, pt(5.0, 10.0)) || !geometry.contains(box, pt(9.999, 9.999)) { os.exit(2i32) }
    let cut = geometry.intersect(box, geometry.rect(5.0, -5.0, 10.0, 10.0))
    if cut.x != 5.0 || cut.y != 0.0 || cut.width != 5.0 || cut.height != 5.0 { os.exit(3i32) }
    let apart = geometry.intersect(box, geometry.rect(20.0, 20.0, 5.0, 5.0))
    if apart.width != 0.0 || apart.height != 0.0 { os.exit(4i32) }
    let both = geometry.union_rect(box, geometry.rect(-5.0, 5.0, 3.0, 20.0))
    if both.x != -5.0 || both.y != 0.0 || both.width != 15.0 || both.height != 25.0 { os.exit(5i32) }
    if geometry.union_rect(box, apart).width != 10.0 { os.exit(6i32) }

    // Transforms: translate then scale, a quarter turn, identity.
    let t = geometry.transform_multiply(geometry.transform_scale(2.0, 3.0), geometry.transform_translate(1.0, 1.0))
    let moved = geometry.transform_point(t, pt(1.0, 2.0))
    if moved.x != 4.0 || moved.y != 9.0 { os.exit(7i32) }
    let turned = geometry.transform_point(geometry.transform_rotate(1.5707963), pt(1.0, 0.0))
    if !near(turned.x, 0.0) || !near(turned.y, 1.0) { os.exit(8i32) }
    let same = geometry.transform_point(geometry.transform_multiply(geometry.transform_identity(), t), pt(1.0, 2.0))
    if same.x != 4.0 || same.y != 9.0 { os.exit(9i32) }

    // Paths: verbs and points in order, a bound that refuses, a line before a move.
    let (made, builder_error) = geometry.path_builder(a, 4usize, 6usize)
    if builder_error != ok { os.exit(10i32) }
    var b = made
    if geometry.line_to(&b, pt(1.0, 1.0)) != geometry.Invalid { os.exit(11i32) }
    if geometry.move_to(&b, pt(0.0, 0.0)) != ok || geometry.line_to(&b, pt(5.0, 0.0)) != ok || geometry.quad_to(&b, pt(5.0, 5.0), pt(0.0, 5.0)) != ok || geometry.close_path(&b) != ok { os.exit(12i32) }
    if geometry.move_to(&b, pt(1.0, 1.0)) != geometry.TooLarge { os.exit(13i32) }
    let path = geometry.finish(&b)
    if path.verbs.len != 4usize || path.points.len != 4usize || path.verbs[2] != .Quad || path.verbs[3] != .Close || path.points[3].y != 5.0 { os.exit(14i32) }
    let (_, zero_error) = geometry.path_builder(a, 0usize, 1usize)
    if zero_error != geometry.Invalid { os.exit(15i32) }

    // Paint: the sRGB transfer at known points, premultiplication, brush validation.
    let mid = paint.srgb8(128u8, 255u8, 0u8, 128u8)
    if !near(mid.red, 0.21586) || mid.green != 1.0 || mid.blue != 0.0 || !near(mid.alpha, 0.50196) { os.exit(16i32) }
    if !near(paint.srgb8(10u8, 0u8, 0u8, 255u8).red, 0.003035) { os.exit(17i32) }
    let pre = paint.premultiply(paint.rgba(1.0, 0.5, 0.25, 0.5))
    if pre.red != 0.5 || pre.green != 0.25 || pre.blue != 0.125 || pre.alpha != 0.5 { os.exit(18i32) }
    var solid = paint.Brush { Solid: paint.rgba(0.1, 0.2, 0.3, 1.0) }
    var loud = paint.Brush { Solid: paint.rgba(1.5, 0.2, 0.3, 1.0) }
    if paint.validate(&solid) != ok || paint.validate(&loud) != paint.Invalid { os.exit(19i32) }
    var stops: [2]paint.Stop = [2]paint.Stop{ paint.Stop { offset: 0.0, color: paint.rgba(0.0, 0.0, 0.0, 1.0) }, paint.Stop { offset: 1.0, color: paint.rgba(1.0, 1.0, 1.0, 1.0) } }
    var linear = paint.Brush { Linear: paint.LinearGradient { start: pt(0.0, 0.0), end: pt(1.0, 0.0), stops: stops[0..] } }
    if paint.validate(&linear) != ok { os.exit(20i32) }
    stops[1].offset = -0.5
    if paint.validate(&linear) != paint.Invalid { os.exit(21i32) }
    stops[1].offset = 1.0
    var radial = paint.Brush { Radial: paint.RadialGradient { center: pt(0.0, 0.0), radius: -1.0, stops: stops[0..] } }
    var empty = paint.Brush { Radial: paint.RadialGradient { center: pt(0.0, 0.0), radius: 1.0, stops: stops[0..0usize] } }
    if paint.validate(&radial) != paint.Invalid || paint.validate(&empty) != paint.Invalid { os.exit(22i32) }

    // Images: sizes, views, a clear in each format, the transfer round trip.
    let (bytes, bytes_error) = image.required_bytes(3u32, 2u32, .Rgba8, 16usize)
    if bytes_error != ok || bytes != 28usize { os.exit(23i32) }
    let (_, short_stride) = image.required_bytes(3u32, 2u32, .Rgba8, 8usize)
    let (_, huge) = image.required_bytes(65536u32, 65536u32, .R8, 65536usize)
    if short_stride != image.Invalid || huge != image.TooLarge { os.exit(24i32) }
    var raw: [20]u8 = zero
    let (_, small) = image.make(raw[0..], 3u32, 2u32, 16usize, .Rgba8, .Straight)
    if small != image.Invalid { os.exit(25i32) }
    let (canvas, canvas_error) = image.allocate(a, 4u32, 3u32, .Rgba8, .Straight)
    if canvas_error != ok || canvas.stride != 16usize || canvas.pixels.len != 48usize { os.exit(26i32) }
    image.clear(canvas, paint.srgb8(200u8, 100u8, 50u8, 255u8))
    if canvas.pixels[0] != 200u8 || canvas.pixels[1] != 100u8 || canvas.pixels[2] != 50u8 || canvas.pixels[3] != 255u8 || canvas.pixels[44] != 200u8 || canvas.pixels[47] != 255u8 { os.exit(27i32) }
    let (bgra, bgra_error) = image.allocate(a, 1u32, 1u32, .Bgra8, .Straight)
    image.clear(bgra, paint.srgb8(200u8, 100u8, 50u8, 128u8))
    if bgra_error != ok || bgra.pixels[0] != 50u8 || bgra.pixels[2] != 200u8 || bgra.pixels[3] != 128u8 { os.exit(28i32) }
    let (halves, halves_error) = image.allocate(a, 1u32, 1u32, .Rgba16Float, .Straight)
    image.clear(halves, paint.rgba(1.0, 0.5, 0.0, 1.0))
    if halves_error != ok || halves.pixels[0] != 0u8 || halves.pixels[1] != 60u8 || halves.pixels[2] != 0u8 || halves.pixels[3] != 56u8 || halves.pixels[4] != 0u8 || halves.pixels[5] != 0u8 { os.exit(29i32) }
    let (strip, strip_error) = image.allocate(a, 1u32, 1u32, .R8, .Opaque)
    if strip_error != ok { os.exit(30i32) }
    var v = 0u32
    while v < 256u32 {
        image.clear(strip, paint.srgb8(u8(v), 0u8, 0u8, 255u8))
        if u32(strip.pixels[0]) != v { os.exit(31i32) }
        v += 1u32
    }

    // A blit clipped at the destination's edges, and a format that differs.
    let (sprite, sprite_error) = image.allocate(a, 2u32, 2u32, .Rgba8, .Straight)
    if sprite_error != ok { os.exit(32i32) }
    image.clear(sprite, paint.srgb8(1u8, 2u8, 3u8, 4u8))
    let (source, source_error) = image.make_const(sprite.pixels, 2u32, 2u32, 8usize, .Rgba8, .Straight)
    if source_error != ok { os.exit(33i32) }
    image.clear(canvas, paint.srgb8(0u8, 0u8, 0u8, 0u8))
    if image.copy(canvas, source, pt(3.0, 2.0)) != ok { os.exit(34i32) }
    if canvas.pixels[2usize * 16usize + 3usize * 4usize] != 1u8 || canvas.pixels[2usize * 16usize + 3usize * 4usize + 3usize] != 4u8 || canvas.pixels[2usize * 16usize + 2usize * 4usize] != 0u8 { os.exit(35i32) }
    if image.copy(canvas, source, pt(-1.0, -1.0)) != ok || canvas.pixels[0] != 1u8 || canvas.pixels[4] != 0u8 || canvas.pixels[16] != 0u8 { os.exit(36i32) }
    if image.copy(strip, source, pt(0.0, 0.0)) != image.Invalid { os.exit(37i32) }

    try io.print("gfx core ok\n")
    ret ok
}
