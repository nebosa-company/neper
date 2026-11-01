// AV1 decoder state and header parsing: the bit reader, the OBU layer, the sequence header and the frame header (the
// uncompressed header and everything it calls), following the AV1 specification's syntax tables. The values keep the
// specification's names, in lower case with underscores, and live in `Seq` (the sequence) and `Hdr` (the frame being
// decoded; a few fields carry over from frame to frame as they do in the specification). The tile data is decoded by the
// modules that use this one.

use e.mem

error Invalid
error Unsupported
error TooLarge

const NUM_REF_FRAMES: usize = 8usize
const REFS_PER_FRAME: usize = 7usize
const TOTAL_REFS_PER_FRAME: usize = 8usize
const MAX_SEGMENTS: usize = 8usize
const SEG_LVL_MAX: usize = 8usize
const SEG_LVL_ALT_Q: usize = 0usize
const SEG_LVL_REF_FRAME: usize = 5usize
const PRIMARY_REF_NONE: i32 = 7i32
const MAX_TILE_COLS: usize = 64usize
const MAX_TILE_ROWS: usize = 64usize
const MAX_TILE_WIDTH: i32 = 4096i32
const MAX_TILE_AREA: i32 = 4096i32 * 2304i32
const SUPERRES_NUM: i32 = 8i32
const SUPERRES_DENOM_MIN: i32 = 9i32
const SUPERRES_DENOM_BITS: u32 = 3u32
const WARPEDMODEL_PREC_BITS: i32 = 16i32
const RESTORATION_TILESIZE_MAX: i32 = 256i32

const OBU_SEQUENCE_HEADER: u32 = 1u32
const OBU_TEMPORAL_DELIMITER: u32 = 2u32
const OBU_FRAME_HEADER: u32 = 3u32
const OBU_TILE_GROUP: u32 = 4u32
const OBU_METADATA: u32 = 5u32
const OBU_FRAME: u32 = 6u32
const OBU_REDUNDANT_FRAME_HEADER: u32 = 7u32
const OBU_TILE_LIST: u32 = 8u32
const OBU_PADDING: u32 = 15u32

const KEY_FRAME: i32 = 0i32
const INTER_FRAME: i32 = 1i32
const INTRA_ONLY_FRAME: i32 = 2i32
const SWITCH_FRAME: i32 = 3i32

const INTRA_FRAME: usize = 0usize
const LAST_FRAME: usize = 1usize
const LAST2_FRAME: usize = 2usize
const LAST3_FRAME: usize = 3usize
const GOLDEN_FRAME: usize = 4usize
const BWDREF_FRAME: usize = 5usize
const ALTREF2_FRAME: usize = 6usize
const ALTREF_FRAME: usize = 7usize

const RESTORE_NONE: i32 = 0i32
const RESTORE_WIENER: i32 = 1i32
const RESTORE_SGRPROJ: i32 = 2i32
const RESTORE_SWITCHABLE: i32 = 3i32

const ONLY_4X4: i32 = 0i32
const TX_MODE_LARGEST: i32 = 1i32
const TX_MODE_SELECT: i32 = 2i32

const SWITCHABLE: i32 = 4i32

const IDENTITY: i32 = 0i32
const TRANSLATION: i32 = 1i32
const ROTZOOM: i32 = 2i32
const AFFINE: i32 = 3i32

// ------------------------------------------------------------------ the bit reader

type Bits = struct { d: []const u8, at: usize, over: bool }

fn bits_of(d: []const u8) -> Bits {
    ret Bits { d: d, at: 0usize, over: false }
}

fn bit(b: *Bits) -> u32 {
    if (b.at >> 3usize) >= b.d.len {
        b.over = true
        b.at += 1usize
        ret 0u32
    }
    let v = (u32(b.d[b.at >> 3usize]) >> (7u32 - u32(b.at & 7usize))) & 1u32
    b.at += 1usize
    ret v
}

// f(n), n up to 32
fn f(b: *Bits, n: u32) -> u32 {
    var x = 0u32
    var i = 0u32
    while i < n {
        x = (x << 1u32) | bit(b)
        i += 1u32
    }
    ret x
}

fn flag(b: *Bits) -> bool {
    ret bit(b) == 1u32
}

fn fi(b: *Bits, n: u32) -> i32 {
    ret i32(f(b, n))
}

// su(n): n bits, two's complement
fn su(b: *Bits, n: u32) -> i32 {
    let v = i32(f(b, n))
    let sign = 1i32 << (n - 1u32)
    if (v & sign) != 0i32 { ret v - 2i32 * sign }
    ret v
}

fn floor_log2(x: u32) -> u32 {
    var s = 0u32
    var v = x
    while v > 1u32 {
        v = v >> 1u32
        s += 1u32
    }
    ret s
}

// ns(n): a non-symmetric unsigned value in 0..n-1
fn ns(b: *Bits, n: u32) -> u32 {
    let w = floor_log2(n) + 1u32
    let m = (1u32 << w) - n
    let v = f(b, w - 1u32)
    if v < m { ret v }
    let extra = f(b, 1u32)
    ret (v << 1u32) - m + extra
}

fn leb128(b: *Bits) -> u64 {
    var value = 0u64
    var i = 0u32
    while i < 8u32 {
        let byte = f(b, 8u32)
        value = value | (u64(byte & 127u32) << (u64(i) * 7u64))
        if (byte & 128u32) == 0u32 { break }
        i += 1u32
    }
    ret value
}

fn uvlc(b: *Bits) -> u32 {
    var leading = 0u32
    while leading < 32u32 {
        if flag(b) { break }
        leading += 1u32
    }
    if leading >= 32u32 { ret 4294967295u32 }
    let v = f(b, leading)
    ret v + (1u32 << leading) - 1u32
}

// ------------------------------------------------------------------ the sequence header

type Seq = struct {
    valid: bool,
    profile: i32,
    still_picture: bool,
    reduced_still_picture_header: bool,
    timing_info_present_flag: bool,
    decoder_model_info_present_flag: bool,
    equal_picture_interval: bool,
    buffer_delay_length_minus_1: i32,
    buffer_removal_time_length_minus_1: i32,
    frame_presentation_time_length_minus_1: i32,
    initial_display_delay_present_flag: bool,
    operating_points_cnt_minus_1: i32,
    operating_point_idc: [32]i32,
    decoder_model_present_for_this_op: [32]bool,
    frame_width_bits_minus_1: i32,
    frame_height_bits_minus_1: i32,
    max_frame_width_minus_1: i32,
    max_frame_height_minus_1: i32,
    frame_id_numbers_present_flag: bool,
    delta_frame_id_length_minus_2: i32,
    additional_frame_id_length_minus_1: i32,
    use_128x128_superblock: bool,
    enable_filter_intra: bool,
    enable_intra_edge_filter: bool,
    enable_interintra_compound: bool,
    enable_masked_compound: bool,
    enable_warped_motion: bool,
    enable_dual_filter: bool,
    enable_order_hint: bool,
    enable_jnt_comp: bool,
    enable_ref_frame_mvs: bool,
    seq_force_screen_content_tools: i32,
    seq_force_integer_mv: i32,
    order_hint_bits: i32,
    enable_superres: bool,
    enable_cdef: bool,
    enable_restoration: bool,
    bit_depth: i32,
    mono_chrome: bool,
    num_planes: i32,
    color_primaries: i32,
    transfer_characteristics: i32,
    matrix_coefficients: i32,
    color_range: bool,
    subsampling_x: i32,
    subsampling_y: i32,
    chroma_sample_position: i32,
    separate_uv_delta_q: bool,
    film_grain_params_present: bool,
}

const SELECT_SCREEN_CONTENT_TOOLS: i32 = 2i32
const SELECT_INTEGER_MV: i32 = 2i32

