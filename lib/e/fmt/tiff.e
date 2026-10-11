// TIFF decoder (L124): the first image of a baseline or extended-baseline file, either byte
// order. Strips only (tiles are `Unsupported`), chunky samples (planar configuration 1);
// compression none, LZW (the MSB-first "early change" variant of the TIFF 6.0 appendix),
// PackBits and Deflate (zlib framing, compression 8 and 32946), with the horizontal
// predictor (2) for 8-bit data; photometric WhiteIsZero, BlackIsZero, RGB and palette;
// 1, 2, 4, 8 and 16 bits per sample (16 keeps the high byte); one to four samples, the
// fourth of an RGB image and the second of a grey one taken as alpha when ExtraSamples
// says so. The result is Rgba8; `Premultiplied` for associated alpha, `Straight` for
// unassociated, `Opaque` otherwise. Dimensions and the strip table are checked against
// the options (zero selects 16,384 per side and 16,777,216 pixels) and the data before any
// pixel is taken. Decode only; BigTIFF, CMYK, YCbCr, planar files, floating point
// samples and JPEG compression are `Unsupported`.

use e.algo.deflate as deflate
use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64 }
type Ifd = struct { width: u32, height: u32, bits: u32, compression: u32, photometric: u32, samples: u32, rows_per_strip: u32, planar: u32, predictor: u32, extra: u32, strips: usize, offsets_at: usize, offsets_type: u32, counts_at: usize, counts_type: u32, color_map_at: usize, color_map_len: usize, big: bool }
error Invalid
error Unsupported
error TooLarge

const READ_LIMIT: usize = 1073741824usize

type Rd = struct { d: []const u8, big: bool }

fn u16_at(r: *Rd, at: usize) -> u32 {
    if r.big { ret (u32(r.d[at]) << 8u32) | u32(r.d[at + 1usize]) }
    ret u32(r.d[at]) | (u32(r.d[at + 1usize]) << 8u32)
}

