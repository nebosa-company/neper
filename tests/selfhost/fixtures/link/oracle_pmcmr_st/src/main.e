// e.algo.stat.pmcmr's siegelTukeyTest against PMCMRplus. tests/oracle/pmcmr_st.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_st`; the layout is at the top of scripts/r_oracle/groups/pmcmr_st.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.math.dist as dist
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n1 = usize(z[0usize])
    let n2 = usize(z[1usize])
    let (o, e0) = mem.alloc[f64](a, 2usize)
    if e0 != ok { os.exit(4) }
    if pm.siegel_tukey(a, z[3usize..3usize + n1 + n2], n1, o) != ok { os.exit(5) }
    ret o[usize(z[2usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_st.json")
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
