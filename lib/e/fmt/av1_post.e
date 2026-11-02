// AV1 in-loop filters of a decoded frame: deblocking, CDEF and loop restoration, driven from the frame header and the
// decoder's mode info arrays.

use e.mem
use e.time
use e.thread
use e.fmt.av1
use e.fmt.av1_dec as D
use e.fmt.av1_lf
use e.fmt.av1_cdef
use e.fmt.av1_lr

error Invalid

type Scratch = struct {
    skips: []u8,
    refs: []i8,
    seg: []u8,
    dlf: []i8,
}

fn new_scratch(a: *mem.Arena, n: usize) -> (Scratch, err) {
    var s: Scratch = zero
    let (a0, e0) = mem.alloc[u8](a, n)
    if e0 != ok { ret (s, e0) }
    let (a1, e1) = mem.alloc[i8](a, n)
    if e1 != ok { ret (s, e1) }
    let (a2, e2) = mem.alloc[u8](a, n)
    if e2 != ok { ret (s, e2) }
    let (a3, e3) = mem.alloc[i8](a, n * 4usize)
    if e3 != ok { ret (s, e3) }
    s.skips = a0
    s.refs = a1
    s.seg = a2
    s.dlf = a3
    ret (s, ok)
}

fn gather(d: *D.Dec, s: *Scratch) {
    let n = d.mi.len
    var i = 0usize
    while i < n {
        let m = &d.mi[i]
        s.skips[i] = m.skip
        s.refs[i] = m.ref0
        s.seg[i] = m.segment_id
        s.dlf[i * 4usize] = m.delta_lf0
        s.dlf[i * 4usize + 1usize] = m.delta_lf1
        s.dlf[i * 4usize + 2usize] = m.delta_lf2
        s.dlf[i * 4usize + 3usize] = m.delta_lf3
        i += 1usize
    }
}

type LfJob = struct {
    p: *const av1_lf.LoopFilterParams,
    f: *const av1_lf.LoopFilterFrame,
    pr: *const av1_lf.Prepared,
    from: usize,
    to: usize,
    cols: bool,
    result: err,
}

fn lf_work(job: *LfJob) {
    if job.cols {
        job.result = av1_lf.filter_pass_cols(job.p, job.f, job.pr, job.from, job.to)
    } else {
        job.result = av1_lf.filter_pass_rows(job.p, job.f, job.pr, job.from, job.to)
    }
}

// One plane and pass of the deblocking filter split into `workers` ranges of 4x4 rows or columns run on that many threads.
fn lf_pass(a: *mem.Arena, p: *const av1_lf.LoopFilterParams, f: *const av1_lf.LoopFilterFrame, plane: u32, pass: u32, workers: usize) -> err {
    let pr = av1_lf.loop_filter_plane_prepare(p, f, plane, pass)
    var count = pr.rows4
    if pass == 1u32 { count = pr.cols4 }
    var n = workers
    if n > count { n = count }
    if n < 2usize {
        if pass == 0u32 { ret av1_lf.filter_pass_rows(p, f, &pr, 0usize, count) }
        ret av1_lf.filter_pass_cols(p, f, &pr, 0usize, count)
    }
    let mark = mem.mark(a)
    let (jobs, jobs_error) = mem.alloc[LfJob](a, n)
    if jobs_error != ok { ret jobs_error }
    var i = 0usize
    while i < n {
        jobs[i] = LfJob { p: p, f: f, pr: &pr, from: i * count / n, to: (i + 1usize) * count / n, cols: pass == 1u32, result: ok }
        i += 1usize
    }
    let (group, group_error) = thread.spawn_all[LfJob](a, lf_work, jobs, 1048576usize)
    if group_error != ok {
        mem.reset(a, mark)
        ret group_error
    }
    let joined = thread.join_all(group)
    var result = joined
    i = 0usize
    while i < n {
        if jobs[i].result != ok { result = jobs[i].result }
        i += 1usize
    }
    mem.reset(a, mark)
    ret result
}

type CdefJob = struct {
    p: av1_cdef.CdefParams,
    idx: []const i8,
    skips: []const u8,
    src: av1_cdef.Planes,
    dst: av1_cdef.Planes,
    from: usize,
    to: usize,
    result: err,
}

fn cdef_work(job: *CdefJob) {
    job.result = av1_cdef.cdef_rows(job.p, job.idx, job.skips, job.src, job.dst, job.from, job.to)
}

fn cdef_threads(a: *mem.Arena, p: av1_cdef.CdefParams, idx: []const i8, skips: []const u8, src: av1_cdef.Planes, dst: av1_cdef.Planes, sb_rows: usize, workers: usize) -> err {
    var n = workers
    if n > sb_rows { n = sb_rows }
    if n < 2usize {
        ret av1_cdef.cdef_rows(p, idx, skips, src, dst, 0usize, sb_rows)
    }
    let mark = mem.mark(a)
    let (jobs, jobs_error) = mem.alloc[CdefJob](a, n)
    if jobs_error != ok { ret jobs_error }
    var i = 0usize
    while i < n {
        jobs[i] = CdefJob { p: p, idx: idx, skips: skips, src: src, dst: dst, from: i * sb_rows / n, to: (i + 1usize) * sb_rows / n, result: ok }
        i += 1usize
    }
    let (group, group_error) = thread.spawn_all[CdefJob](a, cdef_work, jobs, 1048576usize)
    if group_error != ok {
        mem.reset(a, mark)
        ret group_error
    }
    let joined = thread.join_all(group)
    var result = joined
    i = 0usize
    while i < n {
        if jobs[i].result != ok { result = jobs[i].result }
        i += 1usize
    }
    mem.reset(a, mark)
    ret result
}

