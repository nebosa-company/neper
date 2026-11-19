// R arm bayesglm for every family and link glm knows, with prior weights and an offset: bayesglm.fit's loop, step for step (the augmented weighted least squares through dqrdc2, the
// prior standard deviations updated from the posterior, the dispersion of the families that estimate it, R's stopping rule).
//
// Family codes: 0 gaussian, 1 binomial, 2 poisson, 3 Gamma, 4 inverse.gaussian, 5 quasibinomial, 6 quasipoisson. Link codes: 0 identity, 1 log, 2 inverse, 3 logit, 4 probit,
// 5 cauchit, 6 cloglog, 7 sqrt, 8 1/mu^2.
// Also here: glm.fit (glm_fit_gen), sim and display for glm and bayesglm, standardize and rescale. Not here: start, etastart and mustart supplied by the caller, and step halving in bayesglm (its loop answers 0 iterations).

use e.algo.stat.armx87 as xe
use e.algo.stat.arm as ar
use e.algo.stat.armextra as ax
use e.algo.stat.armld as ld
use e.algo.stat.gbmfit as gb
use e.algo.stat.armnorm as an
use e.algo.stat.armtan as tn
use e.algo.stat.mass as ms
use e.algo.rand.r as rng
use e.algo.linalg.decomp as dc
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

// x^3 as R rounds it (x * (x * x), two roundings) and x^1.5 correctly rounded (R on Windows takes powl and rounds), through double-double arithmetic
fn pow3(x: f64) -> f64 { ret x * (x * x) }

fn pow15(x: f64) -> f64 {
    let sq = math.sqrt[f64](x)
    let (sp, se) = gb.two_prod(sq, sq)
    let lo = ((x - sp) - se) / (2.0f64 * sq)
    let (s, t) = gb.dd_mul(sq, lo, x, 0.0f64)
    let _ = t
    ret s
}

fn linkfun(link: usize, mu: f64) -> f64 {
    if link == 0usize { ret mu }
    if link == 1usize { ret xe.log_r(mu) }
    if link == 2usize { ret 1.0f64 / mu }
    if link == 3usize { ret xe.log_r(mu / (1.0f64 - mu)) }
    if link == 4usize { ret qnorm_r(mu) }
    if link == 5usize { ret qcauchy_r(mu) }
    if link == 6usize { ret xe.log_r(0.0f64 - xe.log_r(1.0f64 - mu)) }
    if link == 7usize { ret math.sqrt[f64](mu) }
    ret 1.0f64 / (mu * mu)
}

fn linkinv(link: usize, eta: f64) -> f64 {
    if link == 0usize { ret eta }
    if link == 1usize {
        var m = xe.exp_r(eta)
        if m < eps() { m = eps() }
        ret m
    }
    if link == 2usize { ret 1.0f64 / eta }
    if link == 3usize {
        var t = xe.exp_r(eta)
        if eta < 0.0f64 - 30.0f64 { t = eps() }
        if eta > 30.0f64 { t = 1.0f64 / eps() }
        ret t / (1.0f64 + t)
    }
    if link == 4usize {
        let th = 0.0f64 - dist.qnorm(eps(), 0.0f64, 1.0f64, true, false)
        var e = eta
        if e < 0.0f64 - th { e = 0.0f64 - th }
        if e > th { e = th }
        ret an.pnorm_cr(e)
    }
    if link == 5usize {
        let th = 0.0f64 - qcauchy_r(eps())
        var e = eta
        if e < 0.0f64 - th { e = 0.0f64 - th }
        if e > th { e = th }
        ret tn.pcauchy_c(e)
    }
    if link == 6usize {
        var m = 0.0f64 - dist.expm1(0.0f64 - xe.exp_r(eta))
        if m > 1.0f64 - eps() { m = 1.0f64 - eps() }
        if m < eps() { m = eps() }
        ret m
    }
    if link == 7usize { ret eta * eta }
    ret 1.0f64 / math.sqrt[f64](eta)
}

fn mu_eta(link: usize, eta: f64) -> f64 {
    if link == 0usize { ret 1.0f64 }
    if link == 1usize {
        var m = xe.exp_r(eta)
        if m < eps() { m = eps() }
        ret m
    }
    if link == 2usize { ret 0.0f64 - 1.0f64 / (eta * eta) }
    if link == 3usize {
        let op = 1.0f64 + xe.exp_r(eta)
        if eta > 30.0f64 || eta < 0.0f64 - 30.0f64 { ret eps() }
        ret xe.exp_r(eta) / (op * op)
    }
    if link == 4usize {
        var m = an.dnorm_cr(eta)
        if m < eps() { m = eps() }
        ret m
    }
    if link == 5usize {
        var m = dist.dcauchy(eta, 0.0f64, 1.0f64, false)
        if m < eps() { m = eps() }
        ret m
    }
    if link == 6usize {
        var e = eta
        if e > 700.0f64 { e = 700.0f64 }
        var m = xe.exp_r(e) * xe.exp_r(0.0f64 - xe.exp_r(e))
        if m < eps() { m = eps() }
        ret m
    }
    if link == 7usize { ret 2.0f64 * eta }
    ret 0.0f64 - 1.0f64 / (2.0f64 * pow15(eta))
}

fn variance(fam: usize, mu: f64) -> f64 {
    if fam == 0usize { ret 1.0f64 }
    if fam == 1usize || fam == 5usize { ret mu * (1.0f64 - mu) }
    if fam == 2usize || fam == 6usize { ret mu }
    if fam == 3usize { ret mu * mu }
    ret pow3(mu)
}

fn ylogy(y: f64, mu: f64) -> f64 {
    if y != 0.0f64 { ret y * xe.log_r(y / mu) }
    ret 0.0f64
}

