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
