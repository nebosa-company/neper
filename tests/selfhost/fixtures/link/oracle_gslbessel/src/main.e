// e.algo.stat.gslbessel against gsl, value and error estimate. tests/oracle/gslbessel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslbessel`; the layout of each case is at the top of scripts/r_oracle/groups/gslbessel.R.

use e.algo.stat.gslbessel as gb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gb.i0(x)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = gb.i0_scaled(x)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = gb.i1(x)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = gb.i1_scaled(x)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = gb.k0(x)
        ret (v, e)
    }
    if code == 5usize {
        let (v, e) = gb.k0_scaled(x)
        ret (v, e)
    }
    if code == 6usize {
        let (v, e) = gb.k1(x)
        ret (v, e)
    }
    let (v7, e7) = gb.k1_scaled(x)
    ret (v7, e7)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[2usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslbessel.json")
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
