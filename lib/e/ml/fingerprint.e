// Chemical similarity over small labelled graphs in caller storage: circular
// (Morgan) and path fingerprints folded into caller-sized bit vectors,
// Tanimoto, Dice and bit-distance scoring, Taylor-Butina clustering, and a
// bounded maximum-common-substructure search (McGregor branch and bound).
//
// A molecule is `atoms` (`n` type ids) with bonds `src[k] -> dst[k]` of
// `order[k]` (`m` of them, undirected: either direction reads the same
// bond). Fingerprint bits depend on the bond order given, so two bond
// orderings of one graph may set different bits; canonicalization is out of
// scope. `fmcs` answers the common edge count of the largest connected
// edge-induced common subgraph; single atoms never match, and a `budget`
// of zero answers zero at once.

use e.math

error TooSmall
error Invalid

type Graph = struct { atoms: []const u32, n: usize, src: []const usize, dst: []const usize, order: []const u8, m: usize }

fn splitmix64(state: u64) -> u64 {
    var z = state +% 11400714819323198485u64
    z = (z ^ (z >> 30u64)) *% 13787848793156543929u64
    z = (z ^ (z >> 27u64)) *% 10723151780598845931u64
    ret z ^ (z >> 31u64)
}

fn mix(h: u64, x: u64) -> u64 { ret splitmix64(h +% (x *% 11400714819323198485u64)) }

