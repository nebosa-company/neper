// e.algo.stat.quantreg restricted fits (rq.fit.fnc, the rrq of the plan) and rqss with the total-variation penalty against quantreg.
// tests/oracle/quantreg_rs.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg_rs`; the layout is at the
// top of scripts/r_oracle/groups/quantreg_rs.R.

use e.algo.stat.quantreg as qr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    if kind == 0usize {
        let n = usize(x[1usize])
        let p = usize(x[2usize])
        let tau = x[3usize]
        let n2 = usize(x[4usize])
        let j = usize(x[5usize])
        let y = x[6usize..6usize + n]
        let xm = x[6usize + n..6usize + n + n * p]
        let rm = x[6usize + n + n * p..6usize + n + n * p + n2 * p]
        let rv = x[6usize + n + n * p + n2 * p..6usize + n + n * p + n2 * p + n2]
        let (b, be) = qr.rq_fnc(a, xm, y, n, p, rm, rv, n2, tau, 0.9995f64, 1.0e-6f64)
        if be != ok { ret 0.0f64 / 0.0f64 }
        ret b[j]
    }
    let n = usize(x[1usize])
    let lambda = x[2usize]
    let tau = x[3usize]
    let dorder = i64(x[4usize])
    let j = usize(x[5usize])
    let y = x[6usize..6usize + n]
    let xs = x[6usize + n..6usize + 2usize * n]
    let (b, be) = qr.rqss_tv(a, xs, y, n, lambda, dorder, tau)
    if be != ok { ret 0.0f64 / 0.0f64 }
    ret b[j]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg_rs.json")
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
