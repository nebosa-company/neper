// R performance on a linear model fitted by least squares: r2, r2_adjusted, rmse, mae, mse, sigma, loglik, aic, aicc and bic.
//
// Not here: generalized, mixed and Bayesian models, the other indices and the model checks.

use e.algo.stat.carlmtest as ols
use e.math
use e.math.nmath as nm
use e.algo.stat.desctools as dt
use e.algo.stat.test as tst
use e.algo.stat.flexmixpkg as fx
use e.mem
use e.algo.stat.olsfit as of
use e.math.nmath_beta as nbq

// the index `which` of the lm of y on x (n by p, intercept column included): 0 r2, 1 r2_adjusted, 2 rmse, 3 mae, 4 mse, 5 sigma, 6 loglik, 7 aic, 8 aicc, 9 bic
fn lm_index(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, which: usize) -> f64 {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(n)
    var rss = 0.0f64
    var sae = 0.0f64
    var my = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        sae += math.abs[f64](f.resid[i])
        my += y[i]
        i += 1usize
    }
    my = my / nf
    var tss = 0.0f64
    i = 0usize
    while i < n {
        tss += (y[i] - my) * (y[i] - my)
        i += 1usize
    }
    let r2 = 1.0f64 - rss / tss
    let kf = f64(p) + 1.0f64
    let ll = 0.0f64 - nf / 2.0f64 * (math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) + 1.0f64 - math.log[f64](nf) + math.log[f64](rss))
    let aic = 0.0f64 - 2.0f64 * ll + 2.0f64 * kf
    if which == 0usize { ret r2 }
    if which == 1usize { ret 1.0f64 - (1.0f64 - r2) * (nf - 1.0f64) / (nf - f64(p)) }
    if which == 2usize { ret math.sqrt[f64](rss / nf) }
    if which == 3usize { ret sae / nf }
    if which == 4usize { ret rss / nf }
    if which == 5usize { ret math.sqrt[f64](rss / (nf - f64(p))) }
    if which == 6usize { ret ll }
    if which == 7usize { ret aic }
    if which == 8usize { ret aic + 2.0f64 * kf * (kf + 1.0f64) / (nf - kf - 1.0f64) }
    ret 0.0f64 - 2.0f64 * ll + math.log[f64](nf) * kf
}

// check_heteroscedasticity (Breusch-Pagan on an lm): the p value, the chi-square being the regression sum of squares of r^2 / (RSS / n) on the fitted values, over 2, on one degree of freedom
fn heteroscedasticity_p(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> f64 {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(n)
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    let s2 = rss / nf
    var mf = 0.0f64
    var mu = 0.0f64
    i = 0usize
    while i < n {
        mf += y[i] - f.resid[i]
        mu += f.resid[i] * f.resid[i] / s2
        i += 1usize
    }
    mf = mf / nf
    mu = mu / nf
    var sxy = 0.0f64
    var sxx = 0.0f64
    i = 0usize
    while i < n {
        let d = (y[i] - f.resid[i]) - mf
        sxy += d * (f.resid[i] * f.resid[i] / s2 - mu)
        sxx += d * d
        i += 1usize
    }
    ret nm.pchisq(sxy * sxy / sxx / 2.0f64, 1.0f64, false, false)
}

// check_collinearity: the variance inflation factor of predictor j (x is n by q row-major, no intercept), 1 / (1 - R^2) of x_j on the other predictors and an intercept
fn vif(a: *mem.Arena, x: []const f64, n: usize, q: usize, j: usize) -> f64 {
    let (d, e1) = mem.alloc[f64](a, n * q)
    let (yj, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i * q] = 1.0f64
        var c = 0usize
        var w = 1usize
        while c < q {
            if c != j {
                d[i * q + w] = x[i * q + c]
                w += 1usize
            }
            c += 1usize
        }
        yj[i] = x[i * q + j]
        i += 1usize
    }
    let (f, e) = ols.ols(a, d, yj, n, q)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var rss = 0.0f64
    var m = 0.0f64
    i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        m += yj[i]
        i += 1usize
    }
    m = m / f64(n)
    var tss = 0.0f64
    i = 0usize
    while i < n {
        tss += (yj[i] - m) * (yj[i] - m)
        i += 1usize
    }
    ret tss / rss
}

