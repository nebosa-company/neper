// R stats::as.dendrogram(hclust) and dendextend's rotation and untangling, on a dendrogram of this module's own:
// binary nodes with an ordered pair of children and a height, leaves with a label (the observation) and a value
// (what order.dendrogram answers). rotate, flip_leaves, all_couple_rotations_at_k, heights_per_k, match_order_by_labels,
// entanglement (labels and order matching) and untangle (labels, step1side, step2side, random) follow dendextend's R sources
// step for step, so the child order of every node equals R's.
//
// Not here: untangle method "DendSer" (needs the DendSer package, whose seriation search is not ported) and "stepBothSides".

use e.math
use e.mem
use e.algo.stat.hclust as hc
use e.algo.rand.r as rng

// leaves are the node ids 0..n-1 (the label); the internal node of merge step s is n + s; the root is 2n - 2
type Dend = struct { n: usize, ca: []i32, cb: []i32, hgt: []f64, val: []i32 }

// heights_per_k: for k = ks[j] clusters the cut height hs[j]
type Hpk = struct { k: []usize, h: []f64 }

fn node_id(m: i32, n: usize) -> i32 {
    if m < 0i32 { ret 0i32 - m - 1i32 }
    ret i32(n) + m - 1i32
}

// as.dendrogram(hclust): the children of a node are the merge row's two entries in order, leaf values are the observation numbers
fn from_hclust(a: *mem.Arena, t: *const hc.Tree, n: usize) -> (Dend, err) {
    let (ca, e1) = mem.alloc[i32](a, n - 1usize)
    if e1 != ok { ret (zero, e1) }
    let (cb, e2) = mem.alloc[i32](a, n - 1usize)
    if e2 != ok { ret (zero, e2) }
    let (val, e3) = mem.alloc[i32](a, n)
    if e3 != ok { ret (zero, e3) }
    var s = 0usize
    while s + 1usize < n {
        ca[s] = node_id(t.merge_a[s], n)
        cb[s] = node_id(t.merge_b[s], n)
        s += 1usize
    }
    var l = 0usize
    while l < n {
        val[l] = i32(l + 1usize)
        l += 1usize
    }
    ret (Dend { n: n, ca: ca, cb: cb, hgt: t.height, val: val }, ok)
}

