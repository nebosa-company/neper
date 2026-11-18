// e.algo.stat.energy's normal_e and mvnorm_e against energy. tests/oracle/energy_normal.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R energy_normal`; the layout is at the top of scripts/r_oracle/groups/energy_normal.R.

use e.algo.stat.energy as en
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/energy_normal.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        let got = en.mvnorm_e(a, z[2usize..2usize + n * d], n, d)
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
