
// AV1 loop restoration (Wiener and self-guided filters), spec section 7.17, no superres, 8-bit samples.
//
// `restore_plane` restores one plane. `cdef` is the CDEF output, `pre` the deblocked frame before CDEF
// (the spec's UpscaledCdefFrame and UpscaledCurrFrame); `out` receives the spec's LrFrame: it is first made
// a copy of `cdef`, then each restoration unit is filtered. All three planes share `stride` (samples) and
// need only the plane's own size, Round2(frame_w, sub_x) by Round2(frame_h, sub_y); `sub_x`/`sub_y` are
// the plane's subsampling (0 for luma). `unit_size` is LoopRestorationSize[plane] in plane samples, and
// `units` the LrUnit of every restoration unit, row-major with unit_cols per row, where
// unit_cols = count_units(unit_size, plane width) and the rows likewise (`count_units` below).
// Call it only for planes whose FrameRestorationType is not RESTORE_NONE (others are the copy).
// The output equals the spec's 4x4-block loop because filtering is done on rectangles of at most 64x64
// inside one stripe and one unit, which the spec notes gives the same result. `bit_depth` must be 8
// (Invalid otherwise).
//
// The scratch space (about 90 KB) comes from the arena and is released again before the call returns.
// The inner loops are unchecked: the sample slices are checked against the plane size once, up front
// (Invalid when a plane slice is too short), and every other index is bounded by the fixed scratch sizes.
// The vector loops work on eight columns at a time and so read and write a few lanes past the end of a
// row of the block; the scratch rows are wide enough for that and those lanes never reach the output.
//
// The block's window is widened to i16 once. Wiener: 7-tap passes of madd_i16 on the symmetric pair
// sums, the horizontal one clamped to its 14-bit range, the vertical one packed straight to u8.
// Self-guided: the column and box sums of the samples and of their squares (madd_i16) are formed for
// eight positions at a time, p * s is evaluated in 32 bits (p is clamped at the value past which z is
// 255 anyway, so the product stays below 2^31), the A values (at most 256) are looked up one by one
// and kept as i16, and the weighted neighbour sums and the final projection are vectors again.

use e.mem
use e.simd

const RESTORE_NONE: u32 = 0u32
const RESTORE_WIENER: u32 = 1u32
const RESTORE_SGRPROJ: u32 = 2u32

// rtype is LrType (RESTORE_*); wiener is LrWiener[..][0] (vertical, 3 taps) then LrWiener[..][1] (horizontal);
// xqd0/xqd1 are LrSgrXqd.
type LrUnit = struct { rtype: u32, wiener: [6]i32, sgr_set: u32, xqd0: i32, xqd1: i32 }

type Src = struct { pre: []const u8, cdef: []const u8, stride: usize, end_x: i32, end_y: i32, stripe_start: i32, stripe_end: i32 }

// win: the (h + 6) by (w + 6) window of source samples around a block (stride WIN); inter: wiener's
// horizontal pass; flt0/flt1: the two self-guided filter outputs; a_arr/b_arr: the box filter's A and B
// (stride AB, A as i16); cola/colb: column sums of one row of boxes; a2tab: the A value for each z
type Scratch = struct { win: []i16, inter: []i16, flt0: []i32, flt1: []i32, a_arr: []i16, b_arr: []i32, cola: []i32, colb: []i16, a2tab: []i32 }

error Invalid

const WIN: usize = 70usize
const AB: usize = 72usize
const FL: usize = 64usize

fn count_units(unit_size: u32, frame_size: u32) -> u32 {
    let n = (frame_size + (unit_size >> 1u32)) / unit_size
    if n < 1u32 { ret 1u32 }
    ret n
}

fn sgr_params() -> str {
    ret "\x02\x0c\x01\x04\x02\x0f\x01\x06\x02\x12\x01\x08\x02\x15\x01\x09\x02\x18\x01\x0a\x02\x1d\x01\x0b\x02\x24\x01\x0c\x02\x2d\x01\x0d\x02\x38\x01\x0e\x02\x44\x01\x0f\x00\x00\x01\x05\x00\x00\x01\x08\x00\x00\x01\x0b\x00\x00\x01\x0e\x02\x1e\x00\x00\x02\x4b\x00\x00"
}

