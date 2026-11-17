// R mclust: MclustDA (a mixture per class) and EDDA (one covariance structure for every class) with logLik, BIC, df and predict.
//
// Layouts follow R: x is n by p, means p by G, covariances G stacked p by p matrices, all column-major. Model indices are the package table of model_name.

use e.math
use e.mem
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustem as em
use e.algo.stat.mclustfit as mf

// log of the mixture density sum_k pro_k cdens_k at every row of x, the proportions as given
fn mixture_logdens(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, pro: []const f64, mu: []const f64, sigma: []const f64, out: []f64) -> err {
    let start = mem.mark(a)
    let (lc, e1) = mem.alloc[f64](a, n * g)
    if e1 != ok { ret e1 }
    let ce = mf.log_cdens(a, x, n, p, g, mu, sigma, lc)
    if ce != ok { ret ce }
    var i = 0usize
    while i < n {
        var mx = 0.0f64 - 1.0e308f64
        var k = 0usize
        while k < g {
            let v = math.log[f64](pro[k]) + lc[k * n + i]
            if v > mx { mx = v }
            k += 1usize
        }
        var s = 0.0f64
        k = 0usize
        while k < g {
            s += math.exp[f64](math.log[f64](pro[k]) + lc[k * n + i] - mx)
            k += 1usize
        }
        out[i] = mx + math.log[f64](s)
        i += 1usize
    }
    mem.reset(a, start)
    ret ok
}

// the posteriors of lg (n by nclass log densities) with class proportions cnt / total: z is filled, the 1-based class goes to cl; returns the sum of the log mixture values
fn posterior(lg: []const f64, n: usize, nclass: usize, cnt: []const usize, total: usize, z: []f64, cl: []f64) -> f64 {
    var ll = 0.0f64
    var i = 0usize
    while i < n {
        var mx = 0.0f64 - 1.0e308f64
        var l = 0usize
        while l < nclass {
            let v = lg[l * n + i] + math.log[f64](f64(cnt[l]) / f64(total))
            if v > mx { mx = v }
            l += 1usize
        }
        var s = 0.0f64
        l = 0usize
        while l < nclass {
            s += math.exp[f64](lg[l * n + i] + math.log[f64](f64(cnt[l]) / f64(total)) - mx)
            l += 1usize
        }
        let lse = mx + math.log[f64](s)
        ll += lse
        var best = 0usize
        l = 0usize
        while l < nclass {
            let zz = math.exp[f64](lg[l * n + i] + math.log[f64](f64(cnt[l]) / f64(total)) - lse)
            z[l * n + i] = zz
            if zz > z[best * n + i] { best = l }
            l += 1usize
        }
        cl[i] = f64(best + 1usize)
        i += 1usize
    }
    ret ll
}

