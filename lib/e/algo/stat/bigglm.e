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
use e.math.dist as dist
use e.mem

type Fit = struct { iterations: usize, converged: bool, deviance: f64, rss: f64 }

// family ids: 8 inverse.gaussian(log), 0 gaussian(identity), 1 binomial(logit), 2 poisson(log), 3 Gamma(inverse), 4 Gamma(log), 5 gaussian(log), 6 binomial(probit), 7 binomial(cloglog)
fn base_kind(fam: u8) -> u8 {
    if fam == 0u8 || fam == 5u8 { ret 0u8 }
    if fam == 1u8 || fam == 6u8 || fam == 7u8 { ret 1u8 }
    if fam == 8u8 { ret 4u8 }
    if fam == 2u8 { ret 2u8 }
    ret 3u8
}

// 0 identity, 1 logit, 2 log, 3 inverse, 4 probit, 5 cloglog
fn link_kind(fam: u8) -> u8 {
    if fam == 0u8 { ret 0u8 }
    if fam == 1u8 { ret 1u8 }
    if fam == 2u8 || fam == 4u8 || fam == 5u8 || fam == 8u8 { ret 2u8 }
    if fam == 3u8 { ret 3u8 }
    if fam == 6u8 { ret 4u8 }
    ret 5u8
}

