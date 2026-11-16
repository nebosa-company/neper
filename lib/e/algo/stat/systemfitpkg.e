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
