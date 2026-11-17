// R fdrtool::fdrtool for p values (statistic = "pvalue", cutoff.method = "fndr"): the cutoff by the false
// non-discovery rate, the null proportion eta0 from the censored sample, the Grenander estimator of the p-value
// density (the least concave majorant of the eta0-corrected empirical distribution, by isotonic regression of the
// slopes), and from it the local false discovery rate and the tail-area q values.
//
// And the normal statistic (fdrtool_normal, with R's optimize). Not here: the correlation and Student t statistics, the other cutoff
// methods, the plots, monoreg.

use e.algo.sort
use e.algo.stat.mass as ms
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

type Fdr = struct { eta0: f64, cutoff: f64, ncens: usize }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sorted_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    ret (s, ok)
}

// pval.estimate.eta0(p, method = "quantile", q = 0.1, lambda = seq(0, 0.9, 0.05))
fn estimate_eta0(a: *mem.Arena, p: []const f64) -> (f64, err) {
    let (e0, e) = mem.alloc[f64](a, 19usize)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < 19usize {
        let lam = f64(i) * 0.05f64
        var c = 0.0f64
        var k = 0usize
        while k < p.len {
            if p[k] >= lam { c += 1.0f64 }
            k += 1usize
        }
        var v = c / f64(p.len) / (1.0f64 - lam)
        if v > 1.0f64 { v = 1.0f64 }
        if v < 0.0f64 { v = 0.0f64 }
        e0[i] = v
        i += 1usize
    }
    let (s, se) = sorted_copy(a, e0)
    if se != ok { ret (0.0f64, se) }
    ret (ms.quant7(s, 0.1f64), ok)
}

// the fndr cutoff on the p-value scale
fn fndr_cutoff(a: *mem.Arena, p: []const f64) -> (f64, err) {
    let n = p.len
    let (e0, ee) = estimate_eta0(a, p)
    if ee != ok { ret (0.0f64, ee) }
    let (ax, ae) = mem.alloc[f64](a, n)
    if ae != ok { ret (0.0f64, ae) }
    var i = 0usize
    while i < n {
        ax[i] = 1.0f64 - p[i]
        i += 1usize
    }
    let (sx, se) = sorted_copy(a, ax)
    if se != ok { ret (0.0f64, se) }
    var pr = 0.99f64
    if e0 < pr { pr = e0 }
    var zeta0 = ms.quant7(sx, pr)
    var f2 = fndr_at(ax, e0, zeta0)
    var f1 = fndr_at(ax, e0, 0.9f64 * zeta0)
    while f1 < f2 {
        zeta0 = zeta0 * 0.9f64
        f2 = f1
        f1 = fndr_at(ax, e0, 0.9f64 * zeta0)
    }
    ret (1.0f64 - zeta0, ok)
}

fn fndr_at(ax: []const f64, e0: f64, x: f64) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < ax.len {
        if ax[i] < x { c += 1.0f64 }
        i += 1usize
    }
    let fx = c / f64(ax.len)
    if fx == 0.0f64 { ret 0.0f64 }
    let v = (fx - e0 * x) / fx
    if v < 0.0f64 { ret 0.0f64 }
    ret v
}

// weighted pool-adjacent-violators (C_isomean): ghat receives the isotonic fit of y with weights w
fn isomean(y: []const f64, w: []const f64, ghat: []f64, gew: []f64, k: []usize) {
    var nn = y.len
    if nn == 1usize {
        ghat[0usize] = y[0usize]
        ret
    }
    var c = 0usize
    k[0usize] = 0usize
    gew[0usize] = w[0usize]
    ghat[0usize] = y[0usize]
    var j = 1usize
    while j < nn {
        c += 1usize
        k[c] = j
        gew[c] = w[j]
        ghat[c] = y[j]
        while ghat[c - 1usize] >= ghat[c] {
            let neu = gew[c] + gew[c - 1usize]
            ghat[c - 1usize] = ghat[c - 1usize] + (gew[c] / neu) * (ghat[c] - ghat[c - 1usize])
            gew[c - 1usize] = neu
            c -= 1usize
            if c == 0usize { break }
        }
        j += 1usize
    }
    while nn >= 1usize {
        var i = k[c]
        while i < nn {
            ghat[i] = ghat[c]
            i += 1usize
        }
        nn = k[c]
        if c == 0usize { break }
        c -= 1usize
    }
}

