// Fixed-point decimals: a signed 128-bit coefficient and a scale, the value being
// `coefficient * 10^-scale` with the scale in `0..38`. Arithmetic is exact or refuses:
// `add`, `sub` and `mul` never drop a digit and say `Overflow` when the coefficient
// would not fit; only `div`, `quantize` and `to_i64`, which carry a `Rounding`, ever
// discard digits. `Inexact` is declared by the surface and never returned here: every
// operation that could be inexact carries a rounding mode, so there is no path that
// has to refuse a result for being inexact.
//
// The 128-bit arithmetic is written out over two limbs: sign-magnitude inside, the
// two's-complement `(low, high)` of the surface at the edges.

use e.str

type Coefficient = struct { low: u64, high: i64 }
type Decimal = struct { coefficient: Coefficient, scale: u8 }
type Rounding = enum u8 { ToEven, AwayFromZero, TowardZero, Floor, Ceiling }
error Invalid
error Overflow
error Inexact

const MAX_SCALE: u8 = 38u8

// A magnitude in two unsigned limbs.
type Magnitude = struct { low: u64, high: u64 }

fn magnitude_of(c: Coefficient) -> (Magnitude, bool) {
    var m: Magnitude = zero
    if c.high < 0i64 {
        // Two's complement negation of the pair.
        m.low = 0u64 -% c.low
        m.high = 0u64 -% u64(c.high)
        if c.low != 0u64 { m.high -= 1u64 }
        ret (m, true)
    }
    m.low = c.low
    m.high = u64(c.high)
    ret (m, false)
}

// The coefficient for a magnitude and sign; `Overflow` past 2^127 - 1 (or 2^127 when
// negative).
fn coefficient_of(m: Magnitude, negative: bool) -> (Coefficient, err) {
    var c: Coefficient = zero
    if !negative {
        if m.high > 9223372036854775807u64 { ret (zero, Overflow) }
        c.low = m.low
        c.high = i64(m.high)
        ret (c, ok)
    }
    if m.high > 9223372036854775808u64 || (m.high == 9223372036854775808u64 && m.low != 0u64) { ret (zero, Overflow) }
    c.low = 0u64 -% m.low
    var high = 0u64 -% m.high
    if m.low != 0u64 { high -= 1u64 }
    c.high = i64(high)
    ret (c, ok)
}

fn is_zero(m: Magnitude) -> bool { ret m.low == 0u64 && m.high == 0u64 }

fn magnitude_cmp(a: Magnitude, b: Magnitude) -> i32 {
    if a.high != b.high {
        if a.high < b.high { ret -1i32 }
        ret 1i32
    }
    if a.low != b.low {
        if a.low < b.low { ret -1i32 }
        ret 1i32
    }
    ret 0i32
}

fn magnitude_add(a: Magnitude, b: Magnitude) -> (Magnitude, bool) {
    var out: Magnitude = zero
    out.low = a.low +% b.low
    var carry = 0u64
    if out.low < a.low { carry = 1u64 }
    out.high = a.high +% b.high +% carry
    let overflowed = out.high < a.high || (out.high == a.high && carry != 0u64 && b.high == 18446744073709551615u64)
    ret (out, overflowed)
}

// `a - b` for `a >= b`.
fn magnitude_sub(a: Magnitude, b: Magnitude) -> Magnitude {
    var out: Magnitude = zero
    out.low = a.low -% b.low
    var borrow = 0u64
    if a.low < b.low { borrow = 1u64 }
    out.high = a.high -% b.high -% borrow
    ret out
}

// `a * small`, `false` on overflow.
fn magnitude_mul_small(a: Magnitude, small: u64) -> (Magnitude, bool) {
    let (low, low_carry) = mul_wide(a.low, small)
    let (high, high_carry) = mul_wide(a.high, small)
    if high_carry != 0u64 { ret (zero, false) }
    var out: Magnitude = zero
    out.low = low
    out.high = high +% low_carry
    if out.high < high { ret (zero, false) }
    ret (out, true)
}

