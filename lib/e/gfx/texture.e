// Compressed texture blocks decoded into caller RGBA8 storage, row-major, four
// bytes a texel. `bc_decode` takes one block of the S3TC family: `Bc1` (8 bytes,
// two RGB565 end points and 2-bit indices, the four-colour or the three-colour-
// and-transparent palette by the end-point order), `Bc3` (16 bytes: an 8-bit
// alpha ramp block, then a colour block always read as four colours), `Bc4`
// (8 bytes, one ramp block into red) and `Bc5` (16 bytes, two ramps into red and
// green). Palette and ramp interpolants are rounded to nearest, which the
// specifications leave to the implementation. Signed BC4/BC5 and BC6/BC7 are not
// here.
//
// `astc_decode` is the LDR profile of ASTC for 2-d blocks of any footprint from
// 4x4 to 12x12: block mode, void extent, the partition hash, the integer
// sequence encoding with trits and quints, the ten LDR colour end-point modes
// (0, 1, 4, 5, 6, 8, 9, 10, 12, 13), dual planes and weight-grid infill; each
// texel is the 16-bit interpolation of the expanded end points, kept as its top
// eight bits, which is what `astcenc` answers for 8-bit output. `srgb` expands
// the colour end points the sRGB way (`c << 8 | 0x80`). An HDR end-point mode
// answers `Unsupported`; a block the specification marks as an error answers
// `Invalid`, and the caller paints the error colour it wants.
//
// ponytail: LDR 2-d only. HDR end-point modes (2, 3, 7, 11, 14, 15), 3-d
// footprints, signed BC4/BC5 and BC6H/BC7 are the ceiling; each is a separate
// decoder path on the same bit readers.

type Format = enum u8 { Bc1, Bc3, Bc4, Bc5 }
error Invalid
error TooSmall
error Unsupported

// ---- S3TC ------------------------------------------------------------------

fn nearest_third(x: u32) -> u32 { ret (2u32 * x + 3u32) / 6u32 }

fn put4(out: []u8, at: usize, r: u32, g: u32, b: u32, a: u32) {
    out[at] = u8(r & 255u32)
    out[at + 1usize] = u8(g & 255u32)
    out[at + 2usize] = u8(b & 255u32)
    out[at + 3usize] = u8(a & 255u32)
}

fn expand565(c: u32) -> (u32, u32, u32) {
    let r5 = (c >> 11u32) & 31u32
    let g6 = (c >> 5u32) & 63u32
    let b5 = c & 31u32
    ret ((r5 << 3u32) | (r5 >> 2u32), (g6 << 2u32) | (g6 >> 4u32), (b5 << 3u32) | (b5 >> 2u32))
}

// The colour block at `at`: `four` forces the four-colour palette (BC3).
fn bc_colors(block: []const u8, at: usize, four: bool, out: []u8) {
    let c0 = u32(block[at]) | (u32(block[at + 1usize]) << 8u32)
    let c1 = u32(block[at + 2usize]) | (u32(block[at + 3usize]) << 8u32)
    let (r0, g0, b0) = expand565(c0)
    let (r1, g1, b1) = expand565(c1)
    var palette: [16]u32 = zero
    palette[0] = r0
    palette[1] = g0
    palette[2] = b0
    palette[3] = 255u32
    palette[4] = r1
    palette[5] = g1
    palette[6] = b1
    palette[7] = 255u32
    if four || c0 > c1 {
        palette[8] = nearest_third(2u32 * r0 + r1)
        palette[9] = nearest_third(2u32 * g0 + g1)
        palette[10] = nearest_third(2u32 * b0 + b1)
        palette[11] = 255u32
        palette[12] = nearest_third(r0 + 2u32 * r1)
        palette[13] = nearest_third(g0 + 2u32 * g1)
        palette[14] = nearest_third(b0 + 2u32 * b1)
        palette[15] = 255u32
    } else {
        palette[8] = (r0 + r1 + 1u32) / 2u32
        palette[9] = (g0 + g1 + 1u32) / 2u32
        palette[10] = (b0 + b1 + 1u32) / 2u32
        palette[11] = 255u32
    }
    var i = 0usize
    while i < 16usize {
        let index = usize((u32(block[at + 4usize + i / 4usize]) >> u32(2usize * (i % 4usize))) & 3u32)
        put4(out, i * 4usize, palette[index * 4usize], palette[index * 4usize + 1usize], palette[index * 4usize + 2usize], palette[index * 4usize + 3usize])
        i += 1usize
    }
}

