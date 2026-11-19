// R clue, the partition measures: the Rand agreement of two partitions (1 + (sum n_ij^2 - (sum a_i^2 + sum b_j^2) / 2) / choose(n, 2) on the contingency
// table, with classes labelled 1..k) and the minimal Euclidean membership distance of two hard partitions (the membership matrices, each class of
// the first matched to a class of the second by solve_LSAP on their cross-products, then the root of the summed squared differences).
//
// Not here: the hierarchy measures, the other agreement and dissimilarity methods, consensus and membership of soft partitions.

use e.algo.graph.match as mt
use e.algo.stat.hclust as hc
use e.math
use e.mem

error Malformed

// the contingency table of the labels cx (in 1..kx) and cy (in 1..ky), kx * ky counts row-major, zeroed by the caller
fn table_counts(cx: []const usize, cy: []const usize, n: usize, kx: usize, ky: usize, t: []usize) {
    var r = 0usize
    while r < n {
        t[(cx[r] - 1usize) * ky + (cy[r] - 1usize)] += 1usize
        r += 1usize
    }
}

// clue's Rand agreement of two partitions of n objects, with k the larger class count
fn rand_agreement(a: *mem.Arena, cx: []const usize, cy: []const usize, n: usize, k: usize) -> (f64, err) {
    let (t, e1) = mem.alloc[usize](a, k * k)
    if e1 != ok { ret (0.0f64, e1) }
    var z = 0usize
    while z < k * k {
        t[z] = 0usize
        z += 1usize
    }
    table_counts(cx, cy, n, k, k, t)
    var sij = 0.0f64
    var sa = 0.0f64
    var sb = 0.0f64
    var i = 0usize
    while i < k {
        var rowsum = 0.0f64
        var colsum = 0.0f64
        var j = 0usize
        while j < k {
            let v = f64(t[i * k + j])
            sij += v * v
            rowsum += v
            colsum += f64(t[j * k + i])
            j += 1usize
        }
        sa += rowsum * rowsum
        sb += colsum * colsum
        i += 1usize
    }
    let nf = f64(n)
    let choose2 = nf * (nf - 1.0f64) / 2.0f64
    ret (1.0f64 + (sij - (sa + sb) / 2.0f64) / choose2, ok)
}

// clue's minimal Euclidean distance between the hard partitions cx and cy (labels 1..k): the square root of the summed squared differences of the
// membership matrices, with the classes of cy matched to those of cx by the maximal cross-product assignment
fn euclid_partition(a: *mem.Arena, cx: []const usize, cy: []const usize, n: usize, k: usize) -> (f64, err) {
    let (t, e1) = mem.alloc[usize](a, k * k)
    if e1 != ok { ret (0.0f64, e1) }
    var z = 0usize
    while z < k * k {
        t[z] = 0usize
        z += 1usize
    }
    table_counts(cx, cy, n, k, k, t)
    // cost = minus the cross-products C[i, j] = t[i, j]
    let (costs, e2) = mem.alloc[f64](a, k * k)
    let (asg, e3) = mem.alloc[usize](a, k)
    let (scratch, e4) = mem.alloc[f64](a, 4usize * (k + 1usize))
    let (used, e5) = mem.alloc[usize](a, 2usize * (k + 1usize))
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, Malformed) }
    z = 0usize
    while z < k * k {
        costs[z] = 0.0f64 - f64(t[z])
        z += 1usize
    }
    let (_, e6) = mt.hungarian(costs, k, asg, scratch, used)
    if e6 != ok { ret (0.0f64, e6) }
    // the squared differences of the membership matrices with cy's class asg[i] in place of class i
    var d2 = 0.0f64
    var r = 0usize
    while r < n {
        var i = 0usize
        while i < k {
            var mx = 0.0f64
            if cx[r] == i + 1usize { mx = 1.0f64 }
            var my = 0.0f64
            if cy[r] == asg[i] + 1usize { my = 1.0f64 }
            d2 += (mx - my) * (mx - my)
            i += 1usize
        }
        r += 1usize
    }
    ret (math.sqrt[f64](d2), ok)
}

