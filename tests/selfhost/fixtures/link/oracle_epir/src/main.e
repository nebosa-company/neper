// e.algo.stat.epir against epiR. tests/oracle/epir.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R epir`; the layout is at the top of scripts/r_oracle/groups/epir.R.

use e.algo.stat.epir as ep
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "sb") { ret ep.sssimpleestb(x[0usize], x[1usize], x[2usize], x[3usize] > 0.5f64, x[4usize], x[5usize], x[6usize] > 0.5f64, 0.95f64) }
    if str.eq(c.name, "ms") {
        let ks = usize(x[0usize])
        let wsel = usize(x[2usize + 4usize * ks])
        let (se1, sl1, su1) = ep.strata_mh_rd_var(x[2usize..2usize + ks], x[2usize + ks..2usize + 2usize * ks], x[2usize + 2usize * ks..2usize + 3usize * ks], x[2usize + 3usize * ks..2usize + 4usize * ks], 0.95f64, x[1usize], wsel / 3usize)
        if wsel % 3usize == 0usize { ret se1 }
        if wsel % 3usize == 1usize { ret sl1 }
        ret su1
    }
    if str.eq(c.name, "bd") {
        let kb = usize(x[0usize])
        ret ep.breslow_day(x[1usize..1usize + kb], x[1usize + kb..1usize + 2usize * kb], x[1usize + 2usize * kb..1usize + 3usize * kb], x[1usize + 3usize * kb..1usize + 4usize * kb])
    }
    if str.eq(c.name, "mr") {
        let kr = usize(x[0usize])
        var rv: [8]f64 = zero
        ep.strata_mh_rd(x[2usize..2usize + kr], x[2usize + kr..2usize + 2usize * kr], x[2usize + 2usize * kr..2usize + 3usize * kr], x[2usize + 3usize * kr..2usize + 4usize * kr], 0.95f64, x[1usize], rv[0usize..8usize])
        ret rv[usize(x[2usize + 4usize * kr])]
    }
    if str.eq(c.name, "mh") {
        let km = usize(x[0usize])
        var mv: [12]f64 = zero
        ep.strata_mh(x[1usize..1usize + km], x[1usize + km..1usize + 2usize * km], x[1usize + 2usize * km..1usize + 3usize * km], x[1usize + 3usize * km..1usize + 4usize * km], 0.95f64, mv[0usize..12usize])
        ret mv[usize(x[1usize + 4usize * km])]
    }
    if str.eq(c.name, "iv") || str.eq(c.name, "ivr") {
        let ki = usize(x[0usize])
        var iv: [16]f64 = zero
        ep.epi_iv_or(x[1usize..1usize + ki], x[1usize + ki..1usize + 2usize * ki], x[1usize + 2usize * ki..1usize + 3usize * ki], x[1usize + 3usize * ki..1usize + 4usize * ki], str.eq(c.name, "ivr"), 0.95f64, iv[0usize..16usize])
        ret iv[usize(x[1usize + 4usize * ki])]
    }
    if str.eq(c.name, "dsl") || str.eq(c.name, "dslr") {
        let kd = usize(x[0usize])
        var dv: [8]f64 = zero
        ep.epi_dsl_or(x[1usize..1usize + kd], x[1usize + kd..1usize + 2usize * kd], x[1usize + 2usize * kd..1usize + 3usize * kd], x[1usize + 3usize * kd..1usize + 4usize * kd], str.eq(c.name, "dslr"), 0.95f64, dv[0usize..8usize])
        ret dv[usize(x[1usize + 4usize * kd])]
    }
    if str.eq(c.name, "ss") {
        let wq = usize(x[8usize])
        if wq == 3usize { ret ep.sscc_power(x[0usize], x[1usize], x[7usize], x[2usize], x[5usize], 0.95f64) }
        let (q1, q0, qt) = ep.sscc_n(x[0usize], x[1usize], x[7usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize] > 0.5f64, 0.95f64)
        if wq == 0usize { ret q1 }
        if wq == 1usize { ret q0 }
        ret qt
    }
    if str.eq(c.name, "sc") {
        let ws = usize(x[8usize])
        if ws == 3usize { ret ep.sscohort_power(x[0usize], x[1usize], x[7usize], x[2usize], x[3usize], x[4usize], x[5usize], 0.95f64) }
        let (s1, s0, st) = ep.sscohort_n(x[0usize], x[1usize], x[7usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize] > 0.5f64, 0.95f64)
        if ws == 0usize { ret s1 }
        if ws == 1usize { ret s0 }
        ret st
    }
    if str.eq(c.name, "ccc") {
        let nc = usize(x[0usize])
        var ov: [10]f64 = zero
        ep.epi_ccc(x[1usize..1usize + nc], x[1usize + nc..1usize + 2usize * nc], 0.95f64, ov[0usize..10usize])
        ret ov[usize(x[1usize + 2usize * nc])]
    }
    if str.eq(c.name, "ct") {
        let wt = usize(x[5usize])
        let kt = wt / 3usize
        var t0 = 0.0f64
        var t1 = 0.0f64
        var t2 = 0.0f64
        if kt == 0usize {
            let (a0, a1, a2) = ep.ct_irr(x[0usize], x[1usize], x[2usize], x[3usize], 0.95f64)
            t0 = a0
            t1 = a1
            t2 = a2
        } else if kt == 1usize {
            let (b0, b1, b2) = ep.ct_arate(x[0usize], x[1usize], x[2usize], x[3usize], 0.95f64, x[4usize])
            t0 = b0
            t1 = b1
            t2 = b2
        } else if kt == 2usize {
            let (c0, c1, c2) = ep.ct_afrate(x[0usize], x[1usize], x[2usize], x[3usize], 0.95f64)
            t0 = c0
            t1 = c1
            t2 = c2
        } else if kt == 3usize {
            let (d0, d1, d2) = ep.ct_parate(x[0usize], x[1usize], x[2usize], x[3usize], 0.95f64, x[4usize])
            t0 = d0
            t1 = d1
            t2 = d2
        } else {
            let (e0, e1, e2) = ep.ct_pafrate(x[0usize], x[1usize], x[2usize], x[3usize], 0.95f64)
            t0 = e0
            t1 = e1
            t2 = e2
        }
        if wt % 3usize == 0usize { ret t0 }
        if wt % 3usize == 1usize { ret t1 }
        ret t2
    }
    if str.eq(c.name, "pp") {
        let kp = usize(x[0usize])
        var v0 = 0.0f64
        var v1 = 0.0f64
        var v2 = 0.0f64
        var v3 = 0.0f64
        if kp == 0usize {
            let (a0, a1, a2, a3) = ep.conf_prop_single(x[2usize], x[3usize], 0.95f64)
            v0 = a0
            v1 = a1
            v2 = a2
            v3 = a3
        } else if kp == 1usize {
            let (b0, b1, b2, b3) = ep.conf_prop_unpaired(x[2usize], x[3usize], x[4usize], x[5usize], 0.95f64)
            v0 = b0
            v1 = b1
            v2 = b2
            v3 = b3
        } else {
            let (c0, c1, c2, c3) = ep.conf_prop_paired(x[2usize], x[3usize], x[4usize], x[5usize], 0.95f64)
            v0 = c0
            v1 = c1
            v2 = c2
            v3 = c3
        }
        let wp = usize(x[1usize])
        if wp == 0usize { ret v0 }
        if wp == 1usize { ret v1 }
        if wp == 2usize { ret v2 }
        ret v3
    }
    if str.eq(c.name, "cm") {
        let kd = usize(x[0usize])
        let n1 = usize(x[2usize])
        let n2 = usize(x[3usize])
        let d1 = x[4usize..4usize + n1]
        let d2 = x[4usize + n1..4usize + n1 + n2]
        var q0 = 0.0f64
        var q1 = 0.0f64
        var q2 = 0.0f64
        var q3 = 0.0f64
        if kd == 0usize {
            let (a0, a1, a2, a3) = ep.conf_mean_single(d1, 0.95f64)
            q0 = a0
            q1 = a1
            q2 = a2
            q3 = a3
        } else if kd == 1usize {
            let (b0, b1, b2, b3) = ep.conf_mean_unpaired(d1, d2, 0.95f64)
            q0 = b0
            q1 = b1
            q2 = b2
            q3 = b3
        } else {
            let (c0, c1, c2, c3) = ep.conf_mean_paired(a, d1, d2, 0.95f64)
            q0 = c0
            q1 = c1
            q2 = c2
            q3 = c3
        }
        let wm = usize(x[1usize])
        if wm == 0usize { ret q0 }
        if wm == 1usize { ret q1 }
        if wm == 2usize { ret q2 }
        ret q3
    }
    if str.eq(c.name, "cr") {
        let (re, rl, ru) = ep.conf_inc_rate(x[0usize], x[1usize], 0.95f64, usize(x[2usize]) == 1usize)
        let wr = usize(x[3usize])
        if wr == 0usize { ret re }
        if wr == 1usize { ret rl }
        ret ru
    }
    if str.eq(c.name, "cs") {
        let ks = usize(x[0usize])
        let (se0, se1, se2, se3) = ep.conf_smr(x[2usize..2usize + ks], x[2usize + ks..2usize + 2usize * ks], usize(x[1usize]), 0.95f64)
        let ws = usize(x[2usize + 2usize * ks])
        if ws == 0usize { ret se0 }
        if ws == 1usize { ret se1 }
        if ws == 2usize { ret se2 }
        ret se3
    }
    if str.eq(c.name, "co") {
        let (oe, ol, ou) = ep.conf_odds(x[0usize], x[1usize], 0.95f64)
        let wo = usize(x[2usize])
        if wo == 0usize { ret oe }
        if wo == 1usize { ret ol }
        ret ou
    }
    if str.eq(c.name, "cf") {
        let tc2 = ep.Table2 { a: x[0usize], b: x[1usize], c: x[2usize], d: x[3usize] }
        let (ce, cl2, ch2, cer) = ep.or_cfield(a, tc2, 0.95f64)
        if cer != ok { os.exit(15) }
        let wc2 = usize(x[4usize])
        if wc2 == 0usize { ret ce }
        if wc2 == 1usize { ret cl2 }
        ret ch2
    }
    if str.eq(c.name, "mle") {
        let tf = ep.Table2 { a: x[0usize], b: x[1usize], c: x[2usize], d: x[3usize] }
        let (fe, fl, fh, fer) = ep.fisher_or(a, tf, 0.95f64)
        if fer != ok { os.exit(14) }
        let wf = usize(x[4usize])
        if wf == 0usize { ret fe }
        if wf == 1usize { ret fl }
        ret fh
    }
    if str.eq(c.name, "cc") {
        let tc = ep.Table2 { a: x[0usize], b: x[1usize], c: x[2usize], d: x[3usize] }
        let wc = usize(x[4usize])
        var ce = 0.0f64
        var cl = 0.0f64
        var ch = 0.0f64
        if wc < 3usize {
            let (e9, l9, h9) = ep.or_score(tc, 0.95f64)
            ce = e9
            cl = l9
            ch = h9
        } else {
            let (e10, l10, h10) = ep.af_est(tc, 0.95f64)
            ce = e10
            cl = l10
            ch = h10
        }
        if wc % 3usize == 0usize { ret ce }
        if wc % 3usize == 1usize { ret cl }
        ret ch
    }
    if str.eq(c.name, "pc") {
        let (e8, l8, h8) = ep.prop_ci(x[0usize], x[1usize], 0.95f64, usize(x[2usize]))
        if usize(x[3usize]) == 0usize { ret e8 }
        if usize(x[3usize]) == 1usize { ret l8 }
        ret h8
    }
    if str.eq(c.name, "dt") {
        let td = ep.Table2 { a: x[0usize], b: x[1usize], c: x[2usize], d: x[3usize] }
        let code = usize(x[4usize])
        let (e7, l7, h7) = ep.epi_tests(td, 0.95f64, (code % 100usize) / 3usize, code / 100usize)
        if (code % 100usize) % 3usize == 0usize { ret e7 }
        if (code % 100usize) % 3usize == 1usize { ret l7 }
        ret h7
    }
    let t = ep.Table2 { a: x[0usize], b: x[1usize], c: x[2usize], d: x[3usize] }
    let units = x[4usize]
    let w = usize(x[5usize])
    if w >= 36usize {
        let (ke, kl, kh) = ep.rr_koopman(t, 0.95f64)
        let rk = (w - 36usize) % 3usize
        if rk == 0usize { ret ke }
        if rk == 1usize { ret kl }
        ret kh
    }
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
