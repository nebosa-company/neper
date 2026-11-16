// e.algo.stat.catoolspkg against caTools. tests/oracle/catoolspkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R catoolspkg`; the layout is at the top of scripts/r_oracle/groups/catoolspkg.R.

use e.algo.stat.catoolspkg as ct
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/catoolspkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[4usize])
        let k = usize(x[1usize])
        let (tmp, e1) = mem.alloc[f64](a, k + 2usize)
        if e1 != ok { os.exit(5) }
        let got = ct.window_stat(x[5usize..5usize + n], usize(x[3usize]), (k - 1usize) / 2usize, usize(x[0usize]), x[2usize], tmp)
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
