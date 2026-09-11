// Floating-point functions, every one generic over the float type. Section 11 splits the fence
// in two: the exact set -- `sqrt`, `fma`, `abs`, `min`, `max`, `floor`, `ceil`, `round`,
// `trunc`, `copysign` -- whose answer is one value on every target, and the approximate set --
// `rsqrt` and the thirteen transcendentals -- whose answer is within a stated bound.
//
// `sqrt` is not in this file: it is the instruction, seeded by the compiler, because a
// correctly rounded square root is the hardware's to give. `fma` is computed the way the
// instruction computes it, in integer arithmetic on the significands, since the baseline this
// compiler emits for has no fused instruction and a version that rounded twice would be worse
// than none. The rest of the exact set is bits and comparisons over the value. The rounders
// fold the value through an `i64` where one fits and answer the value itself where one does
// not, since a float past 2^52 has no fraction left to round.
//
// The transcendentals are fdlibm's algorithms (Sun Microsystems, 1993, freely usable with the
// notice kept), as FreeBSD's msun carries them, over `f64`; `f32` goes through `f64` and rounds
// once more. Every constant is the published decimal stored as its bits, so the module holds
// the exact double each algorithm was derived with. The one piece not ported is the reduction
// of a large argument for `sin`, `cos` and `tan`, which is Payne-Hanek written here over 1280
// bits of 2/pi.
//
// Per-function bounds, as section 11 asks for them to be recorded. Each is measured, not
// derived: the four `math_*` fixtures compare against mpmath at 200 bits, and every function
// below is within 1 ULP of the correctly rounded result at every point tried -- `log2` and
// `log10` at 0 -- so within 1.5 ULP of the true value, inside the 2 the section allows.
//   exp, exp2, log, log2, log10          1 ULP (log2, log10: 0 at every point tried)
//   sin, cos, tan                        1 ULP, the reduction exact past 2^19 * pi/4
//   asin, acos, atan, atan2              1 ULP
//   pow                                  1 ULP
//   rsqrt                                1 ULP: `1 / sqrt(x)`, two correctly rounded operations
// Every other function is exact.

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

// --- fma: one rounding, in integer arithmetic on the significands.
//
// The baseline this compiler emits for has no fused instruction, so the fused multiply-add is
// computed the way the instruction computes it: the product of the two significands is exact
// -- 106 bits for `f64` -- the addend is aligned to it, the sum is taken exactly, and the result
// is rounded once. A 256-bit accumulator holds the aligned pair with room to spare; an operand
// so far below the other that it cannot reach the rounding position is folded into the lowest
// bit instead, which is all a rounding ever needs to know about it -- the "jam" bit, which also
// carries the direction through a subtraction.
//
// Every special value is handled before the arithmetic, per IEEE 754: a NaN in, a NaN out; an
// infinity times zero is invalid; infinities of opposite sign meeting are invalid; and the sign
// of an exact zero result is negative only when both the product and the addend are.

type Wide = struct { limbs: [4]u64 }

fn wide_zero() -> Wide {
    var w: Wide = zero
    ret w
}

fn wide_set(w: *Wide, limbs: [4]u64) {
    var at = 0usize
    while at < 4usize {
        w.limbs[at] = limbs[at]
        at += 1usize
    }
}

fn wide_is_zero(w: *const Wide) -> bool {
    ret w.limbs[0usize] == 0u64 && w.limbs[1usize] == 0u64 && w.limbs[2usize] == 0u64 && w.limbs[3usize] == 0u64
}

fn wide_shl(w: *Wide, n: u32) {
    if n == 0u32 { ret }
    let words = usize(n / 64u32)
    let bits = n % 64u32
    var out: [4]u64 = zero
    var at = 3usize
    while true {
        if at >= words {
            let from = at - words
            var value = w.limbs[from] << bits
            if bits != 0u32 && from > 0usize { value = value | (w.limbs[from - 1usize] >> (64u32 - bits)) }
            out[at] = value
        }
        if at == 0usize { break }
        at -= 1usize
    }
    wide_set(w, out)
}

// Shift right, folding every bit shifted out into bit zero.
fn wide_shr_jam(w: *Wide, n: u32) {
    if n == 0u32 { ret }
    var jam = false
    if n >= 256u32 {
        jam = !wide_is_zero(w)
        var cleared: [4]u64 = zero
        if jam { cleared[0usize] = 1u64 }
        wide_set(w, cleared)
        ret
    }
    let words = usize(n / 64u32)
    let bits = n % 64u32
    var at = 0usize
    while at < words {
        if w.limbs[at] != 0u64 { jam = true }
        at += 1usize
    }
    if bits != 0u32 && (w.limbs[words] & ((1u64 << bits) - 1u64)) != 0u64 { jam = true }
    var out: [4]u64 = zero
    at = 0usize
    while at + words < 4usize {
        let from = at + words
        var value = w.limbs[from] >> bits
        if bits != 0u32 && from + 1usize < 4usize { value = value | (w.limbs[from + 1usize] << (64u32 - bits)) }
        out[at] = value
        at += 1usize
    }
    if jam { out[0usize] = out[0usize] | 1u64 }
    wide_set(w, out)
}

fn wide_add(a: *Wide, b: *const Wide) {
    var carry = 0u64
    var at = 0usize
    while at < 4usize {
        let left = a.limbs[at]
        let sum = left + b.limbs[at]
        var next = 0u64
        if sum < left { next = 1u64 }
        let total = sum + carry
        if total < sum { next = 1u64 }
        a.limbs[at] = total
        carry = next
        at += 1usize
    }
}

// `a -= b`, which the caller has established is not negative.
fn wide_sub(a: *Wide, b: *const Wide) {
    var borrow = 0u64
    var at = 0usize
    while at < 4usize {
        let left = a.limbs[at]
        let right = b.limbs[at]
        let difference = left - right
        var next = 0u64
        if left < right { next = 1u64 }
        let total = difference - borrow
        if difference < borrow { next = 1u64 }
        a.limbs[at] = total
        borrow = next
        at += 1usize
    }
}

fn wide_less(a: *const Wide, b: *const Wide) -> bool {
    var at = 4usize
    while at > 0usize {
        at -= 1usize
        if a.limbs[at] != b.limbs[at] { ret a.limbs[at] < b.limbs[at] }
    }
    ret false
}

// The index of the highest set bit, for a value that is not zero.
fn wide_msb(w: *const Wide) -> u32 {
    var at = 4usize
    while at > 0usize {
        at -= 1usize
        if w.limbs[at] != 0u64 {
            var bit = 63u32
            while (w.limbs[at] >> bit) == 0u64 { bit -= 1u32 }
            ret u32(at) * 64u32 + bit
        }
    }
    ret 0u32
}

fn wide_bit(w: *const Wide, index: u32) -> bool {
    if index >= 256u32 { ret false }
    let selected = (w.limbs[usize(index / 64u32)] >> (index % 64u32)) & 1u64
    ret selected != 0u64
}

// Whether any bit below `index` is set.
fn wide_any_below(w: *const Wide, index: u32) -> bool {
    var at = 0u32
    while at < index && at < 256u32 {
        if at % 64u32 == 0u32 && at + 64u32 <= index {
            if w.limbs[usize(at / 64u32)] != 0u64 { ret true }
            at += 64u32
            continue
        }
        if wide_bit(w, at) { ret true }
        at += 1u32
    }
    ret false
}

// Bits [index, index + count) as an integer, `count` at most 64.
fn wide_extract(w: *const Wide, index: u32, count: u32) -> u64 {
    var value = 0u64
    var at = 0u32
    while at < count {
        if wide_bit(w, index + at) { value = value | (1u64 << at) }
        at += 1u32
    }
    ret value
}

// The 106-bit product of two significands below 2^53, into the low two limbs.
fn wide_product(a: u64, b: u64) -> Wide {
    let a_low = a & 4294967295u64
    let a_high = a >> 32u32
    let b_low = b & 4294967295u64
    let b_high = b >> 32u32
    let low_low = a_low * b_low
    let low_high = a_low * b_high
    let high_low = a_high * b_low
    let high_high = a_high * b_high
    // The two middle products meet in the middle; their sum can carry into the top.
    let middle = low_high + high_low
    var middle_carry = 0u64
    if middle < low_high { middle_carry = 1u64 }
    let low = low_low + (middle << 32u32)
    var low_carry = 0u64
    if low < low_low { low_carry = 1u64 }
    var w = wide_zero()
    w.limbs[0usize] = low
    w.limbs[1usize] = high_high + (middle >> 32u32) + (middle_carry << 32u32) + low_carry
    ret w
}

// A float taken apart: its sign, its significand as an integer with the hidden bit in place,
// and the exponent of that integer's lowest bit. `kind` is 0 finite, 1 zero, 2 infinity, 3 NaN.
type Parts = struct { negative: bool, significand: u64, exponent: i64, kind: u8 }

