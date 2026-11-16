// R fracdiff: `diffseries` (the fractionally differenced, mean-centred series, summed directly where R
// convolves by FFT), and the log-periodogram estimates `periodogram_fit` for fdGPH (Geweke and
// Porter-Hudak) and fdSperio (the smoothed periodogram variant), each answering d and the asymptotic and
// regression standard errors.
//
// And `fracdiff_sim` (fdsim.c over R-stream normal innovations). Not here: fracdiff (the Haslett-Raftery approximate likelihood fit).

use e.math
use e.mem
use e.algo.rand.r as rng
use e.math.nmath as nm

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    var m = s / f64(x.len)
    var t = 0.0f64
    i = 0usize
    while i < x.len {
        t += x[i] - m
        i += 1usize
    }
    ret m + t / f64(x.len)
}

// diffseries(x, d)
fn diffseries(a: *mem.Arena, x: []const f64, d: f64) -> ([]f64, err) {
    let n = x.len
    let m = mean_of(x)
    let (b, be) = mem.alloc[f64](a, n)
    if be != ok { ret (b, be) }
    b[0usize] = 1.0f64
    var k = 1usize
    while k < n {
        b[k] = b[k - 1usize] * (f64(k) - (d + 1.0f64)) / f64(k)
        k += 1usize
    }
    let (out, oe) = mem.alloc[f64](a, n)
    if oe != ok { ret (out, oe) }
    var t = 0usize
    while t < n {
        var s = 0.0f64
        k = 0usize
        while k <= t {
            s += b[k] * (x[t - k] - m)
            k += 1usize
        }
        out[t] = s
        t += 1usize
    }
    ret (out, ok)
}

// the shared log-periodogram regression: (d, sd.as, sd.reg); smoothed uses the lag window with exponent beta
fn periodogram_fit(a: *mem.Arena, x0: []const f64, bandw: f64, smoothed: bool, beta: f64) -> (f64, f64, f64, err) {
    let n = x0.len
    let nf = f64(n)
    let g = usize(math.floor[f64](math.pow[f64](nf, bandw)))
    let m0 = mean_of(x0)
    let (x, xe) = mem.alloc[f64](a, n)
    if xe != ok { ret (0.0f64, 0.0f64, 0.0f64, xe) }
    var i = 0usize
    var varx = 0.0f64
    while i < n {
        x[i] = x0[i] - m0
        varx += x[i] * x[i]
        i += 1usize
    }
    varx = varx / nf
    let (cov, ce) = mem.alloc[f64](a, n)
    if ce != ok { ret (0.0f64, 0.0f64, 0.0f64, ce) }
    var k = 1usize
    while k < n {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += x[i] * x[i + k]
            i += 1usize
        }
        cov[k] = s / nf
        k += 1usize
    }
    var mm = 0.0f64
    var m2 = 0.0f64
    let (pw, pe) = mem.alloc[f64](a, n)
    if pe != ok { ret (0.0f64, 0.0f64, 0.0f64, pe) }
    k = 1usize
    while k < n {
        pw[k] = 1.0f64
        k += 1usize
    }
    if smoothed {
        mm = math.floor[f64](math.pow[f64](nf, beta))
        m2 = math.floor[f64](mm / 2.0f64)
        k = 1usize
        while k < n {
            let ak = f64(k) / mm
            if f64(k) <= m2 {
                pw[k] = 1.0f64 - 6.0f64 * ak * ak * (1.0f64 - ak)
            } else if f64(k) <= mm {
                pw[k] = 2.0f64 * (1.0f64 - ak) * (1.0f64 - ak) * (1.0f64 - ak)
            } else {
                pw[k] = 0.0f64
            }
            k += 1usize
        }
    }
    let (xr, xre) = mem.alloc[f64](a, g)
    let (yr, yre) = mem.alloc[f64](a, g)
    if xre != ok { ret (0.0f64, 0.0f64, 0.0f64, xre) }
    if yre != ok { ret (0.0f64, 0.0f64, 0.0f64, yre) }
    var np = 0usize
    var j = 1usize
    while j <= g {
        let w = 2.0f64 * 3.141592653589793f64 * f64(j) / nf
        var s = 0.0f64
        k = 1usize
        while k < n {
            s += cov[k] * pw[k] * math.cos[f64](w * f64(k))
            k += 1usize
        }
        let per = varx + 2.0f64 * s
        if per > 0.0f64 {
            yr[np] = math.log[f64](per / (2.0f64 * 3.141592653589793f64))
            xr[np] = 2.0f64 * math.log[f64](2.0f64 * math.sin[f64](w / 2.0f64))
            np += 1usize
        }
        j += 1usize
    }
    var mx = 0.0f64
    var my = 0.0f64
    i = 0usize
    while i < np {
        mx += xr[i]
        my += yr[i]
        i += 1usize
    }
    mx = mx / f64(np)
    my = my / f64(np)
    var sxx = 0.0f64
    var sxy = 0.0f64
    i = 0usize
    while i < np {
        sxx += (xr[i] - mx) * (xr[i] - mx)
        sxy += (xr[i] - mx) * (yr[i] - my)
        i += 1usize
    }
    let slope = sxy / sxx
    let icpt = my - slope * mx
    var rss = 0.0f64
    i = 0usize
    while i < np {
        let r = yr[i] - icpt - slope * xr[i]
        rss += r * r
        i += 1usize
    }
    var vard = 3.141592653589793f64 * 3.141592653589793f64 / (6.0f64 * sxx)
    if smoothed { vard = (0.539285f64 * mm / nf) / sxx }
    let varreg = rss / ((f64(g) - 1.0f64) * sxx)
    ret (0.0f64 - slope, math.sqrt[f64](vard), math.sqrt[f64](varreg), ok)
}

