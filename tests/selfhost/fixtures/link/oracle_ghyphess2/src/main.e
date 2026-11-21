// e.algo.stat.ghyphess2 against GeneralizedHyperbolic hyperbHessian, nigHessian and gigHessian. tests/oracle/ghyphess2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghyphess2`; the layout is at the top of scripts/r_oracle/groups/ghyphess2.R.

use e.algo.rand.r as rg
use e.algo.stat.ghyp as gh
use e.algo.stat.ghyphess as gx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nn = usize(x[1usize])
    let (d, g1) = mem.alloc[f64](a, nn)
    let (xx, g2) = mem.alloc[f64](a, nn)
    if g1 != ok || g2 != ok { os.exit(7) }
    var rng: rg.Rng = zero
    rg.seed(&rng, i64(x[0usize]))
    var hess: [16]f64 = zero
    var se: [4]f64 = zero
    if str.eq(c.name, "gighess") {
        gh.rgig(&rng, nn, x[7usize], x[8usize], x[9usize], d)
        gx.gig_hessian(d, x[4usize..7usize], hess[0usize..9usize])
        let i = usize(x[2usize])
        let j = usize(x[3usize])
        if i == 3usize {
            if !gx.hess_se(hess[0usize..9usize], 3usize, se[0usize..3usize]) { ret 0.0f64 / 0.0f64 }
            ret se[j]
        }
        ret hess[i * 3usize + j]
    }
    var lam = 1.0f64
    if x[2usize] == 1.0f64 { lam = 0.0f64 - 0.5f64 }
    gh.rghyp(&rng, nn, x[11usize], x[12usize], x[13usize], x[14usize], lam, d, xx)
    let set = usize(x[3usize])
    if x[4usize] == 0.0f64 {
        gx.hyperb_exact_hessian(d, set, x[7usize..11usize], hess[0usize..16usize])
    } else {
        gx.hyperb_ts_hessian(d, usize(x[2usize]), set, x[7usize..11usize], hess[0usize..16usize])
    }
    let i = usize(x[5usize])
    let j = usize(x[6usize])
    if i == 4usize {
        if !gx.hess_se(hess[0usize..16usize], 4usize, se[0usize..4usize]) { ret 0.0f64 / 0.0f64 }
        ret se[j]
    }
    ret hess[i * 4usize + j]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghyphess2.json")
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
