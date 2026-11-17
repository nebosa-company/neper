// e.algo.stat.mumin_fit / mumin_dredge beyond plain lm and glm (prior weights, offsets, aliased designs, negative binomial, quasi families, varying, subset expressions, mixed-model r2)
// against MuMIn. tests/oracle/mumin_ext*.json come from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mumin_ext`; the argument layout is at the top of
// scripts/r_oracle/groups/mumin_ext.R.

use e.algo.stat.mumin_dredge as md
use e.algo.stat.mumin_fit as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

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

// v (nm rows by nc columns, column-major) with its rows taken in the order perm
fn pm(a: *mem.Arena, v: []const f64, perm: []const f64, nm: usize, nc: usize) -> []f64 {
    let o = al(a, nm * nc)
    var j = 0usize
    while j < nc {
        var r = 0usize
        while r < nm {
            o[j * nm + r] = v[j * nm + usize(perm[r])]
            r += 1usize
        }
        j += 1usize
    }
    ret o
}

fn mixed_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let cls = u8(usize(x[0usize]))
    let link = u8(usize(x[1usize]))
    let n = usize(x[2usize])
    let q = usize(x[3usize])
    let fe = x[8usize..8usize + n]
    let z = x[8usize + n..8usize + n + n * q]
    let sig = x[8usize + n + n * q..8usize + n + n * q + q * q]
    let sig0 = x[8usize + n + n * q + q * q..8usize + n + n * q + 2usize * q * q]
    let out = al(a, 8usize)
    let rows = mf.r2_mixed(cls, link, mf.sample_var_of(fe), mf.var_re_sum(z, sig, n, q), x[6usize], x[7usize], mf.var_re_sum(z, sig0, n, q), x[4usize], x[5usize], out)
    if str.eq(c.name, "gm_n") { ret f64(rows) }
    let v = al(a, rows)
    var i = 0usize
    while i < rows {
        if str.eq(c.name, "gm_m") { v[i] = out[2usize * i] } else { v[i] = out[2usize * i + 1usize] }
        i += 1usize
    }
    ret ws(v)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.starts_with(k, "gm_") { ret mixed_answer(a, c) }
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
    let hasw = x[11usize] != 0.0f64
    let haso = x[12usize] != 0.0f64
    var theta = x[13usize]
    if fam == 10u8 { theta = 0.0f64 }
    let nopts = usize(x[14usize])
    let ndim = usize(x[15usize])
    let naltw = usize(x[16usize])
    let nalto = usize(x[17usize])
    let byid = x[18usize] != 0.0f64
    let n2 = usize(x[19usize])
    let nex = usize(x[20usize])
    var at = 21usize
    let (parents, pe) = mem.alloc[u64](a, nt + 1usize)
    if pe != ok { os.exit(21) }
    var i = 0usize
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
    let (opts, oe) = mem.alloc[md.Opt](a, nopts + 1usize)
    if oe != ok { os.exit(23) }
    i = 0usize
    while i < nopts {
        opts[i] = md.Opt { dim: usize(x[at]), kind: u8(usize(x[at + 1usize])), fam: u8(usize(x[at + 2usize])), theta: x[at + 3usize], arr: usize(x[at + 4usize]) }
        at += 5usize
        i += 1usize
    }
    let wt = x[at..at]
    var wsl = wt
    if hasw {
        wsl = x[at..at + n]
        at += n
    }
    var osl = wt
    if haso {
        osl = x[at..at + n]
        at += n
    }
    let altw = x[at..at + naltw * n]
    at += naltw * n
    let alto = x[at..at + nalto * n]
    at += nalto * n
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
    at += n2 * nt
    var nol = wt
    if haso { nol = x[at..at + n2] }
    let sp = md.Spec { fam: fam, theta: theta, wt: wsl, off: osl, altw: altw, alto: alto }
    let allmask = (1u64 << u64(nt)) - 1u64
    if str.starts_with(k, "c_") {
        let m = md.fit_spec(a, xg, n, nt, allmask, y, &sp)
        if str.eq(k, "c_cp") { ret mf.crit_cp(&m, mf.nan()) }
        if str.eq(k, "c_df") { ret m.npar }
        if str.eq(k, "c_dev") { ret m.dev }
        if str.eq(k, "c_ll") { ret m.ll }
        if str.eq(k, "c_bic") { ret mf.ic_of(&m, 2u8, 1.0f64) }
        if str.eq(k, "c_aicc") { ret mf.ic_of(&m, 0u8, 1.0f64) }
        if str.eq(k, "c_stdsd") {
            let est = al(a, q)
            let sev = al(a, q)
            mf.std_coef(a, &m, y, false, est, sev)
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
    var expr = ""
    if c.inputs.len > 0usize { expr = c.inputs[0usize] }
    var names = c.inputs
    if c.inputs.len > 0usize { names = c.inputs[1usize..c.inputs.len] }
    let t = md.dredge(a, xg, n, nt, y, &sp, opts[0usize..nopts], ndim, fixed, mlo, mhi, parents[0usize..nt], zero_rules(a), expr, names, rank, chat, beta, extra[0usize..nex])
    var perm = al(a, t.nm)
    i = 0usize
    while i < t.nm {
        perm[i] = f64(i)
        i += 1usize
    }
    if byid {
        // rows by MuMIn's row name: ties in the criterion (aliased terms) are ordered by rounding noise
        i = 0usize
        while i < t.nm {
            var j = i
            while j > 0usize && t.id[usize(perm[j - 1usize])] > t.id[usize(perm[j])] {
                let tmp = perm[j]
                perm[j] = perm[j - 1usize]
                perm[j - 1usize] = tmp
                j -= 1usize
            }
            i += 1usize
        }
    }
    if str.starts_with(k, "t_") {
        let nm = t.nm
        if str.eq(k, "t_id") {
            let v = al(a, nm)
            i = 0usize
            while i < nm {
                v[i] = f64(t.id[usize(perm[i])])
                i += 1usize
            }
            ret ws(v)
        }
        if str.eq(k, "t_df") { ret ws(pm(a, t.df, perm, nm, 1usize)) }
        if str.eq(k, "t_ll") { ret ws(pm(a, t.ll, perm, nm, 1usize)) }
        if str.eq(k, "t_ic") { ret ws(pm(a, t.ic, perm, nm, 1usize)) }
        if str.eq(k, "t_delta") { ret ws(pm(a, t.delta, perm, nm, 1usize)) }
        if str.eq(k, "t_weight") { ret ws(pm(a, t.weight, perm, nm, 1usize)) }
        if str.eq(k, "t_est") { ret ws(pm(a, t.est, perm, nm, q)) }
        if str.eq(k, "t_se") { ret ws(pm(a, t.se, perm, nm, q)) }
        if str.starts_with(k, "t_col") {
            let j = usize(k[5usize]) - 48usize
            ret ws(pm(a, t.est[j * nm..j * nm + nm], perm, nm, 1usize))
        }
        var e = 0usize
        if str.eq(k, "t_ex2") { e = 1usize }
        if str.eq(k, "t_ex3") { e = 2usize }
        if str.eq(k, "t_ex4") { e = 3usize }
        ret ws(pm(a, t.extra[e * nm..e * nm + nm], perm, nm, 1usize))
    }
    if str.starts_with(k, "v_") {
        let d = usize(k[2usize]) - 48usize - 1usize
        let v = al(a, t.nm)
        i = 0usize
        while i < t.nm {
            v[i] = f64(t.vv[i * ndim + d])
            i += 1usize
        }
        ret ws(v)
    }
    let (ri, rie) = mem.alloc[usize](a, t.nm + 1usize)
    if rie != ok { os.exit(24) }
    let cnt = md.rows_delta(&t, cutoff, ri)
    let sel = ri[0usize..cnt]
    var lv = 0.95f64
    if str.eq(k, "a_ci_full") { lv = level }
    let av = md.model_avg(a, &t, sel, true, lv)
    if str.eq(k, "a_w") { ret ws(av.w) }
    if str.eq(k, "a_sw") { ret ws(av.sw[1usize..q]) }
    if str.eq(k, "a_full") || str.eq(k, "a_cond") {
        let v = al(a, 3usize * q)
        var j = 0usize
        while j < q {
            var m = 0usize
            while m < 3usize {
                if str.eq(k, "a_full") { v[j * 3usize + m] = av.full[j * 5usize + m] } else { v[j * 3usize + m] = av.cond[j * 5usize + m] }
                m += 1usize
            }
            j += 1usize
        }
        ret ws(v)
    }
    if str.eq(k, "a_ci_full") {
        let v = al(a, 2usize * q)
        var j = 0usize
        while j < q {
            v[2usize * j] = av.full[j * 5usize + 3usize]
            v[2usize * j + 1usize] = av.full[j * 5usize + 4usize]
            j += 1usize
        }
        ret ws(v)
    }
    if str.eq(k, "p_coef_full") {
        let v = al(a, n2)
        md.predict_coef(&av, xn, n2, true, v)
        ret ws(v)
    }
    let pf = al(a, n2)
    let ps = al(a, n2)
    md.predict_models(a, &t, sel, &av, xn, n2, nol, fam, true, true, false, true, pf, ps)
    if str.eq(k, "p_resp_se") { ret ws(ps) }
    ret ws(pf)
}

fn zero_rules(a: *mem.Arena) -> []md.Rule {
    let (r, e) = mem.alloc[md.Rule](a, 1usize)
    if e != ok { os.exit(25) }
    ret r[0usize..0usize]
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
            if failures <= 40usize {
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
    var failures = run(a, "tests/oracle/mumin_ext.json")
    failures += run(a, "tests/oracle/mumin_ext2.json")
    failures += run(a, "tests/oracle/mumin_ext3.json")
    failures += run(a, "tests/oracle/mumin_ext4.json")
    if failures > 0usize { os.exit(1) }
    ret ok
}
