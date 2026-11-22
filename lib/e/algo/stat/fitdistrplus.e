// R fitdistrplus: fitdist by maximum likelihood (mledist: optim Nelder-Mead, BFGS for one parameter, optimHess standard errors), moment matching (closed formulas),
// quantile matching (qmedist) and maximum goodness of fit (mgedist); gofstat (ks, cvm, ad, their tests, the chi-squared table); quantile of a fit;
// bootdist (parametric and non-parametric) with its quantile intervals.
//
// Families (kind): 0 norm, 1 lnorm, 2 exp, 3 gamma, 4 weibull, 5 logis. Parameters in R's order: norm (mean, sd), lnorm (meanlog, sdlog), exp (rate),
// gamma (shape, rate), weibull (shape, scale), logis (location, scale).
//
// Not here: user-defined distributions, fix.arg and weights, bounds (constrOptim), the discrete families, mme standard errors, summary plots.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.armld as ld
use e.algo.stat.classint as ci
use e.algo.stat.massgap as mm
use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.scale as sc
use e.mem

type Fit = struct { kind: usize, np: usize, est: [2]f64, sd: [2]f64, vc: [4]f64, loglik: f64, n: usize, value: f64, conv: usize }

// the optimisation problem: mode 0 mle, 1 qme, 2 mge, 3 censored mle
type Ctx = struct {
    kind: usize, mode: usize, x: []const f64, n: usize,
    probs: [2]f64, qemp: [2]f64, gof: usize,
    lc: []const f64, rc: []const f64, nc: []const f64, il: []const f64, ir: []const f64, nobs: usize,
    th: []f64, t1: []f64, t2: []f64
}

fn nparams(kind: usize) -> usize {
    if kind == 2usize { ret 1usize }
    ret 2usize
}

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn isinf(v: f64) -> bool { ret v == inf() || v == 0.0f64 - inf() }

fn dlog(kind: usize, x: f64, p: []const f64) -> f64 {
    if kind == 0usize { ret dist.dnorm(x, p[0usize], p[1usize], true) }
    if kind == 1usize { ret dist.dlnorm(x, p[0usize], p[1usize], true) }
    if kind == 2usize { ret dist.dexp(x, 1.0f64 / p[0usize], true) }
    if kind == 3usize { ret nm.dgamma(x, p[0usize], 1.0f64 / p[1usize], true) }
    if kind == 4usize { ret dist.dweibull(x, p[0usize], p[1usize], true) }
    ret dist.dlogis(x, p[0usize], p[1usize], true)
}

fn pf(kind: usize, x: f64, p: []const f64, lower: bool, lg: bool) -> f64 {
    if kind == 0usize { ret dist.pnorm(x, p[0usize], p[1usize], lower, lg) }
    if kind == 1usize { ret dist.plnorm(x, p[0usize], p[1usize], lower, lg) }
    if kind == 2usize { ret dist.pexp(x, 1.0f64 / p[0usize], lower, lg) }
    if kind == 3usize { ret nm.pgamma(x, p[0usize], 1.0f64 / p[1usize], lower, lg) }
    if kind == 4usize { ret dist.pweibull(x, p[0usize], p[1usize], lower, lg) }
    ret dist.plogis(x, p[0usize], p[1usize], lower, lg)
}

fn qf(kind: usize, pr: f64, p: []const f64) -> f64 {
    if kind == 0usize { ret dist.qnorm(pr, p[0usize], p[1usize], true, false) }
    if kind == 1usize { ret dist.qlnorm(pr, p[0usize], p[1usize], true, false) }
    if kind == 2usize { ret dist.qexp(pr, 1.0f64 / p[0usize], true, false) }
    if kind == 3usize { ret nm.qgamma(pr, p[0usize], 1.0f64 / p[1usize], true, false) }
    if kind == 4usize { ret dist.qweibull(pr, p[0usize], p[1usize], true, false) }
    ret dist.qlogis(pr, p[0usize], p[1usize], true, false)
}

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    // insertion sort is quadratic; heap sort keeps the bootstrap loops cheap
    heap_sort(s)
    ret (s, ok)
}

fn sift(s: []f64, start: usize, end: usize) {
    var root = start
    while 2usize * root + 1usize < end {
        var child = 2usize * root + 1usize
        if child + 1usize < end && s[child] < s[child + 1usize] { child += 1usize }
        if s[root] < s[child] {
            let t = s[root]
            s[root] = s[child]
            s[child] = t
            root = child
        } else {
            ret
        }
    }
}

fn heap_sort(s: []f64) {
    let n = s.len
    if n < 2usize { ret }
    var i = n / 2usize
    while i > 0usize {
        i -= 1usize
        sift(s, i, n)
    }
    var e = n
    while e > 1usize {
        e -= 1usize
        let t = s[0usize]
        s[0usize] = s[e]
        s[e] = t
        sift(s, 0usize, e)
    }
}

// R's mean() and var(): long double accumulation (armld)
fn mean_of(x: []const f64) -> f64 { ret ld.mean_ld(x) }

// (n - 1) / n * var(x), the divisor-n variance as the package writes it; sd0 is sqrt((n - 1) / n) * sd(x)
fn var_n(x: []const f64) -> f64 {
    let n = f64(x.len)
    ret (n - 1.0f64) / n * ld.var_ld(x)
}

fn sd0_of(x: []const f64) -> f64 {
    let n = f64(x.len)
    ret math.sqrt[f64]((n - 1.0f64) / n) * math.sqrt[f64](ld.var_ld(x))
}

// pmin(shape, 100), pmax(shape, eps^(1/3)) of cutshapeparam
fn cut_shape(v: f64) -> f64 {
    var s = v
    if s > 100.0f64 { s = 100.0f64 }
    let lo = math.pow[f64](2.220446049250313e-16f64, 1.0f64 / 3.0f64)
    if s < lo { s = lo }
    ret s
}

