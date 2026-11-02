// AV1 block mode info: the syntax of intra_frame_mode_info and inter_frame_mode_info with the CDF context derivation of
// the specification. Syntax this decoder does not carry (palette, intra block copy, masked compound, inter-intra, local
// warp) returns Unsupported.

use e.fmt.av1
use e.fmt.av1_sym
use e.fmt.av1_tables
use e.fmt.av1_cdf as CDF
use e.fmt.av1_dec as D
use e.fmt.av1_mvp as MV
use e.fmt.av1_warp as WP

error Unsupported

fn dc(d: *D.Dec) -> *D.Dec { ret d }

// ------------------------------------------------------------------ segmentation, skip, cdef, deltas

fn seg_feature_active(d: *D.Dec, feature: usize) -> bool {
    let h = &d.st.h
    ret h.segmentation_enabled && h.feature_enabled[d.b.segment_id * 8usize + feature] != 0i32
}

fn neg_deinterleave(diff: i32, ref: i32, mx: i32) -> i32 {
    if ref == 0i32 { ret diff }
    if ref >= mx - 1i32 { ret mx - diff - 1i32 }
    if 2i32 * ref < mx {
        if diff <= 2i32 * ref {
            if (diff & 1i32) != 0i32 { ret ref + ((diff + 1i32) >> 1u32) }
            ret ref - (diff >> 1u32)
        }
        ret diff
    }
    if diff <= 2i32 * (mx - ref - 1i32) {
        if (diff & 1i32) != 0i32 { ret ref + ((diff + 1i32) >> 1u32) }
        ret ref - (diff >> 1u32)
    }
    ret mx - (diff + 1i32)
}

fn read_segment_id(d: *D.Dec) -> usize {
    let b = &d.b
    var prev_ul = 0i32 - 1i32
    var prev_u = 0i32 - 1i32
    var prev_l = 0i32 - 1i32
    if b.avail_u && b.avail_l { prev_ul = i32(d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col - 1i32)].segment_id) }
    if b.avail_u { prev_u = i32(d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)].segment_id) }
    if b.avail_l { prev_l = i32(d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)].segment_id) }
    var pred = prev_l
    if prev_u == 0i32 - 1i32 {
        if prev_l == 0i32 - 1i32 { pred = 0i32 }
    } else if prev_l == 0i32 - 1i32 {
        pred = prev_u
    } else if prev_ul == prev_u {
        pred = prev_u
    }
    if b.skip { ret usize(pred) }
    var ctx = 0usize
    if prev_ul < 0i32 {
        ctx = 0usize
    } else if prev_ul == prev_u && prev_ul == prev_l {
        ctx = 2usize
    } else if prev_ul == prev_u || prev_ul == prev_l || prev_u == prev_l {
        ctx = 1usize
    }
    let coded = i32(D.sym(d, CDF.C_SEGMENTID, 9usize, ctx, 8usize))
    let v = neg_deinterleave(coded, pred, d.st.h.last_active_seg_id + 1i32)
    ret usize(D.clip3(0i32, d.st.h.last_active_seg_id, v))
}

fn intra_segment_id(d: *D.Dec) -> err {
    let h = &d.st.h
    if h.segmentation_enabled {
        d.b.segment_id = read_segment_id(d)
    } else {
        d.b.segment_id = 0usize
    }
    d.b.lossless = h.lossless_array[d.b.segment_id]
    ret ok
}

// inter frames: only a segmentation map coded in every frame (no temporal prediction) is carried
fn inter_segment_id(d: *D.Dec, pre_skip: bool) -> err {
    let h = &d.st.h
    if !h.segmentation_enabled {
        d.b.segment_id = 0usize
        ret ok
    }
    if !h.segmentation_update_map || h.segmentation_temporal_update { ret Unsupported }
    if pre_skip && !h.seg_id_pre_skip {
        d.b.segment_id = 0usize
        ret ok
    }
    d.b.segment_id = read_segment_id(d)
    ret ok
}

fn read_skip(d: *D.Dec) {
    let b = &d.b
    if d.st.h.seg_id_pre_skip && seg_feature_active(d, D.SEG_LVL_SKIP) {
        b.skip = true
        ret
    }
    var ctx = 0usize
    if b.avail_u { ctx += usize(d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)].skip) }
    if b.avail_l { ctx += usize(d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)].skip) }
    b.skip = D.sym(d, CDF.C_SKIP, 3usize, ctx, 2usize) == 1usize
}

fn read_skip_mode(d: *D.Dec) {
    let b = &d.b
    let h = &d.st.h
    b.skip_mode = false
    if seg_feature_active(d, D.SEG_LVL_SKIP) || seg_feature_active(d, av1.SEG_LVL_REF_FRAME) || seg_feature_active(d, D.SEG_LVL_GLOBALMV) { ret }
    if !h.skip_mode_present || D.block_w(d, b.mi_size) < 8i32 || D.block_h(d, b.mi_size) < 8i32 { ret }
    var ctx = 0usize
    if b.avail_u { ctx += usize(d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)].skip_mode) }
    if b.avail_l { ctx += usize(d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)].skip_mode) }
    b.skip_mode = D.sym(d, CDF.C_SKIPMODE, 3usize, ctx, 2usize) == 1usize
}

fn cdef_slot(d: *D.Dec, r: i32, c: i32) -> usize {
    ret usize((r >> 4u32) * d.cdef_stride + (c >> 4u32))
}

fn read_cdef(d: *D.Dec) {
    let b = &d.b
    let h = &d.st.h
    if b.skip || h.coded_lossless || !d.st.seq.enable_cdef || h.allow_intrabc { ret }
    let r = b.mi_row & (0i32 - 16i32)
    let c = b.mi_col & (0i32 - 16i32)
    let slot = cdef_slot(d, r, c)
    if d.cdef_idx[slot] == i8(0i32 - 1i32) {
        let v = i8(D.lit(d, u32(h.cdef_bits)))
        d.cdef_idx[slot] = v
        var i = r
        while i < r + b.bh4 {
            var j = c
            while j < c + b.bw4 {
                if i < d.mi_rows && j < d.mi_cols { d.cdef_idx[cdef_slot(d, i, j)] = v }
                j += 16i32
            }
            i += 16i32
        }
    }
}

