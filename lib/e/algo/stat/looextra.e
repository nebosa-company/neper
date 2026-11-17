// R loo, the rest: loo with a relative efficiency per observation (relative_eff, the standard errors, mcse_elpd and the PSIS effective sample size), pointwise waic, E_loo (mean, variance, sd, quantile and its Pareto k), loo_compare over any number of models, and loo_model_weights (stacking through constrOptim over R's BFGS, pseudo-BMA with and without the Bayesian bootstrap).
//
// ll is nobs blocks of s draws (a block's draws chain by chain); lpd_point is nobs rows of k models, row-major.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.loopkg as lp
use e.algo.stat.posteriorpkg as pp
use e.algo.stat.rbfgs as bf
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// relative_eff of one observation's draws: ess_mean over the chains of n draws, divided by S
fn relative_eff(a: *mem.Arena, blk: []const f64, nchain: usize, n: usize) -> f64 {
    ret pp.ess_mean(a, blk, nchain, n) / f64(nchain * n)
}

// loo(ll, r_eff): per observation into out (nobs rows of elpd_loo, mcse_elpd_loo, p_loo, pareto k, psis n_eff); reff has one value per observation
fn loo_full(a: *mem.Arena, ll: []const f64, s: usize, nobs: usize, reff: []const f64, out: []f64) -> err {
    ret loo_full_m(a, ll, s, nobs, reff, 0usize, out)
}

// the importance weights of loo's is_method: 0 psis, 1 tis (truncation at sqrt(S) times the mean ratio), 2 sis (raw); lw gets the unnormalised log weights, the Pareto k is 0 for tis and sis
fn is_weights(a: *mem.Arena, lr: []const f64, lw: []f64, r_eff: f64, method: usize) -> (f64, err) {
    if method == 0usize {
        let (k, e) = lp.psis_i_r(a, lr, lw, r_eff)
        ret (k, e)
    }
    let sf = f64(lr.len)
    let cut = lp.logsumexp(lr) - math.log[f64](sf) + 0.5f64 * math.log[f64](sf)
    var i = 0usize
    while i < lr.len {
        lw[i] = lr[i]
        if method == 1usize && lr[i] > cut { lw[i] = cut }
        i += 1usize
    }
    ret (0.0f64, ok)
}

// loo(ll, r_eff, is_method): as loo_full for psis (method 0), tis (1) or sis (2)
fn loo_full_m(a: *mem.Arena, ll: []const f64, s: usize, nobs: usize, reff: []const f64, method: usize, out: []f64) -> err {
    let (lw, e1) = mem.alloc[f64](a, s)
    let (lr, e2) = mem.alloc[f64](a, s)
    let (t, e3) = mem.alloc[f64](a, s)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var o = 0usize
    while o < nobs {
        let start = mem.mark(a)
        var i = 0usize
        while i < s {
            lr[i] = 0.0f64 - ll[o * s + i]
            i += 1usize
        }
        let (k, pe) = is_weights(a, lr, lw, reff[o], method)
        if pe != ok { ret pe }
        let lse = lp.logsumexp(lw)
        i = 0usize
        var w2 = 0.0f64
        while i < s {
            lw[i] = lw[i] - lse
            t[i] = ll[o * s + i] + lw[i]
            w2 += math.exp[f64](2.0f64 * lw[i])
            i += 1usize
        }
        let elpd = lp.logsumexp(t)
        let lpd = lp.logsumexp(ll[o * s..(o + 1usize) * s]) - math.log[f64](f64(s))
        let ee = math.exp[f64](elpd)
        var v = 0.0f64
        i = 0usize
        while i < s {
            let d = math.exp[f64](ll[o * s + i]) - ee
            v += math.exp[f64](2.0f64 * lw[i]) * d * d
            i += 1usize
        }
        v = v / reff[o]
        out[o * 5usize] = elpd
        out[o * 5usize + 1usize] = math.sqrt[f64](math.log[f64](1.0f64 + v / (ee * ee)))
        out[o * 5usize + 2usize] = lpd - elpd
        out[o * 5usize + 3usize] = k
        out[o * 5usize + 4usize] = 1.0f64 / w2 * reff[o]
        mem.reset(a, start)
        o += 1usize
    }
    ret ok
}