fn color_config(b: *Bits, s: *Seq) -> err {
    let high_bitdepth = flag(b)
    if s.profile == 2i32 && high_bitdepth {
        if flag(b) { s.bit_depth = 12i32 } else { s.bit_depth = 10i32 }
    } else if high_bitdepth {
        s.bit_depth = 10i32
    } else {
        s.bit_depth = 8i32
    }
    if s.profile == 1i32 { s.mono_chrome = false } else { s.mono_chrome = flag(b) }
    if s.mono_chrome { s.num_planes = 1i32 } else { s.num_planes = 3i32 }
    if flag(b) {
        s.color_primaries = fi(b, 8u32)
        s.transfer_characteristics = fi(b, 8u32)
        s.matrix_coefficients = fi(b, 8u32)
    } else {
        s.color_primaries = 2i32
        s.transfer_characteristics = 2i32
        s.matrix_coefficients = 2i32
    }
    if s.mono_chrome {
        s.color_range = flag(b)
        s.subsampling_x = 1i32
        s.subsampling_y = 1i32
        s.chroma_sample_position = 0i32
        s.separate_uv_delta_q = false
        ret ok
    } else if s.color_primaries == 1i32 && s.transfer_characteristics == 13i32 && s.matrix_coefficients == 0i32 {
        s.color_range = true
        s.subsampling_x = 0i32
        s.subsampling_y = 0i32
    } else {
        s.color_range = flag(b)
        if s.profile == 0i32 {
            s.subsampling_x = 1i32
            s.subsampling_y = 1i32
        } else if s.profile == 1i32 {
            s.subsampling_x = 0i32
            s.subsampling_y = 0i32
        } else {
            if s.bit_depth == 12i32 {
                s.subsampling_x = fi(b, 1u32)
                if s.subsampling_x == 1i32 { s.subsampling_y = fi(b, 1u32) } else { s.subsampling_y = 0i32 }
            } else {
                s.subsampling_x = 1i32
                s.subsampling_y = 0i32
            }
        }
        if s.subsampling_x == 1i32 && s.subsampling_y == 1i32 { s.chroma_sample_position = fi(b, 2u32) }
    }
    s.separate_uv_delta_q = flag(b)
    ret ok
}

fn sequence_header(b: *Bits, s: *Seq) -> err {
    s.profile = fi(b, 3u32)
    s.still_picture = flag(b)
    s.reduced_still_picture_header = flag(b)
    if s.reduced_still_picture_header {
        s.operating_point_idc[0usize] = 0i32
        let level = f(b, 5u32)
    } else {
        s.timing_info_present_flag = flag(b)
        if s.timing_info_present_flag {
            let ticks = f(b, 32u32)
            let scale = f(b, 32u32)
            s.equal_picture_interval = flag(b)
            if s.equal_picture_interval { let per = uvlc(b) }
            s.decoder_model_info_present_flag = flag(b)
            if s.decoder_model_info_present_flag {
                s.buffer_delay_length_minus_1 = fi(b, 5u32)
                let units = f(b, 32u32)
                s.buffer_removal_time_length_minus_1 = fi(b, 5u32)
                s.frame_presentation_time_length_minus_1 = fi(b, 5u32)
            }
        }
        s.initial_display_delay_present_flag = flag(b)
        s.operating_points_cnt_minus_1 = fi(b, 5u32)
        var i = 0i32
        while i <= s.operating_points_cnt_minus_1 {
            s.operating_point_idc[usize(i)] = fi(b, 12u32)
            let level = f(b, 5u32)
            if level > 7u32 { let tier = f(b, 1u32) }
            if s.decoder_model_info_present_flag {
                s.decoder_model_present_for_this_op[usize(i)] = flag(b)
                if s.decoder_model_present_for_this_op[usize(i)] {
                    let n = u32(s.buffer_delay_length_minus_1) + 1u32
                    let decoder_buffer_delay = f(b, n)
                    let encoder_buffer_delay = f(b, n)
                    let low_delay = f(b, 1u32)
                }
            }
            if s.initial_display_delay_present_flag {
                if flag(b) { let delay = f(b, 4u32) }
            }
            i += 1i32
        }
    }
    s.frame_width_bits_minus_1 = fi(b, 4u32)
    s.frame_height_bits_minus_1 = fi(b, 4u32)
    s.max_frame_width_minus_1 = fi(b, u32(s.frame_width_bits_minus_1) + 1u32)
    s.max_frame_height_minus_1 = fi(b, u32(s.frame_height_bits_minus_1) + 1u32)
    if s.reduced_still_picture_header { s.frame_id_numbers_present_flag = false } else { s.frame_id_numbers_present_flag = flag(b) }
    if s.frame_id_numbers_present_flag {
        s.delta_frame_id_length_minus_2 = fi(b, 4u32)
        s.additional_frame_id_length_minus_1 = fi(b, 3u32)
    }
    s.use_128x128_superblock = flag(b)
    s.enable_filter_intra = flag(b)
    s.enable_intra_edge_filter = flag(b)
    if s.reduced_still_picture_header {
        s.seq_force_screen_content_tools = SELECT_SCREEN_CONTENT_TOOLS
        s.seq_force_integer_mv = SELECT_INTEGER_MV
        s.order_hint_bits = 0i32
    } else {
        s.enable_interintra_compound = flag(b)
        s.enable_masked_compound = flag(b)
        s.enable_warped_motion = flag(b)
        s.enable_dual_filter = flag(b)
        s.enable_order_hint = flag(b)
        if s.enable_order_hint {
            s.enable_jnt_comp = flag(b)
            s.enable_ref_frame_mvs = flag(b)
        }
        if flag(b) { s.seq_force_screen_content_tools = SELECT_SCREEN_CONTENT_TOOLS } else { s.seq_force_screen_content_tools = fi(b, 1u32) }
        if s.seq_force_screen_content_tools > 0i32 {
            if flag(b) { s.seq_force_integer_mv = SELECT_INTEGER_MV } else { s.seq_force_integer_mv = fi(b, 1u32) }
        } else {
            s.seq_force_integer_mv = SELECT_INTEGER_MV
        }
        if s.enable_order_hint { s.order_hint_bits = fi(b, 3u32) + 1i32 } else { s.order_hint_bits = 0i32 }
    }
    s.enable_superres = flag(b)
    s.enable_cdef = flag(b)
    s.enable_restoration = flag(b)
    let color_error = color_config(b, s)
    if color_error != ok { ret color_error }
    s.film_grain_params_present = flag(b)
    if b.over { ret Invalid }
    s.valid = true
    ret ok
}


type RefInfo = struct {
    valid: bool,
    frame_id: i32,
    upscaled_width: i32,
    frame_width: i32,
    frame_height: i32,
    render_width: i32,
    render_height: i32,
    mi_cols: i32,
    mi_rows: i32,
    frame_type: i32,
    order_hint: i32,
    showable_frame: bool,
    saved_order_hints: [8]i32,
    gm_params: [48]i32,
    loop_filter_ref_deltas: [8]i32,
    loop_filter_mode_deltas: [2]i32,
    feature_enabled: [64]i32,
    feature_data: [64]i32,
    bit_depth: i32,
    subsampling_x: i32,
    subsampling_y: i32,
}