// The 8-byte ramp block at `at` into byte `channel` of every texel.
fn bc_ramp(block: []const u8, at: usize, channel: usize, out: []u8) {
    let a0 = u32(block[at])
    let a1 = u32(block[at + 1usize])
    var ramp: [8]u32 = zero
    ramp[0] = a0
    ramp[1] = a1
    if a0 > a1 {
        var i = 1u32
        while i <= 6u32 {
            ramp[usize(i + 1u32)] = (2u32 * ((7u32 - i) * a0 + i * a1) + 7u32) / 14u32
            i += 1u32
        }
    } else {
        var i = 1u32
        while i <= 4u32 {
            ramp[usize(i + 1u32)] = (2u32 * ((5u32 - i) * a0 + i * a1) + 5u32) / 10u32
            i += 1u32
        }
        ramp[6] = 0u32
        ramp[7] = 255u32
    }
    var bits = 0u64
    var i = 0usize
    while i < 6usize {
        bits |= u64(block[at + 2usize + i]) << u32(8usize * i)
        i += 1usize
    }
    i = 0usize
    while i < 16usize {
        let index = usize((bits >> u32(3usize * i)) & 7u64)
        out[i * 4usize + channel] = u8(ramp[index] & 255u32)
        i += 1usize
    }
}

fn bc_decode(block: []const u8, format: Format, out: []u8) -> err {
    if out.len < 64usize { ret TooSmall }
    var needed = 8usize
    if format == .Bc3 || format == .Bc5 { needed = 16usize }
    if block.len < needed { ret Invalid }
    if format == .Bc1 {
        bc_colors(block, 0usize, false, out)
    } else if format == .Bc3 {
        bc_colors(block, 8usize, true, out)
        bc_ramp(block, 0usize, 3usize, out)
    } else {
        var i = 0usize
        while i < 16usize {
            put4(out, i * 4usize, 0u32, 0u32, 0u32, 255u32)
            i += 1usize
        }
        bc_ramp(block, 0usize, 0usize, out)
        if format == .Bc5 { bc_ramp(block, 8usize, 1usize, out) }
    }
    ret ok
}

// ---- ASTC ------------------------------------------------------------------

// Quantisation levels by index: bits, whether a trit or a quint rides along.
fn quant_bits(q: usize) -> u32 {
    let table: [21]u8 = [21]u8{ 1, 0, 2, 0, 1, 3, 1, 2, 4, 2, 3, 5, 3, 4, 6, 4, 5, 7, 5, 6, 8 }
    ret u32(table[q])
}

fn quant_trit(q: usize) -> bool {
    let table: [21]u8 = [21]u8{ 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0 }
    ret table[q] != 0u8
}

fn quant_quint(q: usize) -> bool {
    let table: [21]u8 = [21]u8{ 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0 }
    ret table[q] != 0u8
}

fn ise_bits(n: usize, q: usize) -> usize {
    var total = n * usize(quant_bits(q))
    if quant_trit(q) { total += (8usize * n + 4usize) / 5usize }
    if quant_quint(q) { total += (7usize * n + 2usize) / 3usize }
    ret total
}

fn bit_at(block: []const u8, i: usize) -> u32 {
    ret (u32(block[i / 8usize]) >> u32(i % 8usize)) & 1u32
}

fn field(block: []const u8, lo: usize, n: usize) -> u32 {
    var v = 0u32
    var i = 0usize
    while i < n {
        v |= bit_at(block, lo + i) << u32(i)
        i += 1usize
    }
    ret v
}

// Bit `i` of a sequence that starts at block bit `base`, `limit` bits long
// (zero beyond it), read upward or, for weights, downward from bit 127.
fn seq_bit(block: []const u8, base: usize, limit: usize, reversed: bool, i: usize) -> u32 {
    if i >= limit { ret 0u32 }
    if reversed { ret bit_at(block, 127usize - (base + i)) }
    ret bit_at(block, base + i)
}

fn seq_bits(block: []const u8, base: usize, limit: usize, reversed: bool, pos: usize, n: u32) -> u32 {
    var v = 0u32
    var i = 0u32
    while i < n {
        v |= seq_bit(block, base, limit, reversed, pos + usize(i)) << i
        i += 1u32
    }
    ret v
}

