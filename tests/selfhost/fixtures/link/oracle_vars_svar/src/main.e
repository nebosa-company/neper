// e.algo.stat.varsstr (SVAR by scoring and its impulse responses) against vars. tests/oracle/vars_svar.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vars_svar`; the case layout is at the top of scripts/r_oracle/groups/vars_svar.R.

use e.algo.rand.r as rng
use e.algo.stat.vars2 as vr
use e.algo.stat.varsstr as sv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

const HORIZON: usize = 6usize

fn gen(a: *mem.Arena, seed: i64, t0: usize, k: usize, y: []f64) {
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let seed = i64(x[0usize])
    let t0 = usize(x[1usize])
    let k = usize(x[2usize])
    let p = usize(x[3usize])
    let det = usize(x[4usize])
    let mode = usize(x[5usize])
    let amat = x[6usize..6usize + k * k]
    let bmat = x[6usize + k * k..6usize + 2usize * k * k]
    let ex = 6usize + 2usize * k * k
    let y = vr.zeros(a, t0 * k)
    gen(a, seed, t0, k, y)
    let none = vr.zeros(a, 0usize)
    let (v0, ve) = vr.var_new(a, y, t0, k, p, det, 0usize, none, 0usize)
    if ve != ok { os.exit(31) }
    var v = v0
    var s: sv.Svar = zero
    if sv.svar_fit(a, &v, mode, amat, bmat, none, 100usize, 1.0e-7f64, 1.0f64, &s) != ok { os.exit(32) }
    let nm = c.name
    if str.eq(nm, "sv_a") { ret wsum(s.a) }
    if str.eq(nm, "sv_b") { ret wsum(s.b) }
    if str.eq(nm, "sv_ase") { ret wsum(s.ase) }
    if str.eq(nm, "sv_bse") { ret wsum(s.bse) }
    if str.eq(nm, "sv_sigma") {
        let q = vr.zeros(a, k * k)
        var i = 0usize
        while i < k * k {
            q[i] = s.sigma_u[i] * 100.0f64
            i += 1usize
        }
        ret wsum(q)
    }
    if str.eq(nm, "sv_iter") { ret f64(s.iter) }
    if str.eq(nm, "sv_lr") { ret s.lr_stat }
    if str.eq(nm, "sv_lrp") { ret s.lr_p }
    if str.eq(nm, "sv_lrdf") { ret s.lr_df }
    let out = vr.zeros(a, (HORIZON + 1usize) * k * k)
    if str.eq(nm, "sv_irf0") || str.eq(nm, "sv_irf1") {
        sv.svar_irf(a, &v, s.a, s.b, HORIZON, str.eq(nm, "sv_irf1"), out)
        ret irf_wsum(out, k, HORIZON)
    }
    if str.eq(nm, "sv_fevd") {
        sv.svar_irf(a, &v, s.a, s.b, HORIZON, false, out)
        let fv = vr.zeros(a, HORIZON * k * k)
        sv.struct_fevd(a, out, k, HORIZON, fv)
        var tot = 0.0f64
        var pos = 0usize
        var i = 0usize
        while i < k {
            var n = 0usize
            while n < HORIZON {
                var j = 0usize
                while j < k {
                    pos += 1usize
                    tot += fv[n * k * k + i * k + j] * f64(pos)
                    j += 1usize
                }
                n += 1usize
            }
            i += 1usize
        }
        ret tot
    }
    if str.eq(nm, "sv_bootlo") || str.eq(nm, "sv_boothi") {
        let runs = usize(x[ex + 1usize])
        let ci = x[ex + 2usize]
        let bs = i64(x[ex + 3usize])
        let lo = vr.zeros(a, (HORIZON + 1usize) * k * k)
        let hi = vr.zeros(a, (HORIZON + 1usize) * k * k)
        if sv.svar_irf_boot(a, &v, mode, amat, bmat, none, 100usize, 1.0e-7f64, 1.0f64, HORIZON, false, runs, ci, bs, lo, hi) != ok { os.exit(33) }
        if str.eq(nm, "sv_bootlo") { ret irf_wsum(lo, k, HORIZON) }
        ret irf_wsum(hi, k, HORIZON)
    }
    os.exit(34)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vars_svar.json")
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
