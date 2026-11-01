// AV1 tile decoding: decode_tile, decode_partition and decode_block of the specification. Mode info comes from
// e.fmt.av1_modes, prediction and residual from e.fmt.av1_recon.

use e.time
use e.fmt.av1
use e.fmt.av1_sym
use e.fmt.av1_tables
use e.fmt.av1_cdf as CDF
use e.fmt.av1_dec as D
use e.fmt.av1_modes as M
use e.fmt.av1_recon as R

error Unsupported

fn partition_ctx(d: *D.Dec, r: i32, c: i32, bsize: usize) -> usize {
    let bsl = D.mi_wlog2(d, bsize)
    let avail_u = D.is_inside(d, r - 1i32, c)
    let avail_l = D.is_inside(d, r, c - 1i32)
    var above = 0usize
    var left = 0usize
    if avail_u && D.mi_wlog2(d, usize(d.mi[D.mi_at(d, r - 1i32, c)].size)) < bsl { above = 1usize }
    if avail_l && D.mi_hlog2(d, usize(d.mi[D.mi_at(d, r, c - 1i32)].size)) < bsl { left = 1usize }
    ret left * 2usize + above
}

// the partition cdf of block size `bsize` at context `ctx` (copied out of the context, N+1 entries) and its symbol count
fn partition_cdf_base(bsize: usize, d: *D.Dec) -> (usize, usize, usize) {
    let bsl = D.mi_wlog2(d, bsize)
    if bsl == 1i32 { ret (CDF.C_PARTITIONW8, 5usize, 4usize) }
    if bsl == 2i32 { ret (CDF.C_PARTITIONW16, 11usize, 10usize) }
    if bsl == 3i32 { ret (CDF.C_PARTITIONW32, 11usize, 10usize) }
    if bsl == 4i32 { ret (CDF.C_PARTITIONW64, 11usize, 10usize) }
    ret (CDF.C_PARTITIONW128, 9usize, 8usize)
}

fn pdiff(p: []u16, i: usize) -> u32 {
    var prev = 0u32
    if i > 0usize { prev = u32(p[i - 1usize]) }
    ret u32(p[i]) - prev
}

fn read_partition(d: *D.Dec, r: i32, c: i32, bsize: usize, has_rows: bool, has_cols: bool) -> usize {
    let ctx = partition_ctx(d, r, c, bsize)
    let (base, len, n) = partition_cdf_base(bsize, d)
    if has_rows && has_cols { ret D.sym(d, base, len, ctx, n) }
    if !has_rows && !has_cols { ret D.PARTITION_SPLIT }
    let p = D.cdf(d, base, len, ctx)
    var psum = 0u32
    if has_cols {
        psum = pdiff(p, D.PARTITION_VERT) + pdiff(p, D.PARTITION_SPLIT) + pdiff(p, D.PARTITION_HORZ_A) + pdiff(p, D.PARTITION_VERT_A) + pdiff(p, D.PARTITION_VERT_B)
        if bsize != D.BLOCK_128X128 { psum += pdiff(p, D.PARTITION_VERT_4) }
    } else {
        psum = pdiff(p, D.PARTITION_HORZ) + pdiff(p, D.PARTITION_SPLIT) + pdiff(p, D.PARTITION_HORZ_A) + pdiff(p, D.PARTITION_HORZ_B) + pdiff(p, D.PARTITION_VERT_A)
        if bsize != D.BLOCK_128X128 { psum += pdiff(p, D.PARTITION_HORZ_4) }
    }
    var tmp: [3]u16 = zero
    tmp[0usize] = u16(32768u32 - psum)
    tmp[1usize] = 32768u16
    let split = av1_sym.read_symbol(&d.sd, tmp[..], 2usize) == 1usize
    if split { ret D.PARTITION_SPLIT }
    if has_cols { ret D.PARTITION_HORZ }
    ret D.PARTITION_VERT
}

