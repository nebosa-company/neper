// e.algo.stat.nleqslvpkg against nleqslv and multiroot. tests/oracle/nleqslvpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nleqslvpkg`; the layout is at the top of scripts/r_oracle/groups/nleqslvpkg.R.

use e.algo.stat.nleqslvpkg as nl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nleqslvpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let sys = usize(x[0usize])
        let n = nl.dim_of(sys)
        let (root, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let iters = nl.solve(a, sys, x[2usize..2usize + n], root)
        var got = 0.0f64 - 1.0e9f64
        if iters > 0usize { got = root[usize(x[1usize])] }
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
