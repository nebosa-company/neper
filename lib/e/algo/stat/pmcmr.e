// R PMCMRplus: the Kruskal-Wallis all-pairs post-hoc tests on a one-way layout: Dunn's z test, Conover's t test (also with the Tukey
// single-step p value) and the Tukey-Kramer-Nemenyi test, with the tie corrections of the package, plus the Holm adjustment of p values.
//
// Not here: the many-to-one and other design tests of the package (van der Waerden, Steel, Quade, Friedman post-hoc and the rest),
// the other adjustment methods, the chi-square form of Nemenyi's test.

use e.math
use e.algo.stat.steeltab as stt
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Ranks = struct { n: f64, k: usize, ties_dunn: f64, ties_kw: f64, h: f64, s2: f64 }

// average ranks of x written to r
fn rank_avg(a: *mem.Arena, x: []const f64, r: []f64) -> err {
    let n = x.len
    let (idx, e) = mem.alloc[usize](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = idx[i]
        var j = i
        while j > 0usize && x[idx[j - 1usize]] > x[t] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = t
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && x[idx[j + 1usize]] == x[idx[i]] { j += 1usize }
        let avg = (f64(i) + f64(j)) / 2.0f64 + 1.0f64
        var q = i
        while q <= j {
            r[idx[q]] = avg
            q += 1usize
        }
        i = j + 1usize
    }
    ret ok
}

// group means of ranks and sizes; the common quantities of the three tests
fn setup(a: *mem.Arena, x: []const f64, grp: []const usize, k: usize, rbar: []f64, rn: []f64) -> (Ranks, err) {
    let n = x.len
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (zero, e) }
    let e2 = rank_avg(a, x, r)
    if e2 != ok { ret (zero, e2) }
    var i = 0usize
    while i < k {
        rbar[i] = 0.0f64
        rn[i] = 0.0f64
        i += 1usize
    }
    var sr2 = 0.0f64
    i = 0usize
    while i < n {
        rbar[grp[i] - 1usize] += r[i]
        rn[grp[i] - 1usize] += 1.0f64
        sr2 += r[i] * r[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        rbar[i] = rbar[i] / rn[i]
        i += 1usize
    }
    let nf = f64(n)
    // tie groups from the sorted values
    var tsum = 0.0f64
    let (s, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret (zero, e3) }
    i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && s[j + 1usize] == s[i] { j += 1usize }
        let tt = f64(j - i + 1usize)
        tsum += tt * tt * tt - tt
        i = j + 1usize
    }
    var hs = 0.0f64
    i = 0usize
    while i < k {
        hs += rn[i] * (rbar[i] - (nf + 1.0f64) / 2.0f64) * (rbar[i] - (nf + 1.0f64) / 2.0f64)
        i += 1usize
    }
    let ckw = 1.0f64 - tsum / (nf * nf * nf - nf)
    var s2 = nf * (nf + 1.0f64) / 12.0f64
    if ckw != 1.0f64 { s2 = (sr2 - nf * ((nf + 1.0f64) * (nf + 1.0f64) / 4.0f64)) / (nf - 1.0f64) }
    ret (Ranks { n: nf, k: k, ties_dunn: tsum / (12.0f64 * (nf - 1.0f64)), ties_kw: ckw, h: 12.0f64 / (nf * (nf + 1.0f64)) * hs, s2: s2 }, ok)
}

// Dunn: z and the unadjusted two-sided p
fn dunn(q: Ranks, rbar: []const f64, rn: []const f64, i: usize, j: usize) -> (f64, f64) {
    var dif = rbar[i] - rbar[j]
    if dif < 0.0f64 { dif = 0.0f64 - dif }
    let z = dif / math.sqrt[f64]((q.n * (q.n + 1.0f64) / 12.0f64 - q.ties_dunn) * (1.0f64 / rn[i] + 1.0f64 / rn[j]))
    ret (z, 2.0f64 * dist.pnorm(0.0f64 - z, 0.0f64, 1.0f64, true, false))
}

// Conover: the signed t statistic, its unadjusted two-sided p, and the single-step Tukey p
fn conover(q: Ranks, rbar: []const f64, rn: []const f64, i: usize, j: usize) -> (f64, f64, f64) {
    let hc = q.h / q.ties_kw
    let df = q.n - f64(q.k)
    let b = 1.0f64 / rn[i] + 1.0f64 / rn[j]
    let d = (q.n - 1.0f64 - hc) / df
    let t = (rbar[i] - rbar[j]) / math.sqrt[f64](q.s2 * b * d)
    var at = t
    if at < 0.0f64 { at = 0.0f64 - at }
    let p = 2.0f64 * nb.pt(0.0f64 - at, df, true, false)
    let pt = nb.ptukey(math.sqrt[f64](2.0f64) * at, 1.0f64, f64(q.k), df, false, false)
    ret (t, p, pt)
}

// Tukey-Kramer-Nemenyi: sqrt(2) times the studentised rank difference and its p value (infinite degrees of freedom)
fn nemenyi(q: Ranks, rbar: []const f64, rn: []const f64, i: usize, j: usize) -> (f64, f64) {
    var dif = rbar[i] - rbar[j]
    if dif < 0.0f64 { dif = 0.0f64 - dif }
    let qv = dif / math.sqrt[f64](q.n * (q.n + 1.0f64) / 12.0f64 * (1.0f64 / rn[i] + 1.0f64 / rn[j])) * math.sqrt[f64](2.0f64)
    ret (qv, 1.0f64 - nb.ptukey(qv, 1.0f64, f64(q.k), 1.0e300f64, true, false))
}

