// R PMCMRplus: the Kruskal-Wallis all-pairs post-hoc tests on a one-way layout: Dunn's z test, Conover's t test (also with the Tukey
// single-step p value) and the Tukey-Kramer-Nemenyi test, with the tie corrections of the package, plus the Holm adjustment of p values.
//
// Not here: the many-to-one and other design tests of the package (van der Waerden, Steel, Quade, Friedman post-hoc and the rest),
// the other adjustment methods, the chi-square form of Nemenyi's test.

use e.math
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

// van der Waerden all-pairs test: normal scores qnorm(rank / (n + 1)) of the pooled sample; the statistic of cell (row i, column j), i > j, is
// |mean score_i - mean score_j| / sqrt(s2 (n - 1 - T) / (n - k) (1 / n_i + 1 / n_j)). Answers (t, unadjusted two-sided p, single-step Tukey p).
fn vdw_pair(a: *mem.Arena, n: usize, k: usize, x: []const f64, grp: []const usize, i: usize, j: usize, signed: bool) -> (f64, f64, f64, err) {
    let (r, e0) = mem.alloc[f64](a, n)
    let (aj, e1) = mem.alloc[f64](a, k)
    let (nj, e2) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, mem.Full) }
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
        let z = dist.qnorm(r[t] / (nf + 1.0f64), 0.0f64, 1.0f64, true, false)
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
