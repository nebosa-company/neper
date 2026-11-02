// AV1 decoder state shared by the tile decoder modules: per-frame arrays at 4x4 (MI) resolution, the frame planes, the
// symbol decoder with its CDF context, the above/left contexts of the tile and the mode info of the block being decoded.
// Spec numbering is kept for block sizes, prediction modes, reference frames and transform sizes.

use e.mem
use e.time
use e.fmt.av1
use e.fmt.av1_sym
use e.fmt.av1_tables
use e.fmt.av1_cdf
use e.fmt.av1_lr
use e.fmt.av1_mvp
use e.fmt.av1_inter
use e.fmt.av1_mask
use e.fmt.av1_intra

error Corrupt

const BLOCK_4X4: usize = 0usize
const BLOCK_8X8: usize = 3usize
const BLOCK_64X64: usize = 12usize
const BLOCK_128X128: usize = 15usize
const BLOCK_INVALID: usize = 22usize

const PARTITION_NONE: usize = 0usize
const PARTITION_HORZ: usize = 1usize
const PARTITION_VERT: usize = 2usize
const PARTITION_SPLIT: usize = 3usize
const PARTITION_HORZ_A: usize = 4usize
const PARTITION_HORZ_B: usize = 5usize
const PARTITION_VERT_A: usize = 6usize
const PARTITION_VERT_B: usize = 7usize
const PARTITION_HORZ_4: usize = 8usize
const PARTITION_VERT_4: usize = 9usize

const DC_PRED: usize = 0usize
const V_PRED: usize = 1usize
const H_PRED: usize = 2usize
const D67_PRED: usize = 8usize
const SMOOTH_PRED: usize = 9usize
const UV_CFL_PRED: usize = 13usize
const NEARESTMV: usize = 14usize
const NEARMV: usize = 15usize
const GLOBALMV: usize = 16usize
const NEWMV: usize = 17usize
const NEAREST_NEARESTMV: usize = 18usize
const NEAR_NEARMV: usize = 19usize
const NEAREST_NEWMV: usize = 20usize
const NEW_NEARESTMV: usize = 21usize
const NEAR_NEWMV: usize = 22usize
const NEW_NEARMV: usize = 23usize
const GLOBAL_GLOBALMV: usize = 24usize
const NEW_NEWMV: usize = 25usize

const TX_4X4: usize = 0usize
const TX_64X64: usize = 4usize
const TX_16X32: usize = 9usize
const TX_32X16: usize = 10usize
const TX_32X32: usize = 3usize
const TX_SIZES_ALL: usize = 19usize

const SIMPLE: usize = 0usize
const OBMC: usize = 1usize
const LOCALWARP: usize = 2usize
const COMPOUND_AVERAGE: usize = 2usize
const NONE_REF: i32 = 0i32 - 1i32

const SEG_LVL_SKIP: usize = 6usize
const SEG_LVL_GLOBALMV: usize = 7usize

// one 4x4 position of the frame
type Mi = struct {
    size: u8,
    y_mode: u8,
    uv_mode: u8,
    ref0: i8,
    ref1: i8,
    skip: u8,
    skip_mode: u8,
    is_inter: u8,
    tx_size: u8,
    inter_tx_size: u8,
    segment_id: u8,
    interp0: u8,
    interp1: u8,
    comp_group_idx: u8,
    mmode: u8,
    compound_idx: u8,
    mv0_row: i16,
    mv0_col: i16,
    mv1_row: i16,
    mv1_col: i16,
    delta_lf0: i8,
    delta_lf1: i8,
    delta_lf2: i8,
    delta_lf3: i8,
}

// the mode info of the block being decoded
type Block = struct {
    mi_row: i32,
    mi_col: i32,
    mi_size: usize,
    bw4: i32,
    bh4: i32,
    has_chroma: bool,
    avail_u: bool,
    avail_l: bool,
    avail_u_chroma: bool,
    avail_l_chroma: bool,
    skip: bool,
    skip_mode: bool,
    is_inter: bool,
    use_intrabc: bool,
    segment_id: usize,
    lossless: bool,
    y_mode: usize,
    uv_mode: usize,
    angle_delta_y: i32,
    angle_delta_uv: i32,
    cfl_alpha_u: i32,
    cfl_alpha_v: i32,
    use_filter_intra: bool,
    filter_intra_mode: usize,
    ref_frame0: i32,
    ref_frame1: i32,
    mv0_row: i32,
    mv0_col: i32,
    mv1_row: i32,
    mv1_col: i32,
    interp0: usize,
    interp1: usize,
    motion_mode: usize,
    interintra: bool,
    interintra_mode: usize,
    wedge_interintra: bool,
    wedge_index: usize,
    wedge_sign: usize,
    num_samples: i32,
    local_valid: bool,
    local_params: [6]i32,
    cand_list: [32]i32,
    comp_group_idx: usize,
    compound_idx: usize,
    ref_mv_idx: i32,
    tx_size: usize,
    left_ref0: i32,
    left_ref1: i32,
    above_ref0: i32,
    above_ref1: i32,
    left_intra: bool,
    above_intra: bool,
    left_single: bool,
    above_single: bool,
}

