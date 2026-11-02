// AV1 inter prediction glue: builds the arguments of e.fmt.av1_inter from the decoder state for the blocks of the
// compute_prediction process of the specification.

use e.time
use e.fmt.av1
use e.fmt.av1_dec as D
use e.fmt.av1_inter as IN
use e.fmt.av1_intra as INTRA
use e.fmt.av1_mask as MK
use e.fmt.av1_warp as WP
use e.fmt.av1_mvp as MV

error Unsupported

fn motion_of(d: *D.Dec, ref_frame: i32, mv_row: i32, mv_col: i32, f0: usize, f1: usize, plane: usize) -> IN.Motion {
    var m: IN.Motion = zero
    let slot = usize(d.st.h.ref_frame_idx[usize(ref_frame) - av1.LAST_FRAME])
    m.frame.data = d.ref_planes[slot][plane]
    m.frame.stride = d.ref_stride[plane]
    m.frame.width = d.st.refs[slot].upscaled_width
    m.frame.height = d.st.refs[slot].frame_height
    m.mv_row = mv_row
    m.mv_col = mv_col
    m.filter_y = i32(f0)
    m.filter_x = i32(f1)
    ret m
}

fn motion_at(d: *D.Dec, row: i32, col: i32, list: usize, plane: usize) -> IN.Motion {
    let m = &d.mi[D.mi_at(d, row, col)]
    if list == 0usize {
        ret motion_of(d, i32(m.ref0), i32(m.mv0_row), i32(m.mv0_col), usize(m.interp0), usize(m.interp1), plane)
    }
    ret motion_of(d, i32(m.ref1), i32(m.mv1_row), i32(m.mv1_col), usize(m.interp0), usize(m.interp1), plane)
}

fn fill_neighbors(d: *D.Dec, plane: usize, sx: i32, sy: i32) {
    let b = &d.b
    var k = 0i32
    while k < D.min_i(b.bw4, d.mi_cols - b.mi_col) && k < 32i32 {
        var n: IN.Neighbor = zero
        if b.avail_u {
            let row = b.mi_row - 1i32
            let col = b.mi_col + k
            let m = &d.mi[D.mi_at(d, row, col)]
            n.inter = i32(m.ref0) > i32(av1.INTRA_FRAME)
            n.size4 = D.n4w(d, usize(m.size))
            if n.inter { n.motion = motion_at(d, row, col, 0usize, plane) }
        }
        d.obmc_above[usize(k)] = n
        k += 1i32
    }
    k = 0i32
    while k < D.min_i(b.bh4, d.mi_rows - b.mi_row) && k < 32i32 {
        var n: IN.Neighbor = zero
        if b.avail_l {
            let row = b.mi_row + k
            let col = b.mi_col - 1i32
            let m = &d.mi[D.mi_at(d, row, col)]
            n.inter = i32(m.ref0) > i32(av1.INTRA_FRAME)
            n.size4 = D.n4h(d, usize(m.size))
            if n.inter { n.motion = motion_at(d, row, col, 0usize, plane) }
        }
        d.obmc_left[usize(k)] = n
        k += 1i32
    }
}

