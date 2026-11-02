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

type Tabs = struct {
    lim: [64]i32,
    blim: [64]i32,
    thr: [64]i32,
    lv: [128]i32,
    td: [19]i32,
    bm: [22]i32
}

type Ctx = struct {
    plane: u32,
    pass: u32,
    sub_x: u32,
    sub_y: u32,
    mc: usize,
    stride: usize,
    which: usize,
    maxfs: i32,
    chroma: bool,
    bd: u32,
    one: i32,
    buf: []u16,
    txs: []u8
}

error Invalid

fn ab(x: i32) -> i32 {
    let m = x >> 31u32
    ret (x ^ m) - m
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
    var limit = lvl >> shift
    if limit < 1i32 { limit = 1i32 }
    if sharpness > 0i32 { limit = clip3(1i32, 9i32 - sharpness, lvl >> shift) }
    ret Strength { lvl: lvl, limit: limit, blimit: 2i32 * (lvl + 2i32) + limit, thresh: lvl >> 4u32 }
}

fn mode_type_of(mode: i32) -> usize {
    if mode >= 14i32 && mode != 16i32 && mode != 24i32 { ret 1usize }
    ret 0usize
}

fn delta_index(p: *const LoopFilterParams, plane: u32, pass: u32) -> usize {
    if !p.delta_lf_multi { ret 0usize }
    if plane > 0u32 { ret usize(plane) + 1usize }
    ret usize(pass)
}

fn level_mi(p: *const LoopFilterParams, f: *const LoopFilterFrame, mi: usize, plane: u32, pass: u32) -> i32 {
    let d = i32(f.delta_lfs[mi * 4usize + delta_index(p, plane, pass)])
    ret filter_level(p, usize(f.segment_ids[mi]), i32(f.ref_frames[mi]), mode_type_of(i32(f.y_modes[mi])), d, plane, pass)
}

fn level_at(p: *const LoopFilterParams, f: *const LoopFilterFrame, row: usize, col: usize, plane: u32, pass: u32) -> i32 {
    ret level_mi(p, f, row * f.mi_cols + col, plane, pass)
}

// The table holds filter_level for delta_lf == 0; any other value goes through level_mi.
fn level_of(p: *const LoopFilterParams, f: *const LoopFilterFrame, t: *const Tabs, c: *const Ctx, mi: usize) -> i32 {
    let seg = usize(f.segment_ids[mi])
    let rf = i32(f.ref_frames[mi])
    var rc = 0usize
    if rf > 0i32 { rc = usize(rf) }
    if f.delta_lfs[mi * 4usize + c.which] == 0i8 && seg < 8usize && rc < 8usize {
        ret t.lv[(seg * 8usize + rc) * 2usize + mode_type_of(i32(f.y_modes[mi]))]
    }
    ret level_mi(p, f, mi, c.plane, c.pass)
}

fn wide8(buf: []u16, pos: usize, step: usize) {
    let q0 = i32(buf[pos])
    let q1 = i32(buf[pos + step])
    let p0 = i32(buf[pos - step])
    let p1 = i32(buf[pos - 2usize * step])
    let q2 = i32(buf[pos + 2usize * step])
    let p2 = i32(buf[pos - 3usize * step])
    let q3 = i32(buf[pos + 3usize * step])
    let p3 = i32(buf[pos - 4usize * step])
    buf[pos - 3usize * step] = u16((p3 * 3i32 + p2 * 2i32 + p1 + p0 + q0 + 4i32) >> 3u32)
    buf[pos - 2usize * step] = u16((p3 * 2i32 + p2 + p1 * 2i32 + p0 + q0 + q1 + 4i32) >> 3u32)
    buf[pos - step] = u16((p3 + p2 + p1 + p0 * 2i32 + q0 + q1 + q2 + 4i32) >> 3u32)
    buf[pos] = u16((p2 + p1 + p0 + q0 * 2i32 + q1 + q2 + q3 + 4i32) >> 3u32)
    buf[pos + step] = u16((p1 + p0 + q0 + q1 * 2i32 + q2 + q3 * 2i32 + 4i32) >> 3u32)
    buf[pos + 2usize * step] = u16((p0 + q0 + q1 + q2 * 2i32 + q3 * 3i32 + 4i32) >> 3u32)
}

