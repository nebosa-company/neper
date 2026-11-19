// the default links and the link functions of the gamlss.dist family objects (e.algo.stat.gamlsslink.family_link and the make.link.gamlss functions) for all 116 families against gamlss.dist;
// tests/oracle/gamlss_famlink.json is `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_famlink`; the layout of a case is at the top of scripts/r_oracle/groups/gamlss_famlink.R.

use e.algo.stat.gamlsslink as gl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = gl.family_link(usize(z[0usize]), usize(z[1usize]))
    let what = usize(z[2usize])
    if what == 3usize { ret f64(kind) }
    if what == 0usize { ret gl.linkfun(kind, z[3usize]) }
    if what == 1usize { ret gl.linkinv(kind, z[3usize]) }
    ret gl.mu_eta(kind, z[3usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_famlink.json")
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
