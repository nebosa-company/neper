// e.algo.stat.uwot against uwot::umap. tests/oracle/uwot.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R uwot`; the layout is at the top of scripts/r_oracle/groups/uwot.R.

use e.algo.rand.r as rng
use e.algo.stat.uwot as uw
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pick(y: []const f64, sel: f64) -> f64 {
    if sel >= 0.0f64 { ret y[usize(sel)] }
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        if sel == 0.0f64 - 1.0f64 { s += y[i] * y[i] } else { s += y[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let d = usize(x[2usize])
    let nd = usize(x[4usize])
    let (y, e) = mem.alloc[f64](a, n * nd)
    if e != ok { os.exit(5) }
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    var pa = x[7usize]
    var pb = x[8usize]
    if pa < 0.0f64 {
        var ab: [2]f64 = zero
        if uw.find_ab(a, 0.0f64 - pa, pb, ab[0usize..2usize]) != ok { os.exit(7) }
        pa = ab[0usize]
        pb = ab[1usize]
    }
    if uw.umap_fit(a, x[14usize..14usize + n * d], n, d, usize(x[3usize]), nd, usize(x[5usize]), x[6usize], pa, pb,x[9usize], x[10usize], x[11usize], x[12usize], usize(x[13usize]), &g, y) != ok { os.exit(6) }
    ret pick(y, x[14usize + n * d])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/uwot.json")
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
            if failures <= 6usize {
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
