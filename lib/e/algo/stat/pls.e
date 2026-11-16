// R pls: the four partial least squares fits of `plsr`, kernelpls (Dayal and MacGregor's kernel algorithm), simpls (de Jong), oscorespls
// (orthogonal scores, NIPALS) and widekernelpls (the n by n kernel version), each with centring. X is n by p and Y n by q, row-major.
// A fit holds, for every number of components a = 1..ncomp, the p by q coefficient matrix and the n by q fitted values; the scores,
// the X loadings and the explained X variance are those of the last component. Multi-response eigenvectors carry the arbitrary sign
// the eigen solver gives them, so the scores and loadings of such a fit are determined up to sign (the coefficients are not).
//
// And pcr (`svdpc`) and the cross-validation of mvrCv (PRESS, PRESS0 and the adjustment of adjCV) over given segments. Not here: cppls and the
// jackknife.

use e.algo.stat.ica as ic
use e.algo.stat.psych as ps
use e.math
use e.mem

type Pls = struct { coef: []f64, fitted: []f64, scores: []f64, loadings: []f64, xvar: []f64, ncomp: usize }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// a (m by k) times b (k by n)
fn mm(a: *mem.Arena, x: []const f64, y: []const f64, m: usize, k: usize, n: usize) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, m * n)
    if e != ok { ret (o, e) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += x[i * k + l] * y[l * n + j]
                l += 1usize
            }
            o[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (o, ok)
}

// t(a) (k by m, stored m by k) times b (m by n)
fn tmm(a: *mem.Arena, x: []const f64, y: []const f64, m: usize, k: usize, n: usize) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, k * n)
    if e != ok { ret (o, e) }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var l = 0usize
            while l < m {
                s += x[l * k + i] * y[l * n + j]
                l += 1usize
            }
            o[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (o, ok)
}

fn dot(x: []const f64, y: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

// the centred copy of x (n by c) and its column means
fn centre(a: *mem.Arena, x: []const f64, n: usize, c: usize, doit: bool) -> ([]f64, []f64, err) {
    let (o, e1) = mem.alloc[f64](a, n * c)
    let (mu, e2) = mem.alloc[f64](a, c)
    if e1 != ok { ret (o, mu, e1) }
    if e2 != ok { ret (o, mu, e2) }
    var j = 0usize
    while j < c {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[i * c + j]
            i += 1usize
        }
        mu[j] = 0.0f64
        if doit { mu[j] = s / f64(n) }
        i = 0usize
        while i < n {
            o[i * c + j] = x[i * c + j] - mu[j]
            i += 1usize
        }
        j += 1usize
    }
    ret (o, mu, ok)
}

// the leading eigenvector of the symmetric k by k matrix s
fn top_eigvec(a: *mem.Arena, s: []const f64, k: usize) -> ([]f64, err) {
    let (vals, vecs, e) = ic.eigen_sym(a, s, k)
    if e != ok { ret (vals, e) }
    let (v, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret (v, e2) }
    var i = 0usize
    while i < k {
        v[i] = vecs[i * k]
        i += 1usize
    }
    ret (v, ok)
}

fn alloc_fit(a: *mem.Arena, n: usize, p: usize, q: usize, ncomp: usize) -> (Pls, err) {
    var none: Pls = zero
    let (coef, e1) = mem.alloc[f64](a, ncomp * p * q)
    let (fit, e2) = mem.alloc[f64](a, ncomp * n * q)
    let (sc, e3) = mem.alloc[f64](a, n * ncomp)
    let (ld, e4) = mem.alloc[f64](a, p * ncomp)
    let (xv, e5) = mem.alloc[f64](a, ncomp)
    if e1 != ok { ret (none, e1) }
    if e2 != ok { ret (none, e2) }
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    ret (Pls { coef: coef, fitted: fit, scores: sc, loadings: ld, xvar: xv, ncomp: ncomp }, ok)
}

// B_a = R[, 1:a] tQ[1:a, ] for the p by ncomp projection r and the ncomp by q matrix tq
fn coef_at(f: Pls, r: []const f64, tq: []const f64, p: usize, q: usize, a: usize) {
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var l = 0usize
            while l <= a {
                s += r[i * f.ncomp + l] * tq[l * q + j]
                l += 1usize
            }
            f.coef[a * p * q + i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// fitted values at a components: ymeans + T[, 1:a] tQ[1:a, ]
fn fitted_at(f: Pls, tt: []const f64, tq: []const f64, ymeans: []const f64, n: usize, q: usize, a: usize) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var l = 0usize
            while l <= a {
                s += tt[i * f.ncomp + l] * tq[l * q + j]
                l += 1usize
            }
            f.fitted[a * n * q + i * q + j] = s + ymeans[j]
            j += 1usize
        }
        i += 1usize
    }
}

