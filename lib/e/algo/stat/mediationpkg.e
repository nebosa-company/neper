// R mediation::mediate for a linear mediator model and a linear outcome model without a treatment-mediator interaction, the quasi-Bayesian simulation (boot = FALSE): the coefficients of both models are drawn from
// their normal approximation with mvtnorm::rmvnorm (the mediator model first, then the outcome model, from one stream), and for a linear outcome the average causal mediation effect of every draw is the product
// of the treatment coefficient of the mediator model and the mediator coefficient of the outcome model (the simulated mediator errors cancel in the difference), the direct effect the outcome model's treatment
// coefficient. Summaries as mediate: means (the median for the proportion mediated), percentile intervals and the simulation p value.
//
// Not here: interactions, other families, factors, bootstrap, mixed models, sensitivity analysis.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.arm as ar
use e.algo.stat.armglm as gl
use e.algo.stat.mvtnorm as mv
use e.math
use e.math.dist as dist
use e.mem

fn cmp(ctx: *u8, a: f64, b: f64) -> i32 {
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// the type-7 quantile (R's default) of the sorted vector s at probability p
fn quant7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let h = f64(n - 1usize) * p
    let lo = math.floor[f64](h)
    let k = usize(lo)
    if k + 1usize >= n { ret s[n - 1usize] }
    ret s[k] + (h - lo) * (s[k + 1usize] - s[k])
}

fn sort_in_place(x: []f64) {
    var i = 1usize
    while i < x.len {
        let v = x[i]
        var j = i
        while j > 0usize && x[j - 1usize] > v {
            x[j] = x[j - 1usize]
            j -= 1usize
        }
        x[j] = v
        i += 1usize
    }
}

fn pval(x: []const f64, xhat: f64) -> f64 {
    if xhat == 0.0f64 { ret 1.0f64 }
    var pos = 0.0f64
    var neg = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] > 0.0f64 { pos += 1.0f64 }
        if x[i] < 0.0f64 { neg += 1.0f64 }
        i += 1usize
    }
    var o = 2.0f64 * math.min[f64](pos, neg) / f64(x.len)
    if o > 1.0f64 { o = 1.0f64 }
    ret o
}

// mediate(model.m, model.y, treat, mediator, sims, conf.level) under the seed: mbeta, mcov (pm by pm row-major) of the mediator model with the treatment at index tm; ybeta, ycov of the outcome model with
// the treatment at index ty and the mediator at index my. out, per quantity in the order ACME (d.avg), ADE (z.avg), total effect (tau.coef), proportion mediated (n.avg): the estimate, the lower and upper limits and
// the p value (16 values)
fn mediate_lm(a: *mem.Arena, g: *rng.Rng, mbeta: []const f64, mcov: []const f64, pm: usize, tm: usize, ybeta: []const f64, ycov: []const f64, py: usize, ty: usize, my: usize, sims: usize, conf: f64, out: []f64) -> err {
    let (mdraw, e1) = mv.rmvnorm(a, g, sims, mbeta, mcov, pm, 0u8)
    if e1 != ok { ret e1 }
    let (ydraw, e2) = mv.rmvnorm(a, g, sims, ybeta, ycov, py, 0u8)
    if e2 != ok { ret e2 }
    let (d, e3) = mem.alloc[f64](a, sims)
    let (z, e4) = mem.alloc[f64](a, sims)
    let (tau, e5) = mem.alloc[f64](a, sims)
    let (nu, e6) = mem.alloc[f64](a, sims)
    let (srt, e7) = mem.alloc[f64](a, sims)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var j = 0usize
    while j < sims {
        d[j] = mdraw[j * pm + tm] * ydraw[j * py + my]
        z[j] = ydraw[j * py + ty]
        tau[j] = d[j] + z[j]
        nu[j] = d[j] / tau[j]
        j += 1usize
    }
    let lo = (1.0f64 - conf) / 2.0f64
    let hi = 1.0f64 - lo
    var q = 0usize
    while q < 4usize {
        var v = d
        if q == 1usize { v = z }
        if q == 2usize { v = tau }
        if q == 3usize { v = nu }
        var m = 0.0f64
        j = 0usize
        while j < sims {
            m += v[j]
            srt[j] = v[j]
            j += 1usize
        }
        m = m / f64(sims)
        sort_in_place(srt)
        var est = m
        if q == 3usize {
            // the median of the proportion mediated
            let h = quant7(srt, 0.5f64)
            est = h
        }
        out[q * 4usize] = est
        out[q * 4usize + 1usize] = quant7(srt, lo)
        out[q * 4usize + 2usize] = quant7(srt, hi)
        out[q * 4usize + 3usize] = pval(v, est)
        q += 1usize
    }
    ret ok
}

// ---- general mediate: any mediator model (gaussian, binomial, poisson) and outcome model (identity, logit, probit, log link), with treatment-mediator interaction and covariates ----
// A model's design is described by a base matrix (n by q, row-major: intercept, covariates) and one entry per design column: which base column, whether it is multiplied by the treatment, and for
// an outcome model whether it is multiplied by the mediator. cols holds step entries per column (2: base, treat; 3: base, treat, mediator).

type Spec = struct { base: []const f64, n: usize, q: usize, cols: []const usize, step: usize, p: usize, fam: usize, link: usize, resp: []const f64, tr: []const f64, mobs: []const f64 }

fn design(s: *const Spec, tv: []const f64, mvec: []const f64, out: []f64) {
    var i = 0usize
    while i < s.n {
        var c = 0usize
        while c < s.p {
            var v = s.base[i * s.q + s.cols[c * s.step]]
            if s.cols[c * s.step + 1usize] == 1usize { v = v * tv[i] }
            if s.step == 3usize && s.cols[c * s.step + 2usize] == 1usize { v = v * mvec[i] }
            out[i * s.p + c] = v
            c += 1usize
        }
        i += 1usize
    }
}

fn filled(a: *mem.Arena, n: usize, v: f64) -> ([]f64, err) {
    let (x, e) = mem.alloc[f64](a, n)
    if e != ok { ret (x, e) }
    var i = 0usize
    while i < n {
        x[i] = v
        i += 1usize
    }
    ret (x, ok)
}

fn dot_row(x: []const f64, at: usize, b: []const f64, p: usize) -> f64 {
    var s = 0.0f64
    var c = 0usize
    while c < p {
        s += x[at + c] * b[c]
        c += 1usize
    }
    ret s
}

