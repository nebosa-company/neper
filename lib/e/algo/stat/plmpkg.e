// R plm for a balanced panel (N individuals, T periods, rows ordered by individual): the within, between and random-effects (Swamy-Arora) estimators of y on K regressors, with their classical standard errors and the variance components. The caller passes x without a constant; between and random add one.
//
// Not here: unbalanced panels, the Wallace-Hussain, Amemiya and Nerlove components, two-way effects, robust standard errors and tests.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// OLS of y (n) on x (n by m, row-major): beta into b, the inverse of x'x into xi (m by m); returns the residual sum of squares, NaN if singular
fn ols(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, m: usize, b: []f64, xi: []f64) -> f64 {
    let (g, e1) = mem.alloc[f64](a, m * m)
    let (r, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < m * m {
        g[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        r[i] = 0.0f64
        i += 1usize
    }
    var t = 0usize
    while t < n {
        i = 0usize
        while i < m {
            r[i] += x[t * m + i] * y[t]
            var j = 0usize
            while j < m {
                g[i * m + j] += x[t * m + i] * x[t * m + j]
                j += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    let (inv, ie) = gp.invert(a, g, m)
    if ie != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < m {
        var s = 0.0f64
        var j = 0usize
        while j < m {
            xi[i * m + j] = inv[i * m + j]
            s += inv[i * m + j] * r[j]
            j += 1usize
        }
        b[i] = s
        i += 1usize
    }
    var rss = 0.0f64
    t = 0usize
    while t < n {
        var f = 0.0f64
        i = 0usize
        while i < m {
            f += x[t * m + i] * b[i]
            i += 1usize
        }
        rss += (y[t] - f) * (y[t] - f)
        t += 1usize
    }
    ret rss
}

// out layout: within coef (k), within se (k), sigma2_e, between coef (k + 1, constant first), random coef (k + 1), random se (k + 1), sigma2_mu, theta
fn panel(a: *mem.Arena, x: []const f64, y: []const f64, nn: usize, tt: usize, k: usize, out: []f64) -> err {
    let n = nn * tt
    let (xd, e1) = mem.alloc[f64](a, n * k)
    let (yd, e2) = mem.alloc[f64](a, n)
    let (xm, e3) = mem.alloc[f64](a, nn * (k + 1usize))
    let (ym, e4) = mem.alloc[f64](a, nn)
    let (xg, e5) = mem.alloc[f64](a, n * (k + 1usize))
    let (yg, e6) = mem.alloc[f64](a, n)
    let (b, e7) = mem.alloc[f64](a, k + 1usize)
    let (xi, e8) = mem.alloc[f64](a, (k + 1usize) * (k + 1usize))
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    let tf = f64(tt)
    var i = 0usize
    while i < nn {
        var s = 0.0f64
        var t = 0usize
        while t < tt {
            s += y[i * tt + t]
            t += 1usize
        }
        ym[i] = s / tf
        xm[i * (k + 1usize)] = 1.0f64
        var c = 0usize
        while c < k {
            var sx = 0.0f64
            t = 0usize
            while t < tt {
                sx += x[(i * tt + t) * k + c]
                t += 1usize
            }
            xm[i * (k + 1usize) + 1usize + c] = sx / tf
            t = 0usize
            while t < tt {
                xd[(i * tt + t) * k + c] = x[(i * tt + t) * k + c] - sx / tf
                t += 1usize
            }
            c += 1usize
        }
        t = 0usize
        while t < tt {
            yd[i * tt + t] = y[i * tt + t] - ym[i]
            t += 1usize
        }
        i += 1usize
    }
    let rss_w = ols(a, xd, yd, n, k, b, xi)
    if rss_w != rss_w { ret gp.Singular }
    let s2e = rss_w / f64(n - nn - k)
    i = 0usize
    while i < k {
        out[i] = b[i]
        out[k + i] = math.sqrt[f64](s2e * xi[i * k + i])
        i += 1usize
    }
    out[2usize * k] = s2e
    let kb = k + 1usize
    let rss_b = ols(a, xm, ym, nn, kb, b, xi)
    if rss_b != rss_b { ret gp.Singular }
    i = 0usize
    while i < kb {
        out[2usize * k + 1usize + i] = b[i]
        i += 1usize
    }
    let s2b = rss_b / f64(nn - kb)
    var s2mu = s2b - s2e / tf
    if s2mu < 0.0f64 { s2mu = 0.0f64 }
    let theta = 1.0f64 - math.sqrt[f64](s2e / (s2e + tf * s2mu))
    i = 0usize
    while i < nn {
        var t = 0usize
        while t < tt {
            let r = i * tt + t
            yg[r] = y[r] - theta * ym[i]
            xg[r * kb] = 1.0f64 - theta
            var c = 0usize
            while c < k {
                xg[r * kb + 1usize + c] = x[r * k + c] - theta * xm[i * kb + 1usize + c]
                c += 1usize
            }
            t += 1usize
        }
        i += 1usize
    }
    let rss_r = ols(a, xg, yg, n, kb, b, xi)
    if rss_r != rss_r { ret gp.Singular }
    i = 0usize
    while i < kb {
        out[2usize * k + 1usize + kb + i] = b[i]
        out[2usize * k + 1usize + 2usize * kb + i] = math.sqrt[f64](rss_r / f64(n - kb) * xi[i * kb + i])
        i += 1usize
    }
    out[2usize * k + 1usize + 3usize * kb] = s2mu
    out[2usize * k + 2usize + 3usize * kb] = theta
    ret ok
}
