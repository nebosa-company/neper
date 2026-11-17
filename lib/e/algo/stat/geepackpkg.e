// R geepack: geeglm for a Gaussian response with the identity link and equal-size clusters, with the independence or the exchangeable working correlation
// (Liang-Zeger moment estimates of the scale and the correlation) and the robust sandwich covariance.
//
// gee_fit is the general engine (geese/geeglm: any cluster sizes, gaussian, binomial, poisson and Gamma with their links, independence, exchangeable, AR(1), unstructured and fixed
// working correlations, robust, naive, one-step (also approximate) and fully iterated jackknife covariances); gee_qic and gee_wald_seq are QIC and anova.geeglm; ordgee_fit is ordgee with independence and ordgee_gee with the exchangeable and unstructured odds ratios (a port of geepack ordgee.cc).
//
// Not here: the covariances of the scale and correlation parameters (vgamma, valpha), a scale model (zsca), weights, offsets, bootstrap.

use e.algo.stat.carlmtest as ols
use e.math
use e.math.dist as dist
use e.math.nmath as nm
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

// ---- the general engine: any cluster sizes, links, the five working correlations, the variance estimators, QIC and the sequential Wald table ----
// codes: family 0 gaussian, 1 binomial, 2 poisson, 3 Gamma; link 0 identity, 1 logit, 2 probit, 3 cloglog, 4 log, 5 inverse;
// corstr 0 independence, 1 exchangeable, 2 ar1, 3 unstructured, 4 fixed (R = zc, a maxm by maxm table of the correlations between the waves)

// mean and its derivative with respect to the linear predictor
fn gee_link(link: usize, eta: f64) -> (f64, f64) {
    if link == 0usize { ret (eta, 1.0f64) }
    if link == 1usize {
        let ee = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        ret (ee, ee * (1.0f64 - ee))
    }
    if link == 2usize { ret (dist.pnorm(eta, 0.0f64, 1.0f64, true, false), dist.dnorm(eta, 0.0f64, 1.0f64, false)) }
    if link == 3usize {
        let ex = math.exp[f64](eta)
        ret (1.0f64 - math.exp[f64](0.0f64 - ex), math.exp[f64](eta - ex))
    }
    if link == 4usize {
        let ee = math.exp[f64](eta)
        ret (ee, ee)
    }
    ret (1.0f64 / eta, 0.0f64 - 1.0f64 / (eta * eta))
}

fn gee_linkfun(link: usize, mu: f64) -> f64 {
    if link == 0usize { ret mu }
    if link == 1usize { ret math.log[f64](mu / (1.0f64 - mu)) }
    if link == 2usize { ret dist.qnorm(mu, 0.0f64, 1.0f64, true, false) }
    if link == 3usize { ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - mu)) }
    if link == 4usize { ret math.log[f64](mu) }
    ret 1.0f64 / mu
}

fn gee_sd(fam: usize, mu: f64) -> f64 {
    if fam == 0usize { ret 1.0f64 }
    if fam == 1usize { ret math.sqrt[f64](mu * (1.0f64 - mu)) }
    if fam == 2usize { ret math.sqrt[f64](mu) }
    ret mu
}

fn gee_means2(x: []const f64, n: usize, p: usize, beta: []const f64, fam: usize, link: usize, mu: []f64, dm: []f64, sd: []f64) {
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        var u = 0usize
        while u < p {
            eta += x[i * p + u] * beta[u]
            u += 1usize
        }
        let (m1, d1) = gee_link(link, eta)
        mu[i] = m1
        dm[i] = d1
        sd[i] = gee_sd(fam, m1)
        i += 1usize
    }
}

fn gee_nalpha(corstr: usize, maxm: usize) -> usize {
    if corstr == 0usize { ret 0usize }
    if corstr == 3usize { ret maxm * (maxm - 1usize) / 2usize }
    ret 1usize
}

// the m by m working correlation of a cluster
fn gee_cluster_r(r: []f64, m: usize, maxm: usize, corstr: usize, alpha: []const f64, zc: []const f64) {
    var s = 0usize
    while s < m {
        var t = 0usize
        while t < m {
            var v = 0.0f64
            if s == t {
                v = 1.0f64
            } else {
                var lo = s
                var hi = t
                if t < s {
                    lo = t
                    hi = s
                }
                if corstr == 1usize { v = alpha[0usize] }
                if corstr == 2usize { v = math.pow[f64](alpha[0usize], f64(hi - lo)) }
                if corstr == 3usize { v = alpha[lo * (maxm - 1usize) - lo * (lo + 1usize) / 2usize + hi - 1usize] }
                if corstr == 4usize { v = alpha[0usize] * zc[lo * maxm + hi] }
            }
            r[s * m + t] = v
            t += 1usize
        }
        s += 1usize
    }
}

