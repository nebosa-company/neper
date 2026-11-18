// R betareg: beta regression with a logit mean link and a constant precision (identity link): the maximum-likelihood coefficients, the
// precision and the log-likelihood. The likelihood is maximised by Nelder-Mead restarts on (beta, log phi), so the fit agrees with R to
// its optimiser tolerance, not bit for bit. Not here: variable dispersion, other links, bias correction and the standard errors.

use e.math
use e.math.nmath as nm
use e.math.dist as dst
use e.algo.stat.quantreg as qrb
use e.algo.stat.gslfns as gsl
use e.math.nmath_beta as nbb
use e.math.opt as opt
use e.mem

type Data = struct { x: []const f64, y: []const f64, n: usize, p: usize, link: usize }

fn expit(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

// the mean link inverse and link: 0 logit, 1 probit, 2 cloglog, 3 loglog, 4 cauchit
fn linkinv(t: f64, link: usize) -> f64 {
    if link == 0usize { ret expit(t) }
    if link == 1usize { ret dst.pnorm(t, 0.0f64, 1.0f64, true, false) }
    if link == 3usize { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - t)) }
    if link == 4usize { ret 0.5f64 + math.atan[f64](t) / 3.141592653589793f64 }
    // -expm1(-exp(t)) without cancellation for a small exp(t)
    let e = math.exp[f64](t)
    if e < 0.00001f64 { ret e - e * e / 2.0f64 + e * e * e / 6.0f64 }
    ret 1.0f64 - math.exp[f64](0.0f64 - e)
}

fn linkfun(m: f64, link: usize) -> f64 {
    if link == 0usize { ret math.log[f64](m / (1.0f64 - m)) }
    if link == 1usize { ret dst.qnorm(m, 0.0f64, 1.0f64, true, false) }
    if link == 3usize { ret 0.0f64 - math.log[f64](0.0f64 - math.log[f64](m)) }
    if link == 4usize { ret math.tan[f64](3.141592653589793f64 * (m - 0.5f64)) }
    ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - m))
}

fn loglik(d: *Data, a: []const f64) -> f64 {
    let phi = math.exp[f64](a[d.p])
    var s = 0.0f64
    var i = 0usize
    while i < d.n {
        var t = 0.0f64
        var j = 0usize
        while j < d.p {
            t += d.x[i * d.p + j] * a[j]
            j += 1usize
        }
        let mu = linkinv(t, d.link)
        let yi = d.y[i]
        s += nm.lgammafn(phi) - nm.lgammafn(mu * phi) - nm.lgammafn((1.0f64 - mu) * phi) + (mu * phi - 1.0f64) * math.log[f64](yi) + ((1.0f64 - mu) * phi - 1.0f64) * math.log[f64](1.0f64 - yi)
        i += 1usize
    }
    ret s
}

fn negll(d: *Data, a: []const f64) -> f64 {
    let v = loglik(d, a)
    if v != v { ret 1.0e30f64 }
    ret 0.0f64 - v
}

type Fit = struct { par: []f64, phi: f64, ll: f64 }

// x is n by p row-major with the intercept column; y in (0, 1)
fn fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize) -> (Fit, err) {
    let (f, e) = fit_link(a, x, y, n, p, 0usize)
    ret (f, e)
}

