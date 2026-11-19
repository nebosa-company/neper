// e.algo.stat.gslerr against gsl, value and error estimate. tests/oracle/gslerr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslerr`; the layout of each case is at the top of scripts/r_oracle/groups/gslerr.R.

use e.algo.stat.gslerr as ge
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn arg(x: []const f64, i: usize) -> f64 {
    if i < x.len { ret x[i] }
    ret 0.0f64
}

// (value, error) of function `code`
fn pair(code: usize, a: f64, b: f64, c: f64) -> (f64, f64) {
    if code == 0usize {
        let (v, e) = ge.e_sin(a)
        ret (v, e)
    }
    if code == 1usize {
        let (v, e) = ge.e_cos(a)
        ret (v, e)
    }
    if code == 2usize {
        let (v, e) = ge.e_log(a)
        ret (v, e)
    }
    if code == 3usize {
        let (v, e) = ge.e_log_abs(a)
        ret (v, e)
    }
    if code == 4usize {
        let (v, e) = ge.e_pow_int(a, i64(b))
        ret (v, e)
    }
    if code == 5usize {
        let (v, e) = ge.e_fact(usize(a))
        ret (v, e)
    }
    if code == 6usize {
        let (v, e) = ge.e_choose(usize(a), usize(b))
        ret (v, e)
    }
    if code == 7usize {
        let (v, e) = ge.e_erf_z(a)
        ret (v, e)
    }
    if code == 8usize {
        let (v, e) = ge.e_lngamma(a)
        ret (v, e)
    }
    if code == 9usize {
        let (v, e, _s) = ge.e_lngamma_sgn(a)
        ret (v, e)
    }
    if code == 10usize {
        let (v, e) = ge.e_psi_1piy(a)
        ret (v, e)
    }
    if code == 11usize {
        let (v, e) = ge.e_legendre_p1(a)
        ret (v, e)
    }
    if code == 12usize {
        let (v, e) = ge.e_legendre_p2(a)
        ret (v, e)
    }
    if code == 13usize {
        let (v, e) = ge.e_legendre_p3(a)
        ret (v, e)
    }
    if code == 14usize {
        let (v, e) = ge.e_legendre_pl(usize(a), b)
        ret (v, e)
    }
    if code == 15usize {
        let (v, e) = ge.e_legendre_plm(usize(a), usize(b), c)
        ret (v, e)
    }
    if code == 16usize {
        let (v, e) = ge.e_laguerre_1(a, b)
        ret (v, e)
    }
    if code == 17usize {
        let (v, e) = ge.e_laguerre_2(a, b)
        ret (v, e)
    }
    if code == 18usize {
        let (v, e) = ge.e_laguerre_3(a, b)
        ret (v, e)
    }
    if code == 19usize {
        let (v, e) = ge.e_gegenpoly_1(a, b)
        ret (v, e)
    }
    if code == 20usize {
        let (v, e) = ge.e_gegenpoly_2(a, b)
        ret (v, e)
    }
    if code == 21usize {
        let (v, e) = ge.e_gegenpoly_3(a, b)
        ret (v, e)
    }
    if code == 22usize {
        let (v, e) = ge.e_gegenpoly_n(usize(a), b, c)
        ret (v, e)
    }
    if code == 23usize {
        let (v, e) = ge.e_legendre_q0(a)
        ret (v, e)
    }
    let (v1, e1) = ge.e_legendre_q1(a)
    ret (v1, e1)
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let code = usize(x[0usize])
    let part = usize(x[1usize])
    if part == 2usize {
        let (_v, _e, s) = ge.e_lngamma_sgn(arg(x, 2usize))
        ret s
    }
    let (v, e) = pair(code, arg(x, 2usize), arg(x, 3usize), arg(x, 4usize))
    if part == 0usize { ret v }
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslerr.json")
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
