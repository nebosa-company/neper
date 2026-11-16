// e.algo.stat.fieldspkg against fields. tests/oracle/fieldspkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fieldspkg`; the layout is at the top of scripts/r_oracle/groups/fieldspkg.R.

use e.algo.stat.fieldspkg as fp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "matern") { ret fp.matern(x[0usize], x[1usize], x[2usize], x[3usize]) }
    ret fp.exp_cov(x[0usize], x[1usize], x[2usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fieldspkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
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
