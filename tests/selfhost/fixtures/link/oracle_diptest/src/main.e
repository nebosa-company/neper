// e.algo.stat.dip against diptest::dip. tests/oracle/diptest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R diptest`; the layout is at the top of
// scripts/r_oracle/groups/diptest.R.

use e.algo.rand.r as rr
use e.algo.stat.dip as dp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let (r, e) = dp.dip(a, x[1usize..1usize + n], false)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "p") { ret dp.dip_p(n, r.dip) }
    if str.eq(c.name, "psim") {
        var g: rr.Rng = zero
        rr.seed(&g, i64(x[1usize + n]))
        let (ps, pe) = dp.dip_sim_p(a, &g, n, r.dip, 100usize)
        if pe != ok { ret 0.0f64 / 0.0f64 }
        ret ps
    }
    if str.eq(c.name, "low") { ret f64(r.low) }
    if str.eq(c.name, "high") { ret f64(r.high) }
    ret r.dip
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/diptest.json")
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