// sum and sqrt(N var) of the column col of an nobs by width row-major table
fn estimate(tab: []const f64, nobs: usize, width: usize, col: usize) -> (f64, f64) {
    var m = 0.0f64
    var i = 0usize
    while i < nobs {
        m += tab[i * width + col]
        i += 1usize
    }
    let mean = m / f64(nobs)
    var v = 0.0f64
    i = 0usize
    while i < nobs {
        let d = tab[i * width + col] - mean
        v += d * d
        i += 1usize
    }
    ret (m, math.sqrt[f64](f64(nobs) * v / f64(nobs - 1usize)))
}

// waic(ll) per observation into out (nobs rows of elpd_waic, p_waic)
fn waic_pointwise(ll: []const f64, s: usize, nobs: usize, out: []f64) {
    var o = 0usize
    while o < nobs {
        let blk = ll[o * s..(o + 1usize) * s]
        let lpd = lp.logsumexp(blk) - math.log[f64](f64(s))
        var m = 0.0f64
        var i = 0usize
        while i < s {
            m += blk[i]
            i += 1usize
        }
        m = m / f64(s)
        var v = 0.0f64
        i = 0usize
        while i < s {
            v += (blk[i] - m) * (blk[i] - m)
            i += 1usize
        }
        v = v / f64(s - 1usize)
        out[o * 2usize] = lpd - v
        out[o * 2usize + 1usize] = v
        o += 1usize
    }
}

// loo_compare: the elpd differences of every model against the best (largest total elpd), and their standard errors, from the pointwise elpd_loo of k models (nobs rows of k, row-major): into out (k rows of elpd_diff, se_diff) in the input order; returns the index of the best model
fn compare(pt: []const f64, nobs: usize, k: usize, out: []f64) -> usize {
    var best = 0usize
    var bt = -1.0f64 / 0.0f64
    var j = 0usize
    while j < k {
        var t = 0.0f64
        var i = 0usize
        while i < nobs {
            t += pt[i * k + j]
            i += 1usize
        }
        if t > bt {
            bt = t
            best = j
        }
        j += 1usize
    }
    j = 0usize
    while j < k {
        var m = 0.0f64
        var i = 0usize
        while i < nobs {
            m += pt[i * k + j] - pt[i * k + best]
            i += 1usize
        }
        let md = m / f64(nobs)
        var v = 0.0f64
        i = 0usize
        while i < nobs {
            let d = pt[i * k + j] - pt[i * k + best] - md
            v += d * d
            i += 1usize
        }
        out[j * 2usize] = m
        out[j * 2usize + 1usize] = math.sqrt[f64](f64(nobs) * v / f64(nobs - 1usize))
        j += 1usize
    }
    ret best
}

