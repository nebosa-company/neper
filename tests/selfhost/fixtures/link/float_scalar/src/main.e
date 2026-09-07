// Scalar `f32` and `f64` end to end: literals, the four arithmetic operators, unary
// minus, the six comparisons under IEEE rules, both conversion directions including
// the unsigned 64-bit edge, and float arguments and results across the calling
// convention. Float values live in general registers as raw bits between operations
// and move into xmm only for the operation itself, so this also pins that the bits
// survive a store, a load, a struct field and a call.

use e.mem

error Failed

type Point = struct {
    x: f64,
    y: f32,
    tag: i64,
}

// Enough arguments of each kind to reach past the point where the two conventions
// disagree: Win64 matches a float to the vector register in its own position, System
// V counts the two files separately.
fn mixed(a1: i64, x1: f64, a2: i64, x2: f64, a3: i64, x3: f64, a4: i64, x4: f64, a5: i64, x5: f64) -> f64 {
    let integers = a1 + a2 + a3 + a4 + a5
    ret f64(integers) + x1 + x2 + x3 + x4 + x5
}

fn scaled(v: f32, by: f32) -> f32 {
    ret v * by
}

fn total(values: []const f64) -> f64 {
    var sum = 0.0f64
    var at = 0usize
    while at < values.len {
        sum += values[at]
        at += 1usize
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Literals whose value is exact in binary, so the arithmetic and the conversion
    // have to agree to the bit.
    if 1.5f64 + 2.25f64 != 3.75f64 { ret Failed }
    if 1.5f64 * 2.25f64 != 3.375f64 { ret Failed }
    if 3.75f64 - 2.25f64 != 1.5f64 { ret Failed }
    if 1.0f64 / 4.0f64 != 0.25f64 { ret Failed }
    if -1.5f64 != 0.0f64 - 1.5f64 { ret Failed }
    if -0.0f64 != 0.0f64 { ret Failed }
    if 1e3f64 != 1000.0f64 { ret Failed }
    if 1_000.5f64 != 1000.5f64 { ret Failed }
    if 0.0f64 != 0.0f64 { ret Failed }

    // A decimal with no exact binary form has to round the way IEEE says, not the way
    // a naive scaling would: `0.1 + 0.2` is famously not `0.3`, and the literals must
    // land on exactly the values that make that true.
    if 0.1f64 + 0.2f64 == 0.3f64 { ret Failed }
    if 0.1f64 + 0.1f64 != 0.2f64 { ret Failed }
    if 0.5f64 + 0.25f64 != 0.75f64 { ret Failed }
    if i64(123.456f64 * 1000.0f64) != 123456i64 { ret Failed }

    // Both ends of the f64 range, and the two smallest subnormals, which is where a
    // conversion that scales through a power of ten loses its way.
    if 1.7976931348623157e308f64 <= 1.7976931348623156e308f64 { ret Failed }
    if 5e-324f64 <= 0.0f64 { ret Failed }
    if 5e-324f64 != 4.9e-324f64 { ret Failed }
    if 1e-323f64 != 5e-324f64 + 5e-324f64 { ret Failed }
    if 2.2250738585072014e-308f64 <= 0.0f64 { ret Failed }

    // The six comparisons, and IEEE's rule that every one of them is false against a
    // NaN except `!=`.
    let one = 1.0f64
    let two = 2.0f64
    let nan = 0.0f64 / 0.0f64
    let infinity = 1.0f64 / 0.0f64
    if !(one < two) || !(one <= two) || !(two > one) || !(two >= one) { ret Failed }
    if !(one <= one) || !(one >= one) || !(one == one) { ret Failed }
    if one > two || one >= two || two < one || two <= one || one != one { ret Failed }
    if nan == nan || nan < one || nan <= one || nan > one || nan >= one { ret Failed }
    if one < nan || one <= nan || one > nan || one >= nan { ret Failed }
    if !(nan != nan) { ret Failed }
    if !(infinity > 1.7976931348623157e308f64) { ret Failed }
    if !(-infinity < -1.7976931348623157e308f64) { ret Failed }

    // Conversions. Signed both ways, truncating toward zero.
    if f64(3i64) + f64(4i64) != 7.0f64 { ret Failed }
    if i64(7.9f64) != 7i64 { ret Failed }
    if i64(-7.9f64) != 0i64 - 7i64 { ret Failed }
    if i32(-300.7f64) != 0i32 - 300i32 { ret Failed }
    if u32(300.7f64) != 300u32 { ret Failed }

    // Unsigned 64-bit is the one range the signed instructions cannot express, so it
    // is converted through a halving that keeps the bit the shift would lose.
    if u64(f64(7u64)) != 7u64 { ret Failed }
    if f64(18446744073709551615u64) != 18446744073709551616.0f64 { ret Failed }
    if f64(9223372036854775809u64) != 9223372036854775808.0f64 { ret Failed }
    if f64(18446744073709550591u64) != 18446744073709549568.0f64 { ret Failed }
    if u64(9223372036854775808.0f64) != 9223372036854775808u64 { ret Failed }
    if u64(18446744073709549568.0f64) != 18446744073709549568u64 { ret Failed }
    if usize(f64(5usize)) != 5usize { ret Failed }

    // The two widths convert to each other, and `f32` keeps its own precision.
    if f64(1.5f32) != 1.5f64 { ret Failed }
    if f32(0.1f64) != 0.1f32 { ret Failed }
    if f64(0.1f32) == 0.1f64 { ret Failed }
    if 1.5f32 + 0.25f32 != 1.75f32 { ret Failed }
    if 3.4028235e38f32 <= 0.0f32 { ret Failed }
    if 1e-45f32 <= 0.0f32 { ret Failed }
    if i64(scaled(6.0f32, 7.0f32)) != 42i64 { ret Failed }

    // Across the calling convention, in both files at once.
    if mixed(1i64, 10.0f64, 2i64, 20.0f64, 3i64, 30.0f64, 4i64, 40.0f64, 5i64, 50.0f64) != 165.0f64 { ret Failed }

    // Through memory: a struct field of each width, and a slice walked by a callee.
    var p = Point { x: 2.5f64, y: 0.5f32, tag: 9i64 }
    if p.x != 2.5f64 || p.y != 0.5f32 || p.tag != 9i64 { ret Failed }
    p.x = p.x * 2.0f64
    p.y = p.y + 0.25f32
    if p.x != 5.0f64 || p.y != 0.75f32 || p.tag != 9i64 { ret Failed }

    var values: [4]f64 = zero
    values[0usize] = 1.5f64
    values[1usize] = 2.25f64
    values[2usize] = 0.25f64
    values[3usize] = -1.0f64
    if total(values[0usize..4usize]) != 3.0f64 { ret Failed }
    if total(values[0usize..0usize]) != 0.0f64 { ret Failed }

    let (heap, heap_error) = mem.alloc[f64](a, 2usize)
    if heap_error != ok { ret heap_error }
    heap[0usize] = 0.75f64
    heap[1usize] = 0.25f64
    if total(heap) != 1.0f64 { ret Failed }
    ret ok
}