fn read_delta_qindex(d: *D.Dec) {
    let b = &d.b
    var sb = D.BLOCK_64X64
    if d.st.seq.use_128x128_superblock { sb = D.BLOCK_128X128 }
    if b.mi_size == sb && b.skip { ret }
    if !d.read_deltas { ret }
    var delta_q_abs = i32(D.sym(d, CDF.C_DELTAQ, 5usize, 0usize, 4usize))
    if delta_q_abs == 3i32 {
        let rem_bits = i32(D.lit(d, 3u32)) + 1i32
        let abs_bits = i32(D.lit(d, u32(rem_bits)))
        delta_q_abs = abs_bits + (1i32 << u32(rem_bits)) + 1i32
    }
    if delta_q_abs != 0i32 {
        let sign = D.lit(d, 1u32)
        var reduced = delta_q_abs
        if sign == 1u32 { reduced = 0i32 - delta_q_abs }
        d.current_q_index = D.clip3(1i32, 255i32, d.current_q_index + (reduced << u32(d.st.h.delta_q_res)))
    }
}

fn read_delta_lf(d: *D.Dec) {
    let b = &d.b
    let h = &d.st.h
    var sb = D.BLOCK_64X64
    if d.st.seq.use_128x128_superblock { sb = D.BLOCK_128X128 }
    if b.mi_size == sb && b.skip { ret }
    if !d.read_deltas || !h.delta_lf_present { ret }
    var count = 1usize
    if h.delta_lf_multi {
        count = 4usize
        if d.st.seq.num_planes == 1i32 { count = 2usize }
    }
    var i = 0usize
    while i < count {
        var delta_lf_abs = 0i32
        if h.delta_lf_multi {
            delta_lf_abs = i32(av1_sym.read_symbol(&d.sd, d.ctx[CDF.C_DELTALFMULTI + i * CDF.L_DELTALFMULTI..CDF.C_DELTALFMULTI + (i + 1usize) * CDF.L_DELTALFMULTI], 4usize))
        } else {
            delta_lf_abs = i32(D.sym(d, CDF.C_DELTALF, 5usize, 0usize, 4usize))
        }
        var abs_value = delta_lf_abs
        if delta_lf_abs == 3i32 {
            let n = i32(D.lit(d, 3u32)) + 1i32
            let bits = i32(D.lit(d, u32(n)))
            abs_value = bits + (1i32 << u32(n)) + 1i32
        }
        if abs_value != 0i32 {
            let sign = D.lit(d, 1u32)
            var reduced = abs_value
            if sign == 1u32 { reduced = 0i32 - abs_value }
            d.delta_lf[i] = D.clip3(0i32 - 63i32, 63i32, d.delta_lf[i] + (reduced << u32(h.delta_lf_res)))
        }
        i += 1usize
    }
}

// ------------------------------------------------------------------ transform size

fn above_tx_width(d: *D.Dec, row: i32, col: i32) -> i32 {
    let b = &d.b
    if row == b.mi_row {
        if !b.avail_u { ret 64i32 }
        let m = &d.mi[D.mi_at(d, row - 1i32, col)]
        if m.skip == 1u8 && m.is_inter == 1u8 { ret D.block_w(d, usize(m.size)) }
    }
    ret D.tx_w(d, usize(d.mi[D.mi_at(d, row - 1i32, col)].inter_tx_size))
}

fn left_tx_height(d: *D.Dec, row: i32, col: i32) -> i32 {
    let b = &d.b
    if col == b.mi_col {
        if !b.avail_l { ret 64i32 }
        let m = &d.mi[D.mi_at(d, row, col - 1i32)]
        if m.skip == 1u8 && m.is_inter == 1u8 { ret D.block_h(d, usize(m.size)) }
    }
    ret D.tx_h(d, usize(d.mi[D.mi_at(d, row, col - 1i32)].inter_tx_size))
}

fn read_tx_size(d: *D.Dec, allow_select: bool) {
    let b = &d.b
    if b.lossless {
        b.tx_size = D.TX_4X4
        ret
    }
    let max_rect = usize(d.tab[av1_tables.T_MAX_TX_SIZE_RECT + b.mi_size])
    let max_depth = d.tab[av1_tables.T_MAX_TX_DEPTH + b.mi_size]
    b.tx_size = max_rect
    if b.mi_size > D.BLOCK_4X4 && allow_select && d.st.h.tx_mode == av1.TX_MODE_SELECT {
        var above_w = 0i32
        var left_h = 0i32
        if b.avail_u {
            let m = &d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)]
            if m.is_inter == 1u8 { above_w = D.block_w(d, usize(m.size)) } else { above_w = above_tx_width(d, b.mi_row, b.mi_col) }
        }
        if b.avail_l {
            let m = &d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)]
            if m.is_inter == 1u8 { left_h = D.block_h(d, usize(m.size)) } else { left_h = left_tx_height(d, b.mi_row, b.mi_col) }
        }
        var ctx = 0usize
        if above_w >= D.tx_w(d, max_rect) { ctx += 1usize }
        if left_h >= D.tx_h(d, max_rect) { ctx += 1usize }
        var depth = 0usize
        if max_depth == 4i32 {
            depth = D.sym(d, CDF.C_TX64X64, 4usize, ctx, 3usize)
        } else if max_depth == 3i32 {
            depth = D.sym(d, CDF.C_TX32X32, 4usize, ctx, 3usize)
        } else if max_depth == 2i32 {
            depth = D.sym(d, CDF.C_TX16X16, 4usize, ctx, 3usize)
        } else {
            depth = D.sym(d, CDF.C_TX8X8, 3usize, ctx, 2usize)
        }
        var i = 0usize
        while i < depth {
            b.tx_size = usize(d.tab[av1_tables.T_SPLIT_TX_SIZE + b.tx_size])
            i += 1usize
        }
    }
}

fn find_tx_size(d: *D.Dec, w: i32, h: i32) -> usize {
    var tx = 0usize
    while tx < D.TX_SIZES_ALL {
        if D.tx_w(d, tx) == w && D.tx_h(d, tx) == h { break }
        tx += 1usize
    }
    ret tx
}

