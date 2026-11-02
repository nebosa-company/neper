// AV1 loop filter (deblocking), section 7.14 of the specification: the edge loop filter, filter size,
// adaptive strength and the narrow / 6, 8 and 14-tap wide sample filters, on 8-bit sample planes.
//
// Interface. `loop_filter(p, f)` filters every plane of one frame in place: planes in order, and for
// each plane all vertical edges (pass 0) over the whole frame, then all horizontal edges (pass 1).
// The caller applies the frame-level rule "run only when levels[0] or levels[1] is non-zero";
// `loop_filter` itself skips a chroma plane whose level is zero, as the process does. Only
// bit_depth 8 is supported: any other value is Invalid.
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
//
// Threads. `loop_filter` is `loop_filter_plane_prepare` + `filter_pass_rows` / `filter_pass_cols` over
// the whole plane, per enabled plane (`plane_enabled`). A caller may split a pass over workers: prepare once
// per plane and pass, share the `Prepared` read-only, and give each worker a disjoint range of 4x4 rows
// (pass 0) or columns (pass 1) of the plane. The ranges may run in any order or at once; pass 1 of a plane
// starts only after every pass 0 range of that plane has finished. Planes are independent buffers.
// Why disjoint ranges are safe (7.14.6): a vertical edge filters along sample rows and changes at most 6
// samples (reads 7) on each side of the edge, all in its own row, so a pass 0 unit at plane row r4 touches
// only sample rows 4*r4 .. 4*r4+3; the horizontal edge likewise only sample columns 4*c4 .. 4*c4+3.
// Everything else read (MI arrays, tx sizes, Prepared) is not written.
//
// Vectors. Edges are decided per 4x4 unit in scalar code (`edge_ep`); four neighbouring units are then
// filtered together as 16 byte lanes (pass 1: four units side by side, the samples across the edge are
// whole rows; pass 0: four units on top of each other, transposed 16x8 or 16x16 byte blocks give one
// vector per sample column). Every lane of a vector sees its own unit's limits and filter length through
// per-lane masks. Each sample row (pass 0) or column (pass 1) still meets its edges in the same order as
// the scalar process, so inconsistent transform sizes give the same bytes as well. A group that does not
// fit (plane edge, range end) goes through the scalar `filt`. The edge decision reads the MI arrays without
// bounds checks: `loop_filter_plane_prepare` rejects (valid = false) a plane whose last unit row or column
// would need a MI row or column beyond mi_rows / mi_cols (odd MI counts with subsampling).

use e.mem
use e.simd

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
    p0: []u8,
    p1: []u8,
    p2: []u8,
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
    pw: usize,
    which: usize,
    maxfs: i32,
    chroma: bool,
    buf: []u8,
    txs: []u8
}

// One 4x4 unit's edge decision: ln is the filter length (0 = nothing to filter, else 4, 6, 8 or 16),
// pos the index of q0 of the unit's first sample.
type Ep = struct { ln: i32, lim: i32, blim: i32, thr: i32, pos: usize }

type Eps = struct { e: [4]Ep }

// Group parameters, one lane per sample. w / w2 are 0xFF byte masks and only meaningful when `mixed`: the
// units of the group then differ in length or strength. A unit without an edge has lim = blim = 0, which
// leaves its lanes unchanged. w: luma length >= 8, chroma length 6;
// w2: luma length 16.
type Gp = struct {
    lim: Vec[u8, 16],
    blim: Vec[u8, 16],
    thr: Vec[u8, 16],
    w: Vec[u8, 16],
    w2: Vec[u8, 16],
    maxln: i32,
    mixed: bool
}

// Sample columns p7..p0 = 0..7, q0..q7 = 8..15; each vector holds the 16 lanes of the group.
type Cols = struct { c: [16]Vec[u8, 16] }


type Wo = struct { v: [12]Vec[u8, 16] }

type Work = struct { es: Eps, g: Gp, cols: Cols }

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

// ---- scalar sample filters (units that do not fit a vector group)

fn wide8(buf: []u8, pos: usize, step: usize) {
    @nocheck {
    let q0 = i32(buf[pos])
    let q1 = i32(buf[pos + step])
    let p0 = i32(buf[pos - step])
    let p1 = i32(buf[pos - 2usize * step])
    let q2 = i32(buf[pos + 2usize * step])
    let p2 = i32(buf[pos - 3usize * step])
    let q3 = i32(buf[pos + 3usize * step])
    let p3 = i32(buf[pos - 4usize * step])
    buf[pos - 3usize * step] = u8((p3 * 3i32 + p2 * 2i32 + p1 + p0 + q0 + 4i32) >> 3u32)
    buf[pos - 2usize * step] = u8((p3 * 2i32 + p2 + p1 * 2i32 + p0 + q0 + q1 + 4i32) >> 3u32)
    buf[pos - step] = u8((p3 + p2 + p1 + p0 * 2i32 + q0 + q1 + q2 + 4i32) >> 3u32)
    buf[pos] = u8((p2 + p1 + p0 + q0 * 2i32 + q1 + q2 + q3 + 4i32) >> 3u32)
    buf[pos + step] = u8((p1 + p0 + q0 + q1 * 2i32 + q2 + q3 * 2i32 + 4i32) >> 3u32)
    buf[pos + 2usize * step] = u8((p0 + q0 + q1 + q2 * 2i32 + q3 * 3i32 + 4i32) >> 3u32)
    }
}

// The sample filtering process (7.14.6) for the 4 samples of one edge segment. `pos` is q0 of the first
// sample, `step` the distance across the edge, `adv` the distance along it; ln is the filter length
// (4, 6, 8 or 16). The masks use the sign bit: lim - |d| is negative exactly when |d| > lim.
fn filt(buf: []u8, pos0: usize, step: usize, adv: usize, cnt: i32, lim: i32, blim: i32, thr: i32, ln: i32) {
    let s2 = 2usize * step
    let s3 = 3usize * step
    let s4 = 4usize * step
    var pos = pos0
    var n = 0i32
    @nocheck {
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
                var fl = (1i32 - dp) | (1i32 - dq) | (1i32 - ab(p2 - p0)) | (1i32 - ab(q2 - q0))
                if ln >= 8i32 { fl = fl | (1i32 - ab(p3 - p0)) | (1i32 - ab(q3 - q0)) }
                flat = fl >= 0i32
            }
            if !flat {
                let hev = ((thr - dp) | (thr - dq)) < 0i32
                var filter = 0i32
                if hev {
                    filter = p1 - q1
                    if filter < 0i32 - 128i32 { filter = 0i32 - 128i32 } else if filter > 127i32 { filter = 127i32 }
                }
                filter = filter + 3i32 * (q0 - p0)
                if filter < 0i32 - 128i32 { filter = 0i32 - 128i32 } else if filter > 127i32 { filter = 127i32 }
                var t1 = filter + 4i32
                if t1 > 127i32 { t1 = 127i32 }
                var t2 = filter + 3i32
                if t2 > 127i32 { t2 = 127i32 }
                let filter1 = t1 >> 3u32
                let filter2 = t2 >> 3u32
                var n0 = q0 - filter1
                if n0 < 0i32 { n0 = 0i32 } else if n0 > 255i32 { n0 = 255i32 }
                var n1 = p0 + filter2
                if n1 < 0i32 { n1 = 0i32 } else if n1 > 255i32 { n1 = 255i32 }
                buf[pos] = u8(n0)
                buf[pos - step] = u8(n1)
                if !hev {
                    let f3 = (filter1 + 1i32) >> 1u32
                    var n2 = q1 - f3
                    if n2 < 0i32 { n2 = 0i32 } else if n2 > 255i32 { n2 = 255i32 }
                    var n3 = p1 + f3
                    if n3 < 0i32 { n3 = 0i32 } else if n3 > 255i32 { n3 = 255i32 }
                    buf[pos + step] = u8(n2)
                    buf[pos - s2] = u8(n3)
                }
            } else if ln == 6i32 {
                buf[pos - s2] = u8((p2 * 3i32 + p1 * 2i32 + p0 * 2i32 + q0 + 4i32) >> 3u32)
                buf[pos - step] = u8((p2 + p1 * 2i32 + p0 * 2i32 + q0 * 2i32 + q1 + 4i32) >> 3u32)
                buf[pos] = u8((p1 + p0 * 2i32 + q0 * 2i32 + q1 * 2i32 + q2 + 4i32) >> 3u32)
                buf[pos + step] = u8((p0 + q0 * 2i32 + q1 * 2i32 + q2 * 3i32 + 4i32) >> 3u32)
            } else if ln == 8i32 {
                wide8(buf, pos, step)
            } else {
                wide16(buf, pos, step)
            }
        }
        pos += adv
        n += 1i32
    }
    }
}

