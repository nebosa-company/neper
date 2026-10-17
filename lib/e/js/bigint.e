// Arbitrary-precision integers for JavaScript BigInt (browser tracker 5.8): a sign and a magnitude of 32-bit limbs, least
// significant first. Every operation allocates its result in the arena it is given and leaves its operands alone; a
// magnitude never has leading zero limbs and zero is the empty magnitude (never negative).

use e.mem
use e.str

error DivideByZero
error TooBig

type Big = struct { neg: bool, mag: []const u32 }

// Results larger than this many bits are refused (a RangeError in the caller): the realm has no collector.
const MAX_BITS: u64 = 1073741824u64

fn empty_mag() -> []const u32 {
    var none: []const u32 = zero
    ret none
}

fn zero_big() -> Big { ret Big { neg: false, mag: empty_mag() } }

fn is_zero(x: Big) -> bool { ret x.mag.len == 0usize }

fn trim_len(m: []const u32) -> usize {
    var n = m.len
    while n > 0usize && m[n - 1usize] == 0u32 { n -= 1usize }
    ret n
}

fn make(neg: bool, limbs: []u32, n: usize) -> Big {
    var len = n
    while len > 0usize && limbs[len - 1usize] == 0u32 { len -= 1usize }
    if len == 0usize { ret zero_big() }
    ret Big { neg: neg, mag: limbs[0usize..len] }
}

fn from_u64(a: *mem.Arena, v: u64) -> (Big, err) {
    if v == 0u64 { ret (zero_big(), ok) }
    let limbs = try mem.alloc[u32](a, 2usize)
    limbs[0usize] = u32(v & 4294967295u64)
    limbs[1usize] = u32(v >> 32u64)
    ret (make(false, limbs, 2usize), ok)
}

fn from_i64(a: *mem.Arena, v: i64) -> (Big, err) {
    if v >= 0i64 {
        let (r, e) = from_u64(a, u64(v))
        ret (r, e)
    }
    // -v without overflowing for i64::MIN.
    let mag = u64(0i64 - (v + 1i64)) + 1u64
    let (r2, e2) = from_u64(a, mag)
    if e2 != ok { ret (zero_big(), e2) }
    ret (Big { neg: true, mag: r2.mag }, ok)
}

// --- comparison

fn cmp_mag(x: []const u32, y: []const u32) -> i32 {
    if x.len != y.len {
        if x.len < y.len { ret -1i32 }
        ret 1i32
    }
    var i = x.len
    while i > 0usize {
        i -= 1usize
        if x[i] != y[i] {
            if x[i] < y[i] { ret -1i32 }
            ret 1i32
        }
    }
    ret 0i32
}

fn cmp(x: Big, y: Big) -> i32 {
    if x.neg != y.neg {
        if x.neg { ret -1i32 }
        ret 1i32
    }
    let c = cmp_mag(x.mag, y.mag)
    if x.neg { ret 0i32 - c }
    ret c
}

fn eq(x: Big, y: Big) -> bool { ret cmp(x, y) == 0i32 }

fn bit_length(x: Big) -> u64 {
    if x.mag.len == 0usize { ret 0u64 }
    let top = x.mag[x.mag.len - 1usize]
    var bits = 0u64
    var t = top
    while t != 0u32 {
        bits += 1u64
        t = t >> 1u32
    }
    ret u64(x.mag.len - 1usize) * 32u64 + bits
}

// --- magnitude arithmetic

fn add_mag(a: *mem.Arena, x: []const u32, y: []const u32) -> ([]u32, usize, err) {
    var big = x
    var small = y
    if y.len > x.len {
        big = y
        small = x
    }
    let out = try mem.alloc[u32](a, big.len + 1usize)
    var carry = 0u64
    var i = 0usize
    while i < big.len {
        var s = u64(big[i]) + carry
        if i < small.len { s += u64(small[i]) }
        out[i] = u32(s & 4294967295u64)
        carry = s >> 32u64
        i += 1usize
    }
    out[big.len] = u32(carry)
    ret (out, big.len + 1usize, ok)
}