// the other agreement and dissimilarity measures of clue on two hard partitions (labels 1..k): kind 2 cRand, 3 NMI, 4 Katz-Powell, 5 Fowlkes-Mallows, 6 Jaccard, 7 purity, 8 PS
// (prediction strength), 9 variation of information, 10 comemberships distance, 11 symmetric difference, 12 Manhattan membership distance (the classes matched by the minimal
// assignment). All but the last are functions of the contingency table of the two label vectors.
fn partition_measure(a: *mem.Arena, cx: []const usize, cy: []const usize, n: usize, k: usize, kind: usize) -> (f64, err) {
    let (t, e1) = mem.alloc[usize](a, k * k)
    let (rs, e2) = mem.alloc[f64](a, k)
    let (cs, e3) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, Malformed) }
    var z = 0usize
    while z < k * k {
        t[z] = 0usize
        z += 1usize
    }
    table_counts(cx, cy, n, k, k, t)
    var sxy = 0.0f64
    var i = 0usize
    while i < k {
        rs[i] = 0.0f64
        cs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            let v = f64(t[i * k + j])
            sxy += v * v
            rs[i] += v
            cs[j] += v
            j += 1usize
        }
        i += 1usize
    }
    var sx = 0.0f64
    var sy = 0.0f64
    i = 0usize
    while i < k {
        sx += rs[i] * rs[i]
        sy += cs[i] * cs[i]
        i += 1usize
    }
    let nf = f64(n)
    if kind == 2usize {
        let txy = sxy - nf
        let tx = sx - nf
        let ty = sy - nf
        let f = tx * ty / (nf * nf - nf)
        ret ((txy - f) / ((tx + ty) / 2.0f64 - f), ok)
    }
    if kind == 3usize || kind == 9usize {
        var out = 0.0f64
        var ex = 0.0f64
        var ey = 0.0f64
        i = 0usize
        while i < k {
            let mxv = rs[i] / nf
            if mxv > 0.0f64 { ex += mxv * math.log[f64](mxv) }
            let myv = cs[i] / nf
            if myv > 0.0f64 { ey += myv * math.log[f64](myv) }
            var j = 0usize
            while j < k {
                let g = f64(t[i * k + j]) / nf
                let dl = (rs[i] / nf) * (cs[j] / nf)
                if g > 0.0f64 && dl > 0.0f64 { out += g * math.log[f64](g / dl) }
                j += 1usize
            }
            i += 1usize
        }
        if kind == 3usize { ret (out / math.sqrt[f64](ex * ey), ok) }
        ret ((0.0f64 - ex) + (0.0f64 - ey) - 2.0f64 * out, ok)
    }
    if kind == 4usize { ret ((nf * nf * sxy - sx * sy) / math.sqrt[f64](sx * (nf * nf - sx) * sy * (nf * nf - sy)), ok) }
    if kind == 5usize { ret ((sxy - nf) / math.sqrt[f64]((sx - nf) * (sy - nf)), ok) }
    if kind == 6usize { ret ((sxy - nf) / (sx + sy - nf - sxy), ok) }
    if kind == 7usize {
        var tot = 0.0f64
        i = 0usize
        while i < k {
            var mx = 0.0f64
            var j = 0usize
            while j < k {
                if f64(t[i * k + j]) > mx { mx = f64(t[i * k + j]) }
                j += 1usize
            }
            tot += mx
            i += 1usize
        }
        ret (tot / nf, ok)
    }
    if kind == 8usize {
        var best = 1.0e300f64
        var have = false
        i = 0usize
        while i < k {
            let sz = rs[i]
            if sz > 1.0f64 {
                var sq = 0.0f64
                var j = 0usize
                while j < k {
                    sq += f64(t[i * k + j]) * f64(t[i * k + j])
                    j += 1usize
                }
                let v = (sq - sz) / (sz * (sz - 1.0f64))
                if v < best { best = v }
                have = true
            }
            i += 1usize
        }
        if !have { ret (0.0f64 / 0.0f64, ok) }
        ret (best, ok)
    }
    if kind == 10usize { ret (math.sqrt[f64](sx - 2.0f64 * sxy + sy), ok) }
    if kind == 11usize {
        let choose2 = nf * (nf - 1.0f64) / 2.0f64
        // (1 - Rand) choose(n, 2)
        ret ((0.0f64 - (sxy - (sx + sy) / 2.0f64) / choose2) * choose2, ok)
    }
    // Manhattan: C[i, j] = a_i + b_j - 2 n_ij, matched by the minimal assignment
    let (costs, e4) = mem.alloc[f64](a, k * k)
    let (asg, e5) = mem.alloc[usize](a, k)
    let (scratch, e6) = mem.alloc[f64](a, 4usize * (k + 1usize))
    let (used, e7) = mem.alloc[usize](a, 2usize * (k + 1usize))
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0.0f64, Malformed) }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            costs[i * k + j] = rs[i] + cs[j] - 2.0f64 * f64(t[i * k + j])
            j += 1usize
        }
        i += 1usize
    }
    let (v, e8) = mt.hungarian(costs, k, asg, scratch, used)
    if e8 != ok { ret (0.0f64, e8) }
    ret (v, ok)
}

