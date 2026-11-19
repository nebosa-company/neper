// phangorn::parsimony(tree, data, method = "fitch") for a binary tree and a DNA alignment: the Fitch small-parsimony score summed over the sites, with the ambiguity codes as sets of states (bit 1 A, 2 C, 4 G, 8 T; N is 15, R is 5).
// The tree is ape's edge list (parent and child columns, 0-based, tips 0 .. nt - 1, the root nt) in cladewise order, which puts every parent before its children.
//
// Not here: the other cost matrices (sankoff), non-binary trees, pratchet and the search, pml and the likelihood models, model selection, bootstrap.

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