// steps 3 and 4 of fdrtool: the empirical distribution of the p values corrected by eta0, its Grenander estimator, and from them
// the tail-area q values and the local false discovery rate
fn fdrtool_core(a: *mem.Arena, p: []const f64, eta0: f64, qval: []f64, lfdr: []f64) -> err {
    let n = p.len
    let nf = f64(n)
    // ecdf.pval(p, eta0): the step values at the unique sorted p, then 0 and 1 added when missing
    let (sp, se) = sorted_copy(a, p)
    if se != ok { ret se }
    let (vals, e1) = mem.alloc[f64](a, n + 2usize)
    let (fr, e2) = mem.alloc[f64](a, n + 2usize)
    if e1 != ok || e2 != ok { ret e1 }
    var nv = 0usize
    var cum = 0.0f64
    var i = 0usize
    while i < n {
        cum += 1.0f64
        if i + 1usize == n || sp[i + 1usize] != sp[i] {
            var f = cum / nf
            let hi = 1.0f64 - eta0 * (1.0f64 - sp[i])
            if f > hi { f = hi }
            let lo = eta0 * sp[i]
            if f < lo { f = lo }
            vals[nv] = sp[i]
            fr[nv] = f
            nv += 1usize
        }
        i += 1usize
    }
    if vals[nv - 1usize] != 1.0f64 {
        vals[nv] = 1.0f64
        fr[nv] = 1.0f64
        nv += 1usize
    }
    if vals[0usize] != 0.0f64 {
        var j = nv
        while j > 0usize {
            vals[j] = vals[j - 1usize]
            fr[j] = fr[j - 1usize]
            j -= 1usize
        }
        vals[0usize] = 0.0f64
        fr[0usize] = 0.0f64
        nv += 1usize
    }
    let ii = nv - 2usize
    fr[ii] = 1.0f64 - eta0 * (1.0f64 - vals[ii])
    // gcmlcm(vals, fr, "lcm"): slopes by isotonic regression of -rawslope
    let nd = nv - 1usize
    let (dx, e3) = mem.alloc[f64](a, nd)
    let (rs, e4) = mem.alloc[f64](a, nd)
    let (gh, e5) = mem.alloc[f64](a, nd)
    let (gw, e6) = mem.alloc[f64](a, nd)
    let (kk, e7) = mem.alloc[usize](a, nd)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e3 }
    i = 0usize
    while i < nd {
        dx[i] = vals[i + 1usize] - vals[i]
        var r = (fr[i + 1usize] - fr[i]) / dx[i]
        if r > 1.7976931348623157e308f64 { r = 1.7976931348623157e308f64 }
        if r < 0.0f64 - 1.7976931348623157e308f64 { r = 0.0f64 - 1.7976931348623157e308f64 }
        rs[i] = 0.0f64 - r
        i += 1usize
    }
    isomean(rs, dx, gh, gw, kk)
    // slope = -gh; knots where the slope changes
    let (xk, e8) = mem.alloc[f64](a, nd + 1usize)
    let (yk, e9) = mem.alloc[f64](a, nd + 1usize)
    let (sk, e10) = mem.alloc[f64](a, nd + 1usize)
    if e8 != ok || e9 != ok || e10 != ok { ret e8 }
    var nk = 0usize
    i = 0usize
    while i < nd {
        let sl = 0.0f64 - gh[i]
        var dup = false
        var j = 0usize
        while j < nk {
            if sk[j] == sl { dup = true }
            j += 1usize
        }
        if !dup {
            xk[nk] = vals[i]
            sk[nk] = sl
            nk += 1usize
        }
        i += 1usize
    }
    xk[nk] = vals[nv - 1usize]
    yk[0usize] = fr[0usize]
    i = 0usize
    while i < nk {
        yk[i + 1usize] = yk[i] + (xk[i + 1usize] - xk[i]) * sk[i]
        i += 1usize
    }
    // evaluate: F (linear interpolation, 0 left, last right) and f (step, rule 2)
    i = 0usize
    while i < n {
        var pv = p[i]
        var fF = 0.0f64
        var ff = sk[nk - 1usize]
        if pv <= xk[0usize] {
            fF = 0.0f64
            if pv == xk[0usize] { fF = yk[0usize] }
            ff = sk[0usize]
        } else if pv >= xk[nk] {
            fF = yk[nk]
            ff = sk[nk - 1usize]
        } else {
            var lo = 0usize
            var hi = nk
            while lo + 1usize < hi {
                let mid = (lo + hi) / 2usize
                if pv < xk[mid] { hi = mid } else { lo = mid }
            }
            fF = yk[lo] + (yk[hi] - yk[lo]) * ((pv - xk[lo]) / (xk[hi] - xk[lo]))
            ff = sk[lo]
            if pv == xk[hi] { ff = sk[hi] }
        }
        var qv = eta0 * p[i] / fF
        if qv > 1.0f64 { qv = 1.0f64 }
        qval[i] = qv
        if pv == 2.220446049250313e-16f64 { pv = 0.0f64 }
        var lv = eta0 / ff
        if lv > 1.0f64 { lv = 1.0f64 }
        lfdr[i] = lv
        i += 1usize
    }
    ret ok
}