// kernelpls.fit(X, Y, ncomp, center)
fn kernelpls(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool) -> (Pls, err) {
    var none: Pls = zero
    let (x, xm, e1) = centre(a, x0, n, p, doc)
    if e1 != ok { ret (none, e1) }
    let (y, ym, e2) = centre(a, y0, n, q, doc)
    if e2 != ok { ret (none, e2) }
    let (f, fe) = alloc_fit(a, n, p, q, ncomp)
    if fe != ok { ret (none, fe) }
    let (rr, e3) = mem.alloc[f64](a, p * ncomp)
    let (pp, e4) = mem.alloc[f64](a, p * ncomp)
    let (tq, e5) = mem.alloc[f64](a, ncomp * q)
    let (tsqs, e6) = mem.alloc[f64](a, ncomp)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (none, e3) }
    var (xty, e7) = tmm(a, x, y, n, p, q)
    if e7 != ok { ret (none, e7) }
    let (w, e8) = mem.alloc[f64](a, p)
    let (t, e9) = mem.alloc[f64](a, n)
    if e8 != ok || e9 != ok { ret (none, e8) }
    var ac = 0usize
    while ac < ncomp {
        if q == 1usize {
            let nrm = math.sqrt[f64](dot(xty, xty))
            var i = 0usize
            while i < p {
                w[i] = xty[i] / nrm
                i += 1usize
            }
        } else if q < p {
            let (g, ge) = tmm(a, xty, xty, p, q, q)
            if ge != ok { ret (none, ge) }
            let (qv, qe) = top_eigvec(a, g, q)
            if qe != ok { ret (none, qe) }
            var i = 0usize
            var s2 = 0.0f64
            while i < p {
                var s = 0.0f64
                var j = 0usize
                while j < q {
                    s += xty[i * q + j] * qv[j]
                    j += 1usize
                }
                w[i] = s
                s2 += s * s
                i += 1usize
            }
            let nrm = math.sqrt[f64](s2)
            i = 0usize
            while i < p {
                w[i] = w[i] / nrm
                i += 1usize
            }
        } else {
            let (xt, xte) = mem.alloc[f64](a, q * p)
            if xte != ok { ret (none, xte) }
            var i = 0usize
            while i < p {
                var j = 0usize
                while j < q {
                    xt[j * p + i] = xty[i * q + j]
                    j += 1usize
                }
                i += 1usize
            }
            let (g, ge) = mm(a, xty, xt, p, q, p)
            if ge != ok { ret (none, ge) }
            let (qv, qe) = top_eigvec(a, g, p)
            if qe != ok { ret (none, qe) }
            i = 0usize
            while i < p {
                w[i] = qv[i]
                i += 1usize
            }
        }
        // r = w minus the projections on the earlier loadings
        var i = 0usize
        while i < p {
            rr[i * ncomp + ac] = w[i]
            i += 1usize
        }
        var j = 0usize
        while j < ac {
            var d = 0.0f64
            i = 0usize
            while i < p {
                d += pp[i * ncomp + j] * w[i]
                i += 1usize
            }
            i = 0usize
            while i < p {
                rr[i * ncomp + ac] = rr[i * ncomp + ac] - d * rr[i * ncomp + j]
                i += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += x[i * p + l] * rr[l * ncomp + ac]
                l += 1usize
            }
            t[i] = s
            i += 1usize
        }
        let tsq = dot(t, t)
        i = 0usize
        while i < p {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += x[l * p + i] * t[l]
                l += 1usize
            }
            pp[i * ncomp + ac] = s / tsq
            i += 1usize
        }
        j = 0usize
        while j < q {
            var s = 0.0f64
            i = 0usize
            while i < p {
                s += xty[i * q + j] * rr[i * ncomp + ac]
                i += 1usize
            }
            tq[ac * q + j] = s / tsq
            j += 1usize
        }
        i = 0usize
        while i < p {
            j = 0usize
            while j < q {
                xty[i * q + j] = xty[i * q + j] - (tsq * pp[i * ncomp + ac]) * tq[ac * q + j]
                j += 1usize
            }
            i += 1usize
        }
        tsqs[ac] = tsq
        i = 0usize
        while i < n {
            f.scores[i * ncomp + ac] = t[i]
            i += 1usize
        }
        coef_at(f, rr, tq, p, q, ac)
        ac += 1usize
    }
    var k = 0usize
    while k < ncomp {
        var s = 0.0f64
        var i = 0usize
        while i < p {
            s += pp[i * ncomp + k] * pp[i * ncomp + k]
            f.loadings[i * ncomp + k] = pp[i * ncomp + k]
            i += 1usize
        }
        f.xvar[k] = s * tsqs[k]
        k += 1usize
    }
    k = 0usize
    while k < ncomp {
        fitted_at(f, f.scores, tq, ym, n, q, k)
        k += 1usize
    }
    ret (f, ok)
}

