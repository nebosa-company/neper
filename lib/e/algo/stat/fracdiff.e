// R fracdiff: `diffseries` (the fractionally differenced, mean-centred series, summed directly where R
// convolves by FFT), and the log-periodogram estimates `periodogram_fit` for fdGPH (Geweke and
// Porter-Hudak) and fdSperio (the smoothed periodogram variant), each answering d and the asymptotic and
// regression standard errors.
//
// Not here: fracdiff (the Haslett-Raftery approximate likelihood fit) and fracdiff.sim.

use e.math
use e.mem

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