// the pseudo R^2 of a logistic regression of binary y on x (n by p row-major, intercept included): which 0 Tjur, 1 Cox-Snell, 2 Nagelkerke, 3 McFadden, 4 McFadden adjusted
fn logit_r2(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, which: usize) -> f64 {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (w, e2) = mem.alloc[f64](a, n)
    let (sz, e3) = mem.alloc[f64](a, n)
    let (b, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        w[i] = 1.0f64
        sz[i] = 1.0f64
        i += 1usize
    }
    if fx.binom_glm(a, xc, n, p, y, sz, w, b, false) != ok { ret 0.0f64 / 0.0f64 }
    var s1 = 0.0f64
    var s0 = 0.0f64
    var n1 = 0.0f64
    var n0 = 0.0f64
    var ll = 0.0f64
    var ybar = 0.0f64
    i = 0usize
    while i < n {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += xc[c * n + i] * b[c]
            c += 1usize
        }
        let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
        if y[i] == 1.0f64 {
            s1 += pr
            n1 += 1.0f64
            ll += math.log[f64](pr)
        } else {
            s0 += pr
            n0 += 1.0f64
            ll += math.log[f64](1.0f64 - pr)
        }
        ybar += y[i]
        i += 1usize
    }
    let nf = f64(n)
    ybar = ybar / nf
    let ll0 = nf * (ybar * math.log[f64](ybar) + (1.0f64 - ybar) * math.log[f64](1.0f64 - ybar))
    let dev = 0.0f64 - 2.0f64 * ll
    let nulldev = 0.0f64 - 2.0f64 * ll0
    if which == 0usize { ret s1 / n1 - s0 / n0 }
    let cs = 1.0f64 - math.exp[f64]((dev - nulldev) / nf)
    if which == 1usize { ret cs }
    if which == 2usize { ret cs / (1.0f64 - math.exp[f64](0.0f64 - nulldev / nf)) }
    if which == 3usize { ret 1.0f64 - ll / ll0 }
    ret 1.0f64 - (ll - f64(p)) / ll0
}

