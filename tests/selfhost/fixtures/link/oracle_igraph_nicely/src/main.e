// e.algo.graph.layout_nicely against igraph: layout_nicely (as_tree for small forests, else FR plus align_layout).
// tests/oracle/igraph_nicely.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R igraph_nicely`; the case layout
// is at the top of scripts/r_oracle/groups/igraph_nicely.R.

use e.algo.graph.layout_nicely as ln
use e.algo.rand.r as rg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    var r: rg.Rng = zero
    rg.seed(&r, i64(x[0usize]))
    let n = usize(x[1usize])
    let ne = usize(x[2usize])
    let (ed, e1) = mem.alloc[i64](a, 2usize * ne + 1usize)
    if e1 != ok { os.exit(9) }
    var i = 0usize
    while i < 2usize * ne {
        ed[i] = i64(x[4usize + i])
        i += 1usize
    }
    let out = ln.nicely(a, &r, n, ed[0usize..2usize * ne], x[3usize] != 0.0f64)
    var k = 0usize
    if str.ends_with(nm, "ys") || str.ends_with(nm, "yw") { k = 1usize }
    let sum = str.ends_with(nm, "s")
    var s = 0.0f64
    i = 0usize
    while i < n {
        if sum { s += out[i * 2usize + k] } else { s += f64(i + 1usize) * out[i * 2usize + k] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/igraph_nicely.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 30usize {
                let _ = io.print(c.name)
                let _ = io.print(" ")
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
