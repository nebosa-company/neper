// e.algo.stat.robustbase_lts (ltsReg) against robustbase. tests/oracle/robustbase_lts.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R robustbase_lts`; the layout is at the top of scripts/r_oracle/groups/robustbase_lts.R.

use e.algo.stat.robustbase_lts as lt
use e.io
use e.algo.rand.r as rng
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let pp = usize(x[2usize])
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let icpt = x[3usize] != 0.0f64
    var p = pp
    if icpt { p = pp + 1usize }
    let alpha = x[4usize]
    let n2 = (n + p + 1usize) / 2usize
    let h = usize(f64(2usize * n2) - f64(n) + 2.0f64 * f64(n - n2) * alpha)
    let (o, oe) = mem.alloc[f64](a, 2usize * p + 5usize + 3usize * n + h + 4usize)
    if oe != ok { os.exit(5) }
    if lt.lts_reg(a, &g, x[6usize..6usize + n * pp], x[6usize + n * pp..6usize + n * pp + n], n, pp, icpt, alpha, usize(x[5usize]), o) != ok { os.exit(6) }
    ret o[usize(x[6usize + n * pp + n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/robustbase_lts.json")
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
