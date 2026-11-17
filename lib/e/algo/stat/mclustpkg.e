// R mclust: the parameter counts and BIC of the covariance models, adjustedRandIndex and map.
//
// Not here: the EM fits themselves (me, em, mclustBIC), hierarchical initialisation, classError, unmap, the density and simulation routines.

use e.math
use e.mem
use e.algo.stat.ica as ica
use e.algo.stat.hclust as hcl
use e.str

// the model names in the order of the package table
fn model_name(i: usize) -> str {
    if i == 0usize { ret "E" }
    if i == 1usize { ret "V" }
    if i == 2usize { ret "EII" }
    if i == 3usize { ret "VII" }
    if i == 4usize { ret "EEI" }
    if i == 5usize { ret "VEI" }
    if i == 6usize { ret "EVI" }
    if i == 7usize { ret "VVI" }
    if i == 8usize { ret "EEE" }
    if i == 9usize { ret "EVE" }
    if i == 10usize { ret "VEE" }
    if i == 11usize { ret "VVE" }
    if i == 12usize { ret "EEV" }
    if i == 13usize { ret "VEV" }
    if i == 14usize { ret "EVV" }
    ret "VVV"
}

// nVarParams(modelName, d, G): the number of covariance parameters
fn n_var_params(m: str, d: f64, g: f64) -> f64 {
    if str.eq(m, "E") || str.eq(m, "X") { ret 1.0f64 }
    if str.eq(m, "V") { ret g }
    if str.eq(m, "EII") { ret 1.0f64 }
    if str.eq(m, "VII") { ret g }
    if str.eq(m, "EEI") || str.eq(m, "XXI") { ret d }
    if str.eq(m, "VEI") { ret g + (d - 1.0f64) }
    if str.eq(m, "EVI") { ret 1.0f64 + g * (d - 1.0f64) }
    if str.eq(m, "VVI") { ret g * d }
    if str.eq(m, "EEE") || str.eq(m, "XXX") { ret d * (d + 1.0f64) / 2.0f64 }
    if str.eq(m, "EVE") { ret 1.0f64 + g * (d - 1.0f64) + d * (d - 1.0f64) / 2.0f64 }
    if str.eq(m, "VEE") { ret g + (d - 1.0f64) + d * (d - 1.0f64) / 2.0f64 }
    if str.eq(m, "VVE") { ret g + g * (d - 1.0f64) + d * (d - 1.0f64) / 2.0f64 }
    if str.eq(m, "EEV") { ret 1.0f64 + (d - 1.0f64) + g * d * (d - 1.0f64) / 2.0f64 }
    if str.eq(m, "VEV") { ret g + (d - 1.0f64) + g * d * (d - 1.0f64) / 2.0f64 }
    if str.eq(m, "EVV") { ret 1.0f64 - g + g * d * (d + 1.0f64) / 2.0f64 }
    ret g * d * (d + 1.0f64) / 2.0f64
}

// nMclustParams(modelName, d, G, noise, equalPro)
fn n_mclust_params(m: str, d: f64, g: f64, noise: bool, equal_pro: bool) -> f64 {
    if g == 0.0f64 { ret 1.0f64 }
    var np = n_var_params(m, d, g) + g * d
    if !equal_pro { np += g - 1.0f64 }
    if noise { np += 2.0f64 }
    ret np
}

// bic(modelName, loglik, n, d, G): 2 loglik - nparams log(n)
fn bic(m: str, loglik: f64, n: f64, d: f64, g: f64, noise: bool, equal_pro: bool) -> f64 {
    ret 2.0f64 * loglik - n_mclust_params(m, d, g, noise, equal_pro) * math.log[f64](n)
}

fn choose2(x: f64) -> f64 { ret x * (x - 1.0f64) / 2.0f64 }