fn trits_of(t: u32, out: []u32) {
    var c = 0u32
    var t3 = 0u32
    var t4 = 0u32
    if ((t >> 2u32) & 7u32) == 7u32 {
        c = (((t >> 5u32) & 7u32) << 2u32) | (t & 3u32)
        t4 = 2u32
        t3 = 2u32
    } else {
        c = t & 31u32
        if ((t >> 5u32) & 3u32) == 3u32 {
            t4 = 2u32
            t3 = (t >> 7u32) & 1u32
        } else {
            t4 = (t >> 7u32) & 1u32
            t3 = (t >> 5u32) & 3u32
        }
    }
    if (c & 3u32) == 3u32 {
        out[2] = 2u32
        out[1] = (c >> 4u32) & 1u32
        out[0] = (((c >> 3u32) & 1u32) << 1u32) | (((c >> 2u32) & 1u32) & (~(c >> 3u32) & 1u32))
    } else if ((c >> 2u32) & 3u32) == 3u32 {
        out[2] = 2u32
        out[1] = 2u32
        out[0] = c & 3u32
    } else {
        out[2] = (c >> 4u32) & 1u32
        out[1] = (c >> 2u32) & 3u32
        out[0] = (((c >> 1u32) & 1u32) << 1u32) | ((c & 1u32) & (~(c >> 1u32) & 1u32))
    }
    out[3] = t3
    out[4] = t4
}

fn quints_of(q: u32, out: []u32) {
    if ((q >> 1u32) & 3u32) == 3u32 && ((q >> 5u32) & 3u32) == 0u32 {
        let q0 = q & 1u32
        out[2] = (q0 << 2u32) | ((((q >> 4u32) & 1u32) & (~q0 & 1u32)) << 1u32) | (((q >> 3u32) & 1u32) & (~q0 & 1u32))
        out[1] = 4u32
        out[0] = 4u32
        ret
    }
    var c = 0u32
    if ((q >> 1u32) & 3u32) == 3u32 {
        out[2] = 4u32
        c = (((q >> 3u32) & 3u32) << 3u32) | ((~(q >> 5u32) & 3u32) << 1u32) | (q & 1u32)
    } else {
        out[2] = (q >> 5u32) & 3u32
        c = q & 31u32
    }
    if (c & 7u32) == 5u32 {
        out[1] = 4u32
        out[0] = (c >> 3u32) & 3u32
    } else {
        out[1] = (c >> 3u32) & 3u32
        out[0] = c & 7u32
    }
}

// Decodes `n` values of quantisation `q`: the plain bits into `values`, the trit
// or quint (zero without one) into `extras`.
fn ise_decode(block: []const u8, base: usize, limit: usize, reversed: bool, n: usize, q: usize, values: []u32, extras: []u32) {
    let b = quant_bits(q)
    var pos = 0usize
    var done = 0usize
    if quant_trit(q) {
        while done < n {
            var vals: [5]u32 = zero
            var t = 0u32
            vals[0] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            t |= seq_bits(block, base, limit, reversed, pos, 2u32)
            pos += 2usize
            vals[1] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            t |= seq_bits(block, base, limit, reversed, pos, 2u32) << 2u32
            pos += 2usize
            vals[2] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            t |= seq_bits(block, base, limit, reversed, pos, 1u32) << 4u32
            pos += 1usize
            vals[3] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            t |= seq_bits(block, base, limit, reversed, pos, 2u32) << 5u32
            pos += 2usize
            vals[4] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            t |= seq_bits(block, base, limit, reversed, pos, 1u32) << 7u32
            pos += 1usize
            var ts: [5]u32 = zero
            trits_of(t, ts[..])
            var i = 0usize
            while i < 5usize && done < n {
                values[done] = vals[i]
                extras[done] = ts[i]
                done += 1usize
                i += 1usize
            }
        }
    } else if quant_quint(q) {
        while done < n {
            var vals: [3]u32 = zero
            var qb = 0u32
            vals[0] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            qb |= seq_bits(block, base, limit, reversed, pos, 3u32)
            pos += 3usize
            vals[1] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            qb |= seq_bits(block, base, limit, reversed, pos, 2u32) << 3u32
            pos += 2usize
            vals[2] = seq_bits(block, base, limit, reversed, pos, b)
            pos += usize(b)
            qb |= seq_bits(block, base, limit, reversed, pos, 2u32) << 5u32
            pos += 2usize
            var qs: [3]u32 = zero
            quints_of(qb, qs[..])
            var i = 0usize
            while i < 3usize && done < n {
                values[done] = vals[i]
                extras[done] = qs[i]
                done += 1usize
                i += 1usize
            }
        }
    } else {
        while done < n {
            values[done] = seq_bits(block, base, limit, reversed, pos, b)
            extras[done] = 0u32
            pos += usize(b)
            done += 1usize
        }
    }
}

