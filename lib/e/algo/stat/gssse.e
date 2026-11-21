// R package gss: the standard errors of an approximate-basis fit. regaux of the package (the R side and the Fortran part) builds the posterior covariance of the unpenalised
// coefficients and of the penalised part in the eigenbasis of the penalty (vec, val); predict.ssanova then takes the quadratic form of the new design row with it.
// The package factors that matrix by a pivoted Cholesky only to use hfac' hfac, which is the symmetric matrix wm built here (the rank cut of that factorisation is not applied).

use e.math
use e.mem
use e.algo.stat.gss as gss
use e.algo.linalg.lapack_syevr as sy

fn pw10(x: f64) -> f64 { ret math.pow[f64](10.0f64, x) }

// s (n by n0) and r (n by nxi) are the weighted design, q the nxi by nxi penalty matrix, v / jp / rkv the Cholesky factor, pivots and rank of the last fit
fn regaux_se(a: *mem.Arena, s: []const f64, r: []const f64, q: []const f64, nlambda: f64, v: []const f64, jp: []const usize, rkv: usize, n: usize, n0: usize, nxi: usize, out: *gss.SeAux) -> err {
    let nn = n0 + nxi
    let (ew, e1) = gss.zeros(a, nxi)
    let (ez, e2) = gss.zeros(a, nxi * nxi)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    try sy.dsyevr_all(a, q, nxi, ew, ez)
    let sqe = math.sqrt[f64](2.220446049250313e-16f64)
    var cnt = 0usize
    var k = 0usize
    while k < nxi {
        if ew[nxi - 1usize] > 0.0f64 && ew[nxi - 1usize - k] / ew[nxi - 1usize] > sqe { cnt += 1usize }
        k += 1usize
    }
    var rkq = cnt
    if rkv - n0 < rkq { rkq = rkv - n0 }
    let (val, e3) = gss.zeros(a, rkq)
    let (vec, e4) = gss.zeros(a, nxi * rkq)
    let (rv, e5) = gss.zeros(a, n * rkq)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var j = 0usize
    while j < rkq {
        val[j] = ew[nxi - 1usize - j]
        var i = 0usize
        while i < nxi {
            vec[i + j * nxi] = ez[i + (nxi - 1usize - j) * nxi]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < rkq {
        var i = 0usize
        while i < n {
            var sm = 0.0f64
            var l = 0usize
            while l < nxi {
                sm += r[i + l * n] * vec[l + j * nxi]
                l += 1usize
            }
            rv[i + j * n] = sm
            i += 1usize
        }
        j += 1usize
    }
    // the part of r vec orthogonal to the columns of s
    let (g, e6) = gss.zeros(a, n0 * n0)
    let (bm, e7) = gss.zeros(a, n0 * rkq)
    let (rp, e8) = gss.zeros(a, n * rkq)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    var p = 0usize
    while p < n0 {
        var l = 0usize
        while l < n0 {
            g[p + l * n0] = gss.ddot(s, p * n, 1usize, s, l * n, 1usize, n)
            l += 1usize
        }
        j = 0usize
        while j < rkq {
            bm[p + j * n0] = gss.ddot(s, p * n, 1usize, rv, j * n, 1usize, n)
            j += 1usize
        }
        p += 1usize
    }
    try gss.chol_solve(g, n0, bm, rkq)
    j = 0usize
    while j < rkq {
        var i = 0usize
        while i < n {
            var sm = rv[i + j * n]
            p = 0usize
            while p < n0 {
                sm -= s[i + p * n] * bm[p + j * n0]
                p += 1usize
            }
            rp[i + j * n] = sm
            i += 1usize
        }
        j += 1usize
    }
    let (am, e9) = gss.zeros(a, rkq * rkq)
    let (ar, e10) = gss.zeros(a, rkq * rkq)
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var l2 = 0usize
    j = 0usize
    while j < rkq {
        l2 = 0usize
        while l2 < rkq {
            let gm = gss.ddot(rp, j * n, 1usize, rp, l2 * n, 1usize, n) / math.sqrt[f64](val[j]) / math.sqrt[f64](val[l2])
            am[j + l2 * rkq] = gm
            ar[j + l2 * rkq] = gm
            l2 += 1usize
        }
        j += 1usize
    }
    let lam = pw10(nlambda)
    j = 0usize
    while j < rkq {
        ar[j + j * rkq] += lam
        j += 1usize
    }
    try gss.chol_solve(ar, rkq, am, rkq)
    let (wk2, e11) = gss.zeros(a, rkq * rkq)
    if e11 != ok { ret e11 }
    j = 0usize
    while j < rkq {
        l2 = 0usize
        while l2 < rkq {
            var t = (am[j + l2 * rkq] + am[l2 + j * rkq]) / 2.0f64
            t = t / math.sqrt[f64](val[j]) / math.sqrt[f64](val[l2])
            var dg = 0.0f64
            if j == l2 { dg = 1.0f64 / val[j] }
            wk2[j + l2 * rkq] = dg - t
            l2 += 1usize
        }
        j += 1usize
    }
    // drcr: the pseudo-inverse of the fitted system applied to t(cbind(s, r)) r vec
    let (xw, e12) = gss.zeros(a, nn)
    let (dr, e13) = gss.zeros(a, n0 * rkq)
    let (tmp, e14) = gss.zeros(a, nn)
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    j = 0usize
    while j < rkq {
        p = 0usize
        while p < n0 {
            tmp[p] = gss.ddot(s, p * n, 1usize, rv, j * n, 1usize, n)
            p += 1usize
        }
        p = 0usize
        while p < nxi {
            tmp[n0 + p] = gss.ddot(r, p * n, 1usize, rv, j * n, 1usize, n)
            p += 1usize
        }
        var i = 0usize
        while i < nn {
            xw[i] = tmp[jp[i] - 1usize]
            i += 1usize
        }
        gss.dtrsl_t(v, nn, xw, 0usize)
        i = rkv
        while i < nn {
            xw[i] = 0.0f64
            i += 1usize
        }
        gss.dtrsl_up(v, 0usize, nn, nn, xw, 0usize)
        i = 0usize
        while i < nn {
            tmp[jp[i] - 1usize] = xw[i]
            i += 1usize
        }
        p = 0usize
        while p < n0 {
            dr[p + j * n0] = tmp[p]
            p += 1usize
        }
        j += 1usize
    }
    // sms = 10^nlambda times the leading block of the inverse of the fitted system
    let m = n0 + rkq
    let (wm, e15) = gss.zeros(a, m * m)
    let (ex, e16) = gss.zeros(a, nn * n0)
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    p = 0usize
    while p < n0 {
        ex[p + p * nn] = 1.0f64
        gss.dtrsl_t(v, nn, ex, p * nn)
        p += 1usize
    }
    p = 0usize
    while p < n0 {
        var l = 0usize
        while l < n0 {
            wm[p + l * m] = lam * gss.ddot(ex, p * nn, 1usize, ex, l * nn, 1usize, nn)
            l += 1usize
        }
        j = 0usize
        while j < rkq {
            let t = 0.0f64 - dr[p + j * n0] / val[j]
            wm[p + (n0 + j) * m] = t
            wm[(n0 + j) + p * m] = t
            j += 1usize
        }
        p += 1usize
    }
    j = 0usize
    while j < rkq {
        l2 = 0usize
        while l2 < rkq {
            wm[(n0 + j) + (n0 + l2) * m] = wk2[j + l2 * rkq]
            l2 += 1usize
        }
        j += 1usize
    }
    out.vec = vec
    out.val = val
    out.rkq = rkq
    out.wm = wm
    ret ok
}

// the se.aux of a finished approximate-basis fit (sspreg1 or mspreg1w with n rows, n0 unpenalised columns, nxi basis columns)
fn fit_se(a: *mem.Arena, f: *gss.Ss1, n: usize, n0: usize, nxi: usize) -> err {
    try regaux_se(a, f.sw, f.rw, f.qm, f.nlambda, f.v, f.jp, f.rkv, n, n0, nxi, &f.se)
    ret ok
}

// predict.ssanova standard errors for the approximate basis: s1 (m by n0) and the nq kernels q1 (each m by nxi) at the new rows
fn predict1_se(a: *mem.Arena, f: *const gss.Ss1, s1: []const f64, q1: []const f64, nq: usize, n0: usize, nxi: usize, m: usize, out: []f64) -> err {
    let rkq = f.se.rkq
    let mm = n0 + rkq
    let b = f.varht / pw10(f.nlambda)
    let (xv, e) = gss.zeros(a, mm)
    if e != ok { ret e }
    var i = 0usize
    while i < m {
        var p = 0usize
        while p < n0 {
            xv[p] = s1[i + p * m]
            p += 1usize
        }
        var j = 0usize
        while j < rkq {
            var sm = 0.0f64
            var l = 0usize
            while l < nxi {
                var rw = 0.0f64
                var k = 0usize
                while k < nq {
                    rw += pw10(f.theta[k]) * q1[k * m * nxi + i + l * m]
                    k += 1usize
                }
                sm += rw * f.se.vec[l + j * nxi]
                l += 1usize
            }
            xv[n0 + j] = sm
            j += 1usize
        }
        var quad = 0.0f64
        p = 0usize
        while p < mm {
            var t = 0.0f64
            var l = 0usize
            while l < mm {
                t += f.se.wm[p + l * mm] * xv[l]
                l += 1usize
            }
            quad += xv[p] * t
            p += 1usize
        }
        out[i] = math.sqrt[f64](b * quad)
        i += 1usize
    }
    ret ok
}
