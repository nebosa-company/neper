// Density clustering of row-major `f64` samples in caller storage: DBSCAN
// (core points have at least `min_points` neighbours within `eps`, their
// clusters grow through core neighbours, the rest is noise) and OPTICS (the
// same neighbourhoods produce an ordering and a reachability distance per
// sample, from which clusters at any `eps` can be read). Neighbourhoods are
// found by a full scan, so both are quadratic.

use e.math

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
