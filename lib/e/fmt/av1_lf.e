// AV1 loop filter (deblocking), section 7.14 of the specification: the edge loop filter, filter size,
// adaptive strength and the narrow / 6, 8 and 14-tap wide sample filters.
//
// Interface. `loop_filter(p, f)` filters every plane of one frame in place: planes in order, and for
// each plane all vertical edges (pass 0) over the whole frame, then all horizontal edges (pass 1).
// The caller applies the frame-level rule "run only when levels[0] or levels[1] is non-zero";
// `loop_filter` itself skips a chroma plane whose level is zero, as the process does.
//
// `LoopFilterParams` holds the frame header values: levels[0..3] = loop_filter_level, sharpness,
// delta_enabled, ref_deltas[INTRA_FRAME..ALTREF_FRAME], mode_deltas[0..1], delta_lf_multi, and the
// segmentation loop filter features at index segment * 4 + i for SEG_LVL_ALT_LF_Y_V + i:
// seg_active[] is `segmentation_enabled && FeatureEnabled`, seg_data[] is FeatureData.
//
// `LoopFilterFrame` holds the per-4x4 (MI) arrays, all row-major with stride mi_cols: mi_sizes
// (BLOCK_*), skips (0/1), ref_frames (RefFrames[][0]; INTRA_FRAME is 0, so <= 0 means intra),
// y_modes (YMode; >= 14 NEARESTMV and above), segment_ids, and delta_lfs with 4 values per MI
// (stride 4). tx_sizes0..2 are LoopfilterTxSizes of plane 0..2 (TX_* values), indexed
// [(row >> sub_y) * mi_cols + (col >> sub_x)] with sub_x/sub_y zero for plane 0. The sample planes
// p0..p2 (stride in samples) must hold at least (mi_rows * 4) >> sub_y rows of (mi_cols * 4) >> sub_x
// samples; frame_width / frame_height are the luma FrameWidth / FrameHeight.

type LoopFilterParams = struct {
    levels: [4]i32,
    sharpness: i32,
    delta_enabled: bool,
    ref_deltas: [8]i32,
    mode_deltas: [2]i32,
    delta_lf_multi: bool,
    seg_active: [32]bool,
    seg_data: [32]i32
}

type LoopFilterFrame = struct {
    mi_rows: usize,
    mi_cols: usize,
    frame_width: usize,
    frame_height: usize,
    sub_x: u32,
    sub_y: u32,
    num_planes: u32,
    bit_depth: u32,
    mi_sizes: []u8,
    skips: []u8,
    ref_frames: []i8,
    y_modes: []u8,
    segment_ids: []u8,
    delta_lfs: []i8,
    tx_sizes0: []u8,
    tx_sizes1: []u8,
    tx_sizes2: []u8,
    p0: []u16,
    p1: []u16,
    p2: []u16,
    stride0: usize,
    stride1: usize,
    stride2: usize
}

type Strength = struct { lvl: i32, limit: i32, blimit: i32, thresh: i32 }

error Invalid

fn iabs(x: i32) -> i32 {
    if x < 0i32 { ret 0i32 - x }
    ret x
}

