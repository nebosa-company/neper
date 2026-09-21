// Signal processing over caller `[]f64` storage: smoothing (moving average,
// exponential, Savitzky-Golay), FIR and IIR filtering, the classic IIR designs
// (Butterworth, Chebyshev I, elliptic, Bessel) through the bilinear transform,
// windowed-sinc and Parks-McClellan FIR design, window functions, the STFT and
// its overlap-add inverse, MFCC, a constant-Q transform, the real cepstrum,
// LPC through Levinson-Durbin, dynamic time warping, delay lines (comb,
// one-pole, biquad), spectral subtraction and Wiener denoising, the LMS, NLMS
// and RLS adaptive filters, and polyphase and sinc resampling.
//
// A frequency is a fraction of the Nyquist rate (`1.0` is half the sample
// rate) unless a sample rate is passed. FFT lengths are powers of two. Complex
// values travel as separate real and imaginary slices. Filter coefficients are
// `b` (numerator) and `a` (denominator, `a[0]` normalises), highest power of
// `z^-1` last, as SciPy writes them.

use e.math
use e.math.fft
use e.math.filter

error Invalid
error TooSmall
error NoConvergence

type Window = enum u8 { Rectangular, Hann, Hamming, Blackman }

fn ipow(t: f64, e: usize) -> f64 {
    var r = 1.0f64
    var i = 0usize
    while i < e {
        r = r * t
        i += 1usize
    }
    ret r
}

fn coefficient(c: []const f64, i: usize) -> f64 {
    if i < c.len { ret c[i] }
    ret 0.0f64
}

fn sinc(t: f64) -> f64 {
    if t == 0.0f64 { ret 1.0f64 }
    let p = 3.141592653589793f64 * t
    ret math.sin[f64](p) / p
}

fn asinh(x: f64) -> f64 { ret math.log[f64](x + math.sqrt[f64](x * x + 1.0f64)) }

fn clear(xs: []f64) {
    var i = 0usize
    while i < xs.len {
        xs[i] = 0.0f64
        i += 1usize
    }
}

// --- smoothing ---------------------------------------------------------------

// The mean of every window of `k` samples ("valid" mode): `out.len >= x.len - k + 1`.
fn moving_average(x: []const f64, k: usize, out: []f64) -> err {
    if k == 0usize || k > x.len { ret Invalid }
    let count = x.len - k + 1usize
    if out.len < count { ret TooSmall }
    var sum = 0.0f64
    var i = 0usize
    while i < k {
        sum += x[i]
        i += 1usize
    }
    i = 0usize
    while i < count {
        out[i] = sum / f64(k)
        if i + 1usize < count { sum += x[i + k] - x[i] }
        i += 1usize
    }
    ret ok
}

// `y[n] = alpha x[n] + (1 - alpha) y[n - 1]`, seeded with `x[0]`.
fn ema(x: []const f64, alpha: f64, out: []f64) -> err {
    if out.len < x.len { ret TooSmall }
    var i = 0usize
    while i < x.len {
        if i == 0usize { out[0usize] = x[0usize] } else { out[i] = alpha * x[i] + (1.0f64 - alpha) * out[i - 1usize] }
        i += 1usize
    }
    ret ok
}

// The least-squares smoothing coefficients of an odd `width` and polynomial
// `order` into `out` (`out.len >= width`); `scratch.len >= 3 * (order + 1)^2`.
fn savitzky_golay_coefficients(width: usize, order: usize, out: []f64, scratch: []f64) -> err {
    let m = order + 1usize
    if width % 2usize == 0usize || width <= order { ret Invalid }
    if out.len < width || scratch.len < 3usize * m * m { ret TooSmall }
    var vtv = scratch[..m * m]
    var inv = scratch[m * m..2usize * m * m]
    let half = f64(width / 2usize)
    var r = 0usize
    while r < m {
        var c = 0usize
        while c < m {
            var sum = 0.0f64
            var i = 0usize
            while i < width {
                sum += ipow(f64(i) - half, r + c)
                i += 1usize
            }
            vtv[r * m + c] = sum
            c += 1usize
        }
        r += 1usize
    }
    if filter.mat_inverse(vtv, inv, m, scratch[2usize * m * m..3usize * m * m]) != ok { ret Invalid }
    var i = 0usize
    while i < width {
        var sum = 0.0f64
        var c = 0usize
        while c < m {
            sum += ipow(f64(i) - half, c) * inv[c * m]
            c += 1usize
        }
        out[i] = sum
        i += 1usize
    }
    ret ok
}

// Savitzky-Golay smoothing with zero padding at the edges (SciPy's
// `mode="constant"`); `scratch.len >= width + 3 * (order + 1)^2`.
fn savitzky_golay(x: []const f64, width: usize, order: usize, out: []f64, scratch: []f64) -> err {
    if out.len < x.len || scratch.len < width { ret TooSmall }
    let coefficients_error = savitzky_golay_coefficients(width, order, scratch[..width], scratch[width..])
    if coefficients_error != ok { ret coefficients_error }
    let half = width / 2usize
    var i = 0usize
    while i < x.len {
        var sum = 0.0f64
        var j = 0usize
        while j < width {
            if i + j >= half && i + j - half < x.len { sum += scratch[j] * x[i + j - half] }
            j += 1usize
        }
        out[i] = sum
        i += 1usize
    }
    ret ok
}

// The number of sign changes between neighbours (zero counts as positive).
fn zero_crossings(x: []const f64) -> usize {
    var count = 0usize
    var i = 1usize
    while i < x.len {
        if (x[i] < 0.0f64) != (x[i - 1usize] < 0.0f64) { count += 1usize }
        i += 1usize
    }
    ret count
}

// --- filtering ---------------------------------------------------------------

// Direct convolution with zero history: `out.len >= x.len`.
fn fir(x: []const f64, taps: []const f64, out: []f64) -> err {
    if out.len < x.len { ret TooSmall }
    var n = 0usize
    while n < x.len {
        var sum = 0.0f64
        var k = 0usize
        while k < taps.len && k <= n {
            sum += taps[k] * x[n - k]
            k += 1usize
        }
        out[n] = sum
        n += 1usize
    }
    ret ok
}

// Direct form II transposed with zero initial state; `state.len >=
// max(a.len, b.len) - 1`, cleared by the call and left holding the final state.
fn iir(x: []const f64, b: []const f64, a: []const f64, out: []f64, state: []f64) -> err {
    var order = b.len
    if a.len > order { order = a.len }
    if order == 0usize || a[0usize] == 0.0f64 { ret Invalid }
    if out.len < x.len || state.len + 1usize < order { ret TooSmall }
    order -= 1usize
    var z = state[..order]
    clear(z)
    let a0 = a[0usize]
    var n = 0usize
    while n < x.len {
        var y = coefficient(b, 0usize) * x[n]
        if order > 0usize { y += z[0usize] }
        y = y / a0
        var i = 0usize
        while i < order {
            var acc = coefficient(b, i + 1usize) * x[n] - coefficient(a, i + 1usize) * y
            if i + 1usize < order { acc += z[i + 1usize] }
            z[i] = acc
            i += 1usize
        }
        out[n] = y
        n += 1usize
    }
    ret ok
}

// `y[n] = (1 - c) x[n] + c y[n - 1]`.
fn one_pole(x: []const f64, c: f64, out: []f64) -> err {
    if out.len < x.len { ret TooSmall }
    var n = 0usize
    while n < x.len {
        var y = (1.0f64 - c) * x[n]
        if n > 0usize { y += c * out[n - 1usize] }
        out[n] = y
        n += 1usize
    }
    ret ok
}

