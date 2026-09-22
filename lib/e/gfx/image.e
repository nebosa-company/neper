// Pixel views over caller memory: a width, a height, a row stride in bytes and one of
// four formats -- `R8` one byte, `Rgba8` and `Bgra8` four, `Rgba16Float` eight -- with
// the alpha convention named beside them. A view is made over bytes the caller owns
// (`make`, `make_const`) or over bytes taken once from an arena (`allocate`, tightly
// packed); `required_bytes` is the size the stride and dimensions demand, `TooLarge`
// when it does not fit, `Invalid` when the stride is shorter than a row. Nothing here
// decodes, encodes or uploads: `e.fmt.*` and `e.gfx.scene` do those.
//
// `clear` writes a colour into every pixel, `copy` blits a source onto a destination
// at an origin, clipping to the destination and refusing a format that differs (a
// pixel is bytes here, and converting them is a `paint` question, not a view's). A
// colour goes into 8-bit channels as sRGB: the inverse of `paint.srgb8`'s transfer,
// so a round trip through the two is the identity on every byte; into `R8` as the
// red channel; into `Rgba16Float` as IEEE half floats of the linear value.
//
// The measures and hashes read 8-bit views (`R8`, `Rgba8`, `Bgra8`; a half-float view
// is `Invalid`): `psnr` over every channel byte, the rest over the luma PIL's `L`
// mode takes, `(19595 R + 38470 G + 7471 B + 32768) >> 16`. `ssim` is the uniform
// 8x8-window index with K1 0.01, K2 0.03 and population variance, averaged over every
// window that fits. `ahash`, `dhash` and `phash` shrink by integer box averages
// (`floor(i * source / target)` to the next box start, at least one pixel) and pack
// the bits row-major, first bit highest, as `imagehash` does; `hamming_distance`
// counts the bits two hashes differ in.

use e.bytes
use e.math
use e.math.fft
use e.mem
use e.gfx.geometry
use e.gfx.paint

type Format = enum u8 { R8, Rgba8, Bgra8, Rgba16Float }
type Alpha = enum u8 { Opaque, Straight, Premultiplied }
type Info = struct { width: u32, height: u32, format: Format, alpha: Alpha, frames: u32 }
type Image = struct { pixels: []u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha }
type ConstImage = struct { pixels: []const u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha }
error Invalid
error TooLarge

const MAX_PIXELS: u64 = 1073741824u64

fn bytes_per_pixel(format: Format) -> usize {
    if format == .R8 { ret 1usize }
    if format == .Rgba16Float { ret 8usize }
    ret 4usize
}

fn required_bytes(width: u32, height: u32, format: Format, stride: usize) -> (usize, err) {
    if u64(width) * u64(height) > MAX_PIXELS { ret (0usize, TooLarge) }
    let row = usize(width) * bytes_per_pixel(format)
    if stride < row { ret (0usize, Invalid) }
    if height == 0u32 { ret (0usize, ok) }
    if stride > 18446744073709551615usize / usize(height) { ret (0usize, TooLarge) }
    ret (stride * (usize(height) - 1usize) + row, ok)
}

fn make(pixels: []u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha) -> (Image, err) {
    let (needed, needed_error) = required_bytes(width, height, format, stride)
    if needed_error != ok { ret (zero, needed_error) }
    if pixels.len < needed { ret (zero, Invalid) }
    ret (Image { pixels: pixels, width: width, height: height, stride: stride, format: format, alpha: alpha }, ok)
}

fn make_const(pixels: []const u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha) -> (ConstImage, err) {
    let (needed, needed_error) = required_bytes(width, height, format, stride)
    if needed_error != ok { ret (zero, needed_error) }
    if pixels.len < needed { ret (zero, Invalid) }
    ret (ConstImage { pixels: pixels, width: width, height: height, stride: stride, format: format, alpha: alpha }, ok)
}