fn interintra_region(d: *D.Dec, plane: usize, g: IN.Geom, m0: IN.Motion, dst: []u8, stride: usize, sx: i32, sy: i32) -> err {
    let b = &d.b
    var mode = D.DC_PRED
    if b.interintra_mode == 1usize { mode = D.V_PRED }
    if b.interintra_mode == 2usize { mode = D.H_PRED }
    if b.interintra_mode == 3usize { mode = D.SMOOTH_PRED }
    var sb_mask = 15i32
    if d.st.seq.use_128x128_superblock { sb_mask = 31i32 }
    let sub_row = b.mi_row & sb_mask
    let sub_col = b.mi_col & sb_mask
    let plane_size = D.sub_size(d, b.mi_size, sx, sy)
    let n4w = D.n4w(d, plane_size)
    let n4h = D.n4h(d, plane_size)
    var p: INTRA.IntraParams = zero
    p.mode = u32(mode)
    p.have_left = b.avail_l
    p.have_above = b.avail_u
    if plane > 0usize {
        p.have_left = b.avail_l_chroma
        p.have_above = b.avail_u_chroma
    }
    p.have_above_right = d.block_decoded[plane][usize((sub_row >> u32(sy)) - 1i32 + 1i32) * 35usize + usize((sub_col >> u32(sx)) + n4w + 1i32)] == 1u8
    p.have_below_left = d.block_decoded[plane][usize((sub_row >> u32(sy)) + n4h + 1i32) * 35usize + usize((sub_col >> u32(sx)) - 1i32 + 1i32)] == 1u8
    p.max_x = ((d.mi_cols * 4i32) >> u32(sx)) - 1i32
    p.max_y = ((d.mi_rows * 4i32) >> u32(sy)) - 1i32
    p.bit_depth = u32(d.st.seq.bit_depth)
    p.edge_filter = d.st.seq.enable_intra_edge_filter
    if p.edge_filter {
        var pl_avail_u = b.avail_u
        var pl_avail_l = b.avail_l
        if plane > 0usize {
            pl_avail_u = b.avail_u_chroma
            pl_avail_l = b.avail_l_chroma
        }
        p.above_smooth = D.is_smooth_above(d, plane, pl_avail_u)
        p.left_smooth = D.is_smooth_left(d, plane, pl_avail_l)
    }
    try INTRA.predict_intra(d.frame[plane], stride, usize(g.x), usize(g.y), u32(D.mi_wlog2(d, plane_size) + 2i32), u32(D.mi_hlog2(d, plane_size) + 2i32), p)
    let (r0, r1) = IN.rounds(false, g.bit_depth)
    try IN.block_pred(d.iwk, m0, g, g.x, g.y, g.w, g.h, r0, r1, d.iwk.p0)
    if b.wedge_interintra {
        let (mask, me) = MK.wedge_mask(&d.masks, i32(b.mi_size), i32(b.wedge_sign), i32(b.wedge_index))
        if me != ok { ret me }
        ret MK.blend_interintra(dst, stride, d.iwk.p0, mask, usize(D.block_w(d, b.mi_size)), g.w, g.h, g.sub_x, g.sub_y, true, g.bit_depth, 14u32 - (r0 + r1))
    }
    try MK.interintra_mask(i32(b.interintra_mode), g.w, g.h, d.ii_mask)
    ret MK.blend_interintra(dst, stride, d.iwk.p0, d.ii_mask, usize(g.w), g.w, g.h, g.sub_x, g.sub_y, false, g.bit_depth, 14u32 - (r0 + r1))
}

fn pred_ref(d: *D.Dec, g: IN.Geom, m: IN.Motion, ref_frame: i32, out: []i32, r0: u32, r1: u32) -> err {
    let b = &d.b
    let h = &d.st.h
    let rf = usize(ref_frame)
    let gmp = d.st.h.gm_params[rf * 6usize..rf * 6usize + 6usize]
    var gv = false
    if h.gm_type[rf] > av1.TRANSLATION { gv = WP.setup_shear(gmp).valid }
    let global_mode = b.y_mode == D.GLOBALMV || b.y_mode == D.GLOBAL_GLOBALMV
    let kind = WP.use_warp(g.w, g.h, h.force_integer_mv, b.motion_mode == D.LOCALWARP, b.local_valid, global_mode, h.gm_type[rf], false, gv)
    if kind == 1i32 { ret WP.warp_block(m.frame, b.local_params[..], g.sub_x, g.sub_y, g.x, g.y, g.w, g.h, r0, r1, out) }
    if kind == 2i32 { ret WP.warp_block(m.frame, gmp, g.sub_x, g.sub_y, g.x, g.y, g.w, g.h, r0, r1, out) }
    ret IN.block_pred(d.iwk, m, g, g.x, g.y, g.w, g.h, r0, r1, out)
}

fn warp_region(d: *D.Dec, g: IN.Geom, m0: IN.Motion, m1: IN.Motion, ref0: i32, ref1: i32, compound: bool, dst: []u8, stride: usize) -> err {
    let (r0, r1) = IN.rounds(compound, g.bit_depth)
    let post = 14u32 - (r0 + r1)
    let maxv = (1i32 << g.bit_depth) - 1i32
    try pred_ref(d, g, m0, ref0, d.iwk.p0, r0, r1)
    if compound { try pred_ref(d, g, m1, ref1, d.iwk.p1, r0, r1) }
    var i = 0i32
    while i < g.h {
        var j = 0i32
        while j < g.w {
            let k = usize(i * g.w + j)
            var v = d.iwk.p0[k]
            if compound { v = IN.round2(v + d.iwk.p1[k], 1u32 + post) }
            dst[usize(i) * stride + usize(j)] = u8(D.clip3(0i32, maxv, v))
            j += 1i32
        }
        i += 1i32
    }
    ret ok
}

