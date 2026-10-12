// `e.fmt.png` encode_adaptive (L163): twelve generated images (reference.py beside this
// fixture builds the same ones) encoded with the per-row filter heuristic and the palette
// choice, then the IHDR colour type and depth, the PLTE and tRNS lengths, the length and
// Adler-32 of the inflated filtered stream and the zlib size are checked against a Python
// model of libpng's heuristic, which reference.py also checks against Pillow byte for
// byte on the non-interlaced cases; every file decodes back to its source pixels, a BGRA
// source gives the same stream as RGBA, and adaptive output is smaller than plain filter
// None on the smooth images. Every check has its own exit code.

use e.algo.deflate
use e.fmt.png
use e.gfx.image
use e.io
use e.mem
use e.os

type Rng = struct { s: u64 }

fn next(r: *Rng) -> u32 {
    r.s = (r.s * 1103515245u64 + 12345u64) & 2147483647u64
    ret u32(r.s >> 16u64)
}

fn put(px: []u8, at: usize, r: u32, g: u32, b: u32, a: u32) {
    px[at] = u8(r & 255u32)
    px[at + 1usize] = u8(g & 255u32)
    px[at + 2usize] = u8(b & 255u32)
    px[at + 3usize] = u8(a & 255u32)
}

// Fills `px` (Rgba8, or R8 for kind 6) with generated image `kind` of width w and height h.
fn generate(kind: usize, w: usize, h: usize, px: []u8) {
    var rng = Rng { s: 12345u64 }
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let at = (y * w + x) * 4usize
            let xx = u32(x)
            let yy = u32(y)
            if kind == 0usize {
                if ((x / 5usize) + (y / 3usize)) % 2usize == 1usize { put(px, at, 10u32, 40u32, 200u32, 255u32) } else { put(px, at, 250u32, 250u32, 250u32, 255u32) }
            } else if kind == 1usize {
                let k = (x / 4usize + y / 5usize) % 4usize
                if k == 0usize { put(px, at, 0u32, 0u32, 0u32, 0u32) }
                if k == 1usize { put(px, at, 255u32, 0u32, 0u32, 128u32) }
                if k == 2usize { put(px, at, 0u32, 255u32, 0u32, 255u32) }
                if k == 3usize { put(px, at, 0u32, 0u32, 255u32, 255u32) }
            } else if kind == 2usize {
                let k = u32((x / 3usize + y) % 11usize)
                put(px, at, k * 23u32, 255u32 - k * 20u32, (k * k * 3u32) % 256u32, 255u32)
            } else if kind == 3usize {
                let k = u32((x * 5usize + y * 7usize) % 200usize)
                put(px, at, k, k * 3u32 % 256u32, 255u32 - k, 255u32)
            } else if kind == 4usize {
                let n = next(&rng) & 7u32
                put(px, at, 2u32 * xx + yy + n, xx + 3u32 * yy, (xx * yy) >> 3u32, 255u32)
            } else if kind == 5usize {
                let n = next(&rng) & 7u32
                put(px, at, 2u32 * xx + yy + n, xx + 3u32 * yy, (xx * yy) >> 3u32, 255u32 - ((xx + yy) % 5u32) * 10u32)
            } else if kind == 6usize {
                let n = next(&rng) & 7u32
                px[y * w + x] = u8((xx * 6u32 + yy * 2u32 + n) & 255u32)
            } else {
                let n1 = next(&rng) & 15u32
                let n2 = next(&rng) & 3u32
                put(px, at, xx * 3u32 + yy * 17u32 + n1, xx / 2u32 + n2, 255u32 - xx % 256u32, 255u32)
            }
            x += 1usize
        }
        y += 1usize
    }
}

type Case = struct { kind: usize, w: usize, h: usize, interlace: bool, alpha_used: bool, color: u32, depth: u32, colors: usize, trns: usize, raw_len: usize, adler: u32, zlib6: usize }

