// AV1 inter prediction (spec 7.11.3): motion vector scaling, the 8-tap sub-pixel block prediction,
// single and compound (average, distance weighted, mask) combination and overlapped block motion
// compensation. Out of scope, not implemented: warped motion (local and global), wedge / difference /
// inter-intra masks (a mask blend takes the finished `Mask` from the caller), inter-intra, intra block copy
// (it is a plain `Ref` onto the current frame with its own width and height).
//
// Planes are `[]u16` with a stride in samples. Positions and sizes are in samples of the plane being
// predicted; the frame sizes in `Ref` / `Geom` are LUMA sizes (RefUpscaledWidth, RefFrameHeight,
// FrameWidth, FrameHeight), the plane's own bounds follow from the subsampling.
//
//   new_work(a)                  scratch buffers, made once and reused for every block.
//   predict_inter(wk, g, m0, m1, compound, blend, dst, dst_stride)
//        predict_inter of the spec for one plane region: dst is the plane slice that starts at the sample
//        (g.x, g.y) of the region and has the plane's stride. m1 is read only when compound. The mv fields
//        are mv[0] (row) and mv[1] (col) in 1/8 luma sample; filter_y / filter_x are InterpFilters[..][0] and [1].
//   overlap(wk, g, info, above, left, dst, dst_stride)
//        overlapped motion compensation 7.11.3.9 / 7.11.3.10, run on dst after predict_inter has written
//        the block. `above[k]` / `left[k]` describe the candidate at 4x4 offset k from the block's first
//        column / row (the spec reads column x4|1 and row y4|1, so odd k are read; fill all k below the
//        block's width / height in 4x4 units). Neighbor.motion.frame must be the plane of the neighbour's
//        first reference.
//   distance_weights(dist0, dist1)
//        7.11.3.15 on dist[0], dist[1] (already Clip3(0, 31, Abs(get_relative_dist(..)))); answers (fwd, bck).
//   block_pred(wk, m, g, x, y, w, h, round0, round1, out)
//        the scaling + block inter prediction of one reference into `out` (w*h, row major, unclipped values).
//
// Invalid: a block larger than 128, an empty frame, or a reference outside the 1/16 .. 2x scale range.

use e.mem

error Invalid

const KIND_AVERAGE: i32 = 0i32
const KIND_DISTANCE: i32 = 1i32
const KIND_MASK: i32 = 2i32

type Ref = struct { data: []const u16, stride: usize, width: i32, height: i32 }
type Motion = struct { frame: Ref, mv_row: i32, mv_col: i32, filter_y: i32, filter_x: i32 }
type Geom = struct { x: i32, y: i32, w: i32, h: i32, sub_x: u32, sub_y: u32, cur_w: i32, cur_h: i32, bit_depth: u32 }
// kind: KIND_AVERAGE, KIND_DISTANCE (fwd / bck weights) or KIND_MASK (mask at luma resolution, mask_stride per row)
type Blend = struct { kind: i32, fwd: i32, bck: i32, mask: []const u8, mask_stride: usize }
type Neighbor = struct { inter: bool, size4: i32, motion: Motion }
// w4/h4 Num_4x4_Blocks_Wide/High[MiSize], log2_w/log2_h Mi_Width/Height_Log2[MiSize], cols4 = MiCols - MiCol,
// rows4 = MiRows - MiRow, plane_size = get_plane_residual_size(MiSize, plane) as a block size enum value
type ObmcInfo = struct { w4: i32, h4: i32, log2_w: i32, log2_h: i32, cols4: i32, rows4: i32, plane_size: i32, avail_u: bool, avail_l: bool }
type Work = struct { inter: []i32, p0: []i32, p1: []i32, taps: []i32 }

