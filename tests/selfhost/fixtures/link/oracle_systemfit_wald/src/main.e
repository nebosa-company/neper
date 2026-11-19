// e.algo.stat.systemfitpkg's wald_test against car::linearHypothesis on systemfit fits. tests/oracle/systemfit_wald.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R systemfit_wald`; the layout is at the top of scripts/r_oracle/groups/systemfit_wald.R.

use e.algo.stat.systemfitpkg as sf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kt = usize(z[0usize])
    let nr = usize(z[1usize])
    var out: [3]f64 = zero
    let bo = 3usize
    let vo = bo + kt
    let ro = vo + kt * kt
    let qo = ro + nr * kt
    if sf.wald_test(a, z[bo..vo], z[vo..ro], z[ro..qo], z[qo..qo + nr], nr, kt, z[2usize], out[0usize..3usize]) != ok { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[qo + nr])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/systemfit_wald.json")
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
