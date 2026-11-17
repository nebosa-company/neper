// R metafor on a fitted rma.uni model: confint (qp, pl, ht, wald, wald.log, wald.sqrt for tau2), predict (confidence and prediction intervals), blup, rstandard (marginal and
// conditional), hatvalues, weights, influence (rstudent, dffits, cook.d, cov.r, tau2.del, QE.del, dfbetas), leave1out and cumul. Every refit is metaforfit.fit on a subset.
//
// Results go into out at X0 and after (the fit itself occupies 0 .. 135, see metaforrma).

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.pwr as pw
use e.algo.stat.metaforrma as mr
use e.algo.stat.metaforfit as mf

const X0: usize = 136usize
const STRIDE: usize = 16usize

// the model a feature works on: the data, the control and the fit in out; tmp is scratch for refits
type Mod = struct { ws: *mr.Ws, y: []const f64, v: []const f64, x: []const f64, k: usize, p: usize, c: mr.Ctl, out: []f64, tmp: []f64, a: *mem.Arena }

fn is_na(x: f64) -> bool { ret x != x }

// -------------------------------------------------------------------------------------------------------------------------------
// confint for tau2

type RootCtx = struct { m: *Mod, kind: usize, level_ref: f64, objective: f64, cache: f64 }

// kind 0: Q(tau2) - objective with the uncentered effects (the Q-profile); kind 1: -2 (ll(tau2) - ll(estimate)) - objective, the profile likelihood
fn root_f(c: *RootCtx, t: f64) -> f64 {
    let m = c.m
    if c.kind == 0usize {
        var q: mr.QeCtx = zero
        q.ws = m.ws
        q.ymc = m.y
        q.v = m.v
        q.x = m.x
        q.k = m.k
        q.p = m.p
        q.tgt = c.objective
        ret mr.qe_cb(&q, t)
    }
    var cc = m.c
    cc.tau2fix = t
    cc.skipr2 = true
    mf.fit(m.ws, m.y, m.v, m.x, m.k, m.p, &cc, m.tmp)
    var ll = m.tmp[mr.O_LLML]
    if m.c.method == 8usize { ll = m.tmp[mr.O_LLREML] }
    ret 0.0f64 - 2.0f64 * (ll - c.level_ref) - c.objective
}

fn uroot(c: *RootCtx, lo: f64, hi: f64) -> (f64, bool) {
    let flo = root_f(c, lo)
    let fhi = root_f(c, hi)
    if is_na(flo) || is_na(fhi) { ret (mr.nan(), false) }
    if flo * fhi > 0.0f64 { ret (mr.nan(), false) }
    ret (pw.zeroin[RootCtx](c, root_f, lo, hi, mr.uniroot_tol(), 1000i64), true)
}

fn uroot_gq(c: *mf.GqCtx, lo: f64, hi: f64) -> (f64, bool) {
    let flo = mf.genq_cb(c, lo)
    let fhi = mf.genq_cb(c, hi)
    if is_na(flo) || is_na(fhi) { ret (mr.nan(), false) }
    if flo * fhi > 0.0f64 { ret (mr.nan(), false) }
    ret (pw.zeroin[mf.GqCtx](c, mf.genq_cb, lo, hi, mr.uniroot_tol(), 1000i64), true)
}

