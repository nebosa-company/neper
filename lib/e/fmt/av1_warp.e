// AV1 warped motion: the warp samples process (spec 7.10.4), the setup shear and resolve divisor processes
// (7.11.3.6 / 7.11.3.7), the warp estimation process (7.11.3.8), the block warp process (7.11.3.5) and the
// useWarp decision of 7.11.3.1.
//
// find_warp_samples reads the same MI arrays as av1_mvp.find_mv_stack (`av1_mvp.Frame`, `av1_mvp.Block`, entry
// (r, c) at r * mi_cols + c, ref_frames / mvs with their list and component interleaving, UNWRITTEN = -2 in list 0
// of a position not decoded yet). Block.ref0 is RefFrame[0]; the candidate must have the same ref_frames[0] and
// no second reference. Planes are `[]u16` with a stride, as in av1_inter (`av1_inter.Ref` holds LUMA sizes).
//
//   find_warp_samples(f, b, avail_u, avail_l, mv_row, mv_col, cand_list) -> (NumSamples, err)
//        cand_list holds CandList[i][j] at i * 4 + j (j: 0 srcY, 1 srcX, 2 dstY, 3 dstX, 1/8 luma sample), at least
//        8 * 4 entries. mv_row / mv_col is Mv[0] of the block. NumSamples counts valid candidates (the special case
//        of one large vector gives 1, as in the spec).
//   warp_estimation(b, mv_row, mv_col, num_samples, cand_list, params) -> LocalValid
//        fills params[0..6] (LocalWarpParams) when the result is true; the caller still runs setup_shear on it and
//        uses its `valid` as the final LocalValid (spec 7.11.3.1 step 3).
//   setup_shear(params) -> Shear {valid, alpha, beta, gamma, delta}
//        a parameter set with params[2] <= 0 or |params[3]|, |params[4]| >= 2^20 is not valid (the spec yields an
//        invalid shear for all of them; the early answer only avoids 64 bit overflow and Log2(0)).
//   resolve_divisor(d) -> (divShift, divFactor), d != 0
//   use_warp(...) -> 0 none, 1 local, 2 global (step 7 of 7.11.3.1)
//   warp_block(rf, params, sub_x, sub_y, x, y, w, h, round0, round1, out) -> err
//        the block warp process for the whole w x h region at plane sample (x, y), all 8x8 sections; out is w*h,
//        row major, unclipped values exactly as av1_inter.block_pred produces them (round0 / round1 from
//        av1_inter.rounds). Invalid when the shear of params is not valid, the block is larger than 128 or empty,
//        the reference empty or out too short.

use e.fmt.av1_inter
use e.fmt.av1_mvp

error Invalid

const WARPEDMODEL_PREC_BITS: u32 = 16u32
const WARP_PARAM_REDUCE_BITS: u32 = 6u32
const DIV_LUT_BITS: u32 = 8u32
const DIV_LUT_PREC_BITS: u32 = 14u32
const LS_MV_MAX: i32 = 256i32
const WARPEDMODEL_TRANS_CLAMP: i64 = 8388608i64
const WARPEDMODEL_NONDIAGAFFINE_CLAMP: i64 = 8192i64
const LEAST_SQUARES_SAMPLES_MAX: i32 = 8i32
const PARAM_LIMIT: i32 = 1048576i32

type Shear = struct { valid: bool, alpha: i32, beta: i32, gamma: i32, delta: i32 }
type Scan = struct { num: i32, scanned: i32 }

