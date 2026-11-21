// the sm.regression reference and variability bands and the 2-d sm.density band against sm. tests/oracle/sm_band.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sm_band`; the layout is at the top of scripts/r_oracle/groups/sm_band.R.

use e.algo.stat.sm as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    let n = usize(x[0usize])
    if str.starts_with(k, "d2") {
        let xs = x[5usize..5usize + n]
        let ys = x[5usize + n..5usize + 2usize * n]
        let est = sm.density2(xs, ys, x[1usize], x[2usize], x[3usize], x[4usize])
        let (se, lo, up) = sm.density_band2(est, f64(n), x[1usize], x[2usize])
        if str.eq(k, "d2se") { ret se }
        if str.eq(k, "d2lo") { ret lo }
        ret up
    }
    let xs = x[3usize..3usize + n]
    let ys = x[3usize + n..3usize + 2usize * n]
    let h = x[1usize]
    let p = x[2usize]
    var kind = 0usize
    if str.ends_with(k, "2") { kind = 1usize }
    if str.starts_with(k, "rv") {
        let est = sm.regression(xs, ys, h, p, 1usize)
        let (se, e) = sm.regression_se(a, xs, ys, h, p)
        if e != ok { os.exit(4) }
        if str.eq(k, "rvlo") { ret est - 2.0f64 * se }
        ret est + 2.0f64 * se
    }
    let (se, e) = sm.regression_se_model(a, xs, ys, h, p, kind + 1usize)
    if e != ok { os.exit(4) }
    let my = sm.model_fit(xs, ys, kind, p)
    if str.starts_with(k, "rse") { ret se }
    if str.starts_with(k, "rmy") { ret my }
    if str.starts_with(k, "rlo") { ret my - 2.0f64 * se }
    ret my + 2.0f64 * se
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sm_band.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let start = mem.mark(a)
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
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