// Feedforward `y[n] = x[n] + g x[n - d]` or feedback `y[n] = x[n] + g y[n - d]`.
fn comb(x: []const f64, delay: usize, gain: f64, out: []f64, feedforward: bool) -> err {
    if delay == 0usize { ret Invalid }
    if out.len < x.len { ret TooSmall }
    var n = 0usize
    while n < x.len {
        var y = x[n]
        if n >= delay {
            if feedforward { y += gain * x[n - delay] } else { y += gain * out[n - delay] }
        }
        out[n] = y
        n += 1usize
    }
    ret ok
}

// A second-order section over `c = [b0, b1, b2, a0, a1, a2]`; `state.len >= 2`.
fn biquad(x: []const f64, c: []const f64, out: []f64, state: []f64) -> err {
    if c.len < 6usize { ret TooSmall }
    ret iir(x, c[..3usize], c[3usize..6usize], out, state)
}

// Audio EQ Cookbook coefficients into `out` (six entries); `frequency` is a
// fraction of Nyquist, `gain_db` only matters for the peaking filter.
fn biquad_cookbook(kind: u8, frequency: f64, q: f64, gain_db: f64, out: []f64) -> err {
    if out.len < 6usize { ret TooSmall }
    let w0 = 3.141592653589793f64 * frequency
    let cw = math.cos[f64](w0)
    let alpha = math.sin[f64](w0) / (2.0f64 * q)
    out[4usize] = -2.0f64 * cw
    if kind == 0u8 {
        out[0usize] = (1.0f64 - cw) / 2.0f64
        out[1usize] = 1.0f64 - cw
        out[2usize] = out[0usize]
        out[3usize] = 1.0f64 + alpha
        out[5usize] = 1.0f64 - alpha
    } else if kind == 1u8 {
        out[0usize] = (1.0f64 + cw) / 2.0f64
        out[1usize] = 0.0f64 - (1.0f64 + cw)
        out[2usize] = out[0usize]
        out[3usize] = 1.0f64 + alpha
        out[5usize] = 1.0f64 - alpha
    } else {
        let amp = math.exp[f64](gain_db / 40.0f64 * 2.302585092994046f64)
        out[0usize] = 1.0f64 + alpha * amp
        out[1usize] = out[4usize]
        out[2usize] = 1.0f64 - alpha * amp
        out[3usize] = 1.0f64 + alpha / amp
        out[5usize] = 1.0f64 - alpha / amp
    }
    ret ok
}

fn biquad_lowpass(frequency: f64, q: f64, out: []f64) -> err { ret biquad_cookbook(0u8, frequency, q, 0.0f64, out) }
fn biquad_highpass(frequency: f64, q: f64, out: []f64) -> err { ret biquad_cookbook(1u8, frequency, q, 0.0f64, out) }
fn biquad_peak(frequency: f64, q: f64, gain_db: f64, out: []f64) -> err { ret biquad_cookbook(2u8, frequency, q, gain_db, out) }

// --- windows and FIR design ---------------------------------------------------

// A symmetric window of `n` samples (SciPy's `get_window(kind, n, fftbins=False)`).
fn window(kind: Window, n: usize, out: []f64) -> err {
    if out.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        var phase = 0.0f64
        if n > 1usize { phase = 6.283185307179586f64 * f64(i) / f64(n - 1usize) }
        var w = 1.0f64
        if kind == .Hann { w = 0.5f64 - 0.5f64 * math.cos[f64](phase) }
        if kind == .Hamming { w = 0.54f64 - 0.46f64 * math.cos[f64](phase) }
        if kind == .Blackman { w = 0.42f64 - 0.5f64 * math.cos[f64](phase) + 0.08f64 * math.cos[f64](2.0f64 * phase) }
        out[i] = w
        i += 1usize
    }
    ret ok
}

// A windowed-sinc low-pass of `taps` coefficients with unit DC gain
// (SciPy's `firwin(taps, cutoff, window=kind)`).
fn design_windowed_sinc(taps: usize, cutoff: f64, kind: Window, out: []f64) -> err {
    if taps == 0usize || cutoff <= 0.0f64 || cutoff >= 1.0f64 { ret Invalid }
    let window_error = window(kind, taps, out)
    if window_error != ok { ret window_error }
    let centre = f64(taps - 1usize) / 2.0f64
    var sum = 0.0f64
    var i = 0usize
    while i < taps {
        out[i] = out[i] * cutoff * sinc(cutoff * (f64(i) - centre))
        sum += out[i]
        i += 1usize
    }
    i = 0usize
    while i < taps {
        out[i] = out[i] / sum
        i += 1usize
    }
    ret ok
}

// The interpolant through the extremal set at `x = cos(2 pi f)`.
fn remez_value(x: f64, xs: []const f64, ys: []const f64, ad: []const f64) -> f64 {
    var num = 0.0f64
    var den = 0.0f64
    var k = 0usize
    while k < xs.len {
        let d = x - xs[k]
        if d == 0.0f64 { ret ys[k] }
        num += ad[k] * ys[k] / d
        den += ad[k] / d
        k += 1usize
    }
    ret num / den
}

