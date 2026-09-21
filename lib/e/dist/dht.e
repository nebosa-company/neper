// Distributed hash tables simulated over an in-memory node set: `nodes` is a
// caller `[]const u64` of distinct ids below `2^bits` and every answer is an
// index into it. Chord (`chord_finger_tables`, `chord_lookup`) needs the ids
// sorted: the owner of a key is its successor on the ring, finger k of node
// i is the successor of `id + 2^k`, and a lookup forwards to the closest
// preceding finger until the key falls in (node, successor], counting hops.
// Kademlia (`kademlia_bucket`, `kademlia_buckets`, `kademlia_lookup`) uses
// XOR distance: node i's k-bucket b holds the first `k` nodes (in index
// order) whose distance from i lies in [2^b, 2^(b+1)), and a lookup for a
// target queries `alpha` unqueried nodes among the k closest it knows each
// round, learning each one's k closest, until the k closest are all queried.

error TooSmall
error Invalid

// Is x in the open ring interval (a, b)?
fn between(x: u64, a: u64, b: u64) -> bool {
    if a < b { ret a < x && x < b }
    if a > b { ret x > a || x < b }
    ret x != a
}

// Is x in the half-open ring interval (a, b]?
fn between_closed(x: u64, a: u64, b: u64) -> bool {
    if a < b { ret a < x && x <= b }
    if a > b { ret x > a || x <= b }
    ret true
}

// The index of the first node whose id is at least `key`, wrapping to 0.
fn chord_successor(nodes: []const u64, key: u64) -> usize {
    var i = 0usize
    while i < nodes.len {
        if nodes[i] >= key { ret i }
        i += 1usize
    }
    ret 0usize
}

// Fill `fingers[i * bits + k]` with the successor of `nodes[i] + 2^k`;
// Invalid unless `nodes` is sorted, non-empty and `fingers` holds them all.
fn chord_finger_tables(nodes: []const u64, bits: u32, fingers: []u32) -> err {
    if nodes.len == 0usize || bits == 0u32 || bits >= 64u32 || fingers.len < nodes.len * usize(bits) { ret Invalid }
    let ring = 1u64 << bits
    var i = 0usize
    while i < nodes.len {
        if nodes[i] >= ring || (i > 0usize && nodes[i] <= nodes[i - 1usize]) { ret Invalid }
        var k = 0u32
        while k < bits {
            fingers[i * usize(bits) + usize(k)] = u32(chord_successor(nodes, (nodes[i] + (1u64 << k)) & (ring - 1u64)))
            k += 1u32
        }
        i += 1usize
    }
    ret ok
}

// Answers (owner index, hops) for `key` starting at node `start`.
fn chord_lookup(nodes: []const u64, bits: u32, fingers: []const u32, start: usize, key: u64) -> (usize, usize) {
    var n = start
    var hops = 0usize
    while true {
        let succ = (n + 1usize) % nodes.len
        if between_closed(key, nodes[n], nodes[succ]) { ret (succ, hops) }
        var next_node = n
        var k = bits
        while k > 0u32 && next_node == n {
            k -= 1u32
            let f = usize(fingers[n * usize(bits) + usize(k)])
            if between(nodes[f], nodes[n], key) { next_node = f }
        }
        if next_node == n { ret (succ, hops) }
        n = next_node
        hops += 1usize
    }
    ret (n, hops)
}

// The k-bucket index of `other` seen from `self`: floor(log2(xor distance)).
fn kademlia_bucket(self_id: u64, other: u64) -> u32 {
    var d = self_id ^ other
    var b = 0u32
    while d > 1u64 {
        d >>= 1u32
        b += 1u32
    }
    ret b
}