// simpls.fit(X, Y, ncomp, center, orthScores = FALSE)
fn simpls(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool) -> (Pls, err) {
    var none: Pls = zero
    let (x, xm, e1) = centre(a, x0, n, p, doc)
    if e1 != ok { ret (none, e1) }
    let (y, ym, e2) = centre(a, y0, n, q, doc)
    if e2 != ok { ret (none, e2) }
    let (f, fe) = alloc_fit(a, n, p, q, ncomp)
    if fe != ok { ret (none, fe) }
    let (rr, e3) = mem.alloc[f64](a, p * ncomp)
    let (vv, e4) = mem.alloc[f64](a, p * ncomp)
    let (tq, e5) = mem.alloc[f64](a, ncomp * q)
    if e3 != ok || e4 != ok || e5 != ok { ret (none, e3) }
    var (s, e6) = tmm(a, x, y, n, p, q)
    if e6 != ok { ret (none, e6) }
    let (qa, e7) = mem.alloc[f64](a, q)
    let (ra, e8) = mem.alloc[f64](a, p)
    let (ta, e9) = mem.alloc[f64](a, n)
    let (pa, e10) = mem.alloc[f64](a, p)
    let (va, e11) = mem.alloc[f64](a, p)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (none, e7) }
    var ac = 0usize
    while ac < ncomp {
        var i = 0usize
        var j = 0usize
        if q == 1usize {
            qa[0usize] = 1.0f64
        } else if q < p {
            let (g, ge) = tmm(a, s, s, p, q, q)
            if ge != ok { ret (none, ge) }
            let (qv, qe) = top_eigvec(a, g, q)
            if qe != ok { ret (none, qe) }
            j = 0usize
            while j < q {
                qa[j] = qv[j]
                j += 1usize
            }
        } else {
            let (st, ste) = mem.alloc[f64](a, q * p)
            if ste != ok { ret (none, ste) }
            i = 0usize
            while i < p {
                j = 0usize
                while j < q {
                    st[j * p + i] = s[i * q + j]
                    j += 1usize
                }
                i += 1usize
            }
            let (g, ge) = mm(a, s, st, p, q, p)
            if ge != ok { ret (none, ge) }
            let (qv, qe) = top_eigvec(a, g, p)
            if qe != ok { ret (none, qe) }
            var nq = 0.0f64
            j = 0usize
            while j < q {
                var sm = 0.0f64
                i = 0usize
                while i < p {
                    sm += s[i * q + j] * qv[i]
                    i += 1usize
                }
                qa[j] = sm
                nq += sm * sm
                j += 1usize
            }
            nq = math.sqrt[f64](nq)
            j = 0usize
            while j < q {
                qa[j] = qa[j] / nq
                j += 1usize
            }
        }
        i = 0usize
        while i < p {
            var sm = 0.0f64
            j = 0usize
            while j < q {
                sm += s[i * q + j] * qa[j]
                j += 1usize
            }
            ra[i] = sm
            i += 1usize
        }
        i = 0usize
        var tmean = 0.0f64
        while i < n {
            var sm = 0.0f64
            var l = 0usize
            while l < p {
                sm += x[i * p + l] * ra[l]
                l += 1usize
            }
            ta[i] = sm
            tmean += sm
            i += 1usize
        }
        if doc {
            tmean = tmean / f64(n)
            i = 0usize
            while i < n {
                ta[i] = ta[i] - tmean
                i += 1usize
            }
        }
        let tnorm = math.sqrt[f64](dot(ta, ta))
        i = 0usize
        while i < n {
            ta[i] = ta[i] / tnorm
            i += 1usize
        }
        i = 0usize
        while i < p {
            ra[i] = ra[i] / tnorm
            i += 1usize
        }
        i = 0usize
        while i < p {
            var sm = 0.0f64
            var l = 0usize
            while l < n {
                sm += x[l * p + i] * ta[l]
                l += 1usize
            }
            pa[i] = sm
            va[i] = sm
            i += 1usize
        }
        j = 0usize
        while j < q {
            var sm = 0.0f64
            i = 0usize
            while i < n {
                sm += y[i * q + j] * ta[i]
                i += 1usize
            }
            qa[j] = sm
            j += 1usize
        }
        if ac > 0usize {
            var l = 0usize
            while l < ac {
                var d = 0.0f64
                i = 0usize
                while i < p {
                    d += vv[i * ncomp + l] * pa[i]
                    i += 1usize
                }
                i = 0usize
                while i < p {
                    va[i] = va[i] - d * vv[i * ncomp + l]
                    i += 1usize
                }
                l += 1usize
            }
        }
        let nv = math.sqrt[f64](dot(va, va))
        i = 0usize
        while i < p {
            va[i] = va[i] / nv
            i += 1usize
        }
        // S = S - v (v' S)
        j = 0usize
        while j < q {
            var d = 0.0f64
            i = 0usize
            while i < p {
                d += va[i] * s[i * q + j]
                i += 1usize
            }
            i = 0usize
            while i < p {
                s[i * q + j] = s[i * q + j] - va[i] * d
                i += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < p {
            rr[i * ncomp + ac] = ra[i]
            vv[i * ncomp + ac] = va[i]
            f.loadings[i * ncomp + ac] = pa[i]
            i += 1usize
        }
        j = 0usize
        while j < q {
            tq[ac * q + j] = qa[j]
            j += 1usize
        }
        i = 0usize
        while i < n {
            f.scores[i * ncomp + ac] = ta[i]
            i += 1usize
        }
        coef_at(f, rr, tq, p, q, ac)
        f.xvar[ac] = dot(pa, pa)
        ac += 1usize
    }
    var k = 0usize
    while k < ncomp {
        fitted_at(f, f.scores, tq, ym, n, q, k)
        k += 1usize
    }
    ret (f, ok)
}

// oscorespls.fit(X, Y, ncomp, center, tol, maxit)
fn oscorespls(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool, tol: f64, maxit: i64) -> (Pls, err) {
    var none: Pls = zero
    let (x, xm, e1) = centre(a, x0, n, p, doc)
    if e1 != ok { ret (none, e1) }
    let (y, ym, e2) = centre(a, y0, n, q, doc)
    if e2 != ok { ret (none, e2) }
    let (f, fe) = alloc_fit(a, n, p, q, ncomp)
    if fe != ok { ret (none, fe) }
    let (ww, e3) = mem.alloc[f64](a, p * ncomp)
    let (pp, e4) = mem.alloc[f64](a, p * ncomp)
    let (tq, e5) = mem.alloc[f64](a, ncomp * q)
    let (tsqs, e6) = mem.alloc[f64](a, ncomp)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (none, e3) }
    let (u, e7) = mem.alloc[f64](a, n)
    let (t, e8) = mem.alloc[f64](a, n)
    let (told, e9) = mem.alloc[f64](a, n)
    let (w, e10) = mem.alloc[f64](a, p)
    let (qa, e11) = mem.alloc[f64](a, q)
    let (pa, e12) = mem.alloc[f64](a, p)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (none, e7) }
    var ac = 0usize
    while ac < ncomp {
        var i = 0usize
        if q == 1usize {
            i = 0usize
            while i < n {
                u[i] = y[i]
                i += 1usize
            }
        } else {
            var best = 0usize
            var bv = -1.0f64
            var j = 0usize
            while j < q {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += y[i * q + j] * y[i * q + j]
                    i += 1usize
                }
                if s > bv {
                    bv = s
                    best = j
                }
                j += 1usize
            }
            i = 0usize
            while i < n {
                u[i] = y[i * q + best]
                told[i] = 0.0f64
                i += 1usize
            }
        }
        var nit = 0i64
        var stop = false
        var tsq = 0.0f64
        while !stop {
            nit += 1i64
            var nw = 0.0f64
            var j = 0usize
            while j < p {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += x[i * p + j] * u[i]
                    i += 1usize
                }
                w[j] = s
                nw += s * s
                j += 1usize
            }
            nw = math.sqrt[f64](nw)
            j = 0usize
            while j < p {
                w[j] = w[j] / nw
                j += 1usize
            }
            i = 0usize
            while i < n {
                var s = 0.0f64
                j = 0usize
                while j < p {
                    s += x[i * p + j] * w[j]
                    j += 1usize
                }
                t[i] = s
                i += 1usize
            }
            tsq = dot(t, t)
            j = 0usize
            while j < q {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += y[i * q + j] * (t[i] / tsq)
                    i += 1usize
                }
                qa[j] = s
                j += 1usize
            }
            if q == 1usize {
                stop = true
            } else {
                var diff = 0.0f64
                i = 0usize
                while i < n {
                    let d = (t[i] - told[i]) / t[i]
                    if d == d { diff += math.abs[f64](d) }
                    i += 1usize
                }
                if diff < tol {
                    stop = true
                } else {
                    var qn = 0.0f64
                    j = 0usize
                    while j < q {
                        qn += qa[j] * qa[j]
                        j += 1usize
                    }
                    i = 0usize
                    while i < n {
                        var s = 0.0f64
                        j = 0usize
                        while j < q {
                            s += y[i * q + j] * qa[j]
                            j += 1usize
                        }
                        u[i] = s / qn
                        told[i] = t[i]
                        i += 1usize
                    }
                    if nit >= maxit { stop = true }
                }
            }
        }
        var j = 0usize
        while j < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += x[i * p + j] * (t[i] / tsq)
                i += 1usize
            }
            pa[j] = s
            j += 1usize
        }
        i = 0usize
        while i < n {
            j = 0usize
            while j < p {
                x[i * p + j] = x[i * p + j] - t[i] * pa[j]
                j += 1usize
            }
            var jq = 0usize
            while jq < q {
                y[i * q + jq] = y[i * q + jq] - t[i] * qa[jq]
                jq += 1usize
            }
            f.scores[i * ncomp + ac] = t[i]
            i += 1usize
        }
        j = 0usize
        while j < p {
            ww[j * ncomp + ac] = w[j]
            pp[j * ncomp + ac] = pa[j]
            f.loadings[j * ncomp + ac] = pa[j]
            j += 1usize
        }
        j = 0usize
        while j < q {
            tq[ac * q + j] = qa[j]
            j += 1usize
        }
        tsqs[ac] = tsq
        ac += 1usize
    }
    // R = W (P' W)^-1: PW is upper bidiagonal-ish; solve for the inverse by back substitution on identity columns
    let (rr, re) = proj_from_pw(a, ww, pp, p, ncomp, q == 1usize)
    if re != ok { ret (none, re) }
    var k = 0usize
    while k < ncomp {
        coef_at(f, rr, tq, p, q, k)
        f.xvar[k] = 0.0f64
        var i = 0usize
        var s = 0.0f64
        while i < p {
            s += pp[i * ncomp + k] * pp[i * ncomp + k]
            i += 1usize
        }
        f.xvar[k] = s * tsqs[k]
        fitted_at(f, f.scores, tq, ym, n, q, k)
        k += 1usize
    }
    ret (f, ok)
}

