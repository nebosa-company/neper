// e.algo.stat.gam against R gam::gam with s() terms. tests/oracle/gam.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gam`; the argument layout is at the top of scripts/r_oracle/groups/gam.R.

use e.algo.stat.gam as gm
use e.io
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
    let p = 1usize + q + m
    let df = z[4usize..4usize + q]
    let spar = z[4usize + q..4usize + 2usize * q]
    let ox = 4usize + 2usize * q
    let oz = ox + q * n
    let oy = oz + m * n
    let ow = oy + n
    let what = usize(z[ow + n])
    let idx = usize(z[ow + n + 1usize])
    let (xm, e1) = mem.alloc[f64](a, n * p)
    let (wh, e2) = mem.alloc[usize](a, q + 1usize)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < n {
        xm[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < q * n {
        xm[n + i] = z[ox + i]
        i += 1usize
    }
    i = 0usize
    while i < m * n {
        xm[n + q * n + i] = z[oz + i]
        i += 1usize
    }
    i = 0usize
    while i < q {
        wh[i] = 1usize + i
        i += 1usize
    }
    var f: gm.GamFit = zero
    if gm.gam_fit(a, xm, n, p, z[oy..oy + n], z[ow..ow + n], fam, q, wh, df, spar, 1.0e-7f64, 30usize, 1.0e-7f64, 30usize, &f) != ok { ret nan }
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
    if what == 12usize {
        let t = idx / 3usize
        let r = idx % 3usize
        if r == 0usize { ret f.np_df[t] }
        if r == 1usize { ret f.np_stat[t] }
        ret f.np_p[t]
    }
    if what == 13usize {
        let col = idx / 4usize
        let r = idx % 4usize
        if r == 0usize { ret f.par_df[col] }
        if r == 1usize { ret f.par_ss[col] }
        if r == 2usize { ret f.par_f[col] }
        ret f.par_p[col]
    }
    if what == 14usize {
        if idx == 0usize { ret f.ssr }
        ret f.disp
    }
    if what == 17usize {
        let (d2, e3) = mem.alloc[f64](a, q + 1usize)
        if e3 != ok { ret nan }
        i = 0usize
        while i < q {
            d2[i] = 0.0f64
            if df[i] > 0.0f64 { d2[i] = df[i] + 1.5f64 }
            i += 1usize
        }
        var g: gm.GamFit = zero
        if gm.gam_fit(a, xm, n, p, z[oy..oy + n], z[ow..ow + n], fam, q, wh, d2[0usize..q], spar, 1.0e-7f64, 30usize, 1.0e-7f64, 30usize, &g) != ok { ret nan }
        let at = gm.anova_two(&f, &g)
        ret at[idx]
    }
    if what == 15usize { ret f.se_link[idx] }
    if what == 16usize { ret f.se_resp[idx] }
    ret f.levs[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gam.json")
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
