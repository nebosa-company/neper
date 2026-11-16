// e.algo.stat.kendall against Kendall::Kendall and MannKendall. tests/oracle/kendall.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kendall`; the layout is at the top of
// scripts/r_oracle/groups/kendall.R.

use e.algo.stat.kendall as kd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if c.name.len == 2usize {
        let fr = usize(z[0usize])
        let m = usize(z[1usize])
        let rs = kd.seasonal(a, z[2usize..2usize + m], fr)
        let qs = usize(z[2usize + m])
        if qs == 0usize { ret rs.tau }
        if qs == 1usize { ret rs.sl }
        if qs == 2usize { ret rs.s }
        if qs == 3usize { ret rs.d }
        ret rs.vars
    }
    let n = usize(z[1usize])
    let x = z[2usize..2usize + n]
    let y = z[2usize + n..2usize + 2usize * n]
    let q = usize(z[2usize + 2usize * n])
    let r = kd.kendall(a, x, y)
    if q == 0usize { ret r.tau }
    if q == 1usize { ret r.sl }
    if q == 2usize { ret r.s }
    if q == 3usize { ret r.d }
    ret r.vars
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kendall.json")
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
