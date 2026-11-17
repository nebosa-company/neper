// Rmpfr / MPFR style binary floating point of a chosen precision on the big integers of e.algo.bignum: a value is m * 2^e with m a signed integer of at most `prec` bits, and every operation is the exact result rounded to nearest, ties to even.
//
// Here: from a mantissa and exponent, add, sub, mul, div, sqrt, exp, log, pow, sin, cos, pi, negation, comparison and the conversion to a pair of doubles (the value rounded to 53 bits and the remainder rounded to 53 bits).
//
// Not here: tan, the inverse and hyperbolic functions, gamma, zeta, erf, Bessel, the constants, the other rounding modes, infinities and NaN.

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