// confint(x, type): out[X0 + 0..9] = tau2.lb, tau2.ub, I2.lb, I2.ub, H2.lb, H2.ub, tau.lb, tau.ub, lb converged, ub converged
// type 0 qp, 1 pl, 2 ht, 3 wald, 4 wald.log, 5 wald.sqrt
fn confint_tau2(m: *Mod, kind: usize) {
    let o = m.out
    let k = m.k
    let p = m.p
    let kf = f64(k)
    let pf = f64(p)
    let alpha = 1.0f64 - m.c.level
    let tau2 = o[mr.O_TAU2]
    var tmin = 0.0f64
    if tau2 < tmin { tmin = tau2 }
    var tmax = 100.0f64
    if tau2 * 10.0f64 > tmax { tmax = tau2 * 10.0f64 }
    if tmin * 10.0f64 > tmax { tmax = tmin * 10.0f64 }
    var lb = mr.nan()
    var ub = mr.nan()
    var lbc = false
    var ubc = false
    var rc: RootCtx = zero
    rc.m = m
    if kind == 0usize {
        let critu = nm.qchisq(alpha / 2.0f64, kf - pf, false, false)
        let critl = nm.qchisq(alpha / 2.0f64, kf - pf, true, false)
        rc.kind = 0usize
        rc.objective = 0.0f64
        let qmax = root_f(&rc, tmax)
        let qmin = root_f(&rc, tmin)
        if qmin < critl {
            lb = tmin
            ub = tmin
            lbc = true
            ubc = true
        } else {
            if qmax > critl {
                ub = tmax
                ubc = true
            } else {
                rc.objective = critl
                let (r, f) = uroot(&rc, tmin, tmax)
                ub = r
                ubc = f
            }
        }
        if qmax > critu {
            lb = tmax
            ub = tmax
            lbc = true
            ubc = true
        } else {
            if qmin < critu {
                lb = tmin
                lbc = true
            } else {
                rc.objective = critu
                let (r, f) = uroot(&rc, tmin, tmax)
                lb = r
                lbc = f
            }
        }
    }
    if kind == 1usize {
        rc.kind = 1usize
        var ll = o[mr.O_LLML]
        if m.c.method == 8usize { ll = o[mr.O_LLREML] }
        rc.level_ref = ll
        rc.objective = nm.qchisq(1.0f64 - alpha, 1.0f64, true, false)
        let r0 = root_f(&rc, tmin)
        if !is_na(r0) {
            if r0 < 0.0f64 {
                lb = tmin
                lbc = true
            } else {
                let (r, f) = uroot(&rc, tmin, tau2)
                lb = r
                lbc = f
            }
        }
        let r1 = root_f(&rc, tmax)
        if !is_na(r1) {
            if r1 < 0.0f64 {
                ub = tmax
                ubc = true
            } else {
                let (r, f) = uroot(&rc, tau2, tmax)
                ub = r
                ubc = f
            }
        }
    }
    if kind == 6usize {
        // the generalized Q confidence interval of a GENQ or GENQM model
        var gc: mf.GqCtx = zero
        gc.ws = m.ws
        gc.v = m.v
        gc.k = k
        gc.p = p
        if mr.pbuild(m.ws, m.x, m.c.aw, k, p) {
            gc.q = mr.pquad(m.ws, m.y, k)
            gc.level = 0.0f64
            gc.lower = true
            let gmax = mf.genq_cb(&gc, tmax)
            let gmin = mf.genq_cb(&gc, tmin)
            let a2 = alpha / 2.0f64
            if gmin > 1.0f64 - a2 {
                lb = tmin
                ub = tmin
                lbc = true
                ubc = true
            } else {
                if gmax < 1.0f64 - a2 {
                    ub = tmax
                    ubc = true
                } else {
                    gc.level = a2
                    gc.lower = false
                    let (r, f) = uroot_gq(&gc, tmin, tmax)
                    ub = r
                    ubc = f
                }
            }
            if gmax < a2 {
                lb = tmax
                ub = tmax
                lbc = true
                ubc = true
            } else {
                if gmin > a2 {
                    lb = tmin
                    lbc = true
                } else {
                    gc.level = a2
                    gc.lower = true
                    let (r, f) = uroot_gq(&gc, tmin, tmax)
                    lb = r
                    lbc = f
                }
            }
        }
    }
    let crit = dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, false, false)
    if kind == 2usize {
        var se = 0.0f64
        let qe = o[mr.O_QE]
        if qe > kf {
            se = 0.5f64 * (math.log[f64](qe) - math.log[f64](kf - 1.0f64)) / (math.sqrt[f64](2.0f64 * qe) - math.sqrt[f64](2.0f64 * kf - 3.0f64))
        } else {
            se = math.sqrt[f64](1.0f64 / (2.0f64 * (kf - 2.0f64)) * (1.0f64 - 1.0f64 / (3.0f64 * (kf - 2.0f64) * (kf - 2.0f64))))
        }
        let h2l = math.exp[f64](math.log[f64](o[mr.O_H2]) - crit * 2.0f64 * se)
        let h2u = math.exp[f64](math.log[f64](o[mr.O_H2]) + crit * 2.0f64 * se)
        let i2l = (h2l - 1.0f64) / h2l
        let i2u = (h2u - 1.0f64) / h2u
        lb = mr.max0(i2l * o[mr.O_VT] / (1.0f64 - i2l))
        ub = i2u * o[mr.O_VT] / (1.0f64 - i2u)
        lbc = true
        ubc = true
    }
    if kind == 3usize {
        lb = tau2 - crit * o[mr.O_SETAU2]
        ub = tau2 + crit * o[mr.O_SETAU2]
        if lb < 0.0f64 { lb = 0.0f64 }
        lbc = true
        ubc = true
    }
    if kind == 4usize {
        lbc = true
        ubc = true
        if tau2 >= 0.0f64 {
            lb = math.exp[f64](math.log[f64](tau2) - crit * o[mr.O_SETAU2] / tau2)
            ub = math.exp[f64](math.log[f64](tau2) + crit * o[mr.O_SETAU2] / tau2)
            if tau2 > ub { ub = tau2 }
        }
    }
    if kind == 5usize {
        lbc = true
        ubc = true
        if tau2 >= 0.0f64 {
            let st = math.sqrt[f64](tau2)
            var lo = st - crit * o[mr.O_SETAU2] / (2.0f64 * st)
            if lo < 0.0f64 { lo = 0.0f64 }
            lb = lo * lo
            let hi = st + crit * o[mr.O_SETAU2] / (2.0f64 * st)
            ub = hi * hi
        }
    }
    let vt = o[mr.O_VT]
    o[X0] = lb
    o[X0 + 1usize] = ub
    o[X0 + 2usize] = 100.0f64 * lb / (vt + lb)
    o[X0 + 3usize] = 100.0f64 * ub / (vt + ub)
    o[X0 + 4usize] = lb / vt + 1.0f64
    o[X0 + 5usize] = ub / vt + 1.0f64
    var tl = mr.nan()
    var tu = mr.nan()
    if lb >= 0.0f64 { tl = math.sqrt[f64](lb) }
    if ub >= 0.0f64 { tu = math.sqrt[f64](ub) }
    o[X0 + 6usize] = tl
    o[X0 + 7usize] = tu
    o[X0 + 8usize] = 0.0f64
    if lbc { o[X0 + 8usize] = 1.0f64 }
    o[X0 + 9usize] = 0.0f64
    if ubc { o[X0 + 9usize] = 1.0f64 }
}

