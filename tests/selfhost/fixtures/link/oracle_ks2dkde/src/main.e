// e.algo.stat.ks2dkde against ks (gridded kde, contourLevels, rkde). tests/oracle/ks2dkde.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks2dkde`; the layouts are at the top of scripts/r_oracle/groups/ks2dkde.R.

use e.algo.stat.ks2dkde as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.eq(nm, "rkde1") {
        let n = usize(x[1usize])
        let size = usize(x[3usize])
        let (o, e) = mem.alloc[f64](a, size)
        if e != ok { os.exit(5) }
        if ks.rkde1(a, i64(x[0usize]), x[5usize..5usize + n], x[2usize], size, o) != ok { os.exit(6) }
        ret o[usize(x[4usize])]
    }
    if str.eq(nm, "rkde2") {
        let n = usize(x[1usize])
        let size = usize(x[6usize])
        let (o, e) = mem.alloc[f64](a, size * 2usize)
        if e != ok { os.exit(5) }
        if ks.rkde2(a, i64(x[0usize]), x[8usize..8usize + 2usize * n], n, x[2usize..6usize], size, o) != ok { os.exit(6) }
        ret o[usize(x[7usize])]
    }
    let n = usize(x[0usize])
    let m = 151usize
    if str.eq(nm, "kdecont") { ret ks.kde_contour(a, x[6usize..6usize + 2usize * n], n, x[1usize..5usize], m, x[5usize]) }
    let (gx, e1) = mem.alloc[f64](a, m)
    let (gy, e2) = mem.alloc[f64](a, m)
    let (g, e3) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    ks.kde_grid2d(a, x[7usize..7usize + 2usize * n], n, x[1usize..5usize], m, gx, gy, g)
    ret g[usize(x[6usize]) * m + usize(x[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks2dkde.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
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