// Subpel_Filters[6][16][8], every tap halved (they are all even) plus 64
fn filter_bytes() -> str { ret "\x40\x40\x40\x80\x40\x40\x40\x40\x40\x41\x3d\x7f\x44\x3f\x40\x40\x40\x41\x3b\x7d\x49\x3e\x40\x40\x40\x41\x3a\x7a\x4e\x3c\x41\x40\x40\x41\x39\x77\x53\x3b\x41\x40\x40\x41\x39\x73\x58\x3a\x41\x40\x40\x41\x38\x6f\x5d\x3a\x41\x40\x40\x41\x39\x6a\x61\x3a\x41\x40\x40\x41\x39\x66\x66\x39\x41\x40\x40\x41\x3a\x61\x6a\x39\x41\x40\x40\x41\x3a\x5d\x6f\x38\x41\x40\x40\x41\x3a\x58\x73\x39\x41\x40\x40\x41\x3b\x53\x77\x39\x41\x40\x40\x41\x3c\x4e\x7a\x3a\x41\x40\x40\x40\x3e\x49\x7d\x3b\x41\x40\x40\x40\x3f\x44\x7f\x3d\x41\x40\x40\x40\x40\x80\x40\x40\x40\x40\x40\x41\x4e\x5f\x51\x41\x40\x40\x40\x40\x4d\x5f\x52\x42\x40\x40\x40\x40\x4b\x5f\x54\x42\x40\x40\x40\x40\x4a\x5e\x55\x43\x40\x40\x40\x40\x49\x5d\x56\x44\x40\x40\x40\x40\x48\x5c\x57\x45\x40\x40\x40\x3f\x48\x5b\x58\x46\x40\x40\x40\x3f\x47\x5a\x5a\x47\x3f\x40\x40\x40\x46\x58\x5b\x48\x3f\x40\x40\x40\x45\x57\x5c\x48\x40\x40\x40\x40\x44\x56\x5d\x49\x40\x40\x40\x40\x43\x55\x5e\x4a\x40\x40\x40\x40\x42\x54\x5f\x4b\x40\x40\x40\x40\x42\x52\x5f\x4d\x40\x40\x40\x40\x41\x51\x5f\x4e\x41\x40\x40\x40\x40\x80\x40\x40\x40\x40\x3f\x41\x3d\x7f\x44\x3f\x41\x40\x3f\x43\x3a\x7e\x48\x3d\x42\x3f\x3f\x44\x37\x7c\x4d\x3b\x43\x3f\x3e\x45\x35\x7a\x53\x39\x43\x3f\x3e\x45\x35\x76\x58\x37\x44\x3f\x3e\x45\x34\x72\x5e\x36\x44\x3f\x3e\x45\x34\x6d\x63\x35\x45\x3f\x3e\x46\x34\x68\x68\x34\x46\x3e\x3f\x45\x35\x63\x6d\x34\x45\x3e\x3f\x44\x36\x5e\x72\x34\x45\x3e\x3f\x44\x37\x58\x76\x35\x45\x3e\x3f\x43\x39\x53\x7a\x35\x45\x3e\x3f\x43\x3b\x4d\x7c\x37\x44\x3f\x3f\x42\x3d\x48\x7e\x3a\x43\x3f\x40\x41\x3f\x44\x7f\x3d\x41\x3f\x40\x40\x40\x80\x40\x40\x40\x40\x40\x40\x40\x7c\x44\x40\x40\x40\x40\x40\x40\x78\x48\x40\x40\x40\x40\x40\x40\x74\x4c\x40\x40\x40\x40\x40\x40\x70\x50\x40\x40\x40\x40\x40\x40\x6c\x54\x40\x40\x40\x40\x40\x40\x68\x58\x40\x40\x40\x40\x40\x40\x64\x5c\x40\x40\x40\x40\x40\x40\x60\x60\x40\x40\x40\x40\x40\x40\x5c\x64\x40\x40\x40\x40\x40\x40\x58\x68\x40\x40\x40\x40\x40\x40\x54\x6c\x40\x40\x40\x40\x40\x40\x50\x70\x40\x40\x40\x40\x40\x40\x4c\x74\x40\x40\x40\x40\x40\x40\x48\x78\x40\x40\x40\x40\x40\x40\x44\x7c\x40\x40\x40\x40\x40\x40\x80\x40\x40\x40\x40\x40\x40\x3e\x7f\x44\x3f\x40\x40\x40\x40\x3c\x7d\x49\x3e\x40\x40\x40\x40\x3b\x7a\x4e\x3d\x40\x40\x40\x40\x3a\x77\x53\x3c\x40\x40\x40\x40\x3a\x73\x58\x3b\x40\x40\x40\x40\x39\x6f\x5d\x3b\x40\x40\x40\x40\x3a\x6a\x61\x3b\x40\x40\x40\x40\x3a\x66\x66\x3a\x40\x40\x40\x40\x3b\x61\x6a\x3a\x40\x40\x40\x40\x3b\x5d\x6f\x39\x40\x40\x40\x40\x3b\x58\x73\x3a\x40\x40\x40\x40\x3c\x53\x77\x3a\x40\x40\x40\x40\x3d\x4e\x7a\x3b\x40\x40\x40\x40\x3e\x49\x7d\x3c\x40\x40\x40\x40\x3f\x44\x7f\x3e\x40\x40\x40\x40\x40\x80\x40\x40\x40\x40\x40\x40\x4f\x5f\x51\x41\x40\x40\x40\x40\x4d\x5f\x52\x42\x40\x40\x40\x40\x4b\x5f\x54\x42\x40\x40\x40\x40\x4a\x5e\x55\x43\x40\x40\x40\x40\x49\x5d\x56\x44\x40\x40\x40\x40\x48\x5c\x57\x45\x40\x40\x40\x40\x47\x5b\x58\x46\x40\x40\x40\x40\x46\x5a\x5a\x46\x40\x40\x40\x40\x46\x58\x5b\x47\x40\x40\x40\x40\x45\x57\x5c\x48\x40\x40\x40\x40\x44\x56\x5d\x49\x40\x40\x40\x40\x43\x55\x5e\x4a\x40\x40\x40\x40\x42\x54\x5f\x4b\x40\x40\x40\x40\x42\x52\x5f\x4d\x40\x40\x40\x40\x41\x51\x5f\x4f\x40\x40" }

