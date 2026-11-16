// e.algo.stat.lowesspkg against stats::lowess. tests/oracle/lowesspkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lowesspkg`; the layout is at the top of scripts/r_oracle/groups/lowesspkg.R.

use e.algo.stat.lowesspkg as lw
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lowesspkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[4usize])
        let (x1, e1) = mem.alloc[f64](a, n + 2usize)
        if e1 != ok { os.exit(5) }
        let (y1, e2) = mem.alloc[f64](a, n + 2usize)
        if e2 != ok { os.exit(6) }
        let (ys, e3) = mem.alloc[f64](a, n + 2usize)
        if e3 != ok { os.exit(7) }
        let (w, e4) = mem.alloc[f64](a, n + 2usize)
        if e4 != ok { os.exit(8) }
        let (rw, e5) = mem.alloc[f64](a, n + 2usize)
        if e5 != ok { os.exit(9) }
        let (res, e6) = mem.alloc[f64](a, n + 2usize)
        if e6 != ok { os.exit(10) }
        let (srt, e7) = mem.alloc[f64](a, n + 2usize)
        if e7 != ok { os.exit(11) }
        var i = 0usize
        while i < n {
            x1[i + 1usize] = x[5usize + i]
            y1[i + 1usize] = x[5usize + n + i]
            i += 1usize
        }
        lw.clowess(x1, y1, n, x[0usize], usize(x[1usize]), x[2usize], ys, w, rw, res, srt)
        let got = ys[usize(x[3usize]) + 1usize]
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
