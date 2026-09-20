// PNG both ways over `e.algo.deflate`. Decoding takes every standard colour type at
// every depth (greyscale 1-16, RGB 8/16, indexed 1-8, grey+alpha and RGBA 8/16), the
// tRNS chunk for indexed, grey and RGB transparency, and Adam7 interlacing; it answers
// `image.R8` for opaque greyscale and `image.Rgba8` for everything else, a 16-bit
// sample keeping its high byte. `inspect` reads only the header chunks, counting
// frames from an APNG `acTL` when there is one. Dimensions are checked against the
// options before any pixel memory is taken: a zero limit is no limit. `verify_crc`
// checks every chunk's CRC-32 and the zlib Adler-32; off, they are skipped, which is
// what a reader of a trusted file saves.
//
// Encoding writes greyscale 8 from `R8`, RGB or RGBA 8 from `Rgba8` and `Bgra8`
// (opaque alpha drops the channel), and refuses `Rgba16Float`. Every row goes out
// with filter `None` straight from the caller's pixels -- deterministic, no row
// scratch, so `encode` needs no arena; the deflate encoder's state lives in a stack
// arena. ponytail: `Sub` or `Paeth` filtering would shrink the output and needs a row
// buffer; add it beside a `Level` that asks for it. `interlace` writes the seven Adam7
// passes, which a decoder reads back into the same pixels.

use e.algo.deflate
use e.bytes
use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64, verify_crc: bool }
type EncodeOptions = struct { compression: deflate.Level, interlace: bool }
error Invalid
error Unsupported
error Checksum
error TooLarge

const READ_LIMIT: usize = 1073741824usize
const WINDOW: usize = 32768usize

type Header = struct { width: u32, height: u32, depth: u32, color: u32, interlace: bool, frames: u32 }

