// IEEE 754 bit layouts: unpacking and packing the sign, biased exponent and
// mantissa fields of `f32` and `f64`, and conversion between `f32` and the
// two 16-bit formats, binary16 (`f16`, 5 exponent bits) and bfloat16 (8
// exponent bits, the top half of an `f32`). Conversions round to nearest,
// ties to even, keep the sign of zero, carry infinities across and turn any
// NaN into a quiet NaN of the target.

use e.mem

type Fields = struct { negative: bool, exponent: u32, mantissa: u64 }

// The raw fields of an `f64`: an 11-bit biased exponent and 52-bit mantissa.
fn unpack64(x: f64) -> Fields {
    let bits = mem.bitcast[u64](x)
    ret Fields { negative: (bits >> 63u32) != 0u64, exponent: u32((bits >> 52u32) & 2047u64), mantissa: bits & 4503599627370495u64 }
}

// The raw fields of an `f32`: an 8-bit biased exponent and 23-bit mantissa.
fn unpack32(x: f32) -> Fields {
    let bits = mem.bitcast[u32](x)
    ret Fields { negative: (bits >> 31u32) != 0u32, exponent: (bits >> 23u32) & 255u32, mantissa: u64(bits & 8388607u32) }
}

fn pack64(f: Fields) -> f64 {
    var bits = (u64(f.exponent & 2047u32) << 52u32) | (f.mantissa & 4503599627370495u64)
    if f.negative { bits |= 9223372036854775808u64 }
    ret mem.bitcast[f64](bits)
}

fn pack32(f: Fields) -> f32 {
    var bits = ((f.exponent & 255u32) << 23u32) | u32(f.mantissa & 8388607u64)
    if f.negative { bits |= 2147483648u32 }
    ret mem.bitcast[f32](bits)
}

// The unbiased exponent of an `f64`; a subnormal (or zero) answers -1022.
fn exponent_of(x: f64) -> i32 {
    let f = unpack64(x)
    if f.exponent == 0u32 { ret 0i32 - 1022i32 }
    ret i32(f.exponent) - 1023i32
}

// Round a `u32` bit pattern right by `shift` bits, to nearest, ties to even.
fn round_shift(bits: u32, shift: u32) -> u32 {
    if shift == 0u32 { ret bits }
    if shift > 31u32 {
        ret 0u32
    }
    let kept = bits >> shift
    let dropped = bits & ((1u32 << shift) - 1u32)
    let half = 1u32 << (shift - 1u32)
    if dropped > half || (dropped == half && (kept & 1u32) == 1u32) { ret kept + 1u32 }
    ret kept
}

// `f32` to binary16, rounding to nearest even; overflow is infinity, and a
// value under the smallest subnormal rounds to zero.
fn to_f16(x: f32) -> u16 {
    let bits = mem.bitcast[u32](x)
    let sign = u16((bits >> 16u32) & 32768u32)
    let exponent = (bits >> 23u32) & 255u32
    let mantissa = bits & 8388607u32
    if exponent == 255u32 {
        if mantissa != 0u32 { ret sign | 32256u16 }
        ret sign | 31744u16
    }
    // Rebias 127 -> 15.
    let unbiased = i32(exponent) - 127i32
    if unbiased > 15i32 { ret sign | 31744u16 }
    if unbiased >= 0i32 - 14i32 {
        // Normal in f16: 10 mantissa bits, rounded; a carry rolls into the exponent.
        let rounded = round_shift((u32(unbiased + 15i32) << 23u32) | mantissa, 13u32)
        if rounded >= 31744u32 { ret sign | 31744u16 }
        ret sign | u16(rounded)
    }
    // Subnormal in f16: the implicit bit joins the mantissa and the whole thing shifts.
    let shift = u32(0i32 - 14i32 - unbiased) + 13u32
    if shift > 24u32 { ret sign }
    ret sign | u16(round_shift(mantissa | 8388608u32, shift))
}

fn from_f16(h: u16) -> f32 {
    let sign = (u32(h) & 32768u32) << 16u32
    let exponent = (u32(h) >> 10u32) & 31u32
    var mantissa = u32(h) & 1023u32
    if exponent == 31u32 {
        if mantissa != 0u32 { ret mem.bitcast[f32](sign | 2143289344u32) }
        ret mem.bitcast[f32](sign | 2139095040u32)
    }
    if exponent == 0u32 {
        if mantissa == 0u32 { ret mem.bitcast[f32](sign) }
        // Normalise the subnormal: shift until the implicit bit is in place.
        var e = 113u32
        while (mantissa & 1024u32) == 0u32 {
            mantissa = mantissa << 1u32
            e -= 1u32
        }
        ret mem.bitcast[f32](sign | (e << 23u32) | ((mantissa & 1023u32) << 13u32))
    }
    ret mem.bitcast[f32](sign | ((exponent + 112u32) << 23u32) | (mantissa << 13u32))
}

// `f32` to bfloat16: the top sixteen bits, rounded to nearest even; a NaN
// keeps a set mantissa bit so it stays a NaN.
fn to_bf16(x: f32) -> u16 {
    let bits = mem.bitcast[u32](x)
    if (bits & 2139095040u32) == 2139095040u32 && (bits & 8388607u32) != 0u32 {
        ret u16(bits >> 16u32) | 64u16
    }
    ret u16(round_shift(bits, 16u32))
}

fn from_bf16(h: u16) -> f32 { ret mem.bitcast[f32](u32(h) << 16u32) }
