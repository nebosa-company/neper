// R mclust: the noise component. Mclust(data, G, modelNames, initialization = list(noise = idx), Vinv = v): z has a noise column with the constant density Vinv,
// the EM maximises the mixture of G Gaussians plus uniform noise.
//
// The M step is the one of mclustem on the first G columns of z; the pooled scale of EII, EEI, EVI, EEE, EEV and E divides by the total weight of the G groups
// instead of n (the Fortran uses sumz with the noise column left out), so those sigma are rescaled by n / sum(sumz). The VEI, VEV, EVE, VEE and VVE inner iterations
// restart from scratch every EM step here (mclustem warm starts them), which changes their results only within the inner tolerance.

use e.math
use e.mem
use e.algo.linalg.lapack_syevr as syevr
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustem as em
use e.algo.stat.mclustfit as mf
use e.algo.stat.mclustsubset as ms

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

// hypvol(data, reciprocal = TRUE): 1 over the smaller of the volumes of the bounding box of the data and of its principal component scores (the covariance has divisor n)
fn hypvol_recip(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> f64 {
    if p == 1usize {
        var lo = x[0usize]
        var hi = x[0usize]
        var i = 1usize
        while i < n {
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
            i += 1usize
        }
        ret 1.0f64 / (hi - lo)
    }
    let (cen, e1) = mem.alloc[f64](a, n * p)
    let (cv, e2) = mem.alloc[f64](a, p * p)
    let (w, e3) = mem.alloc[f64](a, p)
    let (vec, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nanv() }
    var bd = 0.0f64
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var lo = x[j * n]
        var hi = x[j * n]
        var i = 0usize
        while i < n {
            m += x[j * n + i]
            if x[j * n + i] < lo { lo = x[j * n + i] }
            if x[j * n + i] > hi { hi = x[j * n + i] }
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            cen[j * n + i] = x[j * n + i] - m
            i += 1usize
        }
        bd += math.log[f64](hi - lo)
        j += 1usize
    }
    var b = 0usize
    while b < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += cen[b * n + i] * cen[c * n + i]
                i += 1usize
            }
            cv[c * p + b] = s / f64(n)
            c += 1usize
        }
        b += 1usize
    }
    if syevr.dsyevr_all(a, cv, p, w, vec) != ok { ret nanv() }
    var pc = 0.0f64
    j = 0usize
    while j < p {
        var lo = 0.0f64
        var hi = 0.0f64
        var i = 0usize
        while i < n {
            var s = 0.0f64
            b = 0usize
            while b < p {
                s += cen[b * n + i] * vec[j * p + b]
                b += 1usize
            }
            if i == 0usize || s < lo { lo = s }
            if i == 0usize || s > hi { hi = s }
            i += 1usize
        }
        pc += math.log[f64](hi - lo)
        j += 1usize
    }
    var vl = bd
    if pc < vl { vl = pc }
    ret math.exp[f64](0.0f64 - vl)
}

// one E step with the noise column: z (n by g + 1), pro (g + 1); returns the log likelihood
fn estep_noise(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, mu: []const f64, sigma: []const f64, pro: []const f64, vinv: f64, z: []f64) -> f64 {
    let (ld, e1) = mem.alloc[f64](a, n * g)
    if e1 != ok { ret nanv() }
    if mf.log_cdens(a, x, n, p, g, mu, sigma, ld) != ok { ret nanv() }
    var hood = 0.0f64
    var i = 0usize
    while i < n {
        var tmax = 0.0f64 - 1.0e308f64
        var k = 0usize
        while k < g {
            let t = math.log[f64](pro[k]) + ld[k * n + i]
            z[k * n + i] = t
            if t > tmax { tmax = t }
            k += 1usize
        }
        let tn = math.log[f64](vinv) + math.log[f64](pro[g])
        z[g * n + i] = tn
        if tn > tmax { tmax = tn }
        var sum = 0.0f64
        k = 0usize
        while k <= g {
            let e = math.exp[f64](z[k * n + i] - tmax)
            z[k * n + i] = e
            sum += e
            k += 1usize
        }
        hood += math.log[f64](sum) + tmax
        k = 0usize
        while k <= g {
            z[k * n + i] = z[k * n + i] / sum
            k += 1usize
        }
        i += 1usize
    }
    ret hood
}

