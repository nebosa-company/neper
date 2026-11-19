// e.algo.stat.gslspecial against gsl, value and error estimate. tests/oracle/gslspecial.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslspecial`; the layout of each case is at the top of scripts/r_oracle/groups/gslspecial.R.

use e.algo.stat.gslspecial as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = sp.dawson(x)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = sp.clausen(x)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = sp.expint_e1(x, false)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = sp.expint_e2(x, false)
        ret (v, e)
    }
    let (v4, e4) = sp.expint_ei(x)
    ret (v4, e4)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[2usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslspecial.json")
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
