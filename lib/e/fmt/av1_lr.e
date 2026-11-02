// AV1 loop restoration (Wiener and self-guided filters), spec section 7.17, no superres.
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
// inside one stripe and one unit, which the spec notes gives the same result.
//
// The scratch space (about 100 KB) comes from the arena and is released again before the call returns.
// The inner loops are unchecked: the sample slices are checked against the plane size once, up front
// (Invalid when a plane slice is too short), and every other index is bounded by the fixed scratch sizes.
// Everything is 32-bit: for samples of up to 12 bits and the coefficient ranges the syntax allows
// (wiener taps, sgr weights) no intermediate exceeds 2^31 except the self-guided product p * s, which
// is formed in 64 bits.

use e.mem

const RESTORE_NONE: u32 = 0u32
const RESTORE_WIENER: u32 = 1u32
const RESTORE_SGRPROJ: u32 = 2u32

// rtype is LrType (RESTORE_*); wiener is LrWiener[..][0] (vertical, 3 taps) then LrWiener[..][1] (horizontal);
// xqd0/xqd1 are LrSgrXqd.
type LrUnit = struct { rtype: u32, wiener: [6]i32, sgr_set: u32, xqd0: i32, xqd1: i32 }

type Src = struct { pre: []const u16, cdef: []const u16, stride: usize, end_x: i32, end_y: i32, stripe_start: i32, stripe_end: i32 }

// win: the (h + 6) by (w + 6) window of source samples around a block (stride WIN); inter: wiener's
// horizontal pass; flt0/flt1: the two self-guided filter outputs; a_arr/b_arr: the box filter's A and B
// (stride AB); cola/colb: column sums of one row of boxes; a2tab: the A value for each z
type Scratch = struct { win: []u16, inter: []i32, flt0: []i32, flt1: []i32, a_arr: []i32, b_arr: []i32, cola: []i32, colb: []i32, a2tab: []i32 }

error Invalid

const WIN: usize = 70usize
const AB: usize = 66usize
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

fn round2(x: i64, n: u32) -> i64 {
    if n == 0u32 { ret x }
    ret (x + (1i64 << (n - 1u32))) >> n
}

fn round2_32(x: i32, n: u32) -> i32 {
    if n == 0u32 { ret x }
    ret (x + (1i32 << (n - 1u32))) >> n
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

// Fills the window of the block at (x, y), w by h, from the stripe-aware source of the spec (rows
// outside the stripe come from the deblocked frame, at most two beyond it).
fn stage(win: []u16, s: *const Src, x: i32, y: i32, w: i32, h: i32) {
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
            @nocheck {
            while k + 4usize <= ww {
                *mem.cast[*u64](&win[wb + k]) = *mem.cast[*u64](&srow[xb + k])
                k += 4usize
            }
            while k < ww {
                win[wb + k] = srow[xb + k]
                k += 1usize
            }
            }
        } else {
            var jx = 0usize
            while jx < ww {
                let xs = imax(0i32, imin(s.end_x, x - 3i32 + i32(jx)))
                win[wb + jx] = srow[rb + usize(xs)]
                jx += 1usize
            }
        }
        iy += 1i32
    }
}

