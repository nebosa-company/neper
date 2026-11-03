// AV1 inter-intra and mask blend prediction pieces (spec 7.11.3.11 .. 7.11.3.14): the wedge mask table, the
// difference weight mask, the intra mode variant mask and the mask blend itself.
//
// Mask layout: row major bytes (0..64), stride given alongside. A wedge or difference weight mask is at LUMA
// resolution of the block (stride = luma block width, or any stride the caller picked for a difference mask);
// the blenders subsample it for chroma exactly as 7.11.3.14 does. This is the `Blend.mask` / `mask_stride`
// layout of av1_inter.predict_inter (KIND_MASK). An intra mode variant mask is at the resolution of the plane
// being predicted (stride = w) and is blended with `wedge = false`.
//
// Predictions `pred`, `p0`, `p1` are the unclipped outputs of av1_inter.block_pred (w*h, row major, stride w) with
// the rounding of 7.11.3.2; `post` is InterPostRound (2 * 7 - (InterRound0 + InterRound1)).
//
//   new_masks(a)                          WedgeMasks of the spec (all block sizes with Wedge_Bits > 0), built once.
//   wedge_mask(m, bsize, sign, index)     view of WedgeMasks[bsize][sign][index]: Block_Width[bsize] x Block_Height[bsize],
//                                         stride = Block_Width[bsize]. Invalid when bsize has no wedge.
//   diffwtd_mask(p0, p1, w, h, mask_type, bit_depth, post, out)      7.11.3.12, out stride = w.
//   interintra_mask(mode, w, h, out)      7.11.3.13 (II_DC_PRED .. II_SMOOTH_PRED), out stride = w.
//   blend_interintra(dst, dst_stride, pred, mask, mask_stride, w, h, sub_x, sub_y, wedge, bit_depth, post)
//                                         7.11.3.14 with interintra = 1; dst already holds the intra prediction.
//                                         `wedge` is wedge_interintra (a luma resolution mask, subsampled for chroma).
//   blend_compound(dst, dst_stride, p0, p1, mask, mask_stride, w, h, sub_x, sub_y, bit_depth, post)
//                                         7.11.3.14 with interintra = 0 (COMPOUND_WEDGE / COMPOUND_DIFFWTD), for a
//                                         caller that holds p0 / p1 already (e.g. to build a difference mask first).
//
// Block sizes are the BLOCK_* enum values (BLOCK_8X8 = 3 ... BLOCK_64X16 = 21).

// Pixel planes (`dst`) are `[]u8` and only 8-bit video is supported: diffwtd_mask, blend_interintra and blend_compound
// return Invalid for bit_depth != 8. Masks are 0..64. blend_compound needs p0 and p1 within the signed 16 bit range
// (true for block_pred output at 8 bits); blend_interintra takes any pred.

use e.mem
use e.simd

error Invalid

const II_DC_PRED: i32 = 0i32
const II_V_PRED: i32 = 1i32
const II_H_PRED: i32 = 2i32
const II_SMOOTH_PRED: i32 = 3i32

type Masks = struct { data: []u8 }

fn wedge_oblique_odd() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x06\x12\x25\x35\x3c\x3f\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40" }

fn wedge_oblique_even() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x04\x0b\x1b\x2e\x3a\x3e\x3f\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40" }

fn wedge_vertical() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x07\x15\x2b\x39\x3e\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40" }

// Wedge_Codebook[3][16][3] as (direction, xoff, yoff); directions: HORIZONTAL 0, VERTICAL 1, OBLIQUE27 2, OBLIQUE63 3, OBLIQUE117 4, OBLIQUE153 5
fn wedge_codebook() -> str { ret "\x02\x04\x04\x03\x04\x04\x04\x04\x04\x05\x04\x04\x00\x04\x02\x00\x04\x04\x00\x04\x06\x01\x04\x04\x02\x04\x02\x02\x04\x06\x05\x04\x02\x05\x04\x06\x03\x02\x04\x03\x06\x04\x04\x02\x04\x04\x06\x04\x02\x04\x04\x03\x04\x04\x04\x04\x04\x05\x04\x04\x01\x02\x04\x01\x04\x04\x01\x06\x04\x00\x04\x04\x02\x04\x02\x02\x04\x06\x05\x04\x02\x05\x04\x06\x03\x02\x04\x03\x06\x04\x04\x02\x04\x04\x06\x04\x02\x04\x04\x03\x04\x04\x04\x04\x04\x05\x04\x04\x00\x04\x02\x00\x04\x06\x01\x02\x04\x01\x06\x04\x02\x04\x02\x02\x04\x06\x05\x04\x02\x05\x04\x06\x03\x02\x04\x03\x06\x04\x04\x02\x04\x04\x06\x04" }

