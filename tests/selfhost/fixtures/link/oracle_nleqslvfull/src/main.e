// e.algo.stat.nleqslvfull against nleqslv. tests/oracle/nleqslvfull.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nleqslvfull`; the argument layout is at the top of scripts/r_oracle/groups/nleqslvfull.R.

use e.algo.stat.nleqslvfull as nl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nleqslvfull.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let sys = usize(x[0usize])
        let n = nl.dim_of(sys)
        let (w0, good) = nl.new_ws(a, sys)
        if !good { os.exit(5) }
        var w = w0
        var maxit = 150usize
        if usize(x[2usize]) == 0usize { maxit = 20usize }
        nl.solve(&w, x[6usize..6usize + n], usize(x[1usize]), usize(x[2usize]), usize(x[3usize]), x[4usize] == 1.0f64, maxit, 0.0f64 - 2.0f64)
        var got = 0.0f64
        let j = usize(x[5usize])
        if str.eq(c.name, "x") {
            got = w.xp[j]
        } else if str.eq(c.name, "termcd") {
            got = w.info[0usize]
        } else if str.eq(c.name, "iter") {
            got = w.info[1usize]
        } else if str.eq(c.name, "nfcnt") {
            got = w.info[2usize]
        } else if str.eq(c.name, "njcnt") {
            got = w.info[3usize]
        } else {
            got = w.sx[j]
        }
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
