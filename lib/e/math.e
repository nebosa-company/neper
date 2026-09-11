// Floating-point functions, every one generic over the float type. Section 11 splits the fence
// in two: the exact set -- `sqrt`, `fma`, `abs`, `min`, `max`, `floor`, `ceil`, `round`,
// `trunc`, `copysign` -- whose answer is one value on every target, and the approximate set,
// whose answer is within a stated bound. What is here is the exact set less `fma`, and `rsqrt`.
//
// `sqrt` is not in this file: it is the instruction, seeded by the compiler, because a
// correctly rounded square root is the hardware's to give. Everything else exact is bits and
// comparisons over the value, and needs nothing the language does not already have. The
// rounders fold the value through an `i64` where one fits and answer the value itself where one
// does not, since a float past 2^52 has no fraction left to round.
//
// Not here, and why:
//   `fma` -- one rounding, on every target. The baseline this compiler emits for has no fused
//   instruction and a software fused multiply-add is exact arithmetic on the significands; it is
//   its own piece of work, and one that must be verified against known answers.
//   `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `exp` `exp2` `log` `log2` `log10` `pow` --
//   within 2 ULP over the whole domain, which for the trigonometric functions means an exact
//   reduction of arguments past 2^60 and for `pow` means the special-value table section 11
//   fixes. That is a libm, and it is written with its bounds recorded here, not sketched.
//
// Per-function bounds, as section 11 asks for them to be recorded: `rsqrt` is `1 / sqrt(x)`,
// two correctly rounded operations, so within 1 ULP of the true value and inside the 2 ULP
// the section allows. Every other function here is exact.

use e.mem

// Every float carries its sign in its top bit, so the sign is a mask on the bits of the width
// -- which `size_of` folds for a scalar, so the branch that is not this width is gone (D144).
fn sign_bit_f32() -> u32 { ret 2147483648u32 }
fn sign_bit_f64() -> u64 { ret 9223372036854775808u64 }

// `1 / sqrt(x)`: two roundings, within 1 ULP, inside the bound section 11 allows for it.
fn rsqrt[F: type](x: F) -> F {
    let one = F(1u64)
    ret one / sqrt[F](x)
}

fn abs[F: type](x: F) -> F {
    if mem.size_of[F]() == 4usize {
        let bits = mem.bitcast[u32](x) & (sign_bit_f32() - 1u32)
        ret mem.bitcast[F](bits)
    }
    let bits = mem.bitcast[u64](x) & (sign_bit_f64() - 1u64)
    ret mem.bitcast[F](bits)
}

// IEEE 754-2019 `minimum` and `maximum`: a NaN on either side is the answer, and the two zeros
// are ordered, `-0` below `+0`, so `min(-0, +0)` is `-0` whichever way it is asked.
fn min[F: type](a: F, b: F) -> F {
    if a != a { ret a }
    if b != b { ret b }
    if a < b { ret a }
    if b < a { ret b }
    // Equal, which is the two zeros or one value twice: the one whose sign is set is the lesser.
    if is_negative[F](a) { ret a }
    ret b
}

fn max[F: type](a: F, b: F) -> F {
    if a != a { ret a }
    if b != b { ret b }
    if a > b { ret a }
    if b > a { ret b }
    if is_negative[F](a) { ret b }
    ret a
}

fn is_negative[F: type](x: F) -> bool {
    if mem.size_of[F]() == 4usize {
        let narrow = mem.bitcast[u32](x) & sign_bit_f32()
        ret narrow != 0u32
    }
    let wide = mem.bitcast[u64](x) & sign_bit_f64()
    ret wide != 0u64
}

// Toward zero. Past 2^52 (2^23 for `f32`) every float is already an integer, so the value is
// its own answer -- which is also what keeps an infinity an infinity and a NaN a NaN, since
// neither compares below the threshold. The sign is put back because `i64(-0.5)` is `0`.
fn trunc[F: type](x: F) -> F {
    if !(abs[F](x) < integral_threshold[F]()) { ret x }
    let whole = F(i64(x))
    ret copysign[F](whole, x)
}

fn floor[F: type](x: F) -> F {
    let toward_zero = trunc[F](x)
    if toward_zero > x { ret toward_zero - F(1u64) }
    ret toward_zero
}

fn ceil[F: type](x: F) -> F {
    let toward_zero = trunc[F](x)
    if toward_zero < x { ret toward_zero + F(1u64) }
    ret toward_zero
}

// Ties to even, which is what SPIR-V's `RoundEven` and every CPU's round-to-nearest do, so
// the device and the host agree that `round(2.5)` is `2`. The half is tested exactly: a float
// that is not past the threshold has a representable fraction, and `x - trunc(x)` is exact.
fn round[F: type](x: F) -> F {
    if !(abs[F](x) < integral_threshold[F]()) { ret x }
    let toward_zero = trunc[F](x)
    let fraction = abs[F](x - toward_zero)
    let half = F(1u64) / F(2u64)
    if fraction < half { ret toward_zero }
    let away = toward_zero + copysign[F](F(1u64), x)
    if fraction > half { ret away }
    // Exactly a half: whichever neighbour is even. A float below the threshold converts to an
    // `i64` exactly, so the parity is the integer's.
    if i64(toward_zero) % 2i64 == 0i64 { ret toward_zero }
    ret away
}

fn copysign[F: type](x: F, y: F) -> F {
    if mem.size_of[F]() == 4usize {
        let magnitude = mem.bitcast[u32](x) & (sign_bit_f32() - 1u32)
        let sign = mem.bitcast[u32](y) & sign_bit_f32()
        ret mem.bitcast[F](magnitude | sign)
    }
    let magnitude = mem.bitcast[u64](x) & (sign_bit_f64() - 1u64)
    let sign = mem.bitcast[u64](y) & sign_bit_f64()
    ret mem.bitcast[F](magnitude | sign)
}

// The first float of the width with no fractional bits at all: 2^23 and 2^52.
fn integral_threshold[F: type]() -> F {
    if mem.size_of[F]() == 4usize { ret F(8388608u64) }
    ret F(4503599627370496u64)
}