fn replicate(v: u32, bits: u32, width: u32) -> u32 {
    var r = 0u32
    var shift = i32(width)
    while shift > 0i32 {
        shift -= i32(bits)
        if shift >= 0i32 {
            r |= v << u32(shift)
        } else {
            r |= v >> u32(0i32 - shift)
        }
    }
    ret r & ((1u32 << width) - 1u32)
}

fn bit_of(v: u32, i: u32) -> u32 { ret (v >> i) & 1u32 }

fn unquant_color(v: u32, extra: u32, q: usize) -> u32 {
    let b = quant_bits(q)
    if !quant_trit(q) && !quant_quint(q) { ret replicate(v, b, 8u32) }
    let a = bit_of(v, 0u32)
    let bb = bit_of(v, 1u32)
    let c = bit_of(v, 2u32)
    let d = bit_of(v, 3u32)
    let e = bit_of(v, 4u32)
    let f = bit_of(v, 5u32)
    var big_a = 0u32
    if a != 0u32 { big_a = 511u32 }
    var big_b = 0u32
    var big_c = 0u32
    if quant_trit(q) {
        if b == 1u32 {
            big_c = 204u32
        } else if b == 2u32 {
            big_c = 93u32
            big_b = (bb << 8u32) | (bb << 4u32) | (bb << 2u32) | (bb << 1u32)
        } else if b == 3u32 {
            big_c = 44u32
            big_b = (c << 8u32) | (bb << 7u32) | (c << 3u32) | (bb << 2u32) | (c << 1u32) | bb
        } else if b == 4u32 {
            big_c = 22u32
            big_b = (d << 8u32) | (c << 7u32) | (bb << 6u32) | (d << 2u32) | (c << 1u32) | bb
        } else if b == 5u32 {
            big_c = 11u32
            big_b = (e << 8u32) | (d << 7u32) | (c << 6u32) | (bb << 5u32) | (e << 1u32) | d
        } else {
            big_c = 5u32
            big_b = (f << 8u32) | (e << 7u32) | (d << 6u32) | (c << 5u32) | (bb << 4u32) | f
        }
    } else {
        if b == 1u32 {
            big_c = 113u32
        } else if b == 2u32 {
            big_c = 54u32
            big_b = (bb << 8u32) | (bb << 3u32) | (bb << 2u32)
        } else if b == 3u32 {
            big_c = 26u32
            big_b = (c << 8u32) | (bb << 7u32) | (c << 2u32) | (bb << 1u32) | c
        } else if b == 4u32 {
            big_c = 13u32
            big_b = (d << 8u32) | (c << 7u32) | (bb << 6u32) | (d << 1u32) | c
        } else {
            big_c = 6u32
            big_b = (e << 8u32) | (d << 7u32) | (c << 6u32) | (bb << 5u32) | e
        }
    }
    var t = extra * big_c + big_b
    t ^= big_a
    ret (big_a & 128u32) | (t >> 2u32)
}

fn unquant_weight(v: u32, extra: u32, q: usize) -> u32 {
    let b = quant_bits(q)
    var r = 0u32
    if !quant_trit(q) && !quant_quint(q) {
        if b == 1u32 {
            r = v * 63u32
        } else if b == 2u32 {
            r = v * 21u32
        } else if b == 3u32 {
            r = v * 9u32
        } else if b == 4u32 {
            r = (v << 2u32) | (v >> 2u32)
        } else {
            r = (v << 1u32) | (v >> 4u32)
        }
    } else if b == 0u32 {
        if quant_trit(q) {
            let table: [3]u8 = [3]u8{ 0, 32, 63 }
            r = u32(table[usize(extra)])
        } else {
            let table: [5]u8 = [5]u8{ 0, 16, 32, 47, 63 }
            r = u32(table[usize(extra)])
        }
    } else {
        let a = bit_of(v, 0u32)
        let bb = bit_of(v, 1u32)
        let c = bit_of(v, 2u32)
        var big_a = 0u32
        if a != 0u32 { big_a = 127u32 }
        var big_b = 0u32
        var big_c = 0u32
        if quant_trit(q) {
            if b == 1u32 {
                big_c = 50u32
            } else if b == 2u32 {
                big_c = 23u32
                big_b = (bb << 6u32) | (bb << 2u32) | bb
            } else {
                big_c = 11u32
                big_b = (c << 6u32) | (bb << 5u32) | (c << 1u32) | bb
            }
        } else {
            if b == 1u32 {
                big_c = 28u32
            } else {
                big_c = 16u32
                big_b = (bb << 6u32) | (bb << 1u32)
            }
        }
        var t = extra * big_c + big_b
        t ^= big_a
        r = (big_a & 32u32) | (t >> 2u32)
    }
    if r > 32u32 { r += 1u32 }
    ret r
}