fn dev_resid(fam: usize, y: f64, mu: f64, wt: f64) -> f64 {
    if fam == 0usize { ret wt * ((y - mu) * (y - mu)) }
    if fam == 1usize || fam == 5usize { ret 2.0f64 * wt * (ylogy(y, mu) + ylogy(1.0f64 - y, 1.0f64 - mu)) }
    if fam == 2usize || fam == 6usize {
        var r = mu * wt
        if y > 0.0f64 { r = wt * (y * xe.log_r(y / mu) - (y - mu)) }
        ret 2.0f64 * r
    }
    if fam == 3usize {
        var q = 1.0f64
        if y != 0.0f64 { q = y / mu }
        ret 0.0f64 - 2.0f64 * wt * (xe.log_r(q) - (y - mu) / mu)
    }
    ret wt * ((y - mu) * (y - mu)) / (y * (mu * mu))
}

fn mustart(fam: usize, y: f64, wt: f64) -> f64 {
    if fam == 1usize || fam == 5usize { ret (wt * y + 0.5f64) / (wt + 1.0f64) }
    if fam == 2usize || fam == 6usize { ret y + 0.1f64 }
    ret y
}

// sum of the deviance residuals, long double style
fn deviance(fam: usize, y: []const f64, mu: []const f64, wt: []const f64, n: usize, tmp: []f64) -> f64 {
    var i = 0usize
    while i < n {
        tmp[i] = dev_resid(fam, y[i], mu[i], wt[i])
        i += 1usize
    }
    ret ax.csum(tmp[0usize..n])
}

