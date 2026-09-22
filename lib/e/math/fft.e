// Discrete transforms over caller storage: the radix-2 fast Fourier transform
// on separate real and imaginary slices (power-of-two lengths), the number
// theoretic transform modulo 998244353 (a primitive root of 3), the fast
// Walsh-Hadamard transform, the type II, III and IV discrete cosine
// transforms (`dct` adds SciPy's orthonormal scaling), the windowed MDCT with
// its overlap-add inverse, the periodised Haar and Daubechies-4 wavelet
// transforms one level and many, and convolutions built on the FFT and the NTT.
//
// The FFT is iterative (bit reversal, then butterflies) and in place; `ifft`
// divides by the length so a round trip is the identity. The cosine transforms
// and the MDCT are the direct `O(n^2)` sums, which is what a caller with a few
// hundred samples wants and what a longer signal should not use.

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

// DCT-IV: `X[k] = sum x[n] cos(pi (n + 1/2) (k + 1/2) / N)`, unnormalised and
// its own inverse up to `2 / N`; `out.len >= x.len`.
fn dct4(x: []const f64, out: []f64) -> err {
    let n = x.len
    if out.len < n { ret TooSmall }
    var k = 0usize
    while k < n {
        var sum = 0.0f64
        var i = 0usize
        while i < n {
            sum += x[i] * math.cos[f64](3.141592653589793f64 * (f64(i) + 0.5f64) * (f64(k) + 0.5f64) / f64(n))
            i += 1usize
        }
        out[k] = sum
        k += 1usize
    }
    ret ok
}

// The DCT of `kind` 2, 3 or 4: unnormalised it is `dct2`, `dct3` or `dct4`;
// with `ortho` it is SciPy's `norm='ortho'` (each kind orthonormal, so the
// kind 2 and 3 pair and kind 4 with itself invert exactly).
fn dct(x: []const f64, out: []f64, kind: u8, ortho: bool) -> err {
    let n = x.len
    if n == 0usize { ret Invalid }
    var e = ok
    if kind == 2u8 { e = dct2(x, out) } else if kind == 3u8 { e = dct3(x, out) } else if kind == 4u8 { e = dct4(x, out) } else { ret Invalid }
    if e != ok { ret e }
    if !ortho { ret ok }
    let scale = math.sqrt[f64](2.0f64 / f64(n))
    // Kind 3 keeps `x[0] / 2` in every output; orthonormal wants `x[0] / sqrt(2)`.
    var shift = 0.0f64
    if kind == 3u8 { shift = x[0usize] * (0.7071067811865476f64 - 0.5f64) }
    var i = 0usize
    while i < n {
        out[i] = (out[i] + shift) * scale
        i += 1usize
    }
    if kind == 2u8 { out[0usize] = out[0usize] * 0.7071067811865476f64 }
    ret ok
}

// The sine window `sin(pi (n + 1/2) / length)` (Princen-Bradley, so
// `w[n]^2 + w[n + N]^2 = 1` over a `2N` frame).
fn sine_window(i: usize, length: usize) -> f64 { ret math.sin[f64](3.141592653589793f64 * (f64(i) + 0.5f64) / f64(length)) }

// Fills `out` with the MDCT sine window of its own length (`2N` for an
// `N`-coefficient transform).
fn mdct_window(out: []f64) {
    var i = 0usize
    while i < out.len {
        out[i] = sine_window(i, out.len)
        i += 1usize
    }
}

// The windowed MDCT of a `2N`-sample frame into `N` coefficients:
// `X[k] = sum w[n] x[n] cos(pi / N (n + 1/2 + N/2) (k + 1/2))`; frames advance
// by `N` and `imdct` plus overlap-add reconstructs each middle `N` exactly.
fn mdct(frame: []const f64, out: []f64) -> err {
    let n = frame.len / 2usize
    if n == 0usize || frame.len != 2usize * n { ret Invalid }
    if out.len < n { ret TooSmall }
    var k = 0usize
    while k < n {
        var sum = 0.0f64
        var i = 0usize
        while i < 2usize * n {
            sum += sine_window(i, 2usize * n) * frame[i] * math.cos[f64](3.141592653589793f64 / f64(n) * (f64(i) + 0.5f64 + f64(n) / 2.0f64) * (f64(k) + 0.5f64))
            i += 1usize
        }
        out[k] = sum
        k += 1usize
    }
    ret ok
}

// The inverse MDCT of `N` coefficients into a windowed `2N`-sample frame
// (`y[n] = 2 w[n] / N sum X[k] cos(...)`); overlap-adding the second half of
// one frame with the first half of the next recovers the signal.
fn imdct(coefficients: []const f64, out: []f64) -> err {
    let n = coefficients.len
    if n == 0usize { ret Invalid }
    if out.len < 2usize * n { ret TooSmall }
    var i = 0usize
    while i < 2usize * n {
        var sum = 0.0f64
        var k = 0usize
        while k < n {
            sum += coefficients[k] * math.cos[f64](3.141592653589793f64 / f64(n) * (f64(i) + 0.5f64 + f64(n) / 2.0f64) * (f64(k) + 0.5f64))
            k += 1usize
        }
        out[i] = sine_window(i, 2usize * n) * sum * 2.0f64 / f64(n)
        i += 1usize
    }
    ret ok
}