fn fit_link(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, link: usize) -> (Fit, err) {
    var d = Data { x: x, y: y, n: n, p: p, link: link }
    let q = p + 1usize
    let (par, e1) = mem.alloc[f64](a, q)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < q {
        par[i] = 0.0f64
        i += 1usize
    }
    // the starting values of the package: the least-squares fit of logit(y) and the precision from the residual variance
    let (z, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (zero, e2) }
    i = 0usize
    while i < n {
        z[i] = linkfun(y[i], link)
        i += 1usize
    }
    let (xtx, e3) = mem.alloc[f64](a, p * p)
    if e3 != ok { ret (zero, e3) }
    let (xty, e4) = mem.alloc[f64](a, p)
    if e4 != ok { ret (zero, e4) }
    i = 0usize
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
            xty[j] += x[i * p + j] * z[i]
            var k = 0usize
            while k < p {
                xtx[j * p + k] += x[i * p + j] * x[i * p + k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    // Gauss-Jordan solve of the normal equations into par[0..p]
    let (aug, e5) = mem.alloc[f64](a, p * (p + 1usize))
    if e5 != ok { ret (zero, e5) }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            aug[i * (p + 1usize) + j] = xtx[i * p + j]
            j += 1usize
        }
        aug[i * (p + 1usize) + p] = xty[i]
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var piv = c
        var k = c + 1usize
        while k < p {
            if math.abs[f64](aug[k * (p + 1usize) + c]) > math.abs[f64](aug[piv * (p + 1usize) + c]) { piv = k }
            k += 1usize
        }
        var j = 0usize
        while j <= p {
            let t = aug[c * (p + 1usize) + j]
            aug[c * (p + 1usize) + j] = aug[piv * (p + 1usize) + j]
            aug[piv * (p + 1usize) + j] = t
            j += 1usize
        }
        let dd = aug[c * (p + 1usize) + c]
        j = 0usize
        while j <= p {
            aug[c * (p + 1usize) + j] = aug[c * (p + 1usize) + j] / dd
            j += 1usize
        }
        k = 0usize
        while k < p {
            if k != c {
                let f = aug[k * (p + 1usize) + c]
                j = 0usize
                while j <= p {
                    aug[k * (p + 1usize) + j] -= f * aug[c * (p + 1usize) + j]
                    j += 1usize
                }
            }
            k += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < p {
        par[i] = aug[i * (p + 1usize) + p]
        i += 1usize
    }
    var rss = 0.0f64
    var sig = 0.0f64
    i = 0usize
    while i < n {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += x[i * p + j] * par[j]
            j += 1usize
        }
        let mu = linkinv(t, link)
        let r = y[i] - mu
        rss += r * r
        sig += mu * (1.0f64 - mu)
        i += 1usize
    }
    let sigma2 = rss / (f64(n) - f64(p)) / ((sig / f64(n)) * (sig / f64(n)))
    let phi0 = 1.0f64 / sigma2 - 1.0f64
    if phi0 > 0.0f64 { par[p] = math.log[f64](phi0) }
    let (scr, e6) = mem.alloc[f64](a, (q + 1usize) * (q + 1usize) + 4usize * q)
    if e6 != ok { ret (zero, e6) }
    var round = 0usize
    var last = 1.0e30f64
    var best = 1.0e30f64
    while round < 12usize {
        let (r, e7) = opt.nelder_mead[Data](&d, negll, par, 0.2f64, 1.0e-15f64, 4000u32, scr)
        if e7 != ok { ret (zero, e7) }
        best = r.value
        if math.abs[f64](last - r.value) < 1.0e-13f64 * (1.0f64 + math.abs[f64](r.value)) && round > 3usize { break }
        last = r.value
        round += 1usize
    }
    ret (Fit { par: par, phi: math.exp[f64](par[p]), ll: 0.0f64 - best }, ok)
}


// g'(mu) of the mean link at mu: 0 logit, 1 probit, 2 cloglog, 3 loglog, 4 cauchit (the inverse of g'(mu))
fn gprime(m: f64, link: usize) -> f64 {
    if link == 0usize { ret 1.0f64 / (m * (1.0f64 - m)) }
    if link == 1usize { ret 1.0f64 / dst.dnorm(dst.qnorm(m, 0.0f64, 1.0f64, true, false), 0.0f64, 1.0f64, false) }
    if link == 3usize { ret 1.0f64 / (m * (0.0f64 - math.log[f64](m))) }
    if link == 4usize {
        let tt = math.tan[f64](3.141592653589793f64 * (m - 0.5f64))
        ret 3.141592653589793f64 * (1.0f64 + tt * tt)
    }
    ret 0.0f64 - 1.0f64 / ((1.0f64 - m) * math.log[f64](1.0f64 - m))
}

// standard errors from the inverse of the Fisher information of Ferrari and Cribari-Neto, which betareg's vcov uses by default (phi on the identity link): K_bb = phi^2 X' W X with
// w = (psi'(mu phi) + psi'((1 - mu) phi)) / g'(mu)^2, K_bp = X' T c with c = phi (psi'(mu phi) mu - psi'((1 - mu) phi) (1 - mu)), T = 1 / g'(mu), K_pp = sum of
// psi'(mu phi) mu^2 + psi'((1 - mu) phi) (1 - mu)^2 - psi'(phi); se[0..p] the coefficients, se[p] phi; false when singular
fn fit_se(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, link: usize, f: *const Fit, se: []f64) -> bool {
    let q = p + 1usize
    let (kk, e1) = mem.alloc[f64](a, q * q)
    let (col, e2) = mem.alloc[f64](a, q)
    let (mat, e3) = mem.alloc[f64](a, q * q)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var i = 0usize
    while i < q * q {
        kk[i] = 0.0f64
        i += 1usize
    }
    let phi = f.phi
    i = 0usize
    while i < n {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += x[i * p + j] * f.par[j]
            j += 1usize
        }
        let mu = linkinv(t, link)
        // 1 - mu without cancellation for the cloglog link, whose upper tail is exp(-exp(t))
        var omu = 1.0f64 - mu
        var gp = gprime(mu, link)
        if link == 2usize {
            omu = math.exp[f64](0.0f64 - math.exp[f64](t))
            gp = 1.0f64 / (omu * math.exp[f64](t))
        }
        if link == 3usize {
            let xx = math.exp[f64](0.0f64 - t)
            if xx < 0.00001f64 { omu = xx - xx * xx / 2.0f64 + xx * xx * xx / 6.0f64 }
            gp = 1.0f64 / (mu * xx)
        }
        let t1 = gsl.psi_n(1usize, mu * phi)
        let t2 = gsl.psi_n(1usize, omu * phi)
        let w = (t1 + t2) / (gp * gp)
        let cc = phi * (t1 * mu - t2 * omu)
        let dd = t1 * mu * mu + t2 * omu * omu - gsl.psi_n(1usize, phi)
        j = 0usize
        while j < p {
            var k = 0usize
            while k < p {
                kk[j * q + k] += phi * phi * w * x[i * p + j] * x[i * p + k]
                k += 1usize
            }
            kk[j * q + p] += x[i * p + j] * cc / gp
            kk[p * q + j] += x[i * p + j] * cc / gp
            j += 1usize
        }
        kk[p * q + p] += dd
        i += 1usize
    }
    var c = 0usize
    while c < q {
        i = 0usize
        while i < q * q {
            mat[i] = kk[i]
            i += 1usize
        }
        i = 0usize
        while i < q {
            col[i] = 0.0f64
            i += 1usize
        }
        col[c] = 1.0f64
        if !qrb.solve_dense(mat, col, q) { ret false }
        se[c] = math.sqrt[f64](col[c])
        c += 1usize
    }
    ret true
}

