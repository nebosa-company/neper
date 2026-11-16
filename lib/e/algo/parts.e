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
