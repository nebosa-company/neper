// R clue consensus: cl_consensus of an ensemble of partitions by the soft Euclidean method "SE" (alternating optimisation from a given start, control = list(start = M0)) and by
// "DWH" (Dimitriadou, Weingessel and Hornik, in the given order), cl_consensus of hclust trees by "majority" (the classes in more than half of the weight, as an ultrametric), and
// cl_medoid of hard partitions under the euclidean dissimilarity. Memberships are n by k row-major, B of them one after another, every partition padded to k columns.

use e.algo.stat.clue as cl
use e.algo.stat.cluelsap as ls
use e.algo.stat.hclust as hc
use e.mem

error Malformed

// match_memberships(M, N): the columns of mi permuted by solve_LSAP(crossprod(N, mi), maximum = TRUE)
fn align(a: *mem.Arena, nm: []const f64, mi: []const f64, n: usize, k: usize, out: []f64) -> err {
    let (cross, e0) = mem.alloc[f64](a, k * k)
    let (asg, e1) = mem.alloc[usize](a, k)
    if e0 != ok || e1 != ok { ret mem.Full }
    var r = 0usize
    while r < k {
        var c = 0usize
        while c < k {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += nm[i * k + r] * mi[i * k + c]
                i += 1usize
            }
            cross[r * k + c] = s
            c += 1usize
        }
        r += 1usize
    }
    let (v, e2) = ls.solve_lsap(a, cross, k, k, true, asg)
    if e2 != ok { ret e2 }
    let _ = v
    r = 0usize
    while r < k {
        var i = 0usize
        while i < n {
            out[i * k + r] = mi[i * k + asg[r]]
            i += 1usize
        }
        r += 1usize
    }
    ret ok
}

// the zero-sum columns of mm dropped and zeros appended in their place (clue's .cl_membership_from_memberships)
fn tidy(mm: []f64, n: usize, k: usize) {
    var dst = 0usize
    var c = 0usize
    while c < k {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += mm[i * k + c]
            i += 1usize
        }
        if s > 0.0f64 {
            if dst != c {
                i = 0usize
                while i < n {
                    mm[i * k + dst] = mm[i * k + c]
                    i += 1usize
                }
            }
            dst += 1usize
        }
        c += 1usize
    }
    while dst < k {
        var i = 0usize
        while i < n {
            mm[i * k + dst] = 0.0f64
            i += 1usize
        }
        dst += 1usize
    }
}

// cl_consensus(method = "SE", weights = w, control = list(start = start)): answers the objective value at the stopping point; the consensus membership goes to out (n by k)
fn consensus_se(a: *mem.Arena, mems: []const f64, w: []const f64, bn: usize, n: usize, k: usize, start: []const f64, maxiter: usize, reltol: f64, out: []f64) -> (f64, err) {
    let sz = n * k
    let (mm, e0) = mem.alloc[f64](a, bn * sz)
    let (tmp, e1) = mem.alloc[f64](a, sz)
    let (wn, e2) = mem.alloc[f64](a, bn)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var ws = 0.0f64
    var b = 0usize
    while b < bn {
        ws += w[b]
        b += 1usize
    }
    b = 0usize
    while b < bn {
        wn[b] = w[b] / ws
        b += 1usize
    }
    var i = 0usize
    while i < bn * sz {
        mm[i] = mems[i]
        i += 1usize
    }
    i = 0usize
    while i < sz {
        out[i] = start[i]
        i += 1usize
    }
    b = 0usize
    while b < bn {
        let e = align(a, out, mm[b * sz..(b + 1usize) * sz], n, k, tmp)
        if e != ok { ret (0.0f64, e) }
        i = 0usize
        while i < sz {
            mm[b * sz + i] = tmp[i]
            i += 1usize
        }
        b += 1usize
    }
    var old = value(mm, wn, out, bn, sz)
    var fresh = old
    var iter = 1usize
    while iter <= maxiter {
        i = 0usize
        while i < sz {
            var s = 0.0f64
            b = 0usize
            while b < bn {
                s += mm[b * sz + i] * wn[b]
                b += 1usize
            }
            out[i] = s
            i += 1usize
        }
        b = 0usize
        while b < bn {
            let e = align(a, out, mm[b * sz..(b + 1usize) * sz], n, k, tmp)
            if e != ok { ret (0.0f64, e) }
            i = 0usize
            while i < sz {
                mm[b * sz + i] = tmp[i]
                i += 1usize
            }
            b += 1usize
        }
        fresh = value(mm, wn, out, bn, sz)
        var d = old - fresh
        if d < 0.0f64 { d = 0.0f64 - d }
        var ao = old
        if ao < 0.0f64 { ao = 0.0f64 - ao }
        if d < reltol * (ao + reltol) { iter = maxiter + 1usize } else {
            old = fresh
            iter += 1usize
        }
    }
    // .stochastify: negative entries to zero, rows to sum one
    i = 0usize
    while i < n {
        var s = 0.0f64
        var c = 0usize
        while c < k {
            if out[i * k + c] < 0.0f64 { out[i * k + c] = 0.0f64 }
            s += out[i * k + c]
            c += 1usize
        }
        c = 0usize
        while c < k {
            out[i * k + c] = out[i * k + c] / s
            c += 1usize
        }
        i += 1usize
    }
    let obj = value(mm, wn, out, bn, sz)
    tidy(out, n, k)
    ret (obj, ok)
}

