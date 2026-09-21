// `e.gfx.filter` over a 32x32 LCG noise image (A, byte values) and a structured
// image (B, low noise plus two discs): every filter's output is digested (FNV over
// each value rounded to 2^-20) against a Python replica that scipy / scikit-image
// agree with (gaussian to 1e-9, sobel, median, otsu, erosion, labels, distance
// transform squared, watershed, flood fill) or that scikit-image's canny matches
// pixel for pixel; fast marching agrees with fast sweeping, and the Laplacian
// pyramid collapses back to its image. Each check exits with its own code.

use e.gfx.filter
use e.io
use e.math
use e.mem
use e.os

fn draw(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn mix(h: u64, word: u64) -> u64 { ret (h ^ word) *% 1099511628211u64 }

fn digest(xs: []const f64) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < xs.len {
        let v = i64(math.round[f64](xs[i] * 1048576.0f64))
        h = mix(h, mem.bitcast[u64](v))
        i += 1usize
    }
    ret h
}

fn digest_u8(xs: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < xs.len {
        h = mix(h, u64(xs[i]))
        i += 1usize
    }
    ret h
}

fn digest_u32(xs: []const u32) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < xs.len {
        h = mix(h, u64(xs[i]))
        i += 1usize
    }
    ret h
}

fn max_diff(a: []const f64, b: []const f64) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < a.len {
        let d = math.abs[f64](a[i] - b[i])
        if d > m { m = d }
        i += 1usize
    }
    ret m
}

