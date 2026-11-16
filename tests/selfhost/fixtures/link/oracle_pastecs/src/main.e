// e.algo.stat.pastecs against pastecs: turnpoints and stat.desc. tests/oracle/pastecs.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pastecs`; the layout is at the top of
// scripts/r_oracle/groups/pastecs.R.

use e.algo.stat.pastecs as pc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[2usize])
    let x = z[3usize..3usize + n]
    let nm = c.name
    if str.starts_with(nm, "tt_") {
        let (tt, te) = pc.trend_test(a, x)
        if te != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(nm, "tt_rho") { ret tt.rho }
        if str.eq(nm, "tt_s") { ret tt.s }
        ret tt.p
    }
    if str.eq(nm, "cen") {
        let cp = usize(z[3usize + n])
        let (cr, ce) = pc.deccensus(a, x, cp)
        if ce != ok { ret 0.0f64 / 0.0f64 }
        let cq = usize(z[4usize + n])
        if cq < cp { ret cr.test_s[cq] }
        if cq == cp { ret cr.amp }
        let k = cq - cp - 1usize
        if k < n { ret cr.ci[k] }
        if k < 2usize * n { ret cr.seasonal[k - n] }
        if k < 3usize * n { ret cr.trend[k - 2usize * n] }
        ret cr.resid[k - 3usize * n]
    }
    if str.eq(nm, "ab") {
        let aq = usize(z[3usize + n])
        let ap = usize(z[4usize + n])
        let (ar, ae) = pc.abund(a, x, aq, ap, z[1usize])
        if ae != ok { ret 0.0f64 / 0.0f64 }
        let ak = usize(z[5usize + n])
        if ak < ap { ret f64(ar.vr[ak]) }
        if ak < 2usize * ap { ret ar.sort_[ak - ap] }
        if ak < 3usize * ap { ret ar.cumsum[ak - 2usize * ap] }
        if ak < 4usize * ap { ret ar.plogind[ak - 3usize * ap] }
        ret ar.pnonull[ak - 4usize * ap]
    }
    if str.eq(nm, "tg") {
        let (tr, te) = pc.turnogram(a, x, z[3usize + n], z[4usize + n], z[5usize + n], z[6usize + n] > 0.5f64, z[7usize + n] > 0.5f64)
        if te != ok { ret 0.0f64 / 0.0f64 }
        let tq = usize(z[8usize + n])
        let m = tr.m
        if tq == 0usize { ret f64(m) }
        if tq <= m { ret tr.interval[tq - 1usize] }
        if tq <= 2usize * m { ret tr.n[tq - m - 1usize] }
        if tq <= 3usize * m { ret tr.turns[tq - 2usize * m - 1usize] }
        if tq <= 4usize * m { ret tr.info[tq - 3usize * m - 1usize] }
        if tq == 4usize * m + 1usize { ret tr.level }
        if tq <= 5usize * m + 1usize { ret tr.turns_min[tq - 4usize * m - 2usize] }
        if tq <= 6usize * m + 1usize { ret tr.turns_max[tq - 5usize * m - 2usize] }
        if tq <= 7usize * m + 1usize { ret tr.info_min[tq - 6usize * m - 2usize] }
        ret tr.info_max[tq - 7usize * m - 2usize]
    }
    if str.eq(nm, "lt") {
        let (lo, le) = mem.alloc[f64](a, n)
        if le != ok { ret 0.0f64 / 0.0f64 }
        pc.local_trend(x, z[1usize], lo)
        ret lo[usize(z[3usize + n])]
    }
    if str.eq(nm, "esc") {
        let en = usize(z[3usize + n])
        let ep = usize(z[4usize + n])
        let (vr, ev) = mem.alloc[usize](a, ep)
        let (rv, er) = mem.alloc[f64](a, ep)
        if ev != ok || er != ok { ret 0.0f64 / 0.0f64 }
        let (cnt, ee) = pc.escouf(a, x, en, ep, z[1usize], vr, rv)
        if ee != ok { ret 0.0f64 / 0.0f64 }
        let eq = usize(z[5usize + n])
        if eq == 0usize { ret f64(cnt) }
        if eq <= cnt { ret f64(vr[eq - 1usize]) }
        ret rv[eq - 1usize - cnt]
    }
    if str.eq(nm, "pg") {
        let (v, ge) = pc.pgleissberg(a, usize(z[3usize]), z[4usize], z[5usize] > 0.5f64, z[6usize] > 0.5f64)
        if ge != ok { ret 0.0f64 / 0.0f64 }
        ret v
    }
    if str.eq(nm, "pen") { ret pc.pennington(x, usize(z[3usize + n])) }
    if str.eq(nm, "reg") {
        let b = 3usize + n
        let no = usize(z[b + n + 1usize])
        let (out, eo) = mem.alloc[f64](a, no)
        if eo != ok { ret 0.0f64 / 0.0f64 }
        let re = pc.regul(x, z[b..b + n], z[b + n], no, z[b + n + 2usize], usize(z[b + n + 3usize]), usize(z[b + n + 4usize]), z[b + n + 5usize], z[b + n + 6usize], out)
        if re != ok { ret 0.0f64 / 0.0f64 }
        ret out[usize(z[b + n + 7usize])]
    }
    if str.eq(nm, "dec") {
        let b = 3usize + n
        let (f, ef) = mem.alloc[f64](a, n + 8usize)
        let (rs, er) = mem.alloc[f64](a, n + 8usize)
        if ef != ok || er != ok { ret 0.0f64 / 0.0f64 }
        let which = usize(z[b + 4usize])
        let idx = usize(z[b + 5usize])
        if z[0usize] == 5.0f64 {
            let na = usize(z[b + 2usize])
            let (axs, eax) = mem.alloc[usize](a, na)
            if eax != ok { ret 0.0f64 / 0.0f64 }
            var q = 0usize
            while q < na {
                axs[q] = usize(z[b + 3usize + q])
                q += 1usize
            }
            let ve = pc.decevf(a, x, u8(z[b]), usize(z[b + 1usize]), axs, f, rs)
            if ve != ok { ret 0.0f64 / 0.0f64 }
            if usize(z[b + 3usize + na]) == 0usize { ret f[usize(z[b + 4usize + na])] }
            ret rs[usize(z[b + 4usize + na])]
        }
        if z[0usize] == 4.0f64 {
            let nw = usize(z[b + 7usize])
            let ae = pc.decaverage(a, x, u8(z[b]), usize(z[b + 1usize]), usize(z[b + 2usize]), u8(z[b + 3usize]), z[b + 8usize..b + 8usize + nw], usize(z[b + 6usize]), f, rs)
            if ae != ok { ret 0.0f64 / 0.0f64 }
        } else if z[0usize] == 2.0f64 {
            let (m, de) = pc.decdiff(a, x, u8(z[b]), usize(z[b + 1usize]), usize(z[b + 2usize]), u8(z[b + 3usize]), f, rs)
            if de != ok { ret 0.0f64 / 0.0f64 }
        } else {
            let de = pc.decmedian(a, x, u8(z[b]), usize(z[b + 1usize]), usize(z[b + 2usize]), u8(z[b + 3usize]), f, rs)
            if de != ok { ret 0.0f64 / 0.0f64 }
        }
        if which == 0usize { ret f[idx] }
        ret rs[idx]
    }
    if str.starts_with(nm, "d_") {
        let (d, e) = pc.stat_desc(a, x, z[1usize])
        if e != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(nm, "d_nbr.null") { ret d.nbr_null }
        if str.eq(nm, "d_min") { ret d.min }
        if str.eq(nm, "d_max") { ret d.max }
        if str.eq(nm, "d_range") { ret d.range }
        if str.eq(nm, "d_sum") { ret d.sum }
        if str.eq(nm, "d_median") { ret d.median }
        if str.eq(nm, "d_mean") { ret d.mean }
        if str.eq(nm, "d_SE.mean") { ret d.se_mean }
        if str.eq(nm, "d_CI.mean") { ret d.ci_mean }
        if str.eq(nm, "d_var") { ret d.variance }
        if str.eq(nm, "d_std.dev") { ret d.std_dev }
        if str.eq(nm, "d_coef.var") { ret d.coef_var }
        if str.eq(nm, "d_skewness") { ret d.skewness }
        if str.eq(nm, "d_skew.2SE") { ret d.skew_2se }
        if str.eq(nm, "d_kurtosis") { ret d.kurtosis }
        if str.eq(nm, "d_normtest.W") { ret d.normtest_w }
        if str.eq(nm, "d_normtest.p") { ret d.normtest_p }
        ret d.kurt_2se
    }
    let (t, e) = pc.turnpoints(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(nm, "nturns") { ret f64(t.nturns) }
    if str.eq(nm, "firstpeak") {
        if t.firstispeak { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(nm, "npeaks") { ret f64(t.npeaks) }
    if str.eq(nm, "npits") { ret f64(t.npits) }
    if str.eq(nm, "tppos_s") { ret t.tppos_sum }
    if str.eq(nm, "tppos_w") { ret t.tppos_w }
    if str.eq(nm, "proba_s") { ret t.proba_sum }
    if str.eq(nm, "proba_w") { ret t.proba_w }
    if str.eq(nm, "info_s") { ret t.info_sum }
    ret t.info_w
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pastecs.json")
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