// start.arg.default
fn start_of(a: *mem.Arena, x: []const f64, kind: usize, st: []f64) -> err {
    let n = x.len
    if kind == 0usize {
        st[0usize] = mean_of(x)
        st[1usize] = sd0_of(x)
        ret ok
    }
    if kind == 1usize {
        let (lx, e) = mem.alloc[f64](a, n)
        if e != ok { ret e }
        var i = 0usize
        while i < n {
            lx[i] = math.log[f64](x[i])
            i += 1usize
        }
        st[0usize] = mean_of(lx)
        st[1usize] = sd0_of(lx)
        ret ok
    }
    if kind == 2usize {
        st[0usize] = 1.0f64 / mean_of(x)
        ret ok
    }
    if kind == 3usize {
        let m = mean_of(x)
        let v = ld.var_ld(x)
        var al = 1.0f64
        var th = m
        if v > 0.0f64 {
            al = m * m / v
            th = v / m
        }
        st[0usize] = cut_shape(al)
        st[1usize] = 1.0f64 / th
        ret ok
    }
    if kind == 4usize {
        let (lx, e) = mem.alloc[f64](a, n)
        if e != ok { ret e }
        var i = 0usize
        while i < n {
            lx[i] = math.log[f64](x[i])
            i += 1usize
        }
        let m = mean_of(lx)
        let v = ld.var_ld(lx)
        let tau = 1.2f64 / math.sqrt[f64](v)
        st[0usize] = cut_shape(tau)
        st[1usize] = math.exp[f64](m + 0.572f64 / tau)
        ret ok
    }
    let m = mean_of(x)
    let v = var_n(x)
    st[0usize] = m
    st[1usize] = math.sqrt[f64](3.0f64 * v) / 3.141592653589793238462643383279f64
    ret ok
}
// the objectives of mledist, qmedist, mgedist and the censored mledist; every mean() and sum() is R's long double one
fn obj(c: *Ctx, p: []const f64) -> f64 {
    if c.mode == 0usize {
        var i = 0usize
        while i < c.x.len {
            let t = dlog(c.kind, c.x[i], p)
            if isinf(t) { ret 2147483647.0f64 }
            c.t1[i] = t
            i += 1usize
        }
        ret 0.0f64 - ld.mean_ld(c.t1[0usize..c.x.len])
    }
    if c.mode == 1usize {
        var d: [2]f64 = zero
        let np = nparams(c.kind)
        var k = 0usize
        while k < np {
            let q = c.qemp[k] - qf(c.kind, c.probs[k], p)
            d[k] = q * q
            k += 1usize
        }
        ret ld.mean_ld(d[0usize..np])
    }
    if c.mode == 3usize { ret obj_cens(c, p) }
    ret obj_gof(c, p)
}

fn obj_cens(c: *Ctx, p: []const f64) -> f64 {
    var i = 0usize
    while i < c.nc.len {
        c.t1[i] = dlog(c.kind, c.nc[i], p)
        i += 1usize
    }
    let t1 = 0.0f64 - ld.sum_ld(c.t1[0usize..c.nc.len])
    i = 0usize
    while i < c.lc.len {
        c.t1[i] = pf(c.kind, c.lc[i], p, true, true)
        i += 1usize
    }
    let t2 = 0.0f64 - ld.sum_ld(c.t1[0usize..c.lc.len])
    i = 0usize
    while i < c.rc.len {
        c.t1[i] = pf(c.kind, c.rc[i], p, false, true)
        i += 1usize
    }
    let t3 = 0.0f64 - ld.sum_ld(c.t1[0usize..c.rc.len])
    i = 0usize
    while i < c.il.len {
        let p4 = pf(c.kind, c.ir[i], p, true, false)
        let p5 = pf(c.kind, c.il[i], p, true, false)
        c.t1[i] = math.log[f64](p4 - p5)
        i += 1usize
    }
    let t4 = 0.0f64 - ld.sum_ld(c.t1[0usize..c.il.len])
    if isinf(t1) || isinf(t2) || isinf(t3) || isinf(t4) { ret 2147483647.0f64 }
    ret (t1 + t2 + t3 + t4) / f64(c.nobs)
}

// mgedist distances; gof 0 CvM 1 KS 2 AD 3 ADR 4 ADL 5 AD2R 6 AD2L 7 AD2; c.x is sorted
fn obj_gof(c: *Ctx, p: []const f64) -> f64 {
    let n = c.x.len
    let nf = f64(n)
    let big = 2147483647.0f64
    var i = 0usize
    while i < n {
        c.th[i] = pf(c.kind, c.x[i], p, true, false)
        i += 1usize
    }
    if c.gof == 0usize {
        i = 0usize
        while i < n {
            let d = c.th[i] - (2.0f64 * f64(i + 1usize) - 1.0f64) / (2.0f64 * nf)
            c.t1[i] = d * d
            i += 1usize
        }
        ret 1.0f64 / (12.0f64 * (nf * nf)) + ld.mean_ld(c.t1[0usize..n])
    }
    if c.gof == 1usize {
        var m = 0.0f64
        i = 0usize
        while i < n {
            let d1 = math.abs[f64](c.th[i] - f64(i + 1usize) / nf)
            let d2 = math.abs[f64](c.th[i] - f64(i) / nf)
            if d1 > m { m = d1 }
            if d2 > m { m = d2 }
            i += 1usize
        }
        ret m
    }
    // the kept terms of the two vectors the Anderson-Darling variants average or sum
    var cnt = 0usize
    i = 0usize
    while i < n {
        let w = 2.0f64 * f64(i + 1usize) - 1.0f64
        let th = c.th[i]
        let rv = c.th[n - 1usize - i]
        var a1 = 0.0f64
        var a2 = 0.0f64
        var keep = false
        if c.gof == 2usize {
            a1 = w * math.log[f64](th * (1.0f64 - rv))
            keep = !isinf(a1) && a1 == a1
        }
        if c.gof == 3usize {
            a1 = w * math.log[f64](1.0f64 - rv)
            a2 = th
            keep = !isinf(a1) && a1 == a1
        }
        if c.gof == 4usize {
            a1 = w * math.log[f64](th)
            a2 = th
            keep = !isinf(a1) && a1 == a1
        }
        if c.gof == 5usize {
            a1 = math.log[f64](1.0f64 - th)
            a2 = w / (1.0f64 - rv)
            keep = !isinf(a1) && a1 == a1 && !isinf(a2) && a2 == a2
        }
        if c.gof == 6usize {
            a1 = math.log[f64](th)
            a2 = w / th
            keep = !isinf(a1) && a1 == a1 && !isinf(a2) && a2 == a2
        }
        if c.gof == 7usize {
            a1 = math.log[f64](th * (1.0f64 - th))
            let q1 = w / th
            let q2 = w / (1.0f64 - rv)
            a2 = q1 + q2
            keep = !isinf(a1) && a1 == a1 && !isinf(q1) && q1 == q1 && !isinf(q2) && q2 == q2
        }
        if keep {
            c.t1[cnt] = a1
            c.t2[cnt] = a2
            cnt += 1usize
        }
        i += 1usize
    }
    if cnt == 0usize { ret big }
    let cf = f64(cnt)
    let v1 = c.t1[0usize..cnt]
    let v2 = c.t2[0usize..cnt]
    if c.gof == 2usize { ret 0.0f64 - cf / nf - ld.mean_ld(v1) / nf }
    if c.gof == 3usize { ret cf / 2.0f64 / nf - 2.0f64 * ld.sum_ld(v2) / nf - ld.mean_ld(v1) / nf }
    if c.gof == 4usize { ret 0.0f64 - 3.0f64 * cf / 2.0f64 / nf + 2.0f64 * ld.sum_ld(v2) / nf - ld.mean_ld(v1) / nf }
    ret 2.0f64 * ld.sum_ld(v1) / nf + ld.mean_ld(v2) / nf
}