// the vcov of a fit (rows idx, 1-based, of the observed design; idx empty means every row): beta, cov and sigma (square root of the residual variance for the gaussian family, of the dispersion otherwise)
fn fit_model(a: *mem.Arena, s: *const Spec, xobs: []const f64, idx: []const i64, beta: []f64, cov: []f64) -> (f64, err) {
    let n = s.n
    let p = s.p
    let (xr, e1) = mem.alloc[f64](a, n * p)
    let (yr, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    var i = 0usize
    while i < n {
        var r = i
        if idx.len == n { r = usize(idx[i] - 1i64) }
        var c = 0usize
        while c < p {
            xr[i * p + c] = xobs[r * p + c]
            c += 1usize
        }
        yr[i] = s.resp[r]
        i += 1usize
    }
    var sigma = 0.0f64
    if s.fam == 0usize {
        let (res, e3) = mem.alloc[f64](a, n)
        if e3 != ok { ret (0.0f64, e3) }
        let (rss, e4) = ar.lm_summary(a, xr, yr, n, p, beta, cov, res)
        if e4 != ok { ret (0.0f64, e4) }
        let s2 = rss / f64(n - p)
        sigma = math.sqrt[f64](s2)
        i = 0usize
        while i < p * p {
            cov[i] = cov[i] * s2
            i += 1usize
        }
    } else {
        let (info, e5) = mem.alloc[f64](a, 5usize)
        if e5 != ok { ret (0.0f64, e5) }
        var none: []const f64 = zero
        let it = gl.glm_fit_gen(a, xr, yr, n, p, s.fam, s.link, none, none, true, beta, cov, info)
        if it == 0usize { ret (0.0f64, mem.Full) }
        sigma = math.sqrt[f64](info[0usize])
        i = 0usize
        while i < p * p {
            cov[i] = cov[i] * info[0usize]
            i += 1usize
        }
    }
    ret (sigma, ok)
}

// R's quantile (type 7): index 1 + (n - 1) p, then (1 - h) x[lo] + h x[hi]
fn quant_r(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let index = 1.0f64 + f64(n - 1usize) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    let ql = s[usize(lo) - 1usize]
    let qh = s[usize(hi) - 1usize]
    var q = ql
    if index > lo && qh != ql {
        let h = index - lo
        q = (1.0f64 - h) * ql + h * qh
    }
    ret q
}

// round to nearest, ties to even
fn rint_even(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    if f - 2.0f64 * math.floor[f64](f / 2.0f64) == 0.0f64 { ret f }
    ret f + 1.0f64
}

// the value hi + lo (a double-double) rounded to the 64-bit mantissa of an x87 long double
fn ld_round(hi: f64, lo: f64) -> (f64, f64) {
    if lo == 0.0f64 { ret (hi, 0.0f64) }
    let bits = mem.bitcast[u64](hi)
    var be = i64((bits >> 52u64) & 2047u64)
    // a power of two with a tail of the opposite sign lies in the binade below
    if (bits & 4503599627370495u64) == 0u64 && ((hi > 0.0f64 && lo < 0.0f64) || (hi < 0.0f64 && lo > 0.0f64)) { be -= 1i64 }
    if be < 100i64 { ret (hi, lo) }
    let u = mem.bitcast[f64](u64(be - 63i64) << 52u64)
    let l2 = rint_even(lo / u) * u
    let t = hi + l2
    ret (t, l2 - (t - hi))
}

// R sums in long double (sum, mean, weighted.mean): every partial sum is rounded to 64 mantissa bits, here by carrying a double-double and rounding it after each addition
fn sum_ld(x: []const f64) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < x.len {
        let t = hi + x[i]
        let bb = t - hi
        let e1 = (hi - (t - bb)) + (x[i] - bb)
        let t2 = e1 + lo
        let b2 = t2 - e1
        let e2 = (e1 - (t2 - b2)) + (lo - b2)
        let h = t + t2
        let b3 = h - t
        let l = ((t - (h - b3)) + (t2 - b3)) + e2
        let (rh, rl) = ld_round(h, l)
        hi = rh
        lo = rl
        i += 1usize
    }
    ret hi + lo
}

fn mean_of(x: []const f64) -> f64 {
    ret sum_ld(x) / f64(x.len)
}

// BCa limits of the replicates theta (mediate's BC.CI): z0 from the share below the mean, the acceleration from the jackknife-like U
fn bca_ci(theta: []const f64, low: f64, high: f64, srt: []const f64, lim: []f64) {
    let r = theta.len
    let mn = mean_of(theta)
    var below = 0.0f64
    var top = 0.0f64
    var u2 = 0.0f64
    var i = 0usize
    while i < r {
        if theta[i] < mn { below += 1.0f64 }
        let u = f64(r - 1usize) * (mn - theta[i])
        top += u * u * u
        u2 += u * u
        i += 1usize
    }
    let z = dist.qnorm(below / f64(r), 0.0f64, 1.0f64, true, false)
    let under = 6.0f64 * math.pow[f64](u2, 1.5f64)
    let ac = top / under
    let zl = z + dist.qnorm(low, 0.0f64, 1.0f64, true, false)
    let zh = z + dist.qnorm(high, 0.0f64, 1.0f64, true, false)
    let li = dist.pnorm(z + zl / (1.0f64 - ac * zl), 0.0f64, 1.0f64, true, false)
    let ui = dist.pnorm(z + zh / (1.0f64 - ac * zh), 0.0f64, 1.0f64, true, false)
    lim[0usize] = quant_r(srt, li)
    lim[1usize] = quant_r(srt, ui)
}

// the summaries of mediate from the replicates of delta.1, delta.0, zeta.1, zeta.0 (length r). est4 empty: the quasi-Bayesian point estimates (means, medians of the proportions); else d1, d0, z1, z0 of the
// sample (bootstrap). out: ten quantities d0, d1, z0, z1, n0, n1, tau, d.avg, z.avg, n.avg, each estimate, lower limit, upper limit, p value (40 values)
fn summarize(a: *mem.Arena, d1: []const f64, d0: []const f64, z1: []const f64, z0: []const f64, conf: f64, est4: []const f64, bca: bool, out: []f64) -> err {
    let r = d1.len
    var sims: [10][]f64 = zero
    var k = 0usize
    while k < 10usize {
        let (v, e) = mem.alloc[f64](a, r)
        if e != ok { ret e }
        sims[k] = v
        k += 1usize
    }
    let (srt, es) = mem.alloc[f64](a, r)
    if es != ok { ret es }
    let boot = est4.len == 4usize
    var j = 0usize
    while j < r {
        var tau = (z1[j] + d0[j] + z0[j] + d1[j]) / 2.0f64
        if boot { tau = (d1[j] + d0[j] + z1[j] + z0[j]) / 2.0f64 }
        sims[0usize][j] = d0[j]
        sims[1usize][j] = d1[j]
        sims[2usize][j] = z0[j]
        sims[3usize][j] = z1[j]
        sims[4usize][j] = d0[j] / tau
        sims[5usize][j] = d1[j] / tau
        sims[6usize][j] = tau
        sims[7usize][j] = (d1[j] + d0[j]) / 2.0f64
        sims[8usize][j] = (z1[j] + z0[j]) / 2.0f64
        sims[9usize][j] = (sims[5usize][j] + sims[4usize][j]) / 2.0f64
        if boot {
            sims[7usize][j] = (d0[j] + d1[j]) / 2.0f64
            sims[8usize][j] = (z0[j] + z1[j]) / 2.0f64
            sims[9usize][j] = (sims[4usize][j] + sims[5usize][j]) / 2.0f64
        }
        j += 1usize
    }
    var est: [10]f64 = zero
    if boot {
        let tc = (est4[0usize] + est4[1usize] + est4[2usize] + est4[3usize]) / 2.0f64
        est[0usize] = est4[1usize]
        est[1usize] = est4[0usize]
        est[2usize] = est4[3usize]
        est[3usize] = est4[2usize]
        est[4usize] = est4[1usize] / tc
        est[5usize] = est4[0usize] / tc
        est[6usize] = tc
        est[7usize] = (est4[0usize] + est4[1usize]) / 2.0f64
        est[8usize] = (est4[2usize] + est4[3usize]) / 2.0f64
        est[9usize] = (est[5usize] + est[4usize]) / 2.0f64
    }
    let low = (1.0f64 - conf) / 2.0f64
    let high = 1.0f64 - low
    k = 0usize
    while k < 10usize {
        j = 0usize
        while j < r {
            srt[j] = sims[k][j]
            j += 1usize
        }
        sort_in_place(srt)
        if !boot {
            if k == 4usize || k == 5usize {
                est[k] = quant_r(srt, 0.5f64)
            }
            if k < 4usize || k == 6usize { est[k] = mean_of(sims[k]) }
            if k == 7usize { est[k] = (est[0usize] + est[1usize]) / 2.0f64 }
            if k == 8usize { est[k] = (est[2usize] + est[3usize]) / 2.0f64 }
            if k == 9usize { est[k] = (est[4usize] + est[5usize]) / 2.0f64 }
        }
        var lim: [2]f64 = zero
        lim[0usize] = quant_r(srt, low)
        lim[1usize] = quant_r(srt, high)
        if bca { bca_ci(sims[k], low, high, srt, lim[0usize..2usize]) }
        out[k * 4usize] = est[k]
        out[k * 4usize + 1usize] = lim[0usize]
        out[k * 4usize + 2usize] = lim[1usize]
        out[k * 4usize + 3usize] = pval(sims[k], est[k])
        k += 1usize
    }
    ret ok
}

