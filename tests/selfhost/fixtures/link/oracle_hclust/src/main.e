// e.algo.stat.hclust against R's hclust. tests/oracle/hclust.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hclust`; the layout is at the top of scripts/r_oracle/groups/hclust.R.

use e.algo.stat.dendextend as de
use e.algo.stat.hclust as hc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn dmat(a: *mem.Arena, x: []const f64, n: usize, at: usize) -> []f64 {
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[at + 2usize * i] - x[at + 2usize * j]
            let dy = x[at + 1usize + 2usize * i] - x[at + 1usize + 2usize * j]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    ret d
}

fn pair(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[2usize])
    let k = usize(x[3usize])
    let d = dmat(a, x, n, 4usize)
    let (t1, e1) = hc.hclust(a, d, n, usize(x[0usize]))
    if e1 != ok { os.exit(6) }
    let (t2, e2) = hc.hclust(a, d, n, usize(x[1usize]))
    if e2 != ok { os.exit(7) }
    if str.eq(c.name, "corcoph") { ret hc.cor_cophenetic(a, &t1, &t2, n) }
    if str.eq(c.name, "bakers") { ret hc.cor_bakers_gamma(a, &t1, &t2, n) }
    if str.eq(c.name, "entang") { ret hc.entanglement(a, &t1, &t2, n, x[4usize + 2usize * n]) }
    let (l1, e3) = mem.alloc[usize](a, n)
    if e3 != ok { os.exit(8) }
    let (l2, e4) = mem.alloc[usize](a, n)
    if e4 != ok { os.exit(9) }
    if hc.cutree(a, &t1, n, k, l1) != ok { os.exit(10) }
    if hc.cutree(a, &t2, n, k, l2) != ok { os.exit(11) }
    let (fm, ef, vf, e5) = hc.fm_index(a, l1, l2)
    if e5 != ok { os.exit(12) }
    if str.eq(c.name, "fm") { ret fm }
    if str.eq(c.name, "fmE") { ret ef }
    ret vf
}

