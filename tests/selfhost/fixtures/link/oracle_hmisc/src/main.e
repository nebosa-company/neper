// e.algo.stat.hmisc against Hmisc: binconf, wtd.mean, wtd.var and somers2. tests/oracle/hmisc.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hmisc`; the layout is at the top of
// scripts/r_oracle/groups/hmisc.R.

use e.algo.stat.hmisc as hm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "bc_lo") || str.eq(c.name, "bc_hi") {
        let (lo, hi) = hm.binconf(x[0usize], x[1usize], x[2usize], u8(x[3usize]))
        if str.eq(c.name, "bc_lo") { ret lo }
        ret hi
    }
    let n = usize(x[0usize])
    if str.eq(c.name, "wmean") { ret hm.wtd_mean(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n]) }
    if str.eq(c.name, "wvar") { ret hm.wtd_var(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n]) }
    let (cc, d) = hm.somers2(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
    if str.eq(c.name, "c") { ret cc }
    ret d
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hmisc.json")
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
