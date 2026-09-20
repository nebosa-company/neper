// JPEG (ITU T.81) both ways. Decoding takes baseline and extended sequential Huffman
// (SOF0, SOF1) and progressive Huffman (SOF2) at 8 bits, greyscale, YCbCr and RGB
// (Adobe transform 0), any sampling factors, restart intervals and several scans per
// component; every scan is decoded through the one progressive machinery -- a baseline
// scan is the case `Ss = 0, Se = 63` -- into coefficient planes held in the arena, then
// dequantised, run through a separable float IDCT, upsampled with the triangle filter
// libjpeg calls fancy, and converted to `image.Rgba8` (opaque) or `image.R8` for
// greyscale. Arithmetic coding (SOF9-11), lossless (SOF3), 12-bit samples, hierarchical
// frames and CMYK answer `Unsupported`; a stream that lies about itself is `Invalid`.
// `inspect` reads through the headers up to the first scan. Dimensions are checked
// against the options before any plane is allocated; a zero limit is no limit.
//
// Encoding writes baseline 4:4:4 YCbCr from `Rgba8` and `Bgra8` (alpha dropped) and
// greyscale from `R8`, with the Annex K quantisation tables scaled by `quality` as
// libjpeg scales them and the Annex K Huffman tables; the output is deterministic for
// the same pixels and options. ponytail: `progressive` encoding and chroma subsampling
// are `Unsupported`; a progressive writer needs scan scripting and a 4:2:0 writer a
// chroma downsampler, and neither buys correctness. `Rgba16Float` is `Unsupported`.

use e.bytes
use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64 }
type EncodeOptions = struct { quality: u8, progressive: bool }
error Invalid
error Unsupported
error TooLarge

const READ_LIMIT: usize = 1073741824usize

fn luma_quant() -> str { ret "\x10\x0b\x0a\x10\x18(3=\x0c\x0c\x0e\x13\x1a:<7\x0e\x0d\x10\x18(9E8\x0e\x11\x16\x1d3WP>\x12\x16%8DmgM\x18#7@Qhq\\1@NWgyxeH\\_bpdgc" }

fn chroma_quant() -> str { ret "\x11\x12\x18/cccc\x12\x15\x1aBcccc\x18\x1a8ccccc/Bcccccccccccccccccccccccccccccccccccccc" }

fn zigzag() -> str { ret "\x00\x01\x08\x10\x09\x02\x03\x0a\x11\x18 \x19\x12\x0b\x04\x05\x0c\x13\x1a!(0)\"\x1b\x14\x0d\x06\x07\x0e\x15\x1c#*1892+$\x1d\x16\x0f\x17\x1e%,3:;4-&\x1f'.5<=6/7>?" }

fn dc_luma_bits() -> str { ret "\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00" }

fn dc_luma_values() -> str { ret "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b" }

fn dc_chroma_bits() -> str { ret "\x00\x03\x01\x01\x01\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00" }

fn dc_chroma_values() -> str { ret "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b" }

fn ac_luma_bits() -> str { ret "\x00\x02\x01\x03\x03\x02\x04\x03\x05\x05\x04\x04\x00\x00\x01}" }

fn ac_luma_values() -> str { ret "\x01\x02\x03\x00\x04\x11\x05\x12!1A\x06\x13Qa\x07\"q\x142\x81\x91\xa1\x08#B\xb1\xc1\x15R\xd1\xf0$3br\x82\x09\x0a\x16\x17\x18\x19\x1a%&'()*456789:CDEFGHIJSTUVWXYZcdefghijstuvwxyz\x83\x84\x85\x86\x87\x88\x89\x8a\x92\x93\x94\x95\x96\x97\x98\x99\x9a\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa" }

fn ac_chroma_bits() -> str { ret "\x00\x02\x01\x02\x04\x04\x03\x04\x07\x05\x04\x04\x00\x01\x02w" }

fn ac_chroma_values() -> str { ret "\x00\x01\x02\x03\x11\x04\x05!1\x06\x12AQ\x07aq\x13\"2\x81\x08\x14B\x91\xa1\xb1\xc1\x09#3R\xf0\x15br\xd1\x0a\x16$4\xe1%\xf1\x17\x18\x19\x1a&'()*56789:CDEFGHIJSTUVWXYZcdefghijstuvwxyz\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x92\x93\x94\x95\x96\x97\x98\x99\x9a\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa" }


// A Huffman table in the spec's F.2.2.3 form: for each length the smallest and
// largest code and where its values start; `present` says the slot was defined.
type Huffman = struct { mincode: [17]i32, maxcode: [18]i32, valptr: [17]i32, values: [256]u8, present: bool }

type Component = struct {
    id: u32,
    h: usize,
    v: usize,
    quant: usize,
    dc_table: usize,
    ac_table: usize,
    blocks_w: usize,
    blocks_h: usize,
    coefficients: []i32,
    predictor: i32,
    plane: []u8,
    plane_w: usize,
    plane_h: usize,
}

type Frame = struct {
    width: usize,
    height: usize,
    progressive: bool,
    count: usize,
    components: [4]Component,
    hmax: usize,
    vmax: usize,
    mcus_x: usize,
    mcus_y: usize,
    restart_interval: usize,
    adobe_transform: u32,
    has_adobe: bool,
}

type Bits = struct { data: []const u8, at: usize, cache: u32, count: u32, marker_hit: bool }

// ------------------------------------------------------------------ bit reading

fn fill(b: *Bits) {
    while b.count <= 24u32 {
        var byte = 0u32
        if !b.marker_hit && b.at < b.data.len {
            byte = u32(b.data[b.at])
            if byte == 255u32 {
                var next = 0u32
                if b.at + 1usize < b.data.len { next = u32(b.data[b.at + 1usize]) }
                if next == 0u32 {
                    b.at += 2usize
                } else {
                    b.marker_hit = true
                    byte = 0u32
                }
            } else {
                b.at += 1usize
            }
        }
        b.cache = b.cache | (byte << (24u32 - b.count))
        b.count += 8u32
    }
}

