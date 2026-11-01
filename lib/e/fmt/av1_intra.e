// AV1 intra prediction (spec 7.11.2), palette prediction (7.11.4) and chroma from luma (7.11.5).
// Every predictor writes its block straight into a plane (u16 samples, `stride` samples per row),
// like the spec's CurrFrame; the block must lie inside the plane buffer. All coordinates are in
// samples of the plane being predicted. Block sizes are log2 widths and heights (2..6).
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
//     bit_depth: 8, 10 or 12
// predict_palette(plane, stride, start_x, start_y, log2w, log2h, palette, map, map_stride, map_x, map_y)
//   Sets each sample to palette[map[(map_y * 4 + i) * map_stride + map_x * 4 + j]]; map_x, map_y are the
//   spec's x, y (4x4 units inside the colour map).
// predict_cfl(plane, stride, luma, luma_stride, start_x, start_y, log2w, log2h, sub_x, sub_y, alpha,
//             max_luma_w, max_luma_h, bit_depth)
//   Adds alpha-scaled subsampled luma AC to the chroma block already holding its DC prediction.
//   alpha is CflAlphaU or CflAlphaV; max_luma_w / max_luma_h the spec's MaxLumaW / MaxLumaH.

error BadMode

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

fn clip1(v: i32, bd: u32) -> i32 {
    let hi = (1i32 << bd) - 1i32
    if v < 0i32 { ret 0i32 }
    if v > hi { ret hi }
    ret v
}

fn round2(v: i32, n: u32) -> i32 {
    if n == 0u32 { ret v }
    ret (v + (1i32 << (n - 1u32))) >> n
}

fn round2_signed(v: i32, n: u32) -> i32 {
    if v >= 0i32 { ret round2(v, n) }
    ret 0i32 - round2(0i32 - v, n)
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

fn pix(plane: []u16, stride: usize, xx: i32, yy: i32) -> i32 {
    ret i32(plane[usize(yy) * stride + usize(xx)])
}

fn put(plane: []u16, stride: usize, xx: i32, yy: i32, v: i32) {
    plane[usize(yy) * stride + usize(xx)] = u16(v)
}

// AboveRow / LeftCol of the general intra process, indices -1..w+h-1
fn prepare(plane: []u16, stride: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams, above: []i32, left: []i32) {
    let n = w + h
    let mid = 1i32 << (p.bit_depth - 1u32)
    var i = 0i32
    if !p.have_above && p.have_left {
        let v = pix(plane, stride, xi - 1i32, yi)
        while i < n { above[ei(i)] = v
            i += 1i32 }
    } else if !p.have_above {
        while i < n { above[ei(i)] = mid - 1i32
            i += 1i32 }
    } else {
        var span = w
        if p.have_above_right { span = 2i32 * w }
        let limit = min_i(p.max_x, xi + span - 1i32)
        while i < n { above[ei(i)] = pix(plane, stride, min_i(limit, xi + i), yi - 1i32)
            i += 1i32 }
    }
    i = 0i32
    if !p.have_left && p.have_above {
        let v = pix(plane, stride, xi, yi - 1i32)
        while i < n { left[ei(i)] = v
            i += 1i32 }
    } else if !p.have_left {
        while i < n { left[ei(i)] = mid + 1i32
            i += 1i32 }
    } else {
        var span = h
        if p.have_below_left { span = 2i32 * h }
        let limit = min_i(p.max_y, yi + span - 1i32)
        while i < n { left[ei(i)] = pix(plane, stride, xi - 1i32, min_i(limit, yi + i))
            i += 1i32 }
    }
    var corner = mid
    if p.have_above && p.have_left {
        corner = pix(plane, stride, xi - 1i32, yi - 1i32)
    } else if p.have_above {
        corner = pix(plane, stride, xi, yi - 1i32)
    } else if p.have_left {
        corner = pix(plane, stride, xi - 1i32, yi)
    }
    above[ei(-1i32)] = corner
    left[ei(-1i32)] = corner
}

fn paeth(plane: []u16, stride: usize, xi: i32, yi: i32, w: i32, h: i32, above: []i32, left: []i32) {
    let tl = above[ei(-1i32)]
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            let a = above[ei(j)]
            let l = left[ei(i)]
            let base = a + l - tl
            let p_left = abs_i(base - l)
            let p_top = abs_i(base - a)
            let p_top_left = abs_i(base - tl)
            var v = tl
            if p_left <= p_top && p_left <= p_top_left { v = l } else if p_top <= p_top_left { v = a }
            put(plane, stride, xi + j, yi + i, v)
            j += 1i32
        }
        i += 1i32
    }
}