// adjustedRandIndex(x, y) for two labelings given as codes 0..kx - 1 and 0..ky - 1
fn adjusted_rand_index(a: *mem.Arena, x: []const usize, y: []const usize) -> f64 {
    let n = x.len
    var kx = 0usize
    var ky = 0usize
    var i = 0usize
    while i < n {
        if x[i] + 1usize > kx { kx = x[i] + 1usize }
        if y[i] + 1usize > ky { ky = y[i] + 1usize }
        i += 1usize
    }
    if kx == 1usize && ky == 1usize { ret 1.0f64 }
    let (tab, e) = mem.alloc[f64](a, kx * ky)
    if e != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < kx * ky {
        tab[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        tab[y[i] * kx + x[i]] += 1.0f64
        i += 1usize
    }
    var aa = 0.0f64
    var rowc = 0.0f64
    var colc = 0.0f64
    i = 0usize
    while i < kx * ky {
        aa += choose2(tab[i])
        i += 1usize
    }
    var r = 0usize
    while r < kx {
        var s = 0.0f64
        var c = 0usize
        while c < ky {
            s += tab[c * kx + r]
            c += 1usize
        }
        rowc += choose2(s)
        r += 1usize
    }
    var c2 = 0usize
    while c2 < ky {
        var s = 0.0f64
        r = 0usize
        while r < kx {
            s += tab[c2 * kx + r]
            r += 1usize
        }
        colc += choose2(s)
        c2 += 1usize
    }
    let b = rowc - aa
    let cc = colc - aa
    let d = choose2(f64(n)) - aa - b - cc
    ret (aa - (aa + b) * (aa + cc) / (aa + b + cc + d)) / ((aa + b + aa + cc) / 2.0f64 - (aa + b) * (aa + cc) / (aa + b + cc + d))
}

// map(z): the 1-based column of the first maximum in each row of the n by k column-major z
fn map(z: []const f64, n: usize, k: usize, out: []usize) {
    var i = 0usize
    while i < n {
        var best = 0usize
        var j = 1usize
        while j < k {
            if z[j * n + i] > z[best * n + i] { best = j }
            j += 1usize
        }
        out[i] = best + 1usize
        i += 1usize
    }
}

// ---- me(data, modelName, z): the EM iterations of mclust from a given membership matrix, for the models EII (and E), VII (and V), EEI, VVI, EEE and VVV ----

// model code: 0 EII, 1 VII, 2 EEI, 3 VVI, 4 EEE, 5 VVV, 6 EVI, 7 EVV, 8 EEV
fn chol_lower(s: []const f64, p: usize, l: []f64) -> bool {
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            l[j * p + i] = 0.0f64
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var d = s[j * p + j]
        var t = 0usize
        while t < j {
            d -= l[t * p + j] * l[t * p + j]
            t += 1usize
        }
        if d <= 0.0f64 { ret false }
        let dj = math.sqrt[f64](d)
        l[j * p + j] = dj
        var i = j + 1usize
        while i < p {
            var v = s[j * p + i]
            t = 0usize
            while t < j {
                v -= l[t * p + i] * l[t * p + j]
                t += 1usize
            }
            l[j * p + i] = v / dj
            i += 1usize
        }
        j += 1usize
    }
    ret true
}

// EM from the memberships z (n by g, column-major) for the data x (n by p), equal proportions off; on return z, pro (g), mu (g by p, column-major) and sigma (g matrices p by p, column-major, stacked) hold the fit,
// info[0] the iterations and info[1] the final error; returns the log likelihood
fn me_em(a: *mem.Arena, model: usize, equal_pro: bool, x: []const f64, z: []f64, n: usize, p: usize, g: usize, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    ret me_em_x(a, model, equal_pro, false, x, z, n, p, g, pro, mu, sigma, info)
}

