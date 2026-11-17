// R metafor rma.uni: the estimators and the model fit (see metaforrma for the linear algebra and the layout of the result vector).
//
// Not here: GENQM, location-scale and selection models.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem
use e.algo.stat.pwr as pw
use e.algo.stat.compqf as cq
use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.metaforrma as mr

type GqCtx = struct { ws: *mr.Ws, v: []const f64, k: usize, p: usize, q: f64, level: f64, lower: bool }

// R's .GENQ.func: the probability of Q under the eigenvalues of S P S (S = diag(sqrt(v + tau2))), minus level, or one minus it
fn genq_cb(c: *GqCtx, t: f64) -> f64 {
    let k = c.k
    let a = c.ws.ar
    let (sm, e1) = mem.alloc[f64](a, k * k)
    let (ev, e2) = mem.alloc[f64](a, k)
    let (zv, e3) = mem.alloc[f64](a, k * k)
    let (lam, e4) = mem.alloc[f64](a, k - c.p)
    let (hh, e5) = mem.alloc[i64](a, k - c.p)
    let (dl, e6) = mem.alloc[f64](a, k - c.p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mr.nan() }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            sm[i * k + j] = math.sqrt[f64](c.v[i] + t) * c.ws.pm[i * k + j] * math.sqrt[f64](c.v[j] + t)
            j += 1usize
        }
        i += 1usize
    }
    if sy.dsyevr_all(a, sm, k, ev, zv) != ok { ret mr.nan() }
    i = 0usize
    while i < k - c.p {
        lam[i] = ev[k - 1usize - i]
        hh[i] = 1i64
        dl[i] = 0.0f64
        i += 1usize
    }
    let (r, fe) = cq.farebrother(a, lam, hh, dl, c.q, 1.0f64, 100000usize, 1.0e-10f64)
    if fe != ok { ret mr.nan() }
    if c.lower { ret r.qq - c.level }
    ret (1.0f64 - r.qq) - c.level
}

fn default_ctl() -> mr.Ctl {
    var c: mr.Ctl = zero
    c.method = 8usize
    c.test = 0usize
    c.weighted = true
    c.level = 0.95f64
    c.tau2fix = mr.nan()
    c.intercept = true
    c.skipr2 = false
    c.tau2min = 0.0f64
    ret c
}

