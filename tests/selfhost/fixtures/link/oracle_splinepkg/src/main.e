// e.algo.stat.splinepkg against stats::spline. tests/oracle/splinepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R splinepkg`; the layout is at the top of scripts/r_oracle/groups/splinepkg.R.

use e.algo.stat.splinepkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/splinepkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[2usize])
        let xs = x[3usize..3usize + n]
        let ys = x[3usize + n..3usize + 2usize * n]
        let (b, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let (cc, e2) = mem.alloc[f64](a, n)
        if e2 != ok { os.exit(6) }
        let (d, e3) = mem.alloc[f64](a, n)
        if e3 != ok { os.exit(7) }
        var i = 0usize
        while i < n {
            b[i] = 0.0f64
            cc[i] = 0.0f64
            d[i] = 0.0f64
            i += 1usize
        }
        if x[0usize] == 0.0f64 { sp.fmm_spline(n, xs, ys, b, cc, d) } else { sp.natural_spline(n, xs, ys, b, cc, d) }
        let u = x[3usize + 2usize * n + usize(x[1usize])]
        let got = sp.spline_eval(n, xs, ys, b, cc, d, u)
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
