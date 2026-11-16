// e.algo.stat.envstats against EnvStats: rosnerTest, tolIntNormK and predIntNormK. tests/oracle/envstats.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R envstats`; the layout is at the top of
// scripts/r_oracle/groups/envstats.R.

use e.algo.stat.envstats as es
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "tk") { ret es.tol_k(z[0usize], z[1usize], z[2usize], i64(z[3usize])) }
    if str.eq(c.name, "pk") { ret es.pred_k(z[0usize], z[1usize], z[2usize], z[3usize] > 0.5f64, z[4usize]) }
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let (r, e) = es.rosner_test(a, z[3usize..3usize + n], k, z[2usize])
    if e != ok { ret nan }
    let f = usize(z[3usize + n])
    let i = usize(z[4usize + n])
    if f == 0usize { ret f64(r.nout) }
    if f == 1usize { ret r.mean[i] }
    if f == 2usize { ret r.sd[i] }
    if f == 3usize { ret r.value[i] }
    if f == 4usize { ret r.obs[i] }
    if f == 5usize { ret r.r[i] }
    if f == 6usize { ret r.lambda[i] }
    if r.outlier[i] { ret 1.0f64 }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/envstats.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