// optim's numerical gradient: central differences with step 1e-3
fn ngrad(c: *Ctx, p: []const f64, g: []f64) {
    var w: [2]f64 = zero
    let np = p.len
    var k = 0usize
    while k < np {
        w[0usize] = p[0usize]
        if np > 1usize { w[1usize] = p[1usize] }
        w[k] = p[k] + 0.001f64
        let v1 = obj(c, w[0usize..np])
        w[k] = p[k] - 0.001f64
        let v2 = obj(c, w[0usize..np])
        g[k] = (v1 - v2) / 0.002f64
        k += 1usize
    }
}

// optimHess: central differences of the numerical gradient, symmetrised; h is np by np
fn ohess(c: *Ctx, p: []const f64, h: []f64) {
    var w: [2]f64 = zero
    var g1: [2]f64 = zero
    var g2: [2]f64 = zero
    let np = p.len
    var i = 0usize
    while i < np {
        w[0usize] = p[0usize]
        if np > 1usize { w[1usize] = p[1usize] }
        w[i] = p[i] + 0.001f64
        ngrad(c, w[0usize..np], g1[0usize..np])
        w[i] = p[i] - 0.001f64
        ngrad(c, w[0usize..np], g2[0usize..np])
        var k = 0usize
        while k < np {
            h[i * np + k] = (g1[k] - g2[k]) / 0.002f64
            k += 1usize
        }
        i += 1usize
    }
    if np == 2usize {
        let m = 0.5f64 * (h[1usize] + h[2usize])
        h[1usize] = m
        h[2usize] = m
    }
}

// optim from start: Nelder-Mead for two parameters, BFGS for one; returns (value, convergence code), the estimate in b
fn optim_run(a: *mem.Arena, c: *Ctx, st: []const f64, b: []f64) -> (f64, usize) {
    let np = st.len
    if np > 1usize {
        let (fmin, cnt, fail) = rnm.nmmin[Ctx](a, c, obj, st, 0.0f64 - inf(), 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, b)
        ret (fmin, fail)
    }
    b[0usize] = st[0usize]
    let fmin = bf.vmmin[Ctx](a, c, obj, ngrad, b, 1.4901161193847656e-08f64, 100usize)
    ret (fmin, 0usize)
}

fn finish_fit(a: *mem.Arena, c: *Ctx, kind: usize, b: []const f64, value: f64, conv: usize, n: usize, want_vcov: bool) -> Fit {
    var f: Fit = zero
    f.kind = kind
    f.np = nparams(kind)
    f.n = n
    f.value = value
    f.conv = conv
    var k = 0usize
    while k < f.np {
        f.est[k] = b[k]
        f.sd[k] = 0.0f64 / 0.0f64
        k += 1usize
    }
    f.loglik = 0.0f64 - value * f64(n)
    if want_vcov {
        var h: [4]f64 = zero
        ohess(c, b[0usize..f.np], h[0usize..f.np * f.np])
        if f.np == 1usize {
            f.vc[0usize] = 1.0f64 / h[0usize] / f64(n)
        } else {
            let det = h[0usize] * h[3usize] - h[1usize] * h[2usize]
            f.vc[0usize] = h[3usize] / det / f64(n)
            f.vc[1usize] = 0.0f64 - h[1usize] / det / f64(n)
            f.vc[2usize] = 0.0f64 - h[2usize] / det / f64(n)
            f.vc[3usize] = h[0usize] / det / f64(n)
        }
        f.sd[0usize] = math.sqrt[f64](f.vc[0usize])
        if f.np == 2usize { f.sd[1usize] = math.sqrt[f64](f.vc[3usize]) }
    }
    ret f
}

// sum(log(d(x))) in long double; the scratch is released again
fn loglik_at(a: *mem.Arena, kind: usize, x: []const f64, p: []const f64) -> f64 {
    let mark = mem.mark(a)
    let (t, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        t[i] = dlog(kind, x[i], p)
        i += 1usize
    }
    let s = ld.sum_ld(t)
    mem.reset(a, mark)
    ret s
}

// the scratch vectors of the objectives, n long
fn scratch(a: *mem.Arena, c: *Ctx, n: usize) -> err {
    let (t0, e0) = mem.alloc[f64](a, n)
    let (t1, e1) = mem.alloc[f64](a, n)
    let (t2, e2) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    c.th = t0
    c.t1 = t1
    c.t2 = t2
    ret ok
}

// fitdist(x, dist, method = "mle"); st is the start (the default when none is given)
fn fit_mle_from(a: *mem.Arena, x: []const f64, kind: usize, st: []const f64) -> (Fit, err) {
    var c: Ctx = zero
    let es = scratch(a, &c, x.len)
    if es != ok { ret (zero, es) }
    c.kind = kind
    c.mode = 0usize
    c.x = x
    let np = nparams(kind)
    let (b, e) = mem.alloc[f64](a, np)
    if e != ok { ret (zero, e) }
    let (value, conv) = optim_run(a, &c, st[0usize..np], b)
    let f = finish_fit(a, &c, kind, b, value, conv, x.len, true)
    ret (f, ok)
}