// x - y for |x| >= |y|.
fn sub_mag(a: *mem.Arena, x: []const u32, y: []const u32) -> ([]u32, usize, err) {
    let out = try mem.alloc[u32](a, x.len + 1usize)
    var borrow = 0i64
    var i = 0usize
    while i < x.len {
        var d = i64(x[i]) - borrow
        if i < y.len { d -= i64(y[i]) }
        if d < 0i64 {
            d += 4294967296i64
            borrow = 1i64
        } else {
            borrow = 0i64
        }
        out[i] = u32(d)
        i += 1usize
    }
    out[x.len] = 0u32
    ret (out, x.len, ok)
}

fn add(a: *mem.Arena, x: Big, y: Big) -> (Big, err) {
    if x.neg == y.neg {
        let (m, n, e) = add_mag(a, x.mag, y.mag)
        if e != ok { ret (zero_big(), e) }
        ret (make(x.neg, m, n), ok)
    }
    let c = cmp_mag(x.mag, y.mag)
    if c == 0i32 { ret (zero_big(), ok) }
    if c > 0i32 {
        let (m2, n2, e2) = sub_mag(a, x.mag, y.mag)
        if e2 != ok { ret (zero_big(), e2) }
        ret (make(x.neg, m2, n2), ok)
    }
    let (m3, n3, e3) = sub_mag(a, y.mag, x.mag)
    if e3 != ok { ret (zero_big(), e3) }
    ret (make(y.neg, m3, n3), ok)
}

fn negate(x: Big) -> Big {
    if x.mag.len == 0usize { ret x }
    ret Big { neg: !x.neg, mag: x.mag }
}

fn sub(a: *mem.Arena, x: Big, y: Big) -> (Big, err) {
    let (r, e) = add(a, x, negate(y))
    ret (r, e)
}

fn mul(a: *mem.Arena, x: Big, y: Big) -> (Big, err) {
    if x.mag.len == 0usize || y.mag.len == 0usize { ret (zero_big(), ok) }
    if bit_length(x) + bit_length(y) > MAX_BITS { ret (zero_big(), TooBig) }
    let n = x.mag.len + y.mag.len
    let out = try mem.alloc[u32](a, n)
    var i = 0usize
    while i < n {
        out[i] = 0u32
        i += 1usize
    }
    var xi = 0usize
    while xi < x.mag.len {
        var carry = 0u64
        let xv = u64(x.mag[xi])
        var yi = 0usize
        while yi < y.mag.len {
            let cur = u64(out[xi + yi]) + xv * u64(y.mag[yi]) + carry
            out[xi + yi] = u32(cur & 4294967295u64)
            carry = cur >> 32u64
            yi += 1usize
        }
        var k = xi + y.mag.len
        while carry != 0u64 {
            let cur2 = u64(out[k]) + carry
            out[k] = u32(cur2 & 4294967295u64)
            carry = cur2 >> 32u64
            k += 1usize
        }
        xi += 1usize
    }
    ret (make(x.neg != y.neg, out, n), ok)
}

// Magnitude divided by one limb: the quotient and the remainder.
fn divrem_small(a: *mem.Arena, x: []const u32, d: u32) -> ([]u32, usize, u32, err) {
    let out = try mem.alloc[u32](a, x.len + 1usize)
    var rem = 0u64
    var i = x.len
    while i > 0usize {
        i -= 1usize
        let cur = (rem << 32u64) | u64(x[i])
        out[i] = u32(cur / u64(d))
        rem = cur % u64(d)
    }
    out[x.len] = 0u32
    ret (out, x.len, u32(rem), ok)
}

