// e.algo.graph.games against igraph under set.seed: gnp, gnm, sbm, pa, smallworld, degseq (configuration), k_regular.
// tests/oracle/igraph_games.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R igraph_games`; the case layout
// is at the top of scripts/r_oracle/groups/igraph_games.R.

use e.algo.graph.games as gg
use e.algo.rand.r as rg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn to_u(a: *mem.Arena, x: []const f64, at: usize, n: usize) -> []usize {
    let (o, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        o[i] = usize(x[at + i])
        i += 1usize
    }
    ret o[0usize..n]
}

fn summary(el: *gg.Edges, nv: usize, what: f64) -> f64 {
    if what == 0.0f64 { ret f64(gg.count(el)) }
    var s = 0.0f64
    var i = 0usize
    while i < gg.count(el) {
        s += f64(i + 1usize) * (f64(el.b[2usize * i]) * f64(nv) + f64(el.b[2usize * i + 1usize]) + 1.0f64)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    let what = x[0usize]
    var r: rg.Rng = zero
    rg.seed(&r, i64(x[1usize]))
    let h = 2usize
    if str.eq(nm, "gnp") {
        let n = usize(x[h])
        var el = gg.gnp(a, &r, n, x[h + 1usize], x[h + 2usize] != 0.0f64, x[h + 3usize] != 0.0f64)
        ret summary(&el, n, what)
    }
    if str.eq(nm, "gnm") {
        let n = usize(x[h])
        var el = gg.gnm(a, &r, n, usize(x[h + 1usize]), x[h + 2usize] != 0.0f64, x[h + 3usize] != 0.0f64)
        ret summary(&el, n, what)
    }
    if str.eq(nm, "sbm") {
        let n = usize(x[h])
        let k = usize(x[h + 3usize])
        let bs = to_u(a, x, h + 4usize, k)
        var el = gg.sbm(a, &r, x[h + 4usize + k..h + 4usize + k + k * k], bs, x[h + 1usize] != 0.0f64, x[h + 2usize] != 0.0f64)
        ret summary(&el, n, what)
    }
    if str.eq(nm, "pa") {
        let n = usize(x[h])
        var sq = to_u(a, x, h + 8usize, 0usize)
        if x[h + 7usize] != 0.0f64 { sq = to_u(a, x, h + 8usize, n) }
        var el = gg.pa(a, &r, n, x[h + 1usize], usize(x[h + 2usize]), sq, x[h + 3usize] != 0.0f64, x[h + 4usize], x[h + 5usize] != 0.0f64, usize(x[h + 6usize]))
        ret summary(&el, n, what)
    }
    if str.eq(nm, "sw") {
        let n = usize(x[h])
        var el = gg.smallworld(a, &r, n, usize(x[h + 1usize]), x[h + 2usize], x[h + 3usize] != 0.0f64, x[h + 4usize] != 0.0f64)
        ret summary(&el, n, what)
    }
    if str.eq(nm, "degseq") {
        let n = usize(x[h])
        let od = to_u(a, x, h + 2usize, n)
        var idg = to_u(a, x, h + 2usize, 0usize)
        if x[h + 1usize] != 0.0f64 { idg = to_u(a, x, h + 2usize + n, n) }
        var el = gg.degseq_config(a, &r, od, idg)
        ret summary(&el, n, what)
    }
    let n = usize(x[h])
    var el = gg.k_regular(a, &r, n, usize(x[h + 1usize]), x[h + 2usize] != 0.0f64, x[h + 3usize] != 0.0f64)
    ret summary(&el, n, what)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/igraph_games.json")
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
