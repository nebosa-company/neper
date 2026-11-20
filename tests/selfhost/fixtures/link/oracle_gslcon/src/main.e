// e.algo.stat.gslcon against gsl, value and error estimate. tests/oracle/gslcon.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslcon`; the layout of each case is at the top of scripts/r_oracle/groups/gslcon.R.

use e.algo.stat.gslcon as gk
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let code = usize(x[0usize])
    var v = 0.0f64
    var e = 0.0f64
    if code == 0usize {
        let (v0, e0) = gk.con_0(x[3usize], x[4usize])
        v = v0
        e = e0
    }
    if code == 1usize {
        let (v1, e1) = gk.con_1(x[3usize], x[4usize])
        v = v1
        e = e1
    }
    if code == 2usize {
        let (v2, e2) = gk.con_sph_reg(i64(x[2usize]), x[3usize], x[4usize])
        v = v2
        e = e2
    }
    // the CRAN gsl wrapper for conicalP_cyl_reg calls gsl_sf_conicalP_sph_reg_e, so R answers with the spherical function
    if code == 3usize {
        let (v3, e3) = gk.con_sph_reg(i64(x[2usize]), x[3usize], x[4usize])
        v = v3
        e = e3
    }
    if code == 4usize {
        let (v4, e4) = gk.con_half(x[3usize], x[4usize])
        v = v4
        e = e4
    }
    if code == 5usize {
        let (v5, e5) = gk.con_mhalf(x[3usize], x[4usize])
        v = v5
        e = e5
    }
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslcon.json")
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
