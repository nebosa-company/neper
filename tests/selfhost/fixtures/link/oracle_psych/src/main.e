// e.algo.stat.psych against psych: alpha, KMO, cortest.bartlett, ICC, cohen.kappa, mardia.
// tests/oracle/psych.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R psych`; the layout is
// at the top of scripts/r_oracle/groups/psych.R.

use e.algo.stat.psych as ps
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "desc") {
        let dn = usize(x[0usize])
        ret ps.describe(a, x[1usize..1usize + dn], usize(x[1usize + dn]))
    }
    if str.eq(c.name, "kappa") {
        let k = usize(x[0usize])
        ret ps.kappa(x[1usize..1usize + k * k], k)
    }
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let xm = x[2usize..2usize + n * p]
    let q = usize(x[2usize + n * p])
    if str.eq(c.name, "alpha_raw") || str.eq(c.name, "alpha_std") {
        let (r, s) = ps.alpha(xm, n, p)
        if str.eq(c.name, "alpha_raw") { ret r }
        ret s
    }
    if str.eq(c.name, "mardia_b1") || str.eq(c.name, "mardia_b2") {
        let (b1, b2, me) = ps.mardia(a, xm, n, p)
        if me != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "mardia_b1") { ret b1 }
        ret b2
    }
    if str.starts_with(c.name, "icc") {
        let (o, oe) = mem.alloc[f64](a, 6usize)
        if oe != ok { ret 0.0f64 / 0.0f64 }
        ps.icc(xm, n, p, o)
        ret o[usize(c.name[3usize]) - 49usize]
    }
    let (r, re) = ps.corr(a, xm, n, p)
    if re != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "bart_chi") || str.eq(c.name, "bart_df") {
        let (chi, df) = ps.bartlett(a, r, p, f64(n))
        if str.eq(c.name, "bart_chi") { ret chi }
        ret df
    }
    let (msa, me) = mem.alloc[f64](a, p)
    if me != ok { ret 0.0f64 / 0.0f64 }
    let (all, ke) = ps.kmo(a, r, p, msa)
    if ke != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "kmo") { ret all }
    ret msa[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/psych.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