// Warped_Filters[193][8], every tap plus 128
fn warped_filters() -> str { ret "\x80\x80\xff\x81\x80\x80\x80\x80\x80\x7f\xff\x82\x80\x80\x80\x80\x81\x7d\xff\x84\x7f\x80\x80\x80\x81\x7c\xfe\x86\x7e\x81\x80\x80\x81\x7b\xfe\x88\x7d\x81\x80\x80\x81\x7a\xfd\x8b\x7c\x81\x80\x80\x81\x79\xfc\x8d\x7c\x81\x80\x80\x82\x78\xfb\x8f\x7b\x81\x80\x80\x82\x77\xfa\x92\x7a\x81\x80\x80\x82\x76\xf9\x94\x7a\x81\x80\x80\x82\x75\xf8\x96\x79\x82\x80\x80\x82\x74\xf7\x99\x78\x82\x80\x80\x83\x73\xf5\x9b\x78\x82\x80\x80\x83\x73\xf4\x9d\x77\x82\x80\x80\x83\x72\xf2\xa0\x76\x83\x80\x80\x83\x71\xf1\xa3\x76\x82\x80\x80\x83\x71\xef\xa5\x75\x83\x80\x80\x83\x70\xed\xa8\x75\x83\x80\x80\x83\x70\xec\xaa\x74\x83\x80\x80\x84\x6f\xea\xad\x73\x83\x80\x80\x84\x6f\xe8\xaf\x73\x83\x80\x80\x84\x6f\xe6\xb2\x72\x83\x80\x80\x84\x6f\xe4\xb4\x72\x83\x80\x80\x84\x6e\xe2\xb7\x71\x84\x80\x80\x84\x6e\xe0\xba\x71\x83\x80\x80\x84\x6e\xde\xbc\x70\x84\x80\x80\x84\x6e\xdb\xbf\x70\x84\x80\x80\x84\x6e\xd9\xc1\x70\x84\x80\x80\x84\x6e\xd7\xc4\x6f\x84\x80\x80\x84\x6e\xd5\xc6\x6f\x84\x80\x80\x84\x6e\xd2\xc9\x6f\x84\x80\x80\x84\x6e\xd0\xcb\x6f\x84\x80\x80\x84\x6e\xce\xce\x6e\x84\x80\x80\x84\x6f\xcb\xd0\x6e\x84\x80\x80\x84\x6f\xc9\xd2\x6e\x84\x80\x80\x84\x6f\xc6\xd5\x6e\x84\x80\x80\x84\x6f\xc4\xd7\x6e\x84\x80\x80\x84\x70\xc1\xd9\x6e\x84\x80\x80\x84\x70\xbf\xdb\x6e\x84\x80\x80\x84\x70\xbc\xde\x6e\x84\x80\x80\x83\x71\xba\xe0\x6e\x84\x80\x80\x84\x71\xb7\xe2\x6e\x84\x80\x80\x83\x72\xb4\xe4\x6f\x84\x80\x80\x83\x72\xb2\xe6\x6f\x84\x80\x80\x83\x73\xaf\xe8\x6f\x84\x80\x80\x83\x73\xad\xea\x6f\x84\x80\x80\x83\x74\xaa\xec\x70\x83\x80\x80\x83\x75\xa8\xed\x70\x83\x80\x80\x83\x75\xa5\xef\x71\x83\x80\x80\x82\x76\xa3\xf1\x71\x83\x80\x80\x83\x76\xa0\xf2\x72\x83\x80\x80\x82\x77\x9d\xf4\x73\x83\x80\x80\x82\x78\x9b\xf5\x73\x83\x80\x80\x82\x78\x99\xf7\x74\x82\x80\x80\x82\x79\x96\xf8\x75\x82\x80\x80\x81\x7a\x94\xf9\x76\x82\x80\x80\x81\x7a\x92\xfa\x77\x82\x80\x80\x81\x7b\x8f\xfb\x78\x82\x80\x80\x81\x7c\x8d\xfc\x79\x81\x80\x80\x81\x7c\x8b\xfd\x7a\x81\x80\x80\x81\x7d\x88\xfe\x7b\x81\x80\x80\x81\x7e\x86\xfe\x7c\x81\x80\x80\x80\x7f\x84\xff\x7d\x81\x80\x80\x80\x80\x82\xff\x7f\x80\x80\x80\x80\x80\x80\xff\x81\x80\x80\x80\x80\x80\x7f\xff\x82\x80\x80\x80\x80\x81\x7d\xff\x84\x7e\x81\x80\x80\x81\x7b\xff\x86\x7e\x81\x80\x80\x82\x7a\xfe\x88\x7d\x81\x80\x7f\x82\x79\xfe\x8b\x7c\x82\x7f\x7f\x83\x78\xfd\x8d\x7b\x82\x7f\x7f\x83\x76\xfc\x90\x7a\x83\x7f\x7f\x84\x75\xfb\x92\x79\x83\x7f\x7f\x84\x74\xfa\x94\x79\x83\x7f\x7f\x84\x73\xf9\x97\x78\x83\x7f\x7e\x85\x72\xf8\x99\x77\x84\x7f\x7f\x85\x71\xf7\x9b\x76\x84\x7f\x7f\x85\x70\xf6\x9e\x75\x84\x7f\x7e\x86\x6f\xf4\xa1\x74\x85\x7f\x7e\x86\x6f\xf2\xa3\x74\x85\x7f\x7e\x86\x6e\xf1\xa6\x73\x85\x7f\x7e\x87\x6d\xef\xa9\x72\x86\x7e\x7e\x87\x6d\xee\xab\x71\x86\x7e\x7e\x87\x6c\xec\xae\x71\x86\x7e\x7e\x87\x6c\xea\xb1\x70\x86\x7e\x7e\x87\x6b\xe8\xb3\x70\x87\x7e\x7e\x87\x6b\xe6\xb6\x6f\x87\x7e\x7e\x88\x6b\xe4\xb8\x6e\x87\x7e\x7e\x88\x6a\xe2\xbb\x6e\x87\x7e\x7e\x88\x6a\xe0\xbe\x6d\x87\x7e\x7e\x88\x6a\xde\xc0\x6d\x87\x7e\x7e\x88\x6a\xdb\xc3\x6c\x88\x7e\x7e\x88\x6a\xd9\xc5\x6c\x88\x7e\x7e\x88\x6a\xd7\xc8\x6b\x88\x7e\x7e\x88\x6b\xd4\xca\x6b\x88\x7e\x7e\x88\x6a\xd2\xcd\x6b\x88\x7e\x7e\x88\x6b\xcf\xcf\x6b\x88\x7e\x7e\x88\x6b\xcd\xd2\x6a\x88\x7e\x7e\x88\x6b\xca\xd4\x6b\x88\x7e\x7e\x88\x6b\xc8\xd7\x6a\x88\x7e\x7e\x88\x6c\xc5\xd9\x6a\x88\x7e\x7e\x88\x6c\xc3\xdb\x6a\x88\x7e\x7e\x87\x6d\xc0\xde\x6a\x88\x7e\x7e\x87\x6d\xbe\xe0\x6a\x88\x7e\x7e\x87\x6e\xbb\xe2\x6a\x88\x7e\x7e\x87\x6e\xb8\xe4\x6b\x88\x7e\x7e\x87\x6f\xb6\xe6\x6b\x87\x7e\x7e\x87\x70\xb3\xe8\x6b\x87\x7e\x7e\x86\x70\xb1\xea\x6c\x87\x7e\x7e\x86\x71\xae\xec\x6c\x87\x7e\x7e\x86\x71\xab\xee\x6d\x87\x7e\x7e\x86\x72\xa9\xef\x6d\x87\x7e\x7f\x85\x73\xa6\xf1\x6e\x86\x7e\x7f\x85\x74\xa3\xf2\x6f\x86\x7e\x7f\x85\x74\xa1\xf4\x6f\x86\x7e\x7f\x84\x75\x9e\xf6\x70\x85\x7f\x7f\x84\x76\x9b\xf7\x71\x85\x7f\x7f\x84\x77\x99\xf8\x72\x85\x7e\x7f\x83\x78\x97\xf9\x73\x84\x7f\x7f\x83\x79\x94\xfa\x74\x84\x7f\x7f\x83\x79\x92\xfb\x75\x84\x7f\x7f\x83\x7a\x90\xfc\x76\x83\x7f\x7f\x82\x7b\x8d\xfd\x78\x83\x7f\x7f\x82\x7c\x8b\xfe\x79\x82\x7f\x80\x81\x7d\x88\xfe\x7a\x82\x80\x80\x81\x7e\x86\xff\x7b\x81\x80\x80\x81\x7e\x84\xff\x7d\x81\x80\x80\x80\x80\x82\xff\x7f\x80\x80\x80\x80\x80\x81\xff\x80\x80\x80\x80\x80\x80\x7f\xff\x82\x80\x80\x80\x80\x81\x7d\xff\x84\x7f\x80\x80\x80\x81\x7c\xfe\x86\x7e\x81\x80\x80\x81\x7b\xfe\x88\x7d\x81\x80\x80\x81\x7a\xfd\x8b\x7c\x81\x80\x80\x81\x79\xfc\x8d\x7c\x81\x80\x80\x82\x78\xfb\x8f\x7b\x81\x80\x80\x82\x77\xfa\x92\x7a\x81\x80\x80\x82\x76\xf9\x94\x7a\x81\x80\x80\x82\x75\xf8\x96\x79\x82\x80\x80\x82\x74\xf7\x99\x78\x82\x80\x80\x83\x73\xf5\x9b\x78\x82\x80\x80\x83\x73\xf4\x9d\x77\x82\x80\x80\x83\x72\xf2\xa0\x76\x83\x80\x80\x83\x71\xf1\xa3\x76\x82\x80\x80\x83\x71\xef\xa5\x75\x83\x80\x80\x83\x70\xed\xa8\x75\x83\x80\x80\x83\x70\xec\xaa\x74\x83\x80\x80\x84\x6f\xea\xad\x73\x83\x80\x80\x84\x6f\xe8\xaf\x73\x83\x80\x80\x84\x6f\xe6\xb2\x72\x83\x80\x80\x84\x6f\xe4\xb4\x72\x83\x80\x80\x84\x6e\xe2\xb7\x71\x84\x80\x80\x84\x6e\xe0\xba\x71\x83\x80\x80\x84\x6e\xde\xbc\x70\x84\x80\x80\x84\x6e\xdb\xbf\x70\x84\x80\x80\x84\x6e\xd9\xc1\x70\x84\x80\x80\x84\x6e\xd7\xc4\x6f\x84\x80\x80\x84\x6e\xd5\xc6\x6f\x84\x80\x80\x84\x6e\xd2\xc9\x6f\x84\x80\x80\x84\x6e\xd0\xcb\x6f\x84\x80\x80\x84\x6e\xce\xce\x6e\x84\x80\x80\x84\x6f\xcb\xd0\x6e\x84\x80\x80\x84\x6f\xc9\xd2\x6e\x84\x80\x80\x84\x6f\xc6\xd5\x6e\x84\x80\x80\x84\x6f\xc4\xd7\x6e\x84\x80\x80\x84\x70\xc1\xd9\x6e\x84\x80\x80\x84\x70\xbf\xdb\x6e\x84\x80\x80\x84\x70\xbc\xde\x6e\x84\x80\x80\x83\x71\xba\xe0\x6e\x84\x80\x80\x84\x71\xb7\xe2\x6e\x84\x80\x80\x83\x72\xb4\xe4\x6f\x84\x80\x80\x83\x72\xb2\xe6\x6f\x84\x80\x80\x83\x73\xaf\xe8\x6f\x84\x80\x80\x83\x73\xad\xea\x6f\x84\x80\x80\x83\x74\xaa\xec\x70\x83\x80\x80\x83\x75\xa8\xed\x70\x83\x80\x80\x83\x75\xa5\xef\x71\x83\x80\x80\x82\x76\xa3\xf1\x71\x83\x80\x80\x83\x76\xa0\xf2\x72\x83\x80\x80\x82\x77\x9d\xf4\x73\x83\x80\x80\x82\x78\x9b\xf5\x73\x83\x80\x80\x82\x78\x99\xf7\x74\x82\x80\x80\x82\x79\x96\xf8\x75\x82\x80\x80\x81\x7a\x94\xf9\x76\x82\x80\x80\x81\x7a\x92\xfa\x77\x82\x80\x80\x81\x7b\x8f\xfb\x78\x82\x80\x80\x81\x7c\x8d\xfc\x79\x81\x80\x80\x81\x7c\x8b\xfd\x7a\x81\x80\x80\x81\x7d\x88\xfe\x7b\x81\x80\x80\x81\x7e\x86\xfe\x7c\x81\x80\x80\x80\x7f\x84\xff\x7d\x81\x80\x80\x80\x80\x82\xff\x7f\x80\x80\x80\x80\x80\x82\xff\x7f\x80" }

