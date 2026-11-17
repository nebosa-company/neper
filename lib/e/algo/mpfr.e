// Rmpfr / MPFR style binary floating point of a chosen precision on the big integers of e.algo.bignum: a value is m * 2^e with m a signed integer of at most `prec` bits, and every operation is the exact result rounded to nearest, ties to even.
//
// Here: from a mantissa and exponent, add, sub, mul, div, sqrt, negation, comparison and the conversion to a pair of doubles (the value rounded to 53 bits and the remainder rounded to 53 bits).
//
// Not here: exp, log, the trigonometric and hyperbolic functions, gamma, zeta, erf, Bessel, the constants, the other rounding modes, infinities and NaN.

use e.algo.bignum as bn
use e.math
use e.mem

type Mp = struct { m: bn.Int, e: i64 }

fn pow2(a: *mem.Arena, k: usize) -> (bn.Int, err) {
    let (limbs, e1) = mem.alloc[u32](a, k / 32usize + 1usize)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < limbs.len {
        limbs[i] = 0u32
        i += 1usize
    }
    limbs[k / 32usize] = 1u32 << u32(k % 32usize)
    ret (bn.make_int(a, bn.Sign.Positive, limbs), ok)
}

fn shl(a: *mem.Arena, x: bn.Int, k: usize) -> (bn.Int, err) {
    if x.sign == bn.Sign.Zero || k == 0usize { ret (x, ok) }
    let (p, e) = pow2(a, k)
    if e != ok { ret (zero, e) }
    let (rt_, re_) = bn.int_mul(a, x, p)
    ret (rt_, re_)
}

fn magnitude(a: *mem.Arena, x: bn.Int) -> bn.Int {
    if x.sign == bn.Sign.Negative { ret bn.make_int(a, bn.Sign.Positive, x.limbs) }
    ret x
}

// m * 2^e rounded to prec bits, to nearest, ties to even
fn round_to(a: *mem.Arena, m: bn.Int, e: i64, prec: usize) -> (Mp, err) {
    if m.sign == bn.Sign.Zero { ret (Mp{ m: m, e: 0i64 }, ok) }
    let bits = bn.int_bits(m)
    if bits <= prec { ret (Mp{ m: m, e: e }, ok) }
    let shift = bits - prec
    let mag = magnitude(a, m)
    let (p, e1) = pow2(a, shift)
    if e1 != ok { ret (zero, e1) }
    let (q0, r, e2) = bn.int_divmod(a, mag, p)
    if e2 != ok { ret (zero, e2) }
    let (half, e3) = pow2(a, shift - 1usize)
    if e3 != ok { ret (zero, e3) }
    let c = bn.int_cmp(r, half)
    var q = q0
    var up = false
    if c > 0i32 { up = true }
    if c == 0i32 {
        if q0.sign != bn.Sign.Zero && (q0.limbs[0usize] & 1u32) == 1u32 { up = true }
    }
    var ee = e + i64(shift)
    if up {
        let (one, e4) = bn.int_from_i64(a, 1i64)
        if e4 != ok { ret (zero, e4) }
        let (q1, e5) = bn.int_add(a, q, one)
        if e5 != ok { ret (zero, e5) }
        q = q1
    }
    if bn.int_bits(q) > prec {
        let (two, e6) = bn.int_from_i64(a, 2i64)
        if e6 != ok { ret (zero, e6) }
        let (q2, rr, e7) = bn.int_divmod(a, q, two)
        if e7 != ok { ret (zero, e7) }
        q = q2
        ee += 1i64
    }
    if m.sign == bn.Sign.Negative { q = bn.make_int(a, bn.Sign.Negative, q.limbs) }
    ret (Mp{ m: q, e: ee }, ok)
}

fn from_parts(a: *mem.Arena, mant: i64, e: i64, prec: usize) -> (Mp, err) {
    let (m, e1) = bn.int_from_i64(a, mant)
    if e1 != ok { ret (zero, e1) }
    let (rt_, re_) = round_to(a, m, e, prec)
    ret (rt_, re_)
}

fn add(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero {
        let (rt2_, re2_) = round_to(a, y.m, y.e, prec)
        ret (rt2_, re2_)
    }
    if y.m.sign == bn.Sign.Zero {
        let (rt2_, re2_) = round_to(a, x.m, x.e, prec)
        ret (rt2_, re2_)
    }
    var e = x.e
    if y.e < e { e = y.e }
    let (xs, e1) = shl(a, x.m, usize(x.e - e))
    let (ys, e2) = shl(a, y.m, usize(y.e - e))
    if e1 != ok || e2 != ok { ret (zero, mem.Full) }
    let (s, e3) = bn.int_add(a, xs, ys)
    if e3 != ok { ret (zero, e3) }
    let (rt_, re_) = round_to(a, s, e, prec)
    ret (rt_, re_)
}

fn neg(a: *mem.Arena, x: Mp) -> Mp {
    if x.m.sign == bn.Sign.Zero { ret x }
    var s = bn.Sign.Negative
    if x.m.sign == bn.Sign.Negative { s = bn.Sign.Positive }
    ret Mp{ m: bn.make_int(a, s, x.m.limbs), e: x.e }
}

fn sub(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let (rt_, re_) = add(a, x, neg(a, y), prec)
    ret (rt_, re_)
}

