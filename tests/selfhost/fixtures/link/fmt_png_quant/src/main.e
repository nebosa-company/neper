// `e.fmt.png.quantize` and `encode_quantized` (D2482) against scripts/gen_png_quant_test.py, an independent
// model of the rule: the most frequent colours kept (ties to the smaller value), the others mapped to the nearest kept
// one (ties to the smaller value). The pictures are generated here with the model's own LCG and integer rounding.
// Every check has its own exit code.

use e.fmt.png
use e.gfx.image
use e.io
use e.mem
use e.os

const W: usize = 48usize
const H: usize = 32usize

fn fnv(data: []const u8) -> u32 {
    var h = 2166136261u64
    var i = 0usize
    while i < data.len {
        h = ((h ^ u64(data[i])) * 16777619u64) & 4294967295u64
        i += 1usize
    }
    ret u32(h)
}

// The distinct colours of an Rgba8 buffer.
fn distinct(data: []const u8) -> usize {
    var seen: [4096]u32 = zero
    var used: [4096]bool = zero
    var n = 0usize
    var i = 0usize
    while i + 4usize <= data.len {
        let c = u32(data[i]) | (u32(data[i + 1usize]) << 8u32) | (u32(data[i + 2usize]) << 16u32) | (u32(data[i + 3usize]) << 24u32)
        var h = usize((u64(c) * 2654435761u64) >> 20u64) & 4095usize
        var found = false
        while used[h] && !found {
            if seen[h] == c { found = true } else { h = (h + 1usize) & 4095usize }
        }
        if !found {
            used[h] = true
            seen[h] = c
            n += 1usize
        }
        i += 4usize
    }
    ret n
}

