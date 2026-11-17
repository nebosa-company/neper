// e.algo.stat.quantreg against quantreg::rq (method br). tests/oracle/quantreg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg`; the layout is at the top of
// scripts/r_oracle/groups/quantreg.R.

use e.algo.stat.quantreg as qr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let y = x[4usize..4usize + n]
    let (d, de) = mem.alloc[f64](a, n * p)
    if de != ok { ret 0.0f64 / 0.0f64 }
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
    if x[3usize] >= 100.0f64 {
        let (se, see) = mem.alloc[f64](a, p)
        if see != ok { ret 0.0f64 / 0.0f64 }
        if qr.rq_se_nid(a, d, y, n, p, x[2usize], se) != ok { ret 0.0f64 / 0.0f64 }
        ret se[usize(x[3usize]) - 100usize]
    }
    let (b, be) = qr.rq(a, d, y, n, p, x[2usize])
    if be != ok { ret 0.0f64 / 0.0f64 }
    ret b[usize(x[3usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg.json")
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
