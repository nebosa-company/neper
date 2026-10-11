// BMP / DIB decoder (L124): the OS/2 core header (12 bytes) and the Windows INFO, V2-V5
// headers; 1, 4 and 8 bit palette images, 16 bit (5-5-5, or bit fields), 24 bit and 32 bit
// (BGRX/BGRA, or bit fields); BI_RGB, BI_RLE8, BI_RLE4, BI_BITFIELDS and
// BI_ALPHABITFIELDS; bottom-up and top-down rows. The result is Rgba8. A channel taken from
// a bit field of n bits is scaled with v * 255 / (2^n - 1), and the fourth byte of a 32
// bit BI_RGB pixel is unused (alpha comes only from an alpha mask in a bit-field or V4/V5
// header, as in Pillow and the browsers). Dimensions are checked
// against the options before any pixel is taken (zero selects 16,384 per side and
// 16,777,216 pixels) and row and palette sizes are checked against the data. Decode only;
// embedded JPEG and PNG data, CMYK and OS/2 2.0 compression are `Unsupported`.

use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64 }
type Header = struct { width: u32, height: u32, top_down: bool, bits: u32, compression: u32, colors: u32, header_size: u32, data_offset: u32, masks: [4]u32, has_alpha_mask: bool, palette_at: usize, palette_entry: usize }
error Invalid
error Unsupported
error TooLarge

const READ_LIMIT: usize = 1073741824usize

fn le16(d: []const u8, at: usize) -> u32 { ret u32(d[at]) | (u32(d[at + 1usize]) << 8u32) }