// One pass of the box filter: the result lands in f (stride FL) and is only meaningful when the pass's
// radius is nonzero.
fn box_filter(win: []const u16, w: usize, h: usize, bit_depth: u32, set: usize, pass: usize, a_arr: []i32, b_arr: []i32, cola: []i32, colb: []i32, a2tab: []const i32, f: []i32) {
    let tab = sgr_params()
    let rr = usize(tab[set * 4usize + pass * 2usize])
    if rr == 0usize { ret }
    let eps = i64(tab[set * 4usize + pass * 2usize + 1usize])
    let nn = i32((2usize * rr + 1usize) * (2usize * rr + 1usize))
    let n2e = i64(nn) * i64(nn) * eps
    let sc = ((1i64 << 20u32) + n2e / 2i64) / n2e
    let one_over_n = i64(((1i32 << 12u32) + nn / 2i32) / nn)
    let ash = 2u32 * (bit_depth - 8u32)
    let bsh = bit_depth - 8u32
    let ww = w + 6usize
    let hi_i = i32(h)
    var i = 0i32 - 1i32
    @nocheck {
    while i <= hi_i {
        if pass == 1usize || (i & 1i32) != 0i32 {
            // column sums over the 2r + 1 rows around row i
            let r0 = usize(i + 3i32) - rr
            let b0 = r0 * WIN
            var c = 0usize
            if rr == 2usize {
                while c < ww {
                    let v0 = i32(win[b0 + c])
                    let v1 = i32(win[b0 + WIN + c])
                    let v2 = i32(win[b0 + 2usize * WIN + c])
                    let v3 = i32(win[b0 + 3usize * WIN + c])
                    let v4 = i32(win[b0 + 4usize * WIN + c])
                    colb[c] = v0 + v1 + v2 + v3 + v4
                    cola[c] = v0 * v0 + v1 * v1 + v2 * v2 + v3 * v3 + v4 * v4
                    c += 1usize
                }
            } else {
                while c < ww {
                    let v0 = i32(win[b0 + c])
                    let v1 = i32(win[b0 + WIN + c])
                    let v2 = i32(win[b0 + 2usize * WIN + c])
                    colb[c] = v0 + v1 + v2
                    cola[c] = v0 * v0 + v1 * v1 + v2 * v2
                    c += 1usize
                }
            }
            // slide the horizontal window: position j (from -1) has its centre at column j + 3
            var sb = 0i32
            var sa = 0i32
            c = 2usize - rr
            while c <= 2usize + rr {
                sb += colb[c]
                sa += cola[c]
                c += 1usize
            }
            let rowat = usize(i + 1i32) * AB
            var j = 0usize
            while j <= w + 1usize {
                // j is the position + 1
                var a = round2_32(sa, ash)
                let d = round2_32(sb, bsh)
                var p = a * nn - d * d
                if p < 0i32 { p = 0i32 }
                var z = (i64(p) * sc + (1i64 << 19u32)) >> 20u32
                if z > 255i64 { z = 255i64 }
                let a2 = a2tab[usize(z)]
                a_arr[rowat + j] = a2
                b_arr[rowat + j] = i32((i64(256i32 - a2) * i64(sb) * one_over_n + 2048i64) >> 12u32)
                if j <= w {
                    sb = sb + colb[j + 3usize + rr] - colb[j + 2usize - rr]
                    sa = sa + cola[j + 3usize + rr] - cola[j + 2usize - rr]
                }
                j += 1usize
            }
        }
        i += 1i32
    }
    // weighted sums of the neighbouring A and B values
    if pass == 0usize {
        var y = 0usize
        while y < h {
            let wb = (y + 3usize) * WIN + 3usize
            var x = 0usize
            if (y & 1usize) != 0usize {
                let rm = (y + 1usize) * AB + 1usize
                while x < w {
                    let at = rm + x
                    let a = 6i32 * a_arr[at] + 5i32 * (a_arr[at - 1usize] + a_arr[at + 1usize])
                    let b = 6i32 * b_arr[at] + 5i32 * (b_arr[at - 1usize] + b_arr[at + 1usize])
                    f[y * FL + x] = (a * i32(win[wb + x]) + b + 128i32) >> 8u32
                    x += 1usize
                }
            } else {
                let ru = y * AB + 1usize
                let rd = (y + 2usize) * AB + 1usize
                while x < w {
                    let au = ru + x
                    let ad = rd + x
                    let a = 6i32 * (a_arr[au] + a_arr[ad]) + 5i32 * (a_arr[au - 1usize] + a_arr[au + 1usize] + a_arr[ad - 1usize] + a_arr[ad + 1usize])
                    let b = 6i32 * (b_arr[au] + b_arr[ad]) + 5i32 * (b_arr[au - 1usize] + b_arr[au + 1usize] + b_arr[ad - 1usize] + b_arr[ad + 1usize])
                    f[y * FL + x] = (a * i32(win[wb + x]) + b + 256i32) >> 9u32
                    x += 1usize
                }
            }
            y += 1usize
        }
    } else {
        var y = 0usize
        while y < h {
            let wb = (y + 3usize) * WIN + 3usize
            let ru = y * AB + 1usize
            let rm = (y + 1usize) * AB + 1usize
            let rd = (y + 2usize) * AB + 1usize
            var x = 0usize
            while x < w {
                let au = ru + x
                let am = rm + x
                let ad = rd + x
                let a = 4i32 * (a_arr[am] + a_arr[am - 1usize] + a_arr[am + 1usize] + a_arr[au] + a_arr[ad]) + 3i32 * (a_arr[au - 1usize] + a_arr[au + 1usize] + a_arr[ad - 1usize] + a_arr[ad + 1usize])
                let b = 4i32 * (b_arr[am] + b_arr[am - 1usize] + b_arr[am + 1usize] + b_arr[au] + b_arr[ad]) + 3i32 * (b_arr[au - 1usize] + b_arr[au + 1usize] + b_arr[ad - 1usize] + b_arr[ad + 1usize])
                f[y * FL + x] = (a * i32(win[wb + x]) + b + 256i32) >> 9u32
                x += 1usize
            }
            y += 1usize
        }
    }
    }
}

