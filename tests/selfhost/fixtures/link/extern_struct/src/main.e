// Structs and unions by value across `extern fn` (D1675), against functions a C
// compiler built: every size Win64 passes as bits or by a copy's address, every System V
// class pair, the MEMORY class, a pair that no longer fits in the registers left, a
// struct in a variadic's `...`, and results in registers and through a hidden pointer.
// Until D1675 an aggregate crossed as neper passes one to itself, by address, and came
// back through a slot the callee was never told about. `back` is the other direction
// (D1676): C calling neper's `@cc` functions, and calls through `extern fn` types.
use back
use cabi
use plat

error ArgumentBits
error ArgumentPair
error ArgumentMemory
error Crowded
error Variadic
error ResultBits
error ResultPair
error ResultMemory
error InAndOut
error Protocol
error Platform
error CalledByC
error ReturnedToC
error CalledByNeper

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn hash_of[T: type](v: T) -> u64 {
    ret T.hash(v)
}

// One eightbyte, or Win64's 1, 2, 4 and 8 bytes: the bits in one register.
fn arguments_in_one() -> bool {
    let b1 = cabi.byte_in(cabi.Byte { a: 200u8 })
    if b1 != 200i64 { ret false }
    let b2 = cabi.short_in(cabi.Short { a: -300i16 })
    if b2 != -300i64 { ret false }
    let b3 = cabi.triple_in(cabi.Triple { a: 1u8, b: 2u8, c: 3u8 })
    if b3 != 197121i64 { ret false }
    let b4 = cabi.single_in(cabi.Single { a: 2.5f32 })
    if b4 != 2.5f64 { ret false }
    let pair = cabi.pair_in(cabi.Pair { x: -3i32, y: 7i32 })
    if pair != -2993i64 { ret false }
    let pairf = cabi.floats_in(cabi.Floats { x: 1.5f32, y: 2.25f32 })
    if pairf != 17.25f64 { ret false }
    var n: cabi.Num = zero
    n.i = -42i64
    ret cabi.num_in(n) == -42i64
}

// Two eightbytes in each class pair; Win64 passes each as a copy's address.
fn arguments_in_two() -> bool {
    let i2 = cabi.longs_in(cabi.Longs { a: 100000000000i64, b: 7i64 })
    if i2 != 299999999993i64 { ret false }
    let di = cabi.double_int_in(cabi.DoubleInt { d: 1.25f64, i: 3i64 })
    if di != 5.5f64 { ret false }
    let id = cabi.int_double_in(cabi.IntDouble { i: 3i64, d: 1.25f64 })
    if id != 7.25f64 { ret false }
    let d2 = cabi.doubles_in(cabi.Doubles { x: 1.5f64, y: 0.25f64 })
    if d2 != 15.25f64 { ret false }
    let f3 = cabi.three_floats_in(cabi.ThreeFloats { a: 1.5f32, b: 2.5f32, c: 3.5f32 })
    if f3 != 178.5f64 { ret false }
    var nest: cabi.Nest = zero
    nest.p = cabi.Pair { x: 1i32, y: 2i32 }
    nest.f[0usize] = 0.5f32
    nest.f[1usize] = 0.25f32
    ret cabi.nest_in(nest) == 1205.25f64
}

// Past sixteen bytes, or unaligned: on the stack by value, or a copy's address.
fn arguments_in_memory() -> bool {
    let big = cabi.Big { a: 7i64, b: 8i64, c: 9i64 }
    if cabi.big_in(big) != 789i64 { ret false }
    let packed = cabi.packed_in(cabi.Packed { tag: 5u8, value: -6i32 })
    if packed != 4994i64 { ret false }
    ret cabi.big_then(cabi.Big { a: 1i64, b: 2i64, c: 3i64 }, 4i64) == 64i64
}

// A pair that finds one register left goes to the stack whole, and the scalar after it
// still takes that register.
fn crowded() -> bool {
    let crowd = cabi.crowd(1i64, 2i64, 3i64, 4i64, 5i64, cabi.Longs { a: 6i64, b: 7i64 }, 8i64)
    if crowd != 204i64 { ret false }
    ret cabi.crowd_sse(1.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64, 7.0f64, cabi.Doubles { x: 8.0f64, y: 9.0f64 }, 10.0f64) == 385.0f64
}

fn results_in_one() -> bool {
    let b1 = cabi.byte_out(200u8)
    if b1.a != 200u8 { ret false }
    let b2 = cabi.short_out(-300i16)
    if b2.a != -300i16 { ret false }
    let b3 = cabi.triple_out(1u8, 2u8, 3u8)
    if b3.a != 1u8 || b3.b != 2u8 || b3.c != 3u8 { ret false }
    let b4 = cabi.single_out(2.5f32)
    if b4.a != 2.5f32 { ret false }
    let pair = cabi.pair_out(-3i32, 7i32)
    if pair.x != -3i32 || pair.y != 7i32 { ret false }
    let pairf = cabi.floats_out(1.5f32, 2.25f32)
    if pairf.x != 1.5f32 || pairf.y != 2.25f32 { ret false }
    let n = cabi.num_out(2.5f64)
    ret n.d == 2.5f64
}

