// AV1 block reconstruction: prediction and residual (transform blocks, dequantization, inverse transform and the addition
// to the frame), the tile level context resets and the loop restoration unit syntax of the specification.

use e.time
use e.fmt.av1_pool
use e.atomic
use e.os
use e.mem
use e.fmt.av1
use e.fmt.av1_sym
use e.fmt.av1_tables
use e.fmt.av1_cdf as CDF
use e.fmt.av1_dec as D
use e.fmt.av1_coef as CO
use e.fmt.av1_txfm as TX
use e.fmt.av1_intra as IN
use e.fmt.av1_lr
use e.fmt.av1_predict as P

error Unsupported
error Invalid

// ------------------------------------------------------------------ tile level resets

fn clear_left_context(d: *D.Dec) {
    var plane = 0usize
    while plane < 3usize {
        var i = 0usize
        while i < d.left_level[plane].len {
            d.left_level[plane][i] = 0u8
            d.left_dc[plane][i] = 0u8
            i += 1usize
        }
        plane += 1usize
    }
    var k = 0usize
    while k < d.left_seg_pred.len {
        d.left_seg_pred[k] = 0u8
        k += 1usize
    }
}

fn reset_lr_refs(d: *D.Dec) {
    var plane = 0usize
    while plane < 3usize {
        d.ref_sgr_xqd[plane * 2usize] = d.tab[av1_tables.T_SGRPROJ_XQD_MID]
        d.ref_sgr_xqd[plane * 2usize + 1usize] = d.tab[av1_tables.T_SGRPROJ_XQD_MID + 1usize]
        var pass = 0usize
        while pass < 2usize {
            var i = 0usize
            while i < 3usize {
                d.ref_lr_wiener[plane * 6usize + pass * 3usize + i] = d.tab[av1_tables.T_WIENER_TAPS_MID + i]
                i += 1usize
            }
            pass += 1usize
        }
        plane += 1usize
    }
}

fn clear_cdef(d: *D.Dec, r: i32, c: i32) {
    d.cdef_idx[cdef_slot(d, r, c)] = i8(0i32 - 1i32)
    if d.st.seq.use_128x128_superblock {
        if c + 16i32 < d.mi_cols { d.cdef_idx[cdef_slot(d, r, c + 16i32)] = i8(0i32 - 1i32) }
        if r + 16i32 < d.mi_rows { d.cdef_idx[cdef_slot(d, r + 16i32, c)] = i8(0i32 - 1i32) }
        if r + 16i32 < d.mi_rows && c + 16i32 < d.mi_cols { d.cdef_idx[cdef_slot(d, r + 16i32, c + 16i32)] = i8(0i32 - 1i32) }
    }
}

fn cdef_slot(d: *D.Dec, r: i32, c: i32) -> usize {
    ret usize((r >> 4u32) * d.cdef_stride + (c >> 4u32))
}

const BD_STRIDE: usize = 35usize

fn bd_at(y: i32, x: i32) -> usize {
    ret usize(y + 1i32) * BD_STRIDE + usize(x + 1i32)
}

fn clear_block_decoded_flags(d: *D.Dec, r: i32, c: i32, sb4: i32) {
    var plane = 0usize
    while plane < usize(d.st.seq.num_planes) {
        var sx = 0i32
        var sy = 0i32
        if plane > 0usize {
            sx = d.st.seq.subsampling_x
            sy = d.st.seq.subsampling_y
        }
        let sb_w4 = (d.col_end - c) >> u32(sx)
        let sb_h4 = (d.row_end - r) >> u32(sy)
        var y = 0i32 - 1i32
        while y <= (sb4 >> u32(sy)) {
            var x = 0i32 - 1i32
            while x <= (sb4 >> u32(sx)) {
                var v = 0u8
                if y < 0i32 && x < sb_w4 {
                    v = 1u8
                } else if x < 0i32 && y < sb_h4 {
                    v = 1u8
                }
                d.block_decoded[plane][bd_at(y, x)] = v
                x += 1i32
            }
            y += 1i32
        }
        d.block_decoded[plane][bd_at(sb4 >> u32(sy), 0i32 - 1i32)] = 0u8
        plane += 1usize
    }
}

// ------------------------------------------------------------------ loop restoration syntax

fn inverse_recenter(r: i32, v: i32) -> i32 {
    if v > 2i32 * r { ret v }
    if (v & 1i32) != 0i32 { ret r - ((v + 1i32) >> 1u32) }
    ret r + (v >> 1u32)
}

fn ns_bool(d: *D.Dec, n: u32) -> u32 {
    var w = 0u32
    var x = n
    while x != 0u32 {
        x = x >> 1u32
        w += 1u32
    }
    let m = (1u32 << w) - n
    let v = D.lit(d, w - 1u32)
    if v < m { ret v }
    let extra = D.lit(d, 1u32)
    ret (v << 1u32) - m + extra
}

