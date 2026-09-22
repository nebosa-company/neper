// Consistent hashing: a ring of virtual nodes, rendezvous (highest random
// weight) hashing, and Lamport's jump consistent hash.
//
// Nodes are `u64` identifiers and keys are `u64` hashes the caller has already
// computed (`e.algo.hash.xxhash64` over the key bytes is the usual source). The
// ring lives in caller storage: `replicas` points per node, sorted once by
// `ring_build`, looked up by binary search. Rendezvous needs no state and moves
// only the keys of a node that leaves; jump needs no state at all but numbers
// buckets `0..count`, so it suits buckets that only ever grow or shrink at the end.

type Point = struct { position: u64, node: u64 }
error TooSmall
error Invalid

fn mix(x: u64) -> u64 {
    var v = x ^ (x >> 33u64)
    v = v *% 18397679294719823053u64
    v = v ^ (v >> 33u64)
    v = v *% 14181476777654086739u64
    ret v ^ (v >> 33u64)
}

// The ring position of replica `replica` of `node`.
fn ring_position(node: u64, replica: u32) -> u64 { ret mix(node *% 11400714819323198485u64 +% u64(replica)) }

// Places `replicas` points per node and sorts them; `points.len >= nodes.len * replicas`.
// Answers the sorted points.
fn ring_build(points: []Point, nodes: []const u64, replicas: u32) -> ([]Point, err) {
    if replicas == 0u32 { ret (points[..0usize], Invalid) }
    let total = nodes.len * usize(replicas)
    if points.len < total { ret (points[..0usize], TooSmall) }
    var at = 0usize
    var n = 0usize
    while n < nodes.len {
        var r = 0u32
        while r < replicas {
            points[at] = Point { position: ring_position(nodes[n], r), node: nodes[n] }
            at += 1usize
            r += 1u32
        }
        n += 1usize
    }
    // Heapsort by position, ties by node so the order is a function of the set.
    var ring = points[..total]
    var start = total / 2usize
    while start > 0usize {
        start -= 1usize
        ring_sift(ring, start, total)
    }
    var end = total
    while end > 1usize {
        end -= 1usize
        let carried = ring[0usize]
        ring[0usize] = ring[end]
        ring[end] = carried
        ring_sift(ring, 0usize, end)
    }
    ret (ring, ok)
}

fn point_before(a: Point, b: Point) -> bool {
    if a.position != b.position { ret a.position < b.position }
    ret a.node < b.node
}

fn ring_sift(ring: []Point, at: usize, end: usize) {
    var here = at
    while true {
        let left = here * 2usize + 1usize
        if left >= end { break }
        var largest = left
        let right = left + 1usize
        if right < end && point_before(ring[left], ring[right]) { largest = right }
        if !point_before(ring[here], ring[largest]) { break }
        let carried = ring[here]
        ring[here] = ring[largest]
        ring[largest] = carried
        here = largest
    }
}

// The node owning `key`: the first point at or after the key's position,
// wrapping to the start of the ring.
fn ring_lookup(ring: []const Point, key: u64) -> (u64, bool) {
    if ring.len == 0usize { ret (0u64, false) }
    let position = mix(key)
    var low = 0usize
    var high = ring.len
    while low < high {
        let middle = low + (high - low) / 2usize
        if ring[middle].position < position { low = middle + 1usize } else { high = middle }
    }
    if low == ring.len { low = 0usize }
    ret (ring[low].node, true)
}

// The `count` distinct nodes after the owner, for replication; answers how many
// were written (fewer when the ring has fewer distinct nodes).
fn ring_successors(ring: []const Point, key: u64, out: []u64) -> usize {
    if ring.len == 0usize || out.len == 0usize { ret 0usize }
    let position = mix(key)
    var low = 0usize
    var high = ring.len
    while low < high {
        let middle = low + (high - low) / 2usize
        if ring[middle].position < position { low = middle + 1usize } else { high = middle }
    }
    var written = 0usize
    var steps = 0usize
    while steps < ring.len && written < out.len {
        let node = ring[(low + steps) % ring.len].node
        var seen = false
        var i = 0usize
        while i < written {
            if out[i] == node { seen = true }
            i += 1usize
        }
        if !seen {
            out[written] = node
            written += 1usize
        }
        steps += 1usize
    }
    ret written
}