fn value(mm: []const f64, wn: []const f64, m: []const f64, bn: usize, sz: usize) -> f64 {
    var v = 0.0f64
    var b = 0usize
    while b < bn {
        var s = 0.0f64
        var i = 0usize
        while i < sz {
            let d = mm[b * sz + i] - m[i]
            s += d * d
            i += 1usize
        }
        v += wn[b] * s
        b += 1usize
    }
    ret v
}

// cl_consensus(method = "DWH", weights = w, control = list(order = 1:B))
fn consensus_dwh(a: *mem.Arena, mems: []const f64, w: []const f64, bn: usize, n: usize, k: usize, out: []f64) -> err {
    let sz = n * k
    let (tmp, e0) = mem.alloc[f64](a, sz)
    if e0 != ok { ret mem.Full }
    var i = 0usize
    while i < sz {
        out[i] = mems[i]
        i += 1usize
    }
    var cum = w[0usize]
    var b = 1usize
    while b < bn {
        cum += w[b]
        let s = w[b] / cum
        let e = align(a, out, mems[b * sz..(b + 1usize) * sz], n, k, tmp)
        if e != ok { ret e }
        i = 0usize
        while i < sz {
            out[i] = (1.0f64 - s) * out[i] + s * tmp[i]
            i += 1usize
        }
        b += 1usize
    }
    tidy(out, n, k)
    ret ok
}

// the class sets of a tree: n singletons then one per merge, each a row of n flags in cls ((2 n - 1) rows)
fn tree_classes(t: *const hc.Tree, n: usize, cls: []bool) {
    var z = 0usize
    while z < (2usize * n - 1usize) * n {
        cls[z] = false
        z += 1usize
    }
    var j = 0usize
    while j < n {
        cls[j * n + j] = true
        j += 1usize
    }
    var s = 0usize
    while s + 1usize < n {
        let row = n + s
        var side = 0usize
        while side < 2usize {
            var c = t.merge_a[s]
            if side == 1usize { c = t.merge_b[s] }
            var src = 0usize
            if c < 0i32 { src = usize(0i32 - c) - 1usize } else { src = n + usize(c) - 1usize }
            var q = 0usize
            while q < n {
                if cls[src * n + q] { cls[row * n + q] = true }
                q += 1usize
            }
            side += 1usize
        }
        s += 1usize
    }
}

fn same_set(x: []const bool, y: []const bool, n: usize) -> bool {
    var q = 0usize
    while q < n {
        if x[q] != y[q] { ret false }
        q += 1usize
    }
    ret true
}

fn subset(x: []const bool, y: []const bool, n: usize) -> bool {
    var q = 0usize
    while q < n {
        if x[q] && !y[q] { ret false }
        q += 1usize
    }
    ret true
}

