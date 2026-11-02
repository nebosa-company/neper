// AV1 constrained directional enhancement filter (CDEF), spec section 7.15, no superres, 8-bit samples.
//
// `cdef_frame(p, cdef_idx, skips, src, dst)` reads the deblocked planes `src` and writes the deringed
// planes `dst` (the spec's CurrFrame and CdefFrame). Both must cover MiRows*4 by MiCols*4 luma samples
// (and the subsampled size for chroma): samples past the picture edge but inside the mode-info grid are
// read and written like any other. `dst` is first made a copy of `src` over that area; only 8x8 blocks
// with a non-negative cdef_idx that are not all-skip are then filtered. Both return Invalid when
// `p.bit_depth` is not 8.
//   cdef_idx: one i8 per 64x64 luma block, row-major, ((mi_cols + 15) >> 4) per row; -1 = no filtering.
//   skips:    one nonzero/zero byte per 4x4 luma block (MiRows by MiCols, row-major), the spec's Skips.
//   CdefParams carries CdefDamping (3 + cdef_damping_minus_3) and the strength tables as stored in the
//   frame header (a sec strength of 3 is already 4, as the syntax makes it).
// `direction(plane, stride, x0, y0, bit_depth)` is the direction search for the 8x8 luma block at
// (x0, y0): it returns (yDir, var). The samples are taken as 8-bit whatever bit_depth says.
//
// The filter works on 16 samples at a time in u8 lanes (two rows of an 8-wide block, or the U and V rows
// of a 4-wide chroma block, which share direction and strengths). A block whose taps all lie inside the
// picture is copied into five column-shifted copies (one per tap column offset -2..2) so that every tap
// of two rows is one 16-byte load. constrain() is |d| and min(|d|, max(0, threshold - (|d| >> shift)))
// in saturating u8 arithmetic; the sign is restored through the identity net = 2 * min(r, max(t - x, 0)) - r,
// so only the sums of r and of its positive part are kept per weight class. That needs strengths up to
// 15 (any bigger one, and every block touching the picture edge, takes the scalar path with the explicit
// availability test of the spec). When only one of the primary and secondary strengths is nonzero the
// min/max clamp is skipped: the tap weights sum to 12/16, so the result is already a convex combination
// of the sample and its taps. With both strengths zero the block is left as the copy.

use e.mem
use e.simd

error Invalid

type CdefParams = struct {
    bit_depth: u32,
    sub_x: u32,
    sub_y: u32,
    num_planes: u32,
    mi_rows: u32,
    mi_cols: u32,
    damping: u32,
    y_pri: [8]u32,
    y_sec: [8]u32,
    uv_pri: [8]u32,
    uv_sec: [8]u32,
}

type Planes = struct { y: []u8, u: []u8, v: []u8, stride_y: usize, stride_uv: usize }

// tap positions of a block (primary k=0,1; secondary dir + 6 k=0,1; secondary dir + 2 k=0,1), their weights and thresholds
type Taps = struct { dy: [6]i32, dx: [6]i32, pw0: i32, pw1: i32, pri: i32, sec: i32, padj: u32, sadj: u32 }

fn directions() -> str {
    ret "\x01\x03\x00\x04\x02\x03\x01\x04\x02\x03\x02\x04\x02\x03\x03\x04\x03\x03\x04\x04\x03\x02\x04\x03\x03\x02\x04\x02\x03\x02\x04\x01"
}

fn uv_dir() -> str {
    ret "\x00\x01\x02\x03\x04\x05\x06\x07\x01\x02\x02\x02\x03\x04\x06\x00\x07\x00\x02\x04\x05\x06\x06\x06\x00\x01\x02\x03\x04\x05\x06\x07"
}