// bayesglm(y ~ x, family, prior.mean, prior.scale, prior.df, weights, offset, scaled, intercept): x is n by k row-major, with the intercept in column 0 when `intercept`; prior_* hold k values
// (the intercept's first), already defaulted by the caller. wts and offset are n long, or empty for weights 1 and no offset. coef gets the k coefficients; info (at least 4 long) gets the
// dispersion, deviance, null deviance and the iteration count. Answers the iteration count, 0 on failure, 101 when the loop ran out of its 100 iterations (bayesglm's maxit) (R's warning).
fn bayesglm_gen(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, fam: usize, link: usize, wts: []const f64, off: []const f64, prior_mean: []const f64, prior_df: []const f64, prior_scale: []const f64, scaled: bool, intercept: bool, coef: []f64, info: []f64, cov: []f64) -> usize {
    let (wv, e1) = mem.alloc[f64](a, n)
    let (ov, e2) = mem.alloc[f64](a, n)
    let (mu, e3) = mem.alloc[f64](a, n)
    let (eta, e4) = mem.alloc[f64](a, n)
    let (tmp, e5) = mem.alloc[f64](a, n)
    let (z, e6) = mem.alloc[f64](a, n)
    let (w, e7) = mem.alloc[f64](a, n)
    let (psd, e8) = mem.alloc[f64](a, k)
    let (ps, e9) = mem.alloc[f64](a, k)
    let (ps0, e10) = mem.alloc[f64](a, k)
    let (cmn, e11) = mem.alloc[f64](a, k)
    let (hat, e12) = mem.alloc[f64](a, k)
    let (vc, e13) = mem.alloc[f64](a, k * k)
    let (good, e14) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret 0usize }
    let nf = f64(n)
    var i = 0usize
    while i < n {
        wv[i] = 1.0f64
        ov[i] = 0.0f64
        if wts.len == n { wv[i] = wts[i] }
        if off.len == n { ov[i] = off[i] }
        i += 1usize
    }
    var j = 0usize
    while j < k {
        ps[j] = prior_scale[j]
        j += 1usize
    }
    if scaled {
        if fam == 0usize {
            let sdy = math.sqrt[f64](ld.var_ld(y[0usize..n]))
            j = 0usize
            while j < k {
                ps[j] = ps[j] * 2.0f64 * sdy
                j += 1usize
            }
        }
        j = 0usize
        while j < k {
            ps0[j] = ps[j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            var lo = x[j]
            var hi = x[j]
            i = 0usize
            while i < n {
                tmp[i] = x[i * k + j]
                if tmp[i] < lo { lo = tmp[i] }
                if tmp[i] > hi { hi = tmp[i] }
                i += 1usize
            }
            var distinct = 0usize
            i = 0usize
            while i < n && distinct < 3usize {
                var seen = false
                var q = 0usize
                while q < i {
                    if tmp[q] == tmp[i] { seen = true }
                    q += 1usize
                }
                if !seen { distinct += 1usize }
                i += 1usize
            }
            var xs = 1.0f64
            if distinct == 2usize { xs = hi - lo }
            if distinct > 2usize {
                xs = 2.0f64 * math.sqrt[f64](ld.var_ld(tmp[0usize..n]))
            }
            ps[j] = ps[j] / xs
            if ps[j] < 1.0e-12f64 { ps[j] = 1.0e-12f64 }
            j += 1usize
        }
    }
    j = 0usize
    while j < k {
        psd[j] = ps[j]
        i = 0usize
        while i < n {
            tmp[i] = x[i * k + j]
            i += 1usize
        }
        cmn[j] = ld.colmean_ld(tmp[0usize..n])
        j += 1usize
    }
    i = 0usize
    while i < n {
        eta[i] = linkfun(link, mustart(fam, y[i], wv[i]))
        mu[i] = linkinv(link, eta[i])
        i += 1usize
    }
    var devold = deviance(fam, y, mu, wv, n, tmp)
    var disp = 1.0f64
    if fam != 1usize && fam != 2usize {
        disp = ld.var_ld(y[0usize..n]) / 10000.0f64
    }
    var dispold = disp
    var dev = devold
    var iter = 1usize
    var conv = false
    var done_iter = 0usize
    while iter <= 100usize && !conv {
        var ng = 0usize
        i = 0usize
        while i < n {
            let me = mu_eta(link, eta[i])
            if wv[i] > 0.0f64 && me != 0.0f64 {
                good[ng] = i
                z[ng] = (eta[i] - ov[i]) + (y[i] - mu[i]) / me
                w[ng] = math.sqrt[f64]((wv[i] * (me * me)) / variance(fam, mu[i]))
                ng += 1usize
            }
            i += 1usize
        }
        if ng == 0usize { ret 0usize }
        let rows = ng + k
        let (xs2, e15) = mem.alloc[f64](a, rows * k)
        let (zs2, e16) = mem.alloc[f64](a, rows)
        let (qa, e17) = mem.alloc[f64](a, k)
        let (w2a, e18) = mem.alloc[f64](a, k)
        let (pva, e19) = mem.alloc[usize](a, k)
        if e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret 0usize }
        var r = 0usize
        while r < ng {
            let ws = w[r]
            var c = 0usize
            while c < k {
                xs2[c * rows + r] = x[good[r] * k + c] * ws
                c += 1usize
            }
            zs2[r] = z[r] * ws
            r += 1usize
        }
        var pr = 0usize
        while pr < k {
            let wp = math.sqrt[f64](disp) / psd[pr]
            var c = 0usize
            while c < k {
                var v = 0.0f64
                if c == pr { v = 1.0f64 }
                if pr == 0usize && intercept && scaled { v = cmn[c] }
                xs2[c * rows + ng + pr] = v * wp
                c += 1usize
            }
            zs2[ng + pr] = prior_mean[pr] * wp
            pr += 1usize
        }
        let qe = ar.dqrdc2_full(xs2, rows, k, qa, w2a, 0.0000001f64)
        if qe != ok { ret 0usize }
        let fq = dc.Qr { qr: xs2, qraux: qa, pivot: pva, rank: k, n: rows, p: k }
        dc.qr_qty(&fq, zs2)
        var rr = k
        while rr > 0usize {
            rr -= 1usize
            hat[rr] = zs2[rr] / xs2[rr * rows + rr]
            if rr > 0usize {
                let t = 0.0f64 - hat[rr]
                var q2 = 0usize
                while q2 < rr {
                    zs2[q2] = zs2[q2] + t * xs2[rr * rows + q2]
                    q2 += 1usize
                }
            }
        }
        ar.chol2inv_upper(xs2, rows, k, vc)
        if cov.len >= k * k {
            var cc = 0usize
            while cc < k * k {
                cov[cc] = vc[cc]
                cc += 1usize
            }
        }
        if fam == 0usize && scaled {
            j = 0usize
            while j < k {
                ps[j] = ps0[j]
                j += 1usize
            }
        }
        j = 0usize
        while j < k {
            let dfj = prior_df[j]
            if dfj == math.inf64() { psd[j] = ps[j] } else {
                let dm = hat[j] - prior_mean[j]
                psd[j] = math.sqrt[f64]((dm * dm + vc[j * k + j] * disp + dfj * (ps[j] * ps[j])) / (1.0f64 + dfj))
            }
            coef[j] = hat[j]
            j += 1usize
        }
        i = 0usize
        while i < n {
            var e = 0.0f64
            j = 0usize
            while j < k {
                e += x[i * k + j] * hat[j]
                j += 1usize
            }
            eta[i] = e + ov[i]
            mu[i] = linkinv(link, eta[i])
            i += 1usize
        }
        dev = deviance(fam, y, mu, wv, n, tmp)
        if fam != 1usize && fam != 2usize {
            // mean((w * (z - x coefs.hat))^2) and mean(rowSums((x V) * x)) * dispersion
            var q = 0usize
            while q < ng {
                var e = 0.0f64
                j = 0usize
                while j < k {
                    e += x[good[q] * k + j] * hat[j]
                    j += 1usize
                }
                let d = w[q] * (z[q] - e)
                tmp[q] = d * d
                q += 1usize
            }
            let mse = ax.rmean(tmp[0usize..ng])
            let (rs, e20) = mem.alloc[f64](a, n)
            if e20 != ok { ret 0usize }
            q = 0usize
            while q < n {
                let (cs, e21) = mem.alloc[f64](a, k)
                if e21 != ok { ret 0usize }
                var c = 0usize
                while c < k {
                    var xv = 0.0f64
                    var l = 0usize
                    while l < k {
                        xv += x[q * k + l] * vc[l * k + c]
                        l += 1usize
                    }
                    cs[c] = xv * x[q * k + c]
                    c += 1usize
                }
                rs[q] = ax.csum(cs[0usize..k])
                q += 1usize
            }
            let unc = ax.rmean(rs[0usize..n]) * disp
            disp = mse + unc
        }
        if iter > 1usize && math.abs[f64](dev - devold) / (0.1f64 + math.abs[f64](dev)) < 1.0e-8f64 && math.abs[f64](disp - dispold) / (0.1f64 + math.abs[f64](disp)) < 1.0e-8f64 {
            conv = true
            done_iter = iter
        } else {
            devold = dev
            dispold = disp
            iter += 1usize
        }
    }
    // the null deviance: the weighted mean when there is an intercept, else the inverse link of the offset
    i = 0usize
    while i < n {
        tmp[i] = wv[i] * y[i]
        i += 1usize
    }
    let swy = ax.csum(tmp[0usize..n])
    let sw = ax.csum(wv[0usize..n])
    i = 0usize
    while i < n {
        if intercept { tmp[i] = dev_resid(fam, y[i], swy / sw, wv[i]) } else { tmp[i] = dev_resid(fam, y[i], linkinv(link, ov[i]), wv[i]) }
        i += 1usize
    }
    var nulldev = ax.csum(tmp[0usize..n])
    if off.len == n && intercept {
        // bayesglm refits the intercept alone under the offset (same priors for the intercept) and takes that deviance
        nulldev = dev
        if k > 1usize {
            let (ones, e22) = mem.alloc[f64](a, n)
            let (c1, e23) = mem.alloc[f64](a, 1usize)
            let (i1, e24) = mem.alloc[f64](a, 4usize)
            if e22 != ok || e23 != ok || e24 != ok { ret 0usize }
            i = 0usize
            while i < n {
                ones[i] = 1.0f64
                i += 1usize
            }
            var nocov: []f64 = zero
            let ie = bayesglm_gen(a, ones, y, n, 1usize, fam, link, wts, off, prior_mean[0usize..1usize], prior_df[0usize..1usize], prior_scale[0usize..1usize], scaled, true, c1, i1, nocov)
            if ie == 0usize { ret 0usize }
            nulldev = i1[1usize]
        }
    }
    if info.len >= 4usize {
        info[0usize] = disp
        info[1usize] = dev
        info[2usize] = nulldev
        info[3usize] = f64(done_iter)
        if !conv { info[3usize] = 100.0f64 }
    }
    if conv { ret done_iter }
    ret 101usize
}

