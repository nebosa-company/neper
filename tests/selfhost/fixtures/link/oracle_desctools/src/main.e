// e.algo.stat.desctools against DescTools. tests/oracle/desctools.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desctools`; the layout is at the top of scripts/r_oracle/groups/desctools.R.

use e.algo.stat.desctools as dt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "binomci") { ret dt.binom_ci(x[1usize], x[2usize], x[3usize], usize(x[0usize]), usize(x[4usize])) }
    if str.eq(c.name, "poisci") { ret dt.poisson_ci(x[1usize], x[2usize], x[3usize], usize(x[0usize]), usize(x[4usize])) }
    if str.eq(c.name, "multici") { ret dt.multinom_ci(x[5usize..5usize + usize(x[4usize])], usize(x[1usize]), x[2usize], usize(x[0usize]), usize(x[3usize])) }
    if str.eq(c.name, "catz") { ret dt.cochran_armitage(x[3usize..3usize + 2usize * usize(x[0usize])], usize(x[0usize]), 0usize) }
    if str.eq(c.name, "catp") { ret dt.cochran_armitage(x[3usize..3usize + 2usize * usize(x[0usize])], usize(x[0usize]), 1usize) }
    if str.eq(c.name, "mhor") { ret dt.mh_or(x[3usize..3usize + 4usize * usize(x[0usize])], usize(x[0usize])) }
    if str.eq(c.name, "bdx") { ret dt.breslow_day(x[3usize..3usize + 4usize * usize(x[0usize])], usize(x[0usize]), false, 0usize) }
    if str.eq(c.name, "bdp") { ret dt.breslow_day(x[3usize..3usize + 4usize * usize(x[0usize])], usize(x[0usize]), false, 1usize) }
    if str.eq(c.name, "bdtx") { ret dt.breslow_day(x[3usize..3usize + 4usize * usize(x[0usize])], usize(x[0usize]), true, 0usize) }
    if str.eq(c.name, "bdtp") { ret dt.breslow_day(x[3usize..3usize + 4usize * usize(x[0usize])], usize(x[0usize]), true, 1usize) }
    if str.eq(c.name, "winsor") { ret dt.winsor_sum(a, x[3usize..3usize + usize(x[0usize])], x[1usize], x[2usize]) }
    if str.eq(c.name, "hl1") { ret dt.hodges_lehmann(a, x[3usize..3usize + usize(x[0usize])], x[0usize..0usize]) }
    if str.eq(c.name, "hl2") {
        let nx = usize(x[0usize])
        ret dt.hodges_lehmann(a, x[3usize..3usize + nx], x[3usize + nx..3usize + nx + usize(x[1usize])])
    }
    if str.eq(c.name, "medci") { ret dt.median_ci(a, x[3usize..3usize + usize(x[0usize])], x[1usize], usize(x[2usize])) }
    if str.eq(c.name, "trim") { ret dt.trim_sum(a, x[3usize..3usize + usize(x[0usize])], x[1usize]) }
    let n = usize(x[0usize])
    let v = x[1usize..1usize + n]
    let k = c.name
    if str.eq(k, "kappa") || str.eq(k, "lambda_symmetric") || str.eq(k, "lambda_row") || str.eq(k, "lambda_column") || str.eq(k, "tau_row") || str.eq(k, "tau_col") || str.eq(k, "or") || str.eq(k, "yq") {
        let r = usize(x[0usize])
        let cc = usize(x[1usize])
        let tb = x[2usize..2usize + r * cc]
        if str.eq(k, "kappa") { ret dt.cohen_kappa(tb, r) }
        if str.eq(k, "lambda_symmetric") { ret dt.lambda_gk(tb, r, cc, 0usize) }
        if str.eq(k, "lambda_row") { ret dt.lambda_gk(tb, r, cc, 1usize) }
        if str.eq(k, "lambda_column") { ret dt.lambda_gk(tb, r, cc, 2usize) }
        if str.eq(k, "tau_row") { ret dt.gk_tau(tb, r, cc, 1usize) }
        if str.eq(k, "tau_col") { ret dt.gk_tau(tb, r, cc, 2usize) }
        if str.eq(k, "or") { ret dt.odds_ratio(tb) }
        ret dt.yule_q(tb)
    }
    if str.eq(k, "cramer") || str.eq(k, "phi") || str.eq(k, "cont") || str.eq(k, "tschuprow") || str.eq(k, "gamma") || str.eq(k, "taub") || str.eq(k, "tauc") || str.eq(k, "somersr") || str.eq(k, "somersc") {
        let r = usize(x[0usize])
        let cc = usize(x[1usize])
        let tb = x[2usize..2usize + r * cc]
        if str.eq(k, "cramer") { ret dt.cramer_v(tb, r, cc) }
        if str.eq(k, "phi") { ret dt.phi_coef(tb, r, cc) }
        if str.eq(k, "cont") { ret dt.cont_coef(tb, r, cc) }
        if str.eq(k, "tschuprow") { ret dt.tschuprow_t(tb, r, cc) }
        if str.eq(k, "gamma") { ret dt.ordinal_assoc(tb, r, cc, 0usize) }
        if str.eq(k, "taub") { ret dt.ordinal_assoc(tb, r, cc, 1usize) }
        if str.eq(k, "tauc") { ret dt.ordinal_assoc(tb, r, cc, 2usize) }
        if str.eq(k, "somersr") { ret dt.ordinal_assoc(tb, r, cc, 3usize) }
        ret dt.ordinal_assoc(tb, r, cc, 4usize)
    }
    if str.eq(k, "skew1") { ret dt.skew(v, 1usize) }
    if str.eq(k, "skew2") { ret dt.skew(v, 2usize) }
    if str.eq(k, "skew3") { ret dt.skew(v, 3usize) }
    if str.eq(k, "kurt1") { ret dt.kurt(v, 1usize) }
    if str.eq(k, "kurt2") { ret dt.kurt(v, 2usize) }
    if str.eq(k, "kurt3") { ret dt.kurt(v, 3usize) }
    if str.eq(k, "gini") { ret dt.gini(a, v, true) }
    if str.eq(k, "ginib") { ret dt.gini(a, v, false) }
    if str.eq(k, "meanad") { ret dt.mean_ad(v) }
    if str.eq(k, "gmean") { ret dt.gmean(v) }
    if str.eq(k, "hmean") { ret dt.hmean(v) }
    if str.eq(k, "entropy") { ret dt.entropy(v) }
    ret dt.coef_var(v)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desctools.json")
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
