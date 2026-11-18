// e.algo.stat.gamlsslink against gamlss.dist::make.link.gamlss. tests/oracle/gamlss_link.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_link`; the layout is at the top of scripts/r_oracle/groups/gamlss_link.R.

use e.algo.stat.gamlsslink as gl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let what = usize(z[1usize])
    if what == 0usize { ret gl.linkfun(kind, z[2usize]) }
    if what == 1usize { ret gl.linkinv(kind, z[2usize]) }
    ret gl.mu_eta(kind, z[2usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_link.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
