// e.algo.stat.stabledistpkg against stabledist::dstable. tests/oracle/stabledist.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R stabledist`; the layout is at the top of scripts/r_oracle/groups/stabledist.R.

use e.algo.stat.stabledistpkg as sd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/stabledist.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        var got = 0.0f64
        if str.eq(c.name, "p") { got = sd.pstable(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) } else { got = sd.dstable(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) }
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
