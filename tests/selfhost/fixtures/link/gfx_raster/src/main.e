// `e.gfx.raster`: Bresenham lines and midpoint circles over LCG inputs agree
// with `skimage.draw` pixel sets (order-independent hash of every pixel plus
// the count), Xiaolin Wu coverage and the midpoint ellipse and top-left
// triangle fill agree with Python replicas, and two triangles on either
// diagonal of a rectangle partition it exactly. Each check exits with its own code.

use e.gfx.raster
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn mix(x: i32, y: i32) -> u64 {
    var v = u64(mem.bitcast[u32](x)) *% 11400714819323198485u64 +% u64(mem.bitcast[u32](y)) *% 14029467366897019727u64
    v ^= v >> 29u32
    ret v *% 13787848793156543929u64
}

fn hash_pixels(pixels: []const raster.Pixel) -> u64 {
    var s = 0u64
    var i = 0usize
    while i < pixels.len {
        s +%= mix(pixels[i].x, pixels[i].y)
        i += 1usize
    }
    ret s
}

fn overlap(a: []const raster.Pixel, b: []const raster.Pixel) -> bool {
    var i = 0usize
    while i < a.len {
        var j = 0usize
        while j < b.len {
            if a[i].x == b[j].x && a[i].y == b[j].y { ret true }
            j += 1usize
        }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 11u64
    var out: [512]raster.Pixel = zero

    // 1: 40 Bresenham lines against skimage.draw.line.
    var total = 0u64
    var count = 0usize
    var i = 0usize
    while i < 40usize {
        let x0 = i32(draw(&state) % 64u64) - 32i32
        let y0 = i32(draw(&state) % 64u64) - 32i32
        let x1 = i32(draw(&state) % 64u64) - 32i32
        let y1 = i32(draw(&state) % 64u64) - 32i32
        let (n, line_error) = raster.line(x0, y0, x1, y1, out[..])
        if line_error != ok { os.exit(1i32) }
        if out[0usize].x != x0 || out[0usize].y != y0 || out[n - 1usize].x != x1 || out[n - 1usize].y != y1 { os.exit(1i32) }
        total +%= hash_pixels(out[..n])
        count += n
        i += 1usize
    }
    if count != 1211usize || total != 16618920669277045007u64 { os.exit(1i32) }
    let (_, no_room) = raster.line(0i32, 0i32, 600i32, 0i32, out[..])
    if no_room != raster.TooSmall { os.exit(1i32) }

    // 2: 20 Xiaolin Wu lines: pixel hash and the coverage sum.
    var aa: [512]raster.Coverage = zero
    total = 0u64
    count = 0usize
    var coverage = 0.0f64
    i = 0usize
    while i < 20usize {
        let x0 = f64(draw(&state) % 6400u64) / 100.0f64 - 32.0f64
        let y0 = f64(draw(&state) % 6400u64) / 100.0f64 - 32.0f64
        let x1 = f64(draw(&state) % 6400u64) / 100.0f64 - 32.0f64
        let y1 = f64(draw(&state) % 6400u64) / 100.0f64 - 32.0f64
        let (n, aa_error) = raster.line_aa(x0, y0, x1, y1, aa[..])
        if aa_error != ok { os.exit(2i32) }
        var j = 0usize
        while j < n {
            total +%= mix(aa[j].x, aa[j].y)
            coverage += aa[j].coverage
            if aa[j].coverage < 0.0f64 || aa[j].coverage > 1.0f64 { os.exit(2i32) }
            j += 1usize
        }
        count += n
        i += 1usize
    }
    var d = coverage - 668.6400000000001f64
    if d < 0.0f64 { d = 0.0f64 - d }
    if count != 1378usize || total != 13500158851680521212u64 || d > 1.0e-9f64 { os.exit(2i32) }

    // 3: circles of radius 0..29 against skimage.draw.circle_perimeter.
    total = 0u64
    count = 0usize
    var radius = 0i32
    while radius < 30i32 {
        let cx = i32(draw(&state) % 20u64)
        let cy = i32(draw(&state) % 20u64)
        let (n, circle_error) = raster.circle(cx, cy, radius, out[..])
        if circle_error != ok { os.exit(3i32) }
        if overlap(out[..n / 2usize], out[n / 2usize..n]) { os.exit(3i32) }
        total +%= hash_pixels(out[..n])
        count += n
        radius += 1i32
    }
    if count != 2461usize || total != 11902945223750767718u64 { os.exit(3i32) }

    // 4: 20 ellipses against the midpoint replica.
    total = 0u64
    count = 0usize
    i = 0usize
    while i < 20usize {
        let cx = i32(draw(&state) % 20u64)
        let cy = i32(draw(&state) % 20u64)
        let rx = 3i32 + i32(draw(&state) % 22u64)
        let ry = 3i32 + i32(draw(&state) % 22u64)
        let (n, ellipse_error) = raster.ellipse(cx, cy, rx, ry, out[..])
        if ellipse_error != ok { os.exit(4i32) }
        total +%= hash_pixels(out[..n])
        count += n
        i += 1usize
    }
    if count != 1568usize || total != 13234415563870094486u64 { os.exit(4i32) }

    // 5: 20 triangles against the top-left replica.
    total = 0u64
    count = 0usize
    i = 0usize
    while i < 20usize {
        var v: [6]f64 = zero
        var j = 0usize
        while j < 6usize {
            v[j] = f64(draw(&state) % 3200u64) / 100.0f64 - 16.0f64
            j += 1usize
        }
        let (n, fill_error) = raster.fill_triangle(v[0usize], v[1usize], v[2usize], v[3usize], v[4usize], v[5usize], out[..])
        if fill_error != ok { os.exit(5i32) }
        total +%= hash_pixels(out[..n])
        count += n
        i += 1usize
    }
    if count != 1079usize || total != 1384684408952073916u64 { os.exit(5i32) }

    // 6: a 20x12 rectangle split along either diagonal is covered once.
    var other: [512]raster.Pixel = zero
    let (na, _) = raster.fill_triangle(0.5f64, 0.5f64, 20.5f64, 0.5f64, 20.5f64, 12.5f64, out[..])
    let (nb, _) = raster.fill_triangle(0.5f64, 0.5f64, 20.5f64, 12.5f64, 0.5f64, 12.5f64, other[..])
    if na != 126usize || nb != 114usize || overlap(out[..na], other[..nb]) { os.exit(6i32) }
    let (nc, _) = raster.fill_triangle(20.5f64, 0.5f64, 0.5f64, 0.5f64, 0.5f64, 12.5f64, out[..])
    let (nd, _) = raster.fill_triangle(20.5f64, 0.5f64, 0.5f64, 12.5f64, 20.5f64, 12.5f64, other[..])
    if nc != 134usize || nd != 106usize || overlap(out[..nc], other[..nd]) { os.exit(6i32) }
    let (degenerate, _) = raster.fill_triangle(0.0f64, 0.0f64, 5.0f64, 5.0f64, 10.0f64, 10.0f64, out[..])
    if degenerate != 0usize { os.exit(6i32) }

    try io.print("gfx raster ok\n")
    ret ok
}