fn mul(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let (p, e1) = bn.int_mul(a, x.m, y.m)
    if e1 != ok { ret (zero, e1) }
    let (rt_, re_) = round_to(a, p, x.e + y.e, prec)
    ret (rt_, re_)
}

fn div(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    if y.m.sign == bn.Sign.Zero { ret (zero, bn.DivideByZero) }
    if x.m.sign == bn.Sign.Zero { ret (x, ok) }
    let bx = bn.int_bits(x.m)
    let by = bn.int_bits(y.m)
    var s = 0usize
    if prec + 2usize + by > bx { s = prec + 2usize + by - bx }
    let (num, e1) = shl(a, magnitude(a, x.m), s)
    if e1 != ok { ret (zero, e1) }
    let (q, r, e2) = bn.int_divmod(a, num, magnitude(a, y.m))
    if e2 != ok { ret (zero, e2) }
    // q has at least prec + 2 bits; one more bit below it records whether the division was exact
    let (q2, e3) = shl(a, q, 1usize)
    if e3 != ok { ret (zero, e3) }
    var qq = q2
    if r.sign != bn.Sign.Zero {
        let (one, e4) = bn.int_from_i64(a, 1i64)
        if e4 != ok { ret (zero, e4) }
        let (q3, e5) = bn.int_add(a, q2, one)
        if e5 != ok { ret (zero, e5) }
        qq = q3
    }
    if x.m.sign != y.m.sign { qq = bn.make_int(a, bn.Sign.Negative, qq.limbs) }
    let (rt_, re_) = round_to(a, qq, x.e - y.e - i64(s) - 1i64, prec)
    ret (rt_, re_)
}

// floor(sqrt(n)) of a non-negative integer, by Newton's iteration
fn isqrt(a: *mem.Arena, n: bn.Int) -> (bn.Int, err) {
    if n.sign == bn.Sign.Zero { ret (n, ok) }
    let (x0, e0) = pow2(a, (bn.int_bits(n) + 1usize) / 2usize)
    if e0 != ok { ret (zero, e0) }
    let (two, e1) = bn.int_from_i64(a, 2i64)
    if e1 != ok { ret (zero, e1) }
    var x = x0
    var go = true
    while go {
        let (q, r, e2) = bn.int_divmod(a, n, x)
        if e2 != ok { ret (zero, e2) }
        let (s, e3) = bn.int_add(a, x, q)
        if e3 != ok { ret (zero, e3) }
        let (y, r2, e4) = bn.int_divmod(a, s, two)
        if e4 != ok { ret (zero, e4) }
        if bn.int_cmp(y, x) >= 0i32 {
            go = false
        } else {
            x = y
        }
    }
    ret (x, ok)
}

fn sqrt(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero { ret (x, ok) }
    var m = x.m
    var e = x.e
    if e % 2i64 != 0i64 {
        let (m2, e1) = shl(a, m, 1usize)
        if e1 != ok { ret (zero, e1) }
        m = m2
        e -= 1i64
    }
    let bits = bn.int_bits(m)
    var t = 0usize
    if 2usize * (prec + 2usize) > bits { t = (2usize * (prec + 2usize) - bits + 1usize) / 2usize }
    let (n, e2) = shl(a, m, 2usize * t)
    if e2 != ok { ret (zero, e2) }
    let (r, e3) = isqrt(a, n)
    if e3 != ok { ret (zero, e3) }
    let (r2, e4) = bn.int_mul(a, r, r)
    if e4 != ok { ret (zero, e4) }
    let (rr, e5) = shl(a, r, 1usize)
    if e5 != ok { ret (zero, e5) }
    var q = rr
    if bn.int_cmp(r2, n) != 0i32 {
        let (one, e6) = bn.int_from_i64(a, 1i64)
        if e6 != ok { ret (zero, e6) }
        let (q2, e7) = bn.int_add(a, rr, one)
        if e7 != ok { ret (zero, e7) }
        q = q2
    }
    let (rt_, re_) = round_to(a, q, (e - i64(2usize * t)) / 2i64 - 1i64, prec)
    ret (rt_, re_)
}

// the value as a double, rounded to nearest (53 bits): the integer mantissa is below 2^53 so the conversion is exact, the scaling by a power of two too
fn to_f64(a: *mem.Arena, x: Mp) -> f64 {
    let (r, e) = round_to(a, x.m, x.e, 53usize)
    if e != ok || r.m.sign == bn.Sign.Zero { ret 0.0f64 }
    var v = 0.0f64
    var i = r.m.limbs.len
    while i > 0usize {
        v = v * 4294967296.0f64 + f64(r.m.limbs[i - 1usize])
        i -= 1usize
    }
    if r.m.sign == bn.Sign.Negative { v = 0.0f64 - v }
    ret v * math.pow[f64](2.0f64, f64(r.e))
}

// (hi, lo): the value rounded to a double, and the remainder (exact in the arithmetic here) rounded to a double
fn to_pair(a: *mem.Arena, x: Mp) -> (f64, f64) {
    let hi = to_f64(a, x)
    // hi as an Mp: the mantissa is recovered by the same rounding
    let (r, e) = round_to(a, x.m, x.e, 53usize)
    if e != ok { ret (hi, 0.0f64) }
    let (d, e2) = sub(a, x, r, bn.int_bits(x.m) + 64usize)
    if e2 != ok { ret (hi, 0.0f64) }
    ret (hi, to_f64(a, d))
}
