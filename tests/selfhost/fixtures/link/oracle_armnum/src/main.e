// e.algo.stat.armld and the correctly rounded functions of e.algo.stat.armglm against R. tests/oracle/armnum.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R armnum`; the layout of a case is at the top of scripts/r_oracle/groups/armnum.R.

use e.algo.stat.armglm as ag
use e.algo.stat.armld as ld
use e.algo.stat.armtan as tn
use e.algo.stat.armx87 as xe
use e.algo.stat.armdt as dr
use e.io
use e.math
use e.math.dist as dist
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "ldsum") {
        let n = usize(x[1usize])
        if x[0usize] == 0.0f64 { ret ld.sum_ld(x[2usize..2usize + n]) }
        if x[0usize] == 1.0f64 { ret ld.mean_ld(x[2usize..2usize + n]) }
        if x[0usize] == 2.0f64 { ret ld.var_ld(x[2usize..2usize + n]) }
        ret ld.colmean_ld(x[2usize..2usize + n])
    }
    let v = x[1usize]
    if x[0usize] == 0.0f64 { ret ag.exp_cr(v) }
    if x[0usize] == 1.0f64 { ret ag.log_cr(v) }
    if x[0usize] == 2.0f64 { ret ag.pow3(v) }
    if x[0usize] == 3.0f64 { ret ag.pow15(v) }
    if x[0usize] == 4.0f64 { ret ag.pnorm_cr(v) }
    if x[0usize] == 5.0f64 { ret ag.dnorm_cr(v) }
    if x[0usize] == 6.0f64 { ret tn.atan_c(v) }
    if x[0usize] == 7.0f64 { ret tn.pcauchy_c(v) }
    if x[0usize] == 8.0f64 { ret dist.dcauchy(v, 0.0f64, 1.0f64, false) }
    if x[0usize] == 9.0f64 { ret ag.qcauchy_r(v) }
    if x[0usize] == 16.0f64 { ret xe.exp_r(v) }
    if x[0usize] == 17.0f64 { ret xe.log_r(v) }
    if x[0usize] == 18.0f64 { ret tn.tan_c(v) }
    if x[0usize] == 19.0f64 { ret xe.exp_r(0.0f64 - xe.exp_r(0.0f64 - v)) }
    if x[0usize] == 12.0f64 { ret dr.log1p_r(v) }
    if x[0usize] == 11.0f64 { ret dr.dt_r(v, x[2usize], true) }
    ret ag.qnorm_r(v)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/armnum.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
