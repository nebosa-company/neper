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

use e.mem

const RESTORE_NONE: u32 = 0u32
const RESTORE_WIENER: u32 = 1u32
const RESTORE_SGRPROJ: u32 = 2u32

// rtype is LrType (RESTORE_*); wiener is LrWiener[..][0] (vertical, 3 taps) then LrWiener[..][1] (horizontal);
// xqd0/xqd1 are LrSgrXqd.
type LrUnit = struct { rtype: u32, wiener: [6]i32, sgr_set: u32, xqd0: i32, xqd1: i32 }

type Src = struct { pre: []const u16, cdef: []const u16, stride: usize, end_x: i32, end_y: i32, stripe_start: i32, stripe_end: i32 }

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

fn clip1(v: i64, bit_depth: u32) -> u16 {
    let top = (1i64 << bit_depth) - 1i64
    if v < 0i64 { ret 0u16 }
    if v > top { ret u16(top) }
    ret u16(v)
}

fn source_sample(s: *Src, x_in: i32, y_in: i32) -> i32 {
    let x = imax(0i32, imin(s.end_x, x_in))
    var y = imax(0i32, imin(s.end_y, y_in))
    if y < s.stripe_start {
        y = imax(s.stripe_start - 2i32, y)
        ret i32(s.pre[usize(y) * s.stride + usize(x)])
    }
    if y > s.stripe_end {
        y = imin(s.stripe_end + 2i32, y)
        ret i32(s.pre[usize(y) * s.stride + usize(x)])
    }
    ret i32(s.cdef[usize(y) * s.stride + usize(x)])
}

// The box filter process for one pass: win is the (h+6) by (w+6) window of source samples around the block,
// the result lands in f (stride FL) and is only meaningful when the pass's radius is nonzero.
fn box_filter(win: []const i32, w: usize, h: usize, bit_depth: u32, set: usize, pass: usize, a_arr: []i64, b_arr: []i64, f: []i32) {
    let tab = sgr_params()
    let r = i32(tab[set * 4usize + pass * 2usize])
    if r == 0i32 { ret }
    let eps = i64(tab[set * 4usize + pass * 2usize + 1usize])
    let n = i64((2i32 * r + 1i32) * (2i32 * r + 1i32))
    let n2e = n * n * eps
    let s = ((1i64 << 20u32) + n2e / 2i64) / n2e
    let one_over_n = ((1i64 << 12u32) + n / 2i64) / n
    var i = 0i32 - 1i32
    while i < i32(h) + 1i32 {
        // pass 0 only ever reads odd rows
        if pass == 1usize || (i & 1i32) != 0i32 {
            var j = 0i32 - 1i32
            while j < i32(w) + 1i32 {
                var a = 0i64
                var b = 0i64
                var dy = 0i32 - r
                while dy <= r {
                    var dx = 0i32 - r
                    while dx <= r {
                        let c = i64(win[usize(i + dy + 3i32) * WIN + usize(j + dx + 3i32)])
                        a += c * c
                        b += c
                        dx += 1i32
                    }
                    dy += 1i32
                }
                a = round2(a, 2u32 * (bit_depth - 8u32))
                let d = round2(b, bit_depth - 8u32)
                var p = a * n - d * d
                if p < 0i64 { p = 0i64 }
                let z = round2(p * s, 20u32)
                var a2 = 0i64
                if z >= 255i64 {
                    a2 = 256i64
                } else if z == 0i64 {
                    a2 = 1i64
                } else {
                    a2 = ((z << 8u32) + z / 2i64) / (z + 1i64)
                }
                let b2 = (256i64 - a2) * b * one_over_n
                let at = usize(i + 1i32) * AB + usize(j + 1i32)
                a_arr[at] = a2
                b_arr[at] = round2(b2, 12u32)
                j += 1i32
            }
        }
        i += 1i32
    }
    i = 0i32
    while i < i32(h) {
        var shift = 5u32
        if pass == 0usize && (i & 1i32) != 0i32 { shift = 4u32 }
        var j = 0i32
        while j < i32(w) {
            var a = 0i64
            var b = 0i64
            var dy = 0i32 - 1i32
            while dy <= 1i32 {
                var dx = 0i32 - 1i32
                while dx <= 1i32 {
                    var weight = 0i64
                    if pass == 0usize {
                        if ((i + dy) & 1i32) != 0i32 {
                            if dx == 0i32 { weight = 6i64 } else { weight = 5i64 }
                        }
                    } else {
                        if dx == 0i32 || dy == 0i32 { weight = 4i64 } else { weight = 3i64 }
                    }
                    let at = usize(i + dy + 1i32) * AB + usize(j + dx + 1i32)
                    a += weight * a_arr[at]
                    b += weight * b_arr[at]
                    dx += 1i32
                }
                dy += 1i32
            }
            let v = a * i64(win[usize(i + 3i32) * WIN + usize(j + 3i32)]) + b
            f[usize(i) * FL + usize(j)] = i32(round2(v, 8u32 + shift - 4u32))
            j += 1i32
        }
        i += 1i32
    }
}