// The model's picture: white with three inks at `levels` coverage levels.
fn picture(dst: []u8, seed: u64, levels: u32) {
    var s = seed
    var at = 0usize
    var i = 0usize
    while i < W * H {
        s = (s * 1103515245u64 + 12345u64) & 2147483647u64
        let v = u32(s >> 16u64)
        var r = 255u32
        var g = 255u32
        var b = 255u32
        if v % 5u32 == 0u32 {
            let which = (v >> 3u32) % 3u32
            let cov = 1u32 + (v >> 5u32) % levels
            var ir = 0u32
            var ig = 114u32
            var ib = 178u32
            if which == 1u32 {
                ir = 213u32
                ig = 94u32
                ib = 0u32
            }
            if which == 2u32 {
                ir = 60u32
                ig = 60u32
                ib = 60u32
            }
            r = ((255u32 * levels - (255u32 - ir) * cov) * 2u32 + levels) / (2u32 * levels)
            g = ((255u32 * levels - (255u32 - ig) * cov) * 2u32 + levels) / (2u32 * levels)
            b = ((255u32 * levels - (255u32 - ib) * cov) * 2u32 + levels) / (2u32 * levels)
        }
        dst[at] = u8(r)
        dst[at + 1usize] = u8(g)
        dst[at + 2usize] = u8(b)
        dst[at + 3usize] = 255u8
        at += 4usize
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var store: [6144]u8 = zero
    var src: [6144]u8 = zero
    // few: 7 colours in, k=256, 7 out
    picture(src[0..], 1u64, 2u32)
    let (img_few, n_few, e_few) = png.quantize(store[0..], image.ConstImage { pixels: src[0..], width: 48u32, height: 32u32, stride: 192usize, format: .Rgba8, alpha: .Straight }, 256usize)
    if e_few != ok { os.exit(10i32) }
    if n_few != 7usize { os.exit(11i32) }
    if fnv(img_few.pixels) != 444138666u32 { os.exit(12i32) }
    if distinct(img_few.pixels) > 256usize { os.exit(13i32) }
    // mid: 140 colours in, k=256, 140 out
    picture(src[0..], 2u64, 60u32)
    let (img_mid, n_mid, e_mid) = png.quantize(store[0..], image.ConstImage { pixels: src[0..], width: 48u32, height: 32u32, stride: 192usize, format: .Rgba8, alpha: .Straight }, 256usize)
    if e_mid != ok { os.exit(20i32) }
    if n_mid != 140usize { os.exit(21i32) }
    if fnv(img_mid.pixels) != 339623587u32 { os.exit(22i32) }
    if distinct(img_mid.pixels) > 256usize { os.exit(23i32) }
    // mid64: 140 colours in, k=64, 64 out
    picture(src[0..], 2u64, 60u32)
    let (img_mid64, n_mid64, e_mid64) = png.quantize(store[0..], image.ConstImage { pixels: src[0..], width: 48u32, height: 32u32, stride: 192usize, format: .Rgba8, alpha: .Straight }, 64usize)
    if e_mid64 != ok { os.exit(30i32) }
    if n_mid64 != 64usize { os.exit(31i32) }
    if fnv(img_mid64.pixels) != 1448005416u32 { os.exit(32i32) }
    if distinct(img_mid64.pixels) > 64usize { os.exit(33i32) }
    // mid16: 175 colours in, k=16, 16 out
    picture(src[0..], 3u64, 90u32)
    let (img_mid16, n_mid16, e_mid16) = png.quantize(store[0..], image.ConstImage { pixels: src[0..], width: 48u32, height: 32u32, stride: 192usize, format: .Rgba8, alpha: .Straight }, 16usize)
    if e_mid16 != ok { os.exit(40i32) }
    if n_mid16 != 16usize { os.exit(41i32) }
    if fnv(img_mid16.pixels) != 1927527961u32 { os.exit(42i32) }
    if distinct(img_mid16.pixels) > 16usize { os.exit(43i32) }
    // one: 84 colours in, k=1, 1 out
    picture(src[0..], 4u64, 30u32)
    let (img_one, n_one, e_one) = png.quantize(store[0..], image.ConstImage { pixels: src[0..], width: 48u32, height: 32u32, stride: 192usize, format: .Rgba8, alpha: .Straight }, 1usize)
    if e_one != ok { os.exit(50i32) }
    if n_one != 1usize { os.exit(51i32) }
    if fnv(img_one.pixels) != 3192706501u32 { os.exit(52i32) }
    if distinct(img_one.pixels) > 1usize { os.exit(53i32) }
    // encode_quantized: an indexed PNG whose decoded pixels are the quantized ones
    picture(src[0..], 2u64, 60u32)
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { os.exit(60i32) }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    let src_png = image.ConstImage { pixels: src[0..], width: 48u32, height: 32u32, stride: 192usize, format: .Rgba8, alpha: .Straight }
    if png.encode_quantized(&writer, src_png, png.EncodeOptions { compression: .Balanced, interlace: false }, 256usize, store[0..]) != ok { os.exit(61i32) }
    let file = io.memory_bytes(&held)
    if file.len < 40usize || file[25usize] != 3u8 { os.exit(62i32) }
    var reader_state = io.SliceReader { data: file, off: 0usize }
    let reader = io.slice_reader(&reader_state)
    let (back, decode_error) = png.decode(a, reader, png.DecodeOptions { max_width: 4096u32, max_height: 4096u32, max_pixels: 16777216u64, verify_crc: true })
    if decode_error != ok { os.exit(63i32) }
    if fnv(back.pixels[0..6144]) != 339623587u32 { os.exit(64i32) }
    // refusals
    var gray: [64]u8 = zero
    let (g1, g2, grey_error) = png.quantize(store[0..], image.ConstImage { pixels: gray[0..], width: 8u32, height: 8u32, stride: 8usize, format: .R8, alpha: .Opaque }, 16usize)
    if grey_error != png.Unsupported { os.exit(70i32) }
    let (z1, z2, zero_error) = png.quantize(store[0..], src_png, 0usize)
    if zero_error != png.Invalid { os.exit(71i32) }
    let (b1, b2, big_error) = png.quantize(store[0..], src_png, 257usize)
    if big_error != png.Invalid { os.exit(72i32) }
    ret ok
}
