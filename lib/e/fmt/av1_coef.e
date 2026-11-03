// AV1 residual coefficient parsing: the coeffs, transform_type, compute_tx_type, get_tx_set and get_scan syntax of the
// specification (section 5.11.39 and neighbours) with the cdf selection and context derivations of section 8.3.2 for every
// symbol they read (all_zero, eob_pt_*, eob_extra, coeff_base_eob, coeff_base, coeff_br, dc_sign, intra/inter_tx_type).
//
// `ctx` is the flat cdf context of e.fmt.av1_cdf (the coefficient cdfs already hold the quantizer-selected set) and `tab` the
// table array of e.fmt.av1_tables. Everything the syntax reads from the surrounding block is in CoefParams; the above/left
// level and dc contexts and TxTypes are caller-owned slices that this module reads and updates exactly as the specification
// does. Indices into them are the specification's: x4/y4 in units of 4 samples of the plane (for the contexts) and of luma
// (for TxTypes, row-major with `tx_stride` entries per row). A read or write outside a slice is skipped, so slices sized
// to the frame in 4x4 units (the context ones to the plane) behave like the specification's unbounded arrays.
//
// `quant` receives the signed coefficients before dequantization in the specification's Quant layout: position
// `(row << bwl) + col` where bwl is Tx_Width_Log2 of Adjusted_Tx_Size (so 64-sample sizes use a 32 sample stride); it must hold
// at least 1024 entries, the first segEob of which are cleared and written.

use e.mem
use e.fmt.av1_sym
use e.fmt.av1_cdf
use e.fmt.av1_tables

error Invalid

const DCT_DCT: usize = 0usize
const IDTX: usize = 9usize
const TX_32X32: usize = 3usize
const TX_16X16: usize = 2usize
const TX_16X64: usize = 17usize
const TX_64X16: usize = 18usize
const TX_CLASS_2D: usize = 0usize
const TX_CLASS_HORIZ: usize = 1usize
const TX_CLASS_VERT: usize = 2usize
const SIG_COEF_CONTEXTS: usize = 42usize
const NUM_BASE_LEVELS: i32 = 2i32
const COEFF_BASE_RANGE: i32 = 12i32

type CoefParams = struct {
    plane: usize,
    start_x: usize,
    start_y: usize,
    tx_size: usize,
    mi_size: usize,
    mi_row: usize,
    mi_col: usize,
    mi_rows: usize,
    mi_cols: usize,
    ssx: usize,
    ssy: usize,
    is_inter: bool,
    reduced_tx_set: bool,
    lossless: bool,
    qidx: i32,
    y_mode: usize,
    uv_mode: usize,
    use_filter_intra: bool,
    filter_intra_mode: usize,
    above_level: []u8,
    above_dc: []u8,
    left_level: []u8,
    left_dc: []u8,
    tx_types: []u8,
    tx_stride: usize,
}

// eob is 0 when all_zero was set; tx_type is PlaneTxType (DCT_DCT then); cul_level and dc_category are the values stored into
// the above/left contexts
type CoefResult = struct {
    eob: usize,
    tx_type: usize,
    cul_level: u32,
    dc_category: u32,
}

fn umin(a: usize, b: usize) -> usize {
    if a < b { ret a }
    ret b
}

fn umax(a: usize, b: usize) -> usize {
    if a > b { ret a }
    ret b
}

fn tv(tab: []const i32, off: usize, i: usize) -> usize {
    ret usize(tab[off + i])
}

fn get_tx_class(tx_type: usize) -> usize {
    if tx_type == 10usize || tx_type == 12usize || tx_type == 14usize { ret TX_CLASS_VERT }
    if tx_type == 11usize || tx_type == 13usize || tx_type == 15usize { ret TX_CLASS_HORIZ }
    ret TX_CLASS_2D
}

// 0 TX_SET_DCTONLY, else the set number of the specification's table (1 and 2 for intra; 1, 2 and 3 for inter)
fn get_tx_set(tab: []const i32, tx_size: usize, is_inter: bool, reduced_tx_set: bool) -> usize {
    let sqr = tv(tab, av1_tables.T_TX_SIZE_SQR, tx_size)
    let sqr_up = tv(tab, av1_tables.T_TX_SIZE_SQR_UP, tx_size)
    if sqr_up > TX_32X32 { ret 0usize }
    if is_inter {
        if reduced_tx_set || sqr_up == TX_32X32 { ret 3usize }
        if sqr == TX_16X16 { ret 2usize }
        ret 1usize
    }
    if sqr_up == TX_32X32 { ret 0usize }
    if reduced_tx_set { ret 2usize }
    if sqr == TX_16X16 { ret 2usize }
    ret 1usize
}

