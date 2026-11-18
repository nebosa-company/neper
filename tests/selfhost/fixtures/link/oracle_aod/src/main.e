// e.algo.stat.aod against aod. tests/oracle/aod.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R aod`; the layout is at the top of scripts/r_oracle/groups/aod.R.

use e.algo.stat.aod as ad
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = usize(x[3usize])
    let n = x[4usize..4usize + k]
    let y = x[4usize + k..4usize + 2usize * k]
    if str.eq(c.name, "iccbin") { ret ad.iccbin_c(n, y) }
    if str.eq(c.name, "donner") {
        let grp = x[4usize + 2usize * k..4usize + 3usize * k]
        let r = ad.donner(n, y, grp, usize(x[4usize + 3usize * k]))
        if x[0usize] == 0.0f64 { ret r.rho }
        ret r.x2
    }
    ret ad.varbin(n, y, x[2usize], usize(x[0usize]), usize(x[1usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/aod.json")
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