// the Gordon-Vichi (kind 13), Boorman-Arabie A (14, half the Manhattan distance), C (15, the class counts minus twice the join's classes) and E (16, one minus the mutual
// information over the joint entropy) dissimilarities of two hard partitions with kx and ky observed classes (labels 1..kx and 1..ky)
fn partition_measure2(a: *mem.Arena, cx: []const usize, cy: []const usize, n: usize, kx: usize, ky: usize, kind: usize) -> (f64, err) {
    var k = kx
    if ky > k { k = ky }
    if kind == 14usize {
        let (v, e) = partition_measure(a, cx, cy, n, k, 12usize)
        ret (v / 2.0f64, e)
    }
    let (t, e1) = mem.alloc[usize](a, k * k)
    let (rs, e2) = mem.alloc[f64](a, k)
    let (cs, e3) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, Malformed) }
    var z = 0usize
    while z < k * k {
        t[z] = 0usize
        z += 1usize
    }
    table_counts(cx, cy, n, k, k, t)
    var i = 0usize
    while i < k {
        rs[i] = 0.0f64
        cs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            rs[i] += f64(t[i * k + j])
            cs[j] += f64(t[i * k + j])
            j += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    if kind == 16usize {
        var mi = 0.0f64
        var h = 0.0f64
        i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                let g = f64(t[i * k + j]) / nf
                if g > 0.0f64 {
                    h -= g * math.log[f64](g)
                    mi += g * math.log[f64](g / ((rs[i] / nf) * (cs[j] / nf)))
                }
                j += 1usize
            }
            i += 1usize
        }
        ret (1.0f64 - mi / h, ok)
    }
    if kind == 15usize {
        // the join: the connected components of the classes linked by a non-empty cell
        let (par, e4) = mem.alloc[usize](a, 2usize * k)
        if e4 != ok { ret (0.0f64, Malformed) }
        i = 0usize
        while i < 2usize * k {
            par[i] = i
            i += 1usize
        }
        i = 0usize
        while i < kx {
            var j = 0usize
            while j < ky {
                if t[i * k + j] > 0usize {
                    var r1 = i
                    while par[r1] != r1 { r1 = par[r1] }
                    var r2 = k + j
                    while par[r2] != r2 { r2 = par[r2] }
                    if r1 != r2 { par[r2] = r1 }
                }
                j += 1usize
            }
            i += 1usize
        }
        var comps = 0usize
        i = 0usize
        while i < kx {
            if par[i] == i { comps += 1usize }
            i += 1usize
        }
        var j2 = 0usize
        while j2 < ky {
            if par[k + j2] == k + j2 { comps += 1usize }
            j2 += 1usize
        }
        ret (f64(kx) + f64(ky) - 2.0f64 * f64(comps), ok)
    }
    // Gordon-Vichi: C[i, j] = a_i + b_j - 2 n_ij on the kx by ky block, zero padding, minimal assignment, square root
    let (costs, e5) = mem.alloc[f64](a, k * k)
    let (asg, e6) = mem.alloc[usize](a, k)
    let (scratch, e7) = mem.alloc[f64](a, 4usize * (k + 1usize))
    let (used, e8) = mem.alloc[usize](a, 2usize * (k + 1usize))
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0.0f64, Malformed) }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            costs[i * k + j] = 0.0f64
            if i < kx && j < ky { costs[i * k + j] = rs[i] + cs[j] - 2.0f64 * f64(t[i * k + j]) }
            j += 1usize
        }
        i += 1usize
    }
    let (v, e9) = mt.hungarian(costs, k, asg, scratch, used)
    if e9 != ok { ret (0.0f64, e9) }
    ret (math.sqrt[f64](v), ok)
}