fn le32(d: []const u8, at: usize) -> u32 {
    ret u32(d[at]) | (u32(d[at + 1usize]) << 8u32) | (u32(d[at + 2usize]) << 16u32) | (u32(d[at + 3usize]) << 24u32)
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

fn parse_header(d: []const u8) -> (Header, err) {
    var h: Header = zero
    if d.len < 26usize { ret (h, Invalid) }
    if d[0] != 66u8 || d[1] != 77u8 { ret (h, Invalid) }
    h.data_offset = le32(d, 10usize)
    let size = le32(d, 14usize)
    h.header_size = size
    var width_signed = 0i32
    var height_signed = 0i32
    if size == 12u32 {
        width_signed = i32(le16(d, 18usize))
        height_signed = i32(le16(d, 20usize))
        if le16(d, 22usize) != 1u32 { ret (h, Invalid) }
        h.bits = le16(d, 24usize)
        h.compression = 0u32
        h.palette_entry = 3usize
    } else if size >= 40u32 && size <= 124u32 {
        if d.len < 14usize + 40usize { ret (h, Invalid) }
        let w = le32(d, 18usize)
        let ht = le32(d, 22usize)
        if w >= 2147483648u32 { ret (h, Invalid) }
        width_signed = i32(w)
        if ht >= 2147483648u32 {
            h.top_down = true
            if ht == 2147483648u32 { ret (h, Invalid) }
            height_signed = i32(0u32 -% ht)
        } else {
            height_signed = i32(ht)
        }
        if le16(d, 26usize) != 1u32 { ret (h, Invalid) }
        h.bits = le16(d, 28usize)
        h.compression = le32(d, 30usize)
        h.colors = le32(d, 46usize)
        h.palette_entry = 4usize
    } else {
        ret (h, Unsupported)
    }
    if width_signed <= 0i32 || height_signed <= 0i32 { ret (h, Invalid) }
    h.width = u32(width_signed)
    h.height = u32(height_signed)
    let b = h.bits
    if b != 1u32 && b != 4u32 && b != 8u32 && b != 16u32 && b != 24u32 && b != 32u32 { ret (h, Invalid) }
    let c = h.compression
    if c > 3u32 && c != 6u32 { ret (h, Unsupported) }
    if c == 1u32 && b != 8u32 { ret (h, Invalid) }
    if c == 2u32 && b != 4u32 { ret (h, Invalid) }
    if (c == 3u32 || c == 6u32) && b != 16u32 && b != 32u32 { ret (h, Invalid) }
    // masks: inside the V4+ header, or three or four words after an INFO header
    if c == 3u32 || c == 6u32 {
        let at = 14usize + 40usize
        var words = 3usize
        if c == 6u32 { words = 4usize }
        if size == 40u32 {
            if d.len < at + words * 4usize { ret (h, Invalid) }
            var k = 0usize
            while k < words {
                h.masks[k] = le32(d, at + k * 4usize)
                k += 1usize
            }
            h.palette_at = at + words * 4usize
        } else {
            if d.len < 14usize + 52usize { ret (h, Invalid) }
            var k = 0usize
            while k < 3usize {
                h.masks[k] = le32(d, at + k * 4usize)
                k += 1usize
            }
            if size >= 56u32 && d.len >= 14usize + 56usize { h.masks[3] = le32(d, at + 12usize) }
            h.palette_at = 14usize + usize(size)
        }
        h.has_alpha_mask = h.masks[3] != 0u32
    } else {
        h.palette_at = 14usize + usize(size)
    }
    ret (h, ok)
}

fn inspect(source: io.Reader) -> (image.Info, err) {
    var r = source
    var head: [138]u8 = zero
    var got = 0usize
    while got < head.len {
        let (n, read_error) = io.read(&r, head[got..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        got += n
    }
    let (h, failure) = parse_header(head[..got])
    if failure != ok { ret (zero, failure) }
    var info: image.Info = zero
    info.width = h.width
    info.height = h.height
    info.format = .Rgba8
    info.frames = 1u32
    info.alpha = .Opaque
    if h.has_alpha_mask { info.alpha = .Straight }
    ret (info, ok)
}

fn shift_of(mask: u32) -> u32 {
    if mask == 0u32 { ret 0u32 }
    var s = 0u32
    var m = mask
    while (m & 1u32) == 0u32 {
        m = m >> 1u32
        s += 1u32
    }
    ret s
}

fn bits_of(mask: u32) -> u32 {
    var n = 0u32
    var m = mask >> shift_of(mask)
    while m != 0u32 {
        n += 1u32
        m = m >> 1u32
    }
    ret n
}

fn channel(pixel: u32, mask: u32, shift: u32, bits: u32) -> u8 {
    if mask == 0u32 || bits == 0u32 { ret 255u8 }
    let v = (pixel & mask) >> shift
    let top = (1u32 << bits) - 1u32
    ret u8(v * 255u32 / top)
}

fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var r = source
    let (d, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (zero, read_error) }
    let (h, header_error) = parse_header(d)
    if header_error != ok { ret (zero, header_error) }
    let within_error = within(h.width, h.height, options)
    if within_error != ok { ret (zero, within_error) }
    let w = usize(h.width)
    let ht = usize(h.height)
    let (out, out_error) = image.allocate(a, h.width, h.height, .Rgba8, .Straight)
    if out_error != ok { ret (zero, out_error) }
    let start = usize(h.data_offset)
    if start > d.len { ret (zero, Invalid) }
    // the palette
    var palette: [256]u32 = zero
    if h.bits <= 8u32 {
        var count = usize(h.colors)
        let full = 1usize << usize(h.bits)
        if count == 0usize || count > full { count = full }
        let need = h.palette_at + count * h.palette_entry
        if need > d.len { ret (zero, Invalid) }
        var k = 0usize
        while k < count {
            let p = h.palette_at + k * h.palette_entry
            palette[k] = (u32(d[p + 2usize]) << 16u32) | (u32(d[p + 1usize]) << 8u32) | u32(d[p]) | 4278190080u32
            k += 1usize
        }
    }
    // palette indices for RLE, decoded to one byte per pixel
    if h.compression == 1u32 || h.compression == 2u32 {
        let (idx, idx_error) = mem.alloc[u8](a, w * ht + 1usize)
        if idx_error != ok { ret (zero, idx_error) }
        var z = 0usize
        while z < w * ht {
            idx[z] = 0u8
            z += 1usize
        }
        var x = 0usize
        var y = 0usize
        var at = start
        var done = false
        while !done && at + 2usize <= d.len {
            let n = usize(d[at])
            let v = d[at + 1usize]
            at += 2usize
            if n > 0usize {
                var k = 0usize
                while k < n {
                    var px = v
                    if h.compression == 2u32 {
                        if k % 2usize == 0usize { px = v >> 4u32 } else { px = v & 15u8 }
                    }
                    if x < w && y < ht { idx[y * w + x] = px }
                    x += 1usize
                    k += 1usize
                }
            } else if v == 0u8 {
                x = 0usize
                y += 1usize
            } else if v == 1u8 {
                done = true
            } else if v == 2u8 {
                if at + 2usize > d.len { ret (zero, Invalid) }
                x += usize(d[at])
                y += usize(d[at + 1usize])
                at += 2usize
            } else {
                let count = usize(v)
                var bytes_used = count
                if h.compression == 2u32 { bytes_used = (count + 1usize) / 2usize }
                if at + bytes_used > d.len { ret (zero, Invalid) }
                var k = 0usize
                while k < count {
                    var px = 0u8
                    if h.compression == 2u32 {
                        let byte = d[at + k / 2usize]
                        if k % 2usize == 0usize { px = byte >> 4u32 } else { px = byte & 15u8 }
                    } else {
                        px = d[at + k]
                    }
                    if x < w && y < ht { idx[y * w + x] = px }
                    x += 1usize
                    k += 1usize
                }
                at += bytes_used
                if bytes_used % 2usize == 1usize { at += 1usize }
            }
            if y > ht + 1usize { break }
        }
        var row = 0usize
        while row < ht {
            var dst_row = row
            if !h.top_down { dst_row = ht - 1usize - row }
            var col = 0usize
            while col < w {
                let c = palette[usize(idx[row * w + col])]
                let o = dst_row * out.stride + col * 4usize
                out.pixels[o] = u8((c >> 16u32) & 255u32)
                out.pixels[o + 1usize] = u8((c >> 8u32) & 255u32)
                out.pixels[o + 2usize] = u8(c & 255u32)
                out.pixels[o + 3usize] = 255u8
                col += 1usize
            }
            row += 1usize
        }
        ret (out, ok)
    }
    // raw rows, padded to four bytes
    let row_bits = u64(w) * u64(h.bits)
    let stride = usize(((row_bits + 31u64) / 32u64) * 4u64)
    if stride * ht > d.len - start { ret (zero, Invalid) }
    var masks = h.masks
    var shifts: [4]u32 = zero
    var widths: [4]u32 = zero
    var use_masks = h.compression == 3u32 || h.compression == 6u32 || h.has_alpha_mask
    if h.bits == 16u32 && !use_masks {
        masks[0] = 31744u32
        masks[1] = 992u32
        masks[2] = 31u32
        use_masks = true
    }
    var k = 0usize
    while k < 4usize {
        shifts[k] = shift_of(masks[k])
        widths[k] = bits_of(masks[k])
        k += 1usize
    }
    // a 32 bit BI_RGB pixel's fourth byte is unused, as in Pillow and the browsers
    let alpha_used = false
    var row = 0usize
    while row < ht {
        var dst_row = row
        if !h.top_down { dst_row = ht - 1usize - row }
        let src = start + row * stride
        var col = 0usize
        while col < w {
            let o = dst_row * out.stride + col * 4usize
            var rr = 0u8
            var gg = 0u8
            var bb = 0u8
            var aa = 255u8
            if h.bits <= 8u32 {
                let per = usize(8u32 / h.bits)
                let byte = d[src + col / per]
                let shift = u32(8usize - usize(h.bits) * (col % per + 1usize))
                let index = usize((u32(byte) >> shift) & ((1u32 << h.bits) - 1u32))
                let c = palette[index]
                rr = u8((c >> 16u32) & 255u32)
                gg = u8((c >> 8u32) & 255u32)
                bb = u8(c & 255u32)
            } else if h.bits == 24u32 {
                bb = d[src + col * 3usize]
                gg = d[src + col * 3usize + 1usize]
                rr = d[src + col * 3usize + 2usize]
            } else {
                var pixel = 0u32
                if h.bits == 16u32 {
                    pixel = le16(d, src + col * 2usize)
                } else {
                    pixel = le32(d, src + col * 4usize)
                }
                if use_masks {
                    rr = channel(pixel, masks[0], shifts[0], widths[0])
                    gg = channel(pixel, masks[1], shifts[1], widths[1])
                    bb = channel(pixel, masks[2], shifts[2], widths[2])
                    if h.has_alpha_mask { aa = channel(pixel, masks[3], shifts[3], widths[3]) }
                } else {
                    bb = u8(pixel & 255u32)
                    gg = u8((pixel >> 8u32) & 255u32)
                    rr = u8((pixel >> 16u32) & 255u32)
                    if alpha_used { aa = u8((pixel >> 24u32) & 255u32) }
                }
            }
            out.pixels[o] = rr
            out.pixels[o + 1usize] = gg
            out.pixels[o + 2usize] = bb
            out.pixels[o + 3usize] = aa
            col += 1usize
        }
        row += 1usize
    }
    ret (out, ok)
}
