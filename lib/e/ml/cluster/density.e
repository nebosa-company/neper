// Density clustering of row-major `f64` samples in caller storage: DBSCAN
// (core points have at least `min_points` neighbours within `eps`, their
// clusters grow through core neighbours, the rest is noise) and OPTICS (the
// same neighbourhoods produce an ordering and a reachability distance per
// sample, from which clusters at any `eps` can be read). Neighbourhoods are
// found by a full scan, so both are quadratic.

use e.math
use e.mem

error TooSmall
error Invalid

const NOISE: usize = 18446744073709551615usize

fn distance(x: []const f64, d: usize, i: usize, j: usize) -> f64 {
    var sum = 0.0f64
    var k = 0usize
    while k < d {
        let t = x[i * d + k] - x[j * d + k]
        sum += t * t
        k += 1usize
    }
    ret math.sqrt[f64](sum)
}

fn neighbour_count(x: []const f64, n: usize, d: usize, i: usize, eps: f64) -> usize {
    var count = 0usize
    var j = 0usize
    while j < n {
        if distance(x, d, i, j) <= eps { count += 1usize }
        j += 1usize
    }
    ret count
}

// DBSCAN; `labels` receives a cluster index per sample or `NOISE`, and the
// cluster count is answered. `scratch.len >= n` is the expansion queue.
fn dbscan(x: []const f64, n: usize, d: usize, eps: f64, min_points: usize, labels: []usize, scratch: []usize) -> (usize, err) {
    if x.len < n * d || labels.len < n || scratch.len < n { ret (0usize, TooSmall) }
    if eps < 0.0f64 || min_points == 0usize { ret (0usize, Invalid) }
    let unvisited = NOISE - 1usize
    var i = 0usize
    while i < n {
        labels[i] = unvisited
        i += 1usize
    }
    var queue = scratch[..n]
    var clusters = 0usize
    i = 0usize
    while i < n {
        if labels[i] == unvisited {
            if neighbour_count(x, n, d, i, eps) < min_points {
                labels[i] = NOISE
            } else {
                let cluster = clusters
                clusters += 1usize
                labels[i] = cluster
                var head = 0usize
                var tail = 0usize
                queue[tail] = i
                tail += 1usize
                while head < tail {
                    let p = queue[head]
                    head += 1usize
                    // p is a core point: every neighbour joins, and core neighbours expand.
                    var j = 0usize
                    while j < n {
                        if distance(x, d, p, j) <= eps {
                            if labels[j] == unvisited || labels[j] == NOISE {
                                let was_unvisited = labels[j] == unvisited
                                labels[j] = cluster
                                if was_unvisited && neighbour_count(x, n, d, j, eps) >= min_points {
                                    queue[tail] = j
                                    tail += 1usize
                                }
                            }
                        }
                        j += 1usize
                    }
                }
            }
        }
        i += 1usize
    }
    ret (clusters, ok)
}

// The core distance of `i`: the distance to its `min_points`-th nearest
// sample (itself counted), or `infinity` when it has fewer within `eps`.
fn core_distance(x: []const f64, n: usize, d: usize, i: usize, eps: f64, min_points: usize, work: []f64) -> f64 {
    var count = 0usize
    var j = 0usize
    while j < n {
        let dist = distance(x, d, i, j)
        if dist <= eps {
            // Insert into the sorted prefix of `work`.
            var k = count
            while k > 0usize && work[k - 1usize] > dist {
                if k < min_points { work[k] = work[k - 1usize] }
                k -= 1usize
            }
            if k < min_points { work[k] = dist }
            if count < min_points { count += 1usize }
        }
        j += 1usize
    }
    if count < min_points { ret infinity() }
    ret work[min_points - 1usize]
}

fn infinity() -> f64 { ret 1.0e300f64 }

