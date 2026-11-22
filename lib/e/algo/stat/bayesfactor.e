// R BayesFactor: Bayes factors with JZS priors. Every function answers the natural log of BF10 as the package's bf slot does, by
// the package's own route: the same integrand, the same R integrate() call (QUADPACK qagi/qags at rel.tol = abs.tol =
// .Machine$double.eps^0.25, 100 subdivisions), so the quadrature error is the package's own and the values agree to rounding.
//
// ttest_tstat: ttest.tstat / meta.t.bf, the noncentral-t likelihood of delta under a Cauchy(0, rscale) prior, with null intervals
// and their complements. ttest_one / ttest_two: ttestBF on data. oneway_fstat: oneWayAOV.Fstat. linreg_r2: linearReg.R2stat.
// lm_bf, anova_bf, general_bf, lm_post: lmBF, anovaBF, generalTestBF and posterior() on data with factors and covariates, through
// the package's design matrix, singleGBayesFactor quadrature and nWayAOV's "auto" choice between its two samplers.
//
// Not ported: constant design columns (nWayAOV drops them), optim failing to converge in gaussianApproxAOV (the package then
// falls back to "simple"), more than 5 factors in a "withmain" enumeration, interactions of continuous variables alone.

use e.math
use e.math.quadpack as qp
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.nchisq as nc
use e.algo.stat.pracma as pr
use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.math.scale as msc
use e.algo.linalg.lapack_syevr as syevr
use e.algo.stat.rbfgs as rbfgs
use e.mem

fn ninf() -> f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
fn pinf() -> f64 { ret 1.0f64 / 0.0f64 }
fn isfin(x: f64) -> bool { ret x == x && x - x == 0.0f64 }
fn rel_tol() -> f64 { ret 1.220703125e-4f64 }

// R's dt(x, df, ncp, log = TRUE) (nmath dnt.c)
fn dnt_log(x: f64, df: f64, ncp: f64) -> f64 {
    if ncp == 0.0f64 { ret nb.dt(x, df, true) }
    if !isfin(x) { ret ninf() }
    if !isfin(df) || df > 1.0e8f64 { ret dist.dnorm(x, ncp, 1.0f64, true) }
    if math.abs[f64](x) > math.sqrt[f64](df * 2.220446049250313e-16f64) {
        let d = nc.pnt(x * math.sqrt[f64]((df + 2.0f64) / df), df + 2.0f64, ncp, true, false) - nc.pnt(x, df, ncp, true, false)
        ret math.log[f64](df) - math.log[f64](math.abs[f64](x)) + math.log[f64](math.abs[f64](d))
    }
    ret nm.lgammafn((df + 1.0f64) / 2.0f64) - nm.lgammafn(df / 2.0f64) - (0.572364942924700087071713675677f64 + 0.5f64 * (math.log[f64](df) + ncp * ncp))
}

// BayesFactor's log1pExp, logExpXplusExpY and logExpXminusExpY (logUtility.cpp)
fn log1p_exp(x: f64) -> f64 {
    if x > 36.04365338911715f64 { ret x }
    if x > 0.0f64 - 1.3862943611198906f64 { ret math.log[f64](1.0f64 + math.exp[f64](x)) }
    ret dist.log1p(math.exp[f64](x))
}
fn log_plus(x: f64, y: f64) -> f64 { ret x + log1p_exp(y - x) }
fn log_minus(x: f64, y: f64) -> f64 {
    let q = x - y
    if q <= 0.0f64 { ret x + ninf() }
    ret x + dist.log1_exp(0.0f64 - q)
}

// R's integrate() dispatch onto qags or qagi; an error unless QUADPACK answers ier 0
fn integrate[Ctx: type](a: *mem.Arena, c: *Ctx, f: fn(*Ctx, f64) -> f64, lo: f64, hi: f64) -> (qp.Qagi, err) {
    if isfin(lo) && isfin(hi) {
        let (r, e) = qp.qags[Ctx](a, c, f, lo, hi, rel_tol(), rel_tol(), 100usize)
        if e != ok { ret (r, e) }
        if r.ier != 0i64 { ret (r, mem.Invalid) }
        ret (r, ok)
    }
    var inf = 2i64
    var bound = 0.0f64
    if isfin(lo) {
        inf = 1i64
        bound = lo
    } else if isfin(hi) {
        inf = 0i64 - 1i64
        bound = hi
    }
    let (r, e) = qp.qagi[Ctx](a, c, f, bound, inf, rel_tol(), rel_tol(), 100usize)
    if e != ok { ret (r, e) }
    if r.ier != 0i64 { ret (r, mem.Invalid) }
    ret (r, ok)
}

type TCtx = struct { t: f64, n: f64, df: f64, rscale: f64, log_const: f64, shift: f64, scale: f64 }

fn t_like(c: *TCtx, delta: f64) -> f64 {
    let d = c.scale * delta + c.shift
    ret math.exp[f64](dnt_log(c.t, c.df, d * math.sqrt[f64](c.n)) + dist.dcauchy(d, 0.0f64, c.rscale, true) - c.log_const)
}

// meta.bf.interval for one t statistic
fn bf_interval(a: *mem.Arena, lower: f64, upper: f64, t: f64, n: f64, df: f64, rscale: f64) -> (f64, err) {
    let null_like = nb.dt(t, df, true)
    let prior = log_minus(dist.pcauchy(upper, 0.0f64, rscale, true, true), dist.pcauchy(lower, 0.0f64, rscale, true, true))
    let est = t / math.sqrt[f64](n)
    let mean = est * n / n
    let sd = 1.0f64 / math.sqrt[f64](n)
    var c = TCtx { t: t, n: n, df: df, rscale: rscale, log_const: 0.0f64, shift: 0.0f64, scale: 1.0f64 }
    c.log_const = dnt_log(t, df, mean * math.sqrt[f64](n)) + dist.dcauchy(mean, 0.0f64, rscale, true)
    c.shift = mean
    c.scale = sd
    let (r, e) = integrate[TCtx](a, &c, t_like, (lower - mean) / sd, (upper - mean) / sd)
    if e != ok { ret (0.0f64, e) }
    if r.result == 0.0f64 || r.result != r.result { ret (0.0f64, mem.Invalid) }
    ret (math.log[f64](r.result * sd) + c.log_const - prior - null_like, ok)
}

// meta.t.bf: lo, hi the null interval on delta (-Inf, Inf for none); compl asks for the complement of the interval
fn t_bf(a: *mem.Arena, t: f64, n: f64, df: f64, rscale: f64, lo0: f64, hi0: f64, compl: bool) -> (f64, err) {
    var lo = lo0
    var hi = hi0
    if lo > hi {
        lo = hi0
        hi = lo0
    }
    if !isfin(lo) && !isfin(hi) {
        if compl { ret (0.0f64, mem.Invalid) }
        let (rv, re) = bf_interval(a, ninf(), pinf(), t, n, df, rscale)
        ret (rv, re)
    }
    if !compl {
        let (rv, re) = bf_interval(a, lo, hi, t, n, df, rscale)
        ret (rv, re)
    }
    if !isfin(lo) {
        let (rv, re) = bf_interval(a, hi, pinf(), t, n, df, rscale)
        ret (rv, re)
    }
    if !isfin(hi) {
        let (rv, re) = bf_interval(a, ninf(), lo, t, n, df, rscale)
        ret (rv, re)
    }
    let l1 = dist.pcauchy(lo, 0.0f64, rscale, true, true)
    let l2 = dist.pcauchy(hi, 0.0f64, rscale, true, true)
    let p1 = log_minus(l1, ninf())
    let p3 = log_minus(0.0f64, l2)
    let p13 = log_plus(p1, p3)
    let (b1, e1) = bf_interval(a, ninf(), lo, t, n, df, rscale)
    if e1 != ok { ret (0.0f64, e1) }
    let (b3, e3) = bf_interval(a, hi, pinf(), t, n, df, rscale)
    if e3 != ok { ret (0.0f64, e3) }
    ret (log_plus(b1 + p1, b3 + p3) - p13, ok)
}

// ttest.tstat(t, n1, n2, nullInterval, rscale, complement)$bf; n2 = 0 is the one-sample test
fn ttest_tstat(a: *mem.Arena, t: f64, n1: f64, n2: f64, rscale: f64, lo: f64, hi: f64, compl: bool) -> (f64, err) {
    var nu = n1 - 1.0f64
    var n = n1
    if n2 != 0.0f64 {
        nu = n1 + n2 - 2.0f64
        n = math.exp[f64](math.log[f64](n1) + math.log[f64](n2) - math.log[f64](n1 + n2))
    }
    if n < 1.0f64 || nu < 1.0f64 { ret (0.0f64, mem.Invalid) }
    if !isfin(t) { ret (0.0f64, mem.Invalid) }
    let (rv, re) = t_bf(a, t, n, nu, rscale, lo, hi, compl)
    ret (rv, re)
}

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    let m = s / f64(x.len)
    var c = 0.0f64
    i = 0usize
    while i < x.len {
        c += x[i] - m
        i += 1usize
    }
    ret m + c / f64(x.len)
}

fn var_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

// ttestBF(x, mu = mu, nullInterval, rscale): the one-sample (or, on differences, paired) test on data
fn ttest_one(a: *mem.Arena, x: []const f64, mu: f64, rscale: f64, lo: f64, hi: f64, compl: bool) -> (f64, err) {
    let n = f64(x.len)
    let t = (mean_of(x) - mu) / math.sqrt[f64](var_of(x)) * math.sqrt[f64](n)
    let (rv, re) = ttest_tstat(a, t, n, 0.0f64, rscale, lo, hi, compl)
    ret (rv, re)
}

// ttestBF(x, y, nullInterval, rscale): the two-sample test, t from t.test(var.equal = TRUE)
fn ttest_two(a: *mem.Arena, x: []const f64, y: []const f64, rscale: f64, lo: f64, hi: f64, compl: bool) -> (f64, err) {
    let nx = f64(x.len)
    let ny = f64(y.len)
    let df = nx + ny - 2.0f64
    var v = 0.0f64
    if nx > 1.0f64 { v = (nx - 1.0f64) * var_of(x) }
    if ny > 1.0f64 { v += (ny - 1.0f64) * var_of(y) }
    v = v / df
    let se = math.sqrt[f64](v * (1.0f64 / nx + 1.0f64 / ny))
    let t = (mean_of(x) - mean_of(y)) / se
    let (rv, re) = ttest_tstat(a, t, nx, ny, rscale, lo, hi, compl)
    ret (rv, re)
}

type FCtx = struct { f: f64, n: f64, j: f64, rscale: f64, log_const: f64 }

fn oneway_log(c: *FCtx, g: f64) -> f64 {
    let dfs = (c.j - 1.0f64) / (c.n * c.j - c.j)
    let omega = (1.0f64 + c.n * g / (dfs * c.f + 1.0f64)) / (c.n * g + 1.0f64)
    ret math.log[f64](c.rscale) - 0.5f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - 1.5f64 * math.log[f64](g) - c.rscale * c.rscale / (2.0f64 * g) - (c.j - 1.0f64) / 2.0f64 * math.log[f64](c.n * g + 1.0f64) - (c.n * c.j - 1.0f64) / 2.0f64 * math.log[f64](omega) - c.log_const
}

fn oneway_g(c: *FCtx, g: f64) -> f64 { ret math.exp[f64](oneway_log(c, g)) }

// oneWayAOV.Fstat(F, N, J, rscale)$bf: N observations in each of J groups
fn oneway_fstat(a: *mem.Arena, f: f64, n: f64, j: f64, rscale: f64) -> (f64, err) {
    var c = FCtx { f: f, n: n, j: j, rscale: rscale, log_const: 0.0f64 }
    c.log_const = oneway_log(&c, 1.0f64)
    let (r, e) = integrate[FCtx](a, &c, oneway_g, 0.0f64, pinf())
    if e != ok { ret (0.0f64, e) }
    ret (math.log[f64](r.result) + c.log_const, ok)
}

type RCtx = struct { n: f64, p: f64, r2: f64, rs2: f64, log_const: f64, shift: f64 }

fn reg_log(c: *RCtx, u0: f64) -> f64 {
    let u = u0 + c.shift
    let aa = 0.5f64 * ((c.n - c.p - 1.0f64) * log1p_exp(u) - (c.n - 1.0f64) * log1p_exp(u + math.log[f64](1.0f64 - c.r2)))
    let b = c.rs2 * c.n / 2.0f64
    let dens = 0.5f64 * math.log[f64](b) - 0.572364942924700087071713675677f64 - 1.5f64 * u - b * math.exp[f64](0.0f64 - u)
    ret aa + dens - c.log_const + u
}

fn reg_u(c: *RCtx, u: f64) -> f64 { ret math.exp[f64](reg_log(c, u)) }

// linearReg.R2stat(N, p, R2, rscale)$bf
fn linreg_r2(a: *mem.Arena, n: f64, p: f64, r2: f64, rscale: f64) -> (f64, err) {
    if p < 1.0f64 || p >= n - 1.0f64 || r2 >= 1.0f64 || r2 < 0.0f64 { ret (0.0f64, mem.Invalid) }
    var z: [4]f64 = zero
    z[0usize] = n
    z[1usize] = n * (2.0f64 - r2) - 3.0f64
    z[2usize] = n - p - 4.0f64 - 2.0f64 * (1.0f64 - r2)
    z[3usize] = 0.0f64 - (1.0f64 - r2) * (p + 3.0f64)
    var re: [3]f64 = zero
    var im: [3]f64 = zero
    let deg = pr.polyroot_c(a, z[0usize..4usize], re[0usize..3usize], im[0usize..3usize])
    if deg < 1i64 { ret (0.0f64, mem.Invalid) }
    var best = 0usize
    var k = 1usize
    while k < usize(deg) {
        if im[k] * im[k] < im[best] * im[best] { best = k }
        k += 1usize
    }
    var modeg = re[best]
    if modeg <= 0.0f64 { modeg = n / 20.0f64 }
    var c = RCtx { n: n, p: p, r2: r2, rs2: rscale * rscale, log_const: 0.0f64, shift: math.log[f64](modeg) }
    c.log_const = reg_log(&c, 0.0f64)
    let (r, e) = integrate[RCtx](a, &c, reg_u, ninf(), pinf())
    if e != ok { ret (0.0f64, e) }
    ret (math.log[f64](r.result) + c.log_const, ok)
}

