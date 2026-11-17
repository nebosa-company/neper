// R mclust: mclustBIC, Mclust model selection, ICL and the density and prediction helpers, over the fits of e.algo.stat.mclustem and the hierarchies of e.algo.stat.mclusthc.
//
// Layouts follow R: x is n by p, means p by G, covariances G stacked p by p matrices, all column-major. Model indices are the package table of model_name:
// E 0, V 1, EII 2, VII 3, EEI 4, VEI 5, EVI 6, VVI 7, EEE 8, EVE 9, VEE 10, VVE 11, EEV 12, VEV 13, EVV 14, VVV 15.

use e.math
use e.mem
use e.str
use e.algo.stat.mclustpkg as mp
use e.algo.stat.mclustem as em
use e.algo.stat.mclusthc as hc
use e.algo.stat.mclusthcv as hv

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// qclass(x, k): the quantile classes of one variable, 1-based
fn qclass(a: *mem.Arena, x: []const f64, n: usize, k: usize, cl: []usize) -> err {
    let (srt, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        srt[i] = x[i]
        i += 1usize
    }
    // insertion sort
    i = 1usize
    while i < n {
        let v = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > v {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = v
        i += 1usize
    }
    var mean = 0.0f64
    i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    let eps = math.sqrt[f64](ss / f64(n - 1usize)) * math.sqrt[f64](2.220446049250313e-16f64)
    let (q, e2) = mem.alloc[f64](a, 2usize * n + k + 4usize)
    if e2 != ok { ret e2 }
    var nq = 0usize
    var m = k
    while nq < k + 1usize {
        m += 1usize
        nq = 0usize
        var t = 0usize
        while t < m {
            // quantile type 7 at probability t / (m - 1)
            let h = f64(n - 1usize) * (f64(t) / f64(m - 1usize))
            var lo = usize(math.floor[f64](h))
            var hi = lo
            if f64(lo) < h { hi = lo + 1usize }
            if hi > n - 1usize { hi = n - 1usize }
            if lo > n - 1usize { lo = n - 1usize }
            var qv = srt[lo]
            if h > f64(lo) && srt[hi] != srt[lo] {
                let fr = h - f64(lo)
                qv = (1.0f64 - fr) * srt[lo] + fr * srt[hi]
            }
            // unique: sorted ascending, so only the previous value can repeat
            if nq == 0usize || q[nq - 1usize] != qv {
                q[nq] = qv
                nq += 1usize
            }
            t += 1usize
        }
    }
    if nq > k + 1usize {
        // drop the nq - k - 1 smallest gaps (the gap after position i removes q[i + 1]), ties by position
        // q[-order(dq)[1:nr]] removes the left end of each of the nr smallest gaps, ties by position
        let drop = nq - k - 1usize
        let (dg, e3) = mem.alloc[f64](a, nq)
        let (rm, e4) = mem.alloc[bool](a, nq)
        if e3 != ok || e4 != ok { ret mem.Full }
        i = 0usize
        while i + 1usize < nq {
            dg[i] = q[i + 1usize] - q[i]
            i += 1usize
        }
        i = 0usize
        while i < nq {
            rm[i] = false
            i += 1usize
        }
        var used = 0usize
        while used < drop {
            var best = 0usize
            var bv = 0.0f64
            var found = false
            i = 0usize
            while i + 1usize < nq {
                if !rm[i] && (!found || dg[i] < bv) {
                    bv = dg[i]
                    best = i
                    found = true
                }
                i += 1usize
            }
            rm[best] = true
            used += 1usize
        }
        var w = 0usize
        i = 0usize
        while i < nq {
            if !rm[i] {
                q[w] = q[i]
                w += 1usize
            }
            i += 1usize
        }
        nq = w
    }
    q[0usize] = srt[0usize] - eps
    q[nq - 1usize] = srt[n - 1usize] + eps
    i = 0usize
    while i < n {
        cl[i] = 0usize
        var c = 0usize
        while c < k {
            if x[i] >= q[c] && x[i] < q[c + 1usize] { cl[i] = c + 1usize }
            c += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the G = 1 fit of mvn(modelName, data): fills mu (p) and sigma (p by p) and returns the log likelihood, NaN when the covariance is singular
fn mvn_fit(a: *mem.Arena, model: usize, x: []const f64, n: usize, p: usize, mu: []f64, sigma: []f64) -> f64 {
    let nn = f64(n)
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[j * n + i]
            i += 1usize
        }
        mu[j] = s / nn
        j += 1usize
    }
    var b = 0usize
    while b < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[b * n + i] - mu[b]) * (x[c * n + i] - mu[c])
                i += 1usize
            }
            sigma[c * p + b] = s / nn
            c += 1usize
        }
        b += 1usize
    }
    // the structure of the covariance: spherical, diagonal or full
    var kind = 2usize
    if model == 0usize || model == 1usize { kind = 1usize }
    if model == 2usize || model == 3usize { kind = 0usize }
    if model == 4usize || model == 5usize || model == 6usize || model == 7usize { kind = 1usize }
    if kind == 0usize {
        var tr = 0.0f64
        var q = 0usize
        while q < p {
            tr += sigma[q * p + q]
            q += 1usize
        }
        b = 0usize
        while b < p * p {
            sigma[b] = 0.0f64
            b += 1usize
        }
        q = 0usize
        while q < p {
            sigma[q * p + q] = tr / f64(p)
            q += 1usize
        }
    } else if kind == 1usize {
        b = 0usize
        while b < p {
            var c = 0usize
            while c < p {
                if b != c { sigma[c * p + b] = 0.0f64 }
                c += 1usize
            }
            b += 1usize
        }
    }
    let (l, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret nan() }
    if !mp.chol_lower(sigma, p, l) { ret nan() }
    var ld = 0.0f64
    var q = 0usize
    while q < p {
        ld += 2.0f64 * math.log[f64](l[q * p + q])
        q += 1usize
    }
    ret 0.0f64 - nn / 2.0f64 * (f64(p) * 1.837877066409345f64 + ld + f64(p))
}

