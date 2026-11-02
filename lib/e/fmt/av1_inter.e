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
// Invalid: a block larger than 128, an empty frame, a reference outside the 1/16 .. 2x scale range, or a slice
// (reference data, destination, mask-free scratch) too short for the block: the hot loops run under @nocheck
// after those extents were validated once per call.

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
    if x_scale == 16384i64 && y_scale == 16384i64 && g.bit_depth <= 12u32 && round0 >= 1u32 && round0 <= 7u32 && round1 >= 1u32 && round0 + round1 <= 14u32 {
        if usize(h + 7i32) * usize(w) > wk.inter.len || usize(w) * usize(h) > out.len { ret Invalid }
        ret block_pred_unscaled(wk.taps, wk.inter, m.frame.data, m.frame.stride, m.frame.width, m.frame.height, m.mv_row, m.mv_col, m.filter_y, m.filter_x, g.sub_x, g.sub_y, x, y, w, h, round0, round1, out)
    }
    ret block_pred_scaled(wk, m, g, x, y, w, h, round0, round1, out, x_scale, y_scale)
}

// The intermediate rows hold sample values plus a bias, so that two adjacent values can be read as
// one i64 and multiplied by a tap in a single instruction: value + value' * 2^32 with both lanes
// positive. A pass over rows (taps sum to 128) leaves lane = result + 128 * bias, which the caller
// removes together with the rounding constant. Samples are at most 12 bits, so |result| < 2^21.
const BIAS_H: i32 = 4194304i32
const OFF_H: i32 = 536870912i32
const BIAS_W: i32 = 131072i32
const OFF_W: i32 = 16777216i32

// With equal sizes the position is exact: start = P * 64 + 32 (P in 1/16 sample), step 1024, so the
// taps are the same for every sample of the block and the whole-sample part is P >> 4. The fast row
// functions run without bounds checks; the extents they touch are validated here, once per call.
fn block_pred_unscaled(taps: []i32, inter: []i32, data: []const u16, stride: usize, fw: i32, fh: i32, mv_row: i32, mv_col: i32, filter_y: i32, filter_x: i32, sub_x: u32, sub_y: u32, x: i32, y: i32, w: i32, h: i32, round0: u32, round1: u32, out: []i32) -> err {
    let px = (x << 4u32) + ((2i32 * mv_col) >> sub_x)
    let py = (y << 4u32) + ((2i32 * mv_row) >> sub_y)
    let ix = px >> 4u32
    let iy = py >> 4u32
    let fx = px & 15i32
    let fy = py & 15i32
    let last_x = ((fw + i32(sub_x)) >> sub_x) - 1i32
    let last_y = ((fh + i32(sub_y)) >> sub_y) - 1i32
    if usize(last_y) * stride + usize(last_x) + 1usize > data.len || taps.len < 768usize { ret Invalid }
    if filter_x < 0i32 || filter_x > 5i32 || filter_y < 0i32 || filter_y > 5i32 { ret Invalid }
    let fxi = small_filter(filter_x, w)
    let fyi = small_filter(filter_y, h)
    let tbx = usize(fxi) * 128usize + usize(fx) * 8usize
    let tby = usize(fyi) * 128usize + usize(fy) * 8usize
    let sh0 = 7u32 - round0
    let add1 = 1i32 << (round1 - 1u32)
    let add0 = 1i32 << (round0 - 1u32)
    let wu = usize(w)
    let x_in = ix >= 3i32 && ix + w + 3i32 <= last_x
    if fx == 0i32 && fy == 0i32 {
        let sh = 14u32 - round0 - round1
        if ix >= 0i32 && ix + w - 1i32 <= last_x {
            copy_rows(data, stride, last_y, ix, iy, wu, usize(h), sh, out)
        } else {
            var r = 0i32
            while r < h {
                let row = usize(clip3(0i32, last_y, iy + r)) * stride
                copy_row(data, row, ix, last_x, w, sh, out, usize(r) * wu)
                r += 1i32
            }
        }
    } else if fy == 0i32 {
        if x_in {
            hpass_fast(data, stride, last_y, ix, iy, 0i32, h, wu, taps, tbx, fxi >= 4i32, add0, round0, out)
        } else {
            hpass_edge(data, stride, last_x, last_y, ix, iy, 0i32, h, w, taps, tbx, add0, round0, out)
        }
        finish_h(out, wu * usize(h), add1, round1)
    } else if fx == 0i32 {
        let xi = ix >= 0i32 && ix + w - 1i32 <= last_x
        let y_in = iy >= 3i32 && iy + h + 3i32 <= last_y
        if xi && y_in {
            let v4 = fyi >= 4i32
            var t_lo = 0i32
            var t_hi = h + 7i32
            if v4 {
                t_lo = 2i32
                t_hi = h + 5i32
            }
            widen_rows(data, stride, ix, iy - 3i32, t_lo, t_hi, wu, inter)
            vinter_all(inter, wu, usize(h), taps, tby, v4, OFF_W, sh0, add1, round1, out)
        } else {
            var rows: [8]usize = zero
            var r = 0i32
            while r < h {
                var t = 0i32
                while t < 8i32 {
                    rows[usize(t)] = usize(clip3(0i32, last_y, iy + r + t - 3i32)) * stride
                    t += 1i32
                }
                vsrc_row(data, rows[..], ix, last_x, w, taps, tby, sh0, add1, round1, out, usize(r) * wu)
                r += 1i32
            }
        }
    } else {
        var t_lo = 0i32
        var t_hi = h + 7i32
        let v4 = fyi >= 4i32
        if v4 {
            t_lo = 2i32
            t_hi = h + 5i32
        }
        if x_in {
            hpass_fast(data, stride, last_y, ix, iy - 3i32, t_lo, t_hi, wu, taps, tbx, fxi >= 4i32, add0, round0, inter)
        } else {
            hpass_edge(data, stride, last_x, last_y, ix, iy - 3i32, t_lo, t_hi, w, taps, tbx, add0, round0, inter)
        }
        vinter_all(inter, wu, usize(h), taps, tby, v4, OFF_H, 0u32, add1, round1, out)
    }
    ret ok
}

