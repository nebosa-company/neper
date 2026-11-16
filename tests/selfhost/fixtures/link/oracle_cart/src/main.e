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
    if str.eq(c.name, "cl_nleaf") || str.eq(c.name, "cl_pred") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let kk = usize(x[2usize])
        let (yc, e1) = mem.alloc[usize](a, n)
        if e1 != ok { os.exit(6) }
        let (pr, e2) = mem.alloc[usize](a, n)
        if e2 != ok { os.exit(7) }
        var i = 0usize
        while i < n {
            yc[i] = usize(x[6usize + i])
            i += 1usize
        }
        let (nl, e3) = ct.rpart_class_pruned(a, x[6usize + n..6usize + n + n * p], yc, n, p, kk, usize(x[3usize]), usize(x[4usize]), x[5usize], pr)
        if e3 != ok { os.exit(8) }
        if str.eq(c.name, "cl_nleaf") { ret f64(nl) }
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += f64(pr[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
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