fn self_guided(sc: *const Scratch, u: *const LrUnit, w: usize, h: usize, bit_depth: u32, out: []u16, out_stride: usize, x: usize, y: usize) {
    let set = usize(u.sgr_set)
    box_filter(sc.win, w, h, bit_depth, set, 0usize, sc.a_arr, sc.b_arr, sc.cola, sc.colb, sc.a2tab, sc.flt0)
    box_filter(sc.win, w, h, bit_depth, set, 1usize, sc.a_arr, sc.b_arr, sc.cola, sc.colb, sc.a2tab, sc.flt1)
    let tab = sgr_params()
    let r0 = tab[set * 4usize]
    let r1 = tab[set * 4usize + 2usize]
    let w0 = u.xqd0
    let w1 = u.xqd1
    let w2 = 128i32 - w0 - w1
    let top = (1i32 << bit_depth) - 1i32
    let win = sc.win
    let flt0 = sc.flt0
    let flt1 = sc.flt1
    var i = 0usize
    @nocheck {
    while i < h {
        let wb = (i + 3usize) * WIN + 3usize
        let ob = (y + i) * out_stride + x
        let fb = i * FL
        var j = 0usize
        while j < w {
            let uu = i32(win[wb + j]) << 4u32
            var v = w1 * uu
            if r0 != 0u8 { v += w0 * flt0[fb + j] } else { v += w0 * uu }
            if r1 != 0u8 { v += w2 * flt1[fb + j] } else { v += w2 * uu }
            v = (v + 1024i32) >> 11u32
            if v < 0i32 { v = 0i32 }
            if v > top { v = top }
            out[ob + j] = u16(v)
            j += 1usize
        }
        i += 1usize
    }
    }
}