// Div_Lut[257], big endian 16 bit
fn div_lut() -> str { ret "\x40\x00\x3f\xc0\x3f\x81\x3f\x42\x3f\x04\x3e\xc6\x3e\x89\x3e\x4c\x3e\x10\x3d\xd4\x3d\x98\x3d\x5d\x3d\x22\x3c\xe8\x3c\xae\x3c\x75\x3c\x3c\x3c\x04\x3b\xcc\x3b\x94\x3b\x5d\x3b\x26\x3a\xef\x3a\xb9\x3a\x84\x3a\x4e\x3a\x19\x39\xe5\x39\xb1\x39\x7d\x39\x49\x39\x16\x38\xe4\x38\xb1\x38\x7f\x38\x4d\x38\x1c\x37\xeb\x37\xba\x37\x8a\x37\x5a\x37\x2a\x36\xfb\x36\xcc\x36\x9d\x36\x6f\x36\x40\x36\x13\x35\xe5\x35\xb8\x35\x8b\x35\x5e\x35\x32\x35\x06\x34\xda\x34\xaf\x34\x83\x34\x58\x34\x2e\x34\x03\x33\xd9\x33\xaf\x33\x86\x33\x5c\x33\x33\x33\x0a\x32\xe2\x32\xb9\x32\x91\x32\x6a\x32\x42\x32\x1b\x31\xf4\x31\xcd\x31\xa6\x31\x80\x31\x59\x31\x34\x31\x0e\x30\xe8\x30\xc3\x30\x9e\x30\x79\x30\x55\x30\x30\x30\x0c\x2f\xe8\x2f\xc4\x2f\xa1\x2f\x7d\x2f\x5a\x2f\x37\x2f\x15\x2e\xf2\x2e\xd0\x2e\xae\x2e\x8c\x2e\x6a\x2e\x48\x2e\x27\x2e\x06\x2d\xe5\x2d\xc4\x2d\xa3\x2d\x83\x2d\x63\x2d\x42\x2d\x23\x2d\x03\x2c\xe3\x2c\xc4\x2c\xa5\x2c\x86\x2c\x67\x2c\x48\x2c\x29\x2c\x0b\x2b\xed\x2b\xcf\x2b\xb1\x2b\x93\x2b\x75\x2b\x58\x2b\x3b\x2b\x1e\x2b\x01\x2a\xe4\x2a\xc7\x2a\xab\x2a\x8e\x2a\x72\x2a\x56\x2a\x3a\x2a\x1e\x2a\x03\x29\xe7\x29\xcc\x29\xb1\x29\x95\x29\x7a\x29\x60\x29\x45\x29\x2a\x29\x10\x28\xf6\x28\xdc\x28\xc2\x28\xa8\x28\x8e\x28\x74\x28\x5b\x28\x41\x28\x28\x28\x0f\x27\xf6\x27\xdd\x27\xc4\x27\xac\x27\x93\x27\x7b\x27\x62\x27\x4a\x27\x32\x27\x1a\x27\x02\x26\xeb\x26\xd3\x26\xbc\x26\xa4\x26\x8d\x26\x76\x26\x5f\x26\x48\x26\x31\x26\x1a\x26\x04\x25\xed\x25\xd7\x25\xc0\x25\xaa\x25\x94\x25\x7e\x25\x68\x25\x52\x25\x3d\x25\x27\x25\x11\x24\xfc\x24\xe7\x24\xd1\x24\xbc\x24\xa7\x24\x92\x24\x7d\x24\x69\x24\x54\x24\x3f\x24\x2b\x24\x17\x24\x02\x23\xee\x23\xda\x23\xc6\x23\xb2\x23\x9e\x23\x8a\x23\x77\x23\x63\x23\x4f\x23\x3c\x23\x29\x23\x15\x23\x02\x22\xef\x22\xdc\x22\xc9\x22\xb6\x22\xa3\x22\x91\x22\x7e\x22\x6c\x22\x59\x22\x47\x22\x34\x22\x22\x22\x10\x21\xfe\x21\xec\x21\xda\x21\xc8\x21\xb6\x21\xa5\x21\x93\x21\x81\x21\x70\x21\x5e\x21\x4d\x21\x3c\x21\x2a\x21\x19\x21\x08\x20\xf7\x20\xe6\x20\xd5\x20\xc5\x20\xb4\x20\xa3\x20\x93\x20\x82\x20\x72\x20\x61\x20\x51\x20\x41\x20\x30\x20\x20\x20\x10\x20\x00" }

