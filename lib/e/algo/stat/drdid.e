// R DRDID: reg_did_panel, the outcome-regression difference-in-differences estimator on panel data, its ATT and analytic standard error from the influence function.
//
// Not here: the inverse-propensity and doubly robust estimators, repeated cross-sections, bootstrap inference and the improved estimators.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// reg_did_panel(y1, y0, D, covariates)$ATT (part 0) and $se (part 1); x is n by p row-major and includes the intercept column the caller wants
fn reg_did_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    // the control rows
    var nc = 0usize
    var i = 0usize
    while i < n {
        if d[i] == 0.0f64 { nc += 1usize }
        i += 1usize
    }
    let (xc, e1) = mem.alloc[f64](a, nc * p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (yc, e2) = mem.alloc[f64](a, nc)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var r = 0usize
    i = 0usize
    while i < n {
        if d[i] == 0.0f64 {
            var j = 0usize
            while j < p {
                xc[r * p + j] = x[i * p + j]
                j += 1usize
            }
            yc[r] = dy[i]
            r += 1usize
        }
        i += 1usize
    }
    let (f, e3) = ols.ols(a, xc, yc, nc, p)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(n)
    // out.delta, the fitted control change at every unit
    let (od, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    var wt = 0.0f64
    var treat = 0.0f64
    var cont = 0.0f64
    i = 0usize
    while i < n {
        var v = 0.0f64
        var j = 0usize
        while j < p {
            v += f.beta[j] * x[i * p + j]
            j += 1usize
        }
        od[i] = v
        wt += d[i]
        treat += d[i] * dy[i]
        cont += d[i] * v
        i += 1usize
    }
    let mw = wt / nf
    let eta_t = (treat / nf) / mw
    let eta_c = (cont / nf) / mw
    let att = eta_t - eta_c
    if part == 0usize { ret att }
    // the influence function
    let (xtx, e5) = mem.alloc[f64](a, p * p)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                if d[i] == 0.0f64 { s += x[i * p + u] * x[i * p + v] }
                i += 1usize
            }
            xtx[u * p + v] = s / nf
            v += 1usize
        }
        u += 1usize
    }
    let (inv, e6) = mem.alloc[f64](a, p * p)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, xtx, p, inv) != ok { ret 0.0f64 / 0.0f64 }
    // M1 = mean over units of w.cont * x
    let (m1, e7) = mem.alloc[f64](a, p)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    u = 0usize
    while u < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += d[i] * x[i * p + u]
            i += 1usize
        }
        m1[u] = s / nf
        u += 1usize
    }
    let (inf, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        let inf_t = (d[i] * dy[i] - d[i] * eta_t) / mw
        let inf_c1 = d[i] * od[i] - d[i] * eta_c
        // asy.lin.rep.ols row: w.ols * (dy - out.delta) * x_i %*% XpX^-1, then times M1
        var inf_c2 = 0.0f64
        if d[i] == 0.0f64 {
            let res = dy[i] - od[i]
            u = 0usize
            while u < p {
                var rowv = 0.0f64
                var v = 0usize
                while v < p {
                    rowv += res * x[i * p + v] * inv[v * p + u]
                    v += 1usize
                }
                inf_c2 += rowv * m1[u]
                u += 1usize
            }
        }
        let ic = (inf_c1 + inf_c2) / mw
        inf[i] = inf_t - ic
        sum += inf[i]
        i += 1usize
    }
    let mean = sum / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (inf[i] - mean) * (inf[i] - mean)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (nf - 1.0f64))
    ret sd * math.sqrt[f64](nf - 1.0f64) / nf
}

