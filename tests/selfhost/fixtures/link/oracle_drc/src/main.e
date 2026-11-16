// e.algo.stat.drc against drc. tests/oracle/drc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R drc`; the layout is at the top of scripts/r_oracle/groups/drc.R.

use e.algo.stat.drc as dr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let (p, e1) = mem.alloc[f64](a, 4usize)
    if e1 != ok { os.exit(5) }
    let (rss, e2) = dr.fit_ll4(a, x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n], p)
    if e2 != ok { os.exit(6) }
    let k = c.name
    if str.eq(k, "b") { ret p[0usize] }
    if str.eq(k, "c") { ret p[1usize] }
    if str.eq(k, "d") { ret p[2usize] }
    if str.eq(k, "e") { ret p[3usize] }
    ret rss
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/drc.json")
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