fn allocate(a: *mem.Arena, width: u32, height: u32, format: Format, alpha: Alpha) -> (Image, err) {
    let stride = usize(width) * bytes_per_pixel(format)
    let (needed, needed_error) = required_bytes(width, height, format, stride)
    if needed_error != ok { ret (zero, needed_error) }
    let (pixels, alloc_error) = mem.alloc[u8](a, needed)
    if alloc_error != ok { ret (zero, alloc_error) }
    var i = 0usize
    while i < needed {
        pixels[i] = 0u8
        i += 1usize
    }
    ret (Image { pixels: pixels, width: width, height: height, stride: stride, format: format, alpha: alpha }, ok)
}

// The 8-bit sRGB code of a linear channel, rounded to nearest.
fn srgb_byte(linear: f32) -> u8 {
    var v = i32(paint.linear_to_srgb(linear) * 255.0 + 0.5)
    if v < 0i32 { v = 0i32 }
    if v > 255i32 { v = 255i32 }
    ret u8(v)
}

fn unit_byte(v: f32) -> u8 {
    var c = v
    if c < 0.0 { c = 0.0 }
    if c > 1.0 { c = 1.0 }
    ret u8(i32(c * 255.0 + 0.5))
}

// IEEE binary16 of a value in `0..1`, rounded to nearest even; zero stays zero.
fn half_bits(v: f32) -> u32 {
    let bits = mem.bitcast[u32](v)
    let sign = (bits >> 16u32) & 32768u32
    let exponent = i32((bits >> 23u32) & 255u32) - 127i32 + 15i32
    let mantissa = bits & 8388607u32
    if (bits & 2147483647u32) == 0u32 { ret sign }
    if exponent >= 31i32 { ret sign | 31744u32 }
    if exponent <= 0i32 {
        if exponent < -10i32 { ret sign }
        let full = mantissa | 8388608u32
        let shift = u32(14i32 - exponent)
        var sub = full >> shift
        let rest = full & ((1u32 << shift) - 1u32)
        let half = 1u32 << (shift - 1u32)
        if rest > half || (rest == half && (sub & 1u32) != 0u32) { sub += 1u32 }
        ret sign | sub
    }
    var out = sign | (u32(exponent) << 10u32) | (mantissa >> 13u32)
    let rest = mantissa & 8191u32
    if rest > 4096u32 || (rest == 4096u32 && (out & 1u32) != 0u32) { out += 1u32 }
    ret out
}

fn put16(pixels: []u8, at: usize, v: u32) {
    pixels[at] = u8(v & 255u32)
    pixels[at + 1usize] = u8(v >> 8u32)
}

fn clear(image: Image, color: paint.Color) {
    var pixel: [8]u8 = zero
    let width = bytes_per_pixel(image.format)
    if image.format == .R8 {
        pixel[0] = srgb_byte(color.red)
    } else if image.format == .Rgba8 {
        pixel[0] = srgb_byte(color.red)
        pixel[1] = srgb_byte(color.green)
        pixel[2] = srgb_byte(color.blue)
        pixel[3] = unit_byte(color.alpha)
    } else if image.format == .Bgra8 {
        pixel[0] = srgb_byte(color.blue)
        pixel[1] = srgb_byte(color.green)
        pixel[2] = srgb_byte(color.red)
        pixel[3] = unit_byte(color.alpha)
    } else {
        put16(pixel[0..], 0usize, half_bits(color.red))
        put16(pixel[0..], 2usize, half_bits(color.green))
        put16(pixel[0..], 4usize, half_bits(color.blue))
        put16(pixel[0..], 6usize, half_bits(color.alpha))
    }
    var y = 0usize
    while y < usize(image.height) {
        var at = y * image.stride
        var x = 0usize
        while x < usize(image.width) {
            mem.copy[u8](image.pixels[at..at + width], pixel[..width])
            at += width
            x += 1usize
        }
        y += 1usize
    }
}

