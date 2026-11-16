// e.algo.stat.normem against norm: em.norm and loglik.norm. tests/oracle/norm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R norm`; the layout is at the top of
// scripts/r_oracle/groups/norm.R.

use e.algo.stat.normda as nd
use e.algo.stat.normem as nm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "mi") {
        let mm = usize(z[0usize])
        let (ev, e5) = mem.alloc[f64](a, mm)
        let (sv, e6) = mem.alloc[f64](a, mm)
        let (ov, e7) = mem.alloc[f64](a, 8usize)
        if e5 != ok || e6 != ok || e7 != ok { ret 0.0f64 / 0.0f64 }
        let qq = usize(z[2usize + 4usize * mm])
        var k = 0usize
        while k < mm {
            ev[k] = z[2usize + k * 2usize + qq]
            sv[k] = z[2usize + 2usize * mm + k * 2usize + qq]
            k += 1usize
        }
        nm.mi_inference(ev, sv, z[1usize], ov)
        ret ov[usize(z[3usize + 4usize * mm])]
    }
    if str.eq(c.name, "mda") {
        let mn = usize(z[0usize])
        let mp = usize(z[1usize])
        let md = (mp + 1usize) * (mp + 2usize) / 2usize
        var mr: nd.Rn = zero
        nd.rngseed(&mr, i64(z[2usize]))
        let (mth, em1) = mem.alloc[f64](a, md)
        if em1 != ok { ret 0.0f64 / 0.0f64 }
        var mj = 0usize
        while mj < md {
            mth[mj] = z[4usize + mj]
            mj += 1usize
        }
        let me = nd.mda_norm(a, &mr, z[4usize + md..4usize + md + mn * mp], mn, mp, mth, usize(z[3usize]))
        if me != ok { ret 0.0f64 / 0.0f64 }
        ret mth[usize(z[4usize + md + mn * mp])]
    }
    if str.eq(c.name, "gp") || str.eq(c.name, "mp") {
        let gn = usize(z[0usize])
        let gpp = usize(z[1usize])
        let gd = (gpp + 1usize) * (gpp + 2usize) / 2usize
        let (pre, ep) = nd.prelim(a, z[2usize + gd..2usize + gd + gn * gpp], gn, gpp)
        if str.eq(c.name, "mp") {
            let (pre2, ep2) = nd.prelim(a, z[2usize + gpp + gpp * gpp..2usize + gpp + gpp * gpp + gn * gpp], gn, gpp)
            let (pk2, ek2) = nd.mkpsi(a, gpp)
            let (mo, eo2) = mem.alloc[f64](a, gd)
            if ep2 != ok || ek2 != ok || eo2 != ok { ret 0.0f64 / 0.0f64 }
            nd.makeparam(&pk2, z[2usize..2usize + gpp], z[2usize + gpp..2usize + gpp + gpp * gpp], pre2.xbar, pre2.sdv, mo)
            ret mo[usize(z[2usize + gpp + gpp * gpp + gn * gpp])]
        }
        let (pk, ek) = nd.mkpsi(a, gpp)
        let (gm, eg1) = mem.alloc[f64](a, gpp)
        let (gs, eg2) = mem.alloc[f64](a, gpp * gpp)
        if ep != ok || ek != ok || eg1 != ok || eg2 != ok { ret 0.0f64 / 0.0f64 }
        nd.getparam(&pk, z[2usize..2usize + gd], pre.xbar, pre.sdv, gm, gs)
        let gq = usize(z[2usize + gd + gn * gpp])
        if gq < gpp { ret gm[gq] }
        ret gs[gq - gpp]
    }
    if str.eq(c.name, "niw") {
        let wp = usize(z[0usize])
        let wd = (wp + 1usize) * (wp + 2usize) / 2usize
        var wr: nd.Rn = zero
        nd.rngseed(&wr, i64(z[1usize]))
        let (wo, ew) = mem.alloc[f64](a, wd)
        if ew != ok { ret 0.0f64 / 0.0f64 }
        let we = nd.ninvwish(a, &wr, wp, z[2usize], z[3usize], z[4usize..4usize + wp], z[4usize + wp..4usize + wp + wp * wp], wo)
        if we != ok { ret 0.0f64 / 0.0f64 }
        ret wo[usize(z[4usize + wp + wp * wp])]
    }
    if str.eq(c.name, "imp") || str.eq(c.name, "da") {
        let dn = usize(z[0usize])
        let dp = usize(z[1usize])
        let dd = (dp + 1usize) * (dp + 2usize) / 2usize
        var rn: nd.Rn = zero
        nd.rngseed(&rn, i64(z[2usize]))
        if str.eq(c.name, "imp") {
            let (out, eo) = mem.alloc[f64](a, dn * dp)
            if eo != ok { ret 0.0f64 / 0.0f64 }
            let ie = nd.imp_norm(a, &rn, z[3usize + dd..3usize + dd + dn * dp], dn, dp, z[3usize..3usize + dd], out)
            if ie != ok { ret 0.0f64 / 0.0f64 }
            ret out[usize(z[3usize + dd + dn * dp])]
        }
        let (st, es) = mem.alloc[f64](a, dd)
        if es != ok { ret 0.0f64 / 0.0f64 }
        let b = 4usize + 2usize + dp + dp * dp
        var j = 0usize
        while j < dd {
            st[j] = z[b + j]
            j += 1usize
        }
        let de = nd.da_norm(a, &rn, z[b + dd..b + dd + dn * dp], dn, dp, st, usize(z[3usize]), z[4usize], z[5usize], z[6usize..6usize + dp], z[6usize + dp..6usize + dp + dp * dp])
        if de != ok { ret 0.0f64 / 0.0f64 }
        ret st[usize(z[b + dd + dn * dp])]
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let x = z[3usize..3usize + n * p]
    if str.eq(c.name, "emp") {
        let (qm, eq1) = mem.alloc[f64](a, p)
        let (qs, eq2) = mem.alloc[f64](a, p * p)
        if eq1 != ok || eq2 != ok { ret 0.0f64 / 0.0f64 }
        let b = 3usize + n * p
        let pri = nm.Prior { mle: false, tau: z[b], m: z[b + 1usize], mu0: z[b + 2usize..b + 2usize + p], lambdainv: z[b + 2usize + p..b + 2usize + p + p * p] }
        let (qit, qe) = nm.em_norm_prior(a, x, n, p, z[2usize], 1000usize, qm, qs, &pri)
        if qe != ok { ret 0.0f64 / 0.0f64 }
        let qq = usize(z[b + 2usize + p + p * p])
        if qq < p { ret qm[qq] }
        ret qs[qq - p]
    }
    if str.eq(c.name, "post") {
        let (pm, ep1) = mem.alloc[f64](a, p)
        let (ps2, ep2) = mem.alloc[f64](a, p * p)
        if ep1 != ok || ep2 != ok { ret 0.0f64 / 0.0f64 }
        let (pit, pe) = nm.em_norm(a, x, n, p, 0.0001f64, 1000usize, pm, ps2)
        if pe != ok { ret 0.0f64 / 0.0f64 }
        let b = 3usize + n * p
        let (lp, lpe) = nm.logpost_norm(a, x, n, p, pm, ps2, z[b], z[b + 1usize], z[b + 2usize..b + 2usize + p], z[b + 2usize + p..b + 2usize + p + p * p])
        if lpe != ok { ret 0.0f64 / 0.0f64 }
        ret lp
    }
    let q = usize(z[3usize + n * p])
    let (mu, e1) = mem.alloc[f64](a, p)
    let (sg, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let (it, e) = nm.em_norm(a, x, n, p, z[2usize], 1000usize, mu, sg)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if q < p { ret mu[q] }
    if q < p + p * p { ret sg[q - p] }
    let (ll, le) = nm.loglik_norm(a, x, n, p, mu, sg)
    if le != ok { ret 0.0f64 / 0.0f64 }
    ret ll
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/norm.json")
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
