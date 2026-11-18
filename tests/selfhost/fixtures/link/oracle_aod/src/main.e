// e.algo.stat.aod against aod. tests/oracle/aod.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R aod`; the layout is at the top of scripts/r_oracle/groups/aod.R.

use e.algo.stat.aod as ad
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wald_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let q = usize(x[1usize])
    let p = usize(x[2usize])
    let b = x[3usize..3usize + p]
    let sg = x[3usize + p..3usize + p + p * p]
    let lm = x[3usize + p + p * p..3usize + p + p * p + q * p]
    let (w, e) = ad.wald_test(a, b, sg, lm, q, p)
    if e != ok { os.exit(6) }
    if x[0usize] == 0.0f64 { ret w.x2 }
    ret w.p
}

fn qpois_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let (o, e) = mem.alloc[f64](a, p + 1usize)
    if e != ok { os.exit(7) }
    let xm = x[4usize..4usize + n * p]
    let y = x[4usize + n * p..4usize + n * p + n]
    if ad.quasipois(a, xm, n, p, y, x[0usize] == 1.0f64, x[3usize], 0.001f64, o) != ok { os.exit(8) }
    ret o[usize(x[4usize + n * p + n])]
}

fn qbin_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let (o, e) = mem.alloc[f64](a, p + 1usize)
    if e != ok { os.exit(9) }
    let xm = x[4usize..4usize + n * p]
    let sc = x[4usize + n * p..4usize + n * p + n]
    let sz = x[4usize + n * p + n..4usize + n * p + 2usize * n]
    if ad.quasibin(a, xm, n, p, sc, sz, x[0usize] == 1.0f64, x[3usize], 0.001f64, o) != ok { os.exit(10) }
    ret o[usize(x[4usize + n * p + 2usize * n])]
}

fn bbin_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, p + 2usize)
    if e != ok { os.exit(11) }
    let xm = x[2usize..2usize + n * p]
    let sc = x[2usize + n * p..2usize + n * p + n]
    let sz = x[2usize + n * p + n..2usize + n * p + 2usize * n]
    let (code, be) = ad.betabin(a, xm, n, p, sc, sz, o)
    if be != ok || code != 0usize { os.exit(12) }
    let ix = usize(x[2usize + n * p + 2usize * n])
    if ix >= 4usize {
        let (se, e2) = mem.alloc[f64](a, p + 1usize)
        if e2 != ok { os.exit(16) }
        if !ad.betabin_se(a, xm, n, p, sc, sz, o[0usize..p + 1usize], se) { os.exit(17) }
        ret se[ix - 4usize]
    }
    ret o[ix]
}

fn nbin_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, p + 2usize)
    if e != ok { os.exit(13) }
    let (code, be) = ad.negbin(a, x[2usize..2usize + n * p], n, p, x[2usize + n * p..2usize + n * p + n], o)
    if be != ok || code != 0usize { os.exit(14) }
    let ix = usize(x[2usize + n * p + n])
    if ix >= 4usize {
        let (se, e2) = mem.alloc[f64](a, p + 1usize)
        if e2 != ok { os.exit(18) }
        if !ad.negbin_se(a, x[2usize..2usize + n * p], n, p, x[2usize + n * p..2usize + n * p + n], o[0usize..p + 1usize], se) { os.exit(19) }
        ret se[ix - 4usize]
    }
    ret o[ix]
}

fn split_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = usize(x[0usize])
    var tot = 0usize
    var i = 0usize
    while i < k {
        tot += usize(x[1usize + i])
        i += 1usize
    }
    let (o, e) = mem.alloc[f64](a, tot + 1usize)
    if e != ok { os.exit(15) }
    let m = ad.splitbin(x[1usize..1usize + k], x[1usize + k..1usize + 2usize * k], o)
    if x[1usize + 2usize * k] < 0.0f64 { ret f64(m) }
    ret o[usize(x[1usize + 2usize * k])]
}

fn grp_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let ng = usize(x[2usize])
    let (gp, ge) = mem.alloc[usize](a, n)
    let (o, oe) = mem.alloc[f64](a, p + ng + 1usize)
    if ge != ok || oe != ok { os.exit(24) }
    var q = 0usize
    while q < n {
        gp[q] = usize(x[3usize + q])
        q += 1usize
    }
    let xm = x[3usize + n..3usize + n + n * p]
    if str.eq(c.name, "bbing") {
        let sc = x[3usize + n + n * p..3usize + 2usize * n + n * p]
        let sz = x[3usize + 2usize * n + n * p..3usize + 3usize * n + n * p]
        let (code, be) = ad.betabin_g(a, xm, n, p, sc, sz, gp, ng, o)
        if be != ok || code != 0usize { os.exit(25) }
        ret o[usize(x[3usize + 3usize * n + n * p])]
    }
    let yy = x[3usize + n + n * p..3usize + 2usize * n + n * p]
    let (code, be) = ad.negbin_g(a, xm, n, p, yy, gp, ng, o)
    if be != ok || code != 0usize { os.exit(26) }
    ret o[usize(x[3usize + 2usize * n + n * p])]
}

fn anova_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (o, e) = mem.alloc[f64](a, 3usize)
    if e != ok { os.exit(27) }
    ad.lr_anova(x[0usize], usize(x[1usize]), x[2usize], usize(x[3usize]), o)
    ret o[usize(x[4usize])]
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = usize(x[3usize])
    let n = x[4usize..4usize + k]
    let y = x[4usize + k..4usize + 2usize * k]
    if str.eq(c.name, "iccbin") { ret ad.iccbin_c(n, y) }
    if str.eq(c.name, "donner") {
        let grp = x[4usize + 2usize * k..4usize + 3usize * k]
        let r = ad.donner(n, y, grp, usize(x[4usize + 3usize * k]))
        if x[0usize] == 0.0f64 { ret r.rho }
        ret r.x2
    }
    ret ad.varbin(n, y, x[2usize], usize(x[0usize]), usize(x[1usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/aod.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64
        if str.eq(c.name, "wald") { got = wald_answer(a, c) } else if str.eq(c.name, "qpois") { got = qpois_answer(a, c) } else if str.eq(c.name, "qbin") { got = qbin_answer(a, c) } else if str.eq(c.name, "bbin") { got = bbin_answer(a, c) } else if str.eq(c.name, "bbing") || str.eq(c.name, "nbing") { got = grp_answer(a, c) } else if str.eq(c.name, "anova") { got = anova_answer(a, c) } else if str.eq(c.name, "nbin") { got = nbin_answer(a, c) } else if str.eq(c.name, "splitbin") { got = split_answer(a, c) } else { got = answer(c) }
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