// Knuth algorithm D over magnitudes: the quotient and the remainder of x / y, y non-empty.
fn divrem_mag(a: *mem.Arena, x: []const u32, y: []const u32) -> ([]u32, usize, []u32, usize, err) {
    if cmp_mag(x, y) < 0i32 {
        let r = try mem.alloc[u32](a, x.len + 1usize)
        var i0 = 0usize
        while i0 < x.len {
            r[i0] = x[i0]
            i0 += 1usize
        }
        let q0 = try mem.alloc[u32](a, 1usize)
        q0[0usize] = 0u32
        ret (q0, 0usize, r, x.len, ok)
    }
    if y.len == 1usize {
        let (q, qn, rem, e) = divrem_small(a, x, y[0usize])
        if e != ok { ret (q, qn, q, 0usize, e) }
        let r1 = try mem.alloc[u32](a, 1usize)
        r1[0usize] = rem
        ret (q, qn, r1, 1usize, ok)
    }
    // Normalise so the top limb of the divisor has its high bit set.
    var norm = 0u32
    var top = y[y.len - 1usize]
    while (top & 2147483648u32) == 0u32 {
        top = top << 1u32
        norm += 1u32
    }
    let n = y.len
    let m = x.len - y.len
    let v = try mem.alloc[u32](a, n)
    let u = try mem.alloc[u32](a, x.len + 1usize)
    var i = 0usize
    while i < n {
        var limb = y[i] << norm
        if norm > 0u32 && i > 0usize { limb = limb | (y[i - 1usize] >> (32u32 - norm)) }
        v[i] = limb
        i += 1usize
    }
    i = 0usize
    while i <= x.len {
        var limb2 = 0u32
        if i < x.len { limb2 = x[i] << norm }
        if norm > 0u32 && i > 0usize { limb2 = limb2 | (x[i - 1usize] >> (32u32 - norm)) }
        u[i] = limb2
        i += 1usize
    }
    let q = try mem.alloc[u32](a, m + 1usize)
    var j = m + 1usize
    while j > 0usize {
        j -= 1usize
        let num = (u64(u[j + n]) << 32u64) | u64(u[j + n - 1usize])
        var qhat = num / u64(v[n - 1usize])
        var rhat = num % u64(v[n - 1usize])
        while qhat >= 4294967296u64 || qhat * u64(v[n - 2usize]) > ((rhat << 32u64) | u64(u[j + n - 2usize])) {
            qhat -= 1u64
            rhat += u64(v[n - 1usize])
            if rhat >= 4294967296u64 { break }
        }
        // Multiply and subtract.
        var borrow = 0i64
        var carry = 0u64
        var k = 0usize
        while k < n {
            let p = qhat * u64(v[k]) + carry
            carry = p >> 32u64
            let sub_v = i64(u[j + k]) - borrow - i64(p & 4294967295u64)
            if sub_v < 0i64 {
                u[j + k] = u32(sub_v + 4294967296i64)
                borrow = 1i64
            } else {
                u[j + k] = u32(sub_v)
                borrow = 0i64
            }
            k += 1usize
        }
        let top_sub = i64(u[j + n]) - borrow - i64(carry)
        if top_sub < 0i64 {
            u[j + n] = u32(top_sub + 4294967296i64)
            // qhat was one too large: add the divisor back.
            qhat -= 1u64
            var c2 = 0u64
            var k2 = 0usize
            while k2 < n {
                let s = u64(u[j + k2]) + u64(v[k2]) + c2
                u[j + k2] = u32(s & 4294967295u64)
                c2 = s >> 32u64
                k2 += 1usize
            }
            u[j + n] = u32((u64(u[j + n]) + c2) & 4294967295u64)
        } else {
            u[j + n] = u32(top_sub)
        }
        q[j] = u32(qhat)
    }
    // Denormalise the remainder.
    let r = try mem.alloc[u32](a, n + 1usize)
    var ri = 0usize
    while ri < n {
        var limb3 = u[ri] >> norm
        if norm > 0u32 { limb3 = limb3 | (u[ri + 1usize] << (32u32 - norm)) }
        r[ri] = limb3
        ri += 1usize
    }
    ret (q, m + 1usize, r, n, ok)
}

