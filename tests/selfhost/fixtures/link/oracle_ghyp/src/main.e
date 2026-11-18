// e.algo.stat.ghyp against GeneralizedHyperbolic. tests/oracle/ghyp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghyp`; the layout is at the top of scripts/r_oracle/groups/ghyp.R.

use e.algo.stat.ghyp as gh
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "pghyp") { ret gh.pghyp(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "pnig") { ret gh.pnig(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "phyperb") { ret gh.phyperb(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "dghyp") { ret gh.dghyp(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "dnig") { ret gh.dnig(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "dhyperb") { ret gh.dhyperb(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    ret gh.dskewlap(x[0usize], x[1usize], x[2usize], x[3usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghyp.json")
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