fn fit_mle(a: *mem.Arena, x: []const f64, kind: usize) -> (Fit, err) {
    let (st, e) = mem.alloc[f64](a, 2usize)
    if e != ok { ret (zero, e) }
    let e2 = start_of(a, x, kind, st)
    if e2 != ok { ret (zero, e2) }
    let (f, e3) = fit_mle_from(a, x, kind, st)
    ret (f, e3)
}

// fitdist(x, dist, method = "mme"): the closed formulas (norm, lnorm, exp, gamma, logis)
fn fit_mme(a: *mem.Arena, x: []const f64, kind: usize) -> Fit {
    var f: Fit = zero
    f.kind = kind
    f.np = nparams(kind)
    f.n = x.len
    let m = mean_of(x)
    let v = var_n(x)
    if kind == 0usize {
        f.est[0usize] = m
        f.est[1usize] = math.sqrt[f64](v)
    }
    if kind == 1usize {
        let sd2 = math.log[f64](1.0f64 + v / (m * m))
        f.est[0usize] = math.log[f64](m) - sd2 / 2.0f64
        f.est[1usize] = math.sqrt[f64](sd2)
    }
    if kind == 2usize { f.est[0usize] = 1.0f64 / m }
    if kind == 3usize {
        f.est[0usize] = m * m / v
        f.est[1usize] = m / v
    }
    if kind == 5usize {
        f.est[0usize] = m
        f.est[1usize] = math.sqrt[f64](3.0f64 * v) / 3.141592653589793238462643383279f64
    }
    f.sd[0usize] = 0.0f64 / 0.0f64
    f.sd[1usize] = 0.0f64 / 0.0f64
    f.loglik = loglik_at(a, kind, x, f.est[0usize..f.np])
    ret f
}

// fitdist(x, dist, method = "qme", probs, qtype = 7)
fn fit_qme(a: *mem.Arena, x: []const f64, kind: usize, probs: []const f64, qtype: u8, start: []const f64) -> (Fit, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (zero, e) }
    var c: Ctx = zero
    let es = scratch(a, &c, x.len)
    if es != ok { ret (zero, es) }
    c.kind = kind
    c.mode = 1usize
    c.x = x
    let np = nparams(kind)
    var k = 0usize
    while k < np {
        c.probs[k] = probs[k]
        c.qemp[k] = ci.quantile_r(s, probs[k], qtype)
        k += 1usize
    }
    let (st, e1) = mem.alloc[f64](a, 2usize)
    let (b, e2) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let e3 = start_or_default(a, x, kind, start, st)
    if e3 != ok { ret (zero, e3) }
    let (value, conv) = optim_run(a, &c, st[0usize..np], b)
    var f = finish_fit(a, &c, kind, b, value, conv, x.len, false)
    f.loglik = loglik_at(a, kind, x, b)
    ret (f, ok)
}

// the given start, or start.arg.default when none is given (a zero-length slice)
fn start_or_default(a: *mem.Arena, x: []const f64, kind: usize, start: []const f64, st: []f64) -> err {
    if start.len == 0usize { ret start_of(a, x, kind, st) }
    st[0usize] = start[0usize]
    if start.len > 1usize { st[1usize] = start[1usize] }
    ret ok
}

// fitdist(x, dist, method = "mge", gof): gof 0 CvM 1 KS 2 AD 3 ADR 4 ADL 5 AD2R 6 AD2L 7 AD2
fn fit_mge(a: *mem.Arena, x: []const f64, kind: usize, gof: usize, start: []const f64) -> (Fit, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (zero, e) }
    var c: Ctx = zero
    let es = scratch(a, &c, x.len)
    if es != ok { ret (zero, es) }
    c.kind = kind
    c.mode = 2usize
    c.x = s
    c.gof = gof
    let np = nparams(kind)
    let (st, e1) = mem.alloc[f64](a, 2usize)
    let (b, e2) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let e3 = start_or_default(a, x, kind, start, st)
    if e3 != ok { ret (zero, e3) }
    let (value, conv) = optim_run(a, &c, st[0usize..np], b)
    var f = finish_fit(a, &c, kind, b, value, conv, x.len, false)
    f.loglik = loglik_at(a, kind, x, b)
    ret (f, ok)
}

fn aic(f: *const Fit) -> f64 { ret 2.0f64 * f64(f.np) - 2.0f64 * f.loglik }

fn bic(f: *const Fit) -> f64 { ret math.log[f64](f64(f.n)) * f64(f.np) - 2.0f64 * f.loglik }

// gofstat: out = (ks, cvm, ad); tests 0 not computed, 1 rejected, 2 not rejected in tests = (ks, ad, cvm); the AD and CvM tests only for an mle fit
fn gofstat(a: *mem.Arena, x: []const f64, f: *const Fit, is_mle: bool, out: []f64, tests: []usize) -> err {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret e }
    let n = f64(s.len)
    let (th, e1) = mem.alloc[f64](a, s.len)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < s.len {
        th[i] = pf(f.kind, s[i], f.est[0usize..f.np], true, false)
        i += 1usize
    }
    let (adv, e2) = mem.alloc[f64](a, s.len)
    let (cvv, e3) = mem.alloc[f64](a, s.len)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var ks = 0.0f64
    i = 0usize
    while i < s.len {
        let d1 = math.abs[f64](th[i] - f64(i + 1usize) / n)
        let d2 = math.abs[f64](th[i] - f64(i) / n)
        if d1 > ks { ks = d1 }
        if d2 > ks { ks = d2 }
        let w = 2.0f64 * f64(i + 1usize) - 1.0f64
        adv[i] = w * (math.log[f64](th[i]) + math.log[f64](1.0f64 - th[s.len - 1usize - i]))
        cvv[i] = (th[i] - w / (2.0f64 * n)) * (th[i] - w / (2.0f64 * n))
        i += 1usize
    }
    let ad = 0.0f64 - n - ld.mean_ld(adv)
    let cvm = 1.0f64 / (12.0f64 * n) + ld.sum_ld(cvv)
    out[0usize] = ks
    out[1usize] = cvm
    out[2usize] = ad
    tests[0usize] = 0usize
    tests[1usize] = 0usize
    tests[2usize] = 0usize
    let dmod = ks * (math.sqrt[f64](n) + 0.12f64 + 0.11f64 / math.sqrt[f64](n))
    if s.len >= 30usize {
        tests[0usize] = 2usize
        if dmod > 1.358f64 { tests[0usize] = 1usize }
    }
    if is_mle && s.len >= 5usize {
        if f.kind == 2usize {
            tests[1usize] = verdict(ad * (1.0f64 + 0.6f64 / n) > 1.321f64)
            tests[2usize] = verdict(cvm * (1.0f64 + 0.16f64 / n) > 0.222f64)
        }
        if f.kind == 3usize {
            let m = f.est[0usize]
            tests[1usize] = verdict(ad > interp_gamma(m, 0usize))
            tests[2usize] = verdict(cvm > interp_gamma(m, 1usize))
        }
        if f.kind == 4usize {
            tests[1usize] = verdict(ad * (1.0f64 + 0.2f64 / math.sqrt[f64](n)) > 0.757f64)
            tests[2usize] = verdict(cvm * (1.0f64 + 0.2f64 / math.sqrt[f64](n)) > 0.124f64)
        }
        if f.kind == 5usize {
            tests[1usize] = verdict(ad * (1.0f64 + 0.25f64 / n) > 0.66f64)
            tests[2usize] = verdict((n * cvm - 0.08f64) / (n - 1.0f64) > 0.098f64)
        }
    }
    ret ok
}

