// R biglm::bigglm for the gaussian (identity), binomial (logit) and Poisson (log) families: iteratively reweighted
// least squares in which each pass accumulates the weighted cross-products of the whole data (the package does it
// chunk by chunk with a QR update; the sums are the same), with the package's own stopping rule. The standard errors
// are those of vcov.bigglm, `sqrt(diag((X'WX)^-1 * dispersion))` with dispersion `ss / (n - p)` for the gaussian family and 1
// for the binomial and Poisson; the convergence test uses the scaled errors of every family:
// `max |(beta_old - beta) / se| < tolerance`.
//
// Not here: other families and links, offsets, the sandwich variance, chunked reading, singular designs.

use e.algo.stat.psych as ps
use e.math
use e.mem

type Fit = struct { iterations: usize, converged: bool, deviance: f64, rss: f64 }

fn linkinv(fam: u8, eta: f64) -> f64 {
    if fam == 0u8 { ret eta }
    if fam == 1u8 {
        let e = math.exp[f64](eta)
        ret e / (1.0f64 + e)
    }
    ret math.exp[f64](eta)
}

fn mu_eta(fam: u8, eta: f64) -> f64 {
    if fam == 0u8 { ret 1.0f64 }
    if fam == 1u8 {
        let e = math.exp[f64](eta)
        var v = e / ((1.0f64 + e) * (1.0f64 + e))
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    var v = math.exp[f64](eta)
    if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
    ret v
}

fn variance(fam: u8, mu: f64) -> f64 {
    if fam == 0u8 { ret 1.0f64 }
    if fam == 1u8 { ret mu * (1.0f64 - mu) }
    ret mu
}

fn dev_resid(fam: u8, y: f64, mu: f64, w: f64) -> f64 {
    if fam == 0u8 { ret w * (y - mu) * (y - mu) }
    if fam == 1u8 {
        var a = 0.0f64
        var b = 0.0f64
        if y > 0.0f64 { a = y * math.log[f64](y / mu) }
        if y < 1.0f64 { b = (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
        ret 2.0f64 * w * (a + b)
    }
    var t = 0.0f64
    if y > 0.0f64 { t = y * math.log[f64](y / mu) }
    ret 2.0f64 * w * (t - (y - mu))
}

// x is n by p column-major with the intercept column included; coef and se receive p values
fn bigglm(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, fam: u8, maxit: usize, tol: f64, coef: []f64, se: []f64) -> (Fit, err) {
    var fit: Fit = zero
    let (xtx, e1) = mem.alloc[f64](a, p * p)
    let (xtz, e2) = mem.alloc[f64](a, p)
    let (inv, e3) = mem.alloc[f64](a, p * p)
    let (beta, e4) = mem.alloc[f64](a, p)
    let (old, e5) = mem.alloc[f64](a, p)
    let (zz, e6) = mem.alloc[f64](a, n)
    let (ww, e7) = mem.alloc[f64](a, n)
    let (sec, e8) = mem.alloc[f64](a, p)
    if e8 != ok { ret (fit, e8) }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (fit, e1) }
    var have = false
    var it = 1usize
    while it <= maxit {
        var dev = 0.0f64
        var rss = 0.0f64
        var sumw = 0.0f64
        var i = 0usize
        while i < n {
            var eta = 0.0f64
            if have {
                var j = 0usize
                while j < p {
                    eta += x[j * n + i] * beta[j]
                    j += 1usize
                }
            }
            let mu = linkinv(fam, eta)
            let dmu = mu_eta(fam, eta)
            zz[i] = eta + (y[i] - mu) / dmu
            ww[i] = w[i] * dmu * dmu / variance(fam, mu)
            if have {
                dev += dev_resid(fam, y[i], mu, w[i])
                rss += (y[i] - mu) * (y[i] - mu) / (w[i] * variance(fam, mu))
            }
            sumw += w[i]
            i += 1usize
        }
        if have { rss = rss * (sumw / f64(n)) }
        // weighted least squares of z on x with weights ww
        var j = 0usize
        while j < p {
            var l = 0usize
            while l < p {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += ww[i] * x[j * n + i] * x[l * n + i]
                    i += 1usize
                }
                xtx[j * p + l] = s
                l += 1usize
            }
            var t = 0.0f64
            i = 0usize
            while i < n {
                t += ww[i] * x[j * n + i] * zz[i]
                i += 1usize
            }
            xtz[j] = t
            j += 1usize
        }
        if !ps.invert(a, xtx, p, inv) { ret (fit, Singular) }
        j = 0usize
        while j < p {
            old[j] = beta[j]
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += inv[j * p + l] * xtz[l]
                l += 1usize
            }
            beta[j] = s
            j += 1usize
        }
        var ss = 0.0f64
        i = 0usize
        while i < n {
            var f = 0.0f64
            j = 0usize
            while j < p {
                f += x[j * n + i] * beta[j]
                j += 1usize
            }
            ss += ww[i] * (zz[i] - f) * (zz[i] - f)
            i += 1usize
        }
        let disp = ss / f64(n - p)
        // the stopping rule scales by ss / (n - p) for every family (the working fit is a biglm); the reported
        // errors have dispersion 1 for the binomial and Poisson families
        var rep_disp = disp
        if fam >= 1u8 { rep_disp = 1.0f64 }
        j = 0usize
        while j < p {
            coef[j] = beta[j]
            se[j] = math.sqrt[f64](inv[j * p + j] * rep_disp)
            sec[j] = math.sqrt[f64](inv[j * p + j] * disp)
            j += 1usize
        }
        fit.iterations = it
        fit.deviance = dev
        fit.rss = rss
        if it >= maxit { break }
        if have {
            var mx = 0.0f64
            j = 0usize
            while j < p {
                let dl = math.abs[f64]((old[j] - beta[j]) / sec[j])
                if dl > mx { mx = dl }
                j += 1usize
            }
            if mx < tol {
                fit.converged = true
                break
            }
        }
        have = true
        it += 1usize
    }
    ret (fit, ok)
}

error Singular
