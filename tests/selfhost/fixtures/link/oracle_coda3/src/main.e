// e.algo.stat.codadiag against coda: batchSE, summary.mcmc, gelman.diag(transform = TRUE), effectiveSize over chains.
// tests/oracle/coda3.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coda3`; the layout is at the top of scripts/r_oracle/groups/coda3.R.

use e.algo.stat.codadiag as cg
use e.algo.stat.codapkg as cd
use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "gtp") || str.eq(c.name, "gtu") || str.eq(c.name, "ess_multi") {
        let nchain = usize(x[0usize])
        let niter = usize(x[1usize])
        let (d, e) = mem.alloc[f64](a, nchain * niter)
        if e != ok { os.exit(4) }
        var i = 0usize
        while i < nchain * niter {
            d[i] = x[2usize + i]
            i += 1usize
        }
        if str.eq(c.name, "ess_multi") {
            var tot = 0.0f64
            var k = 0usize
            while k < nchain {
                tot += cd.effective_size(a, d[k * niter..(k + 1usize) * niter])
                k += 1usize
            }
            ret tot
        }
        cg.gelman_transform(d)
        let (gp, gu) = cd.gelman_psrf(a, d, nchain, niter, x[2usize + nchain * niter])
        if str.eq(c.name, "gtp") { ret gp }
        ret gu
    }
    let n = usize(x[0usize])
    let s = x[1usize..1usize + n]
    if str.eq(c.name, "bse") { ret cg.batch_se(s, usize(x[1usize + n])) }
    if str.eq(c.name, "sm_q") {
        let (srt, e) = mem.alloc[f64](a, n)
        if e != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            srt[i] = s[i]
            i += 1usize
        }
        i = 1usize
        while i < n {
            let t = srt[i]
            var j = i
            while j > 0usize && srt[j - 1usize] > t {
                srt[j] = srt[j - 1usize]
                j -= 1usize
            }
            srt[j] = t
            i += 1usize
        }
        ret ms.quant7(srt, x[1usize + n])
    }
    var out: [4]f64 = zero
    if cg.mcmc_summary(a, s, out[0usize..4usize]) != ok { os.exit(6) }
    if str.eq(c.name, "sm_mean") { ret out[0usize] }
    if str.eq(c.name, "sm_sd") { ret out[1usize] }
    if str.eq(c.name, "sm_nse") { ret out[2usize] }
    ret out[3usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coda3.json")
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
