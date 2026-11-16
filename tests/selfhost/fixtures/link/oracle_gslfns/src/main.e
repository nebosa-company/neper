// e.algo.stat.gslfns against gsl. tests/oracle/gslfns.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslfns`; the layout is at the top of scripts/r_oracle/groups/gslfns.R.

use e.algo.stat.gslfns as gs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "knu") { ret gs.bessel_knu(x[0usize], x[1usize]) }
    if str.eq(k, "inu") { ret gs.bessel_inu(x[0usize], x[1usize]) }
    if str.eq(k, "jn") { ret gs.bessel_jn(i64(x[0usize]), x[1usize]) }
    if str.eq(k, "w0") { ret gs.lambert_w(x[0usize], 0i64) }
    if str.eq(k, "wm1") { ret gs.lambert_w(x[0usize], 0i64 - 1i64) }
    if str.eq(k, "e1") { ret gs.expint_e1(x[0usize]) }
    if str.eq(k, "ei") { ret gs.expint_ei(x[0usize]) }
    if str.eq(k, "dawson") { ret gs.dawson(x[0usize]) }
    if str.eq(k, "clausen") { ret gs.clausen(x[0usize]) }
    if str.eq(k, "hzeta") { ret gs.hzeta(x[0usize], x[1usize]) }
    ret gs.hzeta(x[0usize], 1.0f64)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslfns.json")
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
