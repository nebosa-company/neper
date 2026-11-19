// phangorn::parsimony(tree, data, method = "fitch") for a binary tree and a DNA alignment: the Fitch small-parsimony score summed over the sites, with the ambiguity codes as sets of states (bit 1 A, 2 C, 4 G, 8 T; N is 15, R is 5).
// The tree is ape's edge list (parent and child columns, 0-based, tips 0 .. nt - 1, the root nt) in cladewise order, which puts every parent before its children.
//
// Not here: the other cost matrices (sankoff), non-binary trees, pratchet and the search, pml and the likelihood models, model selection, bootstrap.

use e.math
use e.mem

fn fitch(a: *mem.Arena, par: []const f64, chd: []const f64, ne: usize, nt: usize, data: []const f64, ns: usize) -> f64 {
    let nn = ne + 1usize
    let (c1, e1) = mem.alloc[usize](a, nn)
    let (c2, e2) = mem.alloc[usize](a, nn)
    let (set, e3) = mem.alloc[u32](a, nn)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < nn {
        c1[i] = nn
        c2[i] = nn
        i += 1usize
    }
    i = 0usize
    while i < ne {
        let p = usize(par[i])
        if c1[p] == nn {
            c1[p] = usize(chd[i])
        } else {
            c2[p] = usize(chd[i])
        }
        i += 1usize
    }
    var total = 0usize
    var s = 0usize
    while s < ns {
        i = 0usize
        while i < nt {
            set[i] = u32(data[i * ns + s])
            i += 1usize
        }
        // children after parents in the edge list: walking it backwards reaches the first child edge of a node after every edge below it
        var k = ne
        while k > 0usize {
            k -= 1usize
            let p = usize(par[k])
            if usize(chd[k]) == c1[p] {
                let l = set[c1[p]]
                let r = set[c2[p]]
                if (l & r) != 0u32 {
                    set[p] = l & r
                } else {
                    set[p] = l | r
                    total += 1usize
                }
            }
        }
        s += 1usize
    }
    ret f64(total)
}

// phangorn::upgma (weighted false) and wpgma (true) from a full n by n distance matrix d: out receives the n - 1 merge heights in merge order (half the merged distance), then the total edge length of the tree
fn upgma(a: *mem.Arena, d: []const f64, n: usize, weighted: bool, out: []f64) -> err {
    let (dm, e1) = mem.alloc[f64](a, n * n)
    let (sz, e2) = mem.alloc[f64](a, n)
    let (ht, e3) = mem.alloc[f64](a, n)
    let (alive, e4) = mem.alloc[bool](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var i = 0usize
    while i < n * n {
        dm[i] = d[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        sz[i] = 1.0f64
        ht[i] = 0.0f64
        alive[i] = true
        i += 1usize
    }
    var len = 0.0f64
    var m = 0usize
    while m + 1usize < n {
        var bi = n
        var bj = n
        var best = 0.0f64
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                if alive[i] && alive[j] && (bi == n || dm[i * n + j] < best) {
                    bi = i
                    bj = j
                    best = dm[i * n + j]
                }
                j += 1usize
            }
            i += 1usize
        }
        let h = best / 2.0f64
        out[m] = h
        len += (h - ht[bi]) + (h - ht[bj])
        var k = 0usize
        while k < n {
            if alive[k] && k != bi && k != bj {
                var nd = (dm[bi * n + k] + dm[bj * n + k]) / 2.0f64
                if !weighted { nd = (dm[bi * n + k] * sz[bi] + dm[bj * n + k] * sz[bj]) / (sz[bi] + sz[bj]) }
                dm[bi * n + k] = nd
                dm[k * n + bi] = nd
            }
            k += 1usize
        }
        sz[bi] = sz[bi] + sz[bj]
        ht[bi] = h
        alive[bj] = false
        m += 1usize
    }
    out[n - 1usize] = len
    ret ok
}

// phangorn::dist.hamming(ratio = TRUE) of tips i and j of an alignment of unambiguous states (bit sets as in fitch): the share of sites that differ; jc turns it into the Jukes-Cantor distance -3/4 log(1 - 4/3 p), the maximum
// likelihood distance of dist.ml(model = "JC69")
fn hamming(data: []const f64, ns: usize, i: usize, j: usize, jc: bool) -> f64 {
    var diff = 0.0f64
    var s = 0usize
    while s < ns {
        if data[i * ns + s] != data[j * ns + s] { diff += 1.0f64 }
        s += 1usize
    }
    let p = diff / f64(ns)
    if !jc { ret p }
    ret 0.0f64 - 0.75f64 * math.log[f64](1.0f64 - 4.0f64 / 3.0f64 * p)
}
