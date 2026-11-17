// R mclust: mclustBootstrapLRT(data, modelName, nboot, level, maxG) with the stream of set.seed.
//
// The parametric bootstrap draws through sim() from the fit under H0, so the covariance structures whose draws depend on the signs of an orientation matrix
// (EVE, VEE, VVE, EEV, VEV, EVV) are not supported; the others are: E, V, EII, VII, EEI, VEI, EVI, VVI, EEE, VVV.

use e.math
use e.mem
use e.algo.rand.r as rng
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustem as em
use e.algo.stat.mclustfit as mf
use e.algo.stat.mclustsim as ms

// the sim() parameters of a fit: the model code and the scale, shape, orientation and sigma vectors the sim_draw layout expects
fn sim_params(model: usize, g: usize, p: usize, sigma: []const f64, scale: []f64, shape: []f64, sg: []f64) -> usize {
    var q = 0usize
    if model == 0usize || model == 1usize || model == 2usize || model == 3usize {
        var k = 0usize
        while k < g {
            sg[k] = sigma[k * p * p]
            k += 1usize
        }
        if model < 2usize { ret 1usize }
        ret 3usize
    }
    if model >= 4usize && model <= 7usize {
        // a diagonal structure is the product of scale and shape: draw as VVI with scale one
        var k = 0usize
        while k < g {
            scale[k] = 1.0f64
            var j = 0usize
            while j < p {
                shape[k * p + j] = sigma[k * p * p + j * p + j]
                j += 1usize
            }
            k += 1usize
        }
        ret 7usize
    }
    q = 0usize
    while q < g * p * p {
        sg[q] = sigma[q]
        q += 1usize
    }
    if model == 8usize { ret 15usize }
    ret model
}

// the log likelihood of the EM started from the parameters (pro, mu, sigma) of a fit with g groups at the bootstrap sample x; NaN on failure
fn em_from(a: *mem.Arena, model: usize, x: []const f64, n: usize, p: usize, g: usize, pro: []const f64, mu: []const f64, sigma: []const f64) -> f64 {
    let (res, e1) = mem.alloc[f64](a, 2usize * n * g + 2usize * n + 1usize)
    let (z, e2) = mem.alloc[f64](a, n * g)
    let (pro2, e3) = mem.alloc[f64](a, g)
    let (mu2, e4) = mem.alloc[f64](a, g * p)
    let (sg2, e5) = mem.alloc[f64](a, g * p * p)
    let (inf, e6) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mf.nan() }
    if mf.predict_run(a, x, n, p, g, pro, mu, sigma, res) != ok { ret mf.nan() }
    var q = 0usize
    while q < n * g {
        z[q] = res[n * g + q]
        q += 1usize
    }
    ret em.me_any(a, model, false, x, z, n, p, g, pro2, mu2, sg2, inf)
}