// Whether filt with length ln at cnt positions stays inside a buffer of len samples.
fn reach_ok(len: usize, pos: usize, step: usize, adv: usize, cnt: i32, ln: i32) -> bool {
    var back = 2usize
    if ln >= 16i32 { back = 7usize } else if ln >= 8i32 { back = 4usize } else if ln >= 6i32 { back = 3usize }
    if pos < back * step { ret false }
    ret pos + usize(cnt - 1i32) * adv + (back - 1usize) * step < len
}

// Luma filter length 16 on a flat position: the 14-tap filter when the outer samples are flat too, else the 8-tap.
fn wide16(buf: []u8, pos: usize, step: usize) {
    @nocheck {
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
    let fl = (1i32 - ab(p4 - p0)) | (1i32 - ab(q4 - q0)) | (1i32 - ab(p5 - p0)) | (1i32 - ab(q5 - q0)) | (1i32 - ab(p6 - p0)) | (1i32 - ab(q6 - q0))
    if fl < 0i32 {
        wide8(buf, pos, step)
        ret
    }
    var w = p6 * 6i32 + p5 + p4 + p3 + p2 + p1 + p0 + q0 + 8i32
    var t = p6 + p5 + p4
    buf[pos - 6usize * step] = u8((w + t) >> 4u32)
    w = w + q1 - p6
    t = t + p3 - p6
    buf[pos - 5usize * step] = u8((w + t) >> 4u32)
    w = w + q2 - p6
    t = t + p2 - p5
    buf[pos - 4usize * step] = u8((w + t) >> 4u32)
    w = w + q3 - p6
    t = t + p1 - p4
    buf[pos - 3usize * step] = u8((w + t) >> 4u32)
    w = w + q4 - p6
    t = t + p0 - p3
    buf[pos - 2usize * step] = u8((w + t) >> 4u32)
    w = w + q5 - p6
    t = t + q0 - p2
    buf[pos - step] = u8((w + t) >> 4u32)
    w = w + q6 - p6
    t = t + q1 - p1
    buf[pos] = u8((w + t) >> 4u32)
    w = w + q6 - p5
    t = t + q2 - p0
    buf[pos + step] = u8((w + t) >> 4u32)
    w = w + q6 - p4
    t = t + q3 - q0
    buf[pos + 2usize * step] = u8((w + t) >> 4u32)
    w = w + q6 - p3
    t = t + q4 - q1
    buf[pos + 3usize * step] = u8((w + t) >> 4u32)
    w = w + q6 - p2
    t = t + q5 - q2
    buf[pos + 4usize * step] = u8((w + t) >> 4u32)
    w = w + q6 - p1
    t = t + q6 - q3
    buf[pos + 5usize * step] = u8((w + t) >> 4u32)
    }
}

// ---- vector kernels: Cols holds one vector per sample column, the lanes are the filtered positions

// 8-tap flat filter: outputs p2, p1, p0, q0, q1, q2.
fn w8(c: *const Cols, o: *Wo) {
    @nocheck {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let four = simd.splat[Vec[i16, 8]](4i16)
    let a3L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[4usize], z))
    let a2L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[5usize], z))
    let a1L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[6usize], z))
    let a0L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[7usize], z))
    let b0L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[8usize], z))
    let b1L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[9usize], z))
    let b2L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[10usize], z))
    let b3L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[11usize], z))
    var sL = (a3L << 1u32) +% a3L +% (a2L << 1u32) +% a1L +% a0L +% b0L +% four
    let r0L = sL >> 3u32
    sL = sL -% a3L -% a2L +% a1L +% b1L
    let r1L = sL >> 3u32
    sL = sL -% a3L -% a1L +% a0L +% b2L
    let r2L = sL >> 3u32
    sL = sL -% a3L -% a0L +% b0L +% b3L
    let r3L = sL >> 3u32
    sL = sL -% a2L -% b0L +% b1L +% b3L
    let r4L = sL >> 3u32
    sL = sL -% a1L -% b1L +% b2L +% b3L
    let r5L = sL >> 3u32
    let a3H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[4usize], z))
    let a2H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[5usize], z))
    let a1H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[6usize], z))
    let a0H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[7usize], z))
    let b0H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[8usize], z))
    let b1H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[9usize], z))
    let b2H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[10usize], z))
    let b3H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[11usize], z))
    var sH = (a3H << 1u32) +% a3H +% (a2H << 1u32) +% a1H +% a0H +% b0H +% four
    let r0H = sH >> 3u32
    sH = sH -% a3H -% a2H +% a1H +% b1H
    let r1H = sH >> 3u32
    sH = sH -% a3H -% a1H +% a0H +% b2H
    let r2H = sH >> 3u32
    sH = sH -% a3H -% a0H +% b0H +% b3H
    let r3H = sH >> 3u32
    sH = sH -% a2H -% b0H +% b1H +% b3H
    let r4H = sH >> 3u32
    sH = sH -% a1H -% b1H +% b2H +% b3H
    let r5H = sH >> 3u32
    o.v[0usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r0L, r0H)
    o.v[1usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r1L, r1H)
    o.v[2usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r2L, r2H)
    o.v[3usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r3L, r3H)
    o.v[4usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r4L, r4H)
    o.v[5usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r5L, r5H)
    }
}

// 6-tap flat filter (chroma): outputs p1, p0, q0, q1.
fn w6(c: *const Cols, o: *Wo) {
    @nocheck {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let four = simd.splat[Vec[i16, 8]](4i16)
    let a2L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[5usize], z))
    let a1L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[6usize], z))
    let a0L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[7usize], z))
    let b0L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[8usize], z))
    let b1L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[9usize], z))
    let b2L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[10usize], z))
    var sL = (a2L << 1u32) +% a2L +% (a1L << 1u32) +% (a0L << 1u32) +% b0L +% four
    let r0L = sL >> 3u32
    sL = sL -% (a2L << 1u32) +% b0L +% b1L
    let r1L = sL >> 3u32
    sL = sL -% a2L -% a1L +% b1L +% b2L
    let r2L = sL >> 3u32
    sL = sL -% a1L -% a0L +% (b2L << 1u32)
    let r3L = sL >> 3u32
    let a2H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[5usize], z))
    let a1H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[6usize], z))
    let a0H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[7usize], z))
    let b0H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[8usize], z))
    let b1H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[9usize], z))
    let b2H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[10usize], z))
    var sH = (a2H << 1u32) +% a2H +% (a1H << 1u32) +% (a0H << 1u32) +% b0H +% four
    let r0H = sH >> 3u32
    sH = sH -% (a2H << 1u32) +% b0H +% b1H
    let r1H = sH >> 3u32
    sH = sH -% a2H -% a1H +% b1H +% b2H
    let r2H = sH >> 3u32
    sH = sH -% a1H -% a0H +% (b2H << 1u32)
    let r3H = sH >> 3u32
    o.v[0usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r0L, r0H)
    o.v[1usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r1L, r1H)
    o.v[2usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r2L, r2H)
    o.v[3usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r3L, r3H)
    }
}