fn set_inter_tx(d: *D.Dec, row: i32, col: i32, w4: i32, h4: i32, tx: usize) {
    var ye = h4
    if row + ye > d.mi_rows { ye = d.mi_rows - row }
    var xe = w4
    if col + xe > d.mi_cols { xe = d.mi_cols - col }
    let t = u8(tx)
    var y = 0i32
    @nocheck {
    while y < ye {
        var at = D.mi_at(d, row + y, col)
        var x = 0i32
        while x < xe {
            d.mi[at].inter_tx_size = t
            at += 1usize
            x += 1i32
        }
        y += 1i32
    }
    }
}

fn read_var_tx_size(d: *D.Dec, row: i32, col: i32, tx: usize, depth: i32) {
    let b = &d.b
    if row >= d.mi_rows || col >= d.mi_cols { ret }
    var split = false
    if tx != D.TX_4X4 && depth != 2i32 {
        let above = above_tx_width(d, row, col) < D.tx_w(d, tx)
        let left = left_tx_height(d, row, col) < D.tx_h(d, tx)
        var size = D.max_i(D.block_w(d, b.mi_size), D.block_h(d, b.mi_size))
        if size > 64i32 { size = 64i32 }
        let max_tx = find_tx_size(d, size, size)
        let sqr_up = usize(d.tab[av1_tables.T_TX_SIZE_SQR_UP + tx])
        var ctx = 0usize
        if sqr_up != max_tx { ctx = 3usize }
        ctx += usize(4i32 - i32(max_tx)) * 6usize
        if above { ctx += 1usize }
        if left { ctx += 1usize }
        split = D.sym(d, CDF.C_TXFMSPLIT, 3usize, ctx, 2usize) == 1usize
    }
    let w4 = D.tx_w(d, tx) / 4i32
    let h4 = D.tx_h(d, tx) / 4i32
    if split {
        let sub = usize(d.tab[av1_tables.T_SPLIT_TX_SIZE + tx])
        let step_w = D.tx_w(d, sub) / 4i32
        let step_h = D.tx_h(d, sub) / 4i32
        var i = 0i32
        while i < h4 {
            var j = 0i32
            while j < w4 {
                read_var_tx_size(d, row + i, col + j, sub, depth + 1i32)
                j += step_w
            }
            i += step_h
        }
    } else {
        set_inter_tx(d, row, col, w4, h4, tx)
        b.tx_size = tx
    }
}

fn read_block_tx_size(d: *D.Dec) {
    let b = &d.b
    if d.st.h.tx_mode == av1.TX_MODE_SELECT && b.mi_size > D.BLOCK_4X4 && b.is_inter && !b.skip && !b.lossless {
        let max_tx = usize(d.tab[av1_tables.T_MAX_TX_SIZE_RECT + b.mi_size])
        let tw4 = D.tx_w(d, max_tx) / 4i32
        let th4 = D.tx_h(d, max_tx) / 4i32
        var row = b.mi_row
        while row < b.mi_row + b.bh4 {
            var col = b.mi_col
            while col < b.mi_col + b.bw4 {
                read_var_tx_size(d, row, col, max_tx, 0i32)
                col += tw4
            }
            row += th4
        }
    } else {
        read_tx_size(d, !b.skip || !b.is_inter)
        set_inter_tx(d, b.mi_row, b.mi_col, b.bw4, b.bh4, b.tx_size)
    }
}

// ------------------------------------------------------------------ intra modes

fn is_directional(mode: usize) -> bool {
    ret mode >= D.V_PRED && mode <= D.D67_PRED
}

fn intra_angle_info_y(d: *D.Dec) {
    let b = &d.b
    b.angle_delta_y = 0i32
    if b.mi_size >= D.BLOCK_8X8 && is_directional(b.y_mode) {
        b.angle_delta_y = i32(D.sym(d, CDF.C_ANGLEDELTA, 8usize, b.y_mode - D.V_PRED, 7usize)) - 3i32
    }
}

fn intra_angle_info_uv(d: *D.Dec) {
    let b = &d.b
    b.angle_delta_uv = 0i32
    if b.mi_size >= D.BLOCK_8X8 && is_directional(b.uv_mode) {
        b.angle_delta_uv = i32(D.sym(d, CDF.C_ANGLEDELTA, 8usize, b.uv_mode - D.V_PRED, 7usize)) - 3i32
    }
}

fn read_cfl_alphas(d: *D.Dec) {
    let b = &d.b
    let signs = i32(D.sym(d, CDF.C_CFLSIGN, 9usize, 0usize, 8usize))
    let sign_u = (signs + 1i32) / 3i32
    let sign_v = (signs + 1i32) % 3i32
    b.cfl_alpha_u = 0i32
    b.cfl_alpha_v = 0i32
    if sign_u != 0i32 {
        let ctx = usize((sign_u - 1i32) * 3i32 + sign_v)
        let v = 1i32 + i32(D.sym(d, CDF.C_CFLALPHA, 17usize, ctx, 16usize))
        if sign_u == 1i32 { b.cfl_alpha_u = 0i32 - v } else { b.cfl_alpha_u = v }
    }
    if sign_v != 0i32 {
        let ctx = usize((sign_v - 1i32) * 3i32 + sign_u)
        let v = 1i32 + i32(D.sym(d, CDF.C_CFLALPHA, 17usize, ctx, 16usize))
        if sign_v == 1i32 { b.cfl_alpha_v = 0i32 - v } else { b.cfl_alpha_v = v }
    }
}

fn read_uv_mode(d: *D.Dec) {
    let b = &d.b
    var cfl_allowed = false
    if b.lossless && D.sub_size(d, b.mi_size, d.st.seq.subsampling_x, d.st.seq.subsampling_y) == D.BLOCK_4X4 {
        cfl_allowed = true
    } else if !b.lossless && D.max_i(D.block_w(d, b.mi_size), D.block_h(d, b.mi_size)) <= 32i32 {
        cfl_allowed = true
    }
    if cfl_allowed {
        b.uv_mode = D.sym(d, CDF.C_UVMODECFLALLOWED, 15usize, b.y_mode, 14usize)
    } else {
        b.uv_mode = D.sym(d, CDF.C_UVMODECFLNOTALLOWED, 14usize, b.y_mode, 13usize)
    }
    if b.uv_mode == D.UV_CFL_PRED { read_cfl_alphas(d) }
    intra_angle_info_uv(d)
}

