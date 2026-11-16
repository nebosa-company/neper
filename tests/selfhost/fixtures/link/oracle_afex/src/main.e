// e.algo.stat.afexpkg against afex aov_ez. tests/oracle/afex.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R afex`; the layout is at the top of scripts/r_oracle/groups/afex.R.

use e.algo.stat.afexpkg as af
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn slot(name: str) -> usize {
    if str.eq(name, "F_A") { ret 0usize }
    if str.eq(name, "p_A") { ret 1usize }
    if str.eq(name, "F_B") { ret 2usize }
    if str.eq(name, "p_B") { ret 3usize }
    if str.eq(name, "F_AB") { ret 4usize }
    if str.eq(name, "p_AB") { ret 5usize }
    if str.eq(name, "gg") { ret 6usize }
    if str.eq(name, "hf") { ret 7usize }
    if str.eq(name, "ggp_B") { ret 8usize }
    if str.eq(name, "hfp_B") { ret 9usize }
    if str.eq(name, "ggp_AB") { ret 10usize }
    if str.eq(name, "hfp_AB") { ret 11usize }
    if str.eq(name, "W") { ret 12usize }
    if str.eq(name, "pW") { ret 13usize }
    if str.eq(name, "ges_A") { ret 14usize }
    if str.eq(name, "ges_B") { ret 15usize }
    ret 16usize
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let g = usize(z[1usize])
    let k = usize(z[2usize])
    let (out, e1) = mem.alloc[f64](a, 17usize)
    if e1 != ok { ret nan }
    if af.rm_anova(a, z[3usize..3usize + n * (k + 1usize)], n, g, k, out) != ok { ret nan }
    ret out[slot(c.name)]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/afex.json")
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
