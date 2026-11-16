// e.algo.stat.mvtnorm.pmvnorm2 against mvtnorm::pmvnorm(algorithm = TVPACK()) in two dimensions.
// tests/oracle/pmvnorm.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmvnorm`; the layout
// is at the top of scripts/r_oracle/groups/pmvnorm.R (an infinite bound is 1e300).

use e.algo.stat.mvtnorm as mv
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn bound(v: f64) -> f64 {
    if v >= 1.0e300f64 { ret 1.0f64 / 0.0f64 }
    if v <= 0.0f64 - 1.0e300f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
    ret v
}

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    ret mv.pmvnorm2(bound(z[0usize]), bound(z[1usize]), bound(z[2usize]), bound(z[3usize]), z[4usize], z[5usize], z[6usize], z[7usize], z[8usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmvnorm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