fn filter_intra_mode_info(d: *D.Dec) -> err {
    let b = &d.b
    b.use_filter_intra = false
    if d.st.seq.enable_filter_intra && b.y_mode == D.DC_PRED && D.max_i(D.block_w(d, b.mi_size), D.block_h(d, b.mi_size)) <= 32i32 {
        b.use_filter_intra = D.sym(d, CDF.C_FILTERINTRA, 3usize, b.mi_size, 2usize) == 1usize
        if b.use_filter_intra { b.filter_intra_mode = D.sym(d, CDF.C_FILTERINTRAMODE, 6usize, 0usize, 5usize) }
    }
    ret ok
}

fn intra_frame_mode_info(d: *D.Dec) -> err {
    let b = &d.b
    let h = &d.st.h
    b.skip = false
    if h.seg_id_pre_skip { try intra_segment_id(d) }
    b.skip_mode = false
    read_skip(d)
    if !h.seg_id_pre_skip { try intra_segment_id(d) }
    read_cdef(d)
    read_delta_qindex(d)
    read_delta_lf(d)
    d.read_deltas = false
    b.ref_frame0 = i32(av1.INTRA_FRAME)
    b.ref_frame1 = D.NONE_REF
    if h.allow_intrabc { ret Unsupported }
    b.use_intrabc = false
    b.is_inter = false
    var above_mode = D.DC_PRED
    var left_mode = D.DC_PRED
    if b.avail_u { above_mode = usize(d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)].y_mode) }
    if b.avail_l { left_mode = usize(d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)].y_mode) }
    let actx = usize(d.tab[av1_tables.T_INTRA_MODE_CONTEXT + above_mode])
    let lctx = usize(d.tab[av1_tables.T_INTRA_MODE_CONTEXT + left_mode])
    b.y_mode = D.sym(d, CDF.C_INTRAFRAMEYMODE, 14usize, actx * 5usize + lctx, 13usize)
    intra_angle_info_y(d)
    if b.has_chroma { read_uv_mode(d) }
    if b.mi_size >= D.BLOCK_8X8 && D.block_w(d, b.mi_size) <= 64i32 && D.block_h(d, b.mi_size) <= 64i32 && h.allow_screen_content_tools { ret Unsupported }
    ret filter_intra_mode_info(d)
}

fn intra_block_mode_info(d: *D.Dec) -> err {
    let b = &d.b
    b.ref_frame0 = i32(av1.INTRA_FRAME)
    b.ref_frame1 = D.NONE_REF
    let ctx = usize(d.tab[av1_tables.T_SIZE_GROUP + b.mi_size])
    b.y_mode = D.sym(d, CDF.C_YMODE, 14usize, ctx, 13usize)
    intra_angle_info_y(d)
    if b.has_chroma { read_uv_mode(d) }
    if b.mi_size >= D.BLOCK_8X8 && D.block_w(d, b.mi_size) <= 64i32 && D.block_h(d, b.mi_size) <= 64i32 && d.st.h.allow_screen_content_tools { ret Unsupported }
    ret filter_intra_mode_info(d)
}

// ------------------------------------------------------------------ inter frames

fn check_backward(r: i32) -> bool {
    ret r >= i32(av1.BWDREF_FRAME) && r <= i32(av1.ALTREF_FRAME)
}

fn count_refs(d: *D.Dec, frame_type: usize) -> i32 {
    let b = &d.b
    let ft = i32(frame_type)
    var c = 0i32
    if b.avail_u {
        if b.above_ref0 == ft { c += 1i32 }
        if b.above_ref1 == ft { c += 1i32 }
    }
    if b.avail_l {
        if b.left_ref0 == ft { c += 1i32 }
        if b.left_ref1 == ft { c += 1i32 }
    }
    ret c
}

fn ref_count_ctx(c0: i32, c1: i32) -> usize {
    if c0 < c1 { ret 0usize }
    if c0 == c1 { ret 1usize }
    ret 2usize
}

fn ctx_comp_ref(d: *D.Dec) -> usize {
    ret ref_count_ctx(count_refs(d, av1.LAST_FRAME) + count_refs(d, av1.LAST2_FRAME), count_refs(d, av1.LAST3_FRAME) + count_refs(d, av1.GOLDEN_FRAME))
}

fn ctx_comp_ref_p1(d: *D.Dec) -> usize {
    ret ref_count_ctx(count_refs(d, av1.LAST_FRAME), count_refs(d, av1.LAST2_FRAME))
}

fn ctx_comp_ref_p2(d: *D.Dec) -> usize {
    ret ref_count_ctx(count_refs(d, av1.LAST3_FRAME), count_refs(d, av1.GOLDEN_FRAME))
}

fn ctx_comp_bwdref(d: *D.Dec) -> usize {
    ret ref_count_ctx(count_refs(d, av1.BWDREF_FRAME) + count_refs(d, av1.ALTREF2_FRAME), count_refs(d, av1.ALTREF_FRAME))
}

fn ctx_comp_bwdref_p1(d: *D.Dec) -> usize {
    ret ref_count_ctx(count_refs(d, av1.BWDREF_FRAME), count_refs(d, av1.ALTREF2_FRAME))
}

fn ctx_single_ref_p1(d: *D.Dec) -> usize {
    let fwd = count_refs(d, av1.LAST_FRAME) + count_refs(d, av1.LAST2_FRAME) + count_refs(d, av1.LAST3_FRAME) + count_refs(d, av1.GOLDEN_FRAME)
    let bwd = count_refs(d, av1.BWDREF_FRAME) + count_refs(d, av1.ALTREF2_FRAME) + count_refs(d, av1.ALTREF_FRAME)
    ret ref_count_ctx(fwd, bwd)
}