// validmu and valideta of the families and links (all values finite, and in range)
fn valid_mu(fam: usize, mu: []const f64, n: usize) -> bool {
    var i = 0usize
    while i < n {
        let m = mu[i]
        if m - m != 0.0f64 { ret false }
        if fam == 1usize || fam == 5usize { if m <= 0.0f64 || m >= 1.0f64 { ret false } }
        if fam == 2usize || fam == 6usize || fam == 3usize || fam == 4usize { if m <= 0.0f64 { ret false } }
        i += 1usize
    }
    ret true
}

fn valid_eta(link: usize, eta: []const f64, n: usize) -> bool {
    var i = 0usize
    while i < n {
        let e = eta[i]
        if link == 2usize || link == 7usize || link == 8usize { if e - e != 0.0f64 { ret false } }
        if link == 2usize && e == 0.0f64 { ret false }
        if (link == 7usize || link == 8usize) && e <= 0.0f64 { ret false }
        i += 1usize
    }
    ret true
}

// eta = x beta + offset and mu = linkinv(eta) for every observation
fn eta_mu(x: []const f64, n: usize, k: usize, b: []const f64, ov: []const f64, link: usize, eta: []f64, mu: []f64) {
    var i = 0usize
    while i < n {
        var e = 0.0f64
        var j = 0usize
        while j < k {
            e += x[i * k + j] * b[j]
            j += 1usize
        }
        eta[i] = e + ov[i]
        mu[i] = linkinv(link, eta[i])
        i += 1usize
    }
}