fn decode_subexp_bool(d: *D.Dec, num_syms: i32, k: i32) -> i32 {
    var i = 0i32
    var mk = 0i32
    while true {
        var b2 = k
        if i != 0i32 { b2 = k + i - 1i32 }
        let a = 1i32 << u32(b2)
        if num_syms <= mk + 3i32 * a {
            ret i32(ns_bool(d, u32(num_syms - mk))) + mk
        }
        if D.lit(d, 1u32) == 1u32 {
            i += 1i32
            mk += a
        } else {
            ret i32(D.lit(d, u32(b2))) + mk
        }
    }
    ret 0i32
}

fn decode_signed_subexp_with_ref_bool(d: *D.Dec, low: i32, high: i32, k: i32, r: i32) -> i32 {
    let mx = high - low
    let rr = r - low
    let v = decode_subexp_bool(d, mx, k)
    var x = 0i32
    if (rr << 1u32) <= mx { x = inverse_recenter(rr, v) } else { x = mx - 1i32 - inverse_recenter(mx - 1i32 - rr, v) }
    ret x + low
}

fn read_lr_unit(d: *D.Dec, plane: usize, unit_row: i32, unit_col: i32) {
    let h = &d.st.h
    let u = &d.lr_units[plane][usize(unit_row * d.lr_cols[plane] + unit_col)]
    var rtype = 0usize
    let frt = h.frame_restoration_type[plane]
    if frt == av1.RESTORE_WIENER {
        if D.sym(d, CDF.C_USEWIENER, 3usize, 0usize, 2usize) == 1usize { rtype = 1usize }
    } else if frt == av1.RESTORE_SGRPROJ {
        if D.sym(d, CDF.C_USESGRPROJ, 3usize, 0usize, 2usize) == 1usize { rtype = 2usize }
    } else {
        rtype = D.sym(d, CDF.C_RESTORATIONTYPE, 4usize, 0usize, 3usize)
    }
    u.rtype = u32(rtype)
    if rtype == 1usize {
        var pass = 0usize
        while pass < 2usize {
            var first = 0usize
            if plane > 0usize {
                first = 1usize
                u.wiener[pass * 3usize] = 0i32
            }
            var j = first
            while j < 3usize {
                let mn = d.tab[av1_tables.T_WIENER_TAPS_MIN + j]
                let mx = d.tab[av1_tables.T_WIENER_TAPS_MAX + j]
                let k = d.tab[av1_tables.T_WIENER_TAPS_K + j]
                let ri = plane * 6usize + pass * 3usize + j
                let v = decode_signed_subexp_with_ref_bool(d, mn, mx + 1i32, k, d.ref_lr_wiener[ri])
                u.wiener[pass * 3usize + j] = v
                d.ref_lr_wiener[ri] = v
                j += 1usize
            }
            pass += 1usize
        }
    } else if rtype == 2usize {
        let set = D.lit(d, 4u32)
        u.sgr_set = set
        var i = 0usize
        while i < 2usize {
            let radius = d.tab[av1_tables.T_SGR_PARAMS + usize(set) * 4usize + i * 2usize]
            let mn = d.tab[av1_tables.T_SGRPROJ_XQD_MIN + i]
            let mx = d.tab[av1_tables.T_SGRPROJ_XQD_MAX + i]
            var v = 0i32
            if radius != 0i32 {
                v = decode_signed_subexp_with_ref_bool(d, mn, mx + 1i32, 4i32, d.ref_sgr_xqd[plane * 2usize + i])
            } else if i == 1usize {
                v = D.clip3(mn, mx, 128i32 - d.ref_sgr_xqd[plane * 2usize])
            }
            if i == 0usize { u.xqd0 = v } else { u.xqd1 = v }
            d.ref_sgr_xqd[plane * 2usize + i] = v
            i += 1usize
        }
    }
}

fn read_lr(d: *D.Dec, r: i32, c: i32, bsize: usize) -> err {
    let h = &d.st.h
    if h.allow_intrabc { ret ok }
    let w = D.n4w(d, bsize)
    let hh = D.n4h(d, bsize)
    var plane = 0usize
    while plane < usize(d.st.seq.num_planes) {
        if h.frame_restoration_type[plane] != av1.RESTORE_NONE {
            var sx = 0i32
            var sy = 0i32
            if plane > 0usize {
                sx = d.st.seq.subsampling_x
                sy = d.st.seq.subsampling_y
            }
            if h.use_superres { ret Unsupported }
            let unit_size = h.loop_restoration_size[plane]
            let unit_rows = d.lr_rows[plane]
            let unit_cols = d.lr_cols[plane]
            let row_start = (r * (4i32 >> u32(sy)) + unit_size - 1i32) / unit_size
            let row_end = D.min_i(unit_rows, ((r + hh) * (4i32 >> u32(sy)) + unit_size - 1i32) / unit_size)
            let numerator = 4i32 >> u32(sx)
            let col_start = (c * numerator + unit_size - 1i32) / unit_size
            let col_end = D.min_i(unit_cols, ((c + w) * numerator + unit_size - 1i32) / unit_size)
            var ur = row_start
            while ur < row_end {
                var uc = col_start
                while uc < col_end {
                    read_lr_unit(d, plane, ur, uc)
                    uc += 1i32
                }
                ur += 1i32
            }
        }
        plane += 1usize
    }
    ret ok
}

