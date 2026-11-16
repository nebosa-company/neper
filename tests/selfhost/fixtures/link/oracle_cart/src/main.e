// e.algo.stat.cart against rpart (anova). tests/oracle/cart.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cart`; the layout is at the top of scripts/r_oracle/groups/cart.R.

use e.algo.stat.cart as ct
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (t, e) = ct.rpart_anova(a, x[5usize + n..5usize + n + n * p], x[5usize..5usize + n], n, p, usize(x[2usize]), usize(x[3usize]), x[4usize])
    if e != ok { os.exit(5) }
    if str.eq(c.name, "nleaf") { ret f64(t.nleaf) }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += t.fitted[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cart.json")
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