fn hpass_edge(src: []const u16, stride: usize, last_x: i32, last_y: i32, ix: i32, y0: i32, t_lo: i32, t_hi: i32, w: i32, taps: []i32, tb: usize, add0: i32, r0: u32, dst: []i32) {
    var t = t_lo
    while t < t_hi {
        let row = usize(clip3(0i32, last_y, y0 + t)) * stride
        hrow_frac(src, row, ix, last_x, w, taps, tb, add0, r0, BIAS_H, dst, usize(t - t_lo) * usize(w))
        t += 1i32
    }
}

fn copy_rows(src: []const u16, stride: usize, last_y: i32, ix: i32, iy: i32, w: usize, h: usize, sh: u32, dst: []i32) {
    var r = 0usize
    while r < h {
        let b = usize(clip3(0i32, last_y, iy + i32(r))) * stride + usize(ix)
        let s = src[b..b + w]
        let d = dst[r * w..r * w + w]
        var c = 0usize
        @nocheck {
        while c + 4usize <= w {
            d[c] = i32(s[c]) << sh
            d[c + 1usize] = i32(s[c + 1usize]) << sh
            d[c + 2usize] = i32(s[c + 2usize]) << sh
            d[c + 3usize] = i32(s[c + 3usize]) << sh
            c += 4usize
        }
        while c < w {
            d[c] = i32(s[c]) << sh
            c += 1usize
        }
        }
        r += 1usize
    }
}

fn widen_rows(src: []const u16, stride: usize, ix: i32, y0: i32, t_lo: i32, t_hi: i32, w: usize, dst: []i32) {
    var t = t_lo
    while t < t_hi {
        let b = usize(y0 + t) * stride + usize(ix)
        let s = src[b..b + w]
        let d = dst[usize(t - t_lo) * w..usize(t - t_lo) * w + w]
        var c = 0usize
        @nocheck {
        while c + 4usize <= w {
            d[c] = i32(s[c]) + BIAS_W
            d[c + 1usize] = i32(s[c + 1usize]) + BIAS_W
            d[c + 2usize] = i32(s[c + 2usize]) + BIAS_W
            d[c + 3usize] = i32(s[c + 3usize]) + BIAS_W
            c += 4usize
        }
        while c < w {
            d[c] = i32(s[c]) + BIAS_W
            c += 1usize
        }
        }
        t += 1i32
    }
}

