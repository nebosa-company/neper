// e.algo.stat.bridgesampling against bridgesampling: the normal-proposal bridge sampler.
// tests/oracle/bridgesampling.json comes from `R_ORACLE_LIB=<dir> Rscript
// scripts/r_oracle/generate.R bridgesampling`; the layout and the two log posteriors are at the top of
// scripts/r_oracle/groups/bridgesampling.R.

use e.algo.rand.r as rr
use e.algo.stat.bridgesampling as bs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn lp(id: *u8, th: []const f64) -> f64 {
    let k = *id
    if k == 0u8 {
        var mu: [5]f64 = zero
        var s2: [5]f64 = zero
        mu[0usize] = 1.0f64
        mu[1usize] = 0.0f64 - 2.0f64
        mu[2usize] = 0.5f64
        mu[3usize] = 3.0f64
        mu[4usize] = 0.0f64 - 1.0f64
        s2[0usize] = 1.0f64
        s2[1usize] = 4.0f64
        s2[2usize] = 0.25f64
        s2[3usize] = 2.0f64
        s2[4usize] = 1.0f64
        var s = 0.0f64
        var i = 0usize
        while i < th.len {
            s += (th[i] - mu[i]) * (th[i] - mu[i]) / s2[i]
            i += 1usize
        }
        ret 0.0f64 - 0.5f64 * s
    }
    let q = th[1usize] - 0.25f64 * th[0usize] * th[0usize]
    ret 0.0f64 - 0.5f64 * (th[0usize] * th[0usize] / 4.0f64 + q * q)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[0usize]))
    var id = u8(x[1usize])
    let n = usize(x[2usize])
    let p = usize(x[3usize])
    let (fit, e) = bs.bridge_normal[u8](a, &g, &id, lp, x[4usize..4usize + n * p], n, p, 1000i64)
    if e != ok { os.exit(6) }
    if str.eq(c.name, "logml") { ret fit.logml }
    ret f64(fit.niter)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bridgesampling.json")
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
