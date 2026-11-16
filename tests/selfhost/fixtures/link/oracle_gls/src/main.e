// e.algo.stat.gls against nlme::gls with a fixed correlation structure. tests/oracle/gls.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gls`; the layout is at the top of
// scripts/r_oracle/groups/gls.R.

use e.algo.stat.gls as g
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let tm = x[5usize..5usize + n]
    let y = x[5usize + n..5usize + 2usize * n]
    let xm = x[5usize + 2usize * n..5usize + 2usize * n + n * p]
    let q = usize(x[5usize + 2usize * n + n * p])
    let (coef, ce) = mem.alloc[f64](a, p)
    if ce != ok { ret 0.0f64 / 0.0f64 }
    let (f, fe) = g.gls(a, xm, y, tm, n, p, u8(x[2usize]), x[3usize], x[4usize] != 0.0f64, coef)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    if q < p { ret coef[q] }
    if q == p { ret f.sigma }
    ret f.loglik
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gls.json")
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
