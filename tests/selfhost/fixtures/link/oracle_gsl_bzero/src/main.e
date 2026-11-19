// e.algo.stat.gslfns's bessel_zero_jnu against gsl bessel_zero_Jnu. tests/oracle/gsl_bzero.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gsl_bzero`; the layout is at the top of scripts/r_oracle/groups/gsl_bzero.R.

use e.algo.stat.gslfns as gs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "h3") { ret gs.legendre_h3d(usize(c.args[0usize]), c.args[1usize], c.args[2usize]) }
    if str.eq(c.name, "az") { ret gs.airy_zero(usize(c.args[0usize]), usize(c.args[1usize])) }
    if str.eq(c.name, "ad") {
        if usize(c.args[0usize]) == 2usize { ret gs.airy_ai_deriv(c.args[1usize]) }
        ret gs.airy_bi_deriv(c.args[1usize])
    }
    ret gs.bessel_zero_jnu(c.args[0usize], usize(c.args[1usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gsl_bzero.json")
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