fn take_apart(bits: u64, mantissa: u32, exponent_bits: u32) -> Parts {
    var parts: Parts = zero
    let bias = (1i64 << (exponent_bits - 1u32)) - 1i64
    let exponent_mask = (1u64 << exponent_bits) - 1u64
    let fraction_mask = (1u64 << (mantissa - 1u32)) - 1u64
    parts.negative = ((bits >> (mantissa + exponent_bits - 1u32)) & 1u64) != 0u64
    let field = (bits >> (mantissa - 1u32)) & exponent_mask
    let fraction = bits & fraction_mask
    if field == exponent_mask {
        parts.kind = 2u8
        if fraction != 0u64 { parts.kind = 3u8 }
        ret parts
    }
    if field == 0u64 {
        if fraction == 0u64 {
            parts.kind = 1u8
            ret parts
        }
        parts.significand = fraction
        parts.exponent = 1i64 - bias - i64(mantissa - 1u32)
        ret parts
    }
    parts.significand = fraction | (1u64 << (mantissa - 1u32))
    parts.exponent = i64(field) - bias - i64(mantissa - 1u32)
    ret parts
}

fn put_together(negative: bool, field: u64, fraction: u64, mantissa: u32, exponent_bits: u32) -> u64 {
    var bits = (field << (mantissa - 1u32)) | fraction
    if negative { bits = bits | (1u64 << (mantissa + exponent_bits - 1u32)) }
    ret bits
}

fn quiet_nan_bits(mantissa: u32, exponent_bits: u32) -> u64 {
    let exponent_mask = (1u64 << exponent_bits) - 1u64
    let all_ones = exponent_mask << (mantissa - 1u32)
    ret all_ones | (1u64 << (mantissa - 2u32))
}

fn infinity_bits(negative: bool, mantissa: u32, exponent_bits: u32) -> u64 {
    let exponent_mask = (1u64 << exponent_bits) - 1u64
    ret put_together(negative, exponent_mask, 0u64, mantissa, exponent_bits)
}

// The far operand is aligned no more than this far below the near one: past it, it can only
// ever be a jam bit, and the accumulator has room for the near one shifted up by it.
const ALIGN_LIMIT: i64 = 128i64

fn fma_bits(a: u64, b: u64, c: u64, mantissa: u32, exponent_bits: u32) -> u64 {
    let pa = take_apart(a, mantissa, exponent_bits)
    let pb = take_apart(b, mantissa, exponent_bits)
    let pc = take_apart(c, mantissa, exponent_bits)
    if pa.kind == 3u8 || pb.kind == 3u8 || pc.kind == 3u8 { ret quiet_nan_bits(mantissa, exponent_bits) }
    let product_negative = pa.negative != pb.negative
    if pa.kind == 2u8 || pb.kind == 2u8 {
        if pa.kind == 1u8 || pb.kind == 1u8 { ret quiet_nan_bits(mantissa, exponent_bits) }
        if pc.kind == 2u8 && pc.negative != product_negative { ret quiet_nan_bits(mantissa, exponent_bits) }
        ret infinity_bits(product_negative, mantissa, exponent_bits)
    }
    if pc.kind == 2u8 { ret c }
    if pa.kind == 1u8 || pb.kind == 1u8 {
        if pc.kind == 1u8 { ret put_together(product_negative && pc.negative, 0u64, 0u64, mantissa, exponent_bits) }
        ret c
    }
    // The exact product, and the addend, each with the exponent of its lowest bit.
    var product = wide_product(pa.significand, pb.significand)
    let product_exponent = pa.exponent + pb.exponent
    var addend = wide_zero()
    var addend_exponent = product_exponent
    if pc.kind != 1u8 {
        addend.limbs[0usize] = pc.significand
        addend_exponent = pc.exponent
    }
    // Both are moved to one exponent, the lower of the two, unless the lower is so far down
    // that the operand there could never reach the rounding position -- then it is jammed.
    var base = product_exponent
    if addend_exponent < base { base = addend_exponent }
    if product_exponent - base > ALIGN_LIMIT { base = product_exponent - ALIGN_LIMIT }
    if addend_exponent - base > ALIGN_LIMIT { base = addend_exponent - ALIGN_LIMIT }
    if product_exponent >= base {
        wide_shl(&product, u32(product_exponent - base))
    } else {
        wide_shr_jam(&product, u32(base - product_exponent))
    }
    if addend_exponent >= base {
        wide_shl(&addend, u32(addend_exponent - base))
    } else {
        wide_shr_jam(&addend, u32(base - addend_exponent))
    }
    var total = product
    var negative = product_negative
    if pc.kind == 1u8 || pc.negative == product_negative {
        wide_add(&total, &addend)
    } else {
        if wide_less(&product, &addend) {
            total = addend
            wide_sub(&total, &product)
            negative = pc.negative
        } else {
            wide_sub(&total, &addend)
        }
    }
    // An exact cancellation is a positive zero under round-to-nearest.
    if wide_is_zero(&total) { ret put_together(false, 0u64, 0u64, mantissa, exponent_bits) }
    // The result is `total * 2^base`. Its leading bit sits at `base + msb`; the significand
    // keeps `mantissa` bits from there down, unless the format's lowest exponent stops it
    // sooner, which is what a subnormal result is.
    let bias = (1i64 << (exponent_bits - 1u32)) - 1i64
    let exponent_mask = (1u64 << exponent_bits) - 1u64
    let lowest_exponent = 1i64 - bias - i64(mantissa - 1u32)
    let msb = wide_msb(&total)
    var keep = i64(msb) + 1i64 - i64(mantissa)
    if lowest_exponent - base > keep { keep = lowest_exponent - base }
    var kept = 0u64
    if keep < 0i64 {
        // Fewer bits than the format holds, and room to place them exactly.
        kept = wide_extract(&total, 0u32, msb + 1u32) << u32(0i64 - keep)
        keep = 0i64
    } else {
        kept = wide_extract(&total, u32(keep), mantissa)
        if keep > 0i64 {
            let guard = wide_bit(&total, u32(keep - 1i64))
            let sticky = wide_any_below(&total, u32(keep - 1i64))
            if guard && (sticky || (kept & 1u64) != 0u64) {
                kept += 1u64
                if kept == (1u64 << mantissa) {
                    kept = kept >> 1u32
                    keep += 1i64
                }
            }
        }
    }
    let field = base + keep + i64(mantissa - 1u32) + bias
    let fraction_mask = (1u64 << (mantissa - 1u32)) - 1u64
    if kept >= (1u64 << (mantissa - 1u32)) {
        if field >= i64(exponent_mask) { ret infinity_bits(negative, mantissa, exponent_bits) }
        ret put_together(negative, u64(field), kept & fraction_mask, mantissa, exponent_bits)
    }
    ret put_together(negative, 0u64, kept, mantissa, exponent_bits)
}

fn fma[F: type](a: F, b: F, c: F) -> F {
    if mem.size_of[F]() == 4usize {
        let result = fma_bits(u64(mem.bitcast[u32](a)), u64(mem.bitcast[u32](b)), u64(mem.bitcast[u32](c)), 24u32, 8u32)
        ret mem.bitcast[F](u32(result))
    }
    let result = fma_bits(mem.bitcast[u64](a), mem.bitcast[u64](b), mem.bitcast[u64](c), 53u32, 11u32)
    ret mem.bitcast[F](result)
}

// --- The transcendentals: exp and log, and the three that are one of them scaled.
//
// The algorithms are fdlibm's (Sun Microsystems, 1993, freely usable with its notice kept) as
// FreeBSD's msun carries them, and every constant below is the published decimal stored as
// its bits, so the module holds the exact double the algorithm was derived with. Measured in
// `link/math_exp_log`: `exp`, `exp2` and `log` within 1 ULP, `log2` and `log10` at 0.