// The wavelet filter banks: Haar (two taps) and Daubechies-4 (eight taps).
type Wavelet = enum u8 { Haar, Db4 }

// Writes the decomposition low-pass filter into `lo` and answers its length;
// the high-pass is `hi[j] = (-1)^(j + 1) lo[F - 1 - j]` and reconstruction
// reverses both (PyWavelets' `dec_lo`).
fn wavelet_lowpass(wavelet: Wavelet, lo: []f64) -> usize {
    if wavelet == .Haar {
        lo[0usize] = 0.7071067811865476f64
        lo[1usize] = 0.7071067811865476f64
        ret 2usize
    }
    lo[0usize] = 0.0f64 - 0.010597401785069032f64
    lo[1usize] = 0.0328830116668852f64
    lo[2usize] = 0.030841381835560764f64
    lo[3usize] = 0.0f64 - 0.18703481171909309f64
    lo[4usize] = 0.0f64 - 0.027983769416859854f64
    lo[5usize] = 0.6308807679298589f64
    lo[6usize] = 0.7148465705529157f64
    lo[7usize] = 0.2303778133088965f64
    ret 8usize
}

fn wavelet_highpass(lo: []const f64, taps: usize, j: usize) -> f64 {
    if (j & 1usize) == 1usize { ret lo[taps - 1usize - j] }
    ret 0.0f64 - lo[taps - 1usize - j]
}

// One level of the discrete wavelet transform with periodic extension
// (PyWavelets' `mode='periodization'`): `x.len` even, `approx` and `detail`
// each `x.len / 2` long.
fn dwt(x: []const f64, wavelet: Wavelet, approx: []f64, detail: []f64) -> err {
    let n = x.len
    let half = n / 2usize
    if n == 0usize || n != 2usize * half { ret Invalid }
    if approx.len < half || detail.len < half { ret TooSmall }
    var lo: [8]f64 = zero
    let taps = wavelet_lowpass(wavelet, lo[..])
    var k = 0usize
    while k < half {
        var sa = 0.0f64
        var sd = 0.0f64
        var j = 0usize
        while j < taps {
            let v = x[(2usize * k + taps / 2usize + n * taps - j) % n]
            sa += lo[j] * v
            sd += wavelet_highpass(lo[..], taps, j) * v
            j += 1usize
        }
        approx[k] = sa
        detail[k] = sd
        k += 1usize
    }
    ret ok
}

// The inverse of `dwt`: `out.len >= 2 * approx.len`.
fn idwt(approx: []const f64, detail: []const f64, wavelet: Wavelet, out: []f64) -> err {
    let half = approx.len
    let n = 2usize * half
    if half == 0usize || detail.len < half { ret Invalid }
    if out.len < n { ret TooSmall }
    var lo: [8]f64 = zero
    let taps = wavelet_lowpass(wavelet, lo[..])
    var i = 0usize
    while i < n {
        out[i] = 0.0f64
        i += 1usize
    }
    var k = 0usize
    while k < half {
        var j = 0usize
        while j < taps {
            let at_index = (2usize * k + j + n * taps + 1usize - taps / 2usize) % n
            let rj = taps - 1usize - j
            out[at_index] += lo[rj] * approx[k] + wavelet_highpass(lo[..], taps, rj) * detail[k]
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

// The multi-level decomposition into `out` (`x.len` entries): the coarsest
// approximation first, then the details from coarsest to finest, as
// PyWavelets' `wavedec` lists them; `x.len` divisible by `2^levels`,
// `scratch.len >= x.len`.
fn wavedec(x: []const f64, wavelet: Wavelet, levels: usize, out: []f64, scratch: []f64) -> err {
    let n = x.len
    if levels == 0usize || n == 0usize || (n >> u32(levels)) << u32(levels) != n { ret Invalid }
    if out.len < n || scratch.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = x[i]
        i += 1usize
    }
    var length = n
    var level = 0usize
    while level < levels {
        let half = length / 2usize
        let e = dwt(out[..length], wavelet, scratch[..half], scratch[half..length])
        if e != ok { ret e }
        i = 0usize
        while i < length {
            out[i] = scratch[i]
            i += 1usize
        }
        length = half
        level += 1usize
    }
    ret ok
}

// The inverse of `wavedec` from the same layout; `scratch.len >= coefficients.len`.
fn waverec(coefficients: []const f64, wavelet: Wavelet, levels: usize, out: []f64, scratch: []f64) -> err {
    let n = coefficients.len
    if levels == 0usize || n == 0usize || (n >> u32(levels)) << u32(levels) != n { ret Invalid }
    if out.len < n || scratch.len < n { ret TooSmall }
    var length = n >> u32(levels)
    var i = 0usize
    while i < length {
        out[i] = coefficients[i]
        i += 1usize
    }
    while length < n {
        let e = idwt(out[..length], coefficients[length..2usize * length], wavelet, scratch[..2usize * length])
        if e != ok { ret e }
        i = 0usize
        while i < 2usize * length {
            out[i] = scratch[i]
            i += 1usize
        }
        length = length * 2usize
    }
    ret ok
}
