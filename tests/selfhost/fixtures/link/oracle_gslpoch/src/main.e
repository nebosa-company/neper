// e.algo.stat.gslpoch against gsl, value and error estimate. tests/oracle/gslpoch.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslpoch`; the layout of each case is at the top of scripts/r_oracle/groups/gslpoch.R.

use e.algo.stat.gslpoch as gp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let code = usize(x[0usize])
    let part = usize(x[1usize])
    var v = 0.0f64
    var e = 0.0f64
    var s = 1.0f64
    if code == 0usize {
        let (v0, e0) = gp.lnpoch(a, x[2usize], x[3usize])
        v = v0
        e = e0
    }
    if code == 1usize {
        let (v1, e1) = gp.poch(a, x[2usize], x[3usize])
        v = v1
        e = e1
    }
    if code == 2usize {
        let (v2, e2) = gp.pochrel(a, x[2usize], x[3usize])
        v = v2
        e = e2
    }
    if code == 3usize {
        let (v3, e3, s3) = gp.lnpoch_sgn(a, x[2usize], x[3usize])
        v = v3
        e = e3
        s = s3
    }
    if part == 0usize { ret v }
    if part == 1usize { ret e }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslpoch.json")
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
