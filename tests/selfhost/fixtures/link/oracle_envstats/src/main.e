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
    if str.eq(c.name, "cihw") { ret es.ci_norm_hw(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize] > 0.5f64) }
    if str.eq(c.name, "cin") { ret es.ci_norm_n(z[0usize], z[1usize], z[2usize], z[3usize] > 0.5f64, 5000.0f64) }
    if str.eq(c.name, "ttp") { ret es.tt_power(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize] > 0.5f64, usize(z[5usize]), z[6usize] > 0.5f64) }
    if str.eq(c.name, "ttn") { ret es.tt_n(z[0usize], z[1usize], z[2usize], z[3usize] > 0.5f64, usize(z[4usize]), z[5usize] > 0.5f64, 5000.0f64) }
    if str.eq(c.name, "ptp") { ret es.prop_power(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize], z[5usize] > 0.5f64, usize(z[6usize]), z[7usize] > 0.5f64, z[8usize] > 0.5f64) }
    if str.eq(c.name, "ptn") { ret es.prop_n(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize] > 0.5f64, usize(z[5usize]), z[6usize], z[7usize] > 0.5f64, usize(z[8usize])) }
    if str.eq(c.name, "cibh") { ret es.ci_binom_hw(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize], z[5usize] > 0.5f64, usize(z[6usize]), z[7usize] > 0.5f64) }
    if str.eq(c.name, "cibn") { ret es.ci_binom_n(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize] > 0.5f64, usize(z[5usize]), z[6usize], z[7usize] > 0.5f64, 2.0f64, 3000.0f64, 5.0e-4f64, 5.0e-4f64) }
    if str.eq(c.name, "ptx") { ret es.prop_n_exact(z[0usize], z[1usize], z[2usize], z[3usize], usize(z[4usize]), 2.0f64, 3000.0f64, 0.1f64 * z[2usize]) }
    if str.eq(c.name, "pin") { ret es.pi_norm_n(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize], 5000.0f64) }
    if str.eq(c.name, "tin") { ret es.tol_int_norm_n(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize] > 0.5f64, 5000.0f64) }
    if str.eq(c.name, "gof") {
        let gn = usize(z[0usize])
        let (go, ge) = mem.alloc[f64](a, 3usize)
        if ge != ok { ret nan }
        let gr = es.gof_test(a, z[1usize..1usize + gn], usize(z[1usize + gn]), z[2usize + gn] > 0.5f64, usize(z[3usize + gn]), go)
        if gr != ok { ret nan }
        ret go[usize(z[4usize + gn])]
    }
    if str.eq(c.name, "kst") {
        let sn = usize(z[0usize])
        let (so, se) = mem.alloc[f64](a, 13usize)
        if se != ok { ret nan }
        let sr = es.kendall_seasonal(a, z[1usize..1usize + sn], z[1usize + sn..1usize + 2usize * sn], z[1usize + 2usize * sn..1usize + 3usize * sn], usize(z[1usize + 3usize * sn]), z[2usize + 3usize * sn] > 0.5f64, z[3usize + 3usize * sn], so)
        if sr != ok { ret nan }
        ret so[usize(z[4usize + 3usize * sn])]
    }
    if str.eq(c.name, "kt") {
        let kn = usize(z[0usize])
        let (ko, ke) = mem.alloc[f64](a, 10usize)
        if ke != ok { ret nan }
        let kr = es.kendall_trend(a, z[1usize..1usize + kn], z[1usize + kn..1usize + 2usize * kn], usize(z[1usize + 2usize * kn]), z[2usize + 2usize * kn] > 0.5f64, z[3usize + 2usize * kn], ko)
        if kr != ok { ret nan }
        ret ko[usize(z[4usize + 2usize * kn])]
    }
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
