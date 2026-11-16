// e.algo.stat.pbivnorm against pbivnorm: the bivariate normal distribution function.
// tests/oracle/pbivnorm.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pbivnorm`.

use e.algo.stat.pbivnorm as pb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn limit(v: f64) -> f64 {
    if v > 1.0e308f64 { ret 1.7976931348623157e308f64 }
    if v < 0.0f64 - 1.0e308f64 { ret 0.0f64 - 1.7976931348623157e308f64 }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pbivnorm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = pb.pbivnorm(limit(c.args[0usize]), limit(c.args[1usize]), c.args[2usize])
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
