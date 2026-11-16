// e.algo.stat.scoringrules against scoringRules. tests/oracle/scoringrules.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R scoringrules`; the layout is at the top of scripts/r_oracle/groups/scoringrules.R.

use e.algo.stat.scoringrules as sr
use e.io
use e.mem
use e.math.nmath_beta as nb
use e.os
use e.str
use e.test.oracle as oracle

fn param(c: *const oracle.Case) -> f64 {
    let x = c.args
    let fam = usize(x[0usize])
    let a = x[1usize]
    let b = x[2usize]
    let cc = x[3usize]
    let d = x[4usize]
    let y = x[5usize]
    let k = c.name
    let isc = str.eq(k, "crps")
    let isl = str.eq(k, "logs")
    if fam >= 16usize {
        // (fam, df, loc, scale, lower, upper, y, lmass, umass)
        let dfv = x[1usize]
        let lo2 = x[4usize]
        let hi2 = x[5usize]
        let yv = x[6usize]
        if fam == 16usize { ret sr.crps_gtct(yv, dfv, x[2usize], x[3usize], lo2, hi2, x[7usize], x[8usize]) }
        if fam == 17usize { ret sr.crps_gtct(yv, dfv, x[2usize], x[3usize], lo2, hi2, 0.0f64, 0.0f64) }
        ret sr.crps_gtct(yv, dfv, x[2usize], x[3usize], lo2, hi2, nb.pt((lo2 - x[2usize]) / x[3usize], dfv, true, false), 1.0f64 - nb.pt((hi2 - x[2usize]) / x[3usize], dfv, true, false))
    }
    if fam == 0usize {
        if isc { ret sr.crps_norm(y, a, b) }
        if isl { ret sr.logs_norm(y, a, b) }
        ret sr.dss_norm(y, a, b)
    }
    if fam == 1usize {
        if isc { ret sr.crps_logis(y, a, b) }
        if isl { ret sr.logs_logis(y, a, b) }
        ret sr.dss_logis(y, a, b)
    }
    if fam == 2usize {
        if isc { ret sr.crps_lapl(y, a, b) }
        if isl { ret sr.logs_lapl(y, a, b) }
        ret sr.dss_lapl(y, a, b)
    }
    if fam == 3usize {
        if isc { ret sr.crps_exp(y, a) }
        if isl { ret sr.logs_exp(y, a) }
        ret sr.dss_exp(y, a)
    }
    if fam == 4usize {
        if isc { ret sr.crps_unif(y, a, b, cc, d) }
        if isl { ret sr.logs_unif(y, a, b) }
        ret sr.dss_unif(y, a, b)
    }
    if fam == 5usize {
        if isc { ret sr.crps_lnorm(y, a, b) }
        if isl { ret sr.logs_lnorm(y, a, b) }
        ret sr.dss_lnorm(y, a, b)
    }
    if fam == 6usize {
        if isc { ret sr.crps_gamma(y, a, b) }
        if isl { ret sr.logs_gamma(y, a, b) }
        ret sr.dss_gamma(y, a, b)
    }
    if fam == 7usize { ret sr.crps_binom(y, a, b) }
    if fam == 8usize && isc { ret sr.crps_pois(y, a) }
    if fam == 10usize { ret sr.crps_gtcnorm(y, a, b, cc, d, x[6usize], x[7usize]) }
    if fam == 11usize { ret sr.crps_gtcnorm(y, a, b, cc, d, 0.0f64, 0.0f64) }
    if fam == 12usize { ret sr.crps_gtcnorm(y, a, b, cc, d, sr.pn((cc - a) / b), 1.0f64 - sr.pn((d - a) / b)) }
    if fam == 13usize { ret sr.crps_gtclogis(y, a, b, cc, d, x[6usize], x[7usize]) }
    if fam == 14usize { ret sr.crps_gtclogis(y, a, b, cc, d, 0.0f64, 0.0f64) }
    if fam == 15usize { ret sr.crps_gtclogis(y, a, b, cc, d, sr.plogis_std((cc - a) / b), 1.0f64 - sr.plogis_std((d - a) / b)) }
    if fam == 9usize {
        if isc { ret sr.crps_t(y, a, b, cc) }
        ret sr.logs_t(y, a, b, cc)
    }
    if isl { ret sr.logs_pois(y, a) }
    ret sr.dss_pois(y, a)
}

fn sample(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let alpha = x[1usize]
    let m = usize(x[2usize])
    let d = usize(x[3usize])
    let y = x[4usize..4usize + d]
    let dat = x[4usize + d..4usize + d + m * d]
    if kind == 0usize { ret sr.crps_sample(y[0usize], dat) }
    if kind == 1usize { ret sr.dss_sample(y[0usize], dat) }
    if kind == 2usize { ret sr.logs_sample(a, y[0usize], dat) }
    if kind == 3usize { ret sr.es_sample(y, dat, m) }
    if kind == 4usize { ret sr.vs_sample(y, dat, m, alpha) }
    if kind == 5usize { ret sr.qs_sample(a, y[0usize], dat, alpha) }
    ret sr.rps_probs(usize(y[0usize]), dat)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/scoringrules.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64
        if str.eq(c.name, "sample") { got = sample(a, c) } else { got = param(c) }
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