fn iabs(a: i32) -> i32 {
    if a < 0i32 { ret 0i32 - a }
    ret a
}

fn imin(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}

fn imax(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}

fn clip3(lo: i32, hi: i32, v: i32) -> i32 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

fn clip3_64(lo: i64, hi: i64, v: i64) -> i64 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

fn round2(x: i32, n: u32) -> i32 {
    if n == 0u32 { ret x }
    ret (x + (1i32 << (n - 1u32))) >> n
}

fn round2_64(x: i64, n: u32) -> i64 {
    if n == 0u32 { ret x }
    ret (x + (1i64 << (n - 1u32))) >> n
}

fn round2_signed_64(x: i64, n: u32) -> i64 {
    if x >= 0i64 { ret round2_64(x, n) }
    ret 0i64 - round2_64(0i64 - x, n)
}

fn add_sample(f: *av1_mvp.Frame, b: av1_mvp.Block, d_row: i32, d_col: i32, mv_row: i32, mv_col: i32, sc: *Scan, cand_list: []i32) {
    if sc.scanned >= LEAST_SQUARES_SAMPLES_MAX { ret }
    let r = b.mi_row + d_row
    let c = b.mi_col + d_col
    if c < f.tile_col_start || c >= f.tile_col_end || r < f.tile_row_start || r >= f.tile_row_end { ret }
    let at = usize(r * f.mi_cols + c)
    if i32(f.ref_frames[at * 2usize]) != b.ref0 { ret }
    if f.ref_frames[at * 2usize + 1usize] != -1i8 { ret }
    let cand_sz = i32(f.mi_sizes[at])
    let cand_w4 = av1_mvp.num4_wide(cand_sz)
    let cand_h4 = av1_mvp.num4_high(cand_sz)
    let cand_row = r - (r & (cand_h4 - 1i32))
    let cand_col = c - (c & (cand_w4 - 1i32))
    let mid_y = cand_row * 4i32 + cand_h4 * 2i32 - 1i32
    let mid_x = cand_col * 4i32 + cand_w4 * 2i32 - 1i32
    let size_max = imax(av1_mvp.num4_wide(b.mi_size), av1_mvp.num4_high(b.mi_size)) * 4i32
    let threshold = clip3(16i32, 112i32, size_max)
    let cm = usize(cand_row * f.mi_cols + cand_col) * 4usize
    let cand_mv_row = i32(f.mvs[cm])
    let cand_mv_col = i32(f.mvs[cm + 1usize])
    let valid = iabs(cand_mv_row - mv_row) + iabs(cand_mv_col - mv_col) <= threshold
    sc.scanned += 1i32
    if !valid && sc.scanned > 1i32 { ret }
    let o = usize(sc.num) * 4usize
    cand_list[o] = mid_y * 8i32
    cand_list[o + 1usize] = mid_x * 8i32
    cand_list[o + 2usize] = mid_y * 8i32 + cand_mv_row
    cand_list[o + 3usize] = mid_x * 8i32 + cand_mv_col
    if valid { sc.num += 1i32 }
}

