// e.algo.stat.gamlssdist's BCCGo against gamlss.dist. tests/oracle/gamlss_bccgo.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_bccgo`; the layout is at the top of scripts/r_oracle/groups/gamlss_bccgo.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "sid") { ret gd.dsi(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(c.name, "sip") { ret gd.psi_cdf(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(c.name, "s3d") { ret gd.dst3(z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) }
    if str.eq(c.name, "s3p") { ret gd.pst3(z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) }
    if str.eq(c.name, "s3q") { ret gd.qst3(z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) }
    if str.eq(c.name, "bd") { ret gd.dbccgo(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(c.name, "bp") { ret gd.pbccgo(z[3usize], z[0usize], z[1usize], z[2usize]) }
    ret gd.qbccgo(z[3usize], z[0usize], z[1usize], z[2usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_bccgo.json")
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
