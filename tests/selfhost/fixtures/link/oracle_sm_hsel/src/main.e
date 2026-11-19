// e.algo.stat.sm's hselect_cv (h.select cv) against sm. tests/oracle/sm_hsel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sm_hsel`; the layout is at the top of scripts/r_oracle/groups/sm_hsel.R.

use e.algo.stat.sm as sm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sm_hsel.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let n = usize(c.args[0usize])
        let got = sm.hselect_cv(c.args[1usize..1usize + n])
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
