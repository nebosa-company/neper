// e.algo.stat.tsne_bh against Rtsne with theta > 0. tests/oracle/tsnebh.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsnebh`; the layout is at the top of scripts/r_oracle/groups/tsnebh.R.

use e.algo.rand.r as rng
use e.algo.stat.tsne as ts
use e.algo.stat.tsne_bh as bh
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pick(y: []const f64, sel: f64) -> f64 {
    if sel >= 0.0f64 { ret y[usize(sel)] }
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        if sel == 0.0f64 - 1.0f64 { s += y[i] * y[i] } else { s += y[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rng.Rng = zero
    if c.name[1usize] == 114u8 {
        let n = usize(x[1usize])
        let d = usize(x[2usize])
        let dims = usize(x[3usize])
        let (y, e) = mem.alloc[f64](a, n * dims)
        if e != ok { os.exit(5) }
        rng.seed(&g, i64(x[0usize]))
        var mode = 0usize
        if x[7usize] != 0.0f64 { mode = 1usize }
        if bh.tsne_bh(a, x[8usize..8usize + n * d], n, d, dims, x[4usize], x[6usize], y, usize(x[5usize]), 250usize, 250usize, 0.5f64, 0.8f64, 200.0f64, 12.0f64, mode, &g, false) != ok { os.exit(6) }
        ret pick(y, x[8usize + n * d])
    }
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let dims = usize(x[2usize])
    let (y, e1) = mem.alloc[f64](a, n * dims)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * dims {
        y[i] = x[9usize + n * d + i]
        i += 1usize
    }
    let mode = usize(x[8usize])
    let sel = x[9usize + n * d + n * dims]
    if mode == 3usize {
        let k = usize(x[10usize + n * d + n * dims])
        let (sc, e2) = mem.alloc[f64](a, n * k)
        if e2 != ok { os.exit(7) }
        if ts.pca_scores(a, x[9usize..9usize + n * d], n, d, k, sc) != ok { os.exit(8) }
        if bh.tsne_bh(a, sc, n, k, dims, x[3usize], x[7usize], y, usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), 0.5f64, 0.8f64, 200.0f64, 12.0f64, 1usize, &g, true) != ok { os.exit(9) }
        ret pick(y, sel)
    }
    if bh.tsne_bh(a, x[9usize..9usize + n * d], n, d, dims, x[3usize], x[7usize], y, usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), 0.5f64, 0.8f64, 200.0f64, 12.0f64, mode, &g, true) != ok { os.exit(6) }
    ret pick(y, sel)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsnebh.json")
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
