// e.algo.graph.metrics against igraph: transitivity, coreness, degree assortativity, similarity, eccentricity,
// radius and diameter. tests/oracle/igraph.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R igraph`; the layout is at the top of
// scripts/r_oracle/groups/igraph.R.

use e.algo.graph.metrics as gm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let adj = x[1usize..1usize + n * n]
    let nm = c.name
    if str.eq(nm, "trans_g") { ret gm.transitivity_global(adj, n) }
    if str.eq(nm, "trans_avg") { ret gm.transitivity_average(adj, n) }
    let (core, e1) = mem.alloc[f64](a, n)
    let (deg, e2) = mem.alloc[f64](a, n)
    let (gone, e3) = mem.alloc[bool](a, n)
    let (dist, e4) = mem.alloc[i64](a, n)
    let (queue, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(nm, "assort") { ret gm.assortativity_degree(adj, n) }
    var s = 0.0f64
    var i = 0usize
    if str.eq(nm, "trans_sum") || str.eq(nm, "trans_w") {
        while i < n {
            let v = gm.transitivity_local(adj, n, i)
            if str.eq(nm, "trans_sum") { s += v } else { s += f64(i + 1usize) * v }
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "core_sum") || str.eq(nm, "core_w") {
        gm.coreness(adj, n, core, deg, gone)
        while i < n {
            if str.eq(nm, "core_sum") { s += core[i] } else { s += f64(i + 1usize) * core[i] }
            i += 1usize
        }
        ret s
    }
    if str.ends_with(nm, "_sum") && (str.starts_with(nm, "jac") || str.starts_with(nm, "dic")) || str.ends_with(nm, "_w") && (str.starts_with(nm, "jac") || str.starts_with(nm, "dic")) {
        let dice = str.starts_with(nm, "dic")
        while i < n {
            var j = i + 1usize
            while j < n {
                let v = gm.similarity(adj, n, i, j, dice)
                if str.ends_with(nm, "_sum") { s += v } else { s += f64(i * n + j + 1usize) * v }
                j += 1usize
            }
            i += 1usize
        }
        ret s
    }
    var lo = 1.0e300f64
    var hi = 0.0f64
    while i < n {
        let e = gm.eccentricity(adj, n, i, dist, queue)
        if e < lo { lo = e }
        if e > hi { hi = e }
        if str.eq(nm, "ecc_sum") { s += e } else { s += f64(i + 1usize) * e }
        i += 1usize
    }
    if str.eq(nm, "radius") { ret lo }
    if str.eq(nm, "diameter") { ret hi }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/igraph.json")
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
