// e.ml.cluster.density (kNNdist and lof) against dbscan. tests/oracle/dbscanpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dbscanpkg`; the layout is at the top of scripts/r_oracle/groups/dbscanpkg.R.

use e.io
use e.ml.cluster.density as dn
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let p = usize(x[2usize])
    let row = usize(x[3usize])
    if str.eq(c.name, "snn") || str.eq(c.name, "frcount") || str.eq(c.name, "frsum") {
        let pts5 = x[5usize..5usize + n * d]
        if str.eq(c.name, "snn") {
            let (i1, g1) = mem.alloc[usize](a, n)
            if g1 != ok { os.exit(9) }
            let (d1, g2) = mem.alloc[f64](a, n)
            if g2 != ok { os.exit(10) }
            let (i2, g3) = mem.alloc[usize](a, n)
            if g3 != ok { os.exit(11) }
            let (d2, g4) = mem.alloc[f64](a, n)
            if g4 != ok { os.exit(12) }
            ret dn.snn_shared(pts5, n, d, p, row, usize(x[4usize]), i1, d1, i2, d2)
        }
        let (cnt, sm) = dn.frnn_count(pts5, n, d, row, x[2usize])
        if str.eq(c.name, "frcount") { ret f64(cnt) }
        ret sm
    }
    if str.eq(c.name, "jpc") {
        let k = usize(x[2usize])
        let (lb, h1) = mem.alloc[usize](a, n)
        let (ids, h2) = mem.alloc[usize](a, n * k)
        let (adj, h3) = mem.alloc[u8](a, n * n)
        let (near, h4) = mem.alloc[usize](a, n)
        let (nd, h5) = mem.alloc[f64](a, n)
        let (qu, h6) = mem.alloc[usize](a, n)
        if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok { os.exit(14) }
        let nc = dn.jp_cluster(x[5usize..5usize + n * d], n, d, k, usize(x[3usize]), lb, ids, adj, near, nd, qu)
        if usize(x[4usize]) == 1usize { ret f64(nc) }
        var tot = 0.0f64
        var i = 0usize
        while i < n {
            tot += f64(i + 1usize) * f64(lb[i] + 1usize)
            i += 1usize
        }
        ret tot
    }
    if str.eq(c.name, "snnc") {
        let k = usize(x[2usize])
        let q = usize(x[5usize])
        let (lb, h1) = mem.alloc[usize](a, n)
        let (ids, h2) = mem.alloc[usize](a, n * k)
        let (adj, h3) = mem.alloc[u8](a, n * n)
        let (near, h4) = mem.alloc[usize](a, n)
        let (nd, h5) = mem.alloc[f64](a, n)
        let (qu, h6) = mem.alloc[usize](a, n)
        if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok { os.exit(13) }
        let nc = dn.snn_cluster(x[6usize..6usize + n * d], n, d, k, x[3usize], usize(x[4usize]), lb, ids, adj, near, nd, qu)
        if q == 1usize { ret f64(nc) }
        var tot = 0.0f64
        var i = 0usize
        while i < n {
            if lb[i] != dn.NOISE { tot += f64(i + 1usize) * f64(lb[i] + 1usize) }
            i += 1usize
        }
        ret tot
    }
    let pts = x[4usize..4usize + n * d]
    let (o, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(5) }
    let (kd, e2) = mem.alloc[f64](a, n)
    if e2 != ok { os.exit(6) }
    let (lr, e3) = mem.alloc[f64](a, n)
    if e3 != ok { os.exit(7) }
    let (sc, e4) = mem.alloc[f64](a, n)
    if e4 != ok { os.exit(8) }
    if str.eq(c.name, "knnd") {
        dn.knn_distance(pts, n, d, p, o, sc)
        ret o[row]
    }
    dn.lof(pts, n, d, p, o, kd, lr, sc)
    ret o[row]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dbscanpkg.json")
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
