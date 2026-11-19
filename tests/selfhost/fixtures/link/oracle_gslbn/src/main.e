// e.algo.stat.gslbn against gsl, value and error estimate. tests/oracle/gslbn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslbn`; the layout of each case is at the top of scripts/r_oracle/groups/gslbn.R.

use e.algo.stat.gslbn as gn
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(a: *mem.Arena, code: usize, n: i64, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gn.bessel_yn(n, x)
        ret (v, e)
    }
    if code == 1usize {
        let (v1, e1) = gn.kn(n, x)
        ret (v1, e1)
    }
    if code == 2usize {
        let (v2, e2) = gn.kn_scaled(n, x)
        ret (v2, e2)
    }
    if code == 3usize {
        let (v3, e3) = gn.in_(a, n, x)
        ret (v3, e3)
    }
    let (v4, e4) = gn.in_scaled(a, n, x)
    ret (v4, e4)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(a, usize(x[0usize]), i64(x[2usize]), x[3usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslbn.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