fn obmc_masks() -> str { ret "\x2d\x40\x27\x32\x3b\x40\x24\x2a\x30\x35\x39\x3d\x40\x40\x22\x25\x28\x2b\x2e\x31\x34\x36\x38\x3a\x3c\x3d\x40\x40\x40\x40\x21\x23\x24\x26\x28\x29\x2b\x2c\x2d\x2f\x30\x32\x33\x34\x35\x37\x38\x39\x3a\x3b\x3c\x3c\x3d\x3e\x40\x40\x40\x40\x40\x40\x40\x40" }

fn quant_dist_weight() -> str { ret "\x02\x03\x02\x05\x02\x07" }

fn quant_dist_lookup() -> str { ret "\x09\x07\x0b\x05\x0c\x04\x0d\x03" }

fn new_work(a: *mem.Arena) -> (Work, err) {
    let (inter, e1) = mem.alloc[i32](a, 264usize * 128usize)
    if e1 != ok { ret (Work { inter: inter, p0: inter, p1: inter, taps: inter }, e1) }
    let (p0, e2) = mem.alloc[i32](a, 16384usize)
    if e2 != ok { ret (Work { inter: inter, p0: p0, p1: p0, taps: inter }, e2) }
    let (p1, e3) = mem.alloc[i32](a, 16384usize)
    if e3 != ok { ret (Work { inter: inter, p0: p0, p1: p1, taps: inter }, e3) }
    let (taps, e4) = mem.alloc[i32](a, 768usize)
    if e4 != ok { ret (Work { inter: inter, p0: p0, p1: p1, taps: taps }, e4) }
    let fb = filter_bytes()
    var i = 0usize
    while i < 768usize {
        taps[i] = (i32(fb[i]) - 64i32) * 2i32
        i += 1usize
    }
    ret (Work { inter: inter, p0: p0, p1: p1, taps: taps }, ok)
}

