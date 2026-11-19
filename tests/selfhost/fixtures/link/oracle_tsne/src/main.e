// e.algo.stat.tsne against Rtsne with theta = 0. tests/oracle/tsne.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsne`; the layout is at the top of scripts/r_oracle/groups/tsne.R.

use e.algo.rand.r as rng
use e.algo.stat.tsne as ts
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if c.name.len == 2usize && c.name[1usize] == 114u8 {
        let tn = usize(x[1usize])
        let td = usize(x[2usize])
        let tdims = usize(x[3usize])
        let (ty, te) = mem.alloc[f64](a, tn * tdims)
        if te != ok { os.exit(5) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        ts.tsne_start(&g, tn, tdims, ty)
        var tmode = 0usize
        if x[6usize] != 0.0f64 { tmode = 1usize }
        if ts.tsne_exact(a, x[7usize..7usize + tn * td], tn, td, tdims, x[4usize], ty, usize(x[5usize]), 250usize, 250usize, 0.5f64, 0.8f64, 200.0f64, 12.0f64, tmode) != ok { os.exit(6) }
        ret ty[usize(x[7usize + tn * td])]
    }
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let dims = usize(x[2usize])
    let (y, e1) = mem.alloc[f64](a, n * dims)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * dims {
        y[i] = x[11usize + n * d + i]
        i += 1usize
    }
    let mode = usize(x[11usize + n * d + n * dims + 1usize])
    if mode == 3usize {
        let kk = usize(x[11usize + n * d + n * dims + 2usize])
        let (sc, e2) = mem.alloc[f64](a, n * kk)
        if e2 != ok { os.exit(7) }
        if ts.pca_scores(a, x[11usize..11usize + n * d], n, d, kk, sc) != ok { os.exit(8) }
        if ts.tsne_exact(a, sc, n, kk, dims, x[3usize], y, usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), x[7usize], x[8usize], x[9usize], x[10usize], 1usize) != ok { os.exit(9) }
        ret y[usize(x[11usize + n * d + n * dims])]
    }
    if ts.tsne_exact(a, x[11usize..11usize + n * d], n, d, dims, x[3usize], y, usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), x[7usize], x[8usize], x[9usize], x[10usize], usize(x[11usize + n * d + n * dims + 1usize])) != ok { os.exit(6) }
    ret y[usize(x[11usize + n * d + n * dims])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsne.json")
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
            if failures <= 6usize {
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
