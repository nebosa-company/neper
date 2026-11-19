// e.algo.stat.gamlssq (the gamlss.dist distribution and quantile functions of GPO, LQNO, NBF, NET, NOF, PIG, PIG2, SEP1, SEP2, ST1, ST2, ST4, ST5, WARING, ZABB, ZABNB, ZALG, ZAPIG, ZAZIPF, ZIBB, ZIBNB, ZINBF, ZIPF,
// ZIPIG and BB, BNB) against gamlss.dist; tests/oracle/gamlss_pq.json is `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_pq`; the layout of a case is at the top of scripts/r_oracle/groups/gamlss_pq.R.

use e.algo.stat.gamlssq as gq
use e.math
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[0usize])
    let mu = z[1usize]
    let sg = z[2usize]
    let x = z[3usize]
    let nu = z[4usize]
    let tau = z[5usize]
    let ex = z[6usize]
    let mx = 10000.0f64
    if which == 0usize { ret gq.pgpo(x, mu, sg) }
    if which == 1usize { ret gq.plqno(x, mu, sg) }
    if which == 2usize { ret gq.pnbf(x, mu, sg, nu) }
    if which == 3usize { ret gq.pnet(x, mu, sg, nu, tau) }
    if which == 4usize { ret gq.pnof(x, mu, sg, nu) }
    if which == 5usize { ret gq.ppig2(x, mu, sg) }
    if which == 6usize { ret gq.pst1(a, x, mu, sg, nu, tau) }
    if which == 7usize { ret gq.pzazipf(x, mu, sg) }
    if which == 8usize { ret gq.pzinbf(x, mu, sg, nu, tau) }
    if which == 40usize { ret gq.pgu(x, mu, sg) }
    if which == 10usize { ret gq.qbb(x, mu, sg, ex) }
    if which == 11usize { ret gq.qbnb(x, mu, sg, nu, mx) }
    if which == 12usize { ret gq.qgpo(x, mu, sg, mx) }
    if which == 13usize { ret gq.qlqno(x, mu, sg) }
    if which == 14usize { ret gq.qnbf(x, mu, sg, nu) }
    if which == 15usize { ret gq.qnet(x, mu, sg, nu, tau) }
    if which == 16usize { ret gq.qnof(x, mu, sg, nu) }
    if which == 17usize { ret gq.qpig(x, mu, sg, mx) }
    if which == 18usize { ret gq.qpig2(x, mu, sg, mx) }
    if which == 19usize { ret gq.qsep1(a, x, mu, sg, nu, tau) }
    if which == 20usize { ret gq.qsep2(a, x, mu, sg, nu, tau) }
    if which == 21usize { ret gq.qst1(a, x, mu, sg, nu, tau) }
    if which == 22usize { ret gq.qst2(a, x, mu, sg, nu, tau) }
    if which == 23usize { ret gq.qst4(x, mu, sg, nu, tau) }
    if which == 24usize { ret gq.qst5(x, mu, sg, nu, tau) }
    if which == 25usize { ret gq.qwaring(x, mu, sg, mx) }
    if which == 26usize { ret gq.qzabb(x, mu, sg, nu, ex) }
    if which == 27usize { ret gq.qzabnb(x, mu, sg, nu, tau, mx) }
    if which == 28usize { ret gq.qzalg(x, mu, sg, mx) }
    if which == 29usize { ret gq.qzapig(x, mu, sg, nu, mx) }
    if which == 30usize { ret gq.qzazipf(x, mu, sg, mx) }
    if which == 31usize { ret gq.qzibb(x, mu, sg, nu, ex) }
    if which == 32usize { ret gq.qzibnb(x, mu, sg, nu, tau, mx) }
    if which == 33usize { ret gq.qzinbf(x, mu, sg, nu, tau) }
    if which == 34usize { ret gq.qzipf(x, mu, mx) }
    if which == 35usize { ret gq.qzipig(x, mu, sg, nu, mx) }
    ret 0.0f64 - 1.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_pq.json")
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
