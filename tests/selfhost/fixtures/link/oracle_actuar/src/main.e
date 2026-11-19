// e.algo.stat.actuar against actuar. tests/oracle/actuar.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R actuar`;
// the layout is at the top of scripts/r_oracle/groups/actuar.R.

use e.algo.stat.actuar as ac
use e.io
use e.math
use e.mem
use e.os
use e.algo.rand.r as rr
use e.str
use e.test.oracle as oracle

fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "gg") {
        let rg = usize(x[0usize])
        let st = usize(x[2usize + 2usize * rg])
        let av = x[2usize + 2usize * rg + 1usize]
        let cjg = x[1usize..1usize + rg + 1usize]
        let njg = x[2usize + rg..2usize + 2usize * rg]
        if st == 0usize { ret ac.grouped_ogive(cjg, njg, av) }
        if st == 1usize { ret ac.grouped_emm(cjg, njg, av) }
        ret ac.grouped_elev(cjg, njg, av)
    }
    if str.eq(c.name, "an") { ret ac.agg_normal(x[2usize], x[0usize], x[1usize]) }
    if str.eq(c.name, "ap") { ret ac.agg_npower(x[3usize], x[0usize], x[1usize], x[2usize]) }
    if str.eq(c.name, "cv") {
        let mc = usize(x[0usize])
        let npc = usize(x[1usize + mc])
        let nnc = usize(x[2usize + mc + npc])
        var fsc: [64]f64 = zero
        var wk: [128]f64 = zero
        ac.aggregate_convolution(x[2usize + mc..2usize + mc + npc], x[1usize..1usize + mc], nnc, fsc[0usize..64usize], wk[0usize..128usize])
        var run = 0.0f64
        var sm = 0.0f64
        var j = 0usize
        while j <= nnc {
            run += fsc[j]
            sm += run * f64(j + 1usize)
            j += 1usize
        }
        if usize(x[3usize + mc + npc]) == 0usize { ret run }
        ret sm
    }
    if str.eq(c.name, "dz") {
        let nd = usize(x[1usize])
        var dv: [64]f64 = zero
        let cnt = ac.discretize_cdf(usize(x[0usize]), x[2usize..2usize + 2usize * nd + 1usize], nd, dv[0usize..64usize])
        if usize(x[3usize + 2usize * nd]) == 0usize { ret f64(cnt) }
        var sd = 0.0f64
        var k = 0usize
        while k < cnt {
            sd += dv[k] * f64(k + 1usize)
            k += 1usize
        }
        ret sd
    }
    if str.eq(c.name, "du") {
        let nd = usize(x[0usize])
        var dv: [64]f64 = zero
        let cnt = ac.discretize_unbiased(x[4usize..5usize + nd], nd, x[1usize], x[2usize], x[3usize], dv[0usize..64usize])
        if usize(x[5usize + nd]) == 0usize { ret dv[0usize] }
        var sd = 0.0f64
        var k = 0usize
        while k < cnt {
            sd += dv[k] * f64(k + 1usize)
            k += 1usize
        }
        ret sd
    }
    if str.eq(c.name, "cm") {
        let ni = usize(x[0usize])
        var nsv: [16]usize = zero
        var tot = 0usize
        var q = 0usize
        while q < ni {
            nsv[q] = usize(x[1usize + q])
            tot += nsv[q]
            q += 1usize
        }
        var ov: [4]f64 = zero
        ac.cm_buhlmann_straub(nsv[0usize..ni], x[1usize + ni..1usize + ni + tot], x[1usize + ni + tot..1usize + ni + 2usize * tot], ov[0usize..4usize])
        let st = usize(x[1usize + ni + 2usize * tot])
        if st < 4usize { ret ov[st] }
        var w0 = 0.0f64
        q = 0usize
        while q < nsv[0usize] {
            w0 += x[1usize + ni + tot + q]
            q += 1usize
        }
        ret w0 / (w0 + ov[2usize])
    }
    if str.eq(c.name, "rx") { ret ac.ruin_exp_exp(x[3usize], x[0usize], x[1usize], x[2usize]) }
    if str.eq(c.name, "ph") {
        let mp = usize(x[0usize])
        let (dd, sv) = ac.ph_dens_surv(ar, x[1usize..1usize + mp], x[1usize + mp..1usize + mp + mp * mp], mp, x[1usize + mp + mp * mp])
        if usize(x[2usize + mp + mp * mp]) == 0usize { ret dd }
        ret sv
    }
    if str.eq(c.name, "pm") {
        let mq = usize(x[0usize])
        ret ac.ph_moment(ar, x[1usize..1usize + mq], x[1usize + mq..1usize + mq + mq * mq], mq, usize(x[1usize + mq + mq * mq]))
    }
    if str.eq(c.name, "lf") {
        let kd = usize(x[0usize])
        let sg = usize(x[4usize])
        if kd == 0usize {
            if sg == 0usize { ret ac.lg_d(x[3usize], x[1usize], x[2usize]) }
            if sg == 1usize { ret ac.lg_p(x[3usize], x[1usize], x[2usize]) }
            if sg == 2usize { ret ac.lg_q(x[3usize], x[1usize], x[2usize]) }
            ret ac.lg_m(x[3usize], x[1usize], x[2usize])
        }
        if sg == 0usize { ret ac.gu_d(x[3usize], x[1usize], x[2usize]) }
        if sg == 1usize { ret ac.gu_p(x[3usize], x[1usize], x[2usize]) }
        ret ac.gu_q(x[3usize], x[1usize], x[2usize])
    }
    if str.eq(c.name, "zc") {
        let kz = usize(x[0usize])
        let sz = usize(x[5usize])
        if sz == 0usize { ret ac.zt_d(kz, x[4usize], x[1usize], x[2usize]) }
        if sz == 1usize { ret ac.zt_p(kz, x[4usize], x[1usize], x[2usize]) }
        if sz == 2usize { ret ac.zm_d(kz, x[4usize], x[1usize], x[2usize], x[3usize]) }
        ret ac.zm_p(kz, x[4usize], x[1usize], x[2usize], x[3usize])
    }
    if str.eq(c.name, "ig") {
        let ki = usize(x[0usize])
        let si = usize(x[4usize])
        if ki == 0usize {
            if si == 0usize { ret ac.ig_d(x[3usize], x[1usize], x[2usize]) }
            ret ac.ig_p(x[3usize], x[1usize], x[2usize])
        }
        if si == 0usize { ret ac.logd_d(x[3usize], x[1usize]) }
        ret ac.logd_p(x[3usize], x[1usize])
    }
    if str.eq(c.name, "gb") {
        let sb = usize(x[5usize])
        if sb == 0usize { ret ac.gb_d(x[4usize], x[0usize], x[1usize], x[2usize], x[3usize]) }
        if sb == 1usize { ret ac.gb_p(x[4usize], x[0usize], x[1usize], x[2usize], x[3usize]) }
        if sb == 2usize { ret ac.gb_q(x[4usize], x[0usize], x[1usize], x[2usize], x[3usize]) }
        ret ac.gb_m(x[4usize], x[0usize], x[1usize], x[2usize], x[3usize])
    }
    if str.eq(c.name, "lm") {
        if usize(x[0usize]) == 0usize { ret ac.lg_lev(x[3usize], x[4usize], x[1usize], x[2usize]) }
        ret ac.ig_m(usize(x[4usize]), x[1usize], x[2usize])
    }
    if str.eq(c.name, "gl") {
        if usize(x[0usize]) == 0usize { ret ac.gb_lev(x[5usize], x[6usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
        ret ac.gu_m(usize(x[6usize]), x[1usize], x[2usize])
    }
    if str.eq(c.name, "zq") {
        let kq = usize(x[0usize])
        if usize(x[5usize]) == 0usize { ret ac.zt_q(kq, x[4usize], x[1usize], x[2usize]) }
        ret ac.zm_q(kq, x[4usize], x[1usize], x[2usize], x[3usize])
    }
    if str.eq(c.name, "iq") { ret ac.ig_q(x[2usize], x[0usize], x[1usize]) }
    if str.eq(c.name, "rg") {
        var gg: rr.Rng = zero
        rr.seed(&gg, i64(x[0usize]))
        let nr = usize(x[6usize])
        var tr = 0.0f64
        var ir = 0usize
        while ir < nr {
            tr += ac.rand_draw(&gg, usize(x[1usize]), x[2usize], x[3usize], x[4usize], x[5usize]) * f64(ir + 1usize)
            ir += 1usize
        }
        ret tr
    }
    if str.eq(c.name, "rp") {
        let mr = usize(x[0usize])
        ret ac.ruin_ph_exp(ar, x[1usize..1usize + mr], x[1usize + mr..1usize + mr + mr * mr], mr, x[3usize + mr + mr * mr], x[1usize + mr + mr * mr], x[2usize + mr + mr * mr])
    }
    if str.eq(c.name, "rc") {
        var gc: rr.Rng = zero
        rr.seed(&gc, i64(x[0usize]))
        let nc = usize(x[4usize])
        var tc = 0.0f64
        var ic = 0usize
        while ic < nc {
            var pa = x[2usize]
            var pb = x[3usize]
            if usize(x[1usize]) == 4usize { pa = x[3usize] }
            tc += ac.rand_count(&gc, usize(x[1usize]), pa, pb) * f64(ic + 1usize)
            ic += 1usize
        }
        ret tc
    }
    if str.eq(c.name, "rt") {
        var gt: rr.Rng = zero
        rr.seed(&gt, i64(x[0usize]))
        let nt = usize(x[5usize])
        var tt = 0.0f64
        var it = 0usize
        while it < nt {
            tt += ac.rand_tb(&gt, u8(x[1usize]), x[2usize], x[3usize], x[4usize]) * f64(it + 1usize)
            it += 1usize
        }
        ret tt
    }
    if str.eq(c.name, "by") {
        let nb2 = usize(x[4usize])
        var bo: [5]f64 = zero
        ac.bayes_linear(usize(x[0usize]), x[1usize], x[2usize], x[3usize], x[5usize..5usize + nb2], bo[0usize..5usize])
        ret bo[usize(x[5usize + nb2])]
    }
    if str.eq(c.name, "rcp") {
        var gr: rr.Rng = zero
        rr.seed(&gr, i64(x[0usize]))
        let nrc = usize(x[1usize])
        let (agg, ae) = mem.alloc[f64](ar, nrc)
        if ae != ok { os.exit(30) }
        let re2 = ac.rcompound_pois_gamma(ar, &gr, nrc, x[2usize], x[3usize], x[4usize], agg)
        if re2 != ok { os.exit(31) }
        let wr2 = usize(x[5usize])
        var mean = 0.0f64
        var ws = 0.0f64
        var q = 0usize
        while q < nrc {
            mean += agg[q]
            ws += agg[q] * f64(q + 1usize)
            q += 1usize
        }
        mean = mean / f64(nrc)
        if wr2 == 0usize { ret ws }
        var thr = mean
        if wr2 == 2usize {
            var srt = 0usize
            let (cp, ce3) = mem.alloc[f64](ar, nrc)
            if ce3 != ok { os.exit(32) }
            while srt < nrc {
                cp[srt] = agg[srt]
                srt += 1usize
            }
            var ii = 1usize
            while ii < nrc {
                let v = cp[ii]
                var jj = ii
                while jj > 0usize && cp[jj - 1usize] > v {
                    cp[jj] = cp[jj - 1usize]
                    jj -= 1usize
                }
                cp[jj] = v
                ii += 1usize
            }
            let h = 0.75f64 * f64(nrc - 1usize)
            let lo = usize(math.floor[f64](h))
            let fr = h - f64(lo)
            thr = cp[lo]
            if lo + 1usize < nrc { thr = cp[lo] + fr * (cp[lo + 1usize] - cp[lo]) }
        }
        var le = 0usize
        q = 0usize
        while q < nrc {
            if agg[q] <= thr { le += 1usize }
            q += 1usize
        }
        ret f64(le) / f64(nrc)
    }
    if str.eq(c.name, "pj") {
        let m = usize(x[3usize])
        let nn = usize(x[4usize + m])
        var fs: [64]f64 = zero
        ac.panjer(usize(x[0usize]), x[1usize], x[2usize], x[4usize..4usize + m], nn, fs[0usize..64usize])
        if usize(x[5usize + m]) == 0usize {
            var tot = 0.0f64
            var i = 0usize
            while i <= nn {
                tot += fs[i]
                i += 1usize
            }
            ret tot
        }
        var run = 0.0f64
        var sm = 0.0f64
        var j = 0usize
        while j <= nn {
            run += fs[j]
            sm += run * f64(j + 1usize)
            j += 1usize
        }
        ret sm
    }
    let fam = u8(x[0usize])
    let kind = u8(x[1usize])
    let s1 = x[2usize]
    let s2 = x[3usize]
    let s3 = x[4usize]
    let sc = x[5usize]
    let v = x[6usize]
    let k = x[7usize]
    let nm = c.name
    if fam == 0u8 {
        let (a, g, t) = ac.tb_params(kind, s1, s2, s3)
        if str.eq(nm, "d") { ret ac.tb_d(v, a, g, t, sc) }
        if str.eq(nm, "p") { ret ac.tb_p(v, a, g, t, sc) }
        if str.eq(nm, "q") { ret ac.tb_q(v, a, g, t, sc) }
        if str.eq(nm, "m") { ret ac.tb_m(k, a, g, t, sc) }
        ret ac.tb_lev(v, k, a, g, t, sc)
    }
    if fam == 1u8 {
        if str.eq(nm, "d") { ret ac.tg_d(v, s1, s2, sc) }
        if str.eq(nm, "p") { ret ac.tg_p(v, s1, s2, sc) }
        if str.eq(nm, "q") { ret ac.tg_q(v, s1, s2, sc) }
        if str.eq(nm, "m") { ret ac.tg_m(k, s1, s2, sc) }
        ret ac.tg_lev(v, k, s1, s2, sc)
    }
    if fam == 2u8 {
        var a = s1
        var t = s2
        if kind == 1u8 {
            a = s1
            t = 1.0f64
        }
        if kind == 2u8 {
            a = 1.0f64
            t = s1
        }
        if kind == 3u8 {
            a = 1.0f64
            t = 1.0f64
        }
        if str.eq(nm, "d") { ret ac.itg_d(v, a, t, sc) }
        if str.eq(nm, "p") { ret ac.itg_p(v, a, t, sc) }
        if str.eq(nm, "q") { ret ac.itg_q(v, a, t, sc) }
        if str.eq(nm, "m") { ret ac.itg_m(k, a, t, sc) }
        ret ac.itg_lev(v, k, a, t, sc)
    }
    if str.eq(nm, "d") { ret ac.p1_d(v, s1, sc) }
    if str.eq(nm, "p") { ret ac.p1_p(v, s1, sc) }
    if str.eq(nm, "q") { ret ac.p1_q(v, s1, sc) }
    if str.eq(nm, "m") { ret ac.p1_m(k, s1, sc) }
    ret ac.p1_lev(v, k, s1, sc)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/actuar.json")
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
