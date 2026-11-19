// e.algo.stat.gslell against gsl, value and error estimate. tests/oracle/gslell.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslell`; the layout of each case is at the top of scripts/r_oracle/groups/gslell.R.

use e.algo.stat.gslell as el
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn arg(x: []const f64, i: usize) -> f64 {
    if i < x.len { ret x[i] }
    ret 0.0f64
}

fn pair(code: usize, mode: usize, a: f64, b: f64, c: f64, d: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = el.rc(a, b, mode)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = el.rd(a, b, c, mode)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = el.rf(a, b, c, mode)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = el.rj(a, b, c, d, mode)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = el.ell_f(a, b, mode)
        ret (v, e)
    }
    if code == 5usize {
        let (v, e) = el.ell_e(a, b, mode)
        ret (v, e)
    }
    if code == 6usize {
        let (v, e) = el.ell_p(a, b, c, mode)
        ret (v, e)
    }
    if code == 7usize {
        let (v, e) = el.ell_d(a, b, mode)
        ret (v, e)
    }
    if code == 8usize {
        let (v, e) = el.kcomp(a, mode)
        ret (v, e)
    }
    let (v9, e9) = el.ecomp(a, mode)
    ret (v9, e9)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), usize(x[2usize]), arg(x, 3usize), arg(x, 4usize), arg(x, 5usize), arg(x, 6usize))
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslell.json")
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