// 14-tap flat filter: outputs p5 .. p0, q0 .. q5.
fn w14(c: *const Cols, o: *Wo) {
    @nocheck {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let eight = simd.splat[Vec[i16, 8]](8i16)
    let a6L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[1usize], z))
    let a5L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[2usize], z))
    let a4L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[3usize], z))
    let a3L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[4usize], z))
    let a2L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[5usize], z))
    let a1L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[6usize], z))
    let a0L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[7usize], z))
    let b0L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[8usize], z))
    let b1L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[9usize], z))
    let b2L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[10usize], z))
    let b3L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[11usize], z))
    let b4L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[12usize], z))
    let b5L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[13usize], z))
    let b6L = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](c.c[14usize], z))
    var wL = (a6L << 2u32) +% (a6L << 1u32) +% a5L +% a4L +% a3L +% a2L +% a1L +% a0L +% b0L +% eight
    var tL = a6L +% a5L +% a4L
    let r0L = (wL +% tL) >> 4u32
    wL = wL +% b1L -% a6L
    tL = tL +% a3L -% a6L
    let r1L = (wL +% tL) >> 4u32
    wL = wL +% b2L -% a6L
    tL = tL +% a2L -% a5L
    let r2L = (wL +% tL) >> 4u32
    wL = wL +% b3L -% a6L
    tL = tL +% a1L -% a4L
    let r3L = (wL +% tL) >> 4u32
    wL = wL +% b4L -% a6L
    tL = tL +% a0L -% a3L
    let r4L = (wL +% tL) >> 4u32
    wL = wL +% b5L -% a6L
    tL = tL +% b0L -% a2L
    let r5L = (wL +% tL) >> 4u32
    wL = wL +% b6L -% a6L
    tL = tL +% b1L -% a1L
    let r6L = (wL +% tL) >> 4u32
    wL = wL +% b6L -% a5L
    tL = tL +% b2L -% a0L
    let r7L = (wL +% tL) >> 4u32
    wL = wL +% b6L -% a4L
    tL = tL +% b3L -% b0L
    let r8L = (wL +% tL) >> 4u32
    wL = wL +% b6L -% a3L
    tL = tL +% b4L -% b1L
    let r9L = (wL +% tL) >> 4u32
    wL = wL +% b6L -% a2L
    tL = tL +% b5L -% b2L
    let r10L = (wL +% tL) >> 4u32
    wL = wL +% b6L -% a1L
    tL = tL +% b6L -% b3L
    let r11L = (wL +% tL) >> 4u32
    let a6H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[1usize], z))
    let a5H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[2usize], z))
    let a4H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[3usize], z))
    let a3H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[4usize], z))
    let a2H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[5usize], z))
    let a1H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[6usize], z))
    let a0H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[7usize], z))
    let b0H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[8usize], z))
    let b1H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[9usize], z))
    let b2H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[10usize], z))
    let b3H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[11usize], z))
    let b4H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[12usize], z))
    let b5H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[13usize], z))
    let b6H = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](c.c[14usize], z))
    var wH = (a6H << 2u32) +% (a6H << 1u32) +% a5H +% a4H +% a3H +% a2H +% a1H +% a0H +% b0H +% eight
    var tH = a6H +% a5H +% a4H
    let r0H = (wH +% tH) >> 4u32
    wH = wH +% b1H -% a6H
    tH = tH +% a3H -% a6H
    let r1H = (wH +% tH) >> 4u32
    wH = wH +% b2H -% a6H
    tH = tH +% a2H -% a5H
    let r2H = (wH +% tH) >> 4u32
    wH = wH +% b3H -% a6H
    tH = tH +% a1H -% a4H
    let r3H = (wH +% tH) >> 4u32
    wH = wH +% b4H -% a6H
    tH = tH +% a0H -% a3H
    let r4H = (wH +% tH) >> 4u32
    wH = wH +% b5H -% a6H
    tH = tH +% b0H -% a2H
    let r5H = (wH +% tH) >> 4u32
    wH = wH +% b6H -% a6H
    tH = tH +% b1H -% a1H
    let r6H = (wH +% tH) >> 4u32
    wH = wH +% b6H -% a5H
    tH = tH +% b2H -% a0H
    let r7H = (wH +% tH) >> 4u32
    wH = wH +% b6H -% a4H
    tH = tH +% b3H -% b0H
    let r8H = (wH +% tH) >> 4u32
    wH = wH +% b6H -% a3H
    tH = tH +% b4H -% b1H
    let r9H = (wH +% tH) >> 4u32
    wH = wH +% b6H -% a2H
    tH = tH +% b5H -% b2H
    let r10H = (wH +% tH) >> 4u32
    wH = wH +% b6H -% a1H
    tH = tH +% b6H -% b3H
    let r11H = (wH +% tH) >> 4u32
    o.v[0usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r0L, r0H)
    o.v[1usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r1L, r1H)
    o.v[2usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r2L, r2H)
    o.v[3usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r3L, r3H)
    o.v[4usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r4L, r4H)
    o.v[5usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r5L, r5H)
    o.v[6usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r6L, r6H)
    o.v[7usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r7L, r7H)
    o.v[8usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r8L, r8H)
    o.v[9usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r9L, r9H)
    o.v[10usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r10L, r10H)
    o.v[11usize] = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](r11L, r11H)
    }
}

// The narrow filter on columns p1 .. q1 for the lanes of `nmv` (0xFF); hev lanes are 0xFF too. The
// filter works on the sign-flipped samples with saturating signed byte arithmetic, which is the clip
// to [-128, 127]; f1b / f2b hold (filter + 4) >> 3 and (filter + 3) >> 3 plus 16.
fn narrow(c: *Cols, nmv: Vec[u8, 16], hev: Vec[u8, 16]) {
    @nocheck {
    let sg = simd.splat[Vec[u8, 16]](128u8)
    let ps1 = mem.bitcast[Vec[i8, 16]](c.c[6usize] ^ sg)
    let ps0 = mem.bitcast[Vec[i8, 16]](c.c[7usize] ^ sg)
    let qs0 = mem.bitcast[Vec[i8, 16]](c.c[8usize] ^ sg)
    let qs1 = mem.bitcast[Vec[i8, 16]](c.c[9usize] ^ sg)
    var f = simd.subs[Vec[i8, 16]](ps1, qs1) & mem.bitcast[Vec[i8, 16]](hev)
    let d = simd.subs[Vec[i8, 16]](qs0, ps0)
    f = simd.adds[Vec[i8, 16]](simd.adds[Vec[i8, 16]](simd.adds[Vec[i8, 16]](f, d), d), d) & mem.bitcast[Vec[i8, 16]](nmv)
    let m31 = simd.splat[Vec[u8, 16]](31u8)
    let s16 = simd.splat[Vec[u8, 16]](16u8)
    let f1b = mem.bitcast[Vec[u8, 16]](mem.bitcast[Vec[u16, 8]](mem.bitcast[Vec[u8, 16]](simd.adds[Vec[i8, 16]](f, simd.splat[Vec[i8, 16]](4i8))) ^ sg) >> 3u32) & m31
    let f2b = mem.bitcast[Vec[u8, 16]](mem.bitcast[Vec[u16, 8]](mem.bitcast[Vec[u8, 16]](simd.adds[Vec[i8, 16]](f, simd.splat[Vec[i8, 16]](3i8))) ^ sg) >> 3u32) & m31
    let f3 = (simd.avg_u8[Vec[u8, 16]](f1b, simd.splat[Vec[u8, 16]](0u8)) -% simd.splat[Vec[u8, 16]](8u8)) & ~hev
    c.c[6usize] = mem.bitcast[Vec[u8, 16]](simd.adds[Vec[i8, 16]](ps1, mem.bitcast[Vec[i8, 16]](f3))) ^ sg
    c.c[7usize] = mem.bitcast[Vec[u8, 16]](simd.adds[Vec[i8, 16]](ps0, mem.bitcast[Vec[i8, 16]](f2b -% s16))) ^ sg
    c.c[8usize] = mem.bitcast[Vec[u8, 16]](simd.subs[Vec[i8, 16]](qs0, mem.bitcast[Vec[i8, 16]](f1b -% s16))) ^ sg
    c.c[9usize] = mem.bitcast[Vec[u8, 16]](simd.subs[Vec[i8, 16]](qs1, mem.bitcast[Vec[i8, 16]](f3))) ^ sg
    }
}

fn kern_luma(c: *Cols, g: *const Gp) {
    @nocheck {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let one = simd.splat[Vec[u8, 16]](1u8)
    let p1 = c.c[6usize]
    let p0 = c.c[7usize]
    let q0 = c.c[8usize]
    let q1 = c.c[9usize]
    let md = simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p1, p0), simd.abs_diff[Vec[u8, 16]](q1, q0))
    var m = md
    var fl = md
    if g.maxln >= 8i32 {
        let p2 = c.c[5usize]
        let q2 = c.c[10usize]
        let p3 = c.c[4usize]
        let q3 = c.c[11usize]
        var t = simd.max[Vec[u8, 16]](simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p2, p1), simd.abs_diff[Vec[u8, 16]](q2, q1)), simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p3, p2), simd.abs_diff[Vec[u8, 16]](q3, q2)))
        if g.mixed { t = t & g.w }
        m = simd.max[Vec[u8, 16]](m, t)
        fl = simd.max[Vec[u8, 16]](fl, simd.max[Vec[u8, 16]](simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p2, p0), simd.abs_diff[Vec[u8, 16]](q2, q0)), simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p3, p0), simd.abs_diff[Vec[u8, 16]](q3, q0))))
    }
    let d1 = simd.abs_diff[Vec[u8, 16]](p1, q1)
    let d0 = simd.abs_diff[Vec[u8, 16]](p0, q0)
    let bs = simd.adds[Vec[u8, 16]](simd.adds[Vec[u8, 16]](d0, d0), simd.subs[Vec[u8, 16]](d1, simd.avg_u8[Vec[u8, 16]](d1, z)))
    let okv = simd.min[Vec[u8, 16]](simd.max[Vec[u8, 16]](simd.subs[Vec[u8, 16]](m, g.lim), simd.subs[Vec[u8, 16]](bs, g.blim)), one) -% one
    let hev = z -% simd.min[Vec[u8, 16]](simd.subs[Vec[u8, 16]](md, g.thr), one)
    if g.maxln < 8i32 {
        narrow(c, okv, hev)
        ret
    }
    var m8 = okv & (simd.min[Vec[u8, 16]](simd.subs[Vec[u8, 16]](fl, one), one) -% one)
    if g.mixed { m8 = m8 & g.w }
    if simd.movemask[Vec[u8, 16]](m8) == 0u64 {
        narrow(c, okv, hev)
        ret
    }
    var o8: Wo = zero
    w8(c, &o8)
    var m16 = m8
    var o14: Wo = zero
    var wide = false
    if g.maxln >= 16i32 {
        let o = simd.max[Vec[u8, 16]](simd.max[Vec[u8, 16]](simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](c.c[3usize], p0), simd.abs_diff[Vec[u8, 16]](c.c[12usize], q0)), simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](c.c[2usize], p0), simd.abs_diff[Vec[u8, 16]](c.c[13usize], q0))), simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](c.c[1usize], p0), simd.abs_diff[Vec[u8, 16]](c.c[14usize], q0)))
        m16 = m8 & (simd.min[Vec[u8, 16]](simd.subs[Vec[u8, 16]](o, one), one) -% one)
        if g.mixed { m16 = m16 & g.w2 }
        wide = simd.movemask[Vec[u8, 16]](m16) != 0u64
        if wide { w14(c, &o14) }
    }
    narrow(c, okv & ~m8, hev)
    var k = 0usize
    while k < 6usize {
        let b = c.c[5usize + k]
        c.c[5usize + k] = b ^ ((o8.v[k] ^ b) & m8)
        k += 1usize
    }
    if wide {
        k = 0usize
        while k < 12usize {
            let b = c.c[2usize + k]
            c.c[2usize + k] = b ^ ((o14.v[k] ^ b) & m16)
            k += 1usize
        }
    }
    }
}