fn wiener(sc: *const Scratch, u: *const LrUnit, w: usize, h: usize, bit_depth: u32, out: []u16, out_stride: usize, x: usize, y: usize) {
    var round0 = 3u32
    var round1 = 11u32
    if bit_depth == 12u32 {
        round0 = 5u32
        round1 = 9u32
    }
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
    let offset = 1i32 << (bit_depth + 7u32 - round0 - 1u32)
    let limit = (1i32 << (bit_depth + 1u32 + 7u32 - round0)) - 1i32
    let lo = 0i32 - offset
    let hi = limit - offset
    let rnd0 = 1i32 << (round0 - 1u32)
    let rnd1 = 1i32 << (round1 - 1u32)
    let top = (1i32 << bit_depth) - 1i32
    let win = sc.win
    let inter = sc.inter
    var r = 0usize
    @nocheck {
    while r < h + 6usize {
        let wb = r * WIN
        let ib = r * FL
        var c = 0usize
        while c < w {
            let q = wb + c
            let s = hc0 * (i32(win[q]) + i32(win[q + 6usize])) + hc1 * (i32(win[q + 1usize]) + i32(win[q + 5usize])) + hc2 * (i32(win[q + 2usize]) + i32(win[q + 4usize])) + hc3 * i32(win[q + 3usize])
            var v = (s + rnd0) >> round0
            if v < lo { v = lo }
            if v > hi { v = hi }
            inter[ib + c] = v
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < h {
        let ob = (y + r) * out_stride + x
        let ib = r * FL
        var c = 0usize
        while c < w {
            let q = ib + c
            let s = vc0 * (inter[q] + inter[q + 6usize * FL]) + vc1 * (inter[q + FL] + inter[q + 5usize * FL]) + vc2 * (inter[q + 2usize * FL] + inter[q + 4usize * FL]) + vc3 * inter[q + 3usize * FL]
            var v = (s + rnd1) >> round1
            if v < 0i32 { v = 0i32 }
            if v > top { v = top }
            out[ob + c] = u16(v)
            c += 1usize
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

fn restore_plane(a: *mem.Arena, bit_depth: u32, sub_x: u32, sub_y: u32, frame_w: u32, frame_h: u32, pre: []const u16, cdef: []const u16, out: []u16, stride: usize, unit_size: u32, units: []const LrUnit) -> err {
    ret restore_rows(a, bit_depth, sub_x, sub_y, frame_w, frame_h, pre, cdef, out, stride, unit_size, units, 0u32, count_stripes(frame_h, sub_y))
}

// Restores the stripes [stripe_from, stripe_to) of a plane (clamped to count_stripes) and writes only
// their rows of `out`, the plain copy of the cdef rows included. Stripes are independent: they read
// `pre` and `cdef` only, so any partition of 0..count_stripes(frame_h, sub_y) into ranges, run in any
// order or concurrently (one arena `a` per worker, it holds the ~100 KB scratch), gives the same `out` as
// restore_plane. Ranges may be cut at any stripe boundary; unit boundaries need no alignment.
fn restore_rows(a: *mem.Arena, bit_depth: u32, sub_x: u32, sub_y: u32, frame_w: u32, frame_h: u32, pre: []const u16, cdef: []const u16, out: []u16, stride: usize, unit_size: u32, units: []const LrUnit, stripe_from: u32, stripe_to: u32) -> err {
    let pw = i32((frame_w + sub_x) >> sub_x)
    let ph = i32((frame_h + sub_y) >> sub_y)
    if unit_size == 0u32 { ret Invalid }
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
    let (win_buf, win_buf_err) = mem.alloc[u16](a, WIN * WIN)
    if win_buf_err != ok { ret win_buf_err }
    let (inter, inter_err) = mem.alloc[i32](a, WIN * FL)
    if inter_err != ok { ret inter_err }
    let (flt0, flt0_err) = mem.alloc[i32](a, FL * FL)
    if flt0_err != ok { ret flt0_err }
    let (flt1, flt1_err) = mem.alloc[i32](a, FL * FL)
    if flt1_err != ok { ret flt1_err }
    let (a_arr, a_arr_err) = mem.alloc[i32](a, AB * AB)
    if a_arr_err != ok { ret a_arr_err }
    let (b_arr, b_arr_err) = mem.alloc[i32](a, AB * AB)
    if b_arr_err != ok { ret b_arr_err }
    let (cola, cola_err) = mem.alloc[i32](a, WIN)
    if cola_err != ok { ret cola_err }
    let (colb, colb_err) = mem.alloc[i32](a, WIN)
    if colb_err != ok { ret colb_err }
    let (a2tab, a2tab_err) = mem.alloc[i32](a, 256usize)
    if a2tab_err != ok { ret a2tab_err }
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
                        wiener(&sc, u, usize(w), usize(h), bit_depth, out, stride, usize(x), usize(y))
                    } else {
                        self_guided(&sc, u, usize(w), usize(h), bit_depth, out, stride, usize(x), usize(y))
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