// cl_dissimilarity of two hclust trees on n objects through their ultrametrics (the cophenetic distances of the n (n - 1) / 2 pairs): kind 0 euclidean, 1 manhattan, 2 cophenetic (1 - cor^2), 3 gamma (twice the discordant pairs of ultrametric entries over choose(m, 2)), 4 Chebyshev
fn hier_dissimilarity(a: *mem.Arena, t1: *const hc.Tree, t2: *const hc.Tree, n: usize, kind: usize) -> (f64, err) {
    let m = n * (n - 1usize) / 2usize
    let (u, e0) = mem.alloc[f64](a, m)
    let (v, e1) = mem.alloc[f64](a, m)
    if e0 != ok || e1 != ok { ret (0.0f64, mem.Full) }
    var q = 0usize
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            u[q] = hc.cophenetic(a, t1, n, i, j)
            v[q] = hc.cophenetic(a, t2, n, i, j)
            q += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var s = 0.0f64
    var k = 0usize
    if kind == 0usize {
        while k < m {
            s += (u[k] - v[k]) * (u[k] - v[k])
            k += 1usize
        }
        ret (math.sqrt[f64](s), ok)
    }
    if kind == 1usize {
        while k < m {
            s += math.abs[f64](u[k] - v[k])
            k += 1usize
        }
        ret (s, ok)
    }
    if kind == 4usize {
        while k < m {
            let d = math.abs[f64](u[k] - v[k])
            if d > s { s = d }
            k += 1usize
        }
        ret (s, ok)
    }
    if kind == 2usize {
        var mu = 0.0f64
        var mv = 0.0f64
        while k < m {
            mu += u[k]
            mv += v[k]
            k += 1usize
        }
        mu = mu / f64(m)
        mv = mv / f64(m)
        var suv = 0.0f64
        var suu = 0.0f64
        var svv = 0.0f64
        k = 0usize
        while k < m {
            suv += (u[k] - mu) * (v[k] - mv)
            suu += (u[k] - mu) * (u[k] - mu)
            svv += (v[k] - mv) * (v[k] - mv)
            k += 1usize
        }
        ret (1.0f64 - suv * suv / (suu * svv), ok)
    }
    var disc = 0.0f64
    k = 0usize
    while k < m {
        var l = k + 1usize
        while l < m {
            let p = (u[k] - u[l]) * (v[k] - v[l])
            if p < 0.0f64 { disc += 1.0f64 }
            l += 1usize
        }
        k += 1usize
    }
    ret (2.0f64 * disc / (f64(m) * (f64(m) - 1.0f64) / 2.0f64), ok)
}