fn kern_chroma(c: *Cols, g: *const Gp) {
    @nocheck {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let one = simd.splat[Vec[u8, 16]](1u8)
    let p1 = c.c[6usize]
    let p0 = c.c[7usize]
    let q0 = c.c[8usize]
    let q1 = c.c[9usize]
    let md = simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p1, p0), simd.abs_diff[Vec[u8, 16]](q1, q0))
    var m = md
    var fl = md
    if g.maxln >= 6i32 {
        let p2 = c.c[5usize]
        let q2 = c.c[10usize]
        var t = simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p2, p1), simd.abs_diff[Vec[u8, 16]](q2, q1))
        if g.mixed { t = t & g.w }
        m = simd.max[Vec[u8, 16]](m, t)
        fl = simd.max[Vec[u8, 16]](fl, simd.max[Vec[u8, 16]](simd.abs_diff[Vec[u8, 16]](p2, p0), simd.abs_diff[Vec[u8, 16]](q2, q0)))
    }
    let d1 = simd.abs_diff[Vec[u8, 16]](p1, q1)
    let d0 = simd.abs_diff[Vec[u8, 16]](p0, q0)
    let bs = simd.adds[Vec[u8, 16]](simd.adds[Vec[u8, 16]](d0, d0), simd.subs[Vec[u8, 16]](d1, simd.avg_u8[Vec[u8, 16]](d1, z)))
    let okv = simd.min[Vec[u8, 16]](simd.max[Vec[u8, 16]](simd.subs[Vec[u8, 16]](m, g.lim), simd.subs[Vec[u8, 16]](bs, g.blim)), one) -% one
    let hev = z -% simd.min[Vec[u8, 16]](simd.subs[Vec[u8, 16]](md, g.thr), one)
    if g.maxln < 6i32 {
        narrow(c, okv, hev)
        ret
    }
    var m6 = okv & (simd.min[Vec[u8, 16]](simd.subs[Vec[u8, 16]](fl, one), one) -% one)
    if g.mixed { m6 = m6 & g.w }
    if simd.movemask[Vec[u8, 16]](m6) == 0u64 {
        narrow(c, okv, hev)
        ret
    }
    var o6: Wo = zero
    w6(c, &o6)
    narrow(c, okv & ~m6, hev)
    var k = 0usize
    while k < 4usize {
        let b = c.c[6usize + k]
        c.c[6usize + k] = b ^ ((o6.v[k] ^ b) & m6)
        k += 1usize
    }
    }
}

// ---- group parameters

fn bm(b: bool) -> i32 {
    if b { ret 255i32 }
    ret 0i32
}

fn lane4(a: i32, b: i32, c: i32, d: i32) -> Vec[u8, 16] {
    ret mem.bitcast[Vec[u8, 16]](Vec[u32, 4]{ u32(a) * 16843009u32, u32(b) * 16843009u32, u32(c) * 16843009u32, u32(d) * 16843009u32 })
}

fn make_gp(g: *Gp, es: *const Eps, chroma: bool) {
    let e0 = es.e[0usize]
    let e1 = es.e[1usize]
    let e2 = es.e[2usize]
    let e3 = es.e[3usize]
    var mx = e0.ln
    if e1.ln > mx { mx = e1.ln }
    if e2.ln > mx { mx = e2.ln }
    if e3.ln > mx { mx = e3.ln }
    g.maxln = mx
    let same = e1.ln == e0.ln && e2.ln == e0.ln && e3.ln == e0.ln && e1.lim == e0.lim && e2.lim == e0.lim && e3.lim == e0.lim && e1.blim == e0.blim && e2.blim == e0.blim && e3.blim == e0.blim && e1.thr == e0.thr && e2.thr == e0.thr && e3.thr == e0.thr
    g.mixed = !same
    if same {
        g.lim = simd.splat[Vec[u8, 16]](u8(e0.lim))
        g.blim = simd.splat[Vec[u8, 16]](u8(e0.blim))
        g.thr = simd.splat[Vec[u8, 16]](u8(e0.thr))
    } else {
        g.lim = lane4(e0.lim, e1.lim, e2.lim, e3.lim)
        g.blim = lane4(e0.blim, e1.blim, e2.blim, e3.blim)
        g.thr = lane4(e0.thr, e1.thr, e2.thr, e3.thr)
        if chroma {
            g.w = lane4(bm(e0.ln == 6i32), bm(e1.ln == 6i32), bm(e2.ln == 6i32), bm(e3.ln == 6i32))
        } else {
            g.w = lane4(bm(e0.ln >= 8i32), bm(e1.ln >= 8i32), bm(e2.ln >= 8i32), bm(e3.ln >= 8i32))
            g.w2 = lane4(bm(e0.ln == 16i32), bm(e1.ln == 16i32), bm(e2.ln == 16i32), bm(e3.ln == 16i32))
        }
    }
}

// ---- pass 1 group: four units side by side, one row load per sample row across the edge

fn row_off(pos: usize, stride: usize, k: usize) -> usize {
    if k < 8usize { ret pos - (8usize - k) * stride }
    ret pos + (k - 8usize) * stride
}

fn group1(c: *const Ctx, w: *Work, pos: usize) -> bool {
    var i = 0usize
    while i < 4usize {
        let e = w.es.e[i]
        if e.ln > 0i32 && !reach_ok(c.buf.len, e.pos, c.stride, 1usize, 4i32, e.ln) { ret false }
        i += 1usize
    }
    make_gp(&w.g, &w.es, c.chroma)
    if w.g.maxln == 0i32 { ret true }
    var lo = 6usize
    var hi = 9usize
    var slo = 6usize
    var shi = 9usize
    if w.g.maxln >= 16i32 {
        lo = 1usize
        hi = 14usize
        slo = 2usize
        shi = 13usize
    } else if w.g.maxln >= 8i32 {
        lo = 4usize
        hi = 11usize
        slo = 5usize
        shi = 10usize
    } else if w.g.maxln >= 6i32 {
        lo = 5usize
        hi = 10usize
    }
    var k = lo
    while k <= hi {
        w.cols.c[k] = simd.load[Vec[u8, 16]](c.buf, row_off(pos, c.stride, k))
        k += 1usize
    }
    if c.chroma { kern_chroma(&w.cols, &w.g) } else { kern_luma(&w.cols, &w.g) }
    k = slo
    while k <= shi {
        simd.store[Vec[u8, 16]](c.buf, row_off(pos, c.stride, k), w.cols.c[k])
        k += 1usize
    }
    ret true
}