fn is_tx_type_in_set(tab: []const i32, is_inter: bool, tx_set: usize, tx_type: usize) -> bool {
    if is_inter { ret tab[av1_tables.T_TX_TYPE_IN_SET_INTER + tx_set * 16usize + tx_type] != 0i32 }
    ret tab[av1_tables.T_TX_TYPE_IN_SET_INTRA + tx_set * 16usize + tx_type] != 0i32
}

fn tx_types_at(p: *CoefParams, x4: usize, y4: usize) -> usize {
    let at_index = y4 * p.tx_stride + x4
    if x4 >= p.tx_stride || at_index >= p.tx_types.len { ret DCT_DCT }
    ret usize(p.tx_types[at_index])
}

fn set_tx_types(p: *CoefParams, x4: usize, y4: usize, w4: usize, h4: usize, tx_type: usize) {
    var j = 0usize
    while j < h4 {
        var i = 0usize
        while i < w4 {
            let at_index = (y4 + j) * p.tx_stride + x4 + i
            if x4 + i < p.tx_stride && at_index < p.tx_types.len { p.tx_types[at_index] = u8(tx_type) }
            i += 1usize
        }
        j += 1usize
    }
}

// compute_tx_type(plane, txSz, blockX, blockY) with plane and txSz taken from `p`
fn compute_tx_type(tab: []const i32, p: *CoefParams, block_x: usize, block_y: usize) -> usize {
    let sqr_up = tv(tab, av1_tables.T_TX_SIZE_SQR_UP, p.tx_size)
    if p.lossless || sqr_up > TX_32X32 { ret DCT_DCT }
    let tx_set = get_tx_set(tab, p.tx_size, p.is_inter, p.reduced_tx_set)
    if p.plane == 0usize { ret tx_types_at(p, block_x, block_y) }
    if p.is_inter {
        let x4 = umax(p.mi_col, block_x << p.ssx)
        let y4 = umax(p.mi_row, block_y << p.ssy)
        let t = tx_types_at(p, x4, y4)
        if !is_tx_type_in_set(tab, true, tx_set, t) { ret DCT_DCT }
        ret t
    }
    let t = tv(tab, av1_tables.T_MODE_TO_TXFM, p.uv_mode)
    if !is_tx_type_in_set(tab, false, tx_set, t) { ret DCT_DCT }
    ret t
}

fn default_scan_off(tx_size: usize) -> usize {
    if tx_size == 0usize { ret av1_tables.T_DEFAULT_SCAN_4X4 }
    if tx_size == 5usize { ret av1_tables.T_DEFAULT_SCAN_4X8 }
    if tx_size == 6usize { ret av1_tables.T_DEFAULT_SCAN_8X4 }
    if tx_size == 1usize { ret av1_tables.T_DEFAULT_SCAN_8X8 }
    if tx_size == 7usize { ret av1_tables.T_DEFAULT_SCAN_8X16 }
    if tx_size == 8usize { ret av1_tables.T_DEFAULT_SCAN_16X8 }
    if tx_size == 2usize { ret av1_tables.T_DEFAULT_SCAN_16X16 }
    if tx_size == 9usize { ret av1_tables.T_DEFAULT_SCAN_16X32 }
    if tx_size == 10usize { ret av1_tables.T_DEFAULT_SCAN_32X16 }
    if tx_size == 13usize { ret av1_tables.T_DEFAULT_SCAN_4X16 }
    if tx_size == 14usize { ret av1_tables.T_DEFAULT_SCAN_16X4 }
    if tx_size == 15usize { ret av1_tables.T_DEFAULT_SCAN_8X32 }
    if tx_size == 16usize { ret av1_tables.T_DEFAULT_SCAN_32X8 }
    ret av1_tables.T_DEFAULT_SCAN_32X32
}

fn mrow_scan_off(tx_size: usize) -> usize {
    if tx_size == 0usize { ret av1_tables.T_MROW_SCAN_4X4 }
    if tx_size == 5usize { ret av1_tables.T_MROW_SCAN_4X8 }
    if tx_size == 6usize { ret av1_tables.T_MROW_SCAN_8X4 }
    if tx_size == 1usize { ret av1_tables.T_MROW_SCAN_8X8 }
    if tx_size == 7usize { ret av1_tables.T_MROW_SCAN_8X16 }
    if tx_size == 8usize { ret av1_tables.T_MROW_SCAN_16X8 }
    if tx_size == 2usize { ret av1_tables.T_MROW_SCAN_16X16 }
    if tx_size == 13usize { ret av1_tables.T_MROW_SCAN_4X16 }
    ret av1_tables.T_MROW_SCAN_16X4
}