const LN2_HI: u64 = 4604418534311723008u64 // 0.6931471803691238
const LN2_LO: u64 = 4461442080421002358u64 // 1.9082149292705877e-10
const INV_LN2: u64 = 4609176140021203710u64 // 1.4426950408889634
const EXP_P1: u64 = 4595172819793696062u64 // 0.16666666666666602
const EXP_P2: u64 = 13791923578850950547u64 // -0.0027777777777015593
const EXP_P3: u64 = 4544508515198557740u64 // 6.613756321437934e-05
const EXP_P4: u64 = 13743786778040626161u64 // -1.6533902205465252e-06
const EXP_P5: u64 = 4496342204012209360u64 // 4.1381367970572385e-08
const EXP_OVERFLOW: u64 = 4649454530587146735u64 // 709.782712893384
const EXP_UNDERFLOW: u64 = 13873137513782915153u64 // -745.1332191019411
const LG1: u64 = 4604180019048437139u64 // 0.6666666666666735
const LG2: u64 = 4600877379321592324u64 // 0.3999999999940942
const LG3: u64 = 4598818590951641945u64 // 0.2857142874366239
const LG4: u64 = 4597174411056806063u64 // 0.22222198432149784
const LG5: u64 = 4595719342595441630u64 // 0.1818357216161805
const LG6: u64 = 4594685411790997151u64 // 0.15313837699209373
const LG7: u64 = 4594499633228436036u64 // 0.14798198605116586
const IVLN2_HI: u64 = 4609176140020449280u64 // 1.4426950407214463
const IVLN2_LO: u64 = 4460540536611119616u64 // 1.6751713164886512e-10
const IVLN10_HI: u64 = 4601495173784928256u64 // 0.4342944818781689
const IVLN10_LO: u64 = 4448312028596710869u64 // 2.5082946711645275e-11
const LOG10_2_HI: u64 = 4599094494223097856u64 // 0.30102999566361177
const LOG10_2_LO: u64 = 4420844829172378422u64 // 3.694239077158931e-13
const TWO54: u64 = 4850376798678024192u64 // 1.8014398509481984e+16

fn k(bits: u64) -> f64 { ret mem.bitcast[f64](bits) }
fn high_word(x: f64) -> u32 { ret u32(mem.bitcast[u64](x) >> 32u32) }
fn low_word(x: f64) -> u32 { ret u32(mem.bitcast[u64](x) & 4294967295u64) }
fn with_high_word(x: f64, high: u32) -> f64 {
    let low = mem.bitcast[u64](x) & 4294967295u64
    ret mem.bitcast[f64]((u64(high) << 32u32) | low)
}
fn with_low_word_zero(x: f64) -> f64 { ret mem.bitcast[f64](mem.bitcast[u64](x) & 18446744069414584320u64) }
fn from_words(high: u32, low: u32) -> f64 { ret mem.bitcast[f64]((u64(high) << 32u32) | u64(low)) }
fn nan64() -> f64 { ret k(9221120237041090560u64) }
fn inf64() -> f64 { ret k(9218868437227405312u64) }

// 2^n as a double, for n in the normal range.
fn power_of_two(n: i64) -> f64 { ret from_words(u32(1023i64 + n) << 20u32, 0u32) }

// `y * 2^n`, where `y` is near one and `n` may take the result below the normal range: two
// steps there, so that the second is the one that underflows and rounds.
fn scale(y: f64, n: i64) -> f64 {
    if n >= -1021i64 {
        if n == 1024i64 { ret y * 2.0f64 * k(9214364837600034816u64) }
        ret y * power_of_two(n)
    }
    ret y * power_of_two(n + 1000i64) * power_of_two(-1000i64)
}

// exp(hi - lo) * 2^n with |hi - lo| within half a log of two: the core of `exp` and `exp2`,
// which differ only in how they reach the reduced argument.
fn exp_core(hi: f64, lo: f64, n: i64) -> f64 {
    let x = hi - lo
    let t = x * x
    let c = x - t * (k(EXP_P1) + t * (k(EXP_P2) + t * (k(EXP_P3) + t * (k(EXP_P4) + t * k(EXP_P5)))))
    if n == 0i64 { ret 1.0f64 - ((x * c) / (c - 2.0f64) - x) }
    let y = 1.0f64 - ((lo - (x * c) / (2.0f64 - c)) - hi)
    ret scale(y, n)
}

fn exp64(x: f64) -> f64 {
    let hx = high_word(x)
    let sign = hx >> 31u32
    let ix = hx & 2147483647u32
    if ix >= 1082535490u32 {
        if ix >= 2146435072u32 {
            if ((ix & 1048575u32) | low_word(x)) != 0u32 { ret nan64() }
            if sign == 0u32 { ret inf64() }
            ret 0.0f64
        }
        if x > k(EXP_OVERFLOW) { ret inf64() }
        if x < k(EXP_UNDERFLOW) { ret 0.0f64 }
    }
    if ix <= 1071001154u32 {
        // Below half a log of two, no reduction; below 2^-28, 1 + x is the answer to the ULP.
        if ix < 1043333120u32 { ret 1.0f64 + x }
        ret exp_core(x, 0.0f64, 0i64)
    }
    var n = 0i64
    var hi = 0.0f64
    var lo = 0.0f64
    if ix < 1072734898u32 {
        if sign == 0u32 {
            hi = x - k(LN2_HI)
            lo = k(LN2_LO)
            n = 1i64
        } else {
            hi = x + k(LN2_HI)
            lo = 0.0f64 - k(LN2_LO)
            n = -1i64
        }
    } else {
        var half = 0.5f64
        if sign != 0u32 { half = -0.5f64 }
        n = i64(k(INV_LN2) * x + half)
        let t = f64(n)
        hi = x - t * k(LN2_HI)
        lo = t * k(LN2_LO)
    }
    ret exp_core(hi, lo, n)
}

// 2^x. The integer part is exact and the fraction `r` is in [-1/2, 1/2]; `r * ln 2` is
// formed as a high part that is exact -- `r` cut to 26 bits against the 33-bit `LN2_HI` --
// and a low part carrying what was cut, so the reduced argument reaches the core with the
// error of one rounding of the small part rather than of the whole.
fn exp2_64(x: f64) -> f64 {
    let hx = high_word(x)
    let ix = hx & 2147483647u32
    if ix >= 2146435072u32 {
        if ((ix & 1048575u32) | low_word(x)) != 0u32 { ret nan64() }
        if (hx >> 31u32) == 0u32 { ret inf64() }
        ret 0.0f64
    }
    if x >= 1024.0f64 { ret inf64() }
    if x <= -1075.0f64 { ret 0.0f64 }
    if ix < 1043333120u32 { ret 1.0f64 + x * k(LN2_HI) }
    let n = i64(floor[f64](x + 0.5f64))
    let r = x - f64(n)
    let r_high = mem.bitcast[f64](mem.bitcast[u64](r) & 18446744073575333888u64)
    let r_low = r - r_high
    let hi = r_high * k(LN2_HI)
    let lo = 0.0f64 - (r_low * k(LN2_HI) + r * k(LN2_LO))
    ret exp_core(hi, lo, n)
}

// The reduction `log` and its two scalings share: `x = 2^n * (1 + f)` with `1 + f` in
// [sqrt(2)/2, sqrt(2)). Zero, negative, infinite and NaN inputs are answered here.
type LogParts = struct { n: i64, f: f64, special: f64, is_special: bool }

fn log_reduce(x: f64) -> LogParts {
    var parts: LogParts = zero
    var hx = i64(high_word(x))
    if (high_word(x) >> 31u32) != 0u32 { hx = hx - 4294967296i64 }
    let lx = low_word(x)
    var value = x
    var n = 0i64
    if hx < 1048576i64 {
        if ((hx & 2147483647i64) | i64(lx)) == 0i64 {
            parts.special = 0.0f64 - inf64()
            parts.is_special = true
            ret parts
        }
        if hx < 0i64 {
            parts.special = nan64()
            parts.is_special = true
            ret parts
        }
        n = -54i64
        value = x * k(TWO54)
        hx = i64(high_word(value))
    }
    if hx >= 2146435072i64 {
        parts.special = x
        parts.is_special = true
        ret parts
    }
    n += (hx >> 20u32) - 1023i64
    hx = hx & 1048575i64
    let i = (hx + 614244i64) & 1048576i64
    value = with_high_word(value, u32(hx | (i ^ 1072693248i64)))
    n += i >> 20u32
    parts.n = n
    parts.f = value - 1.0f64
    ret parts
}

// fdlibm's polynomial: with `s = f / (2 + f)` and `z = s^2`, the `R` for which
// `f - hfsq + s * (hfsq + R)` is the log of `1 + f`. Both parts come back, since `log` itself
// chooses between two spellings of that sum by where `f` sits.
fn log_polynomial(f: f64) -> (f64, f64) {
    let s = f / (2.0f64 + f)
    let z = s * s
    let w = z * z
    let t1 = w * (k(LG2) + w * (k(LG4) + w * k(LG6)))
    let t2 = z * (k(LG1) + w * (k(LG3) + w * (k(LG5) + w * k(LG7))))
    ret (s, t1 + t2)
}

