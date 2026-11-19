// e.algo.stat.gslleg against gsl, value and error estimate. tests/oracle/gslleg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslleg`; the layout of each case is at the top of scripts/r_oracle/groups/gslleg.R.

use e.algo.stat.gslleg as gl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var v = 0.0f64
    var e = 0.0f64
    if usize(x[0usize]) == 0usize {
        let (v0, e0) = gl.legendre_ql(i64(x[2usize]), x[4usize])
        v = v0
        e = e0
    }
    if usize(x[0usize]) == 1usize {
        let (v1, e1) = gl.legendre_sphplm(a, i64(x[2usize]), i64(x[3usize]), x[4usize])
        v = v1
        e = e1
    }
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslleg.json")
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