fn imin(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn imax(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

// The w by h samples at the top left of a plane, a row at a time and eight samples per move.
fn copy_plane(src: []const u8, dst: []u8, stride: usize, w: usize, h: usize) {
    if w == 0usize || h == 0usize { ret }
    let last = (h - 1usize) * stride + w - 1usize
    dst[last] = src[last]
    let w4 = w & ~7usize
    var y = 0usize
    @nocheck {
    while y < h {
        let base = y * stride
        var x = 0usize
        while x < w4 {
            *mem.cast[*u64](&dst[base + x]) = *mem.cast[*u64](&src[base + x])
            x += 8usize
        }
        while x < w {
            dst[base + x] = src[base + x]
            x += 1usize
        }
        y += 1usize
    }
    }
}

// Fills the window of the block at (x, y), w by h, from the stripe-aware source of the spec (rows
// outside the stripe come from the deblocked frame, at most two beyond it).
fn stage(win: []i16, s: *const Src, x: i32, y: i32, w: i32, h: i32) {
    let ww = usize(w + 6i32)
    let inside = x >= 3i32 && x + w + 3i32 <= s.end_x + 1i32
    var iy = 0i32
    while iy < h + 6i32 {
        var yc = imax(0i32, imin(s.end_y, y - 3i32 + iy))
        var srow = s.cdef
        if yc < s.stripe_start {
            yc = imax(s.stripe_start - 2i32, yc)
            srow = s.pre
        } else if yc > s.stripe_end {
            yc = imin(s.stripe_end + 2i32, yc)
            srow = s.pre
        }
        let rb = usize(yc) * s.stride
        let wb = usize(iy) * WIN
        if inside {
            let xb = rb + usize(x - 3i32)
            var k = 0usize
            let z8 = simd.splat[Vec[u8, 16]](0u8)
            @nocheck {
            while k + 16usize <= ww {
                let v = simd.load[Vec[u8, 16]](srow, xb + k)
                simd.store[Vec[i16, 8]](win, wb + k, mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](v, z8)))
                simd.store[Vec[i16, 8]](win, wb + k + 8usize, mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](v, z8)))
                k += 16usize
            }
            while k < ww {
                win[wb + k] = i16(srow[xb + k])
                k += 1usize
            }
            }
        } else {
            var jx = 0usize
            while jx < ww {
                let xs = imax(0i32, imin(s.end_x, x - 3i32 + i32(jx)))
                win[wb + jx] = i16(srow[rb + usize(xs)])
                jx += 1usize
            }
        }
        iy += 1i32
    }
}