fn log64(x: f64) -> f64 {
    let parts = log_reduce(x)
    if parts.is_special { ret parts.special }
    let f = parts.f
    let dk = f64(parts.n)
    let hf = mem.bitcast[u64](f)
    // |f| < 2^-20: a short polynomial is enough, and f == 0 exactly is n * ln 2.
    if (high_word(f) & 2147483647u32) < 1044381696u32 {
        if f == 0.0f64 {
            if parts.n == 0i64 { ret 0.0f64 }
            ret dk * k(LN2_HI) + dk * k(LN2_LO)
        }
        let r = f * f * (0.5f64 - 0.33333333333333333f64 * f)
        if parts.n == 0i64 { ret f - r }
        ret dk * k(LN2_HI) - ((r - dk * k(LN2_LO)) - f)
    }
    let (s, big_r) = log_polynomial(f)
    // fdlibm's two spellings of the same sum, chosen by where `f` sits so that the rounding
    // of `hfsq` never dominates: the high word of `1 + f` against two fixed points.
    let hx = i64(high_word(1.0f64 + f) & 1048575u32)
    let lower = hx - 398458i64
    let upper = 440401i64 - hx
    if (lower | upper) > 0i64 {
        let hfsq = 0.5f64 * f * f
        if parts.n == 0i64 { ret f - (hfsq - s * (hfsq + big_r)) }
        ret dk * k(LN2_HI) - ((hfsq - (s * (hfsq + big_r) + dk * k(LN2_LO))) - f)
    }
    if parts.n == 0i64 { ret f - s * (f - big_r) }
    ret dk * k(LN2_HI) - ((s * (f - big_r) - dk * k(LN2_LO)) - f)
}

// log(1 + f) as a high and a low part, which `log2` and `log10` scale by their constant in
// two parts as well, so the scaling adds one rounding and not two.
fn log2_64(x: f64) -> f64 {
    let parts = log_reduce(x)
    if parts.is_special { ret parts.special }
    let f = parts.f
    let y = f64(parts.n)
    let hfsq = 0.5f64 * f * f
    let (s, big_r) = log_polynomial(f)
    let r = s * (hfsq + big_r)
    var hi = f - hfsq
    hi = with_low_word_zero(hi)
    let lo = (f - hi) - hfsq + r
    let val_hi = hi * k(IVLN2_HI)
    var val_lo = (lo + hi) * k(IVLN2_LO) + lo * k(IVLN2_HI)
    let w = y + val_hi
    val_lo += (y - w) + val_hi
    ret val_lo + w
}

fn log10_64(x: f64) -> f64 {
    let parts = log_reduce(x)
    if parts.is_special { ret parts.special }
    let f = parts.f
    let y = f64(parts.n)
    let hfsq = 0.5f64 * f * f
    let (s, big_r) = log_polynomial(f)
    let r = s * (hfsq + big_r)
    var hi = f - hfsq
    hi = with_low_word_zero(hi)
    let lo = (f - hi) - hfsq + r
    let val_hi = hi * k(IVLN10_HI)
    let y2 = y * k(LOG10_2_HI)
    var val_lo = y * k(LOG10_2_LO) + (lo + hi) * k(IVLN10_LO) + lo * k(IVLN10_HI)
    let w = y2 + val_hi
    val_lo += (y2 - w) + val_hi
    ret val_lo + w
}

fn exp[F: type](x: F) -> F { ret F(exp64(f64(x))) }
fn exp2[F: type](x: F) -> F { ret F(exp2_64(f64(x))) }
fn log[F: type](x: F) -> F { ret F(log64(f64(x))) }
fn log2[F: type](x: F) -> F { ret F(log2_64(f64(x))) }
fn log10[F: type](x: F) -> F { ret F(log10_64(f64(x))) }

// --- The inverse trigonometric family, fdlibm again: `atan` and `atan2`, `asin` and `acos`.
// Measured in `link/math_inverse`: all four within 1 ULP.

const ATAN_HI_0: u64 = 4602023952714414927u64 // 0.4636476090008061
const ATAN_HI_1: u64 = 4605249457297304856u64 // 0.7853981633974483
const ATAN_HI_2: u64 = 4607027438436873883u64 // 0.982793723247329
const ATAN_HI_3: u64 = 4609753056924675352u64 // 1.5707963267948966
const ATAN_LO_0: u64 = 4357843414468748770u64 // 2.2698777452961687e-17
const ATAN_LO_1: u64 = 4359948597267291143u64 // 3.061616997868383e-17
const ATAN_LO_2: u64 = 4354989122426817469u64 // 1.3903311031230998e-17
const ATAN_LO_3: u64 = 4364452196894661639u64 // 6.123233995736766e-17
const AT0: u64 = 4599676419421066509u64 // 0.3333333333333293
const AT1: u64 = 13819745816549059524u64 // -0.19999999999876483
const AT2: u64 = 4594314991288484863u64 // 0.14285714272503466
const AT3: u64 = 13816042856347014769u64 // -0.11111110405462356
const AT4: u64 = 4591215095208222830u64 // 0.09090887133436507
const AT5: u64 = 13813579038447671917u64 // -0.0769187620504483
const AT6: u64 = 4589464229703073105u64 // 0.06661073137387531
const AT7: u64 = 13811939918460419482u64 // -0.058335701337905735
const AT8: u64 = 4587333258118041067u64 // 0.049768779946159324
const AT9: u64 = 13808797612367309871u64 // -0.036531572744216916
const AT10: u64 = 4580351289466214929u64 // 0.016285820115365782
const PI_LO: u64 = 4368955796522032135u64 // 1.2246467991473532e-16
const PI: u64 = 4614256656552045848u64 // 3.141592653589793
const PIO2_HI: u64 = 4609753056924675352u64 // 1.5707963267948966
const PIO2_LO: u64 = 4364452196894661639u64 // 6.123233995736766e-17
const PIO4_HI: u64 = 4605249457297304856u64 // 0.7853981633974483
const PS0: u64 = 4595172819793696085u64 // 0.16666666666666666
const PS1: u64 = 13822908529170411389u64 // -0.3255658186224009
const PS2: u64 = 4596417465768494165u64 // 0.20121253213486293
const PS3: u64 = 13809305468778614587u64 // -0.04005553450067941
const PS4: u64 = 4560439845004096136u64 // 0.0007915349942898145
const PS5: u64 = 4540259411154564873u64 // 3.479331075960212e-05
const QS1: u64 = 13835966419869248843u64 // -2.403394911734414
const QS2: u64 = 4611733184086379208u64 // 2.0209457602335057
const QS3: u64 = 13827746767276147033u64 // -0.6882839716054533
const QS4: u64 = 4590215604441354882u64 // 0.07703815055590194

fn atan_hi(index: i64) -> f64 {
    if index == 0i64 { ret k(ATAN_HI_0) }
    if index == 1i64 { ret k(ATAN_HI_1) }
    if index == 2i64 { ret k(ATAN_HI_2) }
    ret k(ATAN_HI_3)
}

fn atan_lo(index: i64) -> f64 {
    if index == 0i64 { ret k(ATAN_LO_0) }
    if index == 1i64 { ret k(ATAN_LO_1) }
    if index == 2i64 { ret k(ATAN_LO_2) }
    ret k(ATAN_LO_3)
}

// The argument is folded onto [0, 7/16) through one of four tangent identities, each with its
// own atan of the fold point in two parts, and the remainder is a polynomial in the square.
fn atan64(x: f64) -> f64 {
    let hx = high_word(x)
    let ix = hx & 2147483647u32
    if ix >= 1141899264u32 {
        // |x| >= 2^66: pi/2 to the sign, and a NaN to itself.
        if ix > 2146435072u32 || (ix == 2146435072u32 && low_word(x) != 0u32) { ret x + x }
        if (hx >> 31u32) != 0u32 { ret 0.0f64 - k(ATAN_HI_3) - k(ATAN_LO_3) }
        ret k(ATAN_HI_3) + k(ATAN_LO_3)
    }
    var id = -1i64
    var v = x
    if ix < 1071382528u32 {
        // |x| < 7/16: no fold, and below 2^-27 the argument is its own atan.
        if ix < 1044381696u32 { ret x }
    } else {
        v = abs[f64](x)
        if ix < 1072889856u32 {
            if ix < 1072037888u32 {
                // |x| < 11/16
                id = 0i64
                v = (2.0f64 * v - 1.0f64) / (2.0f64 + v)
            } else {
                // |x| < 19/16
                id = 1i64
                v = (v - 1.0f64) / (v + 1.0f64)
            }
        } else {
            if ix < 1073971200u32 {
                // |x| < 39/16
                id = 2i64
                v = (v - 1.5f64) / (1.0f64 + 1.5f64 * v)
            } else {
                id = 3i64
                v = -1.0f64 / v
            }
        }
    }
    let z = v * v
    let w = z * z
    let s1 = z * (k(AT0) + w * (k(AT2) + w * (k(AT4) + w * (k(AT6) + w * (k(AT8) + w * k(AT10))))))
    let s2 = w * (k(AT1) + w * (k(AT3) + w * (k(AT5) + w * (k(AT7) + w * k(AT9)))))
    if id < 0i64 { ret v - v * (s1 + s2) }
    let folded = atan_hi(id) - ((v * (s1 + s2) - atan_lo(id)) - v)
    if (hx >> 31u32) != 0u32 { ret 0.0f64 - folded }
    ret folded
}

