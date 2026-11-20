// e.algo.stat.gamlsslms (lms with the BCCG family) against gamlss. tests/oracle/gamlss_lms.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_lms`; the layout is at the top of scripts/r_oracle/groups/gamlss_lms.R.

use e.algo.stat.gamlsslms as lm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_lms.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var n = 0usize
    let scen = mem.mark(a)
    var res: lm.Lms = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if usize(x[0usize]) != 0usize {
            mem.reset(a, scen)
            n = usize(x[0usize])
            let (r, fe) = lm.lms_bccg(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n])
            if fe != ok { os.exit(6) }
            res = r
        }
        let kind = usize(x[1usize])
        let idx = usize(x[2usize])
        var got = 0.0f64
        if kind == 0usize { got = f64(res.which) }
        if kind == 1usize { got = res.aic0 }
        if kind == 2usize { got = res.aic1 }
        if kind == 3usize { got = res.fit.gdev }
        if kind == 4usize { got = res.fit.df }
        if kind == 5usize { got = f64(res.fit.iter) }
        if kind == 6usize { got = res.fit.par[idx] }
        if kind == 7usize { got = res.fit.par[n + idx] }
        if kind == 8usize { got = res.fit.par[2usize * n + idx] }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