// 64 x 64 -> 128 as (low, high).
fn mul_wide(a: u64, b: u64) -> (u64, u64) {
    let a0 = a & 4294967295u64
    let a1 = a >> 32u32
    let b0 = b & 4294967295u64
    let b1 = b >> 32u32
    let p00 = a0 * b0
    let p01 = a0 * b1
    let p10 = a1 * b0
    let p11 = a1 * b1
    let middle = (p00 >> 32u32) + (p01 & 4294967295u64) + (p10 & 4294967295u64)
    let low = (p00 & 4294967295u64) | (middle << 32u32)
    let high = p11 + (p01 >> 32u32) + (p10 >> 32u32) + (middle >> 32u32)
    ret (low, high)
}

// `a * b` in full; `false` when the product needs more than 128 bits.
fn magnitude_mul(a: Magnitude, b: Magnitude) -> (Magnitude, bool) {
    if a.high != 0u64 && b.high != 0u64 { ret (zero, false) }
    let (ll, ll_high) = mul_wide(a.low, b.low)
    let (lh, lh_high) = mul_wide(a.low, b.high)
    let (hl, hl_high) = mul_wide(a.high, b.low)
    if lh_high != 0u64 || hl_high != 0u64 { ret (zero, false) }
    var out: Magnitude = zero
    out.low = ll
    out.high = ll_high +% lh
    if out.high < ll_high { ret (zero, false) }
    let before = out.high
    out.high = out.high +% hl
    if out.high < before { ret (zero, false) }
    ret (out, true)
}

// `a / small` and the remainder.
fn magnitude_divmod_small(a: Magnitude, small: u64) -> (Magnitude, u64) {
    var out: Magnitude = zero
    // Long division in four 32-bit digits.
    var remainder = 0u64
    var digits: [4]u64 = zero
    digits[0] = a.high >> 32u32
    digits[1] = a.high & 4294967295u64
    digits[2] = a.low >> 32u32
    digits[3] = a.low & 4294967295u64
    var quotient: [4]u64 = zero
    var at = 0usize
    while at < 4usize {
        let current = (remainder << 32u32) | digits[at]
        quotient[at] = current / small
        remainder = current % small
        at += 1usize
    }
    out.high = (quotient[0] << 32u32) | quotient[1]
    out.low = (quotient[2] << 32u32) | quotient[3]
    ret (out, remainder)
}

fn make(coefficient: Coefficient, scale: u8) -> (Decimal, err) {
    if scale > MAX_SCALE { ret (zero, Invalid) }
    var d: Decimal = zero
    d.coefficient = coefficient
    d.scale = scale
    ret (d, ok)
}

// Trailing zeros of the coefficient come off, one scale unit each, down to scale 0.
fn normalize(value: Decimal) -> Decimal {
    let (m, negative) = magnitude_of(value.coefficient)
    var magnitude = m
    var scale = value.scale
    if is_zero(magnitude) {
        var z: Decimal = zero
        ret z
    }
    while scale > 0u8 {
        let (quotient, remainder) = magnitude_divmod_small(magnitude, 10u64)
        if remainder != 0u64 { break }
        magnitude = quotient
        scale -= 1u8
    }
    let (coefficient, coefficient_error) = coefficient_of(magnitude, negative)
    if coefficient_error != ok { ret value }
    var out: Decimal = zero
    out.coefficient = coefficient
    out.scale = scale
    ret out
}

// The magnitude scaled up to `scale` decimal places from `from`.
fn raise_scale(m: Magnitude, from: u8, to: u8) -> (Magnitude, bool) {
    var out = m
    var at = from
    while at < to {
        let (scaled, fits) = magnitude_mul_small(out, 10u64)
        if !fits { ret (zero, false) }
        out = scaled
        at += 1u8
    }
    ret (out, true)
}

