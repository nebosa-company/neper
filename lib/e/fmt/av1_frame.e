// AV1 frame decoding: the decoder object (sequence/frame header state, CDF contexts, reference slots), frame setup,
// tile groups and the sample (temporal unit) loop.

use e.mem
use e.os
use e.thread
use e.time
use e.fmt.av1
use e.fmt.av1_sym
use e.fmt.av1_tables
use e.fmt.av1_cdf as CDF
use e.fmt.av1_dec as D
use e.fmt.av1_tile as T
use e.fmt.av1_recon as R
use e.fmt.av1_mvp
use e.fmt.av1_lr
use e.fmt.av1_post
use e.fmt.av1_inter
use e.fmt.av1_mask
use e.fmt.av1_pool

error Unsupported
error Invalid

// one reference slot / output frame: three planes with a border big enough for blocks that overhang the frame
type Plane = struct { data: []u8, stride: usize, w: usize, h: usize }

type Slot = struct {
    buf: i32,
    mi_rows: i32,
    mi_cols: i32,
    ctx: []u16,
    saved_mvs: []i16,
    saved_refs: []i8,
}

const POOL: usize = 14usize

// What the backend thread of a frame needs: the decoder and which of the two frame states it works on.
type BkJob = struct {
    dc: *Decoder,
    x: usize,
    result: err,
}

type Decoder = struct {
    a: *mem.Arena,
    tab: []const i32,
    st: av1.State,
    d: D.Dec,
    st2: av1.State,
    d2: D.Dec,
    async_on: bool,
    nx: usize,
    last: usize,
    bk_running: bool,
    bk_x: usize,
    bk_job: []BkJob,
    bk_threads: []thread.Thread,
    bk_arena: mem.Arena,
    emit_on: bool,
    emit_ctx: *void,
    emit: fn(*void, usize),
    pending_shown: bool,
    ctx: []u16,
    tile_ctx: []u16,
    saved_ctx: []u16,
    slots: [8]Slot,
    pool: [14][3]Plane,
    pool_ref: [14]i32,
    pool_ready: bool,
    scratch: av1_post.Scratch,
    cur_buf: usize,
    out_buf: usize,
    hold: i32,
    ns_tile: i64,
    ns_post: i64,
    ns_setup: i64,
    mf_pool: *av1_pool.Pool,
    prof_on: bool,
    prof: [10]i64,
    shown: bool,
    frame_open: bool,
    tile_num: i32,
}

const PAD: usize = 160usize

fn alloc_plane(a: *mem.Arena, w: usize, h: usize) -> (Plane, err) {
    var p: Plane = zero
    let stride = ((w + 63usize) & ~63usize) + PAD
    let rows = ((h + 63usize) & ~63usize) + PAD
    let (data, e) = mem.alloc[u8](a, stride * rows)
    if e != ok { ret (p, e) }
    p.data = data
    p.stride = stride
    p.w = w
    p.h = h
    ret (p, ok)
}

fn init_dec(a: *mem.Arena, d: *D.Dec, threads: usize) -> err {
    d.threads = threads
    let (mvp, mvp_error) = av1_mvp.new_mvp(a)
    if mvp_error != ok { ret mvp_error }
    d.mvp = mvp
    let (q, qe) = mem.alloc[i32](a, 1024usize)
    if qe != ok { ret qe }
    let (r, re) = mem.alloc[i32](a, 8192usize)
    if re != ok { ret re }
    d.quant = q
    d.resid = r
    var p = 0usize
    while p < 3usize {
        let (bd, be) = mem.alloc[u8](a, 35usize * 35usize)
        if be != ok { ret be }
        d.block_decoded[p] = bd
        p += 1usize
    }
    ret ok
}

