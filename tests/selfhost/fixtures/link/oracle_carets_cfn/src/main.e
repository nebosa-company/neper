// e.algo.stat.carets's create_folds_numeric against caret createFolds. tests/oracle/carets_cfn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R carets_cfn`; the layout is at the top of scripts/r_oracle/groups/carets_cfn.R.

use e.algo.rand.r as rr
use e.algo.stat.carets as cr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[2usize])
    let (fold, e) = mem.alloc[i64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[0usize]))
    if cr.create_folds_numeric(a, &g, z[3usize..3usize + n], usize(z[1usize]), fold) != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(i + 1usize) * f64(fold[i])
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/carets_cfn.json")
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
