// e.algo.stat.systemfitpkg against systemfit SUR. tests/oracle/systemfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R systemfit`; the layout is at the top of scripts/r_oracle/groups/systemfit.R.

use e.algo.stat.systemfitpkg as sf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let passes = usize(z[2usize])
    let dfc = z[3usize] > 0.5f64
    let (ks, e1) = mem.alloc[usize](a, m)
    if e1 != ok { ret nan }
    var kt = 0usize
    var i = 0usize
    while i < m {
        ks[i] = usize(z[4usize + i])
        kt += ks[i]
        i += 1usize
    }
    let (coef, e2) = mem.alloc[f64](a, kt)
    let (se, e3) = mem.alloc[f64](a, kt)
    let (sig, e4) = mem.alloc[f64](a, m * m)
    if e2 != ok || e3 != ok || e4 != ok { ret nan }
    let y = z[4usize + m..4usize + m + m * n]
    let xs = z[4usize + m + m * n..4usize + m + m * n + n * kt]
    if sf.sur(a, xs, ks, y, n, m, dfc, passes, coef, se, sig) != ok { ret nan }
    var s = 0.0f64
    var cnt = kt
    var src = coef
    if str.eq(c.name, "se") { src = se }
    if str.eq(c.name, "sig") {
        src = sig
        cnt = m * m
    }
    i = 0usize
    while i < cnt {
        s += src[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/systemfit.json")
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
