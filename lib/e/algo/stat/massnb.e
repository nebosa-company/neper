// R MASS glm.nb: stats::glm.fit (the IRLS with its step-halving) for the Poisson and negative binomial families under
// the log, sqrt and identity links, theta.ml, theta.mm, and the alternating glm.nb loop. x is n by p, column-major.

use e.algo.linalg.decomp as decomp
use e.algo.stat as sx
use e.algo.stat.mass as ms
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

error BadInput
error NoStart
error StepFailed

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

// link 0 log, 1 sqrt, 2 identity, 3 logit, 4 probit, 5 cauchit (the last three with the binomial family 2)
fn linkfun(link: usize, mu: f64) -> f64 {
    if link == 0usize { ret math.log[f64](mu) }
    if link == 1usize { ret math.sqrt[f64](mu) }
    if link == 3usize { ret math.log[f64](mu / (1.0f64 - mu)) }
    if link == 4usize { ret dist.qnorm(mu, 0.0f64, 1.0f64, true, false) }
    if link == 5usize { ret dist.qcauchy(mu, 0.0f64, 1.0f64, true, false) }
    ret mu
}

fn linkinv(link: usize, eta: f64) -> f64 {
    if link == 0usize {
        let v = math.exp[f64](eta)
        if v < eps() { ret eps() }
        ret v
    }
    if link == 1usize { ret eta * eta }
    if link == 3usize {
        var t = math.exp[f64](eta)
        if eta < -30.0f64 { t = eps() }
        if eta > 30.0f64 { t = 1.0f64 / eps() }
        ret t / (1.0f64 + t)
    }
    if link == 4usize || link == 5usize {
        var th = 0.0f64 - dist.qnorm(eps(), 0.0f64, 1.0f64, true, false)
        if link == 5usize { th = 0.0f64 - dist.qcauchy(eps(), 0.0f64, 1.0f64, true, false) }
        var e = eta
        if e < 0.0f64 - th { e = 0.0f64 - th }
        if e > th { e = th }
        if link == 4usize { ret dist.pnorm(e, 0.0f64, 1.0f64, true, false) }
        ret dist.pcauchy(e, 0.0f64, 1.0f64, true, false)
    }
    ret eta
}

fn mu_eta(link: usize, eta: f64) -> f64 {
    if link == 0usize {
        let v = math.exp[f64](eta)
        if v < eps() { ret eps() }
        ret v
    }
    if link == 1usize { ret 2.0f64 * eta }
    if link == 3usize {
        if eta > 30.0f64 || eta < -30.0f64 { ret eps() }
        let oe = 1.0f64 + math.exp[f64](eta)
        ret math.exp[f64](eta) / (oe * oe)
    }
    if link == 4usize || link == 5usize {
        var d = dist.dnorm(eta, 0.0f64, 1.0f64, false)
        if link == 5usize { d = dist.dcauchy(eta, 0.0f64, 1.0f64, false) }
        if d < eps() { ret eps() }
        ret d
    }
    ret 1.0f64
}

// family 0 Poisson, 1 negative binomial (theta)
fn variance(fam: usize, theta: f64, mu: f64) -> f64 {
    if fam == 0usize { ret mu }
    if fam == 2usize { ret mu * (1.0f64 - mu) }
    ret ms.nb_variance(mu, theta)
}

