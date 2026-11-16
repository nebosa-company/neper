// e.algo.stat.bayesfactor against BayesFactor. tests/oracle/bayesfactor.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayesfactor`; the layout is at the top of scripts/r_oracle/groups/bayesfactor.R.

use e.algo.stat.bayesfactor as bf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayesfactor.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let (got, e) = bf.ttest_log_bf(a, x[0usize], x[1usize], x[2usize], x[3usize])
        if e != ok { os.exit(5) }
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