fn clip3(lo: i32, hi: i32, v: i32) -> i32 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

fn round2(x: i32, n: u32) -> i32 {
    if n == 0u32 { ret x }
    ret (x + (1i32 << (n - 1u32))) >> n
}

fn round2_64(x: i64, n: u32) -> i64 {
    if n == 0u32 { ret x }
    ret (x + (1i64 << (n - 1u32))) >> n
}

fn round2_signed_64(x: i64, n: u32) -> i64 {
    if x >= 0i64 { ret round2_64(x, n) }
    ret 0i64 - round2_64(0i64 - x, n)
}

fn small_filter(f: i32, n: i32) -> i32 {
    if n <= 4i32 {
        if f == 0i32 || f == 2i32 { ret 4i32 }
        if f == 1i32 { ret 5i32 }
    }
    ret f
}

fn block_pred(wk: Work, m: Motion, g: Geom, x: i32, y: i32, w: i32, h: i32, round0: u32, round1: u32, out: []i32) -> err {
    if w < 1i32 || h < 1i32 || w > 128i32 || h > 128i32 { ret Invalid }
    if g.cur_w < 1i32 || g.cur_h < 1i32 || m.frame.width < 1i32 || m.frame.height < 1i32 { ret Invalid }
    let x_scale = ((i64(m.frame.width) << 14u32) + i64(g.cur_w / 2i32)) / i64(g.cur_w)
    let y_scale = ((i64(m.frame.height) << 14u32) + i64(g.cur_h / 2i32)) / i64(g.cur_h)
    if x_scale > 32768i64 || y_scale > 32768i64 || x_scale < 1024i64 || y_scale < 1024i64 { ret Invalid }
    let orig_x = (x << 4u32) + ((2i32 * m.mv_col) >> g.sub_x) + 8i32
    let orig_y = (y << 4u32) + ((2i32 * m.mv_row) >> g.sub_y) + 8i32
    let base_x = i64(orig_x) * x_scale - (8i64 << 14u32)
    let base_y = i64(orig_y) * y_scale - (8i64 << 14u32)
    let start_x = i32(round2_signed_64(base_x, 8u32)) + 32i32
    let start_y = i32(round2_signed_64(base_y, 8u32)) + 32i32
    let step_x = i32(round2_signed_64(x_scale, 4u32))
    let step_y = i32(round2_signed_64(y_scale, 4u32))

    let last_x = ((m.frame.width + i32(g.sub_x)) >> g.sub_x) - 1i32
    let last_y = ((m.frame.height + i32(g.sub_y)) >> g.sub_y) - 1i32
    let ih = (((h - 1i32) * step_y + 1023i32) >> 10u32) + 8i32
    if usize(ih) * usize(w) > wk.inter.len || usize(w) * usize(h) > out.len { ret Invalid }

    let fx = usize(small_filter(m.filter_x, w)) * 128usize
    let fy = usize(small_filter(m.filter_y, h)) * 128usize
    let data = m.frame.data
    var r = 0i32
    while r < ih {
        let ry = clip3(0i32, last_y, (start_y >> 10u32) + r - 3i32)
        let row = usize(ry) * m.frame.stride
        var c = 0i32
        while c < w {
            let p = start_x + step_x * c
            let tap0 = fx + usize((p >> 6u32) & 15i32) * 8usize
            let cx = (p >> 10u32) - 3i32
            var s = 0i32
            var t = 0i32
            while t < 8i32 {
                let px = clip3(0i32, last_x, cx + t)
                s += wk.taps[tap0 + usize(t)] * i32(data[row + usize(px)])
                t += 1i32
            }
            wk.inter[usize(r) * usize(w) + usize(c)] = round2(s, round0)
            c += 1i32
        }
        r += 1i32
    }
    var rr = 0i32
    while rr < h {
        let p = (start_y & 1023i32) + step_y * rr
        let tap0 = fy + usize((p >> 6u32) & 15i32) * 8usize
        let base = usize(p >> 10u32)
        var c = 0i32
        while c < w {
            var s = 0i32
            var t = 0usize
            while t < 8usize {
                s += wk.taps[tap0 + t] * wk.inter[(base + t) * usize(w) + usize(c)]
                t += 1usize
            }
            out[usize(rr) * usize(w) + usize(c)] = round2(s, round1)
            c += 1i32
        }
        rr += 1i32
    }
    ret ok
}