fn group0(c: *const Ctx, w: *Work, pos: usize) -> bool {
    var i = 0usize
    while i < 4usize {
        let e = w.es.e[i]
        if e.ln > 0i32 && !reach_ok(c.buf.len, e.pos, 1usize, c.stride, 4i32, e.ln) { ret false }
        i += 1usize
    }
    make_gp(&w.g, &w.es, c.chroma)
    if w.g.maxln == 0i32 { ret true }
    let r0 = simd.load[Vec[u8, 16]](c.buf, pos + 0usize * c.stride - 4usize)
    let r1 = simd.load[Vec[u8, 16]](c.buf, pos + 1usize * c.stride - 4usize)
    let r2 = simd.load[Vec[u8, 16]](c.buf, pos + 2usize * c.stride - 4usize)
    let r3 = simd.load[Vec[u8, 16]](c.buf, pos + 3usize * c.stride - 4usize)
    let r4 = simd.load[Vec[u8, 16]](c.buf, pos + 4usize * c.stride - 4usize)
    let r5 = simd.load[Vec[u8, 16]](c.buf, pos + 5usize * c.stride - 4usize)
    let r6 = simd.load[Vec[u8, 16]](c.buf, pos + 6usize * c.stride - 4usize)
    let r7 = simd.load[Vec[u8, 16]](c.buf, pos + 7usize * c.stride - 4usize)
    let r8 = simd.load[Vec[u8, 16]](c.buf, pos + 8usize * c.stride - 4usize)
    let r9 = simd.load[Vec[u8, 16]](c.buf, pos + 9usize * c.stride - 4usize)
    let r10 = simd.load[Vec[u8, 16]](c.buf, pos + 10usize * c.stride - 4usize)
    let r11 = simd.load[Vec[u8, 16]](c.buf, pos + 11usize * c.stride - 4usize)
    let r12 = simd.load[Vec[u8, 16]](c.buf, pos + 12usize * c.stride - 4usize)
    let r13 = simd.load[Vec[u8, 16]](c.buf, pos + 13usize * c.stride - 4usize)
    let r14 = simd.load[Vec[u8, 16]](c.buf, pos + 14usize * c.stride - 4usize)
    let r15 = simd.load[Vec[u8, 16]](c.buf, pos + 15usize * c.stride - 4usize)
    let aA0 = simd.unpack_lo[Vec[u8, 16]](r0, r1)
    let aA1 = simd.unpack_lo[Vec[u8, 16]](r2, r3)
    let aA2 = simd.unpack_lo[Vec[u8, 16]](r4, r5)
    let aA3 = simd.unpack_lo[Vec[u8, 16]](r6, r7)
    let aA4 = simd.unpack_lo[Vec[u8, 16]](r8, r9)
    let aA5 = simd.unpack_lo[Vec[u8, 16]](r10, r11)
    let aA6 = simd.unpack_lo[Vec[u8, 16]](r12, r13)
    let aA7 = simd.unpack_lo[Vec[u8, 16]](r14, r15)
    let bA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA0), mem.bitcast[Vec[u16, 8]](aA1)))
    let bA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA0), mem.bitcast[Vec[u16, 8]](aA1)))
    let bA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA2), mem.bitcast[Vec[u16, 8]](aA3)))
    let bA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA2), mem.bitcast[Vec[u16, 8]](aA3)))
    let bA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA4), mem.bitcast[Vec[u16, 8]](aA5)))
    let bA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA4), mem.bitcast[Vec[u16, 8]](aA5)))
    let bA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA6), mem.bitcast[Vec[u16, 8]](aA7)))
    let bA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA6), mem.bitcast[Vec[u16, 8]](aA7)))
    let dA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA0), mem.bitcast[Vec[u32, 4]](bA2)))
    let dA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA0), mem.bitcast[Vec[u32, 4]](bA2)))
    let dA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA1), mem.bitcast[Vec[u32, 4]](bA3)))
    let dA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA1), mem.bitcast[Vec[u32, 4]](bA3)))
    let dA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA4), mem.bitcast[Vec[u32, 4]](bA6)))
    let dA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA4), mem.bitcast[Vec[u32, 4]](bA6)))
    let dA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA5), mem.bitcast[Vec[u32, 4]](bA7)))
    let dA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA5), mem.bitcast[Vec[u32, 4]](bA7)))
    w.cols.c[4usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA0), mem.bitcast[Vec[u64, 2]](dA1)))
    w.cols.c[5usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA0), mem.bitcast[Vec[u64, 2]](dA1)))
    w.cols.c[6usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA2), mem.bitcast[Vec[u64, 2]](dA3)))
    w.cols.c[7usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA2), mem.bitcast[Vec[u64, 2]](dA3)))
    w.cols.c[8usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA4), mem.bitcast[Vec[u64, 2]](dA5)))
    w.cols.c[9usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA4), mem.bitcast[Vec[u64, 2]](dA5)))
    w.cols.c[10usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA6), mem.bitcast[Vec[u64, 2]](dA7)))
    w.cols.c[11usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA6), mem.bitcast[Vec[u64, 2]](dA7)))
    if c.chroma { kern_chroma(&w.cols, &w.g) } else { kern_luma(&w.cols, &w.g) }
    let uA0 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[4usize], w.cols.c[5usize])
    let uA1 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[4usize], w.cols.c[5usize])
    let uA2 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[6usize], w.cols.c[7usize])
    let uA3 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[6usize], w.cols.c[7usize])
    let uA4 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[8usize], w.cols.c[9usize])
    let uA5 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[8usize], w.cols.c[9usize])
    let uA6 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[10usize], w.cols.c[11usize])
    let uA7 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[10usize], w.cols.c[11usize])
    let vA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA0), mem.bitcast[Vec[u16, 8]](uA2)))
    let vA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA0), mem.bitcast[Vec[u16, 8]](uA2)))
    let vA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA4), mem.bitcast[Vec[u16, 8]](uA6)))
    let vA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA4), mem.bitcast[Vec[u16, 8]](uA6)))
    let vA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA1), mem.bitcast[Vec[u16, 8]](uA3)))
    let vA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA1), mem.bitcast[Vec[u16, 8]](uA3)))
    let vA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA5), mem.bitcast[Vec[u16, 8]](uA7)))
    let vA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA5), mem.bitcast[Vec[u16, 8]](uA7)))
    let fA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA0), mem.bitcast[Vec[u32, 4]](vA1)))
    let fA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA0), mem.bitcast[Vec[u32, 4]](vA1)))
    let fA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA2), mem.bitcast[Vec[u32, 4]](vA3)))
    let fA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA2), mem.bitcast[Vec[u32, 4]](vA3)))
    let fA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA4), mem.bitcast[Vec[u32, 4]](vA5)))
    let fA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA4), mem.bitcast[Vec[u32, 4]](vA5)))
    let fA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA6), mem.bitcast[Vec[u32, 4]](vA7)))
    let fA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA6), mem.bitcast[Vec[u32, 4]](vA7)))
    let lanes = Vec[u8, 16]{ 0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8 }
    let low8 = simd.cmp_lt[Vec[u8, 16]](lanes, simd.splat[Vec[u8, 16]](8u8))
    simd.store[Vec[u8, 16]](c.buf, pos + 0usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA0, r0))
    simd.store[Vec[u8, 16]](c.buf, pos + 1usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA0), mem.bitcast[Vec[u64, 2]](r1))))
    simd.store[Vec[u8, 16]](c.buf, pos + 2usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA1, r2))
    simd.store[Vec[u8, 16]](c.buf, pos + 3usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA1), mem.bitcast[Vec[u64, 2]](r3))))
    simd.store[Vec[u8, 16]](c.buf, pos + 4usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA2, r4))
    simd.store[Vec[u8, 16]](c.buf, pos + 5usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA2), mem.bitcast[Vec[u64, 2]](r5))))
    simd.store[Vec[u8, 16]](c.buf, pos + 6usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA3, r6))
    simd.store[Vec[u8, 16]](c.buf, pos + 7usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA3), mem.bitcast[Vec[u64, 2]](r7))))
    simd.store[Vec[u8, 16]](c.buf, pos + 8usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA4, r8))
    simd.store[Vec[u8, 16]](c.buf, pos + 9usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA4), mem.bitcast[Vec[u64, 2]](r9))))
    simd.store[Vec[u8, 16]](c.buf, pos + 10usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA5, r10))
    simd.store[Vec[u8, 16]](c.buf, pos + 11usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA5), mem.bitcast[Vec[u64, 2]](r11))))
    simd.store[Vec[u8, 16]](c.buf, pos + 12usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA6, r12))
    simd.store[Vec[u8, 16]](c.buf, pos + 13usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA6), mem.bitcast[Vec[u64, 2]](r13))))
    simd.store[Vec[u8, 16]](c.buf, pos + 14usize * c.stride - 4usize, simd.select[Vec[u8, 16]](low8, fA7, r14))
    simd.store[Vec[u8, 16]](c.buf, pos + 15usize * c.stride - 4usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA7), mem.bitcast[Vec[u64, 2]](r15))))
    ret true
}