// (the vertical filter of a whole-sample row is the single tap 128)
fn finish_h(buf: []i32, n: usize, add1: i32, r1: u32) {
    let k = add1 - (BIAS_H << 7u32)
    var c = 0usize
    @nocheck {
    while c + 4usize <= n {
        buf[c] = ((buf[c] << 7u32) + k) >> r1
        buf[c + 1usize] = ((buf[c + 1usize] << 7u32) + k) >> r1
        buf[c + 2usize] = ((buf[c + 2usize] << 7u32) + k) >> r1
        buf[c + 3usize] = ((buf[c + 3usize] << 7u32) + k) >> r1
        c += 4usize
    }
    while c < n {
        buf[c] = ((buf[c] << 7u32) + k) >> r1
        c += 1usize
    }
    }
}
// Rows t_lo .. t_hi - 1 (source row y0 + t, clamped) of w outputs each, written to dst at (t - t_lo) * w as
// value + BIAS_H. The columns ix - 3 .. ix + w + 3 must be inside the frame. tap4: only taps 2..5 are nonzero.
// Two outputs per 64-bit product: output c needs tap k on sample c + k, output c + 1 needs tap k - 1 on
// that same sample, so sample c + m is multiplied by (t_m | t_(m-1) << 32).
fn hpass_fast(src: []const u16, stride: usize, last_y: i32, ix: i32, y0: i32, t_lo: i32, t_hi: i32, w: usize, taps: []i32, tb: usize, tap4: bool, add0: i32, r0: u32, dst: []i32) {
    let t0 = i64(taps[tb])
    let t1 = i64(taps[tb + 1usize])
    let t2 = i64(taps[tb + 2usize])
    let t3 = i64(taps[tb + 3usize])
    let t4 = i64(taps[tb + 4usize])
    let t5 = i64(taps[tb + 5usize])
    let t6 = i64(taps[tb + 6usize])
    let t7 = i64(taps[tb + 7usize])
    let ini = i64(add0 + (BIAS_H << r0))
    let init = ini + (ini << 32u32)
    let col = usize(ix - 3i32)
    var t = t_lo
    if tap4 {
        let p2 = t2
        let p3 = t3 + (t2 << 32u32)
        let p4 = t4 + (t3 << 32u32)
        let p5 = t5 + (t4 << 32u32)
        let p6 = t5 << 32u32
        let u2 = taps[tb + 2usize]
        let u3 = taps[tb + 3usize]
        let u4 = taps[tb + 4usize]
        let u5 = taps[tb + 5usize]
        while t < t_hi {
            let b0 = usize(clip3(0i32, last_y, y0 + t)) * stride + col
            let s = src[b0..b0 + w + 7usize]
            let o = usize(t - t_lo) * w
            let d = dst[o..o + w]
            var c = 0usize
            @nocheck {
            while c + 4usize <= w {
                let a2 = i64(s[c + 2usize])
                let a3 = i64(s[c + 3usize])
                let a4 = i64(s[c + 4usize])
                let a5 = i64(s[c + 5usize])
                let a6 = i64(s[c + 6usize])
                let a7 = i64(s[c + 7usize])
                let a8 = i64(s[c + 8usize])
                let q = init + p2 * a2 + p3 * a3 + p4 * a4 + p5 * a5 + p6 * a6
                let r = init + p2 * a4 + p3 * a5 + p4 * a6 + p5 * a7 + p6 * a8
                d[c] = i32(q) >> r0
                d[c + 1usize] = i32(q >> 32u32) >> r0
                d[c + 2usize] = i32(r) >> r0
                d[c + 3usize] = i32(r >> 32u32) >> r0
                c += 4usize
            }
            while c + 2usize <= w {
                let q = init + p2 * i64(s[c + 2usize]) + p3 * i64(s[c + 3usize]) + p4 * i64(s[c + 4usize]) + p5 * i64(s[c + 5usize]) + p6 * i64(s[c + 6usize])
                d[c] = i32(q) >> r0
                d[c + 1usize] = i32(q >> 32u32) >> r0
                c += 2usize
            }
            if c < w {
                let u = u2 * i32(s[c + 2usize]) + u3 * i32(s[c + 3usize]) + u4 * i32(s[c + 4usize]) + u5 * i32(s[c + 5usize])
                d[c] = ((u + add0) >> r0) + BIAS_H
            }
            }
            t += 1i32
        }
    } else {
        let p0 = t0
        let p1 = t1 + (t0 << 32u32)
        let p2 = t2 + (t1 << 32u32)
        let p3 = t3 + (t2 << 32u32)
        let p4 = t4 + (t3 << 32u32)
        let p5 = t5 + (t4 << 32u32)
        let p6 = t6 + (t5 << 32u32)
        let p7 = t7 + (t6 << 32u32)
        let p8 = t7 << 32u32
        let u0 = taps[tb]
        let u1 = taps[tb + 1usize]
        let u2 = taps[tb + 2usize]
        let u3 = taps[tb + 3usize]
        let u4 = taps[tb + 4usize]
        let u5 = taps[tb + 5usize]
        let u6 = taps[tb + 6usize]
        let u7 = taps[tb + 7usize]
        while t < t_hi {
            let b0 = usize(clip3(0i32, last_y, y0 + t)) * stride + col
            let s = src[b0..b0 + w + 7usize]
            let o = usize(t - t_lo) * w
            let d = dst[o..o + w]
            var c = 0usize
            @nocheck {
            while c + 4usize <= w {
                let a0 = i64(s[c])
                let a1 = i64(s[c + 1usize])
                let a2 = i64(s[c + 2usize])
                let a3 = i64(s[c + 3usize])
                let a4 = i64(s[c + 4usize])
                let a5 = i64(s[c + 5usize])
                let a6 = i64(s[c + 6usize])
                let a7 = i64(s[c + 7usize])
                let a8 = i64(s[c + 8usize])
                let a9 = i64(s[c + 9usize])
                let a10 = i64(s[c + 10usize])
                let q = init + p0 * a0 + p1 * a1 + p2 * a2 + p3 * a3 + p4 * a4 + p5 * a5 + p6 * a6 + p7 * a7 + p8 * a8
                let r = init + p0 * a2 + p1 * a3 + p2 * a4 + p3 * a5 + p4 * a6 + p5 * a7 + p6 * a8 + p7 * a9 + p8 * a10
                d[c] = i32(q) >> r0
                d[c + 1usize] = i32(q >> 32u32) >> r0
                d[c + 2usize] = i32(r) >> r0
                d[c + 3usize] = i32(r >> 32u32) >> r0
                c += 4usize
            }
            while c + 2usize <= w {
                let q = init + p0 * i64(s[c]) + p1 * i64(s[c + 1usize]) + p2 * i64(s[c + 2usize]) + p3 * i64(s[c + 3usize]) + p4 * i64(s[c + 4usize]) + p5 * i64(s[c + 5usize]) + p6 * i64(s[c + 6usize]) + p7 * i64(s[c + 7usize]) + p8 * i64(s[c + 8usize])
                d[c] = i32(q) >> r0
                d[c + 1usize] = i32(q >> 32u32) >> r0
                c += 2usize
            }
            if c < w {
                let u = u0 * i32(s[c]) + u1 * i32(s[c + 1usize]) + u2 * i32(s[c + 2usize]) + u3 * i32(s[c + 3usize]) + u4 * i32(s[c + 4usize]) + u5 * i32(s[c + 5usize]) + u6 * i32(s[c + 6usize]) + u7 * i32(s[c + 7usize])
                d[c] = ((u + add0) >> r0) + BIAS_H
            }
            }
            t += 1i32
        }
    }
}

