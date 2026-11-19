// e.algo.stat.pmcmr's Friedman all-pairs tests against PMCMRplus. tests/oracle/pmcmr_frd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_frd`; the layout is at the top of scripts/r_oracle/groups/pmcmr_frd.R.

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
    let y = z[5usize..5usize + n * k]
    var m = 0usize
    if kind == 2usize || kind == 3usize { m = 1usize }
    if kind >= 4usize { m = 2usize }
    let (st, p, e) = pm.frd_pair(a, n, k, y, m, i, j)
    if e != ok { os.exit(4) }
    if kind % 2usize == 0usize { ret st }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_frd.json")
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