fn hash52(seed: u32) -> u32 {
    var p = seed
    p ^= p >> 15u32
    p -%= p << 17u32
    p +%= p << 7u32
    p +%= p << 4u32
    p ^= p >> 5u32
    p +%= p << 16u32
    p ^= p >> 7u32
    p ^= p >> 3u32
    p ^= p << 6u32
    p ^= p >> 17u32
    ret p
}

fn select_partition(index: u32, x0: u32, y0: u32, count: u32, small: bool) -> u32 {
    var x = x0
    var y = y0
    if small {
        x <<= 1u32
        y <<= 1u32
    }
    let seed = index + (count - 1u32) * 1024u32
    let rnum = hash52(seed)
    // Only the eight seeds the two planar axes use; the four for `z` are dropped.
    var s: [8]u32 = zero
    var i = 0usize
    while i < 8usize {
        let v = (rnum >> u32(4usize * i)) & 15u32
        s[i] = v * v
        i += 1usize
    }
    var sh1 = 5u32
    var sh2 = 5u32
    if (seed & 1u32) != 0u32 {
        if (seed & 2u32) != 0u32 { sh1 = 4u32 }
        if count == 3u32 { sh2 = 6u32 }
    } else {
        if count == 3u32 { sh1 = 6u32 }
        if (seed & 2u32) != 0u32 { sh2 = 4u32 }
    }
    s[0] >>= sh1
    s[1] >>= sh2
    s[2] >>= sh1
    s[3] >>= sh2
    s[4] >>= sh1
    s[5] >>= sh2
    s[6] >>= sh1
    s[7] >>= sh2
    let a = (s[0] * x + s[1] * y + (rnum >> 14u32)) & 63u32
    let b = (s[2] * x + s[3] * y + (rnum >> 10u32)) & 63u32
    var c = (s[4] * x + s[5] * y + (rnum >> 6u32)) & 63u32
    var d = (s[6] * x + s[7] * y + (rnum >> 2u32)) & 63u32
    if count < 4u32 { d = 0u32 }
    if count < 3u32 { c = 0u32 }
    if a >= b && a >= c && a >= d { ret 0u32 }
    if b >= c && b >= d { ret 1u32 }
    if c >= d { ret 2u32 }
    ret 3u32
}

// The block mode: kind 0 is an error, 1 a void extent, 2 a weight grid of
// `w` x `h` at quantisation `q` with `dual` planes.
fn block_mode(m: u32) -> (u32, usize, usize, usize, bool) {
    if (m & 511u32) == 508u32 { ret (1u32, 0usize, 0usize, 0usize, false) }
    if ((m >> 7u32) & 3u32) == 3u32 && ((m >> 6u32) & 1u32) == 1u32 && (m & 3u32) == 0u32 { ret (0u32, 0usize, 0usize, 0usize, false) }
    var dual = ((m >> 10u32) & 1u32) != 0u32
    var high = ((m >> 9u32) & 1u32) != 0u32
    var r = 0u32
    var w = 0usize
    var h = 0usize
    let a = usize((m >> 5u32) & 3u32)
    if (m & 3u32) != 0u32 {
        r = ((m & 3u32) << 1u32) | ((m >> 4u32) & 1u32)
        let b = usize((m >> 7u32) & 3u32)
        let sel = (m >> 2u32) & 3u32
        if sel == 0u32 {
            w = b + 4usize
            h = a + 2usize
        } else if sel == 1u32 {
            w = b + 8usize
            h = a + 2usize
        } else if sel == 2u32 {
            w = a + 2usize
            h = b + 8usize
        } else {
            let b1 = usize((m >> 7u32) & 1u32)
            if ((m >> 8u32) & 1u32) == 0u32 {
                w = a + 2usize
                h = b1 + 6usize
            } else {
                w = b1 + 2usize
                h = a + 2usize
            }
        }
    } else {
        r = (((m >> 2u32) & 3u32) << 1u32) | ((m >> 4u32) & 1u32)
        if ((m >> 2u32) & 3u32) == 0u32 { ret (0u32, 0usize, 0usize, 0usize, false) }
        let sel = (m >> 7u32) & 3u32
        if sel == 0u32 {
            w = 12usize
            h = a + 2usize
        } else if sel == 1u32 {
            w = a + 2usize
            h = 12usize
        } else if sel == 3u32 {
            if a == 0usize {
                w = 6usize
                h = 10usize
            } else if a == 1usize {
                w = 10usize
                h = 6usize
            } else {
                ret (0u32, 0usize, 0usize, 0usize, false)
            }
        } else {
            let b = usize((m >> 9u32) & 3u32)
            w = a + 6usize
            h = b + 6usize
            dual = false
            high = false
        }
    }
    if r < 2u32 { ret (0u32, 0usize, 0usize, 0usize, false) }
    var q = usize(r - 2u32)
    if high { q += 6usize }
    ret (2u32, w, h, q, dual)
}