// R = W (P' W)^-1 for the p by c matrices w and p (the inverse of the upper triangular P'W by back substitution; for one response the
// bidiagonal product form of the package)
fn proj_from_pw(a: *mem.Arena, w: []const f64, pm: []const f64, p: usize, c: usize, single: bool) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, p * c)
    if e != ok { ret (r, e) }
    if c == 1usize {
        var i = 0usize
        while i < p {
            r[i] = w[i]
            i += 1usize
        }
        ret (r, ok)
    }
    let (pw, e1) = mem.alloc[f64](a, c * c)
    let (inv, e2) = mem.alloc[f64](a, c * c)
    if e1 != ok { ret (r, e1) }
    if e2 != ok { ret (r, e2) }
    var i = 0usize
    while i < c {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += pm[l * c + i] * w[l * c + j]
                l += 1usize
            }
            pw[i * c + j] = s
            inv[i * c + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    if single {
        // PWinv[a, (a + 1):c] = cumprod(-PW[a + 1, a + 2 ...]) the package's bidiagonal formula
        i = 0usize
        while i < c {
            inv[i * c + i] = 1.0f64
            i += 1usize
        }
        i = 0usize
        while i + 1usize < c {
            var prod = 1.0f64
            var j = i + 1usize
            while j < c {
                prod = prod * (0.0f64 - pw[(j - 1usize) * c + j])
                inv[i * c + j] = prod
                j += 1usize
            }
            i += 1usize
        }
    } else {
        // backsolve(PW, I): upper triangular inverse
        var col = 0usize
        while col < c {
            var row = c
            while row > 0usize {
                row -= 1usize
                var s = 0.0f64
                if row == col { s = 1.0f64 }
                var j = row + 1usize
                while j < c {
                    s -= pw[row * c + j] * inv[j * c + col]
                    j += 1usize
                }
                inv[row * c + col] = s / pw[row * c + row]
            }
            col += 1usize
        }
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var l = 0usize
            while l < c {
                s += w[i * c + l] * inv[l * c + j]
                l += 1usize
            }
            r[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (r, ok)
}

// widekernelpls.fit(X, Y, ncomp, center, tol, maxit)
fn widekernelpls(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool, tol: f64, maxit: i64) -> (Pls, err) {
    var none: Pls = zero
    let (x, xm, e1) = centre(a, x0, n, p, doc)
    if e1 != ok { ret (none, e1) }
    let (y, ym, e2) = centre(a, y0, n, q, doc)
    if e2 != ok { ret (none, e2) }
    let (f, fe) = alloc_fit(a, n, p, q, ncomp)
    if fe != ok { ret (none, fe) }
    let (xxt, e3) = mem.alloc[f64](a, n * n)
    let (yyt, e4) = mem.alloc[f64](a, n * n)
    let (tt, e5) = mem.alloc[f64](a, n * ncomp)
    let (uu, e6) = mem.alloc[f64](a, n * ncomp)
    let (xres, e7) = mem.alloc[f64](a, ncomp)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (none, e3) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += x[i * p + l] * x[j * p + l]
                l += 1usize
            }
            xxt[i * n + j] = s
            var s2 = 0.0f64
            l = 0usize
            while l < q {
                s2 += y[i * q + l] * y[j * q + l]
                l += 1usize
            }
            yyt[i * n + j] = s2
            j += 1usize
        }
        i += 1usize
    }
    var xtot = 0.0f64
    i = 0usize
    while i < n {
        xtot += xxt[i * n + i]
        i += 1usize
    }
    let (t, e8) = mem.alloc[f64](a, n)
    let (told, e9) = mem.alloc[f64](a, n)
    let (u, e10) = mem.alloc[f64](a, n)
    let (g, e11) = mem.alloc[f64](a, n * n)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (none, e8) }
    var ac = 0usize
    while ac < ncomp {
        let mark = mem.mark(a)
        let (m1, me1) = mm(a, xxt, yyt, n, n, n)
        if me1 != ok { ret (none, me1) }
        let (m2, me2) = mm(a, m1, m1, n, n, n)
        if me2 != ok { ret (none, me2) }
        i = 0usize
        while i < n {
            told[i] = y[i * q]
            i += 1usize
        }
        var nit = 0i64
        var stop = false
        while !stop {
            nit += 1i64
            i = 0usize
            var nt = 0.0f64
            while i < n {
                var s = 0.0f64
                var l = 0usize
                while l < n {
                    s += m2[i * n + l] * told[l]
                    l += 1usize
                }
                t[i] = s
                nt += s * s
                i += 1usize
            }
            nt = math.sqrt[f64](nt)
            i = 0usize
            while i < n {
                t[i] = t[i] / nt
                i += 1usize
            }
            var diff = 0.0f64
            i = 0usize
            while i < n {
                let d = (t[i] - told[i]) / t[i]
                if d == d { diff += math.abs[f64](d) }
                i += 1usize
            }
            if diff < tol {
                stop = true
            } else {
                i = 0usize
                while i < n {
                    told[i] = t[i]
                    i += 1usize
                }
                if nit >= maxit { stop = true }
            }
        }
        i = 0usize
        var tu = 0.0f64
        while i < n {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += yyt[i * n + l] * t[l]
                l += 1usize
            }
            u[i] = s
            tu += t[i] * s
            i += 1usize
        }
        i = 0usize
        while i < n {
            u[i] = u[i] / tu
            i += 1usize
        }
        var wpw = 0.0f64
        i = 0usize
        while i < n {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += xxt[i * n + l] * u[l]
                l += 1usize
            }
            wpw += u[i] * s
            i += 1usize
        }
        wpw = math.sqrt[f64](wpw)
        i = 0usize
        while i < n {
            tt[i * ncomp + ac] = t[i] * wpw
            uu[i * ncomp + ac] = u[i] * wpw
            i += 1usize
        }
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                g[i * n + j] = 0.0f64 - t[i] * t[j]
                if i == j { g[i * n + j] += 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
        let (gx, ge1) = mm(a, g, xxt, n, n, n)
        if ge1 != ok { ret (none, ge1) }
        let (gxg, ge2) = mm(a, gx, g, n, n, n)
        if ge2 != ok { ret (none, ge2) }
        let (gy, ge3) = mm(a, g, yyt, n, n, n)
        if ge3 != ok { ret (none, ge3) }
        let (gyg, ge4) = mm(a, gy, g, n, n, n)
        if ge4 != ok { ret (none, ge4) }
        i = 0usize
        while i < n * n {
            xxt[i] = gxg[i]
            yyt[i] = gyg[i]
            i += 1usize
        }
        mem.reset(a, mark)
        var tr = 0.0f64
        i = 0usize
        while i < n {
            tr += xxt[i * n + i]
            i += 1usize
        }
        xres[ac] = tr
        ac += 1usize
    }
    let (ww, e12) = tmm(a, x, uu, n, p, ncomp)
    if e12 != ok { ret (none, e12) }
    let (pp, e13) = tmm(a, x, tt, n, p, ncomp)
    let (qq, e14) = tmm(a, y, tt, n, q, ncomp)
    if e13 != ok || e14 != ok { ret (none, e13) }
    var k = 0usize
    while k < ncomp {
        var nw = 0.0f64
        var tn = 0.0f64
        i = 0usize
        while i < p {
            nw += ww[i * ncomp + k] * ww[i * ncomp + k]
            i += 1usize
        }
        i = 0usize
        while i < n {
            tn += tt[i * ncomp + k] * tt[i * ncomp + k]
            i += 1usize
        }
        nw = math.sqrt[f64](nw)
        i = 0usize
        while i < p {
            ww[i * ncomp + k] = ww[i * ncomp + k] / nw
            pp[i * ncomp + k] = pp[i * ncomp + k] / tn
            i += 1usize
        }
        i = 0usize
        while i < q {
            qq[i * ncomp + k] = qq[i * ncomp + k] / tn
            i += 1usize
        }
        k += 1usize
    }
    let (rr, re) = proj_from_pw(a, ww, pp, p, ncomp, q == 1usize)
    if re != ok { ret (none, re) }
    let (tq, e15) = mem.alloc[f64](a, ncomp * q)
    if e15 != ok { ret (none, e15) }
    k = 0usize
    while k < ncomp {
        var j = 0usize
        while j < q {
            tq[k * q + j] = qq[j * ncomp + k]
            j += 1usize
        }
        k += 1usize
    }
    var prev = xtot
    k = 0usize
    while k < ncomp {
        coef_at(f, rr, tq, p, q, k)
        fitted_at(f, tt, tq, ym, n, q, k)
        f.xvar[k] = prev - xres[k]
        prev = xres[k]
        i = 0usize
        while i < p {
            f.loadings[i * ncomp + k] = pp[i * ncomp + k]
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n * ncomp {
        f.scores[i] = tt[i]
        i += 1usize
    }
    ret (f, ok)
}

// svdpc.fit(X, Y, ncomp, center): principal component regression through the eigen decomposition of X'X (R uses La.svd; scores and
// loadings agree up to sign, the coefficients and fitted values exactly)
fn svdpc(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool) -> (Pls, err) {
    var none: Pls = zero
    let (x, xm, e1) = centre(a, x0, n, p, doc)
    if e1 != ok { ret (none, e1) }
    let (y, ym, e2) = centre(a, y0, n, q, doc)
    if e2 != ok { ret (none, e2) }
    let (f, fe) = alloc_fit(a, n, p, q, ncomp)
    if fe != ok { ret (none, fe) }
    let (xtx, e3) = tmm(a, x, x, n, p, p)
    if e3 != ok { ret (none, e3) }
    let (vals, vecs, ee) = ic.eigen_sym(a, xtx, p)
    if ee != ok { ret (none, ee) }
    let (pm, e4) = mem.alloc[f64](a, p * ncomp)
    let (tq, e5) = mem.alloc[f64](a, ncomp * q)
    if e4 != ok || e5 != ok { ret (none, e4) }
    var k = 0usize
    while k < ncomp {
        var i = 0usize
        while i < p {
            pm[i * ncomp + k] = vecs[i * p + k]
            f.loadings[i * ncomp + k] = vecs[i * p + k]
            i += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            var l = 0usize
            while l < p {
                s += x[i * p + l] * vecs[l * p + k]
                l += 1usize
            }
            f.scores[i * ncomp + k] = s
            i += 1usize
        }
        var j = 0usize
        while j < q {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += f.scores[i * ncomp + k] * y[i * q + j]
                i += 1usize
            }
            tq[k * q + j] = s / vals[k]
            j += 1usize
        }
        f.xvar[k] = vals[k]
        k += 1usize
    }
    k = 0usize
    while k < ncomp {
        coef_at(f, pm, tq, p, q, k)
        fitted_at(f, f.scores, tq, ym, n, q, k)
        k += 1usize
    }
    ret (f, ok)
}

