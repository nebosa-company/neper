// R signal: butter (Butterworth low-pass and high-pass of order n, one cutoff, digital) and filter(b, a, x). (fir1 in the package goes through fir2, a frequency-sampling design with a 512-point grid, scaled at half the cutoff; the windowed sinc below is only close to it, so it is not part of the oracle.)
//
// Not here: band filters, cheby1, cheby2, ellip, bessel, fir2, remez, filtfilt, freqz, grpdelay, sgolay, resample, decimate and the spectrogram.

use e.math
use e.mem

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

// the product of (x - r_k) over complex roots, real coefficients highest power first: out has n + 1 entries
fn poly_from_roots(re: []const f64, im: []const f64, out: []f64) {
    let n = re.len
    var cr: [40]f64 = zero
    var ci: [40]f64 = zero
    cr[0usize] = 1.0f64
    var deg = 0usize
    var k = 0usize
    while k < n {
        // multiply by (x - r): new[j] = old[j - 1] - r * old[j]
        var nr: [40]f64 = zero
        var ni: [40]f64 = zero
        var j = 0usize
        while j <= deg + 1usize {
            // highest power first: new[j] = old[j] - r * old[j - 1]
            var pr = 0.0f64
            var pi2 = 0.0f64
            if j <= deg {
                pr = cr[j]
                pi2 = ci[j]
            }
            var qr = 0.0f64
            var qi = 0.0f64
            if j >= 1usize {
                qr = cr[j - 1usize] * re[k] - ci[j - 1usize] * im[k]
                qi = cr[j - 1usize] * im[k] + ci[j - 1usize] * re[k]
            }
            nr[j] = pr - qr
            ni[j] = pi2 - qi
            j += 1usize
        }
        deg += 1usize
        j = 0usize
        while j <= deg {
            cr[j] = nr[j]
            ci[j] = ni[j]
            j += 1usize
        }
        k += 1usize
    }
    var i = 0usize
    while i <= n {
        out[i] = cr[i]
        i += 1usize
    }
}

// butter(n, w, type): w in (0, 1) of the Nyquist frequency; high = false for low-pass, true for high-pass; b and a have n + 1 entries
fn butter(n: usize, w: f64, high: bool, b: []f64, a: []f64) {
    let warped = 4.0f64 * math.tan[f64](pi() * w / 2.0f64)
    var pr: [20]f64 = zero
    var pim: [20]f64 = zero
    var zr: [20]f64 = zero
    var zi: [20]f64 = zero
    var k = 1usize
    // the analog prototype poles exp(j pi (2k + n - 1) / (2n)), scaled (low-pass) or inverted and scaled (high-pass), then the bilinear transform with fs = 2
    var gnum_r = 1.0f64
    var gnum_i = 0.0f64
    while k <= n {
        let ang = pi() * f64(2usize * k + n - 1usize) / f64(2usize * n)
        var sr = math.cos[f64](ang)
        var si = math.sin[f64](ang)
        if high {
            // w / s
            let den = sr * sr + si * si
            sr = warped * sr / den
            si = 0.0f64 - warped * si / den
        } else {
            sr = warped * sr
            si = warped * si
        }
        // z = (1 + s/4) / (1 - s/4)
        let nr = 1.0f64 + sr / 4.0f64
        let ni = si / 4.0f64
        let dr = 1.0f64 - sr / 4.0f64
        let di = 0.0f64 - si / 4.0f64
        let dd = dr * dr + di * di
        pr[k - 1usize] = (nr * dr + ni * di) / dd
        pim[k - 1usize] = (ni * dr - nr * di) / dd
        zr[k - 1usize] = -1.0f64
        if high { zr[k - 1usize] = 1.0f64 }
        zi[k - 1usize] = 0.0f64
        k += 1usize
    }
    poly_from_roots(pr[0usize..n], pim[0usize..n], a)
    poly_from_roots(zr[0usize..n], zi[0usize..n], b)
    // gain: unit gain at z = 1 (low-pass) or z = -1 (high-pass)
    var x = 1.0f64
    if high { x = 0.0f64 - 1.0f64 }
    var nb = 0.0f64
    var na = 0.0f64
    var j = 0usize
    while j <= n {
        nb = nb * x + b[j]
        na = na * x + a[j]
        j += 1usize
    }
    let g = na / nb
    j = 0usize
    while j <= n {
        b[j] = b[j] * g
        j += 1usize
    }
}