// me_em, or with m_only just the M step of mstep(data, modelName, z): the parameters from z, no E step, returns 0
fn me_em_x(a: *mem.Arena, model: usize, equal_pro: bool, m_only: bool, x: []const f64, z: []f64, n: usize, p: usize, g: usize, pro: []f64, mu: []f64, sigma: []f64, info: []f64) -> f64 {
    let (sz, e1) = mem.alloc[f64](a, g)
    let (w, e2) = mem.alloc[f64](a, g * p * p)
    let (l, e3) = mem.alloc[f64](a, p * p)
    let (ld, e4) = mem.alloc[f64](a, g)
    let (dens, e5) = mem.alloc[f64](a, g)
    let (dv, e6) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    let tol = 1.0e-5f64
    var lk = 1.0e300f64
    var rel_err = 1.0e300f64
    var it = 0usize
    var hood = 0.0f64
    let nn = f64(n)
    let pp = f64(p)
    while rel_err > tol {
        it += 1usize
        var k = 0usize
        while k < g {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += z[k * n + i]
                i += 1usize
            }
            sz[k] = s
            pro[k] = s / nn
            if equal_pro { pro[k] = 1.0f64 / f64(g) }
            var j = 0usize
            while j < p {
                var m = 0.0f64
                i = 0usize
                while i < n {
                    m += z[k * n + i] * x[j * n + i]
                    i += 1usize
                }
                mu[j * g + k] = m / s
                j += 1usize
            }
            k += 1usize
        }
        k = 0usize
        while k < g {
            var j = 0usize
            while j < p {
                var j2 = 0usize
                while j2 < p {
                    var s = 0.0f64
                    var i = 0usize
                    while i < n {
                        s += z[k * n + i] * (x[j * n + i] - mu[j * g + k]) * (x[j2 * n + i] - mu[j2 * g + k])
                        i += 1usize
                    }
                    w[k * p * p + j2 * p + j] = s
                    j2 += 1usize
                }
                j += 1usize
            }
            k += 1usize
        }
        // the covariance of each group by model
        k = 0usize
        while k < g {
            var j = 0usize
            while j < p {
                var j2 = 0usize
                while j2 < p {
                    var v = 0.0f64
                    if model == 0usize {
                        if j == j2 {
                            var tr = 0.0f64
                            var kk = 0usize
                            while kk < g {
                                var q = 0usize
                                while q < p {
                                    tr += w[kk * p * p + q * p + q]
                                    q += 1usize
                                }
                                kk += 1usize
                            }
                            v = tr / (nn * pp)
                        }
                    } else if model == 1usize {
                        if j == j2 {
                            var tr = 0.0f64
                            var q = 0usize
                            while q < p {
                                tr += w[k * p * p + q * p + q]
                                q += 1usize
                            }
                            v = tr / (sz[k] * pp)
                        }
                    } else if model == 2usize {
                        if j == j2 {
                            var tr = 0.0f64
                            var kk = 0usize
                            while kk < g {
                                tr += w[kk * p * p + j * p + j]
                                kk += 1usize
                            }
                            v = tr / nn
                        }
                    } else if model == 7usize {
                        // EVV: W_k over its determinant root, times the pooled determinant roots over n
                        var lam = 0.0f64
                        var kk = 0usize
                        while kk < g {
                            if !chol_lower(w[kk * p * p..kk * p * p + p * p], p, l) { ret 0.0f64 / 0.0f64 }
                            var lg = 0.0f64
                            var q = 0usize
                            while q < p {
                                lg += 2.0f64 * math.log[f64](l[q * p + q])
                                q += 1usize
                            }
                            lam += math.exp[f64](lg / pp)
                            kk += 1usize
                        }
                        if !chol_lower(w[k * p * p..k * p * p + p * p], p, l) { ret 0.0f64 / 0.0f64 }
                        var lgk = 0.0f64
                        var q2 = 0usize
                        while q2 < p {
                            lgk += 2.0f64 * math.log[f64](l[q2 * p + q2])
                            q2 += 1usize
                        }
                        v = w[k * p * p + j2 * p + j] / math.exp[f64](lgk / pp) * (lam / nn)
                    } else if model == 8usize {
                        // EEV: D_k diag(pooled eigenvalues / n) D_k' with D_k the eigenvectors of W_k
                        var pooled = 0.0f64
                        var kk = 0usize
                        while kk < g {
                            let (ev, vecs, ee) = ica.eigen_sym(a, w[kk * p * p..kk * p * p + p * p], p)
                            if ee != ok { ret 0.0f64 / 0.0f64 }
                            if kk == k {
                                var q = 0usize
                                while q < p {
                                    var sumev = 0.0f64
                                    var k3 = 0usize
                                    while k3 < g {
                                        let (ev3, vecs3, ee3) = ica.eigen_sym(a, w[k3 * p * p..k3 * p * p + p * p], p)
                                        if ee3 != ok { ret 0.0f64 / 0.0f64 }
                                        sumev += ev3[q]
                                        k3 += 1usize
                                    }
                                    pooled += vecs[j * p + q] * (sumev / nn) * vecs[j2 * p + q]
                                    q += 1usize
                                }
                            }
                            kk += 1usize
                        }
                        v = pooled
                    } else if model == 6usize {
                        // EVI: lambda B_k with |B_k| = 1: diag(W_k) over its geometric mean, lambda the pooled geometric means over n
                        if j == j2 {
                            var lam = 0.0f64
                            var kk = 0usize
                            while kk < g {
                                var lg = 0.0f64
                                var q = 0usize
                                while q < p {
                                    lg += math.log[f64](w[kk * p * p + q * p + q])
                                    q += 1usize
                                }
                                lam += math.exp[f64](lg / pp)
                                kk += 1usize
                            }
                            var lgk = 0.0f64
                            var q2 = 0usize
                            while q2 < p {
                                lgk += math.log[f64](w[k * p * p + q2 * p + q2])
                                q2 += 1usize
                            }
                            v = w[k * p * p + j * p + j] / math.exp[f64](lgk / pp) * (lam / nn)
                        }
                    } else if model == 3usize {
                        if j == j2 { v = w[k * p * p + j * p + j] / sz[k] }
                    } else if model == 4usize {
                        var tr = 0.0f64
                        var kk = 0usize
                        while kk < g {
                            tr += w[kk * p * p + j2 * p + j]
                            kk += 1usize
                        }
                        v = tr / nn
                    } else {
                        v = w[k * p * p + j2 * p + j] / sz[k]
                    }
                    sigma[k * p * p + j2 * p + j] = v
                    j2 += 1usize
                }
                j += 1usize
            }
            k += 1usize
        }
        if m_only {
            info[0usize] = 1.0f64
            ret 0.0f64
        }
        // the E step
        k = 0usize
        while k < g {
            if !chol_lower(sigma[k * p * p..k * p * p + p * p], p, l) { ret 0.0f64 / 0.0f64 }
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += math.log[f64](l[q * p + q])
                q += 1usize
            }
            ld[k] = s
            k += 1usize
        }
        hood = 0.0f64
        var i = 0usize
        while i < n {
            var den = 0.0f64
            k = 0usize
            while k < g {
                if !chol_lower(sigma[k * p * p..k * p * p + p * p], p, l) { ret 0.0f64 / 0.0f64 }
                var q = 0usize
                var maha = 0.0f64
                while q < p {
                    var v = x[q * n + i] - mu[q * g + k]
                    var t = 0usize
                    while t < q {
                        v -= l[t * p + q] * dv[t]
                        t += 1usize
                    }
                    dv[q] = v / l[q * p + q]
                    maha += dv[q] * dv[q]
                    q += 1usize
                }
                dens[k] = pro[k] * math.exp[f64](0.0f64 - 0.5f64 * maha - ld[k]) / math.pow[f64](2.0f64 * 3.141592653589793f64, pp / 2.0f64)
                den += dens[k]
                k += 1usize
            }
            k = 0usize
            while k < g {
                z[k * n + i] = dens[k] / den
                k += 1usize
            }
            hood += math.log[f64](den)
            i += 1usize
        }
        rel_err = math.abs[f64](lk - hood) / (1.0f64 + math.abs[f64](hood))
        lk = hood
    }
    info[0usize] = f64(it)
    info[1usize] = rel_err
    ret hood
}