// One pass of the box filter: the result lands in f (stride FL) and is only meaningful when the radius of
// the pass is nonzero. The A values (at most 256) are kept as i16, the B values as i32, both with the row
// stride AB; row i + 1 of them belongs to the box row centred on window row i.
fn box_filter(win: []const i16, w: usize, h: usize, set: usize, pass: usize, a_arr: []i16, b_arr: []i32, cola: []i32, colb: []i16, a2tab: []const i32, f: []i32) {
    let tab = sgr_params()
    let rr = usize(tab[set * 4usize + pass * 2usize])
    if rr == 0usize { ret }
    let eps = i64(tab[set * 4usize + pass * 2usize + 1usize])
    let nn = i32((2usize * rr + 1usize) * (2usize * rr + 1usize))
    let n2e = i64(nn) * i64(nn) * eps
    let sc = i32(((1i64 << 20u32) + n2e / 2i64) / n2e)
    // past this p the z of the spec is 255; below it p * sc fits 32 bits
    let pmax = i32((266911744i64 + i64(sc) - 1i64) / i64(sc))
    let one_over_n = ((1i32 << 12u32) + nn / 2i32) / nn
    let ww = w + 6usize
    let hi_i = i32(h)
    let z16 = simd.splat[Vec[i16, 8]](0i16)
    let nv = simd.splat[Vec[i32, 4]](nn)
    let scv = simd.splat[Vec[i32, 4]](sc)
    let pmv = simd.splat[Vec[i32, 4]](pmax)
    let rndv = simd.splat[Vec[i32, 4]](524288i32)
    let c255 = simd.splat[Vec[i32, 4]](255i32)
    var zb: [8]i32 = zero
    var sbb: [8]i32 = zero
    var i = 0i32 - 1i32
    @nocheck {
    while i <= hi_i {
        if pass == 1usize || (i & 1i32) != 0i32 {
            // column sums over the 2r + 1 rows around row i, eight columns at a time
            let b0 = (usize(i + 3i32) - rr) * WIN
            var c = 0usize
            if rr == 2usize {
                while c < ww {
                    let v0 = simd.load[Vec[i16, 8]](win, b0 + c)
                    let v1 = simd.load[Vec[i16, 8]](win, b0 + WIN + c)
                    let v2 = simd.load[Vec[i16, 8]](win, b0 + 2usize * WIN + c)
                    let v3 = simd.load[Vec[i16, 8]](win, b0 + 3usize * WIN + c)
                    let v4 = simd.load[Vec[i16, 8]](win, b0 + 4usize * WIN + c)
                    simd.store[Vec[i16, 8]](colb, c, v0 +% v1 +% v2 +% v3 +% v4)
                    let l01 = simd.unpack_lo[Vec[i16, 8]](v0, v1)
                    let h01 = simd.unpack_hi[Vec[i16, 8]](v0, v1)
                    let l23 = simd.unpack_lo[Vec[i16, 8]](v2, v3)
                    let h23 = simd.unpack_hi[Vec[i16, 8]](v2, v3)
                    let l4 = simd.unpack_lo[Vec[i16, 8]](v4, z16)
                    let h4 = simd.unpack_hi[Vec[i16, 8]](v4, z16)
                    simd.store[Vec[i32, 4]](cola, c, simd.madd_i16[Vec[i16, 8]](l01, l01) +% simd.madd_i16[Vec[i16, 8]](l23, l23) +% simd.madd_i16[Vec[i16, 8]](l4, l4))
                    simd.store[Vec[i32, 4]](cola, c + 4usize, simd.madd_i16[Vec[i16, 8]](h01, h01) +% simd.madd_i16[Vec[i16, 8]](h23, h23) +% simd.madd_i16[Vec[i16, 8]](h4, h4))
                    c += 8usize
                }
            } else {
                while c < ww {
                    let v0 = simd.load[Vec[i16, 8]](win, b0 + c)
                    let v1 = simd.load[Vec[i16, 8]](win, b0 + WIN + c)
                    let v2 = simd.load[Vec[i16, 8]](win, b0 + 2usize * WIN + c)
                    simd.store[Vec[i16, 8]](colb, c, v0 +% v1 +% v2)
                    let l01 = simd.unpack_lo[Vec[i16, 8]](v0, v1)
                    let h01 = simd.unpack_hi[Vec[i16, 8]](v0, v1)
                    let l2 = simd.unpack_lo[Vec[i16, 8]](v2, z16)
                    let h2 = simd.unpack_hi[Vec[i16, 8]](v2, z16)
                    simd.store[Vec[i32, 4]](cola, c, simd.madd_i16[Vec[i16, 8]](l01, l01) +% simd.madd_i16[Vec[i16, 8]](l2, l2))
                    simd.store[Vec[i32, 4]](cola, c + 4usize, simd.madd_i16[Vec[i16, 8]](h01, h01) +% simd.madd_i16[Vec[i16, 8]](h2, h2))
                    c += 8usize
                }
            }
            // the box sums of position j (from -1) are those of the columns j + 2 - r .. j + 2 + r
            let rowat = usize(i + 1i32) * AB
            var j0 = 0usize
            while j0 < w + 2usize {
                var sbv = z16
                var sal = simd.splat[Vec[i32, 4]](0i32)
                var sah = simd.splat[Vec[i32, 4]](0i32)
                var t = 0usize
                while t <= 2usize * rr {
                    let o = j0 + 2usize + t - rr
                    sbv = sbv +% simd.load[Vec[i16, 8]](colb, o)
                    sal = sal +% simd.load[Vec[i32, 4]](cola, o)
                    sah = sah +% simd.load[Vec[i32, 4]](cola, o + 4usize)
                    t += 1usize
                }
                let sbl = mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](sbv, z16))
                let sbh = mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](sbv, z16))
                let pl = simd.min[Vec[i32, 4]]((sal *% nv) -% (sbl *% sbl), pmv)
                let ph = simd.min[Vec[i32, 4]]((sah *% nv) -% (sbh *% sbh), pmv)
                simd.store[Vec[i32, 4]](zb[0usize..8usize], 0usize, simd.min[Vec[i32, 4]](((pl *% scv) +% rndv) >> 20u32, c255))
                simd.store[Vec[i32, 4]](zb[0usize..8usize], 4usize, simd.min[Vec[i32, 4]](((ph *% scv) +% rndv) >> 20u32, c255))
                simd.store[Vec[i32, 4]](sbb[0usize..8usize], 0usize, sbl)
                simd.store[Vec[i32, 4]](sbb[0usize..8usize], 4usize, sbh)
                var l = 0usize
                while l < 8usize {
                    let a2 = a2tab[usize(zb[l] & 255i32)]
                    a_arr[rowat + j0 + l] = i16(a2)
                    b_arr[rowat + j0 + l] = ((256i32 - a2) * sbb[l] * one_over_n + 2048i32) >> 12u32
                    l += 1usize
                }
                j0 += 8usize
            }
        }
        i += 1i32
    }
    // weighted sums of the neighbouring A and B values
    let c6 = simd.splat[Vec[i16, 8]](6i16)
    let c5 = simd.splat[Vec[i16, 8]](5i16)
    let c4 = simd.splat[Vec[i16, 8]](4i16)
    let c3 = simd.splat[Vec[i16, 8]](3i16)
    let d6 = simd.splat[Vec[i32, 4]](6i32)
    let d5 = simd.splat[Vec[i32, 4]](5i32)
    let d4 = simd.splat[Vec[i32, 4]](4i32)
    let d3 = simd.splat[Vec[i32, 4]](3i32)
    let rnd8 = simd.splat[Vec[i32, 4]](128i32)
    let rnd9 = simd.splat[Vec[i32, 4]](256i32)
    var y = 0usize
    while y < h {
        let wb = (y + 3usize) * WIN + 3usize
        var x = 0usize
        if pass == 0usize {
            if (y & 1usize) != 0usize {
                let rm = (y + 1usize) * AB + 1usize
                while x < w {
                    let at = rm + x
                    let av = (c6 *% simd.load[Vec[i16, 8]](a_arr, at)) +% (c5 *% (simd.load[Vec[i16, 8]](a_arr, at - 1usize) +% simd.load[Vec[i16, 8]](a_arr, at + 1usize)))
                    let bl = (d6 *% simd.load[Vec[i32, 4]](b_arr, at)) +% (d5 *% (simd.load[Vec[i32, 4]](b_arr, at - 1usize) +% simd.load[Vec[i32, 4]](b_arr, at + 1usize)))
                    let bh = (d6 *% simd.load[Vec[i32, 4]](b_arr, at + 4usize)) +% (d5 *% (simd.load[Vec[i32, 4]](b_arr, at + 3usize) +% simd.load[Vec[i32, 4]](b_arr, at + 5usize)))
                    let px = simd.load[Vec[i16, 8]](win, wb + x)
                    simd.store[Vec[i32, 4]](f, y * FL + x, (((mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](av, z16)) *% mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](px, z16))) +% bl) +% rnd8) >> 8u32)
                    simd.store[Vec[i32, 4]](f, y * FL + x + 4usize, (((mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](av, z16)) *% mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](px, z16))) +% bh) +% rnd8) >> 8u32)
                    x += 8usize
                }
            } else {
                let ru = y * AB + 1usize
                let rd = (y + 2usize) * AB + 1usize
                while x < w {
                    let au = ru + x
                    let ad = rd + x
                    let av = (c6 *% (simd.load[Vec[i16, 8]](a_arr, au) +% simd.load[Vec[i16, 8]](a_arr, ad))) +% (c5 *% (simd.load[Vec[i16, 8]](a_arr, au - 1usize) +% simd.load[Vec[i16, 8]](a_arr, au + 1usize) +% simd.load[Vec[i16, 8]](a_arr, ad - 1usize) +% simd.load[Vec[i16, 8]](a_arr, ad + 1usize)))
                    let bl = (d6 *% (simd.load[Vec[i32, 4]](b_arr, au) +% simd.load[Vec[i32, 4]](b_arr, ad))) +% (d5 *% (simd.load[Vec[i32, 4]](b_arr, au - 1usize) +% simd.load[Vec[i32, 4]](b_arr, au + 1usize) +% simd.load[Vec[i32, 4]](b_arr, ad - 1usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 1usize)))
                    let bh = (d6 *% (simd.load[Vec[i32, 4]](b_arr, au + 4usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 4usize))) +% (d5 *% (simd.load[Vec[i32, 4]](b_arr, au + 3usize) +% simd.load[Vec[i32, 4]](b_arr, au + 5usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 3usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 5usize)))
                    let px = simd.load[Vec[i16, 8]](win, wb + x)
                    simd.store[Vec[i32, 4]](f, y * FL + x, (((mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](av, z16)) *% mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](px, z16))) +% bl) +% rnd9) >> 9u32)
                    simd.store[Vec[i32, 4]](f, y * FL + x + 4usize, (((mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](av, z16)) *% mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](px, z16))) +% bh) +% rnd9) >> 9u32)
                    x += 8usize
                }
            }
        } else {
            let ru = y * AB + 1usize
            let rm = (y + 1usize) * AB + 1usize
            let rd = (y + 2usize) * AB + 1usize
            while x < w {
                let au = ru + x
                let am = rm + x
                let ad = rd + x
                let av = (c4 *% (simd.load[Vec[i16, 8]](a_arr, am) +% simd.load[Vec[i16, 8]](a_arr, am - 1usize) +% simd.load[Vec[i16, 8]](a_arr, am + 1usize) +% simd.load[Vec[i16, 8]](a_arr, au) +% simd.load[Vec[i16, 8]](a_arr, ad))) +% (c3 *% (simd.load[Vec[i16, 8]](a_arr, au - 1usize) +% simd.load[Vec[i16, 8]](a_arr, au + 1usize) +% simd.load[Vec[i16, 8]](a_arr, ad - 1usize) +% simd.load[Vec[i16, 8]](a_arr, ad + 1usize)))
                let bl = (d4 *% (simd.load[Vec[i32, 4]](b_arr, am) +% simd.load[Vec[i32, 4]](b_arr, am - 1usize) +% simd.load[Vec[i32, 4]](b_arr, am + 1usize) +% simd.load[Vec[i32, 4]](b_arr, au) +% simd.load[Vec[i32, 4]](b_arr, ad))) +% (d3 *% (simd.load[Vec[i32, 4]](b_arr, au - 1usize) +% simd.load[Vec[i32, 4]](b_arr, au + 1usize) +% simd.load[Vec[i32, 4]](b_arr, ad - 1usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 1usize)))
                let bh = (d4 *% (simd.load[Vec[i32, 4]](b_arr, am + 4usize) +% simd.load[Vec[i32, 4]](b_arr, am + 3usize) +% simd.load[Vec[i32, 4]](b_arr, am + 5usize) +% simd.load[Vec[i32, 4]](b_arr, au + 4usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 4usize))) +% (d3 *% (simd.load[Vec[i32, 4]](b_arr, au + 3usize) +% simd.load[Vec[i32, 4]](b_arr, au + 5usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 3usize) +% simd.load[Vec[i32, 4]](b_arr, ad + 5usize)))
                let px = simd.load[Vec[i16, 8]](win, wb + x)
                simd.store[Vec[i32, 4]](f, y * FL + x, (((mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](av, z16)) *% mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](px, z16))) +% bl) +% rnd9) >> 9u32)
                simd.store[Vec[i32, 4]](f, y * FL + x + 4usize, (((mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](av, z16)) *% mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](px, z16))) +% bh) +% rnd9) >> 9u32)
                x += 8usize
            }
        }
        y += 1usize
    }
    }
}

