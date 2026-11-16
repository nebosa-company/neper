// R hclust: Murtagh's nearest-neighbour Lance-Williams agglomeration (ward.D, ward.D2, single, complete, average, mcquitty, median,
// centroid) from a full dissimilarity matrix, with the package's merge matrix, ordering, heights, cutree and cophenetic distances.
// The ties and tie-breaking follow hclust.f and hcass2, so merges and orders equal R's.
//
// Not here: the dendextend functions (cor_bakers_gamma, entanglement, untangle, ladderize, fowlkes_mallows), as.dendrogram and members.

use e.math
use e.mem

// method: 1 ward.D, 2 single, 3 complete, 4 average, 5 mcquitty, 6 median, 7 centroid, 8 ward.D2
type Tree = struct { merge_a: []i32, merge_b: []i32, height: []f64, order: []i32 }

// d is the n by n full symmetric matrix (row-major); it is copied
fn hclust(a: *mem.Arena, d: []const f64, n: usize, method: usize) -> (Tree, err) {
    let (diss, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret (zero, e1) }
    let (membr, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (zero, e2) }
    let (flag, e3) = mem.alloc[bool](a, n)
    if e3 != ok { ret (zero, e3) }
    let (nn, e4) = mem.alloc[usize](a, n)
    if e4 != ok { ret (zero, e4) }
    let (disnn, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret (zero, e5) }
    let (ia, e6) = mem.alloc[usize](a, n)
    if e6 != ok { ret (zero, e6) }
    let (ib, e7) = mem.alloc[usize](a, n)
    if e7 != ok { ret (zero, e7) }
    let (crit, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret (zero, e8) }
    let inf = 1.0e300f64
    var i = 0usize
    while i < n * n {
        diss[i] = d[i]
        if method == 8usize { diss[i] = d[i] * d[i] }
        i += 1usize
    }
    i = 0usize
    while i < n {
        flag[i] = true
        membr[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i + 1usize < n {
        var dmin = inf
        var jm = 0usize
        var j = i + 1usize
        while j < n {
            if diss[i * n + j] < dmin {
                dmin = diss[i * n + j]
                jm = j
            }
            j += 1usize
        }
        nn[i] = jm
        disnn[i] = dmin
        i += 1usize
    }
    var ncl = n
    while ncl > 1usize {
        var dmin = inf
        var im = 0usize
        var jm = 0usize
        i = 0usize
        while i + 1usize < n {
            if flag[i] && disnn[i] < dmin {
                dmin = disnn[i]
                im = i
                jm = nn[i]
            }
            i += 1usize
        }
        ncl -= 1usize
        var i2 = im
        var j2 = jm
        if jm < im {
            i2 = jm
            j2 = im
        }
        ia[n - ncl - 1usize] = i2
        ib[n - ncl - 1usize] = j2
        var cv = dmin
        if method == 8usize { cv = math.sqrt[f64](dmin) }
        crit[n - ncl - 1usize] = cv
        flag[j2] = false
        var dm = inf
        var jj = 0usize
        var k = 0usize
        while k < n {
            if flag[k] && k != i2 {
                var ind1 = i2 * n + k
                var ind2 = j2 * n + k
                if k < i2 { ind1 = k * n + i2 }
                if k < j2 { ind2 = k * n + j2 }
                let d12 = dmin
                let d1 = diss[ind1]
                let d2 = diss[ind2]
                var nv = 0.0f64
                if method == 1usize || method == 8usize {
                    nv = ((membr[i2] + membr[k]) * d1 + (membr[j2] + membr[k]) * d2 - membr[k] * d12) / (membr[i2] + membr[j2] + membr[k])
                }
                if method == 2usize {
                    nv = d1
                    if d2 < nv { nv = d2 }
                }
                if method == 3usize {
                    nv = d1
                    if d2 > nv { nv = d2 }
                }
                if method == 4usize { nv = (membr[i2] * d1 + membr[j2] * d2) / (membr[i2] + membr[j2]) }
                if method == 5usize { nv = 0.5f64 * d1 + 0.5f64 * d2 }
                if method == 6usize { nv = ((d1 + d2) - d12 / 2.0f64) / 2.0f64 }
                if method == 7usize {
                    nv = (membr[i2] * d1 + membr[j2] * d2 - membr[i2] * membr[j2] * d12 / (membr[i2] + membr[j2])) / (membr[i2] + membr[j2])
                }
                diss[ind1] = nv
                if i2 < k && nv < dm {
                    dm = nv
                    jj = k
                }
            }
            k += 1usize
        }
        membr[i2] = membr[i2] + membr[j2]
        disnn[i2] = dm
        nn[i2] = jj
        i = 0usize
        while i + 1usize < n {
            if flag[i] && (nn[i] == i2 || nn[i] == j2) {
                var dm2 = inf
                var j = i + 1usize
                var jj2 = 0usize
                while j < n {
                    if flag[j] && diss[i * n + j] < dm2 {
                        dm2 = diss[i * n + j]
                        jj2 = j
                    }
                    j += 1usize
                }
                nn[i] = jj2
                disnn[i] = dm2
            }
            i += 1usize
        }
    }
    // hcass2: the merge matrix and the order
    let m = n - 1usize
    let (iia, e9) = mem.alloc[i32](a, m)
    if e9 != ok { ret (zero, e9) }
    let (iib, e10) = mem.alloc[i32](a, m)
    if e10 != ok { ret (zero, e10) }
    i = 0usize
    while i < m {
        iia[i] = i32(ia[i]) + 1i32
        iib[i] = i32(ib[i]) + 1i32
        i += 1usize
    }
    i = 0usize
    while i + 1usize < m {
        let kk = i32(ia[i]) + 1i32
        var j = i + 1usize
        while j < m {
            if i32(ia[j]) + 1i32 == kk { iia[j] = 0i32 - i32(i + 1usize) }
            if i32(ib[j]) + 1i32 == kk { iib[j] = 0i32 - i32(i + 1usize) }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        iia[i] = 0i32 - iia[i]
        iib[i] = 0i32 - iib[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        if iia[i] > 0i32 && iib[i] < 0i32 {
            let t = iia[i]
            iia[i] = iib[i]
            iib[i] = t
        }
        if iia[i] > 0i32 && iib[i] > 0i32 {
            var k1 = iia[i]
            var k2 = iib[i]
            if k2 < k1 {
                k1 = iib[i]
                k2 = iia[i]
            }
            iia[i] = k1
            iib[i] = k2
        }
        i += 1usize
    }
    let (ord, e11) = mem.alloc[i32](a, n)
    if e11 != ok { ret (zero, e11) }
    ord[0usize] = iia[m - 1usize]
    ord[1usize] = iib[m - 1usize]
    var loc = 2usize
    var ii = m - 1usize
    while ii > 0usize {
        let cl = i32(ii)
        var j = 0usize
        var placed = false
        while j < loc && !placed {
            if ord[j] == cl {
                ord[j] = iia[ii - 1usize]
                if j == loc - 1usize {
                    loc += 1usize
                    ord[loc - 1usize] = iib[ii - 1usize]
                } else {
                    loc += 1usize
                    var kk = loc - 1usize
                    while kk > j + 1usize {
                        ord[kk] = ord[kk - 1usize]
                        kk -= 1usize
                    }
                    ord[j + 1usize] = iib[ii - 1usize]
                }
                placed = true
            }
            j += 1usize
        }
        ii -= 1usize
    }
    i = 0usize
    while i < n {
        ord[i] = 0i32 - ord[i]
        i += 1usize
    }
    ret (Tree { merge_a: iia, merge_b: iib, height: crit[0usize..m], order: ord }, ok)
}

// cutree into k clusters: labels 1..k numbered by first appearance over the observations
fn cutree(a: *mem.Arena, t: *const Tree, n: usize, k: usize, out: []usize) -> err {
    let (grp, e) = mem.alloc[usize](a, n)
    if e != ok { ret e }
    let (lab, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret e2 }
    // every observation starts alone; apply the first n - k merges
    var i = 0usize
    while i < n {
        grp[i] = i
        i += 1usize
    }
    // cluster id of merge step s: the representative observation of its members
    let (rep, e3) = mem.alloc[usize](a, n)
    if e3 != ok { ret e3 }
    var s = 0usize
    while s < n - k {
        var ra = 0usize
        var rb = 0usize
        if t.merge_a[s] < 0i32 { ra = usize(0i32 - t.merge_a[s]) - 1usize } else { ra = rep[usize(t.merge_a[s]) - 1usize] }
        if t.merge_b[s] < 0i32 { rb = usize(0i32 - t.merge_b[s]) - 1usize } else { rb = rep[usize(t.merge_b[s]) - 1usize] }
        let ga = grp[ra]
        let gb = grp[rb]
        i = 0usize
        while i < n {
            if grp[i] == gb { grp[i] = ga }
            i += 1usize
        }
        rep[s] = ra
        s += 1usize
    }
    var next = 1usize
    i = 0usize
    while i < n {
        lab[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        var found = 0usize
        while j < i {
            if grp[j] == grp[i] {
                found = lab[j]
                break
            }
            j += 1usize
        }
        if found == 0usize {
            found = next
            next += 1usize
        }
        lab[i] = found
        out[i] = found
        i += 1usize
    }
    ret ok
}

// cophenetic distance between observations p and q: the height of the merge that first joins them
fn cophenetic(a: *mem.Arena, t: *const Tree, n: usize, p: usize, q: usize) -> f64 {
    let (grp, e) = mem.alloc[usize](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let (rep, e3) = mem.alloc[usize](a, n)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        grp[i] = i
        i += 1usize
    }
    var s = 0usize
    while s < n - 1usize {
        var ra = 0usize
        var rb = 0usize
        if t.merge_a[s] < 0i32 { ra = usize(0i32 - t.merge_a[s]) - 1usize } else { ra = rep[usize(t.merge_a[s]) - 1usize] }
        if t.merge_b[s] < 0i32 { rb = usize(0i32 - t.merge_b[s]) - 1usize } else { rb = rep[usize(t.merge_b[s]) - 1usize] }
        let ga = grp[ra]
        let gb = grp[rb]
        i = 0usize
        while i < n {
            if grp[i] == gb { grp[i] = ga }
            i += 1usize
        }
        rep[s] = ra
        if grp[p] == grp[q] { ret t.height[s] }
        s += 1usize
    }
    ret 0.0f64
}

// Fowlkes-Mallows index of two clusterings with labels 1..k (dendextend FM_index): the index, its expectation and its variance under independence
fn fm_index(a: *mem.Arena, l1: []const usize, l2: []const usize) -> (f64, f64, f64, err) {
    let n = l1.len
    var k1 = 0usize
    var k2 = 0usize
    var i = 0usize
    while i < n {
        if l1[i] > k1 { k1 = l1[i] }
        if l2[i] > k2 { k2 = l2[i] }
        i += 1usize
    }
    let (m, e) = mem.alloc[f64](a, k1 * k2)
    if e != ok { ret (0.0f64, 0.0f64, 0.0f64, e) }
    let (r, e2) = mem.alloc[f64](a, k1)
    if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
    let (c, e3) = mem.alloc[f64](a, k2)
    if e3 != ok { ret (0.0f64, 0.0f64, 0.0f64, e3) }
    i = 0usize
    while i < k1 * k2 {
        m[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k1 {
        r[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k2 {
        c[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        m[(l1[i] - 1usize) * k2 + (l2[i] - 1usize)] += 1.0f64
        r[l1[i] - 1usize] += 1.0f64
        c[l2[i] - 1usize] += 1.0f64
        i += 1usize
    }
    let nf = f64(n)
    var tk = 0.0f64 - nf
    i = 0usize
    while i < k1 * k2 {
        tk += m[i] * m[i]
        i += 1usize
    }
    var pk = 0.0f64 - nf
    var pk2 = 0.0f64
    i = 0usize
    while i < k1 {
        pk += r[i] * r[i]
        pk2 += r[i] * (r[i] - 1.0f64) * (r[i] - 2.0f64)
        i += 1usize
    }
    var qk = 0.0f64 - nf
    var qk2 = 0.0f64
    i = 0usize
    while i < k2 {
        qk += c[i] * c[i]
        qk2 += c[i] * (c[i] - 1.0f64) * (c[i] - 2.0f64)
        i += 1usize
    }
    let fm = tk / math.sqrt[f64](pk * qk)
    let ef = math.sqrt[f64](pk * qk) / (nf * (nf - 1.0f64))
    let vf = 2.0f64 / (nf * (nf - 1.0f64)) + 4.0f64 * pk2 * qk2 / ((nf * (nf - 1.0f64) * (nf - 2.0f64)) * pk * qk) + (pk - 2.0f64 - 4.0f64 * pk2 / pk) * (qk - 2.0f64 - 4.0f64 * qk2 / qk) / (nf * (nf - 1.0f64) * (nf - 2.0f64) * (nf - 3.0f64)) - pk * qk / (nf * nf * (nf - 1.0f64) * (nf - 1.0f64))
    ret (fm, ef, vf, ok)
}

// the Pearson correlation of the cophenetic distances of two trees over the same observations (dendextend cor_cophenetic)
fn cor_cophenetic(a: *mem.Arena, t1: *const Tree, t2: *const Tree, n: usize) -> f64 {
    var sx = 0.0f64
    var sy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var sxy = 0.0f64
    var cnt = 0.0f64
    var col = 0usize
    while col < n {
        var row = col + 1usize
        while row < n {
            let x = cophenetic(a, t1, n, row, col)
            let y = cophenetic(a, t2, n, row, col)
            sx += x
            sy += y
            sxx += x * x
            syy += y * y
            sxy += x * y
            cnt += 1.0f64
            row += 1usize
        }
        col += 1usize
    }
    let cov = sxy - sx * sy / cnt
    ret cov / math.sqrt[f64]((sxx - sx * sx / cnt) * (syy - sy * sy / cnt))
}

// agnes' agglomerative coefficient: one minus the mean over observations of the height of their first merge relative to the final height
// (agnes' heights equal hclust's for the matching method: average, single, complete, ward = ward.D2, weighted = mcquitty)
fn agnes_ac(a: *mem.Arena, t: *const Tree, n: usize) -> f64 {
    let (first, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i + 1usize < n {
        if t.merge_a[i] < 0i32 { first[usize(0i32 - t.merge_a[i]) - 1usize] = t.height[i] }
        if t.merge_b[i] < 0i32 { first[usize(0i32 - t.merge_b[i]) - 1usize] = t.height[i] }
        i += 1usize
    }
    let hmax = t.height[n - 2usize]
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += first[i] / hmax
        i += 1usize
    }
    ret 1.0f64 - s / f64(n)
}
