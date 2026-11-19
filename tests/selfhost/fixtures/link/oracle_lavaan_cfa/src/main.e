// e.algo.stat.lavaanpkg's one-factor confirmatory factor analysis against lavaan::cfa. tests/oracle/lavaan_cfa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lavaan_cfa`; the layout is at the top of scripts/r_oracle/groups/lavaan_cfa.R.

use e.algo.stat.lavaanpkg as lv
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (out, e1) = mem.alloc[f64](a, 2usize * p + 4usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if !lv.cfa_one_factor(a, z[2usize..2usize + p * p], n, p, out) { ret 0.0f64 / 0.0f64 }
    if c.name.len == 6usize {
        // the standard errors, in the order loadings 2 .. p, residual variances, factor variance
        let (se, se1) = mem.alloc[f64](a, 2usize * p)
        if se1 != ok { ret 0.0f64 / 0.0f64 }
        if !lv.cfa_se(a, out, n, p, se) { ret 0.0f64 / 0.0f64 }
        ret se[usize(z[2usize + p * p])]
    }
    ret out[usize(z[2usize + p * p])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lavaan_cfa.json")
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
