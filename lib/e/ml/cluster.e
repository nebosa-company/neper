// Clustering of row-major `f64` samples (`n` rows of `d` features) in
// caller storage: k-means (Lloyd's iterations from caller centroids,
// `kmeans_pp_init` seeding them, `kmeans_online` updating them one sample
// at a time for a stream, `vector_quantize` growing them by LBG splitting),
// k-medoids (PAM swaps), agglomerative clustering under single, complete or
// average linkage, and neighbour joining over a distance matrix. Labels are
// cluster indices per sample.

use e.algo.rand
use e.math

type Linkage = enum u8 { Single, Complete, Average }
error TooSmall
error Invalid

fn distance_squared(x: []const f64, d: usize, i: usize, y: []const f64, j: usize) -> f64 {
    var sum = 0.0f64
    var k = 0usize
    while k < d {
        let t = x[i * d + k] - y[j * d + k]
        sum += t * t
        k += 1usize
    }
    ret sum
}

// The nearest of `k` centroids to sample `i`, and its squared distance.
fn nearest(x: []const f64, d: usize, i: usize, centroids: []const f64, k: usize) -> (usize, f64) {
    var best = 0usize
    var best_distance = distance_squared(x, d, i, centroids, 0usize)
    var c = 1usize
    while c < k {
        let dist = distance_squared(x, d, i, centroids, c)
        if dist < best_distance {
            best = c
            best_distance = dist
        }
        c += 1usize
    }
    ret (best, best_distance)
}

// Lloyd's iterations from the caller's `centroids` (`k × d`) until no label
// changes or `max_iterations`; `labels` receives the assignment and the
// centroids are updated in place (an emptied cluster keeps its centroid).
// `scratch.len >= k`. Answers the iterations taken.
fn kmeans(x: []const f64, n: usize, d: usize, k: usize, centroids: []f64, labels: []usize, max_iterations: u32, scratch: []usize) -> (u32, err) {
    if x.len < n * d || centroids.len < k * d || labels.len < n || scratch.len < k { ret (0u32, TooSmall) }
    if k == 0usize || n == 0usize { ret (0u32, Invalid) }
    var counts = scratch[..k]
    var i = 0usize
    while i < n {
        labels[i] = k
        i += 1usize
    }
    var iteration = 0u32
    var changed = true
    while iteration < max_iterations && changed {
        changed = false
        i = 0usize
        while i < n {
            let (c, _) = nearest(x, d, i, centroids, k)
            if c != labels[i] {
                labels[i] = c
                changed = true
            }
            i += 1usize
        }
        iteration += 1u32
        if changed {
            var c = 0usize
            while c < k {
                counts[c] = 0usize
                c += 1usize
            }
            i = 0usize
            while i < n {
                counts[labels[i]] += 1usize
                i += 1usize
            }
            c = 0usize
            while c < k {
                if counts[c] > 0usize {
                    var j = 0usize
                    while j < d {
                        centroids[c * d + j] = 0.0f64
                        j += 1usize
                    }
                }
                c += 1usize
            }
            i = 0usize
            while i < n {
                let c2 = labels[i]
                var j = 0usize
                while j < d {
                    centroids[c2 * d + j] += x[i * d + j] / f64(counts[c2])
                    j += 1usize
                }
                i += 1usize
            }
        }
    }
    ret (iteration, ok)
}

// k-means++ seeding: the first centroid uniformly, each next one with
// probability proportional to its squared distance from the nearest chosen;
// `scratch.len >= n`.
fn kmeans_pp_init(x: []const f64, n: usize, d: usize, k: usize, r: *rand.Pcg64, centroids: []f64, scratch: []f64) -> err {
    if x.len < n * d || centroids.len < k * d || scratch.len < n { ret TooSmall }
    if k == 0usize || n == 0usize { ret Invalid }
    var weights = scratch[..n]
    var first = usize(rand.pcg64_bounded(r, u64(n)))
    var j = 0usize
    while j < d {
        centroids[j] = x[first * d + j]
        j += 1usize
    }
    var c = 1usize
    while c < k {
        var total = 0.0f64
        var i = 0usize
        while i < n {
            let (_, dist) = nearest(x, d, i, centroids, c)
            weights[i] = dist
            total += dist
            i += 1usize
        }
        var pick = n - 1usize
        if total > 0.0f64 {
            var u = rand.pcg64_f64(r) * total
            i = 0usize
            var searching = true
            while i < n && searching {
                u -= weights[i]
                if u <= 0.0f64 {
                    pick = i
                    searching = false
                }
                i += 1usize
            }
        } else {
            pick = usize(rand.pcg64_bounded(r, u64(n)))
        }
        j = 0usize
        while j < d {
            centroids[c * d + j] = x[pick * d + j]
            j += 1usize
        }
        c += 1usize
    }
    ret ok
}

