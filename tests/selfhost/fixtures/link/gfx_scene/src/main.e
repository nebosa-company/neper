// `e.gfx.scene`'s CPU reference renderer (D796) over an offscreen `e.gpu` target: a
// solid rectangle, an anti-aliased triangle, a rectangular and a rounded clip, a
// linear gradient, a stroked line with a square cap, a scaled image, a glyph from a
// synthetic font, an opacity layer, a rotated fill, and the refusals -- an unmatched
// Restore, a stale scene, a released texture.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape

// A synthetic TrueType font: one square glyph (id 1) from (100, 100) to (900, 900)
// on 1000 units per em, with the tables `validate_font` wants.
fn w16(d: []u8, at: usize, v: u32) {
    d[at] = u8((v >> 8u32) & 255u32)
    d[at + 1usize] = u8(v & 255u32)
}
fn w32(d: []u8, at: usize, v: u32) {
    w16(d, at, v >> 16u32)
    w16(d, at + 2usize, v & 65535u32)
}
fn record(d: []u8, slot: usize, tag: u32, at: usize, len: usize) {
    let r = 12usize + 16usize * slot
    w32(d, r, tag)
    w32(d, r + 8usize, u32(at))
    w32(d, r + 12usize, u32(len))
}
fn synthetic_font(a: *mem.Arena) -> ([]u8, err) {
    let (d, d_error) = mem.alloc[u8](a, 512usize)
    if d_error != ok { ret (d, d_error) }
    var i = 0usize
    while i < 512usize {
        d[i] = 0u8
        i += 1usize
    }
    w32(d, 0usize, 65536u32)
    w16(d, 4usize, 7u32)
    // head at 128: unitsPerEm at 18, indexToLocFormat at 50 (short).
    record(d, 0usize, 1751474532u32, 128usize, 54usize)
    w16(d, 128usize + 18usize, 1000u32)
    // hhea at 192, hmtx at 228 (two glyphs), maxp at 236 (two glyphs), cmap at 244.
    record(d, 1usize, 1751672161u32, 192usize, 36usize)
    w16(d, 192usize + 4usize, 800u32)
    record(d, 2usize, 1752003704u32, 228usize, 8usize)
    w16(d, 228usize + 4usize, 600u32)
    record(d, 3usize, 1835104368u32, 236usize, 6usize)
    w16(d, 236usize + 4usize, 2u32)
    record(d, 4usize, 1668112752u32, 244usize, 4usize)
    // loca at 252 (short, three entries: 0, 0, glyph 1's length / 2), glyf at 260.
    record(d, 5usize, 1819239265u32, 252usize, 6usize)
    record(d, 6usize, 1735162214u32, 260usize, 40usize)
    let g = 260usize
    w16(d, g, 1u32)
    w16(d, g + 2usize, 100u32)
    w16(d, g + 4usize, 100u32)
    w16(d, g + 6usize, 900u32)
    w16(d, g + 8usize, 900u32)
    w16(d, g + 10usize, 3u32)
    w16(d, g + 12usize, 0u32)
    // Four on-curve points (100,100) (900,100) (900,900) (100,900): x deltas +100
    // +800 same -800, y deltas +100 same +800 same. A short delta is a byte with its
    // sign in the flag (0x02/0x10 for x, 0x04/0x20 for y); a delta of 800 is a
    // signed word, and "same" is the sign bit without the short bit.
    var at = g + 14usize
    d[at] = 55u8
    d[at + 1usize] = 33u8
    d[at + 2usize] = 17u8
    d[at + 3usize] = 33u8
    at += 4usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    d[at + 3usize] = 252u8
    d[at + 4usize] = 224u8
    at += 5usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    at += 3usize
    let glyph_len = at - g
    w16(d, 252usize + 2usize, 0u32)
    w16(d, 252usize + 4usize, u32(glyph_len / 2usize))
    ret (d, ok)
}

fn near(x: u32, want: u32, tolerance: u32) -> bool {
    if x > want { ret x - want <= tolerance }
    ret want - x <= tolerance
}