fn u32_at(r: *Rd, at: usize) -> u32 {
    if r.big {
        ret (u32(r.d[at]) << 24u32) | (u32(r.d[at + 1usize]) << 16u32) | (u32(r.d[at + 2usize]) << 8u32) | u32(r.d[at + 3usize])
    }
    ret u32(r.d[at]) | (u32(r.d[at + 1usize]) << 8u32) | (u32(r.d[at + 2usize]) << 16u32) | (u32(r.d[at + 3usize]) << 24u32)
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

fn type_size(t: u32) -> usize {
    if t == 1u32 || t == 2u32 || t == 6u32 || t == 7u32 { ret 1usize }
    if t == 3u32 || t == 8u32 { ret 2usize }
    if t == 4u32 || t == 9u32 || t == 11u32 { ret 4usize }
    if t == 5u32 || t == 10u32 || t == 12u32 { ret 8usize }
    ret 0usize
}

// The offset of an entry's values: inline in the entry or at the offset it holds.
fn values_at(r: *Rd, entry: usize, t: u32, count: u32) -> (usize, err) {
    let size = type_size(t)
    if size == 0usize { ret (0usize, Invalid) }
    let total = u64(size) * u64(count)
    if total <= 4u64 { ret (entry + 8usize, ok) }
    let at = u64(u32_at(r, entry + 8usize))
    if at > u64(r.d.len) || total > u64(r.d.len) - at { ret (0usize, Invalid) }
    ret (usize(at), ok)
}

// One SHORT or LONG value of an entry's list.
fn nth(r: *Rd, at: usize, t: u32, i: usize) -> u32 {
    if t == 3u32 { ret u16_at(r, at + i * 2usize) }
    ret u32_at(r, at + i * 4usize)
}

fn parse(r: *Rd) -> (Ifd, err) {
    var h: Ifd = zero
    let d = r.d
    if d.len < 8usize { ret (h, Invalid) }
    if d[0] == 73u8 && d[1] == 73u8 {
        r.big = false
    } else if d[0] == 77u8 && d[1] == 77u8 {
        r.big = true
    } else {
        ret (h, Invalid)
    }
    let magic = u16_at(r, 2usize)
    if magic == 43u32 { ret (h, Unsupported) }
    if magic != 42u32 { ret (h, Invalid) }
    let ifd = usize(u32_at(r, 4usize))
    if ifd + 2usize > d.len { ret (h, Invalid) }
    let n = usize(u16_at(r, ifd))
    if ifd + 2usize + n * 12usize + 4usize > d.len { ret (h, Invalid) }
    h.bits = 1u32
    h.compression = 1u32
    h.samples = 1u32
    h.planar = 1u32
    h.predictor = 1u32
    h.rows_per_strip = 4294967295u32
    var bits_at = 0usize
    var bits_type = 0u32
    var bits_count = 0u32
    var strips = 0u32
    var extra_at = 0usize
    var extra_count = 0u32
    var tiled = false
    var k = 0usize
    while k < n {
        let e = ifd + 2usize + k * 12usize
        let tag = u16_at(r, e)
        let t = u16_at(r, e + 2usize)
        let count = u32_at(r, e + 4usize)
        if tag == 256u32 || tag == 257u32 || tag == 259u32 || tag == 262u32 || tag == 277u32 || tag == 278u32 || tag == 284u32 || tag == 317u32 {
            if (t != 3u32 && t != 4u32) || count != 1u32 { ret (h, Invalid) }
            var v = 0u32
            if t == 3u32 { v = u16_at(r, e + 8usize) } else { v = u32_at(r, e + 8usize) }
            if tag == 256u32 { h.width = v }
            if tag == 257u32 { h.height = v }
            if tag == 259u32 { h.compression = v }
            if tag == 262u32 { h.photometric = v }
            if tag == 277u32 { h.samples = v }
            if tag == 278u32 { h.rows_per_strip = v }
            if tag == 284u32 { h.planar = v }
            if tag == 317u32 { h.predictor = v }
        } else if tag == 258u32 {
            if t != 3u32 || count == 0u32 || count > 8u32 { ret (h, Invalid) }
            let (at, at_error) = values_at(r, e, t, count)
            if at_error != ok { ret (h, at_error) }
            bits_at = at
            bits_type = t
            bits_count = count
        } else if tag == 273u32 || tag == 279u32 {
            if (t != 3u32 && t != 4u32) || count == 0u32 { ret (h, Invalid) }
            let (at, at_error) = values_at(r, e, t, count)
            if at_error != ok { ret (h, at_error) }
            if tag == 273u32 {
                h.offsets_at = at
                h.offsets_type = t
                strips = count
            } else {
                h.counts_at = at
                h.counts_type = t
                if count != strips && strips != 0u32 { ret (h, Invalid) }
            }
        } else if tag == 320u32 {
            if t != 3u32 { ret (h, Invalid) }
            let (at, at_error) = values_at(r, e, t, count)
            if at_error != ok { ret (h, at_error) }
            h.color_map_at = at
            h.color_map_len = usize(count)
        } else if tag == 338u32 {
            if t != 3u32 || count == 0u32 { ret (h, Invalid) }
            let (at, at_error) = values_at(r, e, t, count)
            if at_error != ok { ret (h, at_error) }
            extra_at = at
            extra_count = count
        } else if tag == 339u32 {
            let (at, at_error) = values_at(r, e, t, count)
            if at_error != ok { ret (h, at_error) }
            if u16_at(r, at) != 1u32 { ret (h, Unsupported) }
        } else if tag == 322u32 || tag == 323u32 || tag == 324u32 || tag == 325u32 {
            tiled = true
        }
        k += 1usize
    }
    if tiled { ret (h, Unsupported) }
    if h.width == 0u32 || h.height == 0u32 { ret (h, Invalid) }
    if h.offsets_at == 0usize || h.counts_at == 0usize && h.compression != 1u32 { ret (h, Invalid) }
    if h.planar != 1u32 { ret (h, Unsupported) }
    if h.samples == 0u32 || h.samples > 4u32 { ret (h, Unsupported) }
    if bits_count != 0u32 {
        h.bits = nth(r, bits_at, bits_type, 0usize)
        var i = 1usize
        while i < usize(bits_count) {
            if nth(r, bits_at, bits_type, i) != h.bits { ret (h, Unsupported) }
            i += 1usize
        }
    }
    if h.bits != 1u32 && h.bits != 2u32 && h.bits != 4u32 && h.bits != 8u32 && h.bits != 16u32 { ret (h, Unsupported) }
    if h.photometric > 3u32 { ret (h, Unsupported) }
    if h.photometric == 2u32 && h.samples < 3u32 { ret (h, Invalid) }
    if h.photometric == 3u32 && (h.samples != 1u32 || h.bits > 8u32) { ret (h, Invalid) }
    if (h.photometric == 0u32 || h.photometric == 1u32) && h.samples > 2u32 { ret (h, Unsupported) }
    if h.compression != 1u32 && h.compression != 5u32 && h.compression != 8u32 && h.compression != 32946u32 && h.compression != 32773u32 { ret (h, Unsupported) }
    if h.predictor != 1u32 && (h.predictor != 2u32 || h.bits != 8u32) { ret (h, Unsupported) }
    if h.rows_per_strip == 0u32 { ret (h, Invalid) }
    if h.rows_per_strip > h.height { h.rows_per_strip = h.height }
    h.strips = usize((h.height + h.rows_per_strip - 1u32) / h.rows_per_strip)
    if strips != 0u32 && usize(strips) < h.strips { ret (h, Invalid) }
    h.extra = 0u32
    if extra_count > 0u32 { h.extra = u16_at(r, extra_at) }
    h.big = r.big
    ret (h, ok)
}

fn alpha_of(h: Ifd) -> image.Alpha {
    var color_samples = 1u32
    if h.photometric == 2u32 { color_samples = 3u32 }
    if h.samples > color_samples {
        if h.extra == 1u32 { ret .Premultiplied }
        if h.extra == 2u32 { ret .Straight }
    }
    ret .Opaque
}

fn inspect(a: *mem.Arena, source: io.Reader) -> (image.Info, err) {
    var r = source
    var info: image.Info = zero
    let (d, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (info, read_error) }
    var rd = Rd { d: d, big: false }
    let (h, failure) = parse(&rd)
    if failure != ok { ret (info, failure) }
    info.width = h.width
    info.height = h.height
    info.format = .Rgba8
    info.alpha = alpha_of(h)
    info.frames = 1u32
    ret (info, ok)
}

fn packbits(src: []const u8, out: []u8) -> (usize, err) {
    var i = 0usize
    var n = 0usize
    while i < src.len && n < out.len {
        let c = src[i]
        i += 1usize
        if c < 128u8 {
            let count = usize(c) + 1usize
            if i + count > src.len { ret (n, Invalid) }
            var k = 0usize
            while k < count && n < out.len {
                out[n] = src[i + k]
                n += 1usize
                k += 1usize
            }
            i += count
        } else if c > 128u8 {
            let count = 257usize - usize(c)
            if i >= src.len { ret (n, Invalid) }
            let v = src[i]
            i += 1usize
            var k = 0usize
            while k < count && n < out.len {
                out[n] = v
                n += 1usize
                k += 1usize
            }
        }
    }
    ret (n, ok)
}

// TIFF LZW: codes of 9 to 12 bits read most significant bit first, 256 clears, 257 ends,
// and the width grows one code early.
fn lzw(src: []const u8, out: []u8) -> (usize, err) {
    var prefix: [4096]u16 = zero
    var suffix: [4096]u8 = zero
    var stack: [4097]u8 = zero
    var next = 258u32
    var size = 9u32
    var acc = 0u32
    var nbits = 0u32
    var pos = 0usize
    var produced = 0usize
    var old = 4294967295u32
    var first = 0u32
    while true {
        while nbits < size {
            if pos >= src.len { ret (produced, ok) }
            acc = (acc << 8u32) | u32(src[pos])
            nbits += 8u32
            pos += 1usize
        }
        let code = (acc >> (nbits - size)) & ((1u32 << size) - 1u32)
        nbits -= size
        if code == 257u32 { break }
        if code == 256u32 {
            next = 258u32
            size = 9u32
            old = 4294967295u32
            continue
        }
        if old == 4294967295u32 {
            if code >= 256u32 { ret (produced, Invalid) }
            if produced >= out.len { break }
            out[produced] = u8(code)
            produced += 1usize
            old = code
            first = code
            continue
        }
        let incoming = code
        var c = code
        var sp = 0usize
        if c >= next {
            if c > next { ret (produced, Invalid) }
            stack[sp] = u8(first)
            sp += 1usize
            c = old
        }
        while c >= 258u32 {
            if sp >= 4096usize || c >= 4096u32 { ret (produced, Invalid) }
            stack[sp] = suffix[usize(c)]
            sp += 1usize
            c = u32(prefix[usize(c)])
        }
        first = c
        stack[sp] = u8(c)
        sp += 1usize
        while sp > 0usize {
            sp -= 1usize
            if produced >= out.len { ret (produced, ok) }
            out[produced] = stack[sp]
            produced += 1usize
        }
        if next < 4096u32 {
            prefix[usize(next)] = u16(old)
            suffix[usize(next)] = u8(first)
            next += 1u32
            if next == 511u32 { size = 10u32 }
            if next == 1023u32 { size = 11u32 }
            if next == 2047u32 { size = 12u32 }
        }
        old = incoming
    }
    ret (produced, ok)
}

fn inflate(a: *mem.Arena, src: []const u8, out: []u8) -> (usize, err) {
    if src.len < 2usize { ret (0usize, Invalid) }
    let (size, size_error) = deflate.decoder_storage(32768usize)
    if size_error != ok { ret (0usize, size_error) }
    let (storage, storage_error) = mem.alloc[u8](a, size)
    if storage_error != ok { ret (0usize, storage_error) }
    let (dec, dec_error) = deflate.decoder(storage, 32768usize)
    if dec_error != ok { ret (0usize, dec_error) }
    var decoder = dec
    let (_, written, status, failure) = deflate.decode(&decoder, src[2..], out, true)
    if failure != ok { ret (written, Invalid) }
    ret (written, ok)
}

fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var r = source
    let (d, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (zero, read_error) }
    var rd = Rd { d: d, big: false }
    let (h, header_error) = parse(&rd)
    if header_error != ok { ret (zero, header_error) }
    let within_error = within(h.width, h.height, options)
    if within_error != ok { ret (zero, within_error) }
    let w = usize(h.width)
    let ht = usize(h.height)
    let (out, out_error) = image.allocate(a, h.width, h.height, .Rgba8, alpha_of(h))
    if out_error != ok { ret (zero, out_error) }
    let row_bytes = (w * usize(h.bits) * usize(h.samples) + 7usize) / 8usize
    let rps = usize(h.rows_per_strip)
    var strip = 0usize
    while strip < h.strips {
        var rows = rps
        if (strip + 1usize) * rps > ht { rows = ht - strip * rps }
        let want = rows * row_bytes
        let off = usize(nth(&rd, h.offsets_at, h.offsets_type, strip))
        var length = 0usize
        if h.counts_at != 0usize { length = usize(nth(&rd, h.counts_at, h.counts_type, strip)) } else { length = want }
        if off > d.len || length > d.len - off { ret (zero, Invalid) }
        let src = d[off..off + length]
        let (raw, raw_error) = mem.alloc[u8](a, want + 1usize)
        if raw_error != ok { ret (zero, raw_error) }
        var produced = 0usize
        if h.compression == 1u32 {
            if length < want { ret (zero, Invalid) }
            mem.copy[u8](raw[..want], src[..want])
            produced = want
        } else if h.compression == 5u32 {
            let (n, e) = lzw(src, raw[..want])
            if e != ok { ret (zero, e) }
            produced = n
        } else if h.compression == 32773u32 {
            let (n, e) = packbits(src, raw[..want])
            if e != ok { ret (zero, e) }
            produced = n
        } else {
            let (n, e) = inflate(a, src, raw[..want])
            if e != ok { ret (zero, e) }
            produced = n
        }
        if produced < want { ret (zero, Invalid) }
        if h.predictor == 2u32 {
            var y = 0usize
            while y < rows {
                var x = usize(h.samples)
                while x < w * usize(h.samples) {
                    raw[y * row_bytes + x] = raw[y * row_bytes + x] +% raw[y * row_bytes + x - usize(h.samples)]
                    x += 1usize
                }
                y += 1usize
            }
        }
        // pixels of this strip
        var y = 0usize
        while y < rows {
            let dst_y = strip * rps + y
            var x = 0usize
            while x < w {
                var s = 0usize
                var v: [4]u32 = zero
                while s < usize(h.samples) {
                    let sample_index = x * usize(h.samples) + s
                    if h.bits == 8u32 {
                        v[s] = u32(raw[y * row_bytes + sample_index])
                    } else if h.bits == 16u32 {
                        let p = y * row_bytes + sample_index * 2usize
                        if h.big { v[s] = u32(raw[p]) } else { v[s] = u32(raw[p + 1usize]) }
                    } else {
                        let bit = sample_index * usize(h.bits)
                        let byte = u32(raw[y * row_bytes + bit / 8usize])
                        let shift = 8usize - usize(h.bits) - bit % 8usize
                        let raw_value = (byte >> u32(shift)) & ((1u32 << h.bits) - 1u32)
                        if h.photometric == 3u32 {
                            v[s] = raw_value
                        } else {
                            v[s] = raw_value * 255u32 / ((1u32 << h.bits) - 1u32)
                        }
                    }
                    s += 1usize
                }
                var rr = 0u32
                var gg = 0u32
                var bb = 0u32
                var aa = 255u32
                if h.photometric == 3u32 {
                    let entries = 1usize << usize(h.bits)
                    let index = usize(v[0])
                    if h.color_map_len < entries * 3usize || index >= entries { ret (zero, Invalid) }
                    rr = nth(&rd, h.color_map_at, 3u32, index) >> 8u32
                    gg = nth(&rd, h.color_map_at, 3u32, entries + index) >> 8u32
                    bb = nth(&rd, h.color_map_at, 3u32, entries * 2usize + index) >> 8u32
                } else if h.photometric == 2u32 {
                    rr = v[0]
                    gg = v[1]
                    bb = v[2]
                    if h.samples == 4u32 { aa = v[3] }
                } else {
                    var grey = v[0]
                    if h.photometric == 0u32 { grey = 255u32 - grey }
                    rr = grey
                    gg = grey
                    bb = grey
                    if h.samples == 2u32 { aa = v[1] }
                }
                if alpha_of(h) == .Opaque { aa = 255u32 }
                let o = dst_y * out.stride + x * 4usize
                out.pixels[o] = u8(rr & 255u32)
                out.pixels[o + 1usize] = u8(gg & 255u32)
                out.pixels[o + 2usize] = u8(bb & 255u32)
                out.pixels[o + 3usize] = u8(aa & 255u32)
                x += 1usize
            }
            y += 1usize
        }
        strip += 1usize
    }
    ret (out, ok)
}