fn take(b: *Bits, n: u32) -> u32 {
    if n == 0u32 { ret 0u32 }
    fill(b)
    let v = b.cache >> (32u32 - n)
    b.cache = b.cache << n
    b.count -= n
    ret v
}

fn take_bit(b: *Bits) -> u32 {
    ret take(b, 1u32)
}

fn decode_symbol(b: *Bits, h: *const Huffman) -> (u32, err) {
    var code = i32(take_bit(b))
    var length = 1usize
    while length <= 16usize && code > h.maxcode[length] {
        code = (code << 1u32) | i32(take_bit(b))
        length += 1usize
    }
    if length > 16usize { ret (0u32, Invalid) }
    let index = h.valptr[length] + code - h.mincode[length]
    if index < 0i32 || index >= 256i32 { ret (0u32, Invalid) }
    ret (u32(h.values[usize(index)]), ok)
}

fn extend(value: u32, bits: u32) -> i32 {
    if bits == 0u32 { ret 0i32 }
    if value < (1u32 << (bits - 1u32)) { ret i32(value) - (1i32 << bits) + 1i32 }
    ret i32(value)
}

// After a restart marker: the bit buffer starts over at the byte after it.
fn restart(b: *Bits) -> err {
    b.cache = 0u32
    b.count = 0u32
    b.marker_hit = false
    if b.at + 1usize >= b.data.len || b.data[b.at] != 255u8 { ret Invalid }
    let marker = u32(b.data[b.at + 1usize])
    if marker < 208u32 || marker > 215u32 { ret Invalid }
    b.at += 2usize
    ret ok
}

// ------------------------------------------------------------------ tables

fn build_huffman(bits: []const u8, values: []const u8) -> (Huffman, err) {
    var h: Huffman = zero
    var total = 0usize
    var i = 0usize
    while i < 16usize {
        total += usize(bits[i])
        i += 1usize
    }
    if total > 256usize || values.len < total { ret (zero, Invalid) }
    i = 0usize
    while i < total {
        h.values[i] = values[i]
        i += 1usize
    }
    var code = 0i32
    var k = 0i32
    var length = 1usize
    while length <= 16usize {
        let n = i32(bits[length - 1usize])
        h.valptr[length] = k
        h.mincode[length] = code
        code += n
        k += n
        if n > 0i32 { h.maxcode[length] = code - 1i32 } else { h.maxcode[length] = -1i32 }
        code = code << 1u32
        length += 1usize
    }
    h.maxcode[17] = 2147483647i32
    h.present = true
    ret (h, ok)
}

fn zz(k: usize) -> usize {
    ret usize(zigzag()[k])
}

// ------------------------------------------------------------------ scans

type Scan = struct { count: usize, members: [4]usize, ss: usize, se: usize, ah: u32, al: u32, eobrun: u32 }

fn decode_block(b: *Bits, f: *Frame, s: *Scan, dc: []Huffman, ac: []Huffman, c: *Component, block: usize) -> err {
    let base = block * 64usize
    if s.ss == 0usize {
        if s.ah == 0u32 {
            if !dc[c.dc_table].present { ret Invalid }
            let (t, t_error) = decode_symbol(b, &dc[c.dc_table])
            if t_error != ok { ret t_error }
            if t > 16u32 { ret Invalid }
            let diff = extend(take(b, t), t)
            c.predictor += diff
            c.coefficients[base] = c.predictor << s.al
        } else if take_bit(b) != 0u32 {
            c.coefficients[base] = c.coefficients[base] | (1i32 << s.al)
        }
        if s.se == 0usize { ret ok }
    }
    var k = s.ss
    if k == 0usize { k = 1usize }
    if !ac[c.ac_table].present { ret Invalid }
    if s.ah == 0u32 {
        // First AC scan (and the whole of a sequential block): runs and end-of-band.
        if s.eobrun > 0u32 {
            s.eobrun -= 1u32
            ret ok
        }
        while k <= s.se {
            let (rs, rs_error) = decode_symbol(b, &ac[c.ac_table])
            if rs_error != ok { ret rs_error }
            let r = rs >> 4u32
            let size = rs & 15u32
            if size == 0u32 {
                if r < 15u32 {
                    s.eobrun = (1u32 << r) - 1u32
                    if r > 0u32 { s.eobrun += take(b, r) }
                    break
                }
                k += 16usize
                continue
            }
            k += usize(r)
            if k > 63usize { ret Invalid }
            c.coefficients[base + zz(k)] = extend(take(b, size), size) << s.al
            k += 1usize
        }
        ret ok
    }
    // AC refinement (G.1.2.3): one more bit for every coefficient already nonzero,
    // new coefficients of magnitude one placed by zero-run.
    let p1 = 1i32 << s.al
    let m1 = -1i32 << s.al
    if s.eobrun == 0u32 {
        while k <= s.se {
            let (rs, rs_error) = decode_symbol(b, &ac[c.ac_table])
            if rs_error != ok { ret rs_error }
            var r = i32(rs >> 4u32)
            let size = rs & 15u32
            var value = 0i32
            if size == 0u32 {
                if r < 15i32 {
                    s.eobrun = (1u32 << u32(r))
                    if r > 0i32 { s.eobrun += take(b, u32(r)) }
                    break
                }
            } else {
                if size != 1u32 { ret Invalid }
                if take_bit(b) != 0u32 { value = p1 } else { value = m1 }
            }
            while k <= s.se {
                let at = base + zz(k)
                if c.coefficients[at] != 0i32 {
                    if take_bit(b) != 0u32 {
                        let coef = c.coefficients[at]
                        if (coef & p1) == 0i32 {
                            if coef >= 0i32 { c.coefficients[at] = coef + p1 } else { c.coefficients[at] = coef + m1 }
                        }
                    }
                } else {
                    if r == 0i32 {
                        if value != 0i32 { c.coefficients[at] = value }
                        k += 1usize
                        break
                    }
                    r -= 1i32
                }
                k += 1usize
            }
        }
    }
    if s.eobrun > 0u32 {
        while k <= s.se {
            let at = base + zz(k)
            if c.coefficients[at] != 0i32 && take_bit(b) != 0u32 {
                let coef = c.coefficients[at]
                if (coef & p1) == 0i32 {
                    if coef >= 0i32 { c.coefficients[at] = coef + p1 } else { c.coefficients[at] = coef + m1 }
                }
            }
            k += 1usize
        }
        s.eobrun -= 1u32
    }
    ret ok
}

