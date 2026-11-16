// e.algo.stat.fitdist against fitdistrplus. tests/oracle/fitdist.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fitdist`; the layout is at the top of scripts/r_oracle/groups/fitdist.R.

use e.algo.stat.fitdist as fd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let v = x[2usize..2usize + n]
    let (f, e) = fd.fit(a, v, kind)
    if e != ok { os.exit(5) }
    let k = c.name
    if str.eq(k, "p1") { ret f.p1 }
    if str.eq(k, "p2") { ret f.p2 }
    if str.eq(k, "ll") { ret f.loglik }
    if str.eq(k, "aic") { ret fd.aic(&f) }
    if str.eq(k, "bic") { ret fd.bic(&f, n) }
    let (ks, cvm, ad) = fd.gof(a, v, kind, &f)
    if str.eq(k, "ks") { ret ks }
    if str.eq(k, "cvm") { ret cvm }
    ret ad
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fitdist.json")
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
