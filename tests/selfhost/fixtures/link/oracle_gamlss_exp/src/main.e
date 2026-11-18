// e.algo.stat.gamlssdist's EXP and RG functions against gamlss.dist (dEXP, pEXP, qEXP, dRG, pRG, qRG, dPARETO2, pPARETO2, qPARETO2). tests/oracle/gamlss_exp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_exp`; the layout of every case is at the top of scripts/r_oracle/groups/gamlss_exp.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[0usize])
    let mu = z[1usize]
    let sigma = z[2usize]
    let x = z[3usize]
    if which == 0usize { ret gd.dexp_mu(x, mu) }
    if which == 1usize { ret gd.pexp_mu(x, mu) }
    if which == 2usize { ret gd.qexp_mu(x, mu) }
    if which == 3usize { ret gd.drg(x, mu, sigma) }
    if which == 4usize { ret gd.prg(x, mu, sigma) }
    if which == 5usize { ret gd.qrg(x, mu, sigma) }
    if which == 6usize { ret gd.dpareto2(x, mu, sigma) }
    if which == 7usize { ret gd.ppareto2(x, mu, sigma) }
    ret gd.qpareto2(x, mu, sigma)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_exp.json")
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