fn ii_weights_1d() -> str { ret "\x3c\x3a\x38\x36\x34\x32\x30\x2f\x2d\x2c\x2a\x29\x27\x26\x25\x23\x22\x21\x20\x1f\x1e\x1d\x1c\x1b\x1a\x19\x18\x17\x16\x16\x15\x14\x13\x13\x12\x12\x11\x10\x10\x0f\x0f\x0e\x0e\x0d\x0d\x0c\x0c\x0c\x0b\x0b\x0a\x0a\x0a\x09\x09\x09\x08\x08\x08\x08\x07\x07\x07\x07\x06\x06\x06\x06\x06\x05\x05\x05\x05\x05\x04\x04\x04\x04\x04\x04\x04\x04\x03\x03\x03\x03\x03\x03\x03\x03\x03\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x02\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" }

fn num4_wide() -> str { ret "\x01\x01\x02\x02\x02\x04\x04\x04\x08\x08\x08\x10\x10\x10\x20\x20\x01\x04\x02\x08\x04\x10" }

fn num4_high() -> str { ret "\x01\x02\x01\x02\x04\x02\x04\x08\x04\x08\x10\x08\x10\x20\x10\x20\x04\x01\x08\x02\x10\x04" }

fn clip3(lo: i32, hi: i32, v: i32) -> i32 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

fn round2(x: i32, n: u32) -> i32 {
    if n == 0u32 { ret x }
    ret (x + (1i32 << (n - 1u32))) >> n
}

fn has_wedge(bsize: i32) -> bool {
    ret (bsize >= 3i32 && bsize <= 9i32) || bsize == 18i32 || bsize == 19i32
}

fn block_w(bsize: i32) -> usize {
    let t = num4_wide()
    ret usize(t[usize(bsize)]) * 4usize
}

fn block_h(bsize: i32) -> usize {
    let t = num4_high()
    ret usize(t[usize(bsize)]) * 4usize
}

// start of WedgeMasks[bsize][0][0] in Masks.data
fn wedge_base(bsize: i32) -> usize {
    var off = 0usize
    var b = 3i32
    while b < bsize {
        if has_wedge(b) { off += block_w(b) * block_h(b) * 32usize }
        b += 1i32
    }
    ret off
}

fn wedge_total() -> usize {
    var off = 0usize
    var b = 3i32
    while b < 22i32 {
        if has_wedge(b) { off += block_w(b) * block_h(b) * 32usize }
        b += 1i32
    }
    ret off
}

// MasterMask[dir][i][j] lives at dir * 4096 + i * 64 + j
fn master_masks(mm: []u8) {
    let odd = wedge_oblique_odd()
    let even = wedge_oblique_even()
    let vert = wedge_vertical()
    var j = 0usize
    while j < 64usize {
        var shift = 16i32
        var i = 0usize
        while i < 64usize {
            mm[3usize * 4096usize + i * 64usize + j] = even[usize(clip3(0i32, 63i32, i32(j) - shift))]
            shift -= 1i32
            mm[3usize * 4096usize + (i + 1usize) * 64usize + j] = odd[usize(clip3(0i32, 63i32, i32(j) - shift))]
            mm[4096usize + i * 64usize + j] = vert[j]
            mm[4096usize + (i + 1usize) * 64usize + j] = vert[j]
            i += 2usize
        }
        j += 1usize
    }
    var i2 = 0usize
    while i2 < 64usize {
        var j2 = 0usize
        while j2 < 64usize {
            let msk = mm[3usize * 4096usize + i2 * 64usize + j2]
            mm[2usize * 4096usize + j2 * 64usize + i2] = msk
            mm[4usize * 4096usize + i2 * 64usize + (63usize - j2)] = 64u8 - msk
            mm[5usize * 4096usize + (63usize - j2) * 64usize + i2] = 64u8 - msk
            mm[j2 * 64usize + i2] = mm[4096usize + i2 * 64usize + j2]
            j2 += 1usize
        }
        i2 += 1usize
    }
}

