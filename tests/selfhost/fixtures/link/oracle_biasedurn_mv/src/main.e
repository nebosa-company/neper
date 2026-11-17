// e.algo.stat.biasedurn_mv against BiasedUrn: multivariate moments, odds and ball-count estimators.
// tests/oracle/biasedurn_mv.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R biasedurn_mv`; the
// layout of each case is at the top of scripts/r_oracle/groups/biasedurn_mv.R.

use e.algo.stat.biasedurn_mv as mv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "mom") {
        let cc = usize(z[5usize])
        ret mv.mv_moment(a, usize(z[0usize]), z[1usize], z[6usize..6usize + cc], z[6usize + cc..6usize + 2usize * cc], z[4usize], usize(z[2usize]), usize(z[3usize]))
    }
    if str.eq(c.name, "om") {
        let cc = usize(z[3usize])
        ret mv.odds_m(usize(z[0usize]), z[4usize + cc..4usize + 2usize * cc], z[4usize..4usize + cc], z[2usize], usize(z[1usize]))
    }
    if str.eq(c.name, "num") {
        let cc = usize(z[4usize])
        ret mv.num_m(usize(z[0usize]), z[5usize..5usize + cc], z[5usize + cc..5usize + 2usize * cc], z[2usize], z[3usize], usize(z[1usize]), a)
    }
    // "nu": (kind, which, mu, n, N, odds)
    var m1 = 0.0f64
    if z[0usize] == 0.0f64 { m1 = mv.num_fisher(z[2usize], z[3usize], z[4usize], z[5usize]) } else { m1 = mv.num_wall(z[2usize], z[3usize], z[4usize], z[5usize]) }
    if z[1usize] == 0.0f64 { ret m1 }
    ret z[4usize] - m1
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/biasedurn_mv.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
