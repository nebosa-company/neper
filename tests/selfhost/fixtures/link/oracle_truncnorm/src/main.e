// e.algo.stat.truncnorm against truncnorm: d, p, q, e, v and r of the truncated normal.
// tests/oracle/truncnorm.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// truncnorm`; the layout is at the top of scripts/r_oracle/groups/truncnorm.R.

use e.algo.rand.r as rr
use e.algo.stat.truncnorm as tn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "d") { ret tn.dtruncnorm(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(c.name, "p") { ret tn.ptruncnorm(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(c.name, "q") { ret tn.qtruncnorm(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(c.name, "e") { ret tn.etruncnorm(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(c.name, "v") { ret tn.vtruncnorm(x[0usize], x[1usize], x[2usize], x[3usize]) }
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[0usize]))
    let pos = usize(x[5usize])
    var v = 0.0f64
    var i = 0usize
    while i <= pos {
        v = tn.rtruncnorm(&g, x[1usize], x[2usize], x[3usize], x[4usize])
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/truncnorm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
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