fn clamp8(v: i32) -> u32 {
    if v < 0i32 { ret 0u32 }
    if v > 255i32 { ret 255u32 }
    ret u32(v)
}

// `bit_transfer_signed(offset, base)`: `values[o]` becomes a signed offset, `values[b]` the base.
fn transfer(values: []i32, o: usize, b: usize) {
    var base = values[b]
    var offset = values[o]
    base >>= 1u32
    base |= offset & 128i32
    offset >>= 1u32
    offset &= 63i32
    if (offset & 32i32) != 0i32 { offset -= 64i32 }
    values[b] = base
    values[o] = offset
}

fn blue_contract(e: []i32, r: i32, g: i32, b: i32, a: i32) {
    e[0] = (r + b) >> 1u32
    e[1] = (g + b) >> 1u32
    e[2] = b
    e[3] = a
}

fn set4(e: []i32, r: i32, g: i32, b: i32, a: i32) {
    e[0] = r
    e[1] = g
    e[2] = b
    e[3] = a
}

// End points `e0`, `e1` (RGBA, 0..255) of colour mode `cem` from its unquantised values.
fn endpoints(cem: u32, v: []i32, e0: []i32, e1: []i32) -> err {
    if cem == 0u32 {
        set4(e0, v[0], v[0], v[0], 255i32)
        set4(e1, v[1], v[1], v[1], 255i32)
    } else if cem == 1u32 {
        let l0 = (v[0] >> 2u32) | (v[1] & 192i32)
        var l1 = l0 + (v[1] & 63i32)
        if l1 > 255i32 { l1 = 255i32 }
        set4(e0, l0, l0, l0, 255i32)
        set4(e1, l1, l1, l1, 255i32)
    } else if cem == 4u32 {
        set4(e0, v[0], v[0], v[0], v[2])
        set4(e1, v[1], v[1], v[1], v[3])
    } else if cem == 5u32 {
        transfer(v, 1usize, 0usize)
        transfer(v, 3usize, 2usize)
        let l1 = i32(clamp8(v[0] + v[1]))
        let a1 = i32(clamp8(v[2] + v[3]))
        set4(e0, i32(clamp8(v[0])), i32(clamp8(v[0])), i32(clamp8(v[0])), i32(clamp8(v[2])))
        set4(e1, l1, l1, l1, a1)
    } else if cem == 6u32 {
        set4(e0, (v[0] * v[3]) >> 8u32, (v[1] * v[3]) >> 8u32, (v[2] * v[3]) >> 8u32, 255i32)
        set4(e1, v[0], v[1], v[2], 255i32)
    } else if cem == 8u32 {
        if v[1] + v[3] + v[5] >= v[0] + v[2] + v[4] {
            set4(e0, v[0], v[2], v[4], 255i32)
            set4(e1, v[1], v[3], v[5], 255i32)
        } else {
            blue_contract(e0, v[1], v[3], v[5], 255i32)
            blue_contract(e1, v[0], v[2], v[4], 255i32)
        }
    } else if cem == 9u32 {
        transfer(v, 1usize, 0usize)
        transfer(v, 3usize, 2usize)
        transfer(v, 5usize, 4usize)
        if v[1] + v[3] + v[5] >= 0i32 {
            set4(e0, v[0], v[2], v[4], 255i32)
            set4(e1, v[0] + v[1], v[2] + v[3], v[4] + v[5], 255i32)
        } else {
            blue_contract(e0, v[0] + v[1], v[2] + v[3], v[4] + v[5], 255i32)
            blue_contract(e1, v[0], v[2], v[4], 255i32)
        }
        clamp_all(e0)
        clamp_all(e1)
    } else if cem == 10u32 {
        set4(e0, (v[0] * v[3]) >> 8u32, (v[1] * v[3]) >> 8u32, (v[2] * v[3]) >> 8u32, v[4])
        set4(e1, v[0], v[1], v[2], v[5])
    } else if cem == 12u32 {
        if v[1] + v[3] + v[5] >= v[0] + v[2] + v[4] {
            set4(e0, v[0], v[2], v[4], v[6])
            set4(e1, v[1], v[3], v[5], v[7])
        } else {
            blue_contract(e0, v[1], v[3], v[5], v[7])
            blue_contract(e1, v[0], v[2], v[4], v[6])
        }
    } else if cem == 13u32 {
        transfer(v, 1usize, 0usize)
        transfer(v, 3usize, 2usize)
        transfer(v, 5usize, 4usize)
        transfer(v, 7usize, 6usize)
        if v[1] + v[3] + v[5] >= 0i32 {
            set4(e0, v[0], v[2], v[4], v[6])
            set4(e1, v[0] + v[1], v[2] + v[3], v[4] + v[5], v[6] + v[7])
        } else {
            blue_contract(e0, v[0] + v[1], v[2] + v[3], v[4] + v[5], v[6] + v[7])
            blue_contract(e1, v[0], v[2], v[4], v[6])
        }
        clamp_all(e0)
        clamp_all(e1)
    } else {
        ret Unsupported
    }
    ret ok
}

