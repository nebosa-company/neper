// e.math.nmath against R's nmath: gamma, lgamma, and d and p of the gamma, chi-squared and
// Poisson distributions with lower.tail and log.p. tests/oracle/nmath.json comes from
// `Rscript scripts/r_oracle/generate.R nmath`; the layout is at the top of scripts/r_oracle/groups/nmath.R.

use e.io
use e.math.nmath as nm
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let fam = u8(x[0usize])
    let kind = u8(x[1usize])
    let lower = x[5usize] != 0.0f64
    let lg = x[6usize] != 0.0f64
    if fam == 3u8 { ret nm.gammafn(x[2usize]) }
    if fam == 4u8 { ret nm.lgammafn(x[2usize]) }
    if fam == 0u8 {
        if kind == 0u8 { ret nm.dgamma(x[2usize], x[3usize], x[4usize], lg) }
        ret nm.pgamma(x[2usize], x[3usize], x[4usize], lower, lg)
    }
    if fam == 1u8 {
        if kind == 0u8 { ret nm.dchisq(x[2usize], x[3usize], lg) }
        ret nm.pchisq(x[2usize], x[3usize], lower, lg)
    }
    if kind == 0u8 { ret nm.dpois(x[2usize], x[3usize], lg) }
    ret nm.ppois(x[2usize], x[3usize], lower, lg)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nmath.json")
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