fn find_warp_samples(f: *av1_mvp.Frame, b: av1_mvp.Block, avail_u: bool, avail_l: bool, mv_row: i32, mv_col: i32, cand_list: []i32) -> (i32, err) {
    if cand_list.len < 32usize { ret (0i32, Invalid) }
    var sc = Scan { num: 0i32, scanned: 0i32 }
    let w4 = av1_mvp.num4_wide(b.mi_size)
    let h4 = av1_mvp.num4_high(b.mi_size)
    var do_top_left = true
    var do_top_right = true
    if avail_u {
        let src_w = av1_mvp.num4_wide(i32(f.mi_sizes[usize((b.mi_row - 1i32) * f.mi_cols + b.mi_col)]))
        if w4 <= src_w {
            let col_offset = 0i32 - (b.mi_col & (src_w - 1i32))
            if col_offset < 0i32 { do_top_left = false }
            if col_offset + src_w > w4 { do_top_right = false }
            add_sample(f, b, -1i32, 0i32, mv_row, mv_col, &sc, cand_list)
        } else {
            var i = 0i32
            let end = imin(w4, f.mi_cols - b.mi_col)
            while i < end {
                let sw = av1_mvp.num4_wide(i32(f.mi_sizes[usize((b.mi_row - 1i32) * f.mi_cols + b.mi_col + i)]))
                add_sample(f, b, -1i32, i, mv_row, mv_col, &sc, cand_list)
                i += imin(w4, sw)
            }
        }
    }
    if avail_l {
        let src_h = av1_mvp.num4_high(i32(f.mi_sizes[usize(b.mi_row * f.mi_cols + b.mi_col - 1i32)]))
        if h4 <= src_h {
            let row_offset = 0i32 - (b.mi_row & (src_h - 1i32))
            if row_offset < 0i32 { do_top_left = false }
            add_sample(f, b, 0i32, -1i32, mv_row, mv_col, &sc, cand_list)
        } else {
            var i = 0i32
            let end = imin(h4, f.mi_rows - b.mi_row)
            while i < end {
                let sh = av1_mvp.num4_high(i32(f.mi_sizes[usize((b.mi_row + i) * f.mi_cols + b.mi_col - 1i32)]))
                add_sample(f, b, i, -1i32, mv_row, mv_col, &sc, cand_list)
                i += imin(h4, sh)
            }
        }
    }
    if do_top_left { add_sample(f, b, -1i32, -1i32, mv_row, mv_col, &sc, cand_list) }
    if do_top_right {
        if imax(w4, h4) <= 16i32 { add_sample(f, b, -1i32, w4, mv_row, mv_col, &sc, cand_list) }
    }
    if sc.num == 0i32 && sc.scanned > 0i32 { sc.num = 1i32 }
    ret (sc.num, ok)
}

