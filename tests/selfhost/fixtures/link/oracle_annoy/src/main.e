// e.ml.annoy against RcppAnnoy 0.0.23: the forest Annoy builds from a seeded 64-bit KISS generator (euclidean, angular, manhattan, hamming), its
// neighbour queries with search_k, distances, item vectors, tree and item counts, and the index file (size and a checksum of every byte, and of each node
// of the small ones). The items are an integer hash of (i, z) that scripts/r_oracle/groups/annoy.R documents together with the case layout.
// tests/oracle/annoy.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R annoy`.

use e.io
use e.math
use e.mem
use e.ml.annoy as an
use e.os
use e.test.oracle as oracle

type State = struct { ia: an.Index, ib: an.Index, ic: an.Index, bytes: []u8 }

fn fv(i: usize, z: usize, dtype: usize) -> f64 {
    if dtype == 1usize { ret f64((i % 4usize) + z) / 2.0f64 }
    if dtype == 2usize && i % 17usize == 5usize { ret 0.0f64 }
    let b = (i * 7919usize + z * 104729usize + ((i * z * 31usize + i * i * 13usize + z * z * 7usize) % 997usize) * 17usize) % 2003usize
    ret (f64(b) - 1001.0f64) / 8.0f64
}

fn hw(i: usize, z: usize, k: usize) -> u64 {
    ret u64((i + 1usize) * (z * 131usize + k * 7usize + 17usize) * 2654435usize + i * z * 977usize + k * 12345usize)
}

fn hv(i: usize, z: usize, dtype: usize) -> f64 {
    if dtype == 1usize { ret f64(u64((i % 4usize) * 1234567usize + z)) }
    ret f64((hw(i, z, 0usize) % 67108864u64) * 134217728u64 + hw(i, z, 1usize) % 134217728u64)
}

fn item_vec(a: *mem.Arena, metric: usize, i: usize, f: usize, dtype: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, f)
    if e != ok { os.exit(5) }
    var z = 0usize
    while z < f {
        if metric == 3usize { v[z] = hv(i, z, dtype) } else { v[z] = fv(i, z, dtype) }
        z += 1usize
    }
    ret v
}

fn must(e: err) {
    if e != ok { os.exit(6) }
}

// the index of a scenario: items, build, and in mode 2 an unbuild, five more items and a rebuild
fn make(a: *mem.Arena, x: []const f64) -> an.Index {
    let metric = usize(x[0usize])
    let n = usize(x[1usize])
    let f = usize(x[2usize])
    let trees = i64(x[3usize])
    let dtype = usize(x[5usize])
    let mode = usize(x[6usize])
    let (ix, e) = an.new_index(a, u8(metric), f)
    must(e)
    var ixv = ix
    if x[4usize] >= 0.0f64 { an.set_seed(&ixv, u64(x[4usize])) }
    var i = 0usize
    while i < n {
        if mode != 3usize || i % 5usize != 3usize { must(an.add_item(a, &ixv, i, item_vec(a, metric, i, f, dtype))) }
        i += 1usize
    }
    must(an.build(a, &ixv, trees))
    if mode == 2usize {
        must(an.unbuild(&ixv))
        i = n
        while i < n + 5usize {
            must(an.add_item(a, &ixv, i, item_vec(a, metric, i, f, dtype)))
            i += 1usize
        }
        must(an.build(a, &ixv, trees))
    }
    ret ixv
}

fn same_key(x: []const f64, last: []const f64, n: usize) -> bool {
    var i = 0usize
    while i < n {
        if x[i] != last[i] { ret false }
        i += 1usize
    }
    ret true
}

// Annoy leaves the bytes of a hamming split node past its split bit uninitialised: zero them
fn canon(a: *mem.Arena, ix: *an.Index, b: []const u8) -> []u8 {
    let (c, e) = mem.alloc[u8](a, b.len + 1usize)
    must(e)
    var i = 0usize
    while i < b.len {
        c[i] = b[i]
        i += 1usize
    }
    if ix.metric == 3u8 {
        var node = 0usize
        while node < b.len / ix.s {
            let base = node * ix.s
            if usize(an.rd32(b, base)) > ix.k {
                var t = 12usize
                while t < 16usize {
                    c[base + t] = 0u8
                    t += 1usize
                }
                t = 24usize
                while t < ix.s {
                    c[base + t] = 0u8
                    t += 1usize
                }
            }
            node += 1usize
        }
    }
    ret c
}