fn case_of(i: usize) -> Case {
    if i == 0usize { ret Case { kind: 0usize, w: 61usize, h: 20usize, interlace: false, alpha_used: true, color: 3u32, depth: 1u32, colors: 2usize, trns: 0usize, raw_len: 180usize, adler: 4261367696u32, zlib6: 31usize } }
    if i == 1usize { ret Case { kind: 1usize, w: 33usize, h: 20usize, interlace: false, alpha_used: true, color: 3u32, depth: 2u32, colors: 4usize, trns: 2usize, raw_len: 200usize, adler: 3804256049u32, zlib6: 34usize } }
    if i == 2usize { ret Case { kind: 2usize, w: 100usize, h: 30usize, interlace: false, alpha_used: true, color: 3u32, depth: 4u32, colors: 11usize, trns: 0usize, raw_len: 1530usize, adler: 3136352664u32, zlib6: 90usize } }
    if i == 3usize { ret Case { kind: 3usize, w: 50usize, h: 40usize, interlace: false, alpha_used: true, color: 3u32, depth: 8u32, colors: 200usize, trns: 0usize, raw_len: 2040usize, adler: 71435478u32, zlib6: 407usize } }
    if i == 4usize { ret Case { kind: 4usize, w: 97usize, h: 61usize, interlace: false, alpha_used: false, color: 2u32, depth: 8u32, colors: 0usize, trns: 0usize, raw_len: 17812usize, adler: 4279594192u32, zlib6: 5820usize } }
    if i == 5usize { ret Case { kind: 5usize, w: 97usize, h: 61usize, interlace: false, alpha_used: true, color: 6u32, depth: 8u32, colors: 0usize, trns: 0usize, raw_len: 23729usize, adler: 893183262u32, zlib6: 7023usize } }
    if i == 6usize { ret Case { kind: 6usize, w: 40usize, h: 30usize, interlace: false, alpha_used: false, color: 0u32, depth: 8u32, colors: 0usize, trns: 0usize, raw_len: 1230usize, adler: 579282745u32, zlib6: 674usize } }
    if i == 7usize { ret Case { kind: 7usize, w: 1500usize, h: 6usize, interlace: false, alpha_used: false, color: 2u32, depth: 8u32, colors: 0usize, trns: 0usize, raw_len: 27006usize, adler: 3020240968u32, zlib6: 12259usize } }
    if i == 8usize { ret Case { kind: 0usize, w: 61usize, h: 20usize, interlace: true, alpha_used: true, color: 3u32, depth: 1u32, colors: 2usize, trns: 0usize, raw_len: 198usize, adler: 2910014893u32, zlib6: 77usize } }
    if i == 9usize { ret Case { kind: 2usize, w: 100usize, h: 30usize, interlace: true, alpha_used: true, color: 3u32, depth: 4u32, colors: 11usize, trns: 0usize, raw_len: 1565usize, adler: 911667413u32, zlib6: 308usize } }
    if i == 10usize { ret Case { kind: 4usize, w: 97usize, h: 61usize, interlace: true, alpha_used: false, color: 2u32, depth: 8u32, colors: 0usize, trns: 0usize, raw_len: 17867usize, adler: 984585582u32, zlib6: 6860usize } }
    ret Case { kind: 6usize, w: 40usize, h: 30usize, interlace: true, alpha_used: false, color: 0u32, depth: 8u32, colors: 0usize, trns: 0usize, raw_len: 1257usize, adler: 1459645306u32, zlib6: 752usize }
}

fn be32(d: []const u8, at: usize) -> u32 {
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

fn options() -> png.DecodeOptions {
    ret png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: true }
}

// Encodes `source` adaptively (or plain when `plain`) into a fresh buffer; the file bytes.
fn encode_file(a: *mem.Arena, source: image.ConstImage, level: deflate.Level, interlace: bool, plain: bool) -> ([]u8, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 65536usize)
    if buffer_error != ok { ret (buffer, buffer_error) }
    var sink = io.SliceWriter { data: buffer, off: 0usize }
    var w = io.slice_writer(&sink)
    let opts = png.EncodeOptions { compression: level, interlace: interlace }
    var failure = ok
    if plain { failure = png.encode(&w, source, opts) } else { failure = png.encode_adaptive(&w, source, opts) }
    ret (buffer[..sink.off], failure)
}

type Parsed = struct { color: u32, depth: u32, plte: usize, trns: usize, zlib: []u8, idat_size: usize }