// the direct-form difference equation with a[0] normalisation and zero initial state
fn filter(b: []const f64, a: []const f64, x: []const f64, out: []f64) {
    var i = 0usize
    while i < x.len {
        var s = 0.0f64
        var j = 0usize
        while j < b.len {
            if i >= j { s += b[j] * x[i - j] }
            j += 1usize
        }
        j = 1usize
        while j < a.len {
            if i >= j { s -= a[j] * out[i - j] }
            j += 1usize
        }
        out[i] = s / a[0usize]
        i += 1usize
    }
}

fn sinc_of(x: f64) -> f64 {
    if x == 0.0f64 { ret 1.0f64 }
    ret math.sin[f64](pi() * x) / (pi() * x)
}

// fir1(n, w): the order-n low-pass with a Hamming window, normalised to unit gain at DC; out has n + 1 entries
fn fir1(n: usize, w: f64, out: []f64) {
    let m = f64(n)
    var s = 0.0f64
    var i = 0usize
    while i <= n {
        let t = f64(i) - m / 2.0f64
        let win = 0.54f64 - 0.46f64 * math.cos[f64](2.0f64 * pi() * f64(i) / m)
        out[i] = w * sinc_of(w * t) * win
        s += out[i]
        i += 1usize
    }
    i = 0usize
    while i <= n {
        out[i] = out[i] / s
        i += 1usize
    }
}

// filtfilt(b, a, x): zero-phase filtering as the package does it, with 2 * max(length) zeros appended before the forward pass
fn filtfilt(a: *mem.Arena, b: []const f64, aa: []const f64, x: []const f64, out: []f64) -> err {
    var m = b.len
    if aa.len > m { m = aa.len }
    let total = x.len + 2usize * m
    let (y, e1) = mem.alloc[f64](a, total)
    if e1 != ok { ret e1 }
    let (xp, e2) = mem.alloc[f64](a, total)
    if e2 != ok { ret e2 }
    let (r, e3) = mem.alloc[f64](a, total)
    if e3 != ok { ret e3 }
    let (z, e4) = mem.alloc[f64](a, total)
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < total {
        if i < x.len { xp[i] = x[i] } else { xp[i] = 0.0f64 }
        i += 1usize
    }
    filter(b, aa, xp, y)
    i = 0usize
    while i < total {
        r[i] = y[total - 1usize - i]
        i += 1usize
    }
    filter(b, aa, r, z)
    i = 0usize
    while i < x.len {
        out[i] = z[total - 1usize - i]
        i += 1usize
    }
    ret ok
}

// the frequency response at w radians per sample: (re, im) of B(e^{-jw}) / A(e^{-jw})
fn freqz_at(b: []const f64, a: []const f64, w: f64) -> (f64, f64) {
    var br = 0.0f64
    var bi = 0.0f64
    var i = 0usize
    while i < b.len {
        br += b[i] * math.cos[f64](w * f64(i))
        bi -= b[i] * math.sin[f64](w * f64(i))
        i += 1usize
    }
    var ar = 0.0f64
    var ai = 0.0f64
    i = 0usize
    while i < a.len {
        ar += a[i] * math.cos[f64](w * f64(i))
        ai -= a[i] * math.sin[f64](w * f64(i))
        i += 1usize
    }
    let den = ar * ar + ai * ai
    ret ((br * ar + bi * ai) / den, (bi * ar - br * ai) / den)
}
