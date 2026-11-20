// e.algo.stat.gam against R gam::gam with s() and lo() terms together (general.wam). tests/oracle/gam_mix.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gam_mix`; the argument layout is at the top of scripts/r_oracle/groups/gam_mix.R.

use e.algo.stat.gam as gm
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let fam = usize(z[0usize])
    let n = usize(z[1usize])
    let q = usize(z[2usize])
    let m = usize(z[3usize])
    let kind = z[4usize..4usize + q]
    let p1 = z[4usize + q..4usize + 2usize * q]
    let p2 = z[4usize + 2usize * q..4usize + 3usize * q]
    let ox = 4usize + 3usize * q
    let oz = ox + q * n
    let oy = oz + m * n
    let ow = oy + n
    let what = usize(z[ow + n])
    let idx = usize(z[ow + n + 1usize])
    var pl = 0usize
    var i = 0usize
    while i < q {
        if kind[i] == 0.0f64 { pl += 1usize } else { pl += usize(p2[i]) }
        i += 1usize
    }
    let p = 1usize + pl + m
    let (xm, e1) = mem.alloc[f64](a, n * p)
    let (wh, e2) = mem.alloc[usize](a, q + 1usize)
    let (cs, e4) = mem.alloc[usize](a, q + m + 1usize)
    let (d1, e5) = mem.alloc[f64](a, q + 1usize)
    let (d2, e6) = mem.alloc[f64](a, q + 1usize)
    let (sp, e7) = mem.alloc[f64](a, q + 1usize)
    if e1 != ok || e2 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    i = 0usize
    while i < n {
        xm[i] = 1.0f64
        i += 1usize
    }
    // the model-matrix columns in formula order
    var col = 1usize
    var t = 0usize
    while t < q {
        cs[t] = col
        var dg = 1usize
        if kind[t] != 0.0f64 { dg = usize(p2[t]) }
        var j = 0usize
        while j < dg {
            i = 0usize
            while i < n {
                var v = z[ox + t * n + i]
                if j == 1usize { v = v * v }
                xm[(col + j) * n + i] = v
                i += 1usize
            }
            j += 1usize
        }
        col += dg
        t += 1usize
    }
    t = 0usize
    while t < m {
        cs[q + t] = col
        i = 0usize
        while i < n {
            xm[col * n + i] = z[oz + t * n + i]
            i += 1usize
        }
        col += 1usize
        t += 1usize
    }
    // the smoothers run s() terms first, then lo() terms
    var k = 0usize
    var pass = 0usize
    while pass < 2usize {
        t = 0usize
        while t < q {
            var want = 0.0f64
            if pass == 1usize { want = 1.0f64 }
            if kind[t] == want {
                wh[k] = cs[t]
                sp[k] = p2[t]
                if pass == 0usize {
                    d1[k] = p1[t]
                    d2[k] = 0.0f64
                    if p1[t] > 0.0f64 { d2[k] = p1[t] + 1.5f64 }
                } else {
                    d1[k] = 0.0f64 - p1[t]
                    let s2 = p1[t] - 0.15f64
                    d2[k] = 0.0f64 - math.floor[f64](s2 * 100.0f64 + 0.5f64) / 100.0f64
                }
                k += 1usize
            }
            t += 1usize
        }
        pass += 1usize
    }
    var f: gm.GamFit = zero
    if gm.gam_fit(a, xm, n, p, z[oy..oy + n], z[ow..ow + n], fam, q, wh, d1[0usize..q], sp[0usize..q], 1.0e-7f64, 30usize, 1.0e-7f64, 30usize, &f) != ok { ret nan }
    if what == 0usize { ret f.coef[idx] }
    if what == 1usize { ret f.eta[idx] }
    if what == 2usize { ret f.mu[idx] }
    if what == 3usize { ret f.smooth[idx] }
    if what == 4usize { ret f.nldf[idx] }
    if what == 5usize {
        if idx == 0usize { ret f.deviance }
        if idx == 1usize { ret f.null_dev }
        if idx == 2usize { ret f.aic }
        if idx == 3usize { ret f.df_resid }
        if idx == 4usize { ret f64(f.iter) }
        if idx == 5usize { ret f.df_null }
        ret f64(f.rank)
    }
    if what == 7usize { ret f.resid[idx] }
    if what == 8usize { ret f.nl_chisq[idx] }
    if what == 9usize { ret f64(f.bf_iter[idx]) }
    if what == 10usize { ret f.weights[idx] }
    if what == 11usize { ret f.levs[idx] }
    if what == 12usize {
        let tt = idx / 3usize
        let r = idx % 3usize
        if r == 0usize { ret f.np_df[tt] }
        if r == 1usize { ret f.np_stat[tt] }
        ret f.np_p[tt]
    }
    if what == 13usize {
        let tc = cs[idx / 4usize - 1usize]
        let r = idx % 4usize
        if r == 0usize { ret f.par_df[tc] }
        if r == 1usize { ret f.par_ss[tc] }
        if r == 2usize { ret f.par_f[tc] }
        ret f.par_p[tc]
    }
    if what == 14usize {
        if idx == 0usize { ret f.ssr }
        ret f.disp
    }
    if what == 17usize {
        var g: gm.GamFit = zero
        if gm.gam_fit(a, xm, n, p, z[oy..oy + n], z[ow..ow + n], fam, q, wh, d2[0usize..q], sp[0usize..q], 1.0e-7f64, 30usize, 1.0e-7f64, 30usize, &g) != ok { ret nan }
        let at = gm.anova_two(&f, &g)
        ret at[idx]
    }
    if what == 15usize { ret f.se_link[idx] }
    if what == 16usize { ret f.se_resp[idx] }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gam_mix.json")
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