type LrJob = struct {
    bit_depth: u32,
    sub_x: u32,
    sub_y: u32,
    w: u32,
    h: u32,
    pre: []const u8,
    cdef: []const u8,
    out: []u8,
    stride: usize,
    unit: u32,
    units: []const av1_lr.LrUnit,
    from: u32,
    to: u32,
    scratch: []u8,
    result: err,
}

fn lr_work(job: *LrJob) {
    var arena = mem.arena_from(job.scratch)
    job.result = av1_lr.restore_rows(&arena, job.bit_depth, job.sub_x, job.sub_y, job.w, job.h, job.pre, job.cdef, job.out, job.stride, job.unit, job.units, job.from, job.to)
}

fn lr_threads(a: *mem.Arena, bit_depth: u32, sx: u32, sy: u32, w: u32, h: u32, pre: []const u8, cdef: []const u8, out: []u8, stride: usize, unit: u32, units: []const av1_lr.LrUnit, workers: usize) -> err {
    let stripes = av1_lr.count_stripes(h, sy)
    var n = workers
    if usize(stripes) < n { n = usize(stripes) }
    if n < 2usize { ret av1_lr.restore_rows(a, bit_depth, sx, sy, w, h, pre, cdef, out, stride, unit, units, 0u32, stripes) }
    let mark = mem.mark(a)
    let (jobs, jobs_error) = mem.alloc[LrJob](a, n)
    if jobs_error != ok { ret jobs_error }
    var i = 0usize
    while i < n {
        let (scratch, scratch_error) = mem.alloc[u8](a, 524288usize)
        if scratch_error != ok {
            mem.reset(a, mark)
            ret scratch_error
        }
        jobs[i] = LrJob { bit_depth: bit_depth, sub_x: sx, sub_y: sy, w: w, h: h, pre: pre, cdef: cdef, out: out, stride: stride, unit: unit, units: units, from: u32(usize(stripes) * i / n), to: u32(usize(stripes) * (i + 1usize) / n), scratch: scratch, result: ok }
        i += 1usize
    }
    let (group, group_error) = thread.spawn_all[LrJob](a, lr_work, jobs, 1048576usize)
    if group_error != ok {
        mem.reset(a, mark)
        ret group_error
    }
    let joined = thread.join_all(group)
    var result = joined
    i = 0usize
    while i < n {
        if jobs[i].result != ok { result = jobs[i].result }
        i += 1usize
    }
    mem.reset(a, mark)
    ret result
}

fn deblock(d: *D.Dec, s: *Scratch, a: *mem.Arena, workers: usize) -> err {
    let h = &d.st.h
    var p: av1_lf.LoopFilterParams = zero
    var i = 0usize
    while i < 4usize {
        p.levels[i] = h.loop_filter_level[i]
        i += 1usize
    }
    p.sharpness = h.loop_filter_sharpness
    p.delta_enabled = h.loop_filter_delta_enabled
    i = 0usize
    while i < 8usize {
        p.ref_deltas[i] = h.loop_filter_ref_deltas[i]
        i += 1usize
    }
    p.mode_deltas[0usize] = h.loop_filter_mode_deltas[0usize]
    p.mode_deltas[1usize] = h.loop_filter_mode_deltas[1usize]
    p.delta_lf_multi = h.delta_lf_multi
    var seg = 0usize
    while seg < 8usize {
        var k = 0usize
        while k < 4usize {
            p.seg_active[seg * 4usize + k] = h.segmentation_enabled && h.feature_enabled[seg * 8usize + 1usize + k] != 0i32
            p.seg_data[seg * 4usize + k] = h.feature_data[seg * 8usize + 1usize + k]
            k += 1usize
        }
        seg += 1usize
    }
    var f: av1_lf.LoopFilterFrame = zero
    f.mi_rows = usize(d.mi_rows)
    f.mi_cols = usize(d.mi_cols)
    f.frame_width = usize(h.frame_width)
    f.frame_height = usize(h.frame_height)
    f.sub_x = u32(d.st.seq.subsampling_x)
    f.sub_y = u32(d.st.seq.subsampling_y)
    f.num_planes = u32(d.st.seq.num_planes)
    f.bit_depth = u32(d.st.seq.bit_depth)
    f.mi_sizes = d.s_size
    f.skips = s.skips
    f.ref_frames = s.refs
    f.y_modes = d.s_ymode
    f.segment_ids = s.seg
    f.delta_lfs = s.dlf
    f.tx_sizes0 = d.lf_tx[0usize]
    f.tx_sizes1 = d.lf_tx[1usize]
    f.tx_sizes2 = d.lf_tx[2usize]
    f.p0 = d.frame[0usize]
    f.p1 = d.frame[1usize]
    f.p2 = d.frame[2usize]
    f.stride0 = d.stride[0usize]
    f.stride1 = d.stride[1usize]
    f.stride2 = d.stride[2usize]
    var plane = 0u32
    while plane < u32(d.st.seq.num_planes) {
        if av1_lf.plane_enabled(&p, plane) {
            try lf_pass(a, &p, &f, plane, 0u32, workers)
            try lf_pass(a, &p, &f, plane, 1u32, workers)
        }
        plane += 1u32
    }
    ret ok
}