fn verdict(rejected: bool) -> usize {
    if rejected { ret 1usize }
    ret 2usize
}

// approxfun over the shape grid of the Stephens tables, constant beyond the ends (yright is the last value less one in the table); which 0 AD, 1 CvM
fn interp_gamma(m: f64, which: usize) -> f64 {
    var right = 0.752f64
    if which == 1usize { right = 0.126f64 }
    if m < 1.0f64 { ret 0.0f64 / 0.0f64 }
    if m > 20.0f64 { ret right }
    var i = 0usize
    while i < 10usize {
        let x1 = tab(2usize, i + 1usize)
        if m == x1 { ret tab(which, i + 1usize) }
        if m < x1 {
            let x0 = tab(2usize, i)
            if m == x0 { ret tab(which, i) }
            ret tab(which, i) + (tab(which, i + 1usize) - tab(which, i)) * ((m - x0) / (x1 - x0))
        }
        i += 1usize
    }
    ret tab(which, 10usize)
}

// the Stephens table: which 2 the shape grid, 0 the AD critical values, 1 the CvM ones
fn tab(which: usize, i: usize) -> f64 {
    if which == 2usize {
        if i < 6usize { ret f64(i + 1usize) }
        if i == 6usize { ret 8.0f64 }
        if i == 7usize { ret 10.0f64 }
        if i == 8usize { ret 12.0f64 }
        if i == 9usize { ret 15.0f64 }
        ret 20.0f64
    }
    if which == 0usize {
        if i == 0usize { ret 0.786f64 }
        if i == 1usize { ret 0.768f64 }
        if i == 2usize { ret 0.762f64 }
        if i == 3usize { ret 0.759f64 }
        if i == 4usize { ret 0.758f64 }
        if i == 5usize { ret 0.757f64 }
        if i == 6usize { ret 0.755f64 }
        if i < 10usize { ret 0.754f64 }
        ret 0.753f64
    }
    if i == 0usize { ret 0.136f64 }
    if i == 1usize { ret 0.131f64 }
    if i == 2usize { ret 0.129f64 }
    if i < 6usize { ret 0.128f64 }
    if i < 10usize { ret 0.127f64 }
    ret 0.126f64
}

// the chi-squared of gofstat with the default cells (meancount = round(n / (4n)^(2/5))): out = (chisq, df, p-value, ncells); obs and theo get the cell counts
fn chisq_default(a: *mem.Arena, x: []const f64, f: *const Fit, out: []f64, obs: []f64, theo: []f64) -> err {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret e }
    let n = s.len
    let nf = f64(n)
    let mc = usize(math.round[f64](nf / math.pow[f64](4.0f64 * nf, 0.4f64)))
    let (br, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var nb = 0usize
    var from = 0usize
    let lim = (3usize * mc + 1usize) / 2usize
    var rem = n
    while rem > lim {
        let limit = s[from + mc - 1usize]
        br[nb] = limit
        nb += 1usize
        var j = from
        while j < n && s[j] <= limit { j += 1usize }
        rem = n - j
        from = j
    }
    if nb == 0usize {
        out[3usize] = 0.0f64
        ret ok
    }
    ret chisq_breaks(x, f, br[0usize..nb], out, obs, theo)
}

fn chisq_breaks(x: []const f64, f: *const Fit, br: []const f64, out: []f64, obs: []f64, theo: []f64) -> err {
    let n = x.len
    let nf = f64(n)
    let nb = br.len
    var prev_p = 0.0f64
    var prev_f = 0.0f64
    var k = 0usize
    var last_p = 0.0f64
    var last_f = 0.0f64
    while k < nb {
        let pb = pf(f.kind, br[k], f.est[0usize..f.np], true, false)
        var cnt = 0usize
        var j = 0usize
        while j < n {
            if x[j] <= br[k] { cnt += 1usize }
            j += 1usize
        }
        let fb = f64(cnt) / nf
        obs[k] = math.round[f64]((fb - prev_f) * nf)
        theo[k] = (pb - prev_p) * nf
        prev_p = pb
        prev_f = fb
        last_p = pb
        last_f = fb
        k += 1usize
    }
    var cells = nb
    if !(last_p == 1.0f64 && last_f == 1.0f64) {
        obs[nb] = math.round[f64]((1.0f64 - last_f) * nf)
        theo[nb] = (1.0f64 - last_p) * nf
        cells = nb + 1usize
    }
    var chisq = 0.0f64
    k = 0usize
    while k < cells {
        chisq += (obs[k] - theo[k]) * (obs[k] - theo[k]) / theo[k]
        k += 1usize
    }
    let df = f64(cells) - 1.0f64 - f64(f.np)
    out[0usize] = chisq
    out[1usize] = df
    out[2usize] = 0.0f64 / 0.0f64
    if df > 0.0f64 { out[2usize] = nm.pchisq(chisq, df, false, false) }
    out[3usize] = f64(cells)
    ret ok
}

