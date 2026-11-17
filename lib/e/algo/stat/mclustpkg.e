// R mclust: the parameter counts and BIC of the covariance models, adjustedRandIndex and map.
//
// Not here: the EM fits themselves (me, em, mclustBIC), hierarchical initialisation, classError, unmap, the density and simulation routines.

use e.math
use e.mem
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

// model code: 0 EII, 1 VII, 2 EEI, 3 VVI, 4 EEE, 5 VVV
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
