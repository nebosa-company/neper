// R arm: logit and invlogit, se.coef of a linear model, and binned.resids (the binned-residual table behind binnedplot).
//
// rescale (the numeric core of standardize) is here. Not here: sim, discrete, corrplot data and the model refit of standardize.

use e.algo.stat.armx87 as xe
use e.algo.rand.rdist as rd
use e.algo.rand.r as rng
use e.algo.linalg.decomp as dc
use e.algo.stat.carlmtest as ols
use e.algo.stat.mass as ms
use e.algo.stat.desctools as dt
use e.algo.stat.gparot as gp
use e.algo.stat.gbmfit as gb
use e.math
use e.math.dist as dist
use e.mem

fn logit(p: f64) -> f64 { ret math.log[f64](p / (1.0f64 - p)) }

fn invlogit(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

// se.coef(lm): sqrt(diag(sigma^2 (X'X)^-1)) with sigma^2 = RSS / (n - p), into out (p values); x is n by p row-major
fn se_coef(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret e }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    i = 0usize
    while i < p {
        out[i] = math.sqrt[f64](s2 * f.xtx_inv[i * p + i])
        i += 1usize
    }
    ret ok
}

// binned.resids(x, y, nclass)$binned: rows of (xbar, ybar, n, x.lo, x.hi, 2se) into out (at most nclass rows of 6); returns the number of bins
fn binned_resids(a: *mem.Arena, x: []const f64, y: []const f64, nclass0: usize, out: []f64) -> usize {
    let n = x.len
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0usize }
    var nclass = nclass0
    var i = 1usize
    while i < nclass {
        if n * i / nclass == 0usize { nclass = 1usize }
        i += 1usize
    }
    let inf = 1.0f64 / 0.0f64
    let (br, e2) = mem.alloc[f64](a, nclass + 1usize)
    if e2 != ok { ret 0usize }
    var nb = 0usize
    br[0usize] = 0.0f64 - inf
    nb = 1usize
    if nclass > 1usize {
        var q = 1usize
        while q < nclass {
            let bi = n * q / nclass
            var lo = s[bi - 1usize]
            let hi = s[bi]
            if lo == hi {
                if lo == s[0usize] {
                    lo = 0.0f64 - inf
                } else {
                    var m = 0.0f64 - inf
                    var t = 0usize
                    while t < n {
                        if x[t] < lo && x[t] > m { m = x[t] }
                        t += 1usize
                    }
                    lo = m
                }
            }
            let b = (lo + hi) / 2.0f64
            if b != br[nb - 1usize] {
                br[nb] = b
                nb += 1usize
            }
            q += 1usize
        }
    } else {
        let b = (s[0usize] + s[n - 1usize]) / 2.0f64
        br[nb] = b
        nb += 1usize
    }
    // the last break is +Inf; bins are (br[b], br[b + 1]]
    let bins = nb
    var b = 0usize
    while b < bins {
        var cnt = 0.0f64
        var sx = 0.0f64
        var sy = 0.0f64
        var xlo = inf
        var xhi = 0.0f64 - inf
        var t = 0usize
        while t < n {
            let above = x[t] > br[b]
            var inside = above
            if b + 1usize < bins && x[t] > br[b + 1usize] { inside = false }
            if inside {
                cnt += 1.0f64
                sx += x[t]
                sy += y[t]
                if x[t] < xlo { xlo = x[t] }
                if x[t] > xhi { xhi = x[t] }
            }
            t += 1usize
        }
        let ybar = sy / cnt
        var sd = 0.0f64
        if cnt > 1.0f64 {
            var ss = 0.0f64
            t = 0usize
            while t < n {
                let above = x[t] > br[b]
                var inside = above
                if b + 1usize < bins && x[t] > br[b + 1usize] { inside = false }
                if inside { ss += (y[t] - ybar) * (y[t] - ybar) }
                t += 1usize
            }
            sd = math.sqrt[f64](ss / (cnt - 1.0f64))
        }
        out[b * 6usize] = sx / cnt
        out[b * 6usize + 1usize] = ybar
        out[b * 6usize + 2usize] = cnt
        out[b * 6usize + 3usize] = xlo
        out[b * 6usize + 4usize] = xhi
        out[b * 6usize + 5usize] = 2.0f64 * sd / math.sqrt[f64](cnt)
        b += 1usize
    }
    ret bins
}

