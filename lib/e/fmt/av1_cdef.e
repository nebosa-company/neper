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

fn iabs(a: i32) -> i32 {
    if a < 0i32 { ret 0i32 - a }
    ret a
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

fn constrain(diff: i32, threshold: i32, damping: i32) -> i32 {
    if threshold == 0i32 { ret 0i32 }
    let adj = imax(0i32, damping - floor_log2(u32(threshold)))
    let mag = iabs(diff)
    let v = imax(0i32, imin(mag, threshold - (mag >> u32(adj))))
    if diff < 0i32 { ret 0i32 - v }
    ret v
}

fn direction(plane: []const u16, stride: usize, x0: usize, y0: usize, bit_depth: u32) -> (u32, u32) {
    var cost: [8]i32 = zero
    var partial: [8][15]i32 = zero
    let div_table: [9]i32 = [9]i32{ 0, 840, 420, 280, 210, 168, 140, 120, 105 }
    var i = 0usize
    while i < 8usize {
        var j = 0usize
        while j < 8usize {
            let x = i32(plane[(y0 + i) * stride + x0 + j] >> u16(bit_depth - 8u32)) - 128i32
            partial[0usize][i + j] += x
            partial[1usize][i + j / 2usize] += x
            partial[2usize][i] += x
            partial[3usize][3usize + i - j / 2usize] += x
            partial[4usize][7usize + i - j] += x
            partial[5usize][3usize - i / 2usize + j] += x
            partial[6usize][j] += x
            partial[7usize][i / 2usize + j] += x
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        cost[2usize] += partial[2usize][i] * partial[2usize][i]
        cost[6usize] += partial[6usize][i] * partial[6usize][i]
        i += 1usize
    }
    cost[2usize] = cost[2usize] * div_table[8usize]
    cost[6usize] = cost[6usize] * div_table[8usize]
    i = 0usize
    while i < 7usize {
        cost[0usize] += (partial[0usize][i] * partial[0usize][i] + partial[0usize][14usize - i] * partial[0usize][14usize - i]) * div_table[i + 1usize]
        cost[4usize] += (partial[4usize][i] * partial[4usize][i] + partial[4usize][14usize - i] * partial[4usize][14usize - i]) * div_table[i + 1usize]
        i += 1usize
    }
    cost[0usize] += partial[0usize][7usize] * partial[0usize][7usize] * div_table[8usize]
    cost[4usize] += partial[4usize][7usize] * partial[4usize][7usize] * div_table[8usize]
    i = 1usize
    while i < 8usize {
        var j = 0usize
        while j < 5usize {
            cost[i] += partial[i][3usize + j] * partial[i][3usize + j]
            j += 1usize
        }
        cost[i] = cost[i] * div_table[8usize]
        j = 0usize
        while j < 3usize {
            cost[i] += (partial[i][j] * partial[i][j] + partial[i][10usize - j] * partial[i][10usize - j]) * div_table[2usize * j + 2usize]
            j += 1usize
        }
        i += 2usize
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

fn filter_block(p: CdefParams, src: []const u16, dst: []u16, stride: usize, plane: u32, r: u32, c: u32, pri_str: i32, sec_str: i32, damping: i32, dir: u32) {
    var sub_x = 0u32
    var sub_y = 0u32
    if plane > 0u32 {
        sub_x = p.sub_x
        sub_y = p.sub_y
    }
    let coeff_shift = p.bit_depth - 8u32
    let x0 = i32((c * 4u32) >> sub_x)
    let y0 = i32((r * 4u32) >> sub_y)
    let w = i32(8u32 >> sub_x)
    let h = i32(8u32 >> sub_y)
    let rows = i32(p.mi_rows)
    let cols = i32(p.mi_cols)
    let tap_set = usize((u32(pri_str) >> coeff_shift) & 1u32)
    let pri_taps: [4]i32 = [4]i32{ 4, 2, 3, 3 }
    let sec_taps: [4]i32 = [4]i32{ 2, 1, 2, 1 }
    let table = directions()
    var i = 0i32
    while i < h {
        var j = 0i32
        while j < w {
            let x = i32(src[usize(y0 + i) * stride + usize(x0 + j)])
            var sum = 0i32
            var hi = x
            var lo = x
            var k = 0usize
            while k < 2usize {
                var sign = 0i32 - 1i32
                while sign <= 1i32 {
                    var t = 0usize
                    while t < 3usize {
                        // t 0 is the primary direction, 1 and 2 the secondary ones at dir - 2 and dir + 2
                        var d = dir
                        if t == 1usize { d = (dir + 6u32) & 7u32 }
                        if t == 2usize { d = (dir + 2u32) & 7u32 }
                        let at = usize(d) * 4usize + k * 2usize
                        let yy = y0 + i + sign * (i32(table[at]) - 2i32)
                        let xx = x0 + j + sign * (i32(table[at + 1usize]) - 2i32)
                        let cand_r = (yy << sub_y) >> 2u32
                        let cand_c = (xx << sub_x) >> 2u32
                        if cand_c >= 0i32 && cand_c < cols && cand_r >= 0i32 && cand_r < rows {
                            let s = i32(src[usize(yy) * stride + usize(xx)])
                            if t == 0usize {
                                sum += pri_taps[tap_set * 2usize + k] * constrain(s - x, pri_str, damping)
                            } else {
                                sum += sec_taps[tap_set * 2usize + k] * constrain(s - x, sec_str, damping)
                            }
                            hi = imax(s, hi)
                            lo = imin(s, lo)
                        }
                        t += 1usize
                    }
                    sign += 2i32
                }
                k += 1usize
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

fn copy_plane(src: []const u16, dst: []u16, stride: usize, w: usize, h: usize) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            dst[y * stride + x] = src[y * stride + x]
            x += 1usize
        }
        y += 1usize
    }
}

fn cdef_frame(p: CdefParams, cdef_idx: []const i8, skips: []const u8, src: Planes, dst: Planes) {
    let mi_rows = usize(p.mi_rows)
    let mi_cols = usize(p.mi_cols)
    let idx_stride = (mi_cols + 15usize) >> 4u32
    copy_plane(src.y, dst.y, src.stride_y, mi_cols * 4usize, mi_rows * 4usize)
    if p.num_planes > 1u32 {
        let cw = (mi_cols * 4usize) >> p.sub_x
        let ch = (mi_rows * 4usize) >> p.sub_y
        copy_plane(src.u, dst.u, src.stride_uv, cw, ch)
        copy_plane(src.v, dst.v, src.stride_uv, cw, ch)
    }
    let coeff_shift = p.bit_depth - 8u32
    let uv = uv_dir()
    var r = 0usize
    while r < mi_rows {
        var c = 0usize
        while c < mi_cols {
            let idx = i32(cdef_idx[(r >> 4u32) * idx_stride + (c >> 4u32)])
            let sk = skips[r * mi_cols + c] != 0u8 && skips[(r + 1usize) * mi_cols + c] != 0u8 && skips[r * mi_cols + c + 1usize] != 0u8 && skips[(r + 1usize) * mi_cols + c + 1usize] != 0u8
            if idx >= 0i32 && !sk {
                let (y_dir, variance) = direction(src.y, src.stride_y, c * 4usize, r * 4usize, p.bit_depth)
                let i = usize(idx)
                var pri = i32(p.y_pri[i] << coeff_shift)
                let sec = i32(p.y_sec[i] << coeff_shift)
                var dir = y_dir
                if pri == 0i32 { dir = 0u32 }
                var var_str = 0i32
                if (variance >> 6u32) != 0u32 { var_str = imin(floor_log2(variance >> 6u32), 12i32) }
                if variance != 0u32 { pri = (pri * (4i32 + var_str) + 8i32) >> 4u32 } else { pri = 0i32 }
                filter_block(p, src.y, dst.y, src.stride_y, 0u32, u32(r), u32(c), pri, sec, i32(p.damping + coeff_shift), dir)
                if p.num_planes > 1u32 {
                    let upri = i32(p.uv_pri[i] << coeff_shift)
                    let usec = i32(p.uv_sec[i] << coeff_shift)
                    var udir = 0u32
                    if upri != 0i32 { udir = u32(uv[usize((p.sub_x * 2u32 + p.sub_y) * 8u32 + y_dir)]) }
                    let udamp = i32(p.damping + coeff_shift) - 1i32
                    filter_block(p, src.u, dst.u, src.stride_uv, 1u32, u32(r), u32(c), upri, usec, udamp, udir)
                    filter_block(p, src.v, dst.v, src.stride_uv, 2u32, u32(r), u32(c), upri, usec, udamp, udir)
                }
            }
            c += 2usize
        }
        r += 2usize
    }
}