fn block_shape(bsize: i32) -> usize {
    let w4 = block_w(bsize)
    let h4 = block_h(bsize)
    if h4 > w4 { ret 0usize }
    if h4 < w4 { ret 1usize }
    ret 2usize
}

fn fill_wedges(mm: []u8, data: []u8, bsize: i32) {
    let cb = wedge_codebook()
    let w = block_w(bsize)
    let h = block_h(bsize)
    let base = wedge_base(bsize)
    var wedge = 0usize
    while wedge < 16usize {
        let ci = (block_shape(bsize) * 16usize + wedge) * 3usize
        let dir = usize(cb[ci])
        let xoff = 32usize - ((usize(cb[ci + 1usize]) * w) >> 3u32)
        let yoff = 32usize - ((usize(cb[ci + 2usize]) * h) >> 3u32)
        let mb = dir * 4096usize
        var sum = 0usize
        var i = 0usize
        while i < w {
            sum += usize(mm[mb + yoff * 64usize + xoff + i])
            i += 1usize
        }
        i = 1usize
        while i < h {
            sum += usize(mm[mb + (yoff + i) * 64usize + xoff])
            i += 1usize
        }
        let avg = (sum + (w + h - 1usize) / 2usize) / (w + h - 1usize)
        var flip = 0usize
        if avg < 32usize { flip = 1usize }
        let at_flip = base + (flip * 16usize + wedge) * w * h
        let at_other = base + ((1usize - flip) * 16usize + wedge) * w * h
        i = 0usize
        while i < h {
            var j = 0usize
            while j < w {
                let v = mm[mb + (yoff + i) * 64usize + xoff + j]
                data[at_flip + i * w + j] = v
                data[at_other + i * w + j] = 64u8 - v
                j += 1usize
            }
            i += 1usize
        }
        wedge += 1usize
    }
}

fn new_masks(a: *mem.Arena) -> (Masks, err) {
    let (data, e1) = mem.alloc[u8](a, wedge_total())
    if e1 != ok { ret (Masks { data: data }, e1) }
    let (mm, e2) = mem.alloc[u8](a, 6usize * 4096usize)
    if e2 != ok { ret (Masks { data: data }, e2) }
    master_masks(mm)
    var b = 3i32
    while b < 22i32 {
        if has_wedge(b) { fill_wedges(mm, data, b) }
        b += 1i32
    }
    ret (Masks { data: data }, ok)
}

fn wedge_mask(m: *Masks, bsize: i32, wedge_sign: i32, wedge_index: i32) -> ([]const u8, err) {
    if bsize < 0i32 || bsize > 21i32 || !has_wedge(bsize) || wedge_sign < 0i32 || wedge_sign > 1i32 || wedge_index < 0i32 || wedge_index > 15i32 {
        let none: []const u8 = m.data[0usize..0usize]
        ret (none, Invalid)
    }
    let n = block_w(bsize) * block_h(bsize)
    let at = wedge_base(bsize) + (usize(wedge_sign) * 16usize + usize(wedge_index)) * n
    ret (m.data[at..at + n], ok)
}

type Pair = struct { lo: Vec[i16, 8], hi: Vec[i16, 8] }

fn widen(v: Vec[u8, 16]) -> Pair {
    let z = simd.splat[Vec[u8, 16]](0u8)
    ret Pair { lo: mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](v, z)), hi: mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](v, z)) }
}

fn pack16(lo: Vec[i16, 8], hi: Vec[i16, 8]) -> Vec[u8, 16] {
    ret simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](lo, hi)
}

fn round_bias(n: u32) -> i32 {
    if n == 0u32 { ret 0i32 }
    ret 1i32 << (n - 1u32)
}

fn dw4(p0: []const i32, p1: []const i32, at: usize, rnd: Vec[i32, 4], post: u32, top: Vec[i32, 4], flip: bool) -> Vec[i32, 4] {
    let a = simd.load[Vec[i32, 4]](p0, at)
    let b = simd.load[Vec[i32, 4]](p1, at)
    let d = (simd.max[Vec[i32, 4]](a -% b, b -% a) +% rnd) >> post
    let m = simd.min[Vec[i32, 4]]((d >> 4u32) +% simd.splat[Vec[i32, 4]](38i32), top)
    if flip { ret top -% m }
    ret m
}

