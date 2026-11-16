// R geepack: geeglm for a Gaussian response with the identity link and equal-size clusters, with the independence or the exchangeable working correlation
// (Liang-Zeger moment estimates of the scale and the correlation) and the robust sandwich covariance.
//
// Not here: other families and links, unequal clusters, the AR(1), unstructured and fixed correlations, jackknife and bootstrap variances, geese and the Wald tests.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// fits y on x (n = k m rows, p columns, clusters of m consecutive rows) into beta (p), robust covariance (p by p) and returns (phi, alpha);
// exch is true for the exchangeable working correlation
fn geeglm_gaussian(a: *mem.Arena, y: []const f64, x: []const f64, k: usize, m: usize, p: usize, exch: bool, beta: []f64, vb: []f64) -> (f64, f64, err) {
    let n = k * m
    let (r, e1) = mem.alloc[f64](a, m * m)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let (ri, e2) = mem.alloc[f64](a, m * m)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    let (h, e3) = mem.alloc[f64](a, p * p)
    if e3 != ok { ret (0.0f64, 0.0f64, e3) }
    let (hi, e4) = mem.alloc[f64](a, p * p)
    if e4 != ok { ret (0.0f64, 0.0f64, e4) }
    let (g, e5) = mem.alloc[f64](a, p)
    if e5 != ok { ret (0.0f64, 0.0f64, e5) }
    let (res, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret (0.0f64, 0.0f64, e6) }
    var alpha = 0.0f64
    var phi = 1.0f64
    var iter = 0usize
    while iter < 100usize {
        // working correlation and its inverse
        var i = 0usize
        while i < m {
            var j = 0usize
            while j < m {
                if i == j { r[i * m + j] = 1.0f64 } else { r[i * m + j] = alpha }
                j += 1usize
            }
            i += 1usize
        }
        if ols.inverse(a, r, m, ri) != ok { ret (0.0f64, 0.0f64, e1) }
        var u = 0usize
        while u < p {
            g[u] = 0.0f64
            var v = 0usize
            while v < p {
                h[u * p + v] = 0.0f64
                v += 1usize
            }
            u += 1usize
        }
        var c = 0usize
        while c < k {
            var s = 0usize
            while s < m {
                var t = 0usize
                while t < m {
                    let w = ri[s * m + t]
                    u = 0usize
                    while u < p {
                        g[u] += x[(c * m + s) * p + u] * w * y[c * m + t]
                        var v = 0usize
                        while v < p {
                            h[u * p + v] += x[(c * m + s) * p + u] * w * x[(c * m + t) * p + v]
                            v += 1usize
                        }
                        u += 1usize
                    }
                    t += 1usize
                }
                s += 1usize
            }
            c += 1usize
        }
        if ols.inverse(a, h, p, hi) != ok { ret (0.0f64, 0.0f64, e1) }
        var change = 0.0f64
        u = 0usize
        while u < p {
            var nb = 0.0f64
            var v = 0usize
            while v < p {
                nb += hi[u * p + v] * g[v]
                v += 1usize
            }
            let dd = math.abs[f64](nb - beta[u])
            if dd > change { change = dd }
            beta[u] = nb
            u += 1usize
        }
        // residuals, scale and correlation
        var ss = 0.0f64
        i = 0usize
        while i < n {
            var fit = 0.0f64
            u = 0usize
            while u < p {
                fit += x[i * p + u] * beta[u]
                u += 1usize
            }
            res[i] = y[i] - fit
            ss += res[i] * res[i]
            i += 1usize
        }
        phi = ss / f64(n)
        if exch {
            var cross = 0.0f64
            c = 0usize
            while c < k {
                var s = 0usize
                while s < m {
                    var t = s + 1usize
                    while t < m {
                        cross += res[c * m + s] * res[c * m + t]
                        t += 1usize
                    }
                    s += 1usize
                }
                c += 1usize
            }
            let pairs = f64(k) * f64(m) * (f64(m) - 1.0f64) / 2.0f64
            let na = cross / phi / pairs
            let dn = math.abs[f64](na - alpha)
            if dn > change { change = dn }
            alpha = na
        }
        iter += 1usize
        if change < 1.0e-12f64 { break }
    }
    // the sandwich: H^-1 (sum_i X_i' R^-1 r_i r_i' R^-1 X_i) H^-1 (the scale cancels)
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            vb[u * p + v] = 0.0f64
            v += 1usize
        }
        u += 1usize
    }
    let (sc, e7) = mem.alloc[f64](a, p)
    if e7 != ok { ret (0.0f64, 0.0f64, e7) }
    let (mid, e8) = mem.alloc[f64](a, p * p)
    if e8 != ok { ret (0.0f64, 0.0f64, e8) }
    u = 0usize
    while u < p * p {
        mid[u] = 0.0f64
        u += 1usize
    }
    var c = 0usize
    while c < k {
        u = 0usize
        while u < p {
            sc[u] = 0.0f64
            u += 1usize
        }
        var s = 0usize
        while s < m {
            var t = 0usize
            while t < m {
                u = 0usize
                while u < p {
                    sc[u] += x[(c * m + s) * p + u] * ri[s * m + t] * res[c * m + t]
                    u += 1usize
                }
                t += 1usize
            }
            s += 1usize
        }
        u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                mid[u * p + v] += sc[u] * sc[v]
                v += 1usize
            }
            u += 1usize
        }
        c += 1usize
    }
    u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                var w = 0usize
                while w < p {
                    s += hi[u * p + q] * mid[q * p + w] * hi[w * p + v]
                    w += 1usize
                }
                q += 1usize
            }
            vb[u * p + v] = s
            v += 1usize
        }
        u += 1usize
    }
    ret (phi, alpha, ok)
}