// The quadrant from the two signs, the special values IEEE fixes for zeros and infinities, and
// `atan(|y / x|)` otherwise -- with the ratio's exponent gap deciding when it is pi/2 or zero
// outright rather than a division that would overflow or vanish.
fn atan2_64(y: f64, x: f64) -> f64 {
    let hx = high_word(x)
    let lx = low_word(x)
    let hy = high_word(y)
    let ly = low_word(y)
    let ix = hx & 2147483647u32
    let iy = hy & 2147483647u32
    if x != x || y != y { ret x + y }
    if hx == 1072693248u32 && lx == 0u32 { ret atan64(y) }
    let m = ((hy >> 31u32) & 1u32) | ((hx >> 30u32) & 2u32)
    if (iy | ly) == 0u32 {
        // y is a zero: the answer is a zero of y's sign, or pi of y's sign when x is negative.
        if m == 0u32 || m == 1u32 { ret y }
        if m == 2u32 { ret k(PI) + k(PI_LO) }
        ret 0.0f64 - k(PI) - k(PI_LO)
    }
    if (ix | lx) == 0u32 {
        if (hy >> 31u32) != 0u32 { ret 0.0f64 - k(PIO2_HI) - k(PIO2_LO) }
        ret k(PIO2_HI) + k(PIO2_LO)
    }
    if ix == 2146435072u32 {
        if iy == 2146435072u32 {
            if m == 0u32 { ret k(PIO4_HI) + k(ATAN_LO_1) }
            if m == 1u32 { ret 0.0f64 - k(PIO4_HI) - k(ATAN_LO_1) }
            if m == 2u32 { ret 3.0f64 * k(PIO4_HI) + k(ATAN_LO_2) }
            ret 0.0f64 - 3.0f64 * k(PIO4_HI) - k(ATAN_LO_2)
        }
        if m == 0u32 { ret 0.0f64 }
        if m == 1u32 { ret 0.0f64 - 0.0f64 }
        if m == 2u32 { ret k(PI) + k(PI_LO) }
        ret 0.0f64 - k(PI) - k(PI_LO)
    }
    if iy == 2146435072u32 {
        if (hy >> 31u32) != 0u32 { ret 0.0f64 - k(PIO2_HI) - k(PIO2_LO) }
        ret k(PIO2_HI) + k(PIO2_LO)
    }
    let gap = (i64(iy) - i64(ix)) >> 20u32
    var z = 0.0f64
    if gap > 60i64 {
        z = k(PIO2_HI) + 0.5f64 * k(PI_LO)
    } else {
        if (hx >> 31u32) != 0u32 && gap < -60i64 {
            z = 0.0f64
        } else {
            z = atan64(abs[f64](y / x))
        }
    }
    if m == 0u32 { ret z }
    if m == 1u32 { ret 0.0f64 - z }
    if m == 2u32 { ret k(PI) - (z - k(PI_LO)) }
    let lowered = z - k(PI_LO)
    ret lowered - k(PI)
}

// The rational approximation `asin` and `acos` share, in `t = x^2` below one half and in
// `t = (1 - |x|) / 2` above it.
fn asin_ratio(t: f64) -> f64 {
    let p = t * (k(PS0) + t * (k(PS1) + t * (k(PS2) + t * (k(PS3) + t * (k(PS4) + t * k(PS5))))))
    let q = 1.0f64 + t * (k(QS1) + t * (k(QS2) + t * (k(QS3) + t * k(QS4))))
    ret p / q
}

fn asin64(x: f64) -> f64 {
    let hx = high_word(x)
    let ix = hx & 2147483647u32
    if ix >= 1072693248u32 {
        // |x| >= 1: exactly one is pi/2 with the sign, anything past is not an angle.
        if ((ix - 1072693248u32) | low_word(x)) == 0u32 { ret x * k(PIO2_HI) + x * k(PIO2_LO) }
        ret nan64()
    }
    if ix < 1071644672u32 {
        // |x| < 1/2, and below 2^-27 the argument is its own asin.
        if ix < 1044381696u32 { ret x }
        let t = x * x
        let w = asin_ratio(t)
        ret x + x * w
    }
    let w = 1.0f64 - abs[f64](x)
    let t = w * 0.5f64
    let ratio = asin_ratio(t)
    let s = sqrt[f64](t)
    var result = 0.0f64
    if ix >= 1072640819u32 {
        // |x| > 0.975
        result = k(PIO2_HI) - (2.0f64 * (s + s * ratio) - k(PIO2_LO))
    } else {
        let w2 = with_low_word_zero(s)
        let c = (t - w2 * w2) / (s + w2)
        let p = 2.0f64 * s * ratio - (k(PIO2_LO) - 2.0f64 * c)
        let q = k(PIO4_HI) - 2.0f64 * w2
        result = k(PIO4_HI) - (p - q)
    }
    if (hx >> 31u32) != 0u32 { ret 0.0f64 - result }
    ret result
}

fn acos64(x: f64) -> f64 {
    let hx = high_word(x)
    let ix = hx & 2147483647u32
    if ix >= 1072693248u32 {
        if ((ix - 1072693248u32) | low_word(x)) == 0u32 {
            if (hx >> 31u32) != 0u32 { ret 2.0f64 * k(PIO2_HI) + 2.0f64 * k(PIO2_LO) }
            ret 0.0f64
        }
        ret nan64()
    }
    if ix < 1071644672u32 {
        // |x| < 1/2, and below 2^-57 the answer is pi/2 to the ULP.
        if ix <= 1012924416u32 { ret k(PIO2_HI) + k(PIO2_LO) }
        let z = x * x
        let r = asin_ratio(z)
        ret k(PIO2_HI) - (x - (k(PIO2_LO) - x * r))
    }
    if (hx >> 31u32) != 0u32 {
        // x < -1/2
        let z = (1.0f64 + x) * 0.5f64
        let r = asin_ratio(z)
        let s = sqrt[f64](z)
        let w = r * s - k(PIO2_LO)
        ret k(PI) - 2.0f64 * (s + w)
    }
    let z = (1.0f64 - x) * 0.5f64
    let s = sqrt[f64](z)
    let df = with_low_word_zero(s)
    let c = (z - df * df) / (s + df)
    let r = asin_ratio(z)
    let w = r * s + c
    ret 2.0f64 * (df + w)
}

fn atan[F: type](x: F) -> F { ret F(atan64(f64(x))) }
fn atan2[F: type](y: F, x: F) -> F { ret F(atan2_64(f64(y), f64(x))) }
fn asin[F: type](x: F) -> F { ret F(asin64(f64(x))) }
fn acos[F: type](x: F) -> F { ret F(acos64(f64(x))) }

// --- sin, cos and tan: fdlibm's kernels over an argument reduced to [-pi/4, pi/4].
//
// Below 2^19 * pi/4 the reduction is fdlibm's three-step Cody-Waite, with pi/2 in three parts
// of 33 bits so that each product with the integer quotient is exact. Past it the reduction
// is Payne-Hanek over 1280 bits of 2/pi, written here rather than ported: the argument is
// `m * 2^e`, and the bits of 2/pi that can reach the result are the 256 around bit `e`,
// so `m` times that window, taken modulo 2^256, holds the quotient's low two bits and 253
// bits of the fraction -- more than the 61 bits the worst double cancels. Measured in
// `link/math_trig`: all three within 1 ULP.

