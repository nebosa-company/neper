// e.algo.stat.dharma against DHARMa, part two: tests/oracle/dharma2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dharma2`; the argument layouts are at the top of scripts/r_oracle/groups/dharma2.R.

use e.algo.rand.r as rr
use e.algo.stat.dharma as dh
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

// sum of the simulations times 1 + (7 i + 3 j) mod 11 over the 1-based row i and column j
fn wsum(v: []const f64, rows: usize, cols: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cols {
            s += v[i * cols + j] * f64(1usize + ((i + 1usize) * 7usize + (j + 1usize) * 3usize) % 11usize)
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn posw(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn is_name(k: str, a: str) -> bool { ret str.eq(k, a) }

fn model_case(a: *mem.Arena, k: str, x: []const f64) -> f64 {
    let n = usize(x[0usize])
    let ns = usize(x[1usize])
    let sd = i64(x[2usize])
    let kind = usize(x[3usize])
    let method = usize(x[4usize])
    let integer = x[5usize] != 0.0f64
    let rot = usize(x[6usize])
    let p1 = x[7usize]
    let p2 = x[8usize]
    let obs = x[9usize..9usize + n]
    let mu = x[9usize + n..9usize + 2usize * n]
    let w = x[9usize + 2usize * n..9usize + 3usize * n]
    let extra = x[9usize + 3usize * n..x.len]
    var none: []const f64 = zero
    let (sims, e1) = mem.alloc[f64](a, n * ns)
    if e1 != ok { os.exit(5) }
    var g: rr.Rng = zero
    rr.seed(&g, sd)
    if kind == 1usize { dh.sim_gaussian_lm(&g, mu, p1, p2, none, ns, sims) }
    if kind == 2usize { dh.sim_gaussian_lm(&g, mu, p1, p2, w, ns, sims) }
    if kind == 3usize || kind == 9usize { dh.sim_poisson(&g, mu, ns, sims) }
    if kind == 4usize { dh.sim_binomial(&g, mu, none, ns, 0usize, sims) }
    if kind == 5usize { dh.sim_binomial(&g, mu, w, ns, 0usize, sims) }
    if kind == 6usize { dh.sim_binomial(&g, mu, w, ns, 1usize, sims) }
    if kind == 8usize { dh.sim_gaussian_sd(&g, mu, p1, ns, sims) }
    if kind == 7usize {
        let alpha = dh.gamma_shape(obs, mu, w, p1, p2)
        let (shape, e2) = mem.alloc[f64](a, n)
        if e2 != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            shape[i] = alpha * w[i]
            i += 1usize
        }
        dh.sim_gamma(&g, mu, shape, ns, sims)
    }
    if is_name(k, "sim") { ret wsum(sims, n, ns) }
    let (sr, e3) = mem.alloc[f64](a, n)
    if e3 != ok { os.exit(5) }
    var sigma: []const f64 = zero
    if rot == 2usize { sigma = extra }
    if dh.quantile_g(a, &g, sims, obs, ns, method, integer, rot, sigma, sr) != ok { os.exit(6) }
    if is_name(k, "sr") { ret posw(sr) }
    let nboot = usize(extra[0usize])
    let margin = usize(extra[1usize])
    let alt = usize(extra[2usize])
    var g2: rr.Rng = zero
    rr.seed(&g2, i64(extra[3usize]))
    let (res, e4) = mem.alloc[f64](a, 5usize)
    if e4 != ok { os.exit(5) }
    if dh.outlier_boot(a, &g2, sims, sr, ns, nboot, method, integer, margin, alt, res) != ok { os.exit(7) }
    if is_name(k, "mboot_stat") { ret res[0usize] }
    if is_name(k, "mboot_p") { ret res[1usize] }
    if is_name(k, "mboot_lo") { ret res[2usize] }
    ret res[3usize]
}

fn recalc_case(a: *mem.Arena, k: str, x: []const f64) -> f64 {
    let n = usize(x[0usize])
    let ns = usize(x[1usize])
    let obs = x[3usize..3usize + n]
    let sims = x[3usize + n..3usize + n + n * ns]
    let b = 3usize + n + n * ns
    let s3 = i64(x[b])
    let agg = usize(x[b + 1usize])
    let method = usize(x[b + 2usize])
    let integer = x[b + 3usize] != 0.0f64
    let rot = usize(x[b + 4usize])
    var group: []const f64 = zero
    var at = b + 5usize
    if !str.starts_with(k, "rc_nogroup") {
        group = x[at..at + n]
        at += n
    }
    let sel = x[at..at + n]
    let fitted = x[at + n..at + 2usize * n]
    var sigma: []const f64 = zero
    if rot == 2usize { sigma = x[at + 2usize * n..x.len] }
    let (sr, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(5) }
    let (ao, e2) = mem.alloc[f64](a, n)
    if e2 != ok { os.exit(5) }
    let (af, e3) = mem.alloc[f64](a, n)
    if e3 != ok { os.exit(5) }
    let (asm, e4) = mem.alloc[f64](a, n * ns)
    if e4 != ok { os.exit(5) }
    let (ng, er) = dh.recalc(a, sims, obs, fitted, ns, group, sel, agg, s3, method, integer, rot, sigma, sr, ao, af, asm)
    if er != ok { os.exit(6) }
    if str.ends_with(k, "_ng") { ret f64(ng) }
    if str.ends_with(k, "_sr") { ret posw(sr[0usize..ng]) }
    if str.ends_with(k, "_obs") { ret posw(ao[0usize..ng]) }
    ret wsum(asm[0usize..ng * ns], ng, ns)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if is_name(k, "sim") || is_name(k, "sr") || str.starts_with(k, "mboot_") { ret model_case(a, k, x) }
    if str.starts_with(k, "rc_") { ret recalc_case(a, k, x) }
    if is_name(k, "pc_ratio") || is_name(k, "pc_p") {
        let (ratio, p) = dh.pearson_chisq(x[2usize..x.len], x[0usize], usize(x[1usize]))
        if is_name(k, "pc_ratio") { ret ratio }
        ret p
    }
    let n = usize(x[0usize])
    let ns = usize(x[1usize])
    let seed = i64(x[2usize])
    let obs = x[3usize..3usize + n]
    let sims = x[3usize + n..3usize + n + n * ns]
    let b = 3usize + n + n * ns
    let (sr, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(5) }
    if is_name(k, "q_sr") {
        let method = usize(x[b])
        let integer = x[b + 1usize] != 0.0f64
        let rot = usize(x[b + 2usize])
        var sigma: []const f64 = zero
        if rot == 2usize { sigma = x[b + 3usize..x.len] }
        var g: rr.Rng = zero
        rr.seed(&g, seed)
        if dh.quantile_g(a, &g, sims, obs, ns, method, integer, rot, sigma, sr) != ok { os.exit(6) }
        ret posw(sr)
    }
    if dh.pit(a, sims, obs, ns, seed, sr) != ok { os.exit(6) }
    if is_name(k, "dw_pD") {
        let dw = dh.dw_time(a, sr, x[b..b + n])
        ret dh.dw_pvalue(a, dw, n, usize(x[b + n]))
    }
    if is_name(k, "ksalt_stat") { ret dh.ks_stat_alt(a, sr, usize(x[b])) }
    if is_name(k, "ksalt_p") { ret dh.ks_pvalue_alt(a, sr, usize(x[b])) }
    if is_name(k, "nout_m") || is_name(k, "pout_m") {
        let (cnt, p) = dh.outlier_binomial(sr, ns, usize(x[b]), usize(x[b + 1usize]))
        if is_name(k, "nout_m") { ret f64(cnt) }
        ret p
    }
    if str.starts_with(k, "boot_") {
        var g2: rr.Rng = zero
        rr.seed(&g2, i64(x[b + 3usize]))
        let (res, e2) = mem.alloc[f64](a, 5usize)
        if e2 != ok { os.exit(5) }
        if dh.outlier_boot(a, &g2, sims, sr, ns, usize(x[b]), 0usize, false, usize(x[b + 1usize]), usize(x[b + 2usize]), res) != ok { os.exit(7) }
        if is_name(k, "boot_p") { ret res[1usize] }
        if is_name(k, "boot_lo") { ret res[2usize] }
        ret res[3usize]
    }
    if str.starts_with(k, "cat_") {
        let cat = x[b..b + n]
        let (p, e2) = mem.alloc[f64](a, n)
        if e2 != ok { os.exit(5) }
        let (padj, e3) = mem.alloc[f64](a, n)
        if e3 != ok { os.exit(5) }
        var lev: [2]f64 = zero
        let (ng, er) = dh.test_categorical(a, sr, cat, p, padj, lev[0usize..2usize])
        if er != ok { os.exit(6) }
        if is_name(k, "cat_lev_F") { ret lev[0usize] }
        if is_name(k, "cat_lev_p") { ret lev[1usize] }
        let idx = usize(x[b + n])
        if idx >= ng { ret nan_value() }
        if is_name(k, "cat_p") { ret p[idx] }
        ret padj[idx]
    }
    if str.starts_with(k, "gen_") {
        let kind = usize(x[b + n])
        let alt = usize(x[b + n + 1usize])
        let (summ, e2) = mem.alloc[f64](a, ns)
        if e2 != ok { os.exit(5) }
        let (col, e3) = mem.alloc[f64](a, n)
        if e3 != ok { os.exit(5) }
        var observed = 0.0f64
        var j = 0usize
        while j <= ns {
            var i = 0usize
            while i < n {
                if j < ns { col[i] = sims[i * ns + j] } else { col[i] = obs[i] }
                i += 1usize
            }
            var s = 0.0f64
            if kind == 0usize {
                i = 0usize
                while i < n {
                    s += col[i]
                    i += 1usize
                }
                s = s / f64(n)
            } else if kind == 1usize {
                s = col[0usize]
                i = 1usize
                while i < n {
                    if col[i] > s { s = col[i] }
                    i += 1usize
                }
            } else {
                s = math.sqrt[f64](dh.var_of(col))
            }
            if j < ns { summ[j] = s } else { observed = s }
            j += 1usize
        }
        let (ratio, p) = dh.generic_test(summ, observed, alt)
        if is_name(k, "gen_ratio") { ret ratio }
        ret p
    }
    if is_name(k, "mi_alt_p") {
        let (mo, ms, mp) = dh.moran_full(a, sr, x[b..b + n], x[b + n..b + 2usize * n], x[0usize..0usize], usize(x[b + 2usize * n]))
        ret mp
    }
    if is_name(k, "mi_dm_p") || is_name(k, "mi_dm_obs") {
        let (mo, ms, mp) = dh.moran_full(a, sr, x[0usize..0usize], x[0usize..0usize], x[b..b + n * n], usize(x[b + n * n]))
        if is_name(k, "mi_dm_obs") { ret mo }
        ret mp
    }
    os.exit(9)
    ret nan_value()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dharma2.json")
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