// check_normality of an lm: the Shapiro-Wilk p value of rstandard(m) (below 5000 observations; the package switches to a Kolmogorov-Smirnov test from 5000)
fn normality_p(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> f64 {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    let sg = math.sqrt[f64](rss / f64(n - p))
    let (z, e1) = mem.alloc[f64](a, n)
    let (sc, e2) = mem.alloc[f64](a, n / 2usize + 1usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        z[i] = f.resid[i] / (sg * math.sqrt[f64](1.0f64 - f.hat[i]))
        i += 1usize
    }
    let (r, se) = tst.shapiro_wilk(z, sc)
    if se != ok { ret 0.0f64 / 0.0f64 }
    ret r.p_value
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (t, e) = dt.sorted_copy(a, v)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = t.len
    if n % 2usize == 1usize { ret t[n / 2usize] }
    ret (t[n / 2usize - 1usize] + t[n / 2usize]) / 2.0f64
}

// check_outliers method "zscore": the distance of row i is the largest over the q columns (x is n by q row-major) of |x - centre| / scale, with the median and the scaled MAD
// (1.4826) when robust and the mean and standard deviation otherwise
fn zscore_distance(a: *mem.Arena, x: []const f64, n: usize, q: usize, robust: bool, row: usize) -> f64 {
    var best = 0.0f64
    var c = 0usize
    while c < q {
        let (col, e1) = mem.alloc[f64](a, n)
        let (dev, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
        var i = 0usize
        while i < n {
            col[i] = x[i * q + c]
            i += 1usize
        }
        var centre = 0.0f64
        var scale = 0.0f64
        if robust {
            centre = median_of(a, col)
            i = 0usize
            while i < n {
                dev[i] = math.abs[f64](col[i] - centre)
                i += 1usize
            }
            scale = 1.4826f64 * median_of(a, dev)
        } else {
            var sm = 0.0f64
            i = 0usize
            while i < n {
                sm += col[i]
                i += 1usize
            }
            centre = sm / f64(n)
            var ss = 0.0f64
            i = 0usize
            while i < n {
                ss += (col[i] - centre) * (col[i] - centre)
                i += 1usize
            }
            scale = math.sqrt[f64](ss / f64(n - 1usize))
        }
        let d = math.abs[f64](col[row] - centre) / scale
        if d > best { best = d }
        c += 1usize
    }
    ret best
}

// stats::mahalanobis(x, colMeans(x), cov(x)) of row `row` (Gauss-Jordan inverse of the q by q covariance matrix)
fn mahalanobis_distance(a: *mem.Arena, x: []const f64, n: usize, q: usize, row: usize) -> f64 {
    let (mu, e1) = mem.alloc[f64](a, q)
    let (m, e2) = mem.alloc[f64](a, q * 2usize * q)
    let (dv, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var c = 0usize
    while c < q {
        var sm = 0.0f64
        var i = 0usize
        while i < n {
            sm += x[i * q + c]
            i += 1usize
        }
        mu[c] = sm / f64(n)
        c += 1usize
    }
    c = 0usize
    while c < q {
        var c2 = 0usize
        while c2 < q {
            var sm = 0.0f64
            var i = 0usize
            while i < n {
                sm += (x[i * q + c] - mu[c]) * (x[i * q + c2] - mu[c2])
                i += 1usize
            }
            m[c * 2usize * q + c2] = sm / f64(n - 1usize)
            m[c * 2usize * q + q + c2] = 0.0f64
            c2 += 1usize
        }
        m[c * 2usize * q + q + c] = 1.0f64
        c += 1usize
    }
    var col = 0usize
    while col < q {
        var piv = col
        var r = col + 1usize
        while r < q {
            if math.abs[f64](m[r * 2usize * q + col]) > math.abs[f64](m[piv * 2usize * q + col]) { piv = r }
            r += 1usize
        }
        var k = 0usize
        while k < 2usize * q {
            let t = m[col * 2usize * q + k]
            m[col * 2usize * q + k] = m[piv * 2usize * q + k]
            m[piv * 2usize * q + k] = t
            k += 1usize
        }
        let d = m[col * 2usize * q + col]
        k = 0usize
        while k < 2usize * q {
            m[col * 2usize * q + k] = m[col * 2usize * q + k] / d
            k += 1usize
        }
        r = 0usize
        while r < q {
            if r != col {
                let f = m[r * 2usize * q + col]
                k = 0usize
                while k < 2usize * q {
                    m[r * 2usize * q + k] = m[r * 2usize * q + k] - f * m[col * 2usize * q + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    c = 0usize
    while c < q {
        dv[c] = x[row * q + c] - mu[c]
        c += 1usize
    }
    var tot = 0.0f64
    c = 0usize
    while c < q {
        var c2 = 0usize
        while c2 < q {
            tot += dv[c] * m[c * 2usize * q + q + c2] * dv[c2]
            c2 += 1usize
        }
        c += 1usize
    }
    ret tot
}

// stats::cooks.distance of observation `row` of the lm of y on x (n by p row-major, intercept included): (e / (1 - h))^2 h / (s^2 p)
fn cook_distance(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, row: usize) -> f64 {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    let r = f.resid[row] / (1.0f64 - f.hat[row])
    ret r * r * f.hat[row] / (s2 * f64(p))
}

// the fitted probabilities of the logistic regression of binary y on x (n by p row-major), into pr
fn logit_fitted(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, pr: []f64) -> err {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (w, e2) = mem.alloc[f64](a, n)
    let (sz, e3) = mem.alloc[f64](a, n)
    let (b, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret fx.Malformed }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        w[i] = 1.0f64
        sz[i] = 1.0f64
        i += 1usize
    }
    let e = fx.binom_glm(a, xc, n, p, y, sz, w, b, false)
    if e != ok { ret e }
    i = 0usize
    while i < n {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += xc[c * n + i] * b[c]
            c += 1usize
        }
        pr[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
        i += 1usize
    }
    ret ok
}

// stats::quantile type 7 of the sorted sample at probability pp
fn quant7_sorted(s: []const f64, pp: f64) -> f64 {
    let h = (f64(s.len) - 1.0f64) * pp
    let lo = math.floor[f64](h)
    let k = usize(lo)
    if k + 1usize >= s.len { ret s[s.len - 1usize] }
    ret s[k] + (h - lo) * (s[k + 1usize] - s[k])
}

// performance_hosmer(m, n_bins) of a logistic regression: out receives (chi-square, p value); the fitted values are cut at their n_bins quantiles into (lo, hi] groups (the lowest closed)
fn hosmer(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, bins: usize, out: []f64) -> err {
    let (pr, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret fx.Malformed }
    let e = logit_fitted(a, x, y, n, p, pr)
    if e != ok { ret e }
    let (sorted, e2) = dt.sorted_copy(a, pr)
    if e2 != ok { ret e2 }
    let (br, e3) = mem.alloc[f64](a, bins + 1usize)
    if e3 != ok { ret fx.Malformed }
    var k = 0usize
    while k <= bins {
        br[k] = quant7_sorted(sorted, f64(k) / f64(bins))
        k += 1usize
    }
    var chisq = 0.0f64
    k = 0usize
    while k < bins {
        var o1 = 0.0f64
        var o0 = 0.0f64
        var e1s = 0.0f64
        var e0s = 0.0f64
        var i = 0usize
        while i < n {
            var inb = pr[i] > br[k] && pr[i] <= br[k + 1usize]
            if k == 0usize && pr[i] == br[0usize] { inb = true }
            if inb {
                o1 += y[i]
                o0 += 1.0f64 - y[i]
                e1s += pr[i]
                e0s += 1.0f64 - pr[i]
            }
            i += 1usize
        }
        if e1s > 0.0f64 { chisq += (o1 - e1s) * (o1 - e1s) / e1s }
        if e0s > 0.0f64 { chisq += (o0 - e0s) * (o0 - e0s) / e0s }
        k += 1usize
    }
    out[0usize] = chisq
    out[1usize] = 1.0f64 - nm.pchisq(chisq, f64(bins) - 2.0f64, true, false)
    ret ok
}

// r2_efron (1 - sum (y - p)^2 / sum (y - ybar)^2) and the mean log loss of a logistic regression: which 0 Efron, 1 log loss
fn logit_fit_measure(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, which: usize) -> f64 {
    let (pr, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if logit_fitted(a, x, y, n, p, pr) != ok { ret 0.0f64 / 0.0f64 }
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / f64(n)
    var num = 0.0f64
    var den = 0.0f64
    var ll = 0.0f64
    i = 0usize
    while i < n {
        num += (y[i] - pr[i]) * (y[i] - pr[i])
        den += (y[i] - ybar) * (y[i] - ybar)
        if y[i] == 1.0f64 { ll += math.log[f64](pr[i]) } else { ll += math.log[f64](1.0f64 - pr[i]) }
        i += 1usize
    }
    if which == 0usize { ret 1.0f64 - num / den }
    ret 0.0f64 - ll / f64(n)
}

// check_overdispersion and check_zeroinflation of a Poisson regression of counts y on x (n by p row-major, intercept included): which 0 dispersion ratio, 1 Pearson chi-square, 2 its p value (upper tail
// on n - p degrees of freedom), 3 observed zeros, 4 predicted zeros (the rounded sum of exp(-mu)), 5 predicted over observed
fn poisson_checks(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, which: usize) -> f64 {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (w, e2) = mem.alloc[f64](a, n)
    let (b, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        w[i] = 1.0f64
        i += 1usize
    }
    if fx.pois_glm(a, xc, n, p, y, w, b, false) != ok { ret 0.0f64 / 0.0f64 }
    var chisq = 0.0f64
    var obs0 = 0.0f64
    var pred0 = 0.0f64
    i = 0usize
    while i < n {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += xc[c * n + i] * b[c]
            c += 1usize
        }
        let mu = math.exp[f64](t)
        chisq += (y[i] - mu) * (y[i] - mu) / mu
        if y[i] == 0.0f64 { obs0 += 1.0f64 }
        pred0 += math.exp[f64](0.0f64 - mu)
        i += 1usize
    }
    let dfr = f64(n - p)
    if which == 0usize { ret chisq / dfr }
    if which == 1usize { ret chisq }
    if which == 2usize { ret nm.pchisq(chisq, dfr, false, false) }
    if which == 3usize { ret obs0 }
    // the package rounds the predicted count of zeros and reports predicted over observed
    let pr0 = math.round[f64](pred0)
    if which == 4usize { ret pr0 }
    ret pr0 / obs0
}

// parameters::standardize_parameters of an lm with numeric predictors (every method gives the same slopes): the slopes of the least-squares fit of the z-scored response on the z-scored predictors, with their
// t intervals at `level`. x is n by p row-major without the intercept. out[0 .. p] slopes, then p lower limits, then p upper limits
fn std_params_lm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, level: f64, out: []f64) -> err {
    let (des, e1) = mem.alloc[f64](a, n * (p + 1usize))
    let (zy, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let nn = f64(n)
    var i = 0usize
    while i < n {
        des[i] = 1.0f64
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += x[i * p + j]
            i += 1usize
        }
        m = m / nn
        var ss = 0.0f64
        i = 0usize
        while i < n {
            ss += (x[i * p + j] - m) * (x[i * p + j] - m)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / (nn - 1.0f64))
        i = 0usize
        while i < n {
            des[(j + 1usize) * n + i] = (x[i * p + j] - m) / sd
            i += 1usize
        }
        j += 1usize
    }
    var my = 0.0f64
    i = 0usize
    while i < n {
        my += y[i]
        i += 1usize
    }
    my = my / nn
    var sy = 0.0f64
    i = 0usize
    while i < n {
        sy += (y[i] - my) * (y[i] - my)
        i += 1usize
    }
    let sdy = math.sqrt[f64](sy / (nn - 1.0f64))
    i = 0usize
    while i < n {
        zy[i] = (y[i] - my) / sdy
        i += 1usize
    }
    let (o, e3) = of.fit(a, des, n, p + 1usize, zy)
    if e3 != ok { ret e3 }
    let tq = nbq.qt(1.0f64 - (1.0f64 - level) / 2.0f64, nn - f64(p) - 1.0f64, true, false)
    j = 0usize
    while j < p {
        out[j] = o.coef[j + 1usize]
        out[p + j] = o.coef[j + 1usize] - tq * o.se[j + 1usize]
        out[2usize * p + j] = o.coef[j + 1usize] + tq * o.se[j + 1usize]
        j += 1usize
    }
    ret ok
}

// performance_pcp (Herron) and r2_mckelvey of a logistic regression: which 0 the model's percentage correctly predicted (mean of p for y = 1 and 1 - p for y = 0), 1 the null model's (ybar^2 + (1 - ybar)^2),
// 2 and 3 the 95% Wald limits of the first, 4 and 5 of the second (est +- 1.96 sqrt(est (1 - est) / n)), 6 the likelihood-ratio chi-square 2 (ll - ll0) of the test against the null, 7 its p value on 1 degree
// of freedom less than the parameters (p - 1), 8 McKelvey-Zavoina R2: var(eta) / (var(eta) + pi^2 / 3)
fn logit_pcp(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, which: usize) -> f64 {
    let (pr, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if logit_fitted(a, x, y, n, p, pr) != ok { ret 0.0f64 / 0.0f64 }
    let nn = f64(n)
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / nn
    var full = 0.0f64
    var ll = 0.0f64
    var ll0 = 0.0f64
    var me = 0.0f64
    i = 0usize
    while i < n {
        if y[i] == 1.0f64 {
            full += pr[i]
            ll += math.log[f64](pr[i])
            ll0 += math.log[f64](ybar)
        } else {
            full += 1.0f64 - pr[i]
            ll += math.log[f64](1.0f64 - pr[i])
            ll0 += math.log[f64](1.0f64 - ybar)
        }
        me += math.log[f64](pr[i] / (1.0f64 - pr[i]))
        i += 1usize
    }
    full = full / nn
    let nul = ybar * ybar + (1.0f64 - ybar) * (1.0f64 - ybar)
    let z = 1.959963984540054f64
    if which == 0usize { ret full }
    if which == 1usize { ret nul }
    if which == 2usize { ret full - z * math.sqrt[f64](full * (1.0f64 - full) / nn) }
    if which == 3usize { ret full + z * math.sqrt[f64](full * (1.0f64 - full) / nn) }
    if which == 4usize { ret nul - z * math.sqrt[f64](nul * (1.0f64 - nul) / nn) }
    if which == 5usize { ret nul + z * math.sqrt[f64](nul * (1.0f64 - nul) / nn) }
    let chisq = 2.0f64 * (ll - ll0)
    if which == 6usize { ret chisq }
    if which == 7usize { ret nm.pchisq(chisq, f64(p) - 1.0f64, false, false) }
    me = me / nn
    var sv = 0.0f64
    i = 0usize
    while i < n {
        let eta = math.log[f64](pr[i] / (1.0f64 - pr[i]))
        sv += (eta - me) * (eta - me)
        i += 1usize
    }
    sv = sv / nn
    ret sv / (sv + 3.141592653589793f64 * 3.141592653589793f64 / 3.0f64)
}