// Equiripple linear-phase FIR of odd `taps` by the Remez exchange over SciPy's
// grid (density 16): `bands` holds pairs of edges in [0, 1] (Nyquist units),
// `desired` and `weights` one value per band; `out.len >= taps`,
// `scratch.len >= 48 * taps + 12 * bands.len + 64`.
fn design_parks_mcclellan(taps: usize, bands: []const f64, desired: []const f64, weights: []const f64, out: []f64, scratch: []f64) -> err {
    let nbands = bands.len / 2usize
    if taps < 3usize || taps % 2usize == 0usize || nbands == 0usize || desired.len < nbands || weights.len < nbands { ret Invalid }
    let r = taps / 2usize + 1usize
    let cap = 16usize * r + 2usize * nbands + 2usize
    if out.len < taps || scratch.len < 5usize * cap + 5usize * (r + 1usize) + nbands + 1usize { ret TooSmall }
    var grid = scratch[..cap]
    var des = scratch[cap..2usize * cap]
    var wt = scratch[2usize * cap..3usize * cap]
    var e = scratch[3usize * cap..4usize * cap]
    let base = 4usize * cap
    var xs = scratch[base..base + r + 1usize]
    var ys = scratch[base + r + 1usize..base + 2usize * (r + 1usize)]
    var ad = scratch[base + 2usize * (r + 1usize)..base + 3usize * (r + 1usize)]
    var ext = scratch[base + 3usize * (r + 1usize)..base + 4usize * (r + 1usize)]
    var coefficients = scratch[base + 4usize * (r + 1usize)..base + 5usize * (r + 1usize)]
    var starts = scratch[base + 5usize * (r + 1usize)..base + 5usize * (r + 1usize) + nbands + 1usize]
    var found = scratch[base + 5usize * (r + 1usize) + nbands + 1usize..base + 5usize * (r + 1usize) + nbands + 1usize + cap]
    // The grid.
    let delf = 0.5f64 / (16.0f64 * f64(r))
    var ngrid = 0usize
    var l = 0usize
    while l < nbands {
        let fup = bands[2usize * l + 1usize] / 2.0f64
        var f = bands[2usize * l] / 2.0f64
        if f > fup || (l > 0usize && f < bands[2usize * l - 1usize] / 2.0f64) { ret Invalid }
        starts[l] = f64(ngrid)
        var more = true
        while more {
            if ngrid >= cap { ret TooSmall }
            grid[ngrid] = f
            des[ngrid] = desired[l]
            wt[ngrid] = weights[l]
            ngrid += 1usize
            f = f + delf
            more = f <= fup
        }
        grid[ngrid - 1usize] = fup
        l += 1usize
    }
    starts[nbands] = f64(ngrid)
    if ngrid < r + 1usize { ret Invalid }
    var k = 0usize
    while k <= r {
        ext[k] = f64((k * (ngrid - 1usize)) / r)
        k += 1usize
    }
    var iteration = 0usize
    var converged = false
    var delta = 0.0f64
    while !converged && iteration < 40usize {
        // Barycentric weights and the deviation.
        k = 0usize
        while k <= r {
            xs[k] = math.cos[f64](6.283185307179586f64 * grid[usize(ext[k])])
            k += 1usize
        }
        var num = 0.0f64
        var den = 0.0f64
        k = 0usize
        while k <= r {
            var prod = 1.0f64
            var mm = 0usize
            while mm <= r {
                if mm != k { prod = prod * (xs[k] - xs[mm]) }
                mm += 1usize
            }
            ad[k] = 1.0f64 / prod
            let gi = usize(ext[k])
            num += ad[k] * des[gi]
            if k % 2usize == 0usize { den += ad[k] / wt[gi] } else { den -= ad[k] / wt[gi] }
            k += 1usize
        }
        delta = num / den
        k = 0usize
        while k <= r {
            let gj = usize(ext[k])
            if k % 2usize == 0usize { ys[k] = des[gj] - delta / wt[gj] } else { ys[k] = des[gj] + delta / wt[gj] }
            k += 1usize
        }
        // The weighted error on the grid.
        var g = 0usize
        while g < ngrid {
            e[g] = wt[g] * (remez_value(math.cos[f64](6.283185307179586f64 * grid[g]), xs, ys, ad) - des[g])
            g += 1usize
        }
        // Local extrema per band, merged into an alternating sequence.
        var count = 0usize
        l = 0usize
        while l < nbands {
            let s = usize(starts[l])
            let t = usize(starts[l + 1usize])
            g = s
            while g < t {
                let up = e[g] > 0.0f64
                var peak = e[g] != 0.0f64
                if g > s && ((up && e[g - 1usize] > e[g]) || (!up && e[g - 1usize] < e[g])) { peak = false }
                if g + 1usize < t && ((up && e[g + 1usize] > e[g]) || (!up && e[g + 1usize] < e[g])) { peak = false }
                if peak {
                    if count > 0usize && (e[usize(found[count - 1usize])] > 0.0f64) == up {
                        if math.abs[f64](e[g]) > math.abs[f64](e[usize(found[count - 1usize])]) { found[count - 1usize] = f64(g) }
                    } else {
                        found[count] = f64(g)
                        count += 1usize
                    }
                }
                g += 1usize
            }
            l += 1usize
        }
        // Too many: drop the weaker endpoint when one is spare, else the
        // adjacent pair with the smallest larger error (alternation survives).
        while count > r + 1usize {
            var drop = 0usize
            var width = 1usize
            if count == r + 2usize {
                if math.abs[f64](e[usize(found[0usize])]) >= math.abs[f64](e[usize(found[count - 1usize])]) { drop = count - 1usize }
            } else {
                width = 2usize
                var best = 0.0f64
                var j = 0usize
                while j + 1usize < count {
                    var larger = math.abs[f64](e[usize(found[j])])
                    if math.abs[f64](e[usize(found[j + 1usize])]) > larger { larger = math.abs[f64](e[usize(found[j + 1usize])]) }
                    if j == 0usize || larger < best {
                        best = larger
                        drop = j
                    }
                    j += 1usize
                }
            }
            var j2 = drop
            while j2 + width < count {
                found[j2] = found[j2 + width]
                j2 += 1usize
            }
            count -= width
        }
        if count < r + 1usize { ret NoConvergence }
        converged = true
        k = 0usize
        while k <= r {
            if found[k] != ext[k] { converged = false }
            ext[k] = found[k]
            k += 1usize
        }
        iteration += 1usize
    }
    if !converged { ret NoConvergence }
    // Cosine coefficients from samples at f = j / (2r - 1), then the impulse response.
    let samples = 2usize * r - 1usize
    k = 0usize
    while k < r {
        coefficients[k] = remez_value(math.cos[f64](6.283185307179586f64 * f64(k) / f64(samples)), xs, ys, ad)
        k += 1usize
    }
    k = 0usize
    while k < r {
        var sum = coefficients[0usize]
        var j = 1usize
        while j < r {
            sum += 2.0f64 * coefficients[j] * math.cos[f64](6.283185307179586f64 * f64(k * j) / f64(samples))
            j += 1usize
        }
        let value = sum / f64(samples)
        if k == 0usize { out[r - 1usize] = value } else {
            out[r - 1usize + k] = value
            out[r - 1usize - k] = value
        }
        k += 1usize
    }
    ret ok
}

// --- IIR design ---------------------------------------------------------------

fn cmul(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64) { ret (ar * br - ai * bi, ar * bi + ai * br) }

fn cdiv(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64) {
    let d = br * br + bi * bi
    ret ((ar * br + ai * bi) / d, (ai * br - ar * bi) / d)
}

// The coefficients of `prod (z - r_j)`, highest power first, into `cr`/`ci`
// (`rr.len + 1` entries each).
fn poly(rr: []const f64, ri: []const f64, cr: []f64, ci: []f64) {
    cr[0usize] = 1.0f64
    ci[0usize] = 0.0f64
    var j = 0usize
    while j < rr.len {
        cr[j + 1usize] = 0.0f64
        ci[j + 1usize] = 0.0f64
        var k = j + 1usize
        while k > 0usize {
            let (pr, pi) = cmul(rr[j], ri[j], cr[k - 1usize], ci[k - 1usize])
            cr[k] -= pr
            ci[k] -= pi
            k -= 1usize
        }
        j += 1usize
    }
}

// Maps analog zeros, poles and gain (`zr.len <= pr.len`) at sample rate `fs`
// to digital `b`, `a` (`pr.len + 1` entries each) as SciPy's `bilinear_zpk`
// followed by `zpk2tf`; `scratch.len >= 6 * (pr.len + 1)`.
fn bilinear_transform(zr: []const f64, zi: []const f64, pr: []const f64, pi: []const f64, gain: f64, fs: f64, b: []f64, a: []f64, scratch: []f64) -> err {
    let n = pr.len
    if zr.len > n || zi.len != zr.len || pi.len != n { ret Invalid }
    if b.len < n + 1usize || a.len < n + 1usize || scratch.len < 6usize * (n + 1usize) { ret TooSmall }
    let fs2 = 2.0f64 * fs
    var dzr = scratch[..n]
    var dzi = scratch[n..2usize * n]
    var dpr = scratch[2usize * n..3usize * n]
    var dpi = scratch[3usize * n..4usize * n]
    var cr = scratch[4usize * n..5usize * n + 1usize]
    var ci = scratch[5usize * n + 1usize..6usize * n + 2usize]
    var kr = gain
    var ki = 0.0f64
    var j = 0usize
    while j < n {
        if j < zr.len {
            let (r, i) = cdiv(fs2 + zr[j], zi[j], fs2 - zr[j], 0.0f64 - zi[j])
            dzr[j] = r
            dzi[j] = i
            let (nr, ni) = cmul(kr, ki, fs2 - zr[j], 0.0f64 - zi[j])
            kr = nr
            ki = ni
        } else {
            dzr[j] = -1.0f64
            dzi[j] = 0.0f64
        }
        let (r2, i2) = cdiv(fs2 + pr[j], pi[j], fs2 - pr[j], 0.0f64 - pi[j])
        dpr[j] = r2
        dpi[j] = i2
        let (qr, qi) = cdiv(kr, ki, fs2 - pr[j], 0.0f64 - pi[j])
        kr = qr
        ki = qi
        j += 1usize
    }
    poly(dzr, dzi, cr, ci)
    j = 0usize
    while j <= n {
        b[j] = kr * cr[j]
        j += 1usize
    }
    poly(dpr, dpi, cr, ci)
    j = 0usize
    while j <= n {
        a[j] = cr[j]
        j += 1usize
    }
    ret ok
}

