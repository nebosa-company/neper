// e.algo.stat.arm against arm. tests/oracle/arm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R arm`; the layout is at the top of scripts/r_oracle/groups/arm.R.

use e.algo.stat.arm as arm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn stdlm_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let q = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, q + 1usize)
    if e != ok { os.exit(20) }
    if arm.standardize_lm(a, x[2usize + n..2usize + n + n * q], x[2usize..2usize + n], n, q, o) != ok { os.exit(21) }
    ret o[usize(x[2usize + n + n * q])]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "logit") { ret arm.logit(x[0usize]) }
    if str.eq(k, "invlogit") { ret arm.invlogit(x[0usize]) }
    if str.eq(k, "stdlm") { ret stdlm_answer(a, c) }
    if str.eq(k, "bayesglm") {
        let n = usize(x[0usize])
        let kk = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, kk)
        if e != ok { os.exit(30) }
        if arm.bayesglm(a, x[3usize..3usize + n * kk], x[3usize + n * kk..3usize + n * kk + n], n, kk, usize(x[2usize]), o) == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[usize(x[3usize + n * kk + n])]
    }
    if str.eq(k, "rescale") {
        let n = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { os.exit(8) }
        arm.rescale(x[2usize..2usize + n], n, usize(x[0usize]), o)
        ret o[usize(x[2usize + n])]
    }
    if str.eq(k, "se") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, p)
        if e != ok { os.exit(5) }
        if arm.se_coef(a, x[2usize..2usize + n * p], x[2usize + n * p..2usize + n * p + n], n, p, o) != ok { os.exit(6) }
        ret o[usize(x[2usize + n * p + n])]
    }
    let nc = usize(x[0usize])
    let n = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, (nc + 1usize) * 6usize)
    if e != ok { os.exit(7) }
    let rows = arm.binned_resids(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], nc, o)
    if str.eq(k, "binned_rows") { ret f64(rows) }
    let cc = usize(x[2usize + 2usize * n])
    let b = usize(x[3usize + 2usize * n])
    if b >= rows { ret 0.0f64 - 1.0f64 }
    ret o[b * 6usize + cc]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/arm.json")
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