fn be32(d: []const u8, at: usize) -> u32 {
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

fn crc32_update(crc: u32, d: []const u8) -> u32 {
    var c = crc
    var i = 0usize
    while i < d.len {
        c = c ^ u32(d[i])
        var k = 0usize
        while k < 8usize {
            if (c & 1u32) != 0u32 { c = (c >> 1u32) ^ 3988292384u32 } else { c = c >> 1u32 }
            k += 1usize
        }
        i += 1usize
    }
    ret c
}

fn crc32(type_and_data: []const u8) -> u32 {
    ret crc32_update(4294967295u32, type_and_data) ^ 4294967295u32
}

fn adler32_update(state: u32, d: []const u8) -> u32 {
    var a = state & 65535u32
    var b = state >> 16u32
    var i = 0usize
    while i < d.len {
        a = (a + u32(d[i])) % 65521u32
        b = (b + a) % 65521u32
        i += 1usize
    }
    ret (b << 16u32) | a
}

fn channels_of(color: u32) -> usize {
    if color == 2u32 { ret 3usize }
    if color == 4u32 { ret 2usize }
    if color == 6u32 { ret 4usize }
    ret 1usize
}

fn depth_ok(color: u32, depth: u32) -> bool {
    if color == 0u32 { ret depth == 1u32 || depth == 2u32 || depth == 4u32 || depth == 8u32 || depth == 16u32 }
    if color == 3u32 { ret depth == 1u32 || depth == 2u32 || depth == 4u32 || depth == 8u32 }
    if color == 2u32 || color == 4u32 || color == 6u32 { ret depth == 8u32 || depth == 16u32 }
    ret false
}

fn parse_header(ihdr: []const u8) -> (Header, err) {
    if ihdr.len != 13usize { ret (zero, Invalid) }
    var h: Header = zero
    h.width = be32(ihdr, 0usize)
    h.height = be32(ihdr, 4usize)
    h.depth = u32(ihdr[8])
    h.color = u32(ihdr[9])
    if h.width == 0u32 || h.height == 0u32 || h.width > 2147483647u32 || h.height > 2147483647u32 { ret (zero, Invalid) }
    if !depth_ok(h.color, h.depth) { ret (zero, Invalid) }
    if ihdr[10] != 0u8 || ihdr[11] != 0u8 { ret (zero, Unsupported) }
    if ihdr[12] > 1u8 { ret (zero, Invalid) }
    h.interlace = ihdr[12] == 1u8
    h.frames = 1u32
    ret (h, ok)
}

fn signature_ok(d: []const u8) -> bool {
    if d.len < 8usize { ret false }
    ret d[0] == 137u8 && d[1] == 80u8 && d[2] == 78u8 && d[3] == 71u8 && d[4] == 13u8 && d[5] == 10u8 && d[6] == 26u8 && d[7] == 10u8
}

fn info_of(h: Header, has_trns: bool) -> image.Info {
    var format: image.Format = .Rgba8
    var alpha: image.Alpha = .Straight
    if h.color == 0u32 && !has_trns {
        format = .R8
        alpha = .Opaque
    } else if (h.color == 2u32 || h.color == 3u32) && !has_trns {
        alpha = .Opaque
    }
    ret image.Info { width: h.width, height: h.height, format: format, alpha: alpha, frames: h.frames }
}

// Reads chunk by chunk up to the first IDAT, keeping only what the header says.
fn inspect(source: io.Reader) -> (image.Info, err) {
    var r = source
    var head: [8]u8 = zero
    if io.read_exact(&r, head[0..]) != ok { ret (zero, Invalid) }
    if !signature_ok(head[0..]) { ret (zero, Invalid) }
    var header: Header = zero
    var seen_header = false
    var has_trns = false
    var scratch: [4096]u8 = zero
    while true {
        var prefix: [8]u8 = zero
        if io.read_exact(&r, prefix[0..]) != ok { ret (zero, Invalid) }
        let length = usize(be32(prefix[0..], 0usize))
        let kind = be32(prefix[0..], 4usize)
        if length > 2147483647usize { ret (zero, Invalid) }
        if kind == 1229472850u32 {
            var ihdr: [13]u8 = zero
            if length != 13usize || io.read_exact(&r, ihdr[0..]) != ok { ret (zero, Invalid) }
            let (parsed, parse_error) = parse_header(ihdr[0..])
            if parse_error != ok { ret (zero, parse_error) }
            header = parsed
            seen_header = true
            var crc: [4]u8 = zero
            if io.read_exact(&r, crc[0..]) != ok { ret (zero, Invalid) }
            continue
        }
        if !seen_header { ret (zero, Invalid) }
        if kind == 1229209940u32 { break }
        if kind == 1633899596u32 && length >= 4usize {
            var body: [8]u8 = zero
            if io.read_exact(&r, body[0..]) != ok { ret (zero, Invalid) }
            header.frames = be32(body[0..], 0usize)
            if header.frames == 0u32 { header.frames = 1u32 }
            var rest = length + 4usize - 8usize
            while rest > 0usize {
                var take = rest
                if take > 4096usize { take = 4096usize }
                if io.read_exact(&r, scratch[..take]) != ok { ret (zero, Invalid) }
                rest -= take
            }
            continue
        }
        if kind == 1951551059u32 { has_trns = true }
        var rest = length + 4usize
        while rest > 0usize {
            var take = rest
            if take > 4096usize { take = 4096usize }
            if io.read_exact(&r, scratch[..take]) != ok { ret (zero, Invalid) }
            rest -= take
        }
    }
    ret (info_of(header, has_trns), ok)
}

fn within(h: Header, options: DecodeOptions) -> err {
    if options.max_width != 0u32 && h.width > options.max_width { ret TooLarge }
    if options.max_height != 0u32 && h.height > options.max_height { ret TooLarge }
    if options.max_pixels != 0u64 && u64(h.width) * u64(h.height) > options.max_pixels { ret TooLarge }
    ret ok
}

type Pass = struct { x0: usize, y0: usize, dx: usize, dy: usize }

fn pass_of(index: usize) -> Pass {
    if index == 0usize { ret Pass { x0: 0usize, y0: 0usize, dx: 8usize, dy: 8usize } }
    if index == 1usize { ret Pass { x0: 4usize, y0: 0usize, dx: 8usize, dy: 8usize } }
    if index == 2usize { ret Pass { x0: 0usize, y0: 4usize, dx: 4usize, dy: 8usize } }
    if index == 3usize { ret Pass { x0: 2usize, y0: 0usize, dx: 4usize, dy: 4usize } }
    if index == 4usize { ret Pass { x0: 0usize, y0: 2usize, dx: 2usize, dy: 4usize } }
    if index == 5usize { ret Pass { x0: 1usize, y0: 0usize, dx: 2usize, dy: 2usize } }
    ret Pass { x0: 0usize, y0: 1usize, dx: 1usize, dy: 2usize }
}

fn pass_size(p: Pass, width: usize, height: usize) -> (usize, usize) {
    var w = 0usize
    if width > p.x0 { w = (width - p.x0 + p.dx - 1usize) / p.dx }
    var h = 0usize
    if height > p.y0 { h = (height - p.y0 + p.dy - 1usize) / p.dy }
    ret (w, h)
}

fn row_bytes(width: usize, channels: usize, depth: usize) -> usize {
    ret (width * channels * depth + 7usize) / 8usize
}

fn paeth(a: u32, b: u32, c: u32) -> u32 {
    let p = i32(a) + i32(b) - i32(c)
    var pa = p - i32(a)
    if pa < 0i32 { pa = 0i32 - pa }
    var pb = p - i32(b)
    if pb < 0i32 { pb = 0i32 - pb }
    var pc = p - i32(c)
    if pc < 0i32 { pc = 0i32 - pc }
    if pa <= pb && pa <= pc { ret a }
    if pb <= pc { ret b }
    ret c
}

// Undoes one row's filter in place, `previous` being the row above or empty.
fn unfilter(kind: u8, row: []u8, previous: []const u8, bpp: usize) -> err {
    if kind > 4u8 { ret Invalid }
    var i = 0usize
    while i < row.len {
        var left = 0u32
        if i >= bpp { left = u32(row[i - bpp]) }
        var up = 0u32
        if previous.len != 0usize { up = u32(previous[i]) }
        var corner = 0u32
        if i >= bpp && previous.len != 0usize { corner = u32(previous[i - bpp]) }
        var value = u32(row[i])
        if kind == 1u8 { value += left }
        if kind == 2u8 { value += up }
        if kind == 3u8 { value += (left + up) / 2u32 }
        if kind == 4u8 { value += paeth(left, up, corner) }
        row[i] = u8(value & 255u32)
        i += 1usize
    }
    ret ok
}

// The `index`th sample of a row at `depth` bits, scaled to 8 bits when narrower.
fn sample(row: []const u8, index: usize, depth: usize) -> u32 {
    if depth == 8usize { ret u32(row[index]) }
    if depth == 16usize { ret u32(row[index * 2usize]) }
    let bit = index * depth
    let byte = u32(row[bit / 8usize])
    let shift = u32(8usize - depth - (bit % 8usize))
    let raw = (byte >> shift) & ((1u32 << u32(depth)) - 1u32)
    if depth == 1usize { ret raw * 255u32 }
    if depth == 2usize { ret raw * 85u32 }
    ret raw * 17u32
}

// The raw (unscaled) sample, for palette indices and tRNS comparisons.
fn raw_sample(row: []const u8, index: usize, depth: usize) -> u32 {
    if depth == 8usize { ret u32(row[index]) }
    if depth == 16usize { ret (u32(row[index * 2usize]) << 8u32) | u32(row[index * 2usize + 1usize]) }
    let bit = index * depth
    let shift = u32(8usize - depth - (bit % 8usize))
    ret (u32(row[bit / 8usize]) >> shift) & ((1u32 << u32(depth)) - 1u32)
}

type Palette = struct { plte: []const u8, trns: []const u8, has_trns: bool }

// Writes pixel `x` of an unfiltered row into the output image at (`dx`, `dy`).
fn store_pixel(out: image.Image, dx: usize, dy: usize, row: []const u8, x: usize, h: Header, pal: Palette) {
    let depth = usize(h.depth)
    let channels = channels_of(h.color)
    let at = dy * out.stride + dx * image.bytes_per_pixel(out.format)
    if out.format == .R8 {
        out.pixels[at] = u8(sample(row, x, depth))
        ret
    }
    var red = 0u32
    var green = 0u32
    var blue = 0u32
    var alpha = 255u32
    if h.color == 0u32 {
        red = sample(row, x, depth)
        green = red
        blue = red
        if pal.has_trns && pal.trns.len >= 2usize && raw_sample(row, x, depth) == ((u32(pal.trns[0]) << 8u32) | u32(pal.trns[1])) { alpha = 0u32 }
    } else if h.color == 2u32 {
        red = sample(row, x * 3usize, depth)
        green = sample(row, x * 3usize + 1usize, depth)
        blue = sample(row, x * 3usize + 2usize, depth)
        if pal.has_trns && pal.trns.len >= 6usize {
            let r = raw_sample(row, x * 3usize, depth)
            let g = raw_sample(row, x * 3usize + 1usize, depth)
            let b = raw_sample(row, x * 3usize + 2usize, depth)
            if r == ((u32(pal.trns[0]) << 8u32) | u32(pal.trns[1])) && g == ((u32(pal.trns[2]) << 8u32) | u32(pal.trns[3])) && b == ((u32(pal.trns[4]) << 8u32) | u32(pal.trns[5])) { alpha = 0u32 }
        }
    } else if h.color == 3u32 {
        let index = usize(raw_sample(row, x, depth))
        if index * 3usize + 2usize < pal.plte.len {
            red = u32(pal.plte[index * 3usize])
            green = u32(pal.plte[index * 3usize + 1usize])
            blue = u32(pal.plte[index * 3usize + 2usize])
        }
        if pal.has_trns && index < pal.trns.len { alpha = u32(pal.trns[index]) }
    } else if h.color == 4u32 {
        red = sample(row, x * 2usize, depth)
        green = red
        blue = red
        alpha = sample(row, x * 2usize + 1usize, depth)
    } else {
        red = sample(row, x * channels, depth)
        green = sample(row, x * channels + 1usize, depth)
        blue = sample(row, x * channels + 2usize, depth)
        alpha = sample(row, x * channels + 3usize, depth)
    }
    out.pixels[at] = u8(red)
    out.pixels[at + 1usize] = u8(green)
    out.pixels[at + 2usize] = u8(blue)
    out.pixels[at + 3usize] = u8(alpha)
}

// Unfilters the rows of one pass from `raw` and scatters them into `out`.
fn unpack_pass(out: image.Image, raw: []u8, from: usize, p: Pass, h: Header, pal: Palette) -> (usize, err) {
    let (pw, ph) = pass_size(p, usize(h.width), usize(h.height))
    if pw == 0usize || ph == 0usize { ret (from, ok) }
    let depth = usize(h.depth)
    let channels = channels_of(h.color)
    let stride = row_bytes(pw, channels, depth)
    var bpp = channels * depth / 8usize
    if bpp == 0usize { bpp = 1usize }
    var at = from
    var previous = raw[0..0usize]
    var y = 0usize
    while y < ph {
        if at + 1usize + stride > raw.len { ret (at, Invalid) }
        let kind = raw[at]
        let row = raw[at + 1usize..at + 1usize + stride]
        let unfilter_error = unfilter(kind, row, previous, bpp)
        if unfilter_error != ok { ret (at, unfilter_error) }
        var x = 0usize
        while x < pw {
            store_pixel(out, p.x0 + x * p.dx, p.y0 + y * p.dy, row, x, h, pal)
            x += 1usize
        }
        previous = row
        at += 1usize + stride
        y += 1usize
    }
    ret (at, ok)
}

// The unfiltered stream's size: one filter byte and one row per scanline, per pass.
fn raw_size(h: Header) -> usize {
    let depth = usize(h.depth)
    let channels = channels_of(h.color)
    if !h.interlace { ret usize(h.height) * (1usize + row_bytes(usize(h.width), channels, depth)) }
    var total = 0usize
    var i = 0usize
    while i < 7usize {
        let (pw, ph) = pass_size(pass_of(i), usize(h.width), usize(h.height))
        if pw > 0usize && ph > 0usize { total += ph * (1usize + row_bytes(pw, channels, depth)) }
        i += 1usize
    }
    ret total
}

fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var r = source
    let (data, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (zero, read_error) }
    if !signature_ok(data) { ret (zero, Invalid) }
    var header: Header = zero
    var seen_header = false
    var pal: Palette = zero
    var idat_total = 0usize
    var at = 8usize
    // First walk: header, palette, transparency, the compressed size.
    while at + 12usize <= data.len {
        let length = usize(be32(data, at))
        let kind = be32(data, at + 4usize)
        if length > 2147483647usize || at + 12usize + length > data.len { ret (zero, Invalid) }
        let body = data[at + 8usize..at + 8usize + length]
        if options.verify_crc && crc32(data[at + 4usize..at + 8usize + length]) != be32(data, at + 8usize + length) { ret (zero, Checksum) }
        if kind == 1229472850u32 {
            if seen_header { ret (zero, Invalid) }
            let (parsed, parse_error) = parse_header(body)
            if parse_error != ok { ret (zero, parse_error) }
            header = parsed
            seen_header = true
            let within_error = within(header, options)
            if within_error != ok { ret (zero, within_error) }
        } else {
            if !seen_header { ret (zero, Invalid) }
            if kind == 1347179589u32 {
                if length % 3usize != 0usize || length == 0usize || length > 768usize { ret (zero, Invalid) }
                pal.plte = body
            }
            if kind == 1951551059u32 {
                pal.trns = body
                pal.has_trns = true
            }
            if kind == 1633899596u32 && length >= 4usize {
                header.frames = be32(body, 0usize)
                if header.frames == 0u32 { header.frames = 1u32 }
            }
            if kind == 1229209940u32 { idat_total += length }
            if kind == 1229278788u32 { break }
        }
        at += 12usize + length
    }
    if !seen_header || idat_total < 6usize { ret (zero, Invalid) }
    if header.color == 3u32 && pal.plte.len == 0usize { ret (zero, Invalid) }
    // Second walk: the zlib stream, IDAT chunks laid end to end.
    let (zlib, zlib_error) = mem.alloc[u8](a, idat_total)
    if zlib_error != ok { ret (zero, zlib_error) }
    var filled = 0usize
    at = 8usize
    while at + 12usize <= data.len {
        let length = usize(be32(data, at))
        let kind = be32(data, at + 4usize)
        if kind == 1229209940u32 {
            mem.copy[u8](zlib[filled..filled + length], data[at + 8usize..at + 8usize + length])
            filled += length
        }
        if kind == 1229278788u32 { break }
        at += 12usize + length
    }
    if (u32(zlib[0]) & 15u32) != 8u32 || ((u32(zlib[0]) << 8u32) | u32(zlib[1])) % 31u32 != 0u32 { ret (zero, Invalid) }
    if (u32(zlib[1]) & 32u32) != 0u32 { ret (zero, Unsupported) }
    let expected = raw_size(header)
    let (raw, raw_error) = mem.alloc[u8](a, expected)
    if raw_error != ok { ret (zero, raw_error) }
    let (storage_size, storage_size_error) = deflate.decoder_storage(WINDOW)
    if storage_size_error != ok { ret (zero, storage_size_error) }
    let (words, words_error) = mem.alloc[u64](a, storage_size / 8usize + 1usize)
    if words_error != ok { ret (zero, words_error) }
    let storage = mem.view(a, a.off - words.len * 8usize, words.len * 8usize)
    let (made, decoder_error) = deflate.decoder(storage, WINDOW)
    if decoder_error != ok { ret (zero, decoder_error) }
    var d = made
    let (consumed, written, status, decode_error) = deflate.decode(&d, zlib[2usize..zlib.len - 4usize], raw, true)
    if decode_error != ok { ret (zero, Invalid) }
    if status != .Finished || written != expected { ret (zero, Invalid) }
    if options.verify_crc && adler32_update(1u32, raw) != be32(zlib, zlib.len - 4usize) { ret (zero, Checksum) }
    let info = info_of(header, pal.has_trns)
    let (out, out_error) = image.allocate(a, header.width, header.height, info.format, info.alpha)
    if out_error != ok { ret (zero, out_error) }
    var from = 0usize
    if header.interlace {
        var i = 0usize
        while i < 7usize {
            let (next, pass_error) = unpack_pass(out, raw, from, pass_of(i), header, pal)
            if pass_error != ok { ret (zero, pass_error) }
            from = next
            i += 1usize
        }
    } else {
        let (_, pass_error) = unpack_pass(out, raw, 0usize, Pass { x0: 0usize, y0: 0usize, dx: 1usize, dy: 1usize }, header, pal)
        if pass_error != ok { ret (zero, pass_error) }
    }
    ret (out, ok)
}

