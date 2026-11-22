// e.algo.stat.fitdistrplus against fitdistrplus. tests/oracle/fitdist.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fitdist`; the case layout is at the top of scripts/r_oracle/groups/fitdist.R.

use e.algo.rand.r as rng
use e.algo.stat.fitdistrplus as fd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pick(f: *const fd.Fit, k: usize) -> f64 { ret f.est[k] }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let v = x[2usize..2usize + n]
    let ex = x[2usize + n..x.len]
    let k = c.name
    var np = 2usize
    if kind == 2usize { np = 1usize }
    if str.starts_with(k, "c_") || str.starts_with(k, "cb_") { ret cens_answer(a, c) }
    if str.starts_with(k, "dc_") { ret dens_answer(a, k, kind, v, ex) }
    if str.starts_with(k, "d_") { ret desc_answer(a, k, kind, v, ex) }
    if str.starts_with(k, "m_") || str.starts_with(k, "gs_") || str.eq(k, "qt") {
        let (f, e) = fd.fit_mle(a, v, kind)
        if e != ok { os.exit(5) }
        if str.eq(k, "m_p1") { ret f.est[0usize] }
        if str.eq(k, "m_p2") { ret f.est[1usize] }
        if str.eq(k, "m_s1") { ret f.sd[0usize] }
        if str.eq(k, "m_s2") { ret f.sd[1usize] }
        if str.eq(k, "m_ll") { ret f.loglik }
        if str.eq(k, "m_aic") { ret fd.aic(&f) }
        if str.eq(k, "m_bic") { ret fd.bic(&f) }
        if str.eq(k, "m_conv") { ret f64(f.conv) }
        if str.eq(k, "m_v11") { ret f.vc[0usize] }
        if str.eq(k, "m_v12") { ret f.vc[1usize] }
        if str.eq(k, "m_v22") { ret f.vc[3usize] }
        if str.eq(k, "m_cor") { ret fd.cor_of(&f) }
        if str.eq(k, "m_lo") { ret fd.wald(&f, usize(ex[0usize]), 0.025f64) }
        if str.eq(k, "m_up") { ret fd.wald(&f, usize(ex[0usize]), 0.975f64) }
        if str.eq(k, "qt") {
            var out: [5]f64 = zero
            fd.quantiles(&f, ex[0usize..5usize], out[0usize..5usize])
            ret out[usize(ex[5usize])]
        }
        var g: [3]f64 = zero
        var t: [3]usize = zero
        let e2 = fd.gofstat(a, v, &f, true, g[0usize..3usize], t[0usize..3usize])
        if e2 != ok { os.exit(6) }
        if str.eq(k, "gs_ks") { ret g[0usize] }
        if str.eq(k, "gs_cvm") { ret g[1usize] }
        if str.eq(k, "gs_ad") { ret g[2usize] }
        if str.eq(k, "gs_kstest") { ret f64(t[0usize]) }
        if str.eq(k, "gs_adtest") { ret f64(t[1usize]) }
        if str.eq(k, "gs_cvmtest") { ret f64(t[2usize]) }
        var cs: [4]f64 = zero
        let (obs, e3) = mem.alloc[f64](a, n)
        let (theo, e4) = mem.alloc[f64](a, n)
        if e3 != ok || e4 != ok { os.exit(7) }
        let e5 = fd.chisq_default(a, v, &f, cs[0usize..4usize], obs, theo)
        if e5 != ok { os.exit(8) }
        if str.eq(k, "gs_chisq") { ret cs[0usize] }
        if str.eq(k, "gs_df") { ret cs[1usize] }
        if str.eq(k, "gs_pvalue") { ret cs[2usize] }
        if str.eq(k, "gs_ncell") { ret cs[3usize] }
        if str.eq(k, "gs_obs") { ret obs[usize(ex[0usize])] }
        ret theo[usize(ex[0usize])]
    }
    if str.starts_with(k, "s_") {
        let (f, e) = fd.fit_mle_from(a, v, kind, ex[0usize..np])
        if e != ok { os.exit(4) }
        if str.eq(k, "s_p1") { ret f.est[0usize] }
        if str.eq(k, "s_p2") { ret f.est[1usize] }
        ret f.loglik
    }
    if str.starts_with(k, "e_") {
        var f = fd.fit_mme(a, v, kind)
        fd.mme_vcov(a, v, &f)
        if str.eq(k, "e_s1") { ret f.sd[0usize] }
        if str.eq(k, "e_s2") { ret f.sd[1usize] }
        if str.eq(k, "e_p1") { ret f.est[0usize] }
        if str.eq(k, "e_p2") { ret f.est[1usize] }
        ret f.loglik
    }
    if str.starts_with(k, "q_") {
        let (f, e) = fd.fit_qme(a, v, kind, ex[0usize..np], 7u8, ex[0usize..0usize])
        if e != ok { os.exit(9) }
        if str.eq(k, "q_p1") { ret f.est[0usize] }
        ret f.est[1usize]
    }
    if str.starts_with(k, "g_") {
        let (f, e) = fd.fit_mge(a, v, kind, usize(ex[0usize]), ex[0usize..0usize])
        if e != ok { os.exit(10) }
        if str.eq(k, "g_p1") { ret f.est[0usize] }
        ret f.est[1usize]
    }
    ret boot_answer(a, k, kind, v, ex, np)
}