fn results_in_two() -> bool {
    let i2 = cabi.longs_out(100000000000i64, -7i64)
    if i2.a != 100000000000i64 || i2.b != -7i64 { ret false }
    let di = cabi.double_int_out(1.25f64, -3i64)
    if di.d != 1.25f64 || di.i != -3i64 { ret false }
    let id = cabi.int_double_out(-3i64, 1.25f64)
    if id.i != -3i64 || id.d != 1.25f64 { ret false }
    let d2 = cabi.doubles_out(1.5f64, -0.25f64)
    if d2.x != 1.5f64 || d2.y != -0.25f64 { ret false }
    let f3 = cabi.three_floats_out(1.5f32, 2.5f32, 3.5f32)
    if f3.a != 1.5f32 || f3.b != 2.5f32 || f3.c != 3.5f32 { ret false }
    let nest = cabi.nest_out(1i32, -2i32, 0.5f32, 0.25f32)
    ret nest.p.x == 1i32 && nest.p.y == -2i32 && nest.f[0usize] == 0.5f32 && nest.f[1usize] == 0.25f32
}

fn results_in_memory() -> bool {
    let big = cabi.big_out(7i64, 8i64, 9i64)
    if big.a != 7i64 || big.b != 8i64 || big.c != 9i64 { ret false }
    let packed = cabi.packed_out(5u8, -6i32)
    ret packed.tag == 5u8 && packed.value == -6i32
}

fn in_and_out() -> bool {
    let swapped = cabi.doubles_swap(cabi.Doubles { x: 1.5f64, y: 2.5f64 })
    if swapped.x != 2.5f64 || swapped.y != 1.5f64 { ret false }
    let rotated = cabi.big_rotate(cabi.Big { a: 1i64, b: 2i64, c: 3i64 })
    ret rotated.a == 2i64 && rotated.b == 3i64 && rotated.c == 1i64
}

// `[N]Key`'s supplied `cmp` and `hash` call the key's declared ones per element.
fn protocol() -> bool {
    var xs: [2]cabi.Key = zero
    var ys: [2]cabi.Key = zero
    xs[0usize] = cabi.Key { k: 1i64 }
    xs[1usize] = cabi.Key { k: 5i64 }
    ys[0usize] = cabi.Key { k: 1i64 }
    ys[1usize] = cabi.Key { k: 7i64 }
    if order[[2]cabi.Key](xs, ys) != -1i32 { ret false }
    if order[[2]cabi.Key](ys, xs) != 1i32 { ret false }
    ys[1usize] = cabi.Key { k: 5i64 }
    if order[[2]cabi.Key](xs, ys) != 0i32 { ret false }
    var seven: [1]cabi.Key = zero
    var other_seven: [1]cabi.Key = zero
    var eight: [1]cabi.Key = zero
    seven[0usize] = cabi.Key { k: 7i64 }
    other_seven[0usize] = cabi.Key { k: 7i64 }
    eight[0usize] = cabi.Key { k: 8i64 }
    ret hash_of[[1]cabi.Key](seven) == hash_of[[1]cabi.Key](other_seven) && hash_of[[1]cabi.Key](seven) != hash_of[[1]cabi.Key](eight)
}

fn platform() -> bool {
    let absolute = plat.key_abs(plat.Key { k: -7i64 })
    if absolute != 7i64 { ret false }
    let division = plat.long_div(-17i64, 5i64)
    if division.quot != -3i64 || division.rem != -2i64 { ret false }
    ret plat.modulus(plat.Complex { x: 3.0f64, y: 4.0f64 }) == 5.0f64
}

fn main() -> err {
    if !arguments_in_one() { ret ArgumentBits }
    if !arguments_in_two() { ret ArgumentPair }
    if !arguments_in_memory() { ret ArgumentMemory }
    if !crowded() { ret Crowded }
    let sum = cabi.sum_longs(2i32, cabi.Longs { a: 1i64, b: 2i64 }, cabi.Longs { a: 3i64, b: 4i64 })
    if sum != 1234i64 { ret Variadic }
    if !results_in_one() { ret ResultBits }
    if !results_in_two() { ret ResultPair }
    if !results_in_memory() { ret ResultMemory }
    if !in_and_out() { ret InAndOut }
    if !protocol() { ret Protocol }
    if !platform() { ret Platform }
    if !back.called_by_c() { ret CalledByC }
    if !back.returned_to_c() { ret ReturnedToC }
    if !back.called_by_neper() { ret CalledByNeper }
    ret ok
}