fn self_guided(sc: *const Scratch, u: *const LrUnit, w: usize, h: usize, out: []u8, out_stride: usize, x: usize, y: usize) {
    let set = usize(u.sgr_set)
    box_filter(sc.win, w, h, set, 0usize, sc.a_arr, sc.b_arr, sc.cola, sc.colb, sc.a2tab, sc.flt0)
    box_filter(sc.win, w, h, set, 1usize, sc.a_arr, sc.b_arr, sc.cola, sc.colb, sc.a2tab, sc.flt1)
    let tab = sgr_params()
    let r0 = tab[set * 4usize] != 0u8
    let r1 = tab[set * 4usize + 2usize] != 0u8
    let w0 = u.xqd0
    let w1 = u.xqd1
    let w2 = 128i32 - w0 - w1
    let w0v = simd.splat[Vec[i32, 4]](w0)
    let w1v = simd.splat[Vec[i32, 4]](w1)
    let w2v = simd.splat[Vec[i32, 4]](w2)
    let rnd = simd.splat[Vec[i32, 4]](1024i32)
    let z16 = simd.splat[Vec[i16, 8]](0i16)
    let win = sc.win
    let flt0 = sc.flt0
    let flt1 = sc.flt1
    var tmp: [16]u8 = zero
    var i = 0usize
    @nocheck {
    while i < h {
        let wb = (i + 3usize) * WIN + 3usize
        let ob = (y + i) * out_stride + x
        let fb = i * FL
        var j = 0usize
        while j < w {
            var pks: [2]Vec[i16, 8] = zero
            var g = 0usize
            while g < 2usize {
                let px = simd.load[Vec[i16, 8]](win, wb + j + g * 8usize)
                let ul = mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i16, 8]](px, z16)) << 4u32
                let uh = mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i16, 8]](px, z16)) << 4u32
                var vl = w1v *% ul
                var vh = w1v *% uh
                if r0 {
                    vl = vl +% (w0v *% simd.load[Vec[i32, 4]](flt0, fb + j + g * 8usize))
                    vh = vh +% (w0v *% simd.load[Vec[i32, 4]](flt0, fb + j + g * 8usize + 4usize))
                } else {
                    vl = vl +% (w0v *% ul)
                    vh = vh +% (w0v *% uh)
                }
                if r1 {
                    vl = vl +% (w2v *% simd.load[Vec[i32, 4]](flt1, fb + j + g * 8usize))
                    vh = vh +% (w2v *% simd.load[Vec[i32, 4]](flt1, fb + j + g * 8usize + 4usize))
                } else {
                    vl = vl +% (w2v *% ul)
                    vh = vh +% (w2v *% uh)
                }
                pks[g] = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]]((vl +% rnd) >> 11u32, (vh +% rnd) >> 11u32)
                g += 1usize
            }
            let res = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](pks[0usize], pks[1usize])
            if j + 16usize <= w {
                simd.store[Vec[u8, 16]](out, ob + j, res)
            } else {
                simd.store[Vec[u8, 16]](tmp[0usize..16usize], 0usize, res)
                var q = 0usize
                while j + q < w {
                    out[ob + j + q] = tmp[q]
                    q += 1usize
                }
            }
            j += 16usize
        }
        i += 1usize
    }
    }
}

