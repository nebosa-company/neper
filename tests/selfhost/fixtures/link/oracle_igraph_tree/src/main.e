// e.algo.graph.layout_tree against igraph: layout_as_tree (Reingold-Tilford).
// tests/oracle/igraph_tree.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R igraph_tree`; the case layout
// is at the top of scripts/r_oracle/groups/igraph_tree.R.

use e.algo.graph.layout_tree as lt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    let n = usize(x[0usize])
    let ne = usize(x[1usize])
    let nr = usize(x[6usize])
    let nl = usize(x[7usize])
    let (roots, e1) = mem.alloc[usize](a, nr + 1usize)
    let (lev, e2) = mem.alloc[i64](a, nl + 1usize)
    let (ed, e3) = mem.alloc[i64](a, 2usize * ne + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(9) }
    var i = 0usize
    while i < nr {
        roots[i] = usize(x[8usize + i])
        i += 1usize
    }
    i = 0usize
    while i < nl {
        lev[i] = i64(x[8usize + nr + i])
        i += 1usize
    }
    i = 0usize
    while i < 2usize * ne {
        ed[i] = i64(x[8usize + nr + nl + i])
        i += 1usize
    }
    let out = lt.tree(a, n, ed[0usize..2usize * ne], x[2usize] != 0.0f64, usize(x[3usize]), roots[0usize..nr], lev[0usize..nl], x[4usize] != 0.0f64, x[5usize] != 0.0f64)
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/igraph_tree.json")
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
