// e.algo.stat.gsdesign against gsDesign. tests/oracle/gsdesign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gsdesign`; the layout is at the top of scripts/r_oracle/groups/gsdesign.R.

use e.algo.stat.gsdesign as gs
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gsdesign.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        let got = gs.spend(usize(x[0usize]), x[1usize], x[2usize], x[3usize], x[4usize])
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
