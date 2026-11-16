// Ordinary least squares with the coefficient table of R's summary(lm): coefficients, standard errors and t values for the
// columns that are not aliased, the residual variance and the log likelihood that BIC uses. Columns are column-major, n rows;
// the intercept is a column of ones the caller supplies. An aliased column (the QR with R's tolerance 1e-7 drops it) has NaN
// for its coefficient, standard error and t value.

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

type Ols = struct { coef: []f64, se: []f64, tval: []f64, sigma2: f64, rss: f64, rank: usize, n: usize, resid: []f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn fit(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64) -> (Ols, err) {
    var none: Ols = zero
    let (lf, le) = decomp.lm_fit(a, x, n, p, y, 1.0e-7f64)
    if le != ok { ret (none, le) }
    let (f, qe) = decomp.qr(a, x, n, p, 1.0e-7f64)
    if qe != ok { ret (none, qe) }
    let k = f.rank
    let (rinv, re) = mem.alloc[f64](a, k * k + 1usize)
    let (cov, ce) = mem.alloc[f64](a, k * k + 1usize)
    let (se, se2) = mem.alloc[f64](a, p + 1usize)
    let (tv, te) = mem.alloc[f64](a, p + 1usize)
    if re != ok { ret (none, re) }
    if ce != ok { ret (none, ce) }
    if se2 != ok { ret (none, se2) }
    if te != ok { ret (none, te) }
    // R^-1 by back substitution, R the leading k x k upper triangle of the packed factor
    var j = 0usize
    while j < k {
        var i = k
        while i > 0usize {
            i -= 1usize
            var s = 0.0f64
            if i == j { s = 1.0f64 }
            var c = i + 1usize
            while c <= j {
                s = s - f.qr[c * n + i] * rinv[j * k + c]
                c += 1usize
            }
            rinv[j * k + i] = s / f.qr[i * n + i]
        }
        j += 1usize
    }
    // (R'R)^-1 = Rinv Rinv'
    var i = 0usize
    while i < k {
        j = 0usize
        while j < k {
            var s = 0.0f64
            var c = 0usize
            while c < k {
                s += rinv[c * k + i] * rinv[c * k + j]
                c += 1usize
            }
            cov[j * k + i] = s
            j += 1usize
        }
        i += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += lf.residuals[i] * lf.residuals[i]
        i += 1usize
    }
    var s2 = nan()
    if n > k { s2 = rss / f64(n - k) }
    i = 0usize
    while i < p {
        se[i] = nan()
        tv[i] = nan()
        i += 1usize
    }
    i = 0usize
    while i < k {
        let col = f.pivot[i]
        se[col] = math.sqrt[f64](s2 * cov[i * k + i])
        tv[col] = lf.coef[col] / se[col]
        i += 1usize
    }
    ret (Ols { coef: lf.coef, se: se[0usize..p], tval: tv[0usize..p], sigma2: s2, rss: rss, rank: k, n: n, resid: lf.residuals }, ok)
}

// BIC of the fit as R's BIC(lm): -2 logLik + log(n) (rank + 1)
fn bic(o: *const Ols) -> f64 {
    let nf = f64(o.n)
    let ll = 0.5f64 * (0.0f64 - nf * (math.log[f64](2.0f64 * 3.141592653589793f64) + 1.0f64 - math.log[f64](nf) + math.log[f64](o.rss)))
    ret 0.0f64 - 2.0f64 * ll + math.log[f64](nf) * f64(o.rank + 1usize)
}