// ------------------------------------------------------------------ quantizers

fn seg_active_idx(d: *D.Dec, idx: usize, feature: usize) -> bool {
    ret d.st.h.segmentation_enabled && d.st.h.feature_enabled[idx * 8usize + feature] != 0i32
}

fn get_qindex(d: *D.Dec, ignore_delta_q: bool, segment_id: usize) -> i32 {
    let h = &d.st.h
    if seg_active_idx(d, segment_id, av1.SEG_LVL_ALT_Q) {
        let data = h.feature_data[segment_id * 8usize + av1.SEG_LVL_ALT_Q]
        var q = h.base_q_idx + data
        if !ignore_delta_q && h.delta_q_present { q = d.current_q_index + data }
        ret D.clip3(0i32, 255i32, q)
    }
    if !ignore_delta_q && h.delta_q_present { ret d.current_q_index }
    ret h.base_q_idx
}

fn dc_q(d: *D.Dec, b: i32) -> i32 {
    ret d.tab[av1_tables.T_DC_QLOOKUP + usize((d.st.seq.bit_depth - 8i32) >> 1u32) * 256usize + usize(D.clip3(0i32, 255i32, b))]
}

fn ac_q(d: *D.Dec, b: i32) -> i32 {
    ret d.tab[av1_tables.T_AC_QLOOKUP + usize((d.st.seq.bit_depth - 8i32) >> 1u32) * 256usize + usize(D.clip3(0i32, 255i32, b))]
}

// ------------------------------------------------------------------ transform blocks

fn get_tx_size(d: *D.Dec, plane: usize, tx: usize) -> usize {
    if plane == 0usize { ret tx }
    let seq = &d.st.seq
    let uv_tx = usize(d.tab[av1_tables.T_MAX_TX_SIZE_RECT + D.sub_size(d, d.b.mi_size, seq.subsampling_x, seq.subsampling_y)])
    if D.tx_w(d, uv_tx) == 64i32 || D.tx_h(d, uv_tx) == 64i32 {
        if D.tx_w(d, uv_tx) == 16i32 { ret D.TX_16X32 }
        if D.tx_h(d, uv_tx) == 16i32 { ret D.TX_32X16 }
        ret D.TX_32X32
    }
    ret uv_tx
}

// the dequantisation values of the plane at the current block
fn quant_values(d: *D.Dec, plane: usize) -> (i32, i32) {
    let h = &d.st.h
    let qindex = get_qindex(d, false, d.b.segment_id)
    if plane == 0usize { ret (dc_q(d, qindex + h.delta_q_y_dc), ac_q(d, qindex)) }
    if plane == 1usize { ret (dc_q(d, qindex + h.delta_q_u_dc), ac_q(d, qindex + h.delta_q_u_ac)) }
    ret (dc_q(d, qindex + h.delta_q_v_dc), ac_q(d, qindex + h.delta_q_v_ac))
}

fn reconstruct(d: *D.Dec, plane: usize, start_x: usize, start_y: usize, tx: usize, tx_type: usize) -> err {
    let (dcq, acq) = quant_values(d, plane)
    ret reconstruct_with(d, plane, start_x, start_y, tx, tx_type, d.quant, dcq, acq, d.b.lossless)
}

// the last non-zero row and column of the coefficient block, plus one, so the transform can skip the empty part
fn nonzero_limits(q: []const i32, tw: usize, th: usize) -> (usize, usize) {
    var rows = 0usize
    var cols = 0usize
    var y = 0usize
    while y < th {
        var x = 0usize
        while x < tw {
            if q[y * tw + x] != 0i32 {
                if y + 1usize > rows { rows = y + 1usize }
                if x + 1usize > cols { cols = x + 1usize }
            }
            x += 1usize
        }
        y += 1usize
    }
    ret (rows, cols)
}

