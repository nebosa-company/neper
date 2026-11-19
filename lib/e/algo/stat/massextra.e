// R MASS: cov.trob (the multivariate t M-estimate of location and scatter), lm.ridge (ridge regression by the SVD, with
// the GCV, HKB and Lawless-Wang choices), stdres and studres of an lm, contr.sdif, and dose.p from a fitted pair of
// coefficients. Matrices are column-major.

use e.algo.linalg.decomp as decomp
use e.algo.linalg.lapack_gesdd as gesdd
use e.math
use e.math.dist as dist
use e.mem

error BadInput

// cov.trob(x, wt, center, nu, maxit, tol). center_mode 0 TRUE (estimate), 1 FALSE (zero), 2 numeric (center_in).
// cov (p * p) and loc (p) are filled; returns (iterations endit, n used).
fn cov_trob(a: *mem.Arena, x0: []const f64, n0: usize, p: usize, wt0: []const f64, use_wt: bool, center_mode: usize, center_in: []const f64, nu: f64, maxit: usize, tol: f64, cov: []f64, loc: []f64) -> (usize, usize, err) {
    var n = n0
    let (x, e1) = mem.alloc[f64](a, n0 * p)
    let (wt, e2) = mem.alloc[f64](a, n0)
    if e1 != ok || e2 != ok { ret (0usize, 0usize, mem.Full) }
    var m = 0usize
    var i = 0usize
    while i < n0 {
        var keep = true
        if use_wt && !(wt0[i] > 0.0f64) { keep = false }
        if keep {
            var j = 0usize
            while j < p {
                x[m + n0 * j] = x0[i + n0 * j]
                j += 1usize
            }
            wt[m] = 1.0f64
            if use_wt { wt[m] = wt0[i] }
            m += 1usize
        }
        i += 1usize
    }
    n = m
    // compact to n rows
    let (xc, e3) = mem.alloc[f64](a, n * p)
    if e3 != ok { ret (0usize, 0usize, mem.Full) }
    var j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            xc[i + n * j] = x[i + n0 * j]
            i += 1usize
        }
        j += 1usize
    }
    var sw = 0.0f64
    i = 0usize
    while i < n {
        sw += wt[i]
        i += 1usize
    }
    j = 0usize
    while j < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += wt[i] * xc[i + n * j]
            i += 1usize
        }
        loc[j] = s / sw
        if center_mode == 1usize { loc[j] = 0.0f64 }
        if center_mode == 2usize { loc[j] = center_in[j] }
        j += 1usize
    }
    let use_loc = center_mode == 0usize
    let (w, e4) = mem.alloc[f64](a, n)
    let (w0, e5) = mem.alloc[f64](a, n)
    let (xs, e6) = mem.alloc[f64](a, n * p)
    let (xx, e7) = mem.alloc[f64](a, n * p)
    let (qv, e8) = mem.alloc[f64](a, n)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0usize, 0usize, mem.Full) }
    let pf = f64(p)
    i = 0usize
    while i < n {
        w[i] = wt[i] * (1.0f64 + pf / nu)
        i += 1usize
    }
    var k = p
    if n < p { k = n }
    let (d, e9) = mem.alloc[f64](a, k)
    let (u, e10) = mem.alloc[f64](a, n * k)
    let (vt, e11) = mem.alloc[f64](a, k * p)
    if e9 != ok || e10 != ok || e11 != ok { ret (0usize, 0usize, mem.Full) }
    var endit = 0usize
    var iter = 1usize
    var done = false
    while iter <= maxit && !done {
        i = 0usize
        var sw2 = 0.0f64
        while i < n {
            w0[i] = w[i]
            sw2 += w[i]
            i += 1usize
        }
        j = 0usize
        while j < p {
            i = 0usize
            while i < n {
                xx[i + n * j] = xc[i + n * j] - loc[j]
                xs[i + n * j] = math.sqrt[f64](w[i] / sw2) * xx[i + n * j]
                i += 1usize
            }
            j += 1usize
        }
        let se = gesdd.svd_all(a, xs, n, p, d, u, vt)
        if se != ok { ret (0usize, 0usize, se) }
        i = 0usize
        while i < n {
            var q = 0.0f64
            j = 0usize
            while j < p {
                var t = 0.0f64
                var r = 0usize
                while r < p {
                    t += xx[i + n * r] * vt[j + k * r]
                    r += 1usize
                }
                t = t * (1.0f64 / d[j])
                q += t * t
                j += 1usize
            }
            qv[i] = q
            w[i] = (wt[i] * (nu + pf)) / (nu + q)
            i += 1usize
        }
        if use_loc {
            var sw3 = 0.0f64
            i = 0usize
            while i < n {
                sw3 += w[i]
                i += 1usize
            }
            j = 0usize
            while j < p {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += w[i] * xc[i + n * j]
                    i += 1usize
                }
                loc[j] = s / sw3
                j += 1usize
            }
        }
        var conv = true
        i = 0usize
        while i < n {
            if !(math.abs[f64](w[i] - w0[i]) < tol) { conv = false }
            i += 1usize
        }
        if conv { done = true } else {
            endit = iter
            iter += 1usize
        }
    }
    // the final scatter uses X (centred at the loc in force during the last pass), as R does
    var r1 = 0usize
    while r1 < p {
        var c1 = 0usize
        while c1 < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += (math.sqrt[f64](w[i]) * xx[i + n * r1]) * (math.sqrt[f64](w[i]) * xx[i + n * c1])
                i += 1usize
            }
            cov[r1 + p * c1] = s / sw
            c1 += 1usize
        }
        r1 += 1usize
    }
    ret (endit, n, ok)
}