fn cdef_active(h: *const av1.Hdr) -> bool {
    var i = 0usize
    while i < (1usize << u32(h.cdef_bits)) {
        if h.cdef_y_pri_strength[i] != 0i32 || h.cdef_y_sec_strength[i] != 0i32 || h.cdef_uv_pri_strength[i] != 0i32 || h.cdef_uv_sec_strength[i] != 0i32 { ret true }
        i += 1usize
    }
    ret false
}

// Runs the filters on d.frame (in place for deblocking). Returns which plane set holds the result: 0 the frame itself,
// 1 `w1`, 2 `w2`.
fn post_filter(d: *D.Dec, a: *mem.Arena, s: *Scratch, w1: [3][]u8, w2: [3][]u8) -> (usize, err) {
    let h = &d.st.h
    let seq = &d.st.seq
    gather(d, s)
    if h.loop_filter_level[0usize] != 0i32 || h.loop_filter_level[1usize] != 0i32 {
        let (l0, lc0) = time.monotonic()
        let e = deblock(d, s, a, d.threads)
        let (l1, lc1) = time.monotonic()
        d.ns_lf += l1.nanos - l0.nanos
        if e != ok { ret (0usize, e) }
    }
    var result = 0usize
    if seq.enable_cdef && !h.coded_lossless && !h.allow_intrabc && cdef_active(h) {
        var p: av1_cdef.CdefParams = zero
        p.bit_depth = u32(seq.bit_depth)
        p.sub_x = u32(seq.subsampling_x)
        p.sub_y = u32(seq.subsampling_y)
        p.num_planes = u32(seq.num_planes)
        p.mi_rows = u32(d.mi_rows)
        p.mi_cols = u32(d.mi_cols)
        p.damping = u32(h.cdef_damping)
        var i = 0usize
        while i < 8usize {
            p.y_pri[i] = u32(h.cdef_y_pri_strength[i])
            p.y_sec[i] = u32(h.cdef_y_sec_strength[i])
            p.uv_pri[i] = u32(h.cdef_uv_pri_strength[i])
            p.uv_sec[i] = u32(h.cdef_uv_sec_strength[i])
            i += 1usize
        }
        var src: av1_cdef.Planes = zero
        src.y = d.frame[0usize]
        src.u = d.frame[1usize]
        src.v = d.frame[2usize]
        src.stride_y = d.stride[0usize]
        src.stride_uv = d.stride[1usize]
        var dst: av1_cdef.Planes = zero
        dst.y = w1[0usize]
        dst.u = w1[1usize]
        dst.v = w1[2usize]
        dst.stride_y = d.stride[0usize]
        dst.stride_uv = d.stride[1usize]
        let (c0, cc0) = time.monotonic()
        let cdef_error = cdef_threads(a, p, d.cdef_idx, s.skips, src, dst, usize((d.mi_rows + 15i32) >> 4u32), d.threads)
        if cdef_error != ok { ret (0usize, cdef_error) }
        let (c1, cc1) = time.monotonic()
        d.ns_cdef += c1.nanos - c0.nanos
        result = 1usize
    }
    if h.uses_lr {
        let (r0t, rc0) = time.monotonic()
        var cdef_src = d.frame
        if result == 1usize { cdef_src = w1 }
        let out = w2
        var plane = 0usize
        while plane < usize(seq.num_planes) {
            if h.frame_restoration_type[plane] != av1.RESTORE_NONE {
                var sx = 0u32
                var sy = 0u32
                if plane > 0usize {
                    sx = u32(seq.subsampling_x)
                    sy = u32(seq.subsampling_y)
                }
                let e = lr_threads(a, u32(seq.bit_depth), sx, sy, u32(h.upscaled_width), u32(h.frame_height), d.frame[plane], cdef_src[plane], out[plane], d.stride[plane], u32(h.loop_restoration_size[plane]), d.lr_units[plane], d.threads)
                if e != ok { ret (0usize, e) }
            } else {
                var i = 0usize
                while i < out[plane].len {
                    out[plane][i] = cdef_src[plane][i]
                    i += 1usize
                }
            }
            plane += 1usize
        }
        let (r1t, rc1) = time.monotonic()
        d.ns_lr += r1t.nanos - r0t.nanos
        result = 2usize
    }
    ret (result, ok)
}