// ------------------------------------------------------------------ encoding

type Sink = struct { writer: *io.Writer, chunk: [32768]u8, filled: usize, adler: u32, zlib_header_written: bool }

fn put32(d: []u8, at: usize, v: u32) {
    d[at] = u8(v >> 24u32)
    d[at + 1usize] = u8((v >> 16u32) & 255u32)
    d[at + 2usize] = u8((v >> 8u32) & 255u32)
    d[at + 3usize] = u8(v & 255u32)
}

fn write_chunk(w: *io.Writer, kind: str, body: []const u8) -> err {
    var head: [8]u8 = zero
    put32(head[0..], 0usize, u32(body.len))
    mem.copy[u8](head[4usize..8usize], kind)
    try io.write_all(w, head[0..])
    if body.len > 0usize { try io.write_all(w, body) }
    var crc: [4]u8 = zero
    put32(crc[0..], 0usize, crc32_update(crc32_update(4294967295u32, kind), body) ^ 4294967295u32)
    ret io.write_all(w, crc[0..])
}

fn flush_idat(s: *Sink) -> err {
    if s.filled == 0usize { ret ok }
    let write_error = write_chunk(s.writer, "IDAT", s.chunk[..s.filled])
    s.filled = 0usize
    ret write_error
}

// Feeds `input` through the deflate encoder, emitting IDAT chunks as they fill.
fn deflate_into(s: *Sink, e: *deflate.Encoder, input: []const u8, finish: bool) -> err {
    s.adler = adler32_update(s.adler, input)
    var consumed_total = 0usize
    while true {
        let (consumed, written, status, encode_error) = deflate.encode(e, input[consumed_total..], s.chunk[s.filled..], finish)
        if encode_error != ok { ret encode_error }
        consumed_total += consumed
        s.filled += written
        if status == .Finished { ret ok }
        if status == .NeedOutput || s.filled == s.chunk.len {
            try flush_idat(s)
            continue
        }
        if consumed_total >= input.len { ret ok }
    }
    ret ok
}

