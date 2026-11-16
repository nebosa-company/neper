// e.algo.stat.fminsearchpkg against pracma::fminsearch. tests/oracle/fminsearchpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fminsearchpkg`; the layout is at the top of scripts/r_oracle/groups/fminsearchpkg.R.

use e.algo.stat.fminsearchpkg as fm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fminsearchpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let id = usize(x[0usize])
        let n = fm.dim_of(id)
        let (xmin, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let (work, e2) = mem.alloc[f64](a, 8usize * (n + 1usize) * n)
        if e2 != ok { os.exit(6) }
        let (fmin, count, restarts) = fm.nelder_mead(id, x[3usize..3usize + n], 1.0e-8f64, 5000usize, xmin, work)
        var got = 0.0f64
        let what = usize(x[1usize])
        if what == 0usize { got = xmin[usize(x[2usize])] }
        if what == 1usize { got = fmin }
        if what == 2usize { got = f64(count) }
        if what == 3usize { got = f64(restarts) }
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