fn reconstruct_with(d: *D.Dec, plane: usize, start_x: usize, start_y: usize, tx: usize, tx_type: usize, quant: []const i32, dcq: i32, acq: i32, lossless: bool) -> err {
    var tw = usize(D.tx_w(d, tx))
    var th = usize(D.tx_h(d, tx))
    if tw > 32usize { tw = 32usize }
    if th > 32usize { th = 32usize }
    if quant.len < tw * th { ret Invalid }
    let (rows, cols) = nonzero_limits(quant, tw, th)
    try TX.reconstruct_add(quant, tx, tx_type, lossless, u32(d.st.seq.bit_depth), dcq, acq, rows, cols, d.frame[plane], d.stride[plane], start_x, start_y, d.resid)
    ret ok
}

fn push_rec(d: *D.Dec, plane: usize, x: i32, y: i32, tx: usize, tx_type: usize, eob: usize, has_intra: bool, p: IN.IntraParams, is_cfl: bool, alpha: i32, mlw: i32, mlh: i32) -> err {
    if d.rec_n >= d.recs.len { ret Unsupported }
    let r = &d.recs[d.rec_n]
    r.plane = u8(plane)
    r.tx = u8(tx)
    r.tx_type = u8(tx_type)
    r.has_intra = has_intra
    r.is_cfl = is_cfl
    r.lossless = d.b.lossless
    r.eob = u16(eob)
    r.x = x
    r.y = y
    r.alpha = alpha
    r.mlw = mlw
    r.mlh = mlh
    r.p = p
    let (dcq, acq) = quant_values(d, plane)
    r.dcq = dcq
    r.acq = acq
    r.qoff = u32(d.q_n)
    if eob > 0usize {
        var tw = usize(D.tx_w(d, tx))
        var th = usize(D.tx_h(d, tx))
        if tw > 32usize { tw = 32usize }
        if th > 32usize { th = 32usize }
        if d.q_n + tw * th > d.qpool.len { ret Unsupported }
        d.q_n += tw * th
    }
    d.rec_n += 1usize
    ret ok
}

// The pixels of one recorded transform block: its intra prediction (and chroma from luma), then the residual.
fn replay_tx(d: *D.Dec, r: *D.TxRec) -> err {
    let plane = usize(r.plane)
    let tx = usize(r.tx)
    var sx = 0u32
    var sy = 0u32
    if plane > 0usize {
        sx = u32(d.st.seq.subsampling_x)
        sy = u32(d.st.seq.subsampling_y)
    }
    if r.has_intra {
        let lw = u32(d.tab[av1_tables.T_TX_WIDTH_LOG2 + tx])
        let lh = u32(d.tab[av1_tables.T_TX_HEIGHT_LOG2 + tx])
        try IN.predict_intra(d.frame[plane], d.stride[plane], usize(r.x), usize(r.y), lw, lh, r.p)
        if r.is_cfl {
            try IN.predict_cfl(d.frame[plane], d.stride[plane], d.frame[0usize], d.stride[0usize], usize(r.x), usize(r.y), lw, lh, sx, sy, r.alpha, r.mlw, r.mlh, u32(d.st.seq.bit_depth))
        }
    }
    if r.eob > 0u16 {
        var tw = usize(D.tx_w(d, tx))
        var th = usize(D.tx_h(d, tx))
        if tw > 32usize { tw = 32usize }
        if th > 32usize { th = 32usize }
        let q = d.qpool[usize(r.qoff)..usize(r.qoff) + tw * th]
        try reconstruct_with(d, plane, usize(r.x), usize(r.y), tx, usize(r.tx_type), q, r.dcq, r.acq, r.lossless)
    }
    ret ok
}

fn replay_block(d: *D.Dec, br: *D.BRec) -> err {
    d.b = br.b
    if br.kind != 1u8 { try P.predict_inter_block(d) }
    var i = usize(br.first)
    while i < usize(br.first + br.count) {
        try replay_tx(d, &d.recs[i])
        i += 1usize
    }
    ret ok
}

const CHUNK: u32 = 8u32

// A worker of the pipeline: it takes blocks in chunks as the parse thread publishes them and makes the inter ones. The
// pool runs one of these jobs per worker thread; `i` selects the view that thread uses.
fn pipe_work(ctx: *void, i: usize) {
    let d = mem.cast[*D.Dec](ctx)
    let v = &d.views[i]
    let p = d.pipe
    while true {
        var first = 0u32
        while true {
            let seen = atomic.load(&p.claim, .Acquire)
            let (won, was) = atomic.cas(&p.claim, seen, seen + CHUNK, .AcqRel, .Acquire)
            if won {
                first = seen
                break
            }
        }
        var last = first + CHUNK
        while true {
            let published = atomic.load(&p.published, .Acquire)
            if last <= published { break }
            if atomic.load(&p.stop, .Acquire) == 1u32 {
                let final = atomic.load(&p.published, .Acquire)
                if first >= final { ret }
                if last > final { last = final }
                break
            }
            let waited = os.wait_u32(&p.published, published, 100000i64)
        }
        var k = usize(first)
        while k < usize(last) {
            if v.brecs[k].kind == 0u8 {
                let e = replay_block(v, &v.brecs[k])
                if e != ok { atomic.store(&p.failed, 1u32, .Release) }
            }
            k += 1usize
        }
    }
}

