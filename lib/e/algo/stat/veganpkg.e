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

// log of the binomial coefficient, through lgamma
fn lchoose(n: f64, k: f64) -> f64 {
    ret nm.lgammafn(n + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(n - k + 1.0f64)
}

// R's phyper(q, m, n, k, lower.tail = TRUE): the hypergeometric CDF, summed directly because the count
// matrix a vegdist pair sees has at most a few dozen species.
fn hyper_cdf(q: f64, m: f64, n: f64, k: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    var hi = q
    if hi > m { hi = m }
    if hi > k { hi = k }
    var lo = k - n
    if lo < 0.0f64 { lo = 0.0f64 }
    let den = lchoose(m + n, k)
    var sum = 0.0f64
    var i = lo
    while i <= hi {
        sum += math.exp[f64](lchoose(m, i) + lchoose(n, k - i) - den)
        i += 1.0f64
    }
    ret sum
}

// vegdist between rows a and b (morisita is clipped at 0 as vegan does, gower divides by the non-constant columns); method 0 euclidean, 1 manhattan, 2 bray, 3 kulczynski, 4 canberra, 5 gower, 6 horn, 7 morisita, 8 jaccard, 9 binary jaccard (binary bray gives the same ordering as 2B/(1+B)), 10 altGower (|a - b| averaged over the sites where not both are zero), 11 cao (the entropy term of Cao et al. with values below 0.1 floored, natural log), 12 clark (((a - b)/(a + b))^2 averaged over the sites where not both are zero, square rooted)
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
    var alt = 0.0f64
    var altc = 0.0f64
    var cao = 0.0f64
    var caoc = 0.0f64
    var clark = 0.0f64
    var clarkc = 0.0f64
    var ctot_a = 0.0f64
    var ctot_b = 0.0f64
    var cshare_a = 0.0f64
    var cshare_b = 0.0f64
    var cshare1_a = 0.0f64
    var cshare1_b = 0.0f64
    var a_once = 0.0f64
    var a_twice = 0.0f64
    var b_once = 0.0f64
    var b_twice = 0.0f64
    var rsim = 0.0f64
    var rt1 = 0.0f64
    var rt2 = 0.0f64
    var millar = 0.0f64
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
        // Chao-Jaccard's terms: vegan counts a value within 0.01 of 1 or 2 as a singleton or doubleton
        ctot_a += x
        ctot_b += y
        if x > 0.0f64 && y > 0.0f64 {
            cshare_a += x
            cshare_b += y
            if math.abs[f64](y - 1.0f64) < 0.01f64 {
                cshare1_a += x
                b_once += 1.0f64
            } else if math.abs[f64](y - 2.0f64) < 0.01f64 {
                b_twice += 1.0f64
            }
            if math.abs[f64](x - 1.0f64) < 0.01f64 {
                cshare1_b += y
                a_once += 1.0f64
            } else if math.abs[f64](x - 2.0f64) < 0.01f64 {
                a_twice += 1.0f64
            }
        }
        // Raup-Crick's presence/absence counts
        if x > 0.0f64 && y > 0.0f64 { rsim += 1.0f64 }
        if x > 0.0f64 { rt1 += 1.0f64 }
        if y > 0.0f64 { rt2 += 1.0f64 }
        if x + y > 0.0f64 {
            can += math.abs[f64](x - y) / (x + y)
            nz += 1.0f64
            // Millar's binomial deviance term
            let nk = x + y
            let lnnk = math.log[f64](nk)
            var mt1 = 0.0f64
            if x > 0.0f64 { mt1 = x * (math.log[f64](x) - lnnk) }
            var mt2 = 0.0f64
            if y > 0.0f64 { mt2 = y * (math.log[f64](y) - lnnk) }
            millar += (mt1 + mt2 + nk * math.log[f64](2.0f64)) / nk
        }
        if x > 0.0f64 || y > 0.0f64 {
            alt += math.abs[f64](x - y)
            altc += 1.0f64
            // clark answers an infinite term when the pair sums to zero (both negative), as vegan does
            let denom = x + y
            if denom > 0.0f64 {
                let t = (x - y) / denom
                clark += t * t
            } else {
                clark += 1.0e300f64
            }
            clarkc += 1.0f64
            // cao: a value below 0.1 is floored to 0.1, log(t1) - log(2) - (x1 log x2 + x2 log x1)/t1
            var x1 = x
            var x2 = y
            if x1 < 0.1f64 { x1 = 0.1f64 }
            if x2 < 0.1f64 { x2 = 0.1f64 }
            let t1 = x1 + x2
            cao += math.log[f64](t1) - math.log[f64](2.0f64) - (x1 * math.log[f64](x2) + x2 * math.log[f64](x1)) / t1
            caoc += 1.0f64
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
    if method == 10usize {
        if altc == 0.0f64 { ret 0.0f64 / 0.0f64 }
        ret alt / altc
    }
    if method == 11usize {
        if caoc == 0.0f64 { ret 0.0f64 / 0.0f64 }
        let d = cao / caoc
        if d < 0.0f64 { ret 0.0f64 }
        ret d
    }
    if method == 12usize {
        if clarkc == 0.0f64 { ret 0.0f64 / 0.0f64 }
        ret math.sqrt[f64](clark / clarkc)
    }
    if method == 13usize {
        // Chao-Jaccard: U and V are the shared-abundance corrections for each side, then 1 - UV/(U + V - UV)
        var u = cshare_a / ctot_a
        if cshare1_a > 0.0f64 {
            var jonce = b_once
            var jtwice = b_twice
            if jonce < 1.0f64 { jonce = 1.0f64 }
            if jtwice < 1.0f64 { jtwice = 1.0f64 }
            u += (ctot_b - 1.0f64) / ctot_b * jonce / jtwice / 2.0f64 * cshare1_a / ctot_a
        }
        if u > 1.0f64 { u = 1.0f64 }
        var v = cshare_b / ctot_b
        if cshare1_b > 0.0f64 {
            var ionce = a_once
            var itwice = a_twice
            if ionce < 1.0f64 { ionce = 1.0f64 }
            if itwice < 1.0f64 { itwice = 1.0f64 }
            v += (ctot_a - 1.0f64) / ctot_a * ionce / itwice / 2.0f64 * cshare1_b / ctot_b
        }
        if v > 1.0f64 { v = 1.0f64 }
        if u <= 0.0f64 || v <= 0.0f64 { ret 1.0f64 }
        let d = 1.0f64 - u * v / (u + v - u * v)
        if d < 0.0f64 { ret 0.0f64 }
        ret d
    }
    if method == 15usize {
        // mountford: the Newton iteration on exp(d a) + exp(d b) - exp(d (a + b - j)) = 1; the two
        // degenerate cases set the root theta, and the answer is ln(2) - theta (so no shared species
        // answers ln(2), and one richness contained in the other answers 0)
        let ln2 = math.log[f64](2.0f64)
        if rt1 == 0.0f64 || rt2 == 0.0f64 { ret 0.0f64 / 0.0f64 }
        if rsim == 0.0f64 { ret ln2 }
        if rsim == rt1 || rsim == rt2 { ret 0.0f64 }
        let a = rt1
        let b = rt2
        var d = 2.0f64 * rsim / (2.0f64 * a * b - (a + b) * rsim)
        var iter = 0usize
        while iter < 20usize {
            let od = d
            let fa = math.exp[f64](d * a)
            let fb = math.exp[f64](d * b)
            let fj = math.exp[f64](d * (a + b - rsim))
            let f = fa + fb - fj - 1.0f64
            let fp = a * fa + b * fb - (a + b - rsim) * fj
            d = d - f / fp
            let diff = math.abs[f64](od - d)
            if diff / od < 1.0e-5f64 || diff < 1.0e-12f64 { break }
            iter += 1usize
        }
        ret ln2 - d
    }
    if method == 16usize {
        // binomial: Millar's deviance sum, clamped at 0
        if millar < 0.0f64 { ret 0.0f64 }
        ret millar
    }
    if method == 14usize {
        // Raup-Crick: 1 - phyper(sim - 1, min richness, count - min, max richness), count the sites
        let jj = rsim - 1.0f64
        var a = rt1
        var b = rt2
        if a > b {
            a = rt2
            b = rt1
        }
        ret 1.0f64 - hyper_cdf(jj, a, f64(nc) - a, b)
    }
    let b = sabs / (sa + sb)
    ret 2.0f64 * b / (1.0f64 + b)
}
