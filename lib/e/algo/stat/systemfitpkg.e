// R systemfit "SUR": seemingly unrelated regressions of M equations on the same n observations, by feasible GLS. The residual covariance starts from the equation-by-equation OLS residuals and is re-estimated after each pass; the residual-covariance divisor is sqrt((n - k_i)(n - k_j)) ("geomean") or n ("noDfCor").
//
// Not here: unequal observation counts, cross-equation restrictions, 2SLS, 3SLS, WSUR, iteration to convergence, the "max" and "Theil" divisors.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// xs holds the M design matrices one after the other (equation m is n by ks[m], row-major, constant included); y is M columns of n values equation after equation; passes is the number of GLS passes.
// coef and se (sum of ks values each) and the final residual covariance (M by M) are filled
fn sur(a: *mem.Arena, xs: []const f64, ks: []const usize, y: []const f64, n: usize, m: usize, df_cor: bool, passes: usize, coef: []f64, se: []f64, sig: []f64) -> err {
    var kt = 0usize
    var e = 0usize
    while e < m {
        kt += ks[e]
        e += 1usize
    }
    let (off, e0) = mem.alloc[usize](a, m + 1usize)
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
                    if df_cor { dv = math.sqrt[f64](f64(n - ks[i]) * f64(n - ks[j])) }
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
            if df_cor { dv = math.sqrt[f64](f64(n - ks[i]) * f64(n - ks[j])) }
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
