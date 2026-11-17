// R geepack: geeglm for a Gaussian response with the identity link and equal-size clusters, with the independence or the exchangeable working correlation
// (Liang-Zeger moment estimates of the scale and the correlation) and the robust sandwich covariance.
//
// Not here: other families and links, unequal clusters, the AR(1), unstructured and fixed correlations, jackknife and bootstrap variances, geese and the Wald tests.

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