fn group0w(c: *const Ctx, w: *Work, pos: usize) -> bool {
    var i = 0usize
    while i < 4usize {
        let e = w.es.e[i]
        if e.ln > 0i32 && !reach_ok(c.buf.len, e.pos, 1usize, c.stride, 4i32, e.ln) { ret false }
        i += 1usize
    }
    make_gp(&w.g, &w.es, c.chroma)
    if w.g.maxln == 0i32 { ret true }
    let r0 = simd.load[Vec[u8, 16]](c.buf, pos + 0usize * c.stride - 8usize)
    let r1 = simd.load[Vec[u8, 16]](c.buf, pos + 1usize * c.stride - 8usize)
    let r2 = simd.load[Vec[u8, 16]](c.buf, pos + 2usize * c.stride - 8usize)
    let r3 = simd.load[Vec[u8, 16]](c.buf, pos + 3usize * c.stride - 8usize)
    let r4 = simd.load[Vec[u8, 16]](c.buf, pos + 4usize * c.stride - 8usize)
    let r5 = simd.load[Vec[u8, 16]](c.buf, pos + 5usize * c.stride - 8usize)
    let r6 = simd.load[Vec[u8, 16]](c.buf, pos + 6usize * c.stride - 8usize)
    let r7 = simd.load[Vec[u8, 16]](c.buf, pos + 7usize * c.stride - 8usize)
    let r8 = simd.load[Vec[u8, 16]](c.buf, pos + 8usize * c.stride - 8usize)
    let r9 = simd.load[Vec[u8, 16]](c.buf, pos + 9usize * c.stride - 8usize)
    let r10 = simd.load[Vec[u8, 16]](c.buf, pos + 10usize * c.stride - 8usize)
    let r11 = simd.load[Vec[u8, 16]](c.buf, pos + 11usize * c.stride - 8usize)
    let r12 = simd.load[Vec[u8, 16]](c.buf, pos + 12usize * c.stride - 8usize)
    let r13 = simd.load[Vec[u8, 16]](c.buf, pos + 13usize * c.stride - 8usize)
    let r14 = simd.load[Vec[u8, 16]](c.buf, pos + 14usize * c.stride - 8usize)
    let r15 = simd.load[Vec[u8, 16]](c.buf, pos + 15usize * c.stride - 8usize)
    let aA0 = simd.unpack_lo[Vec[u8, 16]](r0, r1)
    let aA1 = simd.unpack_lo[Vec[u8, 16]](r2, r3)
    let aA2 = simd.unpack_lo[Vec[u8, 16]](r4, r5)
    let aA3 = simd.unpack_lo[Vec[u8, 16]](r6, r7)
    let aA4 = simd.unpack_lo[Vec[u8, 16]](r8, r9)
    let aA5 = simd.unpack_lo[Vec[u8, 16]](r10, r11)
    let aA6 = simd.unpack_lo[Vec[u8, 16]](r12, r13)
    let aA7 = simd.unpack_lo[Vec[u8, 16]](r14, r15)
    let bA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA0), mem.bitcast[Vec[u16, 8]](aA1)))
    let bA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA0), mem.bitcast[Vec[u16, 8]](aA1)))
    let bA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA2), mem.bitcast[Vec[u16, 8]](aA3)))
    let bA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA2), mem.bitcast[Vec[u16, 8]](aA3)))
    let bA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA4), mem.bitcast[Vec[u16, 8]](aA5)))
    let bA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA4), mem.bitcast[Vec[u16, 8]](aA5)))
    let bA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA6), mem.bitcast[Vec[u16, 8]](aA7)))
    let bA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aA6), mem.bitcast[Vec[u16, 8]](aA7)))
    let dA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA0), mem.bitcast[Vec[u32, 4]](bA2)))
    let dA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA0), mem.bitcast[Vec[u32, 4]](bA2)))
    let dA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA1), mem.bitcast[Vec[u32, 4]](bA3)))
    let dA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA1), mem.bitcast[Vec[u32, 4]](bA3)))
    let dA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA4), mem.bitcast[Vec[u32, 4]](bA6)))
    let dA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA4), mem.bitcast[Vec[u32, 4]](bA6)))
    let dA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA5), mem.bitcast[Vec[u32, 4]](bA7)))
    let dA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bA5), mem.bitcast[Vec[u32, 4]](bA7)))
    w.cols.c[0usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA0), mem.bitcast[Vec[u64, 2]](dA1)))
    w.cols.c[1usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA0), mem.bitcast[Vec[u64, 2]](dA1)))
    w.cols.c[2usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA2), mem.bitcast[Vec[u64, 2]](dA3)))
    w.cols.c[3usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA2), mem.bitcast[Vec[u64, 2]](dA3)))
    w.cols.c[4usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA4), mem.bitcast[Vec[u64, 2]](dA5)))
    w.cols.c[5usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA4), mem.bitcast[Vec[u64, 2]](dA5)))
    w.cols.c[6usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA6), mem.bitcast[Vec[u64, 2]](dA7)))
    w.cols.c[7usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dA6), mem.bitcast[Vec[u64, 2]](dA7)))
    let aB0 = simd.unpack_hi[Vec[u8, 16]](r0, r1)
    let aB1 = simd.unpack_hi[Vec[u8, 16]](r2, r3)
    let aB2 = simd.unpack_hi[Vec[u8, 16]](r4, r5)
    let aB3 = simd.unpack_hi[Vec[u8, 16]](r6, r7)
    let aB4 = simd.unpack_hi[Vec[u8, 16]](r8, r9)
    let aB5 = simd.unpack_hi[Vec[u8, 16]](r10, r11)
    let aB6 = simd.unpack_hi[Vec[u8, 16]](r12, r13)
    let aB7 = simd.unpack_hi[Vec[u8, 16]](r14, r15)
    let bB0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB0), mem.bitcast[Vec[u16, 8]](aB1)))
    let bB1 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB0), mem.bitcast[Vec[u16, 8]](aB1)))
    let bB2 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB2), mem.bitcast[Vec[u16, 8]](aB3)))
    let bB3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB2), mem.bitcast[Vec[u16, 8]](aB3)))
    let bB4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB4), mem.bitcast[Vec[u16, 8]](aB5)))
    let bB5 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB4), mem.bitcast[Vec[u16, 8]](aB5)))
    let bB6 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB6), mem.bitcast[Vec[u16, 8]](aB7)))
    let bB7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](aB6), mem.bitcast[Vec[u16, 8]](aB7)))
    let dB0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB0), mem.bitcast[Vec[u32, 4]](bB2)))
    let dB2 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB0), mem.bitcast[Vec[u32, 4]](bB2)))
    let dB4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB1), mem.bitcast[Vec[u32, 4]](bB3)))
    let dB6 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB1), mem.bitcast[Vec[u32, 4]](bB3)))
    let dB1 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB4), mem.bitcast[Vec[u32, 4]](bB6)))
    let dB3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB4), mem.bitcast[Vec[u32, 4]](bB6)))
    let dB5 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB5), mem.bitcast[Vec[u32, 4]](bB7)))
    let dB7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](bB5), mem.bitcast[Vec[u32, 4]](bB7)))
    w.cols.c[8usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB0), mem.bitcast[Vec[u64, 2]](dB1)))
    w.cols.c[9usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB0), mem.bitcast[Vec[u64, 2]](dB1)))
    w.cols.c[10usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB2), mem.bitcast[Vec[u64, 2]](dB3)))
    w.cols.c[11usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB2), mem.bitcast[Vec[u64, 2]](dB3)))
    w.cols.c[12usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB4), mem.bitcast[Vec[u64, 2]](dB5)))
    w.cols.c[13usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB4), mem.bitcast[Vec[u64, 2]](dB5)))
    w.cols.c[14usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB6), mem.bitcast[Vec[u64, 2]](dB7)))
    w.cols.c[15usize] = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](dB6), mem.bitcast[Vec[u64, 2]](dB7)))
    kern_luma(&w.cols, &w.g)
    let uA0 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[0usize], w.cols.c[1usize])
    let uA1 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[0usize], w.cols.c[1usize])
    let uA2 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[2usize], w.cols.c[3usize])
    let uA3 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[2usize], w.cols.c[3usize])
    let uA4 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[4usize], w.cols.c[5usize])
    let uA5 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[4usize], w.cols.c[5usize])
    let uA6 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[6usize], w.cols.c[7usize])
    let uA7 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[6usize], w.cols.c[7usize])
    let vA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA0), mem.bitcast[Vec[u16, 8]](uA2)))
    let vA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA0), mem.bitcast[Vec[u16, 8]](uA2)))
    let vA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA4), mem.bitcast[Vec[u16, 8]](uA6)))
    let vA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA4), mem.bitcast[Vec[u16, 8]](uA6)))
    let vA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA1), mem.bitcast[Vec[u16, 8]](uA3)))
    let vA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA1), mem.bitcast[Vec[u16, 8]](uA3)))
    let vA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA5), mem.bitcast[Vec[u16, 8]](uA7)))
    let vA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uA5), mem.bitcast[Vec[u16, 8]](uA7)))
    let fA0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA0), mem.bitcast[Vec[u32, 4]](vA1)))
    let fA1 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA0), mem.bitcast[Vec[u32, 4]](vA1)))
    let fA2 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA2), mem.bitcast[Vec[u32, 4]](vA3)))
    let fA3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA2), mem.bitcast[Vec[u32, 4]](vA3)))
    let fA4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA4), mem.bitcast[Vec[u32, 4]](vA5)))
    let fA5 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA4), mem.bitcast[Vec[u32, 4]](vA5)))
    let fA6 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA6), mem.bitcast[Vec[u32, 4]](vA7)))
    let fA7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vA6), mem.bitcast[Vec[u32, 4]](vA7)))
    let uB0 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[8usize], w.cols.c[9usize])
    let uB1 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[8usize], w.cols.c[9usize])
    let uB2 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[10usize], w.cols.c[11usize])
    let uB3 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[10usize], w.cols.c[11usize])
    let uB4 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[12usize], w.cols.c[13usize])
    let uB5 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[12usize], w.cols.c[13usize])
    let uB6 = simd.unpack_lo[Vec[u8, 16]](w.cols.c[14usize], w.cols.c[15usize])
    let uB7 = simd.unpack_hi[Vec[u8, 16]](w.cols.c[14usize], w.cols.c[15usize])
    let vB0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB0), mem.bitcast[Vec[u16, 8]](uB2)))
    let vB2 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB0), mem.bitcast[Vec[u16, 8]](uB2)))
    let vB1 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB4), mem.bitcast[Vec[u16, 8]](uB6)))
    let vB3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB4), mem.bitcast[Vec[u16, 8]](uB6)))
    let vB4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB1), mem.bitcast[Vec[u16, 8]](uB3)))
    let vB6 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB1), mem.bitcast[Vec[u16, 8]](uB3)))
    let vB5 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB5), mem.bitcast[Vec[u16, 8]](uB7)))
    let vB7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u16, 8]](mem.bitcast[Vec[u16, 8]](uB5), mem.bitcast[Vec[u16, 8]](uB7)))
    let fB0 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB0), mem.bitcast[Vec[u32, 4]](vB1)))
    let fB1 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB0), mem.bitcast[Vec[u32, 4]](vB1)))
    let fB2 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB2), mem.bitcast[Vec[u32, 4]](vB3)))
    let fB3 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB2), mem.bitcast[Vec[u32, 4]](vB3)))
    let fB4 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB4), mem.bitcast[Vec[u32, 4]](vB5)))
    let fB5 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB4), mem.bitcast[Vec[u32, 4]](vB5)))
    let fB6 = mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB6), mem.bitcast[Vec[u32, 4]](vB7)))
    let fB7 = mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u32, 4]](mem.bitcast[Vec[u32, 4]](vB6), mem.bitcast[Vec[u32, 4]](vB7)))
    simd.store[Vec[u8, 16]](c.buf, pos + 0usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA0), mem.bitcast[Vec[u64, 2]](fB0))))
    simd.store[Vec[u8, 16]](c.buf, pos + 1usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA0), mem.bitcast[Vec[u64, 2]](fB0))))
    simd.store[Vec[u8, 16]](c.buf, pos + 2usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA1), mem.bitcast[Vec[u64, 2]](fB1))))
    simd.store[Vec[u8, 16]](c.buf, pos + 3usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA1), mem.bitcast[Vec[u64, 2]](fB1))))
    simd.store[Vec[u8, 16]](c.buf, pos + 4usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA2), mem.bitcast[Vec[u64, 2]](fB2))))
    simd.store[Vec[u8, 16]](c.buf, pos + 5usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA2), mem.bitcast[Vec[u64, 2]](fB2))))
    simd.store[Vec[u8, 16]](c.buf, pos + 6usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA3), mem.bitcast[Vec[u64, 2]](fB3))))
    simd.store[Vec[u8, 16]](c.buf, pos + 7usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA3), mem.bitcast[Vec[u64, 2]](fB3))))
    simd.store[Vec[u8, 16]](c.buf, pos + 8usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA4), mem.bitcast[Vec[u64, 2]](fB4))))
    simd.store[Vec[u8, 16]](c.buf, pos + 9usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA4), mem.bitcast[Vec[u64, 2]](fB4))))
    simd.store[Vec[u8, 16]](c.buf, pos + 10usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA5), mem.bitcast[Vec[u64, 2]](fB5))))
    simd.store[Vec[u8, 16]](c.buf, pos + 11usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA5), mem.bitcast[Vec[u64, 2]](fB5))))
    simd.store[Vec[u8, 16]](c.buf, pos + 12usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA6), mem.bitcast[Vec[u64, 2]](fB6))))
    simd.store[Vec[u8, 16]](c.buf, pos + 13usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA6), mem.bitcast[Vec[u64, 2]](fB6))))
    simd.store[Vec[u8, 16]](c.buf, pos + 14usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_lo[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA7), mem.bitcast[Vec[u64, 2]](fB7))))
    simd.store[Vec[u8, 16]](c.buf, pos + 15usize * c.stride - 8usize, mem.bitcast[Vec[u8, 16]](simd.unpack_hi[Vec[u64, 2]](mem.bitcast[Vec[u64, 2]](fA7), mem.bitcast[Vec[u64, 2]](fB7))))
    ret true
}