// A transform block whose pixels are made after the whole frame is parsed: the intra prediction it needs (if any), the
// quantised coefficients (kept in Dec.qpool) and the dequantisation values of the time it was parsed.
type TxRec = struct {
    plane: u8,
    tx: u8,
    tx_type: u8,
    has_intra: bool,
    is_cfl: bool,
    lossless: bool,
    eob: u16,
    x: i32,
    y: i32,
    qoff: u32,
    dcq: i32,
    acq: i32,
    alpha: i32,
    mlw: i32,
    mlh: i32,
    p: av1_intra.IntraParams,
}

// A decoded block of a deferred frame: its mode info and the transform blocks recs[first .. first + count). kind 0 is an
// inter block (its pixels do not depend on the other blocks of the frame), 1 an intra block and 2 an inter-intra block.
type BRec = struct {
    b: Block,
    first: u32,
    count: u32,
    kind: u8,
}

type Dec = struct {
    st: *av1.State,
    tab: []const i32,
    ctx: []u16,
    sd: av1_sym.Sym,
    mi_rows: i32,
    mi_cols: i32,
    mi: []Mi,
    // tile bounds
    row_start: i32,
    row_end: i32,
    col_start: i32,
    col_end: i32,
    // contexts of the tile, indexed by 4x4 column / row (plane sample units >> 2)
    above_level: [3][]u8,
    above_dc: [3][]u8,
    left_level: [3][]u8,
    left_dc: [3][]u8,
    above_seg_pred: []u8,
    left_seg_pred: []u8,
    cdef_idx: []i8,
    cdef_stride: i32,
    block_decoded: [3][]u8,
    lr_units: [3][]av1_lr.LrUnit,
    lr_cols: [3]i32,
    lr_rows: [3]i32,
    ref_lr_wiener: [18]i32,
    ref_sgr_xqd: [6]i32,
    delta_lf: [4]i32,
    current_q_index: i32,
    read_deltas: bool,
    b: Block,
    dbg: [4096]i32,
    dbg_n: usize,
    ns_pred: i64,
    ns_resid: i64,
    threads: usize,
    deferred: bool,
    recs: []TxRec,
    rec_n: usize,
    brecs: []BRec,
    brec_n: usize,
    qpool: []i32,
    q_n: usize,
    views: []Dec,
    w_work: [8]av1_inter.Work,
    w_oa: [8][]av1_inter.Neighbor,
    w_ol: [8][]av1_inter.Neighbor,
    w_resid: [8][]i32,
    ns_mode: i64,
    ns_coef: i64,
    ns_txfm: i64,
    ns_intra: i64,
    ns_p_plain: i64,
    ns_p_warp: i64,
    ns_p_ii: i64,
    ns_p_obmc: i64,
    n_p_plain: i64,
    n_p_obmc: i64,
    ns_lf: i64,
    ns_cdef: i64,
    ns_lr: i64,
    frame: [3][]u8,
    stride: [3]usize,
    tx_types: []u8,
    lf_tx: [3][]u8,
    quant: []i32,
    resid: []i32,
    max_luma_w: i32,
    max_luma_h: i32,
    s_size: []u8,
    s_ymode: []u8,
    s_inter: []u8,
    s_ref: []i8,
    s_mv: []i16,
    ref_planes: [8][3][]u8,
    ref_stride: [3]usize,
    iwk: av1_inter.Work,
    masks: av1_mask.Masks,
    ii_mask: []u8,
    obmc_above: []av1_inter.Neighbor,
    obmc_left: []av1_inter.Neighbor,
    motion_field: []i16,
    mf_slots: [8]av1_mvp.RefSlot,
    mf_refs: []i8,
    mf_mvs: []i16,
    mvf: av1_mvp.Frame,
    mvp: av1_mvp.Mvp,
}

