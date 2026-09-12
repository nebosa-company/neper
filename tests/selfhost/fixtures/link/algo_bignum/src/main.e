// `e.algo.bignum`: parse and format in three radices, the four operations against
// Python-computed answers, truncating division, gcd, i64 edges, and rationals in lowest
// terms. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.algo.bignum as big

fn text_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn formatted(a: *mem.Arena, v: big.Int, radix: u8) -> str {
    let (initial, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret "" }
    var b = initial
    if big.int_format(v, &b, radix) != ok { ret "" }
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (x, e1) = big.int_parse(a, "123456789012345678901234567890", 10u8)
    let (y, e2) = big.int_parse(a, "-987654321098765432109876543210", 10u8)
    if e1 != ok || e2 != ok { os.exit(1) }
    let (small0, _) = big.int_from_i64(a, 7i64)
    let f0 = formatted(a, small0, 10u8)
    if f0.len != 1usize { os.exit(60i32 + i32(f0.len)) }
    if f0[0] != 55u8 { os.exit(i32(f0[0])) }
    let (small1, _) = big.int_from_i64(a, 1234567i64)
    if !text_equal(formatted(a, small1, 10u8), "1234567") { os.exit(51) }
    let (p0, _) = big.int_parse(a, "1234567", 10u8)
    if big.int_cmp(p0, small1) != 0i32 { os.exit(52) }
    if !text_equal(formatted(a, x, 10u8), "123456789012345678901234567890") { os.exit(40) }
    if !text_equal(formatted(a, y, 10u8), "-987654321098765432109876543210") { os.exit(41) }
    let (small, _) = big.int_from_i64(a, 1234567i64)
    if !text_equal(formatted(a, small, 10u8), "1234567") { os.exit(42) }
    let (p1, _) = big.int_parse(a, "4294967296", 10u8)
    if !text_equal(formatted(a, p1, 10u8), "4294967296") || p1.limbs.len != 2usize || p1.limbs[0] != 0u32 || p1.limbs[1] != 1u32 { os.exit(43) }
    let (sum, e3) = big.int_add(a, x, y)
    if e3 != ok || !text_equal(formatted(a, sum, 10u8), "-864197532086419753208641975320") { os.exit(2) }
    let (difference, e4) = big.int_sub(a, x, y)
    if e4 != ok || !text_equal(formatted(a, difference, 10u8), "1111111110111111111011111111100") { os.exit(3) }
    let (product, e5) = big.int_mul(a, x, y)
    if e5 != ok || !text_equal(formatted(a, product, 10u8), "-121932631137021795226185032733622923332237463801111263526900") { os.exit(4) }
    let (quotient, remainder, e6) = big.int_divmod(a, y, x)
    if e6 != ok || !text_equal(formatted(a, quotient, 10u8), "-8") || !text_equal(formatted(a, remainder, 10u8), "-9000000000900000000090") { os.exit(5) }
    let (back, _, e7) = big.int_divmod(a, product, y)
    if e7 != ok || big.int_cmp(back, x) != 0i32 { os.exit(6) }
    let (hex, e8) = big.int_parse(a, "ffffffffffffffffffffffff", 16u8)
    if e8 != ok || !text_equal(formatted(a, hex, 16u8), "ffffffffffffffffffffffff") || !text_equal(formatted(a, hex, 10u8), "79228162514264337593543950335") { os.exit(7) }
    let (one, _) = big.int_from_i64(a, 1i64)
    let (power, e9) = big.int_add(a, hex, one)
    if e9 != ok || !text_equal(formatted(a, power, 2u8), "1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000") { os.exit(8) }
    let (neg, _) = big.int_from_i64(a, -9223372036854775807i64 - 1i64)
    if !text_equal(formatted(a, neg, 10u8), "-9223372036854775808") { os.exit(9) }
    let (g1, _) = big.int_parse(a, "462", 10u8)
    let (g2, _) = big.int_parse(a, "1071", 10u8)
    let (g, e10) = big.int_gcd(a, g1, g2)
    if e10 != ok || !text_equal(formatted(a, g, 10u8), "21") { os.exit(10) }
    let z = big.int_zero(a)
    let (_, _, by_zero) = big.int_divmod(a, x, z)
    let (_, bad) = big.int_parse(a, "12a", 10u8)
    if by_zero != big.DivideByZero || bad != big.Invalid || big.int_cmp(z, one) >= 0i32 || big.int_cmp(y, x) >= 0i32 { os.exit(11) }
    // Rationals: 1/3 + 1/6 = 1/2; (1/2) * (4/3) = 2/3; (2/3) / (2/3) = 1.
    let (three, _) = big.int_from_i64(a, 3i64)
    let (six, _) = big.int_from_i64(a, 6i64)
    let (third, r1) = big.rat_make(a, one, three)
    let (sixth, r2) = big.rat_make(a, one, six)
    if r1 != ok || r2 != ok { os.exit(12) }
    let (half, r3) = big.rat_add(a, third, sixth)
    let (builder0, _) = str.builder(a, 32usize)
    var hb = builder0
    if r3 != ok || big.rat_format(half, &hb) != ok || !text_equal(str.done(&hb), "1/2") { os.exit(13) }
    let (four, _) = big.int_from_i64(a, 4i64)
    let (four_thirds, _) = big.rat_make(a, four, three)
    let (two_thirds, r4) = big.rat_mul(a, half, four_thirds)
    let (builder1, _) = str.builder(a, 32usize)
    var tb = builder1
    if r4 != ok || big.rat_format(two_thirds, &tb) != ok || !text_equal(str.done(&tb), "2/3") { os.exit(14) }
    let (unit, r5) = big.rat_div(a, two_thirds, two_thirds)
    let (builder2, _) = str.builder(a, 32usize)
    var ub = builder2
    if r5 != ok || big.rat_format(unit, &ub) != ok || !text_equal(str.done(&ub), "1") { os.exit(15) }
    let (minus_third, _) = big.rat_sub(a, sixth, half)
    let (builder3, _) = str.builder(a, 32usize)
    var mb = builder3
    if big.rat_format(minus_third, &mb) != ok || !text_equal(str.done(&mb), "-1/3") { os.exit(16) }
    if big.rat_cmp(minus_third, sixth) >= 0i32 || big.rat_cmp(half, half) != 0i32 || big.rat_cmp(two_thirds, half) <= 0i32 { os.exit(17) }
    let (_, r6) = big.rat_make(a, one, z)
    if r6 != big.DivideByZero { os.exit(18) }
    os.exit(0)
    ret ok
}