fn mcol_scan_off(tx_size: usize) -> usize {
    if tx_size == 0usize { ret av1_tables.T_MCOL_SCAN_4X4 }
    if tx_size == 5usize { ret av1_tables.T_MCOL_SCAN_4X8 }
    if tx_size == 6usize { ret av1_tables.T_MCOL_SCAN_8X4 }
    if tx_size == 1usize { ret av1_tables.T_MCOL_SCAN_8X8 }
    if tx_size == 7usize { ret av1_tables.T_MCOL_SCAN_8X16 }
    if tx_size == 8usize { ret av1_tables.T_MCOL_SCAN_16X8 }
    if tx_size == 2usize { ret av1_tables.T_MCOL_SCAN_16X16 }
    if tx_size == 13usize { ret av1_tables.T_MCOL_SCAN_4X16 }
    ret av1_tables.T_MCOL_SCAN_16X4
}

// get_scan(txSz) for PlaneTxType `tx_type`: the scan (positions in the Quant layout) of segEob entries
fn get_scan(tab: []const i32, tx_size: usize, tx_type: usize) -> []const i32 {
    let w = umin(tv(tab, av1_tables.T_TX_WIDTH, tx_size), 32usize)
    let h = umin(tv(tab, av1_tables.T_TX_HEIGHT, tx_size), 32usize)
    var off = 0usize
    if tx_size == TX_16X64 {
        off = av1_tables.T_DEFAULT_SCAN_16X32
    } else if tx_size == TX_64X16 {
        off = av1_tables.T_DEFAULT_SCAN_32X16
    } else if tv(tab, av1_tables.T_TX_SIZE_SQR_UP, tx_size) == 4usize {
        off = av1_tables.T_DEFAULT_SCAN_32X32
    } else if tx_type == IDTX {
        off = default_scan_off(tx_size)
    } else if tx_type == 10usize || tx_type == 12usize || tx_type == 14usize {
        off = mrow_scan_off(tx_size)
    } else if tx_type == 11usize || tx_type == 13usize || tx_type == 15usize {
        off = mcol_scan_off(tx_size)
    } else {
        off = default_scan_off(tx_size)
    }
    ret tab[off..off + w * h]
}

// the cdf of intra_tx_type / inter_tx_type for `tx_set`, as (offset in ctx, symbol count); count 0 when the set does not
// exist for the transform size
fn tx_type_cdf(tab: []const i32, p: *CoefParams, tx_set: usize) -> (usize, usize) {
    let sqr = tv(tab, av1_tables.T_TX_SIZE_SQR, p.tx_size)
    if p.is_inter {
        if tx_set == 1usize {
            if sqr >= 2usize { ret (0usize, 0usize) }
            ret (av1_cdf.C_INTERTXTYPESET1 + sqr * 17usize, 16usize)
        }
        if tx_set == 2usize { ret (av1_cdf.C_INTERTXTYPESET2, 12usize) }
        if sqr >= 4usize { ret (0usize, 0usize) }
        ret (av1_cdf.C_INTERTXTYPESET3 + sqr * 3usize, 2usize)
    }
    var intra_dir = p.y_mode
    if p.use_filter_intra { intra_dir = tv(tab, av1_tables.T_FILTER_INTRA_MODE_TO_INTRA_DIR, p.filter_intra_mode) }
    if intra_dir >= 13usize { ret (0usize, 0usize) }
    if tx_set == 1usize {
        if sqr >= 2usize { ret (0usize, 0usize) }
        ret (av1_cdf.C_INTRATXTYPESET1 + (sqr * 13usize + intra_dir) * 8usize, 7usize)
    }
    if sqr >= 3usize { ret (0usize, 0usize) }
    ret (av1_cdf.C_INTRATXTYPESET2 + (sqr * 13usize + intra_dir) * 6usize, 5usize)
}

