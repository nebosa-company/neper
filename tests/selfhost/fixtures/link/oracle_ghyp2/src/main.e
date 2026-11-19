// e.algo.stat.ghyp2 against GeneralizedHyperbolic. tests/oracle/ghyp2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghyp2`; the layout is at the top of scripts/r_oracle/groups/ghyp2.R.

use e.algo.stat.ghyp as gh
use e.algo.stat.ghyp2 as g2
use e.algo.stat.ghypmore as gm
use e.algo.stat.ghypdist as gd
use e.algo.rand.r as rg
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "ibf") { ret g2.incomplete_bessel_k_ssf(a, x[0usize], x[1usize], x[2usize], x[3usize], usize(x[4usize])) }
    if str.eq(k, "qgig") {
        if x[4usize] == 0.0f64 { ret g2.qgig(a, x[0usize], x[1usize], x[2usize], x[3usize], 501usize, 0.0000000000000491f64, 200usize) }
        ret g2.qgig_integrate(a, x[0usize], x[1usize], x[2usize], x[3usize], 0.0000000000000491f64, 200usize)
    }
    if str.eq(k, "gigcheck") { ret gm.gig_check_pars(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "ghypcheck") { ret gm.ghyp_check_pars(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "gigrawcase") { ret gm.gig_raw_mom_case(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "gigmom") { ret gm.gig_mom(a, usize(x[0usize]), x[2usize], x[3usize], x[4usize], x[1usize]) }
    if str.eq(k, "gigvar2") { ret gm.gig_var2(a, x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "gigskew") { ret gm.gig_skew(a, x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "gigkurt") { ret gm.gig_kurt(a, x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "gigchpars") {
        let (o, e) = mem.alloc[f64](a, 2usize)
        if e != ok { os.exit(9) }
        gm.gig_change_pars(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], o)
        ret o[usize(x[4usize])]
    }
    if str.eq(k, "hyperbchpars") {
        let (o, e) = mem.alloc[f64](a, 2usize)
        if e != ok { os.exit(9) }
        gm.hyperb_change_pars(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], x[4usize], o)
        ret o[usize(x[5usize])]
    }
    if str.eq(k, "ghypscale") {
        let (o, e) = mem.alloc[f64](a, 4usize)
        if e != ok { os.exit(9) }
        gm.ghyp_scale(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], o)
        ret o[usize(x[6usize])]
    }
    if str.eq(k, "ghypstand") {
        let (o, e) = mem.alloc[f64](a, 4usize)
        if e != ok { os.exit(9) }
        gm.ghyp_stand_pars(x[0usize], x[1usize], x[2usize], o)
        ret o[usize(x[6usize])]
    }
    if str.eq(k, "ghypmombns") { ret gm.ghyp_mom_bns(usize(x[0usize]), x[1usize], x[2usize], x[3usize], x[4usize], 0.000000000001f64) }
    if str.eq(k, "ghypmomabout") { ret gh.ghyp_mom_about(a, usize(x[0usize]), x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], 3usize, x[1usize]) }
    if str.eq(k, "rlam") {
        let w = usize(x[0usize])
        if w == 0usize || w == 3usize { ret gm.r_lambda(x[1usize], x[2usize]) }
        if w == 1usize { ret gm.s_lambda(x[1usize], x[2usize]) }
        if w == 2usize { ret gm.m_lambda(x[1usize], x[2usize]) }
        if w == 4usize { ret gm.w_lambda2(x[1usize], x[2usize]) }
        if w == 5usize { ret gm.w_lambda3(x[1usize], x[2usize]) }
        ret gm.w_lambda4(x[1usize], x[2usize])
    }
    if str.eq(k, "gamlam") {
        if x[0usize] == 1.0f64 { ret gm.gamma_lambda1(x[1usize], x[2usize], x[3usize]) }
        ret gm.gamma_lambda2(x[1usize], x[2usize], x[3usize])
    }
    if str.eq(k, "dgigs") { ret gm.dgig_scaled(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "ddgig") { ret gm.ddgig(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "ddfam") {
        var lm = 1.0f64
        if x[0usize] == 1.0f64 { lm = 0.0f64 - 0.5f64 }
        ret gh.ddghyp(x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], lm)
    }
    if str.eq(k, "pghypT") {
        var qcx = gd.qc_new(a, x[1usize], x[2usize], x[3usize], x[4usize], x[5usize])
        ret gd.pghyp_tail(&qcx, x[0usize], x[6usize] == 1.0f64, gd.qc_mode(&qcx))
    }
    if str.eq(k, "qghypF") { ret gd.qghyp_full(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize] == 1.0f64, x[7usize] == 0.0f64, 501usize, 0.0001220703125f64, 100usize) }
    if str.eq(k, "ghypmode") { ret gh.ghyp_mode(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "ghyprange") {
        let (lo, hi) = gd.ghyp_calc_range(a, x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[0usize])
        if x[1usize] == 0.0f64 { ret lo }
        ret hi
    }
    if str.eq(k, "gigrange") {
        let (lo, hi) = g2.gig_range(x[2usize], x[3usize], x[4usize], x[0usize])
        if x[1usize] == 0.0f64 { ret lo }
        ret hi
    }
    if str.eq(k, "famstat") {
        let lam = 1.0f64 - 1.5f64 * x[0usize]
        let w = usize(x[1usize])
        if w == 0usize { ret gh.ghyp_mean(x[2usize], x[3usize], x[4usize], x[5usize], lam) }
        if w == 1usize { ret gh.ghyp_var(x[3usize], x[4usize], x[5usize], lam) }
        if w == 2usize { ret gh.ghyp_skew(a, x[2usize], x[3usize], x[4usize], x[5usize], lam) }
        if w == 3usize { ret gh.ghyp_kurt(a, x[2usize], x[3usize], x[4usize], x[5usize], lam) }
        if x[0usize] == 0.0f64 { ret x[2usize] + 1.0f64 * (x[5usize] / math.sqrt[f64](x[4usize] * x[4usize] - x[5usize] * x[5usize])) }
        ret gh.ghyp_mode(x[2usize], x[3usize], x[4usize], x[5usize], lam)
    }
    if str.eq(k, "dshyperb") {
        let (o, e) = mem.alloc[f64](a, 4usize)
        if e != ok { os.exit(9) }
        gm.ghyp_stand_pars(x[1usize], x[2usize], 1.0f64, o)
        ret gh.dhyperb(x[0usize], o[0usize], o[1usize], o[2usize], o[3usize])
    }
    if str.eq(k, "rnig") || str.eq(k, "rhyperb") {
        let nn = usize(x[1usize])
        let (o, g1) = mem.alloc[f64](a, nn)
        let (xx, g2_) = mem.alloc[f64](a, nn)
        if g1 != ok || g2_ != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        var lam = 1.0f64
        if str.eq(k, "rnig") { lam = 0.0f64 - 0.5f64 }
        gh.rghyp(&rng, nn, x[3usize], x[4usize], x[5usize], x[6usize], lam, o, xx)
        ret o[usize(x[2usize])]
    }
    if str.eq(k, "rgigx") {
        let nn = usize(x[1usize])
        let (o, g1) = mem.alloc[f64](a, nn)
        if g1 != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        gh.rgig(&rng, nn, x[3usize], x[4usize], x[5usize], o)
        ret o[usize(x[2usize])]
    }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghyp2.json")
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