fn card(x: []const bool, n: usize) -> usize {
    var c = 0usize
    var q = 0usize
    while q < n {
        if x[q] { c += 1usize }
        q += 1usize
    }
    ret c
}

// cl_consensus(trees, method = "majority", weights = w) with p = 1/2: the ultrametric (n by n, row-major) of the classes held by more than half of the weight, its heights
// the depth of nesting of the classes
fn consensus_majority(a: *mem.Arena, trees: []const hc.Tree, w: []const f64, n: usize, d: []f64) -> err {
    let bn = trees.len
    let rows = 2usize * n - 1usize
    let (all, e0) = mem.alloc[bool](a, bn * rows * n)
    let (gam, e1) = mem.alloc[f64](a, bn * rows)
    let (uniq, e2) = mem.alloc[usize](a, bn * rows)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var ws = 0.0f64
    var b = 0usize
    while b < bn {
        ws += w[b]
        tree_classes(&trees[b], n, all[b * rows * n..(b + 1usize) * rows * n])
        b += 1usize
    }
    // distinct classes in first-seen order, each with its weight
    var nu = 0usize
    b = 0usize
    while b < bn {
        var r = 0usize
        while r < rows {
            let idx = b * rows + r
            var found = false
            var u = 0usize
            while u < nu {
                if same_set(all[uniq[u] * n..uniq[u] * n + n], all[idx * n..idx * n + n], n) {
                    found = true
                    gam[u] += w[b] / ws
                }
                u += 1usize
            }
            if !found {
                uniq[nu] = idx
                gam[nu] = w[b] / ws
                nu += 1usize
            }
            r += 1usize
        }
        b += 1usize
    }
    let (kept, e3) = mem.alloc[usize](a, nu)
    let (hgt, e4) = mem.alloc[f64](a, nu)
    if e3 != ok || e4 != ok { ret mem.Full }
    var top = 0.0f64
    var u = 0usize
    while u < nu {
        if gam[u] > top { top = gam[u] }
        u += 1usize
    }
    var nk = 0usize
    u = 0usize
    while u < nu {
        if gam[u] / top > 0.5f64 {
            kept[nk] = uniq[u]
            nk += 1usize
        }
        u += 1usize
    }
    // heights by increasing class size
    var size = 1usize
    while size <= n {
        var c = 0usize
        while c < nk {
            let cs = all[kept[c] * n..kept[c] * n + n]
            if card(cs, n) == size {
                var h = 0.0f64
                if size > 1usize {
                    var e = 0usize
                    while e < nk {
                        let es = all[kept[e] * n..kept[e] * n + n]
                        let ce = card(es, n)
                        if ce < size && subset(es, cs, n) && hgt[e] + 1.0f64 > h { h = hgt[e] + 1.0f64 }
                        e += 1usize
                    }
                }
                hgt[c] = h
            }
            c += 1usize
        }
        size += 1usize
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var best = n + 1usize
            var bh = 0.0f64
            var c = 0usize
            while c < nk {
                let cs = all[kept[c] * n..kept[c] * n + n]
                if cs[i] && cs[j] {
                    let cc = card(cs, n)
                    if cc < best {
                        best = cc
                        bh = hgt[c]
                    }
                }
                c += 1usize
            }
            d[i * n + j] = bh
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// cl_medoid(partitions, "euclidean") of hard partitions (labels 1..k, bn of them, n objects each, one after another in labs): the 0-based index of the one with the least
// summed dissimilarity to all, the first on ties as which.min
fn medoid(a: *mem.Arena, labs: []const usize, bn: usize, n: usize, k: usize) -> (usize, err) {
    var best = 0usize
    var bv = 0.0f64
    var i = 0usize
    while i < bn {
        var s = 0.0f64
        var j = 0usize
        while j < bn {
            if i != j {
                let (v, e) = cl.euclid_partition(a, labs[i * n..(i + 1usize) * n], labs[j * n..(j + 1usize) * n], n, k)
                if e != ok { ret (0usize, e) }
                s += v
            }
            j += 1usize
        }
        if i == 0usize || s < bv {
            bv = s
            best = i
        }
        i += 1usize
    }
    ret (best, ok)
}
