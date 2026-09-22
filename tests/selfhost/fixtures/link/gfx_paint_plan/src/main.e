// `e.gfx.geometry.flatten`/`stroke`, `e.gfx.paint`'s transfer pair, gradient,
// Porter-Duff table, fill rules, coverage rasteriser, subpixel filter and SDF, and
// `e.gfx.image`'s PSNR, SSIM and perceptual hashes, each against a Python replica
// (`scratchpad/gfx_paint_plan/ref.py`). Each check exits with its own code.

use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.io
use e.mem
use e.os

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.002 && d > -0.002
}

fn near_sum(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.01 && d > -0.01
}

fn near64(x: f64, y: f64, tolerance: f64) -> bool {
    let d = x - y
    ret d < tolerance && d > 0.0f64 - tolerance
}

fn pt(x: f32, y: f32) -> geometry.Point {
    ret geometry.Point { x: x, y: y }
}

fn total(xs: []const f32) -> f32 {
    var sum: f32 = 0.0
    var i = 0usize
    while i < xs.len {
        sum += xs[i]
        i += 1usize
    }
    ret sum
}

fn color_near(c: paint.Color, red: f32, green: f32, blue: f32, alpha: f32) -> bool {
    ret near(c.red, red) && near(c.green, green) && near(c.blue, blue) && near(c.alpha, alpha)
}

