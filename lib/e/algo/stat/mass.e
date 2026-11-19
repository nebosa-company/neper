// R MASS, the closed-form part: `mad`, `huber` and `hubers` (Huber's location and scale M-estimates by the
// package's own iteration), `fitdistr` for the families with closed-form maximum likelihood (normal,
// exponential, Poisson, geometric, log-normal) with standard errors and log-likelihood, `boxcox_loglik`
// (the profile log-likelihood of the Box-Cox transform for an intercept-only or given-design model) and
// `bandwidth_nrd`.
//
// `mvrnorm` (the Gaussian draws filled column by column, then mu + V diag(sqrt(lambda)) t(Z) from the sign-exact eigen decomposition).
//
// Not here: lqs, cov.rob, isoMDS, sammon, stepAIC and the numerically optimised fitdistr families.

use e.algo.linalg.decomp as decomp
use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat as sx
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

error NotPositive

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    let n = v.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// mad(x): 1.4826 * median(|x - median(x)|)
fn mad(a: *mem.Arena, x: []const f64) -> f64 {
    let m = median_of(a, x)
    let (d, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        d[i] = math.abs[f64](x[i] - m)
        i += 1usize
    }
    ret 1.4826f64 * median_of(a, d)
}

fn clamp(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

// huber(y, k): (mu, s) with s the MAD
fn huber(a: *mem.Arena, y: []const f64, k: f64, tol: f64) -> (f64, f64) {
    let n = f64(y.len)
    var mu = median_of(a, y)
    let s = mad(a, y)
    var go = true
    var mu1 = mu
    while go {
        var sum = 0.0f64
        var i = 0usize
        while i < y.len {
            sum += clamp(y[i], mu - k * s, mu + k * s)
            i += 1usize
        }
        mu1 = sum / n
        if math.abs[f64](mu - mu1) < tol * s { go = false } else { mu = mu1 }
    }
    ret (mu, s)
}

// hubers(y, k) with both location and scale estimated (the defaults of MASS)
fn hubers(a: *mem.Arena, y: []const f64, k: f64, tol: f64) -> (f64, f64) {
    let n = f64(y.len)
    let n1 = n - 1.0f64
    var mu0 = median_of(a, y)
    var s0 = mad(a, y)
    if s0 == 0.0f64 { ret (mu0, 0.0f64) }
    let th = 2.0f64 * dist.pnorm(k, 0.0f64, 1.0f64, true, false) - 1.0f64
    let beta = th + k * k * (1.0f64 - th) - 2.0f64 * k * dist.dnorm(k, 0.0f64, 1.0f64, false)
    var it = 0usize
    var mu1 = mu0
    var s1 = s0
    while it < 30usize {
        var sum = 0.0f64
        var i = 0usize
        while i < y.len {
            sum += clamp(y[i], mu0 - k * s0, mu0 + k * s0)
            i += 1usize
        }
        mu1 = sum / n
        var ss = 0.0f64
        i = 0usize
        while i < y.len {
            let yy = clamp(y[i], mu0 - k * s0, mu0 + k * s0)
            ss += (yy - mu1) * (yy - mu1)
            i += 1usize
        }
        s1 = math.sqrt[f64](ss / n1 / beta)
        if math.abs[f64](mu0 - mu1) < tol * s0 && math.abs[f64](s0 - s1) < tol * s0 { break }
        mu0 = mu1
        s0 = s1
        it += 1usize
    }
    ret (mu0, s0)
}

// fitdistr: which 0 normal 1 exponential 2 poisson 3 geometric 4 log-normal; answers (est1, est2, se1, se2, loglik)
// (the second entries are NaN for the one-parameter families)
fn fitdistr(a: *mem.Arena, x: []const f64, which: u8) -> (f64, f64, f64, f64, f64, err) {
    let n = f64(x.len)
    let nanv = 0.0f64 / 0.0f64
    var m = 0.0f64
    var i = 0usize
    if which == 4u8 {
        let (lx, le) = mem.alloc[f64](a, x.len)
        if le != ok { ret (nanv, nanv, nanv, nanv, nanv, le) }
        i = 0usize
        var sl = 0.0f64
        while i < x.len {
            lx[i] = math.log[f64](x[i])
            sl += lx[i]
            i += 1usize
        }
        let mu = sl / n
        var ss = 0.0f64
        i = 0usize
        while i < x.len {
            ss += (lx[i] - mu) * (lx[i] - mu)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / n)
        var ll = 0.0f64
        i = 0usize
        while i < x.len {
            ll += dist.dnorm(lx[i], mu, sd, true) - lx[i]
            i += 1usize
        }
        ret (mu, sd, sd / math.sqrt[f64](n), sd / math.sqrt[f64](2.0f64 * n), ll, ok)
    }
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    m = s / n
    if which == 0u8 {
        var ss = 0.0f64
        i = 0usize
        while i < x.len {
            ss += (x[i] - m) * (x[i] - m)
            i += 1usize
        }
        let sd = math.sqrt[f64](ss / n)
        var ll = 0.0f64
        i = 0usize
        while i < x.len {
            ll += dist.dnorm(x[i], m, sd, true)
            i += 1usize
        }
        ret (m, sd, sd / math.sqrt[f64](n), sd / math.sqrt[f64](2.0f64 * n), ll, ok)
    }
    if which == 1u8 {
        let rate = 1.0f64 / m
        ret (rate, nanv, rate / math.sqrt[f64](n), nanv, n * math.log[f64](rate) - rate * s, ok)
    }
    if which == 2u8 {
        var ll = 0.0f64
        i = 0usize
        while i < x.len {
            ll += x[i] * math.log[f64](m) - m - lgam(x[i] + 1.0f64)
            i += 1usize
        }
        ret (m, nanv, math.sqrt[f64](m / n), nanv, ll, ok)
    }
    let p = 1.0f64 / (1.0f64 + m)
    var ll = 0.0f64
    i = 0usize
    while i < x.len {
        ll += math.log[f64](p) + x[i] * math.log[f64](1.0f64 - p)
        i += 1usize
    }
    ret (p, nanv, math.sqrt[f64](p * p * (1.0f64 - p) / n), nanv, ll, ok)
}

fn lgam(x: f64) -> f64 {
    var s = 0.0f64
    var k = 2.0f64
    while k < x {
        s += math.log[f64](k)
        k += 1.0f64
    }
    ret s
}

// the Box-Cox profile log-likelihood at lambda for the response y and the design x (n x p, column-major)
fn boxcox_loglik(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, lam: f64) -> (f64, err) {
    let n = y.len
    var gm = 0.0f64
    var i = 0usize
    while i < n {
        gm += math.log[f64](y[i])
        i += 1usize
    }
    gm = math.exp[f64](gm / f64(n))
    let (yt, ye) = mem.alloc[f64](a, n)
    if ye != ok { ret (0.0f64, ye) }
    i = 0usize
    while i < n {
        let yy = y[i] / gm
        let ly = math.log[f64](yy)
        if math.abs[f64](lam) > 0.02f64 {
            yt[i] = (math.pow[f64](yy, lam) - 1.0f64) / lam
        } else {
            yt[i] = ly * (1.0f64 + (lam * ly) / 2.0f64 * (1.0f64 + (lam * ly) / 3.0f64 * (1.0f64 + (lam * ly) / 4.0f64)))
        }
        i += 1usize
    }
    let (fit, fe) = decomp.lm_fit(a, x, n, p, yt, 1.0e-7f64)
    if fe != ok { ret (0.0f64, fe) }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += fit.residuals[i] * fit.residuals[i]
        i += 1usize
    }
    ret (0.0f64 - f64(n) / 2.0f64 * math.log[f64](rss), ok)
}