fn new_decoder(a: *mem.Arena) -> (Decoder, err) {
    var dc: Decoder = zero
    dc.a = a
    dc.hold = 0i32 - 1i32
    var threads = 8usize
    let (tenv, tenv_error) = os.env(a, "AV1_THREADS")
    if tenv_error == ok && tenv.len > 0usize && tenv[0usize] >= 49u8 && tenv[0usize] <= 57u8 { threads = usize(tenv[0usize] - 48u8) }
    let (penv, penv_error) = os.env(a, "AV1_PROFILE")
    if penv_error == ok && penv.len > 0usize && penv[0usize] == 49u8 { dc.prof_on = true }
    let (tab, tab_error) = av1_tables.load(a)
    if tab_error != ok { ret (dc, tab_error) }
    dc.tab = tab
    let (c0, e0) = mem.alloc[u16](a, CDF.CTX_COUNT)
    if e0 != ok { ret (dc, e0) }
    let (c1, e1) = mem.alloc[u16](a, CDF.CTX_COUNT)
    if e1 != ok { ret (dc, e1) }
    let (c2, e2) = mem.alloc[u16](a, CDF.CTX_COUNT)
    if e2 != ok { ret (dc, e2) }
    dc.ctx = c0
    dc.tile_ctx = c1
    dc.saved_ctx = c2
    CDF.init_non_coeff(dc.saved_ctx, dc.tab)
    var i = 0usize
    while i < 8usize {
        let (sc, se) = mem.alloc[u16](a, CDF.CTX_COUNT)
        if se != ok { ret (dc, se) }
        dc.slots[i].ctx = sc
        i += 1usize
    }
    let (wpool, wpool_error) = av1_pool.new_pool(a, threads - 1usize)
    if wpool_error != ok { ret (dc, wpool_error) }
    dc.d.wp = wpool
    var mf_n = threads - 1usize
    if mf_n > 4usize { mf_n = 4usize }
    let (mfp, mfp_error) = av1_pool.new_pool(a, mf_n)
    if mfp_error != ok { ret (dc, mfp_error) }
    dc.mf_pool = mfp
    dc.d2.wp = wpool
    let init0 = init_dec(a, &dc.d, threads)
    if init0 != ok { ret (dc, init0) }
    let init1 = init_dec(a, &dc.d2, threads)
    if init1 != ok { ret (dc, init1) }
    let (jobs, jobs_error) = mem.alloc[BkJob](a, 1usize)
    if jobs_error != ok { ret (dc, jobs_error) }
    dc.bk_job = jobs
    let (bthreads, bthreads_error) = mem.alloc[thread.Thread](a, 1usize)
    if bthreads_error != ok { ret (dc, bthreads_error) }
    dc.bk_threads = bthreads
    let (bk_bytes, bk_error) = mem.alloc[u8](a, 8388608usize)
    if bk_error != ok { ret (dc, bk_error) }
    dc.bk_arena = mem.arena_from(bk_bytes)
    ret (dc, ok)
}

// The frame state number x (0 or 1): its decoder state and its header state.
fn dec_of(dc: *Decoder, x: usize) -> *D.Dec {
    if x == 0usize { ret &dc.d }
    ret &dc.d2
}

fn st_of(dc: *Decoder, x: usize) -> *av1.State {
    if x == 0usize { ret &dc.st }
    ret &dc.st2
}

