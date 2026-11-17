// e.algo.stat.varschk and the restrict, BQ and restricted-model parts of e.algo.stat.vars2 against vars. tests/oracle/vars_chk.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vars_chk`; the case layout is at the top of scripts/r_oracle/groups/vars_chk.R.

use e.algo.rand.r as rng
use e.algo.stat.varschk as ck
use e.algo.stat.vars2 as vr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

const HORIZON: usize = 6usize

fn gen(a: *mem.Arena, seed: i64, t0: usize, k: usize, nexo: usize, slope: f64, y: []f64, exo: []f64, exof: []f64) {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let am = vr.zeros(a, k * k)
    var i = 0usize
    while i < k * k {
        am[i] = rng.runif(&rg, 0.0f64 - 0.3f64, 0.3f64)
        i += 1usize
    }
    i = 0usize
    while i < t0 * k {
        y[i] = 0.0f64
        i += 1usize
    }
    var t = 1usize
    while t < t0 {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += am[l * k + j] * y[(t - 1usize) * k + l]
                l += 1usize
            }
            y[t * k + j] = s
            j += 1usize
        }
        j = 0usize
        while j < k {
            y[t * k + j] = y[t * k + j] + rng.norm(&rg)
            j += 1usize
        }
        j = 0usize
        while j < k {
            y[t * k + j] = y[t * k + j] + slope * f64(t + 1usize)
            j += 1usize
        }
        t += 1usize
    }
    var c = 0usize
    while c < nexo {
        t = 0usize
        while t < t0 {
            exo[t * nexo + c] = rng.norm(&rg)
            t += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < nexo {
        t = 0usize
        while t < HORIZON {
            exof[t * nexo + c] = rng.norm(&rg)
            t += 1usize
        }
        c += 1usize
    }
}

fn wsum(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn irf_wsum(x: []const f64, k: usize, h: usize) -> f64 {
    var tot = 0.0f64
    var pos = 0usize
    var imp = 0usize
    while imp < k {
        var s = 0usize
        while s <= h {
            var resp = 0usize
            while resp < k {
                pos += 1usize
                tot += x[s * k * k + resp * k + imp] * f64(pos)
                resp += 1usize
            }
            s += 1usize
        }
        imp += 1usize
    }
    ret tot
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let seed = i64(x[0usize])
    let t0 = usize(x[1usize])
    let k = usize(x[2usize])
    let p = usize(x[3usize])
    let det = usize(x[4usize])
    let season = usize(x[5usize])
    let nexo = usize(x[6usize])
    let slope = x[7usize]
    let nm = c.name
    let y = vr.zeros(a, t0 * k)
    let exo = vr.zeros(a, t0 * nexo)
    let exof = vr.zeros(a, HORIZON * nexo)
    gen(a, seed, t0, k, nexo, slope, y, exo, exof)
    let (v0, ve) = vr.var_new(a, y, t0, k, p, det, season, exo, nexo)
    if ve != ok { os.exit(31) }
    var v = v0
    if str.starts_with(nm, "bq_") {
        let lr = vr.zeros(a, k * k)
        let cim = vr.zeros(a, k * k)
        if !ck.var_bq(a, &v, lr, cim) { os.exit(32) }
        if str.eq(nm, "bq_lrim") { ret wsum(lr) }
        if str.eq(nm, "bq_b") { ret wsum(cim) }
        if str.eq(nm, "bq_sigma") {
            let su = vr.resid_cov(a, v.resid, v.obs, k, vr.eq_df(&v, 0usize))
            var i = 0usize
            while i < k * k {
                su[i] = su[i] * 100.0f64
                i += 1usize
            }
            ret wsum(su)
        }
        // Phi_s B
        let phi = vr.zeros(a, (HORIZON + 1usize) * k * k)
        vr.var_phi_all(&v, HORIZON, phi)
        let out = vr.zeros(a, (HORIZON + 1usize) * k * k)
        var s = 0usize
        while s <= HORIZON {
            let m = vr.mmul(a, phi[s * k * k..(s + 1usize) * k * k], cim, k, k, k)
            var q = 0usize
            while q < k * k {
                out[s * k * k + q] = m[q]
                q += 1usize
            }
            s += 1usize
        }
        ret irf_wsum(out, k, HORIZON)
    }
    let rmode = usize(x[8usize])
    let rpar = x[9usize]
    if rmode == 1usize {
        if vr.var_restrict_ser(a, &v, rpar) != ok { os.exit(33) }
    }
    if rmode == 2usize {
        let rm = vr.zeros(a, k * v.nz)
        var i = 0usize
        while i < k {
            var cc = 0usize
            while cc < v.nz {
                var keep = 1.0f64
                if (i + 1usize + cc + 1usize) % 3usize == usize(rpar) { keep = 0.0f64 }
                rm[i * v.nz + cc] = keep
                cc += 1usize
            }
            i += 1usize
        }
        if vr.var_restrict_manual(a, &v, rm) != ok { os.exit(34) }
    }
    if str.eq(nm, "coef") { ret wsum(v.coef) }
    if str.eq(nm, "resid") { ret wsum(v.resid) }
    if str.eq(nm, "irf0") || str.eq(nm, "irf3") {
        let out = vr.zeros(a, (HORIZON + 1usize) * k * k)
        let b3 = str.eq(nm, "irf3")
        if !vr.var_irf(a, &v, HORIZON, b3, b3, out) { os.exit(35) }
        ret irf_wsum(out, k, HORIZON)
    }
    if str.eq(nm, "fevd") {
        let fv = vr.zeros(a, HORIZON * k * k)
        if !vr.var_fevd_r(a, &v, HORIZON, fv) { os.exit(36) }
        var s = 0.0f64
        var pos = 0usize
        var i = 0usize
        while i < k {
            var n = 0usize
            while n < HORIZON {
                var j = 0usize
                while j < k {
                    pos += 1usize
                    s += fv[n * k * k + i * k + j] * f64(pos)
                    j += 1usize
                }
                n += 1usize
            }
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "fcst") || str.eq(nm, "ci") {
        let fc = vr.zeros(a, HORIZON * k)
        let half = vr.zeros(a, HORIZON * k)
        vr.var_predict(a, &v, HORIZON, 0.95f64, exof, fc, half)
        var s = 0.0f64
        var pos = 0usize
        var j = 0usize
        while j < k {
            var n = 0usize
            while n < HORIZON {
                pos += 1usize
                if str.eq(nm, "fcst") { s += fc[n * k + j] * f64(pos) } else { s += half[n * k + j] * f64(pos) }
                n += 1usize
            }
            j += 1usize
        }
        ret s
    }
    let out = vr.zeros(a, 16usize)
    if str.starts_with(nm, "g_") || str.starts_with(nm, "i_") {
        let cmask = usize(x[10usize])
        var boot = false
        var runs = 0usize
        var bs = 0i64
        if str.eq(nm, "g_pboot") {
            boot = true
            runs = usize(x[11usize])
            bs = i64(x[12usize])
        }
        if ck.var_causality(a, &v, cmask, boot, runs, bs, out) != ok { os.exit(37) }
        if str.eq(nm, "g_f") { ret out[0usize] }
        if str.eq(nm, "g_df1") { ret out[1usize] }
        if str.eq(nm, "g_df2") { ret out[2usize] }
        if str.eq(nm, "g_p") || str.eq(nm, "g_pboot") { ret out[3usize] }
        if str.eq(nm, "i_chi") { ret out[4usize] }
        if str.eq(nm, "i_df") { ret out[5usize] }
        ret out[6usize]
    }
    if str.starts_with(nm, "pt") {
        ck.var_serial_pt(a, &v, usize(x[10usize]), out)
        if str.eq(nm, "pt_stat") { ret out[0usize] }
        if str.eq(nm, "pta_stat") { ret out[1usize] }
        if str.eq(nm, "pt_df") { ret out[2usize] }
        if str.eq(nm, "pt_p") { ret out[3usize] }
        ret out[4usize]
    }
    if str.starts_with(nm, "bg_") || str.starts_with(nm, "es_") {
        if ck.var_serial_bg(a, &v, usize(x[10usize]), out) != ok { os.exit(38) }
        if str.eq(nm, "bg_stat") { ret out[0usize] }
        if str.eq(nm, "bg_df") { ret out[1usize] }
        if str.eq(nm, "bg_p") { ret out[2usize] }
        if str.eq(nm, "es_stat") { ret out[3usize] }
        if str.eq(nm, "es_df2") { ret out[5usize] }
        ret out[6usize]
    }
    if str.starts_with(nm, "archm_") {
        if ck.var_arch_multi(a, &v, usize(x[10usize]), out) != ok { os.exit(39) }
        if str.eq(nm, "archm_stat") { ret out[0usize] }
        if str.eq(nm, "archm_df") { ret out[1usize] }
        ret out[2usize]
    }
    if str.starts_with(nm, "archu_") {
        if ck.var_arch_uni(a, &v, usize(x[11usize]) - 1usize, usize(x[10usize]), out) != ok { os.exit(40) }
        if str.eq(nm, "archu_stat") { ret out[0usize] }
        ret out[2usize]
    }
    if str.starts_with(nm, "jbu_") {
        ck.var_jb_uni(a, &v, usize(x[10usize]) - 1usize, out)
        if str.eq(nm, "jbu_stat") { ret out[0usize] }
        ret out[2usize]
    }
    if str.ends_with(nm, "_stat") || str.ends_with(nm, "_p") {
        if !ck.var_jb_multi(a, &v, out) { os.exit(41) }
        if str.eq(nm, "jb_stat") { ret out[0usize] }
        if str.eq(nm, "jb_p") { ret out[2usize] }
        if str.eq(nm, "sk_stat") { ret out[3usize] }
        if str.eq(nm, "ku_stat") { ret out[6usize] }
        ret out[8usize]
    }
    os.exit(42)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vars_chk.json")
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
