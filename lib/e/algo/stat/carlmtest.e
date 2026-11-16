// R car, lmtest and sandwich for a linear model y = X b (X with the intercept column): the OLS fit with its hat values, the heteroskedasticity-consistent
// covariances vcovHC of types HC0 to HC4, the Durbin-Watson statistic, the studentized Breusch-Pagan statistic, and the variance inflation factors.
//
// Not here: the other covariance families (HAC, clustered, bootstrap), the other lmtest tests (RESET, Harvey-Collier, Goldfeld-Quandt, the non-studentized
// Breusch-Pagan), p values, Anova and the rest of car.

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