// Truncating division and remainder (the remainder takes the dividend's sign).
fn divrem(a: *mem.Arena, x: Big, y: Big) -> (Big, Big, err) {
    if y.mag.len == 0usize { ret (zero_big(), zero_big(), DivideByZero) }
    let (q, qn, r, rn, e) = divrem_mag(a, x.mag, y.mag)
    if e != ok { ret (zero_big(), zero_big(), e) }
    ret (make(x.neg != y.neg, q, qn), make(x.neg, r, rn), ok)
}

fn pow(a: *mem.Arena, x: Big, e: Big) -> (Big, err) {
    if is_zero(e) {
        let (one, oe) = from_u64(a, 1u64)
        ret (one, oe)
    }
    if x.mag.len == 0usize { ret (zero_big(), ok) }
    if e.mag.len > 1usize { ret (zero_big(), TooBig) }
    var n = u64(e.mag[0usize])
    if x.mag.len == 1usize && x.mag[0usize] == 1u32 {
        let (one2, oe2) = from_u64(a, 1u64)
        if oe2 != ok { ret (zero_big(), oe2) }
        if x.neg && (n % 2u64) == 1u64 { ret (negate(one2), ok) }
        ret (one2, ok)
    }
    if bit_length(x) * n > MAX_BITS { ret (zero_big(), TooBig) }
    var result = try from_u64(a, 1u64)
    var base = x
    while n > 0u64 {
        if (n & 1u64) == 1u64 { result = try mul(a, result, base) }
        n = n >> 1u64
        if n > 0u64 { base = try mul(a, base, base) }
    }
    ret (result, ok)
}

// --- shifts

fn shl_mag(a: *mem.Arena, x: []const u32, bits: u64) -> ([]u32, usize, err) {
    let limb_shift = usize(bits / 32u64)
    let bit_shift = u32(bits % 32u64)
    let n = x.len + limb_shift + 1usize
    let out = try mem.alloc[u32](a, n)
    var i = 0usize
    while i < n {
        out[i] = 0u32
        i += 1usize
    }
    var k = 0usize
    while k < x.len {
        out[k + limb_shift] = out[k + limb_shift] | (x[k] << bit_shift)
        if bit_shift > 0u32 { out[k + limb_shift + 1usize] = out[k + limb_shift + 1usize] | (x[k] >> (32u32 - bit_shift)) }
        k += 1usize
    }
    ret (out, n, ok)
}

fn is_low_zero(x: []const u32, bits: u64) -> bool {
    let limbs = usize(bits / 32u64)
    var i = 0usize
    while i < limbs && i < x.len {
        if x[i] != 0u32 { ret false }
        i += 1usize
    }
    let rem = u32(bits % 32u64)
    if rem > 0u32 && limbs < x.len {
        let mask = (1u32 << rem) - 1u32
        if (x[limbs] & mask) != 0u32 { ret false }
    }
    ret true
}

fn shr_mag(a: *mem.Arena, x: []const u32, bits: u64) -> ([]u32, usize, err) {
    let limb_shift = usize(bits / 32u64)
    let bit_shift = u32(bits % 32u64)
    if limb_shift >= x.len {
        let z = try mem.alloc[u32](a, 1usize)
        z[0usize] = 0u32
        ret (z, 0usize, ok)
    }
    let n = x.len - limb_shift
    let out = try mem.alloc[u32](a, n)
    var i = 0usize
    while i < n {
        var limb = x[i + limb_shift] >> bit_shift
        if bit_shift > 0u32 && i + limb_shift + 1usize < x.len { limb = limb | (x[i + limb_shift + 1usize] << (32u32 - bit_shift)) }
        out[i] = limb
        i += 1usize
    }
    ret (out, n, ok)
}