fn floor_log2_64(x: i64) -> u32 {
    var n = 0u32
    var v = x
    while v > 1i64 {
        v = v >> 1u32
        n += 1u32
    }
    ret n
}

fn resolve_divisor(d: i64) -> (i32, i64) {
    var a = d
    if d < 0i64 { a = 0i64 - d }
    let n = floor_log2_64(a)
    let e = a - (1i64 << n)
    var fi = 0i64
    if n > DIV_LUT_BITS {
        fi = round2_64(e, n - DIV_LUT_BITS)
    } else {
        fi = e << (DIV_LUT_BITS - n)
    }
    let t = div_lut()
    let k = usize(fi) * 2usize
    let factor = (i64(t[k]) << 8u32) | i64(t[k + 1usize])
    var signed = factor
    if d < 0i64 { signed = 0i64 - factor }
    ret (i32(n + DIV_LUT_PREC_BITS), signed)
}

fn reduce(v: i64) -> i32 {
    ret i32(round2_signed_64(v, WARP_PARAM_REDUCE_BITS)) * 64i32
}

fn setup_shear(params: []const i32) -> Shear {
    let bad = Shear { valid: false, alpha: 0i32, beta: 0i32, gamma: 0i32, delta: 0i32 }
    if params.len < 6usize { ret bad }
    let p2 = params[2usize]
    let p3 = params[3usize]
    let p4 = params[4usize]
    let p5 = params[5usize]
    if p2 <= 0i32 || iabs(p3) >= PARAM_LIMIT || iabs(p4) >= PARAM_LIMIT { ret bad }
    let alpha0 = clip3_64(-32768i64, 32767i64, i64(p2) - 65536i64)
    let beta0 = clip3_64(-32768i64, 32767i64, i64(p3))
    let (shift, factor) = resolve_divisor(i64(p2))
    let v = i64(p4) << WARPEDMODEL_PREC_BITS
    let gamma0 = clip3_64(-32768i64, 32767i64, round2_signed_64(v * factor, u32(shift)))
    let w = i64(p3) * i64(p4)
    let delta0 = clip3_64(-32768i64, 32767i64, i64(p5) - round2_signed_64(w * factor, u32(shift)) - 65536i64)
    let alpha = reduce(alpha0)
    let beta = reduce(beta0)
    let gamma = reduce(gamma0)
    let delta = reduce(delta0)
    var valid = true
    if 4i32 * iabs(alpha) + 7i32 * iabs(beta) >= 65536i32 { valid = false }
    if 4i32 * iabs(gamma) + 4i32 * iabs(delta) >= 65536i32 { valid = false }
    ret Shear { valid: valid, alpha: alpha, beta: beta, gamma: gamma, delta: delta }
}

