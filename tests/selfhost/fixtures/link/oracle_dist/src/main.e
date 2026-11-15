// e.math.dist against R's nmath: d, p and q of norm, unif, exp, weibull, logis, cauchy and lnorm
// with lower.tail and log.p. tests/oracle/dist.json comes from `Rscript scripts/r_oracle/generate.R
// dist`; the layout is at the top of scripts/r_oracle/groups/dist.R.

use e.io
use e.math.dist as d
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let fam = u8(x[0usize])
    let kind = u8(x[1usize])
    let v = x[2usize]
    let a = x[3usize]
    let b = x[4usize]
    let lower = x[5usize] != 0.0f64
    let lg = x[6usize] != 0.0f64
    if fam == 0u8 {
        if kind == 0u8 { ret d.dnorm(v, a, b, lg) }
        if kind == 1u8 { ret d.pnorm(v, a, b, lower, lg) }
        ret d.qnorm(v, a, b, lower, lg)
    }
    if fam == 1u8 {
        if kind == 0u8 { ret d.dunif(v, a, b, lg) }
        if kind == 1u8 { ret d.punif(v, a, b, lower, lg) }
        ret d.qunif(v, a, b, lower, lg)
    }
    if fam == 2u8 {
        if kind == 0u8 { ret d.dexp(v, a, lg) }
        if kind == 1u8 { ret d.pexp(v, a, lower, lg) }
        ret d.qexp(v, a, lower, lg)
    }
    if fam == 3u8 {
        if kind == 0u8 { ret d.dweibull(v, a, b, lg) }
        if kind == 1u8 { ret d.pweibull(v, a, b, lower, lg) }
        ret d.qweibull(v, a, b, lower, lg)
    }
    if fam == 4u8 {
        if kind == 0u8 { ret d.dlogis(v, a, b, lg) }
        if kind == 1u8 { ret d.plogis(v, a, b, lower, lg) }
        ret d.qlogis(v, a, b, lower, lg)
    }
    if fam == 5u8 {
        if kind == 0u8 { ret d.dcauchy(v, a, b, lg) }
        if kind == 1u8 { ret d.pcauchy(v, a, b, lower, lg) }
        ret d.qcauchy(v, a, b, lower, lg)
    }
    if kind == 0u8 { ret d.dlnorm(v, a, b, lg) }
    if kind == 1u8 { ret d.plnorm(v, a, b, lower, lg) }
    ret d.qlnorm(v, a, b, lower, lg)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dist.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 25usize {
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