fn bandwidth_nrd(a: *mem.Arena, x: []const f64) -> f64 {
    let n = f64(x.len)
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var m = 0.0f64
    while i < x.len {
        s[i] = x[i]
        m += x[i]
        i += 1usize
    }
    m = m / n
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        ss += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (n - 1.0f64))
    let q1 = quant7(s, 0.25f64)
    let q3 = quant7(s, 0.75f64)
    let h = (q3 - q1) / 1.34f64
    var mn = sd
    if h < mn { mn = h }
    ret 4.0f64 * 1.06f64 * mn * math.pow[f64](n, 0.0f64 - 0.2f64)
}

fn quant7(s: []const f64, p: f64) -> f64 {
    let index = 1.0f64 + (f64(s.len) - 1.0f64) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    let q = s[usize(lo) - 1usize]
    let xh = s[usize(hi) - 1usize]
    if index > lo && xh != q { ret (1.0f64 - (index - lo)) * q + (index - lo) * xh }
    ret q
}

// ginv(x) for an m by n column-major x: the n by m Moore-Penrose inverse, singular values below sqrt(eps) * max dropped
fn ginv(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> ([]f64, err) {
    let (s, e) = decomp.svd(a, x, m, n)
    let (out, oe) = mem.alloc[f64](a, n * m)
    if e != ok || oe != ok { ret (out, e) }
    var i = 0usize
    while i < n * m {
        out[i] = 0.0f64
        i += 1usize
    }
    var mx = 0.0f64
    var j = 0usize
    while j < s.k {
        if s.d[j] > mx { mx = s.d[j] }
        j += 1usize
    }
    let tol = 1.4901161193847656e-8f64 * mx
    j = 0usize
    while j < s.k {
        if s.d[j] > tol {
            var r = 0usize
            while r < n {
                var c = 0usize
                while c < m {
                    out[c * n + r] += s.v[j * n + r] * s.u[j * m + c] / s.d[j]
                    c += 1usize
                }
                r += 1usize
            }
        }
        j += 1usize
    }
    ret (out, ok)
}

// rlm(y ~ x, psi = psi.huber, k = k, scale.est = "MAD", init = "ls"): iteratively reweighted least squares on the n by p column-major design x; the scale is median(|resid|) / 0.6745 each iteration, the weights min(1, k / |resid / scale|),
// stopping when the relative change of the residuals is at most 1e-4 (at most 20 steps); coef receives the coefficients, out = (scale, iterations, converged)
fn rlm_huber(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, k: f64, coef: []f64, out: []f64) -> err { ret rlm_psi(a, x, n, p, y, 0usize, k, coef, out) }

// the same for the psi function chosen: 0 Huber (tuning k), 1 Tukey bisquare (tuning c), 2 Hampel (a = 2, b = 4, c = 8)
fn rlm_psi(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, psi: usize, k: f64, coef: []f64, out: []f64) -> err {
    let (xw, e1) = mem.alloc[f64](a, n * p)
    let (yw, e2) = mem.alloc[f64](a, n)
    let (res, e3) = mem.alloc[f64](a, n)
    let (old, e4) = mem.alloc[f64](a, n)
    let (ab, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    let (f0, fe0) = decomp.lm_fit(a, x, n, p, y, 1.0e-7f64)
    if fe0 != ok { ret fe0 }
    var j = 0usize
    while j < p {
        coef[j] = f0.coef[j]
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var f = 0.0f64
        j = 0usize
        while j < p {
            f += x[j * n + i] * coef[j]
            j += 1usize
        }
        res[i] = y[i] - f
        i += 1usize
    }
    var scale = 0.0f64
    var done = false
    var it = 0usize
    while it < 20usize && !done {
        it += 1usize
        i = 0usize
        while i < n {
            old[i] = res[i]
            ab[i] = math.abs[f64](res[i])
            i += 1usize
        }
        scale = median_of(a, ab) / 0.6745f64
        if scale == 0.0f64 {
            done = true
        } else {
            i = 0usize
            while i < n {
                let u = math.abs[f64](res[i] / scale)
                var w = 1.0f64
                if psi == 0usize {
                    if u > k { w = k / u }
                } else if psi == 1usize {
                    var r = u / k
                    if r > 1.0f64 { r = 1.0f64 }
                    w = (1.0f64 - r * r) * (1.0f64 - r * r)
                } else {
                    var uu = u
                    if uu < 1.0e-10f64 { uu = 1.0e-10f64 }
                    if uu <= 2.0f64 { w = 1.0f64 } else if uu <= 4.0f64 { w = 2.0f64 / uu } else if uu <= 8.0f64 { w = 2.0f64 * (8.0f64 - uu) / (uu * 4.0f64) } else { w = 0.0f64 }
                }
                let sw = math.sqrt[f64](w)
                yw[i] = y[i] * sw
                j = 0usize
                while j < p {
                    xw[j * n + i] = x[j * n + i] * sw
                    j += 1usize
                }
                i += 1usize
            }
            let (f1, fe1) = decomp.lm_fit(a, xw, n, p, yw, 1.0e-7f64)
            if fe1 != ok { ret fe1 }
            j = 0usize
            while j < p {
                coef[j] = f1.coef[j]
                j += 1usize
            }
            i = 0usize
            while i < n {
                var f = 0.0f64
                j = 0usize
                while j < p {
                    f += x[j * n + i] * coef[j]
                    j += 1usize
                }
                res[i] = y[i] - f
                i += 1usize
            }
            var dn = 0.0f64
            var so = 0.0f64
            i = 0usize
            while i < n {
                dn += (old[i] - res[i]) * (old[i] - res[i])
                so += old[i] * old[i]
                i += 1usize
            }
            var den = so
            if den < 1.0e-20f64 { den = 1.0e-20f64 }
            if math.sqrt[f64](dn / den) <= 1.0e-4f64 { done = true }
        }
    }
    out[0usize] = scale
    out[1usize] = f64(it)
    if done { out[2usize] = 1.0f64 } else { out[2usize] = 0.0f64 }
    ret ok
}

// kde2d(x, y, h, n, lims): the bivariate normal kernel density estimate on the n1 by n2 grid (z[i + n1 j] at (gx[i], gy[j])), the bandwidths h / 4 with h the given pair or bandwidth.nrd of each variable; lims = (x lo, x hi, y lo, y hi)
fn kde2d(a: *mem.Arena, x: []const f64, y: []const f64, h1: f64, h2: f64, n1: usize, n2: usize, lims: []const f64, z: []f64) -> err {
    let nx = x.len
    var hx = h1
    var hy = h2
    if hx <= 0.0f64 { hx = bandwidth_nrd(a, x) }
    if hy <= 0.0f64 { hy = bandwidth_nrd(a, y) }
    hx = hx / 4.0f64
    hy = hy / 4.0f64
    let (gx, e1) = mem.alloc[f64](a, n1)
    let (gy, e2) = mem.alloc[f64](a, n2)
    if e1 != ok || e2 != ok { ret mem.Full }
    let bx = (lims[1usize] - lims[0usize]) / f64(n1 - 1usize)
    let by = (lims[3usize] - lims[2usize]) / f64(n2 - 1usize)
    var i = 0usize
    while i < n1 {
        gx[i] = lims[0usize] + f64(i) * bx
        i += 1usize
    }
    gx[n1 - 1usize] = lims[1usize]
    i = 0usize
    while i < n2 {
        gy[i] = lims[2usize] + f64(i) * by
        i += 1usize
    }
    gy[n2 - 1usize] = lims[3usize]
    let c = 0.3989422804014327f64
    var gi = 0usize
    while gi < n1 {
        var gj = 0usize
        while gj < n2 {
            var s = 0.0f64
            var k = 0usize
            while k < nx {
                let ax = (gx[gi] - x[k]) / hx
                let ay = (gy[gj] - y[k]) / hy
                s += c * math.exp[f64](0.0f64 - 0.5f64 * ax * ax) * c * math.exp[f64](0.0f64 - 0.5f64 * ay * ay)
                k += 1usize
            }
            z[gi + n1 * gj] = s / (f64(nx) * hx * hy)
            gj += 1usize
        }
        gi += 1usize
    }
    ret ok
}

// mvrnorm(n, mu, Sigma) with the generator r: sigma is p by p row-major (symmetric), out is n by p row-major. The n * p normals are drawn column by column
// (as rnorm(p * n) fills matrix(, n)); the result is mu + Z diag(sqrt(lambda)) V' row by row, with V and lambda from eigen(Sigma, symmetric = TRUE).
// Fails when Sigma has an eigenvalue below -1e-6 times the largest.
fn mvrnorm(a: *mem.Arena, r: *rng.Rng, n: usize, p: usize, mu: []const f64, sigma: []const f64, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret e1 }
    let (v, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret e2 }
    let (z, e3) = mem.alloc[f64](a, n * p)
    if e3 != ok { ret e3 }
    let e4 = sy.dsyevr_all(a, sigma, p, w, v)
    if e4 != ok { ret e4 }
    var top = 0.0f64
    var k = 0usize
    while k < p {
        let ak = math.abs[f64](w[k])
        if ak > top { top = ak }
        k += 1usize
    }
    k = 0usize
    while k < p {
        if w[k] < 0.0f64 - 0.000001f64 * top { ret NotPositive }
        k += 1usize
    }
    // the normals, column by column: z[i * p + j] is row i of column j
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            z[i * p + j] = rng.rnorm(r, 0.0f64, 1.0f64)
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var row = 0usize
        while row < p {
            var acc = mu[row]
            k = 0usize
            while k < p {
                // R's eigen lists the eigenvalues in decreasing order, LAPACK ascending: column k of R is column p - 1 - k here
                let kk = p - 1usize - k
                var lam = w[kk]
                if lam < 0.0f64 { lam = 0.0f64 }
                acc += v[kk * p + row] * math.sqrt[f64](lam) * z[i * p + k]
                k += 1usize
            }
            out[i * p + row] = acc
            row += 1usize
        }
        i += 1usize
    }
    ret ok
}

