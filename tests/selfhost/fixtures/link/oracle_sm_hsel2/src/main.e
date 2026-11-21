// e.algo.stat.sm's two-covariate regression h.select (hr2, hr2o) against sm. tests/oracle/sm_hsel2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sm_hsel2`; the layout is at the top of scripts/r_oracle/groups/sm_hsel2.R.

use e.algo.stat.sm as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sm_hsel2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let n = usize(c.args[0usize])
        var got = 0.0f64
        if str.eq(c.name, "hr2o") {
            got = sm.hselect_reg_2d_other(a, c.args[4usize..4usize + n], c.args[4usize + n..4usize + 2usize * n], c.args[4usize + 2usize * n..4usize + 3usize * n], usize(c.args[1usize]), 12.0f64, usize(c.args[3usize]), usize(c.args[2usize]))
        } else {
            got = sm.hselect_reg_2d(c.args[3usize..3usize + n], c.args[3usize + n..3usize + 2usize * n], c.args[3usize + 2usize * n..3usize + 3usize * n], usize(c.args[1usize]), 12.0f64, usize(c.args[2usize]))
        }
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
