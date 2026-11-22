// Low-discrepancy sequences: the Sobol sequence in up to eight dimensions
// from Joe and Kuo's direction numbers (new-joe-kuo-6.21201), in the Gray-code
// order SciPy's unscrambled `Sobol` uses (point 0 is the origin), by index or
// incrementally through `Sobol`; and the van der Corput radical inverse with
// the Halton sequence over the first sixteen primes.
//
// A Sobol coordinate carries 32 fraction bits, so indexes below 2^32 are
// distinct points.

type Sobol = struct { index: u64, x: [8]u64, dims: usize }
error Invalid
error TooSmall

// Direction number `bit` (0..32) of dimension `d` (0..8) as a 32-bit fraction.
fn direction(d: usize, bit: u32) -> u64 {
    if d == 0usize { ret 1u64 << (31u32 - bit) }
    // Primitive polynomials with both end bits, and the initial m values.
    var m: [32]u64 = zero
    var poly = 0u64
    if d == 1usize {
        poly = 3u64
        m[0usize] = 1u64
    } else if d == 2usize {
        poly = 7u64
        m[0usize] = 1u64
        m[1usize] = 3u64
    } else if d == 3usize {
        poly = 11u64
        m[0usize] = 1u64
        m[1usize] = 3u64
        m[2usize] = 1u64
    } else if d == 4usize {
        poly = 13u64
        m[0usize] = 1u64
        m[1usize] = 1u64
        m[2usize] = 1u64
    } else if d == 5usize {
        poly = 19u64
        m[0usize] = 1u64
        m[1usize] = 1u64
        m[2usize] = 3u64
        m[3usize] = 3u64
    } else if d == 6usize {
        poly = 25u64
        m[0usize] = 1u64
        m[1usize] = 3u64
        m[2usize] = 5u64
        m[3usize] = 13u64
    } else {
        poly = 37u64
        m[0usize] = 1u64
        m[1usize] = 1u64
        m[2usize] = 5u64
        m[3usize] = 5u64
        m[4usize] = 17u64
    }
    var degree = 0u32
    while (poly >> (degree + 1u32)) != 0u64 { degree += 1u32 }
    var i = usize(degree)
    while i <= usize(bit) {
        var value = m[i - usize(degree)] ^ (m[i - usize(degree)] << degree)
        var k = 1u32
        while k < degree {
            if ((poly >> (degree - k)) & 1u64) == 1u64 { value ^= m[i - usize(k)] << k }
            k += 1u32
        }
        m[i] = value
        i += 1usize
    }
    ret m[usize(bit)] << (31u32 - bit)
}

// The `index`-th Sobol point in `out.len` (at most eight) dimensions.
fn sobol(index: u64, out: []f64) -> err {
    if out.len > 8usize { ret Invalid }
    if index >= 4294967296u64 { ret Invalid }
    let gray = index ^ (index >> 1u32)
    var d = 0usize
    while d < out.len {
        var x = 0u64
        var bit = 0u32
        while bit < 32u32 {
            if ((gray >> bit) & 1u64) == 1u64 { x ^= direction(d, bit) }
            bit += 1u32
        }
        out[d] = f64(x) / 4294967296.0f64
        d += 1usize
    }
    ret ok
}

// An incremental generator positioned before point 0.
fn sobol_start(dims: usize) -> (Sobol, err) {
    if dims > 8usize { ret (Sobol { index: 0u64, x: zero, dims: 0usize }, Invalid) }
    ret (Sobol { index: 0u64, x: zero, dims: dims }, ok)
}

// The next point: point `s.index`, one direction number away from the last.
fn sobol_next(s: *Sobol, out: []f64) -> err {
    if out.len < s.dims { ret TooSmall }
    if s.index >= 4294967296u64 { ret Invalid }
    if s.index != 0u64 {
        // The lowest zero bit of the previous index picks the direction.
        let previous = s.index - 1u64
        var c = 0u32
        while ((previous >> c) & 1u64) == 1u64 { c += 1u32 }
        var d = 0usize
        while d < s.dims {
            s.x[d] ^= direction(d, c)
            d += 1usize
        }
    }
    var d = 0usize
    while d < s.dims {
        out[d] = f64(s.x[d]) / 4294967296.0f64
        d += 1usize
    }
    s.index += 1u64
    ret ok
}

