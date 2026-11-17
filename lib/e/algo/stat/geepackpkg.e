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

// the mean, its derivative with respect to the linear predictor and the standard deviation of the response under beta, for the gaussian (0), binomial logit (1) and poisson log (2) families
fn gee_means(x: []const f64, n: usize, p: usize, beta: []const f64, family: usize, mu: []f64, dm: []f64, sd: []f64) {
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        var u = 0usize
        while u < p {
            eta += x[i * p + u] * beta[u]
            u += 1usize
        }
        if family == 0usize {
            mu[i] = eta
            dm[i] = 1.0f64
            sd[i] = 1.0f64
        } else if family == 1usize {
            let ee = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
            mu[i] = ee
            dm[i] = ee * (1.0f64 - ee)
            sd[i] = math.sqrt[f64](ee * (1.0f64 - ee))
        } else {
            let ee = math.exp[f64](eta)
            mu[i] = ee
            dm[i] = ee
            sd[i] = math.sqrt[f64](ee)
        }
        i += 1usize
    }
}

// H = sum_i D_i' V_i^-1 D_i and g = sum_i D_i' V_i^-1 (y_i - mu_i) with V_i^-1 = A^-1/2 R^-1 A^-1/2 (the scale cancels), and the middle of the sandwich sum_i s_i s_i' for the scores s_i
fn gee_blocks(x: []const f64, y: []const f64, k: usize, m: usize, p: usize, ri: []const f64, mu: []const f64, dm: []const f64, sd: []const f64, h: []f64, g: []f64, mid: []f64, sc: []f64) {
    var u = 0usize
    while u < p {
        g[u] = 0.0f64
        var v = 0usize
        while v < p {
            h[u * p + v] = 0.0f64
            mid[u * p + v] = 0.0f64
            v += 1usize
        }
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
                let ws = ri[s * m + t] * dm[c * m + s] / (sd[c * m + s] * sd[c * m + t])
                let w = ws * dm[c * m + t]
                let wy = ws * (y[c * m + t] - mu[c * m + t])
                u = 0usize
                while u < p {
                    g[u] += x[(c * m + s) * p + u] * wy
                    sc[u] += x[(c * m + s) * p + u] * wy
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
}

// geeglm for the gaussian, binomial (logit) and poisson (log) families with equal clusters of m consecutive rows and the independence, exchangeable or AR(1) working correlation (corstr 0, 1, 2):
// Fisher scoring of the estimating equation with Pearson-residual moment estimates of the scale and the correlation, started from the independence fit; returns (phi, alpha)
fn geeglm_glm(a: *mem.Arena, y: []const f64, x: []const f64, k: usize, m: usize, p: usize, family: usize, corstr: usize, beta: []f64, vb: []f64) -> (f64, f64, err) {
    let n = k * m
    let (r, e1) = mem.alloc[f64](a, m * m)
    let (ri, e2) = mem.alloc[f64](a, m * m)
    let (h, e3) = mem.alloc[f64](a, p * p)
    let (hi, e4) = mem.alloc[f64](a, p * p)
    let (g, e5) = mem.alloc[f64](a, p)
    let (mu, e6) = mem.alloc[f64](a, n)
    let (dm, e7) = mem.alloc[f64](a, n)
    let (sd, e8) = mem.alloc[f64](a, n)
    let (mid, e9) = mem.alloc[f64](a, p * p)
    let (sc, e10) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var u = 0usize
    while u < p {
        beta[u] = 0.0f64
        u += 1usize
    }
    var alpha = 0.0f64
    var phi = 1.0f64
    var stage = 0usize
    var iter = 0usize
    while iter < 500usize {
        gee_means(x, n, p, beta, family, mu, dm, sd)
        var i = 0usize
        while i < m {
            var j = 0usize
            while j < m {
                if i == j {
                    r[i * m + j] = 1.0f64
                } else if corstr == 1usize {
                    r[i * m + j] = alpha
                } else if corstr == 2usize {
                    var gap = i
                    if j > i { gap = j - i } else { gap = i - j }
                    r[i * m + j] = math.pow[f64](alpha, f64(gap))
                } else {
                    r[i * m + j] = 0.0f64
                }
                j += 1usize
            }
            i += 1usize
        }
        if ols.inverse(a, r, m, ri) != ok { ret (0.0f64, 0.0f64, mem.Full) }
        gee_blocks(x, y, k, m, p, ri, mu, dm, sd, h, g, mid, sc)
        if ols.inverse(a, h, p, hi) != ok { ret (0.0f64, 0.0f64, mem.Full) }
        var change = 0.0f64
        u = 0usize
        while u < p {
            var step = 0.0f64
            var v = 0usize
            while v < p {
                step += hi[u * p + v] * g[v]
                v += 1usize
            }
            if math.abs[f64](step) > change { change = math.abs[f64](step) }
            beta[u] += step
            u += 1usize
        }
        // Pearson residuals at the new beta: the scale and, once the beta has settled, the correlation
        gee_means(x, n, p, beta, family, mu, dm, sd)
        var ss = 0.0f64
        i = 0usize
        while i < n {
            let pr = (y[i] - mu[i]) / sd[i]
            ss += pr * pr
            i += 1usize
        }
        phi = ss / f64(n)
        if corstr != 0usize && (stage > 0usize || change < 1.0e-6f64) {
            var na = alpha
            if corstr == 1usize {
                var cross = 0.0f64
                var cnt = 0.0f64
                var c = 0usize
                while c < k {
                    var s = 0usize
                    while s < m {
                        var t = s + 1usize
                        while t < m {
                            cross += (y[c * m + s] - mu[c * m + s]) / sd[c * m + s] * (y[c * m + t] - mu[c * m + t]) / sd[c * m + t]
                            cnt += 1.0f64
                            t += 1usize
                        }
                        s += 1usize
                    }
                    c += 1usize
                }
                na = cross / phi / cnt
            } else {
                na = ar1_alpha(y, mu, sd, k, m, phi)
            }
            let dn = math.abs[f64](na - alpha)
            if dn > change { change = dn }
            alpha = na
            stage = 1usize
        }
        iter += 1usize
        if change < 1.0e-11f64 && (corstr == 0usize || stage > 0usize) { break }
    }
    // the sandwich at the converged fit
    gee_means(x, n, p, beta, family, mu, dm, sd)
    gee_blocks(x, y, k, m, p, ri, mu, dm, sd, h, g, mid, sc)
    if ols.inverse(a, h, p, hi) != ok { ret (0.0f64, 0.0f64, mem.Full) }
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

// the AR(1) correlation as geepack estimates it: the root in (-1, 1) of sum over cluster pairs s < t of (z_s z_t - a^(t-s)) (t-s) a^(t-s-1), the least squares fit of the lagged products of the scaled Pearson residuals
fn ar1_alpha(y: []const f64, mu: []const f64, sd: []const f64, k: usize, m: usize, phi: f64) -> f64 {
    var lo = 0.0f64 - 0.999f64
    var hi = 0.999f64
    var flo = ar1_score(y, mu, sd, k, m, phi, lo)
    var it = 0usize
    while it < 80usize {
        let mid = (lo + hi) / 2.0f64
        let fm = ar1_score(y, mu, sd, k, m, phi, mid)
        if (fm < 0.0f64) == (flo < 0.0f64) {
            lo = mid
            flo = fm
        } else {
            hi = mid
        }
        it += 1usize
    }
    ret (lo + hi) / 2.0f64
}

fn ar1_score(y: []const f64, mu: []const f64, sd: []const f64, k: usize, m: usize, phi: f64, al: f64) -> f64 {
    var tot = 0.0f64
    var c = 0usize
    while c < k {
        var s = 0usize
        while s < m {
            var t = s + 1usize
            while t < m {
                let lag = f64(t - s)
                let zz = (y[c * m + s] - mu[c * m + s]) / sd[c * m + s] * (y[c * m + t] - mu[c * m + t]) / sd[c * m + t] / phi
                tot += (zz - math.pow[f64](al, lag)) * lag * math.pow[f64](al, lag - 1.0f64)
                t += 1usize
            }
            s += 1usize
        }
        c += 1usize
    }
    ret tot
}