// -------------------------------------------------------------------------------------------------------------------------------
// the hat matrix, residuals and weights

// ws.pm = H = X S X' W for the model's weights (the marginal ones, or the user weights, or unit weights)
fn hat_matrix(m: *Mod, h: []f64) -> bool {
    let k = m.k
    let p = m.p
    let ws = m.ws
    var i = 0usize
    while i < k {
        if m.c.weighted {
            if m.c.aw.len >= k { ws.wfe[i] = m.c.aw[i] } else { ws.wfe[i] = 1.0f64 / (m.v[i] + m.out[mr.O_TAU2]) }
        } else {
            ws.wfe[i] = 1.0f64
        }
        i += 1usize
    }
    if !mr.xwx_inv(ws, m.x, ws.wfe, k, p) { ret false }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var t = 0.0f64
            var a = 0usize
            while a < p {
                var b = 0usize
                while b < p {
                    t += m.x[i * p + a] * ws.s[a * p + b] * m.x[j * p + b]
                    b += 1usize
                }
                a += 1usize
            }
            h[i * k + j] = t * ws.wfe[j]
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// out[X0 + i * STRIDE + 0..2] marginal residual, se, z; + 3..5 conditional; + 6 hat; + 7 weight (percent)
fn residuals(m: *Mod, h: []f64) {
    let k = m.k
    let p = m.p
    let o = m.out
    let tau2 = o[mr.O_TAU2]
    if !hat_matrix(m, h) { ret }
    var sw = 0.0f64
    var i = 0usize
    while i < k {
        var wi = 1.0f64 / (m.v[i] + tau2)
        if !m.c.weighted { wi = 1.0f64 / f64(k) } else if m.c.aw.len >= k { wi = m.c.aw[i] }
        m.ws.w[i] = wi
        sw += wi
        i += 1usize
    }
    i = 0usize
    while i < k {
        var f = 0.0f64
        var a = 0usize
        while a < p {
            f += m.x[i * p + a] * o[mr.O_BETA + a]
            a += 1usize
        }
        var ei = m.y[i] - f
        if math.abs[f64](ei) < 100.0f64 * 2.220446049250313e-16f64 { ei = 0.0f64 }
        // ve_ii = sum_j,l (I - H)_ij M_jl (I - H)_il with M diagonal
        var ve = 0.0f64
        var j = 0usize
        while j < k {
            var imh = 0.0f64 - h[i * k + j]
            if i == j { imh += 1.0f64 }
            ve += imh * imh * (m.v[j] + tau2)
            j += 1usize
        }
        let sei = math.sqrt[f64](ve)
        let b = X0 + i * STRIDE
        o[b] = ei
        o[b + 1usize] = sei
        o[b + 2usize] = ei / sei
        let li = tau2 / (tau2 + m.v[i])
        let pr = li * m.y[i] + (1.0f64 - li) * f
        let ec = m.y[i] - pr
        let sec = math.sqrt[f64](m.v[i] * m.v[i] * (1.0f64 / (m.v[i] + tau2)) * (1.0f64 - h[i * k + i]))
        o[b + 3usize] = ec
        o[b + 4usize] = sec
        o[b + 5usize] = ec / sec
        var hii = h[i * k + i]
        if hii > 1.0f64 - 10.0f64 * 2.220446049250313e-16f64 { hii = 1.0f64 }
        o[b + 6usize] = hii
        o[b + 7usize] = m.ws.w[i] / sw * 100.0f64
        i += 1usize
    }
}

// blup: out[X0 + i * STRIDE + 8..11] = pred, se, pi.lb, pi.ub
fn blup(m: *Mod) {
    let k = m.k
    let p = m.p
    let o = m.out
    let tau2 = o[mr.O_TAU2]
    let alpha = 1.0f64 - m.c.level
    var crit = 0.0f64
    if m.c.test >= 1usize { crit = nb.qt(alpha / 2.0f64, o[mr.O_DDF], false, false) } else { crit = dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, false, false) }
    var i = 0usize
    while i < k {
        let li = tau2 / (tau2 + m.v[i])
        var f = 0.0f64
        var q = 0.0f64
        var a = 0usize
        while a < p {
            f += m.x[i * p + a] * o[mr.O_BETA + a]
            var b = 0usize
            while b < p {
                q += m.x[i * p + a] * o[mr.O_VB + a * p + b] * m.x[i * p + b]
                b += 1usize
            }
            a += 1usize
        }
        let pred = li * m.y[i] + (1.0f64 - li) * f
        var vp = 0.0f64
        if li == 1.0f64 { vp = li * m.v[i] } else { vp = li * m.v[i] + (1.0f64 - li) * (1.0f64 - li) * q }
        let se = math.sqrt[f64](vp)
        let b0 = X0 + i * STRIDE + 8usize
        o[b0] = pred
        o[b0 + 1usize] = se
        o[b0 + 2usize] = pred - crit * se
        o[b0 + 3usize] = pred + crit * se
        i += 1usize
    }
}