// two 16-bit taps in the lanes of every i32, for madd_i16 against interleaved sample pairs
fn tap_pair(a: i32, b: i32) -> Vec[i16, 8] {
    ret mem.bitcast[Vec[i16, 8]](simd.splat[Vec[i32, 4]]((b *% 65536i32) +% (a & 65535i32)))
}

fn wiener(sc: *const Scratch, u: *const LrUnit, w: usize, h: usize, out: []u8, out_stride: usize, x: usize, y: usize) {
    let vc0 = u.wiener[0usize]
    let vc1 = u.wiener[1usize]
    let vc2 = u.wiener[2usize]
    let hc0 = u.wiener[3usize]
    let hc1 = u.wiener[4usize]
    let hc2 = u.wiener[5usize]
    // a filter whose taps are all zero is the identity
    if vc0 == 0i32 && vc1 == 0i32 && vc2 == 0i32 && hc0 == 0i32 && hc1 == 0i32 && hc2 == 0i32 { ret }
    let vc3 = 128i32 - 2i32 * (vc0 + vc1 + vc2)
    let hc3 = 128i32 - 2i32 * (hc0 + hc1 + hc2)
    let hp = tap_pair(hc0, hc1)
    let hq = tap_pair(hc2, hc3)
    let vp = tap_pair(vc0, vc1)
    let vq = tap_pair(vc2, vc3)
    // 8-bit samples: the horizontal pass keeps (s + 4) >> 3 within -2048 .. 6143, the vertical one rounds by 1024 >> 11
    let rnd0 = simd.splat[Vec[i32, 4]](4i32)
    let rnd1 = simd.splat[Vec[i32, 4]](1024i32)
    let vlo = simd.splat[Vec[i16, 8]](-2048i16)
    let vhi = simd.splat[Vec[i16, 8]](6143i16)
    let win = sc.win
    let inter = sc.inter
    var r = 0usize
    @nocheck {
    while r < h + 6usize {
        var q = r * WIN
        var ib = r * FL
        var c = 0usize
        while c < w {
            let p0 = simd.load[Vec[i16, 8]](win, q)
            let p1 = simd.load[Vec[i16, 8]](win, q + 1usize)
            let p2 = simd.load[Vec[i16, 8]](win, q + 2usize)
            let p3 = simd.load[Vec[i16, 8]](win, q + 3usize)
            let p4 = simd.load[Vec[i16, 8]](win, q + 4usize)
            let p5 = simd.load[Vec[i16, 8]](win, q + 5usize)
            let p6 = simd.load[Vec[i16, 8]](win, q + 6usize)
            let s06 = p0 +% p6
            let s15 = p1 +% p5
            let s24 = p2 +% p4
            var lo = simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s06, s15), hp) +% simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s24, p3), hq)
            var hi = simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s06, s15), hp) +% simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s24, p3), hq)
            lo = (lo +% rnd0) >> 3u32
            hi = (hi +% rnd0) >> 3u32
            let pk = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](lo, hi)
            simd.store[Vec[i16, 8]](inter, ib, simd.min[Vec[i16, 8]](simd.max[Vec[i16, 8]](pk, vlo), vhi))
            q += 8usize
            ib += 8usize
            c += 8usize
        }
        r += 1usize
    }
    r = 0usize
    var tmp: [16]u8 = zero
    while r < h {
        let ob = (y + r) * out_stride + x
        var c = 0usize
        while c < w {
            var g = 0usize
            var pks: [2]Vec[i16, 8] = zero
            while g < 2usize {
                let q = r * FL + c + g * 8usize
                let i0 = simd.load[Vec[i16, 8]](inter, q)
                let i1 = simd.load[Vec[i16, 8]](inter, q + FL)
                let i2 = simd.load[Vec[i16, 8]](inter, q + 2usize * FL)
                let i3 = simd.load[Vec[i16, 8]](inter, q + 3usize * FL)
                let i4 = simd.load[Vec[i16, 8]](inter, q + 4usize * FL)
                let i5 = simd.load[Vec[i16, 8]](inter, q + 5usize * FL)
                let i6 = simd.load[Vec[i16, 8]](inter, q + 6usize * FL)
                let s06 = i0 +% i6
                let s15 = i1 +% i5
                let s24 = i2 +% i4
                var lo = simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s06, s15), vp) +% simd.madd_i16[Vec[i16, 8]](simd.unpack_lo[Vec[i16, 8]](s24, i3), vq)
                var hi = simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s06, s15), vp) +% simd.madd_i16[Vec[i16, 8]](simd.unpack_hi[Vec[i16, 8]](s24, i3), vq)
                lo = (lo +% rnd1) >> 11u32
                hi = (hi +% rnd1) >> 11u32
                pks[g] = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](lo, hi)
                g += 1usize
            }
            let res = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](pks[0usize], pks[1usize])
            if c + 16usize <= w {
                simd.store[Vec[u8, 16]](out, ob + c, res)
            } else {
                simd.store[Vec[u8, 16]](tmp[0usize..16usize], 0usize, res)
                var j = 0usize
                while c + j < w {
                    out[ob + c + j] = tmp[j]
                    j += 1usize
                }
            }
            c += 16usize
        }
        r += 1usize
    }
    }
}