// the logistic regression of d on x (n by p) by iteratively reweighted least squares into beta; false when it fails to converge in 100 steps
fn logit_fit(a: *mem.Arena, d: []const f64, x: []const f64, n: usize, p: usize, beta: []f64) -> bool {
    var u = 0usize
    while u < p {
        beta[u] = 0.0f64
        u += 1usize
    }
    let (xtwx, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret false }
    let (inv, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret false }
    let (xtz, e3) = mem.alloc[f64](a, p)
    if e3 != ok { ret false }
    var it = 0usize
    while it < 100usize {
        u = 0usize
        while u < p {
            xtz[u] = 0.0f64
            var v = 0usize
            while v < p {
                xtwx[u * p + v] = 0.0f64
                v += 1usize
            }
            u += 1usize
        }
        var i = 0usize
        while i < n {
            var eta = 0.0f64
            u = 0usize
            while u < p {
                eta += beta[u] * x[i * p + u]
                u += 1usize
            }
            let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
            let w = pr * (1.0f64 - pr)
            let z = eta + (d[i] - pr) / w
            u = 0usize
            while u < p {
                xtz[u] += w * x[i * p + u] * z
                var v = 0usize
                while v < p {
                    xtwx[u * p + v] += w * x[i * p + u] * x[i * p + v]
                    v += 1usize
                }
                u += 1usize
            }
            i += 1usize
        }
        if ols.inverse(a, xtwx, p, inv) != ok { ret false }
        var delta = 0.0f64
        u = 0usize
        while u < p {
            var nb = 0.0f64
            var v = 0usize
            while v < p {
                nb += inv[u * p + v] * xtz[v]
                v += 1usize
            }
            let dd = math.abs[f64](nb - beta[u])
            if dd > delta { delta = dd }
            beta[u] = nb
            u += 1usize
        }
        if delta < 1.0e-13f64 { ret true }
        it += 1usize
    }
    ret false
}

// drdid_panel(y1, y0, D, covariates)$ATT (part 0) and $se (part 1), the locally efficient doubly robust DiD estimator with trim.level 0.995
fn drdid_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    let nf = f64(n)
    let (pb, e0) = mem.alloc[f64](a, p)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    if !logit_fit(a, d, x, n, p, pb) { ret 0.0f64 / 0.0f64 }
    var nc = 0usize
    var i = 0usize
    while i < n {
        if d[i] == 0.0f64 { nc += 1usize }
        i += 1usize
    }
    let (xc, e1) = mem.alloc[f64](a, nc * p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (yc, e2) = mem.alloc[f64](a, nc)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var r = 0usize
    i = 0usize
    while i < n {
        if d[i] == 0.0f64 {
            var j = 0usize
            while j < p {
                xc[r * p + j] = x[i * p + j]
                j += 1usize
            }
            yc[r] = dy[i]
            r += 1usize
        }
        i += 1usize
    }
    let (f, e3) = ols.ols(a, xc, yc, nc, p)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (ps, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let (res, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    let (wt, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    let (wc, e7) = mem.alloc[f64](a, n)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    var mwt = 0.0f64
    var mwc = 0.0f64
    var st = 0.0f64
    var sc = 0.0f64
    i = 0usize
    while i < n {
        var eta = 0.0f64
        var od = 0.0f64
        var j = 0usize
        while j < p {
            eta += pb[j] * x[i * p + j]
            od += f.beta[j] * x[i * p + j]
            j += 1usize
        }
        var pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        if pr > 1.0f64 - 1.0e-6f64 { pr = 1.0f64 - 1.0e-6f64 }
        ps[i] = pr
        res[i] = dy[i] - od
        var trim = 1.0f64
        if d[i] == 0.0f64 && pr >= 0.995f64 { trim = 0.0f64 }
        wt[i] = trim * d[i]
        wc[i] = trim * pr * (1.0f64 - d[i]) / (1.0f64 - pr)
        mwt += wt[i]
        mwc += wc[i]
        st += wt[i] * res[i]
        sc += wc[i] * res[i]
        i += 1usize
    }
    mwt = mwt / nf
    mwc = mwc / nf
    let eta_t = (st / nf) / mwt
    let eta_c = (sc / nf) / mwc
    let att = eta_t - eta_c
    if part == 0usize { ret att }
    let (xpx, e8) = mem.alloc[f64](a, p * p)
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    let (xw, e9) = mem.alloc[f64](a, p * p)
    if e9 != ok { ret 0.0f64 / 0.0f64 }
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            var s1 = 0.0f64
            var s2 = 0.0f64
            i = 0usize
            while i < n {
                if d[i] == 0.0f64 { s1 += x[i * p + u] * x[i * p + v] }
                s2 += ps[i] * (1.0f64 - ps[i]) * x[i * p + u] * x[i * p + v]
                i += 1usize
            }
            xpx[u * p + v] = s1 / nf
            xw[u * p + v] = s2
            v += 1usize
        }
        u += 1usize
    }
    let (xi, e10) = mem.alloc[f64](a, p * p)
    if e10 != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, xpx, p, xi) != ok { ret 0.0f64 / 0.0f64 }
    let (hi, e11) = mem.alloc[f64](a, p * p)
    if e11 != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, xw, p, hi) != ok { ret 0.0f64 / 0.0f64 }
    let (m1, e12) = mem.alloc[f64](a, p)
    if e12 != ok { ret 0.0f64 / 0.0f64 }
    let (m2, e13) = mem.alloc[f64](a, p)
    if e13 != ok { ret 0.0f64 / 0.0f64 }
    let (m3, e14) = mem.alloc[f64](a, p)
    if e14 != ok { ret 0.0f64 / 0.0f64 }
    u = 0usize
    while u < p {
        var a1 = 0.0f64
        var a2 = 0.0f64
        var a3 = 0.0f64
        i = 0usize
        while i < n {
            a1 += wt[i] * x[i * p + u]
            a2 += wc[i] * (res[i] - eta_c) * x[i * p + u]
            a3 += wc[i] * x[i * p + u]
            i += 1usize
        }
        m1[u] = a1 / nf
        m2[u] = a2 / nf
        m3[u] = a3 / nf
        u += 1usize
    }
    let (inf, e15) = mem.alloc[f64](a, n)
    if e15 != ok { ret 0.0f64 / 0.0f64 }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        var wols_m1 = 0.0f64
        var wols_m3 = 0.0f64
        var ps_m2 = 0.0f64
        u = 0usize
        while u < p {
            var rw = 0.0f64
            var rp = 0.0f64
            var v = 0usize
            while v < p {
                if d[i] == 0.0f64 { rw += res[i] * x[i * p + v] * xi[v * p + u] }
                rp += (d[i] - ps[i]) * x[i * p + v] * hi[v * p + u] * nf
                v += 1usize
            }
            wols_m1 += rw * m1[u]
            wols_m3 += rw * m3[u]
            ps_m2 += rp * m2[u]
            u += 1usize
        }
        let inf_t = (wt[i] * res[i] - wt[i] * eta_t - wols_m1) / mwt
        let inf_c = (wc[i] * res[i] - wc[i] * eta_c + ps_m2 - wols_m3) / mwc
        inf[i] = inf_t - inf_c
        sum += inf[i]
        i += 1usize
    }
    let mean = sum / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (inf[i] - mean) * (inf[i] - mean)
        i += 1usize
    }
    ret math.sqrt[f64](ss / (nf - 1.0f64)) * math.sqrt[f64](nf - 1.0f64) / nf
}

