// e.algo.stat.pmcmr's Steel k-sample test against PMCMRplus. tests/oracle/pmcmr_steelk.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_steelk`; the layout is at the top of scripts/r_oracle/groups/pmcmr_steelk.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let alt = usize(z[2usize])
    let what = usize(z[3usize])
    let x = z[4usize..4usize + n]
    let (grp, e0) = mem.alloc[usize](a, n)
    let (o, e1) = mem.alloc[f64](a, 2usize)
    if e0 != ok || e1 != ok { os.exit(4) }
    var t = 0usize
    while t < n {
        grp[t] = usize(z[4usize + n + t])
        t += 1usize
    }
    if pm.steels_k(a, x, grp, k, alt, o) != ok { os.exit(5) }
    ret o[what]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_steelk.json")
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
