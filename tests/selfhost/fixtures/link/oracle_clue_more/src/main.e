// e.algo.stat.clue's soft-partition measures and ultrametric objects against clue. tests/oracle/clue_more.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_more`; the layout is at the top of scripts/r_oracle/groups/clue_more.R.

use e.algo.stat.clue as cl
use e.algo.stat.hclust as hc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    if str.eq(c.name, "softm") {
        let kx = usize(z[2usize])
        let ky = usize(z[3usize])
        let (v, e) = cl.soft_measure(a, z[4usize..4usize + n * kx], z[4usize + n * kx..4usize + n * kx + n * ky], n, kx, ky, kind)
        if e != ok { ret nan }
        ret v
    }
    // an ultrametric is its own single-linkage tree
    let (t1, e1) = hc.hclust(a, z[2usize..2usize + n * n], n, 2usize)
    let (t2, e2) = hc.hclust(a, z[2usize + n * n..2usize + 2usize * n * n], n, 2usize)
    if e1 != ok || e2 != ok { ret nan }
    if kind >= 5usize {
        let (va, ea) = cl.hier_agreement(a, &t1, &t2, n, kind)
        if ea != ok { ret nan }
        ret va
    }
    let (v, e) = cl.hier_dissimilarity(a, &t1, &t2, n, kind)
    if e != ok { ret nan }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_more.json")
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
