// R car, lmtest and sandwich for a linear model y = X b (X with the intercept column): the OLS fit with its hat values, the heteroskedasticity-consistent
// covariances vcovHC of types HC0 to HC4, the Durbin-Watson statistic, the studentized Breusch-Pagan statistic, and the variance inflation factors.
//
// Not here: the other covariance families (HAC, clustered, bootstrap), the other lmtest tests (RESET, Harvey-Collier, Goldfeld-Quandt, the non-studentized
// Breusch-Pagan), p values, Anova and the rest of car.

use e.algo.rand.r as rng
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Fit = struct { beta: []f64, resid: []f64, hat: []f64, xtx_inv: []f64 }

// the inverse of a p by p matrix by Gauss-Jordan elimination with partial pivoting
fn inverse(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> err {
    let (w, e) = mem.alloc[f64](a, p * 2usize * p)
    if e != ok { ret e }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            w[i * 2usize * p + j] = m[i * p + j]
            w[i * 2usize * p + p + j] = 0.0f64
            j += 1usize
        }
        w[i * 2usize * p + p + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var piv = c
        var k = c + 1usize
        while k < p {
            if math.abs[f64](w[k * 2usize * p + c]) > math.abs[f64](w[piv * 2usize * p + c]) { piv = k }
            k += 1usize
        }
        var j = 0usize
        while j < 2usize * p {
            let t = w[c * 2usize * p + j]
            w[c * 2usize * p + j] = w[piv * 2usize * p + j]
            w[piv * 2usize * p + j] = t
            j += 1usize
        }
        let d = w[c * 2usize * p + c]
        j = 0usize
        while j < 2usize * p {
            w[c * 2usize * p + j] = w[c * 2usize * p + j] / d
            j += 1usize
        }
        k = 0usize
        while k < p {
            if k != c {
                let f = w[k * 2usize * p + c]
                j = 0usize
                while j < 2usize * p {
                    w[k * 2usize * p + j] -= f * w[c * 2usize * p + j]
                    j += 1usize
                }
            }
            k += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            out[i * p + j] = w[i * 2usize * p + p + j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn ols(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (Fit, err) {
    var f: Fit = zero
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret (f, e1) }
    let (inv, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret (f, e2) }
    let (xty, e3) = mem.alloc[f64](a, p)
    if e3 != ok { ret (f, e3) }
    let (beta, e4) = mem.alloc[f64](a, p)
    if e4 != ok { ret (f, e4) }
    let (res, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret (f, e5) }
    let (hat, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret (f, e6) }
    var i = 0usize
    while i < p * p {
        xtx[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        xty[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            xty[j] += x[i * p + j] * y[i]
            var k = 0usize
            while k < p {
                xtx[j * p + k] += x[i * p + j] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let ie = inverse(a, xtx, p, inv)
    if ie != ok { ret (f, ie) }
    i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            s += inv[i * p + j] * xty[j]
            j += 1usize
        }
        beta[i] = s
        i += 1usize
    }
    i = 0usize
    while i < n {
        var fit = 0.0f64
        var h = 0.0f64
        var j = 0usize
        while j < p {
            fit += x[i * p + j] * beta[j]
            var k = 0usize
            while k < p {
                h += x[i * p + j] * inv[j * p + k] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        res[i] = y[i] - fit
        hat[i] = h
        i += 1usize
    }
    f.beta = beta
    f.resid = res
    f.hat = hat
    f.xtx_inv = inv
    ret (f, ok)
}

// the diagonal of vcovHC(type): ty 0 HC0, 1 HC1, 2 HC2, 3 HC3, 4 HC4; out has p entries
fn vcov_hc_diag(a: *mem.Arena, x: []const f64, n: usize, p: usize, f: *const Fit, ty: usize, out: []f64) -> err {
    let (meat, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p * p {
        meat[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var w = f.resid[i] * f.resid[i]
        let h = f.hat[i]
        if ty == 2usize { w = w / (1.0f64 - h) }
        if ty == 3usize { w = w / ((1.0f64 - h) * (1.0f64 - h)) }
        if ty == 4usize {
            var dl = f64(n) * h / f64(p)
            if dl > 4.0f64 { dl = 4.0f64 }
            w = w / math.pow[f64](1.0f64 - h, dl)
        }
        var j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                meat[j * p + k] += w * x[i * p + j] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    var scale = 1.0f64
    if ty == 1usize { scale = f64(n) / f64(n - p) }
    // diag((X'X)^-1 meat (X'X)^-1)
    let (tmp, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += f.xtx_inv[j * p + l] * meat[l * p + k]
                l += 1usize
            }
            tmp[j * p + k] = s
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += tmp[j * p + k] * f.xtx_inv[k * p + j]
            k += 1usize
        }
        out[j] = s * scale
        j += 1usize
    }
    ret ok
}

fn durbin_watson(res: []const f64) -> f64 {
    var num = 0.0f64
    var den = res[0usize] * res[0usize]
    var i = 1usize
    while i < res.len {
        num += (res[i] - res[i - 1usize]) * (res[i] - res[i - 1usize])
        den += res[i] * res[i]
        i += 1usize
    }
    ret num / den
}

// the studentized Breusch-Pagan statistic n R^2 of the regression of the squared residuals on X
fn bp_studentized(a: *mem.Arena, x: []const f64, n: usize, p: usize, res: []const f64) -> f64 {
    let (e2, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        e2[i] = res[i] * res[i]
        mean += e2[i]
        i += 1usize
    }
    mean = mean / f64(n)
    let (aux, e3) = ols(a, x, e2, n, p)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var tss = 0.0f64
    var rss = 0.0f64
    i = 0usize
    while i < n {
        tss += (e2[i] - mean) * (e2[i] - mean)
        rss += aux.resid[i] * aux.resid[i]
        i += 1usize
    }
    ret f64(n) * (1.0f64 - rss / tss)
}

// the variance inflation factor of column j (1 <= j < p, the intercept being column 0): 1 / (1 - R^2) of column j on the others
fn vif(a: *mem.Arena, x: []const f64, n: usize, p: usize, j: usize) -> f64 {
    let (xo, e1) = mem.alloc[f64](a, n * (p - 1usize))
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (yo, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var mean = 0.0f64
    while i < n {
        var c = 0usize
        var cc = 0usize
        while c < p {
            if c != j {
                xo[i * (p - 1usize) + cc] = x[i * p + c]
                cc += 1usize
            }
            c += 1usize
        }
        yo[i] = x[i * p + j]
        mean += yo[i]
        i += 1usize
    }
    mean = mean / f64(n)
    let (f, e3) = ols(a, xo, yo, n, p - 1usize)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var tss = 0.0f64
    var rss = 0.0f64
    i = 0usize
    while i < n {
        tss += (yo[i] - mean) * (yo[i] - mean)
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    ret tss / rss
}

// lmtest::bptest with the squared-residual scores f = e^2 / sigma2 - 1 regressed on X: studentized gives n ESS / sum(f^2), the classical form ESS / 2
fn bp_test(a: *mem.Arena, x: []const f64, n: usize, p: usize, res: []const f64, student: bool) -> f64 {
    let (f, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        s2 += res[i] * res[i]
        i += 1usize
    }
    s2 = s2 / f64(n)
    i = 0usize
    while i < n {
        f[i] = res[i] * res[i] / s2 - 1.0f64
        i += 1usize
    }
    let (aux, e2) = ols(a, x, f, n, p)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var ess = 0.0f64
    var ff = 0.0f64
    i = 0usize
    while i < n {
        let fit = f[i] - aux.resid[i]
        ess += fit * fit
        ff += f[i] * f[i]
        i += 1usize
    }
    if student { ret f64(n) * ess / ff }
    ret ess / 2.0f64
}

// resettest(power = 2:3, type = "fitted"): the F statistic of the added fitted^2 and fitted^3 terms
fn reset_f(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> f64 {
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (xe, e2) = mem.alloc[f64](a, n * (p + 2usize))
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var rss0 = 0.0f64
    while i < n {
        var j = 0usize
        while j < p {
            xe[i * (p + 2usize) + j] = x[i * p + j]
            j += 1usize
        }
        let fit = y[i] - f0.resid[i]
        xe[i * (p + 2usize) + p] = fit * fit
        xe[i * (p + 2usize) + p + 1usize] = fit * fit * fit
        rss0 += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let (f1, e3) = ols(a, xe, y, n, p + 2usize)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var rss1 = 0.0f64
    i = 0usize
    while i < n {
        rss1 += f1.resid[i] * f1.resid[i]
        i += 1usize
    }
    ret ((rss0 - rss1) / 2.0f64) / (rss1 / f64(n - p - 2usize))
}

// the upper-tail p value of a chi-square statistic and of an F statistic
fn p_chisq(stat: f64, df: f64) -> f64 { ret nm.pchisq(stat, df, false, false) }

fn p_f(stat: f64, df1: f64, df2: f64) -> f64 { ret nb.pf(stat, df1, df2, false, false) }

// gqtest(point = 0.5, fraction = 0): the ratio of the residual mean squares of the fits to the last and the first segment; the segments are the rows
// 1 .. floor(n / 2) and ceiling(n / 2 + 0.01) .. n; (statistic, df1, df2)
fn goldfeld_quandt(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (f64, f64, f64) {
    let point1 = n / 2usize
    let point2 = usize(math.ceil[f64](f64(n) * 0.5f64 + 0.01f64))
    let n2 = n - point2 + 1usize
    let (f1, e1) = ols(a, x[0usize..point1 * p], y[0usize..point1], point1, p)
    if e1 != ok { ret (0.0f64 / 0.0f64, 0.0f64, 0.0f64) }
    let (f2, e2) = ols(a, x[(point2 - 1usize) * p..n * p], y[point2 - 1usize..n], n2, p)
    if e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64, 0.0f64) }
    var r1 = 0.0f64
    var i = 0usize
    while i < point1 {
        r1 += f1.resid[i] * f1.resid[i]
        i += 1usize
    }
    var r2 = 0.0f64
    i = 0usize
    while i < n2 {
        r2 += f2.resid[i] * f2.resid[i]
        i += 1usize
    }
    let df1 = f64(n2 - p)
    let df2 = f64(point1 - p)
    ret ((r2 / df1) / (r1 / df2), df1, df2)
}

// NeweyWest(m, lag, prewhite = FALSE, adjust): the Bartlett-kernel HAC covariance diagonal (X'X)^-1 [sum_l w_l (G_l + G_l')] (X'X)^-1 with w_l = 1 - l / (lag + 1),
// G_l = sum_t u_t u_{t-l}' for u_t = x_t e_t, scaled by n / (n - p) when adjust
fn newey_west_diag(a: *mem.Arena, x: []const f64, n: usize, p: usize, f: *const Fit, lag: usize, adjust: bool, out: []f64) -> err {
    let (meat, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p * p {
        meat[i] = 0.0f64
        i += 1usize
    }
    var l = 0usize
    while l <= lag {
        var w = 1.0f64
        if l > 0usize { w = 1.0f64 - f64(l) / f64(lag + 1usize) }
        var t = l
        while t < n {
            var j = 0usize
            while j < p {
                var k = 0usize
                while k < p {
                    let g = x[t * p + j] * f.resid[t] * x[(t - l) * p + k] * f.resid[t - l]
                    meat[j * p + k] += w * g
                    if l > 0usize { meat[k * p + j] += w * g }
                    k += 1usize
                }
                j += 1usize
            }
            t += 1usize
        }
        l += 1usize
    }
    var scale = 1.0f64
    if adjust { scale = f64(n) / f64(n - p) }
    let (tmp, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += f.xtx_inv[j * p + q] * meat[q * p + k]
                q += 1usize
            }
            tmp[j * p + k] = s
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += tmp[j * p + k] * f.xtx_inv[k * p + j]
            k += 1usize
        }
        out[j] = s * scale
        j += 1usize
    }
    ret ok
}

// vcovCL(m, cluster, type, cadjust): the clustered covariance diagonal, meat = sum over clusters of (sum of the scores)(sum of the scores)', with the HC1 factor
// (n - 1) / (n - p) when ty is 1 (HC0 for 0) and the cluster factor G / (G - 1) when cadjust; the clusters are 0-based ids below ng
fn vcov_cl_diag(a: *mem.Arena, x: []const f64, n: usize, p: usize, f: *const Fit, cl: []const usize, ng: usize, ty: usize, cadjust: bool, out: []f64) -> err {
    let (sums, e1) = mem.alloc[f64](a, ng * p)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < ng * p {
        sums[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            sums[cl[i] * p + j] += x[i * p + j] * f.resid[i]
            j += 1usize
        }
        i += 1usize
    }
    let (meat, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    i = 0usize
    while i < p * p {
        meat[i] = 0.0f64
        i += 1usize
    }
    var g = 0usize
    while g < ng {
        var j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                meat[j * p + k] += sums[g * p + j] * sums[g * p + k]
                k += 1usize
            }
            j += 1usize
        }
        g += 1usize
    }
    var scale = 1.0f64
    if cadjust { scale = f64(ng) / f64(ng - 1usize) }
    if ty == 1usize { scale = scale * f64(n - 1usize) / f64(n - p) }
    let (tmp, e3) = mem.alloc[f64](a, p * p)
    if e3 != ok { ret e3 }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += f.xtx_inv[j * p + q] * meat[q * p + k]
                q += 1usize
            }
            tmp[j * p + k] = s
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += tmp[j * p + k] * f.xtx_inv[k * p + j]
            k += 1usize
        }
        out[j] = s * scale
        j += 1usize
    }
    ret ok
}

// lmtest::bgtest(order, fill = 0): type 0 Chisq (n sum(fitted^2) / sum(resid^2), df order) or 1 F; returns the statistic and its upper-tail p value
fn bg_test(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, order: usize, ty: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret (nan, nan) }
    let w = p + order
    let (xe, e2) = mem.alloc[f64](a, n * w)
    if e2 != ok { ret (nan, nan) }
    var i = 0usize
    var rss0 = 0.0f64
    while i < n {
        var j = 0usize
        while j < p {
            xe[i * w + j] = x[i * p + j]
            j += 1usize
        }
        var l = 1usize
        while l <= order {
            if i >= l { xe[i * w + p + l - 1usize] = f0.resid[i - l] } else { xe[i * w + p + l - 1usize] = 0.0f64 }
            l += 1usize
        }
        rss0 += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let (f1, e3) = ols(a, xe, f0.resid, n, w)
    if e3 != ok { ret (nan, nan) }
    var rss1 = 0.0f64
    var fit2 = 0.0f64
    i = 0usize
    while i < n {
        rss1 += f1.resid[i] * f1.resid[i]
        let fv = f0.resid[i] - f1.resid[i]
        fit2 += fv * fv
        i += 1usize
    }
    if ty == 0usize {
        let bg = f64(n) * fit2 / rss0
        ret (bg, p_chisq(bg, f64(order)))
    }
    let bg = ((rss0 - rss1) / f64(order)) / (rss1 / f64(n - p - order))
    ret (bg, p_f(bg, f64(order), f64(n - p - order)))
}

// lmtest::raintest(fraction = 0.5, center = 0.5): the rainbow F statistic and its p value, the central subset rows from..to of the data in its given order
fn rain_test(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let from = usize(math.ceil[f64](1.0f64 + f64(n - 1usize) * 0.25f64))
    let n1 = n / 2usize
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret (nan, nan) }
    let (f1, e2) = ols(a, x[(from - 1usize) * p..(from - 1usize + n1) * p], y[from - 1usize..from - 1usize + n1], n1, p)
    if e2 != ok { ret (nan, nan) }
    var s0 = 0.0f64
    var i = 0usize
    while i < n {
        s0 += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    var s1 = 0.0f64
    i = 0usize
    while i < n1 {
        s1 += f1.resid[i] * f1.resid[i]
        i += 1usize
    }
    let rain = ((s0 - s1) / f64(n - n1)) / (s1 / f64(n1 - p))
    ret (rain, p_f(rain, f64(n - n1), f64(n1 - p)))
}

// lmtest::harvtest: the Harvey-Collier statistic from the recursive residuals and its two-sided p value
fn harv_test(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let m = n - p
    let (w, e0) = mem.alloc[f64](a, m)
    if e0 != ok { ret (nan, nan) }
    var r = p
    while r < n {
        let start = mem.mark(a)
        let (f, e1) = ols(a, x[0usize..r * p], y[0usize..r], r, p)
        if e1 != ok { ret (nan, nan) }
        var pr = 0.0f64
        var q = 0.0f64
        var i = 0usize
        while i < p {
            pr += x[r * p + i] * f.beta[i]
            var j = 0usize
            while j < p {
                q += x[r * p + i] * f.xtx_inv[i * p + j] * x[r * p + j]
                j += 1usize
            }
            i += 1usize
        }
        w[r - p] = (y[r] - pr) / math.sqrt[f64](1.0f64 + q)
        mem.reset(a, start)
        r += 1usize
    }
    var mean = 0.0f64
    var i = 0usize
    while i < m {
        mean += w[i]
        i += 1usize
    }
    mean = mean / f64(m)
    var ss = 0.0f64
    i = 0usize
    while i < m {
        ss += (w[i] - mean) * (w[i] - mean)
        i += 1usize
    }
    let sigma = math.sqrt[f64](ss / f64(n - p - 1usize))
    var sum = 0.0f64
    var ss2 = 0.0f64
    i = 0usize
    while i < m {
        sum += w[i] / sigma
        i += 1usize
    }
    let mu = sum / f64(m)
    i = 0usize
    while i < m {
        let d = w[i] / sigma - mu
        ss2 += d * d
        i += 1usize
    }
    let harv = math.abs[f64](sum / math.sqrt[f64](f64(n - p))) / math.sqrt[f64](ss2 / f64(m - 1usize))
    ret (harv, 2.0f64 * nb.pt(harv, f64(n - p - 1usize), false, false))
}

// car::ncvTest (fitted values): the score statistic RegSS / 2 of the regression of e^2 / (RSS / n) on the fitted values, df 1; returns the statistic and its p value
fn ncv_test(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret (nan, nan) }
    let (xe, e2) = mem.alloc[f64](a, n * 2usize)
    let (u, e3) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok { ret (nan, nan) }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n)
    var mean = 0.0f64
    i = 0usize
    while i < n {
        u[i] = f0.resid[i] * f0.resid[i] / s2
        xe[i * 2usize] = 1.0f64
        xe[i * 2usize + 1usize] = y[i] - f0.resid[i]
        mean += u[i]
        i += 1usize
    }
    mean = mean / f64(n)
    let (f1, e4) = ols(a, xe, u, n, 2usize)
    if e4 != ok { ret (nan, nan) }
    var tss = 0.0f64
    var rss1 = 0.0f64
    i = 0usize
    while i < n {
        tss += (u[i] - mean) * (u[i] - mean)
        rss1 += f1.resid[i] * f1.resid[i]
        i += 1usize
    }
    let chi = (tss - rss1) / 2.0f64
    ret (chi, p_chisq(chi, 1.0f64))
}

// car::leveneTest(y, group, center): the one-way ANOVA F of |y - group centre| (center 0 median, 1 mean) over groups coded 0 .. ng - 1; returns F and its p value
fn levene_test(a: *mem.Arena, y: []const f64, grp: []const f64, ng: usize, center: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let n = y.len
    let (z, e1) = mem.alloc[f64](a, n)
    let (tmp, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (nan, nan) }
    var g = 0usize
    while g < ng {
        var m = 0usize
        var i = 0usize
        while i < n {
            if usize(grp[i]) == g {
                tmp[m] = y[i]
                m += 1usize
            }
            i += 1usize
        }
        var c = 0.0f64
        if center == 1usize {
            i = 0usize
            while i < m {
                c += tmp[i]
                i += 1usize
            }
            c = c / f64(m)
        } else {
            i = 1usize
            while i < m {
                let t = tmp[i]
                var j = i
                while j > 0usize && tmp[j - 1usize] > t {
                    tmp[j] = tmp[j - 1usize]
                    j -= 1usize
                }
                tmp[j] = t
                i += 1usize
            }
            if m % 2usize == 1usize { c = tmp[m / 2usize] } else { c = (tmp[m / 2usize - 1usize] + tmp[m / 2usize]) / 2.0f64 }
        }
        i = 0usize
        while i < n {
            if usize(grp[i]) == g { z[i] = math.abs[f64](y[i] - c) }
            i += 1usize
        }
        g += 1usize
    }
    var grand = 0.0f64
    var i = 0usize
    while i < n {
        grand += z[i]
        i += 1usize
    }
    grand = grand / f64(n)
    var ssb = 0.0f64
    var ssw = 0.0f64
    g = 0usize
    while g < ng {
        var m = 0.0f64
        var s = 0.0f64
        i = 0usize
        while i < n {
            if usize(grp[i]) == g {
                m += 1.0f64
                s += z[i]
            }
            i += 1usize
        }
        let gm = s / m
        ssb += m * (gm - grand) * (gm - grand)
        i = 0usize
        while i < n {
            if usize(grp[i]) == g { ssw += (z[i] - gm) * (z[i] - gm) }
            i += 1usize
        }
        g += 1usize
    }
    let f = (ssb / f64(ng - 1usize)) / (ssw / f64(n - ng))
    ret (f, p_f(f, f64(ng - 1usize), f64(n - ng)))
}

// car::linearHypothesis(model, R, rhs) for an lm: the F statistic (R b - rhs)' [R (X'X)^-1 R']^-1 (R b - rhs) / (q s^2), with q rows of the p-column matrix hm and its p value
fn linear_hypothesis(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, hm: []const f64, rhs: []const f64, q: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret (nan, nan) }
    let (d, e2) = mem.alloc[f64](a, q)
    let (m, e3) = mem.alloc[f64](a, q * q)
    let (mi, e4) = mem.alloc[f64](a, q * q)
    if e2 != ok || e3 != ok || e4 != ok { ret (nan, nan) }
    var i = 0usize
    while i < q {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            s += hm[i * p + j] * f0.beta[j]
            j += 1usize
        }
        d[i] = s - rhs[i]
        var k = 0usize
        while k < q {
            var t = 0.0f64
            j = 0usize
            while j < p {
                var l = 0usize
                while l < p {
                    t += hm[i * p + j] * f0.xtx_inv[j * p + l] * hm[k * p + l]
                    l += 1usize
                }
                j += 1usize
            }
            m[i * q + k] = t
            k += 1usize
        }
        i += 1usize
    }
    if inverse(a, m, q, mi) != ok { ret (nan, nan) }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    var quad = 0.0f64
    i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            quad += d[i] * mi[i * q + j] * d[j]
            j += 1usize
        }
        i += 1usize
    }
    let fs = quad / (f64(q) * s2)
    ret (fs, p_f(fs, f64(q), f64(n - p)))
}

// car::Anova(lm, type) for numeric terms, one column per term (the intercept first): type 1 sequential F, types 2 and 3 the marginal F (the squared t statistic); returns F and p of column j >= 1
fn anova_term(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, ty: usize, j: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret (nan, nan) }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    if ty == 1usize {
        let (xa, e2) = mem.alloc[f64](a, n * (j + 1usize))
        let (xb, e3) = mem.alloc[f64](a, n * j)
        if e2 != ok || e3 != ok { ret (nan, nan) }
        i = 0usize
        while i < n {
            var c = 0usize
            while c <= j {
                xa[i * (j + 1usize) + c] = x[i * p + c]
                if c < j { xb[i * j + c] = x[i * p + c] }
                c += 1usize
            }
            i += 1usize
        }
        let (fa, e4) = ols(a, xa, y, n, j + 1usize)
        let (fb, e5) = ols(a, xb, y, n, j)
        if e4 != ok || e5 != ok { ret (nan, nan) }
        var ra = 0.0f64
        var rb = 0.0f64
        i = 0usize
        while i < n {
            ra += fa.resid[i] * fa.resid[i]
            rb += fb.resid[i] * fb.resid[i]
            i += 1usize
        }
        let fs = (rb - ra) / s2
        ret (fs, p_f(fs, 1.0f64, f64(n - p)))
    }
    let t = f0.beta[j]
    let fs = t * t / (f0.xtx_inv[j * p + j] * s2)
    ret (fs, p_f(fs, 1.0f64, f64(n - p)))
}