// me(data, modelName, z, Vinv = vinv): z (n by g + 1) is replaced by the final memberships; pro (g + 1), mu (p by g), sigma (g stacked); info 0 the iterations
fn me_noise(a: *mem.Arena, model: usize, x: []const f64, z: []f64, n: usize, p: usize, g: usize, vinv: f64, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    if model == 5usize || model == 9usize || model == 10usize || model == 11usize || model == 13usize {
        let tol_in = math.sqrt[f64](2.220446049250313e-16f64)
        ret em.me_gen_v(a, model, false, x, z, n, p, g, 1.0e-5f64, tol_in, 2147483647usize, 2147483647usize, 2.220446049250313e-16f64, false, pro, mu, sigma, info, vinv)
    }
    let (zg, e1) = mem.alloc[f64](a, n * g)
    let (inf, e2) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok { ret nanv() }
    var hold = 8.0e307f64
    var iter = 0usize
    let nn = f64(n)
    while true {
        iter += 1usize
        let it0 = mem.mark(a)
        var q = 0usize
        while q < n * g {
            zg[q] = z[q]
            q += 1usize
        }
        var tz = 0.0f64
        var k = 0usize
        while k < g {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += z[k * n + i]
                i += 1usize
            }
            if !(s > 1.4901161193847656e-8f64) { ret nanv() }
            pro[k] = s / nn
            tz += s
            k += 1usize
        }
        let mh = em.mstep_any(a, model, x, zg, n, p, g, pro, mu, sigma, inf)
        if mh != mh { ret nanv() }
        // mstep_any set pro from zg; the noise proportion is the rest of the weight
        var sn = 0.0f64
        var i = 0usize
        while i < n {
            sn += z[g * n + i]
            i += 1usize
        }
        k = 0usize
        while k < g {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += z[k * n + i]
                i += 1usize
            }
            pro[k] = s / nn
            k += 1usize
        }
        pro[g] = sn / nn
        if model == 0usize || model == 2usize || model == 4usize || model == 6usize || model == 8usize || model == 12usize || model == 14usize {
            let f = nn / tz
            q = 0usize
            while q < g * p * p {
                sigma[q] = sigma[q] * f
                q += 1usize
            }
        }
        let hood = estep_noise(a, x, n, p, g, mu, sigma, pro, vinv, z)
        mem.reset(a, it0)
        if hood != hood { ret hood }
        let err1 = math.abs[f64](hold - hood) / (1.0f64 + math.abs[f64](hood))
        hold = hood
        if err1 <= 1.0e-5f64 {
            info[0usize] = f64(iter)
            ret hood
        }
    }
    ret nanv()
}