// BayesFactor's logRepresentedReal: a signed number held as (log |x|, sign), sign 0 for zero
type Lr = struct { m: f64, s: i64 }

fn lr_neg(x: Lr) -> Lr { ret Lr { m: x.m, s: 0i64 - x.s } }
fn lr_abs(x: Lr) -> Lr {
    if x.s == 0i64 { ret x }
    ret Lr { m: x.m, s: 1i64 }
}
fn lr_add(x: Lr, y: Lr) -> Lr {
    if x.s == 0i64 { ret y }
    if y.s == 0i64 { ret x }
    if x.s < 0i64 && y.s < 0i64 { ret lr_neg(lr_add(lr_neg(x), lr_neg(y))) }
    if x.s > 0i64 && y.s < 0i64 { ret lr_sub(x, lr_neg(y)) }
    if x.s < 0i64 && y.s > 0i64 { ret lr_sub(y, lr_neg(x)) }
    ret Lr { m: log_plus(x.m, y.m), s: 1i64 }
}
fn lr_sub(x: Lr, y: Lr) -> Lr {
    if x.s == 0i64 { ret lr_neg(y) }
    if y.s == 0i64 { ret x }
    if x.s < 0i64 && y.s < 0i64 { ret lr_add(lr_neg(lr_abs(x)), lr_abs(y)) }
    if x.s > 0i64 && y.s < 0i64 { ret lr_add(x, lr_neg(y)) }
    if x.s < 0i64 && y.s > 0i64 { ret lr_neg(lr_add(y, lr_neg(x))) }
    if x.m > y.m { ret Lr { m: log_minus(x.m, y.m), s: 1i64 } }
    if x.m < y.m { ret Lr { m: log_minus(y.m, x.m), s: 0i64 - 1i64 } }
    ret Lr { m: 0.0f64, s: 0i64 }
}

// logMeanExpLogs (logSummaryStats.cpp): Welford's running mean on log-represented values
fn log_mean_exp(x: []const f64) -> f64 {
    var m = Lr { m: x[0usize], s: 1i64 }
    var i = 1usize
    while i < x.len {
        let d = lr_sub(Lr { m: x[i], s: 1i64 }, m)
        m = lr_add(m, Lr { m: d.m - math.log[f64](f64(i + 1usize)), s: d.s })
        i += 1usize
    }
    ret m.m
}

fn log_mean2(x: f64, y: f64) -> f64 {
    var v: [2]f64 = zero
    v[0usize] = x
    v[1usize] = y
    ret log_mean_exp(v[0usize..2usize])
}

// genhypergeo_series_pos for two upper and one lower parameter: the log of the series at z; an error where it does not converge
fn genhyper_log(u1: f64, u2: f64, l: f64, z: f64) -> (f64, err) {
    if z > 1.0f64 { ret (0.0f64, mem.Invalid) }
    var fac = 0.0f64
    var temp = 0.0f64
    var i = 0usize
    while i < 2000usize {
        let fi = f64(i)
        fac = fac + (math.log[f64](u1 + fi) + math.log[f64](u2 + fi)) - math.log[f64](l + fi) + math.log[f64](z) - math.log[f64](fi + 1.0f64)
        let series = log_plus(temp, fac)
        if !(log_minus(series, temp) - temp > ninf()) { ret (series, ok) }
        temp = series
        i += 1usize
    }
    ret (0.0f64, mem.Invalid)
}

fn pi_() -> f64 { ret 3.141592653589793f64 }

// .bf10Exact(n, r, kappa)
fn corr_exact(n: f64, r: f64, k: f64) -> (f64, err) {
    if n <= 2.0f64 { ret (0.0f64, ok) }
    if k >= 1.0f64 && math.abs[f64](r) >= 1.0f64 { ret (pinf(), ok) }
    let (h, e) = genhyper_log((n - 1.0f64) / 2.0f64, (n - 1.0f64) / 2.0f64, (n + 2.0f64 / k) / 2.0f64, r * r)
    if e != ok { ret (0.0f64, e) }
    ret ((1.0f64 - 2.0f64 / k) * math.log[f64](2.0f64) + 0.5f64 * math.log[f64](pi_()) - nb.lbeta(1.0f64 / k, 1.0f64 / k) + nm.lgammafn((n + 2.0f64 / k - 1.0f64) / 2.0f64) - nm.lgammafn((n + 2.0f64 / k) / 2.0f64) + h, ok)
}

fn jeffreys(rho: f64, n: f64, r: f64) -> f64 { ret 0.5f64 * (n - 1.0f64) * dist.log1p(0.0f64 - rho * rho) - (n - 1.0f64 - 0.5f64) * dist.log1p(0.0f64 - rho * r) }

type CCtx = struct { n: f64, r: f64, k: f64, log_const: f64 }

fn corr_like(c: *CCtx, rho: f64) -> f64 { ret math.exp[f64](jeffreys(rho, c.n, c.r) + nb.dbeta(rho / 2.0f64 + 0.5f64, 1.0f64 / c.k, 1.0f64 / c.k, true) - math.log[f64](2.0f64) - c.log_const) }

// corr.test.bf.interval
fn corr_interval(a: *mem.Arena, n: f64, r: f64, k: f64, lo: f64, hi: f64) -> (f64, err) {
    let prior = log_minus(nb.pbeta(hi / 2.0f64 + 0.5f64, 1.0f64 / k, 1.0f64 / k, true, true), nb.pbeta(lo / 2.0f64 + 0.5f64, 1.0f64 / k, 1.0f64 / k, true, true))
    var c = CCtx { n: n, r: r, k: k, log_const: jeffreys(r, n, r) }
    let (q, e) = integrate[CCtx](a, &c, corr_like, lo, hi)
    if e != ok { ret (0.0f64, e) }
    if q.result < 0.0f64 { ret (0.0f64, mem.Invalid) }
    let v = math.exp[f64](math.log[f64](q.result) + c.log_const)
    ret (math.log[f64](v) - prior, ok)
}

// corr.test.bf on a sample correlation r of n pairs; lo <= -1 and hi >= 1 is no interval
fn corr_bf(a: *mem.Arena, n: f64, r: f64, k: f64, lo: f64, hi: f64, compl: bool) -> (f64, err) {
    if lo <= 0.0f64 - 1.0f64 && hi >= 1.0f64 {
        if compl { ret (0.0f64, mem.Invalid) }
        let (v, e) = corr_exact(n, r, k)
        ret (v, e)
    }
    if math.abs[f64](lo) >= 1.0f64 || math.abs[f64](hi) >= 1.0f64 {
        if !compl {
            let (v, e) = corr_interval(a, n, r, k, lo, hi)
            ret (v, e)
        }
        if lo <= 0.0f64 - 1.0f64 {
            let (v, e) = corr_interval(a, n, r, k, hi, 1.0f64)
            ret (v, e)
        }
        let (v, e) = corr_interval(a, n, r, k, 0.0f64 - 1.0f64, lo)
        ret (v, e)
    }
    if !compl {
        let (v, e) = corr_interval(a, n, r, k, lo, hi)
        ret (v, e)
    }
    let ik = 1.0f64 / k
    let l1 = nb.pbeta(0.0f64 - 1.0f64 / 2.0f64 + 0.5f64, ik, ik, true, true)
    let l2 = nb.pbeta(lo / 2.0f64 + 0.5f64, ik, ik, true, true)
    let l3 = nb.pbeta(hi / 2.0f64 + 0.5f64, ik, ik, true, true)
    let l4 = nb.pbeta(1.0f64 / 2.0f64 + 0.5f64, ik, ik, true, true)
    let p1 = log_minus(l2, l1)
    let p3 = log_minus(l4, l3)
    let p13 = log_mean2(p1, p3) + math.log[f64](2.0f64)
    let (b1, e1) = corr_interval(a, n, r, k, 0.0f64 - 1.0f64, lo)
    if e1 != ok { ret (0.0f64, e1) }
    let (b3, e3) = corr_interval(a, n, r, k, hi, 1.0f64)
    if e3 != ok { ret (0.0f64, e3) }
    ret (log_plus(b1 + p1, b3 + p3) - p13, ok)
}

fn cor_of(x: []const f64, y: []const f64) -> f64 {
    let mx = mean_of(x)
    let my = mean_of(y)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < x.len {
        sxy += (x[i] - mx) * (y[i] - my)
        sxx += (x[i] - mx) * (x[i] - mx)
        syy += (y[i] - my) * (y[i] - my)
        i += 1usize
    }
    var r = sxy / (math.sqrt[f64](sxx) * math.sqrt[f64](syy))
    if r > 1.0f64 { r = 1.0f64 }
    if r < 0.0f64 - 1.0f64 { r = 0.0f64 - 1.0f64 }
    ret r
}

// correlationBF(y, x, rscale, nullInterval) on data
fn correlation_bf(a: *mem.Arena, y: []const f64, x: []const f64, k: f64, lo: f64, hi: f64, compl: bool) -> (f64, err) {
    let (v, e) = corr_bf(a, f64(x.len), cor_of(y, x), k, lo, hi, compl)
    ret (v, e)
}

type PCtx = struct { y: []const f64, nn: []const f64, p: f64, rscale: f64, log_const: f64, shift: f64, scale: f64 }

fn prop_log(c: *PCtx, lo: f64) -> f64 {
    let x = lo * c.scale + c.shift
    let q = dist.plogis(x, 0.0f64, 1.0f64, true, false)
    var s = 0.0f64
    var i = 0usize
    while i < c.y.len {
        s += nb.dbinom(c.y[i], c.nn[i], q, true)
        i += 1usize
    }
    ret s + dist.dlogis(x, dist.qlogis(c.p, 0.0f64, 1.0f64, true, false), c.rscale, true) - c.log_const
}

fn prop_like(c: *PCtx, lo: f64) -> f64 { ret math.exp[f64](prop_log(c, lo)) }

// prop.test.bf.interval on the log-odds interval (lo, hi)
fn prop_interval(a: *mem.Arena, y: []const f64, nn: []const f64, p: f64, rs: f64, lo: f64, hi: f64) -> (f64, err) {
    let qp0 = dist.qlogis(p, 0.0f64, 1.0f64, true, false)
    let prior = log_minus(dist.plogis(hi, qp0, rs, true, true), dist.plogis(lo, qp0, rs, true, true))
    var sy = 0.0f64
    var sn = 0.0f64
    var i = 0usize
    while i < y.len {
        sy += y[i]
        sn += nn[i]
        i += 1usize
    }
    let ba = sy + 1.0f64
    let bb = sn - sy + 1.0f64
    let est = dist.qlogis(ba / (ba + bb), 0.0f64, 1.0f64, true, false)
    let pvar = ba * bb / ((ba + bb) * (ba + bb) * (ba + bb + 1.0f64))
    let dl = dist.dlogis(est, 0.0f64, 1.0f64, false)
    let sd = math.sqrt[f64](pvar / (dl * dl))
    var c = PCtx { y: y, nn: nn, p: p, rscale: rs, log_const: 0.0f64, shift: 0.0f64, scale: 1.0f64 }
    c.log_const = prop_log(&c, est)
    c.shift = est
    c.scale = sd
    let (q, e) = integrate[PCtx](a, &c, prop_like, (lo - est) / sd, (hi - est) / sd)
    if e != ok { ret (0.0f64, e) }
    var null_like = 0.0f64
    i = 0usize
    while i < y.len {
        null_like += nb.dbinom(y[i], nn[i], p, true)
        i += 1usize
    }
    ret (math.log[f64](q.result * sd) + c.log_const - prior - null_like, ok)
}

// proportionBF(y, N, p, rscale, nullInterval)$bf: lo, hi the interval on the probability scale (0, 1 for none)
fn proportion_bf(a: *mem.Arena, y: []const f64, nn: []const f64, p: f64, rs: f64, lo0: f64, hi0: f64, compl: bool) -> (f64, err) {
    let lo = dist.qlogis(lo0, 0.0f64, 1.0f64, true, false)
    let hi = dist.qlogis(hi0, 0.0f64, 1.0f64, true, false)
    if !isfin(lo) && !isfin(hi) {
        if compl { ret (0.0f64, mem.Invalid) }
        let (v, e) = prop_interval(a, y, nn, p, rs, lo, hi)
        ret (v, e)
    }
    if !compl {
        let (v, e) = prop_interval(a, y, nn, p, rs, lo, hi)
        ret (v, e)
    }
    if !isfin(lo) {
        let (v, e) = prop_interval(a, y, nn, p, rs, hi, pinf())
        ret (v, e)
    }
    if !isfin(hi) {
        let (v, e) = prop_interval(a, y, nn, p, rs, ninf(), lo)
        ret (v, e)
    }
    let qp0 = dist.qlogis(p, 0.0f64, 1.0f64, true, false)
    let p1 = log_minus(dist.plogis(lo, qp0, rs, true, true), dist.plogis(ninf(), qp0, rs, true, true))
    let p3 = log_minus(dist.plogis(pinf(), qp0, rs, true, true), dist.plogis(hi, qp0, rs, true, true))
    let p13 = log_mean2(p1, p3) + math.log[f64](2.0f64)
    let (b1, e1) = prop_interval(a, y, nn, p, rs, ninf(), lo)
    if e1 != ok { ret (0.0f64, e1) }
    let (b3, e3) = prop_interval(a, y, nn, p, rs, hi, pinf())
    if e3 != ok { ret (0.0f64, e3) }
    ret (log_plus(b1 + p1, b3 + p3) - p13, ok)
}

