// `mem.bitcast[T](x)` reads `x`'s bytes as a `T`, which is what makes a pun not need
// a `union`. The fixture pins that the bytes really are unchanged -- against bit
// patterns an independent implementation produced -- and that the four shapes work:
// scalar to scalar, scalar to aggregate, aggregate to scalar, and aggregate to
// aggregate. A scalar lives in a register and an aggregate is an address, so the two
// crossings are the ones that have to move anything.

use e.mem

error Failed

type Pair = struct {
    low: u32,
    high: u32,
}

type Bytes = struct {
    b: [8]u8,
}

type Kind = enum u8 {
    Zero,
    One,
    Two,
}

// The shape `e.str`'s float formatting needs: the sign, exponent and mantissa fields
// read straight out of the value.
fn exponent_field(v: f64) -> u64 {
    let bits = mem.bitcast[u64](v)
    let shifted = bits >> 52u64
    ret shifted & 2047u64
}

fn mantissa_field(v: f64) -> u64 {
    ret mem.bitcast[u64](v) & 4503599627370495u64
}

fn negative(v: f64) -> bool {
    ret mem.bitcast[u64](v) >> 63u64 == 1u64
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Scalar to scalar, against the patterns IEEE-754 gives.
    if mem.bitcast[u64](1.0f64) != 4607182418800017408u64 { ret Failed }
    if mem.bitcast[u64](0.1f64) != 4591870180066957722u64 { ret Failed }
    if mem.bitcast[u64](0.0f64) != 0u64 { ret Failed }
    if mem.bitcast[u64](-0.0f64) != 9223372036854775808u64 { ret Failed }
    if mem.bitcast[f64](4607182418800017408u64) != 1.0f64 { ret Failed }
    if mem.bitcast[u32](1.0f32) != 1065353216u32 { ret Failed }
    if mem.bitcast[u32](0.1f32) != 1036831949u32 { ret Failed }
    if mem.bitcast[f32](1065353216u32) != 1.0f32 { ret Failed }

    // Signedness is a storage convention, so a pun between the two widths of one size
    // changes how the register holds the value without changing a bit of it.
    if mem.bitcast[i32](2147483648u32) != 0i32 - 2147483648i32 { ret Failed }
    if mem.bitcast[u32](0i32 - 1i32) != 4294967295u32 { ret Failed }
    if mem.bitcast[i64](18446744073709551615u64) != 0i64 - 1i64 { ret Failed }
    if mem.bitcast[u64](0i64 - 1i64) != 18446744073709551615u64 { ret Failed }
    if mem.bitcast[i8](255u8) != 0i8 - 1i8 { ret Failed }
    if mem.bitcast[u8](0i8 - 1i8) != 255u8 { ret Failed }
    if mem.bitcast[i16](65535u16) != 0i16 - 1i16 { ret Failed }

    // A NaN keeps its payload: the round trip is the identity even where `==` is not.
    let nan = 0.0f64 / 0.0f64
    if mem.bitcast[f64](mem.bitcast[u64](nan)) == nan { ret Failed }
    if mem.bitcast[u64](mem.bitcast[f64](mem.bitcast[u64](nan))) != mem.bitcast[u64](nan) { ret Failed }
    let infinity = 1.0f64 / 0.0f64
    if mem.bitcast[u64](infinity) != 9218868437227405312u64 { ret Failed }

    // A `bool` and an enum are their bytes too.
    if mem.bitcast[u8](true) != 1u8 { ret Failed }
    if mem.bitcast[u8](false) != 0u8 { ret Failed }
    if mem.bitcast[bool](1u8) != true { ret Failed }
    if mem.bitcast[u8](Kind.Two) != 2u8 { ret Failed }
    if mem.bitcast[Kind](1u8) != Kind.One { ret Failed }

    // Scalar to aggregate: the value is spilled and the slot is read as the struct.
    let pair = mem.bitcast[Pair](1.0f64)
    if pair.low != 0u32 || pair.high != 1072693248u32 { ret Failed }
    let raw = mem.bitcast[Bytes](1.0f64)
    if raw.b[0usize] != 0u8 || raw.b[6usize] != 240u8 || raw.b[7usize] != 63u8 { ret Failed }
    let quad = mem.bitcast[[4]u8](1065353216u32)
    if quad[0usize] != 0u8 || quad[2usize] != 128u8 || quad[3usize] != 63u8 { ret Failed }

    // Aggregate to scalar, and back again unchanged.
    if mem.bitcast[f64](pair) != 1.0f64 { ret Failed }
    if mem.bitcast[f64](raw) != 1.0f64 { ret Failed }
    if mem.bitcast[u32](quad) != 1065353216u32 { ret Failed }
    if mem.bitcast[u64](mem.bitcast[Bytes](0.1f64)) != 4591870180066957722u64 { ret Failed }

    // Aggregate to aggregate: the same eight bytes read two ways.
    let regrouped = mem.bitcast[Pair](raw)
    if regrouped.low != 0u32 || regrouped.high != 1072693248u32 { ret Failed }
    let ungrouped = mem.bitcast[Bytes](pair)
    if ungrouped.b[7usize] != 63u8 { ret Failed }

    // The fields a float formatter reads, on values whose encoding is known.
    if exponent_field(1.0f64) != 1023u64 { ret Failed }
    if mantissa_field(1.0f64) != 0u64 { ret Failed }
    if negative(1.0f64) { ret Failed }
    if !negative(-1.0f64) { ret Failed }
    if !negative(-0.0f64) { ret Failed }
    if exponent_field(0.0f64) != 0u64 { ret Failed }
    if exponent_field(infinity) != 2047u64 { ret Failed }
    if mantissa_field(infinity) != 0u64 { ret Failed }
    if exponent_field(nan) != 2047u64 { ret Failed }
    if mantissa_field(nan) == 0u64 { ret Failed }
    // 5e-324 is the smallest subnormal: exponent field zero, mantissa one.
    if exponent_field(5e-324f64) != 0u64 { ret Failed }
    if mantissa_field(5e-324f64) != 1u64 { ret Failed }
    ret ok
}