// Walks the chunks of `file`, concatenating IDAT bodies into `zlib` (a scratch buffer).
fn parse(file: []const u8, zlib: []u8) -> (Parsed, bool) {
    var p: Parsed = zero
    if file.len < 33usize { ret (p, false) }
    p.depth = u32(file[24])
    p.color = u32(file[25])
    var at = 8usize
    var filled = 0usize
    while at + 12usize <= file.len {
        let n = usize(be32(file, at))
        let kind = file[at + 4usize..at + 8usize]
        if at + 12usize + n > file.len { ret (p, false) }
        if mem.eq[u8](kind, "PLTE") { p.plte = n / 3usize }
        if mem.eq[u8](kind, "tRNS") { p.trns = n }
        if mem.eq[u8](kind, "IDAT") {
            mem.copy[u8](zlib[filled..filled + n], file[at + 8usize..at + 8usize + n])
            filled += n
        }
        at += 12usize + n
    }
    p.zlib = zlib[..filled]
    p.idat_size = filled
    ret (p, at == file.len)
}

// The Adler-32 and length of the inflated zlib stream in `zlib`; 0 length on refusal.
fn raw_of(a: *mem.Arena, zlib: []const u8, out: []u8) -> usize {
    let (need, need_error) = deflate.decoder_storage(32768usize)
    if need_error != ok { ret 0usize }
    let (storage, storage_error) = mem.alloc[u8](a, need)
    if storage_error != ok { ret 0usize }
    let (d0, d_error) = deflate.decoder(storage, 32768usize)
    if d_error != ok { ret 0usize }
    var d = d0
    if zlib.len < 6usize { ret 0usize }
    let (consumed, written, status, decode_error) = deflate.decode(&d, zlib[2usize..zlib.len - 4usize], out, true)
    if decode_error != ok || status != .Finished { ret 0usize }
    // The trailer is the stream's own Adler-32; the caller compares it with the model's and with a recomputation.
    ret written
}