// the fit of `method` (0 kernelpls, 1 simpls, 2 oscorespls, 3 widekernelpls, 4 svdpc, 5 cppls) with the package's default tolerances
fn fit_method(a: *mem.Arena, method: u8, x: []const f64, y: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool) -> (Pls, err) {
    if method == 5u8 {
        let (fc, ec) = cppls(a, x, y, n, p, q, ncomp, doc)
        ret (fc, ec)
    }
    if method == 0u8 {
        let (f, e) = kernelpls(a, x, y, n, p, q, ncomp, doc)
        ret (f, e)
    }
    if method == 1u8 {
        let (f, e) = simpls(a, x, y, n, p, q, ncomp, doc)
        ret (f, e)
    }
    if method == 2u8 {
        let (f, e) = oscorespls(a, x, y, n, p, q, ncomp, doc, 1.4901161193847656e-8f64, 100i64)
        ret (f, e)
    }
    if method == 3u8 {
        let (f, e) = widekernelpls(a, x, y, n, p, q, ncomp, doc, 1.4901161193847656e-8f64, 100i64)
        ret (f, e)
    }
    let (f, e) = svdpc(a, x, y, n, p, q, ncomp, doc)
    ret (f, e)
}

type Cv = struct { press: []f64, press0: []f64, adj: []f64, ncomp: usize }

