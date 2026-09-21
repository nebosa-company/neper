// `e.math.fft` against NumPy and SciPy: an eight-point FFT and its inverse,
// a circular convolution, the NTT round trip and an exact modular convolution
// against a direct sum, the Walsh-Hadamard transform and its self-inverse,
// DCT-II against SciPy and DCT-III as its inverse, and the refusals for
// non-power-of-two lengths. Each check exits with its own code.

use e.io
use e.math.fft
use e.mem
use e.os

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.0000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var re: [8]f64 = zero
    var im: [8]f64 = zero
    var i = 0usize
    while i < 8usize {
        // 1, 2, 3, 4, 0, -1, -2, -3
        if i < 4usize { re[i] = f64(i + 1usize) } else { re[i] = 4.0f64 - f64(i) }
        i += 1usize
    }

    // 1: FFT and inverse.
    if fft.fft(re[..], im[..]) != ok { os.exit(1i32) }
    if !near(re[0usize], 4.0f64) || !near(re[1usize], 0.0f64 - 1.8284271247f64) || !near(im[1usize], 0.0f64 - 12.0710678119f64) { os.exit(1i32) }
    if !near(re[3usize], 3.8284271247f64) || !near(im[3usize], 0.0f64 - 2.0710678119f64) || !near(re[4usize], 0.0f64) || !near(im[7usize], 12.0710678119f64) { os.exit(1i32) }
    if fft.ifft(re[..], im[..]) != ok { os.exit(1i32) }
    i = 0usize
    while i < 8usize {
        var want = 4.0f64 - f64(i)
        if i < 4usize { want = f64(i + 1usize) }
        if !near(re[i], want) || !near(im[i], 0.0f64) { os.exit(1i32) }
        i += 1usize
    }
    var odd_re: [6]f64 = zero
    var odd_im: [6]f64 = zero
    if fft.fft(odd_re[..], odd_im[..]) != fft.Invalid || fft.fft(re[..], im[..7usize]) != fft.Invalid { os.exit(1i32) }

    // 2: circular convolution with [1, 0, 0, 0, 0, 0, 0, 1].
    var y: [8]f64 = zero
    y[0usize] = 1.0f64
    y[7usize] = 1.0f64
    var out: [8]f64 = zero
    var scratch: [24]f64 = zero
    if fft.convolve(re[..], y[..], out[..], scratch[..]) != ok { os.exit(2i32) }
    var expected: [8]f64 = zero
    expected[0usize] = 3.0f64
    expected[1usize] = 5.0f64
    expected[2usize] = 7.0f64
    expected[3usize] = 4.0f64
    expected[4usize] = 0.0f64 - 1.0f64
    expected[5usize] = 0.0f64 - 3.0f64
    expected[6usize] = 0.0f64 - 5.0f64
    expected[7usize] = 0.0f64 - 2.0f64
    i = 0usize
    while i < 8usize {
        if !near(out[i], expected[i]) { os.exit(2i32) }
        i += 1usize
    }
    if fft.convolve(re[..], y[..], out[..], scratch[..20usize]) != fft.TooSmall { os.exit(2i32) }

    // 3: the NTT round trip and an exact modular convolution.
    var values: [8]u64 = zero
    values[0usize] = 1u64
    values[1usize] = 2u64
    values[2usize] = 3u64
    values[3usize] = 4u64
    var original: [8]u64 = zero
    mem.copy[u64](original[..], values[..])
    if fft.ntt(values[..]) != ok { os.exit(3i32) }
    if values[0usize] != 10u64 { os.exit(3i32) }
    if fft.intt(values[..]) != ok { os.exit(3i32) }
    i = 0usize
    while i < 8usize {
        if values[i] != original[i] { os.exit(3i32) }
        i += 1usize
    }
    var other: [8]u64 = zero
    other[0usize] = 5u64
    other[1usize] = 6u64
    other[2usize] = 7u64
    var product: [8]u64 = zero
    var mod_scratch: [8]u64 = zero
    if fft.convolve_mod(original[..], other[..], product[..], mod_scratch[..]) != ok { os.exit(3i32) }
    if product[0usize] != 5u64 || product[1usize] != 16u64 || product[2usize] != 34u64 || product[3usize] != 52u64 || product[4usize] != 45u64 || product[5usize] != 28u64 || product[6usize] != 0u64 { os.exit(3i32) }
    var big: [4]u64 = zero
    big[0usize] = 998244352u64
    big[1usize] = 998244352u64
    var big_out: [4]u64 = zero
    var big_scratch: [4]u64 = zero
    if fft.convolve_mod(big[..], big[..], big_out[..], big_scratch[..]) != ok { os.exit(3i32) }
    // (-1 - x)^2 = 1 + 2x + x^2 modulo the prime.
    if big_out[0usize] != 1u64 || big_out[1usize] != 2u64 || big_out[2usize] != 1u64 || big_out[3usize] != 0u64 { os.exit(3i32) }
    var odd_values: [6]u64 = zero
    if fft.ntt(odd_values[..]) != fft.Invalid { os.exit(3i32) }

    // 4: Walsh-Hadamard.
    var bits: [8]i64 = zero
    bits[0usize] = 1i64
    bits[2usize] = 1i64
    bits[5usize] = 1i64
    bits[6usize] = 1i64
    if fft.fwht(bits[..]) != ok { os.exit(4i32) }
    if bits[0usize] != 4i64 || bits[1usize] != 2i64 || bits[2usize] != 0i64 || bits[3usize] != 0i64 - 2i64 || bits[7usize] != 2i64 { os.exit(4i32) }
    if fft.fwht(bits[..]) != ok { os.exit(4i32) }
    if bits[0usize] != 8i64 || bits[1usize] != 0i64 || bits[2usize] != 8i64 || bits[5usize] != 8i64 || bits[7usize] != 0i64 { os.exit(4i32) }
    var odd_bits: [3]i64 = zero
    if fft.fwht(odd_bits[..]) != fft.Invalid { os.exit(4i32) }

    // 5: DCT-II against SciPy and DCT-III as its inverse.
    var coefficients: [8]f64 = zero
    if fft.dct2(re[..], coefficients[..]) != ok { os.exit(5i32) }
    // SciPy's unnormalised DCT-II is twice this definition: 8, 20.50332358, -12.61728812, ..., -4.07836463.
    if !near(coefficients[0usize], 4.0f64) || !near(coefficients[1usize], 10.25166179f64) || !near(coefficients[2usize], 0.0f64 - 6.30864406f64) || !near(coefficients[7usize], 0.0f64 - 2.03918232f64) { os.exit(5i32) }
    var back: [8]f64 = zero
    if fft.dct3(coefficients[..], back[..]) != ok { os.exit(5i32) }
    i = 0usize
    while i < 8usize {
        if !near(back[i] * 2.0f64 / 8.0f64, re[i]) { os.exit(5i32) }
        i += 1usize
    }
    if fft.dct2(re[..], coefficients[..4usize]) != fft.TooSmall { os.exit(5i32) }

    try io.print("math fft ok\n")
    ret ok
}