fn imin(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn imax(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn floor_log2(v: u32) -> i32 {
    var n = 0i32
    var x = v
    while x > 1u32 {
        x = x >> 1u32
        n += 1i32
    }
    ret n
}

// the shift of the constrain function for a strength (unused for strength 0)
fn damp_shift(threshold: i32, damping: i32) -> u32 {
    if threshold == 0i32 { ret 0u32 }
    ret u32(imax(0i32, damping - floor_log2(u32(threshold))))
}

fn constrain(diff: i32, threshold: i32, adj: u32) -> i32 {
    let s = diff >> 31u32
    let mag = (diff ^ s) - s
    var v = threshold - (mag >> adj)
    v = v & ~(v >> 31u32)
    let e = v - mag
    v = mag + (e & (e >> 31u32))
    ret (v ^ s) - s
}

// The w by h samples at the top left of a plane, a row at a time and eight samples per move.
fn copy_plane(src: []const u8, dst: []u8, stride: usize, w: usize, h: usize) {
    if w == 0usize || h == 0usize { ret }
    let last = (h - 1usize) * stride + w - 1usize
    dst[last] = src[last]
    let w8 = w & ~7usize
    var y = 0usize
    @nocheck {
    while y < h {
        let base = y * stride
        var x = 0usize
        while x < w8 {
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

fn sq(v: i32) -> i32 {
    ret v * v
}

// The partial sums of the spec's direction search, one array of 15 entries per direction (0 = i + j,
// 1 = i + j/2, 3 = 3 + i - j/2, 4 = 7 + i - j, 5 = 3 - i/2 + j, 7 = i/2 + j), the row sums (2) and the
// column sums (6), built with whole-row vector adds at shifted offsets.
fn direction(plane: []const u8, stride: usize, x0: usize, y0: usize, bit_depth: u32) -> (u32, u32) {
    var a0: [24]i16 = zero
    var a4: [24]i16 = zero
    var a5: [24]i16 = zero
    var a7: [24]i16 = zero
    var a1: [24]i32 = zero
    var a3: [24]i32 = zero
    var rows: [8]u64 = zero
    var cost: [8]i32 = zero
    let s0 = a0[0usize..24usize]
    let s4 = a4[0usize..24usize]
    let s5 = a5[0usize..24usize]
    let s7 = a7[0usize..24usize]
    let s1 = a1[0usize..24usize]
    let s3 = a3[0usize..24usize]
    let z8 = simd.splat[Vec[u8, 16]](0u8)
    let k128 = simd.splat[Vec[i16, 8]](128i16)
    let ones = simd.splat[Vec[i16, 8]](1i16)
    let rev = mem.bitcast[Vec[u8, 16]](Vec[u64, 2]{ 0x09080B0A0D0C0F0Eu64, 0x0100030205040706u64 })
    var col = simd.splat[Vec[i16, 8]](0i16)
    var prev = simd.splat[Vec[i16, 8]](0i16)
    let guard = plane[(y0 + 7usize) * stride + x0 + 7usize]
    var i = 0usize
    var at = y0 * stride + x0
    @nocheck {
    while i < 8usize {
        let w = *mem.cast[*u64](&plane[at])
        rows[i] = w
        at = at +% stride
        let raw = mem.bitcast[Vec[u8, 16]](Vec[u64, 2]{ w, 0u64 })
        let r = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](raw, z8)) -% k128
        let rr = mem.bitcast[Vec[i16, 8]](simd.shuffle_bytes[Vec[u8, 16]](mem.bitcast[Vec[u8, 16]](r), rev))
        col = col +% r
        simd.store[Vec[i16, 8]](s0, i, simd.load[Vec[i16, 8]](s0, i) +% r)
        simd.store[Vec[i16, 8]](s4, i, simd.load[Vec[i16, 8]](s4, i) +% rr)
        simd.store[Vec[i32, 4]](s1, i, simd.load[Vec[i32, 4]](s1, i) +% simd.madd_i16[Vec[i16, 8]](r, ones))
        simd.store[Vec[i32, 4]](s3, i, simd.load[Vec[i32, 4]](s3, i) +% simd.madd_i16[Vec[i16, 8]](rr, ones))
        if (i & 1usize) == 0usize {
            prev = r
        } else {
            let pair = prev +% r
            let hi = i >> 1u32
            simd.store[Vec[i16, 8]](s5, 3usize - hi, simd.load[Vec[i16, 8]](s5, 3usize - hi) +% pair)
            simd.store[Vec[i16, 8]](s7, hi, simd.load[Vec[i16, 8]](s7, hi) +% pair)
        }
        i += 1usize
    }
    // directions 2 and 6: eight sums each, weight 105
    var c2 = 0i32
    i = 0usize
    while i < 8usize {
        let two = mem.bitcast[Vec[u8, 16]](Vec[u64, 2]{ rows[i], rows[i + 1usize] })
        let sad = simd.sad_u8[Vec[u8, 16]](two, z8)
        let q0 = i32(sad.lanes[0]) - 1024i32
        let q1 = i32(sad.lanes[1]) - 1024i32
        c2 += q0 * q0 + q1 * q1
        i += 2usize
    }
    cost[2usize] = c2 * 105i32
    let cm = simd.madd_i16[Vec[i16, 8]](col, col)
    cost[6usize] = (cm.lanes[0] + cm.lanes[1] + cm.lanes[2] + cm.lanes[3]) * 105i32
    // directions 0 and 4: weights 840 420 280 210 168 140 120 105 at distance from the middle; the
    // others: three on each side with 420 210 140 and five in the middle with 105
    cost[0usize] = 105i32 * sq(i32(a0[7usize])) + 840i32 * (sq(i32(a0[0usize])) + sq(i32(a0[14usize]))) + 420i32 * (sq(i32(a0[1usize])) + sq(i32(a0[13usize]))) + 280i32 * (sq(i32(a0[2usize])) + sq(i32(a0[12usize]))) + 210i32 * (sq(i32(a0[3usize])) + sq(i32(a0[11usize]))) + 168i32 * (sq(i32(a0[4usize])) + sq(i32(a0[10usize]))) + 140i32 * (sq(i32(a0[5usize])) + sq(i32(a0[9usize]))) + 120i32 * (sq(i32(a0[6usize])) + sq(i32(a0[8usize])))
    cost[4usize] = 105i32 * sq(i32(a4[7usize])) + 840i32 * (sq(i32(a4[0usize])) + sq(i32(a4[14usize]))) + 420i32 * (sq(i32(a4[1usize])) + sq(i32(a4[13usize]))) + 280i32 * (sq(i32(a4[2usize])) + sq(i32(a4[12usize]))) + 210i32 * (sq(i32(a4[3usize])) + sq(i32(a4[11usize]))) + 168i32 * (sq(i32(a4[4usize])) + sq(i32(a4[10usize]))) + 140i32 * (sq(i32(a4[5usize])) + sq(i32(a4[9usize]))) + 120i32 * (sq(i32(a4[6usize])) + sq(i32(a4[8usize])))
    let m1 = sq(a1[3usize]) + sq(a1[4usize]) + sq(a1[5usize]) + sq(a1[6usize]) + sq(a1[7usize])
    let m3 = sq(a3[3usize]) + sq(a3[4usize]) + sq(a3[5usize]) + sq(a3[6usize]) + sq(a3[7usize])
    let m5 = sq(i32(a5[3usize])) + sq(i32(a5[4usize])) + sq(i32(a5[5usize])) + sq(i32(a5[6usize])) + sq(i32(a5[7usize]))
    let m7 = sq(i32(a7[3usize])) + sq(i32(a7[4usize])) + sq(i32(a7[5usize])) + sq(i32(a7[6usize])) + sq(i32(a7[7usize]))
    cost[1usize] = m1 * 105i32 + 420i32 * (sq(a1[0usize]) + sq(a1[10usize])) + 210i32 * (sq(a1[1usize]) + sq(a1[9usize])) + 140i32 * (sq(a1[2usize]) + sq(a1[8usize]))
    cost[3usize] = m3 * 105i32 + 420i32 * (sq(a3[0usize]) + sq(a3[10usize])) + 210i32 * (sq(a3[1usize]) + sq(a3[9usize])) + 140i32 * (sq(a3[2usize]) + sq(a3[8usize]))
    cost[5usize] = m5 * 105i32 + 420i32 * (sq(i32(a5[0usize])) + sq(i32(a5[10usize]))) + 210i32 * (sq(i32(a5[1usize])) + sq(i32(a5[9usize]))) + 140i32 * (sq(i32(a5[2usize])) + sq(i32(a5[8usize])))
    cost[7usize] = m7 * 105i32 + 420i32 * (sq(i32(a7[0usize])) + sq(i32(a7[10usize]))) + 210i32 * (sq(i32(a7[1usize])) + sq(i32(a7[9usize]))) + 140i32 * (sq(i32(a7[2usize])) + sq(i32(a7[8usize])))
    }
    var best_cost = 0i32
    var y_dir = 0usize
    i = 0usize
    while i < 8usize {
        if cost[i] > best_cost {
            best_cost = cost[i]
            y_dir = i
        }
        i += 1usize
    }
    let variance = (best_cost - cost[(y_dir + 4usize) & 7usize]) >> 10u32
    ret (u32(y_dir), u32(variance))
}

// Every tap tested against the picture edge, any strength; for the blocks that touch the edge.
fn edge_block(src: []const u8, dst: []u8, stride: usize, pw: i32, ph: i32, x0: i32, y0: i32, w: i32, h: i32, t: *const Taps) {
    var tw: [12]i32 = zero
    var ty: [12]i32 = zero
    var tx: [12]i32 = zero
    var tk: [12]u32 = zero
    var n = 0usize
    var k = 0usize
    while k < 6usize {
        var sign = 0i32 - 1i32
        while sign <= 1i32 {
            ty[n] = sign * t.dy[k]
            tx[n] = sign * t.dx[k]
            if k < 2usize {
                if k == 0usize { tw[n] = t.pw0 } else { tw[n] = t.pw1 }
                tk[n] = 0u32
            } else {
                tw[n] = 2i32 - i32(k & 1usize)
                tk[n] = 1u32
            }
            n += 1usize
            sign += 2i32
        }
        k += 1usize
    }
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            let x = i32(src[usize(y0 + i) * stride + usize(x0 + j)])
            var sum = 0i32
            var hi = x
            var lo = x
            var m = 0usize
            while m < 12usize {
                let yy = y0 + i + ty[m]
                let xx = x0 + j + tx[m]
                if yy >= 0i32 && yy < ph && xx >= 0i32 && xx < pw {
                    let s = i32(src[usize(yy) * stride + usize(xx)])
                    if tk[m] == 0u32 {
                        sum += tw[m] * constrain(s - x, t.pri, t.padj)
                    } else {
                        sum += tw[m] * constrain(s - x, t.sec, t.sadj)
                    }
                    hi = imax(s, hi)
                    lo = imin(s, lo)
                }
                m += 1usize
            }
            var neg = 0i32
            if sum < 0i32 { neg = 1i32 }
            let v = x + ((8i32 + sum - neg) >> 4u32)
            dst[usize(y0 + i) * stride + usize(x0 + j)] = u8(imax(lo, imin(hi, v)))
            j += 1i32
        }
        i += 1i32
    }
}

const SPLANE: usize = 96usize

// The column-shifted copies of the block's source rows: plane q (tap column offset q - 2) holds rows
// y0 - 2 .. y0 + h + 1 of the samples x0 + q - 2 .. x0 + q + 5, eight bytes a row.
fn stage_luma(src: []const u8, stride: usize, x0: usize, y0: usize, h: usize, s: []u8) {
    let n = h + 4usize
    var q = 0usize
    @nocheck {
    while q < 5usize {
        var si = q * SPLANE
        var at = (y0 - 2usize) * stride + x0 + q - 2usize
        var r = 0usize
        while r < n {
            *mem.cast[*u64](&s[si]) = *mem.cast[*u64](&src[at])
            si = si +% 8usize
            at = at +% stride
            r += 1usize
        }
        q += 1usize
    }
    }
}

// The same for a 4-wide chroma block: each row is four bytes of U then four of V.
fn stage_uv(u: []const u8, v: []const u8, stride: usize, x0: usize, y0: usize, h: usize, s: []u8) {
    let n = h + 4usize
    var q = 0usize
    @nocheck {
    while q < 5usize {
        var si = q * SPLANE
        var at = (y0 - 2usize) * stride + x0 + q - 2usize
        var r = 0usize
        while r < n {
            *mem.cast[*u32](&s[si]) = *mem.cast[*u32](&u[at])
            *mem.cast[*u32](&s[si + 4usize]) = *mem.cast[*u32](&v[at])
            si = si +% 8usize
            at = at +% stride
            r += 1usize
        }
        q += 1usize
    }
    }
}

// The byte offsets in a staged block of the 12 taps (each of the 6 positions and its mirror image) of
// every direction, 12 a direction.
fn tap_offsets(offt: []usize) {
    let table = directions()
    var d = 0usize
    while d < 8usize {
        var k = 0usize
        while k < 6usize {
            var dd = d
            if (k >> 1u32) == 1usize { dd = (d + 6usize) & 7usize }
            if (k >> 1u32) == 2usize { dd = (d + 2usize) & 7usize }
            let a = dd * 4usize + (k & 1usize) * 2usize
            let dyp = usize(table[a])
            let dxp = usize(table[a + 1usize])
            offt[d * 12usize + k * 2usize] = dxp * SPLANE + dyp * 8usize
            offt[d * 12usize + k * 2usize + 1usize] = (4usize - dxp) * SPLANE + (4usize - dyp) * 8usize
            k += 1usize
        }
        d += 1usize
    }
}

// Filters `pairs` pairs of rows of the staged block s into o (16 bytes a pair); off: the tap offsets of
// the block's direction.
fn kernel(s: []const u8, o: []u8, pairs: usize, off: []const usize, pri: i32, sec: i32, padj: u32, sadj: u32, tap_set: usize) {
    let has_pri = pri != 0i32
    let has_sec = sec != 0i32
    let both = has_pri && has_sec
    let z8 = simd.splat[Vec[u8, 16]](0u8)
    let thr_p = simd.splat[Vec[u8, 16]](u8(pri))
    let thr_s = simd.splat[Vec[u8, 16]](u8(sec))
    let msk_p = simd.splat[Vec[u8, 16]](u8(255u32 >> padj))
    let msk_s = simd.splat[Vec[u8, 16]](u8(255u32 >> sadj))
    var ar: [4]Vec[u8, 16] = zero
    var ap: [4]Vec[u8, 16] = zero
    var pi = 0usize
    @nocheck {
    while pi < pairs {
        let pb = pi * 16usize
        let x = simd.load[Vec[u8, 16]](s, 2usize * SPLANE + pb + 16usize)
        var hi = x
        var lo = x
        ar[0usize] = z8
        ar[1usize] = z8
        ar[2usize] = z8
        ar[3usize] = z8
        ap[0usize] = z8
        ap[1usize] = z8
        ap[2usize] = z8
        ap[3usize] = z8
        if has_pri {
            var k = 0usize
            while k < 4usize {
                let tv = simd.load[Vec[u8, 16]](s, off[k] + pb)
                let m = simd.abs_diff[Vec[u8, 16]](tv, x)
                let sh = mem.bitcast[Vec[u8, 16]](mem.bitcast[Vec[u16, 8]](m) >> padj) & msk_p
                let r = simd.min[Vec[u8, 16]](m, simd.subs[Vec[u8, 16]](thr_p, sh))
                let rp = simd.min[Vec[u8, 16]](r, simd.subs[Vec[u8, 16]](tv, x))
                let c = k >> 1u32
                ar[c] = ar[c] +% r
                ap[c] = ap[c] +% rp
                if both {
                    hi = simd.max[Vec[u8, 16]](hi, tv)
                    lo = simd.min[Vec[u8, 16]](lo, tv)
                }
                k += 1usize
            }
        }
        if has_sec {
            var k = 0usize
            while k < 8usize {
                let tv = simd.load[Vec[u8, 16]](s, off[4usize + k] + pb)
                let m = simd.abs_diff[Vec[u8, 16]](tv, x)
                let sh = mem.bitcast[Vec[u8, 16]](mem.bitcast[Vec[u16, 8]](m) >> sadj) & msk_s
                let r = simd.min[Vec[u8, 16]](m, simd.subs[Vec[u8, 16]](thr_s, sh))
                let rp = simd.min[Vec[u8, 16]](r, simd.subs[Vec[u8, 16]](tv, x))
                let c = 2usize + ((k >> 1u32) & 1usize)
                ar[c] = ar[c] +% r
                ap[c] = ap[c] +% rp
                if both {
                    hi = simd.max[Vec[u8, 16]](hi, tv)
                    lo = simd.min[Vec[u8, 16]](lo, tv)
                }
                k += 1usize
            }
        }
        // weighted class sums: 2 * (sum of w * min(r, positive part)) - (sum of w * r)
        var up = z8
        var vp = z8
        if has_pri {
            if tap_set == 0usize {
                let a = (ap[0usize] +% ap[0usize]) +% ap[1usize]
                let b = (ar[0usize] +% ar[0usize]) +% ar[1usize]
                up = a +% a
                vp = b +% b
            } else {
                let a = ap[0usize] +% ap[1usize]
                let b = ar[0usize] +% ar[1usize]
                up = a +% a +% a
                vp = b +% b +% b
            }
        }
        var us = z8
        var vs = z8
        if has_sec {
            us = (ap[2usize] +% ap[2usize]) +% ap[3usize]
            vs = (ar[2usize] +% ar[2usize]) +% ar[3usize]
        }
        let xl = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](x, z8))
        let xh = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](x, z8))
        let ul = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](up, z8)) +% mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](us, z8))
        let uh = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](up, z8)) +% mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](us, z8))
        let vl = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](vp, z8)) +% mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](vs, z8))
        let vh = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](vp, z8)) +% mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](vs, z8))
        let eight = simd.splat[Vec[i16, 8]](8i16)
        let suml = ((ul +% ul) -% vl)
        let sumh = ((uh +% uh) -% vh)
        let dl = ((suml +% eight) +% (suml >> 15u32)) >> 4u32
        let dh = ((sumh +% eight) +% (sumh >> 15u32)) >> 4u32
        var res = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](xl +% dl, xh +% dh)
        if both {
            res = simd.max[Vec[u8, 16]](simd.min[Vec[u8, 16]](res, hi), lo)
        }
        simd.store[Vec[u8, 16]](o, pb, res)
        pi += 1usize
    }
    }
}

