// R mclust: mclustBIC / Mclust with prior = priorControl() (defaultPrior per fit, shrinkage 0.01).
//
// mclust drops EVE, VEE, VVE and EVV when a prior is given, so models must not hold 9, 10, 11 or 14.
// Same result layout as mclustfit.mclust_run without the ICL block.

use e.math
use e.mem
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustem as em
use e.algo.stat.mclustfit as mf
use e.algo.stat.mclustprior as pr

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

// the one group fit with the prior (mvn of mclust): fills mu (p) and sg (p by p) and returns the log likelihood (NaN on failure)
fn mvn_prior(a: *mem.Arena, model: usize, x: []const f64, n: usize, p: usize, mu: []f64, sg: []f64) -> f64 {
    let (pmu, e1) = mem.alloc[f64](a, p)
    let (psc, e2) = mem.alloc[f64](a, p * p)
    let (z1, e3) = mem.alloc[f64](a, n)
    let (pro, e4) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nanv() }
    let dof = pr.default_prior(x, n, p, 1usize, model, pmu, psc)
    let shrk = 0.01f64
    var i = 0usize
    while i < n {
        z1[i] = 1.0f64
        i += 1usize
    }
    var extra = 0.0f64
    if shrk > 0.0f64 { extra = 1.0f64 }
    var mm = model
    if model >= 4usize && model <= 6usize { mm = 7usize }
    if model >= 8usize { mm = 15usize }
    if model == 2usize || model == 3usize {
        // mnxiip: the scatter about the unshrunk mean plus the shrinkage term
        let nn = f64(n)
        var sum = 0.0f64
        var dd = 0.0f64
        var j = 0usize
        while j < p {
            var m = 0.0f64
            i = 0usize
            while i < n {
                m += x[j * n + i]
                i += 1usize
            }
            m = m / nn
            i = 0usize
            while i < n {
                sum += (x[j * n + i] - m) * (x[j * n + i] - m)
                i += 1usize
            }
            dd += (pmu[j] - m) * (pmu[j] - m)
            mu[j] = (nn * m + shrk * pmu[j]) / (nn + shrk)
            j += 1usize
        }
        let sig = (psc[0usize] + shrk * nn / (shrk + nn) * dd + sum) / (dof + nn * f64(p) + 2.0f64 + extra * f64(p))
        var b = 0usize
        while b < p * p {
            sg[b] = 0.0f64
            b += 1usize
        }
        j = 0usize
        while j < p {
            sg[j * p + j] = sig
            j += 1usize
        }
    } else {
        if pr.mstep_prior(a, mm, x, z1, n, p, 1usize, shrk, pmu, psc, dof, pro, mu, sg) != ok { ret nanv() }
    }
    let zz = z1
    pro[0usize] = 1.0f64
    ret em.estep_gen(a, x, n, p, 1usize, mu, sg, pro, zz)
}

// one fit at (g, model) from the hierarchy pairs: the log likelihood, with z, pro, mu and sg filled
fn fit_prior(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, model: usize, pairs: []const usize, z: []f64, pro: []f64, mu: []f64, sg: []f64) -> f64 {
    if g == 1usize {
        let ll = mvn_prior(a, model, x, n, p, mu, sg)
        pro[0usize] = 1.0f64
        var q = 0usize
        while q < n {
            z[q] = 1.0f64
            q += 1usize
        }
        ret ll
    }
    if g > n { ret nanv() }
    let (pmu, e1) = mem.alloc[f64](a, p)
    let (psc, e2) = mem.alloc[f64](a, p * p)
    let (inf, e3) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok { ret nanv() }
    let dof = pr.default_prior(x, n, p, g, model, pmu, psc)
    if mf.start_z(a, x, n, p, g, pairs, z) != ok { ret nanv() }
    ret pr.me_prior(a, model, x, z, n, p, g, 0.01f64, pmu, psc, dof, pro, mu, sg, inf)
}