fn name_less(m1: usize, m2: usize) -> bool {
    let s1 = mp.model_name(m1)
    let s2 = mp.model_name(m2)
    var i = 0usize
    while i < s1.len && i < s2.len {
        if s1[i] != s2[i] { ret s1[i] < s2[i] }
        i += 1usize
    }
    ret s1.len < s2.len
}

// log density of group k for one observation row i (the cdens of mclust), from the covariance matrices
fn log_cdens(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, mu: []const f64, sigma: []const f64, out: []f64) -> err {
    let (lall, e1) = mem.alloc[f64](a, p * p)
    let (dv, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret mem.Full }
    var k = 0usize
    while k < g {
        if !mp.chol_lower(sigma[k * p * p..k * p * p + p * p], p, lall) { ret mem.Full }
        var ld = 0.0f64
        var q = 0usize
        while q < p {
            ld += 2.0f64 * math.log[f64](lall[q * p + q])
            q += 1usize
        }
        var i = 0usize
        while i < n {
            var maha = 0.0f64
            q = 0usize
            while q < p {
                var v = x[q * n + i] - mu[k * p + q]
                var t = 0usize
                while t < q {
                    v -= lall[t * p + q] * dv[t]
                    t += 1usize
                }
                dv[q] = v / lall[q * p + q]
                maha += dv[q] * dv[q]
                q += 1usize
            }
            out[k * n + i] = 0.0f64 - 0.5f64 * (f64(p) * 1.837877066409345f64 + ld + maha)
            i += 1usize
        }
        k += 1usize
    }
    ret ok
}

