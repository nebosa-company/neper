// `dis` shows the packed instructions of `e.simd`'s codec operations (D5960) under
// `--cpu x64-v2`: one packed instruction per call where the lane loop used to be.
use e.os
use e.simd

fn codec(row: []u8, out: []u8, a: Vec[i16, 8], b: Vec[i16, 8]) -> u64 {
    let x = simd.load[Vec[u8, 16]](row, 0usize)
    let y = simd.splat[Vec[u8, 16]](7u8)
    let sat = simd.adds[Vec[u8, 16]](x, y)
    let mix = simd.avg_u8[Vec[u8, 16]](sat, simd.min[Vec[u8, 16]](x, y))
    let wide = simd.madd_i16[Vec[i16, 8]](simd.mulhrs_i16[Vec[i16, 8]](a, b), simd.unpack_lo[Vec[i16, 8]](a, b))
    let narrow = simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](a, b)
    let picked = simd.select[Vec[u8, 16]](simd.cmp_gt[Vec[u8, 16]](mix, narrow), mix, simd.shuffle_bytes[Vec[u8, 16]](x, y))
    simd.store[Vec[u8, 16]](out, 0usize, simd.abs_diff[Vec[u8, 16]](picked, x))
    let sums = simd.sad_u8[Vec[u8, 16]](picked, x)
    ret simd.movemask[Vec[u8, 16]](picked) ^ u64.trunc(wide.lanes[0]) ^ sums.lanes[0]
}

fn main() {
    var row: [16]u8 = zero
    var out: [16]u8 = zero
    let a = simd.splat[Vec[i16, 8]](3i16)
    os.exit(i32.trunc(codec(row[0..], out[0..], a, a)))
}
