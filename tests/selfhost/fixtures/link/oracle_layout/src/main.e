// e.algo.graph.layout against igraph: layout_in_circle, layout_as_star, layout_on_grid, layout_on_sphere.
// tests/oracle/layout.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R layout`; the layout
// is at the top of scripts/r_oracle/groups/layout.R.

use e.algo.graph.layout as ly
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let nm = c.name
    let (out, e) = mem.alloc[f64](a, 3usize * n)
    let (ord, e2) = mem.alloc[usize](a, n)
    if e != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var cols = 2usize
    if str.starts_with(nm, "circleo") {
        var i = 0usize
        while i < n {
            ord[i] = usize(x[1usize + i])
            i += 1usize
        }
        ly.in_circle(n, ord, out)
    } else if str.starts_with(nm, "circle") {
        var i = 0usize
        while i < n {
            ord[i] = i
            i += 1usize
        }
        ly.in_circle(n, ord, out)
    } else if str.starts_with(nm, "star") {
        ly.as_star(n, usize(x[1usize]), out)
    } else if str.starts_with(nm, "grid") {
        ly.on_grid(n, usize(x[1usize]), out)
    } else {
        cols = 3usize
        ly.on_sphere(n, out)
    }
    var k = 0usize
    if str.ends_with(nm, "ys") || str.ends_with(nm, "yw") { k = 1usize }
    if str.ends_with(nm, "zs") || str.ends_with(nm, "zw") { k = 2usize }
    let sum = str.ends_with(nm, "s")
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if sum { s += out[i * cols + k] } else { s += f64(i + 1usize) * out[i * cols + k] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/layout.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