// transform_type(x4, y4, txSz): reads the transform type of a luma transform block when the set allows it and stores it in
// TxTypes; returns it. `x4`, `y4` are in luma 4x4 units.
fn transform_type(sd: *av1_sym.Sym, ctx: []u16, tab: []const i32, p: *CoefParams, x4: usize, y4: usize) -> (usize, err) {
    let tx_set = get_tx_set(tab, p.tx_size, p.is_inter, p.reduced_tx_set)
    var tx_type = DCT_DCT
    if tx_set > 0usize && p.qidx > 0i32 {
        let (off, n) = tx_type_cdf(tab, p, tx_set)
        if n == 0usize { ret (0usize, Invalid) }
        let sym = av1_sym.read_symbol(sd, ctx[off..off + n + 1usize], n)
        if p.is_inter {
            if tx_set == 1usize {
                tx_type = tv(tab, av1_tables.T_TX_TYPE_INTER_INV_SET1, sym)
            } else if tx_set == 2usize {
                tx_type = tv(tab, av1_tables.T_TX_TYPE_INTER_INV_SET2, sym)
            } else {
                tx_type = tv(tab, av1_tables.T_TX_TYPE_INTER_INV_SET3, sym)
            }
        } else if tx_set == 1usize {
            tx_type = tv(tab, av1_tables.T_TX_TYPE_INTRA_INV_SET1, sym)
        } else {
            tx_type = tv(tab, av1_tables.T_TX_TYPE_INTRA_INV_SET2, sym)
        }
    }
    let w4 = tv(tab, av1_tables.T_TX_WIDTH, p.tx_size) >> 2usize
    let h4 = tv(tab, av1_tables.T_TX_HEIGHT, p.tx_size) >> 2usize
    set_tx_types(p, x4, y4, w4, h4, tx_type)
    ret (tx_type, ok)
}

fn ctx_at(a: []u8, i: usize) -> usize {
    if i >= a.len { ret 0usize }
    ret usize(a[i])
}

// the ctx of all_zero
fn txb_skip_ctx(tab: []const i32, p: *CoefParams, x4: usize, y4: usize, w4: usize, h4: usize) -> usize {
    var max_x4 = p.mi_cols
    var max_y4 = p.mi_rows
    var subx = 0usize
    var suby = 0usize
    if p.plane > 0usize {
        max_x4 = max_x4 >> p.ssx
        max_y4 = max_y4 >> p.ssy
        subx = p.ssx
        suby = p.ssy
    }
    let w = tv(tab, av1_tables.T_TX_WIDTH, p.tx_size)
    let h = tv(tab, av1_tables.T_TX_HEIGHT, p.tx_size)
    let bsize = tv(tab, av1_tables.T_SUBSAMPLED_SIZE, (p.mi_size * 2usize + subx) * 2usize + suby)
    let bw = 4usize * tv(tab, av1_tables.T_NUM_4X4_BLOCKS_WIDE, bsize)
    let bh = 4usize * tv(tab, av1_tables.T_NUM_4X4_BLOCKS_HIGH, bsize)
    if p.plane == 0usize {
        var top = 0usize
        var left = 0usize
        var k = 0usize
        while k < w4 {
            if x4 + k < max_x4 { top = umax(top, ctx_at(p.above_level, x4 + k)) }
            k += 1usize
        }
        k = 0usize
        while k < h4 {
            if y4 + k < max_y4 { left = umax(left, ctx_at(p.left_level, y4 + k)) }
            k += 1usize
        }
        top = umin(top, 255usize)
        left = umin(left, 255usize)
        if bw == w && bh == h { ret 0usize }
        if top == 0usize && left == 0usize { ret 1usize }
        if top == 0usize || left == 0usize {
            if umax(top, left) > 3usize { ret 3usize }
            ret 2usize
        }
        if umax(top, left) <= 3usize { ret 4usize }
        if umin(top, left) <= 3usize { ret 5usize }
        ret 6usize
    }
    var above = 0usize
    var left_any = 0usize
    var i = 0usize
    while i < w4 {
        if x4 + i < max_x4 { above = above | ctx_at(p.above_level, x4 + i) | ctx_at(p.above_dc, x4 + i) }
        i += 1usize
    }
    i = 0usize
    while i < h4 {
        if y4 + i < max_y4 { left_any = left_any | ctx_at(p.left_level, y4 + i) | ctx_at(p.left_dc, y4 + i) }
        i += 1usize
    }
    var cx = 7usize
    if above != 0usize { cx += 1usize }
    if left_any != 0usize { cx += 1usize }
    if bw * bh > w * h { cx += 3usize }
    ret cx
}

