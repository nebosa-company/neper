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

// x^(1/2.4) as the inverse of `paint.pow24`: y with y^12 = x^5, by Newton from 1,
// which walks down to the root and never through a vanishing derivative.
fn root24(x: f32) -> f32 {
    if x <= 0.0 { ret 0.0 }
    if x >= 1.0 { ret 1.0 }
    let x5 = x * x * x * x * x
    var y: f32 = 1.0
    var i = 0usize
    while i < 60usize {
        let y11 = y * y * y * y * y * y * y * y * y * y * y
        y = y - (y11 * y - x5) / (12.0 * y11)
        i += 1usize
    }
    ret y
}

// The 8-bit sRGB code of a linear channel, rounded to nearest.
fn srgb_byte(linear: f32) -> u8 {
    var c = linear
    if c < 0.0 { c = 0.0 }
    if c > 1.0 { c = 1.0 }
    var encoded: f32 = 0.0
    if c <= 0.0031308 {
        encoded = c * 12.92
    } else {
        encoded = 1.055 * root24(c) - 0.055
    }
    var v = i32(encoded * 255.0 + 0.5)
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
