// e.algo.graph.degseq_vl against igraph: sample_degseq(method = "vl") under set.seed.
// tests/oracle/igraph_vl.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R igraph_vl`; the case layout
// is at the top of scripts/r_oracle/groups/igraph_vl.R.

use e.algo.graph.degseq_vl as vl
use e.algo.graph.games as gg
use e.algo.rand.r as rg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var r: rg.Rng = zero
    rg.seed(&r, i64(x[1usize]))
    let n = usize(x[2usize])
    let (seq, e1) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok { os.exit(9) }
    var i = 0usize
    while i < n {
        seq[i] = usize(x[3usize + i])
        i += 1usize
    }
    var el = vl.vl(a, &r, seq[0usize..n])
    if x[0usize] == 0.0f64 { ret f64(gg.count(&el)) }
    var s = 0.0f64
    i = 0usize
    while i < gg.count(&el) {
        s += f64(i + 1usize) * (f64(el.b[2usize * i]) * f64(n) + f64(el.b[2usize * i + 1usize]) + 1.0f64)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/igraph_vl.json")
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
