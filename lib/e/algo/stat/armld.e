// x87 extended precision (64-bit mantissa) sums as R computes them: sum(), mean(), var() and colMeans() accumulate in a C long double and round once to double. A software float with the
// 64-bit mantissa, round to nearest even, so the last bit of a sum agrees with R's on a build that uses the x87 type (Windows and Linux on x86-64).
//
// Not here: subnormal values (read as zero), infinities and NaN (a sum containing one answers the plain double sum).

use e.mem

type Ld = struct { neg: bool, e: i64, m: u64 }

fn ld_zero() -> Ld { ret Ld { neg: false, e: 0i64, m: 0u64 } }

fn ld_from(x: f64) -> Ld {
    let bits = mem.bitcast[u64](x)
    let expb = i64((bits >> 52u64) & 2047u64)
    let frac = bits & 4503599627370495u64
    if expb == 0i64 { ret ld_zero() }
    let mant = frac | 4503599627370496u64
    ret Ld { neg: (bits >> 63u64) == 1u64, e: expb - 1075i64 - 11i64, m: mant << 11u64 }
}

fn ld_to(a: Ld) -> f64 {
    if a.m == 0u64 { ret 0.0f64 }
    var mant = a.m >> 11u64
    let rem = a.m & 2047u64
    var e = a.e + 11i64
    if rem > 1024u64 || (rem == 1024u64 && (mant & 1u64) == 1u64) { mant += 1u64 }
    if mant == 9007199254740992u64 {
        mant = mant >> 1u64
        e += 1i64
    }
    let be = u64(e + 52i64 + 1023i64)
    var bits = (be << 52u64) | (mant & 4503599627370495u64)
    if a.neg { bits = bits | 9223372036854775808u64 }
    ret mem.bitcast[f64](bits)
}

fn ld_neg(a: Ld) -> Ld {
    if a.m == 0u64 { ret a }
    ret Ld { neg: !a.neg, e: a.e, m: a.m }
}

// round the 128-bit magnitude (hi, lo), the value being (hi 2^64 + lo) 2^(e - 64), to a 64-bit mantissa; hi has its top bit set
fn ld_round(neg: bool, e0: i64, hi0: u64, lo: u64) -> Ld {
    var hi = hi0
    var e = e0
    if lo > 9223372036854775808u64 || (lo == 9223372036854775808u64 && (hi & 1u64) == 1u64) {
        if hi == 18446744073709551615u64 {
            hi = 9223372036854775808u64
            e += 1i64
        } else {
            hi += 1u64
        }
    }
    ret Ld { neg: neg, e: e, m: hi }
}

fn ld_add(a: Ld, b: Ld) -> Ld {
    if a.m == 0u64 { ret b }
    if b.m == 0u64 { ret a }
    var big = a
    var small = b
    if b.e > a.e || (b.e == a.e && b.m > a.m) {
        big = b
        small = a
    }
    let d = big.e - small.e
    var sh = small.m
    var sl = 0u64
    var sticky = false
    if d == 0i64 {
        sl = 0u64
    } else if d < 64i64 {
        sl = sh << u64(64i64 - d)
        sh = sh >> u64(d)
    } else if d == 64i64 {
        sl = sh
        sh = 0u64
    } else if d < 128i64 {
        let k = d - 64i64
        sl = sh >> u64(k)
        sticky = (sh << u64(64i64 - k)) != 0u64
        sh = 0u64
    } else {
        sh = 0u64
        sl = 0u64
        sticky = true
    }
    if sticky { sl = sl | 1u64 }
    let bh = big.m
    if big.neg == small.neg {
        let lo = sl
        let carry = bh > 18446744073709551615u64 - sh
        var hi = 0u64
        if carry { hi = bh - (18446744073709551615u64 - sh) - 1u64 } else { hi = bh + sh }
        if carry {
            let nlo = (lo >> 1u64) | ((hi & 1u64) << 63u64) | (lo & 1u64)
            let nhi = (hi >> 1u64) | 9223372036854775808u64
            ret ld_round(big.neg, big.e + 1i64, nhi, nlo)
        }
        ret ld_round(big.neg, big.e, hi, lo)
    }
    // magnitudes subtract: big - small, the low word of big being zero
    var lo = 0u64
    var hi = bh - sh
    if sl != 0u64 {
        lo = 18446744073709551615u64 - sl + 1u64
        hi = hi - 1u64
    }
    if hi == 0u64 && lo == 0u64 { ret ld_zero() }
    var e = big.e
    if hi == 0u64 {
        hi = lo
        lo = 0u64
        e -= 64i64
    }
    var s = 0i64
    while (hi & 9223372036854775808u64) == 0u64 {
        hi = (hi << 1u64) | (lo >> 63u64)
        lo = lo << 1u64
        s += 1i64
    }
    ret ld_round(big.neg, e - s, hi, lo)
}