fn fill_taps(t: *Taps, pri: i32, sec: i32, damping: i32, dir: u32, tap_set: usize) {
    let table = directions()
    var k = 0usize
    while k < 2usize {
        let a = usize(dir) * 4usize + k * 2usize
        let b = usize((dir + 6u32) & 7u32) * 4usize + k * 2usize
        let c = usize((dir + 2u32) & 7u32) * 4usize + k * 2usize
        t.dy[k] = i32(table[a]) - 2i32
        t.dx[k] = i32(table[a + 1usize]) - 2i32
        t.dy[2usize + k] = i32(table[b]) - 2i32
        t.dx[2usize + k] = i32(table[b + 1usize]) - 2i32
        t.dy[4usize + k] = i32(table[c]) - 2i32
        t.dx[4usize + k] = i32(table[c + 1usize]) - 2i32
        k += 1usize
    }
    let pri_taps: [4]i32 = [4]i32{ 4, 2, 3, 3 }
    t.pw0 = pri_taps[tap_set * 2usize]
    t.pw1 = pri_taps[tap_set * 2usize + 1usize]
    t.pri = pri
    t.sec = sec
    t.padj = damp_shift(pri, damping)
    t.sadj = damp_shift(sec, damping)
}

// true when the block's taps and samples all lie inside the plane area and the slices, and the
// strengths suit the vector kernel
fn interior(src_len: usize, dst_len: usize, stride: usize, pw: i32, ph: i32, x0: i32, y0: i32, w: i32, h: i32, pri: i32, sec: i32) -> bool {
    if x0 < 2i32 || y0 < 2i32 || x0 + w + 2i32 > pw || y0 + h + 2i32 > ph { ret false }
    if pri > 15i32 || sec > 15i32 { ret false }
    let reach = usize(y0 + h + 1i32) * stride + usize(x0 + w + 1i32)
    ret reach < src_len && reach < dst_len
}

