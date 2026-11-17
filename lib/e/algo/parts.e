// R partitions, the integer-partition part: `P` and `Q` (the counts of all and of distinct-part partitions),
// `parts` (every partition in decreasing lexicographic order), `restrictedparts` (at most m parts) and
// `diffparts` (distinct parts), the last two ordered by the number of parts and then lexicographically
// decreasing, as R prints them. A partition is written as a column of `rows` entries, largest part first, padded
// with zeros.
//
// Not here: compositions, setparts and blockparts (their order is a Gray-code-like sequence of its own), the
// big-integer counts past 2^53, `conjugate` and the other helpers.

use e.mem

// P(n), the number of partitions of n; q[k] receives the number of distinct-part partitions of k for k <= n
fn count(a: *mem.Arena, n: usize, distinct: bool) -> (f64, err) {
    let (t, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i <= n {
        t[i] = 0.0f64
        i += 1usize
    }
    t[0usize] = 1.0f64
    var part = 1usize
    while part <= n {
        if distinct {
            var s = n
            while s >= part {
                t[s] += t[s - part]
                s -= 1usize
            }
        } else {
            var s = part
            while s <= n {
                t[s] += t[s - part]
                s += 1usize
            }
        }
        part += 1usize
    }
    ret (t[n], ok)
}

// enumeration state: `cur` holds the partition under construction, `out` the finished columns
type Gen = struct { out: []f64, rows: usize, cols: usize, cur: []f64, distinct: bool }

// append partitions of `rem` into exactly `left` more parts, each at most `maxp` (and below the previous part when
// distinct), lexicographically decreasing; depth is the index of the next part
fn emit(g: *Gen, depth: usize) {
    var k = 0usize
    while k < g.rows {
        if k < depth { g.out[g.cols * g.rows + k] = g.cur[k] } else { g.out[g.cols * g.rows + k] = 0.0f64 }
        k += 1usize
    }
    g.cols += 1usize
}

fn walk(g: *Gen, rem: usize, left: usize, maxp: usize, depth: usize) {
    if left == 0usize {
        if rem == 0usize { emit(g, depth) }
        ret
    }
    // the largest part first; the rest must still fit: each remaining part is at least 1 (or distinct and smaller)
    var p = maxp
    if p > rem { p = rem }
    while p >= 1usize {
        g.cur[depth] = f64(p)
        var next = p
        if g.distinct { next = p - 1usize }
        walk(g, rem - p, left - 1usize, next, depth + 1usize)
        p -= 1usize
    }
}

// all partitions of n in decreasing lexicographic order (any number of parts); returns the column count
fn parts(a: *mem.Arena, n: usize, out: []f64) -> (usize, err) {
    let (cur, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (0usize, e) }
    var g = Gen { out: out, rows: n, cols: 0usize, cur: cur, distinct: false }
    // the lexicographic order over all lengths: a partition with first part p precedes one with a smaller first part
    walk_any(&g, n, n, 0usize)
    ret (g.cols, ok)
}

fn walk_any(g: *Gen, rem: usize, maxp: usize, depth: usize) {
    if rem == 0usize {
        emit(g, depth)
        ret
    }
    var p = maxp
    if p > rem { p = rem }
    while p >= 1usize {
        g.cur[depth] = f64(p)
        walk_any(g, rem - p, p, depth + 1usize)
        p -= 1usize
    }
}

// partitions of n into at most m parts (distinct false) or into distinct parts (distinct true), ordered by the
// number of parts and then lexicographically decreasing; rows is the column height
fn by_length(a: *mem.Arena, n: usize, m: usize, rows: usize, distinct: bool, out: []f64) -> (usize, err) {
    let (cur, e) = mem.alloc[f64](a, rows + 1usize)
    if e != ok { ret (0usize, e) }
    var g = Gen { out: out, rows: rows, cols: 0usize, cur: cur, distinct: distinct }
    var c = 1usize
    while c <= m {
        var maxp = n
        walk(&g, n, c, maxp, 0usize)
        c += 1usize
    }
    ret (g.cols, ok)
}

type CGen = struct { out: []f64, m: usize, cols: usize, cur: []f64, lo: usize }

// the compositions of rem into positions pos .. 0 (cur[pos] chosen from lo up, position 0 the remainder): the coordinate m - 1 is the slowest, as partitions::compositions orders its columns
fn comp_walk(g: *CGen, pos: usize, rem: usize) {
    if pos == 0usize {
        if rem >= g.lo {
            var j = 0usize
            while j < g.m {
                g.out[g.cols * g.m + j] = g.cur[j]
                j += 1usize
            }
            g.out[g.cols * g.m] = f64(rem)
            g.cols += 1usize
        }
        ret
    }
    var v = g.lo
    while v <= rem {
        g.cur[pos] = f64(v)
        comp_walk(g, pos - 1usize, rem - v)
        v += 1usize
    }
}

// compositions(n, m, include.zero): every way to write n as an ordered sum of m parts (zero allowed or all parts at least 1), columns of m entries into out; returns the number of columns
fn compositions(a: *mem.Arena, n: usize, m: usize, with_zero: bool, out: []f64) -> (usize, err) {
    let (cur, e) = mem.alloc[f64](a, m + 1usize)
    if e != ok { ret (0usize, e) }
    var lo = 1usize
    if with_zero { lo = 0usize }
    var g = CGen { out: out, m: m, cols: 0usize, cur: cur, lo: lo }
    comp_walk(&g, m - 1usize, n)
    ret (g.cols, ok)
}

type BGen = struct { out: []f64, m: usize, cols: usize, cur: []f64, f: []const f64 }

// the vectors with 0 <= x[i] <= f[i] and the given sum, the last coordinate the slowest and ascending, the first the remainder (partitions::blockparts)
fn bp_walk(g: *BGen, pos: usize, rem: usize) {
    if pos == 0usize {
        if f64(rem) <= g.f[0usize] {
            var j = 1usize
            while j < g.m {
                g.out[g.cols * g.m + j] = g.cur[j]
                j += 1usize
            }
            g.out[g.cols * g.m] = f64(rem)
            g.cols += 1usize
        }
        ret
    }
    var v = 0usize
    while v <= rem && f64(v) <= g.f[pos] {
        g.cur[pos] = f64(v)
        bp_walk(g, pos - 1usize, rem - v)
        v += 1usize
    }
}

// blockparts(f, n): the columns of m = f.len entries into out; returns the number of columns
fn blockparts(a: *mem.Arena, f: []const f64, n: usize, out: []f64) -> (usize, err) {
    let m = f.len
    let (cur, e) = mem.alloc[f64](a, m + 1usize)
    if e != ok { ret (0usize, e) }
    var g = BGen { out: out, m: m, cols: 0usize, cur: cur, f: f }
    bp_walk(&g, m - 1usize, n)
    ret (g.cols, ok)
}

// ---- setparts: the set partitions of 1..n by block sizes, in the order the package's C++ search produces them ----

type SGen = struct { sz: []usize, off: []usize, sh: []i64, dg: []i64, dn: usize, nb: usize, num: usize, out: []f64, cols: usize, sentinel_base: i64 }

fn sg_sentinel(g: *SGen, t: usize, e: usize) -> i64 { ret g.sentinel_base - i64(g.sz[t]) + i64(e) }

// the elements of block t are strictly increasing
fn sg_ordered(g: *SGen, t: usize) -> bool {
    var i = 1usize
    while i < g.sz[t] {
        if g.sh[g.off[t] + i] <= g.sh[g.off[t] + i - 1usize] { ret false }
        i += 1usize
    }
    ret true
}

// Tuple::lt of the package: lexicographic when the sizes agree, otherwise "the other is shorter"
fn sg_lt(g: *SGen, a: usize, b: usize) -> bool {
    if g.sz[a] == g.sz[b] {
        var i = 0usize
        while i < g.sz[a] {
            let x = g.sh[g.off[a] + i]
            let y = g.sh[g.off[b] + i]
            if x != y { ret x < y }
            i += 1usize
        }
    }
    ret g.sz[b] < g.sz[a]
}

fn sg_save(g: *SGen) {
    var i = 0usize
    while i < g.num {
        var j = 0usize
        while j < g.nb {
            var k = 0usize
            while k < g.sz[j] {
                if g.sh[g.off[j] + k] == i64(i + 1usize) { g.out[g.cols * g.num + i] = f64(j + 1usize) }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    g.cols += 1usize
}

fn sg_doit(g: *SGen, t: usize, e: usize) {
    if t == g.nb {
        sg_save(g)
        ret
    }
    if !sg_ordered(g, t) { ret }
    if g.sz[t] == e {
        if t > 0usize {
            if !sg_lt(g, t - 1usize, t) { ret }
        }
        sg_doit(g, t + 1usize, 0usize)
        ret
    }
    var i = 0usize
    while i < g.dn {
        // digits.get(i): take element i, the last one moves into its place
        let v = g.dg[i]
        g.dg[i] = g.dg[g.dn - 1usize]
        g.dn -= 1usize
        g.sh[g.off[t] + e] = v
        sg_doit(g, t, e + 1usize)
        // digits.put(i, shape[t][e])
        let back = g.sh[g.off[t] + e]
        if i == g.dn {
            g.dg[g.dn] = back
            g.dn += 1usize
        } else {
            g.dg[g.dn] = g.dg[i]
            g.dn += 1usize
            g.dg[i] = back
        }
        g.sh[g.off[t] + e] = sg_sentinel(g, t, e)
        i += 1usize
    }
}

// setparts(x) for block sizes x (any order; zeros dropped and the rest sorted decreasing): out receives num columns (num = sum x) per set partition, entry i the block of i + 1; returns the number of partitions
fn setparts_shape(a: *mem.Arena, x0: []const usize, out: []f64) -> (usize, err) {
    var nb = 0usize
    var num = 0usize
    var i = 0usize
    while i < x0.len {
        if x0[i] > 0usize {
            nb += 1usize
            num += x0[i]
        }
        i += 1usize
    }
    let (sz, e1) = mem.alloc[usize](a, nb)
    let (off, e2) = mem.alloc[usize](a, nb)
    let (sh, e3) = mem.alloc[i64](a, num)
    let (dg, e4) = mem.alloc[i64](a, num)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0usize, mem.Full) }
    var q = 0usize
    i = 0usize
    while i < x0.len {
        if x0[i] > 0usize {
            sz[q] = x0[i]
            q += 1usize
        }
        i += 1usize
    }
    // sort decreasing
    i = 1usize
    while i < nb {
        let key = sz[i]
        var j = i
        while j > 0usize && sz[j - 1usize] < key {
            sz[j] = sz[j - 1usize]
            j -= 1usize
        }
        sz[j] = key
        i += 1usize
    }
    var o = 0usize
    i = 0usize
    while i < nb {
        off[i] = o
        o += sz[i]
        i += 1usize
    }
    var g = SGen{ sz: sz, off: off, sh: sh, dg: dg, dn: num, nb: nb, num: num, out: out, cols: 0usize, sentinel_base: 2147483647i64 }
    i = 0usize
    while i < nb {
        var e = 0usize
        while e < sz[i] {
            sh[off[i] + e] = sg_sentinel(&g, i, e)
            e += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < num {
        dg[i] = i64(i + 1usize)
        i += 1usize
    }
    sg_doit(&g, 0usize, 0usize)
    ret (g.cols, ok)
}

// setparts(n): the set partitions of 1..n, grouped by the integer partitions of n in the order of `parts(n)`, each group as setparts_shape gives it; out holds n rows per column
fn setparts_n(a: *mem.Arena, n: usize, out: []f64) -> (usize, err) {
    let (pm, e1) = mem.alloc[f64](a, n * n * 2usize + n)
    if e1 != ok { ret (0usize, e1) }
    let (np, pe) = parts(a, n, pm)
    if pe != ok { ret (0usize, pe) }
    let (sz, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (0usize, e2) }
    var total = 0usize
    var c = 0usize
    while c < np {
        var r = 0usize
        while r < n {
            sz[r] = usize(pm[c * n + r])
            r += 1usize
        }
        let (k, se) = setparts_shape(a, sz, out[total * n..out.len])
        if se != ok { ret (0usize, se) }
        total += k
        c += 1usize
    }
    ret (total, ok)
}
