// k-nearest neighbours over row-major `f64` samples by a full Euclidean
// scan in caller storage: `neighbors` answers the `k` nearest indices and
// distances of a query, `classify` the majority label among them (ties to
// the smallest label) and `regress` the mean of their targets.

use e.math

error TooSmall
error Invalid

// The `k` nearest samples to `query`, closest first, into `indices` and
// `distances` (`k` each); `k <= n`.
fn neighbors(x: []const f64, n: usize, d: usize, query: []const f64, k: usize, indices: []usize, distances: []f64) -> err {
    if k == 0usize || k > n { ret Invalid }
    if x.len < n * d || query.len < d || indices.len < k || distances.len < k { ret TooSmall }
    var count = 0usize
    var i = 0usize
    while i < n {
        var sum = 0.0f64
        var j = 0usize
        while j < d {
            let t = x[i * d + j] - query[j]
            sum += t * t
            j += 1usize
        }
        let dist = math.sqrt[f64](sum)
        if count < k || dist < distances[k - 1usize] {
            // Insert into the sorted prefix, dropping the last when full.
            var at = count
            if count == k { at = k - 1usize }
            while at > 0usize && distances[at - 1usize] > dist {
                distances[at] = distances[at - 1usize]
                indices[at] = indices[at - 1usize]
                at -= 1usize
            }
            distances[at] = dist
            indices[at] = i
            if count < k { count += 1usize }
        }
        i += 1usize
    }
    ret ok
}

// The majority label (in `0..classes`) among the `k` nearest; `scratch.len >= 2 * k + classes`
// indices and `distances.len >= k`.
fn classify(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, query: []const f64, k: usize, scratch: []usize, distances: []f64) -> (usize, err) {
    if labels.len < n || scratch.len < k + classes { ret (0usize, TooSmall) }
    if classes == 0usize { ret (0usize, Invalid) }
    var indices = scratch[..k]
    var votes = scratch[k..k + classes]
    let find_error = neighbors(x, n, d, query, k, indices, distances)
    if find_error != ok { ret (0usize, find_error) }
    var c = 0usize
    while c < classes {
        votes[c] = 0usize
        c += 1usize
    }
    var i = 0usize
    while i < k {
        if labels[indices[i]] >= classes { ret (0usize, Invalid) }
        votes[labels[indices[i]]] += 1usize
        i += 1usize
    }
    var best = 0usize
    c = 1usize
    while c < classes {
        if votes[c] > votes[best] { best = c }
        c += 1usize
    }
    ret (best, ok)
}

// The mean target of the `k` nearest; `indices.len >= k`, `distances.len >= k`.
fn regress(x: []const f64, y: []const f64, n: usize, d: usize, query: []const f64, k: usize, indices: []usize, distances: []f64) -> (f64, err) {
    if y.len < n { ret (0.0f64, TooSmall) }
    let find_error = neighbors(x, n, d, query, k, indices, distances)
    if find_error != ok { ret (0.0f64, find_error) }
    var sum = 0.0f64
    var i = 0usize
    while i < k {
        sum += y[indices[i]]
        i += 1usize
    }
    ret (sum / f64(k), ok)
}