// Scratch: sbuf the staged block (5 * SPLANE bytes), obuf the filtered pairs (64), offt the tap offsets.
type Work = struct { sbuf: []u8, obuf: []u8, offt: []const usize }

// pw/ph: size of the plane area in samples; x0/y0/w/h: the block
fn run_block(src: []const u8, dst: []u8, stride: usize, pw: i32, ph: i32, x0: i32, y0: i32, w: i32, h: i32, pri: i32, sec: i32, damping: i32, dir: u32, tap_set: usize, k: *const Work) {
    if w == 8i32 && interior(src.len, dst.len, stride, pw, ph, x0, y0, w, h, pri, sec) {
        stage_luma(src, stride, usize(x0), usize(y0), usize(h), k.sbuf)
        let pairs = usize(h) >> 1u32
        kernel(k.sbuf, k.obuf, pairs, k.offt[usize(dir) * 12usize..usize(dir) * 12usize + 12usize], pri, sec, damp_shift(pri, damping), damp_shift(sec, damping), tap_set)
        var pi = 0usize
        var d0 = usize(y0) * stride + usize(x0)
        @nocheck {
        while pi < pairs {
            *mem.cast[*u64](&dst[d0]) = *mem.cast[*u64](&k.obuf[pi * 16usize])
            *mem.cast[*u64](&dst[d0 + stride]) = *mem.cast[*u64](&k.obuf[pi * 16usize + 8usize])
            d0 = d0 +% (2usize * stride)
            pi += 1usize
        }
        }
    } else {
        var t: Taps = zero
        fill_taps(&t, pri, sec, damping, dir, tap_set)
        edge_block(src, dst, stride, pw, ph, x0, y0, w, h, &t)
    }
}