// hc(data, modelName = "EII"): the agglomeration that merges the pair giving the smallest increase in the pooled within-cluster sum of squares, which is Ward's method on the Euclidean distances;
// out holds the merged pairs as 2 (n - 1) one-based observation numbers, each cluster named by its smallest member and the smaller name first
fn hc_eii(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []usize) -> err {
    let (d, e1) = mem.alloc[f64](a, n * n)
    let (mn, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                let df = x[q * n + i] - x[q * n + j]
                s += df * df
                q += 1usize
            }
            d[i * n + j] = math.sqrt[f64](s)
            j += 1usize
        }
        i += 1usize
    }
    let (t, he) = hcl.hclust(a, d, n, 8usize)
    if he != ok { ret he }
    var st = 0usize
    while st + 1usize < n {
        var la = 0usize
        var lb = 0usize
        if t.merge_a[st] < 0i32 { la = usize(0i32 - t.merge_a[st]) } else { la = mn[usize(t.merge_a[st]) - 1usize] }
        if t.merge_b[st] < 0i32 { lb = usize(0i32 - t.merge_b[st]) } else { lb = mn[usize(t.merge_b[st]) - 1usize] }
        var lo = la
        var hi = lb
        if lb < la {
            lo = lb
            hi = la
        }
        out[2usize * st] = lo
        out[2usize * st + 1usize] = hi
        mn[st] = lo
        st += 1usize
    }
    ret ok
}