// quantile of the fit at the probabilities
fn quantiles(f: *const Fit, probs: []const f64, out: []f64) {
    var i = 0usize
    while i < probs.len {
        out[i] = qf(f.kind, probs[i], f.est[0usize..f.np])
        i += 1usize
    }
}

// bootdist: niter refits from the fit's estimate; the data are drawn from the fitted distribution (param) or by sampling the data (nonparam).
// est is niter by np (row per iteration), conv the convergence codes. The caller seeds r (set.seed) first.
fn boot_sample(a: *mem.Arena, r: *rng.Rng, x: []const f64, f: *const Fit, param: bool, total: usize) -> ([]f64, err) {
    let (rdata, e) = mem.alloc[f64](a, total)
    if e != ok { ret (rdata, e) }
    if param {
        var i = 0usize
        while i < total {
            rdata[i] = rdraw(r, f)
            i += 1usize
        }
    } else {
        let (ix, e1) = rng.sample_int(a, r, i64(x.len), i64(total), true)
        if e1 != ok { ret (rdata, e1) }
        var i = 0usize
        while i < total {
            rdata[i] = x[usize(ix[i] - 1i64)]
            i += 1usize
        }
    }
    ret (rdata, ok)
}

fn bootdist(a: *mem.Arena, r: *rng.Rng, x: []const f64, f: *const Fit, method: usize, param: bool, niter: usize, qtype: u8, probs: []const f64, est: []f64, conv: []usize) -> err {
    let n = x.len
    let (rdata, e) = boot_sample(a, r, x, f, param, niter * n)
    if e != ok { ret e }
    var it = 0usize
    while it < niter {
        let mark = mem.mark(a)
        let d = rdata[it * n..(it + 1usize) * n]
        var g: Fit = zero
        var e2 = ok
        var st: [2]f64 = zero
        st[0usize] = f.est[0usize]
        st[1usize] = f.est[1usize]
        if method == 0usize {
            let (g1, e3) = fit_mle_from(a, d, f.kind, st[0usize..f.np])
            g = g1
            e2 = e3
        }
        if method == 1usize {
            let (g1, e3) = fit_qme(a, d, f.kind, probs, qtype, st[0usize..f.np])
            g = g1
            e2 = e3
        }
        if method == 2usize { g = fit_mme(a, d, f.kind) }
        if e2 != ok { ret e2 }
        var k = 0usize
        while k < f.np {
            est[it * f.np + k] = g.est[k]
            k += 1usize
        }
        conv[it] = g.conv
        mem.reset(a, mark)
        it += 1usize
    }
    ret ok
}

fn rdraw(r: *rng.Rng, f: *const Fit) -> f64 {
    if f.kind == 0usize { ret rng.rnorm(r, f.est[0usize], f.est[1usize]) }
    if f.kind == 1usize { ret rd.rlnorm(r, f.est[0usize], f.est[1usize]) }
    if f.kind == 2usize { ret rng.rexp(r, 1.0f64 / f.est[0usize]) }
    if f.kind == 3usize { ret rd.rgamma(r, f.est[0usize], 1.0f64 / f.est[1usize]) }
    if f.kind == 4usize { ret rd.rweibull(r, f.est[0usize], f.est[1usize]) }
    ret rd.rlogis(r, f.est[0usize], f.est[1usize])
}

// median, 2.5% and 97.5% (type 7) of a column of the bootstrap estimates
fn column_ci(a: *mem.Arena, est: []const f64, np: usize, col: usize, out: []f64) -> err {
    let niter = est.len / np
    let (v, e) = mem.alloc[f64](a, niter)
    if e != ok { ret e }
    var i = 0usize
    while i < niter {
        v[i] = est[i * np + col]
        i += 1usize
    }
    heap_sort(v)
    out[0usize] = ci.quantile_r(v, 0.5f64, 7u8)
    out[1usize] = ci.quantile_r(v, 0.025f64, 7u8)
    out[2usize] = ci.quantile_r(v, 0.975f64, 7u8)
    ret ok
}

// --- censored data: fitdistcens, bootdistcens. left or right NaN is R's NA (left censored when left is NA, right censored when right is NA).

fn is_na(v: f64) -> bool { ret v != v }

// cens2pseudo: split the rows into right censored (left values), left censored (right values), exact (left == right) and interval ones, each in row order
fn cens_prepare(a: *mem.Arena, c: *Ctx, left: []const f64, right: []const f64) -> err {
    let n = left.len
    let (rc, e1) = mem.alloc[f64](a, n)
    let (lc, e2) = mem.alloc[f64](a, n)
    let (nc, e3) = mem.alloc[f64](a, n)
    let (il, e4) = mem.alloc[f64](a, n)
    let (ir, e5) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var nr = 0usize
    var nl = 0usize
    var nn = 0usize
    var ni = 0usize
    var i = 0usize
    while i < n {
        if is_na(left[i]) {
            lc[nl] = right[i]
            nl += 1usize
        } else {
            if is_na(right[i]) {
                rc[nr] = left[i]
                nr += 1usize
            } else {
                if left[i] == right[i] {
                    nc[nn] = left[i]
                    nn += 1usize
                } else {
                    il[ni] = left[i]
                    ir[ni] = right[i]
                    ni += 1usize
                }
            }
        }
        i += 1usize
    }
    c.rc = rc[0usize..nr]
    c.lc = lc[0usize..nl]
    c.nc = nc[0usize..nn]
    c.il = il[0usize..ni]
    c.ir = ir[0usize..ni]
    c.nobs = n
    ret ok
}

// the start of fitdistcens: start.arg.default of the pseudo data c(rcens, lcens, ncens, (left + right) / 2)
fn cens_start(a: *mem.Arena, c: *const Ctx, kind: usize, st: []f64) -> err {
    let total = c.rc.len + c.lc.len + c.nc.len + c.il.len
    let (ps, e) = mem.alloc[f64](a, total)
    if e != ok { ret e }
    var at = 0usize
    var i = 0usize
    while i < c.rc.len {
        ps[at] = c.rc[i]
        at += 1usize
        i += 1usize
    }
    i = 0usize
    while i < c.lc.len {
        ps[at] = c.lc[i]
        at += 1usize
        i += 1usize
    }
    i = 0usize
    while i < c.nc.len {
        ps[at] = c.nc[i]
        at += 1usize
        i += 1usize
    }
    i = 0usize
    while i < c.il.len {
        ps[at] = (c.il[i] + c.ir[i]) / 2.0f64
        at += 1usize
        i += 1usize
    }
    ret start_of(a, ps, kind, st)
}