fn clamp_all(e: []i32) {
    var i = 0usize
    while i < 4usize {
        e[i] = i32(clamp8(e[i]))
        i += 1usize
    }
}

fn astc_decode(block: []const u8, width: usize, height: usize, srgb: bool, out: []u8) -> err {
    if block.len < 16usize || width < 4usize || height < 4usize || width > 12usize || height > 12usize { ret Invalid }
    let texels = width * height
    if out.len < texels * 4usize { ret TooSmall }
    let m = field(block, 0usize, 11usize)
    let (kind, grid_w, grid_h, wq, dual) = block_mode(m)
    if kind == 0u32 { ret Invalid }
    if kind == 1u32 {
        let r = field(block, 64usize, 16usize) >> 8u32
        let g = field(block, 80usize, 16usize) >> 8u32
        let b = field(block, 96usize, 16usize) >> 8u32
        let a = field(block, 112usize, 16usize) >> 8u32
        var i = 0usize
        while i < texels {
            put4(out, i * 4usize, r, g, b, a)
            i += 1usize
        }
        ret ok
    }
    let parts = usize(field(block, 11usize, 2usize)) + 1usize
    if grid_w > width || grid_h > height { ret Invalid }
    var planes = 1usize
    if dual { planes = 2usize }
    let weight_count = grid_w * grid_h * planes
    if weight_count > 64usize { ret Invalid }
    let weight_bits = ise_bits(weight_count, wq)
    if weight_bits < 24usize || weight_bits > 96usize { ret Invalid }
    if dual && parts == 4usize { ret Invalid }
    var color_start = 17usize
    var index = 0u32
    var cems: [4]u32 = zero
    var extra = 0usize
    if parts == 1usize {
        cems[0] = field(block, 13usize, 4usize)
    } else {
        color_start = 29usize
        index = field(block, 13usize, 10usize)
        let cemf = field(block, 23usize, 6usize)
        if (cemf & 3u32) == 0u32 {
            var i = 0usize
            while i < parts {
                cems[i] = cemf >> 2u32
                i += 1usize
            }
        } else {
            extra = 3usize * parts - 4usize
            let base = (cemf & 3u32) - 1u32
            var seq: [12]u32 = zero
            var i = 0usize
            while i < 4usize {
                seq[i] = (cemf >> u32(2usize + i)) & 1u32
                i += 1usize
            }
            let lo = 128usize - weight_bits - extra
            i = 0usize
            while i < extra {
                seq[4usize + i] = bit_at(block, lo + i)
                i += 1usize
            }
            i = 0usize
            while i < parts {
                let class_bit = seq[i]
                let low = seq[parts + 2usize * i] | (seq[parts + 2usize * i + 1usize] << 1u32)
                cems[i] = ((base + class_bit) << 2u32) | low
                i += 1usize
            }
        }
    }
    var ccs = 0usize
    var ccs_bits = 0usize
    if dual {
        ccs_bits = 2usize
        ccs = usize(field(block, 128usize - weight_bits - extra - 2usize, 2usize))
    }
    var value_count = 0usize
    var i = 0usize
    while i < parts {
        value_count += 2usize * (usize(cems[i] >> 2u32) + 1usize)
        i += 1usize
    }
    if value_count > 18usize { ret Invalid }
    let available = 128usize - weight_bits - extra - ccs_bits - color_start
    var cq = 21usize
    var found = false
    while cq > 4usize && !found {
        cq -= 1usize
        if ise_bits(value_count, cq) <= available { found = true }
    }
    if !found { ret Invalid }
    let color_bits = ise_bits(value_count, cq)
    var raw: [18]u32 = zero
    var raw_extra: [18]u32 = zero
    ise_decode(block, color_start, color_bits, false, value_count, cq, raw[..], raw_extra[..])
    var values: [18]i32 = zero
    i = 0usize
    while i < value_count {
        values[i] = i32(unquant_color(raw[i], raw_extra[i], cq))
        i += 1usize
    }
    var e0: [16]i32 = zero
    var e1: [16]i32 = zero
    var at = 0usize
    i = 0usize
    while i < parts {
        let n = 2usize * (usize(cems[i] >> 2u32) + 1usize)
        let endpoint_error = endpoints(cems[i], values[at..at + n], e0[4usize * i..4usize * i + 4usize], e1[4usize * i..4usize * i + 4usize])
        if endpoint_error != ok { ret endpoint_error }
        at += n
        i += 1usize
    }
    var weight_raw: [64]u32 = zero
    var weight_extra: [64]u32 = zero
    ise_decode(block, 0usize, weight_bits, true, weight_count, wq, weight_raw[..], weight_extra[..])
    var weights: [64]u32 = zero
    i = 0usize
    while i < weight_count {
        weights[i] = unquant_weight(weight_raw[i], weight_extra[i], wq)
        i += 1usize
    }
    let small = texels < 31usize
    let ds = (1024usize + width / 2usize) / (width - 1usize)
    let dt = (1024usize + height / 2usize) / (height - 1usize)
    var t = 0usize
    while t < height {
        var s = 0usize
        while s < width {
            var p = 0usize
            if parts > 1usize { p = usize(select_partition(index, u32(s), u32(t), u32(parts), small)) }
            let gs = (ds * s * (grid_w - 1usize) + 32usize) >> 6u32
            let gt = (dt * t * (grid_h - 1usize) + 32usize) >> 6u32
            let js = gs >> 4u32
            let fs = gs & 15usize
            let jt = gt >> 4u32
            let ft = gt & 15usize
            let v0 = js + jt * grid_w
            let w11 = (fs * ft + 8usize) >> 4u32
            let w10 = ft - w11
            let w01 = fs - w11
            let w00 = 16usize + w11 - fs - ft
            var wa = infill(weights[..], weight_count, planes, 0usize, v0, grid_w, w00, w01, w10, w11)
            var wb = wa
            if dual { wb = infill(weights[..], weight_count, planes, 1usize, v0, grid_w, w00, w01, w10, w11) }
            var channel = 0usize
            while channel < 4usize {
                var w = wa
                if dual && channel == ccs { w = wb }
                var c0 = u32(e0[4usize * p + channel])
                var c1 = u32(e1[4usize * p + channel])
                if srgb && channel < 3usize {
                    c0 = (c0 << 8u32) | 128u32
                    c1 = (c1 << 8u32) | 128u32
                } else {
                    c0 = (c0 << 8u32) | c0
                    c1 = (c1 << 8u32) | c1
                }
                let mixed = (c0 * (64u32 - w) + c1 * w + 32u32) >> 6u32
                out[(t * width + s) * 4usize + channel] = u8((mixed >> 8u32) & 255u32)
                channel += 1usize
            }
            s += 1usize
        }
        t += 1usize
    }
    ret ok
}

// Bilinear infill of one plane of the weight grid at the texel's grid position.
fn infill(weights: []const u32, count: usize, planes: usize, plane: usize, v0: usize, grid_w: usize, w00: usize, w01: usize, w10: usize, w11: usize) -> u32 {
    let p00 = grid_weight(weights, count, planes, plane, v0)
    let p01 = grid_weight(weights, count, planes, plane, v0 + 1usize)
    let p10 = grid_weight(weights, count, planes, plane, v0 + grid_w)
    let p11 = grid_weight(weights, count, planes, plane, v0 + grid_w + 1usize)
    ret u32((p00 * w00 + p01 * w01 + p10 * w10 + p11 * w11 + 8usize) >> 4u32)
}

fn grid_weight(weights: []const u32, count: usize, planes: usize, plane: usize, i: usize) -> usize {
    let at = i * planes + plane
    if at >= count { ret 0usize }
    ret usize(weights[at])
}
