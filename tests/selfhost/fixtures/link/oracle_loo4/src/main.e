// e.algo.stat.looextra (tis and sis) and e.algo.stat.loometrics against loo; layouts at the top of scripts/r_oracle/groups/loo4.R.
// tests/oracle/loo4.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R loo4`.

use e.algo.stat.looextra as lx
use e.algo.stat.loometrics as lm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    let s = usize(x[0usize])
    let nobs = usize(x[1usize])
    if str.starts_with(nm, "pm_") {
        let ll = x[2usize..2usize + s * nobs]
        let xs = x[2usize + s * nobs..2usize + 2usize * s * nobs]
        let y = x[2usize + 2usize * s * nobs..2usize + 2usize * s * nobs + nobs]
        let (est, se, e) = lm.predictive_metric(a, xs, ll, y, s, usize(x[2usize + 2usize * s * nobs + nobs]))
        if e != ok { os.exit(4) }
        if str.eq(nm, "pm_est") { ret est }
        ret se
    }
    var method = 0usize
    var reffv = 1.0f64
    var at = 2usize
    if str.starts_with(nm, "is_") {
        method = usize(x[2usize])
        reffv = x[3usize]
        at = 4usize
    }
    let ll = x[at..at + s * nobs]
    let (rf, e1) = mem.alloc[f64](a, nobs)
    let (t, e2) = mem.alloc[f64](a, nobs * 5usize)
    if e1 != ok || e2 != ok { os.exit(5) }
    var i = 0usize
    while i < nobs {
        rf[i] = reffv
        i += 1usize
    }
    if lx.loo_full_m(a, ll, s, nobs, rf, method, t) != ok { os.exit(6) }
    if str.starts_with(nm, "is_") {
        if str.eq(nm, "is_elpd") {
            let (m, se) = lx.estimate(t, nobs, 5usize, 0usize)
            ret m
        }
        if str.eq(nm, "is_se") {
            let (m, se) = lx.estimate(t, nobs, 5usize, 0usize)
            ret se
        }
        var tot = 0.0f64
        i = 0usize
        while i < nobs {
            if str.eq(nm, "is_mcse") { tot += t[i * 5usize + 1usize] }
            if str.eq(nm, "is_neff") { tot += t[i * 5usize + 4usize] }
            i += 1usize
        }
        ret tot
    }
    var out: [4]f64 = zero
    lm.pareto_k_table(t, nobs, s, out[0usize..4usize])
    if str.eq(nm, "pk_c1") { ret out[0usize] }
    if str.eq(nm, "pk_c2") { ret out[1usize] }
    if str.eq(nm, "pk_c3") { ret out[2usize] }
    if str.eq(nm, "pk_ne1") { ret out[3usize] }
    if str.eq(nm, "pk_ids") { ret out[1usize] + out[2usize] }
    ret lm.mcse_loo(t, nobs, s)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/loo4.json")
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
