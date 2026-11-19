// e.algo.stat.gslerr2 against gsl, value and error estimate. tests/oracle/gslerr2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslerr2`; the layout of each case is at the top of scripts/r_oracle/groups/gslerr2.R.

use e.algo.stat.gslerr2 as g2
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pair(code: usize, a: f64, b: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = g2.e_hypot(a, b)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = g2.e_sinc(a)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = g2.e_lnsinh(a)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = g2.e_lncosh(a)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = g2.e_log_1plusx(a)
        ret (v, e)
    }
    if code == 5usize {
        let (v, e) = g2.e_taylorcoeff(i64(a), b)
        ret (v, e)
    }
    if code == 6usize {
        let (v, e) = g2.e_doublefact(usize(a))
        ret (v, e)
    }
    if code == 7usize {
        let (v, e) = g2.e_lnfact(usize(a))
        ret (v, e)
    }
    if code == 8usize {
        let (v, e) = g2.e_lndoublefact(usize(a))
        ret (v, e)
    }
    if code == 9usize {
        let (v, e) = g2.e_choose_full(usize(a), usize(b))
        ret (v, e)
    }
    if code == 10usize {
        let (v, e) = g2.e_gammastar(a)
        ret (v, e)
    }
    if code == 11usize {
        let (v, e) = g2.e_gamma(a)
        ret (v, e)
    }
    if code == 12usize {
        let (v, e) = g2.e_lnbeta(a, b)
        ret (v, e)
    }
    let (v1, e1) = g2.e_log_1plusx_mx(a)
    ret (v1, e1)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (v, e) = pair(usize(x[0usize]), x[2usize], x[3usize])
    if usize(x[1usize]) == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslerr2.json")
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