// Starts the pipeline for a frame about to be parsed with d.deferred: the pool's workers make its inter blocks while the
// parse goes on.
fn pipe_start(d: *D.Dec) -> err {
    d.pipe_on = false
    var n = d.wp.n
    if n > 8usize { n = 8usize }
    if n < 2usize { ret ok }
    atomic.store(&d.pipe.claim, 0u32, .Release)
    atomic.store(&d.pipe.published, 0u32, .Release)
    atomic.store(&d.pipe.stop, 0u32, .Release)
    atomic.store(&d.pipe.failed, 0u32, .Release)
    var i = 0usize
    while i < n {
        d.views[i] = *d
        d.views[i].iwk = d.w_work[i]
        d.views[i].obmc_above = d.w_oa[i]
        d.views[i].obmc_left = d.w_ol[i]
        d.views[i].resid = d.w_resid[i]
        d.views[i].ii_mask = d.w_iim[i]
        i += 1usize
    }
    av1_pool.submit(d.wp, n, pipe_work, mem.cast[*void](d))
    d.pipe_n = n
    d.pipe_on = true
    ret ok
}

// Called after every parsed block: lets the workers see it.
fn pipe_publish(d: *D.Dec) {
    atomic.store(&d.pipe.published, u32(d.brec_n), .Release)
    if d.brec_n % usize(CHUNK) == 0usize { os.wake_all_u32(&d.pipe.published) }
}

// Ends the pipeline: the workers finish what was published and are waited for.
fn pipe_finish(d: *D.Dec) -> err {
    if !d.pipe_on { ret ok }
    atomic.store(&d.pipe.published, u32(d.brec_n), .Release)
    atomic.store(&d.pipe.stop, 1u32, .Release)
    os.wake_all_u32(&d.pipe.published)
    av1_pool.wait(d.wp)
    d.pipe_on = false
    if atomic.load(&d.pipe.failed, .Acquire) == 1u32 { ret Invalid }
    ret ok
}

// Waits until the counter reaches `need`.
fn wf_wait(c: *Atomic[u32], need: u32) {
    while true {
        let v = atomic.load(c, .Acquire)
        if v >= need { ret }
        let waited = os.wait_u32(c, v, 100000i64)
    }
}

// A worker of the wavefront over the superblocks: a superblock is made after the one to its left and the ones above and to
// the above right, which its intra edges read.
fn wf_work(ctx: *void, i: usize) {
    let d = mem.cast[*D.Dec](ctx)
    let v = &d.views[i]
    let p = d.pipe
    let cols = p.wf_cols
    while true {
        var s = 0u32
        while true {
            let seen = atomic.load(&p.wf_next, .Acquire)
            if seen >= p.wf_total { ret }
            let (won, was) = atomic.cas(&p.wf_next, seen, seen + 1u32, .AcqRel, .Acquire)
            if won {
                s = seen
                break
            }
        }
        let sb = p.wf_order[usize(s)]
        let r = usize(sb / cols)
        let c = sb % cols
        s = sb
        wf_wait(&p.wf_done[r], c)
        if r > 0usize {
            var need = c + 2u32
            if need > cols { need = cols }
            wf_wait(&p.wf_done[r - 1usize], need)
        }
        var k = 0usize
        if s > 0u32 { k = usize(p.wf_start[usize(s) - 1usize]) }
        let end = usize(p.wf_start[usize(s)])
        while k < end {
            let e = replay_block(v, &v.brecs[usize(p.wf_idx[k])])
            if e != ok { atomic.store(&p.failed, 1u32, .Release) }
            k += 1usize
        }
        atomic.store(&p.wf_done[r], c + 1u32, .Release)
        os.wake_all_u32(&p.wf_done[r])
    }
}