// the four effect means under outcome coefficients b and the mediator draws pm1, pm0 (per observation): delta.1, delta.0, zeta.1, zeta.0
fn effects(a: *mem.Arena, ys: *const Spec, b: []const f64, tv0: f64, tv1: f64, pm1: []const f64, pm0: []const f64, out4: []f64) -> err {
    let n = ys.n
    let p = ys.p
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (xc, e2) = mem.alloc[f64](a, n * p)
    let (t1, e3) = filled(a, n, tv1)
    let (t0, e4) = filled(a, n, tv0)
    let (df, e5) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var e = 0usize
    while e < 4usize {
        var tt = t1
        var tc = t1
        var mt = pm1
        var mc = pm0
        if e == 1usize {
            tt = t0
            tc = t0
        }
        if e == 2usize {
            mc = pm1
            tc = t0
        }
        if e == 3usize {
            mt = pm0
            tc = t0
        }
        design(ys, tt, mt, xt)
        design(ys, tc, mc, xc)
        var i = 0usize
        while i < n {
            let p1 = gl.linkinv(ys.link, dot_row(xt, i * p, b, p))
            let p0 = gl.linkinv(ys.link, dot_row(xc, i * p, b, p))
            df[i] = p1 - p0
            i += 1usize
        }
        out4[e] = sum_ld(df) / f64(n)
        e += 1usize
    }
    ret ok
}

fn draw_m(g: *rng.Rng, fam: usize, mu: f64) -> f64 {
    if fam == 1usize { ret rd.rbinom(g, 1.0f64, mu) }
    ret rd.rpois(g, mu)
}

// mediate(boot = FALSE): the quasi-Bayesian simulation. Coefficients of the mediator model first, then the outcome model, from one stream (mvtnorm::rmvnorm), then the mediator draws (a gaussian mediator's
// errors, or binomial/poisson draws) for the treated and the control values, column-major over simulations. out as summarize (40 values)
fn mediate_qb(a: *mem.Arena, g: *rng.Rng, ms: *const Spec, mbeta: []const f64, mcov: []const f64, msigma: f64, ys: *const Spec, ybeta: []const f64, ycov: []const f64, tv0: f64, tv1: f64, sims: usize, conf: f64, out: []f64) -> err {
    let n = ms.n
    let pm = ms.p
    let py = ys.p
    let (mdraw, e1) = mv.rmvnorm(a, g, sims, mbeta, mcov, pm, 0u8)
    if e1 != ok { ret e1 }
    let (ydraw, e2) = mv.rmvnorm(a, g, sims, ybeta, ycov, py, 0u8)
    if e2 != ok { ret e2 }
    let (xm1, e3) = mem.alloc[f64](a, n * pm)
    let (xm0, e4) = mem.alloc[f64](a, n * pm)
    let (t1, e5) = filled(a, n, tv1)
    let (t0, e6) = filled(a, n, tv0)
    let (pm1, e7) = mem.alloc[f64](a, sims * n)
    let (pm0, e8) = mem.alloc[f64](a, sims * n)
    let (dd1, e9) = mem.alloc[f64](a, sims)
    let (dd0, e10) = mem.alloc[f64](a, sims)
    let (zz1, e11) = mem.alloc[f64](a, sims)
    let (zz0, e12) = mem.alloc[f64](a, sims)
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    var none: []const f64 = zero
    design(ms, t1, none, xm1)
    design(ms, t0, none, xm0)
    var k = 0usize
    if ms.fam == 0usize {
        while k < sims * n {
            let j = k % sims
            let i = k / sims
            let er = rng.rnorm(g, 0.0f64, msigma)
            pm1[j * n + i] = gl.linkinv(ms.link, dot_row(xm1, i * pm, mdraw[j * pm..j * pm + pm], pm)) + er
            pm0[j * n + i] = gl.linkinv(ms.link, dot_row(xm0, i * pm, mdraw[j * pm..j * pm + pm], pm)) + er
            k += 1usize
        }
    } else {
        while k < sims * n {
            let j = k % sims
            let i = k / sims
            pm1[j * n + i] = draw_m(g, ms.fam, gl.linkinv(ms.link, dot_row(xm1, i * pm, mdraw[j * pm..j * pm + pm], pm)))
            k += 1usize
        }
        k = 0usize
        while k < sims * n {
            let j = k % sims
            let i = k / sims
            pm0[j * n + i] = draw_m(g, ms.fam, gl.linkinv(ms.link, dot_row(xm0, i * pm, mdraw[j * pm..j * pm + pm], pm)))
            k += 1usize
        }
    }
    var j = 0usize
    while j < sims {
        let start = mem.mark(a)
        var o4: [4]f64 = zero
        let ee = effects(a, ys, ydraw[j * py..j * py + py], tv0, tv1, pm1[j * n..j * n + n], pm0[j * n..j * n + n], o4[0usize..4usize])
        if ee != ok { ret ee }
        dd1[j] = o4[0usize]
        dd0[j] = o4[1usize]
        zz1[j] = o4[2usize]
        zz0[j] = o4[3usize]
        mem.reset(a, start)
        j += 1usize
    }
    ret summarize(a, dd1, dd0, zz1, zz0, conf, none, false, out)
}