// the hc pairs mclustBIC uses by default (p > 1): hc(data, "VVV", use = "SVD") when n > p, else hc(data, "EII", use = "SVD"); pairs has 2 (n - 1) entries
fn default_pairs(a: *mem.Arena, x: []const f64, n: usize, p: usize, pairs: []usize) -> err {
    let (z, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret e1 }
    let pe = hc.hc_prep(a, x, n, p, 5usize, z)
    if pe != ok { ret pe }
    if n > p { ret hv.hc_vvv(a, z, n, p, 1.0f64, 1.0f64, pairs) }
    ret mp.hc_eii(a, z, n, p, pairs)
}

// z (n by g) from 0-based labels
fn unmap(lab: []const usize, n: usize, g: usize, z: []f64) {
    var i = 0usize
    while i < n * g {
        z[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        z[lab[i] * n + i] = 1.0f64
        i += 1usize
    }
}

// the starting memberships for g groups
fn start_z(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, pairs: []const usize, z: []f64) -> err {
    let (lab, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    if p > 1usize {
        let he = hc.hclass(a, pairs, n, g, lab)
        if he != ok { ret he }
    } else {
        let qe = qclass(a, x, n, g, lab)
        if qe != ok { ret qe }
        var i = 0usize
        while i < n {
            lab[i] = lab[i] - 1usize
            i += 1usize
        }
    }
    unmap(lab, n, g, z)
    ret ok
}

// mclustBIC(data, G = gmin:gmax, modelNames = models): the BIC matrix (rows G, columns the models, column-major, NaN for a model that fails)
fn mclust_bic(a: *mem.Arena, x: []const f64, n: usize, p: usize, gmin: usize, gmax: usize, models: []const usize, bicm: []f64) -> err {
    let ng = gmax - gmin + 1usize
    let nm = models.len
    let (pairs, e1) = mem.alloc[usize](a, 2usize * n)
    let (z, e2) = mem.alloc[f64](a, n * gmax)
    let (pro, e3) = mem.alloc[f64](a, gmax)
    let (mu, e4) = mem.alloc[f64](a, gmax * p)
    let (sg, e5) = mem.alloc[f64](a, gmax * p * p)
    let (inf, e6) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    if p > 1usize && gmax > 1usize {
        let pe = default_pairs(a, x, n, p, pairs)
        if pe != ok { ret pe }
    }
    var gi = 0usize
    while gi < ng {
        let g = gmin + gi
        var mi = 0usize
        while mi < nm {
            let mod = models[mi]
            let start = mem.mark(a)
            var ll = nan()
            if g == 1usize {
                ll = mvn_fit(a, mod, x, n, p, mu, sg)
            } else if g <= n {
                if start_z(a, x, n, p, g, pairs, z[0usize..n * g]) == ok {
                    ll = em.me_any(a, mod, false, x, z[0usize..n * g], n, p, g, pro, mu, sg, inf)
                }
            }
            var b = nan()
            if ll == ll {
                b = mp.bic(mp.model_name(mod), ll, f64(n), f64(p), f64(g), false, false)
            }
            bicm[mi * ng + gi] = b
            mem.reset(a, start)
            mi += 1usize
        }
        gi += 1usize
    }
    ret ok
}

// Mclust(data, G = gmin:gmax, modelNames = models) without a prior or noise. res: 0 bic of the chosen fit, 1 G, 2 model index, 3 loglik, 4 icl, 5 df, then the BIC matrix (ng by nm),
// then the classification (n, 1-based), the uncertainty (n), the memberships z (n by gmax, the first G columns used), pro (gmax), mean (p by gmax) and covariances (gmax stacked p by p).
fn mclust_run(a: *mem.Arena, x: []const f64, n: usize, p: usize, gmin: usize, gmax: usize, models: []const usize, res: []f64) -> err {
    let ng = gmax - gmin + 1usize
    let nm = models.len
    let bicm = res[6usize..6usize + ng * nm]
    let be = mclust_bic(a, x, n, p, gmin, gmax, models, bicm)
    if be != ok { ret be }
    // pickBIC: the largest BIC, ties by G then by model name
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
                        if gi == bg && name_less(models[mi], models[bm]) { better = true }
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
    let (inf, e6) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var ll = 0.0f64
    var q = 0usize
    if g == 1usize {
        ll = mvn_fit(a, mod, x, n, p, mu, sg)
        pro[0usize] = 1.0f64
        q = 0usize
        while q < n {
            z[q] = 1.0f64
            q += 1usize
        }
    } else {
        if p > 1usize {
            let pe = default_pairs(a, x, n, p, pairs)
            if pe != ok { ret pe }
        }
        let se = start_z(a, x, n, p, g, pairs, z)
        if se != ok { ret se }
        ll = em.me_any(a, mod, false, x, z, n, p, g, pro, mu, sg, inf)
        if ll != ll { ret mem.Full }
        // the extra M step when the proportions differ from the column means of z
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
        // mstep of VEE, EVE, VVE and VEV reports return code 2 in mclust, so its parameters are never taken
        let rc_ok = mod != 9usize && mod != 10usize && mod != 11usize && mod != 13usize
        if rc_ok && dsum > math.sqrt[f64](2.220446049250313e-16f64) {
            let (z2, e7) = mem.alloc[f64](a, n * g)
            let (pro2, e8) = mem.alloc[f64](a, g)
            let (mu2, e9) = mem.alloc[f64](a, g * p)
            let (sg2, e10) = mem.alloc[f64](a, g * p * p)
            if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
            q = 0usize
            while q < n * g {
                z2[q] = z[q]
                q += 1usize
            }
            let _ = em.mstep_any(a, mod, x, z2, n, p, g, pro2, mu2, sg2, inf)
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
    let nparams = mp.n_mclust_params(mp.model_name(mod), f64(p), f64(g), false, false)
    let bicv = mp.bic(mp.model_name(mod), ll, f64(n), f64(p), f64(g), false, false)
    // classification, uncertainty and ICL
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
    q = 0usize
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

// predict.Mclust / estep / dens for newdata x (n by p) under the parameters pro (g), mu (p by g) and sigma (g stacked p by p):
// res holds the log densities cdens (n by g), the memberships z (n by g), the 1-based classification (n), the log likelihood of estep (1) and the mixture density dens (n)
fn predict_run(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, pro: []const f64, mu: []const f64, sigma: []const f64, res: []f64) -> err {
    let lc = res[0usize..n * g]
    let ce = log_cdens(a, x, n, p, g, mu, sigma, lc)
    if ce != ok { ret ce }
    var ps = 0.0f64
    var k = 0usize
    while k < g {
        ps += pro[k]
        k += 1usize
    }
    let off_z = n * g
    let off_cl = 2usize * n * g
    let off_ll = off_cl + n
    let off_d = off_ll + 1usize
    var hood = 0.0f64
    var i = 0usize
    while i < n {
        var mx = 0.0f64 - 1.0e308f64
        k = 0usize
        while k < g {
            let v = math.log[f64](pro[k] / ps) + lc[k * n + i]
            if v > mx { mx = v }
            k += 1usize
        }
        var s = 0.0f64
        k = 0usize
        while k < g {
            s += math.exp[f64](math.log[f64](pro[k] / ps) + lc[k * n + i] - mx)
            k += 1usize
        }
        let lse = mx + math.log[f64](s)
        var best = 0usize
        k = 0usize
        while k < g {
            let zz = math.exp[f64](math.log[f64](pro[k] / ps) + lc[k * n + i] - lse)
            res[off_z + k * n + i] = zz
            if zz > res[off_z + best * n + i] { best = k }
            k += 1usize
        }
        res[off_cl + i] = f64(best + 1usize)
        hood += lse
        // dens() uses the proportions as given
        var dsum = 0.0f64
        k = 0usize
        while k < g {
            dsum += pro[k] * math.exp[f64](lc[k * n + i])
            k += 1usize
        }
        res[off_d + i] = dsum
        i += 1usize
    }
    res[off_ll] = hood
    ret ok
}
