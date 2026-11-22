// R ape::nj: Saitou and Nei neighbour joining of a distance matrix; the 2n - 3 edge lengths are returned sorted ascending (the tree topology is not exposed), which fixes the total length, the unrooted tree up to leaf labelling and every order-free summary.
//
// ape::dist.dna over an alignment with global deletion (pairwise.deletion = FALSE, ape's default): sites
// where any sequence holds a non-ACGT code are dropped first, the base frequencies are counted over the
// whole matrix (ape calls base.freq before it deletes anything), and each model turns the pairwise counts
// into a distance (raw, JC69, K80, F81, F84, TN93, T92).
//
// ape::read.tree (Newick) and the two things the row compares through it: the tips' patristic distances
// (cophenetic.phylo) and the MRCA depth of each tip pair (getMRCA plus node.depth).
//
// Not here: write.tree and the Nexus reader, bionj, upgma, rooting, dist.topo and the tree comparisons,
// drop.tip, ace, rtree and rcoal, the rest of ape.

use e.math
use e.mem

// a dist.dna model this module does not port (ape's K81, GG95 and indel models)
error Unsupported
error TooSmall
error Malformed

// A Newick tree: node 0 is the root and the arrays are sized by the caller (2 * text.len + 1 entries is
// always enough). label[i] is a slice of the parsed text (empty for an unnamed node), edge[i] is the
// branch length to the parent, depth[i] the number of edges from the root, and tip[i] marks a leaf.
type Tree = struct {
    nn: usize,
    parent: []i64,
    edge: []f64,
    depth: []usize,
    label: []str,
    tip: []bool,
}

// The number of edges between node i and the root.
fn tree_depth_of(t: *Tree, i: usize) -> usize {
    var n = 0usize
    var at = i
    while t.parent[at] >= 0i64 {
        n += 1usize
        at = usize(t.parent[at])
    }
    ret n
}

// The summed branch length between node i and the root.
fn tree_path_len(t: *Tree, i: usize) -> f64 {
    var s = 0.0f64
    var at = i
    while t.parent[at] >= 0i64 {
        s += t.edge[at]
        at = usize(t.parent[at])
    }
    ret s
}

// The deepest node on both i's and j's path to the root.
fn tree_mrca(t: *Tree, i0: usize, j0: usize) -> usize {
    var i = i0
    var j = j0
    var di = t.depth[i]
    var dj = t.depth[j]
    while di > dj {
        i = usize(t.parent[i])
        di -= 1usize
    }
    while dj > di {
        j = usize(t.parent[j])
        dj -= 1usize
    }
    while i != j {
        i = usize(t.parent[i])
        j = usize(t.parent[j])
    }
    ret i
}

fn skip_space(s: str, i0: usize) -> usize {
    var i = i0
    while i < s.len && (s[i] == 32u8 || s[i] == 9u8 || s[i] == 10u8 || s[i] == 13u8) { i += 1usize }
    ret i
}

fn is_delim(b: u8) -> bool {
    ret b == 40u8 || b == 41u8 || b == 44u8 || b == 58u8 || b == 59u8 || b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8
}

// The branch length starting at s[i] (the caller has checked for the colon at i), and the index after it.
// The digits are collected into an exact integer and the value is one division (or multiplication) by an
// exactly representable power of ten, so a 10-digit length from write.tree reads back to the same double
// R's strtod gives - accumulating 0.1 steps instead drifts in the last bits (D7761).
fn read_length(s: str, i0: usize) -> (f64, usize, err) {
    var i = skip_space(s, i0 + 1usize)
    var neg = false
    if i < s.len && (s[i] == 45u8 || s[i] == 43u8) {
        neg = s[i] == 45u8
        i += 1usize
    }
    var mant = 0u64
    var digits = 0usize
    var dec = 0i64
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        if mant < 1000000000000000000u64 { mant = mant * 10u64 + u64(s[i] - 48u8) }
        digits += 1usize
        i += 1usize
    }
    if i < s.len && s[i] == 46u8 {
        i += 1usize
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            if mant < 1000000000000000000u64 {
                mant = mant * 10u64 + u64(s[i] - 48u8)
                dec += 1i64
            }
            digits += 1usize
            i += 1usize
        }
    }
    if digits == 0usize { ret (0.0f64, i, Malformed) }
    var exp10 = 0i64 - dec
    if i < s.len && (s[i] == 101u8 || s[i] == 69u8) {
        i += 1usize
        var eneg = false
        if i < s.len && (s[i] == 45u8 || s[i] == 43u8) {
            eneg = s[i] == 45u8
            i += 1usize
        }
        var e = 0i64
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            e = e * 10i64 + i64(s[i] - 48u8)
            i += 1usize
        }
        if eneg { e = 0i64 - e }
        exp10 += e
    }
    var value = f64(mant)
    var p = 1.0f64
    var k = 0i64
    while k < exp10 {
        p = p * 10.0f64
        k += 1i64
    }
    k = 0i64
    while k > exp10 {
        p = p * 10.0f64
        k -= 1i64
    }
    if exp10 >= 0i64 { value = value * p } else { value = value / p }
    if neg { value = 0.0f64 - value }
    ret (value, i, ok)
}