// arrays that live as long as the stream: the frame size is fixed for now
fn alloc_frame_state(dc: *Decoder, d: *D.Dec, h: *const av1.Hdr, with_slots: bool) -> err {
    let a = dc.a
    var p = 0usize
    let n = usize(h.mi_rows * h.mi_cols)
    let (mi, mie) = mem.alloc[D.Mi](a, n)
    if mie != ok { ret mie }
    d.mi = mi
    let (s0, e0) = mem.alloc[u8](a, n)
    if e0 != ok { ret e0 }
    let (s1, e1) = mem.alloc[u8](a, n)
    if e1 != ok { ret e1 }
    let (s2, e2) = mem.alloc[u8](a, n)
    if e2 != ok { ret e2 }
    let (s3, e3) = mem.alloc[i8](a, n * 2usize)
    if e3 != ok { ret e3 }
    let (mfr, mfre) = mem.alloc[i8](a, n)
    if mfre != ok { ret mfre }
    let (mfm, mfme) = mem.alloc[i16](a, n * 2usize)
    if mfme != ok { ret mfme }
    d.mf_refs = mfr
    d.mf_mvs = mfm
    let (mfield, mfielde) = mem.alloc[i16](a, 8usize * usize((h.mi_rows >> 1u32) * (h.mi_cols >> 1u32)) * 2usize)
    if mfielde != ok { ret mfielde }
    d.motion_field = mfield
    var sl = 0usize
    while sl < 8usize && with_slots {
        let (smv, smve) = mem.alloc[i16](a, n * 2usize)
        if smve != ok { ret smve }
        let (srf, srfe) = mem.alloc[i8](a, n)
        if srfe != ok { ret srfe }
        dc.slots[sl].saved_mvs = smv
        dc.slots[sl].saved_refs = srf
        sl += 1usize
    }
    let mi_count = usize(h.mi_rows * h.mi_cols)
    let (recs, recs_error) = mem.alloc[D.TxRec](a, mi_count * 3usize / 2usize + 1024usize)
    if recs_error != ok { ret recs_error }
    d.recs = recs
    let (brecs, brecs_error) = mem.alloc[D.BRec](a, mi_count + 16usize)
    if brecs_error != ok { ret brecs_error }
    d.brecs = brecs
    let (qpool, qpool_error) = mem.alloc[i32](a, mi_count * 24usize + 4096usize)
    if qpool_error != ok { ret qpool_error }
    d.qpool = qpool
    let (pipes, pipes_error) = mem.alloc[D.Pipe](a, 1usize)
    if pipes_error != ok { ret pipes_error }
    d.pipe = &pipes[0usize]
    let sbs = usize((h.mi_rows + 15i32) >> 4u32) * usize((h.mi_cols + 15i32) >> 4u32) + 2usize
    let (wfs, wfs_error) = mem.alloc[u32](a, sbs)
    if wfs_error != ok { ret wfs_error }
    d.pipe.wf_start = wfs
    let (wfo, wfo_error) = mem.alloc[u32](a, sbs)
    if wfo_error != ok { ret wfo_error }
    d.pipe.wf_order = wfo
    let (wfi, wfi_error) = mem.alloc[u32](a, mi_count + 16usize)
    if wfi_error != ok { ret wfi_error }
    d.pipe.wf_idx = wfi
    let (wfd, wfd_error) = mem.alloc[Atomic[u32]](a, usize((h.mi_rows + 15i32) >> 4u32) + 2usize)
    if wfd_error != ok { ret wfd_error }
    d.pipe.wf_done = wfd
    let (pjobs, pjobs_error) = mem.alloc[D.PipeJob](a, 8usize)
    if pjobs_error != ok { ret pjobs_error }
    d.pipe_jobs = pjobs
    let (pthreads, pthreads_error) = mem.alloc[thread.Thread](a, 8usize)
    if pthreads_error != ok { ret pthreads_error }
    d.pipe_threads = pthreads
    let (views, views_error) = mem.alloc[D.Dec](a, 8usize)
    if views_error != ok { ret views_error }
    d.views = views
    var wi = 0usize
    while wi < 8usize {
        let (w_wk, w_wke) = av1_inter.new_work(a)
        if w_wke != ok { ret w_wke }
        d.w_work[wi] = w_wk
        let (w_oa, w_oae) = mem.alloc[av1_inter.Neighbor](a, 32usize)
        if w_oae != ok { ret w_oae }
        let (w_ol, w_ole) = mem.alloc[av1_inter.Neighbor](a, 32usize)
        if w_ole != ok { ret w_ole }
        let (w_rs, w_rse) = mem.alloc[i32](a, 8192usize)
        if w_rse != ok { ret w_rse }
        d.w_oa[wi] = w_oa
        d.w_ol[wi] = w_ol
        d.w_resid[wi] = w_rs
        let (w_im, w_ime) = mem.alloc[u8](a, 16384usize)
        if w_ime != ok { ret w_ime }
        d.w_iim[wi] = w_im
        wi += 1usize
    }
    let (wk, wke) = av1_inter.new_work(a)
    if wke != ok { ret wke }
    d.iwk = wk
    let (mk, mke) = av1_mask.new_masks(a)
    if mke != ok { ret mke }
    d.masks = mk
    let (iim, iime) = mem.alloc[u8](a, 16384usize)
    if iime != ok { ret iime }
    d.ii_mask = iim
    let (oa, oae) = mem.alloc[av1_inter.Neighbor](a, 32usize)
    if oae != ok { ret oae }
    let (ol, ole) = mem.alloc[av1_inter.Neighbor](a, 32usize)
    if ole != ok { ret ole }
    d.obmc_above = oa
    d.obmc_left = ol
    let (s4, e4) = mem.alloc[i16](a, n * 4usize)
    if e4 != ok { ret e4 }
    d.s_size = s0
    d.s_ymode = s1
    d.s_inter = s2
    d.s_ref = s3
    d.s_mv = s4
    let (tt, tte) = mem.alloc[u8](a, n)
    if tte != ok { ret tte }
    d.tx_types = tt
    p = 0usize
    while p < 3usize {
        let (lf, lfe) = mem.alloc[u8](a, n)
        if lfe != ok { ret lfe }
        d.lf_tx[p] = lf
        let (al, ale) = mem.alloc[u8](a, usize(h.mi_cols) + 40usize)
        if ale != ok { ret ale }
        let (ad, ade) = mem.alloc[u8](a, usize(h.mi_cols) + 40usize)
        if ade != ok { ret ade }
        let (ll, lle) = mem.alloc[u8](a, usize(h.mi_rows) + 40usize)
        if lle != ok { ret lle }
        let (ld, lde) = mem.alloc[u8](a, usize(h.mi_rows) + 40usize)
        if lde != ok { ret lde }
        d.above_level[p] = al
        d.above_dc[p] = ad
        d.left_level[p] = ll
        d.left_dc[p] = ld
        p += 1usize
    }
    let (asp, aspe) = mem.alloc[u8](a, usize(h.mi_cols) + 40usize)
    if aspe != ok { ret aspe }
    let (lsp, lspe) = mem.alloc[u8](a, usize(h.mi_rows) + 40usize)
    if lspe != ok { ret lspe }
    d.above_seg_pred = asp
    d.left_seg_pred = lsp
    d.cdef_stride = (h.mi_cols + 15i32) >> 4u32
    let (ci, cie) = mem.alloc[i8](a, usize(d.cdef_stride * ((h.mi_rows + 15i32) >> 4u32)))
    if cie != ok { ret cie }
    d.cdef_idx = ci
    p = 0usize
    while p < 3usize {
        let cap = usize((h.mi_cols * 4i32 / 32i32 + 3i32) * (h.mi_rows * 4i32 / 32i32 + 3i32))
        let (lu, lue) = mem.alloc[av1_lr.LrUnit](a, cap)
        if lue != ok { ret lue }
        d.lr_units[p] = lu
        p += 1usize
    }
    if with_slots {
        let (sc, sce) = av1_post.new_scratch(a, n)
        if sce != ok { ret sce }
        dc.scratch = sc
    }
    ret ok
}