// glm(y ~ x, family, weights, offset) through glm.fit: the iteratively reweighted least squares step for step (dqrdc2 at tolerance 1e-11, the deviance stopping rule at 1e-8, the step halving
// of a divergent or invalid step, at most 25 iterations). coef gets the k coefficients and cov the unscaled covariance chol2inv(R) of the last iteration; info (at least 5 long) gets
// summary.glm's dispersion, the deviance, the null deviance (the intercept-only refit when there is an offset), the iteration count and the residual degrees of freedom. Answers the
// iteration count, 0 on failure, 26 when it did not converge.
fn glm_fit_gen(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, fam: usize, link: usize, wts: []const f64, off: []const f64, intercept: bool, coef: []f64, cov: []f64, info: []f64) -> usize {
    let (wv, e1) = mem.alloc[f64](a, n)
    let (ov, e2) = mem.alloc[f64](a, n)
    let (mu, e3) = mem.alloc[f64](a, n)
    let (eta, e4) = mem.alloc[f64](a, n)
    let (tmp, e5) = mem.alloc[f64](a, n)
    let (z, e6) = mem.alloc[f64](a, n)
    let (w, e7) = mem.alloc[f64](a, n)
    let (good, e8) = mem.alloc[usize](a, n)
    let (cold, e9) = mem.alloc[f64](a, k)
    let (st, e10) = mem.alloc[f64](a, k)
    let (wlast, e11) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        wv[i] = 1.0f64
        ov[i] = 0.0f64
        wlast[i] = 0.0f64
        if wts.len == n { wv[i] = wts[i] }
        if off.len == n { ov[i] = off[i] }
        eta[i] = linkfun(link, mustart(fam, y[i], wv[i]))
        mu[i] = linkinv(link, eta[i])
        i += 1usize
    }
    if !valid_mu(fam, mu, n) || !valid_eta(link, eta, n) { ret 0usize }
    var devold = deviance(fam, y, mu, wv, n, tmp)
    var dev = devold
    var haveold = false
    var conv = false
    var iter = 1usize
    var ng = 0usize
    while iter <= 25usize && !conv {
        ng = 0usize
        i = 0usize
        while i < n {
            let me = mu_eta(link, eta[i])
            wlast[i] = 0.0f64
            if wv[i] > 0.0f64 && me != 0.0f64 {
                good[ng] = i
                z[ng] = (eta[i] - ov[i]) + (y[i] - mu[i]) / me
                w[ng] = math.sqrt[f64]((wv[i] * (me * me)) / variance(fam, mu[i]))
                wlast[i] = w[ng] * w[ng]
                ng += 1usize
            }
            i += 1usize
        }
        if ng == 0usize { ret 0usize }
        let (xq, e12) = mem.alloc[f64](a, ng * k)
        let (zq, e13) = mem.alloc[f64](a, ng)
        let (qa, e14) = mem.alloc[f64](a, k)
        let (w2a, e15) = mem.alloc[f64](a, k)
        let (pva, e16) = mem.alloc[usize](a, k)
        if e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret 0usize }
        var r = 0usize
        while r < ng {
            var c = 0usize
            while c < k {
                xq[c * ng + r] = x[good[r] * k + c] * w[r]
                c += 1usize
            }
            zq[r] = z[r] * w[r]
            r += 1usize
        }
        let qe = ar.dqrdc2_full(xq, ng, k, qa, w2a, 1.0e-11f64)
        if qe != ok { ret 0usize }
        let fq = dc.Qr { qr: xq, qraux: qa, pivot: pva, rank: k, n: ng, p: k }
        dc.qr_qty(&fq, zq)
        var rr = k
        while rr > 0usize {
            rr -= 1usize
            st[rr] = zq[rr] / xq[rr * ng + rr]
            if rr > 0usize {
                let t = 0.0f64 - st[rr]
                var q2 = 0usize
                while q2 < rr {
                    zq[q2] = zq[q2] + t * xq[rr * ng + q2]
                    q2 += 1usize
                }
            }
        }
        ar.chol2inv_upper(xq, ng, k, cov)
        eta_mu(x, n, k, st, ov, link, eta, mu)
        dev = deviance(fam, y, mu, wv, n, tmp)
        if dev - dev != 0.0f64 {
            if !haveold { ret 0usize }
            var ii = 1usize
            while dev - dev != 0.0f64 {
                if ii > 25usize { ret 0usize }
                ii += 1usize
                var j = 0usize
                while j < k {
                    st[j] = (st[j] + cold[j]) / 2.0f64
                    j += 1usize
                }
                eta_mu(x, n, k, st, ov, link, eta, mu)
                dev = deviance(fam, y, mu, wv, n, tmp)
            }
        }
        if !valid_eta(link, eta, n) || !valid_mu(fam, mu, n) {
            if !haveold { ret 0usize }
            var ii = 1usize
            while !valid_eta(link, eta, n) || !valid_mu(fam, mu, n) {
                if ii > 25usize { ret 0usize }
                ii += 1usize
                var j = 0usize
                while j < k {
                    st[j] = (st[j] + cold[j]) / 2.0f64
                    j += 1usize
                }
                eta_mu(x, n, k, st, ov, link, eta, mu)
            }
            dev = deviance(fam, y, mu, wv, n, tmp)
        }
        var j = 0usize
        while j < k {
            coef[j] = st[j]
            j += 1usize
        }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 {
            conv = true
        } else {
            devold = dev
            j = 0usize
            while j < k {
                cold[j] = st[j]
                j += 1usize
            }
            haveold = true
            iter += 1usize
        }
    }
    // summary.glm's dispersion: 1 for binomial and poisson, else the weighted working residuals over the residual degrees of freedom
    let rdf = f64(ng) - f64(k)
    var disp = 1.0f64
    if fam != 1usize && fam != 2usize {
        i = 0usize
        var m = 0usize
        while i < n {
            if wlast[i] > 0.0f64 {
                let me = mu_eta(link, eta[i])
                let r = (y[i] - mu[i]) / me
                tmp[m] = wlast[i] * (r * r)
                m += 1usize
            }
            i += 1usize
        }
        disp = ax.csum(tmp[0usize..m]) / rdf
    }
    i = 0usize
    while i < n {
        tmp[i] = wv[i] * y[i]
        i += 1usize
    }
    let swy = ax.csum(tmp[0usize..n])
    let sw = ax.csum(wv[0usize..n])
    i = 0usize
    while i < n {
        if intercept { tmp[i] = dev_resid(fam, y[i], swy / sw, wv[i]) } else { tmp[i] = dev_resid(fam, y[i], linkinv(link, ov[i]), wv[i]) }
        i += 1usize
    }
    var nulldev = ax.csum(tmp[0usize..n])
    if off.len == n && intercept {
        // glm refits the intercept alone under the offset and takes that deviance
        nulldev = dev
        if k > 1usize {
            let (ones, e17) = mem.alloc[f64](a, n)
            let (c1, e18) = mem.alloc[f64](a, 1usize)
            let (v1, e19) = mem.alloc[f64](a, 1usize)
            let (i1, e20) = mem.alloc[f64](a, 5usize)
            if e17 != ok || e18 != ok || e19 != ok || e20 != ok { ret 0usize }
            i = 0usize
            while i < n {
                ones[i] = 1.0f64
                i += 1usize
            }
            let ie = glm_fit_gen(a, ones, y, n, 1usize, fam, link, wts, off, true, c1, v1, i1)
            if ie == 0usize { ret 0usize }
            nulldev = i1[1usize]
        }
    }
    if info.len >= 5usize {
        info[0usize] = disp
        info[1usize] = dev
        info[2usize] = nulldev
        info[3usize] = f64(iter)
        info[4usize] = rdf
    }
    if conv { ret iter }
    ret 26usize
}

// rescale(x, binary.inputs) of arm: x of n values (NaN for NA, left NaN), a factor given by its level codes (dense rank of the codes is as.numeric(factor(x)), minus one for two levels);
// mode 0 "center", 1 "0/1", 2 "-0.5,0.5", 3 "full" for a two-valued input, anything else (x - mean) / (2 sd)
fn rescale_gen(a: *mem.Arena, x: []const f64, n: usize, mode: usize, is_factor: bool, out: []f64) -> err {
    let (v, e1) = mem.alloc[f64](a, n)
    let (obs, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        v[i] = x[i]
        i += 1usize
    }
    if is_factor {
        var levels = 0usize
        i = 0usize
        while i < n {
            if x[i] == x[i] {
                var rank = 1.0f64
                var j = 0usize
                while j < n {
                    if x[j] == x[j] && x[j] < x[i] {
                        // count each distinct smaller value once
                        var first = true
                        var q = 0usize
                        while q < j {
                            if x[q] == x[j] { first = false }
                            q += 1usize
                        }
                        if first { rank += 1.0f64 }
                    }
                    j += 1usize
                }
                v[i] = rank
            }
            i += 1usize
        }
        var top = 0.0f64
        i = 0usize
        while i < n {
            if v[i] == v[i] && v[i] > top { top = v[i] }
            i += 1usize
        }
        levels = usize(top)
        if levels == 2usize {
            i = 0usize
            while i < n {
                v[i] = v[i] - 1.0f64
                i += 1usize
            }
        }
    }
    var m = 0usize
    var lo = 1.0e308f64
    var hi = 0.0f64 - 1.0e308f64
    i = 0usize
    while i < n {
        if v[i] == v[i] {
            obs[m] = v[i]
            m += 1usize
            if v[i] < lo { lo = v[i] }
            if v[i] > hi { hi = v[i] }
        }
        i += 1usize
    }
    var uniq = 0usize
    i = 0usize
    while i < m && uniq < 3usize {
        var seen = false
        var j = 0usize
        while j < i {
            if obs[j] == obs[i] { seen = true }
            j += 1usize
        }
        if !seen { uniq += 1usize }
        i += 1usize
    }
    let mean = ld.mean_ld(obs[0usize..m])
    let sd = math.sqrt[f64](ld.var_ld(obs[0usize..m]))
    i = 0usize
    while i < n {
        var r = (v[i] - mean) / (2.0f64 * sd)
        if uniq == 2usize {
            if mode == 0usize { r = v[i] - mean }
            if mode == 1usize { r = (v[i] - lo) / (hi - lo) }
            if mode == 2usize { r = v[i] - 0.5f64 }
        }
        out[i] = r
        i += 1usize
    }
    ret ok
}