fn clone(a: *mem.Arena, d: *const Dend) -> (Dend, err) {
    let n = d.n
    let (ca, e1) = mem.alloc[i32](a, n - 1usize)
    if e1 != ok { ret (zero, e1) }
    let (cb, e2) = mem.alloc[i32](a, n - 1usize)
    if e2 != ok { ret (zero, e2) }
    let (val, e3) = mem.alloc[i32](a, n)
    if e3 != ok { ret (zero, e3) }
    var i = 0usize
    while i + 1usize < n {
        ca[i] = d.ca[i]
        cb[i] = d.cb[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        val[i] = d.val[i]
        i += 1usize
    }
    ret (Dend { n: n, ca: ca, cb: cb, hgt: d.hgt, val: val }, ok)
}

fn height_of(d: *const Dend, node: i32) -> f64 {
    if usize(node) < d.n { ret 0.0f64 }
    ret d.hgt[usize(node) - d.n]
}

// the node ids in depth-first preorder, first child first (2n - 1 of them)
fn preorder(a: *mem.Arena, d: *const Dend, out: []i32) -> err {
    let n = d.n
    let (stack, e) = mem.alloc[i32](a, 2usize * n + 2usize)
    if e != ok { ret e }
    stack[0usize] = i32(2usize * n - 2usize)
    var sp = 1usize
    var cnt = 0usize
    while sp > 0usize {
        sp -= 1usize
        let node = stack[sp]
        out[cnt] = node
        cnt += 1usize
        if usize(node) >= n {
            let s = usize(node) - n
            stack[sp] = d.cb[s]
            sp += 1usize
            stack[sp] = d.ca[s]
            sp += 1usize
        }
    }
    ret ok
}

// labels(dend): the observation of each leaf from left to right (0-based)
fn dfs_labels(a: *mem.Arena, d: *const Dend, out: []usize) -> err {
    let n = d.n
    let (nodes, e) = mem.alloc[i32](a, 2usize * n - 1usize)
    if e != ok { ret e }
    let e2 = preorder(a, d, nodes)
    if e2 != ok { ret e2 }
    var cnt = 0usize
    var i = 0usize
    while i < 2usize * n - 1usize {
        if usize(nodes[i]) < n {
            out[cnt] = usize(nodes[i])
            cnt += 1usize
        }
        i += 1usize
    }
    ret ok
}

// order.dendrogram(dend): the leaf values from left to right
fn order_values(a: *mem.Arena, d: *const Dend, out: []i32) -> err {
    let n = d.n
    let (lab, e) = mem.alloc[usize](a, n)
    if e != ok { ret e }
    let e2 = dfs_labels(a, d, lab)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n {
        out[i] = d.val[lab[i]]
        i += 1usize
    }
    ret ok
}

// order.dendrogram(dend) <- ord: the leaf at position p (left to right) takes the value ord[p]
fn set_order(a: *mem.Arena, d: *const Dend, ord: []const i32) -> (Dend, err) {
    let (r, e) = clone(a, d)
    if e != ok { ret (zero, e) }
    let (lab, e2) = mem.alloc[usize](a, d.n)
    if e2 != ok { ret (zero, e2) }
    let e3 = dfs_labels(a, d, lab)
    if e3 != ok { ret (zero, e3) }
    var i = 0usize
    while i < d.n {
        r.val[lab[i]] = ord[i]
        i += 1usize
    }
    ret (r, ok)
}

// the number of leaves under each node
fn members(a: *mem.Arena, d: *const Dend, out: []usize) {
    let n = d.n
    var l = 0usize
    while l < n {
        out[l] = 1usize
        l += 1usize
    }
    var s = 0usize
    while s + 1usize < n {
        out[n + s] = out[usize(d.ca[s])] + out[usize(d.cb[s])]
        s += 1usize
    }
}

// the midpoint attribute (stats midcache.dendrogram): (members of the first child + both children's midpoints) / 2; leaves 0
fn midpoints(a: *mem.Arena, d: *const Dend, out: []f64) -> err {
    let n = d.n
    let (m, e) = mem.alloc[usize](a, 2usize * n - 1usize)
    if e != ok { ret e }
    members(a, d, m)
    var l = 0usize
    while l < n {
        out[l] = 0.0f64
        l += 1usize
    }
    var s = 0usize
    while s + 1usize < n {
        let c1 = usize(d.ca[s])
        let c2 = usize(d.cb[s])
        out[n + s] = (f64(m[c1]) + (out[c1] + out[c2])) / 2.0f64
        s += 1usize
    }
    ret ok
}

// rotate(dend, order): the leaf at position order[i] (1-based, in the current left to right order) gets weight i, and every node
// puts its children in the order of their values, a leaf's value being its weight and a node's the mean of its children's;
// equal values keep the current order (stats reorder.dendrogram with agglo.FUN = mean)
fn rotate(a: *mem.Arena, d: *const Dend, pos: []const i32) -> (Dend, err) {
    let n = d.n
    let (ord, e1) = mem.alloc[i32](a, n)
    if e1 != ok { ret (zero, e1) }
    let (w, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret (zero, e2) }
    let (nv, e3) = mem.alloc[f64](a, 2usize * n - 1usize)
    if e3 != ok { ret (zero, e3) }
    let e4 = order_values(a, d, ord)
    if e4 != ok { ret (zero, e4) }
    var i = 0usize
    while i < n {
        w[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < pos.len {
        w[usize(ord[usize(pos[i]) - 1usize]) - 1usize] = f64(i % n + 1usize)
        i += 1usize
    }
    let (r, e5) = clone(a, d)
    if e5 != ok { ret (zero, e5) }
    var l = 0usize
    while l < n {
        nv[l] = w[usize(d.val[l]) - 1usize]
        l += 1usize
    }
    var s = 0usize
    while s + 1usize < n {
        let c1 = d.ca[s]
        let c2 = d.cb[s]
        let v1 = nv[usize(c1)]
        let v2 = nv[usize(c2)]
        if v2 < v1 {
            r.ca[s] = c2
            r.cb[s] = c1
        }
        nv[n + s] = (v1 + v2) / 2.0f64
        s += 1usize
    }
    ret (r, ok)
}

// the index of the first place in ord where the block blk stands, or ord.len
fn find_block(ord: []const i32, blk: []const i32) -> usize {
    var s = 0usize
    while s + blk.len <= ord.len {
        var same = true
        var j = 0usize
        while j < blk.len {
            if ord[s + j] != blk[j] { same = false }
            j += 1usize
        }
        if same && blk.len > 0usize { ret s }
        s += 1usize
    }
    ret ord.len
}

// t[at..at+cut) replaced by blk; the new length
fn splice(t: []i32, tl: usize, at: usize, cut: usize, blk: []const i32) -> usize {
    let nl = tl - cut + blk.len
    if blk.len > cut {
        var i = tl
        while i > at + cut {
            i -= 1usize
            t[i + blk.len - cut] = t[i]
        }
    } else {
        var i = at + cut
        while i < tl {
            t[i + blk.len - cut] = t[i]
            i += 1usize
        }
    }
    var j = 0usize
    while j < blk.len {
        t[at + j] = blk[j]
        j += 1usize
    }
    ret nl
}

fn find_marker(t: []const i32, tl: usize, m: i32) -> usize {
    var i = 0usize
    while i < tl {
        if t[i] == m { ret i }
        i += 1usize
    }
    ret tl
}

// flip_leaves(dend, leaves1, leaves2): dendextend does it on strings -- the first place the leaves1 block stands becomes a marker, so does
// the first place of leaves2, the markers then take the other block -- and rotates the tree to the order read back. A block that is not found
// (a cluster that is not contiguous, which only a cut of an inverted tree gives) leaves its marker out, and the order read back can then
// repeat or drop leaves; rotate takes it as R's replacement does.
fn flip_leaves(a: *mem.Arena, d: *const Dend, l1: []const i32, l2: []const i32) -> (Dend, err) {
    let n = d.n
    let (ord, e1) = mem.alloc[i32](a, n)
    if e1 != ok { ret (zero, e1) }
    let (t, e2) = mem.alloc[i32](a, 3usize * n + 4usize)
    if e2 != ok { ret (zero, e2) }
    let e4 = order_values(a, d, ord)
    if e4 != ok { ret (zero, e4) }
    var i = 0usize
    while i < n {
        t[i] = ord[i]
        i += 1usize
    }
    let (mk, e6) = mem.alloc[i32](a, 2usize)
    if e6 != ok { ret (zero, e6) }
    mk[0usize] = 0i32 - 1i32
    mk[1usize] = 0i32 - 2i32
    var tl = n
    let s1 = find_block(t[0usize..tl], l1)
    if s1 < tl { tl = splice(t, tl, s1, l1.len, mk[0usize..1usize]) }
    let s2 = find_block(t[0usize..tl], l2)
    if s2 < tl { tl = splice(t, tl, s2, l2.len, mk[1usize..2usize]) }
    let m1 = find_marker(t, tl, 0i32 - 1i32)
    if m1 < tl { tl = splice(t, tl, m1, 1usize, l2) }
    let m2 = find_marker(t, tl, 0i32 - 2i32)
    if m2 < tl { tl = splice(t, tl, m2, 1usize, l1) }
    let (pos, e3) = mem.alloc[i32](a, tl)
    if e3 != ok { ret (zero, e3) }
    i = 0usize
    while i < tl {
        var j = 0usize
        while j < n {
            if ord[j] == t[i] {
                pos[i] = i32(j + 1usize)
                break
            }
            j += 1usize
        }
        i += 1usize
    }
    let (r, e5) = rotate(a, d, pos)
    ret (r, e5)
}

// the clusters of a cut at height h: out[p] is the cluster (numbered from 1 in left to right order) of the leaf at position p, the
// root itself never being cut away; answers the number of clusters (dendextend cut_lower_fun over stats cut.dendrogram)
fn cut_dfs(a: *mem.Arena, d: *const Dend, h: f64, out: []i32) -> (usize, err) {
    let n = d.n
    let (sn, e1) = mem.alloc[i32](a, 2usize * n + 2usize)
    if e1 != ok { ret (0usize, e1) }
    let (sc, e2) = mem.alloc[i32](a, 2usize * n + 2usize)
    if e2 != ok { ret (0usize, e2) }
    let root = i32(2usize * n - 2usize)
    sn[0usize] = root
    sc[0usize] = 0i32
    var sp = 1usize
    var nc = 0i32
    var p = 0usize
    while sp > 0usize {
        sp -= 1usize
        let node = sn[sp]
        var cid = sc[sp]
        if node != root && cid == 0i32 && height_of(d, node) <= h {
            nc += 1i32
            cid = nc
        }
        if usize(node) < n {
            out[p] = cid
            p += 1usize
        } else {
            let s = usize(node) - n
            sn[sp] = d.cb[s]
            sc[sp] = cid
            sp += 1usize
            sn[sp] = d.ca[s]
            sc[sp] = cid
            sp += 1usize
        }
    }
    ret (usize(nc), ok)
}

// heights_per_k.dendrogram: the distinct branch heights from the top, half the smallest gap between two of them below each (and above
// the highest), with the number of clusters a cut at that height gives (the first named 1, the last n)
fn heights_per_k(a: *mem.Arena, d: *const Dend) -> (Hpk, err) {
    let n = d.n
    let (srt, e1) = mem.alloc[f64](a, n - 1usize)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i + 1usize < n {
        srt[i] = d.hgt[i]
        i += 1usize
    }
    // descending insertion sort
    i = 1usize
    while i + 1usize < n {
        let x = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] < x {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = x
        i += 1usize
    }
    var u = 0usize
    i = 0usize
    while i + 1usize < n {
        if i == 0usize || srt[i] != srt[u - 1usize] {
            srt[u] = srt[i]
            u += 1usize
        }
        i += 1usize
    }
    var half = 1.0e300f64
    i = 0usize
    while i + 1usize < u {
        let g = srt[i] - srt[i + 1usize]
        if i == 0usize || g < half * 2.0f64 { half = g / 2.0f64 }
        i += 1usize
    }
    let (hs, e2) = mem.alloc[f64](a, u + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (ks, e3) = mem.alloc[usize](a, u + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (scratch, e4) = mem.alloc[i32](a, n)
    if e4 != ok { ret (zero, e4) }
    hs[0usize] = srt[0usize] + half
    i = 0usize
    while i < u {
        hs[i + 1usize] = srt[i] - half
        i += 1usize
    }
    i = 0usize
    while i <= u {
        let (c, e5) = cut_dfs(a, d, hs[i], scratch)
        if e5 != ok { ret (zero, e5) }
        ks[i] = c
        i += 1usize
    }
    ks[0usize] = 1usize
    ks[u] = n
    ret (Hpk { k: ks, h: hs }, ok)
}

// dendextend cutree.dendrogram with try_cutree_hclust: when the root is the highest node the tree is converted to an hclust (stats
// as.hclust.dendrogram: the nodes numbered in preorder, sorted by height, ties from the later node first) and stats::cutree's merge walk
// answers the clusters, by leaf value, which are read out by position
fn cutree_hclust(a: *mem.Arena, d: *const Dend, k: usize, out: []i32) -> err {
    let n = d.n
    let m = n - 1usize
    let (pre, e1) = mem.alloc[i32](a, 2usize * n - 1usize)
    let (jof, e2) = mem.alloc[usize](a, m)
    let (nodeof, e3) = mem.alloc[usize](a, m)
    let (ii, e4) = mem.alloc[usize](a, m)
    let (rank, e5) = mem.alloc[usize](a, m)
    let (ma, e6) = mem.alloc[i32](a, m)
    let (mb, e7) = mem.alloc[i32](a, m)
    let (mnr, e8) = mem.alloc[i32](a, n + 1usize)
    let (sing, e9) = mem.alloc[bool](a, n + 1usize)
    let (z, e10) = mem.alloc[i32](a, m + 2usize)
    let (lab, e11) = mem.alloc[i32](a, n + 1usize)
    let (ord, e12) = mem.alloc[i32](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret e7 }
    let e13 = preorder(a, d, pre)
    if e13 != ok { ret e13 }
    var j = 0usize
    var i = 0usize
    while i < 2usize * n - 1usize {
        if usize(pre[i]) >= n {
            jof[usize(pre[i]) - n] = j
            nodeof[j] = usize(pre[i]) - n
            j += 1usize
        }
        i += 1usize
    }
    // ii: the indices by height descending (ties in preorder), reversed: a stable insertion sort of descending order then flipped
    i = 0usize
    while i < m {
        ii[i] = i
        i += 1usize
    }
    i = 1usize
    while i < m {
        let x = ii[i]
        var q = i
        while q > 0usize && d.hgt[nodeof[ii[q - 1usize]]] < d.hgt[nodeof[x]] {
            ii[q] = ii[q - 1usize]
            q -= 1usize
        }
        ii[q] = x
        i += 1usize
    }
    i = 0usize
    while i < m / 2usize {
        let t = ii[i]
        ii[i] = ii[m - 1usize - i]
        ii[m - 1usize - i] = t
        i += 1usize
    }
    i = 0usize
    while i < m {
        rank[ii[i]] = i
        i += 1usize
    }
    i = 0usize
    while i < m {
        let s = nodeof[ii[i]]
        let c1 = d.ca[s]
        let c2 = d.cb[s]
        if usize(c1) < n { ma[i] = 0i32 - d.val[usize(c1)] } else { ma[i] = i32(rank[jof[usize(c1) - n]] + 1usize) }
        if usize(c2) < n { mb[i] = 0i32 - d.val[usize(c2)] } else { mb[i] = i32(rank[jof[usize(c2) - n]] + 1usize) }
        i += 1usize
    }
    // stats::cutree's C walk
    i = 1usize
    while i <= n {
        sing[i] = true
        mnr[i] = 0i32
        lab[i] = i32(i)
        i += 1usize
    }
    var step = 1usize
    while step < n {
        var m1 = ma[step - 1usize]
        var m2 = mb[step - 1usize]
        if m1 < 0i32 && m2 < 0i32 {
            mnr[usize(0i32 - m1)] = i32(step)
            mnr[usize(0i32 - m2)] = i32(step)
            sing[usize(0i32 - m1)] = false
            sing[usize(0i32 - m2)] = false
        } else if m1 < 0i32 || m2 < 0i32 {
            var atom = 0usize
            if m1 < 0i32 {
                atom = usize(0i32 - m1)
                m1 = m2
            } else {
                atom = usize(0i32 - m2)
            }
            var l = 1usize
            while l <= n {
                if mnr[l] == m1 { mnr[l] = i32(step) }
                l += 1usize
            }
            mnr[atom] = i32(step)
            sing[atom] = false
        } else {
            var l = 1usize
            while l <= n {
                if mnr[l] == m1 || mnr[l] == m2 { mnr[l] = i32(step) }
                l += 1usize
            }
        }
        if n - step == k {
            var l = 0usize
            while l <= m + 1usize {
                z[l] = 0i32
                l += 1usize
            }
            var nclust = 0i32
            l = 1usize
            while l <= n {
                if sing[l] {
                    nclust += 1i32
                    lab[l] = nclust
                } else {
                    // a cluster number (a merge row) outside the table would be R reading past its work array; none is produced by a valid tree
                    if mnr[l] >= 0i32 && usize(mnr[l]) <= m + 1usize {
                        if z[usize(mnr[l])] == 0i32 {
                            nclust += 1i32
                            z[usize(mnr[l])] = nclust
                        }
                        lab[l] = z[usize(mnr[l])]
                    }
                }
                l += 1usize
            }
        }
        step += 1usize
    }
    let e14 = order_values(a, d, ord)
    if e14 != ok { ret e14 }
    i = 0usize
    while i < n {
        out[i] = lab[usize(ord[i])]
        i += 1usize
    }
    ret ok
}

// cutree(dend, k, order_clusters_as_data = FALSE, use_labels_not_values = FALSE): the cluster of each leaf by position. Without a root
// that is the highest node the cut is dendextend's cutree_1k (a height from heights_per_k, the first named k), and a k no height gives
// is R's NA turned to 0: every leaf in cluster 0. The bool is always true.
fn cutree_pos(a: *mem.Arena, d: *const Dend, k: usize, hp: Hpk, out: []i32) -> (bool, err) {
    let n = d.n
    var i = 0usize
    var top = true
    while i + 1usize < n {
        if d.hgt[i] > d.hgt[n - 2usize] { top = false }
        i += 1usize
    }
    if top {
        let e0 = cutree_hclust(a, d, k, out)
        ret (true, e0)
    }
    i = 0usize
    if k == 1usize {
        while i < n {
            out[i] = 1i32
            i += 1usize
        }
        ret (true, ok)
    }
    if k == n {
        while i < n {
            out[i] = i32(i + 1usize)
            i += 1usize
        }
        ret (true, ok)
    }
    var j = 0usize
    while j < hp.k.len {
        if hp.k[j] == k {
            let (c, e) = cut_dfs(a, d, hp.h[j], out)
            if e != ok { ret (false, e) }
            if hp.h[j] > d.hgt[n - 2usize] {
                i = 0usize
                while i < n {
                    out[i] = 1i32
                    i += 1usize
                }
            }
            if c == n {
                i = 0usize
                while i < n {
                    out[i] = i32(i + 1usize)
                    i += 1usize
                }
            }
            ret (true, ok)
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = 0i32
        i += 1usize
    }
    ret (true, ok)
}

// all_couple_rotations_at_k: the tree itself, then for every cluster of k - 1 holding several clusters of k, the tree with each pair of those flipped
fn all_couple_rotations_at_k(a: *mem.Arena, d: *const Dend, k0: usize, hp: Hpk) -> ([]Dend, err) {
    let n = d.n
    let (kc, e1) = mem.alloc[i32](a, n)
    if e1 != ok { ret (zero, e1) }
    let (km, e2) = mem.alloc[i32](a, n)
    if e2 != ok { ret (zero, e2) }
    let (ord, e3) = mem.alloc[i32](a, n)
    if e3 != ok { ret (zero, e3) }
    let e4 = order_values(a, d, ord)
    if e4 != ok { ret (zero, e4) }
    var k = k0
    let (okk, e5) = cutree_pos(a, d, k, hp, kc)
    if e5 != ok { ret (zero, e5) }
    let (one, e6) = mem.alloc[Dend](a, 1usize)
    if e6 != ok { ret (zero, e6) }
    one[0usize] = *d
    if !okk { ret (one, ok) }
    var okm = false
    while !okm {
        if k < 2usize { ret (one, ok) }
        let (o2, e7) = cutree_pos(a, d, k - 1usize, hp, km)
        if e7 != ok { ret (zero, e7) }
        okm = o2
        if !okm { k -= 1usize }
    }
    // the pairs: for each cluster of k - 1 in order of appearance, the clusters of k inside it in order of appearance, taken two at a time
    let (pa, e8) = mem.alloc[i32](a, n * n)
    if e8 != ok { ret (zero, e8) }
    let (pb, e9) = mem.alloc[i32](a, n * n)
    if e9 != ok { ret (zero, e9) }
    let (seen, e10) = mem.alloc[bool](a, n + 1usize)
    if e10 != ok { ret (zero, e10) }
    let (inb, e11) = mem.alloc[i32](a, n)
    if e11 != ok { ret (zero, e11) }
    var np = 0usize
    var p = 0usize
    while p < n {
        // the first position of a k - 1 cluster starts its turn
        var first = true
        var q = 0usize
        while q < p {
            if km[q] == km[p] { first = false }
            q += 1usize
        }
        if first {
            var m = 0usize
            q = 0usize
            while q < n {
                if km[q] == km[p] {
                    var dup = false
                    var r = 0usize
                    while r < m {
                        if inb[r] == kc[q] { dup = true }
                        r += 1usize
                    }
                    if !dup {
                        inb[m] = kc[q]
                        m += 1usize
                    }
                }
                q += 1usize
            }
            var x = 0usize
            while x < m {
                var y = x + 1usize
                while y < m {
                    pa[np] = inb[x]
                    pb[np] = inb[y]
                    np += 1usize
                    y += 1usize
                }
                x += 1usize
            }
        }
        p += 1usize
    }
    let (lst, e12) = mem.alloc[Dend](a, np + 1usize)
    if e12 != ok { ret (zero, e12) }
    lst[0usize] = *d
    let (b1, e13) = mem.alloc[i32](a, n)
    if e13 != ok { ret (zero, e13) }
    let (b2, e14) = mem.alloc[i32](a, n)
    if e14 != ok { ret (zero, e14) }
    var j = 0usize
    while j < np {
        var c1 = 0usize
        var c2 = 0usize
        var q = 0usize
        while q < n {
            if kc[q] == pa[j] {
                b1[c1] = ord[q]
                c1 += 1usize
            }
            if kc[q] == pb[j] {
                b2[c2] = ord[q]
                c2 += 1usize
            }
            q += 1usize
        }
        let (f, e15) = flip_leaves(a, d, b1[0usize..c1], b2[0usize..c2])
        if e15 != ok { ret (zero, e15) }
        lst[j + 1usize] = f
        j += 1usize
    }
    ret (lst, ok)
}

// the sum of the terms, carried in two doubles so the answer does not depend on the order of the terms (R sums in long double)
fn exact_sum(x: []const f64) -> f64 {
    var s = 0.0f64
    var c = 0.0f64
    var i = 0usize
    while i < x.len {
        let t = s + x[i]
        let bp = t - s
        c += (s - (t - bp)) + (x[i] - bp)
        s = t
        i += 1usize
    }
    ret s + c
}

fn pow_abs(diff: f64, l: f64) -> f64 {
    var ad = diff
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    if ad == 0.0f64 { ret 0.0f64 }
    if ad == 1.0f64 { ret 1.0f64 }
    if l == 2.0f64 { ret ad * ad }
    ret math.pow[f64](ad, l)
}

// match_order_by_labels(change, template): every leaf of change takes the value its label has in template
fn match_order_by_labels(a: *mem.Arena, change: *const Dend, template: *const Dend) -> (Dend, err) {
    let (r, e) = clone(a, change)
    if e != ok { ret (zero, e) }
    var l = 0usize
    while l < change.n {
        r.val[l] = template.val[l]
        l += 1usize
    }
    ret (r, ok)
}

// entanglement(d1, d2, L, leaves_matching_method): the leaves of d1 are numbered 1..n from the left and those of d2 take the number of their
// match in d1 (by label, or by value when by_order), the answer the sum of |difference|^L over the same sum for a tree against its mirror
fn entanglement_dend(a: *mem.Arena, d1: *const Dend, d2: *const Dend, l0: f64, by_order: bool) -> f64 {
    let n = d1.n
    var l = l0
    if l == 0.0f64 { l = 1.0e-50f64 }
    let (lab1, e1) = mem.alloc[usize](a, n)
    let (lab2, e2) = mem.alloc[usize](a, n)
    let (pv, e3) = mem.alloc[usize](a, n)
    let (terms, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    if dfs_labels(a, d1, lab1) != ok { ret 0.0f64 / 0.0f64 }
    if dfs_labels(a, d2, lab2) != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        var key = lab1[i]
        if by_order { key = usize(d1.val[lab1[i]]) - 1usize }
        pv[key] = i + 1usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        var key = lab2[i]
        if by_order { key = usize(d2.val[lab2[i]]) - 1usize }
        terms[i] = pow_abs(f64(i + 1usize) - f64(pv[key]), l)
        i += 1usize
    }
    let num = exact_sum(terms)
    i = 0usize
    while i < n {
        terms[i] = pow_abs(f64(i + 1usize) - f64(n - i), l)
        i += 1usize
    }
    ret num / exact_sum(terms)
}

// untangle(d1, d2, method = "labels"): d2 rotated to the label order of d1; numeric_labels is R's case of labels that are numbers (the labels
// are then taken as positions), otherwise they are matched by name
fn untangle_labels(a: *mem.Arena, d1: *const Dend, d2: *const Dend, numeric_labels: bool) -> (Dend, err) {
    let n = d1.n
    let (lab1, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (zero, e1) }
    let (lab2, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (zero, e2) }
    let (pos, e3) = mem.alloc[i32](a, n)
    if e3 != ok { ret (zero, e3) }
    let e4 = dfs_labels(a, d1, lab1)
    if e4 != ok { ret (zero, e4) }
    let e5 = dfs_labels(a, d2, lab2)
    if e5 != ok { ret (zero, e5) }
    var i = 0usize
    while i < n {
        if numeric_labels {
            pos[i] = i32(lab1[i] + 1usize)
        } else {
            var j = 0usize
            while j < n {
                if lab2[j] == lab1[i] { pos[i] = i32(j + 1usize) }
                j += 1usize
            }
        }
        i += 1usize
    }
    let (r, e6) = rotate(a, d2, pos)
    ret (r, e6)
}

fn same_tree(d1: *const Dend, d2: *const Dend) -> bool {
    var i = 0usize
    while i + 1usize < d1.n {
        if d1.ca[i] != d2.ca[i] || d1.cb[i] != d2.cb[i] { ret false }
        i += 1usize
    }
    ret true
}

// untangle_step_rotate_1side(d1, d2_fixed, L, direction, k_seq): for each k (2..n, or n..2 when backward, or k_seq when it has entries) the
// flip of one pair of k-clusters inside a (k - 1)-cluster that most lowers the entanglement (the first of equals; no flip when none lowers it)
// is kept; an empty hp is computed from d1. Answers the better d1 and d2_fixed (d2 with the values of d1 under by_order).
fn untangle_step_rotate_1side(a: *mem.Arena, d1: *const Dend, d2: *const Dend, l: f64, backward: bool, kseq: []const usize, hp0: Hpk, by_order: bool) -> (Dend, Dend, err) {
    let n = d1.n
    var hp = hp0
    if hp.k.len == 0usize {
        let (h1, eh) = heights_per_k(a, d1)
        if eh != ok { ret (zero, zero, eh) }
        hp = h1
    }
    var fixed = *d2
    if by_order {
        let (m, em) = match_order_by_labels(a, d2, d1)
        if em != ok { ret (zero, zero, em) }
        fixed = m
    }
    var ks = kseq
    if kseq.len == 0usize {
        let (kk, ek) = mem.alloc[usize](a, n - 1usize)
        if ek != ok { ret (zero, zero, ek) }
        var i = 0usize
        while i + 1usize < n {
            kk[i] = i + 2usize
            if backward { kk[i] = n - i }
            i += 1usize
        }
        ks = kk
    }
    var best = *d1
    var ki = 0usize
    while ki < ks.len {
        let (lst, e1) = all_couple_rotations_at_k(a, &best, ks[ki], hp)
        if e1 != ok { ret (zero, zero, e1) }
        var bj = 0usize
        var be = entanglement_dend(a, &lst[0usize], &fixed, l, by_order)
        var j = 1usize
        while j < lst.len {
            let ej = entanglement_dend(a, &lst[j], &fixed, l, by_order)
            if ej < be {
                be = ej
                bj = j
            }
            j += 1usize
        }
        best = lst[bj]
        ki += 1usize
    }
    ret (best, fixed, ok)
}

// untangle_step_rotate_2side(d1, d2, L, direction, max_n_iterations): the one-sided step on d1, then on d2, repeated until the entanglement stops changing
fn untangle_step_rotate_2side(a: *mem.Arena, d1: *const Dend, d2: *const Dend, l: f64, backward: bool, max_iter: usize, kseq: []const usize) -> (Dend, Dend, err) {
    let (hp1, e1) = heights_per_k(a, d1)
    if e1 != ok { ret (zero, zero, e1) }
    let (hp2, e2) = heights_per_k(a, d2)
    if e2 != ok { ret (zero, zero, e2) }
    let (b1, f1, e3) = untangle_step_rotate_1side(a, d1, d2, l, backward, kseq, hp1, false)
    if e3 != ok { ret (zero, zero, e3) }
    var better1 = b1
    let (b2, f2, e4) = untangle_step_rotate_1side(a, d2, &better1, l, backward, kseq, hp2, false)
    if e4 != ok { ret (zero, zero, e4) }
    var better2 = b2
    var e_new = entanglement_dend(a, &better1, &better2, l, false)
    var e_old = e_new + 1.0f64
    var times = 1usize
    while times < max_iter && e_new != e_old {
        e_old = e_new
        let (l1, g1, e5) = untangle_step_rotate_1side(a, &better1, &better2, l, backward, kseq, hp1, false)
        if e5 != ok { ret (zero, zero, e5) }
        if same_tree(&l1, &better1) { break }
        better1 = l1
        let (l2, g2, e6) = untangle_step_rotate_1side(a, &better2, &better1, l, backward, kseq, hp2, false)
        if e6 != ok { ret (zero, zero, e6) }
        if same_tree(&l2, &better2) { break }
        better2 = l2
        e_new = entanglement_dend(a, &better1, &better2, l, false)
        times += 1usize
    }
    ret (better1, better2, ok)
}

// shuffle(dend): rotate(dend, sample(seq_len(n)))
fn shuffle(a: *mem.Arena, g: *rng.Rng, d: *const Dend) -> (Dend, err) {
    let n = d.n
    let (p, e) = rng.sample_int(a, g, i64(n), i64(n), false)
    if e != ok { ret (zero, e) }
    let (pos, e2) = mem.alloc[i32](a, n)
    if e2 != ok { ret (zero, e2) }
    var i = 0usize
    while i < n {
        pos[i] = i32(p[i])
        i += 1usize
    }
    let (r, e5) = rotate(a, d, pos)
    ret (r, e5)
}

// untangle_random_search(d1, d2, R, L, leaves_matching_method) after set.seed(seed): the best of R pairs of shuffles, strictly better than the input
fn untangle_random_search(a: *mem.Arena, d1: *const Dend, d2: *const Dend, reps: usize, l: f64, by_order: bool, seed: i64) -> (Dend, Dend, err) {
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    var o2 = *d2
    if by_order {
        let (m, em) = match_order_by_labels(a, d2, d1)
        if em != ok { ret (zero, zero, em) }
        o2 = m
    }
    var o1 = *d1
    var best = entanglement_dend(a, d1, &o2, l, by_order)
    var base2 = o2
    var r = 0usize
    while r < reps {
        let (s1, e1) = shuffle(a, &g, d1)
        if e1 != ok { ret (zero, zero, e1) }
        let (s2, e2) = shuffle(a, &g, &base2)
        if e2 != ok { ret (zero, zero, e2) }
        let cur = entanglement_dend(a, &s1, &s2, l, by_order)
        if cur < best {
            best = cur
            o1 = s1
            o2 = s2
        }
        r += 1usize
    }
    ret (o1, o2, ok)
}
