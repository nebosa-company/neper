// QOI ("Quite OK Image") decoder (L124): the 14-byte header, then the six chunk kinds -- RGB,
// RGBA, INDEX into the 64-entry running table, DIFF, LUMA and RUN -- exactly as the
// specification's reference decoder reads them. The result is Rgba8, `Opaque` for three
// channels and `Straight` for four. Dimensions are checked against the options (zero
// selects 16,384 per side and 16,777,216 pixels, as for PNG) before any pixel is taken, a
// stream that ends before the last pixel is `Invalid`, and the data is read from the
// reader up to a bound. Decode only.

use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64 }
error Invalid
error Unsupported
error TooLarge

const READ_LIMIT: usize = 1073741824usize

fn be32(d: []const u8, at: usize) -> u32 {
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

fn header(data: []const u8) -> (image.Info, u8, err) {
    var info: image.Info = zero
    if data.len < 14usize { ret (info, 0u8, Invalid) }
    if data[0] != 113u8 || data[1] != 111u8 || data[2] != 105u8 || data[3] != 102u8 { ret (info, 0u8, Invalid) }
    let w = be32(data, 4usize)
    let h = be32(data, 8usize)
    let channels = data[12]
    if w == 0u32 || h == 0u32 { ret (info, 0u8, Invalid) }
    if channels != 3u8 && channels != 4u8 { ret (info, 0u8, Invalid) }
    if data[13] > 1u8 { ret (info, 0u8, Invalid) }
    info.width = w
    info.height = h
    info.format = .Rgba8
    info.frames = 1u32
    if channels == 3u8 { info.alpha = .Opaque } else { info.alpha = .Straight }
    ret (info, channels, ok)
}

fn within(w: u32, h: u32, options: DecodeOptions) -> err {
    var max_w = options.max_width
    var max_h = options.max_height
    var max_pixels = options.max_pixels
    if max_w == 0u32 { max_w = 16384u32 }
    if max_h == 0u32 { max_h = 16384u32 }
    if max_pixels == 0u64 { max_pixels = 16777216u64 }
    if w > max_w || h > max_h { ret TooLarge }
    if u64(w) * u64(h) > max_pixels { ret TooLarge }
    ret ok
}

fn inspect(source: io.Reader) -> (image.Info, err) {
    var r = source
    var head: [14]u8 = zero
    let got = io.read_exact(&r, head[0..])
    if got != ok { ret (zero, Invalid) }
    let (info, channels, failure) = header(head[0..])
    ret (info, failure)
}

fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var r = source
    let (data, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (zero, read_error) }
    let (info, channels, header_error) = header(data)
    if header_error != ok { ret (zero, header_error) }
    let within_error = within(info.width, info.height, options)
    if within_error != ok { ret (zero, within_error) }
    let (out, out_error) = image.allocate(a, info.width, info.height, .Rgba8, info.alpha)
    if out_error != ok { ret (zero, out_error) }
    let total = usize(info.width) * usize(info.height)
    var index: [256]u8 = zero
    var r8 = 0u8
    var g8 = 0u8
    var b8 = 0u8
    var a8 = 255u8
    var at = 14usize
    var run = 0u32
    var p = 0usize
    while p < total {
        if run > 0u32 {
            run -= 1u32
        } else {
            if at >= data.len { ret (zero, Invalid) }
            let tag = data[at]
            at += 1usize
            if tag == 254u8 {
                if at + 3usize > data.len { ret (zero, Invalid) }
                r8 = data[at]
                g8 = data[at + 1usize]
                b8 = data[at + 2usize]
                at += 3usize
            } else if tag == 255u8 {
                if at + 4usize > data.len { ret (zero, Invalid) }
                r8 = data[at]
                g8 = data[at + 1usize]
                b8 = data[at + 2usize]
                a8 = data[at + 3usize]
                at += 4usize
            } else if (tag & 192u8) == 0u8 {
                let slot = usize(tag) * 4usize
                r8 = index[slot]
                g8 = index[slot + 1usize]
                b8 = index[slot + 2usize]
                a8 = index[slot + 3usize]
            } else if (tag & 192u8) == 64u8 {
                r8 = r8 +% (((tag >> 4u32) & 3u8) -% 2u8)
                g8 = g8 +% (((tag >> 2u32) & 3u8) -% 2u8)
                b8 = b8 +% ((tag & 3u8) -% 2u8)
            } else if (tag & 192u8) == 128u8 {
                if at >= data.len { ret (zero, Invalid) }
                let second = data[at]
                at += 1usize
                let dg = (tag & 63u8) -% 32u8
                r8 = r8 +% (dg +% (((second >> 4u32) & 15u8) -% 8u8))
                g8 = g8 +% dg
                b8 = b8 +% (dg +% ((second & 15u8) -% 8u8))
            } else {
                run = u32(tag & 63u8)
            }
            let slot = usize((u32(r8) * 3u32 + u32(g8) * 5u32 + u32(b8) * 7u32 + u32(a8) * 11u32) % 64u32) * 4usize
            index[slot] = r8
            index[slot + 1usize] = g8
            index[slot + 2usize] = b8
            index[slot + 3usize] = a8
        }
        let row = p / usize(info.width)
        let col = p % usize(info.width)
        let o = row * out.stride + col * 4usize
        out.pixels[o] = r8
        out.pixels[o + 1usize] = g8
        out.pixels[o + 2usize] = b8
        out.pixels[o + 3usize] = a8
        p += 1usize
    }
    ret (out, ok)
}
