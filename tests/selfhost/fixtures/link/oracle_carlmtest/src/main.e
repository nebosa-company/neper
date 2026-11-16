// e.algo.stat.carlmtest against car, lmtest and sandwich. tests/oracle/carlmtest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R carlmtest`; the layout is at the top of scripts/r_oracle/groups/carlmtest.R.

use e.algo.stat.carlmtest as cl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let y = x[2usize..2usize + n]
    let des = x[2usize + n..2usize + n + n * p]
    let (f, e) = cl.ols(a, des, y, n, p)
    if str.eq(c.name, "cl") {
        let ng = usize(x[2usize + n + n * p])
        let (cid, e5) = mem.alloc[usize](a, n)
        if e5 != ok { os.exit(10) }
        var q = 0usize
        while q < n {
            cid[q] = usize(x[5usize + n + n * p + q])
            q += 1usize
        }
        let (dv1, e6) = mem.alloc[f64](a, p)
        if e6 != ok { os.exit(11) }
        var ty1 = 0usize
        if x[3usize + n + n * p] > 0.5f64 { ty1 = 1usize }
        if cl.vcov_cl_diag(a, des, n, p, &f, cid, ng, ty1, x[4usize + n + n * p] > 0.5f64, dv1) != ok { os.exit(12) }
        var tt = 0.0f64
        q = 0usize
        while q < p {
            tt += dv1[q] * f64(q + 1usize)
            q += 1usize
        }
        ret tt
    }
    if str.eq(c.name, "lh") || str.eq(c.name, "lhp") {
        let q = usize(x[2usize + n + n * p])
        let base = 3usize + n + n * p
        let (hs, hp) = cl.linear_hypothesis(a, des, y, n, p, x[base..base + q * p], x[base + q * p..base + q * p + q], q)
        if c.name.len == 2usize { ret hs }
        ret hp
    }
    if str.eq(c.name, "ncv") || str.eq(c.name, "ncvp") {
        let (ns, np) = cl.ncv_test(a, des, y, n, p)
        if c.name.len == 3usize { ret ns }
        ret np
    }
    if str.eq(c.name, "lev") || str.eq(c.name, "levp") {
        let (ls, lp) = cl.levene_test(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], usize(x[2usize + 2usize * n]), usize(x[3usize + 2usize * n]))
        if c.name.len == 3usize { ret ls }
        ret lp
    }
    if str.eq(c.name, "rain") || str.eq(c.name, "rainp") || str.eq(c.name, "harv") || str.eq(c.name, "harvp") {
        var rs = 0.0f64
        var rp = 0.0f64
        if c.name[0usize] == 114u8 {
            let (s1, p1) = cl.rain_test(a, des, y, n, p)
            rs = s1
            rp = p1
        } else {
            let (s2, p2) = cl.harv_test(a, des, y, n, p)
            rs = s2
            rp = p2
        }
        if c.name.len == 4usize { ret rs }
        ret rp
    }
    if str.eq(c.name, "bg_c") || str.eq(c.name, "bg_cp") || str.eq(c.name, "bg_f") || str.eq(c.name, "bg_fp") {
        var bty = 0usize
        if c.name[3usize] == 102u8 { bty = 1usize }
        let (bs, bpv) = cl.bg_test(a, des, y, n, p, usize(x[2usize + n + n * p]), bty)
        if str.eq(c.name, "bg_c") || str.eq(c.name, "bg_f") { ret bs }
        ret bpv
    }
    if str.eq(c.name, "nw") {
        let (dv0, e0) = mem.alloc[f64](a, p)
        if e0 != ok { os.exit(8) }
        let lg = usize(x[2usize + n + n * p])
        if cl.newey_west_diag(a, des, n, p, &f, lg, x[3usize + n + n * p] > 0.5f64, dv0) != ok { os.exit(9) }
        var tt = 0.0f64
        var q = 0usize
        while q < p {
            tt += dv0[q] * f64(q + 1usize)
            q += 1usize
        }
        ret tt
    }
    if e != ok { os.exit(5) }
    let k = c.name
    if str.eq(k, "dw") { ret cl.durbin_watson(f.resid) }
    if str.eq(k, "bp") { ret cl.bp_studentized(a, des, n, p, f.resid) }
    if str.eq(k, "bpc") { ret cl.bp_test(a, des, n, p, f.resid, false) }
    if str.eq(k, "reset") { ret cl.reset_f(a, des, y, n, p) }
    if str.eq(k, "gq") || str.eq(k, "gqp") {
        let (gqs, d1, d2) = cl.goldfeld_quandt(a, des, y, n, p)
        if str.eq(k, "gq") { ret gqs }
        ret cl.p_f(gqs, d1, d2)
    }
    if str.eq(k, "bpp") { ret cl.p_chisq(cl.bp_studentized(a, des, n, p, f.resid), f64(p - 1usize)) }
    if str.eq(k, "resetp") { ret cl.p_f(cl.reset_f(a, des, y, n, p), 2.0f64, f64(n - p - 2usize)) }
    var s = 0.0f64
    if str.eq(k, "vif") {
        var j = 1usize
        while j < p {
            s += cl.vif(a, des, n, p, j) * f64(j)
            j += 1usize
        }
        ret s
    }
    var ty = 0usize
    if str.eq(k, "hc1") { ty = 1usize }
    if str.eq(k, "hc2") { ty = 2usize }
    if str.eq(k, "hc3") { ty = 3usize }
    if str.eq(k, "hc4") { ty = 4usize }
    let (dv, e2) = mem.alloc[f64](a, p)
    if e2 != ok { os.exit(6) }
    if cl.vcov_hc_diag(a, des, n, p, &f, ty, dv) != ok { os.exit(7) }
    var j = 0usize
    while j < p {
        s += dv[j] * f64(j + 1usize)
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/carlmtest.json")
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