// One sample of a stream: it joins the nearest centroid, which moves toward
// it by `1 / count` (its `counts` entry, incremented). Answers the cluster.
fn kmeans_online(sample: []const f64, d: usize, k: usize, centroids: []f64, counts: []usize) -> (usize, err) {
    if sample.len < d || centroids.len < k * d || counts.len < k { ret (0usize, TooSmall) }
    if k == 0usize { ret (0usize, Invalid) }
    let (c, _) = nearest(sample, d, 0usize, centroids, k)
    counts[c] += 1usize
    let rate = 1.0f64 / f64(counts[c])
    var j = 0usize
    while j < d {
        centroids[c * d + j] += rate * (sample[j] - centroids[c * d + j])
        j += 1usize
    }
    ret (c, ok)
}

// Linde-Buzo-Gray: from the mean, every centroid splits into `± epsilon`
// copies and k-means runs, until `k` (a power of two) centroids exist;
// `scratch.len >= k` indices. Answers the final k-means iterations.
fn vector_quantize(x: []const f64, n: usize, d: usize, k: usize, epsilon: f64, centroids: []f64, labels: []usize, max_iterations: u32, scratch: []usize) -> (u32, err) {
    if x.len < n * d || centroids.len < k * d || labels.len < n || scratch.len < k { ret (0u32, TooSmall) }
    if k == 0usize || n == 0usize || (k & (k - 1usize)) != 0usize { ret (0u32, Invalid) }
    var j = 0usize
    while j < d {
        centroids[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        j = 0usize
        while j < d {
            centroids[j] += x[i * d + j] / f64(n)
            j += 1usize
        }
        i += 1usize
    }
    var have = 1usize
    var iterations = 0u32
    while have < k {
        var c = 0usize
        while c < have {
            j = 0usize
            while j < d {
                let v = centroids[c * d + j]
                centroids[(have + c) * d + j] = v * (1.0f64 + epsilon)
                centroids[c * d + j] = v * (1.0f64 - epsilon)
                j += 1usize
            }
            c += 1usize
        }
        have *= 2usize
        let (took, run_error) = kmeans(x, n, d, have, centroids, labels, max_iterations, scratch)
        if run_error != ok { ret (0u32, run_error) }
        iterations = took
    }
    if k == 1usize {
        i = 0usize
        while i < n {
            labels[i] = 0usize
            i += 1usize
        }
    }
    ret (iterations, ok)
}

// Total cost of a medoid set: every sample's distance to its nearest medoid.
fn medoid_cost(x: []const f64, n: usize, d: usize, medoids: []const usize, k: usize) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < n {
        var best = 0.0f64
        var m = 0usize
        while m < k {
            let dist = math.sqrt[f64](distance_squared(x, d, i, x, medoids[m]))
            if m == 0usize || dist < best { best = dist }
            m += 1usize
        }
        total += best
        i += 1usize
    }
    ret total
}

// Partitioning around medoids from the caller's `medoids` (sample indices):
// each round the single swap of a medoid with a non-medoid that lowers the
// total distance most is taken, until none does or `max_iterations`;
// `labels` receives the nearest medoid's index. Answers the rounds taken.
fn kmedoids(x: []const f64, n: usize, d: usize, k: usize, medoids: []usize, labels: []usize, max_iterations: u32) -> (u32, err) {
    if x.len < n * d || medoids.len < k || labels.len < n { ret (0u32, TooSmall) }
    if k == 0usize || n == 0usize { ret (0u32, Invalid) }
    var cost = medoid_cost(x, n, d, medoids, k)
    var iteration = 0u32
    var improved = true
    while iteration < max_iterations && improved {
        improved = false
        var best_m = k
        var best_i = n
        var best_cost = cost
        var m = 0usize
        while m < k {
            let old = medoids[m]
            var i = 0usize
            while i < n {
                var is_medoid = false
                var q = 0usize
                while q < k {
                    if medoids[q] == i { is_medoid = true }
                    q += 1usize
                }
                if !is_medoid {
                    medoids[m] = i
                    let trial = medoid_cost(x, n, d, medoids, k)
                    if trial < best_cost {
                        best_cost = trial
                        best_m = m
                        best_i = i
                    }
                    medoids[m] = old
                }
                i += 1usize
            }
            m += 1usize
        }
        if best_m < k {
            medoids[best_m] = best_i
            cost = best_cost
            improved = true
            iteration += 1u32
        }
    }
    var i = 0usize
    while i < n {
        var best = 0usize
        var best_distance = 0.0f64
        var m = 0usize
        while m < k {
            let dist = distance_squared(x, d, i, x, medoids[m])
            if m == 0usize || dist < best_distance {
                best = m
                best_distance = dist
            }
            m += 1usize
        }
        labels[i] = best
        i += 1usize
    }
    ret (iteration, ok)
}

