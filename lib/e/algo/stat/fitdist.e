// R fitdistrplus: the maximum-likelihood fits that have closed forms (kind 0 normal, 1 log-normal, 2 exponential) with the log-likelihood, AIC and BIC, and
// gofstat's Kolmogorov-Smirnov, Cramer-von Mises and Anderson-Darling statistics of the fitted distribution.
//
// Not here: the iterative fits (gamma, Weibull, beta and the rest), the moment, quantile-matching and maximum-goodness-of-fit methods, the standard errors
// (the package takes them from a numerical Hessian), bootstrap, censored data and the discrete distributions.

use e.math
use e.math.dist as dist
use e.mem

type Fit = struct { p1: f64, p2: f64, loglik: f64, npar: f64 }

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

fn cdf(kind: usize, p1: f64, p2: f64, v: f64) -> f64 {
    if kind == 0usize { ret dist.pnorm(v, p1, p2, true, false) }
    if kind == 1usize { ret dist.pnorm(math.log[f64](v), p1, p2, true, false) }
    ret 1.0f64 - math.exp[f64](0.0f64 - p1 * v)
}

fn fit(a: *mem.Arena, x: []const f64, kind: usize) -> (Fit, err) {
    var f: Fit = zero
    let n = f64(x.len)
    var s = 0.0f64
    var i = 0usize
    if kind == 2usize {
        while i < x.len {
            s += x[i]
            i += 1usize
        }
        f.p1 = n / s
        f.p2 = 0.0f64
        f.loglik = n * math.log[f64](f.p1) - f.p1 * s
        f.npar = 1.0f64
        ret (f, ok)
    }
    // location and scale on the raw (kind 0) or log scale (kind 1), the scale with divisor n
    var lsum = 0.0f64
    i = 0usize
    while i < x.len {
        var v = x[i]
        if kind == 1usize {
            v = math.log[f64](v)
            lsum += v
        }
        s += v
        i += 1usize
    }
    let m = s / n
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        var v = x[i]
        if kind == 1usize { v = math.log[f64](v) }
        ss += (v - m) * (v - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / n)
    f.p1 = m
    f.p2 = sd
    // the normal log-likelihood of the (log) data, less the sum of the logs for the log-normal
    f.loglik = 0.0f64 - n * math.log[f64](sd) - 0.5f64 * n * math.log[f64](2.0f64 * 3.141592653589793238462643383279f64) - ss / (2.0f64 * sd * sd) - lsum
    f.npar = 2.0f64
    ret (f, ok)
}

fn aic(f: *const Fit) -> f64 { ret 2.0f64 * f.npar - 2.0f64 * f.loglik }

fn bic(f: *const Fit, n: usize) -> f64 { ret math.log[f64](f64(n)) * f.npar - 2.0f64 * f.loglik }

// (ks, cvm, ad) of the sample against the fitted distribution
fn gof(a: *mem.Arena, x: []const f64, kind: usize, f: *const Fit) -> (f64, f64, f64) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64 / 0.0f64, 0.0f64, 0.0f64) }
    let n = f64(s.len)
    var ks = 0.0f64
    var cvm = 1.0f64 / (12.0f64 * n)
    var ad = 0.0f64 - n
    var i = 0usize
    while i < s.len {
        let p = cdf(kind, f.p1, f.p2, s[i])
        let up = f64(i + 1usize) / n - p
        let dn = p - f64(i) / n
        if up > ks { ks = up }
        if dn > ks { ks = dn }
        let t = (2.0f64 * f64(i + 1usize) - 1.0f64) / (2.0f64 * n)
        cvm += (p - t) * (p - t)
        let q = cdf(kind, f.p1, f.p2, s[s.len - 1usize - i])
        ad -= (2.0f64 * f64(i + 1usize) - 1.0f64) * (math.log[f64](p) + math.log[f64](1.0f64 - q)) / n
        i += 1usize
    }
    ret (ks, cvm, ad)
}