fn linkinv(fam: u8, eta: f64) -> f64 {
    let lk = link_kind(fam)
    if lk == 0u8 { ret eta }
    if lk == 1u8 {
        let e = math.exp[f64](eta)
        ret e / (1.0f64 + e)
    }
    if lk == 3u8 { ret 1.0f64 / eta }
    if lk == 4u8 {
        let thr = 0.0f64 - dist.qnorm(2.220446049250313e-16f64, 0.0f64, 1.0f64, true, false)
        var e = eta
        if e < 0.0f64 - thr { e = 0.0f64 - thr }
        if e > thr { e = thr }
        ret dist.pnorm(e, 0.0f64, 1.0f64, true, false)
    }
    if lk == 5u8 {
        var v = 0.0f64 - dist.expm1(0.0f64 - math.exp[f64](eta))
        if v > 1.0f64 - 2.220446049250313e-16f64 { v = 1.0f64 - 2.220446049250313e-16f64 }
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    ret math.exp[f64](eta)
}

fn mu_eta(fam: u8, eta: f64) -> f64 {
    let lk = link_kind(fam)
    if lk == 0u8 { ret 1.0f64 }
    if lk == 1u8 {
        let e = math.exp[f64](eta)
        var v = e / ((1.0f64 + e) * (1.0f64 + e))
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    if lk == 3u8 { ret 0.0f64 - 1.0f64 / (eta * eta) }
    if lk == 4u8 {
        var v = math.exp[f64](0.0f64 - eta * eta / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64)
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    if lk == 5u8 {
        var ee = eta
        if ee > 700.0f64 { ee = 700.0f64 }
        let e = math.exp[f64](ee)
        var v = e * math.exp[f64](0.0f64 - e)
        if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
        ret v
    }
    var v = math.exp[f64](eta)
    if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
    ret v
}

fn variance(fam: u8, mu: f64) -> f64 {
    let bk = base_kind(fam)
    if bk == 0u8 { ret 1.0f64 }
    if bk == 1u8 { ret mu * (1.0f64 - mu) }
    if bk == 3u8 { ret mu * mu }
    if bk == 4u8 { ret mu * mu * mu }
    ret mu
}

fn dev_resid(fam: u8, y: f64, mu: f64, w: f64) -> f64 {
    let bk = base_kind(fam)
    if bk == 0u8 { ret w * (y - mu) * (y - mu) }
    if bk == 1u8 {
        var a = 0.0f64
        var b = 0.0f64
        if y > 0.0f64 { a = y * math.log[f64](y / mu) }
        if y < 1.0f64 { b = (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
        ret 2.0f64 * w * (a + b)
    }
    if bk == 3u8 { ret 0.0f64 - 2.0f64 * w * (math.log[f64](y / mu) - (y - mu) / mu) }
    if bk == 4u8 { ret w * (y - mu) * (y - mu) / (y * mu * mu) }
    var t = 0.0f64
    if y > 0.0f64 { t = y * math.log[f64](y / mu) }
    ret 2.0f64 * w * (t - (y - mu))
}

// x is n by p column-major with the intercept column included; coef and se receive p values
fn bigglm(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, fam: u8, maxit: usize, tol: f64, coef: []f64, se: []f64) -> (Fit, err) {
    let (zo, ze) = mem.alloc[f64](a, n)
    if ze != ok { var none: Fit = zero
        ret (none, ze) }
    var q = 0usize
    while q < n {
        zo[q] = 0.0f64
        q += 1usize
    }
    let (ft, fe) = bigglm_off(a, x, y, w, zo, n, p, fam, maxit, tol, coef, se)
    ret (ft, fe)
}

// bigglm with an offset: the linear predictor is x b + off, and z - off is what the weighted regression sees
fn bigglm_off(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, off: []const f64, n: usize, p: usize, fam: u8, maxit: usize, tol: f64, coef: []f64, se: []f64) -> (Fit, err) {
    let (sd, sde) = mem.alloc[f64](a, p)
    if sde != ok { var none: Fit = zero
        ret (none, sde) }
    let (ft, fe) = bigglm_sand(a, x, y, w, off, n, p, fam, maxit, tol, coef, se, sd)
    ret (ft, fe)
}

// bigglm_off that also returns the sandwich standard errors of the last pass in sand (vcov(sandwich = TRUE)): (X'WX)^-1 (sum ww^2 e^2 x x') (X'WX)^-1 with e the working residual of that pass at the final coefficients
fn bigglm_sand(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, off: []const f64, n: usize, p: usize, fam: u8, maxit: usize, tol: f64, coef: []f64, se: []f64, sand: []f64) -> (Fit, err) {
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
            var eta = off[i]
            if have {
                var j = 0usize
                while j < p {
                    eta += x[j * n + i] * beta[j]
                    j += 1usize
                }
            }
            let mu = linkinv(fam, eta)
            let dmu = mu_eta(fam, eta)
            zz[i] = eta + (y[i] - mu) / dmu - off[i]
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
        if base_kind(fam) == 1u8 || base_kind(fam) == 2u8 { rep_disp = 1.0f64 }
        j = 0usize
        while j < p {
            coef[j] = beta[j]
            se[j] = math.sqrt[f64](inv[j * p + j] * rep_disp)
            sec[j] = math.sqrt[f64](inv[j * p + j] * disp)
            j += 1usize
        }
        if have {
            // sandwich: V = inv (sum ww^2 e^2 x x') inv, e = zz - x beta
            var jj = 0usize
            while jj < p {
                var vjj = 0.0f64
                var a1 = 0usize
                while a1 < p {
                    var b1 = 0usize
                    while b1 < p {
                        var m = 0.0f64
                        i = 0usize
                        while i < n {
                            var fe = 0.0f64
                            var q = 0usize
                            while q < p {
                                fe += x[q * n + i] * beta[q]
                                q += 1usize
                            }
                            let e = zz[i] - fe
                            m += ww[i] * ww[i] * e * e * x[a1 * n + i] * x[b1 * n + i]
                            i += 1usize
                        }
                        vjj += inv[jj * p + a1] * m * inv[b1 * p + jj]
                        b1 += 1usize
                    }
                    a1 += 1usize
                }
                sand[jj] = math.sqrt[f64](vjj)
                jj += 1usize
            }
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

// bigglm on a design that may have exactly collinear columns (x is n by p column-major, intercept included): a column that is a linear combination of the earlier ones (residual below 1e-10 of its own norm after Gram-Schmidt) is aliased as biglm's singcheck does: coef and se are NaN there (R's NA) and the fit is that of the remaining columns
fn bigglm_alias(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, off: []const f64, n: usize, p: usize, fam: u8, maxit: usize, tol: f64, coef: []f64, se: []f64, sand: []f64) -> (Fit, err) {
    var none: Fit = zero
    let (q, e1) = mem.alloc[f64](a, n * p)
    let (keep, e2) = mem.alloc[usize](a, p)
    let (xr, e3) = mem.alloc[f64](a, n * p)
    let (cr, e4) = mem.alloc[f64](a, p)
    let (sr, e5) = mem.alloc[f64](a, p)
    let (ar, e6) = mem.alloc[f64](a, p)
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    if e6 != ok { ret (none, e6) }
    var kept = 0usize
    var j = 0usize
    while j < p {
        var v = 0usize
        var nrm0 = 0.0f64
        while v < n {
            q[kept * n + v] = x[j * n + v]
            nrm0 += x[j * n + v] * x[j * n + v]
            v += 1usize
        }
        var k = 0usize
        while k < kept {
            var d = 0.0f64
            v = 0usize
            while v < n {
                d += q[kept * n + v] * q[k * n + v]
                v += 1usize
            }
            v = 0usize
            while v < n {
                q[kept * n + v] -= d * q[k * n + v]
                v += 1usize
            }
            k += 1usize
        }
        var nrm1 = 0.0f64
        v = 0usize
        while v < n {
            nrm1 += q[kept * n + v] * q[kept * n + v]
            v += 1usize
        }
        if nrm1 > 1.0e-10f64 * nrm0 {
            let s = math.sqrt[f64](nrm1)
            v = 0usize
            while v < n {
                q[kept * n + v] = q[kept * n + v] / s
                xr[kept * n + v] = x[j * n + v]
                v += 1usize
            }
            keep[kept] = j
            kept += 1usize
        }
        j += 1usize
    }
    let (ft, fe) = bigglm_sand(a, xr[0usize..n * kept], y, w, off, n, kept, fam, maxit, tol, cr[0usize..kept], sr[0usize..kept], ar[0usize..kept])
    j = 0usize
    while j < p {
        coef[j] = 0.0f64 / 0.0f64
        se[j] = 0.0f64 / 0.0f64
        sand[j] = 0.0f64 / 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < kept {
        coef[keep[j]] = cr[j]
        se[keep[j]] = sr[j]
        sand[keep[j]] = ar[j]
        j += 1usize
    }
    ret (ft, fe)
}
