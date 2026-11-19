// e.algo.stat.psych's maximum likelihood factor uniquenesses against psych::fa(fm = "ml"). tests/oracle/psychfa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R psychfa`; the layout is at the top of scripts/r_oracle/groups/psychfa.R.

use e.algo.stat.psych as ps
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let p = usize(z[0usize])
    let q = usize(z[1usize])
    if c.name.len == 7usize {
        let (o3, e3) = mem.alloc[f64](a, p + p * q + q * q)
        if e3 != ok { ret 0.0f64 / 0.0f64 }
        if !ps.fa_ml_promax(a, z[2usize..2usize + p * p], p, q, o3) { ret 0.0f64 / 0.0f64 }
        ret o3[usize(z[2usize + p * p])]
    }
    if c.name.len == 5usize {
        let (o2, e2) = mem.alloc[f64](a, p + p * q + q * q)
        if e2 != ok { ret 0.0f64 / 0.0f64 }
        if !ps.fa_ml_varimax(a, z[2usize..2usize + p * p], p, q, o2) { ret 0.0f64 / 0.0f64 }
        ret o2[usize(z[2usize + p * p])]
    }
    let (out, e1) = mem.alloc[f64](a, p + 1usize + p * q)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if !ps.fa_ml(a, z[2usize..2usize + p * p], p, q, out) { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[2usize + p * p])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/psychfa.json")
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
