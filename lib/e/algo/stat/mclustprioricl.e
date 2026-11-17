// R mclust: mclustICL(..., prior = priorControl()): the final fit of summary(mclustBIC) with the prior (me, then the extra M step when the proportions differ
// from the column means of z), then ICL = BIC + 2 sum(z log z) of that fit.

use e.math
use e.mem
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustfit as mf
use e.algo.stat.mclustprior as pr
use e.algo.stat.mclustpriorfit as pf

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

fn final_fit_prior(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, mod: usize, pairs: []const usize, z: []f64, pro: []f64, mu: []f64, sg: []f64) -> f64 {
    let ll = pf.fit_prior(a, x, n, p, g, mod, pairs, z, pro, mu, sg)
    if ll != ll { ret ll }
    if g == 1usize { ret ll }
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
    if mod == 13usize || !(dsum > math.sqrt[f64](2.220446049250313e-16f64)) { ret ll }
    let (pmu, e6) = mem.alloc[f64](a, p)
    let (psc, e7) = mem.alloc[f64](a, p * p)
    let (pro2, e8) = mem.alloc[f64](a, g)
    let (mu2, e9) = mem.alloc[f64](a, g * p)
    let (sg2, e10) = mem.alloc[f64](a, g * p * p)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret nanv() }
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
    ret ll
}

// the ICL matrix (ng by nm, column-major) for the cells with a finite BIC in bicm
fn mclust_icl_prior(a: *mem.Arena, x: []const f64, n: usize, p: usize, gmin: usize, gmax: usize, models: []const usize, bicm: []const f64, icl: []f64) -> err {
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
        var mi = 0usize
        while mi < nm {
            icl[mi * ng + gi] = nanv()
            if bicm[mi * ng + gi] == bicm[mi * ng + gi] {
                let g = gmin + gi
                let start = mem.mark(a)
                let ll = final_fit_prior(a, x, n, p, g, models[mi], pairs, z[0usize..n * g], pro, mu, sg)
                if ll == ll {
                    let b = mp.bic(mp.model_name(models[mi]), ll, f64(n), f64(p), f64(g), false, false)
                    var cp = 0.0f64
                    var i = 0usize
                    while i < n {
                        var best = 0usize
                        var k = 1usize
                        while k < g {
                            if z[k * n + i] > z[best * n + i] { best = k }
                            k += 1usize
                        }
                        if z[best * n + i] > 0.0f64 { cp += math.log[f64](z[best * n + i]) }
                        i += 1usize
                    }
                    icl[mi * ng + gi] = b + 2.0f64 * cp
                }
                mem.reset(a, start)
            }
            mi += 1usize
        }
        gi += 1usize
    }
    ret ok
}