// loo's weighted quantile (.wquant) of x with weights w at prob
fn wquant(a: *mem.Arena, x: []const f64, w: []const f64, prob: f64) -> f64 {
    let s = x.len
    var same = true
    var i = 0usize
    while i < s {
        if w[i] != w[0usize] { same = false }
        i += 1usize
    }
    let (ord, e) = mem.alloc[usize](a, s)
    let (ww, e2) = mem.alloc[f64](a, s)
    if e != ok || e2 != ok { ret nan() }
    i = 0usize
    while i < s {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < s {
        let v = ord[i]
        var j = i
        while j > 0usize && x[ord[j - 1usize]] > x[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    if same { ret pp.quantile_of(a, x, prob) }
    var c = 0.0f64
    i = 0usize
    while i < s {
        c += w[ord[i]]
        ww[i] = c
        i += 1usize
    }
    i = 0usize
    while i < s {
        ww[i] = ww[i] / c
        i += 1usize
    }
    var wi = 0usize
    while wi < s && !(ww[wi] >= prob) { wi += 1usize }
    if wi == 0usize { ret x[ord[0usize]] }
    let w1 = ww[wi - 1usize]
    let x1 = x[ord[wi - 1usize]]
    ret x1 + (x[ord[wi]] - x1) * (prob - w1) / (ww[wi] - w1)
}

// E_loo(x, psis) for one observation (log ratios lr, relative efficiency r_eff; type 0 mean, 1 variance, 2 sd, 3 quantile at prob): (value, Pareto k of the estimate)
fn e_loo(a: *mem.Arena, x: []const f64, lr: []const f64, r_eff: f64, kind: usize, prob: f64) -> (f64, f64, err) {
    let s = lr.len
    let sf = f64(s)
    let (lw, e1) = mem.alloc[f64](a, s)
    let (w, e2) = mem.alloc[f64](a, s)
    let (rt, e3) = mem.alloc[f64](a, s)
    let (hr, e4) = mem.alloc[f64](a, s)
    let (sc, e5) = mem.alloc[f64](a, s)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (nan(), nan(), e1) }
    let (k0, pe) = lp.psis_i_r(a, lr, lw, r_eff)
    if pe != ok { ret (nan(), nan(), pe) }
    let lse = lp.logsumexp(lw)
    var i = 0usize
    var w2 = 0.0f64
    var mx = 0.0f64 - 1.0f64 / 0.0f64
    while i < s {
        lw[i] = lw[i] - lse
        w[i] = math.exp[f64](lw[i])
        w2 += w[i] * w[i]
        if lw[i] > mx { mx = lw[i] }
        i += 1usize
    }
    var m1 = 0.0f64
    var m2 = 0.0f64
    i = 0usize
    while i < s {
        m1 += w[i] * x[i]
        m2 += w[i] * x[i] * x[i]
        i += 1usize
    }
    var val = 0.0f64
    if kind == 0usize { val = m1 }
    if kind == 1usize || kind == 2usize {
        val = (m2 - m1 * m1) / (1.0f64 - w2)
        if kind == 2usize { val = math.sqrt[f64](val) }
    }
    if kind == 3usize { val = wquant(a, x, w, prob) }
    var tl = usize(math.ceil[f64](math.min[f64](0.2f64 * sf, 3.0f64 * math.sqrt[f64](sf / r_eff))))
    i = 0usize
    while i < s {
        rt[i] = math.exp[f64](lw[i] - mx)
        i += 1usize
    }
    let (kr, _a, _b, _c, e6) = pp.pareto_smooth_nt(a, rt, 1usize, 1.0f64, tl, false, sc)
    if e6 != ok { ret (nan(), nan(), e6) }
    let (h, e8) = mem.alloc[f64](a, s)
    if e8 != ok { ret (nan(), nan(), e8) }
    i = 0usize
    while i < s {
        h[i] = x[i]
        if kind == 1usize || kind == 2usize { h[i] = x[i] * x[i] }
        i += 1usize
    }
    var lo = h[0usize]
    var hi = h[0usize]
    var distinct = 0usize
    var finite = true
    i = 0usize
    while i < s {
        if h[i] < lo { lo = h[i] }
        if h[i] > hi { hi = h[i] }
        if h[i] != h[i] || h[i] - h[i] != 0.0f64 { finite = false }
        i += 1usize
    }
    // exactly two distinct values
    var v1 = h[0usize]
    var v2 = h[0usize]
    var have2 = false
    var more = false
    i = 0usize
    while i < s {
        if h[i] != v1 {
            if !have2 {
                v2 = h[i]
                have2 = true
            } else if h[i] != v2 {
                more = true
            }
        }
        i += 1usize
    }
    distinct = 1usize
    if have2 { distinct = 2usize }
    if more { distinct = 3usize }
    if kind == 3usize || !finite || math.abs[f64](hi - lo) < 2.220446049250313e-16f64 || distinct == 2usize {
        ret (val, kr, ok)
    }
    i = 0usize
    while i < s {
        hr[i] = h[i] * rt[i]
        i += 1usize
    }
    let (khr, _d, _e, _f, e7) = pp.pareto_smooth_nt(a, hr, 0usize, 1.0f64, tl, false, sc)
    if e7 != ok { ret (nan(), nan(), e7) }
    var k = kr
    if khr == khr && (kr != kr || khr > kr) { k = khr }
    if khr != khr && kr != kr { k = nan() }
    ret (val, k, ok)
}

type Stack = struct { lpd: []const f64, n: usize, k: usize, mu: f64, old: []f64, wf: []f64 }

// stacking's negative log score at the K - 1 free weights
fn neg_log_score(c: *Stack, th: []const f64) -> f64 {
    let k = c.k
    var sm = 0.0f64
    var j = 0usize
    while j < k - 1usize {
        sm += th[j]
        j += 1usize
    }
    var tot = 0.0f64
    var i = 0usize
    while i < c.n {
        var m = 0.0f64 - 1.0f64 / 0.0f64
        j = 0usize
        while j < k {
            var wj = 1.0f64 - sm
            if j < k - 1usize { wj = th[j] }
            c.wf[j] = c.lpd[i * k + j] + math.log[f64](wj)
            if c.wf[j] > m { m = c.wf[j] }
            j += 1usize
        }
        tot += lp.logsumexp(c.wf)
        i += 1usize
    }
    ret 0.0f64 - tot
}

fn neg_log_grad(c: *Stack, th: []const f64, g: []f64) {
    let k = c.k
    var sm = 0.0f64
    var j = 0usize
    while j < k - 1usize {
        sm += th[j]
        j += 1usize
    }
    j = 0usize
    while j < k - 1usize {
        g[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < c.n {
        var ml = c.lpd[i * k]
        j = 0usize
        while j < k {
            if c.lpd[i * k + j] > ml { ml = c.lpd[i * k + j] }
            var wj = 1.0f64 - sm
            if j < k - 1usize { wj = th[j] }
            c.wf[j] = c.lpd[i * k + j] + math.log[f64](wj)
            j += 1usize
        }
        let den = math.exp[f64](lp.logsumexp(c.wf) - ml)
        j = 0usize
        while j < k - 1usize {
            g[j] += (math.exp[f64](c.lpd[i * k + j] - ml) - math.exp[f64](c.lpd[i * k + k - 1usize] - ml)) / den
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < k - 1usize {
        g[j] = 0.0f64 - g[j]
        j += 1usize
    }
}

// constrOptim's barrier function R(theta, theta.old)
fn barrier(c: *Stack, th: []const f64) -> f64 {
    let k = c.k
    var sm = 0.0f64
    var j = 0usize
    while j < k - 1usize {
        sm += th[j]
        j += 1usize
    }
    var smo = 0.0f64
    j = 0usize
    while j < k - 1usize {
        smo += c.old[j]
        j += 1usize
    }
    let g0 = 1.0f64 - sm
    if g0 < 0.0f64 { ret nan() }
    j = 0usize
    while j < k - 1usize {
        if th[j] < 0.0f64 { ret nan() }
        j += 1usize
    }
    var bar = (1.0f64 - smo) * math.log[f64](g0) + sm
    j = 0usize
    while j < k - 1usize {
        bar += c.old[j] * math.log[f64](th[j]) - th[j]
        j += 1usize
    }
    if bar != bar || bar - bar != 0.0f64 { bar = 0.0f64 - 1.0f64 / 0.0f64 }
    ret neg_log_score(c, th) - c.mu * bar
}

fn barrier_grad(c: *Stack, th: []const f64, g: []f64) {
    let k = c.k
    neg_log_grad(c, th, g)
    var sm = 0.0f64
    var smo = 0.0f64
    var j = 0usize
    while j < k - 1usize {
        sm += th[j]
        smo += c.old[j]
        j += 1usize
    }
    let g0 = 1.0f64 - sm
    let g0o = 1.0f64 - smo
    j = 0usize
    while j < k - 1usize {
        let dbar = 0.0f64 - g0o / g0 + c.old[j] / th[j]
        g[j] = g[j] - c.mu * dbar
        j += 1usize
    }
}

// stacking_weights(lpd_point) into w (k values): constrOptim from the equal weights over R's BFGS
fn stacking_weights(a: *mem.Arena, lpd: []const f64, n: usize, k: usize, w: []f64) -> err {
    let (old, e1) = mem.alloc[f64](a, k)
    let (th, e2) = mem.alloc[f64](a, k)
    let (wf, e3) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var c = Stack { lpd: lpd, n: n, k: k, mu: 0.0001f64, old: old, wf: wf }
    var j = 0usize
    while j < k - 1usize {
        th[j] = 1.0f64 / f64(k)
        old[j] = th[j]
        j += 1usize
    }
    var obj = neg_log_score(&c, th)
    var r = barrier(&c, th)
    var iter = 0usize
    while iter < 100usize {
        iter += 1usize
        let obj_old = obj
        let r_old = r
        j = 0usize
        while j < k - 1usize {
            old[j] = th[j]
            j += 1usize
        }
        let start = mem.mark(a)
        let b = th[0usize..k - 1usize]
        let fv = bf.vmmin[Stack](a, &c, barrier, barrier_grad, b, 1.490116119384766e-08f64, 100usize)
        r = fv
        if r - r == 0.0f64 && r_old - r_old == 0.0f64 && math.abs[f64](r - r_old) < (0.001f64 + math.abs[f64](r)) * 1.0e-5f64 { break }
        obj = neg_log_score(&c, th)
        if obj > obj_old { break }
        let _ = start
    }
    var sm = 0.0f64
    j = 0usize
    while j < k - 1usize {
        w[j] = th[j]
        sm += th[j]
        j += 1usize
    }
    w[k - 1usize] = 1.0f64 - sm
    ret ok
}

// pseudobma_weights(lpd_point, BB = FALSE) into w
fn pseudobma_weights(lpd: []const f64, n: usize, k: usize, w: []f64) {
    var mx = 0.0f64 - 1.0f64 / 0.0f64
    var j = 0usize
    while j < k {
        var t = 0.0f64
        var i = 0usize
        while i < n {
            t += lpd[i * k + j]
            i += 1usize
        }
        w[j] = t
        if t > mx { mx = t }
        j += 1usize
    }
    var s = 0.0f64
    j = 0usize
    while j < k {
        w[j] = math.exp[f64](w[j] - mx)
        s += w[j]
        j += 1usize
    }
    j = 0usize
    while j < k {
        w[j] = w[j] / s
        j += 1usize
    }
}

// pseudobma_weights(lpd_point, BB = TRUE, BB_n, alpha) after set.seed(seed): the Dirichlet draws come from rgamma row by row
fn pseudobma_bb(a: *mem.Arena, lpd: []const f64, n: usize, k: usize, seed: i64, bbn: usize, alpha: f64, w: []f64) -> err {
    let (bw, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var j = 0usize
    while j < k {
        w[j] = 0.0f64
        j += 1usize
    }
    var z: [16]f64 = zero
    var b = 0usize
    while b < bbn {
        var tot = 0.0f64
        var i = 0usize
        while i < n {
            bw[i] = rd.rgamma(&r, alpha, 1.0f64)
            tot += bw[i]
            i += 1usize
        }
        var mx = 0.0f64 - 1.0f64 / 0.0f64
        j = 0usize
        while j < k {
            var t = 0.0f64
            i = 0usize
            while i < n {
                t += bw[i] / tot * lpd[i * k + j]
                i += 1usize
            }
            z[j] = t * f64(n)
            if z[j] > mx { mx = z[j] }
            j += 1usize
        }
        var s = 0.0f64
        j = 0usize
        while j < k {
            z[j] = math.exp[f64](z[j] - mx)
            s += z[j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            w[j] += z[j] / s
            j += 1usize
        }
        b += 1usize
    }
    j = 0usize
    while j < k {
        w[j] = w[j] / f64(bbn)
        j += 1usize
    }
    ret ok
}