// OPTICS: `order` receives the samples in processing order and
// `reachability` (indexed by sample) the reachability distance, `infinity`
// (1e300) for a sample never reached from a core point; a cluster at any
// `eps' <= eps` is a maximal run of the ordering whose reachability is at
// most `eps'`. `scratch.len >= n` floats hold core distances,
// `work.len >= min_points` sorts neighbours, `marks.len >= n`.
fn optics(x: []const f64, n: usize, d: usize, eps: f64, min_points: usize, order: []usize, reachability: []f64, scratch: []f64, work: []f64, marks: []usize) -> err {
    if x.len < n * d || order.len < n || reachability.len < n || scratch.len < n || work.len < min_points || marks.len < n { ret TooSmall }
    if eps < 0.0f64 || min_points == 0usize { ret Invalid }
    var core = scratch[..n]
    var i = 0usize
    while i < n {
        reachability[i] = infinity()
        marks[i] = 0usize
        core[i] = core_distance(x, n, d, i, eps, min_points, work)
        i += 1usize
    }
    var placed = 0usize
    i = 0usize
    while i < n {
        if marks[i] == 0usize {
            // Seed set: the unprocessed samples with a finite reachability; the
            // smallest is taken next. Start with i itself.
            var current = i
            var expanding = true
            while expanding {
                marks[current] = 1usize
                order[placed] = current
                placed += 1usize
                if core[current] < infinity() {
                    var j = 0usize
                    while j < n {
                        if marks[j] == 0usize {
                            let dist = distance(x, d, current, j)
                            if dist <= eps {
                                let reach = math.max[f64](core[current], dist)
                                if reach < reachability[j] { reachability[j] = reach }
                            }
                        }
                        j += 1usize
                    }
                }
                // Next: the unprocessed sample with the smallest finite reachability.
                var next = n
                var j = 0usize
                while j < n {
                    if marks[j] == 0usize && reachability[j] < infinity() && (next == n || reachability[j] < reachability[next]) { next = j }
                    j += 1usize
                }
                if next == n { expanding = false } else { current = next }
            }
        }
        i += 1usize
    }
    ret ok
}

// kNNdist(x, k): the distance from every row to its k-th nearest other row, into out (n values); scratch holds n values
fn knn_distance(x: []const f64, n: usize, d: usize, k: usize, out: []f64, scratch: []f64) {
    var i = 0usize
    while i < n {
        var m = 0usize
        var j = 0usize
        while j < n {
            if j != i {
                let v = distance(x, d, i, j)
                var q = m
                while q > 0usize && scratch[q - 1usize] > v {
                    scratch[q] = scratch[q - 1usize]
                    q -= 1usize
                }
                scratch[q] = v
                m += 1usize
            }
            j += 1usize
        }
        out[i] = scratch[k - 1usize]
        i += 1usize
    }
}

// dbscan::lof(x, minPts): the local outlier factor of every row into out (n values). kd holds n values, lrd n values, scratch n values.
// The neighbourhood of a row is every other row within its (minPts - 1)-th neighbour distance, ties included.
fn lof(x: []const f64, n: usize, d: usize, min_pts: usize, out: []f64, kd: []f64, lrd: []f64, scratch: []f64) {
    knn_distance(x, n, d, min_pts - 1usize, kd, scratch)
    var a = 0usize
    while a < n {
        var cnt = 0.0f64
        var s = 0.0f64
        var b = 0usize
        while b < n {
            if b != a {
                let dab = distance(x, d, a, b)
                if dab <= kd[a] {
                    var m = kd[b]
                    if dab > m { m = dab }
                    s += m
                    cnt += 1.0f64
                }
            }
            b += 1usize
        }
        lrd[a] = 1.0f64 / (s / cnt)
        a += 1usize
    }
    a = 0usize
    while a < n {
        var cnt = 0.0f64
        var s = 0.0f64
        var b = 0usize
        while b < n {
            if b != a && distance(x, d, a, b) <= kd[a] {
                s += lrd[b]
                cnt += 1.0f64
            }
            b += 1usize
        }
        var v = s / cnt / lrd[a]
        if v != v { v = 1.0f64 }
        out[a] = v
        a += 1usize
    }
}

