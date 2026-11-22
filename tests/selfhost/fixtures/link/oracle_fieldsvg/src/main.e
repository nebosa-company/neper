// e.algo.stat.fieldsvg against fields. tests/oracle/fieldsvg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fieldsvg`; the layout is at the top of scripts/r_oracle/groups/fieldsvg.R.

use e.algo.stat.fieldsvg as fv
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 { ret fv.answer(a, c.args) }

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fieldsvg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