// fracdiff.sim(n, ar, ma, d, mu, n.start) with R's default innovations: R draws the n + q innovations first and the n.start start-up
// values second, then runs fdsim over start-up and innovations and keeps the n values after the burn-in. n_start is not computed from
// the roots of the AR polynomial; pass it (for no AR part R's default is q).
fn fracdiff_sim(a: *mem.Arena, g: *rng.Rng, n: usize, ar: []const f64, ma: []const f64, d: f64, mu: f64, n_start: usize) -> ([]f64, err) {
    let p = ar.len
    let q = ma.len
    let nn = n + n_start
    let (y, e1) = mem.alloc[f64](a, nn + q + 2usize)
    let (s, e2) = mem.alloc[f64](a, nn + q + 2usize)
    let (out, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret (out, e1) }
    if e2 != ok { ret (out, e2) }
    if e3 != ok { ret (out, e3) }
    var i = 0usize
    while i < nn + q + 2usize {
        y[i] = 0.0f64
        s[i] = 0.0f64
        i += 1usize
    }
    // y(1..) is 1-based: start-up values first, innovations after, but the innovations were drawn first
    i = 0usize
    while i < n + q {
        y[n_start + 1usize + i] = rng.rnorm(g, 0.0f64, 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < n_start {
        y[1usize + i] = rng.rnorm(g, 0.0f64, 1.0f64)
        i += 1usize
    }
    let temp0 = 1.0f64 / nm.gammafn(1.0f64 - d)
    var vk = nm.gammafn(1.0f64 - 2.0f64 * d) * (temp0 * temp0)
    y[1usize] = y[1usize] * math.sqrt[f64](vk)
    var temp = d / (1.0f64 - d)
    vk = vk * (1.0f64 - temp * temp)
    var amk = temp * y[1usize]
    s[1usize] = temp
    y[2usize] = amk + y[2usize] * math.sqrt[f64](vk)
    var k = 3usize
    while k <= nn + q {
        let dk1 = f64(k) - 1.0f64
        let dk1d = dk1 - d
        var j = 1usize
        while j <= k - 2usize {
            let dj = dk1 - f64(j)
            s[j] = s[j] * (dk1 * (dj - d) / (dk1d * dj))
            j += 1usize
        }
        temp = d / dk1d
        s[k - 1usize] = temp
        vk = vk * (1.0f64 - temp * temp)
        amk = 0.0f64
        j = 1usize
        while j <= k - 1usize {
            amk += s[j] * y[k - j]
            j += 1usize
        }
        y[k] = amk + y[k] * math.sqrt[f64](vk)
        k += 1usize
    }
    k = 1usize
    while k <= nn {
        var sum = 0.0f64
        var jm = p
        if k - 1usize < jm { jm = k - 1usize }
        var t = 0usize
        while t < jm {
            sum += ar[t] * s[k - t - 1usize]
            t += 1usize
        }
        t = 0usize
        while t < q {
            sum -= ma[t] * y[k + q - t - 1usize]
            t += 1usize
        }
        s[k] = sum + y[k + q]
        k += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = s[n_start + 1usize + i]
        if mu != 0.0f64 { out[i] = out[i] + mu }
        i += 1usize
    }
    ret (out, ok)
}