// The intra and inter-intra blocks, a superblock at a time along the wavefront.
fn replay_wavefront(d: *D.Dec) -> err {
    let p = d.pipe
    var sb4 = 16i32
    if d.st.seq.use_128x128_superblock { sb4 = 32i32 }
    let cols = usize((d.mi_cols + sb4 - 1i32) / sb4)
    let rows = usize((d.mi_rows + sb4 - 1i32) / sb4)
    let total = cols * rows
    if total + 2usize > p.wf_start.len || rows + 2usize > p.wf_done.len || d.brec_n > p.wf_idx.len { ret Unsupported }
    var s = 0usize
    while s < total {
        p.wf_start[s] = 0u32
        s += 1usize
    }
    var k = 0usize
    while k < d.brec_n {
        let br = &d.brecs[k]
        if br.kind != 0u8 {
            s = usize(br.b.mi_row / sb4) * cols + usize(br.b.mi_col / sb4)
            p.wf_start[s] += 1u32
        }
        k += 1usize
    }
    var run = 0u32
    s = 0usize
    while s < total {
        let n = p.wf_start[s]
        p.wf_start[s] = run
        run += n
        s += 1usize
    }
    k = 0usize
    while k < d.brec_n {
        let br = &d.brecs[k]
        if br.kind != 0u8 {
            s = usize(br.b.mi_row / sb4) * cols + usize(br.b.mi_col / sb4)
            p.wf_idx[usize(p.wf_start[s])] = u32(k)
            p.wf_start[s] += 1u32
        }
        k += 1usize
    }
    var r = 0usize
    while r < rows {
        atomic.store(&p.wf_done[r], 0u32, .Release)
        r += 1usize
    }
    var n = 0usize
    var t = 0usize
    while t < cols + 2usize * rows {
        r = 0usize
        while r < rows && 2usize * r <= t {
            let c = t - 2usize * r
            if c < cols {
                p.wf_order[n] = u32(r * cols + c)
                n += 1usize
            }
            r += 1usize
        }
        t += 1usize
    }
    p.wf_cols = u32(cols)
    p.wf_total = u32(total)
    atomic.store(&p.wf_next, 0u32, .Release)
    atomic.store(&p.failed, 0u32, .Release)
    av1_pool.run(d.wp, d.pipe_n, wf_work, mem.cast[*void](d))
    if atomic.load(&p.failed, .Acquire) == 1u32 { ret Invalid }
    ret ok
}

// Makes the pixels of a frame parsed with d.deferred. The inter blocks were made by the pipeline while it was parsed (or are
// made here, in one thread, when no pipeline ran); then the intra and inter-intra blocks in decode order, which read
// their neighbours.
fn replay(d: *D.Dec, a: *mem.Arena, workers: usize) -> err {
    let (j0, jc0) = time.monotonic()
    try pipe_finish(d)
    let (j1, jc1) = time.monotonic()
    d.ns_join += j1.nanos - j0.nanos
    if d.pipe_n == 0usize {
        var i = 0usize
        while i < d.brec_n {
            if d.brecs[i].kind == 0u8 { try replay_block(d, &d.brecs[i]) }
            i += 1usize
        }
    }
    if d.pipe_n >= 2usize {
        try replay_wavefront(d)
    } else {
        var k = 0usize
        while k < d.brec_n {
            if d.brecs[k].kind != 0u8 { try replay_block(d, &d.brecs[k]) }
            k += 1usize
        }
    }
    let (j2, jc2) = time.monotonic()
    d.ns_c += j2.nanos - j1.nanos
    ret ok
}