// the k nearest other rows of `row` by distance, ids and distances in ascending order (stable on equal distances)
fn knn_list(x: []const f64, n: usize, d: usize, k: usize, row: usize, ids: []usize, dist: []f64) {
    var m = 0usize
    var j = 0usize
    while j < n {
        if j != row {
            let v = distance(x, d, row, j)
            var q = m
            while q > 0usize && dist[q - 1usize] > v {
                dist[q] = dist[q - 1usize]
                ids[q] = ids[q - 1usize]
                q -= 1usize
            }
            dist[q] = v
            ids[q] = j
            m += 1usize
        }
        j += 1usize
    }
}

// sNN(x, k)$shared for the c-th nearest neighbour j of row i: the common members of the two k-neighbour lists, plus one when i is in j's list;
// ids and dist are scratch of n, jids and jdist scratch of n
fn snn_shared(x: []const f64, n: usize, d: usize, k: usize, i: usize, c: usize, ids: []usize, dist: []f64, jids: []usize, jdist: []f64) -> f64 {
    knn_list(x, n, d, k, i, ids, dist)
    let j = ids[c]
    knn_list(x, n, d, k, j, jids, jdist)
    var common = 0usize
    var a = 0usize
    while a < k {
        var b = 0usize
        while b < k {
            if ids[a] == jids[b] { common += 1usize }
            b += 1usize
        }
        a += 1usize
    }
    var b = 0usize
    while b < k {
        if jids[b] == i { common += 1usize }
        b += 1usize
    }
    ret f64(common)
}

// frNN(x, eps): how many other rows lie within eps of `row`, and the sum of those distances through the second result
fn frnn_count(x: []const f64, n: usize, d: usize, row: usize, eps: f64) -> (usize, f64) {
    var cnt = 0usize
    var s = 0.0f64
    var j = 0usize
    while j < n {
        if j != row {
            let v = distance(x, d, row, j)
            if v <= eps {
                cnt += 1usize
                s += v
            }
        }
        j += 1usize
    }
    ret (cnt, s)
}

