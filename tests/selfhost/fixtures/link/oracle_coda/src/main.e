// e.algo.stat.codapkg against coda. tests/oracle/coda.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coda`; the layout is at the top of scripts/r_oracle/groups/coda.R.

use e.algo.stat.codapkg as cd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "gz") { ret cd.geweke_z(a, x[1usize..1usize + usize(x[0usize])], x[1usize + usize(x[0usize])], x[2usize + usize(x[0usize])]) }
    if str.eq(c.name, "gp") || str.eq(c.name, "gu") {
        let nchain = usize(x[0usize])
        let niter = usize(x[1usize])
        let (gp, gu) = cd.gelman_psrf(a, x[2usize..2usize + nchain * niter], nchain, niter, x[2usize + nchain * niter])
        if str.eq(c.name, "gp") { ret gp }
        ret gu
    }
    if str.eq(c.name, "hl") || str.eq(c.name, "hu") {
        let (hl, hu) = cd.hpd(a, x[1usize..1usize + usize(x[0usize])], x[1usize + usize(x[0usize])])
        if str.eq(c.name, "hl") { ret hl }
        ret hu
    }
    if str.eq(c.name, "rf_m") || str.eq(c.name, "rf_n") || str.eq(c.name, "rf_nmin") || str.eq(c.name, "rf_i") {
        let rn = usize(x[0usize])
        let (rm, rnn, rmin, ri, re) = cd.raftery(a, x[1usize..1usize + rn], x[1usize + rn], x[2usize + rn], x[3usize + rn], 0.001f64)
        if re != ok { os.exit(8) }
        if str.eq(c.name, "rf_m") { ret rm }
        if str.eq(c.name, "rf_n") { ret rnn }
        if str.eq(c.name, "rf_nmin") { ret rmin }
        ret ri
    }
    let n = usize(x[0usize])
    let s = x[1usize..1usize + n]
    let lm = usize(x[1usize + n])
    if str.eq(c.name, "ess") { ret cd.effective_size(a, s) }
    if str.eq(c.name, "acf_sum") {
        let (o, e) = mem.alloc[f64](a, lm + 1usize)
        if e != ok { os.exit(5) }
        cd.acf(s, lm, o)
        var t = 0.0f64
        var i = 0usize
        while i <= lm {
            t += f64(i + 1usize) * o[i]
            i += 1usize
        }
        ret t
    }
    let (ord, sm, vp, e2) = cd.ar_yw(a, s)
    if e2 != ok { os.exit(6) }
    if str.eq(c.name, "ar_order") { ret f64(ord) }
    ret vp / ((1.0f64 - sm) * (1.0f64 - sm))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coda.json")
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