fn channel(pixel: u32, index: u32) -> u32 {
    ret (pixel >> (index * 8u32)) & 255u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (t, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 64u32, 64u32, .Rgba8)
    if target_error != ok { os.exit(3i32) }
    let (canvas, target_of_error) = scene.target_of(a, t)
    if target_of_error != ok { os.exit(4i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(5i32) }
    var renderer = r
    // The font and the image.
    let (font_bytes, font_error) = synthetic_font(a)
    if font_error != ok { os.exit(6i32) }
    let font = shape.Font { id: 7u32, data: font_bytes, face_index: 0u32 }
    if scene.register_font(&renderer, font) != ok { os.exit(7i32) }
    var image_bytes: [16]u8 = [16]u8{ 255u8, 0u8, 0u8, 255u8, 0u8, 255u8, 0u8, 255u8, 0u8, 0u8, 255u8, 255u8, 255u8, 255u8, 255u8, 255u8 }
    let (view, view_error) = image.make_const(image_bytes[0..], 2u32, 2u32, 8usize, .Rgba8, .Straight)
    if view_error != ok { os.exit(8i32) }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { os.exit(9i32) }

    // The list.
    let (b, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { os.exit(10i32) }
    var builder = b
    let red = paint.Brush { Solid: paint.rgba(1.0, 0.0, 0.0, 1.0) }
    let green = paint.Brush { Solid: paint.rgba(0.0, 1.0, 0.0, 1.0) }
    let blue = paint.Brush { Solid: paint.rgba(0.0, 0.0, 1.0, 1.0) }
    let white = paint.Brush { Solid: paint.rgba(1.0, 1.0, 1.0, 1.0) }
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    // 1. A solid red 16x16 at (2, 2).
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(2.0, 2.0, 16.0, 16.0), brush: red } }) != ok { os.exit(11i32) }
    // 2. A green triangle (22,2) (38,2) (22,18): its hypotenuse is anti-aliased.
    let (pb, pb_error) = geometry.path_builder(a, 8usize, 8usize)
    if pb_error != ok { os.exit(12i32) }
    var path_builder = pb
    if geometry.move_to(&path_builder, geometry.Point { x: 22.0, y: 2.0 }) != ok || geometry.line_to(&path_builder, geometry.Point { x: 38.0, y: 2.0 }) != ok || geometry.line_to(&path_builder, geometry.Point { x: 22.0, y: 18.0 }) != ok || geometry.close_path(&path_builder) != ok { os.exit(13i32) }
    let triangle = geometry.finish(&path_builder)
    if scene.push(&builder, scene.Command { FillPath: scene.FillPath { path: triangle, brush: green } }) != ok { os.exit(14i32) }
    // 3. Under a rect clip (42, 2, 8, 8): a blue fill of a larger rect shows in the clip only.
    if scene.push(&builder, save) != ok { os.exit(15i32) }
    if scene.push(&builder, scene.Command { Clip: scene.Clip { Rect: geometry.rect(42.0, 2.0, 8.0, 8.0) } }) != ok { os.exit(16i32) }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(40.0, 0.0, 20.0, 20.0), brush: blue } }) != ok { os.exit(17i32) }
    if scene.push(&builder, restore) != ok { os.exit(18i32) }
    // 4. A linear gradient from white at x=2 to blue at x=18, on the rows y 22..30.
    var stops: [2]paint.Stop = zero
    stops[0] = paint.Stop { offset: 0.0, color: paint.rgba(1.0, 1.0, 1.0, 1.0) }
    stops[1] = paint.Stop { offset: 1.0, color: paint.rgba(0.0, 0.0, 1.0, 1.0) }
    let gradient = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 2.0, y: 0.0 }, end: geometry.Point { x: 18.0, y: 0.0 }, stops: stops[0..] } }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(2.0, 22.0, 16.0, 8.0), brush: gradient } }) != ok { os.exit(19i32) }
    // 5. A horizontal white stroke of width 4 from (22, 26) to (38, 26), square caps.
    let (sb, sb_error) = geometry.path_builder(a, 4usize, 4usize)
    if sb_error != ok { os.exit(20i32) }
    var stroke_builder = sb
    if geometry.move_to(&stroke_builder, geometry.Point { x: 22.0, y: 26.0 }) != ok || geometry.line_to(&stroke_builder, geometry.Point { x: 38.0, y: 26.0 }) != ok { os.exit(21i32) }
    let line = geometry.finish(&stroke_builder)
    if scene.push(&builder, scene.Command { StrokePath: scene.StrokePath { path: line, brush: white, stroke: paint.Stroke { width: 4.0, cap: .Square, join: .Miter, miter_limit: 4.0 } } }) != ok { os.exit(22i32) }
    // 6. The 2x2 image scaled to 8x8 at (42, 22).
    if scene.push(&builder, scene.Command { Image: scene.DrawImage { texture: texture, source: geometry.rect(0.0, 0.0, 2.0, 2.0), destination: geometry.rect(42.0, 22.0, 8.0, 8.0), opacity: 1.0 } }) != ok { os.exit(23i32) }
    // 7. The square glyph at size 20 with its pen at (2, 58): 16x16 at (4, 40)..(20, 56).
    var glyphs: [1]shape.Glyph = zero
    glyphs[0] = shape.Glyph { id: 1u32, cluster: 0usize, advance_x: 0.6, advance_y: 0.0, offset_x: 0.0, offset_y: 0.0 }
    var runs: [1]layout.GlyphRun = zero
    runs[0] = layout.GlyphRun { run: shape.Run { font: 7u32, direction: .LeftToRight, script: 0u32, language: "", glyphs: glyphs[0..] }, origin: geometry.Point { x: 0.0, y: 0.0 }, size: 20.0 }
    var lines: [1]layout.Line = zero
    lines[0] = layout.Line { runs: runs[0..], bounds: geometry.rect(0.0, 0.0, 12.0, 20.0), baseline: 0.0, start: 0usize, end: 1usize }
    let text_layout = layout.Layout { source: "a", lines: lines[0..], bounds: geometry.rect(0.0, 0.0, 12.0, 20.0) }
    if scene.push(&builder, scene.Command { Text: scene.DrawText { layout: &text_layout, origin: geometry.Point { x: 2.0, y: 58.0 }, brush: white } }) != ok { os.exit(24i32) }
    // 8. An opacity layer at 0.5 holding a red 8x8 at (22, 42).
    if scene.push(&builder, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: geometry.rect(22.0, 42.0, 8.0, 8.0), opacity: 0.5 } }) != ok { os.exit(25i32) }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(22.0, 42.0, 8.0, 8.0), brush: red } }) != ok { os.exit(26i32) }
    if scene.push(&builder, restore) != ok { os.exit(27i32) }
    // 9. A rounded clip: a 12x12 at (42, 42) with radius 6 (a circle) filled green;
    //    its corner pixel stays empty and its centre is green.
    if scene.push(&builder, save) != ok { os.exit(28i32) }
    if scene.push(&builder, scene.Command { Clip: scene.Clip { Rounded: geometry.RRect { rect: geometry.rect(42.0, 42.0, 12.0, 12.0), top_left: geometry.Radius { x: 6.0, y: 6.0 }, top_right: geometry.Radius { x: 6.0, y: 6.0 }, bottom_right: geometry.Radius { x: 6.0, y: 6.0 }, bottom_left: geometry.Radius { x: 6.0, y: 6.0 } } } }) != ok { os.exit(29i32) }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(40.0, 40.0, 16.0, 16.0), brush: green } }) != ok { os.exit(30i32) }
    if scene.push(&builder, restore) != ok { os.exit(31i32) }
    // 10. A rotated fill: translate to (56, 34), rotate 45 degrees, a 4x4 square
    //     centred there, so the pixel at (56, 34) is blue and (60, 34) is not.
    if scene.push(&builder, save) != ok { os.exit(32i32) }
    if scene.push(&builder, scene.Command { Transform: geometry.transform_translate(56.0, 34.0) }) != ok { os.exit(33i32) }
    if scene.push(&builder, scene.Command { Transform: geometry.transform_rotate(0.7853982) }) != ok { os.exit(34i32) }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(-2.0, -2.0, 4.0, 4.0), brush: blue } }) != ok { os.exit(35i32) }
    if scene.push(&builder, restore) != ok { os.exit(36i32) }
    let list = scene.finish(&builder)
    let (compiled, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { os.exit(37i32) }
    if scene.render(&renderer, compiled, canvas, geometry.Size { width: 64.0, height: 64.0 }) != ok { os.exit(38i32) }

    // The pixels, in Rgba8 order: R in the low byte.
    let (shown, shown_error) = gpu.presented(t)
    if shown_error != ok { os.exit(39i32) }
    var pixels: [4096]u32 = zero
    if gpu.read_image(q, shown, pixels[0..]) != ok { os.exit(40i32) }
    // 1: solid red inside, nothing outside.
    if pixels[10usize * 64usize + 10usize] != 4278190335u32 { os.exit(41i32) }
    if pixels[0] != 0u32 || pixels[20usize * 64usize + 10usize] != 0u32 { os.exit(42i32) }
    // 2: green at (24, 4); half covered along the hypotenuse at (29, 10): y = 20 - x.
    if pixels[4usize * 64usize + 24usize] != 4278255360u32 { os.exit(43i32) }
    let edge = pixels[10usize * 64usize + 29usize]
    if !near(channel(edge, 1u32), 128u32, 40u32) || !near(channel(edge, 3u32), 128u32, 40u32) { os.exit(44i32) }
    // 3: blue inside the clip at (45, 5), nothing at (41, 5) and (45, 11).
    if pixels[5usize * 64usize + 45usize] != 4294901760u32 { os.exit(45i32) }
    if pixels[5usize * 64usize + 41usize] != 0u32 || pixels[11usize * 64usize + 45usize] != 0u32 { os.exit(46i32) }
    // 4: the gradient's middle, at x 10 (t = 0.53), is about half white and half blue.
    let middle = pixels[26usize * 64usize + 10usize]
    if !near(channel(middle, 0u32), 120u32, 24u32) || channel(middle, 2u32) != 255u32 || channel(middle, 3u32) != 255u32 { os.exit(47i32) }
    if channel(pixels[26usize * 64usize + 2usize], 0u32) < 230u32 { os.exit(48i32) }
    // 5: the stroke covers y 24..28 and, with its square caps, x 20..40.
    if pixels[26usize * 64usize + 30usize] != 4294967295u32 || pixels[25usize * 64usize + 21usize] != 4294967295u32 { os.exit(49i32) }
    if pixels[29usize * 64usize + 30usize] != 0u32 || pixels[26usize * 64usize + 19usize] != 0u32 { os.exit(50i32) }
    // 6: the image's four quadrants at (43, 23), (49, 23), (43, 29), (49, 29).
    if pixels[23usize * 64usize + 43usize] != 4278190335u32 || pixels[23usize * 64usize + 49usize] != 4278255360u32 { os.exit(51i32) }
    if pixels[29usize * 64usize + 43usize] != 4294901760u32 || pixels[29usize * 64usize + 49usize] != 4294967295u32 { os.exit(52i32) }
    // 7: the glyph, white inside (10, 48) and empty just outside (2, 48) and (10, 38).
    if pixels[48usize * 64usize + 10usize] != 4294967295u32 { os.exit(53i32) }
    if pixels[48usize * 64usize + 2usize] != 0u32 || pixels[38usize * 64usize + 10usize] != 0u32 { os.exit(54i32) }
    // 8: the layer's red at half opacity, premultiplied: (128, 0, 0, 128).
    let faded = pixels[46usize * 64usize + 26usize]
    if !near(channel(faded, 0u32), 128u32, 2u32) || channel(faded, 1u32) != 0u32 || !near(channel(faded, 3u32), 128u32, 2u32) { os.exit(55i32) }
    // 9: the circle's centre green, its corner empty.
    if pixels[48usize * 64usize + 48usize] != 4278255360u32 || pixels[42usize * 64usize + 42usize] != 0u32 { os.exit(56i32) }
    // 10: the rotated square.
    if pixels[34usize * 64usize + 56usize] != 4294901760u32 || pixels[34usize * 64usize + 60usize] != 0u32 { os.exit(57i32) }

    // Refusals: an unmatched Restore, a stale scene, a released texture.
    let (ub, ub_error) = scene.builder(a, 4usize)
    if ub_error != ok { os.exit(58i32) }
    var unmatched = ub
    if scene.push(&unmatched, restore) != ok { os.exit(59i32) }
    let (_, unmatched_error) = scene.compile(&renderer, scene.finish(&unmatched))
    if unmatched_error != scene.Invalid { os.exit(60i32) }
    if scene.release_scene(&renderer, compiled) != ok || scene.release_scene(&renderer, compiled) != scene.Invalid { os.exit(61i32) }
    if scene.render(&renderer, compiled, canvas, geometry.Size { width: 64.0, height: 64.0 }) != scene.Invalid { os.exit(62i32) }
    if scene.release_image(&renderer, texture) != ok || scene.update_image(&renderer, texture, view) != scene.Invalid { os.exit(63i32) }
    if scene.close(&renderer) != ok || scene.close(&renderer) != scene.Invalid { os.exit(64i32) }
    if gpu.close_target(t) != ok || gpu.close(device) != ok { os.exit(65i32) }
    try io.print("gfx scene ok\n")
    ret ok
}