fn mclust_bic_prior(a: *mem.Arena, x: []const f64, n: usize, p: usize, gmin: usize, gmax: usize, models: []const usize, bicm: []f64) -> err {
    let ng = gmax - gmin + 1usize
    let nm = models.len
    let (pairs, e1) = mem.alloc[usize](a, 2usize * n)
    let (z, e2) = mem.alloc[f64](a, n * gmax)
    let (pro, e3) = mem.alloc[f64](a, gmax)
    let (mu, e4) = mem.alloc[f64](a, gmax * p)
    let (sg, e5) = mem.alloc[f64](a, gmax * p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    if p > 1usize && gmax > 1usize {
        let pe = mf.default_pairs(a, x, n, p, pairs)
        if pe != ok { ret pe }
    }
    var gi = 0usize
    while gi < ng {
        let g = gmin + gi
        var mi = 0usize
        while mi < nm {
            let start = mem.mark(a)
            let ll = fit_prior(a, x, n, p, g, models[mi], pairs, z[0usize..n * g], pro, mu, sg)
            var b = nanv()
            if ll == ll { b = mp.bic(mp.model_name(models[mi]), ll, f64(n), f64(p), f64(g), false, false) }
            bicm[mi * ng + gi] = b
            mem.reset(a, start)
            mi += 1usize
        }
        gi += 1usize
    }
    ret ok
}

// Mclust(data, G = gmin:gmax, modelNames = models, prior = priorControl()): res 0 bic, 1 G, 2 model index, 3 loglik, 4 icl, 5 df, then the BIC matrix (ng by nm), classification (n), uncertainty (n),
// z (n by gmax), pro (gmax), mean (p by gmax), covariances (gmax stacked p by p)
fn mclust_run_prior(a: *mem.Arena, x: []const f64, n: usize, p: usize, gmin: usize, gmax: usize, models: []const usize, res: []f64) -> err {
    let ng = gmax - gmin + 1usize
    let nm = models.len
    let bicm = res[6usize..6usize + ng * nm]
    let be = mclust_bic_prior(a, x, n, p, gmin, gmax, models, bicm)
    if be != ok { ret be }
    var bg = 0usize
    var bm = 0usize
    var found = false
    var gi = 0usize
    while gi < ng {
        var mi = 0usize
        while mi < nm {
            let v = bicm[mi * ng + gi]
            if v == v {
                if !found {
                    bg = gi
                    bm = mi
                    found = true
                } else {
                    let cur = bicm[bm * ng + bg]
                    var better = false
                    if v > cur { better = true }
                    if v == cur {
                        if gi < bg { better = true }
                        if gi == bg && mf.name_less(models[mi], models[bm]) { better = true }
                    }
                    if better {
                        bg = gi
                        bm = mi
                    }
                }
            }
            mi += 1usize
        }
        gi += 1usize
    }
    if !found { ret mem.Full }
    let g = gmin + bg
    let mod = models[bm]
    let off_cl = 6usize + ng * nm
    let off_un = off_cl + n
    let off_z = off_un + n
    let off_pro = off_z + n * gmax
    let off_mu = off_pro + gmax
    let off_sg = off_mu + p * gmax
    let (pairs, e1) = mem.alloc[usize](a, 2usize * n)
    let (z, e2) = mem.alloc[f64](a, n * g)
    let (pro, e3) = mem.alloc[f64](a, g)
    let (mu, e4) = mem.alloc[f64](a, g * p)
    let (sg, e5) = mem.alloc[f64](a, g * p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    if p > 1usize && g > 1usize {
        let pe = mf.default_pairs(a, x, n, p, pairs)
        if pe != ok { ret pe }
    }
    let ll = fit_prior(a, x, n, p, g, mod, pairs, z, pro, mu, sg)
    if ll != ll { ret mem.Full }
    if g > 1usize {
        // the extra M step with the prior when the proportions differ from the column means of z
        var dsum = 0.0f64
        var k = 0usize
        while k < g {
            var cm = 0.0f64
            var i = 0usize
            while i < n {
                cm += z[k * n + i]
                i += 1usize
            }
            cm = cm / f64(n)
            dsum += (pro[k] - cm) * (pro[k] - cm)
            k += 1usize
        }
        if mod != 13usize && dsum > math.sqrt[f64](2.220446049250313e-16f64) {
            let (pmu, e6) = mem.alloc[f64](a, p)
            let (psc, e7) = mem.alloc[f64](a, p * p)
            let (pro2, e8) = mem.alloc[f64](a, g)
            let (mu2, e9) = mem.alloc[f64](a, g * p)
            let (sg2, e10) = mem.alloc[f64](a, g * p * p)
            if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
            let dof = pr.default_prior(x, n, p, g, mod, pmu, psc)
            if pr.mstep_prior(a, mod, x, z, n, p, g, 0.01f64, pmu, psc, dof, pro2, mu2, sg2) == ok {
                var q = 0usize
                while q < g {
                    pro[q] = pro2[q]
                    q += 1usize
                }
                q = 0usize
                while q < g * p {
                    mu[q] = mu2[q]
                    q += 1usize
                }
                q = 0usize
                while q < g * p * p {
                    sg[q] = sg2[q]
                    q += 1usize
                }
            }
        }
    }
    let nparams = mp.n_mclust_params(mp.model_name(mod), f64(p), f64(g), false, false)
    let bicv = mp.bic(mp.model_name(mod), ll, f64(n), f64(p), f64(g), false, false)
    var cplog = 0.0f64
    var i = 0usize
    while i < n {
        var best = 0usize
        var k = 1usize
        while k < g {
            if z[k * n + i] > z[best * n + i] { best = k }
            k += 1usize
        }
        res[off_cl + i] = f64(best + 1usize)
        res[off_un + i] = 1.0f64 - z[best * n + i]
        if z[best * n + i] > 0.0f64 { cplog += math.log[f64](z[best * n + i]) }
        i += 1usize
    }
    res[0usize] = bicv
    res[1usize] = f64(g)
    res[2usize] = f64(mod)
    res[3usize] = ll
    res[4usize] = bicv + 2.0f64 * cplog
    res[5usize] = nparams
    var q = 0usize
    while q < n * gmax {
        res[off_z + q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < n * g {
        res[off_z + q] = z[q]
        q += 1usize
    }
    q = 0usize
    while q < gmax {
        res[off_pro + q] = 0.0f64
        q += 1usize
    }
    q = 0usize
    while q < g {
        res[off_pro + q] = pro[q]
        q += 1usize
    }
    q = 0usize
    while q < g * p {
        res[off_mu + q] = mu[q]
        q += 1usize
    }
    q = 0usize
    while q < g * p * p {
        res[off_sg + q] = sg[q]
        q += 1usize
    }
    ret ok
}