fn hash(b: []const u8, from: usize, to: usize) -> f64 {
    var h = 0u64
    var i = from
    while i < to {
        h = (h * 257u64 + u64(b[i]) + 1u64) % 2147483647u64
        i += 1usize
    }
    ret f64(h)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/annoy.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var st: State = zero
    let (skey, ske) = mem.alloc[f64](a, 8usize)
    must(ske)
    let (qkey, qke) = mem.alloc[f64](a, 16usize)
    must(qke)
    var qhave = false
    var qcount = 0usize
    let (qitems, qe1) = mem.alloc[usize](a, 64usize)
    let (qdists, qe2) = mem.alloc[f64](a, 64usize)
    must(qe1)
    must(qe2)
    var at = 0usize
    while at < golden.cases.len {
        let base_mark = mem.mark(a)
        let x0 = golden.cases[at].args
        var sj = 0usize
        while sj < 7usize {
            skey[sj] = x0[sj]
            sj += 1usize
        }
        qhave = false
        st.ia = make(a, x0)
        st.ib = make(a, x0)
        let (bytes, se) = an.save(a, &st.ib)
        must(se)
        st.bytes = bytes
        let (ixc, ce) = an.new_index(a, u8(usize(x0[0usize])), usize(x0[2usize]))
        must(ce)
        st.ic = ixc
        must(an.load(a, &st.ic, st.bytes))
        while at < golden.cases.len && same_key(golden.cases[at].args, skey, 7usize) {
        let c = &golden.cases[at]
        let x = c.args
        let metric = usize(x[0usize])
        let n = usize(x[1usize])
        let f = usize(x[2usize])
        let dtype = usize(x[5usize])
        let phase = usize(x[7usize])
        let kind = usize(x[12usize])
        let rank = usize(x[13usize])
        var ix = &st.ia
        if phase == 1usize { ix = &st.ib }
        if phase == 2usize { ix = &st.ic }
        var got = 0.0f64 / 0.0f64
        if kind <= 2usize {
            if !qhave || !same_key(x, qkey, 12usize) {
                var j = 0usize
                while j < 12usize {
                    qkey[j] = x[j]
                    j += 1usize
                }
                qhave = true
                let start = mem.mark(a)
                let qk = usize(x[8usize])
                let nn = usize(x[10usize])
                let sk = i64(x[11usize])
                var cnt = 0usize
                var qerr = ok
                if qk == 0usize {
                    let (cc, ee) = an.nns_by_item(a, ix, usize(x[9usize]), nn, sk, qitems, qdists)
                    cnt = cc
                    qerr = ee
                } else {
                    var q = item_vec(a, metric, n + 13usize + usize(x[9usize]), f, dtype)
                    if qk == 2usize {
                        var z = 0usize
                        while z < f {
                            q[z] = 0.0f64
                            z += 1usize
                        }
                    }
                    let (cc, ee) = an.nns_by_vector(a, ix, q, nn, sk, qitems, qdists)
                    cnt = cc
                    qerr = ee
                }
                must(qerr)
                qcount = cnt
                mem.reset(a, start)
            }
            if kind == 0usize { got = f64(qcount) }
            if kind == 1usize && rank < qcount { got = f64(qitems[rank]) }
            if kind == 2usize && rank < qcount { got = qdists[rank] }
        }
        if kind == 10usize { got = f64(st.bytes.len) }
        if kind == 11usize { got = hash(canon(a, ix, st.bytes), 0usize, st.bytes.len) }
        if kind == 12usize { got = f64(an.n_trees(ix)) }
        if kind == 13usize { got = f64(an.n_items(ix)) }
        if kind == 14usize { got = an.get_distance(ix, usize(x[9usize]), rank) }
        if kind == 15usize {
            let start = mem.mark(a)
            let (v, e) = mem.alloc[f64](a, f)
            must(e)
            an.get_item(ix, usize(x[9usize]), v)
            got = v[rank]
            mem.reset(a, start)
        }
        if kind == 16usize {
            let start = mem.mark(a)
            let cb = canon(a, ix, st.bytes)
            got = hash(cb, rank * ix.s, (rank + 1usize) * ix.s)
            mem.reset(a, start)
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
        }
        mem.reset(a, base_mark)
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