// mclustBootstrapLRT after set.seed(seed): out holds, per tested g = 1 .. gout, the observed statistic (index g - 1), the p value (gout + g - 1) and the bootstrap statistics (2 gout + (g - 1) nboot + b);
// maxg = 0 stands for maxG = NULL (G up to 9 with the stop at the first p value above level). Returns the number of tested g in gcount
fn boot_lrt(a: *mem.Arena, x: []const f64, n: usize, p: usize, model: usize, nboot: usize, level: f64, maxg: usize, seed: i64, out: []f64, gcount: *usize) -> err {
    var gtop = 9usize
    if maxg > 0usize { gtop = maxg + 1usize }
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    let (pairs, e1) = mem.alloc[usize](a, 2usize * n)
    if e1 != ok { ret mem.Full }
    if p > 1usize {
        let pe = mf.default_pairs(a, x, n, p, pairs)
        if pe != ok { ret pe }
    }
    let gm1 = gtop - 1usize
    let (z0, f1) = mem.alloc[f64](a, n * gtop)
    let (pro0, f2) = mem.alloc[f64](a, gtop)
    let (mu0, f3) = mem.alloc[f64](a, gtop * p)
    let (sg0, f4) = mem.alloc[f64](a, gtop * p * p)
    let (z1, f5) = mem.alloc[f64](a, n * gtop)
    let (pro1, f6) = mem.alloc[f64](a, gtop)
    let (mu1, f7) = mem.alloc[f64](a, gtop * p)
    let (sg1, f8) = mem.alloc[f64](a, gtop * p * p)
    let (scale, f9) = mem.alloc[f64](a, gtop)
    let (shape, f10) = mem.alloc[f64](a, gtop * p)
    let (sgm, f11) = mem.alloc[f64](a, gtop * p * p)
    let (grp, f12) = mem.alloc[f64](a, n)
    let (xb, f13) = mem.alloc[f64](a, n * p)
    let (nul, f14) = mem.alloc[f64](a, 1usize)
    let (sgb, f15) = mem.alloc[f64](a, gtop * p)
    if f15 != ok { ret mem.Full }
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok || f11 != ok || f12 != ok || f13 != ok || f14 != ok { ret mem.Full }
    var g = 0usize
    var go = true
    var lastg = 0usize
    while g < gm1 && go {
        g += 1usize
        let start = mem.mark(a)
        var sgn0: []f64 = zero
        if model == 8usize { sgn0 = sgb[0usize..p] }
        if model == 15usize { sgn0 = sgb[0usize..g * p] }
        let ll0 = mf.final_fit_s(a, x, n, p, g, model, pairs, z0[0usize..n * g], pro0, mu0, sg0, sgn0)
        if g == 1usize && p > 1usize && (model == 8usize || model == 15usize) {
            // mvnXXX: one group, weights one
            let (ones, o1) = mem.alloc[f64](a, n)
            let (mm1, o2) = mem.alloc[f64](a, p)
            if o1 != ok || o2 != ok { ret mem.Full }
            var q = 0usize
            while q < n {
                ones[q] = 1.0f64
                q += 1usize
            }
            q = 0usize
            while q < p {
                mm1[q] = mu0[q]
                q += 1usize
            }
            mp.givens_signs(a, 4usize, x, ones, n, p, 1usize, mm1, sgb[0usize..p])
        }
        if model == 8usize {
            // the sim layout of VVV carries one sign block per group: repeat the pooled signs
            var kk = 1usize
            while kk < g {
                var jj = 0usize
                while jj < p {
                    sgb[kk * p + jj] = sgb[jj]
                    jj += 1usize
                }
                kk += 1usize
            }
            sgn0 = sgb[0usize..g * p]
        }
        let ll1 = mf.final_fit(a, x, n, p, g + 1usize, model, pairs, z1[0usize..n * (g + 1usize)], pro1, mu1, sg1)
        if ll0 != ll0 || ll1 != ll1 { ret mem.Full }
        let obs = 2.0f64 * (ll1 - ll0)
        out[g - 1usize] = obs
        let simmodel = sim_params(model, g, p, sg0, scale, shape, sgm)
        var cnt = 0usize
        var b = 0usize
        var tries = 0usize
        while b < nboot && tries < 100000usize {
            tries += 1usize
            let se = ms.sim_draw(a, &r, simmodel, p, g, n, pro0, mu0, scale, shape, nul, sgm, sgn0, grp, xb)
            if se != ok { ret se }
            var l0 = 0.0f64
            if g == 1usize {
                // the one-component fit is mvnX or mvnXXX: the maximum likelihood fit of the sample
                var fm = 15usize
                if p == 1usize { fm = 0usize }
                let (mm, h1) = mem.alloc[f64](a, p)
                let (ss, h2) = mem.alloc[f64](a, p * p)
                if h1 != ok || h2 != ok { ret mem.Full }
                l0 = mf.mvn_fit(a, fm, xb, n, p, mm, ss)
            } else {
                l0 = em_from(a, model, xb, n, p, g, pro0, mu0, sg0)
            }
            let l1 = em_from(a, model, xb, n, p, g + 1usize, pro1, mu1, sg1)
            let lr = 2.0f64 * (l1 - l0)
            if lr == lr {
                out[2usize * gm1 + (g - 1usize) * nboot + b] = lr
                if lr >= obs { cnt += 1usize }
                b += 1usize
            }
        }
        let pv = (1.0f64 + f64(cnt)) / f64(nboot + 1usize)
        out[gm1 + g - 1usize] = pv
        lastg = g
        if maxg == 0usize && pv > level { go = false }
        mem.reset(a, start)
    }
    *gcount = lastg
    ret ok
}