fn transform_block(d: *D.Dec, plane: usize, base_x: i32, base_y: i32, tx: usize, x: i32, y: i32) -> err {
    let b = &d.b
    let seq = &d.st.seq
    let start_x = base_x + 4i32 * x
    let start_y = base_y + 4i32 * y
    var sx = 0i32
    var sy = 0i32
    if plane > 0usize {
        sx = seq.subsampling_x
        sy = seq.subsampling_y
    }
    let row = (start_y << u32(sy)) >> 2u32
    let col = (start_x << u32(sx)) >> 2u32
    var sb_mask = 15i32
    if seq.use_128x128_superblock { sb_mask = 31i32 }
    let sub_row = row & sb_mask
    let sub_col = col & sb_mask
    let step_x = D.tx_w(d, tx) >> 2u32
    let step_y = D.tx_h(d, tx) >> 2u32
    let max_x = (d.mi_cols * 4i32) >> u32(sx)
    let max_y = (d.mi_rows * 4i32) >> u32(sy)
    if start_x >= max_x || start_y >= max_y { ret ok }
    var rec_intra: IN.IntraParams = zero
    var rec_cfl = false
    var rec_alpha = 0i32
    var rec_mlw = 0i32
    var rec_mlh = 0i32
    var rec_has_intra = false
    if !b.is_inter {
        let is_cfl = plane > 0usize && b.uv_mode == D.UV_CFL_PRED
        var mode = b.y_mode
        var angle = b.angle_delta_y
        if plane > 0usize {
            angle = b.angle_delta_uv
            if is_cfl { mode = D.DC_PRED } else { mode = b.uv_mode }
        }
        var avail_l = b.avail_l
        var avail_u = b.avail_u
        if plane > 0usize {
            avail_l = b.avail_l_chroma
            avail_u = b.avail_u_chroma
        }
        var p: IN.IntraParams = zero
        p.mode = u32(mode)
        p.angle_delta = angle
        p.use_filter_intra = plane == 0usize && b.use_filter_intra
        p.filter_intra_mode = u32(b.filter_intra_mode)
        p.have_left = avail_l || x > 0i32
        p.have_above = avail_u || y > 0i32
        p.have_above_right = d.block_decoded[plane][bd_at((sub_row >> u32(sy)) - 1i32, (sub_col >> u32(sx)) + step_x)] == 1u8
        p.have_below_left = d.block_decoded[plane][bd_at((sub_row >> u32(sy)) + step_y, (sub_col >> u32(sx)) - 1i32)] == 1u8
        p.max_x = max_x - 1i32
        p.max_y = max_y - 1i32
        p.bit_depth = u32(seq.bit_depth)
        p.edge_filter = seq.enable_intra_edge_filter
        if seq.enable_intra_edge_filter {
            p.above_smooth = D.is_smooth_above(d, plane, avail_u)
            p.left_smooth = D.is_smooth_left(d, plane, avail_l)
        }
        var intra_alpha = b.cfl_alpha_u
        if plane == 2usize { intra_alpha = b.cfl_alpha_v }
        if d.deferred {
            rec_intra = p
            rec_cfl = is_cfl
            rec_alpha = intra_alpha
            rec_mlw = d.max_luma_w
            rec_mlh = d.max_luma_h
            rec_has_intra = true
        } else {
        try IN.predict_intra(d.frame[plane], d.stride[plane], usize(start_x), usize(start_y), u32(d.tab[av1_tables.T_TX_WIDTH_LOG2 + tx]), u32(d.tab[av1_tables.T_TX_HEIGHT_LOG2 + tx]), p)
        if is_cfl {
            var alpha = b.cfl_alpha_u
            if plane == 2usize { alpha = b.cfl_alpha_v }
            try IN.predict_cfl(d.frame[plane], d.stride[plane], d.frame[0usize], d.stride[0usize], usize(start_x), usize(start_y), u32(d.tab[av1_tables.T_TX_WIDTH_LOG2 + tx]), u32(d.tab[av1_tables.T_TX_HEIGHT_LOG2 + tx]), u32(sx), u32(sy), alpha, d.max_luma_w, d.max_luma_h, u32(seq.bit_depth))
        }
        }
        if plane == 0usize {
            d.max_luma_w = start_x + step_x * 4i32
            d.max_luma_h = start_y + step_y * 4i32
        }
    }
    var rec_eob = 0usize
    var rec_type = 0usize
    if !b.skip {
        var cp: CO.CoefParams = zero
        cp.plane = plane
        cp.start_x = usize(start_x)
        cp.start_y = usize(start_y)
        cp.tx_size = tx
        cp.mi_size = b.mi_size
        cp.mi_row = usize(b.mi_row)
        cp.mi_col = usize(b.mi_col)
        cp.mi_rows = usize(d.mi_rows)
        cp.mi_cols = usize(d.mi_cols)
        cp.ssx = usize(sx)
        cp.ssy = usize(sy)
        cp.is_inter = b.is_inter
        cp.reduced_tx_set = d.st.h.reduced_tx_set
        cp.lossless = b.lossless
        if d.st.h.segmentation_enabled { cp.qidx = get_qindex(d, true, b.segment_id) } else { cp.qidx = d.st.h.base_q_idx }
        cp.y_mode = b.y_mode
        cp.uv_mode = b.uv_mode
        cp.use_filter_intra = b.use_filter_intra
        cp.filter_intra_mode = b.filter_intra_mode
        cp.above_level = d.above_level[plane]
        cp.above_dc = d.above_dc[plane]
        cp.left_level = d.left_level[plane]
        cp.left_dc = d.left_dc[plane]
        cp.tx_types = d.tx_types
        cp.tx_stride = usize(d.mi_cols)
        var qv = d.quant
        if d.deferred {
            if d.q_n + 1024usize > d.qpool.len { ret Unsupported }
            qv = d.qpool[d.q_n..d.q_n + 1024usize]
        }
        let (res, coef_error) = CO.coeffs(&d.sd, d.ctx, d.tab, &cp, qv)
        if coef_error != ok { ret coef_error }
        rec_eob = res.eob
        rec_type = res.tx_type
        if !d.deferred && res.eob > 0usize { try reconstruct(d, plane, usize(start_x), usize(start_y), tx, res.tx_type) }
    }
    if d.deferred && (rec_has_intra || rec_eob > 0usize) {
        try push_rec(d, plane, start_x, start_y, tx, rec_type, rec_eob, rec_has_intra, rec_intra, rec_cfl, rec_alpha, rec_mlw, rec_mlh)
    }
    var i = 0i32
    while i < step_y {
        var j = 0i32
        while j < step_x {
            let lr = (row >> u32(sy)) + i
            let lc = (col >> u32(sx)) + j
            if lr < d.mi_rows && lc < d.mi_cols { d.lf_tx[plane][usize(lr * d.mi_cols + lc)] = u8(tx) }
            d.block_decoded[plane][bd_at((sub_row >> u32(sy)) + i, (sub_col >> u32(sx)) + j)] = 1u8
            j += 1i32
        }
        i += 1i32
    }
    ret ok
}