// lm.ridge(y ~ x, lambda): x is n by p0 without the intercept column. coefs (k * (p0 + inter), row i for lambda i, column-major k by p) holds coef(fit);
// gcv (k), scales (p0), and (kHKB, kLW) are returned in out2 = [kHKB, kLW].
fn lm_ridge(a: *mem.Arena, x0: []const f64, n: usize, p0: usize, y0: []const f64, lambda: []const f64, inter: bool, coefs: []f64, gcv: []f64, scales: []f64, out2: []f64) -> err {
    let k = lambda.len
    let (x, e1) = mem.alloc[f64](a, n * p0)
    let (y, e2) = mem.alloc[f64](a, n)
    let (xm, e3) = mem.alloc[f64](a, p0)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var ym = 0.0f64
    var i = 0usize
    var j = 0usize
    if inter {
        j = 0usize
        while j < p0 {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += x0[i + n * j]
                i += 1usize
            }
            xm[j] = s / f64(n)
            j += 1usize
        }
        i = 0usize
        while i < n {
            ym += y0[i]
            i += 1usize
        }
        ym /= f64(n)
    }
    j = 0usize
    while j < p0 {
        i = 0usize
        while i < n {
            x[i + n * j] = x0[i + n * j]
            if inter { x[i + n * j] = x0[i + n * j] - xm[j] }
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        y[i] = y0[i]
        if inter { y[i] = y0[i] - ym }
        i += 1usize
    }
    j = 0usize
    while j < p0 {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += (1.0f64 / f64(n)) * (x[i + n * j] * x[i + n * j])
            i += 1usize
        }
        scales[j] = math.sqrt[f64](s)
        i = 0usize
        while i < n {
            x[i + n * j] = x[i + n * j] / scales[j]
            i += 1usize
        }
        j += 1usize
    }
    var kk = n
    if p0 < n { kk = p0 }
    let (d, e4) = mem.alloc[f64](a, kk)
    let (u, e5) = mem.alloc[f64](a, n * kk)
    let (vt, e6) = mem.alloc[f64](a, kk * p0)
    let (rhs, e7) = mem.alloc[f64](a, kk)
    let (ls, e8) = mem.alloc[f64](a, p0)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    let se = gesdd.svd_all(a, x, n, p0, d, u, vt)
    if se != ok { ret se }
    var q = 0usize
    while q < kk {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += u[i + n * q] * y[i]
            i += 1usize
        }
        rhs[q] = s
        q += 1usize
    }
    j = 0usize
    while j < p0 {
        var s = 0.0f64
        q = 0usize
        while q < kk {
            s += vt[q + kk * j] * (rhs[q] / d[q])
            q += 1usize
        }
        ls[j] = s
        j += 1usize
    }
    var ssr = 0.0f64
    var ssf = 0.0f64
    i = 0usize
    while i < n {
        var f = 0.0f64
        j = 0usize
        while j < p0 {
            f += x[i + n * j] * ls[j]
            j += 1usize
        }
        ssf += f * f
        ssr += (y[i] - f) * (y[i] - f)
        i += 1usize
    }
    var ic = 0.0f64
    if inter { ic = 1.0f64 }
    let s2 = ssr / (f64(n) - f64(p0) - ic)
    var sl = 0.0f64
    j = 0usize
    while j < p0 {
        sl += ls[j] * ls[j]
        j += 1usize
    }
    out2[0usize] = (f64(p0) - 2.0f64) * s2 / sl
    out2[1usize] = (f64(p0) - 2.0f64) * s2 * f64(n) / ssf
    let ncol = p0
    var nc = p0
    if inter { nc = p0 + 1usize }
    var l = 0usize
    while l < k {
        var tr = 0.0f64
        let (cf, e9) = mem.alloc[f64](a, p0)
        if e9 != ok { ret mem.Full }
        q = 0usize
        while q < kk {
            tr += d[q] * d[q] / (d[q] * d[q] + lambda[l])
            q += 1usize
        }
        j = 0usize
        while j < p0 {
            var s = 0.0f64
            q = 0usize
            while q < kk {
                s += vt[q + kk * j] * ((d[q] * rhs[q]) / (d[q] * d[q] + lambda[l]))
                q += 1usize
            }
            cf[j] = s
            j += 1usize
        }
        var rs = 0.0f64
        i = 0usize
        while i < n {
            var f = 0.0f64
            j = 0usize
            while j < p0 {
                f += x[i + n * j] * cf[j]
                j += 1usize
            }
            rs += (y[i] - f) * (y[i] - f)
            i += 1usize
        }
        gcv[l] = rs / ((f64(n) - tr) * (f64(n) - tr))
        // coef.ridgelm: scaled back, then the intercept
        var off = 0usize
        var ints = 0.0f64
        j = 0usize
        while j < ncol {
            let sc = cf[j] / scales[j]
            if inter {
                ints += sc * xm[j]
                coefs[l + k * (j + 1usize)] = sc
            } else { coefs[l + k * j] = sc }
            j += 1usize
        }
        if inter { coefs[l] = ym - ints }
        let _ = off
        off = nc
        l += 1usize
    }
    ret ok
}