type Hdr = struct {
    show_existing_frame: bool,
    frame_to_show_map_idx: i32,
    frame_type: i32,
    frame_is_intra: bool,
    show_frame: bool,
    showable_frame: bool,
    error_resilient_mode: bool,
    disable_cdf_update: bool,
    allow_screen_content_tools: bool,
    force_integer_mv: bool,
    current_frame_id: i32,
    frame_size_override_flag: bool,
    order_hint: i32,
    primary_ref_frame: i32,
    refresh_frame_flags: i32,
    ref_order_hint: [8]i32,
    frame_width: i32,
    frame_height: i32,
    upscaled_width: i32,
    render_width: i32,
    render_height: i32,
    mi_cols: i32,
    mi_rows: i32,
    use_superres: bool,
    superres_denom: i32,
    allow_intrabc: bool,
    frame_refs_short_signaling: bool,
    ref_frame_idx: [7]i32,
    allow_high_precision_mv: bool,
    interpolation_filter: i32,
    is_motion_mode_switchable: bool,
    use_ref_frame_mvs: bool,
    order_hints: [8]i32,
    ref_frame_sign_bias: [8]i32,
    disable_frame_end_update_cdf: bool,
    // tile info
    tile_cols: i32,
    tile_rows: i32,
    tile_cols_log2: i32,
    tile_rows_log2: i32,
    mi_col_starts: [65]i32,
    mi_row_starts: [65]i32,
    context_update_tile_id: i32,
    tile_size_bytes: i32,
    // quantization
    base_q_idx: i32,
    delta_q_y_dc: i32,
    delta_q_u_dc: i32,
    delta_q_u_ac: i32,
    delta_q_v_dc: i32,
    delta_q_v_ac: i32,
    using_qmatrix: bool,
    qm_y: i32,
    qm_u: i32,
    qm_v: i32,
    // segmentation
    segmentation_enabled: bool,
    segmentation_update_map: bool,
    segmentation_temporal_update: bool,
    segmentation_update_data: bool,
    feature_enabled: [64]i32,
    feature_data: [64]i32,
    seg_id_pre_skip: bool,
    last_active_seg_id: i32,
    delta_q_present: bool,
    delta_q_res: i32,
    delta_lf_present: bool,
    delta_lf_res: i32,
    delta_lf_multi: bool,
    coded_lossless: bool,
    all_lossless: bool,
    lossless_array: [8]bool,
    seg_qm_level: [24]i32,
    // loop filter
    loop_filter_level: [4]i32,
    loop_filter_sharpness: i32,
    loop_filter_delta_enabled: bool,
    loop_filter_ref_deltas: [8]i32,
    loop_filter_mode_deltas: [2]i32,
    // cdef
    cdef_damping: i32,
    cdef_bits: i32,
    cdef_y_pri_strength: [8]i32,
    cdef_y_sec_strength: [8]i32,
    cdef_uv_pri_strength: [8]i32,
    cdef_uv_sec_strength: [8]i32,
    // loop restoration
    frame_restoration_type: [3]i32,
    loop_restoration_size: [3]i32,
    uses_lr: bool,
    tx_mode: i32,
    reference_select: bool,
    skip_mode_present: bool,
    skip_mode_frame: [2]i32,
    allow_warped_motion: bool,
    reduced_tx_set: bool,
    gm_type: [8]i32,
    gm_params: [48]i32,
    prev_gm_params: [48]i32,
    // film grain (only whether it applies is kept: the sequences of interest carry none)
    apply_grain: bool,
}

type State = struct {
    seq: Seq,
    h: Hdr,
    refs: [8]RefInfo,
    seen_frame_header: bool,
    temporal_id: i32,
    spatial_id: i32,
    operating_point_idc: i32,
}