// sNNclust(x, k, eps, minPts) of dbscan (Jarvis-Patrick shared neighbours, borderPoints = TRUE): two rows are linked when each is among the other's k nearest and they
// share at least eps neighbours (the common members of the two lists, plus one for the other row itself); DBSCAN with min_points on those links (a row's own count plus one).
// labels receives a cluster index per row or NOISE; the cluster count is answered. ids is scratch of n * k, adj of n * n, near and queue of n, nd of n.
fn snn_links(x: []const f64, n: usize, d: usize, k: usize, eps: f64, ids: []usize, adj: []u8, near: []usize, nd: []f64) {
    var i = 0usize
    while i < n {
        knn_list(x, n, d, k, i, near, nd)
        var c = 0usize
        while c < k {
            ids[i * k + c] = near[c]
            c += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        adj[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < n {
        var a = 0usize
        while a < k {
            let j = ids[i * k + a]
            var mutual = false
            var common = 0usize
            var b = 0usize
            while b < k {
                if ids[j * k + b] == i { mutual = true }
                var c = 0usize
                while c < k {
                    if ids[i * k + c] == ids[j * k + b] { common += 1usize }
                    c += 1usize
                }
                b += 1usize
            }
            if mutual && f64(common + 1usize) >= eps { adj[i * n + j] = 1u8 }
            a += 1usize
        }
        i += 1usize
    }
}

fn snn_cluster(x: []const f64, n: usize, d: usize, k: usize, eps: f64, min_points: usize, labels: []usize, ids: []usize, adj: []u8, near: []usize, nd: []f64, queue: []usize) -> usize {
    snn_links(x, n, d, k, eps, ids, adj, near, nd)
    var i = 0usize
    let unvisited = NOISE - 1usize
    i = 0usize
    while i < n {
        labels[i] = unvisited
        i += 1usize
    }
    var clusters = 0usize
    i = 0usize
    while i < n {
        if labels[i] == unvisited {
            if adj_count(adj, n, i) + 1usize < min_points {
                labels[i] = NOISE
            } else {
                let cluster = clusters
                clusters += 1usize
                labels[i] = cluster
                var head = 0usize
                var tail = 1usize
                queue[0usize] = i
                while head < tail {
                    let p = queue[head]
                    head += 1usize
                    var j = 0usize
                    while j < n {
                        if adj[p * n + j] == 1u8 && (labels[j] == unvisited || labels[j] == NOISE) {
                            let was_unvisited = labels[j] == unvisited
                            labels[j] = cluster
                            if was_unvisited && adj_count(adj, n, j) + 1usize >= min_points {
                                queue[tail] = j
                                tail += 1usize
                            }
                        }
                        j += 1usize
                    }
                }
            }
        }
        i += 1usize
    }
    ret clusters
}

fn adj_count(adj: []const u8, n: usize, i: usize) -> usize {
    var c = 0usize
    var j = 0usize
    while j < n {
        if adj[i * n + j] == 1u8 { c += 1usize }
        j += 1usize
    }
    ret c
}

// jpclust(x, k, kt) of dbscan (Jarvis-Patrick): the same links as snn_cluster with kt as the threshold, every connected component a cluster (a row with no link is a cluster of its own), numbered by the first row
// each contains; labels receives the 0-based cluster per row and the count is answered. Scratch as snn_cluster.
fn jp_cluster(x: []const f64, n: usize, d: usize, k: usize, kt: usize, labels: []usize, ids: []usize, adj: []u8, near: []usize, nd: []f64, queue: []usize) -> usize {
    snn_links(x, n, d, k, f64(kt), ids, adj, near, nd)
    var i = 0usize
    while i < n {
        labels[i] = NOISE
        i += 1usize
    }
    var clusters = 0usize
    i = 0usize
    while i < n {
        if labels[i] == NOISE {
            labels[i] = clusters
            var head = 0usize
            var tail = 1usize
            queue[0usize] = i
            while head < tail {
                let p = queue[head]
                head += 1usize
                var j = 0usize
                while j < n {
                    if adj[p * n + j] == 1u8 && labels[j] == NOISE {
                        labels[j] = clusters
                        queue[tail] = j
                        tail += 1usize
                    }
                    j += 1usize
                }
            }
            clusters += 1usize
        }
        i += 1usize
    }
    ret clusters
}

// ---- extractXi of dbscan: the OPTICS xi method on the reachability plot ----

fn xi_rd(rd: []const f64, n: i64, i: i64) -> f64 {
    if i < 1i64 || i > n { ret 0.0f64 / 0.0f64 }
    ret rd[usize(i)]
}

fn xi_inf(v: f64) -> bool { ret v > 1.0e308f64 }

fn xi_valid(rd: []const f64, n: i64, i: i64) -> bool {
    let v = xi_rd(rd, n, i)
    ret v == v
}

fn xi_down(rd: []const f64, n: i64, i: i64, ixi: f64) -> bool {
    if !xi_valid(rd, n, i + 1i64) { ret false }
    if xi_inf(xi_rd(rd, n, i + 1i64)) { ret false }
    ret xi_rd(rd, n, i) * ixi >= xi_rd(rd, n, i + 1i64)
}

fn xi_up(rd: []const f64, n: i64, i: i64, ixi: f64) -> bool {
    if xi_inf(xi_rd(rd, n, i)) { ret false }
    if !xi_valid(rd, n, i + 1i64) { ret true }
    ret xi_rd(rd, n, i) <= xi_rd(rd, n, i + 1i64) * ixi
}

// the steep-down areas still able to start a cluster once mib is the largest value seen since them (updateFilterSDASet)
fn xi_filter(ss: []i64, se: []i64, smax: []f64, smib: []f64, ns: usize, mib: f64, ixi: f64) -> usize {
    var out = 0usize
    var i = 0usize
    while i < ns {
        if smax[i] * ixi > mib {
            ss[out] = ss[i]
            se[out] = se[i]
            smax[out] = smax[i]
            smib[out] = smib[i]
            if mib > smib[out] { smib[out] = mib }
            out += 1usize
        }
        i += 1usize
    }
    ret out
}

// extractXi(optics(x, eps, minPts), xi, minimum, correctPredecessors): order holds 0-based row indexes, reach the reachability per row (1e300 or more for Inf) and pred the predecessor
// per row (NOISE when there is none). labels receives 0 for noise and the 1-based cluster id otherwise (ids follow the clusters sorted by start and end); the cluster count is answered.
fn optics_xi(a: *mem.Arena, order: []const usize, reach: []const f64, pred: []const usize, n: usize, min_pts: usize, xi: f64, minimum: bool, correct: bool, labels: []usize) -> (usize, err) {
    if xi <= 0.0f64 || xi >= 1.0f64 || n == 0usize { ret (0usize, Invalid) }
    let nn = i64(n)
    let ixi = 1.0f64 - xi
    let inf = 1.0e308f64 * 10.0f64
    let mp = i64(min_pts)
    let (rd, e1) = mem.alloc[f64](a, n + 2usize)
    let (ss, e2) = mem.alloc[i64](a, n + 1usize)
    let (se, e3) = mem.alloc[i64](a, n + 1usize)
    let (smax, e4) = mem.alloc[f64](a, n + 1usize)
    let (smib, e5) = mem.alloc[f64](a, n + 1usize)
    let cap = 16usize * n + 16usize
    let (cs, e6) = mem.alloc[i64](a, cap)
    let (ce, e7) = mem.alloc[i64](a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        var v = reach[order[i]]
        if v >= 1.0e299f64 { v = inf }
        rd[i + 1usize] = v
        i += 1usize
    }
    var ns = 0usize
    var nc = 0usize
    var index = 1i64
    var mib = 0.0f64
    while index <= nn {
        let cur = xi_rd(rd, nn, index)
        if cur > mib { mib = cur }
        if !xi_valid(rd, nn, index + 1i64) { break }
        if xi_down(rd, nn, index, ixi) {
            ns = xi_filter(ss, se, smax, smib, ns, mib, ixi)
            let startval = xi_rd(rd, nn, index)
            mib = 0.0f64
            let startsteep = index
            var endsteep = index + 1i64
            while index + 1i64 <= nn {
                index += 1i64
                if xi_down(rd, nn, index, ixi) {
                    endsteep = index + 1i64
                    continue
                }
                if !xi_down(rd, nn, index, 1.0f64) || index - endsteep > mp { break }
            }
            ss[ns] = startsteep
            se[ns] = endsteep
            smax[ns] = startval
            smib[ns] = 0.0f64
            ns += 1usize
            continue
        }
        if xi_up(rd, nn, index, ixi) {
            ns = xi_filter(ss, se, smax, smib, ns, mib, ixi)
            let startsteep = index
            var endsteep = index + 1i64
            mib = xi_rd(rd, nn, index)
            var esuccr = inf
            if xi_valid(rd, nn, index + 1i64) { esuccr = xi_rd(rd, nn, index + 1i64) }
            if !xi_inf(esuccr) {
                while index + 1i64 <= nn {
                    index += 1i64
                    if xi_up(rd, nn, index, ixi) {
                        endsteep = index + 1i64
                        mib = xi_rd(rd, nn, index)
                        esuccr = inf
                        if xi_valid(rd, nn, index + 1i64) { esuccr = xi_rd(rd, nn, index + 1i64) }
                        if xi_inf(esuccr) {
                            endsteep -= 1i64
                            break
                        }
                        continue
                    }
                    if !xi_up(rd, nn, index, 1.0f64) || index - endsteep > mp { break }
                }
            } else {
                endsteep -= 1i64
                index += 1i64
            }
            var q = ns
            while q > 0usize {
                q -= 1usize
                if mib * ixi < smib[q] { continue }
                var cstart = ss[q]
                var cend = endsteep
                if correct {
                    while cend > cstart && xi_inf(xi_rd(rd, nn, cend)) { cend -= 1i64 }
                }
                if smax[q] * ixi >= esuccr {
                    while cstart < cend && xi_rd(rd, nn, cstart + 1i64) > esuccr { cstart += 1i64 }
                } else if esuccr * ixi >= smax[q] {
                    while cend > cstart && xi_rd(rd, nn, cend - 1i64) > smax[q] { cend -= 1i64 }
                }
                if correct {
                    while cend > cstart {
                        let t2 = pred[order[usize(cend - 1i64)]]
                        var found = false
                        if t2 != NOISE {
                            var p = cstart
                            while p <= cend - 1i64 {
                                if order[usize(p - 1i64)] == t2 { found = true }
                                p += 1i64
                            }
                        }
                        if found { break }
                        cend -= 1i64
                    }
                }
                if xi_up(rd, nn, index - 1i64, ixi) { cend -= 1i64 }
                if cend - cstart + 1i64 < mp { continue }
                if nc >= cap { ret (0usize, TooSmall) }
                cs[nc] = cstart
                ce[nc] = cend
                nc += 1usize
            }
        } else {
            index += 1i64
        }
    }
    i = 0usize
    while i < n {
        labels[i] = 0usize
        i += 1usize
    }
    if nc == 0usize { ret (0usize, ok) }
    // sort the clusters by start and end (stable), the id is the rank
    var k = 1usize
    while k < nc {
        let s0 = cs[k]
        let e0 = ce[k]
        var j = k
        while j > 0usize && (cs[j - 1usize] > s0 || (cs[j - 1usize] == s0 && ce[j - 1usize] > e0)) {
            cs[j] = cs[j - 1usize]
            ce[j] = ce[j - 1usize]
            j -= 1usize
        }
        cs[j] = s0
        ce[j] = e0
        k += 1usize
    }
    // paint them by decreasing size (increasing with minimum, painting only unpainted rows), ties by id
    let (perm, e8) = mem.alloc[usize](a, nc)
    let (pos, e9) = mem.alloc[usize](a, n + 2usize)
    if e8 != ok || e9 != ok { ret (0usize, TooSmall) }
    k = 0usize
    while k < nc {
        var j = k
        while j > 0usize {
            let sa = ce[perm[j - 1usize]] - cs[perm[j - 1usize]]
            let sb = ce[k] - cs[k]
            var swap = sa < sb
            if minimum { swap = sa > sb }
            if !swap { break }
            perm[j] = perm[j - 1usize]
            j -= 1usize
        }
        perm[j] = k
        k += 1usize
    }
    i = 0usize
    while i < n + 2usize {
        pos[i] = 0usize
        i += 1usize
    }
    k = 0usize
    while k < nc {
        let c = perm[k]
        var allzero = true
        var p = cs[c]
        while p <= ce[c] {
            if p >= 1i64 && p <= nn && pos[usize(p)] != 0usize { allzero = false }
            p += 1i64
        }
        if !minimum || allzero {
            p = cs[c]
            while p <= ce[c] {
                if p >= 1i64 && p <= nn { pos[usize(p)] = c + 1usize }
                p += 1i64
            }
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        labels[order[i]] = pos[i + 1usize]
        i += 1usize
    }
    ret (nc, ok)
}
