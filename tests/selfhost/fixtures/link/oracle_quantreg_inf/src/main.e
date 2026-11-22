// e.algo.stat.quantreg inference and fitters against quantreg. tests/oracle/quantreg_inf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg_inf`; the layout is at the top of
// scripts/r_oracle/groups/quantreg_inf.R.

use e.algo.stat.quantreg as qr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let tau = x[2usize]
    let mode = usize(x[3usize])
    let y = x[6usize..6usize + n]
    let (d, de) = mem.alloc[f64](a, n * p)
    if de != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < (p - 1usize) * n {
        d[n + k] = x[6usize + n + k]
        k += 1usize
    }
    let (se, see) = mem.alloc[f64](a, p)
    if see != ok { ret 0.0f64 / 0.0f64 }
    if mode >= 300usize {
        let (taus, te) = mem.alloc[f64](a, 5usize)
        let (out, oe) = mem.alloc[f64](a, 5usize * p)
        if oe != ok || te != ok { ret 0.0f64 / 0.0f64 }
        taus[0usize] = 0.1f64
        taus[1usize] = 0.3f64
        taus[2usize] = 0.5f64
        taus[3usize] = 0.7f64
        taus[4usize] = 0.9f64
        if qr.rq_taus(a, d, y, n, p, taus, out) != ok { ret 0.0f64 / 0.0f64 }
        ret out[mode - 300usize]
    }
    let (b, be) = qr.rq(a, d, y, n, p, tau)
    if be != ok { ret 0.0f64 / 0.0f64 }
    if mode >= 200usize {
        if qr.rq_se_boot(a, d, y, n, p, tau, usize(x[5usize]), i64(x[4usize]), se) != ok { ret 0.0f64 / 0.0f64 }
        ret se[mode - 200usize]
    }
    if mode >= 100usize {
        if qr.rq_se_iid(a, d, y, n, p, tau, b, se) != ok { ret 0.0f64 / 0.0f64 }
        ret se[mode - 100usize]
    }
    ret b[mode]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg_inf.json")
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