// standardize(lm(y ~ ...)) or standardize(glm(y ~ ..., family)): `nv` predictors, column c of x (n by nv row-major) numeric (kinds[c] 0) or a factor given by level codes (1), the response
// first rescaled when std_y; a predictor not in `unchanged` (flag 1) with two distinct values is rescaled by `mode`, a numeric one with more by (x - mean) / (2 sd), a factor with more than two levels
// is left as it is and enters the model as treatment-contrast dummies. fam is 255 for lm, else the glm family with its link. out receives the coefficients (intercept first); answers their number
// (0 on failure)
fn standardize_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, nv: usize, kinds: []const f64, unchanged: []const f64, std_y: bool, mode: usize, fam: usize, link: usize, out: []f64) -> usize {
    // the width of every predictor in the design
    var width = 1usize
    var c = 0usize
    let (cols, e1) = mem.alloc[usize](a, nv)
    let (xr, e2) = mem.alloc[f64](a, n)
    let (xs, e3) = mem.alloc[f64](a, n)
    let (yy, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    var tr = 0usize
    while c < nv {
        var i = 0usize
        var uniq = 0usize
        while i < n {
            xr[i] = x[i * nv + c]
            i += 1usize
        }
        i = 0usize
        while i < n {
            if xr[i] == xr[i] {
                var seen = false
                var j = 0usize
                while j < i {
                    if xr[j] == xr[i] { seen = true }
                    j += 1usize
                }
                if !seen { uniq += 1usize }
            }
            i += 1usize
        }
        cols[c] = 1usize
        if kinds[c] == 1.0f64 && (unchanged[c] == 1.0f64 || uniq > 2usize) {
            cols[c] = uniq - 1usize
        }
        if uniq == 1usize && kinds[c] == 1.0f64 { ret 0usize }
        width += cols[c]
        c += 1usize
    }
    let (d, e5) = mem.alloc[f64](a, n * width)
    if e5 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        d[i * width] = 1.0f64
        i += 1usize
    }
    var at = 1usize
    c = 0usize
    while c < nv {
        i = 0usize
        var uniq = 0usize
        while i < n {
            xr[i] = x[i * nv + c]
            i += 1usize
        }
        i = 0usize
        while i < n {
            if xr[i] == xr[i] {
                var seen = false
                var j = 0usize
                while j < i {
                    if xr[j] == xr[i] { seen = true }
                    j += 1usize
                }
                if !seen { uniq += 1usize }
            }
            i += 1usize
        }
        let isf = kinds[c] == 1.0f64
        let change = unchanged[c] != 1.0f64 && (uniq == 2usize || (uniq > 2usize && !isf))
        if change {
            if rescale_gen(a, xr, n, mode, isf, xs) != ok { ret 0usize }
            i = 0usize
            while i < n {
                d[i * width + at] = xs[i]
                i += 1usize
            }
            at += 1usize
        } else if isf {
            // treatment contrasts: an indicator for every level but the first, levels by the rank of the codes
            var l = 1usize
            while l < uniq {
                i = 0usize
                while i < n {
                    var rank = 0usize
                    var j = 0usize
                    while j < n {
                        if xr[j] < xr[i] {
                            var first = true
                            var q = 0usize
                            while q < j {
                                if xr[q] == xr[j] { first = false }
                                q += 1usize
                            }
                            if first { rank += 1usize }
                        }
                        j += 1usize
                    }
                    d[i * width + at] = 0.0f64
                    if rank == l { d[i * width + at] = 1.0f64 }
                    i += 1usize
                }
                at += 1usize
                l += 1usize
            }
        } else {
            i = 0usize
            while i < n {
                d[i * width + at] = xr[i]
                i += 1usize
            }
            at += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < n {
        yy[i] = y[i]
        i += 1usize
    }
    if std_y {
        if rescale_gen(a, y, n, mode, false, yy) != ok { ret 0usize }
    }
    let nofs: []const f64 = y[0usize..0usize]
    if fam == 255usize {
        let (res, e6) = mem.alloc[f64](a, n)
        let (cv, e7) = mem.alloc[f64](a, width * width)
        if e6 != ok || e7 != ok { ret 0usize }
        let (rss, e) = ar.lm_summary(a, d, yy, n, width, out, cv, res)
        let _ = rss
        if e != ok { ret 0usize }
        ret width
    }
    let (cv, e8) = mem.alloc[f64](a, width * width)
    let (inf, e9) = mem.alloc[f64](a, 5usize)
    if e8 != ok || e9 != ok { ret 0usize }
    let it = glm_fit_gen(a, d, yy, n, width, fam, link, nofs, nofs, true, out, cv, inf)
    if it == 0usize { ret 0usize }
    ret width
}

// V.beta of arm's sim for a glm: corr * sd_i * sd_j from summary.glm (cu the unscaled covariance, disp the dispersion), row-major and not symmetrized
fn vbeta_from(cu: []const f64, disp: f64, k: usize, vm: []f64) {
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            let si = math.sqrt[f64](disp * cu[i * k + i])
            let sj = math.sqrt[f64](disp * cu[j * k + j])
            let di = math.sqrt[f64](cu[i * k + i])
            let dj = math.sqrt[f64](cu[j * k + j])
            vm[i * k + j] = ((cu[i * k + j] / (di * dj)) * si) * sj
            j += 1usize
        }
        i += 1usize
    }
}

