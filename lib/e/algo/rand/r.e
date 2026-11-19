// R's random number streams, value for value: the Mersenne-Twister seeded the way
// `set.seed` does it, `runif`, `rnorm` by inversion, `rexp`, and `sample` by rejection
// (R >= 3.6). A stream seeded with the same integer gives the numbers R gives, so a fixture
// can compare Neper's draws with R's directly.
//
// Not here: R's other generators (Super-Duper aside) and normal kinds, `sample` with `prob` or with n past
// 2^32 (R reads more than two 16-bit chunks there), and the hash path R takes for
// n > 1e7. `rbits` does not wrap in 64 bits as R's does, which is why n stays below 2^32.

use e.math
use e.math.special as special
use e.mem

// kind 0 is the Mersenne-Twister, 1 Marsaglia's Super-Duper (set.seed(seed, kind = "Super-Duper")), whose two-word state is i1 and i2
type Rng = struct { mt: [624]u64, mti: i64, kind: i64, i1: u64, i2: u64 }

error TooLarge

const MASK32: u64 = 4294967295u64

// set.seed(seed): the seed is scrambled fifty times, then fills the 625-word state, the first
// word of which is the position and is overwritten with 624.
fn seed(r: *Rng, value: i64) {
    var s = u64(value & 4294967295i64)
    var j = 0usize
    while j < 50usize {
        s = (69069u64 * s + 1u64) & MASK32
        j += 1usize
    }
    s = (69069u64 * s + 1u64) & MASK32
    var i = 0usize
    while i < 624usize {
        s = (69069u64 * s + 1u64) & MASK32
        r.mt[i] = s
        i += 1usize
    }
    r.mti = 624i64
    r.kind = 0i64
}

// set.seed(seed, kind = "Super-Duper"): the seed scrambled fifty times, then two words: I1 (the shift-register word, made non-zero) and I2 (the congruential
// word, made odd)
fn seed_super(r: *Rng, value: i64) {
    var s = u64(value & 4294967295i64)
    var j = 0usize
    while j < 50usize {
        s = (69069u64 * s + 1u64) & MASK32
        j += 1usize
    }
    s = (69069u64 * s + 1u64) & MASK32
    r.i1 = s
    s = (69069u64 * s + 1u64) & MASK32
    r.i2 = s
    if r.i1 == 0u64 { r.i1 = 1u64 }
    r.i2 = r.i2 | 1u64
    r.kind = 1i64
}

fn genrand(r: *Rng) -> f64 {
    if r.kind == 1i64 {
        r.i2 = (r.i2 * 69069u64) & MASK32
        r.i1 = r.i1 ^ (r.i1 >> 15u64)
        r.i1 = r.i1 ^ ((r.i1 << 17u64) & MASK32)
        ret f64(r.i1 ^ r.i2) * 2.328306437080797e-10f64
    }
    if r.mti >= 624i64 {
        var kk = 0usize
        while kk < 227usize {
            let y = (r.mt[kk] & 2147483648u64) | (r.mt[kk + 1usize] & 2147483647u64)
            var mag = 0u64
            if (y & 1u64) != 0u64 { mag = 2567483615u64 }
            r.mt[kk] = r.mt[kk + 397usize] ^ (y >> 1u64) ^ mag
            kk += 1usize
        }
        while kk < 623usize {
            let y = (r.mt[kk] & 2147483648u64) | (r.mt[kk + 1usize] & 2147483647u64)
            var mag = 0u64
            if (y & 1u64) != 0u64 { mag = 2567483615u64 }
            r.mt[kk] = r.mt[kk - 227usize] ^ (y >> 1u64) ^ mag
            kk += 1usize
        }
        let y = (r.mt[623usize] & 2147483648u64) | (r.mt[0usize] & 2147483647u64)
        var mag = 0u64
        if (y & 1u64) != 0u64 { mag = 2567483615u64 }
        r.mt[623usize] = r.mt[396usize] ^ (y >> 1u64) ^ mag
        r.mti = 0i64
    }
    var y = r.mt[usize(r.mti)]
    r.mti += 1i64
    y = y ^ (y >> 11u64)
    y = y ^ (((y << 7u64) & MASK32) & 2636928640u64)
    y = y ^ (((y << 15u64) & MASK32) & 4022730752u64)
    y = y ^ (y >> 18u64)
    ret f64(y) * 2.3283064365386963e-10f64
}

// unif_rand(): never exactly 0 or 1.
fn unif(r: *Rng) -> f64 {
    let x = genrand(r)
    if x <= 0.0f64 { ret 0.5f64 * 2.328306437080797e-10f64 }
    if 1.0f64 - x <= 0.0f64 { ret 1.0f64 - 0.5f64 * 2.328306437080797e-10f64 }
    ret x
}

fn rbits(r: *Rng, bits: i64) -> f64 {
    var v = 0u64
    var n = 0i64
    while n <= bits {
        let v1 = u64(math.floor[f64](unif(r) * 65536.0f64))
        v = 65536u64 * v + v1
        n += 16i64
    }
    let one = 1u64
    ret f64(v & ((one << u64(bits)) - 1u64))
}

