// e.algo.stat.fixestpkg against fixest feols. tests/oracle/fixest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fixest`; the layout is at the top of scripts/r_oracle/groups/fixest.R.

use e.algo.stat.fixestpkg as fx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let g1 = usize(z[2usize])
    let g2 = usize(z[3usize])
    let (f1, e1) = mem.alloc[usize](a, n)
    let (f2, e2) = mem.alloc[usize](a, n)
    let (out, e3) = mem.alloc[f64](a, 4usize * k)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < n {
        f1[i] = usize(z[4usize + n + n * k + i])
        f2[i] = 0usize
        if g2 > 0usize { f2[i] = usize(z[4usize + 2usize * n + n * k + i]) }
        i += 1usize
    }
    if fx.feols(a, z[4usize + n..4usize + n + n * k], z[4usize..4usize + n], n, k, f1, g1, f2, g2, out) != ok { ret nan }
    var lo = 0usize
    if str.eq(c.name, "iid") { lo = k }
    if str.eq(c.name, "het") { lo = 2usize * k }
    if str.eq(c.name, "cl") { lo = 3usize * k }
    var s = 0.0f64
    i = 0usize
    while i < k {
        s += out[lo + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fixest.json")
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