fn above(src: []const f64, level: f64, out: []u8) {
    var i = 0usize
    while i < src.len {
        if src[i] > level { out[i] = 1u8 } else { out[i] = 0u8 }
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var img_a: [1024]f64 = zero
    var img_b: [1024]f64 = zero
    var bytes_a: [1024]u8 = zero
    var state = 12345u64
    var i = 0usize
    while i < 1024usize {
        let v = draw(&state) & 255u64
        img_a[i] = f64(v)
        bytes_a[i] = u8(v)
        i += 1usize
    }
    var y = 0usize
    while y < 32usize {
        var x = 0usize
        while x < 32usize {
            var v = f64(draw(&state) & 31u64)
            let dx1 = i64(x) - 10i64
            let dy1 = i64(y) - 12i64
            if dx1 * dx1 + dy1 * dy1 <= 49i64 { v += 160.0f64 }
            let dx2 = i64(x) - 22i64
            let dy2 = i64(y) - 20i64
            if dx2 * dx2 + dy2 * dy2 <= 36i64 { v += 100.0f64 }
            img_b[y * 32usize + x] = v
            x += 1usize
        }
        y += 1usize
    }
    var dst: [1024]f64 = zero
    var scratch: [7168]f64 = zero
    var gx: [1024]f64 = zero
    var gy: [1024]f64 = zero
    var mag: [1024]f64 = zero
    var bits: [1024]u8 = zero
    var labels: [1024]u32 = zero
    var work: [1025]u32 = zero

    // 1: Gaussian blur, sigma 1.5 (scipy gaussian_filter, reflect, truncate 4).
    if filter.gaussian_blur(img_a[..], 32usize, 32usize, 1.5f64, dst[..], scratch[..]) != ok { os.exit(1i32) }
    if digest(dst[..]) != 5382894779413838334u64 { os.exit(1i32) }

    // 2: Sobel (scipy sobel on both axes) and its magnitude.
    if filter.sobel(img_a[..], 32usize, 32usize, gx[..], gy[..], mag[..]) != ok { os.exit(2i32) }
    if digest(gx[..]) != 2202790946855744293u64 || digest(gy[..]) != 3888579405010203429u64 || digest(mag[..]) != 938039199076156476u64 { os.exit(2i32) }

    // 3: Canny on B (scikit-image canny agrees pixel for pixel: 97 edges).
    let (edge_count, canny_error) = filter.canny(img_b[..], 32usize, 32usize, 60.0f64, 160.0f64, 1.0f64, bits[..], scratch[..])
    if canny_error != ok || edge_count != 97usize || digest_u8(bits[..]) != 6055206943700370634u64 { os.exit(3i32) }

    // 4: median, radius 2 (scipy median_filter size 5).
    if filter.median(img_a[..], 32usize, 32usize, 2usize, dst[..], scratch[..]) != ok { os.exit(4i32) }
    if digest(dst[..]) != 4421362349693760293u64 { os.exit(4i32) }

    // 5: bilateral, sigma_s 1.5, sigma_r 40.
    if filter.bilateral(img_a[..], 32usize, 32usize, 1.5f64, 40.0f64, dst[..]) != ok { os.exit(5i32) }
    if digest(dst[..]) != 10676286851391150509u64 { os.exit(5i32) }

    // 6: guided filter of A steered by B, radius 2, eps 100.
    if filter.guided(img_a[..], img_b[..], 32usize, 32usize, 2usize, 100.0f64, dst[..], scratch[..]) != ok { os.exit(6i32) }
    if digest(dst[..]) != 16414396360793677656u64 { os.exit(6i32) }

    // 7: integral images, f64 and exact u64.
    if filter.integral_image(img_a[..], 32usize, 32usize, scratch[..]) != ok { os.exit(7i32) }
    if filter.integral_sum(scratch[..], 32usize, 3usize, 5usize, 10usize, 7usize) != 8278.0f64 { os.exit(7i32) }
    if filter.integral_sum(scratch[..], 32usize, 0usize, 0usize, 32usize, 32usize) != 129038.0f64 { os.exit(7i32) }
    var table: [1089]u64 = zero
    if filter.integral_image_u8(bytes_a[..], 32usize, 32usize, table[..]) != ok { os.exit(7i32) }
    if filter.integral_sum_u64(table[..], 32usize, 3usize, 5usize, 10usize, 7usize) != 8278u64 { os.exit(7i32) }

    // 8: Otsu (scikit-image threshold_otsu on the byte image).
    if filter.threshold_otsu(bytes_a[..], 32usize, 32usize) != 129u8 { os.exit(8i32) }

    // 9: morphology, radius 1 (scipy grey_erosion / dilation / opening / closing, size 3).
    if filter.morph_erode(img_a[..], 32usize, 32usize, 1usize, dst[..]) != ok || digest(dst[..]) != 15542270942986662693u64 { os.exit(9i32) }
    if filter.morph_dilate(img_a[..], 32usize, 32usize, 1usize, dst[..]) != ok || digest(dst[..]) != 8641651536661345061u64 { os.exit(9i32) }
    if filter.morph_open(img_a[..], 32usize, 32usize, 1usize, dst[..], scratch[..]) != ok || digest(dst[..]) != 16755968655812490021u64 { os.exit(9i32) }
    if filter.morph_close(img_a[..], 32usize, 32usize, 1usize, dst[..], scratch[..]) != ok || digest(dst[..]) != 16916444476401546021u64 { os.exit(9i32) }

    // 10: connected components of A > 127 (scipy label, 4 and 8, relabelled by first appearance).
    above(img_a[..], 127.0f64, bits[..])
    let (count4, label4_error) = filter.label_components(bits[..], 32usize, 32usize, 4u32, labels[..], work[..])
    if label4_error != ok || count4 != 85u32 || digest_u32(labels[..]) != 5466945775762748628u64 { os.exit(10i32) }
    let (count8, label8_error) = filter.label_components(bits[..], 32usize, 32usize, 8u32, labels[..], work[..])
    if label8_error != ok || count8 != 11u32 || digest_u32(labels[..]) != 3255178012700238117u64 { os.exit(10i32) }
    let (_, bad_connectivity) = filter.label_components(bits[..], 32usize, 32usize, 6u32, labels[..], work[..])
    if bad_connectivity != filter.Invalid { os.exit(10i32) }

    // 11: flood fill of the background of B > 100 from (0, 0), pixel stack and scanline
    // (scikit-image flood_fill agrees).
    var fill_a: [1024]u8 = zero
    above(img_b[..], 100.0f64, fill_a[..])
    var fill_b: [1024]u8 = zero
    i = 0usize
    while i < 1024usize {
        fill_b[i] = fill_a[i]
        i += 1usize
    }
    let (filled, fill_error) = filter.flood_fill(fill_a[..], 32usize, 32usize, 0usize, 0usize, 7u8, labels[..])
    if fill_error != ok || filled != 763usize || digest_u8(fill_a[..]) != 13782748531461276267u64 { os.exit(11i32) }
    let (filled_scan, scan_error) = filter.flood_fill_scanline(fill_b[..], 32usize, 32usize, 0usize, 0usize, 7u8, labels[..])
    if scan_error != ok || filled_scan != 763usize || digest_u8(fill_b[..]) != 13782748531461276267u64 { os.exit(11i32) }
    let (again, _) = filter.flood_fill(fill_a[..], 32usize, 32usize, 0usize, 0usize, 7u8, labels[..])
    if again != 0usize { os.exit(11i32) }
    let (_, small_stack) = filter.flood_fill(fill_b[..], 32usize, 32usize, 0usize, 0usize, 9u8, labels[..4usize])
    if small_stack != filter.TooSmall { os.exit(11i32) }

    // 12: squared Euclidean distance transform of A > 40 (scipy distance_transform_edt squared).
    above(img_a[..], 40.0f64, bits[..])
    if filter.distance_transform(bits[..], 32usize, 32usize, dst[..], scratch[..]) != ok { os.exit(12i32) }
    if digest(dst[..]) != 6426445925507953445u64 { os.exit(12i32) }

    // 13: eikonal: fast marching and fast sweeping agree at unit speed and over B's speed map.
    var ones: [1024]f64 = zero
    var speed: [1024]f64 = zero
    i = 0usize
    while i < 1024usize {
        ones[i] = 1.0f64
        speed[i] = 0.5f64 + img_b[i] / 300.0f64
        i += 1usize
    }
    let sources = [2]u32{ 165u32, 665u32 }
    if filter.fast_marching(ones[..], 32usize, 32usize, sources[..], dst[..], labels[..], work[..]) != ok { os.exit(13i32) }
    if digest(dst[..]) != 12145308852204622677u64 { os.exit(13i32) }
    if filter.fast_sweeping(ones[..], 32usize, 32usize, sources[..], gx[..], 4usize) != ok { os.exit(13i32) }
    if max_diff(dst[..], gx[..]) > 0.000000001f64 { os.exit(13i32) }
    if filter.fast_marching(speed[..], 32usize, 32usize, sources[..], dst[..], labels[..], work[..]) != ok { os.exit(13i32) }
    if digest(dst[..]) != 3511420916251423301u64 { os.exit(13i32) }
    if filter.fast_sweeping(speed[..], 32usize, 32usize, sources[..], gx[..], 8usize) != ok { os.exit(13i32) }
    if digest(gx[..]) != 3511420916251423301u64 { os.exit(13i32) }

    // 14: Laplacian pyramid of A, four levels, and its collapse.
    var pyramid: [1360]f64 = zero
    if filter.pyramid_size(32usize, 32usize, 4usize) != 1360usize { os.exit(14i32) }
    if filter.laplacian_pyramid(img_a[..], 32usize, 32usize, 4usize, pyramid[..], scratch[..]) != ok { os.exit(14i32) }
    if digest(pyramid[..]) != 1403669482298226441u64 { os.exit(14i32) }
    if filter.laplacian_collapse(pyramid[..], 32usize, 32usize, 4usize, dst[..], scratch[..]) != ok { os.exit(14i32) }
    if max_diff(dst[..], img_a[..]) > 0.000000001f64 { os.exit(14i32) }
    // an odd size round-trips too
    if filter.laplacian_pyramid(img_b[..357usize], 21usize, 17usize, 3usize, pyramid[..], scratch[..]) != ok { os.exit(14i32) }
    if filter.laplacian_collapse(pyramid[..], 21usize, 17usize, 3usize, dst[..], scratch[..]) != ok { os.exit(14i32) }
    if max_diff(dst[..357usize], img_b[..357usize]) > 0.000000001f64 { os.exit(14i32) }

    // 15: largest rectangle of ones in A > 100 (brute force agrees on the area).
    above(img_a[..], 100.0f64, bits[..])
    let (rect, rect_error) = filter.max_rectangle(bits[..], 32usize, 32usize, labels[..], work[..])
    if rect_error != ok || rect.x != 28usize || rect.y != 16usize || rect.w != 3usize || rect.h != 6usize || rect.area != 18usize { os.exit(15i32) }

    // 16: mean shift over B, spatial 3, range 40, five steps: 61 modes.
    var modes: [3072]f64 = zero
    let (mode_count, shift_error) = filter.mean_shift(img_b[..], 32usize, 32usize, 3.0f64, 40.0f64, 5usize, dst[..], modes[..])
    if shift_error != ok || mode_count != 61usize || digest(dst[..]) != 16336714507846542307u64 { os.exit(16i32) }

    // 17: watershed of B's blurred gradient from two markers (scikit-image watershed,
    // connectivity 1, agrees pixel for pixel: 143 and 881 pixels).
    if filter.gaussian_blur(img_b[..], 32usize, 32usize, 1.0f64, dst[..], scratch[..]) != ok { os.exit(17i32) }
    if filter.sobel(dst[..], 32usize, 32usize, gx[..], gy[..], mag[..]) != ok { os.exit(17i32) }
    var markers: [1024]u32 = zero
    markers[394usize] = 1u32
    markers[662usize] = 2u32
    var ages: [1024]u32 = zero
    if filter.watershed(mag[..], 32usize, 32usize, markers[..], labels[..], work[..1024usize], ages[..]) != ok { os.exit(17i32) }
    var count1 = 0usize
    var count2 = 0usize
    i = 0usize
    while i < 1024usize {
        if labels[i] == 1u32 { count1 += 1usize }
        if labels[i] == 2u32 { count2 += 1usize }
        i += 1usize
    }
    if count1 != 143usize || count2 != 881usize || digest_u32(labels[..]) != 14030671487551898344u64 { os.exit(17i32) }

    try io.print("gfx filter ok\n")
    ret ok
}
