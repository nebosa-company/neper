// e.algo.stat.uwot's find_ab against uwot's find_ab_params. tests/oracle/uwotab.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R uwotab`; the layout is at the top of scripts/r_oracle/groups/uwotab.R.

use e.algo.stat.uwot as uw
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var ab: [2]f64 = zero
    if uw.find_ab(a, x[0usize], x[1usize], ab[0usize..2usize]) != ok { ret 0.0f64 - 1.0e300f64 }
    ret ab[usize(x[2usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/uwotab.json")
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
            if failures <= 6usize {
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
