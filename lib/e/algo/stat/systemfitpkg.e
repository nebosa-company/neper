// R systemfit "SUR": seemingly unrelated regressions of M equations on the same n observations, by feasible GLS. The residual covariance starts from the equation-by-equation OLS residuals and is re-estimated after each pass; the residual-covariance divisor is sqrt((n - k_i)(n - k_j)) ("geomean") or n ("noDfCor").
//
// Not here: unequal observation counts, cross-equation restrictions, 2SLS, 3SLS, WSUR, iteration to convergence, the "max" and "Theil" divisors.

use e.algo.stat.gparot as gp
use e.math
use e.math.nmath as nmg
use e.math.nmath_beta as nbg
use e.mem

// xs holds the M design matrices one after the other (equation m is n by ks[m], row-major, constant included); y is M columns of n values equation after equation; passes is the number of GLS passes.
// coef and se (sum of ks values each) and the final residual covariance (M by M) are filled
fn sur(a: *mem.Arena, xs: []const f64, ks: []const usize, y: []const f64, n: usize, m: usize, df_cor: bool, passes: usize, coef: []f64, se: []f64, sig: []f64) -> err {
    var dv0 = 0usize
    if df_cor { dv0 = 1usize }
    var nul: [1]f64 = zero
    ret surm(a, xs, ks, y, n, m, dv0, passes, nul[0usize..1usize], nul[0usize..1usize], 0usize, coef, se, sig)
}

