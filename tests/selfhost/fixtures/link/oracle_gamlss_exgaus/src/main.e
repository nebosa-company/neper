// e.algo.stat.gamlssdist's exGAUS density and distribution against gamlss.dist (dexGAUS, pexGAUS). tests/oracle/gamlss_exgaus.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_exgaus`; the layout of every case is at the top of scripts/r_oracle/groups/gamlss_exgaus.R.

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
    let nu = z[3usize]
    let x = z[4usize]
    if which == 0usize { ret gd.dexgaus(x, mu, sigma, nu) }
    if which == 2usize { ret gd.qexgaus(x, mu, sigma, nu) }
    ret gd.pexgaus(x, mu, sigma, nu)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_exgaus.json")
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