// lmBF / regressionBF for a model of continuous covariates: R^2 of lm(y ~ the columns of x picked by mask) with an intercept, then
// linearReg.R2stat; x is n x m column-major
fn regression_bf(a: *mem.Arena, y: []const f64, x: []const f64, m: usize, mask: []const bool, rscale: f64) -> (f64, err) {
    let n = y.len
    var p = 0usize
    var k = 0usize
    while k < m {
        if mask[k] { p += 1usize }
        k += 1usize
    }
    if p == 0usize { ret (0.0f64, ok) }
    let (q, e1) = mem.alloc[f64](a, n * p)
    let (r, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    let my = mean_of(y)
    var i = 0usize
    while i < n {
        r[i] = y[i] - my
        i += 1usize
    }
    var tss = 0.0f64
    i = 0usize
    while i < n {
        tss += r[i] * r[i]
        i += 1usize
    }
    var c = 0usize
    k = 0usize
    while k < m {
        if mask[k] {
            let col = x[k * n..k * n + n]
            let mc = mean_of(col)
            let v = q[c * n..c * n + n]
            i = 0usize
            while i < n {
                v[i] = col[i] - mc
                i += 1usize
            }
            var pass = 0usize
            while pass < 2usize {
                var d = 0usize
                while d < c {
                    let u = q[d * n..d * n + n]
                    var dot = 0.0f64
                    i = 0usize
                    while i < n {
                        dot += u[i] * v[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < n {
                        v[i] -= dot * u[i]
                        i += 1usize
                    }
                    d += 1usize
                }
                pass += 1usize
            }
            var nrm = 0.0f64
            i = 0usize
            while i < n {
                nrm += v[i] * v[i]
                i += 1usize
            }
            nrm = math.sqrt[f64](nrm)
            i = 0usize
            while i < n {
                v[i] = v[i] / nrm
                i += 1usize
            }
            var proj = 0.0f64
            i = 0usize
            while i < n {
                proj += v[i] * r[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                r[i] -= proj * v[i]
                i += 1usize
            }
            c += 1usize
        }
        k += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += r[i] * r[i]
        i += 1usize
    }
    let mss = tss - rss
    let (bfv, bfe) = linreg_r2(a, f64(n), f64(p), mss / (mss + rss), rscale)
    ret (bfv, bfe)
}

// lmBF(y ~ g) for one fixed factor with levels 0..nlev-1 in g: two levels go to the two-sample t test at rscale * sqrt(2),
// balanced designs to oneWayAOV.Fstat; an unbalanced design (nWayAOV sampling) is an error here
fn factor_bf(a: *mem.Arena, y: []const f64, g: []const usize, nlev: usize, rscale: f64) -> (f64, err) {
    let (cnt, e1) = mem.alloc[usize](a, nlev)
    let (sum, e2) = mem.alloc[f64](a, nlev)
    if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < nlev {
        cnt[i] = 0usize
        sum[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        cnt[g[i]] += 1usize
        i += 1usize
    }
    if nlev == 2usize {
        let (x0, e3) = mem.alloc[f64](a, cnt[0usize])
        let (x1, e4) = mem.alloc[f64](a, cnt[1usize])
        if e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
        var k0 = 0usize
        var k1 = 0usize
        i = 0usize
        while i < y.len {
            if g[i] == 0usize {
                x0[k0] = y[i]
                k0 += 1usize
            } else {
                x1[k1] = y[i]
                k1 += 1usize
            }
            i += 1usize
        }
        let (v, e) = ttest_two(a, x0, x1, rscale * math.sqrt[f64](2.0f64), ninf(), pinf(), false)
        ret (v, e)
    }
    i = 1usize
    while i < nlev {
        if cnt[i] != cnt[0usize] { ret (0.0f64, mem.Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        sum[g[i]] += y[i]
        i += 1usize
    }
    let gm = mean_of(y)
    var ssb = 0.0f64
    var ssw = 0.0f64
    var l = 0usize
    while l < nlev {
        let mu = sum[l] / f64(cnt[l])
        ssb += f64(cnt[l]) * (mu - gm) * (mu - gm)
        l += 1usize
    }
    i = 0usize
    while i < y.len {
        let mu = sum[g[i]] / f64(cnt[g[i]])
        ssw += (y[i] - mu) * (y[i] - mu)
        i += 1usize
    }
    let fj = f64(nlev)
    let f = (ssb / (fj - 1.0f64)) / (ssw / (f64(y.len) - fj))
    let (v, e) = oneway_fstat(a, f, f64(cnt[0usize]), fj, rscale)
    ret (v, e)
}

fn lg(x: f64) -> f64 { ret nm.lgammafn(x) }

// contingencyTableBF(y, sampleType, priorConcentration = conc)$bf for the I x J table y (column-major, as R stores it).
// kind 0 poisson, 1 joint multinomial, 2 independent multinomial with fixed rows, 3 the same with fixed columns, 4 hypergeometric
fn contingency_bf(a: *mem.Arena, y0: []const f64, ni0: usize, nj0: usize, kind: usize, conc: f64) -> (f64, err) {
    if conc < 1.0f64 { ret (0.0f64, mem.Invalid) }
    var ni = ni0
    var nj = nj0
    let (y, ey) = mem.alloc[f64](a, y0.len)
    if ey != ok { ret (0.0f64, ey) }
    var i = 0usize
    var j = 0usize
    if kind == 3usize {
        ni = nj0
        nj = ni0
        while i < ni {
            j = 0usize
            while j < nj {
                y[i + j * ni] = y0[j + i * ni0]
                j += 1usize
            }
            i += 1usize
        }
    } else {
        while i < y0.len {
            y[i] = y0[i]
            i += 1usize
        }
    }
    let fi = f64(ni)
    let fj = f64(nj)
    let (yr, e1) = mem.alloc[f64](a, ni)
    let (yc, e2) = mem.alloc[f64](a, nj)
    if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    i = 0usize
    while i < ni {
        yr[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < nj {
        yc[j] = 0.0f64
        j += 1usize
    }
    var n = 0.0f64
    var ldy_a = 0.0f64
    var ld_a = 0.0f64
    var sum_ya = 0.0f64
    var sum_a = 0.0f64
    var ld1 = 0.0f64
    j = 0usize
    while j < nj {
        i = 0usize
        while i < ni {
            let v = y[i + j * ni]
            yr[i] += v
            yc[j] += v
            n += v
            ldy_a += lg(v + conc)
            sum_ya += v + conc
            ld_a += lg(conc)
            sum_a += conc
            ld1 += lg(conc) - lg(conc + v)
            i += 1usize
        }
        j += 1usize
    }
    let ar = fj * conc
    let ac = fi * conc
    var r_off = 0.0f64
    var r_off_s = 0.0f64
    var r_y = 0.0f64
    var r_y_s = 0.0f64
    i = 0usize
    while i < ni {
        r_off += lg(ar - (fj - 1.0f64))
        r_off_s += ar - (fj - 1.0f64)
        r_y += lg(yr[i] + ar - (fj - 1.0f64))
        r_y_s += yr[i] + ar - (fj - 1.0f64)
        i += 1usize
    }
    var c_off = 0.0f64
    var c_off_s = 0.0f64
    var c_y = 0.0f64
    var c_y_s = 0.0f64
    j = 0usize
    while j < nj {
        c_off += lg(ac - (fi - 1.0f64))
        c_off_s += ac - (fi - 1.0f64)
        c_y += lg(yc[j] + ac - (fi - 1.0f64))
        c_y_s += yc[j] + ac - (fi - 1.0f64)
        j += 1usize
    }
    let ld_yr = r_y - lg(r_y_s)
    let ld_r = r_off - lg(r_off_s)
    let ld_yc = c_y - lg(c_y_s)
    let ld_c = c_off - lg(c_off_s)
    let ld_ya = ldy_a - lg(sum_ya)
    let ld_aa = ld_a - lg(sum_a)
    if kind == 0usize {
        let b = fi * fj * conc / n
        let df = (fi - 1.0f64) * (fj - 1.0f64)
        ret (lg(sum_a - df) - df * math.log[f64](1.0f64 + 1.0f64 / b) - lg(n + sum_a - df) - ld_yr + ld_r - ld_yc + ld_c - ld1, ok)
    }
    if kind == 1usize { ret (ld_ya + ld_r + ld_c - ld_aa - ld_yr - ld_yc, ok) }
    if kind == 2usize || kind == 3usize {
        var lar = 0.0f64
        var lyar = 0.0f64
        var syar = 0.0f64
        i = 0usize
        while i < ni {
            lar += lg(ar)
            lyar += lg(yr[i] + ar)
            syar += yr[i] + ar
            i += 1usize
        }
        ret (ld_c + (lar - lg(fi * ar)) + ld_ya - ld_yc - (lyar - lg(syar)) - ld_aa, ok)
    }
    if ni != 2usize || nj != 2usize { ret (0.0f64, mem.Invalid) }
    // hypergeometric: M = (col1, col2, row1, row2), every table with those margins
    let m1 = yc[0usize]
    let m3 = yr[0usize]
    let m4 = yr[1usize]
    var mmin = yc[0usize]
    if yc[1usize] < mmin { mmin = yc[1usize] }
    if m3 < mmin { mmin = m3 }
    if m4 < mmin { mmin = m4 }
    var upper = m1
    if m3 < upper { upper = m3 }
    var lower = 0.0f64
    if mmin < upper { lower = upper - mmin }
    let cnt = usize(upper - lower) + 1usize
    let (g, eg) = mem.alloc[f64](a, cnt)
    if eg != ok { ret (0.0f64, eg) }
    var s = 0usize
    while s < cnt {
        let t = lower + f64(s)
        var cell: [4]f64 = zero
        cell[0usize] = t
        cell[1usize] = m1 - t
        cell[2usize] = m3 - t
        cell[3usize] = m4 - m1 + t
        var nsum = 0.0f64
        var lx = 0.0f64
        var lya = 0.0f64
        var sya = 0.0f64
        var k = 0usize
        while k < 4usize {
            nsum += cell[k]
            lx += lg(cell[k] + 1.0f64)
            lya += lg(cell[k] + conc)
            sya += cell[k] + conc
            k += 1usize
        }
        g[s] = lg(nsum + 1.0f64) - lx + (lya - lg(sya)) - ld_aa
        s += 1usize
    }
    let sumg = log_mean_exp(g) + math.log[f64](f64(cnt))
    var pc = lg(n + 1.0f64)
    var prow = lg(n + 1.0f64)
    j = 0usize
    while j < 2usize {
        pc -= lg(yc[j] + 1.0f64)
        prow -= lg(yr[j] + 1.0f64)
        j += 1usize
    }
    ret (ld_ya + pc + prow - ld_aa - sumg, ok)
}

// The interval restriction of the t-test Gibbs samplers (ttestRcpp.cpp, ttestIndepRcpp.cpp): ivl says whether there is one,
// compl whether the draws are from its complement
type Ivl = struct { on: bool, compl: bool, lo: f64, hi: f64 }

// the location (mu, or beta) given sig2: normal, or the normal truncated to the interval of the standardised effect
fn draw_loc(g: *rng.Rng, iv: Ivl, m: f64, v: f64, sig2: f64) -> f64 {
    if !iv.on { ret rng.rnorm(g, m, math.sqrt[f64](v)) }
    let s = math.sqrt[f64](sig2)
    let sv = math.sqrt[f64](v)
    var lo = 0.0f64
    var hi = 1.0f64
    if !iv.compl {
        lo = dist.pnorm(s * iv.lo, m, sv, true, false)
        hi = dist.pnorm(s * iv.hi, m, sv, true, false)
    } else {
        let al = dist.pnorm(s * iv.lo, m, sv, true, true)
        let au = dist.pnorm(s * iv.hi, m, sv, false, true)
        if rd.rlogis(g, au - al, 1.0f64) > 0.0f64 {
            lo = dist.pnorm(s * iv.hi, m, sv, true, false)
            hi = 1.0f64
        } else {
            lo = 0.0f64
            hi = dist.pnorm(s * iv.lo, m, sv, true, false)
        }
    }
    let u = rng.runif(g, lo, hi)
    ret dist.qnorm(u, m, sv, true, false)
}

fn sq(x: f64) -> f64 { ret x * x }

// sig2 given the location loc: inverse gamma, or truncated so that loc / sqrt(sig2) stays in (or out of) the interval
fn draw_sig2(g: *rng.Rng, iv: Ivl, shape: f64, scale: f64, loc: f64) -> f64 {
    if !iv.on { ret 1.0f64 / rd.rgamma(g, shape, 1.0f64 / scale) }
    let agree = iv.lo * iv.hi >= 0.0f64
    let sc = 1.0f64 / scale
    var lo = 0.0f64
    var hi = 1.0f64
    if !iv.compl {
        if agree {
            lo = nm.pgamma(sq(iv.lo / loc), shape, sc, true, false)
            hi = nm.pgamma(sq(iv.hi / loc), shape, sc, true, false)
        } else {
            lo = 0.0f64
            if loc >= 0.0f64 {
                hi = nm.pgamma(sq(iv.hi / loc), shape, sc, true, false)
            } else {
                hi = nm.pgamma(sq(iv.lo / loc), shape, sc, true, false)
            }
        }
    } else {
        if agree {
            if loc * iv.lo < 0.0f64 {
                lo = 0.0f64
                hi = 1.0f64
            } else {
                let al = nm.pgamma(sq(iv.lo / loc), shape, sc, true, true)
                let au = nm.pgamma(sq(iv.hi / loc), shape, sc, false, true)
                if rd.rlogis(g, au - al, 1.0f64) > 0.0f64 {
                    lo = nm.pgamma(sq(iv.hi / loc), shape, sc, true, false)
                    hi = 1.0f64
                } else {
                    lo = 0.0f64
                    hi = nm.pgamma(sq(iv.lo / loc), shape, sc, true, false)
                }
            }
        } else {
            hi = 1.0f64
            if loc >= 0.0f64 {
                lo = nm.pgamma(sq(iv.hi / loc), shape, sc, true, false)
            } else {
                lo = nm.pgamma(sq(iv.lo / loc), shape, sc, true, false)
            }
        }
    }
    let u = rng.runif(g, lo, hi)
    ret 1.0f64 / nm.qgamma(u, shape, sc, true, false)
}

// posterior(ttestBF(x, nullInterval, rscale), iterations): gibbsOneSampleRcpp's chains (mu, sig2, delta, g), iterations x 4 column-major
fn gibbs_one(a: *mem.Arena, g: *rng.Rng, x: []const f64, rscale: f64, iv: Ivl, iterations: usize) -> ([]f64, err) {
    let (ch, e) = mem.alloc[f64](a, iterations * 4usize)
    if e != ok { ret (ch, e) }
    let n = f64(x.len)
    let ybar = mean_of(x)
    let s2 = var_of(x)
    let shape = 0.5f64 * n + 0.5f64
    let sumy2 = (n - 1.0f64) * s2 + n * sq(ybar)
    let rs2 = sq(rscale)
    var mu = ybar
    var sig2 = s2
    var gg = sq(ybar) / s2 + 1.0f64
    var i = 0usize
    while i < iterations {
        let vm = sig2 / (1.0f64 * n + 1.0f64 / gg)
        let mm = ybar * n * vm / sig2
        mu = draw_loc(g, iv, mm, vm, sig2)
        var sc = 0.5f64 * (sumy2 - 2.0f64 * n * ybar * mu)
        sc += (n + 1.0f64 / gg) * sq(mu) / 2.0f64
        sig2 = draw_sig2(g, iv, shape, sc, mu)
        let scg = 0.5f64 * (sq(mu) / sig2 + rs2)
        gg = 1.0f64 / rd.rgamma(g, 0.5f64 * 2.0f64, 1.0f64 / scg)
        ch[i] = mu
        ch[iterations + i] = sig2
        ch[2usize * iterations + i] = mu / math.sqrt[f64](sig2)
        ch[3usize * iterations + i] = gg
        i += 1usize
    }
    ret (ch, ok)
}

// posterior(ttestBF(x, y, nullInterval, rscale), iterations): gibbsTwoSampleRcpp's chains (mu, beta, sig2, delta, g), iterations x 5;
// beta is mean(x) - mean(y) as the package labels it (it orders the groups by reversed factor level)
fn gibbs_two(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, rscale: f64, iv: Ivl, iterations: usize) -> ([]f64, err) {
    let (ch, e) = mem.alloc[f64](a, iterations * 5usize)
    if e != ok { ret (ch, e) }
    let n0 = f64(y.len)
    let n1 = f64(x.len)
    let yb0 = mean_of(y)
    let yb1 = mean_of(x)
    let v0 = var_of(y)
    let v1 = var_of(x)
    let sumn = n0 + n1
    let shape = 0.5f64 * sumn + 0.5f64
    let rs2 = sq(rscale)
    let sumy1 = n0 * yb0
    let sumy2 = n1 * yb1
    let sumysq = ((n0 - 1.0f64) * v0 + n0 * sq(yb0)) + ((n1 - 1.0f64) * v1 + n1 * sq(yb1))
    let sumy = sumy1 + sumy2
    let diffy = n1 * yb1 - n0 * yb0
    let diffn = (n0 - n1) * 1.0f64
    var mu = sumy / sumn
    var beta = yb1 - yb0
    var sig2 = (v0 * (n0 - 1.0f64) + v1 * (n1 - 1.0f64)) / (sumn - 2.0f64)
    var gg = sq(beta) / sig2 + 1.0f64
    var i = 0usize
    while i < iterations {
        let mm = (sumy + (n0 - n1) * beta / 2.0f64) / sumn
        let vm = sig2 / sumn
        mu = rng.rnorm(g, mm, math.sqrt[f64](vm))
        let vb = sig2 / (sumn / 4.0f64 + 1.0f64 / gg)
        let mb = vb / sig2 * ((sumy2 - sumy1) + mu * diffn) / 2.0f64
        beta = draw_loc(g, iv, mb, vb, sig2)
        var sc = 0.5f64 * (sumysq - 2.0f64 * mu * sumy - beta * diffy + n0 * sq(mu - beta / 2.0f64) + n1 * sq(mu + beta / 2.0f64))
        sc += sq(beta) / gg / 2.0f64
        sig2 = draw_sig2(g, iv, shape, sc, beta)
        let scg = 0.5f64 * (sq(beta) / sig2 + rs2)
        gg = 1.0f64 / rd.rgamma(g, 0.5f64 * 2.0f64, 1.0f64 / scg)
        ch[i] = mu
        ch[iterations + i] = beta
        ch[2usize * iterations + i] = sig2
        ch[3usize * iterations + i] = beta / math.sqrt[f64](sig2)
        ch[4usize * iterations + i] = gg
        i += 1usize
    }
    ret (ch, ok)
}

// BayesFactor's rdirichlet(1, alpha) into out: stats::rgamma per component, then divided by the running sum
fn dirichlet1(g: *rng.Rng, alpha: []const f64, out: []f64) {
    var s = 0.0f64
    var k = 0usize
    while k < alpha.len {
        out[k] = rd.rgamma(g, alpha[k], 1.0f64)
        k += 1usize
    }
    k = 0usize
    while k < alpha.len {
        s += out[k]
        k += 1usize
    }
    k = 0usize
    while k < alpha.len {
        out[k] = out[k] / s
        k += 1usize
    }
}

// posterior(contingencyTableBF(y, sampleType, fixedMargin, priorConcentration = conc), iterations): the package's sampler for the
// non-independence model, chains iterations x columns column-major in the package's column order. kind as in contingency_bf;
// the hypergeometric sampler is not implemented in the package either. Returns the chains and the number of columns.
fn contingency_post(a: *mem.Arena, g: *rng.Rng, y: []const f64, ni: usize, nj: usize, kind: usize, conc: f64, it: usize) -> ([]f64, usize, err) {
    let ij = ni * nj
    var ncol = ij
    if kind == 2usize { ncol = ij + ni + ij }
    if kind == 3usize { ncol = ij + nj + ij }
    let (ch, e) = mem.alloc[f64](a, it * ncol)
    let (al, e2) = mem.alloc[f64](a, ij + ni + nj)
    let (tmp, e3) = mem.alloc[f64](a, ij + ni + nj)
    if e != ok || e2 != ok || e3 != ok || kind == 4usize { ret (ch, 0usize, mem.Invalid) }
    var n = 0.0f64
    var k = 0usize
    while k < ij {
        n += y[k]
        k += 1usize
    }
    var i = 0usize
    if kind == 0usize {
        let b = f64(ij) * conc / n
        let sc = 1.0f64 / (b + 1.0f64)
        while i < it {
            k = 0usize
            while k < ij {
                ch[k * it + i] = rd.rgamma(g, y[k] + conc, sc)
                k += 1usize
            }
            i += 1usize
        }
        ret (ch, ncol, ok)
    }
    if kind == 1usize {
        k = 0usize
        while k < ij {
            al[k] = y[k] + conc
            k += 1usize
        }
        while i < it {
            dirichlet1(g, al[0usize..ij], tmp[0usize..ij])
            k = 0usize
            while k < ij {
                ch[k * it + i] = tmp[k]
                k += 1usize
            }
            i += 1usize
        }
        ret (ch, ncol, ok)
    }
    // independent multinomial: the fixed margin's probabilities pi_star first, then omega within each fixed row (column)
    var nf = ni
    var nm2 = nj
    if kind == 3usize {
        nf = nj
        nm2 = ni
    }
    var f = 0usize
    while f < nf {
        var s = 0.0f64
        var m = 0usize
        while m < nm2 {
            if kind == 2usize { s += y[f + m * ni] } else { s += y[m + f * ni] }
            m += 1usize
        }
        al[f] = s + f64(nm2) * conc
        f += 1usize
    }
    i = 0usize
    while i < it {
        dirichlet1(g, al[0usize..nf], tmp[0usize..nf])
        f = 0usize
        while f < nf {
            ch[(ij + f) * it + i] = tmp[f]
            f += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < it {
        f = 0usize
        while f < nf {
            var m = 0usize
            while m < nm2 {
                if kind == 2usize { al[m] = y[f + m * ni] + conc } else { al[m] = y[m + f * ni] + conc }
                m += 1usize
            }
            dirichlet1(g, al[0usize..nm2], tmp[0usize..nm2])
            m = 0usize
            while m < nm2 {
                var cell = m + f * ni
                if kind == 2usize { cell = f + m * ni }
                let ps = ch[(ij + f) * it + i]
                ch[(ij + nf + cell) * it + i] = tmp[m]
                ch[cell * it + i] = ps * tmp[m]
                m += 1usize
            }
            f += 1usize
        }
        i += 1usize
    }
    ret (ch, ncol, ok)
}

// The likelihoods of the two independence Metropolis samplers: proptest_like_Rcpp (proportion.cpp) when corr is false,
// corrtest_like_Rcpp with the Jeffreys approximation (corr.cpp) when it is true
type MCtx = struct { corr: bool, y: []const f64, nn: []const f64, mu: f64, rscale: f64, r: f64, n: f64, ab: f64 }

fn metrop_like(c: *MCtx, v: f64) -> f64 {
    if c.corr {
        let rho = msc.tanh(v)
        ret nb.dbeta((rho + 1.0f64) / 2.0f64, c.ab, c.ab, true) + dist.log1p(0.0f64 - rho * rho) + jeffreys(rho, c.n, c.r)
    }
    let theta = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - v))
    var s = dist.dlogis(v, c.mu, c.rscale, true)
    var i = 0usize
    while i < c.y.len {
        s += nb.dbinom(c.y[i], c.nn[i], theta, true)
        i += 1usize
    }
    ret s
}

// the shared sampler: an independent normal candidate (m0, sd), restricted to (or away from) the interval ilo..ihi on the
// sampled scale; the package's interval-validity test is kept as written (it never sees a draw inside the interval)
fn metrop(g: *rng.Rng, c: *MCtx, m0: f64, sd: f64, iv: Ivl, it: usize, out: []f64) {
    var ub0 = 0.0f64
    var ub1 = 0.0f64
    if iv.on {
        ub0 = dist.pnorm(iv.lo, m0, sd, true, false)
        ub1 = dist.pnorm(iv.hi, m0, sd, true, false)
    }
    var cur = m0
    var valid = true
    var i = 0usize
    while i < it {
        var cand = 0.0f64
        if iv.on {
            if iv.compl {
                cand = rng.runif(g, 0.0f64, ub0 + 1.0f64 - ub1)
                if cand > ub0 { cand = cand - ub0 + ub1 }
            } else {
                cand = rng.runif(g, ub0, ub1)
            }
            cand = dist.qnorm(cand, m0, sd, true, false)
        } else {
            cand = rng.rnorm(g, m0, sd)
        }
        let z = metrop_like(c, cand) - metrop_like(c, cur) + dist.dnorm(cur, m0, sd, true) - dist.dnorm(cand, m0, sd, true)
        if iv.on {
            let tr = dist.pnorm(cur, m0, sd, true, false)
            let inside = ub0 > tr && ub1 < tr
            if (inside && iv.compl) || (!inside && !iv.compl) { valid = false }
        }
        if rng.rexp(g, 1.0f64) > 0.0f64 - z || !valid { cur = cand }
        out[i] = cur
        i += 1usize
    }
}

// posterior(proportionBF(y, N, p, rscale, nullInterval), iterations): metropProportionRcpp's chain, columns (logodds, p);
// iv.lo, iv.hi on the probability scale
fn proportion_post(a: *mem.Arena, g: *rng.Rng, y: []const f64, nn: []const f64, p0: f64, rscale: f64, iv0: Ivl, it: usize) -> ([]f64, err) {
    let (ch, e) = mem.alloc[f64](a, it * 2usize)
    if e != ok { ret (ch, e) }
    var sy = 0.0f64
    var sn = 0.0f64
    var i = 0usize
    while i < y.len {
        sy += y[i]
        sn += nn[i]
        i += 1usize
    }
    let lp = math.log[f64](sy + 1.0f64) - math.log[f64](sn + 2.0f64)
    let lo0 = dist.qlogis(lp, 0.0f64, 1.0f64, true, true)
    let sd = math.exp[f64](0.5f64 * (lp + dist.log1_exp(lp) - math.log[f64](sn + 2.0f64) - 2.0f64 * dist.dlogis(lo0, 0.0f64, 1.0f64, true)))
    var iv = iv0
    if iv.on {
        iv.lo = dist.qlogis(iv0.lo, 0.0f64, 1.0f64, true, false)
        iv.hi = dist.qlogis(iv0.hi, 0.0f64, 1.0f64, true, false)
    }
    var c = MCtx { corr: false, y: y, nn: nn, mu: math.log[f64](p0 / (1.0f64 - p0)), rscale: rscale, r: 0.0f64, n: 0.0f64, ab: 0.0f64 }
    metrop(g, &c, lo0, sd, iv, it, ch[0usize..it])
    i = 0usize
    while i < it {
        ch[it + i] = dist.plogis(ch[i], 0.0f64, 1.0f64, true, false)
        i += 1usize
    }
    ret (ch, ok)
}

// posterior(correlationBF(y, x, rscale, nullInterval), iterations): metropCorrRcpp_jeffreys's chain, columns (rho, zeta)
fn correlation_post(a: *mem.Arena, g: *rng.Rng, y: []const f64, x: []const f64, rscale: f64, iv0: Ivl, it: usize) -> ([]f64, err) {
    let (ch, e) = mem.alloc[f64](a, it * 2usize)
    if e != ok { ret (ch, e) }
    let r = cor_of(y, x)
    let n = f64(x.len)
    let fz = 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r))
    let z0 = fz * (n - 2.0f64) / (n - 2.0f64)
    let sd = math.sqrt[f64](1.0f64 / (n - 2.0f64))
    var iv = iv0
    if iv.on {
        iv.lo = 0.5f64 * math.log[f64]((1.0f64 + iv0.lo) / (1.0f64 - iv0.lo))
        iv.hi = 0.5f64 * math.log[f64]((1.0f64 + iv0.hi) / (1.0f64 - iv0.hi))
    }
    var c = MCtx { corr: true, y: y, nn: x, mu: 0.0f64, rscale: rscale, r: r, n: n, ab: 1.0f64 / rscale }
    metrop(g, &c, z0, sd, iv, it, ch[it..2usize * it])
    var i = 0usize
    while i < it {
        ch[i] = msc.tanh(ch[it + i])
        i += 1usize
    }
    ret (ch, ok)
}

// the lower Cholesky factor of the symmetric q x q matrix s (lower triangle read, column-major) into l
fn chol_lower(s: []const f64, q: usize, l: []f64) {
    var j = 0usize
    while j < q * q {
        l[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < q {
        var d = s[j + j * q]
        var k = 0usize
        while k < j {
            d -= l[j + k * q] * l[j + k * q]
            k += 1usize
        }
        d = math.sqrt[f64](d)
        l[j + j * q] = d
        var i = j + 1usize
        while i < q {
            var v = s[i + j * q]
            k = 0usize
            while k < j {
                v -= l[i + k * q] * l[j + k * q]
                k += 1usize
            }
            l[i + j * q] = v / d
            i += 1usize
        }
        j += 1usize
    }
}

// posterior() for the linear models (lmBF, regressionBF, anovaBF, generalTestBF): jzs_Gibbs on the design x (n x q column-major,
// the first column the intercept), gmap the g index of each of the q - 1 effect columns (the inc_cont continuous ones first),
// rscale per g, sig2 starting at 1 as nWayAOV.Gibbs starts it. Chains iterations x (q + 1 + ng): beta, sig2, g.
fn jzs_gibbs(a: *mem.Arena, g: *rng.Rng, y: []const f64, x: []const f64, q: usize, gmap: []const usize, rscale: []const f64, inc_cont: usize, it: usize) -> ([]f64, err) {
    let (ch, e) = jzs_gibbs_from(a, g, y, x, q, gmap, rscale, inc_cont, it, 1.0f64)
    ret (ch, e)
}

// posterior(lmBF(y ~ covariates)) for continuous covariates only (linearReg.Gibbs): the covariates (n x p column-major) are
// centred, sig2 starts at the residual variance of y on them without an intercept, then jzs_Gibbs with one g
fn linreg_post(a: *mem.Arena, g: *rng.Rng, y: []const f64, cov: []const f64, p: usize, rscale: f64, it: usize) -> ([]f64, err) {
    let n = y.len
    let q = p + 1usize
    let (x, e1) = mem.alloc[f64](a, n * q)
    let (u, e2) = mem.alloc[f64](a, n * p)
    let (r, e3) = mem.alloc[f64](a, n)
    let (gm, e4) = mem.alloc[usize](a, p)
    let (rs, e5) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (x, mem.Full) }
    var i = 0usize
    while i < n {
        x[i] = 1.0f64
        r[i] = y[i]
        i += 1usize
    }
    var j = 0usize
    while j < p {
        gm[j] = 0usize
        let col = cov[j * n..j * n + n]
        let m = mean_of(col)
        i = 0usize
        while i < n {
            x[(j + 1usize) * n + i] = col[i] - m
            u[j * n + i] = col[i] - m
            i += 1usize
        }
        var pass = 0usize
        while pass < 2usize {
            var d = 0usize
            while d < j {
                var dot = 0.0f64
                i = 0usize
                while i < n {
                    dot += u[d * n + i] * u[j * n + i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    u[j * n + i] -= dot * u[d * n + i]
                    i += 1usize
                }
                d += 1usize
            }
            pass += 1usize
        }
        var nrm = 0.0f64
        i = 0usize
        while i < n {
            nrm += u[j * n + i] * u[j * n + i]
            i += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        var proj = 0.0f64
        i = 0usize
        while i < n {
            u[j * n + i] = u[j * n + i] / nrm
            proj += u[j * n + i] * r[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            r[i] -= proj * u[j * n + i]
            i += 1usize
        }
        j += 1usize
    }
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += r[i] * r[i]
        i += 1usize
    }
    rs[0usize] = rscale
    let (ch, e) = jzs_gibbs_from(a, g, y, x, q, gm, rs, p, it, ss / f64(n))
    ret (ch, e)
}

// jzs_sampler's state: the centred design's X'X and X'y, the prior of the inc_cont continuous columns and its log determinant;
// x is n x p column-major without the intercept, the inc_cont continuous columns first
type Nw = struct { n: usize, p: usize, inc: usize, xtx: []f64, xty: []f64, prx: []f64, w: []f64, lf: []f64, sol: []f64, gg: []f64, ldet_prior: f64, sumsq: f64, gmap: []const usize, rscale: []const f64 }

// nWayAOV(y, X, gMap, rscale, iterations, method = "simple")$bf, the Monte Carlo estimate for models with several g
// (jzs_sampler with jzs_mc_marg_like2)
fn nway_mc_bf(a: *mem.Arena, g: *rng.Rng, y: []const f64, x: []const f64, p: usize, gmap: []const usize, rscale: []const f64, inc_cont: usize, it: usize) -> (f64, err) {
    let (c, e) = nw_prep(a, y, x, p, gmap, rscale, inc_cont)
    let (logs, e2) = mem.alloc[f64](a, it)
    if e != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var cc = c
    nw_draw(g, &cc, false, rscale, rscale, logs)
    ret (log_mean_exp(logs), ok)
}

fn nw_prep(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, gmap: []const usize, rscale: []const f64, inc_cont: usize) -> (Nw, err) {
    let n = y.len
    let ng = rscale.len
    let (cx, e1) = mem.alloc[f64](a, n * p)
    let (xtx, e2) = mem.alloc[f64](a, p * p)
    let (w, e3) = mem.alloc[f64](a, p * p)
    let (lf, e4) = mem.alloc[f64](a, p * p)
    let (vec, e5) = mem.alloc[f64](a, 2usize * p + ng + inc_cont * inc_cont + 1usize)
    var c = Nw { n: n, p: p, inc: inc_cont, xtx: xtx, xty: w, prx: w, w: w, lf: lf, sol: w, gg: w, ldet_prior: 0.0f64, sumsq: 0.0f64, gmap: gmap, rscale: rscale }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (c, mem.Full) }
    let xty = vec[0usize..p]
    let prx = vec[2usize * p + ng..2usize * p + ng + inc_cont * inc_cont]
    c.xty = xty
    c.sol = vec[p..2usize * p]
    c.gg = vec[2usize * p..2usize * p + ng]
    c.prx = prx
    let fn_ = f64(n)
    let ybar = mean_of(y)
    var sumsq = 0.0f64
    var i = 0usize
    var j = 0usize
    while j < p {
        let col = x[j * n..j * n + n]
        let m = mean_of(col)
        i = 0usize
        while i < n {
            cx[j * n + i] = col[i] - m
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        sumsq += (y[i] - ybar) * (y[i] - ybar)
        i += 1usize
    }
    var k = 0usize
    j = 0usize
    while j < p {
        k = 0usize
        while k < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += cx[j * n + i] * cx[k * n + i]
                i += 1usize
            }
            xtx[j + k * p] = s
            k += 1usize
        }
        var t = 0.0f64
        i = 0usize
        while i < n {
            t += (y[i] - ybar) * cx[j * n + i]
            i += 1usize
        }
        xty[j] = t
        j += 1usize
    }
    var ldet_prior = 0.0f64
    if inc_cont > 0usize {
        j = 0usize
        while j < inc_cont {
            k = 0usize
            while k <= j {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += cx[j * n + i] * cx[k * n + i]
                    i += 1usize
                }
                prx[j + k * inc_cont] = s / fn_
                prx[k + j * inc_cont] = s / fn_
                k += 1usize
            }
            j += 1usize
        }
        chol_lower(prx, inc_cont, lf)
        j = 0usize
        while j < inc_cont {
            ldet_prior += 2.0f64 * math.log[f64](lf[j + j * inc_cont])
            j += 1usize
        }
    }
    c.ldet_prior = ldet_prior
    c.sumsq = sumsq
    ret (c, ok)
}

// jzs_sampler: one log likelihood ratio per element of out, g drawn from its inverse-gamma prior, or (imp) log g from
// N(mu, sig) with the importance weight of jzs_importance_marg_like2
fn nw_draw(g: *rng.Rng, c: *Nw, imp: bool, mu: []const f64, sig: []const f64, out: []f64) {
    let ng = c.rscale.len
    var iter = 0usize
    while iter < out.len {
        var j = 0usize
        if !imp {
            while j < ng {
                c.gg[j] = 1.0f64 / rd.rgamma(g, 0.5f64, 2.0f64 / (c.rscale[j] * c.rscale[j]))
                j += 1usize
            }
            out[iter] = nw_marg(c)
        } else {
            while j < ng {
                c.gg[j] = rng.rnorm(g, mu[j], sig[j])
                j += 1usize
            }
            var snorm = 0.0f64
            var sinvg = 0.0f64
            var sq_ = 0.0f64
            j = 0usize
            while j < ng {
                let q = c.gg[j]
                snorm += dist.dnorm(q, mu[j], sig[j], true)
                sinvg += dinvgamma1(math.exp[f64](q), 0.5f64, c.rscale[j] * c.rscale[j] / 2.0f64)
                sq_ += q
                c.gg[j] = math.exp[f64](q)
                j += 1usize
            }
            out[iter] = nw_marg(c) + sinvg - snorm + sq_
        }
        iter += 1usize
    }
}

fn dinvgamma1(x: f64, sh: f64, b: f64) -> f64 { ret sh * math.log[f64](b) - nm.lgammafn(sh) - (sh + 1.0f64) * math.log[f64](x) - b / x }

// jzs_mc_marg_like2 at the g values in c.gg
fn nw_marg(c: *Nw) -> f64 {
    let p = c.p
    let inc_cont = c.inc
    let xtx = c.xtx
    let xty = c.xty
    let w = c.w
    let lf = c.lf
    let sol = c.sol
    let gg = c.gg
    let gmap = c.gmap
    let prx = c.prx
    let fn_ = f64(c.n)
    let sumsq = c.sumsq
    var k = 0usize
    var j = 0usize
    while j < p * p {
        w[j] = xtx[j]
        j += 1usize
    }
    var ldets = 0.0f64 - c.ldet_prior
    j = 0usize
    while j < inc_cont {
        ldets += math.log[f64](gg[gmap[j]])
        k = 0usize
        while k <= j {
            w[j + k * p] += prx[j + k * inc_cont] / gg[gmap[j]]
            k += 1usize
        }
        j += 1usize
    }
    j = inc_cont
    while j < p {
        ldets += math.log[f64](gg[gmap[j]])
        w[j + j * p] += 1.0f64 / gg[gmap[j]]
        j += 1usize
    }
    chol_lower(w, p, lf)
    var ldetw = 0.0f64
    j = 0usize
    while j < p {
        ldetw += 2.0f64 * math.log[f64](lf[j + j * p])
        j += 1usize
    }
    ldetw = 0.0f64 - ldetw
    j = 0usize
    while j < p {
        var v = xty[j]
        k = 0usize
        while k < j {
            v -= lf[j + k * p] * sol[k]
            k += 1usize
        }
        sol[j] = v / lf[j + j * p]
        j += 1usize
    }
    var r = p
    while r > 0usize {
        r -= 1usize
        var v = sol[r]
        k = r + 1usize
        while k < p {
            v -= lf[k + r * p] * sol[k]
            k += 1usize
        }
        sol[r] = v / lf[r + r * p]
    }
    var qf = 0.0f64
    j = 0usize
    while j < p {
        qf += xty[j] * sol[j]
        j += 1usize
    }
    ret 0.5f64 * ldetw - 0.5f64 * (fn_ - 1.0f64) * dist.log1p(0.0f64 - qf / sumsq) - 0.5f64 * ldets
}

fn jzs_gibbs_from(a: *mem.Arena, g: *rng.Rng, y: []const f64, x: []const f64, q: usize, gmap: []const usize, rscale: []const f64, inc_cont: usize, it: usize, sig2start: f64) -> ([]f64, err) {
    let n = y.len
    let p = q - 1usize
    let ng = rscale.len
    let ncol = q + 1usize + ng
    let (ch, e1) = mem.alloc[f64](a, it * ncol)
    let (xtx, e2) = mem.alloc[f64](a, q * q)
    let (sg, e3) = mem.alloc[f64](a, q * q)
    let (lf, e4) = mem.alloc[f64](a, q * q)
    let (vec, e5) = mem.alloc[f64](a, 4usize * q + 3usize * ng + n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (ch, mem.Full) }
    let xty = vec[0usize..q]
    let mu = vec[q..2usize * q]
    let beta = vec[2usize * q..3usize * q]
    let z = vec[3usize * q..4usize * q]
    let gg = vec[4usize * q..4usize * q + ng]
    let ssqg = vec[4usize * q + ng..4usize * q + 2usize * ng]
    let cnt = vec[4usize * q + 2usize * ng..4usize * q + 3usize * ng]
    let resid = vec[4usize * q + 3usize * ng..4usize * q + 3usize * ng + n]
    var i = 0usize
    var j = 0usize
    var k = 0usize
    while j < q {
        k = 0usize
        while k < q {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += x[i + j * n] * x[i + k * n]
                i += 1usize
            }
            xtx[j + k * q] = s
            k += 1usize
        }
        var t = 0.0f64
        i = 0usize
        while i < n {
            t += x[i + j * n] * y[i]
            i += 1usize
        }
        xty[j] = t
        j += 1usize
    }
    j = 0usize
    while j < ng {
        gg[j] = 1.0f64
        cnt[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < p {
        cnt[gmap[j]] += 1.0f64
        j += 1usize
    }
    let fn_ = f64(n)
    var sig2 = sig2start
    var iter = 0usize
    while iter < it {
        j = 0usize
        while j < q * q {
            sg[j] = xtx[j]
            j += 1usize
        }
        j = 0usize
        while j < p {
            let gj = gg[gmap[j]]
            if j < inc_cont {
                sg[(j + 1usize) + (j + 1usize) * q] += xtx[(j + 1usize) + (j + 1usize) * q] / fn_ / gj
                k = 0usize
                while k < j {
                    sg[(j + 1usize) + (k + 1usize) * q] += xtx[(j + 1usize) + (k + 1usize) * q] / fn_ / gj
                    k += 1usize
                }
            } else {
                sg[(j + 1usize) + (j + 1usize) * q] += 1.0f64 / gj
            }
            j += 1usize
        }
        // Sigma = sig2 * S^-1 by the Cholesky factor of S, column by column of the identity
        chol_lower(sg, q, lf)
        var col = 0usize
        while col < q {
            i = 0usize
            while i < q {
                var v = 0.0f64
                if i == col { v = 1.0f64 }
                k = 0usize
                while k < i {
                    v -= lf[i + k * q] * z[k]
                    k += 1usize
                }
                z[i] = v / lf[i + i * q]
                i += 1usize
            }
            var r = q
            while r > 0usize {
                r -= 1usize
                var v = z[r]
                k = r + 1usize
                while k < q {
                    v -= lf[k + r * q] * mu[k]
                    k += 1usize
                }
                mu[r] = v / lf[r + r * q]
            }
            i = 0usize
            while i < q {
                sg[i + col * q] = sig2 * mu[i]
                i += 1usize
            }
            col += 1usize
        }
        i = 0usize
        while i < q {
            var v = 0.0f64
            k = 0usize
            while k < q {
                v += sg[i + k * q] * xty[k]
                k += 1usize
            }
            mu[i] = v / sig2
            i += 1usize
        }
        chol_lower(sg, q, lf)
        i = 0usize
        while i < q {
            z[i] = rng.rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < q {
            var v = 0.0f64
            k = 0usize
            while k <= i {
                v += lf[i + k * q] * z[k]
                k += 1usize
            }
            beta[i] = mu[i] + v
            i += 1usize
        }
        var ssq = 0.0f64
        i = 0usize
        while i < n {
            var f = 0.0f64
            k = 0usize
            while k < q {
                f += x[i + k * n] * beta[k]
                k += 1usize
            }
            resid[i] = y[i] - f
            ssq += resid[i] * resid[i]
            i += 1usize
        }
        j = 0usize
        while j < ng {
            ssqg[j] = 0.0f64
            j += 1usize
        }
        if inc_cont > 0usize {
            var qf = 0.0f64
            j = 0usize
            while j < inc_cont {
                var v = 0.0f64
                k = 0usize
                while k < inc_cont {
                    v += beta[k + 1usize] * xtx[(k + 1usize) + (j + 1usize) * q]
                    k += 1usize
                }
                qf += v * beta[j + 1usize]
                j += 1usize
            }
            ssqg[gmap[0usize]] += qf / fn_
        }
        j = inc_cont
        while j < p {
            ssqg[gmap[j]] += beta[j + 1usize] * beta[j + 1usize]
            j += 1usize
        }
        var sg2 = 0.0f64
        j = 0usize
        while j < ng {
            sg2 += ssqg[j] / gg[j]
            j += 1usize
        }
        ssq += sg2
        sig2 = 1.0f64 / rd.rgamma(g, 0.5f64 * (fn_ + f64(p)), 2.0f64 / ssq)
        j = 0usize
        while j < ng {
            gg[j] = 1.0f64 / rd.rgamma(g, 0.5f64 * (cnt[j] + 1.0f64), 2.0f64 / (ssqg[j] / sig2 + rscale[j] * rscale[j]))
            j += 1usize
        }
        j = 0usize
        while j < q {
            ch[j * it + iter] = beta[j]
            j += 1usize
        }
        ch[q * it + iter] = sig2
        j = 0usize
        while j < ng {
            ch[(q + 1usize + j) * it + iter] = gg[j]
            j += 1usize
        }
        iter += 1usize
    }
    ret (ch, ok)
}

// Linear models with factors: compare() of a BFlinearModel (lmBF), anovaBF, generalTestBF and posterior() of their models.
//
// LmData holds the predictors: nv variables of n values each, column-major in x, in the order they first appear in the formula;
// kind 0 is a fixed factor, 1 a random factor (both coded 0..nlev - 1 in the factor's level order), 2 continuous. A term is a
// bit mask over the variables, its factors taken in variable order (a:b, not b:a). method is nWayAOV's: 0 "auto", 1 "simple",
// 2 "importance".
type LmData = struct { y: []const f64, x: []const f64, n: usize, nv: usize, kind: []const usize, nlev: []const usize }

// rscaleFixed, rscaleRandom and rscaleCont as numbers
type LmPrior = struct { fixed: f64, random: f64, cont: f64 }

fn nbits(m: u64) -> usize {
    var c = 0usize
    var v = m
    while v != 0u64 {
        if v & 1u64 != 0u64 { c += 1usize }
        v = v >> 1u64
    }
    ret c
}

fn has(m: u64, v: usize) -> bool { ret (m >> u64(v)) & 1u64 != 0u64 }

// terms() order: by the number of factors in a term, stable
fn sort_terms(a: *mem.Arena, t0: []const u64) -> ([]u64, err) {
    let (t, e) = mem.alloc[u64](a, t0.len)
    if e != ok { ret (t, e) }
    var i = 0usize
    while i < t0.len {
        let v = t0[i]
        var j = i
        while j > 0usize && nbits(t[j - 1usize]) > nbits(v) {
            t[j] = t[j - 1usize]
            j -= 1usize
        }
        t[j] = v
        i += 1usize
    }
    ret (t, ok)
}

// fixedFromRandomProjection(k): eigen(diag(k) - 1/k)$vectors[, 1:(k - 1)], the eigenvectors of the k - 1 unit eigenvalues in
// R's order (decreasing values: LAPACK's columns k - 1 down to 1), k x (k - 1) column-major
fn projection(a: *mem.Arena, k: usize) -> ([]f64, err) {
    let (c, e1) = mem.alloc[f64](a, k * k)
    let (w, e2) = mem.alloc[f64](a, k)
    let (z, e3) = mem.alloc[f64](a, k * k)
    let (s, e4) = mem.alloc[f64](a, k * (k - 1usize))
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (s, mem.Full) }
    let inv = 1.0f64 / f64(k)
    var i = 0usize
    while i < k * k {
        c[i] = 0.0f64 - inv
        i += 1usize
    }
    i = 0usize
    while i < k {
        c[i + i * k] = 1.0f64 - inv
        i += 1usize
    }
    let e = syevr.dsyevr_all(a, c, k, w, z)
    if e != ok { ret (s, e) }
    var j = 0usize
    while j + 1usize < k {
        i = 0usize
        while i < k {
            s[i + j * k] = z[i + (k - 1usize - j) * k]
            i += 1usize
        }
        j += 1usize
    }
    ret (s, ok)
}

// oneDesignMatrix of one variable: a fixed factor's indicators times its projection, a random factor's indicators, a continuous
// variable centred as nWayFormula's centerContinuousColumns centres it
fn var_block(a: *mem.Arena, d: *const LmData, v: usize) -> ([]f64, usize, err) {
    let n = d.n
    let col = d.x[v * n..v * n + n]
    let k = d.nlev[v]
    var m = 1usize
    if d.kind[v] == 0usize { m = k - 1usize }
    if d.kind[v] == 1usize { m = k }
    let (b, e) = mem.alloc[f64](a, n * m)
    if e != ok { ret (b, m, e) }
    var i = 0usize
    if d.kind[v] == 2usize {
        let mu = mean_of(col)
        while i < n {
            b[i] = col[i] - mu
            i += 1usize
        }
        ret (b, m, ok)
    }
    while i < n * m {
        b[i] = 0.0f64
        i += 1usize
    }
    if d.kind[v] == 1usize {
        i = 0usize
        while i < n {
            b[i + usize(col[i]) * n] = 1.0f64
            i += 1usize
        }
        ret (b, m, ok)
    }
    let (s, es) = projection(a, k)
    if es != ok { ret (b, m, es) }
    var j = 0usize
    while j < m {
        i = 0usize
        while i < n {
            b[i + j * n] = s[usize(col[i]) + j * k]
            i += 1usize
        }
        j += 1usize
    }
    ret (b, m, ok)
}

// fullDesignMatrix (each term the row-wise Kronecker product of its variables' blocks), createGMap and createRscales for terms
// already in terms() order: one g per factor term in order, one more shared by every continuous term
type Design = struct { x: []f64, p: usize, gmap: []usize, cont: []bool, rscale: []f64, ng: usize, tcol: []usize, ttype: []usize }

fn design(a: *mem.Arena, d: *const LmData, terms: []const u64, pri: LmPrior) -> (Design, err) {
    let n = d.n
    let nt = terms.len
    let (tcol, e1) = mem.alloc[usize](a, nt + 1usize)
    let (ttype, e2) = mem.alloc[usize](a, nt)
    var ds = Design { x: zero, p: 0usize, gmap: zero, cont: zero, rscale: zero, ng: 0usize, tcol: tcol, ttype: ttype }
    if e1 != ok || e2 != ok { ret (ds, mem.Full) }
    var p = 0usize
    var t = 0usize
    while t < nt {
        tcol[t] = p
        var m = 1usize
        var ty = 0usize
        var v = 0usize
        while v < d.nv {
            if has(terms[t], v) {
                if d.kind[v] == 0usize { m *= d.nlev[v] - 1usize }
                if d.kind[v] == 1usize {
                    m *= d.nlev[v]
                    if ty == 0usize { ty = 1usize }
                }
                if d.kind[v] == 2usize { ty = 2usize }
            }
            v += 1usize
        }
        ttype[t] = ty
        p += m
        t += 1usize
    }
    tcol[nt] = p
    let (x, e3) = mem.alloc[f64](a, n * p)
    let (gmap, e4) = mem.alloc[usize](a, p)
    let (cont, e5) = mem.alloc[bool](a, p)
    if e3 != ok || e4 != ok || e5 != ok { ret (ds, mem.Full) }
    t = 0usize
    while t < nt {
        var cur: []f64 = zero
        var mc = 0usize
        var v = 0usize
        while v < d.nv {
            if has(terms[t], v) {
                let (b, mb, eb) = var_block(a, d, v)
                if eb != ok { ret (ds, eb) }
                if mc == 0usize {
                    cur = b
                    mc = mb
                } else {
                    let (nx, en) = mem.alloc[f64](a, n * mc * mb)
                    if en != ok { ret (ds, en) }
                    var ci = 0usize
                    while ci < mc {
                        var vi = 0usize
                        while vi < mb {
                            var i = 0usize
                            while i < n {
                                nx[i + (ci * mb + vi) * n] = cur[i + ci * n] * b[i + vi * n]
                                i += 1usize
                            }
                            vi += 1usize
                        }
                        ci += 1usize
                    }
                    cur = nx
                    mc = mc * mb
                }
            }
            v += 1usize
        }
        var i = 0usize
        while i < n * mc {
            x[tcol[t] * n + i] = cur[i]
            i += 1usize
        }
        t += 1usize
    }
    var nfac = 0usize
    var ncont = 0usize
    t = 0usize
    while t < nt {
        if ttype[t] == 2usize {
            ncont = 1usize
        } else {
            nfac += 1usize
        }
        t += 1usize
    }
    let ng = nfac + ncont
    let (rscale, e6) = mem.alloc[f64](a, ng)
    if e6 != ok { ret (ds, e6) }
    var f = 0usize
    t = 0usize
    while t < nt {
        var gi = ng - 1usize
        if ttype[t] == 2usize {
            rscale[gi] = pri.cont
        } else {
            gi = f
            rscale[gi] = pri.fixed
            if ttype[t] == 1usize { rscale[gi] = pri.random }
            f += 1usize
        }
        var c = tcol[t]
        while c < tcol[t + 1usize] {
            gmap[c] = gi
            cont[c] = ttype[t] == 2usize
            c += 1usize
        }
        t += 1usize
    }
    ds.x = x
    ds.p = p
    ds.gmap = gmap
    ds.cont = cont
    ds.rscale = rscale
    ds.ng = ng
    ret (ds, ok)
}

// jzs_log_marginal_posterior_logg (jzs_Gauss_approx_aov.cpp) as gaussianApproxAOV and singleGBayesFactor set it up: X'X and
// X'y of the centred design, sumSq = var(y) (N - 1), priorX = crossprod of the raw continuous columns / N
type QCtx = struct { n: usize, p: usize, ng: usize, inc: usize, xtx: []f64, xty: []f64, prx: []f64, sumsq: f64, gmap: []const usize, counts: []f64, rscale: []const f64, gi: []f64, lf: []f64, vi: []f64, z: []f64, row: []f64, row2: []f64, gg: []f64, t1: []f64, t2: []f64, t3: []f64, t4: []f64, d1: []f64, d2: []f64, qb: []f64, limit: bool, shift: f64 }

fn q_prep(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, gmap: []const usize, rscale: []const f64, inc: usize) -> (QCtx, err) {
    let n = y.len
    let ng = rscale.len
    let (mats, e1) = mem.alloc[f64](a, 4usize * p * p + n * p)
    let (vec, e2) = mem.alloc[f64](a, 4usize * p + inc * inc + 10usize * ng + 1usize)
    var c = QCtx { n: n, p: p, ng: ng, inc: inc, xtx: zero, xty: zero, prx: zero, sumsq: 0.0f64, gmap: gmap, counts: zero, rscale: rscale, gi: zero, lf: zero, vi: zero, z: zero, row: zero, row2: zero, gg: zero, t1: zero, t2: zero, t3: zero, t4: zero, d1: zero, d2: zero, qb: zero, limit: true, shift: 0.0f64 }
    if e1 != ok || e2 != ok { ret (c, mem.Full) }
    let pp = p * p
    c.xtx = mats[0usize..pp]
    c.gi = mats[pp..2usize * pp]
    c.lf = mats[2usize * pp..3usize * pp]
    c.vi = mats[3usize * pp..4usize * pp]
    let cx = mats[4usize * pp..4usize * pp + n * p]
    c.xty = vec[0usize..p]
    c.z = vec[p..2usize * p]
    c.row = vec[2usize * p..3usize * p]
    c.row2 = vec[3usize * p..4usize * p]
    var at = 4usize * p
    c.prx = vec[at..at + inc * inc]
    at += inc * inc
    c.counts = vec[at..at + ng]
    c.gg = vec[at + ng..at + 2usize * ng]
    c.t1 = vec[at + 2usize * ng..at + 3usize * ng]
    c.t2 = vec[at + 3usize * ng..at + 4usize * ng]
    c.t3 = vec[at + 4usize * ng..at + 5usize * ng]
    c.t4 = vec[at + 5usize * ng..at + 6usize * ng]
    c.d1 = vec[at + 6usize * ng..at + 7usize * ng]
    c.d2 = vec[at + 7usize * ng..at + 8usize * ng]
    c.qb = vec[at + 8usize * ng..at + 8usize * ng + 1usize]
    let fn_ = f64(n)
    var i = 0usize
    var j = 0usize
    while j < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += x[j * n + i]
            i += 1usize
        }
        let m = s / fn_
        i = 0usize
        while i < n {
            cx[j * n + i] = x[j * n + i] - m
            i += 1usize
        }
        j += 1usize
    }
    let my = mean_of(y)
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += cx[j * n + i] * cx[k * n + i]
                i += 1usize
            }
            c.xtx[j + k * p] = s
            k += 1usize
        }
        var t = 0.0f64
        i = 0usize
        while i < n {
            t += (y[i] - my) * cx[j * n + i]
            i += 1usize
        }
        c.xty[j] = t
        j += 1usize
    }
    c.sumsq = var_of(y) * (fn_ - 1.0f64)
    j = 0usize
    while j < inc {
        var k = 0usize
        while k < inc {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += x[j * n + i] * x[k * n + i]
                i += 1usize
            }
            c.prx[j + k * inc] = s / fn_
            k += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < ng {
        c.counts[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < p {
        c.counts[gmap[j]] += 1.0f64
        j += 1usize
    }
    ret (c, ok)
}

// the log marginal posterior of q = log g (which 0, -Inf outside [-15, 15] when c.limit), its gradient into c.d1 (which 1),
// and also its second derivatives into c.d2 (which 2)
fn qg_eval(c: *QCtx, q: []const f64, which: usize) -> f64 {
    let p = c.p
    let ng = c.ng
    let inc = c.inc
    let gmap = c.gmap
    var i = 0usize
    var j = 0usize
    var k = 0usize
    while i < ng {
        c.gg[i] = math.exp[f64](q[i])
        i += 1usize
    }
    if which == 0usize && c.limit {
        i = 0usize
        while i < ng {
            if q[i] < 0.0f64 - 15.0f64 || q[i] > 15.0f64 { ret ninf() }
            i += 1usize
        }
    }
    i = 0usize
    while i < p * p {
        c.gi[i] = c.xtx[i]
        i += 1usize
    }
    var sumlogg = 0.0f64
    i = inc
    while i < p {
        sumlogg += q[gmap[i]]
        c.gi[i + i * p] += 1.0f64 / c.gg[gmap[i]]
        i += 1usize
    }
    i = 0usize
    while i < inc {
        sumlogg += q[gmap[i]]
        j = 0usize
        while j <= i {
            c.gi[i + j * p] += c.prx[i + j * inc] / c.gg[gmap[i]]
            j += 1usize
        }
        i += 1usize
    }
    let lf = c.lf
    chol_lower(c.gi, p, lf)
    var col = 0usize
    while col < p {
        i = 0usize
        while i < p {
            var v = 0.0f64
            if i == col { v = 1.0f64 }
            k = 0usize
            while k < i {
                v -= lf[i + k * p] * c.z[k]
                k += 1usize
            }
            c.z[i] = v / lf[i + i * p]
            i += 1usize
        }
        var r = p
        while r > 0usize {
            r -= 1usize
            var v = c.z[r]
            k = r + 1usize
            while k < p {
                v -= lf[k + r * p] * c.vi[k + col * p]
                k += 1usize
            }
            c.vi[r + col * p] = v / lf[r + r * p]
        }
        col += 1usize
    }
    i = 0usize
    while i < p {
        var v = 0.0f64
        k = 0usize
        while k < p {
            v += c.xty[k] * c.vi[k + i * p]
            k += 1usize
        }
        c.row[i] = v
        i += 1usize
    }
    var yxvxy = 0.0f64
    i = 0usize
    while i < p {
        yxvxy += c.row[i] * c.xty[i]
        i += 1usize
    }
    let fn_ = f64(c.n)
    if which == 0usize {
        var ldet = 0.0f64
        i = 0usize
        while i < p {
            ldet += 2.0f64 * math.log[f64](lf[i + i * p])
            i += 1usize
        }
        var sig = 0.0f64
        var sq_ = 0.0f64
        i = 0usize
        while i < ng {
            sig += dinvgamma1(c.gg[i], 0.5f64, c.rscale[i] * c.rscale[i] / 2.0f64)
            sq_ += q[i]
            i += 1usize
        }
        ret 0.0f64 - 0.5f64 * sumlogg - 0.5f64 * ldet - 0.5f64 * (fn_ - 1.0f64) * dist.log1p(0.0f64 - yxvxy / c.sumsq) + sig + sq_
    }
    i = 0usize
    while i < ng {
        c.t1[i] = 0.0f64
        c.t2[i] = 0.0f64
        c.t3[i] = 0.0f64
        c.t4[i] = 0.0f64
        i += 1usize
    }
    let rest = c.sumsq - yxvxy
    i = 0usize
    while i < p {
        let gv = c.gg[gmap[i]]
        c.t1[gmap[i]] += c.vi[i + i * p] / gv
        c.t2[gmap[i]] += c.row[i] * c.row[i] / gv / rest
        i += 1usize
    }
    i = 0usize
    while i < ng {
        let gv = c.gg[i]
        let b = c.rscale[i] * c.rscale[i] / 2.0f64
        let dd = gv * ((0.0f64 - 1.5f64) / gv + b / (gv * gv))
        c.d1[i] = 0.0f64 - 0.5f64 * c.counts[i] + 0.5f64 * c.t1[i] + 0.5f64 * (fn_ - 1.0f64) * c.t2[i] + dd + 1.0f64
        i += 1usize
    }
    if which < 2usize { ret 0.0f64 }
    i = 0usize
    while i < p {
        var v = 0.0f64
        var v2 = 0.0f64
        k = 0usize
        while k < p {
            v += c.row[k] * c.vi[k + i * p]
            v2 += c.vi[i + k * p] * c.vi[i + k * p]
            k += 1usize
        }
        c.row2[i] = v
        let gv = c.gg[gmap[i]]
        c.t3[gmap[i]] += v2 / (gv * gv)
        c.t4[gmap[i]] += c.row[i] * v / (gv * gv * rest)
        i += 1usize
    }
    i = 0usize
    while i < ng {
        let gv = c.gg[i]
        let b = c.rscale[i] * c.rscale[i] / 2.0f64
        let dd = gv * gv * (1.5f64 / (gv * gv) - 2.0f64 * b / (gv * gv * gv))
        c.d2[i] = c.d1[i] + 0.5f64 * c.counts[i] - 1.0f64 + dd + 0.5f64 * (c.t3[i] - 2.0f64 * c.t1[i]) + 0.5f64 * (fn_ - 1.0f64) * (c.t2[i] * c.t2[i] - 2.0f64 * c.t2[i] + 2.0f64 * c.t4[i])
        i += 1usize
    }
    ret 0.0f64
}

// optim(fnscale = -1) minimises -Qg with gradient -dQg
fn qg_neg(c: *QCtx, q: []const f64) -> f64 { ret 0.0f64 - qg_eval(c, q, 0usize) }
fn qg_grad(c: *QCtx, q: []const f64, out: []f64) {
    let _ = qg_eval(c, q, 1usize)
    var i = 0usize
    while i < c.ng {
        out[i] = 0.0f64 - c.d1[i]
        i += 1usize
    }
}

fn reltol_optim() -> f64 { ret 1.4901161193847656e-8f64 }

// gaussianApproxAOV: optim BFGS from q = 0, then the normal approximation's sd from the diagonal second derivatives
fn gauss_approx(a: *mem.Arena, c: *QCtx, mu: []f64, sig: []f64) {
    c.limit = true
    var i = 0usize
    while i < c.ng {
        mu[i] = 0.0f64
        i += 1usize
    }
    let _ = rbfgs.vmmin[QCtx](a, c, qg_neg, qg_grad, mu, reltol_optim(), 100usize)
    let _ = qg_eval(c, mu, 2usize)
    i = 0usize
    while i < c.ng {
        sig[i] = math.sqrt[f64](0.0f64 - 1.0f64 / c.d2[i])
        i += 1usize
    }
}

fn single_g_f(c: *QCtx, g: f64) -> f64 {
    c.qb[0usize] = math.log[f64](g)
    ret math.exp[f64](qg_eval(c, c.qb, 0usize) - math.log[f64](g) - c.shift)
}

// singleGBayesFactor: optim BFGS on Qg for the mode, then integrate exp(Qg(log g) - log g - const) over (0, Inf)
fn single_g_bf(a: *mem.Arena, c: *QCtx) -> (f64, err) {
    c.limit = true
    c.qb[0usize] = 0.0f64
    let fmin = rbfgs.vmmin[QCtx](a, c, qg_neg, qg_grad, c.qb, reltol_optim(), 100usize)
    c.shift = (0.0f64 - fmin) - c.qb[0usize]
    c.limit = false
    let (r, e) = integrate[QCtx](a, c, single_g_f, 0.0f64, pinf())
    if e != ok { ret (0.0f64, e) }
    ret (math.log[f64](r.result) + c.shift, ok)
}

// propErrorEst: logSummaryStats' Welford mean and variance on log-represented values, NaN draws dropped
fn prop_err(a: *mem.Arena, x0: []const f64) -> f64 {
    let x = drop_nan(a, x0)
    if x.len < 2usize { ret 0.0f64 / 0.0f64 }
    var m = Lr { m: x[0usize], s: 1i64 }
    var s = Lr { m: ninf(), s: 0i64 }
    var i = 1usize
    while i < x.len {
        let old = m
        let tx = Lr { m: x[i], s: 1i64 }
        let d = lr_sub(tx, old)
        m = lr_add(old, Lr { m: d.m - math.log[f64](f64(i + 1usize)), s: d.s })
        let e = lr_sub(tx, m)
        if d.s != 0i64 && e.s != 0i64 { s = lr_add(s, Lr { m: d.m + e.m, s: d.s * e.s }) }
        i += 1usize
    }
    let lv = s.m - math.log[f64](f64(x.len) - 1.0f64)
    ret math.exp[f64]((lv - math.log[f64](f64(x.len))) / 2.0f64 - m.m)
}

fn drop_nan(a: *mem.Arena, x: []const f64) -> []const f64 {
    var k = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] == x[i] { k += 1usize }
        i += 1usize
    }
    if k == x.len { ret x }
    let (y, e) = mem.alloc[f64](a, k)
    if e != ok { ret x[0usize..0usize] }
    k = 0usize
    i = 0usize
    while i < x.len {
        if x[i] == x[i] {
            y[k] = x[i]
            k += 1usize
        }
        i += 1usize
    }
    ret y
}

// the design with its continuous columns moved first (nWayAOV's order(!continuous)); spos[k] is original column k's position
fn sort_cont(a: *mem.Arena, ds: *const Design, n: usize, lead: usize) -> ([]f64, []usize, []usize, usize, err) {
    let p = ds.p
    let (xs, e1) = mem.alloc[f64](a, n * (p + lead))
    let (gm, e2) = mem.alloc[usize](a, p)
    let (spos, e3) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (xs, gm, spos, 0usize, mem.Full) }
    var i = 0usize
    while i < n * lead {
        xs[i] = 1.0f64
        i += 1usize
    }
    var at = 0usize
    var pass = 0usize
    while pass < 2usize {
        var k = 0usize
        while k < p {
            if ds.cont[k] == (pass == 0usize) {
                spos[k] = at
                gm[at] = ds.gmap[k]
                i = 0usize
                while i < n {
                    xs[(at + lead) * n + i] = ds.x[k * n + i]
                    i += 1usize
                }
                at += 1usize
            }
            k += 1usize
        }
        pass += 1usize
    }
    var inc = 0usize
    i = 0usize
    while i < p {
        if ds.cont[i] { inc += 1usize }
        i += 1usize
    }
    ret (xs, gm, spos, inc, ok)
}

// nWayAOV(y, X, gMap, rscale, iterations, method)$bf for a design with factors: singleGBayesFactor for one g and no continuous
// column, otherwise doNwaySampling, whose "auto" runs 100 draws of each sampler and keeps the one with the smaller error
fn nway_bf(a: *mem.Arena, g: *rng.Rng, y: []const f64, ds: *const Design, method: usize, it: usize) -> (f64, err) {
    let n = y.len
    let p = ds.p
    let ng = ds.ng
    let (xs, gm, spos, inc, e0) = sort_cont(a, ds, n, 0usize)
    if e0 != ok { ret (0.0f64, e0) }
    if ng == 1usize && inc == 0usize {
        if p == 1usize { ret (0.0f64, mem.Invalid) }
        let (qc, eq) = q_prep(a, y, xs, p, gm, ds.rscale, inc)
        if eq != ok { ret (0.0f64, eq) }
        var qv = qc
        let (v, ev) = single_g_bf(a, &qv)
        ret (v, ev)
    }
    let (c0, e1) = nw_prep(a, y, xs, p, gm, ds.rscale, inc)
    let (mv, e2) = mem.alloc[f64](a, 2usize * ng + 100usize)
    if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var c = c0
    let mu = mv[0usize..ng]
    let sig = mv[ng..2usize * ng]
    let pre = mv[2usize * ng..2usize * ng + 100usize]
    var m = method
    if p == 1usize { m = 1usize }
    if m != 1usize {
        let (qc, eq) = q_prep(a, y, xs, p, gm, ds.rscale, inc)
        if eq != ok { ret (0.0f64, eq) }
        var qv = qc
        gauss_approx(a, &qv, mu, sig)
    }
    if m == 0usize {
        nw_draw(g, &c, false, mu, sig, pre)
        let serr = prop_err(a, pre)
        nw_draw(g, &c, true, mu, sig, pre)
        let ierr = prop_err(a, pre)
        m = 2usize
        if ierr != ierr || ierr > serr { m = 1usize }
    }
    let (logs, e3) = mem.alloc[f64](a, it)
    if e3 != ok { ret (0.0f64, e3) }
    nw_draw(g, &c, m == 2usize, mu, sig, logs)
    ret (log_mean_exp(drop_nan(a, logs)), ok)
}

// lmBF(formula, data)'s Bayes factor against the intercept-only model, by compare()'s dispatch: linearReg.R2stat for continuous
// main effects only, the t test or oneWayAOV.Fstat for one factor with two levels or balanced, nWayFormula otherwise
fn lm_bf(a: *mem.Arena, g: *rng.Rng, d: *const LmData, terms: []const u64, pri: LmPrior, method: usize, it: usize) -> (f64, err) {
    var vars = 0u64
    var i = 0usize
    while i < terms.len {
        vars = vars | terms[i]
        i += 1usize
    }
    if vars == 0u64 { ret (0.0f64, ok) }
    var allc = true
    var noc = true
    var v0 = d.nv
    var v = 0usize
    while v < d.nv {
        if has(vars, v) {
            if v0 == d.nv { v0 = v }
            if d.kind[v] == 2usize {
                noc = false
            } else {
                allc = false
            }
        }
        v += 1usize
    }
    if allc {
        let (mask, em) = mem.alloc[bool](a, d.nv)
        if em != ok { ret (0.0f64, em) }
        v = 0usize
        while v < d.nv {
            mask[v] = has(vars, v)
            v += 1usize
        }
        let (rv, re) = regression_bf(a, d.y, d.x, d.nv, mask, pri.cont)
        ret (rv, re)
    }
    if noc && nbits(vars) == 1usize {
        let k = d.nlev[v0]
        let (codes, ec) = mem.alloc[usize](a, d.n)
        let (cnt, en) = mem.alloc[usize](a, k)
        if ec != ok || en != ok { ret (0.0f64, mem.Full) }
        i = 0usize
        while i < k {
            cnt[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < d.n {
            codes[i] = usize(d.x[v0 * d.n + i])
            cnt[codes[i]] += 1usize
            i += 1usize
        }
        var bal = true
        i = 1usize
        while i < k {
            if cnt[i] != cnt[0usize] { bal = false }
            i += 1usize
        }
        var rs = pri.fixed
        if d.kind[v0] == 1usize { rs = pri.random }
        if k == 2usize || bal {
            let (fv, fe) = factor_bf(a, d.y, codes, k, rs)
            ret (fv, fe)
        }
    }
    let (st, es) = sort_terms(a, terms)
    if es != ok { ret (0.0f64, es) }
    let (ds, ed) = design(a, d, st, pri)
    if ed != ok { ret (0.0f64, ed) }
    let (bv, be) = nway_bf(a, g, d.y, &ds, method, it)
    ret (bv, be)
}

// monotoneBoolean(m): every monotone Boolean function of m arguments as a bit mask over its 2^m positions, in the package's order
fn monotone(a: *mem.Arena, m: usize) -> ([]u64, usize, err) {
    let (b0, e1) = mem.alloc[u64](a, 8192usize)
    let (b1, e2) = mem.alloc[u64](a, 8192usize)
    if e1 != ok || e2 != ok || m > 5usize { ret (b0, 0usize, mem.Invalid) }
    var cur = b0
    var nxt = b1
    cur[0usize] = 0u64
    cur[1usize] = 1u64
    var cnt = 2usize
    var half = 1u64
    var lev = 0usize
    while lev < m {
        var k = 0usize
        var i = 0usize
        while i < cnt {
            var j = 0usize
            while j < cnt {
                if (cur[i] | cur[j]) == cur[j] {
                    nxt[k] = cur[i] | (cur[j] << half)
                    k += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        let t = cur
        cur = nxt
        nxt = t
        cnt = k
        half = half * 2u64
        lev += 1usize
    }
    ret (cur, cnt, ok)
}

// the "withmain" models over nf factors, each a bit set over term numbers t = 1..2^nf - 1 (term t holds factor i when bit i of
// t is set): enumerateAnovaModelsWithMain, or (general) possibleRestrictionsWithMainGeneral's submodels of the terms in full
fn withmain(a: *mem.Arena, nf: usize, full: u64, general: bool) -> ([]u64, usize, err) {
    let (mb, cnt, e) = monotone(a, nf)
    let (out, e2) = mem.alloc[u64](a, cnt + 1usize)
    if e != ok || e2 != ok { ret (out, 0usize, mem.Invalid) }
    let l = (1usize << nf) - 1usize
    var k = 0usize
    var found = false
    var r = 2usize
    while r < cnt {
        var model = 0u64
        var c = 0usize
        while c < l {
            if (mb[r] >> u64(c)) & 1u64 != 0u64 { model = model | (1u64 << u64(l - c)) }
            c += 1usize
        }
        if !general || (model & full) == model {
            out[k] = model
            if model == full { found = true }
            k += 1usize
        }
        r += 1usize
    }
    if general && !found {
        out[k] = full
        k += 1usize
    }
    ret (out, k, ok)
}

// a model's terms as variable masks, in increasing term number, then (random) one main term per variable in extra
fn model_terms(a: *mem.Arena, model: u64, fv: []const usize, extra: u64, nv: usize) -> ([]u64, err) {
    let (t, e) = mem.alloc[u64](a, 64usize + nv)
    if e != ok { ret (t, e) }
    var k = 0usize
    var b = 1usize
    while b < 64usize {
        if (model >> u64(b)) & 1u64 != 0u64 {
            var mask = 0u64
            var i = 0usize
            while i < fv.len {
                if (b >> i) & 1usize != 0usize { mask = mask | (1u64 << u64(fv[i])) }
                i += 1usize
            }
            t[k] = mask
            k += 1usize
        }
        b += 1usize
    }
    var v = 0usize
    while v < nv {
        if has(extra, v) {
            t[k] = 1u64 << u64(v)
            k += 1usize
        }
        v += 1usize
    }
    ret (t[0usize..k], ok)
}

// anovaBF's models: "withmain" over the fixed factors, each with every random factor added, as term lists; the last is the
// random-only denominator when there are random factors
fn anova_models(a: *mem.Arena, d: *const LmData) -> ([]u64, usize, []usize, u64, err) {
    let (fv, e1) = mem.alloc[usize](a, d.nv)
    if e1 != ok { ret (zero, 0usize, fv, 0u64, e1) }
    var nf = 0usize
    var rnd = 0u64
    var v = 0usize
    while v < d.nv {
        if d.kind[v] == 0usize {
            fv[nf] = v
            nf += 1usize
        }
        if d.kind[v] == 1usize { rnd = rnd | (1u64 << u64(v)) }
        v += 1usize
    }
    let (ms, k, e2) = withmain(a, nf, 0u64, false)
    ret (ms, k, fv[0usize..nf], rnd, e2)
}

// anovaBF(formula, data, whichRandom, iterations, method)$bf: out gets one log BF per model in the package's row order (against
// the random-only model when there are random factors); answers the number of rows
fn anova_bf(a: *mem.Arena, g: *rng.Rng, d: *const LmData, pri: LmPrior, method: usize, it: usize, out: []f64) -> (usize, err) {
    let (ms, k, fv, rnd, e) = anova_models(a, d)
    if e != ok { ret (0usize, e) }
    var i = 0usize
    while i < k {
        let (t, et) = model_terms(a, ms[i], fv, rnd, d.nv)
        if et != ok { ret (0usize, et) }
        let (b, eb) = lm_bf(a, g, d, t, pri, method, it)
        if eb != ok { ret (0usize, eb) }
        out[i] = b
        i += 1usize
    }
    if rnd != 0u64 {
        let (t, et) = model_terms(a, 0u64, fv, rnd, d.nv)
        if et != ok { ret (0usize, et) }
        let (b, eb) = lm_bf(a, g, d, t, pri, method, it)
        if eb != ok { ret (0usize, eb) }
        i = 0usize
        while i < k {
            out[i] = out[i] - b
            i += 1usize
        }
    }
    ret (k, ok)
}

// generalTestBF's models ("withmain", no neverExclude) for the formula's terms
fn general_models(a: *mem.Arena, d: *const LmData, terms: []const u64) -> ([]u64, usize, []usize, err) {
    let (fv, e1) = mem.alloc[usize](a, d.nv)
    if e1 != ok { ret (zero, 0usize, fv, e1) }
    var vars = 0u64
    var i = 0usize
    while i < terms.len {
        vars = vars | terms[i]
        i += 1usize
    }
    var nf = 0usize
    var v = 0usize
    while v < d.nv {
        if has(vars, v) {
            fv[nf] = v
            nf += 1usize
        }
        v += 1usize
    }
    var full = 0u64
    i = 0usize
    while i < terms.len {
        var t = 0usize
        var f = 0usize
        while f < nf {
            if has(terms[i], fv[f]) { t += 1usize << f }
            f += 1usize
        }
        full = full | (1u64 << u64(t))
        i += 1usize
    }
    if terms.len == 1usize {
        let (one, e2) = mem.alloc[u64](a, 1usize)
        if e2 != ok { ret (one, 0usize, fv, e2) }
        one[0usize] = full
        ret (one, 1usize, fv[0usize..nf], ok)
    }
    let (ms, k, e3) = withmain(a, nf, full, true)
    ret (ms, k, fv[0usize..nf], e3)
}

// generalTestBF(formula, data, whichRandom, iterations, method)$bf, one log BF per model into out; answers the number of rows
fn general_bf(a: *mem.Arena, g: *rng.Rng, d: *const LmData, terms: []const u64, pri: LmPrior, method: usize, it: usize, out: []f64) -> (usize, err) {
    let (ms, k, fv, e) = general_models(a, d, terms)
    if e != ok { ret (0usize, e) }
    var i = 0usize
    while i < k {
        let (t, et) = model_terms(a, ms[i], fv, 0u64, d.nv)
        if et != ok { ret (0usize, et) }
        let (b, eb) = lm_bf(a, g, d, t, pri, method, it)
        if eb != ok { ret (0usize, eb) }
        out[i] = b
        i += 1usize
    }
    ret (k, ok)
}

// the terms of anovaBF's model number idx (0-based)
fn anova_model(a: *mem.Arena, d: *const LmData, idx: usize) -> ([]u64, err) {
    let (ms, k, fv, rnd, e) = anova_models(a, d)
    if e != ok || idx >= k { ret (zero, mem.Invalid) }
    let (t, et) = model_terms(a, ms[idx], fv, rnd, d.nv)
    ret (t, et)
}

fn term_fixed(d: *const LmData, term: u64) -> bool {
    var v = 0usize
    while v < d.nv {
        if has(term, v) && d.kind[v] == 0usize { ret true }
        v += 1usize
    }
    ret false
}

// a term's projection from reduced to full effects (design.projection.intList): the Kronecker product over its variables of
// the fixed factors' projections, identities for random factors and 1 for continuous variables; rows x cols column-major
fn term_projection(a: *mem.Arena, d: *const LmData, term: u64) -> ([]f64, usize, usize, err) {
    let (one, e0) = mem.alloc[f64](a, 1usize)
    if e0 != ok { ret (one, 0usize, 0usize, e0) }
    one[0usize] = 1.0f64
    var cur = one
    var rows = 1usize
    var cols = 1usize
    var v = d.nv
    while v > 0usize {
        v -= 1usize
        if has(term, v) && d.kind[v] != 2usize {
            let k = d.nlev[v]
            var sv: []f64 = zero
            var sc = k
            if d.kind[v] == 0usize {
                let (s, es) = projection(a, k)
                if es != ok { ret (s, 0usize, 0usize, es) }
                sv = s
                sc = k - 1usize
            } else {
                let (s, es) = mem.alloc[f64](a, k * k)
                if es != ok { ret (s, 0usize, 0usize, es) }
                var i = 0usize
                while i < k * k {
                    s[i] = 0.0f64
                    i += 1usize
                }
                i = 0usize
                while i < k {
                    s[i + i * k] = 1.0f64
                    i += 1usize
                }
                sv = s
            }
            let nr = k * rows
            let ncl = sc * cols
            let (nx, en) = mem.alloc[f64](a, nr * ncl)
            if en != ok { ret (nx, 0usize, 0usize, en) }
            var c1 = 0usize
            while c1 < sc {
                var r1 = 0usize
                while r1 < k {
                    var c2 = 0usize
                    while c2 < cols {
                        var r2 = 0usize
                        while r2 < rows {
                            nx[(r1 * rows + r2) + (c1 * cols + c2) * nr] = sv[r1 + c1 * k] * cur[r2 + c2 * rows]
                            r2 += 1usize
                        }
                        c2 += 1usize
                    }
                    r1 += 1usize
                }
                c1 += 1usize
            }
            cur = nx
            rows = nr
            cols = ncl
        }
    }
    ret (cur, rows, cols, ok)
}

// posterior() of an lmBF model (also a row of anovaBF or generalTestBF): linearReg.Gibbs for continuous main effects only,
// otherwise nWayFormula(posterior = TRUE): jzs_Gibbs on the design with its continuous columns first, the columns put back, then
// makeChainNeater's unreduce of every term with a fixed factor. Chains it x ncol column-major: mu, effects, sig2, then each g.
fn lm_post(a: *mem.Arena, g: *rng.Rng, d: *const LmData, terms: []const u64, pri: LmPrior, it: usize) -> ([]f64, usize, err) {
    let n = d.n
    var vars = 0u64
    var i = 0usize
    while i < terms.len {
        vars = vars | terms[i]
        i += 1usize
    }
    var allc = true
    var anyfix = false
    var v = 0usize
    while v < d.nv {
        if has(vars, v) {
            if d.kind[v] != 2usize { allc = false }
            if d.kind[v] == 0usize { anyfix = true }
        }
        v += 1usize
    }
    if allc {
        let p = nbits(vars)
        let (cov, ec) = mem.alloc[f64](a, n * p)
        if ec != ok { ret (cov, 0usize, ec) }
        var k = 0usize
        v = 0usize
        while v < d.nv {
            if has(vars, v) {
                i = 0usize
                while i < n {
                    cov[k * n + i] = d.x[v * n + i]
                    i += 1usize
                }
                k += 1usize
            }
            v += 1usize
        }
        let (ch, e) = linreg_post(a, g, d.y, cov, p, pri.cont, it)
        ret (ch, p + 3usize, e)
    }
    let (st, es) = sort_terms(a, terms)
    if es != ok { ret (zero, 0usize, es) }
    let (ds, ed) = design(a, d, st, pri)
    if ed != ok { ret (zero, 0usize, ed) }
    let p = ds.p
    let ng = ds.ng
    let (xs, gm, spos, inc, e0) = sort_cont(a, &ds, n, 1usize)
    if e0 != ok { ret (xs, 0usize, e0) }
    let (ch, eg) = jzs_gibbs(a, g, d.y, xs, p + 1usize, gm, ds.rscale, inc, it)
    if eg != ok { ret (ch, 0usize, eg) }
    var width = 0usize
    var t = 0usize
    while t < st.len {
        var w = ds.tcol[t + 1usize] - ds.tcol[t]
        if anyfix && term_fixed(d, st[t]) {
            let (s, rows, cols, ep) = term_projection(a, d, st[t])
            if ep != ok { ret (s, 0usize, ep) }
            w = rows
        }
        width += w
        t += 1usize
    }
    let ncol = width + 2usize + ng
    let (out, eo) = mem.alloc[f64](a, it * ncol)
    if eo != ok { ret (out, 0usize, eo) }
    i = 0usize
    while i < it {
        out[i] = ch[i]
        i += 1usize
    }
    var oc = 1usize
    t = 0usize
    while t < st.len {
        let c0 = ds.tcol[t]
        let m = ds.tcol[t + 1usize] - c0
        if anyfix && term_fixed(d, st[t]) {
            let (s, rows, cols, ep) = term_projection(a, d, st[t])
            if ep != ok { ret (s, 0usize, ep) }
            if cols != m { ret (s, 0usize, mem.Invalid) }
            var r = 0usize
            while r < rows {
                i = 0usize
                while i < it {
                    var acc = 0.0f64
                    var c = 0usize
                    while c < m {
                        acc += s[r + c * rows] * ch[(1usize + spos[c0 + c]) * it + i]
                        c += 1usize
                    }
                    out[(oc + r) * it + i] = acc
                    i += 1usize
                }
                r += 1usize
            }
            oc += rows
        } else {
            var c = 0usize
            while c < m {
                i = 0usize
                while i < it {
                    out[(oc + c) * it + i] = ch[(1usize + spos[c0 + c]) * it + i]
                    i += 1usize
                }
                c += 1usize
            }
            oc += m
        }
        t += 1usize
    }
    var c = 0usize
    while c < 1usize + ng {
        i = 0usize
        while i < it {
            out[(oc + c) * it + i] = ch[(p + 1usize + c) * it + i]
            i += 1usize
        }
        c += 1usize
    }
    ret (out, ncol, ok)
}