fn tx_sizes_of(f: *const LoopFilterFrame, plane: u32) -> []u8 {
    if plane == 0u32 { ret f.tx_sizes0 }
    if plane == 1u32 { ret f.tx_sizes1 }
    ret f.tx_sizes2
}

// The edge loop filter process (7.14.2) for one 4x4 luma position, up to the sample filtering: which
// length, strength and where. The frame and pass invariants are in c and t.
fn edge_ep(p: *const LoopFilterParams, f: *const LoopFilterFrame, t: *const Tabs, c: *const Ctx, row0: usize, col0: usize, r: *Ep) {
    @nocheck {
    r.ln = 0i32
    r.lim = 0i32
    r.blim = 0i32
    r.thr = 0i32
    let row = row0 | usize(c.sub_y)
    let col = col0 | usize(c.sub_x)
    let mi = row * f.mi_cols + col
    let ti = (row >> c.sub_y) * c.mc + (col >> c.sub_x)
    let xp = (col0 * 4usize) >> c.sub_x
    let yp = (row0 * 4usize) >> c.sub_y
    r.pos = yp * c.stride + xp
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
    r.lim = t.lim[usize(lvl)]
    r.blim = t.blim[usize(lvl)]
    r.thr = t.thr[usize(lvl)]
    r.ln = fs
    if fs == 8i32 && c.chroma { r.ln = 6i32 }
    }
}

