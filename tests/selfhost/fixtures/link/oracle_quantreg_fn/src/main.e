// e.algo.stat.quantreg Frisch-Newton, lasso and pfn fits against quantreg. tests/oracle/quantreg_fn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg_fn`; the layout is at the top of
// scripts/r_oracle/groups/quantreg_fn.R.

use e.algo.rand.r as rr
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
    let kind = usize(x[3usize]) / 10usize
    let j = usize(x[3usize]) % 10usize
    let seed = i64(x[4usize])
    let y = x[6usize..6usize + n]
    let (d, de) = mem.alloc[f64](a, n * p)
    let (lam, le) = mem.alloc[f64](a, p)
    if de != ok || le != ok { ret 0.0f64 / 0.0f64 }
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
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    if kind == 0usize {
        let (b, be) = qr.rq_fnb(a, d, y, n, p, tau, 1.0e-6f64)
        if be != ok { ret 0.0f64 / 0.0f64 }
        ret b[j]
    }
    if kind == 1usize {
        lam[0usize] = 0.0f64
        k = 1usize
        while k < p {
            lam[k] = x[5usize]
            k += 1usize
        }
        let (b, be) = qr.rq_lasso(a, d, y, n, p, tau, lam, 1.0e-6f64)
        if be != ok { ret 0.0f64 / 0.0f64 }
        ret b[j]
    }
    if kind == 2usize || kind == 4usize {
        if qr.lasso_lambda_hat(a, d, n, p, tau, &rng, lam) != ok { ret 0.0f64 / 0.0f64 }
        if kind == 4usize { ret lam[j] }
        let (b, be) = qr.rq_lasso(a, d, y, n, p, tau, lam, 1.0e-6f64)
        if be != ok { ret 0.0f64 / 0.0f64 }
        ret b[j]
    }
    let (b, be) = qr.rq_pfn(a, d, y, n, p, tau, 0.8f64, 3usize, 1.0e-6f64, &rng)
    if be != ok { ret 0.0f64 / 0.0f64 }
    ret b[j]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg_fn.json")
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