fn diffwtd_mask(p0: []const i32, p1: []const i32, w: i32, h: i32, mask_type: i32, bit_depth: u32, post: u32, out: []u8) -> err {
    if bit_depth != 8u32 { ret Invalid }
    if w < 1i32 || h < 1i32 { ret Invalid }
    let n = usize(w) * usize(h)
    if p0.len < n || p1.len < n || out.len < n { ret Invalid }
    let rnd = simd.splat[Vec[i32, 4]](round_bias(post))
    let top = simd.splat[Vec[i32, 4]](64i32)
    let flip = mask_type != 0i32
    var k = 0usize
    while k + 16usize <= n {
        let m0 = dw4(p0, p1, k, rnd, post, top, flip)
        let m1 = dw4(p0, p1, k + 4usize, rnd, post, top, flip)
        let m2 = dw4(p0, p1, k + 8usize, rnd, post, top, flip)
        let m3 = dw4(p0, p1, k + 12usize, rnd, post, top, flip)
        simd.store[Vec[u8, 16]](out, k, pack16(simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](m0, m1), simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](m2, m3)))
        k += 16usize
    }
    while k < n {
        var diff = p0[k] - p1[k]
        if diff < 0i32 { diff = 0i32 - diff }
        diff = round2(diff, post)
        let m = clip3(0i32, 64i32, 38i32 + diff / 16i32)
        if flip {
            out[k] = u8(64i32 - m)
        } else {
            out[k] = u8(m)
        }
        k += 1usize
    }
    ret ok
}