// Both operands at the larger scale, as signed magnitudes.
fn aligned(a: Decimal, b: Decimal) -> (Magnitude, bool, Magnitude, bool, u8, err) {
    let (ma, na) = magnitude_of(a.coefficient)
    let (mb, nb) = magnitude_of(b.coefficient)
    var scale = a.scale
    if b.scale > scale { scale = b.scale }
    let (ra, fits_a) = raise_scale(ma, a.scale, scale)
    let (rb, fits_b) = raise_scale(mb, b.scale, scale)
    if !fits_a || !fits_b { ret (zero, false, zero, false, 0u8, Overflow) }
    ret (ra, na, rb, nb, scale, ok)
}

fn signed_sum(ma: Magnitude, na: bool, mb: Magnitude, nb: bool, scale: u8) -> (Decimal, err) {
    var magnitude: Magnitude = zero
    var negative = false
    if na == nb {
        let (total, overflowed) = magnitude_add(ma, mb)
        if overflowed { ret (zero, Overflow) }
        magnitude = total
        negative = na
    } else {
        if magnitude_cmp(ma, mb) >= 0i32 {
            magnitude = magnitude_sub(ma, mb)
            negative = na
        } else {
            magnitude = magnitude_sub(mb, ma)
            negative = nb
        }
    }
    if is_zero(magnitude) { negative = false }
    let (coefficient, coefficient_error) = coefficient_of(magnitude, negative)
    if coefficient_error != ok { ret (zero, coefficient_error) }
    var out: Decimal = zero
    out.coefficient = coefficient
    out.scale = scale
    ret (out, ok)
}

fn add(a: Decimal, b: Decimal) -> (Decimal, err) {
    let (ma, na, mb, nb, scale, align_error) = aligned(a, b)
    if align_error != ok { ret (zero, align_error) }
    let (sum, sum_error) = signed_sum(ma, na, mb, nb, scale)
    ret (sum, sum_error)
}

fn sub(a: Decimal, b: Decimal) -> (Decimal, err) {
    let (ma, na, mb, nb, scale, align_error) = aligned(a, b)
    if align_error != ok { ret (zero, align_error) }
    let (difference, difference_error) = signed_sum(ma, na, mb, !nb, scale)
    ret (difference, difference_error)
}

fn mul(a: Decimal, b: Decimal) -> (Decimal, err) {
    if usize(a.scale) + usize(b.scale) > usize(MAX_SCALE) { ret (zero, Overflow) }
    let (ma, na) = magnitude_of(a.coefficient)
    let (mb, nb) = magnitude_of(b.coefficient)
    let (product, fits) = magnitude_mul(ma, mb)
    if !fits { ret (zero, Overflow) }
    var negative = na != nb
    if is_zero(product) { negative = false }
    let (coefficient, coefficient_error) = coefficient_of(product, negative)
    if coefficient_error != ok { ret (zero, coefficient_error) }
    var out: Decimal = zero
    out.coefficient = coefficient
    out.scale = a.scale + b.scale
    ret (out, ok)
}

// Whether a truncated magnitude rounds up, from the discarded part: `remainder` out of
// `divisor`, the truncated value's parity, and the sign.
fn rounds_up(rounding: Rounding, remainder: u64, divisor: u64, odd: bool, negative: bool) -> bool {
    if remainder == 0u64 { ret false }
    if rounding == .TowardZero { ret false }
    if rounding == .AwayFromZero { ret true }
    if rounding == .Floor { ret negative }
    if rounding == .Ceiling { ret !negative }
    let twice = remainder * 2u64
    if twice > divisor { ret true }
    if twice < divisor { ret false }
    ret odd
}

