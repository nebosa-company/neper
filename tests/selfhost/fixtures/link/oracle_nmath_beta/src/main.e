// e.math.toms708 and e.math.nmath_beta against R: pbeta (all branches of bratio), dbeta, lbeta,
// dbinom and pbinom with lower.tail and log.p. tests/oracle/nmath_beta.json comes from
// `Rscript scripts/r_oracle/generate.R nmath_beta`.

use e.io
use e.math.nmath_beta as nb
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let fam = u8(x[0usize])
    let kind = u8(x[1usize])
    let lower = x[5usize] != 0.0f64
    let lg = x[6usize] != 0.0f64
    if fam == 2u8 { ret nb.lbeta(x[3usize], x[4usize]) }
    if fam == 13u8 {
        if kind == 0u8 { ret nb.dsignrank(a, x[2usize], x[3usize], lg) }
        if kind == 1u8 { ret nb.psignrank(a, x[2usize], x[3usize], lower, lg) }
        ret nb.qsignrank(a, x[2usize], x[3usize], lower, lg)
    }
    if fam == 14u8 {
        if kind == 0u8 { ret nb.dwilcox(a, x[2usize], x[3usize], x[4usize], lg) }
        if kind == 1u8 { ret nb.pwilcox(a, x[2usize], x[3usize], x[4usize], lower, lg) }
        ret nb.qwilcox(a, x[2usize], x[3usize], x[4usize], lower, lg)
    }
    if fam == 11u8 { ret nb.qbeta(x[2usize], x[3usize], x[4usize], lower, lg) }
    if fam == 12u8 { ret nb.qf(x[2usize], x[3usize], x[4usize], lower, lg) }
    if fam == 10u8 {
        if kind == 0u8 { ret nb.dhyper(x[2usize], x[3usize], x[4usize], x[7usize], lg) }
        if kind == 1u8 { ret nb.phyper(x[2usize], x[3usize], x[4usize], x[7usize], lower, lg) }
        ret nb.qhyper(x[2usize], x[3usize], x[4usize], x[7usize], lower, lg)
    }
    if fam == 5u8 {
        if kind == 0u8 { ret nb.dgeom(x[2usize], x[3usize], lg) }
        if kind == 1u8 { ret nb.pgeom(x[2usize], x[3usize], lower, lg) }
        ret nb.qgeom(x[2usize], x[3usize], lower, lg)
    }
    if fam == 6u8 {
        if kind == 0u8 { ret nb.dnbinom(x[2usize], x[3usize], x[4usize], lg) }
        if kind == 1u8 { ret nb.pnbinom(x[2usize], x[3usize], x[4usize], lower, lg) }
        ret nb.qnbinom(x[2usize], x[3usize], x[4usize], lower, lg)
    }
    if fam == 7u8 {
        if kind == 0u8 { ret nb.dnbinom_mu(x[2usize], x[3usize], x[4usize], lg) }
        ret nb.pnbinom_mu(x[2usize], x[3usize], x[4usize], lower, lg)
    }
    if fam == 8u8 { ret nb.qbinom(x[2usize], x[3usize], x[4usize], lower, lg) }
    if fam == 9u8 { ret nb.qt(x[2usize], x[3usize], lower, lg) }
    if fam == 3u8 {
        if kind == 0u8 { ret nb.dt(x[2usize], x[3usize], lg) }
        ret nb.pt(x[2usize], x[3usize], lower, lg)
    }
    if fam == 4u8 {
        if kind == 0u8 { ret nb.df(x[2usize], x[3usize], x[4usize], lg) }
        ret nb.pf(x[2usize], x[3usize], x[4usize], lower, lg)
    }
    if fam == 0u8 {
        if kind == 0u8 { ret nb.dbeta(x[2usize], x[3usize], x[4usize], lg) }
        ret nb.pbeta(x[2usize], x[3usize], x[4usize], lower, lg)
    }
    if kind == 0u8 { ret nb.dbinom(x[2usize], x[3usize], x[4usize], lg) }
    ret nb.pbinom(x[2usize], x[3usize], x[4usize], lower, lg)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nmath_beta.json")
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
            if failures <= 30usize {
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