fn interintra_mask(mode: i32, w: i32, h: i32, out: []u8) -> err {
    if w < 1i32 || h < 1i32 || w > 128i32 || h > 128i32 || mode < 0i32 || mode > 3i32 { ret Invalid }
    if out.len < usize(w) * usize(h) { ret Invalid }
    let tbl = ii_weights_1d()
    var big = w
    if h > w { big = h }
    let scale = usize(128i32 / big)
    var i = 0usize
    while i < usize(h) {
        var j = 0usize
        while j < usize(w) {
            var v = 32u8
            if mode == II_V_PRED {
                v = tbl[i * scale]
            } else if mode == II_H_PRED {
                v = tbl[j * scale]
            } else if mode == II_SMOOTH_PRED {
                var lo = i
                if j < i { lo = j }
                v = tbl[lo * scale]
            }
            out[i * usize(w) + j] = v
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn mask_value(mask: []const u8, ms: usize, x: usize, y: usize, sub_x: u32, sub_y: u32, direct: bool) -> i32 {
    if (sub_x == 0u32 && sub_y == 0u32) || direct { ret i32(mask[y * ms + x]) }
    if sub_x != 0u32 && sub_y == 0u32 {
        ret round2(i32(mask[y * ms + 2usize * x]) + i32(mask[y * ms + 2usize * x + 1usize]), 1u32)
    }
    ret round2(i32(mask[2usize * y * ms + 2usize * x]) + i32(mask[2usize * y * ms + 2usize * x + 1usize]) + i32(mask[(2usize * y + 1usize) * ms + 2usize * x]) + i32(mask[(2usize * y + 1usize) * ms + 2usize * x + 1usize]), 2u32)
}

// the mask rows and columns a w x h block reads, checked against the slice
fn mask_fits(mask: []const u8, ms: usize, w: i32, h: i32, sub_x: u32, sub_y: u32, direct: bool) -> bool {
    var cols = usize(w)
    var rows = usize(h)
    if !direct {
        if sub_x != 0u32 { cols = cols * 2usize }
        if sub_y != 0u32 { rows = rows * 2usize }
        if sub_x == 0u32 && sub_y != 0u32 { cols = cols * 2usize }
    }
    ret ms >= cols && mask.len >= (rows - 1usize) * ms + cols
}

// 0: mask sample as is, 1: horizontal pair average, 2: 2x2 average
fn mask_mode(sub_x: u32, sub_y: u32, direct: bool) -> u32 {
    if (sub_x == 0u32 && sub_y == 0u32) || direct { ret 0u32 }
    if sub_x != 0u32 && sub_y == 0u32 { ret 1u32 }
    ret 2u32
}

// 8 averaged mask samples (mode 1 or 2) for output columns x .. x + 8 of output row y, in 16 bit lanes
fn mask8(mask: []const u8, ms: usize, y: usize, x: usize, mode: u32) -> Vec[i16, 8] {
    let ff = simd.splat[Vec[i16, 8]](255i16)
    if mode == 1u32 {
        let a = mem.bitcast[Vec[i16, 8]](simd.load[Vec[u8, 16]](mask, y * ms + 2usize * x))
        ret ((a & ff) +% ((a >> 8u32) & ff) +% simd.splat[Vec[i16, 8]](1i16)) >> 1u32
    }
    let r0 = 2usize * y * ms + 2usize * x
    let a = mem.bitcast[Vec[i16, 8]](simd.load[Vec[u8, 16]](mask, r0))
    let b = mem.bitcast[Vec[i16, 8]](simd.load[Vec[u8, 16]](mask, r0 + ms))
    ret ((a & ff) +% ((a >> 8u32) & ff) +% (b & ff) +% ((b >> 8u32) & ff) +% simd.splat[Vec[i16, 8]](2i16)) >> 2u32
}

fn mask16(mask: []const u8, ms: usize, y: usize, x: usize, mode: u32) -> Vec[u8, 16] {
    if mode == 0u32 { ret simd.load[Vec[u8, 16]](mask, y * ms + x) }
    ret pack16(mask8(mask, ms, y, x, mode), mask8(mask, ms, y, x + 8usize, mode))
}

// pred rounded by post and clipped to a pixel, 16 samples
fn pred16(pred: []const i32, at: usize, rnd: i32, post: u32) -> Vec[u8, 16] {
    let r = simd.splat[Vec[i32, 4]](rnd)
    let a0 = (simd.load[Vec[i32, 4]](pred, at) +% r) >> post
    let a1 = (simd.load[Vec[i32, 4]](pred, at + 4usize) +% r) >> post
    let a2 = (simd.load[Vec[i32, 4]](pred, at + 8usize) +% r) >> post
    let a3 = (simd.load[Vec[i32, 4]](pred, at + 12usize) +% r) >> post
    ret pack16(simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](a0, a1), simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](a2, a3))
}

// Round2(m * d + (64 - m) * p, 6) on 16 pixels; the sum is at most 64 * 255, so it fits 16 bit lanes
fn ii_kernel(d: Vec[u8, 16], p: Vec[u8, 16], m: Vec[u8, 16]) -> Vec[u8, 16] {
    let dw = widen(d)
    let pw = widen(p)
    let mw = widen(m)
    let c64 = simd.splat[Vec[i16, 8]](64i16)
    let c32 = simd.splat[Vec[i16, 8]](32i16)
    let lo = (mw.lo *% dw.lo +% (c64 -% mw.lo) *% pw.lo +% c32) >> 6u32
    let hi = (mw.hi *% dw.hi +% (c64 -% mw.hi) *% pw.hi +% c32) >> 6u32
    ret pack16(lo, hi)
}

fn cp4(a: Vec[i16, 8], b: Vec[i16, 8], rnd: Vec[i32, 4], sh: u32) -> Vec[i32, 4] {
    ret (simd.madd_i16[Vec[i16, 8]](a, b) +% rnd) >> sh
}

// Round2(m * p0 + (64 - m) * p1, 6 + post) clipped to a pixel, 16 samples; p0 and p1 must fit 16 bit signed
fn cp_kernel(p0: []const i32, p1: []const i32, at: usize, m: Vec[u8, 16], rnd: i32, sh: u32) -> Vec[u8, 16] {
    let mw = widen(m)
    let c64 = simd.splat[Vec[i16, 8]](64i16)
    let nlo = c64 -% mw.lo
    let nhi = c64 -% mw.hi
    let r = simd.splat[Vec[i32, 4]](rnd)
    let a0 = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](simd.load[Vec[i32, 4]](p0, at), simd.load[Vec[i32, 4]](p0, at + 4usize))
    let a1 = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](simd.load[Vec[i32, 4]](p0, at + 8usize), simd.load[Vec[i32, 4]](p0, at + 12usize))
    let b0 = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](simd.load[Vec[i32, 4]](p1, at), simd.load[Vec[i32, 4]](p1, at + 4usize))
    let b1 = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](simd.load[Vec[i32, 4]](p1, at + 8usize), simd.load[Vec[i32, 4]](p1, at + 12usize))
    let s0 = cp4(simd.unpack_lo[Vec[i16, 8]](a0, b0), simd.unpack_lo[Vec[i16, 8]](mw.lo, nlo), r, sh)
    let s1 = cp4(simd.unpack_hi[Vec[i16, 8]](a0, b0), simd.unpack_hi[Vec[i16, 8]](mw.lo, nlo), r, sh)
    let s2 = cp4(simd.unpack_lo[Vec[i16, 8]](a1, b1), simd.unpack_lo[Vec[i16, 8]](mw.hi, nhi), r, sh)
    let s3 = cp4(simd.unpack_hi[Vec[i16, 8]](a1, b1), simd.unpack_hi[Vec[i16, 8]](mw.hi, nhi), r, sh)
    ret pack16(simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](s0, s1), simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](s2, s3))
}