// the start z (n by g + 1) of mclustBIC: the hierarchy partition of the rows that are not noise, the noise rows in the last column
fn start_noise(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, isn: []const bool, xs: []const f64, ns: usize, pairs: []const usize, z: []f64) -> err {
    let (lab, e1) = mem.alloc[usize](a, ns)
    let (zs, e2) = mem.alloc[f64](a, ns * g)
    if e1 != ok || e2 != ok { ret mem.Full }
    if ms.subset_z(a, xs, ns, p, g, pairs, zs) != ok { ret mem.Full }
    var q = 0usize
    while q < n * (g + 1usize) {
        z[q] = 0.0f64
        q += 1usize
    }
    var r = 0usize
    var i = 0usize
    while i < n {
        if isn[i] {
            z[g * n + i] = 1.0f64
        } else {
            var k = 0usize
            while k < g {
                z[k * n + i] = zs[k * ns + r]
                k += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    ret ok
}

// Mclust(data, G = gmin:gmax (gmin may be 0), modelNames, initialization = list(noise = idx), Vinv = vinv). noise holds 0-based row indices.
// res: 0 bic, 1 G, 2 model, 3 loglik, 4 icl (NaN), 5 df, the BIC matrix (ng by nm), classification (n, 0 for noise), uncertainty (n), z (n by gmax + 1), pro (gmax + 1), mean (p by gmax), covariances (gmax stacked)
fn mclust_run_noise(a: *mem.Arena, x: []const f64, n: usize, p: usize, noise: []const usize, vinv: f64, gmin: usize, gmax: usize, models: []const usize, res: []f64) -> err {
    let ng = gmax - gmin + 1usize
    let nm = models.len
    let (isn, e0) = mem.alloc[bool](a, n)
    if e0 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        isn[i] = false
        i += 1usize
    }
    i = 0usize
    while i < noise.len {
        isn[noise[i]] = true
        i += 1usize
    }
    let ns = n - noise.len
    let (sub, e1) = mem.alloc[usize](a, ns)
    if e1 != ok { ret mem.Full }
    var r = 0usize
    i = 0usize
    while i < n {
        if !isn[i] {
            sub[r] = i
            r += 1usize
        }
        i += 1usize
    }
    let (xs, e2) = mem.alloc[f64](a, ns * p)
    let (pairs, e3) = mem.alloc[usize](a, 2usize * ns)
    let (z, e4) = mem.alloc[f64](a, n * (gmax + 1usize))
    let (pro, e5) = mem.alloc[f64](a, gmax + 1usize)
    let (mu, e6) = mem.alloc[f64](a, gmax * p + 1usize)
    let (sg, e7) = mem.alloc[f64](a, gmax * p * p + 1usize)
    let (inf, e8) = mem.alloc[f64](a, 4usize)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    ms.take_rows(x, n, p, sub, xs)
    if p > 1usize && gmax > 1usize {
        let pe = ms.subset_pairs(a, xs, ns, n, p, pairs)
        if pe != ok { ret pe }
    }
    let bicm = res[6usize..6usize + ng * nm]
    var gi = 0usize
    while gi < ng {
        let g = gmin + gi
        var mi = 0usize
        while mi < nm {
            var b = nanv()
            if g == 0usize {
                b = 2.0f64 * f64(n) * math.log[f64](vinv) - math.log[f64](f64(n))
            } else {
                let start = mem.mark(a)
                var ll = nanv()
                if start_noise(a, x, n, p, g, isn, xs, ns, pairs, z[0usize..n * (g + 1usize)]) == ok {
                    ll = me_noise(a, models[mi], x, z[0usize..n * (g + 1usize)], n, p, g, vinv, pro, mu, sg, inf)
                }
                if ll == ll { b = mp.bic(mp.model_name(models[mi]), ll, f64(n), f64(p), f64(g), true, false) }
                mem.reset(a, start)
            }
            bicm[mi * ng + gi] = b
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
    let off_pro = off_z + n * (gmax + 1usize)
    let off_mu = off_pro + gmax + 1usize
    let off_sg = off_mu + p * gmax
    res[0usize] = bicm[bm * ng + bg]
    res[1usize] = f64(g)
    res[2usize] = f64(mod)
    res[4usize] = nanv()
    var q = 0usize
    while q < n * (gmax + 1usize) + gmax + 1usize + p * gmax + gmax * p * p {
        res[off_z + q] = 0.0f64
        q += 1usize
    }
    if g == 0usize {
        res[3usize] = f64(n) * math.log[f64](vinv)
        res[5usize] = 0.0f64
        i = 0usize
        while i < n {
            res[off_cl + i] = 0.0f64
            res[off_un + i] = 0.0f64
            i += 1usize
        }
        ret ok
    }
    let ll = blk_fit(a, x, n, p, g, mod, isn, xs, ns, pairs, vinv, z, pro, mu, sg, inf)
    if ll != ll { ret mem.Full }
    res[3usize] = ll
    res[5usize] = mp.n_mclust_params(mp.model_name(mod), f64(p), f64(g), true, false)
    i = 0usize
    while i < n {
        var best = 0usize
        var k = 1usize
        while k <= g {
            if z[k * n + i] > z[best * n + i] { best = k }
            k += 1usize
        }
        var lab = f64(best + 1usize)
        if best == g { lab = 0.0f64 }
        res[off_cl + i] = lab
        res[off_un + i] = 1.0f64 - z[best * n + i]
        i += 1usize
    }
    q = 0usize
    while q < n * (g + 1usize) {
        res[off_z + q] = z[q]
        q += 1usize
    }
    q = 0usize
    while q <= g {
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

fn blk_fit(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, mod: usize, isn: []const bool, xs: []const f64, ns: usize, pairs: []const usize, vinv: f64, z: []f64, pro: []f64, mu: []f64, sg: []f64, inf: []f64) -> f64 {
    if start_noise(a, x, n, p, g, isn, xs, ns, pairs, z[0usize..n * (g + 1usize)]) != ok { ret nanv() }
    ret me_noise(a, mod, x, z[0usize..n * (g + 1usize)], n, p, g, vinv, pro, mu, sg, inf)
}
