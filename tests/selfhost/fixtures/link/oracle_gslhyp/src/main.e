// e.algo.stat.gslhyp against gsl, value and error estimate. tests/oracle/gslhyp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslhyp`; the layout of each case is at the top of scripts/r_oracle/groups/gslhyp.R.

use e.algo.stat.gslhyp as gh
use e.algo.stat.gslhg as gg
use e.algo.stat.gslh2f1 as g2
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var v = 0.0f64
    var e = 0.0f64
    let code = usize(x[0usize])
    if code == 0usize {
        let (v0, e0) = gh.hyperg_0f1(a, x[2usize], x[3usize])
        v = v0
        e = e0
    }
    if code == 1usize {
        let (v1, e1) = gg.hyperg_1f1(a, x[2usize], x[3usize], x[4usize])
        v = v1
        e = e1
    }
    if code == 2usize {
        let (v2, e2) = gg.hyperg_1f1_int(a, i64(x[2usize]), i64(x[3usize]), x[4usize])
        v = v2
        e = e2
    }
    if code == 3usize {
        let (v3, e3) = gg.hyperg_u(a, x[2usize], x[3usize], x[4usize])
        v = v3
        e = e3
    }
    if code == 4usize {
        let (v4, e4) = gg.hyperg_u_int(a, i64(x[2usize]), i64(x[3usize]), x[4usize])
        v = v4
        e = e4
    }
    if code == 5usize {
        let (v5, e5) = gg.hyperg_2f0(a, x[2usize], x[3usize], x[4usize])
        v = v5
        e = e5
    }
    if code == 6usize {
        let (v6, e6) = g2.hyperg_2f1(a, x[2usize], x[3usize], x[4usize], x[5usize])
        v = v6
        e = e6
    }
    if code == 7usize {
        let (v7, e7) = g2.hyperg_2f1_conj(x[2usize], x[3usize], x[4usize], x[5usize])
        v = v7
        e = e7
    }
    if code == 8usize {
        let (v8, e8) = g2.hyperg_2f1_renorm(a, x[2usize], x[3usize], x[4usize], x[5usize])
        v = v8
        e = e8
    }
    if code == 9usize {
        let (v9, e9) = g2.hyperg_2f1_conj_renorm(x[2usize], x[3usize], x[4usize], x[5usize])
        v = v9
        e = e9
    }
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslhyp.json")
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
