// e.algo.stat.uwot's umap_transform against uwot. tests/oracle/uwottr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R uwottr`; the layout is at the top of scripts/r_oracle/groups/uwottr.R.

use e.algo.rand.r as rng
use e.algo.stat.uwot as uw
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
    let nq = usize(x[1usize])
    let k = usize(x[2usize])
    let nt = usize(x[3usize])
    let nd = usize(x[4usize])
    let (y, e) = mem.alloc[f64](a, nq * nd)
    let (idx, e2) = mem.alloc[usize](a, nq * k)
    if e != ok || e2 != ok { os.exit(5) }
    var i = 0usize
    while i < nq * k {
        idx[i] = usize(x[13usize + i])
        i += 1usize
    }
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let dist = x[13usize + nq * k..13usize + 2usize * nq * k]
    let train = x[13usize + 2usize * nq * k..13usize + 2usize * nq * k + nt * nd]
    if uw.umap_transform_fit(a, idx, dist, nq, k, train, nt, nd, usize(x[5usize]), x[6usize], x[7usize], x[8usize], x[9usize], x[10usize], x[11usize], x[12usize] != 0.0f64, &g, y) != ok { os.exit(6) }
    ret pick(y, x[13usize + 2usize * nq * k + nt * nd])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/uwottr.json")
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
