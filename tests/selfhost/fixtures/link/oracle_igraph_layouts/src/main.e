// e.algo.graph.layout_force against igraph: layout_with_fr, kk, graphopt and mds.
// tests/oracle/igraph_layouts.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R igraph_layouts`; the case layout
// is at the top of scripts/r_oracle/groups/igraph_layouts.R.

use e.algo.graph.layout_force as lf
use e.algo.graph.layout_merge as lm
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
    let hasw = x[3usize] != 0.0f64
    let p = x[4usize..10usize]
    let (ed, e1) = mem.alloc[i64](a, 2usize * ne + 1usize)
    if e1 != ok { os.exit(9) }
    var i = 0usize
    while i < 2usize * ne {
        ed[i] = i64(x[10usize + i])
        i += 1usize
    }
    var w = x[10usize..10usize]
    if hasw { w = x[10usize + 2usize * ne..10usize + 3usize * ne] }
    var out = x[0usize..0usize]
    var cols = 2usize
    if str.starts_with(nm, "md_") {
        out = lm.mds2(a, &r, n, ed[0usize..2usize * ne])
    } else if str.starts_with(nm, "fg_") {
        out = lf.fr_grid(a, &r, n, ed[0usize..2usize * ne], usize(p[0usize]), p[1usize], w)
    } else if str.starts_with(nm, "fr_") {
        out = lf.fr(a, &r, n, ed[0usize..2usize * ne], usize(p[0usize]), p[1usize], w)
    } else if str.starts_with(nm, "kk_") {
        out = lf.kk(a, n, ed[0usize..2usize * ne], usize(p[0usize]), p[1usize], p[2usize], w)
    } else if str.starts_with(nm, "go_") {
        out = lf.graphopt(a, &r, n, ed[0usize..2usize * ne], usize(p[0usize]), p[1usize], p[2usize], p[3usize], p[4usize], p[5usize])
    } else {
        cols = usize(p[0usize])
        out = lf.mds(a, n, ed[0usize..2usize * ne], cols)
    }
    var k = 0usize
    if str.ends_with(nm, "ys") || str.ends_with(nm, "yw") { k = 1usize }
    if str.ends_with(nm, "zs") || str.ends_with(nm, "zw") { k = 2usize }
    let sum = str.ends_with(nm, "s")
    var s = 0.0f64
    i = 0usize
    while i < n {
        if sum { s += out[i * cols + k] } else { s += f64(i + 1usize) * out[i * cols + k] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/igraph_layouts.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 60usize {
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