const S1: u64 = 13818544856648471881u64 // -0.16666666666666632
const S2: u64 = 4575957461383575718u64 // 0.00833333333332249
const S3: u64 = 13774824197404582357u64 // -0.0001984126982985795
const S4: u64 = 4523617212983017085u64 // 2.7557313707070068e-06
const S5: u64 = 13716528393433619691u64 // -2.5050760253406863e-08
const S6: u64 = 4460209850635244924u64 // 1.58969099521155e-10
const C1: u64 = 4586165620538955084u64 // 0.0416666666666666
const C2: u64 = 13787419979223748983u64 // -0.001388888888887411
const C3: u64 = 4537941361668330896u64 // 2.480158728947673e-05
const C4: u64 = 13732177093731308205u64 // -2.7557314351390663e-07
const C5: u64 = 4477121870137961473u64 // 2.0875723212975648e-09
const C6: u64 = 13666448951086692564u64 // -1.1359647557788195e-11
const T0: u64 = 4599676419421066595u64 // 0.3333333333333341
const T1: u64 = 4593971859893059194u64 // 0.13333333333320124
const T2: u64 = 4587938466107703806u64 // 0.05396825397622605
const T3: u64 = 4581960672245896759u64 // 0.021869488294859542
const T4: u64 = 4576262931677611155u64 // 0.0088632398235993
const T5: u64 = 4570429193025094440u64 // 0.0035920791075913124
const T6: u64 = 4564358403679355669u64 // 0.0014562094543252903
const T7: u64 = 4558562946408670465u64 // 0.0005880412408202641
const T8: u64 = 4553182066015810993u64 // 0.00024646313481898734
const T9: u64 = 4545397049192321702u64 // 7.817944429395571e-05
const T10: u64 = 4544897349388904425u64 // 7.140724913826082e-05
const T11: u64 = 13759470804966331251u64 // -1.8558637485527546e-05
const T12: u64 = 4538267711989316308u64 // 2.590730518636337e-05
const PIO4: u64 = 4605249457297304856u64 // 0.7853981633974483
const PIO4_LO: u64 = 4359948597267291143u64 // 3.061616997868383e-17
const INVPIO2: u64 = 4603909380684499075u64 // 0.6366197723675814
const PIO2_1: u64 = 4609753056924401664u64 // 1.5707963267341256
const PIO2_1T: u64 = 4454258360616903473u64 // 6.077100506506192e-11
const PIO2_2: u64 = 4454258360616747008u64 // 6.077100506303966e-11
const PIO2_2T: u64 = 4297306550709743731u64 // 2.0222662487959506e-21
const PIO2_3: u64 = 4297306550709518336u64 // 2.0222662487111665e-21
const PIO2_3T: u64 = 4142048980368378305u64 // 8.4784276603689e-32

// floor(2/pi * 2^1280), least significant limb first.
fn two_over_pi_limb(index: usize) -> u64 {
    if index == 0usize { ret 17352294737506481693u64 }
    if index == 1usize { ret 6197850593633725355u64 }
    if index == 2usize { ret 7780917995555872008u64 }
    if index == 3usize { ret 4397547296490951402u64 }
    if index == 4usize { ret 8441921394348257659u64 }
    if index == 5usize { ret 5712322887342352941u64 }
    if index == 6usize { ret 7869616827067468215u64 }
    if index == 7usize { ret 17235013589178936607u64 }
    if index == 8usize { ret 2303758334597371919u64 }
    if index == 9usize { ret 11278244420634880059u64 }
    if index == 10usize { ret 4148332274289687028u64 }
    if index == 11usize { ret 16833452818741296705u64 }
    if index == 12usize { ret 16754012890938950788u64 }
    if index == 13usize { ret 18311050168422213438u64 }
    if index == 14usize { ret 452944820249399836u64 }
    if index == 15usize { ret 13196794004601950944u64 }
    if index == 16usize { ret 18325537948574664033u64 }
    if index == 17usize { ret 15808362127397457985u64 }
    if index == 18usize { ret 18169587780923219392u64 }
    if index == 19usize { ret 11743562013128004905u64 }
    ret 0u64
}
const PIO2_HI_EXACT: u64 = 4609753056924675352u64 // 1.5707963267948966
const PIO2_LO_EXACT: u64 = 4364452196894661639u64 // 6.123233995736766e-17

// A reduced argument: `hi + lo` within pi/4 of the input less `n` quarter turns.
type Reduced = struct { n: i64, hi: f64, lo: f64 }

// An exact product of two doubles as a sum of two, by Veltkamp's split: the high halves
// multiply without rounding, and the rest is gathered as the error term.
fn two_product(a: f64, b: f64) -> (f64, f64) {
    let split = 134217729.0f64
    let ca = a * split
    let a_hi = ca - (ca - a)
    let a_lo = a - a_hi
    let cb = b * split
    let b_hi = cb - (cb - b)
    let b_lo = b - b_hi
    let p = a * b
    let e = ((a_hi * b_hi - p) + a_hi * b_lo + a_lo * b_hi) + a_lo * b_lo
    ret (p, e)
}

// 256 bits of the 1280-bit 2/pi starting at bit `start`, least significant first, with
// zeros beyond either end.
fn two_over_pi_window(start: i64) -> Wide {
    var w = wide_zero()
    var at = 0usize
    while at < 4usize {
        let bit = start + i64(at) * 64i64
        var value = 0u64
        if bit >= 0i64 && bit < 1280i64 {
            let word = usize(bit / 64i64)
            let shift = u32(bit % 64i64)
            value = two_over_pi_limb(word) >> shift
            if shift != 0u32 && word + 1usize < 20usize { value = value | (two_over_pi_limb(word + 1usize) << (64u32 - shift)) }
        } else {
            if bit < 0i64 && bit > -64i64 {
                // The window starts below the table: only the top of this limb is real.
                value = two_over_pi_limb(0usize) << u32(0i64 - bit)
            }
        }
        w.limbs[at] = value
        at += 1usize
    }
    ret w
}

// Payne-Hanek. `x = m * 2^e` with `m` the 53-bit significand; `x * 2/pi` modulo 4 is `m` times
// the bits of 2/pi that land between weight 2^1 and weight 2^-253, and nothing else. That is a
// 256-bit window of the table, and `m` times it modulo 2^256 puts the quotient's low two bits at
// 253 and 254 and the fraction below. The fraction, or one less it when it is past a half, is the
// reduced argument as a multiple of pi/2, taken to two doubles and scaled by pi/2 in two parts.
fn reduce_large(x: f64) -> Reduced {
    var out: Reduced = zero
    let bits = mem.bitcast[u64](x)
    let exponent_field = i64((bits >> 52u32) & 2047u64)
    let m = (bits & 4503599627370495u64) | 4503599627370496u64
    let e = exponent_field - 1075i64
    // Bit `i` of the window has weight 2^(i + start + e - 1280); weight 2^0 is to sit at bit 253.
    let start = 1280i64 - e - 253i64
    let window = two_over_pi_window(start)
    var product = wide_zero()
    var at = 0usize
    while at < 4usize {
        var part = wide_product(m, window.limbs[at])
        wide_shl(&part, u32(at) * 64u32)
        wide_add(&product, &part)
        at += 1usize
    }
    var n = i64(wide_extract(&product, 253u32, 2u32))
    // The fraction: bits 0..252. Past a half, the nearer quarter turn is the next one.
    var fraction = product
    fraction.limbs[3usize] = fraction.limbs[3usize] & 2305843009213693951u64
    var negative = false
    if wide_bit(&fraction, 252u32) {
        n = (n + 1i64) & 3i64
        negative = true
        var whole = wide_zero()
        whole.limbs[3usize] = 2305843009213693952u64
        wide_sub(&whole, &fraction)
        fraction = whole
    }
    if wide_is_zero(&fraction) {
        out.n = n
        ret out
    }
    // The top 53 bits and the 53 below them, each as a double at its own weight.
    let msb = wide_msb(&fraction)
    var top_start = i64(msb) - 52i64
    var top_bits = wide_extract(&fraction, u32(top_start), 53u32)
    var r_hi = f64(top_bits) * power_of_two(top_start - 253i64)
    var r_lo = 0.0f64
    if top_start > 0i64 {
        var low_start = top_start - 53i64
        var low_count = 53u32
        if low_start < 0i64 {
            low_count = u32(top_start)
            low_start = 0i64
        }
        let low_bits = wide_extract(&fraction, u32(low_start), low_count)
        r_lo = f64(low_bits) * power_of_two(low_start - 253i64)
    }
    if negative {
        r_hi = 0.0f64 - r_hi
        r_lo = 0.0f64 - r_lo
    }
    // Times pi/2, exactly enough: the high product split by Veltkamp, the cross terms gathered.
    let (p, p_err) = two_product(r_hi, k(PIO2_HI_EXACT))
    let tail = p_err + r_hi * k(PIO2_LO_EXACT) + r_lo * k(PIO2_HI_EXACT)
    out.hi = p + tail
    out.lo = (p - out.hi) + tail
    out.n = n
    ret out
}

// fdlibm's three-step reduction for arguments below 2^19 * pi/4. The quotient is rounded to
// the nearest integer through the 2^52 trick; each step subtracts an exact product and keeps
// what the subtraction lost, until the remainder holds enough bits of the true one.
fn reduce_medium(x: f64) -> Reduced {
    var out: Reduced = zero
    let magic = 6755399441055744.0f64
    var quotient = x * k(INVPIO2) + magic
    quotient = quotient - magic
    let n = i64(quotient)
    var r = x - quotient * k(PIO2_1)
    var w = quotient * k(PIO2_1T)
    let j = i64(high_word(x) >> 20u32) & 2047i64
    var y0 = r - w
    var i = j - (i64(high_word(y0) >> 20u32) & 2047i64)
    if i > 16i64 {
        var t = r
        w = quotient * k(PIO2_2)
        r = t - w
        w = quotient * k(PIO2_2T) - ((t - r) - w)
        y0 = r - w
        i = j - (i64(high_word(y0) >> 20u32) & 2047i64)
        if i > 49i64 {
            t = r
            w = quotient * k(PIO2_3)
            r = t - w
            w = quotient * k(PIO2_3T) - ((t - r) - w)
            y0 = r - w
        }
    }
    out.n = n & 3i64
    out.hi = y0
    out.lo = (r - y0) - w
    ret out
}

