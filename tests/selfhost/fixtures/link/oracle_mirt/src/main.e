// e.algo.stat.mirtpkg's two-parameter logistic model against mirt::mirt. tests/oracle/mirt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mirt`; the layout is at the top of scripts/r_oracle/groups/mirt.R.

use e.algo.stat.mirtpkg as mi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let j = usize(z[1usize])
    if c.name.len == 5usize {
        let (o2, e2) = mem.alloc[f64](a, j + 2usize)
        if e2 != ok { ret 0.0f64 / 0.0f64 }
        if !mi.rasch(a, z[2usize..2usize + n * j], n, j, o2) { ret 0.0f64 / 0.0f64 }
        ret o2[usize(z[2usize + n * j])]
    }
    let (out, e1) = mem.alloc[f64](a, 2usize * j + 1usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if !mi.tpl(a, z[2usize..2usize + n * j], n, j, out) { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[2usize + n * j])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mirt.json")
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