// a * b rounded once
fn ld_mul(a: Ld, b: Ld) -> Ld {
    if a.m == 0u64 || b.m == 0u64 { ret ld_zero() }
    let m32 = 4294967295u64
    let a0 = a.m & m32
    let a1 = a.m >> 32u64
    let b0 = b.m & m32
    let b1 = b.m >> 32u64
    let p00 = a0 * b0
    let p01 = a0 * b1
    let p10 = a1 * b0
    let p11 = a1 * b1
    let t = p01 + (p00 >> 32u64)
    let t2 = p10 + (t & m32)
    var lo = (t2 << 32u64) | (p00 & m32)
    var hi = p11 + (t >> 32u64) + (t2 >> 32u64)
    var e = a.e + b.e + 64i64
    if (hi & 9223372036854775808u64) == 0u64 {
        hi = (hi << 1u64) | (lo >> 63u64)
        lo = lo << 1u64
        e -= 1i64
    }
    ret ld_round(a.neg != b.neg, e, hi, lo)
}

// a / n for a positive integer n below 2^62, rounded once
fn ld_div(a: Ld, n: u64) -> Ld {
    if a.m == 0u64 { ret a }
    var r = 0u64
    var qh = 0u64
    var ql = 0u64
    var step = 0u64
    while step < 126u64 {
        var bit = 0u64
        if step < 64u64 { bit = (a.m >> (63u64 - step)) & 1u64 }
        r = (r << 1u64) | bit
        var qb = 0u64
        if r >= n {
            r -= n
            qb = 1u64
        }
        qh = (qh << 1u64) | (ql >> 63u64)
        ql = (ql << 1u64) | qb
        step += 1u64
    }
    var s = 0i64
    if qh == 0u64 {
        qh = ql
        ql = 0u64
        s = 64i64
    }
    while (qh & 9223372036854775808u64) == 0u64 {
        qh = (qh << 1u64) | (ql >> 63u64)
        ql = ql << 1u64
        s += 1i64
    }
    if r != 0u64 { ql = ql | 1u64 }
    // value = q 2^(e - 62) with q normalised to 128 bits by s: (qh 2^64 + ql) 2^(e - 62 - s)
    ret ld_round(a.neg, a.e + 2i64 - s + 64i64 - 64i64, qh, ql)
}

// sum(x)
fn sum_ld(v: []const f64) -> f64 {
    var s = ld_zero()
    var i = 0usize
    while i < v.len {
        if v[i] - v[i] != 0.0f64 {
            var t = 0.0f64
            var j = 0usize
            while j < v.len {
                t += v[j]
                j += 1usize
            }
            ret t
        }
        s = ld_add(s, ld_from(v[i]))
        i += 1usize
    }
    ret ld_to(s)
}

// mean(x): the long double sum over n, refined once by the mean of the deviations
fn mean_ld(v: []const f64) -> f64 {
    let n = u64(v.len)
    var s = ld_zero()
    var i = 0usize
    while i < v.len {
        s = ld_add(s, ld_from(v[i]))
        i += 1usize
    }
    s = ld_div(s, n)
    var t = ld_zero()
    i = 0usize
    while i < v.len {
        t = ld_add(t, ld_add(ld_from(v[i]), ld_neg(s)))
        i += 1usize
    }
    s = ld_add(s, ld_div(t, n))
    ret ld_to(s)
}

// colMeans of one column: the long double sum divided by n, rounded once
fn colmean_ld(v: []const f64) -> f64 {
    var s = ld_zero()
    var i = 0usize
    while i < v.len {
        s = ld_add(s, ld_from(v[i]))
        i += 1usize
    }
    ret ld_to(ld_div(s, u64(v.len)))
}

// var(x) as cov.c computes it for complete data: the mean as in mean(), then the sum of the squared double deviations in long double over n - 1
fn var_ld(v: []const f64) -> f64 {
    let n = u64(v.len)
    let xm = mean_ld(v)
    var s = ld_zero()
    let xl = ld_from(xm)
    var i = 0usize
    while i < v.len {
        let d = ld_add(ld_from(v[i]), ld_neg(xl))
        s = ld_add(s, ld_mul(d, d))
        i += 1usize
    }
    ret ld_to(ld_div(s, n - 1u64))
}
