// e.algo.stat.tvpack.tvtl against mvtnorm's TVPACK trivariate. tests/oracle/tvpack.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tvpack`; the layout is at the top of scripts/r_oracle/groups/tvpack.R.

use e.algo.stat.tvpack as tvpack
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    ret tvpack.tvtl(i64(z[0usize]), z[1usize..4usize], z[4usize..7usize], z[7usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tvpack.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