fn dev_resid(fam: usize, theta: f64, y: f64, mu: f64, wt: f64) -> f64 {
    if fam == 1usize { ret ms.nb_dev_resid(y, mu, wt, theta) }
    if fam == 2usize {
        var t1 = 0.0f64
        if y != 0.0f64 { t1 = y * math.log[f64](y / mu) }
        var t2 = 0.0f64
        if 1.0f64 - y != 0.0f64 { t2 = (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
        ret 2.0f64 * wt * (t1 + t2)
    }
    var r = mu * wt
    if y > 0.0f64 { r = wt * y * math.log[f64](y / mu) - (y - mu) }
    ret 2.0f64 * r
}

type Glm = struct { coef: []f64, eta: []f64, mu: []f64, dev: f64, iter: usize, conv: bool, rank: usize, dfres: f64, nulldev: f64 }

fn valid(fam: usize, link: usize, eta: []const f64, mu: []const f64) -> bool {
    var i = 0usize
    while i < eta.len {
        if link == 1usize && (!(eta[i] - eta[i] == 0.0f64) || !(eta[i] > 0.0f64)) { ret false }
        if fam != 1usize && !(mu[i] - mu[i] == 0.0f64) { ret false }
        if !(mu[i] > 0.0f64) { ret false }
        if fam == 2usize && !(mu[i] < 1.0f64) { ret false }
        i += 1usize
    }
    ret true
}

fn total_dev(fam: usize, theta: f64, y: []const f64, mu: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        s += dev_resid(fam, theta, y[i], mu[i], w[i])
        i += 1usize
    }
    ret s
}

// glm.fit(x, y, weights, etastart, offset, family, control = list(epsilon, maxit), intercept). etastart is read when has_eta.
fn glm_fit(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, offset: []const f64, has_eta: bool, etastart: []const f64, fam: usize, theta: f64, link: usize, epsilon: f64, maxit: usize, intercept: bool) -> (Glm, err) {
    var out: Glm = zero
    let (eta, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (start, e3) = mem.alloc[f64](a, p)
    let (coefold, e4) = mem.alloc[f64](a, p)
    let (xw, e5) = mem.alloc[f64](a, n * p)
    let (z, e6) = mem.alloc[f64](a, n)
    let (wv, e7) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (out, mem.Full) }
    var i = 0usize
    while i < n {
        if has_eta {
            eta[i] = etastart[i]
        } else {
            var ms0 = 0.0f64
            if fam == 2usize { ms0 = (w[i] * y[i] + 0.5f64) / (w[i] + 1.0f64) } else if fam == 0usize { ms0 = y[i] + 0.1f64 } else {
                ms0 = y[i]
                if y[i] == 0.0f64 { ms0 = y[i] + 1.0f64 / 6.0f64 }
            }
            eta[i] = linkfun(link, ms0)
        }
        mu[i] = linkinv(link, eta[i])
        i += 1usize
    }
    var devold = total_dev(fam, theta, y, mu, w)
    var dev = devold
    var have_old = false
    var conv = false
    var rank = p
    var iter = 1usize
    while iter <= maxit && !conv {
        var m = 0usize
        i = 0usize
        while i < n {
            let me = mu_eta(link, eta[i])
            if w[i] > 0.0f64 && me != 0.0f64 {
                z[m] = (eta[i] - offset[i]) + (y[i] - mu[i]) / me
                wv[m] = math.sqrt[f64]((w[i] * me * me) / variance(fam, theta, mu[i]))
                var c = 0usize
                while c < p {
                    xw[m + n * c] = x[i + n * c] * wv[m]
                    c += 1usize
                }
                m += 1usize
            }
            i += 1usize
        }
        let (xc, e8) = mem.alloc[f64](a, m * p)
        let (zc, e9) = mem.alloc[f64](a, m)
        if e8 != ok || e9 != ok { ret (out, mem.Full) }
        var c = 0usize
        while c < p {
            var r = 0usize
            while r < m {
                xc[r + m * c] = xw[r + n * c]
                r += 1usize
            }
            c += 1usize
        }
        i = 0usize
        while i < m {
            zc[i] = z[i] * wv[i]
            i += 1usize
        }
        var tol = 1.0e-7f64
        if epsilon / 1000.0f64 < tol { tol = epsilon / 1000.0f64 }
        let (f, fe) = decomp.lm_fit(a, xc, m, p, zc, tol)
        if fe != ok { ret (out, fe) }
        rank = f.rank
        c = 0usize
        while c < p {
            start[c] = f.coef[c]
            c += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            c = 0usize
            while c < p {
                s += x[i + n * c] * start[c]
                c += 1usize
            }
            eta[i] = s + offset[i]
            mu[i] = linkinv(link, eta[i])
            i += 1usize
        }
        dev = total_dev(fam, theta, y, mu, w)
        if !(dev - dev == 0.0f64) {
            if !have_old { ret (out, NoStart) }
            var ii = 1usize
            while !(dev - dev == 0.0f64) {
                if ii > maxit { ret (out, StepFailed) }
                ii += 1usize
                c = 0usize
                while c < p {
                    start[c] = (start[c] + coefold[c]) / 2.0f64
                    c += 1usize
                }
                i = 0usize
                while i < n {
                    var s = 0.0f64
                    c = 0usize
                    while c < p {
                        s += x[i + n * c] * start[c]
                        c += 1usize
                    }
                    eta[i] = s + offset[i]
                    mu[i] = linkinv(link, eta[i])
                    i += 1usize
                }
                dev = total_dev(fam, theta, y, mu, w)
            }
        }
        if !valid(fam, link, eta, mu) {
            if !have_old { ret (out, NoStart) }
            var ii = 1usize
            while !valid(fam, link, eta, mu) {
                if ii > maxit { ret (out, StepFailed) }
                ii += 1usize
                c = 0usize
                while c < p {
                    start[c] = (start[c] + coefold[c]) / 2.0f64
                    c += 1usize
                }
                i = 0usize
                while i < n {
                    var s = 0.0f64
                    c = 0usize
                    while c < p {
                        s += x[i + n * c] * start[c]
                        c += 1usize
                    }
                    eta[i] = s + offset[i]
                    mu[i] = linkinv(link, eta[i])
                    i += 1usize
                }
            }
            dev = total_dev(fam, theta, y, mu, w)
        }
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < epsilon {
            conv = true
        } else {
            devold = dev
            c = 0usize
            while c < p {
                coefold[c] = start[c]
                c += 1usize
            }
            have_old = true
            iter += 1usize
        }
    }
    // the null deviance: the weighted mean (intercept) or linkinv(offset)
    var nulldev = 0.0f64
    var sw = 0.0f64
    var swy = 0.0f64
    i = 0usize
    while i < n {
        sw += w[i]
        swy += w[i] * y[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var wm = linkinv(link, offset[i])
        if intercept { wm = swy / sw }
        nulldev += dev_resid(fam, theta, y[i], wm, w[i])
        i += 1usize
    }
    var nok = 0usize
    i = 0usize
    while i < n {
        if w[i] != 0.0f64 { nok += 1usize }
        i += 1usize
    }
    out = Glm { coef: start, eta: eta, mu: mu, dev: dev, iter: iter, conv: conv, rank: rank, dfres: f64(nok - rank), nulldev: nulldev }
    ret (out, ok)
}

// theta.ml(y, mu, n, weights, limit, eps): returns (theta, SE, warn) with warn 0 none, 1 truncated at zero, 2 iteration limit
fn theta_ml(y: []const f64, mu: []const f64, n: f64, w: []const f64, limit: usize, epsv: f64) -> (f64, f64, usize) {
    var s0 = 0.0f64
    var i = 0usize
    while i < y.len {
        s0 += w[i] * ((y[i] / mu[i] - 1.0f64) * (y[i] / mu[i] - 1.0f64))
        i += 1usize
    }
    var t0 = n / s0
    var it = 0usize
    var del = 1.0f64
    var inf = 0.0f64
    var go = true
    while go {
        it += 1usize
        if !(it < limit && math.abs[f64](del) > epsv) {
            go = false
        } else {
            t0 = math.abs[f64](t0)
            var sc = 0.0f64
            var inn = 0.0f64
            i = 0usize
            while i < y.len {
                sc += w[i] * (sx.digamma(t0 + y[i]) - sx.digamma(t0) + math.log[f64](t0) + 1.0f64 - math.log[f64](t0 + mu[i]) - (y[i] + t0) / (mu[i] + t0))
                inn += w[i] * (0.0f64 - sx.trigamma(t0 + y[i]) + sx.trigamma(t0) - 1.0f64 / t0 + 2.0f64 / (mu[i] + t0) - (y[i] + t0) / ((mu[i] + t0) * (mu[i] + t0)))
                i += 1usize
            }
            inf = inn
            del = sc / inf
            t0 = t0 + del
        }
    }
    var warn = 0usize
    if t0 < 0.0f64 {
        t0 = 0.0f64
        warn = 1usize
    }
    if it == limit { warn = 2usize }
    ret (t0, math.sqrt[f64](1.0f64 / inf), warn)
}

fn theta_mm(y: []const f64, mu: []const f64, dfr: f64, w: []const f64, limit: usize, epsv: f64) -> f64 {
    var n = 0.0f64
    var s0 = 0.0f64
    var i = 0usize
    while i < y.len {
        n += w[i]
        s0 += w[i] * ((y[i] / mu[i] - 1.0f64) * (y[i] / mu[i] - 1.0f64))
        i += 1usize
    }
    var t0 = n / s0
    var it = 0usize
    var del = 1.0f64
    var go = true
    while go {
        it += 1usize
        if !(it < limit && math.abs[f64](del) > epsv) {
            go = false
        } else {
            t0 = math.abs[f64](t0)
            var num = 0.0f64
            var den = 0.0f64
            i = 0usize
            while i < y.len {
                num += w[i] * ((y[i] - mu[i]) * (y[i] - mu[i]) / (mu[i] + mu[i] * mu[i] / t0))
                den += w[i] * (y[i] - mu[i]) * (y[i] - mu[i]) / ((mu[i] + t0) * (mu[i] + t0))
                i += 1usize
            }
            del = (num - dfr) / den
            t0 = t0 - del
        }
    }
    if t0 < 0.0f64 { t0 = 0.0f64 }
    ret t0
}

fn nb_loglik(th: f64, mu: []const f64, y: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        var yz = 0.0f64
        if y[i] == 0.0f64 { yz = 1.0f64 }
        s += w[i] * (nm.lgammafn(th + y[i]) - nm.lgammafn(th) - nm.lgammafn(y[i] + 1.0f64) + th * math.log[f64](th) + y[i] * math.log[f64](mu[i] + yz) - (th + y[i]) * math.log[f64](th + mu[i]))
        i += 1usize
    }
    ret s
}

type Nb = struct { fit: Glm, theta: f64, se: f64, twologlik: f64, aic: f64, alternations: usize, warn: usize, nulldev: f64 }

// glm.nb(y ~ x, weights, offset, link, init.theta (NaN for the Poisson start), control = glm.control(maxit, epsilon))
fn glm_nb(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, offset: []const f64, link: usize, init_theta: f64, maxit: usize, epsilon: f64, intercept: bool, has_offset: bool) -> (Nb, err) {
    var out: Nb = zero
    var f0 = 0usize
    var th0 = 1.0f64
    if init_theta == init_theta {
        f0 = 1usize
        th0 = init_theta
    }
    let (none, ee) = mem.alloc[f64](a, n)
    if ee != ok { ret (out, mem.Full) }
    let (fit0, e0) = glm_fit(a, x, n, p, y, w, offset, false, none, f0, th0, link, epsilon, maxit, intercept)
    if e0 != ok { ret (out, e0) }
    var fit = fit0
    var mu = fit.mu
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += w[i]
        i += 1usize
    }
    let (th1, se1, warn1) = theta_ml(y, mu, sw, w, maxit, 1.220703125e-4f64)
    var th = th1
    var se = se1
    var warn = warn1
    var df1 = fit.dfres
    if df1 < 1.0f64 { df1 = 1.0f64 }
    let d1 = math.sqrt[f64](2.0f64 * df1)
    let d2 = 1.0f64
    var del = 1.0f64
    var lm = nb_loglik(th, mu, y, w)
    var lm0 = lm + 2.0f64 * d1
    var iter = 0usize
    var famtheta = th
    var go = true
    while go {
        iter += 1usize
        if !(iter <= maxit && (math.abs[f64](lm0 - lm) / d1 + math.abs[f64](del) / d2) > epsilon) {
            go = false
        } else {
            let (eta, e1) = mem.alloc[f64](a, n)
            if e1 != ok { ret (out, mem.Full) }
            i = 0usize
            while i < n {
                eta[i] = linkfun(link, mu[i])
                i += 1usize
            }
            let (nf, e2) = glm_fit(a, x, n, p, y, w, offset, true, eta, 1usize, famtheta, link, epsilon, maxit, intercept)
            if e2 != ok { ret (out, e2) }
            fit = nf
            let t0 = th
            let (tn, sen, wn) = theta_ml(y, mu, sw, w, maxit, 1.220703125e-4f64)
            th = tn
            se = sen
            warn = wn
            famtheta = th
            mu = fit.mu
            del = t0 - th
            lm0 = lm
            lm = nb_loglik(th, mu, y, w)
        }
    }
    var nulldev = fit.nulldev
    if iter > maxit { warn = 3usize }
    if has_offset && intercept {
        let (one, e3) = mem.alloc[f64](a, n)
        if e3 != ok { ret (out, mem.Full) }
        i = 0usize
        while i < n {
            one[i] = 1.0f64
            i += 1usize
        }
        let (nf, e4) = glm_fit(a, one, n, 1usize, y, w, offset, false, none, 1usize, famtheta, link, epsilon, maxit, true)
        if e4 != ok { ret (out, e4) }
        nulldev = nf.dev
    }
    let tl = 2.0f64 * lm
    out = Nb { fit: fit, theta: th, se: se, twologlik: tl, aic: 0.0f64 - tl + 2.0f64 * f64(fit.rank) + 2.0f64, alternations: iter, warn: warn, nulldev: nulldev }
    ret (out, ok)
}