fn t(d: *const Dec, base: usize, i: usize) -> i32 {
    ret d.tab[base + i]
}

fn n4w(d: *const Dec, bs: usize) -> i32 { ret d.tab[av1_tables.T_NUM_4X4_BLOCKS_WIDE + bs] }
fn n4h(d: *const Dec, bs: usize) -> i32 { ret d.tab[av1_tables.T_NUM_4X4_BLOCKS_HIGH + bs] }
fn mi_wlog2(d: *const Dec, bs: usize) -> i32 { ret d.tab[av1_tables.T_MI_WIDTH_LOG2 + bs] }
fn mi_hlog2(d: *const Dec, bs: usize) -> i32 { ret d.tab[av1_tables.T_MI_HEIGHT_LOG2 + bs] }
fn block_w(d: *const Dec, bs: usize) -> i32 { ret 4i32 * n4w(d, bs) }
fn block_h(d: *const Dec, bs: usize) -> i32 { ret 4i32 * n4h(d, bs) }
fn tx_w(d: *const Dec, tx: usize) -> i32 { ret d.tab[av1_tables.T_TX_WIDTH + tx] }
fn tx_h(d: *const Dec, tx: usize) -> i32 { ret d.tab[av1_tables.T_TX_HEIGHT + tx] }

fn sub_size(d: *const Dec, bs: usize, sx: i32, sy: i32) -> usize {
    ret usize(d.tab[av1_tables.T_SUBSAMPLED_SIZE + bs * 4usize + usize(sx) * 2usize + usize(sy)])
}

fn mi_at(d: *const Dec, r: i32, c: i32) -> usize {
    ret usize(r * d.mi_cols + c)
}

fn is_inside(d: *const Dec, r: i32, c: i32) -> bool {
    ret c >= d.col_start && c < d.col_end && r >= d.row_start && r < d.row_end
}

// the cdf `idx` of `count` copies of length `len` starting at `base`
fn cdf(d: *Dec, base: usize, len: usize, idx: usize) -> []u16 {
    let from = base + idx * len
    ret d.ctx[from..from + len]
}

fn sym(d: *Dec, base: usize, len: usize, idx: usize, n: usize) -> usize {
    ret av1_sym.read_symbol(&d.sd, cdf(d, base, len, idx), n)
}

fn lit(d: *Dec, n: u32) -> u32 {
    ret av1_sym.read_literal(&d.sd, n)
}

fn clip3(lo: i32, hi: i32, x: i32) -> i32 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn max_i(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn min_i(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn abs_i(a: i32) -> i32 {
    if a < 0i32 { ret 0i32 - a }
    ret a
}

fn is_smooth(d: *Dec, row: i32, col: i32, plane: usize) -> bool {
    if row < 0i32 || col < 0i32 || row >= d.mi_rows || col >= d.mi_cols { ret false }
    let m = &d.mi[mi_at(d, row, col)]
    var mode = usize(m.y_mode)
    if plane > 0usize {
        if i32(m.ref0) > i32(av1.INTRA_FRAME) { ret false }
        mode = usize(m.uv_mode)
    }
    ret mode == 9usize || mode == 10usize || mode == 11usize
}

fn is_smooth_above(d: *Dec, plane: usize, avail: bool) -> bool {
    if !avail { ret false }
    let b = &d.b
    var r = b.mi_row - 1i32
    var c = b.mi_col
    if plane > 0usize {
        if d.st.seq.subsampling_x == 1i32 && (b.mi_col & 1i32) == 0i32 { c += 1i32 }
        if d.st.seq.subsampling_y == 1i32 && (b.mi_row & 1i32) == 1i32 { r -= 1i32 }
    }
    ret is_smooth(d, r, c, plane)
}

fn is_smooth_left(d: *Dec, plane: usize, avail: bool) -> bool {
    if !avail { ret false }
    let b = &d.b
    var r = b.mi_row
    var c = b.mi_col - 1i32
    if plane > 0usize {
        if d.st.seq.subsampling_x == 1i32 && (b.mi_col & 1i32) == 1i32 { c -= 1i32 }
        if d.st.seq.subsampling_y == 1i32 && (b.mi_row & 1i32) == 0i32 { r += 1i32 }
    }
    ret is_smooth(d, r, c, plane)
}