// predict for the nnew rows xn (row-major, p columns): out[X0 + r * STRIDE + 0..5] = pred, se, ci.lb, ci.ub, pi.lb, pi.ub
// predtype 0 default, 1 simple, 2 riley, 3 t
fn predict(m: *Mod, xn: []const f64, nnew: usize, predtype: usize, adjust: bool) {
    let p = m.p
    let o = m.out
    let alpha = 1.0f64 - m.c.level
    var div = 2.0f64
    if adjust { div = 2.0f64 * f64(nnew) }
    let tdist = m.c.test >= 1usize
    let ddf = o[mr.O_DDF]
    var r = 0usize
    while r < nnew {
        var pred = 0.0f64
        var vp = 0.0f64
        var a = 0usize
        while a < p {
            pred += xn[r * p + a] * o[mr.O_BETA + a]
            var b = 0usize
            while b < p {
                vp += xn[r * p + a] * o[mr.O_VB + a * p + b] * xn[r * p + b]
                b += 1usize
            }
            a += 1usize
        }
        var crit = 0.0f64
        if tdist {
            if ddf > 0.0f64 { crit = nb.qt(alpha / div, ddf, false, false) } else { crit = mr.nan() }
        } else {
            crit = dist.qnorm(alpha / div, 0.0f64, 1.0f64, false, false)
        }
        if vp < 0.0f64 { vp = mr.nan() }
        let se = math.sqrt[f64](vp)
        let ci_lb = pred - crit * se
        let ci_ub = pred + crit * se
        var pcrit = crit
        var vpred = vp
        if predtype == 1usize {
            pcrit = dist.qnorm(alpha / div, 0.0f64, 1.0f64, false, false)
            vpred = 0.0f64
        }
        if predtype >= 2usize {
            var pdf = ddf
            if predtype == 2usize { pdf = ddf - o[mr.O_QM] * 0.0f64 - f64(m.p) * 0.0f64 }
            if predtype == 2usize {
                var parms = f64(m.p)
                if m.c.method != 0usize && !(m.c.tau2fix == m.c.tau2fix) { parms += 1.0f64 }
                pdf = ddf - parms + f64(m.p)
            }
            if pdf < 1.0f64 { pdf = 1.0f64 }
            pcrit = nb.qt(alpha / div, pdf, false, false)
        }
        let pse = math.sqrt[f64](vpred + o[mr.O_TAU2])
        let b0 = X0 + r * STRIDE
        o[b0] = pred
        o[b0 + 1usize] = se
        o[b0 + 2usize] = ci_lb
        o[b0 + 3usize] = ci_ub
        o[b0 + 4usize] = pred - pcrit * pse
        o[b0 + 5usize] = pred + pcrit * pse
        r += 1usize
    }
}

