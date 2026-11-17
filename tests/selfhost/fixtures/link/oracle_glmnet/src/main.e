// e.algo.stat.glmnet (gaussian) against glmnet at a user lambda sequence. tests/oracle/glmnet.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glmnet`; the layout is at the top of
// scripts/r_oracle/groups/glmnet.R.

use e.algo.rand.r as rng
use e.algo.stat.glmnet as gl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if c.name[0usize] == 114u8 {
        // r (the fold assignment cv.glmnet makes): (seed, n, nfolds, index), the fold number 1 .. nfolds of observation index
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let rn = usize(x[1usize])
        let (fid, fe) = mem.alloc[usize](a, rn)
        if fe != ok { ret 0.0f64 / 0.0f64 }
        if gl.random_foldid(a, &rr, rn, usize(x[2usize]), fid) != ok { ret 0.0f64 / 0.0f64 }
        ret f64(fid[usize(x[3usize])] + 1usize)
    }
    if c.name[0usize] == 105u8 {
        // i (coef interpolation): (n, p, alpha, std, nl, lambda[nl], vf[p], y[n], X[n p], s, j)
        let ln = usize(x[0usize])
        let lp = usize(x[1usize])
        let lnl = usize(x[4usize])
        let (ic, ice) = mem.alloc[f64](a, lnl * (lp + 1usize))
        let (ico, ioe) = mem.alloc[f64](a, lp + 1usize)
        if ice != ok || ioe != ok { ret 0.0f64 / 0.0f64 }
        let none: []const f64 = zero
        let b0 = 5usize + lnl + lp
        if gl.gaussian(a, x[b0 + ln..b0 + ln + ln * lp], x[b0..b0 + ln], none, none, none, ln, lp, x[2usize], x[3usize] != 0.0f64, x[5usize + lnl..5usize + lnl + lp], x[5usize..5usize + lnl], ic) != ok { ret 0.0f64 / 0.0f64 }
        gl.coef_interp(x[5usize..5usize + lnl], ic, lp, x[b0 + ln + ln * lp], ico)
        ret ico[usize(x[b0 + ln + ln * lp + 1usize])]
    }
    if c.name[0usize] == 110u8 {
        // nlam: the lpath layout, the answer is the number of lambdas glmnet reports
        let ln = usize(x[0usize])
        let lp = usize(x[1usize])
        ret f64(gl.path_len(a, x[5usize + lp + ln..5usize + lp + ln + ln * lp], x[5usize + lp..5usize + lp + ln], ln, lp, x[2usize], x[3usize] != 0.0f64, x[5usize..5usize + lp], 100usize))
    }
    if c.name[0usize] == 108u8 {
        // lpath: (n, p, alpha, std, k, vf[p], y[n], X[n p])
        let ln = usize(x[0usize])
        let lp = usize(x[1usize])
        let (lo, le) = mem.alloc[f64](a, 100usize)
        if le != ok { ret 0.0f64 / 0.0f64 }
        if gl.lambda_path(a, x[5usize + lp + ln..5usize + lp + ln + ln * lp], x[5usize + lp..5usize + lp + ln], ln, lp, x[2usize], x[3usize] != 0.0f64, x[5usize..5usize + lp], 100usize, lo) != ok { ret 0.0f64 / 0.0f64 }
        ret lo[usize(x[4usize])]
    }
    if c.name[0usize] == 109u8 {
        // mg: (n, p, alpha, std, nl, lambda[nl], vf[p], m, Y[n m], X[n p], k, r, j)
        let mn = usize(x[0usize])
        let mp = usize(x[1usize])
        let mnl = usize(x[4usize])
        let mm = usize(x[5usize + mnl + mp])
        let ys = x[6usize + mnl + mp..6usize + mnl + mp + mn * mm]
        let xm2 = x[6usize + mnl + mp + mn * mm..6usize + mnl + mp + mn * mm + mn * mp]
        let at2 = 6usize + mnl + mp + mn * mm + mn * mp
        let (mc, mce) = mem.alloc[f64](a, mnl * mm * (mp + 1usize))
        if mce != ok { ret 0.0f64 / 0.0f64 }
        if gl.mgaussian(a, xm2, ys, mn, mp, mm, x[2usize], x[3usize] != 0.0f64, x[5usize + mnl..5usize + mnl + mp], x[5usize..5usize + mnl], mc) != ok { ret 0.0f64 / 0.0f64 }
        ret mc[(usize(x[at2]) * mm + usize(x[at2 + 1usize])) * (mp + 1usize) + usize(x[at2 + 2usize])]
    }
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let nl = usize(x[4usize])
    let lam = x[5usize..5usize + nl]
    let vf = x[5usize + nl..5usize + nl + p]
    let y = x[5usize + nl + p..5usize + nl + p + n]
    let xm = x[5usize + nl + p + n..5usize + nl + p + n + n * p]
    let at = 5usize + nl + p + n + n * p
    if c.name[0usize] == 99u8 && c.name[1usize] == 118u8 {
        // cv: foldid[n], nfolds, k, which (0 cvm, 1 cvsd) after X
        let (fid, fe) = mem.alloc[usize](a, n)
        let (cm, ce2) = mem.alloc[f64](a, nl)
        let (cs, ce3) = mem.alloc[f64](a, nl)
        if fe != ok || ce2 != ok || ce3 != ok { ret 0.0f64 / 0.0f64 }
        var q = 0usize
        while q < n {
            fid[q] = usize(x[at + q])
            q += 1usize
        }
        let nfo = usize(x[at + n])
        var cve = ok
        if c.name.len > 2usize && c.name[2usize] == 112u8 { cve = gl.cv_poisson(a, usize(x[at + n + 3usize]), xm, y, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, fid, nfo, false, cm, cs) } else if c.name.len > 2usize && c.name[2usize] == 98u8 { cve = gl.cv_binomial(a, usize(x[at + n + 3usize]), xm, y, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, fid, nfo, false, cm, cs) } else { cve = gl.cv_gaussian(a, xm, y, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, fid, nfo, false, cm, cs) }
        if cve != ok { ret 0.0f64 / 0.0f64 }
        if x[at + n + 2usize] >= 2.0f64 {
            let (sel, se) = mem.alloc[f64](a, 2usize)
            if se != ok { ret 0.0f64 / 0.0f64 }
            gl.cv_select(lam, cm, cs, sel)
            ret sel[usize(x[at + n + 2usize]) - 2usize]
        }
        if x[at + n + 2usize] == 0.0f64 { ret cm[usize(x[at + n + 1usize])] }
        ret cs[usize(x[at + n + 1usize])]
    }
    let wl = n * usize(x[at + 2usize])
    let bl = p * usize(x[at + 3usize])
    let ol = n * usize(x[at + 4usize])
    let wts = x[at + 5usize..at + 5usize + wl]
    let lo = x[at + 5usize + wl..at + 5usize + wl + bl]
    let up = x[at + 5usize + wl + bl..at + 5usize + wl + 2usize * bl]
    let off = x[at + 5usize + wl + 2usize * bl..at + 5usize + wl + 2usize * bl + ol]
    let (coef, ce) = mem.alloc[f64](a, nl * (p + 1usize))
    if ce != ok { ret 0.0f64 / 0.0f64 }
    var ge = ok
    if c.name[0usize] == 112u8 {
        ge = gl.poisson(a, xm, y, wts, off, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, coef)
    } else if c.name[0usize] == 98u8 {
        ge = gl.binomial(a, xm, y, wts, off, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, coef)
    } else {
        ge = gl.gaussian(a, xm, y, wts, lo, up, n, p, x[2usize], x[3usize] != 0.0f64, vf, lam, coef)
    }
    if ge != ok { ret 0.0f64 / 0.0f64 }
    ret coef[usize(x[at]) * (p + 1usize) + usize(x[at + 1usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/glmnet.json")
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