fn recount(dc: *Decoder) {
    var k = 0usize
    while k < POOL {
        dc.pool_ref[k] = 0i32
        k += 1usize
    }
    var i = 0usize
    while i < 8usize {
        if dc.slots[i].buf >= 0i32 { dc.pool_ref[usize(dc.slots[i].buf)] += 1i32 }
        i += 1usize
    }
}

// Stage timers (AV1_PROFILE=1): nanoseconds per frame stage in dc.prof, see PROF_NAMES in the tools that print them.
// 0 headers, 1 setup_frame, 2 tile context copies, 3 save after parse, 4 replay (backend), 5 backend buffer bind and pipeline start,
// 6 buffer acquire, 7 reference update after the post filters
fn tick(dc: *Decoder) -> i64 {
    if !dc.prof_on { ret 0i64 }
    let (t, c) = time.monotonic()
    ret t.nanos
}

fn lap(dc: *Decoder, k: usize, t0: i64) {
    if !dc.prof_on { ret }
    let (t, c) = time.monotonic()
    dc.prof[k] += t.nanos - t0
}

fn acquire(dc: *Decoder) -> usize {
    var k = 0usize
    while k < POOL {
        if dc.pool_ref[k] == 0i32 {
            dc.pool_ref[k] = 1i32
            ret k
        }
        k += 1usize
    }
    ret 0usize
}

fn planes_of(dc: *Decoder, k: usize) -> [3][]u8 {
    var out: [3][]u8 = zero
    out[0usize] = dc.pool[k][0usize].data
    out[1usize] = dc.pool[k][1usize].data
    out[2usize] = dc.pool[k][2usize].data
    ret out
}

// Gives the frame about to be made its pixel buffer and the reference planes it predicts from.
fn bind_buffers(dc: *Decoder, d: *D.Dec) {
    dc.cur_buf = acquire(dc)
    var p = 0usize
    while p < 3usize {
        d.frame[p] = dc.pool[dc.cur_buf][p].data
        d.stride[p] = dc.pool[dc.cur_buf][p].stride
        p += 1usize
    }
    var rs = 0usize
    while rs < 8usize {
        if dc.slots[rs].buf >= 0i32 {
            var q = 0usize
            while q < 3usize {
                d.ref_planes[rs][q] = dc.pool[usize(dc.slots[rs].buf)][q].data
                q += 1usize
            }
        }
        rs += 1usize
    }
    d.ref_stride[0usize] = dc.pool[dc.cur_buf][0usize].stride
    d.ref_stride[1usize] = dc.pool[dc.cur_buf][1usize].stride
    d.ref_stride[2usize] = dc.pool[dc.cur_buf][2usize].stride
}

fn alloc_pool(dc: *Decoder, h: *const av1.Hdr) -> err {
    let a = dc.a
    var k = 0usize
    while k < POOL {
        var q = 0usize
        while q < 3usize {
            var pw = usize(h.mi_cols) * 4usize
            var ph = usize(h.mi_rows) * 4usize
            if q > 0usize {
                pw = pw / 2usize
                ph = ph / 2usize
            }
            let (pl, ple) = alloc_plane(a, pw, ph)
            if ple != ok { ret ple }
            dc.pool[k][q] = pl
            dc.pool[k][q].w = usize(h.frame_width)
            dc.pool[k][q].h = usize(h.frame_height)
            if q > 0usize {
                dc.pool[k][q].w = (usize(h.frame_width) + 1usize) >> 1u32
                dc.pool[k][q].h = (usize(h.frame_height) + 1usize) >> 1u32
            }
            q += 1usize
        }
        dc.pool_ref[k] = 0i32
        k += 1usize
    }
    k = 0usize
    while k < 8usize {
        dc.slots[k].buf = 0i32 - 1i32
        k += 1usize
    }
    dc.pool_ready = true
    dc.hold = 0i32 - 1i32
    ret ok
}

