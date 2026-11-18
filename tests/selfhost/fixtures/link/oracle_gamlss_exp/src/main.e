// e.algo.stat.gamlssdist's EXP and RG functions against gamlss.dist (dEXP, pEXP, qEXP, dRG, pRG, qRG, dPARETO2, pPARETO2, qPARETO2, dPARETO1, pPARETO1, qPARETO1, dNO, pNO, qNO, dPO, pPO, qPO). tests/oracle/gamlss_exp.json comes from
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
    if which == 8usize { ret gd.qpareto2(x, mu, sigma) }
    if which == 9usize { ret gd.dpareto1(x, mu) }
    if which == 10usize { ret gd.ppareto1(x, mu) }
    if which == 11usize { ret gd.qpareto1(x, mu) }
    if which == 12usize { ret gd.dno(x, mu, sigma) }
    if which == 13usize { ret gd.pno(x, mu, sigma) }
    if which == 14usize { ret gd.qno(x, mu, sigma) }
    if which == 15usize { ret gd.dpo(x, mu) }
    if which == 16usize { ret gd.ppo(x, mu) }
    if which == 17usize { ret gd.qpo(x, mu) }
    if which == 18usize { ret gd.dga(x, mu, sigma) }
    if which == 19usize { ret gd.pga(x, mu, sigma) }
    if which == 20usize { ret gd.qga(x, mu, sigma) }
    if which == 21usize { ret gd.dwei(x, mu, sigma) }
    if which == 22usize { ret gd.pwei(x, mu, sigma) }
    if which == 23usize { ret gd.qwei(x, mu, sigma) }
    if which == 24usize { ret gd.dlogno(x, mu, sigma) }
    if which == 25usize { ret gd.plogno(x, mu, sigma) }
    if which == 26usize { ret gd.qlogno(x, mu, sigma) }
    if which == 27usize { ret gd.pig(x, mu, sigma) }
    if which == 28usize { ret gd.pzip(x, mu, sigma) }
    if which == 29usize { ret gd.qzip(x, mu, sigma) }
    if which == 30usize { ret gd.dnbi(x, mu, sigma) }
    if which == 31usize { ret gd.pnbi(x, mu, sigma) }
    if which == 32usize { ret gd.qnbi(x, mu, sigma) }
    let nu = z[4usize]
    if which == 33usize { ret gd.dtf(x, mu, sigma, nu) }
    if which == 34usize { ret gd.ptf(x, mu, sigma, nu) }
    if which == 35usize { ret gd.qtf(x, mu, sigma, nu) }
    if which == 36usize { ret gd.pbccg(x, mu, sigma, nu) }
    if which == 37usize { ret gd.qbccg(x, mu, sigma, nu) }
    if which == 38usize { ret gd.dgp(x, mu, sigma) }
    if which == 39usize { ret gd.pgp(x, mu, sigma) }
    ret gd.qgp(x, mu, sigma)
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
