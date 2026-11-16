// e.algo.stat.laeken against laeken. tests/oracle/laeken.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R laeken`;
// the layout is at the top of scripts/r_oracle/groups/laeken.R.

use e.algo.stat.laeken as lk
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let hs = x[1usize] == 1.0f64
    let p = x[2usize]
    let inc = x[3usize..3usize + n]
    let w = x[3usize + n..3usize + 2usize * n]
    let so = x[3usize + 2usize * n..3usize + 3usize * n]
    let nm = c.name
    if str.eq(nm, "gini") { ret lk.gini(a, inc, w, so, hs) }
    if str.eq(nm, "qsr") { ret lk.qsr(a, inc, w, so, hs) }
    if str.eq(nm, "quint") { ret lk.inc_quintile(a, inc, w, so, hs, p) }
    if str.eq(nm, "arpt") { ret lk.arpt(a, inc, w, p) }
    if str.eq(nm, "arpr") { ret lk.arpr(inc, w, lk.arpt(a, inc, w, p)) }
    if str.eq(nm, "rmpg") { ret lk.rmpg(a, inc, w, lk.arpt(a, inc, w, p)) }
    if str.eq(nm, "quant") { ret lk.weighted_quantile(a, inc, w, p) }
    if str.eq(nm, "median") { ret lk.weighted_median(a, inc, w) }
    ret lk.weighted_mean(inc, w)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/laeken.json")
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