// b_*: ex = (method, param, niter, seed, probs(np) ..., then for b_*: index; for bq_*: 3 probs and the index)
fn boot_answer(a: *mem.Arena, k: str, kind: usize, v: []const f64, ex: []const f64, np: usize) -> f64 {
    let method = usize(ex[0usize])
    let param = ex[1usize] == 1.0f64
    let niter = usize(ex[2usize])
    let seed = i64(ex[3usize])
    let probs = ex[4usize..4usize + np]
    var f: fd.Fit = zero
    var e = ok
    if method == 0usize {
        let (f1, e1) = fd.fit_mle(a, v, kind)
        f = f1
        e = e1
    }
    if method == 1usize {
        let (f1, e1) = fd.fit_qme(a, v, kind, probs, 7u8, ex[0usize..0usize])
        f = f1
        e = e1
    }
    if method == 2usize { f = fd.fit_mme(a, v, kind) }
    if e != ok { os.exit(11) }
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    if str.starts_with(k, "b_d") || str.eq(k, "b_s1") {
        let (dd, e0) = fd.boot_sample(a, &r, v, &f, param, niter * v.len)
        if e0 != ok { os.exit(18) }
        if str.eq(k, "b_s1") {
            let (g1, e9) = fd.fit_mle_from(a, dd[0usize..v.len], kind, f.est[0usize..np])
            if e9 != ok { os.exit(19) }
            ret g1.est[0usize]
        }
        var o = 0usize
        if str.eq(k, "b_dlast") { o = (niter - 1usize) * v.len }
        var s = 0.0f64
        var i = 0usize
        while i < v.len {
            s += dd[o + i]
            i += 1usize
        }
        ret s
    }
    let (est, e2) = mem.alloc[f64](a, niter * np)
    let (conv, e3) = mem.alloc[usize](a, niter)
    if e2 != ok || e3 != ok { os.exit(12) }
    let e4 = fd.bootdist(a, &r, v, &f, method, param, niter, 7u8, probs, est, conv)
    if e4 != ok { os.exit(13) }
    let at = 4usize + np
    if str.eq(k, "b_conv") {
        var s = 0usize
        var i = 0usize
        while i < niter {
            s += conv[i]
            i += 1usize
        }
        ret f64(s)
    }
    if str.starts_with(k, "bq_") {
        let pr = ex[at..at + 3usize]
        let j = usize(ex[at + 3usize])
        // quantile of every bootstrap estimate, then the median and the 2.5% / 97.5% of those
        let (bq, e5) = mem.alloc[f64](a, niter)
        if e5 != ok { os.exit(14) }
        var i = 0usize
        while i < niter {
            var g: fd.Fit = zero
            g.kind = kind
            g.np = np
            g.est[0usize] = est[i * np]
            if np == 2usize { g.est[1usize] = est[i * np + 1usize] }
            var q: [3]f64 = zero
            fd.quantiles(&g, pr, q[0usize..3usize])
            bq[i] = q[j]
            i += 1usize
        }
        let (ci, e6) = mem.alloc[f64](a, 3usize)
        if e6 != ok { os.exit(15) }
        let e7 = fd.column_ci(a, bq, 1usize, 0usize, ci)
        if e7 != ok { os.exit(16) }
        if str.eq(k, "bq_med") { ret ci[0usize] }
        if str.eq(k, "bq_lo") { ret ci[1usize] }
        ret ci[2usize]
    }
    let col = usize(ex[at])
    if str.eq(k, "b_first") { ret est[col] }
    if str.eq(k, "b_last") { ret est[(niter - 1usize) * np + col] }
    if str.eq(k, "b_mean") {
        var s = 0.0f64
        var i = 0usize
        while i < niter {
            s += est[i * np + col]
            i += 1usize
        }
        ret s / f64(niter)
    }
    var ci: [3]f64 = zero
    let e8 = fd.column_ci(a, est, np, col, ci[0usize..3usize])
    if e8 != ok { os.exit(17) }
    if str.eq(k, "b_med") { ret ci[0usize] }
    if str.eq(k, "b_lo") { ret ci[1usize] }
    ret ci[2usize]
}