fn single_bit(d: *D.Dec, n: usize, ctx: usize) -> usize {
    ret D.sym(d, CDF.C_SINGLEREF, 3usize, ctx * 6usize + n, 2usize)
}

fn is_samedir(r0: i32, r1: i32) -> bool {
    ret (r0 >= i32(av1.BWDREF_FRAME)) == (r1 >= i32(av1.BWDREF_FRAME))
}

fn b2i(x: bool) -> usize {
    if x { ret 1usize }
    ret 0usize
}

fn comp_ref_type_ctx(d: *D.Dec) -> usize {
    let b = &d.b
    let above_comp = b.avail_u && !b.above_intra && !b.above_single
    let left_comp = b.avail_l && !b.left_intra && !b.left_single
    let above_uni = above_comp && is_samedir(b.above_ref0, b.above_ref1)
    let left_uni = left_comp && is_samedir(b.left_ref0, b.left_ref1)
    if b.avail_u && !b.above_intra && b.avail_l && !b.left_intra {
        let samedir = b2i(is_samedir(b.above_ref0, b.left_ref0))
        if !above_comp && !left_comp { ret 1usize + 2usize * samedir }
        if !above_comp {
            if !left_uni { ret 1usize }
            ret 3usize + samedir
        }
        if !left_comp {
            if !above_uni { ret 1usize }
            ret 3usize + samedir
        }
        if !above_uni && !left_uni { ret 0usize }
        if !above_uni || !left_uni { ret 2usize }
        ret 3usize + b2i((b.above_ref0 == i32(av1.BWDREF_FRAME)) == (b.left_ref0 == i32(av1.BWDREF_FRAME)))
    }
    if b.avail_u && b.avail_l {
        if above_comp { ret 1usize + 2usize * b2i(above_uni) }
        if left_comp { ret 1usize + 2usize * b2i(left_uni) }
        ret 2usize
    }
    if above_comp { ret 4usize * b2i(above_uni) }
    if left_comp { ret 4usize * b2i(left_uni) }
    ret 2usize
}

fn comp_mode_ctx(d: *D.Dec) -> usize {
    let b = &d.b
    if b.avail_u && b.avail_l {
        if b.above_single && b.left_single {
            ret b2i(check_backward(b.above_ref0)) ^ b2i(check_backward(b.left_ref0))
        }
        if b.above_single { ret 2usize + b2i(check_backward(b.above_ref0) || b.above_intra) }
        if b.left_single { ret 2usize + b2i(check_backward(b.left_ref0) || b.left_intra) }
        ret 4usize
    }
    if b.avail_u {
        if b.above_single { ret b2i(check_backward(b.above_ref0)) }
        ret 3usize
    }
    if b.avail_l {
        if b.left_single { ret b2i(check_backward(b.left_ref0)) }
        ret 3usize
    }
    ret 1usize
}

fn read_ref_frames(d: *D.Dec) {
    let b = &d.b
    let h = &d.st.h
    if b.skip_mode {
        b.ref_frame0 = h.skip_mode_frame[0usize]
        b.ref_frame1 = h.skip_mode_frame[1usize]
        ret
    }
    if seg_feature_active(d, av1.SEG_LVL_REF_FRAME) {
        b.ref_frame0 = h.feature_data[b.segment_id * 8usize + av1.SEG_LVL_REF_FRAME]
        b.ref_frame1 = D.NONE_REF
        ret
    }
    if seg_feature_active(d, D.SEG_LVL_SKIP) || seg_feature_active(d, D.SEG_LVL_GLOBALMV) {
        b.ref_frame0 = i32(av1.LAST_FRAME)
        b.ref_frame1 = D.NONE_REF
        ret
    }
    var compound = false
    if h.reference_select && D.min_i(b.bw4, b.bh4) >= 2i32 {
        compound = D.sym(d, CDF.C_COMPMODE, 3usize, comp_mode_ctx(d), 2usize) == 1usize
    }
    if compound {
        let ref_type = D.sym(d, CDF.C_COMPREFTYPE, 3usize, comp_ref_type_ctx(d), 2usize)
        if ref_type == 0usize {
            if D.sym(d, CDF.C_UNICOMPREF, 3usize, ctx_single_ref_p1(d) * 3usize, 2usize) == 1usize {
                b.ref_frame0 = i32(av1.BWDREF_FRAME)
                b.ref_frame1 = i32(av1.ALTREF_FRAME)
            } else {
                let c1 = ref_count_ctx(count_refs(d, av1.LAST2_FRAME), count_refs(d, av1.LAST3_FRAME) + count_refs(d, av1.GOLDEN_FRAME))
                if D.sym(d, CDF.C_UNICOMPREF, 3usize, c1 * 3usize + 1usize, 2usize) == 1usize {
                    if D.sym(d, CDF.C_UNICOMPREF, 3usize, ctx_comp_ref_p2(d) * 3usize + 2usize, 2usize) == 1usize {
                        b.ref_frame0 = i32(av1.LAST_FRAME)
                        b.ref_frame1 = i32(av1.GOLDEN_FRAME)
                    } else {
                        b.ref_frame0 = i32(av1.LAST_FRAME)
                        b.ref_frame1 = i32(av1.LAST3_FRAME)
                    }
                } else {
                    b.ref_frame0 = i32(av1.LAST_FRAME)
                    b.ref_frame1 = i32(av1.LAST2_FRAME)
                }
            }
        } else {
            if D.sym(d, CDF.C_COMPREF, 3usize, ctx_comp_ref(d) * 3usize, 2usize) == 0usize {
                if D.sym(d, CDF.C_COMPREF, 3usize, ctx_comp_ref_p1(d) * 3usize + 1usize, 2usize) == 1usize { b.ref_frame0 = i32(av1.LAST2_FRAME) } else { b.ref_frame0 = i32(av1.LAST_FRAME) }
            } else {
                if D.sym(d, CDF.C_COMPREF, 3usize, ctx_comp_ref_p2(d) * 3usize + 2usize, 2usize) == 1usize { b.ref_frame0 = i32(av1.GOLDEN_FRAME) } else { b.ref_frame0 = i32(av1.LAST3_FRAME) }
            }
            if D.sym(d, CDF.C_COMPBWDREF, 3usize, ctx_comp_bwdref(d) * 2usize, 2usize) == 0usize {
                if D.sym(d, CDF.C_COMPBWDREF, 3usize, ctx_comp_bwdref_p1(d) * 2usize + 1usize, 2usize) == 1usize { b.ref_frame1 = i32(av1.ALTREF2_FRAME) } else { b.ref_frame1 = i32(av1.BWDREF_FRAME) }
            } else {
                b.ref_frame1 = i32(av1.ALTREF_FRAME)
            }
        }
        ret
    }
    if single_bit(d, 0usize, ctx_single_ref_p1(d)) == 1usize {
        if single_bit(d, 1usize, ctx_comp_bwdref(d)) == 0usize {
            if single_bit(d, 5usize, ctx_comp_bwdref_p1(d)) == 1usize { b.ref_frame0 = i32(av1.ALTREF2_FRAME) } else { b.ref_frame0 = i32(av1.BWDREF_FRAME) }
        } else {
            b.ref_frame0 = i32(av1.ALTREF_FRAME)
        }
    } else if single_bit(d, 2usize, ctx_comp_ref(d)) == 1usize {
        if single_bit(d, 4usize, ctx_comp_ref_p2(d)) == 1usize { b.ref_frame0 = i32(av1.GOLDEN_FRAME) } else { b.ref_frame0 = i32(av1.LAST3_FRAME) }
    } else {
        if single_bit(d, 3usize, ctx_comp_ref_p1(d)) == 1usize { b.ref_frame0 = i32(av1.LAST2_FRAME) } else { b.ref_frame0 = i32(av1.LAST_FRAME) }
    }
    b.ref_frame1 = D.NONE_REF
}

