// R ks kde.local.test in d dimensions (1 to 3, exact estimation on the common grid over both samples with the bandwidths given): the density
// difference with the optional mean adjustment, its variance, the chi-square statistic, the p-values and the Hochberg (1988) rejections.
//
// Not here: binned estimation, the default bandwidths of hpi and Hpi, min.ESS, kde objects in place of the data.

use e.algo.stat.classint as ci
use e.algo.stat.ks2dkde as kk
use e.algo.stat.ksnd as nd
use e.math
use e.math.nmath as nm
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the symmetric square root of an SPD d by d matrix
fn sqrtm(h: []const f64, d: usize, o: []f64) {
    var vals: [4]f64 = zero
    var vecs: [16]f64 = zero
    nd.jacobi(h, d, vals[0usize..4usize], vecs[0usize..16usize])
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                s += vecs[i * d + k] * math.sqrt[f64](vals[k]) * vecs[j * d + k]
                k += 1usize
            }
            o[i * d + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// the number of values at or below v in the ascending s
fn upper_count(s: []const f64, v: f64) -> usize {
    var lo = 0usize
    var hi = s.len
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if s[mid] <= v {
            lo = mid + 1usize
        } else {
            hi = mid
        }
    }
    ret lo
}

// kde.local.test(x1, x2, H1, H2, binned = FALSE, mean.adj, signif.level) at the grid of m points per dimension. diff, vr, x2s and pv receive m^d values;
// cnt[0] is the number of cells with a significant positive difference, cnt[1] negative, cnt[2] the number of tests.
fn local_test(a: *mem.Arena, x1: []const f64, n1: usize, x2: []const f64, n2: usize, d: usize, h1: []const f64, h2: []const f64, m: usize, mean_adj: bool, alpha: f64, diff: []f64, vr: []f64, x2s: []f64, pv: []f64, cnt: []f64) -> err {
    let total = nd.pow_usize(m, d)
    var s1: [16]f64 = zero
    var s2: [16]f64 = zero
    sqrtm(h1, d, s1[0usize..16usize])
    sqrtm(h2, d, s2[0usize..16usize])
    var pr = 1.0f64
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var k = 0usize
        while k < d {
            s += s1[j * d + k] * s2[k * d + j]
            k += 1usize
        }
        pr = pr * s
        j += 1usize
    }
    let tol = math.sqrt[f64](math.pow[f64](pr, 1.0f64 / f64(d)))
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (f1, e2) = mem.alloc[f64](a, total)
    let (f2, e3) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    j = 0usize
    while j < d {
        var lo = x1[j]
        var hi = x1[j]
        var i = 0usize
        while i < n1 {
            if x1[i * d + j] < lo { lo = x1[i * d + j] }
            if x1[i * d + j] > hi { hi = x1[i * d + j] }
            i += 1usize
        }
        i = 0usize
        while i < n2 {
            if x2[i * d + j] < lo { lo = x2[i * d + j] }
            if x2[i * d + j] > hi { hi = x2[i * d + j] }
            i += 1usize
        }
        kk.seq_len_out(lo - 3.7f64 * tol, hi + 3.7f64 * tol, m, gp[j * m..j * m + m])
        j += 1usize
    }
    nd.kde_grid_on(a, x1, n1, d, h1, m, gp, f1, 0usize)
    nd.kde_grid_on(a, x2, n2, d, h2, m, gp, f2, 0usize)
    var g1: []f64 = f1
    var g2: []f64 = f2
    if mean_adj {
        let (t1, e4) = mem.alloc[f64](a, total)
        let (t2, e5) = mem.alloc[f64](a, total)
        if e4 != ok || e5 != ok { ret e4 }
        // for d above 1 ks adds up only the first element of the Hessian difference (its loop runs over the one-element list D2fhat), so that is what is built
        var wt = 1usize
        if d > 1usize { wt = 2usize }
        nd.kde_grid_on(a, x1, n1, d, h1, m, gp, t1, wt)
        nd.kde_grid_on(a, x2, n2, d, h2, m, gp, t2, wt)
        g1 = t1
        g2 = t2
    }
    var i1: [16]f64 = zero
    var i2: [16]f64 = zero
    let det1 = nd.inv_det(h1, d, i1[0usize..16usize])
    let det2 = nd.inv_det(h2, d, i2[0usize..16usize])
    let rk = math.pow[f64](4.0f64 * 3.141592653589793f64, 0.0f64 - f64(d) / 2.0f64)
    var ntest = 0usize
    var i = 0usize
    while i < total {
        var hd = 0.0f64
        if mean_adj {
            if d == 1usize {
                hd = g1[i] - g2[i]
            } else {
                hd = h1[0usize] * g1[i] - h2[0usize] * g2[i]
            }
        }
        diff[i] = f1[i] - f2[i] - 0.5f64 * hd
        vr[i] = (f1[i] / (f64(n1) * math.sqrt[f64](det1)) + f2[i] / (f64(n2) * math.sqrt[f64](det2))) * rk
        x2s[i] = diff[i] * diff[i] / vr[i]
        pv[i] = 1.0f64 - nm.pchisq(x2s[i], 1.0f64, true, false)
        if pv[i] != pv[i] {
            if d > 1usize { pv[i] = 0.0f64 }
        }
        if pv[i] == pv[i] { ntest += 1usize }
        i += 1usize
    }
    let (ps, e6) = mem.alloc[f64](a, ntest)
    if e6 != ok { ret e6 }
    var at = 0usize
    i = 0usize
    while i < total {
        if pv[i] == pv[i] {
            ps[at] = pv[i]
            at += 1usize
        }
        i += 1usize
    }
    let (sorted, e7) = ci.sorted_copy(a, ps)
    if e7 != ok { ret e7 }
    var npos = 0usize
    var nneg = 0usize
    i = 0usize
    while i < total {
        var sig = false
        if pv[i] == 0.0f64 { sig = true }
        if pv[i] > 0.0f64 {
            let k = upper_count(sorted, pv[i])
            if pv[i] <= alpha / f64(ntest + 1usize - k) { sig = true }
        }
        if sig && diff[i] > 0.0f64 { npos += 1usize }
        if sig && diff[i] < 0.0f64 { nneg += 1usize }
        i += 1usize
    }
    cnt[0usize] = f64(npos)
    cnt[1usize] = f64(nneg)
    cnt[2usize] = f64(ntest)
    ret ok
}