// The sample filtering process (7.14.6) for the 4 samples of one edge segment. `pos` is q0 of the first
// sample, `step` the distance across the edge, `adv` the distance along it; ln is the filter length
// (4, 6, 8 or 16). limit, blimit and thresh arrive already scaled to the bit depth. The masks use the
// sign bit: lim - |d| is negative exactly when |d| > lim.
fn filt(buf: []u16, pos0: usize, step: usize, adv: usize, cnt: i32, lim: i32, blim: i32, thr: i32, one: i32, bd: u32, ln: i32) {
    let s2 = 2usize * step
    let s3 = 3usize * step
    let s4 = 4usize * step
    let off = 128i32 << (bd - 8u32)
    let lo = 0i32 - (1i32 << (bd - 1u32))
    let hi = (1i32 << (bd - 1u32)) - 1i32
    var pos = pos0
    var n = 0i32
    while n < cnt {
        let q0 = i32(buf[pos])
        let q1 = i32(buf[pos + step])
        let p0 = i32(buf[pos - step])
        let p1 = i32(buf[pos - s2])
        let e1 = p1 - p0
        let m1 = e1 >> 31u32
        let dp = (e1 ^ m1) - m1
        let e2 = q1 - q0
        let m2 = e2 >> 31u32
        let dq = (e2 ^ m2) - m2
        let e3 = p0 - q0
        let m3 = e3 >> 31u32
        let e4 = p1 - q1
        let m4 = e4 >> 31u32
        var bad = (lim - dp) | (lim - dq) | (blim - (((e3 ^ m3) - m3) * 2i32 + ((((e4 ^ m4) - m4)) >> 1u32)))
        var q2 = 0i32
        var p2 = 0i32
        var q3 = 0i32
        var p3 = 0i32
        if ln >= 6i32 {
            q2 = i32(buf[pos + s2])
            p2 = i32(buf[pos - s3])
            bad = bad | (lim - ab(p2 - p1)) | (lim - ab(q2 - q1))
        }
        if ln >= 8i32 {
            q3 = i32(buf[pos + s3])
            p3 = i32(buf[pos - s4])
            bad = bad | (lim - ab(p3 - p2)) | (lim - ab(q3 - q2))
        }
        if bad >= 0i32 {
            var flat = false
            if ln >= 6i32 {
                var fl = (one - dp) | (one - dq) | (one - ab(p2 - p0)) | (one - ab(q2 - q0))
                if ln >= 8i32 { fl = fl | (one - ab(p3 - p0)) | (one - ab(q3 - q0)) }
                flat = fl >= 0i32
            }
            if !flat {
                let hev = ((thr - dp) | (thr - dq)) < 0i32
                let ps1 = p1 - off
                let ps0 = p0 - off
                let qs0 = q0 - off
                let qs1 = q1 - off
                var filter = 0i32
                if hev { filter = clip3(lo, hi, ps1 - qs1) }
                filter = clip3(lo, hi, filter + 3i32 * (qs0 - ps0))
                let filter1 = clip3(lo, hi, filter + 4i32) >> 3u32
                let filter2 = clip3(lo, hi, filter + 3i32) >> 3u32
                buf[pos] = u16(clip3(lo, hi, qs0 - filter1) + off)
                buf[pos - step] = u16(clip3(lo, hi, ps0 + filter2) + off)
                if !hev {
                    let f3 = (filter1 + 1i32) >> 1u32
                    buf[pos + step] = u16(clip3(lo, hi, qs1 - f3) + off)
                    buf[pos - s2] = u16(clip3(lo, hi, ps1 + f3) + off)
                }
            } else if ln == 6i32 {
                buf[pos - s2] = u16((p2 * 3i32 + p1 * 2i32 + p0 * 2i32 + q0 + 4i32) >> 3u32)
                buf[pos - step] = u16((p2 + p1 * 2i32 + p0 * 2i32 + q0 * 2i32 + q1 + 4i32) >> 3u32)
                buf[pos] = u16((p1 + p0 * 2i32 + q0 * 2i32 + q1 * 2i32 + q2 + 4i32) >> 3u32)
                buf[pos + step] = u16((p0 + q0 * 2i32 + q1 * 2i32 + q2 * 3i32 + 4i32) >> 3u32)
            } else if ln == 8i32 {
                wide8(buf, pos, step)
            } else {
                wide16(buf, pos, step, one)
            }
        }
        pos += adv
        n += 1i32
    }
}

