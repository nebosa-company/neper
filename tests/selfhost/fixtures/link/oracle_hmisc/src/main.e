// e.algo.stat.hmisc against Hmisc: binconf, wtd.mean, wtd.var and somers2. tests/oracle/hmisc.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hmisc`; the layout is at the top of
// scripts/r_oracle/groups/hmisc.R.

use e.algo.rand.r as rng
use e.algo.stat.hmisc as hm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "wq") {
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, k)
        if e != ok { ret nan }
        if hm.wtd_quantile(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + k], o) != ok { ret nan }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "scn") || str.eq(c.name, "ssd") || str.eq(c.name, "smh") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 3usize)
        if e != ok { ret nan }
        if str.eq(c.name, "scn") { hm.smean_cl_normal(x[3usize..3usize + n], x[1usize], o) }
        if str.eq(c.name, "ssd") { hm.smean_sdl(x[3usize..3usize + n], x[1usize], o) }
        if str.eq(c.name, "smh") && hm.smedian_hilow(a, x[3usize..3usize + n], x[1usize], o) != ok { ret nan }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "vc") {
        // (n, k, which (0 height, 1 order, 2 merge a, 3 merge b), index, spearman, trans, method, x[n k])
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        let (t, e) = hm.varclus(a, x[7usize..7usize + n * k], n, k, x[4usize] != 0.0f64, usize(x[5usize]), usize(x[6usize]))
        if e != ok { ret nan }
        let ix = usize(x[3usize])
        if x[2usize] == 0.0f64 { ret t.height[ix] }
        if x[2usize] == 1.0f64 { ret f64(t.order[ix]) }
        if x[2usize] == 2.0f64 { ret f64(t.merge_a[ix]) }
        ret f64(t.merge_b[ix])
    }
    if str.eq(c.name, "gmd") { ret hm.gini_md(a, x[1usize..1usize + usize(x[0usize])]) }
    if str.eq(c.name, "info") { ret hm.describe_info(a, x[1usize..1usize + usize(x[0usize])]) }
    if str.eq(c.name, "scb") {
        // (seed, B, conf, which, n, x[n])
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let n = usize(x[4usize])
        let (o, e) = mem.alloc[f64](a, 3usize)
        if e != ok { ret nan }
        if hm.smean_cl_boot(a, &rr, x[5usize..5usize + n], x[2usize], usize(x[1usize]), o) != ok { ret nan }
        ret o[usize(x[3usize])]
    }
    if str.eq(c.name, "red") {
        // (n, p, r2, k, which (0 column removed at step k, 1 its R^2, 2 the number removed), X[n p])
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let (od, e1) = mem.alloc[usize](a, p)
        let (rs, e2) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok { ret nan }
        let cnt = hm.redun_linear(a, x[5usize..5usize + n * p], n, p, x[2usize], od, rs)
        let k = usize(x[3usize])
        if x[4usize] == 2.0f64 { ret f64(cnt) }
        if k >= cnt { ret nan }
        if x[4usize] == 0.0f64 { ret f64(od[k]) }
        ret rs[k]
    }
    if str.eq(c.name, "sp2") {
        // (n, p, which, x[n], y[n])
        let n = usize(x[0usize])
        var o3: [3]f64 = zero
        if hm.spearman2(a, x[3usize..3usize + n], x[3usize + n..3usize + n + n], usize(x[1usize]), o3[0usize..3usize]) != ok { ret nan }
        ret o3[usize(x[2usize])]
    }
    if str.eq(c.name, "sp2f") {
        // (n, ng, which, g[n] 0-based, y[n])
        let n = usize(x[0usize])
        let (gg, ge) = mem.alloc[usize](a, n)
        if ge != ok { ret nan }
        var i = 0usize
        while i < n {
            gg[i] = usize(x[3usize + i])
            i += 1usize
        }
        var o3: [3]f64 = zero
        if hm.spearman2_factor(a, gg, usize(x[1usize]), x[3usize + n..3usize + n + n], o3[0usize..3usize]) != ok { ret nan }
        ret o3[usize(x[2usize])]
    }
    if str.eq(c.name, "bpw") {
        // (p1, p2, n1, n2, alpha)
        ret hm.bpower(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize])
    }
    if str.eq(c.name, "bss") {
        // (p1, p2, fraction, alpha, power, which)
        let (n1, n2) = hm.bsamsize(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize])
        if x[5usize] == 0.0f64 { ret n1 }
        ret n2
    }
    if str.eq(c.name, "ssb") {
        // (alpha, beta, pit, pic, rho)
        ret hm.samplesize_bin(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize])
    }
    if str.eq(c.name, "bal") {
        // (p1, p2, n, alpha, which 0..3)
        var o4: [4]f64 = zero
        hm.ballocation(x[0usize], x[1usize], x[2usize], x[3usize], o4[0usize..4usize])
        ret o4[usize(x[4usize])]
    }
    if str.eq(c.name, "cpw") {
        // (tref, n, mc, r, accrual, tmin, noncomp.c, noncomp.i, alpha)
        ret hm.cpower(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], x[8usize])
    }
    if str.eq(c.name, "cia") {
        // (tref, n1, n2, m1c, m2c, r1, r2, accrual, tmin, alpha)
        ret hm.ciapower(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], x[8usize], x[9usize])
    }
    if str.eq(c.name, "hdq") {
        let n = usize(x[0usize])
        ret hm.hd_quantile(a, x[2usize..2usize + n], x[1usize])
    }
    if str.eq(c.name, "rc") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 2usize)
        if e != ok { ret nan }
        if hm.rcorr_pair(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[1usize] == 1.0f64, o) != ok { ret nan }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "cut") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, usize(x[1usize]) + 2usize)
        if e != ok { ret nan }
        let cnt = hm.cut2_cuts(a, x[3usize..3usize + n], usize(x[1usize]), o)
        if x[2usize] < 0.0f64 { ret f64(cnt) }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "axt") {
        let n = usize(x[0usize])
        ret hm.approx_extrap(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[1usize])
    }
    if str.eq(c.name, "rcc") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 7usize)
        if e != ok { ret nan }
        if usize(x[1usize]) == 7usize { ret hm.rcorr_cens_sd(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[2usize + 2usize * n..2usize + 3usize * n]) }
        hm.rcorr_cens(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[2usize + 2usize * n..2usize + 3usize * n], o)
        ret o[usize(x[1usize])]
    }
    if str.eq(c.name, "wrk") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan }
        if hm.wtd_rank(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], o) != ok { ret nan }
        ret o[usize(x[1usize])]
    }
    if str.eq(c.name, "rcs") {
        let n = usize(x[0usize])
        let nk = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n * (nk - 2usize))
        if e != ok { ret nan }
        hm.rcspline_eval(x[4usize..4usize + n], x[4usize + n..4usize + n + nk], usize(x[2usize]), o)
        ret o[usize(x[3usize])]
    }
    if str.eq(c.name, "bc_lo") || str.eq(c.name, "bc_hi") {
        let (lo, hi) = hm.binconf(x[0usize], x[1usize], x[2usize], u8(x[3usize]))
        if str.eq(c.name, "bc_lo") { ret lo }
        ret hi
    }
    let n = usize(x[0usize])
    if str.eq(c.name, "wmean") { ret hm.wtd_mean(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n]) }
    if str.eq(c.name, "wvar") { ret hm.wtd_var(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n]) }
    let (cc, d) = hm.somers2(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
    if str.eq(c.name, "c") { ret cc }
    ret d
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hmisc.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let start = mem.mark(a)
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