// the ctx of dc_sign
fn dc_sign_ctx(p: *CoefParams, x4: usize, y4: usize, w4: usize, h4: usize) -> usize {
    var max_x4 = p.mi_cols
    var max_y4 = p.mi_rows
    if p.plane > 0usize {
        max_x4 = max_x4 >> p.ssx
        max_y4 = max_y4 >> p.ssy
    }
    var dc_sign = 0i32
    var k = 0usize
    while k < w4 {
        if x4 + k < max_x4 {
            let s = ctx_at(p.above_dc, x4 + k)
            if s == 1usize { dc_sign -= 1i32 } else if s == 2usize { dc_sign += 1i32 }
        }
        k += 1usize
    }
    k = 0usize
    while k < h4 {
        if y4 + k < max_y4 {
            let s = ctx_at(p.left_dc, y4 + k)
            if s == 1usize { dc_sign -= 1i32 } else if s == 2usize { dc_sign += 1i32 }
        }
        k += 1usize
    }
    if dc_sign < 0i32 { ret 1usize }
    if dc_sign > 0i32 { ret 2usize }
    ret 0usize
}


// get_coeff_base_ctx for isEob = 1, already reduced by SIG_COEF_CONTEXTS - SIG_COEF_CONTEXTS_EOB
fn coeff_base_eob_ctx(tab: []const i32, tx_size: usize, c: usize) -> usize {
    let adj = tv(tab, av1_tables.T_ADJUSTED_TX_SIZE, tx_size)
    let bwl = tv(tab, av1_tables.T_TX_WIDTH_LOG2, adj)
    let area = tv(tab, av1_tables.T_TX_HEIGHT, adj) << bwl
    if c == 0usize { ret 0usize }
    if c <= area / 8usize { ret 1usize }
    if c <= area / 4usize { ret 2usize }
    ret 3usize
}


// eob_pt_*: the symbol (eobPt - 1) for eobMultisize `ms` (0 to 6)
fn read_eob_pt(sd: *av1_sym.Sym, ctx: []u16, ms: usize, ptype: usize, tx_class: usize) -> usize {
    var cx = 1usize
    if tx_class == TX_CLASS_2D { cx = 0usize }
    var off = 0usize
    var n = 5usize + ms
    if ms == 0usize {
        off = av1_cdf.C_EOBPT16
    } else if ms == 1usize {
        off = av1_cdf.C_EOBPT32
    } else if ms == 2usize {
        off = av1_cdf.C_EOBPT64
    } else if ms == 3usize {
        off = av1_cdf.C_EOBPT128
    } else if ms == 4usize {
        off = av1_cdf.C_EOBPT256
    } else if ms == 5usize {
        off = av1_cdf.C_EOBPT512
    } else {
        off = av1_cdf.C_EOBPT1024
    }
    if ms < 5usize {
        off += (ptype * 2usize + cx) * (n + 1usize)
    } else {
        off += ptype * (n + 1usize)
    }
    ret av1_sym.read_symbol(sd, ctx[off..off + n + 1usize], n)
}

fn set_contexts(p: *CoefParams, x4: usize, y4: usize, w4: usize, h4: usize, cul_level: u32, dc_category: u32) {
    var i = 0usize
    while i < w4 {
        if x4 + i < p.above_level.len { p.above_level[x4 + i] = u8(cul_level) }
        if x4 + i < p.above_dc.len { p.above_dc[x4 + i] = u8(dc_category) }
        i += 1usize
    }
    i = 0usize
    while i < h4 {
        if y4 + i < p.left_level.len { p.left_level[y4 + i] = u8(cul_level) }
        if y4 + i < p.left_dc.len { p.left_dc[y4 + i] = u8(dc_category) }
        i += 1usize
    }
}

