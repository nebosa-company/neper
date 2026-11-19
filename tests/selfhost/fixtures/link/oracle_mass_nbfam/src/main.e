// e.algo.stat.mass's negative.binomial family terms against MASS. tests/oracle/mass_nbfam.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_nbfam`; the layout is at the top of scripts/r_oracle/groups/mass_nbfam.R.

use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "nbvar") { ret ms.nb_variance(z[1usize], z[3usize]) }
    if str.eq(c.name, "nbdev") { ret ms.nb_dev_resid(z[0usize], z[1usize], z[2usize], z[3usize]) }
    ret ms.nb_aic_term(z[0usize], z[1usize], z[2usize], z[3usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_nbfam.json")
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