// The reference's LCG bytes: `state * 6364136223846793005 + 1442695040888963407`, `(state >> 33) & 255`.
fn fill_lcg(out: []u8, seed: u64) {
    var state = seed
    var i = 0usize
    while i < out.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        out[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1-3: flatten a quad and a cubic at tolerance 0.25.
    let (curve_builder, curve_error) = geometry.path_builder(a, 8usize, 8usize)
    if curve_error != ok { os.exit(1i32) }
    var curves = curve_builder
    if geometry.move_to(&curves, pt(0.0, 0.0)) != ok || geometry.quad_to(&curves, pt(4.0, 8.0), pt(8.0, 0.0)) != ok { os.exit(1i32) }
    if geometry.cubic_to(&curves, pt(8.0, 4.0), pt(0.0, 4.0), pt(0.0, 8.0)) != ok || geometry.close_path(&curves) != ok { os.exit(1i32) }
    var flat_verbs: [32]geometry.PathVerb = zero
    var flat_points: [32]geometry.Point = zero
    let (flat, flat_error) = geometry.flatten(geometry.finish(&curves), 0.25, flat_verbs[..], flat_points[..])
    if flat_error != ok || flat.verbs.len != 12usize || flat.points.len != 11usize { os.exit(2i32) }
    if !near(flat.points[3].x, 6.0) || !near(flat.points[3].y, 3.0) || !near(flat.points[10].x, 0.0) || !near(flat.points[10].y, 8.0) { os.exit(3i32) }
    var tiny_verbs: [4]geometry.PathVerb = zero
    let (_, tiny_error) = geometry.flatten(geometry.finish(&curves), 0.25, tiny_verbs[..], flat_points[..])
    let (_, bad_tolerance) = geometry.flatten(geometry.finish(&curves), 0.0, flat_verbs[..], flat_points[..])
    if tiny_error != geometry.TooLarge || bad_tolerance != geometry.Invalid { os.exit(4i32) }

    // 5-8: stroke an L-shaped polyline three ways and measure each outline's area.
    let (line_builder, line_error) = geometry.path_builder(a, 8usize, 8usize)
    if line_error != ok { os.exit(5i32) }
    var elbow = line_builder
    if geometry.move_to(&elbow, pt(2.0, 2.0)) != ok || geometry.line_to(&elbow, pt(10.0, 2.0)) != ok || geometry.line_to(&elbow, pt(10.0, 10.0)) != ok { os.exit(5i32) }
    var outline_verbs: [64]geometry.PathVerb = zero
    var outline_points: [64]geometry.Point = zero
    var canvas: [196]f32 = zero
    let (bevel, bevel_error) = geometry.stroke(geometry.finish(&elbow), 2.0, .Butt, .Bevel, 4.0, 0.1, outline_verbs[..], outline_points[..])
    if bevel_error != ok || bevel.verbs.len != 14usize || bevel.points.len != 11usize { os.exit(6i32) }
    if paint.fill_path(bevel, .NonZero, 14usize, 14usize, canvas[..]) != ok || !near_sum(total(canvas[..]), 31.5) { os.exit(6i32) }
    let (miter, miter_error) = geometry.stroke(geometry.finish(&elbow), 2.0, .Square, .Miter, 4.0, 0.1, outline_verbs[..], outline_points[..])
    if miter_error != ok || miter.verbs.len != 25usize || miter.points.len != 20usize { os.exit(7i32) }
    if paint.fill_path(miter, .NonZero, 14usize, 14usize, canvas[..]) != ok || !near_sum(total(canvas[..]), 32.0) { os.exit(7i32) }
    if geometry.close_path(&elbow) != ok { os.exit(8i32) }
    let (round, round_error) = geometry.stroke(geometry.finish(&elbow), 2.0, .Round, .Round, 4.0, 0.1, outline_verbs[..], outline_points[..])
    if round_error != ok || round.verbs.len != 42usize || round.points.len != 36usize { os.exit(8i32) }
    if paint.fill_path(round, .NonZero, 14usize, 14usize, canvas[..]) != ok || !near_sum(total(canvas[..]), 51.638456) { os.exit(8i32) }
    let (_, curved_stroke) = geometry.stroke(geometry.finish(&curves), 2.0, .Butt, .Bevel, 4.0, 0.1, outline_verbs[..], outline_points[..])
    if curved_stroke != geometry.Invalid { os.exit(9i32) }

    // 10-11: two overlapping squares under each fill rule.
    let (square_builder, square_error) = geometry.path_builder(a, 16usize, 16usize)
    if square_error != ok { os.exit(10i32) }
    var squares = square_builder
    if geometry.move_to(&squares, pt(1.0, 1.0)) != ok || geometry.line_to(&squares, pt(7.0, 1.0)) != ok || geometry.line_to(&squares, pt(7.0, 7.0)) != ok || geometry.line_to(&squares, pt(1.0, 7.0)) != ok || geometry.close_path(&squares) != ok { os.exit(10i32) }
    if geometry.move_to(&squares, pt(4.0, 4.0)) != ok || geometry.line_to(&squares, pt(10.0, 4.0)) != ok || geometry.line_to(&squares, pt(10.0, 10.0)) != ok || geometry.line_to(&squares, pt(4.0, 10.0)) != ok || geometry.close_path(&squares) != ok { os.exit(10i32) }
    var mask: [144]f32 = zero
    if paint.fill_path(geometry.finish(&squares), .NonZero, 12usize, 12usize, mask[..]) != ok || !near_sum(total(mask[..]), 63.0) { os.exit(11i32) }
    if paint.fill_path(geometry.finish(&squares), .EvenOdd, 12usize, 12usize, mask[..]) != ok || !near_sum(total(mask[..]), 54.0) { os.exit(11i32) }
    if !paint.fill_rule(.NonZero, 2i32) || paint.fill_rule(.EvenOdd, 2i32) || !paint.fill_rule(.EvenOdd, -1i32) || paint.fill_rule(.NonZero, 0i32) { os.exit(11i32) }

    // 12-15: a triangle with fractional edges, its subpixel coverage and its SDF.
    let (tri_builder, tri_error) = geometry.path_builder(a, 4usize, 4usize)
    if tri_error != ok { os.exit(12i32) }
    var tri = tri_builder
    if geometry.move_to(&tri, pt(0.5, 0.5)) != ok || geometry.line_to(&tri, pt(7.5, 1.5)) != ok || geometry.line_to(&tri, pt(3.0, 6.5)) != ok || geometry.close_path(&tri) != ok { os.exit(12i32) }
    var cov: [64]f32 = zero
    if paint.fill_path(geometry.finish(&tri), .NonZero, 8usize, 8usize, cov[..]) != ok || !near_sum(total(cov[..]), 19.75) { os.exit(13i32) }
    if !near(cov[25], 0.25) || !near(cov[19], 1.0) || !near(cov[0], 0.197917) { os.exit(13i32) }
    var wide: [192]f32 = zero
    var sub: [192]f32 = zero
    if paint.glyph_subpixel(geometry.finish(&tri), .NonZero, 8usize, 8usize, wide[..], sub[..]) != ok { os.exit(14i32) }
    if !near(sub[2usize * 24usize + 9usize], 1.0) || !near(sub[3usize * 24usize + 5usize], 0.582062) || !near_sum(total(sub[..]), 59.245801) { os.exit(14i32) }
    var field: [64]f32 = zero
    if paint.glyph_sdf(cov[..], 8usize, 8usize, field[..]) != ok { os.exit(15i32) }
    if !near(field[27], 2.0) || !near(field[0], -1.414214) || !near(field[63], -4.242641) { os.exit(15i32) }
    if paint.fill_path(geometry.finish(&curves), .NonZero, 8usize, 8usize, cov[..]) != paint.Invalid { os.exit(15i32) }

    // 16-19: the transfer pair, gradients under each spread, the Porter-Duff table.
    if !near(paint.srgb_to_linear(0.5), 0.214041) || !near(paint.linear_to_srgb(0.2), 0.484529) || !near(paint.linear_to_srgb(paint.srgb_to_linear(0.5)), 0.5) { os.exit(16i32) }
    var stops: [4]paint.Stop = [4]paint.Stop{ paint.Stop { offset: 0.0, color: paint.rgba(1.0, 0.0, 0.0, 1.0) }, paint.Stop { offset: 0.5, color: paint.rgba(0.0, 1.0, 0.0, 1.0) }, paint.Stop { offset: 0.5, color: paint.rgba(0.0, 0.0, 1.0, 1.0) }, paint.Stop { offset: 1.0, color: paint.rgba(1.0, 1.0, 1.0, 0.5) } }
    var linear = paint.Brush { Linear: paint.LinearGradient { start: pt(0.0, 0.0), end: pt(10.0, 0.0), stops: stops[0..] } }
    if paint.validate(&linear) != ok { os.exit(17i32) }
    if !color_near(paint.gradient(&linear, .Pad, pt(2.5, 0.0)), 0.5, 0.5, 0.0, 1.0) { os.exit(17i32) }
    if !color_near(paint.gradient(&linear, .Pad, pt(12.0, 3.0)), 1.0, 1.0, 1.0, 0.5) { os.exit(17i32) }
    if !color_near(paint.gradient(&linear, .Repeat, pt(12.0, 3.0)), 0.6, 0.4, 0.0, 1.0) { os.exit(17i32) }
    if !color_near(paint.gradient(&linear, .Reflect, pt(-3.0, 3.0)), 0.4, 0.6, 0.0, 1.0) { os.exit(17i32) }
    if !color_near(paint.gradient(&linear, .Pad, pt(5.0, 0.0)), 0.0, 1.0, 0.0, 1.0) { os.exit(17i32) }
    var radial = paint.Brush { Radial: paint.RadialGradient { center: pt(5.0, 5.0), radius: 4.0, stops: stops[0..] } }
    var solid = paint.Brush { Solid: paint.rgba(0.1, 0.2, 0.3, 0.4) }
    if !color_near(paint.gradient(&radial, .Reflect, pt(5.0, 11.0)), 0.0, 1.0, 0.0, 1.0) || !color_near(paint.gradient(&solid, .Pad, pt(9.0, 9.0)), 0.1, 0.2, 0.3, 0.4) { os.exit(18i32) }
    let src = paint.rgba(0.4, 0.2, 0.1, 0.5)
    let dst = paint.rgba(0.2, 0.6, 0.3, 0.8)
    if !color_near(paint.composite(.Clear, src, dst), 0.0, 0.0, 0.0, 0.0) || !color_near(paint.composite(.Src, src, dst), 0.4, 0.2, 0.1, 0.5) || !color_near(paint.composite(.Dst, src, dst), 0.2, 0.6, 0.3, 0.8) { os.exit(19i32) }
    if !color_near(paint.composite(.SrcOver, src, dst), 0.5, 0.5, 0.25, 0.9) || !color_near(paint.composite(.DstOver, src, dst), 0.28, 0.64, 0.32, 0.9) { os.exit(19i32) }
    if !color_near(paint.composite(.SrcIn, src, dst), 0.32, 0.16, 0.08, 0.4) || !color_near(paint.composite(.DstIn, src, dst), 0.1, 0.3, 0.15, 0.4) { os.exit(19i32) }
    if !color_near(paint.composite(.SrcOut, src, dst), 0.08, 0.04, 0.02, 0.1) || !color_near(paint.composite(.DstOut, src, dst), 0.1, 0.3, 0.15, 0.4) { os.exit(19i32) }
    if !color_near(paint.composite(.SrcAtop, src, dst), 0.42, 0.46, 0.23, 0.8) || !color_near(paint.composite(.DstAtop, src, dst), 0.18, 0.34, 0.17, 0.5) { os.exit(19i32) }
    if !color_near(paint.composite(.Xor, src, dst), 0.18, 0.34, 0.17, 0.5) || !color_near(paint.composite(.Plus, src, dst), 0.6, 0.8, 0.4, 1.0) { os.exit(19i32) }

    // 20-24: PSNR, SSIM and the hashes over LCG images.
    var raw_a: [1440]u8 = zero
    var raw_b: [1440]u8 = zero
    fill_lcg(raw_a[..], 7u64)
    fill_lcg(raw_b[..], 11u64)
    var i = 0usize
    while i < 1440usize {
        var v = i32(raw_a[i]) + i32(raw_b[i] % 21u8) - 10i32
        if v < 0i32 { v = 0i32 }
        if v > 255i32 { v = 255i32 }
        raw_b[i] = u8(v)
        i += 1usize
    }
    let (img_a, a_error) = image.make_const(raw_a[..], 40u32, 36u32, 40usize, .R8, .Opaque)
    let (img_b, b_error) = image.make_const(raw_b[..], 40u32, 36u32, 40usize, .R8, .Opaque)
    if a_error != ok || b_error != ok { os.exit(20i32) }
    let (ratio, psnr_error) = image.psnr(img_a, img_b)
    if psnr_error != ok || !near64(ratio, 32.49376845516318f64, 0.000000001f64) { os.exit(21i32) }
    let (same, same_error) = image.psnr(img_a, img_a)
    if same_error != ok || !(same > 1000000.0f64) { os.exit(21i32) }
    let (index, ssim_error) = image.ssim(img_a, img_b)
    if ssim_error != ok || !near64(index, 0.996763195643955f64, 0.000000000001f64) { os.exit(22i32) }
    let (self_index, self_error) = image.ssim(img_a, img_a)
    if self_error != ok || !near64(self_index, 1.0f64, 0.000000000001f64) { os.exit(22i32) }
    let (average, ahash_error) = image.ahash(img_a)
    let (difference, dhash_error) = image.dhash(img_a)
    let (perceptual, phash_error) = image.phash(img_a)
    if ahash_error != ok || dhash_error != ok || phash_error != ok { os.exit(23i32) }
    if average != 974465458772880932u64 || difference != 13093561558610632297u64 || perceptual != 13526586216640942302u64 { os.exit(23i32) }
    let (average_b, ahash_b_error) = image.ahash(img_b)
    if ahash_b_error != ok || image.hamming_distance(average, average_b) != 1u32 || image.hamming_distance(perceptual, perceptual) != 0u32 { os.exit(23i32) }
    var raw_c: [1280]u8 = zero
    fill_lcg(raw_c[..], 3u64)
    let (img_c, c_error) = image.make_const(raw_c[..], 20u32, 16u32, 80usize, .Rgba8, .Straight)
    if c_error != ok { os.exit(24i32) }
    let (average_c, ahash_c_error) = image.ahash(img_c)
    let (perceptual_c, phash_c_error) = image.phash(img_c)
    if ahash_c_error != ok || phash_c_error != ok || average_c != 9174905778940311298u64 || perceptual_c != 16206960349008974826u64 { os.exit(24i32) }
    let (_, mismatch) = image.psnr(img_a, img_c)
    if mismatch != image.Invalid { os.exit(24i32) }

    try io.print("gfx paint plan ok\n")
    ret ok
}