fn read_is_inter(d: *D.Dec) {
    let b = &d.b
    if b.skip_mode {
        b.is_inter = true
        ret
    }
    if seg_feature_active(d, av1.SEG_LVL_REF_FRAME) {
        b.is_inter = d.st.h.feature_data[b.segment_id * 8usize + av1.SEG_LVL_REF_FRAME] != i32(av1.INTRA_FRAME)
        ret
    }
    if seg_feature_active(d, D.SEG_LVL_GLOBALMV) {
        b.is_inter = true
        ret
    }
    var ctx = 0usize
    if b.avail_u && b.avail_l {
        if b.left_intra && b.above_intra {
            ctx = 3usize
        } else {
            ctx = b2i(b.left_intra || b.above_intra)
        }
    } else if b.avail_u || b.avail_l {
        if b.avail_u { ctx = 2usize * b2i(b.above_intra) } else { ctx = 2usize * b2i(b.left_intra) }
    }
    b.is_inter = D.sym(d, CDF.C_ISINTER, 3usize, ctx, 2usize) == 1usize
}

fn mv_component(d: *D.Dec, comp: usize) -> i32 {
    let hp_allowed = d.st.h.allow_high_precision_mv
    let intcl = d.st.h.force_integer_mv
    let sign = D.sym(d, CDF.C_MVSIGN, 3usize, comp, 2usize)
    let class = D.sym(d, CDF.C_MVCLASS + comp * 12usize, 12usize, 0usize, 11usize)
    var mag = 0i32
    if class == 0usize {
        let bit = D.sym(d, CDF.C_MVCLASS0BIT, 3usize, comp, 2usize)
        var fr = 3usize
        if !intcl { fr = D.sym(d, CDF.C_MVCLASS0FR + comp * 10usize + bit * 5usize, 5usize, 0usize, 4usize) }
        var hp = 1usize
        if hp_allowed { hp = D.sym(d, CDF.C_MVCLASS0HP, 3usize, comp, 2usize) }
        mag = i32((bit << 3u32) | (fr << 1u32) | hp) + 1i32
    } else {
        var dd = 0usize
        var i = 0usize
        while i < class {
            let bit = D.sym(d, CDF.C_MVBIT + comp * 30usize + i * 3usize, 3usize, 0usize, 2usize)
            dd = dd | (bit << u32(i))
            i += 1usize
        }
        mag = 2i32 << u32(class + 2usize)
        var fr = 3usize
        if !intcl { fr = D.sym(d, CDF.C_MVFR + comp * 5usize, 5usize, 0usize, 4usize) }
        var hp = 1usize
        if hp_allowed { hp = D.sym(d, CDF.C_MVHP, 3usize, comp, 2usize) }
        mag += i32((dd << 3u32) | (fr << 1u32) | hp) + 1i32
    }
    if sign == 1usize { ret 0i32 - mag }
    ret mag
}

fn read_mv(d: *D.Dec, ref: usize, pred_row: i32, pred_col: i32) {
    let b = &d.b
    let joint = D.sym(d, CDF.C_MVJOINT, 5usize, 0usize, 4usize)
    var dr = 0i32
    var dcol = 0i32
    if joint == 2usize || joint == 3usize { dr = mv_component(d, 0usize) }
    if joint == 1usize || joint == 3usize { dcol = mv_component(d, 1usize) }
    if ref == 0usize {
        b.mv0_row = pred_row + dr
        b.mv0_col = pred_col + dcol
    } else {
        b.mv1_row = pred_row + dr
        b.mv1_col = pred_col + dcol
    }
}

fn get_mode(y_mode: usize, ref_list: usize) -> usize {
    if ref_list == 0usize {
        if y_mode < D.NEAREST_NEARESTMV { ret y_mode }
        if y_mode == D.NEW_NEWMV || y_mode == D.NEW_NEARESTMV || y_mode == D.NEW_NEARMV { ret D.NEWMV }
        if y_mode == D.NEAREST_NEARESTMV || y_mode == D.NEAREST_NEWMV { ret D.NEARESTMV }
        if y_mode == D.NEAR_NEARMV || y_mode == D.NEAR_NEWMV { ret D.NEARMV }
        ret D.GLOBALMV
    }
    if y_mode == D.NEW_NEWMV || y_mode == D.NEAREST_NEWMV || y_mode == D.NEAR_NEWMV { ret D.NEWMV }
    if y_mode == D.NEAREST_NEARESTMV || y_mode == D.NEW_NEARESTMV { ret D.NEARESTMV }
    if y_mode == D.NEAR_NEARMV || y_mode == D.NEW_NEARMV { ret D.NEARMV }
    ret D.GLOBALMV
}