// Circular fingerprints of `radius` around every atom: the initial
// identifier mixes the atom type with its degree, each round folds the
// incident `(order, neighbour identifier)` pairs by summation (order-free),
// and every level's identifiers set one bit each in `bits`.
// `scratch.len >= 2 * n` holds two identifier generations.
fn morgan_fingerprint(atoms: []const u32, n: usize, src: []const usize, dst: []const usize, order: []const u8, m: usize, radius: u32, bits: []u8, scratch: []u64) -> err {
    if atoms.len < n || src.len < m || dst.len < m || order.len < m || bits.len < 1usize || scratch.len < 2usize * n { ret TooSmall }
    if n == 0usize { ret Invalid }
    if bad_endpoints(src, dst, m, n) { ret Invalid }
    var inv = scratch[..n]
    var next = scratch[n..2usize * n]
    var i = 0usize
    while i < bits.len {
        bits[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < n {
        var degree = 0u64
        var k = 0usize
        while k < m {
            if src[k] == i || dst[k] == i { degree += 1u64 }
            k += 1usize
        }
        inv[i] = mix(u64(atoms[i]), degree)
        i += 1usize
    }
    collect_bits(inv, n, bits)
    var r = 0u32
    while r < radius {
        i = 0usize
        while i < n {
            var acc = inv[i]
            var k = 0usize
            while k < m {
                if src[k] == i {
                    acc = mix(mix(acc, u64(order[k])), inv[dst[k]])
                } else if dst[k] == i {
                    acc = mix(mix(acc, u64(order[k])), inv[src[k]])
                }
                k += 1usize
            }
            next[i] = acc
            i += 1usize
        }
        let swap = inv
        inv = next
        next = swap
        collect_bits(inv, n, bits)
        r += 1u32
    }
    ret ok
}

// True when some bond touches no atom.
fn bad_endpoints(src: []const usize, dst: []const usize, m: usize, n: usize) -> bool {
    var k = 0usize
    while k < m {
        if src[k] >= n || dst[k] >= n { ret true }
        k += 1usize
    }
    ret false
}

// One bit per identifier into `bits`.
fn collect_bits(ids: []const u64, n: usize, bits: []u8) {
    var i = 0usize
    while i < n {
        bits[usize(splitmix64(ids[i]) % u64(bits.len))] = 1u8
        i += 1usize
    }
}

// Path fingerprints: every simple directed path of `1..max_length` bonds
// sets the bit of its atom/bond sequence identifier. Paths are found by an
// explicit depth-first search from every atom over unused bonds to
// unvisited atoms, so both directions of one undirected path set the same
// bit twice, harmlessly. `scratch.len >= 3 * max_length + 2` holds the node
// stack, the per-level next-bond indices and the bonds of the open path.
fn path_fingerprint(atoms: []const u32, n: usize, src: []const usize, dst: []const usize, order: []const u8, m: usize, max_length: u32, bits: []u8, scratch: []usize) -> err {
    if atoms.len < n || src.len < m || dst.len < m || order.len < m || bits.len < 1usize { ret TooSmall }
    let length = usize(max_length)
    if n == 0usize || length == 0usize { ret Invalid }
    if scratch.len < 3usize * length + 2usize { ret TooSmall }
    if bad_endpoints(src, dst, m, n) { ret Invalid }
    var stack = scratch[..length + 1usize]
    var ptr = scratch[length + 1usize..2usize * length + 2usize]
    var used = scratch[2usize * length + 2usize..3usize * length + 2usize]
    var i = 0usize
    while i < bits.len {
        bits[i] = 0u8
        i += 1usize
    }
    var start = 0usize
    while start < n {
        stack[0usize] = start
        ptr[0usize] = 0usize
        var depth = 0usize
        while true {
            // The next unused bond from this node to an unvisited one.
            var b = ptr[depth]
            var other = n
            var found = m
            var searching = true
            while b < m && searching {
                if src[b] == stack[depth] {
                    other = dst[b]
                } else if dst[b] == stack[depth] {
                    other = src[b]
                }
                if other != n {
                    var free = true
                    var t = 0usize
                    while t < depth {
                        if used[t] == b { free = false }
                        t += 1usize
                    }
                    t = 0usize
                    while t <= depth && free {
                        if stack[t] == other { free = false }
                        t += 1usize
                    }
                    if free {
                        found = b
                        searching = false
                    }
                }
                b += 1usize
            }
            if found == m {
                if depth == 0usize { break }
                depth -= 1usize
            } else {
                // The path through `found`: atoms along the stack, then `other`.
                var id = u64(atoms[stack[0usize]])
                var l = 0usize
                while l < depth {
                    let bk = used[l]
                    var next_node = dst[bk]
                    if src[bk] != stack[l] { next_node = src[bk] }
                    id = mix(mix(id, u64(order[bk])), u64(atoms[next_node]))
                    l += 1usize
                }
                id = mix(mix(id, u64(order[found])), u64(atoms[other]))
                bits[usize(splitmix64(id) % u64(bits.len))] = 1u8
                used[depth] = found
                ptr[depth] = found + 1usize
                if depth + 1usize < length {
                    stack[depth + 1usize] = other
                    ptr[depth + 1usize] = 0usize
                    depth += 1usize
                }
            }
        }
        start += 1usize
    }
    ret ok
}

// The Tanimoto (Jaccard) similarity of two `n`-bit vectors; two empty
// vectors score 1.
fn tanimoto(a: []const u8, b: []const u8, n: usize) -> (f64, err) {
    if a.len < n || b.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, Invalid) }
    var inter = 0u64
    var total = 0u64
    var i = 0usize
    while i < n {
        if a[i] != 0u8 || b[i] != 0u8 {
            total += 1u64
            if a[i] != 0u8 && b[i] != 0u8 { inter += 1u64 }
        }
        i += 1usize
    }
    if total == 0u64 { ret (1.0f64, ok) }
    ret (f64(inter) / f64(total), ok)
}

// The Dice similarity; two empty vectors score 1.
fn dice(a: []const u8, b: []const u8, n: usize) -> (f64, err) {
    if a.len < n || b.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, Invalid) }
    var inter = 0u64
    var count_a = 0u64
    var count_b = 0u64
    var i = 0usize
    while i < n {
        if a[i] != 0u8 {
            count_a += 1u64
            if b[i] != 0u8 { inter += 1u64 }
        }
        if b[i] != 0u8 { count_b += 1u64 }
        i += 1usize
    }
    if count_a + count_b == 0u64 { ret (1.0f64, ok) }
    ret (2.0f64 * f64(inter) / f64(count_a + count_b), ok)
}

// One minus Tanimoto; two empty vectors are at distance 0.
fn bit_distance(a: []const u8, b: []const u8, n: usize) -> (f64, err) {
    if a.len < n || b.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize { ret (0.0f64, Invalid) }
    let (similarity, similarity_error) = tanimoto(a, b, n)
    if similarity_error != ok { ret (0.0f64, similarity_error) }
    ret (1.0f64 - similarity, ok)
}

