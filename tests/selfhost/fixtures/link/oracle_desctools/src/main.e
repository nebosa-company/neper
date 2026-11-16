// e.algo.stat.desctools against DescTools. tests/oracle/desctools.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desctools`; the layout is at the top of scripts/r_oracle/groups/desctools.R.

use e.algo.stat.desctools as dt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let v = x[1usize..1usize + n]
    let k = c.name
    if str.eq(k, "skew1") { ret dt.skew(v, 1usize) }
    if str.eq(k, "skew2") { ret dt.skew(v, 2usize) }
    if str.eq(k, "skew3") { ret dt.skew(v, 3usize) }
    if str.eq(k, "kurt1") { ret dt.kurt(v, 1usize) }
    if str.eq(k, "kurt2") { ret dt.kurt(v, 2usize) }
    if str.eq(k, "kurt3") { ret dt.kurt(v, 3usize) }
    if str.eq(k, "gini") { ret dt.gini(a, v, true) }
    if str.eq(k, "ginib") { ret dt.gini(a, v, false) }
    if str.eq(k, "meanad") { ret dt.mean_ad(v) }
    if str.eq(k, "gmean") { ret dt.gmean(v) }
    if str.eq(k, "hmean") { ret dt.hmean(v) }
    if str.eq(k, "entropy") { ret dt.entropy(v) }
    ret dt.coef_var(v)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desctools.json")
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
