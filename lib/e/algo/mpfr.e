// Rmpfr / MPFR style binary floating point of a chosen precision on the big integers of e.algo.bignum: a value is m * 2^e with m a signed integer of at most `prec` bits, and every operation is the exact result rounded to nearest, ties to even.
//
// Here: from a mantissa and exponent, add, sub, mul, div, sqrt, exp, log, pow, sin, cos, tan, sinh, cosh, tanh, atan, asin, acos, asinh, acosh, atanh, lgamma, gamma, erf, zeta (real s > 1), besselJ of integer order, pi, log 2, Catalan and Euler constants, negation, comparison and the conversion to a pair of doubles (the value rounded to 53 bits and the remainder rounded to 53 bits).
//
// Not here: zeta, erf, Bessel, the constants, the other rounding modes, infinities and NaN.

use e.algo.bignum as bn
use e.math
use e.mem
use e.str

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

// m * 2^e rounded to prec bits; mode 0 to nearest with ties to even, 1 toward zero, 2 toward +inf, 3 toward -inf, 4 away from zero
fn round_to_m(a: *mem.Arena, m: bn.Int, e: i64, prec: usize, mode: usize) -> (Mp, err) {
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
    if mode == 0usize {
        if c > 0i32 { up = true }
        if c == 0i32 {
            if q0.sign != bn.Sign.Zero && (q0.limbs[0usize] & 1u32) == 1u32 { up = true }
        }
    } else if r.sign != bn.Sign.Zero {
        if mode == 4usize { up = true }
        if mode == 2usize && m.sign != bn.Sign.Negative { up = true }
        if mode == 3usize && m.sign == bn.Sign.Negative { up = true }
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

// m * 2^e rounded to prec bits, to nearest, ties to even
fn round_to(a: *mem.Arena, m: bn.Int, e: i64, prec: usize) -> (Mp, err) {
    let (rt_, re_) = round_to_m(a, m, e, prec, 0usize)
    ret (rt_, re_)
}

fn from_parts(a: *mem.Arena, mant: i64, e: i64, prec: usize) -> (Mp, err) {
    let (m, e1) = bn.int_from_i64(a, mant)
    if e1 != ok { ret (zero, e1) }
    let (rt_, re_) = round_to(a, m, e, prec)
    ret (rt_, re_)
}

fn add_m(a: *mem.Arena, x: Mp, y: Mp, prec: usize, mode: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero {
        let (rt2_, re2_) = round_to_m(a, y.m, y.e, prec, mode)
        ret (rt2_, re2_)
    }
    if y.m.sign == bn.Sign.Zero {
        let (rt2_, re2_) = round_to_m(a, x.m, x.e, prec, mode)
        ret (rt2_, re2_)
    }
    var e = x.e
    if y.e < e { e = y.e }
    let (xs, e1) = shl(a, x.m, usize(x.e - e))
    let (ys, e2) = shl(a, y.m, usize(y.e - e))
    if e1 != ok || e2 != ok { ret (zero, mem.Full) }
    let (s, e3) = bn.int_add(a, xs, ys)
    if e3 != ok { ret (zero, e3) }
    let (rt_, re_) = round_to_m(a, s, e, prec, mode)
    ret (rt_, re_)
}

fn add(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let (rt_, re_) = add_m(a, x, y, prec, 0usize)
    ret (rt_, re_)
}

fn neg(a: *mem.Arena, x: Mp) -> Mp {
    if x.m.sign == bn.Sign.Zero { ret x }
    var s = bn.Sign.Negative
    if x.m.sign == bn.Sign.Negative { s = bn.Sign.Positive }
    ret Mp{ m: bn.make_int(a, s, x.m.limbs), e: x.e }
}

fn sub_m(a: *mem.Arena, x: Mp, y: Mp, prec: usize, mode: usize) -> (Mp, err) {
    let (rt_, re_) = add_m(a, x, neg(a, y), prec, mode)
    ret (rt_, re_)
}

fn sub(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let (rt_, re_) = add(a, x, neg(a, y), prec)
    ret (rt_, re_)
}

fn mul_m(a: *mem.Arena, x: Mp, y: Mp, prec: usize, mode: usize) -> (Mp, err) {
    let (p, e1) = bn.int_mul(a, x.m, y.m)
    if e1 != ok { ret (zero, e1) }
    let (rt_, re_) = round_to_m(a, p, x.e + y.e, prec, mode)
    ret (rt_, re_)
}

fn mul(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let (rt_, re_) = mul_m(a, x, y, prec, 0usize)
    ret (rt_, re_)
}

fn div_m(a: *mem.Arena, x: Mp, y: Mp, prec: usize, mode: usize) -> (Mp, err) {
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
    let (rt_, re_) = round_to_m(a, qq, x.e - y.e - i64(s) - 1i64, prec, mode)
    ret (rt_, re_)
}

fn div(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let (rt_, re_) = div_m(a, x, y, prec, 0usize)
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

fn sqrt_m(a: *mem.Arena, x: Mp, prec: usize, mode: usize) -> (Mp, err) {
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
    let (rt_, re_) = round_to_m(a, q, (e - i64(2usize * t)) / 2i64 - 1i64, prec, mode)
    ret (rt_, re_)
}

fn sqrt(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    let (rt_, re_) = sqrt_m(a, x, prec, 0usize)
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

fn scale2(x: Mp, k: i64) -> Mp {
    if x.m.sign == bn.Sign.Zero { ret x }
    ret Mp{ m: x.m, e: x.e + k }
}

fn mag_exp(x: Mp) -> i64 { ret x.e + i64(bn.int_bits(x.m)) }

// ln 2 = 2 atanh(1/3) = 2 sum (1/3)^(2k+1) / (2k+1), to w bits
fn ln2(a: *mem.Arena, w: usize) -> (Mp, err) {
    let (one, e1) = from_parts(a, 1i64, 0i64, w)
    let (three, e2) = from_parts(a, 3i64, 0i64, w)
    if e1 != ok || e2 != ok { ret (zero, mem.Full) }
    let (z, e3) = div(a, one, three, w)
    if e3 != ok { ret (zero, e3) }
    let (z2, e4) = mul(a, z, z, w)
    if e4 != ok { ret (zero, e4) }
    var p = z
    var sum = z
    var k = 1i64
    var go = true
    while go {
        let (p2, e5) = mul(a, p, z2, w)
        if e5 != ok { ret (zero, e5) }
        p = p2
        let (d, e6) = from_parts(a, 2i64 * k + 1i64, 0i64, w)
        if e6 != ok { ret (zero, e6) }
        let (t, e7) = div(a, p, d, w)
        if e7 != ok { ret (zero, e7) }
        let (s2, e8) = add(a, sum, t, w)
        if e8 != ok { ret (zero, e8) }
        sum = s2
        if mag_exp(t) < mag_exp(sum) - i64(w) - 5i64 { go = false }
        k += 1i64
    }
    ret (scale2(sum, 1i64), ok)
}

// exp(x) to prec bits: x = k ln 2 + r, exp(r / 2^16) by its Taylor series and squared 16 times, then times 2^k; computed with 128 guard bits
fn exp(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero {
        let (o1, oe) = from_parts(a, 1i64, 0i64, prec)
        ret (o1, oe)
    }
    let w = prec + 128usize
    let (l2, e1) = ln2(a, w + 64usize)
    if e1 != ok { ret (zero, e1) }
    let xf = to_f64(a, x)
    let kf = math.floor[f64](xf / 0.6931471805599453f64 + 0.5f64)
    let k = i64(kf)
    let (kk, e2) = from_parts(a, k, 0i64, w + 64usize)
    if e2 != ok { ret (zero, e2) }
    let (kl, e3) = mul(a, kk, l2, w + 64usize)
    if e3 != ok { ret (zero, e3) }
    let (r, e4) = sub(a, x, kl, w)
    if e4 != ok { ret (zero, e4) }
    let r2 = scale2(r, 0i64 - 16i64)
    let (one, e5) = from_parts(a, 1i64, 0i64, w)
    if e5 != ok { ret (zero, e5) }
    var sum = one
    var term = one
    var i = 1i64
    var go = r2.m.sign != bn.Sign.Zero
    while go {
        let (t1, e6) = mul(a, term, r2, w)
        if e6 != ok { ret (zero, e6) }
        let (d, e7) = from_parts(a, i, 0i64, w)
        if e7 != ok { ret (zero, e7) }
        let (t2, e8) = div(a, t1, d, w)
        if e8 != ok { ret (zero, e8) }
        term = t2
        let (s2, e9) = add(a, sum, term, w)
        if e9 != ok { ret (zero, e9) }
        sum = s2
        if term.m.sign == bn.Sign.Zero || mag_exp(term) < 0i64 - i64(w) - 8i64 { go = false }
        i += 1i64
    }
    var q = 0usize
    while q < 16usize {
        let (s3, e10) = mul(a, sum, sum, w)
        if e10 != ok { ret (zero, e10) }
        sum = s3
        q += 1usize
    }
    let sc = scale2(sum, k)
    let (rt_, re_) = round_to(a, sc.m, sc.e, prec)
    ret (rt_, re_)
}

// log(x) for x > 0 to prec bits: x = f 2^k with f in [0.75, 1.5), ln f = 2 atanh((f - 1) / (f + 1)) by its series, plus k ln 2; computed with 128 guard bits
fn log(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign != bn.Sign.Positive { ret (zero, bn.Invalid) }
    let w = prec + 128usize
    let bits = i64(bn.int_bits(x.m))
    // x = m 2^e with m in [2^(bits-1), 2^bits): f = m / 2^bits in [0.5, 1), moved to [0.75, 1.5) by doubling when below 0.75
    var f = Mp{ m: x.m, e: 0i64 - bits }
    var k = x.e + bits
    // compare 4 m with 3 2^bits
    let (m4, e0) = shl(a, x.m, 2usize)
    let (t3, e00) = pow2(a, usize(bits))
    if e0 != ok || e00 != ok { ret (zero, mem.Full) }
    let (three, e01) = bn.int_from_i64(a, 3i64)
    if e01 != ok { ret (zero, e01) }
    let (t3b, e02) = bn.int_mul(a, t3, three)
    if e02 != ok { ret (zero, e02) }
    if bn.int_cmp(m4, t3b) < 0i32 {
        f = scale2(f, 1i64)
        k -= 1i64
    }
    let (one, e1) = from_parts(a, 1i64, 0i64, w)
    if e1 != ok { ret (zero, e1) }
    let (fm, e2) = sub(a, f, one, w + 64usize)
    let (fp, e3) = add(a, f, one, w + 64usize)
    if e2 != ok || e3 != ok { ret (zero, e2) }
    var lnf = f
    if fm.m.sign == bn.Sign.Zero {
        lnf = fm
    } else {
        let (z, e4) = div(a, fm, fp, w)
        if e4 != ok { ret (zero, e4) }
        let (z2, e5) = mul(a, z, z, w)
        if e5 != ok { ret (zero, e5) }
        var p = z
        var sum = z
        var j = 1i64
        var go = true
        while go {
            let (p2, e6) = mul(a, p, z2, w)
            if e6 != ok { ret (zero, e6) }
            p = p2
            let (d, e7) = from_parts(a, 2i64 * j + 1i64, 0i64, w)
            if e7 != ok { ret (zero, e7) }
            let (t, e8) = div(a, p, d, w)
            if e8 != ok { ret (zero, e8) }
            let (s2, e9) = add(a, sum, t, w)
            if e9 != ok { ret (zero, e9) }
            sum = s2
            if t.m.sign == bn.Sign.Zero || mag_exp(t) < mag_exp(sum) - i64(w) - 5i64 { go = false }
            j += 1i64
        }
        lnf = scale2(sum, 1i64)
    }
    var total = lnf
    if k != 0i64 {
        let (l2, e10) = ln2(a, w + 64usize)
        if e10 != ok { ret (zero, e10) }
        let (kk, e11) = from_parts(a, k, 0i64, w + 64usize)
        if e11 != ok { ret (zero, e11) }
        let (kl, e12) = mul(a, kk, l2, w + 64usize)
        if e12 != ok { ret (zero, e12) }
        let (s4, e13) = add(a, kl, lnf, w + 64usize)
        if e13 != ok { ret (zero, e13) }
        total = s4
    }
    let (rt_, re_) = round_to(a, total.m, total.e, prec)
    ret (rt_, re_)
}

// atan(1/n) = sum (-1)^k / ((2k + 1) n^(2k + 1)) for an integer n > 1, to w bits
fn atan_inv(a: *mem.Arena, n: i64, w: usize) -> (Mp, err) {
    let (one, e1) = from_parts(a, 1i64, 0i64, w)
    let (nn, e2) = from_parts(a, n, 0i64, w)
    if e1 != ok || e2 != ok { ret (zero, mem.Full) }
    let (z, e3) = div(a, one, nn, w)
    if e3 != ok { ret (zero, e3) }
    let (z2, e4) = mul(a, z, z, w)
    if e4 != ok { ret (zero, e4) }
    var p = z
    var sum = z
    var k = 1i64
    var go = true
    while go {
        let (p2, e5) = mul(a, p, z2, w)
        if e5 != ok { ret (zero, e5) }
        p = p2
        let (d, e6) = from_parts(a, 2i64 * k + 1i64, 0i64, w)
        if e6 != ok { ret (zero, e6) }
        let (t, e7) = div(a, p, d, w)
        if e7 != ok { ret (zero, e7) }
        var s2 = sum
        var e8 = ok
        if k % 2i64 == 1i64 {
            let (sa, ea) = sub(a, sum, t, w)
            s2 = sa
            e8 = ea
        } else {
            let (sa, ea) = add(a, sum, t, w)
            s2 = sa
            e8 = ea
        }
        if e8 != ok { ret (zero, e8) }
        sum = s2
        if mag_exp(t) < mag_exp(sum) - i64(w) - 5i64 { go = false }
        k += 1i64
    }
    ret (sum, ok)
}

// pi = 16 atan(1/5) - 4 atan(1/239) (Machin), to w bits
fn pi(a: *mem.Arena, w: usize) -> (Mp, err) {
    let (a5, e1) = atan_inv(a, 5i64, w + 8usize)
    let (a239, e2) = atan_inv(a, 239i64, w + 8usize)
    if e1 != ok || e2 != ok { ret (zero, mem.Full) }
    let (d, e3) = sub(a, scale2(a5, 4i64), scale2(a239, 2i64), w + 8usize)
    if e3 != ok { ret (zero, e3) }
    let (rt_, re_) = round_to(a, d.m, d.e, w)
    ret (rt_, re_)
}

// (sin x, cos x) to prec bits for moderate x: x = k pi / 2 + r with |r| <= pi / 4, the Taylor series of sin r and cos r, the quadrant from k mod 4; 160 guard bits plus the size of k
fn sin_cos(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, Mp, err) {
    var w = prec + 160usize
    let xf = to_f64(a, x)
    let kf = math.floor[f64](xf / 1.5707963267948966f64 + 0.5f64)
    let k = i64(kf)
    var kb = 0usize
    var ak = k
    if ak < 0i64 { ak = 0i64 - ak }
    while ak > 0i64 {
        kb += 1usize
        ak = ak / 2i64
    }
    w += kb
    let (p, e1) = pi(a, w + 64usize)
    if e1 != ok { ret (zero, zero, e1) }
    let hp = scale2(p, 0i64 - 1i64)
    let (kk, e2) = from_parts(a, k, 0i64, w + 64usize)
    if e2 != ok { ret (zero, zero, e2) }
    let (kp, e3) = mul(a, kk, hp, w + 64usize)
    if e3 != ok { ret (zero, zero, e3) }
    let (r, e4) = sub(a, x, kp, w)
    if e4 != ok { ret (zero, zero, e4) }
    let (r2, e5) = mul(a, r, r, w)
    if e5 != ok { ret (zero, zero, e5) }
    let (one, e6) = from_parts(a, 1i64, 0i64, w)
    if e6 != ok { ret (zero, zero, e6) }
    // sin r = r - r^3 / 3! + ..., cos r = 1 - r^2 / 2! + ...
    var s = r
    var c = one
    var ts = r
    var tc = one
    var i = 1i64
    var go = true
    while go {
        let (tc1, e7) = mul(a, tc, r2, w)
        let (d1, e8) = from_parts(a, (2i64 * i - 1i64) * (2i64 * i), 0i64, w)
        if e7 != ok || e8 != ok { ret (zero, zero, mem.Full) }
        let (tc2, e9) = div(a, tc1, d1, w)
        if e9 != ok { ret (zero, zero, e9) }
        tc = neg(a, tc2)
        let (c2, e10) = add(a, c, tc, w)
        if e10 != ok { ret (zero, zero, e10) }
        c = c2
        let (ts1, e11) = mul(a, ts, r2, w)
        let (d2, e12) = from_parts(a, (2i64 * i) * (2i64 * i + 1i64), 0i64, w)
        if e11 != ok || e12 != ok { ret (zero, zero, mem.Full) }
        let (ts2, e13) = div(a, ts1, d2, w)
        if e13 != ok { ret (zero, zero, e13) }
        ts = neg(a, ts2)
        let (s2, e14) = add(a, s, ts, w)
        if e14 != ok { ret (zero, zero, e14) }
        s = s2
        if (tc.m.sign == bn.Sign.Zero || mag_exp(tc) < 0i64 - i64(w) - 8i64) && (ts.m.sign == bn.Sign.Zero || mag_exp(ts) < 0i64 - i64(w) - 8i64) { go = false }
        i += 1i64
    }
    var q = k % 4i64
    if q < 0i64 { q += 4i64 }
    var sn = s
    var cs = c
    if q == 1i64 {
        sn = c
        cs = neg(a, s)
    } else if q == 2i64 {
        sn = neg(a, s)
        cs = neg(a, c)
    } else if q == 3i64 {
        sn = neg(a, c)
        cs = s
    }
    let (sr, e15) = round_to(a, sn.m, sn.e, prec)
    let (cr, e16) = round_to(a, cs.m, cs.e, prec)
    if e15 != ok || e16 != ok { ret (zero, zero, e15) }
    ret (sr, cr, ok)
}

// x^y for x > 0 as exp(y log x), the logarithm and the product carried with 192 guard bits and the size of the exponent
fn pow(a: *mem.Arena, x: Mp, y: Mp, prec: usize) -> (Mp, err) {
    let w = prec + 192usize
    let (l, e1) = log(a, x, w)
    if e1 != ok { ret (zero, e1) }
    let (t, e2) = mul(a, y, l, w)
    if e2 != ok { ret (zero, e2) }
    let (rt_, re_) = exp(a, t, prec)
    ret (rt_, re_)
}

// sinh, cosh and tanh from exp with enough guard bits for the cancellation of sinh near 0; kind 0 sinh, 1 cosh, 2 tanh
fn hyper(a: *mem.Arena, kind: usize, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero {
        if kind == 1usize {
            let (o, oe) = from_parts(a, 1i64, 0i64, prec)
            ret (o, oe)
        }
        ret (x, ok)
    }
    var extra = 0usize
    let me = mag_exp(x)
    if me < 0i64 { extra = usize(0i64 - me) }
    let w = prec + 128usize + 2usize * extra
    let (ep, e1) = exp(a, x, w)
    let (em, e2) = exp(a, neg(a, x), w)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    var num = ep
    var den = em
    var e3 = ok
    if kind == 0usize {
        let (d, ed) = sub(a, ep, em, w)
        num = scale2(d, 0i64 - 1i64)
        e3 = ed
    } else if kind == 1usize {
        let (d, ed) = add(a, ep, em, w)
        num = scale2(d, 0i64 - 1i64)
        e3 = ed
    } else {
        let (n2, en) = sub(a, ep, em, w)
        let (d2, ed) = add(a, ep, em, w)
        if en != ok || ed != ok { ret (zero, en) }
        let (q, eq) = div(a, n2, d2, w)
        num = q
        e3 = eq
    }
    if e3 != ok { ret (zero, e3) }
    let (rt_, re_) = round_to(a, num.m, num.e, prec)
    ret (rt_, re_)
}

// tan x = sin x / cos x from the guarded sine and cosine
fn tan(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    let w = prec + 64usize
    let (s, c, e1) = sin_cos(a, x, w)
    if e1 != ok { ret (zero, e1) }
    let (q, e2) = div(a, s, c, w)
    if e2 != ok { ret (zero, e2) }
    let (rt_, re_) = round_to(a, q.m, q.e, prec)
    ret (rt_, re_)
}

// atan x for moderate |x|: four halvings y -> y / (1 + sqrt(1 + y^2)), the series y - y^3 / 3 + .., then times 16
fn atan(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero { ret (x, ok) }
    let w = prec + 128usize
    var y = x
    var q = 0usize
    while q < 4usize {
        let (y2, e1) = mul(a, y, y, w)
        let (one, e2) = from_parts(a, 1i64, 0i64, w)
        if e1 != ok || e2 != ok { ret (zero, e1) }
        let (s1, e3) = add(a, one, y2, w)
        if e3 != ok { ret (zero, e3) }
        let (sq, e4) = sqrt(a, s1, w)
        if e4 != ok { ret (zero, e4) }
        let (den, e5) = add(a, one, sq, w)
        if e5 != ok { ret (zero, e5) }
        let (yn, e6) = div(a, y, den, w)
        if e6 != ok { ret (zero, e6) }
        y = yn
        q += 1usize
    }
    let (y2, e7) = mul(a, y, y, w)
    if e7 != ok { ret (zero, e7) }
    var p = y
    var sum = y
    var k = 1i64
    var go = true
    while go {
        let (p2, e8) = mul(a, p, y2, w)
        if e8 != ok { ret (zero, e8) }
        p = p2
        let (d, e9) = from_parts(a, 2i64 * k + 1i64, 0i64, w)
        if e9 != ok { ret (zero, e9) }
        let (t, e10) = div(a, p, d, w)
        if e10 != ok { ret (zero, e10) }
        var s2 = sum
        var e11 = ok
        if k % 2i64 == 1i64 {
            let (sa, ea) = sub(a, sum, t, w)
            s2 = sa
            e11 = ea
        } else {
            let (sa, ea) = add(a, sum, t, w)
            s2 = sa
            e11 = ea
        }
        if e11 != ok { ret (zero, e11) }
        sum = s2
        if mag_exp(t) < mag_exp(sum) - i64(w) - 5i64 { go = false }
        k += 1i64
    }
    let r = scale2(sum, 4i64)
    let (rt_, re_) = round_to(a, r.m, r.e, prec)
    ret (rt_, re_)
}

// kind 0 asin, 1 acos, 2 asinh, 3 acosh, 4 atanh: the logarithmic and arctangent identities with guard bits for the cancellation near 0 (and near 1 for acos); |x| < 1 for asin, acos and atanh, x > 1 for acosh
fn inverse(a: *mem.Arena, kind: usize, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero {
        if kind == 1usize {
            let (p, e0) = pi(a, prec + 8usize)
            if e0 != ok { ret (zero, e0) }
            let (rt0, re0) = round_to(a, p.m, p.e - 1i64, prec)
            ret (rt0, re0)
        }
        ret (x, ok)
    }
    var extra = 0usize
    let me = mag_exp(x)
    if me < 0i64 { extra = usize(0i64 - me) }
    let w = prec + 160usize + 2usize * extra
    let (one, e1) = from_parts(a, 1i64, 0i64, w)
    if e1 != ok { ret (zero, e1) }
    let (x2, e2) = mul(a, x, x, w)
    if e2 != ok { ret (zero, e2) }
    var res = x
    var er = ok
    if kind == 0usize || kind == 1usize {
        let (d, e3) = sub(a, one, x2, w)
        if e3 != ok { ret (zero, e3) }
        let (sq, e4) = sqrt(a, d, w)
        if e4 != ok { ret (zero, e4) }
        let (t, e5) = div(a, x, sq, w)
        if e5 != ok { ret (zero, e5) }
        let (at, e6) = atan(a, t, w)
        if e6 != ok { ret (zero, e6) }
        res = at
        if kind == 1usize {
            let (p, e7) = pi(a, w)
            if e7 != ok { ret (zero, e7) }
            let (c, e8) = sub(a, scale2(p, 0i64 - 1i64), at, w)
            res = c
            er = e8
        }
    } else if kind == 2usize || kind == 3usize {
        var inner = x2
        var e9 = ok
        if kind == 2usize {
            let (s, ea) = add(a, x2, one, w)
            inner = s
            e9 = ea
        } else {
            let (s, ea) = sub(a, x2, one, w)
            inner = s
            e9 = ea
        }
        if e9 != ok { ret (zero, e9) }
        let (sq, e10) = sqrt(a, inner, w)
        if e10 != ok { ret (zero, e10) }
        // asinh for negative x by oddness: use |x|
        var ax = x
        if x.m.sign == bn.Sign.Negative { ax = neg(a, x) }
        let (s2, e11) = add(a, ax, sq, w)
        if e11 != ok { ret (zero, e11) }
        let (lg, e12) = log(a, s2, w)
        if e12 != ok { ret (zero, e12) }
        res = lg
        if kind == 2usize && x.m.sign == bn.Sign.Negative { res = neg(a, lg) }
    } else {
        let (n1, e13) = add(a, one, x, w)
        let (d1, e14) = sub(a, one, x, w)
        if e13 != ok || e14 != ok { ret (zero, e13) }
        let (q, e15) = div(a, n1, d1, w)
        if e15 != ok { ret (zero, e15) }
        let (lg, e16) = log(a, q, w)
        if e16 != ok { ret (zero, e16) }
        res = scale2(lg, 0i64 - 1i64)
    }
    if er != ok { ret (zero, er) }
    let (rt_, re_) = round_to(a, res.m, res.e, prec)
    ret (rt_, re_)
}

// the Bernoulli numbers B_0 .. B_nmax as exact rationals (Akiyama-Tanigawa), index j holding B_j with B_1 = +1/2
fn bernoulli(a: *mem.Arena, nmax: usize) -> ([]bn.Rat, err) {
    let (res, e0) = mem.alloc[bn.Rat](a, nmax + 1usize)
    let (arr, e1) = mem.alloc[bn.Rat](a, nmax + 1usize)
    if e0 != ok || e1 != ok { ret (res, mem.Full) }
    let (one, e2) = bn.int_from_i64(a, 1i64)
    if e2 != ok { ret (res, e2) }
    var j = 0usize
    while j <= nmax {
        var i = j
        let (d, e3) = bn.int_from_i64(a, i64(j) + 1i64)
        if e3 != ok { ret (res, e3) }
        let (q, e4) = bn.rat_make(a, one, d)
        if e4 != ok { ret (res, e4) }
        arr[j] = q
        // the row below: A[m - 1] = m (A[m - 1] - A[m]) for m = j down to 1
        while i > 0usize {
            let (df, e5) = bn.rat_sub(a, arr[i - 1usize], arr[i])
            if e5 != ok { ret (res, e5) }
            let (mi, e6) = bn.int_from_i64(a, i64(i))
            if e6 != ok { ret (res, e6) }
            let (mr, e7) = bn.rat_make(a, mi, one)
            if e7 != ok { ret (res, e7) }
            let (pr, e8) = bn.rat_mul(a, mr, df)
            if e8 != ok { ret (res, e8) }
            arr[i - 1usize] = pr
            i -= 1usize
        }
        res[j] = arr[0usize]
        j += 1usize
    }
    ret (res, ok)
}

fn rat_to_mp(a: *mem.Arena, r: bn.Rat, w: usize) -> (Mp, err) {
    let (nm, e1) = round_to(a, r.num, 0i64, w + 64usize)
    let (dm, e2) = round_to(a, r.den, 0i64, w + 64usize)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let (q, e3) = div(a, nm, dm, w)
    ret (q, e3)
}

// lgamma(x) for x > 0 to prec bits: lgamma(x + n) by Stirling's series with exact Bernoulli numbers, minus log(x (x + 1) .. (x + n - 1)), n chosen so x + n exceeds the working precision
fn lgamma(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    let w = prec + 160usize
    let xf = to_f64(a, x)
    var n = 0i64
    if xf < f64(w) { n = i64(f64(w) - xf) + 1i64 }
    let (nn, e0) = from_parts(a, n, 0i64, w + 64usize)
    if e0 != ok { ret (zero, e0) }
    let (z, e1) = add(a, x, nn, w + 64usize)
    if e1 != ok { ret (zero, e1) }
    // the product x (x + 1) .. (x + n - 1)
    let (one, e2) = from_parts(a, 1i64, 0i64, w + 64usize)
    if e2 != ok { ret (zero, e2) }
    var prod = one
    var i = 0i64
    while i < n {
        let (ii, e3) = from_parts(a, i, 0i64, w + 64usize)
        let (xi, e4) = add(a, x, ii, w + 64usize)
        if e3 != ok || e4 != ok { ret (zero, mem.Full) }
        let (p2, e5) = mul(a, prod, xi, w + 64usize)
        if e5 != ok { ret (zero, e5) }
        prod = p2
        i += 1i64
    }
    let (lnp, e6) = log(a, prod, w)
    if e6 != ok { ret (zero, e6) }
    let (lz, e7) = log(a, z, w)
    if e7 != ok { ret (zero, e7) }
    let (half, e8) = from_parts(a, 1i64, 0i64 - 1i64, w)
    if e8 != ok { ret (zero, e8) }
    let (zh, e9) = sub(a, z, half, w)
    if e9 != ok { ret (zero, e9) }
    let (t1, e10) = mul(a, zh, lz, w)
    if e10 != ok { ret (zero, e10) }
    let (t2, e11) = sub(a, t1, z, w)
    if e11 != ok { ret (zero, e11) }
    let (p, e12) = pi(a, w)
    if e12 != ok { ret (zero, e12) }
    let (l2p, e13) = log(a, scale2(p, 1i64), w)
    if e13 != ok { ret (zero, e13) }
    let (t3, e14) = add(a, t2, scale2(l2p, 0i64 - 1i64), w)
    if e14 != ok { ret (zero, e14) }
    // the correction series sum B_2k / (2k (2k - 1) z^(2k - 1))
    var kmax = w / 8usize + 10usize
    let (bs, e15) = bernoulli(a, 2usize * kmax)
    if e15 != ok { ret (zero, e15) }
    let (zi, e16) = div(a, one, z, w)
    if e16 != ok { ret (zero, e16) }
    let (zi2, e17) = mul(a, zi, zi, w)
    if e17 != ok { ret (zero, e17) }
    var zp = zi
    var sum = t3
    var k = 1usize
    var go = true
    while go && k <= kmax {
        let (bm, e18) = rat_to_mp(a, bs[2usize * k], w)
        if e18 != ok { ret (zero, e18) }
        let (d, e19) = from_parts(a, i64(2usize * k) * (i64(2usize * k) - 1i64), 0i64, w)
        if e19 != ok { ret (zero, e19) }
        let (b1, e20) = mul(a, bm, zp, w)
        if e20 != ok { ret (zero, e20) }
        let (term, e21) = div(a, b1, d, w)
        if e21 != ok { ret (zero, e21) }
        let (s2, e22) = add(a, sum, term, w)
        if e22 != ok { ret (zero, e22) }
        sum = s2
        if term.m.sign == bn.Sign.Zero || mag_exp(term) < 0i64 - i64(w) - 8i64 { go = false }
        let (zp2, e23) = mul(a, zp, zi2, w)
        if e23 != ok { ret (zero, e23) }
        zp = zp2
        k += 1usize
    }
    let (res, e24) = sub(a, sum, lnp, w)
    if e24 != ok { ret (zero, e24) }
    let (rt_, re_) = round_to(a, res.m, res.e, prec)
    ret (rt_, re_)
}

// gamma(x) for x > 0 as exp(lgamma(x)) with the logarithm carried at prec + 64 + the size of the exponent
fn gamma(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    let (lg, e1) = lgamma(a, x, prec + 96usize)
    if e1 != ok { ret (zero, e1) }
    let (rt_, re_) = exp(a, lg, prec)
    ret (rt_, re_)
}

// log 2 to prec bits
fn const_log2(a: *mem.Arena, prec: usize) -> (Mp, err) {
    let (l, e1) = ln2(a, prec + 64usize)
    if e1 != ok { ret (zero, e1) }
    let (rt_, re_) = round_to(a, l.m, l.e, prec)
    ret (rt_, re_)
}

// Catalan's constant G = pi / 8 log(2 + sqrt 3) + 3 / 8 sum_{n >= 0} 1 / ((2n + 1)^2 binomial(2n, n)), to prec bits
fn const_catalan(a: *mem.Arena, prec: usize) -> (Mp, err) {
    let w = prec + 96usize
    let (p, e1) = pi(a, w)
    let (two, e2) = from_parts(a, 2i64, 0i64, w)
    let (three, e3) = from_parts(a, 3i64, 0i64, w)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, mem.Full) }
    let (s3, e4) = sqrt(a, three, w)
    if e4 != ok { ret (zero, e4) }
    let (t, e5) = add(a, two, s3, w)
    if e5 != ok { ret (zero, e5) }
    let (lg, e6) = log(a, t, w)
    if e6 != ok { ret (zero, e6) }
    let (pl, e7) = mul(a, p, lg, w)
    if e7 != ok { ret (zero, e7) }
    let first = scale2(pl, 0i64 - 3i64)
    // the series: term_n = 1 / ((2n + 1)^2 C(2n, n)), C(2n + 2, n + 1) = C(2n, n) 2 (2n + 1) / (n + 1) kept as a running reciprocal
    let (one, e8) = from_parts(a, 1i64, 0i64, w)
    if e8 != ok { ret (zero, e8) }
    var rc = one
    var sum = one
    var n = 1i64
    var go = true
    while go {
        // 1 / C(2n, n) = 1 / C(2n - 2, n - 1) * n / (2 (2n - 1))
        let (num, e9) = from_parts(a, n, 0i64, w)
        let (den, e10) = from_parts(a, 2i64 * (2i64 * n - 1i64), 0i64, w)
        if e9 != ok || e10 != ok { ret (zero, mem.Full) }
        let (r1, e11) = mul(a, rc, num, w)
        if e11 != ok { ret (zero, e11) }
        let (r2, e12) = div(a, r1, den, w)
        if e12 != ok { ret (zero, e12) }
        rc = r2
        let (sq, e13) = from_parts(a, (2i64 * n + 1i64) * (2i64 * n + 1i64), 0i64, w)
        if e13 != ok { ret (zero, e13) }
        let (tn, e14) = div(a, rc, sq, w)
        if e14 != ok { ret (zero, e14) }
        let (s2, e15) = add(a, sum, tn, w)
        if e15 != ok { ret (zero, e15) }
        sum = s2
        if mag_exp(tn) < 0i64 - i64(w) - 8i64 { go = false }
        n += 1i64
    }
    // 3 / 8 sum = (3 sum) / 8
    let (s3x, e16) = mul(a, three, sum, w)
    if e16 != ok { ret (zero, e16) }
    let (tot, e17) = add(a, first, scale2(s3x, 0i64 - 3i64), w)
    if e17 != ok { ret (zero, e17) }
    let (rt_, re_) = round_to(a, tot.m, tot.e, prec)
    ret (rt_, re_)
}

// erf x = 2 / sqrt(pi) sum (-1)^n x^(2n + 1) / (n! (2n + 1)) for moderate |x|, with guard bits for the cancellation (about x^2 / ln 2 bits)
fn erf(a: *mem.Arena, x: Mp, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero { ret (x, ok) }
    let xf = to_f64(a, x)
    let extra = usize(xf * xf * 1.45f64) + 8usize
    let me = mag_exp(x)
    var small = 0usize
    if me < 0i64 { small = usize(0i64 - me) }
    let w = prec + 128usize + extra + small
    let (x2, e1) = mul(a, x, x, w)
    if e1 != ok { ret (zero, e1) }
    var term = x
    var sum = x
    var n = 1i64
    var go = true
    while go {
        let (t1, e2) = mul(a, term, x2, w)
        let (d, e3) = from_parts(a, n, 0i64, w)
        if e2 != ok || e3 != ok { ret (zero, mem.Full) }
        let (t2, e4) = div(a, t1, d, w)
        if e4 != ok { ret (zero, e4) }
        term = neg(a, t2)
        let (dd, e5) = from_parts(a, 2i64 * n + 1i64, 0i64, w)
        if e5 != ok { ret (zero, e5) }
        let (ct, e6) = div(a, term, dd, w)
        if e6 != ok { ret (zero, e6) }
        let (s2, e7) = add(a, sum, ct, w)
        if e7 != ok { ret (zero, e7) }
        sum = s2
        if mag_exp(ct) < mag_exp(sum) - i64(w) - 5i64 && n > 2i64 { go = false }
        n += 1i64
    }
    let (p, e8) = pi(a, w)
    if e8 != ok { ret (zero, e8) }
    let (sp, e9) = sqrt(a, p, w)
    if e9 != ok { ret (zero, e9) }
    let (q, e10) = div(a, sum, sp, w)
    if e10 != ok { ret (zero, e10) }
    let r = scale2(q, 1i64)
    let (rt_, re_) = round_to(a, r.m, r.e, prec)
    ret (rt_, re_)
}

fn int_mp(a: *mem.Arena, v: bn.Int, w: usize) -> (Mp, err) {
    let (rt_, re_) = round_to(a, v, 0i64, w)
    ret (rt_, re_)
}

// zeta(s) for real s > 1 by Borwein's algorithm: n = 0.4 w + 4 terms, d_k = sum_{i <= k} t_i with t_0 = 1 and t_{i+1} = t_i 4 (n + i)(n - i) / ((2i + 1)(2i + 2)) exact integers,
// zeta = -1 / (d_n (1 - 2^(1 - s))) sum_{k < n} (-1)^k (d_k - d_n) (k + 1)^(-s)
fn zeta(a: *mem.Arena, s: Mp, prec: usize) -> (Mp, err) {
    let w = prec + 96usize
    let n = (w * 4usize) / 10usize + 4usize
    let (d, e0) = mem.alloc[bn.Int](a, n + 1usize)
    if e0 != ok { ret (zero, e0) }
    let (t0, e1) = bn.int_from_i64(a, 1i64)
    if e1 != ok { ret (zero, e1) }
    var t = t0
    var acc = t0
    d[0usize] = acc
    var i = 0usize
    while i < n {
        let (f, e2) = bn.int_from_i64(a, 4i64 * (i64(n) + i64(i)) * (i64(n) - i64(i)))
        let (g, e3) = bn.int_from_i64(a, (2i64 * i64(i) + 1i64) * (2i64 * i64(i) + 2i64))
        if e2 != ok || e3 != ok { ret (zero, mem.Full) }
        let (tf, e4) = bn.int_mul(a, t, f)
        if e4 != ok { ret (zero, e4) }
        let (tq, tr, e5) = bn.int_divmod(a, tf, g)
        if e5 != ok { ret (zero, e5) }
        t = tq
        let (ac2, e6) = bn.int_add(a, acc, t)
        if e6 != ok { ret (zero, e6) }
        acc = ac2
        d[i + 1usize] = acc
        i += 1usize
    }
    let dn = d[n]
    let (one, e7) = from_parts(a, 1i64, 0i64, w)
    let (l2, e8) = ln2(a, w + 32usize)
    if e7 != ok || e8 != ok { ret (zero, mem.Full) }
    let (oms, e9) = sub(a, one, s, w)
    if e9 != ok { ret (zero, e9) }
    let (lt, e10) = mul(a, oms, l2, w)
    if e10 != ok { ret (zero, e10) }
    let (p2, e11) = exp(a, lt, w)
    if e11 != ok { ret (zero, e11) }
    let (den1, e12) = sub(a, one, p2, w)
    if e12 != ok { ret (zero, e12) }
    var sum = scale2(one, 0i64 - 4000i64)
    sum = Mp{ m: bn.int_zero(a), e: 0i64 }
    var k = 0usize
    while k < n {
        let (diff, e13) = bn.int_sub(a, d[k], dn)
        if e13 != ok { ret (zero, e13) }
        let (dm, e14) = int_mp(a, diff, w + 64usize)
        if e14 != ok { ret (zero, e14) }
        let (kp, e15) = from_parts(a, i64(k) + 1i64, 0i64, w)
        if e15 != ok { ret (zero, e15) }
        let (lk, e16) = log(a, kp, w)
        if e16 != ok { ret (zero, e16) }
        let (sl, e17) = mul(a, s, lk, w)
        if e17 != ok { ret (zero, e17) }
        let (pw, e18) = exp(a, neg(a, sl), w)
        if e18 != ok { ret (zero, e18) }
        let (term, e19) = mul(a, dm, pw, w + 64usize)
        if e19 != ok { ret (zero, e19) }
        var s2 = sum
        var e20 = ok
        if k % 2usize == 0usize {
            let (sa, ea) = add(a, sum, term, w + 64usize)
            s2 = sa
            e20 = ea
        } else {
            let (sa, ea) = sub(a, sum, term, w + 64usize)
            s2 = sa
            e20 = ea
        }
        if e20 != ok { ret (zero, e20) }
        sum = s2
        k += 1usize
    }
    let (dnm, e21) = int_mp(a, dn, w + 64usize)
    if e21 != ok { ret (zero, e21) }
    let (dd, e22) = mul(a, dnm, den1, w + 64usize)
    if e22 != ok { ret (zero, e22) }
    let (q, e23) = div(a, sum, dd, w)
    if e23 != ok { ret (zero, e23) }
    let r = neg(a, q)
    let (rt_, re_) = round_to(a, r.m, r.e, prec)
    ret (rt_, re_)
}

// besselJ(x, n) for an integer order n >= 0: sum (-1)^k (x / 2)^(2k + n) / (k! (k + n)!), with guard bits for the cancellation (about x^2 / 2 bits plus the leading zeros)
fn bessel_j(a: *mem.Arena, x: Mp, n: usize, prec: usize) -> (Mp, err) {
    if x.m.sign == bn.Sign.Zero {
        if n == 0usize {
            let (o, oe) = from_parts(a, 1i64, 0i64, prec)
            ret (o, oe)
        }
        ret (x, ok)
    }
    let xf = to_f64(a, x)
    let extra = usize(xf * xf * 0.75f64) + 16usize
    let me = mag_exp(x)
    var small = 0usize
    if me < 0i64 { small = usize(0i64 - me) * (n + 1usize) }
    let w = prec + 128usize + extra + small
    let h = scale2(x, 0i64 - 1i64)
    let (h2, e1) = mul(a, h, h, w)
    if e1 != ok { ret (zero, e1) }
    // the first term (x / 2)^n / n!
    let (one, e2) = from_parts(a, 1i64, 0i64, w)
    if e2 != ok { ret (zero, e2) }
    var term = one
    var i = 1usize
    while i <= n {
        let (hi_, e3) = mul(a, term, h, w)
        let (d, e4) = from_parts(a, i64(i), 0i64, w)
        if e3 != ok || e4 != ok { ret (zero, mem.Full) }
        let (t2, e5) = div(a, hi_, d, w)
        if e5 != ok { ret (zero, e5) }
        term = t2
        i += 1usize
    }
    var sum = term
    var k = 1i64
    var go = true
    while go {
        let (t1, e6) = mul(a, term, h2, w)
        let (d, e7) = from_parts(a, k * (k + i64(n)), 0i64, w)
        if e6 != ok || e7 != ok { ret (zero, mem.Full) }
        let (t2, e8) = div(a, t1, d, w)
        if e8 != ok { ret (zero, e8) }
        term = neg(a, t2)
        let (s2, e9) = add(a, sum, term, w)
        if e9 != ok { ret (zero, e9) }
        sum = s2
        if term.m.sign == bn.Sign.Zero || (mag_exp(term) < mag_exp(sum) - i64(w) - 5i64 && k > 2i64) { go = false }
        k += 1i64
    }
    let (rt_, re_) = round_to(a, sum.m, sum.e, prec)
    ret (rt_, re_)
}

// Euler's constant by the Brent-McCann formula gamma = A(n) / B(n) - log n with B = sum (n^k / k!)^2, A = sum (n^k / k!)^2 H_k, H_k the harmonic numbers; the error is below exp(-4 n), so n = 0.18 w + 8 terms are enough
fn const_euler(a: *mem.Arena, prec: usize) -> (Mp, err) {
    let w = prec + 96usize
    let n = (w * 18usize) / 100usize + 8usize
    let (nm, e1) = from_parts(a, i64(n), 0i64, w)
    let (one, e2) = from_parts(a, 1i64, 0i64, w)
    if e1 != ok || e2 != ok { ret (zero, mem.Full) }
    var term = one
    var h = Mp{ m: bn.int_zero(a), e: 0i64 }
    var b = one
    var aa = Mp{ m: bn.int_zero(a), e: 0i64 }
    var k = 1i64
    while k <= i64(4 * n) + 8i64 {
        // term_k = term_{k - 1} * n / k, squared into the sums
        let (t1, e3) = mul(a, term, nm, w + 32usize)
        let (kk, e4) = from_parts(a, k, 0i64, w + 32usize)
        if e3 != ok || e4 != ok { ret (zero, mem.Full) }
        let (t2, e5) = div(a, t1, kk, w + 32usize)
        if e5 != ok { ret (zero, e5) }
        term = t2
        let (sq, e6) = mul(a, term, term, w + 32usize)
        if e6 != ok { ret (zero, e6) }
        let (inv, e7) = div(a, one, kk, w + 32usize)
        if e7 != ok { ret (zero, e7) }
        let (h2, e8) = add(a, h, inv, w + 32usize)
        if e8 != ok { ret (zero, e8) }
        h = h2
        let (b2, e9) = add(a, b, sq, w + 32usize)
        if e9 != ok { ret (zero, e9) }
        b = b2
        let (sh, e10) = mul(a, sq, h, w + 32usize)
        if e10 != ok { ret (zero, e10) }
        let (a2, e11) = add(a, aa, sh, w + 32usize)
        if e11 != ok { ret (zero, e11) }
        aa = a2
        k += 1i64
    }
    let (q, e12) = div(a, aa, b, w)
    if e12 != ok { ret (zero, e12) }
    let (ln, e13) = log(a, nm, w)
    if e13 != ok { ret (zero, e13) }
    let (r, e14) = sub(a, q, ln, w)
    if e14 != ok { ret (zero, e14) }
    let (rt_, re_) = round_to(a, r.m, r.e, prec)
    ret (rt_, re_)
}

fn int_pow(a: *mem.Arena, b: usize, k: usize) -> (bn.Int, err) {
    let (r0, e0) = bn.int_from_i64(a, 1i64)
    let (bb, e1) = bn.int_from_i64(a, i64(b))
    if e0 != ok || e1 != ok { ret (zero, mem.Full) }
    var r = r0
    var i = 0usize
    while i < k {
        let (r2, e2) = bn.int_mul(a, r, bb)
        if e2 != ok { ret (zero, e2) }
        r = r2
        i += 1usize
    }
    ret (r, ok)
}

// mpfr_get_str(x, base, n, RNDN): the n significant digits of |x| (values 0 .. base - 1, most significant first) written to digs and the exponent E with |x| about 0.d1 d2 ... * base^E; x must be non-zero
fn get_str(a: *mem.Arena, x: Mp, base: usize, n: usize, digs: []u8) -> (i64, err) {
    let bits = bn.int_bits(x.m)
    let lnb = math.log[f64](f64(base))
    var ex = i64(math.floor[f64](f64(i64(bits) + x.e) * 0.6931471805599453f64 / lnb)) + 1i64
    var tries = 0usize
    while tries < 6usize {
        tries += 1usize
        let k = i64(n) - ex
        var num = magnitude(a, x.m)
        var den: bn.Int = zero
        let (one, eo) = bn.int_from_i64(a, 1i64)
        if eo != ok { ret (0i64, eo) }
        den = one
        if k >= 0i64 {
            let (pk, ep) = int_pow(a, base, usize(k))
            if ep != ok { ret (0i64, ep) }
            let (nn, en) = bn.int_mul(a, num, pk)
            if en != ok { ret (0i64, en) }
            num = nn
        } else {
            let (pk, ep) = int_pow(a, base, usize(0i64 - k))
            if ep != ok { ret (0i64, ep) }
            den = pk
        }
        if x.e >= 0i64 {
            let (nn, en) = shl(a, num, usize(x.e))
            if en != ok { ret (0i64, en) }
            num = nn
        } else {
            let (dd, ed) = shl(a, den, usize(0i64 - x.e))
            if ed != ok { ret (0i64, ed) }
            den = dd
        }
        let (q0, r, ed2) = bn.int_divmod(a, num, den)
        if ed2 != ok { ret (0i64, ed2) }
        let (r2, er2) = shl(a, r, 1usize)
        if er2 != ok { ret (0i64, er2) }
        let c = bn.int_cmp(r2, den)
        var q = q0
        if c > 0i32 || (c == 0i32 && q0.sign != bn.Sign.Zero && (q0.limbs[0usize] & 1u32) == 1u32) {
            let (q1, eq1) = bn.int_add(a, q0, one)
            if eq1 != ok { ret (0i64, eq1) }
            q = q1
        }
        let (hi, eh) = int_pow(a, base, n)
        let (lo, el) = int_pow(a, base, n - 1usize)
        if eh != ok || el != ok { ret (0i64, mem.Full) }
        if bn.int_cmp(q, hi) >= 0i32 {
            ex += 1i64
        } else if bn.int_cmp(q, lo) < 0i32 {
            ex -= 1i64
        } else {
            let (b0, eb) = str.builder(a, n + 8usize)
            if eb != ok { ret (0i64, eb) }
            var bld = b0
            let ef = bn.int_format(q, &bld, u8(base))
            if ef != ok { ret (0i64, ef) }
            let s = str.done(&bld)
            var i = 0usize
            while i < n {
                let ch = s[i]
                if ch >= 97u8 { digs[i] = ch - 87u8 } else { digs[i] = ch - 48u8 }
                i += 1usize
            }
            ret (ex, ok)
        }
    }
    ret (0i64, mem.Full)
}

// mpfr("N e k") at prec bits to nearest (mode 0) or the directed modes of round_to_m: the decimal integer N (non-negative) times 10^k, k of either sign, exactly rounded
fn from_decimal(a: *mem.Arena, nn: bn.Int, k: i64, prec: usize, mode: usize) -> (Mp, err) {
    if k >= 0i64 {
        let (pk, ep) = int_pow(a, 10usize, usize(k))
        if ep != ok { ret (zero, ep) }
        let (v, ev) = bn.int_mul(a, nn, pk)
        if ev != ok { ret (zero, ev) }
        let (rt_, re_) = round_to_m(a, v, 0i64, prec, mode)
        ret (rt_, re_)
    }
    let (pk, ep) = int_pow(a, 10usize, usize(0i64 - k))
    if ep != ok { ret (zero, ep) }
    let (rt_, re_) = div_m(a, Mp{ m: nn, e: 0i64 }, Mp{ m: pk, e: 0i64 }, prec, mode)
    ret (rt_, re_)
}
