// R GeneralizedHyperbolic hessians of the hyperbolic, NIG and GIG log-likelihoods: the exact formulas of hyperbHessian (parametrizations 1, 2 and 5), the numerical
// tsHessian of DistributionUtils for every parametrization (hyperbHessian, nigHessian, gigHessian), and the standard errors summary.* take from them.

use e.algo.stat.ghyp as gh
use e.algo.stat.ghypmore as gm
use e.algo.stat.gslfns as gs
use e.math
use e.mem

type HsC = struct { x: []const f64, fam: usize, set: usize }

fn hs_lambda(fam: usize) -> f64 {
    if fam == 1usize { ret 0.0f64 - 0.5f64 }
    ret 1.0f64
}

// the log-likelihood the hessian is taken of, in parametrization set (1 mu delta pi zeta, 2 mu delta alpha beta, 3 phi gamma, 4 xi chi, 5 log scale of delta and zeta)
fn hs_ll(c: *HsC, par: []const f64) -> f64 {
    var ab: [2]f64 = zero
    var delta = par[1usize]
    if c.set == 1usize { gm.hyperb_change_pars(1usize, 2usize, par[1usize], par[2usize], par[3usize], ab[0usize..2usize]) }
    if c.set == 2usize {
        ab[0usize] = par[2usize]
        ab[1usize] = par[3usize]
    }
    if c.set == 3usize { gm.hyperb_change_pars(3usize, 2usize, par[1usize], par[2usize], par[3usize], ab[0usize..2usize]) }
    if c.set == 4usize { gm.hyperb_change_pars(4usize, 2usize, par[1usize], par[2usize], par[3usize], ab[0usize..2usize]) }
    if c.set == 5usize {
        delta = math.exp[f64](par[1usize])
        gm.hyperb_change_pars(1usize, 2usize, delta, par[2usize], math.exp[f64](par[3usize]), ab[0usize..2usize])
    }
    let lam = hs_lambda(c.fam)
    var s = 0.0f64
    var cs = 0.0f64
    var i = 0usize
    while i < c.x.len {
        let v = math.log[f64](gh.dghyp(c.x[i], par[0usize], delta, ab[0usize], ab[1usize], lam))
        let t = s + v
        if math.abs[f64](s) >= math.abs[f64](v) { cs = cs + ((s - t) + v) } else { cs = cs + ((v - t) + s) }
        s = t
        i += 1usize
    }
    ret s + cs
}