// The radical inverse of `index` in `base` (at least 2): the digits mirrored
// past the point. A base below 2 has no inverse, so it answers 0.0 rather than
// dividing by zero or looping forever.
fn van_der_corput(index: u64, base: u64) -> f64 {
    if base < 2u64 { ret 0.0f64 }
    var result = 0.0f64
    var fraction = 1.0f64
    var n = index
    while n > 0u64 {
        fraction = fraction / f64(base)
        result += fraction * f64(n % base)
        n = n / base
    }
    ret result
}

// The Halton coordinate of `index` in `base`.
fn halton(index: u64, base: u64) -> f64 { ret van_der_corput(index, base) }

// The `index`-th Halton point over the first `out.len` primes (at most sixteen).
fn halton_point(index: u64, out: []f64) -> err {
    if out.len > 16usize { ret Invalid }
    var d = 0usize
    while d < out.len {
        out[d] = van_der_corput(index, prime(d))
        d += 1usize
    }
    ret ok
}

// The `d`-th prime, `d < 16`.
fn prime(d: usize) -> u64 {
    if d == 0usize { ret 2u64 }
    if d == 1usize { ret 3u64 }
    if d == 2usize { ret 5u64 }
    if d == 3usize { ret 7u64 }
    if d == 4usize { ret 11u64 }
    if d == 5usize { ret 13u64 }
    if d == 6usize { ret 17u64 }
    if d == 7usize { ret 19u64 }
    if d == 8usize { ret 23u64 }
    if d == 9usize { ret 29u64 }
    if d == 10usize { ret 31u64 }
    if d == 11usize { ret 37u64 }
    if d == 12usize { ret 41u64 }
    if d == 13usize { ret 43u64 }
    if d == 14usize { ret 47u64 }
    ret 53u64
}

// randtoolbox::congruRand: x <- (mult * x + incr) mod modulus, returning x / modulus; the state is advanced in place
fn congru_next(state: *u64, modulus: u64, mult: u64, incr: u64) -> f64 {
    let x = (mult * *state + incr) % modulus
    *state = x
    ret f64(x) / f64(modulus)
}

// (x + y) mod 1: Knuth's mod_sum for two values in [0, 1), where the C macro subtracts the truncated sum.
fn mod_one(x: f64) -> f64 {
    var s = x
    if s >= 1.0f64 { s = s - 1.0f64 }
    ret s
}

// Knuth's ranf_array for a buffer of `aa.len` values (at least 100) against the 100-value state: the first
// 100 come from the state, then the lagged subtraction, and the state is left holding the last 100 values.
fn taocp_next(aa: []f64, ran_u: []f64) {
    let kk = 100usize
    let ll = 37usize
    var j = 0usize
    while j < kk {
        aa[j] = ran_u[j]
        j += 1usize
    }
    while j < aa.len {
        aa[j] = mod_one(aa[j - kk] + aa[j - ll])
        j += 1usize
    }
    var i = 0usize
    while i < ll {
        ran_u[i] = mod_one(aa[j - kk] + aa[j - ll])
        i += 1usize
        j += 1usize
    }
    while i < kk {
        ran_u[i] = mod_one(aa[j - kk] + ran_u[i - ll])
        i += 1usize
        j += 1usize
    }
}

