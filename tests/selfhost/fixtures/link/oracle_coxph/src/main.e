// e.algo.stat.cox against survival::coxph (Breslow and Efron ties). tests/oracle/coxph.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coxph`; the layout is at the top of
// scripts/r_oracle/groups/coxph.R.

use e.algo.stat.cox as cx
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let tm = x[3usize..3usize + n]
    let st = x[3usize + n..3usize + 2usize * n]
    let xm = x[3usize + 2usize * n..3usize + 2usize * n + n * p]
    let q = usize(x[3usize + 2usize * n + n * p])
    let (coef, e1) = mem.alloc[f64](a, p)
    let (se, e2) = mem.alloc[f64](a, p)
    let (ll, e3) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    let fe = cx.coxph(a, tm, st, xm, n, p, x[2usize] != 0.0f64, coef, se, ll)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    if q < p { ret coef[q] }
    if q < 2usize * p { ret se[q - p] }
    ret ll[q - 2usize * p]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coxph.json")
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
