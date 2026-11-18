// e.algo.stat.vcdeffect.interpret_index against effectsize interpret_cohens_d, interpret_r, interpret_rank_biserial, interpret_eta_squared and interpret_oddsratio.
// tests/oracle/vcd_interpret.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vcd_interpret`; the layout is at the top of scripts/r_oracle/groups/vcd_interpret.R.

use e.algo.stat.vcdeffect as ve
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vcd_interpret.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = f64(ve.interpret_index(usize(c.args[0usize]), c.args[1usize]))
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
