// e.algo.stat.sampling.fastflightcube against sampling::fastflightcube. tests/oracle/sampling_cube.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_cube`; the layout is at the top of scripts/r_oracle/groups/sampling_cube.R.

use e.algo.rand.r as rr
use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (pk, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        pk[i] = z[4usize + i]
        i += 1usize
    }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[3usize]))
    let fe = sp.fastflightcube(a, &g, z[4usize + n..4usize + n + n * p], pk, n, p, usize(z[2usize]))
    if fe != ok { os.exit(5) }
    var s = 0.0f64
    var fr = 0.0f64
    i = 0usize
    while i < n {
        s += pk[i] * f64(i + 1usize)
        if pk[i] > 1.0e-11f64 && pk[i] < 1.0f64 - 1.0e-11f64 { fr += 1.0f64 }
        i += 1usize
    }
    if str.eq(c.name, "cs") { ret s }
    ret fr
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_cube.json")
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