// stdres / studres of lm(y ~ x) (the intercept is added here when inter): stddev, stdres (n), studres (n); weights when has_w
fn lm_stdres(a: *mem.Arena, x0: []const f64, n: usize, p0: usize, y: []const f64, w: []const f64, has_w: bool, inter: bool, stdres: []f64, studres: []f64) -> (f64, err) {
    var p = p0
    if inter { p += 1usize }
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (yw, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    var off = 0usize
    if inter {
        while i < n {
            x[i] = 1.0f64
            i += 1usize
        }
        off = n
    }
    i = 0usize
    while i < n * p0 {
        x[off + i] = x0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s = 1.0f64
        if has_w { s = math.sqrt[f64](w[i]) }
        yw[i] = y[i] * s
        var j = 0usize
        while j < p {
            x[i + n * j] = x[i + n * j] * s
            j += 1usize
        }
        i += 1usize
    }
    let (f, fe) = decomp.lm_fit(a, x, n, p, yw, 1.0e-7f64)
    if fe != ok { ret (0.0f64, fe) }
    let (qf, qe) = decomp.qr(a, x, n, p, 1.0e-7f64)
    if qe != ok { ret (0.0f64, qe) }
    // hat_i = sum of squares of row i of the first rank columns of Q
    let (hat, e3) = mem.alloc[f64](a, n)
    let (col, e4) = mem.alloc[f64](a, n)
    if e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    i = 0usize
    while i < n {
        hat[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < qf.rank {
        i = 0usize
        while i < n {
            col[i] = 0.0f64
            i += 1usize
        }
        col[c] = 1.0f64
        decomp.qr_qy(&qf, col)
        i = 0usize
        while i < n {
            hat[i] += col[i] * col[i]
            i += 1usize
        }
        c += 1usize
    }
    // resid <- object$residuals * wt^0.5 : the weighted residuals
    var rss = 0.0f64
    var nn = 0usize
    i = 0usize
    while i < n {
        if !has_w || w[i] != 0.0f64 {
            rss += f.residuals[i] * f.residuals[i]
            nn += 1usize
        }
        i += 1usize
    }
    let rdf = f64(nn - qf.rank)
    let stddev = math.sqrt[f64](rss / rdf)
    var m = 0usize
    i = 0usize
    while i < n {
        if !has_w || w[i] != 0.0f64 {
            let sr = f.residuals[i] / (math.sqrt[f64](1.0f64 - hat[i]) * stddev)
            stdres[m] = sr
            studres[m] = sr / math.sqrt[f64]((f64(n) - f64(qf.rank) - sr * sr) / (f64(n) - f64(qf.rank) - 1.0f64))
            m += 1usize
        }
        i += 1usize
    }
    ret (stddev, ok)
}

// contr.sdif(n): the n by (n - 1) successive-difference contrasts
fn contr_sdif(n: usize, out: []f64) {
    var j = 0usize
    while j + 1usize < n {
        var i = 0usize
        while i < n {
            var v = f64(j + 1usize)
            if i <= j { v = v - f64(n) }
            out[i + n * j] = v / f64(n)
            i += 1usize
        }
        j += 1usize
    }
}

// dose.p: link 0 logit, 1 probit, 2 cloglog, 3 cauchit, 4 log; returns (dose, SE) from the two coefficients and their covariance (v11, v12, v22)
fn dose_p(link: usize, p: f64, b1: f64, b2: f64, v11: f64, v12: f64, v22: f64) -> (f64, f64) {
    var eta = 0.0f64
    if link == 0usize { eta = math.log[f64](p / (1.0f64 - p)) }
    if link == 1usize { eta = dist.qnorm(p, 0.0f64, 1.0f64, true, false) }
    if link == 2usize { eta = math.log[f64](0.0f64 - math.log[f64](1.0f64 - p)) }
    if link == 3usize { eta = dist.qcauchy(p, 0.0f64, 1.0f64, true, false) }
    if link == 4usize { eta = math.log[f64](p) }
    let xp = (eta - b1) / b2
    let pd1 = 0.0f64 - 1.0f64 / b2
    let pd2 = 0.0f64 - xp / b2
    let se = math.sqrt[f64]((pd1 * v11 + pd2 * v12) * pd1 + (pd1 * v12 + pd2 * v22) * pd2)
    ret (xp, se)
}
