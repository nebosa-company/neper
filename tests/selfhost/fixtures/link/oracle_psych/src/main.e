// e.algo.stat.psych against psych: alpha, KMO, cortest.bartlett, ICC, cohen.kappa, mardia.
// tests/oracle/psych.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R psych`; the layout is
// at the top of scripts/r_oracle/groups/psych.R.

use e.algo.stat.psych as ps
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "ctest") {
        let cn = usize(x[0usize])
        let cp = usize(x[1usize])
        ret ps.corr_test(a, x[2usize..2usize + cn * cp], cn, cp, usize(x[2usize + cn * cp]), usize(x[3usize + cn * cp]), usize(x[4usize + cn * cp]))
    }
    if str.eq(c.name, "yule") { ret ps.yule(x[0usize..4usize], false) }
    if str.eq(c.name, "yuleY") { ret ps.yule(x[0usize..4usize], true) }
    if str.eq(c.name, "phi") { ret ps.phi(x[0usize..4usize]) }
    if str.eq(c.name, "tetra") {
        var to: [3]f64 = zero
        ps.tetrachoric(x[0usize..4usize], 0.5f64, to[0usize..3usize])
        ret to[usize(x[4usize])]
    }
    if str.eq(c.name, "tetrap") {
        let tn = usize(x[0usize])
        ret ps.tetrachoric_pair(x[1usize..1usize + tn], x[1usize + tn..1usize + 2usize * tn], 0.5f64)
    }
    if str.eq(c.name, "polyp") {
        let pn = usize(x[0usize])
        ret ps.polychoric_pair(x[2usize..2usize + pn], x[2usize + pn..2usize + 2usize * pn], usize(x[1usize]))
    }
    if str.eq(c.name, "pcav") {
        let vp = usize(x[0usize])
        let vf = usize(x[1usize])
        let (vo, ve) = mem.alloc[f64](a, vp * vf + vf * vf)
        if ve != ok { ret 0.0f64 / 0.0f64 }
        if ps.principal_varimax(a, x[2usize..2usize + vp * vp], vp, vf, vo) != ok { ret 0.0f64 / 0.0f64 }
        ret vo[usize(x[2usize + vp * vp])]
    }
    if str.eq(c.name, "score") {
        let sn = usize(x[0usize])
        let sp = usize(x[1usize])
        let sS = usize(x[2usize])
        let (so, se) = mem.alloc[f64](a, sn * sS + 3usize * sS + sS * sS)
        if se != ok { ret 0.0f64 / 0.0f64 }
        let xs = x[5usize..5usize + sn * sp]
        let ks = x[5usize + sn * sp..5usize + sn * sp + sp * sS]
        if ps.score_items(a, xs, sn, sp, ks, sS, x[3usize], x[4usize], so) != ok { ret 0.0f64 / 0.0f64 }
        ret so[usize(x[5usize + sn * sp + sp * sS])]
    }
    if str.eq(c.name, "fapa") {
        let fp = usize(x[0usize])
        let ff = usize(x[1usize])
        let (fo, fe) = mem.alloc[f64](a, fp * ff + fp)
        if fe != ok { ret 0.0f64 / 0.0f64 }
        if ps.fa_pa(a, x[2usize..2usize + fp * fp], fp, ff, fo) != ok { ret 0.0f64 / 0.0f64 }
        ret fo[usize(x[2usize + fp * fp])]
    }
    if str.eq(c.name, "pca") {
        let pp = usize(x[0usize])
        let nf = usize(x[1usize])
        let (po, pe) = mem.alloc[f64](a, pp * nf + 2usize * pp)
        if pe != ok { ret 0.0f64 / 0.0f64 }
        if ps.principal(a, x[2usize..2usize + pp * pp], pp, nf, po) != ok { ret 0.0f64 / 0.0f64 }
        ret po[usize(x[2usize + pp * pp])]
    }
    if str.eq(c.name, "bis") {
        let bn = usize(x[0usize])
        ret ps.biserial(x[1usize..1usize + bn], x[1usize + bn..1usize + 2usize * bn])
    }
    if str.eq(c.name, "descby") {
        let dn = usize(x[0usize])
        let grp = usize(x[1usize + 2usize * dn])
        let (sub, se) = mem.alloc[f64](a, dn)
        if se != ok { ret 0.0f64 / 0.0f64 }
        var cnt = 0usize
        var ii = 0usize
        while ii < dn {
            if usize(x[1usize + dn + ii]) == grp {
                sub[cnt] = x[1usize + ii]
                cnt += 1usize
            }
            ii += 1usize
        }
        ret ps.describe(a, sub[0usize..cnt], usize(x[2usize + 2usize * dn]))
    }
    if str.eq(c.name, "desc") {
        let dn = usize(x[0usize])
        ret ps.describe(a, x[1usize..1usize + dn], usize(x[1usize + dn]))
    }
    if str.eq(c.name, "kappa") {
        let k = usize(x[0usize])
        ret ps.kappa(x[1usize..1usize + k * k], k)
    }
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let xm = x[2usize..2usize + n * p]
    let q = usize(x[2usize + n * p])
    if str.eq(c.name, "alpha_raw") || str.eq(c.name, "alpha_std") {
        let (r, s) = ps.alpha(xm, n, p)
        if str.eq(c.name, "alpha_raw") { ret r }
        ret s
    }
    if str.eq(c.name, "mardia_b1") || str.eq(c.name, "mardia_b2") {
        let (b1, b2, me) = ps.mardia(a, xm, n, p)
        if me != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "mardia_b1") { ret b1 }
        ret b2
    }
    if str.starts_with(c.name, "icc") {
        let (o, oe) = mem.alloc[f64](a, 6usize)
        if oe != ok { ret 0.0f64 / 0.0f64 }
        ps.icc(xm, n, p, o)
        ret o[usize(c.name[3usize]) - 49usize]
    }
    let (r, re) = ps.corr(a, xm, n, p)
    if re != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "bart_chi") || str.eq(c.name, "bart_df") {
        let (chi, df) = ps.bartlett(a, r, p, f64(n))
        if str.eq(c.name, "bart_chi") { ret chi }
        ret df
    }
    let (msa, me) = mem.alloc[f64](a, p)
    if me != ok { ret 0.0f64 / 0.0f64 }
    let (all, ke) = ps.kmo(a, r, p, msa)
    if ke != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "kmo") { ret all }
    ret msa[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/psych.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