// Agglomerative clustering: every sample its own cluster, the closest pair
// merged under `linkage` until `k` remain; `labels` receives cluster
// indices `0..k`. `distances.len >= n * n` holds the working matrix.
fn agglomerative(x: []const f64, n: usize, d: usize, linkage: Linkage, k: usize, labels: []usize, distances: []f64) -> err {
    if x.len < n * d || labels.len < n || distances.len < n * n { ret TooSmall }
    if k == 0usize || k > n { ret Invalid }
    // Cluster c is alive while labels[c] == c (it holds its members' label); the
    // matrix entry (a, b) is the linkage distance between live clusters.
    var i = 0usize
    while i < n {
        labels[i] = i
        var j = 0usize
        while j < n {
            distances[i * n + j] = math.sqrt[f64](distance_squared(x, d, i, x, j))
            j += 1usize
        }
        i += 1usize
    }
    var alive = n
    while alive > k {
        var a = n
        var b = n
        var best = 0.0f64
        i = 0usize
        while i < n {
            if labels[i] == i {
                var j = i + 1usize
                while j < n {
                    if labels[j] == j && (a == n || distances[i * n + j] < best) {
                        a = i
                        b = j
                        best = distances[i * n + j]
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        // Merge b into a: members relabel, distances combine by linkage.
        var size_a = 0usize
        var size_b = 0usize
        i = 0usize
        while i < n {
            if labels[i] == a { size_a += 1usize }
            if labels[i] == b { size_b += 1usize }
            i += 1usize
        }
        i = 0usize
        while i < n {
            if labels[i] == b { labels[i] = a }
            i += 1usize
        }
        var c = 0usize
        while c < n {
            if labels[c] == c && c != a {
                var combined = 0.0f64
                let da = distances[a * n + c]
                let db = distances[b * n + c]
                if linkage == .Single {
                    combined = math.min[f64](da, db)
                } else if linkage == .Complete {
                    combined = math.max[f64](da, db)
                } else {
                    combined = (da * f64(size_a) + db * f64(size_b)) / f64(size_a + size_b)
                }
                distances[a * n + c] = combined
                distances[c * n + a] = combined
            }
            c += 1usize
        }
        alive -= 1usize
    }
    // Compact the cluster ids to 0..k in order of first appearance.
    // A representative is the smallest index of its cluster, so its members follow it.
    var next = 0usize
    i = 0usize
    while i < n {
        if labels[i] == i {
            var j = i
            while j < n {
                if labels[j] == i { labels[j] = n + next }
                j += 1usize
            }
            next += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        labels[i] -= n
        i += 1usize
    }
    ret ok
}

// Neighbour joining over the `n × n` distance matrix `distance` (copied
// into `work`, `work.len >= n * n`): `joins` receives `(a, b, parent)` per
// step as node ids (leaves `0..n`, new nodes from `n`) and `lengths` the
// two branch lengths; `n - 1` steps, the last joining the final pair.
// `scratch.len >= 3 * n`.
fn neighbor_joining(distance: []const f64, n: usize, work: []f64, joins: []usize, lengths: []f64, scratch: []usize) -> (usize, err) {
    if n < 2usize { ret (0usize, Invalid) }
    if distance.len < n * n || work.len < n * n || joins.len < 3usize * (n - 1usize) || lengths.len < 2usize * (n - 1usize) || scratch.len < 3usize * n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n * n {
        work[i] = distance[i]
        i += 1usize
    }
    // Live rows map to node ids; a row that dies is marked with id n * 2.
    var ids = scratch[..n]
    i = 0usize
    while i < n {
        ids[i] = i
        i += 1usize
    }
    let dead = 2usize * n
    var alive = n
    var next_id = n
    var steps = 0usize
    while alive > 2usize {
        // Row sums and the Q matrix minimum.
        var a = n
        var b = n
        var best = 0.0f64
        i = 0usize
        while i < n {
            if ids[i] != dead {
                var j = i + 1usize
                while j < n {
                    if ids[j] != dead {
                        let q = f64(alive - 2usize) * work[i * n + j] - row_sum(work, n, ids, dead, i) - row_sum(work, n, ids, dead, j)
                        if a == n || q < best {
                            a = i
                            b = j
                            best = q
                        }
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        let dab = work[a * n + b]
        var la = 0.5f64 * dab + (row_sum(work, n, ids, dead, a) - row_sum(work, n, ids, dead, b)) / (2.0f64 * f64(alive - 2usize))
        let lb = dab - la
        joins[3usize * steps] = ids[a]
        joins[3usize * steps + 1usize] = ids[b]
        joins[3usize * steps + 2usize] = next_id
        lengths[2usize * steps] = la
        lengths[2usize * steps + 1usize] = lb
        // Row a becomes the new node; row b dies.
        i = 0usize
        while i < n {
            if ids[i] != dead && i != a && i != b {
                let v = 0.5f64 * (work[a * n + i] + work[b * n + i] - dab)
                work[a * n + i] = v
                work[i * n + a] = v
            }
            i += 1usize
        }
        work[a * n + a] = 0.0f64
        ids[a] = next_id
        ids[b] = dead
        next_id += 1usize
        alive -= 1usize
        steps += 1usize
    }
    // The last two.
    var p = n
    var q = n
    i = 0usize
    while i < n {
        if ids[i] != dead {
            if p == n { p = i } else { q = i }
        }
        i += 1usize
    }
    joins[3usize * steps] = ids[p]
    joins[3usize * steps + 1usize] = ids[q]
    joins[3usize * steps + 2usize] = next_id
    lengths[2usize * steps] = 0.5f64 * work[p * n + q]
    lengths[2usize * steps + 1usize] = 0.5f64 * work[p * n + q]
    steps += 1usize
    ret (steps, ok)
}

fn row_sum(work: []const f64, n: usize, ids: []const usize, dead: usize, i: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < n {
        if ids[j] != dead { s += work[i * n + j] }
        j += 1usize
    }
    ret s
}

// A Gaussian mixture with diagonal covariances by expectation-maximisation
// from the caller's `means` (`k × d`), `variances` (`k × d`) and `weights`
// (`k`), until the log-likelihood improves by less than `tolerance` or
// `max_iterations`; `responsibilities` (`n × k`) receives the posterior of
// each sample. Answers the log-likelihood and the iterations.
fn gmm_em(x: []const f64, n: usize, d: usize, k: usize, means: []f64, variances: []f64, weights: []f64, responsibilities: []f64, tolerance: f64, max_iterations: u32) -> (f64, u32, err) {
    if x.len < n * d || means.len < k * d || variances.len < k * d || weights.len < k || responsibilities.len < n * k { ret (0.0f64, 0u32, TooSmall) }
    if k == 0usize || n == 0usize { ret (0.0f64, 0u32, Invalid) }
    let floor = 1.0e-6f64
    var previous = 0.0f64
    var log_likelihood = 0.0f64
    var iteration = 0u32
    var converged = false
    while iteration < max_iterations && !converged {
        // E step: responsibilities from the log densities, normalised per sample.
        log_likelihood = 0.0f64
        var i = 0usize
        while i < n {
            var largest = 0.0f64
            var c = 0usize
            while c < k {
                var log_density = math.log[f64](weights[c])
                var j = 0usize
                while j < d {
                    let v = math.max[f64](variances[c * d + j], floor)
                    let t = x[i * d + j] - means[c * d + j]
                    log_density -= 0.5f64 * (math.log[f64](6.283185307179586f64 * v) + t * t / v)
                    j += 1usize
                }
                responsibilities[i * k + c] = log_density
                if c == 0usize || log_density > largest { largest = log_density }
                c += 1usize
            }
            var total = 0.0f64
            c = 0usize
            while c < k {
                responsibilities[i * k + c] = math.exp[f64](responsibilities[i * k + c] - largest)
                total += responsibilities[i * k + c]
                c += 1usize
            }
            c = 0usize
            while c < k {
                responsibilities[i * k + c] = responsibilities[i * k + c] / total
                c += 1usize
            }
            log_likelihood += largest + math.log[f64](total)
            i += 1usize
        }
        // M step.
        var c = 0usize
        while c < k {
            var mass = 0.0f64
            i = 0usize
            while i < n {
                mass += responsibilities[i * k + c]
                i += 1usize
            }
            weights[c] = mass / f64(n)
            if mass > 0.0f64 {
                var j = 0usize
                while j < d {
                    var mean = 0.0f64
                    i = 0usize
                    while i < n {
                        mean += responsibilities[i * k + c] * x[i * d + j]
                        i += 1usize
                    }
                    mean = mean / mass
                    var variance = 0.0f64
                    i = 0usize
                    while i < n {
                        let t = x[i * d + j] - mean
                        variance += responsibilities[i * k + c] * t * t
                        i += 1usize
                    }
                    means[c * d + j] = mean
                    variances[c * d + j] = math.max[f64](variance / mass, floor)
                    j += 1usize
                }
            }
            c += 1usize
        }
        iteration += 1u32
        if iteration > 1u32 && math.abs[f64](log_likelihood - previous) < tolerance { converged = true }
        previous = log_likelihood
    }
    ret (log_likelihood, iteration, ok)
}
