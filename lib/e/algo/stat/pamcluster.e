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
