// AV1 motion vector prediction: the motion field estimation process (spec 7.9) and the motion vector prediction
// processes (spec 7.10: find_mv_stack and has_overlappable_candidates). Out of scope: find_warp_samples.
//
// Everything is a pure function over slices the caller fills. The only allocation is `new_mvp`.
//
// MI (4x4 luma) arrays of the current frame, row major with stride `mi_cols`, entry (r, c) at r * mi_cols + c:
//   mi_sizes[r,c]   MiSizes, a BLOCK_* value 0..21 in the order of the spec
//   y_modes[r,c]    YModes (NEARESTMV = 14 .. NEW_NEWMV = 25)
//   is_inters[r,c]  IsInters, 0 or 1
//   ref_frames      RefFrames[r][c][list] at (r * mi_cols + c) * 2 + list; INTRA_FRAME 0, NONE -1. A position of
//                   the frame that is not decoded yet must hold -2 (UNWRITTEN) in list 0: the caller resets the
//                   whole array to -2 at the start of each frame (that is the spec's "has been written for this
//                   frame" test of the scan point process, i.e. the top-right availability).
//   mvs             Mvs[r][c][list][comp] at ((r * mi_cols + c) * 2 + list) * 2 + comp; comp 0 = row, 1 = col
// Reference frame numbers are the spec's: INTRA_FRAME 0, LAST 1, LAST2 2, LAST3 3, GOLDEN 4, BWDREF 5, ALTREF2 6,
// ALTREF 7. Arrays indexed by reference frame have 8 entries (entry 0 unused except where said).
//
// Per frame arrays: order_hints[8] (OrderHints), sign_bias[8] (RefFrameSignBias), gm_type[8] (GmType),
// gm_params[8 * 6] (gm_params[ref][i] at ref * 6 + i). motion_field is MotionFieldMvs[ref][y8][x8][comp] at
// ((ref * (mi_rows >> 1) + y8) * (mi_cols >> 1) + x8) * 2 + comp (ref 0 is allocated and unused); entries are i16
// and -32768 marks an invalid vector.
//
//   new_mvp(a)                          the output buffers
//   find_mv_stack(f, b, p)              7.10.2; fills p
//   has_overlappable_candidates(f, b, avail_u, avail_l)
//   motion_field_estimation(f, out)     7.9; out is MotionFieldMvs, 8 * (mi_rows >> 1) * (mi_cols >> 1) * 2 entries
//
// Outputs of find_mv_stack in `Mvp`: num_found (NumMvFound), new_mv_count, stack[idx * 4 + list * 2 + comp]
// (RefStackMv), weights[idx], drl_ctx[idx] (DrlCtxStack), global_mvs[list * 2 + comp] (GlobalMvs), new_mv_ctx,
// ref_mv_ctx, zero_mv_ctx. For single prediction the stack holds list 0 only, and as in the spec entries
// num_found .. 1 are filled with the global motion vector without being counted.

use e.mem
use e.fmt.av1_pool

const LAST_FRAME: i32 = 1i32
const LAST2_FRAME: i32 = 2i32
const GOLDEN_FRAME: i32 = 4i32
const BWDREF_FRAME: i32 = 5i32
const ALTREF2_FRAME: i32 = 6i32
const ALTREF_FRAME: i32 = 7i32
const UNWRITTEN: i32 = -2i32
const KEY_FRAME: i32 = 0i32
const INTRA_ONLY_FRAME: i32 = 2i32

const MAX_STACK: i32 = 8i32
const REF_CAT_LEVEL: i32 = 640i32
const MV_BORDER: i32 = 128i32
const MAX_FRAME_DISTANCE: i32 = 31i32
const INVALID_MV: i32 = -32768i32

const MODE_GLOBALMV: i32 = 16i32
const MODE_GLOBAL_GLOBALMV: i32 = 24i32
const GM_TRANSLATION: i32 = 1i32

// scratch layout (indices into Mvp.scratch)
const S_ID_MVS: usize = 0usize
const S_DIFF_MVS: usize = 8usize
const S_ID_COUNT: usize = 16usize
const S_DIFF_COUNT: usize = 18usize
const S_COMBINED: usize = 20usize

// One reference slot as saved by the reference frame update process: the MI grid of that frame (stride mi_cols)
// with SavedMvs (row, col per entry, i16) and SavedRefFrames, its frame type (KEY_FRAME 0, INTER 1, INTRA_ONLY 2,
// SWITCH 3) and SavedOrderHints[8].
type RefSlot = struct {
    mi_rows: i32,
    mi_cols: i32,
    frame_type: i32,
    mvs: []const i16,
    ref_frames: []const i8,
    order_hints: []const i32,
}

type Frame = struct {
    mi_rows: i32,
    mi_cols: i32,
    tile_row_start: i32,
    tile_row_end: i32,
    tile_col_start: i32,
    tile_col_end: i32,
    mi_sizes: []const u8,
    y_modes: []const u8,
    is_inters: []const u8,
    ref_frames: []const i8,
    mvs: []const i16,
    order_hint: i32,
    order_hint_bits: u32,
    order_hints: []const i32,
    sign_bias: []const i32,
    gm_type: []const i32,
    gm_params: []const i32,
    force_integer_mv: bool,
    allow_high_precision_mv: bool,
    use_ref_frame_mvs: bool,
    motion_field: []const i16,
    ref_frame_idx: []const i32,
    slots: []const RefSlot,
}