// R_unif_index: an integer in [0, dn) by rejection from the next power of two.
fn unif_index(r: *Rng, dn: f64) -> f64 {
    if dn <= 0.0f64 { ret 0.0f64 }
    let bits = i64(math.ceil[f64](math.log2[f64](dn)))
    var dv = rbits(r, bits)
    while dn <= dv { dv = rbits(r, bits) }
    ret dv
}

fn runif(r: *Rng, a: f64, b: f64) -> f64 {
    if !(a - a == 0.0f64) || !(b - b == 0.0f64) || b < a { ret special.nan() }
    if a == b { ret a }
    var u = unif(r)
    while u <= 0.0f64 || u >= 1.0f64 { u = unif(r) }
    ret a + (b - a) * u
}

// norm_rand() by inversion: two uniforms make a 53-bit one.
fn norm(r: *Rng) -> f64 {
    let big = 134217728.0f64
    var u = unif(r)
    u = f64(i64(big * u)) + unif(r)
    ret special.normal_quantile(u / big)
}

fn rnorm(r: *Rng, mu: f64, sigma: f64) -> f64 {
    if mu != mu || !(sigma - sigma == 0.0f64) || sigma < 0.0f64 { ret special.nan() }
    if sigma == 0.0f64 || !(mu - mu == 0.0f64) { ret mu }
    ret mu + sigma * norm(r)
}

// exp_rand(): Ahrens and Dieter 1972.
fn exp_unit(r: *Rng) -> f64 {
    var q: [16]f64 = zero
    q[0] = 0.6931471805599453f64
    q[1] = 0.9333736875190459f64
    q[2] = 0.9888777961838675f64
    q[3] = 0.9984959252914960f64
    q[4] = 0.9998292811061389f64
    q[5] = 0.9999833164100727f64
    q[6] = 0.9999985691438767f64
    q[7] = 0.9999998906925558f64
    q[8] = 0.9999999924734159f64
    q[9] = 0.9999999995283275f64
    q[10] = 0.9999999999728814f64
    q[11] = 0.9999999999985598f64
    q[12] = 0.9999999999999289f64
    q[13] = 0.9999999999999968f64
    q[14] = 0.9999999999999999f64
    q[15] = 1.0f64
    var a = 0.0f64
    var u = unif(r)
    while u <= 0.0f64 || u >= 1.0f64 { u = unif(r) }
    while true {
        u += u
        if u > 1.0f64 { break }
        a += q[0usize]
    }
    u -= 1.0f64
    if u <= q[0usize] { ret a + u }
    var i = 0usize
    var ustar = unif(r)
    var umin = ustar
    while true {
        ustar = unif(r)
        if umin > ustar { umin = ustar }
        i += 1usize
        if !(u > q[i]) { break }
    }
    ret a + umin * q[0usize]
}

fn rexp(r: *Rng, scale: f64) -> f64 {
    if !(scale - scale == 0.0f64) || scale <= 0.0f64 {
        if scale == 0.0f64 { ret 0.0f64 }
        ret special.nan()
    }
    ret scale * exp_unit(r)
}

// sample.int(n, size, replace): 1-based, as R answers.
fn sample_int(a: *mem.Arena, r: *Rng, n: i64, size: i64, replace: bool) -> ([]i64, err) {
    var out: []i64 = zero
    if n < 0i64 || size < 0i64 { ret (out, TooLarge) }
    if !replace && size > n { ret (out, TooLarge) }
    let (y, y_error) = mem.alloc[i64](a, usize(size))
    if y_error != ok { ret (out, y_error) }
    // R's sample2: n past 1e7 without replacement, size at most n / 2, rejects repeats
    if !replace && n > 10000000i64 && size <= n / 2i64 {
        var i = 0i64
        while i < size {
            var tries = 0i64
            var v = 0i64
            while true {
                v = i64(unif_index(r, f64(n))) + 1i64
                var dup = false
                var k = 0i64
                while k < i {
                    if y[usize(k)] == v { dup = true }
                    k += 1i64
                }
                if !dup { break }
                tries += 1i64
                if tries >= 100i64 { ret (out, TooLarge) }
            }
            y[usize(i)] = v
            i += 1i64
        }
        ret (y, ok)
    }
    if !replace && size >= 2i64 && n >= 4294967296i64 { ret (out, TooLarge) }
    if replace || size < 2i64 {
        var i = 0i64
        while i < size {
            y[usize(i)] = i64(unif_index(r, f64(n))) + 1i64
            i += 1i64
        }
        ret (y, ok)
    }
    let (x, x_error) = mem.alloc[i64](a, usize(n))
    if x_error != ok { ret (out, x_error) }
    var i = 0i64
    while i < n {
        x[usize(i)] = i
        i += 1i64
    }
    var left = n
    i = 0i64
    while i < size {
        let j = i64(unif_index(r, f64(left)))
        y[usize(i)] = x[usize(j)] + 1i64
        left -= 1i64
        x[usize(j)] = x[usize(left)]
        i += 1i64
    }
    ret (y, ok)
}

