// e.algo.stat.glmnet: cox, multinomial, cv, relax and predict against glmnet. tests/oracle/glmnet_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glmnet_ext`; the case layout is at the top of scripts/r_oracle/groups/glmnet_ext.R.

use e.algo.stat.glmnet as gl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 {
    ret 0.0f64 / 0.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let alpha = x[2usize]
    let std = x[3usize] != 0.0f64
    let nl = usize(x[4usize])
    let hw = usize(x[5usize])
    let hb = usize(x[6usize])
    let ho = usize(x[7usize])
    let lam = x[8usize..8usize + nl]
    let vf = x[8usize + nl..8usize + nl + p]
    let d0 = 8usize + nl + p
    var dl = 0usize
    if str.eq(c.name, "cox") || str.eq(c.name, "coxlen") || str.eq(c.name, "coxlam") { dl = 2usize * n }
    let tm = x[d0..d0 + n]
    let st = x[d0 + n..d0 + 2usize * n]
    let xo = d0 + dl
    let xm = x[xo..xo + n * p]
    let wo = xo + n * p
    let wts = x[wo..wo + n * hw]
    let bo = wo + n * hw
    let lo = x[bo..bo + p * hb]
    let up = x[bo + p * hb..bo + 2usize * p * hb]
    let oo = bo + 2usize * p * hb
    let off = x[oo..oo + n * ho]
    let qo = oo + n * ho
    if str.eq(c.name, "cox") {
        let (cf, e1) = mem.alloc[f64](a, nl * p)
        let (dv, e2) = mem.alloc[f64](a, nl)
        if e1 != ok || e2 != ok { ret nan() }
        if gl.cox(a, xm, tm, st, wts, off, lo, up, n, p, alpha, std, vf, lam, cf, dv) != ok { ret nan() }
        ret cf[usize(x[qo]) * p + usize(x[qo + 1usize]) - 1usize]
    }
    if str.eq(c.name, "coxlen") {
        ret f64(gl.cox_path_len(a, xm, tm, st, wts, off, lo, up, n, p, alpha, std, vf, 100usize))
    }
    if str.eq(c.name, "coxlam") {
        let (lo2, e1) = mem.alloc[f64](a, 100usize)
        if e1 != ok { ret nan() }
        if gl.cox_lambda_path(a, xm, tm, st, wts, off, n, p, alpha, std, vf, 100usize, lo2) != ok { ret nan() }
        ret lo2[usize(x[qo])]
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/glmnet_ext.json")
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
                let _ = io.print(c.name)
                let _ = io.print(" ")
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