fn use_warp(w: i32, h: i32, force_integer_mv: bool, local_warp: bool, local_valid: bool, global_mode: bool, gm_type: i32, scaled: bool, global_valid: bool) -> i32 {
    if w < 8i32 || h < 8i32 { ret 0i32 }
    if force_integer_mv { ret 0i32 }
    if local_warp && local_valid { ret 1i32 }
    if global_mode && gm_type > 1i32 && !scaled && global_valid { ret 2i32 }
    ret 0i32
}

fn ls_product(a: i64, b: i64) -> i64 {
    ret ((a * b) >> 2u32) + (a + b)
}

fn warp_div(v: i64, factor: i64, shift: u32) -> i64 {
    ret round2_signed_64(v * factor, shift)
}

fn nondiag(v: i64, factor: i64, shift: u32) -> i64 {
    ret clip3_64(1i64 - WARPEDMODEL_NONDIAGAFFINE_CLAMP, WARPEDMODEL_NONDIAGAFFINE_CLAMP - 1i64, warp_div(v, factor, shift))
}

fn diag(v: i64, factor: i64, shift: u32) -> i64 {
    ret clip3_64(65536i64 - WARPEDMODEL_NONDIAGAFFINE_CLAMP + 1i64, 65536i64 + WARPEDMODEL_NONDIAGAFFINE_CLAMP - 1i64, warp_div(v, factor, shift))
}

fn warp_estimation(b: av1_mvp.Block, mv_row: i32, mv_col: i32, num_samples: i32, cand_list: []const i32, params: []i32) -> bool {
    if params.len < 6usize || usize(num_samples) * 4usize > cand_list.len { ret false }
    var a00 = 0i64
    var a01 = 0i64
    var a11 = 0i64
    var bx0 = 0i64
    var bx1 = 0i64
    var by0 = 0i64
    var by1 = 0i64
    let w4 = av1_mvp.num4_wide(b.mi_size)
    let h4 = av1_mvp.num4_high(b.mi_size)
    let mid_y = b.mi_row * 4i32 + h4 * 2i32 - 1i32
    let mid_x = b.mi_col * 4i32 + w4 * 2i32 - 1i32
    let suy = mid_y * 8i32
    let sux = mid_x * 8i32
    let duy = suy + mv_row
    let dux = sux + mv_col
    var i = 0usize
    while i < usize(num_samples) {
        let sy = cand_list[i * 4usize] - suy
        let sx = cand_list[i * 4usize + 1usize] - sux
        let dy = cand_list[i * 4usize + 2usize] - duy
        let dx = cand_list[i * 4usize + 3usize] - dux
        if iabs(sx - dx) < LS_MV_MAX && iabs(sy - dy) < LS_MV_MAX {
            let lsx = i64(sx)
            let lsy = i64(sy)
            let ldx = i64(dx)
            let ldy = i64(dy)
            a00 += ls_product(lsx, lsx) + 8i64
            a01 += ls_product(lsx, lsy) + 4i64
            a11 += ls_product(lsy, lsy) + 8i64
            bx0 += ls_product(lsx, ldx) + 8i64
            bx1 += ls_product(lsy, ldx) + 4i64
            by0 += ls_product(lsx, ldy) + 4i64
            by1 += ls_product(lsy, ldy) + 8i64
        }
        i += 1usize
    }
    let det = a00 * a11 - a01 * a01
    if det == 0i64 { ret false }
    let (ds0, df0) = resolve_divisor(det)
    var div_shift = ds0
    var div_factor = df0
    div_shift -= 16i32
    if div_shift < 0i32 {
        div_factor = div_factor << u32(0i32 - div_shift)
        div_shift = 0i32
    }
    let sh = u32(div_shift)
    let p2 = diag(a11 * bx0 - a01 * bx1, div_factor, sh)
    let p3 = nondiag(0i64 - a01 * bx0 + a00 * bx1, div_factor, sh)
    let p4 = nondiag(a11 * by0 - a01 * by1, div_factor, sh)
    let p5 = diag(0i64 - a01 * by0 + a00 * by1, div_factor, sh)
    let vx = i64(mv_col) * 8192i64 - (i64(mid_x) * (p2 - 65536i64) + i64(mid_y) * p3)
    let vy = i64(mv_row) * 8192i64 - (i64(mid_x) * p4 + i64(mid_y) * (p5 - 65536i64))
    params[0usize] = i32(clip3_64(0i64 - WARPEDMODEL_TRANS_CLAMP, WARPEDMODEL_TRANS_CLAMP - 1i64, vx))
    params[1usize] = i32(clip3_64(0i64 - WARPEDMODEL_TRANS_CLAMP, WARPEDMODEL_TRANS_CLAMP - 1i64, vy))
    params[2usize] = i32(p2)
    params[3usize] = i32(p3)
    params[4usize] = i32(p4)
    params[5usize] = i32(p5)
    ret true
}

