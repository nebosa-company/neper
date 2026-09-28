// The callee side (D1676): neper `@cc` functions taking and returning structs by value,
// called by C through a function pointer, by neper by name, and by neper through an
// `extern fn` type -- all three the C way. C's own functions are called through one too.
use cabi

@cc(c)
fn pair_back(s: cabi.Pair) -> i64 { ret 1000i64 * i64(s.x) + i64(s.y) }

@cc(c)
fn three_back(s: cabi.ThreeFloats) -> f64 { ret 100.0f64 * f64(s.a) + 10.0f64 * f64(s.b) + f64(s.c) }

@cc(c)
fn mixed_back(first: cabi.DoubleInt, second: cabi.IntDouble) -> f64 {
    ret 1000.0f64 * first.d + 100.0f64 * f64(first.i) + 10.0f64 * f64(second.i) + second.d
}

@cc(c)
fn big_back(s: cabi.Big, x: i64) -> i64 { ret 1000i64 * s.a + 100i64 * s.b + 10i64 * s.c + x }

@cc(c)
fn packed_back(s: cabi.Packed) -> i64 { ret 1000i64 * i64(s.tag) + i64(s.value) }

@cc(c)
fn crowd_back(a: i64, b: i64, c: i64, d: i64, e: i64, s: cabi.Longs, f: i64) -> i64 {
    ret a + 2i64 * b + 3i64 * c + 4i64 * d + 5i64 * e + 6i64 * s.a + 7i64 * s.b + 8i64 * f
}

@cc(c)
fn crowd_sse_back(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, s: cabi.Doubles, h: f64) -> f64 {
    ret a + 2.0f64 * b + 3.0f64 * c + 4.0f64 * d + 5.0f64 * e + 6.0f64 * f + 7.0f64 * g + 8.0f64 * s.x + 9.0f64 * s.y + 10.0f64 * h
}

@cc(c)
fn make_byte(a: u8) -> cabi.Byte { ret cabi.Byte { a: a } }

@cc(c)
fn make_pair(x: i32, y: i32) -> cabi.Pair { ret cabi.Pair { x: x, y: y } }

@cc(c)
fn make_longs(a: i64, b: i64) -> cabi.Longs { ret cabi.Longs { a: a, b: b } }

@cc(c)
fn make_double_int(d: f64, i: i64) -> cabi.DoubleInt { ret cabi.DoubleInt { d: d, i: i } }

@cc(c)
fn make_int_double(i: i64, d: f64) -> cabi.IntDouble { ret cabi.IntDouble { i: i, d: d } }

@cc(c)
fn make_three(a: f32, b: f32, c: f32) -> cabi.ThreeFloats { ret cabi.ThreeFloats { a: a, b: b, c: c } }

@cc(c)
fn make_big(a: i64, b: i64, c: i64) -> cabi.Big { ret cabi.Big { a: a, b: b, c: c } }

@cc(c)
fn negate_doubles(s: cabi.Doubles) -> cabi.Doubles { ret cabi.Doubles { x: 0.0f64 - s.x, y: 0.0f64 - s.y } }

// C calls each callback with the aggregates it built.
fn called_by_c() -> bool {
    if cabi.call_pair(pair_back, -3i32, 7i32) != -2993i64 { ret false }
    if cabi.call_three(three_back, 1.5f32, 2.5f32, 3.5f32) != 178.5f64 { ret false }
    if cabi.call_mixed(mixed_back, 1.5f64, 3i64) != 1831.5f64 { ret false }
    if cabi.call_big(big_back, 1i64, 2i64, 3i64, 4i64) != 1234i64 { ret false }
    if cabi.call_packed(packed_back, 5u8, -6i32) != 4994i64 { ret false }
    if cabi.call_crowd(crowd_back) != 204i64 { ret false }
    ret cabi.call_crowd_sse(crowd_sse_back) == 385.0f64
}

// C takes each aggregate back from a callback.
fn returned_to_c() -> bool {
    if cabi.take_byte(make_byte, 200u8) != 200i64 { ret false }
    if cabi.take_pair(make_pair, -3i32, 7i32) != -2993i64 { ret false }
    if cabi.take_longs(make_longs, 5i64, -7i64) != 43i64 { ret false }
    if cabi.take_double_int(make_double_int, 1.25f64, 3i64) != 5.5f64 { ret false }
    if cabi.take_int_double(make_int_double, 3i64, 1.25f64) != 7.25f64 { ret false }
    if cabi.take_three(make_three, 1.5f32, 2.5f32, 3.5f32) != 178.5f64 { ret false }
    if cabi.take_big(make_big, 7i64, 8i64, 9i64) != 789i64 { ret false }
    let mapped = cabi.map_doubles(negate_doubles, cabi.Doubles { x: 1.5f64, y: -2.5f64 })
    ret mapped.x == -1.5f64 && mapped.y == 2.5f64
}

// neper calls the same functions by name, and through `extern fn` values, both of its own
// and of C's.
fn called_by_neper() -> bool {
    let direct = pair_back(cabi.Pair { x: -3i32, y: 7i32 })
    if direct != -2993i64 { ret false }
    let made = make_big(1i64, 2i64, 3i64)
    if made.a != 1i64 || made.b != 2i64 || made.c != 3i64 { ret false }
    let own: cabi.PairBack = pair_back
    let through_own = own(cabi.Pair { x: 4i32, y: -5i32 })
    if through_own != 3995i64 { ret false }
    let own_maker: cabi.DoubleIntMaker = make_double_int
    let own_made = own_maker(0.5f64, -2i64)
    if own_made.d != 0.5f64 || own_made.i != -2i64 { ret false }
    let theirs = cabi.pair_in_pointer()
    let through_theirs = theirs(cabi.Pair { x: 4i32, y: -5i32 })
    if through_theirs != 3995i64 { ret false }
    let rotate = cabi.big_rotate_pointer()
    let rotated = rotate(cabi.Big { a: 1i64, b: 2i64, c: 3i64 })
    if rotated.a != 2i64 || rotated.b != 3i64 || rotated.c != 1i64 { ret false }
    let their_maker = cabi.double_int_out_pointer()
    let their_made = their_maker(0.5f64, -2i64)
    ret their_made.d == 0.5f64 && their_made.i == -2i64
}