// sur with the residual covariance divisor chosen by div: 0 noDfCor (n), 1 geomean (sqrt((n - k_i)(n - k_j))), 2 max (n - max(k_i, k_j)), 3 Theil (n - k_i - k_j + tr(P_i P_j) with P_i = X_i (X_i'X_i)^-1 X_i')
fn surm(a: *mem.Arena, xs: []const f64, ks: []const usize, y: []const f64, n: usize, m: usize, div: usize, passes: usize, rr: []const f64, qq: []const f64, nr: usize, coef: []f64, se: []f64, sig: []f64) -> err {
    var kt = 0usize
    var e = 0usize
    while e < m {
        kt += ks[e]
        e += 1usize
    }
    let (off, e0) = mem.alloc[usize](a, m + 1usize)
    let (kd, ekd) = mem.alloc[usize](a, m)
    if ekd != ok { ret ekd }
    let (res, e1) = mem.alloc[f64](a, m * n)
    let (g, e2) = mem.alloc[f64](a, kt * kt)
    let (r, e3) = mem.alloc[f64](a, kt)
    let (sinv, e4) = mem.alloc[f64](a, m * m)
    if e0 != ok { ret e0 }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    off[0usize] = 0usize
    e = 0usize
    while e < m {
        off[e + 1usize] = off[e] + ks[e]
        e += 1usize
    }
    // degrees of freedom per equation: the coefficients less the restrictions that involve that equation alone
    e = 0usize
    while e < m {
        kd[e] = ks[e]
        var u0 = 0usize
        while u0 < nr {
            var inside = true
            var any = false
            var w0 = 0usize
            while w0 < kt {
                if rr[u0 * kt + w0] != 0.0f64 {
                    any = true
                    if w0 < off[e] || w0 >= off[e + 1usize] { inside = false }
                }
                w0 += 1usize
            }
            if any && inside { kd[e] -= 1usize }
            u0 += 1usize
        }
        e += 1usize
    }
    // the design matrix of equation e starts at element n * off[e]
    var pass = 0usize
    while pass <= passes {
        // residual covariance and its inverse
        if pass == 0usize {
            var i = 0usize
            while i < m * m {
                sinv[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < m {
                sinv[i * m + i] = 1.0f64
                i += 1usize
            }
        } else {
            var i = 0usize
            while i < m {
                var j = 0usize
                while j < m {
                    var s = 0.0f64
                    var t = 0usize
                    while t < n {
                        s += res[i * n + t] * res[j * n + t]
                        t += 1usize
                    }
                    var dv = f64(n)
                    if div == 1usize { dv = math.sqrt[f64](f64(n - kd[i]) * f64(n - kd[j])) }
                    if div == 2usize {
                        dv = f64(n - kd[i])
                        if kd[j] > kd[i] { dv = f64(n - kd[j]) }
                    }
                    if div == 3usize { dv = f64(n) - f64(ks[i]) - f64(ks[j]) + tr_pp(a, xs[n * off[i]..n * off[i] + n * ks[i]], xs[n * off[j]..n * off[j] + n * ks[j]], n, ks[i], ks[j]) }
                    sig[i * m + j] = s / dv
                    j += 1usize
                }
                i += 1usize
            }
            let (inv, ie) = gp.invert(a, sig, m)
            if ie != ok { ret ie }
            i = 0usize
            while i < m * m {
                sinv[i] = inv[i]
                i += 1usize
            }
        }
        // normal equations X'(Sinv kron I)X b = X'(Sinv kron I)y
        var i = 0usize
        while i < kt * kt {
            g[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < kt {
            r[i] = 0.0f64
            i += 1usize
        }
        var ei = 0usize
        while ei < m {
            var ej = 0usize
            while ej < m {
                let w = sinv[ei * m + ej]
                var p = 0usize
                while p < ks[ei] {
                    var q = 0usize
                    while q < ks[ej] {
                        var s = 0.0f64
                        var t = 0usize
                        while t < n {
                            s += xs[n * off[ei] + t * ks[ei] + p] * xs[n * off[ej] + t * ks[ej] + q]
                            t += 1usize
                        }
                        g[(off[ei] + p) * kt + off[ej] + q] += w * s
                        q += 1usize
                    }
                    var sy = 0.0f64
                    var t2 = 0usize
                    while t2 < n {
                        sy += xs[n * off[ei] + t2 * ks[ei] + p] * y[ej * n + t2]
                        t2 += 1usize
                    }
                    r[off[ei] + p] += w * sy
                    p += 1usize
                }
                ej += 1usize
            }
            ei += 1usize
        }
        let (gi, ge) = gp.invert(a, g, kt)
        if ge != ok { ret ge }
        i = 0usize
        while i < kt {
            var s = 0.0f64
            var j = 0usize
            while j < kt {
                s += gi[i * kt + j] * r[j]
                j += 1usize
            }
            coef[i] = s
            se[i] = math.sqrt[f64](gi[i * kt + i])
            i += 1usize
        }
        if nr > 0usize {
            // restricted GLS: beta_r = beta - gi R' (R gi R')^-1 (R beta - q), covariance gi - gi R' (R gi R')^-1 R gi
            let (rg, er1) = mem.alloc[f64](a, nr * kt)
            let (dm, er2) = mem.alloc[f64](a, nr * nr)
            let (lam, er3) = mem.alloc[f64](a, nr * (kt + 1usize))
            if er1 != ok || er2 != ok || er3 != ok { ret mem.Full }
            var u = 0usize
            while u < nr {
                var v = 0usize
                while v < kt {
                    var t = 0.0f64
                    var w = 0usize
                    while w < kt {
                        t += rr[u * kt + w] * gi[w * kt + v]
                        w += 1usize
                    }
                    rg[u * kt + v] = t
                    v += 1usize
                }
                u += 1usize
            }
            u = 0usize
            while u < nr {
                var v = 0usize
                while v < nr {
                    var t = 0.0f64
                    var w = 0usize
                    while w < kt {
                        t += rg[u * kt + w] * rr[v * kt + w]
                        w += 1usize
                    }
                    dm[u * nr + v] = t
                    v += 1usize
                }
                var rb = 0.0f64
                var w2 = 0usize
                while w2 < kt {
                    rb += rr[u * kt + w2] * coef[w2]
                    w2 += 1usize
                }
                lam[u * (kt + 1usize)] = rb - qq[u]
                var w3 = 0usize
                while w3 < kt {
                    lam[u * (kt + 1usize) + 1usize + w3] = rg[u * kt + w3]
                    w3 += 1usize
                }
                u += 1usize
            }
            // solve dm [lambda | rg] = [R beta - q | R gi]
            gj_solve(dm, nr, lam, kt + 1usize)
            var w4 = 0usize
            while w4 < kt {
                var db = 0.0f64
                var cv = 0.0f64
                var u2 = 0usize
                while u2 < nr {
                    db += rg[u2 * kt + w4] * lam[u2 * (kt + 1usize)]
                    u2 += 1usize
                }
                coef[w4] = coef[w4] - db
                var vv = 0.0f64
                u2 = 0usize
                while u2 < nr {
                    vv += rg[u2 * kt + w4] * lam[u2 * (kt + 1usize) + 1usize + w4]
                    u2 += 1usize
                }
                cv = gi[w4 * kt + w4] - vv
                se[w4] = math.sqrt[f64](cv)
                w4 += 1usize
            }
        }
        // residuals of this pass
        ei = 0usize
        while ei < m {
            var t = 0usize
            while t < n {
                var f = 0.0f64
                var p = 0usize
                while p < ks[ei] {
                    f += xs[n * off[ei] + t * ks[ei] + p] * coef[off[ei] + p]
                    p += 1usize
                }
                res[ei * n + t] = y[ei * n + t] - f
                t += 1usize
            }
            ei += 1usize
        }
        pass += 1usize
    }
    // the reported residual covariance comes from the residuals of the last pass
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += res[i * n + t] * res[j * n + t]
                t += 1usize
            }
            var dv = f64(n)
            if div == 1usize { dv = math.sqrt[f64](f64(n - kd[i]) * f64(n - kd[j])) }
            if div == 2usize {
                dv = f64(n - kd[i])
                if kd[j] > kd[i] { dv = f64(n - kd[j]) }
            }
            if div == 3usize { dv = f64(n) - f64(ks[i]) - f64(ks[j]) + tr_pp(a, xs[n * off[i]..n * off[i] + n * ks[i]], xs[n * off[j]..n * off[j] + n * ks[j]], n, ks[i], ks[j]) }
            sig[i * m + j] = s / dv
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// solve the k by k system m (row-major, destroyed) with the right-hand sides in the k by nr block rhs (row-major, overwritten by the solution) by Gauss-Jordan with partial pivoting
fn gj_solve(m: []f64, k: usize, rhs: []f64, nr: usize) {
    var col = 0usize
    while col < k {
        var piv = col
        var r = col + 1usize
        while r < k {
            if math.abs[f64](m[r * k + col]) > math.abs[f64](m[piv * k + col]) { piv = r }
            r += 1usize
        }
        var c = 0usize
        while c < k {
            let t = m[col * k + c]
            m[col * k + c] = m[piv * k + c]
            m[piv * k + c] = t
            c += 1usize
        }
        c = 0usize
        while c < nr {
            let t = rhs[col * nr + c]
            rhs[col * nr + c] = rhs[piv * nr + c]
            rhs[piv * nr + c] = t
            c += 1usize
        }
        let pv = m[col * k + col]
        c = 0usize
        while c < k {
            m[col * k + c] = m[col * k + c] / pv
            c += 1usize
        }
        c = 0usize
        while c < nr {
            rhs[col * nr + c] = rhs[col * nr + c] / pv
            c += 1usize
        }
        r = 0usize
        while r < k {
            if r != col {
                let f = m[r * k + col]
                c = 0usize
                while c < k {
                    m[r * k + c] -= f * m[col * k + c]
                    c += 1usize
                }
                c = 0usize
                while c < nr {
                    rhs[r * nr + c] -= f * rhs[col * nr + c]
                    c += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
}

// systemfit method "2SLS" for one equation: x (n by k) the regressors, z (n by q) the instruments (both row-major, constants included), y the response. The fitted regressors are x_hat = z (z'z)^-1 z' x, the coefficients (x_hat'x_hat)^-1 x_hat'y,
// the residuals use the actual x, sigma^2 = rss / (n - k), and the standard errors come from sigma^2 (x_hat'x_hat)^-1; coef and se hold k values, the answer is sigma^2
fn twosls(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, n: usize, k: usize, q: usize, coef: []f64, se: []f64) -> (f64, err) {
    let (zz, e0) = mem.alloc[f64](a, q * q)
    let (zx, e1) = mem.alloc[f64](a, q * k)
    let (xh, e2) = mem.alloc[f64](a, n * k)
    let (g, e3) = mem.alloc[f64](a, k * k)
    let (gi, e4) = mem.alloc[f64](a, k * k)
    let (xy, e5) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += z[r * q + i] * z[r * q + j]
                r += 1usize
            }
            zz[i * q + j] = s
            j += 1usize
        }
        j = 0usize
        while j < k {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += z[r * q + i] * x[r * k + j]
                r += 1usize
            }
            zx[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
    // zx <- (z'z)^-1 z'x, then x_hat = z * that
    gj_solve(zz, q, zx, k)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var l = 0usize
            while l < q {
                s += z[i * q + l] * zx[l * k + j]
                l += 1usize
            }
            xh[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += xh[r * k + i] * xh[r * k + j]
                r += 1usize
            }
            g[i * k + j] = s
            gi[i * k + j] = 0.0f64
            j += 1usize
        }
        gi[i * k + i] = 1.0f64
        var s2 = 0.0f64
        var r2 = 0usize
        while r2 < n {
            s2 += xh[r2 * k + i] * y[r2]
            r2 += 1usize
        }
        xy[i] = s2
        i += 1usize
    }
    gj_solve(g, k, gi, k)
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += gi[i * k + j] * xy[j]
            j += 1usize
        }
        coef[i] = s
        i += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        var f = 0.0f64
        var j = 0usize
        while j < k {
            f += x[i * k + j] * coef[j]
            j += 1usize
        }
        rss += (y[i] - f) * (y[i] - f)
        i += 1usize
    }
    let s2v = rss / f64(n - k)
    i = 0usize
    while i < k {
        se[i] = math.sqrt[f64](s2v * gi[i * k + i])
        i += 1usize
    }
    ret (s2v, ok)
}

// systemfit method "3SLS" with one instrument set z (n by q) for every equation: equation-wise 2SLS residuals give the residual covariance (the geometric-mean divisor sqrt((n - k_i)(n - k_j))), then the GLS
// estimator on the projected regressors, beta = [X_hat'(S^-1 x I)X_hat]^-1 X_hat'(S^-1 x I) y; xs and y are laid out as for `sur` (equation after equation); coef and se hold sum(ks) values
fn threesls_z(a: *mem.Arena, xs: []const f64, ks: []const usize, zs: []const f64, qs: []const usize, y: []const f64, n: usize, m: usize, coef: []f64, se: []f64) -> err {
    var itn: [1]usize = zero
    var nul: [1]f64 = zero
    ret threesls_it(a, xs, ks, zs, qs, y, n, m, 1usize, 0.0f64 - 1.0f64, nul[0usize..1usize], nul[0usize..1usize], 0usize, itn[0usize..1usize], coef, se)
}

// iterated 3SLS (control maxiter, tol): passes GLS steps at most, the residual covariance of each step taken from the previous coefficients (the 2SLS ones for the first), stopping once the relative change sqrt(sum((b - b_old)^2) / sum(b_old^2)) is at most tol (tol < 0 never stops early); itn[0] receives the passes made
fn threesls_it(a: *mem.Arena, xs: []const f64, ks: []const usize, zs: []const f64, qs: []const usize, y: []const f64, n: usize, m: usize, passes: usize, tol: f64, rr: []const f64, qq: []const f64, nr: usize, itn: []usize, coef: []f64, se: []f64) -> err {
    var kt = 0usize
    var e = 0usize
    while e < m {
        kt += ks[e]
        e += 1usize
    }
    let (off, e0) = mem.alloc[usize](a, m + 1usize)
    let (xh, e1) = mem.alloc[f64](a, n * kt)
    let (res, e2) = mem.alloc[f64](a, m * n)
    let (sg, e3) = mem.alloc[f64](a, m * m)
    let (sgi, e4) = mem.alloc[f64](a, m * m)
    let (g, e5) = mem.alloc[f64](a, kt * kt)
    let (gi, e6) = mem.alloc[f64](a, kt * kt)
    let (r, e7) = mem.alloc[f64](a, kt)
    let (old, e7b) = mem.alloc[f64](a, kt)
    if e7b != ok { ret mem.Full }
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    off[0usize] = 0usize
    e = 0usize
    while e < m {
        off[e + 1usize] = off[e] + ks[e]
        e += 1usize
    }
    let (kd, ekd) = mem.alloc[usize](a, m)
    if ekd != ok { ret ekd }
    e = 0usize
    while e < m {
        kd[e] = ks[e]
        var u0 = 0usize
        while u0 < nr {
            var inside = true
            var any = false
            var w0 = 0usize
            while w0 < kt {
                if rr[u0 * kt + w0] != 0.0f64 {
                    any = true
                    if w0 < off[e] || w0 >= off[e + 1usize] { inside = false }
                }
                w0 += 1usize
            }
            if any && inside { kd[e] -= 1usize }
            u0 += 1usize
        }
        e += 1usize
    }
    var xoff = 0usize
    var zoff = 0usize
    e = 0usize
    while e < m {
        let k = ks[e]
        let q = qs[e]
        let z = zs[zoff..zoff + n * q]
        let xe = xs[xoff..xoff + n * k]
        let (cf, ec) = mem.alloc[f64](a, k)
        let (sf, es) = mem.alloc[f64](a, k)
        if ec != ok || es != ok { ret mem.Full }
        let (v, et) = twosls(a, xe, z, y[e * n..(e + 1usize) * n], n, k, q, cf, sf)
        let _ = v
        if et != ok { ret et }
        var cq = 0usize
        while cq < k {
            old[off[e] + cq] = cf[cq]
            cq += 1usize
        }
        var i = 0usize
        while i < n {
            var f = 0.0f64
            var j = 0usize
            while j < k {
                f += xe[i * k + j] * cf[j]
                j += 1usize
            }
            res[e * n + i] = y[e * n + i] - f
            i += 1usize
        }
        let (zz, ez) = mem.alloc[f64](a, q * q)
        let (zx, ex) = mem.alloc[f64](a, q * k)
        if ez != ok || ex != ok { ret mem.Full }
        var u = 0usize
        while u < q {
            var w = 0usize
            while w < q {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += z[i * q + u] * z[i * q + w]
                    i += 1usize
                }
                zz[u * q + w] = s
                w += 1usize
            }
            w = 0usize
            while w < k {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += z[i * q + u] * xe[i * k + w]
                    i += 1usize
                }
                zx[u * k + w] = s
                w += 1usize
            }
            u += 1usize
        }
        gj_solve(zz, q, zx, k)
        i = 0usize
        while i < n {
            var j = 0usize
            while j < k {
                var s = 0.0f64
                var l = 0usize
                while l < q {
                    s += z[i * q + l] * zx[l * k + j]
                    l += 1usize
                }
                xh[i * kt + off[e] + j] = s
                j += 1usize
            }
            i += 1usize
        }
        xoff += n * k
        zoff += n * q
        e += 1usize
    }
    if nr > 0usize {
        // restricted two-stage least squares as the first step: restricted OLS on the projected regressors, its residuals (from the actual regressors) giving the first residual covariance
        let (g0, e30) = mem.alloc[f64](a, kt * kt)
        let (gi0, e31) = mem.alloc[f64](a, kt * kt)
        let (b0, e32) = mem.alloc[f64](a, kt)
        let (se0, e33) = mem.alloc[f64](a, kt)
        if e30 != ok || e31 != ok || e32 != ok || e33 != ok { ret mem.Full }
        var u1 = 0usize
        while u1 < kt {
            var v1 = 0usize
            while v1 < kt {
                g0[u1 * kt + v1] = 0.0f64
                gi0[u1 * kt + v1] = 0.0f64
                v1 += 1usize
            }
            gi0[u1 * kt + u1] = 1.0f64
            u1 += 1usize
        }
        var eq0 = 0usize
        while eq0 < m {
            var a0 = 0usize
            while a0 < ks[eq0] {
                var b1 = 0usize
                while b1 < ks[eq0] {
                    var sv = 0.0f64
                    var i0 = 0usize
                    while i0 < n {
                        sv += xh[i0 * kt + off[eq0] + a0] * xh[i0 * kt + off[eq0] + b1]
                        i0 += 1usize
                    }
                    g0[(off[eq0] + a0) * kt + off[eq0] + b1] = sv
                    b1 += 1usize
                }
                var sy = 0.0f64
                var i1 = 0usize
                while i1 < n {
                    sy += xh[i1 * kt + off[eq0] + a0] * y[eq0 * n + i1]
                    i1 += 1usize
                }
                b0[off[eq0] + a0] = sy
                a0 += 1usize
            }
            eq0 += 1usize
        }
        gj_solve(g0, kt, gi0, kt)
        var u2 = 0usize
        while u2 < kt {
            var sv = 0.0f64
            var v2 = 0usize
            while v2 < kt {
                sv += gi0[u2 * kt + v2] * b0[v2]
                v2 += 1usize
            }
            se0[u2] = sv
            u2 += 1usize
        }
        var ii = 0usize
        while ii < kt {
            b0[ii] = se0[ii]
            ii += 1usize
        }
        let er0 = restrict_adjust(a, gi0, b0, se0, rr, qq, nr, kt)
        if er0 != ok { ret er0 }
        var xo0 = 0usize
        eq0 = 0usize
        while eq0 < m {
            var t0 = 0usize
            while t0 < n {
                var f0 = 0.0f64
                var j0 = 0usize
                while j0 < ks[eq0] {
                    f0 += xs[xo0 + t0 * ks[eq0] + j0] * b0[off[eq0] + j0]
                    j0 += 1usize
                }
                res[eq0 * n + t0] = y[eq0 * n + t0] - f0
                t0 += 1usize
            }
            xo0 += n * ks[eq0]
            eq0 += 1usize
        }
        ii = 0usize
        while ii < kt {
            old[ii] = b0[ii]
            ii += 1usize
        }
    }
    var pass3 = 0usize
    while pass3 < passes {
        var p1 = 0usize
        while p1 < m {
            var p2 = 0usize
            while p2 < m {
                var s = 0.0f64
                var i = 0usize
                while i < n {
                    s += res[p1 * n + i] * res[p2 * n + i]
                    i += 1usize
                }
                sg[p1 * m + p2] = s / math.sqrt[f64](f64(n - kd[p1]) * f64(n - kd[p2]))
                sgi[p1 * m + p2] = 0.0f64
                p2 += 1usize
            }
            sgi[p1 * m + p1] = 1.0f64
            p1 += 1usize
        }
        gj_solve(sg, m, sgi, m)
        var i1 = 0usize
        while i1 < m {
            var j1 = 0usize
            while j1 < m {
                var a1 = 0usize
                while a1 < ks[i1] {
                    var b1 = 0usize
                    while b1 < ks[j1] {
                        var s = 0.0f64
                        var i = 0usize
                        while i < n {
                            s += xh[i * kt + off[i1] + a1] * xh[i * kt + off[j1] + b1]
                            i += 1usize
                        }
                        g[(off[i1] + a1) * kt + off[j1] + b1] = sgi[i1 * m + j1] * s
                        b1 += 1usize
                    }
                    a1 += 1usize
                }
                j1 += 1usize
            }
            var a2 = 0usize
            while a2 < ks[i1] {
                var s = 0.0f64
                var j2 = 0usize
                while j2 < m {
                    var i = 0usize
                    while i < n {
                        s += sgi[i1 * m + j2] * xh[i * kt + off[i1] + a2] * y[j2 * n + i]
                        i += 1usize
                    }
                    j2 += 1usize
                }
                r[off[i1] + a2] = s
                a2 += 1usize
            }
            i1 += 1usize
        }
        var q2 = 0usize
        while q2 < kt {
            var w2 = 0usize
            while w2 < kt {
                gi[q2 * kt + w2] = 0.0f64
                w2 += 1usize
            }
            gi[q2 * kt + q2] = 1.0f64
            q2 += 1usize
        }
        gj_solve(g, kt, gi, kt)
        q2 = 0usize
        while q2 < kt {
            var s = 0.0f64
            var w3 = 0usize
            while w3 < kt {
                s += gi[q2 * kt + w3] * r[w3]
                w3 += 1usize
            }
            coef[q2] = s
            se[q2] = math.sqrt[f64](gi[q2 * kt + q2])
            q2 += 1usize
        }
        if nr > 0usize {
            let er = restrict_adjust(a, gi, coef, se, rr, qq, nr, kt)
            if er != ok { ret er }
        }

        // residuals from the new coefficients, and the change of the coefficient vector
        var num = 0.0f64
        var den = 0.0f64
        var qq0 = 0usize
        while qq0 < kt {
            num += (coef[qq0] - old[qq0]) * (coef[qq0] - old[qq0])
            den += old[qq0] * old[qq0]
            old[qq0] = coef[qq0]
            qq0 += 1usize
        }
        var xo2 = 0usize
        var eq5 = 0usize
        while eq5 < m {
            var t5 = 0usize
            while t5 < n {
                var f5 = 0.0f64
                var j5 = 0usize
                while j5 < ks[eq5] {
                    f5 += xs[xo2 + t5 * ks[eq5] + j5] * coef[off[eq5] + j5]
                    j5 += 1usize
                }
                res[eq5 * n + t5] = y[eq5 * n + t5] - f5
                t5 += 1usize
            }
            xo2 += n * ks[eq5]
            eq5 += 1usize
        }
        itn[0usize] = pass3 + 1usize
        if tol >= 0.0f64 && math.sqrt[f64](num / den) <= tol { break }
        pass3 += 1usize
    }
    ret ok
}

// systemfit 3SLS with one instrument set (n by q) shared by every equation
fn threesls(a: *mem.Arena, xs: []const f64, ks: []const usize, z: []const f64, q: usize, y: []const f64, n: usize, m: usize, coef: []f64, se: []f64) -> err {
    let (zs, e0) = mem.alloc[f64](a, m * n * q)
    let (qs, e1) = mem.alloc[usize](a, m)
    if e0 != ok || e1 != ok { ret mem.Full }
    var e = 0usize
    while e < m {
        qs[e] = q
        var i = 0usize
        while i < n * q {
            zs[e * n * q + i] = z[i]
            i += 1usize
        }
        e += 1usize
    }
    ret threesls_z(a, xs, ks, zs, qs, y, n, m, coef, se)
}

// systemfit SUR iterated to convergence (control maxiter, tol): GLS passes are repeated while sqrt(sum((b - b_old)^2) / sum(b_old^2)) exceeds tol, the first pass being compared with the OLS coefficients; answers the number of passes made, and coef, se, sig are those of the last pass
fn sur_iter(a: *mem.Arena, xs: []const f64, ks: []const usize, y: []const f64, n: usize, m: usize, df_cor: bool, maxiter: usize, tol: f64, coef: []f64, se: []f64, sig: []f64) -> (usize, err) {
    var kt = 0usize
    var e = 0usize
    while e < m {
        kt += ks[e]
        e += 1usize
    }
    let (old, e0) = mem.alloc[f64](a, kt)
    let (s0, e1) = mem.alloc[f64](a, kt)
    if e0 != ok || e1 != ok { ret (0usize, mem.Full) }
    let e2 = sur(a, xs, ks, y, n, m, df_cor, 0usize, old, s0, sig)
    if e2 != ok { ret (0usize, e2) }
    var it = 1usize
    while it <= maxiter {
        let e3 = sur(a, xs, ks, y, n, m, df_cor, it, coef, se, sig)
        if e3 != ok { ret (0usize, e3) }
        var num = 0.0f64
        var den = 0.0f64
        var j = 0usize
        while j < kt {
            num += (coef[j] - old[j]) * (coef[j] - old[j])
            den += old[j] * old[j]
            old[j] = coef[j]
            j += 1usize
        }
        if math.sqrt[f64](num / den) <= tol { ret (it, ok) }
        it += 1usize
    }
    ret (maxiter, ok)
}

// tr(P_i P_j) for the projections P = X (X'X)^-1 X' of two row-major designs (n by ki and n by kj): the sum of the elementwise products of (X_i'X_i)^-1 X_i'X_j (X_j'X_j)^-1 and X_j'X_i
fn tr_pp(a: *mem.Arena, xi: []const f64, xj: []const f64, n: usize, ki: usize, kj: usize) -> f64 {
    let (gi, e0) = mem.alloc[f64](a, ki * ki)
    let (gj, e1) = mem.alloc[f64](a, kj * kj)
    let (cij, e2) = mem.alloc[f64](a, ki * kj)
    if e0 != ok || e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var p = 0usize
    while p < ki {
        var q = 0usize
        while q < ki {
            var v = 0.0f64
            var t = 0usize
            while t < n {
                v += xi[t * ki + p] * xi[t * ki + q]
                t += 1usize
            }
            gi[p * ki + q] = v
            q += 1usize
        }
        q = 0usize
        while q < kj {
            var v = 0.0f64
            var t = 0usize
            while t < n {
                v += xi[t * ki + p] * xj[t * kj + q]
                t += 1usize
            }
            cij[p * kj + q] = v
            q += 1usize
        }
        p += 1usize
    }
    p = 0usize
    while p < kj {
        var q = 0usize
        while q < kj {
            var v = 0.0f64
            var t = 0usize
            while t < n {
                v += xj[t * kj + p] * xj[t * kj + q]
                t += 1usize
            }
            gj[p * kj + q] = v
            q += 1usize
        }
        p += 1usize
    }
    // A = (Xi'Xi)^-1 Xi'Xj (ki by kj), B = (Xj'Xj)^-1 Xj'Xi (kj by ki) = ... tr(A B) with Xj'Xi = cij'
    let (ct, e3) = mem.alloc[f64](a, kj * ki)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    p = 0usize
    while p < ki {
        var q = 0usize
        while q < kj {
            ct[q * ki + p] = cij[p * kj + q]
            q += 1usize
        }
        p += 1usize
    }
    gj_solve(gi, ki, cij, kj)
    gj_solve(gj, kj, ct, ki)
    var tr = 0.0f64
    p = 0usize
    while p < ki {
        var q = 0usize
        while q < kj {
            tr += cij[p * kj + q] * ct[q * ki + p]
            q += 1usize
        }
        p += 1usize
    }
    ret tr
}

// linearHypothesis(fit, R, q) for a systemfit fit: the Wald statistic W = (R b - q)'[R V R']^-1 (R b - q) from the coefficients b (kt), their covariance V (kt by kt, row-major), R (nr by kt, row-major) and q (nr);
// out[0] = W (the Chisq test), out[1] its chi-square p-value on nr degrees of freedom, out[2] the p-value of the F test W / nr on (nr, df2) degrees of freedom
fn wald_test(a: *mem.Arena, b: []const f64, v: []const f64, rr: []const f64, qq: []const f64, nr: usize, kt: usize, df2: f64, out: []f64) -> err {
    let (rv, e0) = mem.alloc[f64](a, nr * kt)
    let (d, e1) = mem.alloc[f64](a, nr * nr)
    let (x, e2) = mem.alloc[f64](a, nr)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var u = 0usize
    while u < nr {
        var w = 0usize
        while w < kt {
            var t = 0.0f64
            var l = 0usize
            while l < kt {
                t += rr[u * kt + l] * v[l * kt + w]
                l += 1usize
            }
            rv[u * kt + w] = t
            w += 1usize
        }
        u += 1usize
    }
    u = 0usize
    while u < nr {
        var w = 0usize
        while w < nr {
            var t = 0.0f64
            var l = 0usize
            while l < kt {
                t += rv[u * kt + l] * rr[w * kt + l]
                l += 1usize
            }
            d[u * nr + w] = t
            w += 1usize
        }
        var rb = 0.0f64
        var l2 = 0usize
        while l2 < kt {
            rb += rr[u * kt + l2] * b[l2]
            l2 += 1usize
        }
        x[u] = rb - qq[u]
        u += 1usize
    }
    // solve d z = x, W = x'z
    let (z, e3) = mem.alloc[f64](a, nr)
    if e3 != ok { ret mem.Full }
    u = 0usize
    while u < nr {
        z[u] = x[u]
        u += 1usize
    }
    gj_solve(d, nr, z, 1usize)
    var wst = 0.0f64
    u = 0usize
    while u < nr {
        wst += x[u] * z[u]
        u += 1usize
    }
    out[0usize] = wst
    out[1usize] = nmg.pchisq(wst, f64(nr), false, false)
    out[2usize] = nbg.pf(wst / f64(nr), f64(nr), df2, false, false)
    ret ok
}

// the restricted GLS correction of a solved system: coef <- coef - gi R'(R gi R')^-1 (R coef - q), se from gi - gi R'(R gi R')^-1 R gi (gi the kt by kt unrestricted covariance, row-major)
fn restrict_adjust(a: *mem.Arena, gi: []const f64, coef: []f64, se: []f64, rr: []const f64, qq: []const f64, nr: usize, kt: usize) -> err {
    // restricted GLS: beta_r = beta - gi R' (R gi R')^-1 (R beta - q), covariance gi - gi R' (R gi R')^-1 R gi
    let (rg, er1) = mem.alloc[f64](a, nr * kt)
    let (dm, er2) = mem.alloc[f64](a, nr * nr)
    let (lam, er3) = mem.alloc[f64](a, nr * (kt + 1usize))
    if er1 != ok || er2 != ok || er3 != ok { ret mem.Full }
    var u = 0usize
    while u < nr {
        var v = 0usize
        while v < kt {
            var t = 0.0f64
            var w = 0usize
            while w < kt {
                t += rr[u * kt + w] * gi[w * kt + v]
                w += 1usize
            }
            rg[u * kt + v] = t
            v += 1usize
        }
        u += 1usize
    }
    u = 0usize
    while u < nr {
        var v = 0usize
        while v < nr {
            var t = 0.0f64
            var w = 0usize
            while w < kt {
                t += rg[u * kt + w] * rr[v * kt + w]
                w += 1usize
            }
            dm[u * nr + v] = t
            v += 1usize
        }
        var rb = 0.0f64
        var w2 = 0usize
        while w2 < kt {
            rb += rr[u * kt + w2] * coef[w2]
            w2 += 1usize
        }
        lam[u * (kt + 1usize)] = rb - qq[u]
        var w3 = 0usize
        while w3 < kt {
            lam[u * (kt + 1usize) + 1usize + w3] = rg[u * kt + w3]
            w3 += 1usize
        }
        u += 1usize
    }
    // solve dm [lambda | rg] = [R beta - q | R gi]
    gj_solve(dm, nr, lam, kt + 1usize)
    var w4 = 0usize
    while w4 < kt {
        var db = 0.0f64
        var cv = 0.0f64
        var u2 = 0usize
        while u2 < nr {
            db += rg[u2 * kt + w4] * lam[u2 * (kt + 1usize)]
            u2 += 1usize
        }
        coef[w4] = coef[w4] - db
        var vv = 0.0f64
        u2 = 0usize
        while u2 < nr {
            vv += rg[u2 * kt + w4] * lam[u2 * (kt + 1usize) + 1usize + w4]
            u2 += 1usize
        }
        cv = gi[w4 * kt + w4] - vv
        se[w4] = math.sqrt[f64](cv)
        w4 += 1usize
    }
    ret ok
}
