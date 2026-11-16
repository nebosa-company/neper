// e.algo.stat.metaforpkg against metafor. tests/oracle/metaforpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R metaforpkg`; the layout is at the top of scripts/r_oracle/groups/metaforpkg.R.

use e.algo.stat.metaforpkg as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/metaforpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        let k = usize(x[2usize])
        var got = mf.rma(x[3usize..3usize + k], x[3usize + k..3usize + 2usize * k], usize(x[0usize]), usize(x[1usize]))
        if str.eq(c.name, "knha") { got = mf.rma_knha(x[3usize..3usize + k], x[3usize + k..3usize + 2usize * k], usize(x[0usize]), usize(x[1usize])) }
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