fn warp_8(rf: av1_inter.Ref, params: []const i32, sh: Shear, sub_x: u32, sub_y: u32, x: i32, y: i32, w: i32, h: i32, bi: i32, bj: i32, round0: u32, round1: u32, out: []i32) {
    let last_x = ((rf.width + i32(sub_x)) >> sub_x) - 1i32
    let last_y = ((rf.height + i32(sub_y)) >> sub_y) - 1i32
    let src_x = i64((x + bj * 8i32 + 4i32) << sub_x)
    let src_y = i64((y + bi * 8i32 + 4i32) << sub_y)
    let dst_x = i64(params[2usize]) * src_x + i64(params[3usize]) * src_y + i64(params[0usize])
    let dst_y = i64(params[4usize]) * src_x + i64(params[5usize]) * src_y + i64(params[1usize])
    let x4 = dst_x >> sub_x
    let y4 = dst_y >> sub_y
    let ix4 = i32(x4 >> WARPEDMODEL_PREC_BITS)
    let sx4 = i32(x4 & 65535i64)
    let iy4 = i32(y4 >> WARPEDMODEL_PREC_BITS)
    let sy4 = i32(y4 & 65535i64)
    let t = warped_filters()
    var inter: [120]i32 = zero
    var i1 = -7i32
    while i1 < 8i32 {
        let row = usize(clip3(0i32, last_y, iy4 + i1)) * rf.stride
        var i2 = -4i32
        while i2 < 4i32 {
            let sx = sx4 + sh.alpha * i2 + sh.beta * i1
            let offs = usize(round2(sx, 10u32) + 64i32) * 8usize
            var s = 0i32
            var i3 = 0i32
            while i3 < 8i32 {
                let px = clip3(0i32, last_x, ix4 + i2 - 3i32 + i3)
                s += (i32(t[offs + usize(i3)]) - 128i32) * i32(rf.data[row + usize(px)])
                i3 += 1i32
            }
            inter[usize((i1 + 7i32) * 8i32 + i2 + 4i32)] = round2(s, round0)
            i2 += 1i32
        }
        i1 += 1i32
    }
    let lim1 = imin(4i32, h - bi * 8i32 - 4i32)
    let lim2 = imin(4i32, w - bj * 8i32 - 4i32)
    i1 = -4i32
    while i1 < lim1 {
        var i2 = -4i32
        while i2 < lim2 {
            let sy = sy4 + sh.gamma * i2 + sh.delta * i1
            let offs = usize(round2(sy, 10u32) + 64i32) * 8usize
            var s = 0i32
            var i3 = 0i32
            while i3 < 8i32 {
                s += (i32(t[offs + usize(i3)]) - 128i32) * inter[usize((i1 + i3 + 4i32) * 8i32 + i2 + 4i32)]
                i3 += 1i32
            }
            out[usize(bi * 8i32 + i1 + 4i32) * usize(w) + usize(bj * 8i32 + i2 + 4i32)] = round2(s, round1)
            i2 += 1i32
        }
        i1 += 1i32
    }
}

fn warp_block(rf: av1_inter.Ref, params: []const i32, sub_x: u32, sub_y: u32, x: i32, y: i32, w: i32, h: i32, round0: u32, round1: u32, out: []i32) -> err {
    if w < 1i32 || h < 1i32 || w > 128i32 || h > 128i32 { ret Invalid }
    if rf.width < 1i32 || rf.height < 1i32 || usize(w) * usize(h) > out.len { ret Invalid }
    let sh = setup_shear(params)
    if !sh.valid { ret Invalid }
    var bi = 0i32
    while bi <= ((h - 1i32) >> 3u32) {
        var bj = 0i32
        while bj <= ((w - 1i32) >> 3u32) {
            warp_8(rf, params, sh, sub_x, sub_y, x, y, w, h, bi, bj, round0, round1, out)
            bj += 1i32
        }
        bi += 1i32
    }
    ret ok
}
