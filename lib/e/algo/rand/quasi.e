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
// past the point.
fn van_der_corput(index: u64, base: u64) -> f64 {
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