// Taylor-Butina clustering of `k` `w`-bit fingerprints: every molecule
// counts the neighbours within `cutoff` bit-distance, molecules go in
// falling neighbour-count order (ties to the lower index), and each
// unclaimed molecule opens the cluster of everything still unclaimed
// within its cutoff. `labels` receives cluster indices, `order` the
// processing order; `scratch.len >= 2 * k` holds counts and claims.
// Answers the cluster count.
fn butina(fp: []const u8, k: usize, w: usize, cutoff: f64, labels: []usize, order: []usize, scratch: []usize) -> (usize, err) {
    if fp.len < k * w || labels.len < k || order.len < k || scratch.len < 2usize * k { ret (0usize, TooSmall) }
    if k == 0usize || w == 0usize || cutoff < 0.0f64 { ret (0usize, Invalid) }
    var counts = scratch[..k]
    var taken = scratch[k..2usize * k]
    var i = 0usize
    while i < k {
        counts[i] = 0usize
        taken[i] = 0usize
        order[i] = i
        var j = 0usize
        while j < k {
            let (d, distance_error) = bit_distance(fp[i * w..(i + 1usize) * w], fp[j * w..(j + 1usize) * w], w)
            if distance_error != ok { ret (0usize, distance_error) }
            if d <= cutoff { counts[i] += 1usize }
            j += 1usize
        }
        i += 1usize
    }
    // Selection sort by falling count, the lower index winning ties.
    i = 0usize
    while i < k {
        var best = i
        var j = i + 1usize
        while j < k {
            if counts[order[j]] > counts[order[best]] { best = j }
            j += 1usize
        }
        let swap = order[i]
        order[i] = order[best]
        order[best] = swap
        i += 1usize
    }
    var clusters = 0usize
    var t = 0usize
    while t < k {
        let centre = order[t]
        if taken[centre] == 0usize {
            var j = 0usize
            while j < k {
                if taken[j] == 0usize {
                    let (d, distance_error) = bit_distance(fp[centre * w..(centre + 1usize) * w], fp[j * w..(j + 1usize) * w], w)
                    if distance_error != ok { ret (0usize, distance_error) }
                    if d <= cutoff {
                        taken[j] = 1usize
                        labels[j] = clusters
                    }
                }
                j += 1usize
            }
            clusters += 1usize
        }
        t += 1usize
    }
    ret (clusters, ok)
}