// `value` at exactly `scale` places: raised exactly, or lowered with the rounding.
fn quantize(value: Decimal, scale: u8, rounding: Rounding) -> (Decimal, err) {
    if scale > MAX_SCALE { ret (zero, Invalid) }
    let (m, negative) = magnitude_of(value.coefficient)
    var magnitude = m
    if scale >= value.scale {
        let (raised, fits) = raise_scale(magnitude, value.scale, scale)
        if !fits { ret (zero, Overflow) }
        magnitude = raised
    } else {
        // Divide by 10^(drop) as repeated tens, rounding once on the whole discarded part:
        // all but the last division truncate, and the last one sees whether anything
        // below it was nonzero through the sticky flag.
        var drop = value.scale - scale
        var sticky = false
        while drop > 1u8 {
            let (quotient, remainder) = magnitude_divmod_small(magnitude, 10u64)
            if remainder != 0u64 { sticky = true }
            magnitude = quotient
            drop -= 1u8
        }
        let (quotient, remainder) = magnitude_divmod_small(magnitude, 10u64)
        var twice_remainder = remainder * 2u64
        var divisor = 20u64
        // The sticky part pushes a tie above the half.
        if sticky && remainder == 5u64 { twice_remainder += 1u64 }
        if sticky && remainder == 0u64 { twice_remainder = 1u64 }
        magnitude = quotient
        if rounds_up(rounding, twice_remainder, divisor, (quotient.low & 1u64) != 0u64, negative) {
            let (up, overflowed) = magnitude_add(magnitude, Magnitude { low: 1u64, high: 0u64 })
            if overflowed { ret (zero, Overflow) }
            magnitude = up
        }
    }
    var sign = negative
    if is_zero(magnitude) { sign = false }
    let (coefficient, coefficient_error) = coefficient_of(magnitude, sign)
    if coefficient_error != ok { ret (zero, coefficient_error) }
    var out: Decimal = zero
    out.coefficient = coefficient
    out.scale = scale
    ret (out, ok)
}

// `a / b` at `scale` places: the dividend is raised so that the quotient has one guard
// digit beyond `scale`, divided by long division, then quantized with the remainder as
// the sticky part.
fn div(a: Decimal, b: Decimal, scale: u8, rounding: Rounding) -> (Decimal, err) {
    if scale > MAX_SCALE { ret (zero, Invalid) }
    let (ma, na) = magnitude_of(a.coefficient)
    let (mb, nb) = magnitude_of(b.coefficient)
    if is_zero(mb) { ret (zero, Invalid) }
    // Target scale of the raw quotient: scale + 1 guard digit; the dividend must be at
    // scale (wanted + b.scale) for coefficient division to land there.
    let wanted = usize(scale) + 1usize + usize(b.scale)
    var dividend = ma
    var dividend_scale = usize(a.scale)
    while dividend_scale < wanted {
        let (raised, fits) = magnitude_mul_small(dividend, 10u64)
        if !fits { ret (zero, Overflow) }
        dividend = raised
        dividend_scale += 1usize
    }
    if dividend_scale > wanted {
        // `a` carries more places than the guard needs; drop them into the sticky part.
        var sticky = false
        while dividend_scale > wanted {
            let (quotient, remainder) = magnitude_divmod_small(dividend, 10u64)
            if remainder != 0u64 { sticky = true }
            dividend = quotient
            dividend_scale -= 1usize
        }
        if sticky {
            // Keep the information as one extra unit below the guard digit is not exact;
            // instead widen by one more place carrying a 1, which is enough to break ties.
            let (raised, fits) = magnitude_mul_small(dividend, 10u64)
            if !fits { ret (zero, Overflow) }
            let (with_sticky, _) = magnitude_add(raised, Magnitude { low: 1u64, high: 0u64 })
            dividend = with_sticky
            dividend_scale += 1usize
        }
    }
    let (quotient, remainder) = magnitude_divmod(dividend, mb)
    // Fold the division remainder into a sticky digit below the quotient.
    var raw = quotient
    var raw_scale = dividend_scale - usize(b.scale)
    if !is_zero(remainder) {
        let (raised, fits) = magnitude_mul_small(raw, 10u64)
        if !fits { ret (zero, Overflow) }
        let (with_sticky, _) = magnitude_add(raised, Magnitude { low: 1u64, high: 0u64 })
        raw = with_sticky
        raw_scale += 1usize
    }
    if raw_scale > usize(MAX_SCALE) {
        // Only when the guard digits pushed past the limit: quantize from what we have by
        // dropping places arithmetically first.
        while raw_scale > usize(MAX_SCALE) {
            let (q, r) = magnitude_divmod_small(raw, 10u64)
            raw = q
            if r != 0u64 { raw.low = raw.low | 1u64 }
            raw_scale -= 1usize
        }
    }
    var negative = na != nb
    if is_zero(raw) { negative = false }
    let (coefficient, coefficient_error) = coefficient_of(raw, negative)
    if coefficient_error != ok { ret (zero, coefficient_error) }
    var wide: Decimal = zero
    wide.coefficient = coefficient
    wide.scale = u8(raw_scale)
    let (result, quantize_error) = quantize(wide, scale, rounding)
    ret (result, quantize_error)
}

