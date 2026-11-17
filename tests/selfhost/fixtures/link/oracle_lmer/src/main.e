// e.algo.stat.lmerpkg against lme4 lmer for one random intercept. tests/oracle/lmer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lmer`; the layout is at the top of scripts/r_oracle/groups/lmer.R.

use e.algo.stat.lmerpkg as lm
use e.io
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
    if which >= 1000usize {
        // Satterthwaite df of fixed effect (which - 1000) at lme4's (theta, sigma): args after the data are theta, sigma
        let th = z[5usize + n * p + 2usize * n]
        let sg = z[5usize + n * p + 2usize * n + 1usize]
        let (dfo, de) = mem.alloc[f64](a, p)
        if de != ok { ret nan }
        if lm.lmer_satt(a, z[5usize..5usize + n * p], z[5usize + n * p + n..5usize + n * p + 2usize * n], g, n, p, ng, reml, th, sg, dfo) != ok { ret nan }
        ret dfo[which - 1000usize]
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