// Blits `src` at `dst_origin` (whole pixels: the origin is truncated), clipped to `dst`.
fn copy(dst: Image, src: ConstImage, dst_origin: geometry.Point) -> err {
    if dst.format != src.format { ret Invalid }
    let width = bytes_per_pixel(dst.format)
    let ox = i64(dst_origin.x)
    let oy = i64(dst_origin.y)
    var sy = 0i64
    while sy < i64(src.height) {
        let dy = oy + sy
        if dy >= 0i64 && dy < i64(dst.height) {
            var sx_start = 0i64
            if ox < 0i64 { sx_start = 0i64 - ox }
            var sx_end = i64(src.width)
            if ox + sx_end > i64(dst.width) { sx_end = i64(dst.width) - ox }
            if sx_end > sx_start {
                let count = usize(sx_end - sx_start) * width
                let from = usize(sy) * src.stride + usize(sx_start) * width
                let to = usize(dy) * dst.stride + usize(ox + sx_start) * width
                mem.copy[u8](dst.pixels[to..to + count], src.pixels[from..from + count])
            }
        }
        sy += 1i64
    }
    ret ok
}

fn eight_bit(image: ConstImage) -> bool {
    ret image.format != .Rgba16Float
}

fn psnr(a: ConstImage, b: ConstImage) -> (f64, err) {
    if a.width != b.width || a.height != b.height || a.format != b.format || !eight_bit(a) { ret (0.0f64, Invalid) }
    let row = usize(a.width) * bytes_per_pixel(a.format)
    if row == 0usize || a.height == 0u32 { ret (0.0f64, Invalid) }
    var sum = 0.0f64
    var y = 0usize
    while y < usize(a.height) {
        var i = 0usize
        while i < row {
            let d = f64(a.pixels[y * a.stride + i]) - f64(b.pixels[y * b.stride + i])
            sum += d * d
            i += 1usize
        }
        y += 1usize
    }
    if sum == 0.0f64 { ret (math.inf64(), ok) }
    let mse = sum / (f64(row) * f64(a.height))
    ret (10.0f64 * math.log10[f64](65025.0f64 / mse), ok)
}

// The luma byte of the pixel at `(x, y)`.
fn luma(image: ConstImage, x: usize, y: usize) -> u32 {
    let at = y * image.stride + x * bytes_per_pixel(image.format)
    if image.format == .R8 { ret u32(image.pixels[at]) }
    var r = u32(image.pixels[at])
    var b = u32(image.pixels[at + 2usize])
    if image.format == .Bgra8 {
        r = u32(image.pixels[at + 2usize])
        b = u32(image.pixels[at])
    }
    ret (19595u32 * r + 38470u32 * u32(image.pixels[at + 1usize]) + 7471u32 * b + 32768u32) >> 16u32
}