// the estimate of tau2 by the closed-form and iterative methods, then finish(); see the list of method codes in metaforrma
fn fit(ws: *mr.Ws, y: []const f64, v: []const f64, x: []const f64, k: usize, p: usize, c: *const mr.Ctl, out: []f64) {
    mr.fill_nan(out)
    out[mr.O_CONV] = 1.0f64
    let kf = f64(k)
    let pf = f64(p)
    let method = c.method
    let fixed = c.tau2fix == c.tau2fix && method != 0usize
    if k == 1usize {
        var t1 = 0.0f64
        if fixed { t1 = c.tau2fix }
        var c1 = *c
        c1.test = 0usize
        finish(ws, y, v, x, k, p, &c1, t1, mr.nan(), out)
        ret
    }
    var ybar = 0.0f64
    var i = 0usize
    while i < k {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / kf
    i = 0usize
    while i < k {
        ws.ymc[i] = y[i] - ybar
        i += 1usize
    }
    var tau2 = 0.0f64
    var tau20 = 0.0f64
    var setau2 = mr.nan()
    var conv = true
    let tmin = c.tau2min
    var tmax = 100.0f64
    if method == 6usize || method == 10usize || method == 14usize { tmax = mr.tau2_max(ws, y, k) }
    var vy = 0.0f64
    i = 0usize
    while i < k {
        vy += ws.ymc[i] * ws.ymc[i]
        i += 1usize
    }
    vy = vy / (kf - 1.0f64)
    if method == 2usize || method == 7usize || method == 8usize || method == 9usize {
        i = 0usize
        while i < k {
            ws.wfe[i] = 1.0f64
            i += 1usize
        }
        if !mr.pbuild(ws, x, ws.wfe, k, p) {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        let rss = mr.pquad(ws, ws.ymc, k)
        let trpv = mr.ptrace_v(ws, v, k)
        tau2 = (rss - trpv) / (kf - pf)
        if fixed { tau2 = c.tau2fix }
        if method == 2usize {
            let t0 = mr.max0(tau2)
            setau2 = math.sqrt[f64](1.0f64 / ((kf - pf) * (kf - pf)) * (2.0f64 * mr.psum_pvtpv(ws, v, k) + 4.0f64 * t0 * trpv + 2.0f64 * t0 * t0 * (kf - pf)))
        }
    }
    if method == 1usize || method == 3usize || method == 4usize {
        i = 0usize
        while i < k {
            ws.wfe[i] = 1.0f64 / v[i]
            i += 1usize
        }
        if !mr.pbuild(ws, x, ws.wfe, k, p) {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        let rss = mr.pquad(ws, ws.ymc, k)
        let sw = mr.sum_of(ws.wfe, k)
        let trp = mr.ptrace(ws, k)
        let sp2 = mr.psum2(ws, k)
        if method == 1usize { tau2 = (rss - (kf - pf)) / trp }
        if method == 3usize { tau2 = (rss - kf) / sw }
        if method == 4usize { tau2 = (kf / (kf - pf) * rss - kf) / sw }
        if fixed { tau2 = c.tau2fix }
        let t0 = mr.max0(tau2)
        if method == 1usize { setau2 = math.sqrt[f64](1.0f64 / (trp * trp) * (2.0f64 * (kf - pf) + 4.0f64 * t0 * trp + 2.0f64 * t0 * t0 * sp2)) }
        if method == 3usize { setau2 = math.sqrt[f64](1.0f64 / (sw * sw) * (2.0f64 * (kf - pf) + 4.0f64 * t0 * trp + 2.0f64 * t0 * t0 * sp2)) }
        if method == 4usize { setau2 = kf / (kf - pf) * math.sqrt[f64](1.0f64 / (sw * sw) * (2.0f64 * (kf - pf) + 4.0f64 * t0 * trp + 2.0f64 * t0 * t0 * sp2)) }
    }
    if method == 11usize {
        if c.aw.len < k {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        if !mr.pbuild(ws, x, c.aw, k, p) {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        let rss = mr.pquad(ws, ws.ymc, k)
        let trp = mr.ptrace(ws, k)
        let trpv = mr.ptrace_v(ws, v, k)
        tau2 = (rss - trpv) / trp
        if fixed { tau2 = c.tau2fix }
        let t0 = mr.max0(tau2)
        setau2 = math.sqrt[f64](1.0f64 / (trp * trp) * (2.0f64 * mr.psum_pvtpv(ws, v, k) + 4.0f64 * t0 * mr.psum_pvp(ws, v, k) + 2.0f64 * t0 * t0 * mr.psum2(ws, k)))
    }
    if method == 14usize {
        // GENQM: the median unbiased estimator, the root of the distribution of the generalized Q statistic (Farebrother) at one half
        if c.aw.len < k {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        if !mr.pbuild(ws, x, c.aw, k, p) {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        let rss = mr.pquad(ws, ws.ymc, k)
        let trp = mr.ptrace(ws, k)
        var gc: GqCtx = zero
        gc.ws = ws
        gc.v = v
        gc.k = k
        gc.p = p
        gc.q = rss
        if fixed {
            tau2 = c.tau2fix
        } else {
            gc.level = 0.0f64
            gc.lower = true
            if genq_cb(&gc, tmin) > 0.5f64 {
                tau2 = tmin
            } else if genq_cb(&gc, tmax) < 0.5f64 {
                conv = false
            } else {
                gc.level = 0.5f64
                gc.lower = false
                tau2 = pw.zeroin[GqCtx](&gc, genq_cb, tmin, tmax, mr.uniroot_tol(), 100i64)
            }
        }
        // the pm matrix still holds P, whatever genq_cb left there
        let t0 = mr.max0(tau2)
        let trpv = mr.ptrace_v(ws, v, k)
        let _ = trpv
        setau2 = math.sqrt[f64](1.0f64 / (trp * trp) * (2.0f64 * mr.psum_pvtpv(ws, v, k) + 4.0f64 * t0 * mr.psum_pvp(ws, v, k) + 2.0f64 * t0 * t0 * mr.psum2(ws, k)))
    }
    if method == 5usize {
        tau20 = vy * (kf - 1.0f64) / kf
        mr.weights_of(ws, v, tau20, k)
        if !mr.pbuild(ws, x, ws.w, k, p) {
            out[mr.O_CONV] = 0.0f64
            ret
        }
        let rss = mr.pquad(ws, ws.ymc, k)
        tau2 = tau20 * rss / (kf - pf)
        if fixed { tau2 = c.tau2fix }
        let t0 = mr.max0(tau2)
        setau2 = math.sqrt[f64](tau20 * tau20 / ((kf - pf) * (kf - pf)) * (2.0f64 * mr.psum_pvtpv(ws, v, k) + 4.0f64 * t0 * mr.psum_pvp(ws, v, k) + 2.0f64 * t0 * t0 * mr.psum2(ws, k)))
    }
    if method == 12usize || method == 13usize {
        tau2 = 0.0f64
        if method == 13usize { tau2 = vy * (kf - 1.0f64) / kf }
        var change = 1.0e-5f64 + 1.0f64
        var iter = 0usize
        while change > 1.0e-5f64 {
            iter += 1usize
            let old2 = tau2
            mr.weights_of(ws, v, tau2, k)
            if !mr.pbuild(ws, x, ws.w, k, p) {
                out[mr.O_CONV] = 0.0f64
                ret
            }
            let rss = mr.pquad(ws, ws.ymc, k)
            if method == 12usize {
                tau2 = (rss - mr.ptrace_v(ws, v, k)) / mr.ptrace(ws, k)
                if tau2 < tmin { tau2 = tmin }
            } else {
                tau2 = tau2 * rss / (kf - pf)
            }
            if fixed { tau2 = c.tau2fix }
            change = math.abs[f64](old2 - tau2)
            if iter > 100usize {
                conv = false
                change = 0.0f64
            }
        }
    }
    if method == 6usize || method == 10usize {
        var tgt = kf - pf
        if method == 10usize { tgt = nm.qchisq(0.5f64, kf - pf, true, false) }
        if fixed {
            tau2 = c.tau2fix
        } else {
            let (t, found) = mr.pm_root(ws, ws.ymc, v, x, k, p, tgt, tmin, tmax)
            tau2 = t
            conv = found
        }
    }
    if method == 7usize || method == 8usize || method == 9usize {
        if tau2 < 0.0f64 { tau2 = 0.0f64 }
        if tau2 < tmin { tau2 = tmin }
        var change = 1.0e-5f64 + 1.0f64
        var iter = 0usize
        while change > 1.0e-5f64 {
            iter += 1usize
            let old2 = tau2
            mr.weights_of(ws, v, tau2, k)
            let sw = mr.sum_of(ws.w, k)
            var sw2 = 0.0f64
            i = 0usize
            while i < k {
                sw2 += ws.w[i] * ws.w[i]
                i += 1usize
            }
            if !mr.pbuild(ws, x, ws.w, k, p) {
                out[mr.O_CONV] = 0.0f64
                ret
            }
            let q = mr.pquad(ws, ws.ymc, k)
            var pp = 0.0f64
            i = 0usize
            while i < k {
                pp += ws.py[i] * ws.py[i]
                i += 1usize
            }
            var adj = 0.0f64
            if method == 7usize { adj = (pp - sw) / sw2 }
            if method == 8usize { adj = (pp - mr.ptrace(ws, k)) / mr.psum2(ws, k) }
            if method == 9usize { adj = (q * kf / (kf - pf) - kf) / sw }
            if adj != adj { adj = 0.0f64 }
            while tau2 + adj < tmin { adj = adj / 2.0f64 }
            if fixed { tau2 = c.tau2fix } else { tau2 = tau2 + adj }
            change = math.abs[f64](old2 - tau2)
            if iter > 100usize {
                conv = false
                change = 0.0f64
            }
        }
        if conv && method != 9usize && !fixed {
            let reml = method == 8usize
            i = 0usize
            while i < k {
                ws.wfe[i] = 1.0f64 / v[i]
                i += 1usize
            }
            let ll0 = mr.ll_check(ws, ws.ymc, x, ws.wfe, mr.sum_log(v, 0.0f64, k), k, p, reml)
            mr.weights_of(ws, v, tau2, k)
            let ll1 = mr.ll_check(ws, ws.ymc, x, ws.w, mr.sum_log(v, tau2, k), k, p, reml)
            if ll0 - ll1 > mr.uniroot_tol() && tau2 > 1.0e-5f64 { tau2 = 0.0f64 }
        }
        if conv {
            mr.weights_of(ws, v, tau2, k)
            if !mr.pbuild(ws, x, ws.w, k, p) {
                out[mr.O_CONV] = 0.0f64
                ret
            }
            if method == 7usize {
                var sw2 = 0.0f64
                i = 0usize
                while i < k {
                    sw2 += ws.w[i] * ws.w[i]
                    i += 1usize
                }
                setau2 = math.sqrt[f64](2.0f64 / sw2)
            } else if method == 8usize {
                setau2 = math.sqrt[f64](2.0f64 / mr.psum2(ws, k))
            }
        }
    }
    if !conv {
        out[mr.O_CONV] = 0.0f64
        ret
    }
    if method == 0usize {
        tau2 = 0.0f64
    } else if tau2 < tmin {
        tau2 = tmin
    }
    if method == 9usize || method == 6usize || method == 10usize || method == 12usize || method == 13usize {
        mr.weights_of(ws, v, tau2, k)
        let sw = mr.sum_of(ws.w, k)
        setau2 = math.sqrt[f64](2.0f64 * kf * kf / (kf - pf) / (sw * sw))
    }
    finish(ws, y, v, x, k, p, c, tau2, setau2, out)
}

// the fixed effects, their tests, Q, I2, H2, the fit statistics and R2 given tau2
fn finish(ws: *mr.Ws, y: []const f64, v: []const f64, x: []const f64, k: usize, p: usize, c: *const mr.Ctl, tau2: f64, setau2: f64, out: []f64) {
    let kf = f64(k)
    let pf = f64(p)
    let method = c.method
    out[mr.O_TAU2] = tau2
    out[mr.O_SETAU2] = setau2
    mr.weights_of(ws, v, tau2, k)
    let nweights = c.aw.len >= k
    let knha = c.test >= 2usize
    let eps = 2.220446049250313e-16f64
    var rssknha = 0.0f64
    var rssf = 0.0f64
    // the weighted least squares fit with the marginal weights: beta in out, S in vb until the choice below
    var haveW = false
    if (c.weighted && !nweights) || knha {
        if !mr.xwx_inv(ws, x, ws.w, k, p) { ret }
        mr.beta_of(ws, x, ws.w, y, k, p)
        rssknha = mr.rss_of(ws, y, x, ws.w, ws.b, k, p)
        haveW = true
    }
    var i = 0usize
    var a = 0usize
    var cc = 0usize
    if haveW {
        // keep S and beta of the marginal fit in sub2 and the beta slot of o2
        a = 0usize
        while a < p * p {
            ws.sub2[a] = ws.s[a]
            a += 1usize
        }
        a = 0usize
        while a < p {
            ws.big[a] = ws.b[a]
            a += 1usize
        }
    }
    if c.weighted && !nweights {
        a = 0usize
        while a < p * p {
            out[mr.O_VB + a] = ws.sub2[a]
            a += 1usize
        }
        a = 0usize
        while a < p {
            out[mr.O_BETA + a] = ws.big[a]
            a += 1usize
        }
        rssf = rssknha
    } else {
        // user weights (sandwich with the marginal variances) or the unweighted fit (the same sandwich with unit weights)
        i = 0usize
        while i < k {
            if nweights { ws.wfe[i] = c.aw[i] } else { ws.wfe[i] = 1.0f64 }
            i += 1usize
        }
        if !mr.xwx_inv(ws, x, ws.wfe, k, p) { ret }
        mr.beta_of(ws, x, ws.wfe, y, k, p)
        a = 0usize
        while a < p {
            out[mr.O_BETA + a] = ws.b[a]
            a += 1usize
        }
        // B = X' A M A X, then vb = S B S
        a = 0usize
        while a < p {
            cc = 0usize
            while cc < p {
                var t = 0.0f64
                i = 0usize
                while i < k {
                    t += ws.wfe[i] * ws.wfe[i] * (v[i] + tau2) * x[i * p + a] * x[i * p + cc]
                    i += 1usize
                }
                ws.tmp[a * p + cc] = t
                cc += 1usize
            }
            a += 1usize
        }
        a = 0usize
        while a < p {
            cc = 0usize
            while cc < p {
                var t = 0.0f64
                var m1 = 0usize
                while m1 < p {
                    var m2 = 0usize
                    while m2 < p {
                        t += ws.s[a * p + m1] * ws.tmp[m1 * p + m2] * ws.s[m2 * p + cc]
                        m2 += 1usize
                    }
                    m1 += 1usize
                }
                out[mr.O_VB + a * p + cc] = t
                cc += 1usize
            }
            a += 1usize
        }
        rssf = mr.rss_of(ws, y, x, ws.w, ws.b, k, p)
    }
    var s2w = 1.0f64
    if knha {
        if rssknha <= eps { s2w = 0.0f64 } else { s2w = rssknha / (kf - pf) }
        if c.test == 3usize && s2w < 1.0f64 { s2w = 1.0f64 }
    }
    a = 0usize
    while a < p * p {
        out[mr.O_VB + a] = out[mr.O_VB + a] * s2w
        a += 1usize
    }
    out[mr.O_S2W] = s2w
    out[mr.O_RSSF] = rssf
    var ddf = mr.nan()
    let tdist = c.test >= 1usize
    if tdist { ddf = kf - pf }
    out[mr.O_DDF] = ddf
    // the omnibus test of the moderators (all coefficients when there is no intercept or only an intercept)
    var btt0 = 0usize
    if c.intercept && p > 1usize { btt0 = 1usize }
    let m = p - btt0
    a = 0usize
    while a < m {
        cc = 0usize
        while cc < m {
            ws.sub[a * m + cc] = out[mr.O_VB + (a + btt0) * p + cc + btt0]
            cc += 1usize
        }
        a += 1usize
    }
    var qm = mr.nan()
    if mr.invert_into(ws.sub, m, ws.aug, ws.sub2) {
        qm = 0.0f64
        a = 0usize
        while a < m {
            cc = 0usize
            while cc < m {
                qm += out[mr.O_BETA + btt0 + a] * ws.sub2[a * m + cc] * out[mr.O_BETA + btt0 + cc]
                cc += 1usize
            }
            a += 1usize
        }
    }
    let alpha = 1.0f64 - c.level
    var crit = mr.nan()
    a = 0usize
    while a < p {
        out[mr.O_SE + a] = math.sqrt[f64](out[mr.O_VB + a * p + a])
        out[mr.O_Z + a] = out[mr.O_BETA + a] / out[mr.O_SE + a]
        a += 1usize
    }
    if tdist {
        qm = qm / f64(m)
        if ddf > 0.0f64 {
            out[mr.O_QMP] = nb.pf(qm, f64(m), ddf, false, false)
            crit = nb.qt(alpha / 2.0f64, ddf, false, false)
        }
        a = 0usize
        while a < p {
            if ddf > 0.0f64 { out[mr.O_P + a] = 2.0f64 * nb.pt(math.abs[f64](out[mr.O_Z + a]), ddf, false, false) }
            a += 1usize
        }
    } else {
        out[mr.O_QMP] = nm.pchisq(qm, f64(m), false, false)
        crit = dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, false, false)
        a = 0usize
        while a < p {
            out[mr.O_P + a] = 2.0f64 * dist.pnorm(math.abs[f64](out[mr.O_Z + a]), 0.0f64, 1.0f64, false, false)
            a += 1usize
        }
    }
    out[mr.O_QM] = qm
    a = 0usize
    while a < p {
        out[mr.O_CILB + a] = out[mr.O_BETA + a] - crit * out[mr.O_SE + a]
        out[mr.O_CIUB + a] = out[mr.O_BETA + a] + crit * out[mr.O_SE + a]
        a += 1usize
    }
    // the heterogeneity test with the fixed-effect weights
    i = 0usize
    while i < k {
        ws.wfe[i] = 1.0f64 / v[i]
        i += 1usize
    }
    var ybar = 0.0f64
    i = 0usize
    while i < k {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / kf
    i = 0usize
    while i < k {
        ws.ya[i] = y[i] - ybar
        i += 1usize
    }
    var vt = 0.0f64
    if k > p {
        if !mr.pbuild(ws, x, ws.wfe, k, p) { ret }
        let q = mr.pquad(ws, ws.ya, k)
        let qe = mr.max0(q)
        out[mr.O_QE] = qe
        out[mr.O_QEP] = nm.pchisq(qe, kf - pf, false, false)
        vt = (kf - pf) / mr.ptrace(ws, k)
        if method == 0usize {
            out[mr.O_I2] = mr.max0(100.0f64 * (qe - (kf - pf)) / qe)
            out[mr.O_H2] = qe / (kf - pf)
        } else {
            out[mr.O_I2] = 100.0f64 * tau2 / (vt + tau2)
            out[mr.O_H2] = tau2 / vt + 1.0f64
        }
    } else {
        out[mr.O_QE] = 0.0f64
        out[mr.O_QEP] = 1.0f64
        out[mr.O_I2] = 0.0f64
        out[mr.O_H2] = 1.0f64
    }
    out[mr.O_VT] = vt
    // the log-likelihoods and the information criteria
    let pi2 = 2.0f64 * 3.141592653589793f64
    var parms = pf
    if method != 0usize && !(c.tau2fix == c.tau2fix) { parms += 1.0f64 }
    let sl = mr.sum_log(v, tau2, k)
    let llml = 0.0f64 - 0.5f64 * kf * math.log[f64](pi2) - 0.5f64 * sl - 0.5f64 * rssf
    i = 0usize
    while i < k {
        ws.wfe[i] = 1.0f64
        i += 1usize
    }
    if !mr.xwx_inv(ws, x, ws.wfe, k, p) { ret }
    let ldxx = 0.0f64 - mr.logdet_of(ws.s, p, ws.sub)
    if !mr.xwx_inv(ws, x, ws.w, k, p) { ret }
    let ldxwx = 0.0f64 - mr.logdet_of(ws.s, p, ws.sub)
    let llreml = 0.0f64 - 0.5f64 * (kf - pf) * math.log[f64](pi2) + 0.5f64 * ldxx - 0.5f64 * sl - 0.5f64 * ldxwx - 0.5f64 * rssf
    var devml = 0.0f64
    if k > p {
        var slv = 0.0f64
        i = 0usize
        while i < k {
            slv += math.log[f64](pi2 * v[i])
            i += 1usize
        }
        devml = 0.0f64 - 2.0f64 * llml - slv
    }
    out[mr.O_LLML] = llml
    out[mr.O_DEVML] = devml
    out[mr.O_AICML] = 0.0f64 - 2.0f64 * llml + 2.0f64 * parms
    out[mr.O_BICML] = 0.0f64 - 2.0f64 * llml + parms * math.log[f64](kf)
    var mx = kf
    if parms + 2.0f64 > mx { mx = parms + 2.0f64 }
    out[mr.O_AICCML] = 0.0f64 - 2.0f64 * llml + 2.0f64 * parms * mx / (mx - parms - 1.0f64)
    out[mr.O_LLREML] = llreml
    out[mr.O_DEVREML] = 0.0f64 - 2.0f64 * llreml
    out[mr.O_AICREML] = 0.0f64 - 2.0f64 * llreml + 2.0f64 * parms
    out[mr.O_BICREML] = 0.0f64 - 2.0f64 * llreml + parms * math.log[f64](kf - pf)
    mx = kf - pf
    if parms + 2.0f64 > mx { mx = parms + 2.0f64 }
    out[mr.O_AICCREML] = 0.0f64 - 2.0f64 * llreml + 2.0f64 * parms * mx / (mx - parms - 1.0f64)
    // R2
    if !c.skipr2 && c.intercept && p > 1usize {
        if method == 0usize {
            var wlm = 0.0f64
            var swy = 0.0f64
            var sw = 0.0f64
            i = 0usize
            while i < k {
                var wi = 1.0f64
                if c.weighted { wi = 1.0f64 / v[i] }
                sw += wi
                swy += wi * y[i]
                i += 1usize
            }
            let yw = swy / sw
            var tss = 0.0f64
            var rs = 0.0f64
            i = 0usize
            while i < k {
                var wi = 1.0f64
                if c.weighted { wi = 1.0f64 / v[i] }
                tss += wi * (y[i] - yw) * (y[i] - yw)
                var f = 0.0f64
                a = 0usize
                while a < p {
                    f += x[i * p + a] * out[mr.O_BETA + a]
                    a += 1usize
                }
                rs += wi * (y[i] - f) * (y[i] - f)
                i += 1usize
            }
            wlm = 1.0f64 - (rs / tss) * (kf - 1.0f64) / (kf - pf)
            out[mr.O_R2] = mr.max0(100.0f64 * wlm)
        } else {
            var c1 = *c
            c1.skipr2 = true
            c1.tau2fix = mr.nan()
            c1.intercept = true
            i = 0usize
            while i < k {
                ws.xa[i] = 1.0f64
                i += 1usize
            }
            fit(ws, y, v, ws.xa, k, 1usize, &c1, ws.o2)
            let t2re = ws.o2[mr.O_TAU2]
            var r2 = 0.0f64
            if t2re != 0.0f64 { r2 = (t2re - tau2) / t2re }
            out[mr.O_R2] = mr.max0(100.0f64 * r2)
        }
    }
}
