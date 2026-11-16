// e.ml.mds against base R cmdscale. tests/oracle/cmdscale.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cmdscale`; the layout is at the top of scripts/r_oracle/groups/cmdscale.R.

use e.io
use e.math
use e.mem
use e.ml.mds as mds
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let (coords, e1) = mem.alloc[f64](a, n * k)
    let (eig, e2) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok { ret nan }
    if mds.cmdscale(a, z[2usize..2usize + n * n], n, k, coords, eig) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "eig") {
        while i < k {
            s += eig[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    while i < n * k {
        s += math.abs[f64](coords[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    // the Johnson-Lindenstrauss bound against its closed form
    if mds.jl_dimension(1000usize, 0.1f64) != 5921usize { os.exit(4) }
    let (golden, load_error) = oracle.load(a, "tests/oracle/cmdscale.json")
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
