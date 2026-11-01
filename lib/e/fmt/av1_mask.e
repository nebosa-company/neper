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

use e.mem

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

fn diffwtd_mask(p0: []const i32, p1: []const i32, w: i32, h: i32, mask_type: i32, bit_depth: u32, post: u32, out: []u8) -> err {
    if w < 1i32 || h < 1i32 { ret Invalid }
    let n = usize(w) * usize(h)
    if p0.len < n || p1.len < n || out.len < n { ret Invalid }
    var k = 0usize
    while k < n {
        var diff = p0[k] - p1[k]
        if diff < 0i32 { diff = 0i32 - diff }
        diff = round2(diff, (bit_depth - 8u32) + post)
        let m = clip3(0i32, 64i32, 38i32 + diff / 16i32)
        if mask_type != 0i32 {
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

fn blend_interintra(dst: []u16, dst_stride: usize, pred: []const i32, mask: []const u8, mask_stride: usize, w: i32, h: i32, sub_x: u32, sub_y: u32, wedge: bool, bit_depth: u32, post: u32) -> err {
    if w < 1i32 || h < 1i32 { ret Invalid }
    let direct = !wedge
    if pred.len < usize(w) * usize(h) || dst_stride < usize(w) || dst.len < (usize(h) - 1usize) * dst_stride + usize(w) { ret Invalid }
    if !mask_fits(mask, mask_stride, w, h, sub_x, sub_y, direct) { ret Invalid }
    let maxv = (1i32 << bit_depth) - 1i32
    var y = 0usize
    while y < usize(h) {
        var x = 0usize
        while x < usize(w) {
            let m = mask_value(mask, mask_stride, x, y, sub_x, sub_y, direct)
            let p0 = clip3(0i32, maxv, round2(pred[y * usize(w) + x], post))
            let at = y * dst_stride + x
            dst[at] = u16(round2(m * i32(dst[at]) + (64i32 - m) * p0, 6u32))
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

fn blend_compound(dst: []u16, dst_stride: usize, p0: []const i32, p1: []const i32, mask: []const u8, mask_stride: usize, w: i32, h: i32, sub_x: u32, sub_y: u32, bit_depth: u32, post: u32) -> err {
    if w < 1i32 || h < 1i32 { ret Invalid }
    let n = usize(w) * usize(h)
    if p0.len < n || p1.len < n || dst_stride < usize(w) || dst.len < (usize(h) - 1usize) * dst_stride + usize(w) { ret Invalid }
    if !mask_fits(mask, mask_stride, w, h, sub_x, sub_y, false) { ret Invalid }
    let maxv = (1i32 << bit_depth) - 1i32
    var y = 0usize
    while y < usize(h) {
        var x = 0usize
        while x < usize(w) {
            let m = mask_value(mask, mask_stride, x, y, sub_x, sub_y, false)
            let k = y * usize(w) + x
            dst[y * dst_stride + x] = u16(clip3(0i32, maxv, round2(m * p0[k] + (64i32 - m) * p1[k], 6u32 + post)))
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}
