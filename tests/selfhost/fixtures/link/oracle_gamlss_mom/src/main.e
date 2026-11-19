// e.algo.stat.gamlssdist's family_moment against gamlss.dist. tests/oracle/gamlss_mom.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_mom`; the layout is at the top of scripts/r_oracle/groups/gamlss_mom.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_mom.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        var got = gd.family_moment(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize])
        if c.name.len == 2usize && c.name[0usize] == 109u8 { got = gd.family_mn(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], x[4usize], x[5usize], x[6usize]) }
        if c.name.len == 3usize { got = gd.family_moment2(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], x[4usize], x[5usize]) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
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
