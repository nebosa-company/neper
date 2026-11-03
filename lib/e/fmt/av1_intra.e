// AV1 intra prediction (spec 7.11.2), palette prediction (7.11.4) and chroma from luma (7.11.5), 8-bit.
// Every predictor writes its block straight into a plane (u8 samples, `stride` samples per row),
// like the spec's CurrFrame; the block must lie inside the plane buffer. All coordinates are in
// samples of the plane being predicted. Block sizes are log2 widths and heights (2..6).
// Only 8-bit video is handled: bit_depth must be 8, any other value returns Invalid. Rows of 16 or
// more samples use 16-byte vectors (e.simd), rows of 4 and 8 use 4 and 8 byte accesses (mem.cast) and 8-lane vector
// arithmetic; the result is the same as the scalar formulas of the spec.
//
// predict_intra(plane, stride, x, y, log2w, log2h, p) -> err
//   Predicts the w x h block at (x, y); p.mode is DC_PRED 0, V_PRED 1, H_PRED 2, D45 3, D135 4,
//   D113 5, D157 6, D203 7, D67 8, SMOOTH 9, SMOOTH_V 10, SMOOTH_H 11, PAETH 12 (BadMode otherwise;
//   a CFL block is first predicted with DC_PRED). IntraParams:
//     have_left, have_above, have_above_right, have_below_left: the spec's availability inputs
//     max_x, max_y: largest valid coordinate of the plane, ((MiCols * 4) >> subsampling_x) - 1 and
//                   likewise for rows (samples beyond are replaced by the last valid one)
//     angle_delta: AngleDeltaY (luma) or AngleDeltaUV (chroma), -3..3, used by directional modes
//     use_filter_intra, filter_intra_mode: the recursive predictor; the caller sets it for luma only
//     edge_filter: enable_intra_edge_filter
//     above_smooth, left_smooth: the above / left neighbour (when available) used a smooth mode
//                   (is_smooth of the intra filter type process), only read when edge_filter is set
//     bit_depth: must be 8
// predict_palette(plane, stride, start_x, start_y, log2w, log2h, palette, map, map_stride, map_x, map_y)
//   Sets each sample to palette[map[(map_y * 4 + i) * map_stride + map_x * 4 + j]]; map_x, map_y are the
//   spec's x, y (4x4 units inside the colour map). The palette holds at most 8 colours (map values 0..7).
// predict_cfl(plane, stride, luma, luma_stride, start_x, start_y, log2w, log2h, sub_x, sub_y, alpha,
//             max_luma_w, max_luma_h, bit_depth) -> err
//   Adds alpha-scaled subsampled luma AC to the chroma block already holding its DC prediction.
//   alpha is CflAlphaU or CflAlphaV (-16..16); max_luma_w / max_luma_h the spec's MaxLumaW / MaxLumaH.
//   Invalid for bit_depth != 8, w * h > 1024, |alpha| > 16 or a max_luma smaller than the subsampling.

use e.mem
use e.simd

error BadMode
error Invalid

type Vb = Vec[u8, 16]
type Vi = Vec[i16, 8]
type Vu = Vec[u16, 8]
type Vd = Vec[i32, 4]

type IntraParams = struct {
    mode: u32,
    angle_delta: i32,
    use_filter_intra: bool,
    filter_intra_mode: u32,
    have_left: bool,
    have_above: bool,
    have_above_right: bool,
    have_below_left: bool,
    max_x: i32,
    max_y: i32,
    bit_depth: u32,
    edge_filter: bool,
    above_smooth: bool,
    left_smooth: bool,
}

// the edge buffers hold index -16..175 of the spec's AboveRow / LeftCol
const EDGE_OFF: i32 = 16i32

// Sm_Weights_Tx_4x4 .. 64x64 end to end; the table for log2 n starts at (1 << n) - 4
fn sm_weights() -> str { ret "\xff\x95\x55\x40\xff\xc5\x92\x69\x49\x32\x25\x20\xff\xe1\xc4\xaa\x91\x7b\x66\x54\x44\x36\x2b\x21\x1a\x14\x11\x10\xff\xf0\xe1\xd2\xc4\xb6\xa9\x9d\x91\x85\x7a\x6f\x65\x5c\x53\x4a\x42\x3b\x34\x2d\x27\x22\x1d\x19\x15\x11\x0e\x0c\x0a\x09\x08\x08\xff\xf8\xf0\xe9\xe1\xda\xd2\xcb\xc4\xbd\xb6\xb0\xa9\xa3\x9c\x96\x90\x8a\x85\x7f\x79\x74\x6f\x6a\x65\x60\x5b\x56\x52\x4d\x49\x45\x41\x3d\x39\x36\x32\x2f\x2c\x29\x26\x23\x20\x1d\x1b\x19\x16\x14\x12\x10\x0f\x0d\x0c\x0a\x09\x08\x07\x06\x06\x05\x05\x04\x04\x04" }

// Dr_Intra_Derivative[a], two bytes (low, high) per angle a = 0..89
fn dr_derivative() -> str { ret "\x00\x00\x00\x00\x00\x00\xff\x03\x00\x00\x00\x00\x23\x02\x00\x00\x00\x00\x74\x01\x00\x00\x00\x00\x00\x00\x00\x00\x11\x01\x00\x00\x00\x00\xd7\x00\x00\x00\x00\x00\xb2\x00\x00\x00\x00\x00\x97\x00\x00\x00\x00\x00\x84\x00\x00\x00\x00\x00\x74\x00\x00\x00\x00\x00\x66\x00\x00\x00\x00\x00\x00\x00\x5a\x00\x00\x00\x00\x00\x50\x00\x00\x00\x00\x00\x47\x00\x00\x00\x00\x00\x40\x00\x00\x00\x00\x00\x39\x00\x00\x00\x00\x00\x33\x00\x00\x00\x00\x00\x2d\x00\x00\x00\x00\x00\x00\x00\x28\x00\x00\x00\x00\x00\x23\x00\x00\x00\x00\x00\x1f\x00\x00\x00\x00\x00\x1b\x00\x00\x00\x00\x00\x17\x00\x00\x00\x00\x00\x13\x00\x00\x00\x00\x00\x0f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0b\x00\x00\x00\x00\x00\x07\x00\x00\x00\x00\x00\x03\x00\x00\x00\x00\x00" }

// Intra_Filter_Taps[5][8][7], each value plus 128
fn filter_taps() -> str { ret "\x7a\x8a\x80\x80\x80\x8c\x80\x7b\x82\x8a\x80\x80\x89\x80\x7d\x81\x81\x8a\x80\x87\x80\x7d\x81\x81\x82\x8a\x85\x80\x7c\x86\x80\x80\x80\x82\x8c\x7d\x82\x86\x80\x80\x82\x89\x7d\x82\x82\x86\x80\x82\x87\x7d\x81\x82\x82\x86\x83\x85\x76\x90\x80\x80\x80\x8a\x80\x7a\x80\x90\x80\x80\x86\x80\x7c\x80\x80\x90\x80\x84\x80\x7e\x80\x80\x80\x90\x82\x80\x76\x90\x80\x80\x80\x80\x8a\x7a\x80\x90\x80\x80\x80\x86\x7c\x80\x80\x90\x80\x80\x84\x7e\x80\x80\x80\x90\x80\x82\x78\x88\x80\x80\x80\x90\x80\x78\x80\x88\x80\x80\x90\x80\x78\x80\x80\x88\x80\x90\x80\x78\x80\x80\x80\x88\x90\x80\x7c\x84\x80\x80\x80\x80\x90\x7c\x80\x84\x80\x80\x80\x90\x7c\x80\x80\x84\x80\x80\x90\x7c\x80\x80\x80\x84\x80\x90\x7e\x88\x80\x80\x80\x8a\x80\x7f\x83\x88\x80\x80\x86\x80\x7f\x82\x83\x88\x80\x84\x80\x80\x81\x82\x83\x88\x82\x80\x7f\x84\x80\x80\x80\x83\x8a\x7f\x83\x84\x80\x80\x84\x86\x7f\x82\x83\x84\x80\x84\x84\x7f\x82\x82\x83\x84\x83\x83\x74\x8e\x80\x80\x80\x8e\x80\x76\x80\x8e\x80\x80\x8c\x80\x77\x80\x80\x8e\x80\x8b\x80\x78\x80\x80\x80\x8e\x8a\x80\x76\x8c\x80\x80\x80\x80\x8e\x77\x81\x8c\x80\x80\x80\x8c\x78\x80\x80\x8c\x80\x81\x8b\x79\x80\x80\x81\x8c\x81\x89" }