// MASS negative.binomial(theta): the family's variance, deviance residual and aic term at one observation
fn nb_variance(mu: f64, theta: f64) -> f64 { ret mu + mu * mu / theta }

fn nb_dev_resid(y: f64, mu: f64, wt: f64, theta: f64) -> f64 {
    var m = 1.0f64
    if y > 1.0f64 { m = y }
    ret 2.0f64 * wt * (y * math.log[f64](m / mu) - (y + theta) * math.log[f64]((y + theta) / (mu + theta)))
}

// the contribution of one observation to the family's aic: 2 w ((y + theta) log(mu + theta) - y log mu + lgamma(y + 1) - theta log theta + lgamma(theta) - lgamma(theta + y))
fn nb_aic_term(y: f64, mu: f64, wt: f64, theta: f64) -> f64 {
    ret 2.0f64 * wt * ((y + theta) * math.log[f64](mu + theta) - y * math.log[f64](mu) + nm.lgammafn(y + 1.0f64) - theta * math.log[f64](theta) + nm.lgammafn(theta) - nm.lgammafn(theta + y))
}

// gamma.shape of a Gamma glm: the maximum-likelihood shape alpha by Newton from the moment start, from the response y, the fitted values u, the prior weights A, the deviance and its residual degrees of freedom; alpha and its standard error go to out[0], out[1]
fn gamma_shape(y: []const f64, u: []const f64, aw: []const f64, deviance: f64, dfres: f64, itlim: usize, out: []f64) {
    let dbar = deviance / dfres
    var alpha = (6.0f64 + 2.0f64 * dbar) / (dbar * (6.0f64 + dbar))
    let n = y.len
    let epsmax = math.sqrt[f64](math.sqrt[f64](2.220446049250313e-16f64))
    var eps = 1.0f64
    var itr = 0usize
    var inf = 0.0f64
    while math.abs[f64](eps) > epsmax && itr < itlim {
        itr += 1usize
        var sc = 0.0f64
        inf = 0.0f64
        var i = 0usize
        while i < n {
            var yz = 0.0f64
            if y[i] == 0.0f64 { yz = 1.0f64 }
            let fixed = 0.0f64 - y[i] / u[i] - math.log[f64](u[i]) + math.log[f64](aw[i]) + 1.0f64 + math.log[f64](y[i] + yz)
            sc += aw[i] * (fixed + math.log[f64](alpha) - sx.digamma(aw[i] * alpha))
            inf += aw[i] * (aw[i] * sx.trigamma(aw[i] * alpha) - 1.0f64 / alpha)
            i += 1usize
        }
        eps = sc / inf
        alpha += eps
    }
    out[0usize] = alpha
    out[1usize] = math.sqrt[f64](1.0f64 / inf)
}