// inter: h + 7 rows (8-tap) or h + 3 rows starting at tap row 2 (4-tap) of w biased values (bias * 128 == off).
// Result: (((sum - off) << sh) + add1) >> r1
fn vinter_all(inter: []i32, w: usize, h: usize, taps: []i32, tb: usize, tap4: bool, off: i32, sh: u32, add1: i32, r1: u32, dst: []i32) {
    let t0 = i64(taps[tb])
    let t1 = i64(taps[tb + 1usize])
    let t2 = i64(taps[tb + 2usize])
    let t3 = i64(taps[tb + 3usize])
    let t4 = i64(taps[tb + 4usize])
    let t5 = i64(taps[tb + 5usize])
    let t6 = i64(taps[tb + 6usize])
    let t7 = i64(taps[tb + 7usize])
    let k = add1 - (off << sh)
    var rr = 0usize
    @nocheck {
    while rr < h {
        let b0 = rr * w
        let b1 = b0 + w
        let b2 = b1 + w
        let b3 = b2 + w
        var c = 0usize
        if tap4 {
            while c + 2usize <= w {
                let a = t2 * *mem.cast[*i64](&inter[b0 + c]) + t3 * *mem.cast[*i64](&inter[b1 + c]) + t4 * *mem.cast[*i64](&inter[b2 + c]) + t5 * *mem.cast[*i64](&inter[b3 + c])
                dst[b0 + c] = ((i32(a) << sh) + k) >> r1
                dst[b0 + c + 1usize] = ((i32(a >> 32u32) << sh) + k) >> r1
                c += 2usize
            }
            if c < w {
                let s = taps[tb + 2usize] * inter[b0 + c] + taps[tb + 3usize] * inter[b1 + c] + taps[tb + 4usize] * inter[b2 + c] + taps[tb + 5usize] * inter[b3 + c]
                dst[b0 + c] = ((s << sh) + k) >> r1
            }
        } else {
            let b4 = b3 + w
            let b5 = b4 + w
            let b6 = b5 + w
            let b7 = b6 + w
            while c + 2usize <= w {
                let a = t0 * *mem.cast[*i64](&inter[b0 + c]) + t1 * *mem.cast[*i64](&inter[b1 + c]) + t2 * *mem.cast[*i64](&inter[b2 + c]) + t3 * *mem.cast[*i64](&inter[b3 + c]) + t4 * *mem.cast[*i64](&inter[b4 + c]) + t5 * *mem.cast[*i64](&inter[b5 + c]) + t6 * *mem.cast[*i64](&inter[b6 + c]) + t7 * *mem.cast[*i64](&inter[b7 + c])
                dst[b0 + c] = ((i32(a) << sh) + k) >> r1
                dst[b0 + c + 1usize] = ((i32(a >> 32u32) << sh) + k) >> r1
                c += 2usize
            }
            if c < w {
                let s = taps[tb] * inter[b0 + c] + taps[tb + 1usize] * inter[b1 + c] + taps[tb + 2usize] * inter[b2 + c] + taps[tb + 3usize] * inter[b3 + c] + taps[tb + 4usize] * inter[b4 + c] + taps[tb + 5usize] * inter[b5 + c] + taps[tb + 6usize] * inter[b6 + c] + taps[tb + 7usize] * inter[b7 + c]
                dst[b0 + c] = ((s << sh) + k) >> r1
            }
        }
        rr += 1usize
    }
    }
}

