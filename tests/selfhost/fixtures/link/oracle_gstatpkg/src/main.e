// e.algo.stat.gstatpkg against gstat. tests/oracle/gstatpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gstatpkg`; the layout is at the top of scripts/r_oracle/groups/gstatpkg.R.

use e.algo.stat.gstatpkg as gs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "vgm") { ret gs.vgm_gamma(usize(x[0usize]), x[1usize], x[2usize], x[3usize], x[4usize]) }
    let n = usize(x[0usize])
    if str.eq(k, "ev") {
        let xyz = x[5usize..5usize + 3usize * n]
        let (xy, e1) = mem.alloc[f64](a, 2usize * n)
        if e1 != ok { os.exit(5) }
        let (z, e2) = mem.alloc[f64](a, n)
        if e2 != ok { os.exit(6) }
        var i = 0usize
        while i < n {
            xy[2usize * i] = xyz[3usize * i]
            xy[2usize * i + 1usize] = xyz[3usize * i + 1usize]
            z[i] = xyz[3usize * i + 2usize]
            i += 1usize
        }
        let (np, d, g) = gs.empirical_variogram(xy, z, n, x[1usize], x[2usize], usize(x[3usize]))
        let pt = usize(x[4usize])
        if pt == 0usize { ret np }
        if pt == 1usize { ret d }
        ret g
    }
    let xyz = x[8usize..8usize + 3usize * n]
    let (xy, e1) = mem.alloc[f64](a, 2usize * n)
    if e1 != ok { os.exit(7) }
    let (z, e2) = mem.alloc[f64](a, n)
    if e2 != ok { os.exit(8) }
    var i = 0usize
    while i < n {
        xy[2usize * i] = xyz[3usize * i]
        xy[2usize * i + 1usize] = xyz[3usize * i + 1usize]
        z[i] = xyz[3usize * i + 2usize]
        i += 1usize
    }
    ret gs.ordinary_krige(a, xy, z, n, usize(x[1usize]), x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], usize(x[7usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gstatpkg.json")
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