fn reduce(x: f64) -> Reduced {
    let ix = high_word(x) & 2147483647u32
    if ix < 1094263291u32 { ret reduce_medium(x) }
    // The large path works on the magnitude and puts the sign back: `-x` is `-n` quarter turns
    // and `-r`, and `-n` modulo 4 is `(4 - n) & 3` with the remainder negated.
    if (high_word(x) >> 31u32) != 0u32 {
        var reduced = reduce_large(0.0f64 - x)
        reduced.n = (4i64 - reduced.n) & 3i64
        reduced.hi = 0.0f64 - reduced.hi
        reduced.lo = 0.0f64 - reduced.lo
        ret reduced
    }
    ret reduce_large(x)
}

fn kernel_sin(x: f64, y: f64, has_tail: bool) -> f64 {
    let z = x * x
    let w = z * z
    let r = k(S2) + z * (k(S3) + z * k(S4)) + z * w * (k(S5) + z * k(S6))
    let v = z * x
    if !has_tail { ret x + v * (k(S1) + z * r) }
    ret x - ((z * (0.5f64 * y - v * r) - y) - v * k(S1))
}

fn kernel_cos(x: f64, y: f64) -> f64 {
    let z = x * x
    let w = z * z
    let r = z * (k(C1) + z * (k(C2) + z * k(C3))) + w * w * (k(C4) + z * (k(C5) + z * k(C6)))
    let hz = 0.5f64 * z
    let w2 = 1.0f64 - hz
    ret w2 + (((1.0f64 - w2) - hz) + (z * r - x * y))
}

// `odd` selects tan or its negative reciprocal, which is what the quarter turns past the first
// need; past 0.6744 the argument is folded about pi/4 first.
fn kernel_tan(x_in: f64, y_in: f64, odd: bool) -> f64 {
    var x = x_in
    var y = y_in
    let hx = high_word(x)
    let ix = hx & 2147483647u32
    let folded = ix >= 1072010280u32
    if folded {
        if (hx >> 31u32) != 0u32 {
            x = 0.0f64 - x
            y = 0.0f64 - y
        }
        let z = k(PIO4) - x
        let w = k(PIO4_LO) - y
        x = z + w
        y = 0.0f64
    }
    let z = x * x
    let w = z * z
    var r = k(T1) + w * (k(T3) + w * (k(T5) + w * (k(T7) + w * (k(T9) + w * k(T11)))))
    let v = z * (k(T2) + w * (k(T4) + w * (k(T6) + w * (k(T8) + w * (k(T10) + w * k(T12))))))
    let s = z * x
    r = y + z * (s * (r + v) + y)
    r += k(T0) * s
    let w2 = x + r
    if folded {
        var vv = 1.0f64
        if odd { vv = -1.0f64 }
        var sign = 1.0f64
        if (hx >> 31u32) != 0u32 { sign = -1.0f64 }
        ret sign * (vv - 2.0f64 * (x - (w2 * w2 / (w2 + vv) - r)))
    }
    if !odd { ret w2 }
    // -1 / tan, with the reciprocal taken in two parts so that its rounding is corrected.
    let zz = with_low_word_zero(w2)
    let vv = r - (zz - x)
    let a = -1.0f64 / w2
    let t = with_low_word_zero(a)
    let ss = 1.0f64 + t * zz
    ret t + a * (ss + t * vv)
}

fn sin64(x: f64) -> f64 {
    let ix = high_word(x) & 2147483647u32
    if ix <= 1072243195u32 {
        if ix < 1044381696u32 { ret x }
        ret kernel_sin(x, 0.0f64, false)
    }
    if ix >= 2146435072u32 { ret x - x }
    let r = reduce(x)
    if r.n == 0i64 { ret kernel_sin(r.hi, r.lo, true) }
    if r.n == 1i64 { ret kernel_cos(r.hi, r.lo) }
    if r.n == 2i64 { ret 0.0f64 - kernel_sin(r.hi, r.lo, true) }
    ret 0.0f64 - kernel_cos(r.hi, r.lo)
}

fn cos64(x: f64) -> f64 {
    let ix = high_word(x) & 2147483647u32
    if ix <= 1072243195u32 {
        if ix < 1044381696u32 { ret 1.0f64 }
        ret kernel_cos(x, 0.0f64)
    }
    if ix >= 2146435072u32 { ret x - x }
    let r = reduce(x)
    if r.n == 0i64 { ret kernel_cos(r.hi, r.lo) }
    if r.n == 1i64 { ret 0.0f64 - kernel_sin(r.hi, r.lo, true) }
    if r.n == 2i64 { ret 0.0f64 - kernel_cos(r.hi, r.lo) }
    ret kernel_sin(r.hi, r.lo, true)
}

fn tan64(x: f64) -> f64 {
    let ix = high_word(x) & 2147483647u32
    if ix <= 1072243195u32 {
        if ix < 1044381696u32 { ret x }
        ret kernel_tan(x, 0.0f64, false)
    }
    if ix >= 2146435072u32 { ret x - x }
    let r = reduce(x)
    ret kernel_tan(r.hi, r.lo, (r.n & 1i64) != 0i64)
}

fn sin[F: type](x: F) -> F { ret F(sin64(f64(x))) }
fn cos[F: type](x: F) -> F { ret F(cos64(f64(x))) }
fn tan[F: type](x: F) -> F { ret F(tan64(f64(x))) }

// --- pow, fdlibm's: log2(|x|) to more than a double, times `y` split in two, so the error
// in the exponent is not multiplied by `y` before it reaches 2^(that). The special-value
// table of section 11 is the IEEE 754 one and is handled before any arithmetic. Measured in
// `link/math_pow`: within 1 ULP.

const POW_BP1: u64 = 4609434218613702656u64 // 1.5
const POW_DP_H1: u64 = 4603444093224222720u64 // 0.5849624872207642
const POW_DP_L1: u64 = 4489242115478376454u64 // 1.350039202129749e-08
const POW_L1: u64 = 4603579539098120963u64 // 0.5999999999999946
const POW_L2: u64 = 4601392076422097919u64 // 0.4285714285785502
const POW_L3: u64 = 4599676419357746765u64 // 0.33333332981837743
const POW_L4: u64 = 4598584653024936193u64 // 0.272728123808534
const POW_L5: u64 = 4597478449480325989u64 // 0.23066074577556175
const POW_L6: u64 = 4596625081194860271u64 // 0.20697501780033842
const POW_LG2: u64 = 4604418534313441775u64 // 0.6931471805599453
const POW_LG2_H: u64 = 4604418534330597376u64 // 0.6931471824645996
const POW_LG2_L: u64 = 13700051638354996281u64 // -1.904654299957768e-09
const POW_OVT: u64 = 4365981760143196926u64 // 8.008566259537294e-17
const POW_CP: u64 = 4606838314010018813u64 // 0.9617966939259756
const POW_CP_H: u64 = 4606838314073325568u64 // 0.9617967009544373
const POW_CP_L: u64 = 13708446955223056885u64 // -7.028461650952758e-09
const POW_IVLN2: u64 = 4609176140021203710u64 // 1.4426950408889634
const POW_IVLN2_H: u64 = 4609176139934466048u64 // 1.4426950216293335
const POW_IVLN2_L: u64 = 4491406094830001988u64 // 1.9259629911266175e-08
const POW_THIRD: u64 = 4599676419421066581u64 // 0.3333333333333333
const POW_TWO53: u64 = 4845873199050653696u64 // 9007199254740992.0

fn signed_high(x: f64) -> i64 {
    let h = high_word(x)
    if (h >> 31u32) != 0u32 { ret i64(h) - 4294967296i64 }
    ret i64(h)
}

// Whether `y` is an integer, and whether an odd one: 0 for neither, 1 for odd, 2 for even.
fn integer_kind(y: f64) -> i64 {
    let iy = high_word(y) & 2147483647u32
    let ly = low_word(y)
    if iy >= 1128267776u32 { ret 2i64 }
    if iy < 1072693248u32 { ret 0i64 }
    let power = i64(iy >> 20u32) - 1023i64
    if power > 20i64 {
        let shift = u32(52i64 - power)
        let j = ly >> shift
        if (j << shift) == ly { ret 2i64 - i64(j & 1u32) }
        ret 0i64
    }
    if ly != 0u32 { ret 0i64 }
    let shift = u32(20i64 - power)
    let j = iy >> shift
    if (j << shift) == iy { ret 2i64 - i64(j & 1u32) }
    ret 0i64
}

