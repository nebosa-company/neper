// e.algo.stat.codadiag against coda: heidel.diag, the multivariate psrf, pcramer, autocorr and crosscorr.
// tests/oracle/coda2.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coda2`; the layout is at the top of scripts/r_oracle/groups/coda2.R.

use e.algo.stat.codadiag as cg
use e.algo.stat.codapkg as cd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "pc") { ret cg.pcramer(x[0usize]) }
    if str.eq(c.name, "mpsrf") {
        let nc = usize(x[0usize])
        let ni = usize(x[1usize])
        let nv = usize(x[2usize])
        ret cg.gelman_mpsrf(a, x[3usize..3usize + nc * ni * nv], nc, ni, nv)
    }
    if str.eq(c.name, "psrf_odd") || str.eq(c.name, "psrf_oddu") {
        let nchain = usize(x[0usize])
        let niter = usize(x[1usize])
        let (gp, gu) = cd.gelman_psrf(a, x[2usize..2usize + nchain * niter], nchain, niter, x[2usize + nchain * niter])
        if str.eq(c.name, "psrf_odd") { ret gp }
        ret gu
    }
    if str.eq(c.name, "ac") || str.eq(c.name, "cc") {
        let n = usize(x[0usize])
        let nv = usize(x[1usize])
        let at = 2usize + n * nv
        ret cg.acf_cross(x[2usize..at], n, nv, usize(x[at]), usize(x[at + 1usize]), usize(x[at + 2usize]))
    }
    let n = usize(x[0usize])
    var out: [6]f64 = zero
    if cg.heidel(a, x[1usize..1usize + n], x[1usize + n], x[2usize + n], out[0usize..6usize]) != ok { os.exit(7) }
    if str.eq(c.name, "hw_stest") { ret out[0usize] }
    if str.eq(c.name, "hw_start") { ret out[1usize] }
    if str.eq(c.name, "hw_p") { ret out[2usize] }
    if str.eq(c.name, "hw_htest") { ret out[3usize] }
    if str.eq(c.name, "hw_mean") { ret out[4usize] }
    ret out[5usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coda2.json")
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