// fitdistcens(data, dist): start empty means the default
fn fit_cens(a: *mem.Arena, left: []const f64, right: []const f64, kind: usize, start: []const f64) -> (Fit, err) {
    var c: Ctx = zero
    let es = scratch(a, &c, left.len)
    if es != ok { ret (zero, es) }
    let ec = cens_prepare(a, &c, left, right)
    if ec != ok { ret (zero, ec) }
    c.kind = kind
    c.mode = 3usize
    let np = nparams(kind)
    let (st, e1) = mem.alloc[f64](a, 2usize)
    let (b, e2) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    var e3 = ok
    if start.len == 0usize { e3 = cens_start(a, &c, kind, st) } else { e3 = start_or_default(a, left, kind, start, st) }
    if e3 != ok { ret (zero, e3) }
    let (value, conv) = optim_run(a, &c, st[0usize..np], b)
    let f = finish_fit(a, &c, kind, b, value, conv, left.len, true)
    ret (f, ok)
}

// bootdistcens: niter refits from the estimate on rows sampled with replacement
fn bootdist_cens(a: *mem.Arena, r: *rng.Rng, left: []const f64, right: []const f64, f: *const Fit, niter: usize, est: []f64, conv: []usize) -> err {
    let n = left.len
    let (ix, e) = rng.sample_int(a, r, i64(n), i64(niter * n), true)
    if e != ok { ret e }
    var it = 0usize
    while it < niter {
        let mark = mem.mark(a)
        let (bl, e1) = mem.alloc[f64](a, n)
        let (br, e2) = mem.alloc[f64](a, n)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        var i = 0usize
        while i < n {
            let row = usize(ix[it * n + i] - 1i64)
            bl[i] = left[row]
            br[i] = right[row]
            i += 1usize
        }
        let (g, e3) = fit_cens(a, bl, br, f.kind, f.est[0usize..f.np])
        if e3 != ok { ret e3 }
        var k = 0usize
        while k < f.np {
            est[it * f.np + k] = g.est[k]
            k += 1usize
        }
        conv[it] = g.conv
        mem.reset(a, mark)
        it += 1usize
    }
    ret ok
}

// --- descdist: out = (min, max, median, mean, sd, skewness, kurtosis)

fn moment_k(x: []const f64, k: usize, t: []f64) -> f64 {
    let m1 = mean_of(x)
    var i = 0usize
    while i < x.len {
        let d = x[i] - m1
        if k == 2usize { t[i] = d * d } else { t[i] = math.pow[f64](d, f64(k)) }
        i += 1usize
    }
    ret ld.sum_ld(t[0usize..x.len]) / f64(x.len)
}

fn skew_kurt(x: []const f64, unbiased: bool, t: []f64, out: []f64) {
    let n = f64(x.len)
    let m2 = moment_k(x, 2usize, t)
    let m3 = moment_k(x, 3usize, t)
    let m4 = moment_k(x, 4usize, t)
    let sd = math.sqrt[f64](m2)
    let g1 = m3 / math.pow[f64](sd, 3.0f64)
    let g2 = m4 / (m2 * m2)
    if unbiased {
        out[0usize] = math.sqrt[f64](n * (n - 1.0f64)) * g1 / (n - 2.0f64)
        out[1usize] = (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64)) * ((n + 1.0f64) * g2 - 3.0f64 * (n - 1.0f64)) + 3.0f64
    } else {
        out[0usize] = g1
        out[1usize] = g2
    }
}

