// e.algo.stat.epir against epiR. tests/oracle/epir.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R epir`; the layout is at the top of scripts/r_oracle/groups/epir.R.

use e.algo.stat.epir as ep
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let t = ep.Table2 { a: x[0usize], b: x[1usize], c: x[2usize], d: x[3usize] }
    let units = x[4usize]
    let w = usize(x[5usize])
    if w >= 33usize || (w >= 21usize && w < 24usize) {
        var xe = 0.0f64
        var xl = 0.0f64
        var xh = 0.0f64
        if w >= 33usize {
            let (e5, l5, h5) = ep.af_risk(t, 0.95f64)
            xe = e5
            xl = l5
            xh = h5
        } else {
            let (e6, l6, h6) = ep.rr_score(t, 0.95f64)
            xe = e6
            xl = l6
            xh = h6
        }
        let r5 = (w - 21usize) % 3usize
        if r5 == 0usize { ret xe }
        if r5 == 1usize { ret xl }
        ret xh
    }
    if w >= 24usize {
        var re = 0.0f64
        var rl = 0.0f64
        var rh = 0.0f64
        if w < 27usize {
            let (e2, l2, h2) = ep.paf_risk(t, 0.95f64)
            re = e2
            rl = l2
            rh = h2
        } else if w < 30usize {
            let (e3, l3, h3) = ep.par_risk_ci(t, 0.95f64, units, 0usize)
            re = e3
            rl = l3
            rh = h3
        } else {
            let (e4, l4, h4) = ep.par_risk_ci(t, 0.95f64, units, 1usize)
            re = e4
            rl = l4
            rh = h4
        }
        let r3 = (w - 24usize) % 3usize
        if r3 == 0usize { ret re }
        if r3 == 1usize { ret rl }
        ret rh
    }
    if w < 3usize {
        let (e, lo, hi) = ep.risk_ratio(t, 0.95f64)
        if w == 0usize { ret e }
        if w == 1usize { ret lo }
        ret hi
    }
    if w < 6usize {
        let (e, lo, hi) = ep.odds_ratio(t, 0.95f64)
        if w == 3usize { ret e }
        if w == 4usize { ret lo }
        ret hi
    }
    if w < 9usize {
        let (e, lo, hi) = ep.risk_difference(t, 0.95f64, units)
        if w == 6usize { ret e }
        if w == 7usize { ret lo }
        ret hi
    }
    if w < 12usize {
        let (e, lo, hi) = ep.nnt(t, 0.95f64, units)
        if w == 9usize { ret e }
        if w == 10usize { ret lo }
        ret hi
    }
    if w == 12usize { ret ep.par_risk(t, units) }
    if w < 15usize {
        let (z, p) = ep.wald_test(t, 0usize)
        if w == 13usize { ret z }
        ret p
    }
    if w < 17usize {
        let (z, p) = ep.wald_test(t, 1usize)
        if w == 15usize { ret z }
        ret p
    }
    if w < 19usize {
        let (s, p) = ep.chi2(t, false)
        if w == 17usize { ret s }
        ret p
    }
    let (s, p) = ep.chi2(t, true)
    if w == 19usize { ret s }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/epir.json")
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
