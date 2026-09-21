// Discrete transforms over caller storage: the radix-2 fast Fourier transform
// on separate real and imaginary slices (power-of-two lengths), the number
// theoretic transform modulo 998244353 (a primitive root of 3), the fast
// Walsh-Hadamard transform, the type II and III discrete cosine transforms,
// and convolutions built on the FFT and the NTT.
//
// The FFT is iterative (bit reversal, then butterflies) and in place; `ifft`
// divides by the length so a round trip is the identity. `dct2` and `dct3` are
// the direct `O(n^2)` sums, which is what a caller with a few hundred samples
// wants and what a longer signal should not use.

use e.math

error Invalid
error TooSmall

const MODULUS: u64 = 998244353u64
const ROOT: u64 = 3u64

fn is_power_of_two(n: usize) -> bool { ret n != 0usize && (n & (n - 1usize)) == 0usize }

// Permutes both slices into bit-reversed order.
fn bit_reverse(re: []f64, im: []f64) {
    let n = re.len
    var j = 0usize
    var i = 1usize
    while i < n {
        var bit = n >> 1usize
        while (j & bit) != 0usize {
            j = j ^ bit
            bit = bit >> 1usize
        }
        j = j ^ bit
        if i < j {
            let tr = re[i]
            re[i] = re[j]
            re[j] = tr
            let ti = im[i]
            im[i] = im[j]
            im[j] = ti
        }
        i += 1usize
    }
}

// The forward transform in place: `X[k] = sum x[n] e^(-2 pi i n k / N)`.
fn fft(re: []f64, im: []f64) -> err {
    if re.len != im.len || !is_power_of_two(re.len) { ret Invalid }
    transform(re, im, false)
    ret ok
}

// The inverse transform in place, scaled by `1 / N`.
fn ifft(re: []f64, im: []f64) -> err {
    if re.len != im.len || !is_power_of_two(re.len) { ret Invalid }
    transform(re, im, true)
    let scale = 1.0f64 / f64(re.len)
    var i = 0usize
    while i < re.len {
        re[i] = re[i] * scale
        im[i] = im[i] * scale
        i += 1usize
    }
    ret ok
}

fn transform(re: []f64, im: []f64, inverse: bool) {
    let n = re.len
    bit_reverse(re, im)
    var length = 2usize
    while length <= n {
        var angle = 0.0f64 - 6.283185307179586f64 / f64(length)
        if inverse { angle = 0.0f64 - angle }
        let wr = math.cos[f64](angle)
        let wi = math.sin[f64](angle)
        var start = 0usize
        while start < n {
            var cr = 1.0f64
            var ci = 0.0f64
            var k = 0usize
            while k < length / 2usize {
                let a = start + k
                let b = a + length / 2usize
                let xr = re[b] * cr - im[b] * ci
                let xi = re[b] * ci + im[b] * cr
                re[b] = re[a] - xr
                im[b] = im[a] - xi
                re[a] = re[a] + xr
                im[a] = im[a] + xi
                let next_cr = cr * wr - ci * wi
                ci = cr * wi + ci * wr
                cr = next_cr
                k += 1usize
            }
            start += length
        }
        length = length * 2usize
    }
}

// The circular convolution of two real signals of equal power-of-two length,
// written to `out`; `scratch.len >= 3 * n`.
fn convolve(x: []const f64, y: []const f64, out: []f64, scratch: []f64) -> err {
    let n = x.len
    if y.len != n || out.len < n || !is_power_of_two(n) { ret Invalid }
    if scratch.len < 3usize * n { ret TooSmall }
    var xr = out[..n]
    var xi = scratch[..n]
    var yr = scratch[n..2usize * n]
    var yi = scratch[2usize * n..3usize * n]
    var i = 0usize
    while i < n {
        xr[i] = x[i]
        xi[i] = 0.0f64
        yr[i] = y[i]
        yi[i] = 0.0f64
        i += 1usize
    }
    transform(xr, xi, false)
    transform(yr, yi, false)
    i = 0usize
    while i < n {
        let pr = xr[i] * yr[i] - xi[i] * yi[i]
        let pi = xr[i] * yi[i] + xi[i] * yr[i]
        xr[i] = pr
        xi[i] = pi
        i += 1usize
    }
    transform(xr, xi, true)
    let scale = 1.0f64 / f64(n)
    i = 0usize
    while i < n {
        xr[i] = xr[i] * scale
        i += 1usize
    }
    ret ok
}

fn mul_mod(a: u64, b: u64) -> u64 { ret a % MODULUS * (b % MODULUS) % MODULUS }