// the deviance residual of one observation (gaussian, binomial or poisson)
fn dev_resid(family: usize, y: f64, mu: f64) -> f64 {
    if family == 0usize { ret (y - mu) * (y - mu) }
    if family == 1usize || family == 3usize || family == 4usize {
        var d = 0.0f64
        if y > 0.0f64 { d += y * math.log[f64](y / mu) }
        if y < 1.0f64 { d += (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
        ret 2.0f64 * d
    }
    var d = 0.0f64
    if y > 0.0f64 { d = y * math.log[f64](y / mu) }
    ret 2.0f64 * (d - (y - mu))
}

// chol2inv of the upper triangle of the k by k leading block of the column-major r (leading dimension ld): LAPACK's dpotri('U') as the reference build runs it (dtrti2 then dlauu2, the
// unblocked codes, every product in the reference BLAS order), then the upper triangle copied below. out is k by k column-major (symmetric, so row-major too).
fn chol2inv_upper(r: []const f64, ld: usize, k: usize, out: []f64) {
    var j = 0usize
    while j < k {
        var i = 0usize
        while i < k {
            out[i + j * k] = 0.0f64
            if i <= j { out[i + j * k] = r[i + j * ld] }
            i += 1usize
        }
        j += 1usize
    }
    // dtrti2: inverse of the upper triangular factor in place
    j = 0usize
    while j < k {
        out[j + j * k] = 1.0f64 / out[j + j * k]
        let ajj = 0.0f64 - out[j + j * k]
        // dtrmv('U', 'N', 'N', j, a, x = column j above the diagonal)
        var c = 0usize
        while c < j {
            let t = out[c + j * k]
            if t != 0.0f64 {
                var i = 0usize
                while i < c {
                    out[i + j * k] = out[i + j * k] + t * out[i + c * k]
                    i += 1usize
                }
                out[c + j * k] = out[c + j * k] * out[c + c * k]
            }
            c += 1usize
        }
        var i2 = 0usize
        while i2 < j {
            out[i2 + j * k] = ajj * out[i2 + j * k]
            i2 += 1usize
        }
        j += 1usize
    }
    // dlauu2: the product U U'
    var i = 0usize
    while i < k {
        let aii = out[i + i * k]
        if i + 1usize < k {
            var dot = 0.0f64
            var c = i
            while c < k {
                dot = dot + out[i + c * k] * out[i + c * k]
                c += 1usize
            }
            out[i + i * k] = dot
            // dgemv('N', i, k - i - 1, 1, A(1, i + 1), x = row i of A(., i + 1..), beta = aii, y = column i)
            var r2 = 0usize
            while r2 < i {
                out[r2 + i * k] = aii * out[r2 + i * k]
                r2 += 1usize
            }
            var cc = i + 1usize
            while cc < k {
                let t = out[i + cc * k]
                r2 = 0usize
                while r2 < i {
                    out[r2 + i * k] = out[r2 + i * k] + t * out[r2 + cc * k]
                    r2 += 1usize
                }
                cc += 1usize
            }
        } else {
            var r2 = 0usize
            while r2 <= i {
                out[r2 + i * k] = aii * out[r2 + i * k]
                r2 += 1usize
            }
        }
        i += 1usize
    }
    j = 0usize
    while j < k {
        var i3 = j + 1usize
        while i3 < k {
            out[i3 + j * k] = out[j + i3 * k]
            i3 += 1usize
        }
        j += 1usize
    }
}

// the reference BLAS dnrm2 of LAPACK 3.10 and later (what R 4.x links): the plain sum of squares of the mid-range values, sqrt at the end. A value outside [2^-511, 2^486] takes the scaled
// path of the library's other qr instead (ponytail: not the three-accumulator form, which only differs for inputs near overflow)
fn dnrm2_blue(x: []const f64, from: usize, count: usize) -> f64 {
    var amed = 0.0f64
    var i = 0usize
    var odd = false
    while i < count {
        let v = math.abs[f64](x[from + i])
        if v > 1.0e146f64 || (v < 1.0e-153f64 && v != 0.0f64) { odd = true }
        amed = amed + v * v
        i += 1usize
    }
    if odd { ret dc.norm2(x, from, count) }
    ret math.sqrt[f64](amed)
}

// dqrdc2 of R for a full-rank n by k column-major x (n > k), in place: the R factor above the diagonal, the Householder vectors below, qraux; fails with Singular where dqrdc2 would pivot
// (a column norm under 1e-7 of its original)
fn dqrdc2_full(q: []f64, n: usize, k: usize, qraux: []f64, w2: []f64, tol: f64) -> err {
    var j = 0usize
    while j < k {
        qraux[j] = dnrm2_blue(q, j * n, n)
        w2[j] = qraux[j]
        if w2[j] == 0.0f64 { w2[j] = 1.0f64 }
        j += 1usize
    }
    var l = 0usize
    while l < k {
        if qraux[l] < w2[l] * tol { ret dc.Singular }
        var nrmxl = dnrm2_blue(q, l * n + l, n - l)
        if nrmxl == 0.0f64 { ret dc.Singular }
        if q[l * n + l] != 0.0f64 {
            if q[l * n + l] < 0.0f64 { nrmxl = 0.0f64 - math.abs[f64](nrmxl) } else { nrmxl = math.abs[f64](nrmxl) }
        }
        let inv = 1.0f64 / nrmxl
        var r = l
        while r < n {
            q[l * n + r] = q[l * n + r] * inv
            r += 1usize
        }
        q[l * n + l] = 1.0f64 + q[l * n + l]
        var c = l + 1usize
        while c < k {
            var dot = 0.0f64
            r = l
            while r < n {
                dot = dot + q[l * n + r] * q[c * n + r]
                r += 1usize
            }
            let t = 0.0f64 - dot / q[l * n + l]
            r = l
            while r < n {
                q[c * n + r] = q[c * n + r] + t * q[l * n + r]
                r += 1usize
            }
            if qraux[c] != 0.0f64 {
                let ra = math.abs[f64](q[c * n + l]) / qraux[c]
                var tt = 1.0f64 - ra * ra
                if tt < 0.0f64 { tt = 0.0f64 }
                if math.abs[f64](tt) < 0.000001f64 {
                    qraux[c] = dnrm2_blue(q, c * n + l + 1usize, n - l - 1usize)
                } else {
                    qraux[c] = qraux[c] * math.sqrt[f64](tt)
                }
            }
            c += 1usize
        }
        qraux[l] = q[l * n + l]
        q[l * n + l] = 0.0f64 - nrmxl
        l += 1usize
    }
    ret ok
}

// summary(lm(y ~ x - 1)) the way R computes it: x is n by k row-major; beta is the coefficients, cov the unscaled covariance chol2inv(R) (k by k) and rss the residual sum of squares, all from
// the dqrdc2 fit. Fails on a rank-deficient design.
fn lm_summary(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, beta: []f64, cov: []f64, res: []f64) -> (f64, err) {
    let (cm, e0) = mem.alloc[f64](a, n * k)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            cm[i + j * n] = x[i * k + j]
            j += 1usize
        }
        i += 1usize
    }
    let (qraux, e2) = mem.alloc[f64](a, k)
    let (pv, e3) = mem.alloc[usize](a, k)
    let (qty, e4) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    let (w2a, e5) = mem.alloc[f64](a, k)
    if e5 != ok { ret (0.0f64, e5) }
    let qe = dqrdc2_full(cm, n, k, qraux, w2a, 0.0000001f64)
    if qe != ok { ret (0.0f64, qe) }
    let f = dc.Qr { qr: cm, qraux: qraux, pivot: pv, rank: k, n: n, p: k }
    chol2inv_upper(cm, n, k, cov)
    i = 0usize
    while i < n {
        qty[i] = y[i]
        i += 1usize
    }
    dc.qr_qty(&f, qty)
    var jj = k
    while jj > 0usize {
        jj -= 1usize
        var s = qty[jj]
        var c = jj + 1usize
        while c < k {
            s = s - cm[c * n + jj] * beta[c]
            c += 1usize
        }
        beta[jj] = s / cm[jj * n + jj]
    }
    // the residuals: Q [0; qty[k..n]], applied from the last reflection back as dqrsl does
    i = 0usize
    while i < k {
        qty[i] = 0.0f64
        i += 1usize
    }
    dc.qr_qy(&f, qty)
    var rss = 0.0f64
    var rc = 0.0f64
    i = 0usize
    while i < n {
        res[i] = qty[i]
        let sq = qty[i] * qty[i]
        let tt = rss + sq
        if math.abs[f64](rss) >= math.abs[f64](sq) { rc += (rss - tt) + sq } else { rc += (sq - tt) + rss }
        rss = tt
        i += 1usize
    }
    rss = rss + rc
    ret (rss, ok)
}

