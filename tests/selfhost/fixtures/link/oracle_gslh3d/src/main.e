// e.algo.stat.gslh3d against gsl, value and error estimate. tests/oracle/gslh3d.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslh3d`; the layout of each case is at the top of scripts/r_oracle/groups/gslh3d.R.

use e.algo.stat.gslh3d as gh
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let code = usize(x[0usize])
    if code == 3usize { ret gh.h3d_array_elt(i64(x[5usize]), x[3usize], x[4usize], i64(x[2usize])) }
    var v = 0.0f64
    var e = 0.0f64
    if code == 0usize {
        let (v0, e0) = gh.h3d_0(x[3usize], x[4usize])
        v = v0
        e = e0
    }
    if code == 1usize {
        let (v1, e1) = gh.h3d_1(x[3usize], x[4usize])
        v = v1
        e = e1
    }
    if code == 2usize {
        let (v2, e2) = gh.h3d(i64(x[2usize]), x[3usize], x[4usize])
        v = v2
        e = e2
    }
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslh3d.json")
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