fn transform_tree(d: *D.Dec, start_x: i32, start_y: i32, w: i32, h: i32) -> err {
    if start_x >= d.mi_cols * 4i32 || start_y >= d.mi_rows * 4i32 { ret ok }
    let row = start_y >> 2u32
    let col = start_x >> 2u32
    let luma_tx = usize(d.mi[D.mi_at(d, row, col)].inter_tx_size)
    let luma_w = D.tx_w(d, luma_tx)
    let luma_h = D.tx_h(d, luma_tx)
    if w <= luma_w && h <= luma_h {
        let tx = fi_tx(d, w, h)
        try transform_block(d, 0usize, start_x, start_y, tx, 0i32, 0i32)
    } else if w > h {
        try transform_tree(d, start_x, start_y, w / 2i32, h)
        try transform_tree(d, start_x + w / 2i32, start_y, w / 2i32, h)
    } else if w < h {
        try transform_tree(d, start_x, start_y, w, h / 2i32)
        try transform_tree(d, start_x, start_y + h / 2i32, w, h / 2i32)
    } else {
        try transform_tree(d, start_x, start_y, w / 2i32, h / 2i32)
        try transform_tree(d, start_x + w / 2i32, start_y, w / 2i32, h / 2i32)
        try transform_tree(d, start_x, start_y + h / 2i32, w / 2i32, h / 2i32)
        try transform_tree(d, start_x + w / 2i32, start_y + h / 2i32, w / 2i32, h / 2i32)
    }
    ret ok
}

fn fi_tx(d: *D.Dec, w: i32, h: i32) -> usize {
    var tx = 0usize
    while tx < D.TX_SIZES_ALL {
        if D.tx_w(d, tx) == w && D.tx_h(d, tx) == h { break }
        tx += 1usize
    }
    ret tx
}

fn residual(d: *D.Dec) -> err {
    let b = &d.b
    let seq = &d.st.seq
    var width_chunks = b.bw4 >> 4u32
    var height_chunks = b.bh4 >> 4u32
    if width_chunks < 1i32 { width_chunks = 1i32 }
    if height_chunks < 1i32 { height_chunks = 1i32 }
    var mi_size_chunk = b.mi_size
    if width_chunks > 1i32 || height_chunks > 1i32 { mi_size_chunk = D.BLOCK_64X64 }
    var chunk_y = 0i32
    while chunk_y < height_chunks {
        var chunk_x = 0i32
        while chunk_x < width_chunks {
            let mi_row_chunk = b.mi_row + (chunk_y << 4u32)
            let mi_col_chunk = b.mi_col + (chunk_x << 4u32)
            var planes = 1usize
            if b.has_chroma { planes = 3usize }
            var plane = 0usize
            while plane < planes {
                var tx = D.TX_4X4
                if !b.lossless { tx = get_tx_size(d, plane, b.tx_size) }
                let step_x = D.tx_w(d, tx) >> 2u32
                let step_y = D.tx_h(d, tx) >> 2u32
                var sx = 0i32
                var sy = 0i32
                if plane > 0usize {
                    sx = seq.subsampling_x
                    sy = seq.subsampling_y
                }
                let plane_size = D.sub_size(d, mi_size_chunk, sx, sy)
                let num_w = D.n4w(d, plane_size)
                let num_h = D.n4h(d, plane_size)
                let base_x = (mi_col_chunk >> u32(sx)) * 4i32
                let base_y = (mi_row_chunk >> u32(sy)) * 4i32
                if b.is_inter && !b.lossless && plane == 0usize {
                    try transform_tree(d, base_x, base_y, num_w * 4i32, num_h * 4i32)
                } else {
                    let base_x_block = (b.mi_col >> u32(sx)) * 4i32
                    let base_y_block = (b.mi_row >> u32(sy)) * 4i32
                    var yy = 0i32
                    while yy < num_h {
                        var xx = 0i32
                        while xx < num_w {
                            try transform_block(d, plane, base_x_block, base_y_block, tx, xx + ((chunk_x << 4u32) >> u32(sx)), yy + ((chunk_y << 4u32) >> u32(sy)))
                            xx += step_x
                        }
                        yy += step_y
                    }
                }
                plane += 1usize
            }
            chunk_x += 1i32
        }
        chunk_y += 1i32
    }
    ret ok
}

fn compute_prediction(d: *D.Dec) -> err {
    if d.b.is_inter { ret P.predict_inter_block(d) }
    ret ok
}
