// e.algo.stat.carets against caret: confusionMatrix of a two-class table and postResample. tests/oracle/carets.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R carets`; the layout is at the top of
// scripts/r_oracle/groups/carets.R.

use e.algo.stat.carets as ct
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    let id = usize(z[0usize])
    if str.eq(c.name, "pr") {
        let n = usize(z[1usize])
        let (rmse, r2, mae) = ct.post_resample(z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n])
        if id == 0usize { ret rmse }
        if id == 1usize { ret r2 }
        ret mae
    }
    let m = ct.confusion2(z[1usize], z[2usize], z[3usize], z[4usize], 0.95f64)
    if id == 0usize { ret m.accuracy }
    if id == 1usize { ret m.kappa }
    if id == 2usize { ret m.lower }
    if id == 3usize { ret m.upper }
    if id == 4usize { ret m.nir }
    if id == 5usize { ret m.pvalue }
    if id == 6usize { ret m.mcnemar }
    if id == 7usize { ret m.sens }
    if id == 8usize { ret m.spec }
    if id == 9usize { ret m.ppv }
    if id == 10usize { ret m.npv }
    if id == 11usize { ret m.f1 }
    if id == 12usize { ret m.prevalence }
    if id == 13usize { ret m.detection_rate }
    if id == 14usize { ret m.detection_prevalence }
    ret m.balanced
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/carets.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
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