// car::boxCox profile log-likelihood at lambda: -n/2 log(RSS) of the Jacobian-adjusted Box-Cox power of y (bcPower, j = TRUE) regressed on X; y must be positive
fn box_cox_ll(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, lambda: f64) -> f64 {
    let (z, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    var lg = 0.0f64
    var i = 0usize
    while i < n {
        lg += math.log[f64](y[i])
        i += 1usize
    }
    let gm = math.exp[f64](lg / f64(n))
    i = 0usize
    while i < n {
        if math.abs[f64](lambda) <= 1.0e-6f64 {
            z[i] = gm * math.log[f64](y[i])
        } else {
            z[i] = (math.pow[f64](y[i], lambda) - 1.0f64) / lambda / math.pow[f64](gm, lambda - 1.0f64)
        }
        i += 1usize
    }
    let (f, e1) = ols(a, x, z, n, p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    ret 0.0f64 - f64(n) / 2.0f64 * math.log[f64](rss)
}

// lmtest::lrtest(restricted, full) and waldtest(restricted, full) for nested lm fits, the restricted model dropping the last q columns of x: (LR statistic, chisq p, Wald F, F p)
fn nested_tests(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, q: usize) -> (f64, f64, f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let pr = p - q
    let (xr, e1) = mem.alloc[f64](a, n * pr)
    if e1 != ok { ret (nan, nan, nan, nan) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < pr {
            xr[i * pr + j] = x[i * p + j]
            j += 1usize
        }
        i += 1usize
    }
    let (f1, e2) = ols(a, xr, y, n, pr)
    let (f2, e3) = ols(a, x, y, n, p)
    if e2 != ok || e3 != ok { ret (nan, nan, nan, nan) }
    var r1 = 0.0f64
    var r2 = 0.0f64
    i = 0usize
    while i < n {
        r1 += f1.resid[i] * f1.resid[i]
        r2 += f2.resid[i] * f2.resid[i]
        i += 1usize
    }
    let nf = f64(n)
    let lr = nf * (math.log[f64](r1 / nf) - math.log[f64](r2 / nf))
    let wf = ((r1 - r2) / f64(q)) / (r2 / f64(n - p))
    ret (lr, p_chisq(lr, f64(q)), wf, p_f(wf, f64(q), f64(n - p)))
}

// lmtest::grangertest(x, y, order): the Wald F of the lags of x in the regression of y on its own lags and the lags of x, with its p value
fn granger_f(a: *mem.Arena, xs: []const f64, ys: []const f64, order: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let rows = ys.len - order
    let w = 1usize + 2usize * order
    let (des, e1) = mem.alloc[f64](a, rows * w)
    let (yv, e2) = mem.alloc[f64](a, rows)
    if e1 != ok || e2 != ok { ret (nan, nan) }
    var r = 0usize
    while r < rows {
        let t = r + order
        yv[r] = ys[t]
        des[r * w] = 1.0f64
        var k = 1usize
        while k <= order {
            des[r * w + k] = ys[t - k]
            des[r * w + order + k] = xs[t - k]
            k += 1usize
        }
        r += 1usize
    }
    let (l1, l2, f1, p1) = nested_tests(a, des, yv, rows, w, order)
    ret (f1, p1)
}

// lmtest::coeftest of an lm: the t value and two-sided p value of coefficient j
fn coef_t(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, j: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret (nan, nan) }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let se = math.sqrt[f64](rss / f64(n - p) * f0.xtx_inv[j * p + j])
    let t = f0.beta[j] / se
    ret (t, 2.0f64 * nb.pt(0.0f64 - math.abs[f64](t), f64(n - p), true, false))
}

// influence measures of an lm: kind 0 cooks.distance, 1 rstandard, 2 rstudent, 3 dffits, 4 hatvalues; out receives the n values
fn influence(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, kind: usize, out: []f64) -> err {
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret e1 }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let dfr = f64(n - p)
    let s2 = rss / dfr
    i = 0usize
    while i < n {
        let h = f0.hat[i]
        let e = f0.resid[i]
        let rs = e / math.sqrt[f64](s2 * (1.0f64 - h))
        let si = math.sqrt[f64]((rss - e * e / (1.0f64 - h)) / (dfr - 1.0f64))
        let rt = e / (si * math.sqrt[f64](1.0f64 - h))
        if kind == 0usize { out[i] = e * e * h / (f64(p) * s2 * (1.0f64 - h) * (1.0f64 - h)) }
        if kind == 1usize { out[i] = rs }
        if kind == 2usize { out[i] = rt }
        if kind == 3usize { out[i] = rt * math.sqrt[f64](h / (1.0f64 - h)) }
        if kind == 4usize { out[i] = h }
        i += 1usize
    }
    ret ok
}

