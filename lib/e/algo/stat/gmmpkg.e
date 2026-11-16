// R gmm for the linear model y = X b with instruments Z (n by q, q >= p): the two-step estimator with an iid weighting (sigma^2 Z'Z / n, which is two-stage least squares)
// or the heteroskedasticity-consistent centred moment covariance (vcov = "MDS") with the five HAC kernels at a fixed bandwidth, its covariance matrix and the Hansen J statistic.
//
// Not here: the Andrews and Newey-West bandwidth selectors, prewhitening, the iterated and CUE estimators, nonlinear moment functions and the linear hypothesis tests.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// A' B for A (n by p) and B (n by q), row-major, into out (p by q)
fn crossp(a: []const f64, b: []const f64, n: usize, p: usize, q: usize, out: []f64) {
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += a[r * p + i] * b[r * q + j]
                r += 1usize
            }
            out[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// the GMM step with weight matrix w (q by q): b = (X'Z W Z'X)^-1 X'Z W Z'y; xz is p by q, zy is q
fn gmm_step(a: *mem.Arena, xz: []const f64, zy: []const f64, w: []const f64, p: usize, q: usize, beta: []f64) -> err {
    let (xzw, e1) = mem.alloc[f64](a, p * q)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var k = 0usize
            while k < q {
                s += xz[i * q + k] * w[k * q + j]
                k += 1usize
            }
            xzw[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
    let (m, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    let (mi, e3) = mem.alloc[f64](a, p * p)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < q {
                s += xzw[i * q + k] * xz[j * q + k]
                k += 1usize
            }
            m[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if ols.inverse(a, m, p, mi) != ok { ret e1 }
    i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            var t = 0.0f64
            var k = 0usize
            while k < q {
                t += xzw[j * q + k] * zy[k]
                k += 1usize
            }
            s += mi[i * p + j] * t
            j += 1usize
        }
        beta[i] = s
        i += 1usize
    }
    ret ok
}

// the centred moment covariance (1 / n) sum (g_i - gbar)(g_i - gbar)' of g_i = z_i e_i into s (q by q) and the moment mean into gbar
fn moment_cov(z: []const f64, e: []const f64, n: usize, q: usize, s: []f64, gbar: []f64) {
    var j = 0usize
    while j < q {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += z[i * q + j] * e[i]
            i += 1usize
        }
        gbar[j] = m / f64(n)
        j += 1usize
    }
    j = 0usize
    while j < q {
        var k = 0usize
        while k < q {
            var t = 0.0f64
            var i = 0usize
            while i < n {
                t += (z[i * q + j] * e[i] - gbar[j]) * (z[i * q + k] * e[i] - gbar[k])
                i += 1usize
            }
            s[j * q + k] = t / f64(n)
            k += 1usize
        }
        j += 1usize
    }
}

// the HAC kernel weight at lag j for bandwidth bw: kind 2 Bartlett, 3 Parzen, 4 Truncated, 5 Tukey-Hanning, 6 Quadratic Spectral
fn kernel_weight(kind: usize, j: f64, bw: f64) -> f64 {
    let x = j / bw
    let pi = 3.141592653589793238462643383279f64
    if kind == 2usize {
        if x < 1.0f64 { ret 1.0f64 - x }
        ret 0.0f64
    }
    if kind == 3usize {
        if x <= 0.5f64 { ret 1.0f64 - 6.0f64 * x * x + 6.0f64 * x * x * x }
        if x <= 1.0f64 { ret 2.0f64 * (1.0f64 - x) * (1.0f64 - x) * (1.0f64 - x) }
        ret 0.0f64
    }
    if kind == 4usize {
        if x <= 1.0f64 { ret 1.0f64 }
        ret 0.0f64
    }
    if kind == 5usize {
        if x <= 1.0f64 { ret (1.0f64 + math.cos[f64](pi * x)) / 2.0f64 }
        ret 0.0f64
    }
    let u = 6.0f64 * pi * x / 5.0f64
    ret 25.0f64 / (12.0f64 * pi * pi * x * x) * (math.sin[f64](u) / u - math.cos[f64](u))
}

// the moment covariance of g_i = z_i e_i: the centred lag-0 term for mode 1, plus the kernel-weighted autocovariances for the HAC modes 2 to 6
fn moment_cov_mode(z: []const f64, e: []const f64, n: usize, q: usize, mode: usize, bw: f64, s: []f64, gbar: []f64) {
    moment_cov(z, e, n, q, s, gbar)
    if mode < 2usize { ret }
    var lag = 1usize
    while lag < n {
        let w = kernel_weight(mode, f64(lag), bw)
        if w != 0.0f64 {
            var j = 0usize
            while j < q {
                var k = 0usize
                while k < q {
                    var t = 0.0f64
                    var i = lag
                    while i < n {
                        t += (z[i * q + j] * e[i] - gbar[j]) * (z[(i - lag) * q + k] * e[i - lag] - gbar[k])
                        i += 1usize
                    }
                    s[j * q + k] += w * t / f64(n)
                    s[k * q + j] += w * t / f64(n)
                    k += 1usize
                }
                j += 1usize
            }
        } else if mode != 6usize { break }
        lag += 1usize
    }
}

// the linear two-step GMM: what 0 the coefficient `idx`, 1 the covariance entry idx (row * p + col), 2 the J statistic; mds is true for vcov = "MDS", false for "iid"
fn gmm_linear(a: *mem.Arena, y: []const f64, x: []const f64, z: []const f64, n: usize, p: usize, q: usize, mode: usize, bw: f64, what: usize, idx: usize) -> f64 {
    let mds = mode >= 1usize
    let nf = f64(n)
    let (xz, e1) = mem.alloc[f64](a, p * q)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (zy, e2) = mem.alloc[f64](a, q)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (zz, e3) = mem.alloc[f64](a, q * q)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (zzi, e4) = mem.alloc[f64](a, q * q)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    crossp(x, z, n, p, q, xz)
    crossp(z, z, n, q, q, zz)
    var i = 0usize
    while i < q {
        var s = 0.0f64
        var r = 0usize
        while r < n {
            s += z[r * q + i] * y[r]
            r += 1usize
        }
        zy[i] = s
        i += 1usize
    }
    if ols.inverse(a, zz, q, zzi) != ok { ret 0.0f64 / 0.0f64 }
    let (w0, e5) = mem.alloc[f64](a, q * q)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < q * q {
        w0[i] = zzi[i] * nf
        i += 1usize
    }
    let (b0, e6) = mem.alloc[f64](a, p)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    // the weight (Z'Z / n)^-1 and the iid weight differ only by the scale, which cancels in the estimate
    if gmm_step(a, xz, zy, w0, p, q, b0) != ok { ret 0.0f64 / 0.0f64 }
    let (e, e7) = mem.alloc[f64](a, n)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    let (sm, e8) = mem.alloc[f64](a, q * q)
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    let (gb, e9) = mem.alloc[f64](a, q)
    if e9 != ok { ret 0.0f64 / 0.0f64 }
    let (b, e10) = mem.alloc[f64](a, p)
    if e10 != ok { ret 0.0f64 / 0.0f64 }
    let (gb2, e15) = mem.alloc[f64](a, q)
    if e15 != ok { ret 0.0f64 / 0.0f64 }
    let (w, e11) = mem.alloc[f64](a, q * q)
    if e11 != ok { ret 0.0f64 / 0.0f64 }
    let (wi, e12) = mem.alloc[f64](a, q * q)
    if e12 != ok { ret 0.0f64 / 0.0f64 }
    var r = 0usize
    while r < n {
        var fit = 0.0f64
        var j = 0usize
        while j < p {
            fit += x[r * p + j] * b0[j]
            j += 1usize
        }
        e[r] = y[r] - fit
        r += 1usize
    }
    if mds {
        moment_cov_mode(z, e, n, q, mode, bw, sm, gb)
        if ols.inverse(a, sm, q, w) != ok { ret 0.0f64 / 0.0f64 }
        if gmm_step(a, xz, zy, w, p, q, b) != ok { ret 0.0f64 / 0.0f64 }
    } else {
        i = 0usize
        while i < p {
            b[i] = b0[i]
            i += 1usize
        }
    }
    // the residuals and moment covariance at the final coefficients
    r = 0usize
    while r < n {
        var fit = 0.0f64
        var j = 0usize
        while j < p {
            fit += x[r * p + j] * b[j]
            j += 1usize
        }
        e[r] = y[r] - fit
        r += 1usize
    }
    var jg = 0usize
    while jg < q {
        var m2 = 0.0f64
        var rr = 0usize
        while rr < n {
            m2 += z[rr * q + jg] * e[rr]
            rr += 1usize
        }
        gb2[jg] = m2 / nf
        jg += 1usize
    }
    if what == 0usize { ret b[idx] }
    var sig2 = 0.0f64
    r = 0usize
    while r < n {
        sig2 += e[r] * e[r]
        r += 1usize
    }
    sig2 = sig2 / nf
    if mds {
        moment_cov_mode(z, e, n, q, mode, bw, sm, gb)
    } else {
        i = 0usize
        while i < q * q {
            sm[i] = sig2 * zz[i] / nf
            i += 1usize
        }
        var j = 0usize
        while j < q {
            var m = 0.0f64
            r = 0usize
            while r < n {
                m += z[r * q + j] * e[r]
                r += 1usize
            }
            gb[j] = m / nf
            j += 1usize
        }
    }
    if ols.inverse(a, sm, q, wi) != ok { ret 0.0f64 / 0.0f64 }
    if what == 2usize {
        // the criterion at the final coefficients under the weight the last step used (the iid weight for iid, the first-step moment covariance for MDS)
        var jstat = 0.0f64
        i = 0usize
        while i < q {
            var j = 0usize
            while j < q {
                var wij = wi[i * q + j]
                if mds { wij = w[i * q + j] }
                jstat += gb2[i] * wij * gb2[j]
                j += 1usize
            }
            i += 1usize
        }
        ret nf * jstat
    }
    // the covariance (D' S^-1 D)^-1 / n with D = X'Z / n
    let (m, e13) = mem.alloc[f64](a, p * p)
    if e13 != ok { ret 0.0f64 / 0.0f64 }
    let (mi, e14) = mem.alloc[f64](a, p * p)
    if e14 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < q {
                var l = 0usize
                while l < q {
                    s += xz[i * q + k] / nf * wi[k * q + l] * xz[j * q + l] / nf
                    l += 1usize
                }
                k += 1usize
            }
            m[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if ols.inverse(a, m, p, mi) != ok { ret 0.0f64 / 0.0f64 }
    ret mi[idx] / nf
}