// The sample filter of one unit; false when its samples are out of reach.
fn edge_apply(c: *const Ctx, e: *const Ep) -> bool {
    if e.ln == 0i32 { ret true }
    var step = 1usize
    var adv = c.stride
    if c.pass == 1u32 {
        step = c.stride
        adv = 1usize
    }
    if !reach_ok(c.buf.len, e.pos, step, adv, 4i32, e.ln) { ret false }
    filt(c.buf, e.pos, step, adv, 4i32, e.lim, e.blim, e.thr, e.ln)
    ret true
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
    var l = 0i32
    while l < 64i32 {
        let st = strength(p.sharpness, l)
        t.lim[usize(l)] = st.limit
        t.blim[usize(l)] = st.blimit
        t.thr[usize(l)] = st.thresh
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

// Per plane and pass: everything the range workers share, read-only. It borrows the frame's sample
// plane and tx-size array. rows4 / cols4 count the plane's 4x4 rows / columns that a pass covers.
// `valid` is false when the frame, plane or pass is rejected; the range functions then answer Invalid.
type Prepared = struct {
    t: Tabs,
    c: Ctx,
    valid: bool,
    row_end: usize,
    col_end: usize,
    rows4: usize,
    cols4: usize
}

fn frame_ok(f: *const LoopFilterFrame) -> bool {
    let mis = f.mi_rows * f.mi_cols
    if f.mi_rows == 0usize || f.mi_cols == 0usize { ret false }
    if f.bit_depth != 8u32 || f.num_planes < 1u32 || f.num_planes > 3u32 { ret false }
    ret f.mi_sizes.len >= mis && f.skips.len >= mis && f.ref_frames.len >= mis && f.y_modes.len >= mis && f.segment_ids.len >= mis && f.delta_lfs.len >= mis * 4usize
}

fn plane_ok(f: *const LoopFilterFrame, plane: u32) -> bool {
    ret plane < f.num_planes && check_dims(f, plane) && tx_sizes_of(f, plane).len >= f.mi_rows * f.mi_cols
}

// Whether `loop_filter` filters this plane: luma always, a chroma plane only with a non-zero level.
fn plane_enabled(p: *const LoopFilterParams, plane: u32) -> bool {
    ret plane == 0u32 || p.levels[usize(1u32 + plane)] != 0i32
}

// The strength tables and invariants of one plane and pass (0 = vertical edges, 1 = horizontal edges).
fn loop_filter_plane_prepare(p: *const LoopFilterParams, f: *const LoopFilterFrame, plane: u32, pass: u32) -> Prepared {
    var pr: Prepared = zero
    if !frame_ok(f) || !plane_ok(f, plane) || pass > 1u32 { ret pr }
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
    var maxfs = 16i32
    if plane > 0u32 { maxfs = 8i32 }
    pr.c = Ctx { plane: plane, pass: pass, sub_x: sub_x, sub_y: sub_y, mc: f.mi_cols, stride: stride, pw: (f.mi_cols * 4usize) >> sub_x, which: delta_index(p, plane, pass), maxfs: maxfs, chroma: plane > 0u32, buf: buf, txs: tx_sizes_of(f, plane) }
    fill_tabs(p, f, &pr.t, &pr.c)
    pr.row_end = (f.frame_height + 3usize) >> 2u32
    pr.col_end = (f.frame_width + 3usize) >> 2u32
    if pr.row_end > f.mi_rows { pr.row_end = f.mi_rows }
    if pr.col_end > f.mi_cols { pr.col_end = f.mi_cols }
    pr.rows4 = (pr.row_end + (1usize << sub_y) - 1usize) >> sub_y
    pr.cols4 = (pr.col_end + (1usize << sub_x) - 1usize) >> sub_x
    if pr.rows4 > 0usize && (((pr.rows4 - 1usize) << sub_y) | usize(sub_y)) >= f.mi_rows { ret pr }
    if pr.cols4 > 0usize && (((pr.cols4 - 1usize) << sub_x) | usize(sub_x)) >= f.mi_cols { ret pr }
    pr.valid = true
    ret pr
}

fn apply_all(c: *const Ctx, es: *const Eps) -> bool {
    var i = 0usize
    while i < 4usize {
        if !edge_apply(c, &es.e[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn max_ln(es: *const Eps) -> i32 {
    var m = es.e[0usize].ln
    var i = 1usize
    while i < 4usize {
        if es.e[i].ln > m { m = es.e[i].ln }
        i += 1usize
    }
    ret m
}

// Pass 0 over the plane's 4x4 rows [row4_from, row4_to) (clamped to pr.rows4). An edge of a 4x4 unit at
// plane row r4 reads and writes only the four sample rows 4*r4 .. 4*r4+3 (7.14.6 changes at most 6 samples
// each side along the row and reads 7), so workers on disjoint row ranges touch disjoint samples and
// the rows' results do not depend on the order of the ranges. Within a range the edges go left to right as
// in the whole-plane pass. Invalid: pr is not valid, is a pass 1 table, or a sample is out of reach.
fn filter_pass_rows(p: *const LoopFilterParams, f: *const LoopFilterFrame, pr: *const Prepared, row4_from: usize, row4_to: usize) -> err {
    if !pr.valid || pr.c.pass != 0u32 { ret Invalid }
    var hi = row4_to
    if hi > pr.rows4 { hi = pr.rows4 }
    let col_step = 1usize << pr.c.sub_x
    var e1: Ep = zero
    var wk: Work = zero
    var r4 = row4_from
    while r4 + 4usize <= hi {
        var col = col_step
        while col < pr.col_end {
            let cc = col >> pr.c.sub_x
            let xp = cc * 4usize
            var sv = 0usize
            var i = 0usize
            while i < 4usize {
                let tdim = pr.t.td[usize(pr.c.txs[(r4 + i) * pr.c.mc + cc])]
                if (xp & usize(tdim - 1i32)) == 0usize { sv = sv | (1usize << u32(i)) }
                i += 1usize
            }
            if sv != 0usize {
                i = 0usize
                while i < 4usize {
                    if ((sv >> u32(i)) & 1usize) != 0usize {
                        edge_ep(p, f, &pr.t, &pr.c, (r4 + i) << pr.c.sub_y, col, &wk.es.e[i])
                    } else {
                        wk.es.e[i].ln = 0i32
                        wk.es.e[i].lim = 0i32
                        wk.es.e[i].blim = 0i32
                        wk.es.e[i].thr = 0i32
                        wk.es.e[i].pos = (r4 + i) * 4usize * pr.c.stride + xp
                    }
                    i += 1usize
                }
                let ln = max_ln(&wk.es)
                if ln > 0i32 {
                    if ln >= 16i32 && xp >= 8usize && xp + 8usize <= pr.c.pw {
                        if !group0w(&pr.c, &wk, wk.es.e[0usize].pos) { ret Invalid }
                    } else if ln < 16i32 && xp + 12usize <= pr.c.pw {
                        if !group0(&pr.c, &wk, wk.es.e[0usize].pos) { ret Invalid }
                    } else {
                        if !apply_all(&pr.c, &wk.es) { ret Invalid }
                    }
                }
            }
            col += col_step
        }
        r4 += 4usize
    }
    while r4 < hi {
        let row = r4 << pr.c.sub_y
        let tb = r4 * pr.c.mc
        var col = col_step
        while col < pr.col_end {
            let cc = col >> pr.c.sub_x
            let tdim = pr.t.td[usize(pr.c.txs[tb + cc])]
            if ((cc * 4usize) & usize(tdim - 1i32)) == 0usize {
                edge_ep(p, f, &pr.t, &pr.c, row, col, &e1)
                if !edge_apply(&pr.c, &e1) { ret Invalid }
            }
            col += col_step
        }
        r4 += 1usize
    }
    ret ok
}

// Pass 1 over the plane's 4x4 columns [col4_from, col4_to) (clamped to pr.cols4); the mirror image of
// filter_pass_rows: an edge reads and writes only the four sample columns 4*c4 .. 4*c4+3. Pass 1 of a plane
// may start only after pass 0 has finished on the whole plane. Within a range the edges go top to bottom.
fn filter_pass_cols(p: *const LoopFilterParams, f: *const LoopFilterFrame, pr: *const Prepared, col4_from: usize, col4_to: usize) -> err {
    if !pr.valid || pr.c.pass != 1u32 { ret Invalid }
    var hi = col4_to
    if hi > pr.cols4 { hi = pr.cols4 }
    let row_step = 1usize << pr.c.sub_y
    var e1: Ep = zero
    var wk: Work = zero
    var row = row_step
    while row < pr.row_end {
        let tb = (row >> pr.c.sub_y) * pr.c.mc
        let yp = (row * 4usize) >> pr.c.sub_y
        var c4 = col4_from
        while c4 + 4usize <= hi {
            var sv = 0usize
            var i = 0usize
            while i < 4usize {
                let tdim = pr.t.td[usize(pr.c.txs[tb + c4 + i])]
                if (yp & usize(tdim - 1i32)) == 0usize { sv = sv | (1usize << u32(i)) }
                i += 1usize
            }
            if sv != 0usize {
                i = 0usize
                while i < 4usize {
                    if ((sv >> u32(i)) & 1usize) != 0usize {
                        edge_ep(p, f, &pr.t, &pr.c, row, (c4 + i) << pr.c.sub_x, &wk.es.e[i])
                    } else {
                        wk.es.e[i].ln = 0i32
                        wk.es.e[i].lim = 0i32
                        wk.es.e[i].blim = 0i32
                        wk.es.e[i].thr = 0i32
                        wk.es.e[i].pos = yp * pr.c.stride + (c4 + i) * 4usize
                    }
                    i += 1usize
                }
                if max_ln(&wk.es) > 0i32 {
                    if c4 * 4usize + 16usize <= pr.c.pw {
                        if !group1(&pr.c, &wk, wk.es.e[0usize].pos) { ret Invalid }
                    } else {
                        if !apply_all(&pr.c, &wk.es) { ret Invalid }
                    }
                }
            }
            c4 += 4usize
        }
        while c4 < hi {
            edge_ep(p, f, &pr.t, &pr.c, row, c4 << pr.c.sub_x, &e1)
            if !edge_apply(&pr.c, &e1) { ret Invalid }
            c4 += 1usize
        }
        row += row_step
    }
    ret ok
}

// Filters the whole frame in place (7.14.1). Invalid: the sample planes or MI arrays are too small,
// or bit_depth is not 8.
fn loop_filter(p: *const LoopFilterParams, f: *const LoopFilterFrame) -> err {
    if !frame_ok(f) { ret Invalid }
    var plane = 0u32
    while plane < f.num_planes {
        if !plane_ok(f, plane) { ret Invalid }
        plane += 1u32
    }
    plane = 0u32
    while plane < f.num_planes {
        if plane_enabled(p, plane) {
            let p0 = loop_filter_plane_prepare(p, f, plane, 0u32)
            try filter_pass_rows(p, f, &p0, 0usize, p0.rows4)
            let p1 = loop_filter_plane_prepare(p, f, plane, 1u32)
            try filter_pass_cols(p, f, &p1, 0usize, p1.cols4)
        }
        plane += 1u32
    }
    ret ok
}