// fdrtool(p, statistic = "pvalue", plot = FALSE): fills qval and lfdr (both p.len) and answers eta0, the cutoff
// and the number of censored p values
fn fdrtool_pvalue(a: *mem.Arena, p: []const f64, qval: []f64, lfdr: []f64) -> (Fdr, err) {
    let (r, e) = fdrtool_pvalue_cut(a, p, qval, lfdr, 0u8, 0.75f64)
    ret (r, e)
}

// cutoff.method: 0 "fndr", 1 "pct0" (the 1 - pct0 quantile of the p values)
fn fdrtool_pvalue_cut(a: *mem.Arena, p: []const f64, qval: []f64, lfdr: []f64, method: u8, pct0: f64) -> (Fdr, err) {
    var res: Fdr = zero
    let n = p.len
    let nf = f64(n)
    var x0 = 0.0f64
    if method == 1u8 {
        let (sp0, spe) = sorted_copy(a, p)
        if spe != ok { ret (res, spe) }
        x0 = ms.quant7(sp0, 1.0f64 - pct0)
    } else {
        let (xf, ce) = fndr_cutoff(a, p)
        if ce != ok { ret (res, ce) }
        x0 = xf
    }
    var ncens = 0usize
    var i = 0usize
    while i < n {
        if p[i] >= x0 { ncens += 1usize }
        i += 1usize
    }
    let m = 1.0f64 - x0
    let th = f64(ncens) / nf
    var eta0 = th / m
    if eta0 > 1.0f64 { eta0 = 1.0f64 }
    res.eta0 = eta0
    res.cutoff = x0
    res.ncens = ncens
    let ce2 = fdrtool_core(a, p, eta0, qval, lfdr)
    ret (res, ce2)
}


// ---- statistic = "normal" ----

type Nf = struct { eta0: f64, cutoff: f64, ncens: usize, sd: f64, sd_se: f64, eta0_se: f64 }

fn pnorm1(z: f64) -> f64 { ret dist.pnorm(z, 0.0f64, 1.0f64, true, false) }

// the two-sided p value of the normal null model: pmax(eps, 2 - 2 F0(|x|; sd)), 0 for an infinite x
fn nm_pval(x: f64, sd: f64) -> f64 { ret stat_pval(0u8, x, sd) }

// the null models: stat 0 normal (the parameter is sd), stat 1 correlation (the parameter is kappa, df = kappa - 1)
fn r2t(r: f64, kappa: f64) -> f64 { ret r * math.sqrt[f64]((kappa - 1.0f64) / (1.0f64 - r * r)) }

fn stat_cdf(stat: u8, x: f64, p: f64) -> f64 {
    if stat == 0u8 { ret dist.pnorm(x, 0.0f64, p, true, false) }
    if stat == 2u8 { ret nb.pt(x, p, true, false) }
    ret nb.pt(r2t(x, p), p - 1.0f64, true, false)
}

fn stat_pval(stat: u8, x: f64, p: f64) -> f64 {
    var ax = x
    if ax < 0.0f64 { ax = 0.0f64 - ax }
    if ax > 1.0e300f64 { ret 0.0f64 }
    var v = 2.0f64 - 2.0f64 * stat_cdf(stat, ax, p)
    if v < 2.220446049250313e-16f64 { v = 2.220446049250313e-16f64 }
    ret v
}

// the log density of the untruncated null
fn stat_logf0(stat: u8, x: f64, p: f64) -> f64 {
    if stat == 0u8 { ret dist.dnorm(x, 0.0f64, p, true) }
    if stat == 2u8 { ret nb.dt(x, p, true) }
    let df = p - 1.0f64
    let vol = math.sqrt[f64](df) * math.pow[f64](1.0f64 - x * x, 0.0f64 - 1.5f64)
    ret nb.dt(r2t(x, p), df, true) + math.log[f64](vol)
}