// mvrCv: cross-validation over the segments (seg[i] the 0-based segment of observation i, nseg segments); press and adj are q by ncomp
// row-major. ncomp is lowered to n - (the largest segment) - 1 when that is smaller, as the package does.
fn cross_validate(a: *mem.Arena, method: u8, x: []const f64, y: []const f64, n: usize, p: usize, q: usize, ncomp0: usize, doc: bool, seg: []const usize, nseg: usize) -> (Cv, err) {
    var none: Cv = zero
    var maxseg = 0usize
    var s = 0usize
    while s < nseg {
        var c = 0usize
        var i = 0usize
        while i < n {
            if seg[i] == s { c += 1usize }
            i += 1usize
        }
        if c > maxseg { maxseg = c }
        s += 1usize
    }
    var ncomp = ncomp0
    if n - maxseg - 1usize < ncomp { ncomp = n - maxseg - 1usize }
    let (press, e1) = mem.alloc[f64](a, q * ncomp)
    let (press0, e2) = mem.alloc[f64](a, q)
    let (adj, e3) = mem.alloc[f64](a, q * ncomp)
    let (cvp, e4) = mem.alloc[f64](a, n * q * ncomp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (none, e1) }
    var i = 0usize
    while i < q * ncomp {
        press[i] = 0.0f64
        adj[i] = 0.0f64
        i += 1usize
    }
    s = 0usize
    while s < nseg {
        let mark = mem.mark(a)
        var ntr = 0usize
        var nte = 0usize
        i = 0usize
        while i < n {
            if seg[i] == s { nte += 1usize } else { ntr += 1usize }
            i += 1usize
        }
        let (xt, e5) = mem.alloc[f64](a, ntr * p)
        let (yt, e6) = mem.alloc[f64](a, ntr * q)
        if e5 != ok || e6 != ok { ret (none, e5) }
        var r = 0usize
        i = 0usize
        while i < n {
            if seg[i] != s {
                var l = 0usize
                while l < p {
                    xt[r * p + l] = x[i * p + l]
                    l += 1usize
                }
                l = 0usize
                while l < q {
                    yt[r * q + l] = y[i * q + l]
                    l += 1usize
                }
                r += 1usize
            }
            i += 1usize
        }
        let (fit, fe) = fit_method(a, method, xt, yt, ntr, p, q, ncomp, doc)
        if fe != ok { ret (none, fe) }
        let (xs, xmeans, e7) = centre(a, xt, ntr, p, doc)
        let (ys, ymeans, e8) = centre(a, yt, ntr, q, doc)
        if e7 != ok || e8 != ok { ret (none, e7) }
        var ac = 0usize
        while ac < ncomp {
            var j = 0usize
            while j < q {
                var sse_all = 0.0f64
                i = 0usize
                while i < n {
                    var pr = ymeans[j]
                    var l = 0usize
                    while l < p {
                        pr += (x[i * p + l] - xmeans[l]) * fit.coef[ac * p * q + l * q + j]
                        l += 1usize
                    }
                    sse_all += (pr - y[i * q + j]) * (pr - y[i * q + j])
                    if seg[i] == s { cvp[(i * q + j) * ncomp + ac] = pr }
                    i += 1usize
                }
                adj[j * ncomp + ac] += f64(nte) * sse_all
                j += 1usize
            }
            ac += 1usize
        }
        mem.reset(a, mark)
        s += 1usize
    }
    var j = 0usize
    while j < q {
        var sm = 0.0f64
        i = 0usize
        while i < n {
            sm += y[i * q + j]
            i += 1usize
        }
        let mean = sm / f64(n)
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += (y[i * q + j] - mean) * (y[i * q + j] - mean)
            i += 1usize
        }
        press0[j] = (v / f64(n - 1usize)) * f64(n) * f64(n) / f64(n - 1usize)
        var ac = 0usize
        while ac < ncomp {
            var t = 0.0f64
            i = 0usize
            while i < n {
                let d = cvp[(i * q + j) * ncomp + ac] - y[i * q + j]
                t += d * d
                i += 1usize
            }
            press[j * ncomp + ac] = t
            adj[j * ncomp + ac] = adj[j * ncomp + ac] / (f64(n) * f64(n))
            ac += 1usize
        }
        j += 1usize
    }
    ret (Cv { press: press, press0: press0, adj: adj, ncomp: ncomp }, ok)
}