// DistributionUtils::tsHessian(param, fun) for n parameters (at most 4): central second differences with the step eps^(1/3) max(|z|, 0.01)
fn ts_hessian[C: type](c: *C, f: fn(*C, []const f64) -> f64, param: []const f64, hess: []f64) {
    let n = param.len
    var h: [4]f64 = zero
    var gp: [4]f64 = zero
    var gmn: [4]f64 = zero
    var hp: [16]f64 = zero
    var hm: [16]f64 = zero
    var q: [4]f64 = zero
    let fx = f(c, param)
    let e3 = math.pow[f64](2.220446049250313e-16f64, 1.0f64 / 3.0f64)
    var i = 0usize
    while i < n {
        var m = math.abs[f64](param[i])
        if m < 0.01f64 { m = 0.01f64 }
        h[i] = e3 * m
        let ph = param[i] + h[i]
        h[i] = ph - param[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            q[k] = param[k]
            k += 1usize
        }
        q[i] = param[i] + h[i]
        gp[i] = f(c, q[0usize..n])
        q[i] = param[i] - h[i]
        gmn[i] = f(c, q[0usize..n])
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i
        while j < n {
            var k = 0usize
            while k < n {
                q[k] = param[k]
                k += 1usize
            }
            q[i] = q[i] + h[i]
            q[j] = q[j] + h[j]
            hp[i * 4usize + j] = f(c, q[0usize..n])
            hp[j * 4usize + i] = hp[i * 4usize + j]
            k = 0usize
            while k < n {
                q[k] = param[k]
                k += 1usize
            }
            q[i] = q[i] - h[i]
            q[j] = q[j] - h[j]
            hm[i * 4usize + j] = f(c, q[0usize..n])
            hm[j * 4usize + i] = hm[i * 4usize + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i
        while j < n {
            let hh = h[i] * h[j]
            let v = ((hp[i * 4usize + j] - gp[i] - gp[j] + fx + fx - gmn[i] - gmn[j] + hm[i * 4usize + j]) / hh) / 2.0f64
            hess[i * n + j] = v
            hess[j * n + i] = v
            j += 1usize
        }
        i += 1usize
    }
}

fn hyperb_ts_hessian(x: []const f64, fam: usize, set: usize, param: []const f64, hess: []f64) {
    var c: HsC = zero
    c.x = x
    c.fam = fam
    c.set = set
    ts_hessian[HsC](&c, hs_ll, param, hess)
}

// the GIG tsHessian (parametrization 1: log chi, log psi, lambda) of the log-likelihood
type GsC = struct { x: []const f64 }

fn gs_ll(c: *GsC, p: []const f64) -> f64 {
    var s = 0.0f64
    var cs = 0.0f64
    var i = 0usize
    while i < c.x.len {
        let xv = c.x[i]
        let v = p[2usize] / 2.0f64 * math.log[f64](math.exp[f64](p[1usize]) / math.exp[f64](p[0usize])) - math.log[f64](2.0f64 * gs.bessel_knu(math.abs[f64](p[2usize]), math.sqrt[f64](math.exp[f64](p[0usize]) * math.exp[f64](p[1usize])))) + (p[2usize] - 1.0f64) * math.log[f64](xv) - 0.5f64 * (math.exp[f64](p[0usize]) * (1.0f64 / xv) + math.exp[f64](p[1usize]) * xv)
        let t = s + v
        if math.abs[f64](s) >= math.abs[f64](v) { cs = cs + ((s - t) + v) } else { cs = cs + ((v - t) + s) }
        s = t
        i += 1usize
    }
    ret s + cs
}

fn gig_hessian(x: []const f64, param: []const f64, hess: []f64) {
    var c: GsC = zero
    c.x = x
    ts_hessian[GsC](&c, gs_ll, param, hess)
}

// ---- the exact hyperbolic hessian: sumX(x, mu, delta, r, k) = sum((mu - x)^r / (delta^2 + (x - mu)^2)^(k / 2))
fn sum_x(x: []const f64, mu: f64, delta: f64, r: f64, k: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.pow[f64](mu - x[i], r) / math.pow[f64](delta * delta + (x[i] - mu) * (x[i] - mu), k / 2.0f64)
        i += 1usize
    }
    ret s
}

fn hyperb_exact_hessian(x: []const f64, set: usize, param: []const f64, h: []f64) {
    let n = f64(x.len)
    var i = 0usize
    while i < 16usize {
        h[i] = 0.0f64
        i += 1usize
    }
    if set == 2usize {
        let mu = param[0usize]
        let delta = param[1usize]
        let alpha = param[2usize]
        let beta = param[3usize]
        let tau = delta * math.sqrt[f64](alpha * alpha - beta * beta)
        let br = gs.bessel_knu(0.0f64, tau) / gs.bessel_knu(1.0f64, tau)
        let a2b2 = alpha * alpha - beta * beta
        h[0usize] = 0.0f64 - alpha * delta * delta * sum_x(x, mu, delta, 0.0f64, 3.0f64)
        h[1usize] = alpha * delta * sum_x(x, mu, delta, 1.0f64, 3.0f64)
        h[4usize] = h[1usize]
        h[2usize] = 0.0f64 - sum_x(x, mu, delta, 1.0f64, 1.0f64)
        h[8usize] = h[2usize]
        h[3usize] = 0.0f64 - n
        h[12usize] = h[3usize]
        h[5usize] = n * (tau / (delta * delta) * br + a2b2 * (br * br - 1.0f64)) + alpha * delta * delta * sum_x(x, mu, delta, 0.0f64, 3.0f64) - alpha * sum_x(x, mu, delta, 0.0f64, 1.0f64)
        h[6usize] = 0.0f64 - n * delta * alpha + 2.0f64 * alpha * n * delta / tau * br + n * delta * alpha * br * br - delta * sum_x(x, mu, delta, 0.0f64, 1.0f64)
        h[9usize] = h[6usize]
        h[7usize] = n * (delta * beta - 2.0f64 * beta * delta / tau * br - beta * delta * br * br)
        h[13usize] = h[7usize]
        h[10usize] = (n * (0.0f64 - math.pow[f64](alpha, 6.0f64) * delta * delta + (0.0f64 - 1.0f64 + delta * delta * beta * beta) * math.pow[f64](alpha, 4.0f64) - 4.0f64 * alpha * alpha * beta * beta + math.pow[f64](beta, 4.0f64))) / (alpha * alpha * a2b2 * a2b2) + n * delta * delta / tau * br + n * delta * delta * alpha * alpha / a2b2 * br * br
        h[11usize] = n * beta * alpha * (4.0f64 + alpha * alpha * delta * delta - beta * beta * delta * delta) / (a2b2 * a2b2) - n * delta * delta * beta * alpha / a2b2 * br * br
        h[14usize] = h[11usize]
        h[15usize] = (0.0f64 - 2.0f64 * n * (alpha * alpha + beta * beta) - n * beta * beta * delta * delta * a2b2) / (a2b2 * a2b2) - n * delta * delta / tau * br + n * delta * delta * beta * beta / a2b2 * br * br
        ret
    }
    let mu = param[0usize]
    var delta = param[1usize]
    let pi_ = param[2usize]
    var zeta = param[3usize]
    if set == 5usize {
        delta = math.exp[f64](param[1usize])
        zeta = math.exp[f64](param[3usize])
    }
    let sq = math.sqrt[f64](1.0f64 + pi_ * pi_)
    let br = gs.bessel_knu(0.0f64, zeta) / gs.bessel_knu(1.0f64, zeta)
    let s03 = sum_x(x, mu, delta, 0.0f64, 3.0f64)
    let s33 = sum_x(x, mu, delta, 3.0f64, 3.0f64)
    let s11 = sum_x(x, mu, delta, 1.0f64, 1.0f64)
    let s43 = sum_x(x, mu, delta, 4.0f64, 3.0f64)
    let s21 = sum_x(x, mu, delta, 2.0f64, 1.0f64)
    let s10 = sum_x(x, mu, delta, 1.0f64, 0.0f64)
    let s0m = sum_x(x, mu, delta, 0.0f64, 0.0f64 - 1.0f64)
    if set == 1usize {
        h[0usize] = 0.0f64 - zeta * sq * delta * s03
        h[1usize] = 0.0f64 - zeta / (delta * delta) * (sq * s33 - 2.0f64 * sq * s11 - n * pi_)
        h[4usize] = h[1usize]
        h[2usize] = 0.0f64 - zeta / delta * (pi_ / sq * s11 + n)
        h[8usize] = h[2usize]
        h[3usize] = 0.0f64 - 1.0f64 / delta * (sq * s11 + n * pi_)
        h[12usize] = h[3usize]
        h[5usize] = n / (delta * delta) + zeta / (delta * delta * delta) * (sq * s43 - 3.0f64 * sq * s21 - 2.0f64 * pi_ * s10)
        h[6usize] = zeta / (delta * delta) * (pi_ / sq * s21 + s10)
        h[9usize] = h[6usize]
        h[7usize] = 1.0f64 / (delta * delta) * (sq * s21 + pi_ * s10)
        h[13usize] = h[7usize]
        h[10usize] = n / math.pow[f64](1.0f64 + pi_ * pi_, 2.0f64) * (pi_ * pi_ - 1.0f64) - zeta / (math.pow[f64](1.0f64 + pi_ * pi_, 3.5f64) * delta) * s0m * (2.0f64 * pi_ * pi_ + math.pow[f64](pi_, 4.0f64) + 1.0f64)
        h[11usize] = 0.0f64 - 1.0f64 / delta * (s10 + (pi_ / sq) * s0m)
        h[14usize] = h[11usize]
        h[15usize] = 0.0f64 - n * (1.0f64 + 1.0f64 / (zeta * zeta) - br / zeta - br * br)
        ret
    }
    h[0usize] = 0.0f64 - zeta * sq * delta * s03
    h[1usize] = 0.0f64 - zeta / delta * (sq * s33 - 2.0f64 * sq * s11 - n * pi_)
    h[4usize] = h[1usize]
    h[2usize] = 0.0f64 - zeta / delta * (pi_ / sq * s11 + n)
    h[8usize] = h[2usize]
    h[3usize] = 0.0f64 - zeta / delta * (sq * s11 + n * pi_)
    h[12usize] = h[3usize]
    h[5usize] = zeta / delta * (sq * s43 - 2.0f64 * sq * s21 - pi_ * s10)
    h[6usize] = zeta / delta * (pi_ / sq * s21 + s10)
    h[9usize] = h[6usize]
    h[7usize] = zeta / delta * (sq * s21 + pi_ * s10)
    h[13usize] = h[7usize]
    h[10usize] = n / math.pow[f64](1.0f64 + pi_ * pi_, 2.0f64) * (pi_ * pi_ - 1.0f64) - zeta / (math.pow[f64](1.0f64 + pi_ * pi_, 3.5f64) * delta) * s0m * (2.0f64 * pi_ * pi_ + math.pow[f64](pi_, 4.0f64) + 1.0f64)
    h[11usize] = 0.0f64 - zeta / (sq * delta) * (sq * s10 + pi_ * s0m)
    h[14usize] = h[11usize]
    h[15usize] = 0.0f64 - n * zeta * zeta + 2.0f64 * n * zeta * br + n * zeta * zeta * br * br - sq * zeta / delta * s0m - pi_ * zeta / delta * s10
}

// standard errors: sqrt(diag(solve(-H))) for an n x n hessian, by Gauss-Jordan elimination with partial pivoting; false when singular
fn hess_se(hess: []const f64, n: usize, se: []f64) -> bool {
    var m: [32]f64 = zero
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            m[i * 2usize * n + j] = 0.0f64 - hess[i * n + j]
            m[i * 2usize * n + n + j] = 0.0f64
            if i == j { m[i * 2usize * n + n + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    let w = 2usize * n
    var col = 0usize
    while col < n {
        var piv = col
        var r = col + 1usize
        while r < n {
            if math.abs[f64](m[r * w + col]) > math.abs[f64](m[piv * w + col]) { piv = r }
            r += 1usize
        }
        if m[piv * w + col] == 0.0f64 { ret false }
        if piv != col {
            var k = 0usize
            while k < w {
                let t = m[col * w + k]
                m[col * w + k] = m[piv * w + k]
                m[piv * w + k] = t
                k += 1usize
            }
        }
        let d = m[col * w + col]
        var k = 0usize
        while k < w {
            m[col * w + k] = m[col * w + k] / d
            k += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let f = m[r * w + col]
                k = 0usize
                while k < w {
                    m[r * w + k] = m[r * w + k] - f * m[col * w + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < n {
        se[i] = math.sqrt[f64](m[i * w + n + i])
        i += 1usize
    }
    ret true
}