fn decode_scan(b: *Bits, f: *Frame, s: *Scan, dc: []Huffman, ac: []Huffman) -> err {
    var i = 0usize
    while i < f.count {
        f.components[i].predictor = 0i32
        i += 1usize
    }
    s.eobrun = 0u32
    var mcus = 0usize
    var total = 0usize
    if s.count == 1usize {
        let c = &f.components[s.members[0]]
        let bw = (c.plane_w + 7usize) / 8usize
        let bh = (c.plane_h + 7usize) / 8usize
        total = bw * bh
        var by = 0usize
        while by < bh {
            var bx = 0usize
            while bx < bw {
                if f.restart_interval != 0usize && mcus > 0usize && mcus % f.restart_interval == 0usize {
                    let restart_error = restart(b)
                    if restart_error != ok { ret restart_error }
                    c.predictor = 0i32
                    s.eobrun = 0u32
                }
                let block_error = decode_block(b, f, s, dc, ac, c, by * c.blocks_w + bx)
                if block_error != ok { ret block_error }
                mcus += 1usize
                bx += 1usize
            }
            by += 1usize
        }
        ret ok
    }
    var my = 0usize
    while my < f.mcus_y {
        var mx = 0usize
        while mx < f.mcus_x {
            if f.restart_interval != 0usize && mcus > 0usize && mcus % f.restart_interval == 0usize {
                let restart_error = restart(b)
                if restart_error != ok { ret restart_error }
                i = 0usize
                while i < f.count {
                    f.components[i].predictor = 0i32
                    i += 1usize
                }
                s.eobrun = 0u32
            }
            var m = 0usize
            while m < s.count {
                let c = &f.components[s.members[m]]
                var v = 0usize
                while v < c.v {
                    var h = 0usize
                    while h < c.h {
                        let block_error = decode_block(b, f, s, dc, ac, c, (my * c.v + v) * c.blocks_w + mx * c.h + h)
                        if block_error != ok { ret block_error }
                        h += 1usize
                    }
                    v += 1usize
                }
                m += 1usize
            }
            mcus += 1usize
            mx += 1usize
        }
        my += 1usize
    }
    ret ok
}

// ------------------------------------------------------------------ IDCT and colour

fn cos_table(t: []f32) {
    // cos((2x+1)*u*pi/16) * c(u) / 2, c(0) = 1/sqrt2, by the Taylor series once.
    var u = 0usize
    while u < 8usize {
        var x = 0usize
        while x < 8usize {
            let angle = f32(((2usize * x + 1usize) * u) % 32usize) * 0.19634954
            var c = cosine(angle)
            if u == 0usize { c = c * 0.70710678 }
            t[u * 8usize + x] = c * 0.5
            x += 1usize
        }
        u += 1usize
    }
}

// cos over [0, 2pi) by folding to [0, pi/2] and a nine-term series.
fn cosine(angle: f32) -> f32 {
    var a = angle
    var sign: f32 = 1.0
    if a > 3.14159265 {
        a = 6.2831853 - a
    }
    if a > 1.57079633 {
        a = 3.14159265 - a
        sign = -1.0
    }
    let a2 = a * a
    var term: f32 = 1.0
    var sum: f32 = 1.0
    var n: f32 = 1.0
    var i = 0usize
    while i < 9usize {
        term = 0.0 - term * a2 / (n * (n + 1.0))
        sum += term
        n += 2.0
        i += 1usize
    }
    ret sign * sum
}

fn idct_block(coefficients: []const i32, base: usize, quant: []const u8, t: []const f32, out: []u8, out_at: usize, stride: usize) {
    var d: [64]f32 = zero
    var tmp: [64]f32 = zero
    var i = 0usize
    while i < 64usize {
        d[zz(i)] = f32(coefficients[base + zz(i)]) * f32(quant[i])
        i += 1usize
    }
    // Rows: tmp[y][x] = sum_u t[u][x] * d[y][u].
    var y = 0usize
    while y < 8usize {
        var x = 0usize
        while x < 8usize {
            var sum: f32 = 0.0
            var u = 0usize
            while u < 8usize {
                sum += t[u * 8usize + x] * d[y * 8usize + u]
                u += 1usize
            }
            tmp[y * 8usize + x] = sum
            x += 1usize
        }
        y += 1usize
    }
    // Columns.
    var x = 0usize
    while x < 8usize {
        y = 0usize
        while y < 8usize {
            var sum: f32 = 0.0
            var v = 0usize
            while v < 8usize {
                sum += t[v * 8usize + y] * tmp[v * 8usize + x]
                v += 1usize
            }
            var value = i32(sum + 128.5)
            if sum + 128.5 < 0.0 { value = 0i32 }
            if value > 255i32 { value = 255i32 }
            out[out_at + y * stride + x] = u8(value)
            y += 1usize
        }
        x += 1usize
    }
}

fn clamp_byte(v: f32) -> u8 {
    if v <= 0.0 { ret 0u8 }
    if v >= 255.0 { ret 255u8 }
    ret u8(i32(v + 0.5))
}

