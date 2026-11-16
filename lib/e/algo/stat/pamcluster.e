// R cluster: pam (partitioning around medoids) from a full dissimilarity matrix: the BUILD phase picks the first medoid by the smallest
// total distance and each next one by the largest total gain, the SWAP phase exchanges a medoid and a non-medoid while the total
// distance falls; medoids are reported in the order BUILD chose them (a swap replaces in place), and each observation takes the first nearest one.
//
// Not here: clara, fanny, agnes, diana, mona, daisy, silhouette and the tie rules beyond "first".

use e.mem

// build and swap are the average distances to the nearest medoid after each phase
type PamResult = struct { build: f64, swap: f64 }

fn near_cost(d: []const f64, n: usize, med: []const usize, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var m = 1.0e300f64
        var j = 0usize
        while j < k {
            let v = d[i * n + med[j]]
            if v < m { m = v }
            j += 1usize
        }
        s += m
        i += 1usize
    }
    ret s
}

// med receives the k 0-based medoid indices in package order, label 1..k per observation
fn pam(a: *mem.Arena, d: []const f64, n: usize, k: usize, med: []usize, label: []usize) -> (PamResult, err) {
    let (isman, e1) = mem.alloc[bool](a, n)
    if e1 != ok { ret (zero, e1) }
    let (nearest, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (zero, e2) }
    var i = 0usize
    while i < n {
        isman[i] = false
        i += 1usize
    }
    var best = 0usize
    var bs = 1.0e300f64
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += d[i * n + j]
            j += 1usize
        }
        if s < bs {
            bs = s
            best = i
        }
        i += 1usize
    }
    med[0usize] = best
    isman[best] = true
    i = 0usize
    while i < n {
        nearest[i] = d[i * n + best]
        i += 1usize
    }
    var chosen = 1usize
    while chosen < k {
        var bi = n
        var bg = 0.0f64 - 1.0f64
        i = 0usize
        while i < n {
            if !isman[i] {
                var g = 0.0f64
                var j = 0usize
                while j < n {
                    if !isman[j] {
                        let dd = nearest[j] - d[i * n + j]
                        if dd > 0.0f64 { g += dd }
                    }
                    j += 1usize
                }
                if g > bg {
                    bg = g
                    bi = i
                }
            }
            i += 1usize
        }
        med[chosen] = bi
        isman[bi] = true
        chosen += 1usize
        i = 0usize
        while i < n {
            if d[i * n + bi] < nearest[i] { nearest[i] = d[i * n + bi] }
            i += 1usize
        }
    }
    // the package reports the BUILD medoids in increasing index order; swaps then replace in place
    i = 1usize
    while i < k {
        let t = med[i]
        var j = i
        while j > 0usize && med[j - 1usize] > t {
            med[j] = med[j - 1usize]
            j -= 1usize
        }
        med[j] = t
        i += 1usize
    }
    let build_cost = near_cost(d, n, med, k) / f64(n)
    var cost = near_cost(d, n, med, k)
    var improving = true
    while improving {
        improving = false
        var bm = k
        var bh = n
        var bc = cost
        var m = 0usize
        while m < k {
            var h = 0usize
            while h < n {
                if !isman[h] {
                    let old = med[m]
                    med[m] = h
                    let c = near_cost(d, n, med, k)
                    med[m] = old
                    if c < bc - 1.0e-12f64 {
                        bc = c
                        bm = m
                        bh = h
                    }
                }
                h += 1usize
            }
            m += 1usize
        }
        if bm < k {
            isman[med[bm]] = false
            med[bm] = bh
            isman[bh] = true
            cost = bc
            improving = true
        }
    }
    i = 0usize
    while i < n {
        var bj = 0usize
        var bv = d[i * n + med[0usize]]
        var j = 1usize
        while j < k {
            if d[i * n + med[j]] < bv {
                bv = d[i * n + med[j]]
                bj = j
            }
            j += 1usize
        }
        label[i] = bj + 1usize
        i += 1usize
    }
    ret (PamResult { build: build_cost, swap: cost / f64(n) }, ok)
}

// daisy(metric = "gower") for numeric (type 0) and nominal (type 1) columns of an n by p row-major matrix; a value of NaN is missing.
// out receives the n by n dissimilarity (NaN where no column is shared)
fn daisy_gower(a: *mem.Arena, x: []const f64, n: usize, p: usize, kind: []const usize, out: []f64) -> err {
    let (rng, e) = mem.alloc[f64](a, p)
    if e != ok { ret e }
    var c = 0usize
    while c < p {
        var lo = 1.0e300f64
        var hi = 0.0f64 - 1.0e300f64
        var i = 0usize
        while i < n {
            let v = x[i * p + c]
            if v == v {
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            i += 1usize
        }
        rng[c] = hi - lo
        c += 1usize
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var num = 0.0f64
            var den = 0.0f64
            var cc = 0usize
            while cc < p {
                let u = x[i * p + cc]
                let v = x[j * p + cc]
                if u == u && v == v {
                    den += 1.0f64
                    if kind[cc] == 0usize {
                        var dv = u - v
                        if dv < 0.0f64 { dv = 0.0f64 - dv }
                        if rng[cc] > 0.0f64 { num += dv / rng[cc] }
                    } else {
                        if u != v { num += 1.0f64 }
                    }
                }
                cc += 1usize
            }
            if den == 0.0f64 { out[i * n + j] = 0.0f64 / 0.0f64 } else { out[i * n + j] = num / den }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// silhouette widths of a clustering with labels 1..k from a full dissimilarity matrix; a singleton cluster has width 0
fn silhouette(a: *mem.Arena, d: []const f64, n: usize, cl: []const usize, k: usize, out: []f64) -> err {
    let (size, e) = mem.alloc[f64](a, k)
    if e != ok { ret e }
    var i = 0usize
    while i < k {
        size[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        size[cl[i] - 1usize] += 1.0f64
        i += 1usize
    }
    let (sums, e2) = mem.alloc[f64](a, k)
    if e2 != ok { ret e2 }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < k {
            sums[c] = 0.0f64
            c += 1usize
        }
        var j = 0usize
        while j < n {
            if j != i { sums[cl[j] - 1usize] += d[i * n + j] }
            j += 1usize
        }
        let own = cl[i] - 1usize
        if size[own] <= 1.0f64 {
            out[i] = 0.0f64
        } else {
            let ai = sums[own] / (size[own] - 1.0f64)
            var bi = 1.0e300f64
            c = 0usize
            while c < k {
                if c != own && size[c] > 0.0f64 {
                    let m = sums[c] / size[c]
                    if m < bi { bi = m }
                }
                c += 1usize
            }
            var mx = ai
            if bi > mx { mx = bi }
            out[i] = (bi - ai) / mx
        }
        i += 1usize
    }
    ret ok
}