// the U and V blocks of a 4-wide chroma block, which share everything but the samples
fn run_uv(su: []const u8, sv: []const u8, du: []u8, dv: []u8, stride: usize, pw: i32, ph: i32, x0: i32, y0: i32, h: i32, pri: i32, sec: i32, damping: i32, dir: u32, tap_set: usize, k: *const Work) {
    if interior(su.len, du.len, stride, pw, ph, x0, y0, 4i32, h, pri, sec) && sv.len == su.len && dv.len == du.len {
        stage_uv(su, sv, stride, usize(x0), usize(y0), usize(h), k.sbuf)
        let pairs = usize(h) >> 1u32
        kernel(k.sbuf, k.obuf, pairs, k.offt[usize(dir) * 12usize..usize(dir) * 12usize + 12usize], pri, sec, damp_shift(pri, damping), damp_shift(sec, damping), tap_set)
        var pi = 0usize
        var d0 = usize(y0) * stride + usize(x0)
        @nocheck {
        while pi < pairs {
            *mem.cast[*u32](&du[d0]) = *mem.cast[*u32](&k.obuf[pi * 16usize])
            *mem.cast[*u32](&dv[d0]) = *mem.cast[*u32](&k.obuf[pi * 16usize + 4usize])
            *mem.cast[*u32](&du[d0 + stride]) = *mem.cast[*u32](&k.obuf[pi * 16usize + 8usize])
            *mem.cast[*u32](&dv[d0 + stride]) = *mem.cast[*u32](&k.obuf[pi * 16usize + 12usize])
            d0 = d0 +% (2usize * stride)
            pi += 1usize
        }
        }
    } else {
        var t: Taps = zero
        fill_taps(&t, pri, sec, damping, dir, tap_set)
        edge_block(su, du, stride, pw, ph, x0, y0, 4i32, h, &t)
        edge_block(sv, dv, stride, pw, ph, x0, y0, 4i32, h, &t)
    }
}

