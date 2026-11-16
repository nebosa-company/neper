// e.algo.stat.gmmpkg against gmm. tests/oracle/gmmpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gmmpkg`; the layout is at the top of scripts/r_oracle/groups/gmmpkg.R.

use e.algo.stat.gmmpkg as gm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gmmpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[4usize])
        let p = usize(x[5usize])
        let q = usize(x[6usize])
        let got = gm.gmm_linear(a, x[7usize..7usize + n], x[7usize + n..7usize + n + n * p], x[7usize + n + n * p..7usize + n + n * p + n * q], n, p, q, usize(x[2usize]), x[3usize], usize(x[0usize]), usize(x[1usize]))
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
