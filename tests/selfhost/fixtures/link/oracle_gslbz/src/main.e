// e.algo.stat.gslbzero against gsl, value and error estimate. tests/oracle/gslbz.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslbz`; the layout of each case is at the top of scripts/r_oracle/groups/gslbz.R.

use e.algo.stat.gslbzero as gz
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, nu: f64, s: usize) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gz.bessel_zero_j0(s)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = gz.bessel_zero_j1(s)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = gz.bessel_zero_jnu(nu, s)
        ret (v, e)
    }
    let (v3, e3) = gz.airy_zero(code - 3usize, s)
    ret (v3, e3)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[2usize], usize(x[3usize]))
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslbz.json")
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