fn self_guided(win: []const i32, u: *const LrUnit, w: usize, h: usize, bit_depth: u32, a_arr: []i64, b_arr: []i64, flt0: []i32, flt1: []i32, out: []u16, out_stride: usize, x: usize, y: usize) {
    let set = usize(u.sgr_set)
    box_filter(win, w, h, bit_depth, set, 0usize, a_arr, b_arr, flt0)
    box_filter(win, w, h, bit_depth, set, 1usize, a_arr, b_arr, flt1)
    let tab = sgr_params()
    let r0 = tab[set * 4usize]
    let r1 = tab[set * 4usize + 2usize]
    let w0 = i64(u.xqd0)
    let w1 = i64(u.xqd1)
    let w2 = 128i64 - w0 - w1
    var i = 0usize
    while i < h {
        var j = 0usize
        while j < w {
            let uu = i64(win[(i + 3usize) * WIN + j + 3usize]) << 4u32
            var v = w1 * uu
            if r0 != 0u8 { v += w0 * i64(flt0[i * FL + j]) } else { v += w0 * uu }
            if r1 != 0u8 { v += w2 * i64(flt1[i * FL + j]) } else { v += w2 * uu }
            out[(y + i) * out_stride + x + j] = clip1(round2(v, 11u32), bit_depth)
            j += 1usize
        }
        i += 1usize
    }
}

fn wiener_taps(c: []const i32, at: usize, f: []i32) {
    f[3usize] = 128i32
    var i = 0usize
    while i < 3usize {
        f[i] = c[at + i]
        f[6usize - i] = c[at + i]
        f[3usize] = f[3usize] - 2i32 * c[at + i]
        i += 1usize
    }
}

fn wiener(win: []const i32, u: *const LrUnit, w: usize, h: usize, bit_depth: u32, inter: []i32, out: []u16, out_stride: usize, x: usize, y: usize) {
    var round0 = 3u32
    var round1 = 11u32
    if bit_depth == 12u32 {
        round0 = 5u32
        round1 = 9u32
    }
    var vf: [7]i32 = zero
    var hf: [7]i32 = zero
    wiener_taps(u.wiener[0..], 0usize, vf[0..])
    wiener_taps(u.wiener[0..], 3usize, hf[0..])
    let offset = 1i32 << (bit_depth + 7u32 - round0 - 1u32)
    let limit = (1i32 << (bit_depth + 1u32 + 7u32 - round0)) - 1i32
    var r = 0usize
    while r < h + 6usize {
        var c = 0usize
        while c < w {
            var s = 0i32
            var t = 0usize
            while t < 7usize {
                s += hf[t] * win[r * WIN + c + t]
                t += 1usize
            }
            let v = i32(round2(i64(s), round0))
            inter[r * FL + c] = imax(0i32 - offset, imin(limit - offset, v))
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < h {
        var c = 0usize
        while c < w {
            var s = 0i64
            var t = 0usize
            while t < 7usize {
                s += i64(vf[t]) * i64(inter[(r + t) * FL + c])
                t += 1usize
            }
            out[(y + r) * out_stride + x + c] = clip1(round2(s, round1), bit_depth)
            c += 1usize
        }
        r += 1usize
    }
}

fn restore_plane(a: *mem.Arena, bit_depth: u32, sub_x: u32, sub_y: u32, frame_w: u32, frame_h: u32, pre: []const u16, cdef: []const u16, out: []u16, stride: usize, unit_size: u32, units: []const LrUnit) -> err {
    let pw = i32((frame_w + sub_x) >> sub_x)
    let ph = i32((frame_h + sub_y) >> sub_y)
    if unit_size == 0u32 { ret Invalid }
    let unit_rows = i32(count_units(unit_size, u32(ph)))
    let unit_cols = i32(count_units(unit_size, u32(pw)))
    if units.len < usize(unit_rows) * usize(unit_cols) { ret Invalid }
    var yy = 0i32
    while yy < ph {
        var xx = 0i32
        while xx < pw {
            out[usize(yy) * stride + usize(xx)] = cdef[usize(yy) * stride + usize(xx)]
            xx += 1i32
        }
        yy += 1i32
    }
    let (win_buf, win_buf_err) = mem.alloc[i32](a, WIN * WIN)
    if win_buf_err != ok { ret win_buf_err }
    let (inter, inter_err) = mem.alloc[i32](a, WIN * FL)
    if inter_err != ok { ret inter_err }
    let (flt0, flt0_err) = mem.alloc[i32](a, FL * FL)
    if flt0_err != ok { ret flt0_err }
    let (flt1, flt1_err) = mem.alloc[i32](a, FL * FL)
    if flt1_err != ok { ret flt1_err }
    let (a_arr, a_arr_err) = mem.alloc[i64](a, AB * AB)
    if a_arr_err != ok { ret a_arr_err }
    let (b_arr, b_arr_err) = mem.alloc[i64](a, AB * AB)
    if b_arr_err != ok { ret b_arr_err }
    let usz = i32(unit_size)
    let row_off = i32(8u32 >> sub_y)
    var src = Src { pre: pre, cdef: cdef, stride: stride, end_x: pw - 1i32, end_y: ph - 1i32, stripe_start: 0i32, stripe_end: 0i32 }
    var n = 0i32
    while true {
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
                    var iy = 0i32
                    while iy < h + 6i32 {
                        var jx = 0i32
                        while jx < w + 6i32 {
                            win_buf[usize(iy) * WIN + usize(jx)] = source_sample(&src, x - 3i32 + jx, y - 3i32 + iy)
                            jx += 1i32
                        }
                        iy += 1i32
                    }
                    if u.rtype == RESTORE_WIENER {
                        wiener(win_buf, u, usize(w), usize(h), bit_depth, inter, out, stride, usize(x), usize(y))
                    } else {
                        self_guided(win_buf, u, usize(w), usize(h), bit_depth, a_arr, b_arr, flt0, flt1, out, stride, usize(x), usize(y))
                    }
                }
                x += w
            }
            y = y2 + 1i32
        }
        n += 1i32
    }
    ret ok
}