// rbinom(1, n, pp) by R's inversion algorithm, which R uses when n min(pp, 1 - pp) < 30; the BTPE branch for larger means is not here and the answer is NaN
fn rbinom_inv(r: *Rng, n: f64, pp: f64) -> f64 {
    if n != n || pp != pp || n < 0.0f64 || pp < 0.0f64 || pp > 1.0f64 { ret special.nan() }
    let nn = math.floor[f64](n + 0.5f64)
    if nn == 0.0f64 || pp == 0.0f64 { ret 0.0f64 }
    if pp == 1.0f64 { ret nn }
    var p = pp
    if 1.0f64 - pp < p { p = 1.0f64 - pp }
    let q = 1.0f64 - p
    let np = nn * p
    if np >= 30.0f64 { ret special.nan() }
    let rr = p / q
    let g = rr * (nn + 1.0f64)
    let qn = math.pow[f64](q, nn)
    var ix = 0.0f64
    var found = false
    while !found {
        ix = 0.0f64
        var f = qn
        var u = unif(r)
        var inner = true
        while inner {
            if u < f {
                found = true
                inner = false
            } else {
                if ix > 110.0f64 {
                    inner = false
                } else {
                    u -= f
                    ix += 1.0f64
                    f *= (g / ix - rr)
                }
            }
        }
    }
    if pp > 0.5f64 { ix = nn - ix }
    ret ix
}

// rgamma(a, scale) for a >= 1 as R's nmath rgamma.c does (Ahrens and Dieter 1982, algorithm GD): the same steps and constants, so the stream matches R's. a < 1 (algorithm GS) is not here and answers NaN.
fn rgamma(r: *Rng, a: f64, scale: f64) -> f64 {
    if a != a || scale != scale { ret special.nan() }
    if a < 1.0f64 { ret special.nan() }
    let sqrt32 = 5.656854f64
    let q1 = 0.04166669f64
    let q2 = 0.02083148f64
    let q3 = 0.00801191f64
    let q4 = 0.00144121f64
    let q5 = -7.388e-5f64
    let q6 = 2.4511e-4f64
    let q7 = 2.424e-4f64
    let a1 = 0.3333333f64
    let a2 = -0.250003f64
    let a3 = 0.2000062f64
    let a4 = -0.1662921f64
    let a5 = 0.1423657f64
    let a6 = -0.1367177f64
    let a7 = 0.1233795f64
    let s2 = a - 0.5f64
    let s = math.sqrt[f64](s2)
    let d = sqrt32 - s * 12.0f64
    var t = norm(r)
    var x = s + 0.5f64 * t
    let ret_val = x * x
    if t >= 0.0f64 { ret scale * ret_val }
    var u = unif(r)
    if d * u <= t * t * t { ret scale * ret_val }
    let rr = 1.0f64 / a
    let q0 = ((((((q7 * rr + q6) * rr + q5) * rr + q4) * rr + q3) * rr + q2) * rr + q1) * rr
    var b = 0.0f64
    var si = 0.0f64
    var c = 0.0f64
    if a <= 3.686f64 {
        b = 0.463f64 + s + 0.178f64 * s2
        si = 1.235f64
        c = 0.195f64 / s - 0.079f64 + 0.16f64 * s
    } else if a <= 13.022f64 {
        b = 1.654f64 + 0.0076f64 * s2
        si = 1.68f64 / s + 0.275f64
        c = 0.062f64 / s + 0.024f64
    } else {
        b = 1.77f64
        si = 0.75f64
        c = 0.1515f64 / s
    }
    if x > 0.0f64 {
        let v = t / (s + s)
        var q = 0.0f64
        if math.abs[f64](v) <= 0.25f64 {
            q = q0 + 0.5f64 * t * t * ((((((a7 * v + a6) * v + a5) * v + a4) * v + a3) * v + a2) * v + a1) * v
        } else {
            q = q0 - s * t + 0.25f64 * t * t + (s2 + s2) * math.log[f64](1.0f64 + v)
        }
        if math.log[f64](1.0f64 - u) <= q { ret scale * ret_val }
    }
    var done = false
    while !done {
        let e = exp_unit(r)
        u = unif(r)
        u = u + u - 1.0f64
        if u < 0.0f64 { t = b - si * e } else { t = b + si * e }
        if t >= -0.71874483771719f64 {
            let v = t / (s + s)
            var q = 0.0f64
            if math.abs[f64](v) <= 0.25f64 {
                q = q0 + 0.5f64 * t * t * ((((((a7 * v + a6) * v + a5) * v + a4) * v + a3) * v + a2) * v + a1) * v
            } else {
                q = q0 - s * t + 0.25f64 * t * t + (s2 + s2) * math.log[f64](1.0f64 + v)
            }
            if q > 0.0f64 {
                let w = math.exp[f64](q) - 1.0f64
                if c * math.abs[f64](u) <= w * math.exp[f64](e - 0.5f64 * t * t) { done = true }
            }
        }
    }
    x = s + 0.5f64 * t
    ret scale * x * x
}

// rchisq(1, df) = rgamma(df / 2, 2)
fn rchisq(r: *Rng, df: f64) -> f64 { ret rgamma(r, df / 2.0f64, 2.0f64) }