// per frame state x: arrays at MI resolution and the contexts of the tile
fn clear_mi(d: *D.Dec) {
    let n = d.mi.len
    var zero_mi: D.Mi = zero
    var i = 0usize
    while i < n {
        d.mi[i] = zero_mi
        d.s_size[i] = 0u8
        d.s_ymode[i] = 0u8
        d.s_inter[i] = 0u8
        d.s_ref[i * 2usize] = i8(0i32 - 2i32)
        d.s_ref[i * 2usize + 1usize] = i8(0i32 - 2i32)
        i += 1usize
    }
}

fn setup_frame(dc: *Decoder, x: usize) -> err {
    let st = st_of(dc, x)
    let h = &st.h
    let seq = &st.seq
    let d = dec_of(dc, x)
    if seq.bit_depth != 8i32 || seq.subsampling_x != 1i32 || seq.subsampling_y != 1i32 || seq.mono_chrome { ret Unsupported }
    if h.using_qmatrix || h.use_superres || h.apply_grain { ret Unsupported }
    d.st = st
    d.tab = dc.tab
    d.mi_rows = h.mi_rows
    d.mi_cols = h.mi_cols
    if d.mi.len == 0usize {
        try alloc_frame_state(dc, d, h, dc.d.mi.len == 0usize && dc.d2.mi.len == 0usize)
        if dc.async_on {
            let other = dec_of(dc, 1usize - x)
            if other.mi.len == 0usize { try alloc_frame_state(dc, other, h, false) }
        }
    }
    if usize(h.mi_rows * h.mi_cols) != d.mi.len { ret Unsupported }
    d.mi_rows = h.mi_rows
    d.mi_cols = h.mi_cols
    d.cdef_stride = (h.mi_cols + 15i32) >> 4u32
    let tm = tick(dc)
    clear_mi(d)
    lap(dc, 8usize, tm)
    var i = 0usize
    // loop restoration units
    var p = 0usize
    while p < usize(seq.num_planes) {
        if h.frame_restoration_type[p] != av1.RESTORE_NONE {
            var sx = 0i32
            var sy = 0i32
            if p > 0usize {
                sx = seq.subsampling_x
                sy = seq.subsampling_y
            }
            let unit = h.loop_restoration_size[p]
            let cw = (h.upscaled_width + sx) >> u32(sx)
            let ch = (h.frame_height + sy) >> u32(sy)
            d.lr_cols[p] = i32(av1_lr.count_units(u32(unit), u32(cw)))
            d.lr_rows[p] = i32(av1_lr.count_units(u32(unit), u32(ch)))
        }
        p += 1usize
    }
    if !dc.pool_ready { try alloc_pool(dc, h) }
    // the mv prediction view of the frame
    let m = &d.mvf
    m.mi_rows = h.mi_rows
    m.mi_cols = h.mi_cols
    m.mi_sizes = d.s_size
    m.y_modes = d.s_ymode
    m.is_inters = d.s_inter
    m.ref_frames = d.s_ref
    m.mvs = d.s_mv
    m.order_hint = h.order_hint
    m.order_hint_bits = u32(seq.order_hint_bits)
    m.order_hints = h.order_hints[..]
    m.sign_bias = h.ref_frame_sign_bias[..]
    m.gm_type = h.gm_type[..]
    m.gm_params = h.gm_params[..]
    m.force_integer_mv = h.force_integer_mv
    m.allow_high_precision_mv = h.allow_high_precision_mv
    m.use_ref_frame_mvs = h.use_ref_frame_mvs
    if h.use_ref_frame_mvs {
        var k = 0usize
        while k < 8usize {
            d.mf_slots[k].mi_rows = dc.slots[k].mi_rows
            d.mf_slots[k].mi_cols = dc.slots[k].mi_cols
            d.mf_slots[k].frame_type = st.refs[k].frame_type
            d.mf_slots[k].mvs = dc.slots[k].saved_mvs
            d.mf_slots[k].ref_frames = dc.slots[k].saved_refs
            d.mf_slots[k].order_hints = st.refs[k].saved_order_hints[..]
            k += 1usize
        }
        m.ref_frame_idx = h.ref_frame_idx[..]
        m.slots = d.mf_slots[..]
        let tf = tick(dc)
        av1_mvp.motion_field_estimation_pool(m, d.motion_field, dc.mf_pool)
        lap(dc, 9usize, tf)
        m.motion_field = d.motion_field
    }
    // cdfs of the frame
    if h.primary_ref_frame == av1.PRIMARY_REF_NONE {
        CDF.init_non_coeff(dc.ctx, dc.tab)
        var idx = 3usize
        if h.base_q_idx <= 20i32 {
            idx = 0usize
        } else if h.base_q_idx <= 60i32 {
            idx = 1usize
        } else if h.base_q_idx <= 120i32 {
            idx = 2usize
        }
        CDF.init_coeff(dc.ctx, dc.tab, idx)
    } else {
        let slot = &dc.slots[usize(h.ref_frame_idx[usize(h.primary_ref_frame)])]
        i = 0usize
        while i < CDF.SAVED_COUNT {
            dc.ctx[i] = slot.ctx[i]
            i += 1usize
        }
        zero_counters(dc.ctx, dc.tab)
    }
    dc.tile_num = 0i32
    d.deferred = d.threads > 1usize
    d.rec_n = 0usize
    d.brec_n = 0usize
    d.q_n = 0usize
    d.pipe_n = 0usize
    d.pipe_on = false
    if !dc.async_on {
        bind_buffers(dc, d)
        if d.deferred { try R.pipe_start(d) }
    }
    ret ok
}