// Number of 64-row (luma) stripes of a plane: stripe n covers the plane rows
// [max(0, (64n - 8) >> sub_y), min(plane_h, (64(n+1) - 8) >> sub_y)), the spec's StripeStartY/StripeEndY.
fn count_stripes(frame_h: u32, sub_y: u32) -> u32 {
    let ph = (frame_h + sub_y) >> sub_y
    if ph == 0u32 { ret 0u32 }
    ret (((ph << sub_y) + 8u32 + 63u32) >> 6u32)
}

fn restore_plane(a: *mem.Arena, bit_depth: u32, sub_x: u32, sub_y: u32, frame_w: u32, frame_h: u32, pre: []const u8, cdef: []const u8, out: []u8, stride: usize, unit_size: u32, units: []const LrUnit) -> err {
    ret restore_rows(a, bit_depth, sub_x, sub_y, frame_w, frame_h, pre, cdef, out, stride, unit_size, units, 0u32, count_stripes(frame_h, sub_y))
}

// Restores the stripes [stripe_from, stripe_to) of a plane (clamped to count_stripes) and writes only
// their rows of `out`, the plain copy of the cdef rows included. Stripes are independent: they read
// `pre` and `cdef` only, so any partition of 0..count_stripes(frame_h, sub_y) into ranges, run in any
// order or concurrently (one arena `a` per worker, it holds the ~100 KB scratch), gives the same `out` as
// restore_plane. Ranges may be cut at any stripe boundary; unit boundaries need no alignment.
fn restore_rows(a: *mem.Arena, bit_depth: u32, sub_x: u32, sub_y: u32, frame_w: u32, frame_h: u32, pre: []const u8, cdef: []const u8, out: []u8, stride: usize, unit_size: u32, units: []const LrUnit, stripe_from: u32, stripe_to: u32) -> err {
    let pw = i32((frame_w + sub_x) >> sub_x)
    let ph = i32((frame_h + sub_y) >> sub_y)
    if bit_depth != 8u32 || unit_size == 0u32 { ret Invalid }
    let unit_rows = i32(count_units(unit_size, u32(ph)))
    let unit_cols = i32(count_units(unit_size, u32(pw)))
    if units.len < usize(unit_rows) * usize(unit_cols) { ret Invalid }
    if pw <= 0i32 || ph <= 0i32 { ret ok }
    let need = usize(ph - 1i32) * stride + usize(pw)
    if pre.len < need || cdef.len < need || out.len < need { ret Invalid }
    var n_to = stripe_to
    let n_all = count_stripes(frame_h, sub_y)
    if n_to > n_all { n_to = n_all }
    if stripe_from >= n_to { ret ok }
    let row_lo = imax(0i32, (i32(stripe_from) * 64i32 - 8i32) >> sub_y)
    let row_hi = imin(ph, (i32(n_to) * 64i32 - 8i32) >> sub_y)
    copy_plane(cdef[usize(row_lo) * stride..cdef.len], out[usize(row_lo) * stride..out.len], stride, usize(pw), usize(row_hi - row_lo))
    var needs = false
    var q = 0usize
    while q < units.len {
        if units[q].rtype == RESTORE_WIENER || units[q].rtype == RESTORE_SGRPROJ { needs = true }
        q += 1usize
    }
    if !needs { ret ok }
    let marker = mem.mark(a)
    let (win_buf, win_buf_err) = mem.alloc[i16](a, WIN * WIN + 16usize)
    if win_buf_err != ok { ret win_buf_err }
    let (inter, inter_err) = mem.alloc[i16](a, WIN * FL + 16usize)
    if inter_err != ok { ret inter_err }
    let (flt0, flt0_err) = mem.alloc[i32](a, FL * FL)
    if flt0_err != ok { ret flt0_err }
    let (flt1, flt1_err) = mem.alloc[i32](a, FL * FL)
    if flt1_err != ok { ret flt1_err }
    let (a_arr, a_arr_err) = mem.alloc[i16](a, AB * (AB + 1usize))
    if a_arr_err != ok { ret a_arr_err }
    let (b_arr, b_arr_err) = mem.alloc[i32](a, AB * (AB + 1usize))
    if b_arr_err != ok { ret b_arr_err }
    let (cola, cola_err) = mem.alloc[i32](a, 96usize)
    if cola_err != ok { ret cola_err }
    let (colb, colb_err) = mem.alloc[i16](a, 96usize)
    if colb_err != ok { ret colb_err }
    let (a2tab, a2tab_err) = mem.alloc[i32](a, 256usize)
    if a2tab_err != ok { ret a2tab_err }
    // the vector loops read a few lanes past the data they use: start from zeros so those lanes are defined
    var zi = 0usize
    while zi < win_buf.len {
        win_buf[zi] = 0i16
        zi += 1usize
    }
    zi = 0usize
    while zi < 96usize {
        cola[zi] = 0i32
        colb[zi] = 0i16
        zi += 1usize
    }
    zi = 0usize
    while zi < a_arr.len {
        a_arr[zi] = 0i16
        b_arr[zi] = 0i32
        zi += 1usize
    }
    zi = 0usize
    while zi < inter.len {
        inter[zi] = 0i16
        zi += 1usize
    }
    // A for each z: 1 at 0, 256 from 255, ((z << 8) + z / 2) / (z + 1) between
    a2tab[0usize] = 1i32
    a2tab[255usize] = 256i32
    var z = 1i32
    while z < 255i32 {
        a2tab[usize(z)] = ((z << 8u32) + z / 2i32) / (z + 1i32)
        z += 1i32
    }
    let sc = Scratch { win: win_buf, inter: inter, flt0: flt0, flt1: flt1, a_arr: a_arr, b_arr: b_arr, cola: cola, colb: colb, a2tab: a2tab }
    let usz = i32(unit_size)
    let row_off = i32(8u32 >> sub_y)
    var src = Src { pre: pre, cdef: cdef, stride: stride, end_x: pw - 1i32, end_y: ph - 1i32, stripe_start: 0i32, stripe_end: 0i32 }
    var n = i32(stripe_from)
    while n < i32(n_to) {
        let start = (0i32 - 8i32 + n * 64i32) >> sub_y
        if start > ph - 1i32 { break }
        src.stripe_start = start
        src.stripe_end = start + i32(64u32 >> sub_y) - 1i32
        let hi = imin(ph - 1i32, src.stripe_end)
        var y = imax(0i32, start)
        while y <= hi {
            let ur = imin(unit_rows - 1i32, (y + row_off) / usz)
            var y2 = y
            while y2 + 1i32 <= hi && imin(unit_rows - 1i32, (y2 + 1i32 + row_off) / usz) == ur { y2 += 1i32 }
            var x = 0i32
            while x < pw {
                let uc = imin(unit_cols - 1i32, x / usz)
                var x_end = pw
                if uc < unit_cols - 1i32 { x_end = (uc + 1i32) * usz }
                let w = imin(64i32, x_end - x)
                let h = y2 - y + 1i32
                let u = &units[usize(ur) * usize(unit_cols) + usize(uc)]
                if u.rtype == RESTORE_WIENER || u.rtype == RESTORE_SGRPROJ {
                    stage(win_buf, &src, x, y, w, h)
                    if u.rtype == RESTORE_WIENER {
                        wiener(&sc, u, usize(w), usize(h), out, stride, usize(x), usize(y))
                    } else {
                        self_guided(&sc, u, usize(w), usize(h), out, stride, usize(x), usize(y))
                    }
                }
                x += w
            }
            y = y2 + 1i32
        }
        n += 1i32
    }
    mem.reset(a, marker)
    ret ok
}