// the interquartile range of the null at the parameter
fn stat_iqr(stat: u8, p: f64) -> f64 {
    if stat == 0u8 { ret p * 2.0f64 * dist.qnorm(0.75f64, 0.0f64, 1.0f64, true, false) }
    if stat == 2u8 { ret nb.qt(0.75f64, p, true, false) - nb.qt(0.25f64, p, true, false) }
    let df = p - 1.0f64
    let q3 = nb.qt(0.75f64, df, true, false)
    let q1 = nb.qt(0.25f64, df, true, false)
    ret q3 / math.sqrt[f64](q3 * q3 + df) - q1 / math.sqrt[f64](q1 * q1 + df)
}

// R's optimize() (Brent_fmin) of f over (lo, hi), tol = eps^0.25
fn brent_min[C: type](ctx: *C, f: fn(*C, f64) -> f64, lo: f64, hi: f64) -> f64 {
    ret brent_min_tol[C](ctx, f, lo, hi, math.sqrt[f64](math.sqrt[f64](2.220446049250313e-16f64)))
}

// the same with the tolerance given (optimize(tol = ))
fn brent_min_tol[C: type](ctx: *C, f: fn(*C, f64) -> f64, lo: f64, hi: f64, tol: f64) -> f64 {
    let c = (3.0f64 - math.sqrt[f64](5.0f64)) * 0.5f64
    let eps = math.sqrt[f64](2.220446049250313e-16f64)
    var a = lo
    var b = hi
    var v = a + c * (b - a)
    var w = v
    var x = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = f(ctx, x)
    var fv = fx
    var fw = fx
    let tol3 = tol / 3.0f64
    var going = true
    while going {
        let xm = (a + b) * 0.5f64
        let tol1 = eps * math.abs[f64](x) + tol3
        let t2 = tol1 * 2.0f64
        if math.abs[f64](x - xm) <= t2 - (b - a) * 0.5f64 { break }
        var p = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        if math.abs[f64](e) > tol1 {
            r = (x - w) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - w) * r
            q = (q - r) * 2.0f64
            if q > 0.0f64 { p = 0.0f64 - p } else { q = 0.0f64 - q }
            r = e
            e = d
        }
        var u = 0.0f64
        if math.abs[f64](p) >= math.abs[f64](q * 0.5f64 * r) || p <= q * (a - x) || p >= q * (b - x) {
            if x < xm { e = b - x } else { e = a - x }
            d = c * e
        } else {
            d = p / q
            u = x + d
            if u - a < t2 || b - u < t2 {
                d = tol1
                if x >= xm { d = 0.0f64 - d }
            }
        }
        if math.abs[f64](d) >= tol1 {
            u = x + d
        } else if d > 0.0f64 {
            u = x + tol1
        } else {
            u = x - tol1
        }
        let fu = f(ctx, u)
        if fu <= fx {
            if u < x { b = x } else { a = x }
            v = w
            w = x
            x = u
            fv = fw
            fw = fx
            fx = fu
        } else {
            if u < x { a = u } else { b = u }
            if fu <= fw || w == x {
                v = w
                fv = fw
                w = u
                fw = fu
            } else if fu <= fv || v == x || v == w {
                v = u
                fv = fu
            }
        }
    }
    ret x
}

type Cens = struct { xc: []f64, x0: f64, stat: u8 }

// the negative log likelihood of the censored sample under N(0, sd^2)
fn cens_nlogl(c: *Cens, sd: f64) -> f64 {
    // R's sum() accumulates in long double; a compensated (two-sum) accumulation stands for it
    var s = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < c.xc.len {
        let v = stat_logf0(c.stat, c.xc[i], sd)
        let t = s + v
        var bp = t - s
        let err1 = (s - (t - bp)) + (v - bp)
        comp += err1
        s = t
        i += 1usize
    }
    s = s + comp
    ret f64(c.xc.len) * math.log[f64](1.0f64 - stat_pval(c.stat, c.x0, sd)) - s
}

// iqr.fit for the normal: the interquartile range of the sample over 2 qnorm(.75)
fn iqr_fit_normal(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    ret ((ms.quant7(s, 0.75f64) - ms.quant7(s, 0.25f64)) / (2.0f64 * dist.qnorm(0.75f64, 0.0f64, 1.0f64, true, false)), ok)
}