// load_cdfs: the symbol counter, the last entry of every cdf, is set to zero. A cdf ends where its value reaches 32768.
fn zero_counters(ctx: []u16, tab: []const i32) {
    var i = 0usize
    while i < CDF.SAVED_COUNT {
        if ctx[i] == 32768u16 {
            ctx[i + 1usize] = 0u16
            i += 2usize
        } else {
            i += 1usize
        }
    }
}

fn le_bytes(d: []const u8, at: usize, n: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < n {
        v = v | (usize(d[at + i]) << u32(8usize * i))
        i += 1usize
    }
    ret v
}

// a tile group OBU payload (after the frame header for OBU_FRAME): decodes its tiles
fn tile_group(dc: *Decoder, x: usize, data: []const u8) -> err {
    let h = &st_of(dc, x).h
    let d = dec_of(dc, x)
    let num_tiles = h.tile_cols * h.tile_rows
    var b = av1.bits_of(data)
    var tg_start = 0i32
    var tg_end = num_tiles - 1i32
    if num_tiles > 1i32 {
        if av1.flag(&b) {
            let bits = u32(h.tile_cols_log2 + h.tile_rows_log2)
            tg_start = av1.fi(&b, bits)
            tg_end = av1.fi(&b, bits)
        }
    }
    var at = (b.at + 7usize) >> 3u32
    var tile = tg_start
    while tile <= tg_end {
        let tile_row = tile / h.tile_cols
        let tile_col = tile % h.tile_cols
        var size = data.len - at
        if tile != tg_end {
            size = le_bytes(data, at, usize(h.tile_size_bytes)) + 1usize
            at += usize(h.tile_size_bytes)
        }
        if at + size > data.len { ret Invalid }
        d.row_start = h.mi_row_starts[usize(tile_row)]
        d.row_end = h.mi_row_starts[usize(tile_row + 1i32)]
        d.col_start = h.mi_col_starts[usize(tile_col)]
        d.col_end = h.mi_col_starts[usize(tile_col + 1i32)]
        d.current_q_index = h.base_q_idx
        let tc = tick(dc)
        var i = 0usize
        while i < CDF.CTX_COUNT {
            dc.tile_ctx[i] = dc.ctx[i]
            i += 1usize
        }
        i = CDF.SAVED_COUNT
        while i < CDF.CTX_COUNT {
            dc.tile_ctx[i] = dc.saved_ctx[i]
            i += 1usize
        }
        d.ctx = dc.tile_ctx
        lap(dc, 2usize, tc)
        d.sd = av1_sym.init_symbol(data[at..at + size], h.disable_cdf_update)
        let (t0, c0) = time.monotonic()
        let tile_result = T.decode_tile(d)
        if tile_result != ok {
            let stopped = R.pipe_finish(d)
            ret tile_result
        }
        let (t1, c1) = time.monotonic()
        dc.ns_tile += t1.nanos - t0.nanos
        if !h.disable_frame_end_update_cdf && tile == h.context_update_tile_id {
            i = 0usize
            while i < CDF.SAVED_COUNT {
                dc.saved_ctx[i] = dc.tile_ctx[i]
                i += 1usize
            }
        }
        at += size
        tile += 1i32
    }
    if tg_end == num_tiles - 1i32 {
        if !h.disable_frame_end_update_cdf {
            var i = 0usize
            while i < CDF.SAVED_COUNT {
                dc.ctx[i] = dc.saved_ctx[i]
                i += 1usize
            }
        }
        dc.frame_open = false
        ret frame_parsed(dc, x)
    }
    ret ok
}

