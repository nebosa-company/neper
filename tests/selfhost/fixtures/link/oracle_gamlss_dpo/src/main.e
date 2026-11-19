// e.algo.stat.gamlssdist's double Poisson DPO density, distribution and quantile against gamlss.dist (dDPO, pDPO, qDPO). tests/oracle/gamlss_dpo.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_dpo`; the layout of every case is at the top of scripts/r_oracle/groups/gamlss_dpo.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[0usize])
    if which == 0usize { ret gd.ddpo(z[3usize], z[1usize], z[2usize]) }
    if which == 1usize { ret gd.pdpo(z[3usize], z[1usize], z[2usize]) }
    if which == 2usize { ret gd.qdpo(z[3usize], z[1usize], z[2usize]) }
    if which == 3usize { ret gd.ddbi(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 4usize { ret gd.pdbi(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 5usize { ret gd.qdbi(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 6usize { ret gd.dgaf(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 7usize { ret gd.pgaf(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 8usize { ret gd.qgaf(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 9usize { ret gd.dzisichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 10usize { ret gd.dsep(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    ret gd.dzasichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_dpo.json")
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
