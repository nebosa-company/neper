// R dagitty: reasoning about a causal DAG of at most 20 nodes given as an adjacency matrix (row i, column j set when i -> j): ancestors,
// d-separation by the moralised ancestral graph, and the minimal adjustment sets for a total effect (the generalized adjustment
// criterion of Perkovic et al.: no node of Z forbidden, and Z separates X from Y once the first edges of the proper causal paths are
// removed). Node sets are bit masks.
//
// Not here: the other effect types, canonical and exhaustive set types, instrumentalVariables, paths, equivalentDAGs, localTests and the
// mixed-graph (bidirected edge) forms.

use e.mem

fn has(adj: []const bool, n: usize, i: usize, j: usize) -> bool { ret adj[i * n + j] }

fn bit(i: usize) -> u32 { ret 1u32 << u32(i) }

fn parents_mask(adj: []const bool, n: usize, j: usize) -> u32 {
    var m = 0u32
    var i = 0usize
    while i < n {
        if has(adj, n, i, j) { m = m | bit(i) }
        i += 1usize
    }
    ret m
}

fn children_mask(adj: []const bool, n: usize, i: usize) -> u32 {
    var m = 0u32
    var j = 0usize
    while j < n {
        if has(adj, n, i, j) { m = m | bit(j) }
        j += 1usize
    }
    ret m
}

// the nodes in `seed` and all their ancestors
fn ancestors(adj: []const bool, n: usize, seed: u32) -> u32 {
    var m = seed
    var changed = true
    while changed {
        changed = false
        var j = 0usize
        while j < n {
            if (m & bit(j)) != 0u32 {
                let p = parents_mask(adj, n, j)
                if (m | p) != m {
                    m = m | p
                    changed = true
                }
            }
            j += 1usize
        }
    }
    ret m
}

// the nodes in `seed` and all their descendants
fn descendants(adj: []const bool, n: usize, seed: u32) -> u32 {
    var m = seed
    var changed = true
    while changed {
        changed = false
        var i = 0usize
        while i < n {
            if (m & bit(i)) != 0u32 {
                let c = children_mask(adj, n, i)
                if (m | c) != m {
                    m = m | c
                    changed = true
                }
            }
            i += 1usize
        }
    }
    ret m
}