// Luma filter length 16 on a flat position: the 14-tap filter when the outer samples are flat too, else the 8-tap.
fn wide16(buf: []u16, pos: usize, step: usize, one: i32) {
    let q0 = i32(buf[pos])
    let q1 = i32(buf[pos + step])
    let p0 = i32(buf[pos - step])
    let p1 = i32(buf[pos - 2usize * step])
    let q2 = i32(buf[pos + 2usize * step])
    let p2 = i32(buf[pos - 3usize * step])
    let q3 = i32(buf[pos + 3usize * step])
    let p3 = i32(buf[pos - 4usize * step])
    let q4 = i32(buf[pos + 4usize * step])
    let p4 = i32(buf[pos - 5usize * step])
    let q5 = i32(buf[pos + 5usize * step])
    let p5 = i32(buf[pos - 6usize * step])
    let q6 = i32(buf[pos + 6usize * step])
    let p6 = i32(buf[pos - 7usize * step])
    let fl = (one - ab(p4 - p0)) | (one - ab(q4 - q0)) | (one - ab(p5 - p0)) | (one - ab(q5 - q0)) | (one - ab(p6 - p0)) | (one - ab(q6 - q0))
    if fl < 0i32 {
        wide8(buf, pos, step)
        ret
    }
    var w = p6 * 6i32 + p5 + p4 + p3 + p2 + p1 + p0 + q0 + 8i32
    var t = p6 + p5 + p4
    buf[pos - 6usize * step] = u16((w + t) >> 4u32)
    w = w + q1 - p6
    t = t + p3 - p6
    buf[pos - 5usize * step] = u16((w + t) >> 4u32)
    w = w + q2 - p6
    t = t + p2 - p5
    buf[pos - 4usize * step] = u16((w + t) >> 4u32)
    w = w + q3 - p6
    t = t + p1 - p4
    buf[pos - 3usize * step] = u16((w + t) >> 4u32)
    w = w + q4 - p6
    t = t + p0 - p3
    buf[pos - 2usize * step] = u16((w + t) >> 4u32)
    w = w + q5 - p6
    t = t + q0 - p2
    buf[pos - step] = u16((w + t) >> 4u32)
    w = w + q6 - p6
    t = t + q1 - p1
    buf[pos] = u16((w + t) >> 4u32)
    w = w + q6 - p5
    t = t + q2 - p0
    buf[pos + step] = u16((w + t) >> 4u32)
    w = w + q6 - p4
    t = t + q3 - q0
    buf[pos + 2usize * step] = u16((w + t) >> 4u32)
    w = w + q6 - p3
    t = t + q4 - q1
    buf[pos + 3usize * step] = u16((w + t) >> 4u32)
    w = w + q6 - p2
    t = t + q5 - q2
    buf[pos + 4usize * step] = u16((w + t) >> 4u32)
    w = w + q6 - p1
    t = t + q6 - q3
    buf[pos + 5usize * step] = u16((w + t) >> 4u32)
}

// The sample filtering process (7.14.6) at one position of the boundary: `pos` is the index of q0, `step` the
// distance between samples across the edge, filter_size is 4, 8 or 16.
fn filter_sample(buf: []u16, pos: usize, step: usize, chroma: bool, st: Strength, filter_size: i32, bd: u32) {
    let sh = bd - 8u32
    var ln = 16i32
    if filter_size == 4i32 { ln = 4i32 } else if chroma { ln = 6i32 } else if filter_size == 8i32 { ln = 8i32 }
    filt(buf, pos, step, 0usize, 1i32, st.limit << sh, st.blimit << sh, st.thresh << sh, 1i32 << sh, bd, ln)
}

fn tx_sizes_of(f: *const LoopFilterFrame, plane: u32) -> []u8 {
    if plane == 0u32 { ret f.tx_sizes0 }
    if plane == 1u32 { ret f.tx_sizes1 }
    ret f.tx_sizes2
}

