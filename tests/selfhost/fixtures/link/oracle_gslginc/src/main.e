// e.algo.stat.gslginc against gsl, value and error estimate. tests/oracle/gslginc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslginc`; the layout of each case is at the top of scripts/r_oracle/groups/gslginc.R.

use e.algo.stat.gslginc as gi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, a: f64, b: f64, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gi.gamma_inc(a, x)
        ret (v, e)
    }
    if code == 1usize {
        let (v1, e1) = gi.gamma_inc_p(a, x)
        ret (v1, e1)
    }
    if code == 2usize {
        let (v2, e2) = gi.gamma_inc_q(a, x)
        ret (v2, e2)
    }
    let (v3, e3) = gi.beta_inc(a, b, x)
    ret (v3, e3)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[2usize], x[3usize], x[4usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslginc.json")
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
