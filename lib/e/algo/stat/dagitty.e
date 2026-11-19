// R dagitty: reasoning about a causal DAG of at most 20 nodes given as an adjacency matrix (row i, column j set when i -> j): ancestors,
// d-separation by the moralised ancestral graph, and the minimal adjustment sets for a total effect (the generalized adjustment
// criterion of Perkovic et al.: no node of Z forbidden, and Z separates X from Y once the first edges of the proper causal paths are
// removed). Node sets are bit masks.
//
// Not here: the other effect types, canonical and exhaustive set types, instrumentalVariables, paths, equivalentDAGs, localTests and the
// mixed-graph (bidirected edge) forms.

use e.algo.stat.mass as mass
use e.math
use e.math.nmath as nm
use e.math.dist as nq
use e.math.scale as sc
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

// the v-structures of an n by n DAG (n at most 8) as a set of (u, v, z) with u < v non-adjacent parents of z, packed u * 64 + v * 8 + z into vs (512 entries)
fn v_structures(adj: []const bool, n: usize, vs: []bool) {
    var i = 0usize
    while i < 512usize {
        vs[i] = false
        i += 1usize
    }
    var z = 0usize
    while z < n {
        var u = 0usize
        while u < n {
            var v = u + 1usize
            while v < n {
                if has(adj, n, u, z) && has(adj, n, v, z) && !has(adj, n, u, v) && !has(adj, n, v, u) { vs[u * 64usize + v * 8usize + z] = true }
                v += 1usize
            }
            u += 1usize
        }
        z += 1usize
    }
}

fn is_acyclic(adj: []const bool, n: usize) -> bool {
    var done = 0u32
    var progress = true
    while progress {
        progress = false
        var v = 0usize
        while v < n {
            if (done & bit(v)) == 0u32 && (parents_mask(adj, n, v) & ~done) == 0u32 {
                done = done | bit(v)
                progress = true
            }
            v += 1usize
        }
    }
    ret done == (1u32 << u32(n)) - 1u32
}

