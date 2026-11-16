// e.algo.stat.cshell against e1071::cshell with given centres. tests/oracle/cshell.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cshell`; the layout is at the top of scripts/r_oracle/groups/cshell.R.

use e.algo.rand.r as rng
use e.algo.stat.cshell as cs
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let d = usize(z[2usize])
    let nc = usize(z[3usize])
    let dist = i64(z[4usize])
    let itmax = i64(z[5usize])
    let m = z[6usize]
    let x = z[7usize..7usize + n * d]
    let q = usize(z[7usize + n * d + nc * d])
    let (cen, e1) = mem.alloc[f64](a, nc * d)
    let (rad, e2) = mem.alloc[f64](a, nc)
    let (u, e3) = mem.alloc[f64](a, n * nc)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < nc * d {
        cen[i] = z[7usize + n * d + i]
        i += 1usize
    }
    i = 0usize
    while i < nc { rad[i] = 0.2f64
        i += 1usize }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (fit, fe) = cs.cshell(a, &g, x, n, d, nc, cen, rad, m, dist, itmax, u)
    if fe != ok { ret nan }
    var s = 0.0f64
    if q == 0usize {
        i = 0usize
        while i < nc * d { s += f64(i + 1usize) * cen[i]
            i += 1usize }
        ret s
    }
    if q == 1usize {
        i = 0usize
        while i < nc { s += f64(i + 1usize) * rad[i]
            i += 1usize }
        ret s
    }
    if q == 2usize { ret f64(fit.iter) }
    if q == 3usize { ret fit.ermin }
    i = 0usize
    while i < n * nc { s += f64(i + 1usize) * u[i]
        i += 1usize }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cshell.json")
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
