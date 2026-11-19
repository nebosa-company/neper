// e.algo.stat.envstats's egamma against EnvStats. tests/oracle/envstats_wl.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R envstats_wl`; the layout is at the top of scripts/r_oracle/groups/envstats_wl.R.

use e.algo.stat.envstats as es
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var o: [2]f64 = zero
    let fam = usize(x[0usize])
    if fam == 0usize {
        es.e_weibull(x[2usize..x.len], o[0usize..2usize])
    } else {
        es.e_lnorm(x[2usize..x.len], fam - 1usize, o[0usize..2usize])
    }
    ret o[usize(x[1usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/envstats_wl.json")
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