fn source_channels(value: image.ConstImage) -> (usize, u8, err) {
    if value.format == .R8 { ret (1usize, 0u8, ok) }
    if value.format == .Rgba16Float { ret (0usize, 0u8, Unsupported) }
    if value.alpha == .Opaque { ret (3usize, 2u8, ok) }
    ret (4usize, 6u8, ok)
}

// Gathers the pixels of one pass row into `line` as PNG bytes and deflates them,
// the filter byte first.
fn encode_row(s: *Sink, e: *deflate.Encoder, value: image.ConstImage, p: Pass, y: usize, pw: usize, channels: usize, line: []u8) -> err {
    var filter: [1]u8 = zero
    try deflate_into(s, e, filter[0..], false)
    let bpp = image.bytes_per_pixel(value.format)
    let row = (p.y0 + y * p.dy) * value.stride
    var x = 0usize
    while x < pw {
        var take = pw - x
        if take * channels > line.len { take = line.len / channels }
        var i = 0usize
        while i < take {
            let at = row + (p.x0 + (x + i) * p.dx) * bpp
            let to = i * channels
            if channels == 1usize {
                line[to] = value.pixels[at]
            } else if value.format == .Bgra8 {
                line[to] = value.pixels[at + 2usize]
                line[to + 1usize] = value.pixels[at + 1usize]
                line[to + 2usize] = value.pixels[at]
                if channels == 4usize { line[to + 3usize] = value.pixels[at + 3usize] }
            } else {
                line[to] = value.pixels[at]
                line[to + 1usize] = value.pixels[at + 1usize]
                line[to + 2usize] = value.pixels[at + 2usize]
                if channels == 4usize { line[to + 3usize] = value.pixels[at + 3usize] }
            }
            i += 1usize
        }
        try deflate_into(s, e, line[..take * channels], false)
        x += take
    }
    ret ok
}

fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err {
    let (channels, color, channels_error) = source_channels(value)
    if channels_error != ok { ret channels_error }
    let (_, size_error) = image.required_bytes(value.width, value.height, value.format, value.stride)
    if size_error != ok { ret Invalid }
    if value.pixels.len < value.stride * usize(value.height) - value.stride + usize(value.width) * image.bytes_per_pixel(value.format) { ret Invalid }
    var signature: [8]u8 = [8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 }
    try io.write_all(writer, signature[0..])
    var ihdr: [13]u8 = zero
    put32(ihdr[0..], 0usize, value.width)
    put32(ihdr[0..], 4usize, value.height)
    ihdr[8] = 8u8
    ihdr[9] = color
    if options.interlace { ihdr[12] = 1u8 }
    try write_chunk(writer, "IHDR", ihdr[0..])
    var arena_bytes: [163840]u8 = zero
    var arena = mem.arena_from(arena_bytes[0..])
    let storage_size = deflate.encoder_storage(options.compression)
    let (words, words_error) = mem.alloc[u64](&arena, storage_size / 8usize + 1usize)
    if words_error != ok { ret words_error }
    let storage = mem.view(&arena, arena.off - words.len * 8usize, words.len * 8usize)
    let (made, encoder_error) = deflate.encoder(storage, options.compression)
    if encoder_error != ok { ret encoder_error }
    var e = made
    var sink: Sink = zero
    sink.writer = writer
    sink.adler = 1u32
    var zlib_head: [2]u8 = [2]u8{ 120, 156 }
    if options.compression == .Fast { zlib_head[1] = 1u8 }
    sink.chunk[0] = zlib_head[0]
    sink.chunk[1] = zlib_head[1]
    sink.filled = 2usize
    var line: [16384]u8 = zero
    var passes = 1usize
    if options.interlace { passes = 7usize }
    var i = 0usize
    while i < passes {
        var p = Pass { x0: 0usize, y0: 0usize, dx: 1usize, dy: 1usize }
        if options.interlace { p = pass_of(i) }
        let (pw, ph) = pass_size(p, usize(value.width), usize(value.height))
        var y = 0usize
        while pw > 0usize && y < ph {
            try encode_row(&sink, &e, value, p, y, pw, channels, line[0..])
            y += 1usize
        }
        i += 1usize
    }
    try deflate_into(&sink, &e, line[0..0usize], true)
    if sink.filled + 4usize > sink.chunk.len { try flush_idat(&sink) }
    put32(sink.chunk[0..], sink.filled, sink.adler)
    sink.filled += 4usize
    try flush_idat(&sink)
    try write_chunk(writer, "IEND", line[0..0usize])
    ret ok
}