// x << n for a signed shift count (a negative count shifts right, rounding toward negative infinity).
fn shift_by(a: *mem.Arena, x: Big, count: Big) -> (Big, err) {
    if x.mag.len == 0usize { ret (x, ok) }
    if count.mag.len > 1usize {
        if !count.neg { ret (zero_big(), TooBig) }
        if x.neg {
            let (m1, e1) = from_i64(a, -1i64)
            ret (m1, e1)
        }
        ret (zero_big(), ok)
    }
    var n = 0u64
    if count.mag.len == 1usize { n = u64(count.mag[0usize]) }
    if !count.neg {
        if bit_length(x) + n > MAX_BITS { ret (zero_big(), TooBig) }
        let (m, mn, e) = shl_mag(a, x.mag, n)
        if e != ok { ret (zero_big(), e) }
        ret (make(x.neg, m, mn), ok)
    }
    let (m2, mn2, e2) = shr_mag(a, x.mag, n)
    if e2 != ok { ret (zero_big(), e2) }
    var r = make(x.neg, m2, mn2)
    if x.neg && !is_low_zero(x.mag, n) {
        // Floor: a negative value with discarded bits rounds away from zero.
        let (one, oe) = from_u64(a, 1u64)
        if oe != ok { ret (zero_big(), oe) }
        r = try sub(a, r, one)
    }
    ret (r, ok)
}

// --- bitwise operations on the infinite two's complement form

// The two's complement limbs of x sign-extended to `n` limbs.
fn twos(a: *mem.Arena, x: Big, n: usize) -> ([]u32, err) {
    let out = try mem.alloc[u32](a, n)
    var i = 0usize
    while i < n {
        if i < x.mag.len { out[i] = x.mag[i] } else { out[i] = 0u32 }
        i += 1usize
    }
    if x.neg {
        var carry = 1u64
        i = 0usize
        while i < n {
            let v = u64(~out[i]) + carry
            out[i] = u32(v & 4294967295u64)
            carry = v >> 32u64
            i += 1usize
        }
    }
    ret (out, ok)
}

fn from_twos(a: *mem.Arena, limbs: []u32, n: usize) -> (Big, err) {
    let neg = (limbs[n - 1usize] & 2147483648u32) != 0u32
    if !neg { ret (make(false, limbs, n), ok) }
    var carry = 1u64
    var i = 0usize
    while i < n {
        let v = u64(~limbs[i]) + carry
        limbs[i] = u32(v & 4294967295u64)
        carry = v >> 32u64
        i += 1usize
    }
    ret (make(true, limbs, n), ok)
}

// op: 0 and, 1 or, 2 xor.
fn bitwise(a: *mem.Arena, x: Big, y: Big, op: u8) -> (Big, err) {
    var n = x.mag.len
    if y.mag.len > n { n = y.mag.len }
    n += 1usize
    let xs = try twos(a, x, n)
    let ys = try twos(a, y, n)
    var i = 0usize
    while i < n {
        if op == 0u8 { xs[i] = xs[i] & ys[i] } else if op == 1u8 { xs[i] = xs[i] | ys[i] } else { xs[i] = xs[i] ^ ys[i] }
        i += 1usize
    }
    let (r, e) = from_twos(a, xs, n)
    ret (r, e)
}

fn bit_not(a: *mem.Arena, x: Big) -> (Big, err) {
    // ~x = -x - 1
    let (one, oe) = from_u64(a, 1u64)
    if oe != ok { ret (zero_big(), oe) }
    let (r, e) = sub(a, negate(x), one)
    ret (r, e)
}

// BigInt.asUintN(bits, x): x modulo 2^bits.
fn as_uint_n(a: *mem.Arena, bits: u64, x: Big) -> (Big, err) {
    if bits == 0u64 { ret (zero_big(), ok) }
    if bits > MAX_BITS { ret (zero_big(), TooBig) }
    let n = usize((bits + 31u64) / 32u64) + 1usize
    var wide = n
    if x.mag.len + 1usize > wide { wide = x.mag.len + 1usize }
    let t = try twos(a, x, wide)
    let out = try mem.alloc[u32](a, n)
    var i = 0usize
    while i < n {
        if i < wide { out[i] = t[i] } else if x.neg { out[i] = 4294967295u32 } else { out[i] = 0u32 }
        i += 1usize
    }
    // Clear the bits at and above `bits`.
    let full = usize(bits / 32u64)
    let rem = u32(bits % 32u64)
    if rem > 0u32 && full < n { out[full] = out[full] & ((1u32 << rem) - 1u32) }
    var k = full
    if rem > 0u32 { k += 1usize }
    while k < n {
        out[k] = 0u32
        k += 1usize
    }
    ret (make(false, out, n), ok)
}