// Binary long division of two magnitudes, 128 bits a time.
fn magnitude_divmod(a: Magnitude, b: Magnitude) -> (Magnitude, Magnitude) {
    if b.high == 0u64 {
        let (quotient, remainder) = magnitude_divmod_small(a, b.low)
        ret (quotient, Magnitude { low: remainder, high: 0u64 })
    }
    var quotient: Magnitude = zero
    var remainder: Magnitude = zero
    var bit = 128usize
    while bit > 0usize {
        bit -= 1usize
        // remainder = remainder << 1 | bit(a, bit)
        remainder.high = (remainder.high << 1u32) | (remainder.low >> 63u32)
        remainder.low = remainder.low << 1u32
        var source = a.low
        var index = bit
        if bit >= 64usize {
            source = a.high
            index = bit - 64usize
        }
        if ((source >> u32(index)) & 1u64) != 0u64 { remainder.low = remainder.low | 1u64 }
        if magnitude_cmp(remainder, b) >= 0i32 {
            remainder = magnitude_sub(remainder, b)
            if bit >= 64usize {
                quotient.high = quotient.high | (1u64 << u32(bit - 64usize))
            } else {
                quotient.low = quotient.low | (1u64 << u32(bit))
            }
        }
    }
    ret (quotient, remainder)
}

fn compare(a: Decimal, b: Decimal) -> i32 {
    let (ma, na, mb, nb, _, align_error) = aligned(a, b)
    if align_error != ok {
        // Past 128 bits at the common scale: the signs and the integer parts decide.
        if na != nb {
            if na { ret -1i32 }
            ret 1i32
        }
        ret 0i32
    }
    if is_zero(ma) && is_zero(mb) { ret 0i32 }
    if na != nb {
        if na { ret -1i32 }
        ret 1i32
    }
    let order = magnitude_cmp(ma, mb)
    if na { ret 0i32 - order }
    ret order
}

