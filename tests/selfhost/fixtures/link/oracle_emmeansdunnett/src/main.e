// e.algo.stat.emmeans' Dunnett adjusted p against emmeans (adjust = "dunnett"). tests/oracle/emmeansdunnett.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R emmeansdunnett`; the layout is at the top of scripts/r_oracle/groups/emmeansdunnett.R.

use e.algo.stat.emmeans as em
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let k = usize(z[0usize])
    if c.name.len == 8usize { ret em.p_dunnettx(z[3usize], f64(k - 1usize), z[1usize]) }
    ret em.dunnett_p(z[3usize], z[2usize], z[4usize..4usize + k - 1usize], z[1usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/emmeansdunnett.json")
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