// copy a 4 or 8 byte row
fn copy_narrow(dst: []u8, d: usize, src: []const u8, s: usize, w: usize) {
    if w == 8usize {
        *mem.cast[*u64](&dst[d]) = *mem.cast[*u64](&src[s])
    } else {
        *mem.cast[*u32](&dst[d]) = *mem.cast[*u32](&src[s])
    }
}

// row y of the effective (luma resolution reduced) mask, w samples, into mrow at off
fn mask_row(mrow: []u8, off: usize, mask: []const u8, ms: usize, y: usize, w: usize, sub_x: u32, sub_y: u32, direct: bool, mode: u32) {
    if mode == 0u32 {
        copy_narrow(mrow, off, mask, y * ms, w)
        ret
    }
    var need = y * ms + 16usize
    if mode == 2u32 { need = (2usize * y + 1usize) * ms + 16usize }
    if need <= mask.len && mrow.len >= off + 16usize {
        let v = mask8(mask, ms, y, 0usize, mode)
        simd.store[Vec[u8, 16]](mrow, off, pack16(v, v))
        ret
    }
    var x = 0usize
    while x < w {
        mrow[off + x] = u8(mask_value(mask, ms, x, y, sub_x, sub_y, direct))
        x += 1usize
    }
}

fn ii_scalar(dst: []u8, dst_stride: usize, pred: []const i32, mask: []const u8, ms: usize, w: usize, y: usize, x0: usize, sub_x: u32, sub_y: u32, direct: bool, post: u32) {
    var x = x0
    while x < w {
        let m = mask_value(mask, ms, x, y, sub_x, sub_y, direct)
        let p0 = clip3(0i32, 255i32, round2(pred[y * w + x], post))
        let at = y * dst_stride + x
        dst[at] = u8(round2(m * i32(dst[at]) + (64i32 - m) * p0, 6u32))
        x += 1usize
    }
}

