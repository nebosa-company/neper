// R performance on a linear model fitted by least squares: r2, r2_adjusted, rmse, mae, mse, sigma, loglik, aic, aicc and bic.
//
// Not here: generalized, mixed and Bayesian models, the other indices and the model checks.

use e.algo.stat.carlmtest as ols
use e.math
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