// Reads the levels of the coefficients of coeffs() (Quant before the signs). The levels already read live in padded
// arrays (`lv` the level, `l3` the level capped at 3) whose zero margins stand for the neighbours outside the block, so the
// neighbour sums need no bounds tests; every neighbour offset of the specification points right or down.
fn read_levels(sd: *av1_sym.Sym, ctx: []u16, tab: []const i32, p: *CoefParams, quant: []i32, scan: []const i32, eob: usize, tx_class: usize, tx_sz_ctx: usize, ptype: usize) {
    let adj = tv(tab, av1_tables.T_ADJUSTED_TX_SIZE, p.tx_size)
    let bwl = tv(tab, av1_tables.T_TX_WIDTH_LOG2, adj)
    let width = 1usize << bwl
    let height = tv(tab, av1_tables.T_TX_HEIGHT, adj)
    let stride = width + 4usize
    var lv: [1296]u8 = undef
    var l3: [1296]u8 = undef
    let padded = ((height + 4usize) * stride + 7usize) & ~7usize
    if eob == 0usize || eob > scan.len || quant.len < (height << bwl) || padded > 1296usize { ret }
    var d: [5]usize = zero
    var m: [3]usize = zero
    var i = 0usize
    while i < 5usize {
        let o = av1_tables.T_SIG_REF_DIFF_OFFSET + (tx_class * 5usize + i) * 2usize
        d[i] = usize(tab[o]) * stride + usize(tab[o + 1usize])
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        let o = av1_tables.T_MAG_REF_OFFSET_WITH_TX_CLASS + (tx_class * 3usize + i) * 2usize
        m[i] = usize(tab[o]) * stride + usize(tab[o + 1usize])
        i += 1usize
    }
    let d0 = d[0usize]
    let d1 = d[1usize]
    let d2 = d[2usize]
    let d3 = d[3usize]
    let d4 = d[4usize]
    let m0 = m[0usize]
    let m1 = m[1usize]
    let m2 = m[2usize]
    let base_off = av1_cdf.C_COEFFBASE + (tx_sz_ctx * 2usize + ptype) * SIG_COEF_CONTEXTS * 5usize
    let br_off = av1_cdf.C_COEFFBR + (umin(tx_sz_ctx, TX_32X32) * 2usize + ptype) * 21usize * 5usize
    let eob_off = av1_cdf.C_COEFFBASEEOB + (tx_sz_ctx * 2usize + ptype) * 16usize
    let pos_ctx_off = av1_tables.T_COEFF_BASE_POS_CTX_OFFSET
    let ctx_2d_off = av1_tables.T_COEFF_BASE_CTX_OFFSET + p.tx_size * 25usize
    let wmask = width - 1usize
    @nocheck {
        i = 0usize
        while i < padded {
            *mem.cast[*u64](&lv[i]) = 0u64
            *mem.cast[*u64](&l3[i]) = 0u64
            i += 8usize
        }
        // the state of the symbol decoder lives in locals for the whole loop; it is written back to sd for a refill or a call
        var dif = sd.dif
        var rng = sd.range
        var cnt = sd.cnt
        let adapt = sd.adapt
        var c = eob
        while c > 0usize {
            c -= 1usize
            let pos = usize(scan[c])
            let row = pos >> bwl
            let col = pos & wmask
            let pi = row * stride + col
            var level = 0u32
            var off = 0usize
            var phase = 0u32
            var more = true
            if c == eob - 1usize {
                var cx = 3usize
                if c == 0usize {
                    cx = 0usize
                } else if c <= (height << bwl) / 8usize {
                    cx = 1usize
                } else if c <= (height << bwl) / 4usize {
                    cx = 2usize
                }
                let eoff = eob_off + cx * 4usize
                sd.dif = dif
                sd.range = rng
                sd.cnt = cnt
                level = u32(av1_sym.read_symbol(sd, ctx[eoff..eoff + 4usize], 3usize)) + 1u32
                dif = sd.dif
                rng = sd.range
                cnt = sd.cnt
                phase = 1u32
            } else {
                let mag = u32(l3[pi + d0]) + u32(l3[pi + d1]) + u32(l3[pi + d2]) + u32(l3[pi + d3]) + u32(l3[pi + d4])
                var cx = usize((mag + 1u32) >> 1u32)
                if cx > 4usize { cx = 4usize }
                if tx_class == TX_CLASS_2D {
                    if pos == 0usize {
                        cx = 0usize
                    } else {
                        cx += usize(tab[ctx_2d_off + umin(row, 4usize) * 5usize + umin(col, 4usize)])
                    }
                } else if tx_class == TX_CLASS_VERT {
                    cx += usize(tab[pos_ctx_off + umin(row, 2usize)])
                } else {
                    cx += usize(tab[pos_ctx_off + umin(col, 2usize)])
                }
                off = base_off + cx * 5usize
            }
            if phase == 1u32 {
                if level > 2u32 {
                    let mag = u32(lv[pi + m0]) + u32(lv[pi + m1]) + u32(lv[pi + m2])
                    var cx = usize((mag + 1u32) >> 1u32)
                    if cx > 6usize { cx = 6usize }
                    if pos != 0usize {
                        var near = false
                        if tx_class == TX_CLASS_2D {
                            near = row < 2usize && col < 2usize
                        } else if tx_class == TX_CLASS_HORIZ {
                            near = col == 0usize
                        } else {
                            near = row == 0usize
                        }
                        if near { cx += 7usize } else { cx += 14usize }
                    }
                    off = br_off + cx * 5usize
                } else {
                    more = false
                }
            }
            while more {
                // one symbol of four values at ctx[off..]: the work of av1_sym.read_symbol4 with the state in locals
                if cnt < 16i32 {
                    sd.dif = dif
                    sd.cnt = cnt
                    av1_sym.refill(sd)
                    dif = sd.dif
                    cnt = sd.cnt
                }
                let v = u32(dif >> 48u32)
                let r8 = rng >> 8u32
                var symbol = 3usize
                var prev = rng
                var cur = 0u32
                let c0 = ((r8 * ((32768u32 - u32(ctx[off])) >> 6u32)) >> 1u32) + 12u32
                if v >= c0 {
                    symbol = 0usize
                    cur = c0
                } else {
                    let c1 = ((r8 * ((32768u32 - u32(ctx[off + 1usize])) >> 6u32)) >> 1u32) + 8u32
                    if v >= c1 {
                        symbol = 1usize
                        cur = c1
                        prev = c0
                    } else {
                        let c2 = ((r8 * ((32768u32 - u32(ctx[off + 2usize])) >> 6u32)) >> 1u32) + 4u32
                        prev = c1
                        if v >= c2 {
                            symbol = 2usize
                            cur = c2
                        } else {
                            prev = c2
                        }
                    }
                }
                let range = prev - cur
                var nb = 0u32
                var x = range
                if x < 256u32 {
                    x = x << 8u32
                    nb = 8u32
                }
                if x < 4096u32 {
                    x = x << 4u32
                    nb += 4u32
                }
                if x < 16384u32 {
                    x = x << 2u32
                    nb += 2u32
                }
                if x < 32768u32 { nb += 1u32 }
                rng = range << nb
                dif = (dif - (u64(cur) << 48u32)) << nb
                cnt -= i32(nb)
                if adapt {
                    let cn = ctx[off + 4usize]
                    var rate = 5u32
                    if cn > 15u16 { rate += 1u32 }
                    if cn > 31u16 { rate += 1u32 }
                    var k = 0usize
                    while k < symbol {
                        let cv = u32(ctx[off + k])
                        ctx[off + k] = u16(cv - (cv >> rate))
                        k += 1usize
                    }
                    while k < 3usize {
                        let cv = u32(ctx[off + k])
                        ctx[off + k] = u16(cv + ((32768u32 - cv) >> rate))
                        k += 1usize
                    }
                    if cn < 32u16 { ctx[off + 4usize] = cn + 1u16 }
                }
                if phase == 0u32 {
                    level = u32(symbol)
                    phase = 1u32
                    if level > 2u32 {
                        let mag = u32(lv[pi + m0]) + u32(lv[pi + m1]) + u32(lv[pi + m2])
                        var cx = usize((mag + 1u32) >> 1u32)
                        if cx > 6usize { cx = 6usize }
                        if pos != 0usize {
                            var near = false
                            if tx_class == TX_CLASS_2D {
                                near = row < 2usize && col < 2usize
                            } else if tx_class == TX_CLASS_HORIZ {
                                near = col == 0usize
                            } else {
                                near = row == 0usize
                            }
                            if near { cx += 7usize } else { cx += 14usize }
                        }
                        off = br_off + cx * 5usize
                    } else {
                        more = false
                    }
                } else {
                    level += u32(symbol)
                    if symbol < 3usize || phase == 4u32 { more = false }
                    phase += 1u32
                }
            }
            lv[pi] = u8(level)
            var capped = level
            if capped > 3u32 { capped = 3u32 }
            l3[pi] = u8(capped)
            quant[pos] = i32(level)
        }
        sd.dif = dif
        sd.range = rng
        sd.cnt = cnt
    }
}