fn blend_interintra(dst: []u8, dst_stride: usize, pred: []const i32, mask: []const u8, mask_stride: usize, w: i32, h: i32, sub_x: u32, sub_y: u32, wedge: bool, bit_depth: u32, post: u32) -> err {
    if bit_depth != 8u32 { ret Invalid }
    if w < 1i32 || h < 1i32 { ret Invalid }
    let direct = !wedge
    if pred.len < usize(w) * usize(h) || dst_stride < usize(w) || dst.len < (usize(h) - 1usize) * dst_stride + usize(w) { ret Invalid }
    if !mask_fits(mask, mask_stride, w, h, sub_x, sub_y, direct) { ret Invalid }
    let mode = mask_mode(sub_x, sub_y, direct)
    let wu = usize(w)
    let hu = usize(h)
    let rnd = round_bias(post)
    var y = 0usize
    if wu >= 16usize {
        while y < hu {
            var x = 0usize
            while x + 16usize <= wu {
                let at = y * dst_stride + x
                simd.store[Vec[u8, 16]](dst, at, ii_kernel(simd.load[Vec[u8, 16]](dst, at), pred16(pred, y * wu + x, rnd, post), mask16(mask, mask_stride, y, x, mode)))
                x += 16usize
            }
            ii_scalar(dst, dst_stride, pred, mask, mask_stride, wu, y, x, sub_x, sub_y, direct, post)
            y += 1usize
        }
        ret ok
    }
    if wu == 8usize || wu == 4usize {
        let g = 16usize / wu
        var mrow: [32]u8 = zero
        var dsc: [16]u8 = zero
        while y + g <= hu {
            var k = 0usize
            while k < g {
                mask_row(mrow[..], k * wu, mask, mask_stride, y + k, wu, sub_x, sub_y, direct, mode)
                copy_narrow(dsc[..], k * wu, dst, (y + k) * dst_stride, wu)
                k += 1usize
            }
            let r = ii_kernel(simd.load[Vec[u8, 16]](dsc[..], 0usize), pred16(pred, y * wu, rnd, post), simd.load[Vec[u8, 16]](mrow[..], 0usize))
            simd.store[Vec[u8, 16]](dsc[..], 0usize, r)
            k = 0usize
            while k < g {
                copy_narrow(dst, (y + k) * dst_stride, dsc[..], k * wu, wu)
                k += 1usize
            }
            y += g
        }
    }
    while y < hu {
        ii_scalar(dst, dst_stride, pred, mask, mask_stride, wu, y, 0usize, sub_x, sub_y, direct, post)
        y += 1usize
    }
    ret ok
}

fn cp_scalar(dst: []u8, dst_stride: usize, p0: []const i32, p1: []const i32, mask: []const u8, ms: usize, w: usize, y: usize, x0: usize, sub_x: u32, sub_y: u32, post: u32) {
    var x = x0
    while x < w {
        let m = mask_value(mask, ms, x, y, sub_x, sub_y, false)
        let k = y * w + x
        dst[y * dst_stride + x] = u8(clip3(0i32, 255i32, round2(m * p0[k] + (64i32 - m) * p1[k], 6u32 + post)))
        x += 1usize
    }
}

fn blend_compound(dst: []u8, dst_stride: usize, p0: []const i32, p1: []const i32, mask: []const u8, mask_stride: usize, w: i32, h: i32, sub_x: u32, sub_y: u32, bit_depth: u32, post: u32) -> err {
    if bit_depth != 8u32 { ret Invalid }
    if w < 1i32 || h < 1i32 { ret Invalid }
    let n = usize(w) * usize(h)
    if p0.len < n || p1.len < n || dst_stride < usize(w) || dst.len < (usize(h) - 1usize) * dst_stride + usize(w) { ret Invalid }
    if !mask_fits(mask, mask_stride, w, h, sub_x, sub_y, false) { ret Invalid }
    let mode = mask_mode(sub_x, sub_y, false)
    let wu = usize(w)
    let hu = usize(h)
    let sh = 6u32 + post
    let rnd = round_bias(sh)
    var y = 0usize
    if wu >= 16usize {
        while y < hu {
            var x = 0usize
            while x + 16usize <= wu {
                simd.store[Vec[u8, 16]](dst, y * dst_stride + x, cp_kernel(p0, p1, y * wu + x, mask16(mask, mask_stride, y, x, mode), rnd, sh))
                x += 16usize
            }
            cp_scalar(dst, dst_stride, p0, p1, mask, mask_stride, wu, y, x, sub_x, sub_y, post)
            y += 1usize
        }
        ret ok
    }
    if wu == 8usize || wu == 4usize {
        let g = 16usize / wu
        var mrow: [32]u8 = zero
        var dsc: [16]u8 = zero
        while y + g <= hu {
            var k = 0usize
            while k < g {
                mask_row(mrow[..], k * wu, mask, mask_stride, y + k, wu, sub_x, sub_y, false, mode)
                k += 1usize
            }
            simd.store[Vec[u8, 16]](dsc[..], 0usize, cp_kernel(p0, p1, y * wu, simd.load[Vec[u8, 16]](mrow[..], 0usize), rnd, sh))
            k = 0usize
            while k < g {
                copy_narrow(dst, (y + k) * dst_stride, dsc[..], k * wu, wu)
                k += 1usize
            }
            y += g
        }
    }
    while y < hu {
        cp_scalar(dst, dst_stride, p0, p1, mask, mask_stride, wu, y, 0usize, sub_x, sub_y, post)
        y += 1usize
    }
    ret ok
}
