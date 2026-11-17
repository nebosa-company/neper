// e.algo.stat.vars2 against vars: VAR with every deterministic type, seasonal dummies and exogenous regressors, VARselect, roots, predict, irf with bootstrap
// bands, fevd. tests/oracle/vars_core.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vars_core`; the case layout is at the top of
// scripts/r_oracle/groups/vars_core.R.

use e.algo.rand.r as rng
use e.algo.stat.vars2 as vr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

const HORIZON: usize = 6usize

// y, the exogenous rows and the future exogenous rows the group draws from the seed
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

// sum of x[i] * (i + 1)
fn wsum(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// the weighted sum of irf-shaped blocks [s][response][impulse] in R's order: impulse, horizon, response
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
    let y = vr.zeros(a, t0 * k)
    let exo = vr.zeros(a, t0 * nexo)
    let exof = vr.zeros(a, HORIZON * nexo)
    gen(a, seed, t0, k, nexo, slope, y, exo, exof)
    let nm = c.name
    if str.eq(nm, "aic") || str.eq(nm, "hq") || str.eq(nm, "sc") || str.eq(nm, "fpe") || str.eq(nm, "selection") {
        let lm = usize(x[8usize])
        let crit = vr.zeros(a, 4usize * lm)
        if vr.var_select(a, y, t0, k, lm, det, season, exo, nexo, crit) != ok { os.exit(30) }
        if str.eq(nm, "aic") { ret wsum(crit[0usize..lm]) }
        if str.eq(nm, "hq") { ret wsum(crit[lm..2usize * lm]) }
        if str.eq(nm, "sc") { ret wsum(crit[2usize * lm..3usize * lm]) }
        if str.eq(nm, "fpe") { ret wsum(crit[3usize * lm..4usize * lm]) }
        var s = 0.0f64
        var q = 0usize
        while q < 4usize {
            s += f64(vr.var_selection(crit, lm, q)) * f64(q + 1usize)
            q += 1usize
        }
        ret s
    }
    let (v, ve) = vr.var_new(a, y, t0, k, p, det, season, exo, nexo)
    if ve != ok { os.exit(31) }
    if str.eq(nm, "coef") { ret wsum(v.coef) }
    if str.eq(nm, "resid") { ret wsum(v.resid) }
    if str.eq(nm, "sigma") {
        let sg = vr.var_covres(a, &v)
        // symmetric, so the column-major weights read the same as row-major
        ret wsum(sg)
    }
    if str.eq(nm, "loglik") { ret vr.var_loglik(a, &v) }
    if str.starts_with(nm, "sm_") {
        let eq = usize(x[8usize]) - 1usize
        let so = vr.zeros(a, 8usize)
        let tb = vr.zeros(a, 4usize * v.nz)
        if vr.var_summary_eq(a, &v, eq, so, tb) != ok { os.exit(37) }
        if str.eq(nm, "sm_sigma") { ret so[0usize] }
        if str.eq(nm, "sm_r2") { ret so[1usize] }
        if str.eq(nm, "sm_adj") { ret so[2usize] }
        if str.eq(nm, "sm_f") { ret so[3usize] }
        if str.eq(nm, "sm_fp") { ret so[6usize] }
        var col = 0usize
        if str.eq(nm, "sm_se") { col = 1usize }
        if str.eq(nm, "sm_t") { col = 2usize }
        if str.eq(nm, "sm_p") { col = 3usize }
        var s = 0.0f64
        var j = 0usize
        while j < v.nz {
            s += tb[4usize * j + col] * f64(j + 1usize)
            j += 1usize
        }
        ret s
    }
    if str.eq(nm, "roots") {
        let rt = vr.zeros(a, k * p)
        if vr.var_roots(a, &v, rt) != ok { os.exit(32) }
        ret wsum(rt)
    }
    if str.eq(nm, "fcst") || str.eq(nm, "lower") || str.eq(nm, "upper") || str.eq(nm, "ci") {
        let ci = x[8usize]
        let fc = vr.zeros(a, HORIZON * k)
        let half = vr.zeros(a, HORIZON * k)
        vr.var_predict(a, &v, HORIZON, ci, exof, fc, half)
        // R lists variable by variable, each its HORIZON rows
        var s = 0.0f64
        var pos = 0usize
        var j = 0usize
        while j < k {
            var n = 0usize
            while n < HORIZON {
                pos += 1usize
                var val = fc[n * k + j]
                if str.eq(nm, "lower") { val = fc[n * k + j] - half[n * k + j] }
                if str.eq(nm, "upper") { val = fc[n * k + j] + half[n * k + j] }
                if str.eq(nm, "ci") { val = half[n * k + j] }
                s += val * f64(pos)
                n += 1usize
            }
            j += 1usize
        }
        ret s
    }
    if str.eq(nm, "fevd") {
        let fv = vr.zeros(a, HORIZON * k * k)
        if !vr.var_fevd_r(a, &v, HORIZON, fv) { os.exit(33) }
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
    if str.eq(nm, "irf0") || str.eq(nm, "irf1") || str.eq(nm, "irf2") || str.eq(nm, "irf3") {
        let b = usize(x[9usize])
        let out = vr.zeros(a, (HORIZON + 1usize) * k * k)
        if !vr.var_irf(a, &v, HORIZON, b % 2usize == 1usize, b >= 2usize, out) { os.exit(34) }
        ret irf_wsum(out, k, HORIZON)
    }
    if str.eq(nm, "bootlo") || str.eq(nm, "boothi") {
        let runs = usize(x[9usize])
        let ci = x[10usize]
        let bs = i64(x[11usize])
        let ortho = x[12usize] == 1.0f64
        let cum = x[13usize] == 1.0f64
        let lo = vr.zeros(a, (HORIZON + 1usize) * k * k)
        let hi = vr.zeros(a, (HORIZON + 1usize) * k * k)
        if vr.var_irf_boot(a, &v, HORIZON, ortho, cum, runs, ci, bs, lo, hi) != ok { os.exit(35) }
        if str.eq(nm, "bootlo") { ret irf_wsum(lo, k, HORIZON) }
        ret irf_wsum(hi, k, HORIZON)
    }
    os.exit(36)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vars_core.json")
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