fn predict_region(d: *D.Dec, plane: usize, x: i32, y: i32, w: i32, h: i32, cand_row: i32, cand_col: i32, sx: i32, sy: i32) -> err {
    let b = &d.b
    let mi = &d.mi[D.mi_at(d, cand_row, cand_col)]
    let compound = i32(mi.ref1) > i32(av1.INTRA_FRAME)
    var g: IN.Geom = zero
    g.x = x
    g.y = y
    g.w = w
    g.h = h
    g.sub_x = u32(sx)
    g.sub_y = u32(sy)
    g.cur_w = d.st.h.frame_width
    g.cur_h = d.st.h.frame_height
    g.bit_depth = u32(d.st.seq.bit_depth)
    let m0 = motion_at(d, cand_row, cand_col, 0usize, plane)
    var m1 = m0
    if compound { m1 = motion_at(d, cand_row, cand_col, 1usize, plane) }
    var blend: IN.Blend = zero
    blend.kind = IN.KIND_AVERAGE
    let stride = d.stride[plane]
    let start = usize(y) * stride + usize(x)
    let dst = d.frame[plane][start..d.frame[plane].len]
    var needs_warp = b.motion_mode == D.LOCALWARP
    if (b.y_mode == D.GLOBALMV || b.y_mode == D.GLOBAL_GLOBALMV) && (d.st.h.gm_type[usize(mi.ref0)] > av1.TRANSLATION || (compound && d.st.h.gm_type[usize(mi.ref1)] > av1.TRANSLATION)) { needs_warp = true }
    if b.interintra {
        try interintra_region(d, plane, g, m0, dst, stride, sx, sy)
    } else if needs_warp {
        try warp_region(d, g, m0, m1, i32(mi.ref0), i32(mi.ref1), compound, dst, stride)
    } else {
        try IN.predict_inter(d.iwk, g, m0, m1, compound, blend, dst, stride)
    }
    if b.motion_mode == D.OBMC {
        var info: IN.ObmcInfo = zero
        info.w4 = b.bw4
        info.h4 = b.bh4
        info.log2_w = D.mi_wlog2(d, b.mi_size)
        info.log2_h = D.mi_hlog2(d, b.mi_size)
        info.cols4 = d.mi_cols - b.mi_col
        info.rows4 = d.mi_rows - b.mi_row
        info.plane_size = i32(D.sub_size(d, b.mi_size, sx, sy))
        info.avail_u = b.avail_u
        info.avail_l = b.avail_l
        fill_neighbors(d, plane, sx, sy)
        try IN.overlap(d.iwk, g, info, d.obmc_above, d.obmc_left, dst, stride)
    }
    ret ok
}

fn predict_inter_block(d: *D.Dec) -> err {
    let b = &d.b
    let seq = &d.st.seq
    if b.motion_mode == D.LOCALWARP {
        var mb: MV.Block = zero
        mb.mi_row = b.mi_row
        mb.mi_col = b.mi_col
        mb.mi_size = i32(b.mi_size)
        mb.ref0 = b.ref_frame0
        mb.ref1 = b.ref_frame1
        b.local_valid = WP.warp_estimation(mb, b.mv0_row, b.mv0_col, b.num_samples, b.cand_list[..], b.local_params[..])
        if b.local_valid { b.local_valid = WP.setup_shear(b.local_params[..]).valid }
    }
    var planes = 1usize
    if b.has_chroma { planes = 3usize }
    var plane = 0usize
    while plane < planes {
        var sx = 0i32
        var sy = 0i32
        if plane > 0usize {
            sx = seq.subsampling_x
            sy = seq.subsampling_y
        }
        let plane_size = D.sub_size(d, b.mi_size, sx, sy)
        let num_w = D.n4w(d, plane_size)
        let num_h = D.n4h(d, plane_size)
        let base_x = (b.mi_col >> u32(sx)) * 4i32
        let base_y = (b.mi_row >> u32(sy)) * 4i32
        var cand_row = (b.mi_row >> u32(sy)) << u32(sy)
        var cand_col = (b.mi_col >> u32(sx)) << u32(sx)
        var pred_w = D.block_w(d, b.mi_size) >> u32(sx)
        var pred_h = D.block_h(d, b.mi_size) >> u32(sy)
        var some_intra = false
        var r = 0i32
        while r < (num_h << u32(sy)) {
            var c = 0i32
            while c < (num_w << u32(sx)) {
                if cand_row + r < d.mi_rows && cand_col + c < d.mi_cols {
                    if i32(d.mi[D.mi_at(d, cand_row + r, cand_col + c)].ref0) == i32(av1.INTRA_FRAME) { some_intra = true }
                }
                c += 1i32
            }
            r += 1i32
        }
        if some_intra {
            pred_w = num_w * 4i32
            pred_h = num_h * 4i32
            cand_row = b.mi_row
            cand_col = b.mi_col
        }
        var rr = 0i32
        var y = 0i32
        while y < num_h * 4i32 {
            var cc = 0i32
            var x = 0i32
            while x < num_w * 4i32 {
                try predict_region(d, plane, base_x + x, base_y + y, pred_w, pred_h, cand_row + rr, cand_col + cc, sx, sy)
                cc += 1i32
                x += pred_w
            }
            rr += 1i32
            y += pred_h
        }
        plane += 1usize
    }
    ret ok
}