// the statistic of one bootstrap replicate (mediate's med.fun): refit both models on rows idx (empty: the sample), draw the mediator for the observed rows, d1, d0, z1, z0
fn boot_stat(a: *mem.Arena, g: *rng.Rng, ms: *const Spec, ys: *const Spec, xm_obs: []const f64, ym_obs: []const f64, idx: []const i64, tv0: f64, tv1: f64, out4: []f64) -> err {
    let n = ms.n
    let pm = ms.p
    let py = ys.p
    let (bm, e1) = mem.alloc[f64](a, pm)
    let (cm, e2) = mem.alloc[f64](a, pm * pm)
    let (by, e3) = mem.alloc[f64](a, py)
    let (cy, e4) = mem.alloc[f64](a, py * py)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let (sm, f1) = fit_model(a, ms, xm_obs, idx, bm, cm)
    if f1 != ok { ret f1 }
    let (sy, f2) = fit_model(a, ys, ym_obs, idx, by, cy)
    if f2 != ok { ret f2 }
    let (xm1, e5) = mem.alloc[f64](a, n * pm)
    let (xm0, e6) = mem.alloc[f64](a, n * pm)
    let (t1, e7) = filled(a, n, tv1)
    let (t0, e8) = filled(a, n, tv0)
    let (pm1, e9) = mem.alloc[f64](a, n)
    let (pm0, e10) = mem.alloc[f64](a, n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    var none: []const f64 = zero
    design(ms, t1, none, xm1)
    design(ms, t0, none, xm0)
    var i = 0usize
    if ms.fam == 0usize {
        while i < n {
            let er = rng.rnorm(g, 0.0f64, sm)
            pm1[i] = gl.linkinv(ms.link, dot_row(xm1, i * pm, bm, pm)) + er
            pm0[i] = gl.linkinv(ms.link, dot_row(xm0, i * pm, bm, pm)) + er
            i += 1usize
        }
    } else {
        while i < n {
            pm1[i] = draw_m(g, ms.fam, gl.linkinv(ms.link, dot_row(xm1, i * pm, bm, pm)))
            i += 1usize
        }
        i = 0usize
        while i < n {
            pm0[i] = draw_m(g, ms.fam, gl.linkinv(ms.link, dot_row(xm0, i * pm, bm, pm)))
            i += 1usize
        }
    }
    ret effects(a, ys, by, tv0, tv1, pm1, pm0, out4)
}

// mediate(boot = TRUE): boot::boot's order, the n * sims resampled rows first (sample.int, column-major), then the statistic on the sample, on each replicate, and on the sample once more for the estimates
fn mediate_boot(a: *mem.Arena, g: *rng.Rng, ms: *const Spec, ys: *const Spec, tv0: f64, tv1: f64, sims: usize, conf: f64, bca: bool, out: []f64) -> err {
    let n = ms.n
    var none: []const f64 = zero
    let (xm_obs, e1) = mem.alloc[f64](a, n * ms.p)
    let (ym_obs, e2) = mem.alloc[f64](a, n * ys.p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    design(ms, ms.tr, none, xm_obs)
    design(ys, ys.tr, ys.mobs, ym_obs)
    let (all, e3) = rng.sample_int(a, g, i64(n), i64(n * sims), true)
    if e3 != ok { ret e3 }
    var idn: []const i64 = zero
    var t4: [4]f64 = zero
    let ez = boot_stat(a, g, ms, ys, xm_obs, ym_obs, idn, tv0, tv1, t4[0usize..4usize])
    if ez != ok { ret ez }
    let (d1, e4) = mem.alloc[f64](a, sims)
    let (d0, e5) = mem.alloc[f64](a, sims)
    let (z1, e6) = mem.alloc[f64](a, sims)
    let (z0, e7) = mem.alloc[f64](a, sims)
    let (ix, e8) = mem.alloc[i64](a, n)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    var r = 0usize
    while r < sims {
        let start = mem.mark(a)
        var i = 0usize
        while i < n {
            ix[i] = all[r + sims * i]
            i += 1usize
        }
        let er = boot_stat(a, g, ms, ys, xm_obs, ym_obs, ix, tv0, tv1, t4[0usize..4usize])
        if er != ok { ret er }
        d1[r] = t4[0usize]
        d0[r] = t4[1usize]
        z1[r] = t4[2usize]
        z0[r] = t4[3usize]
        mem.reset(a, start)
        r += 1usize
    }
    var est: [4]f64 = zero
    let ef = boot_stat(a, g, ms, ys, xm_obs, ym_obs, idn, tv0, tv1, est[0usize..4usize])
    if ef != ok { ret ef }
    ret summarize(a, d1, d0, z1, z0, conf, est[0usize..4usize], bca, out)
}

// ---- medsens: the sensitivity analysis to a correlation rho between the two models' errors ----
// Output layout (nr values of rho: seq(-1 + rho.by, 1 - rho.by, rho.by)): seven quantities d0, d1, z0, z1, tau, nu0, nu1 each as three blocks of nr (estimate, lower limit, upper limit), then ind.d0, ind.d1, ind.z0,
// ind.z1 and R2tilde.prod (26 blocks of nr), then 14 scalars: err.cr.d (two: min |d0|, min |d1|), err.cr.z (two), r.square.m, r.square.y, then R2star and R2tilde thresholds of d0, d1, z0, z1. NaN where R has NULL.

fn rho_count(rho_by: f64) -> usize { ret usize(math.floor[f64]((2.0f64 - 2.0f64 * rho_by) / rho_by + 1.0e-10f64)) + 1usize }

fn inv_mat(a: *mem.Arena, x: []const f64, k: usize, out: []f64) -> err {
    let (w, e) = mem.alloc[f64](a, k * 2usize * k)
    if e != ok { ret e }
    let k2 = 2usize * k
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            w[i * k2 + j] = x[i * k + j]
            w[i * k2 + k + j] = 0.0f64
            if i == j { w[i * k2 + k + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var piv = c
        var r = c + 1usize
        while r < k {
            if math.abs[f64](w[r * k2 + c]) > math.abs[f64](w[piv * k2 + c]) { piv = r }
            r += 1usize
        }
        if piv != c {
            var j = 0usize
            while j < k2 {
                let t = w[c * k2 + j]
                w[c * k2 + j] = w[piv * k2 + j]
                w[piv * k2 + j] = t
                j += 1usize
            }
        }
        let d = w[c * k2 + c]
        var j = 0usize
        while j < k2 {
            w[c * k2 + j] = w[c * k2 + j] / d
            j += 1usize
        }
        r = 0usize
        while r < k {
            if r != c {
                let f = w[r * k2 + c]
                j = 0usize
                while j < k2 {
                    w[r * k2 + j] = w[r * k2 + j] - f * w[c * k2 + j]
                    j += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            out[i * k + j] = w[i * k2 + k + j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// crossprod of two row-major n by p and n by q matrices (p by q)
fn xtx(x: []const f64, p: usize, y: []const f64, q: usize, n: usize, out: []f64) {
    var a = 0usize
    while a < p {
        var b = 0usize
        while b < q {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += x[i * p + a] * y[i * q + b]
                i += 1usize
            }
            out[a * q + b] = s
            b += 1usize
        }
        a += 1usize
    }
}

fn first_min_abs(v: []const f64) -> usize {
    var at = 0usize
    var i = 1usize
    while i < v.len {
        if math.abs[f64](v[i]) < math.abs[f64](v[at]) { at = i }
        i += 1usize
    }
    ret at
}

fn put_thresholds(out: []f64, nr: usize, rho_by: f64, d0: []const f64, d1: []const f64, z0: []const f64, z1: []const f64, two: bool, rsm: f64, rsy: f64) {
    let base = 26usize * nr
    let nan = 0.0f64 / 0.0f64
    var k = 0usize
    while k < 14usize {
        out[base + k] = nan
        k += 1usize
    }
    let rho_from = -1.0f64

    var ed0 = rho_from + rho_by + rho_by * f64(first_min_abs(d0))
    var ed1 = ed0
    var ez0 = rho_from + rho_by + rho_by * f64(first_min_abs(z0))
    var ez1 = ez0
    if two {
        ed1 = rho_from + rho_by + rho_by * f64(first_min_abs(d1))
        ez1 = rho_from + rho_by + rho_by * f64(first_min_abs(z1))
    }
    out[base] = ed0
    out[base + 2usize] = ez0
    out[base + 4usize] = rsm
    out[base + 5usize] = rsy
    out[base + 6usize] = ed0 * ed0
    out[base + 7usize] = ed0 * ed0 * (1.0f64 - rsm) * (1.0f64 - rsy)
    out[base + 10usize] = ez0 * ez0
    out[base + 11usize] = ez0 * ez0 * (1.0f64 - rsm) * (1.0f64 - rsy)
    if two {
        out[base + 1usize] = ed1
        out[base + 3usize] = ez1
        out[base + 8usize] = ed1 * ed1
        out[base + 9usize] = ed1 * ed1 * (1.0f64 - rsm) * (1.0f64 - rsy)
        out[base + 12usize] = ez1 * ez1
        out[base + 13usize] = ez1 * ez1 * (1.0f64 - rsm) * (1.0f64 - rsy)
    }
}

fn sample_var(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

// medsens for a gaussian mediator and a gaussian outcome (the stacked seemingly-unrelated regression solved by iterated GLS for each rho). xm, xy: observed design matrices (n by pm, n by py, row-major, intercept first);
// tm the treatment column of xm, ty and my the treatment and mediator columns of xy, tmy the interaction column of xy (or a value past py). effect.type "both".
fn medsens_ct(a: *mem.Arena, xm: []const f64, ym: []const f64, pm: usize, xy: []const f64, yy: []const f64, py: usize, n: usize, tm: usize, ty: usize, my: usize, tmy: usize, rho_by: f64, conf: f64, eps: f64, out: []f64) -> err {
    let nr = rho_count(rho_by)
    let nan = 0.0f64 / 0.0f64
    let pt = pm + py
    let int = tmy < py
    let (gmm, e1) = mem.alloc[f64](a, pm * pm)
    let (gmy, e2) = mem.alloc[f64](a, pm * py)
    let (gyy, e3) = mem.alloc[f64](a, py * py)
    let (rm, e4) = mem.alloc[f64](a, pm)
    let (rmy, e5) = mem.alloc[f64](a, pm)
    let (rym, e6) = mem.alloc[f64](a, py)
    let (ry, e7) = mem.alloc[f64](a, py)
    let (im, e8) = mem.alloc[f64](a, pm * pm)
    let (iy, e9) = mem.alloc[f64](a, py * py)
    let (bm, e10) = mem.alloc[f64](a, pm)
    let (by, e11) = mem.alloc[f64](a, py)
    let (bt, e12) = mem.alloc[f64](a, pt)
    let (bs, e13) = mem.alloc[f64](a, pt)
    let (am, e14) = mem.alloc[f64](a, pt * pt)
    let (ai, e15) = mem.alloc[f64](a, pt * pt)
    let (rhs, e16) = mem.alloc[f64](a, pt)
    let (r1, e17) = mem.alloc[f64](a, n)
    let (r2, e18) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret mem.Full }
    xtx(xm, pm, xm, pm, n, gmm)
    xtx(xm, pm, xy, py, n, gmy)
    xtx(xy, py, xy, py, n, gyy)
    xtx(xm, pm, ym[0usize..n], 1usize, n, rm)
    xtx(xm, pm, yy[0usize..n], 1usize, n, rmy)
    xtx(xy, py, ym[0usize..n], 1usize, n, rym)
    xtx(xy, py, yy[0usize..n], 1usize, n, ry)
    var ie = inv_mat(a, gmm, pm, im)
    if ie != ok { ret ie }
    ie = inv_mat(a, gyy, py, iy)
    if ie != ok { ret ie }
    var i = 0usize
    while i < pm {
        var s = 0.0f64
        var j = 0usize
        while j < pm {
            s += im[i * pm + j] * rm[j]
            j += 1usize
        }
        bm[i] = s
        i += 1usize
    }
    i = 0usize
    while i < py {
        var s = 0.0f64
        var j = 0usize
        while j < py {
            s += iy[i * py + j] * ry[j]
            j += 1usize
        }
        by[i] = s
        i += 1usize
    }
    // the mediator design means over the covariate columns (not the intercept and not the treatment)
    var mbar: [16]f64 = zero
    var c = 0usize
    while c < pm {
        var s = 0.0f64
        let (col, ec) = mem.alloc[f64](a, n)
        if ec != ok { ret ec }
        i = 0usize
        while i < n {
            col[i] = xm[i * pm + c]
            i += 1usize
        }
        s = sum_ld(col) / f64(n)
        mbar[c] = s
        c += 1usize
    }
    let low = (1.0f64 - conf) / 2.0f64
    let high = 1.0f64 - low
    let zl = dist.qnorm(low, 0.0f64, 1.0f64, true, false)
    let zh = dist.qnorm(high, 0.0f64, 1.0f64, true, false)
    var d0 = 0.0f64
    var ri = 0usize
    while ri < nr {
        let rho = -1.0f64 + rho_by + f64(ri) * rho_by
        i = 0usize
        while i < pm {
            bt[i] = bm[i]
            i += 1usize
        }
        i = 0usize
        while i < py {
            bt[pm + i] = by[i]
            i += 1usize
        }
        var dif = 1.0f64
        while math.abs[f64](dif) > eps {
            i = 0usize
            while i < n {
                var s1 = ym[i]
                var s2 = yy[i]
                c = 0usize
                while c < pm {
                    s1 -= xm[i * pm + c] * bt[c]
                    c += 1usize
                }
                c = 0usize
                while c < py {
                    s2 -= xy[i * py + c] * bt[pm + c]
                    c += 1usize
                }
                r1[i] = s1
                r2[i] = s2
                i += 1usize
            }
            var q11 = 0.0f64
            var q22 = 0.0f64
            i = 0usize
            while i < n {
                q11 += r1[i] * r1[i]
                q22 += r2[i] * r2[i]
                i += 1usize
            }
            let o11 = q11 / f64(n - 1usize)
            let o22 = q22 / f64(n - 1usize)
            let off = rho * math.sqrt[f64](sample_var(r1)) * math.sqrt[f64](sample_var(r2))
            let det = o11 * o22 - off * off
            let w11 = o22 / det
            let w22 = o11 / det
            let w12 = (0.0f64 - off) / det
            i = 0usize
            while i < pm {
                var j = 0usize
                while j < pm {
                    am[i * pt + j] = w11 * gmm[i * pm + j]
                    j += 1usize
                }
                j = 0usize
                while j < py {
                    am[i * pt + pm + j] = w12 * gmy[i * py + j]
                    am[(pm + j) * pt + i] = w12 * gmy[i * py + j]
                    j += 1usize
                }
                rhs[i] = w11 * rm[i] + w12 * rmy[i]
                i += 1usize
            }
            i = 0usize
            while i < py {
                var j = 0usize
                while j < py {
                    am[(pm + i) * pt + pm + j] = w22 * gyy[i * py + j]
                    j += 1usize
                }
                rhs[pm + i] = w12 * rym[i] + w22 * ry[i]
                i += 1usize
            }
            let ie2 = inv_mat(a, am, pt, ai)
            if ie2 != ok { ret ie2 }
            dif = 0.0f64
            i = 0usize
            while i < pt {
                var s = 0.0f64
                var j = 0usize
                while j < pt {
                    s += ai[i * pt + j] * rhs[j]
                    j += 1usize
                }
                bs[i] = s
                dif += (s - bt[i]) * (s - bt[i])
                i += 1usize
            }
            i = 0usize
            while i < pt {
                bt[i] = bs[i]
                i += 1usize
            }
        }
        let mct = bt[tm]
        let ytr = bt[pm + ty]
        let ymed = bt[pm + my]
        let vmt = ai[tm * pt + tm]
        let vyt = ai[(pm + ty) * pt + pm + ty]
        let vym = ai[(pm + my) * pt + pm + my]
        var d0v = mct * ymed
        var d1v = d0v
        var z0v = ytr
        var z1v = ytr
        var d0var = mct * mct * vym + ymed * ymed * vmt
        var d1var = d0var
        var z0var = vyt
        var z1var = vyt
        if int {
            let ytm = bt[pm + tmy]
            let vytm = ai[(pm + tmy) * pt + pm + tmy]
            let vymtm = ai[(pm + my) * pt + pm + tmy]
            let vytrtm = ai[(pm + ty) * pt + pm + tmy]
            d1v = mct * (ymed + ytm)
            d0var = ymed * ymed * vmt + mct * mct * vym
            d1var = (ymed + ytm) * (ymed + ytm) * vmt + mct * mct * (vym + vytm + 2.0f64 * vymtm)
            // the mean mediator under control and treatment, covariates at their means
            var dotc = 0.0f64
            var vcov = 0.0f64
            var vtc = 0.0f64
            var vic = 0.0f64
            var ca = 1usize
            while ca < pm {
                if ca != tm {
                    dotc += bt[ca] * mbar[ca]
                    vtc += mbar[ca] * ai[tm * pt + ca]
                    vic += mbar[ca] * ai[ca]
                    var cb = 1usize
                    while cb < pm {
                        if cb != tm { vcov += mbar[ca] * ai[ca * pt + cb] * mbar[cb] }
                        cb += 1usize
                    }
                }
                ca += 1usize
            }
            let mb0 = bt[0usize] + dotc
            let vmb0 = ai[0usize] + vcov
            let mb1 = bt[0usize] + mct + dotc
            let vmb1 = ai[0usize] + vmt + vcov + 2.0f64 * (ai[tm] + vtc + vic)
            z0v = ytr + ytm * mb0
            z1v = ytr + ytm * mb1
            z0var = vyt + mb0 * mb0 * vytm + ytm * ytm * vmb0 + vytm * vmb0 + 2.0f64 * mb0 * vytrtm
            z1var = vyt + mb1 * mb1 * vytm + ytm * ytm * vmb1 + vytm * vmb1 + 2.0f64 * mb1 * vytrtm
        }
        var q = 0usize
        while q < 26usize {
            out[q * nr + ri] = nan
            q += 1usize
        }
        out[ri] = d0v
        out[nr + ri] = d0v + zl * math.sqrt[f64](d0var)
        out[2usize * nr + ri] = d0v + zh * math.sqrt[f64](d0var)
        out[3usize * nr + ri] = d1v
        out[4usize * nr + ri] = d1v + zl * math.sqrt[f64](d1var)
        out[5usize * nr + ri] = d1v + zh * math.sqrt[f64](d1var)
        out[6usize * nr + ri] = z0v
        out[7usize * nr + ri] = z0v + zl * math.sqrt[f64](z0var)
        out[8usize * nr + ri] = z0v + zh * math.sqrt[f64](z0var)
        out[9usize * nr + ri] = z1v
        out[10usize * nr + ri] = z1v + zl * math.sqrt[f64](z1var)
        out[11usize * nr + ri] = z1v + zh * math.sqrt[f64](z1var)
        var k4 = 0usize
        while k4 < 4usize {
            var ind = 0.0f64
            if out[(3usize * k4 + 1usize) * nr + ri] < 0.0f64 && out[(3usize * k4 + 2usize) * nr + ri] > 0.0f64 { ind = 1.0f64 }
            out[(21usize + k4) * nr + ri] = ind
            k4 += 1usize
        }
        d0 = d0v
        ri += 1usize
    }
    // R squared of both least squares fits
    var rsm = 0.0f64
    var rsy = 0.0f64
    var which = 0usize
    while which < 2usize {
        var p = pm
        if which == 1usize { p = py }
        let (bb, eb) = mem.alloc[f64](a, p)
        let (cv, ec2) = mem.alloc[f64](a, p * p)
        let (fit, ef) = mem.alloc[f64](a, n)
        let (rs, er) = mem.alloc[f64](a, n)
        if eb != ok || ec2 != ok || ef != ok || er != ok { ret mem.Full }
        var xx = xm
        var yv = ym
        if which == 1usize {
            xx = xy
            yv = yy
        }
        let (rss, el) = ar.lm_summary(a, xx, yv, n, p, bb, cv, rs)
        if el != ok { ret el }
        i = 0usize
        while i < n {
            fit[i] = dot_row(xx, i * p, bb, p)
            i += 1usize
        }
        let fm = mean_of(fit)
        var mss = 0.0f64
        i = 0usize
        while i < n {
            mss += (fit[i] - fm) * (fit[i] - fm)
            i += 1usize
        }
        if which == 0usize { rsm = mss / (mss + rss) }
        if which == 1usize { rsy = mss / (mss + rss) }
        which += 1usize
    }
    put_thresholds(out, nr, rho_by, out[0usize..nr], out[3usize * nr..4usize * nr], out[6usize * nr..7usize * nr], out[9usize * nr..10usize * nr], int, rsm, rsy)
    i = 0usize
    while i < nr {
        let rho = -1.0f64 + rho_by + f64(i) * rho_by
        out[25usize * nr + i] = rho * rho * (1.0f64 - rsm) * (1.0f64 - rsy)
        i += 1usize
    }
    ret ok
}

fn pn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn lm_rsq(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, beta: []f64, cov: []f64) -> (f64, f64, err) {
    let (fit, ef) = mem.alloc[f64](a, n)
    let (rs, er) = mem.alloc[f64](a, n)
    if ef != ok || er != ok { ret (0.0f64, 0.0f64, mem.Full) }
    let (rss, el) = ar.lm_summary(a, x, y, n, p, beta, cov, rs)
    if el != ok { ret (0.0f64, 0.0f64, el) }
    var i = 0usize
    while i < n {
        fit[i] = dot_row(x, i * p, beta, p)
        i += 1usize
    }
    let fm = mean_of(fit)
    var mss = 0.0f64
    i = 0usize
    while i < n {
        mss += (fit[i] - fm) * (fit[i] - fm)
        i += 1usize
    }
    ret (rss, mss / (mss + rss), ok)
}

// medsens for a gaussian mediator and a probit outcome without interaction (the procedure of Imai, Keele and Yamamoto): the mediator model's coefficients, its error variance (inverse gamma) and the outcome
// model's coefficients are drawn first, in that order, then each rho is run over the same draws. tm: treatment column of xm; ty, my: treatment and mediator columns of xy.
fn medsens_bo(a: *mem.Arena, g: *rng.Rng, xm: []const f64, ym: []const f64, pm: usize, xy: []const f64, yy: []const f64, py: usize, n: usize, tm: usize, ty: usize, my: usize, rho_by: f64, conf: f64, sims: usize, out: []f64) -> err {
    let nr = rho_count(rho_by)
    let (bm, e1) = mem.alloc[f64](a, pm)
    let (cm, e2) = mem.alloc[f64](a, pm * pm)
    let (by, e3) = mem.alloc[f64](a, py)
    let (cy, e4) = mem.alloc[f64](a, py * py)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let (rssm, rsm, el) = lm_rsq(a, xm, ym, n, pm, bm, cm)
    if el != ok { ret el }
    let df = f64(n - pm)
    let s2 = rssm / df
    var i = 0usize
    while i < pm * pm {
        cm[i] = cm[i] * s2
        i += 1usize
    }
    let (info, e5) = mem.alloc[f64](a, 5usize)
    if e5 != ok { ret e5 }
    var none: []const f64 = zero
    let it = gl.glm_fit_gen(a, xy, yy, n, py, 1usize, 4usize, none, none, true, by, cy, info)
    if it == 0usize { ret mem.Full }
    i = 0usize
    while i < py * py {
        cy[i] = cy[i] * info[0usize]
        i += 1usize
    }
    let (msim, e6) = mv.rmvnorm(a, g, sims, bm, cm, pm, 0u8)
    if e6 != ok { ret e6 }
    let (sig2, e7) = mem.alloc[f64](a, sims)
    if e7 != ok { ret e7 }
    let shape = df / 2.0f64
    let invscale = (df / 2.0f64) * s2
    var k = 0usize
    while k < sims {
        sig2[k] = math.sqrt[f64](1.0f64 / rd.rgamma(g, shape, 1.0f64 / invscale))
        k += 1usize
    }
    let (ysim, e8) = mv.rmvnorm(a, g, sims, by, cy, py, 0u8)
    if e8 != ok { ret e8 }
    // the outcome design without the mediator, at treatment 1 and 0
    let pw = py - 1usize
    let (w1, e9) = mem.alloc[f64](a, n * pw)
    let (w0, e10) = mem.alloc[f64](a, n * pw)
    let (yt, e11) = mem.alloc[f64](a, sims * pw)
    let (rho12, e12) = mem.alloc[f64](a, sims)
    let (gam, e13) = mem.alloc[f64](a, sims)
    let (eta0, e14) = mem.alloc[f64](a, n)
    let (eta1, e15) = mem.alloc[f64](a, n)
    let (df0, e16) = mem.alloc[f64](a, n)
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret mem.Full }
    var tw = ty
    if ty > my { tw = ty - 1usize }
    i = 0usize
    while i < n {
        var c = 0usize
        var cw = 0usize
        while c < py {
            if c != my {
                w1[i * pw + cw] = xy[i * py + c]
                w0[i * pw + cw] = xy[i * py + c]
                if c == ty {
                    w1[i * pw + cw] = 1.0f64
                    w0[i * pw + cw] = 0.0f64
                }
                cw += 1usize
            }
            c += 1usize
        }
        i += 1usize
    }
    k = 0usize
    while k < sims {
        let gt = ysim[k * py + my]
        rho12[k] = (sig2[k] * gt) / (1.0f64 + math.sqrt[f64](sig2[k] * sig2[k] * (gt * gt)))
        var c = 0usize
        var cw = 0usize
        while c < py {
            if c != my {
                yt[k * pw + cw] = ysim[k * py + c] * math.sqrt[f64](1.0f64 - rho12[k] * rho12[k]) + msim[k * pm + cw] * (rho12[k] / sig2[k])
                cw += 1usize
            }
            c += 1usize
        }
        k += 1usize
    }
    let low = (1.0f64 - conf) / 2.0f64
    let high = 1.0f64 - low
    let (srt, e17) = mem.alloc[f64](a, sims)
    if e17 != ok { ret e17 }
    var sm: [7][]f64 = zero
    var q = 0usize
    while q < 7usize {
        let (v, ev) = mem.alloc[f64](a, sims)
        if ev != ok { ret ev }
        sm[q] = v
        q += 1usize
    }
    var ri = 0usize
    while ri < nr {
        let rho = -1.0f64 + rho_by + f64(ri) * rho_by
        k = 0usize
        while k < sims {
            gam[k] = ((0.0f64 - rho) + rho12[k] * math.sqrt[f64]((1.0f64 - rho * rho) / (1.0f64 - rho12[k] * rho12[k]))) / sig2[k]
            let s1 = math.sqrt[f64](gam[k] * gam[k] * (sig2[k] * sig2[k]) + 2.0f64 * gam[k] * rho * sig2[k] + 1.0f64)
            let b2 = msim[k * pm + tm]
            let beta3 = s1 * yt[k * pw + tw] - b2 * gam[k]
            i = 0usize
            while i < n {
                eta0[i] = dot_row(w0, i * pw, yt[k * pw..k * pw + pw], pw)
                eta1[i] = dot_row(w1, i * pw, yt[k * pw..k * pw + pw], pw)
                i += 1usize
            }
            let sh = gam[k] * b2 / s1
            i = 0usize
            while i < n {
                df0[i] = pn(eta0[i] + sh) - pn(eta0[i])
                i += 1usize
            }
            sm[0usize][k] = sum_ld(df0) / f64(n)
            i = 0usize
            while i < n {
                df0[i] = pn(eta1[i]) - pn(eta1[i] - sh)
                i += 1usize
            }
            sm[1usize][k] = sum_ld(df0) / f64(n)
            i = 0usize
            while i < n {
                df0[i] = pn(eta1[i]) - pn(eta0[i])
                i += 1usize
            }
            sm[4usize][k] = sum_ld(df0) / f64(n)
            sm[5usize][k] = sm[0usize][k] / sm[4usize][k]
            sm[6usize][k] = sm[1usize][k] / sm[4usize][k]
            let sb = beta3 / s1
            i = 0usize
            while i < n {
                df0[i] = pn(eta0[i] + sb) - pn(eta0[i])
                i += 1usize
            }
            sm[2usize][k] = sum_ld(df0) / f64(n)
            i = 0usize
            while i < n {
                df0[i] = pn(eta1[i]) - pn(eta1[i] - sb)
                i += 1usize
            }
            sm[3usize][k] = sum_ld(df0) / f64(n)
            k += 1usize
        }
        q = 0usize
        while q < 7usize {
            k = 0usize
            while k < sims {
                srt[k] = sm[q][k]
                k += 1usize
            }
            sort_in_place(srt)
            out[(3usize * q) * nr + ri] = mean_of(sm[q])
            out[(3usize * q + 1usize) * nr + ri] = quant_r(srt, low)
            out[(3usize * q + 2usize) * nr + ri] = quant_r(srt, high)
            q += 1usize
        }
        q = 0usize
        while q < 4usize {
            var ind = 0.0f64
            if out[(3usize * q + 1usize) * nr + ri] < 0.0f64 && out[(3usize * q + 2usize) * nr + ri] > 0.0f64 { ind = 1.0f64 }
            out[(21usize + q) * nr + ri] = ind
            q += 1usize
        }
        ri += 1usize
    }
    // R2tilde: the mediator model's R squared and the outcome model's latent variance share
    let (fit, ef2) = mem.alloc[f64](a, n)
    if ef2 != ok { ret ef2 }
    i = 0usize
    while i < n {
        fit[i] = dot_row(xy, i * py, by, py)
        i += 1usize
    }
    let vy = sample_var(fit)
    let rsy = vy / (1.0f64 + vy)
    put_thresholds(out, nr, rho_by, out[0usize..nr], out[3usize * nr..4usize * nr], out[6usize * nr..7usize * nr], out[9usize * nr..10usize * nr], true, rsm, rsy)
    i = 0usize
    while i < nr {
        let rho = -1.0f64 + rho_by + f64(i) * rho_by
        out[25usize * nr + i] = rho * rho * (1.0f64 - rsm) * (1.0f64 - rsy)
        i += 1usize
    }
    ret ok
}

fn dn(x: f64) -> f64 { ret dist.dnorm(x, 0.0f64, 1.0f64, false) }

// a weighted least squares fit by rows scaled with sqrt(w) (lm.wfit): beta, the unscaled covariance and the weighted residual sum of squares
fn wls(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, beta: []f64, cov: []f64) -> (f64, err) {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (ys, e2) = mem.alloc[f64](a, n)
    let (rs, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < n {
        let sw = math.sqrt[f64](w[i])
        var c = 0usize
        while c < p {
            xs[i * p + c] = x[i * p + c] * sw
            c += 1usize
        }
        ys[i] = y[i] * sw
        i += 1usize
    }
    let (rss, el) = ar.lm_summary(a, xs, ys, n, p, beta, cov, rs)
    ret (rss, el)
}

// medsens for a probit mediator and a gaussian outcome, with or without the treatment-mediator interaction (tmy past py when there is none): for every rho and every draw k of the mediator coefficients the outcome
// model is refit by iterated weighted least squares with the inverse-Mills correction, one coefficient draw each (rmvnorm(1, ...)), rho outermost. The direct effect with the interaction reads pnorm(-mu.1.sim[k]), the
// matrix indexed by a single position as the package does.
fn medsens_bm(a: *mem.Arena, g: *rng.Rng, xm: []const f64, mb: []const f64, pm: usize, xy: []const f64, yy: []const f64, py: usize, n: usize, tm: usize, ty: usize, my: usize, tmy: usize, rho_by: f64, conf: f64, sims: usize, eps: f64, out: []f64) -> err {
    let nr = rho_count(rho_by)
    let nan = 0.0f64 / 0.0f64
    let int = tmy < py
    let (bm, e1) = mem.alloc[f64](a, pm)
    let (cm, e2) = mem.alloc[f64](a, pm * pm)
    let (info, e3) = mem.alloc[f64](a, 5usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var none: []const f64 = zero
    let it = gl.glm_fit_gen(a, xm, mb, n, pm, 1usize, 4usize, none, none, true, bm, cm, info)
    if it == 0usize { ret mem.Full }
    var i = 0usize
    while i < pm * pm {
        cm[i] = cm[i] * info[0usize]
        i += 1usize
    }
    let (msim, e4) = mv.rmvnorm(a, g, sims, bm, cm, pm, 0u8)
    if e4 != ok { ret e4 }
    // mu.sim, mu.1.sim, mu.0.sim, each n by sims (observation-major here: [i * sims + k])
    let (mu, e5) = mem.alloc[f64](a, n * sims)
    let (mu1, e6) = mem.alloc[f64](a, n * sims)
    let (mu0, e7) = mem.alloc[f64](a, n * sims)
    if e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var k = 0usize
    while k < sims {
        i = 0usize
        while i < n {
            var s = 0.0f64
            var s1 = 0.0f64
            var s0 = 0.0f64
            var c = 0usize
            while c < pm {
                let b = msim[k * pm + c]
                s += xm[i * pm + c] * b
                var x1 = xm[i * pm + c]
                var x0 = xm[i * pm + c]
                if c == tm {
                    x1 = 1.0f64
                    x0 = 0.0f64
                }
                s1 += x1 * b
                s0 += x0 * b
                c += 1usize
            }
            mu[i * sims + k] = s
            mu1[i * sims + k] = s1
            mu0[i * sims + k] = s0
            i += 1usize
        }
        k += 1usize
    }
    let low = (1.0f64 - conf) / 2.0f64
    let high = 1.0f64 - low
    let pa = py + 1usize
    let (lam, e8) = mem.alloc[f64](a, n)
    let (adj, e9) = mem.alloc[f64](a, n)
    let (wv, e10) = mem.alloc[f64](a, n)
    let (xa, e11) = mem.alloc[f64](a, n * pa)
    let (ysr, e12) = mem.alloc[f64](a, n)
    let (ba, e13) = mem.alloc[f64](a, pa)
    let (ca, e14) = mem.alloc[f64](a, pa * pa)
    let (by, e15) = mem.alloc[f64](a, py)
    let (cy, e16) = mem.alloc[f64](a, py * py)
    let (df0, e17) = mem.alloc[f64](a, n)
    let (srt, e18) = mem.alloc[f64](a, sims)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret mem.Full }
    var sm: [4][]f64 = zero
    var q = 0usize
    while q < 4usize {
        let (v, ev) = mem.alloc[f64](a, sims)
        if ev != ok { ret ev }
        sm[q] = v
        q += 1usize
    }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < py {
            xa[i * pa + c] = xy[i * py + c]
            c += 1usize
        }
        i += 1usize
    }
    var ri = 0usize
    while ri < nr {
        let rho = -1.0f64 + rho_by + f64(ri) * rho_by
        k = 0usize
        while k < sims {
            let start = mem.mark(a)
            i = 0usize
            while i < n {
                let m = mb[i]
                let mu_i = mu[i * sims + k]
                let l = (m * dn(0.0f64 - mu_i) - (1.0f64 - m) * dn(0.0f64 - mu_i)) / (m * pn(mu_i) + (1.0f64 - m) * pn(0.0f64 - mu_i))
                lam[i] = l
                adj[i] = l * rho
                wv[i] = 1.0f64 - rho * rho * l * (l + mu_i)
                xa[i * pa + py] = adj[i]
                i += 1usize
            }
            // lm drops an aliased column: at rho = 0 the correction term is all zeros
            var rss0 = 0.0f64
            var ew0 = ok
            var df0n = n - pa
            if rho == 0.0f64 {
                let (rr, ee) = wls(a, xy, yy, wv, n, py, by, cy)
                rss0 = rr
                ew0 = ee
                df0n = n - py
            } else {
                let (rr, ee) = wls(a, xa, yy, wv, n, pa, ba, ca)
                rss0 = rr
                ew0 = ee
            }
            if ew0 != ok { ret ew0 }
            var sigma3 = math.sqrt[f64](rss0 / f64(df0n))
            var dif = 1.0f64
            var sigt = 0.0f64
            while math.abs[f64](dif) > eps {
                i = 0usize
                while i < n {
                    ysr[i] = yy[i] - sigma3 * adj[i]
                    i += 1usize
                }
                let (rss1, ew1) = wls(a, xy, ysr, wv, n, py, by, cy)
                if ew1 != ok { ret ew1 }
                sigt = math.sqrt[f64](rss1 / f64(n - py))
                dif = sigt - sigma3
                sigma3 = sigt
            }
            i = 0usize
            while i < py * py {
                cy[i] = cy[i] * (sigt * sigt)
                i += 1usize
            }
            let (dr, edr) = mv.rmvnorm(a, g, 1usize, by, cy, py, 0u8)
            if edr != ok { ret edr }
            var dr0 = 0.0f64
            var dr1 = 0.0f64
            var z0v = 0.0f64
            var z1v = 0.0f64
            let cmed = dr[my]
            let ctr = dr[ty]
            if int {
                let ctm = dr[tmy]
                i = 0usize
                while i < n {
                    df0[i] = (cmed + ctm) * (pn(mu1[i * sims + k]) - pn(mu0[i * sims + k]))
                    i += 1usize
                }
                dr1 = sum_ld(df0) / f64(n)
                i = 0usize
                while i < n {
                    df0[i] = cmed * (pn(mu1[i * sims + k]) - pn(mu0[i * sims + k]))
                    i += 1usize
                }
                dr0 = sum_ld(df0) / f64(n)
                // the single-index element of the n by sims matrix, column-major
                let lr = k % n
                let lc = k / n
                let m1 = mu1[lr * sims + lc]
                let m0 = mu0[lr * sims + lc]
                i = 0usize
                while i < n {
                    df0[i] = (ctr + ctm) * pn(mu1[i * sims + k]) + ctr * pn(0.0f64 - m1)
                    i += 1usize
                }
                z1v = sum_ld(df0) / f64(n)
                i = 0usize
                while i < n {
                    df0[i] = (ctr + ctm) * pn(mu0[i * sims + k]) + ctr * pn(0.0f64 - m0)
                    i += 1usize
                }
                z0v = sum_ld(df0) / f64(n)
            } else {
                i = 0usize
                while i < n {
                    df0[i] = cmed * (pn(mu1[i * sims + k]) - pn(mu0[i * sims + k]))
                    i += 1usize
                }
                dr0 = sum_ld(df0) / f64(n)
                dr1 = dr0
                z0v = ctr
                z1v = ctr
            }
            sm[0usize][k] = dr0
            sm[1usize][k] = dr1
            sm[2usize][k] = z0v
            sm[3usize][k] = z1v
            mem.reset(a, start)
            k += 1usize
        }
        q = 0usize
        while q < 26usize {
            out[q * nr + ri] = nan
            q += 1usize
        }
        q = 0usize
        while q < 4usize {
            k = 0usize
            while k < sims {
                srt[k] = sm[q][k]
                k += 1usize
            }
            sort_in_place(srt)
            out[(3usize * q) * nr + ri] = mean_of(sm[q])
            out[(3usize * q + 1usize) * nr + ri] = quant_r(srt, low)
            out[(3usize * q + 2usize) * nr + ri] = quant_r(srt, high)
            var ind = 0.0f64
            if out[(3usize * q + 1usize) * nr + ri] < 0.0f64 && out[(3usize * q + 2usize) * nr + ri] > 0.0f64 { ind = 1.0f64 }
            out[(21usize + q) * nr + ri] = ind
            q += 1usize
        }
        ri += 1usize
    }
    // R squared: the latent variance share of the mediator model, the least squares fit of the outcome
    let (fit, ef2) = mem.alloc[f64](a, n)
    let (b2, e19) = mem.alloc[f64](a, py)
    let (c2, e20) = mem.alloc[f64](a, py * py)
    if ef2 != ok || e19 != ok || e20 != ok { ret mem.Full }
    i = 0usize
    while i < n {
        fit[i] = dot_row(xm, i * pm, bm, pm)
        i += 1usize
    }
    let vm = sample_var(fit)
    let rsm = vm / (1.0f64 + vm)
    let (rssy, rsy, eq) = lm_rsq(a, xy, yy, n, py, b2, c2)
    if eq != ok { ret eq }
    put_thresholds(out, nr, rho_by, out[0usize..nr], out[3usize * nr..4usize * nr], out[6usize * nr..7usize * nr], out[9usize * nr..10usize * nr], int, rsm, rsy)
    i = 0usize
    while i < nr {
        let rho = -1.0f64 + rho_by + f64(i) * rho_by
        out[25usize * nr + i] = rho * rho * (1.0f64 - rsm) * (1.0f64 - rsy)
        i += 1usize
    }
    ret ok
}