fn store_block(d: *D.Dec) {
    let b = &d.b
    var y = 0i32
    while y < b.bh4 {
        var x = 0i32
        while x < b.bw4 {
            let rr = b.mi_row + y
            let cc = b.mi_col + x
            if rr < d.mi_rows && cc < d.mi_cols {
                let m = &d.mi[D.mi_at(d, rr, cc)]
                m.y_mode = u8(b.y_mode)
                if b.ref_frame0 == i32(av1.INTRA_FRAME) && b.has_chroma { m.uv_mode = u8(b.uv_mode) }
                m.ref0 = i8(b.ref_frame0)
                m.ref1 = i8(b.ref_frame1)
                if b.is_inter {
                    m.comp_group_idx = u8(b.comp_group_idx)
                    m.compound_idx = u8(b.compound_idx)
                    m.interp0 = u8(b.interp0)
                    m.interp1 = u8(b.interp1)
                    m.mv0_row = i16(b.mv0_row)
                    m.mv0_col = i16(b.mv0_col)
                    m.mv1_row = i16(b.mv1_row)
                    m.mv1_col = i16(b.mv1_col)
                }
                if b.is_inter { m.is_inter = 1u8 } else { m.is_inter = 0u8 }
                if b.skip_mode { m.skip_mode = 1u8 } else { m.skip_mode = 0u8 }
                if b.skip { m.skip = 1u8 } else { m.skip = 0u8 }
                let at = D.mi_at(d, rr, cc)
                d.s_size[at] = u8(b.mi_size)
                d.s_ymode[at] = u8(b.y_mode)
                if b.is_inter { d.s_inter[at] = 1u8 } else { d.s_inter[at] = 0u8 }
                d.s_ref[at * 2usize] = i8(b.ref_frame0)
                d.s_ref[at * 2usize + 1usize] = i8(b.ref_frame1)
                if b.is_inter {
                    d.s_mv[at * 4usize] = i16(b.mv0_row)
                    d.s_mv[at * 4usize + 1usize] = i16(b.mv0_col)
                    d.s_mv[at * 4usize + 2usize] = i16(b.mv1_row)
                    d.s_mv[at * 4usize + 3usize] = i16(b.mv1_col)
                }
                m.tx_size = u8(b.tx_size)
                m.mmode = u8(b.motion_mode)
                if b.interintra { m.mmode = 9u8 }
                m.size = u8(b.mi_size)
                m.segment_id = u8(b.segment_id)
                m.delta_lf0 = i8(d.delta_lf[0usize])
                m.delta_lf1 = i8(d.delta_lf[1usize])
                m.delta_lf2 = i8(d.delta_lf[2usize])
                m.delta_lf3 = i8(d.delta_lf[3usize])
            }
            x += 1i32
        }
        y += 1i32
    }
}

fn reset_block_context(d: *D.Dec) {
    let b = &d.b
    var plane = 0usize
    var planes = 1usize
    if b.has_chroma { planes = 3usize }
    while plane < planes {
        var sx = 0i32
        var sy = 0i32
        if plane > 0usize {
            sx = d.st.seq.subsampling_x
            sy = d.st.seq.subsampling_y
        }
        var i = b.mi_col >> u32(sx)
        while i < ((b.mi_col + b.bw4) >> u32(sx)) {
            d.above_level[plane][usize(i)] = 0u8
            d.above_dc[plane][usize(i)] = 0u8
            i += 1i32
        }
        i = b.mi_row >> u32(sy)
        while i < ((b.mi_row + b.bh4) >> u32(sy)) {
            d.left_level[plane][usize(i)] = 0u8
            d.left_dc[plane][usize(i)] = 0u8
            i += 1i32
        }
        plane += 1usize
    }
}

fn decode_block(d: *D.Dec, r: i32, c: i32, sub: usize) -> err {
    let b = &d.b
    let seq = &d.st.seq
    b.mi_row = r
    b.mi_col = c
    b.mi_size = sub
    b.bw4 = D.n4w(d, sub)
    b.bh4 = D.n4h(d, sub)
    if b.bh4 == 1i32 && seq.subsampling_y == 1i32 && (r & 1i32) == 0i32 {
        b.has_chroma = false
    } else if b.bw4 == 1i32 && seq.subsampling_x == 1i32 && (c & 1i32) == 0i32 {
        b.has_chroma = false
    } else {
        b.has_chroma = seq.num_planes > 1i32
    }
    b.avail_u = D.is_inside(d, r - 1i32, c)
    b.avail_l = D.is_inside(d, r, c - 1i32)
    b.avail_u_chroma = b.avail_u
    b.avail_l_chroma = b.avail_l
    if b.has_chroma {
        if seq.subsampling_y == 1i32 && b.bh4 == 1i32 { b.avail_u_chroma = D.is_inside(d, r - 2i32, c) }
        if seq.subsampling_x == 1i32 && b.bw4 == 1i32 { b.avail_l_chroma = D.is_inside(d, r, c - 2i32) }
    } else {
        b.avail_u_chroma = false
        b.avail_l_chroma = false
    }
    b.use_filter_intra = false
    b.angle_delta_y = 0i32
    b.angle_delta_uv = 0i32
    b.uv_mode = D.DC_PRED
    b.interp0 = 0usize
    b.interp1 = 0usize
    b.motion_mode = D.SIMPLE
    b.comp_group_idx = 0usize
    b.compound_idx = 0usize
    b.mv0_row = 0i32
    b.mv0_col = 0i32
    b.mv1_row = 0i32
    b.mv1_col = 0i32
    let (tm0, cm0) = time.monotonic()
    if d.st.h.frame_is_intra {
        try M.intra_frame_mode_info(d)
    } else {
        try M.inter_frame_mode_info(d)
    }
    M.read_block_tx_size(d)
    if b.skip { reset_block_context(d) }
    if b.mi_col >= 48i32 && b.mi_row < 16i32 && b.mi_col < 64i32 && d.dbg_n < 4000usize {
        d.dbg[d.dbg_n] = b.mi_row
        d.dbg[d.dbg_n + 1usize] = b.mi_col
        d.dbg[d.dbg_n + 2usize] = i32(b.mi_size)
        d.dbg[d.dbg_n + 3usize] = i32(b.y_mode)
        d.dbg[d.dbg_n + 4usize] = b.ref_frame0
        d.dbg[d.dbg_n + 5usize] = i32(b.motion_mode)
        d.dbg[d.dbg_n + 6usize] = b.mv0_row
        d.dbg[d.dbg_n + 7usize] = b.mv0_col
        d.dbg_n += 8usize
    }
    store_block(d)
    let (tm1, cm1) = time.monotonic()
    try R.compute_prediction(d)
    let (tm2, cm2) = time.monotonic()
    try R.residual(d)
    let (tm3, cm3) = time.monotonic()
    d.ns_mode += tm1.nanos - tm0.nanos
    d.ns_pred += tm2.nanos - tm1.nanos
    d.ns_resid += tm3.nanos - tm2.nanos
    ret ok
}

