// e.algo.stat.gslsync against gsl, value and error estimate. tests/oracle/gslsync.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslsync`; the layout of each case is at the top of scripts/r_oracle/groups/gslsync.R.

use e.algo.stat.gslsync as gs
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gs.synchrotron_1(x)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = gs.synchrotron_2(x)
        ret (v, e)
    }
    let (v2, e2) = gs.transport(code, x)
    ret (v2, e2)
}

fn answer(c: *const oracle.Case) -> f64 {
    let a = c.args
    let (v, e) = pair(usize(a[0usize]), a[2usize])
    if usize(a[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslsync.json")
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
