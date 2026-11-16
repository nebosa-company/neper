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

// the central row of sgolay(p, n): the weights of the Savitzky-Golay smoother of polynomial order p over a window of n (odd) points
fn sgolay_center(a: *mem.Arena, p: usize, n: usize, out: []f64) -> err {
    let q = p + 1usize
    let half = (n - 1usize) / 2usize
    let (g, e1) = mem.alloc[f64](a, q * q)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                let t = f64(k) - f64(half)
                s += math.pow[f64](t, f64(i + j))
                k += 1usize
            }
            g[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
    // solve G c = e0 by Gauss-Jordan with partial pivoting
    let (aug, e2) = mem.alloc[f64](a, q * (q + 1usize))
    if e2 != ok { ret e2 }
    i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            aug[i * (q + 1usize) + j] = g[i * q + j]
            j += 1usize
        }
        aug[i * (q + 1usize) + q] = 0.0f64
        i += 1usize
    }
    aug[q] = 1.0f64
    var c = 0usize
    while c < q {
        var piv = c
        var r = c + 1usize
        while r < q {
            if math.abs[f64](aug[r * (q + 1usize) + c]) > math.abs[f64](aug[piv * (q + 1usize) + c]) { piv = r }
            r += 1usize
        }
        var j = 0usize
        while j <= q {
            let t = aug[c * (q + 1usize) + j]
            aug[c * (q + 1usize) + j] = aug[piv * (q + 1usize) + j]
            aug[piv * (q + 1usize) + j] = t
            j += 1usize
        }
        let d = aug[c * (q + 1usize) + c]
        j = 0usize
        while j <= q {
            aug[c * (q + 1usize) + j] = aug[c * (q + 1usize) + j] / d
            j += 1usize
        }
        r = 0usize
        while r < q {
            if r != c {
                let f = aug[r * (q + 1usize) + c]
                j = 0usize
                while j <= q {
                    aug[r * (q + 1usize) + j] -= f * aug[c * (q + 1usize) + j]
                    j += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    var k = 0usize
    while k < n {
        let t = f64(k) - f64(half)
        var s = 0.0f64
        var j = 0usize
        while j < q {
            s += aug[j * (q + 1usize) + q] * math.pow[f64](t, f64(j))
            j += 1usize
        }
        out[k] = s
        k += 1usize
    }
    ret ok
}

// cheby1(n, rp, w, type): Chebyshev type I (passband ripple rp dB), low-pass or high-pass; b and a have n + 1 entries
fn cheby1(n: usize, rp: f64, w: f64, high: bool, b: []f64, a: []f64) {
    let eps = math.sqrt[f64](math.pow[f64](10.0f64, rp / 10.0f64) - 1.0f64)
    let mu = asinh_of(1.0f64 / eps) / f64(n)
    let warped = 4.0f64 * math.tan[f64](pi() * w / 2.0f64)
    var pr: [20]f64 = zero
    var pim: [20]f64 = zero
    var zr: [20]f64 = zero
    var zi: [20]f64 = zero
    var k = 1usize
    while k <= n {
        let th = pi() * f64(2usize * k - 1usize) / f64(2usize * n)
        // the prototype pole -sinh(mu) sin(th) + j cosh(mu) cos(th)
        var sr = 0.0f64 - sinh_of(mu) * math.sin[f64](th)
        var si = cosh_of(mu) * math.cos[f64](th)
        if high {
            let den = sr * sr + si * si
            sr = warped * sr / den
            si = 0.0f64 - warped * si / den
        } else {
            sr = warped * sr
            si = warped * si
        }
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
    var g0 = 1.0f64
    if n % 2usize == 0usize { g0 = 1.0f64 / math.sqrt[f64](1.0f64 + eps * eps) }
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
    let g = g0 * na / nb
    j = 0usize
    while j <= n {
        b[j] = b[j] * g
        j += 1usize
    }
}

fn sinh_of(x: f64) -> f64 { ret (math.exp[f64](x) - math.exp[f64](0.0f64 - x)) / 2.0f64 }

fn cosh_of(x: f64) -> f64 { ret (math.exp[f64](x) + math.exp[f64](0.0f64 - x)) / 2.0f64 }

fn asinh_of(x: f64) -> f64 { ret math.log[f64](x + math.sqrt[f64](x * x + 1.0f64)) }

// cheby2(n, rs, w, type): Chebyshev type II (stopband attenuation rs dB, w the stopband edge), low-pass or high-pass
fn cheby2(n: usize, rs: f64, w: f64, high: bool, b: []f64, a: []f64) {
    let eps = 1.0f64 / math.sqrt[f64](math.pow[f64](10.0f64, rs / 10.0f64) - 1.0f64)
    let mu = asinh_of(1.0f64 / eps) / f64(n)
    let warped = 4.0f64 * math.tan[f64](pi() * w / 2.0f64)
    var pr: [20]f64 = zero
    var pim: [20]f64 = zero
    var zr: [20]f64 = zero
    var zi: [20]f64 = zero
    var nz = 0usize
    var k = 1usize
    while k <= n {
        let th = pi() * f64(2usize * k - 1usize) / f64(2usize * n)
        // the type I pole inverted: 1 / (-sinh(mu) sin(th) + j cosh(mu) cos(th))
        let cr = 0.0f64 - sinh_of(mu) * math.sin[f64](th)
        let ci = cosh_of(mu) * math.cos[f64](th)
        let cd = cr * cr + ci * ci
        var sr = cr / cd
        var si = 0.0f64 - ci / cd
        if high {
            let den = sr * sr + si * si
            sr = warped * sr / den
            si = 0.0f64 - warped * si / den
        } else {
            sr = warped * sr
            si = warped * si
        }
        let nr = 1.0f64 + sr / 4.0f64
        let ni = si / 4.0f64
        let dr = 1.0f64 - sr / 4.0f64
        let di = 0.0f64 - si / 4.0f64
        let dd = dr * dr + di * di
        pr[k - 1usize] = (nr * dr + ni * di) / dd
        pim[k - 1usize] = (ni * dr - nr * di) / dd
        // the zero j / cos(th) of the prototype, absent when cos(th) = 0 (the odd-order middle pole)
        let ct = math.cos[f64](th)
        if math.abs[f64](ct) > 1.0e-12f64 {
            var yr = 0.0f64
            var yi = 1.0f64 / ct
            if high {
                // w / (j y) = -j w / y
                yi = 0.0f64 - warped / yi
            } else {
                yi = warped * yi
            }
            let znr = 1.0f64 + yr / 4.0f64
            let zni = yi / 4.0f64
            let zdr = 1.0f64 - yr / 4.0f64
            let zdi = 0.0f64 - yi / 4.0f64
            let zd = zdr * zdr + zdi * zdi
            zr[nz] = (znr * zdr + zni * zdi) / zd
            zi[nz] = (zni * zdr - znr * zdi) / zd
            nz += 1usize
            yr = 0.0f64
        }
        k += 1usize
    }
    // zeros at infinity of the prototype: z = -1 (low-pass) or z = +1 (high-pass)
    while nz < n {
        zr[nz] = -1.0f64
        if high { zr[nz] = 1.0f64 }
        zi[nz] = 0.0f64
        nz += 1usize
    }
    poly_from_roots(pr[0usize..n], pim[0usize..n], a)
    poly_from_roots(zr[0usize..n], zi[0usize..n], b)
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

// the response of the polynomial c(e^{-jw}) and of its k-weighted copy, as (re, im, wre, wim)
fn poly_resp(c: []const f64, w: f64) -> (f64, f64, f64, f64) {
    var re = 0.0f64
    var im = 0.0f64
    var wre = 0.0f64
    var wim = 0.0f64
    var k = 0usize
    while k < c.len {
        let cr = math.cos[f64](w * f64(k))
        let ci = 0.0f64 - math.sin[f64](w * f64(k))
        re += c[k] * cr
        im += c[k] * ci
        wre += f64(k) * c[k] * cr
        wim += f64(k) * c[k] * ci
        k += 1usize
    }
    ret (re, im, wre, wim)
}

// the group delay of B / A at w radians per sample: Re(B'/B) - Re(A'/A) with the k-weighted sums; 0 at a singularity as the package sets it
fn grpdelay_at(b: []const f64, a: []const f64, w: f64) -> f64 {
    let (br, bi, bwr, bwi) = poly_resp(b, w)
    let (ar, ai, awr, awi) = poly_resp(a, w)
    let bd = br * br + bi * bi
    let ad = ar * ar + ai * ai
    // the package works on the product polynomial c = b * rev(a), sets its ratio to 0 where it vanishes and subtracts length(a) - 1
    if bd < 1.0e-14f64 || ad < 1.0e-14f64 { ret 0.0f64 - f64(a.len - 1usize) }
    let gb = (bwr * br + bwi * bi) / bd
    let ga = (awr * ar + awi * ai) / ad
    ret gb - ga
}

// butter(n, c(w1, w2)): the band-pass Butterworth filter, order 2n (b and a have 2n + 1 entries); the gain is unity at the centre of the band
fn butter_band(n: usize, w1: f64, w2: f64, b: []f64, a: []f64) {
    let ww1 = 4.0f64 * math.tan[f64](pi() * w1 / 2.0f64)
    let ww2 = 4.0f64 * math.tan[f64](pi() * w2 / 2.0f64)
    let bw = ww2 - ww1
    let w0sq = ww1 * ww2
    var pr: [40]f64 = zero
    var pim: [40]f64 = zero
    var np = 0usize
    var k = 1usize
    while k <= n {
        let ang = pi() * f64(2usize * k + n - 1usize) / f64(2usize * n)
        let sr = math.cos[f64](ang)
        let si = math.sin[f64](ang)
        // roots of s^2 - (bw p) s + w0sq = 0: s = (bw p / 2) +- sqrt((bw p / 2)^2 - w0sq)
        let hr = bw * sr / 2.0f64
        let hi = bw * si / 2.0f64
        let dr = hr * hr - hi * hi - w0sq
        let di = 2.0f64 * hr * hi
        // complex square root
        let mag = math.sqrt[f64](dr * dr + di * di)
        var rr = math.sqrt[f64]((mag + dr) / 2.0f64)
        var ri = math.sqrt[f64]((mag - dr) / 2.0f64)
        if di < 0.0f64 { ri = 0.0f64 - ri }
        let s1r = hr + rr
        let s1i = hi + ri
        let s2r = hr - rr
        let s2i = hi - ri
        rr = 0.0f64
        pr[np] = bilin_re(s1r, s1i)
        pim[np] = bilin_im(s1r, s1i)
        np += 1usize
        pr[np] = bilin_re(s2r, s2i)
        pim[np] = bilin_im(s2r, s2i)
        np += 1usize
        k += 1usize
    }
    var zr: [40]f64 = zero
    var zi: [40]f64 = zero
    var j = 0usize
    while j < n {
        zr[j] = 1.0f64
        zr[n + j] = -1.0f64
        j += 1usize
    }
    poly_from_roots(pr[0usize..2usize * n], pim[0usize..2usize * n], a)
    poly_from_roots(zr[0usize..2usize * n], zi[0usize..2usize * n], b)
    // unit gain at the digital image of the analog centre frequency sqrt(w1 w2)
    let theta = 2.0f64 * math.atan[f64](math.sqrt[f64](w0sq) / 4.0f64)
    let (br, bi, wr1, wi1) = poly_resp(b, theta)
    let (ar, ai, wr2, wi2) = poly_resp(a, theta)
    let gm = math.sqrt[f64]((ar * ar + ai * ai) / (br * br + bi * bi))
    j = 0usize
    while j <= 2usize * n {
        b[j] = b[j] * gm
        j += 1usize
    }
}

fn bilin_re(sr: f64, si: f64) -> f64 {
    let nr = 1.0f64 + sr / 4.0f64
    let ni = si / 4.0f64
    let dr = 1.0f64 - sr / 4.0f64
    let di = 0.0f64 - si / 4.0f64
    ret (nr * dr + ni * di) / (dr * dr + di * di)
}

fn bilin_im(sr: f64, si: f64) -> f64 {
    let nr = 1.0f64 + sr / 4.0f64
    let ni = si / 4.0f64
    let dr = 1.0f64 - sr / 4.0f64
    let di = 0.0f64 - si / 4.0f64
    ret (ni * dr - nr * di) / (dr * dr + di * di)
}

// approx(x, y, v, ties = "ordered") for sorted x that may repeat: the value at the last knot at or below v, linear to the next
fn approx_ord(x: []const f64, y: []const f64, n: usize, v: f64) -> f64 {
    if v >= x[n - 1usize] { ret y[n - 1usize] }
    var i = 0usize
    var j = 1usize
    while j < n - 1usize {
        if x[j] <= v { i = j }
        j += 1usize
    }
    if v == x[i] { ret y[i] }
    ret y[i] + (y[i + 1usize] - y[i]) * ((v - x[i]) / (x[i + 1usize] - x[i]))
}

// fir2(n, f, m, grid_n, ramp_n, hamming(n + 1)): frequency-sampling FIR design of n + 1 taps into out; f ascends from 0 to 1 with m the gains at those points
fn fir2(a: *mem.Arena, n: usize, f: []const f64, m: []const f64, grid_n0: usize, ramp_n: f64, out: []f64) -> err {
    let t = f.len
    var grid_n = grid_n0
    if 2usize * grid_n < n + 1usize {
        var p2 = 1usize
        while p2 < n + 1usize { p2 *= 2usize }
        grid_n = p2
    }
    let gn = f64(grid_n)
    let (fb, e1) = mem.alloc[f64](a, 3usize * t)
    if e1 != ok { ret e1 }
    let (mb, e2) = mem.alloc[f64](a, 3usize * t)
    if e2 != ok { ret e2 }
    var nf = 0usize
    let (fx, e3) = mem.alloc[f64](a, 3usize * t)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < t {
        fx[i] = f[i]
        i += 1usize
    }
    nf = t
    if ramp_n > 0.0f64 {
        var extra = 0usize
        i = 0usize
        while i + 1usize < t {
            if f[i + 1usize] == f[i] {
                fx[i] = f[i] - ramp_n / gn / 2.0f64
                fx[i + 1usize] = f[i + 1usize] + ramp_n / gn / 2.0f64
                fx[t + extra] = f[i]
                extra += 1usize
            }
            i += 1usize
        }
        nf = t + extra
        i = 0usize
        while i < nf {
            if fx[i] < 0.0f64 { fx[i] = 0.0f64 }
            if fx[i] > 1.0f64 { fx[i] = 1.0f64 }
            i += 1usize
        }
        // sort and unique
        i = 1usize
        while i < nf {
            let tv = fx[i]
            var q = i
            while q > 0usize && fx[q - 1usize] > tv {
                fx[q] = fx[q - 1usize]
                q -= 1usize
            }
            fx[q] = tv
            i += 1usize
        }
        var w = 0usize
        i = 0usize
        while i < nf {
            if w == 0usize || fx[i] != fx[w - 1usize] {
                fx[w] = fx[i]
                w += 1usize
            }
            i += 1usize
        }
        nf = w
        i = 0usize
        while i < nf {
            mb[i] = approx_ord(f, m, t, fx[i])
            i += 1usize
        }
        i = 0usize
        while i < nf {
            fb[i] = fx[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < t {
            fb[i] = f[i]
            mb[i] = m[i]
            i += 1usize
        }
    }
    let (grid, e4) = mem.alloc[f64](a, grid_n + 1usize)
    if e4 != ok { ret e4 }
    i = 0usize
    while i <= grid_n {
        grid[i] = approx_ord(fb, mb, nf, f64(i) / gn)
        i += 1usize
    }
    let odd = n % 2usize == 1usize
    var big = 2usize * grid_n
    if odd { big = 4usize * grid_n }
    let (v, e5) = mem.alloc[f64](a, big)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < big {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i <= grid_n {
        v[i] = grid[i]
        i += 1usize
    }
    // the mirrored tail grid[grid_n .. 2] closes the sequence
    i = 0usize
    while i + 1usize < grid_n {
        v[big - 1usize - i] = grid[i + 1usize]
        i += 1usize
    }
    let (bb, e6) = mem.alloc[f64](a, n + 1usize)
    if e6 != ok { ret e6 }
    var k = 0usize
    while k <= n {
        var idx = 0usize
        if !odd {
            let fl = (n + 1usize) / 2usize
            let ce = n + 1usize - fl
            if k < fl { idx = big - fl + k } else { idx = k - fl }
            let _ = ce
        } else {
            let h2 = (n + 1usize) / 2usize
            if k < h2 { idx = big - n + 2usize * k } else { idx = 2usize * (k - h2) + 1usize }
        }
        var s = 0.0f64
        var j = 0usize
        while j < big {
            s += v[j] * math.cos[f64](2.0f64 * pi() * f64((j * idx) % big) / f64(big))
            j += 1usize
        }
        s = s / f64(big)
        if odd { s = 2.0f64 * s }
        bb[k] = s
        k += 1usize
    }
    k = 0usize
    while k <= n {
        out[k] = bb[k] * (0.54f64 - 0.46f64 * math.cos[f64](2.0f64 * pi() * f64(k) / f64(n)))
        k += 1usize
    }
    ret ok
}