// c_*, cb_*: args (kind, n, left..., right..., extras); -1 is R's NA. cb_: extras (niter, seed, index)
fn cens_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let k = c.name
    var np = 2usize
    if kind == 2usize { np = 1usize }
    let (bl, e1) = mem.alloc[f64](a, n)
    let (br, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { os.exit(20) }
    var i = 0usize
    while i < n {
        bl[i] = x[2usize + i]
        br[i] = x[2usize + n + i]
        if bl[i] < 0.0f64 { bl[i] = 0.0f64 / 0.0f64 }
        if br[i] < 0.0f64 { br[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    let ex = x[2usize + 2usize * n..x.len]
    let (f, e) = fd.fit_cens(a, bl, br, kind, ex[0usize..0usize])
    if e != ok { os.exit(21) }
    if str.eq(k, "c_p1") { ret f.est[0usize] }
    if str.eq(k, "c_p2") { ret f.est[1usize] }
    if str.eq(k, "c_s1") { ret f.sd[0usize] }
    if str.eq(k, "c_s2") { ret f.sd[1usize] }
    if str.eq(k, "c_ll") { ret f.loglik }
    if str.eq(k, "c_aic") { ret fd.aic(&f) }
    if str.eq(k, "c_bic") { ret fd.bic(&f) }
    let niter = usize(ex[0usize])
    var r: rng.Rng = zero
    rng.seed(&r, i64(ex[1usize]))
    let (est, e3) = mem.alloc[f64](a, niter * np)
    let (conv, e4) = mem.alloc[usize](a, niter)
    if e3 != ok || e4 != ok { os.exit(22) }
    let e5 = fd.bootdist_cens(a, &r, bl, br, &f, niter, est, conv)
    if e5 != ok { os.exit(23) }
    let col = usize(ex[2usize])
    if str.eq(k, "cb_first") { ret est[col] }
    if str.eq(k, "cb_last") { ret est[(niter - 1usize) * np + col] }
    if str.eq(k, "cb_mean") {
        var s = 0.0f64
        var j = 0usize
        while j < niter {
            s += est[j * np + col]
            j += 1usize
        }
        ret s / f64(niter)
    }
    var ci: [3]f64 = zero
    let e6 = fd.column_ci(a, est, np, col, ci[0usize..3usize])
    if e6 != ok { os.exit(24) }
    if str.eq(k, "cb_med") { ret ci[0usize] }
    if str.eq(k, "cb_lo") { ret ci[1usize] }
    ret ci[2usize]
}

// d_*: extras (method 0 unbiased 1 sample [, boot, seed])
fn desc_answer(a: *mem.Arena, k: str, kind: usize, v: []const f64, ex: []const f64) -> f64 {
    let unbiased = ex[0usize] == 0.0f64
    if str.starts_with(k, "d_b") {
        let boot = usize(ex[1usize])
        var r: rng.Rng = zero
        rng.seed(&r, i64(ex[2usize]))
        let (s2, e1) = mem.alloc[f64](a, boot)
        let (kt, e2) = mem.alloc[f64](a, boot)
        if e1 != ok || e2 != ok { os.exit(25) }
        let e3 = fd.descdist_boot(a, &r, v, unbiased, boot, s2, kt)
        if e3 != ok { os.exit(26) }
        if str.eq(k, "d_bs2_first") { ret s2[0usize] }
        if str.eq(k, "d_bs2_last") { ret s2[boot - 1usize] }
        if str.eq(k, "d_bk_first") { ret kt[0usize] }
        ret kt[boot - 1usize]
    }
    var o: [7]f64 = zero
    let e = fd.descdist(a, v, unbiased, o[0usize..7usize])
    if e != ok { os.exit(27) }
    if str.eq(k, "d_min") { ret o[0usize] }
    if str.eq(k, "d_max") { ret o[1usize] }
    if str.eq(k, "d_median") { ret o[2usize] }
    if str.eq(k, "d_mean") { ret o[3usize] }
    if str.eq(k, "d_sd") { ret o[4usize] }
    if str.eq(k, "d_skew") { ret o[5usize] }
    ret o[6usize]
}

// dc_*: the default histogram and the fitted density at the 101 points of denscomp; extras (index)
fn dens_answer(a: *mem.Arena, k: str, kind: usize, v: []const f64, ex: []const f64) -> f64 {
    let (b, cnt, e) = fd.hist_default(a, v)
    if e != ok { os.exit(28) }
    if str.eq(k, "dc_nbreaks") { ret f64(b.len) }
    let i = usize(ex[0usize])
    if str.eq(k, "dc_break") { ret b[i] }
    if str.eq(k, "dc_count") { ret cnt[i] }
    if str.eq(k, "dc_dens") { ret cnt[i] / (f64(v.len) * (b[i + 1usize] - b[i])) }
    let (f, e1) = fd.fit_mle(a, v, kind)
    if e1 != ok { os.exit(29) }
    var lo = v[0usize]
    var hi = v[0usize]
    var j = 0usize
    while j < v.len {
        if v[j] < lo { lo = v[j] }
        if v[j] > hi { hi = v[j] }
        j += 1usize
    }
    ret fd.dens(kind, fd.seq_at(lo, hi, 101usize, i), f.est[0usize..f.np])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fitdist.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var shown: [6]usize = zero
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            let kk = usize(c.args[0usize])
            shown[kk] += 1usize
            if shown[kk] <= 60usize {
                let (initial, builder_error) = str.builder(a, 160usize)
                if builder_error == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    let _ = str.push(&b, " kind ")
                    let _ = str.push_f64(&b, c.args[0usize])
                    let _ = str.push(&b, " n ")
                    let _ = str.push_f64(&b, c.args[1usize])
                    let _ = str.push(&b, ": got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, ", R says ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