// -------------------------------------------------------------------------------------------------------------------------------
// refits on subsets

// fit on the rows with incl[i] != 0 (the first n rows of the model), results into m.tmp; the copies live in the arena
fn subset_fit(m: *Mod, incl: []const f64, intercept: bool, tmp: []f64) -> usize {
    let p = m.p
    var n = 0usize
    var i = 0usize
    while i < m.k {
        if incl[i] != 0.0f64 { n += 1usize }
        i += 1usize
    }
    let (sy, e1) = mem.alloc[f64](m.a, n)
    let (sv, e2) = mem.alloc[f64](m.a, n)
    let (sx, e3) = mem.alloc[f64](m.a, n * p)
    let (sw, e4) = mem.alloc[f64](m.a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    var j = 0usize
    i = 0usize
    while i < m.k {
        if incl[i] != 0.0f64 {
            sy[j] = m.y[i]
            sv[j] = m.v[i]
            var a = 0usize
            while a < p {
                sx[j * p + a] = m.x[i * p + a]
                a += 1usize
            }
            if m.c.aw.len >= m.k { sw[j] = m.c.aw[i] }
            j += 1usize
        }
        i += 1usize
    }
    var c = m.c
    c.skipr2 = true
    c.intercept = intercept
    if m.c.aw.len >= m.k { c.aw = sw[0usize..n] }
    mf.fit(m.ws, sy, sv, sx, n, p, &c, tmp)
    ret n
}

// leave1out (the model must be intercept-only): out[X0 + i * STRIDE + 0..10] = beta, se, zval, pval, ci.lb, ci.ub, QE, QEp, tau2, I2, H2 without study i
fn leave1out(m: *Mod) {
    let k = m.k
    let (incl, e) = mem.alloc[f64](m.a, k)
    if e != ok { ret }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            if j == i { incl[j] = 0.0f64 } else { incl[j] = 1.0f64 }
            j += 1usize
        }
        let _ = subset_fit(m, incl, true, m.tmp)
        store_row(m, X0 + i * STRIDE)
        i += 1usize
    }
}

// cumul in the data order: the first i + 1 studies
fn cumul(m: *Mod) {
    let k = m.k
    let (incl, e) = mem.alloc[f64](m.a, k)
    if e != ok { ret }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            if j <= i { incl[j] = 1.0f64 } else { incl[j] = 0.0f64 }
            j += 1usize
        }
        let _ = subset_fit(m, incl, true, m.tmp)
        store_row(m, X0 + i * STRIDE)
        i += 1usize
    }
}

fn store_row(m: *Mod, b: usize) {
    let t = m.tmp
    let o = m.out
    o[b] = t[mr.O_BETA]
    o[b + 1usize] = t[mr.O_SE]
    o[b + 2usize] = t[mr.O_Z]
    o[b + 3usize] = t[mr.O_P]
    o[b + 4usize] = t[mr.O_CILB]
    o[b + 5usize] = t[mr.O_CIUB]
    o[b + 6usize] = t[mr.O_QE]
    o[b + 7usize] = t[mr.O_QEP]
    o[b + 8usize] = t[mr.O_TAU2]
    o[b + 9usize] = t[mr.O_I2]
    o[b + 10usize] = t[mr.O_H2]
}

