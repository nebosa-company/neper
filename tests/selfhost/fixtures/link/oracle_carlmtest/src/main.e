// e.algo.stat.carlmtest against car, lmtest and sandwich. tests/oracle/carlmtest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R carlmtest`; the layout is at the top of scripts/r_oracle/groups/carlmtest.R.

use e.algo.stat.carlmtest as cl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let y = x[2usize..2usize + n]
    let des = x[2usize + n..2usize + n + n * p]
    let (f, e) = cl.ols(a, des, y, n, p)
    if str.eq(c.name, "nw") {
        let (dv0, e0) = mem.alloc[f64](a, p)
        if e0 != ok { os.exit(8) }
        let lg = usize(x[2usize + n + n * p])
        if cl.newey_west_diag(a, des, n, p, &f, lg, x[3usize + n + n * p] > 0.5f64, dv0) != ok { os.exit(9) }
        var tt = 0.0f64
        var q = 0usize
        while q < p {
            tt += dv0[q] * f64(q + 1usize)
            q += 1usize
        }
        ret tt
    }
    if e != ok { os.exit(5) }
    let k = c.name
    if str.eq(k, "dw") { ret cl.durbin_watson(f.resid) }
    if str.eq(k, "bp") { ret cl.bp_studentized(a, des, n, p, f.resid) }
    if str.eq(k, "bpc") { ret cl.bp_test(a, des, n, p, f.resid, false) }
    if str.eq(k, "reset") { ret cl.reset_f(a, des, y, n, p) }
    if str.eq(k, "gq") || str.eq(k, "gqp") {
        let (gqs, d1, d2) = cl.goldfeld_quandt(a, des, y, n, p)
        if str.eq(k, "gq") { ret gqs }
        ret cl.p_f(gqs, d1, d2)
    }
    if str.eq(k, "bpp") { ret cl.p_chisq(cl.bp_studentized(a, des, n, p, f.resid), f64(p - 1usize)) }
    if str.eq(k, "resetp") { ret cl.p_f(cl.reset_f(a, des, y, n, p), 2.0f64, f64(n - p - 2usize)) }
    var s = 0.0f64
    if str.eq(k, "vif") {
        var j = 1usize
        while j < p {
            s += cl.vif(a, des, n, p, j) * f64(j)
            j += 1usize
        }
        ret s
    }
    var ty = 0usize
    if str.eq(k, "hc1") { ty = 1usize }
    if str.eq(k, "hc2") { ty = 2usize }
    if str.eq(k, "hc3") { ty = 3usize }
    if str.eq(k, "hc4") { ty = 4usize }
    let (dv, e2) = mem.alloc[f64](a, p)
    if e2 != ok { os.exit(6) }
    if cl.vcov_hc_diag(a, des, n, p, &f, ty, dv) != ok { os.exit(7) }
    var j = 0usize
    while j < p {
        s += dv[j] * f64(j + 1usize)
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/carlmtest.json")
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