// lmtest::jtest(M1, M2) with M1 on columns 0 and 1 of the design and M2 on column 0 and columns 2 .. p - 1: the t value and p value of the other model's fitted values added to each model, (t1, p1, t2, p2)
fn j_test(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (f64, f64, f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let p1 = 2usize
    let p2 = p - 1usize
    let (x1, e1) = mem.alloc[f64](a, n * (p1 + 1usize))
    let (x2, e2) = mem.alloc[f64](a, n * (p2 + 1usize))
    let (z1, e3) = mem.alloc[f64](a, n * p1)
    let (z2, e4) = mem.alloc[f64](a, n * p2)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (nan, nan, nan, nan) }
    var i = 0usize
    while i < n {
        z1[i * p1] = x[i * p]
        z1[i * p1 + 1usize] = x[i * p + 1usize]
        z2[i * p2] = x[i * p]
        var c = 2usize
        while c < p {
            z2[i * p2 + c - 1usize] = x[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    let (f1, e5) = ols(a, z1, y, n, p1)
    let (f2, e6) = ols(a, z2, y, n, p2)
    if e5 != ok || e6 != ok { ret (nan, nan, nan, nan) }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < p1 {
            x1[i * (p1 + 1usize) + c] = z1[i * p1 + c]
            c += 1usize
        }
        x1[i * (p1 + 1usize) + p1] = y[i] - f2.resid[i]
        c = 0usize
        while c < p2 {
            x2[i * (p2 + 1usize) + c] = z2[i * p2 + c]
            c += 1usize
        }
        x2[i * (p2 + 1usize) + p2] = y[i] - f1.resid[i]
        i += 1usize
    }
    let (t1, q1) = coef_t(a, x1, y, n, p1 + 1usize, p1)
    let (t2, q2) = coef_t(a, x2, y, n, p2 + 1usize, p2)
    ret (t1, q1, t2, q2)
}

// car::powerTransform(lm)$lambda for a positive response: the maximiser of the Box-Cox profile log-likelihood over [-3, 3] by golden-section search to 1e-12; R reaches it through optimize and L-BFGS-B, so it agrees to the optimiser's tolerance (about 1e-4)
fn power_transform_lambda(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> f64 {
    let gr = (math.sqrt[f64](5.0f64) - 1.0f64) / 2.0f64
    var lo = 0.0f64 - 3.0f64
    var hi = 3.0f64
    var c = hi - gr * (hi - lo)
    var d = lo + gr * (hi - lo)
    var fc = box_cox_ll(a, x, y, n, p, c)
    var fd = box_cox_ll(a, x, y, n, p, d)
    var it = 0usize
    while it < 120usize && hi - lo > 1.0e-12f64 {
        if fc > fd {
            hi = d
            d = c
            fd = fc
            c = hi - gr * (hi - lo)
            fc = box_cox_ll(a, x, y, n, p, c)
        } else {
            lo = c
            c = d
            fc = fd
            d = lo + gr * (hi - lo)
            fd = box_cox_ll(a, x, y, n, p, d)
        }
        it += 1usize
    }
    ret (lo + hi) / 2.0f64
}

// car::Anova / anova for a term spanning columns start .. start + q - 1 of the design: type 1 the sequential F (the term added to the columns before it), types 2 and 3 the marginal F (the term dropped from the full model, no interactions); returns F and p on (q, n - p)
fn anova_block(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, start: usize, q: usize, ty: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e0) = ols(a, x, y, n, p)
    if e0 != ok { ret (nan, nan) }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    // the smaller model: type 1 keeps the columns before start, the others every column outside the term
    var pr = p - q
    if ty == 1usize { pr = start }
    let (xr, e1) = mem.alloc[f64](a, n * pr)
    if e1 != ok { ret (nan, nan) }
    i = 0usize
    while i < n {
        var m = 0usize
        var c = 0usize
        while c < p {
            let inside = c >= start && c < start + q
            var keep = !inside
            if ty == 1usize { keep = c < start }
            if keep {
                xr[i * pr + m] = x[i * p + c]
                m += 1usize
            }
            c += 1usize
        }
        i += 1usize
    }
    // type 1 compares with the model through the term, not the full one
    var rss_big = rss
    if ty == 1usize {
        let pb = start + q
        let (xb, e2) = mem.alloc[f64](a, n * pb)
        if e2 != ok { ret (nan, nan) }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < pb {
                xb[i * pb + c] = x[i * p + c]
                c += 1usize
            }
            i += 1usize
        }
        let (fb, e3) = ols(a, xb, y, n, pb)
        if e3 != ok { ret (nan, nan) }
        rss_big = 0.0f64
        i = 0usize
        while i < n {
            rss_big += fb.resid[i] * fb.resid[i]
            i += 1usize
        }
    }
    let (fr, e4) = ols(a, xr, y, n, pr)
    if e4 != ok { ret (nan, nan) }
    var rss_r = 0.0f64
    i = 0usize
    while i < n {
        rss_r += fr.resid[i] * fr.resid[i]
        i += 1usize
    }
    let fs = ((rss_r - rss_big) / f64(q)) / s2
    ret (fs, p_f(fs, f64(q), f64(n - p)))
}

// sandwich::vcovBS(lm, R, type = "xy") with each observation its own cluster: the covariance of the coefficients of R pairs-bootstrap refits (rows drawn by sample.int(n, n, TRUE) per replicate), written row-major into out (p by p)
fn vcov_bs(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, p: usize, nrep: usize, out: []f64) -> err {
    let (cf, e1) = mem.alloc[f64](a, nrep * p)
    let (xb, e2) = mem.alloc[f64](a, n * p)
    let (yb, e3) = mem.alloc[f64](a, n)
    let (mu, e4) = mem.alloc[f64](a, p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var r = 0usize
    while r < nrep {
        let start = mem.mark(a)
        let (draw, de) = rng.sample_int(a, g, i64(n), i64(n), true)
        if de != ok { ret de }
        var i = 0usize
        while i < n {
            let k = usize(draw[i]) - 1usize
            var c = 0usize
            while c < p {
                xb[i * p + c] = x[k * p + c]
                c += 1usize
            }
            yb[i] = y[k]
            i += 1usize
        }
        let (fit, fe) = ols(a, xb, yb, n, p)
        if fe != ok { ret fe }
        var c = 0usize
        while c < p {
            cf[r * p + c] = fit.beta[c]
            c += 1usize
        }
        mem.reset(a, start)
        r += 1usize
    }
    var c = 0usize
    while c < p {
        var s = 0.0f64
        r = 0usize
        while r < nrep {
            s += cf[r * p + c]
            r += 1usize
        }
        mu[c] = s / f64(nrep)
        c += 1usize
    }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            r = 0usize
            while r < nrep {
                s += (cf[r * p + i] - mu[i]) * (cf[r * p + j] - mu[j])
                r += 1usize
            }
            out[i * p + j] = s / f64(nrep - 1usize)
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// sandwich::vcovPL(lm, cluster, order.by, lag, aggregate = TRUE, adjust = TRUE) with the Bartlett kernel: the scores summed over the observations of each distinct time (lag < 0 means "NW1987", floor(nt^(1/4))), the Newey-West meat of the aggregated series, n / (n - k) times (X'X)^-1 S (X'X)^-1; the diagonal goes to out
fn vcov_pl_diag(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, time: []const f64, lag0: i64, out: []f64) -> err {
    let (f0, e1) = ols(a, x, y, n, p)
    if e1 != ok { ret e1 }
    let (ut, e2) = mem.alloc[f64](a, n)
    let (ag, e3) = mem.alloc[f64](a, n * p)
    let (s, e4) = mem.alloc[f64](a, p * p)
    let (t1, e5) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var nt = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < nt {
            if ut[j] == time[i] { seen = true }
            j += 1usize
        }
        if !seen {
            ut[nt] = time[i]
            nt += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < nt {
        let v = ut[i]
        var j = i
        while j > 0usize && ut[j - 1usize] > v {
            ut[j] = ut[j - 1usize]
            j -= 1usize
        }
        ut[j] = v
        i += 1usize
    }
    i = 0usize
    while i < nt * p {
        ag[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var g = 0usize
        while ut[g] != time[i] { g += 1usize }
        var c = 0usize
        while c < p {
            ag[g * p + c] += f0.resid[i] * x[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    var lag = 0usize
    if lag0 >= 0i64 { lag = usize(lag0) }
    if lag0 < 0i64 { lag = usize(math.floor[f64](math.pow[f64](f64(nt), 0.25f64))) }
    i = 0usize
    while i < p * p {
        s[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j <= lag && j < nt {
        let w = 1.0f64 - f64(j) / f64(lag + 1usize)
        var r = j
        while r < nt {
            var c1 = 0usize
            while c1 < p {
                var c2 = 0usize
                while c2 < p {
                    let v = ag[r * p + c1] * ag[(r - j) * p + c2]
                    if j == 0usize {
                        s[c1 * p + c2] += v
                    } else {
                        s[c1 * p + c2] += w * v
                        s[c2 * p + c1] += w * v
                    }
                    c2 += 1usize
                }
                c1 += 1usize
            }
            r += 1usize
        }
        j += 1usize
    }
    // V = n / (n - k) (X'X)^-1 S (X'X)^-1
    var c1 = 0usize
    while c1 < p {
        var c2 = 0usize
        while c2 < p {
            var v = 0.0f64
            var q = 0usize
            while q < p {
                v += s[c1 * p + q] * f0.xtx_inv[q * p + c2]
                q += 1usize
            }
            t1[c1 * p + c2] = v
            c2 += 1usize
        }
        c1 += 1usize
    }
    c1 = 0usize
    while c1 < p {
        var v = 0.0f64
        var q = 0usize
        while q < p {
            v += f0.xtx_inv[c1 * p + q] * t1[q * p + c1]
            q += 1usize
        }
        out[c1] = v * f64(n) / f64(n - p)
        c1 += 1usize
    }
    ret ok
}

// the F test of Anova's term rows when terms interact: the residual sum of squares of the model on the columns with big[c] > 0.5 against that on small[c] > 0.5 (q columns fewer), over the residual mean square of the full design; (F, p) on (q, n - p)
fn anova_masked(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, big: []const f64, small: []const f64, q: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let (f0, e0) = ols(a, x, y, n, p)
    if e0 != ok { ret (nan, nan) }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f0.resid[i] * f0.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    var sums = 0.0f64
    var sumb = 0.0f64
    var pass = 0usize
    while pass < 2usize {
        var m = 0usize
        var c = 0usize
        while c < p {
            var keep = big[c] > 0.5f64
            if pass == 1usize { keep = small[c] > 0.5f64 }
            if keep { m += 1usize }
            c += 1usize
        }
        let (xm, e1) = mem.alloc[f64](a, n * m)
        if e1 != ok { ret (nan, nan) }
        i = 0usize
        while i < n {
            var k = 0usize
            c = 0usize
            while c < p {
                var keep = big[c] > 0.5f64
                if pass == 1usize { keep = small[c] > 0.5f64 }
                if keep {
                    xm[i * m + k] = x[i * p + c]
                    k += 1usize
                }
                c += 1usize
            }
            i += 1usize
        }
        let (fm, e2) = ols(a, xm, y, n, m)
        if e2 != ok { ret (nan, nan) }
        var r = 0.0f64
        i = 0usize
        while i < n {
            r += fm.resid[i] * fm.resid[i]
            i += 1usize
        }
        if pass == 0usize { sumb = r } else { sums = r }
        pass += 1usize
    }
    let fs = ((sums - sumb) / f64(q)) / s2
    ret (fs, p_f(fs, f64(q), f64(n - p)))
}

// the determinant of the m by m row-major matrix a (partial-pivot elimination on a copy)
fn det_of(a: *mem.Arena, mt: []const f64, m: usize) -> f64 {
    if m == 0usize { ret 1.0f64 }
    let (w, e) = mem.alloc[f64](a, m * m)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < m * m {
        w[i] = mt[i]
        i += 1usize
    }
    var det = 1.0f64
    var col = 0usize
    while col < m {
        var piv = col
        var r = col + 1usize
        while r < m {
            if math.abs[f64](w[r * m + col]) > math.abs[f64](w[piv * m + col]) { piv = r }
            r += 1usize
        }
        if w[piv * m + col] == 0.0f64 { ret 0.0f64 }
        if piv != col {
            var c = 0usize
            while c < m {
                let t = w[col * m + c]
                w[col * m + c] = w[piv * m + c]
                w[piv * m + c] = t
                c += 1usize
            }
            det = 0.0f64 - det
        }
        det = det * w[col * m + col]
        r = col + 1usize
        while r < m {
            let f = w[r * m + col] / w[col * m + col]
            var c = col
            while c < m {
                w[r * m + c] -= f * w[col * m + c]
                c += 1usize
            }
            r += 1usize
        }
        col += 1usize
    }
    ret det
}

// car::vif for a term spanning columns start .. start + q - 1 of the design (column 0 the intercept): the generalised VIF det(R_term) det(R_rest) / det(R) of the correlation matrix R of the other coefficients' covariance; its (1 / (2 q)) power as the second value
fn gvif(a: *mem.Arena, x: []const f64, n: usize, p: usize, start: usize, q: usize) -> (f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let m = p - 1usize
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    let (inv, e2) = mem.alloc[f64](a, p * p)
    let (rm, e3) = mem.alloc[f64](a, m * m)
    let (rt, e4) = mem.alloc[f64](a, q * q)
    let (rr, e5) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (nan, nan) }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += x[r * p + i] * x[r * p + j]
                r += 1usize
            }
            xtx[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if inverse(a, xtx, p, inv) != ok { ret (nan, nan) }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            rm[i * m + j] = inv[(i + 1usize) * p + j + 1usize] / math.sqrt[f64](inv[(i + 1usize) * p + i + 1usize] * inv[(j + 1usize) * p + j + 1usize])
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            rt[i * q + j] = rm[(start - 1usize + i) * m + start - 1usize + j]
            j += 1usize
        }
        i += 1usize
    }
    let mr = m - q
    var ri = 0usize
    i = 0usize
    while i < m {
        if i < start - 1usize || i >= start - 1usize + q {
            var rj = 0usize
            var j = 0usize
            while j < m {
                if j < start - 1usize || j >= start - 1usize + q {
                    rr[ri * mr + rj] = rm[i * m + j]
                    rj += 1usize
                }
                j += 1usize
            }
            ri += 1usize
        }
        i += 1usize
    }
    let g = det_of(a, rt, q) * det_of(a, rr[0usize..mr * mr], mr) / det_of(a, rm, m)
    ret (g, math.pow[f64](g, 1.0f64 / (2.0f64 * f64(q))))
}