fn recursive(plane: []u16, stride: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams, above: []i32, left: []i32) {
    let taps = filter_taps()
    var pv: [7]i32 = zero
    let h2 = h >> 1u32
    let w4 = w >> 2u32
    var i2 = 0i32
    while i2 < h2 {
        var j4 = 0i32
        while j4 < w4 {
            var i = 0i32
            while i < 7i32 {
                var v = 0i32
                if i < 5i32 {
                    if i2 == 0i32 {
                        v = above[ei((j4 << 2u32) + i - 1i32)]
                    } else if j4 == 0i32 && i == 0i32 {
                        v = left[ei((i2 << 1u32) - 1i32)]
                    } else {
                        v = pix(plane, stride, xi + (j4 << 2u32) + i - 1i32, yi + (i2 << 1u32) - 1i32)
                    }
                } else if j4 == 0i32 {
                    v = left[ei((i2 << 1u32) + i - 5i32)]
                } else {
                    v = pix(plane, stride, xi + (j4 << 2u32) - 1i32, yi + (i2 << 1u32) + i - 5i32)
                }
                pv[usize(i)] = v
                i += 1i32
            }
            var i1 = 0i32
            while i1 < 2i32 {
                var j1 = 0i32
                while j1 < 4i32 {
                    var pr = 0i32
                    let row = (i32(p.filter_intra_mode) * 8i32 + (i1 << 2u32) + j1) * 7i32
                    var k = 0i32
                    while k < 7i32 {
                        pr = pr + (i32(taps[usize(row + k)]) - 128i32) * pv[usize(k)]
                        k += 1i32
                    }
                    put(plane, stride, xi + (j4 << 2u32) + j1, yi + (i2 << 1u32) + i1, clip1(round2_signed(pr, 4u32), p.bit_depth))
                    j1 += 1i32
                }
                i1 += 1i32
            }
            j4 += 1i32
        }
        i2 += 1i32
    }
}

fn dc(plane: []u16, stride: usize, xi: i32, yi: i32, log2w: u32, log2h: u32, p: IntraParams, above: []i32, left: []i32) {
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    var sum = 0i32
    var k = 0i32
    var v = 1i32 << (p.bit_depth - 1u32)
    if p.have_left && p.have_above {
        while k < h { sum = sum + left[ei(k)]
            k += 1i32 }
        k = 0i32
        while k < w { sum = sum + above[ei(k)]
            k += 1i32 }
        sum = sum + ((w + h) >> 1u32)
        v = sum / (w + h)
    } else if p.have_left {
        while k < h { sum = sum + left[ei(k)]
            k += 1i32 }
        v = clip1((sum + (h >> 1u32)) >> log2h, p.bit_depth)
    } else if p.have_above {
        while k < w { sum = sum + above[ei(k)]
            k += 1i32 }
        v = clip1((sum + (w >> 1u32)) >> log2w, p.bit_depth)
    }
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            put(plane, stride, xi + j, yi + i, v)
            j += 1i32
        }
        i += 1i32
    }
}

fn smooth(plane: []u16, stride: usize, xi: i32, yi: i32, log2w: u32, log2h: u32, mode: u32, above: []i32, left: []i32) {
    let wt = sm_weights()
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    let ox = usize(w - 4i32)
    let oy = usize(h - 4i32)
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            let wy = i32(wt[oy + usize(i)])
            let wx = i32(wt[ox + usize(j)])
            var v = 0i32
            if mode == 9u32 {
                v = round2(wy * above[ei(j)] + (256i32 - wy) * left[ei(h - 1i32)] + wx * left[ei(i)] + (256i32 - wx) * above[ei(w - 1i32)], 9u32)
            } else if mode == 10u32 {
                v = round2(wy * above[ei(j)] + (256i32 - wy) * left[ei(h - 1i32)], 8u32)
            } else {
                v = round2(wx * left[ei(i)] + (256i32 - wx) * above[ei(w - 1i32)], 8u32)
            }
            put(plane, stride, xi + j, yi + i, v)
            j += 1i32
        }
        i += 1i32
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