fn clip3(lo: i32, hi: i32, x: i32) -> i32 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn min_i32(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn max_i32(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn get_relative_dist(s: *const Seq, a: i32, b: i32) -> i32 {
    if !s.enable_order_hint { ret 0i32 }
    let diff = a - b
    let m = 1i32 << u32(s.order_hint_bits - 1i32)
    ret (diff & (m - 1i32)) - (diff & m)
}

fn tile_log2(blk_size: i32, goal: i32) -> i32 {
    var k = 0i32
    while (blk_size << u32(k)) < goal { k += 1i32 }
    ret k
}

fn default_gm(h: *Hdr, out: usize) {
    var i = 0usize
    while i < 6usize {
        if i % 3usize == 2usize { h.gm_params[out + i] = 65536i32 } else { h.gm_params[out + i] = 0i32 }
        i += 1usize
    }
}

fn setup_past_independence(h: *Hdr) {
    var i = 0usize
    while i < 64usize {
        h.feature_data[i] = 0i32
        h.feature_enabled[i] = 0i32
        i += 1usize
    }
    var r = 0usize
    while r < 8usize {
        var k = 0usize
        while k < 6usize {
            if k % 3usize == 2usize { h.prev_gm_params[r * 6usize + k] = 65536i32 } else { h.prev_gm_params[r * 6usize + k] = 0i32 }
            k += 1usize
        }
        r += 1usize
    }
    h.loop_filter_delta_enabled = true
    h.loop_filter_ref_deltas[INTRA_FRAME] = 1i32
    h.loop_filter_ref_deltas[LAST_FRAME] = 0i32
    h.loop_filter_ref_deltas[LAST2_FRAME] = 0i32
    h.loop_filter_ref_deltas[LAST3_FRAME] = 0i32
    h.loop_filter_ref_deltas[BWDREF_FRAME] = 0i32
    h.loop_filter_ref_deltas[GOLDEN_FRAME] = 0i32 - 1i32
    h.loop_filter_ref_deltas[ALTREF_FRAME] = 0i32 - 1i32
    h.loop_filter_ref_deltas[ALTREF2_FRAME] = 0i32 - 1i32
    h.loop_filter_mode_deltas[0usize] = 0i32
    h.loop_filter_mode_deltas[1usize] = 0i32
}

fn load_previous(st: *State) {
    let slot = usize(st.h.ref_frame_idx[usize(st.h.primary_ref_frame)])
    let r = &st.refs[slot]
    var i = 0usize
    while i < 48usize {
        st.h.prev_gm_params[i] = r.gm_params[i]
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        st.h.loop_filter_ref_deltas[i] = r.loop_filter_ref_deltas[i]
        i += 1usize
    }
    st.h.loop_filter_mode_deltas[0usize] = r.loop_filter_mode_deltas[0usize]
    st.h.loop_filter_mode_deltas[1usize] = r.loop_filter_mode_deltas[1usize]
    i = 0usize
    while i < 64usize {
        st.h.feature_enabled[i] = r.feature_enabled[i]
        st.h.feature_data[i] = r.feature_data[i]
        i += 1usize
    }
}

fn compute_image_size(h: *Hdr) {
    h.mi_cols = 2i32 * ((h.frame_width + 7i32) >> 3u32)
    h.mi_rows = 2i32 * ((h.frame_height + 7i32) >> 3u32)
}

fn superres_params(b: *Bits, s: *const Seq, h: *Hdr) {
    if s.enable_superres { h.use_superres = flag(b) } else { h.use_superres = false }
    if h.use_superres {
        let coded_denom = fi(b, SUPERRES_DENOM_BITS)
        h.superres_denom = coded_denom + SUPERRES_DENOM_MIN
    } else {
        h.superres_denom = SUPERRES_NUM
    }
    h.upscaled_width = h.frame_width
    h.frame_width = (h.upscaled_width * SUPERRES_NUM + (h.superres_denom / 2i32)) / h.superres_denom
}

fn frame_size(b: *Bits, s: *const Seq, h: *Hdr) {
    if h.frame_size_override_flag {
        h.frame_width = fi(b, u32(s.frame_width_bits_minus_1) + 1u32) + 1i32
        h.frame_height = fi(b, u32(s.frame_height_bits_minus_1) + 1u32) + 1i32
    } else {
        h.frame_width = s.max_frame_width_minus_1 + 1i32
        h.frame_height = s.max_frame_height_minus_1 + 1i32
    }
    superres_params(b, s, h)
    compute_image_size(h)
}

fn render_size(b: *Bits, h: *Hdr) {
    if flag(b) {
        h.render_width = fi(b, 16u32) + 1i32
        h.render_height = fi(b, 16u32) + 1i32
    } else {
        h.render_width = h.upscaled_width
        h.render_height = h.frame_height
    }
}

fn frame_size_with_refs(b: *Bits, st: *State) {
    var found = false
    var i = 0usize
    while i < REFS_PER_FRAME {
        found = flag(b)
        if found {
            let r = &st.refs[usize(st.h.ref_frame_idx[i])]
            st.h.upscaled_width = r.upscaled_width
            st.h.frame_width = st.h.upscaled_width
            st.h.frame_height = r.frame_height
            st.h.render_width = r.render_width
            st.h.render_height = r.render_height
            break
        }
        i += 1usize
    }
    if !found {
        frame_size(b, &st.seq, &st.h)
        render_size(b, &st.h)
    } else {
        superres_params(b, &st.seq, &st.h)
        compute_image_size(&st.h)
    }
}

fn read_delta_q(b: *Bits) -> i32 {
    if flag(b) { ret su(b, 7u32) }
    ret 0i32
}

fn quantization_params(b: *Bits, s: *const Seq, h: *Hdr) {
    h.base_q_idx = fi(b, 8u32)
    h.delta_q_y_dc = read_delta_q(b)
    if s.num_planes > 1i32 {
        var diff_uv_delta = false
        if s.separate_uv_delta_q { diff_uv_delta = flag(b) }
        h.delta_q_u_dc = read_delta_q(b)
        h.delta_q_u_ac = read_delta_q(b)
        if diff_uv_delta {
            h.delta_q_v_dc = read_delta_q(b)
            h.delta_q_v_ac = read_delta_q(b)
        } else {
            h.delta_q_v_dc = h.delta_q_u_dc
            h.delta_q_v_ac = h.delta_q_u_ac
        }
    } else {
        h.delta_q_u_dc = 0i32
        h.delta_q_u_ac = 0i32
        h.delta_q_v_dc = 0i32
        h.delta_q_v_ac = 0i32
    }
    h.using_qmatrix = flag(b)
    if h.using_qmatrix {
        h.qm_y = fi(b, 4u32)
        h.qm_u = fi(b, 4u32)
        if !s.separate_uv_delta_q { h.qm_v = h.qm_u } else { h.qm_v = fi(b, 4u32) }
    }
}

fn seg_feature_bits(j: usize) -> u32 {
    if j == 0usize { ret 8u32 }
    if j >= 1usize && j <= 4usize { ret 6u32 }
    if j == 5usize { ret 3u32 }
    ret 0u32
}

fn seg_feature_signed(j: usize) -> bool {
    ret j <= 4usize
}

fn seg_feature_max(j: usize) -> i32 {
    if j == 0usize { ret 255i32 }
    if j >= 1usize && j <= 4usize { ret 63i32 }
    if j == 5usize { ret 7i32 }
    ret 0i32
}

fn segmentation_params(b: *Bits, h: *Hdr) {
    h.segmentation_enabled = flag(b)
    if h.segmentation_enabled {
        if h.primary_ref_frame == PRIMARY_REF_NONE {
            h.segmentation_update_map = true
            h.segmentation_temporal_update = false
            h.segmentation_update_data = true
        } else {
            h.segmentation_update_map = flag(b)
            h.segmentation_temporal_update = false
            if h.segmentation_update_map { h.segmentation_temporal_update = flag(b) }
            h.segmentation_update_data = flag(b)
        }
        if h.segmentation_update_data {
            var i = 0usize
            while i < MAX_SEGMENTS {
                var j = 0usize
                while j < SEG_LVL_MAX {
                    let enabled = flag(b)
                    var enabled_value = 0i32
                    if enabled { enabled_value = 1i32 }
                    h.feature_enabled[i * 8usize + j] = enabled_value
                    var clipped = 0i32
                    if enabled {
                        let bits_to_read = seg_feature_bits(j)
                        let limit = seg_feature_max(j)
                        if seg_feature_signed(j) {
                            let v = su(b, 1u32 + bits_to_read)
                            clipped = clip3(0i32 - limit, limit, v)
                        } else {
                            let v = fi(b, bits_to_read)
                            clipped = clip3(0i32, limit, v)
                        }
                    }
                    h.feature_data[i * 8usize + j] = clipped
                    j += 1usize
                }
                i += 1usize
            }
        }
    } else {
        var i = 0usize
        while i < 64usize {
            h.feature_enabled[i] = 0i32
            h.feature_data[i] = 0i32
            i += 1usize
        }
    }
    h.seg_id_pre_skip = false
    h.last_active_seg_id = 0i32
    var i2 = 0usize
    while i2 < MAX_SEGMENTS {
        var j2 = 0usize
        while j2 < SEG_LVL_MAX {
            if h.feature_enabled[i2 * 8usize + j2] != 0i32 {
                h.last_active_seg_id = i32(i2)
                if j2 >= SEG_LVL_REF_FRAME { h.seg_id_pre_skip = true }
            }
            j2 += 1usize
        }
        i2 += 1usize
    }
}

fn tile_info(b: *Bits, s: *const Seq, h: *Hdr) -> err {
    var sb_cols = (h.mi_cols + 15i32) >> 4u32
    var sb_rows = (h.mi_rows + 15i32) >> 4u32
    var sb_shift = 4i32
    if s.use_128x128_superblock {
        sb_cols = (h.mi_cols + 31i32) >> 5u32
        sb_rows = (h.mi_rows + 31i32) >> 5u32
        sb_shift = 5i32
    }
    let sb_size = sb_shift + 2i32
    let max_tile_width_sb = MAX_TILE_WIDTH >> u32(sb_size)
    var max_tile_area_sb = MAX_TILE_AREA >> u32(2i32 * sb_size)
    let min_log2_tile_cols = tile_log2(max_tile_width_sb, sb_cols)
    let max_log2_tile_cols = tile_log2(1i32, min_i32(sb_cols, i32(MAX_TILE_COLS)))
    let max_log2_tile_rows = tile_log2(1i32, min_i32(sb_rows, i32(MAX_TILE_ROWS)))
    let min_log2_tiles = max_i32(min_log2_tile_cols, tile_log2(max_tile_area_sb, sb_rows * sb_cols))
    let uniform = flag(b)
    if uniform {
        h.tile_cols_log2 = min_log2_tile_cols
        while h.tile_cols_log2 < max_log2_tile_cols {
            if flag(b) { h.tile_cols_log2 += 1i32 } else { break }
        }
        let tile_width_sb = (sb_cols + (1i32 << u32(h.tile_cols_log2)) - 1i32) >> u32(h.tile_cols_log2)
        var i = 0i32
        var start_sb = 0i32
        while start_sb < sb_cols {
            if i >= 64i32 { ret Invalid }
            h.mi_col_starts[usize(i)] = start_sb << u32(sb_shift)
            i += 1i32
            start_sb += tile_width_sb
        }
        h.mi_col_starts[usize(i)] = h.mi_cols
        h.tile_cols = i
        let min_log2_tile_rows = max_i32(min_log2_tiles - h.tile_cols_log2, 0i32)
        h.tile_rows_log2 = min_log2_tile_rows
        while h.tile_rows_log2 < max_log2_tile_rows {
            if flag(b) { h.tile_rows_log2 += 1i32 } else { break }
        }
        let tile_height_sb = (sb_rows + (1i32 << u32(h.tile_rows_log2)) - 1i32) >> u32(h.tile_rows_log2)
        i = 0i32
        start_sb = 0i32
        while start_sb < sb_rows {
            if i >= 64i32 { ret Invalid }
            h.mi_row_starts[usize(i)] = start_sb << u32(sb_shift)
            i += 1i32
            start_sb += tile_height_sb
        }
        h.mi_row_starts[usize(i)] = h.mi_rows
        h.tile_rows = i
    } else {
        var widest_tile_sb = 0i32
        var start_sb = 0i32
        var i = 0i32
        while start_sb < sb_cols {
            if i >= 64i32 { ret Invalid }
            h.mi_col_starts[usize(i)] = start_sb << u32(sb_shift)
            let max_width = min_i32(sb_cols - start_sb, max_tile_width_sb)
            let size_sb = i32(ns(b, u32(max_width))) + 1i32
            widest_tile_sb = max_i32(size_sb, widest_tile_sb)
            start_sb += size_sb
            i += 1i32
        }
        h.mi_col_starts[usize(i)] = h.mi_cols
        h.tile_cols = i
        h.tile_cols_log2 = tile_log2(1i32, h.tile_cols)
        if min_log2_tiles > 0i32 { max_tile_area_sb = (sb_rows * sb_cols) >> u32(min_log2_tiles + 1i32) } else { max_tile_area_sb = sb_rows * sb_cols }
        let max_tile_height_sb = max_i32(max_tile_area_sb / widest_tile_sb, 1i32)
        start_sb = 0i32
        i = 0i32
        while start_sb < sb_rows {
            if i >= 64i32 { ret Invalid }
            h.mi_row_starts[usize(i)] = start_sb << u32(sb_shift)
            let max_height = min_i32(sb_rows - start_sb, max_tile_height_sb)
            let size_sb = i32(ns(b, u32(max_height))) + 1i32
            start_sb += size_sb
            i += 1i32
        }
        h.mi_row_starts[usize(i)] = h.mi_rows
        h.tile_rows = i
        h.tile_rows_log2 = tile_log2(1i32, h.tile_rows)
    }
    if h.tile_cols_log2 > 0i32 || h.tile_rows_log2 > 0i32 {
        h.context_update_tile_id = fi(b, u32(h.tile_rows_log2 + h.tile_cols_log2))
        h.tile_size_bytes = fi(b, 2u32) + 1i32
    } else {
        h.context_update_tile_id = 0i32
    }
    ret ok
}

fn delta_q_params(b: *Bits, h: *Hdr) {
    h.delta_q_res = 0i32
    h.delta_q_present = false
    if h.base_q_idx > 0i32 { h.delta_q_present = flag(b) }
    if h.delta_q_present { h.delta_q_res = fi(b, 2u32) }
}

fn delta_lf_params(b: *Bits, h: *Hdr) {
    h.delta_lf_present = false
    h.delta_lf_res = 0i32
    h.delta_lf_multi = false
    if h.delta_q_present {
        if !h.allow_intrabc { h.delta_lf_present = flag(b) }
        if h.delta_lf_present {
            h.delta_lf_res = fi(b, 2u32)
            h.delta_lf_multi = flag(b)
        }
    }
}

fn seg_feature_active_idx(h: *const Hdr, idx: usize, feature: usize) -> bool {
    ret h.segmentation_enabled && h.feature_enabled[idx * 8usize + feature] != 0i32
}

// the quantizer index of a segment, without the block-level delta (get_qindex with ignoreDeltaQ equal to 1)
fn get_qindex_frame(h: *const Hdr, segment_id: usize) -> i32 {
    if seg_feature_active_idx(h, segment_id, SEG_LVL_ALT_Q) {
        ret clip3(0i32, 255i32, h.base_q_idx + h.feature_data[segment_id * 8usize + SEG_LVL_ALT_Q])
    }
    ret h.base_q_idx
}

fn loop_filter_params(b: *Bits, s: *const Seq, h: *Hdr) {
    if h.coded_lossless || h.allow_intrabc {
        h.loop_filter_level[0usize] = 0i32
        h.loop_filter_level[1usize] = 0i32
        h.loop_filter_ref_deltas[INTRA_FRAME] = 1i32
        h.loop_filter_ref_deltas[LAST_FRAME] = 0i32
        h.loop_filter_ref_deltas[LAST2_FRAME] = 0i32
        h.loop_filter_ref_deltas[LAST3_FRAME] = 0i32
        h.loop_filter_ref_deltas[BWDREF_FRAME] = 0i32
        h.loop_filter_ref_deltas[GOLDEN_FRAME] = 0i32 - 1i32
        h.loop_filter_ref_deltas[ALTREF_FRAME] = 0i32 - 1i32
        h.loop_filter_ref_deltas[ALTREF2_FRAME] = 0i32 - 1i32
        h.loop_filter_mode_deltas[0usize] = 0i32
        h.loop_filter_mode_deltas[1usize] = 0i32
        ret
    }
    h.loop_filter_level[0usize] = fi(b, 6u32)
    h.loop_filter_level[1usize] = fi(b, 6u32)
    if s.num_planes > 1i32 {
        if h.loop_filter_level[0usize] != 0i32 || h.loop_filter_level[1usize] != 0i32 {
            h.loop_filter_level[2usize] = fi(b, 6u32)
            h.loop_filter_level[3usize] = fi(b, 6u32)
        }
    }
    h.loop_filter_sharpness = fi(b, 3u32)
    h.loop_filter_delta_enabled = flag(b)
    if h.loop_filter_delta_enabled {
        if flag(b) {
            var i = 0usize
            while i < TOTAL_REFS_PER_FRAME {
                if flag(b) { h.loop_filter_ref_deltas[i] = su(b, 7u32) }
                i += 1usize
            }
            i = 0usize
            while i < 2usize {
                if flag(b) { h.loop_filter_mode_deltas[i] = su(b, 7u32) }
                i += 1usize
            }
        }
    }
}

fn cdef_params(b: *Bits, s: *const Seq, h: *Hdr) {
    if h.coded_lossless || h.allow_intrabc || !s.enable_cdef {
        h.cdef_bits = 0i32
        h.cdef_y_pri_strength[0usize] = 0i32
        h.cdef_y_sec_strength[0usize] = 0i32
        h.cdef_uv_pri_strength[0usize] = 0i32
        h.cdef_uv_sec_strength[0usize] = 0i32
        h.cdef_damping = 3i32
        ret
    }
    h.cdef_damping = fi(b, 2u32) + 3i32
    h.cdef_bits = fi(b, 2u32)
    var i = 0i32
    while i < (1i32 << u32(h.cdef_bits)) {
        h.cdef_y_pri_strength[usize(i)] = fi(b, 4u32)
        h.cdef_y_sec_strength[usize(i)] = fi(b, 2u32)
        if h.cdef_y_sec_strength[usize(i)] == 3i32 { h.cdef_y_sec_strength[usize(i)] += 1i32 }
        if s.num_planes > 1i32 {
            h.cdef_uv_pri_strength[usize(i)] = fi(b, 4u32)
            h.cdef_uv_sec_strength[usize(i)] = fi(b, 2u32)
            if h.cdef_uv_sec_strength[usize(i)] == 3i32 { h.cdef_uv_sec_strength[usize(i)] += 1i32 }
        }
        i += 1i32
    }
}

fn remap_lr_type(t: i32) -> i32 {
    if t == 0i32 { ret RESTORE_NONE }
    if t == 1i32 { ret RESTORE_SWITCHABLE }
    if t == 2i32 { ret RESTORE_WIENER }
    ret RESTORE_SGRPROJ
}

fn lr_params(b: *Bits, s: *const Seq, h: *Hdr) {
    h.frame_restoration_type[0usize] = RESTORE_NONE
    h.frame_restoration_type[1usize] = RESTORE_NONE
    h.frame_restoration_type[2usize] = RESTORE_NONE
    h.uses_lr = false
    if h.all_lossless || h.allow_intrabc || !s.enable_restoration { ret }
    var uses_chroma_lr = false
    var i = 0usize
    while i < usize(s.num_planes) {
        h.frame_restoration_type[i] = remap_lr_type(fi(b, 2u32))
        if h.frame_restoration_type[i] != RESTORE_NONE {
            h.uses_lr = true
            if i > 0usize { uses_chroma_lr = true }
        }
        i += 1usize
    }
    if h.uses_lr {
        var lr_unit_shift = 0i32
        if s.use_128x128_superblock {
            lr_unit_shift = fi(b, 1u32) + 1i32
        } else {
            lr_unit_shift = fi(b, 1u32)
            if lr_unit_shift != 0i32 { lr_unit_shift += fi(b, 1u32) }
        }
        h.loop_restoration_size[0usize] = RESTORATION_TILESIZE_MAX >> u32(2i32 - lr_unit_shift)
        var lr_uv_shift = 0i32
        if s.subsampling_x == 1i32 && s.subsampling_y == 1i32 && uses_chroma_lr { lr_uv_shift = fi(b, 1u32) }
        h.loop_restoration_size[1usize] = h.loop_restoration_size[0usize] >> u32(lr_uv_shift)
        h.loop_restoration_size[2usize] = h.loop_restoration_size[0usize] >> u32(lr_uv_shift)
    }
}

fn read_tx_mode(b: *Bits, h: *Hdr) {
    if h.coded_lossless {
        h.tx_mode = ONLY_4X4
    } else if flag(b) {
        h.tx_mode = TX_MODE_SELECT
    } else {
        h.tx_mode = TX_MODE_LARGEST
    }
}

fn skip_mode_params(b: *Bits, st: *State) {
    let s = &st.seq
    let h = &st.h
    var skip_mode_allowed = false
    if h.frame_is_intra || !h.reference_select || !s.enable_order_hint {
        skip_mode_allowed = false
    } else {
        var forward_idx = 0i32 - 1i32
        var backward_idx = 0i32 - 1i32
        var forward_hint = 0i32
        var backward_hint = 0i32
        var i = 0usize
        while i < REFS_PER_FRAME {
            let ref_hint = st.refs[usize(h.ref_frame_idx[i])].order_hint
            if get_relative_dist(s, ref_hint, h.order_hint) < 0i32 {
                if forward_idx < 0i32 || get_relative_dist(s, ref_hint, forward_hint) > 0i32 {
                    forward_idx = i32(i)
                    forward_hint = ref_hint
                }
            } else if get_relative_dist(s, ref_hint, h.order_hint) > 0i32 {
                if backward_idx < 0i32 || get_relative_dist(s, ref_hint, backward_hint) < 0i32 {
                    backward_idx = i32(i)
                    backward_hint = ref_hint
                }
            }
            i += 1usize
        }
        if forward_idx < 0i32 {
            skip_mode_allowed = false
        } else if backward_idx >= 0i32 {
            skip_mode_allowed = true
            h.skip_mode_frame[0usize] = i32(LAST_FRAME) + min_i32(forward_idx, backward_idx)
            h.skip_mode_frame[1usize] = i32(LAST_FRAME) + max_i32(forward_idx, backward_idx)
        } else {
            var second_forward_idx = 0i32 - 1i32
            var second_forward_hint = 0i32
            var k = 0usize
            while k < REFS_PER_FRAME {
                let ref_hint = st.refs[usize(h.ref_frame_idx[k])].order_hint
                if get_relative_dist(s, ref_hint, forward_hint) < 0i32 {
                    if second_forward_idx < 0i32 || get_relative_dist(s, ref_hint, second_forward_hint) > 0i32 {
                        second_forward_idx = i32(k)
                        second_forward_hint = ref_hint
                    }
                }
                k += 1usize
            }
            if second_forward_idx < 0i32 {
                skip_mode_allowed = false
            } else {
                skip_mode_allowed = true
                h.skip_mode_frame[0usize] = i32(LAST_FRAME) + min_i32(forward_idx, second_forward_idx)
                h.skip_mode_frame[1usize] = i32(LAST_FRAME) + max_i32(forward_idx, second_forward_idx)
            }
        }
    }
    if skip_mode_allowed { h.skip_mode_present = flag(b) } else { h.skip_mode_present = false }
}

fn inverse_recenter(r: i32, v: i32) -> i32 {
    if v > 2i32 * r { ret v }
    if (v & 1i32) != 0i32 { ret r - ((v + 1i32) >> 1u32) }
    ret r + (v >> 1u32)
}

fn decode_subexp(b: *Bits, num_syms: i32) -> i32 {
    var i = 0i32
    var mk = 0i32
    let k = 3i32
    while true {
        var b2 = k
        if i != 0i32 { b2 = k + i - 1i32 }
        let a = 1i32 << u32(b2)
        if num_syms <= mk + 3i32 * a {
            let v = i32(ns(b, u32(num_syms - mk)))
            ret v + mk
        } else {
            if flag(b) {
                i += 1i32
                mk += a
            } else {
                let v = fi(b, u32(b2))
                ret v + mk
            }
        }
    }
    ret 0i32
}

fn decode_unsigned_subexp_with_ref(b: *Bits, mx: i32, r: i32) -> i32 {
    let v = decode_subexp(b, mx)
    if (r << 1u32) <= mx { ret inverse_recenter(r, v) }
    ret mx - 1i32 - inverse_recenter(mx - 1i32 - r, v)
}

fn decode_signed_subexp_with_ref(b: *Bits, low: i32, high: i32, r: i32) -> i32 {
    let x = decode_unsigned_subexp_with_ref(b, high - low, r - low)
    ret x + low
}

fn read_global_param(b: *Bits, h: *Hdr, gtype: i32, ref: usize, idx: usize) {
    var abs_bits = 12i32
    var prec_bits = 15i32
    if idx < 2usize {
        if gtype == TRANSLATION {
            var hp = 0i32
            if !h.allow_high_precision_mv { hp = 1i32 }
            abs_bits = 9i32 - hp
            prec_bits = 3i32 - hp
        } else {
            abs_bits = 12i32
            prec_bits = 6i32
        }
    }
    let prec_diff = WARPEDMODEL_PREC_BITS - prec_bits
    var round = 0i32
    var sub = 0i32
    if idx % 3usize == 2usize {
        round = 65536i32
        sub = 1i32 << u32(prec_bits)
    }
    let mx = 1i32 << u32(abs_bits)
    let r = (h.prev_gm_params[ref * 6usize + idx] >> u32(prec_diff)) - sub
    h.gm_params[ref * 6usize + idx] = (decode_signed_subexp_with_ref(b, 0i32 - mx, mx + 1i32, r) << u32(prec_diff)) + round
}

fn global_motion_params(b: *Bits, h: *Hdr) {
    var ref = LAST_FRAME
    while ref <= ALTREF_FRAME {
        h.gm_type[ref] = IDENTITY
        default_gm(h, ref * 6usize)
        ref += 1usize
    }
    if h.frame_is_intra { ret }
    ref = LAST_FRAME
    while ref <= ALTREF_FRAME {
        var gtype = IDENTITY
        if flag(b) {
            if flag(b) {
                gtype = ROTZOOM
            } else if flag(b) {
                gtype = TRANSLATION
            } else {
                gtype = AFFINE
            }
        }
        h.gm_type[ref] = gtype
        if gtype >= ROTZOOM {
            read_global_param(b, h, gtype, ref, 2usize)
            read_global_param(b, h, gtype, ref, 3usize)
            if gtype == AFFINE {
                read_global_param(b, h, gtype, ref, 4usize)
                read_global_param(b, h, gtype, ref, 5usize)
            } else {
                h.gm_params[ref * 6usize + 4usize] = 0i32 - h.gm_params[ref * 6usize + 3usize]
                h.gm_params[ref * 6usize + 5usize] = h.gm_params[ref * 6usize + 2usize]
            }
        }
        if gtype >= TRANSLATION {
            read_global_param(b, h, gtype, ref, 0usize)
            read_global_param(b, h, gtype, ref, 1usize)
        }
        ref += 1usize
    }
}

// the film grain syntax is read to keep the bit position right; only whether the grain applies is kept
fn film_grain_params(b: *Bits, st: *State) -> err {
    let s = &st.seq
    let h = &st.h
    h.apply_grain = false
    if !s.film_grain_params_present || (!h.show_frame && !h.showable_frame) { ret ok }
    h.apply_grain = flag(b)
    if !h.apply_grain { ret ok }
    let grain_seed = f(b, 16u32)
    var update_grain = true
    if h.frame_type == INTER_FRAME { update_grain = flag(b) }
    if !update_grain {
        let ref_idx = f(b, 3u32)
        ret ok
    }
    let num_y_points = f(b, 4u32)
    var i = 0u32
    while i < num_y_points {
        let v = f(b, 16u32)
        i += 1u32
    }
    var chroma_scaling_from_luma = false
    if !s.mono_chrome { chroma_scaling_from_luma = flag(b) }
    var num_cb_points = 0u32
    var num_cr_points = 0u32
    if s.mono_chrome || chroma_scaling_from_luma || (s.subsampling_x == 1i32 && s.subsampling_y == 1i32 && num_y_points == 0u32) {
        num_cb_points = 0u32
        num_cr_points = 0u32
    } else {
        num_cb_points = f(b, 4u32)
        i = 0u32
        while i < num_cb_points {
            let v = f(b, 16u32)
            i += 1u32
        }
        num_cr_points = f(b, 4u32)
        i = 0u32
        while i < num_cr_points {
            let v = f(b, 16u32)
            i += 1u32
        }
    }
    let grain_scaling_minus_8 = f(b, 2u32)
    let ar_coeff_lag = f(b, 2u32)
    let num_pos_luma = 2u32 * ar_coeff_lag * (ar_coeff_lag + 1u32)
    var num_pos_chroma = num_pos_luma
    if num_y_points != 0u32 {
        num_pos_chroma = num_pos_luma + 1u32
        i = 0u32
        while i < num_pos_luma {
            let v = f(b, 8u32)
            i += 1u32
        }
    }
    if chroma_scaling_from_luma || num_cb_points != 0u32 {
        i = 0u32
        while i < num_pos_chroma {
            let v = f(b, 8u32)
            i += 1u32
        }
    }
    if chroma_scaling_from_luma || num_cr_points != 0u32 {
        i = 0u32
        while i < num_pos_chroma {
            let v = f(b, 8u32)
            i += 1u32
        }
    }
    let ar_coeff_shift_minus_6 = f(b, 2u32)
    let grain_scale_shift = f(b, 2u32)
    if num_cb_points != 0u32 {
        let m = f(b, 8u32)
        let lm = f(b, 8u32)
        let o = f(b, 9u32)
    }
    if num_cr_points != 0u32 {
        let m = f(b, 8u32)
        let lm = f(b, 8u32)
        let o = f(b, 9u32)
    }
    let overlap_flag = f(b, 1u32)
    let clip_to_restricted_range = f(b, 1u32)
    ret ok
}

// the frame header of the specification. Returns Unsupported for the few syntax paths the decoder does not carry
// (short reference signalling).
fn uncompressed_header(b: *Bits, st: *State) -> err {
    let s = &st.seq
    let h = &st.h
    var id_len = 0i32
    if s.frame_id_numbers_present_flag { id_len = s.additional_frame_id_length_minus_1 + s.delta_frame_id_length_minus_2 + 3i32 }
    let all_frames = 255i32
    h.show_existing_frame = false
    h.use_ref_frame_mvs = false
    h.allow_high_precision_mv = false
    h.allow_intrabc = false
    if s.reduced_still_picture_header {
        h.frame_type = KEY_FRAME
        h.frame_is_intra = true
        h.show_frame = true
        h.showable_frame = false
        h.error_resilient_mode = true
    } else {
        h.show_existing_frame = flag(b)
        if h.show_existing_frame {
            h.frame_to_show_map_idx = fi(b, 3u32)
            if s.decoder_model_info_present_flag && !s.equal_picture_interval {
                let t = f(b, u32(s.frame_presentation_time_length_minus_1) + 1u32)
            }
            h.refresh_frame_flags = 0i32
            if s.frame_id_numbers_present_flag { let display_frame_id = f(b, u32(id_len)) }
            h.frame_type = st.refs[usize(h.frame_to_show_map_idx)].frame_type
            if h.frame_type == KEY_FRAME { h.refresh_frame_flags = all_frames }
            if b.over { ret Invalid }
            ret ok
        }
        h.frame_type = fi(b, 2u32)
        h.frame_is_intra = h.frame_type == INTRA_ONLY_FRAME || h.frame_type == KEY_FRAME
        h.show_frame = flag(b)
        if h.show_frame && s.decoder_model_info_present_flag && !s.equal_picture_interval {
            let t = f(b, u32(s.frame_presentation_time_length_minus_1) + 1u32)
        }
        if h.show_frame { h.showable_frame = h.frame_type != KEY_FRAME } else { h.showable_frame = flag(b) }
        if h.frame_type == SWITCH_FRAME || (h.frame_type == KEY_FRAME && h.show_frame) { h.error_resilient_mode = true } else { h.error_resilient_mode = flag(b) }
    }
    if h.frame_type == KEY_FRAME && h.show_frame {
        var i = 0usize
        while i < NUM_REF_FRAMES {
            st.refs[i].valid = false
            st.refs[i].order_hint = 0i32
            i += 1usize
        }
        i = 0usize
        while i < REFS_PER_FRAME {
            h.order_hints[LAST_FRAME + i] = 0i32
            i += 1usize
        }
    }
    h.disable_cdf_update = flag(b)
    if s.seq_force_screen_content_tools == SELECT_SCREEN_CONTENT_TOOLS { h.allow_screen_content_tools = flag(b) } else { h.allow_screen_content_tools = s.seq_force_screen_content_tools != 0i32 }
    if h.allow_screen_content_tools {
        if s.seq_force_integer_mv == SELECT_INTEGER_MV { h.force_integer_mv = flag(b) } else { h.force_integer_mv = s.seq_force_integer_mv != 0i32 }
    } else {
        h.force_integer_mv = false
    }
    if h.frame_is_intra { h.force_integer_mv = true }
    if s.frame_id_numbers_present_flag {
        h.current_frame_id = fi(b, u32(id_len))
    } else {
        h.current_frame_id = 0i32
    }
    if h.frame_type == SWITCH_FRAME {
        h.frame_size_override_flag = true
    } else if s.reduced_still_picture_header {
        h.frame_size_override_flag = false
    } else {
        h.frame_size_override_flag = flag(b)
    }
    h.order_hint = fi(b, u32(s.order_hint_bits))
    if h.frame_is_intra || h.error_resilient_mode { h.primary_ref_frame = PRIMARY_REF_NONE } else { h.primary_ref_frame = fi(b, 3u32) }
    if s.decoder_model_info_present_flag {
        if flag(b) {
            var op = 0i32
            while op <= s.operating_points_cnt_minus_1 {
                if s.decoder_model_present_for_this_op[usize(op)] {
                    let idc = s.operating_point_idc[usize(op)]
                    let in_temporal = (idc >> u32(st.temporal_id)) & 1i32
                    let in_spatial = (idc >> u32(st.spatial_id + 8i32)) & 1i32
                    if idc == 0i32 || (in_temporal == 1i32 && in_spatial == 1i32) {
                        let t = f(b, u32(s.buffer_removal_time_length_minus_1) + 1u32)
                    }
                }
                op += 1i32
            }
        }
    }
    if h.frame_type == SWITCH_FRAME || (h.frame_type == KEY_FRAME && h.show_frame) { h.refresh_frame_flags = all_frames } else { h.refresh_frame_flags = fi(b, 8u32) }
    if !h.frame_is_intra || h.refresh_frame_flags != all_frames {
        if h.error_resilient_mode && s.enable_order_hint {
            var i = 0usize
            while i < NUM_REF_FRAMES {
                h.ref_order_hint[i] = fi(b, u32(s.order_hint_bits))
                if h.ref_order_hint[i] != st.refs[i].order_hint { st.refs[i].valid = false }
                i += 1usize
            }
        }
    }
    if h.frame_is_intra {
        frame_size(b, s, h)
        render_size(b, h)
        if h.allow_screen_content_tools && h.upscaled_width == h.frame_width { h.allow_intrabc = flag(b) }
    } else {
        if !s.enable_order_hint {
            h.frame_refs_short_signaling = false
        } else {
            h.frame_refs_short_signaling = flag(b)
            if h.frame_refs_short_signaling { ret Unsupported }
        }
        var i = 0usize
        while i < REFS_PER_FRAME {
            h.ref_frame_idx[i] = fi(b, 3u32)
            if s.frame_id_numbers_present_flag { let delta = f(b, u32(s.delta_frame_id_length_minus_2) + 2u32) }
            i += 1usize
        }
        if h.frame_size_override_flag && !h.error_resilient_mode {
            frame_size_with_refs(b, st)
        } else {
            frame_size(b, s, h)
            render_size(b, h)
        }
        if h.force_integer_mv { h.allow_high_precision_mv = false } else { h.allow_high_precision_mv = flag(b) }
        if flag(b) { h.interpolation_filter = SWITCHABLE } else { h.interpolation_filter = fi(b, 2u32) }
        h.is_motion_mode_switchable = flag(b)
        if h.error_resilient_mode || !s.enable_ref_frame_mvs { h.use_ref_frame_mvs = false } else { h.use_ref_frame_mvs = flag(b) }
        i = 0usize
        while i < REFS_PER_FRAME {
            let ref_frame = LAST_FRAME + i
            let hint = st.refs[usize(h.ref_frame_idx[i])].order_hint
            h.order_hints[ref_frame] = hint
            if !s.enable_order_hint {
                h.ref_frame_sign_bias[ref_frame] = 0i32
            } else if get_relative_dist(s, hint, h.order_hint) > 0i32 {
                h.ref_frame_sign_bias[ref_frame] = 1i32
            } else {
                h.ref_frame_sign_bias[ref_frame] = 0i32
            }
            i += 1usize
        }
    }
    if s.reduced_still_picture_header || h.disable_cdf_update { h.disable_frame_end_update_cdf = true } else { h.disable_frame_end_update_cdf = flag(b) }
    if h.primary_ref_frame == PRIMARY_REF_NONE {
        setup_past_independence(h)
    } else {
        load_previous(st)
    }
    let tile_error = tile_info(b, s, h)
    if tile_error != ok { ret tile_error }
    quantization_params(b, s, h)
    segmentation_params(b, h)
    delta_q_params(b, h)
    delta_lf_params(b, h)
    h.coded_lossless = true
    var segment_id = 0usize
    while segment_id < MAX_SEGMENTS {
        let qindex = get_qindex_frame(h, segment_id)
        h.lossless_array[segment_id] = qindex == 0i32 && h.delta_q_y_dc == 0i32 && h.delta_q_u_ac == 0i32 && h.delta_q_u_dc == 0i32 && h.delta_q_v_ac == 0i32 && h.delta_q_v_dc == 0i32
        if !h.lossless_array[segment_id] { h.coded_lossless = false }
        if h.using_qmatrix {
            if h.lossless_array[segment_id] {
                h.seg_qm_level[segment_id] = 15i32
                h.seg_qm_level[8usize + segment_id] = 15i32
                h.seg_qm_level[16usize + segment_id] = 15i32
            } else {
                h.seg_qm_level[segment_id] = h.qm_y
                h.seg_qm_level[8usize + segment_id] = h.qm_u
                h.seg_qm_level[16usize + segment_id] = h.qm_v
            }
        }
        segment_id += 1usize
    }
    h.all_lossless = h.coded_lossless && h.frame_width == h.upscaled_width
    loop_filter_params(b, s, h)
    cdef_params(b, s, h)
    lr_params(b, s, h)
    read_tx_mode(b, h)
    if h.frame_is_intra { h.reference_select = false } else { h.reference_select = flag(b) }
    skip_mode_params(b, st)
    if h.frame_is_intra || h.error_resilient_mode || !s.enable_warped_motion { h.allow_warped_motion = false } else { h.allow_warped_motion = flag(b) }
    h.reduced_tx_set = flag(b)
    global_motion_params(b, h)
    let grain_error = film_grain_params(b, st)
    if grain_error != ok { ret grain_error }
    if b.over { ret Invalid }
    ret ok
}

type Obu = struct { kind: u32, payload: []const u8, temporal_id: i32, spatial_id: i32 }

// the OBU at `at` of `d` (every OBU of an MP4 sample carries its size); the offset after it
fn read_obu(d: []const u8, at: usize) -> (Obu, usize, err) {
    var o = Obu { kind: 0u32, payload: d[0usize..0usize], temporal_id: 0i32, spatial_id: 0i32 }
    if at >= d.len { ret (o, at, Invalid) }
    let hdr = u32(d[at])
    let has_ext = (hdr >> 2u32) & 1u32
    let has_size = (hdr >> 1u32) & 1u32
    o.kind = (hdr >> 3u32) & 15u32
    var p = at + 1usize
    if has_ext == 1u32 {
        if p >= d.len { ret (o, at, Invalid) }
        o.temporal_id = i32(d[p] >> 5u8)
        o.spatial_id = i32((d[p] >> 3u8) & 3u8)
        p += 1usize
    }
    if has_size == 0u32 {
        o.payload = d[p..d.len]
        ret (o, d.len, ok)
    }
    var size = 0u64
    var i = 0u32
    while i < 8u32 {
        if p >= d.len { ret (o, at, Invalid) }
        let byte = u64(d[p])
        p += 1usize
        size = size | ((byte & 127u64) << (u64(i) * 7u64))
        if (byte & 128u64) == 0u64 { break }
        i += 1u32
    }
    if size > u64(d.len - p) { ret (o, at, Invalid) }
    o.payload = d[p..p + usize(size)]
    ret (o, p + usize(size), ok)
}

fn save_refs(st: *State) {
    let h = &st.h
    var i = 0usize
    while i < NUM_REF_FRAMES {
        if ((h.refresh_frame_flags >> u32(i)) & 1i32) != 0i32 {
            let r = &st.refs[i]
            r.valid = true
            r.frame_id = h.current_frame_id
            r.upscaled_width = h.upscaled_width
            r.frame_width = h.frame_width
            r.frame_height = h.frame_height
            r.render_width = h.render_width
            r.render_height = h.render_height
            r.mi_cols = h.mi_cols
            r.mi_rows = h.mi_rows
            r.frame_type = h.frame_type
            r.order_hint = h.order_hint
            r.showable_frame = h.showable_frame
            var k = 0usize
            while k < 8usize {
                r.saved_order_hints[k] = h.order_hints[k]
                r.loop_filter_ref_deltas[k] = h.loop_filter_ref_deltas[k]
                k += 1usize
            }
            k = 0usize
            while k < 48usize {
                r.gm_params[k] = h.gm_params[k]
                k += 1usize
            }
            k = 0usize
            while k < 64usize {
                r.feature_enabled[k] = h.feature_enabled[k]
                r.feature_data[k] = h.feature_data[k]
                k += 1usize
            }
            r.loop_filter_mode_deltas[0usize] = h.loop_filter_mode_deltas[0usize]
            r.loop_filter_mode_deltas[1usize] = h.loop_filter_mode_deltas[1usize]
        }
        i += 1usize
    }
}