// the training sum of squared residuals of response j after `a` + 1 components, and the total sum of squares of the response
fn train_sse(f: Pls, y: []const f64, n: usize, q: usize, j: usize, ac: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        let d = y[i * q + j] - f.fitted[ac * n * q + i * q + j]
        s += d * d
        i += 1usize
    }
    ret s
}

// cppls.fit(X, Y, ncomp, center) with the default powers (lower = upper = 0.5, no Y.add): canonical powered PLS, each weight vector the first canonical direction of X W0 (W0 = X'Y) against Y mapped back through W0, the first canonical vector found by power iteration on Szz^-1 Szy Syy^-1 Syz; the coefficients and fitted values follow the plain loops of cppls.fit (signs of weights, scores and loadings are free, the coefficients and fits are not)
fn cppls(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool) -> (Pls, err) {
    var none: Pls = zero
    let (xo, xm, e1) = centre(a, x0, n, p, doc)
    if e1 != ok { ret (none, e1) }
    let (y, ym, e2) = centre(a, y0, n, q, doc)
    if e2 != ok { ret (none, e2) }
    let (f, fe) = alloc_fit(a, n, p, q, ncomp)
    if fe != ok { ret (none, fe) }
    let (x, e3) = mem.alloc[f64](a, n * p)
    let (ww, e4) = mem.alloc[f64](a, p * ncomp)
    let (pp, e5) = mem.alloc[f64](a, p * ncomp)
    let (qq, e6) = mem.alloc[f64](a, q * ncomp)
    let (tt, e7) = mem.alloc[f64](a, n * ncomp)
    let (tsqs, e8) = mem.alloc[f64](a, ncomp)
    let (pw, e9) = mem.alloc[f64](a, ncomp * ncomp)
    let (ipw, e10) = mem.alloc[f64](a, ncomp * ncomp)
    if e3 != ok { ret (none, e3) }
    if e4 != ok { ret (none, e4) }
    if e5 != ok { ret (none, e5) }
    if e6 != ok { ret (none, e6) }
    if e7 != ok { ret (none, e7) }
    if e8 != ok { ret (none, e8) }
    if e9 != ok { ret (none, e9) }
    if e10 != ok { ret (none, e10) }
    var i = 0usize
    while i < n * p {
        x[i] = xo[i]
        i += 1usize
    }
    let (syy, e11) = tmm(a, y, y, n, q, q)
    if e11 != ok { ret (none, e11) }
    let (syyi, e12) = mem.alloc[f64](a, q * q)
    if e12 != ok { ret (none, e12) }
    if !ps.invert(a, syy, q, syyi) { ret (none, e12) }
    let (v, e13) = mem.alloc[f64](a, q)
    let (v2, e14) = mem.alloc[f64](a, q)
    let (wa, e15) = mem.alloc[f64](a, p)
    let (ta, e16) = mem.alloc[f64](a, n)
    let (pa, e17) = mem.alloc[f64](a, p)
    if e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret (none, e13) }
    var ac = 0usize
    while ac < ncomp {
        let (w0, e20) = tmm(a, x, y, n, p, q)
        if e20 != ok { ret (none, e20) }
        let (z, e21) = mm(a, x, w0, n, p, q)
        if e21 != ok { ret (none, e21) }
        let (szz, e22) = tmm(a, z, z, n, q, q)
        let (szy, e23) = tmm(a, z, y, n, q, q)
        if e22 != ok { ret (none, e22) }
        if e23 != ok { ret (none, e23) }
        let (szzi, e24) = mem.alloc[f64](a, q * q)
        if e24 != ok { ret (none, e24) }
        if !ps.invert(a, szz, q, szzi) { ret (none, e24) }
        // M = Szz^-1 Szy Syy^-1 Szy'
        let (m1, e25) = mm(a, szzi, szy, q, q, q)
        if e25 != ok { ret (none, e25) }
        let (m2, e26) = mm(a, m1, syyi, q, q, q)
        if e26 != ok { ret (none, e26) }
        let (mt, e27) = mem.alloc[f64](a, q * q)
        if e27 != ok { ret (none, e27) }
        var r = 0usize
        while r < q {
            var c = 0usize
            while c < q {
                mt[r * q + c] = szy[c * q + r]
                c += 1usize
            }
            r += 1usize
        }
        let (mm3, e28) = mm(a, m2, mt, q, q, q)
        if e28 != ok { ret (none, e28) }
        r = 0usize
        while r < q {
            v[r] = 1.0f64 / math.sqrt[f64](f64(q))
            r += 1usize
        }
        var it = 0usize
        while it < 5000usize {
            var nv = 0.0f64
            r = 0usize
            while r < q {
                var s = 0.0f64
                var c = 0usize
                while c < q {
                    s += mm3[r * q + c] * v[c]
                    c += 1usize
                }
                v2[r] = s
                nv += s * s
                r += 1usize
            }
            nv = math.sqrt[f64](nv)
            var diff = 0.0f64
            r = 0usize
            while r < q {
                let nw = v2[r] / nv
                diff += math.abs[f64](nw - v[r])
                v[r] = nw
                r += 1usize
            }
            if diff < 1.0e-15f64 { break }
            it += 1usize
        }
        // a = Szz^-1 Szy Syy^-1 (Szy' ...) : the canonical vector of Z is Szz^-1 Szy u with u the Y-side eigenvector; v here is the Z-side eigenvector already
        i = 0usize
        while i < p {
            var s = 0.0f64
            var c = 0usize
            while c < q {
                s += w0[i * q + c] * v[c]
                c += 1usize
            }
            wa[i] = s
            i += 1usize
        }
        var nw = 0.0f64
        i = 0usize
        while i < p {
            nw += wa[i] * wa[i]
            i += 1usize
        }
        nw = math.sqrt[f64](nw)
        i = 0usize
        while i < p {
            wa[i] = wa[i] / nw
            i += 1usize
        }
        var tsq = 0.0f64
        i = 0usize
        while i < n {
            var s = 0.0f64
            var c = 0usize
            while c < p {
                s += x[i * p + c] * wa[c]
                c += 1usize
            }
            ta[i] = s
            tsq += s * s
            i += 1usize
        }
        i = 0usize
        while i < p {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += x[l * p + i] * ta[l]
                l += 1usize
            }
            pa[i] = s / tsq
            i += 1usize
        }
        var j = 0usize
        while j < q {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += y[i * q + j] * ta[i]
                i += 1usize
            }
            qq[j * ncomp + ac] = s / tsq
            j += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < p {
                x[i * p + c] -= ta[i] * pa[c]
                c += 1usize
            }
            tt[i * ncomp + ac] = ta[i]
            i += 1usize
        }
        i = 0usize
        while i < p {
            ww[i * ncomp + ac] = wa[i]
            pp[i * ncomp + ac] = pa[i]
            f.loadings[i * ncomp + ac] = pa[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            f.scores[i * ncomp + ac] = ta[i]
            i += 1usize
        }
        tsqs[ac] = tsq
        // B_a = W[, 1:a] (P[, 1:a]' W[, 1:a])^-1 Q[, 1:a]'
        let na = ac + 1usize
        let (sub, e30) = mem.alloc[f64](a, na * na)
        let (subi, e31) = mem.alloc[f64](a, na * na)
        if e30 != ok { ret (none, e30) }
        if e31 != ok { ret (none, e31) }
        var l1 = 0usize
        while l1 < na {
            var l2 = 0usize
            while l2 < na {
                var s = 0.0f64
                i = 0usize
                while i < p {
                    s += pp[i * ncomp + l1] * ww[i * ncomp + l2]
                    i += 1usize
                }
                sub[l1 * na + l2] = s
                l2 += 1usize
            }
            l1 += 1usize
        }
        if !ps.invert(a, sub, na, subi) { ret (none, e31) }
        i = 0usize
        while i < p {
            j = 0usize
            while j < q {
                var s = 0.0f64
                l1 = 0usize
                while l1 < na {
                    var l2 = 0usize
                    while l2 < na {
                        s += ww[i * ncomp + l1] * subi[l1 * na + l2] * qq[j * ncomp + l2]
                        l2 += 1usize
                    }
                    l1 += 1usize
                }
                f.coef[ac * p * q + i * q + j] = s
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            j = 0usize
            while j < q {
                var s = 0.0f64
                var c = 0usize
                while c < p {
                    s += xo[i * p + c] * f.coef[ac * p * q + c * q + j]
                    c += 1usize
                }
                f.fitted[ac * n * q + i * q + j] = s + ym[j]
                j += 1usize
            }
            i += 1usize
        }
        var xv = 0.0f64
        i = 0usize
        while i < p {
            xv += pa[i] * pa[i]
            i += 1usize
        }
        f.xvar[ac] = xv * tsq
        ac += 1usize
    }
    ret (f, ok)
}