// ref0 / ref1 are RefFrame[0] / RefFrame[1]; ref1 is read only when compound
type Block = struct { mi_row: i32, mi_col: i32, mi_size: i32, ref0: i32, ref1: i32, compound: bool }

type Mvp = struct {
    num_found: i32,
    new_mv_count: i32,
    new_mv_ctx: i32,
    ref_mv_ctx: i32,
    zero_mv_ctx: i32,
    found_match: bool,
    stack: []i32,
    weights: []i32,
    drl_ctx: []i32,
    global_mvs: []i32,
    scratch: []i32,
}

fn new_mvp(a: *mem.Arena) -> (Mvp, err) {
    var p: Mvp = zero
    let (st, e1) = mem.alloc[i32](a, 32usize)
    if e1 != ok { ret (p, e1) }
    let (wt, e2) = mem.alloc[i32](a, 16usize)
    if e2 != ok { ret (p, e2) }
    let (dr, e3) = mem.alloc[i32](a, 16usize)
    if e3 != ok { ret (p, e3) }
    let (gl, e4) = mem.alloc[i32](a, 4usize)
    if e4 != ok { ret (p, e4) }
    let (sc, e5) = mem.alloc[i32](a, 32usize)
    if e5 != ok { ret (p, e5) }
    p.stack = st
    p.weights = wt
    p.drl_ctx = dr
    p.global_mvs = gl
    p.scratch = sc
    ret (p, ok)
}

fn num4_wide(s: i32) -> i32 {
    let t = "\x01\x01\x02\x02\x02\x04\x04\x04\x08\x08\x08\x10\x10\x10\x20\x20\x01\x04\x02\x08\x04\x10"
    ret i32(t[usize(s)])
}

fn num4_high(s: i32) -> i32 {
    let t = "\x01\x02\x01\x02\x04\x02\x04\x08\x04\x08\x10\x08\x10\x20\x10\x20\x04\x01\x08\x02\x10\x04"
    ret i32(t[usize(s)])
}