// The edge loop filter process (7.14.2) for one 4x4 luma position; the frame and pass invariants are in c and t.
fn edge(p: *const LoopFilterParams, f: *const LoopFilterFrame, t: *const Tabs, c: *const Ctx, row0: usize, col0: usize) {
    let row = row0 | usize(c.sub_y)
    let col = col0 | usize(c.sub_x)
    let mi = row * f.mi_cols + col
    let ti = (row >> c.sub_y) * c.mc + (col >> c.sub_x)
    let xp = (col0 * 4usize) >> c.sub_x
    let yp = (row0 * 4usize) >> c.sub_y
    var cpos = xp
    var prev_mi = mi - (1usize << c.sub_x)
    var prev_ti = ti - 1usize
    if c.pass == 1u32 {
        cpos = yp
        prev_mi = mi - (f.mi_cols << c.sub_y)
        prev_ti = ti - c.mc
    }
    let tdim = t.td[usize(c.txs[ti])]
    if (i32(cpos) & (tdim - 1i32)) != 0i32 { ret }
    if (i32(cpos) & t.bm[usize(f.mi_sizes[mi])]) != 0i32 && f.skips[mi] != 0u8 && f.ref_frames[mi] > 0i8 { ret }
    var fs = tdim
    let pdim = t.td[usize(c.txs[prev_ti])]
    if pdim < fs { fs = pdim }
    if fs > c.maxfs { fs = c.maxfs }
    var lvl = level_of(p, f, t, c, mi)
    if lvl == 0i32 { lvl = level_of(p, f, t, c, prev_mi) }
    if lvl <= 0i32 { ret }
    let lim = t.lim[usize(lvl)]
    let blim = t.blim[usize(lvl)]
    let thr = t.thr[usize(lvl)]
    var step = 1usize
    var adv = c.stride
    if c.pass == 1u32 {
        step = c.stride
        adv = 1usize
    }
    var ln = fs
    if fs == 8i32 && c.chroma { ln = 6i32 }
    filt(c.buf, yp * c.stride + xp, step, adv, 4i32, lim, blim, thr, c.one, c.bd, ln)
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

fn fill_tabs(p: *const LoopFilterParams, f: *const LoopFilterFrame, t: *Tabs, c: *const Ctx) {
    let sh = f.bit_depth - 8u32
    var l = 0i32
    while l < 64i32 {
        let st = strength(p.sharpness, l)
        t.lim[usize(l)] = st.limit << sh
        t.blim[usize(l)] = st.blimit << sh
        t.thr[usize(l)] = st.thresh << sh
        l += 1i32
    }
    var k = 0usize
    while k < 128usize {
        let mt = k & 1usize
        let rc = (k >> 1u32) & 7usize
        let seg = k >> 4u32
        var rf = 0i32
        if rc > 0usize { rf = i32(rc) }
        t.lv[k] = filter_level(p, seg, rf, mt, 0i32, c.plane, c.pass)
        k += 1usize
    }
    k = 0usize
    while k < 19usize {
        if c.pass == 0u32 { t.td[k] = i32(tx_w()[k]) } else { t.td[k] = i32(tx_h()[k]) }
        k += 1usize
    }
    k = 0usize
    while k < 22usize {
        var b = 0i32
        if c.pass == 0u32 { b = (4i32 * i32(blk_w4()[k])) >> c.sub_x } else { b = (4i32 * i32(blk_h4()[k])) >> c.sub_y }
        if b < 4i32 { b = 4i32 }
        t.bm[k] = b - 1i32
        k += 1usize
    }
}

fn filter_pass(p: *const LoopFilterParams, f: *const LoopFilterFrame, t: *Tabs, plane: u32, pass: u32) {
    var sub_x = 0u32
    var sub_y = 0u32
    var buf = f.p0
    var stride = f.stride0
    if plane > 0u32 {
        sub_x = f.sub_x
        sub_y = f.sub_y
        buf = f.p1
        stride = f.stride1
        if plane == 2u32 {
            buf = f.p2
            stride = f.stride2
        }
    }
    let which = delta_index(p, plane, pass)
    var maxfs = 16i32
    if plane > 0u32 { maxfs = 8i32 }
    let c = Ctx { plane: plane, pass: pass, sub_x: sub_x, sub_y: sub_y, mc: f.mi_cols, stride: stride, which: which, maxfs: maxfs, chroma: plane > 0u32, bd: f.bit_depth, one: 1i32 << (f.bit_depth - 8u32), buf: buf, txs: tx_sizes_of(f, plane) }
    fill_tabs(p, f, t, &c)
    let row_step = 1usize << sub_y
    let col_step = 1usize << sub_x
    var row_end = (f.frame_height + 3usize) >> 2u32
    var col_end = (f.frame_width + 3usize) >> 2u32
    if row_end > f.mi_rows { row_end = f.mi_rows }
    if col_end > f.mi_cols { col_end = f.mi_cols }
    var row = 0usize
    var col_start = 0usize
    if pass == 0u32 { col_start = col_step } else { row = row_step }
    while row < row_end {
        var col = col_start
        while col < col_end {
            edge(p, f, t, &c, row, col)
            col += col_step
        }
        row += row_step
    }
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
    var t: Tabs = zero
    plane = 0u32
    while plane < f.num_planes {
        if plane == 0u32 || p.levels[usize(1u32 + plane)] != 0i32 {
            filter_pass(p, f, &t, plane, 0u32)
            filter_pass(p, f, &t, plane, 1u32)
        }
        plane += 1u32
    }
    ret ok
}
