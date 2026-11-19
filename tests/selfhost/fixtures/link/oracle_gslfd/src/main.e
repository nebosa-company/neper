// e.algo.stat.gslfd against gsl, value and error estimate. tests/oracle/gslfd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslfd`; the layout of each case is at the top of scripts/r_oracle/groups/gslfd.R.

use e.algo.stat.gslfd as fd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(a: *mem.Arena, code: usize, p: f64, q: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = fd.fd_m1(p)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = fd.fd_0(p)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = fd.fd_1(p)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = fd.fd_2(p)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = fd.fd_mhalf(a, p)
        ret (v, e)
    }
    if code == 5usize {
        let (v, e) = fd.fd_half(a, p)
        ret (v, e)
    }
    if code == 6usize {
        let (v, e) = fd.fd_3half(a, p)
        ret (v, e)
    }
    if code == 7usize {
        let (v, e) = fd.fd_int(a, i64(p), q)
        ret (v, e)
    }
    let (v1, e1) = fd.fd_inc_0(p, q)
    ret (v1, e1)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(a, usize(x[0usize]), x[2usize], x[3usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslfd.json")
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
