// e.algo.stat.qgraphpkg against qgraph centrality_auto. tests/oracle/qgraph.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qgraph`; the layout is at the top of scripts/r_oracle/groups/qgraph.R.

use e.algo.stat.qgraphpkg as qg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (out, e1) = mem.alloc[f64](a, 4usize * n)
    if e1 != ok { ret nan }
    if qg.centrality(a, z[1usize..1usize + n * n], n, out) != ok { ret nan }
    var b = 3usize
    if str.eq(c.name, "between") { b = 0usize }
    if str.eq(c.name, "closeness") { b = 1usize }
    if str.eq(c.name, "strength") { b = 2usize }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += out[b * n + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qgraph.json")
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