// iqr.fit: the scale parameter whose null has the observed interquartile range (closed form for the normal, optimize over the support
// otherwise)
type IqrCtx = struct { stat: u8, obs: f64 }

fn iqr_obj(c: *IqrCtx, p: f64) -> f64 {
    let d = stat_iqr(c.stat, p) - c.obs
    ret d * d
}

fn iqr_fit(a: *mem.Arena, stat: u8, x: []const f64) -> (f64, err) {
    if stat == 0u8 {
        let (v0, e0) = iqr_fit_normal(a, x)
        ret (v0, e0)
    }
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    var c = IqrCtx { stat: stat, obs: ms.quant7(s, 0.75f64) - ms.quant7(s, 0.25f64) }
    var slo = 3.0f64
    var shi = 1.0e9f64
    if stat == 2u8 {
        slo = 1.0f64
        shi = 1000.0f64
    }
    let v1 = brent_min[IqrCtx](&c, iqr_obj, slo, shi)
    ret (v1, ok)
}

fn fdrtool_normal(a: *mem.Arena, x: []const f64, qval: []f64, lfdr: []f64) -> (Nf, err) {
    let (r, e) = fdrtool_stat_cut(a, 0u8, x, qval, lfdr, 0u8, 0.75f64)
    ret (r, e)
}

fn fdrtool_normal_cut(a: *mem.Arena, x: []const f64, qval: []f64, lfdr: []f64, method: u8, pct0: f64) -> (Nf, err) {
    let (r, e) = fdrtool_stat_cut(a, 0u8, x, qval, lfdr, method, pct0)
    ret (r, e)
}

// statistic = "correlation" with the fndr cutoff: the scale fields hold kappa
fn fdrtool_corr(a: *mem.Arena, x: []const f64, qval: []f64, lfdr: []f64) -> (Nf, err) {
    let (r, e) = fdrtool_stat_cut(a, 1u8, x, qval, lfdr, 0u8, 0.75f64)
    ret (r, e)
}

// the Student t null (censored.fit's statistic = "studentt" after fndr.cutoff); the scale fields hold the degrees of freedom
fn fdrtool_t(a: *mem.Arena, x: []const f64, qval: []f64, lfdr: []f64) -> (Nf, err) {
    let (r, e) = fdrtool_stat_cut(a, 2u8, x, qval, lfdr, 0u8, 0.75f64)
    ret (r, e)
}

fn fdrtool_corr_cut(a: *mem.Arena, x: []const f64, qval: []f64, lfdr: []f64, method: u8, pct0: f64) -> (Nf, err) {
    let (r, e) = fdrtool_stat_cut(a, 1u8, x, qval, lfdr, method, pct0)
    ret (r, e)
}