// d_* cases: as.dendrogram objects and dendextend untangling; the argument layout is at the end of scripts/r_oracle/groups/hclust.R
fn mkd(a: *mem.Arena, x: []const f64, n: usize, at: usize, method: usize) -> de.Dend {
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let ex = x[at + 2usize * i] - x[at + 2usize * j]
            let ey = x[at + 1usize + 2usize * i] - x[at + 1usize + 2usize * j]
            var v = math.sqrt[f64](ex * ex + ey * ey)
            if method == 6usize || method == 7usize { v = v * v }
            d[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
    let (t, e2) = hc.hclust(a, d, n, method)
    if e2 != ok { os.exit(6) }
    let (r, e3) = de.from_hclust(a, &t, n)
    if e3 != ok { os.exit(7) }
    ret r
}

fn perm_at(a: *mem.Arena, x: []const f64, n: usize, at: usize) -> []i32 {
    let (p, e) = mem.alloc[i32](a, n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        p[i] = i32(x[at + i])
        i += 1usize
    }
    ret p
}

fn wsum(a: *mem.Arena, d: *const de.Dend) -> f64 {
    let (o, e) = mem.alloc[i32](a, d.n)
    if e != ok { os.exit(5) }
    if de.order_values(a, d, o) != ok { os.exit(5) }
    var s = 0.0f64
    var i = 0usize
    while i < d.n {
        s += f64(o[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// which: 0 internal heights, 1 node keys (a leaf's value, an internal node's minus its members), 2 midpoints; each weighted by the position in the preorder
fn node_stat(a: *mem.Arena, d: *const de.Dend, which: usize) -> f64 {
    let n = d.n
    let (pre, e1) = mem.alloc[i32](a, 2usize * n - 1usize)
    let (mem_n, e2) = mem.alloc[usize](a, 2usize * n - 1usize)
    let (mid, e3) = mem.alloc[f64](a, 2usize * n - 1usize)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    if de.preorder(a, d, pre) != ok { os.exit(5) }
    de.members(a, d, mem_n)
    if de.midpoints(a, d, mid) != ok { os.exit(5) }
    var s = 0.0f64
    var idx = 0usize
    var i = 0usize
    while i < 2usize * n - 1usize {
        let node = usize(pre[i])
        if which == 1usize {
            var key = 0.0f64 - f64(mem_n[node])
            if node < n { key = f64(d.val[node]) }
            s += key * f64(i + 1usize)
        } else if node >= n {
            idx += 1usize
            if which == 0usize { s += d.hgt[node - n] * f64(idx) }
            if which == 2usize { s += mid[node] * f64(idx) }
        }
        i += 1usize
    }
    ret s
}

fn dend_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[2usize])
    let lab = x[5usize]
    let d1 = mkd(a, x, n, 8usize, usize(x[0usize]))
    let d2 = mkd(a, x, n, 8usize + 2usize * n, usize(x[1usize]))
    let perm1 = perm_at(a, x, n, 8usize + 4usize * n)
    let perm2 = perm_at(a, x, n, 8usize + 5usize * n)
    let kind = c.name
    var hp0: de.Hpk = zero
    var ks0: []usize = zero
    if str.eq(kind, "d_ord") { ret wsum(a, &d1) }
    if str.eq(kind, "d_h") { ret node_stat(a, &d1, 0usize) }
    if str.eq(kind, "d_k") { ret node_stat(a, &d1, 1usize) }
    if str.eq(kind, "d_mid") { ret node_stat(a, &d1, 2usize) }
    let (dr, er) = de.rotate(a, &d1, perm1)
    if er != ok { os.exit(8) }
    if str.eq(kind, "d_rot") { ret wsum(a, &dr) }
    if str.eq(kind, "d_rotk") { ret node_stat(a, &dr, 1usize) }
    if str.eq(kind, "d_rotmid") { ret node_stat(a, &dr, 2usize) }
    if str.eq(kind, "d_hpk") || str.eq(kind, "d_hpkn") {
        let (hp, eh) = de.heights_per_k(a, &d1)
        if eh != ok { os.exit(9) }
        var s = 0.0f64
        var j = 0usize
        while j < hp.k.len {
            if str.eq(kind, "d_hpk") { s += hp.h[j] * f64(j + 1usize) } else { s += f64(hp.k[j]) * f64(j + 1usize) }
            j += 1usize
        }
        ret s
    }
    if str.eq(kind, "d_all") || str.eq(kind, "d_alln") {
        let (hp, eh) = de.heights_per_k(a, &dr)
        if eh != ok { os.exit(9) }
        let (lst, el) = de.all_couple_rotations_at_k(a, &dr, usize(x[3usize]), hp)
        if el != ok { os.exit(10) }
        if str.eq(kind, "d_alln") { ret f64(lst.len) }
        var s = 0.0f64
        var j = 0usize
        while j < lst.len {
            s += f64(j + 1usize) * wsum(a, &lst[j])
            j += 1usize
        }
        ret s
    }
    if str.eq(kind, "d_mbl") {
        let (da, e1) = de.set_order(a, &d1, perm1)
        if e1 != ok { os.exit(8) }
        let (r, e2) = de.match_order_by_labels(a, &d2, &da)
        if e2 != ok { os.exit(8) }
        ret wsum(a, &r)
    }
    if str.eq(kind, "d_ent") {
        let (da, e1) = de.set_order(a, &d1, perm1)
        if e1 != ok { os.exit(8) }
        let (db, e2) = de.set_order(a, &d2, perm2)
        if e2 != ok { os.exit(8) }
        ret de.entanglement_dend(a, &da, &db, x[3usize], x[4usize] == 1.0f64)
    }
    if str.eq(kind, "d_ulab") {
        let (r, e1) = de.untangle_labels(a, &d1, &d2, lab == 0.0f64)
        if e1 != ok { os.exit(8) }
        ret wsum(a, &r)
    }
    let l = x[3usize]
    if str.eq(kind, "d_u1a") || str.eq(kind, "d_u1b") || str.eq(kind, "d_u1e") {
        let by_order = x[6usize] == 1.0f64
        var d2s = d2
        if by_order {
            let (ds, e1) = de.set_order(a, &d2, perm2)
            if e1 != ok { os.exit(8) }
            d2s = ds
        }
        let (b, f, e2) = de.untangle_step_rotate_1side(a, &d1, &d2s, l, x[4usize] == 1.0f64, ks0, hp0, by_order)
        if e2 != ok { os.exit(11) }
        if str.eq(kind, "d_u1a") { ret wsum(a, &b) }
        if str.eq(kind, "d_u1b") { ret wsum(a, &f) }
        ret de.entanglement_dend(a, &b, &f, l, by_order)
    }
    if str.eq(kind, "d_u2a") || str.eq(kind, "d_u2b") || str.eq(kind, "d_u2e") {
        let (b1, b2, e2) = de.untangle_step_rotate_2side(a, &d1, &d2, l, x[4usize] == 1.0f64, usize(x[6usize]), ks0)
        if e2 != ok { os.exit(12) }
        if str.eq(kind, "d_u2a") { ret wsum(a, &b1) }
        if str.eq(kind, "d_u2b") { ret wsum(a, &b2) }
        ret de.entanglement_dend(a, &b1, &b2, l, false)
    }
    // d_ura, d_urb, d_ure
    let by_order = x[4usize] == 1.0f64
    var d2s = d2
    if by_order {
        let (ds, e1) = de.set_order(a, &d2, perm2)
        if e1 != ok { os.exit(8) }
        d2s = ds
    }
    let (r1, r2, e3) = de.untangle_random_search(a, &d1, &d2s, usize(x[6usize]), l, by_order, i64(x[7usize]))
    if e3 != ok { os.exit(13) }
    if str.eq(kind, "d_ura") { ret wsum(a, &r1) }
    if str.eq(kind, "d_urb") { ret wsum(a, &r2) }
    ret de.entanglement_dend(a, &r1, &r2, l, by_order)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "d_") { ret dend_answer(a, c) }
    if str.eq(c.name, "fm") || str.eq(c.name, "fmE") || str.eq(c.name, "fmV") || str.eq(c.name, "corcoph") || str.eq(c.name, "entang") || str.eq(c.name, "bakers") { ret pair(a, c) }
    let x = c.args
    let method = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[3usize + 2usize * i] - x[3usize + 2usize * j]
            let dy = x[4usize + 2usize * i] - x[4usize + 2usize * j]
            var v = math.sqrt[f64](dx * dx + dy * dy)
            if method == 6usize || method == 7usize { v = dx * dx + dy * dy }
            d[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
    let (t, e2) = hc.hclust(a, d, n, method)
    if e2 != ok { os.exit(6) }
    let kind = c.name
    var s = 0.0f64
    if str.eq(kind, "ac") { ret hc.agnes_ac(a, &t, n) }
    if str.eq(kind, "agh") {
        i = 0usize
        while i < n - 1usize {
            s += t.height[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "height") {
        i = 0usize
        while i < n - 1usize {
            s += t.height[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "merge") {
        i = 0usize
        while i < n - 1usize {
            s += f64(t.merge_a[i]) * f64(2usize * i + 1usize) + f64(t.merge_b[i]) * f64(2usize * i + 2usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "ladr") || str.eq(kind, "ladl") {
        // ladderize(as.dendrogram(h), right): the leaf order, answered as sum of leaf * (position + 1)
        let (lo, le) = mem.alloc[usize](a, n)
        if le != ok { os.exit(8) }
        if hc.ladderize_order(a, &t, n, str.eq(kind, "ladr"), lo) != ok { os.exit(9) }
        i = 0usize
        while i < n {
            s += f64(lo[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "order") {
        i = 0usize
        while i < n {
            s += f64(t.order[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "cuth") {
        let (lab2, e5) = mem.alloc[usize](a, n)
        if e5 != ok { os.exit(7) }
        let e6 = hc.cutree_h(a, &t, n, x[3usize + 2usize * n], lab2)
        if e6 != ok { os.exit(8) }
        i = 0usize
        while i < n {
            s += f64(lab2[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "cut") {
        let (lab, e3) = mem.alloc[usize](a, n)
        if e3 != ok { os.exit(7) }
        let e4 = hc.cutree(a, &t, n, k, lab)
        if e4 != ok { os.exit(8) }
        i = 0usize
        while i < n {
            s += f64(lab[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    // coph: pairs in the column-major upper triangle order of R's lower-triangle dist: (2,1), (3,1), ..., then (3,2), ...
    var pos = 1usize
    var col = 0usize
    while col < n {
        var row = col + 1usize
        while row < n {
            s += hc.cophenetic(a, &t, n, row, col) * f64(pos)
            pos += 1usize
            row += 1usize
        }
        col += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hclust.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
