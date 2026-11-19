// e.algo.stat.gsldebye against gsl, value and error estimate. tests/oracle/gsldebye.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gsldebye`; the layout of each case is at the top of scripts/r_oracle/groups/gsldebye.R.

use e.algo.stat.gsldebye as gd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = gd.debye(usize(x[0usize]), x[2usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gsldebye.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 16usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
