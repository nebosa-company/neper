// e.algo.stat.pmcmr's dunnettTest against PMCMRplus. tests/oracle/pmcmr_dunnett.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_dunnett`; the layout is at the top of scripts/r_oracle/groups/pmcmr_dunnett.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.math.dist as dist
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let kind = usize(z[2usize])
    let jj = usize(z[3usize])
    let x = z[4usize..4usize + n]
    let (grp, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(4) }
    var t = 0usize
    while t < n {
        grp[t] = usize(z[4usize + n + t])
        t += 1usize
    }
    if kind == 2usize { ret pm.dunnett_one_sided(x, grp, k, jj, 0usize) }
    if kind == 3usize { ret pm.dunnett_one_sided(x, grp, k, jj, 1usize) }
    let (tv, p) = pm.dunnett_many(x, grp, k, jj)
    if kind == 0usize { ret tv }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_dunnett.json")
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