// Pre-warps a low-pass prototype to `cutoff` (Nyquist fraction) and applies the
// bilinear transform at `fs = 2`, as SciPy's `iirfilter`.
// ponytail: low-pass only; high-pass is `lp2hp_zpk` (p = wo / p, zeros at 0) on the same prototypes.
fn finish_lowpass(zr: []f64, zi: []f64, pr: []f64, pi: []f64, gain: f64, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err {
    let warped = 4.0f64 * math.tan[f64](3.141592653589793f64 * cutoff / 2.0f64)
    var k = gain
    var j = 0usize
    while j < pr.len {
        pr[j] = pr[j] * warped
        pi[j] = pi[j] * warped
        if j < zr.len {
            zr[j] = zr[j] * warped
            zi[j] = zi[j] * warped
        } else {
            k = k * warped
        }
        j += 1usize
    }
    ret bilinear_transform(zr, zi, pr, pi, k, 2.0f64, b, a, scratch)
}

// A Butterworth low-pass of `order` at `cutoff` (Nyquist fraction) into `b`,
// `a` (`order + 1` entries each); `scratch.len >= 12 * (order + 1)`.
fn design_butterworth(order: usize, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err {
    if order == 0usize || cutoff <= 0.0f64 || cutoff >= 1.0f64 { ret Invalid }
    if scratch.len < 12usize * (order + 1usize) { ret TooSmall }
    var pr = scratch[..order]
    var pi = scratch[order..2usize * order]
    var j = 0usize
    while j < order {
        let angle = 3.141592653589793f64 * (f64(2usize * j + 1usize) - f64(order)) / f64(2usize * order)
        pr[j] = 0.0f64 - math.cos[f64](angle)
        pi[j] = 0.0f64 - math.sin[f64](angle)
        j += 1usize
    }
    ret finish_lowpass(scratch[..0usize], scratch[..0usize], pr, pi, 1.0f64, cutoff, b, a, scratch[2usize * order..])
}

// A Chebyshev type I low-pass with `ripple_db` passband ripple; storage as
// `design_butterworth`.
fn design_chebyshev(order: usize, ripple_db: f64, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err {
    if order == 0usize || cutoff <= 0.0f64 || cutoff >= 1.0f64 || ripple_db <= 0.0f64 { ret Invalid }
    if scratch.len < 12usize * (order + 1usize) { ret TooSmall }
    var pr = scratch[..order]
    var pi = scratch[order..2usize * order]
    let eps = math.sqrt[f64](math.exp[f64](0.1f64 * ripple_db * 2.302585092994046f64) - 1.0f64)
    let mu = asinh(1.0f64 / eps) / f64(order)
    let sh = (math.exp[f64](mu) - math.exp[f64](0.0f64 - mu)) / 2.0f64
    let ch = (math.exp[f64](mu) + math.exp[f64](0.0f64 - mu)) / 2.0f64
    var kr = 1.0f64
    var ki = 0.0f64
    var j = 0usize
    while j < order {
        let theta = 3.141592653589793f64 * (f64(2usize * j + 1usize) - f64(order)) / f64(2usize * order)
        pr[j] = 0.0f64 - sh * math.cos[f64](theta)
        pi[j] = 0.0f64 - ch * math.sin[f64](theta)
        let (nr, ni) = cmul(kr, ki, 0.0f64 - pr[j], 0.0f64 - pi[j])
        kr = nr
        ki = ni
        j += 1usize
    }
    if order % 2usize == 0usize { kr = kr / math.sqrt[f64](1.0f64 + eps * eps) }
    ret finish_lowpass(scratch[..0usize], scratch[..0usize], pr, pi, kr, cutoff, b, a, scratch[2usize * order..])
}

// `p(z)` and `p'(z)` of a real polynomial `c[k] z^k` at a complex point.
fn horner(c: []const f64, zr: f64, zi: f64) -> (f64, f64, f64, f64) {
    var vr = 0.0f64
    var vi = 0.0f64
    var dr = 0.0f64
    var di = 0.0f64
    var k = c.len
    while k > 0usize {
        k -= 1usize
        let (ndr, ndi) = cmul(dr, di, zr, zi)
        dr = ndr + vr
        di = ndi + vi
        let (nvr, nvi) = cmul(vr, vi, zr, zi)
        vr = nvr + c[k]
        vi = nvi
    }
    ret (vr, vi, dr, di)
}

// All roots of a monic real polynomial (`c[k] z^k`, `c[n] = 1`) by
// Durand-Kerner with a Newton polish, into `rr`/`ri` (`n` entries).
fn poly_roots(c: []const f64, rr: []f64, ri: []f64) -> err {
    let n = c.len - 1usize
    var radius = 1.0f64
    if c[0usize] != 0.0f64 { radius = math.exp[f64](math.log[f64](math.abs[f64](c[0usize])) / f64(n)) }
    var j = 0usize
    while j < n {
        let angle = 6.283185307179586f64 * f64(j) / f64(n) + 0.4f64
        rr[j] = radius * math.cos[f64](angle)
        ri[j] = radius * math.sin[f64](angle)
        j += 1usize
    }
    var iteration = 0usize
    var moved = true
    while moved && iteration < 500usize {
        moved = false
        j = 0usize
        while j < n {
            let (vr, vi, _, _) = horner(c, rr[j], ri[j])
            var dr = 1.0f64
            var di = 0.0f64
            var m = 0usize
            while m < n {
                if m != j {
                    let (ndr, ndi) = cmul(dr, di, rr[j] - rr[m], ri[j] - ri[m])
                    dr = ndr
                    di = ndi
                }
                m += 1usize
            }
            let (sr, si) = cdiv(vr, vi, dr, di)
            rr[j] -= sr
            ri[j] -= si
            if math.abs[f64](sr) + math.abs[f64](si) > 1.0e-12f64 * radius { moved = true }
            j += 1usize
        }
        iteration += 1usize
    }
    if moved { ret NoConvergence }
    j = 0usize
    while j < n {
        var step = 0usize
        while step < 3usize {
            let (vr, vi, dr, di) = horner(c, rr[j], ri[j])
            let (sr, si) = cdiv(vr, vi, dr, di)
            rr[j] -= sr
            ri[j] -= si
            step += 1usize
        }
        j += 1usize
    }
    ret ok
}

// A Bessel low-pass (SciPy's `norm="phase"`); storage as `design_butterworth`.
fn design_bessel(order: usize, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err {
    if order == 0usize || cutoff <= 0.0f64 || cutoff >= 1.0f64 { ret Invalid }
    if scratch.len < 12usize * (order + 1usize) { ret TooSmall }
    var pr = scratch[..order]
    var pi = scratch[order..2usize * order]
    var c = scratch[2usize * order..3usize * order + 1usize]
    // Reverse Bessel polynomial: c[k] = (2n - k)! / (2^(n - k) k! (n - k)!).
    c[order] = 1.0f64
    var k = order
    while k > 0usize {
        c[k - 1usize] = c[k] * f64(2usize * order - k + 1usize) * f64(k) / (2.0f64 * f64(order - k + 1usize))
        k -= 1usize
    }
    let roots_error = poly_roots(c, pr, pi)
    if roots_error != ok { ret roots_error }
    let scale = math.exp[f64](0.0f64 - math.log[f64](c[0usize]) / f64(order))
    k = 0usize
    while k < order {
        pr[k] = pr[k] * scale
        pi[k] = pi[k] * scale
        k += 1usize
    }
    ret finish_lowpass(scratch[..0usize], scratch[..0usize], pr, pi, 1.0f64, cutoff, b, a, scratch[3usize * order + 1usize..])
}

// `pi / (2 AGM(1, b0))`: the complete elliptic integral with `b0 = sqrt(1 - m)`.
fn agm_k(b0: f64) -> f64 {
    var a = 1.0f64
    var b = b0
    var i = 0usize
    while i < 60usize && math.abs[f64](a - b) > 1.0e-16f64 * a {
        let t = (a + b) / 2.0f64
        b = math.sqrt[f64](a * b)
        a = t
        i += 1usize
    }
    ret 3.141592653589793f64 / (2.0f64 * a)
}

fn ellipk(m: f64) -> f64 { ret agm_k(math.sqrt[f64](1.0f64 - m)) }
fn ellipkm1(p: f64) -> f64 { ret agm_k(math.sqrt[f64](p)) }

// Jacobi `sn`, `cn`, `dn` of `u` with parameter `m` by the AGM (Cephes `ellpj`).
// ponytail: the m -> 1 hyperbolic branch is omitted; the AGM just loses digits there.
fn ellipj(u: f64, m: f64) -> (f64, f64, f64) {
    if m < 1.0e-9f64 {
        let t = math.sin[f64](u)
        let b = math.cos[f64](u)
        let ai = 0.25f64 * m * (u - t * b)
        ret (t - ai * b, b + ai * t, 1.0f64 - 0.5f64 * m * t * t)
    }
    var a: [9]f64 = zero
    var c: [9]f64 = zero
    a[0usize] = 1.0f64
    var b = math.sqrt[f64](1.0f64 - m)
    c[0usize] = math.sqrt[f64](m)
    var twon = 1.0f64
    var i = 0usize
    while i < 8usize && math.abs[f64](c[i] / a[i]) > 1.1102230246251565e-16f64 {
        let ai = a[i]
        i += 1usize
        c[i] = (ai - b) / 2.0f64
        let t = math.sqrt[f64](ai * b)
        a[i] = (ai + b) / 2.0f64
        b = t
        twon = twon * 2.0f64
    }
    var phi = twon * a[i] * u
    var previous = phi
    while i > 0usize {
        let t = c[i] * math.sin[f64](phi) / a[i]
        previous = phi
        phi = (math.asin[f64](t) + phi) / 2.0f64
        i -= 1usize
    }
    let sn = math.sin[f64](phi)
    let cn = math.cos[f64](phi)
    let dnfac = math.cos[f64](phi - previous)
    var dn = cn / dnfac
    if math.abs[f64](dnfac) < 0.1f64 { dn = math.sqrt[f64](1.0f64 - m * sn * sn) }
    ret (sn, cn, dn)
}

// The real `z` with `w = sc(z, 1 - m)` by Landen descent (SciPy's `_arc_jac_sc1`).
fn arc_sc1(w: f64, m: f64) -> f64 {
    var k = math.sqrt[f64](m)
    var kprod = 1.0f64
    var y = w
    while k != 0.0f64 {
        let kp = math.sqrt[f64]((1.0f64 - k) * (1.0f64 + k))
        let knext = (1.0f64 - kp) / (1.0f64 + kp)
        y = 2.0f64 * y / ((1.0f64 + knext) * (1.0f64 + math.sqrt[f64](1.0f64 + k * k * y * y)))
        kprod = kprod * (1.0f64 + knext)
        k = knext
    }
    ret kprod * asinh(y)
}

// Solves `n K(m) / K'(m) = K(m1) / K'(m1)` for `m` through the nome.
fn ellipdeg(n: usize, m1: f64) -> f64 {
    let q1 = math.exp[f64](0.0f64 - 3.141592653589793f64 * ellipkm1(m1) / ellipk(m1))
    let q = math.exp[f64](math.log[f64](q1) / f64(n))
    var num = 0.0f64
    var den = 1.0f64
    var i = 0usize
    while i <= 7usize {
        num += math.pow[f64](q, f64(i * (i + 1usize)))
        den += 2.0f64 * math.pow[f64](q, f64((i + 1usize) * (i + 1usize)))
        i += 1usize
    }
    ret 16.0f64 * q * ipow(num / den, 4usize)
}

// An elliptic (Cauer) low-pass with `ripple_db` passband ripple and
// `attenuation_db` stopband depth, as SciPy's `ellip`; storage as
// `design_butterworth`.
fn design_elliptic(order: usize, ripple_db: f64, attenuation_db: f64, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err {
    if order == 0usize || cutoff <= 0.0f64 || cutoff >= 1.0f64 || ripple_db <= 0.0f64 || attenuation_db <= ripple_db { ret Invalid }
    if scratch.len < 12usize * (order + 1usize) { ret TooSmall }
    let nz = 2usize * (order / 2usize)
    var zr = scratch[..nz]
    var zi = scratch[nz..2usize * nz]
    var pr = scratch[2usize * nz..2usize * nz + order]
    var pi = scratch[2usize * nz + order..2usize * nz + 2usize * order]
    let rest = 2usize * nz + 2usize * order
    let eps_sq = math.exp[f64](0.1f64 * ripple_db * 2.302585092994046f64) - 1.0f64
    let eps = math.sqrt[f64](eps_sq)
    if order == 1usize {
        pr[0usize] = 0.0f64 - math.sqrt[f64](1.0f64 / eps_sq)
        pi[0usize] = 0.0f64
        ret finish_lowpass(zr, zi, pr, pi, 0.0f64 - pr[0usize], cutoff, b, a, scratch[rest..])
    }
    let ck1_sq = eps_sq / (math.exp[f64](0.1f64 * attenuation_db * 2.302585092994046f64) - 1.0f64)
    let val0 = ellipk(ck1_sq)
    let m = ellipdeg(order, ck1_sq)
    let capk = ellipk(m)
    let v0 = capk * arc_sc1(1.0f64 / eps, ck1_sq) / (f64(order) * val0)
    let (sv, cv, dv) = ellipj(v0, 1.0f64 - m)
    var kr = 1.0f64
    var ki = 0.0f64
    var zcount = 0usize
    var pcount = 0usize
    var j = 1usize - order % 2usize
    while j < order {
        let (s, c, d) = ellipj(f64(j) * capk / f64(order), m)
        if math.abs[f64](s) > 2.0e-16f64 {
            let z = 1.0f64 / (math.sqrt[f64](m) * s)
            zr[zcount] = 0.0f64
            zi[zcount] = z
            zr[zcount + 1usize] = 0.0f64
            zi[zcount + 1usize] = 0.0f64 - z
            zcount += 2usize
        }
        let den = 1.0f64 - (d * sv) * (d * sv)
        let p_re = 0.0f64 - c * d * sv * cv / den
        let p_im = 0.0f64 - s * dv / den
        pr[pcount] = p_re
        pi[pcount] = p_im
        pcount += 1usize
        if order % 2usize == 0usize || j != 0usize {
            pr[pcount] = p_re
            pi[pcount] = 0.0f64 - p_im
            pcount += 1usize
        }
        j += 2usize
    }
    j = 0usize
    while j < order {
        let (nr, ni) = cmul(kr, ki, 0.0f64 - pr[j], 0.0f64 - pi[j])
        kr = nr
        ki = ni
        j += 1usize
    }
    j = 0usize
    while j < nz {
        let (nr2, ni2) = cdiv(kr, ki, 0.0f64 - zr[j], 0.0f64 - zi[j])
        kr = nr2
        ki = ni2
        j += 1usize
    }
    if order % 2usize == 0usize { kr = kr / math.sqrt[f64](1.0f64 + eps_sq) }
    ret finish_lowpass(zr, zi, pr, pi, kr, cutoff, b, a, scratch[rest..])
}

// --- spectral ---------------------------------------------------------------------

// Windowed frames of `frame` samples (a power of two) every `hop` samples,
// transformed into `re`/`im` (`frames * frame` entries each); answers the
// frame count `(x.len - frame) / hop + 1`.
fn stft(x: []const f64, frame: usize, hop: usize, win: []const f64, re: []f64, im: []f64) -> (usize, err) {
    if hop == 0usize || frame == 0usize || x.len < frame || win.len < frame { ret (0usize, Invalid) }
    let frames = (x.len - frame) / hop + 1usize
    if re.len < frames * frame || im.len < frames * frame { ret (0usize, TooSmall) }
    var f = 0usize
    while f < frames {
        var block_re = re[f * frame..(f + 1usize) * frame]
        var block_im = im[f * frame..(f + 1usize) * frame]
        var i = 0usize
        while i < frame {
            block_re[i] = x[f * hop + i] * win[i]
            block_im[i] = 0.0f64
            i += 1usize
        }
        let fft_error = fft.fft(block_re, block_im)
        if fft_error != ok { ret (0usize, fft_error) }
        f += 1usize
    }
    ret (frames, ok)
}

// Overlap-add inverse of `stft` with window-sum normalisation into `out`
// (`(frames - 1) * hop + frame` samples); `scratch.len >= 2 * frame + out.len`.
fn istft(re: []const f64, im: []const f64, frames: usize, frame: usize, hop: usize, win: []const f64, out: []f64, scratch: []f64) -> err {
    if hop == 0usize || frames == 0usize || win.len < frame { ret Invalid }
    let n = (frames - 1usize) * hop + frame
    if out.len < n || re.len < frames * frame || im.len < frames * frame || scratch.len < 2usize * frame + n { ret TooSmall }
    var br = scratch[..frame]
    var bi = scratch[frame..2usize * frame]
    var norm = scratch[2usize * frame..2usize * frame + n]
    clear(out[..n])
    clear(norm)
    var f = 0usize
    while f < frames {
        var i = 0usize
        while i < frame {
            br[i] = re[f * frame + i]
            bi[i] = im[f * frame + i]
            i += 1usize
        }
        let fft_error = fft.ifft(br, bi)
        if fft_error != ok { ret fft_error }
        i = 0usize
        while i < frame {
            out[f * hop + i] += br[i] * win[i]
            norm[f * hop + i] += win[i] * win[i]
            i += 1usize
        }
        f += 1usize
    }
    var i = 0usize
    while i < n {
        if norm[i] > 1.0e-10f64 { out[i] = out[i] / norm[i] }
        i += 1usize
    }
    ret ok
}

fn hz_to_mel(f: f64) -> f64 { ret 2595.0f64 * math.log10[f64](1.0f64 + f / 700.0f64) }
fn mel_to_hz(m: f64) -> f64 { ret 700.0f64 * (math.exp[f64](m / 2595.0f64 * 2.302585092994046f64) - 1.0f64) }

// Mel-frequency cepstral coefficients: Hann-windowed power spectra, an HTK mel
// filterbank of `n_mels` unnormalised triangles from 0 Hz to Nyquist,
// `log(energy + 1e-10)`, then the first `n_coeffs` of an unnormalised DCT-II;
// `out[frame * n_coeffs + c]`, `scratch.len >= 3 * frame + 2 * n_mels`.
fn mfcc(x: []const f64, sample_rate: f64, frame: usize, hop: usize, n_mels: usize, n_coeffs: usize, out: []f64, scratch: []f64) -> (usize, err) {
    if hop == 0usize || frame < 2usize || x.len < frame || n_mels == 0usize || n_coeffs > n_mels { ret (0usize, Invalid) }
    let frames = (x.len - frame) / hop + 1usize
    if out.len < frames * n_coeffs || scratch.len < 3usize * frame + 2usize * n_mels { ret (0usize, TooSmall) }
    var win = scratch[..frame]
    var re = scratch[frame..2usize * frame]
    var im = scratch[2usize * frame..3usize * frame]
    var energy = scratch[3usize * frame..3usize * frame + n_mels]
    var dct = scratch[3usize * frame + n_mels..3usize * frame + 2usize * n_mels]
    let window_error = window(.Hann, frame, win)
    if window_error != ok { ret (0usize, window_error) }
    let mel_top = hz_to_mel(sample_rate / 2.0f64)
    var f = 0usize
    while f < frames {
        let (_, stft_error) = stft(x[f * hop..f * hop + frame], frame, frame, win, re, im)
        if stft_error != ok { ret (0usize, stft_error) }
        var mel = 0usize
        while mel < n_mels {
            let lo = mel_to_hz(mel_top * f64(mel) / f64(n_mels + 1usize))
            let mid = mel_to_hz(mel_top * f64(mel + 1usize) / f64(n_mels + 1usize))
            let hi = mel_to_hz(mel_top * f64(mel + 2usize) / f64(n_mels + 1usize))
            var sum = 0.0f64
            var k = 0usize
            while k <= frame / 2usize {
                let hz = f64(k) * sample_rate / f64(frame)
                var w = 0.0f64
                if hz >= lo && hz <= mid { w = (hz - lo) / (mid - lo) }
                if hz > mid && hz <= hi { w = (hi - hz) / (hi - mid) }
                sum += w * (re[k] * re[k] + im[k] * im[k])
                k += 1usize
            }
            energy[mel] = math.log[f64](sum + 1.0e-10f64)
            mel += 1usize
        }
        let dct_error = fft.dct2(energy, dct)
        if dct_error != ok { ret (0usize, dct_error) }
        var c = 0usize
        while c < n_coeffs {
            out[f * n_coeffs + c] = dct[c]
            c += 1usize
        }
        f += 1usize
    }
    ret (frames, ok)
}

// The constant-Q transform of the start of `x`: bin `k` at `f_min 2^(k / bins_per_octave)`
// with `Q = 1 / (2^(1 / bins_per_octave) - 1)`, a Hann-windowed kernel of
// `ceil(Q sample_rate / f_k)` samples scaled by its length, into `re`/`im`.
// ponytail: direct O(sum N_k) kernels, one frame; an FFT kernel bank if many frames matter.
fn cqt(x: []const f64, sample_rate: f64, f_min: f64, bins_per_octave: usize, n_bins: usize, re: []f64, im: []f64) -> err {
    if bins_per_octave == 0usize || f_min <= 0.0f64 { ret Invalid }
    if re.len < n_bins || im.len < n_bins { ret TooSmall }
    let q = 1.0f64 / (math.exp[f64](0.6931471805599453f64 / f64(bins_per_octave)) - 1.0f64)
    var k = 0usize
    while k < n_bins {
        let fk = f_min * math.exp[f64](0.6931471805599453f64 * f64(k) / f64(bins_per_octave))
        let length = usize(math.ceil[f64](q * sample_rate / fk))
        if length > x.len || length < 2usize { ret Invalid }
        var sr = 0.0f64
        var si = 0.0f64
        var n = 0usize
        while n < length {
            let w = 0.5f64 - 0.5f64 * math.cos[f64](6.283185307179586f64 * f64(n) / f64(length - 1usize))
            let phase = 0.0f64 - 6.283185307179586f64 * q * f64(n) / f64(length)
            sr += x[n] * w * math.cos[f64](phase)
            si += x[n] * w * math.sin[f64](phase)
            n += 1usize
        }
        re[k] = sr / f64(length)
        im[k] = si / f64(length)
        k += 1usize
    }
    ret ok
}

// The real cepstrum `ifft(log |fft(x)|)` of a power-of-two signal into `out`;
// `scratch.len >= x.len`.
fn cepstrum(x: []const f64, out: []f64, scratch: []f64) -> err {
    let n = x.len
    if out.len < n || scratch.len < n { ret TooSmall }
    var re = out[..n]
    var im = scratch[..n]
    var i = 0usize
    while i < n {
        re[i] = x[i]
        im[i] = 0.0f64
        i += 1usize
    }
    let fft_error = fft.fft(re, im)
    if fft_error != ok { ret fft_error }
    i = 0usize
    while i < n {
        var magnitude = math.sqrt[f64](re[i] * re[i] + im[i] * im[i])
        if magnitude < 1.0e-300f64 { magnitude = 1.0e-300f64 }
        re[i] = math.log[f64](magnitude)
        im[i] = 0.0f64
        i += 1usize
    }
    ret fft.ifft(re, im)
}

// `out = max(magnitude - alpha noise, floor magnitude)` per bin.
fn spectral_subtract(magnitude: []const f64, noise: []const f64, alpha: f64, floor: f64, out: []f64) -> err {
    if noise.len < magnitude.len || out.len < magnitude.len { ret TooSmall }
    var i = 0usize
    while i < magnitude.len {
        var v = magnitude[i] - alpha * noise[i]
        if v < floor * magnitude[i] { v = floor * magnitude[i] }
        out[i] = v
        i += 1usize
    }
    ret ok
}

// Per-frame spectral Wiener gain over non-overlapping frames of `frame`
// samples (a power of two): each bin is scaled by `max(P - noise_variance, 0) / P`
// with `P = |X|^2 / frame`; the tail shorter than a frame is copied;
// `scratch.len >= frame`.
fn wiener(x: []const f64, noise_variance: f64, frame: usize, out: []f64, scratch: []f64) -> err {
    if frame == 0usize { ret Invalid }
    if out.len < x.len || scratch.len < frame { ret TooSmall }
    var im = scratch[..frame]
    var start = 0usize
    while start + frame <= x.len {
        var re = out[start..start + frame]
        var i = 0usize
        while i < frame {
            re[i] = x[start + i]
            im[i] = 0.0f64
            i += 1usize
        }
        let fft_error = fft.fft(re, im)
        if fft_error != ok { ret fft_error }
        i = 0usize
        while i < frame {
            let power = (re[i] * re[i] + im[i] * im[i]) / f64(frame)
            var gain = 0.0f64
            if power > noise_variance { gain = (power - noise_variance) / power }
            re[i] = re[i] * gain
            im[i] = im[i] * gain
            i += 1usize
        }
        let inverse_error = fft.ifft(re, im)
        if inverse_error != ok { ret inverse_error }
        start += frame
    }
    while start < x.len {
        out[start] = x[start]
        start += 1usize
    }
    ret ok
}

// --- linear prediction and alignment ------------------------------------------

// Solves the Toeplitz normal equations of `r[0..order]`: `out[0] = 1` and
// `out[1..order]` the predictor `A(z) = 1 + sum a_k z^-k`; answers the final
// prediction error. `scratch.len >= order + 1`.
fn levinson_durbin(r: []const f64, order: usize, out: []f64, scratch: []f64) -> (f64, err) {
    if r.len <= order || out.len <= order || scratch.len <= order { ret (0.0f64, TooSmall) }
    if r[0usize] <= 0.0f64 { ret (0.0f64, Invalid) }
    var error_power = r[0usize]
    out[0usize] = 1.0f64
    var i = 1usize
    while i <= order {
        var acc = r[i]
        var j = 1usize
        while j < i {
            acc += out[j] * r[i - j]
            j += 1usize
        }
        let k = 0.0f64 - acc / error_power
        j = 1usize
        while j < i {
            scratch[j] = out[j] + k * out[i - j]
            j += 1usize
        }
        j = 1usize
        while j < i {
            out[j] = scratch[j]
            j += 1usize
        }
        out[i] = k
        error_power = error_power * (1.0f64 - k * k)
        i += 1usize
    }
    ret (error_power, ok)
}

// Autocorrelation LPC of `order`; `scratch.len >= 2 * (order + 1)`.
fn lpc(x: []const f64, order: usize, out: []f64, scratch: []f64) -> (f64, err) {
    if scratch.len < 2usize * (order + 1usize) || x.len <= order { ret (0.0f64, TooSmall) }
    var r = scratch[..order + 1usize]
    var lag = 0usize
    while lag <= order {
        var sum = 0.0f64
        var n = lag
        while n < x.len {
            sum += x[n] * x[n - lag]
            n += 1usize
        }
        r[lag] = sum
        lag += 1usize
    }
    let (power, solve_error) = levinson_durbin(r, order, out, scratch[order + 1usize..])
    ret (power, solve_error)
}

// Dynamic time warping with absolute local cost and the three moves; fills the
// accumulated cost matrix `cost` (`a.len * b.len`, row-major) and answers the distance.
fn dtw(a: []const f64, b: []const f64, cost: []f64) -> (f64, err) {
    let na = a.len
    let nb = b.len
    if na == 0usize || nb == 0usize { ret (0.0f64, Invalid) }
    if cost.len < na * nb { ret (0.0f64, TooSmall) }
    var i = 0usize
    while i < na {
        var j = 0usize
        while j < nb {
            var best = 0.0f64
            if i > 0usize && j > 0usize {
                best = cost[(i - 1usize) * nb + j - 1usize]
                if cost[(i - 1usize) * nb + j] < best { best = cost[(i - 1usize) * nb + j] }
                if cost[i * nb + j - 1usize] < best { best = cost[i * nb + j - 1usize] }
            } else if i > 0usize {
                best = cost[(i - 1usize) * nb]
            } else if j > 0usize {
                best = cost[j - 1usize]
            }
            cost[i * nb + j] = best + math.abs[f64](a[i] - b[j])
            j += 1usize
        }
        i += 1usize
    }
    ret (cost[na * nb - 1usize], ok)
}

// The warping path of a filled `dtw` matrix from `(0, 0)` to the end, as index
// pairs into `path_a`/`path_b` (at most `na + nb - 1`); answers its length.
fn dtw_path(cost: []const f64, na: usize, nb: usize, path_a: []usize, path_b: []usize) -> (usize, err) {
    if na == 0usize || nb == 0usize || cost.len < na * nb { ret (0usize, Invalid) }
    if path_a.len < na + nb - 1usize || path_b.len < na + nb - 1usize { ret (0usize, TooSmall) }
    var i = na - 1usize
    var j = nb - 1usize
    var count = 0usize
    var more = true
    while more {
        path_a[count] = i
        path_b[count] = j
        count += 1usize
        if i == 0usize && j == 0usize {
            more = false
        } else if i == 0usize {
            j -= 1usize
        } else if j == 0usize {
            i -= 1usize
        } else {
            let diagonal = cost[(i - 1usize) * nb + j - 1usize]
            let up = cost[(i - 1usize) * nb + j]
            let left = cost[i * nb + j - 1usize]
            if diagonal <= up && diagonal <= left {
                i -= 1usize
                j -= 1usize
            } else if up <= left {
                i -= 1usize
            } else {
                j -= 1usize
            }
        }
    }
    var lo = 0usize
    var hi = count - 1usize
    while lo < hi {
        let ta = path_a[lo]
        path_a[lo] = path_a[hi]
        path_a[hi] = ta
        let tb = path_b[lo]
        path_b[lo] = path_b[hi]
        path_b[hi] = tb
        lo += 1usize
        hi -= 1usize
    }
    ret (count, ok)
}

// --- adaptive filters -------------------------------------------------------------

fn tap_input(x: []const f64, n: usize, k: usize) -> f64 {
    if k > n { ret 0.0f64 }
    ret x[n - k]
}

// LMS (`normalised` false) or NLMS: `w` (`taps`, updated in place, zeroed by the
// caller) tracks `d` from `x`; `out_error[n] = d[n] - y[n]`. NLMS divides `mu`
// by `eps + ||u||^2`.
fn lms_core(x: []const f64, d: []const f64, mu: f64, eps: f64, normalised: bool, w: []f64, out_error: []f64) -> err {
    if d.len < x.len || out_error.len < x.len || w.len == 0usize { ret TooSmall }
    var n = 0usize
    while n < x.len {
        var y = 0.0f64
        var power = eps
        var k = 0usize
        while k < w.len {
            let u = tap_input(x, n, k)
            y += w[k] * u
            power += u * u
            k += 1usize
        }
        let e = d[n] - y
        out_error[n] = e
        var step = mu
        if normalised { step = mu / power }
        k = 0usize
        while k < w.len {
            w[k] += step * e * tap_input(x, n, k)
            k += 1usize
        }
        n += 1usize
    }
    ret ok
}

fn lms(x: []const f64, d: []const f64, mu: f64, w: []f64, out_error: []f64) -> err { ret lms_core(x, d, mu, 0.0f64, false, w, out_error) }
fn nlms(x: []const f64, d: []const f64, mu: f64, eps: f64, w: []f64, out_error: []f64) -> err { ret lms_core(x, d, mu, eps, true, w, out_error) }

// Recursive least squares with forgetting factor `lambda` and `P = I / delta`;
// `p` holds `taps * taps`, `scratch.len >= 2 * taps`.
fn rls(x: []const f64, d: []const f64, lambda: f64, delta: f64, w: []f64, p: []f64, scratch: []f64, out_error: []f64) -> err {
    let taps = w.len
    if taps == 0usize || lambda <= 0.0f64 || delta <= 0.0f64 { ret Invalid }
    if d.len < x.len || out_error.len < x.len || p.len < taps * taps || scratch.len < 2usize * taps { ret TooSmall }
    var pu = scratch[..taps]
    var g = scratch[taps..2usize * taps]
    clear(p[..taps * taps])
    var i = 0usize
    while i < taps {
        p[i * taps + i] = 1.0f64 / delta
        i += 1usize
    }
    var n = 0usize
    while n < x.len {
        // pu = P u, denominator = lambda + u' P u, gain g = pu / denominator.
        var den = lambda
        var y = 0.0f64
        i = 0usize
        while i < taps {
            var sum = 0.0f64
            var k = 0usize
            while k < taps {
                sum += p[i * taps + k] * tap_input(x, n, k)
                k += 1usize
            }
            pu[i] = sum
            den += tap_input(x, n, i) * sum
            y += w[i] * tap_input(x, n, i)
            i += 1usize
        }
        let e = d[n] - y
        out_error[n] = e
        i = 0usize
        while i < taps {
            g[i] = pu[i] / den
            w[i] += g[i] * e
            i += 1usize
        }
        // P = (P - g u' P) / lambda, with u' P = (P u)' by symmetry.
        i = 0usize
        while i < taps {
            var k = 0usize
            while k < taps {
                p[i * taps + k] = (p[i * taps + k] - g[i] * pu[k]) / lambda
                k += 1usize
            }
            i += 1usize
        }
        n += 1usize
    }
    ret ok
}

// --- resampling -----------------------------------------------------------------

// Rational resampling by `up / down` through the FIR `taps` (SciPy's
// `resample_poly(x, up, down, window=taps)`: the taps are scaled by `up` and the
// output is centred); answers `ceil(x.len * up / down)` samples into `out`.
fn resample_polyphase(x: []const f64, up: usize, down: usize, taps: []const f64, out: []f64) -> (usize, err) {
    if up == 0usize || down == 0usize || taps.len == 0usize { ret (0usize, Invalid) }
    let n_out = (x.len * up + down - 1usize) / down
    if out.len < n_out { ret (0usize, TooSmall) }
    let half = (taps.len - 1usize) / 2usize
    let pre_pad = down - half % down
    let pre_remove = (half + pre_pad) / down
    var i = 0usize
    while i < n_out {
        // Index into the zero-stuffed input hit by the centre of this output.
        let m = (i + pre_remove) * down
        var sum = 0.0f64
        var k = 0usize
        if m >= pre_pad {
            let top = m - pre_pad
            k = top % up
            while k < taps.len && k <= top {
                let j = (top - k) / up
                if j < x.len { sum += taps[k] * x[j] }
                k += up
            }
        }
        out[i] = sum * f64(up)
        i += 1usize
    }
    ret (n_out, ok)
}

// Band-limited resampling by a Hann-windowed sinc of `half_width` input
// samples each side: `out[i]` is the signal at input time `i / ratio`.
fn resample_sinc(x: []const f64, ratio: f64, half_width: usize, out: []f64) -> err {
    if ratio <= 0.0f64 || half_width == 0usize { ret Invalid }
    var i = 0usize
    while i < out.len {
        let t = f64(i) / ratio
        let centre = math.floor[f64](t)
        var sum = 0.0f64
        var j = 0usize
        while j <= 2usize * half_width {
            let sample = centre - f64(half_width) + f64(j)
            if sample >= 0.0f64 && sample < f64(x.len) {
                let d = t - sample
                if math.abs[f64](d) < f64(half_width) {
                    let w = 0.5f64 + 0.5f64 * math.cos[f64](3.141592653589793f64 * d / f64(half_width))
                    sum += x[usize(sample)] * sinc(d) * w
                }
            }
            j += 1usize
        }
        out[i] = sum
        i += 1usize
    }
    ret ok
}