fn ssim(a: ConstImage, b: ConstImage) -> (f64, err) {
    if a.width != b.width || a.height != b.height || !eight_bit(a) || !eight_bit(b) { ret (0.0f64, Invalid) }
    if a.width < 8u32 || a.height < 8u32 { ret (0.0f64, Invalid) }
    let c1 = 6.5025f64
    let c2 = 58.5225f64
    var total = 0.0f64
    var windows = 0usize
    var y = 0usize
    while y + 8usize <= usize(a.height) {
        var x = 0usize
        while x + 8usize <= usize(a.width) {
            var sa = 0.0f64
            var sb = 0.0f64
            var saa = 0.0f64
            var sbb = 0.0f64
            var sab = 0.0f64
            var v = 0usize
            while v < 8usize {
                var u = 0usize
                while u < 8usize {
                    let pa = f64(luma(a, x + u, y + v))
                    let pb = f64(luma(b, x + u, y + v))
                    sa += pa
                    sb += pb
                    saa += pa * pa
                    sbb += pb * pb
                    sab += pa * pb
                    u += 1usize
                }
                v += 1usize
            }
            let ma = sa / 64.0f64
            let mb = sb / 64.0f64
            let va = saa / 64.0f64 - ma * ma
            let vb = sbb / 64.0f64 - mb * mb
            let cov = sab / 64.0f64 - ma * mb
            total += ((2.0f64 * ma * mb + c1) * (2.0f64 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
            windows += 1usize
            x += 1usize
        }
        y += 1usize
    }
    ret (total / f64(windows), ok)
}

// The mean luma of the box that cell `(cx, cy)` of a `cols x rows` grid covers.
fn cell_mean(image: ConstImage, cols: usize, rows: usize, cx: usize, cy: usize) -> f32 {
    let x0 = cx * usize(image.width) / cols
    var x1 = (cx + 1usize) * usize(image.width) / cols
    if x1 <= x0 { x1 = x0 + 1usize }
    let y0 = cy * usize(image.height) / rows
    var y1 = (cy + 1usize) * usize(image.height) / rows
    if y1 <= y0 { y1 = y0 + 1usize }
    var sum = 0u32
    var y = y0
    while y < y1 {
        var x = x0
        while x < x1 {
            sum += luma(image, x, y)
            x += 1usize
        }
        y += 1usize
    }
    ret f32(sum) / f32((x1 - x0) * (y1 - y0))
}

fn hashable(image: ConstImage) -> bool {
    ret eight_bit(image) && image.width > 0u32 && image.height > 0u32
}

// Average hash: 8x8 cells, a bit where a cell is brighter than their mean.
fn ahash(image: ConstImage) -> (u64, err) {
    if !hashable(image) { ret (0u64, Invalid) }
    var cells: [64]f32 = zero
    var mean: f32 = 0.0
    var i = 0usize
    while i < 64usize {
        cells[i] = cell_mean(image, 8usize, 8usize, i % 8usize, i / 8usize)
        mean += cells[i]
        i += 1usize
    }
    mean = mean / 64.0
    var hash = 0u64
    i = 0usize
    while i < 64usize {
        hash = hash << 1u32
        if cells[i] > mean { hash |= 1u64 }
        i += 1usize
    }
    ret (hash, ok)
}

// Difference hash: 9x8 cells, a bit where a cell is brighter than its left neighbour.
fn dhash(image: ConstImage) -> (u64, err) {
    if !hashable(image) { ret (0u64, Invalid) }
    var hash = 0u64
    var y = 0usize
    while y < 8usize {
        var previous = cell_mean(image, 9usize, 8usize, 0usize, y)
        var x = 1usize
        while x < 9usize {
            let current = cell_mean(image, 9usize, 8usize, x, y)
            hash = hash << 1u32
            if current > previous { hash |= 1u64 }
            previous = current
            x += 1usize
        }
        y += 1usize
    }
    ret (hash, ok)
}

// Perceptual hash: 32x32 cells, the 2D DCT-II, a bit where one of the lowest 8x8
// coefficients (the DC among them) is above their median.
fn phash(image: ConstImage) -> (u64, err) {
    if !hashable(image) { ret (0u64, Invalid) }
    var grid: [1024]f64 = zero
    var line: [32]f64 = zero
    var i = 0usize
    while i < 1024usize {
        grid[i] = f64(cell_mean(image, 32usize, 32usize, i % 32usize, i / 32usize))
        i += 1usize
    }
    var y = 0usize
    while y < 32usize {
        let e = fft.dct2(grid[y * 32usize..y * 32usize + 32usize], line[..])
        if e != ok { ret (0u64, e) }
        mem.copy[f64](grid[y * 32usize..y * 32usize + 32usize], line[..])
        y += 1usize
    }
    var column: [32]f64 = zero
    var x = 0usize
    while x < 32usize {
        i = 0usize
        while i < 32usize {
            column[i] = grid[i * 32usize + x]
            i += 1usize
        }
        let e = fft.dct2(column[..], line[..])
        if e != ok { ret (0u64, e) }
        i = 0usize
        while i < 32usize {
            grid[i * 32usize + x] = line[i]
            i += 1usize
        }
        x += 1usize
    }
    var low: [64]f64 = zero
    var sorted: [64]f64 = zero
    i = 0usize
    while i < 64usize {
        low[i] = grid[(i / 8usize) * 32usize + i % 8usize]
        var j = i
        while j > 0usize && sorted[j - 1usize] > low[i] {
            sorted[j] = sorted[j - 1usize]
            j -= 1usize
        }
        sorted[j] = low[i]
        i += 1usize
    }
    let median = (sorted[31usize] + sorted[32usize]) / 2.0f64
    var hash = 0u64
    i = 0usize
    while i < 64usize {
        hash = hash << 1u32
        if low[i] > median { hash |= 1u64 }
        i += 1usize
    }
    ret (hash, ok)
}

fn hamming_distance(a: u64, b: u64) -> u32 {
    ret bytes.count_ones[u64](a ^ b)
}