// the cl_agreement of two hclust trees: kind 5 cophenetic (the correlation of the ultrametrics), 6 angle (their cosine), 7 gamma (one minus the gamma dissimilarity), 8 euclidean and 9 manhattan (1 / (1 + the dissimilarity)); kind 10 is the symmetric
// difference dissimilarity, the classes (one per merge) of the two trees counted that are in only one of them
fn hier_agreement(a: *mem.Arena, t1: *const hc.Tree, t2: *const hc.Tree, n: usize, kind: usize) -> (f64, err) {
    if kind == 10usize {
        let m1 = n - 1usize
        let (c1, e0) = mem.alloc[bool](a, m1 * n)
        let (c2, e1) = mem.alloc[bool](a, m1 * n)
        if e0 != ok || e1 != ok { ret (0.0f64, mem.Full) }
        var tr = 0usize
        while tr < 2usize {
            var i = 0usize
            while i < m1 {
                var j = 0usize
                while j < n {
                    if tr == 0usize { c1[i * n + j] = false } else { c2[i * n + j] = false }
                    j += 1usize
                }
                var side = 0usize
                while side < 2usize {
                    var code = t1.merge_a[i]
                    if tr == 0usize {
                        if side == 1usize { code = t1.merge_b[i] }
                    } else {
                        code = t2.merge_a[i]
                        if side == 1usize { code = t2.merge_b[i] }
                    }
                    if code < 0i32 {
                        let o = usize(0i32 - code) - 1usize
                        if tr == 0usize { c1[i * n + o] = true } else { c2[i * n + o] = true }
                    } else {
                        let r = usize(code) - 1usize
                        j = 0usize
                        while j < n {
                            if tr == 0usize {
                                if c1[r * n + j] { c1[i * n + j] = true }
                            } else {
                                if c2[r * n + j] { c2[i * n + j] = true }
                            }
                            j += 1usize
                        }
                    }
                    side += 1usize
                }
                i += 1usize
            }
            tr += 1usize
        }
        var common = 0usize
        var i2 = 0usize
        while i2 < m1 {
            var k = 0usize
            var found = false
            while k < m1 && !found {
                var same = true
                var j2 = 0usize
                while j2 < n {
                    if c1[i2 * n + j2] != c2[k * n + j2] { same = false }
                    j2 += 1usize
                }
                if same { found = true }
                k += 1usize
            }
            if found { common += 1usize }
            i2 += 1usize
        }
        ret (f64(2usize * m1 - 2usize * common), ok)
    }
    if kind == 8usize || kind == 9usize {
        let (d, e) = hier_dissimilarity(a, t1, t2, n, kind - 8usize)
        ret (1.0f64 / (1.0f64 + d), e)
    }
    if kind == 7usize {
        let (d, e) = hier_dissimilarity(a, t1, t2, n, 3usize)
        ret (1.0f64 - d, e)
    }
    let m = n * (n - 1usize) / 2usize
    let (u, e0) = mem.alloc[f64](a, m)
    let (v, e1) = mem.alloc[f64](a, m)
    if e0 != ok || e1 != ok { ret (0.0f64, mem.Full) }
    var q = 0usize
    var i3 = 0usize
    while i3 + 1usize < n {
        var j3 = i3 + 1usize
        while j3 < n {
            u[q] = hc.cophenetic(a, t1, n, i3, j3)
            v[q] = hc.cophenetic(a, t2, n, i3, j3)
            q += 1usize
            j3 += 1usize
        }
        i3 += 1usize
    }
    var mu = 0.0f64
    var mv = 0.0f64
    var k2 = 0usize
    while k2 < m {
        mu += u[k2]
        mv += v[k2]
        k2 += 1usize
    }
    mu = mu / f64(m)
    mv = mv / f64(m)
    if kind == 6usize {
        mu = 0.0f64
        mv = 0.0f64
    }
    var suv = 0.0f64
    var suu = 0.0f64
    var svv = 0.0f64
    k2 = 0usize
    while k2 < m {
        suv += (u[k2] - mu) * (v[k2] - mv)
        suu += (u[k2] - mu) * (u[k2] - mu)
        svv += (v[k2] - mv) * (v[k2] - mv)
        k2 += 1usize
    }
    ret (suv / math.sqrt[f64](suu * svv), ok)
}

// clue's minimal Euclidean membership distance of two soft partitions given as n by k row-major membership matrices u and v: the classes of v matched to those of u by the maximal cross-product assignment (solve_LSAP(crossprod(u, v), maximum = TRUE))
fn euclid_soft(a: *mem.Arena, u: []const f64, v: []const f64, n: usize, k: usize) -> (f64, err) {
    let (costs, e2) = mem.alloc[f64](a, k * k)
    let (asg, e3) = mem.alloc[usize](a, k)
    let (scratch, e4) = mem.alloc[f64](a, 4usize * (k + 1usize))
    let (used, e5) = mem.alloc[usize](a, 2usize * (k + 1usize))
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, Malformed) }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var c = 0.0f64
            var r = 0usize
            while r < n {
                c += u[r * k + i] * v[r * k + j]
                r += 1usize
            }
            costs[i * k + j] = 0.0f64 - c
            j += 1usize
        }
        i += 1usize
    }
    let (_, e6) = mt.hungarian(costs, k, asg, scratch, used)
    if e6 != ok { ret (0.0f64, e6) }
    var d2 = 0.0f64
    var r2 = 0usize
    while r2 < n {
        i = 0usize
        while i < k {
            let d = u[r2 * k + i] - v[r2 * k + asg[i]]
            d2 += d * d
            i += 1usize
        }
        r2 += 1usize
    }
    ret (math.sqrt[f64](d2), ok)
}
