// e.algo.stat.gslairy against gsl, value and error estimate. tests/oracle/gslairy.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslairy`; the layout of each case is at the top of scripts/r_oracle/groups/gslairy.R.

use e.algo.stat.gslairy as ga
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, x: f64, mode: usize) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = ga.airy_ai(x, mode)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = ga.airy_ai_scaled(x, mode)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = ga.airy_bi(x, mode)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = ga.airy_bi_scaled(x, mode)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = ga.airy_ai_deriv(x, mode)
        ret (v, e)
    }
    if code == 5usize {
        let (v, e) = ga.airy_ai_deriv_scaled(x, mode)
        ret (v, e)
    }
    if code == 6usize {
        let (v, e) = ga.airy_bi_deriv(x, mode)
        ret (v, e)
    }
    let (v7, e7) = ga.airy_bi_deriv_scaled(x, mode)
    ret (v7, e7)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[3usize], usize(x[2usize]))
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslairy.json")
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
