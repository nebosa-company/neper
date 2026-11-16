// e.algo.stat.mixtools against mixtools. tests/oracle/mixtools.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixtools`; the layout is at the top of scripts/r_oracle/groups/mixtools.R.

use e.algo.stat.mixtools as mt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let k = usize(x[1usize])
    let data = x[2usize..2usize + n]
    let (lam, e1) = mem.alloc[f64](a, k)
    if e1 != ok { os.exit(5) }
    let (mu, e2) = mem.alloc[f64](a, k)
    if e2 != ok { os.exit(6) }
    let (sd, e3) = mem.alloc[f64](a, k)
    if e3 != ok { os.exit(7) }
    var j = 0usize
    while j < k {
        lam[j] = x[2usize + n + j]
        mu[j] = x[2usize + n + k + j]
        sd[j] = x[2usize + n + 2usize * k + j]
        j += 1usize
    }
    let (f, e4) = mt.normal_mix_em(a, data, lam, mu, sd, 1.0e-8f64, 1000usize)
    if e4 != ok { os.exit(8) }
    let kind = c.name
    if str.eq(kind, "ll") { ret f.loglik }
    if str.eq(kind, "iter") { ret f64(f.iter) }
    var s = 0.0f64
    j = 0usize
    while j < k {
        if str.eq(kind, "lambda") { s += lam[j] * f64(j + 1usize) }
        if str.eq(kind, "mu") { s += mu[j] * f64(j + 1usize) }
        if str.eq(kind, "sd") { s += sd[j] * f64(j + 1usize) }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixtools.json")
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