// H, g and the per-cluster pieces H_i (hs) and U_i (us) over the clusters other than skip; mid = sum U_i U_i'
fn gee_blocks2(a: *mem.Arena, x: []const f64, y: []const f64, cs: []const usize, szu: []const usize, k: usize, p: usize, maxm: usize, corstr: usize, alpha: []const f64, zc: []const f64, mu: []const f64, dm: []const f64, sd: []const f64, skip: usize, h: []f64, g: []f64, mid: []f64, hs: []f64, us: []f64) -> err {
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
        if c == skip {
            c += 1usize
            continue
        }
        let m = szu[c]
        let o = cs[c]
        let mk = mem.mark(a)
        let (r, e1) = mem.alloc[f64](a, m * m)
        let (ri, e2) = mem.alloc[f64](a, m * m)
        if e1 != ok || e2 != ok { ret mem.Full }
        gee_cluster_r(r, m, maxm, corstr, alpha, zc)
        if ols.inverse(a, r, m, ri) != ok { ret mem.Full }
        u = 0usize
        while u < p {
            us[c * p + u] = 0.0f64
            var v = 0usize
            while v < p {
                hs[c * p * p + u * p + v] = 0.0f64
                v += 1usize
            }
            u += 1usize
        }
        var s = 0usize
        while s < m {
            var t = 0usize
            while t < m {
                let ws = ri[s * m + t] * dm[o + s] / (sd[o + s] * sd[o + t])
                let w = ws * dm[o + t]
                let wy = ws * (y[o + t] - mu[o + t])
                u = 0usize
                while u < p {
                    us[c * p + u] += x[(o + s) * p + u] * wy
                    var v = 0usize
                    while v < p {
                        hs[c * p * p + u * p + v] += x[(o + s) * p + u] * w * x[(o + t) * p + v]
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
            g[u] += us[c * p + u]
            var v = 0usize
            while v < p {
                h[u * p + v] += hs[c * p * p + u * p + v]
                mid[u * p + v] += us[c * p + u] * us[c * p + v]
                v += 1usize
            }
            u += 1usize
        }
        mem.reset(a, mk)
        c += 1usize
    }
    ret ok
}

fn gee_ar1_score2(z: []const f64, cs: []const usize, szu: []const usize, k: usize, skip: usize, phi: f64, al: f64) -> f64 {
    var tot = 0.0f64
    var c = 0usize
    while c < k {
        if c != skip {
            let o = cs[c]
            var s = 0usize
            while s < szu[c] {
                var t = s + 1usize
                while t < szu[c] {
                    let lag = f64(t - s)
                    tot += (z[o + s] * z[o + t] / phi - math.pow[f64](al, lag)) * lag * math.pow[f64](al, lag - 1.0f64)
                    t += 1usize
                }
                s += 1usize
            }
        }
        c += 1usize
    }
    ret tot
}

// the moment estimate of the correlation parameters from the scaled Pearson residuals z; returns the largest change
fn gee_alpha(z: []const f64, cs: []const usize, szu: []const usize, k: usize, maxm: usize, corstr: usize, skip: usize, phi: f64, alpha: []f64, sumb: []f64, cnt: []f64) -> f64 {
    var change = 0.0f64
    if corstr == 2usize {
        var lo = 0.0f64 - 0.999f64
        var hi = 0.999f64
        var flo = gee_ar1_score2(z, cs, szu, k, skip, phi, lo)
        var it = 0usize
        while it < 80usize {
            let mid = (lo + hi) / 2.0f64
            let fm = gee_ar1_score2(z, cs, szu, k, skip, phi, mid)
            if (fm < 0.0f64) == (flo < 0.0f64) {
                lo = mid
                flo = fm
            } else {
                hi = mid
            }
            it += 1usize
        }
        let na = (lo + hi) / 2.0f64
        change = math.abs[f64](na - alpha[0usize])
        alpha[0usize] = na
        ret change
    }
    let nal = gee_nalpha(corstr, maxm)
    var q = 0usize
    while q < nal {
        sumb[q] = 0.0f64
        cnt[q] = 0.0f64
        q += 1usize
    }
    var c = 0usize
    while c < k {
        if c != skip {
            let o = cs[c]
            var s = 0usize
            while s < szu[c] {
                var t = s + 1usize
                while t < szu[c] {
                    var idx = 0usize
                    if corstr == 3usize { idx = s * (maxm - 1usize) - s * (s + 1usize) / 2usize + t - 1usize }
                    sumb[idx] += z[o + s] * z[o + t]
                    cnt[idx] += 1.0f64
                    t += 1usize
                }
                s += 1usize
            }
        }
        c += 1usize
    }
    q = 0usize
    while q < nal {
        if cnt[q] > 0.0f64 {
            let na = sumb[q] / phi / cnt[q]
            let dn = math.abs[f64](na - alpha[q])
            if dn > change { change = dn }
            alpha[q] = na
        }
        q += 1usize
    }
    ret change
}

// the iteration: Fisher scoring in beta with Pearson-residual moment estimates of the scale and the correlation; the buffers h, mid, hs, us hold the blocks at the end
fn gee_core(a: *mem.Arena, y: []const f64, x: []const f64, cs: []const usize, szu: []const usize, k: usize, p: usize, maxm: usize, fam: usize, link: usize, corstr: usize, zc: []const f64, skip: usize, warm: bool, beta: []f64, alpha: []f64, h: []f64, mid: []f64, hs: []f64, us: []f64) -> (f64, err) {
    let n = cs[k - 1usize] + szu[k - 1usize]
    let nal = gee_nalpha(corstr, maxm)
    let (mu, e1) = mem.alloc[f64](a, n)
    let (dm, e2) = mem.alloc[f64](a, n)
    let (sd, e3) = mem.alloc[f64](a, n)
    let (z, e4) = mem.alloc[f64](a, n)
    let (hi, e5) = mem.alloc[f64](a, p * p)
    let (g, e6) = mem.alloc[f64](a, p)
    let (sumb, e7) = mem.alloc[f64](a, nal + 1usize)
    let (cnt, e8) = mem.alloc[f64](a, nal + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0.0f64, mem.Full) }
    var neff = 0usize
    var c = 0usize
    while c < k {
        if c != skip { neff += szu[c] }
        c += 1usize
    }
    var u = 0usize
    if !warm {
        // the start: least squares of the link of a shifted response on x
        let (xtx, e9) = mem.alloc[f64](a, p * p)
        let (xti, e10) = mem.alloc[f64](a, p * p)
        let (xtz, e11) = mem.alloc[f64](a, p)
        if e9 != ok || e10 != ok || e11 != ok { ret (0.0f64, mem.Full) }
        u = 0usize
        while u < p {
            xtz[u] = 0.0f64
            var v = 0usize
            while v < p {
                xtx[u * p + v] = 0.0f64
                v += 1usize
            }
            u += 1usize
        }
        var i = 0usize
        while i < n {
            var inside = true
            c = 0usize
            if skip < k {
                if i >= cs[skip] && i < cs[skip] + szu[skip] { inside = false }
            }
            if inside {
                var ms = y[i]
                if fam == 1usize { ms = (y[i] + 0.5f64) / 2.0f64 }
                if fam == 2usize { ms = y[i] + 0.1f64 }
                let ez = gee_linkfun(link, ms)
                u = 0usize
                while u < p {
                    xtz[u] += x[i * p + u] * ez
                    var v = 0usize
                    while v < p {
                        xtx[u * p + v] += x[i * p + u] * x[i * p + v]
                        v += 1usize
                    }
                    u += 1usize
                }
            }
            i += 1usize
        }
        if ols.inverse(a, xtx, p, xti) != ok { ret (0.0f64, mem.Full) }
        u = 0usize
        while u < p {
            var s0 = 0.0f64
            var v = 0usize
            while v < p {
                s0 += xti[u * p + v] * xtz[v]
                v += 1usize
            }
            beta[u] = s0
            u += 1usize
        }
        var q0 = 0usize
        while q0 < nal {
            alpha[q0] = 0.0f64
            q0 += 1usize
        }
        if corstr == 4usize { alpha[0usize] = 1.0f64 }
    }
    var stage = 0usize
    if warm { stage = 1usize }
    var phi = 1.0f64
    var iter = 0usize
    while iter < 500usize {
        gee_means2(x, n, p, beta, fam, link, mu, dm, sd)
        if gee_blocks2(a, x, y, cs, szu, k, p, maxm, corstr, alpha, zc, mu, dm, sd, skip, h, g, mid, hs, us) != ok { ret (0.0f64, mem.Full) }
        if ols.inverse(a, h, p, hi) != ok { ret (0.0f64, mem.Full) }
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
        gee_means2(x, n, p, beta, fam, link, mu, dm, sd)
        var ss = 0.0f64
        var i = 0usize
        while i < n {
            z[i] = (y[i] - mu[i]) / sd[i]
            i += 1usize
        }
        c = 0usize
        while c < k {
            if c != skip {
                var s = 0usize
                while s < szu[c] {
                    ss += z[cs[c] + s] * z[cs[c] + s]
                    s += 1usize
                }
            }
            c += 1usize
        }
        phi = ss / f64(neff)
        if corstr >= 1usize && corstr <= 3usize && (stage > 0usize || change < 1.0e-6f64) {
            let dn = gee_alpha(z, cs, szu, k, maxm, corstr, skip, phi, alpha, sumb, cnt)
            if dn > change { change = dn }
            stage = 1usize
        }
        iter += 1usize
        if change < 1.0e-11f64 && (corstr == 0usize || corstr == 4usize || stage > 0usize) { break }
    }
    gee_means2(x, n, p, beta, fam, link, mu, dm, sd)
    if gee_blocks2(a, x, y, cs, szu, k, p, maxm, corstr, alpha, zc, mu, dm, sd, skip, h, g, mid, hs, us) != ok { ret (0.0f64, mem.Full) }
    ret (phi, ok)
}

// sandwich = hi mid hi into out (p by p)
fn gee_sandwich(hi: []const f64, mid: []const f64, p: usize, out: []f64) {
    var u = 0usize
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
            out[u * p + v] = s
            v += 1usize
        }
        u += 1usize
    }
}