// coeffs(plane, startX, startY, txSz). Returns the result and sets Quant, the above/left contexts and (luma) TxTypes.
fn coeffs(sd: *av1_sym.Sym, ctx: []u16, tab: []const i32, p: *CoefParams, quant: []i32) -> (CoefResult, err) {
    let x4 = p.start_x >> 2usize
    let y4 = p.start_y >> 2usize
    let w4 = tv(tab, av1_tables.T_TX_WIDTH, p.tx_size) >> 2usize
    let h4 = tv(tab, av1_tables.T_TX_HEIGHT, p.tx_size) >> 2usize
    let tx_sz_ctx = (tv(tab, av1_tables.T_TX_SIZE_SQR, p.tx_size) + tv(tab, av1_tables.T_TX_SIZE_SQR_UP, p.tx_size) + 1usize) >> 1usize
    var ptype = 0usize
    if p.plane > 0usize { ptype = 1usize }
    var seg_eob = umin(1024usize, tv(tab, av1_tables.T_TX_WIDTH, p.tx_size) * tv(tab, av1_tables.T_TX_HEIGHT, p.tx_size))
    if p.tx_size == TX_16X64 || p.tx_size == TX_64X16 { seg_eob = 512usize }
    if quant.len < seg_eob || p.tx_size > TX_64X16 { ret (zero, Invalid) }
    var c0 = 0usize
    @nocheck {
        while c0 < seg_eob {
            *mem.cast[*u64](&quant[c0]) = 0u64
            c0 += 2usize
        }
    }
    var res = CoefResult { eob: 0usize, tx_type: DCT_DCT, cul_level: 0u32, dc_category: 0u32 }

    let zcx = txb_skip_ctx(tab, p, x4, y4, w4, h4)
    let zoff = av1_cdf.C_TXBSKIP + (tx_sz_ctx * 13usize + zcx) * 3usize
    let all_zero = av1_sym.read_symbol(sd, ctx[zoff..zoff + 3usize], 2usize)
    if all_zero == 1usize {
        if p.plane == 0usize { set_tx_types(p, x4, y4, w4, h4, DCT_DCT) }
    } else {
        if p.plane == 0usize {
            let (_t, te) = transform_type(sd, ctx, tab, p, x4, y4)
            if te != ok { ret (zero, te) }
        }
        let tx_type = compute_tx_type(tab, p, x4, y4)
        res.tx_type = tx_type
        let tx_class = get_tx_class(tx_type)
        let scan = get_scan(tab, p.tx_size, tx_type)
        let wl = umin(tv(tab, av1_tables.T_TX_WIDTH_LOG2, p.tx_size), 5usize)
        let hl = umin(tv(tab, av1_tables.T_TX_HEIGHT_LOG2, p.tx_size), 5usize)
        let ms = wl + hl - 4usize
        let eob_pt = read_eob_pt(sd, ctx, ms, ptype, tx_class) + 1usize
        var eob = eob_pt
        if eob_pt >= 2usize { eob = (1usize << (eob_pt - 2usize)) + 1usize }
        if eob_pt >= 3usize {
            let eoff = av1_cdf.C_EOBEXTRA + (((tx_sz_ctx * 2usize + ptype) * 9usize) + eob_pt - 3usize) * 3usize
            let extra = av1_sym.read_symbol(sd, ctx[eoff..eoff + 3usize], 2usize)
            if extra == 1usize { eob += 1usize << (eob_pt - 3usize) }
            var i = 1usize
            while i < eob_pt - 2usize {
                let bit = av1_sym.read_bool(sd)
                if bit == 1u32 { eob += 1usize << (eob_pt - 3usize - i) }
                i += 1usize
            }
        }
        if eob > seg_eob { ret (zero, Invalid) }
        res.eob = eob
        read_levels(sd, ctx, tab, p, quant, scan, eob, tx_class, tx_sz_ctx, ptype)
        var cul = 0u32
        var c = 0usize
        var bad = false
        @nocheck {
        while c < eob && !bad {
            let pos = usize(scan[c])
            var q = quant[pos]
            if q != 0i32 {
                var sign = 0u32
                if c == 0usize {
                    let dcx = dc_sign_ctx(p, x4, y4, w4, h4)
                    let doff = av1_cdf.C_DCSIGN + (ptype * 3usize + dcx) * 3usize
                    sign = u32(av1_sym.read_symbol(sd, ctx[doff..doff + 3usize], 2usize))
                } else {
                    sign = av1_sym.read_bool(sd)
                }
                if q > NUM_BASE_LEVELS + COEFF_BASE_RANGE {
                    var length = 0u32
                    var done = false
                    while !done {
                        length += 1u32
                        if av1_sym.read_bool(sd) == 1u32 { done = true } else if length >= 20u32 {
                            bad = true
                            done = true
                        }
                    }
                    var x = 1i32
                    var i = 0u32
                    while i + 1u32 < length {
                        x = (x << 1u32) | i32(av1_sym.read_bool(sd))
                        i += 1u32
                    }
                    q = x + COEFF_BASE_RANGE + NUM_BASE_LEVELS
                }
                if pos == 0usize && q > 0i32 {
                    if sign == 1u32 { res.dc_category = 1u32 } else { res.dc_category = 2u32 }
                }
                q = q & 0xFFFFFi32
                cul += u32(q)
                if sign == 1u32 { q = 0i32 - q }
                quant[pos] = q
            }
            c += 1usize
        }
        }
        if bad { ret (zero, Invalid) }
        if cul > 63u32 { cul = 63u32 }
        res.cul_level = cul
    }
    set_contexts(p, x4, y4, w4, h4, res.cul_level, res.dc_category)
    ret (res, ok)
}