// the number of DAGs in the Markov equivalence class of the DAG (same skeleton and same v-structures), the DAG itself included (equivalentDAGs); n at most 8, at most 20 edges
fn equivalent_dag_count(a: *mem.Arena, adj: []const bool, n: usize) -> usize {
    var eu: [28]usize = zero
    var ev: [28]usize = zero
    var m = 0usize
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if has(adj, n, i, j) && m < 28usize {
                eu[m] = i
                ev[m] = j
                m += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    if m > 20usize { ret 0usize }
    let (g, e0) = mem.alloc[bool](a, n * n)
    let (vs0, e1) = mem.alloc[bool](a, 512usize)
    let (vs1, e2) = mem.alloc[bool](a, 512usize)
    if e0 != ok || e1 != ok || e2 != ok { ret 0usize }
    v_structures(adj, n, vs0)
    var count = 0usize
    var mask = 0u32
    let total = 1u32 << u32(m)
    while mask < total {
        var t = 0usize
        while t < n * n {
            g[t] = false
            t += 1usize
        }
        var e = 0usize
        while e < m {
            if ((mask >> u32(e)) & 1u32) == 1u32 { g[ev[e] * n + eu[e]] = true } else { g[eu[e] * n + ev[e]] = true }
            e += 1usize
        }
        if is_acyclic(g, n) {
            v_structures(g, n, vs1)
            var same = true
            t = 0usize
            while t < 512usize {
                if vs0[t] != vs1[t] { same = false }
                t += 1usize
            }
            if same { count += 1usize }
        }
        mask += 1u32
    }
    ret count
}

// impliedConditionalIndependencies (type "missing.edge"): for every non-adjacent pair (x < y) every minimal d-separating set. Answers the number of statements and a
// signature, the sum over the statements of zmask + 256 x + 2048 y (the nodes 0-based), which the oracle recomputes from dagitty's output.
fn implied_independencies(adj: []const bool, n: usize) -> (usize, f64) {
    var count = 0usize
    var sig = 0.0f64
    var x = 0usize
    while x < n {
        var y = x + 1usize
        while y < n {
            if !has(adj, n, x, y) && !has(adj, n, y, x) {
                let rest = ((1u32 << u32(n)) - 1u32) & ~(bit(x) | bit(y))
                var z = 0u32
                let total = 1u32 << u32(n)
                while z < total {
                    if (z & ~rest) == 0u32 && dseparated(adj, n, bit(x), bit(y), z) {
                        // minimal: no proper subset separates
                        var minimal = true
                        if z != 0u32 {
                            var sub = (z - 1u32) & z
                            var more = true
                            while more {
                                if dseparated(adj, n, bit(x), bit(y), sub) {
                                    minimal = false
                                    more = false
                                } else if sub == 0u32 {
                                    more = false
                                } else {
                                    sub = (sub - 1u32) & z
                                }
                            }
                        }
                        if minimal {
                            count += 1usize
                            sig += f64(z) + 256.0f64 * f64(x) + 2048.0f64 * f64(y)
                        }
                    }
                    z += 1u32
                }
            }
            y += 1usize
        }
        x += 1usize
    }
    ret (count, sig)
}

// whether z is a minimal d-separating set of x and y (no proper subset separates them)
fn minimal_separator(adj: []const bool, n: usize, x: usize, y: usize, z: u32) -> bool {
    if !dseparated(adj, n, bit(x), bit(y), z) { ret false }
    if z == 0u32 { ret true }
    var sub = (z - 1u32) & z
    while true {
        if dseparated(adj, n, bit(x), bit(y), sub) { ret false }
        if sub == 0u32 { break }
        sub = (sub - 1u32) & z
    }
    ret true
}

// the statements of impliedConditionalIndependencies (missing.edge) one by one into ox, oy (x < y) and oz (the set as a bit mask); the number written
fn implied_list(adj: []const bool, n: usize, ox: []usize, oy: []usize, oz: []u32) -> usize {
    var count = 0usize
    var x = 0usize
    while x < n {
        var y = x + 1usize
        while y < n {
            if !has(adj, n, x, y) && !has(adj, n, y, x) {
                let rest = ((1u32 << u32(n)) - 1u32) & ~(bit(x) | bit(y))
                var z = 0u32
                let total = 1u32 << u32(n)
                while z < total {
                    if (z & ~rest) == 0u32 && minimal_separator(adj, n, x, y, z) && count < ox.len {
                        ox[count] = x
                        oy[count] = y
                        oz[count] = z
                        count += 1usize
                    }
                    z += 1u32
                }
            }
            y += 1usize
        }
        x += 1usize
    }
    ret count
}

// localTests(type = "cis") on a correlation matrix (n_vars square, row-major) and the sample size: the partial correlation of x and y given the bit mask z from the pseudo-inverse of the
// sub-matrix (x, y, then z in index order), the chi-squared(1) p value of its Fisher z on nobs - |z| - 3 degrees of freedom, and the interval dagitty computes with atan (not tanh) at
// conf.level; out = (estimate, p value, lower, upper)
fn local_test(a: *mem.Arena, cor: []const f64, nv: usize, x: usize, y: usize, z: u32, nobs: f64, level: f64, out: []f64) -> err {
    var vars: [32]usize = zero
    vars[0usize] = x
    vars[1usize] = y
    var m = 2usize
    var i = 0usize
    while i < nv {
        if (z & bit(i)) != 0u32 {
            vars[m] = i
            m += 1usize
        }
        i += 1usize
    }
    let (sub, e1) = mem.alloc[f64](a, m * m)
    if e1 != ok { ret e1 }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            sub[i * m + j] = cor[vars[i] * nv + vars[j]]
            j += 1usize
        }
        i += 1usize
    }
    let (gi, ge) = mass.ginv(a, sub, m, m)
    if ge != ok { ret ge }
    let pcor = 0.0f64 - gi[1usize] / math.sqrt[f64](gi[0usize] * gi[m + 1usize])
    let pz = sc.atanh(pcor)
    let df = nobs - f64(m - 2usize) - 3.0f64
    let sem = 1.0f64 / math.sqrt[f64](df)
    let crit = dist_qnorm_upper((1.0f64 - level) / 2.0f64)
    out[0usize] = pcor
    out[1usize] = nm.pchisq(pz * pz * df, 1.0f64, false, false)
    out[2usize] = math.atan[f64](pz - crit * sem)
    out[3usize] = math.atan[f64](pz + crit * sem)
    ret ok
}

fn dist_qnorm_upper(p: f64) -> f64 { ret 0.0f64 - nq.qnorm(p, 0.0f64, 1.0f64, true, false) }