fn pow64(x: f64, y: f64) -> f64 {
    let hx = signed_high(x)
    let lx = low_word(x)
    let hy = signed_high(y)
    let ly = low_word(y)
    let ix = hx & 2147483647i64
    let iy = hy & 2147483647i64
    // x^0 is 1, and 1^y is 1, a NaN `y` included.
    if (iy | i64(ly)) == 0i64 { ret 1.0f64 }
    if hx == 1072693248i64 && lx == 0u32 { ret 1.0f64 }
    if ix > 2146435072i64 || (ix == 2146435072i64 && lx != 0u32) || iy > 2146435072i64 || (iy == 2146435072i64 && ly != 0u32) { ret nan64() }
    var yisint = 0i64
    if hx < 0i64 { yisint = integer_kind(y) }
    if ly == 0u32 {
        if iy == 2146435072i64 {
            // y is an infinity: (-1)^inf is 1, |x| > 1 goes with the sign of y, |x| < 1 against.
            if ((ix - 1072693248i64) | i64(lx)) == 0i64 { ret 1.0f64 }
            if ix >= 1072693248i64 {
                if hy >= 0i64 { ret y }
                ret 0.0f64
            }
            if hy < 0i64 { ret 0.0f64 - y }
            ret 0.0f64
        }
        if iy == 1072693248i64 {
            if hy < 0i64 { ret 1.0f64 / x }
            ret x
        }
        if hy == 1073741824i64 { ret x * x }
        if hy == 1071644672i64 && hx >= 0i64 { ret sqrt[f64](x) }
    }
    var ax = abs[f64](x)
    if lx == 0u32 {
        if ix == 2146435072i64 || ix == 0i64 || ix == 1072693248i64 {
            // x is a zero, an infinity or one.
            var z = ax
            if hy < 0i64 { z = 1.0f64 / z }
            if hx < 0i64 {
                if ((ix - 1072693248i64) | yisint) == 0i64 { ret nan64() }
                if yisint == 1i64 { z = 0.0f64 - z }
            }
            ret z
        }
    }
    // A negative base with a non-integer exponent is not a real number; an odd integer
    // exponent keeps the sign.
    var negative_base = hx < 0i64
    if negative_base && yisint == 0i64 { ret nan64() }
    var s = 1.0f64
    if negative_base && yisint == 1i64 { s = -1.0f64 }
    var t1 = 0.0f64
    var t2 = 0.0f64
    if iy > 1105199104i64 {
        // |y| > 2^31: the result overflows or vanishes unless x is within 2^-20 of one, and
        // there log(x) is a short series.
        if iy > 1140850688i64 {
            if ix <= 1072693247i64 {
                if hy < 0i64 { ret inf64() }
                ret 0.0f64
            }
            if ix >= 1072693248i64 {
                if hy > 0i64 { ret inf64() }
                ret 0.0f64
            }
        }
        if ix < 1072693247i64 {
            if hy < 0i64 { ret s * inf64() }
            ret s * 0.0f64
        }
        if ix > 1072693248i64 {
            if hy > 0i64 { ret s * inf64() }
            ret s * 0.0f64
        }
        let t = ax - 1.0f64
        let w = (t * t) * (0.5f64 - t * (k(POW_THIRD) - t * 0.25f64))
        let u = k(POW_IVLN2_H) * t
        let v = t * k(POW_IVLN2_L) - w * k(POW_IVLN2)
        t1 = with_low_word_zero(u + v)
        t2 = v - (t1 - u)
    } else {
        var n = 0i64
        var ixn = ix
        if ixn < 1048576i64 {
            ax = ax * k(POW_TWO53)
            n -= 53i64
            ixn = signed_high(ax)
        }
        n += (ixn >> 20u32) - 1023i64
        let j = ixn & 1048575i64
        ixn = j | 1072693248i64
        var kk = 0i64
        if j <= 235662i64 {
            kk = 0i64
        } else {
            if j < 767610i64 {
                kk = 1i64
            } else {
                kk = 0i64
                n += 1i64
                ixn -= 1048576i64
            }
        }
        ax = with_high_word(ax, u32(ixn))
        var bp = 1.0f64
        var dp_h = 0.0f64
        var dp_l = 0.0f64
        if kk == 1i64 {
            bp = k(POW_BP1)
            dp_h = k(POW_DP_H1)
            dp_l = k(POW_DP_L1)
        }
        // ss = s_h + s_l = (ax - bp) / (ax + bp), in two parts.
        let u = ax - bp
        let v = 1.0f64 / (ax + bp)
        let ss = u * v
        let s_h = with_low_word_zero(ss)
        let t_h = from_words(u32(((ixn >> 1u32) | 536870912i64) + 524288i64 + (kk << 18u32)), 0u32)
        let t_l = ax - (t_h - bp)
        let s_l = v * ((u - s_h * t_h) - s_h * t_l)
        // log(ax) from the series in ss.
        var s2 = ss * ss
        var r = s2 * s2 * (k(POW_L1) + s2 * (k(POW_L2) + s2 * (k(POW_L3) + s2 * (k(POW_L4) + s2 * (k(POW_L5) + s2 * k(POW_L6))))))
        r += s_l * (s_h + ss)
        s2 = s_h * s_h
        let t_h2 = with_low_word_zero(3.0f64 + s2 + r)
        let t_l2 = r - ((t_h2 - 3.0f64) - s2)
        let u2 = s_h * t_h2
        let v2 = s_l * t_h2 + t_l2 * ss
        let p_h = with_low_word_zero(u2 + v2)
        let p_l = v2 - (p_h - u2)
        let z_h = k(POW_CP_H) * p_h
        let z_l = k(POW_CP_L) * p_h + p_l * k(POW_CP) + dp_l
        // log2(ax) = n + dp_h + z_h + z_l, as t1 + t2.
        let t = f64(n)
        t1 = with_low_word_zero(((z_h + z_l) + dp_h) + t)
        t2 = z_l - (((t1 - t) - dp_h) - z_h)
    }
    // y * log2(ax) as p_h + p_l, with y split so the high product is exact.
    let y1 = with_low_word_zero(y)
    let p_l = (y - y1) * t1 + y * t2
    var p_h = y1 * t1
    var z = p_l + p_h
    let j = signed_high(z)
    let i = low_word(z)
    if j >= 1083179008i64 {
        // z >= 1024: overflow, unless it is exactly the edge and the low part pulls it under.
        if ((j - 1083179008i64) | i64(i)) != 0i64 { ret s * inf64() }
        if p_l + k(POW_OVT) > z - p_h { ret s * inf64() }
    } else {
        if (j & 2147483647i64) >= 1083231232i64 {
            // z <= -1075: underflow, with the same edge.
            if ((j + 1064317952i64) | i64(i)) != 0i64 { ret s * 0.0f64 }
            if p_l <= z - p_h { ret s * 0.0f64 }
        }
    }
    // 2^(p_h + p_l): the integer part off into `n`, the rest through exp's polynomial.
    let ii = j & 2147483647i64
    var kk = (ii >> 20u32) - 1023i64
    var n = 0i64
    if ii > 1071644672i64 {
        var nn = j + (1048576i64 >> u32(kk + 1i64))
        kk = ((nn & 2147483647i64) >> 20u32) - 1023i64
        let t = from_words(u32(nn & (0i64 - (1048575i64 >> u32(kk)) - 1i64)), 0u32)
        nn = ((nn & 1048575i64) | 1048576i64) >> u32(20i64 - kk)
        if j < 0i64 { nn = 0i64 - nn }
        p_h -= t
        n = nn
    }
    let t = with_low_word_zero(p_l + p_h)
    let u = t * k(POW_LG2_H)
    let v = (p_l - (t - p_h)) * k(POW_LG2) + t * k(POW_LG2_L)
    z = u + v
    let w = v - (z - u)
    let tt = z * z
    let t1b = z - tt * (k(EXP_P1) + tt * (k(EXP_P2) + tt * (k(EXP_P3) + tt * (k(EXP_P4) + tt * k(EXP_P5)))))
    let r = (z * t1b) / (t1b - 2.0f64) - (w + z * w)
    z = 1.0f64 - (r - z)
    let jz = signed_high(z) + (n << 20u32)
    if (jz >> 20u32) <= 0i64 { ret s * scale(z, n) }
    ret s * with_high_word(z, u32(jz))
}

fn pow[F: type](x: F, y: F) -> F { ret F(pow64(f64(x), f64(y))) }