// arm::sim for an lm (n.sims draws): sigma[s] = sigma.hat sqrt((n - k) / rchisq(1, n - k)), then beta[s, ] = mvrnorm(1, beta.hat, (X'X)^-1 sigma[s]^2), in that order per draw so one R stream gives
// the same numbers; x is n by k row-major; beta is nsims by k row-major
fn sim_lm(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, k: usize, nsims: usize, sigma: []f64, beta: []f64) -> err {
    let (bh, e0) = mem.alloc[f64](a, k)
    let (v0, e3) = mem.alloc[f64](a, k * k)
    if e0 != ok || e3 != ok { ret mem.Full }
    let (rs0, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret mem.Full }
    let (rss, e) = lm_summary(a, x, y, n, k, bh, v0, rs0)
    if e != ok { ret e }
    var i = 0usize
    let df = f64(n - k)
    let sh = math.sqrt[f64](rss / df)
    let (cv, e1) = mem.alloc[f64](a, k * k)
    let (dr, e2) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok { ret e1 }
    var s = 0usize
    while s < nsims {
        sigma[s] = sh * math.sqrt[f64](df / rd.rchisq(g, df))
        i = 0usize
        while i < k * k {
            cv[i] = v0[i] * (sigma[s] * sigma[s])
            i += 1usize
        }
        let me = ms.mvrnorm(a, g, 1usize, k, bh, cv, dr)
        if me != ok { ret me }
        i = 0usize
        while i < k {
            beta[s * k + i] = dr[i]
            i += 1usize
        }
        s += 1usize
    }
    ret ok
}

