// R mediation::mediate for a linear mediator model and a linear outcome model without a treatment-mediator interaction, the quasi-Bayesian simulation (boot = FALSE): the coefficients of both models are drawn from
// their normal approximation with mvtnorm::rmvnorm (the mediator model first, then the outcome model, from one stream), and for a linear outcome the average causal mediation effect of every draw is the product
// of the treatment coefficient of the mediator model and the mediator coefficient of the outcome model (the simulated mediator errors cancel in the difference), the direct effect the outcome model's treatment
// coefficient. Summaries as mediate: means (the median for the proportion mediated), percentile intervals and the simulation p value.
//
// Not here: interactions, other families, factors, bootstrap, mixed models, sensitivity analysis.

use e.algo.rand.r as rng
use e.algo.stat.mvtnorm as mv
use e.math
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