// ape::read.tree on one Newick string: labels may be bare (no quotes) and branch lengths are optional on
// both leaves and internal nodes. Returns the number of tips; the tips are numbered in the order they
// appear, so their node indices are the tip order ape reports. The Tree arrays must be the same length and
// at least 2 * text length + 1, which always holds a binary tree.
fn read_tree(s: str, t: *Tree) -> (usize, err) {
    let cap = t.parent.len
    var nn = 0usize
    var tips = 0usize
    var stack: [128]usize = zero
    var sp = 0usize
    var cur: i64 = 0i64
    var i = skip_space(s, 0usize)
    if i >= s.len { ret (0usize, Malformed) }
    if s[i] != 40u8 {
        // the whole tree is one bare label
        var b = i
        while b < s.len && !is_delim(s[b]) { b += 1usize }
        if b == i { ret (0usize, Malformed) }
        if cap < 1usize { ret (0usize, TooSmall) }
        t.parent[0usize] = -1i64
        t.edge[0usize] = 0.0f64
        t.label[0usize] = s[i..b]
        t.tip[0usize] = true
        t.depth[0usize] = 0usize
        t.nn = 1usize
        ret (1usize, ok)
    }
    // the root is node 0 and its child list is the first thing the text opens
    if cap < 1usize { ret (0usize, TooSmall) }
    t.parent[0usize] = -1i64
    t.edge[0usize] = 0.0f64
    t.label[0usize] = ""
    t.tip[0usize] = false
    nn = 1usize
    stack[0usize] = 0usize
    sp = 1usize
    i += 1usize
    while true {
        i = skip_space(s, i)
        if i >= s.len { ret (tips, Malformed) }
        if s[i] == 41u8 {
            // the innermost open internal node closes
            if sp == 0usize { ret (tips, Malformed) }
            sp -= 1usize
            let closed = stack[sp]
            i += 1usize
            i = skip_space(s, i)
            if i < s.len && s[i] == 58u8 {
                let (len, after, le) = read_length(s, i)
                if le != ok { ret (tips, le) }
                t.edge[closed] = len
                i = after
                i = skip_space(s, i)
            }
            cur = t.parent[closed]
            if i >= s.len || s[i] == 59u8 { break }
            if s[i] == 44u8 {
                i += 1usize
                continue
            }
            if s[i] == 41u8 { continue }
            ret (tips, Malformed)
        }
        if nn >= cap { ret (tips, TooSmall) }
        let node = nn
        nn += 1usize
        t.parent[node] = cur
        t.edge[node] = 0.0f64
        t.label[node] = ""
        t.tip[node] = false
        if s[i] == 40u8 {
            // an internal node opens a child list of its own
            if sp >= 128usize { ret (tips, TooSmall) }
            stack[sp] = node
            sp += 1usize
            cur = i64(node)
            i += 1usize
            continue
        }
        var b = i
        while b < s.len && !is_delim(s[b]) { b += 1usize }
        if b == i { ret (tips, Malformed) }
        t.label[node] = s[i..b]
        t.tip[node] = true
        tips += 1usize
        i = skip_space(s, b)
        if i < s.len && s[i] == 58u8 {
            let (len, after, le) = read_length(s, i)
            if le != ok { ret (tips, le) }
            t.edge[node] = len
            i = after
            i = skip_space(s, i)
        }
        if i >= s.len || s[i] == 59u8 { break }
        if s[i] == 44u8 {
            i += 1usize
            continue
        }
        if s[i] == 41u8 { continue }
        ret (tips, Malformed)
    }
    t.nn = nn
    var k = 0usize
    while k < nn {
        t.depth[k] = tree_depth_of(t, k)
        k += 1usize
    }
    ret (tips, ok)
}
// Recompute depth[] from the parent array, for a tree that was edited after parsing.
fn refresh_depths(t: *Tree) {
    var k = 0usize
    while k < t.nn {
        t.depth[k] = tree_depth_of(t, k)
        k += 1usize
    }
}