// influence: out[X0 + i * STRIDE + 0..7] = rstudent, dffits, cook.d, cov.r, tau2.del, QE.del, hat, weight; 8 + a: dfbetas of coefficient a
fn influence(m: *Mod, h: []f64) {
    let k = m.k
    let p = m.p
    let o = m.out
    let (incl, e) = mem.alloc[f64](m.a, k)
    if e != ok { ret }
    let (svb, e2) = mem.alloc[f64](m.a, p * p)
    if e2 != ok { ret }
    let (sub, e3) = mem.alloc[f64](m.a, p * p)
    if e3 != ok { ret }
    let (sub2, e4) = mem.alloc[f64](m.a, p * p)
    if e4 != ok { ret }
    let (aug, e5) = mem.alloc[f64](m.a, 2usize * p * p)
    if e5 != ok { ret }
    let (wdel, e6) = mem.alloc[f64](m.a, k)
    if e6 != ok { ret }
    residuals(m, h)
    let btt0 = 0usize
    let nb2 = p - btt0
    var a = 0usize
    while a < nb2 {
        var b = 0usize
        while b < nb2 {
            sub[a * nb2 + b] = o[mr.O_VB + (a + btt0) * p + b + btt0]
            b += 1usize
        }
        a += 1usize
    }
    let ok1 = mr.invert_into(sub, nb2, aug, svb)
    let ldfull = mr.logdet_of(sub, nb2, sub2)
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            if j == i { incl[j] = 0.0f64 } else { incl[j] = 1.0f64 }
            j += 1usize
        }
        let n = subset_fit(m, incl, false, m.tmp)
        let t = m.tmp
        let base = X0 + i * STRIDE
        let tau2del = t[mr.O_TAU2]
        var delpred = 0.0f64
        var vdel = 0.0f64
        var f = 0.0f64
        a = 0usize
        while a < p {
            delpred += m.x[i * p + a] * t[mr.O_BETA + a]
            f += m.x[i * p + a] * o[mr.O_BETA + a]
            var b = 0usize
            while b < p {
                vdel += m.x[i * p + a] * t[mr.O_VB + a * p + b] * m.x[i * p + b]
                b += 1usize
            }
            a += 1usize
        }
        let s2w = t[mr.O_S2W]
        let hii = o[base + 6usize]
        var dff = (f - delpred) / math.sqrt[f64](s2w * hii * (tau2del + m.v[i]))
        let _ = n
        // vb.del: the inverse of X' W X over all k rows with the weights 1 / (v + tau2.del)
        a = 0usize
        while a < k {
            wdel[a] = 1.0f64 / (m.v[a] + tau2del)
            a += 1usize
        }
        let okv = mr.xwx_inv(m.ws, m.x, wdel, k, p)
        a = 0usize
        while a < p {
            var dfb = o[mr.O_BETA + a] - t[mr.O_BETA + a]
            if okv { o[base + 8usize + a] = dfb / math.sqrt[f64](s2w * m.ws.s[a * p + a]) }
            a += 1usize
        }
        // Cook's distance and the covariance ratio over the moderators
        var cook = 0.0f64
        a = 0usize
        while a < nb2 {
            var b = 0usize
            while b < nb2 {
                cook += (o[mr.O_BETA + btt0 + a] - t[mr.O_BETA + btt0 + a]) * svb[a * nb2 + b] * (o[mr.O_BETA + btt0 + b] - t[mr.O_BETA + btt0 + b])
                b += 1usize
            }
            a += 1usize
        }
        a = 0usize
        while a < nb2 {
            var b = 0usize
            while b < nb2 {
                sub2[a * nb2 + b] = t[mr.O_VB + (a + btt0) * p + b + btt0]
                b += 1usize
            }
            a += 1usize
        }
        let ldd = mr.logdet_of(sub2, nb2, aug)
        let resid0 = m.y[i] - delpred
        var resid = resid0
        if math.abs[f64](resid) < 100.0f64 * 2.220446049250313e-16f64 { resid = 0.0f64 }
        let seresid = math.sqrt[f64](m.v[i] * s2w + vdel + tau2del * s2w)
        o[base] = resid / seresid
        o[base + 1usize] = dff
        o[base + 2usize] = cook
        o[base + 3usize] = math.exp[f64](ldd - ldfull)
        o[base + 4usize] = tau2del
        o[base + 5usize] = t[mr.O_QE]
        i += 1usize
    }
    let _ = ok1
}