// The plane's value at output pixel (x, y), the triangle filter across an
// upsampling of `fx`, `fy`.
fn sample_plane(c: *const Component, x: usize, y: usize, fx: usize, fy: usize) -> f32 {
    if fx == 1usize && fy == 1usize { ret f32(c.plane[y * c.plane_w + x]) }
    let sx = (f32(x) + 0.5) / f32(fx) - 0.5
    let sy = (f32(y) + 0.5) / f32(fy) - 0.5
    var x0 = 0i32
    if sx > 0.0 { x0 = i32(sx) }
    var y0 = 0i32
    if sy > 0.0 { y0 = i32(sy) }
    var wx = sx - f32(x0)
    var wy = sy - f32(y0)
    if wx < 0.0 { wx = 0.0 }
    if wy < 0.0 { wy = 0.0 }
    var x1 = x0 + 1i32
    var y1 = y0 + 1i32
    if x1 >= i32(c.plane_w) { x1 = i32(c.plane_w) - 1i32 }
    if y1 >= i32(c.plane_h) { y1 = i32(c.plane_h) - 1i32 }
    if x0 >= i32(c.plane_w) { x0 = i32(c.plane_w) - 1i32 }
    if y0 >= i32(c.plane_h) { y0 = i32(c.plane_h) - 1i32 }
    let top = f32(c.plane[usize(y0) * c.plane_w + usize(x0)]) * (1.0 - wx) + f32(c.plane[usize(y0) * c.plane_w + usize(x1)]) * wx
    let bottom = f32(c.plane[usize(y1) * c.plane_w + usize(x0)]) * (1.0 - wx) + f32(c.plane[usize(y1) * c.plane_w + usize(x1)]) * wx
    ret top * (1.0 - wy) + bottom * wy
}

// ------------------------------------------------------------------ the stream

type Decoder = struct {
    data: []const u8,
    at: usize,
    frame: Frame,
    quant: [4][64]u8,
    quant_present: [4]bool,
    dc: [4]Huffman,
    ac: [4]Huffman,
    seen_frame: bool,
}

fn u16_at(d: []const u8, at: usize) -> usize {
    ret (usize(d[at]) << 8u32) | usize(d[at + 1usize])
}

fn parse_dqt(dec: *Decoder, body: []const u8) -> err {
    var at = 0usize
    while at < body.len {
        let precision = u32(body[at]) >> 4u32
        let id = usize(body[at] & 15u8)
        if id > 3usize { ret Invalid }
        if precision != 0u32 { ret Unsupported }
        if at + 65usize > body.len { ret Invalid }
        var i = 0usize
        while i < 64usize {
            dec.quant[id][i] = body[at + 1usize + i]
            i += 1usize
        }
        dec.quant_present[id] = true
        at += 65usize
    }
    ret ok
}

fn parse_dht(dec: *Decoder, body: []const u8) -> err {
    var at = 0usize
    while at + 17usize <= body.len {
        let class = u32(body[at]) >> 4u32
        let id = usize(body[at] & 15u8)
        if id > 3usize || class > 1u32 { ret Invalid }
        var total = 0usize
        var i = 0usize
        while i < 16usize {
            total += usize(body[at + 1usize + i])
            i += 1usize
        }
        if at + 17usize + total > body.len { ret Invalid }
        let (table, table_error) = build_huffman(body[at + 1usize..at + 17usize], body[at + 17usize..at + 17usize + total])
        if table_error != ok { ret table_error }
        if class == 0u32 { dec.dc[id] = table } else { dec.ac[id] = table }
        at += 17usize + total
    }
    if at != body.len { ret Invalid }
    ret ok
}

fn parse_sof(dec: *Decoder, body: []const u8, progressive: bool) -> err {
    if dec.seen_frame { ret Unsupported }
    if body.len < 6usize { ret Invalid }
    if body[0] != 8u8 { ret Unsupported }
    var f: Frame = zero
    f.height = u16_at(body, 1usize)
    f.width = u16_at(body, 3usize)
    f.count = usize(body[5])
    f.progressive = progressive
    if f.width == 0usize || f.height == 0usize { ret Invalid }
    if f.count != 1usize && f.count != 3usize { ret Unsupported }
    if body.len < 6usize + 3usize * f.count { ret Invalid }
    var i = 0usize
    while i < f.count {
        let at = 6usize + 3usize * i
        var c: Component = zero
        c.id = u32(body[at])
        c.h = usize(body[at + 1usize] >> 4u32)
        c.v = usize(body[at + 1usize] & 15u8)
        c.quant = usize(body[at + 2usize])
        if c.h == 0usize || c.h > 4usize || c.v == 0usize || c.v > 4usize || c.quant > 3usize { ret Invalid }
        if c.h > f.hmax { f.hmax = c.h }
        if c.v > f.vmax { f.vmax = c.v }
        f.components[i] = c
        i += 1usize
    }
    f.mcus_x = (f.width + 8usize * f.hmax - 1usize) / (8usize * f.hmax)
    f.mcus_y = (f.height + 8usize * f.vmax - 1usize) / (8usize * f.vmax)
    dec.frame = f
    dec.seen_frame = true
    ret ok
}

