// `e.math`'s exact set, which section 11 says is one value on every target: `sqrt` as the
// instruction, and `abs`, `min`, `max`, `floor`, `ceil`, `round`, `trunc` and `copysign` as
// source. Exact means bit-for-bit, so the answers are compared through their bits where a
// sign could hide -- `-0` and `+0` compare equal as values and are not the same answer.

use e.mem
use e.os
use e.math

fn bits64(x: f64) -> u64 { ret mem.bitcast[u64](x) }
fn bits32(x: f32) -> u32 { ret mem.bitcast[u32](x) }
fn negative_zero() -> f64 { ret mem.bitcast[f64](9223372036854775808u64) }
fn quiet_nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn infinity() -> f64 { ret 1.0f64 / 0.0f64 }

fn main(a: *mem.Arena) -> err {
    // --- sqrt is the instruction: correctly rounded, on both widths, with the special values
    // section 11 fixes. `sqrt(2)` is checked by its bits, which is what correctly rounded means.
    if math.sqrt[f64](4.0f64) != 2.0f64 { os.exit(10i32) }
    if bits64(math.sqrt[f64](2.0f64)) != 4609047870845172685u64 { os.exit(11i32) }
    if math.sqrt[f32](9.0f32) != 3.0f32 { os.exit(12i32) }
    if bits32(math.sqrt[f32](2.0f32)) != 1068827891u32 { os.exit(13i32) }
    let root_of_less = math.sqrt[f64](-1.0f64)
    if root_of_less == root_of_less { os.exit(14i32) }
    if bits64(math.sqrt[f64](negative_zero())) != bits64(negative_zero()) { os.exit(15i32) }
    if math.sqrt[f64](infinity()) != infinity() { os.exit(16i32) }
    if math.sqrt[f64](0.0f64) != 0.0f64 { os.exit(17i32) }
    // Through a generic, where the width is a type parameter until the instance.
    if root_of[f64](16.0f64) != 4.0f64 { os.exit(18i32) }
    if root_of[f32](16.0f32) != 4.0f32 { os.exit(19i32) }

    // --- rsqrt: 1 / sqrt, within a ULP.
    if math.rsqrt[f64](4.0f64) != 0.5f64 { os.exit(20i32) }
    if math.rsqrt[f32](0.25f32) != 2.0f32 { os.exit(21i32) }

    // --- abs clears the sign and nothing else; copysign moves it, NaN included.
    if math.abs[f64](-3.5f64) != 3.5f64 { os.exit(30i32) }
    if math.abs[f32](-3.5f32) != 3.5f32 { os.exit(31i32) }
    if bits64(math.abs[f64](negative_zero())) != bits64(0.0f64) { os.exit(32i32) }
    if math.copysign[f64](3.0f64, -1.0f64) != -3.0f64 { os.exit(33i32) }
    if math.copysign[f64](-3.0f64, 1.0f64) != 3.0f64 { os.exit(34i32) }
    if bits64(math.copysign[f64](0.0f64, -1.0f64)) != bits64(negative_zero()) { os.exit(35i32) }
    if math.copysign[f32](2.0f32, -0.0f32) != -2.0f32 { os.exit(36i32) }
    let signed_nan = math.copysign[f64](quiet_nan(), -1.0f64)
    if (bits64(signed_nan) >> 63u32) != 1u64 { os.exit(37i32) }

    // --- min and max are IEEE 754-2019 minimum and maximum: a NaN wins, and the zeros are
    // ordered with `-0` below `+0`.
    if math.min[f64](1.0f64, 2.0f64) != 1.0f64 { os.exit(40i32) }
    if math.max[f64](1.0f64, 2.0f64) != 2.0f64 { os.exit(41i32) }
    if math.min[f32](-1.0f32, -2.0f32) != -2.0f32 { os.exit(42i32) }
    let min_with_nan = math.min[f64](1.0f64, quiet_nan())
    if min_with_nan == min_with_nan { os.exit(43i32) }
    let max_with_nan = math.max[f64](quiet_nan(), 1.0f64)
    if max_with_nan == max_with_nan { os.exit(44i32) }
    if bits64(math.min[f64](0.0f64, negative_zero())) != bits64(negative_zero()) { os.exit(45i32) }
    if bits64(math.min[f64](negative_zero(), 0.0f64)) != bits64(negative_zero()) { os.exit(46i32) }
    if bits64(math.max[f64](0.0f64, negative_zero())) != bits64(0.0f64) { os.exit(47i32) }
    if bits64(math.max[f64](negative_zero(), 0.0f64)) != bits64(0.0f64) { os.exit(48i32) }

    // --- The four rounders, on the values where they differ from each other.
    if math.trunc[f64](2.7f64) != 2.0f64 { os.exit(50i32) }
    if math.trunc[f64](-2.7f64) != -2.0f64 { os.exit(51i32) }
    if math.floor[f64](2.7f64) != 2.0f64 { os.exit(52i32) }
    if math.floor[f64](-2.7f64) != -3.0f64 { os.exit(53i32) }
    if math.ceil[f64](2.2f64) != 3.0f64 { os.exit(54i32) }
    if math.ceil[f64](-2.2f64) != -2.0f64 { os.exit(55i32) }
    // Ties to even: 2.5 down, 3.5 up, -2.5 up toward zero, and a value just under the half down.
    if math.round[f64](2.5f64) != 2.0f64 { os.exit(56i32) }
    if math.round[f64](3.5f64) != 4.0f64 { os.exit(57i32) }
    if math.round[f64](-2.5f64) != -2.0f64 { os.exit(58i32) }
    if math.round[f64](-3.5f64) != -4.0f64 { os.exit(59i32) }
    if math.round[f64](2.4999999f64) != 2.0f64 { os.exit(60i32) }
    if math.round[f64](2.5000001f64) != 3.0f64 { os.exit(61i32) }
    if math.round[f64](0.5f64) != 0.0f64 { os.exit(62i32) }
    if math.round[f64](1.5f64) != 2.0f64 { os.exit(63i32) }
    // The sign of a zero result is the sign of the input.
    if bits64(math.trunc[f64](-0.5f64)) != bits64(negative_zero()) { os.exit(64i32) }
    if bits64(math.ceil[f64](-0.5f64)) != bits64(negative_zero()) { os.exit(65i32) }
    if bits64(math.round[f64](-0.4f64)) != bits64(negative_zero()) { os.exit(66i32) }
    if bits64(math.floor[f64](0.5f64)) != bits64(0.0f64) { os.exit(67i32) }
    // Already integral, infinite or NaN: the value is its own answer.
    if math.floor[f64](3.0f64) != 3.0f64 { os.exit(68i32) }
    if math.round[f64](4503599627370497.0f64) != 4503599627370497.0f64 { os.exit(69i32) }
    if math.trunc[f64](infinity()) != infinity() { os.exit(70i32) }
    let rounded_nan = math.round[f64](quiet_nan())
    if rounded_nan == rounded_nan { os.exit(71i32) }
    // The same four in single precision, where the threshold is 2^23.
    if math.floor[f32](-2.5f32) != -3.0f32 { os.exit(72i32) }
    if math.ceil[f32](2.5f32) != 3.0f32 { os.exit(73i32) }
    if math.round[f32](2.5f32) != 2.0f32 { os.exit(74i32) }
    if math.trunc[f32](-2.5f32) != -2.0f32 { os.exit(75i32) }
    if math.round[f32](8388609.0f32) != 8388609.0f32 { os.exit(76i32) }
    ret ok
}

fn root_of[F: type](x: F) -> F {
    ret math.sqrt[F](x)
}