// the draws of mvrnorm(nsims, bhat, V): eigen() reads the lower triangle of R's matrix and dsyevr_all the lower triangle of the transposed one, so it gets the transpose
fn sim_draws(a: *mem.Arena, g: *rng.Rng, vm: []const f64, bhat: []const f64, k: usize, nsims: usize, beta: []f64) -> err {
    let (vt, e) = mem.alloc[f64](a, k * k)
    if e != ok { ret e }
    var i = 0usize
    while i < k * k {
        vt[(i % k) * k + i / k] = vm[i]
        i += 1usize
    }
    ret ms.mvrnorm(a, g, nsims, k, bhat, vt, beta)
}

// arm::sim for a glm of any family and link: the coefficients are mvrnorm(nsims, beta.hat, V.beta) from summary.glm's covariance and dispersion, sigma = sqrt(dispersion) in every draw
// (n.sims of them). bhat gets the coefficients, beta the draws (nsims by k row-major), sigma the nsims values
fn sim_glm_gen(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, k: usize, fam: usize, link: usize, wts: []const f64, off: []const f64, nsims: usize, bhat: []f64, beta: []f64, sigma: []f64) -> err {
    let (cu, e1) = mem.alloc[f64](a, k * k)
    let (vm, e2) = mem.alloc[f64](a, k * k)
    let (info, e3) = mem.alloc[f64](a, 5usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let it = glm_fit_gen(a, x, y, n, k, fam, link, wts, off, true, bhat, cu, info)
    if it == 0usize { ret mem.Full }
    vbeta_from(cu, info[0usize], k, vm)
    var s = 0usize
    while s < nsims {
        sigma[s] = math.sqrt[f64](info[0usize])
        s += 1usize
    }
    ret sim_draws(a, g, vm, bhat, k, nsims, beta)
}

// sim() on a bayesglm fit: the same, with the covariance of the last augmented least squares fit and the dispersion bayesglm keeps
fn sim_bayesglm(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, k: usize, fam: usize, link: usize, wts: []const f64, off: []const f64, prior_mean: []const f64, prior_df: []const f64, prior_scale: []const f64, scaled: bool, nsims: usize, bhat: []f64, beta: []f64, sigma: []f64) -> err {
    let (cu, e1) = mem.alloc[f64](a, k * k)
    let (vm, e2) = mem.alloc[f64](a, k * k)
    let (info, e3) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let it = bayesglm_gen(a, x, y, n, k, fam, link, wts, off, prior_mean, prior_df, prior_scale, scaled, true, bhat, info, cu)
    if it == 0usize { ret mem.Full }
    vbeta_from(cu, info[0usize], k, vm)
    var s = 0usize
    while s < nsims {
        sigma[s] = math.sqrt[f64](info[0usize])
        s += 1usize
    }
    ret sim_draws(a, g, vm, bhat, k, nsims, beta)
}

// display(glm) and sigma.hat for any family and link (default prior weights and offset empty): out = n, k, deviance, null.deviance, dispersion, sigma.hat (NaN unless gaussian), then coef.est,
// coef.se, z or t value and p value (k each); the families that estimate the dispersion use t values on the residual degrees of freedom
fn display_glm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, fam: usize, link: usize, wts: []const f64, off: []const f64, out: []f64) -> err {
    let (beta, e1) = mem.alloc[f64](a, k)
    let (cu, e2) = mem.alloc[f64](a, k * k)
    let (info, e3) = mem.alloc[f64](a, 5usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let it = glm_fit_gen(a, x, y, n, k, fam, link, wts, off, true, beta, cu, info)
    if it == 0usize { ret mem.Full }
    var nok = 0usize
    var i = 0usize
    while i < n {
        if wts.len == n { if wts[i] != 0.0f64 { nok += 1usize } } else { nok += 1usize }
        i += 1usize
    }
    display_fill(cu, beta, info[0usize], info[1usize], info[2usize], f64(nok), f64(nok - k), k, fam, out)
    ret ok
}

// display(bayesglm): the same quantities from the bayesglm fit (covariance of the last augmented fit, bayesglm's dispersion, normal p values)
fn display_bayesglm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, fam: usize, link: usize, wts: []const f64, off: []const f64, prior_mean: []const f64, prior_df: []const f64, prior_scale: []const f64, scaled: bool, out: []f64) -> err {
    let (beta, e1) = mem.alloc[f64](a, k)
    let (cu, e2) = mem.alloc[f64](a, k * k)
    let (info, e3) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let it = bayesglm_gen(a, x, y, n, k, fam, link, wts, off, prior_mean, prior_df, prior_scale, scaled, true, beta, info, cu)
    if it == 0usize { ret mem.Full }
    var nok = 0usize
    var i = 0usize
    while i < n {
        if wts.len == n { if wts[i] != 0.0f64 { nok += 1usize } } else { nok += 1usize }
        i += 1usize
    }
    // bayesglm passes its own dispersion to summary, so the values are z values with normal p values for every family
    display_fill(cu, beta, info[0usize], info[1usize], info[2usize], f64(nok), 0.0f64, k, 1usize, out)
    var j = 0usize
    while j < k {
        out[6usize + k + j] = math.sqrt[f64](info[0usize] * cu[j * k + j])
        out[6usize + 2usize * k + j] = beta[j] / out[6usize + k + j]
        out[6usize + 3usize * k + j] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](out[6usize + 2usize * k + j]), 0.0f64, 1.0f64, true, false)
        j += 1usize
    }
    out[4usize] = info[0usize]
    out[5usize] = nan_f()
    if fam == 0usize { out[5usize] = math.sqrt[f64](info[0usize]) }
    ret ok
}

