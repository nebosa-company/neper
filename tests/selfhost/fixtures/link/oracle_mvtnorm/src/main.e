// e.algo.stat.mvtnorm against mvtnorm: dmvnorm and dmvt (log), rmvnorm (eigen and chol) and rmvt under
// set.seed. tests/oracle/mvtnorm.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// mvtnorm`; the layouts are at the top of scripts/r_oracle/groups/mvtnorm.R.

use e.algo.rand.r as rr
use e.algo.stat.mvtnorm as mv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "dmvnorm") {
        let p = usize(x[0usize])
        let (v, e) = mv.dmvnorm(a, x[1usize..1usize + p], x[1usize + p..1usize + 2usize * p], x[1usize + 2usize * p..1usize + 2usize * p + p * p], p)
        if e != ok { os.exit(6) }
        ret v
    }
    if str.eq(c.name, "dmvt") {
        let p = usize(x[0usize])
        let (v, e) = mv.dmvt(a, x[2usize..2usize + p], x[2usize + p..2usize + 2usize * p], x[2usize + 2usize * p..2usize + 2usize * p + p * p], p, x[1usize])
        if e != ok { os.exit(6) }
        ret v
    }
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[0usize]))
    let method = u8(x[1usize])
    let n = usize(x[2usize])
    let p = usize(x[3usize])
    if str.eq(c.name, "rmvnorm") {
        let (r, e) = mv.rmvnorm(a, &g, n, x[4usize..4usize + p], x[4usize + p..4usize + p + p * p], p, method)
        if e != ok { os.exit(7) }
        ret r[usize(x[x.len - 1usize])]
    }
    let df = x[4usize]
    let (r, e) = mv.rmvt(a, &g, n, x[5usize + p..5usize + p + p * p], p, df, x[5usize..5usize + p], method)
    if e != ok { os.exit(8) }
    ret r[usize(x[x.len - 1usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mvtnorm.json")
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
            if failures <= 15usize {
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
