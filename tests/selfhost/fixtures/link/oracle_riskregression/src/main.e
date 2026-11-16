// e.algo.stat.riskregpkg against riskRegression Score(). tests/oracle/riskregression.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R riskregression`; the layout is at the top of scripts/r_oracle/groups/riskregression.R.

use e.algo.stat.riskregpkg as rr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (out, e1) = mem.alloc[f64](a, 2usize)
    if e1 != ok { ret nan }
    if rr.score(a, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], z[2usize + 2usize * n..2usize + 3usize * n], z[1usize], out) != ok { ret nan }
    if str.eq(c.name, "brier") { ret out[0usize] }
    ret out[1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/riskregression.json")
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