// RSS of the least-squares fit of y on an intercept and the columns of x (n by p, row-major) chosen by mask, by Gaussian elimination on the normal equations with partial pivoting
fn lm_rss(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, mask: []const f64) -> (f64, err) {
    var q = 1usize
    var j = 0usize
    while j < p {
        if mask[j] != 0.0f64 { q += 1usize }
        j += 1usize
    }
    let (idx, e0) = mem.alloc[usize](a, q)
    let (m, e1) = mem.alloc[f64](a, q * (q + 1usize))
    if e0 != ok || e1 != ok { ret (0.0f64, mem.Full) }
    idx[0usize] = p
    var c = 1usize
    j = 0usize
    while j < p {
        if mask[j] != 0.0f64 {
            idx[c] = j
            c += 1usize
        }
        j += 1usize
    }
    var r = 0usize
    while r < q {
        var s = 0usize
        while s < q {
            var v = 0.0f64
            var i = 0usize
            while i < n {
                var xr = 1.0f64
                if idx[r] < p { xr = x[i * p + idx[r]] }
                var xs = 1.0f64
                if idx[s] < p { xs = x[i * p + idx[s]] }
                v += xr * xs
                i += 1usize
            }
            m[r * (q + 1usize) + s] = v
            s += 1usize
        }
        var v2 = 0.0f64
        var i2 = 0usize
        while i2 < n {
            var xr = 1.0f64
            if idx[r] < p { xr = x[i2 * p + idx[r]] }
            v2 += xr * y[i2]
            i2 += 1usize
        }
        m[r * (q + 1usize) + q] = v2
        r += 1usize
    }
    var col = 0usize
    while col < q {
        var piv = col
        var rr = col + 1usize
        while rr < q {
            if math.abs[f64](m[rr * (q + 1usize) + col]) > math.abs[f64](m[piv * (q + 1usize) + col]) { piv = rr }
            rr += 1usize
        }
        var cc = 0usize
        while cc <= q {
            let t = m[col * (q + 1usize) + cc]
            m[col * (q + 1usize) + cc] = m[piv * (q + 1usize) + cc]
            m[piv * (q + 1usize) + cc] = t
            cc += 1usize
        }
        rr = 0usize
        while rr < q {
            if rr != col {
                let f = m[rr * (q + 1usize) + col] / m[col * (q + 1usize) + col]
                cc = col
                while cc <= q {
                    m[rr * (q + 1usize) + cc] -= f * m[col * (q + 1usize) + cc]
                    cc += 1usize
                }
            }
            rr += 1usize
        }
        col += 1usize
    }
    var rss = 0.0f64
    var i3 = 0usize
    while i3 < n {
        var fit = 0.0f64
        r = 0usize
        while r < q {
            var xr = 1.0f64
            if idx[r] < p { xr = x[i3 * p + idx[r]] }
            fit += xr * m[r * (q + 1usize) + q] / m[r * (q + 1usize) + r]
            r += 1usize
        }
        rss += (y[i3] - fit) * (y[i3] - fit)
        i3 += 1usize
    }
    ret (rss, ok)
}