fn copy_row(src: []const u16, row: usize, ix: i32, last_x: i32, w: i32, sh: u32, dst: []i32, doff: usize) {
    let cl = clip3(0i32, w, 0i32 - ix)
    let cr = clip3(cl, w, last_x + 1i32 - ix)
    var c = 0i32
    while c < w {
        if c >= cl && c < cr {
            var b = row + usize(ix + c)
            while c < cr {
                dst[doff + usize(c)] = i32(src[b]) << sh
                b += 1usize
                c += 1i32
            }
        } else {
            dst[doff + usize(c)] = i32(src[row + usize(clip3(0i32, last_x, ix + c))]) << sh
            c += 1i32
        }
    }
}

fn hrow_frac(src: []const u16, row: usize, ix: i32, last_x: i32, w: i32, taps: []i32, tb: usize, add0: i32, r0: u32, bias: i32, dst: []i32, doff: usize) {
    let t0 = taps[tb]
    let t1 = taps[tb + 1usize]
    let t2 = taps[tb + 2usize]
    let t3 = taps[tb + 3usize]
    let t4 = taps[tb + 4usize]
    let t5 = taps[tb + 5usize]
    let t6 = taps[tb + 6usize]
    let t7 = taps[tb + 7usize]
    let cl = clip3(0i32, w, 3i32 - ix)
    let cr = clip3(cl, w, last_x - 3i32 - ix)
    var c = 0i32
    while c < w {
        if c >= cl && c < cr {
            var b = row + usize(ix + c - 3i32)
            while c < cr {
                let s = t0 * i32(src[b]) + t1 * i32(src[b + 1usize]) + t2 * i32(src[b + 2usize]) + t3 * i32(src[b + 3usize]) + t4 * i32(src[b + 4usize]) + t5 * i32(src[b + 5usize]) + t6 * i32(src[b + 6usize]) + t7 * i32(src[b + 7usize])
                dst[doff + usize(c)] = ((s + add0) >> r0) + bias
                b += 1usize
                c += 1i32
            }
        } else {
            var s = 0i32
            var t = 0i32
            while t < 8i32 {
                s += taps[tb + usize(t)] * i32(src[row + usize(clip3(0i32, last_x, ix + c - 3i32 + t))])
                t += 1i32
            }
            dst[doff + usize(c)] = ((s + add0) >> r0) + bias
            c += 1i32
        }
    }
}
fn vsrc_row(src: []const u16, rows: []usize, ix: i32, last_x: i32, w: i32, taps: []i32, tb: usize, sh: u32, add1: i32, r1: u32, dst: []i32, doff: usize) {
    let t0 = taps[tb]
    let t1 = taps[tb + 1usize]
    let t2 = taps[tb + 2usize]
    let t3 = taps[tb + 3usize]
    let t4 = taps[tb + 4usize]
    let t5 = taps[tb + 5usize]
    let t6 = taps[tb + 6usize]
    let t7 = taps[tb + 7usize]
    let q0 = rows[0usize]
    let q1 = rows[1usize]
    let q2 = rows[2usize]
    let q3 = rows[3usize]
    let q4 = rows[4usize]
    let q5 = rows[5usize]
    let q6 = rows[6usize]
    let q7 = rows[7usize]
    let cl = clip3(0i32, w, 0i32 - ix)
    let cr = clip3(cl, w, last_x + 1i32 - ix)
    var c = 0i32
    while c < w {
        var b = usize(clip3(0i32, last_x, ix + c))
        if c >= cl && c < cr {
            while c < cr {
                let s = t0 * i32(src[q0 + b]) + t1 * i32(src[q1 + b]) + t2 * i32(src[q2 + b]) + t3 * i32(src[q3 + b]) + t4 * i32(src[q4 + b]) + t5 * i32(src[q5 + b]) + t6 * i32(src[q6 + b]) + t7 * i32(src[q7 + b])
                dst[doff + usize(c)] = ((s << sh) + add1) >> r1
                b += 1usize
                c += 1i32
            }
        } else {
            let s = t0 * i32(src[q0 + b]) + t1 * i32(src[q1 + b]) + t2 * i32(src[q2 + b]) + t3 * i32(src[q3 + b]) + t4 * i32(src[q4 + b]) + t5 * i32(src[q5 + b]) + t6 * i32(src[q6 + b]) + t7 * i32(src[q7 + b])
            dst[doff + usize(c)] = ((s << sh) + add1) >> r1
            c += 1i32
        }
    }
}
fn block_pred_scaled(wk: Work, m: Motion, g: Geom, x: i32, y: i32, w: i32, h: i32, round0: u32, round1: u32, out: []i32, x_scale: i64, y_scale: i64) -> err {
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

// When the block is an exact copy of the reference (no scaling, whole-sample vector, inside the frame)
// answers (true, index of the first sample in the reference data).
fn int_src(len: usize, stride: usize, fw: i32, fh: i32, mv_row: i32, mv_col: i32, g: Geom) -> (bool, usize) {
    if g.cur_w < 1i32 || g.cur_h < 1i32 || fw < 1i32 || fh < 1i32 { ret (false, 0usize) }
    if fw != g.cur_w || fh != g.cur_h { ret (false, 0usize) }
    let px = (g.x << 4u32) + ((2i32 * mv_col) >> g.sub_x)
    let py = (g.y << 4u32) + ((2i32 * mv_row) >> g.sub_y)
    if (px & 15i32) != 0i32 || (py & 15i32) != 0i32 { ret (false, 0usize) }
    let ix = px >> 4u32
    let iy = py >> 4u32
    let last_x = ((fw + i32(g.sub_x)) >> g.sub_x) - 1i32
    let last_y = ((fh + i32(g.sub_y)) >> g.sub_y) - 1i32
    if ix < 0i32 || iy < 0i32 || ix + g.w - 1i32 > last_x || iy + g.h - 1i32 > last_y { ret (false, 0usize) }
    if usize(last_y) * stride + usize(last_x) + 1usize > len { ret (false, 0usize) }
    ret (true, usize(iy) * stride + usize(ix))
}

fn copy_block(src: []const u16, s0: usize, s_stride: usize, dst: []u16, dst_stride: usize, w: usize, h: usize, maxv: i32) {
    var i = 0usize
    while i < h {
        let s = src[s0 + i * s_stride..s0 + i * s_stride + w]
        let d = dst[i * dst_stride..i * dst_stride + w]
        var j = 0usize
        @nocheck {
        while j + 4usize <= w {
            d[j] = u16(clip3(0i32, maxv, i32(s[j])))
            d[j + 1usize] = u16(clip3(0i32, maxv, i32(s[j + 1usize])))
            d[j + 2usize] = u16(clip3(0i32, maxv, i32(s[j + 2usize])))
            d[j + 3usize] = u16(clip3(0i32, maxv, i32(s[j + 3usize])))
            j += 4usize
        }
        while j < w {
            d[j] = u16(clip3(0i32, maxv, i32(s[j])))
            j += 1usize
        }
        }
        i += 1usize
    }
}

// both whole-sample sources: the average / distance weighted blend reduces to plain shifts of the samples
fn blend_int(a: []const u16, a0: usize, a_stride: usize, b: []const u16, b0: usize, b_stride: usize, dst: []u16, dst_stride: usize, w: usize, h: usize, maxv: i32, kind: i32, fwd: i32, bck: i32) {
    var i = 0usize
    while i < h {
        let sa = a[a0 + i * a_stride..a0 + i * a_stride + w]
        let sb = b[b0 + i * b_stride..b0 + i * b_stride + w]
        let d = dst[i * dst_stride..i * dst_stride + w]
        var j = 0usize
        @nocheck {
        if kind == KIND_AVERAGE {
            while j + 4usize <= w {
                d[j] = u16(clip3(0i32, maxv, (i32(sa[j]) + i32(sb[j]) + 1i32) >> 1u32))
                d[j + 1usize] = u16(clip3(0i32, maxv, (i32(sa[j + 1usize]) + i32(sb[j + 1usize]) + 1i32) >> 1u32))
                d[j + 2usize] = u16(clip3(0i32, maxv, (i32(sa[j + 2usize]) + i32(sb[j + 2usize]) + 1i32) >> 1u32))
                d[j + 3usize] = u16(clip3(0i32, maxv, (i32(sa[j + 3usize]) + i32(sb[j + 3usize]) + 1i32) >> 1u32))
                j += 4usize
            }
            while j < w {
                d[j] = u16(clip3(0i32, maxv, (i32(sa[j]) + i32(sb[j]) + 1i32) >> 1u32))
                j += 1usize
            }
        } else {
            while j < w {
                d[j] = u16(clip3(0i32, maxv, (fwd * i32(sa[j]) + bck * i32(sb[j]) + 8i32) >> 4u32))
                j += 1usize
            }
        }
        }
        i += 1usize
    }
}

fn comb_single(p0: []i32, w: usize, h: usize, maxv: i32, dst: []u16, dst_stride: usize) {
    var i = 0usize
    while i < h {
        let s = p0[i * w..i * w + w]
        let d = dst[i * dst_stride..i * dst_stride + w]
        var j = 0usize
        @nocheck {
        while j + 4usize <= w {
            d[j] = u16(clip3(0i32, maxv, s[j]))
            d[j + 1usize] = u16(clip3(0i32, maxv, s[j + 1usize]))
            d[j + 2usize] = u16(clip3(0i32, maxv, s[j + 2usize]))
            d[j + 3usize] = u16(clip3(0i32, maxv, s[j + 3usize]))
            j += 4usize
        }
        while j < w {
            d[j] = u16(clip3(0i32, maxv, s[j]))
            j += 1usize
        }
        }
        i += 1usize
    }
}

fn comb_avg(p0: []i32, p1: []i32, w: usize, h: usize, sh: u32, maxv: i32, dst: []u16, dst_stride: usize) {
    let add = 1i32 << (sh - 1u32)
    var i = 0usize
    while i < h {
        let s0 = p0[i * w..i * w + w]
        let s1 = p1[i * w..i * w + w]
        let d = dst[i * dst_stride..i * dst_stride + w]
        var j = 0usize
        @nocheck {
        while j + 4usize <= w {
            d[j] = u16(clip3(0i32, maxv, (s0[j] + s1[j] + add) >> sh))
            d[j + 1usize] = u16(clip3(0i32, maxv, (s0[j + 1usize] + s1[j + 1usize] + add) >> sh))
            d[j + 2usize] = u16(clip3(0i32, maxv, (s0[j + 2usize] + s1[j + 2usize] + add) >> sh))
            d[j + 3usize] = u16(clip3(0i32, maxv, (s0[j + 3usize] + s1[j + 3usize] + add) >> sh))
            j += 4usize
        }
        while j < w {
            d[j] = u16(clip3(0i32, maxv, (s0[j] + s1[j] + add) >> sh))
            j += 1usize
        }
        }
        i += 1usize
    }
}

fn comb_dist(p0: []i32, p1: []i32, w: usize, h: usize, sh: u32, fwd: i32, bck: i32, maxv: i32, dst: []u16, dst_stride: usize) {
    let add = 1i32 << (sh - 1u32)
    var i = 0usize
    while i < h {
        let s0 = p0[i * w..i * w + w]
        let s1 = p1[i * w..i * w + w]
        let d = dst[i * dst_stride..i * dst_stride + w]
        var j = 0usize
        @nocheck {
        while j + 4usize <= w {
            d[j] = u16(clip3(0i32, maxv, (fwd * s0[j] + bck * s1[j] + add) >> sh))
            d[j + 1usize] = u16(clip3(0i32, maxv, (fwd * s0[j + 1usize] + bck * s1[j + 1usize] + add) >> sh))
            d[j + 2usize] = u16(clip3(0i32, maxv, (fwd * s0[j + 2usize] + bck * s1[j + 2usize] + add) >> sh))
            d[j + 3usize] = u16(clip3(0i32, maxv, (fwd * s0[j + 3usize] + bck * s1[j + 3usize] + add) >> sh))
            j += 4usize
        }
        while j < w {
            d[j] = u16(clip3(0i32, maxv, (fwd * s0[j] + bck * s1[j] + add) >> sh))
            j += 1usize
        }
        }
        i += 1usize
    }
}

fn predict_inter(wk: Work, g: Geom, m0: Motion, m1: Motion, compound: bool, blend: Blend, dst: []u16, dst_stride: usize) -> err {
    let (r0, r1) = rounds(compound, g.bit_depth)
    let post = 14u32 - (r0 + r1)
    let maxv = (1i32 << g.bit_depth) - 1i32
    let w = usize(g.w)
    let hh = usize(g.h)
    if g.w >= 1i32 && g.h >= 1i32 && g.w <= 128i32 && g.h <= 128i32 && (hh - 1usize) * dst_stride + w <= dst.len && g.bit_depth <= 12u32 {
        let (k0, a0) = int_src(m0.frame.data.len, m0.frame.stride, m0.frame.width, m0.frame.height, m0.mv_row, m0.mv_col, g)
        if k0 && !compound {
            copy_block(m0.frame.data, a0, m0.frame.stride, dst, dst_stride, w, hh, maxv)
            ret ok
        }
        if k0 && compound && (blend.kind == KIND_AVERAGE || blend.kind == KIND_DISTANCE) {
            let (k1, b0) = int_src(m1.frame.data.len, m1.frame.stride, m1.frame.width, m1.frame.height, m1.mv_row, m1.mv_col, g)
            if k1 {
                blend_int(m0.frame.data, a0, m0.frame.stride, m1.frame.data, b0, m1.frame.stride, dst, dst_stride, w, hh, maxv, blend.kind, blend.fwd, blend.bck)
                ret ok
            }
        }
    }
    try block_pred(wk, m0, g, g.x, g.y, g.w, g.h, r0, r1, wk.p0)
    if compound { try block_pred(wk, m1, g, g.x, g.y, g.w, g.h, r0, r1, wk.p1) }
    if hh > 0usize && (hh - 1usize) * dst_stride + w > dst.len { ret Invalid }
    let p0 = wk.p0
    let p1 = wk.p1
    if !compound {
        comb_single(p0, w, hh, maxv, dst, dst_stride)
    } else if blend.kind == KIND_AVERAGE {
        comb_avg(p0, p1, w, hh, 1u32 + post, maxv, dst, dst_stride)
    } else if blend.kind == KIND_DISTANCE {
        comb_dist(p0, p1, w, hh, 4u32 + post, blend.fwd, blend.bck, maxv, dst, dst_stride)
    } else {
        let sx = g.sub_x != 0u32
        let sy = g.sub_y != 0u32
        let sh = 6u32 + post
        let add = 1i32 << (sh - 1u32)
        let ms = blend.mask_stride
        let mk_data = blend.mask
        var i = 0usize
        while i < hh {
            let o = i * w
            let d = i * dst_stride
            var j = 0usize
            while j < w {
                var mk = 0i32
                if !sx && !sy {
                    mk = i32(mk_data[i * ms + j])
                } else if sx && !sy {
                    mk = (i32(mk_data[i * ms + 2usize * j]) + i32(mk_data[i * ms + 2usize * j + 1usize]) + 1i32) >> 1u32
                } else {
                    mk = (i32(mk_data[2usize * i * ms + 2usize * j]) + i32(mk_data[2usize * i * ms + 2usize * j + 1usize]) + i32(mk_data[(2usize * i + 1usize) * ms + 2usize * j]) + i32(mk_data[(2usize * i + 1usize) * ms + 2usize * j + 1usize]) + 2i32) >> 2u32
                }
                dst[d + j] = u16(clip3(0i32, maxv, (mk * p0[o + j] + (64i32 - mk) * p1[o + j] + add) >> sh))
                j += 1usize
            }
            i += 1usize
        }
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

fn blend_rows(p1: []i32, mt: []i32, pw: usize, ph: usize, pass: i32, maxv: i32, dst: []u16, at: usize, dst_stride: usize) {
    var i = 0usize
    @nocheck {
    while i < ph {
        let at0 = at + i * dst_stride
        let o1 = i * pw
        var j = 0usize
        if pass == 1i32 {
            while j < pw {
                let mk = mt[j]
                let o = clip3(0i32, maxv, p1[o1 + j])
                dst[at0 + j] = u16((mk * i32(dst[at0 + j]) + (64i32 - mk) * o + 32i32) >> 6u32)
                j += 1usize
            }
        } else {
            let mk = mt[i]
            while j < pw {
                let o = clip3(0i32, maxv, p1[o1 + j])
                dst[at0 + j] = u16((mk * i32(dst[at0 + j]) + (64i32 - mk) * o + 32i32) >> 6u32)
                j += 1usize
            }
        }
        i += 1usize
    }
    }
}

// pass 0: blend from above (mask by row), pass 1: from the left (mask by column)
fn predict_overlap(wk: Work, g: Geom, nb: Neighbor, pred_x: i32, pred_y: i32, pred_w: i32, pred_h: i32, pass: i32, dst: []u16, dst_stride: usize) -> err {
    let (r0, r1) = rounds(false, g.bit_depth)
    let maxv = (1i32 << g.bit_depth) - 1i32
    try block_pred(wk, nb.motion, g, pred_x, pred_y, pred_w, pred_h, r0, r1, wk.p1)
    var mask_len = pred_h
    if pass == 1i32 { mask_len = pred_w }
    var mt: [128]i32 = zero
    var k = 0usize
    while k < usize(mask_len) {
        mt[k] = obmc_mask(mask_len, k)
        k += 1usize
    }
    if pred_x < g.x || pred_y < g.y { ret Invalid }
    let ox = usize(pred_x - g.x)
    let oy = usize(pred_y - g.y)
    let pw = usize(pred_w)
    let ph = usize(pred_h)
    let at = oy * dst_stride + ox
    if at + (ph - 1usize) * dst_stride + pw > dst.len { ret Invalid }
    blend_rows(wk.p1, mt[..], pw, ph, pass, maxv, dst, at, dst_stride)
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