fn imin(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn imax(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn clip3(lo: i32, hi: i32, x: i32) -> i32 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn blk_w4() -> str { ret "\x01\x01\x02\x02\x02\x04\x04\x04\x08\x08\x08\x10\x10\x10\x20\x20\x01\x04\x02\x08\x04\x10" }

fn blk_h4() -> str { ret "\x01\x02\x01\x02\x04\x02\x04\x08\x04\x08\x10\x08\x10\x20\x10\x20\x04\x01\x08\x02\x10\x04" }

fn tx_w() -> str { ret "\x04\x08\x10\x20\x40\x04\x08\x08\x10\x10\x20\x20\x40\x04\x10\x08\x20\x10\x40" }

fn tx_h() -> str { ret "\x04\x08\x10\x20\x40\x08\x04\x10\x08\x20\x10\x40\x20\x10\x04\x20\x08\x40\x10" }

// The adaptive filter strength selection process (7.14.5); ref_frame <= 0 is INTRA_FRAME.
fn filter_level(p: *const LoopFilterParams, segment: usize, ref_frame: i32, mode_type: usize, delta_lf: i32, plane: u32, pass: u32) -> i32 {
    var i = pass
    if plane > 0u32 { i = plane + 1u32 }
    let feature = segment * 4usize + usize(i)
    var lvl = clip3(0i32, 63i32, delta_lf + p.levels[usize(i)])
    if p.seg_active[feature] {
        lvl = clip3(0i32, 63i32, lvl + p.seg_data[feature])
    }
    if p.delta_enabled {
        let scale = 1i32 << u32(lvl >> 5u32)
        if ref_frame <= 0i32 {
            lvl = lvl + p.ref_deltas[0usize] * scale
        } else {
            lvl = lvl + p.ref_deltas[usize(ref_frame)] * scale + p.mode_deltas[mode_type] * scale
        }
        lvl = clip3(0i32, 63i32, lvl)
    }
    ret lvl
}

// limit, blimit and thresh from a level (the tail of 7.14.4).
fn strength(sharpness: i32, lvl: i32) -> Strength {
    var shift = 0u32
    if sharpness > 4i32 { shift = 2u32 } else if sharpness > 0i32 { shift = 1u32 }
    var limit = imax(1i32, lvl >> shift)
    if sharpness > 0i32 { limit = clip3(1i32, 9i32 - sharpness, lvl >> shift) }
    ret Strength { lvl: lvl, limit: limit, blimit: 2i32 * (lvl + 2i32) + limit, thresh: lvl >> 4u32 }
}

fn at(pos: usize, step: usize, k: i32) -> usize {
    if k < 0i32 { ret pos - usize(0i32 - k) * step }
    ret pos + usize(k) * step
}

fn narrow(buf: []u16, pos: usize, step: usize, hev: bool, bd: u32) {
    let off = 128i32 << (bd - 8u32)
    let lo = 0i32 - (1i32 << (bd - 1u32))
    let hi = (1i32 << (bd - 1u32)) - 1i32
    let ps1 = i32(buf[at(pos, step, -2i32)]) - off
    let ps0 = i32(buf[at(pos, step, -1i32)]) - off
    let qs0 = i32(buf[pos]) - off
    let qs1 = i32(buf[at(pos, step, 1i32)]) - off
    var filter = 0i32
    if hev { filter = clip3(lo, hi, ps1 - qs1) }
    filter = clip3(lo, hi, filter + 3i32 * (qs0 - ps0))
    let filter1 = clip3(lo, hi, filter + 4i32) >> 3u32
    let filter2 = clip3(lo, hi, filter + 3i32) >> 3u32
    buf[pos] = u16(clip3(lo, hi, qs0 - filter1) + off)
    buf[at(pos, step, -1i32)] = u16(clip3(lo, hi, ps0 + filter2) + off)
    if !hev {
        let f3 = (filter1 + 1i32) >> 1u32
        buf[at(pos, step, 1i32)] = u16(clip3(lo, hi, qs1 - f3) + off)
        buf[at(pos, step, -2i32)] = u16(clip3(lo, hi, ps1 + f3) + off)
    }
}

fn wide(buf: []u16, pos: usize, step: usize, chroma: bool, log2_size: u32) {
    var n = 3i32
    if log2_size == 4u32 { n = 6i32 } else if chroma { n = 2i32 }
    var n2 = 1i32
    if log2_size == 3u32 && !chroma { n2 = 0i32 }
    var s: [14]i32 = zero
    var k = 0i32 - (n + 1i32)
    while k <= n {
        s[usize(k + 7i32)] = i32(buf[at(pos, step, k)])
        k += 1i32
    }
    var out: [14]i32 = zero
    var i = 0i32 - n
    while i < n {
        var t = 0i32
        var j = 0i32 - n
        while j <= n {
            let q = clip3(0i32 - (n + 1i32), n, i + j)
            var tap = 1i32
            if iabs(j) <= n2 { tap = 2i32 }
            t = t + s[usize(q + 7i32)] * tap
            j += 1i32
        }
        out[usize(i + 7i32)] = (t + (1i32 << (log2_size - 1u32))) >> log2_size
        i += 1i32
    }
    i = 0i32 - n
    while i < n {
        buf[at(pos, step, i)] = u16(out[usize(i + 7i32)])
        i += 1i32
    }
}

// The sample filtering process (7.14.6) at one position of the boundary: `pos` is the index of q0,
// `step` the distance between samples across the edge (1 for a vertical edge, the stride for a
// horizontal one), filter_size is 4, 8 or 16.
fn filter_sample(buf: []u16, pos: usize, step: usize, chroma: bool, st: Strength, filter_size: i32, bd: u32) {
    let sh = bd - 8u32
    let q0 = i32(buf[pos])
    let q1 = i32(buf[at(pos, step, 1i32)])
    let p0 = i32(buf[at(pos, step, -1i32)])
    let p1 = i32(buf[at(pos, step, -2i32)])
    let thresh_bd = st.thresh << sh
    let hev = iabs(p1 - p0) > thresh_bd || iabs(q1 - q0) > thresh_bd
    var filter_len = 16i32
    if filter_size == 4i32 { filter_len = 4i32 } else if chroma { filter_len = 6i32 } else if filter_size == 8i32 { filter_len = 8i32 }
    let limit_bd = st.limit << sh
    let blimit_bd = st.blimit << sh
    var bad = iabs(p1 - p0) > limit_bd || iabs(q1 - q0) > limit_bd || iabs(p0 - q0) * 2i32 + iabs(p1 - q1) / 2i32 > blimit_bd
    var q2 = 0i32
    var p2 = 0i32
    var q3 = 0i32
    var p3 = 0i32
    if filter_len >= 6i32 {
        q2 = i32(buf[at(pos, step, 2i32)])
        p2 = i32(buf[at(pos, step, -3i32)])
        if iabs(p2 - p1) > limit_bd || iabs(q2 - q1) > limit_bd { bad = true }
    }
    if filter_len >= 8i32 {
        q3 = i32(buf[at(pos, step, 3i32)])
        p3 = i32(buf[at(pos, step, -4i32)])
        if iabs(p3 - p2) > limit_bd || iabs(q3 - q2) > limit_bd { bad = true }
    }
    if bad { ret }
    let one = 1i32 << sh
    var flat = false
    if filter_size >= 8i32 {
        flat = iabs(p1 - p0) <= one && iabs(q1 - q0) <= one && iabs(p2 - p0) <= one && iabs(q2 - q0) <= one
        if filter_len >= 8i32 && (iabs(p3 - p0) > one || iabs(q3 - q0) > one) { flat = false }
    }
    if filter_size == 4i32 || !flat {
        narrow(buf, pos, step, hev, bd)
        ret
    }
    var flat2 = false
    if filter_size >= 16i32 {
        flat2 = true
        var m = 4i32
        while m <= 6i32 {
            if iabs(i32(buf[at(pos, step, 0i32 - (m + 1i32))]) - p0) > one || iabs(i32(buf[at(pos, step, m)]) - q0) > one { flat2 = false }
            m += 1i32
        }
    }
    if filter_size == 8i32 || !flat2 {
        wide(buf, pos, step, chroma, 3u32)
    } else {
        wide(buf, pos, step, chroma, 4u32)
    }
}

fn tx_sizes_of(f: *const LoopFilterFrame, plane: u32) -> []u8 {
    if plane == 0u32 { ret f.tx_sizes0 }
    if plane == 1u32 { ret f.tx_sizes1 }
    ret f.tx_sizes2
}

fn level_at(p: *const LoopFilterParams, f: *const LoopFilterFrame, row: usize, col: usize, plane: u32, pass: u32) -> i32 {
    let mi = row * f.mi_cols + col
    let mode = i32(f.y_modes[mi])
    var mode_type = 0usize
    if mode >= 14i32 && mode != 16i32 && mode != 24i32 { mode_type = 1usize }
    var which = 0usize
    if p.delta_lf_multi {
        which = usize(pass)
        if plane > 0u32 { which = usize(plane) + 1usize }
    }
    let d = i32(f.delta_lfs[mi * 4usize + which])
    ret filter_level(p, usize(f.segment_ids[mi]), i32(f.ref_frames[mi]), mode_type, d, plane, pass)
}

// The edge loop filter process (7.14.2) for one 4x4 luma position.
fn edge(p: *const LoopFilterParams, f: *const LoopFilterFrame, plane: u32, pass: u32, row0: usize, col0: usize) {
    var sub_x = 0u32
    var sub_y = 0u32
    if plane > 0u32 {
        sub_x = f.sub_x
        sub_y = f.sub_y
    }
    let x = col0 * 4usize
    let y = row0 * 4usize
    let row = row0 | usize(sub_y)
    let col = col0 | usize(sub_x)
    if x >= f.frame_width || y >= f.frame_height { ret }
    if pass == 0u32 && x == 0usize { ret }
    if pass == 1u32 && y == 0usize { ret }
    var dx = 1usize
    var dy = 0usize
    if pass == 1u32 {
        dx = 0usize
        dy = 1usize
    }
    let xp = x >> sub_x
    let yp = y >> sub_y
    let prev_row = row - (dy << sub_y)
    let prev_col = col - (dx << sub_x)
    let mi = row * f.mi_cols + col
    let txs = tx_sizes_of(f, plane)
    let tx = usize(txs[(row >> sub_y) * f.mi_cols + (col >> sub_x)])
    let prev_tx = usize(txs[(prev_row >> sub_y) * f.mi_cols + (prev_col >> sub_x)])
    let size = usize(f.mi_sizes[mi])
    let bw = imax(4i32, (4i32 * i32(blk_w4()[size])) >> sub_x)
    let bh = imax(4i32, (4i32 * i32(blk_h4()[size])) >> sub_y)
    let skip = f.skips[mi] != 0u8
    let intra = f.ref_frames[mi] <= 0i8
    var block_edge = false
    var tx_edge = false
    var base_size = 0i32
    if pass == 0u32 {
        block_edge = i32(xp) % bw == 0i32
        tx_edge = i32(xp) % i32(tx_w()[tx]) == 0i32
        base_size = imin(i32(tx_w()[prev_tx]), i32(tx_w()[tx]))
    } else {
        block_edge = i32(yp) % bh == 0i32
        tx_edge = i32(yp) % i32(tx_h()[tx]) == 0i32
        base_size = imin(i32(tx_h()[prev_tx]), i32(tx_h()[tx]))
    }
    if !tx_edge { ret }
    if !(block_edge || !skip || intra) { ret }
    var filter_size = imin(16i32, base_size)
    if plane > 0u32 { filter_size = imin(8i32, base_size) }
    var lvl = level_at(p, f, row, col, plane, pass)
    if lvl == 0i32 { lvl = level_at(p, f, prev_row, prev_col, plane, pass) }
    if lvl <= 0i32 { ret }
    let st = strength(p.sharpness, lvl)
    var stride = f.stride0
    if plane == 1u32 { stride = f.stride1 } else if plane == 2u32 { stride = f.stride2 }
    var step = 1usize
    if pass == 1u32 { step = stride }
    var i = 0usize
    while i < 4usize {
        let pos = (yp + dx * i) * stride + xp + dy * i
        if plane == 0u32 {
            filter_sample(f.p0, pos, step, false, st, filter_size, f.bit_depth)
        } else if plane == 1u32 {
            filter_sample(f.p1, pos, step, true, st, filter_size, f.bit_depth)
        } else {
            filter_sample(f.p2, pos, step, true, st, filter_size, f.bit_depth)
        }
        i += 1usize
    }
}

fn check_dims(f: *const LoopFilterFrame, plane: u32) -> bool {
    var sub_x = 0u32
    var sub_y = 0u32
    var stride = f.stride0
    var len = f.p0.len
    if plane > 0u32 {
        sub_x = f.sub_x
        sub_y = f.sub_y
        stride = f.stride1
        len = f.p1.len
        if plane == 2u32 {
            stride = f.stride2
            len = f.p2.len
        }
    }
    let w = (f.mi_cols * 4usize) >> sub_x
    let h = (f.mi_rows * 4usize) >> sub_y
    ret stride >= w && len >= (h - 1usize) * stride + w
}

// Filters the whole frame in place (7.14.1). Invalid: the sample planes or MI arrays are too small.
fn loop_filter(p: *const LoopFilterParams, f: *const LoopFilterFrame) -> err {
    let mis = f.mi_rows * f.mi_cols
    if f.mi_rows == 0usize || f.mi_cols == 0usize { ret Invalid }
    if f.bit_depth < 8u32 || f.bit_depth > 12u32 || f.num_planes < 1u32 || f.num_planes > 3u32 { ret Invalid }
    if f.mi_sizes.len < mis || f.skips.len < mis || f.ref_frames.len < mis || f.y_modes.len < mis || f.segment_ids.len < mis || f.delta_lfs.len < mis * 4usize { ret Invalid }
    var plane = 0u32
    while plane < f.num_planes {
        if !check_dims(f, plane) || tx_sizes_of(f, plane).len < mis { ret Invalid }
        plane += 1u32
    }
    plane = 0u32
    while plane < f.num_planes {
        if plane == 0u32 || p.levels[usize(1u32 + plane)] != 0i32 {
            var row_step = 1usize
            var col_step = 1usize
            if plane > 0u32 {
                row_step = 1usize << f.sub_y
                col_step = 1usize << f.sub_x
            }
            var pass = 0u32
            while pass < 2u32 {
                var row = 0usize
                while row < f.mi_rows {
                    var col = 0usize
                    while col < f.mi_cols {
                        edge(p, f, plane, pass, row, col)
                        col += col_step
                    }
                    row += row_step
                }
                pass += 1u32
            }
        }
        plane += 1u32
    }
    ret ok
}