// hclass(hc(data, "EII"), g): the group of each observation (0-based labels in order of first appearance) after the first n - g merges of the hierarchy
fn hc_eii_groups(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, lab: []usize) -> err {
    let (pairs, e1) = mem.alloc[usize](a, 2usize * n)
    let (root, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    let he = hc_eii(a, x, n, p, pairs)
    if he != ok { ret he }
    var i = 0usize
    while i < n {
        root[i] = i
        i += 1usize
    }
    var s = 0usize
    while s + g < n {
        let u = pairs[2usize * s] - 1usize
        let v = pairs[2usize * s + 1usize] - 1usize
        // the clusters are named by their smallest member: relabel every member of v's group
        let rv = root[v]
        let ru = root[u]
        i = 0usize
        while i < n {
            if root[i] == rv { root[i] = ru }
            i += 1usize
        }
        s += 1usize
    }
    var next = 0usize
    i = 0usize
    while i < n {
        var found = false
        var j = 0usize
        while j < i && !found {
            if root[j] == root[i] {
                lab[i] = lab[j]
                found = true
            }
            j += 1usize
        }
        if !found {
            lab[i] = next
            next += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the BIC of the model fitted by EM from the hc(data, "EII") partition into g groups, as mclustBIC(initialization = list(hcPairs = hc(data, "EII"))) reports it; NaN when the fit fails
fn bic_hc_eii(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, model: usize) -> f64 {
    let (lab, e1) = mem.alloc[usize](a, n)
    let (z, e2) = mem.alloc[f64](a, n * g)
    let (pro, e3) = mem.alloc[f64](a, g)
    let (mu, e4) = mem.alloc[f64](a, g * p)
    let (sg, e5) = mem.alloc[f64](a, g * p * p)
    let (inf, e6) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    if hc_eii_groups(a, x, n, p, g, lab) != ok { ret 0.0f64 / 0.0f64 }
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
    let ll = me_em(a, model, false, x, z, n, p, g, pro, mu, sg, inf)
    if ll != ll { ret ll }
    ret bic(me_label(model), ll, f64(n), f64(p), f64(g), false, false)
}

// the model names of the me_em codes
fn me_label(m: usize) -> str {
    if m == 0usize { ret "EII" }
    if m == 1usize { ret "VII" }
    if m == 2usize { ret "EEI" }
    if m == 3usize { ret "VVI" }
    if m == 4usize { ret "EEE" }
    if m == 5usize { ret "VVV" }
    if m == 6usize { ret "EVI" }
    if m == 7usize { ret "EVV" }
    ret "EEV"
}

// Mclust(data, G = gmin:gmax, modelNames = the nine me_em models, initialization = list(hcPairs = hc(data, "EII"))): the best BIC over the grid (the first maximum scanning groups, then models),
// out = (bic, G, model code, loglik); lab receives the 1-based classification by the largest posterior probability
fn mclust_select(a: *mem.Arena, x: []const f64, n: usize, p: usize, gmin: usize, gmax: usize, models: []const usize, lab: []usize, out: []f64) -> err {
    var best = 0.0f64 - 1.0e300f64
    var bg = 0usize
    var bm = 0usize
    var g = gmin
    while g <= gmax {
        var k = 0usize
        while k < models.len {
            let b = bic_hc_eii(a, x, n, p, g, models[k])
            if b == b && b > best {
                best = b
                bg = g
                bm = models[k]
            }
            k += 1usize
        }
        g += 1usize
    }
    if bg == 0usize { ret mem.Full }
    // refit the winner and classify
    let (labs, e1) = mem.alloc[usize](a, n)
    let (z, e2) = mem.alloc[f64](a, n * bg)
    let (pro, e3) = mem.alloc[f64](a, bg)
    let (mu, e4) = mem.alloc[f64](a, bg * p)
    let (sg, e5) = mem.alloc[f64](a, bg * p * p)
    let (inf, e6) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    let he = hc_eii_groups(a, x, n, p, bg, labs)
    if he != ok { ret he }
    var i = 0usize
    while i < n * bg {
        z[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        z[labs[i] * n + i] = 1.0f64
        i += 1usize
    }
    let ll = me_em(a, bm, false, x, z, n, p, bg, pro, mu, sg, inf)
    map(z, n, bg, lab)
    out[0usize] = best
    out[1usize] = f64(bg)
    out[2usize] = f64(bm)
    out[3usize] = ll
    ret ok
}

// classError(classification, class) when every class of either labelling has a unique best partner: the error rate and, in bad (0 or 1 per observation), the misclassified ones;
// both codings are 0-based; the larger of the two one-directional error sets is kept
fn class_error(a: *mem.Arena, cl: []const usize, tr: []const usize, bad: []usize) -> f64 {
    let n = cl.len
    var kc = 0usize
    var kt = 0usize
    var i = 0usize
    while i < n {
        if cl[i] + 1usize > kc { kc = cl[i] + 1usize }
        if tr[i] + 1usize > kt { kt = tr[i] + 1usize }
        i += 1usize
    }
    let (tab, e) = mem.alloc[f64](a, kc * kt)
    let (ma, e2) = mem.alloc[usize](a, kc)
    let (mb, e3) = mem.alloc[usize](a, kt)
    if e != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < kc * kt {
        tab[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        tab[tr[i] * kc + cl[i]] += 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < kc {
        var best = 0usize
        var t = 1usize
        while t < kt {
            if tab[t * kc + c] > tab[best * kc + c] { best = t }
            t += 1usize
        }
        ma[c] = best
        c += 1usize
    }
    var t2 = 0usize
    while t2 < kt {
        var best = 0usize
        var c2 = 1usize
        while c2 < kc {
            if tab[t2 * kc + c2] > tab[t2 * kc + best] { best = c2 }
            c2 += 1usize
        }
        mb[t2] = best
        t2 += 1usize
    }
    var one = 0usize
    var two = 0usize
    i = 0usize
    while i < n {
        if ma[cl[i]] != tr[i] { one += 1usize }
        if mb[tr[i]] != cl[i] { two += 1usize }
        i += 1usize
    }
    var cnt = 0usize
    i = 0usize
    while i < n {
        var is_bad = false
        if one > two { is_bad = ma[cl[i]] != tr[i] } else { is_bad = mb[tr[i]] != cl[i] }
        if is_bad {
            bad[i] = 1usize
            cnt += 1usize
        } else {
            bad[i] = 0usize
        }
        i += 1usize
    }
    ret f64(cnt) / f64(n)
}

// mclust::dmvnorm(x, mean, sigma, log): the multivariate normal density at one point of length d, sigma d by d column-major; log = true answers the log density
fn dmvnorm(a: *mem.Arena, x: []const f64, mean: []const f64, sigma: []const f64, lg: bool) -> f64 {
    let d = x.len
    let (l, e1) = mem.alloc[f64](a, d * d)
    let (z, e2) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    if !chol_lower(sigma, d, l) { ret 0.0f64 / 0.0f64 }
    // solve L z = x - mean by forward substitution
    var q = 0.0f64
    var logdet = 0.0f64
    var i = 0usize
    while i < d {
        var s = x[i] - mean[i]
        var j = 0usize
        while j < i {
            s -= l[j * d + i] * z[j]
            j += 1usize
        }
        z[i] = s / l[i * d + i]
        q += z[i] * z[i]
        logdet += 2.0f64 * math.log[f64](l[i * d + i])
        i += 1usize
    }
    let ld = 0.0f64 - 0.5f64 * (f64(d) * 1.8378770664093453f64 + logdet + q)
    if lg { ret ld }
    ret math.exp[f64](ld)
}
