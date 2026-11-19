// e.algo.stat.pmcmr's van der Waerden all-pairs test against PMCMRplus. tests/oracle/pmcmr_vdw.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_vdw`; the layout is at the top of scripts/r_oracle/groups/pmcmr_vdw.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let kind = usize(z[2usize])
    let i = usize(z[3usize])
    let j = usize(z[4usize])
    let x = z[5usize..5usize + n]
    let (grp, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(4) }
    var t = 0usize
    while t < n {
        grp[t] = usize(z[5usize + n + t]) - 1usize
        t += 1usize
    }
    let (tv, p, pt, e) = pm.vdw_pair(a, n, k, x, grp, i, j, false, false)
    if e != ok { os.exit(5) }
    if kind == 0usize { ret tv }
    if kind == 1usize { ret p }
    ret pt
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_vdw.json")
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