fn rounds(compound: bool, bit_depth: u32) -> (u32, u32) {
    var r0 = 3u32
    var r1 = 11u32
    if compound { r1 = 7u32 }
    if bit_depth == 12u32 {
        r0 = 5u32
        if !compound { r1 = 9u32 }
    }
    ret (r0, r1)
}

fn distance_weights(dist0: i32, dist1: i32) -> (i32, i32) {
    let d0 = dist1
    let d1 = dist0
    var order = 0usize
    if d0 <= d1 { order = 1usize }
    let wt = quant_dist_weight()
    let lk = quant_dist_lookup()
    var i = 3usize
    if d0 != 0i32 && d1 != 0i32 {
        i = 0usize
        while i < 3usize {
            let c0 = i32(wt[i * 2usize + order])
            let c1 = i32(wt[i * 2usize + 1usize - order])
            if order == 1usize {
                if d0 * c0 > d1 * c1 { break }
            } else {
                if d0 * c0 < d1 * c1 { break }
            }
            i += 1usize
        }
    }
    ret (i32(lk[i * 2usize + order]), i32(lk[i * 2usize + 1usize - order]))
}

fn predict_inter(wk: Work, g: Geom, m0: Motion, m1: Motion, compound: bool, blend: Blend, dst: []u16, dst_stride: usize) -> err {
    let (r0, r1) = rounds(compound, g.bit_depth)
    let post = 14u32 - (r0 + r1)
    let maxv = (1i32 << g.bit_depth) - 1i32
    try block_pred(wk, m0, g, g.x, g.y, g.w, g.h, r0, r1, wk.p0)
    if compound { try block_pred(wk, m1, g, g.x, g.y, g.w, g.h, r0, r1, wk.p1) }
    var i = 0i32
    while i < g.h {
        var j = 0i32
        while j < g.w {
            let k = usize(i) * usize(g.w) + usize(j)
            let a0 = wk.p0[k]
            var v = 0i32
            if !compound {
                v = a0
            } else if blend.kind == KIND_AVERAGE {
                v = round2(a0 + wk.p1[k], 1u32 + post)
            } else if blend.kind == KIND_DISTANCE {
                v = round2(blend.fwd * a0 + blend.bck * wk.p1[k], 4u32 + post)
            } else {
                var mk = 0i32
                let mi = usize(i)
                let mj = usize(j)
                let ms = blend.mask_stride
                if g.sub_x == 0u32 && g.sub_y == 0u32 {
                    mk = i32(blend.mask[mi * ms + mj])
                } else if g.sub_x != 0u32 && g.sub_y == 0u32 {
                    mk = round2(i32(blend.mask[mi * ms + 2usize * mj]) + i32(blend.mask[mi * ms + 2usize * mj + 1usize]), 1u32)
                } else {
                    mk = round2(i32(blend.mask[2usize * mi * ms + 2usize * mj]) + i32(blend.mask[2usize * mi * ms + 2usize * mj + 1usize]) + i32(blend.mask[(2usize * mi + 1usize) * ms + 2usize * mj]) + i32(blend.mask[(2usize * mi + 1usize) * ms + 2usize * mj + 1usize]), 2u32)
                }
                v = round2(mk * a0 + (64i32 - mk) * wk.p1[k], 6u32 + post)
            }
            dst[usize(i) * dst_stride + usize(j)] = u16(clip3(0i32, maxv, v))
            j += 1i32
        }
        i += 1i32
    }
    ret ok
}

