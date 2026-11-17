// e.algo.stat.varsvec (vec2var and SVEC) against vars on a cointegrated system. tests/oracle/vars_vec.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vars_vec`; the case layout is at the top of scripts/r_oracle/groups/vars_vec.R.

use e.algo.rand.r as rng
use e.algo.stat.varschk as ck
use e.algo.stat.vars2 as vr
use e.algo.stat.varsstr as ss
use e.algo.stat.varsvec as vv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

const HORIZON: usize = 6usize

fn gen(a: *mem.Arena, seed: i64, t0: usize, k: usize, y: []f64) {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let e = vr.zeros(a, t0 * k)
    var c = 0usize
    while c < k {
        var t = 0usize
        while t < t0 {
            e[t * k + c] = rng.norm(&rg)
            t += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < k {
        var s = 0.0f64
        var t = 0usize
        while t < t0 {
            s += e[t * k + c]
            y[t * k + c] = s
            t += 1usize
        }
        c += 1usize
    }
    var t = 0usize
    while t < t0 {
        y[t * k + 1usize] = y[t * k] + 0.5f64 * e[t * k + 1usize]
        t += 1usize
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

fn fevd_wsum(fv: []const f64, k: usize, h: usize) -> f64 {
    var s = 0.0f64
    var pos = 0usize
    var i = 0usize
    while i < k {
        var n = 0usize
        while n < h {
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let seed = i64(x[0usize])
    let t0 = usize(x[1usize])
    let k = usize(x[2usize])
    let lag = usize(x[3usize])
    let ecdet = usize(x[4usize])
    let spec = usize(x[5usize])
    let season = usize(x[6usize])
    let r = usize(x[7usize])
    let y = vr.zeros(a, t0 * k)
    gen(a, seed, t0, k, y)
    let (m, me) = vv.vecm_new(a, y, t0, k, lag, ecdet, spec, season)
    if me != ok { os.exit(31) }
    let (xv, xe) = vv.vec2var(a, &m, r)
    if xe != ok { os.exit(32) }
    let nm = c.name
    let blk = (HORIZON + 1usize) * k * k
    if str.starts_with(nm, "v2_") {
        if str.eq(nm, "v2_a") { ret wsum(xv.a) }
        if str.eq(nm, "v2_det") { ret wsum(xv.det) }
        if str.eq(nm, "v2_resid") { ret wsum(xv.v.resid) }
        if str.starts_with(nm, "v2_irf") {
            let b = usize(x[9usize])
            let out = vr.zeros(a, blk)
            if !vv.vec2_irf(a, &xv, HORIZON, b % 2usize == 1usize, b >= 2usize, out) { os.exit(33) }
            ret irf_wsum(out, k, HORIZON)
        }
        if str.eq(nm, "v2_fevd") {
            let fv = vr.zeros(a, HORIZON * k * k)
            if !vv.vec2_fevd(a, &xv, HORIZON, fv) { os.exit(34) }
            ret fevd_wsum(fv, k, HORIZON)
        }
        if str.eq(nm, "v2_fcst") || str.eq(nm, "v2_ci") {
            let fc = vr.zeros(a, HORIZON * k)
            let half = vr.zeros(a, HORIZON * k)
            vv.vec2_predict(a, &xv, HORIZON, x[8usize], fc, half)
            var s = 0.0f64
            var pos = 0usize
            var j = 0usize
            while j < k {
                var n = 0usize
                while n < HORIZON {
                    pos += 1usize
                    if str.eq(nm, "v2_fcst") { s += fc[n * k + j] * f64(pos) } else { s += half[n * k + j] * f64(pos) }
                    n += 1usize
                }
                j += 1usize
            }
            ret s
        }
        let out = vr.zeros(a, 16usize)
        if str.starts_with(nm, "v2_pt") {
            vv.vec2_serial_pt(a, &xv, usize(x[8usize]), out)
            if str.eq(nm, "v2_pt_stat") { ret out[0usize] }
            if str.eq(nm, "v2_pta_stat") { ret out[1usize] }
            if str.eq(nm, "v2_pt_df") { ret out[2usize] }
            ret out[3usize]
        }
        if str.starts_with(nm, "v2_bg") || str.starts_with(nm, "v2_es") {
            if ck.var_serial_bg(a, &xv.v, usize(x[8usize]), out) != ok { os.exit(35) }
            if str.eq(nm, "v2_bg_stat") { ret out[0usize] }
            if str.eq(nm, "v2_bg_p") { ret out[2usize] }
            if str.eq(nm, "v2_es_stat") { ret out[3usize] }
            ret out[6usize]
        }
        if str.starts_with(nm, "v2_archm") {
            if ck.var_arch_multi(a, &xv.v, usize(x[8usize]), out) != ok { os.exit(36) }
            if str.eq(nm, "v2_archm_stat") { ret out[0usize] }
            ret out[2usize]
        }
        if str.starts_with(nm, "v2_jb") {
            if !ck.var_jb_multi(a, &xv.v, out) { os.exit(37) }
            if str.eq(nm, "v2_jb_stat") { ret out[0usize] }
            ret out[2usize]
        }
        if str.starts_with(nm, "v2_boot") {
            let runs = usize(x[8usize])
            let ci = x[9usize]
            let bs = i64(x[10usize])
            let lo = vr.zeros(a, blk)
            let hi = vr.zeros(a, blk)
            let none = vr.zeros(a, 0usize)
            if vv.vec2_irf_boot(a, &m, r, false, none, none, HORIZON, x[11usize] == 1.0f64, x[12usize] == 1.0f64, runs, ci, bs, lo, hi) != ok { os.exit(38) }
            if str.eq(nm, "v2_bootlo") { ret irf_wsum(lo, k, HORIZON) }
            ret irf_wsum(hi, k, HORIZON)
        }
        os.exit(39)
    }
    // SVEC
    let sseed = i64(x[8usize])
    let k2 = k * k
    let lr = x[9usize..9usize + k2]
    let sr = x[9usize + k2..9usize + 2usize * k2]
    let ex = 9usize + 2usize * k2
    var rg: rng.Rng = zero
    rng.seed(&rg, sseed)
    var sf: vv.SvecFit = zero
    let none = vr.zeros(a, 0usize)
    if vv.svec_fit(a, &m, r, lr, sr, none, 100usize, 1.0e-7f64, 1.0f64, &rg, &sf) != ok { os.exit(40) }
    if str.eq(nm, "sv_sr") { ret wsum(sf.sr) }
    if str.eq(nm, "sv_lr") { ret wsum(sf.lr) }
    if str.eq(nm, "sv_sigma") {
        let q = vr.zeros(a, k2)
        var i = 0usize
        while i < k2 {
            q[i] = sf.sigma_u[i] * 100.0f64
            i += 1usize
        }
        ret wsum(q)
    }
    if str.eq(nm, "sv_nres") { ret f64(sf.nres_c1) + 2.0f64 * f64(sf.nres_b) }
    if str.eq(nm, "sv_iter") { ret f64(sf.iter) }
    if str.eq(nm, "sv_lrstat") { ret sf.lr_stat }
    if str.eq(nm, "sv_lrp") { ret sf.lr_p }
    if str.eq(nm, "sv_lrdf") { ret sf.lr_df }
    if str.eq(nm, "sv_irf0") || str.eq(nm, "sv_irf1") {
        let out = vr.zeros(a, blk)
        vv.svec_irf(a, &xv, sf.sr, HORIZON, str.eq(nm, "sv_irf1"), out)
        ret irf_wsum(out, k, HORIZON)
    }
    if str.eq(nm, "sv_fevd") {
        let out = vr.zeros(a, blk)
        vv.svec_irf(a, &xv, sf.sr, HORIZON, false, out)
        let fv = vr.zeros(a, HORIZON * k * k)
        ss.struct_fevd(a, out, k, HORIZON, fv)
        ret fevd_wsum(fv, k, HORIZON)
    }
    if str.starts_with(nm, "sv_boot") {
        let runs = usize(x[ex + 1usize])
        let ci = x[ex + 2usize]
        let bs = i64(x[ex + 3usize])
        let lo = vr.zeros(a, blk)
        let hi = vr.zeros(a, blk)
        if vv.vec2_irf_boot(a, &m, r, true, lr, sr, HORIZON, false, false, runs, ci, bs, lo, hi) != ok { os.exit(41) }
        if str.eq(nm, "sv_bootlo") { ret irf_wsum(lo, k, HORIZON) }
        ret irf_wsum(hi, k, HORIZON)
    }
    os.exit(42)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vars_vec.json")
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
