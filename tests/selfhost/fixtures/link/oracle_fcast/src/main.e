// e.algo.stat.fcast against forecast: BoxCox, InvBoxCox and BoxCox.lambda(method = "loglik").
// tests/oracle/fcast.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fcast`; the layout is
// at the top of scripts/r_oracle/groups/fcast.R.

use e.algo.stat.fcast as fc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "bc") { ret fc.box_cox(x[0usize], x[1usize]) }
    if str.eq(c.name, "ibc") { ret fc.inv_box_cox(fc.box_cox(x[0usize], x[1usize]), x[1usize]) }
    if str.eq(c.name, "guer") {
        let gn = usize(x[1usize])
        let (work, we) = mem.alloc[f64](a, gn + 1usize)
        if we != ok { ret 0.0f64 / 0.0f64 }
        ret fc.guerrero(x[2usize..2usize + gn], usize(x[0usize]), x[2usize + gn], x[3usize + gn], work)
    }
    if str.eq(c.name, "cro") {
        let cn = usize(x[2usize])
        let (fits, fe) = mem.alloc[f64](a, cn)
        let (work, we) = mem.alloc[f64](a, 2usize * cn)
        if fe != ok || we != ok { ret 0.0f64 / 0.0f64 }
        let level = fc.croston(x[3usize..3usize + cn], x[1usize], usize(x[0usize]), fits, work)
        let pos = usize(x[3usize + cn])
        if pos == cn { ret level }
        ret fits[pos]
    }
    let n = usize(x[0usize])
    let (logx, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret fc.box_cox_lambda_loglik(x[1usize..1usize + n], x[1usize + n], x[2usize + n], logx)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fcast.json")
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