fn has_nearmv(m: usize) -> bool {
    ret m == D.NEARMV || m == D.NEAR_NEARMV || m == D.NEAR_NEWMV || m == D.NEW_NEARMV
}

fn needs_interp_filter(d: *D.Dec) -> bool {
    let b = &d.b
    let large = D.min_i(D.block_w(d, b.mi_size), D.block_h(d, b.mi_size)) >= 8i32
    if b.skip_mode || b.motion_mode == D.LOCALWARP { ret false }
    if large && b.y_mode == D.GLOBALMV { ret d.st.h.gm_type[usize(b.ref_frame0)] == av1.TRANSLATION }
    if large && b.y_mode == D.GLOBAL_GLOBALMV {
        ret d.st.h.gm_type[usize(b.ref_frame0)] == av1.TRANSLATION || d.st.h.gm_type[usize(b.ref_frame1)] == av1.TRANSLATION
    }
    ret true
}

fn interp_ctx(d: *D.Dec, dir: usize) -> usize {
    let b = &d.b
    var ctx = ((dir & 1usize) * 2usize + b2i(b.ref_frame1 > i32(av1.INTRA_FRAME))) * 4usize
    var left_type = 3usize
    var above_type = 3usize
    if b.avail_l {
        let m = &d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)]
        if i32(m.ref0) == b.ref_frame0 || i32(m.ref1) == b.ref_frame0 {
            if dir == 0usize { left_type = usize(m.interp0) } else { left_type = usize(m.interp1) }
        }
    }
    if b.avail_u {
        let m = &d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)]
        if i32(m.ref0) == b.ref_frame0 || i32(m.ref1) == b.ref_frame0 {
            if dir == 0usize { above_type = usize(m.interp0) } else { above_type = usize(m.interp1) }
        }
    }
    if left_type == above_type {
        ctx += left_type
    } else if left_type == 3usize {
        ctx += above_type
    } else if above_type == 3usize {
        ctx += left_type
    } else {
        ctx += 3usize
    }
    ret ctx
}

fn read_drl(d: *D.Dec, first: i32, last: i32) {
    let b = &d.b
    let p = &d.mvp
    var idx = first
    while idx < last {
        if p.num_found > idx + 1i32 {
            if D.sym(d, CDF.C_DRLMODE, 3usize, usize(p.drl_ctx[usize(idx)]), 2usize) == 0usize {
                b.ref_mv_idx = idx
                break
            }
            b.ref_mv_idx = idx + 1i32
        }
        idx += 1i32
    }
}

fn read_modes_and_mvs(d: *D.Dec, compound: bool) {
    let b = &d.b
    let p = &d.mvp
    if b.skip_mode {
        b.y_mode = D.NEAREST_NEARESTMV
    } else if seg_feature_active(d, D.SEG_LVL_SKIP) || seg_feature_active(d, D.SEG_LVL_GLOBALMV) {
        b.y_mode = D.GLOBALMV
    } else if compound {
        let ctx = usize(d.tab[av1_tables.T_COMPOUND_MODE_CTX_MAP + usize(p.ref_mv_ctx >> 1u32) * 5usize + usize(D.min_i(p.new_mv_ctx, 4i32))])
        b.y_mode = D.NEAREST_NEARESTMV + D.sym(d, CDF.C_COMPOUNDMODE, 9usize, ctx, 8usize)
    } else if D.sym(d, CDF.C_NEWMV, 3usize, usize(p.new_mv_ctx), 2usize) == 0usize {
        b.y_mode = D.NEWMV
    } else if D.sym(d, CDF.C_ZEROMV, 3usize, usize(p.zero_mv_ctx), 2usize) == 0usize {
        b.y_mode = D.GLOBALMV
    } else if D.sym(d, CDF.C_REFMV, 3usize, usize(p.ref_mv_ctx), 2usize) == 0usize {
        b.y_mode = D.NEARESTMV
    } else {
        b.y_mode = D.NEARMV
    }
    b.ref_mv_idx = 0i32
    if b.y_mode == D.NEWMV || b.y_mode == D.NEW_NEWMV {
        read_drl(d, 0i32, 2i32)
    } else if has_nearmv(b.y_mode) {
        b.ref_mv_idx = 1i32
        read_drl(d, 1i32, 3i32)
    }
    var i = 0usize
    var lists = 1usize
    if compound { lists = 2usize }
    while i < lists {
        let comp_mode = get_mode(b.y_mode, i)
        var pr = 0i32
        var pc = 0i32
        if comp_mode == D.GLOBALMV {
            pr = p.global_mvs[i * 2usize]
            pc = p.global_mvs[i * 2usize + 1usize]
        } else {
            var pos = usize(b.ref_mv_idx)
            if comp_mode == D.NEARESTMV { pos = 0usize }
            if comp_mode == D.NEWMV && p.num_found <= 1i32 { pos = 0usize }
            pr = p.stack[pos * 4usize + i * 2usize]
            pc = p.stack[pos * 4usize + i * 2usize + 1usize]
        }
        if comp_mode == D.NEWMV {
            read_mv(d, i, pr, pc)
        } else if i == 0usize {
            b.mv0_row = pr
            b.mv0_col = pc
        } else {
            b.mv1_row = pr
            b.mv1_col = pc
        }
        i += 1usize
    }
}

fn is_scaled(d: *D.Dec, ref_frame: i32) -> bool {
    let h = &d.st.h
    let slot = usize(h.ref_frame_idx[usize(ref_frame) - av1.LAST_FRAME])
    let r = &d.st.refs[slot]
    let xs = ((r.upscaled_width << 14u32) + (h.frame_width / 2i32)) / h.frame_width
    let ys = ((r.frame_height << 14u32) + (h.frame_height / 2i32)) / h.frame_height
    ret xs != 16384i32 || ys != 16384i32
}

