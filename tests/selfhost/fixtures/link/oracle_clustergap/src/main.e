// e.algo.stat.clustergap (clusGap, maxSE) against cluster::clusGap and cluster::maxSE. tests/oracle/clustergap.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clustergap`; the argument layouts are at the top of
// scripts/r_oracle/groups/clustergap.R.

use e.algo.rand.r as rr
use e.algo.stat.clustergap as cg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum_f(v: []const f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "maxse") {
        let kk = usize(x[2usize])
        ret f64(cg.max_se(x[3usize..3usize + kk], x[3usize + kk..3usize + 2usize * kk], kk, usize(x[0usize]), x[1usize]))
    }
    let fun = usize(x[0usize])
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let kmax = usize(x[3usize])
    let bb = usize(x[4usize])
    let dpow = x[5usize]
    let pca = x[6usize] != 0.0f64
    let seed = i64(x[7usize])
    var rg: rr.Rng = zero
    rr.seed(&rg, seed)
    let (g, e1) = cg.clus_gap(a, x[8usize + p * p..8usize + p * p + n * p], n, p, kmax, bb, dpow, pca, x[8usize..8usize + p * p], fun, &rg)
    if e1 != ok { os.exit(5) }
    let nm = c.name
    if str.eq(nm, "logw") { ret wsum_f(g.logw, kmax) }
    if str.eq(nm, "elogw") { ret wsum_f(g.elogw, kmax) }
    if str.eq(nm, "gap") { ret wsum_f(g.gap, kmax) }
    if str.eq(nm, "se") { ret wsum_f(g.se, kmax) }
    os.exit(6)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clustergap.json")
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