fn edge_filter(buf: []i32, sz: i32, strength: i32) {
    if strength == 0i32 { ret }
    let kern = edge_kernel()
    var edge: [136]i32 = zero
    var i = 0i32
    while i < sz {
        edge[usize(i)] = buf[ei(i - 1i32)]
        i += 1i32
    }
    i = 1i32
    while i < sz {
        var s = 0i32
        var j = 0i32
        while j < 5i32 {
            let k = min_i(max_i(i - 2i32 + j, 0i32), sz - 1i32)
            s = s + i32(kern[usize((strength - 1i32) * 5i32 + j)]) * edge[usize(k)]
            j += 1i32
        }
        buf[ei(i - 1i32)] = (s + 8i32) >> 4u32
        i += 1i32
    }
}

fn upsample(buf: []i32, num_px: i32, bd: u32) {
    var dup: [40]i32 = zero
    dup[0] = buf[ei(-1i32)]
    var i = -1i32
    while i < num_px {
        dup[usize(i + 2i32)] = buf[ei(i)]
        i += 1i32
    }
    dup[usize(num_px + 2i32)] = buf[ei(num_px - 1i32)]
    buf[ei(-2i32)] = dup[0]
    i = 0i32
    while i < num_px {
        let s = 0i32 - dup[usize(i)] + 9i32 * dup[usize(i + 1i32)] + 9i32 * dup[usize(i + 2i32)] - dup[usize(i + 3i32)]
        buf[ei(2i32 * i - 1i32)] = clip1(round2(s, 4u32), bd)
        buf[ei(2i32 * i)] = dup[usize(i + 2i32)]
        i += 1i32
    }
}

fn directional(plane: []u16, stride: usize, xi: i32, yi: i32, w: i32, h: i32, p: IntraParams, above: []i32, left: []i32) {
    let p_angle = mode_to_angle(p.mode) + p.angle_delta * 3i32
    var up_a = 0u32
    var up_l = 0u32
    if p.edge_filter {
        var filter_type = false
        if p.above_smooth || p.left_smooth { filter_type = true }
        if p_angle != 90i32 && p_angle != 180i32 {
            if p_angle > 90i32 && p_angle < 180i32 && w + h >= 24i32 {
                let corner = round2(left[ei(0i32)] * 5i32 + above[ei(-1i32)] * 6i32 + above[ei(0i32)] * 5i32, 4u32)
                left[ei(-1i32)] = corner
                above[ei(-1i32)] = corner
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
            upsample(above, w + extra, p.bit_depth)
        }
        if use_upsample(w, h, filter_type, p_angle - 180i32) {
            up_l = 1u32
            var extra = 0i32
            if p_angle > 180i32 { extra = w }
            upsample(left, h + extra, p.bit_depth)
        }
    }
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            var v = 0i32
            if p_angle < 90i32 {
                let dx = derivative(p_angle)
                let idx = (i + 1i32) * dx
                let base = (idx >> (6u32 - up_a)) + (j << up_a)
                let shift = ((idx << up_a) >> 1u32) & 31i32
                let max_base = (w + h - 1i32) << up_a
                if base < max_base {
                    v = round2(above[ei(base)] * (32i32 - shift) + above[ei(base + 1i32)] * shift, 5u32)
                } else {
                    v = above[ei(max_base)]
                }
            } else if p_angle > 90i32 && p_angle < 180i32 {
                let dx = derivative(180i32 - p_angle)
                let dy = derivative(p_angle - 90i32)
                let idx = (j << 6u32) - (i + 1i32) * dx
                let base = idx >> (6u32 - up_a)
                if base >= 0i32 - (1i32 << up_a) {
                    let shift = ((idx << up_a) >> 1u32) & 31i32
                    v = round2(above[ei(base)] * (32i32 - shift) + above[ei(base + 1i32)] * shift, 5u32)
                } else {
                    let idy = (i << 6u32) - (j + 1i32) * dy
                    let base_l = idy >> (6u32 - up_l)
                    let shift = ((idy << up_l) >> 1u32) & 31i32
                    v = round2(left[ei(base_l)] * (32i32 - shift) + left[ei(base_l + 1i32)] * shift, 5u32)
                }
            } else if p_angle > 180i32 {
                let dy = derivative(270i32 - p_angle)
                let idx = (j + 1i32) * dy
                let base = (idx >> (6u32 - up_l)) + (i << up_l)
                let shift = ((idx << up_l) >> 1u32) & 31i32
                v = round2(left[ei(base)] * (32i32 - shift) + left[ei(base + 1i32)] * shift, 5u32)
            } else if p_angle == 90i32 {
                v = above[ei(j)]
            } else {
                v = left[ei(i)]
            }
            put(plane, stride, xi + j, yi + i, v)
            j += 1i32
        }
        i += 1i32
    }
}

