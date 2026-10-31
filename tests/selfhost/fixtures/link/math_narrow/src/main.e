// Narrow IEEE floats exercise e.math's bit helpers directly and through the SIMD
// reductions.  The sign can only be observed through the representation: -0 and
// +0 compare equal as values.

use e.math
use e.mem
use e.os
use e.simd

fn bits_h(x: f16) -> u16 { ret mem.bitcast[u16](x) }
fn bits_b(x: bf16) -> u16 { ret mem.bitcast[u16](x) }

fn main(a: *mem.Arena) -> err {
    let h_minus_zero = mem.bitcast[f16](32768u16)
    let b_minus_zero = mem.bitcast[bf16](32768u16)

    if bits_h(math.abs[f16](h_minus_zero)) != 0u16 { os.exit(10i32) }
    if bits_b(math.abs[bf16](b_minus_zero)) != 0u16 { os.exit(11i32) }
    if !math.is_negative[f16](h_minus_zero) || !math.is_negative[bf16](b_minus_zero) { os.exit(12i32) }
    if bits_h(math.copysign[f16](f16(3.0f64), h_minus_zero)) != bits_h(f16(-3.0f64)) { os.exit(13i32) }
    if bits_b(math.copysign[bf16](bf16(3.0f64), b_minus_zero)) != bits_b(bf16(-3.0f64)) { os.exit(14i32) }

    if bits_h(math.min[f16](f16(0.0f64), h_minus_zero)) != bits_h(h_minus_zero) { os.exit(15i32) }
    if bits_h(math.max[f16](h_minus_zero, f16(0.0f64))) != 0u16 { os.exit(16i32) }
    if bits_b(math.min[bf16](bf16(0.0f64), b_minus_zero)) != bits_b(b_minus_zero) { os.exit(17i32) }
    if bits_b(math.max[bf16](b_minus_zero, bf16(0.0f64))) != 0u16 { os.exit(18i32) }

    let h_lanes = Vec[f16, 8]{ f16(3.0f64), f16(-2.0f64), f16(7.0f64), f16(-4.0f64), f16(1.0f64), f16(5.0f64), f16(0.0f64), f16(6.0f64) }
    let b_lanes = Vec[bf16, 8]{ bf16(3.0f64), bf16(-2.0f64), bf16(7.0f64), bf16(-4.0f64), bf16(1.0f64), bf16(5.0f64), bf16(0.0f64), bf16(6.0f64) }
    if simd.reduce_min[Vec[f16, 8]](h_lanes) != f16(-4.0f64) { os.exit(19i32) }
    if simd.reduce_max[Vec[f16, 8]](h_lanes) != f16(7.0f64) { os.exit(20i32) }
    if simd.reduce_min[Vec[bf16, 8]](b_lanes) != bf16(-4.0f64) { os.exit(21i32) }
    if simd.reduce_max[Vec[bf16, 8]](b_lanes) != bf16(7.0f64) { os.exit(22i32) }

    ret ok
}