fn lm_aic(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, mask: []const f64) -> (f64, err) {
    let (rss, e) = lm_rss(a, x, n, p, y, mask)
    if e != ok { ret (0.0f64, e) }
    var q = 1.0f64
    var j = 0usize
    while j < p {
        if mask[j] != 0.0f64 { q += 1.0f64 }
        j += 1usize
    }
    ret (f64(n) * math.log[f64](rss / f64(n)) + 2.0f64 * q, ok)
}

// stepAIC(lm) over single-column numeric terms: direction 0 both, 1 backward, 2 forward; scope is every column (upper) down to the intercept only (lower); mask (1 in the model) is the start and receives the final model.
// Rows are tried as MASS orders them: <none> first, then the drops in term order, then the adds in column order; the step with the smallest AIC is taken, and the search stops when <none> is first or the gain is under 1e-7. The answer is the final AIC.
fn step_aic_lm(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, direction: usize, mask: []f64) -> (f64, err) {
    var (cur, e) = lm_aic(a, x, n, p, y, mask)
    if e != ok { ret (0.0f64, e) }
    var steps = 0usize
    while steps < 1000usize {
        var best = cur
        var bj = p
        var j = 0usize
        if direction != 2usize {
            while j < p {
                if mask[j] != 0.0f64 {
                    mask[j] = 0.0f64
                    let (v, ev) = lm_aic(a, x, n, p, y, mask)
                    mask[j] = 1.0f64
                    if ev != ok { ret (0.0f64, ev) }
                    if v < best {
                        best = v
                        bj = j
                    }
                }
                j += 1usize
            }
        }
        j = 0usize
        if direction != 1usize {
            while j < p {
                if mask[j] == 0.0f64 {
                    mask[j] = 1.0f64
                    let (v, ev) = lm_aic(a, x, n, p, y, mask)
                    mask[j] = 0.0f64
                    if ev != ok { ret (0.0f64, ev) }
                    if v < best {
                        best = v
                        bj = j
                    }
                }
                j += 1usize
            }
        }
        if bj == p || best >= cur - 1.0e-7f64 { break }
        if mask[bj] != 0.0f64 { mask[bj] = 0.0f64 } else { mask[bj] = 1.0f64 }
        cur = best
        steps += 1usize
    }
    ret (cur, ok)
}