// IRLS of glm.fit for the binomial (family 1, logit) and poisson (family 2, log) with a dispersion of 1: the stopping rule is R's (|dev - devold| / (|dev| + 0.1) < 1e-8), cov is (X'WX)^-1 with the
// weights of the last iteration (what summary.glm uses); d is n by k row-major
fn glm_fit(a: *mem.Arena, d: []const f64, y: []const f64, n: usize, k: usize, family: usize, eta0: []const f64, beta: []f64, cov: []f64) -> err {
    let (wl, e0) = mem.alloc[f64](a, n)
    let (mf, e1) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok { ret mem.Full }
    ret glm_fit_w(a, d, y, n, k, family, eta0, beta, cov, wl, mf)
}

// glm_fit that also answers the working weights of the last iteration (what glm.fit keeps in $weights) and the final fitted means
fn glm_fit_w(a: *mem.Arena, d: []const f64, y: []const f64, n: usize, k: usize, family: usize, eta0: []const f64, beta: []f64, cov: []f64, wlast: []f64, mufinal: []f64) -> err {
    let (eta, e2) = mem.alloc[f64](a, n)
    let (mu, e3) = mem.alloc[f64](a, n)
    let (am, e4) = mem.alloc[f64](a, k * k)
    let (bv, e5) = mem.alloc[f64](a, k)
    let (bq, e6) = mem.alloc[f64](a, k)
    let (ri, e7) = mem.alloc[f64](a, k * k)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    var devold = 0.0f64
    while i < n {
        if family == 1usize { mu[i] = (y[i] + 0.5f64) / 2.0f64 } else { mu[i] = y[i] + 0.1f64 }
        if family == 1usize { eta[i] = xe.log_r(mu[i] / (1.0f64 - mu[i])) } else { eta[i] = xe.log_r(mu[i]) }
        if eta0.len == n { eta[i] = eta0[i] }
        if family == 1usize {
            var tmp = xe.exp_r(eta[i])
            if eta[i] < 0.0f64 - 30.0f64 { tmp = 2.220446049250313e-16f64 }
            if eta[i] > 30.0f64 { tmp = 1.0f64 / 2.220446049250313e-16f64 }
            mu[i] = tmp / (1.0f64 + tmp)
        } else {
            mu[i] = xe.exp_r(eta[i])
            if mu[i] < 2.220446049250313e-16f64 { mu[i] = 2.220446049250313e-16f64 }
        }
        devold += dev_resid(family, y[i], mu[i])
        i += 1usize
    }
    var it = 0usize
    while it < 25usize {
        let (xq, qe1) = mem.alloc[f64](a, n * k)
        let (zq, qe2) = mem.alloc[f64](a, n)
        if qe1 != ok || qe2 != ok { ret mem.Full }
        i = 0usize
        while i < n {
            var vr = mu[i]
            var me = 0.0f64
            if family == 1usize {
                vr = mu[i] * (1.0f64 - mu[i])
                let opexp = 1.0f64 + xe.exp_r(eta[i])
                me = xe.exp_r(eta[i]) / (opexp * opexp)
                if eta[i] > 30.0f64 || eta[i] < 0.0f64 - 30.0f64 { me = 2.220446049250313e-16f64 }
            } else {
                me = xe.exp_r(eta[i])
                if me < 2.220446049250313e-16f64 { me = 2.220446049250313e-16f64 }
            }
            let sw = math.sqrt[f64]((me * me) / vr)
            wlast[i] = sw * sw
            let z = eta[i] + (y[i] - mu[i]) / me
            var c = 0usize
            while c < k {
                xq[c * n + i] = sw * d[i * k + c]
                c += 1usize
            }
            zq[i] = sw * z
            i += 1usize
        }
        let (w2a, e8) = mem.alloc[f64](a, k)
        let (qxa, e9) = mem.alloc[f64](a, k)
        let (pva, e10) = mem.alloc[usize](a, k)
        if e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
        let fe = dqrdc2_full(xq, n, k, qxa, w2a, 1.0e-11f64)
        if fe != ok { ret gp.Singular }
        let fq = dc.Qr { qr: xq, qraux: qxa, pivot: pva, rank: k, n: n, p: k }
        dc.qr_qty(&fq, zq)
        // dqrsl's coefficient solve, column oriented
        var r = k
        while r > 0usize {
            r -= 1usize
            bq[r] = zq[r] / xq[r * n + r]
            if r > 0usize {
                let t = 0.0f64 - bq[r]
                var q2 = 0usize
                while q2 < r {
                    zq[q2] = zq[q2] + t * xq[r * n + q2]
                    q2 += 1usize
                }
            }
        }
        r = 0usize
        while r < k {
            beta[r] = bq[r]
            r += 1usize
        }
        chol2inv_upper(xq, n, k, cov)
        var dev = 0.0f64
        i = 0usize
        while i < n {
            var e = 0.0f64
            r = 0usize
            while r < k {
                e += d[i * k + r] * beta[r]
                r += 1usize
            }
            eta[i] = e
            if family == 1usize {
                var tmp = xe.exp_r(e)
                if e < 0.0f64 - 30.0f64 { tmp = 2.220446049250313e-16f64 }
                if e > 30.0f64 { tmp = 1.0f64 / 2.220446049250313e-16f64 }
                mu[i] = tmp / (1.0f64 + tmp)
            } else {
                mu[i] = xe.exp_r(e)
                if mu[i] < 2.220446049250313e-16f64 { mu[i] = 2.220446049250313e-16f64 }
            }
            dev += dev_resid(family, y[i], mu[i])
            i += 1usize
        }
        i = 0usize
        while i < n {
            mufinal[i] = mu[i]
            i += 1usize
        }
        it += 1usize
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 { break }
        devold = dev
    }
    ret ok
}
