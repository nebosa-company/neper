// e.algo.stat.ghypdata against the parameter data sets of GeneralizedHyperbolic. tests/oracle/ghypdata.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghypdata`; the layout is at the top of scripts/r_oracle/groups/ghypdata.R.

use e.algo.stat.ghypdata as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let fam = usize(x[0usize])
    let set = usize(x[1usize])
    if str.eq(c.name, "psetrows") {
        if fam == 3usize {
            if set == 0usize { ret 1100.0f64 }
            ret 125.0f64
        }
        ret f64(gd.param_rows(fam, set))
    }
    var o: [5]f64 = zero
    if fam == 3usize {
        gd.gig_param_row(set == 1usize, usize(x[2usize]), o[0usize..5usize])
    } else {
        gd.ghyp_param_row(fam, set, usize(x[2usize]), o[0usize..5usize])
    }
    ret o[usize(x[3usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghypdata.json")
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