// Count the nodes in each of node `self`'s buckets into `counts` (one per bit).
fn kademlia_buckets(nodes: []const u64, self: usize, counts: []usize) -> err {
    var b = 0usize
    while b < counts.len {
        counts[b] = 0usize
        b += 1usize
    }
    var j = 0usize
    while j < nodes.len {
        if j != self {
            let at = usize(kademlia_bucket(nodes[self], nodes[j]))
            if at >= counts.len { ret TooSmall }
            counts[at] += 1usize
        }
        j += 1usize
    }
    ret ok
}

// Does node `i`'s table hold node `j`? The first `k` of a bucket in index order do.
fn knows(nodes: []const u64, i: usize, j: usize, k: usize) -> bool {
    if i == j { ret false }
    let b = kademlia_bucket(nodes[i], nodes[j])
    var seen = 0usize
    var m = 0usize
    while m < j {
        if m != i && kademlia_bucket(nodes[i], nodes[m]) == b { seen += 1usize }
        m += 1usize
    }
    ret seen < k
}

// Answers (how many of the k closest were found, rounds); `out` receives
// them by rising distance and `scratch` holds `2 * nodes.len + k` entries
// (Invalid otherwise). `scratch[..nodes.len]` is used as per-node state.
// ponytail: routing tables are recomputed from the id list on every query (O(n^2) per query); materialise them when n grows past a few hundred.
fn kademlia_lookup(nodes: []const u64, start: usize, goal: u64, k: usize, alpha: usize, out: []usize, scratch: []usize) -> (usize, usize, err) {
    let n = nodes.len
    if start >= n || k == 0usize || alpha == 0usize || out.len < k || scratch.len < 2usize * n + k { ret (0usize, 0usize, Invalid) }
    // scratch[..n]: 0 unknown, 1 known, 2 queried (kept as usize to share the slice).
    let state = scratch[..n]
    let peer = scratch[n..2usize * n]
    let learned = scratch[2usize * n..2usize * n + k]
    var j = 0usize
    while j < n {
        state[j] = 0usize
        if knows(nodes, start, j, k) { state[j] = 1usize }
        j += 1usize
    }
    var rounds = 0usize
    var again = true
    while again {
        again = false
        j = 0usize
        while j < n {
            peer[j] = 0usize
            if state[j] != 0usize { peer[j] = 1usize }
            j += 1usize
        }
        let found = closest_u(nodes, goal, peer, k, out)
        var asked = 0usize
        var c = 0usize
        while c < found && asked < alpha {
            let q = out[c]
            if state[q] == 1usize {
                state[q] = 2usize
                asked += 1usize
                // q answers with the k closest it knows.
                var m = 0usize
                while m < n {
                    peer[m] = 0usize
                    if knows(nodes, q, m, k) { peer[m] = 1usize }
                    m += 1usize
                }
                let got = closest_u(nodes, goal, peer, k, learned)
                m = 0usize
                while m < got {
                    if state[learned[m]] == 0usize { state[learned[m]] = 1usize }
                    m += 1usize
                }
            }
            c += 1usize
        }
        if asked > 0usize {
            rounds += 1usize
            again = true
        }
    }
    j = 0usize
    while j < n {
        peer[j] = 0usize
        if state[j] != 0usize { peer[j] = 1usize }
        j += 1usize
    }
    let count = closest_u(nodes, goal, peer, k, out)
    ret (count, rounds, ok)
}

// The `k` closest to `goal` among the nodes with `state[j] != 0`, into
// `out` by rising distance (ties by index); answers how many.
fn closest_u(nodes: []const u64, goal: u64, state: []const usize, k: usize, out: []usize) -> usize {
    var n = 0usize
    var j = 0usize
    while j < nodes.len {
        if state[j] != 0usize {
            let d = nodes[j] ^ goal
            var at = n
            while at > 0usize && (nodes[out[at - 1usize]] ^ goal) > d {
                if at < k { out[at] = out[at - 1usize] }
                at -= 1usize
            }
            if at < k { out[at] = j }
            if n < k { n += 1usize }
        }
        j += 1usize
    }
    ret n
}