fn edge_kernel() -> str { ret "\x00\x04\x08\x04\x00\x00\x05\x06\x05\x00\x02\x04\x04\x04\x02" }
// Intra_Filter_Taps by tap: 16 bytes per (mode, tap), the first 8 are the tap of the 8 outputs, each value plus 128
fn filter_cols() -> str { ret "\x7a\x7b\x7d\x7d\x7c\x7d\x7d\x7d\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x82\x81\x81\x86\x82\x82\x81\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x81\x81\x80\x86\x82\x82\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x82\x80\x80\x86\x82\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x80\x80\x80\x86\x80\x80\x80\x80\x80\x80\x80\x80\x8c\x89\x87\x85\x82\x82\x82\x83\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8c\x89\x87\x85\x80\x80\x80\x80\x80\x80\x80\x80\x76\x7a\x7c\x7e\x76\x7a\x7c\x7e\x80\x80\x80\x80\x80\x80\x80\x80\x90\x80\x80\x80\x90\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x90\x80\x80\x80\x90\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x90\x80\x80\x80\x90\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x90\x80\x80\x80\x90\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x86\x84\x82\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x86\x84\x82\x80\x80\x80\x80\x80\x80\x80\x80\x78\x78\x78\x78\x7c\x7c\x7c\x7c\x80\x80\x80\x80\x80\x80\x80\x80\x88\x80\x80\x80\x84\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x88\x80\x80\x80\x84\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x88\x80\x80\x80\x84\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x88\x80\x80\x80\x84\x80\x80\x80\x80\x80\x80\x80\x80\x90\x90\x90\x90\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x90\x90\x90\x90\x80\x80\x80\x80\x80\x80\x80\x80\x7e\x7f\x7f\x80\x7f\x7f\x7f\x7f\x80\x80\x80\x80\x80\x80\x80\x80\x88\x83\x82\x81\x84\x83\x82\x82\x80\x80\x80\x80\x80\x80\x80\x80\x80\x88\x83\x82\x80\x84\x83\x82\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x88\x83\x80\x80\x84\x83\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x88\x80\x80\x80\x84\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x86\x84\x82\x83\x84\x84\x83\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8a\x86\x84\x83\x80\x80\x80\x80\x80\x80\x80\x80\x74\x76\x77\x78\x76\x77\x78\x79\x80\x80\x80\x80\x80\x80\x80\x80\x8e\x80\x80\x80\x8c\x81\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8e\x80\x80\x80\x8c\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8e\x80\x80\x80\x8c\x81\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8e\x80\x80\x80\x8c\x80\x80\x80\x80\x80\x80\x80\x80\x8e\x8c\x8b\x8a\x80\x80\x81\x81\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x8e\x8c\x8b\x89\x80\x80\x80\x80\x80\x80\x80\x80" }

fn mode_to_angle(mode: u32) -> i32 {
    if mode == 1u32 { ret 90i32 }
    if mode == 2u32 { ret 180i32 }
    if mode == 3u32 { ret 45i32 }
    if mode == 4u32 { ret 135i32 }
    if mode == 5u32 { ret 113i32 }
    if mode == 6u32 { ret 157i32 }
    if mode == 7u32 { ret 203i32 }
    ret 67i32
}

fn derivative(angle: i32) -> i32 {
    let t = dr_derivative()
    ret i32(t[usize(angle) * 2usize]) + (i32(t[usize(angle) * 2usize + 1usize]) << 8u32)
}

fn clip8(v: i32) -> i32 {
    if v < 0i32 { ret 0i32 }
    if v > 255i32 { ret 255i32 }
    ret v
}

fn round2(v: i32, n: u32) -> i32 {
    if n == 0u32 { ret v }
    ret (v + (1i32 << (n - 1u32))) >> n
}

