// R mclust: Mclust / mclustBIC with initialization = list(subset = idx): the hierarchy and the first M step run on data[subset, ], then E step and EM on all the data.
//
// sub holds the 0-based row indices of the subset (the caller draws them, e.g. under set.seed). Same result layout as mclustfit.mclust_run without the ICL block.

use e.math
use e.mem
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustem as em
use e.algo.stat.mclustfit as mf
use e.algo.stat.mclusthc as hc
use e.algo.stat.mclusthcv as hv

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

fn take_rows(x: []const f64, n: usize, p: usize, sub: []const usize, xs: []f64) {
    let ns = sub.len
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < ns {
            xs[j * ns + i] = x[j * n + sub[i]]
            i += 1usize
        }
        j += 1usize
    }
}

// hc of the subset rows (VVV when the full data has more rows than variables, else EII)
fn subset_pairs(a: *mem.Arena, xs: []const f64, ns: usize, n: usize, p: usize, pairs: []usize) -> err {
    let (z, e1) = mem.alloc[f64](a, ns * p)
    if e1 != ok { ret e1 }
    let pe = hc.hc_prep(a, xs, ns, p, 5usize, z)
    if pe != ok { ret pe }
    if n > p { ret hv.hc_vvv(a, z, ns, p, 1.0f64, 1.0f64, pairs) }
    ret mp.hc_eii(a, z, ns, p, pairs)
}

// the start memberships of the subset rows for g groups
fn subset_z(a: *mem.Arena, xs: []const f64, ns: usize, p: usize, g: usize, pairs: []const usize, z: []f64) -> err {
    ret mf.start_z(a, xs, ns, p, g, pairs, z)
}

// one fit at (g, model): the log likelihood with z (n by g), pro, mu, sg filled
fn fit_subset(a: *mem.Arena, x: []const f64, n: usize, p: usize, xs: []const f64, ns: usize, g: usize, model: usize, pairs: []const usize, z: []f64, pro: []f64, mu: []f64, sg: []f64) -> f64 {
    if g == 1usize {
        let ll = mf.mvn_fit(a, model, x, n, p, mu, sg)
        pro[0usize] = 1.0f64
        var q = 0usize
        while q < n {
            z[q] = 1.0f64
            q += 1usize
        }
        ret ll
    }
    let (zs, e1) = mem.alloc[f64](a, ns * g)
    let (inf, e2) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok { ret nanv() }
    if subset_z(a, xs, ns, p, g, pairs, zs) != ok { ret nanv() }
    let mh = em.mstep_any(a, model, xs, zs, ns, p, g, pro, mu, sg, inf)
    if mh != mh { ret nanv() }
    let eh = em.estep_gen(a, x, n, p, g, mu, sg, pro, z)
    if eh != eh { ret nanv() }
    ret em.me_any(a, model, false, x, z, n, p, g, pro, mu, sg, inf)
}

fn mclust_run_subset(a: *mem.Arena, x: []const f64, n: usize, p: usize, sub: []const usize, gmin: usize, gmax: usize, models: []const usize, res: []f64) -> err {
    let ng = gmax - gmin + 1usize
    let nm = models.len
    let ns = sub.len
    let (xs, e0) = mem.alloc[f64](a, ns * p)
    let (pairs, e1) = mem.alloc[usize](a, 2usize * ns)
    let (z, e2) = mem.alloc[f64](a, n * gmax)
    let (pro, e3) = mem.alloc[f64](a, gmax)
    let (mu, e4) = mem.alloc[f64](a, gmax * p)
    let (sg, e5) = mem.alloc[f64](a, gmax * p * p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    take_rows(x, n, p, sub, xs)
    if p > 1usize && gmax > 1usize {
        let pe = subset_pairs(a, xs, ns, n, p, pairs)
        if pe != ok { ret pe }
    }
    let bicm = res[6usize..6usize + ng * nm]
    var gi = 0usize
    while gi < ng {
        let g = gmin + gi
        var mi = 0usize
        while mi < nm {
            let start = mem.mark(a)
            var ll = nanv()
            if g <= ns { ll = fit_subset(a, x, n, p, xs, ns, g, models[mi], pairs, z[0usize..n * g], pro, mu, sg) }
            var b = nanv()
            if ll == ll { b = mp.bic(mp.model_name(models[mi]), ll, f64(n), f64(p), f64(g), false, false) }
            bicm[mi * ng + gi] = b
            mem.reset(a, start)
            mi += 1usize
        }
        gi += 1usize
    }
    var bg = 0usize
    var bm = 0usize
    var found = false
    gi = 0usize
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
    let ll = fit_subset(a, x, n, p, xs, ns, g, mod, pairs, z[0usize..n * g], pro, mu, sg)
    if ll != ll { ret mem.Full }
    if g > 1usize {
        // the extra M step on all the data (taken only when mstep reports success)
        let rc_ok = mod != 9usize && mod != 10usize && mod != 11usize && mod != 13usize
        if rc_ok {
            let (z2, e7) = mem.alloc[f64](a, n * g)
            let (pro2, e8) = mem.alloc[f64](a, g)
            let (mu2, e9) = mem.alloc[f64](a, g * p)
            let (sg2, e10) = mem.alloc[f64](a, g * p * p)
            let (inf, e11) = mem.alloc[f64](a, 4usize)
            if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
            var q = 0usize
            while q < n * g {
                z2[q] = z[q]
                q += 1usize
            }
            let mh = em.mstep_any(a, mod, x, z2, n, p, g, pro2, mu2, sg2, inf)
            if mh == mh {
                q = 0usize
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