fn predict_intra(plane: []u16, stride: usize, x: usize, y: usize, log2w: u32, log2h: u32, p: IntraParams) -> err {
    if p.mode > 12u32 { ret BadMode }
    let xi = i32(x)
    let yi = i32(y)
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    var above: [192]i32 = zero
    var left: [192]i32 = zero
    prepare(plane, stride, xi, yi, w, h, p, above[..], left[..])
    if p.use_filter_intra {
        recursive(plane, stride, xi, yi, w, h, p, above[..], left[..])
    } else if p.mode >= 1u32 && p.mode <= 8u32 {
        directional(plane, stride, xi, yi, w, h, p, above[..], left[..])
    } else if p.mode >= 9u32 && p.mode <= 11u32 {
        smooth(plane, stride, xi, yi, log2w, log2h, p.mode, above[..], left[..])
    } else if p.mode == 0u32 {
        dc(plane, stride, xi, yi, log2w, log2h, p, above[..], left[..])
    } else {
        paeth(plane, stride, xi, yi, w, h, above[..], left[..])
    }
    ret ok
}

fn predict_palette(plane: []u16, stride: usize, start_x: usize, start_y: usize, log2w: u32, log2h: u32, palette: []const u16, map: []const u8, map_stride: usize, map_x: usize, map_y: usize) {
    let w = usize(1u32 << log2w)
    let h = usize(1u32 << log2h)
    var i = 0usize
    while i < h {
        var j = 0usize
        while j < w {
            plane[(start_y + i) * stride + start_x + j] = palette[usize(map[(map_y * 4usize + i) * map_stride + map_x * 4usize + j])]
            j += 1usize
        }
        i += 1usize
    }
}

// subsampled luma with 3 fractional bits for chroma sample (j, i) of the block at (start_x, start_y)
fn cfl_luma(luma: []u16, luma_stride: usize, xx: i32, yy: i32, sub_x: u32, sub_y: u32, max_w: i32, max_h: i32) -> i32 {
    let ly = min_i(yy << sub_y, max_h - (1i32 << sub_y))
    let lx = min_i(xx << sub_x, max_w - (1i32 << sub_x))
    var t = 0i32
    var ddy = 0i32
    while ddy <= i32(sub_y) {
        var ddx = 0i32
        while ddx <= i32(sub_x) {
            t = t + pix(luma, luma_stride, lx + ddx, ly + ddy)
            ddx += 1i32
        }
        ddy += 1i32
    }
    ret t << (3u32 - sub_x - sub_y)
}

fn predict_cfl(plane: []u16, stride: usize, luma: []u16, luma_stride: usize, start_x: usize, start_y: usize, log2w: u32, log2h: u32, sub_x: u32, sub_y: u32, alpha: i32, max_luma_w: i32, max_luma_h: i32, bit_depth: u32) {
    let sx = i32(start_x)
    let sy = i32(start_y)
    let w = 1i32 << log2w
    let h = 1i32 << log2h
    var avg = 0i32
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            avg = avg + cfl_luma(luma, luma_stride, sx + j, sy + i, sub_x, sub_y, max_luma_w, max_luma_h)
            j += 1i32
        }
        i += 1i32
    }
    avg = round2(avg, log2w + log2h)
    i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            let l = cfl_luma(luma, luma_stride, sx + j, sy + i, sub_x, sub_y, max_luma_w, max_luma_h)
            let dcv = pix(plane, stride, sx + j, sy + i)
            put(plane, stride, sx + j, sy + i, clip1(dcv + round2_signed(alpha * (l - avg), 6u32), bit_depth))
            j += 1i32
        }
        i += 1i32
    }
}
