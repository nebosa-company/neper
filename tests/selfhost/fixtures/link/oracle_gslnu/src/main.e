// e.algo.stat.gslnu against gsl, value and error estimate. tests/oracle/gslnu.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslnu`; the layout of each case is at the top of scripts/r_oracle/groups/gslnu.R.

use e.algo.stat.gslnu as gu
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(a: *mem.Arena, code: usize, nu: f64, x: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = gu.bessel_jnu(a, nu, x)
        ret (v, e)
    }
    if code == 1usize {
        let (v1, e1) = gu.bessel_ynu(a, nu, x)
        ret (v1, e1)
    }
    if code == 2usize {
        let (v2, e2) = gu.inu(a, nu, x)
        ret (v2, e2)
    }
    if code == 3usize {
        let (v3, e3) = gu.inu_scaled(a, nu, x)
        ret (v3, e3)
    }
    if code == 4usize {
        let (v4, e4) = gu.knu(nu, x)
        ret (v4, e4)
    }
    if code == 5usize {
        let (v5, e5) = gu.knu_scaled(nu, x)
        ret (v5, e5)
    }
    if code == 6usize {
        let (v6, e6) = gu.bessel_lnknu(nu, x)
        ret (v6, e6)
    }
    if code == 7usize {
        let (v7, e7) = gu.jn_full(a, i64(nu), x)
        ret (v7, e7)
    }
    if code == 8usize {
        let (v8, e8) = gu.yn_full(i64(nu), x)
        ret (v8, e8)
    }
    if code == 9usize {
        let (v9, e9) = gu.kn_full(i64(nu), x)
        ret (v9, e9)
    }
    if code == 10usize {
        let (v10, e10) = gu.kn_scaled_full(i64(nu), x)
        ret (v10, e10)
    }
    if code == 11usize {
        let (v11, e11) = gu.in_full(a, i64(nu), x)
        ret (v11, e11)
    }
    let (v12, e12) = gu.in_scaled_full(a, i64(nu), x)
    ret (v12, e12)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(a, usize(x[0usize]), x[2usize], x[3usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslnu.json")
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