// The frame is parsed: what the next frame's parse needs (cdfs, motion vectors, reference header state) is saved now,
// then the pixels are made and filtered: at once, or on a backend thread while the next frame is parsed.
fn frame_parsed(dc: *Decoder, x: usize) -> err {
    let st = st_of(dc, x)
    let h = &st.h
    let d = dec_of(dc, x)
    let tv = tick(dc)
    save_motion(dc, d, st)
    av1.save_refs(st)
    var i = 0usize
    while i < 8usize {
        if ((h.refresh_frame_flags >> u32(i)) & 1i32) != 0i32 {
            dc.slots[i].mi_rows = h.mi_rows
            dc.slots[i].mi_cols = h.mi_cols
            let nm = d.mi.len
            mem.copy[i8](dc.slots[i].saved_refs[0usize..nm], d.mf_refs[0usize..nm])
            mem.copy[i16](dc.slots[i].saved_mvs[0usize..nm * 2usize], d.mf_mvs[0usize..nm * 2usize])
            var k = 0usize
            while k < CDF.SAVED_COUNT {
                dc.slots[i].ctx[k] = dc.ctx[k]
                k += 1usize
            }
        }
        i += 1usize
    }
    dc.last = x
    lap(dc, 3usize, tv)
    if !dc.async_on {
        ret backend(dc, x)
    }
    try finish_backend(dc)
    dc.bk_job[0usize] = BkJob { dc: dc, x: x, result: ok }
    let (th, spawn_error) = thread.spawn[BkJob](bk_main, &dc.bk_job[0usize], 8388608usize)
    if spawn_error != ok { ret spawn_error }
    dc.bk_threads[0usize] = th
    dc.bk_running = true
    dc.bk_x = x
    ret ok
}

fn bk_main(job: *BkJob) {
    job.result = backend(job.dc, job.x)
}

// Waits for the backend thread, if one runs, and hands over the finished frame.
fn finish_backend(dc: *Decoder) -> err {
    if !dc.bk_running { ret ok }
    let joined = thread.join(dc.bk_threads[0usize])
    dc.bk_running = false
    if joined != ok { ret joined }
    if dc.bk_job[0usize].result != ok { ret dc.bk_job[0usize].result }
    if dc.shown && dc.emit_on { dc.emit(dc.emit_ctx, dc.out_buf) }
    ret ok
}

// Makes the pixels of the frame in state x, filters them and puts it into its reference slots.
fn backend(dc: *Decoder, x: usize) -> err {
    let st = st_of(dc, x)
    let d = dec_of(dc, x)
    if dc.async_on {
        dc.hold = 0i32 - 1i32
        let tb = tick(dc)
        recount(dc)
        bind_buffers(dc, d)
        if d.deferred {
            try R.pipe_start(d)
            R.pipe_publish(d)
        }
        lap(dc, 5usize, tb)
    }
    if d.deferred {
        let tr = tick(dc)
        let replayed = R.replay(d, dc.a, d.threads)
        lap(dc, 4usize, tr)
        if replayed != ok { ret replayed }
    }
    ret finish_frame(dc, x)
}

// motion field motion vector storage (7.19) and the reference update: the finished frame goes into the slots named by
// refresh_frame_flags
fn finish_frame(dc: *Decoder, x: usize) -> err {
    let h = &st_of(dc, x).h
    let d = dec_of(dc, x)
    let tq = tick(dc)
    let w1 = acquire(dc)
    let w2 = acquire(dc)
    lap(dc, 6usize, tq)
    let (p0, pc0) = time.monotonic()
    let (which, post_error) = av1_post.post_filter(d, dc.a, &dc.scratch, planes_of(dc, w1), planes_of(dc, w2))
    let (p1, pc1) = time.monotonic()
    dc.ns_post += p1.nanos - p0.nanos
    if post_error != ok { ret post_error }
    let tu = tick(dc)
    var final = dc.cur_buf
    if which == 1usize { final = w1 }
    if which == 2usize { final = w2 }
    if w1 != final { dc.pool_ref[w1] = 0i32 }
    if w2 != final { dc.pool_ref[w2] = 0i32 }
    if dc.cur_buf != final { dc.pool_ref[dc.cur_buf] = 0i32 }
    dc.out_buf = final
    var i = 0usize
    while i < 8usize {
        if ((h.refresh_frame_flags >> u32(i)) & 1i32) != 0i32 {
            let old = dc.slots[i].buf
            if old >= 0i32 { dc.pool_ref[usize(old)] -= 1i32 }
            dc.slots[i].buf = i32(final)
            dc.pool_ref[final] += 1i32
        }
        i += 1usize
    }
    recount(dc)
    dc.pool_ref[final] += 1i32
    dc.hold = i32(final)
    dc.shown = h.show_frame
    lap(dc, 7usize, tu)
    ret ok
}