// the output length of gee_fit for p coefficients: beta (p), then the p by p matrices robust, naive, one-step jackknife (j1s, also the approximate jackknife) and fully iterated jackknife (fij), then the correlation parameters
fn gee_out_len(p: usize, maxm: usize, corstr: usize) -> usize { ret p + 4usize * p * p + gee_nalpha(corstr, maxm) }

// the cluster sizes sz (k of them, rows consecutive); returns the scale; dofij false leaves the fij block zero
fn gee_fit(a: *mem.Arena, y: []const f64, x: []const f64, sz: []const f64, k: usize, p: usize, fam: usize, link: usize, corstr: usize, zc: []const f64, dofij: bool, out: []f64) -> (f64, err) {
    let (cs, e1) = mem.alloc[usize](a, k)
    let (szu, e2) = mem.alloc[usize](a, k)
    if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var maxm = 0usize
    var run = 0usize
    var c = 0usize
    while c < k {
        szu[c] = usize(sz[c])
        cs[c] = run
        run += szu[c]
        if szu[c] > maxm { maxm = szu[c] }
        c += 1usize
    }
    let nal = gee_nalpha(corstr, maxm)
    let pp = p * p
    let (h, e3) = mem.alloc[f64](a, pp)
    let (mid, e4) = mem.alloc[f64](a, pp)
    let (hs, e5) = mem.alloc[f64](a, k * pp)
    let (us, e6) = mem.alloc[f64](a, k * p)
    let (hi, e7) = mem.alloc[f64](a, pp)
    let (alpha, e8) = mem.alloc[f64](a, nal + 1usize)
    let (beta, e9) = mem.alloc[f64](a, p)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (0.0f64, mem.Full) }
    let (phi, ec) = gee_core(a, y, x, cs, szu, k, p, maxm, fam, link, corstr, zc, k, false, beta, alpha, h, mid, hs, us)
    if ec != ok { ret (0.0f64, ec) }
    if ols.inverse(a, h, p, hi) != ok { ret (0.0f64, mem.Full) }
    var u = 0usize
    while u < p {
        out[u] = beta[u]
        u += 1usize
    }
    gee_sandwich(hi, mid, p, out[p..p + pp])
    u = 0usize
    while u < pp {
        out[p + pp + u] = phi * hi[u]
        out[p + 3usize * pp + u] = 0.0f64
        u += 1usize
    }
    // the one-step jackknife, scaled by (k - parameters) / k
    let kk = f64(k)
    let sc = (kk - f64(p + 1usize + nal)) / kk
    let (hl, e10) = mem.alloc[f64](a, pp)
    let (hli, e11) = mem.alloc[f64](a, pp)
    let (jm, e12) = mem.alloc[f64](a, pp)
    if e10 != ok || e11 != ok || e12 != ok { ret (0.0f64, mem.Full) }
    u = 0usize
    while u < pp {
        jm[u] = 0.0f64
        u += 1usize
    }
    c = 0usize
    while c < k {
        u = 0usize
        while u < pp {
            hl[u] = h[u] - hs[c * pp + u]
            u += 1usize
        }
        let mk = mem.mark(a)
        if ols.inverse(a, hl, p, hli) != ok { ret (0.0f64, mem.Full) }
        let (dl, e13) = mem.alloc[f64](a, p)
        if e13 != ok { ret (0.0f64, mem.Full) }
        u = 0usize
        while u < p {
            var s0 = 0.0f64
            var v = 0usize
            while v < p {
                s0 += hli[u * p + v] * us[c * p + v]
                v += 1usize
            }
            dl[u] = s0
            u += 1usize
        }
        u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                jm[u * p + v] += dl[u] * dl[v]
                v += 1usize
            }
            u += 1usize
        }
        mem.reset(a, mk)
        c += 1usize
    }
    u = 0usize
    while u < pp {
        out[p + 2usize * pp + u] = sc * jm[u]
        u += 1usize
    }
    // the fully iterated jackknife: refit without each cluster from the full fit
    if dofij {
        let (b2, e14) = mem.alloc[f64](a, p)
        let (a2, e15) = mem.alloc[f64](a, nal + 1usize)
        if e14 != ok || e15 != ok { ret (0.0f64, mem.Full) }
        u = 0usize
        while u < pp {
            jm[u] = 0.0f64
            u += 1usize
        }
        c = 0usize
        while c < k {
            let mk = mem.mark(a)
            u = 0usize
            while u < p {
                b2[u] = beta[u]
                u += 1usize
            }
            u = 0usize
            while u < nal {
                a2[u] = alpha[u]
                u += 1usize
            }
            let (ph2, e16) = gee_core(a, y, x, cs, szu, k, p, maxm, fam, link, corstr, zc, c, true, b2, a2, hl, hli, hs, us)
            if e16 != ok { ret (0.0f64, e16) }
            u = 0usize
            while u < p {
                var v = 0usize
                while v < p {
                    jm[u * p + v] += (b2[u] - beta[u]) * (b2[v] - beta[v])
                    v += 1usize
                }
                u += 1usize
            }
            mem.reset(a, mk)
            c += 1usize
        }
        u = 0usize
        while u < pp {
            out[p + 3usize * pp + u] = sc * jm[u]
            u += 1usize
        }
    }
    u = 0usize
    while u < nal {
        out[p + 4usize * pp + u] = alpha[u]
        u += 1usize
    }
    ret (phi, ok)
}

fn gee_maxsize(sz: []const f64, k: usize) -> usize {
    var m = 0usize
    var c = 0usize
    while c < k {
        if usize(sz[c]) > m { m = usize(sz[c]) }
        c += 1usize
    }
    ret m
}

