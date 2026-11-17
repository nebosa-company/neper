// e.algo.stat.lmerpkg against lme4 lmer for one random intercept. tests/oracle/lmer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lmer`; the layout is at the top of scripts/r_oracle/groups/lmer.R.

use e.algo.stat.lmerpkg as lm
use e.io
use e.math
use e.math.nmath_beta as nb
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let ng = usize(z[2usize])
    let reml = z[3usize] != 0.0f64
    let which = usize(z[4usize])
    let (g, ge) = mem.alloc[usize](a, n)
    let (beta, be) = mem.alloc[f64](a, p)
    let (re, ree) = mem.alloc[f64](a, ng)
    let (out, oe) = mem.alloc[f64](a, 4usize)
    if ge != ok || be != ok || ree != ok || oe != ok { ret nan }
    var i = 0usize
    while i < n {
        g[i] = usize(z[5usize + n * p + i])
        i += 1usize
    }
    if which >= 6000usize {
        // joint contest: which = 6000 + k (0 F, 1 numerator df, 2 denominator df, 3 p value), theta, sigma, q, then L (q by p, row-major) follow the data
        let th = z[5usize + n * p + 2usize * n]
        let sg = z[5usize + n * p + 2usize * n + 1usize]
        let q = usize(z[5usize + n * p + 2usize * n + 2usize])
        let (jo, jee) = mem.alloc[f64](a, 4usize)
        if jee != ok { ret nan }
        if lm.lmer_contest_joint(a, z[5usize..5usize + n * p], z[5usize + n * p + n..5usize + n * p + 2usize * n], g, n, p, ng, reml, th, sg, z[5usize + n * p + 2usize * n + 3usize..5usize + n * p + 2usize * n + 3usize + q * p], q, jo) != ok { ret nan }
        ret jo[which - 6000usize]
    }
    if which >= 5000usize {
        // ranova: which = 5000 + k (0 reduced criterion, 1 full criterion, 2 LRT, 3 p value), theta and sigma follow the data
        let th = z[5usize + n * p + 2usize * n]
        let sg = z[5usize + n * p + 2usize * n + 1usize]
        let (ro, rae) = mem.alloc[f64](a, 4usize)
        if rae != ok { ret nan }
        if lm.lmer_ranova(a, z[5usize..5usize + n * p], z[5usize + n * p + n..5usize + n * p + 2usize * n], g, n, p, ng, th, sg, ro) != ok { ret nan }
        ret ro[which - 5000usize]
    }
    if which >= 4000usize {
        // contest1D: which = 4000 + k (k 0..4 the output), the contrast L[p] follows theta and sigma
        let th = z[5usize + n * p + 2usize * n]
        let sg = z[5usize + n * p + 2usize * n + 1usize]
        let (co, ce) = mem.alloc[f64](a, 5usize)
        if ce != ok { ret nan }
        if lm.lmer_contest(a, z[5usize..5usize + n * p], z[5usize + n * p + n..5usize + n * p + 2usize * n], g, n, p, ng, reml, th, sg, z[5usize + n * p + 2usize * n + 2usize..5usize + n * p + 2usize * n + 2usize + p], co) != ok { ret nan }
        ret co[which - 4000usize]
    }
    if which >= 1000usize {
        // Satterthwaite df of fixed effect (which - 1000) at lme4's (theta, sigma): args after the data are theta, sigma
        let th = z[5usize + n * p + 2usize * n]
        let sg = z[5usize + n * p + 2usize * n + 1usize]
        let (dfo, de) = mem.alloc[f64](a, p)
        let (eo, ee) = mem.alloc[f64](a, p)
        let (so, se2) = mem.alloc[f64](a, p)
        if de != ok || ee != ok || se2 != ok { ret nan }
        if lm.lmer_satt(a, z[5usize..5usize + n * p], z[5usize + n * p + n..5usize + n * p + 2usize * n], g, n, p, ng, reml, th, sg, dfo, eo, so) != ok { ret nan }
        // which = 1000 + j: the df; 2000 + j: the t statistic; 3000 + j: its two-sided p value
        let jj = which % 1000usize
        if which < 2000usize { ret dfo[jj] }
        let tv = eo[jj] / so[jj]
        if which < 3000usize { ret tv }
        ret 2.0f64 * nb.pt(0.0f64 - math.abs[f64](tv), dfo[jj], true, false)
    }
    if lm.lmer_ri(a, z[5usize..5usize + n * p], z[5usize + n * p + n..5usize + n * p + 2usize * n], g, n, p, ng, reml, beta, re, out) != ok { ret nan }
    if which < 4usize { ret out[which] }
    if which < 4usize + p { ret beta[which - 4usize] }
    ret re[which - 4usize - p]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lmer.json")
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