fn min_i(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn max_i(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn abs_i(a: i32) -> i32 {
    if a < 0i32 { ret 0i32 - a }
    ret a
}

fn ei(k: i32) -> usize { ret usize(k + EDGE_OFF) }

fn lo16(a: Vb) -> Vi { ret mem.bitcast[Vi](simd.unpack_lo[Vb](a, simd.splat[Vb](0u8))) }

fn hi16(a: Vb) -> Vi { ret mem.bitcast[Vi](simd.unpack_hi[Vb](a, simd.splat[Vb](0u8))) }

// Unaligned 4 and 8 byte accesses (x64 little endian). The byte access first checks the far end of the range.
fn put32(buf: []u8, at: usize, v: u32) {
    buf[at + 3usize] = u8(v >> 24u32)
    let q = mem.cast[*u32](&buf[at])
    *q = v
}

fn put64(buf: []u8, at: usize, v: u64) {
    buf[at + 7usize] = u8(v >> 56u32)
    let q = mem.cast[*u64](&buf[at])
    *q = v
}

fn get64(buf: []u8, at: usize) -> u64 {
    let last = buf[at + 7usize]
    let q = mem.cast[*u64](&buf[at])
    ret *q
}

// The low 8 (store8) or 4 (store4) bytes of v.
fn store8(buf: []u8, at: usize, v: Vb) {
    let q = mem.bitcast[Vec[u64, 2]](v)
    buf[at + 7usize] = u8(q[0usize] >> 56u32)
    let a = mem.cast[*u64](&buf[at])
    *a = q[0usize]
}

fn store4(buf: []u8, at: usize, v: Vb) {
    let q = mem.bitcast[Vec[u32, 4]](v)
    buf[at + 3usize] = u8(q[0usize] >> 24u32)
    let a = mem.cast[*u32](&buf[at])
    *a = q[0usize]
}

// n bytes in 16-byte steps; a tail of fewer than 16 repeats the last 16 (8 or 4 bytes below 16; the regions do not overlap each other).
fn copy_bytes(dst: []u8, d: usize, src: []u8, s: usize, n: usize) {
    if n >= 16usize {
        var k = 0usize
        while k + 16usize <= n {
            simd.store[Vb](dst, d + k, simd.load[Vb](src, s + k))
            k += 16usize
        }
        if k < n { simd.store[Vb](dst, d + n - 16usize, simd.load[Vb](src, s + n - 16usize)) }
    } else if n >= 8usize {
        let last = src[s + n - 1usize]
        dst[d + n - 1usize] = last
        let sa = mem.cast[*u64](&src[s])
        let da = mem.cast[*u64](&dst[d])
        *da = *sa
        if n > 8usize {
            let sb = mem.cast[*u64](&src[s + n - 8usize])
            let db = mem.cast[*u64](&dst[d + n - 8usize])
            *db = *sb
        }
    } else if n >= 4usize {
        let last = src[s + n - 1usize]
        dst[d + n - 1usize] = last
        let sa = mem.cast[*u32](&src[s])
        let da = mem.cast[*u32](&dst[d])
        *da = *sa
        if n > 4usize {
            let sb = mem.cast[*u32](&src[s + n - 4usize])
            let db = mem.cast[*u32](&dst[d + n - 4usize])
            *db = *sb
        }
    } else {
        var k = 0usize
        while k < n {
            dst[d + k] = src[s + k]
            k += 1usize
        }
    }
}

fn fill_bytes(dst: []u8, d: usize, n: usize, v: u8) {
    if n >= 16usize {
        let sv = simd.splat[Vb](v)
        var k = 0usize
        while k + 16usize <= n {
            simd.store[Vb](dst, d + k, sv)
            k += 16usize
        }
        if k < n { simd.store[Vb](dst, d + n - 16usize, sv) }
    } else if n >= 8usize {
        let q = u64(v) * 72340172838076673u64
        dst[d + n - 1usize] = v
        let da = mem.cast[*u64](&dst[d])
        *da = q
        if n > 8usize {
            let db = mem.cast[*u64](&dst[d + n - 8usize])
            *db = q
        }
    } else if n >= 4usize {
        let q = u32(v) * 16843009u32
        dst[d + n - 1usize] = v
        let da = mem.cast[*u32](&dst[d])
        *da = q
        if n > 4usize {
            let db = mem.cast[*u32](&dst[d + n - 4usize])
            *db = q
        }
    } else {
        var k = 0usize
        while k < n {
            dst[d + k] = v
            k += 1usize
        }
    }
}

fn sum_bytes(a: []const u8, off: usize, n: usize) -> i32 {
    var total = 0i32
    var k = 0usize
    if n >= 16usize {
        let z = simd.splat[Vb](0u8)
        var acc = simd.splat[Vec[u64, 2]](0u64)
        while k + 16usize <= n {
            acc = acc +% simd.sad_u8[Vb](simd.load[Vb](a, off + k), z)
            k += 16usize
        }
        total = i32(acc[0usize] + acc[1usize])
    }
    while k < n {
        total += i32(a[off + k])
        k += 1usize
    }
    ret total
}

// AboveRow[0..cnt) of the general intra process for a block of width w
fn edge_above(plane: []u8, stride: usize, xi: i32, yi: i32, w: i32, cnt: i32, p: IntraParams, above: []u8) {
    if !p.have_above && p.have_left {
        fill_bytes(above, ei(0i32), usize(cnt), plane[usize(yi) * stride + usize(xi - 1i32)])
    } else if !p.have_above {
        fill_bytes(above, ei(0i32), usize(cnt), 127u8)
    } else {
        var span = w
        if p.have_above_right { span = 2i32 * w }
        let limit = min_i(p.max_x, xi + span - 1i32)
        let row0 = usize(yi - 1i32) * stride
        var m = limit - xi + 1i32
        if m > cnt { m = cnt }
        if m < 0i32 { m = 0i32 }
        copy_bytes(above, ei(0i32), plane, row0 + usize(xi), usize(m))
        if m < cnt { fill_bytes(above, ei(m), usize(cnt - m), plane[row0 + usize(limit)]) }
    }
}

// LeftCol[0..cnt) for a block of height h
fn edge_left(plane: []u8, stride: usize, xi: i32, yi: i32, h: i32, cnt: i32, p: IntraParams, left: []u8) {
    if !p.have_left && p.have_above {
        fill_bytes(left, ei(0i32), usize(cnt), plane[usize(yi - 1i32) * stride + usize(xi)])
    } else if !p.have_left {
        fill_bytes(left, ei(0i32), usize(cnt), 129u8)
    } else {
        var span = h
        if p.have_below_left { span = 2i32 * h }
        let limit = min_i(p.max_y, yi + span - 1i32)
        var m = limit - yi + 1i32
        if m > cnt { m = cnt }
        if m < 0i32 { m = 0i32 }
        var at = usize(yi) * stride + usize(xi - 1i32)
        var i = 0i32
        while i < m {
            left[ei(i)] = plane[at]
            at += stride
            i += 1i32
        }
        if m < cnt { fill_bytes(left, ei(m), usize(cnt - m), plane[usize(limit) * stride + usize(xi - 1i32)]) }
    }
}

fn corner_of(plane: []u8, stride: usize, xi: i32, yi: i32, p: IntraParams) -> u8 {
    if p.have_above && p.have_left { ret plane[usize(yi - 1i32) * stride + usize(xi - 1i32)] }
    if p.have_above { ret plane[usize(yi - 1i32) * stride + usize(xi)] }
    if p.have_left { ret plane[usize(yi) * stride + usize(xi - 1i32)] }
    ret 128u8
}

// AboveRow / LeftCol of the general intra process, indices -1..w+h-1
fn prepare(plane: []u8, stride: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams, above: []u8, left: []u8) {
    edge_above(plane, stride, xi, yi, w, w + h, p, above)
    edge_left(plane, stride, xi, yi, h, w + h, p, left)
    let corner = corner_of(plane, stride, xi, yi, p)
    above[ei(-1i32)] = corner
    left[ei(-1i32)] = corner
}

// 16 bytes when wide, else the low 8
fn st(plane: []u8, at: usize, v: Vb, wide: bool) {
    if wide {
        simd.store[Vb](plane, at, v)
    } else {
        let q = mem.bitcast[Vec[u64, 2]](v)
        plane[at + 7usize] = u8(q[0usize] >> 56u32)
        let a = mem.cast[*u64](&plane[at])
        *a = q[0usize]
    }
}

fn fill_rows(plane: []u8, stride: usize, pos: usize, w: usize, h: usize, v: u8) {
    var i = 0usize
    while i < h {
        fill_bytes(plane, pos + i * stride, w, v)
        i += 1usize
    }
}

fn paeth_narrow(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, above: []u8, left: []u8) {
    let tl = i32(above[ei(-1i32)])
    var i = 0i32
    @nocheck {
    while i < h {
        let l = i32(left[ei(i)])
        let row0 = pos + usize(i) * stride
        var j = 0i32
        while j < w {
            let a = i32(above[ei(j)])
            let base = a + l - tl
            let p_left = abs_i(base - l)
            let p_top = abs_i(base - a)
            let p_top_left = abs_i(base - tl)
            var v = tl
            if p_left <= p_top && p_left <= p_top_left { v = l } else if p_top <= p_top_left { v = a }
            plane[row0 + usize(j)] = u8(v)
            j += 1i32
        }
        i += 1i32
    }
    }
}

// p_left = |a - tl|, p_top = |l - tl|, p_top_left = |a + l - 2 tl|; 16 samples at a time
fn paeth_wide(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, above: []u8, left: []u8) {
    let tl = i32(above[ei(-1i32)])
    let tlv = simd.splat[Vu](u16(tl))
    let tl2v = simd.splat[Vu](u16(2i32 * tl))
    var i = 0i32
    while i < h {
        let l = i32(left[ei(i)])
        let lv = simd.splat[Vu](u16(l))
        let ptv = simd.splat[Vu](u16(abs_i(l - tl)))
        let row0 = pos + usize(i) * stride
        var j = 0i32
        while j < w {
            let a = simd.load[Vb](above, ei(j))
            let alo = mem.bitcast[Vu](lo16(a))
            let ahi = mem.bitcast[Vu](hi16(a))
            let pl0 = simd.abs_diff[Vu](alo, tlv)
            let ptl0 = simd.abs_diff[Vu](alo +% lv, tl2v)
            let r0 = simd.select[Vu](simd.cmp_le[Vu](pl0, ptv) & simd.cmp_le[Vu](pl0, ptl0), lv, simd.select[Vu](simd.cmp_le[Vu](ptv, ptl0), alo, tlv))
            let pl1 = simd.abs_diff[Vu](ahi, tlv)
            let ptl1 = simd.abs_diff[Vu](ahi +% lv, tl2v)
            let r1 = simd.select[Vu](simd.cmp_le[Vu](pl1, ptv) & simd.cmp_le[Vu](pl1, ptl1), lv, simd.select[Vu](simd.cmp_le[Vu](ptv, ptl1), ahi, tlv))
            st(plane, row0 + usize(j), simd.pack_sat[Vb, Vi](mem.bitcast[Vi](r0), mem.bitcast[Vi](r1)), w >= 16i32)
            j += 16i32
        }
        i += 1i32
    }
}

// The 8 outputs of a 4 x 2 block are the 7 inputs times the 7 tap columns (filter_cols), summed in 16 bits (|sum| <= 40 * 255).
fn recursive(plane: []u8, stride: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams, above: []u8, left: []u8) {
    let cols = filter_cols()
    let mb = usize(p.filter_intra_mode) * 112usize
    let c128 = simd.splat[Vi](128i16)
    let t0 = lo16(simd.load[Vb](cols, mb)) -% c128
    let t1 = lo16(simd.load[Vb](cols, mb + 16usize)) -% c128
    let t2 = lo16(simd.load[Vb](cols, mb + 32usize)) -% c128
    let t3 = lo16(simd.load[Vb](cols, mb + 48usize)) -% c128
    let t4 = lo16(simd.load[Vb](cols, mb + 64usize)) -% c128
    let t5 = lo16(simd.load[Vb](cols, mb + 80usize)) -% c128
    let t6 = lo16(simd.load[Vb](cols, mb + 96usize)) -% c128
    let c8 = simd.splat[Vi](8i16)
    let h2 = h >> 1u32
    let w4 = w >> 2u32
    var i2 = 0i32
    while i2 < h2 {
        var j4 = 0i32
        while j4 < w4 {
            let x0 = xi + (j4 << 2u32)
            let y0 = yi + (i2 << 1u32)
            var v0 = 0i32
            var v1 = 0i32
            var v2 = 0i32
            var v3 = 0i32
            var v4 = 0i32
            var v5 = 0i32
            var v6 = 0i32
            if i2 == 0i32 {
                let a0 = ei((j4 << 2u32) - 1i32)
                v0 = i32(above[a0])
                v1 = i32(above[a0 + 1usize])
                v2 = i32(above[a0 + 2usize])
                v3 = i32(above[a0 + 3usize])
                v4 = i32(above[a0 + 4usize])
            } else {
                let ro = usize(y0 - 1i32) * stride + usize(x0)
                if j4 == 0i32 { v0 = i32(left[ei((i2 << 1u32) - 1i32)]) } else { v0 = i32(plane[ro - 1usize]) }
                v1 = i32(plane[ro])
                v2 = i32(plane[ro + 1usize])
                v3 = i32(plane[ro + 2usize])
                v4 = i32(plane[ro + 3usize])
            }
            if j4 == 0i32 {
                v5 = i32(left[ei(i2 << 1u32)])
                v6 = i32(left[ei((i2 << 1u32) + 1i32)])
            } else {
                v5 = i32(plane[usize(y0) * stride + usize(x0 - 1i32)])
                v6 = i32(plane[usize(y0 + 1i32) * stride + usize(x0 - 1i32)])
            }
            let pr = (simd.splat[Vi](i16(v0)) *% t0) +% (simd.splat[Vi](i16(v1)) *% t1) +% (simd.splat[Vi](i16(v2)) *% t2) +% (simd.splat[Vi](i16(v3)) *% t3) +% (simd.splat[Vi](i16(v4)) *% t4) +% (simd.splat[Vi](i16(v5)) *% t5) +% (simd.splat[Vi](i16(v6)) *% t6)
            let sg = pr >> 15u32
            let rs = (((((pr ^ sg) -% sg) +% c8) >> 4u32) ^ sg) -% sg
            let words = mem.bitcast[Vec[u32, 4]](simd.pack_sat[Vb, Vi](rs, rs))
            put32(plane, usize(y0) * stride + usize(x0), words[0usize])
            put32(plane, usize(y0 + 1i32) * stride + usize(x0), words[1usize])
            j4 += 1i32
        }
        i2 += 1i32
    }
}

fn dc_pred(plane: []u8, stride: usize, pos: usize, log2w: u32, log2h: u32, p: IntraParams, above: []u8, left: []u8) {
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    var v = 128i32
    if p.have_left && p.have_above {
        let total = sum_bytes(left, ei(0i32), usize(h)) + sum_bytes(above, ei(0i32), usize(w)) + ((w + h) >> 1u32)
        v = total / (w + h)
    } else if p.have_left {
        v = (sum_bytes(left, ei(0i32), usize(h)) + (h >> 1u32)) >> log2h
    } else if p.have_above {
        v = (sum_bytes(above, ei(0i32), usize(w)) + (w >> 1u32)) >> log2w
    }
    fill_rows(plane, stride, pos, usize(w), usize(h), u8(v))
}

fn vert(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, above: []u8) {
    var i = 0usize
    while i < usize(h) {
        copy_bytes(plane, pos + i * stride, above, ei(0i32), usize(w))
        i += 1usize
    }
}

fn horz(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, left: []u8) {
    var i = 0i32
    while i < h {
        fill_bytes(plane, pos + usize(i) * stride, usize(w), left[ei(i)])
        i += 1i32
    }
}

fn smooth_narrow(plane: []u8, stride: usize, pos: usize, log2w: u32, log2h: u32, mode: u32, above: []u8, left: []u8) {
    let wt = sm_weights()
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    let ox = usize(w - 4i32)
    let oy = usize(h - 4i32)
    let bl = i32(left[ei(h - 1i32)])
    let tr = i32(above[ei(w - 1i32)])
    var i = 0i32
    @nocheck {
    while i < h {
        let wy = i32(wt[oy + usize(i)])
        let l = i32(left[ei(i)])
        let row0 = pos + usize(i) * stride
        var j = 0i32
        while j < w {
            let wx = i32(wt[ox + usize(j)])
            var v = 0i32
            if mode == 9u32 {
                v = (wy * i32(above[ei(j)]) + (256i32 - wy) * bl + wx * l + (256i32 - wx) * tr + 256i32) >> 9u32
            } else if mode == 10u32 {
                v = (wy * i32(above[ei(j)]) + (256i32 - wy) * bl + 128i32) >> 8u32
            } else {
                v = (wx * l + (256i32 - wx) * tr + 128i32) >> 8u32
            }
            plane[row0 + usize(j)] = u8(v)
            j += 1i32
        }
        i += 1i32
    }
    }
}

// SMOOTH needs wy * above + wx * l + ... in 32 bits: pairs (above, wx) are multiplied by (wy, l - tr) with madd,
// since wx * l + (256 - wx) * tr = 256 * tr + wx * (l - tr). SMOOTH_V and SMOOTH_H fit 16 unsigned bits.
fn smooth_wide(plane: []u8, stride: usize, pos: usize, log2w: u32, log2h: u32, mode: u32, above: []u8, left: []u8) {
    let wt = sm_weights()
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    let ox = usize(w - 4i32)
    let oy = usize(h - 4i32)
    let bl = i32(left[ei(h - 1i32)])
    let tr = i32(above[ei(w - 1i32)])
    var i = 0i32
    if mode == 9u32 {
        var ia: [128]i16 = undef
        var j = 0i32
        while j < w {
            let a = simd.load[Vb](above, ei(j))
            let wb = simd.load[Vb](wt, ox + usize(j))
            let alo = lo16(a)
            let ahi = hi16(a)
            let wlo = lo16(wb)
            let whi = hi16(wb)
            simd.store[Vi](ia[..], usize(j) * 2usize, simd.unpack_lo[Vi](alo, wlo))
            simd.store[Vi](ia[..], usize(j) * 2usize + 8usize, simd.unpack_hi[Vi](alo, wlo))
            simd.store[Vi](ia[..], usize(j) * 2usize + 16usize, simd.unpack_lo[Vi](ahi, whi))
            simd.store[Vi](ia[..], usize(j) * 2usize + 24usize, simd.unpack_hi[Vi](ahi, whi))
            j += 16i32
        }
        while i < h {
            let wy = i32(wt[oy + usize(i)])
            let l = i32(left[ei(i)])
            let pairv = mem.bitcast[Vi](simd.splat[Vd](wy + (l - tr) *% 65536i32))
            let cv = simd.splat[Vd]((256i32 - wy) * bl + 256i32 * tr + 256i32)
            let row0 = pos + usize(i) * stride
            j = 0i32
            while j < w {
                let b = usize(j) * 2usize
                let m0 = (simd.madd_i16[Vi](simd.load[Vi](ia[..], b), pairv) +% cv) >> 9u32
                let m1 = (simd.madd_i16[Vi](simd.load[Vi](ia[..], b + 8usize), pairv) +% cv) >> 9u32
                let m2 = (simd.madd_i16[Vi](simd.load[Vi](ia[..], b + 16usize), pairv) +% cv) >> 9u32
                let m3 = (simd.madd_i16[Vi](simd.load[Vi](ia[..], b + 24usize), pairv) +% cv) >> 9u32
                st(plane, row0 + usize(j), simd.pack_sat[Vb, Vi](simd.pack_sat[Vi, Vd](m0, m1), simd.pack_sat[Vi, Vd](m2, m3)), w >= 16i32)
                j += 16i32
            }
            i += 1i32
        }
    } else if mode == 10u32 {
        while i < h {
            let wy = i32(wt[oy + usize(i)])
            let wyv = simd.splat[Vu](u16(wy))
            let nbl = simd.splat[Vu](u16((256i32 - wy) * bl + 128i32))
            let row0 = pos + usize(i) * stride
            var j = 0i32
            while j < w {
                let a = simd.load[Vb](above, ei(j))
                let r0 = ((wyv *% mem.bitcast[Vu](lo16(a))) +% nbl) >> 8u32
                let r1 = ((wyv *% mem.bitcast[Vu](hi16(a))) +% nbl) >> 8u32
                st(plane, row0 + usize(j), simd.pack_sat[Vb, Vi](mem.bitcast[Vi](r0), mem.bitcast[Vi](r1)), w >= 16i32)
                j += 16i32
            }
            i += 1i32
        }
    } else {
        var wxa: [64]u16 = undef
        var ta: [64]u16 = undef
        let trv = simd.splat[Vu](u16(tr))
        let c256 = simd.splat[Vu](256u16)
        let c128 = simd.splat[Vu](128u16)
        var j = 0i32
        while j < w {
            let wb = simd.load[Vb](wt, ox + usize(j))
            let wlo = mem.bitcast[Vu](lo16(wb))
            let whi = mem.bitcast[Vu](hi16(wb))
            simd.store[Vu](wxa[..], usize(j), wlo)
            simd.store[Vu](wxa[..], usize(j) + 8usize, whi)
            simd.store[Vu](ta[..], usize(j), ((c256 -% wlo) *% trv) +% c128)
            simd.store[Vu](ta[..], usize(j) + 8usize, ((c256 -% whi) *% trv) +% c128)
            j += 16i32
        }
        while i < h {
            let lv = simd.splat[Vu](u16(left[ei(i)]))
            let row0 = pos + usize(i) * stride
            j = 0i32
            while j < w {
                let r0 = ((simd.load[Vu](wxa[..], usize(j)) *% lv) +% simd.load[Vu](ta[..], usize(j))) >> 8u32
                let r1 = ((simd.load[Vu](wxa[..], usize(j) + 8usize) *% lv) +% simd.load[Vu](ta[..], usize(j) + 8usize)) >> 8u32
                st(plane, row0 + usize(j), simd.pack_sat[Vb, Vi](mem.bitcast[Vi](r0), mem.bitcast[Vi](r1)), w >= 16i32)
                j += 16i32
            }
            i += 1i32
        }
    }
}

fn edge_strength(w: i32, h: i32, filter_type: bool, delta: i32) -> i32 {
    let d = abs_i(delta)
    let blk = w + h
    var strength = 0i32
    if !filter_type {
        if blk <= 8i32 {
            if d >= 56i32 { strength = 1i32 }
        } else if blk <= 16i32 {
            if d >= 40i32 { strength = 1i32 }
        } else if blk <= 24i32 {
            if d >= 8i32 { strength = 1i32 }
            if d >= 16i32 { strength = 2i32 }
            if d >= 32i32 { strength = 3i32 }
        } else if blk <= 32i32 {
            strength = 1i32
            if d >= 4i32 { strength = 2i32 }
            if d >= 32i32 { strength = 3i32 }
        } else {
            strength = 3i32
        }
    } else {
        if blk <= 8i32 {
            if d >= 40i32 { strength = 1i32 }
            if d >= 64i32 { strength = 2i32 }
        } else if blk <= 16i32 {
            if d >= 20i32 { strength = 1i32 }
            if d >= 48i32 { strength = 2i32 }
        } else if blk <= 24i32 {
            if d >= 4i32 { strength = 3i32 }
        } else {
            strength = 3i32
        }
    }
    ret strength
}

fn use_upsample(w: i32, h: i32, filter_type: bool, delta: i32) -> bool {
    let d = abs_i(delta)
    if d <= 0i32 || d >= 40i32 { ret false }
    if !filter_type { ret w + h <= 16i32 }
    ret w + h <= 8i32
}

// The 5-tap edge filter over sz samples (index -1 .. sz - 2) in place: output i reads the buffer at i - 3 .. i + 1, so 16
// outputs come from five unaligned loads; the first output and the last two clamp their taps and are recomputed.
fn edge_filter(buf: []u8, sz: i32, strength: i32) {
    if strength == 0i32 || sz < 2i32 { ret }
    let kern = edge_kernel()
    var out: [144]u8 = undef
    let n = usize(sz - 1i32)
    let kb = usize((strength - 1i32) * 5i32)
    let k0 = simd.splat[Vu](u16(kern[kb]))
    let k1 = simd.splat[Vu](u16(kern[kb + 1usize]))
    let k2 = simd.splat[Vu](u16(kern[kb + 2usize]))
    let k3 = simd.splat[Vu](u16(kern[kb + 3usize]))
    let k4 = simd.splat[Vu](u16(kern[kb + 4usize]))
    let c8 = simd.splat[Vu](8u16)
    var t = 0usize
    while t < n {
        let base = usize(EDGE_OFF - 2i32) + t
        let s1 = simd.load[Vb](buf, base + 1usize)
        let s2 = simd.load[Vb](buf, base + 2usize)
        let s3 = simd.load[Vb](buf, base + 3usize)
        var lo = (mem.bitcast[Vu](lo16(s1)) *% k1) +% (mem.bitcast[Vu](lo16(s2)) *% k2) +% (mem.bitcast[Vu](lo16(s3)) *% k3) +% c8
        var hi = (mem.bitcast[Vu](hi16(s1)) *% k1) +% (mem.bitcast[Vu](hi16(s2)) *% k2) +% (mem.bitcast[Vu](hi16(s3)) *% k3) +% c8
        if strength == 3i32 {
            let s0 = simd.load[Vb](buf, base)
            let s4 = simd.load[Vb](buf, base + 4usize)
            lo = lo +% (mem.bitcast[Vu](lo16(s0)) *% k0) +% (mem.bitcast[Vu](lo16(s4)) *% k4)
            hi = hi +% (mem.bitcast[Vu](hi16(s0)) *% k0) +% (mem.bitcast[Vu](hi16(s4)) *% k4)
        }
        simd.store[Vb](out[..], t, simd.pack_sat[Vb, Vi](mem.bitcast[Vi](lo >> 4u32), mem.bitcast[Vi](hi >> 4u32)))
        t += 16usize
    }
    var f = 0i32
    while f < 3i32 {
        var i = 1i32
        if f == 1i32 { i = sz - 2i32 }
        if f == 2i32 { i = sz - 1i32 }
        if i >= 1i32 {
            var acc = 8i32
            var jj = 0i32
            while jj < 5i32 {
                let k = min_i(max_i(i - 2i32 + jj, 0i32), sz - 1i32)
                acc = acc + i32(kern[kb + usize(jj)]) * i32(buf[ei(k - 1i32)])
                jj += 1i32
            }
            out[usize(i - 1i32)] = u8(acc >> 4u32)
        }
        f += 1i32
    }
    copy_bytes(buf, ei(0i32), out[..], 0usize, n)
}

// d = the edge shifted by two with its first and last sample repeated: output i reads d[i .. i + 3]
fn upsample(buf: []u8, num_px: i32) {
    var d: [48]u8 = zero
    var o: [32]u8 = undef
    copy_bytes(d[..], 1usize, buf, ei(-1i32), usize(num_px + 1i32))
    d[0usize] = d[1usize]
    d[usize(num_px) + 2usize] = d[usize(num_px) + 1usize]
    buf[ei(-2i32)] = d[0usize]
    let x0 = simd.load[Vb](d[..], 0usize)
    let x1 = simd.load[Vb](d[..], 1usize)
    let x2 = simd.load[Vb](d[..], 2usize)
    let x3 = simd.load[Vb](d[..], 3usize)
    let nine = simd.splat[Vi](9i16)
    let c8 = simd.splat[Vi](8i16)
    let slo = (((nine *% (lo16(x1) +% lo16(x2))) -% (lo16(x0) +% lo16(x3))) +% c8) >> 4u32
    let shi = (((nine *% (hi16(x1) +% hi16(x2))) -% (hi16(x0) +% hi16(x3))) +% c8) >> 4u32
    let res = simd.pack_sat[Vb, Vi](slo, shi)
    simd.store[Vb](o[..], 0usize, simd.unpack_lo[Vb](res, x2))
    simd.store[Vb](o[..], 16usize, simd.unpack_hi[Vb](res, x2))
    copy_bytes(buf, ei(-1i32), o[..], 0usize, usize(2i32 * num_px))
}

// 16 samples round2(src[s + k] * (32 - shift) + src[s + k + 1] * shift, 5)
fn interp16(src: []u8, s: usize, shift: i32) -> Vb {
    let a0 = simd.load[Vb](src, s)
    let a1 = simd.load[Vb](src, s + 1usize)
    let wa = simd.splat[Vi](i16(32i32 - shift))
    let wb = simd.splat[Vi](i16(shift))
    let r16 = simd.splat[Vi](16i16)
    let lo = ((lo16(a0) *% wa) +% (lo16(a1) *% wb) +% r16) >> 5u32
    let hi = ((hi16(a0) *% wa) +% (hi16(a1) *% wb) +% r16) >> 5u32
    ret simd.pack_sat[Vb, Vi](lo, hi)
}

// pshufb indices for the even bytes, the odd bytes, and the lane numbers 0..7 as i16
fn shuf_tab() -> str { ret "\x00\x02\x04\x06\x08\x0a\x0c\x0e\x80\x80\x80\x80\x80\x80\x80\x80\x01\x03\x05\x07\x09\x0b\x0d\x0f\x80\x80\x80\x80\x80\x80\x80\x80\x00\x00\x01\x00\x02\x00\x03\x00\x04\x00\x05\x00\x06\x00\x07\x00" }

// Lanes 0..7 of round2(e[b0 + (k << up)] * (32 - shift) + e[b0 + (k << up) + 1] * shift, 5) as i16
fn interp8(e: []u8, b0: i32, up: u32, shift: i32) -> Vi {
    let x0 = simd.load[Vb](e, ei(b0))
    var a0 = lo16(x0)
    var a1 = lo16(simd.load[Vb](e, ei(b0 + 1i32)))
    if up == 1u32 {
        let tb = shuf_tab()
        a0 = lo16(simd.shuffle_bytes[Vb](x0, simd.load[Vb](tb, 0usize)))
        a1 = lo16(simd.shuffle_bytes[Vb](x0, simd.load[Vb](tb, 16usize)))
    }
    let wa = simd.splat[Vi](i16(32i32 - shift))
    let wb = simd.splat[Vi](i16(shift))
    ret ((a0 *% wa) +% (a1 *% wb) +% simd.splat[Vi](16i16)) >> 5u32
}

fn zone1(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, dx: i32, up_a: u32, above: []u8) {
    let max_base = (w + h - 1i32) << up_a
    let edge_v = above[ei(max_base)]
    var i = 0i32
    while i < h {
        let row0 = pos + usize(i) * stride
        let idx = (i + 1i32) * dx
        let shift = ((idx << up_a) >> 1u32) & 31i32
        if w >= 16i32 && up_a == 0u32 {
            let b0 = idx >> 6u32
            var jc = max_base - b0
            if jc > w { jc = w }
            if jc <= 0i32 {
                fill_bytes(plane, row0, usize(w), edge_v)
            } else {
                var j = 0i32
                while j < jc {
                    simd.store[Vb](plane, row0 + usize(j), interp16(above, ei(b0 + j), shift))
                    j += 16i32
                }
                if jc < w { fill_bytes(plane, row0 + usize(jc), usize(w - jc), edge_v) }
            }
        } else {
            let b0 = idx >> (6u32 - up_a)
            if b0 >= max_base {
                fill_bytes(plane, row0, usize(w), edge_v)
            } else {
                let r = interp8(above, b0, up_a, shift)
                let ids = mem.bitcast[Vi](simd.load[Vb](shuf_tab(), 32usize))
                let live = simd.cmp_lt[Vi](simd.splat[Vi](i16(b0)) +% (ids << up_a), simd.splat[Vi](i16(max_base)))
                let pk = simd.pack_sat[Vb, Vi](simd.select[Vi](live, r, simd.splat[Vi](i16(edge_v))), r)
                if w == 8i32 { store8(plane, row0, pk) } else { store4(plane, row0, pk) }
            }
        }
        i += 1i32
    }
}

// Transposes the 16 x 16 bytes whose column c (consecutive rows) is t[src0 + c * h ..] into 16 plane rows.
fn transpose_tile(plane: []u8, dst0: usize, stride: usize, t: []u8, src0: usize, h: usize) {
    var m: [16]Vb = undef
    var n: [16]Vb = undef
    var c = 0usize
    while c < 16usize {
        m[c] = simd.load[Vb](t, src0 + c * h)
        c += 1usize
    }
    var k = 0usize
    while k < 8usize {
        n[2usize * k] = simd.unpack_lo[Vb](m[2usize * k], m[2usize * k + 1usize])
        n[2usize * k + 1usize] = simd.unpack_hi[Vb](m[2usize * k], m[2usize * k + 1usize])
        k += 1usize
    }
    k = 0usize
    while k < 4usize {
        let a0 = mem.bitcast[Vu](n[4usize * k])
        let a1 = mem.bitcast[Vu](n[4usize * k + 1usize])
        let a2 = mem.bitcast[Vu](n[4usize * k + 2usize])
        let a3 = mem.bitcast[Vu](n[4usize * k + 3usize])
        m[4usize * k] = mem.bitcast[Vb](simd.unpack_lo[Vu](a0, a2))
        m[4usize * k + 1usize] = mem.bitcast[Vb](simd.unpack_hi[Vu](a0, a2))
        m[4usize * k + 2usize] = mem.bitcast[Vb](simd.unpack_lo[Vu](a1, a3))
        m[4usize * k + 3usize] = mem.bitcast[Vb](simd.unpack_hi[Vu](a1, a3))
        k += 1usize
    }
    k = 0usize
    while k < 8usize {
        let g = (k >> 2u32) * 8usize
        let q = k & 3usize
        let b0 = mem.bitcast[Vec[u32, 4]](m[g + q])
        let b1 = mem.bitcast[Vec[u32, 4]](m[g + q + 4usize])
        n[g + 2usize * q] = mem.bitcast[Vb](simd.unpack_lo[Vec[u32, 4]](b0, b1))
        n[g + 2usize * q + 1usize] = mem.bitcast[Vb](simd.unpack_hi[Vec[u32, 4]](b0, b1))
        k += 1usize
    }
    k = 0usize
    while k < 8usize {
        let d0 = mem.bitcast[Vec[u64, 2]](n[k])
        let d1 = mem.bitcast[Vec[u64, 2]](n[k + 8usize])
        m[2usize * k] = mem.bitcast[Vb](simd.unpack_lo[Vec[u64, 2]](d0, d1))
        m[2usize * k + 1usize] = mem.bitcast[Vb](simd.unpack_hi[Vec[u64, 2]](d0, d1))
        k += 1usize
    }
    k = 0usize
    while k < 16usize {
        simd.store[Vb](plane, dst0 + k * stride, m[k])
        k += 1usize
    }
}

fn zone2_scalar(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, dx: i32, dy: i32, up_a: u32, up_l: u32, above: []u8, left: []u8) {
    var i = 0i32
    while i < h {
        let row0 = pos + usize(i) * stride
        var j = 0i32
        while j < w {
            let idx = (j << 6u32) - (i + 1i32) * dx
            let base = idx >> (6u32 - up_a)
            var v = 0i32
            if base >= 0i32 - (1i32 << up_a) {
                let shift = ((idx << up_a) >> 1u32) & 31i32
                v = round2(i32(above[ei(base)]) * (32i32 - shift) + i32(above[ei(base + 1i32)]) * shift, 5u32)
            } else {
                let idy = (i << 6u32) - (j + 1i32) * dy
                let base_l = idy >> (6u32 - up_l)
                let shift = ((idy << up_l) >> 1u32) & 31i32
                v = round2(i32(left[ei(base_l)]) * (32i32 - shift) + i32(left[ei(base_l + 1i32)]) * shift, 5u32)
            }
            @nocheck { plane[row0 + usize(j)] = u8(v) }
            j += 1i32
        }
        i += 1i32
    }
}

// A pixel (i, j) comes from the left column when 64 * (j + 1) < (i + 1) * dx: the first jc columns of a row, the rows
// from ic(j) = 64 * (j + 1) / dx of a column. Those samples are built column by column in the transposed block t (one
// vector of consecutive rows each); the rest of a row is the above-row interpolation, whose shift is the same along the row.
fn zone2(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, dx: i32, dy: i32, up_a: u32, up_l: u32, above: []u8, left: []u8) {
    var t: [4112]u8 = undef
    var tmp: [16]u8 = undef
    let tiles = w >= 16i32 && h >= 16i32
    var j = 0i32
    while j < w {
        let ic = (64i32 * (j + 1i32)) / dx
        if ic >= h {
            j = w
        } else {
            let k = 0i32 - (j + 1i32) * dy
            let b0 = k >> (6u32 - up_l)
            let shift = ((k << up_l) >> 1u32) & 31i32
            if up_l == 0u32 {
                var i = ic
                if tiles { i = (ic >> 4u32) << 4u32 }
                while i < h {
                    simd.store[Vb](t[..], usize(j * h + i), interp16(left, ei(b0 + i), shift))
                    i += 16i32
                }
            } else {
                let r = interp8(left, b0 + (ic << 1u32), 1u32, shift)
                simd.store[Vb](t[..], usize(j * h + ic), simd.pack_sat[Vb, Vi](r, r))
            }
            j += 1i32
        }
    }
    if tiles {
        var i0 = 0i32
        while i0 < h {
            var j0 = 0i32
            while j0 < w {
                if i0 + 15i32 >= (64i32 * (j0 + 1i32)) / dx {
                    transpose_tile(plane, pos + usize(i0) * stride + usize(j0), stride, t[..], usize(j0 * h + i0), usize(h))
                }
                j0 += 16i32
            }
            i0 += 16i32
        }
    }
    var i = 0i32
    while i < h {
        let row0 = pos + usize(i) * stride
        let kk = 0i32 - (i + 1i32) * dx
        let b0 = kk >> (6u32 - up_a)
        let shift = ((kk << up_a) >> 1u32) & 31i32
        var jc = ((i + 1i32) * dx - 1i32) >> 6u32
        if jc > w { jc = w }
        let n = w - jc
        if n > 0i32 {
            if n >= 16i32 {
                var j2 = jc
                while j2 + 16i32 <= w {
                    simd.store[Vb](plane, row0 + usize(j2), interp16(above, ei(b0 + j2), shift))
                    j2 += 16i32
                }
                if j2 < w { simd.store[Vb](plane, row0 + usize(w - 16i32), interp16(above, ei(b0 + w - 16i32), shift)) }
            } else {
                if up_a == 0u32 {
                    simd.store[Vb](tmp[..], 0usize, interp16(above, ei(b0 + jc), shift))
                } else {
                    let r = interp8(above, b0 + (jc << 1u32), 1u32, shift)
                    simd.store[Vb](tmp[..], 0usize, simd.pack_sat[Vb, Vi](r, r))
                }
                copy_bytes(plane, row0 + usize(jc), tmp[..], 0usize, usize(n))
            }
        }
        if !tiles {
            var jj = 0i32
            @nocheck {
            while jj < jc {
                plane[row0 + usize(jj)] = t[usize(jj * h + i)]
                jj += 1i32
            }
            }
        }
        i += 1i32
    }
}

// Column j holds interpolations of consecutive left samples, so 16 rows of it are one vector; the block is built
// transposed in `t` and then copied out row by row.
fn zone3_scalar(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, dy: i32, up_l: u32, left: []u8) {
    var i = 0i32
    while i < h {
        let row0 = pos + usize(i) * stride
        var j = 0i32
        while j < w {
            let idx = (j + 1i32) * dy
            let base = (idx >> (6u32 - up_l)) + (i << up_l)
            let shift = ((idx << up_l) >> 1u32) & 31i32
            let v = round2(i32(left[ei(base)]) * (32i32 - shift) + i32(left[ei(base + 1i32)]) * shift, 5u32)
            @nocheck { plane[row0 + usize(j)] = u8(v) }
            j += 1i32
        }
        i += 1i32
    }
}

fn zone3(plane: []u8, stride: usize, pos: usize, w: i32, h: i32, dy: i32, up_l: u32, left: []u8) {
    if w * h <= 16i32 {
        zone3_scalar(plane, stride, pos, w, h, dy, up_l, left)
    } else {
        var t: [4112]u8 = undef
        var j = 0i32
        while j < w {
            let idx = (j + 1i32) * dy
            let b0 = idx >> (6u32 - up_l)
            let shift = ((idx << up_l) >> 1u32) & 31i32
            if h >= 16i32 {
                var i = 0i32
                while i < h {
                    simd.store[Vb](t[..], usize(j) * usize(h) + usize(i), interp16(left, ei(b0 + i), shift))
                    i += 16i32
                }
            } else {
                let r = interp8(left, b0, up_l, shift)
                simd.store[Vb](t[..], usize(j) * usize(h), simd.pack_sat[Vb, Vi](r, r))
            }
            j += 1i32
        }
        if w >= 16i32 && h >= 16i32 {
            var i0 = 0i32
            while i0 < h {
                var j0 = 0i32
                while j0 < w {
                    transpose_tile(plane, pos + usize(i0) * stride + usize(j0), stride, t[..], usize(j0 * h + i0), usize(h))
                    j0 += 16i32
                }
                i0 += 16i32
            }
        } else {
            var i = 0i32
            while i < h {
                let row0 = pos + usize(i) * stride
                var k = 0usize
                var tp = usize(i)
                @nocheck {
                while k < usize(w) {
                    plane[row0 + k] = t[tp]
                    tp += usize(h)
                    k += 1usize
                }
                }
                i += 1i32
            }
        }
    }
}

fn directional(plane: []u8, stride: usize, pos: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams, above: []u8, left: []u8) {
    let p_angle = mode_to_angle(p.mode) + p.angle_delta * 3i32
    var up_a = 0u32
    var up_l = 0u32
    if p.edge_filter {
        var filter_type = false
        if p.above_smooth || p.left_smooth { filter_type = true }
        if p_angle != 90i32 && p_angle != 180i32 {
            if p_angle > 90i32 && p_angle < 180i32 && w + h >= 24i32 {
                let corner = round2(i32(left[ei(0i32)]) * 5i32 + i32(above[ei(-1i32)]) * 6i32 + i32(above[ei(0i32)]) * 5i32, 4u32)
                left[ei(-1i32)] = u8(corner)
                above[ei(-1i32)] = u8(corner)
            }
            if p.have_above {
                let strength = edge_strength(w, h, filter_type, p_angle - 90i32)
                var extra = 0i32
                if p_angle < 90i32 { extra = h }
                edge_filter(above, min_i(w, p.max_x - xi + 1i32) + extra + 1i32, strength)
            }
            if p.have_left {
                let strength = edge_strength(w, h, filter_type, p_angle - 180i32)
                var extra = 0i32
                if p_angle > 180i32 { extra = w }
                edge_filter(left, min_i(h, p.max_y - yi + 1i32) + extra + 1i32, strength)
            }
        }
        if use_upsample(w, h, filter_type, p_angle - 90i32) {
            up_a = 1u32
            var extra = 0i32
            if p_angle < 90i32 { extra = h }
            upsample(above, w + extra)
        }
        if use_upsample(w, h, filter_type, p_angle - 180i32) {
            up_l = 1u32
            var extra = 0i32
            if p_angle > 180i32 { extra = w }
            upsample(left, h + extra)
        }
    }
    if p_angle < 90i32 {
        zone1(plane, stride, pos, w, h, derivative(p_angle), up_a, above)
    } else if p_angle > 90i32 && p_angle < 180i32 {
        if w * h <= 32i32 {
            zone2_scalar(plane, stride, pos, w, h, derivative(180i32 - p_angle), derivative(p_angle - 90i32), up_a, up_l, above, left)
        } else {
            zone2(plane, stride, pos, w, h, derivative(180i32 - p_angle), derivative(p_angle - 90i32), up_a, up_l, above, left)
        }
    } else if p_angle > 180i32 {
        zone3(plane, stride, pos, w, h, derivative(270i32 - p_angle), up_l, left)
    } else if p_angle == 90i32 {
        vert(plane, stride, pos, w, h, above)
    } else {
        horz(plane, stride, pos, w, h, left)
    }
}

// Whether the w x h block at (xi, yi) and the edge samples the availability flags promise lie inside the plane.
fn extents_ok(plane: []u8, stride: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams) -> bool {
    if xi < 0i32 || yi < 0i32 || usize(xi + w) > stride { ret false }
    if plane.len < usize(yi + h - 1i32) * stride + usize(xi + w) { ret false }
    if p.have_above && yi < 1i32 { ret false }
    if p.have_left && xi < 1i32 { ret false }
    if p.max_x < 0i32 || p.max_y < 0i32 || usize(p.max_x) >= stride { ret false }
    if (p.have_above || p.have_left) && plane.len < (usize(p.max_y) + 1usize) * stride { ret false }
    ret true
}

fn predict_intra(plane: []u8, stride: usize, x: usize, y: usize, log2w: u32, log2h: u32, p: IntraParams) -> err {
    if p.mode > 12u32 { ret BadMode }
    if p.bit_depth != 8u32 { ret Invalid }
    let xi = i32(x)
    let yi = i32(y)
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    if !extents_ok(plane, stride, xi, yi, w, h, p) { ret Invalid }
    let pos = y * stride + x
    if p.use_filter_intra || (p.mode >= 3u32 && p.mode <= 8u32) || ((p.mode == 1u32 || p.mode == 2u32) && p.angle_delta != 0i32) {
        var above: [192]u8 = undef
        var left: [192]u8 = undef
        prepare(plane, stride, xi, yi, w, h, p, above[..], left[..])
        if p.use_filter_intra {
            recursive(plane, stride, xi, yi, w, h, p, above[..], left[..])
        } else {
            directional(plane, stride, pos, xi, yi, w, h, p, above[..], left[..])
        }
        ret ok
    }
    var above: [96]u8 = undef
    var left: [96]u8 = undef
    if p.mode == 0u32 {
        if p.have_above { edge_above(plane, stride, xi, yi, w, w, p, above[..]) }
        if p.have_left { edge_left(plane, stride, xi, yi, h, h, p, left[..]) }
        dc_pred(plane, stride, pos, log2w, log2h, p, above[..], left[..])
    } else if p.mode == 1u32 {
        edge_above(plane, stride, xi, yi, w, w, p, above[..])
        vert(plane, stride, pos, w, h, above[..])
    } else if p.mode == 2u32 {
        edge_left(plane, stride, xi, yi, h, h, p, left[..])
        horz(plane, stride, pos, w, h, left[..])
    } else {
        edge_above(plane, stride, xi, yi, w, w, p, above[..])
        edge_left(plane, stride, xi, yi, h, h, p, left[..])
        if p.mode == 12u32 {
            above[ei(-1i32)] = corner_of(plane, stride, xi, yi, p)
            if w >= 8i32 {
                paeth_wide(plane, stride, pos, w, h, above[..], left[..])
            } else {
                paeth_narrow(plane, stride, pos, w, h, above[..], left[..])
            }
        } else if w >= 8i32 {
            smooth_wide(plane, stride, pos, log2w, log2h, p.mode, above[..], left[..])
        } else {
            smooth_narrow(plane, stride, pos, log2w, log2h, p.mode, above[..], left[..])
        }
    }
    ret ok
}

fn predict_palette(plane: []u8, stride: usize, start_x: usize, start_y: usize, log2w: u32, log2h: u32, palette: []const u16, map: []const u8, map_stride: usize, map_x: usize, map_y: usize) {
    let w = usize(1u32 << log2w)
    let h = usize(1u32 << log2h)
    var i = 0usize
    if w >= 16usize {
        var pal: [16]u8 = zero
        var c = 0usize
        while c < palette.len && c < 8usize {
            pal[c] = u8(palette[c])
            c += 1usize
        }
        let pv = simd.load[Vb](pal[..], 0usize)
        while i < h {
            let dst = (start_y + i) * stride + start_x
            let src = (map_y * 4usize + i) * map_stride + map_x * 4usize
            var j = 0usize
            while j < w {
                simd.store[Vb](plane, dst + j, simd.shuffle_bytes[Vb](pv, simd.load[Vb](map, src + j)))
                j += 16usize
            }
            i += 1usize
        }
    } else if w == 8usize {
        while i < h {
            let dst = (start_y + i) * stride + start_x
            let src = (map_y * 4usize + i) * map_stride + map_x * 4usize
            let q = u64(palette[usize(map[src])]) | (u64(palette[usize(map[src + 1usize])]) << 8u32) | (u64(palette[usize(map[src + 2usize])]) << 16u32) | (u64(palette[usize(map[src + 3usize])]) << 24u32) | (u64(palette[usize(map[src + 4usize])]) << 32u32) | (u64(palette[usize(map[src + 5usize])]) << 40u32) | (u64(palette[usize(map[src + 6usize])]) << 48u32) | (u64(palette[usize(map[src + 7usize])]) << 56u32)
            plane[dst + 7usize] = u8(q >> 56u32)
            let qa = mem.cast[*u64](&plane[dst])
            *qa = q
            i += 1usize
        }
    } else {
        while i < h {
            let dst = (start_y + i) * stride + start_x
            let src = (map_y * 4usize + i) * map_stride + map_x * 4usize
            let q = u32(palette[usize(map[src])]) | (u32(palette[usize(map[src + 1usize])]) << 8u32) | (u32(palette[usize(map[src + 2usize])]) << 16u32) | (u32(palette[usize(map[src + 3usize])]) << 24u32)
            plane[dst + 3usize] = u8(q >> 24u32)
            let qa = mem.cast[*u32](&plane[dst])
            *qa = q
            i += 1usize
        }
    }
}

// subsampled luma with 3 fractional bits for chroma sample (xx, yy)
fn cfl_luma(luma: []const u8, luma_stride: usize, xx: i32, yy: i32, sub_x: u32, sub_y: u32, max_w: i32, max_h: i32) -> i32 {
    let ly = min_i(yy << sub_y, max_h - (1i32 << sub_y))
    let lx = min_i(xx << sub_x, max_w - (1i32 << sub_x))
    let at = usize(ly) * luma_stride + usize(lx)
    var t = i32(luma[at])
    if sub_x == 1u32 { t = t + i32(luma[at + 1usize]) }
    if sub_y == 1u32 {
        t = t + i32(luma[at + luma_stride])
        if sub_x == 1u32 { t = t + i32(luma[at + luma_stride + 1usize]) }
    }
    ret t << (3u32 - sub_x - sub_y)
}

fn predict_cfl(plane: []u8, stride: usize, luma: []const u8, luma_stride: usize, start_x: usize, start_y: usize, log2w: u32, log2h: u32, sub_x: u32, sub_y: u32, alpha: i32, max_luma_w: i32, max_luma_h: i32, bit_depth: u32) -> err {
    if bit_depth != 8u32 { ret Invalid }
    if sub_x > 1u32 || sub_y > 1u32 || alpha > 16i32 || alpha < 0i32 - 16i32 || log2w + log2h > 10u32 { ret Invalid }
    if max_luma_w < (1i32 << sub_x) || max_luma_h < (1i32 << sub_y) { ret Invalid }
    let sx = i32(start_x)
    let sy = i32(start_y)
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    var lum: [1024]i16 = undef
    // chroma columns whose luma samples need no clamping: 8 of them are one 16-byte luma load
    var nvc = 0i32
    if sub_x == 1u32 {
        nvc = ((max_luma_w - 2i32) >> 1u32) - sx + 1i32
        if nvc > w { nvc = w }
        if nvc < 0i32 { nvc = 0i32 }
    }
    let ones = simd.splat[Vi](1i16)
    var i = 0i32
    while i < h {
        let ly = min_i((sy + i) << sub_y, max_luma_h - (1i32 << sub_y))
        let at0 = usize(ly) * luma_stride
        var j = 0i32
        while j + 8i32 <= nvc {
            let lx = usize((sx + j) << 1u32)
            var r0 = lo16(simd.load[Vb](luma, at0 + lx))
            var r1 = hi16(simd.load[Vb](luma, at0 + lx))
            if sub_y == 1u32 {
                let b = simd.load[Vb](luma, at0 + luma_stride + lx)
                r0 = r0 +% lo16(b)
                r1 = r1 +% hi16(b)
            }
            let s = simd.pack_sat[Vi, Vd](simd.madd_i16[Vi](r0, ones), simd.madd_i16[Vi](r1, ones)) << (2u32 - sub_y)
            simd.store[Vi](lum[..], usize(i * w + j), s)
            j += 8i32
        }
        while j < w {
            lum[usize(i * w + j)] = i16(cfl_luma(luma, luma_stride, sx + j, sy + i, sub_x, sub_y, max_luma_w, max_luma_h))
            j += 1i32
        }
        i += 1i32
    }
    var acc = simd.splat[Vd](0i32)
    var k = 0usize
    while k < usize(w * h) {
        acc = acc +% simd.madd_i16[Vi](simd.load[Vi](lum[..], k), ones)
        k += 8usize
    }
    let avg = round2(acc[0usize] + acc[1usize] + acc[2usize] + acc[3usize], log2w + log2h)
    let avgv = simd.splat[Vi](i16(avg))
    let alv = simd.splat[Vi](i16(alpha))
    let c32 = simd.splat[Vi](32i16)
    var tmp: [16]u8 = zero
    i = 0i32
    while i < h {
        let row0 = usize(sy + i) * stride + usize(sx)
        var j = 0i32
        if w >= 16i32 {
            while j < w {
                let dcb = simd.load[Vb](plane, row0 + usize(j))
                let m0 = (simd.load[Vi](lum[..], usize(i * w + j)) -% avgv) *% alv
                let m1 = (simd.load[Vi](lum[..], usize(i * w + j + 8i32)) -% avgv) *% alv
                let s0 = m0 >> 15u32
                let s1 = m1 >> 15u32
                let r0 = (((((m0 ^ s0) -% s0) +% c32) >> 6u32) ^ s0) -% s0
                let r1 = (((((m1 ^ s1) -% s1) +% c32) >> 6u32) ^ s1) -% s1
                simd.store[Vb](plane, row0 + usize(j), simd.pack_sat[Vb, Vi](lo16(dcb) +% r0, hi16(dcb) +% r1))
                j += 16i32
            }
        } else if w == 8i32 {
            put64(tmp[..], 0usize, get64(plane, row0))
            let dcb = simd.load[Vb](tmp[..], 0usize)
            let m0 = (simd.load[Vi](lum[..], usize(i * w)) -% avgv) *% alv
            let s0 = m0 >> 15u32
            let r0 = lo16(dcb) +% (((((m0 ^ s0) -% s0) +% c32) >> 6u32) ^ s0) -% s0
            store8(plane, row0, simd.pack_sat[Vb, Vi](r0, r0))
        } else {
            while j < w {
                let m = alpha * (i32(lum[usize(i * w + j)]) - avg)
                var r = 0i32
                if m >= 0i32 { r = (m + 32i32) >> 6u32 } else { r = 0i32 - ((32i32 - m) >> 6u32) }
                plane[row0 + usize(j)] = u8(clip8(i32(plane[row0 + usize(j)]) + r))
                j += 1i32
            }
        }
        i += 1i32
    }
    ret ok
}
