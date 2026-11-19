// e.algo.stat.mass's step_aic_lm against MASS stepAIC. tests/oracle/mass_step.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_step`; the layout is at the top of scripts/r_oracle/groups/mass_step.R.

use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (mask, e0) = mem.alloc[f64](a, p)
    if e0 != ok { ret nan }
    var j = 0usize
    while j < p {
        mask[j] = z[3usize]
        j += 1usize
    }
    let (aic, e) = ms.step_aic_lm(a, z[4usize..4usize + n * p], n, p, z[4usize + n * p..4usize + n * p + n], usize(z[2usize]), mask)
    if e != ok { ret nan }
    if usize(z[4usize + n * p + n]) == 0usize { ret aic }
    var s = 0.0f64
    var w = 1.0f64
    j = 0usize
    while j < p {
        if mask[j] != 0.0f64 { s += w }
        w = w * 2.0f64
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_step.json")
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
