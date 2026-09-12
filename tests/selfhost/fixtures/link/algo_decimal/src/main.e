// `e.algo.decimal`: exact add, sub and mul over a 128-bit coefficient, division and
// quantization under every rounding mode, ties to even, comparison across scales,
// scientific parsing, the 2^127 edges, and the formatting of each. Every check has its
// own exit code.
use e.os
use e.mem
use e.str
use e.algo.decimal as dec

fn text_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn shown(a: *mem.Arena, v: dec.Decimal) -> str {
    let (initial, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret "" }
    var b = initial
    if dec.format(v, &b) != ok { ret "" }
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (x, e1) = dec.parse("123.450")
    let (y, e2) = dec.parse("-0.0055")
    if e1 != ok || e2 != ok || x.scale != 3u8 || y.scale != 4u8 { os.exit(1) }
    if !text_equal(shown(a, x), "123.450") || !text_equal(shown(a, y), "-0.0055") { os.exit(2) }
    let (sum, e3) = dec.add(x, y)
    if e3 != ok || !text_equal(shown(a, sum), "123.4445") { os.exit(3) }
    let (difference, e4) = dec.sub(x, y)
    if e4 != ok || !text_equal(shown(a, difference), "123.4555") { os.exit(4) }
    let (product, e5) = dec.mul(x, y)
    if e5 != ok || !text_equal(shown(a, product), "-0.6789750") { os.exit(5) }
    let n = dec.normalize(x)
    if n.scale != 2u8 || !text_equal(shown(a, n), "123.45") { os.exit(6) }
    let (third, e6) = dec.div(dec_from("1"), dec_from("3"), 5u8, .ToEven)
    if e6 != ok || !text_equal(shown(a, third), "0.33333") { os.exit(7) }
    let (two_thirds, e7) = dec.div(dec_from("2"), dec_from("3"), 5u8, .ToEven)
    if e7 != ok || !text_equal(shown(a, two_thirds), "0.66667") { os.exit(8) }
    let (neg, e8) = dec.div(dec_from("-7"), dec_from("2"), 0u8, .ToEven)
    let (neg_floor, e9) = dec.div(dec_from("-7"), dec_from("2"), 0u8, .Floor)
    let (neg_ceil, e10) = dec.div(dec_from("-7"), dec_from("2"), 0u8, .Ceiling)
    let (neg_away, e11) = dec.div(dec_from("-7"), dec_from("2"), 0u8, .AwayFromZero)
    let (neg_zero, e12) = dec.div(dec_from("-7"), dec_from("2"), 0u8, .TowardZero)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { os.exit(9) }
    if !text_equal(shown(a, neg), "-4") || !text_equal(shown(a, neg_floor), "-4") || !text_equal(shown(a, neg_ceil), "-3") || !text_equal(shown(a, neg_away), "-4") || !text_equal(shown(a, neg_zero), "-3") { os.exit(10) }
    let (even, _) = dec.div(dec_from("5"), dec_from("2"), 0u8, .ToEven)
    if !text_equal(shown(a, even), "2") { os.exit(11) }
    let (q1, e13) = dec.quantize(dec_from("2.675"), 2u8, .ToEven)
    let (q2, e14) = dec.quantize(dec_from("2.665"), 2u8, .ToEven)
    let (q3, e15) = dec.quantize(dec_from("2.6751"), 2u8, .ToEven)
    let (q4, e16) = dec.quantize(dec_from("1.5"), 4u8, .TowardZero)
    if e13 != ok || e14 != ok || e15 != ok || e16 != ok { os.exit(12) }
    if !text_equal(shown(a, q1), "2.68") || !text_equal(shown(a, q2), "2.66") || !text_equal(shown(a, q3), "2.68") || !text_equal(shown(a, q4), "1.5000") { os.exit(13) }
    if dec.compare(x, y) <= 0i32 || dec.compare(dec_from("1.50"), dec_from("1.5")) != 0i32 || dec.compare(dec_from("-2"), dec_from("-1")) >= 0i32 { os.exit(14) }
    let (i1, e17) = dec.to_i64(dec_from("-12.5"), .ToEven)
    let (i2, e18) = dec.to_i64(dec_from("12.5"), .AwayFromZero)
    if e17 != ok || i1 != -12i64 || e18 != ok || i2 != 13i64 { os.exit(15) }
    let (f, e19) = dec.from_i64(-42i64, 3u8)
    if e19 != ok || !text_equal(shown(a, f), "-42.000") { os.exit(16) }
    let (sci, e20) = dec.parse("1.5e3")
    let (sci2, e21) = dec.parse("15E-4")
    if e20 != ok || !text_equal(shown(a, sci), "1500") || e21 != ok || !text_equal(shown(a, sci2), "0.0015") { os.exit(17) }
    let (_, bad1) = dec.parse("1.2.3")
    let (_, bad2) = dec.parse("abc")
    let (_, bad3) = dec.parse("")
    if bad1 != dec.Invalid || bad2 != dec.Invalid || bad3 != dec.Invalid { os.exit(18) }
    // 128-bit coefficients: 10^37 * 10 overflows the scale space; 2^127 - 1 parses.
    let (big, e22) = dec.parse("170141183460469231731687303715884105727")
    if e22 != ok || !text_equal(shown(a, big), "170141183460469231731687303715884105727") { os.exit(19) }
    let (_, too_big) = dec.parse("170141183460469231731687303715884105728")
    if too_big != dec.Overflow { os.exit(20) }
    let (_, overflow) = dec.mul(big, dec_from("2"))
    if overflow != dec.Overflow { os.exit(21) }
    let (_, div_zero) = dec.div(x, dec_from("0"), 2u8, .ToEven)
    if div_zero != dec.Invalid { os.exit(22) }
    let (zero_value, _) = dec.parse("-0.000")
    if !text_equal(shown(a, zero_value), "0.000") || dec.compare(zero_value, dec_from("0")) != 0i32 { os.exit(23) }
    os.exit(0)
    ret ok
}

fn dec_from(text: str) -> dec.Decimal {
    let (value, _) = dec.parse(text)
    ret value
}
