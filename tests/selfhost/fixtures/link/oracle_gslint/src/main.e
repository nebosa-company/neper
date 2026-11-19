// e.algo.stat.gslint against gsl, value and error estimate. tests/oracle/gslint.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslint`; the layout of each case is at the top of scripts/r_oracle/groups/gslint.R.

use e.algo.stat.gslint as gi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gi.si(x)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = gi.ci(x)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = gi.shi(x)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = gi.chi(x)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = gi.atanint(x)
        ret (v, e)
    }
    let (v5, e5) = gi.expint_3(x)
    ret (v5, e5)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[2usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslint.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 16usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
