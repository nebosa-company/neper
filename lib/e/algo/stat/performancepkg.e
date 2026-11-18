// R performance on a linear model fitted by least squares: r2, r2_adjusted, rmse, mae, mse, sigma, loglik, aic, aicc and bic.
//
// Not here: generalized, mixed and Bayesian models, the other indices and the model checks.

use e.algo.stat.carlmtest as ols
use e.math
use e.math.nmath as nm
use e.algo.stat.test as tst
use e.algo.stat.flexmixpkg as fx
use e.mem

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
