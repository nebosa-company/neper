// e.algo.stat.hdrcdepkg against hdrcde. tests/oracle/hdrcdepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hdrcdepkg`; the layout is at the top of scripts/r_oracle/groups/hdrcdepkg.R.

use e.algo.stat.desctools as dt
use e.algo.stat.hdrcdepkg as hd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hdrcdepkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[4usize])
        let xs = x[5usize..5usize + n]
        let (s, e1) = dt.sorted_copy(a, xs)
        if e1 != ok { os.exit(5) }
        let (gx, e2) = mem.alloc[f64](a, 512usize)
        if e2 != ok { os.exit(6) }
        let (gy, e3) = mem.alloc[f64](a, 512usize)
        if e3 != ok { os.exit(7) }
        let (sc, e4) = mem.alloc[f64](a, 2560usize)
        if e4 != ok { os.exit(8) }
        let (fx, e5) = mem.alloc[f64](a, n)
        if e5 != ok { os.exit(9) }
        let (ends, e6) = mem.alloc[f64](a, 100usize)
        if e6 != ok { os.exit(10) }
        hd.den_grid(xs, s, x[3usize], gx, gy, sc)
        let alpha = 1.0f64 - x[2usize]
        let fa = hd.falpha_of(xs, gx, gy, alpha, fx)
        var got = fa
        let what = usize(x[0usize])
        if what >= 1usize {
            let cnt = hd.hdr_ends(gx, gy, fa, ends)
            if what == 1usize { got = f64(cnt) } else if usize(x[1usize]) < cnt { got = ends[usize(x[1usize])] } else { got = 0.0f64 - 1.0f64 }
        }
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