fn obmc_mask(len: i32, i: usize) -> i32 {
    let tbl = obmc_masks()
    if len == 2i32 { ret i32(tbl[i]) }
    if len == 4i32 { ret i32(tbl[2usize + i]) }
    if len == 8i32 { ret i32(tbl[6usize + i]) }
    if len == 16i32 { ret i32(tbl[14usize + i]) }
    ret i32(tbl[30usize + i])
}

// pass 0: blend from above (mask by row), pass 1: from the left (mask by column)
fn predict_overlap(wk: Work, g: Geom, nb: Neighbor, pred_x: i32, pred_y: i32, pred_w: i32, pred_h: i32, pass: i32, dst: []u16, dst_stride: usize) -> err {
    let (r0, r1) = rounds(false, g.bit_depth)
    let maxv = (1i32 << g.bit_depth) - 1i32
    try block_pred(wk, nb.motion, g, pred_x, pred_y, pred_w, pred_h, r0, r1, wk.p1)
    var mask_len = pred_h
    if pass == 1i32 { mask_len = pred_w }
    let ox = usize(pred_x - g.x)
    let oy = usize(pred_y - g.y)
    var i = 0i32
    while i < pred_h {
        var j = 0i32
        while j < pred_w {
            var mk = obmc_mask(mask_len, usize(i))
            if pass == 1i32 { mk = obmc_mask(mask_len, usize(j)) }
            let o = clip3(0i32, maxv, wk.p1[usize(i) * usize(pred_w) + usize(j)])
            let at = (oy + usize(i)) * dst_stride + ox + usize(j)
            dst[at] = u16(round2(mk * i32(dst[at]) + (64i32 - mk) * o, 6u32))
            j += 1i32
        }
        i += 1i32
    }
    ret ok
}

fn min_i32(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn overlap(wk: Work, g: Geom, info: ObmcInfo, above: []Neighbor, left: []Neighbor, dst: []u16, dst_stride: usize) -> err {
    if info.avail_u {
        if info.plane_size >= 3i32 {
            var x4 = 0i32
            var count = 0i32
            let limit = min_i32(4i32, info.log2_w)
            let end4 = min_i32(info.cols4, info.w4)
            while count < limit && x4 < end4 {
                let at = usize(x4 | 1i32)
                if at >= above.len { ret Invalid }
                let nb = above[at]
                let step4 = clip3(2i32, 16i32, nb.size4)
                if nb.inter {
                    count += 1i32
                    let pred_w = min_i32(g.w, (step4 * 4i32) >> g.sub_x)
                    let pred_h = min_i32(g.h >> 1u32, 32i32 >> g.sub_y)
                    try predict_overlap(wk, g, nb, g.x + ((x4 * 4i32) >> g.sub_x), g.y, pred_w, pred_h, 0i32, dst, dst_stride)
                }
                x4 += step4
            }
        }
    }
    if info.avail_l {
        var y4 = 0i32
        var count = 0i32
        let limit = min_i32(4i32, info.log2_h)
        let end4 = min_i32(info.rows4, info.h4)
        while count < limit && y4 < end4 {
            let at = usize(y4 | 1i32)
            if at >= left.len { ret Invalid }
            let nb = left[at]
            let step4 = clip3(2i32, 16i32, nb.size4)
            if nb.inter {
                count += 1i32
                let pred_w = min_i32(g.w >> 1u32, 32i32 >> g.sub_x)
                let pred_h = min_i32(g.h, (step4 * 4i32) >> g.sub_y)
                try predict_overlap(wk, g, nb, g.x, g.y + ((y4 * 4i32) >> g.sub_y), pred_w, pred_h, 1i32, dst, dst_stride)
            }
            y4 += step4
        }
    }
    ret ok
}