// residuals(f, type) and predict(f, type) of observation i at the fitted (beta, phi): kind 0 response y - mu, 1 pearson, 2 deviance, 3 weighted, 4 sweighted, 5 quantile, 6 predict response (mu),
// 7 predict link (eta), 8 predict precision (phi), 9 predict variance mu (1 - mu) / (1 + phi)
fn fit_value(x: []const f64, y: []const f64, p: usize, link: usize, f: *const Fit, i: usize, kind: usize) -> f64 {
    var t = 0.0f64
    var j = 0usize
    while j < p {
        t += x[i * p + j] * f.par[j]
        j += 1usize
    }
    let mu = linkinv(t, link)
    let phi = f.phi
    let yi = y[i]
    if kind == 0usize { ret yi - mu }
    if kind == 6usize { ret mu }
    if kind == 7usize { ret t }
    if kind == 8usize { ret phi }
    let vr = mu * (1.0f64 - mu) / (1.0f64 + phi)
    if kind == 9usize { ret vr }
    if kind == 1usize { ret (yi - mu) / math.sqrt[f64](vr) }
    if kind == 2usize {
        let l1 = nm.lgammafn(phi) - nm.lgammafn(yi * phi) - nm.lgammafn((1.0f64 - yi) * phi) + (yi * phi - 1.0f64) * math.log[f64](yi) + ((1.0f64 - yi) * phi - 1.0f64) * math.log[f64](1.0f64 - yi)
        let l2 = nm.lgammafn(phi) - nm.lgammafn(mu * phi) - nm.lgammafn((1.0f64 - mu) * phi) + (mu * phi - 1.0f64) * math.log[f64](yi) + ((1.0f64 - mu) * phi - 1.0f64) * math.log[f64](1.0f64 - yi)
        var sg = 1.0f64
        if yi - mu < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        ret sg * math.sqrt[f64](2.0f64 * math.abs[f64](l1 - l2))
    }
    if kind == 5usize { ret dst.qnorm(nbb.pbeta(yi, mu * phi, (1.0f64 - mu) * phi, true, false), 0.0f64, 1.0f64, true, false) }
    let ystar = math.log[f64](yi / (1.0f64 - yi))
    let mustar = gsl.psi(mu * phi) - gsl.psi((1.0f64 - mu) * phi)
    let v = gsl.psi_n(1usize, mu * phi) + gsl.psi_n(1usize, (1.0f64 - mu) * phi)
    if kind == 3usize { ret (ystar - mustar) / math.sqrt[f64](phi * v) }
    ret (ystar - mustar) / math.sqrt[f64](v)
}