// The common edge count of the largest connected edge-induced common
// subgraph of `ga`/`gb` (McGregor branch and bound over compatible edge
// pairs, both orientations, edges in index order with a skip branch each).
// `map_a` (`na`) receives the best `a -> b` atom map (`nb` where unmapped).
// `scratch.len >= na + nb + ma + mb` holds the working maps and edge marks.
// `budget` bounds the visited states; exhaustion keeps the best so far.
fn fmcs(atoms_a: []const u32, na: usize, src_a: []const usize, dst_a: []const usize, order_a: []const u8, ma: usize, atoms_b: []const u32, nb: usize, src_b: []const usize, dst_b: []const usize, order_b: []const u8, mb: usize, budget: u32, map_a: []usize, scratch: []usize) -> (usize, err) {
    if atoms_a.len < na || src_a.len < ma || dst_a.len < ma || order_a.len < ma || atoms_b.len < nb || src_b.len < mb || dst_b.len < mb || order_b.len < mb || map_a.len < na || scratch.len < na + nb + ma + mb { ret (0usize, TooSmall) }
    if na == 0usize || nb == 0usize { ret (0usize, Invalid) }
    if bad_endpoints(src_a, dst_a, ma, na) || bad_endpoints(src_b, dst_b, mb, nb) { ret (0usize, Invalid) }
    var i = 0usize
    while i < na {
        map_a[i] = nb
        i += 1usize
    }
    if ma == 0usize || mb == 0usize { ret (0usize, ok) }
    var ga = Graph { atoms: atoms_a, n: na, src: src_a, dst: dst_a, order: order_a, m: ma }
    var gb = Graph { atoms: atoms_b, n: nb, src: src_b, dst: dst_b, order: order_b, m: mb }
    var work_a = scratch[..na]
    var work_b = scratch[na..na + nb]
    var used_a = scratch[na + nb..na + nb + ma]
    var used_b = scratch[na + nb + ma..na + nb + ma + mb]
    i = 0usize
    while i < na {
        work_a[i] = nb
        i += 1usize
    }
    i = 0usize
    while i < nb {
        work_b[i] = na
        i += 1usize
    }
    i = 0usize
    while i < ma {
        used_a[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < mb {
        used_b[i] = 0usize
        i += 1usize
    }
    var best = 0usize
    var remaining = budget
    fmcs_search(&ga, &gb, work_a, work_b, used_a, used_b, map_a, &best, &remaining, 0usize, ma, mb)
    ret (best, ok)
}

// One search state with `mapped` edges so far and `ra`/`rb` unused edges
// left: the first usable edge of `ga` pairs with every compatible unused
// edge of `gb` in both orientations, then with the skip branch. `best`
// counts the most edges yet with their map in `map_a`; `budget` counts
// down the visited states.
fn fmcs_search(ga: *const Graph, gb: *const Graph, work_a: []usize, work_b: []usize, used_a: []usize, used_b: []usize, map_a: []usize, best: *usize, budget: *u32, mapped: usize, ra: usize, rb: usize) {
    if *budget != 0u32 {
        *budget = *budget - 1u32
        var room = ra
        if rb < room { room = rb }
        if mapped + room > *best {
            // The first unused edge touching the mapped region (any edge first).
            var ea = ga.m
            var k = 0usize
            while k < ga.m && ea == ga.m {
                if used_a[k] == 0usize && (mapped == 0usize || work_a[ga.src[k]] != gb.n || work_a[ga.dst[k]] != gb.n) { ea = k }
                k += 1usize
            }
            if ea != ga.m {
                let u = ga.src[ea]
                let v = ga.dst[ea]
                used_a[ea] = 1usize
                var kb = 0usize
                while kb < gb.m {
                    if used_b[kb] == 0usize && gb.order[kb] == ga.order[ea] && (mapped == 0usize || work_b[gb.src[kb]] != ga.n || work_b[gb.dst[kb]] != ga.n) {
                        let x = gb.src[kb]
                        let y = gb.dst[kb]
                        var flip = 0usize
                        while flip < 2usize {
                            var xx = x
                            var yy = y
                            if flip == 1usize {
                                xx = y
                                yy = x
                            }
                            var compatible = true
                            if work_a[u] != gb.n {
                                if work_a[u] != xx { compatible = false }
                            } else if work_b[xx] != ga.n {
                                compatible = false
                            } else if ga.atoms[u] != gb.atoms[xx] {
                                compatible = false
                            }
                            if compatible {
                                if work_a[v] != gb.n {
                                    if work_a[v] != yy { compatible = false }
                                } else if work_b[yy] != ga.n {
                                    compatible = false
                                } else if ga.atoms[v] != gb.atoms[yy] {
                                    compatible = false
                                }
                            }
                            if compatible {
                                var fresh_u = false
                                var fresh_v = false
                                if work_a[u] == gb.n {
                                    work_a[u] = xx
                                    work_b[xx] = u
                                    fresh_u = true
                                }
                                if work_a[v] == gb.n {
                                    work_a[v] = yy
                                    work_b[yy] = v
                                    fresh_v = true
                                }
                                used_b[kb] = 1usize
                                if mapped + 1usize > *best {
                                    *best = mapped + 1usize
                                    var c = 0usize
                                    while c < ga.n {
                                        map_a[c] = work_a[c]
                                        c += 1usize
                                    }
                                }
                                fmcs_search(ga, gb, work_a, work_b, used_a, used_b, map_a, best, budget, mapped + 1usize, ra - 1usize, rb - 1usize)
                                used_b[kb] = 0usize
                                if fresh_u {
                                    work_a[u] = gb.n
                                    work_b[xx] = ga.n
                                }
                                if fresh_v {
                                    work_a[v] = gb.n
                                    work_b[yy] = ga.n
                                }
                            }
                            flip += 1usize
                        }
                    }
                    kb += 1usize
                }
                used_a[ea] = 0usize
                fmcs_search(ga, gb, work_a, work_b, used_a, used_b, map_a, best, budget, mapped, ra - 1usize, rb)
            }
        }
    }
}