// MclustDA(data, class, modelType = "MclustDA" or "EDDA", G = 1:gmax, modelNames = models) and its logLik, BIC and df, with predict at xnew (nn rows).
// cls holds 0-based class labels. res: 0 loglik, 1 bic, 2 df, 3 EDDA model index (-1 otherwise), then per class the number of components G (nclass) and the model index (nclass),
// then the predicted posteriors (nn by nclass) and the 1-based predicted classes (nn)
fn mclustda_run(a: *mem.Arena, x: []const f64, n: usize, p: usize, cls: []const usize, nclass: usize, edda: bool, gmax: usize, models: []const usize, xnew: []const f64, nn: usize, res: []f64) -> err {
    let (cnt, e1) = mem.alloc[usize](a, nclass)
    let (lgd, e2) = mem.alloc[f64](a, n * nclass)
    let (lgn, e3) = mem.alloc[f64](a, nn * nclass)
    let (zt, e4) = mem.alloc[f64](a, n * nclass)
    let (clt, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var l = 0usize
    while l < nclass {
        cnt[l] = 0usize
        l += 1usize
    }
    var i = 0usize
    while i < n {
        cnt[cls[i]] += 1usize
        i += 1usize
    }
    var df = 0.0f64
    res[3usize] = 0.0f64 - 1.0f64
    let (one, e15) = mem.alloc[f64](a, 1usize)
    if e15 != ok { ret mem.Full }
    one[0usize] = 1.0f64
    if edda {
        let (z, e6) = mem.alloc[f64](a, n * nclass)
        let (pro, e7) = mem.alloc[f64](a, nclass)
        let (mu, e8) = mem.alloc[f64](a, nclass * p)
        let (sg, e9) = mem.alloc[f64](a, nclass * p * p)
        let (inf, e10) = mem.alloc[f64](a, 4usize)
        let (bmu, e12) = mem.alloc[f64](a, nclass * p)
        let (bsg, e13) = mem.alloc[f64](a, nclass * p * p)
        let (ld, e14) = mem.alloc[f64](a, n)
        if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e12 != ok || e13 != ok || e14 != ok { ret mem.Full }
        var bestbic = 0.0f64
        var have = false
        var bestm = 0usize
        var mi = 0usize
        while mi < models.len {
            mf.unmap(cls, n, nclass, z)
            let _ = em.mstep_any(a, models[mi], x, z, n, p, nclass, pro, mu, sg, inf)
            var ok_fit = true
            var q = 0usize
            while q < nclass * p * p {
                if sg[q] != sg[q] { ok_fit = false }
                q += 1usize
            }
            var ll = mf.nan()
            if ok_fit {
                if mixture_logdens(a, x, n, p, nclass, pro, mu, sg, ld) == ok {
                    var s = 0.0f64
                    var r = 0usize
                    while r < n {
                        s += ld[r]
                        r += 1usize
                    }
                    ll = s
                }
            }
            if ll == ll {
                let b = mp.bic(mp.model_name(models[mi]), ll, f64(n), f64(p), f64(nclass), false, true)
                if !have || b >= bestbic {
                    have = true
                    bestbic = b
                    bestm = models[mi]
                    var t = 0usize
                    while t < nclass * p {
                        bmu[t] = mu[t]
                        t += 1usize
                    }
                    t = 0usize
                    while t < nclass * p * p {
                        bsg[t] = sg[t]
                        t += 1usize
                    }
                }
            }
            mi += 1usize
        }
        if !have { ret mem.Full }
        res[3usize] = f64(bestm)
        var c = 0usize
        while c < nclass {
            res[4usize + c] = 1.0f64
            res[4usize + nclass + c] = f64(bestm)
            let _ = mixture_logdens(a, x, n, p, 1usize, one, bmu[c * p..c * p + p], bsg[c * p * p..c * p * p + p * p], lgd[c * n..c * n + n])
            let _ = mixture_logdens(a, xnew, nn, p, 1usize, one, bmu[c * p..c * p + p], bsg[c * p * p..c * p * p + p * p], lgn[c * nn..c * nn + nn])
            c += 1usize
        }
        df = f64(p * nclass) + mp.n_var_params(mp.model_name(bestm), f64(p), f64(nclass)) + f64(nclass) - 1.0f64
    } else {
        var c = 0usize
        while c < nclass {
            let nl = cnt[c]
            let (xl, f1) = mem.alloc[f64](a, nl * p)
            if f1 != ok { ret f1 }
            var j = 0usize
            while j < p {
                var r = 0usize
                var w = 0usize
                while r < n {
                    if cls[r] == c {
                        xl[j * nl + w] = x[j * n + r]
                        w += 1usize
                    }
                    r += 1usize
                }
                j += 1usize
            }
            let rsz = 6usize + 2usize * gmax * models.len + 2usize * nl + nl * gmax + gmax + p * gmax + gmax * p * p
            let (rl, f2) = mem.alloc[f64](a, rsz)
            if f2 != ok { ret f2 }
            let fe = mf.mclust_run(a, xl, nl, p, 1usize, gmax, models, rl)
            if fe != ok { ret fe }
            let g = usize(rl[1usize])
            let mod = usize(rl[2usize])
            res[4usize + c] = f64(g)
            res[4usize + nclass + c] = f64(mod)
            let off_cl = 6usize + gmax * models.len
            let off_pro = off_cl + 2usize * nl + nl * gmax
            let off_mu = off_pro + gmax
            let off_sg = off_mu + p * gmax
            let _ = mixture_logdens(a, x, n, p, g, rl[off_pro..off_pro + g], rl[off_mu..off_mu + p * g], rl[off_sg..off_sg + g * p * p], lgd[c * n..c * n + n])
            let _ = mixture_logdens(a, xnew, nn, p, g, rl[off_pro..off_pro + g], rl[off_mu..off_mu + p * g], rl[off_sg..off_sg + g * p * p], lgn[c * nn..c * nn + nn])
            df += f64(g) - 1.0f64 + f64(g * p) + mp.n_var_params(mp.model_name(mod), f64(p), f64(g))
            c += 1usize
        }
        df += f64(nclass) - 1.0f64
    }
    let ll = posterior(lgd, n, nclass, cnt, n, zt, clt)
    res[0usize] = ll
    res[1usize] = 2.0f64 * ll - math.log[f64](f64(n)) * df
    res[2usize] = df
    let off_z = 4usize + 2usize * nclass
    let _ = posterior(lgn, nn, nclass, cnt, n, res[off_z..off_z + nn * nclass], res[off_z + nn * nclass..off_z + nn * nclass + nn])
    ret ok
}