// x and y (masks) are d-separated given z: x and y disconnected in the moral graph of the ancestors of x, y and z with z removed
fn dseparated(adj: []const bool, n: usize, x: u32, y: u32, z: u32) -> bool {
    let anc = ancestors(adj, n, x | y | z)
    // undirected adjacency over the ancestral set: edges and the marrying of parents
    var reach = x & ~z
    var changed = true
    while changed {
        changed = false
        var i = 0usize
        while i < n {
            if (reach & bit(i)) != 0u32 {
                var j = 0usize
                while j < n {
                    if (anc & bit(j)) != 0u32 && (z & bit(j)) == 0u32 && (reach & bit(j)) == 0u32 {
                        var linked = has(adj, n, i, j) || has(adj, n, j, i)
                        if !linked {
                            // married: a common child inside the ancestral set
                            var k = 0usize
                            while k < n {
                                if (anc & bit(k)) != 0u32 && has(adj, n, i, k) && has(adj, n, j, k) { linked = true }
                                k += 1usize
                            }
                        }
                        if linked {
                            reach = reach | bit(j)
                            changed = true
                        }
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
    }
    ret (reach & y) == 0u32
}

// whether z is a valid adjustment set for the total effect of x on y (single nodes)
fn valid_adjustment(a: *mem.Arena, adj: []const bool, n: usize, x: usize, y: usize, z: u32) -> bool {
    let anc_y = ancestors(adj, n, bit(y))
    let de_x = descendants(adj, n, bit(x))
    let pcp = de_x & anc_y & ~bit(x)
    let forb = descendants(adj, n, pcp)
    if (z & forb) != 0u32 { ret false }
    if (z & (bit(x) | bit(y))) != 0u32 { ret false }
    let (g, e) = mem.alloc[bool](a, n * n)
    if e != ok { ret false }
    var t = 0usize
    while t < n * n {
        g[t] = adj[t]
        t += 1usize
    }
    var w = 0usize
    while w < n {
        if has(adj, n, x, w) && (anc_y & bit(w)) != 0u32 { g[x * n + w] = false }
        w += 1usize
    }
    ret dseparated(g, n, bit(x), bit(y), z)
}

// the minimal adjustment sets as masks: how many, and the sum of the masks (written to sets, which needs room for 2^n entries)
fn minimal_adjustment_sets(a: *mem.Arena, adj: []const bool, n: usize, x: usize, y: usize, sets: []u32) -> usize {
    let total = 1u32 << u32(n)
    var found = 0usize
    var z = 0u32
    while z < total {
        if valid_adjustment(a, adj, n, x, y, z) {
            // minimal: no proper subset is valid
            var minimal = true
            if z != 0u32 {
                var s = (z - 1u32) & z
                var more = true
                while more {
                    if valid_adjustment(a, adj, n, x, y, s) {
                        minimal = false
                        more = false
                    } else if s == 0u32 {
                        more = false
                    } else {
                        s = (s - 1u32) & z
                    }
                }
            }
            if minimal {
                sets[found] = z
                found += 1usize
            }
        }
        z += 1u32
    }
    ret found
}

// every valid adjustment set for the total effect of x on y, as masks (sets needs room for 2^n entries); returns how many
fn all_adjustment_sets(a: *mem.Arena, adj: []const bool, n: usize, x: usize, y: usize, sets: []u32) -> usize {
    let total = 1u32 << u32(n)
    var found = 0usize
    var z = 0u32
    while z < total {
        if valid_adjustment(a, adj, n, x, y, z) {
            sets[found] = z
            found += 1usize
        }
        z += 1u32
    }
    ret found
}

// the canonical adjustment set: the ancestors of x and y without x, y and the descendants of the nodes on proper causal paths; (mask, true) when it is a valid
// adjustment set, (0, false) when none (dagitty answers an empty list)
fn canonical_adjustment_set(a: *mem.Arena, adj: []const bool, n: usize, x: usize, y: usize) -> (u32, bool) {
    let anc_xy = ancestors(adj, n, bit(x) | bit(y))
    let anc_y = ancestors(adj, n, bit(y))
    let de_x = descendants(adj, n, bit(x))
    let pcp = de_x & anc_y & ~bit(x)
    let forb = descendants(adj, n, pcp)
    let cand = anc_xy & ~(bit(x) | bit(y)) & ~forb
    if valid_adjustment(a, adj, n, x, y, cand) { ret (cand, true) }
    ret (0u32, false)
}

// the simple paths of the skeleton between x and y (every edge usable in either direction) and how many are open given z; paths is the count of all, open of the open ones
fn count_paths(adj: []const bool, n: usize, x: usize, y: usize, z: u32) -> (usize, usize) {
    // the nodes with a descendant (or themselves) in z: the colliders that z opens
    var opens = 0u32
    var v = 0usize
    while v < n {
        if (descendants(adj, n, bit(v)) & z) != 0u32 { opens = opens | bit(v) }
        v += 1usize
    }
    var stack: [16]usize = zero
    var next: [16]usize = zero
    var total = 0usize
    var open = 0usize
    var depth = 0usize
    stack[0usize] = x
    next[0usize] = 0usize
    var used = bit(x)
    var go = true
    while go {
        let cur = stack[depth]
        var moved = false
        var w = next[depth]
        while w < n && !moved {
            if w != cur && (has(adj, n, cur, w) || has(adj, n, w, cur)) && (used & bit(w)) == 0u32 {
                next[depth] = w + 1usize
                if w == y {
                    // a complete path: stack[0..depth] then y
                    total += 1usize
                    var isopen = true
                    var t = 1usize
                    while t <= depth {
                        let node = stack[t]
                        let prev = stack[t - 1usize]
                        var nxt = y
                        if t < depth { nxt = stack[t + 1usize] }
                        let coll = has(adj, n, prev, node) && has(adj, n, nxt, node)
                        if coll {
                            if (opens & bit(node)) == 0u32 { isopen = false }
                        } else {
                            if (z & bit(node)) != 0u32 { isopen = false }
                        }
                        t += 1usize
                    }
                    // the last interior node's next is y: handled above (nxt = y when t == depth)
                    if isopen { open += 1usize }
                } else {
                    depth += 1usize
                    stack[depth] = w
                    next[depth] = 0usize
                    used = used | bit(w)
                    moved = true
                }
            }
            if !moved { w += 1usize }
        }
        if !moved {
            if depth == 0usize {
                go = false
            } else {
                used = used & ~bit(stack[depth])
                depth -= 1usize
            }
        }
    }
    ret (total, open)
}
