// e.algo.stat.ghyp against GeneralizedHyperbolic. tests/oracle/ghypnfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghypnfit`; the layout is at the top of scripts/r_oracle/groups/ghypnfit.R.

use e.algo.rand.r as rg
use e.algo.stat.ghyp as gh
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "ghypMom") { ret gh.ghyp_mom(a, usize(x[0usize]), x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], usize(x[1usize])) }
    if str.eq(k, "hyperbFit") {
        let nn = usize(x[0usize])
        let wh = usize(x[1usize])
        let (o, g1) = mem.alloc[f64](a, 4usize)
        if g1 != ok { os.exit(7) }
        let (ml, cnt, fl) = gh.hyperb_fit(a, x[7usize..7usize + nn], x[2usize..6usize], o)
        if wh < 4usize { ret o[wh] }
        if wh == 4usize { ret ml }
        ret f64(cnt)
    }
    if str.eq(k, "nigFit") {
        let nn = usize(x[0usize])
        let wh = usize(x[1usize])
        let (o, g1) = mem.alloc[f64](a, 4usize)
        if g1 != ok { os.exit(7) }
        let (ml, cnt, fl) = gh.nig_fit(a, x[7usize..7usize + nn], x[2usize..6usize], o)
        if wh < 4usize { ret o[wh] }
        if wh == 4usize { ret ml }
        ret f64(cnt)
    }
    if str.eq(k, "ghypKurt") { ret gh.ghyp_kurt(a, x[2usize], x[3usize], x[4usize], x[5usize], x[6usize]) }
    if str.eq(k, "pgig") { ret gh.pgig(a, x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "ghypSkew") { ret gh.ghyp_skew(a, x[2usize], x[3usize], x[4usize], x[5usize], x[6usize]) }
    if str.eq(k, "pskewlap") { ret gh.pskewlap(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "qskewlap") { ret gh.qskewlap(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "dgig") { ret gh.dgig(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "gigMode") { ret gh.gig_mode(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "gigVar") { ret gh.gig_var(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "gigRaw3") { ret gh.gig_raw_mom(3.0f64, x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "gigMean") { ret gh.gig_mean(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "rskewlap") {
        let nn = usize(x[1usize])
        let (o, g1) = mem.alloc[f64](a, nn)
        let (yy, g2) = mem.alloc[f64](a, nn)
        if g1 != ok || g2 != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        gh.rskewlap(&rng, nn, x[3usize], x[4usize], x[5usize], o, yy)
        ret o[usize(x[2usize])]
    }
    if str.eq(k, "rghyp") {
        let nn = usize(x[1usize])
        let (o, g1) = mem.alloc[f64](a, nn)
        let (xx, g2) = mem.alloc[f64](a, nn)
        if g1 != ok || g2 != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        gh.rghyp(&rng, nn, x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], o, xx)
        ret o[usize(x[2usize])]
    }
    if str.eq(k, "qghyp") { ret gh.qghyp(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "ghypMean") { ret gh.ghyp_mean(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "ghypVar") { ret gh.ghyp_var(x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "pghyp") { ret gh.pghyp(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "pnig") { ret gh.pnig(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "phyperb") { ret gh.phyperb(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "ddghyp") { ret gh.ddghyp(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "chpars") {
        let (o, e) = mem.alloc[f64](a, 2usize)
        if e != ok { os.exit(9) }
        gh.ghyp_change_pars(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], x[4usize], o)
        ret o[usize(x[5usize])]
    }
    if str.eq(k, "dghyp") { ret gh.dghyp(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "dnig") { ret gh.dnig(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(k, "dhyperb") { ret gh.dhyperb(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    ret gh.dskewlap(x[0usize], x[1usize], x[2usize], x[3usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghypnfit.json")
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
