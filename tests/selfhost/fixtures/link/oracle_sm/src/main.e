// e.algo.stat.sm against sm. tests/oracle/sm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sm`; the layout is at the top of scripts/r_oracle/groups/sm.R.

use e.algo.stat.sm as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    let n = usize(x[0usize])
    if str.eq(k, "hn1") { ret sm.hnorm(x[1usize..1usize + n], 1usize) }
    if str.eq(k, "hn2") { ret sm.hnorm(x[1usize..1usize + n], 2usize) }
    if str.eq(k, "dens1") { ret sm.density1(x[3usize..3usize + n], x[1usize], x[2usize]) }
    if str.eq(k, "dens2") { ret sm.density2(x[5usize..5usize + n], x[5usize + n..5usize + 2usize * n], x[1usize], x[2usize], x[3usize], x[4usize]) }
    ret sm.regression(x[4usize..4usize + n], x[4usize + n..4usize + 2usize * n], x[1usize], x[2usize], usize(x[3usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sm.json")
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
