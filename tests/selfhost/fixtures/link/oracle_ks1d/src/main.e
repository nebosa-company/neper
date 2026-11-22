// e.algo.stat.ks1d against ks (hpi, hscv, hlscv in one dimension). tests/oracle/ks1d.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks1d`; the layout is at the top of scripts/r_oracle/groups/ks1d.R.

use e.algo.stat.ks1d as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    let n = usize(x[0usize])
    if str.eq(k, "hlscv") { ret ks.hlscv(a, x[1usize..1usize + n]) }
    if str.eq(k, "hscv") { ret ks.hscv(a, x[3usize..3usize + n], usize(x[1usize]), x[2usize] > 0.5f64) }
    ret ks.hpi(a, x[4usize..4usize + n], usize(x[1usize]), x[2usize] > 0.5f64, usize(x[3usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks1d.json")
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
