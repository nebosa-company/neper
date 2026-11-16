// R vegan on a sites-by-species count matrix (row-major): the diversity indices (Shannon, Simpson, inverse Simpson, Pielou), richness, rarefied richness, Chao1, and the vegdist dissimilarities euclidean, manhattan, bray, kulczynski, canberra, gower, horn, morisita and jaccard (quantitative and binary).
//
// Not here: ordination, ACE, Fisher alpha, the remaining vegdist methods, permutation tests and the community-ecology tests.

use e.math
use e.math.nmath as nm

// diversity of row r: out = Shannon (natural log), Simpson 1 - sum p^2, inverse Simpson, Pielou evenness, richness, Chao1 (bias-corrected)
fn diversity(m: []const f64, nr: usize, nc: usize, r: usize, out: []f64) {
    var tot = 0.0f64
    var j = 0usize
    while j < nc {
        tot += m[r * nc + j]
        j += 1usize
    }
    var h = 0.0f64
    var sp = 0.0f64
    var s = 0.0f64
    var f1 = 0.0f64
    var f2 = 0.0f64
    j = 0usize
    while j < nc {
        let x = m[r * nc + j]
        if x > 0.0f64 {
            let p = x / tot
            h -= p * math.log[f64](p)
            sp += p * p
            s += 1.0f64
            if x == 1.0f64 { f1 += 1.0f64 }
            if x == 2.0f64 { f2 += 1.0f64 }
        }
        j += 1usize
    }
    out[0usize] = h
    out[1usize] = 1.0f64 - sp
    out[2usize] = 1.0f64 / sp
    out[3usize] = h / math.log[f64](s)
    out[4usize] = s
    out[5usize] = s + f1 * (f1 - 1.0f64) / (2.0f64 * (f2 + 1.0f64))
}

// vegan rarefy: expected richness of a subsample of size n from row r
fn rarefy(m: []const f64, nc: usize, r: usize, n: f64) -> f64 {
    var tot = 0.0f64
    var j = 0usize
    while j < nc {
        tot += m[r * nc + j]
        j += 1usize
    }
    var s = 0.0f64
    j = 0usize
    while j < nc {
        let x = m[r * nc + j]
        if x > 0.0f64 {
            var miss = 0.0f64
            if tot - x >= n { miss = math.exp[f64](nm.lgammafn(tot - x + 1.0f64) - nm.lgammafn(n + 1.0f64) - nm.lgammafn(tot - x - n + 1.0f64) - (nm.lgammafn(tot + 1.0f64) - nm.lgammafn(n + 1.0f64) - nm.lgammafn(tot - n + 1.0f64))) }
            s += 1.0f64 - miss
        }
        j += 1usize
    }
    ret s
}

// vegdist between rows a and b (morisita is clipped at 0 as vegan does, gower divides by the non-constant columns); method 0 euclidean, 1 manhattan, 2 bray, 3 kulczynski, 4 canberra, 5 gower, 6 horn, 7 morisita, 8 jaccard, 9 binary jaccard (binary bray gives the same ordering as 2B/(1+B))
fn vegdist(m: []const f64, nr: usize, nc: usize, ra: usize, rb: usize, method: usize) -> f64 {
    var sa = 0.0f64
    var sb = 0.0f64
    var sab = 0.0f64
    var smin = 0.0f64
    var sabs = 0.0f64
    var ssq = 0.0f64
    var saa = 0.0f64
    var sbb = 0.0f64
    var saa1 = 0.0f64
    var sbb1 = 0.0f64
    var can = 0.0f64
    var nz = 0.0f64
    var gw = 0.0f64
    var gcount = 0.0f64
    var j = 0usize
    while j < nc {
        var x = m[ra * nc + j]
        var y = m[rb * nc + j]
        if method == 9usize {
            if x > 0.0f64 { x = 1.0f64 }
            if y > 0.0f64 { y = 1.0f64 }
        }
        sa += x
        sb += y
        sab += x * y
        if x < y { smin += x } else { smin += y }
        sabs += math.abs[f64](x - y)
        ssq += (x - y) * (x - y)
        saa += x * x
        sbb += y * y
        saa1 += x * (x - 1.0f64)
        sbb1 += y * (y - 1.0f64)
        if x + y > 0.0f64 {
            can += math.abs[f64](x - y) / (x + y)
            nz += 1.0f64
        }
        var lo = 1.0e300f64
        var hi = 0.0f64 - 1.0e300f64
        var i = 0usize
        while i < nr {
            let v = m[i * nc + j]
            if v < lo { lo = v }
            if v > hi { hi = v }
            i += 1usize
        }
        if hi > lo {
            gw += math.abs[f64](x - y) / (hi - lo)
            gcount += 1.0f64
        }
        j += 1usize
    }
    if method == 0usize { ret math.sqrt[f64](ssq) }
    if method == 1usize { ret sabs }
    if method == 2usize || method == 9usize {
        let b = sabs / (sa + sb)
        if method == 9usize { ret 2.0f64 * b / (1.0f64 + b) }
        ret b
    }
    if method == 3usize { ret 1.0f64 - 0.5f64 * (smin / sa + smin / sb) }
    if method == 4usize { ret can / nz }
    if method == 5usize { ret gw / gcount }
    if method == 6usize { ret 1.0f64 - 2.0f64 * sab / ((saa / (sa * sa) + sbb / (sb * sb)) * sa * sb) }
    if method == 7usize {
        let d = 1.0f64 - 2.0f64 * sab / ((saa1 / (sa * (sa - 1.0f64)) + sbb1 / (sb * (sb - 1.0f64))) * sa * sb)
        if d < 1.0e-15f64 { ret 0.0f64 }
        ret d
    }
    let b = sabs / (sa + sb)
    ret 2.0f64 * b / (1.0f64 + b)
}