// QIC of geepack: out = (QIC, QICu, quasi likelihood, CIC (the trace term), parameters, QICC)
fn gee_qic(a: *mem.Arena, y: []const f64, x: []const f64, sz: []const f64, k: usize, p: usize, fam: usize, link: usize, corstr: usize, zc: []const f64, out: []f64) -> err {
    let maxm = gee_maxsize(sz, k)
    let pp = p * p
    var n = 0usize
    var c = 0usize
    while c < k {
        n += usize(sz[c])
        c += 1usize
    }
    let (o1, e1) = mem.alloc[f64](a, gee_out_len(p, maxm, corstr))
    let (o0, e2) = mem.alloc[f64](a, gee_out_len(p, maxm, 0usize))
    let (ai, e3) = mem.alloc[f64](a, pp)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let (ph1, e4) = gee_fit(a, y, x, sz, k, p, fam, link, corstr, zc, false, o1)
    if e4 != ok { ret e4 }
    let (ph0, e5) = gee_fit(a, y, x, sz, k, p, fam, link, 0usize, zc, false, o0)
    if e5 != ok { ret e5 }
    if ols.inverse(a, o0[p + pp..p + 2usize * pp], p, ai) != ok { ret mem.Full }
    var trace = 0.0f64
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            trace += ai[u * p + v] * o1[p + v * p + u]
            v += 1usize
        }
        u += 1usize
    }
    var quasi = 0.0f64
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        u = 0usize
        while u < p {
            eta += x[i * p + u] * o1[u]
            u += 1usize
        }
        let (mu, dmu) = gee_link(link, eta)
        if fam == 0usize { quasi -= (y[i] - mu) * (y[i] - mu) / 2.0f64 }
        if fam == 1usize { quasi += y[i] * math.log[f64](mu / (1.0f64 - mu)) + math.log[f64](1.0f64 - mu) }
        if fam == 2usize { quasi += y[i] * math.log[f64](mu) - mu }
        if fam == 3usize { quasi += 0.0f64 - y[i] / (mu - math.log[f64](mu)) }
        i += 1usize
    }
    let params = f64(p)
    let kpm = params + f64(gee_nalpha(corstr, maxm))
    let qic = 0.0f64 - 2.0f64 * (quasi - trace)
    out[0usize] = qic
    out[1usize] = 0.0f64 - 2.0f64 * (quasi - params)
    out[2usize] = quasi
    out[3usize] = trace
    out[4usize] = params
    out[5usize] = qic + 2.0f64 * kpm * (kpm + 1.0f64) / (f64(k) - kpm - 1.0f64)
    ret ok
}

// anova.geeglm: the sequential Wald table; assign gives each column of x its term (0 for the intercept), nvars the number of terms; out has 3 entries per row: df, Wald statistic, p value
fn gee_wald_seq(a: *mem.Arena, y: []const f64, x: []const f64, sz: []const f64, k: usize, p: usize, fam: usize, link: usize, corstr: usize, zc: []const f64, assign: []const f64, nvars: usize, out: []f64) -> err {
    let maxm = gee_maxsize(sz, k)
    var n = 0usize
    var c = 0usize
    while c < k {
        n += usize(sz[c])
        c += 1usize
    }
    var nfit = nvars
    if nfit == 0usize { nfit = 1usize }
    var hasint = 0usize
    if assign[0usize] == 0.0f64 { hasint = 1usize }
    var prev = 0usize
    var t = 0usize
    while t < nfit {
        // the columns of the terms up to t + 1 (all of them for the last fit)
        var pi = 0usize
        var u = 0usize
        while u < p {
            if t + 1usize == nfit || usize(assign[u]) <= t + 1usize { pi += 1usize }
            u += 1usize
        }
        let mk = mem.mark(a)
        let (xs, e1) = mem.alloc[f64](a, n * pi)
        let (o, e2) = mem.alloc[f64](a, gee_out_len(pi, maxm, corstr))
        if e1 != ok || e2 != ok { ret mem.Full }
        var i = 0usize
        while i < n {
            var col = 0usize
            u = 0usize
            while u < p {
                if t + 1usize == nfit || usize(assign[u]) <= t + 1usize {
                    xs[i * pi + col] = x[i * p + u]
                    col += 1usize
                }
                u += 1usize
            }
            i += 1usize
        }
        let (ph, e3) = gee_fit(a, y, xs, sz, k, pi, fam, link, corstr, zc, false, o)
        if e3 != ok { ret e3 }
        var df = pi - prev
        if t == 0usize { df = pi - hasint }
        let (vs, e4) = mem.alloc[f64](a, df * df)
        let (vi, e5) = mem.alloc[f64](a, df * df)
        if e4 != ok || e5 != ok { ret mem.Full }
        u = 0usize
        while u < df {
            var v = 0usize
            while v < df {
                vs[u * df + v] = o[pi + (pi - df + u) * pi + pi - df + v]
                v += 1usize
            }
            u += 1usize
        }
        if ols.inverse(a, vs, df, vi) != ok { ret mem.Full }
        var x2 = 0.0f64
        u = 0usize
        while u < df {
            var v = 0usize
            while v < df {
                x2 += o[pi - df + u] * vi[u * df + v] * o[pi - df + v]
                v += 1usize
            }
            u += 1usize
        }
        out[3usize * t] = f64(df)
        out[3usize * t + 1usize] = x2
        out[3usize * t + 2usize] = nm.pchisq(x2, f64(df), false, false)
        mem.reset(a, mk)
        prev = pi
        t += 1usize
    }
    ret ok
}