fn inter_block_mode_info(d: *D.Dec) -> err {
    let b = &d.b
    let h = &d.st.h
    let seq = &d.st.seq
    read_ref_frames(d)
    let compound = b.ref_frame1 > i32(av1.INTRA_FRAME)
    var mb: MV.Block = zero
    mb.mi_row = b.mi_row
    mb.mi_col = b.mi_col
    mb.mi_size = i32(b.mi_size)
    mb.ref0 = b.ref_frame0
    mb.ref1 = b.ref_frame1
    mb.compound = compound
    d.mvf.tile_row_start = d.row_start
    d.mvf.tile_row_end = d.row_end
    d.mvf.tile_col_start = d.col_start
    d.mvf.tile_col_end = d.col_end
    MV.find_mv_stack(&d.mvf, mb, &d.mvp)
    read_modes_and_mvs(d, compound)
    b.interintra = false
    b.wedge_interintra = false
    if !b.skip_mode && seq.enable_interintra_compound && !compound && b.mi_size >= D.BLOCK_8X8 && b.mi_size <= 9usize {
        let ctx = usize(d.tab[av1_tables.T_SIZE_GROUP + b.mi_size] - 1i32)
        b.interintra = D.sym(d, CDF.C_INTERINTRA, 3usize, ctx, 2usize) == 1usize
        if b.interintra {
            b.interintra_mode = D.sym(d, CDF.C_INTERINTRAMODE, 5usize, ctx, 4usize)
            b.ref_frame1 = i32(av1.INTRA_FRAME)
            b.angle_delta_y = 0i32
            b.angle_delta_uv = 0i32
            b.use_filter_intra = false
            b.wedge_interintra = D.sym(d, CDF.C_WEDGEINTERINTRA, 3usize, b.mi_size, 2usize) == 1usize
            if b.wedge_interintra {
                b.wedge_index = D.sym(d, CDF.C_WEDGEINDEX, 17usize, b.mi_size, 16usize)
                b.wedge_sign = 0usize
            }
        }
    }
    b.motion_mode = D.SIMPLE
    if !b.skip_mode && h.is_motion_mode_switchable && D.min_i(D.block_w(d, b.mi_size), D.block_h(d, b.mi_size)) >= 8i32 {
        var simple = false
        if !h.force_integer_mv && (b.y_mode == D.GLOBALMV || b.y_mode == D.GLOBAL_GLOBALMV) {
            if h.gm_type[usize(b.ref_frame0)] > av1.TRANSLATION { simple = true }
        }
        if compound || b.ref_frame1 == i32(av1.INTRA_FRAME) { simple = true }
        if !simple && !MV.has_overlappable_candidates(&d.mvf, mb, b.avail_u, b.avail_l) { simple = true }
        if !simple {
            let (ns, nse) = WP.find_warp_samples(&d.mvf, mb, b.avail_u, b.avail_l, b.mv0_row, b.mv0_col, b.cand_list[..])
            if nse != ok { ret nse }
            b.num_samples = ns
            if h.force_integer_mv || ns == 0i32 || !h.allow_warped_motion || is_scaled(d, b.ref_frame0) {
                if D.sym(d, CDF.C_USEOBMC, 3usize, b.mi_size, 2usize) == 1usize { b.motion_mode = D.OBMC }
            } else {
                b.motion_mode = D.sym(d, CDF.C_MOTIONMODE, 4usize, b.mi_size, 3usize)
            }
        }
    }
    b.comp_group_idx = 0usize
    b.compound_idx = 1usize
    if compound && !b.skip_mode {
        if seq.enable_masked_compound { ret Unsupported }
        if seq.enable_jnt_comp { ret Unsupported }
    }
    if h.interpolation_filter == av1.SWITCHABLE {
        var dirs = 1usize
        if seq.enable_dual_filter { dirs = 2usize }
        var dir = 0usize
        while dir < dirs {
            var f = 0usize
            if needs_interp_filter(d) { f = D.sym(d, CDF.C_INTERPFILTER, 4usize, interp_ctx(d, dir), 3usize) }
            if dir == 0usize { b.interp0 = f } else { b.interp1 = f }
            dir += 1usize
        }
        if !seq.enable_dual_filter { b.interp1 = b.interp0 }
    } else {
        b.interp0 = usize(h.interpolation_filter)
        b.interp1 = usize(h.interpolation_filter)
    }
    ret ok
}

fn inter_frame_mode_info(d: *D.Dec) -> err {
    let b = &d.b
    let h = &d.st.h
    b.use_intrabc = false
    b.left_ref0 = i32(av1.INTRA_FRAME)
    b.above_ref0 = i32(av1.INTRA_FRAME)
    b.left_ref1 = D.NONE_REF
    b.above_ref1 = D.NONE_REF
    if b.avail_l {
        let m = &d.mi[D.mi_at(d, b.mi_row, b.mi_col - 1i32)]
        b.left_ref0 = i32(m.ref0)
        b.left_ref1 = i32(m.ref1)
    }
    if b.avail_u {
        let m = &d.mi[D.mi_at(d, b.mi_row - 1i32, b.mi_col)]
        b.above_ref0 = i32(m.ref0)
        b.above_ref1 = i32(m.ref1)
    }
    b.left_intra = b.left_ref0 <= i32(av1.INTRA_FRAME)
    b.above_intra = b.above_ref0 <= i32(av1.INTRA_FRAME)
    b.left_single = b.left_ref1 <= i32(av1.INTRA_FRAME)
    b.above_single = b.above_ref1 <= i32(av1.INTRA_FRAME)
    b.skip = false
    try inter_segment_id(d, true)
    read_skip_mode(d)
    if b.skip_mode { b.skip = true } else { read_skip(d) }
    if !h.seg_id_pre_skip { try inter_segment_id(d, false) }
    b.lossless = h.lossless_array[b.segment_id]
    read_cdef(d)
    read_delta_qindex(d)
    read_delta_lf(d)
    d.read_deltas = false
    read_is_inter(d)
    if b.is_inter { ret inter_block_mode_info(d) }
    ret intra_block_mode_info(d)
}
