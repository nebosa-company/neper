// e.algo.stat.envstats's enorm, eexp and epois with confidence intervals against EnvStats. tests/oracle/envstats_est.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R envstats_est`; the layout is at the top of scripts/r_oracle/groups/envstats_est.R.

use e.algo.stat.envstats as es
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let fam = usize(x[0usize])
    let t = usize(x[1usize])
    let cl = x[2usize]
    let what = usize(x[3usize])
    let d = x[4usize..x.len]
    var o: [4]f64 = zero
    if fam < 2usize {
        es.e_norm(d, cl, fam, t, o[0usize..4usize])
        ret o[what]
    }
    if fam == 2usize {
        es.e_exp(d, cl, t, o[0usize..3usize])
        if what == 0usize { ret o[0usize] }
        ret o[what - 1usize]
    }
    es.e_pois(d, cl, t, o[0usize..3usize])
    if what == 0usize { ret o[0usize] }
    ret o[what - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/envstats_est.json")
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
