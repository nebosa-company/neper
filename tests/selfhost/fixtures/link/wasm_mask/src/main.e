// `& | ^ ~` on masks of 2, 4, 8 and 16 bytes on wasm32-wasi (D5213's simd128 table). A `Vec` is
// 16, 32 or 64 bytes, so the 2-, 4- and 8-byte shapes the emitter loads with narrower moves are
// only ever the masks of two 64-bit, four 32-bit and eight 16-bit lanes (src/lower.e,
// `vector_packed_immediate`); the sixteen-byte one is a mask of byte lanes. The exit status says
// which check failed.
use e.simd
use e.os

fn main() -> i64 {
    let two_a = Mask[i64, 2]{ true, false }
    let two_b = Mask[i64, 2]{ true, true }
    if simd.bits[Vec[i64, 2]](two_a & two_b) != 1u64 { os.exit(1i32) }
    if simd.bits[Vec[i64, 2]](two_a | Mask[i64, 2]{ false, true }) != 3u64 { os.exit(2i32) }
    if simd.bits[Vec[i64, 2]](two_a ^ two_b) != 2u64 { os.exit(3i32) }
    if simd.bits[Vec[i64, 2]](~two_a) != 2u64 { os.exit(4i32) }

    let four_a = Mask[i32, 4]{ true, false, true, false }
    let four_b = Mask[i32, 4]{ true, true, false, false }
    if simd.bits[Vec[i32, 4]](four_a & four_b) != 1u64 { os.exit(5i32) }
    if simd.bits[Vec[i32, 4]](four_a | four_b) != 7u64 { os.exit(6i32) }
    if simd.bits[Vec[i32, 4]](four_a ^ four_b) != 6u64 { os.exit(7i32) }
    if simd.bits[Vec[i32, 4]](~four_a) != 10u64 { os.exit(8i32) }

    let eight_a = Mask[i16, 8]{ true, false, true, false, true, false, true, false }
    let eight_b = Mask[i16, 8]{ true, true, false, false, true, true, false, false }
    if simd.bits[Vec[i16, 8]](eight_a & eight_b) != 17u64 { os.exit(9i32) }
    if simd.bits[Vec[i16, 8]](eight_a | eight_b) != 119u64 { os.exit(10i32) }
    if simd.bits[Vec[i16, 8]](eight_a ^ eight_b) != 102u64 { os.exit(11i32) }
    if simd.bits[Vec[i16, 8]](~eight_a) != 170u64 { os.exit(12i32) }

    let sixteen_a = Mask[u8, 16]{ true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false }
    let sixteen_b = Mask[u8, 16]{ true, true, false, false, true, true, false, false, true, true, false, false, true, true, false, false }
    if simd.bits[Vec[u8, 16]](sixteen_a & sixteen_b) != 4369u64 { os.exit(13i32) }
    if simd.bits[Vec[u8, 16]](sixteen_a | sixteen_b) != 30583u64 { os.exit(14i32) }
    if simd.bits[Vec[u8, 16]](sixteen_a ^ sixteen_b) != 26214u64 { os.exit(15i32) }
    if simd.bits[Vec[u8, 16]](~sixteen_a) != 43690u64 { os.exit(16i32) }
    ret 0i64
}