// Rendezvous hashing: the index of the node with the highest weight for `key`.
fn rendezvous(nodes: []const u64, key: u64) -> (usize, bool) {
    if nodes.len == 0usize { ret (0usize, false) }
    var best = 0usize
    var best_weight = 0u64
    var i = 0usize
    while i < nodes.len {
        let weight = mix(nodes[i] ^ mix(key))
        if i == 0usize || weight > best_weight || (weight == best_weight && nodes[i] < nodes[best]) {
            best = i
            best_weight = weight
        }
        i += 1usize
    }
    ret (best, true)
}

// Jump consistent hash: a bucket in `0..buckets`, with only `1/buckets` of the
// keys moving when a bucket is added at the end. `buckets` must be positive.
fn jump(key: u64, buckets: u32) -> u32 {
    if buckets == 0u32 { ret 0u32 }
    var k = key
    var b = 0i64 - 1i64
    var j = 0i64
    while j < i64(buckets) {
        b = j
        k = k *% 2862933555777941757u64 +% 1u64
        // (b + 1) * (2^31 / ((k >> 33) + 1)), in floating point as the paper writes it.
        j = i64(f64(b + 1i64) * (2147483648.0f64 / f64((k >> 33u64) + 1u64)))
    }
    ret u32(b)
}

// The planned name for placing virtual nodes: `k` points per node, or
// `k * weights[i]` when `weights` is given (empty means uniform), sorted into
// a ring; `points.len` must hold them all.
fn virtual_nodes(points: []Point, nodes: []const u64, k: u32, weights: []const u32) -> ([]Point, err) {
    if k == 0u32 { ret (points[..0usize], Invalid) }
    if weights.len == 0usize {
        let (ring, ring_error) = ring_build(points, nodes, k)
        ret (ring, ring_error)
    }
    if weights.len < nodes.len { ret (points[..0usize], TooSmall) }
    var total = 0usize
    var n = 0usize
    while n < nodes.len {
        total += usize(k) * usize(weights[n])
        n += 1usize
    }
    if points.len < total { ret (points[..0usize], TooSmall) }
    var at = 0usize
    n = 0usize
    while n < nodes.len {
        var r = 0u32
        let replicas = k * weights[n]
        while r < replicas {
            points[at] = Point { position: ring_position(nodes[n], r), node: nodes[n] }
            at += 1usize
            r += 1u32
        }
        n += 1usize
    }
    var ring = points[..total]
    var start = total / 2usize
    while start > 0usize {
        start -= 1usize
        ring_sift(ring, start, total)
    }
    var end = total
    while end > 1usize {
        end -= 1usize
        let carried = ring[0usize]
        ring[0usize] = ring[end]
        ring[end] = carried
        ring_sift(ring, 0usize, end)
    }
    ret (ring, ok)
}

// The balance check: how many of `keys` each of `nodes` owns, into `counts`
// (`counts.len >= nodes.len`); a key owned by a node outside `nodes` is `Invalid`.
fn virtual_nodes_load(ring: []const Point, keys: []const u64, nodes: []const u64, counts: []usize) -> err {
    if counts.len < nodes.len { ret TooSmall }
    var n = 0usize
    while n < nodes.len {
        counts[n] = 0usize
        n += 1usize
    }
    var i = 0usize
    while i < keys.len {
        let (owner, found) = ring_lookup(ring, keys[i])
        if !found { ret Invalid }
        var hit = false
        n = 0usize
        while n < nodes.len {
            if nodes[n] == owner && !hit {
                counts[n] += 1usize
                hit = true
            }
            n += 1usize
        }
        if !hit { ret Invalid }
        i += 1usize
    }
    ret ok
}