// ipw_did_panel (std false) and std_ipw_did_panel (std true): the inverse-propensity DiD estimators with trim.level 0.995; part 0 the ATT, 1 its standard error
fn ipw_did_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, std: bool, part: usize) -> f64 {
    let nf = f64(n)
    let (pb, e0) = mem.alloc[f64](a, p)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    if !logit_fit(a, d, x, n, p, pb) { ret 0.0f64 / 0.0f64 }
    let (ps, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (wt, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (wc, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var mwt = 0.0f64
    var mwc = 0.0f64
    var md = 0.0f64
    var st = 0.0f64
    var sc = 0.0f64
    var i = 0usize
    while i < n {
        var eta = 0.0f64
        var j = 0usize
        while j < p {
            eta += pb[j] * x[i * p + j]
            j += 1usize
        }
        var pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        if pr > 1.0f64 - 1.0e-6f64 { pr = 1.0f64 - 1.0e-6f64 }
        ps[i] = pr
        var trim = 1.0f64
        if d[i] == 0.0f64 && pr >= 0.995f64 { trim = 0.0f64 }
        wt[i] = trim * d[i]
        wc[i] = trim * pr * (1.0f64 - d[i]) / (1.0f64 - pr)
        mwt += wt[i]
        mwc += wc[i]
        md += d[i]
        st += wt[i] * dy[i]
        sc += wc[i] * dy[i]
        i += 1usize
    }
    mwt = mwt / nf
    mwc = mwc / nf
    md = md / nf
    var eta_t = 0.0f64
    var eta_c = 0.0f64
    if std {
        eta_t = (st / nf) / mwt
        eta_c = (sc / nf) / mwc
    } else {
        eta_t = (st / nf) / md
        eta_c = (sc / nf) / md
    }
    let att = eta_t - eta_c
    if part == 0usize { ret att }
    let (xw, e4) = mem.alloc[f64](a, p * p)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            var s2 = 0.0f64
            i = 0usize
            while i < n {
                s2 += ps[i] * (1.0f64 - ps[i]) * x[i * p + u] * x[i * p + v]
                i += 1usize
            }
            xw[u * p + v] = s2
            v += 1usize
        }
        u += 1usize
    }
    let (hi, e5) = mem.alloc[f64](a, p * p)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, xw, p, hi) != ok { ret 0.0f64 / 0.0f64 }
    let (m2, e6) = mem.alloc[f64](a, p)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    u = 0usize
    while u < p {
        var a2 = 0.0f64
        i = 0usize
        while i < n {
            if std { a2 += wc[i] * (dy[i] - eta_c) * x[i * p + u] } else { a2 += wc[i] * dy[i] * x[i * p + u] }
            i += 1usize
        }
        m2[u] = a2 / nf
        u += 1usize
    }
    let (inf, e7) = mem.alloc[f64](a, n)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        var ps_m2 = 0.0f64
        u = 0usize
        while u < p {
            var rp = 0.0f64
            var v = 0usize
            while v < p {
                rp += (d[i] - ps[i]) * x[i * p + v] * hi[v * p + u] * nf
                v += 1usize
            }
            ps_m2 += rp * m2[u]
            u += 1usize
        }
        if std {
            let inf_t = (wt[i] * dy[i] - wt[i] * eta_t) / mwt
            let inf_c = (wc[i] * dy[i] - wc[i] * eta_c + ps_m2) / mwc
            inf[i] = inf_t - inf_c
        } else {
            inf[i] = (wt[i] * dy[i] - wc[i] * dy[i] - ps_m2 - d[i] * att) / md
        }
        sum += inf[i]
        i += 1usize
    }
    let mean = sum / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (inf[i] - mean) * (inf[i] - mean)
        i += 1usize
    }
    ret math.sqrt[f64](ss / (nf - 1.0f64)) * math.sqrt[f64](nf - 1.0f64) / nf
}