fn as_int_n(a: *mem.Arena, bits: u64, x: Big) -> (Big, err) {
    if bits == 0u64 { ret (zero_big(), ok) }
    let u = try as_uint_n(a, bits, x)
    // If bit (bits - 1) is set the value is u - 2^bits.
    let top = bits - 1u64
    let limb = usize(top / 32u64)
    var set = false
    if limb < u.mag.len { set = (u.mag[limb] & (1u32 << u32(top % 32u64))) != 0u32 }
    if !set { ret (u, ok) }
    let one = try from_u64(a, 1u64)
    let (p, pn, pe) = shl_mag(a, one.mag, bits)
    if pe != ok { ret (zero_big(), pe) }
    let r = try sub(a, u, make(false, p, pn))
    ret (r, ok)
}

// --- conversions

fn to_u64_wrapping(x: Big) -> u64 {
    var v = 0u64
    if x.mag.len > 0usize { v = u64(x.mag[0usize]) }
    if x.mag.len > 1usize { v = v | (u64(x.mag[1usize]) << 32u64) }
    if x.neg { ret (~v) +% 1u64 }
    ret v
}

fn to_i64_wrapping(x: Big) -> i64 { ret i64(to_u64_wrapping(x)) }

fn pow2_f64(e: i64) -> f64 {
    var r = 1.0f64
    var n = e
    while n > 0i64 {
        if n >= 64i64 {
            r = r * 18446744073709551616.0f64
            n -= 64i64
        } else {
            r = r * 2.0f64
            n -= 1i64
        }
        if r > 1.0e308f64 * 10.0f64 { ret r }
    }
    ret r
}

fn to_f64(x: Big) -> f64 {
    if x.mag.len == 0usize { ret 0.0f64 }
    let bits = bit_length(x)
    var value = 0.0f64
    if bits <= 64u64 {
        var v = u64(x.mag[0usize])
        if x.mag.len > 1usize { v = v | (u64(x.mag[1usize]) << 32u64) }
        value = f64(v)
    } else {
        // The top 64 bits with a sticky bit for everything below, scaled back.
        let drop = bits - 64u64
        let limb = usize(drop / 32u64)
        let sh = u32(drop % 32u64)
        var l1 = 0u64
        var l2 = 0u64
        if limb + 1usize < x.mag.len { l1 = u64(x.mag[limb + 1usize]) }
        if limb + 2usize < x.mag.len { l2 = u64(x.mag[limb + 2usize]) }
        var top64 = (u64(x.mag[limb]) >> u64(sh)) | (l1 << (32u64 - u64(sh)))
        if sh > 0u32 { top64 = top64 | (l2 << (64u64 - u64(sh))) }
        if !is_low_zero(x.mag, drop) { top64 = top64 | 1u64 }
        value = f64(top64) * pow2_f64(i64(drop))
    }
    if x.neg { ret 0.0f64 - value }
    ret value
}

// An integral finite double as a BigInt.
fn from_f64(a: *mem.Arena, x: f64) -> (Big, err) {
    if x == 0.0f64 { ret (zero_big(), ok) }
    var v = x
    var neg = false
    if v < 0.0f64 {
        neg = true
        v = 0.0f64 - v
    }
    let bits = mem.bitcast[u64](v)
    let exp = i64((bits >> 52u64) & 2047u64) - 1075i64
    var mant = (bits & 4503599627370495u64) | 4503599627370496u64
    if exp < 0i64 {
        mant = mant >> u64(0i64 - exp)
        let (r, e) = from_u64(a, mant)
        if e != ok { ret (zero_big(), e) }
        ret (Big { neg: neg && r.mag.len > 0usize, mag: r.mag }, ok)
    }
    let base = try from_u64(a, mant)
    let (m, mn, se) = shl_mag(a, base.mag, u64(exp))
    if se != ok { ret (zero_big(), se) }
    ret (make(neg, m, mn), ok)
}