fn save_motion(dc: *Decoder, d: *D.Dec, st: *av1.State) {
    let h = &st.h
    let n = d.mi.len
    // a reference's vectors are kept when it lies in the past
    var keep: [8]bool = zero
    var r = 1usize
    while r < 8usize {
        let ref_idx = usize(h.ref_frame_idx[r - av1.LAST_FRAME])
        keep[r] = av1.get_relative_dist(&st.seq, st.refs[ref_idx].order_hint, h.order_hint) < 0i32
        r += 1usize
    }
    var i = 0usize
    @nocheck {
    while i < n {
        var ref_out = i8(0i32 - 1i32)
        var mv_row = 0i16
        var mv_col = 0i16
        var list = 0usize
        while list < 2usize {
            let rf = i32(d.s_ref[i * 2usize + list])
            if rf > i32(av1.INTRA_FRAME) && keep[usize(rf)] {
                let mr = i32(d.s_mv[i * 4usize + list * 2usize])
                let mc = i32(d.s_mv[i * 4usize + list * 2usize + 1usize])
                if D.abs_i(mr) <= 4095i32 && D.abs_i(mc) <= 4095i32 {
                    ref_out = i8(rf)
                    mv_row = i16(mr)
                    mv_col = i16(mc)
                }
            }
            list += 1usize
        }
        d.mf_refs[i] = ref_out
        d.mf_mvs[i * 2usize] = mv_row
        d.mf_mvs[i * 2usize + 1usize] = mv_col
        i += 1usize
    }
    }
}

// one temporal unit's worth of OBUs (an MP4 sample). In the plain mode it sets dc.shown when a frame is output; in the async
// mode (dc.async_on) the frames come out through dc.emit as their backends finish, and flush ends the stream.
fn decode_sample(dc: *Decoder, sample: []const u8) -> err {
    var at = 0usize
    if !dc.async_on {
        dc.shown = false
        dc.hold = 0i32 - 1i32
        recount(dc)
    }
    var x = 0usize
    if dc.async_on { x = dc.nx }
    while at < sample.len {
        let (o, next, obu_error) = av1.read_obu(sample, at)
        if obu_error != ok { ret obu_error }
        at = next
        if o.kind == av1.OBU_SEQUENCE_HEADER {
            var b = av1.bits_of(o.payload)
            try av1.sequence_header(&b, &st_of(dc, dc.last).seq)
        } else if o.kind == av1.OBU_FRAME || o.kind == av1.OBU_FRAME_HEADER {
            if dc.async_on {
                x = dc.nx
                st_of(dc, x).seq = st_of(dc, dc.last).seq
                st_of(dc, x).refs = st_of(dc, dc.last).refs
                st_of(dc, x).h = st_of(dc, dc.last).h
            }
            let st = st_of(dc, x)
            st.temporal_id = o.temporal_id
            st.spatial_id = o.spatial_id
            var b = av1.bits_of(o.payload)
            let th = tick(dc)
            try av1.uncompressed_header(&b, st)
            lap(dc, 0usize, th)
            if st.h.show_existing_frame {
                if st.h.frame_type == av1.KEY_FRAME { ret Unsupported }
                try finish_backend(dc)
                let shown_buf = dc.slots[usize(st.h.frame_to_show_map_idx)].buf
                if shown_buf < 0i32 { ret Invalid }
                dc.out_buf = usize(shown_buf)
                dc.pool_ref[dc.out_buf] += 1i32
                dc.hold = shown_buf
                dc.shown = true
                if dc.async_on && dc.emit_on { dc.emit(dc.emit_ctx, dc.out_buf) }
                continue
            }
            let ts = tick(dc)
            try setup_frame(dc, x)
            lap(dc, 1usize, ts)
            dc.frame_open = true
            if dc.async_on { dc.nx = 1usize - x }
            if o.kind == av1.OBU_FRAME {
                let off = (b.at + 7usize) >> 3u32
                try tile_group(dc, x, o.payload[off..o.payload.len])
            }
        } else if o.kind == av1.OBU_TILE_GROUP {
            try tile_group(dc, x, o.payload)
        }
    }
    ret ok
}

// Ends an async stream: the last frame is finished and handed over.
fn flush(dc: *Decoder) -> err {
    ret finish_backend(dc)
}

// Ends the decoder: the backend thread and the worker pool are stopped. Call it before the decoder's arena is reset or
// released.
fn close(dc: *Decoder) -> err {
    let flushed = finish_backend(dc)
    let mf_closed = av1_pool.close(dc.mf_pool)
    let closed = av1_pool.close(dc.d.wp)
    if flushed != ok { ret flushed }
    ret closed
}
