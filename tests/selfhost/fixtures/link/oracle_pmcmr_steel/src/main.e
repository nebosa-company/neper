// e.algo.stat.pmcmr's Steel many-to-one rank test against PMCMRplus. tests/oracle/pmcmr_steel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_steel`; the layout is at the top of scripts/r_oracle/groups/pmcmr_steel.R.

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
    let jj = usize(z[3usize])
    let what = usize(z[4usize])
    let x = z[5usize..5usize + n * (k + 1usize)]
    let (grp, e0) = mem.alloc[usize](a, n * (k + 1usize))
    if e0 != ok { os.exit(4) }
    var t = 0usize
    while t < n * (k + 1usize) {
        grp[t] = t / n + 1usize
        t += 1usize
    }
    let (rs, crit, e) = pm.steel_stat(a, x, grp, n, k, jj, alt == 1usize)
    if e != ok { os.exit(5) }
    if what == 0usize { ret rs }
    ret crit
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_steel.json")
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