// Walks the marker segments up to the first SOS (or EOI), filling the decoder.
fn parse_headers(dec: *Decoder) -> err {
    if dec.data.len < 4usize || dec.data[0] != 255u8 || dec.data[1] != 216u8 { ret Invalid }
    dec.at = 2usize
    while true {
        while dec.at < dec.data.len && dec.data[dec.at] == 255u8 { dec.at += 1usize }
        if dec.at >= dec.data.len { ret Invalid }
        let marker = u32(dec.data[dec.at])
        dec.at += 1usize
        if marker == 217u32 { ret ok }
        if marker == 218u32 { ret ok }
        if marker >= 208u32 && marker <= 215u32 { continue }
        if dec.at + 2usize > dec.data.len { ret Invalid }
        let length = u16_at(dec.data, dec.at)
        if length < 2usize || dec.at + length > dec.data.len { ret Invalid }
        let body = dec.data[dec.at + 2usize..dec.at + length]
        dec.at += length
        if marker == 219u32 {
            let dqt_error = parse_dqt(dec, body)
            if dqt_error != ok { ret dqt_error }
        } else if marker == 196u32 {
            let dht_error = parse_dht(dec, body)
            if dht_error != ok { ret dht_error }
        } else if marker == 192u32 || marker == 193u32 {
            let sof_error = parse_sof(dec, body, false)
            if sof_error != ok { ret sof_error }
        } else if marker == 194u32 {
            let sof_error = parse_sof(dec, body, true)
            if sof_error != ok { ret sof_error }
        } else if marker == 195u32 || (marker >= 197u32 && marker <= 207u32 && marker != 200u32) {
            ret Unsupported
        } else if marker == 221u32 {
            if body.len < 2usize { ret Invalid }
            dec.frame.restart_interval = u16_at(body, 0usize)
        } else if marker == 238u32 {
            if body.len >= 12usize && body[0] == 65u8 && body[1] == 100u8 && body[2] == 111u8 && body[3] == 98u8 && body[4] == 101u8 {
                dec.frame.has_adobe = true
                dec.frame.adobe_transform = u32(body[11])
            }
        }
    }
    ret Invalid
}

fn info_of(f: Frame) -> image.Info {
    var format: image.Format = .Rgba8
    if f.count == 1usize { format = .R8 }
    ret image.Info { width: u32(f.width), height: u32(f.height), format: format, alpha: .Opaque, frames: 1u32 }
}