// Knuth's ranf_start: the seed is expanded into 199 values, the lag structure is squared and reduced with
// the seed's low bits, and ten full ranf_array passes warm the state up. ran_u holds 100 values afterwards.
fn taocp_start(seed: u64, ran_u: []f64) -> err {
    if ran_u.len < 100usize { ret TooSmall }
    var u: [199]f64 = zero
    let ulp = (1.0f64 / f64(1u64 << 30u32)) / f64(1u64 << 22u32)
    var ss = 2.0f64 * ulp * f64((seed & 1073741823u64) + 2u64)
    var j = 0usize
    while j < 100usize {
        u[j] = ss
        ss += ss
        if ss >= 1.0f64 { ss = ss - (1.0f64 - 2.0f64 * ulp) }
        j += 1usize
    }
    u[1usize] = u[1usize] + ulp
    var sd = seed & 1073741823u64
    var t = 69usize
    while t != 0usize {
        j = 99usize
        while j > 0usize {
            u[j + j] = u[j]
            u[j + j - 1usize] = 0.0f64
            j -= 1usize
        }
        j = 198usize
        while j >= 100usize {
            u[j - 63usize] = mod_one(u[j - 63usize] + u[j])
            u[j - 100usize] = mod_one(u[j - 100usize] + u[j])
            j -= 1usize
        }
        if (sd & 1u64) == 1u64 {
            j = 100usize
            while j > 0usize {
                u[j] = u[j - 1usize]
                j -= 1usize
            }
            u[0usize] = u[100usize]
            u[37usize] = mod_one(u[37usize] + u[100usize])
        }
        if sd != 0u64 {
            sd = sd >> 1u32
        } else {
            t -= 1usize
        }
    }
    j = 0usize
    while j < 37usize {
        ran_u[j + 63usize] = u[j]
        j += 1usize
    }
    while j < 100usize {
        ran_u[j - 37usize] = u[j]
        j += 1usize
    }
    var warm = 0usize
    while warm < 10usize {
        taocp_next(u[0usize..199usize], ran_u)
        warm += 1usize
    }
    ret ok
}

// randtoolbox::knuthTAOCP after setSeed(seed): the values in ranf_array order. Below 101 values it fills a
// 101-value buffer and keeps the first `out.len`, which is what randtoolbox's temp buffer does (the
// discarded values do not matter, because every call re-runs ranf_start).
fn taocp_values(seed: u64, out: []f64) -> err {
    if out.len == 0usize { ret ok }
    var ran_u: [100]f64 = zero
    let e = taocp_start(seed, ran_u[0usize..100usize])
    if e != ok { ret e }
    if out.len >= 101usize {
        taocp_next(out, ran_u[0usize..100usize])
        ret ok
    }
    var buf: [101]f64 = zero
    taocp_next(buf[0usize..101usize], ran_u[0usize..100usize])
    var i = 0usize
    while i < out.len {
        out[i] = buf[i]
        i += 1usize
    }
    ret ok
}

// qrng::korobov's generator vector when one value is given: a, a^2, ..., a^(d-1) mod n (qrng's
// generator^(0:(d-1)) %% n), a value per dimension.
fn korobov_generator(base: u64, n: u64, d: usize, out: []u64) -> err {
    if n == 0u64 { ret Invalid }
    if out.len < d { ret TooSmall }
    var x = 1u64 % n
    var j = 0usize
    while j < d {
        out[j] = x
        x = (x * (base % n)) % n
        j += 1usize
    }
    ret ok
}

// qrng::korobov with randomize = "none": out (n by d row-major) receives the sequence. Each column is a
// running sum of generator[j] / n that wraps by one when it passes 1, exactly as qrng's C does, so a point
// is (index * generator[j] mod n) / n only up to the accumulation's rounding - the wrap is `> 1`, not `>=`.
fn korobov_sequence(n: u64, generator: []const u64, d: usize, out: []f64) -> err {
    if n < 2u64 { ret Invalid }
    if generator.len < d || out.len < usize(n) * d { ret TooSmall }
    var j = 0usize
    while j < d {
        let aux = f64(generator[j]) / f64(n)
        out[j] = 0.0f64
        var i = 1usize
        while u64(i) < n {
            var v = out[(i - 1usize) * d + j] + aux
            if v > 1.0f64 { v = v - 1.0f64 }
            out[i * d + j] = v
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}