// fdrtool(x, statistic = "normal" (stat 0) or "correlation" (stat 1), plot = FALSE). cutoff.method: 0 "fndr", 1 "pct0" (the pct0
// quantile of |x|), 2 "locfdr" (b times the interquartile scale of x, of atanh(x) for the correlation)
fn fdrtool_stat_cut(a: *mem.Arena, stat: u8, x: []const f64, qval: []f64, lfdr: []f64, method: u8, pct0: f64) -> (Nf, err) {
    var res: Nf = zero
    let n = x.len
    let nf = f64(n)
    // step 1: the approximate null (the interquartile scale and eta0 from its p values), then the fndr cutoff
    let (sc0, ie) = iqr_fit(a, stat, x)
    if ie != ok { ret (res, ie) }
    let (pv0, pe) = mem.alloc[f64](a, n)
    let (ax, ae) = mem.alloc[f64](a, n)
    if pe != ok || ae != ok { ret (res, pe) }
    var i = 0usize
    while i < n {
        pv0[i] = stat_pval(stat, x[i], sc0)
        ax[i] = math.abs[f64](x[i])
        i += 1usize
    }
    let (e0, ee) = estimate_eta0(a, pv0)
    if ee != ok { ret (res, ee) }
    let (sx, se) = sorted_copy(a, ax)
    if se != ok { ret (res, se) }
    var pr = 0.99f64
    if e0 < pr { pr = e0 }
    var zeta0 = ms.quant7(sx, pr)
    var f2 = fndr_norm(stat, ax, e0, sc0, zeta0)
    var f1 = fndr_norm(stat, ax, e0, sc0, 0.9f64 * zeta0)
    while f1 < f2 {
        zeta0 = zeta0 * 0.9f64
        f2 = f1
        f1 = fndr_norm(stat, ax, e0, sc0, 0.9f64 * zeta0)
    }
    var x0 = zeta0
    if method == 1u8 { x0 = ms.quant7(sx, pct0) }
    if method == 2u8 {
        var b = 4.3f64 * math.exp[f64](0.0f64 - 0.26f64 * math.log[f64](nf) / math.log[f64](10.0f64))
        if nf > 500000.0f64 { b = 1.0f64 }
        if stat == 0u8 {
            x0 = b * sc0
        } else {
            let (zz, ze) = mem.alloc[f64](a, n)
            if ze != ok { ret (res, ze) }
            var zi = 0usize
            while zi < n {
                zz[zi] = 0.5f64 * math.log[f64]((1.0f64 + x[zi]) / (1.0f64 - x[zi]))
                zi += 1usize
            }
            let (zs, zse) = sorted_copy(a, zz)
            if zse != ok { ret (res, zse) }
            let sdhat = (ms.quant7(zs, 0.75f64) - ms.quant7(zs, 0.25f64)) / (2.0f64 * dist.qnorm(0.75f64, 0.0f64, 1.0f64, true, false))
            let z0 = b * sdhat
            let ez = math.exp[f64](2.0f64 * z0)
            x0 = (ez - 1.0f64) / (ez + 1.0f64)
        }
    }
    if x0 < 0.0f64 { x0 = 0.0f64 - x0 }
    // step 2: the censored fit of the scale
    var nc = 0usize
    i = 0usize
    while i < n {
        if ax[i] <= x0 { nc += 1usize }
        i += 1usize
    }
    let (xc, ce) = mem.alloc[f64](a, nc)
    if ce != ok { ret (res, ce) }
    var j = 0usize
    i = 0usize
    while i < n {
        if ax[i] <= x0 {
            xc[j] = x[i]
            j += 1usize
        }
        i += 1usize
    }
    let (start, st) = iqr_fit(a, stat, xc)
    if st != ok { ret (res, st) }
    var lo = start / 1000.0f64
    var up = start * 1000.0f64
    if stat == 0u8 {
        if lo < 1.0e-9f64 { lo = 1.0e-9f64 }
    } else if stat == 2u8 {
        if lo < 1.0f64 { lo = 1.0f64 }
        if up > 1000.0f64 { up = 1000.0f64 }
    } else {
        if lo < 3.0f64 { lo = 3.0f64 }
        if up > 1.0e9f64 { up = 1.0e9f64 }
    }
    var cs = Cens { xc: xc, x0: x0, stat: stat }
    let sd = brent_min[Cens](&cs, cens_nlogl, lo, up)
    // 1 / num.curv(sd, nlogL)
    var h = 2.220446049250313e-16f64
    h = math.sqrt[f64](math.sqrt[f64](h)) * math.abs[f64](sd)
    if h < 1.0e-4f64 { h = 1.0e-4f64 }
    let w0 = 0.0f64 - 1.0f64 / 12.0f64
    let w1 = 4.0f64 / 3.0f64
    let w2 = 0.0f64 - 5.0f64 / 2.0f64
    let curv = (w0 * cens_nlogl(&cs, sd + h * (0.0f64 - 2.0f64)) + w1 * cens_nlogl(&cs, sd + h * (0.0f64 - 1.0f64)) + w2 * cens_nlogl(&cs, sd) + w1 * cens_nlogl(&cs, sd + h) + w0 * cens_nlogl(&cs, sd + h * 2.0f64)) / (h * h)
    var sc_var = 1.0f64 / curv
    if sc_var != sc_var || sc_var < 0.0f64 { sc_var = 0.0f64 }
    res.sd = sd
    res.sd_se = math.sqrt[f64](sc_var)
    let m = 1.0f64 - stat_pval(stat, x0, sd)
    let th = f64(nc) / nf
    var eta0 = th / m
    if eta0 > 1.0f64 { eta0 = 1.0f64 }
    res.eta0 = eta0
    res.eta0_se = math.sqrt[f64](th * (1.0f64 - th) / (nf * m * m))
    res.cutoff = x0
    res.ncens = nc
    // steps 3 and 4
    let (pv, pe2) = mem.alloc[f64](a, n)
    if pe2 != ok { ret (res, pe2) }
    i = 0usize
    while i < n {
        pv[i] = stat_pval(stat, x[i], sd)
        i += 1usize
    }
    let ce2 = fdrtool_core(a, pv, eta0, qval, lfdr)
    ret (res, ce2)
}

