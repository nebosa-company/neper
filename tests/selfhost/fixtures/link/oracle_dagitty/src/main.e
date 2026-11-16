// e.algo.stat.dagitty against dagitty. tests/oracle/dagitty.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dagitty`; the layout is at the top of scripts/r_oracle/groups/dagitty.R.

use e.algo.stat.dagitty as dg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let xi = usize(x[1usize])
    let yi = usize(x[2usize])
    let z = u32(x[3usize])
    let (adj, e) = mem.alloc[bool](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n * n {
        adj[i] = x[4usize + i] > 0.5f64
        i += 1usize
    }
    let k = c.name
    if str.eq(k, "dsep") {
        if dg.dseparated(adj, n, dg.bit(xi), dg.bit(yi), z) { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(k, "anc") { ret f64(dg.ancestors(adj, n, dg.bit(yi))) }
    let (sets, e2) = mem.alloc[u32](a, usize(1u32 << u32(n)))
    if e2 != ok { os.exit(6) }
    let cnt = dg.minimal_adjustment_sets(a, adj, n, xi, yi, sets)
    if str.eq(k, "nadj") { ret f64(cnt) }
    var s = 0.0f64
    i = 0usize
    while i < cnt {
        s += f64(sets[i])
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dagitty.json")
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