// `[+-]digits[.digits][e[+-]digits]`, every digit kept: the scale is the count of
// fraction digits less the exponent, clamped into `0..38` by raising the coefficient
// when the exponent is positive.
fn parse(source: str) -> (Decimal, err) {
    var at = 0usize
    var negative = false
    if at < source.len && (source[at] == 45u8 || source[at] == 43u8) {
        negative = source[at] == 45u8
        at += 1usize
    }
    var magnitude: Magnitude = zero
    var digits = 0usize
    var fraction_digits = 0usize
    var in_fraction = false
    while at < source.len {
        let c = source[at]
        if c >= 48u8 && c <= 57u8 {
            let (scaled, fits) = magnitude_mul_small(magnitude, 10u64)
            if !fits { ret (zero, Overflow) }
            let (with_digit, overflowed) = magnitude_add(scaled, Magnitude { low: u64(c - 48u8), high: 0u64 })
            if overflowed { ret (zero, Overflow) }
            magnitude = with_digit
            digits += 1usize
            if in_fraction { fraction_digits += 1usize }
        } else {
            if c == 46u8 && !in_fraction {
                in_fraction = true
            } else {
                break
            }
        }
        at += 1usize
    }
    if digits == 0usize { ret (zero, Invalid) }
    var exponent = 0i64
    if at < source.len && (source[at] == 101u8 || source[at] == 69u8) {
        at += 1usize
        var exponent_negative = false
        if at < source.len && (source[at] == 45u8 || source[at] == 43u8) {
            exponent_negative = source[at] == 45u8
            at += 1usize
        }
        var exponent_digits = 0usize
        while at < source.len && source[at] >= 48u8 && source[at] <= 57u8 {
            exponent = exponent * 10i64 + i64(source[at] - 48u8)
            if exponent > 1000i64 { ret (zero, Overflow) }
            exponent_digits += 1usize
            at += 1usize
        }
        if exponent_digits == 0usize { ret (zero, Invalid) }
        if exponent_negative { exponent = 0i64 - exponent }
    }
    if at != source.len { ret (zero, Invalid) }
    var scale = i64(fraction_digits) - exponent
    while scale < 0i64 {
        let (scaled, fits) = magnitude_mul_small(magnitude, 10u64)
        if !fits { ret (zero, Overflow) }
        magnitude = scaled
        scale += 1i64
    }
    if scale > i64(MAX_SCALE) { ret (zero, Overflow) }
    if is_zero(magnitude) { negative = false }
    let (coefficient, coefficient_error) = coefficient_of(magnitude, negative)
    if coefficient_error != ok { ret (zero, coefficient_error) }
    var out: Decimal = zero
    out.coefficient = coefficient
    out.scale = u8(scale)
    ret (out, ok)
}

// Plain notation: the coefficient's digits with the point `scale` places from the
// right, a leading zero before the point when the value is below one.
fn format(value: Decimal, b: *str.Builder) -> err {
    let (m, negative) = magnitude_of(value.coefficient)
    var magnitude = m
    var digits: [40]u8 = zero
    var count = 0usize
    while !is_zero(magnitude) {
        let (quotient, remainder) = magnitude_divmod_small(magnitude, 10u64)
        digits[count] = u8(remainder) + 48u8
        count += 1usize
        magnitude = quotient
    }
    if count == 0usize {
        digits[0] = 48u8
        count = 1usize
    }
    // Pad with zeros up to scale + 1 digits so the integer part has at least one.
    while count < usize(value.scale) + 1usize {
        digits[count] = 48u8
        count += 1usize
    }
    if negative { try str.push_byte(b, 45u8) }
    var at = count
    while at > 0usize {
        at -= 1usize
        if at + 1usize == usize(value.scale) { try str.push_byte(b, 46u8) }
        try str.push_byte(b, digits[at])
    }
    ret ok
}

fn to_i64(value: Decimal, rounding: Rounding) -> (i64, err) {
    let (whole, quantize_error) = quantize(value, 0u8, rounding)
    if quantize_error != ok { ret (0i64, quantize_error) }
    let c = whole.coefficient
    if c.high == 0i64 && c.low <= 9223372036854775807u64 { ret (i64(c.low), ok) }
    if c.high == -1i64 && c.low >= 9223372036854775808u64 { ret (i64(c.low), ok) }
    ret (0i64, Overflow)
}

fn from_i64(value: i64, scale: u8) -> (Decimal, err) {
    if scale > MAX_SCALE { ret (zero, Invalid) }
    var c: Coefficient = zero
    c.low = u64(value)
    c.high = 0i64
    if value < 0i64 { c.high = -1i64 }
    var out: Decimal = zero
    out.coefficient = c
    out.scale = 0u8
    let (scaled, scale_error) = quantize(out, scale, .TowardZero)
    ret (scaled, scale_error)
}