// ape::drop.tip: drop[] is indexed by tip order (the order the tips appear) and marks the tips to remove.
// A node left with a single child is collapsed and its branch length is added to that child's, which is
// what ape does; when the root is left with one child, that child becomes the root. The surviving tips keep
// their order. out receives the new tree (its arrays at least t.nn long) and the number of tips is returned.
fn drop_tips(t: *Tree, drop: []const bool, out: *Tree) -> (usize, err) {
    if out.parent.len < t.nn || out.edge.len < t.nn || out.depth.len < t.nn || out.label.len < t.nn || out.tip.len < t.nn {
        ret (0usize, TooSmall)
    }
    var i = 0usize
    while i < t.nn {
        out.parent[i] = t.parent[i]
        out.edge[i] = t.edge[i]
        out.depth[i] = t.depth[i]
        out.label[i] = t.label[i]
        out.tip[i] = t.tip[i]
        i += 1usize
    }
    out.nn = t.nn
    // -2 marks a removed node, which is distinct from the root's -1
    var tip_at = 0usize
    i = 0usize
    while i < t.nn {
        if t.tip[i] {
            if tip_at < drop.len && drop[tip_at] { out.parent[i] = -2i64 }
            tip_at += 1usize
        }
        i += 1usize
    }
    var changed = true
    var guard = 0usize
    while changed && guard <= t.nn {
        changed = false
        guard += 1usize
        i = 0usize
        while i < t.nn {
            if out.parent[i] != -2i64 {
                var children = 0usize
                var only = 0usize
                var k = 0usize
                while k < t.nn {
                    if out.parent[k] >= 0i64 && usize(out.parent[k]) == i {
                        children += 1usize
                        only = k
                    }
                    k += 1usize
                }
                if children == 1usize {
                    out.parent[only] = out.parent[i]
                    out.edge[only] = out.edge[only] + out.edge[i]
                    out.parent[i] = -2i64
                    changed = true
                }
            }
            i += 1usize
        }
    }
    // compact the living nodes, keeping their relative order
    var remap: [1024]usize = zero
    var live = 0usize
    i = 0usize
    while i < t.nn {
        if out.parent[i] != -2i64 {
            remap[i] = live
            live += 1usize
        } else {
            remap[i] = 0usize
        }
        i += 1usize
    }
    var par2: [1024]i64 = zero
    i = 0usize
    while i < t.nn {
        if out.parent[i] != -2i64 {
            let np = remap[i]
            par2[np] = -1i64
            if out.parent[i] >= 0i64 { par2[np] = i64(remap[usize(out.parent[i])]) }
        }
        i += 1usize
    }
    // write the compacted node set back, two arrays at a time
    var edge2: [1024]f64 = zero
    var lab2: [1024]str = zero
    var tip2: [1024]bool = zero
    var tips = 0usize
    i = 0usize
    while i < t.nn {
        if out.parent[i] != -2i64 {
            let np = remap[i]
            edge2[np] = out.edge[i]
            lab2[np] = out.label[i]
            tip2[np] = out.tip[i]
            if out.tip[i] { tips += 1usize }
        }
        i += 1usize
    }
    i = 0usize
    while i < live {
        out.parent[i] = par2[i]
        out.edge[i] = edge2[i]
        out.label[i] = lab2[i]
        out.tip[i] = tip2[i]
        i += 1usize
    }
    out.nn = live
    refresh_depths(out)
    ret (tips, ok)
}
// ape::cophenetic.phylo: the patristic distance between every pair of tips, in tip order (the order the
// tips appear in the Newick, which is ape's tip.label order). out is n by n row-major; returns n.
fn cophenetic(t: *Tree, out: []f64) -> (usize, err) {
    var tips: [128]usize = zero
    var n = 0usize
    var i = 0usize
    while i < t.nn {
        if t.tip[i] {
            if n >= 128usize { ret (n, TooSmall) }
            tips[n] = i
            n += 1usize
        }
        i += 1usize
    }
    if out.len < n * n { ret (n, TooSmall) }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let m = tree_mrca(t, tips[i], tips[j])
            out[i * n + j] = tree_path_len(t, tips[i]) + tree_path_len(t, tips[j]) - 2.0f64 * tree_path_len(t, m)
            j += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

// ape's base order for the LogDet contingency table is A, G, C, T (its DNAbin codes are 136, 72, 40, 24),
// while this module reads 0..3 as A, C, G, T, so the row and column indices are mapped here.
fn ape_base(code: u8) -> usize {
    if code == 0u8 { ret 0usize }
    if code == 2u8 { ret 1usize }
    if code == 1u8 { ret 2usize }
    ret 3usize
}

// ape's detFourByFour, the cofactor expansion of a 4 by 4 matrix in column-major order, kept in its own
// operation order so the LogDet value matches R's bit for bit where the table agrees.
fn det_four(x: [16]f64) -> f64 {
    let a33a44 = x[10usize] * x[15usize]
    let a34a43 = x[14usize] * x[11usize]
    let a34a42 = x[14usize] * x[7usize]
    let a32a44 = x[6usize] * x[15usize]
    let a32a43 = x[6usize] * x[11usize]
    let a33a42 = x[10usize] * x[7usize]
    let a34a41 = x[14usize] * x[3usize]
    let a31a44 = x[2usize] * x[15usize]
    let a31a43 = x[2usize] * x[11usize]
    let a33a41 = x[10usize] * x[3usize]
    let a31a42 = x[2usize] * x[7usize]
    let a32a41 = x[6usize] * x[3usize]
    var det = x[0usize] * x[5usize] * (a33a44 - a34a43) + x[0usize] * x[9usize] * (a34a42 - a32a44)
    det += x[0usize] * x[13usize] * (a32a43 - a33a42) + x[4usize] * x[9usize] * (a31a44 - a34a41)
    det += x[4usize] * x[13usize] * (a33a41 - a31a43) + x[4usize] * x[1usize] * (a34a43 - a33a44)
    det += x[8usize] * x[13usize] * (a31a42 - a32a41) + x[8usize] * x[1usize] * (a32a44 - a34a42)
    det += x[8usize] * x[5usize] * (a34a41 - a31a44) + x[12usize] * x[1usize] * (a33a42 - a32a43)
    det += x[12usize] * x[5usize] * (a31a43 - a33a41) + x[12usize] * x[9usize] * (a32a41 - a31a42)
    ret det
}

// The DNA codes this module reads: 0..3 are A, C, G and T and anything else is an unknown base or a gap.
// A site is kept only when every sequence has 0..3 there (ape's global deletion), and the distance of a
// pair counts the differing kept sites. model: 0 raw, 1 JC69, 2 K80 (transitions/transversions), 3 F81,
// 4 F84, 5 TN93 and 6 T92, all with the base frequencies of the whole matrix. out is n by n row-major with
// a zero diagonal.
fn dist_dna(a: *mem.Arena, x: []const u8, n: usize, l: usize, model: u8, out: []f64) -> err {
    if model > 7u8 { ret Unsupported }
    let (keep, e1) = mem.alloc[bool](a, l)
    if e1 != ok { ret e1 }
    var s = 0usize
    while s < l {
        var all_known = true
        var i = 0usize
        while i < n {
            if x[i * l + s] > 3u8 { all_known = false }
            i += 1usize
        }
        keep[s] = all_known
        s += 1usize
    }
    var kept = 0usize
    s = 0usize
    while s < l {
        if keep[s] { kept += 1usize }
        s += 1usize
    }
    // the base frequencies of the whole matrix, for F81: ape computes base.freq(x) before the deletion, so a
    // site that is later dropped still counts towards the frequencies (only its distance is lost)
    var freq: [4]f64 = zero
    var b = 0usize
    while b < 4usize {
        var count = 0.0f64
        var i = 0usize
        while i < n {
            s = 0usize
            while s < l {
                let code = x[i * l + s]
                if code <= 3u8 && usize(code) == b { count += 1.0f64 }
                s += 1usize
            }
            i += 1usize
        }
        freq[b] = count
        b += 1usize
    }
    var total = 0.0f64
    b = 0usize
    while b < 4usize {
        total += freq[b]
        b += 1usize
    }
    var e81 = 1.0f64
    var pi: [4]f64 = zero
    b = 0usize
    while b < 4usize {
        pi[b] = freq[b] / total
        e81 -= pi[b] * pi[b]
        b += 1usize
    }
    // the base-frequency constants F84 and T92 use, and TN93's three weights
    let a84 = (pi[0] * pi[2]) / (pi[0] + pi[2]) + (pi[1] * pi[3]) / (pi[1] + pi[3])
    let b84 = pi[0] * pi[2] + pi[1] * pi[3]
    let c84 = (pi[0] + pi[2]) * (pi[1] + pi[3])
    let wg = 2.0f64 * (pi[1] + pi[2]) * (1.0f64 - (pi[1] + pi[2]))
    let gr = pi[0] + pi[2]
    let gy = pi[1] + pi[3]
    let k1 = 2.0f64 * pi[0] * pi[2] / gr
    let k2 = 2.0f64 * pi[1] * pi[3] / gy
    let k3 = 2.0f64 * (gr * gy - pi[0] * pi[2] * gy / gr - pi[1] * pi[3] * gr / gy)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[i * n + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var diffs = 0usize
            var ts_purine = 0usize
            var ts_pyrimidine = 0usize
            s = 0usize
            while s < l {
                if keep[s] {
                    let ai = x[i * l + s]
                    let bj = x[j * l + s]
                    if ai != bj {
                        diffs += 1usize
                        // A<->G and C<->T are the two transition kinds TN93 weighs separately
                        if (ai == 0u8 && bj == 2u8) || (ai == 2u8 && bj == 0u8) { ts_purine += 1usize }
                        if (ai == 1u8 && bj == 3u8) || (ai == 3u8 && bj == 1u8) { ts_pyrimidine += 1usize }
                    }
                }
                s += 1usize
            }
            let len = f64(kept)
            let nd = f64(diffs)
            let ns = f64(ts_purine + ts_pyrimidine)
            var d = 0.0f64
            if model == 0u8 {
                d = nd / len
            } else if model == 1u8 {
                d = 0.0f64 - 0.75f64 * math.log[f64](1.0f64 - 4.0f64 * (nd / len) / 3.0f64)
            } else if model == 2u8 {
                let p = ns / len
                let q = (nd - ns) / len
                d = 0.0f64 - 0.5f64 * math.log[f64]((1.0f64 - 2.0f64 * p - q) * math.sqrt[f64](1.0f64 - 2.0f64 * q))
            } else if model == 3u8 {
                d = 0.0f64 - e81 * math.log[f64](1.0f64 - (nd / len) / e81)
            } else if model == 4u8 {
                let p = ns / len
                let q = (nd - ns) / len
                let f1 = 0.0f64 - 2.0f64 * a84 * math.log[f64](1.0f64 - p / (2.0f64 * a84) - (a84 - b84) * q / (2.0f64 * a84 * c84))
                let f2 = 2.0f64 * (a84 - b84 - c84) * math.log[f64](1.0f64 - q / (2.0f64 * c84))
                d = f1 + f2
            } else if model == 5u8 {
                let p1 = f64(ts_purine) / len
                let p2 = f64(ts_pyrimidine) / len
                let q = (nd - f64(ts_purine) - f64(ts_pyrimidine)) / len
                let w1 = 1.0f64 - p1 / k1 - q / (2.0f64 * gr)
                let w2 = 1.0f64 - p2 / k2 - q / (2.0f64 * gy)
                let w3 = 1.0f64 - q / (2.0f64 * gr * gy)
                d = 0.0f64 - k1 * math.log[f64](w1) - k2 * math.log[f64](w2) - k3 * math.log[f64](w3)
            } else if model == 6u8 {
                let p = ns / len
                let q = (nd - ns) / len
                d = 0.0f64 - wg * math.log[f64](1.0f64 - p / wg - q) - 0.5f64 * (1.0f64 - wg) * math.log[f64](1.0f64 - 2.0f64 * q)
            } else {
                // LogDet: the determinant of the 4 by 4 contingency table of the pair's retained sites,
                // built in ape's base order (A, G, C, T) and column-major, then -ln(det)/4 - ln(4)
                var ftab: [16]f64 = zero
                s = 0usize
                while s < l {
                    if keep[s] {
                        let row = ape_base(x[i * l + s])
                        let col = ape_base(x[j * l + s])
                        ftab[col * 4usize + row] = ftab[col * 4usize + row] + 1.0f64
                    }
                    s += 1usize
                }
                var t4 = 0usize
                while t4 < 16usize {
                    ftab[t4] = ftab[t4] / len
                    t4 += 1usize
                }
                d = 0.0f64 - math.log[f64](det_four(ftab)) / 4.0f64 - math.log[f64](4.0f64)
            }
            out[i * n + j] = d
            out[j * n + i] = d
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// d is n by n row-major (n >= 3); the edge lengths go into out (2n - 3 values)
fn nj(a: *mem.Arena, d: []const f64, n: usize, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, n * n)
    let (alive, e2) = mem.alloc[bool](a, n)
    let (r, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n * n {
        w[i] = d[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        alive[i] = true
        i += 1usize
    }
    var left = n
    var ne = 0usize
    while left > 3usize {
        i = 0usize
        while i < n {
            r[i] = 0.0f64
            if alive[i] {
                var j = 0usize
                while j < n {
                    if alive[j] { r[i] += w[i * n + j] }
                    j += 1usize
                }
            }
            i += 1usize
        }
        var bi = 0usize
        var bj = 0usize
        var best = 1.0e300f64
        i = 0usize
        while i < n {
            if alive[i] {
                var j = i + 1usize
                while j < n {
                    if alive[j] {
                        let q = f64(left - 2usize) * w[i * n + j] - r[i] - r[j]
                        if q < best {
                            best = q
                            bi = i
                            bj = j
                        }
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        let lf = f64(left - 2usize)
        let di = w[bi * n + bj] / 2.0f64 + (r[bi] - r[bj]) / (2.0f64 * lf)
        let dj = w[bi * n + bj] - di
        out[ne] = di
        out[ne + 1usize] = dj
        ne += 2usize
        // the new node replaces bi
        var k = 0usize
        while k < n {
            if alive[k] && k != bi && k != bj {
                let nd = (w[bi * n + k] + w[bj * n + k] - w[bi * n + bj]) / 2.0f64
                w[bi * n + k] = nd
                w[k * n + bi] = nd
            }
            k += 1usize
        }
        alive[bj] = false
        left -= 1usize
    }
    var p = 0usize
    var q = 0usize
    var s = 0usize
    i = 0usize
    while i < n {
        if alive[i] {
            if p == 0usize && q == 0usize && s == 0usize { p = i + 1usize } else if q == 0usize { q = i + 1usize } else { s = i + 1usize }
        }
        i += 1usize
    }
    let ip = p - 1usize
    let iq = q - 1usize
    let is = s - 1usize
    out[ne] = (w[ip * n + iq] + w[ip * n + is] - w[iq * n + is]) / 2.0f64
    out[ne + 1usize] = (w[ip * n + iq] + w[iq * n + is] - w[ip * n + is]) / 2.0f64
    out[ne + 2usize] = (w[ip * n + is] + w[iq * n + is] - w[ip * n + iq]) / 2.0f64
    // ascending
    i = 1usize
    while i < 2usize * n - 3usize {
        let v = out[i]
        var j = i
        while j > 0usize && out[j - 1usize] > v {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = v
        i += 1usize
    }
    ret ok
}