// fndrfunc of fndr.cutoff for the normal: (F(x) - eta0 (2 F0(x) - 1)) / F(x) clipped at zero, F the share of |x| below x
fn fndr_norm(stat: u8, ax: []const f64, e0: f64, sc: f64, x: f64) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < ax.len {
        if ax[i] < x { c += 1.0f64 }
        i += 1usize
    }
    let fx = c / f64(ax.len)
    if fx == 0.0f64 { ret 0.0f64 }
    let v = (fx - e0 * (2.0f64 * stat_cdf(stat, x, sc) - 1.0f64)) / fx
    if v < 0.0f64 { ret 0.0f64 }
    ret v
}

// ---- the exported helpers: monoreg, gcmlcm, grenander ----

type Mono = struct { x: []f64, y: []f64, w: []f64, yf: []f64 }

// monoreg(x, y, w, type): zero weights dropped, equal x merged (weights added, y the weighted mean), sorted by x, then the weighted
// isotonic (or, negated, antitonic) regression of y
fn monoreg(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, antitonic: bool) -> (Mono, err) {
    var res: Mono = zero
    let n = x.len
    let (idx, e1) = mem.alloc[usize](a, n)
    let (fpos, e0) = mem.alloc[usize](a, n)
    if e1 != ok || e0 != ok { ret (res, e1) }
    var m = 0usize
    var i = 0usize
    while i < n {
        if w[i] != 0.0f64 {
            idx[m] = i
            fpos[i] = m
            m += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < m {
        let v = idx[i]
        var j = i
        while j > 0usize && x[idx[j - 1usize]] > x[v] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
    // R merges duplicated x values with y taken by the filtered position from the unfiltered y (a quirk of monoreg when zero weights
    // and duplicates occur together); with no duplicates it uses the filtered y
    var groups = 0usize
    i = 0usize
    while i < m {
        var j = i
        while j < m && x[idx[j]] == x[idx[i]] { j += 1usize }
        groups += 1usize
        i = j
    }
    let has_dup = groups != m
    let (xv, e2) = mem.alloc[f64](a, m)
    let (yv, e3) = mem.alloc[f64](a, m)
    let (wv, e4) = mem.alloc[f64](a, m)
    if e2 != ok || e3 != ok || e4 != ok { ret (res, e2) }
    var lx = 0usize
    i = 0usize
    while i < m {
        var j = i
        var sw = 0.0f64
        var sy = 0.0f64
        while j < m && x[idx[j]] == x[idx[i]] {
            sw += w[idx[j]]
            sy += y[idx[j]] * w[idx[j]]
            j += 1usize
        }
        xv[lx] = x[idx[i]]
        if j - i > 1usize {
            wv[lx] = sw
            yv[lx] = sy / sw
        } else {
            wv[lx] = w[idx[i]]
            if has_dup { yv[lx] = y[fpos[idx[i]]] } else { yv[lx] = y[idx[i]] }
        }
        lx += 1usize
        i = j
    }
    let (yf, e5) = mem.alloc[f64](a, lx)
    let (gew, e6) = mem.alloc[f64](a, lx)
    let (kk, e7) = mem.alloc[usize](a, lx)
    let (yy, e8) = mem.alloc[f64](a, lx)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (res, e5) }
    i = 0usize
    while i < lx {
        yy[i] = yv[i]
        if antitonic { yy[i] = 0.0f64 - yv[i] }
        i += 1usize
    }
    if lx > 0usize { isomean(yy, wv[0usize..lx], yf, gew, kk) }
    if antitonic {
        i = 0usize
        while i < lx {
            yf[i] = 0.0f64 - yf[i]
            i += 1usize
        }
    }
    res.x = xv[0usize..lx]
    res.y = yv[0usize..lx]
    res.w = wv[0usize..lx]
    res.yf = yf
    ret (res, ok)
}

type Gcm = struct { xk: []f64, yk: []f64, sk: []f64 }

// gcmlcm(x, y, type): the greatest convex minorant (lcm false) or the least concave majorant (lcm true) of the points, as knots
fn gcmlcm(a: *mem.Arena, x: []const f64, y: []const f64, lcm: bool) -> (Gcm, err) {
    var res: Gcm = zero
    let n = x.len
    if n < 2usize { ret (res, mem.Invalid) }
    let nm1 = n - 1usize
    let (dx, e1) = mem.alloc[f64](a, nm1)
    let (slope, e3) = mem.alloc[f64](a, nm1)
    let (gew, e4) = mem.alloc[f64](a, nm1)
    let (kk, e5) = mem.alloc[usize](a, nm1)
    let (tmp, e6) = mem.alloc[f64](a, nm1)
    if e1 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (res, e1) }
    var i = 0usize
    while i < nm1 {
        dx[i] = x[i + 1usize] - x[i]
        var r = (y[i + 1usize] - y[i]) / dx[i]
        if r > 1.7976931348623157e308f64 { r = 1.7976931348623157e308f64 }
        if r < 0.0f64 - 1.7976931348623157e308f64 { r = 0.0f64 - 1.7976931348623157e308f64 }
        tmp[i] = r
        if lcm { tmp[i] = 0.0f64 - r }
        i += 1usize
    }
    isomean(tmp, dx, slope, gew, kk)
    if lcm {
        i = 0usize
        while i < nm1 {
            slope[i] = 0.0f64 - slope[i]
            i += 1usize
        }
    }
    let (xk, e7) = mem.alloc[f64](a, n)
    let (sk, e8) = mem.alloc[f64](a, nm1)
    if e7 != ok || e8 != ok { ret (res, e7) }
    var nk = 0usize
    i = 0usize
    while i < nm1 {
        var dup = false
        var j = 0usize
        while j < nk {
            if sk[j] == slope[i] { dup = true }
            j += 1usize
        }
        if !dup {
            xk[nk] = x[i]
            sk[nk] = slope[i]
            nk += 1usize
        }
        i += 1usize
    }
    xk[nk] = x[n - 1usize]
    let (yk, e9) = mem.alloc[f64](a, nk + 1usize)
    if e9 != ok { ret (res, e9) }
    yk[0usize] = y[0usize]
    var cum = 0.0f64
    i = 0usize
    while i < nk {
        cum += (xk[i + 1usize] - xk[i]) * sk[i]
        yk[i + 1usize] = y[0usize] + cum
        i += 1usize
    }
    res.xk = xk[0usize..nk + 1usize]
    res.yk = yk
    res.sk = sk[0usize..nk]
    ret (res, ok)
}

type Gren = struct { xk: []f64, fk_cdf: []f64, fk: []f64 }

// grenander(ecdf(x), type): the knots of the decreasing (least concave majorant) or increasing (greatest convex minorant) density
// estimate of the sample x; fk repeats its last slope, as R's f.knots does
fn grenander(a: *mem.Arena, x: []const f64, decreasing: bool) -> (Gren, err) {
    var res: Gren = zero
    let n = x.len
    let (s, e1) = sorted_copy(a, x)
    if e1 != ok { ret (res, e1) }
    let (ux, e2) = mem.alloc[f64](a, n)
    let (uy, e3) = mem.alloc[f64](a, n)
    let (uy0, e4) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok || e4 != ok { ret (res, e2) }
    var m = 0usize
    var i = 0usize
    while i < n {
        var j = i
        while j < n && s[j] == s[i] { j += 1usize }
        ux[m] = s[i]
        uy[m] = f64(j) / f64(n)
        m += 1usize
        i = j
    }
    var gres: Gcm = zero
    var ge: err = ok
    if decreasing {
        let (g1, ge1) = gcmlcm(a, ux[0usize..m], uy[0usize..m], true)
        gres = g1
        ge = ge1
    } else {
        uy0[0usize] = 0.0f64
        i = 1usize
        while i < m {
            uy0[i] = uy[i - 1usize]
            i += 1usize
        }
        let (g2, ge2) = gcmlcm(a, ux[0usize..m], uy0[0usize..m], false)
        gres = g2
        ge = ge2
    }
    if ge != ok { ret (res, ge) }
    let nk = gres.sk.len
    let (fk, e5) = mem.alloc[f64](a, nk + 1usize)
    if e5 != ok { ret (res, e5) }
    i = 0usize
    while i < nk {
        fk[i] = gres.sk[i]
        i += 1usize
    }
    fk[nk] = gres.sk[nk - 1usize]
    res.xk = gres.xk
    res.fk_cdf = gres.yk
    res.fk = fk
    ret (res, ok)
}