fn main(a: *mem.Arena, args: []str) -> err {
    var smooth_adler = 0u32
    var smooth_adaptive = 0usize
    var smooth_plain = 0usize
    let case_mark = a.off
    var i = 0usize
    while i < 12usize {
        // The arena is small: each case returns what it took.
        a.off = case_mark
        let c = case_of(i)
        let base = i32(100usize + i * 10usize)
        var format = image.Format.Rgba8
        var bpp = 4usize
        if c.kind == 6usize {
            format = .R8
            bpp = 1usize
        }
        let (pixels, pixel_error) = mem.alloc[u8](a, c.w * c.h * 4usize)
        if pixel_error != ok { os.exit(base + 1i32) }
        generate(c.kind, c.w, c.h, pixels)
        var alpha = image.Alpha.Straight
        if !c.alpha_used { alpha = .Opaque }
        let (source, source_error) = image.make_const(pixels[..c.w * c.h * bpp], u32(c.w), u32(c.h), c.w * bpp, format, alpha)
        if source_error != ok { os.exit(base + 2i32) }
        let (file, encode_error) = encode_file(a, source, .Balanced, c.interlace, false)
        if encode_error != ok { os.exit(base + 3i32) }
        let (zbuf, zbuf_error) = mem.alloc[u8](a, file.len)
        if zbuf_error != ok { os.exit(base + 4i32) }
        let (parsed, parsed_ok) = parse(file, zbuf)
        if !parsed_ok { os.exit(base + 5i32) }
        if parsed.color != c.color || parsed.depth != c.depth { os.exit(base + 6i32) }
        if parsed.plte != c.colors || parsed.trns != c.trns { os.exit(base + 7i32) }
        let (raw, raw_error) = mem.alloc[u8](a, c.raw_len + 64usize)
        if raw_error != ok { os.exit(base + 8i32) }
        let raw_len = raw_of(a, parsed.zlib, raw)
        if raw_len != c.raw_len { os.exit(base + 9i32) }
        let adler = png.adler32_update(1u32, raw[..raw_len])
        if adler != c.adler || adler != be32(parsed.zlib, parsed.zlib.len - 4usize) { os.exit(base + 10i32) }
        // Against zlib level 6 on the same filtered rows (reference.py): no more than 1% and 8 bytes larger.
        if c.zlib6 > 0usize && parsed.idat_size > c.zlib6 + c.zlib6 / 100usize + 8usize { os.exit(base + 11i32) }
        // The pixels read back.
        var state: io.SliceReader = zero
        state.data = file
        state.off = 0usize
        let (decoded, decode_error) = png.decode(a, io.slice_reader(&state), options())
        if decode_error != ok { os.exit(base + 12i32) }
        if decoded.format != format || decoded.width != u32(c.w) || decoded.height != u32(c.h) { os.exit(base + 13i32) }
        var y = 0usize
        while y < c.h {
            let row = decoded.pixels[y * decoded.stride..y * decoded.stride + c.w * bpp]
            if !mem.eq[u8](row, pixels[y * c.w * bpp..(y + 1usize) * c.w * bpp]) { os.exit(base + 14i32) }
            y += 1usize
        }
        if i == 4usize {
            smooth_adler = adler
            smooth_adaptive = parsed.idat_size
            let (plain_file, plain_error) = encode_file(a, source, .Balanced, false, true)
            if plain_error != ok { os.exit(base + 15i32) }
            smooth_plain = plain_file.len
        }
        i += 1usize
    }
    // Adaptive filters beat filter None on the smooth image.
    if smooth_adaptive == 0usize || smooth_adaptive + 400usize > smooth_plain { os.exit(300i32) }

    // BGRA gives the same filtered stream as RGBA; Fast and Best levels decode back.
    a.off = case_mark
    let c = case_of(4usize)
    let (rgba, rgba_error) = mem.alloc[u8](a, c.w * c.h * 4usize)
    let (bgra, bgra_error) = mem.alloc[u8](a, c.w * c.h * 4usize)
    if rgba_error != ok || bgra_error != ok { os.exit(310i32) }
    generate(4usize, c.w, c.h, rgba)
    var j = 0usize
    while j < rgba.len {
        bgra[j] = rgba[j + 2usize]
        bgra[j + 1usize] = rgba[j + 1usize]
        bgra[j + 2usize] = rgba[j]
        bgra[j + 3usize] = rgba[j + 3usize]
        j += 4usize
    }
    let (view, view_error) = image.make_const(bgra, u32(c.w), u32(c.h), c.w * 4usize, .Bgra8, .Opaque)
    if view_error != ok { os.exit(311i32) }
    let level_mark = a.off
    var level = 0usize
    while level < 3usize {
        a.off = level_mark
        var lv = deflate.Level.Fast
        if level == 1usize { lv = .Balanced }
        if level == 2usize { lv = .Best }
        let (file, encode_error) = encode_file(a, view, lv, false, false)
        if encode_error != ok { os.exit(312i32) }
        let (zbuf, zbuf_error) = mem.alloc[u8](a, file.len)
        if zbuf_error != ok { os.exit(313i32) }
        let (parsed, parsed_ok) = parse(file, zbuf)
        if !parsed_ok || parsed.color != 2u32 { os.exit(314i32) }
        let (raw, raw_error) = mem.alloc[u8](a, c.raw_len + 64usize)
        if raw_error != ok { os.exit(315i32) }
        let raw_len = raw_of(a, parsed.zlib, raw)
        if raw_len != c.raw_len || png.adler32_update(1u32, raw[..raw_len]) != smooth_adler { os.exit(316i32) }
        level += 1usize
    }

    // A source that cannot be written is refused, as for encode.
    let (halves, halves_error) = image.allocate(a, 2u32, 2u32, .Rgba16Float, .Straight)
    if halves_error != ok { os.exit(320i32) }
    let (half_view, half_view_error) = image.make_const(halves.pixels, 2u32, 2u32, 16usize, .Rgba16Float, .Straight)
    if half_view_error != ok { os.exit(321i32) }
    let (_, half_error) = encode_file(a, half_view, .Fast, false, false)
    if half_error != png.Unsupported { os.exit(322i32) }

    try io.print("fmt png adaptive ok\n")
    ret ok
}