fn cdef_frame(p: CdefParams, cdef_idx: []const i8, skips: []const u8, src: Planes, dst: Planes) -> err {
    ret cdef_rows(p, cdef_idx, skips, src, dst, 0usize, (usize(p.mi_rows) + 15usize) >> 4u32)
}

fn copy_rows(src: []const u8, dst: []u8, stride: usize, w: usize, y0: usize, y1: usize) {
    if y1 <= y0 { ret }
    copy_plane(src[y0 * stride..src.len], dst[y0 * stride..dst.len], stride, w, y1 - y0)
}

// Filters the superblock rows [sb_row_from, sb_row_to) (64 luma rows each, clamped to the picture) after
// copying exactly those rows of src to dst. Superblock rows read src only and write only their own dst
// rows, so any partition of 0..(mi_rows + 15) / 16 run in any order or concurrently gives the same dst as
// cdef_frame. No shared state: the scratch lives on the caller's stack.
fn cdef_rows(p: CdefParams, cdef_idx: []const i8, skips: []const u8, src: Planes, dst: Planes, sb_row_from: usize, sb_row_to: usize) -> err {
    if p.bit_depth != 8u32 { ret Invalid }
    let mi_rows = usize(p.mi_rows)
    let mi_cols = usize(p.mi_cols)
    let idx_stride = (mi_cols + 15usize) >> 4u32
    let r_from = sb_row_from * 16usize
    var r_to = sb_row_to * 16usize
    if r_to > mi_rows { r_to = mi_rows }
    if r_from >= r_to { ret ok }
    copy_rows(src.y, dst.y, src.stride_y, mi_cols * 4usize, r_from * 4usize, r_to * 4usize)
    let cw = (mi_cols * 4usize) >> p.sub_x
    let ch = (mi_rows * 4usize) >> p.sub_y
    let chroma = p.num_planes > 1u32
    if chroma {
        let c0 = (r_from * 4usize) >> p.sub_y
        let c1 = (r_to * 4usize) >> p.sub_y
        copy_rows(src.u, dst.u, src.stride_uv, cw, c0, c1)
        copy_rows(src.v, dst.v, src.stride_uv, cw, c0, c1)
    }
    let damping = i32(p.damping)
    let uv = uv_dir()
    var sbuf: [512]u8 = zero
    var obuf: [64]u8 = zero
    var offt: [96]usize = zero
    tap_offsets(offt[0usize..96usize])
    let wk = Work { sbuf: sbuf[0usize..512usize], obuf: obuf[0usize..64usize], offt: offt[0usize..96usize] }
    let ypw = i32(mi_cols * 4usize)
    let yph = i32(mi_rows * 4usize)
    let cpw = i32(cw)
    let cph = i32(ch)
    let bw = i32(8u32 >> p.sub_x)
    let bh = i32(8u32 >> p.sub_y)
    var r = r_from
    while r < r_to {
        var c = 0usize
        while c < mi_cols {
            let idx = i32(cdef_idx[(r >> 4u32) * idx_stride + (c >> 4u32)])
            if idx >= 0i32 {
                let s0 = r * mi_cols + c
                let busy = skips[s0] == 0u8 || skips[s0 + mi_cols] == 0u8 || skips[s0 + 1usize] == 0u8 || skips[s0 + mi_cols + 1usize] == 0u8
                if busy {
                    let i = usize(idx)
                    var pri = i32(p.y_pri[i])
                    let sec = i32(p.y_sec[i])
                    var upri = 0i32
                    var usec = 0i32
                    if chroma {
                        upri = i32(p.uv_pri[i])
                        usec = i32(p.uv_sec[i])
                    }
                    var y_dir = 0u32
                    var variance = 0u32
                    if pri != 0i32 || upri != 0i32 {
                        let (d0, v0) = direction(src.y, src.stride_y, c * 4usize, r * 4usize, 8u32)
                        y_dir = d0
                        variance = v0
                    }
                    var dir = y_dir
                    if pri == 0i32 { dir = 0u32 }
                    var var_str = 0i32
                    if (variance >> 6u32) != 0u32 { var_str = imin(floor_log2(variance >> 6u32), 12i32) }
                    if variance != 0u32 { pri = (pri * (4i32 + var_str) + 8i32) >> 4u32 } else { pri = 0i32 }
                    if pri != 0i32 || sec != 0i32 {
                        run_block(src.y, dst.y, src.stride_y, ypw, yph, i32(c * 4usize), i32(r * 4usize), 8i32, 8i32, pri, sec, damping, dir, usize(u32(pri) & 1u32), &wk)
                    }
                    if chroma && (upri != 0i32 || usec != 0i32) {
                        var udir = 0u32
                        if upri != 0i32 { udir = u32(uv[usize((p.sub_x * 2u32 + p.sub_y) * 8u32 + y_dir)]) }
                        let udamp = damping - 1i32
                        let utap = usize(u32(upri) & 1u32)
                        let ux = i32((c * 4usize) >> p.sub_x)
                        let uy = i32((r * 4usize) >> p.sub_y)
                        if bw == 4i32 {
                            run_uv(src.u, src.v, dst.u, dst.v, src.stride_uv, cpw, cph, ux, uy, bh, upri, usec, udamp, udir, utap, &wk)
                        } else {
                            run_block(src.u, dst.u, src.stride_uv, cpw, cph, ux, uy, bw, bh, upri, usec, udamp, udir, utap, &wk)
                            run_block(src.v, dst.v, src.stride_uv, cpw, cph, ux, uy, bw, bh, upri, usec, udamp, udir, utap, &wk)
                        }
                    }
                }
            }
            c += 2usize
        }
        r += 2usize
    }
    ret ok
}