// -1, 0, 1 comparing with a double; 2 when the double is NaN.
fn cmp_f64(a: *mem.Arena, x: Big, y: f64) -> i32 {
    if y != y { ret 2i32 }
    if y - y != 0.0f64 {
        if y > 0.0f64 { ret -1i32 }
        ret 1i32
    }
    var ip = y
    if y < 4503599627370496.0f64 && y > -4503599627370496.0f64 {
        if y >= 0.0f64 { ip = f64(i64(y)) } else { ip = 0.0f64 - f64(i64(0.0f64 - y)) }
    }
    let (bi, e) = from_f64(a, ip)
    if e != ok { ret 2i32 }
    let c = cmp(x, bi)
    if c != 0i32 { ret c }
    if y > ip { ret -1i32 }
    if y < ip { ret 1i32 }
    ret 0i32
}

fn digit_char(d: u32) -> u8 {
    if d < 10u32 { ret u8(48u32 + d) }
    ret u8(87u32 + d)
}

fn to_string(a: *mem.Arena, x: Big, radix: u32) -> (str, err) {
    if x.mag.len == 0usize { ret ("0", ok) }
    var cur = try mem.alloc[u32](a, x.mag.len + 1usize)
    var n = x.mag.len
    var i = 0usize
    while i < n {
        cur[i] = x.mag[i]
        i += 1usize
    }
    // Chunks of the largest power of the radix that fits a limb.
    var chunk = radix
    var chunk_digits = 1u32
    while u64(chunk) * u64(radix) <= 4294967295u64 {
        chunk = chunk * radix
        chunk_digits += 1u32
    }
    let digits = try mem.alloc[u8](a, (x.mag.len + 2usize) * usize(chunk_digits))
    var dn = 0usize
    while n > 0usize {
        let (q, qn, rem, e) = divrem_small(a, cur[0usize..n], chunk)
        if e != ok { ret ("", e) }
        var r = rem
        var d = 0u32
        while d < chunk_digits {
            digits[dn] = digit_char(r % radix)
            dn += 1usize
            r = r / radix
            d += 1u32
        }
        n = qn
        while n > 0usize && q[n - 1usize] == 0u32 { n -= 1usize }
        cur = q
    }
    while dn > 1usize && digits[dn - 1usize] == 48u8 { dn -= 1usize }
    var out = try str.builder(a, dn + 2usize)
    if x.neg { try str.push(&out, "-") }
    var k = dn
    while k > 0usize {
        k -= 1usize
        try str.push_byte(&out, digits[k])
    }
    ret (str.done(&out), ok)
}

fn digit_value(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c - 48u8) }
    if c >= 97u8 && c <= 122u8 { ret u32(c - 97u8) + 10u32 }
    if c >= 65u8 && c <= 90u8 { ret u32(c - 65u8) + 10u32 }
    ret 99u32
}

// Digits in `radix` (no sign, no prefix, no separators) as a non-negative BigInt; false when a digit is invalid or none.
fn parse_digits(a: *mem.Arena, s: str, radix: u32) -> (Big, bool, err) {
    if s.len == 0usize { ret (zero_big(), false, ok) }
    var cur = try mem.alloc[u32](a, s.len / 4usize + 4usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let d = digit_value(s[i])
        if d >= radix { ret (zero_big(), false, ok) }
        // cur = cur * radix + d
        var carry = u64(d)
        var k = 0usize
        while k < n {
            let v = u64(cur[k]) * u64(radix) + carry
            cur[k] = u32(v & 4294967295u64)
            carry = v >> 32u64
            k += 1usize
        }
        if carry != 0u64 {
            if n >= cur.len {
                let bigger = try mem.alloc[u32](a, cur.len * 2usize)
                var c2 = 0usize
                while c2 < n {
                    bigger[c2] = cur[c2]
                    c2 += 1usize
                }
                cur = bigger
            }
            cur[n] = u32(carry)
            n += 1usize
        }
        i += 1usize
    }
    ret (make(false, cur, n), true, ok)
}
