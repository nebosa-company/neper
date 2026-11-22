// e.algo.stat.quantreg rank-inversion intervals and coefficient table against quantreg. tests/oracle/quantreg_rank.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg_rank`; the layout is at the top of
// scripts/r_oracle/groups/quantreg_rank.R.

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
    let y = x[4usize..4usize + n]
    let (d, de) = mem.alloc[f64](a, n * p)
    let (out, oe) = mem.alloc[f64](a, 3usize * p)
    let (raw, re) = mem.alloc[f64](a, 8usize * p)
    let (se, see) = mem.alloc[f64](a, p)
    let (tv, te) = mem.alloc[f64](a, p)
    let (pv, pe) = mem.alloc[f64](a, p)
    if de != ok || oe != ok || re != ok || see != ok || te != ok || pe != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < (p - 1usize) * n {
        d[n + k] = x[4usize + n + k]
        k += 1usize
    }
    if kind <= 2usize {
        if qr.rq_rank(a, d, y, n, p, tau, 0.1f64, true, true, true, out, raw) != ok { ret 0.0f64 / 0.0f64 }
    } else if kind <= 4usize {
        if qr.rq_rank(a, d, y, n, p, tau, 0.1f64, false, true, true, out, raw) != ok { ret 0.0f64 / 0.0f64 }
    } else if kind <= 6usize {
        if qr.rq_rank(a, d, y, n, p, tau, 0.05f64, true, false, true, out, raw) != ok { ret 0.0f64 / 0.0f64 }
    } else {
        let (b, be) = qr.rq(a, d, y, n, p, tau)
        if be != ok { ret 0.0f64 / 0.0f64 }
        if qr.rq_se_iid(a, d, y, n, p, tau, b, se) != ok { ret 0.0f64 / 0.0f64 }
        qr.rq_tvalues(b, se, f64(n - p), tv, pv)
        if kind == 7usize { ret tv[j] }
        ret pv[j]
    }
    if kind == 0usize { ret out[3usize * j] }
    if kind == 1usize || kind == 3usize || kind == 5usize { ret out[3usize * j + 1usize] }
    ret out[3usize * j + 2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg_rank.json")
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