fn nan_f() -> f64 { ret 0.0f64 / 0.0f64 }

fn display_fill(cu: []const f64, beta: []const f64, disp: f64, dev: f64, nulldev: f64, nobs: f64, rdf: f64, k: usize, fam: usize, out: []f64) {
    out[0usize] = nobs
    out[1usize] = f64(k)
    out[2usize] = dev
    out[3usize] = nulldev
    out[4usize] = disp
    out[5usize] = nan_f()
    if fam == 0usize { out[5usize] = math.sqrt[f64](disp) }
    var j = 0usize
    while j < k {
        let se = math.sqrt[f64](disp * cu[j * k + j])
        let t = beta[j] / se
        out[6usize + j] = beta[j]
        out[6usize + k + j] = se
        out[6usize + 2usize * k + j] = t
        if fam == 1usize || fam == 2usize {
            out[6usize + 3usize * k + j] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](t), 0.0f64, 1.0f64, true, false)
        } else {
            out[6usize + 3usize * k + j] = 2.0f64 * nb.pt(0.0f64 - math.abs[f64](t), nobs - f64(k), true, false)
        }
        j += 1usize
    }
    let _ = rdf
}

// R's tanpi for a double in (0, 0.5], then qcauchy(p) of the standard Cauchy (lower tail, no log)
fn qcauchy_r(p0: f64) -> f64 {
    var p = p0
    var lower = true
    if p > 0.5f64 {
        if p == 1.0f64 { ret math.inf64() }
        p = 1.0f64 - p
        lower = false
    }
    if p == 0.5f64 { ret 0.0f64 }
    if p == 0.0f64 {
        if lower { ret 0.0f64 - math.inf64() }
        ret math.inf64()
    }
    var t = 1.0f64
    if p != 0.25f64 { t = tn.tan_c(3.141592653589793238462643383280f64 * p) }
    if lower { ret 0.0f64 - 1.0f64 / t }
    ret 1.0f64 / t
}

// qnorm(p) of the standard normal, lower tail, no log, p in (0, 1): AS 241 as R codes it with the correctly rounded log
fn qnorm_r(p: f64) -> f64 {
    if p <= 0.0f64 || p >= 1.0f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }
    let q = p - 0.5f64
    var val = 0.0f64
    if math.abs[f64](q) <= 0.425f64 {
        let r = 0.180625f64 - q * q
        val = q * (((((((r * 2509.0809287301226727f64 + 33430.575583588128105f64) * r + 67265.770927008700853f64) * r + 45921.953931549871457f64) * r + 13731.693765509461125f64) * r + 1971.5909503065514427f64) * r + 133.14166789178437745f64) * r + 3.387132872796366608f64) / (((((((r * 5226.495278852854561f64 + 28729.085735721942674f64) * r + 39307.89580009271061f64) * r + 21213.794301586595867f64) * r + 5394.1960214247511077f64) * r + 687.1870074920579083f64) * r + 42.313330701600911252f64) * r + 1.0f64)
        ret val
    }
    var lp = 0.0f64
    if q > 0.0f64 { lp = xe.log_r(0.5f64 - p + 0.5f64) } else { lp = xe.log_r(p) }
    var r = math.sqrt[f64](0.0f64 - lp)
    if r <= 5.0f64 {
        r = r - 1.6f64
        val = (((((((r * 7.7454501427834140764e-4f64 + 0.0227238449892691845833f64) * r + 0.24178072517745061177f64) * r + 1.27045825245236838258f64) * r + 3.64784832476320460504f64) * r + 5.7694972214606914055f64) * r + 4.6303378461565452959f64) * r + 1.42343711074968357734f64) / (((((((r * 1.05075007164441684324e-9f64 + 5.475938084995344946e-4f64) * r + 0.0151986665636164571966f64) * r + 0.14810397642748007459f64) * r + 0.68976733498510000455f64) * r + 1.6763848301838038494f64) * r + 2.05319162663775882187f64) * r + 1.0f64)
    } else if r <= 27.0f64 {
        r = r - 5.0f64
        val = (((((((r * 2.01033439929228813265e-7f64 + 2.71155556874348757815e-5f64) * r + 0.0012426609473880784386f64) * r + 0.026532189526576123093f64) * r + 0.29656057182850489123f64) * r + 1.7848265399172913358f64) * r + 5.4637849111641143699f64) * r + 6.6579046435011037772f64) / (((((((r * 2.04426310338993978564e-15f64 + 1.4215117583164458887e-7f64) * r + 1.8463183175100546818e-5f64) * r + 7.868691311456132591e-4f64) * r + 0.0148753612908506148525f64) * r + 0.13692988092273580531f64) * r + 0.59983220655588793769f64) * r + 1.0f64)
    } else {
        ret dist.qnorm(p, 0.0f64, 1.0f64, true, false)
    }
    if q < 0.0f64 { val = 0.0f64 - val }
    ret val
}

// the correctly rounded library functions the fits use, exported for the oracle to check against R
fn exp_cr(x: f64) -> f64 { ret xe.exp_r(x) }
fn log_cr(x: f64) -> f64 { ret xe.log_r(x) }
fn pnorm_cr(x: f64) -> f64 { ret an.pnorm_cr(x) }
fn dnorm_cr(x: f64) -> f64 { ret an.dnorm_cr(x) }