fn pow_mod(base: u64, exponent: u64) -> u64 {
    var result = 1u64
    var b = base % MODULUS
    var e = exponent
    while e != 0u64 {
        if (e & 1u64) == 1u64 { result = mul_mod(result, b) }
        b = mul_mod(b, b)
        e = e >> 1u64
    }
    ret result
}

// The number theoretic transform modulo 998244353 in place; `values.len` a
// power of two at most `2^23`.
fn ntt(values: []u64) -> err {
    if !is_power_of_two(values.len) || values.len > 8388608usize { ret Invalid }
    ntt_transform(values, false)
    ret ok
}

fn intt(values: []u64) -> err {
    if !is_power_of_two(values.len) || values.len > 8388608usize { ret Invalid }
    ntt_transform(values, true)
    let inverse_n = pow_mod(u64(values.len), MODULUS - 2u64)
    var i = 0usize
    while i < values.len {
        values[i] = mul_mod(values[i], inverse_n)
        i += 1usize
    }
    ret ok
}

fn ntt_transform(values: []u64, inverse: bool) {
    let n = values.len
    var j = 0usize
    var i = 1usize
    while i < n {
        var bit = n >> 1usize
        while (j & bit) != 0usize {
            j = j ^ bit
            bit = bit >> 1usize
        }
        j = j ^ bit
        if i < j {
            let t = values[i]
            values[i] = values[j]
            values[j] = t
        }
        i += 1usize
    }
    var length = 2usize
    while length <= n {
        var w = pow_mod(ROOT, (MODULUS - 1u64) / u64(length))
        if inverse { w = pow_mod(w, MODULUS - 2u64) }
        var start = 0usize
        while start < n {
            var factor = 1u64
            var k = 0usize
            while k < length / 2usize {
                let a = start + k
                let b = a + length / 2usize
                let u = values[a]
                let v = mul_mod(values[b], factor)
                values[a] = (u + v) % MODULUS
                values[b] = (u + MODULUS - v) % MODULUS
                factor = mul_mod(factor, w)
                k += 1usize
            }
            start += length
        }
        length = length * 2usize
    }
}

// The exact cyclic convolution of two integer sequences modulo 998244353,
// written to `out`; `scratch.len >= n`.
fn convolve_mod(x: []const u64, y: []const u64, out: []u64, scratch: []u64) -> err {
    let n = x.len
    if y.len != n || out.len < n || !is_power_of_two(n) { ret Invalid }
    if scratch.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = x[i] % MODULUS
        scratch[i] = y[i] % MODULUS
        i += 1usize
    }
    ntt_transform(out[..n], false)
    ntt_transform(scratch[..n], false)
    i = 0usize
    while i < n {
        out[i] = mul_mod(out[i], scratch[i])
        i += 1usize
    }
    ntt_transform(out[..n], true)
    let inverse_n = pow_mod(u64(n), MODULUS - 2u64)
    i = 0usize
    while i < n {
        out[i] = mul_mod(out[i], inverse_n)
        i += 1usize
    }
    ret ok
}

// The fast Walsh-Hadamard transform in place (unnormalised; applying it twice
// gives `n` times the input).
fn fwht(values: []i64) -> err {
    if !is_power_of_two(values.len) { ret Invalid }
    var length = 1usize
    while length < values.len {
        var start = 0usize
        while start < values.len {
            var k = 0usize
            while k < length {
                let a = values[start + k]
                let b = values[start + k + length]
                values[start + k] = a + b
                values[start + k + length] = a - b
                k += 1usize
            }
            start += length * 2usize
        }
        length = length * 2usize
    }
    ret ok
}

// DCT-II: `X[k] = sum x[n] cos(pi (n + 1/2) k / N)`, unnormalised, `out.len >= x.len`.
fn dct2(x: []const f64, out: []f64) -> err {
    let n = x.len
    if out.len < n { ret TooSmall }
    var k = 0usize
    while k < n {
        var sum = 0.0f64
        var i = 0usize
        while i < n {
            sum += x[i] * math.cos[f64](3.141592653589793f64 * (f64(i) + 0.5f64) * f64(k) / f64(n))
            i += 1usize
        }
        out[k] = sum
        k += 1usize
    }
    ret ok
}

// DCT-III, the inverse of `dct2` up to the factor `2 / N`:
// `x[n] = X[0] / 2 + sum_{k >= 1} X[k] cos(pi k (n + 1/2) / N)`.
fn dct3(x: []const f64, out: []f64) -> err {
    let n = x.len
    if out.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        var sum = x[0usize] / 2.0f64
        var k = 1usize
        while k < n {
            sum += x[k] * math.cos[f64](3.141592653589793f64 * f64(k) * (f64(i) + 0.5f64) / f64(n))
            k += 1usize
        }
        out[i] = sum
        i += 1usize
    }
    ret ok
}
