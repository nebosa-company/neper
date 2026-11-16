// e.algo.stat.locpoly against KernSmooth::locpoly. tests/oracle/locpoly.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R locpoly`; the layout is at the top of
// scripts/r_oracle/groups/locpoly.R.

use e.algo.stat.locpoly as lp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let drv = usize(z[1usize])
    let degree = usize(z[2usize])
    let h = z[3usize]
    let m = usize(z[4usize])
    let x = z[5usize..5usize + n]
    let y = z[5usize + n..5usize + 2usize * n]
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let (out, e) = mem.alloc[f64](a, m)
    if e != ok { ret nan }
    if lp.locpoly(a, x, y, drv, degree, h, m, lo, hi, out) != ok { ret nan }
    if str.eq(c.name, "first") { ret out[0usize] }
    if str.eq(c.name, "mid") { ret out[(m + 1usize) / 2usize - 1usize] }
    if str.eq(c.name, "last") { ret out[m - 1usize] }
    var s = 0.0f64
    i = 0usize
    while i < m {
        if str.eq(c.name, "sum") { s += out[i] } else { s += f64(i + 1usize) * out[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/locpoly.json")
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
