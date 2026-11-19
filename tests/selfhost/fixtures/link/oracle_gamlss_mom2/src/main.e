// e.algo.stat.gamlssm: the mean and variance functions of the family objects of BB, BEINF, BNB, GAF, GB2, GIG, GT, JSUo, NBF, NET, NOF, PARETO2o, PE2, PIG, SHASHo, SN2, SST, ST2, ST3, ST4, ST5, WARING, ZABNB, ZAPIG, ZASICHEL,
// ZAZIPF, ZIBNB, ZIPF, ZIPIG and ZISICHEL against gamlss.dist; tests/oracle/gamlss_mom2.json is `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_mom2`; the layout of a case is at the top of scripts/r_oracle/groups/gamlss_mom2.R.

use e.algo.stat.gamlssm as gm
use e.math
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    ret gm.family_moment3(a, usize(z[0usize]), usize(z[1usize]), z[2usize], z[3usize], z[4usize], z[5usize], z[6usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_mom2.json")
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