// the least-squares coefficients of y on x over the rows where sel[i] is 1, into beta (p values); false when the fit fails
fn sub_ols(a: *mem.Arena, y: []const f64, x: []const f64, sel: []const f64, n: usize, p: usize, beta: []f64) -> bool {
    var m = 0usize
    var i = 0usize
    while i < n {
        if sel[i] == 1.0f64 { m += 1usize }
        i += 1usize
    }
    let (xs, e1) = mem.alloc[f64](a, m * p)
    if e1 != ok { ret false }
    let (ys, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret false }
    var r = 0usize
    i = 0usize
    while i < n {
        if sel[i] == 1.0f64 {
            var j = 0usize
            while j < p {
                xs[r * p + j] = x[i * p + j]
                j += 1usize
            }
            ys[r] = y[i]
            r += 1usize
        }
        i += 1usize
    }
    let (f, e3) = ols.ols(a, xs, ys, m, p)
    if e3 != ok { ret false }
    var j = 0usize
    while j < p {
        beta[j] = f.beta[j]
        j += 1usize
    }
    ret true
}

// reg_did_rc(y, post, D, covariates), the outcome-regression DiD estimator for repeated cross-sections: part 0 the ATT, 1 its standard error
fn reg_did_rc(a: *mem.Arena, y: []const f64, post: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    let nf = f64(n)
    let (pre_sel, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (post_sel, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        pre_sel[i] = 0.0f64
        post_sel[i] = 0.0f64
        if d[i] == 0.0f64 && post[i] == 0.0f64 { pre_sel[i] = 1.0f64 }
        if d[i] == 0.0f64 && post[i] == 1.0f64 { post_sel[i] = 1.0f64 }
        i += 1usize
    }
    let (b0, e3) = mem.alloc[f64](a, p)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (b1, e4) = mem.alloc[f64](a, p)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    if !sub_ols(a, y, x, pre_sel, n, p, b0) { ret 0.0f64 / 0.0f64 }
    if !sub_ols(a, y, x, post_sel, n, p, b1) { ret 0.0f64 / 0.0f64 }
    let (op, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    let (oq, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    var mtp = 0.0f64
    var mtq = 0.0f64
    var mc = 0.0f64
    var stp = 0.0f64
    var stq = 0.0f64
    var sc = 0.0f64
    i = 0usize
    while i < n {
        var v0 = 0.0f64
        var v1 = 0.0f64
        var j = 0usize
        while j < p {
            v0 += b0[j] * x[i * p + j]
            v1 += b1[j] * x[i * p + j]
            j += 1usize
        }
        op[i] = v0
        oq[i] = v1
        let wtp = d[i] * (1.0f64 - post[i])
        let wtq = d[i] * post[i]
        mtp += wtp
        mtq += wtq
        mc += d[i]
        stp += wtp * y[i]
        stq += wtq * y[i]
        sc += d[i] * (v1 - v0)
        i += 1usize
    }
    mtp = mtp / nf
    mtq = mtq / nf
    mc = mc / nf
    let eta_tp = (stp / nf) / mtp
    let eta_tq = (stq / nf) / mtq
    let eta_c = (sc / nf) / mc
    let att = (eta_tq - eta_tp) - eta_c
    if part == 0usize { ret att }
    let (xi0, e7) = mem.alloc[f64](a, p * p)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    let (xi1, e8) = mem.alloc[f64](a, p * p)
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    let (g0, e9) = mem.alloc[f64](a, p * p)
    if e9 != ok { ret 0.0f64 / 0.0f64 }
    let (g1, e10) = mem.alloc[f64](a, p * p)
    if e10 != ok { ret 0.0f64 / 0.0f64 }
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            var s0 = 0.0f64
            var s1 = 0.0f64
            i = 0usize
            while i < n {
                s0 += pre_sel[i] * x[i * p + u] * x[i * p + v]
                s1 += post_sel[i] * x[i * p + u] * x[i * p + v]
                i += 1usize
            }
            g0[u * p + v] = s0 / nf
            g1[u * p + v] = s1 / nf
            v += 1usize
        }
        u += 1usize
    }
    if ols.inverse(a, g0, p, xi0) != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, g1, p, xi1) != ok { ret 0.0f64 / 0.0f64 }
    let (m1, e11) = mem.alloc[f64](a, p)
    if e11 != ok { ret 0.0f64 / 0.0f64 }
    u = 0usize
    while u < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += d[i] * x[i * p + u]
            i += 1usize
        }
        m1[u] = s / nf
        u += 1usize
    }
    let (inf, e12) = mem.alloc[f64](a, n)
    if e12 != ok { ret 0.0f64 / 0.0f64 }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        let wtp = d[i] * (1.0f64 - post[i])
        let wtq = d[i] * post[i]
        let inf_t = (wtq * y[i] - wtq * eta_tq) / mtq - (wtp * y[i] - wtp * eta_tp) / mtp
        let c1 = d[i] * (oq[i] - op[i]) - d[i] * eta_c
        var c2post = 0.0f64
        var c2pre = 0.0f64
        u = 0usize
        while u < p {
            var rq = 0.0f64
            var rp = 0.0f64
            var v = 0usize
            while v < p {
                rq += post_sel[i] * (y[i] - oq[i]) * x[i * p + v] * xi1[v * p + u]
                rp += pre_sel[i] * (y[i] - op[i]) * x[i * p + v] * xi0[v * p + u]
                v += 1usize
            }
            c2post += rq * m1[u]
            c2pre += rp * m1[u]
            u += 1usize
        }
        inf[i] = inf_t - (c1 + c2post - c2pre) / mc
        sum += inf[i]
        i += 1usize
    }
    let mean = sum / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (inf[i] - mean) * (inf[i] - mean)
        i += 1usize
    }
    ret math.sqrt[f64](ss / (nf - 1.0f64)) * math.sqrt[f64](nf - 1.0f64) / nf
}
