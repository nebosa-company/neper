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
