// AV1 constrained directional enhancement filter (CDEF), spec section 7.15, no superres.
//
// `cdef_frame(p, cdef_idx, skips, src, dst)` reads the deblocked planes `src` and writes the deringed
// planes `dst` (the spec's CurrFrame and CdefFrame). Both must cover MiRows*4 by MiCols*4 luma samples
// (and the subsampled size for chroma): samples past the picture edge but inside the mode-info grid are
// read and written like any other. `dst` is first made a copy of `src` over that area; only 8x8 blocks
// with a non-negative cdef_idx that are not all-skip are then filtered.
//   cdef_idx: one i8 per 64x64 luma block, row-major, ((mi_cols + 15) >> 4) per row; -1 = no filtering.
//   skips:    one nonzero/zero byte per 4x4 luma block (MiRows by MiCols, row-major), the spec's Skips.
//   CdefParams carries CdefDamping (3 + cdef_damping_minus_3) and the strength tables as stored in the
//   frame header (a sec strength of 3 is already 4, as the syntax makes it).
// `direction(plane, stride, x0, y0, bit_depth)` is the direction search for the 8x8 luma block at
// (x0, y0): it returns (yDir, var).
//
// A block whose taps all lie inside the picture takes an unchecked fast path (its extent is checked
// against the slice lengths first); the others use the generic path with the availability test. For 8-bit
// samples with strengths up to 15 the constrain function is a table lookup (one table per strength and
// plane kind, built when first used). When only one of the primary and secondary strengths is nonzero
// the min/max clamp is skipped: the tap weights sum to 12/16, so the result is already a convex
// combination of the sample and its taps. With both strengths zero the block is left as the copy.

use e.mem

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

type Planes = struct { y: []u16, u: []u16, v: []u16, stride_y: usize, stride_uv: usize }

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

