// e.algo.stat.mumin_fit and mumin_dredge against MuMIn. tests/oracle/mumin_dredge*.json come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mumin_dredge`; the argument layout is at the top of scripts/r_oracle/groups/mumin_dredge.R.

use e.algo.stat.mumin_dredge as md
use e.algo.stat.lmerpkg as lm4
use e.algo.stat.mumin_fit as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// sum(v * seq_along(v)) with NaN as 0
fn ws(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if !mf.is_nan(v[i]) { s += v[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn al(a: *mem.Arena, n: usize) -> []f64 { ret mf.zalloc(a, n) }

fn model_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    let n = usize(x[0usize])
    let nt = usize(x[1usize])
    let fam = u8(usize(x[2usize]))
    let rank = u8(usize(x[3usize]))
    let chat = x[4usize]
    let beta = u8(usize(x[5usize]))
    let mlo = usize(x[6usize])
    let mhi = usize(x[7usize])
    let fixed = u64(x[8usize])
    let cutoff = x[9usize]
    let level = x[10usize]
    let revised = x[11usize] != 0.0f64
    let resp = x[12usize] != 0.0f64
    let sefit = x[13usize] != 0.0f64
    let bt = x[14usize] != 0.0f64
    let n2 = usize(x[15usize])
    let nr = usize(x[16usize])
    let nex = usize(x[17usize])
    let nsel = usize(x[18usize])
    var at = 19usize
    let (rules, re) = mem.alloc[md.Rule](a, nr + 1usize)
    if re != ok { os.exit(20) }
    var i = 0usize
    while i < nr {
        rules[i] = md.Rule { kind: u8(usize(x[at])), m1: u64(x[at + 1usize]), m2: u64(x[at + 2usize]) }
        at += 3usize
        i += 1usize
    }
    let (parents, pe) = mem.alloc[u64](a, nt + 1usize)
    if pe != ok { os.exit(21) }
    i = 0usize
    while i < nt {
        parents[i] = u64(x[at + i])
        i += 1usize
    }
    at += nt
    let (extra, ee) = mem.alloc[u8](a, nex + 1usize)
    if ee != ok { os.exit(22) }
    i = 0usize
    while i < nex {
        extra[i] = u8(usize(x[at + i]))
        i += 1usize
    }
    at += nex
    let (selm, se) = mem.alloc[u64](a, nsel + 1usize)
    if se != ok { os.exit(23) }
    i = 0usize
    while i < nsel {
        selm[i] = u64(x[at + i])
        i += 1usize
    }
    at += nsel
    let y = x[at..at + n]
    at += n
    let q = nt + 1usize
    let xg = al(a, n * q)
    i = 0usize
    while i < n {
        xg[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * nt {
        xg[n + i] = x[at + i]
        i += 1usize
    }
    at += n * nt
    let xn = al(a, n2 * q)
    i = 0usize
    while i < n2 {
        xn[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n2 * nt {
        xn[n2 + i] = x[at + i]
        i += 1usize
    }
    let allmask = (1u64 << u64(nt)) - 1u64
    let none = al(a, 0usize)
    let sp = md.Spec { fam: fam, theta: 1.0f64, wt: none, off: none, altw: none, alto: none }
    let (opts0, oe0) = mem.alloc[md.Opt](a, 1usize)
    let (names0, ne0) = mem.alloc[str](a, 1usize)
    if oe0 != ok || ne0 != ok { os.exit(26) }
    if str.eq(k, "c_cp") || str.eq(k, "c_cp_disp") || str.eq(k, "c_bic") || str.eq(k, "c_aicc") || str.eq(k, "c_qaic") || str.eq(k, "c_qaicc") || str.eq(k, "c_stdsd") || str.eq(k, "c_stdpsd") || str.eq(k, "c_r2m") || str.eq(k, "c_r2c") || str.eq(k, "c_r2n") {
        let m = md.fit_mask(a, xg, n, nt, allmask, y, fam)
        if str.eq(k, "c_cp") { ret mf.crit_cp(&m, mf.nan()) }
        if str.eq(k, "c_cp_disp") { ret mf.crit_cp(&m, 1.7f64) }
        if str.eq(k, "c_bic") { ret mf.ic_of(&m, 2u8, 1.0f64) }
        if str.eq(k, "c_aicc") { ret mf.ic_of(&m, 0u8, 1.0f64) }
        if str.eq(k, "c_qaic") { ret mf.ic_of(&m, 3u8, 1.4f64) }
        if str.eq(k, "c_qaicc") { ret mf.ic_of(&m, 4u8, 1.4f64) }
        if str.eq(k, "c_stdsd") || str.eq(k, "c_stdpsd") {
            let est = al(a, q)
            let sev = al(a, q)
            mf.std_coef(a, &m, y, str.eq(k, "c_stdpsd"), est, sev)
            let both = al(a, 2usize * q)
            i = 0usize
            while i < q {
                both[i] = est[i]
                both[q + i] = sev[i]
                i += 1usize
            }
            ret ws(both)
        }
        let o = al(a, 8usize)
        let rows = mf.r2_fit(a, xg, y, &m, o)
        if str.eq(k, "c_r2n") { ret f64(rows) }
        let v = al(a, rows)
        i = 0usize
        while i < rows {
            if str.eq(k, "c_r2m") { v[i] = o[2usize * i] } else { v[i] = o[2usize * i + 1usize] }
            i += 1usize
        }
        ret ws(v)
    }
    if str.starts_with(k, "s_") {
        let t = md.model_sel(a, xg, n, nt, selm[0usize..nsel], y, &sp, rank, chat, 0u8, extra[0usize..nex])
        if str.eq(k, "s_order") {
            let v = al(a, t.nm)
            i = 0usize
            while i < t.nm {
                v[i] = f64(t.id[i])
                i += 1usize
            }
            ret ws(v)
        }
        if str.eq(k, "s_ic") { ret ws(t.ic) }
        if str.eq(k, "s_delta") { ret ws(t.delta) }
        if str.eq(k, "s_weight") { ret ws(t.weight) }
        ret ws(t.df)
    }
    let t = md.dredge(a, xg, n, nt, y, &sp, opts0[0usize..0usize], 0usize, fixed, mlo, mhi, parents[0usize..nt], rules[0usize..nr], "", names0[0usize..0usize], rank, chat, beta, extra[0usize..nex])
    if str.starts_with(k, "t_") {
        if str.eq(k, "t_id") {
            let v = al(a, t.nm)
            i = 0usize
            while i < t.nm {
                v[i] = f64(t.id[i])
                i += 1usize
            }
            ret ws(v)
        }
        if str.eq(k, "t_df") { ret ws(t.df) }
        if str.eq(k, "t_ll") { ret ws(t.ll) }
        if str.eq(k, "t_ic") { ret ws(t.ic) }
        if str.eq(k, "t_delta") { ret ws(t.delta) }
        if str.eq(k, "t_weight") { ret ws(t.weight) }
        if str.eq(k, "t_est") { ret ws(t.est) }
        if str.eq(k, "t_se") { ret ws(t.se) }
        // t_ex<k>: the k-th extra column
        var e = 0usize
        if str.eq(k, "t_ex2") { e = 1usize }
        if str.eq(k, "t_ex3") { e = 2usize }
        if str.eq(k, "t_ex4") { e = 3usize }
        ret ws(t.extra[e * t.nm..e * t.nm + t.nm])
    }
    let (ri, rie) = mem.alloc[usize](a, t.nm + 1usize)
    if rie != ok { os.exit(24) }
    let cnt = md.rows_delta(&t, cutoff, ri)
    let sel = ri[0usize..cnt]
    var lv = 0.95f64
    if str.eq(k, "a_ci_full") || str.eq(k, "a_ci_cond") { lv = level }
    let av = md.model_avg(a, &t, sel, revised, lv)
    if str.eq(k, "a_w") { ret ws(av.w) }
    if str.eq(k, "a_sw") { ret ws(av.sw[1usize..q]) }
    if str.eq(k, "a_n") { ret ws(av.nmod[1usize..q]) }
    if str.eq(k, "a_coef") {
        let v = al(a, 2usize * q)
        i = 0usize
        while i < q {
            v[i] = av.coef_full[i]
            v[q + i] = av.coef_cond[i]
            i += 1usize
        }
        ret ws(v)
    }
    if str.eq(k, "a_full") || str.eq(k, "a_cond") || str.eq(k, "a_full_nr") || str.eq(k, "a_cond_nr") {
        let v = al(a, 3usize * q)
        var j = 0usize
        while j < q {
            var m = 0usize
            while m < 3usize {
                if str.eq(k, "a_full") || str.eq(k, "a_full_nr") { v[j * 3usize + m] = av.full[j * 5usize + m] } else { v[j * 3usize + m] = av.cond[j * 5usize + m] }
                m += 1usize
            }
            j += 1usize
        }
        ret ws(v)
    }
    if str.eq(k, "a_ci_full") || str.eq(k, "a_ci_cond") {
        let v = al(a, 2usize * q)
        var j = 0usize
        while j < q {
            if str.eq(k, "a_ci_full") {
                v[2usize * j] = av.full[j * 5usize + 3usize]
                v[2usize * j + 1usize] = av.full[j * 5usize + 4usize]
            } else {
                v[2usize * j] = av.cond[j * 5usize + 3usize]
                v[2usize * j + 1usize] = av.cond[j * 5usize + 4usize]
            }
            j += 1usize
        }
        ret ws(v)
    }
    if str.eq(k, "a_vcov_full") || str.eq(k, "a_vcov_cond") {
        let v = al(a, q * q)
        md.avg_vcov(&t, sel, &av, str.eq(k, "a_vcov_full"), v)
        ret ws(v)
    }
    if str.eq(k, "p_coef_full") || str.eq(k, "p_coef_cond") {
        let v = al(a, n2)
        md.predict_coef(&av, xn, n2, str.eq(k, "p_coef_full"), v)
        ret ws(v)
    }
    let pf = al(a, n2)
    let ps = al(a, n2)
    md.predict_models(a, &t, sel, &av, xn, n2, sp.wt[0usize..0usize], fam, resp, sefit, bt, true, pf, ps)
    if str.eq(k, "p_resp_se") || str.eq(k, "p_link_se") || str.eq(k, "p_bt_se") { ret ws(ps) }
    ret ws(pf)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.starts_with(k, "z_") {
        let n = usize(x[0usize])
        let bm = u8(usize(x[1usize]))
        let sdm = x[2usize]
        let kinds = [2]u8{ 0u8, 1u8 }
        let o = al(a, 2usize * n)
        let ce = al(a, 2usize)
        let sc = al(a, 2usize)
        mf.stdize_cols(x[3usize..3usize + 2usize * n], n, 2usize, kinds[0usize..2usize], bm, true, true, sdm, o, ce, sc)
        if str.eq(k, "z_x") { ret ws(o[0usize..n]) }
        if str.eq(k, "z_z") { ret ws(o[n..2usize * n]) }
        if str.eq(k, "z_cx") { ret ws(ce[0usize..1usize]) }
        if str.eq(k, "z_sx") { ret ws(sc[0usize..1usize]) }
        if str.eq(k, "z_cz") { ret ws(ce[1usize..2usize]) }
        ret ws(sc[1usize..2usize])
    }
    if str.eq(k, "lmer_r2m") || str.eq(k, "lmer_r2c") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let ng = usize(x[2usize])
        let (gi, ge) = mem.alloc[usize](a, n + 1usize)
        if ge != ok { os.exit(30) }
        var i = 0usize
        while i < n {
            gi[i] = usize(x[3usize + n * p + i])
            i += 1usize
        }
        let beta = al(a, p)
        let ranef = al(a, ng)
        let out = al(a, 8usize)
        let xm = x[3usize..3usize + n * p]
        if lm4.lmer_ri(a, xm, x[3usize + n * p + n..3usize + n * p + 2usize * n], gi[0usize..n], n, p, ng, true, beta, ranef, out) != ok { os.exit(31) }
        let fit = al(a, n)
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < p {
                s += xm[j * n + i] * beta[j]
                j += 1usize
            }
            fit[i] = s
            i += 1usize
        }
        let v = mf.sample_var_of(fit)
        let rr = al(a, 2usize)
        let _ = mf.r2glmm(0u8, 0u8, v, out[3usize] * out[3usize], out[2usize] * out[2usize], 0.0f64, 0.0f64, 1.0f64, 1.0f64, rr)
        if str.eq(k, "lmer_r2m") { ret rr[0usize] }
        ret rr[1usize]
    }
    if str.eq(k, "qic") || str.eq(k, "qicu") {
        let p = usize(x[0usize])
        let n = usize(x[1usize])
        let cls = u8(usize(x[2usize]))
        let o = al(a, 3usize)
        let base = 5usize
        mf.qic(a, x[base..base + n], x[base + n..base + 2usize * n], x[base + 2usize * n..base + 2usize * n + p * p], x[base + 2usize * n + p * p..base + 2usize * n + 2usize * p * p], p, cls, x[3usize], o)
        if str.eq(k, "qic") { ret o[0usize] }
        ret o[1usize]
    }
    ret model_answer(a, c)
}

fn run(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
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
            if failures <= 60usize {
                let (initial, be) = str.builder(a, 160usize)
                var b = initial
                let _ = str.push(&b, path)
                let _ = str.push(&b, " ")
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " n=")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " fam=")
                let _ = str.push_f64(&b, c.args[2usize])
                let _ = str.push(&b, " rank=")
                let _ = str.push_f64(&b, c.args[3usize])
                let _ = str.push(&b, " beta=")
                let _ = str.push_f64(&b, c.args[5usize])
                let _ = str.push(&b, ": got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, ", R says ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    var failures = run(a, "tests/oracle/mumin_dredge.json")
    failures += run(a, "tests/oracle/mumin_dredge2.json")
    failures += run(a, "tests/oracle/mumin_dredge3.json")
    failures += run(a, "tests/oracle/mumin_dredge4.json")
    failures += run(a, "tests/oracle/mumin_dredge5.json")
    if failures > 0usize { os.exit(1) }
    ret ok
}