// p.adjust(p, "holm") in place
fn holm(a: *mem.Arena, p: []f64) -> err {
    let m = p.len
    let (idx, e) = mem.alloc[usize](a, m)
    if e != ok { ret e }
    var i = 0usize
    while i < m {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < m {
        let t = idx[i]
        var j = i
        while j > 0usize && p[idx[j - 1usize]] > p[t] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = t
        i += 1usize
    }
    var run = 0.0f64
    i = 0usize
    while i < m {
        var v = (f64(m) - f64(i)) * p[idx[i]]
        if v > 1.0f64 { v = 1.0f64 }
        if v > run { run = v }
        idx[i] = idx[i]
        p[idx[i]] = run
        i += 1usize
    }
    ret ok
}

// order of p (ascending, or descending), stable: the index of each rank
fn order_idx(a: *mem.Arena, p: []const f64, desc: bool, idx: []usize) -> err {
    let m = p.len
    var i = 0usize
    while i < m {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < m {
        let t = idx[i]
        var j = i
        while j > 0usize {
            var swap = p[idx[j - 1usize]] > p[t]
            if desc { swap = p[idx[j - 1usize]] < p[t] }
            if !swap { break }
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = t
        i += 1usize
    }
    ret ok
}

// p.adjust(p, method) in place: kind 0 holm, 1 hochberg, 2 hommel, 3 bonferroni, 4 BH, 5 BY
fn p_adjust(a: *mem.Arena, p: []f64, kind: usize) -> err {
    let n = p.len
    let nf = f64(n)
    let (o, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    let (res, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    if kind == 3usize {
        var i = 0usize
        while i < n {
            var v = nf * p[i]
            if v > 1.0f64 { v = 1.0f64 }
            p[i] = v
            i += 1usize
        }
        ret ok
    }
    if kind == 0usize {
        let e = order_idx(a, p, false, o)
        if e != ok { ret e }
        var run = 0.0f64
        var i = 0usize
        while i < n {
            var v = (nf - f64(i)) * p[o[i]]
            if v > 1.0f64 { v = 1.0f64 }
            if v > run { run = v }
            res[o[i]] = run
            i += 1usize
        }
    } else if kind == 1usize || kind == 4usize || kind == 5usize {
        let e = order_idx(a, p, true, o)
        if e != ok { ret e }
        var q = 1.0f64
        if kind == 5usize {
            q = 0.0f64
            var k = 1usize
            while k <= n {
                q += 1.0f64 / f64(k)
                k += 1usize
            }
        }
        var run = 1.0e300f64
        var i = 0usize
        while i < n {
            // the i-th largest has index n - i in 1..n
            let rank = f64(n - i)
            var v = 0.0f64
            if kind == 1usize { v = (nf + 1.0f64 - rank) * p[o[i]] } else { v = q * nf / rank * p[o[i]] }
            if v < run { run = v }
            var w = run
            if w > 1.0f64 { w = 1.0f64 }
            res[o[i]] = w
            i += 1usize
        }
    } else {
        let e = order_idx(a, p, false, o)
        if e != ok { ret e }
        let (ps, e3) = mem.alloc[f64](a, n)
        if e3 != ok { ret e3 }
        let (qv, e4) = mem.alloc[f64](a, n)
        if e4 != ok { ret e4 }
        let (pa, e5) = mem.alloc[f64](a, n)
        if e5 != ok { ret e5 }
        var i = 0usize
        while i < n {
            ps[i] = p[o[i]]
            i += 1usize
        }
        var mn = 1.0e300f64
        i = 0usize
        while i < n {
            let v = nf * ps[i] / f64(i + 1usize)
            if v < mn { mn = v }
            i += 1usize
        }
        i = 0usize
        while i < n {
            qv[i] = mn
            pa[i] = mn
            i += 1usize
        }
        var m = n - 1usize
        while m >= 2usize {
            let n1 = n - m + 1usize
            var q1 = 1.0e300f64
            var j = 0usize
            while j < m - 1usize {
                let v = f64(m) * ps[n - m + 1usize + j] / f64(j + 2usize)
                if v < q1 { q1 = v }
                j += 1usize
            }
            j = 0usize
            while j < n1 {
                let v = f64(m) * ps[j]
                if v < q1 { qv[j] = v } else { qv[j] = q1 }
                j += 1usize
            }
            j = n - m + 1usize
            while j < n {
                qv[j] = qv[n - m]
                j += 1usize
            }
            j = 0usize
            while j < n {
                if qv[j] > pa[j] { pa[j] = qv[j] }
                j += 1usize
            }
            m -= 1usize
        }
        i = 0usize
        while i < n {
            var v = pa[i]
            if ps[i] > v { v = ps[i] }
            res[o[i]] = v
            i += 1usize
        }
    }
    var i = 0usize
    while i < n {
        p[i] = res[i]
        i += 1usize
    }
    ret ok
}

// Friedman all-pairs tests on a complete block design (y is n blocks by k treatments, row-major): the ranks within each block are averaged for ties. kind 0 Nemenyi (the statistic
// sqrt(2) |mean rank difference| / sqrt(k (k + 1) / (6 n)) and its single-step Tukey p with infinite df), kind 1 Conover with the Tukey p, kind 2 Conover's t and its unadjusted p.
// Kind 3 is Demsar's many-to-one z (the signed mean rank difference over sqrt(k (k + 1) / (6 n)), normal p). The pair is (row i, column j) of the result table, so i > j; the Conover statistic is the signed rank sum difference R_j - R_i over sqrt(A B).
fn frd_pair(a: *mem.Arena, n: usize, k: usize, y: []const f64, kind: usize, i: usize, j: usize) -> (f64, f64, err) {
    let (r, e0) = mem.alloc[f64](a, n * k)
    let (row, e1) = mem.alloc[f64](a, k)
    let (rr, e2) = mem.alloc[f64](a, k)
    let (rs, e3) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var c = 0usize
    while c < k {
        rs[c] = 0.0f64
        c += 1usize
    }
    var b = 0usize
    var sumsq = 0.0f64
    while b < n {
        c = 0usize
        while c < k {
            row[c] = y[b * k + c]
            c += 1usize
        }
        let er = rank_avg(a, row, rr)
        if er != ok { ret (0.0f64, 0.0f64, er) }
        c = 0usize
        while c < k {
            rs[c] += rr[c]
            sumsq += rr[c] * rr[c]
            c += 1usize
        }
        b += 1usize
    }
    let nf = f64(n)
    let kf = f64(k)
    if kind == 6usize {
        // frdAllPairsExactTest: the rank-sum difference R_i - R_j and its exact two-sided p, the tail of the n-fold convolution of the per-block difference distribution (Eisinga et al.)
        let dsum = rs[i] - rs[j]
        var ad = dsum
        if ad < 0.0f64 { ad = 0.0f64 - ad }
        ret (dsum, frd_exact_p(n, k, usize(math.floor[f64](ad + 0.5f64))), ok)
    }
    if kind == 5usize {
        // frdAllPairsSiegelTest: the mean rank difference over sqrt(k (k + 1) / (6 n)) and its two-sided normal p (unadjusted)
        var dsg = (rs[i] - rs[j]) / nf
        if dsg < 0.0f64 { dsg = 0.0f64 - dsg }
        let zsg = dsg / math.sqrt[f64](kf * (kf + 1.0f64) / (6.0f64 * nf))
        ret (zsg, 2.0f64 * dist.pnorm(0.0f64 - zsg, 0.0f64, 1.0f64, true, false), ok)
    }
    if kind == 4usize {
        // frdManyOneNemenyiTest: the rank-sum difference over sqrt(n k (k + 1) / 6) and its single-step p, 1 - P(all |Z| < |stat|) for k - 1 equicorrelated (1/2) normals
        let zn = (rs[i] - rs[j]) / math.sqrt[f64](nf * kf * (kf + 1.0f64) / 6.0f64)
        var azn = zn
        if azn < 0.0f64 { azn = 0.0f64 - azn }
        ret (zn, 1.0f64 - mvn_equicorr_half(azn, k - 1usize), ok)
    }
    if kind == 3usize {
        let zd = (rs[i] - rs[j]) / nf / math.sqrt[f64](kf * (kf + 1.0f64) / (6.0f64 * nf))
        var az = zd
        if az < 0.0f64 { az = 0.0f64 - az }
        ret (zd, 2.0f64 * dist.pnorm(0.0f64 - az, 0.0f64, 1.0f64, true, false), ok)
    }
    if kind == 0usize {
        var dif = (rs[i] - rs[j]) / nf
        if dif < 0.0f64 { dif = 0.0f64 - dif }
        let q = dif / math.sqrt[f64](kf * (kf + 1.0f64) / (6.0f64 * nf)) * math.sqrt[f64](2.0f64)
        ret (q, 1.0f64 - nb.ptukey(q, 1.0f64, kf, 1.0e300f64, true, false), ok)
    }
    let s2 = (sumsq - kf * nf * (kf + 1.0f64) * (kf + 1.0f64) / 4.0f64) / (kf - 1.0f64)
    var t2 = 0.0f64
    c = 0usize
    while c < k {
        let dd = rs[c] - nf * (kf + 1.0f64) / 2.0f64
        t2 += dd * dd
        c += 1usize
    }
    t2 = t2 / s2
    let df = nf * kf - kf - nf + 1.0f64
    let aa = s2 * (2.0f64 * nf * (kf - 1.0f64)) / df
    let bb = 1.0f64 - t2 / (nf * (kf - 1.0f64))
    let diff = rs[j] - rs[i]
    let tv = diff / (math.sqrt[f64](aa) * math.sqrt[f64](bb))
    var at = tv
    if at < 0.0f64 { at = 0.0f64 - at }
    if kind == 1usize {
        let qv = math.sqrt[f64](2.0f64) * at
        ret (math.sqrt[f64](2.0f64) * tv, nb.ptukey(qv, 1.0f64, kf, 1.0e300f64, false, false), ok)
    }
    ret (tv, 2.0f64 * nb.pt(0.0f64 - at, df, true, false), ok)
}

// van der Waerden all-pairs test: normal scores qnorm(rank / (n + 1)) of the pooled sample (or, with exact_scores, the expected normal order statistics, the normal scores test); the statistic of cell (row i, column j), i > j, is
// |mean score_i - mean score_j| / sqrt(s2 (n - 1 - T) / (n - k) (1 / n_i + 1 / n_j)). Answers (t, unadjusted two-sided p, single-step Tukey p).
fn vdw_pair(a: *mem.Arena, n: usize, k: usize, x: []const f64, grp: []const usize, i: usize, j: usize, signed: bool, exact_scores: bool) -> (f64, f64, f64, err) {
    let (r, e0) = mem.alloc[f64](a, n)
    let (aj, e1) = mem.alloc[f64](a, k)
    let (nj, e2) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, mem.Full) }
    let (eij, e9) = mem.alloc[f64](a, n)
    if e9 != ok { ret (0.0f64, 0.0f64, 0.0f64, mem.Full) }
    if exact_scores { norm_order(n, eij) }
    let er = rank_avg(a, x, r)
    if er != ok { ret (0.0f64, 0.0f64, 0.0f64, er) }
    var c = 0usize
    while c < k {
        aj[c] = 0.0f64
        nj[c] = 0.0f64
        c += 1usize
    }
    let nf = f64(n)
    var ss = 0.0f64
    var t = 0usize
    while t < n {
        var z = dist.qnorm(r[t] / (nf + 1.0f64), 0.0f64, 1.0f64, true, false)
        if exact_scores { z = eij[usize(r[t]) - 1usize] }
        aj[grp[t]] += z
        nj[grp[t]] += 1.0f64
        ss += z * z
        t += 1usize
    }
    let s2 = ss / (nf - 1.0f64)
    var stat = 0.0f64
    c = 0usize
    while c < k {
        stat += aj[c] * aj[c] / nj[c]
        c += 1usize
    }
    stat = stat / s2
    let kf = f64(k)
    var dif = aj[i] / nj[i] - aj[j] / nj[j]
    if dif < 0.0f64 && !signed { dif = 0.0f64 - dif }
    let tv = dif / math.sqrt[f64](s2 * (nf - 1.0f64 - stat) / (nf - kf) * (1.0f64 / nj[i] + 1.0f64 / nj[j]))
    var at = tv
    if at < 0.0f64 { at = 0.0f64 - at }
    let p = 2.0f64 * nb.pt(0.0f64 - at, nf - kf, true, false)
    let pt = nb.ptukey(math.sqrt[f64](2.0f64) * at, 1.0f64, kf, nf - kf, false, false)
    ret (tv, p, pt, ok)
}

// Quade all-pairs test on a complete block design (y is b blocks by k treatments, row-major): ranks within blocks, block ranges ranked, s = q (r - (k + 1) / 2). dist 0 the t form
// (|S_i - S_j| / sqrt(2 b (A - B) / ((b - 1) (k - 1))), two-sided p at (b - 1)(k - 1) df), dist 1 the normal form on the weighted rank sums. Answers (statistic, unadjusted p).
fn quade_pair(a: *mem.Arena, b: usize, k: usize, y: []const f64, dist_kind: usize, i: usize, j: usize) -> (f64, f64, err) {
    let (rng, e0) = mem.alloc[f64](a, b)
    let (q, e1) = mem.alloc[f64](a, b)
    let (r, e2) = mem.alloc[f64](a, b * k)
    let (row, e3) = mem.alloc[f64](a, k)
    let (rr, e4) = mem.alloc[f64](a, k)
    let (ss, e5) = mem.alloc[f64](a, k)
    let (ww, e6) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var t = 0usize
    while t < b {
        var lo = y[t * k]
        var hi = y[t * k]
        var c = 0usize
        while c < k {
            row[c] = y[t * k + c]
            if row[c] < lo { lo = row[c] }
            if row[c] > hi { hi = row[c] }
            c += 1usize
        }
        rng[t] = hi - lo
        let er = rank_avg(a, row, rr)
        if er != ok { ret (0.0f64, 0.0f64, er) }
        c = 0usize
        while c < k {
            r[t * k + c] = rr[c]
            c += 1usize
        }
        t += 1usize
    }
    let eq = rank_avg(a, rng, q)
    if eq != ok { ret (0.0f64, 0.0f64, eq) }
    let bf = f64(b)
    let kf = f64(k)
    var c = 0usize
    while c < k {
        ss[c] = 0.0f64
        ww[c] = 0.0f64
        c += 1usize
    }
    var aa = 0.0f64
    t = 0usize
    while t < b {
        c = 0usize
        while c < k {
            let s = q[t] * (r[t * k + c] - (kf + 1.0f64) / 2.0f64)
            aa += s * s
            ss[c] += s
            ww[c] += q[t] * r[t * k + c]
            c += 1usize
        }
        t += 1usize
    }
    if dist_kind == 0usize {
        var bb = 0.0f64
        c = 0usize
        while c < k {
            bb += ss[c] * ss[c]
            c += 1usize
        }
        bb = bb / bf
        let denom = math.sqrt[f64](2.0f64 * bf * (aa - bb) / ((bf - 1.0f64) * (kf - 1.0f64)))
        var dif = ss[i] - ss[j]
        if dif < 0.0f64 { dif = 0.0f64 - dif }
        let tv = dif / denom
        ret (tv, 2.0f64 * nb.pt(0.0f64 - tv, (bf - 1.0f64) * (kf - 1.0f64), true, false), ok)
    }
    let n = bf * kf
    let denom = math.sqrt[f64]((kf * (kf + 1.0f64) * (2.0f64 * n + 1.0f64) * (kf - 1.0f64)) / (18.0f64 * n * (n + 1.0f64)))
    let ff = 1.0f64 / (bf * (bf + 1.0f64) / 2.0f64)
    var dz = ww[i] * ff - ww[j] * ff
    if dz < 0.0f64 { dz = 0.0f64 - dz }
    let zv = dz / denom
    ret (zv, 2.0f64 * dist.pnorm(0.0f64 - zv, 0.0f64, 1.0f64, true, false), ok)
}

// Dunn's many-to-one test against group 0: the signed z of (mean rank_j - mean rank_0) and its two-sided p (ties corrected as in dunn)
fn dunn_many(q: Ranks, rbar: []const f64, rn: []const f64, j: usize) -> (f64, f64) {
    let dif = rbar[j] - rbar[0usize]
    let z = dif / math.sqrt[f64]((q.n * (q.n + 1.0f64) / 12.0f64 - q.ties_dunn) * (1.0f64 / rn[0usize] + 1.0f64 / rn[j]))
    var az = z
    if az < 0.0f64 { az = 0.0f64 - az }
    ret (z, 2.0f64 * dist.pnorm(0.0f64 - az, 0.0f64, 1.0f64, true, false))
}

// manyOneUTest's statistic of group j against group 0: the Mann-Whitney U (smaller of the two) standardised with the tie-corrected variance, signed negative when the rank sum
// of group 0 is the smaller (normal approximation, as PMCMRplus). The two-sided p is 2 pnorm(-|z|).
fn manyone_u(a: *mem.Arena, x: []const f64, grp: []const usize, g0: usize, j: usize) -> (f64, err) {
    let n = x.len
    let (sub, e0) = mem.alloc[f64](a, n)
    let (who, e1) = mem.alloc[usize](a, n)
    let (r, e2) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var m = 0usize
    var t = 0usize
    while t < n {
        if grp[t] == g0 || grp[t] == j {
            sub[m] = x[t]
            who[m] = grp[t]
            m += 1usize
        }
        t += 1usize
    }
    let er = rank_avg(a, sub[0usize..m], r[0usize..m])
    if er != ok { ret (0.0f64, er) }
    var r1 = 0.0f64
    var r2 = 0.0f64
    var n1 = 0.0f64
    var n2 = 0.0f64
    t = 0usize
    while t < m {
        if who[t] == g0 {
            r1 += r[t]
            n1 += 1.0f64
        } else {
            r2 += r[t]
            n2 += 1.0f64
        }
        t += 1usize
    }
    let u1 = n1 * n2 + n1 * (n1 + 1.0f64) / 2.0f64 - r1
    let u2 = n1 * n2 + n2 * (n2 + 1.0f64) / 2.0f64 - r2
    var umn = u1
    if u2 < umn { umn = u2 }
    // the tie correction: sum over tied values of (t^3 - t) / 12 on the ranks
    var ties = 0.0f64
    t = 0usize
    while t < m {
        var cnt = 0.0f64
        var q = 0usize
        while q < m {
            if r[q] == r[t] { cnt += 1.0f64 }
            q += 1usize
        }
        ties += (cnt * cnt * cnt - cnt) / 12.0f64 / cnt
        t += 1usize
    }
    let s = n1 + n2
    let v = (n1 * n2 / (s * (s - 1.0f64))) * ((s * s * s - s) / 12.0f64 - ties)
    var z = (umn - n1 * n2 / 2.0f64) / math.sqrt[f64](v)
    if r1 < r2 { z = 0.0f64 - z }
    ret (z, ok)
}

// kwAllPairsNemenyiTest(dist = "Chisquare"): the statistic dif^2 / (n (n + 1) / 12 (1 / n_i + 1 / n_j)) divided by the tie correction C and its upper chi-square p with k - 1 degrees of freedom
fn nemenyi_chisq(q: Ranks, rbar: []const f64, rn: []const f64, i: usize, j: usize) -> (f64, f64) {
    var dif = rbar[i] - rbar[j]
    if dif < 0.0f64 { dif = 0.0f64 - dif }
    let st = dif * dif / (q.n * (q.n + 1.0f64) / 12.0f64 * (1.0f64 / rn[i] + 1.0f64 / rn[j])) / q.ties_kw
    ret (st, 1.0f64 - nm.pchisq(st, f64(q.k - 1usize), true, false))
}

// dscfAllPairsTest: the Dwass-Steel-Critchlow-Fligner statistic of the pair (g0, j) is -sqrt(2) |z| of the pairwise Mann-Whitney z (always on the smaller U), and its p is the upper
// Tukey probability of |statistic| for k means and infinite degrees of freedom; answers (statistic, p)
fn dscf_pair(a: *mem.Arena, x: []const f64, grp: []const usize, k: usize, g0: usize, j: usize) -> (f64, f64, err) {
    let (z, e) = manyone_u(a, x, grp, g0, j)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    var az = z
    if az < 0.0f64 { az = 0.0f64 - az }
    let st = 0.0f64 - math.sqrt[f64](2.0f64) * az
    ret (st, 1.0f64 - nb.ptukey(math.sqrt[f64](2.0f64) * az, 1.0f64, f64(k), 1.0e300f64, true, false), ok)
}

// tukeyTest (kind 0) and scheffeTest (kind 1) on one-way data (labels 1..k): with the pooled variance s2 = sum((n_g - 1) var_g) / (n - k) and dif = mean_ri - mean_cj, Tukey's
// q = dif / sqrt(s2 (1/n_ri + 1/n_cj) / 2) with the upper Tukey probability of |q| (k means, n - k df), Scheffe's F = dif^2 / (s2 (1/n_ri + 1/n_cj) (k - 1)) with the upper F probability
fn oneway_pair(x: []const f64, grp: []const usize, k: usize, ri: usize, cj: usize, kind: usize) -> (f64, f64) {
    let n = x.len
    var cnt: [16]f64 = zero
    var mean: [16]f64 = zero
    var t = 0usize
    while t < n {
        cnt[grp[t] - 1usize] += 1.0f64
        mean[grp[t] - 1usize] += x[t]
        t += 1usize
    }
    var g = 0usize
    while g < k {
        mean[g] = mean[g] / cnt[g]
        g += 1usize
    }
    var ss = 0.0f64
    t = 0usize
    while t < n {
        let d = x[t] - mean[grp[t] - 1usize]
        ss += d * d
        t += 1usize
    }
    let nf = f64(n)
    let kf = f64(k)
    let s2 = ss / (nf - kf)
    let dif = mean[ri] - mean[cj]
    let b = 1.0f64 / cnt[ri] + 1.0f64 / cnt[cj]
    if kind == 0usize {
        let q = dif / math.sqrt[f64](s2 * 0.5f64 * b)
        var aq = q
        if aq < 0.0f64 { aq = 0.0f64 - aq }
        ret (q, 1.0f64 - nb.ptukey(aq, 1.0f64, kf, nf - kf, true, false))
    }
    let fv = dif * dif / (s2 * b * (kf - 1.0f64))
    ret (fv, nb.pf(fv, kf - 1.0f64, nf - kf, false, false))
}

// welchManyOneTTest: Welch's t of group j (1-based label j + 1) against group 1, t.test(x = group j, y = group 1): t = (mean_j - mean_1) / sqrt(v_j / n_j + v_1 / n_1) with the
// Welch-Satterthwaite degrees of freedom; answers (t, unadjusted two-sided p)
fn welch_pair(x: []const f64, grp: []const usize, j: usize) -> (f64, f64) {
    var n1 = 0.0f64
    var n2 = 0.0f64
    var m1 = 0.0f64
    var m2 = 0.0f64
    var t = 0usize
    while t < x.len {
        if grp[t] == 1usize {
            n1 += 1.0f64
            m1 += x[t]
        }
        if grp[t] == j + 1usize {
            n2 += 1.0f64
            m2 += x[t]
        }
        t += 1usize
    }
    m1 = m1 / n1
    m2 = m2 / n2
    var s1 = 0.0f64
    var s2 = 0.0f64
    t = 0usize
    while t < x.len {
        if grp[t] == 1usize { s1 += (x[t] - m1) * (x[t] - m1) }
        if grp[t] == j + 1usize { s2 += (x[t] - m2) * (x[t] - m2) }
        t += 1usize
    }
    let v1 = s1 / (n1 - 1.0f64) / n1
    let v2 = s2 / (n2 - 1.0f64) / n2
    let tv = (m2 - m1) / math.sqrt[f64](v1 + v2)
    let df = (v1 + v2) * (v1 + v2) / (v1 * v1 / (n1 - 1.0f64) + v2 * v2 / (n2 - 1.0f64))
    var at = tv
    if at < 0.0f64 { at = 0.0f64 - at }
    ret (tv, 2.0f64 * nb.pt(0.0f64 - at, df, true, false))
}

// siegelTukeyTest (two-sided; with ties the normal approximation): the pooled sample is sorted, the ranks 1, 4, 5, 8, 9, ... from the low end and ..., 7, 6, 3, 2 from the high end are assigned by position, W = R1 -
// n1 (n1 + 1) / 2 and the exact p is 2 min(1/2, the Wilcoxon tail on the side of W); answers (W, p). x holds the first sample then the second
fn siegel_tukey(a: *mem.Arena, x: []const f64, n1: usize, out: []f64) -> err {
    let n = x.len
    let n2 = n - n1
    let (r, e0) = mem.alloc[f64](a, n)
    let (ord, e1) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok { ret mem.Full }
    let nup = (n + 1usize) / 2usize
    let ndown = n / 2usize
    var m = 1usize
    r[0usize] = 1.0f64
    while m < nup {
        // the low-end ranks: c(1, a * 4 + b) with a = ceil(m / 2) and b alternating 0, 1 (R's rep(seq(ceiling(N / 4)), each = 2) and rep(c(0, 1)))
        let aa = (m + 1usize) / 2usize
        let bb = (m + 1usize) % 2usize
        r[m] = f64(aa * 4usize + bb)
        m += 1usize
    }
    // the high-end ranks: rev((a * 4 + b - 2)[1:floor(N / 2)]), written back to front
    var kk = 1usize
    while kk <= ndown {
        let aa = (kk + 1usize) / 2usize
        let bb = (kk + 1usize) % 2usize
        r[nup + (ndown - kk)] = f64(aa * 4usize + bb - 2usize)
        kk += 1usize
    }
    // order of the pooled sample
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = ord[i]
        var j = i
        while j > 0usize && x[ord[j - 1usize]] > x[t] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = t
        i += 1usize
    }
    var r1 = 0.0f64
    i = 0usize
    while i < n {
        if ord[i] < n1 { r1 += r[i] }
        i += 1usize
    }
    let n1f = f64(n1)
    let n2f = f64(n2)
    // ties: S1 and S2 are the sums of squares of the Siegel-Tukey ranks and of their tied-group means over the tied observations, and the answer is the normal z with continuity
    // correction (R's warning branch), p = 2 min(1/2, upper normal tail of |z|)
    var s1 = 0.0f64
    var s2 = 0.0f64
    var tied = false
    i = 0usize
    while i < n {
        var cnt = 0.0f64
        var sm = 0.0f64
        var q = 0usize
        while q < n {
            if x[ord[q]] == x[ord[i]] {
                cnt += 1.0f64
                sm += r[q]
            }
            q += 1usize
        }
        if cnt > 1.0f64 {
            tied = true
            s1 += r[i] * r[i]
            let rc = sm / cnt
            s2 += rc * rc
        }
        i += 1usize
    }
    if tied {
        var av = 1.0f64
        if 2.0f64 * r1 > n1f * (n1f + n2f + 1.0f64) { av = -1.0f64 }
        let numer = 2.0f64 * r1 - n1f * (n1f + n2f + 1.0f64) + av
        let denom = math.sqrt[f64](n1f * (n1f + n2f + 1.0f64) * (n2f / 3.0f64) - 4.0f64 * (n1f * n2f / ((n1f + n2f) * (n1f + n2f - 1.0f64))) * (s1 - s2))
        let z = numer / denom
        var az = z
        if az < 0.0f64 { az = 0.0f64 - az }
        out[0usize] = z
        out[1usize] = 2.0f64 * math.min[f64](0.5f64, dist.pnorm(0.0f64 - az, 0.0f64, 1.0f64, true, false))
        ret ok
    }
    let w = r1 - n1f * (n1f + 1.0f64) / 2.0f64
    var p = 0.0f64
    if w > n1f * n2f / 2.0f64 {
        p = 2.0f64 * math.min[f64](0.5f64, nb.pwilcox(a, w - 1.0f64, n1f, n2f, false, false))
    } else {
        p = 2.0f64 * math.min[f64](0.5f64, nb.pwilcox(a, w, n1f, n2f, true, false))
    }
    out[0usize] = w
    out[1usize] = p
    ret ok
}

// P(-c < Z_i < c for all i) for m standard normals with common correlation 1/2 (the many-to-one structure): the one-dimensional integral over the common factor,
// integral phi(z) [Phi((c + sqrt(1/2) z) / sqrt(1/2)) - Phi((-c + sqrt(1/2) z) / sqrt(1/2))]^m dz, by Simpson's rule (R's pmvnorm is a Monte Carlo with absolute error 1e-3)
fn mvn_equicorr_half(c: f64, m: usize) -> f64 {
    let steps = 4000usize
    let lo = 0.0f64 - 9.0f64
    let hi = 9.0f64
    let h = (hi - lo) / f64(steps)
    let rs = math.sqrt[f64](0.5f64)
    var s = 0.0f64
    var i = 0usize
    while i <= steps {
        let z = lo + h * f64(i)
        let up = dist.pnorm((c + rs * z) / rs, 0.0f64, 1.0f64, true, false)
        let dn = dist.pnorm((0.0f64 - c + rs * z) / rs, 0.0f64, 1.0f64, true, false)
        let f = math.exp[f64](0.0f64 - z * z / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) * math.pow[f64](up - dn, f64(m))
        var wgt = 2.0f64
        if i == 0usize || i == steps { wgt = 1.0f64 } else if i % 2usize == 1usize { wgt = 4.0f64 }
        s += wgt * f
        i += 1usize
    }
    ret s * h / 3.0f64
}

// P(|Z_i| < c for all i) for standard normals with correlations lam_i lam_j (a one-factor structure, the many-to-one correlation of group sizes n_i and a control n_0 with
// lam_i = sqrt(n_i / (n_i + n_0))): the integral over the common factor of the product of the conditional interval probabilities, by Simpson's rule
fn mvn_one_factor(c: f64, lam: []const f64) -> f64 {
    let steps = 4000usize
    let lo = 0.0f64 - 9.0f64
    let h = 18.0f64 / f64(steps)
    var s = 0.0f64
    var i = 0usize
    while i <= steps {
        let z = lo + h * f64(i)
        var prod = 1.0f64
        var q = 0usize
        while q < lam.len {
            let rs = math.sqrt[f64](1.0f64 - lam[q] * lam[q])
            prod *= dist.pnorm((c + lam[q] * z) / rs, 0.0f64, 1.0f64, true, false) - dist.pnorm((0.0f64 - c + lam[q] * z) / rs, 0.0f64, 1.0f64, true, false)
            q += 1usize
        }
        let f = math.exp[f64](0.0f64 - z * z / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) * prod
        var wgt = 2.0f64
        if i == 0usize || i == steps { wgt = 1.0f64 } else if i % 2usize == 1usize { wgt = 4.0f64 }
        s += wgt * f
        i += 1usize
    }
    ret s * h / 3.0f64
}

// kwManyOneDunnTest(p.adjust.method = "single-step"): the single-step p value 1 - P(|Z_i| < |z_j| for all i) of comparison j (1-based)
fn dunn_many_single(q: Ranks, rbar: []const f64, rn: []const f64, k: usize, j: usize, lam: []f64) -> (f64, f64) {
    var m = 1usize
    while m < k {
        lam[m - 1usize] = math.sqrt[f64](rn[m] / (rn[m] + rn[0usize]))
        m += 1usize
    }
    let (z, p) = dunn_many(q, rbar, rn, j)
    let _ = p
    var az = z
    if az < 0.0f64 { az = 0.0f64 - az }
    ret (z, 1.0f64 - mvn_one_factor(az, lam[0usize..k - 1usize]))
}

// kwManyOneNdwTest (Nemenyi-Damico-Wolfe, single-step): the statistic is the many-to-one rank difference over sqrt(n (n + 1) / 12 (1 / n_j + 1 / n_0)), without Dunn's tie correction,
// and the p value 1 - P(|Z_i| < |z_j| for all i) with the one-factor correlation of group sizes; answers (z, p)
fn ndw_many(q: Ranks, rbar: []const f64, rn: []const f64, k: usize, j: usize, lam: []f64) -> (f64, f64) {
    var m = 1usize
    while m < k {
        lam[m - 1usize] = math.sqrt[f64](rn[m] / (rn[m] + rn[0usize]))
        m += 1usize
    }
    let z = (rbar[j] - rbar[0usize]) / math.sqrt[f64](q.n * (q.n + 1.0f64) / 12.0f64 * (1.0f64 / rn[j] + 1.0f64 / rn[0usize]))
    var az = z
    if az < 0.0f64 { az = 0.0f64 - az }
    ret (z, 1.0f64 - mvn_one_factor(az, lam[0usize..k - 1usize]))
}

// steelTest (two-sided is the default; "greater" negates the data): the rank sum R_j of dose group j (1-based label j + 1) among the control's and its own 2 n observations (the dose
// ranks summed), balanced groups of n replicates; ctrl is label 1. Answers (R_j, the critical value from the table for n replicates and k dose levels, -1 when the table has none)
fn steel_stat(a: *mem.Arena, x: []const f64, grp: []const usize, n: usize, nk: usize, j: usize, greater: bool) -> (f64, f64, err) {
    let (sub, e0) = mem.alloc[f64](a, 2usize * n)
    let (who, e1) = mem.alloc[usize](a, 2usize * n)
    let (rk, e2) = mem.alloc[f64](a, 2usize * n)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var m = 0usize
    var t = 0usize
    while t < x.len {
        if grp[t] == 1usize || grp[t] == j + 1usize {
            var v = x[t]
            if greater { v = 0.0f64 - v }
            sub[m] = v
            who[m] = grp[t]
            m += 1usize
        }
        t += 1usize
    }
    let er = rank_avg(a, sub[0usize..m], rk[0usize..m])
    if er != ok { ret (0.0f64, 0.0f64, er) }
    var rs = 0.0f64
    t = 0usize
    while t < m {
        if who[t] != 1usize { rs += rk[t] }
        t += 1usize
    }
    var crit = -1.0f64
    if n >= 4usize && n <= 20usize && nk >= 2usize && nk <= 9usize {
        let tab = stt.steel_table()
        crit = tab[(n - 4usize) * 8usize + (nk - 2usize)]
    }
    ret (rs, crit, ok)
}

// P(T_i < q for all i) (or P(|T_i| < q) when two_sided) for the many-to-one multivariate t with df degrees of freedom and one-factor correlations lam_i lam_j: the integral over the scale s = chi / sqrt(df) (density
// df^(df/2) s^(df - 1) exp(-df s^2 / 2) / (2^(df/2 - 1) Gamma(df/2))) and over the common normal factor of the product of Phi((q s + lam_i z) / sqrt(1 - lam_i^2)), by nested Simpson's rule
fn mvt_one_factor_upper(q: f64, lam: []const f64, df: f64, two_sided: bool) -> f64 {
    let ns = 400usize
    let nz = 300usize
    let smax = 1.0f64 + 8.0f64 / math.sqrt[f64](df) + 2.0f64
    let hs = smax / f64(ns)
    let zlo = 0.0f64 - 9.0f64
    let hz = 18.0f64 / f64(nz)
    let lg = nm.lgammafn(df / 2.0f64)
    let c0 = (df / 2.0f64) * math.log[f64](df) - (df / 2.0f64 - 1.0f64) * math.log[f64](2.0f64) - lg
    var total = 0.0f64
    var i = 0usize
    while i <= ns {
        let s = hs * f64(i)
        var fs = 0.0f64
        if s > 0.0f64 { fs = math.exp[f64](c0 + (df - 1.0f64) * math.log[f64](s) - df * s * s / 2.0f64) }
        var inner = 0.0f64
        if fs > 0.0f64 {
            var j = 0usize
            while j <= nz {
                let z = zlo + hz * f64(j)
                var prod = 1.0f64
                var m = 0usize
                while m < lam.len {
                    let rs = math.sqrt[f64](1.0f64 - lam[m] * lam[m])
                    var term = dist.pnorm((q * s + lam[m] * z) / rs, 0.0f64, 1.0f64, true, false)
                    if two_sided { term -= dist.pnorm((0.0f64 - q * s + lam[m] * z) / rs, 0.0f64, 1.0f64, true, false) }
                    prod *= term
                    m += 1usize
                }
                let f = math.exp[f64](0.0f64 - z * z / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64) * prod
                var wz = 2.0f64
                if j == 0usize || j == nz { wz = 1.0f64 } else if j % 2usize == 1usize { wz = 4.0f64 }
                inner += wz * f
                j += 1usize
            }
            inner = inner * hz / 3.0f64
        }
        var ws = 2.0f64
        if i == 0usize || i == ns { ws = 1.0f64 } else if i % 2usize == 1usize { ws = 4.0f64 }
        total += ws * fs * inner
        i += 1usize
    }
    ret total * hs / 3.0f64
}

// dunnettTest (two-sided): t_j = (mean_j - mean_1) / sqrt(s2 (1 / n_j + 1 / n_1)) with the pooled s2 on n - k degrees of freedom, p = min(1, 2 (1 - P(T_i < |t_j| for all i))) under the one-factor
// correlations sqrt(n_i / (n_i + n_1)); grp holds labels 1..k; answers (t, p)
fn dunnett_many(x: []const f64, grp: []const usize, k: usize, j: usize) -> (f64, f64) {
    let n = x.len
    var cnt: [16]f64 = zero
    var mean: [16]f64 = zero
    var t = 0usize
    while t < n {
        cnt[grp[t] - 1usize] += 1.0f64
        mean[grp[t] - 1usize] += x[t]
        t += 1usize
    }
    var g = 0usize
    while g < k {
        mean[g] = mean[g] / cnt[g]
        g += 1usize
    }
    var ss = 0.0f64
    t = 0usize
    while t < n {
        let d = x[t] - mean[grp[t] - 1usize]
        ss += d * d
        t += 1usize
    }
    let df = f64(n) - f64(k)
    let s2 = ss / df
    let tv = (mean[j] - mean[0usize]) / math.sqrt[f64](s2 * (1.0f64 / cnt[j] + 1.0f64 / cnt[0usize]))
    var lam: [16]f64 = zero
    g = 1usize
    while g < k {
        lam[g - 1usize] = math.sqrt[f64](cnt[g] / (cnt[g] + cnt[0usize]))
        g += 1usize
    }
    var at = tv
    if at < 0.0f64 { at = 0.0f64 - at }
    var p = 2.0f64 * (1.0f64 - mvt_one_factor_upper(at, lam[0usize..k - 1usize], df, false))
    if p > 1.0f64 { p = 1.0f64 }
    ret (tv, p)
}

// the single-step p of a many-to-one t statistic: 1 - P(|T_i| < |t| for all i) for group sizes (lam_i = sqrt(n_i / (n_i + n_0))) and df degrees of freedom
fn t_single_step_p(t: f64, rn: []const f64, k: usize, df: f64) -> f64 {
    var lam: [16]f64 = zero
    var m = 1usize
    while m < k {
        lam[m - 1usize] = math.sqrt[f64](rn[m] / (rn[m] + rn[0usize]))
        m += 1usize
    }
    var at = t
    if at < 0.0f64 { at = 0.0f64 - at }
    ret 1.0f64 - mvt_one_factor_upper(at, lam[0usize..k - 1usize], df, true)
}

// dunnettTest one-sided: alt 0 "greater" p = pDunnett(t, upper) = 1 - P(T_i < t for all i), alt 1 "less" p = pDunnett(t, lower) = 1 - P(T_i > t for all i); t as in dunnett_many
fn dunnett_one_sided(x: []const f64, grp: []const usize, k: usize, j: usize, alt: usize) -> f64 {
    let (tv, p2) = dunnett_many(x, grp, k, j)
    let _ = p2
    let n = x.len
    var cnt: [16]f64 = zero
    var u = 0usize
    while u < n {
        cnt[grp[u] - 1usize] += 1.0f64
        u += 1usize
    }
    var lam: [16]f64 = zero
    var g = 1usize
    while g < k {
        lam[g - 1usize] = math.sqrt[f64](cnt[g] / (cnt[g] + cnt[0usize]))
        g += 1usize
    }
    let df = f64(n) - f64(k)
    if alt == 0usize { ret 1.0f64 - mvt_one_factor_upper(tv, lam[0usize..k - 1usize], df, false) }
    // pDunnett(lower.tail = TRUE) = 1 - P(all T_i > t) = 1 - P(all -T_i < -t)
    ret 1.0f64 - mvt_one_factor_upper(0.0f64 - tv, lam[0usize..k - 1usize], df, false)
}

// tamhaneDunnettTest (two-sided): the Welch-type t_j = (mean_j - mean_1) / sqrt(v_j / n_j + v_1 / n_1) of group j (0-based index, labels 1..k) against the control, and
// p = 1 - P(|T_i| < |t_j| for all i = 1 .. k - 1) for independent t components sharing the chi scale (identity correlation) at n_1 + n_j - 2 degrees of freedom; answers (t, p)
fn tamhane_dunnett(x: []const f64, grp: []const usize, k: usize, j: usize) -> (f64, f64) {
    var cnt: [16]f64 = zero
    var mean: [16]f64 = zero
    var t = 0usize
    while t < x.len {
        cnt[grp[t] - 1usize] += 1.0f64
        mean[grp[t] - 1usize] += x[t]
        t += 1usize
    }
    var g = 0usize
    while g < k {
        mean[g] = mean[g] / cnt[g]
        g += 1usize
    }
    var vr: [16]f64 = zero
    t = 0usize
    while t < x.len {
        let d = x[t] - mean[grp[t] - 1usize]
        vr[grp[t] - 1usize] += d * d
        t += 1usize
    }
    g = 0usize
    while g < k {
        vr[g] = vr[g] / (cnt[g] - 1.0f64)
        g += 1usize
    }
    let tv = (mean[j] - mean[0usize]) / math.sqrt[f64](vr[j] / cnt[j] + vr[0usize] / cnt[0usize])
    var lam: [16]f64 = zero
    var at = tv
    if at < 0.0f64 { at = 0.0f64 - at }
    ret (tv, 1.0f64 - mvt_one_factor_upper(at, lam[0usize..k - 1usize], cnt[0usize] + cnt[j] - 2.0f64, true))
}

// the exact two-sided p P(|D| >= d) of the rank-sum difference of two treatments over n blocks of k untied ranks (pexactfrsd): in one block the difference is delta in -(k - 1) .. (k - 1)
// with probability (k - |delta|) / (k (k - 1)) for delta != 0, and D is the n-fold convolution of that; d = 0 gives 1
fn frd_exact_p(n: usize, k: usize, d: usize) -> f64 {
    if d == 0usize { ret 1.0f64 }
    let half = n * (k - 1usize)
    let w = 2usize * half + 1usize
    var cur: [1024]f64 = zero
    var nxt: [1024]f64 = zero
    if w > 1024usize { ret 0.0f64 / 0.0f64 }
    cur[half] = 1.0f64
    var b = 0usize
    while b < n {
        var t = 0usize
        while t < w {
            nxt[t] = 0.0f64
            t += 1usize
        }
        t = 0usize
        while t < w {
            if cur[t] != 0.0f64 {
                var dl = 1usize
                while dl < k {
                    let pr = f64(k - dl) / f64(k * (k - 1usize))
                    nxt[t + dl] += cur[t] * pr
                    nxt[t - dl] += cur[t] * pr
                    dl += 1usize
                }
            }
            t += 1usize
        }
        t = 0usize
        while t < w {
            cur[t] = nxt[t]
            t += 1usize
        }
        b += 1usize
    }
    var p = 0.0f64
    var t = 0usize
    while t < w {
        var off = t
        if t < half { off = half - t } else { off = t - half }
        if off >= d { p += cur[t] }
        t += 1usize
    }
    ret p
}

// the expected values of the normal order statistics of a sample of n, E[Z(r:n)] = r C(n, r) integral x Phi(x)^(r - 1) (1 - Phi(x))^(n - r) phi(x) dx, by Simpson's rule on [-9, 9]
// (SuppDists' normOrder, which PMCMRplus uses, is an approximation good to about 1e-4; this is the exact value); out receives the n values in increasing order
fn norm_order(n: usize, out: []f64) {
    let steps = 6000usize
    let lo = 0.0f64 - 9.0f64
    let h = 18.0f64 / f64(steps)
    var r = 1usize
    while r <= n {
        // log of r C(n, r)
        let lc = nm.lgammafn(f64(n) + 1.0f64) - nm.lgammafn(f64(r)) - nm.lgammafn(f64(n - r) + 1.0f64)
        var s = 0.0f64
        var i = 0usize
        while i <= steps {
            let x = lo + h * f64(i)
            let cdf = dist.pnorm(x, 0.0f64, 1.0f64, true, false)
            let sf = dist.pnorm(x, 0.0f64, 1.0f64, false, false)
            var lf = lc + dist.dnorm(x, 0.0f64, 1.0f64, true)
            if r > 1usize { lf += f64(r - 1usize) * math.log[f64](cdf) }
            if n > r { lf += f64(n - r) * math.log[f64](sf) }
            let f = x * math.exp[f64](lf)
            var wgt = 2.0f64
            if i == 0usize || i == steps { wgt = 1.0f64 } else if i % 2usize == 1usize { wgt = 4.0f64 }
            s += wgt * f
            i += 1usize
        }
        out[r - 1usize] = s * h / 3.0f64
        r += 1usize
    }
}

// steelsKSampleTest (kSamples' Steel.test, method "asymptotic"): groups 1 (control) .. k, alt 0 "greater", 1 "less", 2 "two.sided". out = (S, p): S the extreme standardised Mann-Whitney count
// (max, min or max |.| over the k - 1 comparisons of (W_j - mu_j) / tau_j) and p the smallest of the comparisons' asymptotic p values, each 1 - integral phi(z) prod_i Phi((S tau_i - n_i sig0 z) / sig_i) dz
// with the continuity correction of 0.5 (0.25 for pairs with ties) applied to W_j, as kSamples' Steelnormal does
fn steels_k(a: *mem.Arena, x: []const f64, grp: []const usize, k: usize, alt: usize, out: []f64) -> err {
    let n = x.len
    let (xs, e0) = mem.alloc[f64](a, n)
    let (rx, e1) = mem.alloc[f64](a, n)
    let (sub, e2) = mem.alloc[f64](a, n)
    let (who, e3) = mem.alloc[usize](a, n)
    let (rk, e4) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var t = 0usize
    while t < n {
        xs[t] = x[t]
        if alt == 1usize { xs[t] = 0.0f64 - x[t] }
        t += 1usize
    }
    let er = rank_avg(a, xs, rx)
    if er != ok { ret er }
    var cnt: [16]f64 = zero
    t = 0usize
    while t < n {
        cnt[grp[t] - 1usize] += 1.0f64
        t += 1usize
    }
    let nf = f64(n)
    var d2 = 0.0f64
    var d3 = 0.0f64
    t = 0usize
    while t < n {
        var c = 0.0f64
        var q = 0usize
        while q < n {
            if rx[q] == rx[t] { c += 1.0f64 }
            q += 1usize
        }
        // each member of a tied block of c contributes c - 1 and (c - 1)(c - 2) / ... so the block sums to c (c - 1) and c (c - 1)(c - 2)
        d2 += (c - 1.0f64)
        d3 += (c - 1.0f64) * (c - 2.0f64)
        t += 1usize
    }
    let n2 = nf * (nf - 1.0f64)
    let n3 = n2 * (nf - 2.0f64)
    let n0 = cnt[0usize]
    let sig02 = n0 / 12.0f64 * (1.0f64 - d3 / n3)
    let sig0 = math.sqrt[f64](sig02)
    var wv: [16]f64 = zero
    var corr: [16]f64 = zero
    var mu: [16]f64 = zero
    var sg: [16]f64 = zero
    var tau: [16]f64 = zero
    var g = 1usize
    while g < k {
        let ni = cnt[g]
        var m = 0usize
        t = 0usize
        while t < n {
            if grp[t] == 1usize || grp[t] == g + 1usize {
                sub[m] = xs[t]
                who[m] = grp[t]
                m += 1usize
            }
            t += 1usize
        }
        let er2 = rank_avg(a, sub[0usize..m], rk[0usize..m])
        if er2 != ok { ret er2 }
        var rsum = 0.0f64
        var tied = false
        t = 0usize
        while t < m {
            if who[t] != 1usize { rsum += rk[t] }
            var q = t + 1usize
            while q < m {
                if sub[q] == sub[t] { tied = true }
                q += 1usize
            }
            t += 1usize
        }
        wv[g - 1usize] = rsum - ni * (ni + 1.0f64) / 2.0f64
        corr[g - 1usize] = 0.5f64
        if tied { corr[g - 1usize] = 0.25f64 }
        mu[g - 1usize] = n0 * ni / 2.0f64
        let s2 = n0 * ni / 12.0f64 * (n0 + 1.0f64 - 3.0f64 * d2 / n2 - (n0 - 2.0f64) * d3 / n3)
        sg[g - 1usize] = math.sqrt[f64](s2)
        tau[g - 1usize] = math.sqrt[f64](ni * ni * sig02 + s2)
        g += 1usize
    }
    let m1 = k - 1usize
    // the statistic and its comparison
    var best = 0usize
    var sobs = 0.0f64
    var j = 0usize
    while j < m1 {
        let sj = (wv[j] - mu[j]) / tau[j]
        var key = sj
        if alt == 2usize && sj < 0.0f64 { key = 0.0f64 - sj }
        var bkey = sobs
        if alt == 2usize && sobs < 0.0f64 { bkey = 0.0f64 - sobs }
        if j == 0usize || key > bkey {
            best = j
            sobs = sj
        }
        j += 1usize
    }
    // 'less' works on the negated data, so the largest standardised count there is the smallest here
    var sret = sobs
    if alt == 1usize { sret = 0.0f64 - sobs }
    if alt == 2usize && sret < 0.0f64 { sret = 0.0f64 - sret }
    out[0usize] = sret
    // the asymptotic p of every comparison (the data were negated for "less", so the greater form applies); the answer is the smallest, as kSamples takes min(Steelnormal(...))
    var pmin = 2.0f64
    var cj = 0usize
    while cj < m1 {
        var sj2 = (wv[cj] - corr[cj] - mu[cj]) / tau[cj]
        if alt == 2usize {
            var aw = wv[cj] - corr[cj] - mu[cj]
            if aw < 0.0f64 { aw = 0.0f64 - aw }
            sj2 = aw / tau[cj]
        }
        let steps = 4000usize
        let lo = 0.0f64 - 10.0f64
        let h = 20.0f64 / f64(steps)
        var s = 0.0f64
        var i = 0usize
        while i <= steps {
            let z = lo + h * f64(i)
            var fac = 1.0f64
            var q = 0usize
            while q < m1 {
                let ni = cnt[q + 1usize]
                let up = dist.pnorm((sj2 * tau[q] - ni * sig0 * z) / sg[q], 0.0f64, 1.0f64, true, false)
                if alt == 2usize {
                    fac *= up - dist.pnorm((0.0f64 - sj2 * tau[q] - ni * sig0 * z) / sg[q], 0.0f64, 1.0f64, true, false)
                } else {
                    fac *= up
                }
                q += 1usize
            }
            let f = dist.dnorm(z, 0.0f64, 1.0f64, false) * fac
            var wgt = 2.0f64
            if i == 0usize || i == steps { wgt = 1.0f64 } else if i % 2usize == 1usize { wgt = 4.0f64 }
            s += wgt * f
            i += 1usize
        }
        let pj = 1.0f64 - s * h / 3.0f64
        if pj < pmin { pmin = pj }
        cj += 1usize
    }
    out[1usize] = pmin
    ret ok
}

// lsdTest (kind 0) and gamesHowellTest (kind 1) on one-way data for the table cell (row group ri, column group cj), dif = mean_ri - mean_cj. LSD: t = dif / sqrt(s2 (1/n_i + 1/n_j)) with the pooled s2
// on n - k df and the unadjusted two-sided p. Games-Howell: q = sqrt(2) dif / sqrt(v_i / n_i + v_j / n_j) with the Welch-Satterthwaite df and the upper Tukey probability of |q| for k means; answers (stat, p)
fn lsd_gh_pair(x: []const f64, grp: []const usize, k: usize, ri: usize, cj: usize, kind: usize) -> (f64, f64) {
    let n = x.len
    var cnt: [16]f64 = zero
    var mean: [16]f64 = zero
    var vr: [16]f64 = zero
    var t = 0usize
    while t < n {
        cnt[grp[t] - 1usize] += 1.0f64
        mean[grp[t] - 1usize] += x[t]
        t += 1usize
    }
    var g = 0usize
    while g < k {
        mean[g] = mean[g] / cnt[g]
        g += 1usize
    }
    var ss = 0.0f64
    t = 0usize
    while t < n {
        let d = x[t] - mean[grp[t] - 1usize]
        ss += d * d
        vr[grp[t] - 1usize] += d * d
        t += 1usize
    }
    g = 0usize
    while g < k {
        vr[g] = vr[g] / (cnt[g] - 1.0f64)
        g += 1usize
    }
    let nf = f64(n)
    let kf = f64(k)
    let dif = mean[ri] - mean[cj]
    if kind == 0usize {
        let s2 = ss / (nf - kf)
        let tv = dif / math.sqrt[f64](s2 * (1.0f64 / cnt[ri] + 1.0f64 / cnt[cj]))
        var at = tv
        if at < 0.0f64 { at = 0.0f64 - at }
        ret (tv, 2.0f64 * nb.pt(0.0f64 - at, nf - kf, true, false))
    }
    let aa = vr[ri] / cnt[ri] + vr[cj] / cnt[cj]
    let q = dif / math.sqrt[f64](aa) * math.sqrt[f64](2.0f64)
    let df = aa * aa / (vr[ri] * vr[ri] / (cnt[ri] * cnt[ri] * (cnt[ri] - 1.0f64)) + vr[cj] * vr[cj] / (cnt[cj] * cnt[cj] * (cnt[cj] - 1.0f64)))
    var aq = q
    if aq < 0.0f64 { aq = 0.0f64 - aq }
    if kind == 1usize { ret (q, 1.0f64 - nb.ptukey(aq, 1.0f64, kf, df, true, false)) }
    // Tamhane's T2 (kind 2) and Dunnett's T3 (kind 3): the Welch t = q / sqrt(2) with the same Welch df
    let tw = q / math.sqrt[f64](2.0f64)
    var at = tw
    if at < 0.0f64 { at = 0.0f64 - at }
    let mpairs = kf * (kf - 1.0f64) / 2.0f64
    if kind == 2usize {
        // the unadjusted Welch p, then the Sidak-type adjustment min(1, 1 - (1 - p)^m) over the k (k - 1) / 2 pairs
        let pu = 2.0f64 * nb.pt(0.0f64 - at, df, true, false)
        var pa = 1.0f64 - math.pow[f64](1.0f64 - pu, mpairs)
        if pa > 1.0f64 { pa = 1.0f64 }
        ret (tw, pa)
    }
    // T3: the studentised maximum modulus of m = k (k - 1) / 2 independent t components at the rounded Welch df
    var lam: [16]f64 = zero
    let mm = usize(mpairs)
    ret (tw, 1.0f64 - mvt_one_factor_upper(at, lam[0usize..mm], math.floor[f64](df + 0.5f64), true))
}

// snkTest (kind 0) and duncanTest (kind 1) on one-way data for the table cell (row group ri, column group cj): the groups are ranked by mean (decreasing), p = 1 + the rank distance
// of the two, and the p value is the upper Tukey probability of |q| for p means at n - k df. SNK: q = (mean_ri - mean_cj) / sqrt(s2 / 2 (1/n_i + 1/n_j)); Duncan: q = |dif| / sqrt(s2 / r) with
// r = k / sum(1/n_g), and the probability adjusted to min(1, 1 - (1 - p)^(1 / (p - 1))); answers (q, p)
fn range_pair(x: []const f64, grp: []const usize, k: usize, ri: usize, cj: usize, kind: usize) -> (f64, f64) {
    let n = x.len
    var cnt: [16]f64 = zero
    var mean: [16]f64 = zero
    var t = 0usize
    while t < n {
        cnt[grp[t] - 1usize] += 1.0f64
        mean[grp[t] - 1usize] += x[t]
        t += 1usize
    }
    var g = 0usize
    while g < k {
        mean[g] = mean[g] / cnt[g]
        g += 1usize
    }
    var ss = 0.0f64
    t = 0usize
    while t < n {
        let d = x[t] - mean[grp[t] - 1usize]
        ss += d * d
        t += 1usize
    }
    let nf = f64(n)
    let kf = f64(k)
    let s2 = ss / (nf - kf)
    // rank positions in decreasing mean order
    var pi = 0usize
    var pj = 0usize
    g = 0usize
    while g < k {
        if mean[g] > mean[ri] { pi += 1usize }
        if mean[g] > mean[cj] { pj += 1usize }
        g += 1usize
    }
    var dpos = 0usize
    if pi > pj { dpos = pi - pj } else { dpos = pj - pi }
    let pm = 1usize + dpos
    let dif = mean[ri] - mean[cj]
    if kind == 0usize {
        let q = dif / math.sqrt[f64](s2 / 2.0f64 * (1.0f64 / cnt[ri] + 1.0f64 / cnt[cj]))
        var aq = q
        if aq < 0.0f64 { aq = 0.0f64 - aq }
        ret (q, 1.0f64 - nb.ptukey(aq, 1.0f64, f64(pm), nf - kf, true, false))
    }
    var hs = 0.0f64
    g = 0usize
    while g < k {
        hs += 1.0f64 / cnt[g]
        g += 1usize
    }
    let r = kf / hs
    var ad = dif
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    let tv = ad / math.sqrt[f64](s2 / r)
    let pu = 1.0f64 - nb.ptukey(tv, 1.0f64, f64(pm), nf - kf, true, false)
    var pa = 1.0f64 - math.pow[f64](1.0f64 - pu, 1.0f64 / (f64(pm) - 1.0f64))
    if pa > 1.0f64 { pa = 1.0f64 }
    ret (tv, pa)
}