fn decode_partition(d: *D.Dec, r: i32, c: i32, bsize: usize) -> err {
    if r >= d.mi_rows || c >= d.mi_cols { ret ok }
    let num4 = D.n4w(d, bsize)
    let half = num4 >> 1u32
    let quarter = half >> 1u32
    let has_rows = (r + half) < d.mi_rows
    let has_cols = (c + half) < d.mi_cols
    var partition = D.PARTITION_NONE
    if bsize >= D.BLOCK_8X8 { partition = read_partition(d, r, c, bsize, has_rows, has_cols) }
    let sub = usize(d.tab[av1_tables.T_PARTITION_SUBSIZE + partition * 22usize + bsize])
    let split_size = usize(d.tab[av1_tables.T_PARTITION_SUBSIZE + D.PARTITION_SPLIT * 22usize + bsize])
    if partition == D.PARTITION_NONE {
        try decode_block(d, r, c, sub)
    } else if partition == D.PARTITION_HORZ {
        try decode_block(d, r, c, sub)
        if has_rows { try decode_block(d, r + half, c, sub) }
    } else if partition == D.PARTITION_VERT {
        try decode_block(d, r, c, sub)
        if has_cols { try decode_block(d, r, c + half, sub) }
    } else if partition == D.PARTITION_SPLIT {
        try decode_partition(d, r, c, sub)
        try decode_partition(d, r, c + half, sub)
        try decode_partition(d, r + half, c, sub)
        try decode_partition(d, r + half, c + half, sub)
    } else if partition == D.PARTITION_HORZ_A {
        try decode_block(d, r, c, split_size)
        try decode_block(d, r, c + half, split_size)
        try decode_block(d, r + half, c, sub)
    } else if partition == D.PARTITION_HORZ_B {
        try decode_block(d, r, c, sub)
        try decode_block(d, r + half, c, split_size)
        try decode_block(d, r + half, c + half, split_size)
    } else if partition == D.PARTITION_VERT_A {
        try decode_block(d, r, c, split_size)
        try decode_block(d, r + half, c, split_size)
        try decode_block(d, r, c + half, sub)
    } else if partition == D.PARTITION_VERT_B {
        try decode_block(d, r, c, sub)
        try decode_block(d, r, c + half, split_size)
        try decode_block(d, r + half, c + half, split_size)
    } else if partition == D.PARTITION_HORZ_4 {
        try decode_block(d, r, c, sub)
        try decode_block(d, r + quarter, c, sub)
        try decode_block(d, r + quarter * 2i32, c, sub)
        if r + quarter * 3i32 < d.mi_rows { try decode_block(d, r + quarter * 3i32, c, sub) }
    } else {
        try decode_block(d, r, c, sub)
        try decode_block(d, r, c + quarter, sub)
        try decode_block(d, r, c + quarter * 2i32, sub)
        if c + quarter * 3i32 < d.mi_cols { try decode_block(d, r, c + quarter * 3i32, sub) }
    }
    ret ok
}

// decode_tile: the tile's symbol decoder and CDF context are set up by the caller; `d.row_start`.. hold its bounds
fn decode_tile(d: *D.Dec) -> err {
    var plane = 0usize
    while plane < 3usize {
        var i = 0usize
        while i < d.above_level[plane].len {
            d.above_level[plane][i] = 0u8
            d.above_dc[plane][i] = 0u8
            i += 1usize
        }
        plane += 1usize
    }
    var k = 0usize
    while k < d.above_seg_pred.len {
        d.above_seg_pred[k] = 0u8
        k += 1usize
    }
    d.delta_lf[0usize] = 0i32
    d.delta_lf[1usize] = 0i32
    d.delta_lf[2usize] = 0i32
    d.delta_lf[3usize] = 0i32
    R.reset_lr_refs(d)
    var sb = D.BLOCK_64X64
    if d.st.seq.use_128x128_superblock { sb = D.BLOCK_128X128 }
    let sb4 = D.n4w(d, sb)
    var r = d.row_start
    while r < d.row_end {
        R.clear_left_context(d)
        var c = d.col_start
        while c < d.col_end {
            d.read_deltas = d.st.h.delta_q_present
            R.clear_cdef(d, r, c)
            R.clear_block_decoded_flags(d, r, c, sb4)
            try R.read_lr(d, r, c, sb)
            try decode_partition(d, r, c, sb)
            c += sb4
        }
        r += sb4
    }
    ret ok
}
