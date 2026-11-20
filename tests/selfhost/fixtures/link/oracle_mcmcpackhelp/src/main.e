// e.algo.stat.mcmcpackhelp against MCbinomialbeta, MCpoissongamma, MCnormalnormal, MCmultinomdirichlet, BayesFactor and PostProbMod.
// tests/oracle/mcmcpackhelp.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackhelp`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackhelp.R.

use e.algo.rand.r as rng
use e.algo.stat.mcmcpackhelp as mh
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(m: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m.len {
        s += f64(i + 1usize) * m[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "bfmat") {
        let m = z.len
        let (bf, e1) = mem.alloc[f64](a, m * m)
        let (lb, e2) = mem.alloc[f64](a, m * m)
        if e1 != ok || e2 != ok { ret nan }
        mh.bayes_factor(z, bf, lb)
        ret wsum(bf) + wsum(lb)
    }
    if str.eq(c.name, "sumx") {
        let (o, e1) = mem.alloc[f64](a, 9usize)
        if e1 != ok || mh.summary_mcmc(a, z, o) != ok { ret nan }
        ret wsum(o)
    }
    if str.eq(c.name, "hpd") {
        let (o, e1) = mem.alloc[f64](a, 2usize)
        if e1 != ok || mh.hpd_interval(a, z[1usize..z.len], z[0usize], o) != ok { ret nan }
        ret wsum(o)
    }
    if str.eq(c.name, "ppm") {
        let m = usize(z[0usize])
        let np = usize(z[1usize])
        let (out, e1) = mem.alloc[f64](a, m)
        if e1 != ok { ret nan }
        mh.post_prob_mod(z[2usize + np..2usize + np + m], z[2usize..2usize + np], out)
        ret wsum(out)
    }
    var r: rng.Rng = zero
    rng.seed(&r, i64(z[0usize]))
    let mc = usize(z[1usize])
    if str.eq(c.name, "mcmd") {
        let d = usize(z[2usize])
        let (ya, e1) = mem.alloc[f64](a, d)
        let (out, e2) = mem.alloc[f64](a, mc * d)
        if e1 != ok || e2 != ok { ret nan }
        mh.mc_multinomdirichlet(&r, z[3usize..3usize + d], z[3usize + d..3usize + 2usize * d], mc, ya, out)
        ret wsum(out)
    }
    let (out, e3) = mem.alloc[f64](a, mc)
    if e3 != ok { ret nan }
    if str.eq(c.name, "mcbb") {
        let m = usize(z[4usize])
        mh.mc_binomialbeta(&r, z[5usize..5usize + m], z[5usize + m..5usize + 2usize * m], z[2usize], z[3usize], mc, out)
    }
    if str.eq(c.name, "mcpg") { mh.mc_poissongamma(&r, z[4usize..z.len], z[2usize], z[3usize], mc, out) }
    if str.eq(c.name, "mcnn") { mh.mc_normalnormal(&r, z[5usize..z.len], z[2usize], z[3usize], z[4usize], mc, out) }
    ret wsum(out)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackhelp.json")
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