fn inspect(source: io.Reader) -> (image.Info, err) {
    var r = source
    var head: [65536]u8 = zero
    var filled = 0usize
    while filled < head.len {
        let (got, read_error) = io.read(&r, head[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        filled += got
    }
    var dec: Decoder = zero
    dec.data = head[..filled]
    let header_error = parse_headers(&dec)
    if header_error != ok && !dec.seen_frame { ret (zero, header_error) }
    if !dec.seen_frame { ret (zero, Invalid) }
    ret (info_of(dec.frame), ok)
}

fn within(f: Frame, options: DecodeOptions) -> err {
    if options.max_width != 0u32 && f.width > usize(options.max_width) { ret TooLarge }
    if options.max_height != 0u32 && f.height > usize(options.max_height) { ret TooLarge }
    if options.max_pixels != 0u64 && u64(f.width) * u64(f.height) > options.max_pixels { ret TooLarge }
    ret ok
}

fn parse_sos(dec: *Decoder, body: []const u8) -> (Scan, err) {
    var s: Scan = zero
    if body.len < 1usize { ret (zero, Invalid) }
    s.count = usize(body[0])
    if s.count == 0usize || s.count > 4usize || body.len < 4usize + 2usize * s.count { ret (zero, Invalid) }
    var i = 0usize
    while i < s.count {
        let id = u32(body[1usize + 2usize * i])
        let tables = body[2usize + 2usize * i]
        var found = false
        var k = 0usize
        while k < dec.frame.count {
            if dec.frame.components[k].id == id {
                s.members[i] = k
                dec.frame.components[k].dc_table = usize(tables >> 4u32)
                dec.frame.components[k].ac_table = usize(tables & 15u8)
                if dec.frame.components[k].dc_table > 3usize || dec.frame.components[k].ac_table > 3usize { ret (zero, Invalid) }
                found = true
            }
            k += 1usize
        }
        if !found { ret (zero, Invalid) }
        i += 1usize
    }
    let at = 1usize + 2usize * s.count
    s.ss = usize(body[at])
    s.se = usize(body[at + 1usize])
    s.ah = u32(body[at + 2usize]) >> 4u32
    s.al = u32(body[at + 2usize]) & 15u32
    if !dec.frame.progressive {
        if s.ss != 0usize || s.se != 63usize || s.ah != 0u32 || s.al != 0u32 { ret (zero, Invalid) }
    } else {
        if s.ss > 63usize || s.se > 63usize || s.ss > s.se || s.al > 13u32 { ret (zero, Invalid) }
        if s.ss == 0usize && s.se != 0usize { ret (zero, Invalid) }
        if s.ss != 0usize && s.count != 1usize { ret (zero, Invalid) }
    }
    ret (s, ok)
}

fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var r = source
    let (data, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (zero, read_error) }
    var dec: Decoder = zero
    dec.data = data
    let header_error = parse_headers(&dec)
    if header_error != ok { ret (zero, header_error) }
    if !dec.seen_frame { ret (zero, Invalid) }
    let within_error = within(dec.frame, options)
    if within_error != ok { ret (zero, within_error) }
    let f = &dec.frame
    var i = 0usize
    while i < f.count {
        let c = &f.components[i]
        c.blocks_w = f.mcus_x * c.h
        c.blocks_h = f.mcus_y * c.v
        c.plane_w = (f.width * c.h + f.hmax - 1usize) / f.hmax
        c.plane_h = (f.height * c.v + f.vmax - 1usize) / f.vmax
        let (coefficients, coefficients_error) = mem.alloc[i32](a, c.blocks_w * c.blocks_h * 64usize)
        if coefficients_error != ok { ret (zero, coefficients_error) }
        var k = 0usize
        while k < coefficients.len {
            coefficients[k] = 0i32
            k += 1usize
        }
        c.coefficients = coefficients
        i += 1usize
    }
    // Every scan, up to EOI; the header walker stopped at the first SOS marker byte.
    var scans = 0usize
    while true {
        let marker = u32(dec.data[dec.at - 1usize])
        if marker == 217u32 { break }
        if marker != 218u32 { ret (zero, Invalid) }
        if dec.at + 2usize > dec.data.len { ret (zero, Invalid) }
        let length = u16_at(dec.data, dec.at)
        if length < 2usize || dec.at + length > dec.data.len { ret (zero, Invalid) }
        let (scan, scan_error) = parse_sos(&dec, dec.data[dec.at + 2usize..dec.at + length])
        if scan_error != ok { ret (zero, scan_error) }
        var s = scan
        var b = Bits { data: dec.data, at: dec.at + length, cache: 0u32, count: 0u32, marker_hit: false }
        let decode_error = decode_scan(&b, f, &s, dec.dc[0..], dec.ac[0..])
        if decode_error != ok { ret (zero, decode_error) }
        scans += 1usize
        // Resume the marker walk after the entropy data.
        dec.at = b.at
        let more_error = parse_headers_from(&dec)
        if more_error != ok { ret (zero, more_error) }
    }
    if scans == 0usize { ret (zero, Invalid) }
    // Planes: dequantise and transform every block.
    var t: [64]f32 = zero
    cos_table(t[0..])
    i = 0usize
    while i < f.count {
        let c = &f.components[i]
        if !dec.quant_present[c.quant] { ret (zero, Invalid) }
        let stride = c.blocks_w * 8usize
        let (plane, plane_error) = mem.alloc[u8](a, stride * c.blocks_h * 8usize)
        if plane_error != ok { ret (zero, plane_error) }
        var by = 0usize
        while by < c.blocks_h {
            var bx = 0usize
            while bx < c.blocks_w {
                idct_block(c.coefficients, (by * c.blocks_w + bx) * 64usize, dec.quant[c.quant][0..], t[0..], plane, by * 8usize * stride + bx * 8usize, stride)
                bx += 1usize
            }
            by += 1usize
        }
        c.plane = plane
        c.plane_w = stride
        c.plane_h = c.blocks_h * 8usize
        i += 1usize
    }
    let info = info_of(*f)
    let (out, out_error) = image.allocate(a, info.width, info.height, info.format, .Opaque)
    if out_error != ok { ret (zero, out_error) }
    let rgb_direct = f.count == 3usize && ((f.has_adobe && f.adobe_transform == 0u32) || (!f.has_adobe && f.components[0].id == 82u32 && f.components[1].id == 71u32 && f.components[2].id == 66u32))
    var y = 0usize
    while y < f.height {
        var x = 0usize
        while x < f.width {
            let at = y * out.stride + x * image.bytes_per_pixel(info.format)
            if f.count == 1usize {
                out.pixels[at] = u8(i32(sample_plane(&f.components[0], x, y, f.hmax / f.components[0].h, f.vmax / f.components[0].v) + 0.5))
            } else {
                let c0 = sample_plane(&f.components[0], x, y, f.hmax / f.components[0].h, f.vmax / f.components[0].v)
                let c1 = sample_plane(&f.components[1], x, y, f.hmax / f.components[1].h, f.vmax / f.components[1].v)
                let c2 = sample_plane(&f.components[2], x, y, f.hmax / f.components[2].h, f.vmax / f.components[2].v)
                if rgb_direct {
                    out.pixels[at] = clamp_byte(c0)
                    out.pixels[at + 1usize] = clamp_byte(c1)
                    out.pixels[at + 2usize] = clamp_byte(c2)
                } else {
                    out.pixels[at] = clamp_byte(c0 + 1.402 * (c2 - 128.0))
                    out.pixels[at + 1usize] = clamp_byte(c0 - 0.344136 * (c1 - 128.0) - 0.714136 * (c2 - 128.0))
                    out.pixels[at + 2usize] = clamp_byte(c0 + 1.772 * (c1 - 128.0))
                }
                out.pixels[at + 3usize] = 255u8
            }
            x += 1usize
        }
        y += 1usize
    }
    ret (out, ok)
}

// Continues the marker walk from `dec.at` after a scan's entropy data.
fn parse_headers_from(dec: *Decoder) -> err {
    while true {
        while dec.at < dec.data.len && dec.data[dec.at] != 255u8 { dec.at += 1usize }
        while dec.at < dec.data.len && dec.data[dec.at] == 255u8 { dec.at += 1usize }
        if dec.at >= dec.data.len { ret Invalid }
        let marker = u32(dec.data[dec.at])
        dec.at += 1usize
        if marker == 217u32 || marker == 218u32 { ret ok }
        if marker >= 208u32 && marker <= 215u32 || marker == 0u32 { continue }
        if dec.at + 2usize > dec.data.len { ret Invalid }
        let length = u16_at(dec.data, dec.at)
        if length < 2usize || dec.at + length > dec.data.len { ret Invalid }
        let body = dec.data[dec.at + 2usize..dec.at + length]
        dec.at += length
        if marker == 219u32 {
            let dqt_error = parse_dqt(dec, body)
            if dqt_error != ok { ret dqt_error }
        } else if marker == 196u32 {
            let dht_error = parse_dht(dec, body)
            if dht_error != ok { ret dht_error }
        } else if marker == 221u32 {
            if body.len < 2usize { ret Invalid }
            dec.frame.restart_interval = u16_at(body, 0usize)
        } else if marker >= 192u32 && marker <= 207u32 && marker != 196u32 && marker != 200u32 {
            ret Unsupported
        }
    }
    ret Invalid
}

// ------------------------------------------------------------------ encoding

type Writer = struct { sink: *io.Writer, buffer: [4096]u8, filled: usize, cache: u32, count: u32 }

fn flush_bytes(w: *Writer) -> err {
    if w.filled == 0usize { ret ok }
    let write_error = io.write_all(w.sink, w.buffer[..w.filled])
    w.filled = 0usize
    ret write_error
}

fn put_byte(w: *Writer, b: u8) -> err {
    if w.filled >= w.buffer.len { try flush_bytes(w) }
    w.buffer[w.filled] = b
    w.filled += 1usize
    ret ok
}

fn put_bits(w: *Writer, value: u32, n: u32) -> err {
    if n == 0u32 { ret ok }
    w.cache = w.cache | ((value & ((1u32 << n) - 1u32)) << (32u32 - n - w.count))
    w.count += n
    while w.count >= 8u32 {
        let b = u8(w.cache >> 24u32)
        try put_byte(w, b)
        if b == 255u8 { try put_byte(w, 0u8) }
        w.cache = w.cache << 8u32
        w.count -= 8u32
    }
    ret ok
}

fn put_marker(w: *Writer, marker: u8, body: []const u8) -> err {
    try put_byte(w, 255u8)
    try put_byte(w, marker)
    if body.len > 0usize {
        try put_byte(w, u8((body.len + 2usize) >> 8u32))
        try put_byte(w, u8((body.len + 2usize) & 255usize))
        var i = 0usize
        while i < body.len {
            try put_byte(w, body[i])
            i += 1usize
        }
    }
    ret ok
}

// Codes and lengths per symbol from a BITS/HUFFVAL pair (Annex C).
type Codes = struct { code: [256]u32, size: [256]u32 }

fn codes_of(bits: str, values: str) -> Codes {
    var c: Codes = zero
    var code = 0u32
    var k = 0usize
    var length = 1u32
    while length <= 16u32 {
        var n = usize(bits[usize(length) - 1usize])
        while n > 0usize {
            c.code[usize(values[k])] = code
            c.size[usize(values[k])] = length
            code += 1u32
            k += 1usize
            n -= 1usize
        }
        code = code << 1u32
        length += 1u32
    }
    ret c
}

fn scaled_quant(base: str, quality: u8, out: []u8) {
    var q = u32(quality)
    if q == 0u32 { q = 1u32 }
    if q > 100u32 { q = 100u32 }
    var scale = 200u32 - 2u32 * q
    if q < 50u32 { scale = 5000u32 / q }
    var i = 0usize
    while i < 64usize {
        var v = (u32(base[i]) * scale + 50u32) / 100u32
        if v < 1u32 { v = 1u32 }
        if v > 255u32 { v = 255u32 }
        out[i] = u8(v)
        i += 1usize
    }
}

fn magnitude_bits(v: i32) -> u32 {
    var m = v
    if m < 0i32 { m = 0i32 - m }
    var n = 0u32
    while m > 0i32 {
        n += 1u32
        m = m >> 1u32
    }
    ret n
}

fn encode_block(w: *Writer, samples: []const f32, quant: []const u8, t: []const f32, dc: *const Codes, ac: *const Codes, predictor: *i32) -> err {
    // Forward DCT: F[v][u] = sum_y sum_x t[v][y] t[u][x] s[y][x] (the table already
    // carries c(u)/2), then quantise in zigzag order.
    var tmp: [64]f32 = zero
    var y = 0usize
    while y < 8usize {
        var u = 0usize
        while u < 8usize {
            var sum: f32 = 0.0
            var x = 0usize
            while x < 8usize {
                sum += t[u * 8usize + x] * samples[y * 8usize + x]
                x += 1usize
            }
            tmp[y * 8usize + u] = sum
            u += 1usize
        }
        y += 1usize
    }
    var q: [64]i32 = zero
    var v = 0usize
    while v < 8usize {
        var u = 0usize
        while u < 8usize {
            var sum: f32 = 0.0
            y = 0usize
            while y < 8usize {
                sum += t[v * 8usize + y] * tmp[y * 8usize + u]
                y += 1usize
            }
            q[v * 8usize + u] = i32(sum / f32(quant[v * 8usize + u]) + 1024.5) - 1024i32
            u += 1usize
        }
        v += 1usize
    }
    // DC difference, then the AC run-lengths in zigzag order.
    let diff = q[0] - *predictor
    *predictor = q[0]
    let dc_bits = magnitude_bits(diff)
    try put_bits(w, dc.code[usize(dc_bits)], dc.size[usize(dc_bits)])
    if dc_bits > 0u32 {
        var value = diff
        if diff < 0i32 { value = diff - 1i32 }
        try put_bits(w, u32(value & ((1i32 << dc_bits) - 1i32)), dc_bits)
    }
    var run = 0u32
    var k = 1usize
    while k < 64usize {
        let coef = q[zz(k)]
        if coef == 0i32 {
            run += 1u32
        } else {
            while run >= 16u32 {
                try put_bits(w, ac.code[240], ac.size[240])
                run -= 16u32
            }
            let bits = magnitude_bits(coef)
            let symbol = usize((run << 4u32) | bits)
            try put_bits(w, ac.code[symbol], ac.size[symbol])
            var value = coef
            if coef < 0i32 { value = coef - 1i32 }
            try put_bits(w, u32(value & ((1i32 << bits) - 1i32)), bits)
            run = 0u32
        }
        k += 1usize
    }
    if run > 0u32 { try put_bits(w, ac.code[0], ac.size[0]) }
    ret ok
}

// The 8x8 block of one channel at (bx, by), edge pixels repeated past the image.
fn gather(value: image.ConstImage, channel: usize, bx: usize, by: usize, out: []f32) {
    let bpp = image.bytes_per_pixel(value.format)
    var y = 0usize
    while y < 8usize {
        var py = by * 8usize + y
        if py >= usize(value.height) { py = usize(value.height) - 1usize }
        var x = 0usize
        while x < 8usize {
            var px = bx * 8usize + x
            if px >= usize(value.width) { px = usize(value.width) - 1usize }
            let at = py * value.stride + px * bpp
            var v: f32 = 0.0
            if channel == 3usize {
                v = f32(value.pixels[at])
            } else {
                var r = f32(value.pixels[at])
                var g = f32(value.pixels[at + 1usize])
                var b = f32(value.pixels[at + 2usize])
                if value.format == .Bgra8 {
                    let swap = r
                    r = b
                    b = swap
                }
                if channel == 0usize { v = 0.299 * r + 0.587 * g + 0.114 * b }
                if channel == 1usize { v = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b }
                if channel == 2usize { v = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b }
            }
            out[y * 8usize + x] = v - 128.0
            x += 1usize
        }
        y += 1usize
    }
}

fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err {
    if options.progressive { ret Unsupported }
    if value.format == .Rgba16Float { ret Unsupported }
    if value.width == 0u32 || value.height == 0u32 || value.width > 65535u32 || value.height > 65535u32 { ret Invalid }
    let (_, size_error) = image.required_bytes(value.width, value.height, value.format, value.stride)
    if size_error != ok { ret Invalid }
    var grey = value.format == .R8
    var w: Writer = zero
    w.sink = writer
    try put_marker(&w, 216u8, w.buffer[0..0usize])
    var jfif: [14]u8 = [14]u8{ 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0 }
    try put_marker(&w, 224u8, jfif[0..])
    var quant: [130]u8 = zero
    quant[0] = 0u8
    scaled_quant(luma_quant(), options.quality, quant[1usize..65usize])
    quant[65] = 1u8
    scaled_quant(chroma_quant(), options.quality, quant[66usize..130usize])
    var luma_zz: [64]u8 = zero
    var chroma_zz: [64]u8 = zero
    var i = 0usize
    while i < 64usize {
        luma_zz[i] = quant[1usize + zz(i)]
        chroma_zz[i] = quant[66usize + zz(i)]
        i += 1usize
    }
    var dqt: [130]u8 = zero
    dqt[0] = 0u8
    dqt[65] = 1u8
    mem.copy[u8](dqt[1usize..65usize], luma_zz[0..])
    mem.copy[u8](dqt[66usize..130usize], chroma_zz[0..])
    if grey { try put_marker(&w, 219u8, dqt[0usize..65usize]) } else { try put_marker(&w, 219u8, dqt[0..]) }
    var sof: [15]u8 = zero
    sof[0] = 8u8
    sof[1] = u8(value.height >> 8u32)
    sof[2] = u8(value.height & 255u32)
    sof[3] = u8(value.width >> 8u32)
    sof[4] = u8(value.width & 255u32)
    sof[5] = 3u8
    sof[6] = 1u8
    sof[7] = 17u8
    sof[8] = 0u8
    sof[9] = 2u8
    sof[10] = 17u8
    sof[11] = 1u8
    sof[12] = 3u8
    sof[13] = 17u8
    sof[14] = 1u8
    if grey {
        sof[5] = 1u8
        try put_marker(&w, 192u8, sof[0usize..9usize])
    } else {
        try put_marker(&w, 192u8, sof[0..])
    }
    try put_huffman(&w, 0u8, dc_luma_bits(), dc_luma_values())
    try put_huffman(&w, 16u8, ac_luma_bits(), ac_luma_values())
    if !grey {
        try put_huffman(&w, 1u8, dc_chroma_bits(), dc_chroma_values())
        try put_huffman(&w, 17u8, ac_chroma_bits(), ac_chroma_values())
    }
    var sos: [10]u8 = [10]u8{ 3, 1, 0, 2, 17, 3, 17, 0, 63, 0 }
    if grey {
        var sos_grey: [6]u8 = [6]u8{ 1, 1, 0, 0, 63, 0 }
        try put_marker(&w, 218u8, sos_grey[0..])
    } else {
        try put_marker(&w, 218u8, sos[0..])
    }
    var t: [64]f32 = zero
    cos_table(t[0..])
    let dc_l = codes_of(dc_luma_bits(), dc_luma_values())
    let ac_l = codes_of(ac_luma_bits(), ac_luma_values())
    let dc_c = codes_of(dc_chroma_bits(), dc_chroma_values())
    let ac_c = codes_of(ac_chroma_bits(), ac_chroma_values())
    var predictors: [3]i32 = zero
    var samples: [64]f32 = zero
    let bw = (usize(value.width) + 7usize) / 8usize
    let bh = (usize(value.height) + 7usize) / 8usize
    var by = 0usize
    while by < bh {
        var bx = 0usize
        while bx < bw {
            if grey {
                gather(value, 3usize, bx, by, samples[0..])
                try encode_block(&w, samples[0..], quant[1usize..65usize], t[0..], &dc_l, &ac_l, &predictors[0])
            } else {
                gather(value, 0usize, bx, by, samples[0..])
                try encode_block(&w, samples[0..], quant[1usize..65usize], t[0..], &dc_l, &ac_l, &predictors[0])
                gather(value, 1usize, bx, by, samples[0..])
                try encode_block(&w, samples[0..], quant[66usize..130usize], t[0..], &dc_c, &ac_c, &predictors[1])
                gather(value, 2usize, bx, by, samples[0..])
                try encode_block(&w, samples[0..], quant[66usize..130usize], t[0..], &dc_c, &ac_c, &predictors[2])
            }
            bx += 1usize
        }
        by += 1usize
    }
    if w.count > 0u32 { try put_bits(&w, 127u32, 8u32 - w.count) }
    try put_marker(&w, 217u8, w.buffer[0..0usize])
    ret flush_bytes(&w)
}

fn put_huffman(w: *Writer, class_id: u8, bits: str, values: str) -> err {
    var body: [273]u8 = zero
    body[0] = class_id
    mem.copy[u8](body[1usize..17usize], bits)
    mem.copy[u8](body[17usize..17usize + values.len], values)
    ret put_marker(w, 196u8, body[..17usize + values.len])
}