// jack.test(model, ncomp, use.mean = TRUE) of a fit with segment-wise jackknife coefficients: sd[i * q + j] = sqrt((nseg - 1) mean_s (B_s - mean B)^2) of the coefficient of predictor i for response j at ncomp components, and the full-data coefficients in coef; the t values are coef / sd on nseg - 1 degrees of freedom
fn jack_test(a: *mem.Arena, method: u8, x: []const f64, y: []const f64, n: usize, p: usize, q: usize, ncomp: usize, doc: bool, seg: []const usize, nseg: usize, coef: []f64, sd: []f64) -> err {
    let (full, fe) = fit_method(a, method, x, y, n, p, q, ncomp, doc)
    if fe != ok { ret fe }
    let (bs, e1) = mem.alloc[f64](a, nseg * p * q)
    if e1 != ok { ret e1 }
    var s = 0usize
    while s < nseg {
        let start = mem.mark(a)
        var m = 0usize
        var i = 0usize
        while i < n {
            if seg[i] != s { m += 1usize }
            i += 1usize
        }
        let (xt, e2) = mem.alloc[f64](a, m * p)
        let (yt, e3) = mem.alloc[f64](a, m * q)
        if e2 != ok { ret e2 }
        if e3 != ok { ret e3 }
        var k = 0usize
        i = 0usize
        while i < n {
            if seg[i] != s {
                var c = 0usize
                while c < p {
                    xt[k * p + c] = x[i * p + c]
                    c += 1usize
                }
                c = 0usize
                while c < q {
                    yt[k * q + c] = y[i * q + c]
                    c += 1usize
                }
                k += 1usize
            }
            i += 1usize
        }
        let (ft, fe2) = fit_method(a, method, xt, yt, m, p, q, ncomp, doc)
        if fe2 != ok { ret fe2 }
        var c2 = 0usize
        while c2 < p * q {
            bs[s * p * q + c2] = ft.coef[(ncomp - 1usize) * p * q + c2]
            c2 += 1usize
        }
        s += 1usize
    }
    var c = 0usize
    while c < p * q {
        coef[c] = full.coef[(ncomp - 1usize) * p * q + c]
        var mean = 0.0f64
        s = 0usize
        while s < nseg {
            mean += bs[s * p * q + c]
            s += 1usize
        }
        mean = mean / f64(nseg)
        var ss = 0.0f64
        s = 0usize
        while s < nseg {
            let d = bs[s * p * q + c] - mean
            ss += d * d
            s += 1usize
        }
        sd[c] = math.sqrt[f64](f64(nseg - 1usize) * ss / f64(nseg))
        c += 1usize
    }
    ret ok
}