fn descdist(a: *mem.Arena, x: []const f64, unbiased: bool, out: []f64) -> err {
    let (s, e) = sorted_copy(a, x)
    let (t, e1) = mem.alloc[f64](a, x.len)
    if e != ok { ret e }
    if e1 != ok { ret e1 }
    let n = s.len
    out[0usize] = s[0usize]
    out[1usize] = s[n - 1usize]
    if n % 2usize == 1usize { out[2usize] = s[n / 2usize] } else { out[2usize] = (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64 }
    out[3usize] = mean_of(x)
    if unbiased { out[4usize] = math.sqrt[f64](ld.var_ld(x)) } else { out[4usize] = math.sqrt[f64](moment_k(x, 2usize, t)) }
    var sk: [2]f64 = zero
    skew_kurt(x, unbiased, t, sk[0usize..2usize])
    out[5usize] = sk[0usize]
    out[6usize] = sk[1usize]
    ret ok
}

// the bootstrap of descdist: squared skewness and kurtosis of each of boot samples of the data (the points the Cullen and Frey graph draws)
fn descdist_boot(a: *mem.Arena, r: *rng.Rng, x: []const f64, unbiased: bool, boot: usize, s2: []f64, kurt: []f64) -> err {
    let n = x.len
    let (ix, e) = rng.sample_int(a, r, i64(n), i64(n * boot), true)
    let (d, e1) = mem.alloc[f64](a, n)
    let (t, e2) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var it = 0usize
    while it < boot {
        var i = 0usize
        while i < n {
            d[i] = x[usize(ix[it * n + i] - 1i64)]
            i += 1usize
        }
        var sk: [2]f64 = zero
        skew_kurt(d, unbiased, t, sk[0usize..2usize])
        s2[it] = sk[0usize] * sk[0usize]
        kurt[it] = sk[1usize]
        it += 1usize
    }
    ret ok
}

// --- denscomp data: the default histogram (Sturges breaks) and the fitted densities on 101 points over the range of the data

// breaks and counts of hist(x, plot = FALSE)
fn hist_default(a: *mem.Arena, x: []const f64) -> ([]f64, []f64, err) {
    let nclass = math.ceil[f64](math.log2[f64](f64(x.len)) + 1.0f64)
    let (b, c, e) = mm.hist_counts(a, x, nclass)
    ret (b, c, e)
}

// seq(lo, hi, length.out = m)[i] (zero based)
fn seq_at(lo: f64, hi: f64, m: usize, i: usize) -> f64 {
    if i == 0usize { ret lo }
    if i + 1usize == m { ret hi }
    ret lo + f64(i) * ((hi - lo) / f64(m - 1usize))
}

// d<dist>(x), not the log density
fn dens(kind: usize, x: f64, p: []const f64) -> f64 {
    if kind == 0usize { ret dist.dnorm(x, p[0usize], p[1usize], false) }
    if kind == 1usize { ret dist.dlnorm(x, p[0usize], p[1usize], false) }
    if kind == 2usize { ret dist.dexp(x, 1.0f64 / p[0usize], false) }
    if kind == 3usize { ret nm.dgamma(x, p[0usize], 1.0f64 / p[1usize], false) }
    if kind == 4usize { ret dist.dweibull(x, p[0usize], p[1usize], false) }
    ret dist.dlogis(x, p[0usize], p[1usize], false)
}

// vcov correlation and the Wald interval of confint.default: est + sd * qnorm(prob)
fn wald(f: *const Fit, k: usize, prob: f64) -> f64 { ret f.est[k] + f.sd[k] * dist.qnorm(prob, 0.0f64, 1.0f64, true, false) }

fn cor_of(f: *const Fit) -> f64 { ret f.vc[1usize] / math.sqrt[f64](f.vc[0usize] * f.vc[3usize]) }

// --- mme standard errors: the delta method of mme.vcov, vcov = J^-1 A J^-T / n with the numerical Jacobian of the theoretical moments (step sqrt(eps))

fn sq(v: f64) -> f64 { ret v * v }

// the theoretical moment of the given order as the package defines it (mnorm, mlnorm, mexp, mgamma, mlogis)
fn mth(kind: usize, ord: f64, p: []const f64) -> f64 {
    let pi = 3.141592653589793238462643383279f64
    if kind == 0usize {
        if ord == 1.0f64 { ret p[0usize] }
        if ord == 2.0f64 { ret sq(p[1usize]) + sq(p[0usize]) }
        if ord == 3.0f64 { ret 3.0f64 * p[0usize] * sq(p[1usize]) + math.pow[f64](p[0usize], 3.0f64) }
        ret 3.0f64 * math.pow[f64](p[1usize], 4.0f64) + 6.0f64 * sq(p[0usize]) * sq(p[1usize]) + math.pow[f64](p[0usize], 4.0f64)
    }
    if kind == 1usize { ret math.exp[f64](ord * p[0usize] + sq(ord) * sq(p[1usize]) / 2.0f64) }
    if kind == 2usize {
        if ord == 1.0f64 { ret 1.0f64 / p[0usize] }
        ret 2.0f64 / sq(p[0usize])
    }
    if kind == 3usize {
        var r = p[0usize] / p[1usize]
        if ord == 1.0f64 { ret r }
        r = r * (p[0usize] + 1.0f64) / p[1usize]
        if ord == 2.0f64 { ret r }
        r = r * (p[0usize] + 2.0f64) / p[1usize]
        if ord == 3.0f64 { ret r }
        ret r * (p[0usize] + 3.0f64) / p[1usize]
    }
    if ord == 1.0f64 { ret p[0usize] }
    ret sq(p[1usize]) * sq(pi) / 3.0f64 + sq(p[0usize])
}

// mean(x^order) as memp does for the closed formulas
fn memp(a: *mem.Arena, x: []const f64, ord: usize) -> f64 {
    let mark = mem.mark(a)
    let (t, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        if ord == 1usize { t[i] = x[i] }
        if ord == 2usize { t[i] = x[i] * x[i] }
        if ord > 2usize { t[i] = math.pow[f64](x[i], f64(ord)) }
        i += 1usize
    }
    let m = ld.mean_ld(t)
    mem.reset(a, mark)
    ret m
}

// fills f.vc and f.sd of a fit_mme result
fn mme_vcov(a: *mem.Arena, x: []const f64, f: *Fit) {
    let np = f.np
    let eps = 1.4901161193847656e-08f64
    var j: [4]f64 = zero
    var w: [2]f64 = zero
    var k = 0usize
    while k < np {
        var i = 0usize
        while i < np {
            w[0usize] = f.est[0usize]
            if np > 1usize { w[1usize] = f.est[1usize] }
            w[i] = f.est[i] + eps
            let fp = mth(f.kind, f64(k + 1usize), w[0usize..np])
            w[i] = f.est[i] - eps
            let fm = mth(f.kind, f64(k + 1usize), w[0usize..np])
            j[k * np + i] = (fp - fm) / (2.0f64 * eps)
            i += 1usize
        }
        k += 1usize
    }
    var am: [4]f64 = zero
    var r = 0usize
    while r < np {
        var c = r
        while c < np {
            let v = mth(f.kind, f64(r + c + 2usize), f.est[0usize..np]) - memp(a, x, r + 1usize) * memp(a, x, c + 1usize)
            am[r * np + c] = v
            am[c * np + r] = v
            c += 1usize
        }
        r += 1usize
    }
    var ji: [4]f64 = zero
    if np == 1usize {
        ji[0usize] = 1.0f64 / j[0usize]
    } else {
        let det = j[0usize] * j[3usize] - j[1usize] * j[2usize]
        ji[0usize] = j[3usize] / det
        ji[1usize] = 0.0f64 - j[1usize] / det
        ji[2usize] = 0.0f64 - j[2usize] / det
        ji[3usize] = j[0usize] / det
    }
    // vc = ji * am * ji^T / n
    var t: [4]f64 = zero
    r = 0usize
    while r < np {
        var c = 0usize
        while c < np {
            var s = 0.0f64
            var q = 0usize
            while q < np {
                s += ji[r * np + q] * am[q * np + c]
                q += 1usize
            }
            t[r * np + c] = s
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < np {
        var c = 0usize
        while c < np {
            var s = 0.0f64
            var q = 0usize
            while q < np {
                s += t[r * np + q] * ji[c * np + q]
                q += 1usize
            }
            f.vc[r * np + c] = s / f64(x.len)
            c += 1usize
        }
        r += 1usize
    }
    f.sd[0usize] = math.sqrt[f64](f.vc[0usize])
    if np == 2usize { f.sd[1usize] = math.sqrt[f64](f.vc[3usize]) }
}
