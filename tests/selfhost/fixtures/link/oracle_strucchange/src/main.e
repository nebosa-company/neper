// e.algo.stat.strucpkg against strucchange Fstats and breakpoints. tests/oracle/strucchange.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R strucchange`; the layout is at the top of scripts/r_oracle/groups/strucchange.R.

use e.algo.stat.strucpkg as sc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "p2") {
        let nd = usize(z[0usize])
        let (xr, exr) = mem.alloc[f64](a, nd * 2usize)
        if exr != ok { ret nan }
        var qd = 0usize
        while qd < nd {
            xr[qd * 2usize] = 1.0f64
            xr[qd * 2usize + 1usize] = z[3usize + nd + qd]
            qd += 1usize
        }
        var pout: [2]f64 = zero
        let pe = sc.pscore2_lm(a, z[3usize..3usize + nd], z[3usize + nd..3usize + 2usize * nd], xr, nd, 2usize, 10usize, pout[0usize..2usize])
        if pe != ok { ret nan }
        ret pout[usize(z[3usize + 2usize * nd])]
    }
    if str.eq(c.name, "pw") {
        let nd = usize(z[0usize])
        let (xr, exr) = mem.alloc[f64](a, nd * 2usize)
        if exr != ok { ret nan }
        var qd = 0usize
        while qd < nd {
            xr[qd * 2usize] = 1.0f64
            xr[qd * 2usize + 1usize] = z[3usize + nd + qd]
            qd += 1usize
        }
        var pout: [2]f64 = zero
        let pe = sc.pscore_lmw(a, z[3usize..3usize + nd], z[3usize + nd..3usize + 2usize * nd], z[3usize + 2usize * nd..3usize + 3usize * nd], xr, nd, 2usize, 10usize, usize(z[2usize]), pout[0usize..2usize])
        if pe != ok { ret nan }
        ret pout[usize(z[3usize + 3usize * nd])]
    }
    if str.eq(c.name, "ps") {
        let nd = usize(z[0usize])
        let (xr, exr) = mem.alloc[f64](a, nd * 2usize)
        if exr != ok { ret nan }
        var qd = 0usize
        while qd < nd {
            xr[qd * 2usize] = 1.0f64
            xr[qd * 2usize + 1usize] = z[3usize + nd + qd]
            qd += 1usize
        }
        var pout: [2]f64 = zero
        let pe = sc.pscore_lm(a, z[3usize..3usize + nd], z[3usize + nd..3usize + 2usize * nd], xr, nd, 2usize, 10usize, usize(z[2usize]), pout[0usize..2usize])
        if pe != ok { ret nan }
        ret pout[usize(z[3usize + 2usize * nd])]
    }
    if str.eq(c.name, "dv") {
        let nd = usize(z[0usize])
        let (xr, exr) = mem.alloc[f64](a, nd * 2usize)
        if exr != ok { ret nan }
        var qd = 0usize
        while qd < nd {
            xr[qd * 2usize] = 1.0f64
            xr[qd * 2usize + 1usize] = z[3usize + nd + qd]
            qd += 1usize
        }
        var dout: [3]f64 = zero
        let de = sc.davies_lm(a, z[3usize..3usize + nd], z[3usize + nd..3usize + 2usize * nd], xr, nd, 2usize, 10usize, usize(z[2usize]), dout[0usize..3usize])
        if de != ok { ret nan }
        ret dout[usize(z[3usize + 2usize * nd])]
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let y = z[3usize..3usize + n]
    let x = z[3usize + n..3usize + n + n * p]
    if str.eq(c.name, "pf1") || str.eq(c.name, "pf2") || str.eq(c.name, "pf3") || str.eq(c.name, "sf1") || str.eq(c.name, "sf2") || str.eq(c.name, "sf3") {
        let fr = usize(math.floor[f64](0.15f64 * f64(n)))
        let tt = n - fr
        let (fv, ef) = mem.alloc[f64](a, tt - fr + 1usize)
        if ef != ok { ret nan }
        sc.fstats(a, y, x, n, p, fr, tt, fv)
        var mx = fv[0usize]
        var sm = 0.0f64
        var se = 0.0f64
        var q = 0usize
        while q < fv.len {
            if fv[q] > mx { mx = fv[q] }
            sm += fv[q]
            se += math.exp[f64](0.5f64 * fv[q])
            q += 1usize
        }
        let nf = f64(fv.len)
        var st = mx
        var ty = 0usize
        if str.eq(c.name, "pf2") || str.eq(c.name, "sf2") {
            st = sm / nf
            ty = 1usize
        }
        if str.eq(c.name, "pf3") || str.eq(c.name, "sf3") {
            st = math.log[f64](se / nf)
            ty = 2usize
        }
        if c.name[0usize] == 115u8 { ret st }
        ret sc.pvalue_fstats(ty, st, p, f64(fr) / f64(n))
    }
    if str.eq(c.name, "cus") || str.eq(c.name, "cusp") {
        let (cs, cp) = sc.ols_cusum(a, y, x, n, p)
        if str.eq(c.name, "cus") { ret cs }
        ret cp
    }
    if str.eq(c.name, "rmo") || str.eq(c.name, "rmop") {
        let (qs, qp) = sc.rec_mosum(a, y, x, n, p, z[3usize + n + n * p])
        if str.eq(c.name, "rmo") { ret qs }
        ret qp
    }
    if str.eq(c.name, "mos") || str.eq(c.name, "mosp") {
        let (ms, mp) = sc.ols_mosum(a, y, x, n, p, z[3usize + n + n * p])
        if str.eq(c.name, "mos") { ret ms }
        ret mp
    }
    if str.eq(c.name, "rec") || str.eq(c.name, "recp") {
        let (rs, rp) = sc.rec_cusum(a, y, x, n, p)
        if str.eq(c.name, "rec") { ret rs }
        ret rp
    }
    let from = usize(math.floor[f64](0.15f64 * f64(n)))
    let to = n - from
    if str.eq(c.name, "fsum") || str.eq(c.name, "supf") {
        let (f, e1) = mem.alloc[f64](a, to - from + 1usize)
        if e1 != ok { ret nan }
        sc.fstats(a, y, x, n, p, from, to, f)
        var s = 0.0f64
        var mx = f[0usize]
        var i = 0usize
        while i < f.len {
            s += f[i] * f64(i + 1usize)
            if f[i] > mx { mx = f[i] }
            i += 1usize
        }
        if str.eq(c.name, "supf") { ret mx }
        ret s
    }
    let (bp, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret nan }
    let rss = sc.breakpoints(a, y, x, n, p, from, m, bp)
    if str.eq(c.name, "rss") { ret rss }
    if str.eq(c.name, "bic") { ret sc.breakpoints_bic(rss, n, p, m) }
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += bp[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/strucchange.json")
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
