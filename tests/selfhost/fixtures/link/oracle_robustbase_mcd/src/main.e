// e.algo.stat.robustbase covMcd against robustbase. tests/oracle/robustbase_mcd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R robustbase_mcd`; the layout is at the top of scripts/r_oracle/groups/robustbase_mcd.R.

use e.algo.stat.robustbase as rb
use e.io
use e.algo.rand.r as rng
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let (o, oe) = mem.alloc[f64](a, 2usize * p + 2usize * p * p + 2usize)
    if oe != ok { os.exit(5) }
    if rb.cov_mcd(a, &g, x[5usize..5usize + n * p], n, p, x[3usize], usize(x[4usize]), o) != ok { os.exit(6) }
    ret o[usize(x[5usize + n * p])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/robustbase_mcd.json")
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
