// e.algo.stat.suppdists against SuppDists: inverse Gaussian, Kendall, Spearman (exact) and Johnson distributions.
// tests/oracle/suppdists.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R suppdists`; the
// layout is at the top of scripts/r_oracle/groups/suppdists.R.

use e.algo.stat.suppdists as sd
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nm = c.name
    let nan = 0.0f64 / 0.0f64
    if str.eq(nm, "ig_d") { ret sd.dinv_gauss(z[2usize], z[0usize], z[1usize]) }
    if str.eq(nm, "ig_p") { ret sd.pinv_gauss(z[2usize], z[0usize], z[1usize]) }
    if str.eq(nm, "ig_q") { ret sd.qinv_gauss(z[2usize], z[0usize], z[1usize]) }
    if str.eq(nm, "pc_d") { ret sd.fcorrelation(z[2usize], z[0usize], i64(z[1usize])) }
    if str.eq(nm, "pc_p") { ret sd.pcorrelation(z[2usize], z[0usize], i64(z[1usize])) }
    if str.eq(nm, "pc_q") { ret sd.qcorrelation(z[2usize], z[0usize], i64(z[1usize])) }
    if str.starts_with(nm, "kw_") {
        let nsc = z[0usize] == 1.0f64
        let kc = i64(z[1usize])
        let kn = i64(z[2usize])
        if str.eq(nm, "kw_p") { ret sd.pkruskal_wallis(z[4usize], kc, kn, z[3usize], nsc) }
        if str.eq(nm, "kw_u") { ret sd.qkruskal_wallis_upper(z[4usize], kc, kn, z[3usize], nsc) }
        if str.eq(nm, "kw_q") { ret sd.xkruskal_wallis(z[4usize], kc, kn, z[3usize], nsc) }
        ret sd.fkruskal_wallis(z[4usize], kc, kn, z[3usize], nsc)
    }
    if str.starts_with(nm, "mf_") {
        let mdf = i64(z[0usize])
        let mk = i64(z[1usize])
        if str.eq(nm, "mf_p") { ret sd.pmaxfratio(z[2usize], mdf, mk) }
        if str.eq(nm, "mf_u") { ret sd.qmaxfratio_upper(z[2usize], mdf, mk) }
        if str.eq(nm, "mf_d") { ret sd.fmaxfratio(z[2usize], mdf, mk) }
        ret sd.xmaxfratio(z[2usize], mdf, mk)
    }
    if str.starts_with(nm, "fr_") {
        let fr = i64(z[0usize])
        let fn_ = i64(z[1usize])
        let (fd, fe) = sd.friedman_exact(a, fr, fn_)
        if fe != ok { ret nan }
        if str.eq(nm, "fr_p") { ret sd.pfrie(&fd, z[2usize], fr, fn_, false) }
        if str.eq(nm, "fr_u") { ret sd.qfrie(&fd, z[2usize], fr, fn_, false) }
        if str.eq(nm, "fr_d") { ret sd.ffrie(&fd, z[2usize], fr, fn_, false) }
        ret sd.xfrie(&fd, z[2usize], fr, fn_)
    }
    if str.starts_with(nm, "mo_") {
        var mm = sd.moments_pearson(0.0f64, 3i64)
        var what = 0usize
        if str.eq(nm, "mo_ig") {
            mm = sd.moments_inv_gauss(z[0usize], z[1usize])
            what = usize(z[2usize])
        } else if str.eq(nm, "mo_jo") {
            mm = sd.moments_johnson(z[0usize], z[1usize], z[2usize], z[3usize], u8(z[4usize]))
            what = usize(z[5usize])
        } else if str.eq(nm, "mo_mf") {
            mm = sd.moments_maxfratio(i64(z[0usize]), i64(z[1usize]))
            what = usize(z[2usize])
        } else if str.eq(nm, "mo_kw") {
            mm = sd.moments_kruskal_wallis(i64(z[1usize]), i64(z[2usize]), z[3usize], z[0usize] == 1.0f64)
            what = usize(z[4usize])
        } else if str.eq(nm, "mo_fr") {
            let (md, me) = sd.friedman_exact(a, i64(z[0usize]), i64(z[1usize]))
            if me != ok { ret nan }
            mm = sd.moments_friedman(&md, i64(z[0usize]), i64(z[1usize]))
            what = usize(z[2usize])
        } else if str.eq(nm, "mo_sp") {
            mm = sd.moments_spearman(i64(z[0usize]))
            what = usize(z[1usize])
        } else {
            mm = sd.moments_pearson(z[0usize], i64(z[1usize]))
            what = usize(z[2usize])
        }
        if what == 0usize { ret mm.mean }
        if what == 1usize { ret mm.median }
        if what == 2usize { ret mm.mode }
        if what == 3usize { ret mm.variance }
        if what == 4usize { ret mm.third }
        ret mm.fourth
    }
    if str.starts_with(nm, "kp_") {
        let kn = i64(z[0usize])
        var kv = 0.0f64
        var ke = ok
        if str.eq(nm, "kp_p") {
            let (r1, e1) = sd.pkendall_pkg(a, kn, z[1usize])
            kv = r1
            ke = e1
        } else if str.eq(nm, "kp_u") {
            let (r2, e2) = sd.qkendall_pkg(a, kn, z[1usize])
            kv = r2
            ke = e2
        } else if str.eq(nm, "kp_d") {
            let (r3, e3) = sd.fkendall_pkg(a, kn, z[1usize])
            kv = r3
            ke = e3
        } else if str.eq(nm, "kp_q") {
            let (r4, e4) = sd.xkendall_pkg(a, z[1usize], kn)
            kv = r4
            ke = e4
        } else if z[1usize] == 0.0f64 {
            kv = f64(4i64 * kn + 10i64) / f64(9i64 * kn * (kn - 1i64))
        } else {
            let (r5, e5) = sd.fourth_kendall(a, kn)
            kv = r5
            ke = e5
        }
        if ke != ok { ret nan }
        ret kv
    }
    if str.starts_with(nm, "sq_") {
        let sr = i64(z[0usize])
        let (sdist, se) = sd.friedman_exact_rho(a, sr)
        if se != ok { ret nan }
        if str.eq(nm, "sq_p") { ret sd.pspearman_pkg(&sdist, z[1usize], sr) }
        if str.eq(nm, "sq_u") { ret sd.qspearman_pkg(&sdist, z[1usize], sr) }
        if str.eq(nm, "sq_d") { ret sd.fspearman_pkg(&sdist, z[1usize], sr) }
        // the package's quantile search calls the Friedman cdf with the rho flag off and two blocks, which is exact only for r <= 5
        let (qdist, qe) = sd.friedman_exact(a, sr, 2i64)
        if qe != ok { ret nan }
        ret sd.xspearman_pkg(&qdist, z[1usize], sr)
    }
    if str.starts_with(nm, "jf_") {
        var jf: sd.JFit = zero
        var jw = 0usize
        if str.eq(nm, "jf_q") {
            jf = sd.johnson_fit_quantiles(z[0usize], z[1usize], z[2usize], z[3usize], z[4usize])
            jw = usize(z[5usize])
        } else {
            let jv = z[1usize]
            let jsd = math.sqrt[f64](jv)
            jf = sd.johnson_moment_fit(z[0usize], jsd, z[2usize] / (jsd * jv), z[3usize] / (jv * jv))
            jw = usize(z[4usize])
        }
        if !jf.ok_ { ret nan }
        if jw == 0usize { ret jf.gamma }
        if jw == 1usize { ret jf.delta }
        if jw == 2usize { ret jf.xi }
        if jw == 3usize { ret jf.lambda }
        ret f64(jf.kind)
    }
    if str.eq(nm, "gh_d") { ret sd.ghyper_d(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(nm, "gh_p") { ret sd.ghyper_p(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(nm, "gh_q") { ret sd.ghyper_q(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.starts_with(nm, "ken_") || str.starts_with(nm, "sp_") {
        let n = usize(z[0usize])
        var v = 0.0f64
        var e = ok
        if str.eq(nm, "ken_d") {
            let (r, re) = sd.dkendall(a, z[1usize], n)
            v = r
            e = re
        } else if str.eq(nm, "ken_p") {
            let (r, re) = sd.pkendall(a, z[1usize], n)
            v = r
            e = re
        } else if str.eq(nm, "sp_d") {
            let (r, re) = sd.dspearman(a, z[1usize], n)
            v = r
            e = re
        } else {
            let (r, re) = sd.pspearman(a, z[1usize], n)
            v = r
            e = re
        }
        if e != ok { ret nan }
        ret v
    }
    let kind = u8(z[0usize])
    if str.eq(nm, "jo_d") { ret sd.djohnson(z[5usize], z[1usize], z[2usize], z[3usize], z[4usize], kind) }
    if str.eq(nm, "jo_p") { ret sd.pjohnson(z[5usize], z[1usize], z[2usize], z[3usize], z[4usize], kind) }
    ret sd.qjohnson(z[5usize], z[1usize], z[2usize], z[3usize], z[4usize], kind)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/suppdists.json")
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