fn abs_off(v: i32) -> i32 {
    if v < 0i32 { ret 0i32 - v }
    ret v
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

// The w by h samples at the top left of a plane, a row at a time and four samples per move.
fn copy_plane(src: []const u16, dst: []u16, stride: usize, w: usize, h: usize) {
    if w == 0usize || h == 0usize { ret }
    let last = (h - 1usize) * stride + w - 1usize
    dst[last] = src[last]
    let w4 = w & ~3usize
    var y = 0usize
    @nocheck {
    while y < h {
        let base = y * stride
        var x = 0usize
        while x < w4 {
            *mem.cast[*u64](&dst[base + x]) = *mem.cast[*u64](&src[base + x])
            x += 4usize
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

// part holds the 8 directions' sums at 15 entries each: 0 = i + j, 1 = i + j/2, 2 = i, 3 = 3 + i - j/2,
// 4 = 7 + i - j, 5 = 3 - i/2 + j, 6 = j, 7 = i/2 + j
fn direction(plane: []const u16, stride: usize, x0: usize, y0: usize, bit_depth: u32) -> (u32, u32) {
    var part: [120]i32 = zero
    var cost: [8]i32 = zero
    let sh = u16(bit_depth - 8u32)
    let guard = plane[(y0 + 7usize) * stride + x0 + 7usize]
    var i = 0usize
    @nocheck {
    while i < 8usize {
        let b = (y0 + i) * stride + x0
        let v0 = i32(plane[b] >> sh) - 128i32
        let v1 = i32(plane[b + 1usize] >> sh) - 128i32
        let v2 = i32(plane[b + 2usize] >> sh) - 128i32
        let v3 = i32(plane[b + 3usize] >> sh) - 128i32
        let v4 = i32(plane[b + 4usize] >> sh) - 128i32
        let v5 = i32(plane[b + 5usize] >> sh) - 128i32
        let v6 = i32(plane[b + 6usize] >> sh) - 128i32
        let v7 = i32(plane[b + 7usize] >> sh) - 128i32
        part[i] += v0
        part[i + 1usize] += v1
        part[i + 2usize] += v2
        part[i + 3usize] += v3
        part[i + 4usize] += v4
        part[i + 5usize] += v5
        part[i + 6usize] += v6
        part[i + 7usize] += v7
        part[67usize + i] += v0
        part[66usize + i] += v1
        part[65usize + i] += v2
        part[64usize + i] += v3
        part[63usize + i] += v4
        part[62usize + i] += v5
        part[61usize + i] += v6
        part[60usize + i] += v7
        part[30usize + i] = v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7
        part[90usize] += v0
        part[91usize] += v1
        part[92usize] += v2
        part[93usize] += v3
        part[94usize] += v4
        part[95usize] += v5
        part[96usize] += v6
        part[97usize] += v7
        let p0 = v0 + v1
        let p1 = v2 + v3
        let p2 = v4 + v5
        let p3 = v6 + v7
        part[15usize + i] += p0
        part[16usize + i] += p1
        part[17usize + i] += p2
        part[18usize + i] += p3
        part[48usize + i] += p0
        part[47usize + i] += p1
        part[46usize + i] += p2
        part[45usize + i] += p3
        let hi = i >> 1u32
        part[78usize - hi] += v0
        part[79usize - hi] += v1
        part[80usize - hi] += v2
        part[81usize - hi] += v3
        part[82usize - hi] += v4
        part[83usize - hi] += v5
        part[84usize - hi] += v6
        part[85usize - hi] += v7
        part[105usize + hi] += v0
        part[106usize + hi] += v1
        part[107usize + hi] += v2
        part[108usize + hi] += v3
        part[109usize + hi] += v4
        part[110usize + hi] += v5
        part[111usize + hi] += v6
        part[112usize + hi] += v7
        i += 1usize
    }
    // directions 2 and 6: eight sums each, weight 105
    var c2 = 0i32
    var c6 = 0i32
    i = 0usize
    while i < 8usize {
        c2 += sq(part[30usize + i])
        c6 += sq(part[90usize + i])
        i += 1usize
    }
    cost[2usize] = c2 * 105i32
    cost[6usize] = c6 * 105i32
    // directions 0 and 4: weights 840 420 280 210 168 140 120 105 at distance from the middle
    let dv: [8]i32 = [8]i32{ 840, 420, 280, 210, 168, 140, 120, 105 }
    var c0 = sq(part[7usize]) * 105i32
    var c4 = sq(part[67usize]) * 105i32
    i = 0usize
    while i < 7usize {
        c0 += (sq(part[i]) + sq(part[14usize - i])) * dv[i]
        c4 += (sq(part[60usize + i]) + sq(part[74usize - i])) * dv[i]
        i += 1usize
    }
    cost[0usize] = c0
    cost[4usize] = c4
    // directions 1 3 5 7: five middle entries weight 105, three on each side weight 840/ 420/ 280 pattern 2j+2
    var d = 1usize
    while d < 8usize {
        let o = d * 15usize
        var m = 0i32
        m += sq(part[o + 3usize])
        m += sq(part[o + 4usize])
        m += sq(part[o + 5usize])
        m += sq(part[o + 6usize])
        m += sq(part[o + 7usize])
        var c = m * 105i32
        c += (sq(part[o]) + sq(part[o + 10usize])) * dv[1usize]
        c += (sq(part[o + 1usize]) + sq(part[o + 9usize])) * dv[3usize]
        c += (sq(part[o + 2usize]) + sq(part[o + 8usize])) * dv[5usize]
        cost[d] = c
        d += 2usize
    }
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

// sample p of the block with the clamp: both strengths nonzero
fn fast_both(src: []const u16, dst: []u16, stride: usize, x0: usize, y0: usize, w: usize, h: usize, t: *const Taps) {
    let st = i32(stride)
    let po0 = t.dy[0usize] * st + t.dx[0usize]
    let po1 = t.dy[1usize] * st + t.dx[1usize]
    let sa0 = t.dy[2usize] * st + t.dx[2usize]
    let sa1 = t.dy[3usize] * st + t.dx[3usize]
    let sb0 = t.dy[4usize] * st + t.dx[4usize]
    let sb1 = t.dy[5usize] * st + t.dx[5usize]
    let pw0 = t.pw0
    let pw1 = t.pw1
    let pri = t.pri
    let sec = t.sec
    let padj = t.padj
    let sadj = t.sadj
    var i = 0usize
    @nocheck {
    while i < h {
        let base = (y0 + i) * stride + x0
        var j = 0usize
        while j < w {
            let q = i32(base + j)
            let x = i32(src[base + j])
            let a0 = i32(src[usize(q + po0)])
            let a1 = i32(src[usize(q - po0)])
            let a2 = i32(src[usize(q + po1)])
            let a3 = i32(src[usize(q - po1)])
            let b0 = i32(src[usize(q + sa0)])
            let b1 = i32(src[usize(q - sa0)])
            let b2 = i32(src[usize(q + sa1)])
            let b3 = i32(src[usize(q - sa1)])
            let c0 = i32(src[usize(q + sb0)])
            let c1 = i32(src[usize(q - sb0)])
            let c2 = i32(src[usize(q + sb1)])
            let c3 = i32(src[usize(q - sb1)])
            var sum = pw0 * (constrain(a0 - x, pri, padj) + constrain(a1 - x, pri, padj))
            sum += pw1 * (constrain(a2 - x, pri, padj) + constrain(a3 - x, pri, padj))
            sum += 2i32 * (constrain(b0 - x, sec, sadj) + constrain(b1 - x, sec, sadj) + constrain(c0 - x, sec, sadj) + constrain(c1 - x, sec, sadj))
            sum += constrain(b2 - x, sec, sadj) + constrain(b3 - x, sec, sadj) + constrain(c2 - x, sec, sadj) + constrain(c3 - x, sec, sadj)
            var hi = imax(imax(imax(a0, a1), imax(a2, a3)), imax(imax(b0, b1), imax(b2, b3)))
            hi = imax(imax(hi, x), imax(imax(c0, c1), imax(c2, c3)))
            var lo = imin(imin(imin(a0, a1), imin(a2, a3)), imin(imin(b0, b1), imin(b2, b3)))
            lo = imin(imin(lo, x), imin(imin(c0, c1), imin(c2, c3)))
            var neg = 0i32
            if sum < 0i32 { neg = 1i32 }
            let v = x + ((8i32 + sum - neg) >> 4u32)
            dst[base + j] = u16(imax(lo, imin(hi, v)))
            j += 1usize
        }
        i += 1usize
    }
    }
}

fn fast_pri(src: []const u16, dst: []u16, stride: usize, x0: usize, y0: usize, w: usize, h: usize, t: *const Taps) {
    let st = i32(stride)
    let po0 = t.dy[0usize] * st + t.dx[0usize]
    let po1 = t.dy[1usize] * st + t.dx[1usize]
    let pw0 = t.pw0
    let pw1 = t.pw1
    let pri = t.pri
    let padj = t.padj
    var i = 0usize
    @nocheck {
    while i < h {
        let base = (y0 + i) * stride + x0
        var j = 0usize
        while j < w {
            let q = i32(base + j)
            let x = i32(src[base + j])
            var sum = pw0 * (constrain(i32(src[usize(q + po0)]) - x, pri, padj) + constrain(i32(src[usize(q - po0)]) - x, pri, padj))
            sum += pw1 * (constrain(i32(src[usize(q + po1)]) - x, pri, padj) + constrain(i32(src[usize(q - po1)]) - x, pri, padj))
            var neg = 0i32
            if sum < 0i32 { neg = 1i32 }
            dst[base + j] = u16(x + ((8i32 + sum - neg) >> 4u32))
            j += 1usize
        }
        i += 1usize
    }
    }
}

fn fast_sec(src: []const u16, dst: []u16, stride: usize, x0: usize, y0: usize, w: usize, h: usize, t: *const Taps) {
    let st = i32(stride)
    let sa0 = t.dy[2usize] * st + t.dx[2usize]
    let sa1 = t.dy[3usize] * st + t.dx[3usize]
    let sb0 = t.dy[4usize] * st + t.dx[4usize]
    let sb1 = t.dy[5usize] * st + t.dx[5usize]
    let sec = t.sec
    let sadj = t.sadj
    var i = 0usize
    @nocheck {
    while i < h {
        let base = (y0 + i) * stride + x0
        var j = 0usize
        while j < w {
            let q = i32(base + j)
            let x = i32(src[base + j])
            var sum = 2i32 * (constrain(i32(src[usize(q + sa0)]) - x, sec, sadj) + constrain(i32(src[usize(q - sa0)]) - x, sec, sadj) + constrain(i32(src[usize(q + sb0)]) - x, sec, sadj) + constrain(i32(src[usize(q - sb0)]) - x, sec, sadj))
            sum += constrain(i32(src[usize(q + sa1)]) - x, sec, sadj) + constrain(i32(src[usize(q - sa1)]) - x, sec, sadj) + constrain(i32(src[usize(q + sb1)]) - x, sec, sadj) + constrain(i32(src[usize(q - sb1)]) - x, sec, sadj)
            var neg = 0i32
            if sum < 0i32 { neg = 1i32 }
            dst[base + j] = u16(x + ((8i32 + sum - neg) >> 4u32))
            j += 1usize
        }
        i += 1usize
    }
    }
}


const NOTAB: usize = 1000000usize

// constrain() of every difference -255..255 for the strengths 1..15 of 8-bit samples, 512 entries per
// strength and plane kind (luma, chroma: the damping differs); built when first used
fn table_at(tabs: []i32, built: []u8, thr: i32, kind: usize, damping: i32) -> usize {
    if thr <= 0i32 || thr > 15i32 { ret NOTAB }
    let key = usize(thr) * 2usize + kind
    let at = key * 512usize
    if built[key] == 0u8 {
        let adj = damp_shift(thr, damping)
        var d = 0i32 - 255i32
        while d <= 255i32 {
            tabs[at + usize(d + 255i32)] = constrain(d, thr, adj)
            d += 1i32
        }
        built[key] = 1u8
    }
    ret at
}

// The table versions of the fast paths: a tap pair is q + o and q - o (o = |offset|); the table for a
// pixel x is indexed by tap + 255 - x.
fn tab_pri(src: []const u16, dst: []u16, stride: usize, x0: usize, y0: usize, w: usize, h: usize, t: *const Taps, tabs: []const i32, pt: usize) {
    let o0 = usize(abs_off(t.dy[0usize] * i32(stride) + t.dx[0usize]))
    let o1 = usize(abs_off(t.dy[1usize] * i32(stride) + t.dx[1usize]))
    let pw0 = t.pw0
    let pw1 = t.pw1
    let tp = tabs[pt..pt + 512usize]
    var i = 0usize
    @nocheck {
    while i < h {
        let base = (y0 + i) * stride + x0
        var j = 0usize
        while j < w {
            let qs = base + j
            let xu = usize(src[qs])
            let c = 255usize - xu
            var sum = pw0 * (tp[usize(src[qs + o0]) + c] + tp[usize(src[qs - o0]) + c])
            sum += pw1 * (tp[usize(src[qs + o1]) + c] + tp[usize(src[qs - o1]) + c])
            dst[qs] = u16(i32(xu) + ((8i32 + sum + (sum >> 31u32)) >> 4u32))
            j += 1usize
        }
        i += 1usize
    }
    }
}

fn tab_sec(src: []const u16, dst: []u16, stride: usize, x0: usize, y0: usize, w: usize, h: usize, t: *const Taps, tabs: []const i32, st: usize) {
    let st32 = i32(stride)
    let a0 = usize(abs_off(t.dy[2usize] * st32 + t.dx[2usize]))
    let a1 = usize(abs_off(t.dy[3usize] * st32 + t.dx[3usize]))
    let b0 = usize(abs_off(t.dy[4usize] * st32 + t.dx[4usize]))
    let b1 = usize(abs_off(t.dy[5usize] * st32 + t.dx[5usize]))
    let ts = tabs[st..st + 512usize]
    var i = 0usize
    @nocheck {
    while i < h {
        let base = (y0 + i) * stride + x0
        var j = 0usize
        while j < w {
            let qs = base + j
            let xu = usize(src[qs])
            let c = 255usize - xu
            var sum = 2i32 * (ts[usize(src[qs + a0]) + c] + ts[usize(src[qs - a0]) + c] + ts[usize(src[qs + b0]) + c] + ts[usize(src[qs - b0]) + c])
            sum += ts[usize(src[qs + a1]) + c] + ts[usize(src[qs - a1]) + c] + ts[usize(src[qs + b1]) + c] + ts[usize(src[qs - b1]) + c]
            dst[qs] = u16(i32(xu) + ((8i32 + sum + (sum >> 31u32)) >> 4u32))
            j += 1usize
        }
        i += 1usize
    }
    }
}

fn tab_both(src: []const u16, dst: []u16, stride: usize, x0: usize, y0: usize, w: usize, h: usize, t: *const Taps, tabs: []const i32, pt: usize, st: usize) {
    let st32 = i32(stride)
    let o0 = usize(abs_off(t.dy[0usize] * st32 + t.dx[0usize]))
    let o1 = usize(abs_off(t.dy[1usize] * st32 + t.dx[1usize]))
    let a0 = usize(abs_off(t.dy[2usize] * st32 + t.dx[2usize]))
    let a1 = usize(abs_off(t.dy[3usize] * st32 + t.dx[3usize]))
    let b0 = usize(abs_off(t.dy[4usize] * st32 + t.dx[4usize]))
    let b1 = usize(abs_off(t.dy[5usize] * st32 + t.dx[5usize]))
    let pw0 = t.pw0
    let pw1 = t.pw1
    let tp = tabs[pt..pt + 512usize]
    let ts = tabs[st..st + 512usize]
    var i = 0usize
    @nocheck {
    while i < h {
        let base = (y0 + i) * stride + x0
        var j = 0usize
        while j < w {
            let qs = base + j
            let xu = usize(src[qs])
            let c = 255usize - xu
            let p0 = usize(src[qs + o0])
            let p1 = usize(src[qs - o0])
            let p2 = usize(src[qs + o1])
            let p3 = usize(src[qs - o1])
            let s0 = usize(src[qs + a0])
            let s1 = usize(src[qs - a0])
            let s2 = usize(src[qs + a1])
            let s3 = usize(src[qs - a1])
            let s4 = usize(src[qs + b0])
            let s5 = usize(src[qs - b0])
            let s6 = usize(src[qs + b1])
            let s7 = usize(src[qs - b1])
            var sum = pw0 * (tp[p0 + c] + tp[p1 + c]) + pw1 * (tp[p2 + c] + tp[p3 + c])
            sum += 2i32 * (ts[s0 + c] + ts[s1 + c] + ts[s4 + c] + ts[s5 + c])
            sum += ts[s2 + c] + ts[s3 + c] + ts[s6 + c] + ts[s7 + c]
            let delta = (8i32 + sum + (sum >> 31u32)) >> 4u32
            var v = xu
            if delta > 0i32 {
                v = xu + usize(delta)
                var hi = xu
                if p0 > hi { hi = p0 }
                if p1 > hi { hi = p1 }
                if p2 > hi { hi = p2 }
                if p3 > hi { hi = p3 }
                if s0 > hi { hi = s0 }
                if s1 > hi { hi = s1 }
                if s2 > hi { hi = s2 }
                if s3 > hi { hi = s3 }
                if s4 > hi { hi = s4 }
                if s5 > hi { hi = s5 }
                if s6 > hi { hi = s6 }
                if s7 > hi { hi = s7 }
                if v > hi { v = hi }
            } else if delta < 0i32 {
                var vn = i32(xu) + delta
                var lo = xu
                if p0 < lo { lo = p0 }
                if p1 < lo { lo = p1 }
                if p2 < lo { lo = p2 }
                if p3 < lo { lo = p3 }
                if s0 < lo { lo = s0 }
                if s1 < lo { lo = s1 }
                if s2 < lo { lo = s2 }
                if s3 < lo { lo = s3 }
                if s4 < lo { lo = s4 }
                if s5 < lo { lo = s5 }
                if s6 < lo { lo = s6 }
                if s7 < lo { lo = s7 }
                if vn < i32(lo) { vn = i32(lo) }
                v = usize(vn)
            }
            dst[qs] = u16(v)
            j += 1usize
        }
        i += 1usize
    }
    }
}

// Every tap tested against the picture edge; for the blocks that touch it.
fn edge_block(src: []const u16, dst: []u16, stride: usize, pw: i32, ph: i32, x0: i32, y0: i32, w: i32, h: i32, t: *const Taps) {
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
            dst[usize(y0 + i) * stride + usize(x0 + j)] = u16(imax(lo, imin(hi, v)))
            j += 1i32
        }
        i += 1i32
    }
}

// pw/ph: size of the plane area in samples; x0/y0/w/h: the block
fn run_block(src: []const u16, dst: []u16, stride: usize, pw: i32, ph: i32, x0: i32, y0: i32, w: i32, h: i32, pri: i32, sec: i32, damping: i32, dir: u32, tap_set: usize, tabs: []const i32, pt: usize, st: usize) {
    var t: Taps = zero
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
    let reach = usize(y0 + h + 1i32) * stride + usize(x0 + w + 1i32)
    if x0 >= 2i32 && y0 >= 2i32 && x0 + w + 2i32 <= pw && y0 + h + 2i32 <= ph && reach < src.len && reach < dst.len && (pri != 0i32 || sec != 0i32) {
        if sec == 0i32 {
            if pt != NOTAB {
                tab_pri(src, dst, stride, usize(x0), usize(y0), usize(w), usize(h), &t, tabs, pt)
            } else {
                fast_pri(src, dst, stride, usize(x0), usize(y0), usize(w), usize(h), &t)
            }
        } else if pri == 0i32 {
            if st != NOTAB {
                tab_sec(src, dst, stride, usize(x0), usize(y0), usize(w), usize(h), &t, tabs, st)
            } else {
                fast_sec(src, dst, stride, usize(x0), usize(y0), usize(w), usize(h), &t)
            }
        } else if pt != NOTAB && st != NOTAB {
            tab_both(src, dst, stride, usize(x0), usize(y0), usize(w), usize(h), &t, tabs, pt, st)
        } else {
            fast_both(src, dst, stride, usize(x0), usize(y0), usize(w), usize(h), &t)
        }
    } else {
        edge_block(src, dst, stride, pw, ph, x0, y0, w, h, &t)
    }
}

fn filter_block(p: CdefParams, src: []const u16, dst: []u16, stride: usize, plane: u32, r: u32, c: u32, pri_str: i32, sec_str: i32, damping: i32, dir: u32) {
    var sub_x = 0u32
    var sub_y = 0u32
    if plane > 0u32 {
        sub_x = p.sub_x
        sub_y = p.sub_y
    }
    let coeff_shift = p.bit_depth - 8u32
    let tap_set = usize((u32(pri_str) >> coeff_shift) & 1u32)
    let pw = i32((p.mi_cols * 4u32) >> sub_x)
    let ph = i32((p.mi_rows * 4u32) >> sub_y)
    var none: [1]i32 = zero
    run_block(src, dst, stride, pw, ph, i32((c * 4u32) >> sub_x), i32((r * 4u32) >> sub_y), i32(8u32 >> sub_x), i32(8u32 >> sub_y), pri_str, sec_str, damping, dir, tap_set, none[0usize..1usize], NOTAB, NOTAB)
}

fn cdef_frame(p: CdefParams, cdef_idx: []const i8, skips: []const u8, src: Planes, dst: Planes) {
    cdef_rows(p, cdef_idx, skips, src, dst, 0usize, (usize(p.mi_rows) + 15usize) >> 4u32)
}

fn copy_rows(src: []const u16, dst: []u16, stride: usize, w: usize, y0: usize, y1: usize) {
    if y1 <= y0 { ret }
    copy_plane(src[y0 * stride..src.len], dst[y0 * stride..dst.len], stride, w, y1 - y0)
}

// Filters the superblock rows [sb_row_from, sb_row_to) (64 luma rows each, clamped to the picture) after
// copying exactly those rows of src to dst. Superblock rows read src only and write only their own dst
// rows, so any partition of 0..(mi_rows + 15) / 16 run in any order or concurrently gives the same dst as
// cdef_frame. No shared state: the constrain tables live on the caller's stack.
fn cdef_rows(p: CdefParams, cdef_idx: []const i8, skips: []const u8, src: Planes, dst: Planes, sb_row_from: usize, sb_row_to: usize) {
    let mi_rows = usize(p.mi_rows)
    let mi_cols = usize(p.mi_cols)
    let idx_stride = (mi_cols + 15usize) >> 4u32
    let r_from = sb_row_from * 16usize
    var r_to = sb_row_to * 16usize
    if r_to > mi_rows { r_to = mi_rows }
    if r_from >= r_to { ret }
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
    let coeff_shift = p.bit_depth - 8u32
    let damping = i32(p.damping + coeff_shift)
    let uv = uv_dir()
    var tabs: [16384]i32 = zero
    var built: [32]u8 = zero
    let use_tabs = p.bit_depth == 8u32
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
                    var pri = i32(p.y_pri[i] << coeff_shift)
                    let sec = i32(p.y_sec[i] << coeff_shift)
                    var upri = 0i32
                    var usec = 0i32
                    if chroma {
                        upri = i32(p.uv_pri[i] << coeff_shift)
                        usec = i32(p.uv_sec[i] << coeff_shift)
                    }
                    var y_dir = 0u32
                    var variance = 0u32
                    if pri != 0i32 || upri != 0i32 {
                        let (d0, v0) = direction(src.y, src.stride_y, c * 4usize, r * 4usize, p.bit_depth)
                        y_dir = d0
                        variance = v0
                    }
                    var dir = y_dir
                    if pri == 0i32 { dir = 0u32 }
                    var var_str = 0i32
                    if (variance >> 6u32) != 0u32 { var_str = imin(floor_log2(variance >> 6u32), 12i32) }
                    if variance != 0u32 { pri = (pri * (4i32 + var_str) + 8i32) >> 4u32 } else { pri = 0i32 }
                    if pri != 0i32 || sec != 0i32 {
                        var ypt = NOTAB
                        var yst = NOTAB
                        if use_tabs {
                            ypt = table_at(tabs[0usize..16384usize], built[0usize..32usize], pri, 0usize, damping)
                            yst = table_at(tabs[0usize..16384usize], built[0usize..32usize], sec, 0usize, damping)
                        }
                        run_block(src.y, dst.y, src.stride_y, ypw, yph, i32(c * 4usize), i32(r * 4usize), 8i32, 8i32, pri, sec, damping, dir, usize((u32(pri) >> coeff_shift) & 1u32), tabs[0usize..16384usize], ypt, yst)
                    }
                    if chroma && (upri != 0i32 || usec != 0i32) {
                        var udir = 0u32
                        if upri != 0i32 { udir = u32(uv[usize((p.sub_x * 2u32 + p.sub_y) * 8u32 + y_dir)]) }
                        let udamp = damping - 1i32
                        let utap = usize((u32(upri) >> coeff_shift) & 1u32)
                        let ux = i32((c * 4usize) >> p.sub_x)
                        let uy = i32((r * 4usize) >> p.sub_y)
                        var cpt = NOTAB
                        var cst = NOTAB
                        if use_tabs {
                            cpt = table_at(tabs[0usize..16384usize], built[0usize..32usize], upri, 1usize, udamp)
                            cst = table_at(tabs[0usize..16384usize], built[0usize..32usize], usec, 1usize, udamp)
                        }
                        run_block(src.u, dst.u, src.stride_uv, cpw, cph, ux, uy, bw, bh, upri, usec, udamp, udir, utap, tabs[0usize..16384usize], cpt, cst)
                        run_block(src.v, dst.v, src.stride_uv, cpw, cph, ux, uy, bw, bh, upri, usec, udamp, udir, utap, tabs[0usize..16384usize], cpt, cst)
                    }
                }
            }
            c += 2usize
        }
        r += 2usize
    }
}