fn div_mult(i: i32) -> i32 {
    let t = "\x00\x00\x40\x00\x20\x00\x15\x55\x10\x00\x0c\xcc\x0a\xaa\x09\x24\x08\x00\x07\x1c\x06\x66\x05\xd1\x05\x55\x04\xec\x04\x92\x04\x44\x04\x00\x03\xc3\x03\x8e\x03\x5e\x03\x33\x03\x0c\x02\xe8\x02\xc8\x02\xaa\x02\x8f\x02\x76\x02\x5e\x02\x49\x02\x34\x02\x22\x02\x10"
    ret (i32(t[usize(i) * 2usize]) << 8u32) | i32(t[usize(i) * 2usize + 1usize])
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

fn clip3(lo: i32, hi: i32, v: i32) -> i32 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

fn round2_signed_64(x: i64, n: u32) -> i64 {
    if x >= 0i64 { ret (x + (1i64 << (n - 1u32))) >> n }
    ret 0i64 - ((0i64 - x + (1i64 << (n - 1u32))) >> n)
}

fn relative_dist(f: *Frame, a: i32, b: i32) -> i32 {
    if f.order_hint_bits == 0u32 { ret 0i32 }
    let diff = a - b
    let m = 1i32 << (f.order_hint_bits - 1u32)
    ret (diff & (m - 1i32)) - (diff & m)
}

fn is_inside(f: *Frame, r: i32, c: i32) -> bool {
    ret c >= f.tile_col_start && c < f.tile_col_end && r >= f.tile_row_start && r < f.tile_row_end
}

fn lower_prec(f: *Frame, v: i32) -> i32 {
    if f.allow_high_precision_mv { ret v }
    if f.force_integer_mv {
        let a_int = (iabs(v) + 3i32) >> 3u32
        if v > 0i32 { ret a_int << 3u32 }
        ret 0i32 - (a_int << 3u32)
    }
    if (v & 1i32) != 0i32 {
        if v > 0i32 { ret v - 1i32 }
        ret v + 1i32
    }
    ret v
}

fn setup_global_mv(f: *Frame, b: Block, lst: usize, p: *Mvp) {
    var ref_frame = b.ref0
    if lst == 1usize { ref_frame = b.ref1 }
    var mv_row = 0i32
    var mv_col = 0i32
    if ref_frame > 0i32 {
        let typ = f.gm_type[usize(ref_frame)]
        let g = usize(ref_frame) * 6usize
        if typ == GM_TRANSLATION {
            mv_row = f.gm_params[g] >> 13u32
            mv_col = f.gm_params[g + 1usize] >> 13u32
        } else if typ > GM_TRANSLATION {
            let bw = num4_wide(b.mi_size) * 4i32
            let bh = num4_high(b.mi_size) * 4i32
            let x = i64(b.mi_col * 4i32 + bw / 2i32 - 1i32)
            let y = i64(b.mi_row * 4i32 + bh / 2i32 - 1i32)
            let xc = i64(f.gm_params[g + 2usize] - 65536i32) * x + i64(f.gm_params[g + 3usize]) * y + i64(f.gm_params[g])
            let yc = i64(f.gm_params[g + 4usize]) * x + i64(f.gm_params[g + 5usize] - 65536i32) * y + i64(f.gm_params[g + 1usize])
            if f.allow_high_precision_mv {
                mv_row = i32(round2_signed_64(yc, 13u32))
                mv_col = i32(round2_signed_64(xc, 13u32))
            } else {
                mv_row = i32(round2_signed_64(yc, 14u32)) * 2i32
                mv_col = i32(round2_signed_64(xc, 14u32)) * 2i32
            }
        }
    }
    p.global_mvs[lst * 2usize] = lower_prec(f, mv_row)
    p.global_mvs[lst * 2usize + 1usize] = lower_prec(f, mv_col)
}

fn has_newmv(mode: i32) -> bool {
    ret mode == 17i32 || mode == 25i32 || mode == 22i32 || mode == 23i32 || mode == 20i32 || mode == 21i32
}

fn push_single(p: *Mvp, mv_row: i32, mv_col: i32, weight: i32) {
    var i = 0i32
    while i < p.num_found {
        if p.stack[usize(i) * 4usize] == mv_row && p.stack[usize(i) * 4usize + 1usize] == mv_col { break }
        i += 1i32
    }
    if i < p.num_found {
        p.weights[usize(i)] += weight
    } else if p.num_found < MAX_STACK {
        p.stack[usize(p.num_found) * 4usize] = mv_row
        p.stack[usize(p.num_found) * 4usize + 1usize] = mv_col
        p.weights[usize(p.num_found)] = weight
        p.num_found += 1i32
    }
}

fn push_pair(p: *Mvp, r0: i32, c0: i32, r1: i32, c1: i32, weight: i32) {
    var i = 0i32
    while i < p.num_found {
        let o = usize(i) * 4usize
        if p.stack[o] == r0 && p.stack[o + 1usize] == c0 && p.stack[o + 2usize] == r1 && p.stack[o + 3usize] == c1 { break }
        i += 1i32
    }
    if i < p.num_found {
        p.weights[usize(i)] += weight
    } else if p.num_found < MAX_STACK {
        let o = usize(p.num_found) * 4usize
        p.stack[o] = r0
        p.stack[o + 1usize] = c0
        p.stack[o + 2usize] = r1
        p.stack[o + 3usize] = c1
        p.weights[usize(p.num_found)] = weight
        p.num_found += 1i32
    }
}

fn search_stack(f: *Frame, b: Block, p: *Mvp, mi: usize, cand_list: usize, weight: i32) {
    let cand_mode = i32(f.y_modes[mi])
    let cand_size = i32(f.mi_sizes[mi])
    let large = imin(num4_wide(cand_size), num4_high(cand_size)) >= 2i32
    var cand_row = 0i32
    var cand_col = 0i32
    if (cand_mode == MODE_GLOBALMV || cand_mode == MODE_GLOBAL_GLOBALMV) && f.gm_type[usize(b.ref0)] > GM_TRANSLATION && large {
        cand_row = p.global_mvs[0usize]
        cand_col = p.global_mvs[1usize]
    } else {
        cand_row = i32(f.mvs[(mi * 2usize + cand_list) * 2usize])
        cand_col = i32(f.mvs[(mi * 2usize + cand_list) * 2usize + 1usize])
    }
    cand_row = lower_prec(f, cand_row)
    cand_col = lower_prec(f, cand_col)
    if has_newmv(cand_mode) { p.new_mv_count += 1i32 }
    p.found_match = true
    push_single(p, cand_row, cand_col, weight)
}

fn compound_search_stack(f: *Frame, b: Block, p: *Mvp, mi: usize, weight: i32) {
    let cand_mode = i32(f.y_modes[mi])
    var r0 = i32(f.mvs[mi * 4usize])
    var c0 = i32(f.mvs[mi * 4usize + 1usize])
    var r1 = i32(f.mvs[mi * 4usize + 2usize])
    var c1 = i32(f.mvs[mi * 4usize + 3usize])
    if cand_mode == MODE_GLOBAL_GLOBALMV {
        if f.gm_type[usize(b.ref0)] > GM_TRANSLATION {
            r0 = p.global_mvs[0usize]
            c0 = p.global_mvs[1usize]
        }
        if f.gm_type[usize(b.ref1)] > GM_TRANSLATION {
            r1 = p.global_mvs[2usize]
            c1 = p.global_mvs[3usize]
        }
    }
    r0 = lower_prec(f, r0)
    c0 = lower_prec(f, c0)
    r1 = lower_prec(f, r1)
    c1 = lower_prec(f, c1)
    p.found_match = true
    push_pair(p, r0, c0, r1, c1, weight)
    if has_newmv(cand_mode) { p.new_mv_count += 1i32 }
}

fn add_ref_mv_candidate(f: *Frame, b: Block, p: *Mvp, mv_row: i32, mv_col: i32, weight: i32) {
    let mi = usize(mv_row * f.mi_cols + mv_col)
    if f.is_inters[mi] == 0u8 { ret }
    if !b.compound {
        var cl = 0usize
        while cl < 2usize {
            if i32(f.ref_frames[mi * 2usize + cl]) == b.ref0 { search_stack(f, b, p, mi, cl, weight) }
            cl += 1usize
        }
    } else if i32(f.ref_frames[mi * 2usize]) == b.ref0 && i32(f.ref_frames[mi * 2usize + 1usize]) == b.ref1 {
        compound_search_stack(f, b, p, mi, weight)
    }
}

fn scan_row(f: *Frame, b: Block, p: *Mvp, delta_row_in: i32) {
    let bw4 = num4_wide(b.mi_size)
    let end4 = imin(imin(bw4, f.mi_cols - b.mi_col), 16i32)
    var delta_row = delta_row_in
    var delta_col = 0i32
    let use_step16 = bw4 >= 16i32
    if iabs(delta_row) > 1i32 {
        delta_row += b.mi_row & 1i32
        delta_col = 1i32 - (b.mi_col & 1i32)
    }
    var i = 0i32
    while i < end4 {
        let mv_row = b.mi_row + delta_row
        let mv_col = b.mi_col + delta_col + i
        if !is_inside(f, mv_row, mv_col) { break }
        var span = imin(bw4, num4_wide(i32(f.mi_sizes[usize(mv_row * f.mi_cols + mv_col)])))
        if iabs(delta_row) > 1i32 { span = imax(2i32, span) }
        if use_step16 { span = imax(4i32, span) }
        add_ref_mv_candidate(f, b, p, mv_row, mv_col, span * 2i32)
        i += span
    }
}

fn scan_col(f: *Frame, b: Block, p: *Mvp, delta_col_in: i32) {
    let bh4 = num4_high(b.mi_size)
    let end4 = imin(imin(bh4, f.mi_rows - b.mi_row), 16i32)
    var delta_row = 0i32
    var delta_col = delta_col_in
    let use_step16 = bh4 >= 16i32
    if iabs(delta_col) > 1i32 {
        delta_row = 1i32 - (b.mi_row & 1i32)
        delta_col += b.mi_col & 1i32
    }
    var i = 0i32
    while i < end4 {
        let mv_row = b.mi_row + delta_row + i
        let mv_col = b.mi_col + delta_col
        if !is_inside(f, mv_row, mv_col) { break }
        var span = imin(bh4, num4_high(i32(f.mi_sizes[usize(mv_row * f.mi_cols + mv_col)])))
        if iabs(delta_col) > 1i32 { span = imax(2i32, span) }
        if use_step16 { span = imax(4i32, span) }
        add_ref_mv_candidate(f, b, p, mv_row, mv_col, span * 2i32)
        i += span
    }
}

fn scan_point(f: *Frame, b: Block, p: *Mvp, delta_row: i32, delta_col: i32) {
    let mv_row = b.mi_row + delta_row
    let mv_col = b.mi_col + delta_col
    if is_inside(f, mv_row, mv_col) && i32(f.ref_frames[usize(mv_row * f.mi_cols + mv_col) * 2usize]) != UNWRITTEN {
        add_ref_mv_candidate(f, b, p, mv_row, mv_col, 4i32)
    }
}

fn add_tpl_ref_mv(f: *Frame, b: Block, p: *Mvp, delta_row: i32, delta_col: i32) {
    let mv_row = (b.mi_row + delta_row) | 1i32
    let mv_col = (b.mi_col + delta_col) | 1i32
    if !is_inside(f, mv_row, mv_col) { ret }
    let x8 = mv_col >> 1u32
    let y8 = mv_row >> 1u32
    let w8 = f.mi_cols >> 1u32
    let h8 = f.mi_rows >> 1u32
    let at_origin = delta_row == 0i32 && delta_col == 0i32
    if at_origin { p.zero_mv_ctx = 1i32 }
    let o0 = ((usize(b.ref0) * usize(h8) + usize(y8)) * usize(w8) + usize(x8)) * 2usize
    if i32(f.motion_field[o0]) == INVALID_MV { ret }
    var r0 = i32(f.motion_field[o0])
    var c0 = i32(f.motion_field[o0 + 1usize])
    if !b.compound {
        r0 = lower_prec(f, r0)
        c0 = lower_prec(f, c0)
        if at_origin {
            if iabs(r0 - p.global_mvs[0usize]) >= 16i32 || iabs(c0 - p.global_mvs[1usize]) >= 16i32 {
                p.zero_mv_ctx = 1i32
            } else {
                p.zero_mv_ctx = 0i32
            }
        }
        push_single(p, r0, c0, 2i32)
    } else {
        let o1 = ((usize(b.ref1) * usize(h8) + usize(y8)) * usize(w8) + usize(x8)) * 2usize
        if i32(f.motion_field[o1]) == INVALID_MV { ret }
        var r1 = i32(f.motion_field[o1])
        var c1 = i32(f.motion_field[o1 + 1usize])
        r0 = lower_prec(f, r0)
        c0 = lower_prec(f, c0)
        r1 = lower_prec(f, r1)
        c1 = lower_prec(f, c1)
        if at_origin {
            if iabs(r0 - p.global_mvs[0usize]) >= 16i32 || iabs(c0 - p.global_mvs[1usize]) >= 16i32 || iabs(r1 - p.global_mvs[2usize]) >= 16i32 || iabs(c1 - p.global_mvs[3usize]) >= 16i32 {
                p.zero_mv_ctx = 1i32
            } else {
                p.zero_mv_ctx = 0i32
            }
        }
        push_pair(p, r0, c0, r1, c1, 2i32)
    }
}

fn check_sb_border(b: Block, delta_row: i32, delta_col: i32) -> bool {
    let r = (b.mi_row & 15i32) + delta_row
    let c = (b.mi_col & 15i32) + delta_col
    ret r >= 0i32 && r < 16i32 && c >= 0i32 && c < 16i32
}

fn temporal_scan(f: *Frame, b: Block, p: *Mvp) {
    let bw4 = num4_wide(b.mi_size)
    let bh4 = num4_high(b.mi_size)
    var step_w4 = 2i32
    if bw4 >= 16i32 { step_w4 = 4i32 }
    var step_h4 = 2i32
    if bh4 >= 16i32 { step_h4 = 4i32 }
    var delta_row = 0i32
    while delta_row < imin(bh4, 16i32) {
        var delta_col = 0i32
        while delta_col < imin(bw4, 16i32) {
            add_tpl_ref_mv(f, b, p, delta_row, delta_col)
            delta_col += step_w4
        }
        delta_row += step_h4
    }
    if bh4 >= 2i32 && bh4 < 16i32 && bw4 >= 2i32 && bw4 < 16i32 {
        if check_sb_border(b, bh4, -2i32) { add_tpl_ref_mv(f, b, p, bh4, -2i32) }
        if check_sb_border(b, bh4, bw4) { add_tpl_ref_mv(f, b, p, bh4, bw4) }
        if check_sb_border(b, bh4 - 2i32, bw4) { add_tpl_ref_mv(f, b, p, bh4 - 2i32, bw4) }
    }
}

fn sort_stack(p: *Mvp, start: i32, end_in: i32, compound: bool) {
    var end = end_in
    while end > start {
        var new_end = start
        var idx = start + 1i32
        while idx < end {
            let i = usize(idx)
            if p.weights[i - 1usize] < p.weights[i] {
                let tw = p.weights[i - 1usize]
                p.weights[i - 1usize] = p.weights[i]
                p.weights[i] = tw
                var k = 0usize
                var n = 2usize
                if compound { n = 4usize }
                while k < n {
                    let tm = p.stack[(i - 1usize) * 4usize + k]
                    p.stack[(i - 1usize) * 4usize + k] = p.stack[i * 4usize + k]
                    p.stack[i * 4usize + k] = tm
                    k += 1usize
                }
                new_end = idx
            }
            idx += 1i32
        }
        end = new_end
    }
}

fn add_extra_mv_candidate(f: *Frame, b: Block, p: *Mvp, mi: usize) {
    var cand_list = 0usize
    while cand_list < 2usize {
        let cand_ref = i32(f.ref_frames[mi * 2usize + cand_list])
        if cand_ref > 0i32 {
            if b.compound {
                var lst = 0usize
                while lst < 2usize {
                    var cand_row = i32(f.mvs[(mi * 2usize + cand_list) * 2usize])
                    var cand_col = i32(f.mvs[(mi * 2usize + cand_list) * 2usize + 1usize])
                    var list_ref = b.ref0
                    if lst == 1usize { list_ref = b.ref1 }
                    if cand_ref == list_ref && p.scratch[S_ID_COUNT + lst] < 2i32 {
                        let o = S_ID_MVS + lst * 4usize + usize(p.scratch[S_ID_COUNT + lst]) * 2usize
                        p.scratch[o] = cand_row
                        p.scratch[o + 1usize] = cand_col
                        p.scratch[S_ID_COUNT + lst] += 1i32
                    } else if p.scratch[S_DIFF_COUNT + lst] < 2i32 {
                        if f.sign_bias[usize(cand_ref)] != f.sign_bias[usize(list_ref)] {
                            cand_row = 0i32 - cand_row
                            cand_col = 0i32 - cand_col
                        }
                        let o = S_DIFF_MVS + lst * 4usize + usize(p.scratch[S_DIFF_COUNT + lst]) * 2usize
                        p.scratch[o] = cand_row
                        p.scratch[o + 1usize] = cand_col
                        p.scratch[S_DIFF_COUNT + lst] += 1i32
                    }
                    lst += 1usize
                }
            } else {
                var cand_row = i32(f.mvs[(mi * 2usize + cand_list) * 2usize])
                var cand_col = i32(f.mvs[(mi * 2usize + cand_list) * 2usize + 1usize])
                if f.sign_bias[usize(cand_ref)] != f.sign_bias[usize(b.ref0)] {
                    cand_row = 0i32 - cand_row
                    cand_col = 0i32 - cand_col
                }
                var idx = 0i32
                while idx < p.num_found {
                    if cand_row == p.stack[usize(idx) * 4usize] && cand_col == p.stack[usize(idx) * 4usize + 1usize] { break }
                    idx += 1i32
                }
                if idx == p.num_found {
                    p.stack[usize(idx) * 4usize] = cand_row
                    p.stack[usize(idx) * 4usize + 1usize] = cand_col
                    p.weights[usize(idx)] = 2i32
                    p.num_found += 1i32
                }
            }
        }
        cand_list += 1usize
    }
}

fn extra_search(f: *Frame, b: Block, p: *Mvp) {
    var k = 0usize
    while k < 4usize {
        p.scratch[S_ID_COUNT + k] = 0i32
        k += 1usize
    }
    var w4 = imin(16i32, num4_wide(b.mi_size))
    var h4 = imin(16i32, num4_high(b.mi_size))
    w4 = imin(w4, f.mi_cols - b.mi_col)
    h4 = imin(h4, f.mi_rows - b.mi_row)
    let num4x4 = imin(w4, h4)
    var pass = 0i32
    while pass < 2i32 {
        var idx = 0i32
        while idx < num4x4 && p.num_found < 2i32 {
            var mv_row = b.mi_row + idx
            var mv_col = b.mi_col - 1i32
            if pass == 0i32 {
                mv_row = b.mi_row - 1i32
                mv_col = b.mi_col + idx
            }
            if !is_inside(f, mv_row, mv_col) { break }
            let mi = usize(mv_row * f.mi_cols + mv_col)
            add_extra_mv_candidate(f, b, p, mi)
            if pass == 0i32 {
                idx += num4_wide(i32(f.mi_sizes[mi]))
            } else {
                idx += num4_high(i32(f.mi_sizes[mi]))
            }
        }
        pass += 1i32
    }
    if b.compound {
        var lst = 0usize
        while lst < 2usize {
            var comp_count = 0usize
            var i = 0i32
            while i < p.scratch[S_ID_COUNT + lst] {
                let src = S_ID_MVS + lst * 4usize + usize(i) * 2usize
                let dst = S_COMBINED + comp_count * 4usize + lst * 2usize
                p.scratch[dst] = p.scratch[src]
                p.scratch[dst + 1usize] = p.scratch[src + 1usize]
                comp_count += 1usize
                i += 1i32
            }
            i = 0i32
            while i < p.scratch[S_DIFF_COUNT + lst] && comp_count < 2usize {
                let src = S_DIFF_MVS + lst * 4usize + usize(i) * 2usize
                let dst = S_COMBINED + comp_count * 4usize + lst * 2usize
                p.scratch[dst] = p.scratch[src]
                p.scratch[dst + 1usize] = p.scratch[src + 1usize]
                comp_count += 1usize
                i += 1i32
            }
            while comp_count < 2usize {
                let dst = S_COMBINED + comp_count * 4usize + lst * 2usize
                p.scratch[dst] = p.global_mvs[lst * 2usize]
                p.scratch[dst + 1usize] = p.global_mvs[lst * 2usize + 1usize]
                comp_count += 1usize
            }
            lst += 1usize
        }
        let c0 = S_COMBINED
        let c1 = S_COMBINED + 4usize
        if p.num_found == 1i32 {
            var pick = c0
            if p.scratch[c0] == p.stack[0usize] && p.scratch[c0 + 1usize] == p.stack[1usize] && p.scratch[c0 + 2usize] == p.stack[2usize] && p.scratch[c0 + 3usize] == p.stack[3usize] {
                pick = c1
            }
            let o = usize(p.num_found) * 4usize
            k = 0usize
            while k < 4usize {
                p.stack[o + k] = p.scratch[pick + k]
                k += 1usize
            }
            p.weights[usize(p.num_found)] = 2i32
            p.num_found += 1i32
        } else {
            var idx = 0usize
            while idx < 2usize {
                let o = usize(p.num_found) * 4usize
                k = 0usize
                while k < 4usize {
                    p.stack[o + k] = p.scratch[S_COMBINED + idx * 4usize + k]
                    k += 1usize
                }
                p.weights[usize(p.num_found)] = 2i32
                p.num_found += 1i32
                idx += 1usize
            }
        }
    } else {
        var idx = p.num_found
        while idx < 2i32 {
            p.stack[usize(idx) * 4usize] = p.global_mvs[0usize]
            p.stack[usize(idx) * 4usize + 1usize] = p.global_mvs[1usize]
            idx += 1i32
        }
    }
}

fn context_and_clamping(f: *Frame, b: Block, p: *Mvp, num_new: i32, close_matches: i32, total_matches: i32) {
    let bw4 = num4_wide(b.mi_size)
    let bh4 = num4_high(b.mi_size)
    var idx = 0i32
    while idx < p.num_found {
        var z = 0i32
        if idx + 1i32 < p.num_found {
            let w0 = p.weights[usize(idx)]
            let w1 = p.weights[usize(idx) + 1usize]
            if w0 >= REF_CAT_LEVEL {
                if w1 < REF_CAT_LEVEL { z = 1i32 }
            } else {
                z = 2i32
            }
        }
        p.drl_ctx[usize(idx)] = z
        idx += 1i32
    }
    let top = 0i32 - (b.mi_row * 4i32 * 8i32)
    let bottom = (f.mi_rows - bh4 - b.mi_row) * 4i32 * 8i32
    let left = 0i32 - (b.mi_col * 4i32 * 8i32)
    let right = (f.mi_cols - bw4 - b.mi_col) * 4i32 * 8i32
    let row_border = MV_BORDER + bh4 * 4i32 * 8i32
    let col_border = MV_BORDER + bw4 * 4i32 * 8i32
    var num_lists = 1usize
    if b.compound { num_lists = 2usize }
    var lst = 0usize
    while lst < num_lists {
        idx = 0i32
        while idx < p.num_found {
            let o = usize(idx) * 4usize + lst * 2usize
            p.stack[o] = clip3(top - row_border, bottom + row_border, p.stack[o])
            p.stack[o + 1usize] = clip3(left - col_border, right + col_border, p.stack[o + 1usize])
            idx += 1i32
        }
        lst += 1usize
    }
    if close_matches == 0i32 {
        p.new_mv_ctx = imin(total_matches, 1i32)
        p.ref_mv_ctx = total_matches
    } else if close_matches == 1i32 {
        p.new_mv_ctx = 3i32 - imin(num_new, 1i32)
        p.ref_mv_ctx = 2i32 + total_matches
    } else {
        p.new_mv_ctx = 5i32 - imin(num_new, 1i32)
        p.ref_mv_ctx = 5i32
    }
}

fn find_mv_stack(f: *Frame, b: Block, p: *Mvp) {
    let bw4 = num4_wide(b.mi_size)
    let bh4 = num4_high(b.mi_size)
    p.num_found = 0i32
    p.new_mv_count = 0i32
    var k = 0usize
    while k < 4usize {
        p.global_mvs[k] = 0i32
        k += 1usize
    }
    setup_global_mv(f, b, 0usize, p)
    if b.compound { setup_global_mv(f, b, 1usize, p) }
    p.found_match = false
    scan_row(f, b, p, -1i32)
    var found_above = p.found_match
    p.found_match = false
    scan_col(f, b, p, -1i32)
    var found_left = p.found_match
    p.found_match = false
    if imax(bw4, bh4) <= 16i32 { scan_point(f, b, p, -1i32, bw4) }
    if p.found_match { found_above = true }
    var close_matches = 0i32
    if found_above { close_matches += 1i32 }
    if found_left { close_matches += 1i32 }
    let num_nearest = p.num_found
    let num_new = p.new_mv_count
    k = 0usize
    while k < usize(num_nearest) {
        p.weights[k] += REF_CAT_LEVEL
        k += 1usize
    }
    p.zero_mv_ctx = 0i32
    if f.use_ref_frame_mvs { temporal_scan(f, b, p) }
    scan_point(f, b, p, -1i32, -1i32)
    if p.found_match { found_above = true }
    p.found_match = false
    scan_row(f, b, p, -3i32)
    if p.found_match { found_above = true }
    p.found_match = false
    scan_col(f, b, p, -3i32)
    if p.found_match { found_left = true }
    p.found_match = false
    if bh4 > 1i32 { scan_row(f, b, p, -5i32) }
    if p.found_match { found_above = true }
    p.found_match = false
    if bw4 > 1i32 { scan_col(f, b, p, -5i32) }
    if p.found_match { found_left = true }
    var total_matches = 0i32
    if found_above { total_matches += 1i32 }
    if found_left { total_matches += 1i32 }
    sort_stack(p, 0i32, num_nearest, b.compound)
    sort_stack(p, num_nearest, p.num_found, b.compound)
    if p.num_found < 2i32 { extra_search(f, b, p) }
    context_and_clamping(f, b, p, num_new, close_matches, total_matches)
}

fn has_overlappable_candidates(f: *Frame, b: Block, avail_u: bool, avail_l: bool) -> bool {
    if avail_u {
        let w4 = num4_wide(b.mi_size)
        var x4 = b.mi_col
        while x4 < imin(f.mi_cols, b.mi_col + w4) {
            if f.ref_frames[usize((b.mi_row - 1i32) * f.mi_cols + (x4 | 1i32)) * 2usize] > 0i8 { ret true }
            x4 += 2i32
        }
    }
    if avail_l {
        let h4 = num4_high(b.mi_size)
        var y4 = b.mi_row
        while y4 < imin(f.mi_rows, b.mi_row + h4) {
            if f.ref_frames[usize((y4 | 1i32) * f.mi_cols + b.mi_col - 1i32) * 2usize] > 0i8 { ret true }
            y4 += 2i32
        }
    }
    ret false
}

fn mv_projection(v: i32, numerator: i32, denominator: i32) -> i32 {
    let den = imin(MAX_FRAME_DISTANCE, denominator)
    let num = clip3(0i32 - MAX_FRAME_DISTANCE, MAX_FRAME_DISTANCE, numerator)
    let scaled = round2_signed_64(i64(v) * i64(num) * i64(div_mult(den)), 14u32)
    ret clip3(-16383i32, 16383i32, i32(scaled))
}

// project() of the spec; answers the new position, or -1 when the position is not valid
fn project(v8_in: i32, delta: i32, dst_sign: i32, max8: i32, max_off8: i32) -> i32 {
    let base8 = (v8_in >> 3u32) << 3u32
    var offset8 = 0i32
    if delta >= 0i32 {
        offset8 = delta >> 6u32
    } else {
        offset8 = 0i32 - ((0i32 - delta) >> 6u32)
    }
    let v8 = v8_in + dst_sign * offset8
    if v8 < 0i32 || v8 >= max8 || v8 < base8 - max_off8 || v8 >= base8 + 8i32 + max_off8 { ret -1i32 }
    ret v8
}

// Whether the projection from reference `src` happens at all (the slot is a decoded inter frame of the same size).
fn projection_valid(f: *Frame, src: i32) -> bool {
    let slot = f.slots[usize(f.ref_frame_idx[usize(src - LAST_FRAME)])]
    ret !(slot.mi_rows != f.mi_rows || slot.mi_cols != f.mi_cols || slot.frame_type == INTRA_ONLY_FRAME || slot.frame_type == KEY_FRAME)
}

// The rows y0 up to y1 of the sources of one projection. A source row only lands in its own band of 8 rows (project() keeps v8
// inside base8 .. base8 + 8 for rows), so bands that start at a multiple of 8 are independent of each other.
fn projection_rows(f: *Frame, out: []i16, src: i32, dst_sign: i32, y0: i32, y1: i32) {
    let src_idx = usize(f.ref_frame_idx[usize(src - LAST_FRAME)])
    let slot = f.slots[src_idx]
    let w8 = f.mi_cols >> 1u32
    let h8 = f.mi_rows >> 1u32
    var y8 = y0
    while y8 < y1 {
        var x8 = 0i32
        while x8 < w8 {
            let mi = usize((2i32 * y8 + 1i32) * slot.mi_cols + 2i32 * x8 + 1i32)
            let src_ref = i32(slot.ref_frames[mi])
            if src_ref > 0i32 {
                let ref_to_cur = relative_dist(f, f.order_hints[usize(src)], f.order_hint)
                let ref_offset = relative_dist(f, f.order_hints[usize(src)], slot.order_hints[usize(src_ref)])
                if iabs(ref_to_cur) <= MAX_FRAME_DISTANCE && iabs(ref_offset) <= MAX_FRAME_DISTANCE && ref_offset > 0i32 {
                    let mv_row = i32(slot.mvs[mi * 2usize])
                    let mv_col = i32(slot.mvs[mi * 2usize + 1usize])
                    let proj_row = mv_projection(mv_row, ref_to_cur * dst_sign, ref_offset)
                    let proj_col = mv_projection(mv_col, ref_to_cur * dst_sign, ref_offset)
                    let pos_y8 = project(y8, proj_row, dst_sign, h8, 0i32)
                    let pos_x8 = project(x8, proj_col, dst_sign, w8, 8i32)
                    if pos_y8 >= 0i32 && pos_x8 >= 0i32 {
                        var dst = LAST_FRAME
                        while dst <= ALTREF_FRAME {
                            let ref_to_dst = relative_dist(f, f.order_hint, f.order_hints[usize(dst)])
                            let o = ((usize(dst) * usize(h8) + usize(pos_y8)) * usize(w8) + usize(pos_x8)) * 2usize
                            out[o] = i16(mv_projection(mv_row, ref_to_dst, ref_offset))
                            out[o + 1usize] = i16(mv_projection(mv_col, ref_to_dst, ref_offset))
                            dst += 1i32
                        }
                    }
                }
            }
            x8 += 1i32
        }
        y8 += 1i32
    }
}

// Reads f.mi_rows / mi_cols, order_hint(_bits), order_hints, ref_frame_idx[7] (ref_frame_idx[i] is the slot of
// LAST_FRAME + i) and f.slots[8]. RefSlot.mvs / ref_frames hold ONE vector and reference per MI position
// (SavedMvs / SavedRefFrames): mvs at (r * mi_cols + c) * 2 + comp, ref_frames at r * mi_cols + c.
type MfJob = struct { f: *Frame, out: []i16, n: usize, srcs: [5]i32, signs: [5]i32 }

// The projections to make, in the spec's order (a later one overwrites an earlier one), decided from the headers alone.
fn mf_plan(f: *Frame, out: []i16) -> MfJob {
    var j: MfJob = zero
    j.f = f
    j.out = out
    let last_idx = usize(f.ref_frame_idx[0usize])
    let cur_gold_order_hint = f.order_hints[usize(GOLDEN_FRAME)]
    let last_alt_order_hint = f.slots[last_idx].order_hints[usize(ALTREF_FRAME)]
    if last_alt_order_hint != cur_gold_order_hint && projection_valid(f, LAST_FRAME) {
        j.srcs[j.n] = LAST_FRAME
        j.signs[j.n] = -1i32
        j.n += 1usize
    }
    var ref_stamp = 1i32
    if relative_dist(f, f.order_hints[usize(BWDREF_FRAME)], f.order_hint) > 0i32 && projection_valid(f, BWDREF_FRAME) {
        j.srcs[j.n] = BWDREF_FRAME
        j.signs[j.n] = 1i32
        j.n += 1usize
        ref_stamp -= 1i32
    }
    if relative_dist(f, f.order_hints[usize(ALTREF2_FRAME)], f.order_hint) > 0i32 && projection_valid(f, ALTREF2_FRAME) {
        j.srcs[j.n] = ALTREF2_FRAME
        j.signs[j.n] = 1i32
        j.n += 1usize
        ref_stamp -= 1i32
    }
    if relative_dist(f, f.order_hints[usize(ALTREF_FRAME)], f.order_hint) > 0i32 && ref_stamp >= 0i32 && projection_valid(f, ALTREF_FRAME) {
        j.srcs[j.n] = ALTREF_FRAME
        j.signs[j.n] = 1i32
        j.n += 1usize
        ref_stamp -= 1i32
    }
    if ref_stamp >= 0i32 && projection_valid(f, LAST2_FRAME) {
        j.srcs[j.n] = LAST2_FRAME
        j.signs[j.n] = -1i32
        j.n += 1usize
    }
    ret j
}

// One band of 8 rows of 8x8 units: its part of the output is cleared, then every projection is made into it.
fn mf_band(ctx: *void, band: usize) {
    let j = mem.cast[*MfJob](ctx)
    let h8 = j.f.mi_rows >> 1u32
    let w8 = j.f.mi_cols >> 1u32
    let y0 = i32(band) * 8i32
    let y1 = imin(y0 + 8i32, h8)
    var dst = 0usize
    while dst < 8usize {
        var i = ((dst * usize(h8) + usize(y0)) * usize(w8)) * 2usize
        let end = ((dst * usize(h8) + usize(y1)) * usize(w8)) * 2usize
        while i < end {
            j.out[i] = i16(INVALID_MV)
            i += 1usize
        }
        dst += 1usize
    }
    var k = 0usize
    while k < j.n {
        projection_rows(j.f, j.out, j.srcs[k], j.signs[k], y0, y1)
        k += 1usize
    }
}

fn motion_field_estimation(f: *Frame, out: []i16) {
    var j = mf_plan(f, out)
    let bands = usize((f.mi_rows >> 1u32) + 7i32) >> 3u32
    var band = 0usize
    while band < bands {
        mf_band(mem.cast[*void](&j), band)
        band += 1usize
    }
}

// The same, the bands shared between the workers of `pool` and the caller. The pool must not be in use by anything else.
fn motion_field_estimation_pool(f: *Frame, out: []i16, pool: *av1_pool.Pool) {
    var j = mf_plan(f, out)
    let bands = usize((f.mi_rows >> 1u32) + 7i32) >> 3u32
    av1_pool.run(pool, bands, mf_band, mem.cast[*void](&j))
}