// ordgee with the independence working correlation: the cumulative indicators I(y > j), j = 1..nlev-1, of every observation follow the multinomial covariance
// V_jl = P(y > max(j, l)) - P(y > j) P(y > l); intercepts for the categories then the px covariates (no intercept column); link 1 logit, 2 probit, 3 cloglog
// out: beta (p = nlev - 1 + px), robust, naive and one-step jackknife covariances (p by p each)
fn ordgee_fit(a: *mem.Arena, ycat: []const f64, x: []const f64, sz: []const f64, k: usize, px: usize, nlev: usize, link: usize, out: []f64) -> err {
    let nc = nlev - 1usize
    let p = nc + px
    let pp = p * p
    var n = 0usize
    var c = 0usize
    while c < k {
        n += usize(sz[c])
        c += 1usize
    }
    let (beta, e1) = mem.alloc[f64](a, p)
    let (h, e2) = mem.alloc[f64](a, pp)
    let (hi, e3) = mem.alloc[f64](a, pp)
    let (g, e4) = mem.alloc[f64](a, p)
    let (mid, e5) = mem.alloc[f64](a, pp)
    let (hs, e6) = mem.alloc[f64](a, k * pp)
    let (us, e7) = mem.alloc[f64](a, k * p)
    let (mu, e8) = mem.alloc[f64](a, nc)
    let (dm, e9) = mem.alloc[f64](a, nc)
    let (vm, e10) = mem.alloc[f64](a, nc * nc)
    let (vi, e11) = mem.alloc[f64](a, nc * nc)
    let (dd, e12) = mem.alloc[f64](a, nc * p)
    let (tmp, e13) = mem.alloc[f64](a, nc * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    // start: the intercepts at the marginal link of P(y > j), slopes zero
    var j = 0usize
    while j < p {
        beta[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < nc {
        var cntj = 0.0f64
        var i0 = 0usize
        while i0 < n {
            if ycat[i0] > f64(j + 1usize) { cntj += 1.0f64 }
            i0 += 1usize
        }
        let pj = (cntj + 0.5f64) / (f64(n) + 1.0f64)
        beta[j] = gee_linkfun(link, pj)
        j += 1usize
    }
    var iter = 0usize
    var last = 0.0f64
    while iter < 200usize {
        // blocks at beta
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
        var o = 0usize
        c = 0usize
        while c < k {
            u = 0usize
            while u < p {
                us[c * p + u] = 0.0f64
                var v = 0usize
                while v < p {
                    hs[c * pp + u * p + v] = 0.0f64
                    v += 1usize
                }
                u += 1usize
            }
            var s = 0usize
            while s < usize(sz[c]) {
                let mk = mem.mark(a)
                j = 0usize
                while j < nc {
                    var eta = beta[j]
                    u = 0usize
                    while u < px {
                        eta += x[o * px + u] * beta[nc + u]
                        u += 1usize
                    }
                    let (m1, d1) = gee_link(link, eta)
                    mu[j] = m1
                    dm[j] = d1
                    j += 1usize
                }
                j = 0usize
                while j < nc {
                    var l = 0usize
                    while l < nc {
                        var mx = j
                        if l < j { mx = l }
                        vm[j * nc + l] = mu[mx] - mu[j] * mu[l]
                        l += 1usize
                    }
                    j += 1usize
                }
                if ols.inverse(a, vm, nc, vi) != ok { ret mem.Full }
                j = 0usize
                while j < nc {
                    u = 0usize
                    while u < p {
                        var dv = 0.0f64
                        if u == j { dv = dm[j] }
                        if u >= nc { dv = dm[j] * x[o * px + u - nc] }
                        dd[j * p + u] = dv
                        u += 1usize
                    }
                    j += 1usize
                }
                // tmp = Vi dd
                j = 0usize
                while j < nc {
                    u = 0usize
                    while u < p {
                        var sv = 0.0f64
                        var l = 0usize
                        while l < nc {
                            sv += vi[j * nc + l] * dd[l * p + u]
                            l += 1usize
                        }
                        tmp[j * p + u] = sv
                        u += 1usize
                    }
                    j += 1usize
                }
                j = 0usize
                while j < nc {
                    var yj = 0.0f64
                    if ycat[o] > f64(j + 1usize) { yj = 1.0f64 }
                    let rj = yj - mu[j]
                    u = 0usize
                    while u < p {
                        us[c * p + u] += tmp[j * p + u] * rj
                        var v = 0usize
                        while v < p {
                            hs[c * pp + u * p + v] += dd[j * p + u] * tmp[j * p + v]
                            v += 1usize
                        }
                        u += 1usize
                    }
                    j += 1usize
                }
                mem.reset(a, mk)
                o += 1usize
                s += 1usize
            }
            u = 0usize
            while u < p {
                g[u] += us[c * p + u]
                var v = 0usize
                while v < p {
                    h[u * p + v] += hs[c * pp + u * p + v]
                    mid[u * p + v] += us[c * p + u] * us[c * p + v]
                    v += 1usize
                }
                u += 1usize
            }
            c += 1usize
        }
        if ols.inverse(a, h, p, hi) != ok { ret mem.Full }
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
        last = change
        iter += 1usize
        if change < 1.0e-12f64 { break }
    }
    var u2 = 0usize
    while u2 < p {
        out[u2] = beta[u2]
        u2 += 1usize
    }
    gee_sandwich(hi, mid, p, out[p..p + pp])
    u2 = 0usize
    while u2 < pp {
        out[p + pp + u2] = hi[u2]
        u2 += 1usize
    }
    let kk = f64(k)
    let sc = (kk - f64(p)) / kk
    let (hl, e14) = mem.alloc[f64](a, pp)
    let (hli, e15) = mem.alloc[f64](a, pp)
    let (jm, e16) = mem.alloc[f64](a, pp)
    if e14 != ok || e15 != ok || e16 != ok { ret mem.Full }
    u2 = 0usize
    while u2 < pp {
        jm[u2] = 0.0f64
        u2 += 1usize
    }
    c = 0usize
    while c < k {
        u2 = 0usize
        while u2 < pp {
            hl[u2] = h[u2] - hs[c * pp + u2]
            u2 += 1usize
        }
        let mk = mem.mark(a)
        if ols.inverse(a, hl, p, hli) != ok { ret mem.Full }
        let (dl, e17) = mem.alloc[f64](a, p)
        if e17 != ok { ret mem.Full }
        u2 = 0usize
        while u2 < p {
            var s0 = 0.0f64
            var v = 0usize
            while v < p {
                s0 += hli[u2 * p + v] * us[c * p + v]
                v += 1usize
            }
            dl[u2] = s0
            u2 += 1usize
        }
        u2 = 0usize
        while u2 < p {
            var v = 0usize
            while v < p {
                jm[u2 * p + v] += dl[u2] * dl[v]
                v += 1usize
            }
            u2 += 1usize
        }
        mem.reset(a, mk)
        c += 1usize
    }
    u2 = 0usize
    while u2 < pp {
        out[p + 2usize * pp + u2] = sc * jm[u2]
        u2 += 1usize
    }
    ret ok
}

// ---- ordgee with the exchangeable (corstr 1) and unstructured (corstr 3) log odds-ratio structures, a port of geepack's ordgee.cc ----

fn ogs_odds2p11(psi: f64, m1: f64, m2: f64) -> f64 {
    if math.abs[f64](psi - 1.0f64) < 0.001f64 { ret m1 * m2 }
    let e1 = 1.0f64 + (m1 + m2) * (psi - 1.0f64)
    let s = math.sqrt[f64](e1 * e1 + 4.0f64 * psi * (1.0f64 - psi) * m1 * m2)
    ret 0.5f64 / (psi - 1.0f64) * (e1 - s)
}

// derivative of the joint probability with respect to the odds ratio
fn ogs_p11_odds(psi: f64, m1: f64, m2: f64) -> f64 {
    if math.abs[f64](psi - 1.0f64) < 0.001f64 { ret m1 * m2 * (0.0f64 - (m1 + m2) + m1 * m2 + 1.0f64) }
    let ex1 = psi - 1.0f64
    let ex2 = 0.5f64 / ex1
    let ex3 = m1 + m2
    let ex5 = 1.0f64 + ex3 * ex1
    let ex7 = 4.0f64 * psi
    let ex8 = 1.0f64 - psi
    let ex9 = ex7 * ex8
    let ex10 = ex9 * m1
    let ex12 = ex5 * ex5 + ex10 * m2
    let ex14 = ex5 - math.sqrt[f64](ex12)
    let ex23 = 1.0f64 / math.sqrt[f64](ex12)
    ret ex2 * (ex3 - 0.5f64 * ((2.0f64 * (ex3 * ex5) + (4.0f64 * ex8 - ex7) * m1 * m2) * ex23)) - 0.5f64 / (ex1 * ex1) * ex14
}

// derivatives of the joint probability with respect to the two margins
fn ogs_p11_mu(psi: f64, m1: f64, m2: f64) -> (f64, f64) {
    if math.abs[f64](psi - 1.0f64) < 0.001f64 { ret (m2, m1) }
    let ex1 = psi - 1.0f64
    let ex2 = 0.5f64 / ex1
    let ex3 = m1 + m2
    let ex5 = 1.0f64 + ex3 * ex1
    let ex7 = 4.0f64 * psi
    let ex8 = 1.0f64 - psi
    let ex9 = ex7 * ex8
    let ex10 = ex9 * m1
    let ex12 = ex5 * ex5 + ex10 * m2
    let ex23 = 1.0f64 / math.sqrt[f64](ex12)
    let ex33 = 2.0f64 * (ex1 * ex5)
    ret (ex2 * (ex1 - 0.5f64 * ((ex33 + ex9 * m2) * ex23)), ex2 * (ex1 - 0.5f64 * ((ex33 + ex10) * ex23)))
}

fn ogs_min(i: usize, j: usize) -> usize {
    if i < j { ret i }
    ret j
}

// the working blocks of one cluster of m observations, each with c cumulative categories: means, link derivatives, residuals, the derivative matrix (mc by p) and the covariance (mc by mc)
fn ogs_build(ycat: []const f64, x: []const f64, o: usize, m: usize, c: usize, p: usize, px: usize, link: usize, corstr: usize, maxm: usize, beta: []const f64, alpha: []const f64, mu: []f64, pr: []f64, dd: []f64, vm: []f64) {
    let mc = m * c
    var s = 0usize
    while s < m {
        var j = 0usize
        while j < c {
            var eta = beta[j]
            var u = 0usize
            while u < px {
                eta += x[(o + s) * px + u] * beta[c + u]
                u += 1usize
            }
            let (m1, d1) = gee_link(link, eta)
            let r = s * c + j
            mu[r] = m1
            var yj = 0.0f64
            if ycat[o + s] > f64(j + 1usize) { yj = 1.0f64 }
            pr[r] = yj - m1
            u = 0usize
            while u < p {
                var dv = 0.0f64
                if u == j { dv = d1 }
                if u >= c { dv = d1 * x[(o + s) * px + u - c] }
                dd[r * p + u] = dv
                u += 1usize
            }
            j += 1usize
        }
        s += 1usize
    }
    var q = 0usize
    while q < mc * mc {
        vm[q] = 0.0f64
        q += 1usize
    }
    s = 0usize
    while s < m {
        var i = 0usize
        while i < c {
            var j = 0usize
            while j < c {
                vm[(s * c + i) * mc + s * c + j] = mu[s * c + ogs_min(i, j)] - mu[s * c + i] * mu[s * c + j]
                j += 1usize
            }
            i += 1usize
        }
        var t = s + 1usize
        while t < m {
            var idx = 0usize
            if corstr == 3usize { idx = s * (maxm - 1usize) - s * (s + 1usize) / 2usize + t - 1usize }
            let psi = math.exp[f64](alpha[idx])
            i = 0usize
            while i < c {
                var j = 0usize
                while j < c {
                    let v = ogs_odds2p11(psi, mu[s * c + i], mu[t * c + j]) - mu[s * c + i] * mu[t * c + j]
                    vm[(s * c + i) * mc + t * c + j] = v
                    vm[(t * c + i) * mc + s * c + j] = v
                    j += 1usize
                }
                i += 1usize
            }
            t += 1usize
        }
        s += 1usize
    }
}

// the pairwise moment equation of two observations: u2 = products of the residuals minus the joint covariance, d2 = its derivative in the log odds ratio, v2 = its working covariance
fn ogs_pair(a: *mem.Arena, pr1: []const f64, pr2: []const f64, mu1: []const f64, mu2: []const f64, psi: f64, c: usize, u2: []f64, d2: []f64, v2: []f64) -> err {
    let cc = c * c
    let (p11, e1) = mem.alloc[f64](a, cc)
    let (sg, e2) = mem.alloc[f64](a, cc)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < c {
        var j = 0usize
        while j < c {
            let k = i * c + j
            p11[k] = ogs_odds2p11(psi, mu1[i], mu2[j])
            sg[k] = p11[k] - mu1[i] * mu2[j]
            u2[k] = pr1[i] * pr2[j] - sg[k]
            d2[k] = ogs_p11_odds(psi, mu1[i], mu2[j]) * psi
            j += 1usize
        }
        i += 1usize
    }
    var c1 = 0usize
    while c1 < c {
        var c3 = c1
        while c3 < c {
            let c13 = ogs_min(c1, c3)
            var c2 = 0usize
            while c2 < c {
                var c4 = c2
                while c4 < c {
                    let c24 = ogs_min(c2, c4)
                    let v = p11[c13 * c + c24] - p11[c13 * c + c2] * mu2[c4] - p11[c13 * c + c4] * mu2[c2] + mu1[c13] * mu2[c2] * mu2[c4] - p11[c1 * c + c24] * mu1[c3] + p11[c1 * c + c2] * mu1[c3] * mu2[c4] + p11[c1 * c + c4] * mu1[c3] * mu2[c2] - 3.0f64 * mu1[c1] * mu1[c3] * mu2[c2] * mu2[c4] - p11[c3 * c + c24] * mu1[c1] + p11[c3 * c + c2] * mu1[c1] * mu2[c4] + p11[c3 * c + c4] * mu1[c1] * mu2[c2] + mu1[c1] * mu1[c3] * mu2[c24]
                    v2[(c1 * c + c2) * cc + c3 * c + c4] = v
                    v2[(c1 * c + c4) * cc + c3 * c + c2] = v
                    v2[(c3 * c + c2) * cc + c1 * c + c4] = v
                    v2[(c3 * c + c4) * cc + c1 * c + c2] = v
                    c4 += 1usize
                }
                c2 += 1usize
            }
            c3 += 1usize
        }
        c1 += 1usize
    }
    i = 0usize
    while i < cc {
        var j = 0usize
        while j < cc {
            v2[i * cc + j] -= sg[i] * sg[j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// ordgee with the exchangeable (corstr 1) or unstructured (corstr 3) odds-ratio working structure: the beta and alpha steps alternate as in geepack until the largest change is at most 1e-4 (25 iterations at most)
// out: beta (p = nlev - 1 + px), robust and naive covariances (p by p each), alpha (q), robust and naive covariances of alpha (q by q each)
fn ordgee_gee(a: *mem.Arena, ycat: []const f64, x: []const f64, sz: []const f64, k: usize, px: usize, nlev: usize, link: usize, corstr: usize, out: []f64) -> err {
    let c = nlev - 1usize
    let p = c + px
    let pp = p * p
    let maxm = gee_maxsize(sz, k)
    var q = 1usize
    if corstr == 3usize { q = maxm * (maxm - 1usize) / 2usize }
    let (beta, e1) = mem.alloc[f64](a, p)
    let (alpha, e2) = mem.alloc[f64](a, q)
    let (h, e3) = mem.alloc[f64](a, pp)
    let (hi, e4) = mem.alloc[f64](a, pp)
    let (g, e5) = mem.alloc[f64](a, p)
    let (hq, e6) = mem.alloc[f64](a, q * q)
    let (hqi, e7) = mem.alloc[f64](a, q * q)
    let (gq, e8) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var n = 0usize
    var cl = 0usize
    while cl < k {
        n += usize(sz[cl])
        cl += 1usize
    }
    // the start: the stacked binary regression of geepack's glm.fit
    var j = 0usize
    while j < p {
        beta[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < c {
        var cntj = 0.0f64
        var i0 = 0usize
        while i0 < n {
            if ycat[i0] > f64(j + 1usize) { cntj += 1.0f64 }
            i0 += 1usize
        }
        beta[j] = gee_linkfun(link, (cntj + 0.5f64) / (f64(n) + 1.0f64))
        j += 1usize
    }
    var it0 = 0usize
    while it0 < 100usize {
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
        var o = 0usize
        while o < n {
            j = 0usize
            while j < c {
                var eta = beta[j]
                u = 0usize
                while u < px {
                    eta += x[o * px + u] * beta[c + u]
                    u += 1usize
                }
                let (m1, d1) = gee_link(link, eta)
                var yj = 0.0f64
                if ycat[o] > f64(j + 1usize) { yj = 1.0f64 }
                let w = d1 * d1 / (m1 * (1.0f64 - m1))
                let sc0 = d1 * (yj - m1) / (m1 * (1.0f64 - m1))
                u = 0usize
                while u < p {
                    var xu = 0.0f64
                    if u == j { xu = 1.0f64 }
                    if u >= c { xu = x[o * px + u - c] }
                    g[u] += sc0 * xu
                    var v = 0usize
                    while v < p {
                        var xv = 0.0f64
                        if v == j { xv = 1.0f64 }
                        if v >= c { xv = x[o * px + v - c] }
                        h[u * p + v] += w * xu * xv
                        v += 1usize
                    }
                    u += 1usize
                }
                j += 1usize
            }
            o += 1usize
        }
        if ols.inverse(a, h, p, hi) != ok { ret mem.Full }
        var ch0 = 0.0f64
        u = 0usize
        while u < p {
            var st = 0.0f64
            var v = 0usize
            while v < p {
                st += hi[u * p + v] * g[v]
                v += 1usize
            }
            if math.abs[f64](st) > ch0 { ch0 = math.abs[f64](st) }
            beta[u] += st
            u += 1usize
        }
        it0 += 1usize
        if ch0 < 1.0e-13f64 { break }
    }
    j = 0usize
    while j < q {
        alpha[j] = 0.0f64
        j += 1usize
    }
    var iter = 0usize
    while iter < 25usize {
        // the beta step
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
        var o = 0usize
        cl = 0usize
        while cl < k {
            let m = usize(sz[cl])
            let mc = m * c
            let mk = mem.mark(a)
            let (mu, f1) = mem.alloc[f64](a, mc)
            let (pr, f2) = mem.alloc[f64](a, mc)
            let (dd, f3) = mem.alloc[f64](a, mc * p)
            let (vm, f4) = mem.alloc[f64](a, mc * mc)
            let (vi, f5) = mem.alloc[f64](a, mc * mc)
            if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok { ret mem.Full }
            ogs_build(ycat, x, o, m, c, p, px, link, corstr, maxm, beta, alpha, mu, pr, dd, vm)
            if ols.inverse(a, vm, mc, vi) != ok { ret mem.Full }
            var r = 0usize
            while r < mc {
                var t2 = 0usize
                while t2 < mc {
                    let w = vi[r * mc + t2]
                    u = 0usize
                    while u < p {
                        g[u] += dd[r * p + u] * w * pr[t2]
                        var v = 0usize
                        while v < p {
                            h[u * p + v] += dd[r * p + u] * w * dd[t2 * p + v]
                            v += 1usize
                        }
                        u += 1usize
                    }
                    t2 += 1usize
                }
                r += 1usize
            }
            mem.reset(a, mk)
            o += m
            cl += 1usize
        }
        if ols.inverse(a, h, p, hi) != ok { ret mem.Full }
        var change = 0.0f64
        u = 0usize
        while u < p {
            var st = 0.0f64
            var v = 0usize
            while v < p {
                st += hi[u * p + v] * g[v]
                v += 1usize
            }
            if math.abs[f64](st) > change { change = math.abs[f64](st) }
            beta[u] += st
            u += 1usize
        }
        // the alpha step at the new beta
        var z1 = 0usize
        while z1 < q * q {
            hq[z1] = 0.0f64
            z1 += 1usize
        }
        z1 = 0usize
        while z1 < q {
            gq[z1] = 0.0f64
            z1 += 1usize
        }
        o = 0usize
        cl = 0usize
        while cl < k {
            let m = usize(sz[cl])
            let mc = m * c
            if m > 1usize {
                let mk = mem.mark(a)
                let (mu, f1) = mem.alloc[f64](a, mc)
                let (pr, f2) = mem.alloc[f64](a, mc)
                let (dd, f3) = mem.alloc[f64](a, mc * p)
                let (vm, f4) = mem.alloc[f64](a, mc * mc)
                let (u2, f5) = mem.alloc[f64](a, c * c)
                let (d2, f6) = mem.alloc[f64](a, c * c)
                let (v2, f7) = mem.alloc[f64](a, c * c * c * c)
                let (v2i, f8) = mem.alloc[f64](a, c * c * c * c)
                if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok { ret mem.Full }
                ogs_build(ycat, x, o, m, c, p, px, link, corstr, maxm, beta, alpha, mu, pr, dd, vm)
                var s = 0usize
                while s < m {
                    var t = s + 1usize
                    while t < m {
                        var idx = 0usize
                        if corstr == 3usize { idx = s * (maxm - 1usize) - s * (s + 1usize) / 2usize + t - 1usize }
                        let mk2 = mem.mark(a)
                        if ogs_pair(a, pr[s * c..s * c + c], pr[t * c..t * c + c], mu[s * c..s * c + c], mu[t * c..t * c + c], math.exp[f64](alpha[idx]), c, u2, d2, v2) != ok { ret mem.Full }
                        if ols.inverse(a, v2, c * c, v2i) != ok { ret mem.Full }
                        var r = 0usize
                        while r < c * c {
                            var t2 = 0usize
                            while t2 < c * c {
                                hq[idx * q + idx] += d2[r] * v2i[r * c * c + t2] * d2[t2]
                                gq[idx] += d2[r] * v2i[r * c * c + t2] * u2[t2]
                                t2 += 1usize
                            }
                            r += 1usize
                        }
                        mem.reset(a, mk2)
                        t += 1usize
                    }
                    s += 1usize
                }
                mem.reset(a, mk)
            }
            o += m
            cl += 1usize
        }
        if ols.inverse(a, hq, q, hqi) != ok { ret mem.Full }
        u = 0usize
        while u < q {
            var st = 0.0f64
            var v = 0usize
            while v < q {
                st += hqi[u * q + v] * gq[v]
                v += 1usize
            }
            if math.abs[f64](st) > change { change = math.abs[f64](st) }
            alpha[u] += st
            u += 1usize
        }
        iter += 1usize
        if change <= 1.0e-4f64 { break }
    }
    // the covariances: blocks A (beta), D (alpha by beta), F (alpha) and the per-cluster scores
    let (us1, g1) = mem.alloc[f64](a, k * p)
    let (us3, g2) = mem.alloc[f64](a, k * q)
    let (dm, g3) = mem.alloc[f64](a, q * p)
    let (ai, g4) = mem.alloc[f64](a, pp)
    let (fi, g5) = mem.alloc[f64](a, q * q)
    let (di, g6) = mem.alloc[f64](a, q * p)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok { ret mem.Full }
    var z2 = 0usize
    while z2 < pp {
        h[z2] = 0.0f64
        z2 += 1usize
    }
    z2 = 0usize
    while z2 < q * q {
        hq[z2] = 0.0f64
        z2 += 1usize
    }
    z2 = 0usize
    while z2 < q * p {
        dm[z2] = 0.0f64
        z2 += 1usize
    }
    var o2 = 0usize
    cl = 0usize
    while cl < k {
        let m = usize(sz[cl])
        let mc = m * c
        let mk = mem.mark(a)
        let (mu, f1) = mem.alloc[f64](a, mc)
        let (pr, f2) = mem.alloc[f64](a, mc)
        let (dd, f3) = mem.alloc[f64](a, mc * p)
        let (vm, f4) = mem.alloc[f64](a, mc * mc)
        let (vi, f5) = mem.alloc[f64](a, mc * mc)
        let (u2, f6) = mem.alloc[f64](a, c * c)
        let (d2, f7) = mem.alloc[f64](a, c * c)
        let (v2, f8) = mem.alloc[f64](a, c * c * c * c)
        let (v2i, f9) = mem.alloc[f64](a, c * c * c * c)
        let (wv, f10) = mem.alloc[f64](a, c * c)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok { ret mem.Full }
        ogs_build(ycat, x, o2, m, c, p, px, link, corstr, maxm, beta, alpha, mu, pr, dd, vm)
        if ols.inverse(a, vm, mc, vi) != ok { ret mem.Full }
        var u = 0usize
        while u < p {
            us1[cl * p + u] = 0.0f64
            u += 1usize
        }
        u = 0usize
        while u < q {
            us3[cl * q + u] = 0.0f64
            u += 1usize
        }
        var r = 0usize
        while r < mc {
            var t2 = 0usize
            while t2 < mc {
                let w = vi[r * mc + t2]
                u = 0usize
                while u < p {
                    us1[cl * p + u] += dd[r * p + u] * w * pr[t2]
                    var v = 0usize
                    while v < p {
                        h[u * p + v] += dd[r * p + u] * w * dd[t2 * p + v]
                        v += 1usize
                    }
                    u += 1usize
                }
                t2 += 1usize
            }
            r += 1usize
        }
        var s = 0usize
        while s < m {
            var t = s + 1usize
            while t < m {
                var idx = 0usize
                if corstr == 3usize { idx = s * (maxm - 1usize) - s * (s + 1usize) / 2usize + t - 1usize }
                let psi = math.exp[f64](alpha[idx])
                let mk2 = mem.mark(a)
                if ogs_pair(a, pr[s * c..s * c + c], pr[t * c..t * c + c], mu[s * c..s * c + c], mu[t * c..t * c + c], psi, c, u2, d2, v2) != ok { ret mem.Full }
                if ols.inverse(a, v2, c * c, v2i) != ok { ret mem.Full }
                r = 0usize
                while r < c * c {
                    var sw = 0.0f64
                    var sv = 0.0f64
                    var t2 = 0usize
                    while t2 < c * c {
                        sw += v2i[r * c * c + t2] * d2[t2]
                        t2 += 1usize
                    }
                    wv[r] = sw
                    sv += 0.0f64
                    r += 1usize
                }
                r = 0usize
                while r < c * c {
                    hq[idx * q + idx] += d2[r] * wv[r]
                    us3[cl * q + idx] += wv[r] * u2[r]
                    // row r of the derivative of the pair equation in beta
                    let i1 = r / c
                    let j1 = r - i1 * c
                    let (gm1, gm2) = ogs_p11_mu(math.exp[f64](alpha[0usize]), mu[s * c + i1], mu[t * c + j1])
                    let ga = gm1 - mu[t * c + j1]
                    let gb = gm2 - mu[s * c + i1]
                    u = 0usize
                    while u < p {
                        let ub = (0.0f64 - pr[t * c + j1] - ga) * dd[(s * c + i1) * p + u] + (0.0f64 - pr[s * c + i1] - gb) * dd[(t * c + j1) * p + u]
                        dm[idx * p + u] += wv[r] * (0.0f64 - ub)
                        u += 1usize
                    }
                    r += 1usize
                }
                mem.reset(a, mk2)
                t += 1usize
            }
            s += 1usize
        }
        mem.reset(a, mk)
        o2 += m
        cl += 1usize
    }
    if ols.inverse(a, h, p, ai) != ok { ret mem.Full }
    if ols.inverse(a, hq, q, fi) != ok { ret mem.Full }
    // di = - fi dm ai
    var u3 = 0usize
    while u3 < q {
        var v3 = 0usize
        while v3 < p {
            var sacc = 0.0f64
            var w3 = 0usize
            while w3 < q {
                var x3 = 0usize
                while x3 < p {
                    sacc += fi[u3 * q + w3] * dm[w3 * p + x3] * ai[x3 * p + v3]
                    x3 += 1usize
                }
                w3 += 1usize
            }
            di[u3 * p + v3] = 0.0f64 - sacc
            v3 += 1usize
        }
        u3 += 1usize
    }
    let qq = q * q
    let (vb, g7) = mem.alloc[f64](a, pp)
    let (va, g8) = mem.alloc[f64](a, qq)
    let (mid, g9) = mem.alloc[f64](a, pp)
    if g7 != ok || g8 != ok || g9 != ok { ret mem.Full }
    var z3 = 0usize
    while z3 < pp {
        mid[z3] = 0.0f64
        z3 += 1usize
    }
    z3 = 0usize
    while z3 < qq {
        va[z3] = 0.0f64
        z3 += 1usize
    }
    cl = 0usize
    while cl < k {
        var u = 0usize
        while u < p {
            var v = 0usize
            while v < p {
                mid[u * p + v] += us1[cl * p + u] * us1[cl * p + v]
                v += 1usize
            }
            u += 1usize
        }
        u = 0usize
        while u < q {
            var ia = 0.0f64
            var w = 0usize
            while w < p {
                ia += di[u * p + w] * us1[cl * p + w]
                w += 1usize
            }
            w = 0usize
            while w < q {
                ia += fi[u * q + w] * us3[cl * q + w]
                w += 1usize
            }
            gq[u] = ia
            u += 1usize
        }
        u = 0usize
        while u < q {
            var v = 0usize
            while v < q {
                va[u * q + v] += gq[u] * gq[v]
                v += 1usize
            }
            u += 1usize
        }
        cl += 1usize
    }
    var su = 0usize
    while su < p {
        var sv2 = 0usize
        while sv2 < p {
            var sacc2 = 0.0f64
            var sq = 0usize
            while sq < p {
                var sw = 0usize
                while sw < p {
                    sacc2 += ai[su * p + sq] * mid[sq * p + sw] * ai[sv2 * p + sw]
                    sw += 1usize
                }
                sq += 1usize
            }
            vb[su * p + sv2] = sacc2
            sv2 += 1usize
        }
        su += 1usize
    }
    var w4 = 0usize
    while w4 < p {
        out[w4] = beta[w4]
        w4 += 1usize
    }
    w4 = 0usize
    while w4 < pp {
        out[p + w4] = vb[w4]
        out[p + pp + w4] = ai[w4]
        w4 += 1usize
    }
    w4 = 0usize
    while w4 < q {
        out[p + 2usize * pp + w4] = alpha[w4]
        w4 += 1usize
    }
    w4 = 0usize
    while w4 < qq {
        out[p + 2usize * pp + q + w4] = va[w4]
        out[p + 2usize * pp + q + qq + w4] = fi[w4]
        w4 += 1usize
    }
    ret ok
}
